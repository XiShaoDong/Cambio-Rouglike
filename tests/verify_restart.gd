extends Node
var failures := 0
var checks := 0
func _ready() -> void:
	GameState.turn_effect_rules_enabled = false  # 规则测试由 verify_turn_effect_rules 单独开启
	await get_tree().process_frame
	await _test()
	await _test_ready_clicked_reset()
	_test_shield_survives_restart()
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

## 回归：重开本局（换 match_id）时，客户端的命中 Ready 点击态必须复位，
## 否则回到 INITIAL_PEEK（phase 未离开）时 Ready 按钮卡在"已准备"且禁用。
func _test_ready_clicked_reset() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	GameState._reset_match()
	GameState._add_player(1, "H")
	GameState._add_player(2, "C")
	GameState._server_start_match(0, 5)
	var snap_a: Dictionary = GameState._snapshot_for(0)
	scene.latest_state = snap_a
	scene.game_view._ready_clicked = true
	scene.game_view._last_match_id = str(snap_a.get("match_id", ""))
	# 重开 → 新 match_id
	GameState._server_restart_match(0, "r1")
	var snap_b: Dictionary = GameState._snapshot_for(0)
	_check("重开产生新 match_id", str(snap_b.get("match_id", "")) != str(snap_a.get("match_id", "")))
	scene.latest_state = snap_b
	scene.game_view.render(snap_b)
	_check("重开后 Ready 点击态复位", scene.game_view._ready_clicked == false)
	_check("重开后 Ready 按钮可用", not scene.ready_button.disabled)
	scene.queue_free()
	await get_tree().process_frame

## 回归：重开本局应保留玩家买的道具状态——护盾保护格在重开后仍在。
func _test_shield_survives_restart() -> void:
	GameState._reset_match()
	GameState._add_player(1, "H")
	GameState._add_player(2, "C")
	GameState.run_state["relics"][Relics.GUARD_SHIELD_ID] = Relics.def_by_id(Relics.GUARD_SHIELD_ID)
	GameState.run_state["relic_inventories"][0] = [Relics.GUARD_SHIELD_ID]
	GameState._server_start_match(0, 5)
	var slot_before := int(GameState.players[0].protected_slot)
	_check("护盾开局生效(随机选格)", slot_before >= 0)
	_check("开局后护盾已从遗物栏消耗", not (Relics.GUARD_SHIELD_ID in GameState.run_state["relic_inventories"].get(0, [])))
	GameState._server_restart_match(0, "r2")
	_check("重开保留护盾保护格", int(GameState.players[0].protected_slot) == slot_before)
	_check("重开不复活护盾(遗物栏仍无)", not (Relics.GUARD_SHIELD_ID in GameState.run_state["relic_inventories"].get(0, [])))
	# 进入新一局（match_number+1）：护盾记录作废、不再保护
	GameState._deal_next_match()
	_check("新一局护盾失效", int(GameState.players[0].protected_slot) == -1)
