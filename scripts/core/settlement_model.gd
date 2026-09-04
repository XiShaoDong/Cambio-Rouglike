class_name SettlementModel
extends RefCounted
## 结算模型（同步轮记分，纯计算）
## 每轮所有玩家一起翻开各自第 N 张牌，各自 running_total 累加，随后整表按累计分实时重排。

static func build(players: Array) -> Dictionary:
	var layout_order: Array = []
	for player in players:
		layout_order.append(int(player.id))
	var max_slots := 0
	for player in players:
		max_slots = maxi(max_slots, int(player.slots.size()))
	var rounds: Array = []
	var totals: Dictionary = {}
	var revealed: Dictionary = {}
	for slot in max_slots:
		var flips: Array = []
		for player in players:
			var seat := int(player.id)
			var entry: Dictionary = player.slots[slot] if slot < player.slots.size() else {}
			if entry.has("card"):
				var value := int(entry.card.value)
				totals[seat] = int(totals.get(seat, 0)) + value
				revealed[seat] = (revealed.get(seat, []) as Array) + [value]
				flips.append({
					"seat": seat,
					"value": value,
					"rank": str(entry.card.rank),
					"suit": str(entry.card.suit),
					"total": int(totals[seat]),
				})
		rounds.append({"slot": slot, "flips": flips, "ranking": _ranking(players, totals, revealed)})
	return {"layout_order": layout_order, "rounds": rounds}

static func _ranking(players: Array, totals: Dictionary, revealed: Dictionary) -> Array:
	var entries: Array = []
	for player in players:
		var seat := int(player.id)
		var values: Array = (revealed.get(seat, []) as Array).duplicate()
		values.sort()
		entries.append({
			"id": seat,
			"name": str(player.name),
			"score": int(totals.get(seat, 0)),
			"count": values.size(),
			"values": values,
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return ScoreSystem._is_lower_score(a, b))
	return entries