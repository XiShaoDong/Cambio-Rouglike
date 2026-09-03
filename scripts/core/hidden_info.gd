class_name HiddenInfo
extends RefCounted
## 隐藏信息系统（Feature 13）
## 职责：把服务器完整状态投影成每个玩家看到的快照。
## 服务器保存完整牌堆和手牌；客户端根据接收者身份投影不同状态，
## 未知牌只提供无语义令牌（card_id）和槽位，不泄漏真实卡牌。
## 本类是纯函数工具：不持有状态，输入为 GameState 的当前内部数据。

## 生成某个 viewer（seat_id）视角的快照。
## state: GameState 实例（读取其内部字段）；viewer_id: 该快照的接收者 seat id。
static func snapshot_for(state: Node, viewer_id: int) -> Dictionary:
	var snapshot_players: Array = []
	var phase: int = int(state.phase)
	var turn_order: Array = state.turn_order
	var players: Dictionary = state.players
	for seat in turn_order:
		var reveal_all: bool = phase == GameState.Phase.GAME_OVER
		var peek_slots: Array[int] = []
		if phase == GameState.Phase.INITIAL_PEEK:
			peek_slots = [2, 3]
		snapshot_players.append(_player_snapshot(state, int(seat), reveal_all, viewer_id, peek_slots))
	var current_seat := int(state.current_player_id)
	var snapshot := {
		"protocol_version": state.PROTOCOL_VERSION,
		"match_id": state.match_id,
		"state_revision": state.state_revision,
		"phase": phase,
		"phase_name": _phase_name(phase),
		"viewer_id": viewer_id,
		"current_player": current_seat,
		"current_name": players.get(current_seat, {}).get("name", ""),
		"players": snapshot_players,
		"draw_count": state.deck.size(),
		"discard": public_card(state, str(state.discard_pile.back())) if not state.discard_pile.is_empty() else {},
		"slap_rank": state.slap_rank,
		"slap_open": bool(state.slap_open),
		"slap_duel": _slap_duel_snapshot(state) if phase == GameState.Phase.SLAP_DUEL else {},
		"slap_exchange_actor": int(state.slap_exchange.get("actor", 0)),
		"suspended": _suspended(state),
		"offline_players": _offline_players(state),
		"kong_caller": state.kong_caller,
		"match_number": state.match_number,
		"ready_count": state.initial_confirmed.size() if phase == GameState.Phase.INITIAL_PEEK else 0,
		"event_log": state.event_log.duplicate(),
		"result": state.last_result.duplicate(),
		"run": state.run_state.duplicate(),
	}
	if (phase == GameState.Phase.TURN_DECISION or phase == GameState.Phase.Q_DECISION) and not state.pending_draw.is_empty():
		if viewer_id == current_seat:
			var pending: Dictionary = public_card(state, str(state.pending_draw.card_id))
			pending["source"] = str(state.pending_draw.get("source", "draw"))
			snapshot["pending"] = pending
		else:
			# 其他玩家：只看到一张背面大牌（仅无语义令牌，不泄漏牌面）
			snapshot["pending"] = {"card_id": str(state.pending_draw.card_id), "hidden": true}
	return snapshot

## 条件暂停：INITIAL_PEEK 需全员 ready（任一离线即暂停）；其余阶段仅当前行动者离线时暂停。
static func _suspended(state: Node) -> bool:
	if int(state.phase) == GameState.Phase.INITIAL_PEEK:
		for seat in state.turn_order:
			if bool(state.players[seat].get("offline", false)):
				return true
		return false
	var cp := int(state.current_player_id)
	return state.players.has(cp) and bool(state.players[cp].get("offline", false))

## 离线座位列表（seat_id）。
static func _offline_players(state: Node) -> Array:
	var arr: Array = []
	for seat in state.turn_order:
		if bool(state.players[seat].get("offline", false)):
			arr.append(int(seat))
	return arr

## 贴牌比拼快照：候选人、扫动时长、服务器截止时刻、目标位置（公开）。
static func _slap_duel_snapshot(state: Node) -> Dictionary:
	var duel: Dictionary = state.slap_duel
	return {
		"contestants": duel.get("correct", {}).keys(),
		"duration_ms": int(duel.get("duration_ms", 0)),
		"deadline_server_ms": int(duel.get("start_ms", 0)) + int(duel.get("duration_ms", 0)),
		"target": float(duel.get("target", 0.5)),
	}

## 单玩家投影：玩家自己的牌按 peek_slots 揭示；他人牌只给令牌。
## seat: 被投影玩家的 seat_id；viewer_id: 接收者 seat_id。槽位固定为 HAND_SIZE（初始布局），缺失槽位为空；超出部分横向追加。
static func _player_snapshot(state: Node, seat: int, reveal_all: bool, viewer_id: int, peek_slots: Array[int]) -> Dictionary:
	var player: Dictionary = state.players[seat]
	var slot_count: int = maxi(KongRules.HAND_SIZE, player.cards.size())
	var slots: Array = []
	for index in slot_count:
		var slot := {"card_id": ""}
		if index < player.cards.size():
			var card_id: String = player.cards[index]
			if not card_id.is_empty():
				slot["card_id"] = card_id
				if reveal_all or (seat == viewer_id and peek_slots.has(index)):
					slot["card"] = public_card(state, card_id)
		slots.append(slot)
	return {"id": seat, "name": player.name, "count": player.cards.size(), "health": player.health,
		"ready": state.initial_confirmed.has(seat), "slots": slots}

## 卡牌公共表示（不含身份敏感信息之外的内容，仅用于展示/能力提示）。
static func public_card(state: Node, card_id: String) -> Dictionary:
	var card: Dictionary = state.cards[card_id]
	return {"id": card.id, "rank": card.rank, "suit": card.suit, "value": card.value, "label": KongRules.display_name(card)}

static func _phase_name(phase: int) -> String:
	match phase:
		GameState.Phase.LOBBY: return "大厅"
		GameState.Phase.INITIAL_PEEK: return "开局记忆"
		GameState.Phase.TURN_DRAW: return "抽牌"
		GameState.Phase.TURN_DECISION: return "处理抽到的牌"
		GameState.Phase.Q_DECISION: return "Q：决定交换"
		GameState.Phase.SLAP_WINDOW: return "贴牌抢答"
		GameState.Phase.SLAP_EXCHANGE: return "贴中他人：交出一张牌"
		GameState.Phase.SLAP_DUEL: return "贴牌比拼"
		GameState.Phase.GAME_OVER: return "结算"
	return ""
