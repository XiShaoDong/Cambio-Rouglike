extends Node
## headless 单元测试：商店 Phase 1（每人独立 2 格 / $10 刷新 / 锁跨商店 / 个人遗物栏）

var failures := 0
var checks := 0
var _rejections := 0

func _ready() -> void:
	GameState.turn_effect_rules_enabled = false
	GameState.command_rejected.connect(_count_reject)
	await _test_relic_defs()
	await _test_shop_flow()
	await _test_shop_snapshot()
	await _test_buy_valid()
	await _test_buy_invalid()
	await _test_independent_shops()
	await _test_refresh()
	await _test_refresh_invalid()
	await _test_lock_persist_across_shop()
	await _test_buy_clears_lock()
	await _test_all_done_advance()
	_test_over_hand_advance()
	var status: String = " (FAILURES!)" if failures > 0 else ""
	print("=== SHOP RESULT: %d/%d passed%s ===" % [checks - failures, checks, status])
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

func _open_with_finish(limit := 5) -> void:
	GameState._reset_match()
	_rejections = 0
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0, limit)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._finish_game()

func _open_shop() -> void:
	_open_with_finish(5)
	GameState._on_series_auto_advance()

func _offers(seat: int) -> Array:
	return (GameState.shop.get("seats", {}).get(seat, {}) as Dictionary).get("offers", [])

func _test_relic_defs() -> void:
	var pool: Array = Relics.pool()
	_check("遗物池含 14 件", pool.size() == 14)
	var ids := {}
	var fields_ok := true
	for relic in pool:
		var id := str(relic.get("id", ""))
		if id.is_empty() or ids.has(id):
			fields_ok = false
		ids[id] = true
		if str(relic.get("name", "")).is_empty() or str(relic.get("desc", "")).is_empty() \
				or str(relic.get("glyph", "")).is_empty():
			fields_ok = false
	_check("遗物 id 唯一且 name/desc/glyph 齐全", fields_ok)
	_check("遗物固定价 50", int(pool[0].get("price", 0)) == 50)
	_check("刷新价 10", Relics.SHOP_REFRESH_COST == 10)
	_check("def_by_id 反查", Relics.def_by_id(Relics.JOKER_TRANSFORM_ID).get("name", "") != "")
	_check("glyph_for 占位字符", Relics.glyph_for("relic_tax_hand") == "-1")

func _test_shop_flow() -> void:
	_open_shop()
	_check("衔接进入商店阶段", GameState.phase == GameState.Phase.SHOP)
	_check("商店清空上一轮结果", GameState.shop_result.is_empty())
	_check("每人 2 个货位", _offers(0).size() == 2 and _offers(1).size() == 2 and _offers(2).size() == 2)
	GameState._server_shop_skip(0)
	GameState._server_shop_skip(1)
	GameState._server_shop_skip(2)
	_check("全员跳过后进入下一局 match_number 递增", GameState.match_number == 2 and GameState.phase == GameState.Phase.INITIAL_PEEK)

func _test_shop_snapshot() -> void:
	_open_shop()
	var snap: Dictionary = GameState._snapshot_for(0)
	var shop: Dictionary = snap.get("shop", {})
	_check("快照含商店 offers", not shop.is_empty())
	var offers: Array = shop.get("offers", [])
	var ok := offers.size() == 2
	for offer in offers:
		var o: Dictionary = offer
		if not o.has("price") or not o.has("locked") or not o.has("id"):
			ok = false
	_check("快照 offer 含 id/price/locked", ok)
	_check("快照含刷新价与可用性", int(shop.get("refresh_cost", 0)) == 10 and bool(shop.get("can_refresh", false)))
	var player_relics_ok := true
	for p in snap.get("players", []):
		if (p.get("relics", []) as Array).size() != 3:
			player_relics_ok = false
	_check("快照 players[].relics 固定 3 格", player_relics_ok)
	_check("快照不泄露他人商店锁", not (snap.get("run", {}) as Dictionary).has("shop_locks"))

func _test_buy_valid() -> void:
	_open_shop()
	GameState.players[0].currency = 100
	var relic_id: String = str((_offers(0)[0] as Dictionary).get("relic_id", ""))
	GameState._server_shop_buy(0, 0)
	_check("购买扣款 50", int(GameState.players[0].currency) == 50)
	_check("遗物进入个人遗物栏", relic_id in (GameState.run_state["relic_inventories"].get(0, []) as Array))
	_check("本人已购买遗物", bool(GameState._shop_seat(0).get("relic_bought", false)))
	_check("买遗物不自动结束商店", not GameState._shop_submitted(0) and GameState.phase == GameState.Phase.SHOP)
	_check("购买结果公开", not GameState.shop_result.is_empty())

func _test_buy_invalid() -> void:
	_open_shop()
	GameState._server_shop_buy(0, 99)
	_check("offer 越界被拒", _rejections == 1)
	GameState.players[0].currency = 10
	GameState._server_shop_buy(0, 0)
	_check("货币不足被拒", _rejections == 2)
	GameState.players[0].currency = 100
	GameState._server_shop_buy(0, 0)
	GameState._server_shop_buy(0, 1)
	_check("已购买后再买被拒(限购1)", _rejections == 3)
	# 遗物栏满：直接塞 3 件后购买被拒
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(0, 5)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._finish_game()
	GameState._on_series_auto_advance()
	_rejections = 0
	GameState.run_state["relic_inventories"][0] = ["relic_tax_hand", "relic_odd_hand", "relic_duplicate"]
	GameState.players[0].currency = 100
	GameState._server_shop_buy(0, 0)
	_check("遗物栏满购买被拒", _rejections == 1)

