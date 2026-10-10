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
	_test_settle_window_slap()
	_test_overflow_settle()
	_test_overflow_no_reset()
	_test_discard_history()
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
	# seat2 最终行动（末位）→ 不再立即结算，进入结算贴牌窗口
	GameState._server_take(2, "draw", "kb-4")
	GameState._server_discard_draw(2, "kb-5")
	_check("末位行动后不立即结算（进入贴牌窗口）", GameState.phase != GameState.Phase.GAME_OVER and GameState.final_settle_pending)
	_check("窗口内保持 slap_open 与 TURN_DRAW（可贴牌）", GameState.slap_open and GameState.phase == GameState.Phase.TURN_DRAW)
	var snap := HiddenInfo.snapshot_for(GameState, 0)
	_check("快照含 settle_deadline_server_ms>0", int(snap.get("settle_deadline_server_ms", 0)) > 0)
	# 窗口内普通操作被拒（状态不变）
	GameState._server_take(2, "draw", "kb-4b")
	_check("窗口内禁止抽牌（状态不变）", GameState.phase == GameState.Phase.TURN_DRAW and GameState.pending_draw.is_empty() and GameState.current_player_id == 2)
	# 窗口到期 → 结算
	GameState._on_settle_timeout()
	_check("窗口到期后结算 GAME_OVER", GameState.phase == GameState.Phase.GAME_OVER)
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
	_check("重复喊叫被拒后仍能进入结算窗口", GameState.final_settle_pending)
	GameState._on_settle_timeout()
	_check("窗口到期后仍能正常结算", GameState.phase == GameState.Phase.GAME_OVER)

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

## 结算窗口内贴牌判定结束 → 安排收尾宽限（等赠送/自贴动画）后结算。
func _test_settle_window_slap() -> void:
	_open()
	GameState._server_kongbaya(0, "kw-1")
	GameState._server_take(1, "draw", "kw-2")
	GameState._server_discard_draw(1, "kw-3")
	GameState._server_take(2, "draw", "kw-4")
	GameState._server_discard_draw(2, "kw-5")
	_check("进入结算窗口", GameState.final_settle_pending)
	# 模拟窗口内贴牌判定结束（赠送/自贴）
	GameState.slap.finish_slap()
	_check("贴牌结束后仍在结算窗口（未立即结算）", GameState.final_settle_pending and GameState.phase != GameState.Phase.GAME_OVER)
	_check("贴牌结束后改为收尾宽限（timer 在跑且 ≤ grace）", GameState.settle_timer.time_left > 0.0 and GameState.settle_timer.time_left <= KongRules.SLAP_SETTLE_GRACE_SECONDS + 0.05)
	GameState._on_settle_timeout()
	_check("宽限到期后结算 GAME_OVER", GameState.phase == GameState.Phase.GAME_OVER)

## 手牌超限（R-07）：罚牌先落地（pending、slap_open=false、deadline=0）→ 再开 10s 贴牌窗口 → 结算。
func _test_overflow_settle() -> void:
	_open()
	GameState._begin_overflow_settle(1)
	_check("超限：先进入罚牌落地阶段（pending 且不接受贴牌）", GameState.final_settle_pending and not GameState.slap_open)
	_check("超限：罚牌阶段 deadline=0", int(HiddenInfo.snapshot_for(GameState, 0).get("settle_deadline_server_ms", 0)) == 0)
	GameState._on_settle_timeout()  # 罚牌落地 → 开贴牌窗口
	_check("超限：罚牌落地后开 10s 贴牌窗口", GameState.slap_open and GameState.final_settle_pending)
	_check("超限：窗口 deadline>0", int(HiddenInfo.snapshot_for(GameState, 0).get("settle_deadline_server_ms", 0)) > 0)
	GameState._on_settle_timeout()  # 窗口到期 → 超限结算
	_check("超限：窗口到期后按超限结算 GAME_OVER", GameState.phase == GameState.Phase.GAME_OVER and GameState.last_result.has("failed_hand"))

## 结束倒计时开始后，再次超限不得重制倒计时（回归 bug：另一玩家贴错被顶到 7 张导致重制）。
func _test_overflow_no_reset() -> void:
	_open()
	GameState._begin_overflow_settle(1)
	GameState._on_settle_timeout()  # 罚牌落地 → 10s 贴牌窗口
	var dl: int = GameState.final_settle_deadline_ms
	_check("结束倒计时已开始（deadline>0 且开贴牌）", dl > 0 and GameState.slap_open)
	GameState._begin_overflow_settle(2)  # 倒计时中再次超限
	_check("再次超限不重制 deadline", GameState.final_settle_deadline_ms == dl)
	_check("再次超限不回到罚牌阶段（仍开贴牌）", GameState.final_settle_pending and GameState.slap_open)
	GameState._on_settle_timeout()
	_check("倒计时到期结算 GAME_OVER", GameState.phase == GameState.Phase.GAME_OVER)

## 弃牌历史（stats 数据源）：弃牌后 discard_history/discard_count 反映到快照。
func _test_discard_history() -> void:
	_open()
	GameState._server_take(0, "draw", "dh-1")
	var cid := str(GameState.pending_draw.card_id)
	GameState._server_discard_draw(0, "dh-2")
	_check("服务器记录弃牌历史", GameState.discard_history.has(cid))
	var snap := HiddenInfo.snapshot_for(GameState, 0)
	_check("快照 discard_count≥1", int(snap.get("discard_count", 0)) >= 1)
	_check("快照 discard_history 含该牌", (snap.get("discard_history", []) as Array).size() >= 1)
	_check("弃牌历史条目含 rank/suit", str((snap.get("discard_history", []) as Array)[0].get("suit", "")) != "")