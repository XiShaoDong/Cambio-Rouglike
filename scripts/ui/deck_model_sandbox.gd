class_name DeckModelSandbox
extends Node3D
## 抽牌堆模型卡背投影沙盒：加载 DeckCardPile.glb + 套 deck_back_projection 着色器，
## 环视相机 + 实时调参面板（与 CardBlock 单卡背参照对比）。纯展示原型。

const MODEL_PATH := "res://assets/3Dmodels/DeckCardPile.glb"
const SHADER_PATH := "res://assets/shaders/deck_back_projection.gdshader"
const BACK_TEX_PATH := "res://assets/Cards/back07.png"

var camera: Table3dCamera
var model_scale := 0.376  # ≈ Table3dLayout.BLOCK_SIZE.x / 1.86，使牌堆≈一张卡宽
var _config := DeckBackConfig.new()
var _model: Node3D
var _mat: ShaderMaterial
var _ref_card: MeshInstance3D
var _hud: Label

func _ready() -> void:
	_build()
	set_process(true)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build() -> void:
	if _model != null:
		return
	camera = get_node_or_null("CameraRig")
	if camera != null:
		camera.frame_for_seat(0.0)
	var scene := load(MODEL_PATH) as PackedScene
	_model = scene.instantiate()
	_model.name = "DeckModel"
	add_child(_model)
	_model.position = Vector3(0.0, Table3dLayout.TABLE_HEIGHT, 0.0)
	_model.scale = Vector3.ONE * model_scale
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_mat.set_shader_parameter("back_tex", load(BACK_TEX_PATH))
	for mi in _mesh_instances(_model):
		mi.material_override = _mat
	_build_ref_card()
	apply_config(_config)
	_build_ui()

func _mesh_instances(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_mesh_instances(c))
	return out

func _build_ref_card() -> void:
	_ref_card = MeshInstance3D.new()
	_ref_card.name = "RefCard"
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Y
	plane.size = Vector2(Table3dLayout.BLOCK_SIZE.x, Table3dLayout.BLOCK_SIZE.z)
	_ref_card.mesh = plane
	var ref_mat := StandardMaterial3D.new()
	ref_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ref_mat.albedo_texture = load(BACK_TEX_PATH)
	ref_mat.uv1_scale = Vector3(1.0, -1.0, 1.0)
	_ref_card.material_override = ref_mat
	_ref_card.position = Vector3(Table3dLayout.BLOCK_SIZE.x + 0.4, Table3dLayout.TABLE_HEIGHT + 0.002, 0.0)
	add_child(_ref_card)

## 写整份 config 到着色器 uniform。
func apply_config(cfg: DeckBackConfig) -> void:
	_config = cfg
	var d := cfg.to_dict()
	for k in DeckBackConfig.KEYS:
		_mat.set_shader_parameter(k, d[k])

## 改单项参数（配置 + uniform 同步）。
func set_param(name: String, value) -> void:
	var d := _config.to_dict()
	d[name] = value
	var next := DeckBackConfig.new()
	for k in DeckBackConfig.KEYS:
		next.set(k, d[k])
	_config = next
	_mat.set_shader_parameter(name, value)

func model_node() -> Node3D:
	return _model

func material() -> ShaderMaterial:
	return _mat

func config() -> DeckBackConfig:
	return _config

func _process(_delta: float) -> void:
	if _hud == null:
		return
	_hud.text = "scale=%.3f  rotation=%.0f°  ao=%.2f  edge=%.2f" % [
		model_scale, _config.rotation_deg, _config.layer_ao, _config.edge_darken]

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and camera != null:
		camera.look(event.relative)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "Tuner"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-320.0, 8.0)
	panel.custom_minimum_size = Vector2(300.0, 0.0)
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	_add_slider(vb, "project_card_size.x", 0.2, 3.0, _config.project_card_size.x)
	_add_slider(vb, "project_card_size.y", 0.2, 3.0, _config.project_card_size.y)
	_add_slider(vb, "rotation_deg", -180.0, 180.0, _config.rotation_deg)
	_add_slider(vb, "layer_height", 0.002, 0.05, _config.layer_height)
	_add_slider(vb, "layer_offset.x", 0.0, 0.2, _config.layer_offset.x)
	_add_slider(vb, "layer_offset.y", 0.0, 0.2, _config.layer_offset.y)
	_add_slider(vb, "layer_shuffle", 0.0, 5.0, _config.layer_shuffle)
	_add_slider(vb, "layer_ao", 0.0, 1.0, _config.layer_ao)
	_add_slider(vb, "edge_darken", 0.0, 1.0, _config.edge_darken)
	_add_slider(vb, "edge_softness", 0.0, 1.0, _config.edge_softness)
	_add_slider(vb, "model_height", 0.05, 0.6, _config.model_height)
	var row := HBoxContainer.new()
	vb.add_child(row)
	var color := ColorPickerButton.new()
	color.color = _config.tint
	color.custom_minimum_size = Vector2(80.0, 0.0)
	color.color_changed.connect(func(cc): set_param("tint", cc))
	row.add_child(color)
	var tile_cb := CheckBox.new()
	tile_cb.text = "tile"
	tile_cb.button_pressed = _config.tile
	tile_cb.toggled.connect(func(on): set_param("tile", on))
	row.add_child(tile_cb)
	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(func(): _rebuild_defaults())
	row.add_child(reset)
	_hud = Label.new()
	_hud.name = "Hud"
	_hud.position = Vector2(12.0, 8.0)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	layer.add_child(_hud)

func _add_slider(parent: Control, param: String, lo: float, hi: float, value: float) -> void:
	var lbl := Label.new()
	lbl.text = "%s = %.3f" % [param, value]
	parent.add_child(lbl)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 200.0
	s.value = value
	s.value_changed.connect(func(v):
		lbl.text = "%s = %.3f" % [param, v]
		_apply_nested(param, v))
	parent.add_child(s)

func _apply_nested(param: String, value: float) -> void:
	if param.ends_with(".x") or param.ends_with(".y"):
		var base := param.substr(0, param.length() - 2)
		var vec := _config.get(base) as Vector2
		if param.ends_with(".x"):
			vec.x = value
		else:
			vec.y = value
		set_param(base, vec)
	else:
		set_param(param, value)

func _rebuild_defaults() -> void:
	apply_config(DeckBackConfig.new())
