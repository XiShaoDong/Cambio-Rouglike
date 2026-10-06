extends Node
## headless 单元测试：Q 能力看牌 hold（2D 展示层）——保持正面 / 交换 consume / 不交换翻回动画后清理。

var failures := 0
var checks := 0
var main_node: Node

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main_node = scene.instantiate()
	add_child(main_node)
	await get_tree().process_frame
	await get_tree().process_frame
	await _run()
	print("=== Q HOLD RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _make_anchor(pid: int, slot: int, pos: Vector2) -> void:
	var a := Control.new()
	a.custom_minimum_size = Vector2(64, 90)
	a.size = Vector2(64, 90)
	a.position = pos
	main_node.add_child(a)
	if not main_node._card_slots.has(pid):
		main_node._card_slots[pid] = {}
	main_node._card_slots[pid][slot] = a

func _run() -> void:
	main_node._table3d_active = false
	_make_anchor(1, 0, Vector2(200, 100))  # 对方牌
	_make_anchor(0, 0, Vector2(200, 300))  # 自己牌

	# 1) Q 看对方牌：hold 登记 + 槽位标记动画 + 激活
	main_node._hold_next_reveal = true
	main_node._show_private_reveal("Q", [{"rank": "K", "suit": "♠", "value": 10}], {"player_id": 1, "slot": 0})
	_check("Q hold 登记（对方牌）", main_node.reveal.has_held(1, 0))
	_check("Q hold 槽位标记动画", main_node.is_anim_slot(1, 0))
	_check("Q hold 激活", main_node._q_hold_active)
	# 2) Q 看自己牌：hold 登记
	main_node._hold_next_reveal = true
	main_node._show_private_reveal("Q", [{"rank": "3", "suit": "♥", "value": 3}], {"player_id": 0, "slot": 0})
	_check("Q hold 登记（自己牌）", main_node.reveal.has_held(0, 0))

	# 3) 交换：consume 返回牌面、清登记、撤槽位标记（交由交换飞牌从正面起飞）
	var c_target: Dictionary = main_node.reveal.consume_held(1, 0)
	_check("consume 返回对方牌面", str(c_target.get("rank", "")) == "K")
	_check("consume 后登记清除", not main_node.reveal.has_held(1, 0))
	_check("consume 后槽位标记撤销", not main_node.is_anim_slot(1, 0))
	var c_own: Dictionary = main_node.reveal.consume_held(0, 0)
	_check("consume 返回自己牌面", str(c_own.get("rank", "")) == "3")

	# 4) 不交换：重新 hold，release 先播翻回动画，动画结束后才清理
	main_node._hold_next_reveal = true
	main_node._show_private_reveal("Q", [{"rank": "K", "suit": "♠", "value": 10}], {"player_id": 1, "slot": 0})
	main_node._release_q_holds()
	_check("release 复位 _q_hold_active", not main_node._q_hold_active)
	_check("release 立即清登记（动画在 overlay 播）", not main_node.reveal.has_held(1, 0))
	_check("release 期间槽位仍标记动画（不瞬切）", main_node.is_anim_slot(1, 0))
	await get_tree().create_timer(0.62).timeout
	_check("翻回动画结束后槽位标记撤销", not main_node.is_anim_slot(1, 0))
