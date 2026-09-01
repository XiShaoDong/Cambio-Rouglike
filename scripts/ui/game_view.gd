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

## 卡牌图片 352x512 比例，所有卡牌尺寸遵循该比例（图片 KEEP_ASPECT_CENTERED 正好填满）。
const CARD_ASPECT := 0.6875
const CARD_SELF_SIZE := Vector2(62, 90)
const CARD_PILE_SIZE := Vector2(74, 107)
const CARD_BIG_SIZE := Vector2(110, 160)

var main: Node
var _ready_clicked := false

func _init(owner_node: Node) -> void:
	main = owner_node

func build() -> void:
	main.game_panel.add_theme_constant_override("separation", 14)
	var board_scene: PackedScene = load("res://scenes/ui/game_board.tscn")
	var board: Control = board_scene.instantiate()
	board.name = "GameBoard"
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.game_panel.add_child(board)
	main.board = board
	# 顶部标题栏（TitleBar 场景）：标题 + 状态信息
	main.status_label = board.get_node("TitleBar/StatusLabel")
	main.status_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	var title_label: Label = board.get_node("TitleBar/Title")
	title_label.add_theme_color_override("font_color", UITheme.color("accent"))
	# 顶部：提示 + Ready（HintArea 场景）
	main.ready_button = board.get_node("HintArea/TopBar/ReadyButton")
	main.ready_button.add_theme_color_override("font_color", UITheme.color("success"))
	main.ready_button.pressed.connect(func():
		_ready_clicked = true
		GameState.request_initial_ready())
	main.center_hint = board.get_node("HintArea/CenterHint")
	main.center_hint.add_theme_color_override("font_color", UITheme.color("accent"))
	main._hint_actions = board.get_node("HintArea/HintActions")
	# 四个玩家区域（GameBoard 直接子节点，锚点自由定位，可拖拽）
	main.top_player_box = board.get_node("PlayerTop")
	main.left_player_box = board.get_node("PlayerLeft")
	main.right_player_box = board.get_node("PlayerRight")
	main.bottom_player_box = board.get_node("PlayerBottom")
	# 中部：中央牌堆
	var pile_area := board.get_node("MiddleRow/PileArea")
	var pile_row: HBoxContainer = pile_area.get_node("PileRow")
	main.deck_button = main._make_card_button({}, CARD_PILE_SIZE)
	main.deck_button.pressed.connect(main._on_deck_pressed)
	pile_row.add_child(main.deck_button)
	main.discard_button = main._make_card_button({}, CARD_PILE_SIZE)
	main.discard_button.pressed.connect(main._on_discard_pressed)
	pile_row.add_child(main.discard_button)
	# 抽到的牌（大牌）：放到 GameBoard 顶层，绝对定位不被容器裁剪，按钮可点击
	main.pending_overlay = main.board
	main.pending_card_box = Control.new()
	main.pending_card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.pending_card_box.visible = false
	main.pending_card_box.z_index = 10
	main.pending_overlay.add_child(main.pending_card_box)
	main.pending_card_button = main._make_card_button({}, CARD_PILE_SIZE)
	main.pending_card_box.add_child(main.pending_card_button)
	main.pending_action_button = main._button("Use Power")
	main.pending_action_button.custom_minimum_size = Vector2(90, 30)
	main.pending_action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.pending_action_button.add_theme_font_size_override("font_size", 13)
	main.pending_action_button.z_index = 20
	main.pending_action_button.pressed.connect(main._on_pending_action)
	main.pending_overlay.add_child(main.pending_action_button)
	# 右下操作区（Corner 场景，锚点绝对定位到右下角）
	var corner := board.get_node("Corner")
	var controls_row: HBoxContainer = corner.get_node("ControlsRow")
	main.bell_button = controls_row.get_node("BellButton")
	main.bell_button.add_theme_color_override("font_color", UITheme.color("danger"))
	main.bell_button.pressed.connect(main._request_kongbaya)
	main.round_label = controls_row.get_node("RoundLabel")
	main.round_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	main.controls_box = controls_row.get_node("ControlsBox")
	var log_row: HBoxContainer = corner.get_node("LogRow")
	main.log_box = log_row.get_node("LogBox")
	main.log_box.add_theme_color_override("default_color", UITheme.color("text_secondary"))

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
	# 能力弃牌本地显示：立即在弃牌堆顶部显示弃掉的牌，服务器确认后清除并改由服务器状态
	if not main._discard_local_display.is_empty():
		var local: Dictionary = main._discard_local_display
		var server_confirmed: bool = not discard.is_empty() and str(discard.get("id", "")) == str(local.get("id", ""))
		if server_confirmed:
			main._discard_local_display = {}
		else:
			main.discard_button.setup(local)
			main._highlight(main.discard_button, available)
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
	var should_show: bool = phase == PHASE_TURN_DECISION and main.latest_state.has("pending")
	if not should_show:
		main.pending_card_box.visible = false
		main.pending_action_button.visible = false
		return
	var pending: Dictionary = main.latest_state.pending
	# 抽牌动画：仅当前玩家播放（其他玩家直接显示背面大牌）
	if is_current and main._draw_flip_pending and str(pending.get("source", "draw")) == "draw":
		main._draw_flip_pending = false
		main.pending_card_box.visible = false
		main.pending_action_button.visible = false
		if is_instance_valid(main.deck_button) and is_instance_valid(main.discard_button):
			var deck_rect: Rect2 = main.deck_button.get_global_rect()
			var disc_rect: Rect2 = main.discard_button.get_global_rect()
			var mid: Vector2 = (deck_rect.get_center() + disc_rect.get_center()) / 2.0
			var big_size: Vector2 = deck_rect.size * 1.5
			var big_rect: Rect2 = Rect2(mid - big_size / 2.0, big_size)
			main._pending_card_id = ""
			main.animator.play_draw(pending, deck_rect, big_rect, func():
				_rebuild_pending_card(pending, is_current))
		return
	# 普通更新：只在 pending 卡牌或视角(is_current)变化时重建，避免动画期间反复释放重建
	var card_id := str(pending.get("card_id", ""))
	if card_id != main._pending_card_id or is_current != main._pending_is_current:
		_rebuild_pending_card(pending, is_current)
	main.pending_card_box.visible = true

