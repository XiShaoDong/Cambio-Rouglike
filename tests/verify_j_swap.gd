extends Node
## headless 单元测试：J（盲换）改为与 Q 同款的"选两张 → 交换/不交换"确认流程。
## 关键：选齐两张后**不自动发起交换**，出现「J：交换」「J：不交换」，交换仅在两选齐时可用。

var failures := 0
var checks := 0
var main_node: Node

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main_node = scene.instantiate()
	add_child(main_node)
	await get_tree().process_frame
	await get_tree().process_frame
	_run()
	print("=== J SWAP RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _state() -> Dictionary:
	return {
		"phase": 3, "phase_name": "p", "viewer_id": 0, "current_player": 0, "current_name": "A",
		"players": [
			{"id": 0, "name": "A", "slots": [{}, {}, {}, {}], "health": 2, "currency": 100, "count": 4, "eliminated": false},
			{"id": 1, "name": "B", "slots": [{}, {}, {}, {}], "health": 2, "currency": 100, "count": 4, "eliminated": false},
		],
		"draw_count": 40, "discard": {}, "pending": {"rank": "J", "source": "draw"},
		"event_log": [], "match_number": 1, "slap_rank": "", "slap_open": false,
		"slap_exchange_actor": 0, "kong_caller": -1, "ready_count": 0, "result": {}, "run": {},
		"q_decision": {},
	}

func _run() -> void:
	main_node.latest_state = _state()
	# 用能力：进入选牌（jack_target）
	main_node.interaction.begin_ability()
	_check("J 用能力后进入 jack_target", main_node.interaction.action_mode == "jack_target")
	var acts0 := ActionModel.conditional_actions(main_node.latest_state, main_node._interaction_ctx())
	_check("用能力即出现交换/不交换", acts0.size() == 2)
	_check("未选牌时交换禁用", not bool(_find(acts0, ActionModel.J_EXCHANGE).get("enabled", true)))
	_check("hint 提示选择（jack_target）", "J" in main_node._hint_for(3, true))

	# 选对方牌 → jack_own
	main_node.interaction.on_card_pressed(1, 0)
	_check("选对方牌后进入 jack_own", main_node.interaction.action_mode == "jack_own")

	# 选自己牌 → jack_ready（不自动交换）
	main_node.interaction.on_card_pressed(0, 1)
	_check("选自己牌后进入 jack_ready", main_node.interaction.action_mode == "jack_ready")
	_check("未自动交换（action_mode 未重置）", main_node.interaction.action_mode == "jack_ready")
	var ctx: Dictionary = main_node._interaction_ctx()
	_check("记录对方牌槽", int(ctx.get("selected_their_slot", -1)) == 0)
	_check("记录自己牌槽", int(ctx.get("selected_own_slot", -1)) == 1)
	var acts1 := ActionModel.conditional_actions(main_node.latest_state, ctx)
	_check("两张已选后交换启用", bool(_find(acts1, ActionModel.J_EXCHANGE).get("enabled", false)))
	_check("hint 提示已选两张", "J" in main_node._hint_for(3, true))

func _find(acts: Array, action: String) -> Dictionary:
	for a in acts:
		if str(a.get("action", "")) == action:
			return a
	return {}