func _test_independent_shops() -> void:
	_open_shop()
	GameState.players[0].currency = 100
	GameState.players[1].currency = 100
	var id0: String = str((_offers(0)[0] as Dictionary).get("relic_id", ""))
	GameState._server_shop_buy(0, 0)
	GameState._server_shop_buy(1, 0)
	_check("不同玩家可买各自货位", 0 in GameState.run_state["relic_inventories"] and 1 in GameState.run_state["relic_inventories"])
	_check("个人购买互不影响", bool(GameState._shop_seat(0).get("relic_bought", false)) \
		and bool(GameState._shop_seat(1).get("relic_bought", false)) and not GameState._shop_submitted(2))
	_check("seat0 买到自己的饰品", id0 in (GameState.run_state["relic_inventories"][0] as Array))

func _test_refresh() -> void:
	_open_shop()
	GameState.players[0].currency = 100
	var before_locked := str((_offers(0)[0] as Dictionary).get("relic_id", ""))
	GameState._server_shop_lock(0, 0, true)
	GameState._server_shop_refresh(0)
	_check("刷新扣 10", int(GameState.players[0].currency) == 90)
	_check("锁定货位不刷新", str((_offers(0)[0] as Dictionary).get("relic_id", "")) == before_locked \
		and bool((_offers(0)[0] as Dictionary).get("locked", false)))
	_check("未锁货位仍可购买", not bool((_offers(0)[1] as Dictionary).get("locked", false)))
	# 只锁一格仍可刷新
	var snap := GameState._snapshot_for(0)
	_check("快照 can_refresh=true（仅一格锁）", bool(snap.get("shop", {}).get("can_refresh", false)))

func _test_refresh_invalid() -> void:
	_open_shop()
	GameState.players[0].currency = 100
	GameState._server_shop_lock(0, 0, true)
	GameState._server_shop_lock(0, 1, true)
	_rejections = 0
	GameState._server_shop_refresh(0)
	_check("两格全锁不能刷新", _rejections == 1)
	GameState._server_shop_lock(0, 0, false)
	GameState.players[0].currency = 5
	_rejections = 0
	GameState._server_shop_refresh(0)
	_check("货币不足不能刷新", _rejections == 1)
	GameState.players[0].currency = 100
	GameState._server_shop_skip(0)
	_rejections = 0
	GameState._server_shop_refresh(0)
	_check("已结束商店不能刷新", _rejections == 1)

func _test_lock_persist_across_shop() -> void:
	_open_shop()
	var locked_id := str((_offers(0)[1] as Dictionary).get("relic_id", ""))
	GameState._server_shop_lock(0, 1, true)
	GameState._server_shop_skip(0)
	GameState._server_shop_skip(1)
	GameState._server_shop_skip(2)
	# 下一局直接结束，再进商店
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._finish_game()
	GameState._on_series_auto_advance()
	var offer: Dictionary = _offers(0)[1]
	_check("锁跨商店保留在原货位", str(offer.get("relic_id", "")) == locked_id and bool(offer.get("locked", false)))

func _test_buy_clears_lock() -> void:
	_open_shop()
	GameState.players[0].currency = 100
	var relic_id := str((_offers(0)[0] as Dictionary).get("relic_id", ""))
	GameState._server_shop_lock(0, 0, true)
	GameState._server_shop_buy(0, 0)
	var locks: Dictionary = GameState.run_state.get("shop_locks", {}).get(0, {})
	_check("买走该件清除该槽锁", not locks.has(0))
	_check("买到的正是锁定件", relic_id in (GameState.run_state["relic_inventories"][0] as Array))

func _test_all_done_advance() -> void:
	_open_shop()
	GameState.players[0].currency = 100
	GameState._server_shop_buy(0, 0)
	GameState._server_shop_skip(0)
	GameState._server_shop_skip(1)
	GameState._server_shop_skip(2)
	_check("全员完成后进入下一局", GameState.phase == GameState.Phase.INITIAL_PEEK and GameState.match_number == 2)

## R-07 手牌超限结束（另一条 GAME_OVER 入口）也必须启动"结算→商店"自动推进，否则卡结算。
func _test_over_hand_advance() -> void:
	GameState._reset_match()
	_rejections = 0
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(0, 5)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._finish_game_over_hand(0)
	_check("R-07 超限结束停在 GAME_OVER", GameState.phase == GameState.Phase.GAME_OVER)
	_check("R-07 结束时衔接 Timer 已启动", not GameState.series_timer.is_stopped())
	GameState._on_series_auto_advance()
	_check("R-07 结束后可进入商店", GameState.phase == GameState.Phase.SHOP)
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(0, 5)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState.match_number = int(GameState.run_state.get("match_limit", 5))
	GameState._finish_game_over_hand(0)
	_check("把末 R-07 带系列赛总结", not (GameState.last_result.get("series", {}) as Dictionary).is_empty())
	_check("把末 R-07 不启动商店 timer", GameState.series_timer.is_stopped())
