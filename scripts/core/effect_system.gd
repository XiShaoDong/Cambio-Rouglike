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
		"7", "8", "9", "10":
			_peek(sender, rank, data, action_id, false)
		"J":
			_blind_swap(sender, data, action_id)
		"Q":
			_start_queen(sender, data, action_id)

## 奇数/偶数视野饰品授予的一次性查看（不触发 7/8、9/10 的加减分饰品）。
func resolve_granted_peek(sender: int, granted: String, data: Dictionary, action_id := "") -> void:
	var rank := "7" if granted == "peek_own" else "9"
	_peek(sender, rank, data, action_id, true)

## 7/8（看自己）与 9/10（看别人）；持有「视野互换」时可跨目标。
## granted=true 表示来自奇数/偶数视野，不消耗/触发窥视削弱/加成。
func _peek(sender: int, rank: String, data: Dictionary, action_id: String, granted: bool) -> void:
	var target := sender
	var slot := int(data.get("slot", -1))
	if data.has("target") or data.has("target_slot"):
		target = int(data.get("target", sender))
		slot = int(data.get("target_slot", slot))
	var target_is_self := target == sender
	var own_default := rank == "7" or rank == "8"
	var flex: bool = game._is_relic_owner(sender, Relics.PEEK_FLEX_ID)
	if target_is_self and not own_default and not flex:
		game._reject(sender, game.RejectCode.INVALID_TARGET, action_id)
		return
	if not target_is_self and own_default and not flex:
		game._reject(sender, game.RejectCode.INVALID_TARGET, action_id)
		return
	if not game._valid_slot(target, slot):
		game._reject(sender, game.RejectCode.INVALID_TARGET, action_id)
		return
	if not game.players.has(target):
		game._reject(sender, game.RejectCode.INVALID_TARGET, action_id)
		return
	var card_id := str(game.players[target].cards[slot])
	if card_id.is_empty():
		game._reject(sender, game.RejectCode.INVALID_SLOT, action_id)
		return
	# 7/8 窥视削弱 / 9/10 窥视加成：自动应用、每名持有者每局一次。
	if not granted:
		if own_default and game._use_relic_once(sender, Relics.PEEK_REDUCE_ID):
			game.cards[card_id]["value"] = int(game.cards[card_id]["value"]) - 1
		elif (rank == "9" or rank == "10") and game._use_relic_once(sender, Relics.PEEK_BONUS_ID):
			game.cards[card_id]["value"] = int(game.cards[card_id]["value"]) + 1
	var title := "查看自己的牌" if target_is_self else "查看别人的牌"
	game._send_reveal(sender, title, [game.peek.public_card(card_id)], {"player_id": target, "slot": slot})
	game._broadcast_peek_highlight(sender, {"player_id": target, "slot": slot})
	if target_is_self:
		game._add_log("%s 查看了自己的一张牌。" % game.players[sender].name)
	else:
		game._add_log("%s 查看了 %s 的一张牌。" % [game.players[sender].name, game.players[target].name])
	game._discard_pending_and_open_slap("advance")

func _blind_swap(sender: int, data: Dictionary, action_id := "") -> void:
	var swap_target := int(data.get("target", 0))
	var own_swap_slot := int(data.get("own_slot", -1))
	var their_swap_slot := int(data.get("target_slot", -1))
	if swap_target == sender or not game._valid_slot(sender, own_swap_slot) or not game._valid_slot(swap_target, their_swap_slot):
		game._reject(sender, game.RejectCode.INVALID_TARGET, action_id)
		return
	if game._is_protected(swap_target, their_swap_slot):
		game._reject(sender, game.RejectCode.PROTECTED, action_id)
		return
	var gifted_id := str(game.players[sender].cards[own_swap_slot])
	if gifted_id.is_empty():
		game._reject(sender, game.RejectCode.INVALID_SLOT, action_id)
		return
	game.swap.swap(sender, own_swap_slot, swap_target, their_swap_slot, "%s 与 %s 盲换了一张牌。" % [game.players[sender].name, game.players[swap_target].name])
	# J 交换加成：交给对方的牌 +2（每名持有者每局一次）；先加值再广播牌面。
	if not gifted_id.is_empty() and game._use_relic_once(sender, Relics.JACK_BONUS_ID):
		game.cards[gifted_id]["value"] = int(game.cards[gifted_id]["value"]) + 2
	# a 槽原牌 = 现在 target 槽的牌；b 槽原牌 = 现在 sender 槽的牌
	var a_data: Dictionary = game.peek.public_card(str(game.players[swap_target].cards[their_swap_slot]))
	var b_data: Dictionary = game.peek.public_card(str(game.players[sender].cards[own_swap_slot]))
	game._broadcast_exchange({"kind": "swap", "a": sender, "a_slot": own_swap_slot, "b": swap_target, "b_slot": their_swap_slot, "a_data": a_data, "b_data": b_data})
	game._discard_pending_and_open_slap("advance")

func _start_queen(sender: int, data: Dictionary, action_id := "") -> void:
	var q_target := int(data.get("target", 0))
	var q_slot := int(data.get("target_slot", -1))
	if q_target == sender or not game._valid_slot(q_target, q_slot):
		game._reject(sender, game.RejectCode.INVALID_TARGET, action_id)
		return
	if game._is_protected(q_target, q_slot):
		game._reject(sender, game.RejectCode.PROTECTED, action_id)
		return
	game.q_context = {"actor": sender, "target": q_target, "target_slot": q_slot, "own_viewed": false}
	game.phase = game.Phase.Q_DECISION
	game._send_reveal(sender, "Q：查看后决定是否交换", [game.peek.public_card(str(game.players[q_target].cards[q_slot]))], {"player_id": q_target, "slot": q_slot})
	game._broadcast_peek_highlight(sender, {"player_id": q_target, "slot": q_slot, "hold": true})
	game._add_log("%s 正在决定是否交换。" % game.players[sender].name)
	game._broadcast_state()
