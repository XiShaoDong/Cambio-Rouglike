class_name TutorialView
extends Control
## 3D 教学局（正式对局操作）：鼠标捕获 + 中心准星；本地时间线，不接网络/GameState。

signal closed
signal completed

const TABLE3D_SCENE := "res://scenes/ui/table3d.tscn"
const SETTLEMENT_SCENE := "res://scenes/ui/settlement_page.tscn"
const MANUAL_SCENE := "res://scenes/ui/manual_panel.tscn"
const SLAP_SECONDS := TutorialOverlay.SLAP_SECONDS
const ANIMALESE_SCRIPT := preload("res://scripts/tutorial/animalese_voice.gd")
const POINTER_SCRIPT := preload("res://scripts/tutorial/tutorial_pointer.gd")

var controller := TutorialController.new()
var skip_requested := false
## 测试用：自动步骤不等待动画，直接落到结束状态。
var instant_auto := false

var _table3d: Node3D
var _overlay: TutorialOverlay
var _pointer: Control
var _animalese: Node
var _tooltip: CardTooltip
var _order_panel: CardOrderPanel
var _manual: Control
var _manual_open := false
var _known_cards: Dictionary = {}
var _peek_flipped := false
var _sequence_busy := false
var _crosshair: Crosshair
var _settlement: Control
var _paused := false
var _line_index := 0
var _step_token := 0
var _slap_running := false
var _slap_left := 0.0
var _slap_last_int := -1
var _slap_token := 0
var _slap_total := SLAP_SECONDS
var _race_mode := false
var _race_token := 0
var _race_locked := false
var _talk_token := 0
var _interact_lock := 0.0
var _completed_emitted := false
var _current_state: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table3d = load(TABLE3D_SCENE).instantiate()
	_table3d.name = "Table3D"
	_table3d.hover_amp = 1.0
	add_child(_table3d)
	_table3d.set_active(true)
	# 主菜单里可能还留着上一局的 Table3D 相机；教程必须接管当前视口，
	# 否则会从旧相机视角渲染，桌面看起来"出现在别的位置"。
	if _table3d.camera != null:
		_table3d.camera.camera_node().make_current()
	_overlay = TutorialOverlay.new()
	_overlay.name = "Overlay"
	_overlay.z_index = 200
	_overlay.resume_pressed.connect(func(): _set_paused(false))
	_overlay.restart_pressed.connect(_restart)
	_overlay.skip_step_pressed.connect(_skip_step)
	_overlay.skip_all_pressed.connect(finish_skip)
	_overlay.exit_pressed.connect(finish_skip)
	_overlay.summary_done_pressed.connect(finish_skip)
	add_child(_overlay)
	_animalese = ANIMALESE_SCRIPT.new()
	_animalese.name = "Animalese"
	add_child(_animalese)
	_pointer = POINTER_SCRIPT.new()
	_pointer.name = "Pointer"
	add_child(_pointer)
	_tooltip = CardTooltip.new()
	_tooltip.name = "CardTooltip"
	_tooltip.z_index = 190
	add_child(_tooltip)
	_tooltip.hide_tip()
	_order_panel = CardOrderPanel.new()
	_order_panel.name = "CardOrder"
	_order_panel.z_index = 150
	add_child(_order_panel)
	_order_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_order_panel.offset_left = -340
	_order_panel.offset_right = -24
	_order_panel.offset_top = 90
	_order_panel.offset_bottom = 260
	_manual = load(MANUAL_SCENE).instantiate()
	_manual.name = "TutorialManual"
	_manual.z_index = 230
	_manual.visible = false
	add_child(_manual)
	for path in ["Center/Panel/VBox/Tabs/TabStats", "Center/Panel/VBox/Tabs/TabKeys",
			"Center/Panel/VBox/Tabs/TabHintLeft", "Center/Panel/VBox/Tabs/TabHintRight"]:
		var n = _manual.get_node_or_null(path)
		if n != null:
			n.visible = false
	var mhint = _manual.get_node_or_null("Center/Panel/VBox/Hint")
	if mhint != null:
		mhint.text = "Tab 关闭"
	_manual.set_tab(ManualPanel.TAB_MANUAL)
	_overlay.ready_pressed.connect(_on_ready_pressed)
	_crosshair = Crosshair.new()
	_crosshair.name = "Crosshair"
	_crosshair.z_index = 210
	add_child(_crosshair)
	_set_paused(false)
	_enter_step(true)


