class_name RevealController
extends RefCounted
## 看牌揭示控制器（main.gd 拆分 · 第四优先级）
## 职责：处理 private reveal，在点击卡牌位置播放翻牌动画。
## 动画节点挂到稳定 overlay，避免被对局界面重建释放。持有 main 引用。

var main: Node

func _init(owner_node: Node) -> void:
	main = owner_node

## 收到私下揭示：对每张牌在目标位置播放翻牌。
func show_private_reveal(_title: String, revealed_cards: Array, target: Dictionary = {}) -> void:
	for card in revealed_cards:
		_flip_card_show(card, target)

func _flip_card_show(card: Dictionary, target: Dictionary = {}) -> void:
	var anchor: Control = null
	var target_id := int(target.get("player_id", 0))
	var slot := int(target.get("slot", -1))
	if main._card_slots.has(target_id) and main._card_slots[target_id].has(slot):
		var candidate: Control = main._card_slots[target_id][slot]
		if is_instance_valid(candidate):
			anchor = candidate
	if anchor == null:
		# 目标卡牌尚未渲染或已释放（reveal 与状态广播时序），挂起到渲染后执行
		main._pending_flips.append({"card": card, "target_id": target_id, "slot": slot})
		return
	_flip_at(anchor, card)

func _flip_at(anchor: Control, card: Dictionary) -> void:
	_play_flip_at(anchor, card)

## 在锚点位置翻牌展示（保持卡牌尺寸，只纵轴翻转，不缩放）。
func _play_flip_at(anchor: Control, card: Dictionary) -> void:
	var rect: Rect2 = anchor.get_global_rect()
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.overlay.add_child(layer)
	var card_size := rect.size
	layer.global_position = rect.position
	layer.custom_minimum_size = card_size
	# 单个卡牌：设置正面数据，强制背面起点，纵轴翻到正面展示
	var card_node: Button = main._make_card_button(card, card_size)
	card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(card_node)
	if card_node is CardView:
		var cv := card_node as CardView
		cv.back.visible = true
		cv.front.visible = false
		cv.flip_to_face(true)
		await main.get_tree().create_timer(1.0).timeout
		if is_instance_valid(cv):
			cv.flip_to_face(false)
		await main.get_tree().create_timer(0.5).timeout
	if is_instance_valid(layer):
		layer.queue_free()