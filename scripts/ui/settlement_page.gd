class_name SettlementPage
extends Control
## 结算弹层：居中排名窗口 + 同步轮算分动画（Balatro 式）+ 冠军特效。
## 场景实体承载静态骨架（scenes/ui/settlement_page.tscn），脚本负责填动态排名行、主题样式、标题、动画。

const ROW_H := 46
const ROW_W := 480
const FLIP_STEP := 0.35
const ROUND_DELAY := 0.55
const RESORT_DURATION := 0.35

var _model: Dictionary = {}
var _is_host := false
var _on_winner: Callable = Callable()
var _on_next_match: Callable = Callable()
var _on_abort: Callable = Callable()
var _rows: Dictionary = {}
var _rank_area: Control
var _footer: Control
var _title: Label

func setup(model: Dictionary, is_host: bool, match_number: int,
		on_winner: Callable, on_next_match: Callable, on_abort: Callable, auto_play := true) -> void:
	_model = model
	_is_host = is_host
	_on_winner = on_winner
	_on_next_match = on_next_match
	_on_abort = on_abort
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bind_ui(match_number)
	if auto_play:
		_run_sequence()

func _bind_ui(match_number: int) -> void:
	var center: CenterContainer = get_node("Center")
	var panel: PanelContainer = center.get_node("Panel")
	panel.add_theme_stylebox_override("panel", _panel_style())
	_title = get_node("Center/Panel/VBox/Title")
	_title.text = "结算 · 第 %d 局" % match_number
	_title.add_theme_color_override("font_color", UITheme.color("accent"))
	_rank_area = get_node("Center/Panel/VBox/RankingArea")
	_footer = get_node("Center/Panel/VBox/Footer")

	var n := _model.layout_order.size()
	_rank_area.custom_minimum_size = Vector2(ROW_W, n * ROW_H)
	var layout_order: Array = _model.layout_order
	for index in layout_order.size():
		_rank_area.add_child(_make_row(int(layout_order[index]), index))

func _make_row(seat: int, index: int) -> Control:
	var row := Control.new()
	row.name = "Row%d" % seat
	row.position = Vector2(0, index * ROW_H)
	row.size = Vector2(ROW_W, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(hbox)

	var rank_lbl := Label.new()
	rank_lbl.custom_minimum_size = Vector2(44, ROW_H)
	rank_lbl.text = str(index + 1)
	rank_lbl.add_theme_font_size_override("font_size", 18)
	rank_lbl.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	hbox.add_child(rank_lbl)

	var name_lbl := Label.new()
	name_lbl.custom_minimum_size = Vector2(130, ROW_H)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", UITheme.color("text_primary"))
	hbox.add_child(name_lbl)

	var cards_box := HBoxContainer.new()
	cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_box.add_theme_constant_override("separation", 6)
	cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(cards_box)

	var total_lbl := Label.new()
	total_lbl.custom_minimum_size = Vector2(70, ROW_H)
	total_lbl.text = "0"
	total_lbl.add_theme_font_size_override("font_size", 18)
	total_lbl.add_theme_color_override("font_color", UITheme.color("accent"))
	total_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(total_lbl)

	_rows[seat] = {"row": row, "rank": rank_lbl, "name": name_lbl, "cards": cards_box, "total": total_lbl}
	return row

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.color("bg_elevated")
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)
	style.border_color = UITheme.color("border")
	style.set_border_width_all(1)
	return style

func _run_sequence() -> void:
	for round in _model.rounds:
		var flips: Array = round.flips
		for flip in flips:
			_reveal_flip(int(flip.seat), flip, flips.find(flip) * FLIP_STEP)
		await get_tree().create_timer(ROUND_DELAY).timeout
		await _resort(round.ranking)
		await get_tree().create_timer(0.2).timeout
	await _champion()
	_show_footer()

func _reveal_flip(seat: int, flip: Dictionary, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not _rows.has(seat):
		return
	var entry: Dictionary = _rows[seat]
	var card_lbl := Label.new()
	card_lbl.text = "%s%s" % [str(flip.rank), str(flip.suit)]
	card_lbl.add_theme_font_size_override("font_size", 14)
	card_lbl.add_theme_color_override("font_color", UITheme.color("text_primary"))
	card_lbl.modulate.a = 0.0
	entry.cards.add_child(card_lbl)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(card_lbl, "modulate:a", 1.0, 0.25)
	tween.tween_property(card_lbl, "scale", Vector2.ONE, 0.25)
	_count_total(entry, int(flip.total))

func _count_total(entry: Dictionary, target: int) -> void:
	var from := int(entry.total.text)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		entry.total.text = str(roundi(v)),
		float(from), float(target), 0.3)

func _resort(ranking: Array) -> void:
	for index in ranking.size():
		var seat := int(ranking[index].id)
		if not _rows.has(seat):
			continue
		var entry: Dictionary = _rows[seat]
		entry.rank.text = str(index + 1)
		var tween := create_tween()
		tween.tween_property(entry.row, "position:y", float(index * ROW_H), RESORT_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(RESORT_DURATION + 0.05).timeout

func _champion() -> void:
	if _model.rounds.is_empty():
		return
	var final_ranking: Array = _model.rounds[_model.rounds.size() - 1].ranking
	if final_ranking.is_empty():
		return
	var entry: Dictionary = _rows.get(int(final_ranking[0].id), {})
	if entry.is_empty():
		return
	entry.name.text = "★ %s" % str(entry.name.text)
	entry.name.add_theme_color_override("font_color", Color("f6d77a"))
	var tween := create_tween()
	tween.set_loops(6)
	tween.tween_property(entry.name, "modulate", Color(1.6, 1.35, 0.4), 0.22)
	tween.tween_property(entry.name, "modulate", Color(1.0, 1.0, 1.0), 0.22)
	if _on_winner.is_valid():
		_on_winner.call()
	await tween.finished

func _show_footer() -> void:
	_footer.visible = true
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_footer.add_child(box)
	if _is_host:
		var again := Button.new()
		again.text = "再来一局"
		again.pressed.connect(func() -> void:
			if _on_next_match.is_valid():
				_on_next_match.call())
		box.add_child(again)
		var exit := Button.new()
		exit.text = "返回大厅"
		exit.pressed.connect(func() -> void:
			if _on_abort.is_valid():
				_on_abort.call())
		box.add_child(exit)
	else:
		var wait := Label.new()
		wait.text = "等待房主开始下一局"
		wait.add_theme_color_override("font_color", UITheme.color("text_secondary"))
		box.add_child(wait)