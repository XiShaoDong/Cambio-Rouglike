extends Node
## headless 单元测试：2D 伪 3D 卡牌倾斜（纯数学 / 单应 / shader / 视图装配）。

var failures := 0
var checks := 0


func _ready() -> void:
	await _run()
	print("=== CARD TILT RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)


func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)


func _run() -> void:
	_test_angles()
	_test_projection()
	_test_homography()
	_test_lighting()
	await _test_shader_and_view()
	await _test_preset_and_card_view()


func _test_angles() -> void:
	var t := CardTiltMath.target_angles(Vector2(0.5, -0.5), 14.0)
	_check("target_angles 方向", is_equal_approx(t.x, 7.0) and is_equal_approx(t.y, -7.0))
	var clamped := CardTiltMath.target_angles(Vector2(3.0, -4.0), 14.0)
	_check("target_angles 钳制", is_equal_approx(clamped.x, 14.0) and is_equal_approx(clamped.y, -14.0))
	var neg := CardTiltMath.target_angles(Vector2(1.0, 0.0), -5.0)
	_check("target_angles 负上限归零", is_equal_approx(neg.x, 0.0))

	var start := Vector2(0.0, 0.0)
	var target := Vector2(10.0, 10.0)
	var same := CardTiltMath.smooth_angles(start, target, 10.0, 0.0)
	_check("smooth 零帧不变", same.is_equal_approx(start))
	var near := CardTiltMath.smooth_angles(start, target, 10.0, 1.0)
	_check("smooth 大帧收敛", near.distance_to(target) < 0.2)
	var step := CardTiltMath.smooth_angles(start, target, 10.0, 0.016)
	_check("smooth 单帧部分推进", step.x > 0.0 and step.x < target.x)
	var instant := CardTiltMath.smooth_angles(start, target, 0.0, 0.016)
	_check("smooth response=0 直达", instant.is_equal_approx(target))

	var basis := CardTiltMath.rotation_basis(0.0, 0.0)
	_check("rotation 零角=单位阵", basis.is_equal_approx(Basis()))


func _test_projection() -> void:
	var aspect := 1.4
	var flat := CardTiltMath.projected_quad(aspect, Basis(), 3.0, 1.8)
	var half_x := 0.5 / 1.8
	_check("静止左右对称", is_equal_approx(flat[0].x, 0.5 - half_x) and is_equal_approx(flat[1].x, 0.5 + half_x))
	_check("静止中心居中", is_equal_approx((flat[0].x + flat[2].x) * 0.5, 0.5))
	_check("静止上下对称", is_equal_approx(flat[0].y, flat[1].y) and is_equal_approx(flat[3].y, flat[2].y) and is_equal_approx((flat[0].y + flat[3].y) * 0.5, 0.5))
	_check("静止高度比例正确", is_equal_approx(flat[2].y - flat[0].y, 1.0 / 1.8))

	var yaw := CardTiltMath.projected_quad(aspect, CardTiltMath.rotation_basis(20.0, 0.0), 3.0, 1.8)
	_check("正 yaw 右边缘内收", yaw[1].x < flat[1].x)
	_check("正 yaw 左边缘几乎不动（收缩远小于右边缘）", (flat[0].x - yaw[0].x) < (flat[1].x - yaw[1].x) * 0.2)

	var pitch := CardTiltMath.projected_quad(aspect, CardTiltMath.rotation_basis(0.0, 20.0), 3.0, 1.8)
	_check("正 pitch 下边缘外扩", pitch[2].y > flat[2].y)
	_check("正 pitch 上边缘内收", pitch[0].y > flat[0].y)

	var side := CardTiltMath.project_point(Vector3(0.5, 0.0, 0.0), 3.0, 3.0)
	_check("project_point 静止", side.is_equal_approx(Vector2(0.5, 0.0)))
	var padded := CardTiltMath.padded_size(Vector2(100.0, 140.0), 1.8)
	_check("padded_size", padded.is_equal_approx(Vector2(180.0, 252.0)))


func _test_homography() -> void:
	var quad := CardTiltMath.projected_quad(1.4, CardTiltMath.rotation_basis(17.0, -12.0), 3.0, 1.8)
	var h := CardTiltMath.homography_unit_to_quad(quad)
	var src := PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)])
	var forward_ok := true
	for i in 4:
		var mapped := CardTiltMath.apply3(h, src[i])
		if mapped.distance_to(quad[i]) > 0.0005:
			forward_ok = false
	_check("单应 源角→目标角", forward_ok)

	var inv := CardTiltMath.invert3(h)
	var inverse_ok := true
	for i in 4:
		var mapped := CardTiltMath.apply3(inv, quad[i])
		if mapped.distance_to(src[i]) > 0.0005:
			inverse_ok = false
	_check("单应 逆 目标角→源角", inverse_ok)

	var center := CardTiltMath.apply3(inv, Vector2(0.5, 0.5))
	_check("逆映射 中心→中心", center.is_equal_approx(Vector2(0.5, 0.5)))

	var identity := CardTiltMath.invert3(PackedFloat64Array(CardTiltMath.IDENTITY_ROWS))
	_check("单位阵求逆", CardTiltMath.apply3(identity, Vector2(0.25, 0.75)).is_equal_approx(Vector2(0.25, 0.75)))

	var flat_quad := CardTiltMath.projected_quad(1.4, Basis(), 3.0, 1.8)
	var flat_inv := CardTiltMath.invert3(CardTiltMath.homography_unit_to_quad(flat_quad))
	var round_trip := CardTiltMath.apply3(flat_inv, flat_quad[1])
	_check("静止逆映射往返", round_trip.is_equal_approx(Vector2(1.0, 0.0)))


