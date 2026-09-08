extends Node
## headless 单元测试：系列赛框架（Milestone 1）

var failures := 0
var checks := 0
var _rejections := 0

func _ready() -> void:
	await _test_match_limit()
	await _test_lifecycle()
	await _test_series_end()
	await _test_ranking()
	await _test_guard()
	await _test_elimination()
	await _test_spectator_snapshot()
	await _test_over_hand_ranking()
	await _test_settlement_model_excludes_eliminated()
	await _test_dev_eliminate()
	await _test_auto_advance()
	await _test_next_match_guard()
	await _test_page_series()
	var status: String = " (FAILURES!)" if failures > 0 else ""
	print("=== SERIES RESULT: %d/%d passed%s ===" % [checks - failures, checks, status])
	get_tree().quit(1 if failures > 0 else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _open(limit := 0) -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0, limit)

func _test_match_limit() -> void:
	_rejections = 0
	_open(3)
	_check("start_match 设定局数=3", int(GameState.run_state.get("match_limit", 0)) == 3)
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(0, 99)
	_check("局数超上限被夹到10", int(GameState.run_state.get("match_limit", 0)) == 10)
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(0, 1)
	_check("局数低于下限回退默认5", int(GameState.run_state.get("match_limit", 0)) == 5)
	GameState._server_start_match(1, 7)
	_check("非房主拒绝(状态不变)", GameState.phase == GameState.Phase.INITIAL_PEEK and int(GameState.run_state.get("match_limit", 0)) == 5)

func _test_lifecycle() -> void:
	GameState.command_rejected.connect(func(_c: int, _m: String) -> void: _rejections += 1)
	_rejections = 0
	_open()
	_check("默认 match_limit=5", int(GameState.run_state.get("match_limit", 0)) == 5)
	_check("初始 currency=100", int(GameState.players[0].get("currency", 0)) == KongRules.START_CURRENCY)
	_check("初始 wins=0", int(GameState.players[0].get("wins", -1)) == 0)
	_check("三人生存计数=3", GameState._alive_count() == 3)
	GameState.players[2].health = 0
	_check("淘汰后存活计数=2", GameState._alive_count() == 2)
	_check("淘汰者不在存活序", GameState._alive_order() == [0, 1])

func _test_series_end() -> void:
	_rejections = 0
	_open(2)  # 局数下限=2；把 match_number 推到把末局（2/2）再结算 → 一局即把末
	GameState.match_number = 2
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._finish_game()
	_check("赛满局数后 _series_finished", GameState._series_finished())
	_check("把末 last_result.series.finished", bool(GameState.last_result.get("series", {}).get("finished", false)))
	var series: Dictionary = GameState.last_result.get("series", {})
	_check("把末 series.ranking 含 3 人", (series.get("ranking", []) as Array).size() == 3)

func _test_ranking() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState.players[0].wins = 2
	GameState.players[0].currency = 5
	GameState.players[1].wins = 3
	GameState.players[1].currency = 9
	GameState.players[2].wins = 3
	GameState.players[2].currency = 7
	var r: Array = SeriesRanking.final_ranking(GameState.players, GameState.turn_order)
	_check("排名按胜场降序、同胜场按货币降序", [int(r[0].id), int(r[1].id), int(r[2].id)] == [1, 2, 0])
	GameState.players[2].health = 0
	r = SeriesRanking.final_ranking(GameState.players, GameState.turn_order)
	_check("淘汰者不入总排名", r.size() == 2 and int(r[0].id) != 2 and int(r[1].id) != 2)

func _test_guard() -> void:
	_rejections = 0
	_open()
	GameState.players[0].health = 0
	_check("guard 拦截观战者", GameState._guard_spectator(0, "g-0"))
	_check("guard 放行存活者", not GameState._guard_spectator(1, "g-1"))
	_check("SPECTATOR 拒绝已发", _rejections == 1)

func _test_elimination() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState.players[2].health = 0
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	_check("存活者就绪即进入押注阶段", GameState.phase == GameState.Phase.BET)
	_check("淘汰者未被发牌", GameState.players[2].cards.is_empty())
	_check("存活者各发4张", GameState.players[0].cards.size() == KongRules.HAND_SIZE and GameState.players[1].cards.size() == KongRules.HAND_SIZE)
	GameState._server_bet(0, KongRules.MIN_BET)
	GameState._server_bet(1, KongRules.MIN_BET)
	_check("存活者押注后进入抽牌", GameState.phase == GameState.Phase.TURN_DRAW)
	var d: Dictionary = TurnSystem.decide(GameState._alive_order(), 0, -1, [])
	_check("回合跳过淘汰者 0->1", int(d.next_player) == 1)

func _test_spectator_snapshot() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState.players[2].health = 0
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	var snap: Dictionary = GameState._snapshot_for(2)
	var leak := false
	for p in snap.players:
		for s in p.slots:
			if (s as Dictionary).has("card"):
				leak = true
	_check("观战快照无任何暗牌面", not leak)
	_check("观战者本人 eliminated 标记", bool(snap.players[2].get("eliminated", false)))

