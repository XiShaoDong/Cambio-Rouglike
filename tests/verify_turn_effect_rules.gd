extends Node
## headless 单元测试：每局随机增强的真实玩法（plus_one / 6 传递 / 炸弹）。
## 旧测试通过 GameState.turn_effect_rules_enabled=false 保持确定性；本测试显式开启。

var failures := 0
var checks := 0
var _rejections := 0
var _pass_ids := 0
var _last_exchange: Dictionary = {}

func _ready() -> void:
	GameState.command_rejected.connect(_count_reject)
	GameState.card_exchange_animated.connect(func(data: Dictionary): _last_exchange = data)
	_test_effect_reveal_phase()
	_test_effect_persists_per_match()
	_test_plus_one()
	_test_six_replace_triggers_pass()
	_test_six_power_red_joker()
	_test_six_power_action_ui()
	_test_six_not_trigger_other_effect()
	_test_pass_offline_auto()
	_test_pass_snapshot()
	_test_pass_kick_removes_from_queue()
	_test_bomb_mark()
	_test_bomb_start_effect()
	_test_bomb_countdown()
	_test_rules_disabled()
	_test_dev_test_mode()
	await _test_ui_badges()
	var status: String = " (FAILURES!)" if failures > 0 else ""
	print("=== TURN EFFECT RULES RESULT: %d/%d passed%s ===" % [checks - failures, checks, status])
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

## 3 人开局；先用 rules=false 避免自动效果干扰，随后开启规则。
## 开局到 INITIAL_PEEK（不发 ready），用于检查测试模式准备的手牌/抽牌堆。
func _open_peek() -> void:
	GameState._reset_match()
	GameState.turn_effect_rules_enabled = false
	_rejections = 0
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0, 5)

func _open() -> void:
	GameState._reset_match()
	GameState.turn_effect_rules_enabled = false
	_rejections = 0
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0, 5)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState.turn_effect_rules_enabled = true
	GameState.effect_pass.clear()
	GameState.phase = GameState.Phase.TURN_DRAW

func _set_slot(seat: int, slot: int, rank: String) -> void:
	var cid := str(GameState.players[seat].cards[slot])
	GameState.cards[cid].rank = rank
	GameState.cards[cid].value = KongRules.card_value(rank)

func _snapshot_hands() -> Dictionary:
	var out := {}
	for seat in GameState.turn_order:
		out[int(seat)] = (GameState.players[int(seat)].cards as Array).duplicate()
	return out

## 依次让等待者选择 slot 0，直到传递结束。
func _play_through_pass() -> void:
	var guard := 0
	while GameState.phase == GameState.Phase.EFFECT_PASS and guard < 12:
		var ep: Dictionary = HiddenInfo.snapshot_for(GameState, 0).get("effect_pass", {})
		var seat := int(ep.get("await_seat", -1))
		if seat < 0:
			break
		_pass_ids += 1
		GameState._server_effect_pass(seat, 0, "pass_%d" % _pass_ids)
		guard += 1

func _test_effect_reveal_phase() -> void:
	GameState._reset_match()
	GameState.turn_effect_rules_enabled = true
	_rejections = 0
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0, 5)
	GameState._server_initial_ready(0)
	_check("只有一人 Ready 不展示本局效果", GameState.phase == GameState.Phase.INITIAL_PEEK)
	GameState._server_initial_ready(1)
	_check("两人 Ready 仍不展示本局效果", GameState.phase == GameState.Phase.INITIAL_PEEK)
	GameState._server_initial_ready(2)
	_check("全员 Ready 后进入本局效果展示阶段", GameState.phase == GameState.Phase.EFFECT_REVEAL)
	_check("展示阶段有服务器 deadline", int(GameState.effect_reveal_deadline_ms) > 0)
	var snap := HiddenInfo.snapshot_for(GameState, 0)
	_check("快照公开展示 deadline", int(snap.get("effect_reveal_deadline_server_ms", 0)) > 0)
	GameState._server_take(0, "draw", "reveal_take")
	_check("展示阶段禁止抽牌", GameState.phase == GameState.Phase.EFFECT_REVEAL and GameState.pending_draw.is_empty())
	GameState._on_effect_reveal_timeout()
	_check("展示结束开始第一回合", GameState.phase == GameState.Phase.TURN_DRAW and GameState.turn_index == 1)
	_check("展示结束清 deadline", int(GameState.effect_reveal_deadline_ms) == 0)

