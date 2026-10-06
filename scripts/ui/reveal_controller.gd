class_name RevealController
extends RefCounted
## 看牌揭示控制器（main.gd 拆分 · 第四优先级）
## 职责：处理 private reveal，在点击卡牌位置播放翻牌动画。
## 动画节点挂到稳定 overlay，避免被对局界面重建释放。持有 main 引用。

var main: Node

func _init(owner_node: Node) -> void:
	main = owner_node

## 收到私下揭示：对每张牌在目标位置播放翻牌。
## hold=true（Q 能力）：翻到正面后**保持**不翻回，直到 release_held_peeks()。
func show_private_reveal(_title: String, revealed_cards: Array, target: Dictionary = {}, hold := false) -> void:
	for card in revealed_cards:
		_flip_card_show(card, target, hold)

func _flip_card_show(card: Dictionary, target: Dictionary = {}, hold := false) -> void:
	var anchor: Control = null
	var target_id := int(target.get("player_id", 0))
	var slot := int(target.get("slot", -1))
	if main._card_slots.has(target_id) and main._card_slots[target_id].has(slot):
		var candidate: Control = main._card_slots[target_id][slot]
		if is_instance_valid(candidate):
			anchor = candidate
	if anchor == null:
		# 目标卡牌尚未渲染或已释放（reveal 与状态广播时序），挂起到渲染后执行
		var entry := {"card": card, "target_id": target_id, "slot": slot}
		if target.has("correct"):
			entry["correct"] = bool(target.correct)
		if hold:
			entry["hold"] = true
		main._pending_flips.append(entry)
		return
	_flip_at(anchor, card, target_id, slot, target.has("correct"), bool(target.get("correct", false)), hold)

## 按是否贴牌 reveal 分发：贴牌走 _play_slap_flip（对错都带炫光），看牌走 _play_flip_at。
func _flip_at(anchor: Control, card: Dictionary, target_id: int = 0, slot: int = -1, is_slap := false, correct := false, hold := false) -> void:
	if is_slap:
		_play_slap_flip(anchor, card, target_id, slot, correct)
	else:
		_play_flip_at(anchor, card, target_id, slot, hold)

## 在锚点位置翻牌展示（保持卡牌尺寸，只纵轴翻转，不缩放）。
## 期间把该槽位标记为动画中（渲染为空占位），避免露出底下默认背面。
## 同时上判定锁：贴牌判定翻牌期间禁止再点击新牌（`main._slap_reveal_lock`）。
## 看牌的 hold 揭示登记："pid_slot" -> {layer, card_node, cv}（Q 能力确认前不翻回）。
var _held_peek: Dictionary = {}

func _play_flip_at(anchor: Control, card: Dictionary, target_id: int = 0, slot: int = -1, hold := false) -> void:
	main._slap_reveal_begin()
	var rect: Rect2 = anchor.get_global_rect()
	# 隐藏底下原卡 + 标记槽位为空占位（render 重建时也不露默认背面）
	if is_instance_valid(anchor):
		anchor.visible = false
	if slot >= 0:
		main.mark_anim_slot(target_id, slot)
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
		if hold:
			# Q 能力：保持正面，登记等待 release_held_peeks()；槽位继续标记为动画（render 不重建）
			_held_peek["%d_%d" % [target_id, slot]] = {"layer": layer, "card_node": card_node, "cv": cv}
			main._slap_reveal_end()
			return
		await main.get_tree().create_timer(1.0).timeout
		if is_instance_valid(cv):
			cv.flip_to_face(false)
		await main.get_tree().create_timer(0.5).timeout
	if is_instance_valid(layer):
		layer.queue_free()
	# 清除动画标记并刷新槽位
	if slot >= 0:
		main.unmark_anim_slot(target_id, slot)
	main._render_game_if_active()
	main._slap_reveal_end()
	if is_instance_valid(anchor):
		anchor.visible = true

## 某槽位是否有 Q hold 揭示。
func has_held(pid: int, slot: int) -> bool:
	return _held_peek.has("%d_%d" % [pid, slot])

## 取走并释放某槽位的 hold（不翻回，供交换飞牌从正面起飞），返回揭示牌面（无则 {}）。
func consume_held(pid: int, slot: int) -> Dictionary:
	var key := "%d_%d" % [pid, slot]
	if not _held_peek.has(key):
		return {}
	var held: Dictionary = _held_peek[key]
	_held_peek.erase(key)
	var card: Dictionary = {}
	if is_instance_valid(held.get("cv")) and held.cv is CardView:
		card = (held.cv as CardView).card_data
	if is_instance_valid(held.get("layer")):
		held.layer.queue_free()
	main.unmark_anim_slot(pid, slot)
	return card

