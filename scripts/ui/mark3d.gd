class_name Mark3D
extends Node3D
## 桌面标记（波纹 ping）：两层向外扩散的圆环 + 内圈箭头（尖端指向圆心）+ 上方红色眼睛 billboard。
## 纯客户端展示层；存活 MARK_LIFETIME 秒后淡出并发出 finished。本地 +Z = 指向圆心。

signal finished

const Mark3dMathScript := preload("res://scripts/ui/mark3d_math.gd")

const LIFETIME := 3.0
const FADE_OUT := 0.3
const PERIOD := 1.2
const RING_INNER := 0.20
const RING_OUTER := 0.2333  # 半径在"手牌宽一半(0.35)"基础上缩小 1/3
const RING_BASE_SCALE := 1.0
const RING_MAX_SCALE := 2.2
const RING_PEAK_ALPHA := 0.85
const MARK_LIFT := 0.10    # 抬离桌面，使标记显示在卡牌上方
const CHEVRON_ARM := 0.18  # 箭头臂长（从圆心向后）
const CHEVRON_HALF_W := 0.12
const CHEVRON_THICK := 0.04
const EYE_HEIGHT := 0.5
const EYE_TEX := Vector2i(96, 64)
const MARK_COLOR := Color("ff3b3b")

var _rings: Array = []
var _ring_mats: Array = []
var _arrow: Node3D
var _arrow_mats: Array = []
var _eye: Sprite3D
var _label: Label3D
var _icon_kind := "eye"
var _color: Color = MARK_COLOR
var _t := 0.0
var _done := false

func _ready() -> void:
	_build()
	_apply(0.0, 1.0)

func _build() -> void:
	if not _rings.is_empty():
		return
	for i in 2:
		var tm := TorusMesh.new()
		tm.inner_radius = RING_INNER
		tm.outer_radius = RING_OUTER
		tm.rings = 96          # 主圆切分（越高越圆，消除八边形感）
		tm.ring_segments = 24  # 管截面切分
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.position = Vector3(0, MARK_LIFT, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := _unlit(_color)
		mi.material_override = mat
		add_child(mi)
		_rings.append(mi)
		_ring_mats.append(mat)
	_arrow = Node3D.new()
	_arrow.position = Vector3(0, MARK_LIFT, 0)
	add_child(_arrow)
	# 无长方形杆：仅一个"∧"形箭头，顶点在圆心（本地原点），两臂向后（-Z）张开。
	var chevron := MeshInstance3D.new()
	chevron.mesh = _chevron_mesh()
	chevron.position = Vector3.ZERO
	var amat := _unlit(_color)
	chevron.material_override = amat
	chevron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.add_child(chevron)
	_arrow_mats.append(amat)
	_eye = Sprite3D.new()
	_eye.texture = _eye_texture(_color)
	_eye.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_eye.no_depth_test = true
	_eye.pixel_size = 0.006
	_eye.position = Vector3(0, EYE_HEIGHT, 0)
	_eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_eye)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.004
	_label.font_size = 64
	_label.outline_size = 8
	_label.outline_modulate = Color(0, 0, 0, 0.6)
	_label.position = Vector3(0, EYE_HEIGHT, 0)
	_label.visible = false
	add_child(_label)

