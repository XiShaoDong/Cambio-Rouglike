class_name LifeIcon
extends Control
## 程序化心形生命图标。无图片资源依赖。

var color := Color.WHITE

func setup(p_color: Color) -> void:
	color = p_color
	queue_redraw()

func _draw() -> void:
	var s := minf(size.x, size.y)
	var center := size * 0.5
	var r := s * 0.26
	draw_circle(center + Vector2(-r * 0.9, -r * 0.5), r, color)
	draw_circle(center + Vector2(r * 0.9, -r * 0.5), r, color)
	var pts := PackedVector2Array([
		center + Vector2(-r * 1.85, -r * 0.1),
		center + Vector2(r * 1.85, -r * 0.1),
		center + Vector2(0, r * 1.9),
	])
	draw_colored_polygon(pts, color)