func _exit_tree() -> void:
	_stop_talk()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _input(event: InputEvent) -> void:
	if _sequence_busy:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB and not _paused and not controller.is_summary():
			_toggle_manual(not _manual_open)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_SHIFT and not _manual_open and not _paused \
				and not controller.is_summary():
			if _order_panel != null:
				_order_panel.toggle()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			if _manual_open:
				_toggle_manual(false)
			elif not controller.is_summary():
				if not _paused and controller.is_auto():
					_overlay.show_toast("演示中，请稍候…")
				else:
					_set_paused(not _paused)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			if not _paused and not controller.is_summary() and not _manual_open:
				if controller.mode() == "peek":
					if _peek_flipped:
						_on_ready_pressed()
					else:
						_peek_flip()
				else:
					handle_continue()
				get_viewport().set_input_as_handled()
			return
	if _manual_open or _paused or controller.is_summary():
		return
	if controller.mode() == "peek":
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _overlay.is_over_ready(get_viewport().get_mouse_position()):
				return  # 让 Ready 按钮自己处理
			_peek_flip()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if _table3d != null and _table3d.camera != null:
			_table3d.camera.look(event.relative)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if controller.is_talk():
			handle_continue()
		else:
			_click_center()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _table3d == null or _table3d.camera == null:
		return
	if _manual_open or _paused or controller.is_summary():
		_crosshair.visible = false
		if _pointer != null:
			_pointer.hide_target()
		if _tooltip != null:
			_tooltip.hide_tip()
		return
	var cam: Camera3D = _table3d.camera.camera_node()
	if cam != null:
		var robot = _opponent_robot()
		if robot != null and robot.has_method("set_gaze_target_world"):
			robot.set_gaze_target_world(cam.global_position)
	_table3d.update_facing(int(_current_state.get("current_player", -1)))
	if controller.mode() == "peek":
		_crosshair.visible = false
		_update_pointer()
		if _tooltip != null:
			_tooltip.hide_tip()
		return
	_crosshair.visible = true
	var hit: bool = _table3d.update_hover(controller.is_interact())
	_crosshair.set_active(hit)
	_update_pointer()
	_update_card_tooltip(cam)
	if _interact_lock > 0.0:
		_interact_lock = maxf(_interact_lock - delta, 0.0)
	if _slap_running:
		_tick_slap(delta)


func handle_continue() -> void:
	if _paused or _sequence_busy:
		return
	if not controller.is_talk():
		return
	var lines := TutorialText.lines(controller.step_id())
	if _line_index + 1 < lines.size():
		_line_index += 1
		_show_line()
		return
	if controller.advance():
		_enter_step(false)


func handle_pick(meta: Dictionary) -> void:
	if _paused or _sequence_busy or controller.is_summary() or not controller.is_interact():
		return
	if _interact_lock > 0.0:
		return
	if controller.step_id() == "slap_prompt" and (not _slap_running or _race_locked):
		return
	var r: Dictionary = controller.pick(meta)
	if not bool(r.get("ok", false)):
		var msg := str(r.get("message", ""))
		if not msg.is_empty():
			_overlay.show_toast(msg)
		return
	var effect := str(r.get("effect", ""))
	if effect == "replace":
		_known_cards["0_3"] = TutorialSteps.card_by_id("p6")
	if effect == "slap" or effect == "slap_other":
		_play_slap_sequence(effect, int(r.get("slot", -1)))
		return
	_play_effect(effect, int(r.get("slot", -1)))
	_enter_step(false)
	if effect == "draw" and not instant_auto:
		_interact_lock = 0.45


func finish_skip() -> void:
	skip_requested = true
	closed.emit()


func _click_center() -> void:
	if _table3d == null or _table3d.camera == null:
		return
	var center := get_viewport().get_visible_rect().size * 0.5
	var meta := Table3dPicker.pick(_table3d.camera.camera_node(), _table3d.get_world_3d(), center)
	handle_pick(meta)


