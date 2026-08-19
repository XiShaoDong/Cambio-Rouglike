class_name CardView
extends Button
## 卡牌视图节点（Feature 01）
## 职责：正面/背面图片渲染、点击信号、高亮、翻牌/发牌动画。
## 不负责：任何规则判断（可点击性、可替换、Slap 合法性等由 GameState/UI 决定）。
## 素材：res://assets/Cards/back07.png（背面），{suit}_{rank}.png（正面）。

signal card_clicked(view: CardView)

const BACK_TEXTURE := "res://assets/Cards/back07.png"
const CARD_DIR := "res://assets/Cards/"

var card_data: Dictionary = {}
var is_face_up := false
var enabled_hover := true

@onready var back: PanelContainer = $Back
@onready var back_texture: TextureRect = $Back/BackTexture
@onready var front: PanelContainer = $Front
@onready var front_texture: TextureRect = $Front/FrontTexture

var _pending_setup := false
var _pending_highlight := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	pressed.connect(func(): card_clicked.emit(self))
	back_texture.texture = load(BACK_TEXTURE)
	_refresh()
	if _pending_setup:
		_pending_setup = false
	if _pending_highlight:
		_pending_highlight = false
		set_highlight(true)

## 设置卡牌数据；card 为空则显示背面。
func setup(data: Dictionary) -> void:
	card_data = data
	is_face_up = not data.is_empty()
	if not is_inside_tree():
		_pending_setup = true
		return
	_refresh()

func _refresh() -> void:
	if not is_inside_tree() or not is_instance_valid(front_texture):
		return
	front.visible = is_face_up and not card_data.is_empty()
	back.visible = not front.visible
	if front.visible:
		front_texture.texture = _front_texture()

## 根据 rank/suit 计算正面素材路径。
func _front_texture() -> Texture2D:
	var rank := str(card_data.get("rank", "?"))
	var suit := str(card_data.get("suit", ""))
	var path := ""
	if rank == "JOKER":
		path = CARD_DIR + ("Joker1.png" if suit == "red" else "Joker2.png")
	else:
		var suit_file := _suit_file(suit)
		var rank_file := _rank_file(rank)
		path = CARD_DIR + "%s_%s.png" % [suit_file, rank_file]
	var tex := load(path)
	return tex if tex != null else load(BACK_TEXTURE)

func _suit_file(suit: String) -> String:
	match suit:
		"♠": return "spades"
		"♥": return "hearts"
		"♣": return "clubs"
		"♦": return "diamonds"
	return "spades"

func _rank_file(rank: String) -> String:
	match rank:
		"A": return "ace"
		"J": return "jack"
		"Q": return "queen"
		"K": return "king"
		"10": return "10"
		_: return "0" + rank

## 高亮（金色提亮 + 边框）；关闭时恢复。
func set_highlight(on: bool) -> void:
	_pending_highlight = on
	if not is_inside_tree() or not is_instance_valid(front) or not is_instance_valid(back):
		return
	if on:
		modulate = Color(1.25, 1.18, 0.9, 1.0)
		scale = Vector2(1.05, 1.05)
	else:
		modulate = Color.WHITE
		scale = Vector2.ONE

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
	tween.tween_property(self, "scale:x", 0.05, 0.42)
	tween.tween_callback(_finish_flip.bind(from, to, 0.42))

## 纵轴翻转：绕垂直中线 scale.x 1→0→1，中途切换面到指定面。face_up=true 显示正面。
func flip_to_face(face_up: bool) -> void:
	pivot_offset = size / 2.0
	var from := front if front.visible else back
	var to := front if face_up else back
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale:x", 0.0, 0.225)
	tween.tween_callback(_finish_flip.bind(from, to, 0.225))

## 翻面后半段：切换面并展开（独立 tween，避免在已启动 tween 内追加）。
func _finish_flip(from: Control, to: Control, dur: float) -> void:
	if not is_instance_valid(from) or not is_instance_valid(to):
		return
	from.visible = false
	to.visible = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale:x", 1.0, dur)

## 发牌/移动动画：从 from_pos 飞到当前位置。
func animate_from(from_pos: Vector2) -> void:
	global_position = from_pos
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", get_parent().global_position + position, 0.4)
