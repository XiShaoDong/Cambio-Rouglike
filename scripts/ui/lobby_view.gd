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
var _room_status_label: Label
var _player_count_label: Label
var _share_field: LineEdit
var _share_hint: Label
var _header_room_code: Label
var _center_art: Control
var _center_cards: Array = []
var _wide_active := false
var layout_mode_override := ""
var _resizing_layout := false
var _slots_box: Container
var _match_minus: Button
var _match_value: Label
var _stage_title: Label
var _effect_mode := "normal"
var _fixed_effect := ""
var _shop_enabled := true
var _is_room_host := false
var _mode_buttons: Array = []
var _effect_dropdown: OptionButton
var _shop_on_btn: Button
var _shop_off_btn: Button
var _match_plus: Button
var _match_limit_value := KongRules.DEFAULT_MATCH_LIMIT
var _disband_dialog: Control
var _disband_ok: Button
var _disband_close: Callable
var _ready_button: Button
var _start_button: Button
var _disband_button: Button
var _invite_button: Button
var _leave_button: Button
var _panel: PanelContainer
var _avatar_label: Label
var _nickname_label: Label
var _edit_button: Button
var _advanced_toggle: Button
var _advanced_box: VBoxContainer
var _rejoin_button: Button
var _nickname_dialog: Control
var _nickname_close: Callable
var _nickname_ok: Button
var _nickname_edit: LineEdit

func _init(owner_node: Node) -> void:
	main = owner_node

## 构建大厅界面（需已存在 main.lobby_panel）。
func build() -> void:
	_build_menu()
	_build_room()
	_show_menu()

func _build_menu() -> void:
	_wide_active = _use_wide_layout()
	_apply_frame_style()
	if _wide_active:
		_build_menu_wide()
	else:
		_build_menu_compact()

func _build_menu_wide() -> void:
	_panel = main.lobby_panel.get_parent() as PanelContainer
	_menu_box = VBoxContainer.new()
	_menu_box.name = "MenuWide"
	_menu_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_menu_box.add_theme_constant_override("separation", 10)
	main.lobby_panel.add_child(_menu_box)
	if not main.resized.is_connected(_on_main_resized):
		main.resized.connect(_on_main_resized)
	_update_panel_size()

	# Header
	var header := HBoxContainer.new()
	header.name = "Header"
	header.custom_minimum_size = Vector2(0, 68)
	header.add_theme_constant_override("separation", 14)
	_menu_box.add_child(header)
	var logo := TextureRect.new()
	logo.texture = load("res://icon.svg")
	logo.custom_minimum_size = Vector2(44, 44)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(logo)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 6)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(brand)
	var brand_title := Label.new()
	brand_title.text = "KONG · LAN"
	brand_title.add_theme_font_size_override("font_size", 24)
	brand_title.add_theme_color_override("font_color", UITheme.color("text_primary"))
	brand.add_child(brand_title)
	var brand_mvp := Label.new()
	brand_mvp.text = "MVP"
	brand_mvp.add_theme_font_size_override("font_size", 14)
	brand_mvp.add_theme_color_override("font_color", UITheme.color("accent"))
	brand_mvp.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	brand.add_child(brand_mvp)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	status_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(status_row)
	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_color_override("font_color", UITheme.color("success"))
	status_row.add_child(dot)
	main.lobby_status_label = Label.new()
	main.lobby_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.lobby_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	main.lobby_status_label.add_theme_font_size_override("font_size", 12)
	main.lobby_status_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	main.lobby_status_label.custom_minimum_size = Vector2(280, 0)
	status_row.add_child(main.lobby_status_label)
	var settings: Button = main._button("⚙")
	settings.name = "SettingsButton"
	settings.custom_minimum_size = Vector2(42, 42)
	settings.tooltip_text = "设置（ESC）"
	settings.pressed.connect(main._toggle_settings)
	_apply_secondary_style(settings)
	header.add_child(settings)
	main.lobby_status_label.text = "输入昵称，创建房间或凭房间码加入。"

	_menu_box.add_child(_divider_line())

	var content := HBoxContainer.new()
	content.name = "MainContent"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	_menu_box.add_child(content)

	# 左：控制面板
	var left := PanelContainer.new()
	left.name = "LobbyPanel"
	var left_style := StyleBoxFlat.new()
	left_style.bg_color = UITheme.color("bg_surface")
	left_style.bg_color.a = 0.84
	left_style.set_corner_radius_all(14)
	left_style.set_content_margin_all(20)
	left_style.border_color = UITheme.color("border")
	left_style.set_border_width_all(1)
	left.add_theme_stylebox_override("panel", left_style)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 58.0
	left.custom_minimum_size = Vector2(560, 0)
	content.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 12)
	left.add_child(lv)

	# 玩家资料
	var profile := PanelContainer.new()
	profile.name = "PlayerProfile"
	profile.add_theme_stylebox_override("panel", _card_style())
	lv.add_child(profile)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 14)
	profile.add_child(prow)
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(56, 56)
	avatar.size = Vector2(56, 56)
	var av := StyleBoxFlat.new()
	av.bg_color = UITheme.color("accent_soft")
	av.set_corner_radius_all(28)
	av.border_color = UITheme.color("border_strong")
	av.set_border_width_all(2)
	avatar.add_theme_stylebox_override("panel", av)
	prow.add_child(avatar)
	_avatar_label = Label.new()
	_avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar_label.add_theme_font_size_override("font_size", 22)
	_avatar_label.add_theme_color_override("font_color", UITheme.color("accent"))
	avatar.add_child(_avatar_label)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(info)
	var caption := Label.new()
	caption.text = "当前玩家"
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", UITheme.color("text_muted"))
	info.add_child(caption)
	_nickname_label = Label.new()
	_nickname_label.add_theme_font_size_override("font_size", 21)
	_nickname_label.add_theme_color_override("font_color", UITheme.color("text_primary"))
	info.add_child(_nickname_label)
	var nick_hint := Label.new()
	nick_hint.text = "本地昵称 · 仅用于显示"
	nick_hint.add_theme_font_size_override("font_size", 10)
	nick_hint.add_theme_color_override("font_color", UITheme.color("text_muted"))
	info.add_child(nick_hint)
	_edit_button = main._button("✎")
	_edit_button.name = "EditNickname"
	_edit_button.custom_minimum_size = Vector2(44, 44)
	_edit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_edit_button.tooltip_text = "修改昵称（仅用于之后创建/加入房间，不改变当前连接身份）"
	_edit_button.pressed.connect(_open_nickname_dialog)
	_apply_secondary_style(_edit_button)
	prow.add_child(_edit_button)

	main.name_input = LineEdit.new()
	main.name_input.visible = false
	main.name_input.text = str(Settings.get_setting("profile", "nickname", "玩家"))
	lv.add_child(main.name_input)
	refresh_player_info()

	# 加入房间（独立卡片）
	var join_card := PanelContainer.new()
	join_card.name = "JoinCard"
	join_card.add_theme_stylebox_override("panel", _card_style())
	lv.add_child(join_card)
	var join_vb := VBoxContainer.new()
	join_vb.add_theme_constant_override("separation", 10)
	join_card.add_child(join_vb)
	var join_label := Label.new()
	join_label.text = "加入现有房间"
	join_label.add_theme_font_size_override("font_size", 13)
	join_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	join_vb.add_child(join_label)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 12)
	join_vb.add_child(code_row)
	main.room_code_input = LineEdit.new()
	main.room_code_input.placeholder_text = "请输入房间码（如：K7X2Q9）"
	main.room_code_input.custom_minimum_size = Vector2(0, 52)
	main.room_code_input.clear_button_enabled = true
	main.room_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.room_code_input.size_flags_stretch_ratio = 68.0
	_style_input(main.room_code_input)
	code_row.add_child(main.room_code_input)
	var join_code: Button = main._button("⇥  加入房间")
	join_code.custom_minimum_size = Vector2(0, 52)
	join_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_code.size_flags_stretch_ratio = 32.0
	join_code.pressed.connect(join_by_code)
	join_code.disabled = main.is_dev_join
	_apply_primary_style(join_code)
	code_row.add_child(join_code)

	# 创建房间主操作
	var host: Button = main._button("＋   创建房间\n开启一场新的对局")
	host.custom_minimum_size = Vector2(0, 92)
	host.add_theme_font_size_override("font_size", 16)
	host.pressed.connect(host_game)
	host.disabled = main.is_dev_join
	_apply_primary_style(host)
	lv.add_child(host)

	# 高级连接
	_advanced_toggle = main._button("›  高级连接选项\n       IP 直连 · 手动配置")
	_advanced_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_advanced_toggle.custom_minimum_size = Vector2(0, 70)
	_advanced_toggle.add_theme_font_size_override("font_size", 13)
	_apply_secondary_style(_advanced_toggle)
	lv.add_child(_advanced_toggle)
	_advanced_box = VBoxContainer.new()
	_advanced_box.visible = false
	_advanced_box.add_theme_constant_override("separation", 8)
	lv.add_child(_advanced_box)
	_advanced_toggle.pressed.connect(func():
		_advanced_box.visible = not _advanced_box.visible
		_advanced_toggle.text = ("⌄  高级连接选项\n       IP 直连 · 手动配置" if _advanced_box.visible else "›  高级连接选项\n       IP 直连 · 手动配置"))
	var adv_row := HBoxContainer.new()
	adv_row.add_theme_constant_override("separation", 10)
	_advanced_box.add_child(adv_row)
	main.address_input = LineEdit.new()
	main.address_input.placeholder_text = "房主 IP"
	main.address_input.text = "127.0.0.1"
	main.address_input.custom_minimum_size = Vector2(0, 44)
	main.address_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_input(main.address_input)
	adv_row.add_child(main.address_input)
	main.port_input = LineEdit.new()
	main.port_input.placeholder_text = "端口"
	main.port_input.text = str(KongNetwork.DEFAULT_PORT)
	main.port_input.custom_minimum_size = Vector2(90, 44)
	main.port_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_input(main.port_input)
	adv_row.add_child(main.port_input)
	var join_ip: Button = main._button("直连加入")
	join_ip.custom_minimum_size = Vector2(100, 44)
	join_ip.pressed.connect(join_game)
	join_ip.disabled = main.is_dev_join
	_apply_secondary_style(join_ip)
	adv_row.add_child(join_ip)
	var dev: Button = main._button("开发者：本机双开")
	dev.custom_minimum_size = Vector2(0, 40)
	dev.pressed.connect(dev_launch_second)
	dev.add_theme_color_override("font_color", UITheme.color("success"))
	dev.disabled = main.is_dev_join
	_apply_secondary_style(dev)
	_advanced_box.add_child(dev)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(spacer)
	_rejoin_button = main._button("↻  重连上次对局")
	_rejoin_button.name = "RejoinEntry"
	_rejoin_button.custom_minimum_size = Vector2(0, 62)
	_rejoin_button.visible = false
	_rejoin_button.pressed.connect(main._do_reconnect)
	_apply_secondary_style(_rejoin_button)
	lv.add_child(_rejoin_button)

	# 右：视觉区（背景图由 main 铺满；这里只放低对比水印）
	var visual := Control.new()
	visual.name = "GameVisual"
	visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visual.size_flags_stretch_ratio = 42.0
	visual.custom_minimum_size = Vector2(300, 0)
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(visual)
	var mark := Label.new()
	mark.text = "KONG"
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_font_size_override("font_size", 118)
	mark.add_theme_color_override("font_color", Color(0.82, 0.86, 1.0, 0.10))
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(mark)
	var mark_sub := Label.new()
	mark_sub.text = "LAN MVP"
	mark_sub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark_sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark_sub.offset_top = 72
	mark_sub.add_theme_font_size_override("font_size", 14)
	mark_sub.add_theme_color_override("font_color", Color(0.82, 0.86, 1.0, 0.18))
	mark_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(mark_sub)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	var footer_text := Label.new()
	footer_text.text = "KONG · LAN MVP   |   连接你的游戏世界"
	footer_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer_text.add_theme_font_size_override("font_size", 11)
	footer_text.add_theme_color_override("font_color", UITheme.color("text_muted"))
	footer.add_child(footer_text)
	var footer_line := ColorRect.new()
	footer_line.color = UITheme.color("border")
	footer_line.color.a = 0.30
	footer_line.custom_minimum_size = Vector2(0, 1)
	footer_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(footer_line)
	_menu_box.add_child(footer)

	_ensure_nickname_dialog()

