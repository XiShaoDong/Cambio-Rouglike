extends Node

## 贴牌比拼（SLAP_DUEL）headless 验证：
##   1) 单正确贴牌 → 收集窗结束正常解决（SLAP_EXCHANGE）
##   2) 双正确贴牌 → 进入比拼，双方 STOP → 胜者解决，败者无罚
##   3) 双正确贴牌 → 进入比拼，一方不 STOP → 超时解决
## 直接调用内部结算方法（collection_timeout/duel_timeout）避免真实定时等待。

var failures := 0
var checks := 0
var seen_rejects: Array[int] = []

func _ready() -> void:
	GameState.command_rejected.connect(_on_rejected)
	await _test_single_correct()
	await _test_duel_both_stop()
	await _test_duel_timeout()
	await _test_debug_duel()
	await _test_duel_nobody_stops()
	print("=== DUEL RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _on_rejected(code: int, _message: String) -> void:
	seen_rejects.append(code)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[FAIL] " + name)
	else:
		print("[PASS] " + name)

func _rejected(code: int) -> bool:
	return code in seen_rejects

## 重置并开局 2 人，制造 slap_rank=rank、slap_open 的窗口；两人 slot0 各放一张该点数的牌。
func _open_window_with_rank(rank: String) -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(1)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	var c1 := ""
	var c2 := ""
	for cid in GameState.cards:
		if str(GameState.cards[cid].rank) == rank:
			if c1.is_empty():
				c1 = cid
			elif c2.is_empty():
				c2 = cid
				break
	GameState.players[1].cards[0] = c1
	GameState.players[2].cards[0] = c2
	GameState.slap_rank = rank
	GameState.slap_open = true
	GameState.phase = GameState.Phase.TURN_DRAW
	GameState.current_player_id = 2

func _count_nonempty(cards: Array) -> int:
	var n := 0
	for c in cards:
		if str(c) != "":
			n += 1
	return n

func _test_single_correct() -> void:
	_open_window_with_rank("7")
	seen_rejects.clear()
	GameState._server_slap_duel_stop(1, "sc-early")
	_check("非比拼阶段 STOP 被拒 INVALID_PHASE", _rejected(GameState.RejectCode.INVALID_PHASE))
	GameState._server_slap(1, 2, 0, "sc-1")
	_check("单正确进入收集窗", not GameState.slap_collect.is_empty())
	GameState.slap.collection_timeout()
	_check("收集后单人正确解决为 SLAP_EXCHANGE", GameState.phase == GameState.Phase.SLAP_EXCHANGE)
	_check("单人正确不进入比拼", GameState.slap_duel.is_empty())

func _test_duel_both_stop() -> void:
	_open_window_with_rank("7")
	GameState._server_slap(1, 2, 0, "db-1")
	GameState._server_slap(2, 1, 0, "db-2")
	GameState.slap.collection_timeout()
	_check("双正确进入比拼", GameState.phase == GameState.Phase.SLAP_DUEL)
	_check("比拼两个候选人", int(GameState.slap_duel.correct.size()) == 2)
	var loser_before: int = _count_nonempty(GameState.players[1].cards)
	GameState._server_slap_duel_stop(1, "db-stop1")
	_check("第一个 STOP 后仍在比拼", GameState.phase == GameState.Phase.SLAP_DUEL)
	seen_rejects.clear()
	GameState._server_slap_duel_stop(1, "db-stop1b")
	_check("重复 STOP 被拒 ALREADY_STOPPED", _rejected(GameState.RejectCode.ALREADY_STOPPED))
	GameState._server_slap_duel_stop(2, "db-stop2")
	_check("双方 STOP 后解决为 SLAP_EXCHANGE", GameState.phase == GameState.Phase.SLAP_EXCHANGE)
	_check("比拼状态已清空", GameState.slap_duel.is_empty())
	var winner := int(GameState.slap_exchange.get("actor", 0))
	_check("胜者是一方候选人", winner == 1 or winner == 2)
	var loser := (2 if winner == 1 else 1)
	_check("败者无罚牌", _count_nonempty(GameState.players[loser].cards) == loser_before)

func _test_duel_timeout() -> void:
	_open_window_with_rank("9")
	GameState._server_slap(1, 2, 0, "dt-1")
	GameState._server_slap(2, 1, 0, "dt-2")
	GameState.slap.collection_timeout()
	_check("超时场景进入比拼", GameState.phase == GameState.Phase.SLAP_DUEL)
	GameState._server_slap_duel_stop(1, "dt-stop1")
	_check("另一方未 STOP 时仍在比拼", GameState.phase == GameState.Phase.SLAP_DUEL)
	GameState.slap.duel_timeout()
	_check("比拼超时后解决", GameState.phase != GameState.Phase.SLAP_DUEL)
	_check("未 STOP 者败（1 号已 STOP 应胜出）", int(GameState.slap_exchange.get("actor", 0)) == 1)

func _test_debug_duel() -> void:
	# 调试模式（F11 开启 debug_duel）：不判正确性，任意贴牌计入；第二名不同玩家贴牌立即比拼。
	_open_window_with_rank("7")
	var wrong := ""
	for cid in GameState.cards:
		if str(GameState.cards[cid].rank) != "7":
			wrong = cid
			break
	GameState.players[1].cards[0] = wrong
	GameState.players[2].cards[0] = wrong
	GameState.debug_duel = true
	var c1_before: int = _count_nonempty(GameState.players[1].cards)
	var c2_before: int = _count_nonempty(GameState.players[2].cards)
	GameState._server_slap(1, 2, 0, "dd-1")
	_check("调试：贴不匹配牌仍进入收集", not GameState.slap_collect.is_empty())
	_check("调试：不匹配贴牌不罚牌(1)", _count_nonempty(GameState.players[1].cards) == c1_before)
	GameState._server_slap(2, 1, 0, "dd-2")
	_check("调试：双贴立即进入比拼", GameState.phase == GameState.Phase.SLAP_DUEL)
	_check("调试：不匹配贴牌不罚牌(2)", _count_nonempty(GameState.players[2].cards) == c2_before)
	GameState.debug_duel = false

func _test_duel_nobody_stops() -> void:
	# 全员未按 STOP：比拼超时必须无异常解决（不因 best=0 报错），兜底选第一个候选人。
	_open_window_with_rank("8")
	GameState._server_slap(1, 2, 0, "ns-1")
	GameState._server_slap(2, 1, 0, "ns-2")
	GameState.slap.collection_timeout()
	_check("无人 STOP 场景进入比拼", GameState.phase == GameState.Phase.SLAP_DUEL)
	GameState.slap.duel_timeout()
	_check("无人 STOP 超时后正常解决", GameState.phase != GameState.Phase.SLAP_DUEL)
	_check("无人 STOP 兜底胜者是候选人", int(GameState.slap_exchange.get("actor", 0)) == 1 or int(GameState.slap_exchange.get("actor", 0)) == 2)