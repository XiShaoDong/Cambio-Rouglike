extends Node
## headless 单元测试：桌面标记（Mark3dMath / Mark3D / Table3dView / 同步 / 拾取）。

const Mark3dMathScript := preload("res://scripts/ui/mark3d_math.gd")
const Mark3DScript := preload("res://scripts/ui/mark3d.gd")

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== MARK RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _step(node, seconds: float, dt := 0.1) -> void:
	var t := 0.0
	while t < seconds:
		node._process(dt)
		t += dt

func _run() -> void:
	_test_math()
	await _test_mark3d()
	await _test_mark_icon()
	await _test_view()
	await _test_ray()
	await _test_sync()
	await _test_wheel()

func _test_math() -> void:
	var d: Vector3 = Mark3dMathScript.arrow_dir_xz(Vector3(0, 1, 0), Vector3(0, 1, 5))
	_check("箭头方向 owner(+z)→center", d.is_equal_approx(Vector3(0, 0, -1)))
	_check("箭头方向退化回退", Mark3dMathScript.arrow_dir_xz(Vector3(0, 1, 0), Vector3(0, 1, 0)).is_equal_approx(Vector3.FORWARD))
	_check("on_table 内", Mark3dMathScript.on_table(Vector3(3, 1, 3), 3.8))
	_check("on_table 外", not Mark3dMathScript.on_table(Vector3(4, 1, 0), 3.8))
	_check("ring_scale 端点", is_equal_approx(Mark3dMathScript.ring_scale(0.0, 0.3, 2.0), 0.3) and is_equal_approx(Mark3dMathScript.ring_scale(1.0, 0.3, 2.0), 2.0))
	_check("ring_alpha 端点", is_equal_approx(Mark3dMathScript.ring_alpha(0.0, 0.8), 0.8) and is_equal_approx(Mark3dMathScript.ring_alpha(1.0, 0.8), 0.0))
	_check("wrap_phase", is_equal_approx(Mark3dMathScript.wrap_phase(1.25, 1.0), 0.25))
	_check("sector 上=eye", Mark3dMathScript.sector_for(Vector2(0, -1), 0.1, 1.0) == "eye")
	_check("sector 右=question", Mark3dMathScript.sector_for(Vector2(1, 0), 0.1, 1.0) == "question")
	_check("sector 下=number", Mark3dMathScript.sector_for(Vector2(0, 1), 0.1, 1.0) == "number")
	_check("sector 左=exclaim", Mark3dMathScript.sector_for(Vector2(-1, 0), 0.1, 1.0) == "exclaim")
	_check("sector 中空=''", Mark3dMathScript.sector_for(Vector2(0.02, 0), 0.1, 1.0) == "")
	_check("sector 超范围=''", Mark3dMathScript.sector_for(Vector2(2, 0), 0.1, 1.0) == "")

func _test_mark3d() -> void:
	var m = Mark3DScript.new()
	add_child(m)
	await get_tree().process_frame
	m.set_process(false)
	_check("构建两层环", m._rings.size() == 2)
	_check("有箭头与红眼", m._arrow != null and m._eye != null)
	m.setup(Vector3(1, 0, 0))
	_check("箭头对齐 owner 方向", absf(m._arrow.rotation.y - atan2(1.0, 0.0)) < 0.001)
	var s0: Vector3 = (m._rings[0] as Node3D).scale
	m._process(0.3)
	var s1: Vector3 = (m._rings[0] as Node3D).scale
	_check("波纹随时间扩散", not s0.is_equal_approx(s1))
	var done := [false]
	m.finished.connect(func(): done[0] = true)
	_step(m, Mark3DScript.LIFETIME + Mark3DScript.FADE_OUT + 0.2)
	_check("到时发出 finished", done[0])
	await get_tree().process_frame
	_check("到时释放节点", not is_instance_valid(m))

