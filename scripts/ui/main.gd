extends Control

## Deliberately code-built MVP interface: it keeps the visual layer small while
## the game rules and networking remain independently testable.

var dev: DevTools
var dev_mode := false

func _notification(what: int) -> void:
	# 点击窗口关闭：拦截默认退出。若仍在房间/对局中 → 回初始大厅；已在初始大厅 → 真正退出
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _table3d_active:
			_set_table3d(false)
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
	if _table3d_active:
		_set_table3d(false)
	if Network.is_host:
		GameState.request_close_room()
	else:
		lobby._leave_room()
	_set_status("已回到大厅。")

## F10：在 2D 对局界面与 3D 只读预览之间切换。
func _toggle_table3d() -> void:
	_set_table3d(not _table3d_active)

## 点击路由：命中看板 → "board"；有模态面板 → "blocked"；否则 → "table"。
## 关键：常驻提示板可见不等于"模态打开"，不能因此吞掉牌桌点击。
func _click_route(board_hit: bool) -> String:
	if board_hit:
		return "board"
	if _board_has_panel():
		return "blocked"
	return "table"

## 准星点击分发：只调用既有入口，不改规则。
func _table3d_click() -> void:
	if table3d == null or not is_instance_valid(table3d):
		return
	var hit := _board_hit()
	match _click_route(not hit.is_empty()):
		"board":
			(hit.host as Board3d).push_click(hit.coord)
			return
		"blocked":
			return
	var pick: Dictionary = table3d.pick_center()
	match str(pick.get("kind", "")):
		"slot":
			interaction.on_card_pressed(int(pick.get("seat", 0)), int(pick.get("slot", -1)))
		"deck":
			_on_deck_pressed()
		"discard":
			# 弃牌堆按上下文：可弃大牌/用能力 → 弃掉抽到的牌；否则 → 取弃牌顶
			if ActionModel.pending_discard_available(latest_state):
				_on_pending_action()
			else:
				_on_discard_pressed()
		"hud":
			_on_action(str(pick.get("action", "")))

## 3D 操作面板动作（与 2D 控制按钮行为一致）。
func _on_action(action: String) -> void:
	match action:
		"ready":
			game_view._ready_clicked = true
			GameState.request_initial_ready()
		"kongbaya":
			_request_kongbaya()
		"q_keep":
			_release_q_holds()
			GameState.request_q_decision(false, -1, _next_action_id())
		"q_exchange":
			# 不在此释放：保留两张正面，等交换飞牌 consume 后从正面起飞、背面落地
			GameState.request_q_decision(true, -1, _next_action_id())
		"j_exchange":
			interaction.jack_swap_now()
		"j_keep":
			interaction.jack_cancel()
		"joker":
			_open_joker_transform_panel()

## 3D 操作面板按钮：条件动作（Q/Joker）已移到提示板下方，Ready 在提示板、Kongbaya 由铃铛负责，
## 故 3D 桌面 HUD 不再承载按钮（保留空面板以兼容既有结构）。
func _hud_buttons() -> Array:
	return []

## 本地交互态上下文（供 ActionModel.conditional_actions 判定 J 是否可选交换/交换是否可用）。
func _interaction_ctx() -> Dictionary:
	return {
		"action_mode": interaction.action_mode,
		"selected_target": interaction.selected_target,
		"selected_their_slot": interaction.selected_their_slot,
		"selected_own_slot": interaction.selected_own_slot,
	}

## 3D 激活时恒定捕获鼠标（看板交互走准星），准星恒显示。
func _sync_table3d_pointer() -> void:
	if not _table3d_active:
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _crosshair != null and is_instance_valid(_crosshair):
		_crosshair.visible = true

## 3D 自己面板（屏幕右下角）：生命/金钱/卡牌数（无名字）。
func _ensure_self_panel() -> void:
	if _self_panel != null and is_instance_valid(_self_panel):
		return
	_self_panel = PlayerStatPanel.new()
	_self_panel.name = "SelfStatPanel"
	_self_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_self_panel.z_index = 80
	_self_panel.set_corner_style(true)  # 屏幕角落 HUD：dark 下 #FEF0E4 底 + 白字
	add_child(_self_panel)
	_self_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, int(round(_corner_margin())))
	_self_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_self_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

## 四角 HUD 到屏幕边缘的边距：把"目标屏幕像素 75"换算成 CanvasItem 设计坐标，
## 补偿 `window/stretch/mode=canvas_items` 的窗口拉伸（窗口大于 1280×760 时放大 → 实测 >75）。
func _corner_margin() -> float:
	var win := get_window()
	if win == null:
		return CORNER_MARGIN
	var base := Vector2(win.content_scale_size)
	var win_size := Vector2(win.size)
	if base.x <= 0.0 or win_size.x <= 0.0:
		return CORNER_MARGIN
	var scale := win_size.x / base.x
	return CORNER_MARGIN / maxf(scale, 0.0001)

## 3D action hint 屏幕面板：顶部居中的「倒计时 + 提示文本」。
func _ensure_hint_hud() -> void:
	if _hint_hud != null and is_instance_valid(_hint_hud):
		return
	_hint_hud = HintHud.new()
	_hint_hud.name = "HintHud"
	_hint_hud.z_index = 80
	add_child(_hint_hud)

## 驱动 HintHud：文本随 hint 变化，进入新回合（key 变化）时重置 30 并播进场。
func _update_hint_hud(phase: int, viewer: int, current: int) -> void:
	if _hint_hud == null or not is_instance_valid(_hint_hud):
		return
	var text := _hint_for(phase, viewer == current)
	_hint_hud.set_phase_visible(phase)
	var slap_state := HintHud.SLAP_HIDDEN
	if phase == PHASE_SLAP_EXCHANGE or phase == PHASE_SLAP_DUEL:
		slap_state = HintHud.SLAP_CLOSE
	elif bool(latest_state.get("slap_open", false)):
		slap_state = HintHud.SLAP_OPEN
	_hint_hud.set_slap_state(slap_state)
	var key := "%d:%d" % [int(latest_state.get("match_number", 1)), current]
	if phase in _HUD_ACTIVE_PHASES and key != _hud_turn_key:
		_hud_turn_key = key
		_hint_hud.reset_turn(HintHud.PHASE_TURN_SECONDS, text)
	else:
		_hint_hud.set_hint(text)

