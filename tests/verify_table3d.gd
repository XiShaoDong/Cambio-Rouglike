extends Node
## headless 单元测试：3D 预览的节点层（CardBlock / 相机 / 快照渲染）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TABLE3D RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_card_block()
	_test_camera()
	await _test_view_render()

func _test_card_block() -> void:
	var known := CardBlock.new()
	add_child(known)
	known.setup({"card": {"rank": "A", "suit": "♥"}})
	_check("CardBlock 已知牌文本 A♥", known.label_text() == "A♥")
	_check("CardBlock 已知牌用正面贴图", known.has_face_texture() and known.block_color() == Color.WHITE and known.albedo_texture() == load("res://assets/Cards/hearts_ace.png"))
	_check("CardBlock 非保护无发光", not known.has_glow())
	var unknown := CardBlock.new()
	add_child(unknown)
	unknown.setup({})
	_check("CardBlock 未知牌无文本", unknown.label_text() == "")
	_check("CardBlock 未知牌颜色", unknown.has_back_texture() and unknown.block_color() == Color.WHITE)
	var prot := CardBlock.new()
	add_child(prot)
	prot.setup({"protected": true, "card": {"rank": "K", "suit": "♠"}})
	_check("CardBlock 护盾发光", prot.has_glow())
	_check("CardBlock 护盾紫色", prot.has_glow() and prot.glow_color() == CardBlock.PROTECTED_COLOR)
	_check("CardBlock 护盾仍显示点数", prot.label_text() == "K♠")
	_check("CardBlock Joker 文本", CardBlock.card_text({"rank": "JOKER", "suit": "red"}) == "JOKER")
	_check("CardBlock 空卡文本", CardBlock.card_text({}) == "")

## 构造带场景子节点的相机 rig（契约：PitchPivot/Camera3D 由场景提供）。
func _make_camera_rig() -> Table3dCamera:
	var rig := Table3dCamera.new()
	var pivot := Node3D.new()
	pivot.name = "PitchPivot"
	rig.add_child(pivot)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	pivot.add_child(cam)
	add_child(rig)
	return rig

func _test_camera() -> void:
	var rig := _make_camera_rig()
	rig.frame_for_seat(0.0)
	_check("相机基准朝向 0°", is_equal_approx(rig.base_yaw, 0.0))
	_check("相机默认俯角对准桌心", is_equal_approx(rig.pitch, Table3dCamera.aim_pitch_deg(rig.EYE_HEIGHT, Table3dLayout.SEAT_RADIUS + rig.CAMERA_BACK)))
	_check("相机座位位置", rig.position.is_equal_approx(Vector3(0.0, rig.EYE_HEIGHT, Table3dLayout.SEAT_RADIUS + rig.CAMERA_BACK)))
	rig.look(Vector2(-100.0, 0.0))
	_check("鼠标左移 → yaw +50（方向正确、灵敏度 0.5）", is_equal_approx(rig.yaw, 50.0))
	rig.look(Vector2(1000.0, 1000.0))
	_check("yaw 夹下限 -90", is_equal_approx(rig.yaw, -Table3dCamera.YAW_LIMIT))
	_check("pitch 夹上限 60", is_equal_approx(rig.pitch, Table3dCamera.PITCH_LIMIT))
	rig.look(Vector2(-5000.0, -5000.0))
	_check("yaw 夹上限 +90", is_equal_approx(rig.yaw, Table3dCamera.YAW_LIMIT))
	_check("pitch 夹下限 -60", is_equal_approx(rig.pitch, -Table3dCamera.PITCH_LIMIT))
	rig.frame_for_seat(180.0)
	_check("对面基准朝向 180°", is_equal_approx(rig.base_yaw, 180.0))
	_check("对面座位位置", rig.position.is_equal_approx(Vector3(0.0, rig.EYE_HEIGHT, -(Table3dLayout.SEAT_RADIUS + rig.CAMERA_BACK))))
	# 同一座位重复取景（每次 render 调 frame_for_seat）不应复位用户环视
	rig.look(Vector2(20.0, 10.0))
	var yaw_after_look: float = rig.yaw
	rig.frame_for_seat(180.0)
	_check("重复取景保留环视（不复位）", is_equal_approx(rig.yaw, yaw_after_look))

