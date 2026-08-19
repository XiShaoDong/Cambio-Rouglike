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

## 场景2：抽牌堆与自己交换。actor 为操作者，slot 为被替换的槽位。
func animate_replace(actor: int, slot: int) -> void:
	if not main._card_slots.has(actor) or not main._card_slots[actor].has(slot):
		return
	var old_card: Control = main._card_slots[actor][slot]
	if not is_instance_valid(old_card):
		return
	var old_rect: Rect2 = old_card.get_global_rect()
	var old_data: Dictionary = _card_data_of(old_card)
	# 玩家旧牌 → 弃牌堆：翻面成正面，移动到弃牌堆并缩放到牌堆大小
	if is_instance_valid(main.discard_button):
		_fly(old_rect, main.discard_button.get_global_rect(), old_data, true)
	# 大牌 → 玩家 slot：移动到玩家牌位置并缩放到手牌大小，翻到背面
	if is_instance_valid(main.pending_card_button):
		var big_rect: Rect2 = main.pending_card_button.get_global_rect()
		var big_data: Dictionary = _card_data_of(main.pending_card_button)
		_fly(big_rect, old_rect, big_data, false)

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
	# 两张牌背面沿轨迹互换，按目标尺寸缩放（不翻面）
	_fly(rect_a, rect_b, _card_data_of(card_a), false)
	_fly(rect_b, rect_a, _card_data_of(card_b), false)

## 处理 server 广播的交换动画事件（各 client 用自己视角定位）。
func handle_exchange(data: Dictionary) -> void:
	match str(data.get("kind", "")):
		"replace":
			animate_replace(int(data.get("actor", 0)), int(data.get("slot", -1)))
		"swap":
			animate_swap(int(data.get("a", 0)), int(data.get("a_slot", -1)), int(data.get("b", 0)), int(data.get("b_slot", -1)))
		"discard":
			_animate_discard_pending()

## 弃牌动画：pending 大牌从抽牌堆移动到弃牌堆（翻成正面）。
func _animate_discard_pending() -> void:
	if is_instance_valid(main.pending_card_button) and is_instance_valid(main.discard_button):
		var big_rect: Rect2 = main.pending_card_button.get_global_rect()
		var big_data: Dictionary = _card_data_of(main.pending_card_button)
		_fly(big_rect, main.discard_button.get_global_rect(), big_data, true)

func _card_data_of(card: Control) -> Dictionary:
	if card is CardView:
		return (card as CardView).card_data
	return {}

## 在 overlay 上创建一张卡牌副本，从 from_rect 飞到 to_rect。
## 按起始/目标尺寸逐步缩放；flip_to_face=true 时先翻成正面，再以正面移动。
func _fly(from_rect: Rect2, to_rect: Rect2, data: Dictionary, flip_to_face: bool) -> void:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.overlay.add_child(layer)
	var from_size := from_rect.size
	var to_size := to_rect.size
	# 背面（起始尺寸，可自由缩放）
	var back_face: Button = main._make_card_button({}, from_size)
	back_face.custom_minimum_size = Vector2.ZERO
	layer.add_child(back_face)
	back_face.global_position = from_rect.position
	# 正面（如需要）
	var front_face: Button = null
	if flip_to_face or not data.is_empty():
		front_face = main._make_card_button(data, from_size)
		front_face.custom_minimum_size = Vector2.ZERO
		front_face.visible = false
		layer.add_child(front_face)
	var tween := main.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	if flip_to_face:
		# 翻面：背面收缩 → 切正面 → 展开
		tween.tween_property(back_face, "scale:x", 0.05, 0.2)
		tween.tween_callback(_reveal_front.bind(back_face, front_face))
		tween.tween_property(front_face, "scale:x", 1.0, 0.2)
		# 正面移动到弃牌堆，同时缩放到目标尺寸
		tween.set_parallel(true)
		tween.tween_property(front_face, "global_position", to_rect.position, 0.5)
		tween.tween_property(front_face, "size", to_size, 0.5)
	else:
		# 背面移动 + 缩放（不翻面）
		tween.set_parallel(true)
		tween.tween_property(back_face, "global_position", to_rect.position, 0.5)
		tween.tween_property(back_face, "size", to_size, 0.5)
	tween.set_parallel(false)
	tween.tween_callback(layer.queue_free)

func _reveal_front(back_face: Control, front_face: Control) -> void:
	back_face.visible = false
	if is_instance_valid(front_face):
		front_face.visible = true