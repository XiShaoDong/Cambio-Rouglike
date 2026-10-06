class_name KeyHintPanel
extends VBoxContainer
## 3D 左下角按键提示：每行「说明（纯白色、无边框）+ 按键（圆角半透明灰底、黑字、带边框）」。
## content-fit（说明/按键都按内容自适应宽度）；纯展示，不处理输入。

const DESC_FONT_SIZE := 18
const CHIP_FONT_SIZE := 16
const DESC_COLOR := Color(1.0, 1.0, 1.0)
const CHIP_BORDER := Color(1.0, 1.0, 1.0, 0.38)
# 四个角 UI（dark mode）：背景统一纯白（保留原透明度），字体纯白。
const CORNER_BG := Color(1.0, 1.0, 1.0)
const CORNER_BG_ALPHA := 0.45
const CORNER_TEXT := Color(1.0, 1.0, 1.0)
# 右上角回合徽标：字号 = chip 两倍再缩小 1/3；左右内边距加宽。
const ROUND_FONT_SIZE := 21          # = 16*2*2/3
const ROUND_H_PAD := 18.0

## 仅 dark mode 应用新配色；light/其他沿用旧的半透明灰底黑字。
static func chip_bg() -> Color:
	if UITheme.current == "dark":
		var c := CORNER_BG
		c.a = CORNER_BG_ALPHA
		return c
	return Color(0.42, 0.44, 0.48, 0.45)

static func chip_text_color() -> Color:
	return CORNER_TEXT if UITheme.current == "dark" else Color(0.05, 0.06, 0.08)

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
	var style := StyleBoxFlat.new()
	style.bg_color = chip_bg()
	style.set_corner_radius_all(6)
	style.set_content_margin_all(5)
	if h_pad >= 0.0:
		style.content_margin_left = h_pad
		style.content_margin_right = h_pad
	style.border_color = CHIP_BORDER
	style.set_border_width_all(1)
	return style

func setup(rows: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 8)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	for entry in rows:
		add_child(_make_row(str(entry[0]), str(entry[1])))

func _make_row(desc: String, key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	var d := Label.new()
	d.name = "Desc"
	d.text = desc
	d.add_theme_font_size_override("font_size", DESC_FONT_SIZE)
	d.add_theme_color_override("font_color", DESC_COLOR)
	d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(d)
	row.add_child(_make_chip(key))
	return row

func _make_chip(key: String) -> PanelContainer:
	return make_chip(key, CHIP_FONT_SIZE)

## 测试/调试访问器。
func row_count() -> int:
	return get_child_count()

func desc_text(index: int) -> String:
	var row := get_child(index)
	return (row.get_node("Desc") as Label).text

func key_text(index: int) -> String:
	var row := get_child(index)
	return (row.get_node("Chip/Key") as Label).text

func chip_style(index: int) -> StyleBoxFlat:
	var row := get_child(index)
	return (row.get_node("Chip") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
