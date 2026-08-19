extends Control

## Deliberately code-built MVP interface: it keeps the visual layer small while
## the game rules and networking remain independently testable.

var dev: DevTools

func _unhandled_input(event: InputEvent) -> void:
	dev.handle_input(event)


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
var pending_card_box: Control
var pending_card_button: Button
var pending_action_button: Button
var controls_box: HBoxContainer
var log_box: RichTextLabel
var overlay: Control
var pending_overlay: Control
var background: ColorRect
var is_dev_join := false
var start_button: Button = null
var _cards := CardFactory.new()
var interaction: GameInteraction
var lobby: LobbyView
var game_view: GameView
var reveal: RevealController
var animator: CardAnimator
var _card_slots: Dictionary = {}
var _pending_flips: Array = []
var _draw_flip_pending := false
var _pending_hidden_for_ability := false

func _ready() -> void:
	interaction = GameInteraction.new(self)
	lobby = LobbyView.new(self)
	game_view = GameView.new(self)
	reveal = RevealController.new(self)
	animator = CardAnimator.new(self)
	dev = DevTools.new(self)
	_build_interface()
	GameState.lobby_updated.connect(func(l: Dictionary): lobby.update_lobby(l))
	GameState.state_updated.connect(_on_state_updated)
	GameState.private_reveal_received.connect(_show_private_reveal)
	GameState.card_exchange_animated.connect(func(data: Dictionary): animator.handle_exchange(data))
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
	if interaction != null:
		interaction.action_mode = ""
		interaction.selected_target = 0
		interaction.selected_own_slot = -1
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
	game_view.build()

func _build_lobby() -> void:
	lobby.build()

func _on_deck_pressed() -> void:
	_draw_flip_pending = true
	GameState.request_take("draw", _next_action_id())

func _on_discard_pressed() -> void:
	GameState.request_take("discard", _next_action_id())

func _host_game() -> void:
	lobby.host_game()

func _join_game() -> void:
	lobby.join_game()

func _dev_launch_second() -> void:
	lobby.dev_launch_second()

func _apply_dev_join() -> void:
	lobby.apply_dev_join()

func _request_kongbaya() -> void:
	GameState.request_kongbaya(_next_action_id())

func _entered_name() -> String:
	var chosen := name_input.text.strip_edges().left(16)
	return chosen if not chosen.is_empty() else "玩家"

func _entered_port() -> int:
	var parsed := int(port_input.text)
	return parsed if parsed > 0 and parsed < 65536 else KongNetwork.DEFAULT_PORT

func _on_state_updated(state: Dictionary) -> void:
	latest_state = state
	if interaction != null:
		interaction.reset_for_phase(state)
	if int(state.phase) != last_phase:
		last_phase = int(state.phase)
	lobby_panel.visible = false
	game_panel.visible = true
	_render_game()

func _render_game() -> void:
	game_view.render(latest_state)

func _flush_pending_flips() -> void:
	if _pending_flips.is_empty():
		return
	var remaining: Array = []
	for entry in _pending_flips:
		var target_id := int(entry.target_id)
		var slot := int(entry.slot)
		if _card_slots.has(target_id) and _card_slots[target_id].has(slot) and is_instance_valid(_card_slots[target_id][slot]):
			reveal._flip_at(_card_slots[target_id][slot], entry.card)
		else:
			remaining.append(entry)
	_pending_flips = remaining

func _on_pending_action() -> void:
	var pending: Dictionary = latest_state.get("pending", {})
	var actor := int(latest_state.get("viewer_id", 0))
	var big_data: Dictionary = pending.duplicate()
	big_data.erase("source")
	# 隐藏棋盘大牌，播副本动画飞向弃牌堆（避免双卡）
	pending_card_box.visible = false
	animator._animate_discard_pending(big_data, actor)
	if KongRules.has_ability(str(pending.get("rank", ""))):
		_pending_hidden_for_ability = true
		_begin_ability()
	else:
		GameState.request_discard_draw(_next_action_id())

func _card_actionable(player_id: int, slot: int) -> bool:
	return interaction.card_actionable(player_id, slot)

func _highlight(button: Button, on: bool) -> void:
	_cards.highlight(button, on)

func _make_card_button(card: Dictionary, card_size: Vector2) -> Button:
	return _cards.make_card(card, card_size)

func _begin_ability() -> void:
	interaction.begin_ability()

func _on_card_pressed(player_id: int, slot: int) -> void:
	interaction.on_card_pressed(player_id, slot)

func _hint_for(phase: int, is_current: bool) -> String:
	if phase == PHASE_INITIAL_PEEK: return "记住下方两张牌，点 Ready 等待。"
	if phase == PHASE_SLAP_WINDOW: return "贴牌：记到同点数就点它，贴错罚抽。"
	if phase == PHASE_SLAP_EXCHANGE:
		return "贴中他人：选一张自己的牌交给对方。"
	if phase == PHASE_TURN_DRAW and is_current: return "抽牌堆或弃牌顶取牌；弃牌顶只能替换。"
	if phase == PHASE_TURN_DECISION and is_current:
		return _mode_instruction("处理抽到的牌：替换或使用大牌下按钮。")
	if phase == PHASE_Q_DECISION and is_current: return _mode_instruction("Q 已看过目标牌：不换或点自己一张交换。")
	if phase == PHASE_GAME_OVER: return "按总分、牌数、最高单牌判定。"
	return "等待其他玩家行动。"

func _mode_instruction(fallback: String) -> String:
	return interaction.mode_instruction(fallback)

func _show_private_reveal(title: String, revealed_cards: Array, target: Dictionary = {}) -> void:
	reveal.show_private_reveal(title, revealed_cards, target)

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
