extends Node
## headless 单元测试：3D 对局交互（拾取标记 / 高亮 / 揭示 / 相机 / HUD / 视图）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TABLE3D INTERACTION RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_layout_pick()
	await _test_card_block()
	_test_camera_accessor()
	await _test_picker()
	_test_hud()
	await _test_view()
	await _test_hover_pose()

func _test_layout_pick() -> void:
	_check("PICK_LAYER == 2", Table3dLayout.PICK_LAYER == 2)
	_check("PICK_MASK == 2", Table3dLayout.PICK_MASK == 2)

func _test_card_block() -> void:
	var block := CardBlock.new()
	add_child(block)
	block.setup({"card": {"rank": "A", "suit": "♥"}})
	block.set_pick({"kind": "slot", "seat": 1, "slot": 2})
	_check("set_pick/pick_meta 往返", block.pick_meta().get("kind", "") == "slot" and int(block.pick_meta().get("seat", -1)) == 1 and int(block.pick_meta().get("slot", -1)) == 2)
	_check("拾取 Area 在 PICK_LAYER", block.get_node("PickArea").collision_layer == Table3dLayout.PICK_MASK)
	# 高亮
	block.set_actionable(true)
	_check("可操作边缘高亮色", block.has_glow() and block.glow_color() == Table3dLayout.ACTIONABLE_COLOR)
	block.set_actionable(false)
	_check("取消高亮回牌面", block.has_face_texture() and not block.has_glow())
	# protected 优先于 actionable
	var prot := CardBlock.new()
	add_child(prot)
	prot.setup({"protected": true, "card": {"rank": "K", "suit": "♠"}})
	prot.set_actionable(true)
	_check("protected 优先于 actionable", prot.glow_color() == CardBlock.PROTECTED_COLOR)
	# 揭示 / 恢复
	var hidden := CardBlock.new()
	add_child(hidden)
	hidden.setup({"card_id": "c1"})
	_check("未知牌初始无文本", hidden.label_text() == "")
	hidden.reveal({"rank": "Q", "suit": "♦"}, Color(0.2, 0.9, 0.4))
	await get_tree().create_timer(CardBlock.FLIP_DURATION + 0.05).timeout
	_check("reveal 翻到正面显示 Q♦", hidden.label_text() == "Q♦")
	_check("reveal 用牌面 + 彩色发光", hidden.has_face_texture() and hidden.has_glow() and hidden.glow_color() == Color(0.2, 0.9, 0.4))
	hidden.restore()
	await get_tree().create_timer(CardBlock.FLIP_DURATION + 0.05).timeout
	_check("restore 翻回未知（无文本）", hidden.label_text() == "")
	_check("restore 后回到未知卡背", hidden.has_back_texture() and hidden.block_color() == Color.WHITE)
	# flash 短暂边缘发光后恢复
	hidden.flash(Color(0.2, 0.6, 1.0), 0.05)
	_check("flash 立即染色", hidden.has_glow() and hidden.glow_color() == Color(0.2, 0.6, 1.0))
	await get_tree().create_timer(0.15).timeout
	_check("flash 结束后恢复卡背", hidden.has_back_texture() and not hidden.has_glow() and hidden.block_color() == Color.WHITE)
	# 视觉 pivot：hover 只动 _visual，拾取盒留根
	var vb := CardBlock.new()
	add_child(vb)
	vb.setup({"card": {"rank": "A", "suit": "♥"}})
	_check("视觉 pivot 为根子节点", vb.visual_node() != null and vb.visual_node().get_parent() == vb)
	_check("拾取盒仍在根", vb.get_node("PickArea") != null and vb.get_node("PickArea").get_parent() == vb)
	_check("Mesh 挂在视觉 pivot 下", vb.visual_node().has_node("Mesh"))

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

func _test_camera_accessor() -> void:
	var rig := _make_camera_rig()
	_check("camera_node 非空且为 Camera3D", rig.camera_node() != null and rig.camera_node() is Camera3D)

