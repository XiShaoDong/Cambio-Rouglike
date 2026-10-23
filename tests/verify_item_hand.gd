extends Node
## headless 测试：道具手牌纯函数/模型/Overlay/可替换手部接口。

var failures := 0
var checks := 0

func _ready() -> void:
	_test_math()
	_test_model()
	await _test_overlay()
	await _test_main_input()
	var status: String = " (FAILURES!)" if failures > 0 else ""
	print("=== ITEM HAND RESULT: %d/%d passed%s ===" % [checks - failures, checks, status])
	get_tree().quit(1 if failures > 0 else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _test_math() -> void:
	_check("Q/E 循环回绕", ItemHandMath.cycle(0, 3, -1) == 2 and ItemHandMath.cycle(2, 3, 1) == 0)
	var layout := ItemHandMath.fan_layout(3, Vector2(110, 154), Vector2(500, 500), 18.0, 90.0, 1, 30.0)
	_check("扇形 3 张布局", layout.size() == 3)
	_check("选中卡抬起并置顶", int(layout[1].z) == 100 and float(layout[1].scale) > 1.0 \
		and float(layout[1].pos.y) < float(layout[0].pos.y))
	_check("左右卡对称旋转", float(layout[0].rot_deg) < 0.0 and float(layout[2].rot_deg) > 0.0)
	var players := [{"id": 0}, {"id": 1}, {"id": 2}, {"id": 3}]
	_check("目标顺序从下一位开始", ItemHandMath.target_order(players, 0) == [1, 2, 3])
	_check("目标顺序从中间开始回绕", ItemHandMath.target_order(players, 2) == [3, 0, 1])
	_check("目标顺序跳过淘汰者", ItemHandMath.target_order([{"id": 0}, {"id": 1}, {"id": 2, "eliminated": true}], 0) == [1])

func _test_model() -> void:
	var m := ItemHandModel.new()
	m.set_cards([ItemCards.FATE_PLUS2_ID, ItemCards.INTERFERE_ID])
	_check("模型初始选中第一张", m.selected_id() == ItemCards.FATE_PLUS2_ID)
	m.cycle_card(1)
	_check("模型 Q/E 切卡", m.selected_id() == ItemCards.INTERFERE_ID)
	m.begin_target([1, 2, 3])
	_check("模型进入目标模式", m.target_mode and m.target_seat() == 1)
	m.cycle_target(-1)
	_check("模型目标回绕", m.target_seat() == 3)
	m.end_target()
	_check("模型退出目标模式", not m.target_mode and m.target_seat() == -1)

func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = code
	return e

func _test_main_input() -> void:
	var main_node: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	await get_tree().process_frame
	var players := []
	for i in 4:
		players.append({"id": i, "name": "P%d" % i, "slots": [], "relics": ["", "", ""],
			"health": 2, "currency": 100, "count": 0, "eliminated": false})
	main_node.latest_state = {
		"phase": 2, "viewer_id": 0, "current_player": 0, "current_name": "P0",
		"players": players, "item_cards": [ItemCards.INTERFERE_ID],
		"item_card_used": false, "draw_count": 40, "discard": {}, "discard_count": 0,
		"pending": {}, "event_log": [], "match_number": 1, "slap_rank": "", "slap_open": false,
		"slap_exchange_actor": 0, "kong_caller": -1, "ready_count": 0, "result": {},
		"run": {"match_limit": 5}, "q_decision": {}, "shop": {},
	}
	_check("main 空格打开道具手牌", main_node._item_hand_handle_input(_key(KEY_SPACE)) 		and main_node._item_hand != null and main_node._item_hand.is_open())
	_check("main Enter 进入目标模式", main_node._item_hand_handle_input(_key(KEY_ENTER)) 		and main_node._item_hand.is_target_mode())
	_check("main 目标初始为下一位对手", main_node._item_target_seat == 1)
	var border_found := false
	for area in [main_node.top_player_box, main_node.left_player_box, main_node.right_player_box, main_node.bottom_player_box]:
		if area != null and area.get_node_or_null("ItemTargetBorder") != null:
			border_found = true
	_check("2D 目标玩家区域高亮", border_found)
	# 目标模式（Enter 后切换视角的连线）：A/D 切目标，Q/E 不再参与
	_check("main A/D 切目标", main_node._item_hand_handle_input(_key(KEY_A)) and main_node._item_target_seat == ItemHandMath.target_order(main_node.latest_state.get("players", []), 0)[-1])
	main_node._item_hand_handle_input(_key(KEY_D))
	main_node._item_hand_handle_input(_key(KEY_D))
	_check("main D 回绕切目标", main_node._item_target_seat == 2)
	_check("main Q 已不参与目标切换", main_node._item_target_seat == 2)
	_check("main Esc 取消目标回到扇形", main_node._item_hand_handle_input(_key(KEY_ESCAPE)) 		and not main_node._item_hand.is_target_mode() and main_node._item_hand.is_open())
	_check("main A/D 切卡", main_node._item_hand_handle_input(_key(KEY_A)) \
		and main_node._item_hand.selected_id() == ItemCards.INTERFERE_ID)
	_check("main 空格放下手牌", main_node._item_hand_handle_input(_key(KEY_SPACE)) 		and not main_node._item_hand.is_open())
	main_node.queue_free()

func _test_overlay() -> void:
	var overlay := ItemHandOverlay.new()
	add_child(overlay)
	await get_tree().process_frame
	overlay.setup({"item_cards": [ItemCards.FATE_PLUS2_ID, ItemCards.INTERFERE_ID]}, 0)
	overlay.open()
	_check("Overlay 打开并显示 2 张", overlay.is_open() and overlay.card_count() == 2)
	_check("Overlay 选中第一张", overlay.selected_id() == ItemCards.FATE_PLUS2_ID)
	_check("Overlay 说明显示卡名/说明", overlay.selected_title_text() == "命运·加二" \
		and overlay.selected_body_text().contains("对手"))
	_check("Overlay 手部实现 ItemHandArt", overlay.hand_art() is ItemHandArt)
	overlay.select_next(1)
	_check("Overlay Q/E 切卡", overlay.selected_id() == ItemCards.INTERFERE_ID)
	overlay.begin_target([1, 2, 3])
	_check("Overlay 目标模式收起扇形", overlay.is_target_mode() and overlay.target_panel_visible())
	overlay.cycle_target(1)
	_check("Overlay 目标 Q/E 切换", overlay.target_seat() == 2)
	overlay.cancel_target()
	_check("Overlay 取消目标回到扇形", not overlay.is_target_mode() and not overlay.target_panel_visible())
	overlay.close()
	_check("Overlay 放下立即消失", not overlay.is_open())
	# 可替换手部：换成同一场景仍实现接口
	overlay.set_hand_art_scene(load("res://scenes/ui/hand_silhouette_2d.tscn"))
	_check("可替换手部接口", overlay.hand_art() is ItemHandArt)
	overlay.queue_free()
