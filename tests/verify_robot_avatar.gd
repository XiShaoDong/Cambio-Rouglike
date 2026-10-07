extends Node
## headless 单元测试：Robot 角色（眼动权重纯函数 + RobotAvatar 包装 + 接入 table3d）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== ROBOT AVATAR RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_math()
	await _test_robot_avatar()
	await _test_integration()
	await _test_shared_world()
	_test_look_sync()

## 座位世界坐标必须与观看者无关（共享世界）——否则同步的世界注视方向会被镜像。
func _test_shared_world() -> void:
	_check("seat_angle 固定(0/1/2/3)", Table3dLayout.seat_angle(0) == 0.0 and Table3dLayout.seat_angle(1) == 270.0 and Table3dLayout.seat_angle(2) == 90.0 and Table3dLayout.seat_angle(3) == 180.0)
	var v = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(v)
	await get_tree().process_frame
	var players := [
		{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2, "slots": [{"card_id": "c1"}]},
		{"id": 1, "name": "乙", "count": 2, "currency": 0, "health": 2, "slots": [{"card_id": "c2"}]},
	]
	var st := {"players": players, "draw_count": 30, "discard": {}, "pending": {}, "phase": 2}
	st["viewer_id"] = 0
	v.render(st)
	await get_tree().process_frame
	var p0_as0: Vector3 = v._seat_node_by_id[0].global_position
	var p1_as0: Vector3 = v._seat_node_by_id[1].global_position
	st["viewer_id"] = 1
	v.render(st)
	await get_tree().process_frame
	var p0_as1: Vector3 = v._seat_node_by_id[0].global_position
	var p1_as1: Vector3 = v._seat_node_by_id[1].global_position
	_check("共享世界：seat0 坐标与观看者无关", p0_as0.is_equal_approx(p0_as1))
	_check("共享世界：seat1 坐标与观看者无关", p1_as0.is_equal_approx(p1_as1))
	_check("共享世界：seat0/seat1 相距确定", p0_as0.distance_to(p1_as0) > 1.0)
	v.queue_free()
	await get_tree().process_frame

func _test_math() -> void:
	# 正前：全 0
	var ahead := RobotAvatarMath.eye_look_weights(Vector3(0, 0, 1))
	var ahead_zero := true
	for k in ahead.keys():
		if absf(float(ahead[k])) > 0.001:
			ahead_zero = false
	_check("正前 → 眼动权重全 0", ahead_zero)
	# 向机器人左侧（+X）：左眼外展 + 右眼内收
	var left := RobotAvatarMath.eye_look_weights(Vector3(1, 0, 1))
	_check("向左看 → OutLeft>0", float(left["eyeLookOutLeft"]) > 0.5)
	_check("向左看 → InRight>0", float(left["eyeLookInRight"]) > 0.5)
	_check("向左看 → 另一对为 0", float(left["eyeLookInLeft"]) == 0.0 and float(left["eyeLookOutRight"]) == 0.0)
	# 向右侧（-X）
	var right := RobotAvatarMath.eye_look_weights(Vector3(-1, 0, 1))
	_check("向右看 → InLeft>0 且 OutRight>0", float(right["eyeLookInLeft"]) > 0.5 and float(right["eyeLookOutRight"]) > 0.5)
	# 上/下
	var up := RobotAvatarMath.eye_look_weights(Vector3(0, 1, 1))
	_check("向上看 → Up.left/right>0", float(up["eyeLookUpLeft"]) > 0.5 and float(up["eyeLookUpRight"]) > 0.5)
	var down := RobotAvatarMath.eye_look_weights(Vector3(0, -1, 1))
	_check("向下看 → Down.left/right>0", float(down["eyeLookDownLeft"]) > 0.5 and float(down["eyeLookDownRight"]) > 0.5)
	# 夹取：极角不超过 1
	var extreme := RobotAvatarMath.eye_look_weights(Vector3(9, 0, 1))
	_check("权重夹取到 1", float(extreme["eyeLookOutLeft"]) == 1.0)
	# 眨眼
	var blink := RobotAvatarMath.blink_weights(2.0)
	_check("眨眼权重夹取到 1", float(blink["eyeBlinkLeft"]) == 1.0 and float(blink["eyeBlinkRight"]) == 1.0)
	# 说话 jawOpen：范围 0..1 且有起伏
	var jmin := 1.0
	var jmax := 0.0
	for k in 80:
		var v := RobotAvatarMath.talk_jaw(float(k) * 0.041)
		jmin = minf(jmin, v)
		jmax = maxf(jmax, v)
	_check("talk_jaw 范围 0..1 且有起伏", jmin >= 0.0 and jmax <= 1.0 and (jmax - jmin) > 0.1)
	# 玩家配色：调色板 8 色、pick_color 避开已用
	_check("调色板 8 色且含默认", KongRules.PLAYER_COLORS.size() == 8 and KongRules.PLAYER_COLORS.has("#496AFE"))
	var only: Array = KongRules.PLAYER_COLORS.duplicate()
	var removed: String = only.pop_back()
	_check("pick_color 避开已用色", KongRules.pick_color(only) == removed)
	_check("pick_color 默认属于调色板", KongRules.PLAYER_COLORS.has(KongRules.pick_color([])))

