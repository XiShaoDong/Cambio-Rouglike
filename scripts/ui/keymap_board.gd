class_name KeymapBoard
extends Control
## 按键映射页内容（3D 全息看板第三页）：五列 + 行状态。
## 左=原始默认键（只读），右=可点重绑的新键；底部保存按钮。
## 纯展示 + 本地待保存状态；真正落盘由 ManualPanel/main 驱动。

signal save_requested(new_map: Dictionary)
signal changed()

const CAPTURE_TEXT := "按键中…"
const RESERVED_TEXT := "保留键，不可绑定"
const KEY_COL_W := 72.0
const LABEL_COL_W := 70.0
const DESC_COL_W := 180.0
const STATUS_COL_W := 110.0
const ROW_H := 38.0

var _pending: Dictionary = {}
var _baseline: Dictionary = {}
var _capturing := ""
var _chip_btns := {}       # id -> Button（新键）
var _default_chips := {}   # id -> PanelContainer（只读原始键）
var _status := {}          # id -> Label
var _row_panels := {}      # id -> PanelContainer
var _row_states := {}      # id -> normal/hover/capture/bad/ok
var _save_btn: Button = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	changed.connect(_on_changed)

func _on_changed() -> void:
	set_save_enabled(has_changes())

func setup(current_map: Dictionary, _reserved: Array = []) -> void:
	_baseline = current_map.duplicate()
	_pending = current_map.duplicate()
	_capturing = ""
	_chip_btns.clear()
	_default_chips.clear()
	_status.clear()
	_row_panels.clear()
	_row_states.clear()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.name = "KeymapVBox"
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	vb.add_child(_make_header())
	for id in KeybindModel.action_ids():
		vb.add_child(_make_row(str(id), KeybindModel.action_def(str(id))))
	_save_btn = Button.new()
	_save_btn.name = "SaveButton"
	_save_btn.text = "保存"
	_save_btn.custom_minimum_size = Vector2(140, 40)
	_save_btn.add_theme_font_size_override("font_size", 16)
	_save_btn.set_meta("board_interactive", true)
	UIStyle.apply_primary(_save_btn)
	_save_btn.disabled = true
	_save_btn.pressed.connect(func(): save_requested.emit(pending_map()))
	vb.add_child(_save_btn)
	custom_minimum_size = vb.get_combined_minimum_size()

func _make_header() -> HBoxContainer:
	var head := HBoxContainer.new()
	head.name = "Header"
	head.add_theme_constant_override("separation", 8)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(LABEL_COL_W + 8.0 + DESC_COL_W, 0)
	head.add_child(pad)
	head.add_child(_head_cell("原始", KEY_COL_W))
	head.add_child(_head_cell("新按键", KEY_COL_W))
	head.add_child(_head_cell("状态", STATUS_COL_W))
	return head

func _head_cell(text: String, width: float) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(width, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", UITheme.color("hud_text_muted"))
	return lbl

func _make_row(id: String, def: Dictionary) -> PanelContainer:
	var wrap := PanelContainer.new()
	wrap.name = "RowPanel_" + id
	wrap.custom_minimum_size = Vector2(0, ROW_H)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.add_theme_stylebox_override("panel", UIStyle.row("normal"))
	wrap.mouse_entered.connect(_on_row_hover.bind(id, true))
	wrap.mouse_exited.connect(_on_row_hover.bind(id, false))
	_row_panels[id] = wrap
	_row_states[id] = "normal"

	var row := HBoxContainer.new()
	row.name = "Row_" + id
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	wrap.add_child(row)

	var l := Label.new()
	l.text = str(def.get("label", id))
	l.custom_minimum_size = Vector2(LABEL_COL_W, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UITheme.color("text_primary"))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)

	var d := Label.new()
	d.text = str(def.get("desc", ""))
	d.custom_minimum_size = Vector2(DESC_COL_W, 0)
	d.add_theme_font_size_override("font_size", 12)
	d.add_theme_color_override("font_color", UITheme.color("hud_text_muted"))
	d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(d)

	# 左：原始默认键（只读参考，变暗、不可点）
	var dchip := KeyHintPanel.make_chip(OS.get_keycode_string(int(def.get("default", 0))), 13)
	dchip.name = "Default"
	dchip.custom_minimum_size = Vector2(KEY_COL_W, 26)
	dchip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dchip.modulate = Color(1, 1, 1, 0.55)
	var dkey: Label = dchip.get_node_or_null("Key")
	if dkey != null:
		dkey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dchip)

	# 右：可重绑的新键（点它进入捕获）
	var chip := Button.new()
	chip.name = "Chip"
	chip.text = OS.get_keycode_string(int(_pending.get(id, 0)))
	chip.custom_minimum_size = Vector2(KEY_COL_W, 26)
	chip.add_theme_font_size_override("font_size", 13)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.set_meta("board_interactive", true)
	UIStyle.apply_chip_button(chip, false)
	chip.pressed.connect(begin_capture.bind(id))
	row.add_child(chip)

	var status := Label.new()
	status.name = "Status"
	status.custom_minimum_size = Vector2(STATUS_COL_W, 0)
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", UITheme.color("danger_text"))
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(status)

	_chip_btns[id] = chip
	_default_chips[id] = dchip
	_status[id] = status
	return wrap

