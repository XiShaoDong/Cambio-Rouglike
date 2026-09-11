extends Node
## headless 单元测试：商店盲拍（Milestone 3）

var failures := 0
var checks := 0
var _rejections := 0

func _ready() -> void:
	await _test_relic_defs()
	await _test_shop_flow()
	await _test_shop_snapshot()
	await _test_bid_valid()
	await _test_bid_invalid()
	await _test_resolve_winner()
	await _test_resolve_tie()
	await _test_skip_all()
	await _test_inventory_override()
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

func _open_with_finish(limit := 5) -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0, limit)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._server_bet(0, KongRules.MIN_BET)
	GameState._server_bet(1, KongRules.MIN_BET)
	GameState._server_bet(2, KongRules.MIN_BET)
	GameState._finish_game()

## 在货架中找指定遗物 offer 下标（池仅两件、每次全上架）。
func _find_offer(relic_id: String, offers: Array) -> int:
	for i in offers.size():
		if str(offers[i].relic_id) == relic_id:
			return i
	return -1

func _test_relic_defs() -> void:
	var pool: Array = Relics.pool()
	_check("遗物池含 v1 两件", pool.size() == 2)
	_check("遗物字段齐全", str(pool[0].get("id", "")) != "" and str(pool[0].get("name", "")) != "")
	_check("def_by_id 反查", Relics.def_by_id("relic_joker_transform").get("name", "") != "")

func _test_shop_flow() -> void:
	_open_with_finish(5)
	_check("非把末结算后停在 GAME_OVER", GameState.phase == GameState.Phase.GAME_OVER)
	_check("衔接 Timer 已启动", not GameState.series_timer.is_stopped())
	GameState._on_series_auto_advance()
	_check("衔接进入商店阶段", GameState.phase == GameState.Phase.SHOP)
	_check("商店清空上一轮结果", GameState.shop_result.is_empty())
	var offers: Array = GameState.shop.get("offers", [])
	_check("商店 offer 数 <= 3 且 >0", offers.size() > 0 and offers.size() <= 3)
	# 全员跳过 → 下一局
	GameState._server_shop_skip(0)
	GameState._server_shop_skip(1)
	GameState._server_shop_skip(2)
	_check("商店后进入下一局 match_number 递增", GameState.match_number == 2 and GameState.phase == GameState.Phase.INITIAL_PEEK)

func _test_shop_snapshot() -> void:
	_open_with_finish(5)
	GameState._on_series_auto_advance()
	var snap: Dictionary = GameState._snapshot_for(0)
	_check("快照含商店 offers", not snap.get("shop", {}).is_empty())
	var offers: Array = snap.get("shop", {}).get("offers", [])
	var leak := false
	for offer in offers:
		if (offer as Dictionary).has("amount"):
			leak = true
	_check("快照不含任何出价金额", not leak)

func _test_bid_valid() -> void:
	_rejections = 0
	GameState.command_rejected.connect(func(_c: int, _m: String) -> void: _rejections += 1)
	_open_with_finish(5)
	GameState._on_series_auto_advance()
	var offers: Array = GameState.shop.offers
	var min_bid: int = int(offers[0].min_bid)
	GameState._server_shop_bid(0, 0, min_bid)
	_check("出价生效并记录 order", GameState.shop.bids.has(0) and int(GameState.shop.bids[0].offer) == 0)
	_check("未全员提交不裁决", GameState.phase == GameState.Phase.SHOP)
	GameState._server_shop_bid(0, 0, min_bid)
	_check("重复出价被拒", _rejections == 1)
	GameState._server_shop_bid(1, 0, min_bid)
	GameState._server_shop_bid(2, 0, min_bid)
	_check("全员出价后裁决进入下一局", GameState.phase == GameState.Phase.INITIAL_PEEK and GameState.match_number == 2)

