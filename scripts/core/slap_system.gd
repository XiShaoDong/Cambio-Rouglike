class_name SlapSystem
extends RefCounted
## 贴牌系统（Feature 10）
## 职责：管理贴牌窗口的开启/关闭/尝试/交换/比拼（SLAP_DUEL）。
## 持有 GameState 引用，操作其状态与副作用方法。前置校验在尝试/交换时一并处理。
## 窗口语义：无固定定时器——上一玩家弃牌/用技能后 `slap_open=true` 并推进回合，
## 直到下一玩家 `take`（抽牌）或正确贴牌解决，窗口关闭（见 `game_state._server_take`）。
## 比拼语义：首个正确贴牌开启 400ms 收集窗；期间其他正确贴牌加入；结束后
## ≥2 人进入 SLAP_DUEL，按 bar 目标（随机加粗区中心红点）最近者胜。

var game: Node

## 调试：收集窗加长，避免第一名贴牌被 400ms 定时器抢先解决，便于第二名跟上。
const DEBUG_DUEL_COLLECT_MS := 30000

func _init(state: Node) -> void:
	game = state

## 开启贴牌窗口：清空本窗口记录，由 game_state 置 slap_open 并推进回合。
func open_slap() -> void:
	game.slap_exchange.clear()
	game.slap_collect.clear()

