class_name Table3dHud
extends Node3D
## 3D 操作面板（Milestone 2）：准星可点的一组扁方块按钮 + Label3D。
## 纯展示 + 拾取标记；动作由 main 处理。

const BUTTON_SIZE := Vector3(1.15, 0.34, 0.05)
const BUTTON_GAP := 0.16
const ENABLED_COLOR := Color(0.30, 0.55, 0.85)
const DISABLED_COLOR := Color(0.22, 0.22, 0.26)

var _buttons: Array = []

## buttons: [{text: String, action: String, enabled: bool}]
func set_buttons(buttons: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons = buttons.duplicate(true)
	var count := _buttons.size()
	for i in count:
		var spec: Dictionary = _buttons[i]
		var holder := Node3D.new()
		holder.name = "HudBtn%d" % i
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var box := BoxMesh.new()
		box.size = BUTTON_SIZE
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ENABLED_COLOR if bool(spec.get("enabled", true)) else DISABLED_COLOR
		mesh.material_override = mat
		holder.add_child(mesh)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.004
		label.font_size = 64
		label.text = str(spec.get("text", ""))
		label.position = Vector3(0.0, 0.0, BUTTON_SIZE.z * 0.5 + 0.02)
		holder.add_child(label)
		var area := Area3D.new()
		area.name = "PickArea"
		var shape := CollisionShape3D.new()
		var pick_box := BoxShape3D.new()
		pick_box.size = BUTTON_SIZE
		shape.shape = pick_box
		area.add_child(shape)
		area.collision_layer = Table3dLayout.PICK_MASK
		area.collision_mask = 0
		area.set_meta("pick", {"kind": "hud", "action": str(spec.get("action", ""))})
		holder.add_child(area)
		holder.position = Vector3(
			(float(i) - (float(count) - 1.0) / 2.0) * (BUTTON_SIZE.x + BUTTON_GAP), 0.0, 0.0)
		add_child(holder)

func button_count() -> int:
	return _buttons.size()

func button_action(index: int) -> String:
	return str(_buttons[index].get("action", ""))

func button_color(index: int) -> Color:
	var mesh: MeshInstance3D = get_child(index).get_node("Mesh")
	return (mesh.material_override as StandardMaterial3D).albedo_color
