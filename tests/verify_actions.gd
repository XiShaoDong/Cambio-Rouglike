extends Node
## headless 单元测试：ActionModel（2D/3D 共用的动作与可用性判定）。

var failures := 0
var checks := 0

func _ready() -> void:
	_run()
	print("=== ACTIONS RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	var q_ready := {"phase": 4, "viewer_id": 0, "current_player": 0, "q_decision": {"own_viewed": true}}
	var q_acts := ActionModel.conditional_actions(q_ready)
	_check("Q 两按钮", q_acts.size() == 2 and q_acts[0].action == ActionModel.Q_KEEP and q_acts[1].action == ActionModel.Q_EXCHANGE)
	_check("Q 未看自己牌无按钮", ActionModel.conditional_actions({"phase": 4, "viewer_id": 0, "current_player": 0, "q_decision": {"own_viewed": false}}).is_empty())
	_check("非当前玩家无动作", ActionModel.conditional_actions({"phase": 4, "viewer_id": 1, "current_player": 0, "q_decision": {"own_viewed": true}}).is_empty())
	var j_state := {"phase": 3, "viewer_id": 1, "current_player": 1, "pending": {"rank": "JOKER"}, "run": {"relics": {Relics.JOKER_TRANSFORM_ID: 1}}}
	var j_acts := ActionModel.conditional_actions(j_state)
	_check("Joker 变换按钮", j_acts.size() == 1 and j_acts[0].action == ActionModel.JOKER)
	_check("无遗物无 Joker 按钮", ActionModel.conditional_actions({"phase": 3, "viewer_id": 1, "current_player": 1, "pending": {"rank": "JOKER"}, "run": {"relics": {}}}).is_empty())
	_check("非 JOKER pending 无按钮", ActionModel.conditional_actions({"phase": 3, "viewer_id": 1, "current_player": 1, "pending": {"rank": "7"}, "run": {"relics": {Relics.JOKER_TRANSFORM_ID: 1}}}).is_empty())
	_check("空快照无动作", ActionModel.conditional_actions({}).is_empty())
	_check("kongbaya 可用", ActionModel.kongbaya_available({"phase": 2, "viewer_id": 0, "current_player": 0}))
	_check("kongbaya 非当前不可用", not ActionModel.kongbaya_available({"phase": 2, "viewer_id": 1, "current_player": 0}))
	_check("kongbaya 非抽牌阶段不可用", not ActionModel.kongbaya_available({"phase": 3, "viewer_id": 0, "current_player": 0}))
	_check("空快照 kongbaya 不可用", not ActionModel.kongbaya_available({}))
	var r := {"ready_count": 1, "players": [{}, {}]}
	_check("Ready 文案", ActionModel.ready_text(r, false) == "Ready（1/2）")
	_check("已准备文案", ActionModel.ready_text(r, true) == "已准备（1/2）")
	_check("Ready 可用", ActionModel.ready_enabled(r, false))
	_check("点击后不可用", not ActionModel.ready_enabled(r, true))
	_check("全员 ready 不可用", not ActionModel.ready_enabled({"ready_count": 2, "players": [{}, {}]}, false))
	# 弃牌堆可用性（取弃牌顶 / 弃大牌）
	var take := {"phase": 2, "viewer_id": 0, "current_player": 0, "discard": {"rank": "7", "suit": "♣"}}
	_check("取弃牌顶可用", ActionModel.discard_take_available(take))
	_check("弃牌堆空不可取", not ActionModel.discard_take_available({"phase": 2, "viewer_id": 0, "current_player": 0, "discard": {}}))
	_check("非当前不可取弃牌顶", not ActionModel.discard_take_available({"phase": 2, "viewer_id": 1, "current_player": 0, "discard": {"rank": "7", "suit": "♣"}}))
	_check("非抽牌阶段不可取", not ActionModel.discard_take_available({"phase": 3, "viewer_id": 0, "current_player": 0, "discard": {"rank": "7", "suit": "♣"}}))
	var pend := {"phase": 3, "viewer_id": 0, "current_player": 0, "pending": {"rank": "7", "source": "draw"}}
	_check("弃大牌可用", ActionModel.pending_discard_available(pend))
	_check("取自弃牌堆的 pending 不可弃", not ActionModel.pending_discard_available({"phase": 3, "viewer_id": 0, "current_player": 0, "pending": {"rank": "7", "source": "discard"}}))
	_check("非当前不可弃大牌", not ActionModel.pending_discard_available({"phase": 3, "viewer_id": 1, "current_player": 0, "pending": {"rank": "7", "source": "draw"}}))
	_check("无 pending 不可弃", not ActionModel.pending_discard_available({"phase": 3, "viewer_id": 0, "current_player": 0, "pending": {}}))
	_check("弃牌堆 actionable 合并", ActionModel.discard_pile_actionable(take) and ActionModel.discard_pile_actionable(pend))
	_check("空快照弃牌堆不可点", not ActionModel.discard_pile_actionable({}))
