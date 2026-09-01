extends Node

## 断线重连（阶段一：seat 身份 + 离线标记 + 条件暂停）headless 验证：
##   1) 身份：注册分配 seat_id，peer→seat 映射正确
##   2) 非当前玩家掉线 → 不暂停，对局继续
##   3) 轮到离线者 → 条件暂停（suspended=true），操作被拒 MATCH_SUSPENDED
##   4) 房主踢出离线者 → 移除座位并继续轮转
## 阶段二（token 重连恢复）在后续阶段补充。

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