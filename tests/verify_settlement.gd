extends Node
## headless 单元测试：结算模型（同步轮记分）

var failures := 0
var checks := 0
var _rejections := 0

func _ready() -> void:
	await _test_model_even()
	await _test_model_uneven()
	await _test_model_final_matches_score_system()
	await _test_next_match()
	var status: String = " (FAILURES!)" if failures > 0 else ""
	print("=== SETTLEMENT RESULT: %d/%d passed%s ===" % [checks - failures, checks, status])
	get_tree().quit(1 if failures > 0 else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _players_even() -> Array:
	return [
		{"id": 0, "name": "A", "count": 2, "slots": [
			{"card_id": "a0", "card": {"rank": "7", "suit": "♠", "value": 7, "label": "7♠"}},
			{"card_id": "a1", "card": {"rank": "7", "suit": "♥", "value": 7, "label": "7♥"}}]},
		{"id": 1, "name": "B", "count": 2, "slots": [
			{"card_id": "b0", "card": {"rank": "2", "suit": "♠", "value": 2, "label": "2♠"}},
			{"card_id": "b1", "card": {"rank": "10", "suit": "♠", "value": 10, "label": "10♠"}}]},
		{"id": 2, "name": "C", "count": 2, "slots": [
			{"card_id": "c0", "card": {"rank": "5", "suit": "♠", "value": 5, "label": "5♠"}},
			{"card_id": "c1", "card": {"rank": "K", "suit": "♠", "value": -1, "label": "K♠"}}]},
	]

func _test_model_even() -> void:
	var model: Dictionary = SettlementModel.build(_players_even())
	_check("layout_order=座位顺序[0,1,2]", model.layout_order == [0, 1, 2])
	_check("轮数=最大手牌数=2", model.rounds.size() == 2)
	var r0: Dictionary = model.rounds[0]
	_check("第0轮 flips 顺序=玩家数组顺序", r0.flips[0].seat == 0 and r0.flips[1].seat == 1 and r0.flips[2].seat == 2)
	_check("第0轮每人 total=自身值", r0.flips[0].total == 7 and r0.flips[1].total == 2 and r0.flips[2].total == 5)
	_check("第0轮排名按累计分升序 B,C,A", [r0.ranking[0].id, r0.ranking[1].id, r0.ranking[2].id] == [1, 2, 0])
	var r1: Dictionary = model.rounds[1]
	_check("第1轮累计 A=14 B=12 C=4", r1.flips[0].total == 14 and r1.flips[1].total == 12 and r1.flips[2].total == 4)
	_check("第1轮排名 C,B,A", [r1.ranking[0].id, r1.ranking[1].id, r1.ranking[2].id] == [2, 1, 0])
	_check("冠军=最低分 C", r1.ranking[0].id == 2)

func _players_uneven() -> Array:
	return [
		{"id": 0, "name": "A", "count": 2, "slots": [
			{"card_id": "a0", "card": {"rank": "A", "suit": "♠", "value": 1, "label": "A♠"}},
			{"card_id": "a1", "card": {"rank": "2", "suit": "♥", "value": 2, "label": "2♥"}}]},
		{"id": 1, "name": "B", "count": 1, "slots": [
			{"card_id": "b0", "card": {"rank": "A", "suit": "♣", "value": 1, "label": "A♣"}}]},
		{"id": 2, "name": "C", "count": 3, "slots": [
			{"card_id": "c0", "card": {"rank": "3", "suit": "♠", "value": 3, "label": "3♠"}},
			{"card_id": "c1", "card": {"rank": "4", "suit": "♠", "value": 4, "label": "4♠"}},
			{"card_id": "c2", "card": {"rank": "5", "suit": "♠", "value": 5, "label": "5♠"}}]},
	]

func _test_model_uneven() -> void:
	var model: Dictionary = SettlementModel.build(_players_uneven())
	_check("轮数=最大手牌数=3", model.rounds.size() == 3)
	_check("第1轮只有 A,C 翻牌（B 无第2张）", model.rounds[1].flips.size() == 2)
	_check("第2轮只有 C 翻牌", model.rounds[2].flips.size() == 1 and model.rounds[2].flips[0].seat == 2)
	_check("B 无牌轮总分保持不变", model.rounds[1].flips[0].total == 3 and model.rounds[1].flips[1].total == 7)
	_check("未翻牌玩家 total 不回退（B=1）", model.rounds[2].flips[0].total == 12)

func _test_model_final_matches_score_system() -> void:
	var players: Array = _players_even()
	var model: Dictionary = SettlementModel.build(players)
	var final_ranking: Array = model.rounds[model.rounds.size() - 1].ranking
	var full: Array = []
	for player in players:
		var values: Array[int] = []
		for slot in player.slots:
			if slot.has("card"):
				values.append(int(slot.card.value))
		values.sort()
		var total := 0
		for v in values:
			total += v
		full.append({"id": int(player.id), "name": str(player.name), "score": total, "count": values.size(), "values": values})
	full.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return ScoreSystem._is_lower_score(a, b))
	var ids_full: Array = []
	for entry in full:
		ids_full.append(int(entry.id))
	var ids_final: Array = []
	for entry in final_ranking:
		ids_final.append(int(entry.id))
	_check("最终排名与 ScoreSystem 全量一致", ids_final == ids_full)

func _test_next_match() -> void:
	GameState.command_rejected.connect(func(_code: int, _msg: String) -> void: _rejections += 1)

	_rejections = 0
	_open()
	GameState._server_next_match(0, "nm-1")
	_check("非 GAME_OVER 拒绝", GameState.phase == GameState.Phase.TURN_DRAW and _rejections == 1)

	GameState._finish_game()
	_check("已进入 GAME_OVER", GameState.phase == GameState.Phase.GAME_OVER)
	var before_number: int = GameState.match_number
	GameState._server_next_match(0, "nm-2")
	_check("match_number 递增", GameState.match_number == before_number + 1)
	_check("回 INITIAL_PEEK", GameState.phase == GameState.Phase.INITIAL_PEEK)
	_check("手牌重发每人 HAND_SIZE 张", GameState.players[0].cards.size() == KongRules.HAND_SIZE and GameState.players[1].cards.size() == KongRules.HAND_SIZE and GameState.players[2].cards.size() == KongRules.HAND_SIZE)
	_check("initial_confirmed 清空", GameState.initial_confirmed.is_empty())

	GameState._finish_game()
	var before_phase: int = GameState.phase
	var before_number2: int = GameState.match_number
	GameState._server_next_match(1, "nm-3")
	_check("非房主拒绝（阶段与局数不变）", GameState.phase == before_phase and GameState.match_number == before_number2)

func _open() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)