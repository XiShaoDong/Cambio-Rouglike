extends Node
## headless 测试：道具卡数据/商店货架/私有库存/购买/刷新/锁/结束商店/使用。

var failures := 0
var checks := 0
var _rejections := 0
var _last_item_event: Dictionary = {}

func _ready() -> void:
	GameState.turn_effect_rules_enabled = false
	GameState.command_rejected.connect(_count_reject)
	GameState.item_card_used.connect(func(d: Dictionary): _last_item_event = d)
	_test_defs()
	await _test_shop_offers_private()
	await _test_buy_and_finish()
	await _test_card_refresh_lock()
	await _test_lock_persist_and_buy_clears()
	await _test_use_item_card()
	var status: String = " (FAILURES!)" if failures > 0 else ""
	print("=== ITEM CARDS RESULT: %d/%d passed%s ===" % [checks - failures, checks, status])
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

func _open_shop() -> void:
	GameState._reset_match()
	_rejections = 0
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0, 5)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._finish_game()
	GameState._on_series_auto_advance()

func _cards(seat: int) -> Array:
	return (GameState.shop.get("seats", {}).get(seat, {}) as Dictionary).get("card_offers", [])

func _test_defs() -> void:
	var pool: Array = ItemCards.pool()
	_check("道具卡池 3 张", pool.size() == 3)
	var ids := {}
	var ok := true
	for card in pool:
		var id := str(card.get("id", ""))
		if id.is_empty() or ids.has(id):
			ok = false
		ids[id] = true
		if str(card.get("name", "")).is_empty() or str(card.get("desc", "")).is_empty() \
				or str(card.get("glyph", "")).is_empty():
			ok = false
	_check("道具卡 id 唯一 + 字段齐全", ok)
	_check("道具卡统一 $50", int(pool[0].get("price", 0)) == 50)
	_check("Demo 卡都可选对手目标", ItemCards.def_by_id(ItemCards.FATE_PLUS2_ID).get("target_mode") == ItemCards.TARGET_OPPONENT \
		and ItemCards.def_by_id(ItemCards.INTERFERE_ID).get("target_mode") == ItemCards.TARGET_OPPONENT \
		and ItemCards.def_by_id(ItemCards.CHARM_ID).get("target_mode") == ItemCards.TARGET_OPPONENT)

func _test_shop_offers_private() -> void:
	_open_shop()
	_check("每人 3 张卡牌货位", _cards(0).size() == 3 and _cards(1).size() == 3)
	var snap0 := GameState._snapshot_for(0)
	var snap1 := GameState._snapshot_for(1)
	_check("快照含 card_offers", (snap0.get("shop", {}).get("card_offers", []) as Array).size() == 3)
	_check("快照含卡牌刷新价", int(snap0.get("shop", {}).get("card_refresh_cost", 0)) == ItemCards.REFRESH_COST)
	_check("快照 item_cards 私有", (snap0.get("item_cards", []) as Array).is_empty() and (snap1.get("item_cards", []) as Array).is_empty())
	var run0: Dictionary = snap0.get("run", {})
	_check("run 不含私有 item 字段", not run0.has("item_inventories") and not run0.has("item_locks"))

func _test_buy_and_finish() -> void:
	_open_shop()
	GameState.players[0].currency = 100
	var card_id := str((_cards(0)[0] as Dictionary).get("item_id", ""))
	GameState._server_shop_buy_card(0, 0)
	_check("买卡扣 50", int(GameState.players[0].currency) == 50)
	_check("卡进入个人卡牌栏", card_id in (GameState.run_state["item_inventories"].get(0, []) as Array))
	_check("本店已买卡", bool(GameState._shop_seat(0).get("card_bought", false)))
	_check("买卡不自动结束商店", not GameState._shop_submitted(0))
	_rejections = 0
	GameState._server_shop_buy_card(0, 1)
	_check("同一商店不能买第二张", _rejections == 1)
	GameState._server_shop_skip(1)
	GameState._server_shop_skip(2)
	_check("其他人结束后仍停商店", GameState.phase == GameState.Phase.SHOP)
	GameState._server_shop_skip(0)
	_check("全员结束后开下一局", GameState.phase == GameState.Phase.INITIAL_PEEK and GameState.match_number == 2)