func _unlit(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## "∧"形（翻过来的 V）箭头，顶点在本地原点（圆心），两臂沿 -Z 向后、±X 张开，位于 XZ 平面。
func _chevron_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	_add_bar(st, Vector3.ZERO, Vector3(-CHEVRON_HALF_W, 0, -CHEVRON_ARM))
	_add_bar(st, Vector3.ZERO, Vector3(CHEVRON_HALF_W, 0, -CHEVRON_ARM))
	return st.commit()

## 一段有厚度的斜杆（XZ 平面内的细四边形）。
func _add_bar(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var dir := (b - a).normalized()
	var perp := Vector3(dir.z, 0, -dir.x) * (CHEVRON_THICK * 0.5)
	st.add_vertex(a - perp)
	st.add_vertex(b - perp)
	st.add_vertex(b + perp)
	st.add_vertex(a - perp)
	st.add_vertex(b + perp)
	st.add_vertex(a + perp)

## 程序化红眼贴图（眼白/红虹膜/瞳孔/高光）。
func _eye_texture(c: Color) -> ImageTexture:
	var img := Image.create(EYE_TEX.x, EYE_TEX.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := EYE_TEX.x / 2
	var cy := EYE_TEX.y / 2
	_ellipse(img, cx, cy, int(EYE_TEX.x * 0.46), int(EYE_TEX.y * 0.42), c.lightened(0.25))
	_ellipse(img, cx, cy, int(EYE_TEX.y * 0.34), int(EYE_TEX.y * 0.34), c)
	_ellipse(img, cx, cy, int(EYE_TEX.y * 0.16), int(EYE_TEX.y * 0.16), Color(0.05, 0.0, 0.0))
	_ellipse(img, cx - int(EYE_TEX.y * 0.12), cy - int(EYE_TEX.y * 0.12), 4, 4, Color(1, 1, 1, 0.9))
	return ImageTexture.create_from_image(img)

func _ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, col: Color) -> void:
	if rx <= 0 or ry <= 0:
		return
	for y in range(maxi(0, cy - ry), mini(img.get_height(), cy + ry + 1)):
		for x in range(maxi(0, cx - rx), mini(img.get_width(), cx + rx + 1)):
			var nx := float(x - cx) / float(rx)
			var ny := float(y - cy) / float(ry)
			if nx * nx + ny * ny <= 1.0:
				img.set_pixel(x, y, col)

## 由 owner→center 水平方向设定内圈箭头朝向；并设定图标与是否显示波纹/箭头。
func setup(owner_dir: Vector3, icon := "eye", text := "", show_pointer := true) -> void:
	_build()
	var d := Vector3(owner_dir.x, 0.0, owner_dir.z)
	if d.length_squared() < 0.000001:
		d = Vector3.FORWARD
	d = d.normalized()
	_arrow.rotation.y = atan2(d.x, d.z)
	_icon_kind = icon
	for r in _rings:
		(r as Node3D).visible = show_pointer
	_arrow.visible = show_pointer
	_eye.visible = icon == "eye"
	_label.visible = icon != "eye"
	match icon:
		"question":
			_label.text = "?"
		"exclaim":
			_label.text = "!"
		"number":
			_label.text = text if not text.is_empty() else "-1"
		_:
			_label.text = ""

func set_color(c: Color) -> void:
	_build()
	_color = c
	for m in _ring_mats:
		(m as StandardMaterial3D).albedo_color = c
		(m as StandardMaterial3D).emission = c
	for m in _arrow_mats:
		(m as StandardMaterial3D).albedo_color = c
		(m as StandardMaterial3D).emission = c
	if _eye != null:
		_eye.texture = _eye_texture(c)
	if _label != null:
		_label.modulate = c

func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	var fade := 1.0
	if _t > LIFETIME:
		fade = clampf(1.0 - (_t - LIFETIME) / FADE_OUT, 0.0, 1.0)
	_apply(_t, fade)
	if _eye != null:
		_eye.position.y = EYE_HEIGHT + sin(_t * 3.0) * 0.05
		if _label != null:
			_label.position.y = EYE_HEIGHT + sin(_t * 3.0) * 0.05
		_eye.modulate.a = fade
	if _t >= LIFETIME + FADE_OUT:
		_done = true
		finished.emit()
		queue_free()

func _apply(t: float, fade: float) -> void:
	for i in _rings.size():
		var phase: float = Mark3dMathScript.wrap_phase(t / PERIOD + float(i) * 0.5, 1.0)
		var sc: float = Mark3dMathScript.ring_scale(phase, RING_BASE_SCALE, RING_MAX_SCALE)
		(_rings[i] as Node3D).scale = Vector3(sc, 1.0, sc)
		var a: float = Mark3dMathScript.ring_alpha(phase, RING_PEAK_ALPHA) * fade
		(_ring_mats[i] as StandardMaterial3D).albedo_color = Color(_color.r, _color.g, _color.b, a)
