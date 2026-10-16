class_name LobbyView
extends RefCounted
## 大厅视图（main.gd 拆分）：两态——主菜单（创建/加入）/ 房间（槽位 + Ready + 房主控制）。
## 纯展示 + 转发 request_*；ready/host_seat/kick 均为服务器权威（见 GameState）。

var main: Node

# 主菜单态
var _menu_box: VBoxContainer
# 房间态
var _room_box: VBoxContainer
var _header_label: Label
var _share_field: LineEdit
var _slots_box: VBoxContainer
var _match_limit_spin: SpinBox
var _ready_button: Button
var _start_button: Button
var _disband_button: Button
var _invite_button: Button
var _leave_button: Button

func _init(owner_node: Node) -> void:
	main = owner_node

## 构建大厅界面（需已存在 main.lobby_panel）。
func build() -> void:
	_build_menu()
	_build_room()
	_show_menu()

func _build_menu() -> void:
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 12)
	main.lobby_panel.add_child(_menu_box)

	var lobby_title := Label.new()
	lobby_title.text = "KONG  ·  LAN MVP"
	lobby_title.add_theme_font_size_override("font_size", 30)
	lobby_title.add_theme_color_override("font_color", UITheme.color("accent"))
	_menu_box.add_child(lobby_title)

	main.lobby_status_label = Label.new()
	main.lobby_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.lobby_status_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	main.lobby_status_label.text = "输入昵称，创建房间或凭房间码加入。"
	_menu_box.add_child(main.lobby_status_label)

	# 昵称
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	_menu_box.add_child(name_row)
	main.name_input = LineEdit.new()
	main.name_input.placeholder_text = "昵称"
	main.name_input.text = "玩家"
	main.name_input.custom_minimum_size = Vector2(200, 42)
	name_row.add_child(main.name_input)

	# 加入房间：房间码
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	_menu_box.add_child(code_row)
	main.room_code_input = LineEdit.new()
	main.room_code_input.placeholder_text = "房间码（如 K7X2Q9）"
	main.room_code_input.custom_minimum_size = Vector2(240, 42)
	code_row.add_child(main.room_code_input)
	var join_code: Button = main._button("加入房间")
	join_code.pressed.connect(join_by_code)
	join_code.disabled = main.is_dev_join
	code_row.add_child(join_code)

	# 创建房间
	var host: Button = main._button("创建房间")
	host.pressed.connect(host_game)
	host.disabled = main.is_dev_join
	_menu_box.add_child(host)

	# 高级（IP 直连），默认折叠
	var adv_toggle: Button = main._button("▸ 高级（IP 直连）")
	adv_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_menu_box.add_child(adv_toggle)
	var adv := VBoxContainer.new()
	adv.visible = false
	adv.add_theme_constant_override("separation", 8)
	_menu_box.add_child(adv)
	adv_toggle.pressed.connect(func(): adv.visible = not adv.visible)
	var adv_row := HBoxContainer.new()
	adv_row.add_theme_constant_override("separation", 10)
	adv.add_child(adv_row)
	main.address_input = LineEdit.new()
	main.address_input.placeholder_text = "房主 IP"
	main.address_input.text = "127.0.0.1"
	main.address_input.custom_minimum_size = Vector2(170, 42)
	adv_row.add_child(main.address_input)
	main.port_input = LineEdit.new()
	main.port_input.placeholder_text = "端口"
	main.port_input.text = str(KongNetwork.DEFAULT_PORT)
	main.port_input.custom_minimum_size = Vector2(95, 42)
	main.port_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	adv_row.add_child(main.port_input)
	var join_ip: Button = main._button("直连加入")
	join_ip.pressed.connect(join_game)
	join_ip.disabled = main.is_dev_join
	adv_row.add_child(join_ip)
	var dev: Button = main._button("开发者：本机双开")
	dev.pressed.connect(dev_launch_second)
	dev.add_theme_color_override("font_color", UITheme.color("success"))
	dev.disabled = main.is_dev_join
	adv_row.add_child(dev)

