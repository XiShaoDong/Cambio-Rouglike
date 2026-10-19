class_name CardTooltip
extends Control
## 3D 大牌 hover 的气泡提示（屏幕空间）：半圆/胶囊文字框，放在卡牌右上角外侧。
## 位置由 main 用相机投影的大牌屏幕矩形喂入。

const FONT := 18
const BG := Color(0.08, 0.09, 0.12, 0.92)
const BORDER := Color(1.0, 1.0, 1.0, 0.25)
const TEXT := Color(0.95, 0.97, 1.0)
const MAX_W := 320.0
const GAP_X := 10.0        # 气泡左缘距卡牌右缘（不重叠）
const GAP_Y := 10.0        # 气泡下缘距卡牌上缘（不重叠）
const ABOVE_GAP := 18.0

var _bubble: PanelContainer
var _label: Label
var _style: StyleBoxFlat
var _shown := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = BG
	_style.set_corner_radius_all(18)
	_style.set_content_margin_all(12)
	_style.border_color = BORDER
	_style.set_border_width_all(1)
	_bubble.add_theme_stylebox_override("panel", _style)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", FONT)
	_label.add_theme_color_override("font_color", TEXT)
	_bubble.add_child(_label)
	add_child(_bubble)
	visible = false

## 放在卡牌屏幕矩形的**右上角外侧**（贴近但不重叠）。
func show_beside(text: String, card_rect: Rect2) -> void:
	if text.is_empty():
		hide_tip()
		return
	_prepare(text)
	var sz := _bubble.get_combined_minimum_size()
	var pos := Vector2(card_rect.end.x + GAP_X, card_rect.position.y - sz.y - GAP_Y)
	_place(pos, sz)

## 在 target 正上方显示（备用/测试）。
func show_text(text: String, target: Vector2) -> void:
	if text.is_empty():
		hide_tip()
		return
	_prepare(text)
	var sz := _bubble.get_combined_minimum_size()
	var pos := target + Vector2(-sz.x * 0.5, -sz.y - ABOVE_GAP)
	_place(pos, sz)

func hide_tip() -> void:
	_shown = false
	visible = false

func text() -> String:
	return _label.text if _label != null else ""

func is_shown() -> bool:
	return _shown

func bubble_size() -> Vector2:
	return _bubble.get_combined_minimum_size() if _bubble != null else Vector2.ZERO

## 先量出文本宽度，给 Label 一个非零最小宽度（否则 autowrap 的最小宽为 0 → 气泡没宽度）。
func _prepare(text: String) -> void:
	_label.text = text
	var font := _label.get_theme_font("font")
	var fs := _label.get_theme_font_size("font_size")
	if font != null:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_label.custom_minimum_size.x = minf(MAX_W - 24.0, w + 2.0)

func _place(pos: Vector2, sz: Vector2) -> void:
	pos.x = clampf(pos.x, 8.0, maxf(8.0, size.x - sz.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, size.y - sz.y - 8.0))
	_bubble.position = pos
	_bubble.size = sz
	# 半圆/胶囊感：圆角取高度一半（有上限，避免超高时过圆）。
	_style.set_corner_radius_all(int(minf(sz.y * 0.5, 28.0)))
	_shown = true
	visible = true
