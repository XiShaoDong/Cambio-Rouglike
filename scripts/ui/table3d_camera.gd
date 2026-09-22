class_name Table3dCamera
extends Node3D
## 3D 预览相机 rig（Milestone 1）
## 结构：CameraRig(yaw, 本节点) → PitchPivot(pitch) → Camera3D。
## 职责：把 rig 摆到某座位并朝桌心，随后由鼠标相对位移驱动 yaw/pitch（夹取）。

const PITCH_LIMIT := 60.0
const YAW_LIMIT := 90.0
const DEFAULT_PITCH := 20.0  # 正=俯视
const EYE_HEIGHT := 1.6
const MOUSE_SENSITIVITY := 0.5  # 度/像素（原 1.0 过快，减半）

var base_yaw := 0.0
var yaw := 0.0
var pitch := DEFAULT_PITCH

var _built := false
var _framed := false
var _framed_angle := 0.0
var _pivot: Node3D
var _camera: Camera3D

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	# 从场景解析（scenes/ui/table3d.tscn）：CameraRig(本节点) → PitchPivot → Camera3D
	_pivot = get_node_or_null("PitchPivot")
	_camera = _pivot.get_node_or_null("Camera3D") if _pivot != null else null
	if _pivot == null or _camera == null:
		push_error("[Table3dCamera] 场景缺少 PitchPivot/Camera3D 节点")

## 相机节点访问器（供射线拾取用）。
func camera_node() -> Camera3D:
	_build()
	return _camera

## 把相机摆到角度 seat_angle_deg 对应的座位后方，基准朝向桌心。
## 座位在圆上角度 a（0°=近侧 +Z），rig +Z 沿径向外，故 -Z（相机视线）朝桌心。
func frame_for_seat(seat_angle_deg: float) -> void:
	_build()
	var a := deg_to_rad(seat_angle_deg)
	var dir := Vector3(sin(a), 0.0, cos(a))
	position = dir * Table3dLayout.SEAT_RADIUS + Vector3(0.0, EYE_HEIGHT, 0.0)
	var new_base := rad_to_deg(atan2(dir.x, dir.z))
	# 同一座位重复 render 时保留用户当前环视，避免视角被复位
	if _framed and is_equal_approx(new_base, _framed_angle):
		return
	_framed = true
	_framed_angle = new_base
	base_yaw = new_base
	yaw = base_yaw
	pitch = DEFAULT_PITCH
	_apply()

## 鼠标相对位移（像素）驱动环视：鼠标右移 → 视角右转（yaw 递减；
## Godot 中 +yaw 为向左转），灵敏度 MOUSE_SENSITIVITY 度/像素。
## yaw 夹在基准 ±YAW_LIMIT，pitch 夹 ±PITCH_LIMIT。
func look(rel: Vector2) -> void:
	yaw = clampf(yaw - rel.x * MOUSE_SENSITIVITY, base_yaw - YAW_LIMIT, base_yaw + YAW_LIMIT)
	pitch = clampf(pitch + rel.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	_apply()

func _apply() -> void:
	if _pivot == null:
		return
	rotation_degrees = Vector3(0.0, yaw, 0.0)
	_pivot.rotation_degrees = Vector3(-pitch, 0.0, 0.0)
