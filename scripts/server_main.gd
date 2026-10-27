extends Node
## KONG 专用（中立）服务器 headless 入口：无 UI，只做权威，不占玩家座位。
##
## 运行：
##   godot --headless --path . res://scenes/server.tscn -- --port 7007
## 导出的 Linux 包同理：./KongServer --headless -- --port 7007
## 若与服务同机部署（目录看到源 IP=127.0.0.1），用 --advertise <公网IP> 上报对外地址。
## 房间池模式：加 --pool，以 idle 登记；房间结束后自动换新码回到池里等待再次分配。

var _pool: PoolRegistrar = null
var _pool_dc: DirectoryClient = null
var _pool_port := 0

func _ready() -> void:
	var port := KongNetwork.DEFAULT_PORT
	var dir_url := str(Settings.get_setting("network", "directory_url", ""))
	var advertise := ""
	var room_code_arg := ""
	var pool := false
	var raw_args := OS.get_cmdline_user_args()
	var args: Array = []
	for a in raw_args:
		if str(a).begins_with("--") and str(a).contains("="):
			var kv := str(a).split("=", true, 1)
			args.append(kv[0])
			args.append(kv[1])
		else:
			args.append(a)
	for i in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size():
			var p := int(args[i + 1])
			if p > 0 and p < 65536:
				port = p
		elif args[i] == "--directory" and i + 1 < args.size():
			dir_url = args[i + 1]
		elif args[i] == "--advertise" and i + 1 < args.size():
			advertise = args[i + 1]
		elif args[i] == "--code" and i + 1 < args.size():
			room_code_arg = args[i + 1]
		elif args[i] == "--pool":
			pool = true
	Network.start_dedicated(port)
	print("[KONG] dedicated server listening on UDP %d" % port)
	if pool:
		_start_pool(dir_url.strip_edges(), port, advertise.strip_edges())
	else:
		_register_with_directory(dir_url.strip_edges(), port, advertise.strip_edges(), room_code_arg.strip_edges())

## 向中心目录登记（拿房间码），并周期性心跳续命。未配置目录则提示按 IP 直连。
func _register_with_directory(url: String, port: int, advertise := "", fixed_code := "") -> void:
	if url.is_empty():
		print("[KONG] no directory configured; players must join by IP")
		return
	var dc := DirectoryClient.new()
	dc.setup(url)
	add_child(dc)
	var on_created := func(ok: bool, data: Dictionary):
		if ok and data.has("code"):
			var code := str(data["code"])
			print("[KONG] room code: %s" % code)
			var t := Timer.new()
			t.wait_time = 10.0
			t.timeout.connect(func(): dc.heartbeat(code))
			add_child(t)
			t.start()
		else:
			print("[KONG] directory create failed: %s" % str(data.get("error", "?")))
	dc.create_room(port, "dedicated", KongRules.MAX_PLAYERS, on_created, advertise, fixed_code)

## ===== 房间池模式：idle 登记 / 房间结束换码 / 心跳自愈 =====
func _start_pool(url: String, port: int, advertise: String) -> void:
	if url.is_empty():
		print("[KONG] pool mode needs --directory; players must join by IP")
		return
	_pool_port = port
	var dc := DirectoryClient.new()
	dc.setup(url)
	add_child(dc)
	_pool_dc = dc
	_pool = PoolRegistrar.new()
	_pool.setup(
		func(p: int, mode: String, max_players: int, state: String, cb: Callable):
			dc.create_room(p, mode, max_players, cb, advertise, "", state),
		func(c: String, cb: Callable):
			dc.close_room(c, cb))
	_pool.register_idle(port, "dedicated", KongRules.MAX_PLAYERS, func(ok: bool, _d: Dictionary):
		if ok:
			print("[KONG] pool room code: %s" % _pool.code)
		else:
			print("[KONG] pool register failed: %s" % _pool.last_error))
	GameState.room_ended.connect(_on_pool_room_ended)
	var t := Timer.new()
	t.wait_time = 10.0
	t.timeout.connect(_on_pool_heartbeat)
	add_child(t)
	t.start()

func _on_pool_room_ended() -> void:
	if _pool == null:
		return
	print("[KONG] room ended; recycling pool instance on UDP %d" % _pool_port)
	_pool.rotate_after_room(_pool_port, "dedicated", KongRules.MAX_PLAYERS, func(ok: bool, _d: Dictionary):
		if ok:
			print("[KONG] new room code: %s" % _pool.code)
		else:
			print("[KONG] pool re-register failed: %s" % _pool.last_error))

func _on_pool_heartbeat() -> void:
	if _pool == null or _pool.code.is_empty():
		return
	if _pool_dc == null:
		return
	var code := _pool.code
	_pool_dc.heartbeat(code, func(ok: bool, _d: Dictionary):
		if ok:
			return
		_pool.re_register(_pool_port, "dedicated", KongRules.MAX_PLAYERS,
			not GameState.players.is_empty(), func(_ok2: bool, _d2: Dictionary):
				print("[KONG] pool re-registered code: %s" % _pool.code)))
