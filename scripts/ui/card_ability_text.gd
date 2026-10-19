class_name CardAbilityText
extends RefCounted
## 卡牌信息气泡内容（纯函数，headless 可测）：
## 第一行 左=牌名 / 右=分数（大字）；之后每行=能力说明；无能力=「无能力」。
## source=="discard"（大牌取自弃牌堆）→ 能力不可发动。

static func info(rank: String, source := "") -> Dictionary:
	var lines: Array = []
	if source == "discard":
		lines = ["从弃牌堆取得：只能替换，不能发动能力"]
	else:
		match rank:
			"7", "8":
				lines = ["看自己一张牌"]
			"9", "10":
				lines = ["看别人一张牌"]
			"J":
				lines = ["盲换：与自己一张牌交换"]
			"Q":
				lines = ["查看两张牌，并选择是否交换", "不能对两个其他玩家生效"]
			_:
				lines = ["无能力"]
	return {
		"rank": display_rank(rank),
		"value": KongRules.card_value(rank),
		"lines": lines,
	}

static func display_rank(rank: String) -> String:
	return "Joker" if rank == "JOKER" else rank
