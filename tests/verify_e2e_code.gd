extends Node
## P2 端到端：**输码联机**。目录服务需先启动（如 python3 server/directory/directory.py --port 8080）。
##   host  : godot --headless --path . res://tests/verify_e2e_code.tscn -- -role host   -port 17099 -dir http://127.0.0.1:8080
##   client: godot --headless --path . res://tests/verify_e2e_code.tscn -- -role client -port 17099 -dir http://127.0.0.1:8080
## 流程：host 建房→向目录登记拿码（写入 user://e2e_code.txt）；client 读码→目录查地址→连接→进入同一房间。

var role := ""
var port := 17099
var dir_url := "http://127.0.0.1:8080"
var deadline := 45.0
var done := false
var code := ""
const CODE_FILE := "user://e2e_code.txt"

func _ready() -> void:
	_parse_args()
	if role.is_empty():
		_fail("need -role host|client")
		return
	GameState.lobby_updated.connect(_on_lobby)
	Network.joined_server.connect(func(): print("[%s] connected to server" % role))
	if role == "host":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CODE_FILE))
		Network.host_started.connect(_on_host_started)
		Network.host_game({"name": "房主A"}, port)
		print("[host] hosting on %d" % port)
	else:
		_poll_code()

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"-role":
				i += 1; role = args[i] if i < args.size() else ""
			"-port":
				i += 1; port = int(args[i]) if i < args.size() else port
			"-dir":
				i += 1; dir_url = args[i] if i < args.size() else dir_url
		i += 1

func _process(delta: float) -> void:
	if done:
		return
	deadline -= delta
	if deadline <= 0.0:
		_fail("timeout")

func _on_host_started(_p: Dictionary) -> void:
	var dc := DirectoryClient.new()
	dc.setup(dir_url)
	add_child(dc)
	dc.create_room(port, "player_host", KongRules.MAX_PLAYERS, func(ok: bool, data: Dictionary):
		if ok and data.has("code"):
			code = str(data["code"])
			_write_file(CODE_FILE, code)
			print("[host] room code = %s" % code)
		else:
			_fail("register failed: %s" % str(data.get("error", "?"))))

func _poll_code() -> void:
	var waited := 0.0
	while waited < deadline:
		if FileAccess.file_exists(CODE_FILE):
			var fa := FileAccess.open(CODE_FILE, FileAccess.READ)
			if fa != null:
				var c := fa.get_as_text().strip_edges()
				fa.close()
				if not c.is_empty():
					_join_by_code(c)
					return
		await get_tree().create_timer(0.3).timeout
		waited += 0.3
	_fail("no code file (host 未登记？)")

func _join_by_code(c: String) -> void:
	print("[client] got code %s → 向目录查地址" % c)
	var dc := DirectoryClient.new()
	dc.setup(dir_url)
	add_child(dc)
	dc.join_room(c, func(ok: bool, data: Dictionary):
		if ok and data.has("host"):
			print("[client] resolved %s:%d" % [str(data["host"]), int(data["port"])])
			Network.join_game(str(data["host"]), {"name": "玩家B"}, int(data["port"]))
		else:
			_fail("join_room failed: %s" % str(data.get("error", "?"))))

func _on_lobby(lobby: Dictionary) -> void:
	var n := int((lobby.get("players", []) as Array).size())
	print("[%s] lobby: %d players" % [role, n])
	if n >= 2 and not done:
		_pass("输码联机成功（房间成员 %d）" % n)

func _write_file(path: String, text: String) -> void:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa != null:
		fa.store_string(text)
		fa.close()

func _pass(msg: String) -> void:
	done = true
	print("VERIFY %s PASS: %s" % [role, msg])
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0)

func _fail(msg: String) -> void:
	if done:
		return
	done = true
	print("VERIFY %s FAIL: %s" % [role, msg])
	get_tree().quit(1)
