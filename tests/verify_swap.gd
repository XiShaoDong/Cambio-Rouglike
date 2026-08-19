extends Node
## 交换动画 headless 验证

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
	print("=== SWAP RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[FAIL] " + name)
	else:
		print("[PASS] " + name)

func _run() -> void:
	var gv = main_node.game_view
	var anim = main_node.animator
	var players := [
		{"id": 1, "name": "A", "slots": [
			{"card_id": "c1", "card": {"rank": "7", "suit": "♥", "value": 7}},
			{"card_id": "c2", "card": {"rank": "8", "suit": "♠", "value": 8}},
		]},
		{"id": 2, "name": "B", "slots": [
			{"card_id": "c3", "card": {"rank": "9", "suit": "♦", "value": 9}},
			{"card_id": "c4", "card": {"rank": "K", "suit": "♣", "value": 13}},
		]},
	]
	main_node.latest_state = {"phase": 3, "phase_name": "处理抽到的牌", "viewer_id": 1, "current_player": 1, "current_name": "A", "players": players, "discard": {}, "event_log": [], "match_number": 1, "draw_count": 40, "slap_rank": "", "slap_seconds": 0.0, "slap_exchange_actor": 0, "kong_caller": 0, "ready_count": 0, "result": {}, "run": {}}
	gv._render_players(1)
	await get_tree().process_frame
	anim.animate_swap(1, 0, 2, 1, {"rank": "7", "suit": "♥", "value": 7}, {"rank": "K", "suit": "♣", "value": 13})
	_check("交换标记 A slot0", main_node.is_anim_slot(1, 0))
	_check("交换标记 B slot1", main_node.is_anim_slot(2, 1))
	await get_tree().create_timer(2.0).timeout
	_check("A slot0 标记已清除", not main_node.is_anim_slot(1, 0))
	_check("B slot1 标记已清除", not main_node.is_anim_slot(2, 1))
	main_node._render_game()
	await get_tree().process_frame
	var slot_a = main_node._card_slots.get(1, {}).get(0, null)
	var slot_b = main_node._card_slots.get(2, {}).get(1, null)
	_check("A slot0 是卡牌(CardView)", slot_a is CardView)
	_check("B slot1 是卡牌(CardView)", slot_b is CardView)

	# replace 测试：A slot1 与抽牌堆大牌交换
	main_node.latest_state.pending = {"rank": "10", "suit": "♠", "value": 10, "source": "draw"}
	main_node._render_game()
	await get_tree().process_frame
	anim.animate_replace(1, 1, {"rank": "8", "suit": "♠", "value": 8}, {"rank": "10", "suit": "♠", "value": 10})
	_check("replace 标记 A slot1", main_node.is_anim_slot(1, 1))
	await get_tree().create_timer(2.0).timeout
	_check("replace 后 A slot1 标记已清除", not main_node.is_anim_slot(1, 1))
	_check("replace 后弃牌堆锁已清除", not main_node._discard_anim_lock)
	main_node._render_game()
	await get_tree().process_frame
	var slot_rep = main_node._card_slots.get(1, {}).get(1, null)
	_check("replace 后 A slot1 是卡牌(CardView)", slot_rep is CardView)
