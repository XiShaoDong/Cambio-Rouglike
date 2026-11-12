extends Node
## headless：取自弃牌堆的待处理牌可以再次弃掉；牌面能力仍被禁止。

var failures := 0
var checks := 0
var rejects: Array[int] = []

func _ready() -> void:
	GameState.turn_effect_rules_enabled = false
	GameState.command_rejected.connect(func(code: int, _msg: String) -> void: rejects.append(code))
	_run()
	print("=== DISCARD TAKE DISCARD RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _open() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)

func _run() -> void:
	_open()
	_check("开局当前玩家=0", GameState.current_player_id == 0 and GameState.phase == GameState.Phase.TURN_DRAW)
	var cid := GameState._draw_from_deck()
	GameState._push_discard(cid)
	GameState.slap_rank = str(GameState.cards[cid].rank)
	var before := GameState.discard_pile.size()
	rejects.clear()
	GameState._server_take(0, "discard", "dt-1")
	_check("取弃牌顶进入 TURN_DECISION", GameState.phase == GameState.Phase.TURN_DECISION)
	_check("pending.source=discard", str(GameState.pending_draw.get("source", "")) == "discard")
	_check("取走后弃牌堆少一张", GameState.discard_pile.size() == before - 1)
	rejects.clear()
	GameState._server_discard_draw(0, "dt-2")
	_check("取弃牌顶后可弃掉", rejects.is_empty() and GameState.pending_draw.is_empty())
	_check("弃掉的牌回到弃牌顶", GameState.discard_pile.size() == before \
		and str(GameState.discard_pile[GameState.discard_pile.size() - 1]) == cid)
	_check("弃牌后开贴牌窗口并换人", GameState.slap_open and GameState.current_player_id == 1)

	# 牌面能力仍被禁止（7/8/9/10/Q 等）
	var seven := ""
	for card_id in GameState.cards:
		if str(GameState.cards[card_id].rank) == "7":
			seven = card_id
			break
	if not seven.is_empty():
		GameState.pending_draw = {"card_id": seven, "source": "discard"}
		GameState.current_player_id = 0
		GameState.phase = GameState.Phase.TURN_DECISION
		rejects.clear()
		GameState._server_use_ability(0, {"slot": 0}, "dt-3")
		_check("弃牌来源仍不能发动牌面能力", GameState.RejectCode.ABILITY_FORBIDDEN in rejects)
