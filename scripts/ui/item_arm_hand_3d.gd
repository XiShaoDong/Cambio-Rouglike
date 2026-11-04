class_name ItemArmHand3D
extends ItemHandArt
## 空格道具手牌的 3D 手臂手部：大臂袖口 → 手肘弯折 → 小臂斜向前 → 掌心朝相机的右手。
## 用透明 SubViewport 渲染，任意尺寸下清晰；复用 AvatarHand 的粗模手指。
## 注：assets/3Dmodels/iron_hand_prosthetic_arm_low.glb 是静态高模（无骨骼），
## 已放在项目内备用；本组件仍用可弯肘的程序化手臂。

const VIEW_SCALE := 2.0
const SLEEVE_COLOR := Color(0.20, 0.24, 0.34)
const DEFAULT_ARM_COLOR := Color(0.24, 0.30, 0.44)
const ARM_SHADER := preload("res://assets/shaders/arm_overlay_3d.gdshader")

# 俯视正交平面（x=屏幕右，z=屏幕下）；手在扇形卡下方，肘在右侧，形成 V。
const SHOULDER := Vector3(1.15, 0.10, 0.95)
const ELBOW := Vector3(0.85, 0.10, 0.25)
const WRIST := Vector3(0.02, 0.10, 0.42)

var _rect := Rect2()
var _vp: SubViewport
var _tex: TextureRect
var _cam: Camera3D
var _hand: AvatarHand
var _arm_mat: ShaderMaterial
var _hand_base := Transform3D()
var _body_color := DEFAULT_ARM_COLOR
var _selected := 0
var _count := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_build()


func _build() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "Viewport"
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.size = Vector2i(1040, 600)
	add_child(_vp)

	_tex = TextureRect.new()
	_tex.name = "Texture"
	_tex.texture = _vp.get_texture()
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_tex)

	_arm_mat = ShaderMaterial.new()
	_arm_mat.shader = ARM_SHADER
	_arm_mat.set_shader_parameter("albedo_color", _body_color)
	_arm_mat.set_shader_parameter("rim_strength", 0.22)
	_arm_mat.set_shader_parameter("light_dir_world", Vector3(-0.45, 0.82, 0.36))
	var sleeve := ShaderMaterial.new()
	sleeve.shader = ARM_SHADER
	sleeve.set_shader_parameter("albedo_color", SLEEVE_COLOR)
	sleeve.set_shader_parameter("rim_strength", 0.12)

	var root := Node3D.new()
	root.name = "Arm"
	_vp.add_child(root)
	# 大臂袖口（右下画面外 → 手肘）
	_add_segment(root, SHOULDER, ELBOW, 0.18, 0.13, sleeve)
	# 小臂（手肘 → 手腕）
	_add_segment(root, ELBOW, WRIST, 0.13, 0.085, _arm_mat)
	# 手腕护圈
	_add_segment(root, WRIST + (ELBOW - WRIST).normalized() * 0.05, WRIST, 0.10, 0.095, sleeve)

	_hand = AvatarHand.new()
	_hand.name = "Hand"
	root.add_child(_hand)
	_hand.set_material(_arm_mat)
	# 俯视：手指朝屏幕上方（-Z），掌心朝上（+Y，正对相机），拇指在左。
	_hand_base = Transform3D(Basis(
		Vector3(1, 0, 0),
		Vector3(0, 0, -1),
		Vector3(0, 1, 0)), WRIST)
	_hand.transform = _hand_base
	_hand.scale = Vector3.ONE * 3.0

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 1.20
	_cam.near = 0.05
	_cam.far = 5.0
	_cam.position = Vector3(0.0, 2.0, 0.0)
	_cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_vp.add_child(_cam)
	_cam.make_current()


func _add_segment(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, mat: Material) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = r1
	cyl.bottom_radius = r0
	cyl.height = a.distance_to(b)
	cyl.radial_segments = 20
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = mat
	var dir := (b - a).normalized()
	mi.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), (a + b) * 0.5)
	parent.add_child(mi)


func setup(rect: Rect2) -> void:
	_rect = rect
	position = rect.position
	size = rect.size
	if _vp != null:
		_vp.size = Vector2i(maxi(1, int(rect.size.x * VIEW_SCALE)), maxi(1, int(rect.size.y * VIEW_SCALE)))
	queue_redraw()


func play_open() -> void:
	visible = true
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	modulate.a = 1.0


func play_close(_immediate: bool) -> void:
	visible = false
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func set_selected_hint(index: int, count: int) -> void:
	_selected = index
	_count = count
	if _hand == null:
		return
	var dir := 0.0
	if count > 1:
		dir = (float(index) / float(maxi(count - 1, 1))) - 0.5
	_hand.transform = Transform3D(_hand_base.basis, _hand_base.origin + Vector3(dir * 0.02, 0.0, 0.0))


## 与玩家机体同色（ItemHandOverlay 会传入快照里的玩家颜色）。
func set_body_color(color: Color) -> void:
	_body_color = color
	if _arm_mat != null:
		_arm_mat.set_shader_parameter("albedo_color", color)


func viewport() -> SubViewport:
	return _vp


## 桌面接触阴影：按投影把淡黑椭圆画在 3D 图下面（Control 自身绘制先于子节点）。
func _draw() -> void:
	if _cam == null or _vp == null:
		return
	var vp_size := Vector2(_vp.size)
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return
	var scale := _rect.size / vp_size
	var pts := [WRIST, (WRIST + ELBOW) * 0.5, ELBOW]
	for p in pts:
		var sp: Vector2 = _cam.unproject_position(p) * scale
		for i in 3:
			draw_circle(sp, 16.0 - i * 4.0, Color(0.0, 0.0, 0.0, 0.05))
