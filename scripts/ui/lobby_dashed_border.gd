class_name LobbyDashedBorder
extends Control
## 空席位虚线边框（低对比度；纯绘制，不拦截点击）。

var color := Color(1, 1, 1, 0.22)
var dash := 6.0
var gap := 5.0
var width := 1.5

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 4.0 or size.y <= 4.0:
		return
	var a := Vector2(2, 2)
	var b := Vector2(size.x - 2, 2)
	var c := Vector2(size.x - 2, size.y - 2)
	var d := Vector2(2, size.y - 2)
	draw_dashed_line(a, b, color, width, dash, true, true)
	draw_dashed_line(b, c, color, width, dash, true, true)
	draw_dashed_line(c, d, color, width, dash, true, true)
	draw_dashed_line(d, a, color, width, dash, true, true)
