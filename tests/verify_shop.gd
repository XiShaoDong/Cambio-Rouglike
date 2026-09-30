extends Node
## headless 单元测试：商店固定价购买（每人限购 1 件，同件先到先得）

var failures := 0
var checks := 0
var _rejections := 0

func _ready() -> void:
	GameState.command_rejected.connect(_count_reject)
	await _test_relic_defs()
	await _test_shop_flow()
	await _test_shop_snapshot()
	await _test_buy_valid()
	await _test_buy_invalid()
	await _test_sold_first_come()
	await _test_all_done_advance()
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

func _test_relic_defs() -> void:
	var pool: Array = Relics.pool()
	_check("遗物池含 v1 两件", pool.size() == 2)
	_check("遗物字段齐全", str(pool[0].get("id", "")) != "" and str(pool[0].get("name", "")) != "")
	_check("遗物固定价 50", int(pool[0].get("price", 0)) == 50 and int(pool[1].get("price", 0)) == 50)
	_check("def_by_id 反查", Relics.def_by_id(Relics.JOKER_TRANSFORM_ID).get("name", "") != "")

func _test_shop_flow() -> void:
	_open_with_finish(5)
	_check("非把末结算后停在 GAME_OVER", GameState.phase == GameState.Phase.GAME_OVER)
	_check("衔接 Timer 已启动", not GameState.series_timer.is_stopped())
	GameState._on_series_auto_advance()
	_check("衔接进入商店阶段", GameState.phase == GameState.Phase.SHOP)
	_check("商店清空上一轮结果", GameState.shop_result.is_empty())
	var offers: Array = GameState.shop.get("offers", [])
	_check("商店 offer 数 <= 3 且 >0", offers.size() > 0 and offers.size() <= 3)
	GameState._server_shop_skip(0)
	GameState._server_shop_skip(1)
	GameState._server_shop_skip(2)
	_check("全员跳过后进入下一局 match_number 递增", GameState.match_number == 2 and GameState.phase == GameState.Phase.INITIAL_PEEK)

func _test_shop_snapshot() -> void:
	_open_with_finish(5)
	GameState._on_series_auto_advance()
	var snap: Dictionary = GameState._snapshot_for(0)
	_check("快照含商店 offers", not snap.get("shop", {}).is_empty())
	var offers: Array = snap.get("shop", {}).get("offers", [])
	var ok := offers.size() > 0
	for offer in offers:
		if not (offer as Dictionary).has("price") or not (offer as Dictionary).has("sold_by"):
			ok = false
	_check("快照 offer 含 price/sold_by", ok)

func _test_buy_valid() -> void:
	_open_with_finish(5)
	GameState._on_series_auto_advance()
	GameState.players[0].currency = 100
	var relic_id: String = str(GameState.shop.offers[0].relic_id)
	GameState._server_shop_buy(0, 0)
	_check("购买扣款 50", int(GameState.players[0].currency) == 50)
	_check("遗物入库且记持有者", GameState.run_state.relics.has(relic_id) and int(GameState.run_state.relic_owners[relic_id]) == 0)
	_check("该件标记售出", GameState.shop.sold.has(0))
	_check("本人标记完成", GameState.shop.done.has(0))
	_check("未全员完成仍停留商店", GameState.phase == GameState.Phase.SHOP)

func _test_buy_invalid() -> void:
	_open_with_finish(5)
	GameState._on_series_auto_advance()
	GameState._server_shop_buy(0, 99)
	_check("offer 越界被拒", _rejections == 1)
	GameState.players[0].currency = 10
	GameState._server_shop_buy(0, 0)
	_check("货币不足被拒", _rejections == 2)
	GameState.players[0].currency = 100
	GameState._server_shop_buy(0, 0)
	GameState._server_shop_buy(0, 1)
	_check("已购买后再买被拒(限购1)", _rejections == 3)

func _test_sold_first_come() -> void:
	_open_with_finish(5)
	GameState._on_series_auto_advance()
	GameState.players[0].currency = 100
	GameState.players[1].currency = 100
	GameState._server_shop_buy(0, 0)
	GameState._server_shop_buy(1, 0)  # 同件已售出（seat1 非 host，拒绝走 RPC，改断言状态）
	_check("同件先到先得(后到未成交)", int(GameState.shop.sold[0]) == 0 and not GameState.shop.done.has(1))
	GameState._server_shop_buy(1, 1)  # seat1 买另一件
	_check("他人可买另一件", int(GameState.shop.sold.get(1, -1)) == 1)

func _test_all_done_advance() -> void:
	_open_with_finish(5)
	GameState._on_series_auto_advance()
	GameState.players[0].currency = 100
	GameState._server_shop_buy(0, 0)
	GameState._server_shop_skip(1)
	GameState._server_shop_skip(2)
	_check("全员完成后进入下一局", GameState.phase == GameState.Phase.INITIAL_PEEK and GameState.match_number == 2)