class_name LobbyView
extends RefCounted
## 大厅视图（main.gd 拆分 · 第二优先级）
## 职责：大厅 UI 构建、创建/加入房间、开发者双开、房间成员列表刷新。
## 持有 main（组合根）引用，访问其 UI 成员与工具方法。

var main: Node

func _init(owner_node: Node) -> void:
	main = owner_node

## 构建大厅界面（需已存在 lobby_panel）。
func build() -> void:
	var lobby_title := Label.new()
	lobby_title.text = "KONG  ·  LAN MVP"
	lobby_title.add_theme_font_size_override("font_size", 30)
	lobby_title.add_theme_color_override("font_color", UITheme.color("accent"))
	main.lobby_panel.add_child(lobby_title)
	main.lobby_status_label = Label.new()
	main.lobby_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.lobby_status_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	main.lobby_status_label.text = "输入昵称后创建或加入局域网房间。默认端口 7007。"
	main.lobby_panel.add_child(main.lobby_status_label)
	var intro := Label.new()
	intro.text = "房主的电脑负责裁定全部规则；同一 Wi‑Fi 下的朋友输入房主的局域网 IP 即可加入。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.lobby_panel.add_child(intro)
	var inputs := HBoxContainer.new()
	inputs.add_theme_constant_override("separation", 10)
	main.lobby_panel.add_child(inputs)
	main.name_input = LineEdit.new()
	main.name_input.placeholder_text = "昵称"
	main.name_input.text = "玩家"
	main.name_input.custom_minimum_size = Vector2(190, 42)
	inputs.add_child(main.name_input)
	main.address_input = LineEdit.new()
	main.address_input.placeholder_text = "房主 IP（加入时填写）"
	main.address_input.text = "127.0.0.1"
	main.address_input.custom_minimum_size = Vector2(240, 42)
	inputs.add_child(main.address_input)
	main.port_input = LineEdit.new()
	main.port_input.placeholder_text = "端口"
	main.port_input.text = str(KongNetwork.DEFAULT_PORT)
	main.port_input.custom_minimum_size = Vector2(105, 42)
	main.port_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	inputs.add_child(main.port_input)
	var host: Button = main._button("创建房间")
	host.pressed.connect(host_game)
	host.disabled = main.is_dev_join
	inputs.add_child(host)
	var join: Button = main._button("加入房间")
	join.pressed.connect(join_game)
	join.disabled = main.is_dev_join
	inputs.add_child(join)
	var dev: Button = main._button("开发者：本机双开测试")
	dev.pressed.connect(dev_launch_second)
	dev.add_theme_color_override("font_color", UITheme.color("success"))
	dev.disabled = main.is_dev_join
	inputs.add_child(dev)
	main.lobby_members = RichTextLabel.new()
	main.lobby_members.bbcode_enabled = true
	main.lobby_members.fit_content = true
	main.lobby_members.custom_minimum_size = Vector2(0, 140)
	main.lobby_members.add_theme_font_size_override("normal_font_size", 18)
	main.lobby_panel.add_child(main.lobby_members)

func host_game() -> void:
	Network.host_game({"name": main._entered_name()}, main._entered_port())

func join_game() -> void:
	var address: String = main.address_input.text.strip_edges()
	if address.is_empty():
		main._show_toast("请输入房主的局域网 IP。")
		return
	main._reconnect_expected = false  # 正常加入，不触发重连
	Network.join_game(address, {"name": main._entered_name()}, main._entered_port())

func dev_launch_second() -> void:
	var executable := OS.get_executable_path()
	var project_dir := ProjectSettings.globalize_path("res://")
	var port: int = main._entered_port()
	var args := PackedStringArray(["--path", project_dir, "--", "--dev-join", "127.0.0.1:%d" % port])
	var pid := OS.create_process(executable, args)
	if pid == 0:
		main._show_toast("启动第二个实例失败，请直接手动运行：%s --path %s" % [executable, project_dir])
	else:
		main._local_log.append("已启动第二实例（开发者2）")

