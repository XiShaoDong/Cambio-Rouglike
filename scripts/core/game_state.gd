class_name KongGameState
extends Node

## Server-authoritative Kong match rules. Clients submit only intentions
## ("take draw pile", "use slot 2"); this node validates them and sends a
## different snapshot to every peer so hidden card faces remain hidden.

signal lobby_updated(lobby: Dictionary)
signal state_updated(state: Dictionary)
signal private_reveal_received(title: String, cards: Array, target: Dictionary)
signal toast_received(message: String)
signal command_rejected(code: int, message: String)
signal match_aborted(code: int, message: String)
signal card_exchange_animated(data: Dictionary)
signal peek_highlighted(data: Dictionary)

enum Phase { LOBBY, INITIAL_PEEK, TURN_DRAW, TURN_DECISION, Q_DECISION, SLAP_WINDOW, SLAP_EXCHANGE, GAME_OVER, SLAP_DUEL }

const PROTOCOL_VERSION := 1
const MAX_ACTION_HISTORY := 64

enum RejectCode {
	PROTOCOL_VERSION_MISMATCH,
	ROOM_FULL,
	ROOM_NOT_OPEN,
	NOT_HOST,
	NOT_ENOUGH_PLAYERS,
	MATCH_NOT_ACTIVE,
	INVALID_PHASE,
	NOT_CURRENT_PLAYER,
	INVALID_SLOT,
	INVALID_TARGET,
	INVALID_SOURCE,
	ABILITY_FORBIDDEN,
	DRAW_UNAVAILABLE,
	ALREADY_ATTEMPTED_SLAP,  # 已弃用：贴牌不限次数，不再返回该错误（保留枚举值避免位移）
	DUPLICATE_OR_EXPIRED_ACTION,
	MATCH_ABORTED_PLAYER_LEFT,
	HOST_DISCONNECTED,
	NOT_DUEL_CONTESTANT,
	ALREADY_STOPPED,
}

var phase: Phase = Phase.LOBBY
var players: Dictionary = {}
var turn_order: Array[int] = []
var current_player_id := 0
var deck: Array[String] = []
var discard_pile: Array[String] = []
var cards: Dictionary = {}
var pending_draw: Dictionary = {}
var q_context: Dictionary = {}
var initial_confirmed: Dictionary = {}
var final_queue: Array[int] = []
var kong_caller := 0
var kong_called_first_turn := false
var slap_rank := ""
var slap_open := false
var slap_exchange: Dictionary = {}
var slap_collect: Dictionary = {}
var slap_duel: Dictionary = {}
var debug_duel := false
var last_result: Dictionary = {}
var event_log: Array[String] = []
var run_state: Dictionary = KongRules.new_default_run()
var match_number := 1
var match_id := ""
var state_revision := 0
var action_history: Dictionary = {}
var last_seen_revision := -1

var peek: PeekSystem
var effects: EffectSystem
var swap: SwapSystem
var slap: SlapSystem
var kongbaya: KongbayaSystem
var slap_collect_timer := Timer.new()
var slap_duel_timer := Timer.new()

func _ready() -> void:
	peek = PeekSystem.new(self)
	effects = EffectSystem.new(self)
	swap = SwapSystem.new(self)
	slap = SlapSystem.new(self)
	kongbaya = KongbayaSystem.new(self)
	slap_collect_timer.one_shot = true
	slap_duel_timer.one_shot = true
	add_child(slap_collect_timer)
	add_child(slap_duel_timer)
	slap_collect_timer.timeout.connect(slap.collection_timeout)
	slap_duel_timer.timeout.connect(slap.duel_timeout)
	Network.host_started.connect(_on_host_started)
	Network.joined_server.connect(_on_joined_server)
	Network.peer_left.connect(_on_peer_left)
	Network.connection_status_changed.connect(_on_network_status)

func _on_network_status(message: String) -> void:
	if not Network.is_host and message.contains("断开"):
		toast_received.emit(message)
		_broadcast_abort(RejectCode.HOST_DISCONNECTED)

func _on_host_started(profile: Dictionary) -> void:
	_reset_match()
	_add_player(1, str(profile.get("name", "房主")))
	_broadcast_lobby()

func _on_joined_server() -> void:
	request_register_player.rpc_id(1, str(Network.local_profile.get("name", "玩家")), PROTOCOL_VERSION)

