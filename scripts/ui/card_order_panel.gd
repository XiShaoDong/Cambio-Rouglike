class_name CardOrderPanel
extends VBoxContainer
## 左下角「牌序」面板：
## 第一行：牌序 + SHIFT（同一排，SHIFT 在右）；
## 下面：黑桃卡序一排（堆叠），其下一条很细的向右箭头。
## 卡序 Q J 10 9 8 7 6 5 4 3 2 A Joker K。纯展示层。

signal toggled(expanded: bool)

const ORDER := ["Q", "J", "10", "9", "8", "7", "6", "5", "4", "3", "2", "A", "JOKER", "K"]
const FILES := {
	"Q": "res://assets/SmallCards/spades_queen.png",
	"J": "res://assets/SmallCards/spades_jack.png",
	"10": "res://assets/SmallCards/spades_10.png",
	"9": "res://assets/SmallCards/spades_09.png",
	"8": "res://assets/SmallCards/spades_08.png",
	"7": "res://assets/SmallCards/spades_07.png",
	"6": "res://assets/SmallCards/spades_06.png",
	"5": "res://assets/SmallCards/spades_05.png",
	"4": "res://assets/SmallCards/spades_04.png",
	"3": "res://assets/SmallCards/spades_03.png",
	"2": "res://assets/SmallCards/spades_02.png",
	"A": "res://assets/SmallCards/spades_ace.png",
	"JOKER": "res://assets/SmallCards/Joker1.png",
	"K": "res://assets/SmallCards/spades_king.png",
}

# 整体尺寸按 2/3 缩放（再缩小 1/3）。
const SHRINK := 2.0 / 3.0
const CARD_W := 34.0 * SHRINK   # 原 34 → 缩小 1/3
const CARD_H := 48.0 * SHRINK   # 原 48 → 缩小 1/3
const STEP := 0.78          # 堆叠步进（占卡宽比例；越大遮挡越少）
const ARROW_H := 8.0 * SHRINK   # 原 8 → 缩小 1/3
const TITLE_FONT_SIZE := 12
const SHIFT_FONT_SIZE := 10
const CHIP_PAD := 3.0

var _expanded := true
var _shift_btn: Button
var _cards: Control
var _arrow: ThinArrow

func _ready() -> void:
	add_theme_constant_override("separation", 3)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_header()
	_build_cards()
	_build_arrow()
	set_expanded(true)

## 第一行：牌序 + SHIFT（一排）。
func _build_header() -> void:
	var row := HBoxContainer.new()
	row.name = "Header"
	row.add_theme_constant_override("separation", 5)
	# 标题行按内容收缩（不与下方卡牌同宽），位置仍在左侧不变。
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var title := Label.new()
	title.name = "Title"
	title.text = "牌序"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	row.add_child(title)
	_shift_btn = Button.new()
	_shift_btn.name = "Shift"
	_shift_btn.text = "SHIFT"
	_shift_btn.focus_mode = Control.FOCUS_NONE
	for st_name in ["normal", "hover", "pressed", "disabled"]:
		_shift_btn.add_theme_stylebox_override(st_name, _chip_style())
	_shift_btn.add_theme_color_override("font_color", KeyHintPanel.chip_text_color())
	_shift_btn.add_theme_font_size_override("font_size", SHIFT_FONT_SIZE)
	_shift_btn.pressed.connect(toggle)
	row.add_child(_shift_btn)

## SHIFT chip：沿用按键 chip 样式，但内边距/圆角随面板一起缩小。
func _chip_style() -> StyleBoxFlat:
	var style := KeyHintPanel.chip_style_box()
	style.set_content_margin_all(CHIP_PAD)
	style.set_corner_radius_all(4)
	return style

## 下面：卡牌一排（堆叠）。
func _build_cards() -> void:
	_cards = Control.new()
	_cards.name = "Cards"
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var step := CARD_W * STEP
	var total_w := CARD_W + step * float(ORDER.size() - 1)
	_cards.custom_minimum_size = Vector2(total_w, CARD_H)
	add_child(_cards)
	for i in ORDER.size():
		var rank: String = ORDER[i]
		var tr := TextureRect.new()
		tr.name = "Card%d_%s" % [i, rank]
		tr.texture = load(FILES[rank])
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.position = Vector2(step * float(i), 0.0)
		tr.size = Vector2(CARD_W, CARD_H)
		_cards.add_child(tr)

func _build_arrow() -> void:
	var step := CARD_W * STEP
	var total_w := CARD_W + step * float(ORDER.size() - 1)
	_arrow = ThinArrow.new()
	_arrow.name = "Arrow"
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.custom_minimum_size = Vector2(total_w, ARROW_H)
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
		var c := Color(1.0, 1.0, 1.0, 0.85)
		draw_line(Vector2(0.0, y), Vector2(w, y), c, 1.0)
		draw_line(Vector2(w - 7.0, y - 3.0), Vector2(w, y), c, 1.0)
		draw_line(Vector2(w - 7.0, y + 3.0), Vector2(w, y), c, 1.0)