func _test_view() -> void:
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	view.show_mark(1, Vector3(1.0, Table3dLayout.TABLE_HEIGHT, 1.0))
	await get_tree().process_frame
	_check("show_mark 生成标记", view._marks.has(1) and is_instance_valid(view._marks[1]))
	var first = view._marks[1]
	view.show_mark(1, Vector3(2.0, Table3dLayout.TABLE_HEIGHT, 2.0))
	await get_tree().process_frame
	_check("同席替换标记", view._marks[1] != first and not is_instance_valid(first))
	_check("标记位于落点", (view._marks[1] as Node3D).global_position.distance_to(Vector3(2.0, Table3dLayout.TABLE_HEIGHT, 2.0)) < 0.02)
	# 按玩家颜色渲染
	view._last_state = {"players": [{"id": 1, "color": "#3ABA64"}]}
	view.show_mark(1, Vector3(0.5, Table3dLayout.TABLE_HEIGHT, 0.5))
	await get_tree().process_frame
	_check("标记用玩家颜色", (view._marks[1] as Node3D)._color.is_equal_approx(Color.html("#3ABA64")))
	view.render({
		"viewer_id": 0, "current_player": 1,
		"players": [
			{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2, "slots": [{"card_id": "c1"}]},
			{"id": 1, "name": "乙", "count": 2, "currency": 0, "health": 2, "slots": [{"card_id": "c2"}]},
		],
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 2,
	})
	await get_tree().process_frame
	view.show_mark(1, Vector3(0.5, Table3dLayout.TABLE_HEIGHT, 0.5), "nose", "question", "")
	await get_tree().process_frame
	var nm = view._marks[1]
	_check("nose 标记隐藏波纹", not (nm._rings[0] as Node3D).visible)
	var r1 = view._seat_nodes[1].get_node("Avatar").get_node("RobotAvatar")
	_check("nose 标记驱动该席鼻子", r1._nose_target_world.is_equal_approx(Vector3(0.5, Table3dLayout.TABLE_HEIGHT, 0.5)))
	view.clear_marks()
	_check("clear_marks 清空", view._marks.is_empty())
	view.queue_free()
	await get_tree().process_frame

func _test_ray() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(0, 5, 0), Vector3(0, 0, 0), Vector3.FORWARD)
	var center := get_viewport().get_visible_rect().size * 0.5
	var p: Vector3 = Table3dPicker.ray_plane_y(cam, center, 0.0)
	_check("射线命中桌面平面", p.is_finite() and absf(p.y) < 0.05)
	cam.look_at_from_position(Vector3(0, 5, 0), Vector3(1, 5, 0), Vector3.UP)
	var p2: Vector3 = Table3dPicker.ray_plane_y(cam, center, 0.0)
	_check("水平射线 → 非有限", not p2.is_finite())
	cam.queue_free()
	await get_tree().process_frame

func _test_sync() -> void:
	var got: Array = []
	var cb := func(seat, pos, style, icon, text): got.append([seat, pos, style, icon, text])
	GameState.mark_placed.connect(cb)
	GameState._apply_mark(2, Vector3(1, 1, 1), "ripple", "number", "5")
	_check("_apply_mark 5 参信号", got.size() == 1 and int(got[0][0]) == 2 and str(got[0][2]) == "ripple" and str(got[0][3]) == "number" and str(got[0][4]) == "5")
	GameState._apply_mark(3, Vector3(INF, 0, 0), "nose", "eye", "")
	_check("_apply_mark 非有限忽略", got.size() == 1)
	GameState.receive_mark(4, Vector3(2, 1, 3), "nose", "exclaim", "")
	_check("receive_mark 发信号", got.size() == 2 and str(got[1][3]) == "exclaim")
	GameState.mark_placed.disconnect(cb)

func _test_wheel() -> void:
	var w = load("res://scripts/ui/mark_wheel.gd").new()
	add_child(w)
	await get_tree().process_frame
	w.size = Vector2(1280, 760)   # 确保尺寸确定
	w.open(Vector2(400, 300), "5")
	var ro = w._outer_px()
	w.update_cursor(Vector2(400, 300 - ro * 0.7))
	_check("轮盘 上=eye", w.selected() == "eye")
	w.update_cursor(Vector2(400 + ro * 0.7, 300))
	_check("轮盘 右=question", w.selected() == "question")
	w.update_cursor(Vector2(400, 300 + ro * 0.7))
	_check("轮盘 下=number", w.selected() == "number")
	w.update_cursor(Vector2(400 - ro * 0.7, 300))
	_check("轮盘 左=exclaim", w.selected() == "exclaim")
	w.update_cursor(Vector2(400, 300))
	_check("轮盘 中空=''", w.selected() == "")
	_check("轮盘 数字文本", w._number_text == "5")
	w.close()
	_check("轮盘 close 隐藏", not w.visible)
	w.queue_free()
	await get_tree().process_frame

func _test_mark_icon() -> void:
	var m = Mark3DScript.new()
	add_child(m)
	await get_tree().process_frame
	m.set_process(false)
	m.setup(Vector3(1, 0, 0), "eye", "", true)
	_check("eye 用 Sprite3D", m._icon_kind == "eye" and m._eye.visible)
	m.setup(Vector3(1, 0, 0), "question", "", true)
	_check("question 用 Label3D ?", m._icon_kind == "question" and m._label.visible and m._label.text == "?")
	m.setup(Vector3(1, 0, 0), "exclaim", "", true)
	_check("exclaim 文本 !", m._label.text == "!")
	m.setup(Vector3(1, 0, 0), "number", "5", true)
	_check("number 文本 5", m._label.text == "5")
	m.setup(Vector3(1, 0, 0), "eye", "", false)
	_check("show_pointer=false 隐藏波纹/箭头", not (m._rings[0] as Node3D).visible and not m._arrow.visible)
	m.queue_free()
	await get_tree().process_frame
