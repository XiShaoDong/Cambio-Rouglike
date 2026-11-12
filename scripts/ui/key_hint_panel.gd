class_name KeyHintPanel
extends VBoxContainer
## 3D 左下角按键提示：每行「说明文字（无底板）+ 按键 chip（UIStyle 深色玻璃）」。
## content-fit（说明/按键都按内容自适应宽度）；纯展示，不处理输入。

const DESC_FONT_SIZE := 18
const CHIP_FONT_SIZE := 16
# 兼容旧测试：角落 chip 的不透明度常量（实际样式由 UIStyle 提供）。
const CORNER_BG_ALPHA := 0.94
# 左上角回合徽标：字号 22；左右内边距加宽。
const ROUND_FONT_SIZE := 22
const ROUND_H_PAD := 16.0

static func chip_bg() -> Color:
	return UIStyle.chip(false).bg_color

static func chip_text_color() -> Color:
	return UIStyle.chip_text(false)

## 通用按键/徽标 chip（说明/回合徽标共用同一套样式）。
## h_pad >= 0 时覆盖左右内边距（如回合徽标要更宽的左右边框）。
static func make_chip(text: String, font_size := CHIP_FONT_SIZE, h_pad := -1.0) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "Chip"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", chip_style_box(h_pad))
	var k := Label.new()
	k.name = "Key"
	k.text = text
	k.add_theme_font_size_override("font_size", font_size)
	k.add_theme_color_override("font_color", chip_text_color())
	chip.add_child(k)
	return chip

## 圆角半透明底 + 细边框的 chip 样式。h_pad >= 0 时覆盖左右内边距。
static func chip_style_box(h_pad := -1.0) -> StyleBoxFlat:
	var style := UIStyle.chip(false)
	if h_pad >= 0.0:
		style.content_margin_left = h_pad
		style.content_margin_right = h_pad
	return style

func setup(rows: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 8)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	for entry in rows:
		# entry[1] == "__mouse__"：该行按键位换成鼠标形状图标（右键放大）。
		add_child(_make_row(str(entry[0]), str(entry[1])))

func _make_row(desc: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var d := Label.new()
	d.name = "Desc"
	d.text = desc
	d.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
	d.add_theme_color_override("font_color", UITheme.color("text_primary"))
	d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(d)
	if key == "__mouse__":
		var icon := _make_mouse_icon()
		row.add_child(icon)
	else:
		row.add_child(_make_chip(key))
	return row

## 圆润鼠标图标（"放大=按住右键"）：圆角机身 + 中缝 + 滚轮；右上按键区高亮。
func _make_mouse_icon() -> Control:
	var icon := Control.new()
	icon.name = "MouseIcon"
	icon.custom_minimum_size = Vector2(22, 22)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_mouse.bind(icon))
	return icon

func _draw_mouse(c: Control) -> void:
	const W := 22.0
	const H := 22.0
	var cx := W * 0.5
	var cy := H * 0.5
	var rx := 9.0
	var ry := 10.5
	var line := UITheme.color("text_primary")
	var fill := UITheme.color("accent")
	# 右上按键区填充（-90°..0° 象限，闭合到中心）
	var pts := PackedVector2Array([Vector2(cx, cy)])
	for i in 13:
		var a := -PI * 0.5 + (PI * 0.5) * float(i) / 12.0
		pts.append(Vector2(cx + rx * cos(a), cy + ry * sin(a)))
	c.draw_colored_polygon(pts, fill)
	# 圆润机身
	var outline := PackedVector2Array()
	for i in 33:
		var a := TAU * float(i) / 32.0
		outline.append(Vector2(cx + rx * cos(a), cy + ry * sin(a)))
	c.draw_polyline(outline, line, 1.8, true)
	# 中缝
	c.draw_line(Vector2(cx - rx, cy), Vector2(cx + rx, cy), line, 1.8, true)
	# 滚轮
	c.draw_rect(Rect2(cx - 1.4, cy - 7.0, 2.8, 5.5), line)

func _make_chip(key: String) -> PanelContainer:
	return make_chip(key, CHIP_FONT_SIZE)

## 测试/调试访问器。
func row_count() -> int:
	return get_child_count()

func has_mouse_icon(index: int) -> bool:
	var row := get_child(index)
	return row.has_node("MouseIcon")

func desc_text(index: int) -> String:
	var row := get_child(index)
	return (row.get_node("Desc") as Label).text

func key_text(index: int) -> String:
	var row := get_child(index)
	if not row.has_node("Chip/Key"):
		return ""
	return (row.get_node("Chip/Key") as Label).text

func chip_style(index: int) -> StyleBoxFlat:
	var row := get_child(index)
	return (row.get_node("Chip") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
