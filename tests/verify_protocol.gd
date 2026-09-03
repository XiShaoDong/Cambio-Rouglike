extends Node

## P0-N 协议验证（headless 单进程，直接驱动服务器端逻辑）：
##   godot --headless --path . res://tests/verify_protocol.tscn
## 验证：快照契约字段、revision 递增、拒绝码、action_id 幂等。
## 身份语义：seat_id（host=seat0/peer1，client=seat1/peer2）。
## 拒绝码走 seat0 的本地信号路径收集；跨 peer 拒绝码由 verify_net 双实例覆盖。

var failures := 0
var checks := 0
var seen_rejects: Array[int] = []
var aborted := false
var last_reveal: Dictionary = {}

func _ready() -> void:
	GameState.command_rejected.connect(_on_rejected)
	GameState.match_aborted.connect(_on_aborted)
	GameState.private_reveal_received.connect(_on_reveal)
	GameState._reset_match()
	GameState._add_player(1, "房主")
	run_checks()
	print("=== RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _on_reveal(title: String, cards: Array, target: Dictionary) -> void:
	last_reveal = {"title": title, "cards": cards, "target": target}

func _on_rejected(code: int, _message: String) -> void:
	seen_rejects.append(code)

func _on_aborted(_code: int, _message: String) -> void:
	aborted = true

func _check(name: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[FAIL] " + name)
	else:
		print("[PASS] " + name)

func _rejected(code: int) -> bool:
	return code in seen_rejects

func run_checks() -> void:
	var s: Dictionary = GameState._snapshot_for(0)
	_check("快照含 protocol_version/match_id/state_revision",
		s.has("protocol_version") and s.has("match_id") and s.has("state_revision"))
	_check("快照不含暗牌 rank/suit/value（T20）", not _snapshot_leaks(s))
	_check("空 action_id 放行", GameState._check_action_id(0, ""))
	_check("action_id 首次放行", GameState._check_action_id(0, "dup-1"))
	_check("同一 action_id 第二次被拒", not GameState._check_action_id(0, "dup-1"))
	_check("不同 action_id 放行", GameState._check_action_id(0, "dup-2"))

	seen_rejects.clear()
	GameState._server_start_match(0)
	_check("只有 1 人开局被拒 NOT_ENOUGH_PLAYERS", _rejected(GameState.RejectCode.NOT_ENOUGH_PLAYERS))
	_check("被拒后仍在 LOBBY", GameState.phase == GameState.Phase.LOBBY)

	GameState._add_player(2, "玩家B")
	GameState._server_start_match(0)
	_check("开局后 phase=INITIAL_PEEK", GameState.phase == GameState.Phase.INITIAL_PEEK)
	_check("match_id 已生成", not GameState.match_id.is_empty())
	var rev0 := GameState.state_revision

	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	_check("全员确认后 phase=TURN_DRAW", GameState.phase == GameState.Phase.TURN_DRAW)
	_check("revision 已递增", GameState.state_revision > rev0)

	GameState._server_take(0, "draw", "draw-1")
	var phase_after := GameState.phase
	seen_rejects.clear()
	GameState._server_take(0, "draw", "draw-1")
	_check("重复 action_id 不重复执行", GameState.phase == phase_after)
	_check("重复 action_id 被拒（DUPLICATE 或 INVALID_PHASE）",
		_rejected(GameState.RejectCode.DUPLICATE_OR_EXPIRED_ACTION) or _rejected(GameState.RejectCode.INVALID_PHASE))

	seen_rejects.clear()
	GameState._server_replace(0, 99, "r1")
	_check("越界槽位被拒 INVALID_SLOT", _rejected(GameState.RejectCode.INVALID_SLOT))

	# Peek（7/8）测试：注入 pending 为 7，看自己一张牌应触发 reveal 且 target 正确
	var seven_id := ""
	for cid in GameState.cards:
		if str(GameState.cards[cid].rank) == "7":
			seven_id = cid
			break
	if not seven_id.is_empty():
		GameState.pending_draw = {"card_id": seven_id, "source": "draw"}
		last_reveal = {}
		GameState._server_use_ability(0, {"slot": 0}, "peek-1")
		_check("7/8 看牌触发 private_reveal_received", not last_reveal.is_empty())
		if not last_reveal.is_empty():
			_check("reveal 带 target(player_id/slot)", int(last_reveal.target.get("player_id", 0)) == 0 and last_reveal.target.get("slot", -1) == 0)
			_check("reveal 卡牌是玩家手牌 slot 0 的牌", str(last_reveal.cards[0].get("id", "")) == str(GameState.players[0].cards[0]))
		_check("看牌后进入贴牌窗口(slap_open+TURN_DRAW)", GameState.slap_open and GameState.phase == GameState.Phase.TURN_DRAW)
		_check("看牌后窗口由下一玩家接管", GameState.current_player_id == 1)
		# 窗口内下一玩家可抽牌并关闭窗口
		GameState._server_take(1, "draw", "t-peek")
		_check("窗口内抽牌关闭窗口", not GameState.slap_open and GameState.phase == GameState.Phase.TURN_DECISION)
		# 回到 0 的 TURN_DECISION 供后续测试（重置 pending 为另一张非能力牌）
		for cid in GameState.cards:
			if str(GameState.cards[cid].rank) == "A":
				GameState.pending_draw = {"card_id": cid, "source": "draw"}
				break
		GameState.current_player_id = 0
		GameState.phase = GameState.Phase.TURN_DECISION

	seen_rejects.clear()
	GameState._server_replace(0, 0, "r2")
	_check("合法替换后 slap_open 且 TURN_DRAW", GameState.slap_open and GameState.phase == GameState.Phase.TURN_DRAW)
	_check("替换后当前玩家轮转为 1", GameState.current_player_id == 1)

	# 窗口内贴错 → 罚抽一张牌（需求 3），窗口继续
	var wrong_id := ""
	for cid in GameState.cards:
		if str(GameState.cards[cid].rank) != GameState.slap_rank:
			wrong_id = cid
			break
	if wrong_id != "":
		var before_cards: Array = GameState.players[0].cards.duplicate()
		GameState.players[1].cards[0] = wrong_id
		seen_rejects.clear()
		GameState._server_slap(0, 1, 0, "s-wrong")
		_check("窗口内贴错被接受（未拒 INVALID_PHASE）", not _rejected(GameState.RejectCode.INVALID_PHASE))
		_check("贴错后罚抽一张牌", _count_nonempty(GameState.players[0].cards) > _count_nonempty(before_cards))
		_check("贴错后窗口继续", GameState.slap_open and GameState.phase == GameState.Phase.TURN_DRAW)
		# 不限次数：同一玩家窗口内可再次尝试（不再被 ALREADY_ATTEMPTED_SLAP 拒绝）
		seen_rejects.clear()
		var before2: Array = GameState.players[0].cards.duplicate()
		GameState._server_slap(0, 1, 0, "s-wrong2")
		_check("同一玩家窗口内可再次贴牌（未拒 ALREADY_ATTEMPTED_SLAP）", not _rejected(GameState.RejectCode.ALREADY_ATTEMPTED_SLAP))
		_check("再次贴错再次罚牌", _count_nonempty(GameState.players[0].cards) > _count_nonempty(before2))
		_check("再次贴错窗口仍继续", GameState.slap_open and GameState.phase == GameState.Phase.TURN_DRAW)
	# 复位到 1 的窗口，验证抽牌关窗
	GameState.current_player_id = 1
	GameState.slap_open = true
	GameState.phase = GameState.Phase.TURN_DRAW

	seen_rejects.clear()
	GameState._server_take(1, "draw", "t2")
	_check("窗口内当前玩家抽牌关闭窗口", not GameState.slap_open and GameState.phase == GameState.Phase.TURN_DECISION)

	seen_rejects.clear()
	GameState._server_kongbaya(0, "kb1")
	_check("非 TURN_DRAW 喊 Kongbaya 被拒 INVALID_PHASE",
		_rejected(GameState.RejectCode.INVALID_PHASE))

	var s2: Dictionary = GameState._snapshot_for(0)
	_check("贴牌窗口快照仍不含暗牌", not _snapshot_leaks(s2))

	# 断线（阶段一）：对局中玩家离开 → 标记离线 + 条件暂停，不中止
	GameState._server_slap(0, 0, 0, "s1")
	aborted = false
	GameState._on_peer_left(2)  # seat1 的 peer
	_check("对局中玩家离开不触发 match_aborted", not aborted)
	_check("离开者标记离线", bool(GameState.players[1].get("offline", false)))
	_check("座位仍在 turn_order（等待重连）", GameState.players.size() == 2)
	_check("房主座位保留在线", not bool(GameState.players[0].get("offline", false)))
	# 条件暂停：seat1 非当前玩家（当前应为 0 或 1 视状态），先断言 suspended 计算正确
	_check("suspended 字段存在于快照", GameState._snapshot_for(0).has("suspended"))

func _snapshot_leaks(s: Dictionary) -> bool:
	for player in s.get("players", []):
		for slot in player.get("slots", []):
			if slot.has("card"):
				return true
	return false

func _count_nonempty(cards: Array) -> int:
	var n := 0
	for c in cards:
		if str(c) != "":
			n += 1
	return n