func _build_menu_compact() -> void:
	_panel = main.lobby_panel.get_parent() as PanelContainer
	_menu_box = VBoxContainer.new()
	_menu_box.name = "MenuBox"
	_menu_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_menu_box.add_theme_constant_override("separation", 12)
	main.lobby_panel.add_child(_menu_box)
	if not main.resized.is_connected(_on_main_resized):
		main.resized.connect(_on_main_resized)
	_update_panel_size()

	var lobby_title := Label.new()
	lobby_title.text = "KONG  ·  LAN MVP"
	lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_title.add_theme_font_size_override("font_size", 34)
	lobby_title.add_theme_color_override("font_color", UITheme.color("accent"))
	_menu_box.add_child(lobby_title)

	main.lobby_status_label = Label.new()
	main.lobby_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.lobby_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.lobby_status_label.add_theme_font_size_override("font_size", 13)
	main.lobby_status_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	main.lobby_status_label.text = "输入昵称，创建房间或凭房间码加入。"
	_menu_box.add_child(main.lobby_status_label)

	# 当前玩家信息卡
	var player_card := PanelContainer.new()
	player_card.name = "PlayerCard"
	player_card.add_theme_stylebox_override("panel", _card_style())
	_menu_box.add_child(player_card)
	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 12)
	player_card.add_child(player_row)
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(44, 44)
	avatar.size = Vector2(44, 44)
	var avatar_style := StyleBoxFlat.new()
	avatar_style.bg_color = UITheme.color("accent")
	avatar_style.set_corner_radius_all(22)
	avatar.add_theme_stylebox_override("panel", avatar_style)
	player_row.add_child(avatar)
	_avatar_label = Label.new()
	_avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar_label.add_theme_font_size_override("font_size", 18)
	_avatar_label.add_theme_color_override("font_color", Color(0.08, 0.09, 0.12))
	avatar.add_child(_avatar_label)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	player_row.add_child(info)
	var caption := Label.new()
	caption.text = "当前玩家"
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	info.add_child(caption)
	_nickname_label = Label.new()
	_nickname_label.add_theme_font_size_override("font_size", 20)
	_nickname_label.add_theme_color_override("font_color", UITheme.color("text_primary"))
	info.add_child(_nickname_label)
	_edit_button = main._button("✎")
	_edit_button.name = "EditNickname"
	_edit_button.custom_minimum_size = Vector2(44, 44)
	_edit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_edit_button.tooltip_text = "修改昵称（仅用于之后创建/加入房间，不改变当前连接身份）"
	_edit_button.pressed.connect(_open_nickname_dialog)
	_apply_secondary_style(_edit_button)
	player_row.add_child(_edit_button)

	# 隐藏的昵称存储（保持 _entered_name / dev join 兼容）
	main.name_input = LineEdit.new()
	main.name_input.visible = false
	main.name_input.text = str(Settings.get_setting("profile", "nickname", "玩家"))
	_menu_box.add_child(main.name_input)
	refresh_player_info()

	# 加入现有房间（独立卡片）
	var join_card := PanelContainer.new()
	join_card.name = "JoinCard"
	join_card.add_theme_stylebox_override("panel", _card_style())
	_menu_box.add_child(join_card)
	var join_vb := VBoxContainer.new()
	join_vb.add_theme_constant_override("separation", 8)
	join_card.add_child(join_vb)
	var join_label := Label.new()
	join_label.text = "加入现有房间"
	join_label.add_theme_font_size_override("font_size", 14)
	join_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	join_vb.add_child(join_label)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	join_vb.add_child(code_row)
	main.room_code_input = LineEdit.new()
	main.room_code_input.placeholder_text = "K7X2Q9"
	main.room_code_input.custom_minimum_size = Vector2(0, 50)
	main.room_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_input(main.room_code_input)
	code_row.add_child(main.room_code_input)
	var join_code: Button = main._button("加入房间")
	join_code.custom_minimum_size = Vector2(120, 50)
	join_code.pressed.connect(join_by_code)
	join_code.disabled = main.is_dev_join
	_apply_secondary_style(join_code)
	code_row.add_child(join_code)

	# 创建房间（主操作）
	var host: Button = main._button("＋  创建房间\n开启一场新的对局")
	host.text = "＋  创建房间\n开启一场新的对局"
	host.custom_minimum_size = Vector2(0, 78)
	host.add_theme_font_size_override("font_size", 18)
	host.pressed.connect(host_game)
	host.disabled = main.is_dev_join
	_apply_primary_style(host)
	_menu_box.add_child(host)

	# 弹性空白：主要操作在上，次要操作靠下
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0, 8)
	_menu_box.add_child(spacer)

	# 高级连接（折叠）
	_advanced_toggle = main._button("›  高级连接选项\n    IP 直连 · 手动配置")
	_advanced_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_advanced_toggle.custom_minimum_size = Vector2(0, 58)
	_advanced_toggle.add_theme_font_size_override("font_size", 13)
	_apply_secondary_style(_advanced_toggle)
	_menu_box.add_child(_advanced_toggle)
	_advanced_box = VBoxContainer.new()
	_advanced_box.visible = false
	_advanced_box.add_theme_constant_override("separation", 8)
	_menu_box.add_child(_advanced_box)
	_advanced_toggle.pressed.connect(func():
		_advanced_box.visible = not _advanced_box.visible
		_advanced_toggle.text = ("⌄  高级连接选项\n    IP 直连 · 手动配置" if _advanced_box.visible else "›  高级连接选项\n    IP 直连 · 手动配置"))
	var adv_row := HBoxContainer.new()
	adv_row.add_theme_constant_override("separation", 10)
	_advanced_box.add_child(adv_row)
	main.address_input = LineEdit.new()
	main.address_input.placeholder_text = "房主 IP"
	main.address_input.text = "127.0.0.1"
	main.address_input.custom_minimum_size = Vector2(0, 44)
	main.address_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_input(main.address_input)
	adv_row.add_child(main.address_input)
	main.port_input = LineEdit.new()
	main.port_input.placeholder_text = "端口"
	main.port_input.text = str(KongNetwork.DEFAULT_PORT)
	main.port_input.custom_minimum_size = Vector2(90, 44)
	main.port_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_input(main.port_input)
	adv_row.add_child(main.port_input)
	var join_ip: Button = main._button("直连加入")
	join_ip.custom_minimum_size = Vector2(100, 44)
	join_ip.pressed.connect(join_game)
	join_ip.disabled = main.is_dev_join
	adv_row.add_child(join_ip)
	var dev: Button = main._button("开发者：本机双开")
	dev.custom_minimum_size = Vector2(0, 40)
	dev.pressed.connect(dev_launch_second)
	dev.add_theme_color_override("font_color", UITheme.color("success"))
	dev.disabled = main.is_dev_join
	_advanced_box.add_child(dev)

	# 重连入口（底部）
	_rejoin_button = main._button("↻  重连上次对局")
	_rejoin_button.name = "RejoinEntry"
	_rejoin_button.custom_minimum_size = Vector2(0, 54)
	_rejoin_button.visible = false
	_rejoin_button.pressed.connect(main._do_reconnect)
	_apply_secondary_style(_rejoin_button)
	_menu_box.add_child(_rejoin_button)

	# 昵称编辑弹窗
	_ensure_nickname_dialog()