func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not players.has(peer_id):
		return
	var left_name: String = players[peer_id].get("name", "玩家")
	players.erase(peer_id)
	turn_order.erase(peer_id)
	if phase == Phase.LOBBY:
		_broadcast_lobby()
		return
	_broadcast_abort(RejectCode.MATCH_ABORTED_PLAYER_LEFT, "%s 中途断线，当前对局已中止。" % left_name)
	_reset_match()
	_add_player(1, str(Network.local_profile.get("name", "房主")))
	_broadcast_lobby()

func _reset_match() -> void:
	phase = Phase.LOBBY
	players.clear()
	turn_order.clear()
	deck.clear()
	discard_pile.clear()
	cards.clear()
	pending_draw.clear()
	q_context.clear()
	initial_confirmed.clear()
	final_queue.clear()
	kong_caller = 0
	kong_called_first_turn = false
	slap_rank = ""
	slap_open = false
	slap_exchange.clear()
	slap_collect.clear()
	slap_duel.clear()
	slap_collect_timer.stop()
	slap_duel_timer.stop()
	last_result.clear()
	event_log.clear()
	run_state = KongRules.new_default_run()
	match_number = 1
	match_id = ""
	state_revision = 0
	last_seen_revision = -1
	action_history.clear()

func _new_match_id() -> String:
	return "m_%08x_%s" % [randi(), Time.get_unix_time_from_system()]

func _reject_code_message(code: int) -> String:
	match code:
		RejectCode.PROTOCOL_VERSION_MISMATCH: return "客户端与服务器版本不兼容。"
		RejectCode.ROOM_FULL: return "房间已满。"
		RejectCode.ROOM_NOT_OPEN: return "房间当前不能注册或开局。"
		RejectCode.NOT_HOST: return "只有房主可以开始对局。"
		RejectCode.NOT_ENOUGH_PLAYERS: return "至少需要 %d 位玩家。" % KongRules.MIN_PLAYERS
		RejectCode.MATCH_NOT_ACTIVE: return "当前没有进行中的对局。"
		RejectCode.INVALID_PHASE: return "当前阶段不允许该操作。"
		RejectCode.NOT_CURRENT_PLAYER: return "还没轮到你行动。"
		RejectCode.INVALID_SLOT: return "牌位不存在或不属于你。"
		RejectCode.INVALID_TARGET: return "目标玩家或牌位不合法。"
		RejectCode.INVALID_SOURCE: return "该牌源当前不可用。"
		RejectCode.ABILITY_FORBIDDEN: return "这张牌不能发动能力。"
		RejectCode.DRAW_UNAVAILABLE: return "没有可抽的牌。"
		RejectCode.ALREADY_ATTEMPTED_SLAP: return "本次贴牌窗口你已经尝试过了。"
		RejectCode.DUPLICATE_OR_EXPIRED_ACTION: return "该操作已处理或已过期。"
		RejectCode.MATCH_ABORTED_PLAYER_LEFT: return "其他玩家中途断线，对局已中止。"
		RejectCode.HOST_DISCONNECTED: return "房主已经断开。"
		RejectCode.NOT_DUEL_CONTESTANT: return "你不是比拼候选人。"
		RejectCode.ALREADY_STOPPED: return "你已经在比拼中按过 STOP。"
	return "操作被拒绝。"

func _check_action_id(sender: int, action_id: String) -> bool:
	if action_id.is_empty():
		return true
	var seen: Array = action_history.get(sender, [])
	if action_id in seen:
		return false
	seen.append(action_id)
	if seen.size() > MAX_ACTION_HISTORY:
		seen.pop_front()
	action_history[sender] = seen
	return true

func _reject(sender: int, code: int, action_id := "") -> void:
	var message := _reject_code_message(code)
	if sender == 1:
		command_rejected.emit(code, message)
	else:
		receive_rejected.rpc_id(sender, code, action_id, message)

func _add_player(peer_id: int, display_name: String) -> void:
	var safe_name := display_name.strip_edges().left(16)
	if safe_name.is_empty():
		safe_name = "玩家 %d" % peer_id
	players[peer_id] = {
		"id": peer_id,
		"name": safe_name,
		"cards": [],
		"has_acted": false,
		"health": int(run_state.get("health", 3)),
	}
	turn_order.append(peer_id)

