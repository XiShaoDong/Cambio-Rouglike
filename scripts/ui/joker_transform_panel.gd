class_name JokerTransformPanel
extends Control
## Joker 变换面板：选点数(13) + 花色(4)，预览，确认/取消。Enter 确认、Esc 取消。

const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const SUITS := ["♠", "♥", "♣", "♦"]

var _rank := "7"
var _suit := "♠"
var _on_confirm: Callable = Callable()
var _on_cancel: Callable = Callable()

func setup(on_confirm: Callable, on_cancel: Callable) -> void:
	_on_confirm = on_confirm
	_on_cancel = on_cancel
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = get_node("Center/Panel")
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.color("bg_elevated")
	style.bg_color.a = 1.0
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)
	style.border_color = UITheme.color("border")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	var rank_grid: GridContainer = get_node("Center/Panel/VBox/RankRow")
	for rank in RANKS:
		var btn := Button.new()
		btn.text = rank
		btn.custom_minimum_size = Vector2(40, 32)
		btn.pressed.connect(_pick_rank.bind(rank))
		rank_grid.add_child(btn)
	var suit_row: HBoxContainer = get_node("Center/Panel/VBox/SuitRow")
	for suit in SUITS:
		var btn := Button.new()
		btn.text = suit
		btn.custom_minimum_size = Vector2(52, 36)
		btn.pressed.connect(_pick_suit.bind(suit))
		suit_row.add_child(btn)
	get_node("Center/Panel/VBox/Actions/Cancel").pressed.connect(_cancel)
	get_node("Center/Panel/VBox/Actions/Confirm").pressed.connect(_confirm)
	_refresh()

func _pick_rank(rank: String) -> void:
	_rank = rank
	_refresh()

func _pick_suit(suit: String) -> void:
	_suit = suit
	_refresh()

func _refresh() -> void:
	var preview: Label = get_node("Center/Panel/VBox/Preview")
	preview.text = "预览：%s%s" % [_rank, _suit]

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_confirm()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_cancel()
			get_viewport().set_input_as_handled()

func _confirm() -> void:
	if _on_confirm.is_valid():
		_on_confirm.call(_rank, _suit)
	visible = false

func _cancel() -> void:
	if _on_cancel.is_valid():
		_on_cancel.call()
	visible = false