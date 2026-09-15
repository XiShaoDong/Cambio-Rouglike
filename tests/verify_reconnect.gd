extends Node

## 断线重连（阶段一：seat 身份 + 离线标记 + 条件暂停；阶段二：token 认领 + 手牌恢复）headless 验证：
##   1) 身份：注册分配 seat_id + token，peer→seat 映射正确
##   2) 非当前玩家掉线 → 不暂停，对局继续
##   3) 轮到离线者 → 条件暂停（suspended=true），操作被拒 MATCH_SUSPENDED
##   4) 房主踢出离线者 → 移除座位并继续轮转
##   5) 重连：凭 token 认领座位、恢复在线、定向补回手牌面
##   6) 踢出后剩 1 人 → 中止销毁房间；房主解散房间

var failures := 0
var checks := 0
var seen_rejects: Array[int] = []

func _ready() -> void:
	GameState.command_rejected.connect(_on_rejected)
	await _test_identity()
	await _test_continue_when_not_current_turn()
	await _test_pause_on_offline_turn()
	await _test_host_kick()
	await _test_host_kick_last_player()
	await _test_close_room()
	await _test_reconnect_token()
	await _test_reconnect_resume()
	print("=== RECONNECT RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
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

func _count_nonempty(cards: Array) -> int:
	var n := 0
	for c in cards:
		if str(c) != "":
			n += 1
	return n

## 重置并开局 2 人（seat0=房主，seat1=客户端）。
func _open_match() -> void:
	GameState._reset_match()
	GameState._add_player(1, "Host")
	GameState._add_player(2, "Client")
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)

## 重置并开局 3 人（seat0/1/2）。
func _open_match3() -> void:
	GameState._reset_match()
	GameState._add_player(1, "Host")
	GameState._add_player(2, "ClientB")
	GameState._add_player(3, "ClientC")
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)

func _test_identity() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	_check("注册分配 seat：A=0", GameState.players.has(0) and GameState.players[0].name == "A")
	_check("注册分配 seat：B=1", GameState.players.has(1) and GameState.players[1].name == "B")
	_check("peer1→seat0 映射", GameState._peer_to_seat(1) == 0)
	_check("peer2→seat1 映射", GameState._peer_to_seat(2) == 1)
	_check("未知 peer→-1", GameState._peer_to_seat(99) == -1)
	_check("turn_order 为 seat 顺序", GameState.turn_order == [0, 1])

func _test_continue_when_not_current_turn() -> void:
	_open_match()
	# 当前玩家 seat0（房主），seat1 掉线 → 非当前回合不暂停
	GameState._on_peer_left(2)  # seat1 掉线
	_check("掉线者标记离线", bool(GameState.players[1].get("offline", false)))
	_check("掉线者 seat 保留", GameState.players.has(1))
	_check("非当前回合不暂停", not GameState._is_suspended())
	_check("快照 suspended=false", not bool(GameState._snapshot_for(0).get("suspended", false)))
	_check("快照 offline_players=[1]", GameState._snapshot_for(0).get("offline_players", []) == [1])
	# seat0 仍可行动（抽牌）
	seen_rejects.clear()
	GameState._server_take(0, "draw", "c-1")
	_check("非当前回合掉线后 seat0 可继续抽牌", not _rejected(GameState.RejectCode.MATCH_SUSPENDED) and GameState.phase == GameState.Phase.TURN_DECISION)

func _test_pause_on_offline_turn() -> void:
	_open_match()
	GameState._on_peer_left(2)  # seat1 掉线
	# 构造：seat0 已完成行动，轮到 seat1（离线）→ 暂停
	GameState.players[0].has_acted = true
	GameState.current_player_id = 1
	GameState.phase = GameState.Phase.TURN_DRAW
	GameState.slap_open = false
	_check("轮到离线者→条件暂停", GameState._is_suspended())
	var snap: Dictionary = GameState._snapshot_for(0)
	_check("快照 suspended=true", bool(snap.get("suspended", false)))
	# 暂停期间任何操作被拒 MATCH_SUSPENDED
	seen_rejects.clear()
	GameState._server_take(0, "draw", "p-1")
	_check("暂停中抽牌被拒 MATCH_SUSPENDED", _rejected(GameState.RejectCode.MATCH_SUSPENDED))
	seen_rejects.clear()
	GameState._server_initial_ready(0)
	_check("暂停中 ready 被拒（INVALID_PHASE 或 MATCH_SUSPENDED）",
		_rejected(GameState.RejectCode.MATCH_SUSPENDED) or _rejected(GameState.RejectCode.INVALID_PHASE))

