class_name Table3dTuner
extends Node3D
## Table3D 调参沙盒：实例化真实 table3d.tscn，按参数实时重摆节点，并提供写回 UI。

const TABLE3D_SCENE := "res://scenes/ui/table3d.tscn"
const SAMPLE_CARDS := [
	{"rank": "A", "suit": "♥"}, {"rank": "K", "suit": "♠"},
	{"rank": "Q", "suit": "♦"}, {"rank": "J", "suit": "♣"},
	{"rank": "10", "suit": "♥"}, {"rank": "7", "suit": "♠"},
]

var values: Dictionary = Table3dTunerModel.defaults()
var table3d: Node3D = null
var writer := Table3dTunerWriter.new()
var show_viewer_avatar := false

func _ready() -> void:
	table3d = load(TABLE3D_SCENE).instantiate()
	add_child(table3d)   # add_child 同步触发 table3d 的 _ready，节点立即可用
	reload_from_sources()
	apply_values()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	build_ui()

func set_value(key: String, value: float) -> void:
	values[key] = value

func seat_nodes() -> Array:
	var out: Array = []
	for i in 4:
		out.append(table3d.get_node_or_null("Seats/Seat%d" % i))
	return out

func avatar_nodes() -> Array:
	var out: Array = []
	for s in seat_nodes():
		if s != null:
			out.append(s.get_node_or_null("Avatar"))
	return out

func reload_from_sources() -> void:
	var texts := {
		Table3dTunerModel.LAYOUT_FILE: _read(Table3dTunerModel.LAYOUT_FILE),
		Table3dTunerModel.SCENE_FILE: _read(Table3dTunerModel.SCENE_FILE),
		Table3dTunerModel.VIEW_FILE: _read(Table3dTunerModel.VIEW_FILE),
	}
	values = Table3dTunerModel.parse_sources(texts)

func reset_defaults() -> void:
	values = Table3dTunerModel.defaults()

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""

func _viewer_angle() -> float:
	var base: Array = Table3dTunerModel.parse_layout(_read(Table3dTunerModel.LAYOUT_FILE)).get("angles", [0.0])
	var a: float = float(base[0]) if base.size() > 0 else 0.0
	return a + float(values["seat_angle_offset"])

func _angles_for_display() -> Array:
	var base: Array = Table3dTunerModel.parse_layout(_read(Table3dTunerModel.LAYOUT_FILE)).get("angles", [0.0, 270.0, 90.0, 180.0])
	var out: Array = []
	for a in base:
		out.append(float(a) + float(values["seat_angle_offset"]))
	return out

func apply_values() -> void:
	if table3d == null:
		return
	_apply_scene_nodes()
	_apply_camera()
	_apply_seats()
	_apply_pending()
	_rebuild_sample_cards()
	_apply_hud()

func _apply_scene_nodes() -> void:
	var table := table3d.get_node_or_null("Table") as MeshInstance3D
	var edge := table3d.get_node_or_null("TableEdge") as MeshInstance3D
	var side := float(values["table_radius"]) * 2.0
	if table != null:
		(table.mesh as BoxMesh).size = Vector3(side, 0.08, side)
	if edge != null:
		(edge.mesh as BoxMesh).size = Vector3(side + 0.375, 0.12, side + 0.375)
	for av in avatar_nodes():
		var body: Node = av.get_node_or_null("Body")
		var head: Node = av.get_node_or_null("Head")
		if body != null:
			body.position.y = float(values["body_y"])
		if head != null:
			head.position.y = float(values["head_y"])

func _apply_camera() -> void:
	var cam = table3d.get_node_or_null("CameraRig")
	if cam == null:
		return
	cam.EYE_HEIGHT = float(values["camera_eye_height"])
	cam.CAMERA_BACK = float(values["camera_back"])
	cam.MOUSE_SENSITIVITY = float(values["camera_sensitivity"])
	var angle := _viewer_angle()
	cam.set("_framed", false)
	cam.frame_for_seat(angle)   # 取基准朝向 + 复位环视
	# frame_for_seat 用的是 Table3dLayout.SEAT_RADIUS 常量；用调参后的半径与眼高重摆相机臂。
	var rad := deg_to_rad(angle)
	var dir := Vector3(sin(rad), 0.0, cos(rad))
	var dist := float(values["seat_radius"]) + float(values["camera_back"])
	cam.position = dir * dist + Vector3(0.0, float(values["camera_eye_height"]), 0.0)
	cam.set("pitch", Table3dCamera.aim_pitch_deg(float(values["camera_eye_height"]), dist))
	cam.look(Vector2.ZERO)   # rel=0：不改 yaw/pitch，仅应用上面设的相机臂与俯角

