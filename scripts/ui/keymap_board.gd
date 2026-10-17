class_name KeymapBoard
extends Control
## 按键映射页内容（3D 全息看板第三页）：每行左右两格——左=你绑定的新键（可点重绑），
## 右=原始默认键（只读参考）；底部保存按钮。
## 纯展示 + 本地待保存状态；真正落盘由 ManualPanel/main 驱动。
## 可交互控件（左键 chip / 保存按钮）带 meta("board_interactive")，供 Board3d 部分穿透判定。

signal save_requested(new_map: Dictionary)
signal changed()

const CAPTURE_TEXT := "按键中…"
const RESERVED_TEXT := "保留键，不可绑定"
const ERR_COLOR := Color(0.82, 0.24, 0.24)
const KEY_COL_W := 112.0       # 单格宽（新按键列 / 原始列同宽）
const LABEL_COL_W := 96.0
const DESC_COL_W := 280.0

var _pending: Dictionary = {}
var _baseline: Dictionary = {}
var _capturing := ""
var _chip_btns := {}       # id -> Button（左：可重绑的新键）
var _default_chips := {}   # id -> PanelContainer（右：只读原始键）
var _status := {}          # id -> Label
var _save_btn: Button = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	changed.connect(_on_changed)

func _on_changed() -> void:
	set_save_enabled(has_changes())

## 用当前映射重建所有行 + 保存按钮（打开页时调用；同时重置待保存状态）。
func setup(current_map: Dictionary, _reserved: Array = []) -> void:
	_baseline = current_map.duplicate()
	_pending = current_map.duplicate()
	_capturing = ""
	_chip_btns.clear()
	_default_chips.clear()
	_status.clear()
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
	_save_btn.custom_minimum_size = Vector2(0, 40)
	_save_btn.add_theme_font_size_override("font_size", 20)
	_save_btn.set_meta("board_interactive", true)
	_save_btn.disabled = true
	_save_btn.pressed.connect(func(): save_requested.emit(pending_map()))
	vb.add_child(_save_btn)
	custom_minimum_size = vb.get_combined_minimum_size()

## 表头：左「新按键」右「原始」，与数据行的两格对齐。
func _make_header() -> HBoxContainer:
	var head := HBoxContainer.new()
	head.name = "Header"
	head.add_theme_constant_override("separation", 10)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(LABEL_COL_W + 10.0 + DESC_COL_W, 0)
	head.add_child(pad)
	head.add_child(_head_cell("新按键"))
	head.add_child(_head_cell("原始"))
	return head

func _head_cell(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(KEY_COL_W, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", KeyHintPanel.chip_text_color())
	return lbl

func _make_row(id: String, def: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row_" + id
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = str(def.get("label", id))
	l.custom_minimum_size = Vector2(LABEL_COL_W, 0)
	l.add_theme_font_size_override("font_size", 18)
	row.add_child(l)
	var d := Label.new()
	d.text = str(def.get("desc", ""))
	d.custom_minimum_size = Vector2(DESC_COL_W, 0)
	d.add_theme_font_size_override("font_size", 15)
	row.add_child(d)
	# 左：可重绑的新键（点它进入捕获）
	var chip := Button.new()
	chip.name = "Chip"
	chip.text = OS.get_keycode_string(int(_pending.get(id, 0)))
	chip.custom_minimum_size = Vector2(KEY_COL_W, 32)
	chip.add_theme_font_size_override("font_size", 16)
	chip.set_meta("board_interactive", true)
	for st_name in ["normal", "hover", "pressed", "disabled"]:
		chip.add_theme_stylebox_override(st_name, KeyHintPanel.chip_style_box())
	chip.add_theme_color_override("font_color", KeyHintPanel.chip_text_color())
	chip.pressed.connect(begin_capture.bind(id))
	row.add_child(chip)
	# 右：原始默认键（只读参考，变暗、不可点）
	var dchip := KeyHintPanel.make_chip(OS.get_keycode_string(int(def.get("default", 0))), 16)
	dchip.name = "Default"
	dchip.custom_minimum_size = Vector2(KEY_COL_W, 32)
	dchip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dchip.modulate = Color(1, 1, 1, 0.55)
	var dkey: Label = dchip.get_node_or_null("Key")
	if dkey != null:
		dkey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dchip)
	var status := Label.new()
	status.name = "Status"
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", ERR_COLOR)
	row.add_child(status)
	_chip_btns[id] = chip
	_default_chips[id] = dchip
	_status[id] = status
	return row

func begin_capture(id: String) -> void:
	if _capturing != "":
		cancel_capture()
	_capturing = id
	_chip_btns[id].text = CAPTURE_TEXT

## 由 main 捕获下一个 keydown 后调用。
func capture_key(keycode: int) -> void:
	if _capturing == "":
		return
	var id := _capturing
	var res: Dictionary = KeybindModel.rebind(_pending, id, keycode)
	if not bool(res.get("ok", false)):
		_status[id].text = RESERVED_TEXT if str(res.get("error", "")) == KeybindModel.ERR_RESERVED else "无效"
		return
	_pending = res.get("map")
	_capturing = ""
	_status[id].text = ""
	refresh_chips()
	changed.emit()

func cancel_capture() -> void:
	if _capturing == "":
		return
	var id := _capturing
	_capturing = ""
	_status[id].text = ""
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
