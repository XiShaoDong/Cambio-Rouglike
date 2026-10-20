class_name EmoteWheel
extends Control
## 6 扇区表情轮盘（文案 1..6，中心中空、扇区之间虚线分界）。纯视觉：由 main 喂光标位置。

const Mark3dMathScript := preload("res://scripts/ui/mark3d_math.gd")

const COUNT := 6
const INNER_RATIO := 0.16
const OUTER_RATIO := 0.34
const FONT_SIZE := 26
const BG := Color(0.06, 0.07, 0.10, 0.72)
const SECTOR := Color(0.20, 0.22, 0.28, 0.85)
const SECTOR_HL := Color(0.95, 0.82, 0.35, 0.95)
const TXT := Color(0.95, 0.96, 1.0)
const DIVIDER := Color(0.90, 0.92, 1.0, 0.55)

var _center := Vector2.ZERO
var _cursor := Vector2.ZERO
var _selected := -1

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func open(center: Vector2) -> void:
	_center = center
	_cursor = center
	_selected = -1
	visible = true
	queue_redraw()

func close() -> void:
	visible = false

func update_cursor(pos: Vector2) -> void:
	_cursor = pos
	_selected = Mark3dMathScript.sector_index_for(pos - _center, _inner_px(), _outer_px(), COUNT)
	queue_redraw()

func selected() -> int:
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
	var w := 360.0 / float(COUNT)
	for i in COUNT:
		_draw_sector(-90.0 + i * w, w, inner, outer, SECTOR_HL if _selected == i else SECTOR)
	for k in COUNT:
		var ba := deg_to_rad(-90.0 + w * 0.5 + w * float(k))
		var bdir := Vector2(cos(ba), sin(ba))
		_draw_dashed(_center + bdir * inner, _center + bdir * outer, DIVIDER, 2.0, 8.0, 6.0)
	var mid := outer - (outer - inner) * 0.5
	var f := ThemeDB.fallback_font
	for i in COUNT:
		var a := deg_to_rad(-90.0 + i * w)
		var p := _center + Vector2(cos(a), sin(a)) * mid
		var s := str(i + 1)
		var sz := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		draw_string(f, p - Vector2(sz.x * 0.5, -sz.y * 0.28), s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TXT)
	draw_circle(_center, inner, BG)

func _draw_sector(center_deg: float, width_deg: float, inner: float, outer: float, col: Color) -> void:
	var a0 := deg_to_rad(center_deg - width_deg * 0.5)
	var a1 := deg_to_rad(center_deg + width_deg * 0.5)
	var pts := PackedVector2Array()
	var steps := 16
	for k in steps + 1:
		var a := a0 + (a1 - a0) * float(k) / float(steps)
		pts.append(_center + Vector2(cos(a), sin(a)) * outer)
	for k in range(steps, -1, -1):
		var a := a0 + (a1 - a0) * float(k) / float(steps)
		pts.append(_center + Vector2(cos(a), sin(a)) * inner)
	draw_colored_polygon(pts, col)

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
