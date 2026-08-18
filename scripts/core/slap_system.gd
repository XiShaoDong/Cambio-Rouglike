class_name SlapSystem
extends RefCounted
## 贴牌系统（Feature 10）
## 职责：管理贴牌窗口的开启/关闭/尝试/交换/超时。
## 持有 GameState 引用，操作其状态与副作用方法。前置校验在尝试/交换时一并处理。

var game: Node

func _init(state: Node) -> void:
	game = state

## 开启贴牌窗口。resume 为 "advance"（推进回合）或其他（回抽牌阶段）。
func open_slap(resume: String) -> void:
	game.slap_resume = resume
	game.slap_attempted.clear()
	game.slap_exchange.clear()
	game.phase = game.Phase.SLAP_WINDOW
	game.slap_timer.start(KongRules.SLAP_WINDOW_SECONDS)
	game._broadcast_state()

## 玩家尝试贴牌。
func attempt(sender: int, target_player: int, slot: int, action_id := "") -> void:
	if game.phase != game.Phase.SLAP_WINDOW:
		game._reject(sender, game.RejectCode.INVALID_PHASE, action_id)
		return
	if not game.players.has(sender):
		return
	if game.slap_attempted.has(sender):
		game._reject(sender, game.RejectCode.ALREADY_ATTEMPTED_SLAP, action_id)
		return
	if not game._check_action_id(sender, action_id):
		game._reject(sender, game.RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	if not game._valid_slot(target_player, slot):
		game._reject(sender, game.RejectCode.INVALID_TARGET, action_id)
		return
	game.slap_attempted[sender] = true
	var target_card: String = game.players[target_player].cards[slot]
	# 贴牌尝试：无论对错，把被贴的牌翻给所有玩家看
	var card_public: Dictionary = game.peek.public_card(target_card)
	var target_name: String = game.players[target_player].name
	for pid in game.players:
		game._send_reveal(int(pid), "贴牌：翻出 %s 的牌" % target_name, [card_public], {"player_id": target_player, "slot": slot})
	if game.cards[target_card].rank != game.slap_rank:
		add_penalty(sender)
		game._add_log("%s 贴错了，罚抽一张牌。" % game.players[sender].name)
		game._broadcast_state()
		return
	if target_player == sender:
		game.players[sender].cards.remove_at(slot)
		game.discard_pile.append(target_card)
		game._add_log("%s 成功贴出自己的 %s。" % [game.players[sender].name, game.slap_rank])
		finish_slap()
		return
	game.slap_timer.stop()
	game.phase = game.Phase.SLAP_EXCHANGE
	game.slap_exchange = {"actor": sender, "target": target_player, "target_slot": slot, "target_card": target_card}
	game._add_log("%s 贴中了 %s 的牌，等待交出一张自己的牌。" % [game.players[sender].name, game.players[target_player].name])
	game._broadcast_state()

## 贴中他人后，行动者交出一张自己的牌。
func exchange(sender: int, own_slot: int, action_id := "") -> void:
	if game.phase != game.Phase.SLAP_EXCHANGE:
		game._reject(sender, game.RejectCode.INVALID_PHASE, action_id)
		return
	if sender != int(game.slap_exchange.get("actor", 0)):
		game._reject(sender, game.RejectCode.NOT_CURRENT_PLAYER, action_id)
		return
	if not game._check_action_id(sender, action_id):
		game._reject(sender, game.RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	if not game._valid_slot(sender, own_slot):
		game._reject(sender, game.RejectCode.INVALID_SLOT, action_id)
		return
	var target := int(game.slap_exchange.target)
	var target_slot := int(game.slap_exchange.target_slot)
	if not game._valid_slot(target, target_slot):
		return
	var gift: String = game.players[sender].cards[own_slot]
	var pasted: String = game.players[target].cards[target_slot]
	game.players[sender].cards.remove_at(own_slot)
	game.players[target].cards[target_slot] = gift
	game.discard_pile.append(pasted)
	game._add_log("%s 成功贴牌并将一张牌交给 %s。" % [game.players[sender].name, game.players[target].name])
	finish_slap()

## 贴牌窗口超时。
func on_timeout() -> void:
	if game.multiplayer.is_server() and game.phase == game.Phase.SLAP_WINDOW:
		game._add_log("贴牌时间结束。")
		finish_slap()

## 关闭贴牌窗口并推进。
func finish_slap() -> void:
	game.slap_timer.stop()
	game.slap_rank = ""
	game.slap_attempted.clear()
	game.slap_exchange.clear()
	if game.slap_resume == "advance":
		game._advance_turn()
	else:
		game.phase = game.Phase.TURN_DRAW
		game._broadcast_state()

## 给玩家加一张罚抽牌。
func add_penalty(peer_id: int) -> void:
	var penalty: String = game._draw_from_deck()
	if not penalty.is_empty():
		game.players[peer_id].cards.append(penalty)