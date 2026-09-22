class_name CardBlock
extends Node3D
## 3D 卡牌方块视图（Milestone 1 只读预览 + Milestone 2 拾取/高亮/瞬时揭示）
## 职责：方块 + Label3D 展示 slot；提供拾取标记、可操作高亮、瞬时揭示。
## 纯展示层：不做规则/隐私判断（已知/未知由快照 slot 是否含 "card" 决定）。

const PROTECTED_COLOR := Color(0.62, 0.35, 0.85)
const BACK_TEXTURE_PATH := "res://assets/Cards/back07.png"

static var _back_tex: Texture2D = null

var _built := false
var _mesh: MeshInstance3D
var _label: Label3D
var _material: StandardMaterial3D
var _area: Area3D
var _pick_shape: CollisionShape3D
var _last_slot: Dictionary = {}
var _actionable := false
var _pick_enabled := true

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	# 卡面用平面（UV 完整 0–1）。BoxMesh 的 UV 是十字展开，顶面只采样一条线 → 贴图被裁。
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Y
	plane.size = Vector2(Table3dLayout.BLOCK_SIZE.x, Table3dLayout.BLOCK_SIZE.z)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	_mesh.mesh = plane
	_material = StandardMaterial3D.new()
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # 两面可见，避免看到背面消失
	_mesh.material_override = _material
	add_child(_mesh)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.0025
	_label.font_size = 96
	_label.position = Vector3(0.0, Table3dLayout.BLOCK_SIZE.y * 0.5 + 0.08, 0.0)
	add_child(_label)
	# 拾取标记：独立物理层，仅用于射线拾取
	_area = Area3D.new()
	_area.name = "PickArea"
	var shape := CollisionShape3D.new()
	var pick_box := BoxShape3D.new()
	pick_box.size = Vector3(Table3dLayout.BLOCK_SIZE.x, Table3dLayout.PICK_HEIGHT, Table3dLayout.BLOCK_SIZE.z)
	shape.shape = pick_box
	_pick_shape = shape
	_area.add_child(shape)
	_area.collision_layer = Table3dLayout.PICK_MASK
	_area.collision_mask = 0
	add_child(_area)

## 设置槽位内容：已知牌显示点数标签；颜色按 protected > actionable > 分类色。
func setup(slot: Dictionary) -> void:
	_build()
	_last_slot = slot
	var card: Dictionary = slot.get("card", {})
	_label.text = "" if card.is_empty() else card_text(card)
	_apply_color()

## 设置拾取元数据（{"kind":"slot","seat":..,"slot":..} 或 hud/deck/...）。
func set_pick(meta: Dictionary) -> void:
	_build()
	_area.set_meta("pick", meta)

func pick_meta() -> Dictionary:
	if _area == null:
		return {}
	return _area.get_meta("pick", {})

## 启用/禁用拾取（隐藏的卡不应被准星命中）。
func set_pick_enabled(on: bool) -> void:
	_build()
	if _pick_shape != null:
		_pick_shape.disabled = not on
	_pick_enabled = on

func is_pick_enabled() -> bool:
	return _pick_enabled

## 可操作高亮（金色）。
func set_actionable(on: bool) -> void:
	_build()
	_actionable = on
	_apply_color()

## 瞬时揭示：临时显示 card 正面；color.a>0 时染该色，否则用牌面分类色。
## 用 restore() 回到最近 setup(slot)。
func reveal(card: Dictionary, color := Color(0, 0, 0, 0)) -> void:
	_build()
	_label.text = card_text(card)
	_material.albedo_texture = null
	_material.albedo_color = color if color.a > 0.0 else Table3dLayout.known_color_for_rank(str(card.get("rank", "")))
	_material.emission_enabled = false

## 回到最近一次 setup(slot) 的状态（标签 + 贴图/颜色）。
func restore() -> void:
	_build()
	setup(_last_slot)

## 短暂染色（不改标签），dur 秒后恢复。
func flash(color: Color, dur: float) -> void:
	_build()
	_material.albedo_texture = null
	_material.albedo_color = color
	_material.emission_enabled = false
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(self):
			_apply_color())

## 未知牌（无 "card"）用现有卡背贴图；已知牌用分类色。发光由 protected/actionable 决定。
func _apply_color() -> void:
	var card: Dictionary = _last_slot.get("card", {})
	if card.is_empty():
		_material.albedo_texture = _back_texture()
		_material.albedo_color = Color.WHITE
	else:
		_material.albedo_texture = null
		_material.albedo_color = Table3dLayout.slot_color(_last_slot)
	_apply_emission()

func _apply_emission() -> void:
	if bool(_last_slot.get("protected", false)):
		_material.emission_enabled = true
		_material.emission = PROTECTED_COLOR
		_material.emission_energy_multiplier = 1.5
	elif _actionable:
		_material.emission_enabled = true
		_material.emission = Table3dLayout.ACTIONABLE_COLOR
		_material.emission_energy_multiplier = 0.6
	else:
		_material.emission_enabled = false

static func _back_texture() -> Texture2D:
	if _back_tex == null:
		_back_tex = load(BACK_TEXTURE_PATH)
	return _back_tex

## 卡片显示文本（"A♥"；Joker 显示 "JOKER"；空卡空串）。
static func card_text(card: Dictionary) -> String:
	if card.is_empty():
		return ""
	var rank := str(card.get("rank", "?"))
	if rank == "JOKER":
		return "JOKER"
	return "%s%s" % [rank, str(card.get("suit", ""))]

func label_text() -> String:
	return _label.text if _label != null else ""

func block_color() -> Color:
	return _material.albedo_color if _material != null else Color.BLACK

func is_emissive() -> bool:
	return _material != null and _material.emission_enabled

func emission_color() -> Color:
	return _material.emission if _material != null else Color.BLACK

## 当前是否使用卡背贴图（未知牌）。
func has_back_texture() -> bool:
	return _material != null and _material.albedo_texture != null