## 重建棋盘大牌并定位显示（动画完成回调 / pending 变化时调用）。
## is_current 为当前玩家时显示正面 + Use Power/弃牌按钮；其他玩家显示背面、无按钮。
func _rebuild_pending_card(pending: Dictionary, is_current: bool = true) -> void:
	main._pending_card_id = str(pending.get("card_id", ""))
	main._pending_is_current = is_current
	main.pending_card_button.queue_free()
	var is_hidden: bool = bool(pending.get("hidden", false)) or not is_current
	var display: Dictionary = {} if is_hidden else pending
	main.pending_card_button = main._make_card_button(display, CARD_BIG_SIZE)
	main.pending_card_box.add_child(main.pending_card_button)
	main.pending_card_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.pending_card_button.move_to_front()
	_apply_pending_setup(pending, is_current)
	main.pending_card_box.visible = true

## 棋盘大牌默认 setup：中心 = 两堆中心，大牌实际 1.5 倍尺寸（不用 scale，避免位移）。
## is_current 为当前玩家时显示 Use Power/弃牌按钮；其他玩家不显示按钮。
func _apply_pending_setup(pending: Dictionary, is_current: bool = true) -> void:
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
	main.pending_action_button.visible = false
	if not is_current:
		return
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
	var all_areas: Array = [main.top_player_box, main.left_player_box, main.right_player_box, main.bottom_player_box]
	for area in all_areas:
		area.visible = false
		_clear_area(area)
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

func _clear_area(area: Control) -> void:
	if area.has_node("VBox/HandCenter/HandGrid"):
		for c in area.get_node("VBox/HandCenter/HandGrid").get_children():
			c.queue_free()
	var extra := area.get_node_or_null("ExtraLayer")
	if extra != null:
		# 立即释放，避免 queue_free 延迟导致下一次新建同名节点变 ExtraLayer@N
		extra.free()

func _render_player_section(area: Control, player: Dictionary, viewer: int, is_top: bool) -> void:
	var is_me := int(player.id) == viewer
	var font_size := 16 if is_me else 12
	# 卡牌尺寸：优先用 PlayerArea 场景导出的 card_size（可在编辑器调），否则用代码默认 62x90
	var exported: Variant = area.get("card_size")
	var card_size: Vector2 = exported if exported != null and exported != Vector2.ZERO else CARD_SELF_SIZE
	area.visible = true
	# 主网格列数固定按 HAND_SIZE（罚牌/第 5+ 张不改变列数，避免整手重排位移）
	var hand: GridContainer = area.get_node("VBox/HandCenter/HandGrid")
	hand.columns = maxi(2, ceili(min(player.slots.size(), KongRules.HAND_SIZE) / 2.0))
	# 第 5 张起的额外槽位（罚牌）：ExtraLayer 直接子节点，每个槽位按槽号固定绝对定位
	# （主网格上方/下方、行列固定），加新罚牌时已存在卡牌位置不变
	var old_extra := area.get_node_or_null("ExtraLayer")
	if old_extra != null:
		old_extra.free()
	var extra_layer: Control = null
	if player.slots.size() > KongRules.HAND_SIZE:
		extra_layer = Control.new()
		extra_layer.name = "ExtraLayer"
		extra_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		area.add_child(extra_layer)
	for slot_index in player.slots.size():
		if slot_index >= KongRules.HAND_SIZE:
			if extra_layer != null:
				_render_extra_slot(extra_layer, player, slot_index, card_size, hand)
			continue
		_render_card_slot(hand, player, slot_index, card_size)
	var name_label: Label = area.get_node("VBox/NameLabel")
	var suffix := "（你）" if is_me else ""
	var ready_mark := ""
	if int(main.latest_state.phase) == PHASE_INITIAL_PEEK:
		ready_mark = "  [✓已准备]" if bool(player.get("ready", false)) else "  [等待]"
	name_label.text = "%s%s%s" % [player.name, suffix, ready_mark]
	name_label.add_theme_font_size_override("font_size", font_size)
	name_label.add_theme_color_override("font_color", UITheme.color("player_self_text") if is_me else UITheme.color("player_other_text"))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var name_style := StyleBoxFlat.new()
	name_style.bg_color = UITheme.color("player_self_bg") if is_me else UITheme.color("player_other_bg")
	name_style.set_corner_radius_all(6)
	name_style.set_content_margin_all(6)
	name_label.add_theme_stylebox_override("normal", name_style)
	if is_top:
		name_label.text = "▲ " + name_label.text
	if is_me:
		name_label.text = "▼ " + name_label.text

