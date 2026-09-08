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
	_check("初始 currency=10", int(GameState.players[0].get("currency", 0)) == 10)
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
