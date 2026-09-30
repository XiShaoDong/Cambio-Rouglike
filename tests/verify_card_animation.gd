extends Node
## headless 单元测试：卡牌交互动效（配置 / 纯数学 / 控制器 / 沙盒）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== CARD ANIMATION RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_config()
	_test_state_machine()
	_test_easing()
	_test_height_shadow_compose()
	_test_show_back()
	_test_bend()
	await _test_controller()
	await _test_sandbox()

func _test_config() -> void:
	var c := CardAnimationConfig.new()
	_check("config 默认值合法", c.validate().is_empty())
	_check("config to_dict 键数", c.to_dict().size() == CardAnimationConfig.KEYS.size())
	_check("config 默认 hover_lift", is_equal_approx(c.hover_lift, 0.12))
	_check("config 默认 hover_clearance", is_equal_approx(c.hover_clearance, 0.03))
	var bad := CardAnimationConfig.new()
	bad.hover_lift = -1.0
	_check("config 非法值被抓", bad.validate().has("hover_lift"))

func _test_state_machine() -> void:
	var M := CardAnimationMath
	_check("IDLE + enter → HOVER", M.next_state(M.IDLE, M.EV_ENTER, true, false, false) == M.HOVER)
	_check("IDLE + click 无效", M.next_state(M.IDLE, M.EV_CLICK, false, false, false) == M.IDLE)
	_check("HOVER + exit → IDLE", M.next_state(M.HOVER, M.EV_EXIT, false, false, false) == M.IDLE)
	_check("HOVER + click → PRESS", M.next_state(M.HOVER, M.EV_CLICK, true, false, false) == M.PRESS)
	_check("PRESS + exit 不中断", M.next_state(M.PRESS, M.EV_EXIT, false, false, false) == M.PRESS)
	_check("PRESS + timer → FLIP", M.next_state(M.PRESS, M.EV_TIMER, true, false, false) == M.FLIP)
	_check("FLIP + click 无效", M.next_state(M.FLIP, M.EV_CLICK, true, false, false) == M.FLIP)
	_check("FLIP + timer 未完成仍 FLIP", M.next_state(M.FLIP, M.EV_TIMER, true, false, false) == M.FLIP)
	_check("FLIP + timer 完成 → LAND", M.next_state(M.FLIP, M.EV_TIMER, true, true, false) == M.LAND)
	_check("LAND + timer 完成且悬停 → HOVER", M.next_state(M.LAND, M.EV_TIMER, true, true, true) == M.HOVER)
	_check("LAND + timer 完成且未悬停 → IDLE", M.next_state(M.LAND, M.EV_TIMER, false, true, true) == M.IDLE)

func _test_easing() -> void:
	var M := CardAnimationMath
	_check("ease_out_cubic 端点", is_equal_approx(M.ease_out_cubic(0.0), 0.0) and is_equal_approx(M.ease_out_cubic(1.0), 1.0))
	_check("ease_out_cubic 单调", M.ease_out_cubic(0.3) < M.ease_out_cubic(0.6))
	_check("ease_in_out_cubic 端点", is_equal_approx(M.ease_in_out_cubic(0.0), 0.0) and is_equal_approx(M.ease_in_out_cubic(1.0), 1.0))
	_check("ease_out_back 端点", is_equal_approx(M.ease_out_back(0.0), 0.0) and is_equal_approx(M.ease_out_back(1.0), 1.0))
	_check("ease_out_back 过冲", M.ease_out_back(0.7) > 1.0)
	_check("lerp_f 中点", is_equal_approx(M.lerp_f(0.0, 10.0, 0.5), 5.0))