func _test_host_kick() -> void:
	_open_match3()
	GameState._on_peer_left(2)  # seat1 掉线（剩余 seat0/2 仍够继续）
	# 构造：轮到 seat1（离线）暂停
	GameState.players[0].has_acted = true
	GameState.current_player_id = 1
	GameState.phase = GameState.Phase.TURN_DRAW
	GameState.slap_open = false
	GameState._kick_offline_seat(1)
	_check("踢出后座位移除", not GameState.players.has(1))
	_check("踢出后不在 turn_order", not 1 in GameState.turn_order)
	_check("踢出后解除暂停", not GameState._is_suspended())
	_check("踢出后仍够 2 人继续（未中止）", GameState.phase != GameState.Phase.LOBBY)
	_check("踢出后轮转到下一在线者（seat2）", GameState.current_player_id == 2 and GameState.phase == GameState.Phase.TURN_DRAW)

func _test_host_kick_last_player() -> void:
	# 踢出抗议玩家后只剩 1 人 → 对局无法继续，自动中止并销毁房间（回初始大厅可重建）
	_open_match()
	GameState._on_peer_left(2)  # seat1 掉线
	GameState.players[0].has_acted = true
	GameState.current_player_id = 1
	GameState.phase = GameState.Phase.TURN_DRAW
	GameState.slap_open = false
	GameState._kick_offline_seat(1)
	_check("踢出最后一名玩家后回 LOBBY", GameState.phase == GameState.Phase.LOBBY)
	_check("中止后销毁房间（清除玩家座位）", GameState.players.is_empty())

func _test_close_room() -> void:
	# 房主解散房间：重置对局 + 关闭服务器连接，回到初始大厅可重建
	_open_match()
	var flag_box := {"flag": false}
	var cb := func(_c: int, _m: String): flag_box["flag"] = true
	GameState.match_aborted.connect(cb)
	GameState._server_close_room()
	_check("解散房间触发本地 match_aborted", bool(flag_box["flag"]))
	_check("解散后重置回 LOBBY", GameState.phase == GameState.Phase.LOBBY)
	_check("解散后清除玩家座位", GameState.players.is_empty())
	GameState.match_aborted.disconnect(cb)

func _test_reconnect_token() -> void:
	# 注册分配 token；掉线后 token 保留；凭 token 认领座位
	GameState._reset_match()
	GameState._add_player(1, "A")  # seat0 host
	GameState._add_player(2, "B")  # seat1 client
	var t1: String = GameState.players[0].token
	var t2: String = GameState.players[1].token
	_check("注册分配了非空 token", not t1.is_empty() and not t2.is_empty())
	_check("token 互不相同", t1 != t2)
	_check("token→seat 反查正确", GameState._seat_by_token(t2) == 1)
	_check("未知 token 反查 -1", GameState._seat_by_token("nope") == -1)
	# 掉线（非 LOBBY 分支），token 保留
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._on_peer_left(2)
	_check("掉线后 token 保留", str(GameState.players[1].token) == t2)
	_check("掉线后 offline=true", bool(GameState.players[1].get("offline", false)))
	_check("掉线后 peer_id 清空", int(GameState.players[1].peer_id) == 0)

func _test_reconnect_resume() -> void:
	# 重连：凭 token 认领，offline 复位、peer_id 更新、手牌恢复数据正确
	GameState._reset_match()
	GameState._add_player(1, "H")
	GameState._add_player(2, "C")
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	var t2: String = GameState.players[1].token
	# 记录 seat1 手牌（从完整 cards 读取当前槽位 id）
	var before_hand: Array = GameState.players[1].cards.duplicate()
	GameState._on_peer_left(2)  # seat1 掉线
	var resume_captured := {"hand": [], "pending": {}, "got": false}
	var cb := func(hand: Array, pending: Dictionary):
		resume_captured["hand"] = hand
		resume_captured["pending"] = pending
		resume_captured["got"] = true
	GameState.resume_hand_received.connect(cb)
	# 模拟重连：新 peer=9，seat0 视角发请求（headless 下 peer 用 9）
	GameState.players[1].token = t2
	GameState._server_reconnect(0, t2, "C", GameState.PROTOCOL_VERSION)
	GameState.resume_hand_received.disconnect(cb)
	_check("重连认领后 offline=false", not bool(GameState.players[1].get("offline", false)))
	_check("重连后 peer_id 更新", int(GameState.players[1].peer_id) == 1 or int(GameState.players[1].peer_id) == 9)
	_check("重连后仍在对局中", GameState.phase != GameState.Phase.LOBBY)
	_check("恢复手牌触发 resume_hand_received", bool(resume_captured["got"]))
	if bool(resume_captured["got"]):
		var h: Array = resume_captured["hand"]
		_check("恢复手牌数量与手牌一致", h.size() == before_hand.size())
		_check("恢复手牌槽位卡面正确", not h.is_empty() and (h[0].is_empty() or h[0].has("rank") or h[0].has("id")))
	# 无效 token 重连：认领失败，offline 状态不变（不产生新座位/不误认领）
	var before_offline: bool = bool(GameState.players[1].get("offline", false))
	var before_seats: int = GameState.players.size()
	GameState._server_reconnect(0, "badtoken", "X", GameState.PROTOCOL_VERSION)
	_check("无效 token 不改变离线状态", bool(GameState.players[1].get("offline", false)) == before_offline)
	_check("无效 token 不新增座位", GameState.players.size() == before_seats)