func _enter_step(first := false) -> void:
	if controller.is_done():
		return
	_step_token += 1
	var token := _step_token
	var id := controller.step_id()
	_line_index = 0
	_interact_lock = 0.0
	_stop_slap()
	_current_state = controller.state().duplicate(true)
	if first:
		AudioManager.play_deal_shuffle()
	_render_state(_current_state, _actionable_for_step(id), id == "part2_replace")
	_update_overlay(id)
	_show_step_line(id)
	if controller.mode() == "peek":
		_enter_peek(id)
		return
	_overlay.show_ready(false)
	if _manual_open:
		_toggle_manual(false)
	if not _paused and not controller.is_summary():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_crosshair.visible = true
	var slap_mode := controller.slap_mode()
	if slap_mode == "race":
		_start_race()
	elif slap_mode == "explain":
		_overlay.set_slap("explain")
	match controller.mode():
		"auto":
			_run_auto(id, token)
		"summary":
			_show_summary()


func _render_state(state: Dictionary, actionable := Callable(), ability_pending := false) -> void:
	if _table3d == null:
		return
	_table3d.update_facing(int(state.get("current_player", -1)))
	_table3d.render(state, actionable, ability_pending)


func _play_wrong_slap(slot: int) -> void:
	if instant_auto or _current_state.is_empty():
		return
	var players: Array = _current_state.get("players", [])
	if players.size() < 2:
		return
	var slots: Array = players[1].get("slots", [])
	if slot < 0 or slot >= slots.size():
		return
	var cid := str((slots[slot] as Dictionary).get("card_id", ""))
	_table3d.reveal_slot(TutorialSteps.OPPONENT, slot, TutorialSteps.card_by_id(cid),
		Color(1.0, 0.35, 0.35, 1.0), 2.4)
	AudioManager.play_slap_fail()
	_overlay.show_toast("贴牌错误：手牌与弃牌堆点数不一致")


func _enter_peek(id: String) -> void:
	_peek_flipped = false
	_known_cards.clear()
	_table3d.release_held_reveals(false)
	_overlay.show_ready(true)
	_overlay.set_task(TutorialText.task(id))
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_crosshair.visible = false
	if _tooltip != null:
		_tooltip.hide_tip()


func _peek_flip() -> void:
	if _peek_flipped:
		return
	_peek_flipped = true
	var two := TutorialSteps.card_by_id("p2")
	var ten := TutorialSteps.card_by_id("p3")
	_table3d.reveal_slot_held(TutorialSteps.PLAYER, 2, two)
	_table3d.reveal_slot_held(TutorialSteps.PLAYER, 3, ten)
	_known_cards["0_2"] = two
	_known_cards["0_3"] = ten
	_overlay.set_speech(TutorialText.SPEAKER, "记好了，就点击 Ready 吧。", false)
	_overlay.set_task("记好了就点击 Ready")
	AudioManager.play_flip()


func _on_ready_pressed() -> void:
	if controller.mode() != "peek":
		return
	if not _peek_flipped:
		_overlay.flash_ready_warning()
		return
	_table3d.release_held_reveals(true)
	_overlay.show_ready(false)
	_crosshair.visible = true
	if controller.advance():
		_enter_step(false)


func _toggle_manual(on: bool) -> void:
	_manual_open = on
	if _manual != null:
		_manual.visible = on
	if on:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_crosshair.visible = false
		if _pointer != null:
			_pointer.hide_target()
		if _tooltip != null:
			_tooltip.hide_tip()
		return
	if controller.mode() == "peek":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_crosshair.visible = false
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_crosshair.visible = true


func _update_card_tooltip(cam: Camera3D) -> void:
	if _tooltip == null or cam == null:
		return
	var pick: Dictionary = _table3d.hovered_pick()
	var kind := str(pick.get("kind", ""))
	# 只显示公开/真实已知的牌；手牌槽位（背面）不从教程记忆表反推牌面，避免 hover 泄露。
	var card: Dictionary = _table3d.hovered_card()
	var rank := str(card.get("rank", ""))
	if rank.is_empty():
		_tooltip.hide_tip()
		return
	var source := ""
	if kind == "pending":
		source = str((_current_state.get("pending", {}) as Dictionary).get("source", "draw"))
	var rect: Rect2 = _table3d.hovered_screen_rect(cam)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		var center := get_viewport().get_visible_rect().size * 0.5
		rect = Rect2(center - Vector2(24, 24), Vector2(48, 48))
	_tooltip.show_state(HoverState.NEUTRAL, CardAbilityText.display_rank(rank),
		CardAbilityText.ability(rank, source), "", rect)