@rpc("any_peer", "reliable")
func request_register_player(display_name: String, protocol_version: int = KongGameState.PROTOCOL_VERSION) -> void:
	if not multiplayer.is_server() or phase != Phase.LOBBY:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 0 or players.has(sender):
		return
	if protocol_version != PROTOCOL_VERSION:
		_reject(sender, RejectCode.PROTOCOL_VERSION_MISMATCH)
		return
	if players.size() >= KongRules.MAX_PLAYERS:
		_reject(sender, RejectCode.ROOM_FULL)
		return
	_add_player(sender, display_name)
	_add_log("%s 加入了房间。" % players[sender].name)
	_broadcast_lobby()

func request_start_match() -> void:
	if multiplayer.is_server():
		_server_start_match(1)
	else:
		server_start_match.rpc_id(1)

@rpc("any_peer", "reliable")
func server_start_match() -> void:
	if multiplayer.is_server():
		_server_start_match(multiplayer.get_remote_sender_id())

func _server_start_match(sender: int) -> void:
	if phase != Phase.LOBBY:
		_reject(sender, RejectCode.ROOM_NOT_OPEN)
		return
	if sender != 1:
		_reject(sender, RejectCode.NOT_HOST)
		return
	if players.size() < KongRules.MIN_PLAYERS:
		_reject(sender, RejectCode.NOT_ENOUGH_PLAYERS)
		return
	match_id = _new_match_id()
	_create_deck()
	for peer_id in turn_order:
		players[peer_id].cards.clear()
		players[peer_id].has_acted = false
		for _slot in KongRules.HAND_SIZE:
			players[peer_id].cards.append(_draw_from_deck())
	phase = Phase.INITIAL_PEEK
	initial_confirmed.clear()
	_add_log("对局开始：请记住自己下方的两张牌。")
	_broadcast_state()

func _create_deck() -> void:
	deck.clear()
	cards.clear()
	var suits := ["♠", "♥", "♣", "♦"]
	var ranks := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
	var serial := 0
	for suit in suits:
		for rank in ranks:
			_add_card("c_%08x_%03d" % [randi(), serial], rank, suit)
			serial += 1
	_add_card("c_%08x_%03d" % [randi(), serial], "JOKER", "black")
	serial += 1
	_add_card("c_%08x_%03d" % [randi(), serial], "JOKER", "red")
	deck.shuffle()

func _add_card(card_id: String, rank: String, suit: String) -> void:
	cards[card_id] = {"id": card_id, "rank": rank, "suit": suit, "value": KongRules.card_value(rank)}
	deck.append(card_id)

func _draw_from_deck() -> String:
	if deck.is_empty():
		if discard_pile.size() <= 1:
			return ""
		var top: String = discard_pile.pop_back()
		deck = discard_pile.duplicate()
		discard_pile = [top]
		deck.shuffle()
		_add_log("抽牌堆重洗。")
	return deck.pop_back()

func request_initial_ready() -> void:
	if multiplayer.is_server():
		_server_initial_ready(1)
	else:
		server_initial_ready.rpc_id(1)

@rpc("any_peer", "reliable")
func server_initial_ready() -> void:
	if multiplayer.is_server():
		_server_initial_ready(multiplayer.get_remote_sender_id())

func _server_initial_ready(sender: int) -> void:
	if phase != Phase.INITIAL_PEEK:
		_reject(sender, RejectCode.INVALID_PHASE)
		return
	if not players.has(sender):
		return
	if initial_confirmed.has(sender):
		_reject(sender, RejectCode.DUPLICATE_OR_EXPIRED_ACTION)
		return
	initial_confirmed[sender] = true
	if initial_confirmed.size() < players.size():
		_broadcast_state()
		return
	current_player_id = turn_order[0]
	phase = Phase.TURN_DRAW
	_add_log("轮到 %s 行动。" % players[current_player_id].name)
	_broadcast_state()

func request_take(source: String, action_id := "") -> void:
	if multiplayer.is_server():
		_server_take(1, source, action_id)
	else:
		server_take.rpc_id(1, source, action_id)

@rpc("any_peer", "reliable")
func server_take(source: String, action_id: String) -> void:
	if multiplayer.is_server():
		_server_take(multiplayer.get_remote_sender_id(), source, action_id)

