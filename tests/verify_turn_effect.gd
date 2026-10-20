extends Node
## headless 单元测试：每回合随机增强数据（TurnEffect）+ 展示面板（TurnEffectPanel）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TURN EFFECT RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_data()
	await _test_panel()
	await _test_main_updates_by_turn_index()

func _test_data() -> void:
	_check("5 种效果", TurnEffect.all().size() == 5)
	_check("无效果 id", str(TurnEffect.by_id("none")["id"]) == "none")
	_check("红 Joker", str(TurnEffect.by_id("joker_red")["name"]).contains("红"))
	_check("黑 Joker", str(TurnEffect.by_id("joker_black")["name"]).contains("黑"))
	_check("炸弹标记", bool(TurnEffect.by_id("bomb")["bomb"]))
	var ids := {}
	for e in TurnEffect.all():
		ids[str(e["id"])] = true
	_check("随机结果合法", ids.has(str(TurnEffect.random()["id"])))
	# 服务器权威抽取：turn_index 递增、id 合法
	GameState.turn_index = 0
	GameState.turn_effect_id = ""
	GameState._roll_turn_effect()
	_check("服务器抽取 turn_index 递增", GameState.turn_index == 1)
	_check("服务器抽取 id 合法", GameState.TURN_EFFECT_IDS.has(GameState.turn_effect_id))
	# 连续抽取不会与上一回合相同（避免一直显示同一效果）
	var prev := GameState.turn_effect_id
	var all_differ := true
	for i in 8:
		GameState._roll_turn_effect()
		if GameState.turn_effect_id == prev:
			all_differ = false
		prev = GameState.turn_effect_id
	_check("连续换回合效果不与上次相同", all_differ)

func _test_panel() -> void:
	var p := TurnEffectPanel.new()
	add_child(p)
	await get_tree().process_frame
	_check("初始隐藏", not p.visible)
	p.set_effect(TurnEffect.by_id("bomb"))
	_check("内容 id=bomb", p.effect_id() == "bomb")
	_check("说明非空", not p.description_text().is_empty())
	p.reveal(TurnEffect.by_id("joker_red"), Vector2(400, 300), Vector2(1100, 75))
	_check("reveal 可见", p.visible)
	_check("reveal 播放中", p.is_revealing())
	_check("中央放大", p.scale.x > 1.0)
	p.dock_at(Vector2(1100, 75))
	_check("dock 后不再播放", not p.is_revealing() and p.visible)
	_check("dock 缩放 1", is_equal_approx(p.scale.x, 1.0))
	_check("dock 右上角贴住 dock 点（不跑出屏幕）", is_equal_approx(p.position.x + p.size.x, 1100.0) and is_equal_approx(p.position.y, 75.0))
	p.hide_panel()
	_check("hide 后不可见", not p.visible)
	p.queue_free()

func _state() -> Dictionary:
	return {
		"phase": 2, "phase_name": "p", "viewer_id": 0, "current_player": 0, "current_name": "A",
		"players": [
			{"id": 0, "name": "A", "slots": [{}, {}, {}, {}], "health": 2, "currency": 100, "count": 4, "eliminated": false},
			{"id": 1, "name": "B", "slots": [{}, {}, {}, {}], "health": 2, "currency": 100, "count": 4, "eliminated": false},
		],
		"draw_count": 40, "discard": {}, "pending": {}, "event_log": [], "match_number": 1,
		"slap_rank": "", "slap_open": false, "slap_exchange_actor": 0, "kong_caller": -1,
		"ready_count": 0, "result": {}, "run": {"match_limit": 5}, "q_decision": {},
		"turn_index": 1, "turn_effect": "joker_red",
	}

func _test_main_updates_by_turn_index() -> void:
	var main_node: Node = preload("res://scenes/main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	await get_tree().process_frame
	main_node.latest_state = _state()
	main_node._set_table3d(true)
	await get_tree().process_frame
	main_node._refresh_table3d()
	await get_tree().process_frame
	_check("客户端首回合效果=joker_red", main_node._turn_effect_panel.effect_id() == "joker_red")
	var st2: Dictionary = _state()
	st2["turn_index"] = 2
	st2["turn_effect"] = "bomb"
	main_node.latest_state = st2
	main_node._refresh_table3d()
	await get_tree().process_frame
	_check("turn_index 变化后效果更新=bomb", main_node._turn_effect_panel.effect_id() == "bomb")
	main_node._set_table3d(false)
	main_node.queue_free()
