class_name TutorialView
extends Control
## 3D 教学局：固定镜头 + 鼠标指针点击；本地时间线，不接网络/GameState。

signal closed
signal completed

const TABLE3D_SCENE := "res://scenes/ui/table3d.tscn"
const SETTLEMENT_SCENE := "res://scenes/ui/settlement_page.tscn"

var controller := TutorialController.new()
var skip_requested := false
var _table3d: Node3D
var _overlay: TutorialOverlay
var _settlement: Control
var _confirm: ConfirmationDialog
var _completed_emitted := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_table3d = load(TABLE3D_SCENE).instantiate()
	_table3d.name = "Table3D"
	add_child(_table3d)
	_table3d.set_active(true)
	_overlay = TutorialOverlay.new()
	_overlay.name = "Overlay"
	_overlay.action_pressed.connect(handle_action)
	_overlay.continue_pressed.connect(handle_continue)
	_overlay.skip_step_pressed.connect(_skip_step)
	_overlay.skip_all_pressed.connect(finish_skip)
	_overlay.restart_pressed.connect(_restart)
	_overlay.exit_pressed.connect(func(): closed.emit())
	add_child(_overlay)
	_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			handle_continue()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_ensure_confirm()
			_confirm.popup_centered()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_viewport().gui_get_hovered_control() != null:
			return
		handle_pick(_pick_at_mouse())
		get_viewport().set_input_as_handled()

func _pick_at_mouse() -> Dictionary:
	if _table3d == null or _table3d.camera == null:
		return {}
	var cam: Camera3D = _table3d.camera.camera_node()
	if cam == null:
		return {}
	return Table3dPicker.pick(cam, _table3d.get_world_3d(), get_viewport().get_mouse_position())

func handle_continue() -> void:
	if controller.is_interact():
		return
	controller.advance()
	_refresh()

func handle_action(id: String) -> void:
	var r: Dictionary = controller.action(id)
	if not bool(r.get("ok", false)):
		_overlay.show_toast(str(r.get("message", "")))
	_refresh()

func handle_pick(meta: Dictionary) -> void:
	var r: Dictionary = controller.pick(meta)
	if not bool(r.get("ok", false)) and not str(r.get("message", "")).is_empty():
		_overlay.show_toast(str(r.get("message", "")))
	_refresh()

func _skip_step() -> void:
	controller.skip_step()
	_refresh()

func _restart() -> void:
	controller.restart()
	if _settlement != null and is_instance_valid(_settlement):
		_settlement.queue_free()
		_settlement = null
	_refresh()

func finish_skip() -> void:
	skip_requested = true
	closed.emit()

func _ensure_confirm() -> void:
	if _confirm != null and is_instance_valid(_confirm):
		return
	_confirm = ConfirmationDialog.new()
	_confirm.title = "跳过教程"
	_confirm.dialog_text = "确定要跳过新手教程吗？"
	_confirm.confirmed.connect(finish_skip)
	add_child(_confirm)

func _refresh() -> void:
	if _settlement != null and is_instance_valid(_settlement) and controller.step_id() != "settle":
		_settlement.queue_free()
		_settlement = null
	var st: Dictionary = controller.state()
	_table3d.render(st, _actionable_for_step(), false)
	if controller.step_id() == "settle":
		_show_settlement()
	if controller.step_id() == "summary" and not _completed_emitted:
		_completed_emitted = true
		completed.emit()
	var total := TutorialController.STEPS.size()
	_overlay.set_step(
		TutorialText.title(controller.step_id()),
		"%d / %d" % [mini(controller.step_index + 1, total), total],
		TutorialText.body(controller.step_id()),
		controller.is_interact(),
		controller.step_id()
	)

func _actionable_for_step() -> Callable:
	var id := controller.step_id()
	if id == "replace":
		return func(seat: int, slot: int) -> bool: return seat == 0 and slot == 1
	if id == "slap":
		return func(seat: int, slot: int) -> bool: return seat == 0 and slot == 2
	return func(_seat: int, _slot: int) -> bool: return false

func _show_settlement() -> void:
	if _settlement != null and is_instance_valid(_settlement):
		return
	_settlement = load(SETTLEMENT_SCENE).instantiate()
	_settlement.name = "TutorialSettlement"
	add_child(_settlement)
	var flip := func(seat: int, slot: int, card: Dictionary) -> void:
		_table3d.reveal_slot_settle(seat, slot, card)
	_settlement.setup(TutorialSteps.result_model(), false, 1,
		Callable(), Callable(), Callable(), flip)
	var footer := _settlement.get_node_or_null("Center/Panel/VBox/Footer")
	if footer != null:
		footer.visible = false
