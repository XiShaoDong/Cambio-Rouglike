class_name PlayerStatPanel
extends VBoxContainer
## 玩家状态面板（2D）：名字在状态框**上方**（放大），框内是生命/金钱/卡牌数（图标+数字）。
## 自己面板无名字；其他玩家面板带名字。底色透明白灰 + 黑边框。

const ICON_SIZE := 22
const FONT_SIZE := 14
const NAME_FONT_SIZE := 28
const BG_COLOR := Color(0.86, 0.88, 0.92, 0.22)
const BORDER_COLOR := Color(0.0, 0.0, 0.0, 0.85)
# 四个角 UI：深色玻璃（由 UIStyle 统一提供）。
const CORNER_ICON_SIZE := 20
const CORNER_FONT_SIZE := 18

var data := {}

var _name_label: Label
var _frame: PanelContainer
var _row: HBoxContainer
var _corner := false

## 标记为"屏幕角落 HUD"（dark mode 下换 #FEF0E4 底 + 白字；仅自身面板用，头顶座位面板不调用）。
func set_corner_style(on := true) -> void:
	_corner = on
	if _frame != null:
		_frame.add_theme_stylebox_override("panel", _frame_style())
	if _name_label != null:
		_name_label.add_theme_color_override("font_color", _text_color())
	if not data.is_empty():
		set_data(str(data.get("name", "")), int(data.get("health", 0)), int(data.get("currency", 0)), int(data.get("cards", 0)))

func _corner_active() -> bool:
	return _corner

func _frame_bg() -> Color:
	return UITheme.color("hud_surface") if _corner_active() else BG_COLOR

func _text_color() -> Color:
	return UITheme.color("text_primary")

func _frame_style() -> StyleBoxFlat:
	if _corner_active():
		return UIStyle.panel(12, 12, 8, true)
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	return style

func _ready() -> void:
	_build()

func _build() -> void:
	if _row != null:
		return
	add_theme_constant_override("separation", 2)
	alignment = BoxContainer.ALIGNMENT_CENTER
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_name_label.add_theme_color_override("font_color", _text_color())
	_name_label.visible = false
	add_child(_name_label)

	_frame = PanelContainer.new()
	_frame.name = "Frame"
	_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_frame.add_theme_stylebox_override("panel", _frame_style())
	add_child(_frame)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_frame.add_child(box)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_row)

## 更新内容；player_name 为空则隐藏名字行。
func set_data(player_name: String, health: int, currency: int, cards: int) -> void:
	_build()
	data = {"name": player_name, "health": health, "currency": currency, "cards": cards}
	_name_label.text = player_name
	_name_label.visible = player_name != ""
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_add_group(LifeIcon.new(), UITheme.color("danger"), health)
	_add_group(CoinIcon.new(), UITheme.color("currency") if _corner else UITheme.color("accent"), currency)
	_add_group(CardCountIcon.new(), UITheme.color("text_secondary"), cards)

func _add_group(icon: Control, color: Color, value: int) -> void:
	var icon_size := CORNER_ICON_SIZE if _corner_active() else ICON_SIZE
	var font_size := CORNER_FONT_SIZE if _corner_active() else FONT_SIZE
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.size = icon.custom_minimum_size
	icon.call("setup", color)
	_row.add_child(icon)
	var num := Label.new()
	num.text = str(value)
	num.add_theme_font_size_override("font_size", font_size)
	num.add_theme_color_override("font_color", _text_color())
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row.add_child(num)

## 状态框（带边框/底的 PanelContainer），供测试/外部取样式。
func frame_panel() -> PanelContainer:
	_build()
	return _frame

func name_visible() -> bool:
	return _name_label != null and _name_label.visible

func name_text() -> String:
	return _name_label.text if _name_label != null else ""
