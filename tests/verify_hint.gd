extends Node
var main_node: Node
var failures := 0
var checks := 0

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main_node = scene.instantiate()
	add_child(main_node)
	await get_tree().process_frame
	await get_tree().process_frame
	await _run()
	print("=== HINT RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[FAIL] " + name)
	else:
		print("[PASS] " + name)

func _set_state(phase: int, is_current: bool, pending: Dictionary = {}, mode: String = "") -> void:
	main_node.latest_state = {"phase": phase, "phase_name": "p", "viewer_id": 1, "current_player": 1 if is_current else 2, "current_name": "Bob", "players": [], "discard": {}, "event_log": [], "match_number": 1, "draw_count": 40, "slap_rank": "", "slap_seconds": 0.0, "slap_exchange_actor": 0, "kong_caller": 0, "ready_count": 0, "result": {}, "run": {}}
	if not pending.is_empty():
		main_node.latest_state["pending"] = pending
	main_node.interaction.action_mode = mode

func _run() -> void:
	_set_state(3, true, {"rank": "7", "source": "draw"}, "replace")
	var h1: String = main_node._hint_for(3, true)
	_check("current 7/8 replace hint 非空", not h1.is_empty())
	_check("current 7/8 replace 含 replace", "replace" in h1)
	_set_state(3, false, {"rank": "7", "source": "draw"}, "")
	var h2: String = main_node._hint_for(3, false)
	_check("other 7/8 hint 非空", not h2.is_empty())
	_check("other hint 含 Bob", "Bob" in h2)
	_set_state(3, true, {"rank": "J", "source": "draw"}, "peek_own")
	var h3: String = main_node._hint_for(3, true)
	_check("J mode hint 非空", not h3.is_empty())
	_set_state(3, true, {"rank": "9", "source": "draw"}, "")
	var h4: String = main_node._hint_for(3, true)
	_check("9/10 初始 hint 非空", not h4.is_empty())
	# 验证设到 center_hint
	main_node.game_view.render(main_node.latest_state)
	await get_tree().process_frame
	_check("center_hint 文本非空", not main_node.center_hint.text.is_empty())
	_check("center_hint 文本已设", main_node.center_hint.text == h4)