func _test_robot_avatar() -> void:
	var robot := RobotAvatar.new()
	add_child(robot)
	await get_tree().process_frame
	_check("模型实例化（Robot 子节点）", robot.has_node("Robot"))
	_check("剔除自带 Camera", not robot.has_node("Robot/Camera"))
	_check("剔除自带 Light", not robot.has_node("Robot/Light"))
	_check("解析眼球网格 + 形状键", robot._eyes != null and robot._eye_index.has("eyeLookUpLeft"))
	# 待机手臂姿势：手骨被放低（T-pose 时 hand.L 全局 y≈1.35）
	var hand := robot._skeleton.find_bone("hand.L")
	var hand_y := robot._skeleton.get_bone_global_pose(hand).origin.y
	_check("手臂放下（hand.L 降低）", hand_y < 1.0)
	# overlay 染色
	var mat := StandardMaterial3D.new()
	robot.set_overlay(mat)
	var meshes: Array = []
	robot._collect_meshes(robot._robot, meshes)
	var any_overlay := false
	for m in meshes:
		if (m as MeshInstance3D).material_overlay == mat:
			any_overlay = true
	_check("set_overlay 作用于模型网格", any_overlay and meshes.size() >= 5)
	robot.set_overlay(null)
	# 机体材质（逐实例覆盖，支持每玩家不同色；不改共享素材）
	var arms = robot._robot.get_node("Armature/Skeleton3D/Arms")
	_check("机体默认色金属", robot._body_mat != null and robot._body_mat.albedo_color.is_equal_approx(RobotAvatar.BODY_COLOR) and robot._body_mat.metallic > 0.5)
	_check("机体用逐实例 surface override", arms.get_surface_override_material(0) == robot._body_mat)
	var shared_body_mat = arms.mesh.surface_get_material(0)
	robot.set_body_color(Color("3ABA64"))
	_check("set_body_color 换色", robot._body_mat.albedo_color.is_equal_approx(Color("3ABA64")))
	_check("共享材质未被改动", not shared_body_mat.albedo_color.is_equal_approx(Color("3ABA64")))
	robot.set_body_color(RobotAvatar.BODY_COLOR)
	_check("Tiny_Eyes 形状键存在", robot._eye_index.has("Tiny_Eyes"))
	robot.set_eye_zoom(true)
	_check("放大 → 小眼睛 Tiny_Eyes=1", robot.blend_value("Tiny_Eyes") == 1.0)
	robot.set_eye_zoom(false)
	_check("松开 → 小眼睛归零", robot.blend_value("Tiny_Eyes") == 0.0)
	# 眼球追踪：看向左前 → 左眼外展
	var eye := robot.eye_world_position()
	robot.set_eye_look(eye + Vector3(1, 0, 1))
	_check("set_eye_look 驱动眼动形状键", robot.blend_value("eyeLookOutLeft") > 0.5)
	robot.reset_eyes()
	_check("reset_eyes 归零", robot.blend_value("eyeLookOutLeft") == 0.0)
	# 世界方向直驱（接收他人注视同步）
	robot.set_eye_direction(Vector3(1, 0, 1))
	_check("set_eye_direction 向左", robot.blend_value("eyeLookOutLeft") > 0.5)
	robot.set_eye_direction(Vector3(-1, 0, 1))
	_check("set_eye_direction 换向", robot.blend_value("eyeLookInLeft") > 0.5)
	robot.reset_eyes()
	# VRM Head Tracking：头在限定范围内跟随注视点，眼睛只做相对头的残余（head/eye 独立、不叠加）
	var head_idx := robot._skeleton.find_bone("Head")
	var rest_head: Transform3D = robot._skeleton.get_bone_global_rest(head_idx)
	var sk := robot._skeleton.global_transform
	var eye0 := robot.eye_world_position()
	var fwd_w := sk.basis * Vector3(0, 0, 1)
	var left_w := sk.basis * Vector3(1, 0, 0)
	var t20 := eye0 + (fwd_w * cos(deg_to_rad(20.0)) + left_w * sin(deg_to_rad(20.0))) * 100.0
	robot.set_gaze_target_world(t20)
	var head_pose: Transform3D = robot._skeleton.get_bone_global_pose(head_idx)
	_check("Head Tracking：头随注视点转动", not head_pose.basis.is_equal_approx(rest_head.basis))
	_check("Head Tracking：头吸收后眼睛残余≈0", robot.blend_value("eyeLookOutLeft") < 0.1)
	# 超出头范围（45°）→ 头到上限(30°)，眼睛做剩余(≈15°)
	var t45 := eye0 + (fwd_w * cos(deg_to_rad(45.0)) + left_w * sin(deg_to_rad(45.0))) * 100.0
	robot.set_gaze_target_world(t45)
	_check("Head Tracking：超范围眼睛做剩余", robot.blend_value("eyeLookOutLeft") > 0.3)
	robot.reset_eyes()
	_check("reset_eyes 头回正", robot._skeleton.get_bone_global_pose(head_idx).basis.is_equal_approx(rest_head.basis))
	# 说话：驱动 jawOpen（多正弦开合），停说归零
	_check("存在 jawOpen 目标网格", not robot._jaw_targets.is_empty())
	robot.set_talking(true)
	var jaw_max := 0.0
	for _i in 24:
		await get_tree().process_frame
		jaw_max = maxf(jaw_max, robot.jaw_value())
	_check("说话驱动 jawOpen（有张开）", jaw_max > 0.1)
	robot.set_talking(false)
	_check("停说 jawOpen 归零", robot.jaw_value() == 0.0)
	robot.queue_free()
	await get_tree().process_frame