func _update_overlay(id: String) -> void:
	var total := TutorialController.STEPS.size()
	_overlay.set_step(
		TutorialText.title(id),
		"%d / %d" % [mini(controller.step_index + 1, total), total],
		TutorialText.task(id),
		controller.is_talk(),
		id
	)


func _show_step_line(id: String) -> void:
	var lines := TutorialText.lines(id)
	if lines.is_empty():
		_overlay.hide_speech()
		_stop_talk()
		return
	_show_line()


func _show_line() -> void:
	var lines := TutorialText.lines(controller.step_id())
	if _line_index < 0 or _line_index >= lines.size():
		return
	var text := str(lines[_line_index])
	_overlay.set_speech(TutorialText.SPEAKER, text, controller.is_talk())
	_talk_for(text)


func _talk_for(text: String) -> void:
	_talk_token += 1
	var token := _talk_token
	var robot = _opponent_robot()
	if robot != null and robot.has_method("set_talking"):
		robot.set_talking(true)
	_overlay.set_speech_visible_chars(0)
	var interval: float = _animalese.seconds_per_char() if _animalese != null else 0.055
	for i in text.length():
		if token != _talk_token:
			return
		_overlay.set_speech_visible_chars(i + 1)
		var ch := text[i]
		if _animalese != null:
			_animalese.play_char(ch, _animalese.is_question(text, i))
		var wait := interval
		if ch == " " or ch == "," or ch == "." or ch == "!" or ch == "?" or ch == "…":
			wait *= 2.2
		await get_tree().create_timer(wait).timeout
	if token != _talk_token:
		return
	await get_tree().create_timer(0.35).timeout
	if token != _talk_token:
		return
	if robot != null and is_instance_valid(robot) and robot.has_method("set_talking"):
		robot.set_talking(false)


func _stop_talk() -> void:
	_talk_token += 1
	if _animalese != null and is_instance_valid(_animalese):
		_animalese.stop_all()
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.set_speech_visible_chars(-1)
	var robot = _opponent_robot()
	if robot != null and is_instance_valid(robot) and robot.has_method("set_talking"):
		robot.set_talking(false)


func _opponent_robot():
	if _table3d == null:
		return null
	var avatar = _table3d.get_node_or_null("Seats/Seat1/Avatar")
	if avatar == null:
		return null
	return avatar.get_node_or_null("RobotAvatar")


func _actionable_for_step(id: String) -> Callable:
	if id == "welcome" or id == "part2_peek":
		return func(seat: int, slot: int) -> bool: 			return seat == TutorialSteps.PLAYER and (slot == 2 or slot == 3)
	if id == "rules_choices_hand":
		return func(seat: int, slot: int) -> bool: return seat == TutorialSteps.PLAYER
	if id == "part2_replace":
		return func(seat: int, slot: int) -> bool: return seat == TutorialSteps.PLAYER and slot == 3
	if id == "slap_prompt":
		return func(seat: int, slot: int) -> bool: return seat == TutorialSteps.PLAYER and slot == 2
	if id == "slap_other_click":
		return func(seat: int, slot: int) -> bool: return seat == TutorialSteps.OPPONENT and slot == 3
	if id == "slap_other_exchange":
		return func(seat: int, slot: int) -> bool: 			return seat == TutorialSteps.PLAYER and (slot == 0 or slot == 1 or slot == 3)
	return func(_seat: int, _slot: int) -> bool: return false


## 不移动相机；用屏幕空间红箭头指向当前步骤目标。
func _update_pointer() -> void:
	if _pointer == null:
		return
	if controller.focus().is_empty() or _table3d == null or _table3d.camera == null:
		_pointer.hide_target()
		return
	var cam: Camera3D = _table3d.camera.camera_node()
	if cam == null:
		_pointer.hide_target()
		return
	var world := _focus_point(controller.focus())
	if cam.is_position_behind(world):
		_pointer.hide_target()
		return
	_pointer.set_target(cam.unproject_position(world))


