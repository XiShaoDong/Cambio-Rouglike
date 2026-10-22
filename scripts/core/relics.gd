class_name Relics
extends RefCounted
## 遗物数据与池。Phase 1：定义 + 商店展示 + 占位字符；效果钩子后续接入。

const RELIC_PRICE := 50
const SHOP_REFRESH_COST := 10
const JOKER_TRANSFORM_ID := "relic_joker_transform"
const GUARD_SHIELD_ID := "relic_guard_shield"
const TAX_HAND_ID := "relic_tax_hand"
const FOUR_SUITS_ID := "relic_four_suits"
const ODD_HAND_ID := "relic_odd_hand"
const DUPLICATE_ID := "relic_duplicate"
const TRIPLE_ID := "relic_triple"
const PEEK_REDUCE_ID := "relic_peek_reduce"
const PEEK_FLEX_ID := "relic_peek_flex"
const ODD_PEEK_ID := "relic_odd_peek"
const EVEN_PEEK_ID := "relic_even_peek"
const SLAP_BONUS_ID := "relic_slap_bonus"
const JACK_BONUS_ID := "relic_jack_bonus"
const PEEK_BONUS_ID := "relic_peek_bonus"

static func pool() -> Array:
	return [
		joker_transform(),
		guard_shield(),
		tax_hand(),
		four_suits(),
		odd_hand(),
		duplicate(),
		triple(),
		peek_reduce(),
		peek_flex(),
		odd_peek(),
		even_peek(),
		slap_bonus(),
		jack_bonus(),
		peek_bonus(),
	]

static func def_by_id(id: String) -> Dictionary:
	for relic in pool():
		if str(relic.get("id", "")) == id:
			return relic
	return {}

static func glyph_for(id: String) -> String:
	var def := def_by_id(id)
	return str(def.get("glyph", "?"))

static func joker_transform() -> Dictionary:
	return _def("relic_joker_transform", "Joker 变换",
		"抽到 Joker 时可变换为任意牌（未变换时 Joker +2 分）", "J", "accent", "utility")

static func guard_shield() -> Dictionary:
	return _def("relic_guard_shield", "防守护盾",
		"下一局随机保护一格，免疫贴牌与交换", "◇", "relic_shield", "utility")

static func tax_hand() -> Dictionary:
	return _def(TAX_HAND_ID, "手牌税",
		"手牌大于 4 张时，每张牌 -1 分（负分牌不受影响，最低到 0）", "-1", "danger", "score_down")

static func four_suits() -> Dictionary:
	return _def(FOUR_SUITS_ID, "四花色压制",
		"手牌包含四个花色时，每张牌 -2 分（负分牌不受影响，最低到 0）", "4", "danger", "score_down")

static func odd_hand() -> Dictionary:
	return _def(ODD_HAND_ID, "奇数惩罚",
		"手牌数量为奇数时，总分 -6", "-6", "danger", "score_down")

static func duplicate() -> Dictionary:
	return _def(DUPLICATE_ID, "重复折半",
		"手牌中有相同点数的牌时，总分 ÷1.5", "/1.5", "danger", "score_down")

static func triple() -> Dictionary:
	return _def(TRIPLE_ID, "三张相同",
		"手牌中有三张或以上相同点数的牌时，总分 ÷2，可与重复折半叠加", "/2", "danger", "score_down")

static func peek_reduce() -> Dictionary:
	return _def(PEEK_REDUCE_ID, "窥视削弱",
		"使用 7/8 查看自己的牌时，可使被查看的牌 -1 分（可降到负分，本局有效）", "7", "accent", "vision")

static func peek_flex() -> Dictionary:
	return _def(PEEK_FLEX_ID, "视野互换",
		"7/8 可以当 9/10 用（看别人），9/10 可以当 7/8 用（看自己）", "<>", "accent", "vision")

static func odd_peek() -> Dictionary:
	return _def(ODD_PEEK_ID, "奇数视野",
		"每回合限一次：从抽牌堆抽到无能力的奇数牌时，可选择当作 7/8 查看自己一张", "ODD", "accent", "vision")

static func even_peek() -> Dictionary:
	return _def(EVEN_PEEK_ID, "偶数视野",
		"每回合限一次：从抽牌堆抽到无能力的偶数牌时，可选择当作 9/10 查看别人一张", "EVEN", "accent", "vision")

static func slap_bonus() -> Dictionary:
	return _def(SLAP_BONUS_ID, "贴牌加成",
		"每回合限一次：成功贴其他玩家的牌后，交给对方的牌 +3 分（本局有效）", "+3", "success", "score_up")

static func jack_bonus() -> Dictionary:
	return _def(JACK_BONUS_ID, "J 交换加成",
		"每回合限一次：使用 J 交换时，交给对方的牌 +2 分（本局有效）", "+2", "success", "score_up")

static func peek_bonus() -> Dictionary:
	return _def(PEEK_BONUS_ID, "窥视加成",
		"每回合限一次：使用 9/10 查看别人的牌时，可使被查看的牌 +1 分（本局有效）", "+1", "success", "score_up")

static func _def(id: String, name: String, desc: String, glyph: String, color_key: String, category: String) -> Dictionary:
	return {"id": id, "name": name, "desc": desc, "price": RELIC_PRICE,
		"glyph": glyph, "color": color_key, "category": category}