func _test_lighting() -> void:
	var normal := CardTiltMath.surface_normal(0.0, 0.0)
	_check("静止法线朝观察者", normal.is_equal_approx(Vector3(0.0, 0.0, 1.0)))
	var tilted := CardTiltMath.surface_normal(20.0, 0.0)
	_check("正 yaw 法线偏右", tilted.x > 0.0 and absf(tilted.length() - 1.0) < 0.0001)
	var light := CardTiltMath.light_direction()
	_check("光源方向已归一化", absf(light.length() - 1.0) < 0.0001)

	var far := CardTiltMath.inverse_uv_map(1.4, 89.0, 0.0, 3.0, 1.8)
	var finite := true
	for value in far:
		if not is_finite(value):
			finite = false
	_check("接近 90° 不产生 NaN", finite)


func _test_shader_and_view() -> void:
	var shader := load("res://assets/shaders/card_tilt.gdshader") as Shader
	_check("shader 可加载", shader != null)
	if shader != null:
		_check("shader 含逆映射 uniform", shader.code.contains("inv_row0") and shader.code.contains("card_normal"))

	var view := CardTiltView.new()
	add_child(view)
	await get_tree().process_frame
	var mat := view.material as ShaderMaterial
	_check("视图装配 ShaderMaterial", mat != null and mat.shader != null)
	view.set_pointer_normalized(Vector2(1.0, 1.0))
	await get_tree().process_frame
	_check("外部指针产生倾斜", absf(view.yaw_deg) > 0.0 or absf(view.pitch_deg) > 0.0)
	var tmp_path := "user://card_tilt_test_preset.cfg"
	view.max_tilt_deg = 7.0
	view.pad = 2.2
	view.gloss_tint = Color(1.0, 0.5, 0.25, 1.0)
	var saved_path := view.save_preset(tmp_path)
	_check("preset 保存返回路径", saved_path == tmp_path and FileAccess.file_exists(tmp_path))
	view.max_tilt_deg = 30.0
	view.pad = 1.0
	view.gloss_tint = Color.WHITE
	var restored := view.load_preset(tmp_path)
	_check("save/load preset 往返", restored and is_equal_approx(view.max_tilt_deg, 7.0) and is_equal_approx(view.pad, 2.2))
	_check("preset 保留 gloss_tint", view.gloss_tint.is_equal_approx(Color(1.0, 0.5, 0.25, 1.0)))
	_check("默认预设写在项目 res://", CardTiltView.PRESET_PATH.begins_with("res://"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	view.material = null
	view.queue_free()
	await get_tree().process_frame


func _test_preset_and_card_view() -> void:
	_check("默认预设常量在 res://", CardTiltPreset.PROJECT_PATH.begins_with("res://"))

	var preset_path := "user://card_tilt_preset_test.cfg"
	var values: Dictionary = CardTiltPreset.DEFAULTS.duplicate(true)
	values["max_tilt_deg"] = 11.0
	values["gloss_tint"] = Color(0.9, 0.4, 0.2, 1.0)
	var saved := CardTiltPreset.save_params(values, preset_path)
	var loaded := CardTiltPreset.load_params(preset_path)
	_check("CardTiltPreset save/load", saved == preset_path and is_equal_approx(float(loaded.get("max_tilt_deg", 0.0)), 11.0))
	_check("CardTiltPreset 颜色往返", (loaded.get("gloss_tint", Color.WHITE) as Color).is_equal_approx(Color(0.9, 0.4, 0.2, 1.0)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(preset_path))

	var card = load("res://scenes/ui/card.tscn").instantiate()
	add_child(card)
	await get_tree().process_frame
	var tex := card.get_node("Front/FrontTexture") as TextureRect
	_check("普通 CardView 不挂 tilt 材质", tex.material == null)
	card.setup({"rank": "A", "suit": "♠"})
	card.set_tilt_enabled(true)
	await get_tree().process_frame
	var mat := tex.material as ShaderMaterial
	_check("大牌 CardView 开启后挂 tilt 材质", mat != null and mat.shader != null)
	var canvas_pad := float(mat.get_shader_parameter("canvas_pad"))
	var rect_size := mat.get_shader_parameter("rect_size") as Vector2
	_check("CardView 画布按 pad 扩展", canvas_pad > 1.0 and rect_size.x > 0.0 and rect_size.y > 0.0)
	card.set_tilt_pointer(Vector2(1.0, 1.0))
	for i in 12:
		card._process(0.1)
	var angles: Vector2 = card.tilt_angles()
	_check("CardView 指针驱动倾斜", angles.x > 1.0 and angles.y > 0.0)
	var uniform_tilt := (mat.get_shader_parameter("tilt_deg") as Vector3)
	_check("CardView uniform 同步", absf(uniform_tilt.x - angles.x) < 0.001)
	card.queue_free()
	await get_tree().process_frame

	var plain := CardBlock.new()
	add_child(plain)
	plain.setup({"card": {"rank": "K", "suit": "♣"}})
	await get_tree().process_frame
	var bmat := plain._material as ShaderMaterial
	_check("3D 卡面统一使用 spatial 打光 shader", bmat != null and bmat.shader != null and bmat.shader.code.contains("gloss_strength"))
	_check("3D 光影固定（无 tilt uniform）", bmat != null and not bmat.shader.code.contains("tilt_amount"))
	_check("3D 卡面贴图走 shader 参数", bmat != null and bmat.get_shader_parameter("albedo_tex") != null)
	plain.queue_free()
	await get_tree().process_frame
