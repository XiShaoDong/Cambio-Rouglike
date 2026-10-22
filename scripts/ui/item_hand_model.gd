class_name ItemHandModel
extends RefCounted
## 道具手牌纯状态：卡列表 / 选中索引 / 目标模式 / 目标索引。

var cards: Array[String] = []
var selected := 0
var target_mode := false
var targets: Array[int] = []
var target_index := 0

func set_cards(ids: Array) -> void:
	cards.clear()
	for id in ids:
		var s := str(id)
		if not s.is_empty():
			cards.append(s)
	selected = clampi(selected, 0, maxi(0, cards.size() - 1))
	if cards.is_empty():
		selected = 0

func count() -> int:
	return cards.size()

func selected_id() -> String:
	if selected < 0 or selected >= cards.size():
		return ""
	return cards[selected]

func selected_def() -> Dictionary:
	return ItemCards.def_by_id(selected_id())

func cycle_card(dir: int) -> void:
	if cards.is_empty():
		selected = 0
		return
	selected = ItemHandMath.cycle(selected, cards.size(), dir)

func begin_target(target_ids: Array) -> void:
	targets.clear()
	for id in target_ids:
		targets.append(int(id))
	target_index = 0
	target_mode = not targets.is_empty()

func cycle_target(dir: int) -> void:
	if targets.is_empty():
		target_index = 0
		return
	target_index = ItemHandMath.cycle(target_index, targets.size(), dir)

func target_seat() -> int:
	if not target_mode or target_index < 0 or target_index >= targets.size():
		return -1
	return targets[target_index]

func end_target() -> void:
	target_mode = false
	targets.clear()
	target_index = 0