func _test_picker() -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(50.0, 0.0, 0.0)
	var block := CardBlock.new()
	root.add_child(block)
	block.setup({"card_id": "c9"})
	block.set_pick({"kind": "slot", "seat": 2, "slot": 1})
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0.0, 0.0, 2.0)
	cam.look_at(root.global_position)
	await get_tree().physics_frame
	var center := get_viewport().get_visible_rect().size * 0.5
	var hit := Table3dPicker.pick(cam, root.get_world_3d(), center)
	_check("拾取命中槽位", str(hit.get("kind", "")) == "slot" and int(hit.get("seat", -1)) == 2 and int(hit.get("slot", -1)) == 1)
	cam.position = Vector3(0.0, 5.0, 5.0)
	cam.look_at(Vector3(0.0, 3.0, 0.0))
	await get_tree().physics_frame
	var miss := Table3dPicker.pick(cam, root.get_world_3d(), center)
	_check("准星指空处未命中", miss.is_empty())

func _test_hud() -> void:
	var hud := Table3dHud.new()
	add_child(hud)
	hud.set_buttons([
		{"text": "Ready（1/2）", "action": "ready", "enabled": true},
		{"text": "🔔 KONGBAYA", "action": "kongbaya", "enabled": false},
	])
	_check("HUD 按钮数", hud.button_count() == 2)
	_check("HUD action 0", hud.button_action(0) == "ready")
	_check("HUD action 1", hud.button_action(1) == "kongbaya")
	_check("HUD 禁用按钮颜色", hud.button_color(1) == Table3dHud.DISABLED_COLOR)
	_check("HUD 启用按钮颜色", hud.button_color(0) == Table3dHud.ENABLED_COLOR)
	var area: Area3D = hud.get_child(0).get_node("PickArea")
	_check("HUD 按钮可拾取", area.get_meta("pick", {}).get("action", "") == "ready")

