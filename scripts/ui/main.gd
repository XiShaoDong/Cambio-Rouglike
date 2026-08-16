extends Control

## Deliberately code-built MVP interface: it keeps the visual layer small while
## the game rules and networking remain independently testable.

class DashedBorder:
	extends Control
	var color := Color("ffffff")
	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var c: Color = UITheme.color("card_back_border")
		draw_dashed_line(rect.position, Vector2(rect.end.x, rect.position.y), c, 2.0, 5.0, true)
		draw_dashed_line(Vector2(rect.end.x, rect.position.y), rect.end, c, 2.0, 5.0, true)
		draw_dashed_line(rect.end, Vector2(rect.position.x, rect.end.y), c, 2.0, 5.0, true)
		draw_dashed_line(Vector2(rect.position.x, rect.end.y), rect.position, c, 2.0, 5.0, true)

var _layout_debug := false
var _theme_index := 0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			_layout_debug = not _layout_debug
			_apply_layout_debug()
		elif event.keycode == KEY_T:
			_theme_index = (_theme_index + 1) % UITheme.TOKENS.size()
			var names: Array = UITheme.TOKENS.keys()
			UITheme.switch_theme(str(names[_theme_index]))
			_rebuild_theme()

func _apply_layout_debug() -> void:
	var colors := [Color(1, 0, 0, 0.45), Color(0, 1, 0, 0.45), Color(0, 0, 1, 0.45), Color(1, 1, 0, 0.45), Color(1, 0, 1, 0.45)]
	var index := 0
	_tint_children(self, colors, index)

func _rebuild_theme() -> void:
	background.color = UITheme.color("bg_table")
	if not latest_state.is_empty():
		_render_game()
	else:
		_set_status("主题已切换：%s" % UITheme.current)

func _tint_children(node: Node, colors: Array, depth: int) -> void:
	if node is Control:
		var ctl: Control = node
		if _layout_debug:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(1, 1, 1, 0.04)
			style.border_color = colors[depth % colors.size()]
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			ctl.add_theme_stylebox_override("panel", style)
			ctl.add_theme_stylebox_override("normal", style)
			ctl.set_meta("debug_style", style)
		else:
			if ctl.has_meta("debug_style"):
				ctl.remove_theme_stylebox_override("panel")
				ctl.remove_theme_stylebox_override("normal")
				ctl.remove_meta("debug_style")
	for child in node.get_children():
		_tint_children(child, colors, depth + 1)

const PHASE_LOBBY := 0
const PHASE_INITIAL_PEEK := 1
const PHASE_TURN_DRAW := 2
const PHASE_TURN_DECISION := 3
const PHASE_Q_DECISION := 4
const PHASE_SLAP_WINDOW := 5
const PHASE_SLAP_EXCHANGE := 6
const PHASE_GAME_OVER := 7

var latest_lobby: Dictionary = {}
var latest_state: Dictionary = {}
var action_mode := ""
var selected_target := 0
var selected_own_slot := -1
var last_phase := -1

var status_label: Label
var lobby_panel: VBoxContainer
var game_panel: VBoxContainer
var name_input: LineEdit
var address_input: LineEdit
var port_input: LineEdit
var lobby_members: RichTextLabel
var game_header: Label
var ready_button: Button
var bell_button: Button
var round_label: Label
var deck_button: Button
var discard_button: Button
var top_player_box: VBoxContainer
var left_player_box: VBoxContainer
var right_player_box: VBoxContainer
var bottom_player_box: VBoxContainer
var center_hint: Label
var pending_card_box: VBoxContainer
var pending_card_button: Button
var pending_action_button: Button
var controls_box: HBoxContainer
var log_box: RichTextLabel
var overlay: Control
var pending_overlay: Control
var background: ColorRect
var is_dev_join := false
var _ready_clicked := false
var start_button: Button = null

func _ready() -> void:
	_build_interface()
	GameState.lobby_updated.connect(_on_lobby_updated)
	GameState.state_updated.connect(_on_state_updated)
	GameState.private_reveal_received.connect(_show_private_reveal)
	GameState.toast_received.connect(_show_toast)
	GameState.command_rejected.connect(_on_command_rejected)
	GameState.match_aborted.connect(_on_match_aborted)
	Network.connection_status_changed.connect(_set_status)
	Network.connection_failed.connect(_show_toast)
	_apply_dev_join()
	_set_status("输入昵称后创建或加入局域网房间。默认端口 7007。")

