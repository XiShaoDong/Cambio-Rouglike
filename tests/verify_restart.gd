extends Node
var failures := 0
var checks := 0
func _ready() -> void:
	await get_tree().process_frame
	await _test()
	print("=== RESTART RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)
func _check(n: String, ok: bool) -> void:
	checks += 1
	if ok: print("[PASS] " + n)
	else: failures += 1; printerr("[FAIL] " + n)
func _test() -> void:
	GameState._reset_match()
	GameState.phase = GameState.Phase.LOBBY
	GameState._add_player(1, "房主")
	GameState._add_player(2, "乙")
	GameState._server_start_match(0, 5)
	var mid0 := GameState.match_id
	var num0 := GameState.match_number
	GameState.players[0].currency = 123
	GameState.players[0].health = 2
	GameState._server_restart_match(0, "a1")
	_check("重开生成新 match_id", GameState.match_id != mid0 and not GameState.match_id.is_empty())
	_check("match_number 保留", GameState.match_number == num0)
	_check("货币保留", int(GameState.players[0].currency) == 123)
	_check("生命保留", int(GameState.players[0].health) == 2)
	_check("手牌重发 HAND_SIZE", GameState.players[0].cards.size() == KongRules.HAND_SIZE)
	_check("回 INITIAL_PEEK", GameState.phase == GameState.Phase.INITIAL_PEEK)
	var mid1 := GameState.match_id
	GameState._server_restart_match(1, "a2")
	_check("非房主拒绝（match_id 不变）", GameState.match_id == mid1)

	# 发牌编排
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var st := {"viewer_id": 0, "current_player": 0, "players": [
		{"id": 0, "name": "甲", "count": 4, "currency": 0, "health": 2, "slots": [{"card_id":"c0"},{"card_id":"c1"},{"card_id":"c2"},{"card_id":"c3"}]},
		{"id": 1, "name": "乙", "count": 4, "currency": 0, "health": 2, "slots": [{"card_id":"d0"},{"card_id":"d1"},{"card_id":"d2"},{"card_id":"d3"}]},
	], "draw_count": 30, "discard": {}, "pending": {}, "phase": 1}
	view.render(st)
	await get_tree().process_frame
	view.set_deal_speed(99.0)
	view.play_deal(st)
	_check("发牌标记在途", view._dealing and view._anim_slots.size() > 0)
	await get_tree().create_timer(1.5).timeout
	_check("发牌结束清空在途", not view._dealing and view._anim_slots.is_empty())
	view.queue_free()
	await get_tree().process_frame
