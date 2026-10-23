class_name CameraFlyTool
extends RefCounted
## 3D 开发辅助：自由飞行相机（左下角 WASD + Space/Ctrl）。
## G 开/关；开启时 WASD 前后左右、Space 上升、Ctrl 下降、鼠标环视照常；
## 其它键盘输入被工具模式吞掉（防误触轮盘/手牌/牌序等）。
## 移动以相机朝向为基准：前向 = 相机视线的水平投影（随环视转向）。

const SPEED := 5.0     # 平移 m/s
const VERTICAL := 3.0  # 升降 m/s

var active := false
var _pressed := {}  # keycode -> true

func toggle() -> void:
	active = not active
	if not active:
		reset()

func stop() -> void:
	active = false
	reset()

func reset() -> void:
	_pressed.clear()

## 是否属于本工具的移动键（WASD / Space / Ctrl）。
static func is_move_key(code: Key) -> bool:
	return code == KEY_W or code == KEY_A or code == KEY_S or code == KEY_D \
		or code == KEY_SPACE or code == KEY_CTRL

## 记录按键状态；返回是否由本工具消费该键（G 切换由调用方处理）。
func handle_key(code: Key, pressed: bool) -> bool:
	if not active or not is_move_key(code):
		return false
	if pressed:
		_pressed[code] = true
	else:
		_pressed.erase(code)
	return true

## 每帧按按键集合推进相机全局位移。
func step(delta: float, cam: Camera3D) -> void:
	if not active or cam == null:
		return
	var fwd := -(cam.global_transform.basis.z as Vector3)
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var dir := Vector3.ZERO
	if _pressed.get(KEY_W, false):
		dir += fwd
	if _pressed.get(KEY_S, false):
		dir -= fwd
	if _pressed.get(KEY_D, false):
		dir += right
	if _pressed.get(KEY_A, false):
		dir -= right
	var vert := 0.0
	if _pressed.get(KEY_SPACE, false):
		vert += VERTICAL
	if _pressed.get(KEY_CTRL, false):
		vert -= VERTICAL
	if dir.length_squared() > 0.001:
		dir = dir.normalized()
	cam.global_position += (dir * SPEED + Vector3.UP * vert) * delta
