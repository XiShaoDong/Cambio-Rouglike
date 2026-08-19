class_name EffectSystem
extends RefCounted
## 卡牌能力系统（Feature 07）
## 职责：解析并执行抽到的牌的能力（7/8 看自己、9/10 看别人、J 盲换、Q 看后换）。
## 前置校验（阶段/行动者/来源/幂等）由 GameState 完成；本类只做能力效果。
## 持有 GameState 引用，操作其公开状态与副作用方法。

var game: Node

func _init(state: Node) -> void:
	game = state

## 执行能力。sender 为行动者，rank 为能力牌点数，data 为操作参数。
func resolve_ability(sender: int, rank: String, data: Dictionary, action_id := "") -> void:
	match rank:
		"7", "8":
			_peek_own(sender, data, action_id)
		"9", "10":
			_peek_other(sender, data, action_id)
		"J":
			_blind_swap(sender, data, action_id)
		"Q":
			_start_queen(sender, data, action_id)

func _peek_own(sender: int, data: Dictionary, action_id := "") -> void:
	var own_slot := int(data.get("slot", -1))
	if not game._valid_slot(sender, own_slot):
		game._reject(sender, game.RejectCode.INVALID_SLOT, action_id)
		return
	game._send_reveal(sender, "查看自己的牌", [game.peek.public_card(game.players[sender].cards[own_slot])], {"player_id": sender, "slot": own_slot})
	game._add_log("%s 查看了自己的一张牌。" % game.players[sender].name)
	game._discard_pending_and_open_slap("advance")

func _peek_other(sender: int, data: Dictionary, action_id := "") -> void:
	var target := int(data.get("target", 0))
	var target_slot := int(data.get("target_slot", -1))
	if target == sender or not game._valid_slot(target, target_slot):
		game._reject(sender, game.RejectCode.INVALID_TARGET, action_id)
		return
	game._send_reveal(sender, "查看别人的牌", [game.peek.public_card(game.players[target].cards[target_slot])], {"player_id": target, "slot": target_slot})
	game._add_log("%s 查看了 %s 的一张牌。" % [game.players[sender].name, game.players[target].name])
	game._discard_pending_and_open_slap("advance")

func _blind_swap(sender: int, data: Dictionary, action_id := "") -> void:
	var swap_target := int(data.get("target", 0))
	var own_swap_slot := int(data.get("own_slot", -1))
	var their_swap_slot := int(data.get("target_slot", -1))
	if swap_target == sender or not game._valid_slot(sender, own_swap_slot) or not game._valid_slot(swap_target, their_swap_slot):
		game._reject(sender, game.RejectCode.INVALID_TARGET, action_id)
		return
	game.swap.swap(sender, own_swap_slot, swap_target, their_swap_slot, "%s 与 %s 盲换了一张牌。" % [game.players[sender].name, game.players[swap_target].name])
	game._broadcast_exchange({"kind": "swap", "a": sender, "a_slot": own_swap_slot, "b": swap_target, "b_slot": their_swap_slot})
	game._discard_pending_and_open_slap("advance")

func _start_queen(sender: int, data: Dictionary, action_id := "") -> void:
	var q_target := int(data.get("target", 0))
	var q_slot := int(data.get("target_slot", -1))
	if q_target == sender or not game._valid_slot(q_target, q_slot):
		game._reject(sender, game.RejectCode.INVALID_TARGET, action_id)
		return
	game.q_context = {"actor": sender, "target": q_target, "target_slot": q_slot}
	game.phase = game.Phase.Q_DECISION
	game._send_reveal(sender, "Q：查看后决定是否交换", [game.peek.public_card(game.players[q_target].cards[q_slot])], {"player_id": q_target, "slot": q_slot})
	game._add_log("%s 正在决定是否交换。" % game.players[sender].name)
	game._broadcast_state()