func _test_effect_persists_per_match() -> void:
	_open()
	var id := GameState.turn_effect_id
	var ti := GameState.turn_index
	GameState.turn_effect_rules_enabled = false
	GameState._start_turn(0)
	GameState._start_turn(1)
	_check("同一局效果不重抽", GameState.turn_effect_id == id)
	_check("每回合仍推进 turn_index", GameState.turn_index == ti + 2)
	GameState.turn_effect_rules_enabled = true
	GameState._deal_next_match()
	_check("下一局结算/商店后重新抽取效果", GameState.turn_effect_id != id)

func _test_plus_one() -> void:
	_open()
	_set_slot(0, 2, "A")
	_set_slot(1, 2, "Q")
	_set_slot(2, 2, "10")
	_last_exchange = {}
	GameState._apply_plus_one(0)
	_check("左下角 +1 广播服务器事件", str(_last_exchange.get("kind", "")) == "plus_one" \
		and int(_last_exchange.get("seat", -1)) == 0 and int(_last_exchange.get("slot", -1)) == 2)
	_check("左下角 +1：只加当前玩家 A→2", str(GameState.cards[str(GameState.players[0].cards[2])].rank) == "2")
	_check("左下角 +1 同步分值", int(GameState.cards[str(GameState.players[0].cards[2])].value) == 2)
	_check("左下角 +1：其他玩家不动", str(GameState.cards[str(GameState.players[1].cards[2])].rank) == "Q" \
		and str(GameState.cards[str(GameState.players[2].cards[2])].rank) == "10")
	GameState._apply_plus_one(1)
	_check("左下角 +1：Q→A 循环", str(GameState.cards[str(GameState.players[1].cards[2])].rank) == "A")
	GameState._apply_plus_one(2)
	_check("左下角 +1：10→J", str(GameState.cards[str(GameState.players[2].cards[2])].rank) == "J")
	_set_slot(0, 2, "K")
	_last_exchange = {}
	GameState._apply_plus_one(0)
	_check("左下角 +1：K 不变", str(GameState.cards[str(GameState.players[0].cards[2])].rank) == "K")
	_check("左下角 +1：无数值变化不广播", _last_exchange.is_empty())
	var other_before := str(GameState.cards[str(GameState.players[0].cards[0])].rank)
	GameState._apply_plus_one(0)
	_check("左下角 +1：其它槽位不变", str(GameState.cards[str(GameState.players[0].cards[0])].rank) == other_before)
	# 换牌后按槽位继续生效：把另一张牌换进 slot 2，下个自己的回合 +1。
	var new_cid := str(GameState.players[0].cards[0])
	GameState.players[0].cards[2] = new_cid
	_set_slot(0, 2, "5")
	GameState._apply_plus_one(0)
	_check("左下角 +1：换牌后新牌继续 +1", str(GameState.cards[new_cid].rank) == "6")

func _test_six_replace_triggers_pass() -> void:
	_open()
	GameState.turn_effect_id = "six_swap"
	_set_slot(0, 0, "6")
	GameState._server_take(0, "draw", "six_take")
	GameState._server_replace(0, 0, "six_replace")
	_check("打出 6：进入 EFFECT_PASS", GameState.phase == GameState.Phase.EFFECT_PASS)
	_check("打出 6：广播右侧触发 UI", str(_last_exchange.get("kind", "")) == "effect_trigger" \
		and str((_last_exchange.get("card", {}) as Dictionary).get("rank", "")) == "6")
	var before := _snapshot_hands()
	_play_through_pass()
	_check("打出 6：广播 effect_pass 动画事件", str(_last_exchange.get("kind", "")) == "effect_pass")
	_check("打出 6：动画事件含 3 段移动", (_last_exchange.get("moves", []) as Array).size() == 3)
	var no_face := true
	for m in _last_exchange.get("moves", []):
		if (m as Dictionary).has("card") or (m as Dictionary).has("rank"):
			no_face = false
	_check("打出 6：动画事件不泄露牌面", no_face)
	_check("打出 6：传递后回到 TURN_DRAW", GameState.phase == GameState.Phase.TURN_DRAW)
	_check("打出 6：回合推进到下一人", GameState.current_player_id == 1)
	_check("打出 6：0→1", str(GameState.players[1].cards[0]) == str(before[0][0]))
	_check("打出 6：1→2", str(GameState.players[2].cards[0]) == str(before[1][0]))
	_check("打出 6：2→0", str(GameState.players[0].cards[0]) == str(before[2][0]))