## 3D 左下角按键提示（放大 Command / 手册 Tab）：说明纯白 + 圆角白底按键。
func _ensure_key_hints() -> void:
	if _key_hints != null and is_instance_valid(_key_hints):
		return
	_key_hints = KeyHintPanel.new()
	_key_hints.name = "KeyHints"
	_key_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key_hints.z_index = 80
	add_child(_key_hints)
	_key_hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, int(round(_corner_margin())))
	_key_hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_key_hints.grow_horizontal = Control.GROW_DIRECTION_END
	_key_hints.setup([["放大", "Command"], ["手册", "Tab"]])

## 3D 右上角回合徽标（与按键 chip 同款圆角灰底+边框，字号 = Command chip ×2）。
func _ensure_round_badge() -> void:
	if _round_badge != null and is_instance_valid(_round_badge):
		return
	_round_badge = KeyHintPanel.make_chip("回合 1/1", KeyHintPanel.ROUND_FONT_SIZE, KeyHintPanel.ROUND_H_PAD)
	_round_badge.name = "RoundBadge"
	_round_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_badge.z_index = 80
	add_child(_round_badge)
	_round_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(round(_corner_margin())))
	_round_badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_round_badge.grow_vertical = Control.GROW_DIRECTION_END
	_update_round_badge()

func _update_round_badge() -> void:
	if _round_badge == null or not is_instance_valid(_round_badge):
		return
	var label: Label = _round_badge.get_node_or_null("Key")
	if label == null:
		return
	var limit := int((latest_state.get("run", {}) as Dictionary).get("match_limit", KongRules.DEFAULT_MATCH_LIMIT))
	label.text = "回合 %d/%d" % [int(latest_state.get("match_number", 1)), limit]

func _update_self_panel() -> void:
	if _self_panel == null or not is_instance_valid(_self_panel):
		return
	var viewer := int(latest_state.get("viewer_id", 0))
	for p in latest_state.get("players", []):
		if int(p.id) == viewer:
			_self_panel.set_data("", int(p.get("health", 0)), int(p.get("currency", 0)), int(p.get("count", 0)))
			return

## 确保看板存在：模态大板 board3d + 常驻提示板 hint3d（均挂 table3d 下，随 3D 世界显隐）。
func _ensure_board() -> void:
	if table3d == null or not is_instance_valid(table3d):
		return
	if board3d == null or not is_instance_valid(board3d):
		board3d = Board3d.new()
		board3d.name = "ModalBoard"
		table3d.add_child(board3d)
	if hint3d == null or not is_instance_valid(hint3d):
		hint3d = Board3d.new()
		hint3d.name = "HintBoard"
		table3d.add_child(hint3d)
		hint3d.set_halo_enabled(false)   # 提示板只显示按钮本身，不要外圈光晕边框
		hint3d.set_pick_pad(Vector2(0.5, 0.5))   # 放宽拾取盒：准星略偏也能命中 Ready/按钮
		_hint_panel = _make_hint_panel()
		hint3d.mount_panel(_hint_panel)

## 看板定位：模态板锚在本机座位→桌心的 BOARD_DEPTH 深度处、悬浮于桌面上方（贴近玩家）；
## 提示板沿用"相机→桌心连线"（其"贴准星"逻辑依赖该基准）。
func _place_boards() -> void:
	if table3d == null or not is_instance_valid(table3d):
		return
	var cam: Camera3D = table3d.camera.camera_node()
	var viewer := int(latest_state.get("viewer_id", 0))
	var seat_pos: Vector3 = table3d.seat_world(viewer)
	# 模态大板 + 提示板（Ready/条件按钮）：统一锚到本机座位与桌心之间的深度、悬浮桌面上方（贴玩家、不靠后）
	if board3d != null and is_instance_valid(board3d):
		board3d.global_position = _board_anchor_world(seat_pos, cam, board3d.world_size().y)
	if hint3d != null and is_instance_valid(hint3d):
		hint3d.global_position = _board_anchor_world(seat_pos, cam, hint3d.world_size().y)

## 看板/提示板统一锚点：本机座位→桌心 BOARD_DEPTH 深度、悬浮桌面上方；无座位时回退相机→桌心连线。
func _board_anchor_world(seat_pos: Vector3, cam: Camera3D, board_h: float) -> Vector3:
	if seat_pos.length_squared() > 0.0001:
		var anchor := Table3dLayout.board_depth_pos(seat_pos, BOARD_DEPTH, BOARD_TABLE_HALF)
		return Vector3(anchor.x, Table3dLayout.TABLE_HEIGHT + BOARD_FLOAT_H + board_h * 0.5, anchor.z)
	if cam != null:
		var dir := Vector3(0.0, Table3dLayout.TABLE_HEIGHT, 0.0) - cam.global_position
		if dir.length_squared() > 0.0001:
			return cam.global_position + dir.normalized() * BOARD_DIST
	return Vector3.ZERO