## 渲染单个卡牌槽位到指定容器（主网格或 ExtraLayer），并登记到 _card_slots 供动画定位。
## use_fixed 时用 fixed_pos（全局坐标）绝对定位（罚牌附加行：按槽号固定，加新牌不移位）。
func _render_card_slot(container: Control, player: Dictionary, slot_index: int, card_size: Vector2, fixed_pos := Vector2.ZERO, use_fixed := false) -> void:
	var pid := int(player.id)
	var slot: Dictionary = player.slots[slot_index]
	var is_empty_slot := str(slot.get("card_id", "")) == ""
	var is_anim_slot: bool = main.is_anim_slot(pid, slot_index)
	if is_empty_slot or is_anim_slot:
		# 空槽/动画中槽位：透明占位（无虚线），保持网格布局对齐但不可见
		var empty := PanelContainer.new()
		empty.custom_minimum_size = card_size
		empty.size = card_size
		var ts := StyleBoxFlat.new()
		ts.bg_color = Color(0, 0, 0, 0)
		ts.set_corner_radius_all(8)
		empty.add_theme_stylebox_override("panel", ts)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(empty)
		if use_fixed:
			empty.global_position = fixed_pos
		if not main._card_slots.has(pid):
			main._card_slots[pid] = {}
		main._card_slots[pid][slot_index] = empty
		return
	var card_button: Button = main._make_card_button(slot.get("card", {}), card_size)
	card_button.tooltip_text = "记忆牌面后，点击以执行当前操作"
	card_button.pressed.connect(main._on_card_pressed.bind(pid, slot_index))
	main._highlight(card_button, main._card_actionable(pid, slot_index))
	container.add_child(card_button)
	if use_fixed:
		card_button.global_position = fixed_pos
	if not main._card_slots.has(pid):
		main._card_slots[pid] = {}
	main._card_slots[pid][slot_index] = card_button
	# 查看高亮持久化：该槽位在查看光晕有效期内 → render 重建后恢复蓝色光晕
	var glow_key := "%d_%d" % [pid, slot_index]
	if main._peek_glow_slots.has(glow_key):
		var deadline: int = int(main._peek_glow_slots[glow_key])
		if Time.get_ticks_msec() < deadline:
			var remain: float = (deadline - Time.get_ticks_msec()) / 1000.0
			(card_button as CardView).flash_glow(main.PEEK_GLOW_COLOR, remain, main.PEEK_GLOW_SIZE)
			print("[peek_glow] render re-applied glow pid=%d slot=%d remain=%.2fs" % [pid, slot_index, remain])
		else:
			main._peek_glow_slots.erase(glow_key)

func _render_log() -> void:
	var accent_html := UITheme.color("accent").to_html(false)
	var lines := ["[color=#%s]对局记录[/color]" % accent_html]
	for entry in main._local_log:
		lines.append("• %s" % str(entry))
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

## 渲染罚牌附加槽位到 ExtraLayer：按槽号固定绝对定位（统一在主网格上方、行列固定）。
## 所有玩家方向一致（向上增长），与主视角一致。
func _render_extra_slot(layer: Control, player: Dictionary, slot_index: int, card_size: Vector2, hand: GridContainer) -> void:
	var pos := _extra_slot_pos(hand.get_global_rect(), slot_index, card_size)
	_render_card_slot(layer, player, slot_index, card_size, pos, true)

## 附加槽位固定位置（统一在主网格上方）：idx0/1 在靠主网格的一行（第1列/第2列），idx2/3 在更上一行，依此类推。
## 每个槽位位置只由槽号决定，加新罚牌时已存在的卡牌不移动。
func _extra_slot_pos(grid_rect: Rect2, slot_index: int, card_size: Vector2) -> Vector2:
	var idx := slot_index - KongRules.HAND_SIZE
	var col := idx % 2
	var row := idx / 2
	var x := grid_rect.position.x + col * (card_size.x + 6.0)
	var y := grid_rect.position.y - (row + 1) * (card_size.y + 6.0)
	return Vector2(x, y)
