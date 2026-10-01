class_name Board3d
extends Node3D
## 3D 全息看板宿主：把 2D Control 面板渲染到 SubViewport，再贴到朝向相机的半透明 quad。
## 纯客户端展示层：不改规则/协议/快照；交互由 main 用准星射线 → push_input 合成事件驱动。

const BOARD_W := 2.6
const BOARD_H := 1.8
const BOARD_Y := 1.6
const BOARD_ALPHA := 0.92
const VIEWPORT_SIZE := Vector2i(1024, 708)
const HALO_MARGIN := 0.08
const HALO_COLOR := Color(0.42, 0.72, 0.95, 0.35)

var _viewport: SubViewport
var _screen: MeshInstance3D
var _pick: Area3D
var _banner_host: Control
var _banner: Label
var _panels: Array = []
var _pending_release: InputEventMouseButton = null

func _ready() -> void:
	_build()

func _build() -> void:
	if _viewport != null:
		return
	position = Vector3(0.0, BOARD_Y, 0.0)
	visible = false

	_viewport = SubViewport.new()
	_viewport.name = "Viewport"
	_viewport.size = VIEWPORT_SIZE
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	# 等待提示（无面板时显示）
	_banner_host = CenterContainer.new()
	_banner_host.name = "BannerHost"
	_banner_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.75)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	style.border_color = HALO_COLOR
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	_banner = Label.new()
	_banner.name = "Banner"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	panel.add_child(_banner)
	_banner_host.add_child(panel)
	_viewport.add_child(_banner_host)
	_banner_host.visible = false

	# 光晕底（比屏幕略大，营造全息边）
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	var halo_mesh := QuadMesh.new()
	halo_mesh.size = Vector2(BOARD_W + HALO_MARGIN, BOARD_H + HALO_MARGIN)
	halo.mesh = halo_mesh
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.albedo_color = HALO_COLOR
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_mat.no_depth_test = true
	halo.material_override = halo_mat
	halo.position = Vector3(0.0, 0.0, -0.01)
	add_child(halo)

	# 屏幕
	_screen = MeshInstance3D.new()
	_screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = Vector2(BOARD_W, BOARD_H)
	_screen.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, BOARD_ALPHA)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	_screen.material_override = mat
	add_child(_screen)

	# 拾取
	_pick = Area3D.new()
	_pick.name = "Pick"
	_pick.collision_layer = Table3dLayout.PICK_MASK
	_pick.collision_mask = 0
	_pick.set_meta("pick", {"kind": "board"})
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BOARD_W, BOARD_H, 0.02)
	shape.shape = box
	_pick.add_child(shape)
	add_child(_pick)

func viewport() -> SubViewport:
	return _viewport

func screen_mesh() -> MeshInstance3D:
	return _screen

func has_panel() -> bool:
	return _panels.size() > 0

## 把面板挂进看板视口（3D 模式）。
func mount_panel(control: Control) -> void:
	_build()
	if control == null:
		return
	var parent := control.get_parent()
	if parent != null and parent != _viewport:
		parent.remove_child(control)
	if control.get_parent() != _viewport:
		_viewport.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not _panels.has(control):
		_panels.append(control)
	_sync_visible()

## 从看板视口取出面板（不 free，由调用方决定去向）。
func unmount_panel(control: Control) -> void:
	_panels.erase(control)
	if control != null and is_instance_valid(control) and control.get_parent() == _viewport:
		_viewport.remove_child(control)
	_sync_visible()

## 取出全部面板并返回（切回 2D 时用）。
func detach_all() -> Array:
	var out: Array = _panels.duplicate()
	for c in out:
		unmount_panel(c)
	return out

func set_banner(text: String) -> void:
	_build()
	_banner.text = text
	_sync_visible()

func _sync_visible() -> void:
	if _banner_host != null:
		_banner_host.visible = not has_panel() and not _banner.text.is_empty()
	visible = has_panel() or (_banner != null and not _banner.text.is_empty())

## 每帧朝向相机（billboard）。用显式基让 quad 正面（+Z）朝相机，贴图不镜像。
func set_facing(cam: Camera3D) -> void:
	if cam == null:
		return
	var to_cam := cam.global_position - global_position
	if to_cam.length_squared() < 0.0001:
		return
	var fwd := to_cam.normalized()
	var right := Vector3.UP.cross(fwd)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := fwd.cross(right).normalized()
	var t := global_transform
	t.basis = Basis(right, up, fwd)
	global_transform = t

## 屏幕中心射线命中看板 → 返回视口像素坐标；未命中返回 (-1,-1)。
func hit_viewport_coord(cam: Camera3D) -> Vector2i:
	if cam == null or not visible:
		return Vector2i(-1, -1)
	var center := get_viewport().get_visible_rect().size * 0.5
	var hit := Table3dPicker.pick_hit(cam, get_world_3d(), center)
	if str(hit.get("pick", {}).get("kind", "")) != "board":
		return Vector2i(-1, -1)
	var local := BoardInput.world_to_local(global_transform, hit.get("position", Vector3.ZERO))
	var uv := BoardInput.local_to_uv(local, Vector2(BOARD_W, BOARD_H))
	return BoardInput.uv_to_viewport(uv, VIEWPORT_SIZE)

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
