class_name CardOrderPanel
extends VBoxContainer
## 3D 左下角「牌序」：标题 + Shift 开关 + 叠放的小牌面。
## 小牌面与结算页同款：浅色卡面、左上点数、无花色；Joker 显示 JK（红字）。
## 纯展示层，不处理输入（Shift 按钮除外）。

signal toggled(expanded: bool)

const ORDER := ["Q", "J", "10", "9", "8", "7", "6", "5", "4", "3", "2", "A", "JK", "K"]
const CARD_W := 26.0
const CARD_H := 34.0
const STEP := 18.0
const TITLE_FONT_SIZE := 18
const SHIFT_FONT_SIZE := 15

var _expanded := true
var _shift_btn: Button
var _cards: Control
var _arrow: ThinArrow

func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_header()
	_build_cards()
	_build_arrow()
	set_expanded(true)

## 第一行：牌序 + SHIFT（一排）。
func _build_header() -> void:
	var row := HBoxContainer.new()
	row.name = "Header"
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var title := Label.new()
	title.name = "Title"
	title.text = "牌序"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", UITheme.color("text_primary"))
	row.add_child(title)
	_shift_btn = Button.new()
	_shift_btn.name = "Shift"
	_shift_btn.text = "Shift"
	_shift_btn.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "disabled"]:
		_shift_btn.add_theme_stylebox_override(st_name, UIStyle.chip(false))
	_shift_btn.add_theme_color_override("font_color", UIStyle.chip_text(false))
	_shift_btn.add_theme_font_size_override("font_size", SHIFT_FONT_SIZE)
	_shift_btn.pressed.connect(toggle)
	row.add_child(_shift_btn)

## 下面：叠放的浅色小牌面（只显示点数）。
func _build_cards() -> void:
	_cards = Control.new()
	_cards.name = "Cards"
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var total_w := CARD_W + STEP * float(ORDER.size() - 1)
	_cards.custom_minimum_size = Vector2(total_w, CARD_H)
	add_child(_cards)
	for i in ORDER.size():
		var rank: String = ORDER[i]
		var card := PanelContainer.new()
		card.name = "Card%d_%s" % [i, rank]
		card.custom_minimum_size = Vector2(CARD_W, CARD_H)
		card.size = Vector2(CARD_W, CARD_H)
		card.position = Vector2(STEP * float(i), 0.0)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = UITheme.color("card_face_bg")
		style.border_color = UITheme.color("card_border")
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 4
		style.content_margin_top = 2
		style.content_margin_right = 2
		style.content_margin_bottom = 2
		card.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.text = rank
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color",
			UITheme.color("card_rank_red") if rank == "JK" else UITheme.color("card_rank_black"))
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.add_child(label)
		_cards.add_child(card)

func _build_arrow() -> void:
	var total_w := CARD_W + STEP * float(ORDER.size() - 1)
	_arrow = ThinArrow.new()
	_arrow.name = "Arrow"
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.custom_minimum_size = Vector2(total_w, 8.0)
	add_child(_arrow)

func toggle() -> void:
	set_expanded(not _expanded)

func set_expanded(on: bool) -> void:
	_expanded = on
	if _cards != null:
		_cards.visible = on
	if _arrow != null:
		_arrow.visible = on
	toggled.emit(on)

func is_expanded() -> bool:
	return _expanded

func shift_button() -> Button:
	return _shift_btn

func card_count() -> int:
	return _cards.get_child_count() if _cards != null else 0

func rank_at(i: int) -> String:
	return ORDER[i] if i >= 0 and i < ORDER.size() else ""

## 很细的指向右箭头。
class ThinArrow extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var y := size.y * 0.5
		var c := UITheme.color("text_primary")
		c.a = 0.7
		draw_line(Vector2(0.0, y), Vector2(w, y), c, 1.0)
		draw_line(Vector2(w - 7.0, y - 3.0), Vector2(w, y), c, 1.0)
		draw_line(Vector2(w - 7.0, y + 3.0), Vector2(w, y), c, 1.0)
