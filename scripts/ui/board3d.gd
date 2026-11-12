class_name Board3d
extends Node3D
## 3D billboard UI 宿主：把 2D Control 渲染到 SubViewport，再贴到朝向相机的半透明 quad。
## 纯客户端展示层：不改规则/协议/快照；交互由 main 用准星射线 → push_input 合成事件驱动。
## 支持多实例（模态大板 / 常驻提示板）：挂载后按面板内容 wrap 尺寸。

const PIXEL_SCALE := 0.0022          # 每个视口像素对应的世界单位
const WRAP_PADDING := Vector2i(24, 24)
const MIN_VIEWPORT := Vector2i(120, 56)
const PICK_PAD := Vector2(0.18, 0.18)  # 拾取盒比视觉尺寸外扩的世界单位（准星略偏也能命中）
const HALO_MARGIN := 0.06
const HALO_COLOR := Color(0.42, 0.72, 0.95, 0.35)
const BOARD_ALPHA := 0.96
const EDGE_GLOW := 0.14
const HOLO_COLOR := Color(0.435, 0.827, 1.0)
const SHADOW_ALPHA := 0.62
const CORNER_INSET := 0.07
const CORNER_THICK := 0.010
const DUST_AMOUNT := 18
const FLOAT_AMP := 0.010
const FLOAT_SPEED := 0.75
const GROUND_DEFAULT := 1.8

var _viewport: SubViewport
var _visual: Node3D
var _screen: MeshInstance3D
var _halo: MeshInstance3D
var _shadow: MeshInstance3D
var _shadow_mesh: QuadMesh
var _beam_a: MeshInstance3D
var _beam_b: MeshInstance3D
var _beam_mat: ShaderMaterial
var _ground: MeshInstance3D
var _ground_mesh: QuadMesh
var _corners: Array = []
var _corner_mat: StandardMaterial3D
var _dust: GPUParticles3D
var _pick: Area3D
var _pick_box: BoxShape3D
var _pick_shape: CollisionShape3D
var _panels: Array = []
var _pending_release: InputEventMouseButton = null
var _world_size := Vector2(0.6, 0.3)
var _viewport_size := MIN_VIEWPORT
var _time := 0.0
var halo_enabled := false  # 是否显示外圈光晕边框（默认关：面板/按钮只显示内容本身，不带外框）
var frame_enabled := true  # 圆角发光边：模态看板默认开，常驻提示板关（只显示按钮）
var pick_pad := PICK_PAD   # 拾取盒相对视觉尺寸的外扩量（提示板可加大，便于对准）
var ground_drop := GROUND_DEFAULT  # 看板底边到桌面的距离（光锥/地面辉光高度）

func _ready() -> void:
	_build()

func _build() -> void:
	if _viewport != null:
		return
	visible = false

	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.size = _viewport_size
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	# 视觉层单独挂一个节点：漂浮动画只动这里，根节点的锚点/拾取保持不变。
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	# 光晕底（比屏幕略大，营造全息边）
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	_halo.mesh = QuadMesh.new()
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.albedo_color = HALO_COLOR
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_mat.no_depth_test = true
	_halo.material_override = halo_mat
	_halo.position = Vector3(0.0, 0.0, -0.03)
	_halo.visible = halo_enabled
	_visual.add_child(_halo)

	# 背板：软边深色投影，给看板"厚度"与悬浮感。
	_shadow = MeshInstance3D.new()
	_shadow.name = "ShadowPlate"
	_shadow_mesh = QuadMesh.new()
	_shadow.mesh = _shadow_mesh
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, SHADOW_ALPHA)
	shadow_mat.albedo_texture = _make_radial_texture(0.55)
	shadow_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_shadow.material_override = shadow_mat
	_shadow.position = Vector3(0.0, 0.0, -0.02)
	_visual.add_child(_shadow)

	# 屏幕：细分曲面 + 全息 shader（圆角发光边/外发光/扫描线/轻微色差/顶点弧度）
	_screen = MeshInstance3D.new()
	_screen.name = "Screen"
	var screen_mesh := PlaneMesh.new()
	screen_mesh.orientation = PlaneMesh.FACE_Z
	screen_mesh.subdivide_width = 24
	screen_mesh.subdivide_depth = 16
	_screen.mesh = screen_mesh
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/board_holo.gdshader")
	mat.set_shader_parameter("board_tex", _viewport.get_texture())
	mat.set_shader_parameter("tint", Color(1.0, 1.0, 1.0, BOARD_ALPHA))
	mat.set_shader_parameter("edge_glow", EDGE_GLOW if frame_enabled else 0.0)
	_screen.material_override = mat
	_visual.add_child(_screen)

	_build_beam()
	_build_ground()
	_build_corners()
	_build_dust()

	# 拾取（薄盒随根旋转，射线命中即本板）
	_pick = Area3D.new()
	_pick.name = "Pick"
	_pick.collision_layer = Table3dLayout.PICK_MASK
	_pick.collision_mask = 0
	_pick.set_meta("pick", {"kind": "board"})
	var shape := CollisionShape3D.new()
	_pick_box = BoxShape3D.new()
	shape.shape = _pick_box
	shape.disabled = true   # 初始无面板 → 隐藏：拾取盒禁用
	_pick_shape = shape
	_pick.add_child(shape)
	add_child(_pick)

	_apply_size()
	_sync_extras()

