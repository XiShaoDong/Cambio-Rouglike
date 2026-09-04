extends Control

## Deliberately code-built MVP interface: it keeps the visual layer small while
## the game rules and networking remain independently testable.

var dev: DevTools

func _notification(what: int) -> void:
	# 点击窗口关闭：拦截默认退出。若仍在房间/对局中 → 回初始大厅；已在初始大厅 → 真正退出
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _in_room():
			_leave_to_main_menu()
		else:
			get_tree().quit()

## 是否处于房间/对局连接中（ENet 连接建立，区别于初始大厅的 Offline peer）。
func _in_room() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer is ENetMultiplayerPeer

## 从房间/对局回到初始大厅界面（点窗口关闭时调用）：
## 房主解散房间通知全员；客户端退出房间断开连接。不真正退出程序。
func _leave_to_main_menu() -> void:
	if Network.is_host:
		GameState.request_close_room()
	else:
		lobby._leave_room()
	_set_status("已回到大厅。")

func _unhandled_input(event: InputEvent) -> void:
	# 比拼中按空格 = 停止（与 STOP 按钮等效）
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if _duel_panel != null and _duel_panel.has_method("stop"):
			_duel_panel.stop()
			get_viewport().set_input_as_handled()
			return
	# ESC 呼出/关闭设置菜单（大厅与对局通用）
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_toggle_settings()
		get_viewport().set_input_as_handled()
		return
	dev.handle_input(event)


const PHASE_LOBBY := 0
const PHASE_INITIAL_PEEK := 1
const PHASE_TURN_DRAW := 2
const PHASE_TURN_DECISION := 3
const PHASE_Q_DECISION := 4
const PHASE_SLAP_WINDOW := 5
const PHASE_SLAP_EXCHANGE := 6
const PHASE_GAME_OVER := 7
const PHASE_SLAP_DUEL := 8

const PEEK_GLOW_COLOR := Color("3ef0f7ff")  # 查看牌蓝色光晕
const PEEK_GLOW_DURATION := 1.5
const PEEK_GLOW_SIZE := 14
const SLAP_CORRECT_GLOW := Color("87d9a1")  # 贴对绿色炫光（同 UITheme success）
const SLAP_WRONG_GLOW := Color("ff7b7b")  # 贴错红色炫光（同 UITheme danger）
const SLAP_GLOW_SIZE := 14
const DuelBarScript := preload("res://scripts/ui/duel_bar.gd")
const SettingsMenuScript := preload("res://scripts/ui/settings_menu.gd")
const SettlementPageScript := preload("res://scenes/ui/settlement_page.tscn")

var latest_lobby: Dictionary = {}
var latest_state: Dictionary = {}
var last_phase := -1

var status_label: Label
var lobby_status_label: Label
var lobby_panel: VBoxContainer
var game_panel: VBoxContainer
var name_input: LineEdit
var address_input: LineEdit
var port_input: LineEdit
var lobby_members: RichTextLabel
var ready_button: Button
var bell_button: Button
var round_label: Label
var deck_button: Button
var discard_button: Button
var top_player_box: Control
var left_player_box: Control
var right_player_box: Control
var bottom_player_box: Control
var center_hint: Label
var _hint_actions: HBoxContainer
var pending_card_box: Control
var pending_card_button: Button
var pending_action_button: Button
var controls_box: HBoxContainer
var log_box: RichTextLabel
var overlay: Control
var pending_overlay: Control
var background: ColorRect
var board: Control
var is_dev_join := false
var start_button: Button = null
var close_room_button: Button = null
var leave_room_button: Button = null
var _cards := CardFactory.new()
var interaction: GameInteraction
var lobby: LobbyView
var game_view: GameView
var reveal: RevealController
var animator: CardAnimator
var _card_slots: Dictionary = {}
var _local_log: Array = []
var _pending_flips: Array = []
var _pending_slap_penalties: Array = []
var _draw_flip_pending := false
var _pending_hidden_for_ability := false
var _pending_card_id := ""
var _pending_is_current := false
var _anim_slots: Dictionary = {}
var _discard_anim_lock := false
var _discard_local_display: Dictionary = {}
var _peek_glow_slots: Dictionary = {}
var _slap_reveal_lock := false
var _duel_panel: Control = null
var settings_menu: Control = null
var _my_token := ""
var _rejoin_addr := ""
var _rejoin_port := KongNetwork.DEFAULT_PORT
var _was_in_match := false
var _reconnect_panel: Control = null
var _reconnect_expected := false
var settlement_page: Control = null
var _pending_winner_sfx := false