var _action_counter := 0

func _next_action_id() -> String:
	_action_counter += 1
	return "%d-%d-%d" % [multiplayer.get_unique_id(), Time.get_ticks_usec(), _action_counter]

func _on_command_rejected(_code: int, message: String) -> void:
	_show_toast("被拒绝：%s" % message)

func _on_match_aborted(_code: int, message: String) -> void:
	latest_state.clear()
	last_phase = -1
	action_mode = ""
	selected_target = 0
	selected_own_slot = -1
	lobby_panel.visible = true
	game_panel.visible = false
	_set_status("对局中止：%s" % message)

func _build_interface() -> void:
	background = ColorRect.new()
	background.color = UITheme.color("bg_table")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 50
	add_child(overlay)
	var margin := Control.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.offset_left = 36
	margin.offset_right = -36
	margin.offset_top = 28
	margin.offset_bottom = -28
	add_child(margin)
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)
	var title := Label.new()
	title.text = "KONG  ·  LAN MVP"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UITheme.color("accent"))
	page.add_child(title)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	page.add_child(status_label)
	lobby_panel = VBoxContainer.new()
	lobby_panel.add_theme_constant_override("separation", 12)
	page.add_child(lobby_panel)
	_build_lobby()
	game_panel = VBoxContainer.new()
	game_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_panel.add_theme_constant_override("separation", 12)
	game_panel.visible = false
	page.add_child(game_panel)
	_build_game()

func _build_lobby() -> void:
	var intro := Label.new()
	intro.text = "房主的电脑负责裁定全部规则；同一 Wi‑Fi 下的朋友输入房主的局域网 IP 即可加入。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_panel.add_child(intro)
	var inputs := HBoxContainer.new()
	inputs.add_theme_constant_override("separation", 10)
	lobby_panel.add_child(inputs)
	name_input = LineEdit.new()
	name_input.placeholder_text = "昵称"
	name_input.text = "玩家"
	name_input.custom_minimum_size = Vector2(190, 42)
	inputs.add_child(name_input)
	address_input = LineEdit.new()
	address_input.placeholder_text = "房主 IP（加入时填写）"
	address_input.text = "127.0.0.1"
	address_input.custom_minimum_size = Vector2(240, 42)
	inputs.add_child(address_input)
	port_input = LineEdit.new()
	port_input.placeholder_text = "端口"
	port_input.text = str(KongNetwork.DEFAULT_PORT)
	port_input.custom_minimum_size = Vector2(105, 42)
	port_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	inputs.add_child(port_input)
	var host := _button("创建房间")
	host.pressed.connect(_host_game)
	host.disabled = is_dev_join
	inputs.add_child(host)
	var join := _button("加入房间")
	join.pressed.connect(_join_game)
	join.disabled = is_dev_join
	inputs.add_child(join)
	var dev := _button("开发者：本机双开测试")
	dev.pressed.connect(_dev_launch_second)
	dev.add_theme_color_override("font_color", UITheme.color("success"))
	dev.disabled = is_dev_join
	inputs.add_child(dev)
	lobby_members = RichTextLabel.new()
	lobby_members.bbcode_enabled = true
	lobby_members.fit_content = true
	lobby_members.custom_minimum_size = Vector2(0, 140)
	lobby_members.add_theme_font_size_override("normal_font_size", 18)
	lobby_panel.add_child(lobby_members)

