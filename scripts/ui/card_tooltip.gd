class_name CardTooltip
extends Control
## 3D 大牌 hover 的聊天气泡（屏幕空间）：圆角气泡 + 指向卡牌的小尾巴。
## 只做展示；位置由 main 用相机投影的大牌屏幕坐标喂入。

const FONT := 18
const BG := Color(0.08, 0.09, 0.12, 0.92)
const BORDER := Color(1.0, 1.0, 1.0, 0.25)
const TEXT := Color(0.95, 0.97, 1.0)
const TAIL := 10.0
const MAX_W := 320.0
const GAP := 26.0

var _bubble: PanelContainer
var _label: Label
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
	visible = false

## 在 target（屏幕坐标）附近显示气泡；每帧可重复调用以跟随相机。
func show_text(text: String, target: Vector2) -> void:
	if text.is_empty():
		hide_tip()
		return
	_label.text = text
	_target = target
	_shown = true
	visible = true
	_layout()

func hide_tip() -> void:
	_shown = false
	visible = false
	queued_draw_clear()

func text() -> String:
	return _label.text if _label != null else ""

func is_shown() -> bool:
	return _shown

func _layout() -> void:
	_label.custom_minimum_size.x = 0.0
	var sz := _bubble.get_combined_minimum_size()
	if sz.x > MAX_W:
		_label.custom_minimum_size.x = MAX_W - 24.0
		sz = _bubble.get_combined_minimum_size()
	var pos := _target + Vector2(-sz.x * 0.5, -sz.y - GAP)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, size.x - sz.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, size.y - sz.y - 8.0))
	_bubble.position = pos
	_bubble.size = sz
	queue_redraw()

func _draw() -> void:
	if not _shown:
		return
	var b := Rect2(_bubble.position, _bubble.size)
	var from := Vector2(b.position.x + b.size.x * 0.5, b.end.y)
	var tri := PackedVector2Array([
		from + Vector2(-TAIL, 0.0),
		from + Vector2(TAIL, 0.0),
		_target,
	])
	draw_colored_polygon(tri, BG)

func queued_draw_clear() -> void:
	queue_redraw()
