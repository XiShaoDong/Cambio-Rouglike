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
	await _test_main_updates_per_match()

func _test_data() -> void:
	_check("4 种效果", TurnEffect.all().size() == 4)
	_check("无效果 id", str(TurnEffect.by_id("none")["id"]) == "none")
	_check("6 效果", str(TurnEffect.by_id("six_swap")["name"]).contains("6"))
	_check("6 效果说明含传递", str(TurnEffect.by_id("six_swap")["desc"]).contains("传递"))
	_check("炸弹标记", bool(TurnEffect.by_id("bomb")["bomb"]))
	var ids := {}
	for e in TurnEffect.all():
		ids[str(e["id"])] = true
	_check("随机结果合法", ids.has(str(TurnEffect.random()["id"])))
	# 服务器权威抽取：每局抽一次，不推进 turn_index
	GameState.turn_index = 0
	GameState.turn_effect_id = ""
	GameState._roll_turn_effect()
	_check("服务器抽取不推进 turn_index", GameState.turn_index == 0)
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
	p.reveal(TurnEffect.by_id("six_swap"), Vector2(400, 300), Vector2(1100, 75))
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
		"match_id": "m1",
		"phase": 2, "phase_name": "p", "viewer_id": 0, "current_player": 0, "current_name": "A",
		"players": [
			{"id": 0, "name": "A", "slots": [{}, {}, {}, {}], "health": 2, "currency": 100, "count": 4, "eliminated": false},
			{"id": 1, "name": "B", "slots": [{}, {}, {}, {}], "health": 2, "currency": 100, "count": 4, "eliminated": false},
		],
		"draw_count": 40, "discard": {}, "pending": {}, "event_log": [], "match_number": 1,
		"slap_rank": "", "slap_open": false, "slap_exchange_actor": 0, "kong_caller": -1,
		"ready_count": 0, "result": {}, "run": {"match_limit": 5}, "q_decision": {},
		"turn_index": 1, "turn_effect": "six_swap",
	}

func _test_main_updates_per_match() -> void:
	var main_node: Node = preload("res://scenes/main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	await get_tree().process_frame
	# 开局记忆阶段（INITIAL_PEEK）不展示效果，等全员 Ready 进入 TURN_DRAW 后再展示。
	var peek_state: Dictionary = _state()
	peek_state["phase"] = 1
	main_node.latest_state = peek_state
	main_node._set_table3d(true)
	await get_tree().process_frame
	main_node._refresh_table3d()
	await get_tree().process_frame
	_check("开局记忆阶段不展示效果", main_node._turn_effect_panel == null or not main_node._turn_effect_panel.visible)
	var reveal_state: Dictionary = _state()
	reveal_state["phase"] = 12
	main_node.latest_state = reveal_state
	main_node._set_table3d(true)
	await get_tree().process_frame
	main_node._refresh_table3d()
	await get_tree().process_frame
	_check("客户端首局效果=six_swap", main_node._turn_effect_panel.effect_id() == "six_swap")
	_check("效果展示中 hint=查看本局特效", main_node._hint_hud.cur_label().text == main_node.EFFECT_REVEAL_TEXT)
	_check("效果展示中倒计时=5s", is_equal_approx(main_node._hint_hud.timer().limit, 5.0) and main_node._hint_hud.timer().seconds_left() in [4, 5])
	main_node.latest_state = _state()
	main_node._refresh_table3d()
	await get_tree().process_frame
	_check("展示阶段结束开始第一个玩家倒计时", is_equal_approx(main_node._hint_hud.timer().limit, 30.0) \
		and main_node._hint_hud.timer().seconds_left() > 28 \
		and main_node._hint_hud.cur_label().text == main_node._hint_for(2, true))
	var st2: Dictionary = _state()
	st2["turn_index"] = 2
	st2["turn_effect"] = "six_swap"
	main_node.latest_state = st2
	main_node._refresh_table3d()
	await get_tree().process_frame
	_check("同一局内换回合不换效果", main_node._turn_effect_panel.effect_id() == "six_swap")
	var st3: Dictionary = _state()
	st3["match_id"] = "m2"
	st3["phase"] = 12
	st3["turn_effect"] = "bomb"
	main_node.latest_state = st3
	main_node._refresh_table3d()
	await get_tree().process_frame
	_check("下一局 match_id 变化后效果更新=bomb", main_node._turn_effect_panel.effect_id() == "bomb")
	# 开发者 T 面板：测试模式入口 + 面板不超出屏幕。
	main_node.size = Vector2(1280, 760)
	Network.is_host = true
	main_node.dev_mode = true
	main_node.latest_state = _state()
	main_node.dev.refresh_panel()
	await get_tree().process_frame
	var dev_panel: Control = main_node.get_node_or_null("DevPanel")
	_check("开发者面板存在", dev_panel != null)
	if dev_panel != null:
		_check("开发者面板在屏幕内", dev_panel.position.x >= 0.0 and dev_panel.position.y >= 0.0 \
			and dev_panel.position.x + dev_panel.size.x <= main_node.size.x + 0.5 \
			and dev_panel.position.y + dev_panel.size.y <= main_node.size.y + 0.5)
		_check("开发者面板可滚动", dev_panel.get_node_or_null("Scroll") != null)
	var before_mode: bool = GameState.dev_test_mode
	main_node.dev._toggle_test_mode()
	_check("测试模式可切换", GameState.dev_test_mode != before_mode)
	main_node.dev._toggle_test_mode()
	main_node.dev._on_test_effect_selected(3)
	_check("测试效果可选择 +1", GameState.dev_test_effect == "plus_one")
	GameState.dev_test_effect = ""
	GameState.dev_test_mode = false
	Network.is_host = false
	# +1 浮字：由服务器 plus_one 事件触发（1s 上升 + 1s 淡出后释放）。
	var plus_state: Dictionary = _state()
	plus_state["match_id"] = "m_plus"
	plus_state["phase"] = 2
	plus_state["turn_effect"] = "plus_one"
	plus_state["turn_index"] = 50
	plus_state["current_player"] = 0
	plus_state["players"][0]["slots"][2] = {"card_id": "p", "card": {"rank": "2", "suit": "♠"}}
	main_node.latest_state = plus_state
	main_node._render_game()
	GameState.card_exchange_animated.emit({"kind": "plus_one", "seat": 0, "slot": 2})
	_check("+1 浮字出现", _count_plus_one(main_node) == 1)
	await get_tree().create_timer(2.1).timeout
	_check("+1 浮字 2s 后释放", _count_plus_one(main_node) == 0)
	# 炸弹爆炸贴图：出现后 0.6s 淡出释放。
	main_node._render_game()
	main_node._show_bomb_burst(0, 2)
	_check("炸弹爆炸贴图出现", main_node.get_node_or_null("BombBurst") != null)
	await get_tree().create_timer(0.8).timeout
	_check("炸弹爆炸贴图 0.6s 后释放", main_node.get_node_or_null("BombBurst") == null)
	main_node._set_table3d(false)
	main_node.queue_free()

func _count_plus_one(main_node: Node) -> int:
	var n := 0
	for c in main_node.get_children():
		if c is Label and (c as Label).text == "+1":
			n += 1
	return n
