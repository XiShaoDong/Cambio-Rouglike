class_name GameView
extends RefCounted
## 对局视图 + 渲染器（main.gd 拆分 · 第三优先级）
## 职责：构建对局界面（build_*）与把 GameState 投影成 UI（render_*）。
## 持有 main（组合根）引用，通过其工具方法（_button/_make_card_button/_highlight/_clear
## 等）与状态（latest_state/interaction/_cards/_card_slots/_pending_flips/overlay）协作。

const PHASE_INITIAL_PEEK := 1
const PHASE_TURN_DRAW := 2
const PHASE_TURN_DECISION := 3
const PHASE_Q_DECISION := 4
const PHASE_SLAP_WINDOW := 5
const PHASE_SLAP_EXCHANGE := 6
const PHASE_GAME_OVER := 7

var main: Node
var _ready_clicked := false

func _init(owner_node: Node) -> void:
	main = owner_node

func build() -> void:
	main.game_panel.add_theme_constant_override("separation", 14)
	# 顶部：标题 + 提示 + Ready
	var top_unit := VBoxContainer.new()
	top_unit.alignment = BoxContainer.ALIGNMENT_CENTER
	top_unit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top_unit.add_theme_constant_override("separation", 6)
	main.game_panel.add_child(top_unit)
	var top_bar := HBoxContainer.new()
	top_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	top_bar.add_theme_constant_override("separation", 24)
	top_unit.add_child(top_bar)
	main.game_header = Label.new()
	main.game_header.add_theme_font_size_override("font_size", 18)
	main.game_header.add_theme_color_override("font_color", UITheme.color("text_primary"))
	main.game_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.game_header.visible = false
	top_bar.add_child(main.game_header)
	main.ready_button = main._button("Ready（0/0）")
	main.ready_button.custom_minimum_size = Vector2(180, 40)
	main.ready_button.add_theme_font_size_override("font_size", 16)
	main.ready_button.add_theme_color_override("font_color", UITheme.color("success"))
	main.ready_button.pressed.connect(func():
		_ready_clicked = true
		GameState.request_initial_ready())
	main.ready_button.visible = false
	top_bar.add_child(main.ready_button)
	main.center_hint = RichTextLabel.new()
	main.center_hint.bbcode_enabled = true
	main.center_hint.scroll_active = false
	main.center_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.center_hint.custom_minimum_size = Vector2(0, 72)
	main.center_hint.add_theme_color_override("default_color", UITheme.color("accent"))
	top_unit.add_child(main.center_hint)
	main._hint_actions = HBoxContainer.new()
	main._hint_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	main._hint_actions.add_theme_constant_override("separation", 8)
	top_unit.add_child(main._hint_actions)
	# 上方对手
	main.top_player_box = VBoxContainer.new()
	main.top_player_box.alignment = BoxContainer.ALIGNMENT_CENTER
	main.top_player_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.top_player_box.add_theme_constant_override("separation", 4)
	main.game_panel.add_child(main.top_player_box)
	# 中部行：左对手 | 中央牌堆 | 右对手
	var opponents_row := HBoxContainer.new()
	opponents_row.alignment = BoxContainer.ALIGNMENT_CENTER
	opponents_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	opponents_row.add_theme_constant_override("separation", 36)
	main.game_panel.add_child(opponents_row)
	main.left_player_box = VBoxContainer.new()
	main.left_player_box.alignment = BoxContainer.ALIGNMENT_CENTER
	main.left_player_box.add_theme_constant_override("separation", 4)
	opponents_row.add_child(main.left_player_box)
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
	main.deck_button = main._make_card_button({}, Vector2(68, 107))
	main.deck_button.pressed.connect(main._on_deck_pressed)
	pile_row.add_child(main.deck_button)
	main.discard_button = main._make_card_button({}, Vector2(68, 107))
	main.discard_button.pressed.connect(main._on_discard_pressed)
	pile_row.add_child(main.discard_button)
	var pile_hint := Label.new()
	pile_hint.text = "抽牌堆          弃牌堆"
	pile_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pile_hint.add_theme_font_size_override("font_size", 12)
	pile_hint.add_theme_color_override("font_color", UITheme.color("text_muted"))
	center_unit.add_child(pile_hint)
	main.right_player_box = VBoxContainer.new()
	main.right_player_box.alignment = BoxContainer.ALIGNMENT_CENTER
	main.right_player_box.add_theme_constant_override("separation", 4)
	opponents_row.add_child(main.right_player_box)
	# 抽到的牌（大牌）：完全贴合叠放在抽牌堆（deck_button）上
	main.pending_overlay = Control.new()
	main.pending_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.pending_overlay.mouse_filter = Control.MOUSE_FILTER_PASS
	main.pending_overlay.z_index = 10
	center_unit.add_child(main.pending_overlay)
	main.pending_card_box = Control.new()
	main.pending_card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.pending_card_box.visible = false
	main.pending_overlay.add_child(main.pending_card_box)
	main.pending_card_button = main._make_card_button({}, Vector2(68, 107))
	main.pending_card_box.add_child(main.pending_card_button)
	main.pending_action_button = main._button("Use Power")
	main.pending_action_button.custom_minimum_size = Vector2(90, 30)
	main.pending_action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.pending_action_button.add_theme_font_size_override("font_size", 13)
	main.pending_action_button.z_index = 20
	main.pending_action_button.pressed.connect(main._on_pending_action)
	main.pending_overlay.add_child(main.pending_action_button)
	# 当前玩家（底部）
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 80)
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.game_panel.add_child(spacer)
	main.bottom_player_box = VBoxContainer.new()
	main.bottom_player_box.alignment = BoxContainer.ALIGNMENT_CENTER
	main.bottom_player_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.bottom_player_box.add_theme_constant_override("separation", 4)
	main.game_panel.add_child(main.bottom_player_box)
	# 右下操作区（绝对定位到右下角，不随对局内容流动）
	var corner := VBoxContainer.new()
	corner.alignment = BoxContainer.ALIGNMENT_END
	corner.add_theme_constant_override("separation", 8)
	corner.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	corner.offset_left = -360
	corner.offset_top = -150
	corner.offset_right = -12
	corner.offset_bottom = -8
	main.overlay.add_child(corner)
	var controls_row := HBoxContainer.new()
	controls_row.alignment = BoxContainer.ALIGNMENT_END
	controls_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_row.add_theme_constant_override("separation", 14)
	corner.add_child(controls_row)
	main.bell_button = main._button("🔔 KONGBAYA")
	main.bell_button.custom_minimum_size = Vector2(190, 46)
	main.bell_button.add_theme_font_size_override("font_size", 18)
	main.bell_button.add_theme_color_override("font_color", UITheme.color("danger"))
	main.bell_button.pressed.connect(main._request_kongbaya)
	controls_row.add_child(main.bell_button)
	main.round_label = Label.new()
	main.round_label.text = "第 1 局"
	main.round_label.add_theme_font_size_override("font_size", 14)
	main.round_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	main.round_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	controls_row.add_child(main.round_label)
	main.controls_box = HBoxContainer.new()
	main.controls_box.add_theme_constant_override("separation", 8)
	controls_row.add_child(main.controls_box)
	# 右下：对局记录
	var log_row := HBoxContainer.new()
	log_row.alignment = BoxContainer.ALIGNMENT_END
	log_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	corner.add_child(log_row)
	main.log_box = RichTextLabel.new()
	main.log_box.bbcode_enabled = true
	main.log_box.custom_minimum_size = Vector2(340, 120)
	main.log_box.add_theme_font_size_override("normal_font_size", 12)
	main.log_box.add_theme_color_override("default_color", UITheme.color("text_secondary"))
	log_row.add_child(main.log_box)

