extends Node
## headless 单元测试：Robot 鼻子指针（NoseAvatar + RobotAvatar + table3d + 注视同步）。

const NoseAvatarScript := preload("res://scripts/ui/nose_avatar.gd")

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== NOSE RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	await _test_nose_avatar()
	await _test_robot_nose()
	await _test_view_nose()
	_test_game_state_nose()
	await _test_setting()

## 彩蛋开关：设置菜单里的"鼻子点击"开关（默认关闭）。
func _test_setting() -> void:
	var menu = load("res://scripts/ui/settings_menu.gd").new()
	add_child(menu)
	await get_tree().process_frame
	_check("设置菜单有'鼻子点击'开关", menu._nose_check != null)
	_check("开关初值取自 Settings", menu._nose_check.button_pressed == bool(Settings.get_setting("gameplay", "nose_click", false)))
	_check("Loc 有 nose_click 文案", Loc.t("nose_click") != "nose_click")
	menu.queue_free()
	await get_tree().process_frame

## 手动步进 _process 以获得确定性时间。
func _step(nose, seconds: float, dt := 0.1) -> void:
	var t := 0.0
	while t < seconds:
		nose._process(dt)
		t += dt

func _test_nose_avatar() -> void:
	var nose = NoseAvatarScript.new()
	add_child(nose)
	await get_tree().process_frame
	nose.set_process(false)
	_check("初始 IDLE 长度 0", nose.state_name() == "IDLE" and absf(nose.length()) < 0.001)
	nose.set_target(2.0)
	_check("set_target>0 → EXTENDING", nose.state_name() == "EXTENDING")
	_step(nose, NoseAvatarScript.NOSE_DURATION + 0.15)
	_check("到时 → EXTENDED 且长度≈2", nose.state_name() == "EXTENDED" and absf(nose.length() - 2.0) < 0.01)
	nose.set_target(2.0)
	_check("EXTENDED 再设同值不改变状态", nose.state_name() == "EXTENDED")
	nose.set_target(3.0)
	_check("EXTENDED 改目标即时对齐", nose.state_name() == "EXTENDED" and absf(nose.length() - 3.0) < 0.001)
	nose.set_target(0.0)
	_check("set_target(0) → RETRACTING", nose.state_name() == "RETRACTING")
	_step(nose, NoseAvatarScript.NOSE_DURATION + 0.15)
	_check("缩回 → IDLE 长度≈0", nose.state_name() == "IDLE" and absf(nose.length()) < 0.01)
	nose.set_target(0.0)
	_check("IDLE 设 0 无变化", nose.state_name() == "IDLE")
	nose.set_color(Color("3ABA64"))
	_check("set_color 改材质色", nose._mat.albedo_color.is_equal_approx(Color("3ABA64")))
	nose.queue_free()
	await get_tree().process_frame

func _test_robot_nose() -> void:
	var robot := RobotAvatar.new()
	add_child(robot)
	await get_tree().process_frame
	_check("Robot 建立了鼻子", robot._nose != null)
	robot._nose.set_process(false)
	# 目标世界点 = 鼻根 + 前方 2.0 → 鼻子世界长度应为 2.0、鼻尖落在目标点
	var base: Vector3 = robot.nose_base_world().origin
	var fwd: Vector3 = (robot._skeleton.global_transform.basis * Vector3(0, 0, 1)).normalized()
	var target: Vector3 = base + fwd * 2.0
	robot.set_nose_target_world(target)
	robot._update_nose()
	_step(robot._nose, NoseAvatarScript.NOSE_DURATION + 0.15)
	_check("鼻子世界长度≈2.0", absf(robot.nose_length() - 2.0) < 0.06)
	var tip: Vector3 = robot._nose.global_transform * Vector3(0, 0, robot._nose.length())
	_check("鼻尖接近目标点", tip.distance_to(target) < 0.15)
	# 随头：头姿势变化后鼻子位姿随之变化（基随头、鼻尖仍指向目标）
	var t0: Transform3D = robot._nose.transform
	var eye: Vector3 = robot.eye_world_position()
	var left_w: Vector3 = robot._skeleton.global_transform.basis * Vector3(1, 0, 0)
	robot.set_gaze_target_world(eye + left_w * 100.0)
	robot._update_nose()
	var t1: Transform3D = robot._nose.transform
	_check("鼻子随 Head 移动", not t0.origin.is_equal_approx(t1.origin) or not t0.basis.is_equal_approx(t1.basis))
	# 颜色同步
	robot.set_body_color(Color("3ABA64"))
	_check("鼻子随机体色", robot._nose._mat.albedo_color.is_equal_approx(Color("3ABA64")))
	# 关闭 → 缩回
	robot.set_nose_target_world(Vector3.ZERO)
	robot._update_nose()
	_check("关闭 → 缩回", robot._nose.state_name() == "RETRACTING")
	robot.queue_free()
	await get_tree().process_frame