func _apply_frame_style() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var st := StyleBoxFlat.new()
	st.set_content_margin_all(22)
	if _wide_active:
		st.bg_color = Color(0, 0, 0, 0)
		st.border_width_left = 0
		st.border_width_top = 0
		st.border_width_right = 0
		st.border_width_bottom = 0
	else:
		st.bg_color = UITheme.color("bg_elevated")
		st.bg_color.a = 0.96
		st.set_corner_radius_all(16)
		st.border_color = UITheme.color("border")
		st.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", st)

func _on_main_resized() -> void:
	if _resizing_layout:
		return
	if _room_box != null and _room_box.visible and layout_mode_override == "" \
			and str(Settings.get_setting("display", "lobby_layout", "auto")) == "auto":
		if _use_wide_layout() != _wide_active:
			_resizing_layout = true
			refresh_layout()
			_resizing_layout = false
			return
	_update_panel_size()

func _update_panel_size() -> void:
	if _panel == null or not is_instance_valid(_panel) or main == null:
		return
	var max_w := 480.0
	if _wide_active:
		max_w = 1680.0
	elif _room_box != null and _room_box.visible:
		max_w = 680.0
	var w: float = minf(max_w, maxf(320.0, main.size.x * 0.9))
	var h: float = maxf(500.0, main.size.y - 56.0) if _wide_active \
		else minf(760.0, maxf(480.0, main.size.y * 0.92))
	_panel.custom_minimum_size = Vector2(w, h)
	_update_seat_columns()

func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.color("bg_elevated")
	style.bg_color.a = 0.62
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	style.border_color = UITheme.color("border")
	style.set_border_width_all(1)
	return style

func _style_input(edit: LineEdit) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = UITheme.color("bg_elevated")
	st.bg_color.a = 0.62
	st.set_corner_radius_all(10)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	st.border_color = UITheme.color("border")
	st.set_border_width_all(1)
	edit.add_theme_stylebox_override("normal", st)
	var focus: StyleBoxFlat = st.duplicate()
	focus.border_color = UITheme.color("accent_focus")
	edit.add_theme_stylebox_override("focus", focus)

func _divider_line(alpha: float = 0.30) -> Control:
	var line := ColorRect.new()
	line.color = UITheme.color("border")
	line.color.a = alpha
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line

func refresh_player_info() -> void:
	if _nickname_label == null or main.name_input == null:
		return
	var n: String = main.name_input.text.strip_edges()
	if n.is_empty():
		n = "玩家"
	_nickname_label.text = n
	if _avatar_label != null:
		_avatar_label.text = n.left(1)

