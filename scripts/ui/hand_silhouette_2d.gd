class_name HandSilhouette2D
extends ItemHandArt
## 默认 2D 手部：哆啦A梦式圆手——大圆手掌 + 单独大拇指胶囊，
## 其余四指并入圆掌整体（不画指缝）。纯程序化绘制。
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
	var bottom := r.end.y
	var palm_r := minf(r.size.x, r.size.y) * 0.30
	var palm_c := Vector2(cx, r.position.y + r.size.y * 0.55)
	# 袖口（从屏幕底部伸上来，画在掌后）
	var sleeve_w := palm_r * 1.35
	var sleeve := PackedVector2Array([
		Vector2(cx - sleeve_w * 0.5, palm_c.y + palm_r * 0.35),
		Vector2(cx + sleeve_w * 0.5, palm_c.y + palm_r * 0.35),
		Vector2(cx + sleeve_w * 0.72, bottom),
		Vector2(cx - sleeve_w * 0.72, bottom),
	])
	draw_colored_polygon(sleeve, SLEEVE_COLOR)
	draw_polyline(sleeve + PackedVector2Array([sleeve[0]]), OUTLINE, 2.0, true)
	# 手掌：一个完整大圆（四指并入掌心，不画指缝）
	draw_circle(palm_c, palm_r, PALM_COLOR)
	draw_arc(palm_c, palm_r, 0.0, TAU, 48, OUTLINE, 2.0, true)
	# 拇指：独立胶囊（从掌心左下朝左上伸出），随选中第一张时轻微偏移
	var t0 := palm_c + Vector2(-palm_r * 0.55, palm_r * 0.38)
	var t1 := t0 + Vector2(-palm_r * 0.62, -palm_r * 0.78)
	var thumb_r := palm_r * 0.30
	# 描边层（略宽 + 两端圆头）
	draw_line(t0, t1, OUTLINE, thumb_r * 2.0 + 3.0, true)
	draw_circle(t0, thumb_r + 1.5, OUTLINE)
	draw_circle(t1, thumb_r + 1.5, OUTLINE)
	# 填充层
	draw_line(t0, t1, PALM_COLOR, thumb_r * 2.0, true)
	draw_circle(t0, thumb_r, PALM_COLOR)
	draw_circle(t1, thumb_r, PALM_COLOR)
