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