## 把最新状态投影到界面。
func render(state: Dictionary) -> void:
	if state.is_empty():
		return
	var phase := int(state.phase)
	var viewer := int(state.viewer_id)
	var is_current := viewer == int(state.current_player)
	var total_players: int = state.players.size()
	if phase == PHASE_INITIAL_PEEK:
		var ready_count: int = int(state.get("ready_count", 0))
		main.ready_button.visible = true
		main.ready_button.disabled = ready_count >= total_players or _ready_clicked
		if _ready_clicked:
			main.ready_button.text = "已准备（%d/%d）" % [ready_count, total_players]
		else:
			main.ready_button.text = "Ready（%d/%d）" % [ready_count, total_players]
	else:
		main.ready_button.visible = false
		_ready_clicked = false
	main.center_hint.text = main._hint_for(phase, is_current)
	main.round_label.text = "第 %d 局" % int(state.get("match_number", 1))
	main.bell_button.disabled = not (phase == PHASE_TURN_DRAW and is_current)
	main.bell_button.tooltip_text = "轮到你抽牌时，按下铃铛宣布 KONGBAYA！其他人各有一次最后行动。"
	_update_pending_card(phase, is_current)
	main._clear(main.controls_box)
	var can_take := phase == PHASE_TURN_DRAW and is_current
	main.deck_button.disabled = not can_take
	main._highlight(main.deck_button, can_take)
	var discard: Dictionary = state.discard
	var discard_available := can_take and not discard.is_empty()
	_update_discard_button(discard, discard_available)
	_render_controls(phase, is_current)
	_render_players(viewer)
	_render_log()
	main._flush_pending_flips()

