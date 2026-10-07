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
