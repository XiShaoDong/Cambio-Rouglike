class_name BellModel
extends Node3D
## Kong 铃铛模型包装：实例化 assets/3Dmodels/call-bell.glb + 按高度分段的金属着色器
## （黑底座 / 金钟体 / 银顶钮）。由 table3d_view 在 _bind 时挂载、隐藏旧场景占位，
## 拾取仍用场景里的 PickArea。纯客户端展示层，零规则/协议改动。

const MODEL_PATH := "res://assets/3Dmodels/call-bell.glb"
const SHADER_PATH := "res://assets/shaders/bell_metal.gdshader"
const SCALE := 0.37                                    # ≈ 旧铃铛尺寸（模型 footprint 1.9 → ~0.70）
const BASE_COLOR := Color(0.02, 0.02, 0.025)           # 黑底座
const DOME_COLOR := Color(0.88, 0.62, 0.20)            # 金钟体
const KNOB_COLOR := Color(0.92, 0.93, 0.96)            # 银顶钮
const BASE_TOP := 0.26                                 # 模型局部 Y：底座上界
const KNOB_BOTTOM := 1.10                              # 模型局部 Y：顶钮下界

var _mat: ShaderMaterial
var _mesh_nodes: Array = []

func _ready() -> void:
	build()

func build() -> void:
	if _mat != null:
		return
	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		push_error("[BellModel] 无法加载 " + MODEL_PATH)
		return
	var model := scene.instantiate()
	model.name = "Model"
	add_child(model)
	scale = Vector3.ONE * SCALE

	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_mat.set_shader_parameter("base_color", BASE_COLOR)
	_mat.set_shader_parameter("dome_color", DOME_COLOR)
	_mat.set_shader_parameter("knob_color", KNOB_COLOR)
	_mat.set_shader_parameter("base_top", BASE_TOP)
	_mat.set_shader_parameter("knob_bottom", KNOB_BOTTOM)
	_mat.set_shader_parameter("glow", 0.0)
	_mesh_nodes = _collect_meshes(model)
	for mi in _mesh_nodes:
		mi.material_override = _mat

func _collect_meshes(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_collect_meshes(c))
	return out

## 可用性辉光（金色 emission；table3d_view 依快照切换）。
func set_glow(on: bool) -> void:
	build()
	if _mat != null:
		_mat.set_shader_parameter("glow", 1.0 if on else 0.0)

func material() -> ShaderMaterial:
	build()
	return _mat

func mesh_count() -> int:
	build()
	return _mesh_nodes.size()

func model_node() -> Node3D:
	build()
	return get_node_or_null("Model")
