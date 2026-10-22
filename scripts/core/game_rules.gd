class_name KongRules
extends RefCounted

## Central, data-only rules. Keep this independent from UI and ENet so the same
## match authority can run in a LAN host or a future headless VPS process.

const MAX_PLAYERS := 4
const MIN_PLAYERS := 2
const HAND_SIZE := 4
## 初始牌堆总张数：4 花色 × 13 点数 + 2 Joker = 54（用于抽牌堆 "剩余/总数" 展示）。
const DECK_SIZE := 54
## 玩家机器人配色（进入游戏时随机分配、保证不重复；末位为原默认色）。
const PLAYER_COLORS := ["#3ABA64", "#BD414B", "#A36DE9", "#7158FE", "#A0D45D", "#B18C3E", "#63CBEA", "#496AFE"]

## 从调色板随机取一个未被占用的颜色（existing 为已占用颜色字符串列表）；
## 调色板取尽时退回随机（当前 8 色 ≥ MAX_PLAYERS，正常不会发生）。
static func pick_color(existing: Array) -> String:
	var used := {}
	for c in existing:
		used[str(c)] = true
	var free: Array = []
	for c in PLAYER_COLORS:
		if not used.has(c):
			free.append(c)
	if free.is_empty():
		return PLAYER_COLORS[randi() % PLAYER_COLORS.size()]
	return str(free[randi() % free.size()])
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

## 每局开局随机增强展示阶段（秒）：全员 Ready 后先展示本局效果，期间不可操作。
const EFFECT_REVEAL_SECONDS := 5.0

## 最终轮（Kongbaya）末位玩家行动后的**结算贴牌窗口**（秒）：期间仅可贴牌，到时开始结算。
## 目的：末位行动后不立即结算，给其他玩家贴牌机会，并让末位动作的在途动画（peek 翻回 / J·Q 换位）放完。
const SLAP_SETTLE_SECONDS := 2.0
## 结算前收尾宽限（秒）：贴牌判定 / 罚牌 / 赠牌等发生在窗口内的动画放完后再结算。
const SLAP_SETTLE_GRACE_SECONDS := 1.2
## 手牌超限（R-07）：罚牌先飞到玩家手里，之后才开贴牌结算窗口（秒）。
const SETTLE_OVERFLOW_PENALTY_DELAY := 0.9

const SPECIAL_RANKS := ["7", "8", "9", "10", "J", "Q"]
## 随机增强「左下角 +1」的点数循环：A→2→…→Q→A（K / Joker 不参与）。
const RANK_CYCLE := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q"]

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

## 随机增强「左下角 +1」：返回循环中的下一档；K/Joker 等不在循环内返回空串（不改变）。
static func next_rank_in_cycle(rank: String) -> String:
	var i := RANK_CYCLE.find(rank)
	if i < 0:
		return ""
	return str(RANK_CYCLE[(i + 1) % RANK_CYCLE.size()])

static func has_ability(rank: String) -> bool:
	return rank in SPECIAL_RANKS

## 奇数/偶数点数（Joker 不参与；用于「奇数/偶数视野」饰品）。
static func is_odd_rank(rank: String) -> bool:
	return rank in ["A", "3", "5", "7", "9", "J", "K"]

static func is_even_rank(rank: String) -> bool:
	return rank in ["2", "4", "6", "8", "10", "Q"]

static func display_name(card: Dictionary) -> String:
	if card.rank == "JOKER":
		return "大王" if card.suit == "red" else "小王"
	return "%s%s" % [card.rank, card.suit]

static func new_default_run() -> Dictionary:
	# The MVP leaves modifiers disabled. Future relics/mutators belong in this
	# serializable run state, rather than in match-flow conditionals.
		return {
		"health": START_HEALTH,
		"relic_slots": 3,
		"relics": {},
		"relic_inventories": {},
		"shop_locks": {},
		"item_slots": ItemCards.SLOT_LIMIT,
		"item_inventories": {},
		"item_locks": {},
		"mutator_ids": [],
		"enable_relics": false,
		"match_limit": DEFAULT_MATCH_LIMIT,
		# 玩法设置（系列赛级，房主在 LOBBY 修改）：效果模式 / 固定特效 / 商店开关。
		"effect_mode": "normal",   # normal=无特效 / random=每局随机 / fixed=整系列固定特效
		"fixed_effect": "",        # fixed 模式下的特效 id（six_swap/plus_one/bomb）
		"shop_enabled": true,      # 关闭后系列赛非把末结算直接开下一局
		# 对局详情（系列赛级，房主在 LOBBY「对局详情」弹窗修改）：
		"start_health": START_HEALTH,   # 玩家初始生命（新一届系列赛开局生效）
		"start_currency": START_CURRENCY,  # 玩家初始金钱
		"shop_price": Relics.RELIC_PRICE,      # 商店物品基础价（遗物/道具卡同价，价格系一并生效）
	}
