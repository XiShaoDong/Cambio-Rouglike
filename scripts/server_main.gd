extends Node
## KONG 专用（中立）服务器 headless 入口：无 UI，只做权威，不占玩家座位。
##
## 运行：
##   godot --headless --path . res://scenes/server.tscn -- --port 7007
## 导出的 Linux 包同理：./KongServer --headless -- --port 7007

func _ready() -> void:
	var port := KongNetwork.DEFAULT_PORT
	var dir_url := str(Settings.get_setting("network", "directory_url", ""))
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size():
			var p := int(args[i + 1])
			if p > 0 and p < 65536:
				port = p
		elif args[i] == "--directory" and i + 1 < args.size():
			dir_url = args[i + 1]
	Network.start_dedicated(port)
	print("[KONG] dedicated server listening on UDP %d" % port)
	_register_with_directory(dir_url.strip_edges(), port)

## 向中心目录登记（拿房间码），并周期性心跳续命。未配置目录则提示按 IP 直连。
func _register_with_directory(url: String, port: int) -> void:
	if url.is_empty():
		print("[KONG] no directory configured; players must join by IP")
		return
	var dc := DirectoryClient.new()
	dc.setup(url)
	add_child(dc)
	dc.create_room(port, "dedicated", KongRules.MAX_PLAYERS, func(ok: bool, data: Dictionary):
		if ok and data.has("code"):
			var code := str(data["code"])
			print("[KONG] room code: %s" % code)
			var t := Timer.new()
			t.wait_time = 10.0
			t.timeout.connect(func(): dc.heartbeat(code))
			add_child(t)
			t.start()
		else:
			print("[KONG] directory create failed: %s" % str(data.get("error", "?"))))