func _test_integration() -> void:
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var all_have_robot := true
	var placeholders_hidden := true
	for i in 4:
		var avatar = view._seat_nodes[i].get_node_or_null("Avatar")
		if avatar == null or not avatar.has_node("RobotAvatar"):
			all_have_robot = false
		var head = avatar.get_node_or_null("Head") if avatar != null else null
		var body = avatar.get_node_or_null("Body") if avatar != null else null
		if head != null and head.visible:
			placeholders_hidden = false
		if body != null and body.visible:
			placeholders_hidden = false
	_check("每个座位挂载 RobotAvatar", all_have_robot)
	_check("占位 Head/Body 隐藏", placeholders_hidden)
	view.render({
		"viewer_id": 0, "current_player": 1,
		"players": [
			{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2, "color": "#3ABA64", "slots": [{"card_id": "c1"}]},
			{"id": 1, "name": "乙", "count": 2, "currency": 0, "health": 2, "color": "#BD414B", "slots": [{"card_id": "c2"}]},
		],
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 2,
	})
	await get_tree().process_frame
	_check("viewer 自身角色隐藏", not view._seat_nodes[0].get_node("Avatar").visible)
	var robot1 = view._seat_nodes[1].get_node("Avatar").get_node_or_null("RobotAvatar")
	_check("对手机器人可见（当前回合不再染色）", view._seat_nodes[1].get_node("Avatar").visible and robot1 != null and not _robot_has_overlay(robot1))
	_check("快照 color 驱动机体颜色", robot1._body_mat.albedo_color.is_equal_approx(Color.html("#BD414B")))
	# 无同步数据时：稳定看向本机相机（位置固定）→ 转动朝向不应改变眼球（防旧"瞄准点翻转")
	var cam: Camera3D = view.camera.camera_node()
	cam.look_at_from_position(cam.global_position, cam.global_position + Vector3(1, 0, 0), Vector3.UP)
	view.update_avatars(cam)
	var look_a := _eye_snapshot(robot1)
	cam.look_at_from_position(cam.global_position, cam.global_position + Vector3(-1, 0, 0), Vector3.UP)
	view.update_avatars(cam)
	var look_b := _eye_snapshot(robot1)
	_check("无同步时看向本机（不随朝向抖动）", look_a == look_b)
	# 远程注视同步（世界注视点 gaze target）：该席眼睛跟随其“主人”的注视点
	var eye1: Vector3 = robot1.eye_world_position()
	view.update_avatars(cam, {1: eye1 + Vector3(0, 0, 10)})
	var remote_a := _eye_snapshot(robot1)
	view.update_avatars(cam, {1: eye1 + Vector3(10, 0, 0)})
	var remote_b := _eye_snapshot(robot1)
	_check("远程注视点驱动该席眼睛", remote_a != remote_b)
	# 放大联动（远程同步的 zoom → 该席小眼睛）
	view.camera.set_zoom(true)
	_check("相机 zoomed 置位", bool(view.camera.zoomed))
	var robot1b = view._seat_nodes[1].get_node("Avatar").get_node("RobotAvatar")
	view.update_avatars(cam, {1: eye1 + Vector3(0, 0, 10)}, {1: true})
	_check("远程放大同步 → 该席小眼睛", robot1b.blend_value("Tiny_Eyes") == 1.0)
	view.update_avatars(cam, {1: eye1 + Vector3(0, 0, 10)}, {1: false})
	_check("远程未放大 → 小眼睛归零", robot1b.blend_value("Tiny_Eyes") == 0.0)
	view.set_eye_zoom(true)
	_check("View.set_eye_zoom 联动", robot1b.blend_value("Tiny_Eyes") == 1.0)
	view.set_eye_zoom(false)
	view.camera.reset_zoom()
	_check("reset_zoom 清 zoomed", not bool(view.camera.zoomed))
	# 远程说话同步：该席 jawOpen 被驱动
	view.update_avatars(cam, {1: eye1 + Vector3(0, 0, 10)}, {}, false, {1: true})
	var jaw_i := 0.0
	for _i in 16:
		await get_tree().process_frame
		jaw_i = maxf(jaw_i, robot1.jaw_value())
	_check("远程说话同步驱动 jawOpen", jaw_i > 0.1)
	view.update_avatars(cam, {1: eye1 + Vector3(0, 0, 10)}, {}, false, {1: false})
	_check("远程停说 jawOpen 归零", robot1.jaw_value() == 0.0)
	# 连续性：注视方向绕该席"朝向桌心"的前方连续扫动 ±80°，眼球权重不应相邻突变
	var base: Vector3 = Vector3.ZERO - robot1.global_position
	base.y = 0.0
	base = base.normalized()
	var max_jump := 0.0
	var prev: Array = []
	for k in 17:
		var a := deg_to_rad(-80.0 + 10.0 * float(k))
		var d: Vector3 = Basis(Vector3.UP, a) * base
		view.update_avatars(cam, {1: robot1.eye_world_position() + d * 10.0})
		var cur := _eye_snapshot(robot1)
		if not prev.is_empty():
			for i in cur.size():
				max_jump = maxf(max_jump, absf(float(cur[i]) - float(prev[i])))
		prev = cur
	_check("注视方向连续扫动无突变", max_jump < 700.0 and max_jump > 0.0)
	# 出局/离线仍变暗（与回合无关的 overlay 保留）
	view.render({"viewer_id": 0, "current_player": 1, "players": [
		{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 0, "eliminated": true, "slots": [{"card_id": "c1"}]},
		{"id": 1, "name": "乙", "count": 2, "currency": 0, "health": 2, "slots": [{"card_id": "c2"}]},
	], "draw_count": 30, "discard": {}, "pending": {}, "phase": 2})
	await get_tree().process_frame
	var robot0 = view._seat_nodes[0].get_node("Avatar").get_node("RobotAvatar")
	_check("出局角色仍变暗（非回合）", _robot_has_overlay(robot0))
	view.queue_free()
	await get_tree().process_frame