func _update_discard_button(discard: Dictionary, available: bool) -> void:
	# 弃牌堆动画中：延迟显示（落位后才更新）
	if main._discard_anim_lock:
		return
	main.discard_button.disabled = not available
	if main.discard_button is CardView:
		main.discard_button.setup(discard)
		if discard.is_empty():
			# 弃牌堆为空：隐藏卡面，只留虚线空位
			main.discard_button.back.visible = false
			main.discard_button.front.visible = false
			if not main.discard_button.has_node("DiscardDashed"):
				var dashed: DashedBorder = DashedBorder.new()
				dashed.name = "DiscardDashed"
				dashed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				dashed.mouse_filter = Control.MOUSE_FILTER_IGNORE
				main.discard_button.add_child(dashed)
			main.discard_button.get_node("DiscardDashed").visible = true
		elif main.discard_button.has_node("DiscardDashed"):
			main.discard_button.get_node("DiscardDashed").visible = false
	main._highlight(main.discard_button, available)

func _update_pending_card(phase: int, is_current: bool) -> void:
	# 能力选择中：棋盘大牌隐藏（已用副本飞向弃牌堆），pending 弃掉后清除标记
	if main._pending_hidden_for_ability:
		main.pending_card_box.visible = false
		main.pending_action_button.visible = false
		if not (phase == PHASE_TURN_DECISION and is_current and main.latest_state.has("pending")):
			main._pending_hidden_for_ability = false
		return
	var should_show: bool = phase == PHASE_TURN_DECISION and is_current and main.latest_state.has("pending")
	main.pending_card_box.visible = should_show
	main.pending_action_button.visible = false
	if not should_show:
		return
	var pending: Dictionary = main.latest_state.pending
	main.pending_card_button.queue_free()
	main.pending_card_button = main._make_card_button(pending, Vector2(102, 160))
	main.pending_card_box.add_child(main.pending_card_button)
	main.pending_card_button.move_to_front()
	# 棋盘默认 setup：两堆中心 + scale 1.5 + 按钮
	_apply_pending_setup(pending)
	# 抽牌动画：点击抽牌堆后，隐藏棋盘大牌，用副本从抽牌堆飞到大牌位置并翻成正面
	if main._draw_flip_pending and str(pending.get("source", "draw")) == "draw":
		main._draw_flip_pending = false
		if is_instance_valid(main.deck_button) and is_instance_valid(main.discard_button):
			var deck_rect: Rect2 = main.deck_button.get_global_rect()
			var disc_rect: Rect2 = main.discard_button.get_global_rect()
			var mid: Vector2 = (deck_rect.get_center() + disc_rect.get_center()) / 2.0
			var big_size: Vector2 = deck_rect.size * 1.5
			var big_rect: Rect2 = Rect2(mid - big_size / 2.0, big_size)
			main.pending_card_box.visible = false
			main.animator.play_draw(pending, deck_rect, big_rect, func():
				main.pending_card_box.visible = true)

## 棋盘大牌默认 setup：中心 = 两堆中心，大牌实际 1.5 倍尺寸（不用 scale，避免位移）。
func _apply_pending_setup(pending: Dictionary) -> void:
	if is_instance_valid(main.deck_button) and is_instance_valid(main.discard_button):
		var deck_rect: Rect2 = main.deck_button.get_global_rect()
		var disc_rect: Rect2 = main.discard_button.get_global_rect()
		var mid: Vector2 = (deck_rect.get_center() + disc_rect.get_center()) / 2.0
		var big_size: Vector2 = deck_rect.size * 1.5
		main.pending_card_box.global_position = mid - big_size / 2.0
		main.pending_card_box.size = big_size
		main.pending_card_box.pivot_offset = Vector2.ZERO
		main.pending_card_box.scale = Vector2.ONE
		# Use Power/弃牌按钮放在大牌内部下方
		main.pending_action_button.custom_minimum_size = Vector2(big_size.x - 8, 26)
		main.pending_action_button.global_position = mid - Vector2(big_size.x / 2.0, 0) + Vector2(4, big_size.y / 2.0 - 28)
	var from_discard := str(pending.get("source", "draw")) == "discard"
	if from_discard:
		return
	main.pending_action_button.visible = true
	if KongRules.has_ability(str(pending.get("rank", ""))):
		main.pending_action_button.text = "Use Power"
		main.pending_action_button.add_theme_color_override("font_color", UITheme.color("accent"))
	else:
		main.pending_action_button.text = "弃牌"
		main.pending_action_button.add_theme_color_override("font_color", UITheme.color("text_secondary"))