func _focus_point(kind: String) -> Vector3:
	match kind:
		"deck":
			return _table3d.center_xform("deck").origin + Vector3(0.0, 0.05, 0.0)
		"discard":
			return _table3d.center_xform("discard").origin + Vector3(0.0, 0.05, 0.0)
		"own_hand":
			if controller.step_id() == "part2_replace":
				return _table3d.slot_xform(TutorialSteps.PLAYER, 3).origin
			if controller.step_id() == "slap_prompt":
				return _table3d.slot_xform(TutorialSteps.PLAYER, 2).origin
			if controller.step_id() == "slap_other_exchange":
				return _table3d.slot_xform(TutorialSteps.PLAYER, 1).origin
			return (_table3d.slot_xform(TutorialSteps.PLAYER, 2).origin \
				+ _table3d.slot_xform(TutorialSteps.PLAYER, 3).origin) * 0.5
		"opponent":
			return _table3d.seat_world(TutorialSteps.OPPONENT) + Vector3(0.0, 3.1, 0.0)
		"opponent_hand":
			return _table3d.slot_xform(TutorialSteps.OPPONENT, 3).origin
		"opponent_two":
			return _table3d.slot_xform(TutorialSteps.OPPONENT, 4).origin
		_:
			return Vector3(0.0, 1.0, 0.0)


## 真实贴牌表现：先翻牌（绿光）→ 再飞到弃牌堆 → 再进入下一步。
func _play_slap_sequence(effect: String, slot: int) -> void:
	if instant_auto:
		_enter_step(false)
		return
	_stop_slap()
	var players: Array = _current_state.get("players", [])
	if players.size() < 2:
		_enter_step(false)
		return
	var card: Dictionary = {}
	var target := TutorialSteps.PLAYER
	var target_slot := 2
	if effect == "slap":
		card = _known_cards.get("0_2", TutorialSteps.card_by_id("p2"))
		target = TutorialSteps.PLAYER
		target_slot = slot
	else:
		var o_slots: Array = players[1].get("slots", [])
		if slot >= 0 and slot < o_slots.size():
			card = TutorialSteps.card_by_id(str((o_slots[slot] as Dictionary).get("card_id", "")))
		target = TutorialSteps.OPPONENT
		target_slot = slot
	if card.is_empty():
		_enter_step(false)
		return
	_sequence_busy = true
	var token := _step_token
	_table3d.reveal_slot(target, target_slot, card, Color(0.55, 0.9, 0.6, 1.0), 1.1)
	AudioManager.play_slap_success()
	_show_burst(card, "贴牌成功", TutorialSteps.PLAYER_NAME)
	await get_tree().create_timer(0.55).timeout
	if not is_inside_tree() or token != _step_token:
		_sequence_busy = false
		return
	_table3d.animate_exchange({"kind": "slap_resolved", "target": target,
		"target_slot": target_slot, "card": card})
	await get_tree().create_timer(0.45).timeout
	_sequence_busy = false
	if not is_inside_tree() or token != _step_token:
		return
	_enter_step(false)