func _test_height_shadow_compose() -> void:
	var M := CardAnimationMath
	var cd := CardAnimationConfig.new().to_dict()
	_check("height t=0 ≈0", absf(M.height({"hover": 0.0, "flip": 0.0}, cd, 0.0)) < 0.0001)
	_check("height hover=1 抑制 idle", is_equal_approx(M.height({"hover": 1.0, "flip": 0.0}, cd, 1.0), cd["hover_lift"]))
	_check("height flip=0.5 峰值", is_equal_approx(M.height({"hover": 0.0, "flip": 0.5}, cd, 0.0), cd["flip_lift"]))
	_check("shadow h=0 scale=1", is_equal_approx(M.shadow_scale_for(0.0, cd), 1.0))
	_check("shadow h=0 alpha=base", is_equal_approx(M.shadow_alpha_for(0.0, cd), cd["shadow_base_alpha"]))
	var maxh: float = cd["hover_lift"] + cd["flip_lift"]
	_check("shadow h=max scale", is_equal_approx(M.shadow_scale_for(maxh, cd), 1.0 - cd["shadow_scale_loss"]))
	_check("shadow h=max alpha", is_equal_approx(M.shadow_alpha_for(maxh, cd), cd["shadow_base_alpha"] * (1.0 - cd["shadow_alpha_loss"])))
	_check("press 0 → 1", is_equal_approx(M.press_scale(0.0, cd), 1.0))
	_check("press 1 → 1", is_equal_approx(M.press_scale(1.0, cd), 1.0))
	_check("press 三段最低 ≈ min", M.press_scale(0.33, cd) <= cd["press_min"] + 0.001)
	_check("press 三段过冲 ≈ over", M.press_scale(0.66, cd) >= cd["press_over"] - 0.001)
	_check("land 0 → 1", is_equal_approx(M.land_scale(0.0, cd), 1.0))
	_check("land 1 → 1", is_equal_approx(M.land_scale(1.0, cd), 1.0))
	var c := M.compose({"hover": 1.0, "press": 0.0, "flip": 0.0, "land": 0.0}, cd, 0.0, Vector2.ZERO)
	var half_len: float = Table3dLayout.BLOCK_SIZE.z * 0.5 * cd["hover_scale"]
	var comp: float = maxf(cd["hover_lift"], cd["hover_clearance"] + half_len * sin(deg_to_rad(cd["hover_pitch"])))
	_check("compose hover 位移=离桌补偿", is_equal_approx((c["visual_pos"] as Vector3).y, comp))
	_check("compose hover 缩放", is_equal_approx(float(c["visual_scale"]), cd["hover_scale"]))
	_check("compose hover 仰角(朝玩家=负 rot_x)", is_equal_approx((c["visual_rot_deg"] as Vector3).x, -cd["hover_pitch"]))
	var near_y: float = (c["visual_pos"] as Vector3).y - half_len * sin(deg_to_rad(absf((c["visual_rot_deg"] as Vector3).x)))
	_check("compose hover 近边不穿桌", near_y >= cd["hover_clearance"] - 1e-4)
	var cf := M.compose({"hover": 0.0, "press": 0.0, "flip": 0.5, "land": 0.0}, cd, 0.0, Vector2.ZERO)
	_check("compose flip_deg 90", is_equal_approx(float(cf["flip_deg"]), 90.0))
	_check("compose flip 高度峰值", is_equal_approx((cf["visual_pos"] as Vector3).y, cd["flip_lift"]))
	var ct := M.compose({"hover": 0.0, "press": 0.0, "flip": 0.0, "land": 0.0}, cd, 0.0, Vector2(0.5, -0.5))
	_check("compose 准星 tilt 方向", (ct["visual_rot_deg"] as Vector3).x > 0.0 and (ct["visual_rot_deg"] as Vector3).y > 0.0)

func _test_show_back() -> void:
	var b := CardBlock.new()
	add_child(b)
	b.setup({"card": {"rank": "A", "suit": "♥"}})
	_check("初始正面点数", b.label_text() == "A♥" and b.has_face_texture())
	b.show_back(true)
	_check("切背面：卡背贴图", b.has_back_texture())
	_check("切背面：隐藏点数", b.label_text() == "")
	b.show_back(false)
	_check("回正面：点数恢复", b.label_text() == "A♥" and b.has_face_texture())

func _test_bend() -> void:
	var b := CardBlock.new()
	add_child(b)
	b.setup({"card": {"rank": "A", "suit": "♥"}})
	b.set_bend(0.3)
	var max_y := -1e9
	var min_y := 1e9
	for v in b.mesh_vertices():
		max_y = maxf(max_y, v.y)
		min_y = minf(min_y, v.y)
	_check("弯曲：远端贴平(最小 y≈0)", absf(min_y) < 0.001)
	_check("弯曲：近端上翘(最大 y≈0.3)", absf(max_y - 0.3) < 0.02)
	b.set_bend(0.0)
	var flat := true
	for v in b.mesh_vertices():
		if absf(v.y) > 0.001:
			flat = false
	_check("弯曲归零恢复平", flat)