## 有模态面板 / 提示按钮时，自动把相机视线对准看板——看板锚在高位，默认准星落在桌面会打不到。
## 模态板：仅在**打开时**对准一次（商店/结算内容或高度变化不再重对准，避免相机跳动打断点击）。
## 提示板（Ready/Q/J）：按钮集合变化时重新对准，保证新出现的按钮落在准星上。
func _auto_aim_board() -> void:
	# 结算（算分/翻牌）期间不要强制调整玩家镜头；也不在此时聚焦，交由玩家自由环视。
	if int(latest_state.get("phase", -1)) == PHASE_GAME_OVER:
		_board_aim_key = ""
		return
	var host: Node3D = null
	var key := ""
	if _board_has_panel() and board3d != null and is_instance_valid(board3d) and board3d.visible:
		host = board3d
		key = "modal"
	elif hint3d != null and is_instance_valid(hint3d) and hint3d.visible:
		host = hint3d
		key = "hint|%s" % str(hint3d.world_size())
	if host == null:
		_board_aim_key = ""
		return
	if key == _board_aim_key:
		return
	_board_aim_key = key
	if table3d.camera != null:
		table3d.camera.aim_at(host.global_position)

## 模态挂载：3D 激活挂到模态大板，否则沿用 2D 父节点（默认 main）。
func _mount_modal(control: Control, parent_2d: Node = null) -> void:
	if _table3d_active:
		_ensure_board()
		if board3d != null and is_instance_valid(board3d):
			board3d.mount_panel(control)
			return
	(parent_2d if parent_2d != null else self).add_child(control)

## 模态关闭前先从看板卸下（3D 时），避免已释放面板残留在看板 _panels。
func _unmount_modal(control: Control) -> void:
	if _table3d_active and board3d != null and is_instance_valid(board3d) \
			and control != null and is_instance_valid(control):
		board3d.unmount_panel(control)

func _board_has_panel() -> bool:
	return board3d != null and is_instance_valid(board3d) and board3d.has_panel()

## 构造常驻提示面板：提示文本 + （开局记忆阶段）Ready 按钮。
func _make_hint_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "HintPanel"
	# 透明容器：不再加面板边框/底色（3D 下只显示按钮本身，去除从 2D 迁移来的那层边框）
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var vb := VBoxContainer.new()
	vb.name = "VBox"
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	# Ready：醒目 accent 底 + 大尺寸（3D 板上尺寸即世界尺寸，越大越好点/越明显）
	var ready := Button.new()
	ready.name = "ReadyButton"
	ready.text = "Ready"
	ready.custom_minimum_size = Vector2(340.0, 96.0)
	ready.add_theme_font_size_override("font_size", 32)
	ready.add_theme_color_override("font_color", Color(0.08, 0.09, 0.12))
	ready.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var acc := UITheme.color("accent")
	var bstyle := StyleBoxFlat.new()
	bstyle.bg_color = acc
	bstyle.set_corner_radius_all(12)
	bstyle.set_content_margin_all(12)
	bstyle.border_color = acc.darkened(0.25)
	bstyle.set_border_width_all(2)
	ready.add_theme_stylebox_override("normal", bstyle)
	# hover：明显变亮 + 白边，反馈更强（3D 准星悬停同一 hover 态）
	var bhover: StyleBoxFlat = bstyle.duplicate()
	bhover.bg_color = acc.lightened(0.35)
	bhover.border_color = Color(1, 1, 1, 0.85)
	bhover.set_border_width_all(3)
	ready.add_theme_stylebox_override("hover", bhover)
	var bdown: StyleBoxFlat = bstyle.duplicate()
	bdown.bg_color = acc.darkened(0.15)
	ready.add_theme_stylebox_override("pressed", bdown)
	var boff: StyleBoxFlat = bstyle.duplicate()
	boff.bg_color = UITheme.color("bg_elevated")
	boff.border_color = UITheme.color("text_muted")
	ready.add_theme_stylebox_override("disabled", boff)
	ready.pressed.connect(_on_hint_ready)
	vb.add_child(ready)
	# 条件动作按钮（Q 交换/不交换、变换 Joker）统一放提示文本下方（与 2D HintArea/HintActions 一致）
	var acts := HBoxContainer.new()
	acts.name = "HintActions"
	acts.add_theme_constant_override("separation", 16)
	acts.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(acts)
	return panel

func _on_hint_ready() -> void:
	game_view._ready_clicked = true
	GameState.request_initial_ready()

## 刷新提示板：文本 + Ready 可见性/状态；随后按内容重算尺寸。LOBBY 隐藏。
func _refresh_hint_panel() -> void:
	if _hint_panel == null or not is_instance_valid(_hint_panel):
		return
	var phase := int(latest_state.get("phase", PHASE_LOBBY))
	if phase == PHASE_LOBBY:
		if hint3d != null and is_instance_valid(hint3d):
			hint3d.visible = false
		return
	var viewer := int(latest_state.get("viewer_id", 0))
	var current := int(latest_state.get("current_player", -1))
	_update_hint_hud(phase, viewer, current)
	var ready: Button = _hint_panel.get_node_or_null("VBox/ReadyButton")
	if ready != null:
		ready.visible = phase == PHASE_INITIAL_PEEK
		ready.text = ActionModel.ready_text(latest_state, game_view._ready_clicked)
		ready.disabled = not ActionModel.ready_enabled(latest_state, game_view._ready_clicked)
	# 条件动作按钮（Q 交换/不交换、变换 Joker）重建：紧贴提示文本下方
	var acts: HBoxContainer = _hint_panel.get_node_or_null("VBox/HintActions")
	var has_actions := false
	if acts != null:
		for child in acts.get_children():
			acts.remove_child(child)
			child.queue_free()
		for entry in ActionModel.conditional_actions(latest_state, _interaction_ctx()):
			has_actions = true
			var act_btn := _decision_button(str(entry.get("text", "")))
			act_btn.disabled = not bool(entry.get("enabled", true))
			act_btn.pressed.connect(_on_action.bind(str(entry.get("action", ""))))
			acts.add_child(act_btn)
	# 提示板只承载 Ready / 条件动作按钮：无按钮时隐藏，避免遗留空面板浮在牌桌上
	if hint3d != null and is_instance_valid(hint3d):
		var has_buttons := (ready != null and ready.visible) or has_actions
		hint3d.visible = has_buttons
		if has_buttons:
			hint3d.wrap_to_content()