## 玩家尝试贴牌。合法窗口：slap_open 且当前阶段为 TURN_DRAW（下一玩家尚未抽牌）。
## 同一窗口内玩家可多次尝试（不限次数）；贴错罚牌后仍可继续，贴对进入收集窗。
func attempt(sender: int, target_player: int, slot: int, action_id := "") -> void:
	if not game.slap_open or game.phase != game.Phase.TURN_DRAW:
		game._reject(sender, game.RejectCode.INVALID_PHASE, action_id)
		return
	if not game.players.has(sender):
		return
	if not game._check_action_id(sender, action_id):
		game._reject(sender, game.RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	if not game._valid_slot(target_player, slot):
		game._reject(sender, game.RejectCode.INVALID_TARGET, action_id)
		return
	var target_card: String = game.players[target_player].cards[slot]
	# 贴牌尝试：先判对错（debug 模式不判正确性），把被贴的牌翻给所有玩家看并带对错标记
	var correct: bool = game.debug_duel or game.cards[target_card].rank == game.slap_rank
	var card_public: Dictionary = game.peek.public_card(target_card)
	var target_name: String = game.players[target_player].name
	for pid in game.players:
		game._send_reveal(int(pid), "贴牌：翻出 %s 的牌" % target_name, [card_public], {"player_id": target_player, "slot": slot, "correct": correct})
	if not correct:
		var penalty_slot := add_penalty(sender)
		game._add_log("%s 贴错了，罚抽一张牌。" % game.players[sender].name)
		# 手牌超限（> MAX_HAND_CARDS）：立即结算，该玩家判定失败，不再广播罚牌动画
		if game._check_over_hand(sender):
			return
		if penalty_slot >= 0:
			game._broadcast_exchange({"kind": "slap_penalty", "peer": sender, "slot": penalty_slot})
		game._broadcast_state()
		return
	_add_to_collection(sender, target_player, slot, target_card)

## 正确贴牌进入收集窗（首个开启定时器；同人重复贴牌忽略）。
## 调试模式（debug_duel）：不判正确性，任意贴牌计入；第二名不同玩家贴牌立即进入比拼。
func _add_to_collection(sender: int, target_player: int, slot: int, target_card: String) -> void:
	if game.slap_collect.is_empty():
		game.slap_collect = {"correct": {}}
		var ms := KongRules.SLAP_DUEL_COLLECT_MS if not game.debug_duel else DEBUG_DUEL_COLLECT_MS
		game.slap_collect_timer.start(ms / 1000.0)
	var correct: Dictionary = game.slap_collect.correct
	if not correct.has(sender):
		correct[sender] = {"target": target_player, "target_slot": slot, "target_card": target_card}
		game._add_log("%s 贴中了 %s 的牌，判定中…" % [game.players[sender].name, game.players[target_player].name])
		game._broadcast_state()
	if game.debug_duel and correct.size() >= 2:
		collection_timeout()

## 收集窗结束：1 人正常解决；≥2 人进入比拼。
func collection_timeout() -> void:
	game.slap_collect_timer.stop()
	var correct: Dictionary = game.slap_collect.get("correct", {})
	game.slap_collect.clear()
	if correct.is_empty():
		return
	if correct.size() == 1:
		var peer := int(correct.keys()[0])
		var info: Dictionary = correct[peer]
		_resolve_correct_slap(peer, int(info.target), int(info.target_slot), str(info.target_card))
	else:
		_start_duel(correct)

## 进入比拼：随机目标位置，阶段切到 SLAP_DUEL。
func _start_duel(correct: Dictionary) -> void:
	game.slap_open = false
	game.phase = game.Phase.SLAP_DUEL
	var target := randf_range(KongRules.SLAP_DUEL_TARGET_MIN, KongRules.SLAP_DUEL_TARGET_MAX)
	game.slap_duel = {
		"start_ms": Time.get_ticks_msec(),
		"duration_ms": KongRules.SLAP_DUEL_DURATION_MS,
		"target": target,
		"correct": correct,
		"stops": {},
		"order": [],
	}
	game.slap_duel_timer.start((KongRules.SLAP_DUEL_DURATION_MS + KongRules.SLAP_DUEL_GRACE_MS) / 1000.0)
	game._add_log("多人同时贴中 %s，进入比拼！" % game.slap_rank)
	game._broadcast_state()

## 候选人按 STOP：按服务器到达时间记录。
func duel_stop(sender: int, action_id := "") -> void:
	if game.phase != game.Phase.SLAP_DUEL:
		game._reject(sender, game.RejectCode.INVALID_PHASE, action_id)
		return
	if not game.slap_duel.get("correct", {}).has(sender):
		game._reject(sender, game.RejectCode.NOT_DUEL_CONTESTANT, action_id)
		return
	if game.slap_duel.get("stops", {}).has(sender):
		game._reject(sender, game.RejectCode.ALREADY_STOPPED, action_id)
		return
	if not game._check_action_id(sender, action_id):
		game._reject(sender, game.RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	game.slap_duel.stops[sender] = Time.get_ticks_msec()
	game.slap_duel.order.append(sender)
	if game.slap_duel.stops.size() >= game.slap_duel.correct.size():
		game.slap_duel_timer.stop()
		resolve_duel()
	else:
		game._broadcast_state()

## 比拼超时（有候选人未按 STOP）：按当前到达记录结算。
func duel_timeout() -> void:
	if game.phase == game.Phase.SLAP_DUEL:
		resolve_duel()

## 结算比拼：最接近 bar 目标（红心）者胜；败者无惩罚。
func resolve_duel() -> void:
	game.slap_duel_timer.stop()
	var duel: Dictionary = game.slap_duel
	var target: float = duel.target
	var duration_ms: int = duel.duration_ms
	var start_ms: int = duel.start_ms
	var best := 0
	var best_dist := 999.0
	var details: Array = []
	for peer in duel.correct.keys():
		var p := int(peer)
		var dist := 999.0
		if duel.stops.has(p):
			var elapsed: float = float(int(duel.stops[p]) - start_ms)
			var pos: float = _duel_position(elapsed, duration_ms)
			dist = absf(pos - target)
			details.append("%s 停在 %.2f" % [game.players[p].name, pos])
		else:
			details.append("%s 未停止" % game.players[p].name)
		if dist < best_dist:
			best_dist = dist
			best = p
	# 无人按 STOP：兜底选第一个候选人（不报错），保证比拼总能解决
	if best == 0:
		best = int(duel.correct.keys()[0])
	var info: Dictionary = duel.correct[best]
	game.slap_duel.clear()
	game._add_log("比拼：%s → 目标 %.2f。%s 贴牌成功。" % ["；".join(details), target, game.players[best].name])
	_resolve_correct_slap(best, int(info.target), int(info.target_slot), str(info.target_card))

## 扫动函数：0→1→0 一趟来回（与客户端 bar 一致）。
static func _duel_position(elapsed_ms: float, duration_ms: int) -> float:
	var t := clampf(elapsed_ms / float(duration_ms), 0.0, 1.0)
	if t <= 0.5:
		return 2.0 * t
	return 2.0 - 2.0 * t

## 解决一次正确贴牌（单收集胜者或比拼胜者）：自贴→弃牌；贴他人→SLAP_EXCHANGE。
## 规则微调：贴他人时在进 SLAP_EXCHANGE 之际就把被贴的牌丢进弃牌堆（动画与状态一致），
## 交换阶段只把行动者的牌补进已清空的对方槽位。
func _resolve_correct_slap(sender: int, target_player: int, slot: int, target_card: String) -> void:
	if target_player == sender:
		game.players[sender].cards[slot] = ""
		game.discard_pile.append(target_card)
		game._broadcast_exchange({"kind": "slap_resolved", "target": target_player, "target_slot": slot, "card": game.peek.public_card(target_card)})
		game._add_log("%s 成功贴出自己的 %s。" % [game.players[sender].name, game.slap_rank])
		finish_slap()
		return
	game.slap_open = false
	game.phase = game.Phase.SLAP_EXCHANGE
	game.players[target_player].cards[slot] = ""
	game.discard_pile.append(target_card)
	game._broadcast_exchange({"kind": "slap_resolved", "target": target_player, "target_slot": slot, "card": game.peek.public_card(target_card)})
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
	game.players[sender].cards[own_slot] = ""
	game.players[target].cards[target_slot] = gift
	game._broadcast_exchange({"kind": "slap_gift", "actor": sender, "own_slot": own_slot, "target": target, "target_slot": target_slot})
	game._add_log("%s 成功贴牌并将一张牌交给 %s。" % [game.players[sender].name, game.players[target].name])
	finish_slap()

## 关闭贴牌窗口并恢复当前玩家的抽牌阶段（该玩家尚未抽牌，贴牌不打断其回合）。
func finish_slap() -> void:
	game.slap_open = false
	game.slap_rank = ""
	game.slap_exchange.clear()
	game.slap_collect.clear()
	game.phase = game.Phase.TURN_DRAW
	game._broadcast_state()

## 给玩家加一张罚抽牌（优先填入空槽位，保持固定布局；满则追加为新槽）。
## 返回罚牌落位槽号；无可抽牌时返回 -1。
func add_penalty(peer_id: int) -> int:
	var penalty: String = game._draw_from_deck()
	if penalty.is_empty():
		return -1
	var cards: Array = game.players[peer_id].cards
	for index in cards.size():
		if str(cards[index]) == "":
			cards[index] = penalty
			return index
	cards.append(penalty)
	return cards.size() - 1