func _play_effect(effect: String, slot := -1) -> void:
	if instant_auto:
		return
	var p: Array = _current_state.get("players", [])
	match effect:
		"replace":
			if p.size() < 2:
				return
			var old_card: Dictionary = (p[0].slots[3] as Dictionary).get("card", {})
			var big_card: Dictionary = _current_state.get("pending", {})
			_table3d.animate_exchange({"kind": "replace", "actor": TutorialSteps.PLAYER,
				"slot": 3, "old_data": old_card, "big_data": big_card})
			AudioManager.play_flip()
		"discard":
			var discard_card: Dictionary = _current_state.get("pending", {})
			_table3d.animate_exchange({"kind": "discard", "actor": TutorialSteps.PLAYER,
				"big_data": discard_card})
			AudioManager.play_discard()
		"slap":
			if p.is_empty():
				return
			var card: Dictionary = _known_cards.get("0_2", TutorialSteps.card_by_id("p2"))
			_table3d.animate_exchange({"kind": "slap_resolved", "target": TutorialSteps.PLAYER,
				"target_slot": 2, "card": card})
			AudioManager.play_slap_success()
			_show_burst(card, "贴牌成功", TutorialSteps.PLAYER_NAME)
		"slap_other":
			if p.size() < 2:
				return
			var o_slots: Array = p[1].get("slots", [])
			if o_slots.size() <= 3:
				return
			var q_card: Dictionary = TutorialSteps.card_by_id(str((o_slots[3] as Dictionary).get("card_id", "")))
			_table3d.reveal_slot(TutorialSteps.OPPONENT, 3, q_card,
				Color(0.55, 0.9, 0.6, 1.0), 1.0)
			_table3d.animate_exchange({"kind": "slap_resolved",
				"target": TutorialSteps.OPPONENT, "target_slot": 3, "card": q_card})
			AudioManager.play_slap_success()
		"slap_gift":
			_table3d.animate_exchange({"kind": "slap_gift", "actor": TutorialSteps.PLAYER,
				"own_slot": slot, "target": TutorialSteps.OPPONENT, "target_slot": 3})
			AudioManager.play_select()
		"draw":
			AudioManager.play_draw()


func _show_burst(card: Dictionary, title: String, who: String) -> void:
	if card.is_empty():
		return
	var burst := SlapSuccessBurst.new()
	burst.name = "TutorialBurst"
	burst.z_index = 180
	add_child(burst)
	burst.setup(card, who, title)


func _run_auto(id: String, token: int) -> void:
	while _paused and token == _step_token:
		await get_tree().process_frame
	if token != _step_token:
		return
	if instant_auto:
		var end_state := controller.end_state()
		_render_state(end_state, _actionable_for_step(controller.step_id()), false)
		_current_state = end_state
		if controller.advance():
			_enter_step(false)
		return
	match id:
		"opponent_replace":
			var drew := TutorialSteps.state_by_id("opponent_drew_Q")
			_render_state(drew, _actionable_for_step(controller.step_id()), false)
			_current_state = drew
			AudioManager.play_draw()
			await get_tree().create_timer(1.0).timeout
			if token != _step_token:
				return
			var replaced_state := TutorialSteps.state_by_id("opponent_replaced")
			_animate_replace(TutorialSteps.OPPONENT, 3, _current_state, replaced_state)
			_render_state(replaced_state, _actionable_for_step(controller.step_id()), false)
			_current_state = replaced_state
			AudioManager.play_flip()
			await get_tree().create_timer(1.5).timeout
		"opponent_discard":
			var mid := TutorialSteps.state_by_id("opponent_drew_2")
			_render_state(mid, _actionable_for_step(controller.step_id()), false)
			_current_state = mid
			await get_tree().create_timer(1.0).timeout
			if token != _step_token:
				return
			var discarded_state := TutorialSteps.state_by_id("opponent_discarded_2")
			_table3d.animate_exchange({"kind": "discard", "actor": TutorialSteps.OPPONENT,
				"big_data": TutorialSteps.card_by_id("o5")})
			_render_state(discarded_state, _actionable_for_step(controller.step_id()), false)
			_current_state = discarded_state
			AudioManager.play_discard()
			await get_tree().create_timer(1.0).timeout
		"wrong_slap_demo":
			var drew := TutorialSteps.state_by_id("opponent_drew_4")
			_render_state(drew, _actionable_for_step(controller.step_id()), false)
			_current_state = drew
			await get_tree().create_timer(1.0).timeout
			if token != _step_token:
				return
			var discarded := TutorialSteps.state_by_id("opponent_discarded_4")
			_table3d.animate_exchange({"kind": "discard", "actor": TutorialSteps.OPPONENT,
				"big_data": TutorialSteps.card_by_id("o6")})
			_render_state(discarded, _actionable_for_step(controller.step_id()), false)
			_current_state = discarded
			AudioManager.play_discard()
			await get_tree().create_timer(1.0).timeout
			if token != _step_token:
				return
			var two := TutorialSteps.card_by_id("o10")
			_table3d.reveal_slot(TutorialSteps.OPPONENT, 4, two,
				Color(1.0, 0.35, 0.35, 1.0), 1.6)
			AudioManager.play_slap_fail()
			_overlay.show_toast("贴牌错误：2 ≠ 4")
			await get_tree().create_timer(1.0).timeout
			if token != _step_token:
				return
			var penalty_state := TutorialSteps.state_by_id("opponent_penalty_1")
			_table3d.animate_exchange({"kind": "slap_penalty",
				"peer": TutorialSteps.OPPONENT, "slot": 5})
			_render_state(penalty_state, _actionable_for_step(controller.step_id()), false)
			_current_state = penalty_state
			AudioManager.play_slap_fail()
			await get_tree().create_timer(1.0).timeout
		"slap_other_setup":
			_table3d.animate_exchange({"kind": "replace", "actor": TutorialSteps.OPPONENT,
				"slot": 2, "old_data": TutorialSteps.card_by_id("o2"),
				"big_data": TutorialSteps.card_by_id("o11")})
			var window_state := TutorialSteps.state_by_id("slap_other_window")
			_render_state(window_state, _actionable_for_step(controller.step_id()), false)
			_current_state = window_state
			AudioManager.play_flip()
			await get_tree().create_timer(1.2).timeout
		"overflow_demo":
			await get_tree().create_timer(0.3).timeout
			if token != _step_token:
				return
			var two := TutorialSteps.card_by_id("o10")
			_table3d.reveal_slot(TutorialSteps.OPPONENT, 4, two,
				Color(1.0, 0.35, 0.35, 1.0), 1.2)
			AudioManager.play_slap_fail()
			_overlay.show_toast("贴牌错误：2 ≠ Q")
			await get_tree().create_timer(0.8).timeout
			if token != _step_token:
				return
			var over := controller.end_state()
			_table3d.animate_exchange({"kind": "slap_penalty",
				"peer": TutorialSteps.OPPONENT, "slot": 6})
			_render_state(over, _actionable_for_step(controller.step_id()), false)
			_current_state = over
			AudioManager.play_slap_fail()
			await get_tree().create_timer(1.0).timeout
	if token != _step_token:
		return
	if controller.advance():
		_enter_step(false)


