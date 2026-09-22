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
	_check("可操作高亮色", block.block_color() == Table3dLayout.ACTIONABLE_COLOR)
	block.set_actionable(false)
	_check("取消高亮回分类色", block.block_color() == Table3dLayout.known_color_for_rank("A"))
	# protected 优先于 actionable
	var prot := CardBlock.new()
	add_child(prot)
	prot.setup({"protected": true, "card": {"rank": "K", "suit": "♠"}})
	prot.set_actionable(true)
	_check("protected 优先于 actionable", prot.block_color() == CardBlock.PROTECTED_COLOR)
	# 揭示 / 恢复
	var hidden := CardBlock.new()
	add_child(hidden)
	hidden.setup({"card_id": "c1"})
	_check("未知牌初始无文本", hidden.label_text() == "")
	hidden.reveal({"rank": "Q", "suit": "♦"}, Color(0.2, 0.9, 0.4))
	_check("reveal 后显示 Q♦", hidden.label_text() == "Q♦")
	_check("reveal 带色", hidden.block_color() == Color(0.2, 0.9, 0.4))
	hidden.restore()
	_check("restore 后回到未知（无文本）", hidden.label_text() == "")
	_check("restore 后回到未知灰", hidden.block_color() == Table3dLayout.UNKNOWN_COLOR)
	# flash 短暂染色后恢复
	hidden.flash(Color(0.2, 0.6, 1.0), 0.05)
	_check("flash 立即染色", hidden.block_color() == Color(0.2, 0.6, 1.0))
	await get_tree().create_timer(0.15).timeout
	_check("flash 结束后恢复", hidden.block_color() == Table3dLayout.UNKNOWN_COLOR)

func _test_camera_accessor() -> void:
	var rig := Table3dCamera.new()
	add_child(rig)
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