## 统一大厅风格弹窗：全屏遮罩 + 居中卡片 + accent 标题（与设置菜单同款）。
## 返回 {root, vbox, close}；close 为关闭回调（Callable）。
func _make_modal(title_text: String) -> Dictionary:
	var root := Control.new()
	root.name = "StyledModal"
	root.z_index = 120
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = UITheme.color("bg_elevated")
	st.bg_color.a = 0.98
	st.set_corner_radius_all(14)
	st.set_content_margin_all(24)
	st.border_color = UITheme.color("border")
	st.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", st)
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UITheme.color("accent"))
	vbox.add_child(title)
	var close := func():
		root.visible = false
	dim.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close.call())
	return {"root": root, "vbox": vbox, "close": close}

func _ensure_nickname_dialog() -> void:
	if _nickname_dialog != null and is_instance_valid(_nickname_dialog):
		return
	var modal := _make_modal("修改玩家名称")
	_nickname_dialog = modal.root
	_nickname_close = modal.close
	_nickname_edit = LineEdit.new()
	_nickname_edit.custom_minimum_size = Vector2(320, 44)
	_nickname_edit.max_length = 16
	_style_input(_nickname_edit)
	modal.vbox.add_child(_nickname_edit)
	_nickname_ok = main._button("保存")
	_nickname_ok.custom_minimum_size = Vector2(130, 44)
	_nickname_ok.disabled = true
	_nickname_ok.pressed.connect(_save_nickname)
	_apply_primary_style(_nickname_ok)
	var cancel: Button = main._button("取消")
	cancel.custom_minimum_size = Vector2(130, 44)
	cancel.pressed.connect(func():
		_nickname_close.call())
	_apply_secondary_style(cancel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_nickname_ok)
	row.add_child(cancel)
	modal.vbox.add_child(row)
	_nickname_edit.text_changed.connect(func(_t: String):
		_nickname_ok.disabled = _nickname_edit.text.strip_edges().is_empty())
	_nickname_edit.text_submitted.connect(func(_t: String): _save_nickname())
	main.add_child(_nickname_dialog)

func _open_nickname_dialog() -> void:
	if _nickname_dialog == null or not is_instance_valid(_nickname_dialog):
		return
	_nickname_edit.text = main.name_input.text
	_nickname_ok.disabled = _nickname_edit.text.strip_edges().is_empty()
	_nickname_dialog.visible = true
	_nickname_edit.call_deferred("grab_focus")
	_nickname_edit.call_deferred("select_all")

func _save_nickname() -> void:
	var n: String = _nickname_edit.text.strip_edges().left(16)
	if n.is_empty():
		return
	main.name_input.text = n
	Settings.set_setting("profile", "nickname", n)
	refresh_player_info()
	_nickname_close.call()
	main._show_toast("昵称已更新：%s" % n)

func show_rejoin(on: bool) -> void:
	if _rejoin_button != null:
		_rejoin_button.visible = on

func _build_room() -> void:
	_wide_active = _use_wide_layout()
	_apply_frame_style()
	if _wide_active:
		_build_room_wide()
	else:
		_build_room_compact()

func _use_wide_layout() -> bool:
	if layout_mode_override == "wide":
		return true
	if layout_mode_override == "compact":
		return false
	var mode := str(Settings.get_setting("display", "lobby_layout", "auto"))
	if mode == "wide":
		return true
	if mode == "compact":
		return false
	return main != null and main.size.x >= 1100.0

## 设置菜单切换布局后调用：重建房间布局并保留当前快照。
func refresh_layout() -> void:
	var wide := _use_wide_layout()
	if wide == _wide_active and _menu_box != null and _room_box != null:
		_update_panel_size()
		return
	_wide_active = wide
	_rebuild_all()

func _build_room_compact() -> void:
	_room_box = VBoxContainer.new()
	_room_box.name = "RoomBox"
	_room_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_box.add_theme_constant_override("separation", 8)
	main.lobby_panel.add_child(_room_box)

	_header_label = Label.new()
	_header_label.text = "房间大厅"
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", 28)
	_header_label.add_theme_color_override("font_color", UITheme.color("accent"))
	_room_box.add_child(_header_label)
	_room_status_label = Label.new()
	_room_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_room_status_label.add_theme_font_size_override("font_size", 13)
	_room_status_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	_room_box.add_child(_room_status_label)

	# 房间码 / 邀请地址
	var invite_panel := PanelContainer.new()
	invite_panel.name = "InvitePanel"
	invite_panel.add_theme_stylebox_override("panel", _card_style())
	_room_box.add_child(invite_panel)
	var invite_vb := VBoxContainer.new()
	invite_vb.add_theme_constant_override("separation", 6)
	invite_panel.add_child(invite_vb)
	var invite_lbl := Label.new()
	invite_lbl.text = "房间码 / 邀请地址"
	invite_lbl.add_theme_font_size_override("font_size", 13)
	invite_lbl.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	invite_vb.add_child(invite_lbl)
	var share_row := HBoxContainer.new()
	share_row.add_theme_constant_override("separation", 10)
	invite_vb.add_child(share_row)
	_share_field = LineEdit.new()
	_share_field.editable = false
	_share_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_share_field.custom_minimum_size = Vector2(0, 48)
	_share_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_share_field.add_theme_font_size_override("font_size", 26)
	_share_field.add_theme_color_override("font_color", UITheme.color("text_primary"))
	share_row.add_child(_share_field)
	var copy_btn: Button = main._button("复制")
	copy_btn.custom_minimum_size = Vector2(96, 48)
	copy_btn.pressed.connect(_on_copy_share)
	_apply_secondary_style(copy_btn)
	share_row.add_child(copy_btn)
	_share_hint = Label.new()
	_share_hint.text = "复制房间码发给朋友；无房间码时复制局域网直连地址。"
	_share_hint.add_theme_font_size_override("font_size", 11)
	_share_hint.add_theme_color_override("font_color", UITheme.color("text_muted"))
	invite_vb.add_child(_share_hint)

	# 固定 4 席位
	var seats_head := HBoxContainer.new()
	seats_head.add_theme_constant_override("separation", 8)
	_room_box.add_child(seats_head)
	var seats_lbl := Label.new()
	seats_lbl.text = "房间玩家"
	seats_lbl.add_theme_font_size_override("font_size", 15)
	seats_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seats_head.add_child(seats_lbl)
	_player_count_label = Label.new()
	_player_count_label.add_theme_font_size_override("font_size", 13)
	_player_count_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	seats_head.add_child(_player_count_label)
	_slots_box = GridContainer.new()
	_slots_box.name = "SeatGrid"
	_slots_box.columns = 2
	_slots_box.add_theme_constant_override("h_separation", 10)
	_slots_box.add_theme_constant_override("v_separation", 10)
	_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_box.add_child(_slots_box)

	# 系列赛局数（房主 ±，其他只读）
	var series_panel := PanelContainer.new()
	series_panel.name = "SeriesPanel"
	series_panel.add_theme_stylebox_override("panel", _card_style())
	_room_box.add_child(series_panel)
	var series_row := HBoxContainer.new()
	series_row.add_theme_constant_override("separation", 10)
	series_panel.add_child(series_row)
	var series_lbl := Label.new()
	series_lbl.text = "系列赛局数"
	series_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	series_lbl.add_theme_font_size_override("font_size", 15)
	series_row.add_child(series_lbl)
	_match_minus = main._button("−")
	_match_minus.custom_minimum_size = Vector2(40, 40)
	_match_minus.pressed.connect(_change_match_limit.bind(-1))
	_apply_secondary_style(_match_minus)
	series_row.add_child(_match_minus)
	_match_value = Label.new()
	_match_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_value.custom_minimum_size = Vector2(56, 0)
	_match_value.add_theme_font_size_override("font_size", 22)
	_match_value.add_theme_color_override("font_color", UITheme.color("accent"))
	series_row.add_child(_match_value)
	_match_plus = main._button("+")
	_match_plus.custom_minimum_size = Vector2(40, 40)
	_match_plus.pressed.connect(_change_match_limit.bind(1))
	_apply_secondary_style(_match_plus)
	series_row.add_child(_match_plus)

	# 主操作：开始对局 / 非房主准备
	_ready_button = main._button("准备")
	_ready_button.custom_minimum_size = Vector2(0, 50)
	_ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_button.add_theme_font_size_override("font_size", 18)
	_ready_button.pressed.connect(_on_ready_pressed)
	_apply_secondary_style(_ready_button)
	_room_box.add_child(_ready_button)
	_start_button = main._button("开始对局")
	_start_button.custom_minimum_size = Vector2(0, 56)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.add_theme_font_size_override("font_size", 19)
	_start_button.pressed.connect(_on_start_pressed)
	_apply_primary_style(_start_button)
	_room_box.add_child(_start_button)

	# 次级操作：邀请 / 解散或离开
	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation", 10)
	_room_box.add_child(secondary)
	_invite_button = main._button("邀请好友")
	_invite_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invite_button.custom_minimum_size = Vector2(0, 42)
	_invite_button.pressed.connect(main._on_invite_friends)
	_apply_secondary_style(_invite_button)
	secondary.add_child(_invite_button)
	_disband_button = main._button("解散房间")
	_disband_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_disband_button.custom_minimum_size = Vector2(0, 42)
	_disband_button.add_theme_color_override("font_color", UITheme.color("danger"))
	_disband_button.pressed.connect(_open_disband_dialog)
	_apply_danger_style(_disband_button)
	secondary.add_child(_disband_button)
	_leave_button = main._button("离开房间")
	_leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_leave_button.custom_minimum_size = Vector2(0, 42)
	_leave_button.pressed.connect(_leave_room)
	_apply_secondary_style(_leave_button)
	secondary.add_child(_leave_button)

	_ensure_disband_dialog()

