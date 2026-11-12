class_name TutorialSteps
extends RefCounted
## 教程固定牌序与快照（与 HiddenInfo 同形状，纯数据、可复现）。
## 玩家 seat0 = [K,K,2,10]（下排 2/10 开局可见）；对手 seat1 = [Q,Q,Q,Q]（始终不可见）。

const PLAYER := 0
const OPPONENT := 1
const PLAYER_NAME := "你"
const OPPONENT_NAME := "阿岚"

const CARDS := {
	"p0": ["K", "♠"], "p1": ["K", "♥"], "p2": ["2", "♦"], "p3": ["10", "♣"],
	"p4": ["7", "♠"], "p5": ["9", "♥"],
	"o0": ["Q", "♠"], "o1": ["Q", "♥"], "o2": ["Q", "♦"], "o3": ["Q", "♣"],
	"o4": ["Q", "♠"], "o5": ["2", "♥"], "o6": ["4", "♣"],
	"o7": ["5", "♠"], "o8": ["8", "♦"], "o9": ["9", "♣"],
	"o10": ["2", "♠"], "o11": ["Q", "♥"],
}

const OPPONENT_OPEN := ["o0", "o1", "o2", "o3"]

static func card_by_id(id: String) -> Dictionary:
	if not CARDS.has(id):
		return {}
	var rs: Array = CARDS[id]
	var rank := str(rs[0])
	var d := {"id": id, "rank": rank, "suit": str(rs[1]), "value": KongRules.card_value(rank)}
	d["label"] = KongRules.display_name(d)
	return d

static func opponent_cards() -> Array:
	var out: Array = []
	for id in OPPONENT_OPEN:
		out.append(card_by_id(id))
	return out

static func _slot(id: String, revealed := false) -> Dictionary:
	var s := {"card_id": id, "protected": false, "bomb": false}
	if revealed and not id.is_empty():
		s["card"] = card_by_id(id)
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
		"draw_count": 46,
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

static func _player_after_replace() -> Array:
	return [_slot("p0"), _slot("p1"), _slot("p2"), _slot("p4")]

static func _player_after_slap() -> Array:
	return [_slot("p0"), _slot("p1"), _empty_slot(), _slot("p4")]

static func _opponent_hand() -> Array:
	return [_slot("o0"), _slot("o1"), _slot("o2"), _slot("o3")]

static func _opponent_after_replace() -> Array:
	return [_slot("o0"), _slot("o1"), _slot("o2"), _slot("o4")]

## 对手手里多一张 2（贴牌比赛用）。
static func _opponent_with_two() -> Array:
	return [_slot("o0"), _slot("o1"), _slot("o2"), _slot("o3"), _slot("o10")]

## 对手换出一张 Q 后的手牌：slot2 换成 o11，slot3 仍留一张 Q。
static func _opponent_slap_other() -> Array:
	return [_slot("o0"), _slot("o1"), _slot("o11"), _slot("o3"), _slot("o10"), _slot("o7")]

static func _discard(id: String) -> Dictionary:
	return card_by_id(id)

## 1a) 发牌后全部背面（教学视图再用 reveal_slot_held 翻开下排两张）。
static func state_dealt() -> Dictionary:
	return _state(GameState.Phase.INITIAL_PEEK, _player_hand(), _opponent_hand())

## 1b) 开局下排两张已翻开（用于测试/静态展示）。
static func state_initial() -> Dictionary:
	return _state(GameState.Phase.INITIAL_PEEK,
		[_slot("p0"), _slot("p1"), _slot("p2", true), _slot("p3", true)], _opponent_hand())

## 2) 记忆环节结束：下排盖回。
static func state_memorized() -> Dictionary:
	return _state(GameState.Phase.INITIAL_PEEK, _player_hand(), _opponent_hand())

## 3) 轮到玩家抽牌。
static func state_ready_draw() -> Dictionary:
	return _state(GameState.Phase.TURN_DRAW, _player_hand(), _opponent_hand())

## 4) 抽到 7（等待替换）。
static func state_drawn_7() -> Dictionary:
	var pending := card_by_id("p4")
	pending["source"] = "draw"
	return _state(GameState.Phase.TURN_DECISION, _player_hand(), _opponent_hand(),
		{"draw_count": 45, "pending": pending})

## 5) 玩家把 10 换成 7；旧牌 10 进弃牌堆并开贴牌窗口，轮到对手。
static func state_player_replaced() -> Dictionary:
	return _state(GameState.Phase.TURN_DRAW, _player_after_replace(), _opponent_hand(), {
		"current_player": OPPONENT, "draw_count": 45,
		"discard": _discard("p3"), "discard_count": 1, "discard_history": [_discard("p3")],
		"slap_open": true,
	})

