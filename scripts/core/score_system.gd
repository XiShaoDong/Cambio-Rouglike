class_name ScoreSystem
extends RefCounted
## 结算系统（Feature 12）
## 职责：计算手牌分数、排名、胜负。纯计算，不持有状态。
## 排序规则：总分 → 牌数量 → 从最大单牌开始逐一比较 → 玩家 id 兜底。

## 计算所有玩家排名（按分数从低到高）。
## players: GameState 的 players 字典；cards: 卡牌定义字典；turn_order: 玩家顺序。
static func calculate_ranking(players: Dictionary, cards: Dictionary, turn_order: Array) -> Array:
	var ranking: Array = []
	for peer_id in turn_order:
		var values: Array[int] = []
		for card_id in players[peer_id].cards:
			values.append(int(cards[card_id].value))
		values.sort()
		var total := 0
		for value in values:
			total += value
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
