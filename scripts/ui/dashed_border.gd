class_name DashedBorder
extends Control
## 虚线边框（弃牌堆空位占位提示）。

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var c: Color = UITheme.color("card_back_border")
	draw_dashed_line(rect.position, Vector2(rect.end.x, rect.position.y), c, 2.0, 5.0, true)
	draw_dashed_line(Vector2(rect.end.x, rect.position.y), rect.end, c, 2.0, 5.0, true)
	draw_dashed_line(rect.end, Vector2(rect.position.x, rect.end.y), c, 2.0, 5.0, true)
	draw_dashed_line(Vector2(rect.position.x, rect.end.y), rect.position, c, 2.0, 5.0, true)
