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
const BOARD_ALPHA := 0.94

var _viewport: SubViewport
var _screen: MeshInstance3D
var _halo: MeshInstance3D
var _pick: Area3D
var _pick_box: BoxShape3D
var _pick_shape: CollisionShape3D
var _panels: Array = []
var _pending_release: InputEventMouseButton = null
var _world_size := Vector2(0.6, 0.3)
var _viewport_size := MIN_VIEWPORT
var halo_enabled := false  # 是否显示外圈光晕边框（默认关：面板/按钮只显示内容本身，不带外框）
var pick_pad := PICK_PAD   # 拾取盒相对视觉尺寸的外扩量（提示板可加大，便于对准）

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
	_halo.position = Vector3(0.0, 0.0, -0.01)
	_halo.visible = halo_enabled
	add_child(_halo)

	# 屏幕
	_screen = MeshInstance3D.new()
	_screen.name = "Screen"
	_screen.mesh = QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, BOARD_ALPHA)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	_screen.material_override = mat
	add_child(_screen)

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
	(_screen.mesh as QuadMesh).size = _world_size
	(_halo.mesh as QuadMesh).size = _world_size + Vector2(HALO_MARGIN, HALO_MARGIN) * 2.0
	_halo.visible = halo_enabled
	_pick_box.size = Vector3(_world_size.x + pick_pad.x, _world_size.y + pick_pad.y, 0.02)

func _sync_visible() -> void:
	visible = _panels.size() > 0
	# 隐藏时禁用拾取盒：否则隐藏看板仍参与射线，会抢走其他看板（同锚点）的命中
	#（表现为"看得到按钮但 hover/点击不生效"，B46）。
	if _pick_shape != null:
		_pick_shape.disabled = not visible

## 外部按需显隐（如提示板无按钮时隐藏）：显隐必须同时同步拾取盒，
## 否则隐藏后拾取盒仍启用（同层），会挡住其他看板（商店等）的命中。
func set_shown(on: bool) -> void:
	visible = on
	if _pick_shape != null:
		_pick_shape.disabled = not on

## 面板内容尺寸变化（如结算页逐轮新增排名行）时自动重新 wrap，避免内容被裁。
func _process(_delta: float) -> void:
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
	var local := BoardInput.world_to_local(global_transform, hit.get("position", Vector3.ZERO))
	var uv := BoardInput.local_to_uv(local, _world_size)
	return BoardInput.uv_to_viewport(uv, _viewport_size)

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
