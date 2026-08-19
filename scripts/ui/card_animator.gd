class_name CardAnimator
extends RefCounted
## 卡牌移动/交换动画（main.gd 拆分补充）
## 职责：在稳定 overlay 上播放卡牌轨迹动画。
## 场景1：玩家间交换（J/Q）——两张牌背面沿轨迹互换。
## 场景2：抽牌堆与自己交换（replace）——玩家旧牌翻出移动至弃牌堆，
##       同时大牌从抽牌堆移动至玩家牌堆并翻到背面。

var main: Node
var _discard_anim_time := 0

func _init(owner_node: Node) -> void:
	main = owner_node

## 抽牌动画：副本从抽牌堆(deck_rect)飞到大牌位置(big_rect)并翻成正面（不改棋盘节点）。
## on_finish 在副本落位后调用（用于显示棋盘大牌 setup）。
func play_draw(data: Dictionary, deck_rect: Rect2, big_rect: Rect2, on_finish: Callable = Callable()) -> void:
	_fly(deck_rect, big_rect, data, false, true, null, on_finish)

## 场景2：抽牌堆与自己交换。actor 为操作者，slot 为被替换的槽位。
func animate_replace(actor: int, slot: int, old_data: Dictionary, big_data: Dictionary) -> void:
	if not main._card_slots.has(actor) or not main._card_slots[actor].has(slot):
		return
	var old_card: Control = main._card_slots[actor][slot]
	if not is_instance_valid(old_card):
		return
	var old_rect: Rect2 = old_card.get_global_rect()
	main.mark_anim_slot(actor, slot)
	# 统计实际执行的动画数，全部完成后才清除标记并重建
	var total := 0
	if is_instance_valid(main.discard_button):
		total += 1
	if is_instance_valid(main.pending_card_button):
		total += 1
	if total == 0:
		main.unmark_anim_slot(actor, slot)
		return
	var counter := {"remaining": total}
	var done := _replace_done.bind(counter, actor, slot)
	# 玩家旧牌 → 弃牌堆：隐藏源卡，副本翻成正面移动到弃牌堆（延迟显示，落位后解锁）
	if is_instance_valid(main.discard_button):
		main._discard_anim_lock = true
		_fly(old_rect, main.discard_button.get_global_rect(), old_data, _face_up_of(old_card), true,
			old_card, done)
	# 大牌 → 玩家 slot：隐藏大牌反馈，副本从两堆中心移动到玩家牌位置并翻成目标槽位当前面
	if is_instance_valid(main.pending_card_button):
		var big_rect: Rect2 = _big_card_rect()
		main.pending_card_box.visible = false
		var big_start_face_up := int(main.latest_state.get("viewer_id", 0)) == actor
		_fly(big_rect, old_rect, big_data, big_start_face_up, _face_up_of(old_card), null, done)

## replace 完成回调：两个副本都完成后清除标记、解锁弃牌堆并重建。
func _replace_done(counter: Dictionary, actor: int, slot: int) -> void:
	counter["remaining"] = int(counter["remaining"]) - 1
	if int(counter["remaining"]) <= 0:
		main.unmark_anim_slot(actor, slot)
		main._discard_anim_lock = false
		main._render_game()

## 场景1：玩家间交换（J/Q）。a 换 a_slot，b 换 b_slot。
func animate_swap(a: int, a_slot: int, b: int, b_slot: int, a_data: Dictionary, b_data: Dictionary) -> void:
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
	# 标记动画槽位 + 隐藏源卡，副本互换（两个动画都完成后才清除标记并重建）
	main.mark_anim_slot(a, a_slot)
	main.mark_anim_slot(b, b_slot)
	var counter := {"remaining": 2}
	_fly(rect_a, rect_b, a_data, _face_up_of(card_a), _face_up_of(card_b), card_a, _swap_done.bind(counter, a, a_slot, b, b_slot))
	_fly(rect_b, rect_a, b_data, _face_up_of(card_b), _face_up_of(card_a), card_b, _swap_done.bind(counter, a, a_slot, b, b_slot))

## 交换动画完成回调：两个副本都完成后清除标记并重建。
func _swap_done(counter: Dictionary, a: int, a_slot: int, b: int, b_slot: int) -> void:
	counter["remaining"] = int(counter["remaining"]) - 1
	if int(counter["remaining"]) <= 0:
		main.unmark_anim_slot(a, a_slot)
		main.unmark_anim_slot(b, b_slot)
		main._render_game()

