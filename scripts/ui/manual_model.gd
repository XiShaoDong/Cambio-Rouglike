class_name ManualModel
extends RefCounted
## 手册数据（纯函数，headless 可测）：牌面按数值排序 → 能力 → 分数。
## 分数取 `KongRules.card_value`（A=1、2-10 面值、J/Q=10、K=-1、Joker=0）；
## 能力取 `KongRules.SPECIAL_RANKS` 对应的效果（7/8 看自己、9/10 看别人、J 盲换、Q 看后决定换）。

## 展示顺序：A,2,…,10,J,Q,K,Joker。
const RANK_ORDER := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "JOKER"]
const NO_POWER := "—"

static func rows() -> Array:
	var out: Array = []
	for rank in RANK_ORDER:
		out.append({
			"rank": display_rank(rank),
			"power": power_text(rank),
			"score": KongRules.card_value(rank),
		})
	return out

static func display_rank(rank: String) -> String:
	return "Joker" if rank == "JOKER" else rank

static func power_text(rank: String) -> String:
	match rank:
		"7", "8":
			return "看自己一张牌"
		"9", "10":
			return "看别人一张牌"
		"J":
			return "盲换：与自己一张牌交换"
		"Q":
			return "看别人一张，再看自己一张，决定是否交换"
	return NO_POWER