## 回归：超限结算（R-07）不得把出局玩家算进排名（0 张 0 分恒第一）。
func _test_over_hand_ranking() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState.players[2].health = 0
	GameState._server_start_match(0)
	for _i in 3:
		GameState.players[0].cards.append(GameState._draw_from_deck())
	GameState._finish_game_over_hand(0)
	var ranking: Array = GameState.last_result.ranking
	_check("超限结算排除出局者", ranking.size() == 1 and int(ranking[0].id) != 2)
	_check("超限结算仅剩存活者参与", int(ranking[0].id) == 1)

## 回归：结算模型只纳入存活者（main._open_settlement 的过滤同款逻辑）。
func _test_settlement_model_excludes_eliminated() -> void:
	var players: Array = [
		{"id": 0, "name": "A", "count": 2, "eliminated": false, "slots": [
			{"card_id": "a0", "card": {"rank": "7", "suit": "♠", "value": 7, "label": "7♠"}},
			{"card_id": "a1", "card": {"rank": "2", "suit": "♥", "value": 2, "label": "2♥"}}]},
		{"id": 2, "name": "C", "count": 0, "eliminated": true, "slots": []},
	]
	var alive: Array = players.filter(func(p: Dictionary) -> bool: return not bool(p.get("eliminated", false)))
	var model: Dictionary = SettlementModel.build(alive)
	_check("结算模型排除出局者", model.layout_order == [0])

## 开发者工具：房主直接判玩家出局；非房主被拒；出局当前行动者自动推进回合。
func _test_dev_eliminate() -> void:
	_rejections = 0
	_open()
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._server_dev_eliminate(1, 2)
	_check("非房主开发者出局被拒(状态不变)", GameState._is_alive(2))
	GameState._server_dev_eliminate(0, 0)
	_check("出局当前行动者后回合推进跳过", GameState.phase == GameState.Phase.TURN_DRAW and GameState.current_player_id == 1)
	GameState._server_dev_eliminate(0, 2)
	_check("房主开发者出局生效", not GameState._is_alive(2))
	_check("出局者手牌保留", GameState.players[2].cards.size() == KongRules.HAND_SIZE)

func _test_auto_advance() -> void:
	_open(5)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._finish_game()
	_check("非把末启动自动衔接 Timer", not GameState.series_timer.is_stopped())
	GameState._on_series_auto_advance()
	_check("自动开下一局 match_number 递增", GameState.match_number == 2)
	_check("回 INITIAL_PEEK", GameState.phase == GameState.Phase.INITIAL_PEEK)
	GameState._finish_game()
	GameState._server_next_match(0, "nm-ok")
	_check("未把末仍可手动 next", GameState.phase == GameState.Phase.INITIAL_PEEK)

func _test_next_match_guard() -> void:
	_rejections = 0
	_open(2)
	GameState.match_number = 2  # 把末局 2/2（match_limit 下限 2 起，不能 _open(1)）
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._finish_game()
	_check("把末 Timer 不启动", GameState.series_timer.is_stopped())
	GameState._server_next_match(0, "nm-x")
	_check("把末 next_match 被拒", _rejections == 1 and GameState.phase == GameState.Phase.GAME_OVER)

func _test_page_series() -> void:
	await get_tree().process_frame
	var model: Dictionary = SettlementModel.build([
		{"id": 0, "name": "A", "count": 2, "slots": [
			{"card_id": "a0", "card": {"rank": "7", "suit": "♠", "value": 7, "label": "7♠"}},
			{"card_id": "a1", "card": {"rank": "2", "suit": "♥", "value": 2, "label": "2♥"}}]},
		{"id": 1, "name": "B", "count": 2, "slots": [
			{"card_id": "b0", "card": {"rank": "3", "suit": "♠", "value": 3, "label": "3♠"}},
			{"card_id": "b1", "card": {"rank": "4", "suit": "♥", "value": 4, "label": "4♥"}}]},
	])
	var series: Dictionary = {"finished": true, "ranking": [
		{"id": 1, "name": "B", "wins": 3, "currency": 9},
		{"id": 0, "name": "A", "wins": 2, "currency": 5}]}
	var page: Control = preload("res://scenes/ui/settlement_page.tscn").instantiate()
	get_tree().root.add_child(page)
	page.setup(model, true, 3, Callable(), Callable(), Callable(), Callable(), false, 5, series)
	await get_tree().process_frame
	_check("结算页标题带局数X", page._title.text == "结算 · 第 3 / 5 局")
	page._show_series_summary(series)
	_check("把末总榜已显示", page.get_node("Center/Panel/VBox/SeriesBox").visible)
	var rows: VBoxContainer = page.get_node("Center/Panel/VBox/SeriesBox/SeriesRows")
	_check("总榜行数=排名数", rows.get_child_count() == 2)
	page.queue_free()