func _build_game() -> void:
	game_panel.add_theme_constant_override("separation", 14)
	# ── 顶部单元（居中）：标题 + 对局记录 log + 提示 + Ready ──
	var top_unit := VBoxContainer.new()
	top_unit.alignment = BoxContainer.ALIGNMENT_CENTER
	top_unit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top_unit.add_theme_constant_override("separation", 6)
	game_panel.add_child(top_unit)
	var top_bar := HBoxContainer.new()
	top_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	top_bar.add_theme_constant_override("separation", 24)
	top_unit.add_child(top_bar)
	game_header = Label.new()
	game_header.add_theme_font_size_override("font_size", 18)
	game_header.add_theme_color_override("font_color", UITheme.color("text_primary"))
	game_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_bar.add_child(game_header)
	ready_button = _button("Ready（0/0）")
	ready_button.custom_minimum_size = Vector2(180, 40)
	ready_button.add_theme_font_size_override("font_size", 16)
	ready_button.add_theme_color_override("font_color", UITheme.color("success"))
	ready_button.pressed.connect(func():
		_ready_clicked = true
		GameState.request_initial_ready())
	ready_button.visible = false
	top_bar.add_child(ready_button)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.custom_minimum_size = Vector2(360, 54)
	log_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	log_box.add_theme_font_size_override("normal_font_size", 12)
	log_box.add_theme_color_override("default_color", UITheme.color("text_secondary"))
	top_unit.add_child(log_box)
	center_hint = Label.new()
	center_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_hint.add_theme_color_override("font_color", UITheme.color("accent"))
	top_unit.add_child(center_hint)
	# ── 对家（上方，居中）──
	top_player_box = VBoxContainer.new()
	top_player_box.alignment = BoxContainer.ALIGNMENT_CENTER
	top_player_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top_player_box.add_theme_constant_override("separation", 4)
	game_panel.add_child(top_player_box)
	# ── 中部行（居中）：左对手 | 中央牌堆单元 | 右对手 ──
	var opponents_row := HBoxContainer.new()
	opponents_row.alignment = BoxContainer.ALIGNMENT_CENTER
	opponents_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	opponents_row.add_theme_constant_override("separation", 36)
	game_panel.add_child(opponents_row)
	left_player_box = VBoxContainer.new()
	left_player_box.alignment = BoxContainer.ALIGNMENT_CENTER
	left_player_box.add_theme_constant_override("separation", 4)
	opponents_row.add_child(left_player_box)
	# 中央牌堆单元（组件 2）：抽牌堆 | 弃牌堆 + 提示，正中央
	var center_unit := VBoxContainer.new()
	center_unit.alignment = BoxContainer.ALIGNMENT_CENTER
	center_unit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center_unit.add_theme_constant_override("separation", 12)
	opponents_row.add_child(center_unit)
	var pile_row := HBoxContainer.new()
	pile_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pile_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pile_row.add_theme_constant_override("separation", 28)
	center_unit.add_child(pile_row)
	deck_button = _make_card_button({}, Vector2(68, 107), false)
	deck_button.pressed.connect(_on_deck_pressed)
	pile_row.add_child(deck_button)
	discard_button = _make_card_button({}, Vector2(68, 107), false)
	discard_button.pressed.connect(_on_discard_pressed)
	pile_row.add_child(discard_button)
	var pile_hint := Label.new()
	pile_hint.text = "抽牌堆          弃牌堆"
	pile_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pile_hint.add_theme_font_size_override("font_size", 12)
	pile_hint.add_theme_color_override("font_color", UITheme.color("text_muted"))
	center_unit.add_child(pile_hint)
	right_player_box = VBoxContainer.new()
	right_player_box.alignment = BoxContainer.ALIGNMENT_CENTER
	right_player_box.add_theme_constant_override("separation", 4)
	opponents_row.add_child(right_player_box)
	# 抽到的牌（大牌）：覆盖在牌堆单元上（两堆正中间）
	pending_overlay = Control.new()
	pending_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pending_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	pending_overlay.z_index = 10
	center_unit.add_child(pending_overlay)
	pending_card_box = VBoxContainer.new()
	pending_card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pending_card_box.add_theme_constant_override("separation", 10)
	pending_card_box.anchor_left = 0.5
	pending_card_box.anchor_right = 0.5
	pending_card_box.anchor_top = 0.5
	pending_card_box.anchor_bottom = 0.5
	pending_card_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pending_card_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	pending_card_box.visible = false
	pending_overlay.add_child(pending_card_box)
	pending_card_button = _make_card_button({}, Vector2(68, 107), false)
	pending_card_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pending_card_box.add_child(pending_card_button)
	pending_action_button = _button("Use Power")
	pending_action_button.custom_minimum_size = Vector2(0, 30)
	pending_action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pending_action_button.add_theme_font_size_override("font_size", 13)
	pending_action_button.pressed.connect(_on_pending_action)
	pending_card_box.add_child(pending_action_button)
	# ── 当前玩家（组件 3）：牌堆正下方，间距加大 ──
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 80)
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_panel.add_child(spacer)
	bottom_player_box = VBoxContainer.new()
	bottom_player_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_player_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom_player_box.add_theme_constant_override("separation", 4)
	game_panel.add_child(bottom_player_box)
	# ── 右下操作区 ──
	var controls_row := HBoxContainer.new()
	controls_row.alignment = BoxContainer.ALIGNMENT_END
	controls_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_row.add_theme_constant_override("separation", 14)
	game_panel.add_child(controls_row)
	bell_button = _button("🔔 KONGBAYA")
	bell_button.custom_minimum_size = Vector2(190, 46)
	bell_button.add_theme_font_size_override("font_size", 18)
	bell_button.add_theme_color_override("font_color", UITheme.color("danger"))
	bell_button.pressed.connect(_request_kongbaya)
	controls_row.add_child(bell_button)
	round_label = Label.new()
	round_label.text = "第 1 局"
	round_label.add_theme_font_size_override("font_size", 14)
	round_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls_row.add_child(round_label)
	controls_box = HBoxContainer.new()
	controls_box.add_theme_constant_override("separation", 8)
	controls_row.add_child(controls_box)