func _test_six_power_red_joker() -> void:
	_open()
	GameState.turn_effect_id = "six_swap"
	GameState._server_take(0, "draw", "rj_take")
	var cid := str(GameState.pending_draw.card_id)
	GameState.cards[cid].rank = "JOKER"
	GameState.cards[cid].suit = "red"
	GameState.cards[cid].value = 0
	GameState._server_effect_power(0, "rj_power")
	_check("红 Joker 能力：进入 EFFECT_PASS", GameState.phase == GameState.Phase.EFFECT_PASS)
	_check("红 Joker 能力：广播右侧触发 UI", str(_last_exchange.get("kind", "")) == "effect_trigger" \
		and str((_last_exchange.get("card", {}) as Dictionary).get("rank", "")) == "JOKER" \
		and str((_last_exchange.get("card", {}) as Dictionary).get("suit", "")) == "red")
	_check("红 Joker 能力：待处理牌已清空", GameState.pending_draw.is_empty())
	_check("红 Joker 能力：红 Joker 进弃牌堆", GameState.discard_pile.has(cid))
	var before := _snapshot_hands()
	_play_through_pass()
	_check("红 Joker 能力：传递后回到 TURN_DRAW", GameState.phase == GameState.Phase.TURN_DRAW)
	_check("红 Joker 能力：回合推进到下一人", GameState.current_player_id == 1)
	_check("红 Joker 能力：仍顺时针传递", str(GameState.players[1].cards[0]) == str(before[0][0]))

func _test_six_power_action_ui() -> void:
	var st := {
		"phase": 3, "turn_effect": "six_swap", "viewer_id": 0, "current_player": 0,
		"pending": {"rank": "JOKER", "suit": "red"}, "run": {},
	}
	var acts := ActionModel.conditional_actions(st)
	var has_power := false
	for a in acts:
		if str(a.get("action", "")) == ActionModel.SIX_SWAP_POWER:
			has_power = true
	_check("UI：红 Joker 出现使用能力按钮", has_power)
	st["turn_effect"] = "none"
	acts = ActionModel.conditional_actions(st)
	has_power = false
	for a in acts:
		if str(a.get("action", "")) == ActionModel.SIX_SWAP_POWER:
			has_power = true
	_check("UI：非 6 效果不出现使用能力按钮", not has_power)
	st["turn_effect"] = "six_swap"
	st["pending"]["suit"] = "black"
	acts = ActionModel.conditional_actions(st)
	has_power = false
	for a in acts:
		if str(a.get("action", "")) == ActionModel.SIX_SWAP_POWER:
			has_power = true
	_check("UI：黑 Joker 不出现使用能力按钮", not has_power)
	st["pending"]["suit"] = "red"
	st["pending"]["source"] = "discard"
	acts = ActionModel.conditional_actions(st)
	has_power = false
	for a in acts:
		if str(a.get("action", "")) == ActionModel.SIX_SWAP_POWER:
			has_power = true
	_check("UI：弃牌堆取得的红 Joker 不出现使用能力按钮", not has_power)

func _test_six_not_trigger_other_effect() -> void:
	_open()
	GameState.turn_effect_id = "none"
	_set_slot(0, 0, "6")
	GameState._server_take(0, "draw", "no_take")
	GameState._server_replace(0, 0, "no_replace")
	_check("非 6 效果：打出 6 不进入 EFFECT_PASS", GameState.phase == GameState.Phase.TURN_DRAW and GameState.effect_pass.is_empty())
	_check("非 6 效果：正常推进回合", GameState.current_player_id == 1)

