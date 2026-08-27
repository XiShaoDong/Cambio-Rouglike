class_name GameInteraction
extends RefCounted
## 玩家交互状态机（main.gd 拆分 · 第一优先级）
## 职责：管理玩家在点击卡牌时的交互状态（action_mode/selected）与转移。
## 不负责：UI 构建、GameState 投影、动画——只决定"玩家点击后下一步该做什么"。
## 持有 main（组合根）引用，读 latest_state，调用 GameState 的 request_* 与 main 的刷新。

const PHASE_TURN_DRAW := 2
const PHASE_SLAP_WINDOW := 5
const PHASE_SLAP_EXCHANGE := 6
const PHASE_SLAP_DUEL := 8

var main: Node
var action_mode := ""
var selected_target := 0
var selected_own_slot := -1
var selected_their_slot := -1

func _init(owner_node: Node) -> void:
	main = owner_node

## 玩家点击卡牌时调用。player_id/slot 为目标卡牌。
func on_card_pressed(player_id: int, slot: int) -> void:
	var state: Dictionary = main.latest_state
	if state.is_empty():
		return
	var phase := int(state.phase)
	var viewer := int(state.viewer_id)
	if phase == PHASE_SLAP_DUEL:
		return
	if bool(state.get("slap_open", false)) and phase == PHASE_TURN_DRAW:
		if main._slap_reveal_lock:
			return
		GameState.request_slap(player_id, slot, main._next_action_id())
		return
	if phase == PHASE_SLAP_EXCHANGE and player_id == viewer and int(state.slap_exchange_actor) == viewer:
		GameState.request_slap_exchange(slot, main._next_action_id())
		return
	if int(state.current_player) != viewer:
		return
	match action_mode:
		"replace":
			if player_id == viewer:
				GameState.request_replace(slot, main._next_action_id())
		"peek_own":
			if player_id == viewer:
				GameState.request_use_ability({"slot": slot}, main._next_action_id())
		"peek_other":
			if player_id != viewer:
				GameState.request_use_ability({"target": player_id, "target_slot": slot}, main._next_action_id())
		"queen_target":
			if player_id != viewer:
				GameState.request_use_ability({"target": player_id, "target_slot": slot}, main._next_action_id())
		"q_exchange":
			if player_id == viewer:
				GameState.request_q_decision(true, slot, main._next_action_id())
		"jack_target":
			if player_id != viewer:
				selected_target = player_id
				selected_their_slot = slot
				action_mode = "jack_own"
				main._render_game()
		"jack_own":
			if player_id == viewer:
				selected_own_slot = slot
				GameState.request_use_ability({"target": selected_target, "own_slot": selected_own_slot, "target_slot": selected_their_slot}, main._next_action_id())
				_reset()

## 根据抽到的能力牌设置交互模式。
func begin_ability() -> void:
	var pending: Dictionary = main.latest_state.get("pending", {})
	match str(pending.get("rank", "")):
		"7", "8": action_mode = "peek_own"
		"9", "10": action_mode = "peek_other"
		"J": action_mode = "jack_target"
		"Q": action_mode = "queen_target"
	main._render_game()

## 该卡牌当前是否可操作（决定高亮）。
func card_actionable(player_id: int, _slot: int) -> bool:
	var state: Dictionary = main.latest_state
	var phase := int(state.phase)
	var viewer := int(state.viewer_id)
	var is_current := viewer == int(state.current_player)
	if phase == PHASE_SLAP_DUEL:
		return false
	if bool(state.get("slap_open", false)) and phase == PHASE_TURN_DRAW:
		return false
	if phase == PHASE_SLAP_EXCHANGE:
		return player_id == viewer and int(state.slap_exchange_actor) == viewer
	if not is_current:
		return false
	match action_mode:
		"replace", "peek_own", "q_exchange":
			return player_id == viewer
		"peek_other", "queen_target":
			return player_id != viewer
		"jack_target":
			return player_id != viewer
		"jack_own":
			return player_id == viewer
	return false

## 发送 J 交换请求后清空交互选择状态。
func _reset() -> void:
	action_mode = ""
	selected_target = 0
	selected_own_slot = -1
	selected_their_slot = -1

## 模式相关提示语。
func mode_instruction(fallback: String) -> String:
	match action_mode:
		"replace": return "请选择自己要被替换的手牌。"
		"peek_own": return "7 / 8：请选择自己要查看的手牌。"
		"peek_other": return "9 / 10：请选择其他玩家的一张牌。"
		"queen_target": return "Q：请选择其他玩家的一张牌查看。"
		"q_exchange": return "Q：请选择自己交出去的牌。"
		"jack_target": return "J：点击要换的对方牌。"
		"jack_own": return "J：再点击自己要换的牌。"
	return fallback

## 阶段变化时重置交互状态。
func reset_for_phase(state: Dictionary) -> void:
	if int(state.phase) == main.last_phase:
		return
	action_mode = ""
	selected_target = 0
	selected_own_slot = -1
	selected_their_slot = -1
	if int(state.phase) == 3 and int(state.viewer_id) == int(state.current_player):  # TURN_DECISION
		action_mode = "replace"