func _test_card_refresh_lock() -> void:
	_open_shop()
	GameState.players[0].currency = 100
	var locked_id := str((_cards(0)[0] as Dictionary).get("item_id", ""))
	GameState._server_shop_card_lock(0, 0, true)
	GameState._server_shop_card_refresh(0)
	_check("卡牌刷新扣 10", int(GameState.players[0].currency) == 90)
	_check("锁定卡位不刷新", str((_cards(0)[0] as Dictionary).get("item_id", "")) == locked_id \
		and bool((_cards(0)[0] as Dictionary).get("locked", false)))
	_check("未锁卡位仍可买", not bool((_cards(0)[1] as Dictionary).get("locked", false)))
	var snap := GameState._snapshot_for(0)
	_check("快照 card_can_refresh", bool(snap.get("shop", {}).get("card_can_refresh", false)))
	GameState._server_shop_card_lock(0, 1, true)
	GameState._server_shop_card_lock(0, 2, true)
	_rejections = 0
	GameState._server_shop_card_refresh(0)
	_check("三格全锁不能刷新", _rejections == 1)

func _test_lock_persist_and_buy_clears() -> void:
	_open_shop()
	var locked_id := str((_cards(0)[2] as Dictionary).get("item_id", ""))
	GameState._server_shop_card_lock(0, 2, true)
	GameState._server_shop_skip(0)
	GameState._server_shop_skip(1)
	GameState._server_shop_skip(2)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._finish_game()
	GameState._on_series_auto_advance()
	_check("卡牌锁跨商店保留", str((_cards(0)[2] as Dictionary).get("item_id", "")) == locked_id \
		and bool((_cards(0)[2] as Dictionary).get("locked", false)))
	GameState.players[0].currency = 100
	GameState._server_shop_buy_card(0, 2)
	_check("买走锁定卡清锁", not (GameState.run_state.get("item_locks", {}).get(0, {}) as Dictionary).has(2))

func _test_use_item_card() -> void:
	GameState._reset_match()
	_rejections = 0
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState.run_state["item_inventories"][0] = [ItemCards.INTERFERE_ID, ItemCards.FATE_PLUS2_ID, ItemCards.CHARM_ID]
	GameState._server_start_match(0, 5)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	_last_item_event = {}
	GameState._server_use_item_card(0, 0, 0, "ic1")
	_check("对手卡非法目标被拒", _rejections == 1)
	GameState._server_use_item_card(0, 0, 1, "ic2")
	_check("对手卡使用成功并消耗", not (GameState.run_state["item_inventories"][0] as Array).has(ItemCards.INTERFERE_ID))
	_check("使用后广播卡面事件", str(_last_item_event.get("card", {}).get("id", "")) == ItemCards.INTERFERE_ID \
		and int(_last_item_event.get("target", -1)) == 1 and int(_last_item_event.get("actor", -1)) == 0)
	_rejections = 0
	GameState._server_use_item_card(0, 0, 1, "ic3")
	_check("每回合只能使用一张", _rejections == 1)
	# 下一回合：所有 Demo 卡都手动选对手目标
	GameState.current_player_id = 0
	GameState._start_turn(0)
	_last_item_event = {}
	GameState._server_use_item_card(0, 0, 1, "ic4")
	_check("Demo 卡可选对手目标", int(_last_item_event.get("target", -1)) == 1)
	GameState.current_player_id = 0
	GameState._start_turn(0)
	_last_item_event = {}
	GameState._server_use_item_card(0, 0, 2, "ic5")
	_check("第三张 Demo 卡可选另一对手", int(_last_item_event.get("target", -1)) == 2)
	_check("道具卡全部消耗", (GameState.run_state["item_inventories"][0] as Array).is_empty())
	var snap := GameState._snapshot_for(0)
	_check("快照 item_card_used 本回合为真", bool(snap.get("item_card_used", false)))