func _apply_seats() -> void:
	var angles := _angles_for_display()
	var r := float(values["seat_radius"])
	for i in seat_nodes().size():
		var s: Node3D = seat_nodes()[i]
		if s == null:
			continue
		var a: float = float(angles[i]) if i < angles.size() else 0.0
		var rad := deg_to_rad(a)
		s.position = Vector3(sin(rad), 0.0, cos(rad)) * r
		s.rotation_degrees = Vector3(0.0, a + 180.0, 0.0)
		var av := s.get_node_or_null("Avatar")
		if av != null:
			av.position = Vector3(0.0, float(values["camera_eye_height"]), -float(values["camera_back"]))
			av.visible = (i != 0) or show_viewer_avatar

func _apply_pending() -> void:
	var deck := table3d.get_node_or_null("Center/Deck") as Node3D
	var disc := table3d.get_node_or_null("Center/DiscardTop") as Node3D
	var pend := table3d.get_node_or_null("Center/Pending") as Node3D
	if deck == null or disc == null or pend == null:
		return
	pend.position = Vector3((deck.position.x + disc.position.x) * 0.5, float(values["pending_y"]),
		(deck.position.z + disc.position.z) * 0.5)

func _slot_local(slot: int) -> Vector3:
	var grid := Table3dLayout.slot_grid_pos(slot)
	return Vector3(
		-grid.x * (float(values["block_w"]) + float(values["gap_x"])),
		0.0,
		(1.0 - grid.y) * (float(values["block_d"]) + float(values["gap_z"])))

func _rebuild_sample_cards() -> void:
	var count := 4
	for i in seat_nodes().size():
		var s: Node3D = seat_nodes()[i]
		if s == null:
			continue
		var hand: Node3D = s.get_node("HandAnchor")
		for child in hand.get_children():
			hand.remove_child(child)
			child.queue_free()
		for slot in count:
			var block := CardBlock.new()
			block.name = "Sample%d" % slot
			block.position = _slot_local(slot)
			hand.add_child(block)
			block.setup({"card": SAMPLE_CARDS[(i + slot) % SAMPLE_CARDS.size()]})

func _apply_hud() -> void:
	var hud = table3d.get_node_or_null("Hud")
	if hud == null:
		return
	hud.set_buttons([
		{"text": "Ready", "action": "ready", "enabled": true},
		{"text": "Kongbaya", "action": "kongbaya", "enabled": true},
		{"text": "Q", "action": "q", "enabled": false},
	])
	var rad := deg_to_rad(_viewer_angle())
	var dir := Vector3(sin(rad), 0.0, cos(rad))
	hud.position = dir * (float(values["seat_radius"]) - float(values["hud_offset"])) + Vector3(0.0, float(values["hud_height"]), 0.0)
	hud.rotation_degrees = Vector3(0.0, _viewer_angle() + 180.0, 0.0)

func _input(event: InputEvent) -> void:
	var cam = table3d.get_node_or_null("CameraRig") if table3d != null else null
	if cam == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam.look(event.relative)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

var _sliders: Dictionary = {}     # key -> HSlider
var _value_labels: Dictionary = {} # key -> Label
var _target_checks: Dictionary = {} # file -> CheckBox
var _force_check: CheckBox


func write_targets() -> Array:
	return [Table3dTunerModel.LAYOUT_FILE, Table3dTunerModel.SCENE_FILE, Table3dTunerModel.VIEW_FILE]

func slider_count() -> int:
	return _sliders.size()

