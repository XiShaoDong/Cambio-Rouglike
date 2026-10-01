extends Node
## headless 单元测试：3D 全息看板宿主（坐标换算 / 挂载 / 朝向 / 输入合成 / 等待提示 / main 路由）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== BOARD3D RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	await _test_board_input()
	await _test_board3d()
	await _test_modals_dim()

func _test_board_input() -> void:
	var size := Vector2(2.6, 1.8)
	_check("中心 → uv(0.5,0.5)", BoardInput.local_to_uv(Vector3.ZERO, size).is_equal_approx(Vector2(0.5, 0.5)))
	_check("左上角 → uv(0,0)", BoardInput.local_to_uv(Vector3(-1.3, 0.9, 0.0), size).is_equal_approx(Vector2(0.0, 0.0)))
	_check("右下角 → uv(1,1)", BoardInput.local_to_uv(Vector3(1.3, -0.9, 0.0), size).is_equal_approx(Vector2(1.0, 1.0)))
	_check("uv(0.5,0.5) → 视口中心", BoardInput.uv_to_viewport(Vector2(0.5, 0.5), Vector2i(1024, 708)) == Vector2i(512, 354))
	_check("uv(0,0) → (0,0)", BoardInput.uv_to_viewport(Vector2(0.0, 0.0), Vector2i(1024, 708)) == Vector2i(0, 0))
	_check("uv(1,1) → 右下角", BoardInput.uv_to_viewport(Vector2(1.0, 1.0), Vector2i(1024, 708)) == Vector2i(1024, 708))
	var xf := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.6, 0.0))
	_check("world_to_local 平移", BoardInput.world_to_local(xf, Vector3(0.0, 1.6, 0.0)).is_equal_approx(Vector3.ZERO))

func _make_camera() -> Camera3D:
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 3.5, 4.5)
	return cam

func _test_board3d() -> void:
	var cam := _make_camera()
	var b := Board3d.new()
	add_child(b)
	await get_tree().process_frame
	cam.look_at(b.global_position, Vector3.UP)
	_check("初始无面板且隐藏", not b.has_panel() and not b.visible)

	var panel := Control.new()
	panel.name = "TestPanel"
	var full_btn := Button.new()
	full_btn.name = "FullBtn"
	full_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(full_btn)
	add_child(panel)  # 先像 main 一样挂 2D，再交给看板

	b.mount_panel(panel)
	await get_tree().process_frame
	_check("mount 后 has_panel", b.has_panel())
	_check("面板父节点为 SubViewport", panel.get_parent() == b.viewport())
	_check("看板可见", b.visible)
	_check("屏幕贴图为视口纹理",
		(b.screen_mesh().material_override as StandardMaterial3D).albedo_texture == b.viewport().get_texture())

	b.set_facing(cam)
	await get_tree().process_frame
	var to_cam := (cam.global_position - b.global_position).normalized()
	_check("看板 +Z 朝相机", b.global_transform.basis.z.normalized().dot(to_cam) > 0.99)

	await get_tree().physics_frame
	await get_tree().physics_frame
	var coord := b.hit_viewport_coord(cam)
	_check("准星命中看板返回视口中心附近", coord.x >= 0 and absi(coord.x - 512) < 40 and absi(coord.y - 354) < 40)

	var got := [0]
	full_btn.pressed.connect(func() -> void: got[0] += 1)
	b.push_click(Vector2i(512, 354))
	await get_tree().process_frame
	await get_tree().process_frame
	_check("push_click 合成事件触发按钮", got[0] == 1)

	var catcher := KeyCatcher.new()
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(catcher)
	var key_ev := InputEventKey.new()
	key_ev.keycode = KEY_ENTER
	key_ev.pressed = true
	b.push_key(key_ev)
	await get_tree().process_frame
	_check("push_key 送达视口内节点", catcher.events.has(KEY_ENTER))

	b.unmount_panel(panel)
	_check("unmount 后面板脱离视口", panel.get_parent() == null)
	_check("unmount 后隐藏", not b.has_panel() and not b.visible)
	b.set_banner("等待其他玩家…")
	_check("banner 非空 → 可见", b.visible)
	b.set_banner("")
	_check("banner 空 → 隐藏", not b.visible)
	panel.queue_free()


func _test_modals_dim() -> void:
	var shop: Control = load("res://scenes/ui/shop_panel.tscn").instantiate()
	add_child(shop)
	await get_tree().process_frame
	var shop_state := {"viewer_id": 0, "players": [{"id": 0, "currency": 100}], "shop": {"offers": [], "done": []}}
	shop.setup(shop_state, Callable(), Callable(), true)
	_check("shop dim=true → Dim 可见", (shop.get_node("Dim") as CanvasItem).visible)
	shop.setup(shop_state, Callable(), Callable(), false)
	_check("shop dim=false → Dim 隐藏", not (shop.get_node("Dim") as CanvasItem).visible)
	shop.queue_free()

	var duel := DuelBar.new()
	add_child(duel)
	await get_tree().process_frame
	duel.setup(self, {"duration_ms": 2000, "target": 0.5, "viewer_contestant": 0}, Callable(), false)
	_check("duel dim=false → 无 Dim 遮罩", duel.get_node_or_null("Dim") == null)
	duel.queue_free()


class KeyCatcher extends Control:
	var events: Array = []
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey:
			events.append(event.keycode)