func _test_view_render() -> void:
	var scene: PackedScene = load("res://scenes/ui/table3d.tscn")
	var view := scene.instantiate()
	add_child(view)
	await get_tree().process_frame
	var state := {
		"viewer_id": 0,
		"players": [
			{"id": 0, "name": "甲", "count": 2, "currency": 100, "health": 2, "eliminated": false,
			 "slots": [{"card_id": "c1"}, {"card_id": "c2"}, {"card_id": "c3"},
			           {"card_id": "c4", "card": {"rank": "A", "suit": "♥"}}]},
			{"id": 1, "name": "乙", "count": 1, "currency": 80, "health": 2, "eliminated": false,
			 "slots": [{"card_id": "c9"}, {"card_id": "c10"}, {"card_id": "c11"}, {"card_id": "c12"}]},
		],
		"draw_count": 30,
		"discard": {},
		"pending": {},
		"phase": 2,
	}
	view.render(state)
	await get_tree().process_frame
	_check("viewer 座位可见", view._seat_nodes[0].visible)
	_check("对手座位可见", view._seat_nodes[1].visible)
	_check("空座位隐藏", not view._seat_nodes[2].visible and not view._seat_nodes[3].visible)
	_check("viewer 手牌 4 槽", view._seat_nodes[0].get_node("HandAnchor").get_child_count() == 4)
	_check("主手牌两列关于座位中轴居中", is_zero_approx(view._slot_local(0).origin.x + view._slot_local(1).origin.x) and is_zero_approx(view._slot_local(2).origin.x + view._slot_local(3).origin.x))
	_check("viewer 面板 data", view._seat_panels[0].data.get("name") == "甲" and int(view._seat_panels[0].data.get("currency")) == 100)
	_check("对手面板 data", view._seat_panels[1].data.get("name") == "乙")
	_check("每席面板各一", view._seat_panels.size() == 4)
	_check("viewer 相机基准 0°", is_equal_approx(view.camera.base_yaw, 0.0))
	var found_ace := false
	for child in view._seat_nodes[0].get_node("HandAnchor").get_children():
		if child is CardBlock and child.label_text() == "A♥":
			found_ace = true
	_check("已知牌 A♥ 渲染", found_ace)
	var hidden_ok := true
	for child in view._seat_nodes[1].get_node("HandAnchor").get_children():
		if child is CardBlock and child.label_text() != "":
			hidden_ok = false
	_check("他人未知牌无点数标签", hidden_ok)
	# 弃牌顶与 pending 已知牌渲染
	view.render({
		"viewer_id": 0,
		"players": state.players,
		"draw_count": 29,
		"discard": {"rank": "7", "suit": "♣"},
		"pending": {"rank": "Q", "suit": "♦", "source": "draw"},
		"phase": 3,
	})
	await get_tree().process_frame
	var center = view.get_node("Center")
	_check("弃牌顶标签 7♣", (center.get_node("DiscardTop") as CardBlock).label_text() == "7♣")
	_check("pending 标签 Q♦", (center.get_node("Pending") as CardBlock).label_text() == "Q♦")
	# pending 首次出现会触发抽牌飞牌（期间大牌隐藏），落地后才显示
	await get_tree().create_timer(1.0).timeout
	_check("pending 可见（抽牌飞牌落地后）", (center.get_node("Pending") as Node3D).visible)
	_check("大牌位于桌心正上方", (center.get_node("Pending") as Node3D).position.is_equal_approx(Vector3(0.0, Table3dView.PENDING_Y, 0.0)))
	var deck_n: Node3D = center.get_node("Deck")
	var disc_n: Node3D = center.get_node("DiscardTop")
	_check("两堆关于桌心对称", is_zero_approx(deck_n.position.x + disc_n.position.x) and is_zero_approx(deck_n.position.z - disc_n.position.z))
	# 空槽（贴牌成功被清掉的牌）不渲染 → 卡牌消失
	view.render({
		"viewer_id": 0,
		"players": [
			{"id": 0, "name": "甲", "count": 3, "currency": 100, "health": 2, "eliminated": false,
			 "slots": [{"card_id": "c1"}, {"card_id": ""}, {"card_id": "c3"}, {"card_id": "c4"}]},
			{"id": 1, "name": "乙", "count": 1, "currency": 80, "health": 2, "eliminated": false,
			 "slots": [{"card_id": "c9"}, {"card_id": "c10"}, {"card_id": "c11"}, {"card_id": "c12"}]},
		],
		"draw_count": 28, "discard": {}, "pending": {}, "phase": 6,
	})
	await get_tree().process_frame
	_check("空槽不渲染（卡牌消失）", view._seat_nodes[0].get_node("HandAnchor").get_child_count() == 3)
	_check("空槽无 CardBlock 登记", not view._card_blocks[0].has(1) and view._card_blocks[0].has(3))