func _render_controls(phase: int, is_current: bool) -> void:
	# 清空 hint 区域的操作按钮
	for child in main._hint_actions.get_children():
		child.queue_free()
	if phase == PHASE_Q_DECISION and is_current:
		var keep: Button = main._button("Q：不交换")
		keep.pressed.connect(func(): GameState.request_q_decision(false, -1, main._next_action_id()))
		main._hint_actions.add_child(keep)
		var exchange: Button = main._button("Q：交换（再点自己一张牌）")
		exchange.pressed.connect(func(): main.interaction.action_mode = "q_exchange"; main._render_game())
		main._hint_actions.add_child(exchange)
	elif phase == PHASE_GAME_OVER:
		var result: Dictionary = main.latest_state.result
		var summary := Label.new()
		if result.has("reason"):
			summary.text = str(result.reason)
		else:
			var winners: Array = result.get("winners", [])
			var winner_names: Array[String] = []
			for player in main.latest_state.players:
				if int(player.id) in winners:
					winner_names.append(str(player.name))
			summary.text = "获胜：%s" % "、".join(winner_names)
		summary.add_theme_font_size_override("font_size", 20)
		summary.add_theme_color_override("font_color", UITheme.color("success"))
		main.controls_box.add_child(summary)

func _render_players(viewer: int) -> void:
	main._clear(main.top_player_box)
	main._clear(main.left_player_box)
	main._clear(main.right_player_box)
	main._clear(main.bottom_player_box)
	var players: Array = main.latest_state.players
	var others: Array = []
	var me: Dictionary = {}
	for player in players:
		if int(player.id) == viewer:
			me = player
		else:
			others.append(player)
	var opponent_slots: Array = []
	for player in others:
		opponent_slots.append(player)
	if opponent_slots.size() >= 1:
		_render_player_section(main.left_player_box, opponent_slots[0], viewer, false)
	if opponent_slots.size() >= 2:
		_render_player_section(main.right_player_box, opponent_slots[1], viewer, false)
	if opponent_slots.size() >= 3:
		_render_player_section(main.top_player_box, opponent_slots[2], viewer, true)
	if not me.is_empty():
		_render_player_section(main.bottom_player_box, me, viewer, false)

func _render_player_section(box: VBoxContainer, player: Dictionary, viewer: int, is_top: bool) -> void:
	var is_me := int(player.id) == viewer
	var card_size := Vector2(57, 89) if is_me else Vector2(34, 53)
	var font_size := 16 if is_me else 12
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	box.add_child(section)
	var hand := GridContainer.new()
	hand.columns = maxi(2, ceili(player.slots.size() / 2.0))
	hand.add_theme_constant_override("h_separation", 6)
	hand.add_theme_constant_override("v_separation", 6)
	hand.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	section.add_child(hand)
	for slot_index in player.slots.size():
		var slot: Dictionary = player.slots[slot_index]
		var is_empty_slot := str(slot.get("card_id", "")) == ""
		var is_anim_slot: bool = main.is_anim_slot(int(player.id), slot_index)
		if is_empty_slot or is_anim_slot:
			# 空槽/动画中槽位：透明背景 + 虚线边框占位
			var empty := PanelContainer.new()
			empty.custom_minimum_size = card_size
			empty.size = card_size
			var ts := StyleBoxFlat.new()
			ts.bg_color = Color(0, 0, 0, 0)
			ts.set_corner_radius_all(8)
			empty.add_theme_stylebox_override("panel", ts)
			empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var dashed := DashedBorder.new()
			dashed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			dashed.mouse_filter = Control.MOUSE_FILTER_IGNORE
			empty.add_child(dashed)
			hand.add_child(empty)
			if not main._card_slots.has(int(player.id)):
				main._card_slots[int(player.id)] = {}
			main._card_slots[int(player.id)][slot_index] = empty
			continue
		var card_button: Button = main._make_card_button(slot.get("card", {}), card_size)
		card_button.tooltip_text = "记忆牌面后，点击以执行当前操作"
		card_button.pressed.connect(main._on_card_pressed.bind(int(player.id), slot_index))
		main._highlight(card_button, main._card_actionable(int(player.id), slot_index))
		hand.add_child(card_button)
		if not main._card_slots.has(int(player.id)):
			main._card_slots[int(player.id)] = {}
		main._card_slots[int(player.id)][slot_index] = card_button
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
	if int(main.latest_state.phase) == PHASE_INITIAL_PEEK:
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

func _render_log() -> void:
	var accent_html := UITheme.color("accent").to_html(false)
	var lines := ["[color=#%s]对局记录[/color]" % accent_html]
	for entry in main.latest_state.event_log:
		lines.append("• %s" % str(entry))
	if int(main.latest_state.phase) == PHASE_GAME_OVER:
		var ranking: Array = (main.latest_state.result as Dictionary).get("ranking", [])
		if not ranking.is_empty():
			lines.append("\n[color=#f6d77a]排名[/color]")
			for index in ranking.size():
				var entry: Dictionary = ranking[index]
				lines.append("%d. %s：%d 分，%d 张" % [index + 1, entry.name, int(entry.score), int(entry.count)])
	main.log_box.text = "\n".join(lines)