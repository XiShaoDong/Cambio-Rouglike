class_name Crosshair
extends Control
## 屏幕中心准星（仅 3D 预览时显示）。

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var col := Color(1, 1, 1, 0.9)
	draw_line(Vector2(-11, 0), Vector2(-3, 0), col, 2.0)
	draw_line(Vector2(3, 0), Vector2(11, 0), col, 2.0)
	draw_line(Vector2(0, -11), Vector2(0, -3), col, 2.0)
	draw_line(Vector2(0, 3), Vector2(0, 11), col, 2.0)
	draw_circle(Vector2.ZERO, 1.5, col)