func _server_take(sender: int, source: String, action_id := "") -> void:
	if phase != Phase.TURN_DRAW:
		_reject(sender, RejectCode.INVALID_PHASE, action_id)
		return
	if sender != current_player_id:
		_reject(sender, RejectCode.NOT_CURRENT_PLAYER, action_id)
		return
	if not _check_action_id(sender, action_id):
		_reject(sender, RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	var card_id := ""
	if source == "draw":
		card_id = _draw_from_deck()
	elif source == "discard" and not discard_pile.is_empty():
		if players[sender].cards.is_empty():
			_reject(sender, RejectCode.INVALID_SOURCE, action_id)
			return
		card_id = discard_pile.pop_back()
	else:
		_reject(sender, RejectCode.INVALID_SOURCE, action_id)
		return
	if card_id.is_empty():
		_reject(sender, RejectCode.DRAW_UNAVAILABLE, action_id)
		return
	pending_draw = {"card_id": card_id, "source": source}
	slap_open = false
	phase = Phase.TURN_DECISION
	_add_log("%s 取了一张牌。" % players[sender].name)
	_broadcast_state()

func request_replace(slot: int, action_id := "") -> void:
	if multiplayer.is_server():
		_server_replace(1, slot, action_id)
	else:
		server_replace.rpc_id(1, slot, action_id)

@rpc("any_peer", "reliable")
func server_replace(slot: int, action_id: String) -> void:
	if multiplayer.is_server():
		_server_replace(multiplayer.get_remote_sender_id(), slot, action_id)

func _server_replace(sender: int, slot: int, action_id := "") -> void:
	if phase != Phase.TURN_DECISION:
		_reject(sender, RejectCode.INVALID_PHASE, action_id)
		return
	if sender != current_player_id:
		_reject(sender, RejectCode.NOT_CURRENT_PLAYER, action_id)
		return
	if not _valid_slot(sender, slot):
		_reject(sender, RejectCode.INVALID_SLOT, action_id)
		return
	if not _check_action_id(sender, action_id):
		_reject(sender, RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	var incoming: String = pending_draw.card_id
	var outgoing: String = players[sender].cards[slot]
	players[sender].cards[slot] = incoming
	pending_draw.clear()
	_discard(outgoing)
	_add_log("%s 替换了一张手牌。" % players[sender].name)
	_broadcast_exchange({"kind": "replace", "actor": sender, "slot": slot,
		"old_data": _card_public(outgoing), "big_data": _card_public(incoming)})
	_open_slap("")
	_advance_turn()

func request_discard_draw(action_id := "") -> void:
	if multiplayer.is_server():
		_server_discard_draw(1, action_id)
	else:
		server_discard_draw.rpc_id(1, action_id)

@rpc("any_peer", "reliable")
func server_discard_draw(action_id: String) -> void:
	if multiplayer.is_server():
		_server_discard_draw(multiplayer.get_remote_sender_id(), action_id)

func _server_discard_draw(sender: int, action_id := "") -> void:
	if phase != Phase.TURN_DECISION:
		_reject(sender, RejectCode.INVALID_PHASE, action_id)
		return
	if sender != current_player_id:
		_reject(sender, RejectCode.NOT_CURRENT_PLAYER, action_id)
		return
	if pending_draw.get("source") != "draw":
		_reject(sender, RejectCode.ABILITY_FORBIDDEN, action_id)
		return
	if not _check_action_id(sender, action_id):
		_reject(sender, RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	_broadcast_exchange({"kind": "discard", "actor": sender, "big_data": _card_public(pending_draw.card_id)})
	_discard_pending_and_open_slap("advance")
	_add_log("%s 弃掉了抽到的牌。" % players[sender].name)

func request_use_ability(data: Dictionary, action_id := "") -> void:
	if multiplayer.is_server():
		_server_use_ability(1, data, action_id)
	else:
		server_use_ability.rpc_id(1, data, action_id)

@rpc("any_peer", "reliable")
func server_use_ability(data: Dictionary, action_id: String) -> void:
	if multiplayer.is_server():
		_server_use_ability(multiplayer.get_remote_sender_id(), data, action_id)

func _server_use_ability(sender: int, data: Dictionary, action_id := "") -> void:
	if phase != Phase.TURN_DECISION:
		_reject(sender, RejectCode.INVALID_PHASE, action_id)
		return
	if sender != current_player_id:
		_reject(sender, RejectCode.NOT_CURRENT_PLAYER, action_id)
		return
	if pending_draw.get("source") != "draw":
		_reject(sender, RejectCode.ABILITY_FORBIDDEN, action_id)
		return
	if not _check_action_id(sender, action_id):
		_reject(sender, RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	var rank: String = cards[pending_draw.card_id].rank
	if not KongRules.has_ability(rank):
		_reject(sender, RejectCode.ABILITY_FORBIDDEN, action_id)
		return
	effects.resolve_ability(sender, rank, data, action_id)

func request_q_decision(exchange: bool, own_slot := -1, action_id := "") -> void:
	if multiplayer.is_server():
		_server_q_decision(1, exchange, own_slot, action_id)
	else:
		server_q_decision.rpc_id(1, exchange, own_slot, action_id)

@rpc("any_peer", "reliable")
func server_q_decision(exchange: bool, own_slot: int, action_id: String) -> void:
	if multiplayer.is_server():
		_server_q_decision(multiplayer.get_remote_sender_id(), exchange, own_slot, action_id)

func _server_q_decision(sender: int, exchange: bool, own_slot: int, action_id := "") -> void:
	if phase != Phase.Q_DECISION:
		_reject(sender, RejectCode.INVALID_PHASE, action_id)
		return
	if sender != int(q_context.get("actor", 0)):
		_reject(sender, RejectCode.NOT_CURRENT_PLAYER, action_id)
		return
	if not _check_action_id(sender, action_id):
		_reject(sender, RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	if exchange:
		var target := int(q_context.target)
		var target_slot := int(q_context.target_slot)
		if not _valid_slot(sender, own_slot) or not _valid_slot(target, target_slot):
			_reject(sender, RejectCode.INVALID_SLOT, action_id)
			return
		swap.swap(sender, own_slot, target, target_slot, "%s 用 Q 交换了一张牌。" % players[sender].name)
		var a_data: Dictionary = _card_public(players[target].cards[target_slot])
		var b_data: Dictionary = _card_public(players[sender].cards[own_slot])
		_broadcast_exchange({"kind": "swap", "a": sender, "a_slot": own_slot, "b": target, "b_slot": target_slot, "a_data": a_data, "b_data": b_data})
	else:
		_add_log("%s 用 Q 放弃了交换。" % players[sender].name)
	q_context.clear()
	_discard_pending_and_open_slap("advance")

func request_slap(target_player: int, slot: int, action_id := "") -> void:
	if multiplayer.is_server():
		_server_slap(1, target_player, slot, action_id)
	else:
		server_slap.rpc_id(1, target_player, slot, action_id)

@rpc("any_peer", "reliable")
func server_slap(target_player: int, slot: int, action_id: String) -> void:
	if multiplayer.is_server():
		_server_slap(multiplayer.get_remote_sender_id(), target_player, slot, action_id)

func _server_slap(sender: int, target_player: int, slot: int, action_id := "") -> void:
	slap.attempt(sender, target_player, slot, action_id)

func request_slap_exchange(own_slot: int, action_id := "") -> void:
	if multiplayer.is_server():
		_server_slap_exchange(1, own_slot, action_id)
	else:
		server_slap_exchange.rpc_id(1, own_slot, action_id)

@rpc("any_peer", "reliable")
func server_slap_exchange(own_slot: int, action_id: String) -> void:
	if multiplayer.is_server():
		_server_slap_exchange(multiplayer.get_remote_sender_id(), own_slot, action_id)

func _server_slap_exchange(sender: int, own_slot: int, action_id := "") -> void:
	slap.exchange(sender, own_slot, action_id)

func request_slap_duel_stop(action_id := "") -> void:
	if multiplayer.is_server():
		_server_slap_duel_stop(1, action_id)
	else:
		server_slap_duel_stop.rpc_id(1, action_id)

@rpc("any_peer", "reliable")
func server_slap_duel_stop(action_id: String) -> void:
	if multiplayer.is_server():
		_server_slap_duel_stop(multiplayer.get_remote_sender_id(), action_id)

func _server_slap_duel_stop(sender: int, action_id := "") -> void:
	slap.duel_stop(sender, action_id)

func request_kongbaya(action_id := "") -> void:
	if multiplayer.is_server():
		_server_kongbaya(1, action_id)
	else:
		server_kongbaya.rpc_id(1, action_id)

@rpc("any_peer", "reliable")
func server_kongbaya(action_id: String) -> void:
	if multiplayer.is_server():
		_server_kongbaya(multiplayer.get_remote_sender_id(), action_id)

func _server_kongbaya(sender: int, action_id := "") -> void:
	kongbaya.declare(sender, action_id)

func _discard_pending_and_open_slap(_resume: String) -> void:
	var card_id: String = pending_draw.card_id
	pending_draw.clear()
	_discard(card_id)
	_open_slap("")
	_advance_turn()

func _discard(card_id: String) -> void:
	discard_pile.append(card_id)
	slap_rank = cards[card_id].rank

func _open_slap(_resume: String) -> void:
	slap_open = true
	slap.open_slap()

func _finish_slap() -> void:
	slap.finish_slap()

func _advance_turn(final_mode := false) -> void:
	if players.has(current_player_id):
		players[current_player_id].has_acted = true
	var decision: Dictionary
	if kong_caller != 0 or final_mode:
		decision = {"type": TurnSystem.Decision.FINAL if not final_queue.is_empty() else TurnSystem.Decision.FINISH,
			"next_player": int(final_queue[0]) if not final_queue.is_empty() else 0}
	else:
		decision = TurnSystem.decide(turn_order, current_player_id, 0, [])
	match decision.type:
		TurnSystem.Decision.FINISH:
			_finish_game()
			return
		TurnSystem.Decision.FINAL:
			current_player_id = decision.next_player
			final_queue.pop_front()
			phase = Phase.TURN_DRAW
			_add_log("%s 的最终行动。" % players[current_player_id].name)
			_broadcast_state()
			return
		TurnSystem.Decision.NEXT:
			current_player_id = decision.next_player
			phase = Phase.TURN_DRAW
			_add_log("轮到 %s 行动。" % players[current_player_id].name)
			_broadcast_state()

func _finish_game(reason := "") -> void:
	slap_open = false
	slap_collect.clear()
	slap_duel.clear()
	slap_collect_timer.stop()
	slap_duel_timer.stop()
	phase = Phase.GAME_OVER
	if not reason.is_empty():
		last_result = {"reason": reason, "ranking": []}
		_broadcast_state()
		return
	var ranking := _calculate_ranking()
	var winners: Array[int] = []
	var losers: Array[int] = []
	if not ranking.is_empty():
		for entry in ranking:
			if _same_score(entry, ranking[0]): winners.append(int(entry.id))
			if _same_score(entry, ranking[ranking.size() - 1]): losers.append(int(entry.id))
	if winners.size() == players.size():
		losers.clear()
	if kong_called_first_turn and kong_caller not in winners:
		losers = [kong_caller]
	for peer_id in losers:
		players[peer_id].health = max(0, int(players[peer_id].health) - 1)
	last_result = {"ranking": ranking, "winners": winners, "penalized": losers, "first_turn_kong": kong_called_first_turn}
	_add_log("对局结束，所有手牌已翻开。")
	_broadcast_state()

func _calculate_ranking() -> Array:
	return ScoreSystem.calculate_ranking(players, cards, turn_order)

func _is_lower_score(a: Dictionary, b: Dictionary) -> bool:
	return ScoreSystem._is_lower_score(a, b)

func _same_score(a: Dictionary, b: Dictionary) -> bool:
	return ScoreSystem.same_score(a, b)

func _valid_slot(peer_id: int, slot: int) -> bool:
	return players.has(peer_id) and slot >= 0 and slot < players[peer_id].cards.size()

func _card_public(card_id: String) -> Dictionary:
	return HiddenInfo.public_card(self, card_id)

func _player_snapshot(peer_id: int, reveal_all: bool, viewer_id := 0, peek_slots: Array[int] = []) -> Dictionary:
	return HiddenInfo._player_snapshot(self, peer_id, reveal_all, viewer_id, peek_slots)

func _snapshot_for(viewer_id: int) -> Dictionary:
	return HiddenInfo.snapshot_for(self, viewer_id)

func _phase_name() -> String:
	return HiddenInfo._phase_name(phase)

func _lobby_snapshot() -> Dictionary:
	var entries: Array = []
	for peer_id in turn_order:
		entries.append({"id": peer_id, "name": players[peer_id].name})
	return {"players": entries, "host_id": 1, "min_players": KongRules.MIN_PLAYERS, "max_players": KongRules.MAX_PLAYERS}

func _broadcast_lobby() -> void:
	var lobby := _lobby_snapshot()
	_receive_lobby(lobby)
	for peer_id in players.keys():
		if int(peer_id) != 1:
			receive_lobby.rpc_id(int(peer_id), lobby)

func _broadcast_state() -> void:
	state_revision += 1
	var snapshots: Dictionary = {}
	for peer_id in players.keys():
		snapshots[int(peer_id)] = _snapshot_for(int(peer_id))
	for peer_id in snapshots:
		if peer_id == 1:
			_receive_state.call_deferred(snapshots[peer_id])
		else:
			receive_state.rpc_id(peer_id, snapshots[peer_id])

func _broadcast_abort(code: int, message := "") -> void:
	if message.is_empty():
		message = _reject_code_message(code)
	for peer_id in players.keys():
		if int(peer_id) == 1:
			match_aborted.emit(code, message)
		else:
			receive_match_aborted.rpc_id(int(peer_id), code, message)

func _send_reveal(peer_id: int, title: String, revealed_cards: Array, target: Dictionary = {}) -> void:
	if peek != null:
		peek.send_reveal(peer_id, title, revealed_cards, target)
	else:
		_receive_reveal(title, revealed_cards, target)

## 广播交换动画事件到所有玩家（在 _broadcast_state 之前调用，保证 client 先用旧布局定位）。
func _broadcast_exchange(data: Dictionary) -> void:
	for peer_id in players.keys():
		if int(peer_id) == 1:
			_receive_exchange_animated(data)
		else:
			receive_exchange_animated.rpc_id(int(peer_id), data)

## 广播查看高亮事件给除 viewer 外的所有玩家（不含牌面，仅标记被查看牌的位置）。
func _broadcast_peek_highlight(viewer: int, data: Dictionary) -> void:
	print("[peek_glow] server broadcast viewer=%d -> %s" % [viewer, str(data)])
	for peer_id in players.keys():
		if int(peer_id) == viewer:
			continue
		if int(peer_id) == 1:
			_receive_peek_highlight(data)
		else:
			receive_peek_highlight.rpc_id(int(peer_id), data)

func _send_toast(peer_id: int, message: String) -> void:
	if peer_id == 1:
		toast_received.emit(message)
	else:
		receive_toast.rpc_id(peer_id, message)

func _add_log(message: String) -> void:
	event_log.push_front(message)
	if event_log.size() > 6:
		event_log.pop_back()

func _receive_lobby(lobby: Dictionary) -> void:
	lobby_updated.emit(lobby)

func _receive_state(snapshot: Dictionary) -> void:
	var revision := int(snapshot.get("state_revision", -1))
	if revision <= last_seen_revision:
		return
	last_seen_revision = revision
	state_updated.emit(snapshot)

func _receive_reveal(title: String, revealed_cards: Array, target: Dictionary = {}) -> void:
	private_reveal_received.emit(title, revealed_cards, target)

func _receive_exchange_animated(data: Dictionary) -> void:
	card_exchange_animated.emit(data)

func _receive_peek_highlight(data: Dictionary) -> void:
	peek_highlighted.emit(data)

@rpc("authority", "call_remote", "reliable")
func receive_lobby(lobby: Dictionary) -> void:
	_receive_lobby(lobby)

@rpc("authority", "call_remote", "reliable")
func receive_state(snapshot: Dictionary) -> void:
	_receive_state(snapshot)

@rpc("authority", "call_remote", "reliable")
func receive_reveal(title: String, revealed_cards: Array, target: Dictionary = {}) -> void:
	_receive_reveal(title, revealed_cards, target)

@rpc("authority", "call_remote", "reliable")
func receive_exchange_animated(data: Dictionary) -> void:
	_receive_exchange_animated(data)

@rpc("authority", "call_remote", "reliable")
func receive_peek_highlight(data: Dictionary) -> void:
	_receive_peek_highlight(data)

@rpc("authority", "call_remote", "reliable")
func receive_toast(message: String) -> void:
	toast_received.emit(message)

@rpc("authority", "call_remote", "reliable")
func receive_rejected(code: int, _action_id: String, message: String) -> void:
	command_rejected.emit(code, message)

@rpc("authority", "call_remote", "reliable")
func receive_match_aborted(code: int, message: String) -> void:
	# 对局中止后 state_revision 从 0 重新计数，客户端必须重置去重水位线，
	# 否则新一局所有快照（revision 从 1 起）都会被误判为旧包丢弃，UI 卡在大厅。
	last_seen_revision = -1
	match_aborted.emit(code, message)
