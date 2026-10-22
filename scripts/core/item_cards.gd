class_name ItemCards
extends RefCounted
## 道具卡数据（商店 CARDS 区）。Phase 1：购买/持有/查看/选目标/消耗；效果后续接入。

const SLOT_LIMIT := 3
const PRICE := 50
const REFRESH_COST := 10

const TARGET_NEXT := "next"
const TARGET_OPPONENT := "opponent"
const TARGET_SELF := "self"
const TARGET_NONE := "none"

const FATE_PLUS2_ID := "item_fate_plus2"
const INTERFERE_ID := "item_interfere"
const CHARM_ID := "item_charm"

static func pool() -> Array:
	return [fate_plus2(), interfere(), charm()]

static func def_by_id(id: String) -> Dictionary:
	for card in pool():
		if str(card.get("id", "")) == id:
			return card
	return {}

static func fate_plus2() -> Dictionary:
	# Demo 阶段统一用 opponent，确保任何一张卡都能进入 Q/E 目标锁定流程。
	return _def(FATE_PLUS2_ID, "命运·加二", "选择一名对手，其抽到的手牌点数 +2（效果待接入）",
		"+2", "success", TARGET_OPPONENT)

static func interfere() -> Dictionary:
	return _def(INTERFERE_ID, "干扰", "选择一名对手（效果待接入）",
		"?", "danger", TARGET_OPPONENT)

static func charm() -> Dictionary:
	# Demo 阶段统一用 opponent，确保任何一张卡都能进入 Q/E 目标锁定流程。
	return _def(CHARM_ID, "护符", "选择一名对手（演示：无实际效果）",
		"◆", "accent", TARGET_OPPONENT)

static func _def(id: String, name: String, desc: String, glyph: String, color_key: String, target_mode: String) -> Dictionary:
	return {"id": id, "name": name, "desc": desc, "glyph": glyph,
		"color": color_key, "target_mode": target_mode, "price": PRICE}
