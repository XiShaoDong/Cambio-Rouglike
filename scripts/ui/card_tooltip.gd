class_name CardTooltip
extends Control
## 3D 卡牌 hover 信息气泡（屏幕空间）。支持两种形态：
## - 旧能力气泡：单/双框，统一 360 宽。
## - 状态气泡：E 区 hover 变体，标题/正文/状态条/状态色描边。

const FONT := 14
const TITLE_FONT := 16
const NOTE_FONT := 12
const FIXED_W := 360.0
const BAR_W := 4.0
const BAR_GAP := 8.0
const GAP_X := 10.0
const GAP_Y := 10.0

var _bubble: PanelContainer
var _tint: ColorRect
var _hbox: HBoxContainer
var _bar: ColorRect
var _text_box: VBoxContainer
var _title: Label
var _label: Label
var _state_note: Label
var _state := ""
var _style: StyleBoxFlat
var _shown := false
var _bubble2: PanelContainer
var _label2: Label
var _note_shown := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.custom_minimum_size.x = FIXED_W
	_style = UIStyle.tooltip(false)
	_bubble.add_theme_stylebox_override("panel", _style)
	add_child(_bubble)
	_tint = ColorRect.new()
	_tint.name = "StateTint"
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.visible = false
	_bubble.add_child(_tint)
	_hbox = HBoxContainer.new()
	_hbox.name = "Box"
	_hbox.add_theme_constant_override("separation", int(BAR_GAP))
	_bubble.add_child(_hbox)
	_bar = ColorRect.new()
	_bar.name = "StateBar"
	_bar.custom_minimum_size.x = BAR_W
	_bar.size_flags_vertical = Control.SIZE_FILL
	_bar.visible = false
	_hbox.add_child(_bar)
	_text_box = VBoxContainer.new()
	_text_box.name = "TextBox"
	_text_box.add_theme_constant_override("separation", 2)
	_text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hbox.add_child(_text_box)
	_title = Label.new()
	_title.name = "Title"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", TITLE_FONT)
	_title.visible = false
	_text_box.add_child(_title)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = FIXED_W - 20.0
	_label.add_theme_font_size_override("font_size", FONT)
	_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	_text_box.add_child(_label)
	_state_note = Label.new()
	_state_note.name = "StateNote"
	_state_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_state_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_state_note.custom_minimum_size.x = FIXED_W - 20.0
	_state_note.add_theme_font_size_override("font_size", NOTE_FONT)
	_state_note.add_theme_color_override("font_color", UITheme.color("hud_text_muted"))
	_state_note.visible = false
	_text_box.add_child(_state_note)

	# 第二框（旧能力触发提示）：出现在第一气泡正下方。
	_bubble2 = PanelContainer.new()
	_bubble2.name = "BubbleNote"
	_bubble2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble2.custom_minimum_size.x = FIXED_W
	_bubble2.add_theme_stylebox_override("panel", _make_style())
	_label2 = Label.new()
	_label2.name = "Text"
	_label2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label2.custom_minimum_size.x = FIXED_W - 20.0
	_label2.add_theme_font_size_override("font_size", FONT)
	_label2.add_theme_color_override("font_color", UITheme.color("accent_focus"))
	_bubble2.add_child(_label2)
	add_child(_bubble2)
	visible = false

## 第二框：accent_soft 底 + accent_focus 描边。
func _make_style() -> StyleBoxFlat:
	return UIStyle.tooltip(true)