## 标记某个玩家槽位正在动画（渲染时该槽位显示虚线占位，不显示原卡）。
func mark_anim_slot(pid: int, slot: int) -> void:
	_anim_slots["%d_%d" % [pid, slot]] = true

func unmark_anim_slot(pid: int, slot: int) -> void:
	_anim_slots.erase("%d_%d" % [pid, slot])

func is_anim_slot(pid: int, slot: int) -> bool:
	return _anim_slots.has("%d_%d" % [pid, slot])

## 贴牌判定锁按计数管理：多人同时贴中会同时 hold 多张翻牌，全部释放后才解锁。
var _slap_reveal_count := 0
func _slap_reveal_begin() -> void:
	_slap_reveal_count += 1
	_slap_reveal_lock = true

func _slap_reveal_end() -> void:
	_slap_reveal_count = maxi(0, _slap_reveal_count - 1)
	_slap_reveal_lock = _slap_reveal_count > 0

## 贴牌结算时清除所有尚未播放的贴牌翻牌（本轮贴牌已全部裁决，不再需要补播）。
func purge_slap_pending_flips() -> void:
	if _pending_flips.is_empty():
		return
	var remaining: Array = []
	for entry in _pending_flips:
		if entry.has("correct"):
			continue
		remaining.append(entry)
	_pending_flips = remaining

func _ready() -> void:
	# 拦截窗口关闭：在房间/对局中时先回初始大厅而非直接退出
	get_tree().set_auto_accept_quit(false)
	# 启动即应用持久化主题，保证 UI 用正确 token 构建
	UITheme.switch_theme(str(Settings.get_setting("display", "theme", "dark")))
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
	GameState.peek_highlighted.connect(_on_peek_highlight)
	GameState.toast_received.connect(_show_toast)
	GameState.command_rejected.connect(_on_command_rejected)
	GameState.match_aborted.connect(_on_match_aborted)
	GameState.registered_token_received.connect(_on_registered_token)
	GameState.resume_hand_received.connect(_on_resume_hand)
	GameState.sfx_played.connect(_on_sfx)
	Network.connection_status_changed.connect(_set_status)
	Network.connection_failed.connect(_show_toast)
	Network.joined_server.connect(_on_joined_server_for_reconnect)
	_apply_dev_join()
	_restore_identity()
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
	_was_in_match = false
	if interaction != null:
		interaction.action_mode = ""
		interaction.selected_target = 0
		interaction.selected_own_slot = -1
		interaction.selected_their_slot = -1
	lobby.reset_lobby()
	_close_settlement()
	_set_status("对局中止：%s" % message)
	# 断线后回大厅：若持有 token，在初始界面显示"重连上次对局"入口
	if not Network.is_host and not _my_token.is_empty():
		_render_rejoin_entry()

## 收到服务器发放的身份 token：保存内存 + 持久化（user://identity.cfg）。
func _on_registered_token(token: String) -> void:
	_my_token = token
	_save_identity()

## 重连成功：隐藏重连面板并重渲染界面（本人手牌按快照显示为背面）。
func _on_resume_hand(_hand: Array, _pending: Dictionary) -> void:
	_hide_reconnect_panel()
	_remove_rejoin_entry()
	if not latest_state.is_empty():
		_render_game()

## 从 user://identity.cfg 恢复上次的 token 与地址。
func _restore_identity() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://identity.cfg") != OK:
		return
	_my_token = str(cfg.get_value("identity", "last_token", ""))
	_rejoin_addr = str(cfg.get_value("identity", "last_addr", ""))
	_rejoin_port = int(cfg.get_value("identity", "last_port", KongNetwork.DEFAULT_PORT))

func _save_identity() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://identity.cfg")
	cfg.set_value("identity", "last_token", _my_token)
	cfg.set_value("identity", "last_addr", _rejoin_addr)
	cfg.set_value("identity", "last_port", _rejoin_port)
	cfg.save("user://identity.cfg")

## 对局中与房主断开 → 若已保存 token，弹重连入口（非房主）。
func _on_server_disconnected_in_match() -> void:
	if not _was_in_match or Network.is_host or _my_token.is_empty():
		return
	_show_reconnect_panel("与房主连接断开，可重连继续对局")

