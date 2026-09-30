class_name ActionModel
extends RefCounted
## 纯函数：由快照推导「条件动作按钮」与关键可用性；2D 控制区与 3D HUD/铃铛共用。
## 不依赖任何节点；阶段数值与 GameState.Phase 对齐。

const Q_KEEP := "q_keep"
const Q_EXCHANGE := "q_exchange"
const JOKER := "joker"

const PHASE_TURN_DRAW := 2
const PHASE_TURN_DECISION := 3
const PHASE_Q_DECISION := 4

## 条件动作按钮：需要时出现，点了触发 request_*。
## - Q_DECISION 且当前玩家且已看自己牌 → 「Q：不交换」「Q：交换」
## - TURN_DECISION 且当前玩家且 pending 为 JOKER 且持有 Joker 遗物 → 「变换 Joker」
static func conditional_actions(state: Dictionary) -> Array:
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
	return out

## 铃铛（Kongbaya）可用：TURN_DRAW 且 viewer 为当前玩家。
static func kongbaya_available(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	return int(state.get("phase", 0)) == PHASE_TURN_DRAW \
		and int(state.get("viewer_id", 0)) == int(state.get("current_player", -1))

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
