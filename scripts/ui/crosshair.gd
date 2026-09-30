class_name Crosshair
extends Control
## 屏幕中心准星（仅 3D 预览时显示）。悬停到可点目标时变金色并放大。

var active := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	queue_redraw()

func _draw() -> void:
	var col := Color(1.0, 0.85, 0.35, 0.98) if active else Color(1, 1, 1, 0.9)
	var r := 14.0 if active else 11.0
	draw_line(Vector2(-r, 0), Vector2(-3, 0), col, 2.0)
	draw_line(Vector2(3, 0), Vector2(r, 0), col, 2.0)
	draw_line(Vector2(0, -r), Vector2(0, -3), col, 2.0)
	draw_line(Vector2(0, 3), Vector2(0, r), col, 2.0)
	draw_circle(Vector2.ZERO, 2.0 if active else 1.5, col)