func _on_deck_pressed() -> void:
	GameState.request_take("draw", _next_action_id())
	_animate_draw()

func _on_discard_pressed() -> void:
	GameState.request_take("discard", _next_action_id())

func _animate_draw() -> void:
	pending_card_box.modulate.a = 0.0
	pending_card_box.scale = Vector2(0.5, 0.5)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(pending_card_box, "modulate:a", 1.0, 0.3)
	tween.tween_property(pending_card_box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func():
		pending_card_box.modulate.a = 1.0
		pending_card_box.scale = Vector2.ONE)

func _host_game() -> void:
	var port := _entered_port()
	Network.host_game({"name": _entered_name()}, port)

func _join_game() -> void:
	var address := address_input.text.strip_edges()
	if address.is_empty():
		_show_toast("请输入房主的局域网 IP。")
		return
	Network.join_game(address, {"name": _entered_name()}, _entered_port())

func _dev_launch_second() -> void:
	var executable := OS.get_executable_path()
	var project_dir := ProjectSettings.globalize_path("res://")
	var port := _entered_port()
	var args := PackedStringArray(["--path", project_dir, "--", "--dev-join", "127.0.0.1:%d" % port])
	var pid := OS.create_process(executable, args)
	if pid == 0:
		_show_toast("启动第二个实例失败，请直接手动运行：%s --path %s" % [executable, project_dir])
	else:
		_set_status("已启动本机第二实例（PID %d），它会在 %d 秒内自动加入 127.0.0.1:%d。" % [pid, 2, port])

func _apply_dev_join() -> void:
	var args := OS.get_cmdline_user_args()
	var target := ""
	for index in range(args.size()):
		if args[index] == "--dev-join" and index + 1 < args.size():
			target = args[index + 1]
			break
	if target.is_empty():
		return
	is_dev_join = true
	var parts := target.rsplit(":", true, 1)
	var address := parts[0] if parts.size() == 2 else "127.0.0.1"
	var port := int(parts[1]) if parts.size() == 2 else KongNetwork.DEFAULT_PORT
	name_input.text = "开发者2"
	address_input.text = address
	port_input.text = str(port)
	Network.join_game(address, {"name": "开发者2"}, port)
	_set_status("开发者模式：正在自动加入 %s:%d…" % [address, port])

func _request_kongbaya() -> void:
	GameState.request_kongbaya(_next_action_id())

func _entered_name() -> String:
	var chosen := name_input.text.strip_edges().left(16)
	return chosen if not chosen.is_empty() else "玩家"

func _entered_port() -> int:
	var parsed := int(port_input.text)
	return parsed if parsed > 0 and parsed < 65536 else KongNetwork.DEFAULT_PORT

func _on_lobby_updated(lobby: Dictionary) -> void:
	latest_lobby = lobby
	lobby_panel.visible = true
	game_panel.visible = false
	var lines := ["[color=#f6d77a]房间玩家（%d/%d）[/color]" % [lobby.players.size(), lobby.max_players]]
	for entry in lobby.players:
		var host_mark := "  [房主]" if int(entry.id) == int(lobby.host_id) else ""
		lines.append("• %s%s" % [entry.name, host_mark])
	if Network.is_host:
		lines.append("\n[房主] 至少 2 人后可开始。")
		if start_button == null:
			start_button = _button("开始对局")
			start_button.name = "StartMatch"
			start_button.pressed.connect(GameState.request_start_match)
			lobby_panel.add_child(start_button)
		start_button.disabled = lobby.players.size() < int(lobby.min_players)
	lobby_members.text = "\n".join(lines)

