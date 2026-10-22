class_name LobbyDashedBorder
extends Control
## 空席位虚线边框（低对比度；纯绘制，不拦截点击）。
## 支持 rounded corners：四段直边 + 四段虚线圆弧。

var color := Color(1, 1, 1, 0.22)
var dash := 3.0
var gap := 2.6
var width := 1.5
var corner_radius := 10.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 8.0 or size.y <= 8.0:
		return
	var inset := 2.0 + width * 0.5
	var r := minf(corner_radius, minf(size.x, size.y) * 0.5 - inset)
	if r < 0.5:
		# 太小放不下圆角：退化为直角矩形虚线
		var a := Vector2(inset, inset)
		var b := Vector2(size.x - inset, inset)
		var c := Vector2(size.x - inset, size.y - inset)
		var d := Vector2(inset, size.y - inset)
		draw_dashed_line(a, b, color, width, dash, true, true)
		draw_dashed_line(b, c, color, width, dash, true, true)
		draw_dashed_line(c, d, color, width, dash, true, true)
		draw_dashed_line(d, a, color, width, dash, true, true)
		return
	var top_l := Vector2(inset + r, inset)
	var top_r := Vector2(size.x - inset - r, inset)
	var bot_l := Vector2(inset + r, size.y - inset)
	var bot_r := Vector2(size.x - inset - r, size.y - inset)
	var left_t := Vector2(inset, inset + r)
	var left_b := Vector2(inset, size.y - inset - r)
	var right_t := Vector2(size.x - inset, inset + r)
	var right_b := Vector2(size.x - inset, size.y - inset - r)
	# 四段直边
	draw_dashed_line(top_l, top_r, color, width, dash, false, true)
	draw_dashed_line(right_t, right_b, color, width, dash, false, true)
	draw_dashed_line(bot_r, bot_l, color, width, dash, false, true)
	draw_dashed_line(left_b, left_t, color, width, dash, false, true)
	# 四个 90° 圆角虚线圆弧
	_dashed_arc(Vector2(inset + r, inset + r), r, PI, PI * 1.5)          # 左上
	_dashed_arc(Vector2(size.x - inset - r, inset + r), r, PI * 1.5, TAU) # 右上
	_dashed_arc(Vector2(size.x - inset - r, size.y - inset - r), r, 0.0, PI * 0.5)  # 右下
	_dashed_arc(Vector2(inset + r, size.y - inset - r), r, PI * 0.5, PI)            # 左下

func _dashed_arc(center: Vector2, r: float, a0: float, a1: float) -> void:
	var total := absf(a1 - a0) * r
	var dir := signf(a1 - a0)
	var t := 0.0
	while true:
		var seg_end := minf(t + dash, total)
		if seg_end > t:
			var s0 := a0 + (t / r) * dir
			var s1 := a0 + (seg_end / r) * dir
			draw_arc(center, r, minf(s0, s1), maxf(s0, s1), 10, color, width, true)
		t += dash + gap
		if t >= total:
			break