func build_ui() -> void:
	if not _sliders.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.name = "TunerUI"
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	margin.custom_minimum_size = Vector2(330, 0)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	layer.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 0)
	margin.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var groups := Table3dTunerModel.groups()
	var params := Table3dTunerModel.params()
	for g in groups:
		var header := Label.new()
		header.text = "— %s —" % g
		root.add_child(header)
		for key in params.keys():
			if str((params[key] as Dictionary)["group"]) != g:
				continue
			_add_row(root, key, params[key])

	root.add_child(HSeparator.new())
	var reset_btn := Button.new()
	reset_btn.text = "重置默认"
	reset_btn.pressed.connect(func(): reset_defaults(); _sync_sliders(); apply_values())
	root.add_child(reset_btn)
	var reload_btn := Button.new()
	reload_btn.text = "重新解析源文件"
	reload_btn.pressed.connect(func(): reload_from_sources(); _sync_sliders(); apply_values())
	root.add_child(reload_btn)
	var copy_btn := Button.new()
	copy_btn.text = "复制参数片段"
	copy_btn.pressed.connect(func(): DisplayServer.clipboard_set(Table3dTunerModel.format_fragment(values)))
	root.add_child(copy_btn)

	root.add_child(HSeparator.new())
	root.add_child(_label("写回目标（手动勾选）"))
	for path in write_targets():
		var cb := CheckBox.new()
		cb.text = path
		cb.button_pressed = true
		root.add_child(cb)
		_target_checks[path] = cb
	_force_check = CheckBox.new()
	_force_check.text = "仍要覆盖占用中文件"
	_force_check.button_pressed = false
	root.add_child(_force_check)
	var write_btn := Button.new()
	write_btn.text = "写回源文件"
	write_btn.pressed.connect(func(): _report(write_back(_force_check.button_pressed)))
	root.add_child(write_btn)
	_write_log = _label("")
	root.add_child(_write_log)

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _add_row(root: VBoxContainer, key: String, meta: Dictionary) -> void:
	var row := VBoxContainer.new()
	var top := HBoxContainer.new()
	var name := _label(str(meta["label"]))
	name.custom_minimum_size = Vector2(180, 0)
	top.add_child(name)
	var value_label := _label("")
	top.add_child(value_label)
	row.add_child(top)
	var slider := HSlider.new()
	slider.min_value = float(meta["min"])
	slider.max_value = float(meta["max"])
	slider.step = float(meta["step"])
	slider.value = float(values.get(key, meta["default"]))
	slider.custom_minimum_size = Vector2(300, 0)
	slider.value_changed.connect(func(v: float):
		set_value(key, v)
		value_label.text = Table3dTunerModel._fmt(v)
		apply_values())
	row.add_child(slider)
	root.add_child(row)
	_sliders[key] = slider
	_value_labels[key] = value_label
	value_label.text = Table3dTunerModel._fmt(slider.value)

func _sync_sliders() -> void:
	for key in _sliders.keys():
		(_sliders[key] as HSlider).set_value_no_signal(float(values.get(key, 0.0)))
		(_value_labels[key] as Label).text = Table3dTunerModel._fmt(float(values.get(key, 0.0)))

var _write_log: Label = null

func write_back(force := false) -> Array:
	var results: Array = []
	var texts := {
		Table3dTunerModel.LAYOUT_FILE: _read(Table3dTunerModel.LAYOUT_FILE),
		Table3dTunerModel.SCENE_FILE: _read(Table3dTunerModel.SCENE_FILE),
		Table3dTunerModel.VIEW_FILE: _read(Table3dTunerModel.VIEW_FILE),
	}
	for path in write_targets():
		var cb: CheckBox = _target_checks.get(path)
		if cb == null or not cb.button_pressed:
			continue
		var new_text := ""
		match path:
			Table3dTunerModel.LAYOUT_FILE:
				new_text = Table3dTunerModel.apply_layout(texts[path], values)["text"]
			Table3dTunerModel.SCENE_FILE:
				new_text = Table3dTunerModel.apply_scene(texts[path], values)["text"]
			Table3dTunerModel.VIEW_FILE:
				new_text = Table3dTunerModel.apply_view(texts[path], values)["text"]
		var r := writer.write(path, new_text, force)
		r["file"] = path
		results.append(r)
	return results

func _report(results: Array) -> void:
	if _write_log == null:
		return
	var lines: Array = []
	for r in results:
		lines.append("%s → %s%s" % [str(r["file"]).get_file(), "OK" if r["ok"] else "拒绝", "" if r["ok"] else " (" + str(r["error"]) + ")"])
	_write_log.text = "写回结果:\n" + "\n".join(lines)
