class_name Table3dCamera
extends Node3D
## 3D 预览相机 rig（Milestone 1）
## 结构：CameraRig(yaw, 本节点) → PitchPivot(pitch) → Camera3D。
## 职责：把 rig 摆到某座位并朝桌心，随后由鼠标相对位移驱动 yaw/pitch（夹取）。

const PITCH_LIMIT := 60.0
const YAW_LIMIT := 90.0
const DEFAULT_PITCH := 20.0  # 正=俯视
const EYE_HEIGHT := 1.6

var base_yaw := 0.0
var yaw := 0.0
var pitch := DEFAULT_PITCH

var _built := false
var _pivot: Node3D
var _camera: Camera3D

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	_pivot = Node3D.new()
	_pivot.name = "PitchPivot"
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_pivot.add_child(_camera)

## 把相机摆到角度 seat_angle_deg 对应的座位后方，基准朝向桌心。
## 座位在圆上角度 a（0°=近侧 +Z），rig +Z 沿径向外，故 -Z（相机视线）朝桌心。
func frame_for_seat(seat_angle_deg: float) -> void:
	_build()
	var a := deg_to_rad(seat_angle_deg)
	var dir := Vector3(sin(a), 0.0, cos(a))
	position = dir * Table3dLayout.SEAT_RADIUS + Vector3(0.0, EYE_HEIGHT, 0.0)
	base_yaw = rad_to_deg(atan2(dir.x, dir.z))
	yaw = base_yaw
	pitch = DEFAULT_PITCH
	_apply()

## 鼠标相对位移（像素）驱动环视：yaw 夹在基准 ±YAW_LIMIT，pitch 夹 ±PITCH_LIMIT。
func look(rel: Vector2) -> void:
	yaw = clampf(yaw + rel.x, base_yaw - YAW_LIMIT, base_yaw + YAW_LIMIT)
	pitch = clampf(pitch + rel.y, -PITCH_LIMIT, PITCH_LIMIT)
	_apply()

func _apply() -> void:
	rotation_degrees = Vector3(0.0, yaw, 0.0)
	_pivot.rotation_degrees = Vector3(-pitch, 0.0, 0.0)