func _test_view() -> void:
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	view.render({
		"viewer_id": 0,
		"players": [
			{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2,
			 "slots": [{"card_id": "c1"}, {"card_id": "c2"}, {"card_id": "c3"}, {"card_id": "c4"}]},
			{"id": 1, "name": "乙", "count": 4, "currency": 0, "health": 2,
			 "slots": [{"card_id": "c9"}, {"card_id": "c10"}, {"card_id": "c11"}, {"card_id": "c12"}]},
		],
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 2,
	})
	await get_tree().physics_frame
	_check("_card_blocks 登记", view._card_blocks.has(0) and view._card_blocks[0].has(0))
	_check("自己角色隐藏（含头与身体）", not view._seat_nodes[0].get_node("Avatar").visible)
	_check("对手角色可见", view._seat_nodes[1].get_node("Avatar").visible)
	var avatar = view._seat_nodes[0].get_node("Avatar")
	_check("角色位于眼位（EYE_HEIGHT/CAMERA_BACK）", avatar.position.is_equal_approx(Vector3(0.0, view.camera.EYE_HEIGHT, -view.camera.CAMERA_BACK)))
	_check("身体在头正下方（无水平位移）", avatar.get_node("Body").position.x == 0.0 and avatar.get_node("Body").position.z == 0.0)
	# 默认取景：准星应指向牌堆（可点），且 hover 有高亮反馈
	_check("默认准星指向牌堆", str(view.pick_center().get("kind", "")) == "deck")
	_check("hover 命中可点目标", view.update_hover())
	var deck_block = view.get_node("Center/Deck")
	_check("hover 边缘高亮", deck_block.has_glow())
	view.clear_hover()
	_check("取消 hover 清除高亮", not deck_block.has_glow())
	# 悬停对象被释放后应安全（历史：带类型形参传已释放对象会报错并中断 clear_hover）
	var tmp := CardBlock.new()
	add_child(tmp)
	view._hover_collider = tmp
	tmp.queue_free()
	await get_tree().process_frame
	view.clear_hover()
	_check("悬停对象释放后 clear_hover 安全", view._hover_collider == null)
	# 从 slot0 正上方垂直下看 → pick_center 命中 slot0（避免被同列 slot1 遮挡）
	var block = view._card_blocks[0][0]
	view.camera.get_node("PitchPivot").rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	view.camera.rotation_degrees = Vector3.ZERO
	view.camera.global_position = block.global_position + Vector3(0.0, 1.2, 0.0)
	await get_tree().physics_frame
	var pick: Dictionary = view.pick_center()
	_check("pick_center 命中槽位", str(pick.get("kind", "")) == "slot" and int(pick.get("seat", -1)) == 0 and int(pick.get("slot", -1)) == 0)
	# 高亮
	view.render({
		"viewer_id": 0,
		"players": [
			{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2,
			 "slots": [{"card_id": "c1"}, {"card_id": "c2"}, {"card_id": "c3"}, {"card_id": "c4"}]},
			{"id": 1, "name": "乙", "count": 4, "currency": 0, "health": 2,
			 "slots": [{"card_id": "c9"}, {"card_id": "c10"}, {"card_id": "c11"}, {"card_id": "c12"}]},
		],
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 2,
	}, func(seat: int, slot: int) -> bool: return seat == 0 and slot == 0)
	await get_tree().process_frame
	_check("render(actionable) 高亮", view._card_blocks[0][0].glow_color() == Table3dLayout.ACTIONABLE_COLOR)
	_check("非可操作不高亮", not view._card_blocks[0][1].has_glow())
	# 揭示 / 恢复（水平翻转）
	view.reveal_slot(0, 0, {"rank": "A", "suit": "♥"}, Color(0.2, 0.9, 0.4), 0.6)
	await get_tree().create_timer(CardBlock.FLIP_DURATION + 0.05).timeout
	_check("reveal_slot 翻到正面显示 A♥", view._card_blocks[0][0].label_text() == "A♥")
	await get_tree().create_timer(0.6).timeout
	_check("reveal_slot 后恢复无文本", view._card_blocks[0][0].label_text() == "")
	# HUD 可拾取
	view.set_hud_buttons([{"text": "Ready", "action": "ready", "enabled": true}])
	await get_tree().process_frame
	var hud_btn = view._hud.get_child(0)
	# 从桌心一侧朝 viewer 看 HUD：避免 seat0 手牌（HUD 与相机之间的 fixture）遮挡射线
	view.camera.get_node("PitchPivot").rotation_degrees = Vector3.ZERO
	view.camera.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	view.camera.global_position = hud_btn.global_position + Vector3(0.0, 0.0, -1.0)
	await get_tree().physics_frame
	var hud_pick: Dictionary = view.pick_center()
	_check("pick_center 命中 HUD", str(hud_pick.get("kind", "")) == "hud" and str(hud_pick.get("action", "")) == "ready")
	_check("铃铛拾取标记", view.get_node("Center/KongBell/PickArea").get_meta("pick", {}).get("action", "") == "kongbaya")
	_check("pending 与牌堆同尺寸（scale 1）", view.get_node("Center/Pending").scale.is_equal_approx(Vector3.ONE))
	# 回合标识：当前行动者名字面板上方的红色倒三角
	var players := [
		{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2,
		 "slots": [{"card_id": "c1"}, {"card_id": "c2"}, {"card_id": "c3"}, {"card_id": "c4"}]},
		{"id": 1, "name": "乙", "count": 4, "currency": 0, "health": 2,
		 "slots": [{"card_id": "c9"}, {"card_id": "c10"}, {"card_id": "c11"}, {"card_id": "c12"}]},
	]
	view.render({"viewer_id": 0, "current_player": 1, "players": players,
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 2})
	await get_tree().process_frame
	var m0 = view._seat_nodes[0].get_node_or_null("Avatar/TurnMarker")
	var m1 = view._seat_nodes[1].get_node_or_null("Avatar/TurnMarker")
	_check("回合标识：当前行动者显示", m1 != null and m1.visible)
	_check("回合标识：非当前行动者隐藏", m0 != null and not m0.visible)
	var fill = m1.get_node_or_null("Fill") if m1 != null else null
	var hint = m1.get_node_or_null("LookHint") if m1 != null else null
	var outline = m1.get_node_or_null("Outline") if m1 != null else null
	var marker_ok := false
	var ring_ok := false
	if fill != null and (fill.mesh as ArrayMesh) != null:
		var verts: PackedVector3Array = (fill.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		marker_ok = verts.size() == 3 and (fill.material_override as StandardMaterial3D).albedo_color == Table3dView.TURN_MARKER_COLOR
	if outline != null and (outline.mesh as ArrayMesh) != null:
		var o_verts: PackedVector3Array = (outline.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		ring_ok = o_verts.size() == 18 and (outline.material_override as StandardMaterial3D).albedo_color == Table3dView.TURN_MARKER_OUTLINE_COLOR
	_check("回合标识：红色倒三角（3 顶点）", marker_ok)
	_check("回合标识：空心黑边（18 顶点环，不遮红心）", ring_ok)
	_check("回合标识：顶部「看牌」提示", hint != null and hint.text == Table3dView.TURN_MARKER_HINT and hint.modulate == Table3dView.TURN_MARKER_HINT_COLOR)
	view.render({"viewer_id": 0, "current_player": 1, "players": players,
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 7})
	await get_tree().process_frame
	_check("回合标识：GAME_OVER 不显示", not m1.visible)
	# 揭示跨 render 保持：状态广播重建卡牌后仍重新翻到正面
	view.render({"viewer_id": 0, "current_player": 1, "players": players,
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 2})
	await get_tree().process_frame
	view.reveal_slot(0, 0, {"rank": "K", "suit": "♣"}, Color(0.2, 0.9, 0.4), 1.0)
	await get_tree().create_timer(CardBlock.FLIP_DURATION + 0.05).timeout
	view.render({"viewer_id": 0, "current_player": 1, "players": players,
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 2})
	await get_tree().create_timer(CardBlock.FLIP_DURATION + 0.05).timeout
	_check("揭示跨 render 保持正面", view._card_blocks[0][0].label_text() == "K♣")
	# hover 动效：仅 own 槽启用；抬起时拾取盒不动；跨 render 保持
	var players_h := [
		{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2,
		 "slots": [{"card_id": "c1"}, {"card_id": "c2"}, {"card_id": "c3"}, {"card_id": "c4"}]},
		{"id": 1, "name": "乙", "count": 4, "currency": 0, "health": 2,
		 "slots": [{"card_id": "c9"}, {"card_id": "c10"}, {"card_id": "c11"}, {"card_id": "c12"}]},
	]
	view.render({"viewer_id": 0, "players": players_h, "draw_count": 30, "discard": {}, "pending": {}, "phase": 2})
	await get_tree().process_frame
	_check("own 槽启用 hover 动画", view._card_blocks[0][0].hover_anim_enabled)
	_check("非 own 槽不启用", not view._card_blocks[1][0].hover_anim_enabled)
	var hb = view._card_blocks[0][0]
	var base_pos: Vector3 = hb.position
	var area_pos: Vector3 = hb.get_node("PickArea").global_position
	hb.set_hover_pose(true, Vector2.ZERO)
	await get_tree().create_timer(CardAnimationConfig.new().hover_in_dur + 0.1).timeout
	_check("own hover 抬起", hb.visual_node().position.y > 0.0)
	_check("抬起时拾取盒不移动", hb.position.is_equal_approx(base_pos) and hb.get_node("PickArea").global_position.is_equal_approx(area_pos))
	view._hover_slot = {"seat": 0, "slot": 0}
	view._hover_ray_local = Vector2.ZERO
	view.render({"viewer_id": 0, "players": players_h, "draw_count": 30, "discard": {}, "pending": {}, "phase": 2})
	await get_tree().process_frame
	_check("跨 render 保持 hover 抬起", view._card_blocks[0][0].hover_progress() == 1.0)
	_check("跨 render 后视觉抬起", view._card_blocks[0][0].visual_node().position.y > 0.0)

func _test_hover_pose() -> void:
	var cfg := CardAnimationConfig.new()
	var b := CardBlock.new()
	b.hover_anim_enabled = true
	add_child(b)
	b.setup({"card": {"rank": "A", "suit": "♥"}})
	b.set_hover_pose(true, Vector2.ZERO)
	await get_tree().create_timer(cfg.hover_in_dur + 0.1).timeout
	_check("own hover 抬起", b.hover_progress() > 0.9 and b.visual_node().position.y > 0.0)
	b.set_hover_pose(false, Vector2.ZERO)
	await get_tree().create_timer(cfg.hover_out_dur + 0.1).timeout
	_check("离开落回", b.hover_progress() < 0.1 and absf(b.visual_node().position.y) < 0.001)
	var c := CardBlock.new()
	add_child(c)
	c.setup({"card": {"rank": "2", "suit": "♣"}})
	c.set_hover_pose(true, Vector2.ZERO)
	await get_tree().create_timer(cfg.hover_in_dur + 0.1).timeout
	_check("未启用动画的块不抬", c.visual_node().position.is_equal_approx(Vector3.ZERO))