func _on_state_updated(state: Dictionary) -> void:
	latest_state = state
	if int(state.phase) != last_phase:
		action_mode = ""
		selected_target = 0
		selected_own_slot = -1
		last_phase = int(state.phase)
		if int(state.phase) == PHASE_TURN_DECISION and int(state.viewer_id) == int(state.current_player):
			action_mode = "replace"
	lobby_panel.visible = false
	game_panel.visible = true
	_render_game()

func _render_game() -> void:
	if latest_state.is_empty(): return
	var phase := int(latest_state.phase)
	var viewer := int(latest_state.viewer_id)
	var is_current := viewer == int(latest_state.current_player)
	game_header.text = "%s  ·  %s" % [latest_state.phase_name, "轮到你" if is_current else "轮到 %s" % latest_state.current_name]
	var total_players: int = latest_state.players.size()
	if phase == PHASE_INITIAL_PEEK:
		var ready_count: int = int(latest_state.get("ready_count", 0))
		ready_button.visible = true
		ready_button.disabled = ready_count >= total_players or _ready_clicked
		if _ready_clicked:
			ready_button.text = "已准备（%d/%d）" % [ready_count, total_players]
		else:
			ready_button.text = "Ready（%d/%d）" % [ready_count, total_players]
	else:
		ready_button.visible = false
		_ready_clicked = false
	center_hint.text = _hint_for(phase, is_current)
	round_label.text = "第 %d 局" % int(latest_state.get("match_number", 1))
	bell_button.disabled = not (phase == PHASE_TURN_DRAW and is_current)
	bell_button.tooltip_text = "轮到你抽牌时，按下铃铛宣布 KONGBAYA！其他人各有一次最后行动。"
	_update_pending_card(phase, is_current)
	_clear(controls_box)
	var can_take := phase == PHASE_TURN_DRAW and is_current
	deck_button.disabled = not can_take
	_highlight(deck_button, can_take)
	var discard := latest_state.discard as Dictionary
	var discard_available := can_take and not discard.is_empty()
	_update_discard_button(discard, discard_available)
	_render_controls(phase, is_current)
	_render_players(viewer)
	_render_log()

func _update_discard_button(discard: Dictionary, available: bool) -> void:
	discard_button.disabled = not available
	# 清空旧内容（保留虚线占位）
	for child in discard_button.get_children():
		if child.name != "DiscardDashed":
			child.queue_free()
	discard_button.set_meta("base_style", null)
	if discard.is_empty():
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.set_corner_radius_all(8)
		discard_button.add_theme_stylebox_override("normal", style)
		discard_button.add_theme_stylebox_override("hover", style)
		discard_button.add_theme_stylebox_override("pressed", style)
		discard_button.add_theme_stylebox_override("disabled", style)
		discard_button.set_meta("base_style", style)
		discard_button.text = ""
		if not discard_button.has_node("DiscardDashed"):
			var dashed := DashedBorder.new()
			dashed.name = "DiscardDashed"
			dashed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			dashed.mouse_filter = Control.MOUSE_FILTER_IGNORE
			discard_button.add_child(dashed)
		discard_button.get_node("DiscardDashed").visible = true
	else:
		if discard_button.has_node("DiscardDashed"):
			discard_button.get_node("DiscardDashed").visible = false
		discard_button.text = ""
		var face := PanelContainer.new()
		var face_style := StyleBoxFlat.new()
		face_style.bg_color = UITheme.color("card_face_bg")
		face_style.border_color = UITheme.color("card_border")
		face_style.set_border_width_all(1)
		face_style.set_corner_radius_all(8)
		face.add_theme_stylebox_override("panel", face_style)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rank_label := Label.new()
		rank_label.text = str(discard.get("rank", "?"))
		rank_label.add_theme_font_size_override("font_size", 15)
		rank_label.add_theme_color_override("font_color", UITheme.color("card_rank_red") if str(discard.get("suit", "")) in ["♥", "♦"] else UITheme.color("card_rank_black"))
		rank_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		rank_label.offset_left = 5
		rank_label.offset_top = 1
		rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(rank_label)
		var suit_label := Label.new()
		suit_label.text = str(discard.get("suit", ""))
		suit_label.add_theme_font_size_override("font_size", 22)
		suit_label.add_theme_color_override("font_color", UITheme.color("card_rank_red") if str(discard.get("suit", "")) in ["♥", "♦"] else UITheme.color("card_rank_black"))
		suit_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		suit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(suit_label)
		discard_button.add_child(face)
	_highlight(discard_button, available)

