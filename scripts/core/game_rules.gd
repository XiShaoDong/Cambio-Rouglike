class_name KongRules
extends RefCounted

## Central, data-only rules. Keep this independent from UI and ENet so the same
## match authority can run in a LAN host or a future headless VPS process.

const MAX_PLAYERS := 4
const MIN_PLAYERS := 2
const HAND_SIZE := 4
## 手牌数上限：玩家总牌数超过该值（> MAX_HAND_CARDS）时对局立即结算，该玩家判定失败。
const MAX_HAND_CARDS := 6

## 贴牌比拼：首个正确贴牌后的收集窗口（毫秒），期间其他正确贴牌加入比拼。
const SLAP_DUEL_COLLECT_MS := 400
## 比拼 bar 扫动总时长（毫秒）：标记 0→1→0 一趟来回。
const SLAP_DUEL_DURATION_MS := 2000
## 比拼结束宽限（毫秒）：等最后一名候选人按 STOP。
const SLAP_DUEL_GRACE_MS := 2000
## 加粗区目标位置范围（bar 归一化坐标，避开贴边）。
const SLAP_DUEL_TARGET_MIN := 0.15
const SLAP_DUEL_TARGET_MAX := 0.85

const SPECIAL_RANKS := ["7", "8", "9", "10", "J", "Q"]

const START_CURRENCY := 100
const START_HEALTH := 2
## 名次奖励（R-12）：第一 / 中间 / 垫底。
const RANK_REWARD_FIRST := 40
const RANK_REWARD_MIDDLE := 10
const MIN_BET := 20
const MAX_BET := 100
const BET_STEP := 5
const SAFE_RETURN := 1.5   # 非最后玩家返还倍数
const WINNER_RETURN := 2.0 # 第一名返还倍数
const DEFAULT_MATCH_LIMIT := 5
const MIN_MATCH_LIMIT := 2
const MAX_MATCH_LIMIT := 10

## 局间自动衔接：结算展示多久后服务器自动开下一局（毫秒）。商店里程碑将替换为等全员。
const SERIES_AUTO_ADVANCE_MS := 10000

static func card_value(rank: String) -> int:
	match rank:
		"A": return 1
		"J", "Q": return 10
		"K": return -1
		"JOKER": return 0
		_: return int(rank)

static func has_ability(rank: String) -> bool:
	return rank in SPECIAL_RANKS

static func display_name(card: Dictionary) -> String:
	if card.rank == "JOKER":
		return "大王" if card.suit == "red" else "小王"
	return "%s%s" % [card.rank, card.suit]

static func new_default_run() -> Dictionary:
	# The MVP leaves modifiers disabled. Future relics/mutators belong in this
	# serializable run state, rather than in match-flow conditionals.
	return {
		"health": START_HEALTH,
		"relic_slots": 2,
		"relics": {},
		"relic_owners": {},
		"mutator_ids": [],
		"enable_relics": false,
		"match_limit": DEFAULT_MATCH_LIMIT,
	}
