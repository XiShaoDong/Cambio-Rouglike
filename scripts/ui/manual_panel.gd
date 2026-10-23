class_name ManualPanel
extends Control
## 手册 / Stats 面板（3D 全息看板）：顶部页签，两页内容。
## - 手册：三列（牌 / 能力 / 分数），数据来自 `ManualModel.rows()`。
## - Stats：弃牌堆出现过的牌，4 行花色扇形展开（`StatsBoard`）。
## 纯展示，无规则交互。Tab 打开手册页、S 打开 Stats 页、Esc 关闭。

const COL_RANK := 72.0
const COL_SCORE := 72.0
const COL_POWER := 300.0
const TEXT := Color(0.10, 0.12, 0.16)
const TEXT_MUTED := Color(0.32, 0.36, 0.42)
const HEADER := Color(0.16, 0.20, 0.28)
const TAB_MANUAL := 0
const TAB_STATS := 1
const TAB_KEYS := 2

var _tab := TAB_MANUAL
var _tab_manual: Button
var _tab_stats: Button
var _grid: GridContainer
var _stats: StatsBoard
signal save_confirmed(new_map: Dictionary)
var _keymap: KeymapBoard
var _tab_keys: Button
var _confirm: Control

func _ready() -> void:
	_style_panel()
	_build_tabs()
	_build_grid()
	_build_stats()
	_build_keymap()
	_build_confirm()
	set_tab(_tab)

func _style_panel() -> void:
	var panel: PanelContainer = get_node("Center/Panel")
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.90, 0.92, 0.96, 0.82)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(24)
	style.border_color = Color(1.0, 1.0, 1.0, 0.55)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)

func _build_tabs() -> void:
	var vbox: VBoxContainer = get_node("Center/Panel/VBox")
	var bar := HBoxContainer.new()
	bar.name = "Tabs"
	bar.add_theme_constant_override("separation", 8)
	vbox.add_child(bar)
	vbox.move_child(bar, 1)  # 放在 Title 之后、Hint 之前
	# PS 式左右“切页”提示键（纯展示，不拦截点击）：Q ◀ …… ▶ E
	var hint_left := KeyHintPanel.make_chip("Q ◀", 15, 8)
	hint_left.name = "TabHintLeft"
	hint_left.tooltip_text = "Q：左切页签"
	hint_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(hint_left)
	var spacer_l := Control.new()
	spacer_l.name = "SpacerL"
	spacer_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer_l)
	_tab_manual = _tab_button("手册")
	_tab_manual.pressed.connect(func(): set_tab(TAB_MANUAL))
	bar.add_child(_tab_manual)
	_tab_stats = _tab_button("Stats")
	_tab_stats.pressed.connect(func(): set_tab(TAB_STATS))
	bar.add_child(_tab_stats)
	_tab_keys = _tab_button("按键")
	_tab_keys.pressed.connect(func(): set_tab(TAB_KEYS))
	bar.add_child(_tab_keys)
	var spacer_r := Control.new()
	spacer_r.name = "SpacerR"
	spacer_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer_r)
	var hint_right := KeyHintPanel.make_chip("E ▶", 15, 8)
	hint_right.name = "TabHintRight"
	hint_right.tooltip_text = "E：右切页签"
	hint_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(hint_right)
	var hint: Label = get_node("Center/Panel/VBox/Hint")
	hint.add_theme_color_override("font_color", TEXT_MUTED)
	hint.text = "Tab 手册 / S Stats / K 按键 / Q·E 切页 / Esc 关闭"

func _tab_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(88.0, 0.0)
	btn.add_theme_font_size_override("font_size", 18)
	btn.set_meta("board_interactive", true)
	return btn

func _build_grid() -> void:
	var title: Label = get_node("Center/Panel/VBox/Title")
	title.add_theme_color_override("font_color", HEADER)
	_grid = get_node("Center/Panel/VBox/Grid")
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 28)
	_grid.add_theme_constant_override("v_separation", 6)
	_grid.add_child(_cell("牌", COL_RANK, true, true))
	_grid.add_child(_cell("能力", COL_POWER, true, false))
	_grid.add_child(_cell("分数", COL_SCORE, true, true))
	for entry in ManualModel.rows():
		_grid.add_child(_cell(str(entry.rank), COL_RANK, false, true))
		_grid.add_child(_cell(str(entry.power), COL_POWER, false, false))
		_grid.add_child(_cell(str(entry.score), COL_SCORE, false, true))