func viewport() -> SubViewport:
	return _viewport

func screen_mesh() -> MeshInstance3D:
	return _screen

func world_size() -> Vector2:
	return _world_size

func viewport_size() -> Vector2i:
	return _viewport_size

func has_panel() -> bool:
	_prune_panels()
	return _panels.size() > 0

## 当前挂载的面板数量（供 main 判定"是否只有只读面板"）。
func panel_count() -> int:
	_prune_panels()
	return _panels.size()

## 清理已释放（queue_free 后）的面板条目，避免后续对已释放对象做类型化调用。
func _prune_panels() -> void:
	var live: Array = []
	for c in _panels:
		if c != null and is_instance_valid(c):
			live.append(c)
	_panels = live

## 把面板挂进看板视口（3D 模式），随后按内容自适应尺寸。
func mount_panel(control: Control) -> void:
	_build()
	if control == null:
		return
	_prune_panels()
	var parent := control.get_parent()
	if parent != null and parent != _viewport:
		parent.remove_child(control)
	if control.get_parent() != _viewport:
		_viewport.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not _panels.has(control):
		_panels.append(control)
	_sync_visible()
	call_deferred("wrap_to_content")

## 从看板视口取出面板（不 free，由调用方决定去向）。
func unmount_panel(control: Control) -> void:
	_panels.erase(control)
	if control != null and is_instance_valid(control) and control.get_parent() == _viewport:
		_viewport.remove_child(control)
	_sync_visible()

## 取出全部面板并返回（切回 2D 时用）。
func detach_all() -> Array:
	_prune_panels()
	var out: Array = _panels.duplicate()
	for c in out:
		unmount_panel(c)
	return out

## 按（最上层）面板内容最小尺寸调整视口与 quad 尺寸。
func wrap_to_content() -> void:
	_build()
	if _panels.is_empty():
		return
	var control: Control = _panels[_panels.size() - 1]
	var content := _content_min_size(control)
	_viewport_size = Vector2i(
		int(ceil(content.x)) + WRAP_PADDING.x,
		int(ceil(content.y)) + WRAP_PADDING.y).max(MIN_VIEWPORT)
	_apply_size()

func _content_min_size(control: Control) -> Vector2:
	if control == null or not is_instance_valid(control):
		return Vector2(MIN_VIEWPORT) / PIXEL_SCALE
	var pc := _find_panel_container(control)
	if pc != null:
		return pc.get_combined_minimum_size()
	var m := control.get_combined_minimum_size()
	return m if m != Vector2.ZERO else Vector2(MIN_VIEWPORT) / PIXEL_SCALE

func _find_panel_container(node: Node) -> PanelContainer:
	if node is PanelContainer:
		return node
	for c in node.get_children():
		var r := _find_panel_container(c)
		if r != null:
			return r
	return null

