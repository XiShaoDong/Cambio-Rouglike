class_name CardBlock
extends Node3D
## 3D 卡牌方块视图（Milestone 1 只读预览）
## 职责：把快照 slot 投影成一个方块 + 一个 Label3D（显示 rank+suit）。
## 纯展示层：不做规则/隐私判断（slot 是否含 "card" 由快照决定）。

const PROTECTED_COLOR := Color(0.62, 0.35, 0.85)

var _built := false
var _mesh: MeshInstance3D
var _label: Label3D
var _material: StandardMaterial3D

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Table3dLayout.BLOCK_SIZE
	_mesh.mesh = box
	_material = StandardMaterial3D.new()
	_mesh.material_override = _material
	add_child(_mesh)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.0025
	_label.font_size = 96
	_label.position = Vector3(0.0, 0.0, Table3dLayout.BLOCK_SIZE.z * 0.5 + 0.02)
	add_child(_label)

## 设置槽位内容：已知牌显示点数标签 + 分类色；未知牌深灰无标签。
## protected 槽位叠加紫色自发光。
func setup(slot: Dictionary) -> void:
	_build()
	var is_protected := bool(slot.get("protected", false))
	var color := PROTECTED_COLOR if is_protected else Table3dLayout.slot_color(slot)
	_material.albedo_color = color
	_material.emission_enabled = is_protected
	if is_protected:
		_material.emission = color
		_material.emission_energy_multiplier = 1.5
	var card: Dictionary = slot.get("card", {})
	_label.text = "" if card.is_empty() else card_text(card)

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
