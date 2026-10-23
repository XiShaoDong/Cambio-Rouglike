extends Node
## headless 单元测试：飞行相机辅助工具（CameraFlyTool）纯逻辑。

const FlyTool := preload("res://scripts/ui/camera_fly_tool.gd")

var failures := 0
var checks := 0

func _ready() -> void:
	_test_handle()
	_test_step()
	_test_toggle()
	_test_save()
	print("=== CAMERA FLY RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _test_handle() -> void:
	var tool := FlyTool.new()
	_check("默认未激活", not tool.active)
	_check("未激活不消费移动键", not tool.handle_key(KEY_W, true))
	_check("G 不被 handle_key 消费（调用方处理）", not tool.handle_key(KEY_G, true))
	tool.active = true
	_check("激活后 WASD 消费", tool.handle_key(KEY_W, true) and tool.handle_key(KEY_A, true))
	_check("U/J 消费", tool.handle_key(KEY_U, true) and tool.handle_key(KEY_J, false))
	_check("非移动键不消费", not tool.handle_key(KEY_Y, true))
	tool.handle_key(KEY_W, false)
	_check("抬起清除按键", tool.handle_key(KEY_W, false))
	tool.stop()
	_check("stop 后不消费", not tool.handle_key(KEY_D, true))

func _test_step() -> void:
	var tool := FlyTool.new()
	var cam := Camera3D.new()
	add_child(cam)
	# 相机朝 -Z（默认）：按下 W 前进 1s → z 减为 -SPEED
	tool.active = true
	tool.handle_key(KEY_W, true)
	tool.step(1.0, cam)
	_check("W 前进（-Z）", cam.global_position.is_equal_approx(Vector3(0, 0, -FlyTool.SPEED)))
	tool.handle_key(KEY_U, true)
	tool.step(1.0, cam)
	_check("U 上升", cam.global_position.y > 0.0)
	tool.handle_key(KEY_U, false)
	tool.handle_key(KEY_J, true)
	var y_before := cam.global_position.y
	tool.step(1.0, cam)
	_check("J 下降", cam.global_position.y < y_before)
	tool.handle_key(KEY_J, false)
	tool.handle_key(KEY_W, false)
	# 相机朝 -X（看左边）：D 右移应向 +Z
	var basis := Basis(Vector3.UP, deg_to_rad(-90.0))
	cam.global_transform.basis = basis
	tool.handle_key(KEY_D, true)
	var z_before := float(cam.global_position.z)
	tool.step(1.0, cam)
	_check("D 右移随相机朝向", cam.global_position.z > z_before)
	tool.stop()

func _test_toggle() -> void:
	var tool := FlyTool.new()
	tool.active = true
	tool.handle_key(KEY_W, true)
	tool.toggle()
	_check("toggle 关闭并清按键", not tool.active)
	_check("toggle 后不消费", not tool.handle_key(KEY_W, true))
	tool.toggle()
	_check("toggle 再次打开", tool.active)

func _test_save() -> void:
	var tool := FlyTool.new()
	var cam := Camera3D.new()
	add_child(cam)
	_check("初始未保存", not tool.has_saved())
	cam.global_position = Vector3(3, 2, -4)
	cam.rotation_degrees = Vector3(0, 40, 0)
	tool.save_view(cam)
	_check("保存后 has_saved", tool.has_saved())
	cam.global_position = Vector3.ZERO
	cam.global_transform.basis = Basis.IDENTITY
	tool.apply_saved(cam)
	_check("apply 回到保存的姿态", cam.global_position.is_equal_approx(Vector3(3, 2, -4)) \
		and cam.global_transform.basis.get_euler().y > 0.0)
