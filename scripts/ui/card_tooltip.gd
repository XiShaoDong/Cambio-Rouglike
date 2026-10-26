class_name CardTooltip
extends Control
## 3D 卡牌 hover 信息气泡（屏幕空间）：单行文案（长文本自动换行），统一固定宽度。
## 放在卡牌右上角外侧（贴近、不重叠）；位置由 main 用相机投影的卡牌屏幕矩形喂入。

const FONT := 16
const BG := Color(0.08, 0.09, 0.12, 0.92)
const BORDER := Color(1.0, 1.0, 1.0, 0.25)
const TEXT := Color(0.95, 0.97, 1.0)
const FIXED_W := 240.0     # 统一固定气泡宽度（高度随换行自适应）
const GAP_X := 10.0
const GAP_Y := 10.0

var _bubble: PanelContainer
var _label: Label
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
	_style = StyleBoxFlat.new()
	_style.bg_color = BG
	_style.set_corner_radius_all(14)
	_style.set_content_margin_all(10)
	_style.border_color = BORDER
	_style.set_border_width_all(1)
	_bubble.add_theme_stylebox_override("panel", _style)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = FIXED_W - 20.0
	_label.add_theme_font_size_override("font_size", FONT)
	_label.add_theme_color_override("font_color", TEXT)
	_bubble.add_child(_label)
	add_child(_bubble)
	# 第二框（能力提示："点击弃牌堆以触发能力"）——出现在第一气泡正下方。
	_bubble2 = PanelContainer.new()
	_bubble2.name = "BubbleNote"
	_bubble2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble2.add_theme_stylebox_override("panel", _make_style())
	_label2 = Label.new()
	_label2.name = "Text"
	_label2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label2.custom_minimum_size.x = FIXED_W - 20.0
	_label2.add_theme_font_size_override("font_size", FONT)
	_label2.add_theme_color_override("font_color", TEXT)
	_bubble2.add_child(_label2)
	add_child(_bubble2)
	visible = false

## 样式构造复用（第一/第二气泡同款深色圆角）。
func _make_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.set_corner_radius_all(14)
	style.set_content_margin_all(10)
	style.border_color = BORDER
	style.set_border_width_all(1)
	return style

## 在卡牌屏幕矩形右上角外侧显示一行气泡文案。
func show_line(text: String, card_rect: Rect2) -> void:
	if text.is_empty():
		hide_tip()
		return
	_label.text = text
	var sz := _bubble.get_combined_minimum_size()
	var pos := Vector2(card_rect.end.x + GAP_X, card_rect.position.y - sz.y - GAP_Y)
	_place(pos, sz)

## 第一框显示能力文案；note 非空时在其正下方再弹第二框（能力触发提示）。
func show_with_note(text: String, note: String, card_rect: Rect2) -> void:
	if text.is_empty():
		hide_tip()
		return
	_label.text = text
	var sz := _bubble.get_combined_minimum_size()
	var pos := Vector2(card_rect.end.x + GAP_X, card_rect.position.y - sz.y - GAP_Y)
	_place(pos, sz)
	if note.is_empty():
		_label2.text = ""
		_bubble2.visible = false
		_note_shown = false
		return
	_label2.text = note
	var sz2 := _bubble2.get_combined_minimum_size()
	# 第二框贴第一框正下方：x 与第一框左缘对齐、y = 第一框 bottom + 间距
	var pos2 := Vector2(pos.x, pos.y + sz.y + GAP_Y)
	_place2(pos2, sz2)

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