func _build_room_wide() -> void:
	_room_box = VBoxContainer.new()
	_room_box.name = "RoomWide"
	_room_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_box.add_theme_constant_override("separation", 12)
	main.lobby_panel.add_child(_room_box)

	# 顶栏：品牌 / 状态（+ 分割线）
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.custom_minimum_size = Vector2(0, 48)
	_room_box.add_child(top)
	var logo := PanelContainer.new()
	logo.custom_minimum_size = Vector2(36, 36)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var logo_st := StyleBoxFlat.new()
	logo_st.bg_color = UITheme.color("accent_soft")
	logo_st.set_corner_radius_all(10)
	logo_st.set_content_margin_all(0)
	logo.add_theme_stylebox_override("panel", logo_st)
	top.add_child(logo)
	var logo_tex := TextureRect.new()
	logo_tex.texture = load("res://assets/Cards/back07.png")
	logo_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo_tex.offset_left = 5
	logo_tex.offset_right = -5
	logo_tex.offset_top = 5
	logo_tex.offset_bottom = -5
	logo_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.add_child(logo_tex)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(brand)
	var brand_title := Label.new()
	brand_title.text = "KONG"
	brand_title.add_theme_font_size_override("font_size", 16)
	brand_title.add_theme_color_override("font_color", UITheme.color("text_primary"))
	brand.add_child(brand_title)
	_header_label = Label.new()
	_header_label.text = "· LAN"
	_header_label.add_theme_font_size_override("font_size", 12)
	_header_label.add_theme_color_override("font_color", UITheme.color("accent"))
	brand.add_child(_header_label)
	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_font_size_override("font_size", 12)
	dot.add_theme_color_override("font_color", UITheme.color("success"))
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(dot)
	_room_status_label = Label.new()
	_room_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_room_status_label.add_theme_font_size_override("font_size", 12)
	_room_status_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	_room_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_room_status_label)
	_room_box.add_child(_divider_line())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_box.add_child(body)

	# 左列：房间玩家（透明底）
	var left := VBoxContainer.new()
	left.name = "PlayersColumn"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 27.0
	left.custom_minimum_size = Vector2(220, 0)
	body.add_child(left)
	var ltitle := Label.new()
	ltitle.text = "房间玩家"
	ltitle.add_theme_font_size_override("font_size", 15)
	ltitle.add_theme_color_override("font_color", UITheme.color("text_primary"))
	left.add_child(ltitle)
	_player_count_label = Label.new()
	_player_count_label.add_theme_font_size_override("font_size", 12)
	_player_count_label.add_theme_color_override("font_color", UITheme.color("text_muted"))
	left.add_child(_player_count_label)
	_slots_box = VBoxContainer.new()
	_slots_box.name = "SeatList"
	_slots_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_slots_box.add_theme_constant_override("separation", 8)
	left.add_child(_slots_box)

	# 中列：ROOM 01 舞台 + 房间码卡
	var center := PanelContainer.new()
	center.name = "CenterStage"
	var center_style := _card_style()
	center_style.bg_color = UITheme.color("bg_surface")
	center_style.set_content_margin_all(16)
	center_style.set_corner_radius_all(14)
	center.add_theme_stylebox_override("panel", center_style)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_stretch_ratio = 45.0
	center.custom_minimum_size = Vector2(340, 0)
	body.add_child(center)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	center.add_child(cv)
	var room_no := Label.new()
	room_no.name = "RoomNo"
	room_no.text = "ROOM 01"
	room_no.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_no.add_theme_font_size_override("font_size", 12)
	room_no.add_theme_color_override("font_color", UITheme.color("accent"))
	cv.add_child(room_no)
	_stage_title = Label.new()
	_stage_title.name = "StageTitle"
	_stage_title.text = "准备开始"
	_stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_title.add_theme_font_size_override("font_size", 24)
	_stage_title.add_theme_color_override("font_color", UITheme.color("text_primary"))
	cv.add_child(_stage_title)
	# 玩法选择：模式分段 slider（普通/随机/指定）+ 指定特效下拉（仅房主可改）
	var mode_seg := HBoxContainer.new()
	mode_seg.name = "ModeSegmented"
	mode_seg.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_seg.add_theme_constant_override("separation", 4)
	cv.add_child(mode_seg)
	_mode_buttons.clear()
	for entry in [["normal", "普通"], ["random", "随机"], ["fixed", "指定"]]:
		var mode_btn: Button = main._button(str(entry[1]))
		mode_btn.name = "Mode_" + str(entry[0])
		mode_btn.custom_minimum_size = Vector2(66, 30)
		mode_btn.add_theme_font_size_override("font_size", 13)
		mode_btn.toggle_mode = true
		mode_btn.pressed.connect(_change_effect_mode.bind(str(entry[0])))
		mode_seg.add_child(mode_btn)
		_mode_buttons.append([str(entry[0]), mode_btn])
	_effect_dropdown = OptionButton.new()
	_effect_dropdown.name = "EffectDropdown"
	_effect_dropdown.visible = false
	_effect_dropdown.custom_minimum_size = Vector2(0, 32)
	_effect_dropdown.add_theme_font_size_override("font_size", 13)
	for fx in TurnEffect.all():
		var fx_id := str(fx["id"])
		if fx_id == "none":
			continue  # 无特效 == 普通模式，不作下拉选项
		_effect_dropdown.add_item(str(fx["name"]))
		_effect_dropdown.set_item_metadata(_effect_dropdown.item_count - 1, fx_id)
	_effect_dropdown.item_selected.connect(func(idx: int):
		if _is_room_host and _effect_mode == "fixed":
			GameState.request_set_effect_mode("fixed", str(_effect_dropdown.get_item_metadata(idx)), main._next_action_id()))
	cv.add_child(_effect_dropdown)
	var stage_gap := Control.new()
	stage_gap.custom_minimum_size = Vector2(0, 2)
	cv.add_child(stage_gap)
	_center_art = Control.new()
	_center_art.name = "CenterArt"
	_center_art.custom_minimum_size = Vector2(0, 170)
	_center_art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_art.resized.connect(_layout_center_art)
	cv.add_child(_center_art)
	_center_cards.clear()
	var back_tex: Texture2D = load("res://assets/Cards/back07.png")
	for i in 3:
		var tr := TextureRect.new()
		tr.texture = back_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = Vector2(96, 134)
		tr.pivot_offset = tr.size * 0.5
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_center_art.add_child(tr)
		_center_cards.append(tr)
	var code_card := PanelContainer.new()
	code_card.name = "RoomCodeCard"
	var code_style := _card_style()
	code_style.content_margin_left = 16
	code_style.content_margin_right = 10
	code_style.content_margin_top = 10
	code_style.content_margin_bottom = 10
	code_style.bg_color = UITheme.color("bg_elevated")
	code_style.bg_color.a = 0.5
	code_card.add_theme_stylebox_override("panel", code_style)
	cv.add_child(code_card)
	var code_vb := VBoxContainer.new()
	code_vb.add_theme_constant_override("separation", 2)
	code_card.add_child(code_vb)
	var code_lbl := Label.new()
	code_lbl.text = "房间码"
	code_lbl.add_theme_font_size_override("font_size", 11)
	code_lbl.add_theme_color_override("font_color", UITheme.color("text_muted"))
	code_vb.add_child(code_lbl)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	code_vb.add_child(code_row)
	_share_field = LineEdit.new()
	_share_field.name = "ShareField"
	_share_field.editable = false
	_share_field.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_share_field.custom_minimum_size = Vector2(0, 44)
	_share_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_share_field.add_theme_font_size_override("font_size", 26)
	_share_field.add_theme_color_override("font_color", UITheme.color("text_primary"))
	_style_input(_share_field)
	code_row.add_child(_share_field)
	var copy_btn: Button = main._button("⧉")
	copy_btn.name = "CopyButton"
	copy_btn.custom_minimum_size = Vector2(40, 40)
	copy_btn.tooltip_text = "复制房间码 / 邀请信息"
	copy_btn.pressed.connect(_on_copy_share)
	_apply_secondary_style(copy_btn)
	code_row.add_child(copy_btn)
	_share_hint = Label.new()
	_share_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_share_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_share_hint.add_theme_font_size_override("font_size", 10)
	_share_hint.add_theme_color_override("font_color", UITheme.color("text_muted"))
	cv.add_child(_share_hint)

	# 右列：对局设置 + 操作（透明底）
	var right := VBoxContainer.new()
	right.name = "SettingsColumn"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 28.0
	right.custom_minimum_size = Vector2(240, 0)
	body.add_child(right)
	var stitle := Label.new()
	stitle.text = "对局设置"
	stitle.add_theme_font_size_override("font_size", 15)
	stitle.add_theme_color_override("font_color", UITheme.color("text_primary"))
	right.add_child(stitle)
	var series_card := PanelContainer.new()
	series_card.name = "SeriesCard"
	series_card.add_theme_stylebox_override("panel", _card_style())
	right.add_child(series_card)
	var series_vb := VBoxContainer.new()
	series_vb.add_theme_constant_override("separation", 8)
	series_card.add_child(series_vb)
	var series_row := HBoxContainer.new()
	series_row.add_theme_constant_override("separation", 8)
	series_vb.add_child(series_row)
	var series_lbl := Label.new()
	series_lbl.text = "系列赛局数"
	series_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	series_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	series_lbl.add_theme_font_size_override("font_size", 13)
	series_row.add_child(series_lbl)
	_match_minus = main._button("−")
	_match_minus.custom_minimum_size = Vector2(36, 36)
	_match_minus.pressed.connect(_change_match_limit.bind(-1))
	_apply_secondary_style(_match_minus)
	series_row.add_child(_match_minus)
	_match_value = Label.new()
	_match_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_value.custom_minimum_size = Vector2(44, 0)
	_match_value.add_theme_font_size_override("font_size", 18)
	_match_value.add_theme_color_override("font_color", UITheme.color("text_primary"))
	series_row.add_child(_match_value)
	_match_plus = main._button("+")
	_match_plus.custom_minimum_size = Vector2(36, 36)
	_match_plus.pressed.connect(_change_match_limit.bind(1))
	_apply_secondary_style(_match_plus)
	series_row.add_child(_match_plus)
	var series_hint := Label.new()
	series_hint.name = "SeriesHint"
	series_hint.text = "房主可修改对局参数"
	series_hint.add_theme_font_size_override("font_size", 11)
	series_hint.add_theme_color_override("font_color", UITheme.color("text_muted"))
	series_vb.add_child(series_hint)
	# 商店开关卡：仅开/关；关闭后非把末结算直接开下一局（仅房主可改）
	var shop_card := PanelContainer.new()
	shop_card.name = "ShopCard"
	shop_card.add_theme_stylebox_override("panel", _card_style())
	right.add_child(shop_card)
	var shop_vb := VBoxContainer.new()
	shop_vb.add_theme_constant_override("separation", 8)
	shop_card.add_child(shop_vb)
	var shop_lbl := Label.new()
	shop_lbl.text = "商店"
	shop_lbl.add_theme_font_size_override("font_size", 13)
	shop_lbl.add_theme_color_override("font_color", UITheme.color("text_primary"))
	shop_vb.add_child(shop_lbl)
	var shop_toggle := HBoxContainer.new()
	shop_toggle.add_theme_constant_override("separation", 6)
	shop_toggle.alignment = BoxContainer.ALIGNMENT_CENTER
	shop_vb.add_child(shop_toggle)
	_shop_on_btn = main._button("开")
	_shop_on_btn.name = "ShopOn"
	_shop_on_btn.custom_minimum_size = Vector2(64, 30)
	_shop_on_btn.toggle_mode = true
	_shop_on_btn.add_theme_font_size_override("font_size", 13)
	_shop_on_btn.pressed.connect(func(): _change_shop_enabled(true))
	shop_toggle.add_child(_shop_on_btn)
	_shop_off_btn = main._button("关")
	_shop_off_btn.name = "ShopOff"
	_shop_off_btn.custom_minimum_size = Vector2(64, 30)
	_shop_off_btn.toggle_mode = true
	_shop_off_btn.add_theme_font_size_override("font_size", 13)
	_shop_off_btn.pressed.connect(func(): _change_shop_enabled(false))
	shop_toggle.add_child(_shop_off_btn)
	var shop_hint := Label.new()
	shop_hint.name = "ShopHint"
	shop_hint.text = "关闭后结算直接进入下一局"
	shop_hint.add_theme_font_size_override("font_size", 11)
	shop_hint.add_theme_color_override("font_color", UITheme.color("text_muted"))
	shop_vb.add_child(shop_hint)
	var gap := Control.new()
	gap.name = "Spacer"
	gap.custom_minimum_size = Vector2(0, 14)
	right.add_child(gap)
	_ready_button = main._button("准备")
	_ready_button.custom_minimum_size = Vector2(0, 50)
	_ready_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ready_button.pressed.connect(_on_ready_pressed)
	_apply_secondary_style(_ready_button)
	right.add_child(_ready_button)
	_start_button = main._button("▶   开始对局")
	_start_button.custom_minimum_size = Vector2(0, 52)
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.add_theme_font_size_override("font_size", 16)
	_start_button.pressed.connect(_on_start_pressed)
	_apply_primary_style(_start_button)
	right.add_child(_start_button)
	var gap2 := Control.new()
	gap2.name = "Spacer2"
	gap2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(gap2)
	_invite_button = main._button("邀请好友")
	_invite_button.custom_minimum_size = Vector2(0, 46)
	_invite_button.pressed.connect(main._on_invite_friends)
	_apply_secondary_style(_invite_button)
	right.add_child(_invite_button)
	_disband_button = main._button("解散房间")
	_disband_button.custom_minimum_size = Vector2(0, 46)
	_disband_button.pressed.connect(_open_disband_dialog)
	_apply_danger_style(_disband_button)
	right.add_child(_disband_button)
	_leave_button = main._button("离开房间")
	_leave_button.custom_minimum_size = Vector2(0, 46)
	_leave_button.pressed.connect(_leave_room)
	_apply_secondary_style(_leave_button)
	right.add_child(_leave_button)
	_ensure_disband_dialog()

