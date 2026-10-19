class_name CardTooltip
extends Control
## 3D 大牌 hover 的聊天气泡（屏幕空间）：圆角气泡 + 指向卡牌的三角形尖角。
## 位置由 main 用相机投影的大牌屏幕矩形喂入（默认放在卡牌右上角外侧）。

const FONT := 18
const BG := Color(0.08, 0.09, 0.12, 0.92)
const BORDER := Color(1.0, 1.0, 1.0, 0.25)
const TEXT := Color(0.95, 0.97, 1.0)
const TAIL := 9.0          # 尖角底边半宽
const MAX_W := 320.0
const GAP_X := 26.0        # 气泡在卡牌右侧的外扩
const GAP_Y := 20.0        # 气泡在卡牌上方的外扩
const ABOVE_GAP := 26.0

var _bubble: PanelContainer
var _label: Label
var _tail: Polygon2D
var _target := Vector2.ZERO
var _shown := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.set_corner_radius_all(14)
	style.set_content_margin_all(12)
	style.border_color = BORDER
	style.set_border_width_all(1)
	_bubble.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", FONT)
	_label.add_theme_color_override("font_color", TEXT)
	_bubble.add_child(_label)
	add_child(_bubble)
	# 尖角单独用 Polygon2D（在气泡之后添加 → 画在气泡上层，保证可见）。
	_tail = Polygon2D.new()
	_tail.name = "Tail"
	_tail.color = BG
	add_child(_tail)
	visible = false

## 放在卡牌屏幕矩形的**右上角外侧**，尖角指向卡牌右上角。
func show_beside(text: String, card_rect: Rect2) -> void:
	if text.is_empty():
		hide_tip()
		return
	_prepare(text)
	var sz := _bubble.get_combined_minimum_size()
	var pos := Vector2(card_rect.end.x + GAP_X, card_rect.position.y - sz.y - GAP_Y)
	_place(pos, sz, Vector2(card_rect.end.x, card_rect.position.y))

## 在 target 正上方显示（备用/测试）。
func show_text(text: String, target: Vector2) -> void:
	if text.is_empty():
		hide_tip()
		return
	_prepare(text)
	var sz := _bubble.get_combined_minimum_size()
	var pos := target + Vector2(-sz.x * 0.5, -sz.y - ABOVE_GAP)
	_place(pos, sz, target)

func hide_tip() -> void:
	_shown = false
	visible = false
	if _tail != null:
		_tail.polygon = PackedVector2Array()

func text() -> String:
	return _label.text if _label != null else ""

func is_shown() -> bool:
	return _shown

func bubble_size() -> Vector2:
	return _bubble.get_combined_minimum_size() if _bubble != null else Vector2.ZERO

func tail_points() -> PackedVector2Array:
	return _tail.polygon if _tail != null else PackedVector2Array()

## 先量出文本宽度，给 Label 一个非零最小宽度（否则 autowrap 的最小宽为 0 → 气泡没宽度）。
func _prepare(text: String) -> void:
	_label.text = text
	var font := _label.get_theme_font("font")
	var fs := _label.get_theme_font_size("font_size")
	if font != null:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_label.custom_minimum_size.x = minf(MAX_W - 24.0, w + 2.0)

func _place(pos: Vector2, sz: Vector2, tail_target: Vector2) -> void:
	pos.x = clampf(pos.x, 8.0, maxf(8.0, size.x - sz.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, size.y - sz.y - 8.0))
	_bubble.position = pos
	_bubble.size = sz
	_target = tail_target
	_shown = true
	visible = true
	_update_tail(Rect2(pos, sz), tail_target)

## 尖角：锚在气泡下边缘（避开圆角），三角形指向目标点。
func _update_tail(b: Rect2, target: Vector2) -> void:
	var anchor := Vector2(clampf(target.x, b.position.x + 16.0, b.end.x - 16.0), b.end.y)
	var dir := target - anchor
	if dir.length() < 0.5:
		dir = Vector2(0.0, 1.0)
		anchor = Vector2(b.position.x + 16.0, b.end.y)
	dir = dir.normalized()
	var nrm := Vector2(-dir.y, dir.x) * TAIL
	_tail.polygon = PackedVector2Array([anchor - nrm, anchor + nrm, target])