## 从命令行参数应用开发者自动加入。
func apply_dev_join() -> void:
	var args := OS.get_cmdline_user_args()
	var target := ""
	for index in range(args.size()):
		if args[index] == "--dev-join" and index + 1 < args.size():
			target = args[index + 1]
			break
	if target.is_empty():
		return
	main.is_dev_join = true
	var parts := target.rsplit(":", true, 1)
	var address: String = parts[0] if parts.size() == 2 else "127.0.0.1"
	var port: int = int(parts[1]) if parts.size() == 2 else KongNetwork.DEFAULT_PORT
	main.name_input.text = "开发者2"
	main.address_input.text = address
	main.port_input.text = str(port)
	Network.join_game(address, {"name": "开发者2"}, port)
	main._set_status("开发者模式：正在自动加入 %s:%d…" % [address, port])

## 回到初始大厅：清空房主操作按钮与成员列表（解散房间/中止/退出房间后调用）。
func reset_lobby() -> void:
	if main.start_button != null:
		if is_instance_valid(main.start_button):
			main.start_button.queue_free()
		main.start_button = null
	if main.close_room_button != null:
		if is_instance_valid(main.close_room_button):
			main.close_room_button.queue_free()
		main.close_room_button = null
	if main.leave_room_button != null:
		if is_instance_valid(main.leave_room_button):
			main.leave_room_button.queue_free()
		main.leave_room_button = null
	main.lobby_members.text = ""
	main.lobby_panel.visible = true
	main.game_panel.visible = false

## 刷新房间成员列表。
func update_lobby(lobby: Dictionary) -> void:
	main.latest_lobby = lobby
	main.lobby_panel.visible = true
	main.game_panel.visible = false
	var lines := ["[color=#f6d77a]房间玩家（%d/%d）[/color]" % [lobby.players.size(), lobby.max_players]]
	for entry in lobby.players:
		var host_mark := "  [房主]" if int(entry.id) == int(lobby.host_id) else ""
		lines.append("• %s%s" % [entry.name, host_mark])
	if Network.is_host:
		lines.append("\n[房主] 至少 2 人后可开始。")
		if main.start_button == null:
			main.start_button = main._button("开始对局")
			main.start_button.name = "StartMatch"
			main.start_button.pressed.connect(GameState.request_start_match)
			main.lobby_panel.add_child(main.start_button)
		main.start_button.disabled = lobby.players.size() < int(lobby.min_players)
		# 房主可解散房间：通知全员回大厅并关闭服务器，回到初始界面
		if main.close_room_button == null:
			main.close_room_button = main._button("解散房间")
			main.close_room_button.name = "CloseRoom"
			main.close_room_button.pressed.connect(GameState.request_close_room)
			main.lobby_panel.add_child(main.close_room_button)
	else:
		# 客户端可主动退出房间：断开连接回到初始大厅
		if main.leave_room_button == null:
			main.leave_room_button = main._button("退出房间")
			main.leave_room_button.name = "LeaveRoom"
			main.leave_room_button.pressed.connect(_leave_room)
			main.lobby_panel.add_child(main.leave_room_button)
	main.lobby_members.text = "\n".join(lines)

## 客户端主动退出房间：断开连接，回到初始大厅界面。
## 保留 token 与地址，便于之后重新"加入房间"时凭 token 重连回原座位（若房主对局仍在进行）。
func _leave_room() -> void:
	GameState._reset_match()
	Network.disconnect_game(false)
	main._rejoin_addr = main.address_input.text.strip_edges() if not main.address_input.text.strip_edges().is_empty() else main._rejoin_addr
	main._rejoin_port = main._entered_port()
	main._save_identity()
	main._reconnect_expected = false
	reset_lobby()
	main._set_status("已退出房间。")