## 准星射线命中哪块看板（模态板 / 提示板）→ {host, coord}；未命中 {}。
func _board_hit() -> Dictionary:
	if table3d == null or not is_instance_valid(table3d):
		return {}
	var cam: Camera3D = table3d.camera.camera_node()
	for host in [board3d, hint3d]:
		if host != null and is_instance_valid(host) and host.visible:
			var c: Vector2i = host.hit_viewport_coord(cam)
			if c.x >= 0:
				return {"host": host, "coord": c}
	return {}

## 更新两块看板内 hover：命中板推送 motion，其余推 motion_out；返回是否命中任一板。
func _update_board_hover() -> bool:
	var hit := _board_hit()
	for host in [board3d, hint3d]:
		if host == null or not is_instance_valid(host):
			continue
		if not hit.is_empty() and hit.host == host:
			host.push_motion(hit.coord)
		else:
			host.push_motion_out()
	return not hit.is_empty()

## 3D 只读预览开关（仅对局中可用）。激活时隐藏 2D 棋盘（含 background，
## 否则 CanvasItem 会盖住 3D）并捕获鼠标；退出时恢复并重绘 2D。
func _set_table3d(on: bool) -> void:
	if on and (latest_state.is_empty() or int(latest_state.get("phase", PHASE_LOBBY)) == PHASE_LOBBY):
		return
	_table3d_active = on
	if on:
		if table3d == null or not is_instance_valid(table3d):
			table3d = load("res://scenes/ui/table3d.tscn").instantiate()
			table3d.name = "Table3D"
			add_child(table3d)
			move_child(table3d, 0)
		table3d.set_active(true)
		if _crosshair == null or not is_instance_valid(_crosshair):
			_crosshair = Crosshair.new()
			_crosshair.name = "Crosshair"
			_crosshair.z_index = 80
			add_child(_crosshair)
		_ensure_board()
		table3d.set_hud_buttons(_hud_buttons())
		table3d.render(latest_state, interaction.card_actionable)
		_place_boards()
		_sync_table3d_pointer()
		_ensure_hint_hud()
		_hint_hud.show_hud(true)
		_refresh_hint_panel()
		_ensure_self_panel()
		_self_panel.visible = true
		_update_self_panel()
		_ensure_key_hints()
		_key_hints.visible = true
		_ensure_round_badge()
		_round_badge.visible = true
		background.visible = false
		game_panel.visible = false
	else:
		_close_manual()
		if table3d != null and is_instance_valid(table3d):
			table3d.clear_hover()
			table3d.set_active(false)
			table3d.camera.reset_zoom()
		if _crosshair != null and is_instance_valid(_crosshair):
			_crosshair.visible = false
			_crosshair.set_active(false)
		if _self_panel != null and is_instance_valid(_self_panel):
			_self_panel.visible = false
		if _key_hints != null and is_instance_valid(_key_hints):
			_key_hints.visible = false
		if _round_badge != null and is_instance_valid(_round_badge):
			_round_badge.visible = false
		if _hint_hud != null and is_instance_valid(_hint_hud):
			_hint_hud.show_hud(false)
		if _slap_burst != null and is_instance_valid(_slap_burst):
			_slap_burst.queue_free()
			_slap_burst = null
		_q_hidden_held = false
		if board3d != null and is_instance_valid(board3d):
			for c in board3d.detach_all():
				if c != null and is_instance_valid(c):
					add_child(c)
		background.visible = true
		game_panel.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_render_game()

## 3D 预览的输入走 _input（早于 GUI 路由，保证鼠标移动/退出键必定到达，
## 不受任何 Control 的 mouse_filter 影响）。
func _input(event: InputEvent) -> void:
	if not _table3d_active:
		return
	var board_panel := _board_has_panel()
	# 按住 Command/Alt：拉近视场（放大）；松开恢复。不标记 handled，避免影响其他快捷键。
	if event is InputEventKey and not event.echo and (event.keycode == KEY_META or event.keycode == KEY_ALT):
		if table3d != null and is_instance_valid(table3d):
			table3d.camera.set_zoom(event.pressed)
	if event is InputEventKey and event.pressed and not event.echo:
		# F10/V 任何时候都可切回 2D（含看板面板打开时；面板会被重挂回 2D）。
		if event.keycode == KEY_F10 or event.keycode == KEY_V:
			_set_table3d(false)
			get_viewport().set_input_as_handled()
			return
		# Tab：开/关手册（3D 全息看板）
		if event.keycode == KEY_TAB:
			_toggle_manual()
			get_viewport().set_input_as_handled()
			return
		# M：切换说话（嘴开合，同步给其他玩家看你的角色）
		if event.keycode == KEY_M:
			_talking_local = not _talking_local
			get_viewport().set_input_as_handled()
			return
		# 手册打开时 Esc 先关手册（优先于退出 3D）
		if event.keycode == KEY_ESCAPE and manual_panel != null and is_instance_valid(manual_panel):
			_close_manual()
			get_viewport().set_input_as_handled()
			return
		# 有看板面板时，Enter/Esc 交给面板（Joker/商店）；否则 Esc 退出 3D。
		if board_panel and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_ESCAPE):
			if board3d != null and is_instance_valid(board3d):
				board3d.push_key(event)
			get_viewport().set_input_as_handled()
			return
		if not board_panel and event.keycode == KEY_ESCAPE:
			_set_table3d(false)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		if table3d != null and is_instance_valid(table3d):
			table3d.camera.look(event.relative)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_table3d_click()
		get_viewport().set_input_as_handled()

