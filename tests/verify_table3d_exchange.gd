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
	await _test_reveal_replay_no_restart()
	_test_reveal_glow_priority()
	await _test_draw_fly()
	await _test_discard_pile_actionable()

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

## B37 回归：揭示重放不应把翻牌从头再播（翻完又显示正面 + 重新打炫光）。
func _test_reveal_replay_no_restart() -> void:
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	view.render(_base_state())
	await get_tree().process_frame

	# 揭示完成后重放：应保持正面，不从 0 重播
	view.reveal_slot(0, 2, {"rank": "Q", "suit": "♦"}, Color(0.9, 0.3, 0.3), 1.5)
	await get_tree().create_timer(CardBlock.FLIP_DURATION + 0.1).timeout
	_check("揭示完成后进度 1", is_equal_approx(view._card_blocks[0][2].reveal_progress(), 1.0))
	view.render(_base_state())
	await get_tree().process_frame
	_check("重放后仍为正面（进度不归零）", is_equal_approx(view._card_blocks[0][2].reveal_progress(), 1.0))
	_check("重放后牌面保持", view._card_blocks[0][2].label_text() == "Q♦")
	_check("重放后炫光保持", view._card_blocks[0][2].has_glow() and view._card_blocks[0][2].glow_color() == Color(0.9, 0.3, 0.3))
	# 揭示窗口结束后恢复背面
	await get_tree().create_timer(1.0).timeout
	_check("揭示结束恢复背面", view._card_blocks[0][2].label_text() == "" and not view._card_blocks[0][2].has_glow())

	# 进行中重放：进度续播、不归零
	view.reveal_slot(0, 3, {"rank": "J", "suit": "♣"}, Color(0, 0, 0, 0), 1.5)
	await get_tree().create_timer(0.15).timeout
	var mid_before: float = view._card_blocks[0][3].reveal_progress()
	view.render(_base_state())
	await get_tree().process_frame
	var mid_after: float = view._card_blocks[0][3].reveal_progress()
	_check("进行中重放进度不回零", mid_after > 0.0 and absf(mid_after - mid_before) < 0.35)
	await get_tree().create_timer(1.6).timeout
	view.queue_free()

## 揭示炫光（贴对绿 / 贴错红 / 查看蓝）优先于一切非 flash；hover 又高于 actionable（悬停可确认选中）。
func _test_reveal_glow_priority() -> void:
	var b := CardBlock.new()
	add_child(b)
	b.setup({"card_id": "x"})
	b.set_actionable(true)
	_check("actionable 显示金色", b.has_glow() and b.glow_color() == Table3dLayout.ACTIONABLE_COLOR)
	b.set_hover(true)
	_check("hover 覆盖 actionable 显示浅蓝", b.glow_color() == Color(0.7, 0.95, 1.0))
	b.reveal({"rank": "Q", "suit": "♦"}, Color(0.9, 0.3, 0.3))
	_check("揭示炫光覆盖 hover 浅蓝", b.glow_color() == Color(0.9, 0.3, 0.3))
	b.set_hover(true)
	_check("hover 重绘不覆盖揭示炫光", b.glow_color() == Color(0.9, 0.3, 0.3))
	b.set_actionable(true)
	_check("actionable 重绘不覆盖揭示炫光", b.glow_color() == Color(0.9, 0.3, 0.3))
	b.set_actionable(false)
	b.restore()
	_check("恢复后揭示炫光清除、回到 hover 浅蓝", b.glow_color() == Color(0.7, 0.95, 1.0))
	b.queue_free()