func _build_stats() -> void:
	var vbox: VBoxContainer = get_node("Center/Panel/VBox")
	_stats = StatsBoard.new()
	_stats.name = "Stats"
	vbox.add_child(_stats)
	_stats.visible = false

func _cell(text: String, width: float, header: bool, center: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(width, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	lbl.add_theme_font_size_override("font_size", 20 if header else 18)
	lbl.add_theme_color_override("font_color", HEADER if header else TEXT)
	return lbl

## 切换页签（0=手册，1=Stats，2=按键）。
func set_tab(index: int) -> void:
	_tab = index if index in [TAB_MANUAL, TAB_STATS, TAB_KEYS] else TAB_MANUAL
	var title: Label = get_node("Center/Panel/VBox/Title")
	if _grid != null:
		_grid.visible = _tab == TAB_MANUAL
	if _stats != null:
		_stats.visible = _tab == TAB_STATS
	if _keymap != null:
		_keymap.visible = _tab == TAB_KEYS
	if title != null:
		title.text = "Stats · 弃牌堆" if _tab == TAB_STATS else ("按键映射" if _tab == TAB_KEYS else "手册")
	if _tab_manual != null:
		_tab_manual.disabled = _tab == TAB_MANUAL
	if _tab_stats != null:
		_tab_stats.disabled = _tab == TAB_STATS
	if _tab_keys != null:
		_tab_keys.disabled = _tab == TAB_KEYS

## 填充 Stats 数据（弃牌历史）。
func setup_stats(history: Array) -> void:
	if _stats != null:
		_stats.setup(history)

## 测试访问器。
func current_tab() -> int:
	return _tab

func grid_columns() -> int:
	return _grid.columns

func stats_board() -> StatsBoard:
	return _stats

func _build_keymap() -> void:
	_keymap = KeymapBoard.new()
	_keymap.name = "Keymap"
	var vbox: VBoxContainer = get_node("Center/Panel/VBox")
	vbox.add_child(_keymap)
	_keymap.visible = false
	_keymap.setup(KeybindModel.defaults(), KeybindModel.RESERVED)
	_keymap.save_requested.connect(func(_m): open_confirm())

func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.name = "ConfirmOverlay"
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.visible = false
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.set_meta("board_interactive", true)
	_confirm.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.90, 0.92, 0.96, 0.97)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(24)
	style.border_color = Color(1, 1, 1, 0.6)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)
	var lbl := Label.new()
	lbl.text = "确认保存当前按键映射？"
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", HEADER)
	vb.add_child(lbl)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	var ok := Button.new()
	ok.name = "ConfirmOk"
	ok.text = "确认"
	ok.custom_minimum_size = Vector2(120, 44)
	ok.add_theme_font_size_override("font_size", 20)
	ok.set_meta("board_interactive", true)
	ok.pressed.connect(on_confirm_save)
	hb.add_child(ok)
	var cancel := Button.new()
	cancel.name = "ConfirmCancel"
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(120, 44)
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.set_meta("board_interactive", true)
	cancel.pressed.connect(on_confirm_cancel)
	hb.add_child(cancel)
	add_child(_confirm)

func setup_keymap(current_map: Dictionary, reserved: Array) -> void:
	if _keymap != null:
		_keymap.setup(current_map, reserved)

func keymap_board() -> KeymapBoard:
	return _keymap

func open_confirm() -> void:
	if _confirm != null:
		_confirm.visible = true

func confirm_visible() -> bool:
	return _confirm != null and _confirm.visible

func on_confirm_save() -> void:
	if _confirm != null:
		_confirm.visible = false
	if _keymap != null:
		_keymap.commit()
		_keymap.set_save_enabled(false)
		save_confirmed.emit(_keymap.pending_map())

func on_confirm_cancel() -> void:
	if _confirm != null:
		_confirm.visible = false

func capturing() -> String:
	return _keymap.capturing() if _keymap != null else ""

func capture_key(keycode: int) -> void:
	if _keymap != null:
		_keymap.capture_key(keycode)

func cancel_capture() -> void:
	if _keymap != null:
		_keymap.cancel_capture()
