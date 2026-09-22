class_name CardCountIcon
extends Control
## 程序化「卡牌数」图标：圆角矩形描边 + 内框。风格同 CoinIcon/LifeIcon。

var color := Color.WHITE

func setup(p_color: Color) -> void:
	color = p_color
	queue_redraw()

func _draw() -> void:
	var m := 3.0
	var r := Rect2(Vector2(m, m), size - Vector2(m, m) * 2.0)
	draw_rect(r, color, false, 2.0)
	var pad := Vector2(r.size.x, r.size.y) * 0.26
	draw_rect(Rect2(r.position + pad, r.size - pad * 2.0), color, false, 1.5)