func _test_look_sync() -> void:
	GameState.remote_looks.clear()
	GameState.remote_zoom.clear()
	GameState._apply_look(1, Vector3(0, 0, 5), true, true)
	_check("_apply_look 存储注视点", GameState.remote_looks.has(1) and (GameState.remote_looks[1] as Vector3).is_equal_approx(Vector3(0, 0, 5)))
	_check("_apply_look 存储 zoom", bool(GameState.remote_zoom.get(1, false)))
	_check("_apply_look 存储 talk", bool(GameState.remote_talk.get(1, false)))
	GameState.receive_look(2, Vector3(1, 0, 0), false, false)
	_check("receive_look 存储", GameState.remote_looks.has(2) and not bool(GameState.remote_zoom.get(2, true)))
	GameState._apply_look(3, Vector3(INF, 0, 0), false)
	_check("非有限注视点忽略", not GameState.remote_looks.has(3))
	GameState.remote_looks.clear()
	GameState.remote_zoom.clear()
	GameState.remote_talk.clear()

func _eye_snapshot(robot) -> Array:
	var out: Array = []
	for k in RobotAvatarMath.LOOK_NAMES:
		out.append(round(robot.blend_value(k) * 1000.0))
	return out

func _robot_has_overlay(robot) -> bool:
	var meshes: Array = []
	robot._collect_meshes(robot._robot, meshes)
	for m in meshes:
		if (m as MeshInstance3D).material_overlay != null:
			return true
	return false
