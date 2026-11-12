class_name HoverState
extends RefCounted
## 3D hover 状态的纯函数模型：只从快照 + 交互模式 + 当前拾取对象推导展示状态。
## 不读写规则、不修改状态；颜色/样式由 UIStyle 消费。

const NEUTRAL := "neutral"
const SLAP := "slap"
const ACTION := "action"
const VALID := "valid"
const INVALID := "invalid"
const WARNING := "warning"

const PHASE_TURN_DRAW := 2

static func _result(state: String, title: String, body: String, note := "") -> Dictionary:
	return {"state": state, "title": title, "body": body, "note": note}

static func _protected(state: Dictionary, seat: int, slot: int) -> bool:
	for p in state.get("players", []):
		if int(p.get("id", -1)) != seat:
			continue
		var slots: Array = p.get("slots", [])
		if slot >= 0 and slot < slots.size():
			return bool((slots[slot] as Dictionary).get("protected", false))
	return false

static func _ability_result(valid: bool, title: String, body: String, note: String) -> Dictionary:
	return _result(VALID if valid else INVALID, title, body, note)

static func resolve(state: Dictionary, action_mode: String, pick: Dictionary, _card: Dictionary = {}) -> Dictionary:
	if state.is_empty() or pick.is_empty():
		return {}
	var kind := str(pick.get("kind", ""))
	var phase := int(state.get("phase", 0))
	var viewer := int(state.get("viewer_id", -1))
	var current := int(state.get("current_player", -2))

	if kind == "deck":
		if ActionModel.draw_available(state):
			return _result(ACTION, "抽取一张卡牌", "点击抽牌堆抽一张牌。")
		return {}

	if kind == "discard":
		# 当前玩家抽牌后：弃牌堆是“用能力/弃掉大牌”的动作目标，信息跟随当前大牌。
		if ActionModel.pending_discard_available(state):
			var pending: Dictionary = state.get("pending", {})
			var source := str(pending.get("source", "draw"))
			var rank := str(pending.get("rank", ""))
			if source == "discard":
				return _result(WARNING, "注意", "这张牌来自弃牌堆，无法发动牌面能力。", "仍可弃掉这张牌。")
			if not rank.is_empty():
				var body := CardAbilityText.text(rank, "draw")
				var granted := str(pending.get("granted_ability", ""))
				if not granted.is_empty():
					body += "\n饰品赋予：可查看一张牌"
				var can_use := not granted.is_empty() or KongRules.has_ability(rank)
				return _result(ACTION, "触发能力", body,
					"点击弃牌堆以触发能力" if can_use else "点击弃牌堆弃掉抽到的牌")
		# 抽牌阶段：弃牌顶可拿，但只用于交换，不能触发能力。
		if phase == PHASE_TURN_DRAW and viewer == current \
				and not (state.get("discard", {}) as Dictionary).is_empty():
			return _result(WARNING, "注意",
				"抽取弃牌堆的牌只用于交换，无法使用其能力。",
				"仍可取走此牌用于替换。")
		return {}

	if kind != "slot":
		return {}
	var seat := int(pick.get("seat", -1))
	var slot := int(pick.get("slot", -1))

	# 贴牌窗口：任意未受保护的牌都可尝试贴牌；不预判对错。
	if bool(state.get("slap_open", false)) and phase == PHASE_TURN_DRAW:
		if _protected(state, seat, slot):
			return _result(INVALID, "无法贴牌", "该牌受到护盾保护，无法贴牌。", "请改选未受保护的牌。")
		return _result(SLAP, "贴牌", "点击这张牌尝试贴牌。", "不预判对错，结果由服务器判定。")

	# 7/8、9/10、Q 的查看目标。
	match action_mode:
		"peek_own":
			return _ability_result(seat == viewer, "翻看卡牌" if seat == viewer else "无法查看",
				"7 / 8：只能查看自己的牌。" if seat == viewer else "7 / 8 只能查看自己的牌。",
				"点击查看，牌面仅自己可见。" if seat == viewer else "请改选自己的一张牌。")
		"peek_other":
			return _ability_result(seat != viewer, "翻看卡牌" if seat != viewer else "无法查看",
				"9 / 10：只能查看其他玩家的牌。" if seat != viewer else "9 / 10 只能查看其他玩家的牌。",
				"点击查看，牌面仅自己可见。" if seat != viewer else "请改选其他玩家的一张牌。")
		"peek_any":
			return _result(VALID, "翻看卡牌", "视野互换：可选择自己或其他玩家的一张牌。",
				"点击查看，牌面仅自己可见。")
		"queen_target":
			return _ability_result(seat != viewer, "翻看卡牌" if seat != viewer else "无法查看",
				"Q：先查看其他玩家的一张牌。" if seat != viewer else "Q 第一步只能选择其他玩家的牌。",
				"点击查看，牌面仅自己可见。" if seat != viewer else "请改选其他玩家的一张牌。")
		"q_view_own":
			return _ability_result(seat == viewer, "翻看卡牌" if seat == viewer else "无法查看",
				"Q：再查看自己的一张牌。" if seat == viewer else "Q 第二步只能选择自己的牌。",
				"点击查看，牌面仅自己可见。" if seat == viewer else "请改选自己的一张牌。")
		"replace":
			return _result(ACTION if seat == viewer else INVALID,
				"替换卡牌" if seat == viewer else "无法替换",
				"点击这张手牌，用取到的牌替换它。" if seat == viewer else "只能替换自己的手牌。",
				"被替换的牌会进入弃牌堆。" if seat == viewer else "请改选自己的牌。")
	return {}
