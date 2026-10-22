class_name HandSilhouette2D
extends ItemHandArt
## 默认 2D 手部占位：深色袖口 + 手掌 + 拇指，纯程序化绘制。
## 替换时新建一个 extends ItemHandArt 的节点/场景，赋给 ItemHandOverlay.hand_art_scene 即可。

const SLEEVE_COLOR := Color(0.12, 0.13, 0.17, 0.96)
const PALM_COLOR := Color(0.20, 0.22, 0.28, 0.98)
const OUTLINE := Color(0.02, 0.02, 0.03, 0.95)

var hand_rect := Rect2()
var _selected := 0
var _count := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func setup(p_hand_rect: Rect2) -> void:
	hand_rect = p_hand_rect
	queue_redraw()

func play_open() -> void:
	visible = true
	modulate.a = 1.0

func play_close(_immediate: bool) -> void:
	visible = false

func set_selected_hint(index: int, count: int) -> void:
	_selected = index
	_count = count
	queue_redraw()

func _draw() -> void:
	if hand_rect.size.x <= 0.0 or hand_rect.size.y <= 0.0:
		return
	var r := hand_rect
	var cx := r.position.x + r.size.x * 0.5
	var top := r.position.y
	var bottom := r.end.y
	var palm_w := r.size.x * 0.46
	var palm_h := r.size.y * 0.42
	var palm := Rect2(Vector2(cx - palm_w * 0.5, top + r.size.y * 0.22), Vector2(palm_w, palm_h))
	# 袖口（从屏幕底部伸上来）
	var sleeve := PackedVector2Array([
		Vector2(cx - palm_w * 0.43, palm.position.y + palm.size.y * 0.55),
		Vector2(cx + palm_w * 0.43, palm.position.y + palm.size.y * 0.55),
		Vector2(cx + palm_w * 0.62, bottom),
		Vector2(cx - palm_w * 0.62, bottom),
	])
	draw_colored_polygon(sleeve, SLEEVE_COLOR)
	draw_polyline(sleeve + PackedVector2Array([sleeve[0]]), OUTLINE, 2.0, true)
	# 手掌（圆角多边形）
	var palm_pts := _rounded_rect_points(palm, 24.0)
	draw_colored_polygon(palm_pts, PALM_COLOR)
	draw_polyline(palm_pts + PackedVector2Array([palm_pts[0]]), OUTLINE, 2.0, true)
	# 拇指：从手掌左下/右下伸出（按选中轻微偏移）
	var thumb_side := -1.0 if _selected <= 0 else -1.0
	var thumb_center := Vector2(cx + thumb_side * palm_w * 0.56, palm.position.y + palm.size.y * 0.48)
	draw_circle(thumb_center, palm_w * 0.13, PALM_COLOR)
	draw_arc(thumb_center, palm_w * 0.13, 0.0, TAU, 24, OUTLINE, 2.0)
	# 手指缝（简单三条短线，增强手型）
	for i in 3:
		var x := cx + (float(i) - 1.0) * palm_w * 0.16
		draw_line(Vector2(x, palm.position.y + palm.size.y * 0.12), Vector2(x, palm.position.y + palm.size.y * 0.34), Color(0, 0, 0, 0.35), 2.0)

func _rounded_rect_points(rect: Rect2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var corners := [
		{"c": rect.position + Vector2(r, r), "a": PI, "b": PI * 1.5},
		{"c": Vector2(rect.end.x - r, rect.position.y + r), "a": PI * 1.5, "b": TAU},
		{"c": Vector2(rect.end.x - r, rect.end.y - r), "a": 0.0, "b": PI * 0.5},
		{"c": Vector2(rect.position.x + r, rect.end.y - r), "a": PI * 0.5, "b": PI},
	]
	for corner in corners:
		for i in 6:
			var a: float = float(corner.a) + (float(corner.b) - float(corner.a)) * (float(i) / 5.0)
			pts.append(corner.c + Vector2(cos(a), sin(a)) * r)
	return pts
