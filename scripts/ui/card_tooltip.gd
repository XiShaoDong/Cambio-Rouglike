class_name CardTooltip
extends Control
## 3D 卡牌 hover 信息气泡（屏幕空间）：
## 第一行 左=牌名 / 右=分数（大字）；之后每行=能力说明（无能力=「无能力」）。
## 放在卡牌右上角外侧（贴近、不重叠）；位置由 main 用相机投影的卡牌屏幕矩形喂入。

const RANK_FONT := 24
const LINE_FONT := 15
const BG := Color(0.08, 0.09, 0.12, 0.92)
const BORDER := Color(1.0, 1.0, 1.0, 0.25)
const TEXT := Color(0.95, 0.97, 1.0)
const MAX_W := 300.0
const GAP_X := 10.0
const GAP_Y := 10.0

var _bubble: PanelContainer
var _vbox: VBoxContainer
var _row: HBoxContainer
var _rank_label: Label
var _score_label: Label
var _lines_box: VBoxContainer
var _style: StyleBoxFlat
var _content_key := ""
var _shown := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = BG
	_style.set_corner_radius_all(18)
	_style.set_content_margin_all(12)
	_style.border_color = BORDER
	_style.set_border_width_all(1)
	_bubble.add_theme_stylebox_override("panel", _style)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	_bubble.add_child(_vbox)
	# 第一行：牌名（左） / 分数（右，大字）
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	_vbox.add_child(_row)
	_rank_label = _make_label(RANK_FONT)
	_rank_label.name = "Rank"
	_row.add_child(_rank_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(spacer)
	_score_label = _make_label(RANK_FONT)
	_score_label.name = "Score"
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_row.add_child(_score_label)
	# 能力行
	_lines_box = VBoxContainer.new()
	_lines_box.name = "Lines"
	_lines_box.add_theme_constant_override("separation", 3)
	_vbox.add_child(_lines_box)
	add_child(_bubble)
	visible = false

func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT)
	return l

## info = {rank, value, lines}（来自 CardAbilityText.info）；放在 card_rect 右上角外侧。
func show_card(info: Dictionary, card_rect: Rect2) -> void:
	_set_content(info)
	var sz := _bubble.get_combined_minimum_size()
	var pos := Vector2(card_rect.end.x + GAP_X, card_rect.position.y - sz.y - GAP_Y)
	_place(pos, sz)

func hide_tip() -> void:
	_shown = false
	visible = false

func is_shown() -> bool:
	return _shown

func bubble_size() -> Vector2:
	return _bubble.get_combined_minimum_size() if _bubble != null else Vector2.ZERO

func rank_text() -> String:
	return _rank_label.text if _rank_label != null else ""

func score_text() -> String:
	return _score_label.text if _score_label != null else ""

func line_texts() -> Array:
	var out: Array = []
	if _lines_box == null:
		return out
	for c in _lines_box.get_children():
		if c is Label:
			out.append((c as Label).text)
	return out

func _set_content(info: Dictionary) -> void:
	var lines: Array = info.get("lines", [])
	var key := "%s|%s|%s" % [str(info.get("rank", "")), str(info.get("value", 0)), str(lines)]
	if key == _content_key:
		return
	_content_key = key
	_rank_label.text = str(info.get("rank", ""))
	_score_label.text = str(info.get("value", 0))
	for c in _lines_box.get_children():
		_lines_box.remove_child(c)
		c.queue_free()
	var font := _rank_label.get_theme_font("font")
	for line in lines:
		var l := _make_label(LINE_FONT)
		l.text = str(line)
		if font != null:
			var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, LINE_FONT).x
			l.custom_minimum_size.x = minf(MAX_W - 24.0, w + 2.0)
		else:
			l.custom_minimum_size.x = MAX_W - 24.0
		_lines_box.add_child(l)

func _place(pos: Vector2, sz: Vector2) -> void:
	pos.x = clampf(pos.x, 8.0, maxf(8.0, size.x - sz.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, size.y - sz.y - 8.0))
	_bubble.position = pos
	_bubble.size = sz
	_style.set_corner_radius_all(int(minf(sz.y * 0.5, 28.0)))
	_shown = true
	visible = true