## 释放全部 Q 能力 hold 的看牌。animate_back=true 先播翻回动画再清理（槽位在动画期间
## 仍标记为动画，render 不重建，副本在 overlay 上跨广播持续），false 立即清理。
func release_held_peeks(animate_back := true) -> void:
	if _held_peek.is_empty():
		return
	var items: Dictionary = _held_peek.duplicate()
	_held_peek.clear()
	if animate_back:
		for key in items.keys():
			var held: Dictionary = items[key]
			if is_instance_valid(held.get("cv")):
				(held.cv as CardView).flip_to_face(false)
		main.get_tree().create_timer(0.5).timeout.connect(func():
			for key in items.keys():
				_free_held_entry(key, items[key])
			main._render_game_if_active())
	else:
		for key in items.keys():
			_free_held_entry(key, items[key])
		main._render_game_if_active()

## 清理一个 hold 条目：移除 overlay 副本、撤销槽位动画标记。
func _free_held_entry(key: String, held: Dictionary) -> void:
	if is_instance_valid(held.get("layer")):
		held.layer.queue_free()
	var parts := str(key).split("_")
	var pid := int(parts[0])
	var slot := int(parts[1])
	main.unmark_anim_slot(pid, slot)
	if main._card_slots.has(pid) and main._card_slots[pid].has(slot):
		var anchor: Control = main._card_slots[pid][slot]
		if anchor != null and is_instance_valid(anchor):
			anchor.visible = true

## 贴牌判定翻牌：翻到正面后按对错打炫光（绿=对，红=错）。
## 正确：绿光 hold 不翻回（v2），等待结算事件（slap_resolved）直接 fly 或翻回；
## 错误：红光停留后翻回，罚牌动画由 slap_penalty 事件另行触发。
var _held_slap: Dictionary = {}  # "pid_slot" -> {layer, card_node, cv}

func _play_slap_flip(anchor: Control, card: Dictionary, target_id: int, slot: int, correct: bool) -> void:
	main._slap_reveal_begin()
	var rect: Rect2 = anchor.get_global_rect()
	if is_instance_valid(anchor):
		anchor.visible = false
	if slot >= 0:
		main.mark_anim_slot(target_id, slot)
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.overlay.add_child(layer)
	var card_size := rect.size
	layer.global_position = rect.position
	layer.custom_minimum_size = card_size
	var card_node: Button = main._make_card_button(card, card_size)
	card_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(card_node)
	if card_node is CardView:
		var cv := card_node as CardView
		cv.back.visible = true
		cv.front.visible = false
		cv.flip_to_face(true)
		if correct:
			# 正确：绿光保持，登记 hold 等待结算（结算时 release_slap_except 翻回输家 / free_slap 交 fly）
			cv.set_glow(main.SLAP_CORRECT_GLOW, main.SLAP_GLOW_SIZE)
			_held_slap["%d_%d" % [target_id, slot]] = {"layer": layer, "card_node": card_node, "cv": cv}
			return
		cv.set_glow(main.SLAP_WRONG_GLOW, main.SLAP_GLOW_SIZE)
		await main.get_tree().create_timer(0.9).timeout
		if is_instance_valid(cv):
			cv.flip_to_face(false)
		await main.get_tree().create_timer(0.5).timeout
	# anchor 可能被 render 重建释放（罚牌广播渲染），无效时跳过恢复（新槽位已可见）
	_cleanup_slap(layer, target_id, slot, anchor if is_instance_valid(anchor) else null)

## 释放指定槽位的 hold 翻牌（赢家：交 fly，直接清 overlay，槽位标记由 fly 接管）。
func free_slap(target_id: int, slot: int) -> void:
	var key := "%d_%d" % [target_id, slot]
	if not _held_slap.has(key):
		return
	var held: Dictionary = _held_slap[key]
	_held_slap.erase(key)
	if is_instance_valid(held.layer):
		held.layer.queue_free()
	main._slap_reveal_end()

## 翻回除 keep 槽外的所有 hold 翻牌（比拼输家），延迟释放等翻回动画播完。
func release_slap_except(keep_target: int, keep_slot: int) -> void:
	var keep_key := "%d_%d" % [keep_target, keep_slot]
	for key in _held_slap.keys():
		if key == keep_key:
			continue
		var held: Dictionary = _held_slap[key]
		var parts := str(key).split("_")
		var pid := int(parts[0])
		var slot := int(parts[1])
		_held_slap.erase(key)
		if is_instance_valid(held.cv):
			held.cv.flip_to_face(false)
		main._slap_reveal_end()
		var layer: Control = held.layer
		main.get_tree().create_timer(0.5).timeout.connect(func():
			if is_instance_valid(layer):
				layer.queue_free()
			main.unmark_anim_slot(pid, slot)
			main._render_game_if_active())

## 贴牌翻牌收尾：清理 overlay、解除槽位标记、渲染并解锁判定锁。
func _cleanup_slap(layer: Control, target_id: int, slot: int, anchor: Control) -> void:
	if is_instance_valid(layer):
		layer.queue_free()
	if slot >= 0:
		main.unmark_anim_slot(target_id, slot)
	main._render_game_if_active()
	main._slap_reveal_end()
	if is_instance_valid(anchor):
		anchor.visible = true
