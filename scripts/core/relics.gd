class_name Relics
extends RefCounted
## 遗物数据与池（Milestone 4 才接入效果钩子；本里程碑仅定义 + 入库）。

const RELIC_MIN_BID := 2

static func pool() -> Array:
	return [joker_transform(), guard_shield()]

static func def_by_id(id: String) -> Dictionary:
	for relic in pool():
		if str(relic.get("id", "")) == id:
			return relic
	return {}

static func joker_transform() -> Dictionary:
	return {"id": "relic_joker_transform", "name": "Joker 变换",
		"desc": "抽到 Joker 时可变换为任意牌（未变换时 Joker +2 分）", "min_bid": RELIC_MIN_BID}

static func guard_shield() -> Dictionary:
	return {"id": "relic_guard_shield", "name": "防守护盾",
		"desc": "下一局随机保护一格，免疫贴牌与交换", "min_bid": RELIC_MIN_BID}