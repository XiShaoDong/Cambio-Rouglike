class_name MarkWheel
extends Control
## 四扇区轮盘（上眼/右问/下数/左叹，中心中空）。纯视觉：mouse_filter=IGNORE，由 main 喂光标位置。
## 悬停"数字"扇区时，外圈展开 A~K + 红/黑 Joker（15 等分），选择哪张就作为标记文字；
## 不选（仍停在数字扇区）= 默认消费方（main 用弃牌堆顶）。

const Mark3dMathScript := preload("res://scripts/ui/mark3d_math.gd")

const INNER_RATIO := 0.16   # 中空内半径 = min(屏幕边)/2 * ratio
const OUTER_RATIO := 0.34
const OUTER2_RATIO := 0.61  # 外圈（数字展开）外半径（环带比原来加厚 1/2，转动时不易划出）
const FONT_SIZE := 28
const OUTER_FONT_SIZE := 18
const BG := Color(0.06, 0.07, 0.10, 0.72)
const SECTOR := Color(0.20, 0.22, 0.28, 0.85)
const SECTOR_HL := Color(0.95, 0.82, 0.35, 0.95)
const OUTER_SECTOR := Color(0.15, 0.17, 0.23, 0.88)
const OUTER_SECTOR_HL := Color(0.95, 0.82, 0.35, 0.95)
const TXT := Color(0.95, 0.96, 1.0)
const JOKER_RED := Color("ff5a5a")
const JOKER_BLACK := Color("0b0b0e")
const DIVIDER := Color(0.90, 0.92, 1.0, 0.55)  # 扇区分界线

# 外圈 15 项：A~K + 红 Joker + 黑 Joker（均显示 "Jk"，红/黑配色）
const OUTER_ITEMS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "Jk", "Jk"]
const RED_JOKER_IDX := 13
const BLACK_JOKER_IDX := 14

var _center := Vector2.ZERO
var _cursor := Vector2.ZERO
var _number_text := ""
var _selected := ""
var _outer_active := false   # 悬停数字扇区 → 展开外圈
var _outer_index := -1       # 外圈选项索引（-1=未选，用默认数字）

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
	_outer_active = false
	_outer_index = -1
	visible = true
	queue_redraw()

func close() -> void:
	visible = false

func update_cursor(pos: Vector2) -> void:
	_cursor = pos
	var off := pos - _center
	var r := off.length()
	if r <= _outer_px():
		# 内圈四扇区
		_selected = Mark3dMathScript.sector_for(off, _inner_px(), _outer_px())
		_outer_active = (_selected == "number")
		_outer_index = -1
	elif _outer_active and r <= _outer2_px():
		# 外圈：仍在数字展开态，按角度选 15 项之一（图标仍视为 number）
		_outer_index = Mark3dMathScript.sector_index_for(off, _outer_px(), _outer2_px(), OUTER_ITEMS.size())
		_selected = "number"
	else:
		# 超出外圈，或此前不在数字扇区 → 无选择
		_selected = ""
		_outer_active = false
		_outer_index = -1
	queue_redraw()

func selected() -> String:
	return _selected

## 外圈所选项（如 "K"/"Jk"）；未选返回 ""（由 main 回退到弃牌堆顶）。
func selected_text() -> String:
	if _outer_active and _outer_index >= 0 and _outer_index < OUTER_ITEMS.size():
		return OUTER_ITEMS[_outer_index]
	return ""

func _inner_px() -> float:
	return minf(size.x, size.y) * 0.5 * INNER_RATIO

func _outer_px() -> float:
	return minf(size.x, size.y) * 0.5 * OUTER_RATIO

func _outer2_px() -> float:
	return minf(size.x, size.y) * 0.5 * OUTER2_RATIO

func _draw() -> void:
	if not visible:
		return
	var inner := _inner_px()
	var outer := _outer_px()
	if _outer_active:
		_draw_outer_ring(outer, _outer2_px())
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

## 外圈：15 等分环带 + 每项标签（红/黑 Joker 配色）。索引 0 在正上方、顺时针。
func _draw_outer_ring(r0: float, r1: float) -> void:
	var n := OUTER_ITEMS.size()
	var step := 360.0 / float(n)
	for i in n:
		var center_deg := -90.0 + step * float(i)
		var col := OUTER_SECTOR_HL if i == _outer_index else OUTER_SECTOR
		_draw_annular_sector_deg(center_deg, step * 0.5, r0, r1, col)
	var mid := (r0 + r1) * 0.5
	for i in n:
		var a := deg_to_rad(-90.0 + step * float(i))
		var p := _center + Vector2(cos(a), sin(a)) * mid
		_draw_outer_label(OUTER_ITEMS[i], p, i)

func _outer_color(i: int) -> Color:
	if i == RED_JOKER_IDX:
		return JOKER_RED
	if i == BLACK_JOKER_IDX:
		return JOKER_BLACK
	return TXT

func _draw_outer_label(txt: String, p: Vector2, i: int) -> void:
	var f := ThemeDB.fallback_font
	var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, OUTER_FONT_SIZE)
	var org := p - Vector2(sz.x * 0.5, -sz.y * 0.28)
	var col := _outer_color(i)
	if i == BLACK_JOKER_IDX:
		# 深色字在深色底上→加浅色描边保证可读
		draw_string_outline(f, org, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, OUTER_FONT_SIZE, 2, Color(0.9, 0.92, 1.0, 0.85))
	draw_string(f, org, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, OUTER_FONT_SIZE, col)

func _number_display() -> String:
	if _outer_active and _outer_index >= 0 and _outer_index < OUTER_ITEMS.size():
		return OUTER_ITEMS[_outer_index]
	return _number_text if not _number_text.is_empty() else "-1"

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
	_draw_annular_sector_deg(center_deg, 45.0, inner, outer, col)

func _draw_annular_sector_deg(center_deg: float, half_deg: float, inner: float, outer: float, col: Color) -> void:
	var a0 := deg_to_rad(center_deg - half_deg)
	var a1 := deg_to_rad(center_deg + half_deg)
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
		s = _number_display()
	elif kind == "exclaim":
		s = "!"
	var sz := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	draw_string(f, p - Vector2(sz.x * 0.5, -sz.y * 0.28), s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TXT)