func _update_pending_card(phase: int, is_current: bool) -> void:
	var should_show := phase == PHASE_TURN_DECISION and is_current and latest_state.has("pending")
	pending_card_box.visible = should_show
	if not should_show:
		return
	var pending: Dictionary = latest_state.pending
	pending_card_button.queue_free()
	pending_card_button = _make_card_button(pending, Vector2(68, 107), false)
	pending_card_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pending_card_box.add_child(pending_card_button)
	pending_card_button.move_to_front()
	var from_discard := str(pending.get("source", "draw")) == "discard"
	if from_discard:
		pending_action_button.visible = false
		return
	pending_action_button.visible = true
	if KongRules.has_ability(str(pending.get("rank", ""))):
		pending_action_button.text = "Use Power"
		pending_action_button.add_theme_color_override("font_color", UITheme.color("accent"))
	else:
		pending_action_button.text = "弃牌"
		pending_action_button.add_theme_color_override("font_color", UITheme.color("text_secondary"))

func _on_pending_action() -> void:
	var pending: Dictionary = latest_state.get("pending", {})
	if KongRules.has_ability(str(pending.get("rank", ""))):
		_begin_ability()
	else:
		GameState.request_discard_draw(_next_action_id())

func _render_controls(phase: int, is_current: bool) -> void:
	if phase == PHASE_Q_DECISION and is_current:
		var keep := _button("Q：不交换")
		keep.pressed.connect(func(): GameState.request_q_decision(false, -1, _next_action_id()))
		controls_box.add_child(keep)
		var exchange := _button("Q：交换（再点自己一张牌）")
		exchange.pressed.connect(func(): action_mode = "q_exchange"; _render_game())
		controls_box.add_child(exchange)
	elif phase == PHASE_GAME_OVER:
		var result: Dictionary = latest_state.result
		var summary := Label.new()
		if result.has("reason"):
			summary.text = str(result.reason)
		else:
			var winners: Array = result.get("winners", [])
			var winner_names: Array[String] = []
			for player in latest_state.players:
				if int(player.id) in winners: winner_names.append(str(player.name))
			summary.text = "获胜：%s" % "、".join(winner_names)
		summary.add_theme_font_size_override("font_size", 20)
		summary.add_theme_color_override("font_color", UITheme.color("success"))
		controls_box.add_child(summary)

func _render_players(viewer: int) -> void:
	_clear(top_player_box)
	_clear(left_player_box)
	_clear(right_player_box)
	_clear(bottom_player_box)
	var players: Array = latest_state.players
	var others: Array = []
	var me: Dictionary = {}
	for player in players:
		if int(player.id) == viewer:
			me = player
		else:
			others.append(player)
	# 位置分配：左右优先，最后才是上方（参考图）
	var opponent_slots: Array = []
	for player in others:
		opponent_slots.append(player)
	if opponent_slots.size() >= 1:
		_render_player_section(left_player_box, opponent_slots[0], viewer, false)
	if opponent_slots.size() >= 2:
		_render_player_section(right_player_box, opponent_slots[1], viewer, false)
	if opponent_slots.size() >= 3:
		_render_player_section(top_player_box, opponent_slots[2], viewer, true)
	if not me.is_empty():
		_render_player_section(bottom_player_box, me, viewer, false)