func _test_pass_offline_auto() -> void:
	_open()
	GameState.players[1].offline = true
	_check("传递：可启动", GameState._begin_effect_pass(0, true, Callable()))
	_check("传递离线：先等待发起者", int(HiddenInfo.snapshot_for(GameState, 0)["effect_pass"]["await_seat"]) == 0)
	GameState._server_effect_pass(0, 0, "o0")
	_check("传递离线：离线玩家自动选后轮到下一人", int(HiddenInfo.snapshot_for(GameState, 0)["effect_pass"]["await_seat"]) == 2)
	GameState._server_effect_pass(2, 0, "o2")
	_check("传递离线：不卡死", GameState.phase == GameState.Phase.TURN_DRAW)

func _test_pass_snapshot() -> void:
	_open()
	GameState._begin_effect_pass(0, true, Callable())
	var snap := HiddenInfo.snapshot_for(GameState, 1)
	var ep: Dictionary = snap.get("effect_pass", {})
	_check("快照：effect_pass 等待者", int(ep.get("await_seat", -1)) == 0)
	_check("快照：effect_pass 队列", (ep.get("queue", []) as Array) == [0, 1, 2])
	_check("快照：不泄露已选牌面", not ep.has("picks"))

func _test_pass_kick_removes_from_queue() -> void:
	_open()
	GameState._begin_effect_pass(0, true, Callable())
	GameState.players[1].offline = true
	GameState.players[1].peer_id = 0
	GameState._kick_offline_seat(1)
	_check("传递踢出：队列移除被踢者", (GameState.effect_pass.get("queue", []) as Array) == [0, 2])
	GameState._server_effect_pass(0, 0, "k0")
	GameState._server_effect_pass(2, 0, "k2")
	_check("传递踢出：剩余玩家可完成", GameState.phase == GameState.Phase.TURN_DRAW)

func _test_bomb_mark() -> void:
	_open()
	for cid in GameState.cards:
		GameState.cards[cid].erase("bomb")
		GameState.cards[cid].erase("bomb_turns")
	GameState._mark_bomb_cards()
	var bomb_ids: Array[String] = []
	for cid in GameState.cards:
		if bool(GameState.cards[cid].get("bomb", false)):
			bomb_ids.append(str(cid))
	_check("炸弹：标记 4 张", bomb_ids.size() == 4)
	var in_deck := 0
	for cid in bomb_ids:
		if GameState.deck.has(cid):
			in_deck += 1
	_check("炸弹：全部来自抽牌堆", in_deck == 4)
	var in_hand := false
	for seat in GameState.turn_order:
		for cid in GameState.players[int(seat)].cards:
			if bool(GameState.cards[str(cid)].get("bomb", false)):
				in_hand = true
	_check("炸弹：不会出现在开局手牌", not in_hand)

func _test_bomb_start_effect() -> void:
	_open()
	for cid in GameState.cards:
		GameState.cards[cid].erase("bomb")
		GameState.cards[cid].erase("bomb_turns")
	GameState.turn_effect_id = "bomb"
	GameState._apply_match_start_effect()
	var n := 0
	for cid in GameState.cards:
		if bool(GameState.cards[cid].get("bomb", false)):
			n += 1
	_check("炸弹：开局效果自动标记", n == 4)

