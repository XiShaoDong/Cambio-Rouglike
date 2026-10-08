extends Node
## headless 单元测试：贴牌成功爆炸弹层（SlapSuccessBurst）+ main 3D 集成。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== SLAP BURST RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	# 单元：构建 + 内容 + 位置
	var burst := SlapSuccessBurst.new()
	add_child(burst)
	burst.setup({"rank": "J", "suit": "♥", "label": "J♥"}, "玩家A")
	await get_tree().process_frame
	_check("第一行=贴牌成功", burst.title_text() == "贴牌成功")
	var nm := burst.get_node_or_null("VBox/Name")
	_check("第二行=玩家名", nm != null and (nm as Label).text == "玩家A")
	var bg := burst.get_node_or_null("Burst")
	_check("齿状爆炸背景有贴图", bg != null and (bg as TextureRect).texture != null)
	_check("背景拉伸铺满", bg != null and (bg as TextureRect).stretch_mode == TextureRect.STRETCH_SCALE)
	var card := burst.get_node_or_null("VBox/CardCenter/Card") as CardView
	_check("中间有卡牌", card != null)
	_check("卡面=红桃J", card != null and card.is_face_up and str(card.card_data.get("rank")) == "J" and str(card.card_data.get("suit")) == "♥")
	_check("中线在屏幕 3/4、垂直居中", is_equal_approx(burst.anchor_left, 0.75) and is_equal_approx(burst.anchor_top, 0.5))
	_check("非交互（IGNORE）", burst.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	burst.queue_free()

	# 集成：3D 下收到 slap_resolved 弹层；切回 2D 移除
	var main_node: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main_node)
	await get_tree().process_frame
	await get_tree().process_frame
	main_node.latest_state = {
		"phase": 2, "viewer_id": 0, "current_player": 0, "current_name": "玩家A",
		"players": [
			{"id": 0, "name": "玩家A", "slots": [], "health": 2, "currency": 100, "count": 0, "eliminated": false},
			{"id": 1, "name": "B", "slots": [], "health": 2, "currency": 100, "count": 0, "eliminated": false},
		],
		"draw_count": 40, "discard": {}, "pending": {}, "event_log": [], "match_number": 1,
		"slap_rank": "", "slap_open": false, "slap_exchange_actor": 0, "kong_caller": -1,
		"ready_count": 0, "result": {}, "run": {"match_limit": 5}, "q_decision": {},
	}
	main_node._set_table3d(true)
	await get_tree().process_frame
	GameState.card_exchange_animated.emit({"kind": "slap_resolved", "actor": 0, "target": 1, "target_slot": 0, "card": {"rank": "J", "suit": "♥", "label": "J♥"}})
	await get_tree().process_frame
	_check("3D 下 slap_resolved 弹出爆炸层", main_node._slap_burst != null and is_instance_valid(main_node._slap_burst))
	_check("爆炸层标题正确", main_node._slap_burst != null and main_node._slap_burst.title_text() == "贴牌成功")
	_check("爆炸层显示贴中者名字", main_node._slap_burst != null and (main_node._slap_burst.get_node_or_null("VBox/Name") as Label).text == "玩家A")
	main_node._set_table3d(false)
	await get_tree().process_frame
	_check("切回 2D 后爆炸层已移除", main_node._slap_burst == null)
	main_node.queue_free()
