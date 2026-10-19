class_name CardOrderPanel
extends HBoxContainer
## 左下角「牌序」面板：左侧竖排 牌序 / SHIFT（开关），右侧细箭头 + 黑桃卡序（卡牌在最下方）。
## 卡序按点数从大到小：Q J 10 9 8 7 6 5 4 3 2 A Joker K；卡牌堆叠排列。纯展示层。

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

const CARD_W := 34.0
const CARD_H := 48.0
const STEP := 0.78          # 堆叠步进（占卡宽比例；越大遮挡越少）
const ARROW_H := 8.0

var _expanded := true
var _shift_btn: Button
var _cards: Control
var _arrow: ThinArrow

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_BEGIN
	_build_header()
	_build_content()
	set_expanded(true)

## 左侧：牌序（上）/ SHIFT（下，最底）。
func _build_header() -> void:
	var col := VBoxContainer.new()
	col.name = "Header"
	col.add_theme_constant_override("separation", 6)
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var title := Label.new()
	title.name = "Title"
	title.text = "牌序"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	col.add_child(title)
	_shift_btn = Button.new()
	_shift_btn.name = "Shift"
	_shift_btn.text = "SHIFT"
	_shift_btn.focus_mode = Control.FOCUS_NONE
	_shift_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for st_name in ["normal", "hover", "pressed", "disabled"]:
		_shift_btn.add_theme_stylebox_override(st_name, KeyHintPanel.chip_style_box())
	_shift_btn.add_theme_color_override("font_color", KeyHintPanel.chip_text_color())
	_shift_btn.add_theme_font_size_override("font_size", 15)
	_shift_btn.pressed.connect(toggle)
	col.add_child(_shift_btn)

## 右侧：细箭头（上）+ 卡序（下，最底）。
func _build_content() -> void:
	var col := VBoxContainer.new()
	col.name = "Content"
	col.add_theme_constant_override("separation", 3)
	col.size_flags_vertical = Control.SIZE_SHRINK_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var step := CARD_W * STEP
	var total_w := CARD_W + step * float(ORDER.size() - 1)
	_arrow = ThinArrow.new()
	_arrow.name = "Arrow"
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.custom_minimum_size = Vector2(total_w, ARROW_H)
	col.add_child(_arrow)
	_cards = Control.new()
	_cards.name = "Cards"
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards.custom_minimum_size = Vector2(total_w, CARD_H)
	col.add_child(_cards)
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
