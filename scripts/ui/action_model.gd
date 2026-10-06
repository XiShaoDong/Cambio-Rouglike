class_name ActionModel
extends RefCounted
## 纯函数：由快照推导「条件动作按钮」与关键可用性；2D 控制区与 3D HUD/铃铛共用。
## 不依赖任何节点；阶段数值与 GameState.Phase 对齐。

const Q_KEEP := "q_keep"
const Q_EXCHANGE := "q_exchange"
const J_KEEP := "j_keep"
const J_EXCHANGE := "j_exchange"
const JOKER := "joker"

const PHASE_TURN_DRAW := 2
const PHASE_TURN_DECISION := 3
const PHASE_Q_DECISION := 4

## J 交换交互模式（本地 action_mode）：jack_target 选对方牌 → jack_own 选自己牌 → jack_ready 待确认。
const JACK_MODES := ["jack_target", "jack_own", "jack_ready"]

## 条件动作按钮：需要时出现，点了触发 request_*。
## - Q_DECISION 且当前玩家且已看自己牌 → 「Q：不交换」「Q：交换」
## - TURN_DECISION 且当前玩家且正在 J 交换（ctx.action_mode 为 jack_*）→ 「J：不交换」「J：交换」
##   （「J：交换」仅当两张牌都已选，`ctx` 由本地 interaction 提供）
## - TURN_DECISION 且当前玩家且 pending 为 JOKER 且持有 Joker 遗物 → 「变换 Joker」
static func conditional_actions(state: Dictionary, ctx: Dictionary = {}) -> Array:
	var out: Array = []
	if state.is_empty():
		return out
	var phase := int(state.get("phase", 0))
	var viewer := int(state.get("viewer_id", 0))
	if viewer != int(state.get("current_player", -1)):
		return out
	if phase == PHASE_Q_DECISION:
		var qd: Dictionary = state.get("q_decision", {})
		if bool(qd.get("own_viewed", false)):
			out.append({"action": Q_KEEP, "text": "Q：不交换", "enabled": true})
			out.append({"action": Q_EXCHANGE, "text": "Q：交换", "enabled": true})
	elif phase == PHASE_TURN_DECISION:
		var pending: Dictionary = state.get("pending", {})
		if str(pending.get("rank", "")) == "JOKER":
			var run: Dictionary = state.get("run", {})
			if (run.get("relics", {}) as Dictionary).has(Relics.JOKER_TRANSFORM_ID):
				out.append({"action": JOKER, "text": "变换 Joker", "enabled": true})
		# J 交换：两张都已选才能「交换」（与 Q 的确认按钮一致，仅多了"选两张牌"步骤）
		if JACK_MODES.has(str(ctx.get("action_mode", ""))):
			var both_selected := int(ctx.get("selected_their_slot", -1)) >= 0 \
				and int(ctx.get("selected_own_slot", -1)) >= 0
			out.append({"action": J_KEEP, "text": "J：不交换", "enabled": true})
			out.append({"action": J_EXCHANGE, "text": "J：交换", "enabled": both_selected})
	return out

## 抽牌堆可抽：TURN_DRAW 且 viewer 为当前玩家（2D 抽牌堆高亮 / 3D 抽牌堆光晕同源）。
static func draw_available(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	return int(state.get("phase", 0)) == PHASE_TURN_DRAW \
		and int(state.get("viewer_id", 0)) == int(state.get("current_player", -1))

## 铃铛（Kongbaya）可用：与抽牌同条件（TURN_DRAW 且 viewer 为当前玩家）。
static func kongbaya_available(state: Dictionary) -> bool:
	return draw_available(state)

## 弃牌堆可直接点「取弃牌顶」：TURN_DRAW 且当前玩家且弃牌堆非空。
static func discard_take_available(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	if int(state.get("phase", 0)) != PHASE_TURN_DRAW:
		return false
	if int(state.get("viewer_id", 0)) != int(state.get("current_player", -1)):
		return false
	return not (state.get("discard", {}) as Dictionary).is_empty()

## 弃牌堆可直接点「弃掉抽到的牌 / 用能力」：TURN_DECISION 且当前玩家且 pending 非空且非取自弃牌堆。
static func pending_discard_available(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	if int(state.get("phase", 0)) != PHASE_TURN_DECISION:
		return false
	if int(state.get("viewer_id", 0)) != int(state.get("current_player", -1)):
		return false
	var pending: Dictionary = state.get("pending", {})
	if pending.is_empty():
		return false
	return str(pending.get("source", "draw")) != "discard"

## 弃牌堆在当前快照下是否可点（取弃牌顶 或 弃掉大牌 / 用能力）。
static func discard_pile_actionable(state: Dictionary) -> bool:
	return discard_take_available(state) or pending_discard_available(state)

## Ready 按钮文案（2D 固定按钮与 3D HUD 共用）。
static func ready_text(state: Dictionary, ready_clicked: bool) -> String:
	var ready_count := int(state.get("ready_count", 0))
	var total: int = (state.get("players", []) as Array).size()
	if ready_clicked:
		return "已准备（%d/%d）" % [ready_count, total]
	return "Ready（%d/%d）" % [ready_count, total]

## Ready 按钮可用性。
static func ready_enabled(state: Dictionary, ready_clicked: bool) -> bool:
	var ready_count := int(state.get("ready_count", 0))
	var total: int = (state.get("players", []) as Array).size()
	return not ready_clicked and ready_count < total
