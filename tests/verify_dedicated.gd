extends Node
## headless 单元测试：P1 —— Network 中立 host 开关 + start_dedicated + GameState 不占座。

var failures := 0
var checks := 0

func _ready() -> void:
	await get_tree().process_frame
	# max_clients 派生
	Network.host_is_player = true
	_check("玩家模式 max_clients = MAX-1", Network.max_clients() == KongRules.MAX_PLAYERS - 1)
	Network.host_is_player = false
	_check("dedicated max_clients = MAX", Network.max_clients() == KongRules.MAX_PLAYERS)
	Network.host_is_player = true

	# 专用服务器：不占座
	Network.start_dedicated(17077)
	_check("start_dedicated is_host=true", Network.is_host)
	_check("start_dedicated host_is_player=false", not Network.host_is_player)
	_check("start_dedicated dedicated=true", Network.dedicated)
	_check("dedicated: GameState 无座位", GameState.players.is_empty())
	# 模拟两个客户端注册 → seat 0/1；首个即房主
	GameState._add_player(2, "C1")
	GameState._add_player(3, "C2")
	_check("首个客户端 = seat0 且为房主", GameState.players.has(0) and GameState.host_seat == 0)
	_check("第二客户端 = seat1", GameState._peer_to_seat(3) == 1)
	_check("服务器(peer1) 无座位", GameState._peer_to_seat(1) == -1)
	Network.disconnect_game(false)
	_check("disconnect 复位 host_is_player", Network.host_is_player and not Network.dedicated)

	# 玩家-host：房主占 seat0
	GameState._reset_match()
	Network.host_game({"name": "H"}, 17078, true)
	_check("host_game(玩家) host_is_player=true", Network.host_is_player and not Network.dedicated)
	_check("玩家-host: 房主占 seat0", GameState.players.has(0))
	Network.disconnect_game(false)

	# headless 入口场景 scenes/server.tscn → 启动中立专用服务器
	var srv = load("res://scenes/server.tscn").instantiate()
	add_child(srv)
	await get_tree().process_frame
	_check("server.tscn → is_host", Network.is_host)
	_check("server.tscn → 不占座(dedicated)", Network.dedicated and not Network.host_is_player)
	_check("server.tscn → GameState 无座位", GameState.players.is_empty())
	srv.queue_free()
	Network.disconnect_game(false)

	# dedicated：中止/解散只终止本房间、保留服务器进程（无 zombie）
	Network.start_dedicated(17080)
	GameState._add_player(2, "C1")
	GameState._add_player(3, "C2")
	GameState._server_abort_match()
	_check("dedicated abort → 回 LOBBY", GameState.phase == GameState.Phase.LOBBY)
	_check("dedicated abort → 清空座位", GameState.players.is_empty())
	_check("dedicated abort → 服务器进程保留", Network.is_host and not Network.host_is_player)
	Network.disconnect_game(false)

	# P3a：account_id 关联座位（内部用；缺省为空=匿名）
	GameState._reset_match()
	GameState._add_player(1, "H", "acc_test1")
	GameState._add_player(2, "C")
	_check("座位带 account_id", str(GameState.players[0].get("account_id", "")) == "acc_test1")
	_check("缺省 account_id 为空", str(GameState.players[1].get("account_id", "")) == "")

	print("=== DEDICATED RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)
