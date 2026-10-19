class_name CardAbilityText
extends RefCounted
## 抽到的大牌（pending）能力解释文案（纯函数，headless 可测）。
## 只有"从抽牌堆抽出"的牌可发动能力；从弃牌堆取到的 7–Q 只能替换，故返回空。

static func ability(rank: String, source: String) -> String:
	if source == "discard":
		return ""
	match rank:
		"7", "8":
			return "看自己一张牌"
		"9", "10":
			return "看别人一张牌"
		"J":
			return "盲换：与自己一张牌交换"
		"Q":
			return "看别人一张牌，再看自己一张，决定是否交换"
	return ""

## 聊天气泡正文：有解释时前缀点数，如「9：看别人一张牌」；无解释返回空串。
static func bubble_text(rank: String, source: String) -> String:
	var t := ability(rank, source)
	if t.is_empty():
		return ""
	return "%s：%s" % [rank, t]
