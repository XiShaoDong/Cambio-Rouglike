extends Node
## headless 单元测试：货币经济（Milestone 2）

var failures := 0
var checks := 0
var _rejections := 0

func _ready() -> void:
	await _test_defaults()
	await _test_bet_phase()
	await _test_bet_all_in()
	await _test_settlement()
	await _test_all_in_loss()
	await _test_all_in_win()
	await _test_tie()
	await _test_kong_first_turn()
	await _test_over_hand()
	var status: String = " (FAILURES!)" if failures > 0 else ""
	print("=== ECONOMY RESULT: %d/%d passed%s ===" % [checks - failures, checks, status])
	get_tree().quit(1 if failures > 0 else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

## 开局 3 人；seat0 最低分(胜)、seat1 中、seat2 最高分(垫底)。
## 按计划语义「押注时已扣货币」：settle 前先扣除每人的押注额，模拟 BET 阶段扣款。
func _open_with_hands(bets: Dictionary) -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	for seat in [0, 1, 2]:
		var vals: Array = [3, 4] if seat == 0 else ([5, 6] if seat == 1 else [7, 8])
		GameState.players[seat].cards = []
		for i in vals.size():
			var cid := "t%d_%d" % [seat, i]
			GameState.cards[cid] = {"id": cid, "rank": str(vals[i]), "suit": "♠", "value": vals[i]}
			GameState.players[seat].cards.append(cid)
	GameState.bets = bets
	_deduct_bets()

## 模拟 BET 阶段已扣款：从玩家货币中扣除各自押注额。
func _deduct_bets() -> void:
	for seat in GameState.bets:
		GameState.players[seat].currency = int(GameState.players[seat].currency) - int(GameState.bets[seat].get("amount", 0))

func _test_defaults() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	_check("起始货币=100", int(GameState.players[0].currency) == KongRules.START_CURRENCY)
	_check("灵魂币 health=1", int(GameState.players[0].health) == 1)
	_check("押注常量 20/5/100", KongRules.MIN_BET == 20 and KongRules.BET_STEP == 5 and KongRules.MAX_BET == 100)

func _test_bet_phase() -> void:
	GameState.command_rejected.connect(func(_c: int, _m: String) -> void: _rejections += 1)
	_rejections = 0
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	_check("开局确认后进入押注阶段", GameState.phase == GameState.Phase.BET)
	GameState._server_bet(0, 15)
	_check("低于入场被拒", _rejections == 1 and not GameState.bets.has(0))
	GameState._server_bet(0, 22)
	_check("非5倍数被拒", _rejections == 2)
	GameState._server_bet(0, 500)
	_check("超上限被拒", _rejections == 3)
	GameState._server_bet(0, 20)
	_check("正常押注生效并扣货币", GameState.bets.has(0) and int(GameState.players[0].currency) == 80)
	GameState._server_bet(0, 20)
	_check("重复押注被拒", _rejections == 4 and int(GameState.players[0].currency) == 80)
	GameState._server_bet(1, 20)
	_check("未全员押注不推进", GameState.phase == GameState.Phase.BET)
	GameState._server_bet(2, 20)
	_check("全员押注后进入抽牌", GameState.phase == GameState.Phase.TURN_DRAW and GameState.current_player_id == 0)
	_check("快照含 bet_ready", (GameState._snapshot_for(0).get("bet_ready", []) as Array).size() == 0)  # BET 已结束

func _test_bet_all_in() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState.players[1].currency = 10  # seat1 押不起入场
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_bet(0, 20)
	GameState._server_bet(1, 0)  # all-in：全货币+灵魂币
	_check("all-in 押注记录全货币", GameState.bets.has(1) and int(GameState.bets[1].amount) == 10 and bool(GameState.bets[1].all_in))
	_check("all-in 后货币归零", int(GameState.players[1].currency) == 0)
	_check("双方押完进入抽牌", GameState.phase == GameState.Phase.TURN_DRAW)

func _test_settlement() -> void:
	_open_with_hands({0: {"amount": 20, "all_in": false}, 1: {"amount": 20, "all_in": false}, 2: {"amount": 20, "all_in": false}})
	GameState._finish_game()
	_check("胜者 2×+垫底者押注", int(GameState.players[0].currency) == 140)  # 100-20+60
	_check("安全玩家 1.5×", int(GameState.players[1].currency) == 110)      # 100-20+30
	_check("垫底者全失", int(GameState.players[2].currency) == 80)          # 100-20+0
	_check("胜场+1", int(GameState.players[0].wins) == 1)
	_check("economy gains 记录", int(GameState.last_result.economy[0]) == 40 and int(GameState.last_result.economy[1]) == 10 and int(GameState.last_result.economy[2]) == -20)
	_check("无人出局(无 all-in)", GameState.players[0].health == 1 and GameState.players[1].health == 1 and GameState.players[2].health == 1)

func _test_all_in_loss() -> void:
	_open_with_hands({0: {"amount": 20, "all_in": false}, 1: {"amount": 20, "all_in": false}, 2: {"amount": 10, "all_in": true}})
	GameState.players[2].currency = 10
	GameState._finish_game()
	_check("all-in 垫底出局", GameState.players[2].health == 0)
	_check("all-in 垫底货币=0", int(GameState.players[2].currency) == 0)
	_check("penalized 记录出局者", (GameState.last_result.penalized as Array).has(2))

func _test_all_in_win() -> void:
	_open_with_hands({0: {"amount": 10, "all_in": true}, 1: {"amount": 20, "all_in": false}, 2: {"amount": 20, "all_in": false}})
	GameState.players[0].currency = 10
	GameState._finish_game()
	_check("all-in 胜者保留灵魂币", GameState.players[0].health == 1)
	_check("all-in 胜者货币恢复", int(GameState.players[0].currency) > 0)

func _test_tie() -> void:
	# 并列第一：seat0/seat1 同分，平分 2×+垫底者押注；并列垫底 seat2/seat3 同失
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._add_player(4, "D")
	for seat in [0, 1, 2, 3]:
		var vals: Array = [3, 3] if seat <= 1 else [9, 9]
		GameState.players[seat].cards = []
		for i in vals.size():
			var cid := "u%d_%d" % [seat, i]
			GameState.cards[cid] = {"id": cid, "rank": str(vals[i]), "suit": "♠", "value": vals[i]}
			GameState.players[seat].cards.append(cid)
	GameState.bets = {0: {"amount": 20, "all_in": false}, 1: {"amount": 20, "all_in": false}, 2: {"amount": 20, "all_in": false}, 3: {"amount": 20, "all_in": false}}
	_deduct_bets()
	GameState._finish_game()
	# 奖池给胜者组：2×20+2×20 + 垫底者押注(40) = 120，2 人平分 60
	_check("并列第一各拿60", int(GameState.players[0].currency) == 140 and int(GameState.players[1].currency) == 140)
	_check("并列垫底同失", int(GameState.players[2].currency) == 80 and int(GameState.players[3].currency) == 80)

func _test_kong_first_turn() -> void:
	_open_with_hands({0: {"amount": 20, "all_in": false}, 1: {"amount": 20, "all_in": false}, 2: {"amount": 20, "all_in": false}})
	GameState.kong_called_first_turn = true
	GameState.kong_caller = 1  # 安全玩家 seat1 首回合喊但非最低分 → 按最后一名处理
	GameState._finish_game()
	_check("Kong 首回合失败者按垫底失去押注", int(GameState.players[1].currency) == 80)
	_check("Kong 首回合不影响真正的垫底者", int(GameState.players[2].currency) == 110)  # seat2 变安全 1.5×
	_check("胜者拿到 Kong 失败者押注", int(GameState.players[0].currency) == 140)

func _test_over_hand() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState.players[2].health = 0
	GameState.bets = {0: {"amount": 20, "all_in": false}, 1: {"amount": 20, "all_in": false}}
	_deduct_bets()
	GameState._server_start_match(0)
	for _i in 3:
		GameState.players[0].cards.append(GameState._draw_from_deck())
	GameState._finish_game_over_hand(0)
	_check("超限玩家按垫底失去押注", int(GameState.players[0].currency) == 80)
	_check("超限结算排除出局者", GameState.last_result.ranking.size() == 1)