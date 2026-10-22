extends Node
## headless 测试：12 件新饰品的 Phase 2 规则（结算减分 / 视野 / 加分）。

var failures := 0
var checks := 0
var _rejections := 0

func _ready() -> void:
	GameState.turn_effect_rules_enabled = false
	GameState.command_rejected.connect(_count_reject)
	_test_score_mods()
	await _test_peek_reduce()
	await _test_peek_bonus()
	await _test_peek_flex()
	await _test_odd_even_peek()
	await _test_slap_bonus()
	await _test_jack_bonus()
	var status: String = " (FAILURES!)" if failures > 0 else ""
	print("=== RELIC RULES RESULT: %d/%d passed%s ===" % [checks - failures, checks, status])
	get_tree().quit(1 if failures > 0 else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _count_reject(_c: int, _m: String) -> void:
	_rejections += 1

func _open(count := 2, relics := {}) -> void:
	GameState._reset_match()
	_rejections = 0
	for i in count:
		GameState._add_player(i + 1, "P%d" % i)
	for seat in relics:
		GameState.run_state["relic_inventories"][int(seat)] = (relics[seat] as Array).duplicate()
		for id in relics[seat]:
			GameState.run_state["relics"][str(id)] = Relics.def_by_id(str(id))
	GameState._server_start_match(0, 5)
	for i in count:
		GameState._server_initial_ready(i)

func _set_pending(rank: String) -> void:
	var cid := str(GameState.pending_draw.card_id)
	GameState.cards[cid].rank = rank
	GameState.cards[cid].value = KongRules.card_value(rank)

func _next_turn_for(seat: int) -> void:
	GameState.slap_open = false
	GameState.current_player_id = seat
	GameState._start_turn(seat)

func _score(ranks: Array, suits: Array, relic_ids: Array) -> int:
	var p := {"A": {"cards": [], "health": 2, "name": "A"}}
	var cards := {}
	for i in ranks.size():
		var cid := "c%d" % i
		cards[cid] = {"id": cid, "rank": str(ranks[i]), "suit": str(suits[i]), "value": KongRules.card_value(str(ranks[i]))}
		p["A"].cards.append(cid)
	var mods := {"A": {}}
	for id in relic_ids:
		mods["A"][str(id)] = true
	var ranking := ScoreSystem.calculate_ranking(p, cards, ["A"], {}, mods)
	return int(ranking[0].score)

func _test_score_mods() -> void:
	_check("手牌税：5 张正分牌各 -1", _score(["5","5","5","5","5"], ["♠","♥","♣","♦","♠"], [Relics.TAX_HAND_ID]) == 20)
	_check("手牌税：负分 K 不受影响", _score(["K","5","5","5","5"], ["♠","♥","♣","♦","♠"], [Relics.TAX_HAND_ID]) == 15)
	_check("四花色：每张 -2 最低 0", _score(["A","A","A","A"], ["♠","♥","♣","♦"], [Relics.FOUR_SUITS_ID]) == 0)
	_check("四花色：K 不受影响", _score(["K","A","A","A"], ["♠","♥","♣","♦"], [Relics.FOUR_SUITS_ID]) == -1)
	_check("奇数手牌：总分 -6", _score(["2","2","2","2","2"], ["♠","♥","♣","♦","♠"], [Relics.ODD_HAND_ID]) == 4)
	_check("重复折半：/1.5 向下取整", _score(["5","5","7"], ["♠","♥","♣"], [Relics.DUPLICATE_ID]) == 11)
	_check("三张相同：/2", _score(["5","5","5","7"], ["♠","♥","♣","♦"], [Relics.TRIPLE_ID]) == 11)
	_check("重复 + 三张可叠加", _score(["5","5","5","7"], ["♠","♥","♣","♦"], [Relics.DUPLICATE_ID, Relics.TRIPLE_ID]) == 7)
	_check("顺序：每张→求和→-6→除法", _score(["5","5","5","5","5"], ["♠","♥","♣","♦","♠"], [Relics.TAX_HAND_ID, Relics.ODD_HAND_ID]) == 14)
	# 集成：GameState._calculate_ranking 会自动带上持有者的结算饰品
	_open(2, {0: [Relics.TAX_HAND_ID]})
	GameState.players[0].cards = []
	for i in 5:
		var cid := "score%d" % i
		GameState.cards[cid] = {"id": cid, "rank": "5", "suit": "♠", "value": 5}
		GameState.players[0].cards.append(cid)
	var integrated := 0
	for row in GameState._calculate_ranking():
		if int(row.id) == 0:
			integrated = int(row.score)
	_check("GameState 结算自动应用饰品", integrated == 20)

func _test_peek_reduce() -> void:
	_open(2, {0: [Relics.PEEK_REDUCE_ID]})
	GameState.players[0].cards[0] = "p0"
	GameState.cards["p0"] = {"id": "p0", "rank": "5", "suit": "♠", "value": 10}
	GameState._server_take(0, "draw", "pr1")
	_set_pending("7")
	GameState._server_use_ability(0, {"slot": 0}, "pr2")
	_check("7/8 自动让被看牌 -1", int(GameState.cards["p0"].value) == 9)
	_check("7/8 削弱每局一次", bool(GameState.relic_used.get(0, {}).get(Relics.PEEK_REDUCE_ID, false)))
	# 同一局第二次：不再 -1
	_next_turn_for(0)
	GameState._server_take(0, "draw", "pr3")
	_set_pending("8")
	GameState._server_use_ability(0, {"slot": 0}, "pr4")
	_check("7/8 削弱同局不重复触发", int(GameState.cards["p0"].value) == 9)

func _test_peek_bonus() -> void:
	_open(2, {0: [Relics.PEEK_BONUS_ID]})
	GameState.players[1].cards[0] = "p1"
	GameState.cards["p1"] = {"id": "p1", "rank": "5", "suit": "♠", "value": 5}
	GameState._server_take(0, "draw", "pb1")
	_set_pending("9")
	GameState._server_use_ability(0, {"target": 1, "target_slot": 0}, "pb2")
	_check("9/10 自动让被看牌 +1", int(GameState.cards["p1"].value) == 6)
	_next_turn_for(0)
	GameState._server_take(0, "draw", "pb3")
	_set_pending("10")
	GameState._server_use_ability(0, {"target": 1, "target_slot": 0}, "pb4")
	_check("9/10 加成同局不重复", int(GameState.cards["p1"].value) == 6)

func _test_peek_flex() -> void:
	_open(2, {0: [Relics.PEEK_FLEX_ID]})
	GameState.players[1].cards[0] = "f1"
	GameState.cards["f1"] = {"id": "f1", "rank": "5", "suit": "♠", "value": 5}
	GameState._server_take(0, "draw", "pf1")
	_set_pending("7")
	GameState._server_use_ability(0, {"target": 1, "target_slot": 0}, "pf2")
	_check("7/8 可当 9/10 看别人", _rejections == 0 and GameState.phase != GameState.Phase.TURN_DECISION)
	_next_turn_for(0)
	GameState.players[0].cards[0] = "f0"
	GameState.cards["f0"] = {"id": "f0", "rank": "5", "suit": "♠", "value": 5}
	GameState._server_take(0, "draw", "pf3")
	_set_pending("9")
	GameState._server_use_ability(0, {"slot": 0}, "pf4")
	_check("9/10 可当 7/8 看自己", _rejections == 0)

func _test_odd_even_peek() -> void:
	_open(2, {0: [Relics.ODD_PEEK_ID, Relics.EVEN_PEEK_ID]})
	_pending_rank_from_top("A")
	_check("奇数牌获得 peek_own", str(GameState.pending_draw.get("granted_ability", "")) == "peek_own")
	var snap := GameState._snapshot_for(0)
	_check("快照暴露 granted_ability", str(snap.get("pending", {}).get("granted_ability", "")) == "peek_own")
	GameState._server_use_ability(0, {"slot": 0}, "op2")
	_check("奇数视野可正常查看", _rejections == 0)
	_next_turn_for(0)
	_pending_rank_from_top("2")
	_check("偶数牌获得 peek_other", str(GameState.pending_draw.get("granted_ability", "")) == "peek_other")
	GameState._server_use_ability(0, {"target": 1, "target_slot": 0}, "ep2")
	_check("偶数视野可正常查看别人", _rejections == 0)
	_next_turn_for(0)
	_pending_rank_from_top("A")
	_check("奇数视野同局不重复", str(GameState.pending_draw.get("granted_ability", "")) == "")
	GameState._deal_next_match()
	_check("下一局重置一次性使用", GameState.relic_used.is_empty())

func _pending_rank_from_top(rank: String) -> void:
	var cid := "top_%s_%d" % [rank, randf()]
	GameState.cards[cid] = {"id": cid, "rank": rank, "suit": "♠", "value": KongRules.card_value(rank)}
	GameState.deck.append(cid)
	GameState._server_take(0, "draw", "take_%s_%d" % [rank, randf()])
	# 记录当前 pending 用于断言

func _test_slap_bonus() -> void:
	_open(2, {0: [Relics.SLAP_BONUS_ID]})
	GameState.players[0].cards = ["gift"]
	GameState.cards["gift"] = {"id": "gift", "rank": "5", "suit": "♠", "value": 5}
	GameState.players[1].cards = ["target"]
	GameState.cards["target"] = {"id": "target", "rank": "7", "suit": "♠", "value": 7}
	GameState.phase = GameState.Phase.SLAP_EXCHANGE
	GameState.slap_exchange = {"actor": 0, "target": 1, "target_slot": 0, "target_card": "target"}
	GameState._server_slap_exchange(0, 0, "sb1")
	_check("贴牌给出牌 +3", int(GameState.cards["gift"].value) == 8)
	# 同局第二次不再加（直接重设交换上下文）
	GameState.players[0].cards = ["gift2"]
	GameState.cards["gift2"] = {"id": "gift2", "rank": "6", "suit": "♠", "value": 6}
	GameState.phase = GameState.Phase.SLAP_EXCHANGE
	GameState.slap_exchange = {"actor": 0, "target": 1, "target_slot": 0, "target_card": "target"}
	GameState._server_slap_exchange(0, 0, "sb2")
	_check("贴牌加成同局不重复", int(GameState.cards["gift2"].value) == 6)

func _test_jack_bonus() -> void:
	_open(2, {0: [Relics.JACK_BONUS_ID]})
	GameState.players[0].cards = ["jgift"]
	GameState.cards["jgift"] = {"id": "jgift", "rank": "5", "suit": "♠", "value": 5}
	GameState.players[1].cards = ["jtarget"]
	GameState.cards["jtarget"] = {"id": "jtarget", "rank": "7", "suit": "♠", "value": 7}
	GameState._server_take(0, "draw", "jb1")
	_set_pending("J")
	GameState._server_use_ability(0, {"target": 1, "own_slot": 0, "target_slot": 0}, "jb2")
	_check("J 交换给出牌 +2", int(GameState.cards["jgift"].value) == 7)
	_check("J 交换后牌到对方槽位", str(GameState.players[1].cards[0]) == "jgift")
