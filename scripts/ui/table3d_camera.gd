class_name Table3dCamera
extends Node3D
## 3D 预览相机 rig（Milestone 1）
## 结构：CameraRig(yaw, 本节点) → PitchPivot(pitch) → Camera3D。
## 职责：把 rig 摆到某座位并朝桌心，随后由鼠标相对位移驱动 yaw/pitch（夹取）。

const PITCH_LIMIT := 60.0
const YAW_LIMIT := 90.0
@export var EYE_HEIGHT := 2.0
@export var CAMERA_BACK := 1.5  # 相机在座位半径外再后退的距离（多看到桌面）
@export_range(0,1,0.05) var MOUSE_SENSITIVITY := 0.5  # 度/像素（原 1.0 过快，减半）
@export var ZOOM_FOV := 38.0    # 按住 Command/Alt 时拉近后的视场角（越小越放大）
const ZOOM_TIME := 0.18

## 默认俯角：对准桌心（正=俯视）。取景时用，保证准星起始落在桌面上。
static func aim_pitch_deg(eye_height: float, horizontal_distance: float) -> float:
	if horizontal_distance <= 0.001:
		return 0.0
	return clampf(rad_to_deg(atan2(eye_height, horizontal_distance)), -PITCH_LIMIT, PITCH_LIMIT)

var base_yaw := 0.0
var yaw := 0.0
var pitch := 0.0
var zoomed := false  # 是否按住 Command/Alt 拉近视场（供角色等联动，如放大时眼睛换 Eye2）

var _built := false
var _framed := false
var _framed_angle := 0.0
var _pivot: Node3D
var _camera: Camera3D
var _base_fov := 75.0
var _zoom_tween: Tween = null

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
	else:
		_base_fov = _camera.fov

## 相机节点访问器（供射线拾取用）。
func camera_node() -> Camera3D:
	_build()
	return _camera

## 把相机摆到角度 seat_angle_deg 对应的座位后方，基准朝向桌心。
## 座位在圆上角度 a（0°=近侧 +Z），rig +Z 沿径向外，故 -Z（相机视线）朝桌心。
func frame_for_seat(seat_angle_deg: float, target_height := 0.0) -> void:
	_build()
	var a := deg_to_rad(seat_angle_deg)
	var dir := Vector3(sin(a), 0.0, cos(a))
	position = dir * (Table3dLayout.SEAT_RADIUS + CAMERA_BACK) + Vector3(0.0, EYE_HEIGHT, 0.0)
	var new_base := rad_to_deg(atan2(dir.x, dir.z))
	# 同一座位重复 render 时保留用户当前环视，避免视角被复位
	if _framed and is_equal_approx(new_base, _framed_angle):
		return
	_framed = true
	_framed_angle = new_base
	base_yaw = new_base
	yaw = base_yaw
	pitch = aim_pitch_deg(EYE_HEIGHT - target_height, Table3dLayout.SEAT_RADIUS + CAMERA_BACK)
	_apply()

## 鼠标相对位移（像素）驱动环视：鼠标右移 → 视角右转（yaw 递减；
## Godot 中 +yaw 为向左转），灵敏度 MOUSE_SENSITIVITY 度/像素。
## yaw 夹在基准 ±YAW_LIMIT，pitch 夹 ±PITCH_LIMIT。
func look(rel: Vector2) -> void:
	yaw = clampf(yaw - rel.x * MOUSE_SENSITIVITY, base_yaw - YAW_LIMIT, base_yaw + YAW_LIMIT)
	pitch = clampf(pitch + rel.y * MOUSE_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
	_apply()

## 直接把视线对准世界坐标 target（用于自动对准高位看板/按钮，使准星命中）。
## yaw/pitch 仍夹取在基准 ±限制内（不越界）。对不准时至少朝该方向。
func aim_at(target: Vector3) -> void:
	_build()
	var to := target - global_position
	var horiz := Vector2(to.x, to.z).length()
	yaw = clampf(rad_to_deg(atan2(-to.x, -to.z)), base_yaw - YAW_LIMIT, base_yaw + YAW_LIMIT)
	pitch = clampf(rad_to_deg(atan2(-to.y, maxf(horiz, 0.0001))), -PITCH_LIMIT, PITCH_LIMIT)
	_apply()

func _apply() -> void:
	if _pivot == null:
		return
	rotation_degrees = Vector3(0.0, yaw, 0.0)
	_pivot.rotation_degrees = Vector3(-pitch, 0.0, 0.0)

## 按住 Command/Alt 拉近视场（FOV 变小 = 放大）；松开恢复。纯观察者视角，不影响拾取/规则。
func set_zoom(on: bool) -> void:
	_build()
	zoomed = on
	if _camera == null:
		return
	var target := ZOOM_FOV if on else _base_fov
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(_camera, "fov", target, ZOOM_TIME)

## 立即复位视场（退出 3D 等，不播动画）。
func reset_zoom() -> void:
	_build()
	zoomed = false
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = null
	if _camera != null:
		_camera.fov = _base_fov

## 基准视场角（未拉近时的 FOV）。
func base_fov() -> float:
	_build()
	return _base_fov
