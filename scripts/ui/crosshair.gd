class_name Crosshair
extends Control
## 屏幕中心准星（仅 3D 预览时显示）。悬停到可点目标时变金色并放大。

var active := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	queue_redraw()

func _draw() -> void:
	var col := UITheme.color("highlight_glow") if active else Color(1, 1, 1, 0.55)
	var r := 10.0 if active else 9.0
	# 圆环 + 中心点：悬停可点目标时变金色。
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, col, 3.0 if active else 2.0, true)
	draw_circle(Vector2.ZERO, 3.0 if active else 2.5, col)
