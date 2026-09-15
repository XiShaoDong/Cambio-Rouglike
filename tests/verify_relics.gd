extends Node
## headless 单元测试：遗物效果 v1（Milestone 4）
## 覆盖：防守护盾（局开始随机护盾格并消耗/贴牌与 J/Q 交换免疫/快照标记/无遗物 no-op）
##      + Joker 变换（抽到 Joker 可选变换为任意牌/未变换分值 +2/已变换清除加成）。

var failures := 0
var checks := 0
var _rejections := 0

func _ready() -> void:
	GameState.command_rejected.connect(_count_reject)
	await _test_guard_apply()
	await _test_guard_slap()
	await _test_guard_j_swap()
	await _test_guard_q_start()
	await _test_guard_q_exchange()
	await _test_guard_visible()
	await _test_no_relic_noop()
	await _test_joker_transform()
	await _test_joker_penalty()
	await _test_joker_transform_clears_penalty()
	var status: String = " (FAILURES!)" if failures > 0 else ""
	print("=== RELICS RESULT: %d/%d passed%s ===" % [checks - failures, checks, status])
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

## 3 人开局；seat_shield（默认房主 0）持防守护盾。返回后 phase=TURN_DRAW（已押注）。
func _open_shield(seat_shield := 0) -> void:
	GameState._reset_match()
	_rejections = 0
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState.run_state["relics"][Relics.GUARD_SHIELD_ID] = Relics.def_by_id(Relics.GUARD_SHIELD_ID)
	GameState.run_state["relic_owners"][Relics.GUARD_SHIELD_ID] = seat_shield
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._server_bet(0, KongRules.MIN_BET)
	GameState._server_bet(1, KongRules.MIN_BET)
	GameState._server_bet(2, KongRules.MIN_BET)

## 当前玩家 seat 抽一张并强制 pending 为该 rank（走 _server_take 保持合法状态机）。
func _draw_rank(seat: int, rank: String, action_id: String) -> void:
	GameState._server_take(seat, "draw", action_id)
	var cid: String = str(GameState.pending_draw.card_id)
	GameState.cards[cid].rank = rank
	GameState.cards[cid].value = KongRules.card_value(rank)

func _test_guard_apply() -> void:
	_open_shield(0)
	_check("护盾在下一局开局生效(随机选格)", GameState.players[0].protected_slot >= 0 and GameState.players[0].protected_slot < GameState.players[0].cards.size())
	_check("护盾一局后消耗", not GameState.run_state.relics.has(Relics.GUARD_SHIELD_ID))
	_check("他人无护盾", int(GameState.players[1].protected_slot) == -1 and int(GameState.players[2].protected_slot) == -1)

func _test_guard_slap() -> void:
	_open_shield(0)
	# 开一个贴牌窗口：seat0 抽牌弃掉
	GameState._server_take(0, "draw", "s1")
	GameState._server_discard_draw(0, "s2")
	var protected_slot: int = GameState.players[0].protected_slot
	var protected_card: String = GameState.players[0].cards[protected_slot]
	# seat1 贴 seat0 的受护盾格（非 host 的拒绝走 RPC 无法在单进程断言信号，改用可观测状态）
	GameState._server_slap(1, 0, protected_slot, "s3")
	_check("贴护盾格被拒(槽位未动/未入收集/窗口仍开)",
		GameState.players[0].cards[protected_slot] == protected_card
		and GameState.slap_collect.is_empty() and GameState.slap_open)
	# 贴非护盾格 → 不被 PROTECTED 拒绝（进入收集窗或罚牌，必有结果）
	var hand_before := GameState._hand_count(1)
	GameState._server_slap(1, 0, (protected_slot + 1) % GameState.players[0].cards.size(), "s4")
	_check("贴非护盾格不因 PROTECTED 被拒(进入判定)", GameState._hand_count(1) != hand_before or not GameState.slap_collect.is_empty())

func _test_guard_j_swap() -> void:
	_open_shield(1)
	var protected_slot: int = GameState.players[1].protected_slot
	# seat0 抽 J 后对 seat1 的护盾格发动 J（target_slot 护盾）→ 拒绝
	_draw_rank(0, "J", "j0")
	GameState._server_use_ability(0, {"target": 1, "own_slot": 0, "target_slot": protected_slot}, "j1")
	_check("J 盲换指定护盾格被拒", _rejections == 1 and GameState.phase == GameState.Phase.TURN_DECISION)
	# 非护盾格（另一格）→ 不被 PROTECTED 拒绝
	var before := _rejections
	GameState._server_use_ability(0, {"target": 1, "own_slot": 0, "target_slot": (protected_slot + 1) % 4}, "j2")
	_check("J 盲换非护盾格不因 PROTECTED 被拒", _rejections == before)

func _test_guard_q_start() -> void:
	_open_shield(1)
	var protected_slot: int = GameState.players[1].protected_slot
	_draw_rank(0, "Q", "q0")
	GameState._server_use_ability(0, {"target": 1, "target_slot": protected_slot}, "q1")
	_check("Q 指定护盾格被拒", _rejections == 1 and GameState.phase == GameState.Phase.TURN_DECISION)