## 6) 对手也换一张（Q 换 Q），弃掉旧 Q；轮到玩家。
static func state_opponent_replaced() -> Dictionary:
	return _state(GameState.Phase.TURN_DRAW, _player_after_replace(), _opponent_after_replace(), {
		"current_player": PLAYER, "draw_count": 44,
		"discard": _discard("o3"), "discard_count": 2,
		"discard_history": [_discard("p3"), _discard("o3")],
		"slap_open": true,
	})

## 7) 玩家抽到 9（不想要）。
static func state_drawn_9() -> Dictionary:
	var pending := card_by_id("p5")
	pending["source"] = "draw"
	return _state(GameState.Phase.TURN_DECISION, _player_after_replace(), _opponent_after_replace(), {
		"current_player": PLAYER, "draw_count": 43, "pending": pending,
		"discard": _discard("o3"), "discard_count": 2,
		"discard_history": [_discard("p3"), _discard("o3")],
	})

## 8) 玩家弃掉 9；轮到对手。
static func state_player_discarded_9() -> Dictionary:
	return _state(GameState.Phase.TURN_DRAW, _player_after_replace(), _opponent_after_replace(), {
		"current_player": OPPONENT, "draw_count": 43,
		"discard": _discard("p5"), "discard_count": 3,
		"discard_history": [_discard("p3"), _discard("o3"), _discard("p5")],
		"slap_open": true,
	})

## 9) 对手抽到 2（他人视角只看到背面）。对手手里还留着一张 2（贴牌比赛用）。
static func state_opponent_drew_2() -> Dictionary:
	return _state(GameState.Phase.TURN_DRAW, _player_after_replace(), _opponent_with_two(), {
		"current_player": OPPONENT, "draw_count": 42,
		"pending": {"card_id": "o5", "source": "draw", "hidden": true},
		"discard": _discard("p5"), "discard_count": 3,
		"discard_history": [_discard("p3"), _discard("o3"), _discard("p5")],
	})

## 10) 对手弃掉一张 2 → 贴牌窗口开启（对手手里还有一张 2）。
static func state_opponent_discarded_2() -> Dictionary:
	return _state(GameState.Phase.TURN_DRAW, _player_after_replace(), _opponent_with_two(), {
		"current_player": OPPONENT, "draw_count": 42,
		"discard": _discard("o5"), "discard_count": 4,
		"discard_history": [_discard("p3"), _discard("o3"), _discard("p5"), _discard("o5")],
		"slap_open": true,
	})

## 11) 玩家赢得贴牌比赛，贴掉自己的 2（对手手里的 2 保留）。
static func state_slap_success() -> Dictionary:
	return _state(GameState.Phase.TURN_DRAW, _player_after_slap(), _opponent_with_two(), {
		"current_player": OPPONENT, "draw_count": 42,
		"discard": _discard("p2"), "discard_count": 5,
		"discard_history": [_discard("p3"), _discard("o3"), _discard("p5"),
			_discard("o5"), _discard("p2")],
	})

## 11b) 贴牌比赛中对手先贴中（临时状态，教程随后重置比赛）。
static func state_race_lost() -> Dictionary:
	var o := _opponent_with_two()
	o[4] = _empty_slot()
	return _state(GameState.Phase.TURN_DRAW, _player_after_replace(), o, {
		"current_player": OPPONENT, "draw_count": 42,
		"discard": _discard("o10"), "discard_count": 5,
		"discard_history": [_discard("p3"), _discard("o3"), _discard("p5"),
			_discard("o5"), _discard("o10")],
		"slap_open": false,
	})

## 12) 对手抽一张 4（背面）。
static func state_opponent_drew_4() -> Dictionary:
	return _state(GameState.Phase.TURN_DRAW, _player_after_slap(), _opponent_with_two(), {
		"current_player": OPPONENT, "draw_count": 41,
		"pending": {"card_id": "o6", "source": "draw", "hidden": true},
		"discard": _discard("p2"), "discard_count": 5,
		"discard_history": [_discard("p3"), _discard("o3"), _discard("p5"),
			_discard("o5"), _discard("p2")],
	})

## 13) 对手弃掉 4，然后（由对手自己）错误贴出自己的 2。
static func state_opponent_discarded_4() -> Dictionary:
	return _state(GameState.Phase.TURN_DRAW, _player_after_slap(), _opponent_with_two(), {
		"current_player": OPPONENT, "draw_count": 41,
		"discard": _discard("o6"), "discard_count": 6,
		"discard_history": [_discard("p3"), _discard("o3"), _discard("p5"),
			_discard("o5"), _discard("p2"), _discard("o6")],
		"slap_open": true,
	})