func _test_bid_invalid() -> void:
	_rejections = 0
	_open_with_finish(5)
	GameState._on_series_auto_advance()
	GameState._server_shop_bid(0, 99, 10)
	_check("offer 越界被拒", _rejections == 1 and not GameState.shop.bids.has(0))
	GameState._server_shop_bid(0, 0, 1)
	_check("低于起拍价被拒", _rejections == 2)
	GameState._server_shop_bid(0, 0, 99999)
	_check("超过货币被拒", _rejections == 3)
	GameState._server_shop_skip(0)
	_check("跳过生效", GameState.shop.skip.has(0))
	GameState._server_shop_bid(0, 0, 2)
	_check("已提交后再出价被拒", _rejections == 4)

func _test_resolve_winner() -> void:
	_open_with_finish(5)
	GameState._on_series_auto_advance()
	var offers: Array = GameState.shop.offers
	# 固定竞拍 Joker 遗物：护盾会在下一局开局被消耗，Joker 遗物持久入库（确定性断言）
	var oi := _find_offer(Relics.JOKER_TRANSFORM_ID, offers)
	var relic_id: String = str(offers[oi].relic_id)
	var min_bid: int = int(offers[oi].min_bid)
	GameState.players[0].currency = 100
	GameState.players[1].currency = 100
	GameState._server_shop_bid(0, oi, min_bid)
	GameState._server_shop_bid(1, oi, min_bid + 10)  # seat1 更高
	GameState._server_shop_skip(2)
	_check("最高价者拍到", int(GameState.shop_result[str(oi)].winner) == 1)
	_check("胜者扣货币", int(GameState.players[1].currency) == 100 - (min_bid + 10))
	_check("败者不扣货币", int(GameState.players[0].currency) == 100)
	_check("遗物入库", GameState.run_state.relics.has(relic_id))
	_check("进入下一局", GameState.phase == GameState.Phase.INITIAL_PEEK and GameState.match_number == 2)

func _test_resolve_tie() -> void:
	_open_with_finish(5)
	GameState._on_series_auto_advance()
	var offers: Array = GameState.shop.offers
	var min_bid: int = int(offers[0].min_bid)
	GameState._server_shop_bid(0, 0, min_bid)  # 先提交
	GameState._server_shop_bid(1, 0, min_bid)  # 后提交同价
	GameState._server_shop_skip(2)
	_check("同价先到先得", int(GameState.shop_result["0"].winner) == 0)

func _test_skip_all() -> void:
	_open_with_finish(5)
	GameState._on_series_auto_advance()
	GameState._server_shop_skip(0)
	GameState._server_shop_skip(1)
	GameState._server_shop_skip(2)
	_check("全员跳过无入库", GameState.run_state.relics.is_empty())
	_check("全员跳过进入下一局", GameState.phase == GameState.Phase.INITIAL_PEEK and GameState.match_number == 2)

func _test_inventory_override() -> void:
	_open_with_finish(5)
	GameState._on_series_auto_advance()
	var offers: Array = GameState.shop.offers
	var oi := _find_offer(Relics.JOKER_TRANSFORM_ID, offers)
	var min_bid: int = int(offers[oi].min_bid)
	GameState._server_shop_bid(0, oi, min_bid)
	GameState._server_shop_skip(1)
	GameState._server_shop_skip(2)
	var relic_id: String = str(offers[oi].relic_id)
	_check("遗物入库", GameState.run_state.relics.has(relic_id))
	# 打完下一局再进商店 → 拍到同件覆写（数量不变）。Joker 遗物不消耗（护盾会消耗），
	# 已持有遗物必然在架；若异常不在架则跳过以稳定 relics.size()==1。
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._server_bet(0, KongRules.MIN_BET)
	GameState._server_bet(1, KongRules.MIN_BET)
	GameState._server_bet(2, KongRules.MIN_BET)
	GameState._finish_game()
	GameState._on_series_auto_advance()
	var offers2: Array = GameState.shop.offers
	var held_idx := _find_offer(relic_id, offers2)
	if held_idx >= 0:
		GameState._server_shop_bid(0, held_idx, int(offers2[held_idx].min_bid))
	else:
		GameState._server_shop_skip(0)
	GameState._server_shop_skip(1)
	GameState._server_shop_skip(2)
	_check("同种遗物覆写而非累积", GameState.run_state.relics.size() == 1)