func _test_guard_q_exchange() -> void:
	_open_shield(1)
	var protected_slot: int = GameState.players[1].protected_slot
	# 手动构造 Q 上下文指向护盾格（已按新流程查看自己牌），直接测交换分支的护盾拒绝
	GameState.q_context = {"actor": 0, "target": 1, "target_slot": protected_slot, "own_viewed": true, "own_slot": 0}
	GameState.phase = GameState.Phase.Q_DECISION
	GameState._server_q_decision(0, true, 0, "qe1")
	_check("Q 交换指定护盾格被拒", _rejections == 1)

func _test_guard_visible() -> void:
	_open_shield(0)
	var snap: Dictionary = GameState._snapshot_for(0)
	var protected_slot: int = GameState.players[0].protected_slot
	var found := false
	for p in snap.players:
		if int(p.id) == 0:
			for i in p.slots.size():
				if bool(p.slots[i].get("protected", false)) and i == protected_slot:
					found = true
	_check("快照标记护盾槽", found)

func _test_no_relic_noop() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(0)
	_check("无遗物时无护盾", int(GameState.players[0].protected_slot) == -1)

## 2 人开局；transform=true 时 seat0 持 Joker 变换遗物。返回后 phase=TURN_DECISION、pending 为 JOKER。
func _open_joker(transform: bool) -> void:
	GameState._reset_match()
	_rejections = 0
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	if transform:
		GameState.run_state["relics"][Relics.JOKER_TRANSFORM_ID] = Relics.def_by_id(Relics.JOKER_TRANSFORM_ID)
		GameState.run_state["relic_owners"][Relics.JOKER_TRANSFORM_ID] = 0
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_bet(0, KongRules.MIN_BET)
	GameState._server_bet(1, KongRules.MIN_BET)
	GameState._server_take(0, "draw", "jt0")
	var cid: String = str(GameState.pending_draw.card_id)
	GameState.cards[cid].rank = "JOKER"
	GameState.cards[cid].value = 0

func _test_joker_transform() -> void:
	_open_joker(true)
	GameState._server_joker_transform(0, "7", "♠", "jt-1")
	var pending: Dictionary = GameState.pending_draw
	_check("Joker 变换生效(7♠)", str(GameState.cards[pending.card_id].rank) == "7" and str(GameState.cards[pending.card_id].suit) == "♠")
	_check("变换后按新点数计值", int(GameState.cards[pending.card_id].value) == 7)
	# 无遗物者变换被拒
	_open_joker(false)
	GameState._server_joker_transform(0, "7", "♠", "jt-2")
	_check("无遗物者变换被拒", _rejections == 1 and str(GameState.cards[GameState.pending_draw.card_id].rank) == "JOKER")
	# 已变换后再变换被拒
	_open_joker(true)
	GameState._server_joker_transform(0, "A", "♠", "jt-3")
	GameState._server_joker_transform(0, "2", "♠", "jt-4")
	_check("已变换后不能再次变换", _rejections == 1 and str(GameState.cards[GameState.pending_draw.card_id].rank) == "A")

func _test_joker_penalty() -> void:
	# seat0 持 Joker 遗物且手里留一张 JOKER → 结算分值 +2（他人视角同值计算无加成）
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState.run_state["relics"][Relics.JOKER_TRANSFORM_ID] = Relics.def_by_id(Relics.JOKER_TRANSFORM_ID)
	GameState.run_state["relic_owners"][Relics.JOKER_TRANSFORM_ID] = 0
	GameState._server_start_match(0)
	GameState.players[0].cards = ["ja"]
	GameState.cards["ja"] = {"id": "ja", "rank": "JOKER", "suit": "black", "value": 0}
	GameState.players[1].cards = ["jb"]
	GameState.cards["jb"] = {"id": "jb", "rank": "5", "suit": "♠", "value": 5}
	var val: int = GameState._relic_card_value(0, "ja")
	_check("持遗物 Joker 分值+2", val == 2)
	_check("他人 Joker 分值不变", GameState._relic_card_value(1, "ja") == 0)
	var ranking: Array = GameState._calculate_ranking()
	_check("排名含 Joker+2", int(ranking[0].score) == 2 or int(ranking[1].score) == 2)

func _test_joker_transform_clears_penalty() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState.run_state["relics"][Relics.JOKER_TRANSFORM_ID] = Relics.def_by_id(Relics.JOKER_TRANSFORM_ID)
	GameState.run_state["relic_owners"][Relics.JOKER_TRANSFORM_ID] = 0
	GameState._server_start_match(0)
	GameState.players[0].cards = ["jc"]
	GameState.cards["jc"] = {"id": "jc", "rank": "7", "suit": "♠", "value": 7}
	GameState.players[1].cards = ["jd"]
	GameState.cards["jd"] = {"id": "jd", "rank": "5", "suit": "♠", "value": 5}
	_check("已变换的牌按新点数计(非JOKER无+2)", GameState._relic_card_value(0, "jc") == 7)