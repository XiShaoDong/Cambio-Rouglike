class_name RelicIcon
extends Control
## 程序化遗物图标：_draw 绘制盾形/五角星/空槽。无图片资源依赖。

enum Kind { EMPTY, SHIELD, JOKER, GLYPH }

var kind := Kind.EMPTY
var color := Color.WHITE
var glyph := ""

func setup(p_kind: Kind, p_color: Color) -> void:
	kind = p_kind
	color = p_color
	queue_redraw()

## 占位字符图标（Phase 1 饰品无专属美术时使用）。
func setup_glyph(text: String, p_color: Color) -> void:
	kind = Kind.GLYPH
	glyph = text
	color = p_color
	queue_redraw()

func _draw() -> void:
	match kind:
		Kind.SHIELD: _draw_shape(_shield_points())
		Kind.JOKER: _draw_shape(_star_points())
		Kind.GLYPH: _draw_glyph()
		_: _draw_empty()

func _draw_glyph() -> void:
	var rect := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	var fill := Color(color)
	fill.a = 0.16
	draw_rect(rect, fill, true)
	draw_rect(rect, Color(color, 0.55), false, 1.5)
	if glyph.is_empty():
		return
	var font := ThemeDB.fallback_font
	var text := glyph
	var font_size := 16 if text.length() <= 2 else 11
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pos := Vector2((size.x - text_size.x) * 0.5, (size.y + text_size.y * 0.55) * 0.5)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## 盾形（经典圆盾轮廓，中心 (16,16)，size 默认 32×32）。
func _shield_points() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(16, 2), Vector2(27, 6), Vector2(27, 18),
		Vector2(16, 30), Vector2(5, 18), Vector2(5, 6),
	])

## 五角星。
func _star_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var outer := 13.0
	var inner := 5.5
	for i in 10:
		var ang: float = -PI / 2.0 + i * PI / 5.0
		var r := outer if i % 2 == 0 else inner
		pts.append(Vector2(16.0 + cos(ang) * r, 16.0 + sin(ang) * r))
	return pts

## 多边形：半透明填充 + 实色描边（2px）。
func _draw_shape(points: PackedVector2Array) -> void:
	var fill := Color(color)
	fill.a = 0.35
	draw_colored_polygon(points, fill)
	draw_polyline(points, color, 2.0, true)

## 空槽：极淡空心圆角方框。
func _draw_empty() -> void:
	var rect := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	var outline := Color(color)
	outline.a = 0.35
	draw_rect(rect, Color(0, 0, 0, 0), false, 1.5)
	draw_rect(rect, outline, false, 1.5)
