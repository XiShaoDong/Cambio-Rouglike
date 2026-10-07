extends Node
## headless 单元测试：TurnTimer 纯模型 + HintText 文案表 + HintHud 屏幕面板 + main 集成。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== HINT_HUD RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_turn_timer()
	_test_hint_text()
	await _test_hint_hud()
	await _test_hint_hud_fixes()
	await _test_slap_row()
	await _test_main_integration()

func _test_turn_timer() -> void:
	var t := TurnTimer.new()
	t.reset(30.0)
	_check("TurnTimer reset=30", is_equal_approx(t.remaining, 30.0) and t.seconds_left() == 30)
	t.tick(1.5)
	_check("TurnTimer tick 递减", is_equal_approx(t.remaining, 28.5) and t.seconds_left() == 28)
	t.tick(40.0)
	_check("TurnTimer 可为负", t.remaining < 0.0 and t.seconds_left() < 0)
	t.reset(30.0)
	_check("TurnTimer phase 正常 0", t.phase() == 0)
	t.reset(8.0)
	_check("TurnTimer phase 临近 1", t.phase() == 1)
	t.reset(0.0)
	_check("TurnTimer phase 超时 2", t.phase() == 2)
	var n := TurnTimer.new()
	n.reset(0.0)
	n.tick(0.3)
	_check("TurnTimer floor 负数 -1", n.seconds_left() == -1)

func _hint_state(phase: int, viewer: int, current: int, pending: Dictionary = {}) -> Dictionary:
	return {
		"phase": phase, "viewer_id": viewer, "current_player": current, "current_name": "Bob",
		"players": [], "discard": {}, "pending": pending, "event_log": [], "match_number": 1,
		"slap_rank": "", "slap_open": false, "slap_exchange_actor": 0, "kong_caller": -1,
		"ready_count": 0, "result": {}, "run": {}, "q_decision": {},
	}

func _test_hint_text() -> void:
	_check("HintText INITIAL_PEEK", HintText.hint(_hint_state(1, 0, 0), 1, true, "") == "Remember your two bottom cards, then click Ready")
	_check("HintText TURN_DRAW 当前", "discard pile" in HintText.hint(_hint_state(2, 0, 0), 2, true, ""))
	_check("HintText TURN_DRAW 他人含 Bob", "Bob" in HintText.hint(_hint_state(2, 1, 0), 2, false, ""))
	var replace_state := _hint_state(3, 0, 0, {"rank": "9", "source": "draw"})
	_check("HintText decision replace 含 replace", "replace" in HintText.hint(replace_state, 3, true, "replace").to_lower())
	_check("HintText decision 他人含 Bob", "Bob" in HintText.hint(replace_state, 3, false, ""))
	_check("HintText GAME_OVER 非空", not HintText.hint(_hint_state(7, 0, 0), 7, true, "").is_empty())

func _test_hint_hud() -> void:
	var hud := HintHud.new()
	add_child(hud)
	await get_tree().process_frame
	hud.show_hud(true)
	_check("HintHud 顶部居中锚点", is_equal_approx(hud.anchor_left, 0.5) and is_equal_approx(hud.anchor_right, 0.5) and is_equal_approx(hud.anchor_top, 0.0))
	_check("HintHud 初始隐藏于建造后 show", hud.visible)
	hud.set_phase_visible(2)
	hud.reset_turn(30.0)
	var pill: PanelContainer = hud.pill()
	_check("胶囊存在且可见", pill != null and pill.visible)
	var st: StyleBoxFlat = pill.get_theme_stylebox("panel")
	_check("胶囊圆角=高/2", is_equal_approx(float(st.corner_radius_top_left), HintHud.PILL_H * 0.5))
	_check("胶囊左右留白", is_equal_approx(st.content_margin_left, HintHud.PILL_H_PAD) and is_equal_approx(st.content_margin_right, HintHud.PILL_H_PAD))
	_check("胶囊有边框", st.border_width_top >= 2)
	_check("倒计时文本=30", hud.pill_label().text == "30")
	_check("进场：胶囊从上方掉落", pill.position.y < 0.0)
	hud.set_hint("First")
	hud.set_hint("Second")
	_check("换字：旧片仍在", hud.cur_label().text == "First")
	_check("换字：新片从上方进入", hud.next_label().text == "Second" and hud.next_label().position.y < hud.hint_base_y())
	hud.set_phase_visible(7)
	_check("GAME_OVER 隐藏胶囊", not pill.visible)
	hud.set_phase_visible(2)
	hud.reset_turn(1.0)
	hud.timer().tick(2.0)
	hud._process(0.0)
	_check("负秒红色", hud.pill_label().get_theme_color("font_color") == HintHud.COLOR_OVER)
	hud.show_hud(false)
	_check("show_hud(false) 不可见", not hud.visible)
	_check("show_hud(false) 停止计时", not hud.is_processing())
	hud.queue_free()

