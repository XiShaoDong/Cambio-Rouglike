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
	var col := Color(1.0, 0.85, 0.35, 0.98) if active else Color(1, 1, 1, 0.9)
	var r := 4.0 if active else 3.0
	# 单点准星：深色描边保证在亮/暗背景上都看得见。
	draw_circle(Vector2.ZERO, r + 1.2, Color(0, 0, 0, 0.55))
	draw_circle(Vector2.ZERO, r, col)
