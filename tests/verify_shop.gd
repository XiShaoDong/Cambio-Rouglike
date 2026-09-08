extends Node
## headless 单元测试：商店盲拍（Milestone 3）

var failures := 0
var checks := 0
var _rejections := 0

func _ready() -> void:
	await _test_relic_defs()
	await _test_shop_flow()
	await _test_shop_snapshot()
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