func _on_row_hover(id: String, on: bool) -> void:
	if str(_row_states.get(id, "")) != "normal" and str(_row_states.get(id, "")) != "hover":
		return
	_set_row_state(id, "hover" if on else "normal")

func _set_row_state(id: String, state: String) -> void:
	_row_states[id] = state
	if _row_panels.has(id):
		(_row_panels[id] as PanelContainer).add_theme_stylebox_override("panel", UIStyle.row(state))

func begin_capture(id: String) -> void:
	if _capturing != "":
		cancel_capture()
	_capturing = id
	_chip_btns[id].text = CAPTURE_TEXT
	UIStyle.apply_chip_button(_chip_btns[id], true)
	_set_row_state(id, "capture")

## 由 main 捕获下一个 keydown 后调用。
func capture_key(keycode: int) -> void:
	if _capturing == "":
		return
	var id := _capturing
	var res: Dictionary = KeybindModel.rebind(_pending, id, keycode)
	if not bool(res.get("ok", false)):
		_status[id].text = RESERVED_TEXT if str(res.get("error", "")) == KeybindModel.ERR_RESERVED else "无效"
		_status[id].add_theme_color_override("font_color", UITheme.color("danger_text"))
		_set_row_state(id, "bad")
		return
	_pending = res.get("map")
	_capturing = ""
	var swapped := str(res.get("swapped", ""))
	_status[id].text = "已自动交换" if swapped != "" else ""
	_status[id].add_theme_color_override("font_color",
		UITheme.color("accent_focus") if swapped != "" else UITheme.color("danger_text"))
	_set_row_state(id, "ok" if swapped != "" else "normal")
	UIStyle.apply_chip_button(_chip_btns[id], false)
	refresh_chips()
	changed.emit()

func cancel_capture() -> void:
	if _capturing == "":
		return
	var id := _capturing
	_capturing = ""
	_status[id].text = ""
	_status[id].add_theme_color_override("font_color", UITheme.color("danger_text"))
	_set_row_state(id, "normal")
	UIStyle.apply_chip_button(_chip_btns[id], false)
	_refresh_chip(id)

func capturing() -> String:
	return _capturing

func pending_map() -> Dictionary:
	return _pending.duplicate()

func has_changes() -> bool:
	return _pending != _baseline

func commit() -> void:
	_baseline = _pending.duplicate()

func set_save_enabled(on: bool) -> void:
	if _save_btn != null:
		_save_btn.disabled = not on

func refresh_chips() -> void:
	for id in _chip_btns.keys():
		_refresh_chip(str(id))

func _refresh_chip(id: String) -> void:
	if _chip_btns.has(id):
		_chip_btns[id].text = CAPTURE_TEXT if id == _capturing else OS.get_keycode_string(int(_pending.get(id, 0)))
		UIStyle.apply_chip_button(_chip_btns[id], id == _capturing)

## 测试访问器。
func row_count() -> int:
	return _chip_btns.size()

func chip_text(id: String) -> String:
	return _chip_btns[id].text if _chip_btns.has(id) else ""

## 右侧只读「原始」列文本。
func default_text(id: String) -> String:
	if not _default_chips.has(id):
		return ""
	var lbl: Label = _default_chips[id].get_node_or_null("Key")
	return lbl.text if lbl != null else ""

func status_text(id: String) -> String:
	return _status[id].text if _status.has(id) else ""
