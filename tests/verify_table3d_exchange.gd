extends Node
## headless 单元测试：3D 对局换牌飞牌接入（animate_exchange / 跨 render 标记 / 落地恢复）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TABLE3D EXCHANGE RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	await _test_exchange()

func _base_state() -> Dictionary:
	return {
		"viewer_id": 0, "current_player": 0, "phase": 3,
		"draw_count": 30, "discard": {}, "pending": {},
		"players": [
			{"id": 0, "name": "甲", "count": 4, "currency": 0, "health": 2, "eliminated": false,
			 "slots": [{"card_id": "a", "card": {"rank": "K", "suit": "♠"}},
			           {"card_id": "b", "card": {"rank": "A", "suit": "♥"}},
			           {"card_id": "c"}, {"card_id": "d"}]},
			{"id": 1, "name": "乙", "count": 4, "currency": 0, "health": 2, "eliminated": false,
			 "slots": [{"card_id": "e"}, {"card_id": "f", "card": {"rank": "Q", "suit": "♦"}},
			           {"card_id": "g"}, {"card_id": "h"}]},
		],
	}

func _wait_flyers(view, timeout := 3.0) -> void:
	var t := 0.0
	while t < timeout and not view._flyers.is_empty():
		await get_tree().create_timer(0.05).timeout
		t += 0.05

func _test_exchange() -> void:
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	view.render(_base_state())
	await get_tree().process_frame

	# replace：2 段 + 标记槽 + 弃牌锁
	view.animate_exchange({"kind": "replace", "actor": 0, "slot": 0,
		"old_data": {"rank": "K", "suit": "♠"}, "big_data": {"rank": "7", "suit": "♦"}})
	_check("replace 生成 2 张飞牌", view._flyers.size() == 2)
	_check("replace 标记槽位", view._has_anim_slot(0, 0))
	_check("replace 弃牌锁", view._discard_hold)
	view.render(_base_state())
	await get_tree().process_frame
	_check("replace 标记槽不渲染", not view._card_blocks[0].has(0))
	await _wait_flyers(view)
	_check("replace 落地清标记/解锁/释放", not view._has_anim_slot(0, 0) and not view._discard_hold and view._flyers.is_empty())
	_check("replace 落地后槽位恢复", view._card_blocks[0].has(0))

	# swap：2 段，两段全落地才清标记
	view.animate_exchange({"kind": "swap", "a": 0, "a_slot": 1, "b": 1, "b_slot": 1,
		"a_data": {"rank": "A", "suit": "♥"}, "b_data": {"rank": "Q", "suit": "♦"}})
	_check("swap 生成 2 张飞牌", view._flyers.size() == 2)
	_check("swap 标记双槽", view._has_anim_slot(0, 1) and view._has_anim_slot(1, 1))
	await _wait_flyers(view)
	_check("swap 落地清双标记", not view._has_anim_slot(0, 1) and not view._has_anim_slot(1, 1))

	# discard：1 段 + 弃牌锁
	view.animate_exchange({"kind": "discard", "actor": 0, "big_data": {"rank": "8", "suit": "♠"}})
	_check("discard 生成 1 张飞牌", view._flyers.size() == 1)
	_check("discard 弃牌锁", view._discard_hold)
	await _wait_flyers(view)
	_check("discard 落理解锁", not view._discard_hold and view._flyers.is_empty())

	# slap_penalty：未渲染槽 + 背面
	view.animate_exchange({"kind": "slap_penalty", "peer": 1, "slot": 4})
	_check("penalty 生成 1 张飞牌", view._flyers.size() == 1)
	_check("penalty 背面无标签", view._flyers[0].card_block().label_text() == "")
	_check("未渲染槽 xform 非零", not view.slot_xform(1, 4).origin.is_zero_approx())
	await _wait_flyers(view)
	_check("penalty 落地清标记", not view._has_anim_slot(1, 4))

	# slap_resolved：槽→弃牌，牌面公开 + 弃牌锁
	view.animate_exchange({"kind": "slap_resolved", "target": 0, "target_slot": 2, "card": {"rank": "Q", "suit": "♦"}})
	_check("resolved 生成 1 张飞牌", view._flyers.size() == 1)
	_check("resolved 弃牌锁", view._discard_hold)
	await _wait_flyers(view)
	_check("resolved 落地清标记/解锁", not view._has_anim_slot(0, 2) and not view._discard_hold)

	# slap_gift：非 viewer 背面；viewer==actor 带牌面
	view.animate_exchange({"kind": "slap_gift", "actor": 1, "own_slot": 0, "target": 0, "target_slot": 3})
	_check("gift 非 actor 背面", view._flyers[0].card_block().label_text() == "")
	await _wait_flyers(view)
	view.animate_exchange({"kind": "slap_gift", "actor": 0, "own_slot": 0, "target": 1, "target_slot": 3})
	_check("gift viewer==actor 带牌面", view._flyers[0].card_block().label_text() == "K♠")
	await _wait_flyers(view)
	_check("gift 落地清双标记", not view._has_anim_slot(0, 0) and not view._has_anim_slot(1, 3))

	# set_active(false) 清理
	view.animate_exchange({"kind": "discard", "actor": 0, "big_data": {}})
	_check("清理前有飞牌", view._flyers.size() > 0)
	view.set_active(false)
	_check("set_active(false) 清飞牌/锁/标记", view._flyers.is_empty() and not view._discard_hold and view._anim_slots.is_empty())
	view.set_active(true)

	# 无状态安全跳过
	var bare = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(bare)
	await get_tree().process_frame
	bare.animate_exchange({"kind": "discard", "actor": 0, "big_data": {}})
	_check("无状态时安全跳过", bare._flyers.is_empty())
	bare.queue_free()
	view.queue_free()
