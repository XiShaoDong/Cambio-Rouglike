extends Node
## KONG 专用（中立）服务器 headless 入口：无 UI，只做权威，不占玩家座位。
##
## 运行：
##   godot --headless --path . res://scenes/server.tscn -- --port 7007
## 导出的 Linux 包同理：./KongServer --headless -- --port 7007

func _ready() -> void:
	var port := KongNetwork.DEFAULT_PORT
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--port" and i + 1 < args.size():
			var p := int(args[i + 1])
			if p > 0 and p < 65536:
				port = p
			break
	Network.start_dedicated(port)
	print("[KONG] dedicated server listening on UDP %d" % port)
