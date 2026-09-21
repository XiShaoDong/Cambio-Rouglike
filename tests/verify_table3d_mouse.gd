extends Node
## headless 回归测试：3D 预览鼠标环视相关的不变量。
## ① _unhandled_input 能收到鼠标移动（否则环视无从触发）；
## ② 满屏默认 STOP 的 Control 不会吞掉鼠标移动（Godot 行为：STOP 不消费 motion）；
## ③ table3d 的 Camera3D 是该 Viewport 的当前相机（否则旋转 rig 不影响画面）；
## ④ look() 确实改变相机朝向，且 yaw 夹在基准 ±90°。

var failures := 0
var checks := 0
var got_motion := false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		got_motion = true

func _ready() -> void:
	await _run()
	print("=== TABLE3D MOUSE RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _push_motion() -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(100, 100)
	ev.relative = Vector2(10, 0)
	get_viewport().push_input(ev)

func _run() -> void:
	await get_tree().process_frame
	# ① 3D 模式下 _unhandled_input 必须能收到鼠标移动
	got_motion = false
	_push_motion()
	await get_tree().process_frame
	_check("无遮挡时 _unhandled_input 收到鼠标移动", got_motion)
	# ② 满屏默认 STOP 的 Control（如 main 的 margin/page）不应吞掉鼠标移动
	var blocker := Control.new()
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(blocker)
	await get_tree().process_frame
	got_motion = false
	_push_motion()
	await get_tree().process_frame
	_check("满屏 STOP Control 仍不吞鼠标移动", got_motion)
	# ③④ 相机为当前相机，且 look() 能改变朝向
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var rig_cam = view.get_node_or_null("CameraRig/PitchPivot/Camera3D")
	_check("table3d 相机存在", rig_cam != null)
	_check("table3d 相机为当前相机", rig_cam != null and get_viewport().get_camera_3d() == rig_cam)
	view.render({
		"viewer_id": 0,
		"players": [
			{"id": 0, "name": "甲", "count": 1, "currency": 0, "health": 2, "slots": [{"card_id": "c1"}]},
			{"id": 1, "name": "乙", "count": 1, "currency": 0, "health": 2, "slots": [{"card_id": "c2"}]},
		],
		"draw_count": 1, "discard": {}, "phase": 2,
	})
	await get_tree().process_frame
	_check("座位取景后相机离开原点", view.camera.position.length() > 1.0)
	var rot_before: Vector3 = view.camera.rotation_degrees
	view.camera.look(Vector2(30.0, 20.0))
	_check("鼠标移动改变相机朝向", view.camera.rotation_degrees != rot_before)
	_check("yaw 夹在基准 ±90°", absf(view.camera.yaw - view.camera.base_yaw) <= 90.001)