## 14) 错误贴牌罚 1 张 → 对手 6 张（2 还在手里）。
static func state_opponent_penalty_1() -> Dictionary:
	var hand := _opponent_with_two()
	hand.append(_slot("o7"))
	return _state(GameState.Phase.TURN_DRAW, _player_after_slap(), hand, {
		"current_player": OPPONENT, "draw_count": 41,
		"discard": _discard("o6"), "discard_count": 6,
		"discard_history": [_discard("p3"), _discard("o3"), _discard("p5"),
			_discard("o5"), _discard("p2"), _discard("o6")],
	})

## 15) 对手换一张 Q 出去，右下角还留一张 Q；贴别人牌的窗口开启。
static func state_slap_other_window() -> Dictionary:
	return _state(GameState.Phase.TURN_DRAW, _player_after_slap(), _opponent_slap_other(), {
		"current_player": OPPONENT, "draw_count": 40,
		"discard": _discard("o2"), "discard_count": 7,
		"discard_history": [_discard("p3"), _discard("o3"), _discard("p5"),
			_discard("o5"), _discard("p2"), _discard("o6"), _discard("o2")],
		"slap_open": true,
	})

## 16) 玩家贴中对手右下角的 Q → 进入交牌阶段。
static func state_slap_other_exchange() -> Dictionary:
	var o := _opponent_slap_other()
	o[3] = _empty_slot()
	return _state(GameState.Phase.SLAP_EXCHANGE, _player_after_slap(), o, {
		"current_player": PLAYER, "draw_count": 40,
		"discard": _discard("o3"), "discard_count": 8,
		"discard_history": [_discard("p3"), _discard("o3"), _discard("p5"),
			_discard("o5"), _discard("p2"), _discard("o6"), _discard("o2"), _discard("o3")],
		"slap_exchange": {"actor": PLAYER, "target": OPPONENT, "target_slot": 3, "target_card": "o3"},
	})

## 17) 玩家交出一张自己的牌；对手 6 张、玩家 2 张。
static func state_after_gift(gift_slot := 0) -> Dictionary:
	var p := _player_after_slap()
	var o := _opponent_slap_other()
	var gift_id := ""
	if gift_slot >= 0 and gift_slot < p.size():
		gift_id = str((p[gift_slot] as Dictionary).get("card_id", ""))
		if not gift_id.is_empty():
			p[gift_slot] = _empty_slot()
	o[3] = _slot(gift_id) if not gift_id.is_empty() else _empty_slot()
	return _state(GameState.Phase.TURN_DRAW, p, o, {
		"current_player": OPPONENT, "draw_count": 40,
		"discard": _discard("o3"), "discard_count": 8,
		"discard_history": [_discard("p3"), _discard("o3"), _discard("p5"),
			_discard("o5"), _discard("p2"), _discard("o6"), _discard("o2"), _discard("o3")],
	})

## 18) 对手再贴错一次 → 7 张，立即结算。
static func state_game_over(gift_slot := 0) -> Dictionary:
	var st := state_after_gift(gift_slot).duplicate(true)
	var hand: Array = st.players[1].slots
	hand.append(_slot("o8"))
	var p: Array = st.players[0].slots
	for slot in p:
		if not str(slot.get("card_id", "")).is_empty():
			slot["card"] = card_by_id(str(slot.card_id))
	for slot in hand:
		if not str(slot.get("card_id", "")).is_empty():
			slot["card"] = card_by_id(str(slot.card_id))
	st.players[0] = _player(PLAYER, PLAYER_NAME, p)
	st.players[1] = _player(OPPONENT, OPPONENT_NAME, hand)
	st["phase"] = GameState.Phase.GAME_OVER
	st["current_player"] = PLAYER
	st["slap_open"] = false
	return st

static func result_model(gift_slot := 0) -> Dictionary:
	return SettlementModel.build(state_game_over(gift_slot).players)

static func state_by_id(id: String) -> Dictionary:
	match id:
		"dealt": return state_dealt()
		"initial": return state_initial()
		"memorized": return state_memorized()
		"ready_draw": return state_ready_draw()
		"drawn_7": return state_drawn_7()
		"player_replaced": return state_player_replaced()
		"opponent_replaced": return state_opponent_replaced()
		"drawn_9": return state_drawn_9()
		"player_discarded_9": return state_player_discarded_9()
		"opponent_drew_2": return state_opponent_drew_2()
		"opponent_discarded_2": return state_opponent_discarded_2()
		"slap_success": return state_slap_success()
		"race_lost": return state_race_lost()
		"opponent_drew_4": return state_opponent_drew_4()
		"opponent_discarded_4": return state_opponent_discarded_4()
		"opponent_penalty_1": return state_opponent_penalty_1()
		"slap_other_window": return state_slap_other_window()
		"slap_other_exchange": return state_slap_other_exchange()
	return state_initial()