func _layout_center_art() -> void:
	if _center_art == null or _center_cards.is_empty():
		return
	var c := _center_art.size
	var cx := c.x * 0.5
	var cy := c.y * 0.52
	for i in _center_cards.size():
		var card: TextureRect = _center_cards[i]
		var off := (float(i) - 1.0) * 44.0
		card.size = Vector2(96, 134)
		card.pivot_offset = card.size * 0.5
		card.position = Vector2(cx + off - 48.0, cy - 67.0 + absf(off) * 0.12)
		card.rotation_degrees = (float(i) - 1.0) * 9.0

func _ensure_disband_dialog() -> void:
	if _disband_dialog != null and is_instance_valid(_disband_dialog):
		return
	var modal := _make_modal("解散房间")
	_disband_dialog = modal.root
	_disband_close = modal.close
	var text := Label.new()
	text.text = "确定解散整个房间？所有玩家都会回到主菜单。"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 14)
	text.add_theme_color_override("font_color", UITheme.color("text_primary"))
	modal.vbox.add_child(text)
	_disband_ok = main._button("解散")
	_disband_ok.custom_minimum_size = Vector2(130, 44)
	_disband_ok.pressed.connect(func():
		_disband_close.call()
		GameState.request_close_room())
	_apply_danger_style(_disband_ok)
	var cancel: Button = main._button("取消")
	cancel.custom_minimum_size = Vector2(130, 44)
	cancel.pressed.connect(func():
		_disband_close.call())
	_apply_secondary_style(cancel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(_disband_ok)
	row.add_child(cancel)
	modal.vbox.add_child(row)
	main.add_child(_disband_dialog)

func _apply_secondary_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.color("bg_elevated")
	normal.bg_color.a = 0.92
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(8)
	normal.border_color = UITheme.color("border")
	normal.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = UITheme.color("bg_surface_alt")
	btn.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = UITheme.color("bg_hover")
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", UITheme.color("text_primary"))

func _apply_danger_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.color("danger")
	normal.bg_color.a = 0.15
	normal.set_corner_radius_all(10)
	normal.set_content_margin_all(10)
	normal.border_color = UITheme.color("danger")
	normal.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = UITheme.color("danger")
	hover.bg_color.a = 0.28
	btn.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = UITheme.color("danger")
	pressed.bg_color.a = 0.4
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", UITheme.color("danger"))

func _apply_primary_style(btn: Button) -> void:
	var acc := UITheme.color("accent")
	var normal := StyleBoxFlat.new()
	normal.bg_color = acc
	normal.set_corner_radius_all(10)
	normal.set_content_margin_all(10)
	normal.border_color = UITheme.color("accent_hover")
	normal.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = UITheme.color("accent_hover")
	btn.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = UITheme.color("accent_pressed")
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", UITheme.color("text_on_accent"))

func _change_match_limit(delta: int) -> void:
	if main.latest_lobby.is_empty():
		return
	var your_id := int(main.latest_lobby.get("your_id", -1))
	if your_id != int(main.latest_lobby.get("room_host", 0)):
		return
	var v := clampi(_match_limit_value + delta, KongRules.MIN_MATCH_LIMIT, KongRules.MAX_MATCH_LIMIT)
	if v == _match_limit_value:
		return
	_match_limit_value = v
	_match_value.text = str(v)
	GameState.request_set_match_limit(v, main._next_action_id())

## 房主切换效果模式（局部乐观更新；服务器胁迫以广播为准）。
func _change_effect_mode(mode: String) -> void:
	if not _is_room_host or mode == _effect_mode:
		return
	_effect_mode = mode
	_refresh_gameplay_controls()
	GameState.request_set_effect_mode(mode, _fixed_effect, main._next_action_id())

## 房主切换指定特效。
func _change_fixed_effect(effect_id: String) -> void:
	if not _is_room_host or effect_id == _fixed_effect:
		return
	_fixed_effect = effect_id
	_refresh_gameplay_controls()
	GameState.request_set_effect_mode("fixed", effect_id, main._next_action_id())

## 房主开关商店。
func _change_shop_enabled(on: bool) -> void:
	if not _is_room_host or on == _shop_enabled:
		return
	_shop_enabled = on
	_refresh_gameplay_controls()
	GameState.request_set_shop_enabled(on, main._next_action_id())

func _select_button_look(btn: Button, selected: bool) -> void:
	if selected:
		_apply_primary_style(btn)
	else:
		_apply_secondary_style(btn)

## 按当前设置刷新模式分段/特效下拉/商店开关/中央卡牌着色（数据来自本地乐观值）。
func _refresh_gameplay_controls() -> void:
	for m in _mode_buttons:
		var key: String = str(m[0])
		var btn: Button = m[1]
		var selected := key == _effect_mode
		_select_button_look(btn, selected)
		btn.button_pressed = selected
		btn.disabled = not _is_room_host
	if _effect_dropdown != null:
		_effect_dropdown.visible = _effect_mode == "fixed"
		_effect_dropdown.disabled = not _is_room_host
		var idx := 0
		for i in _effect_dropdown.item_count:
			if str(_effect_dropdown.get_item_metadata(i)) == _fixed_effect:
				idx = i
				break
		_effect_dropdown.select(idx)
	if _shop_on_btn != null and _shop_off_btn != null:
		_select_button_look(_shop_on_btn, _shop_enabled)
		_select_button_look(_shop_off_btn, not _shop_enabled)
		_shop_on_btn.button_pressed = _shop_enabled
		_shop_off_btn.button_pressed = not _shop_enabled
		_shop_on_btn.disabled = not _is_room_host
		_shop_off_btn.disabled = not _is_room_host
	_apply_center_card_tint()

## 中央三张卡背按模式着色：普通=原色 / 随机=淡绿 / 指定=淡金。
func _apply_center_card_tint() -> void:
	if _center_cards.is_empty():
		return
	var tint := Color(1, 1, 1)
	match _effect_mode:
		"random":
			tint = Color(0.72, 1.0, 0.86)
		"fixed":
			tint = Color(1.0, 0.92, 0.66)
	for card in _center_cards:
		card.self_modulate = tint

func _open_disband_dialog() -> void:
	if _disband_dialog != null:
		_disband_dialog.visible = true

## 主题切换后重建大厅（保留昵称/房间码/地址输入与当前房间快照）。
func apply_theme() -> void:
	if main.latest_state not in [null, {}] and int((main.latest_state as Dictionary).get("phase", GameState.Phase.LOBBY)) != GameState.Phase.LOBBY:
		return
	_rebuild_all()

func _rebuild_all() -> void:
	var name_text: String = main.name_input.text if main.name_input != null else "玩家"
	var code_text: String = main.room_code_input.text if main.room_code_input != null else ""
	var addr_text: String = main.address_input.text if main.address_input != null else "127.0.0.1"
	var port_text: String = main.port_input.text if main.port_input != null else str(KongNetwork.DEFAULT_PORT)
	if _menu_box != null and is_instance_valid(_menu_box):
		main.lobby_panel.remove_child(_menu_box)
		_menu_box.queue_free()
	if _room_box != null and is_instance_valid(_room_box):
		main.lobby_panel.remove_child(_room_box)
		_room_box.queue_free()
	if _nickname_dialog != null and is_instance_valid(_nickname_dialog):
		main.remove_child(_nickname_dialog)
		_nickname_dialog.queue_free()
	if _disband_dialog != null and is_instance_valid(_disband_dialog):
		main.remove_child(_disband_dialog)
		_disband_dialog.queue_free()
	_menu_box = null
	_room_box = null
	_slots_box = null
	_nickname_dialog = null
	_disband_dialog = null
	_apply_frame_style()
	_build_menu()
	_build_room()
	main.name_input.text = name_text
	main.room_code_input.text = code_text
	main.address_input.text = addr_text
	main.port_input.text = port_text
	refresh_player_info()
	if not main.latest_lobby.is_empty():
		update_lobby(main.latest_lobby)
	else:
		_show_menu()

func _set_lobby_bg_visible(on: bool) -> void:
	if main.lobby_bg != null:
		main.lobby_bg.visible = on

func _show_menu() -> void:
	_set_lobby_bg_visible(true)
	if _menu_box != null:
		_menu_box.visible = true
	if _room_box != null:
		_room_box.visible = false
	_update_panel_size()

func _show_room() -> void:
	_set_lobby_bg_visible(true)
	if _menu_box != null:
		_menu_box.visible = false
	if layout_mode_override == "" and str(Settings.get_setting("display", "lobby_layout", "auto")) == "auto" \
			and _use_wide_layout() != _wide_active:
		_wide_active = _use_wide_layout()
		if _room_box != null and is_instance_valid(_room_box):
			main.lobby_panel.remove_child(_room_box)
			_room_box.queue_free()
		_room_box = null
		_slots_box = null
		_build_room()
	if _room_box != null:
		_room_box.visible = true
	_update_panel_size()

func _update_seat_columns() -> void:
	if _slots_box == null or _panel == null or not (_slots_box is GridContainer):
		return
	var width: float = maxf(_panel.size.x, _panel.custom_minimum_size.x)
	(_slots_box as GridContainer).columns = 2 if width >= 560.0 else 1

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
	refresh_player_info()
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
	if main.lobby_root != null:
		main.lobby_root.visible = true
	main.game_panel.visible = false

## 刷新房间界面（服务器逐 peer 下发的 lobby 快照）。
func update_lobby(lobby: Dictionary) -> void:
	main.latest_lobby = lobby
	main.lobby_panel.visible = true
	if main.lobby_root != null:
		main.lobby_root.visible = true
	main.game_panel.visible = false
	_set_lobby_bg_visible(true)
	_show_room()

	var your_id: int = int(lobby.get("your_id", -1))
	var is_host: bool = your_id == int(lobby.get("room_host", 0))
	var entries: Array = lobby.get("players", [])
	var maxp := int(lobby.get("max_players", KongRules.MAX_PLAYERS))
	_header_label.text = "KONG · LAN MVP" if _wide_active else "房间大厅"
	if _header_room_code != null:
		_header_room_code.text = "Room: %s" % _share_text()
	_player_count_label.text = "%d / %d" % [entries.size(), maxp]
	if _stage_title != null:
		_stage_title.text = "全员已就绪" if _all_ready(lobby) else "准备开始"
	_room_status_label.text = "等待玩家加入" if entries.size() < int(lobby.get("min_players", KongRules.MIN_PLAYERS)) \
		else ("全员已准备，等待房主开始" if _all_ready(lobby) else "等待玩家准备")

	_rebuild_slots(lobby, is_host, your_id)

	_share_field.text = _share_text()
	_share_hint.text = ("房间码用于加入；复制按钮会复制当前邀请值。" if not str(main.room_code).is_empty() \
		else "当前未拿到房间码，复制按钮会复制局域网直连地址。")

	var limit := int(lobby.get("match_limit", KongRules.DEFAULT_MATCH_LIMIT))
	_match_limit_value = clampi(limit, KongRules.MIN_MATCH_LIMIT, KongRules.MAX_MATCH_LIMIT)
	_match_value.text = str(_match_limit_value)
	_match_minus.disabled = not is_host or _match_limit_value <= KongRules.MIN_MATCH_LIMIT
	_match_plus.disabled = not is_host or _match_limit_value >= KongRules.MAX_MATCH_LIMIT
	# 玩法设置（系列赛级，快照下发）
	_is_room_host = is_host
	_effect_mode = str(lobby.get("effect_mode", "normal"))
	_fixed_effect = str(lobby.get("fixed_effect", ""))
	_shop_enabled = bool(lobby.get("shop_enabled", true))
	_refresh_gameplay_controls()

	var my_ready := false
	for e in entries:
		if int(e.get("id", -1)) == your_id:
			my_ready = bool(e.get("ready", false))
	_ready_button.visible = not is_host
	_ready_button.text = "取消准备" if my_ready else "准备"
	_ready_button.disabled = false

	_start_button.visible = is_host
	_start_button.disabled = not (entries.size() >= int(lobby.get("min_players", KongRules.MIN_PLAYERS)) and _all_ready(lobby))
	_invite_button.visible = true
	_disband_button.visible = is_host
	_leave_button.visible = not is_host

func _rebuild_slots(lobby: Dictionary, is_host: bool, your_id: int) -> void:
	for c in _slots_box.get_children():
		_slots_box.remove_child(c)
		c.queue_free()
	var maxp := int(lobby.get("max_players", KongRules.MAX_PLAYERS))
	var host := int(lobby.get("room_host", 0))
	var taken: Dictionary = {}
	for e in lobby.get("players", []):
		taken[int(e.get("id", -1))] = e
	for seat in range(maxp):
		var card := LobbySeatCard.new()
		card.name = "SeatCard%d" % seat
		var player: Dictionary = taken.get(seat, {})
		var can_kick := is_host and taken.has(seat) and seat != your_id
		if _wide_active:
			card.setup_row(seat, player, seat == host, seat == your_id, can_kick)
		else:
			card.setup(seat, player, seat == host, seat == your_id, can_kick)
		card.kick_requested.connect(func(s: int): GameState.request_kick(s))
		_slots_box.add_child(card)
	_update_seat_columns()

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
	main._show_toast("已复制邀请信息：%s" % text)

func _on_ready_pressed() -> void:
	var my_ready := false
	var your_id := int(main.latest_lobby.get("your_id", -1))
	for e in main.latest_lobby.get("players", []):
		if int(e.get("id", -1)) == your_id:
			my_ready = bool(e.get("ready", false))
	GameState.request_set_ready(not my_ready)

func _on_start_pressed() -> void:
	GameState.request_start_match(int(_match_limit_value))

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