## 处理 server 广播的交换动画事件（各 client 用自己视角定位）。
func handle_exchange(data: Dictionary) -> void:
	match str(data.get("kind", "")):
		"replace":
			animate_replace(int(data.get("actor", 0)), int(data.get("slot", -1)),
				data.get("old_data", {}), data.get("big_data", {}))
		"swap":
			animate_swap(int(data.get("a", 0)), int(data.get("a_slot", -1)), int(data.get("b", 0)), int(data.get("b_slot", -1)),
				data.get("a_data", {}), data.get("b_data", {}))
		"discard":
			_animate_discard_pending(data.get("big_data", {}), int(data.get("actor", 0)))

## 弃牌动画：pending 大牌从大牌位置移动到弃牌堆（隐藏源反馈，缩放与弃牌堆一致，落位后显示）。
func _animate_discard_pending(big_data: Dictionary, actor: int) -> void:
	# 去重：点击者本地已播，server 事件短时间到达跳过（其他玩家靠事件播）
	var now := Time.get_ticks_msec()
	if now - _discard_anim_time < 1000:
		return
	_discard_anim_time = now
	if is_instance_valid(main.discard_button):
		var big_rect: Rect2 = _big_card_rect()
		main.pending_card_box.visible = false
		main._discard_anim_lock = true
		var big_start_face_up := int(main.latest_state.get("viewer_id", 0)) == actor
		_fly(big_rect, main.discard_button.get_global_rect(), big_data, big_start_face_up, true,
			null, func():
				main._discard_anim_lock = false
				main._render_game())

## 大牌显示位置（两堆中心，1.5 倍尺寸）。
func _big_card_rect() -> Rect2:
	if is_instance_valid(main.deck_button) and is_instance_valid(main.discard_button):
		var deck_r: Rect2 = main.deck_button.get_global_rect()
		var disc_r: Rect2 = main.discard_button.get_global_rect()
		var mid: Vector2 = (deck_r.get_center() + disc_r.get_center()) / 2.0
		var big_size: Vector2 = deck_r.size * 1.5
		return Rect2(mid - big_size / 2.0, big_size)
	if is_instance_valid(main.pending_card_button):
		return main.pending_card_button.get_global_rect()
	return Rect2()

## 读取控件当前显示的面（各 client 自己视角）。
func _face_up_of(card: Control) -> bool:
	if card is CardView:
		return (card as CardView).is_face_up
	return false

## 在 overlay 上创建一张卡牌副本，从 from_rect 飞到 to_rect。
## 按起始/目标尺寸逐步缩放；start/end_face_up 决定是否纵轴翻转（背↔正）。
## 时长随移动距离增长。source_card 为被移动走的原卡（动画开始时隐藏，避免双卡）。
## on_finish 在动画结束（副本落位清理）后调用，用于刷新目标位置。
func _fly(from_rect: Rect2, to_rect: Rect2, data: Dictionary, start_face_up: bool, end_face_up: bool, source_card: Control = null, on_finish: Callable = Callable()) -> void:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.overlay.add_child(layer)
	var from_size := from_rect.size
	var to_size := to_rect.size
	# 距离 → 时长
	var dist := from_rect.get_center().distance_to(to_rect.get_center())
	var dur: float = clampf(0.3 + dist * 0.002, 0.3, 0.9)
	# 起始面卡牌（背面则 data 为空）
	var start_data: Dictionary = data if start_face_up else {}
	var card: Button = main._make_card_button(start_data, from_size)
	card.custom_minimum_size = Vector2.ZERO
	card.pivot_offset = from_size / 2.0
	layer.add_child(card)
	card.global_position = from_rect.position
	# 隐藏源原卡（动画期间源位置不显示）
	if source_card != null and is_instance_valid(source_card):
		source_card.visible = false
	var tween := main.create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	if start_face_up != end_face_up:
		# 需要翻转：纵轴 scale.x 1→0→1，中途切换面
		var end_data: Dictionary = data if end_face_up else {}
		tween.tween_property(card, "scale:x", 0.0, dur * 0.35)
		tween.tween_callback(_reveal_data.bind(card, end_data))
		tween.set_parallel(true)
		tween.tween_property(card, "scale:x", 1.0, dur * 0.65)
		tween.tween_property(card, "global_position", to_rect.position, dur)
		tween.tween_property(card, "size", to_size, dur)
	else:
		# 不需要翻转：直接移动 + 缩放
		tween.set_parallel(true)
		tween.tween_property(card, "global_position", to_rect.position, dur)
		tween.tween_property(card, "size", to_size, dur)
	tween.set_parallel(false)
	tween.tween_callback(_cleanup.bind(layer, on_finish))

## 翻面中途切换牌面数据。
func _reveal_data(card: Control, end_data: Dictionary) -> void:
	if card is CardView:
		(card as CardView).setup(end_data)

## 动画结束：清理副本层，触发完成回调。
func _cleanup(layer: Control, on_finish: Callable) -> void:
	if is_instance_valid(layer):
		layer.queue_free()
	if on_finish.is_valid():
		on_finish.call()