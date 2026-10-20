class_name TurnEffect
extends RefCounted
## 每回合随机增强的展示数据（UI-only；玩法见 docs/KONG_开发文档.md「随机增强」章节）。

const EFFECTS := [
	{
		"id": "none",
		"name": "无效果",
		"desc": "本回合没有特殊效果",
		"card": "res://assets/SmallCards/back01.png",
		"bomb": false,
	},
	{
		"id": "joker_red",
		"name": "红 Joker",
		"desc": "顺时针交换一张卡牌（从发起者开始）",
		"card": "res://assets/SmallCards/Joker1.png",
		"bomb": false,
	},
	{
		"id": "joker_black",
		"name": "黑 Joker",
		"desc": "逆时针交换一张卡牌（从发起者开始）",
		"card": "res://assets/SmallCards/Joker2.png",
		"bomb": false,
	},
	{
		"id": "plus_one",
		"name": "左下角 +1",
		"desc": "左下角的卡牌每回合点数 +1（A→Q 循环，Q 之后回到 A）",
		"card": "res://assets/SmallCards/spades_ace.png",
		"bomb": false,
	},
	{
		"id": "bomb",
		"name": "炸弹",
		"desc": "随机 4 张牌带炸弹标记；在手牌保留 3 回合后消失",
		"card": "res://assets/SmallCards/spades_02.png",
		"bomb": true,
	},
]

static func all() -> Array:
	return EFFECTS

static func random(rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		return EFFECTS[randi() % EFFECTS.size()]
	return EFFECTS[rng.randi() % EFFECTS.size()]

static func by_id(id: String) -> Dictionary:
	for e in EFFECTS:
		if str(e["id"]) == id:
			return e
	return {}