## 3D 悬停指示：每帧按准星命中更新目标高亮与准星状态。
func _process(delta: float) -> void:
	if not _table3d_active:
		return
	if table3d == null or not is_instance_valid(table3d):
		return
	_place_boards()
	_auto_aim_board()
	var cam: Camera3D = table3d.camera.camera_node()
	if board3d != null and is_instance_valid(board3d):
		board3d.set_facing(cam)
	if hint3d != null and is_instance_valid(hint3d):
		hint3d.set_facing(cam)
	table3d.update_facing()
	_update_look_send(delta, cam)
	table3d.update_avatars(cam, GameState.remote_looks, GameState.remote_zoom, bool(table3d.camera.zoomed), GameState.remote_talk, _talking_local)
	var on_board := _update_board_hover()
	if _board_has_panel():
		table3d.clear_hover()
		if _crosshair != null and is_instance_valid(_crosshair):
			_crosshair.set_active(on_board)
		return
	if on_board:
		table3d.clear_hover()
		if _crosshair != null and is_instance_valid(_crosshair):
			_crosshair.set_active(true)
		return
	var on_target: bool = table3d.update_hover()
	if _crosshair != null and is_instance_valid(_crosshair):
		_crosshair.set_active(on_target)

## 3D 下按固定频率把本机相机注视方向上报服务器（转发给其他玩家），
## 使每席机器人眼睛跟随其“主人”自己的鼠标/相机（而非本机）。方向无变化则不发送。
func _update_look_send(delta: float, cam: Camera3D) -> void:
	if cam == null:
		return
	_look_send_timer += delta
	if _look_send_timer < LOOK_SEND_INTERVAL:
		return
	_look_send_timer = 0.0
	var dir := -cam.global_transform.basis.z
	if dir.length_squared() < 0.000001:
		return
	dir = dir.normalized()
	var zoomed := bool(table3d.camera.zoomed)
	var talking := _talking_local
	var dir_changed := _last_look_dir == Vector3.ZERO or _last_look_dir.dot(dir) <= LOOK_SEND_EPS_DOT
	if not dir_changed and zoomed == _last_look_zoom and talking == _last_look_talk:
		return
	_last_look_dir = dir
	_last_look_zoom = zoomed
	_last_look_talk = talking
	var seat := int(latest_state.get("viewer_id", -1))
	if seat < 0:
		return
	var target := cam.global_position + dir * LOOK_TARGET_DISTANCE
	if multiplayer.is_server():
		GameState._apply_look(seat, target, zoomed, talking)
	else:
		GameState.server_look.rpc_id(1, target, zoomed, talking)

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
const PHASE_SHOP := 10

## HintHud 胶囊显示 + 倒计时重置的阶段（与 HintHud.ACTIVE_PHASES 一致）。
## 不含 INITIAL_PEEK：进入房间直到全员 ready 后才开始计时。
const _HUD_ACTIVE_PHASES := [PHASE_TURN_DRAW, PHASE_TURN_DECISION, PHASE_Q_DECISION, PHASE_SLAP_EXCHANGE, PHASE_SLAP_DUEL]

const CORNER_MARGIN := 75.0     # 3D 四个角 HUD 到屏幕边缘的统一边距（目标=屏幕像素）
const BOARD_DIST := 3.0        # 回退用：看板沿"相机→桌心"连线距相机的距离（无座位锚点时）
## 模态看板锚点（贴玩家、不靠后）：本机座位→桌心的 0..1 深度（用户 0-10 标度的 2/10）。
const BOARD_DEPTH := 0.2
const BOARD_TABLE_HALF := 3.8  # 牌桌半宽（scenes/ui/table3d.tscn 桌面 7.6）
const BOARD_FLOAT_H := 2.1     # 看板底部距桌面的悬浮高度（抬高，避免贴桌面）

const PEEK_GLOW_COLOR := Color("3ef0f7ff")  # 查看牌蓝色光晕
const PEEK_GLOW_DURATION := 1.5
const PEEK_GLOW_SIZE := 14
const LOOK_SEND_INTERVAL := 1.0 / 12.0   # 注视方向上报间隔（秒）
const LOOK_SEND_EPS_DOT := 0.999         # 方向变化小于该阈值（≈2.6°）不重复发送
const LOOK_TARGET_DISTANCE := 12.0       # 相机射线固定距离生成"世界注视点"（gaze target）
const SLAP_CORRECT_GLOW := Color("87d9a1")  # 贴对绿色炫光（同 UITheme success）
const SLAP_WRONG_GLOW := Color("ff7b7b")  # 贴错红色炫光（同 UITheme danger）
const SLAP_GLOW_SIZE := 14
const DuelBarScript := preload("res://scripts/ui/duel_bar.gd")
const SettingsMenuScript := preload("res://scripts/ui/settings_menu.gd")
const SettlementPageScript := preload("res://scenes/ui/settlement_page.tscn")
const ShopPanelScript := preload("res://scenes/ui/shop_panel.tscn")
const JokerTransformPanelScript := preload("res://scenes/ui/joker_transform_panel.tscn")
const ManualPanelScript := preload("res://scenes/ui/manual_panel.tscn")

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
var board3d: Board3d = null
var hint3d: Board3d = null
var _hint_panel: Control = null
var table3d: Node3D = null
var _table3d_active := false
var _look_send_timer := 0.0
var _last_look_dir := Vector3.ZERO
var _last_look_zoom := false
var _last_look_talk := false
var _talking_local := false
var _crosshair: Control = null
var _self_panel: PlayerStatPanel = null
var is_dev_join := false
var start_button: Button = null
var close_room_button: Button = null
var leave_room_button: Button = null
var match_limit_spin: SpinBox = null
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
var _slap_burst: Control = null
var _board_aim_key := ""
var settings_menu: Control = null
var _my_token := ""
var _rejoin_addr := ""
var _rejoin_port := KongNetwork.DEFAULT_PORT
var _was_in_match := false
var _reconnect_panel: Control = null
var _reconnect_expected := false
var settlement_page: Control = null
var shop_panel: Control = null
var joker_panel: Control = null
var manual_panel: Control = null
var _key_hints: KeyHintPanel = null
var _round_badge: Control = null
var _hint_hud: HintHud = null
var _hud_turn_key := ""
var _shop_result_shown := ""
var _pending_winner_sfx := false
# Q 能力：下一次收到的看牌揭示保持正面（不自动翻回），直到玩家确认交换/不交换。
var _hold_next_reveal := false
var _q_hold_active := false
var _q_hidden_held := false   # Q 两张看牌：他人视角闭眼翻转 hold 中（决策结束释放）

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

