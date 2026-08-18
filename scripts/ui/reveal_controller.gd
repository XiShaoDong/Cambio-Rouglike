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
	var center := anchor.get_global_rect().get_center()
	_play_flip_at(center, card)

## 在全局坐标 center 处播放翻牌动画（挂到稳定的 overlay，避免被界面重建释放）。
func _play_flip_at(center: Vector2, card: Dictionary) -> void:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.overlay.add_child(layer)
	var card_size := Vector2(90, 140)
	layer.global_position = center - card_size / 2.0
	layer.custom_minimum_size = card_size
	# 背面：先展示（代表被点击的那张牌）
	var back_face: Button = main._make_card_button({}, card_size)
	back_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(back_face)
	back_face.pivot_offset = back_face.size / 2.0
	# 正面：真实牌面（预创建但隐藏）
	var front_face: Button = main._make_card_button(card, card_size)
	front_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front_face.visible = false
	layer.add_child(front_face)
	front_face.pivot_offset = front_face.size / 2.0
	# 阶段1：背面收缩到 0
	await _scale_to(back_face, 0.05, 0.25)
	if not is_instance_valid(layer) or not is_instance_valid(back_face) or not is_instance_valid(front_face):
		return
	# 阶段2：切换为正面，展开
	back_face.visible = false
	front_face.visible = true
	await _scale_to(front_face, 1.0, 0.25)
	if not is_instance_valid(layer) or not is_instance_valid(front_face):
		return
	# 阶段3：停留展示
	await main.get_tree().create_timer(1.0).timeout
	if not is_instance_valid(layer) or not is_instance_valid(front_face):
		return
	# 阶段4：正面收缩，翻回背面
	await _scale_to(front_face, 0.05, 0.25)
	if not is_instance_valid(layer) or not is_instance_valid(front_face) or not is_instance_valid(back_face):
		return
	front_face.visible = false
	back_face.visible = true
	await _scale_to(back_face, 1.0, 0.25)
	if is_instance_valid(layer):
		layer.queue_free()

func _scale_to(node: Control, x: float, duration: float) -> void:
	var tween := main.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "scale:x", x, duration)
	await tween.finished