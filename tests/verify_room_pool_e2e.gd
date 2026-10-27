extends Node
## 房间池端到端（需先启动目录与一个 --pool 实例）：
##   python3 server/directory/directory.py --port 18191
##   Godot --headless --path . res://scenes/server.tscn -- --port 17107 --pool \
##     --directory http://127.0.0.1:18191
##   Godot ... res://tests/verify_room_pool_e2e.tscn -- -role creator -dir http://127.0.0.1:18191
##   Godot ... res://tests/verify_room_pool_e2e.tscn -- -role joiner  -dir http://127.0.0.1:18191
## creator 把码写入 user://pool_code.txt，joiner 读取后加入。

var role := ""
var dir_url := "http://127.0.0.1:18191"
var deadline := 45.0
var done := false
const CODE_FILE := "user://pool_code.txt"

func _ready() -> void:
	_parse_args()
	if role.is_empty():
		_fail("need -role creator|joiner")
		return
	GameState.lobby_updated.connect(_on_lobby)
	if role == "creator":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CODE_FILE))
		_create()
	else:
		_poll_code()

func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"-role":
				i += 1
				role = args[i] if i < args.size() else ""
			"-dir":
				i += 1
				dir_url = args[i] if i < args.size() else dir_url
		i += 1

func _process(delta: float) -> void:
	if done:
		return
	deadline -= delta
	if deadline <= 0.0:
		_fail("timeout")

func _create() -> void:
	var dc := DirectoryClient.new()
	dc.setup(dir_url)
	add_child(dc)
	dc.allocate_room(func(ok: bool, data: Dictionary):
		if not ok:
			_fail("allocate failed: %s" % str(data.get("error", "?")))
			return
		var code := str(data.get("code", ""))
		dc.join_room(code, func(ok2: bool, data2: Dictionary):
			if not ok2 or not data2.has("host"):
				_fail("join_room failed")
				return
			_write_file(CODE_FILE, code)
			print("[creator] code=%s → connect %s:%d" % [code, str(data2["host"]), int(data2["port"])])
			Network.join_game(str(data2["host"]), {"name": "创建者A"}, int(data2["port"]))))

func _poll_code() -> void:
	var waited := 0.0
	while waited < deadline:
		if FileAccess.file_exists(CODE_FILE):
			var fa := FileAccess.open(CODE_FILE, FileAccess.READ)
			if fa != null:
				var c := fa.get_as_text().strip_edges()
				fa.close()
				if not c.is_empty():
					_join(c)
					return
		await get_tree().create_timer(0.3).timeout
		waited += 0.3
	_fail("no code file")

func _join(c: String) -> void:
	var dc := DirectoryClient.new()
	dc.setup(dir_url)
	add_child(dc)
	dc.join_room(c, func(ok: bool, data: Dictionary):
		if ok and data.has("host"):
			Network.join_game(str(data["host"]), {"name": "朋友B"}, int(data["port"]))
		else:
			_fail("join_room failed: %s" % str(data.get("error", "?"))))

func _on_lobby(lobby: Dictionary) -> void:
	var players: Array = lobby.get("players", [])
	var host_id := int(lobby.get("room_host", -1))
	var your_id := int(lobby.get("your_id", -1))
	if role == "creator" and players.size() >= 2:
		if host_id == your_id:
			print("[creator] host ok → disband to verify pool recycle")
			GameState.request_close_room()
			_pass("创建者成为房主，朋友已加入（%d 人）" % players.size())
		else:
			_fail("创建者不是房主")
	elif role == "joiner" and players.size() >= 2:
		_pass("朋友凭码加入成功（%d 人）" % players.size())

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
