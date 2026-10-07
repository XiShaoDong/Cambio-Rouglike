extends Node
## headless 单元测试：3D 全息看板宿主（坐标换算 / 挂载+wrap / 朝向 / 输入合成 / 拾取消歧 / main 双板路由）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== BOARD3D RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	await _test_board_input()
	await _test_board3d()
	await _test_modals_dim()
	await _test_ready_click()
	await _test_main_routing()

## 3D 开局记忆：Ready 在提示板上，且默认准星（相机→桌心连线）能直接落到它上面 → 可直接点到。
func _test_ready_click() -> void:
	Network.is_host = true
	var main: Node = preload("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var st := _tournament_state()
	st["phase"] = 1
	st["viewer_id"] = 0
	st["current_player"] = 0
	main.latest_state = st
	main._set_table3d(true)
	await get_tree().process_frame
	await get_tree().process_frame
	main._refresh_hint_panel()
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var ready: Button = main._hint_panel.get_node_or_null("VBox/ReadyButton")
	_check("3D 开局记忆显示 Ready", ready != null and ready.visible)
	_check("Ready 已加大高度（易点）", ready != null and ready.custom_minimum_size.y >= 60.0)
	_check("Ready 有明显 hover 样式", ready != null and ready.has_theme_stylebox_override("hover"))
	# 有可点元素时提示板贴准星：默认准星（相机→桌心）应直接落在 Ready 内（无需抬头）
	var cam: Camera3D = main.table3d.camera.camera_node()
	for i in 3:
		await get_tree().physics_frame
	var coord: Vector2i = main.hint3d.hit_viewport_coord(cam)
	var rr: Rect2 = ready.get_global_rect() if ready != null else Rect2()
	_check("默认准星即落在 Ready 内（3D 可直接点）", coord.x >= 0 and rr.has_point(Vector2(coord)))
	# 让 main._process 推送 hover motion，检查 Ready 是否真的进入 hover 态
	await get_tree().process_frame
	await get_tree().process_frame
	_check("准星悬停时 Ready.is_hovered()", ready != null and ready.is_hovered())
	main.queue_free()

func _test_board_input() -> void:
	var size := Vector2(2.6, 1.8)
	_check("中心 → uv(0.5,0.5)", BoardInput.local_to_uv(Vector3.ZERO, size).is_equal_approx(Vector2(0.5, 0.5)))
	_check("左上角 → uv(0,0)", BoardInput.local_to_uv(Vector3(-1.3, 0.9, 0.0), size).is_equal_approx(Vector2(0.0, 0.0)))
	_check("右下角 → uv(1,1)", BoardInput.local_to_uv(Vector3(1.3, -0.9, 0.0), size).is_equal_approx(Vector2(1.0, 1.0)))
	_check("uv(0.5,0.5) → 视口中心", BoardInput.uv_to_viewport(Vector2(0.5, 0.5), Vector2i(1024, 708)) == Vector2i(512, 354))
	_check("uv(0,0) → (0,0)", BoardInput.uv_to_viewport(Vector2(0.0, 0.0), Vector2i(1024, 708)) == Vector2i(0, 0))
	_check("uv(1,1) → 右下角", BoardInput.uv_to_viewport(Vector2(1.0, 1.0), Vector2i(1024, 708)) == Vector2i(1024, 708))
	var xf := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.6, 0.0))
	_check("world_to_local 平移", BoardInput.world_to_local(xf, Vector3(0.0, 1.6, 0.0)).is_equal_approx(Vector3.ZERO))

func _make_camera() -> Camera3D:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 3.5, 4.5)
	return cam