## 清除 Q 能力的 hold 揭示（2D overlay + 3D 揭示登记）。animate_back=true 播翻回动画
## （2D 副本 / 3D 跨 render 续播），false 立即清除（结算等强制场景）。
func _drop_q_holds(animate_back := false) -> void:
	_hold_next_reveal = false
	_q_hold_active = false
	if reveal != null:
		reveal.release_held_peeks(animate_back)
	if table3d != null and is_instance_valid(table3d):
		table3d.release_held_reveals(animate_back)

## 玩家确认 Q 不交换（或已不在 Q_DECISION）时调用：翻回 hold 的牌（带动画）。
## 交换路径不在此释放——保留正面由交换飞牌 consume（翻回/飞牌衔接见 animate_swap）。
func _release_q_holds(animate_back := true) -> void:
	if not _q_hold_active:
		return
	_drop_q_holds(animate_back)
	if not animate_back:
		_render_game_if_active()

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
	# 2D 走 CardAnimator（原逻辑逐字不动）；3D 走 table3d 的飞牌编排。
	GameState.card_exchange_animated.connect(func(data: Dictionary):
		if _table3d_active:
			if str(data.get("kind", "")) == "slap_resolved":
				_show_slap_success(data)
			if table3d != null and is_instance_valid(table3d):
				table3d.animate_exchange(data)
		else:
			animator.handle_exchange(data))
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
	if _table3d_active:
		_set_table3d(false)
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
	_mount_modal(panel, overlay)
	_reconnect_panel = panel

func _hide_reconnect_panel() -> void:
	if _reconnect_panel != null and is_instance_valid(_reconnect_panel):
		_unmount_modal(_reconnect_panel)
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
	# 3D 下抽牌飞牌由 table3d_view 负责（不置 2D 抽牌标志，避免 2D 副本浮在 3D 画面上）
	if not _table3d_active:
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
	game_panel.visible = not _table3d_active
	# 兜底：离开 Q_DECISION 时翻回 hold 的看牌（请求被拒/异常流转），避免牌永久正面。
	if _q_hold_active and int(state.phase) != PHASE_Q_DECISION:
		_release_q_holds()
	# Q 的两张看牌：其他玩家视角的闭眼占位翻转 hold 到决策结束 → 离开 Q_DECISION 时翻回
	if _q_hidden_held and int(state.phase) != PHASE_Q_DECISION:
		if _table3d_active and table3d != null and is_instance_valid(table3d):
			table3d.release_hidden_reveals()
		_q_hidden_held = false
	if int(state.phase) == PHASE_GAME_OVER:
		# 结算接管棋盘：先清残留动画/挂起状态再渲染，
		# 保证卡牌以真实卡（而非在途揭示的动画占位）出现。
		_clear_settlement_anim_state()
	_render_game()
	dev.refresh_panel()
	if int(state.phase) == PHASE_GAME_OVER:
		_open_settlement()
	else:
		_close_settlement()
	if int(state.phase) == PHASE_SHOP:
		_open_shop_panel()
	else:
		_close_shop_panel()
	# Joker 变换面板只在处理 JOKER 的 TURN_DECISION 时可用，离开即关闭
	if int(state.phase) != PHASE_TURN_DECISION or str(state.get("pending", {}).get("rank", "")) != "JOKER":
		_on_joker_cancel()
	_show_shop_result_toast(state)
	_sync_table3d_pointer()

## 清空上一局可能残留的动画/挂起状态（对局结束时在途的看牌/贴牌揭示）。
func _clear_settlement_anim_state() -> void:
	_anim_slots.clear()
	_pending_slap_penalties.clear()
	_pending_flips.clear()
	_slap_reveal_count = 0
	_slap_reveal_lock = false
	_drop_q_holds()

## 动画完成刷新：对局已进入结算（GAME_OVER，结算页接管棋盘）时跳过重渲染，
## 防止在途揭示动画的延迟 _render_game 把结算翻开的牌翻回背面。
func _render_game_if_active() -> void:
	if int(latest_state.phase) == PHASE_GAME_OVER:
		return
	_render_game()

func _render_game() -> void:
	# 每次渲染前清空卡牌槽位映射：渲染会全量重建，防止上一局残留槽位
	#（如超出手牌数的罚牌槽位）指向已释放节点，致后续动画报 freed instance。
	_card_slots.clear()
	game_view.render(latest_state)
	_render_duel(latest_state)
	# ExtraLayer 附加卡已同步定位，罚牌 fly 可直接取到正确锚点
	_flush_slap_penalties()
	_refresh_table3d()

## 3D 激活时把最新状态 + 本地交互态（interaction.action_mode）投影到 3D：
## 渲染卡牌（含可操作高亮）/ HUD / 自身面板 / 提示板。
## 集中在此，保证**本地** action_mode 变化（用能力、J 两段交换）也能即时刷新 3D 提示与高亮——
## 过去只在 _on_state_updated（服务器广播）刷新，导致 3D 提示/高亮停留旧态，切 2D 再回才更新。
func _refresh_table3d() -> void:
	if not _table3d_active or table3d == null or not is_instance_valid(table3d):
		return
	table3d.render(latest_state, interaction.card_actionable)
	table3d.set_hud_buttons(_hud_buttons())
	_update_self_panel()
	_update_round_badge()
	_refresh_hint_panel()