func _test_controller() -> void:
	var a := CardAnimation.new()
	a.config = CardAnimationConfig.new()
	add_child(a)
	await get_tree().process_frame
	_check("控制器已建节点", a.visual != null and a.shadow != null and a.body != null)
	_check("控制器基准拾取盒(不随动画)", a.pick_area != null and not a.body.is_pick_enabled())
	a.enter_hover()
	await get_tree().create_timer(a.config.hover_in_dur + 0.05).timeout
	_check("hover 抬升", a.visual.position.y > 0.0)
	_check("hover 阴影缩小", a.shadow.scale.x < 1.0)
	var mat: StandardMaterial3D = a.shadow.material_override
	_check("hover 阴影变淡", mat.albedo_color.a < a.config.shadow_base_alpha)
	a.click()
	await get_tree().create_timer(a.config.press_dur + 0.03).timeout
	_check("点击后进入 FLIP", a.state == CardAnimationMath.FLIP)
	a.click()
	await get_tree().create_timer(0.02).timeout
	_check("FLIP 中点击被忽略", a.state == CardAnimationMath.FLIP)
	await get_tree().create_timer(a.config.flip_dur + a.config.land_dur + 0.15).timeout
	_check("翻牌后显示背面", a.showing_back)
	_check("翻牌后仍悬停 → HOVER", a.state == CardAnimationMath.HOVER)
	_check("land 后缩放≈hover_scale", absf(a.visual.scale.x - a.config.hover_scale) < 0.03)
	a.exit_hover()
	await get_tree().create_timer(a.config.hover_out_dur + 0.05).timeout
	# IDLE 会恢复 idle 悬浮（±idle_amp），故只校验状态与不再抬升
	_check("离开悬停 → IDLE", a.state == CardAnimationMath.IDLE and absf(a.visual.position.y) <= a.config.idle_amp + 0.001)
	# 翻牌途中离开：落定后应回 IDLE 且 hover 归零（防卡在抬起态）
	a.enter_hover()
	await get_tree().create_timer(a.config.hover_in_dur + 0.05).timeout
	a.click()
	await get_tree().create_timer(a.config.press_dur + 0.02).timeout
	_check("翻牌途中离开前处于 FLIP", a.state == CardAnimationMath.FLIP)
	a.exit_hover()
	await get_tree().create_timer(a.config.flip_dur + a.config.land_dur + a.config.hover_out_dur + 0.2).timeout
	_check("翻牌途中离开 → 落定 IDLE", a.state == CardAnimationMath.IDLE)
	_check("翻牌途中离开 → hover 归零", a.hover_p < 0.02)
	a.enter_hover()
	await get_tree().create_timer(a.config.hover_in_dur + 0.05).timeout
	_check("可重新 hover 抬起", a.visual.position.y > 0.0)

func _test_sandbox() -> void:
	var scene: PackedScene = load("res://scenes/ui/card_animation_sandbox.tscn")
	var s = scene.instantiate()
	add_child(s)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_check("沙盒 10 张卡(2×5)", s.actors.size() == 10)
	_check("沙盒相机已取景", s.camera != null and s.camera.camera_node() != null)
	_check("准星命中某张卡", s.hovered >= 0)
	var center := s.get_viewport().get_visible_rect().size * 0.5
	var hit := Table3dPicker.pick_hit(s.camera.camera_node(), s.get_world_3d(), center)
	_check("pick_hit 含命中点 position", hit.has("position") and hit.get("position") is Vector3)
	s.auto_hover = false
	if s.hovered >= 0:
		s.actors[s.hovered].exit_hover()
	s.play(0, "hover")
	await get_tree().create_timer(s.actors[0].config.hover_in_dur + 0.05).timeout
	_check("沙盒 play hover 弯曲上翘", s.actors[0].body.bend_amount() > 0.0)
	s.play(0, "flip")
	await get_tree().create_timer(s.actors[0].config.press_dur + s.actors[0].config.flip_dur + s.actors[0].config.land_dur + 0.15).timeout
	_check("沙盒 play flip 显示背面", s.actors[0].showing_back)
	s.play(0, "reset")
	await get_tree().process_frame
	_check("沙盒 reset 回正面", not s.actors[0].showing_back and s.actors[0].flip_turns == 0 and s.actors[0].body.bend_amount() == 0.0)
