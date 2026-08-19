class_name CardAnimator
extends RefCounted
## 卡牌移动/交换动画（main.gd 拆分补充）
## 职责：在稳定 overlay 上播放卡牌轨迹动画。
## 场景1：玩家间交换（J/Q）——两张牌背面沿轨迹互换。
## 场景2：抽牌堆与自己交换（replace）——玩家旧牌翻出移动至弃牌堆，
##       同时大牌从抽牌堆移动至玩家牌堆并翻到背面。

var main: Node

func _init(owner_node: Node) -> void:
	main = owner_node

## 场景2：抽牌堆与自己交换。slot 为玩家点击的槽位。
func animate_replace(slot: int) -> void:
	var viewer := int(main.latest_state.get("viewer_id", 0))
	if not main._card_slots.has(viewer) or not main._card_slots[viewer].has(slot):
		return
	var old_card: Control = main._card_slots[viewer][slot]
	if not is_instance_valid(old_card):
		return
	var old_rect: Rect2 = old_card.get_global_rect()
	var old_data: Dictionary = {}
	if old_card is CardView:
		old_data = (old_card as CardView).card_data
	# 玩家旧牌 → 弃牌堆：翻出后移动
	if is_instance_valid(main.discard_button):
		_fly(old_rect.position, main.discard_button.get_global_rect().position, old_data, true)
	# 大牌 → 玩家 slot：移动并翻到背面
	if is_instance_valid(main.pending_card_button):
		var big_rect: Rect2 = main.pending_card_button.get_global_rect()
		var big_data: Dictionary = {}
		if main.pending_card_button is CardView:
			big_data = (main.pending_card_button as CardView).card_data
		_fly(big_rect.position, old_rect.position, big_data, false)

## 场景1：玩家间交换（J/Q）。a 换 a_slot，b 换 b_slot。
func animate_swap(a: int, a_slot: int, b: int, b_slot: int) -> void:
	if not main._card_slots.has(a) or not main._card_slots[a].has(a_slot):
		return
	if not main._card_slots.has(b) or not main._card_slots[b].has(b_slot):
		return
	var card_a: Control = main._card_slots[a][a_slot]
	var card_b: Control = main._card_slots[b][b_slot]
	if not is_instance_valid(card_a) or not is_instance_valid(card_b):
		return
	var rect_a: Rect2 = card_a.get_global_rect()
	var rect_b: Rect2 = card_b.get_global_rect()
	# 两张牌背面沿轨迹互换（不翻面）
	_fly(rect_a.position, rect_b.position, _card_data_of(card_a), false)
	_fly(rect_b.position, rect_a.position, _card_data_of(card_b), false)

func _card_data_of(card: Control) -> Dictionary:
	if card is CardView:
		return (card as CardView).card_data
	return {}

## 在 overlay 上创建一张卡牌副本，从 from 飞到 to。
## flip_to_face=true 时先显示背面再翻成正面；否则保持背面移动。
func _fly(from: Vector2, to: Vector2, data: Dictionary, flip_to_face: bool) -> void:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.overlay.add_child(layer)
	var card_size := Vector2(57, 89)
	# 背面
	var back_face: Button = main._make_card_button({}, card_size)
	layer.add_child(back_face)
	back_face.global_position = from
	# 正面（如需要）
	var front_face: Button = null
	if flip_to_face or not data.is_empty():
		front_face = main._make_card_button(data, card_size)
		front_face.visible = false
		layer.add_child(front_face)
	# 移动轨迹
	var tween := main.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	if flip_to_face:
		# 先翻成正面再移动
		tween.tween_property(back_face, "scale:x", 0.05, 0.2)
		tween.tween_callback(_reveal_front.bind(back_face, front_face))
		tween.tween_property(front_face, "scale:x", 1.0, 0.2)
		tween.tween_property(front_face, "global_position", to, 0.5)
	else:
		tween.tween_property(back_face, "global_position", to, 0.5)
	tween.tween_callback(layer.queue_free)

func _reveal_front(back_face: Control, front_face: Control) -> void:
	back_face.visible = false
	if is_instance_valid(front_face):
		front_face.visible = true