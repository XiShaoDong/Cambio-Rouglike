class_name CardView
extends Button
## 卡牌视图节点（Feature 01）
## 职责：正面/背面渲染、点击信号、高亮、翻牌/发牌动画。
## 不负责：任何规则判断（可点击性、可替换、Slap 合法性等由 GameState/UI 决定）。

signal card_clicked(view: CardView)

var card_data: Dictionary = {}
var is_face_up := false
var enabled_hover := true

@onready var back: PanelContainer = $Back
@onready var back_card: Control = $Back/BackCard
@onready var back_label: Label = $Back/BackCard/BackLabel
@onready var front: PanelContainer = $Front
@onready var rank_label: Label = $Front/FrontCard/RankLabel
@onready var suit_label: Label = $Front/FrontCard/SuitLabel
@onready var value_label: Label = $Front/FrontCard/ValueLabel

var _base_back_style: StyleBoxFlat
var _base_front_style: StyleBoxFlat
var _pending_setup := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	pressed.connect(func(): card_clicked.emit(self))
	_build_styles()
	_refresh()
	if _pending_setup:
		_pending_setup = false

func _build_styles() -> void:
	var back_style := StyleBoxFlat.new()
	back_style.set_corner_radius_all(8)
	back_style.bg_color = UITheme.color("card_back_bg")
	back_style.border_color = UITheme.color("card_back_border")
	back_style.set_border_width_all(clampi(int(size.x * 0.05), 2, 5))
	back.add_theme_stylebox_override("panel", back_style)
	_base_back_style = back_style
	back_label.add_theme_font_size_override("font_size", maxi(18, int(size.x * 0.4)))
	back_label.add_theme_color_override("font_color", UITheme.color("card_back_border"))

	var front_style := StyleBoxFlat.new()
	front_style.set_corner_radius_all(8)
	front_style.bg_color = UITheme.color("card_face_bg")
	front_style.border_color = UITheme.color("card_border")
	front_style.set_border_width_all(1)
	front.add_theme_stylebox_override("panel", front_style)
	_base_front_style = front_style

## 设置卡牌数据；card 为空则显示背面。
func setup(data: Dictionary) -> void:
	card_data = data
	is_face_up = not data.is_empty()
	if not is_inside_tree():
		_pending_setup = true
		return
	_refresh()

func _refresh() -> void:
	if not is_inside_tree():
		return
	front.visible = is_face_up and not card_data.is_empty()
	back.visible = not front.visible
	if front.visible:
		var rank := str(card_data.get("rank", "?"))
		var suit := str(card_data.get("suit", ""))
		var value := int(card_data.get("value", 0))
		var is_joker := rank == "JOKER"
		var is_red := suit == "♥" or suit == "♦" or (is_joker and suit == "red")
		var color := UITheme.color("card_rank_red") if is_red else UITheme.color("card_rank_black")
		rank_label.text = "J" if is_joker else rank
		rank_label.add_theme_color_override("font_color", color)
		suit_label.text = "🃏" if is_joker else suit
		suit_label.add_theme_color_override("font_color", color)
		value_label.text = str(value)
		value_label.add_theme_color_override("font_color", UITheme.color("card_value"))
		_resize_labels()

func _resize_labels() -> void:
	var is_big := size.y >= 60.0
	var is_xl := size.y >= 95.0
	rank_label.add_theme_font_size_override("font_size", 18 if is_xl else (15 if is_big else 11))
	suit_label.add_theme_font_size_override("font_size", 30 if is_xl else (24 if is_big else 16))
	value_label.add_theme_font_size_override("font_size", 17 if is_xl else (14 if is_big else 10))

## 高亮（金色光晕）；关闭时恢复基础样式。
func set_highlight(on: bool) -> void:
	var target := front if front.visible else back
	if on:
		var glow := UITheme.color("highlight_glow")
		var style := (_base_back_style if not front.visible else _base_front_style).duplicate() as StyleBoxFlat
		style.shadow_color = glow
		style.shadow_size = 10
		style.border_color = glow
		style.set_border_width_all(maxi(2, int(size.x * 0.06)))
		target.add_theme_stylebox_override("panel", style)
	else:
		target.add_theme_stylebox_override("panel", _base_back_style if not front.visible else _base_front_style)

## 翻牌动画：当前面翻到另一面（scale.x 收缩→切面→展开）。
func flip_show() -> void:
	var from := front if front.visible else back
	var to := back if front.visible else front
	_create_flip(from, to)

func _create_flip(from: Control, to: Control) -> void:
	pivot_offset = size / 2.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale:x", 0.05, 0.28)
	tween.tween_callback(func():
		from.visible = false
		to.visible = true
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "scale:x", 1.0, 0.28))

## 发牌/移动动画：从 from_pos 飞到当前位置。
func animate_from(from_pos: Vector2) -> void:
	global_position = from_pos
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", get_parent().global_position + position, 0.4)