func _test_board3d() -> void:
	var cam := _make_camera()
	var b := Board3d.new()
	add_child(b)
	await get_tree().process_frame
	cam.look_at(b.global_position, Vector3.UP)
	_check("初始无面板且隐藏", not b.has_panel() and not b.visible)

	var panel := PanelContainer.new()
	panel.name = "TestPanel"
	var full_btn := Button.new()
	full_btn.name = "FullBtn"
	full_btn.text = "X"
	full_btn.custom_minimum_size = Vector2(300.0, 120.0)
	panel.add_child(full_btn)
	add_child(panel)  # 先像 main 一样挂 2D，再交给看板

	b.mount_panel(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("mount 后 has_panel", b.has_panel())
	_check("面板父节点为 SubViewport", panel.get_parent() == b.viewport())
	_check("看板可见", b.visible)
	_check("屏幕贴图为视口纹理",
		(b.screen_mesh().material_override as StandardMaterial3D).albedo_texture == b.viewport().get_texture())

	# wrap：视口尺寸 = 内容最小尺寸 + 内边距；quad = 视口 × 像素比例
	var content := panel.get_combined_minimum_size()
	var vs := b.viewport_size()
	_check("wrap 视口宽 = 内容宽 + 内边距",
		absi(vs.x - (int(ceil(content.x)) + Board3d.WRAP_PADDING.x)) <= 1)
	_check("wrap quad 尺寸 = 视口 × 像素比例",
		absf(b.world_size().x - float(vs.x) * Board3d.PIXEL_SCALE) < 0.001)

	b.set_facing(cam)
	await get_tree().process_frame
	var to_cam := (cam.global_position - b.global_position)
	to_cam.y = 0.0
	to_cam = to_cam.normalized()
	_check("看板 +Z 水平朝相机", b.global_transform.basis.z.normalized().dot(to_cam) > 0.99)
	_check("看板竖直（+Y=世界 up）", b.global_transform.basis.y.normalized().dot(Vector3.UP) > 0.99)

	await get_tree().physics_frame
	await get_tree().physics_frame
	var coord := b.hit_viewport_coord(cam)
	_check("准星命中看板返回视口中心附近",
		coord.x >= 0 and absi(coord.x - vs.x / 2) < 40 and absi(coord.y - vs.y / 2) < 40)

	var got := [0]
	full_btn.pressed.connect(func() -> void: got[0] += 1)
	b.push_click(Vector2i(vs.x / 2, vs.y / 2))
	await get_tree().process_frame
	await get_tree().process_frame
	_check("push_click 合成事件触发按钮", got[0] == 1)

	var catcher := KeyCatcher.new()
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(catcher)
	var key_ev := InputEventKey.new()
	key_ev.keycode = KEY_ENTER
	key_ev.pressed = true
	b.push_key(key_ev)
	await get_tree().process_frame
	_check("push_key 送达视口内节点", catcher.events.has(KEY_ENTER))

	# 拾取消歧：另一块可见看板不在准星下 → 不误命中
	var b2 := Board3d.new()
	add_child(b2)
	b2.position = Vector3(50.0, 0.0, 0.0)
	var p2 := PanelContainer.new()
	var lbl2 := Label.new()
	lbl2.text = "B2"
	p2.add_child(lbl2)
	add_child(p2)
	b2.mount_panel(p2)
	await get_tree().process_frame
	await get_tree().physics_frame
	_check("远处看板未被中心射线命中", b2.hit_viewport_coord(cam) == Vector2i(-1, -1))

	b.unmount_panel(panel)
	_check("unmount 后面板脱离视口", panel.get_parent() == null)
	_check("unmount 后隐藏", not b.has_panel() and not b.visible)

	# 已释放面板残留在 _panels：has_panel / detach_all 不得对已释放对象报错（复现退出 3D 崩溃）
	var ghost := PanelContainer.new()
	var glbl := Label.new()
	glbl.text = "ghost"
	ghost.add_child(glbl)
	add_child(ghost)
	b.mount_panel(ghost)
	await get_tree().process_frame
	ghost.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("已释放面板被清理：has_panel 为假", not b.has_panel())
	b.detach_all()
	_check("detach_all 对已释放条目安全", true)

	panel.queue_free()
	p2.queue_free()
	b2.queue_free()


func _test_modals_dim() -> void:
	var shop: Control = load("res://scenes/ui/shop_panel.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	var shop_state := {"viewer_id": 0, "players": [{"id": 0, "currency": 100}], "shop": {"offers": [], "done": []}}
	shop.setup(shop_state, Callable(), Callable(), true)
	_check("shop dim=true → Dim 可见", (shop.get_node("Dim") as CanvasItem).visible)
	shop.setup(shop_state, Callable(), Callable(), false)
	_check("shop dim=false → Dim 隐藏", not (shop.get_node("Dim") as CanvasItem).visible)
	shop.queue_free()

	var duel := DuelBar.new()
	add_child(duel)
	await get_tree().process_frame
	duel.setup(self, {"duration_ms": 2000, "target": 0.5, "viewer_contestant": 0}, Callable(), false)
	_check("duel dim=false → 无 Dim 遮罩", duel.get_node_or_null("Dim") == null)
	duel.queue_free()


func _tournament_state() -> Dictionary:
	return {
		"phase": 2, "phase_name": "p", "viewer_id": 0, "current_player": 1, "current_name": "B",
		"players": [{"id": 0, "name": "A", "slots": [], "health": 2, "currency": 100, "count": 0,
			"ready": false, "eliminated": false}],
		"draw_count": 40, "discard": {}, "pending": {}, "run": {}, "match_number": 1,
		"result": {}, "event_log": [], "slap_open": false, "slap_rank": "",
		"slap_exchange_actor": 0, "kong_caller": -1, "ready_count": 0, "offline_players": [],
	}

func _test_main_routing() -> void:
	await get_tree().process_frame
	Network.is_host = true
	var main: Node = preload("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main.latest_state = _tournament_state()
	main._set_table3d(true)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("3D 下有 board3d 节点", main.board3d != null and is_instance_valid(main.board3d))
	_check("3D 下有 hint3d 节点", main.hint3d != null and is_instance_valid(main.hint3d))
	_check("提示板已挂常驻提示面板", main.hint3d.has_panel())
	_check("无模态时模态大板不显示", not main.board3d.visible)
	_check("无模态时点击落到牌桌", main._click_route(false) == "table")
	_check("命中看板时点击给看板", main._click_route(true) == "board")

	# 看板：XZ 在"相机→桌心"连线上、Y 抬高 1/3；面板竖直；提示板在大板上方
	var cam: Camera3D = main.table3d.camera.camera_node()
	var cm: Dictionary = main.get_script().get_script_constant_map()
	var bdist: float = cm.get("BOARD_DIST", 0.0)
	var base: Vector3 = cam.global_position + (Vector3(0.0, Table3dLayout.TABLE_HEIGHT, 0.0) - cam.global_position).normalized() * bdist
	var bp: Vector3 = main.board3d.global_position
	_check("模态板 XZ 在相机→桌心连线上", absf(bp.x - base.x) < 0.05 and absf(bp.z - base.z) < 0.05)
	_check("模态板高度已抬升", bp.y > base.y + 0.1)
	_check("面板完全竖直（+Y=世界 up）",
		main.board3d.global_transform.basis.y.normalized().dot(Vector3.UP) > 0.99)
	_check("提示板在大板上方", main.hint3d.global_position.y > bp.y + 0.1)

	main._open_shop_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("模态挂到模态大板 SubViewport", main.shop_panel.get_parent() == main.board3d.viewport())
	_check("board3d.has_panel()", main.board3d.has_panel())
	_check("有模态时模态大板显示", main.board3d.visible)
	_check("有模态时未命中看板则拦截（不点穿牌桌）", main._click_route(false) == "blocked")

	# 开局记忆阶段：提示板显示 Ready 按钮
	var st := _tournament_state()
	st["phase"] = 1
	main.latest_state = st
	main._refresh_hint_panel()
	await get_tree().process_frame
	var ready: Button = main._hint_panel.get_node_or_null("VBox/ReadyButton")
	_check("开局记忆阶段提示板显示 Ready", ready != null and ready.visible)

	# Q_DECISION 已看自己牌：交换/不交换按钮出现在提示板下方（与 2D HintActions 一致）
	var qst := _tournament_state()
	qst["phase"] = 4
	qst["viewer_id"] = 0
	qst["current_player"] = 0
	qst["q_decision"] = {"own_viewed": true, "actor": 0, "target": 1, "target_slot": 0}
	main.latest_state = qst
	main._refresh_hint_panel()
	await get_tree().process_frame
	var acts: HBoxContainer = main._hint_panel.get_node_or_null("VBox/HintActions")
	_check("Q 决策按钮在提示板下方（2 个）", acts != null and acts.get_child_count() == 2)
	_check("3D 桌面 HUD 不再承载条件动作", main._hud_buttons().is_empty())
	# 决策按钮更大更好点 + 明显的 hover 反馈
	var dbtn: Button = acts.get_child(0) if acts != null and acts.get_child_count() > 0 else null
	_check("决策按钮尺寸放大", dbtn != null and dbtn.custom_minimum_size.x >= 200.0 and dbtn.custom_minimum_size.y >= 50.0)
	_check("决策按钮有 hover 样式", dbtn != null and dbtn.has_theme_stylebox_override("hover"))

	main._set_table3d(false)
	await get_tree().process_frame
	_check("切回 2D 后模态重新挂到 main", main.shop_panel.get_parent() == main)
	main.queue_free()


class KeyCatcher extends Control:
	var events: Array = []
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey:
			events.append(event.keycode)