func _test_bomb_countdown() -> void:
	_open()
	for cid in GameState.cards:
		GameState.cards[cid].erase("bomb")
		GameState.cards[cid].erase("bomb_turns")
	GameState._mark_bomb_cards()
	var bomb_id := ""
	for cid in GameState.cards:
		if bool(GameState.cards[cid].get("bomb", false)):
			bomb_id = str(cid)
			break
	GameState.deck.erase(bomb_id)
	GameState.players[0].cards[0] = bomb_id
	GameState.cards[bomb_id]["bomb_turns"] = 3
	var snap := HiddenInfo.snapshot_for(GameState, 1)
	_check("炸弹：槽位快照公开 bomb", bool(snap["players"][0]["slots"][0].get("bomb", false)))
	GameState._tick_bomb_cards(1)
	_check("炸弹：只结算持有者回合", int(GameState.cards[bomb_id].get("bomb_turns", 0)) == 3)
	GameState._tick_bomb_cards(0)
	_check("炸弹：第 1 回合后剩 2", int(GameState.cards[bomb_id].get("bomb_turns", 0)) == 2)
	GameState._tick_bomb_cards(0)
	_check("炸弹：第 2 回合后剩 1", int(GameState.cards[bomb_id].get("bomb_turns", 0)) == 1)
	GameState._tick_bomb_cards(0)
	_check("炸弹：第 3 回合后消失", str(GameState.players[0].cards[0]).is_empty())
	_check("炸弹：广播爆炸动画事件", str(_last_exchange.get("kind", "")) == "bomb_explode" \
		and int(_last_exchange.get("seat", -1)) == 0 \
		and (_last_exchange.get("slots", []) as Array).has(0))
	_check("炸弹：爆炸事件公开牌面", (_last_exchange.get("cards", []) as Array).size() == 1 \
		and not str(((_last_exchange.get("cards", []) as Array)[0] as Dictionary).get("rank", "")).is_empty())
	_check("炸弹：不进弃牌堆", not GameState.discard_pile.has(bomb_id))
	_check("炸弹：不进弃牌历史", not GameState.discard_history.has(bomb_id))
	_check("炸弹：标记清除", not bool(GameState.cards[bomb_id].get("bomb", false)))

func _test_dev_test_mode() -> void:
	# +1：开局所有玩家手牌全 A。
	GameState.dev_test_mode = true
	GameState.dev_test_effect = "plus_one"
	_open_peek()
	_check("测试模式：强制 +1 效果", GameState.turn_effect_id == "plus_one")
	var all_aces := true
	for seat in GameState.turn_order:
		for cid in GameState.players[int(seat)].cards:
			if str(GameState.cards[str(cid)].rank) != "A":
				all_aces = false
	_check("测试模式 +1：所有开局手牌为 A", all_aces)
	# 6：抽牌堆全 6（保留 Joker）。
	GameState.dev_test_effect = "six_swap"
	_open_peek()
	var deck_sixes := true
	for cid in GameState.deck:
		var rank := str(GameState.cards[str(cid)].rank)
		if rank != "JOKER" and rank != "6":
			deck_sixes = false
	_check("测试模式 6：抽牌堆全 6（Joker 保留原样）", deck_sixes)
	# 炸弹：抽牌堆全部带炸弹标记。
	GameState.dev_test_effect = "bomb"
	_open_peek()
	var all_bombs := not GameState.deck.is_empty()
	for cid in GameState.deck:
		if not bool(GameState.cards[str(cid)].get("bomb", false)):
			all_bombs = false
	_check("测试模式炸弹：抽牌堆全部带炸弹", all_bombs)
	# 关闭测试模式：不再改牌。
	GameState.dev_test_mode = false
	GameState.dev_test_effect = "plus_one"
	_open_peek()
	var first_cid := str(GameState.players[0].cards[0])
	GameState.cards[first_cid].rank = "K"
	GameState._apply_test_mode_setup()
	_check("关闭测试模式：不改手牌", str(GameState.cards[first_cid].rank) == "K")
	GameState.dev_test_effect = ""
	GameState.dev_test_mode = false

func _test_ui_badges() -> void:
	var view: CardView = load("res://scenes/ui/card.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	view.setup({"rank": "A", "suit": "♠", "value": 1, "bomb": true})
	_check("2D 卡牌炸弹角标", view.has_bomb())
	view.setup({"rank": "A", "suit": "♠", "value": 1})
	_check("2D 卡牌无炸弹角标", not view.has_bomb())
	view.queue_free()
	var block := CardBlock.new()
	add_child(block)
	await get_tree().process_frame
	block.setup({"card": {}, "bomb": true})
	_check("3D 卡牌炸弹角标", block.has_bomb())
	block.setup({"card": {}, "bomb": false})
	_check("3D 卡牌无炸弹角标", not block.has_bomb())
	block.queue_free()

func _test_rules_disabled() -> void:
	_open()
	GameState.turn_effect_rules_enabled = false
	GameState.turn_effect_id = "six_swap"
	GameState._start_turn(0)
	_check("关闭规则：不进入 EFFECT_PASS", GameState.phase == GameState.Phase.TURN_DRAW and GameState.effect_pass.is_empty())
	GameState.turn_effect_rules_enabled = true