## 构建重连面板（覆盖层）。
func _show_reconnect_panel(title: String) -> void:
	if _reconnect_panel != null and is_instance_valid(_reconnect_panel):
		return
	var panel := PanelContainer.new()
	panel.name = "ReconnectPanel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", UITheme.color("accent"))
	vb.add_child(lbl)
	var addr := Label.new()
	addr.text = "房主：%s:%d" % [_rejoin_addr, _rejoin_port]
	addr.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	vb.add_child(addr)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var btn_reconnect: Button = _button("重连")
	btn_reconnect.pressed.connect(_do_reconnect)
	row.add_child(btn_reconnect)
	var btn_later: Button = _button("稍后")
	btn_later.pressed.connect(_hide_reconnect_panel)
	row.add_child(btn_later)
	overlay.add_child(panel)
	_reconnect_panel = panel

func _hide_reconnect_panel() -> void:
	if _reconnect_panel != null and is_instance_valid(_reconnect_panel):
		_reconnect_panel.queue_free()
	_reconnect_panel = null

## 执行重连：记录当前输入框的地址/端口（供下次），重新加入并用 token 认领座位。
func _do_reconnect() -> void:
	if _my_token.is_empty():
		_hide_reconnect_panel()
		return
	_rejoin_addr = address_input.text.strip_edges() if not address_input.text.strip_edges().is_empty() else _rejoin_addr
	_rejoin_port = _entered_port()
	_save_identity()
	_reconnect_expected = true
	Network.join_game(_rejoin_addr, {"name": _entered_name()}, _rejoin_port)

func _on_joined_server_for_reconnect() -> void:
	# 连接成功：若本机持有 token（曾注册过，退出/断线后想回原对局），
	# 先尝试凭 token 认领原座位；token 无效时服务端会拒绝，不影响 LOBBY 阶段的正常注册。
	if not _my_token.is_empty():
		_reconnect_expected = false
		GameState.request_reconnect(_my_token, _entered_name())

## 在初始大厅显示"重连上次对局"入口（断线后持有 token 时）。
func _render_rejoin_entry() -> void:
	_remove_rejoin_entry()
	var btn: Button = _button("重连上次对局")
	btn.name = "RejoinEntry"
	btn.pressed.connect(_do_reconnect)
	lobby_panel.add_child(btn)

func _remove_rejoin_entry() -> void:
	for child in lobby_panel.get_children():
		if child.name == "RejoinEntry":
			child.queue_free()
			break

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
	if _slap_reveal_lock:
		return
	_draw_flip_pending = true
	GameState.request_take("draw", _next_action_id())

func _on_discard_pressed() -> void:
	if _slap_reveal_lock:
		return
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

## 服务器广播的音效事件：本地播放对应音效（bell=铃铛，winner=延迟到冠军出场再播）。
func _on_sfx(kind: String) -> void:
	match kind:
		"bell":
			AudioManager.play_bell()
		"winner":
			_pending_winner_sfx = true

func _entered_name() -> String:
	var chosen := name_input.text.strip_edges().left(16)
	return chosen if not chosen.is_empty() else "玩家"

func _entered_port() -> int:
	var parsed := int(port_input.text)
	return parsed if parsed > 0 and parsed < 65536 else KongNetwork.DEFAULT_PORT

func _on_state_updated(state: Dictionary) -> void:
	latest_state = state
	# 非 LOBBY 阶段视为对局中（用于断线后判断是否提示重连）
	_was_in_match = int(state.phase) != 0
	if interaction != null:
		interaction.reset_for_phase(state)
	if int(state.phase) != last_phase:
		last_phase = int(state.phase)
	lobby_panel.visible = false
	game_panel.visible = true
	_render_game()
	if int(state.phase) == PHASE_GAME_OVER:
		_open_settlement()
	else:
		_close_settlement()

func _render_game() -> void:
	game_view.render(latest_state)
	_render_duel(latest_state)
	# ExtraLayer 附加卡已同步定位，罚牌 fly 可直接取到正确锚点
	_flush_slap_penalties()

## 罚牌 fly：事件到达时目标槽位可能尚未渲染（追加的第 5+ 张），render 后再补飞。
func _flush_slap_penalties() -> void:
	if _pending_slap_penalties.is_empty():
		return
	var remaining: Array = []
	for item in _pending_slap_penalties:
		var peer := int(item[0])
		var slot := int(item[1])
		if _card_slots.has(peer) and _card_slots[peer].has(slot) and is_instance_valid(_card_slots[peer][slot]):
			animator._animate_slap_penalty(peer, slot)
		else:
			remaining.append(item)
	_pending_slap_penalties = remaining

