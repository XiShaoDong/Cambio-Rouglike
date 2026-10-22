class_name ScoreSystem
extends RefCounted
## 结算系统（Feature 12）
## 职责：计算手牌分数、排名、胜负。纯计算，不持有状态。
## 排序规则：总分 → 牌数量 → 从最大单牌开始逐一比较 → 玩家 id 兜底。

## 计算所有玩家排名（按分数从低到高）。
## players: GameState 的 players 字典；cards: 卡牌定义字典；turn_order: 玩家顺序。
## joker_bonus: {seat: true} 持有 Joker 遗物者的座位集合——其手中的 JOKER 卡分值 +2。
## relic_mods: {seat: {relic_id: true}} 结算类饰品（手牌税/四花色/奇数/重复/三张）。
static func calculate_ranking(players: Dictionary, cards: Dictionary, turn_order: Array,
		joker_bonus: Dictionary = {}, relic_mods: Dictionary = {}) -> Array:
	var ranking: Array = []
	for peer_id in turn_order:
		if int(players[peer_id].get("health", 1)) <= 0:
			continue  # 出局（观战）玩家不参与排名，避免 0 张 0 分恒排第一
		var mods: Dictionary = relic_mods.get(peer_id, {})
		var values: Array[int] = []
		var rank_counts := {}
		var suits := {}
		for card_id in players[peer_id].cards:
			if str(card_id).is_empty():
				continue
			var card: Dictionary = cards[card_id]
			var v: int = int(card.value)
			if joker_bonus.has(peer_id) and str(card.rank) == "JOKER":
				v += 2
			# 每张牌的减分只作用于正分牌，最低 0；K(-1)/Joker(0) 不受影响。
			if v > 0 and mods.has(Relics.TAX_HAND_ID):
				v = maxi(0, v - 1)
			values.append(v)
			var rank := str(card.rank)
			rank_counts[rank] = int(rank_counts.get(rank, 0)) + 1
			suits[str(card.suit)] = true
		# 四花色：必须集齐 ♠♥♣♦（Joker 的红/黑不计）；每张正分牌再 -2。
		var four_suits := suits.has("♠") and suits.has("♥") and suits.has("♣") and suits.has("♦")
		if mods.has(Relics.FOUR_SUITS_ID) and four_suits:
			for i in values.size():
				if values[i] > 0:
					values[i] = maxi(0, values[i] - 2)
		values.sort()
		var total := 0
		for value in values:
			total += value
		if mods.has(Relics.ODD_HAND_ID) and values.size() % 2 == 1:
			total -= 6
		var scaled := float(total)
		if mods.has(Relics.DUPLICATE_ID):
			for rank in rank_counts:
				if int(rank_counts[rank]) >= 2:
					scaled /= 1.5
					break
		if mods.has(Relics.TRIPLE_ID):
			for rank in rank_counts:
				if int(rank_counts[rank]) >= 3:
					scaled /= 2.0
					break
		total = int(floor(scaled))
		ranking.append({"id": peer_id, "name": players[peer_id].name, "score": total, "count": values.size(), "values": values})
	ranking.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _is_lower_score(a, b))
	return ranking

## a 是否排在 b 之前（更差/更小）。
static func _is_lower_score(a: Dictionary, b: Dictionary) -> bool:
	if int(a.score) != int(b.score):
		return int(a.score) < int(b.score)
	if int(a.count) != int(b.count):
		return int(a.count) < int(b.count)
	var a_values: Array = a.values
	var b_values: Array = b.values
	for index in range(min(a_values.size(), b_values.size())):
		if int(a_values[index]) != int(b_values[index]):
			return int(a_values[index]) < int(b_values[index])
	return int(a.id) < int(b.id)

## 两个条目是否同分（score/count/values 完全相同）。
static func same_score(a: Dictionary, b: Dictionary) -> bool:
	return int(a.score) == int(b.score) and int(a.count) == int(b.count) and a.values == b.values