func _build_room() -> void:
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 12)
	main.lobby_panel.add_child(_room_box)

	# 分享行：房间地址 + 复制
	var share_row := HBoxContainer.new()
	share_row.add_theme_constant_override("separation", 8)
	_room_box.add_child(share_row)
	var share_lbl := Label.new()
	share_lbl.text = "房间码 / 地址（发给朋友）："
	share_row.add_child(share_lbl)
	_share_field = LineEdit.new()
	_share_field.editable = false
	_share_field.custom_minimum_size = Vector2(260, 42)
	share_row.add_child(_share_field)
	var copy_btn: Button = main._button("复制")
	copy_btn.pressed.connect(_on_copy_share)
	share_row.add_child(copy_btn)

	_header_label = Label.new()
	_header_label.add_theme_font_size_override("font_size", 18)
	_header_label.add_theme_color_override("font_color", UITheme.color("accent"))
	_room_box.add_child(_header_label)

	_slots_box = VBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 6)
	_room_box.add_child(_slots_box)

	# 局数设置（房主可编辑，客人只读可见）
	var limits := HBoxContainer.new()
	limits.add_theme_constant_override("separation", 8)
	_room_box.add_child(limits)
	var limits_lbl := Label.new()
	limits_lbl.text = "系列赛局数："
	limits.add_child(limits_lbl)
	_match_limit_spin = SpinBox.new()
	_match_limit_spin.min_value = KongRules.MIN_MATCH_LIMIT
	_match_limit_spin.max_value = KongRules.MAX_MATCH_LIMIT
	_match_limit_spin.step = 1
	_match_limit_spin.value = KongRules.DEFAULT_MATCH_LIMIT
	_match_limit_spin.custom_minimum_size = Vector2(100, 0)
	limits.add_child(_match_limit_spin)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	_room_box.add_child(controls)

	_ready_button = main._button("准备")
	_ready_button.pressed.connect(_on_ready_pressed)
	controls.add_child(_ready_button)

	_start_button = main._button("开始对局")
	_start_button.pressed.connect(_on_start_pressed)
	controls.add_child(_start_button)

	_disband_button = main._button("解散房间")
	_disband_button.add_theme_color_override("font_color", UITheme.color("danger"))
	_disband_button.pressed.connect(GameState.request_close_room)
	controls.add_child(_disband_button)

	_invite_button = main._button("邀请好友")
	_invite_button.pressed.connect(main._on_invite_friends)
	controls.add_child(_invite_button)

	_leave_button = main._button("退出房间")
	_leave_button.pressed.connect(_leave_room)
	controls.add_child(_leave_button)

func _show_menu() -> void:
	if _menu_box != null:
		_menu_box.visible = true
	if _room_box != null:
		_room_box.visible = false

func _show_room() -> void:
	if _menu_box != null:
		_menu_box.visible = false
	if _room_box != null:
		_room_box.visible = true

func host_game() -> void:
	Network.host_game({"name": main._entered_name()}, main._entered_port())

## 直连加入（高级：IP:端口）。
func join_game() -> void:
	var address: String = main.address_input.text.strip_edges()
	if address.is_empty():
		main._show_toast("请输入房主 IP。")
		return
	main._reconnect_expected = false  # 正常加入，不触发重连
	Network.join_game(address, {"name": main._entered_name()}, main._entered_port())

## 凭房间码加入：向目录查地址后连接。
func join_by_code() -> void:
	var code: String = main.room_code_input.text.strip_edges()
	if code.is_empty():
		main._show_toast("请输入房间码。")
		return
	if main.directory == null or not main.directory.is_configured():
		main._show_toast("未配置目录服务：请到 设置 → 目录地址 填写（或用高级里的 IP 直连）。")
		return
	main._reconnect_expected = false
	main._show_toast("正在查询房间 %s…" % code.to_upper())
	main.directory.join_room(code, func(ok: bool, data: Dictionary):
		if ok and data.has("host"):
			var host := str(data["host"])
			var p := int(data.get("port", KongNetwork.DEFAULT_PORT))
			main.address_input.text = host
			main.port_input.text = str(p)
			Network.join_game(host, {"name": main._entered_name()}, p)
		else:
			main._show_toast("加入失败：房间不存在或已过期。"))

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

## 回到主菜单态（解散房间/中止/退出房间后调用）。
func reset_lobby() -> void:
	if _slots_box != null:
		for c in _slots_box.get_children():
			c.queue_free()
	_show_menu()
	main._view_defaulted_3d = false  # 回到大厅 → 下一局重新默认 3D
	main.lobby_panel.visible = true
	main.game_panel.visible = false