func _set_content(state: String, title: String, body: String, note: String) -> void:
	_state = state
	_title.text = title
	_title.visible = not title.is_empty()
	_label.text = body
	_state_note.text = note
	_state_note.visible = not note.is_empty()
	var has_state := not state.is_empty()
	_bar.visible = has_state
	if has_state:
		_bar.color = UIStyle.hover_color(state)
		_tint.visible = true
		_tint.color = UIStyle.hover_color(state)
		_tint.color.a = 0.10
		_bubble.add_theme_stylebox_override("panel", UIStyle.info_box(state))
		_title.add_theme_color_override("font_color", UIStyle.hover_color(state))
		_label.custom_minimum_size.x = FIXED_W - 20.0 - BAR_W - BAR_GAP
		_title.custom_minimum_size.x = FIXED_W - 20.0 - BAR_W - BAR_GAP
		_state_note.custom_minimum_size.x = FIXED_W - 20.0 - BAR_W - BAR_GAP
	else:
		_tint.visible = false
		_bubble.add_theme_stylebox_override("panel", UIStyle.tooltip(false))
		_label.custom_minimum_size.x = FIXED_W - 20.0
		_title.custom_minimum_size.x = FIXED_W - 20.0
		_state_note.custom_minimum_size.x = FIXED_W - 20.0

func _hide_note() -> void:
	_label2.text = ""
	_bubble2.visible = false
	_note_shown = false

## 在卡牌屏幕矩形右上角外侧显示一行气泡文案。
func show_line(text: String, card_rect: Rect2) -> void:
	if text.is_empty():
		hide_tip()
		return
	_set_content("", "", text, "")
	_hide_note()
	var sz := _bubble.get_combined_minimum_size()
	var pos := Vector2(card_rect.end.x + GAP_X, card_rect.position.y - sz.y - GAP_Y)
	_place(pos, sz)

## 第一框显示能力文案；note 非空时在其正下方再弹第二框（能力触发提示）。
func show_with_note(text: String, note: String, card_rect: Rect2) -> void:
	if text.is_empty():
		hide_tip()
		return
	_set_content("", "", text, "")
	var sz := _bubble.get_combined_minimum_size()
	var pos := Vector2(card_rect.end.x + GAP_X, card_rect.position.y - sz.y - GAP_Y)
	_place(pos, sz)
	if note.is_empty():
		_hide_note()
		return
	_label2.text = note
	var sz2 := _bubble2.get_combined_minimum_size()
	var pos2 := Vector2(pos.x, pos.y + sz.y + GAP_Y)
	_place2(pos2, sz2)

## 状态气泡：标题 + 正文 + 状态条/状态色描边（E 区 Hover/Info）。
func show_state(state: String, title: String, body: String, note: String, card_rect: Rect2) -> void:
	if state.is_empty() or (title.is_empty() and body.is_empty()):
		hide_tip()
		return
	_set_content(state, title, body, note)
	_hide_note()
	var sz := _bubble.get_combined_minimum_size()
	var pos := Vector2(card_rect.end.x + GAP_X, card_rect.position.y - sz.y - GAP_Y)
	_place(pos, sz)

func hide_tip() -> void:
	_shown = false
	_note_shown = false
	visible = false

func note_text() -> String:
	return _label2.text if _label2 != null else ""

func note_shown() -> bool:
	return _note_shown

func text() -> String:
	return _label.text if _label != null else ""

func title_text() -> String:
	return _title.text if _title != null else ""

func state_note_text() -> String:
	return _state_note.text if _state_note != null else ""

func state() -> String:
	return _state

func is_shown() -> bool:
	return _shown

func bubble_size() -> Vector2:
	return _bubble.get_combined_minimum_size() if _bubble != null else Vector2.ZERO

func _place(pos: Vector2, sz: Vector2) -> void:
	pos.x = clampf(pos.x, 8.0, maxf(8.0, size.x - sz.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, size.y - sz.y - 8.0))
	_bubble.position = pos
	_bubble.size = sz
	_shown = true
	visible = true

func _place2(pos: Vector2, sz: Vector2) -> void:
	pos.x = clampf(pos.x, 8.0, maxf(8.0, size.x - sz.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, size.y - sz.y - 8.0))
	_bubble2.position = pos
	_bubble2.size = sz
	_note_shown = true
	_bubble2.visible = true
