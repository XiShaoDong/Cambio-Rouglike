class_name SeriesRanking
extends RefCounted
## 系列赛把末总排名（纯计算，不持有状态）。
## 存活者：胜场降序 → 货币降序 → seat 升序；淘汰者不入榜。

static func final_ranking(players: Dictionary, turn_order: Array) -> Array:
	var entries: Array = []
	for seat in turn_order:
		var p: Dictionary = players[int(seat)]
		if int(p.get("health", 0)) <= 0:
			continue
		entries.append({
			"id": int(seat),
			"name": str(p.get("name", "")),
			"wins": int(p.get("wins", 0)),
			"currency": int(p.get("currency", 0)),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.wins) != int(b.wins):
			return int(a.wins) > int(b.wins)
		if int(a.currency) != int(b.currency):
			return int(a.currency) > int(b.currency)
		return int(a.id) < int(b.id))
	return entries