## 刷新房间界面（服务器逐 peer 下发的 lobby 快照）。
func update_lobby(lobby: Dictionary) -> void:
	main.latest_lobby = lobby
	main.lobby_panel.visible = true
	main.game_panel.visible = false
	_show_room()

	var your_id: int = int(lobby.get("your_id", -1))
	var is_host: bool = your_id == int(lobby.get("room_host", 0))
	var entries: Array = lobby.get("players", [])
	_header_label.text = "房间玩家（%d/%d）" % [entries.size(), int(lobby.get("max_players", KongRules.MAX_PLAYERS))]

	_rebuild_slots(lobby, is_host)

	# 房间地址
	_share_field.text = _share_text()

	# 局数：显示权威值；房主可编辑
	var limit := int(lobby.get("match_limit", KongRules.DEFAULT_MATCH_LIMIT))
	_match_limit_spin.set_value_no_signal(limit)
	_match_limit_spin.editable = is_host

	# 控制按钮
	var my_ready := false
	for e in entries:
		if int(e.get("id", -1)) == your_id:
			my_ready = bool(e.get("ready", false))
	_ready_button.visible = not is_host
	_ready_button.text = "取消准备" if my_ready else "准备"
	_ready_button.disabled = false

	_start_button.visible = is_host
	_disband_button.visible = is_host
	_invite_button.visible = is_host
	_leave_button.visible = not is_host

	if is_host:
		var ok := entries.size() >= int(lobby.get("min_players", KongRules.MIN_PLAYERS)) and _all_ready(lobby)
		_start_button.disabled = not ok

func _rebuild_slots(lobby: Dictionary, is_host: bool) -> void:
	for c in _slots_box.get_children():
		c.queue_free()
	var maxp := int(lobby.get("max_players", KongRules.MAX_PLAYERS))
	var host := int(lobby.get("room_host", 0))
	var taken: Dictionary = {}
	for e in lobby.get("players", []):
		taken[int(e.get("id", -1))] = e
	for seat in range(maxp):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var lbl := Label.new()
		if taken.has(seat):
			var e: Dictionary = taken[seat]
			lbl.text = "%d. %s %s %s" % [
				seat + 1,
				str(e.get("name", "")),
				"[房主]" if seat == host else "",
				"✔ 已准备" if bool(e.get("ready", false)) else "… 未准备",
			]
		else:
			lbl.text = "%d. 等待加入…" % [seat + 1]
		row.add_child(lbl)
		if is_host and taken.has(seat) and seat != host:
			var kick: Button = main._button("踢出")
			kick.pressed.connect(GameState.request_kick.bind(seat))
			row.add_child(kick)
		_slots_box.add_child(row)

## 非房主是否全部已准备（房主无需准备）。
func _all_ready(lobby: Dictionary) -> bool:
	var host := int(lobby.get("room_host", 0))
	var need := 0
	for e in lobby.get("players", []):
		if int(e.get("id", -1)) == host:
			continue
		need += 1
		if not bool(e.get("ready", false)):
			return false
	return need >= 1

func _share_text() -> String:
	if not str(main.room_code).is_empty():
		return str(main.room_code)
	var port: int = main._entered_port()
	if Network.is_host:
		return "%s:%d" % [_guess_lan_ip(), port]
	var addr: String = main.address_input.text.strip_edges()
	return "%s:%d" % [addr if not addr.is_empty() else "?", port]

## 房间码异步到位后刷新分享框。
func refresh_share() -> void:
	if _share_field != null:
		_share_field.text = _share_text()

func _guess_lan_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127."):
			return ip
	return "127.0.0.1"

func _on_copy_share() -> void:
	var text := _share_field.text
	DisplayServer.clipboard_set(text)
	main._show_toast("已复制房间地址：%s" % text)

func _on_ready_pressed() -> void:
	var my_ready := false
	var your_id := int(main.latest_lobby.get("your_id", -1))
	for e in main.latest_lobby.get("players", []):
		if int(e.get("id", -1)) == your_id:
			my_ready = bool(e.get("ready", false))
	GameState.request_set_ready(not my_ready)

func _on_start_pressed() -> void:
	GameState.request_start_match(int(_match_limit_spin.value))

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