## SLAP_DUEL 阶段：创建/更新比拼 bar 弹层，离开阶段时移除。
func _render_duel(state: Dictionary) -> void:
	if int(state.get("phase", 0)) == PHASE_SLAP_DUEL:
		if _duel_panel == null:
			var duel: Dictionary = state.get("slap_duel", {})
			var contestants: Array = duel.get("contestants", [])
			duel["viewer_contestant"] = 1 if int(state.get("viewer_id", 0)) in contestants else 0
			_duel_panel = DuelBarScript.new()
			overlay.add_child(_duel_panel)
			_duel_panel.setup(self, duel, _on_slap_duel_stop)
	else:
		if _duel_panel != null:
			_duel_panel.queue_free()
			_duel_panel = null

func _on_slap_duel_stop() -> void:
	GameState.request_slap_duel_stop(_next_action_id())

## GAME_OVER 时打开结算弹层（幂等：已打开则跳过）。reason-only 结算不开弹层，保留右下角摘要。
func _open_settlement() -> void:
	if settlement_page != null and is_instance_valid(settlement_page):
		return
	var result: Dictionary = latest_state.get("result", {})
	if result.get("ranking", []).is_empty():
		return
	var model: Dictionary = SettlementModel.build(latest_state.players)
	var page := SettlementPageScript.instantiate()
	page.name = "SettlementPage"
	# 直接挂 main 末尾 + z_index（仿 settings_menu 已验证模式）：main 子节点逆序 pick，
	# 末位子节点优先于棋盘（margin）接收点击；overlay 是 IGNORE，挂它下面会被 4.6 的
	# get_mouse_filter_with_override 判定为整棵子树不可点。
	page.z_index = 100
	add_child(page)
	page.setup(model, Network.is_host, int(latest_state.get("match_number", 1)),
		_play_pending_winner, _request_next_match, GameState.request_abort_match)
	settlement_page = page

## 关闭结算弹层（收到新局/中止时调用）。
func _close_settlement() -> void:
	if settlement_page != null and is_instance_valid(settlement_page):
		settlement_page.queue_free()
	settlement_page = null

## 冠军时刻：若服务器已广播过 winner 音效事件，此刻播放（延迟到冠军出场）。
func _play_pending_winner() -> void:
	if _pending_winner_sfx:
		AudioManager.play_winner()
		_pending_winner_sfx = false

## 结算页「再来一局」→ 服务器开新局。
func _request_next_match() -> void:
	GameState.request_next_match(_next_action_id())

## ESC 切换设置菜单：懒创建一次，反复切 visible。
func _toggle_settings() -> void:
	if settings_menu == null or not is_instance_valid(settings_menu):
		settings_menu = SettingsMenuScript.new()
		add_child(settings_menu)
	settings_menu.visible = not settings_menu.visible

## 设置菜单切换主题后调用：重刷背景与对局渲染（与 T 键切换同保真度）。
func apply_theme() -> void:
	background.color = UITheme.color("bg_table")
	if not latest_state.is_empty():
		_render_game()
	else:
		_set_status("主题已切换：%s" % UITheme.current)

func _flush_pending_flips() -> void:
	if _pending_flips.is_empty():
		return
	var remaining: Array = []
	for entry in _pending_flips:
		var target_id := int(entry.target_id)
		var slot := int(entry.slot)
		if _card_slots.has(target_id) and _card_slots[target_id].has(slot) and is_instance_valid(_card_slots[target_id][slot]):
			reveal._flip_at(_card_slots[target_id][slot], entry.card, target_id, slot, entry.has("correct"), bool(entry.get("correct", false)))
		else:
			remaining.append(entry)
	_pending_flips = remaining

