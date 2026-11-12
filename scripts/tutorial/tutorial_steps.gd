class_name TutorialSteps
extends RefCounted
## 教程固定牌序与快照（与 HiddenInfo 同形状，纯数据、可复现）。
## 玩家 seat0 [9,2,5,K]（下排 5/K 开局可见）；对手 seat1 [4,5,7,J]（始终不可见）。

const PLAYER := 0
const OPPONENT := 1
const PLAYER_NAME := "你"
const OPPONENT_NAME := "阿岚"

const CARDS := {
	"p0": ["9", "♠"], "p1": ["2", "♥"], "p2": ["5", "♦"], "p3": ["K", "♣"],
	"p7": ["7", "♠"],
	"o0": ["4", "♣"], "o1": ["5", "♠"], "o2": ["7", "♥"], "o3": ["J", "♦"],
	"d2": ["2", "♥"], "d5": ["5", "♠"], "d2b": ["2", "♦"],
}

static func _card(id: String) -> Dictionary:
	var rs: Array = CARDS[id]
	var rank := str(rs[0])
	var d := {"id": id, "rank": rank, "suit": str(rs[1]), "value": KongRules.card_value(rank)}
	d["label"] = KongRules.display_name(d)
	return d

static func _slot(id: String, revealed := false) -> Dictionary:
	var s := {"card_id": id, "protected": false, "bomb": false}
	if revealed and not id.is_empty():
		s["card"] = _card(id)
	return s

static func _empty_slot() -> Dictionary:
	return {"card_id": "", "protected": false, "bomb": false}

static func _player(seat: int, name: String, slots: Array) -> Dictionary:
	var count := 0
	for s in slots:
		if not str(s.get("card_id", "")).is_empty():
			count += 1
	return {"id": seat, "name": name, "count": count, "health": 2, "color": "",
		"eliminated": false, "currency": 100, "relics": ["", "", ""], "ready": true, "slots": slots}

static func _state(phase: int, p_slots: Array, o_slots: Array, extra := {}) -> Dictionary:
	var st := {
		"viewer_id": PLAYER,
		"current_player": PLAYER,
		"phase": phase,
		"match_id": "tutorial",
		"match_number": 1,
		"draw_count": 44,
		"discard": {},
		"discard_count": 0,
		"discard_history": [],
		"pending": {},
		"slap_open": false,
		"kong_caller": -1,
		"offline_players": [],
		"run": {"match_limit": 5},
		"turn_effect": "none",
		"players": [_player(PLAYER, PLAYER_NAME, p_slots), _player(OPPONENT, OPPONENT_NAME, o_slots)],
	}
	for k in extra.keys():
		st[k] = extra[k]
	return st

static func _player_hand() -> Array:
	return [_slot("p0"), _slot("p1"), _slot("p2"), _slot("p3")]

static func _opponent_hand() -> Array:
	return [_slot("o0"), _slot("o1"), _slot("o2"), _slot("o3")]

static func state_initial() -> Dictionary:
	return _state(GameState.Phase.INITIAL_PEEK,
		[_slot("p0"), _slot("p1"), _slot("p2", true), _slot("p3", true)], _opponent_hand())

static func state_memorized() -> Dictionary:
	return _state(GameState.Phase.INITIAL_PEEK, _player_hand(), _opponent_hand())

static func state_ready_draw() -> Dictionary:
	return _state(GameState.Phase.TURN_DRAW, _player_hand(), _opponent_hand())

static func state_drawn() -> Dictionary:
	var pending := _card("p7")
	pending["source"] = "draw"
	return _state(GameState.Phase.TURN_DRAW, _player_hand(), _opponent_hand(),
		{"draw_count": 43, "pending": pending})

static func state_replaced() -> Dictionary:
	var slots := [_slot("p0"), _slot("p7"), _slot("p2"), _slot("p3")]
	return _state(GameState.Phase.TURN_DRAW, slots, _opponent_hand(), {
		"current_player": OPPONENT, "draw_count": 42,
		"discard": _card("d2"), "discard_count": 1, "discard_history": [_card("d2")],
		"slap_open": true,
	})

static func state_opponent_discard() -> Dictionary:
	var slots := [_slot("p0"), _slot("p7"), _slot("p2"), _slot("p3")]
	return _state(GameState.Phase.TURN_DRAW, slots, _opponent_hand(), {
		"current_player": PLAYER, "draw_count": 41,
		"discard": _card("d5"), "discard_count": 2,
		"discard_history": [_card("d2"), _card("d5")], "slap_open": true,
	})

static func state_after_slap() -> Dictionary:
	var slots := [_slot("p0"), _slot("p7"), _empty_slot(), _slot("p3")]
	return _state(GameState.Phase.TURN_DRAW, slots, _opponent_hand(), {
		"current_player": PLAYER, "draw_count": 41,
		"discard": _card("p2"), "discard_count": 3,
		"discard_history": [_card("d2"), _card("d5"), _card("p2")],
		"slap_open": false,
	})

static func state_kongbaya() -> Dictionary:
	var st := state_after_slap()
	st["kong_caller"] = PLAYER
	st["current_player"] = OPPONENT
	return st

static func state_game_over() -> Dictionary:
	var p := [_slot("p0", true), _slot("p7", true), _empty_slot(), _slot("p3", true)]
	var o := [_slot("o0", true), _slot("o1", true), _slot("o2", true), _slot("o3", true)]
	return _state(GameState.Phase.GAME_OVER, p, o, {
		"current_player": PLAYER, "draw_count": 41,
		"discard": _card("p2"), "discard_count": 3,
		"discard_history": [_card("d2"), _card("d5"), _card("p2")],
		"kong_caller": PLAYER,
	})

static func result_model() -> Dictionary:
	return SettlementModel.build(state_game_over().players)

static func state_by_id(id: String) -> Dictionary:
	match id:
		"initial": return state_initial()
		"memorized": return state_memorized()
		"ready_draw": return state_ready_draw()
		"drawn": return state_drawn()
		"replaced": return state_replaced()
		"opponent_discard": return state_opponent_discard()
		"after_slap": return state_after_slap()
		"kongbaya": return state_kongbaya()
		"game_over": return state_game_over()
	return state_initial()
