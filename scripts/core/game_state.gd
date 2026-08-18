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

enum Phase { LOBBY, INITIAL_PEEK, TURN_DRAW, TURN_DECISION, Q_DECISION, SLAP_WINDOW, SLAP_EXCHANGE, GAME_OVER }

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
	ALREADY_ATTEMPTED_SLAP,
	DUPLICATE_OR_EXPIRED_ACTION,
	MATCH_ABORTED_PLAYER_LEFT,
	HOST_DISCONNECTED,
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
var slap_resume := ""
var slap_attempted: Dictionary = {}
var slap_exchange: Dictionary = {}
var last_result: Dictionary = {}
var event_log: Array[String] = []
var run_state: Dictionary = KongRules.new_default_run()
var match_number := 1
var match_id := ""
var state_revision := 0
var action_history: Dictionary = {}
var last_seen_revision := -1

var slap_timer := Timer.new()

func _ready() -> void:
	slap_timer.one_shot = true
	add_child(slap_timer)
	slap_timer.timeout.connect(_on_slap_timeout)
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
	slap_resume = ""
	slap_attempted.clear()
	slap_exchange.clear()
	last_result.clear()
	event_log.clear()
	run_state = KongRules.new_default_run()
	match_number = 1
	match_id = ""
	state_revision = 0
	action_history.clear()
	slap_timer.stop()

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
	_open_slap("advance")

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
	match rank:
		"7", "8":
			var own_slot := int(data.get("slot", -1))
			if not _valid_slot(sender, own_slot):
				_reject(sender, RejectCode.INVALID_SLOT, action_id)
				return
			_send_reveal(sender, "查看自己的牌", [_card_public(players[sender].cards[own_slot])], {"player_id": sender, "slot": own_slot})
			_add_log("%s 查看了自己的一张牌。" % players[sender].name)
			_discard_pending_and_open_slap("advance")
		"9", "10":
			var target := int(data.get("target", 0))
			var target_slot := int(data.get("target_slot", -1))
			if target == sender or not _valid_slot(target, target_slot):
				_reject(sender, RejectCode.INVALID_TARGET, action_id)
				return
			_send_reveal(sender, "查看别人的牌", [_card_public(players[target].cards[target_slot])], {"player_id": target, "slot": target_slot})
			_add_log("%s 查看了 %s 的一张牌。" % [players[sender].name, players[target].name])
			_discard_pending_and_open_slap("advance")
		"J":
			var swap_target := int(data.get("target", 0))
			var own_swap_slot := int(data.get("own_slot", -1))
			var their_swap_slot := int(data.get("target_slot", -1))
			if swap_target == sender or not _valid_slot(sender, own_swap_slot) or not _valid_slot(swap_target, their_swap_slot):
				_reject(sender, RejectCode.INVALID_TARGET, action_id)
				return
			var mine: String = players[sender].cards[own_swap_slot]
			players[sender].cards[own_swap_slot] = players[swap_target].cards[their_swap_slot]
			players[swap_target].cards[their_swap_slot] = mine
			_add_log("%s 与 %s 盲换了一张牌。" % [players[sender].name, players[swap_target].name])
			_discard_pending_and_open_slap("advance")
		"Q":
			var q_target := int(data.get("target", 0))
			var q_slot := int(data.get("target_slot", -1))
			if q_target == sender or not _valid_slot(q_target, q_slot):
				_reject(sender, RejectCode.INVALID_TARGET, action_id)
				return
			q_context = {"actor": sender, "target": q_target, "target_slot": q_slot}
			phase = Phase.Q_DECISION
			_send_reveal(sender, "Q：查看后决定是否交换", [_card_public(players[q_target].cards[q_slot])], {"player_id": q_target, "slot": q_slot})
			_add_log("%s 正在决定是否交换。" % players[sender].name)
			_broadcast_state()

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
		var mine: String = players[sender].cards[own_slot]
		players[sender].cards[own_slot] = players[target].cards[target_slot]
		players[target].cards[target_slot] = mine
		_add_log("%s 用 Q 交换了一张牌。" % players[sender].name)
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
	if phase != Phase.SLAP_WINDOW:
		_reject(sender, RejectCode.INVALID_PHASE, action_id)
		return
	if not players.has(sender):
		return
	if slap_attempted.has(sender):
		_reject(sender, RejectCode.ALREADY_ATTEMPTED_SLAP, action_id)
		return
	if not _check_action_id(sender, action_id):
		_reject(sender, RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	if not _valid_slot(target_player, slot):
		_reject(sender, RejectCode.INVALID_TARGET, action_id)
		return
	slap_attempted[sender] = true
	var target_card: String = players[target_player].cards[slot]
	if cards[target_card].rank != slap_rank:
		_add_penalty_card(sender)
		_add_log("%s 贴错了，罚抽一张牌。" % players[sender].name)
		_broadcast_state()
		return
	if target_player == sender:
		players[sender].cards.remove_at(slot)
		discard_pile.append(target_card)
		_add_log("%s 成功贴出自己的 %s。" % [players[sender].name, slap_rank])
		_finish_slap()
		return
	slap_timer.stop()
	phase = Phase.SLAP_EXCHANGE
	slap_exchange = {"actor": sender, "target": target_player, "target_slot": slot, "target_card": target_card}
	_add_log("%s 贴中了 %s 的牌，等待交出一张自己的牌。" % [players[sender].name, players[target_player].name])
	_broadcast_state()

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
	if phase != Phase.SLAP_EXCHANGE:
		_reject(sender, RejectCode.INVALID_PHASE, action_id)
		return
	if sender != int(slap_exchange.get("actor", 0)):
		_reject(sender, RejectCode.NOT_CURRENT_PLAYER, action_id)
		return
	if not _check_action_id(sender, action_id):
		_reject(sender, RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	if not _valid_slot(sender, own_slot):
		_reject(sender, RejectCode.INVALID_SLOT, action_id)
		return
	var target := int(slap_exchange.target)
	var target_slot := int(slap_exchange.target_slot)
	if not _valid_slot(target, target_slot):
		return
	var gift: String = players[sender].cards[own_slot]
	var pasted: String = players[target].cards[target_slot]
	players[sender].cards.remove_at(own_slot)
	players[target].cards[target_slot] = gift
	discard_pile.append(pasted)
	_add_log("%s 成功贴牌并将一张牌交给 %s。" % [players[sender].name, players[target].name])
	_finish_slap()

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
	if phase != Phase.TURN_DRAW:
		_reject(sender, RejectCode.INVALID_PHASE, action_id)
		return
	if sender != current_player_id:
		_reject(sender, RejectCode.NOT_CURRENT_PLAYER, action_id)
		return
	if not _check_action_id(sender, action_id):
		_reject(sender, RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	kong_caller = sender
	kong_called_first_turn = not bool(players[sender].has_acted)
	final_queue = TurnSystem.build_final_queue(turn_order, sender)
	_add_log("%s 喊出了 Kongbaya！其他玩家各有最后一次行动。" % players[sender].name)
	_advance_turn(true)

func _discard_pending_and_open_slap(resume: String) -> void:
	var card_id: String = pending_draw.card_id
	pending_draw.clear()
	_discard(card_id)
	_open_slap(resume)

func _discard(card_id: String) -> void:
	discard_pile.append(card_id)
	slap_rank = cards[card_id].rank

func _open_slap(resume: String) -> void:
	slap_resume = resume
	slap_attempted.clear()
	slap_exchange.clear()
	phase = Phase.SLAP_WINDOW
	slap_timer.start(KongRules.SLAP_WINDOW_SECONDS)
	_broadcast_state()

func _on_slap_timeout() -> void:
	if multiplayer.is_server() and phase == Phase.SLAP_WINDOW:
		_add_log("贴牌时间结束。")
		_finish_slap()

func _finish_slap() -> void:
	slap_timer.stop()
	slap_rank = ""
	slap_attempted.clear()
	slap_exchange.clear()
	if slap_resume == "advance":
		_advance_turn()
	else:
		phase = Phase.TURN_DRAW
		_broadcast_state()

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

func _add_penalty_card(peer_id: int) -> void:
	var penalty := _draw_from_deck()
	if not penalty.is_empty():
		players[peer_id].cards.append(penalty)

func _finish_game(reason := "") -> void:
	slap_timer.stop()
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
	if peer_id == 1:
		_receive_reveal(title, revealed_cards, target)
	else:
		receive_reveal.rpc_id(peer_id, title, revealed_cards, target)

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
func receive_toast(message: String) -> void:
	toast_received.emit(message)

@rpc("authority", "call_remote", "reliable")
func receive_rejected(code: int, _action_id: String, message: String) -> void:
	command_rejected.emit(code, message)

@rpc("authority", "call_remote", "reliable")
func receive_match_aborted(code: int, message: String) -> void:
	match_aborted.emit(code, message)
