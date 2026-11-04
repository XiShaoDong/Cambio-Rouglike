class_name AvatarHand
extends Node3D
## 低模机器人右手：手掌 + 四指 + 拇指（BoxMesh 粗模），挂在 hand.R 骨骼上。
## 材质由 RobotAvatar 传入（与机体同色/同光照），不单独持有玩家颜色。

const PALM_SIZE := Vector3(0.14, 0.11, 0.055)
const FINGER_WIDTH := 0.026
const FINGER_LENGTHS := [0.075, 0.09, 0.085, 0.07]
const FINGER_X := [-0.048, -0.016, 0.016, 0.048]

var _meshes: Array[MeshInstance3D] = []


func _ready() -> void:
	_build()


func _build() -> void:
	if not _meshes.is_empty():
		return
	_add_box(PALM_SIZE, Vector3(0.0, PALM_SIZE.y * 0.5, 0.0))
	# 四指从手掌末端继续沿 +Y 伸出（骨骼 +Y = 手臂/手指方向）。
	for i in 4:
		var length: float = FINGER_LENGTHS[i]
		_add_box(Vector3(FINGER_WIDTH, length, 0.03),
			Vector3(FINGER_X[i], PALM_SIZE.y + length * 0.5, 0.0))
	# 拇指：靠掌侧斜向外。
	var thumb := _add_box(Vector3(0.032, 0.085, 0.032), Vector3(-0.088, 0.055, 0.012))
	thumb.rotation_degrees = Vector3(0.0, 0.0, 38.0)


func _add_box(size: Vector3, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	add_child(mi)
	_meshes.append(mi)
	return mi


## 套用与机体相同的材质（含玩家颜色 / 眼神高光）。
func set_material(mat: Material) -> void:
	for mi in _meshes:
		mi.material_override = mat


func mesh_count() -> int:
	return _meshes.size()
