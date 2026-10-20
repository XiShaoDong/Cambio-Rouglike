class_name TurnEffect
extends RefCounted
## 每回合随机增强的**展示数据**（UI-only；玩法见 docs/KONG_开发文档.md「随机增强」章节）。
##
## [随机增强接入点 · 后续对接]
## - effect id 由服务器 `GameState._roll_turn_effect()` 抽取，写入快照 `turn_effect`（全员一致）。
## - 真实效果应在**服务器**换回合处按 id 应用（见 `game_state.gd` 的 `_roll_turn_effect` 标注），
##   客户端只读 id 展示文案/卡图；**不要在客户端/本文件实现规则**。
## - 新增效果时：先加 id → `KongGameState.TURN_EFFECT_IDS`，再在这里补 name/desc/card/bomb 展示数据。

const EFFECTS := [
	{
		"id": "none",
		"name": "无效果",
		"desc": "本回合没有特殊效果",
		"card": "res://assets/SmallCards/back01.png",
		"bomb": false,
	},
	{
		"id": "six_swap",
		"name": "6",
		"desc": "打出任意花色的 6 时，顺时针传递一张牌（从打出者开始）；抽到红 Joker 可选择使用能力触发",
		"card": "res://assets/SmallCards/spades_06.png",
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
