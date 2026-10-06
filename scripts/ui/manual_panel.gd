class_name ManualPanel
extends Control
## 手册面板（3D 全息看板）：透明毛玻璃 + 三列（牌 / 能力 / 分数）。
## 数据来自 `ManualModel.rows()`（A..K/Joker，按数值排序）。纯展示，无交互。

const COL_RANK := 72.0
const COL_SCORE := 72.0
const COL_POWER := 300.0
const TEXT := Color(0.10, 0.12, 0.16)
const TEXT_MUTED := Color(0.32, 0.36, 0.42)
const HEADER := Color(0.16, 0.20, 0.28)

func _ready() -> void:
	_style_panel()
	_build_grid()

func _style_panel() -> void:
	var panel: PanelContainer = get_node("Center/Panel")
	# 透明毛玻璃：半透明浅灰底 + 淡白边框 + 大圆角（在 3D 上呈磨砂观感）
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.90, 0.92, 0.96, 0.82)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(24)
	style.border_color = Color(1.0, 1.0, 1.0, 0.55)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)

func _build_grid() -> void:
	var title: Label = get_node("Center/Panel/VBox/Title")
	title.add_theme_color_override("font_color", HEADER)
	var hint: Label = get_node("Center/Panel/VBox/Hint")
	hint.add_theme_color_override("font_color", TEXT_MUTED)
	var grid: GridContainer = get_node("Center/Panel/VBox/Grid")
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	grid.add_child(_cell("牌", COL_RANK, true, true))
	grid.add_child(_cell("能力", COL_POWER, true, false))
	grid.add_child(_cell("分数", COL_SCORE, true, true))
	for entry in ManualModel.rows():
		grid.add_child(_cell(str(entry.rank), COL_RANK, false, true))
		grid.add_child(_cell(str(entry.power), COL_POWER, false, false))
		grid.add_child(_cell(str(entry.score), COL_SCORE, false, true))

func _cell(text: String, width: float, header: bool, center: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(width, 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if center else HORIZONTAL_ALIGNMENT_LEFT
	lbl.add_theme_font_size_override("font_size", 20 if header else 18)
	lbl.add_theme_color_override("font_color", HEADER if header else TEXT)
	return lbl

## 测试访问器。
func grid_columns() -> int:
	var grid: GridContainer = get_node("Center/Panel/VBox/Grid")
	return grid.columns