func _animate_replace(actor: int, slot: int, from_state: Dictionary, to_state: Dictionary) -> void:
	var from_players: Array = from_state.get("players", [])
	var to_players: Array = to_state.get("players", [])
	if from_players.size() <= actor or to_players.size() <= actor:
		return
	var from_slots: Array = from_players[actor].get("slots", [])
	var to_slots: Array = to_players[actor].get("slots", [])
	if slot >= from_slots.size() or slot >= to_slots.size():
		return
	_table3d.animate_exchange({"kind": "replace", "actor": actor, "slot": slot,
		"old_data": (from_slots[slot] as Dictionary).get("card", {}),
		"big_data": (to_slots[slot] as Dictionary).get("card", {})})


func _start_slap_window(total := SLAP_SECONDS) -> void:
	_slap_token += 1
	_slap_running = true
	_slap_left = total
	_slap_total = total
	_slap_last_int = int(ceil(total))
	_overlay.set_slap("run", total, total)
	AudioManager.play_countdown()


func _stop_slap() -> void:
	_slap_token += 1
	_race_token += 1
	_race_mode = false
	_race_locked = false
	_slap_running = false
	_slap_left = 0.0
	_slap_last_int = -1
	_overlay.set_slap("off")


func _tick_slap(delta: float) -> void:
	_slap_left -= delta
	var secs := maxf(_slap_left, 0.0)
	var whole := int(ceil(secs))
	if whole != _slap_last_int and whole >= 1:
		_slap_last_int = whole
		AudioManager.play_countdown()
	_overlay.set_slap("run", secs, _slap_total)
	if _slap_left <= 0.0:
		_slap_running = false
		_overlay.set_slap("timeout")
		if _race_mode:
			return
		_overlay.show_toast(TutorialText.toast("slap_timeout"))


