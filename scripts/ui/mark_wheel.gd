class_name MarkWheel
extends Control
## 四扇区轮盘（上眼/右问/下数/左叹，中心中空）。纯视觉：mouse_filter=IGNORE，由 main 喂光标位置。

const Mark3dMathScript := preload("res://scripts/ui/mark3d_math.gd")

const INNER_RATIO := 0.16   # 中空内半径 = min(屏幕边)/2 * ratio
const OUTER_RATIO := 0.34
const FONT_SIZE := 28
const BG := Color(0.06, 0.07, 0.10, 0.72)
const SECTOR := Color(0.20, 0.22, 0.28, 0.85)
const SECTOR_HL := Color(0.95, 0.82, 0.35, 0.95)
const TXT := Color(0.95, 0.96, 1.0)
const DIVIDER := Color(0.90, 0.92, 1.0, 0.55)  # 扇区分界线

var _center := Vector2.ZERO
var _cursor := Vector2.ZERO
var _number_text := ""
var _selected := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func open(center: Vector2, number_text: String) -> void:
	_center = center
	_cursor = center
	_number_text = number_text
	_selected = ""
	visible = true
	queue_redraw()

func close() -> void:
	visible = false

func update_cursor(pos: Vector2) -> void:
	_cursor = pos
	_selected = Mark3dMathScript.sector_for(pos - _center, _inner_px(), _outer_px())
	queue_redraw()

func selected() -> String:
	return _selected

func _inner_px() -> float:
	return minf(size.x, size.y) * 0.5 * INNER_RATIO

func _outer_px() -> float:
	return minf(size.x, size.y) * 0.5 * OUTER_RATIO

func _draw() -> void:
	if not visible:
		return
	var inner := _inner_px()
	var outer := _outer_px()
	draw_circle(_center, outer, BG)
	var names := ["eye", "question", "number", "exclaim"]
	var base := [-90.0, 0.0, 90.0, 180.0]
	for i in 4:
		_draw_annular_sector(base[i], inner, outer, SECTOR_HL if _selected == names[i] else SECTOR)
	# 4 条固定虚线分界线（位于相邻扇区之间；不依赖 hover）
	for k in 4:
		var ba := deg_to_rad(-45.0 + 90.0 * float(k))
		var bdir := Vector2(cos(ba), sin(ba))
		_draw_dashed(_center + bdir * inner, _center + bdir * outer, DIVIDER, 2.0, 8.0, 6.0)
	var mid := outer - (outer - inner) * 0.5
	for i in 4:
		var a := deg_to_rad(base[i])
		var p := _center + Vector2(cos(a), sin(a)) * mid
		_draw_icon(names[i], p)
	draw_circle(_center, inner, BG)

## 虚线：从 a 到 b，按 dash/gap 交替绘制。
func _draw_dashed(a: Vector2, b: Vector2, col: Color, width: float, dash: float, gap: float) -> void:
	var total := a.distance_to(b)
	if total <= 0.0:
		return
	var dir := (b - a) / total
	var t := 0.0
	while t < total:
		var t2 := minf(t + dash, total)
		draw_line(a + dir * t, a + dir * t2, col, width)
		t = t2 + gap

func _draw_annular_sector(center_deg: float, inner: float, outer: float, col: Color) -> void:
	var a0 := deg_to_rad(center_deg - 45.0)
	var a1 := deg_to_rad(center_deg + 45.0)
	var pts := PackedVector2Array()
	var steps := 20
	for k in steps + 1:
		var a := a0 + (a1 - a0) * float(k) / float(steps)
		pts.append(_center + Vector2(cos(a), sin(a)) * outer)
	for k in range(steps, -1, -1):
		var a := a0 + (a1 - a0) * float(k) / float(steps)
		pts.append(_center + Vector2(cos(a), sin(a)) * inner)
	draw_colored_polygon(pts, col)

func _draw_icon(kind: String, p: Vector2) -> void:
	var f := ThemeDB.fallback_font
	if kind == "eye":
		draw_circle(p, 10.0, TXT)
		draw_circle(p, 4.0, Color(0.1, 0.1, 0.12))
		return
	var s := "?"
	if kind == "number":
		s = _number_text if not _number_text.is_empty() else "-1"
	elif kind == "exclaim":
		s = "!"
	var sz := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	draw_string(f, p - Vector2(sz.x * 0.5, -sz.y * 0.28), s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TXT)