## 罚牌 fly：事件到达时目标槽位可能尚未渲染（追加的第 5+ 张），render 后再补飞。
func _flush_slap_penalties() -> void:
	if _table3d_active or _pending_slap_penalties.is_empty():
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
			_mount_modal(_duel_panel, overlay)
			_duel_panel.setup(self, duel, _on_slap_duel_stop, not _table3d_active)
	else:
		if _duel_panel != null:
			_unmount_modal(_duel_panel)
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
	# 结算模型只纳入存活者：出局玩家 0 张 0 分，混入会恒排第一。
	var alive_players: Array = latest_state.players.filter(func(p: Dictionary) -> bool: return not bool(p.get("eliminated", false)))
	var model: Dictionary = SettlementModel.build(alive_players)
	var page := SettlementPageScript.instantiate()
	page.name = "SettlementPage"
	# 直接挂 main 末尾 + z_index（仿 settings_menu 已验证模式）：main 子节点逆序 pick，
	# 末位子节点优先于棋盘（margin）接收点击；overlay 是 IGNORE，挂它下面会被 4.6 的
	# get_mouse_filter_with_override 判定为整棵子树不可点。
	page.z_index = 100
	_mount_modal(page)
	var run: Dictionary = latest_state.get("run", {})
	var match_limit: int = int(run.get("match_limit", KongRules.DEFAULT_MATCH_LIMIT))
	var series: Dictionary = (latest_state.get("result", {}) as Dictionary).get("series", {})
	var rewards: Dictionary = (latest_state.get("result", {}) as Dictionary).get("rewards", {})
	page.setup(model, Network.is_host, int(latest_state.get("match_number", 1)),
		_play_pending_winner, _request_next_match, GameState.request_abort_match,
		_on_settlement_flip, true, match_limit, series, rewards)
	settlement_page = page

## 结算联动：每轮翻牌时刻把对应棋盘卡牌从背面翻到正面（与结算页行内记分同步）。
func _on_settlement_flip(seat: int, slot: int, card: Dictionary) -> void:
	if not _card_slots.has(seat) or not _card_slots[seat].has(slot):
		return
	var card_node: Control = _card_slots[seat][slot]
	if is_instance_valid(card_node) and card_node is CardView:
		(card_node as CardView).flip_reveal(card)

## 关闭结算弹层（收到新局/中止时调用）。
func _close_settlement() -> void:
	if settlement_page != null and is_instance_valid(settlement_page):
		_unmount_modal(settlement_page)
		settlement_page.queue_free()
	settlement_page = null

## SHOP 阶段打开/刷新商店面板（已存在则刷新内容，反映购买/售出/完成状态）。
func _open_shop_panel() -> void:
	if shop_panel != null and is_instance_valid(shop_panel):
		shop_panel.setup(latest_state, _on_shop_buy, _on_shop_skip, not _table3d_active)
		return
	var panel := ShopPanelScript.instantiate()
	panel.name = "ShopPanel"
	panel.z_index = 90
	_mount_modal(panel)
	panel.setup(latest_state, _on_shop_buy, _on_shop_skip, not _table3d_active)
	shop_panel = panel

func _close_shop_panel() -> void:
	if shop_panel != null and is_instance_valid(shop_panel):
		_unmount_modal(shop_panel)
		shop_panel.queue_free()
	shop_panel = null

func _on_shop_buy(offer: int) -> void:
	GameState.request_shop_buy(offer, _next_action_id())

func _on_shop_skip() -> void:
	GameState.request_shop_skip(_next_action_id())

## Joker 变换面板：打开（幂等，场景实体，选点数/花色/确认/取消）。
func _open_joker_transform_panel() -> void:
	if joker_panel != null and is_instance_valid(joker_panel):
		return
	var panel := JokerTransformPanelScript.instantiate()
	panel.name = "JokerTransformPanel"
	panel.z_index = 95
	_mount_modal(panel)
	panel.setup(_on_joker_confirm, _on_joker_cancel)
	joker_panel = panel

func _on_joker_cancel() -> void:
	if joker_panel != null and is_instance_valid(joker_panel):
		_unmount_modal(joker_panel)
		joker_panel.queue_free()
	joker_panel = null

func _on_joker_confirm(rank: String, suit: String) -> void:
	GameState.request_joker_transform(rank, suit, _next_action_id())
	_on_joker_cancel()

## 手册：Tab 开/关（3D 全息看板，弹在面前；三列 牌/能力/分数）。
func _toggle_manual() -> void:
	if manual_panel != null and is_instance_valid(manual_panel):
		_close_manual()
	else:
		_open_manual()

func _open_manual() -> void:
	if manual_panel != null and is_instance_valid(manual_panel):
		return
	var panel := ManualPanelScript.instantiate()
	panel.name = "ManualPanel"
	panel.z_index = 92
	_mount_modal(panel)
	manual_panel = panel

func _close_manual() -> void:
	if manual_panel != null and is_instance_valid(manual_panel):
		# 无论是否仍处于 3D 都先从看板卸下（退出 3D 时 board3d.detach_all 不该再看到它）
		if board3d != null and is_instance_valid(board3d) and manual_panel.get_parent() == board3d.viewport():
			board3d.unmount_panel(manual_panel)
		manual_panel.queue_free()
	manual_panel = null