## 贴牌比赛：玩家必须在 1.5s 内点自己的 2，否则阿岚先贴中；失败后重置重试。
func _start_race() -> void:
	_race_token += 1
	var token := _race_token
	_race_mode = true
	_race_locked = false
	var reset := TutorialSteps.state_by_id("opponent_discarded_2")
	_render_state(reset, _actionable_for_step(controller.step_id()), false)
	_current_state = reset
	_start_slap_window(1.5)
	_a_lan_race_wait(token)


func _a_lan_race_wait(token: int) -> void:
	await get_tree().create_timer(1.5).timeout
	if _paused:
		return
	if token != _race_token or controller.step_id() != "slap_prompt":
		return
	_race_locked = true
	_slap_running = false
	_overlay.set_slap("timeout")
	var two := TutorialSteps.card_by_id("o10")
	_table3d.reveal_slot(TutorialSteps.OPPONENT, 4, two,
		Color(0.55, 0.9, 0.6, 1.0), 0.8)
	AudioManager.play_slap_success()
	await get_tree().create_timer(0.35).timeout
	if _paused:
		return
	if token != _race_token or controller.step_id() != "slap_prompt":
		return
	_table3d.animate_exchange({"kind": "slap_resolved",
		"target": TutorialSteps.OPPONENT, "target_slot": 4, "card": two})
	var lost := TutorialSteps.state_by_id("race_lost")
	_render_state(lost, _actionable_for_step(controller.step_id()), false)
	_current_state = lost
	await get_tree().create_timer(1.0).timeout
	if _paused:
		return
	if token != _race_token or controller.step_id() != "slap_prompt":
		return
	_overlay.show_toast(TutorialText.toast("race_lost"))
	await get_tree().create_timer(0.9).timeout
	if _paused:
		return
	if token != _race_token or controller.step_id() != "slap_prompt":
		return
	_start_race()


func _set_paused(on: bool) -> void:
	_paused = on
	_overlay.show_pause(on)
	if on:
		_stop_talk()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_crosshair.visible = false
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_crosshair.visible = true
	if controller.step_id() == "slap_prompt":
		_start_race()


func _skip_step() -> void:
	if controller.is_summary():
		finish_skip()
		return
	_set_paused(false)
	if controller.mode() == "peek":
		_table3d.release_held_reveals(false)
		_overlay.show_ready(false)
	if _manual_open:
		_toggle_manual(false)
	controller.skip_step()
	_enter_step(false)


func _restart() -> void:
	controller.restart()
	_completed_emitted = false
	_known_cards.clear()
	_peek_flipped = false
	if _manual_open:
		_toggle_manual(false)
	if _table3d != null:
		_table3d.release_held_reveals(false)
		_table3d.clear_settle_reveals()
	_free_settlement()
	_overlay.show_summary(false)
	_overlay.show_ready(false)
	_set_paused(false)
	_enter_step(true)


func _free_settlement() -> void:
	if _settlement != null and is_instance_valid(_settlement):
		_settlement.queue_free()
	_settlement = null


func _show_summary() -> void:
	_stop_slap()
	_overlay.set_slap("off")
	_overlay.hide_speech()
	_overlay.show_ready(false)
	_stop_talk()
	if _manual_open:
		_toggle_manual(false)
	_overlay.show_summary(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_crosshair.visible = false
	if _pointer != null:
		_pointer.hide_target()
	if _tooltip != null:
		_tooltip.hide_tip()
	if not _completed_emitted:
		_completed_emitted = true
		completed.emit()
	_show_settlement()


func _show_settlement() -> void:
	if _settlement != null and is_instance_valid(_settlement):
		return
	_settlement = load(SETTLEMENT_SCENE).instantiate()
	_settlement.name = "TutorialSettlement"
	_settlement.z_index = 100
	_settlement.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_settlement)
	var flip := func(seat: int, slot: int, card: Dictionary) -> void:
		_table3d.reveal_slot_settle(seat, slot, card)
	_settlement.setup(TutorialSteps.result_model(controller.gift_slot), false, 1,
		Callable(), Callable(), Callable(), flip)
	var footer := _settlement.get_node_or_null("Center/Panel/VBox/Footer")
	if footer != null:
		footer.visible = false
	if _overlay != null and is_instance_valid(_overlay):
		move_child(_overlay, get_child_count() - 1)