func _apply_size() -> void:
	if _viewport == null:
		return
	_viewport.size = _viewport_size
	_world_size = Vector2(_viewport_size) * PIXEL_SCALE
	(_screen.mesh as PlaneMesh).size = _world_size
	(_halo.mesh as QuadMesh).size = _world_size + Vector2(HALO_MARGIN, HALO_MARGIN) * 2.0
	_halo.visible = halo_enabled
	_pick_box.size = Vector3(_world_size.x + pick_pad.x, _world_size.y + pick_pad.y, 0.02)
	_layout_extras()

# ===== 全息增强层（背板 / 光锥 / 地面辉光 / 四角支架 / 尘埃） =====

## 径向渐变贴图：中心实、边缘透明。用于软边背板与地面辉光。
func _make_radial_texture(mid_alpha: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, mid_alpha))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	return t

## 光锥：一片上窄下宽的梯形；两片交叉摆放近似体积光。
func _make_beam_mesh(top_w: float, bottom_w: float, height: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array([
		Vector3(-top_w * 0.5, 0.0, 0.0),
		Vector3(top_w * 0.5, 0.0, 0.0),
		Vector3(bottom_w * 0.5, -height, 0.0),
		Vector3(-bottom_w * 0.5, -height, 0.0),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0),
	])
	var normals := PackedVector3Array([
		Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK,
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _build_beam() -> void:
	_beam_mat = ShaderMaterial.new()
	_beam_mat.shader = preload("res://assets/shaders/board_beam.gdshader")
	_beam_mat.set_shader_parameter("beam_color", HOLO_COLOR)
	_beam_mat.set_shader_parameter("beam_alpha", 0.16)
	_beam_mat.set_shader_parameter("side_softness", 0.28)
	_beam_a = MeshInstance3D.new()
	_beam_a.name = "BeamA"
	_beam_a.material_override = _beam_mat
	_beam_a.position = Vector3(0.0, 0.0, -0.012)
	_visual.add_child(_beam_a)
	_beam_b = MeshInstance3D.new()
	_beam_b.name = "BeamB"
	_beam_b.material_override = _beam_mat
	_beam_b.rotation_degrees.y = 90.0
	_beam_b.position = Vector3(0.0, 0.0, -0.012)
	_visual.add_child(_beam_b)

func _build_ground() -> void:
	_ground = MeshInstance3D.new()
	_ground.name = "GroundGlow"
	_ground_mesh = QuadMesh.new()
	_ground.mesh = _ground_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(HOLO_COLOR.r, HOLO_COLOR.g, HOLO_COLOR.b, 0.5)
	m.albedo_texture = _make_radial_texture(0.5)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_ground.material_override = m
	_ground.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_visual.add_child(_ground)

func _build_corners() -> void:
	_corner_mat = StandardMaterial3D.new()
	_corner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_corner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_corner_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_corner_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_corner_mat.albedo_color = Color(HOLO_COLOR.r, HOLO_COLOR.g, HOLO_COLOR.b, 0.9)
	for i in 8:
		var m := MeshInstance3D.new()
		m.name = "Corner%d" % i
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		m.mesh = q
		m.material_override = _corner_mat
		m.position.z = 0.006
		_visual.add_child(m)
		_corners.append(m)

func _build_dust() -> void:
	_dust = GPUParticles3D.new()
	_dust.name = "Dust"
	_dust.amount = DUST_AMOUNT
	_dust.lifetime = 5.0
	_dust.preprocess = 4.0
	_dust.local_coords = true
	_dust.emitting = false
	_dust.visibility_aabb = AABB(Vector3(-3.0, -3.0, -1.0), Vector3(6.0, 6.0, 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.5, 0.4, 0.05)
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 20.0
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.05
	pm.gravity = Vector3(0.0, 0.02, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	_dust.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.012)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.albedo_color = Color(HOLO_COLOR.r, HOLO_COLOR.g, HOLO_COLOR.b, 0.55)
	quad.material = dm
	_dust.draw_pass_1 = quad
	_dust.position = Vector3(0.0, 0.0, 0.05)
	_visual.add_child(_dust)

## 尺寸变化后重排所有增强层（背板/光锥/地面/四角/尘埃范围）。
func _layout_extras() -> void:
	if _visual == null:
		return
	var w := _world_size.x
	var h := _world_size.y
	if _shadow_mesh != null:
		_shadow_mesh.size = Vector2(w + 0.30, h + 0.30)
	if _ground_mesh != null:
		_ground_mesh.size = Vector2(w * 1.45, maxf(w * 0.55, h * 0.20))
	if _ground != null:
		_ground.position = Vector3(0.0, -h * 0.5 - ground_drop + 0.01, 0.0)
	if _beam_a != null and _beam_b != null:
		var beam_mesh := _make_beam_mesh(w * 0.92, w * 1.18, maxf(ground_drop, 0.2))
		_beam_a.mesh = beam_mesh
		_beam_b.mesh = beam_mesh
		_beam_a.position.y = -h * 0.5
		_beam_b.position.y = -h * 0.5
	if _dust != null and _dust.process_material is ParticleProcessMaterial:
		(_dust.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(w * 0.45, h * 0.45, 0.06)
	var hw := w * 0.5
	var hh := h * 0.5
	var arm := minf(0.16, w * 0.10)
	var idx := 0
	for sy: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			if idx + 1 >= _corners.size():
				return
			var cx := sx * (hw - CORNER_INSET)
			var cy := sy * (hh - CORNER_INSET)
			var horiz: MeshInstance3D = _corners[idx]
			idx += 1
			horiz.scale = Vector3(arm, CORNER_THICK, 1.0)
			horiz.position = Vector3(cx - sx * arm * 0.5, cy, 0.006)
			var vert: MeshInstance3D = _corners[idx]
			idx += 1
			vert.scale = Vector3(CORNER_THICK, arm, 1.0)
			vert.position = Vector3(cx, cy - sy * arm * 0.5, 0.006)

## 增强层显隐：常驻提示板（frame_enabled=false）只保留按钮本身。
func _sync_extras() -> void:
	var on := frame_enabled and visible
	if _shadow != null:
		_shadow.visible = on
	if _beam_a != null:
		_beam_a.visible = on
	if _beam_b != null:
		_beam_b.visible = on
	if _ground != null:
		_ground.visible = on
	for c in _corners:
		if c != null and is_instance_valid(c):
			c.visible = on
	if _dust != null:
		_dust.emitting = on

func _sync_visible() -> void:
	visible = _panels.size() > 0
	# 隐藏时禁用拾取盒：否则隐藏看板仍参与射线，会抢走其他看板（同锚点）的命中
	#（表现为"看得到按钮但 hover/点击不生效"，B46）。
	if _pick_shape != null:
		_pick_shape.disabled = not visible
	_sync_extras()

## 外部按需显隐（如提示板无按钮时隐藏）：显隐必须同时同步拾取盒，
## 否则隐藏后拾取盒仍启用（同层），会挡住其他看板（商店等）的命中。
func set_shown(on: bool) -> void:
	visible = on
	if _pick_shape != null:
		_pick_shape.disabled = not on
	_sync_extras()

## 面板内容尺寸变化（如结算页逐轮新增排名行）时自动重新 wrap，避免内容被裁。
func _process(delta: float) -> void:
	_time += delta
	# 漂浮只动视觉层，根节点（锚点）保持不动；常驻提示板不漂浮，保持按钮稳定。
	if _visual != null:
		if visible and frame_enabled:
			_visual.position.y = sin(_time * FLOAT_SPEED) * FLOAT_AMP
		elif _visual.position.y != 0.0:
			_visual.position.y = 0.0
	if _panels.is_empty():
		return
	var control = _panels[_panels.size() - 1]
	if control == null or not is_instance_valid(control):
		_prune_panels()  # 顶部条目已释放：清理，避免下次重复访问
		return
	var content := _content_min_size(control)
	var want := Vector2i(
		int(ceil(content.x)) + WRAP_PADDING.x,
		int(ceil(content.y)) + WRAP_PADDING.y).max(MIN_VIEWPORT)
	if want != _viewport_size:
		wrap_to_content()

## 显隐外圈光晕边框（提示板的纯按钮面板可关闭，只显示按钮本身）。
func set_halo_enabled(on: bool) -> void:
	halo_enabled = on
	if _halo != null and is_instance_valid(_halo):
		_halo.visible = on

## 显隐圆角发光边（常驻提示板关闭，只保留按钮）。
func set_frame_enabled(on: bool) -> void:
	frame_enabled = on
	if _screen != null:
		var m := _screen.material_override as ShaderMaterial
		if m != null:
			m.set_shader_parameter("edge_glow", EDGE_GLOW if on else 0.0)
	_sync_extras()

## 看板底边到桌面的距离（决定光锥高度与地面辉光位置）。
func set_ground_drop(v: float) -> void:
	ground_drop = maxf(0.2, v)
	_layout_extras()

## 设置拾取盒外扩量（提示板可加大，让准星略偏也能命中按钮）。
func set_pick_pad(p: Vector2) -> void:
	pick_pad = p
	if _pick_box != null:
		_apply_size()

## 只绕世界 Y 朝向相机（**完全竖直**，不含俯仰）。+Y = 世界 up，+Z 水平指向相机，贴图不镜像。
func set_facing(cam: Camera3D) -> void:
	if cam == null:
		return
	var to_cam := cam.global_position - global_position
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.0001:
		return
	var fwd := to_cam.normalized()
	var up := Vector3.UP
	var right := up.cross(fwd)
	if right.length_squared() < 0.0001:
		return
	right = right.normalized()
	var t := global_transform
	t.basis = Basis(right, up, fwd)
	global_transform = t

## 屏幕中心射线命中本看板 → 返回视口像素坐标；未命中返回 (-1,-1)。
func hit_viewport_coord(cam: Camera3D) -> Vector2i:
	if cam == null or not visible:
		return Vector2i(-1, -1)
	var center := get_viewport().get_visible_rect().size * 0.5
	var hit := Table3dPicker.pick_hit(cam, get_world_3d(), center)
	if hit.get("collider") != _pick:
		return Vector2i(-1, -1)
	# 用屏幕层（含漂浮位移）换算，保证视觉位置与点击映射一致。
	var plane_tf := global_transform
	if _screen != null and is_instance_valid(_screen):
		plane_tf = _screen.global_transform
	var local := BoardInput.world_to_local(plane_tf, hit.get("position", Vector3.ZERO))
	var uv := BoardInput.local_to_uv(local, _world_size)
	# 拾取盒比视觉略大：边缘命中也归本板，坐标夹到视口内，避免掉给牌桌做 hover。
	var coord := BoardInput.uv_to_viewport(uv, _viewport_size)
	coord.x = clampi(coord.x, 0, _viewport_size.x - 1)
	coord.y = clampi(coord.y, 0, _viewport_size.y - 1)
	return coord

func push_motion(pos: Vector2i, rel := Vector2.ZERO) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(pos)
	ev.relative = rel
	_viewport.push_input(ev, true)

func push_motion_out() -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(-1000, -1000)
	ev.relative = Vector2.ZERO
	_viewport.push_input(ev, true)

## 合成一次左键点击（按下立即、抬起延迟一帧，确保按钮收到完整 press→release）。
func push_click(pos: Vector2i) -> void:
	var dn := InputEventMouseButton.new()
	dn.button_index = MOUSE_BUTTON_LEFT
	dn.pressed = true
	dn.position = Vector2(pos)
	_viewport.push_input(dn, true)
	_pending_release = InputEventMouseButton.new()
	_pending_release.button_index = MOUSE_BUTTON_LEFT
	_pending_release.pressed = false
	_pending_release.position = Vector2(pos)
	call_deferred("_flush_release")

func _flush_release() -> void:
	if _pending_release != null:
		_viewport.push_input(_pending_release, true)
		_pending_release = null

func push_key(event: InputEventKey) -> void:
	if event == null:
		return
	_viewport.push_input(event.duplicate(), true)

## 该视口像素坐标是否位于某个带 meta("board_interactive") 的可见控件矩形内。
## 用于手册/Stats/按键页的"部分穿透"：命中可交互控件才接管点击，其余穿透到牌桌。
func interactive_at(coord: Vector2i) -> bool:
	_prune_panels()
	var p := Vector2(coord)
	for panel in _panels:
		if _interactive_hit(panel, p):
			return true
	return false

func _interactive_hit(node: Node, p: Vector2) -> bool:
	if node is Control:
		var c := node as Control
		if c.visible and bool(c.get_meta("board_interactive", false)) and c.get_global_rect().has_point(p):
			return true
	for child in node.get_children():
		if _interactive_hit(child, p):
			return true
	return false
