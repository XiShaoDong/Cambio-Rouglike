class_name CoinIcon
extends Control
## 程序化铜钱图标：外圆 + 内方孔。无图片资源依赖。

var color := Color.WHITE

func setup(p_color: Color) -> void:
	color = p_color
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 1.5
	draw_arc(c, r, 0.0, TAU, 32, color, 2.0, true)
	var h := r * 0.45
	var hole := Rect2(c - Vector2(h, h), Vector2(h * 2.0, h * 2.0))
	draw_rect(hole, color, false, 2.0)
