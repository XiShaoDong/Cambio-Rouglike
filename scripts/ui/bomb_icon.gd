class_name BombIcon
extends Control
## 程序化炸弹小图标（无需素材）：黑色圆身 + 引线 + 火花。纯展示。

const BODY := Color(0.05, 0.05, 0.06)
const FUSE := Color(0.45, 0.33, 0.12)
const SPARK := Color(1.0, 0.62, 0.12)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(18, 18)

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.30
	draw_circle(c + Vector2(0.0, r * 0.25), r, BODY)
	draw_line(c + Vector2(r * 0.55, -r * 0.55), c + Vector2(r * 1.25, -r * 1.55), FUSE, 2.0)
	draw_circle(c + Vector2(r * 1.25, -r * 1.55), 2.0, SPARK)