## 3D 抽牌飞牌：pending 出现 → 飞牌（抽牌堆/弃牌堆 → 竖立大牌），所有人可见。
func _test_draw_fly() -> void:
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	# 首帧（无 pending）建立基线，不触发
	view.render(_base_state())
	await get_tree().process_frame
	_check("首帧无 pending 不触发飞牌", view._flyers.is_empty())

	# 抽牌堆抽牌：pending 出现 → 1 张飞牌 + 大牌隐藏
	var s := _base_state()
	s["pending"] = {"rank": "Q", "suit": "♦", "source": "draw"}
	view.render(s)
	await get_tree().process_frame
	_check("抽牌出现 → 1 张飞牌", view._flyers.size() == 1)
	_check("抽牌期间大牌隐藏", view._pending_hold and not view._pending_block.visible)
	_check("抽牌飞牌从抽牌堆侧起飞", view._flyers[0].global_position.x < view.center_xform("pending").origin.x)
	await _wait_flyers(view)
	_check("抽牌落地 → 大牌显示、锁解除", not view._pending_hold and view._pending_block.visible)

	# 取弃牌顶：弃牌堆顶变化 → 从弃牌堆起飞
	view.render(_base_state())
	await get_tree().process_frame
	var s2 := _base_state()
	s2["discard"] = {"rank": "7", "suit": "♣"}
	view.render(s2)   # prev：pending 空、弃牌顶 7♣
	await get_tree().process_frame
	var s3 := _base_state()
	s3["discard"] = {}                              # 弃牌堆被取走 → 顶变化
	s3["pending"] = {"rank": "7", "suit": "♣", "source": "discard"}
	view.render(s3)
	await get_tree().process_frame
	_check("取弃牌顶 → 1 张飞牌", view._flyers.size() == 1)
	_check("取弃牌顶从弃牌堆侧起飞", view._flyers[0].global_position.x > view.center_xform("pending").origin.x)
	await _wait_flyers(view)

	# 非行动者：pending 隐藏 → 飞牌为背面
	view.render(_base_state())
	await get_tree().process_frame
	var s5 := _base_state()
	s5["pending"] = {"card_id": "z", "hidden": true}
	view.render(s5)
	await get_tree().process_frame
	_check("非行动者抽牌飞牌为背面", view._flyers.size() == 1 and view._flyers[0].card_block().label_text() == "")
	await _wait_flyers(view)
	view.queue_free()

## 弃牌堆按上下文可点 + 金色光晕；大牌不再直接可点。
func _test_discard_pile_actionable() -> void:
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var disc = view.get_node("Center/DiscardTop")
	var deck = view.get_node("Center/Deck")
	# TURN_DRAW 当前玩家 + 弃牌堆非空 → 可取弃牌顶 + 光晕
	var s := _base_state()
	s["phase"] = 2
	s["discard"] = {"rank": "7", "suit": "♣"}
	s["pending"] = {}
	view.render(s)
	await get_tree().process_frame
	_check("TURN_DRAW 弃牌堆可点", disc.is_pick_enabled())
	_check("TURN_DRAW 弃牌堆金色光晕", disc.has_glow() and disc.glow_color() == Table3dLayout.ACTIONABLE_COLOR)
	_check("TURN_DRAW 自己抽牌 → 抽牌堆金色光晕", deck.has_glow() and deck.glow_color() == Table3dLayout.ACTIONABLE_COLOR)
	# TURN_DECISION 当前玩家 + pending(draw) → 可弃大牌 + 光晕；大牌本身不可点
	var s2 := _base_state()
	s2["phase"] = 3
	s2["discard"] = {}
	s2["pending"] = {"rank": "Q", "suit": "♦", "source": "draw"}
	view.render(s2)
	await get_tree().process_frame
	_check("TURN_DECISION 弃牌堆可点（弃大牌）", disc.is_pick_enabled())
	_check("TURN_DECISION 弃牌堆金色光晕", disc.has_glow() and disc.glow_color() == Table3dLayout.ACTIONABLE_COLOR)
	_check("大牌本身不再可点", not view._pending_block.is_pick_enabled())
	# 非当前玩家 → 弃牌堆不可点/不光晕
	var s3 := _base_state()
	s3["phase"] = 3
	s3["current_player"] = 1
	s3["pending"] = {"card_id": "zzz", "hidden": true}
	view.render(s3)
	await get_tree().process_frame
	_check("非当前弃牌堆不可点", not disc.is_pick_enabled())
	_check("非当前弃牌堆不光晕", not disc.has_glow())
	_check("非当前抽牌堆不光晕", not deck.has_glow())
	view.queue_free()