## 商店裁决结果一次性 toast（每个 shop_result 只提示一次）。
func _show_shop_result_toast(state: Dictionary) -> void:
	var result: Dictionary = state.get("shop_result", {})
	if result.is_empty():
		return
	var key: String = JSON.stringify(result)
	if key == _shop_result_shown:
		return
	_shop_result_shown = key
	var parts: Array = []
	for offer_idx in result:
		var r: Dictionary = result[offer_idx]
		var name := ""
		for p in state.players:
			if int(p.id) == int(r.winner):
				name = str(p.name)
				break
		parts.append("%s 以 %d 购买了 %s" % [name, int(r.amount), str(r.name)])
	_show_toast("商店：%s" % "　".join(parts))

## 冠军时刻：若服务器已广播过 winner 音效事件，此刻播放（延迟到冠军出场）。
func _play_pending_winner() -> void:
	if _pending_winner_sfx:
		AudioManager.play_winner()
		_pending_winner_sfx = false

## 结算页「再来一局」→ 服务器开新局。
func _request_next_match() -> void:
	GameState.request_next_match(_next_action_id())

## 开发者工具：房主直接判某玩家出局（服务器以房主身份校验）。
func _dev_eliminate(seat: int) -> void:
	GameState.request_dev_eliminate(seat)

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
		_render_game_if_active()
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
			reveal._flip_at(_card_slots[target_id][slot], entry.card, target_id, slot, entry.has("correct"), bool(entry.get("correct", false)), bool(entry.get("hold", false)))
		else:
			remaining.append(entry)
	_pending_flips = remaining

func _on_pending_action() -> void:
	var pending: Dictionary = latest_state.get("pending", {})
	var actor := int(latest_state.get("viewer_id", 0))
	var big_data: Dictionary = pending.duplicate()
	big_data.erase("source")
	# 隐藏棋盘大牌，播副本动画飞向弃牌堆（落位后弃牌堆显示，大牌不重建）；3D 下无 2D fly
	if not _table3d_active:
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
	return HintText.hint(latest_state, phase, is_current, interaction.action_mode)

func _mode_instruction(fallback: String) -> String:
	return interaction.mode_instruction(fallback)

func _show_private_reveal(title: String, revealed_cards: Array, target: Dictionary = {}) -> void:
	# Q 能力的两张揭示（对方牌 + 自己牌）保持正面，直到玩家确认交换/不交换。
	var hold := _hold_next_reveal
	_hold_next_reveal = false
	if hold:
		_q_hold_active = true
	if _table3d_active and target.has("slot") and table3d != null and is_instance_valid(table3d):
		var seat := int(target.get("player_id", 0))
		var slot := int(target.get("slot", -1))
		var color := Color(0, 0, 0, 0)
		if target.has("correct"):
			color = SLAP_CORRECT_GLOW if bool(target.get("correct", false)) else SLAP_WRONG_GLOW
		else:
			color = PEEK_GLOW_COLOR
		for card in revealed_cards:
			if hold:
				table3d.reveal_slot_held(seat, slot, card, color)
			else:
				table3d.reveal_slot(seat, slot, card, color, PEEK_GLOW_DURATION)
		return
	reveal.show_private_reveal(title, revealed_cards, target, hold)

## 其他玩家查看某张牌时，在被查看的牌上标蓝色光晕 1 秒（不含牌面）。
## 记录槽位到 _peek_glow_slots，render 重建卡牌后仍可恢复光晕。
## 贴牌成功爆炸弹层（仅 3D）：屏幕空间齿状爆炸 + 卡面 + 「贴牌成功」 + 贴中者名字。
func _show_slap_success(data: Dictionary) -> void:
	if _slap_burst != null and is_instance_valid(_slap_burst):
		_slap_burst.queue_free()
		_slap_burst = null
	var actor := int(data.get("actor", -1))
	var player_name := ""
	for p in latest_state.get("players", []):
		if int(p.id) == actor:
			player_name = str(p.get("name", ""))
			break
	var burst := SlapSuccessBurst.new()
	burst.name = "SlapSuccessBurst"
	burst.z_index = 90
	add_child(burst)
	_slap_burst = burst
	burst.setup(data.get("card", {}), player_name)

func _on_peek_highlight(data: Dictionary) -> void:
	if _table3d_active and table3d != null and is_instance_valid(table3d):
		# 3D：翻到"黑底闭眼"占位面 + 蓝光（比单纯蓝光更明显），到时翻回；Q 的两张 hold 到决策。
		var hold := bool(data.get("hold", false))
		if hold:
			_q_hidden_held = true
		table3d.reveal_hidden_slot(int(data.get("player_id", 0)), int(data.get("slot", -1)), PEEK_GLOW_COLOR, PEEK_GLOW_DURATION, hold)
		return
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

## 决策按钮（Q/J 的 交换·不交换 等条件动作）：更大更好点，hover 变亮色 accent 明显反馈。
## 2D `HintActions` 与 3D 提示板 `HintActions` 共用（3D 板上尺寸即世界尺寸，放大也更易用准星点到）。
const DECISION_BTN_MIN := Vector2(210.0, 58.0)
func _decision_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = DECISION_BTN_MIN
	b.add_theme_font_size_override("font_size", 24)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var acc := UITheme.color("accent")
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.color("bg_elevated")
	normal.set_corner_radius_all(12)
	normal.set_content_margin_all(12)
	normal.border_color = UITheme.color("border_strong")
	normal.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_color_override("font_color", UITheme.color("text_primary"))
	# hover：整块变亮 accent + 深色字，反馈强烈（3D 准星悬停也走同一 hover 态）
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = acc.lightened(0.08)
	hover.border_color = acc.lightened(0.35)
	hover.set_border_width_all(3)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_color_override("font_hover_color", Color(0.06, 0.08, 0.12))
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = acc.darkened(0.12)
	pressed.border_color = acc
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_pressed_color", Color(0.06, 0.08, 0.12))
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = UITheme.color("bg_elevated")
	disabled.border_color = UITheme.color("text_muted")
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_color_override("font_disabled_color", UITheme.color("text_muted"))
	return b

func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