func _test_hint_hud_fixes() -> void:
	var hud := HintHud.new()
	add_child(hud)
	await get_tree().process_frame
	hud.show_hud(true)
	# 问题 1：INITIAL_PEEK（大家 ready）阶段不显示胶囊。
	hud.set_phase_visible(1)
	_check("ready 阶段隐藏胶囊", not hud.pill().visible)
	hud.set_phase_visible(2)
	_check("TURN_DRAW 显示胶囊", hud.pill().visible)
	# 问题 2：新回合直接提交文本到单片，不做换字遗留。
	hud.set_hint("A")
	hud.set_hint("B")  # 启动换字动画：B 在 next
	_check("换字中 cur 仍 A", hud.cur_label().text == "A")
	hud.reset_turn(30.0, "B")  # 新回合：提交 B 到单片
	_check("新回合 cur=B", hud.cur_label().text == "B")
	_check("新回合 next 隐藏", not hud.next_label().visible)
	hud.set_hint("B")  # 同文本；不应残留旧文本
	_check("同文本不残留", hud.cur_label().text == "B")
	# 连续快速换字最终收敛到最新文本。
	hud.set_hint("C")
	hud.set_hint("D")
	await get_tree().create_timer(0.7).timeout
	_check("连续换字收敛到最新 D", hud.cur_label().text == "D")
	_check("收敛后仅一片可见", not hud.next_label().visible)
	hud.queue_free()

func _test_slap_row() -> void:
	var hud := HintHud.new()
	add_child(hud)
	await get_tree().process_frame
	hud.show_hud(true)
	hud.set_hint("Draw")
	_check("SLAP 初始隐藏", not hud.slap_row_visible())
	hud.set_slap_state(HintHud.SLAP_OPEN)
	_check("OPEN：行可见", hud.slap_row_visible())
	_check("OPEN：绿 SLAP OPEN", hud.slap_label().text == "SLAP OPEN" and hud.slap_label().get_theme_color("font_color") == HintHud.SLAP_OPEN_COLOR)
	_check("OPEN：条可见 value≈1", hud.slap_bar().visible and is_equal_approx(hud.slap_bar().value, 1.0))
	_check("状态行水平居中", hud.slap_label().horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER)
	hud._process(3.0)
	var v_mid: float = hud.slap_bar().value
	hud.set_slap_state(HintHud.SLAP_OPEN)
	_check("同状态重发不重置条", is_equal_approx(hud.slap_bar().value, v_mid) and v_mid < 1.0)
	hud.set_slap_state(HintHud.SLAP_CLOSE)
	_check("CLOSE：红 SLAP CLOSE", hud.slap_label().text == "SLAP CLOSE" and hud.slap_label().get_theme_color("font_color") == HintHud.SLAP_CLOSE_COLOR)
	_check("CLOSE：条隐藏", not hud.slap_bar().visible)
	hud.set_slap_state(HintHud.SLAP_HIDDEN)
	_check("HIDDEN：整行隐藏", not hud.slap_row_visible())
	hud.set_slap_state(HintHud.SLAP_OPEN)
	_check("重开窗口条重置满", is_equal_approx(hud.slap_bar().value, 1.0) and not hud.slap_exhausted())
	hud._process(HintHud.SLAP_BAR_SECONDS + 0.1)
	_check("走空：整行消失", not hud.slap_row_visible() and hud.slap_exhausted())
	hud.set_slap_state(HintHud.SLAP_HIDDEN)
	hud.set_slap_state(HintHud.SLAP_OPEN)
	await get_tree().process_frame
	var w: float = maxf(maxf(hud.pill().get_combined_minimum_size().x, HintHud.HINT_MAX_W), HintHud.SLAP_BAR_W)
	_check("条水平居中", is_equal_approx(hud.slap_bar().position.x, (w - HintHud.SLAP_BAR_W) * 0.5))
	hud.queue_free()

func _main_state() -> Dictionary:
	return {
		"phase": 2, "phase_name": "抽牌", "viewer_id": 0, "current_player": 0, "current_name": "A",
		"players": [
			{"id": 0, "name": "A", "slots": [{}, {}, {}, {}], "health": 2, "currency": 100, "count": 4, "eliminated": false},
			{"id": 1, "name": "B", "slots": [{}, {}, {}, {}], "health": 2, "currency": 100, "count": 4, "eliminated": false},
		],
		"draw_count": 40, "discard": {}, "pending": {}, "event_log": [], "match_number": 1,
		"slap_rank": "", "slap_open": false, "slap_exchange_actor": 0, "kong_caller": -1,
		"ready_count": 0, "result": {}, "run": {"match_limit": 5}, "q_decision": {},
	}

func _test_main_integration() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main_node: Node = scene.instantiate()
	add_child(main_node)
	await get_tree().process_frame
	await get_tree().process_frame
	main_node.latest_state = _main_state()
	main_node._set_table3d(true)
	await get_tree().process_frame
	_check("main 已建 HintHud", main_node._hint_hud != null and is_instance_valid(main_node._hint_hud))
	_check("3D 下 HintHud 可见", main_node._hint_hud.visible)
	_check("hint3d 不再有 HintLabel", main_node._hint_panel.get_node_or_null("VBox/HintLabel") == null)
	_check("hint3d 仍有 Ready", main_node._hint_panel.get_node_or_null("VBox/ReadyButton") != null)
	_check("HintHud 文本=_hint_for", main_node._hint_hud.cur_label().text == main_node._hint_for(2, true))
	_check("回合 key 记录 1:0", main_node._hud_turn_key == "1:0")
	# 问题 2（集成）：viewer=0 等待 viewer=1，hint 应为"等待他人"且无换字遗留。
	main_node.latest_state = _main_state()
	main_node.latest_state["current_player"] = 1
	main_node._refresh_hint_panel()
	await get_tree().process_frame
	_check("等待他人时 hint 正确", "Waiting" in main_node._hint_hud.cur_label().text)
	_check("等待他人时 next 隐藏", not main_node._hint_hud.next_label().visible)
	main_node._set_table3d(false)
	await get_tree().process_frame
	_check("退出 3D 后 HintHud 隐藏", not main_node._hint_hud.visible)
	main_node.queue_free()
