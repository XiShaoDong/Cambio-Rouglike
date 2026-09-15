extends Node

## Kongbaya 最终轮 headless 验证：
##   1) 正常流程：喊叫 → 其余玩家依次最终行动 → 全部结束后结算 GAME_OVER
##   2) 一场一次：最终轮玩家再喊被拒（kong_caller/final_queue 不被改写、回合不推进）
##   3) 首次行动前喊叫标记 kong_called_first_turn
##   4) 喊叫者座位为 0（房主）时最终轮与结算仍正确（kong_caller 哨兵为 -1 而非 0）

var failures := 0
var checks := 0

func _ready() -> void:
	await _test_normal_flow()
	await _test_repeat_rejected()
	await _test_first_turn_flag()
	print("=== KONGBAYA RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[FAIL] " + name)
	else:
		print("[PASS] " + name)

## 重置并开局 3 人（seat0/1/2），当前为 seat0。
func _open() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)

func _test_normal_flow() -> void:
	_open()
	_check("开局无喊叫（kong_caller=-1）", GameState.kong_caller == -1)
	GameState._server_kongbaya(0, "kb-1")
	_check("喊叫者记录为 seat0", GameState.kong_caller == 0)
	_check("最终轮开始轮到下一玩家 seat1", GameState.current_player_id == 1 and GameState.phase == GameState.Phase.TURN_DRAW)
	_check("最终队列=[2]", GameState.final_queue == [2])
	# seat1 最终行动
	GameState._server_take(1, "draw", "kb-2")
	GameState._server_discard_draw(1, "kb-3")
	_check("seat1 最终行动后轮到 seat2", GameState.current_player_id == 2 and GameState.phase == GameState.Phase.TURN_DRAW)
	_check("最终队列已清空", GameState.final_queue.is_empty())
	# seat2 最终行动
	GameState._server_take(2, "draw", "kb-4")
	GameState._server_discard_draw(2, "kb-5")
	_check("最后一名最终玩家行动后结算 GAME_OVER", GameState.phase == GameState.Phase.GAME_OVER)
	_check("结算含排名结果", not GameState.last_result.is_empty() and GameState.last_result.has("ranking"))

func _test_repeat_rejected() -> void:
	_open()
	GameState._server_kongbaya(0, "kb-r1")
	# seat1（远程 peer）在最终轮再喊：拒绝走 RPC 无本地信号，用状态不被改写验证
	GameState._server_kongbaya(1, "kb-r2")
	_check("重复喊叫不改写 kong_caller", GameState.kong_caller == 0)
	_check("重复喊叫不重置 final_queue", GameState.final_queue == [2])
	_check("重复喊叫不推进回合（仍在 seat1 最终行动）", GameState.current_player_id == 1 and GameState.phase == GameState.Phase.TURN_DRAW)
	# seat1 正常完成最终行动，对局仍能结算
	GameState._server_take(1, "draw", "kb-r3")
	GameState._server_discard_draw(1, "kb-r4")
	GameState._server_take(2, "draw", "kb-r5")
	GameState._server_discard_draw(2, "kb-r6")
	_check("重复喊叫被拒后仍能正常结算", GameState.phase == GameState.Phase.GAME_OVER)

func _test_first_turn_flag() -> void:
	_open()
	# 喊叫者尚未行动过（首回合）→ kong_called_first_turn = true
	GameState._server_kongbaya(0, "kb-f1")
	_check("首回合喊叫标记 kong_called_first_turn", GameState.kong_called_first_turn)
	_check("喊叫后喊叫者 has_acted 置位", bool(GameState.players[0].has_acted))
	# 非首回合：新开局，先让 seat0 完成一回合再喊
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._server_take(0, "draw", "kb-f2")
	GameState._server_discard_draw(0, "kb-f3")  # 轮到 seat1，seat0 has_acted=true
	GameState.current_player_id = 0
	GameState.phase = GameState.Phase.TURN_DRAW
	GameState._server_kongbaya(0, "kb-f4")
	_check("非首回合喊叫标记 kong_called_first_turn=false", not GameState.kong_called_first_turn)