func _on_pending_action() -> void:
	var pending: Dictionary = latest_state.get("pending", {})
	var actor := int(latest_state.get("viewer_id", 0))
	var big_data: Dictionary = pending.duplicate()
	big_data.erase("source")
	# 隐藏棋盘大牌，播副本动画飞向弃牌堆（落位后弃牌堆显示，大牌不重建）
	animator._animate_discard_pending(big_data, actor)
	if KongRules.has_ability(str(pending.get("rank", ""))):
		_pending_hidden_for_ability = true
		# 能力牌弃牌：本地立即在弃牌堆顶部显示该牌，避免被旧状态覆盖，直到服务器确认
		_discard_local_display = big_data
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
	var name := str(latest_state.get("current_name", ""))
	match phase:
		PHASE_INITIAL_PEEK:
			return "Remember your two bottom cards, then click Ready"
		PHASE_TURN_DRAW:
			var slap_note := ""
			if bool(latest_state.get("slap_open", false)):
				slap_note = " · SLAP open: click matching card"
			if is_current:
				return "Draw from the deck or the discard pile (discard top only replaces)" + slap_note
			return "Waiting for %s to draw a card" % name + slap_note
		PHASE_TURN_DECISION:
			return _decision_hint(is_current, name)
		PHASE_Q_DECISION:
			if is_current:
				return "Swap or not? Pick your own card to exchange, or choose not to"
			return "Waiting for %s to decide" % name
		PHASE_SLAP_WINDOW:
			return "Slap: click a card of the same rank. Wrong slap draws a penalty"
		PHASE_SLAP_EXCHANGE:
			if is_current:
				return "Choose one of your cards to give to the slapped player"
			return "Waiting for %s to give a card" % name
		PHASE_SLAP_DUEL:
			return "Duel: stop closest to the red mark to win the slap"
		PHASE_GAME_OVER:
			return "Ranked by total score, then card count, then highest single card"
	return "Waiting for %s to act" % name

## 处理抽到的牌阶段的细分 hint（按来源/能力/操作模式，区分当前玩家与其他玩家）。
func _decision_hint(is_current: bool, name: String) -> String:
	var pending: Dictionary = latest_state.get("pending", {})
	var rank := str(pending.get("rank", ""))
	var source := str(pending.get("source", "draw"))
	if not is_current:
		# 其他玩家看到的提示
		if source == "discard":
			return "%s took a card from the Discard" % name
		if rank == "J":
			return "%s drew a card and is choosing cards to swap" % name
		if rank in ["7", "8", "9", "10", "Q"]:
			return "%s drew a card and is choosing a card to look at" % name
		return "%s drew a card from the Deck" % name
	# 当前玩家看到的提示
	if source == "discard":
		return "Replace one of your cards with the drawn card"
	match interaction.action_mode:
		"replace":
			return "Replace one of your cards, or discard the drawn card"
		"peek_own":
			return "Choose one of your own cards to peek"
		"peek_other":
			return "Choose another player's card to peek"
		"queen_target":
			return "Peek another player's card, then decide to swap"
		"q_exchange":
			return "Choose your own card to exchange"
		"jack_target":
			return "Click the opponent's card to swap"
		"jack_own":
			return "Click your own card to complete the swap"
	if rank == "J":
		return "Discard to swap two cards, or replace one of your cards"
	if rank in ["7", "8"]:
		return "Discard to peek your own card, or replace one of your cards"
	if rank in ["9", "10"]:
		return "Discard to peek someone's card, or replace one of your cards"
	if rank == "Q":
		return "Discard to peek and decide to swap, or replace one of your cards"
	return "Discard the drawn card, or replace one of your cards"

func _mode_instruction(fallback: String) -> String:
	return interaction.mode_instruction(fallback)

func _show_private_reveal(title: String, revealed_cards: Array, target: Dictionary = {}) -> void:
	reveal.show_private_reveal(title, revealed_cards, target)

## 其他玩家查看某张牌时，在被查看的牌上标蓝色光晕 1 秒（不含牌面）。
## 记录槽位到 _peek_glow_slots，render 重建卡牌后仍可恢复光晕。
func _on_peek_highlight(data: Dictionary) -> void:
	var pid := int(data.get("player_id", 0))
	var slot := int(data.get("slot", -1))
	var key := "%d_%d" % [pid, slot]
	_peek_glow_slots[key] = Time.get_ticks_msec() + int(PEEK_GLOW_DURATION * 1000.0)
	print("[peek_glow] client received: player_id=%d slot=%d（其他玩家视角，蓝色光晕标记）" % [pid, slot])
	if _card_slots.has(pid) and _card_slots[pid].has(slot):
		var card: Control = _card_slots[pid][slot]
		if is_instance_valid(card) and card is CardView:
			(card as CardView).flash_glow(PEEK_GLOW_COLOR, PEEK_GLOW_DURATION, PEEK_GLOW_SIZE)
			print("[peek_glow] flash_glow applied directly pid=%d slot=%d" % [pid, slot])

func _show_toast(message: String) -> void:
	_set_status(message)

func _set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message
	if lobby_status_label != null:
		lobby_status_label.text = message

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.add_theme_font_size_override("font_size", 16)
	return button

func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