func _render_player_section(box: VBoxContainer, player: Dictionary, viewer: int, is_top: bool) -> void:
	var is_me := int(player.id) == viewer
	var card_size := Vector2(57, 89) if is_me else Vector2(34, 53)
	var font_size := 16 if is_me else 12
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	box.add_child(section)
	var hand := GridContainer.new()
	hand.columns = 2
	hand.add_theme_constant_override("h_separation", 6)
	hand.add_theme_constant_override("v_separation", 6)
	hand.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	section.add_child(hand)
	for slot_index in player.slots.size():
		var slot: Dictionary = player.slots[slot_index]
		var card_button := _make_card_button(slot.get("card", {}), card_size)
		card_button.tooltip_text = "记忆牌面后，点击以执行当前操作"
		card_button.pressed.connect(_on_card_pressed.bind(int(player.id), slot_index))
		_highlight(card_button, _card_actionable(int(player.id), slot_index))
		hand.add_child(card_button)
	var name_panel := PanelContainer.new()
	var name_style := StyleBoxFlat.new()
	name_style.bg_color = UITheme.color("player_self_bg") if is_me else UITheme.color("player_other_bg")
	name_style.set_corner_radius_all(6)
	name_style.set_content_margin_all(6)
	name_panel.add_theme_stylebox_override("panel", name_style)
	name_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var name_label := Label.new()
	var suffix := "（你）" if is_me else ""
	var ready_mark := ""
	if int(latest_state.phase) == PHASE_INITIAL_PEEK:
		ready_mark = "  [✓已准备]" if bool(player.get("ready", false)) else "  [等待]"
	name_label.text = "%s%s%s" % [player.name, suffix, ready_mark]
	name_label.add_theme_font_size_override("font_size", font_size)
	name_label.add_theme_color_override("font_color", UITheme.color("player_self_text") if is_me else UITheme.color("player_other_text"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if is_top:
		name_label.text = "▲ " + name_label.text
	if is_me:
		name_label.text = "▼ " + name_label.text
	name_panel.add_child(name_label)
	section.add_child(name_panel)

func _card_actionable(player_id: int, _slot: int) -> bool:
	var phase := int(latest_state.phase)
	var viewer := int(latest_state.viewer_id)
	var is_current := viewer == int(latest_state.current_player)
	if phase == PHASE_SLAP_WINDOW:
		return true
	if phase == PHASE_SLAP_EXCHANGE:
		return player_id == viewer and int(latest_state.slap_exchange_actor) == viewer
	if not is_current:
		return false
	match action_mode:
		"replace", "peek_own", "q_exchange":
			return player_id == viewer
		"peek_other", "queen_target":
			return player_id != viewer
		"jack_target":
			return player_id != viewer
		"jack_own":
			return player_id == viewer
		"jack_their":
			return player_id == selected_target
	return false

func _highlight(button: Button, on: bool) -> void:
	if button.has_method("highlight") and button.get_script() != null:
		button.call("highlight", on)
		return
	var base: StyleBoxFlat = button.get_meta("base_style", null) as StyleBoxFlat
	if on:
		var style := (base.duplicate() if base else StyleBoxFlat.new()) as StyleBoxFlat
		style.shadow_color = UITheme.color("highlight_glow")
		style.shadow_size = 10
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
	else:
		button.add_theme_stylebox_override("normal", base)
		button.add_theme_stylebox_override("hover", base)
		button.add_theme_stylebox_override("pressed", base)

var _card_scene_cache: PackedScene = null

func _card_scene() -> PackedScene:
	if _card_scene_cache == null:
		_card_scene_cache = load("res://scenes/ui/card.tscn")
	return _card_scene_cache

func _make_card_button(card: Dictionary, card_size: Vector2, interactive := true) -> Button:
	var btn: Button = _card_scene().instantiate()
	btn.custom_minimum_size = card_size
	btn.size = card_size
	btn.pivot_offset = card_size / 2.0
	if btn.has_method("setup"):
		btn.call("setup", card, not card.is_empty(), -1, card_size)
	btn.set("show_shadow", true)
	btn.set("interactive", interactive)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn

func _render_log() -> void:
	var accent_html := UITheme.color("accent").to_html(false)
	var lines := ["[color=#%s]对局记录[/color]" % accent_html]
	for entry in latest_state.event_log:
		lines.append("• %s" % str(entry))
	if int(latest_state.phase) == PHASE_GAME_OVER:
		var ranking: Array = (latest_state.result as Dictionary).get("ranking", [])
		if not ranking.is_empty():
			lines.append("\n[color=#f6d77a]排名[/color]")
			for index in ranking.size():
				var entry: Dictionary = ranking[index]
				lines.append("%d. %s：%d 分，%d 张" % [index + 1, entry.name, int(entry.score), int(entry.count)])
	log_box.text = "\n".join(lines)

func _begin_ability() -> void:
	var pending: Dictionary = latest_state.get("pending", {})
	match str(pending.get("rank", "")):
		"7", "8": action_mode = "peek_own"
		"9", "10": action_mode = "peek_other"
		"J": action_mode = "jack_target"
		"Q": action_mode = "queen_target"
	_render_game()

func _on_card_pressed(player_id: int, slot: int) -> void:
	if latest_state.is_empty(): return
	var phase := int(latest_state.phase)
	var viewer := int(latest_state.viewer_id)
	if phase == PHASE_SLAP_WINDOW:
		GameState.request_slap(player_id, slot, _next_action_id())
		return
	if phase == PHASE_SLAP_EXCHANGE and player_id == viewer and int(latest_state.slap_exchange_actor) == viewer:
		GameState.request_slap_exchange(slot, _next_action_id())
		return
	if int(latest_state.current_player) != viewer: return
	match action_mode:
		"replace":
			if player_id == viewer: GameState.request_replace(slot, _next_action_id())
		"peek_own":
			if player_id == viewer: GameState.request_use_ability({"slot": slot}, _next_action_id())
		"peek_other":
			if player_id != viewer: GameState.request_use_ability({"target": player_id, "target_slot": slot}, _next_action_id())
		"queen_target":
			if player_id != viewer: GameState.request_use_ability({"target": player_id, "target_slot": slot}, _next_action_id())
		"q_exchange":
			if player_id == viewer: GameState.request_q_decision(true, slot, _next_action_id())
		"jack_target":
			if player_id != viewer:
				selected_target = player_id
				action_mode = "jack_own"
				_render_game()
		"jack_own":
			if player_id == viewer:
				selected_own_slot = slot
				action_mode = "jack_their"
				_render_game()
		"jack_their":
			if player_id == selected_target:
				GameState.request_use_ability({"target": selected_target, "own_slot": selected_own_slot, "target_slot": slot}, _next_action_id())

func _hint_for(phase: int, is_current: bool) -> String:
	if phase == PHASE_INITIAL_PEEK: return "记住你下方两张牌，然后在顶部点击 Ready 等待其他玩家。"
	if phase == PHASE_SLAP_WINDOW: return "贴牌窗口：如果你记得任意一张同点数牌，立刻点击它。贴错会罚抽；每人本次只能尝试一次。"
	if phase == PHASE_SLAP_EXCHANGE:
		return "贴中他人：成功者请选择自己的一张牌交给对方。"
	if phase == PHASE_TURN_DRAW and is_current: return "点击高亮的抽牌堆或弃牌顶取牌；拿弃牌顶只能用于替换。"
	if phase == PHASE_TURN_DECISION and is_current:
		return _mode_instruction("处理抽到的牌：点击高亮的自己手牌替换，或使用大牌下方的操作按钮。")
	if phase == PHASE_Q_DECISION and is_current: return _mode_instruction("Q 已让你看过目标牌：选择不换，或点击自己一张牌来交换。")
	if phase == PHASE_GAME_OVER: return "按总分、牌数、最高单牌依次判定。"
	return "等待其他玩家行动；任何弃牌后都可能出现贴牌抢答。"

func _mode_instruction(fallback: String) -> String:
	match action_mode:
		"replace": return "请选择自己要被替换的手牌。"
		"peek_own": return "7 / 8：请选择自己要查看的手牌。"
		"peek_other": return "9 / 10：请选择其他玩家的一张牌。"
		"queen_target": return "Q：请选择其他玩家的一张牌查看。"
		"q_exchange": return "Q：请选择自己交出去的牌。"
		"jack_target": return "J：先点击任意一张对方的牌以选择交换对象。"
		"jack_own": return "J：请选择自己要盲换出去的牌。"
		"jack_their": return "J：请选择对方要盲换的牌。"
	return fallback

func _show_private_reveal(title: String, revealed_cards: Array) -> void:
	var labels: Array[String] = []
	for card in revealed_cards:
		labels.append("%s（%d 分）" % [str(card.label), int(card.value)])
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = "\n".join(labels) + "\n\n请记住牌面；关闭后它会再次盖住。"
	dialog.get_ok_button().text = "记住了"
	dialog.confirmed.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(370, 210))
	if is_dev_join:
		dialog.confirmed.emit()
		dialog.queue_free()

func _show_toast(message: String) -> void:
	_set_status(message)

func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.add_theme_font_size_override("font_size", 16)
	return button

func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