func _test_view_nose() -> void:
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	_check("本机相机鼻子已建立", view._local_nose != null)
	# hovered_card_world = 悬停卡牌节点中心
	view._hover_card = null
	_check("无悬停 → null", view.hovered_card_world() == null)
	var fake := Node3D.new()
	add_child(fake)
	fake.global_position = Vector3(1, 2, 3)
	view._hover_card = fake
	_check("有卡 → 卡中心", (view.hovered_card_world() as Vector3).is_equal_approx(Vector3(1, 2, 3)))
	fake.queue_free()
	view._hover_card = null
	_check("NOSE_PICK_KINDS 不含 hud", not Table3dView.NOSE_PICK_KINDS.has("hud"))
	_check("deck/discard/pending 认可", Table3dView.NOSE_PICK_KINDS.has("deck") and Table3dView.NOSE_PICK_KINDS.has("discard") and Table3dView.NOSE_PICK_KINDS.has("pending"))
	# 本机鼻子瞄准世界目标点
	view.set_local_nose_target_world(Vector3(0, 1.0, 0))
	_check("本机鼻子 EXTENDING", view.local_nose_state_name() == "EXTENDING")
	_step(view._local_nose, NoseAvatarScript.NOSE_DURATION + 0.15)
	_check("本机鼻子长度>0", view.local_nose_length() > 0.5)
	_check("本机鼻根世界位置有效", view.local_nose_base_world().length() > 0.1)
	# 远程下发（世界坐标）
	view.render({
		"viewer_id": 0, "current_player": 1,
		"players": [
			{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2, "slots": [{"card_id": "c1"}]},
			{"id": 1, "name": "乙", "count": 2, "currency": 0, "health": 2, "slots": [{"card_id": "c2"}]},
		],
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 2,
	})
	await get_tree().process_frame
	var robot1 = view._seat_nodes[1].get_node("Avatar").get_node("RobotAvatar")
	robot1._nose.set_process(false)
	var rtarget: Vector3 = robot1.nose_base_world().origin + Vector3(0, 0, 2)
	view.update_noses({1: rtarget}, Vector3.ZERO)
	robot1._update_nose()
	_step(robot1._nose, NoseAvatarScript.NOSE_DURATION + 0.15)
	_check("远程鼻子长度≈2.0（世界）", absf(robot1.nose_length() - 2.0) < 0.1)
	view.clear_local_nose()
	_step(view._local_nose, NoseAvatarScript.NOSE_DURATION + 0.15)
	_check("clear_local_nose 缩回", absf(view.local_nose_length()) < 0.02)
	view.queue_free()
	await get_tree().process_frame

func _test_game_state_nose() -> void:
	GameState.remote_nose.clear()
	GameState._apply_look(1, Vector3(0, 0, 5), true, true, Vector3(1, 2, 3))
	_check("_apply_look 存 nose", (GameState.remote_nose.get(1, Vector3.ZERO) as Vector3).is_equal_approx(Vector3(1, 2, 3)))
	GameState.receive_look(2, Vector3(1, 0, 0), false, false, Vector3(4, 5, 6))
	_check("receive_look 存 nose", (GameState.remote_nose.get(2, Vector3.ZERO) as Vector3).is_equal_approx(Vector3(4, 5, 6)))
	GameState._apply_look(3, Vector3(0, 0, 5), false, false)
	_check("旧 4 参调用向后兼容（nose=ZERO）", (GameState.remote_nose.get(3, Vector3.ONE) as Vector3).is_equal_approx(Vector3.ZERO))
	GameState.remote_looks.clear()
	GameState.remote_zoom.clear()
	GameState.remote_talk.clear()
	GameState.remote_nose.clear()
