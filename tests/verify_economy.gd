extends Node
## headless 单元测试：名次奖励经济（rank-reward economy，替代押注）

var failures := 0
var checks := 0

func _ready() -> void:
	await _test_defaults()
	await _test_direct_turn_after_ready()
	await _test_rank_rewards()
	await _test_tie_split()
	await _test_all_tie()
	await _test_last_life_and_elimination()
	await _test_kong_first_turn()
	await _test_over_hand()
	await _test_elimination_deferred()
	await _test_lone_player_not_penalized()
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

func _set_hand(seat: int, vals: Array) -> void:
	GameState.players[seat].cards = []
	for i in vals.size():
		var cid := "t%d_%d_%d" % [seat, i, randi() % 100000]
		GameState.cards[cid] = {"id": cid, "rank": str(vals[i]), "suit": "♠", "value": int(vals[i])}
		GameState.players[seat].cards.append(cid)

## 3 人：seat0 最低分(胜)、seat1 中、seat2 最高分(垫底)
func _open_three() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	_set_hand(0, [3, 4])
	_set_hand(1, [5, 6])
	_set_hand(2, [7, 8])

func _test_defaults() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	_check("起始货币=100", int(GameState.players[0].currency) == KongRules.START_CURRENCY)
	_check("起始生命=2", int(GameState.players[0].health) == KongRules.START_HEALTH)
	_check("START_HEALTH 常量=2", KongRules.START_HEALTH == 2)

func _test_direct_turn_after_ready() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	_check("记忆确认后直接进入抽牌", GameState.phase == GameState.Phase.TURN_DRAW)
	_check("先手为 seat0", int(GameState.current_player_id) == 0)
	_check("快照不再含 bet_ready", not GameState._snapshot_for(0).has("bet_ready"))

func _test_rank_rewards() -> void:
	_open_three()
	GameState._finish_game()
	_check("第一名 +40", int(GameState.players[0].currency) == 140)
	_check("中间 +10", int(GameState.players[1].currency) == 110)
	_check("垫底 +0", int(GameState.players[2].currency) == 100)
	_check("垫底 -1 生命", int(GameState.players[2].health) == 1)
	_check("非垫底不掉血", int(GameState.players[0].health) == 2 and int(GameState.players[1].health) == 2)
	_check("rewards 记录", int(GameState.last_result.rewards[0].money) == 40 and int(GameState.last_result.rewards[1].money) == 10 and int(GameState.last_result.rewards[2].money) == 0)
	_check("penalized 含垫底", (GameState.last_result.penalized as Array).has(2))
	_check("胜场+1", int(GameState.players[0].wins) == 1)

func _test_tie_split() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._add_player(4, "D")
	_set_hand(0, [3, 3]); _set_hand(1, [3, 3])
	_set_hand(2, [9, 9]); _set_hand(3, [9, 9])
	GameState._finish_game()
	_check("并列第一平分(40+10)/2=25", int(GameState.players[0].currency) == 125 and int(GameState.players[1].currency) == 125)
	_check("并列垫底 +0", int(GameState.players[2].currency) == 100 and int(GameState.players[3].currency) == 100)
	_check("并列垫底同扣血", int(GameState.players[2].health) == 1 and int(GameState.players[3].health) == 1)

func _test_all_tie() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._add_player(4, "D")
	for s in [0, 1, 2, 3]:
		_set_hand(s, [4, 4])
	GameState._finish_game()
	_check("全员同分每人 +10", int(GameState.players[0].currency) == 110 and int(GameState.players[3].currency) == 110)
	_check("全员同分无人掉血", int(GameState.players[0].health) == 2 and int(GameState.players[3].health) == 2)
	_check("全员同分无胜场", int(GameState.players[0].wins) == 0)

func _test_last_life_and_elimination() -> void:
	_open_three()
	GameState.players[2].health = 1
	GameState._finish_game()
	_check("垫底第二次扣血出局", int(GameState.players[2].health) == 0)
	_check("出局者 _is_alive=false", not GameState._is_alive(2))
	_check("出局者保留货币", int(GameState.players[2].currency) == 100)

func _test_kong_first_turn() -> void:
	_open_three()
	GameState.kong_called_first_turn = true
	GameState.kong_caller = 1
	GameState._finish_game()
	_check("Kong 首回合失败者 0 金钱", int(GameState.players[1].currency) == 100)
	_check("Kong 首回合失败者 -1 命", int(GameState.players[1].health) == 1)
	_check("真正垫底者也 -1 命", int(GameState.players[2].health) == 1)

func _test_over_hand() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	_set_hand(0, [7, 7, 7, 7, 7, 7, 7])
	_set_hand(1, [3, 4]); _set_hand(2, [5, 6])
	GameState._finish_game_over_hand(0)
	_check("超限者 0 金钱", int(GameState.players[0].currency) == 100)
	_check("超限者 -1 命", int(GameState.players[0].health) == 1)
	_check("超限失败不参与排名", GameState.last_result.ranking.size() == 2)

func _eliminated_in_snapshot(seat: int) -> bool:
	for p in GameState._snapshot_for(0).get("players", []):
		if int(p.id) == seat:
			return bool(p.get("eliminated", false))
	return false

func _test_elimination_deferred() -> void:
	_open_three()
	GameState.players[2].health = 1
	GameState._finish_game()
	_check("垫底出局者本局仍正常结算（未标观战）", int(GameState.players[2].health) == 0 and not _eliminated_in_snapshot(2))
	GameState._deal_next_match()
	_check("下一局起才标观战", _eliminated_in_snapshot(2))

func _test_lone_player_not_penalized() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	_set_hand(0, [7, 7, 7, 7, 7, 7, 7])  # seat0 超限失败
	_set_hand(1, [3, 4])
	GameState._finish_game_over_hand(0)
	_check("超限失败者 -1 命", int(GameState.players[0].health) == 1)
	_check("唯一在场者不算垫底、不扣命", int(GameState.players[1].health) == KongRules.START_HEALTH)
