class_name RelicBasket
extends Node3D
## 3D 饰品篮（单格）：浅盘 + 占位字符 + 拾取盒；Phase 1 只展示，不处理点击。

const BASE_RADIUS := 0.16
const LABEL_SIZE := 64
const PICK_SIZE := Vector3(0.34, 0.22, 0.34)

var slot := -1
var relic_id := ""
var _label: Label3D
var _highlight: MeshInstance3D
var _base_material: StandardMaterial3D

func setup(p_slot: int, p_relic_id: String) -> void:
	slot = p_slot
	relic_id = p_relic_id
	_ensure_nodes()
	_update_visual()

func relic() -> String:
	return relic_id

func pick_meta() -> Dictionary:
	return {"kind": "relic", "seat": -1, "slot": slot}

func _ensure_nodes() -> void:
	if _label != null:
		return
	var base := MeshInstance3D.new()
	base.name = "Base"
	var mesh := CylinderMesh.new()
	mesh.top_radius = BASE_RADIUS
	mesh.bottom_radius = BASE_RADIUS * 0.86
	mesh.height = 0.03
	mesh.radial_segments = 24
	base.mesh = mesh
	_base_material = StandardMaterial3D.new()
	_base_material.albedo_color = Color(0.12, 0.13, 0.17, 0.92)
	_base_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	base.material_override = _base_material
	base.position.y = 0.015
	add_child(base)

	_highlight = MeshInstance3D.new()
	_highlight.name = "HighlightRing"
	var torus := TorusMesh.new()
	torus.inner_radius = BASE_RADIUS * 0.86
	torus.outer_radius = BASE_RADIUS * 1.14
	torus.rings = 24
	torus.ring_segments = 12
	_highlight.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.95, 0.82, 0.35, 0.9)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.95, 0.82, 0.35)
	ring_mat.emission_energy_multiplier = 1.6
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight.material_override = ring_mat
	_highlight.position.y = 0.035
	_highlight.visible = false
	add_child(_highlight)

	_label = Label3D.new()
	_label.name = "Glyph"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = LABEL_SIZE
	_label.pixel_size = 0.0022
	_label.position = Vector3(0.0, 0.12, 0.0)
	_label.outline_size = 8
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.8)
	add_child(_label)

	var pick := Area3D.new()
	pick.name = "PickArea"
	pick.collision_layer = Table3dLayout.PICK_MASK
	pick.collision_mask = 0
	pick.set_meta("pick", pick_meta())
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = PICK_SIZE
	shape.shape = box
	pick.add_child(shape)
	add_child(pick)

func _update_visual() -> void:
	if _label == null:
		return
	if relic_id.is_empty():
		_label.text = "·"
		_label.modulate = Color(1.0, 1.0, 1.0, 0.35)
		if _base_material != null:
			_base_material.albedo_color = Color(0.12, 0.13, 0.17, 0.55)
		return
	var def := Relics.def_by_id(relic_id)
	_label.text = str(def.get("glyph", "?"))
	var color := Color(0.92, 0.94, 1.0)
	match str(def.get("color", "")):
		"danger": color = Color(0.95, 0.45, 0.45)
		"success": color = Color(0.55, 0.9, 0.6)
		"relic_shield": color = Color(0.69, 0.48, 0.88)
		"accent": color = Color(0.95, 0.82, 0.35)
	_label.modulate = color
	if _base_material != null:
		_base_material.albedo_color = Color(0.12, 0.13, 0.17, 0.92)

func set_highlight(on: bool) -> void:
	if _highlight != null:
		_highlight.visible = on

## 与 Table3dView._apply_hover 的通用接口兼容。
func set_hover(on: bool, _color := Color(1, 1, 1, 1)) -> void:
	set_highlight(on)
