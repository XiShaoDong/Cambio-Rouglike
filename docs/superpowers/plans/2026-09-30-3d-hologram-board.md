# 3D 全息看板（悬浮 UI 宿主）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 3D 模式下，把结算 / 商店 / Joker / 比拼 / 重连等 2D 模态与等待提示，从"贴相机的全屏 2D 层"改为牌桌中心上方、朝向玩家的半透明全息看板，交互走准星，相机保持可环视。

**Architecture:** 新增 `Board3d`（`Node3D`）作为宿主：内部一个 `SubViewport` 承载现有 `Control` 面板，输出贴到一块朝向相机的 `QuadMesh` 上；`main` 根据是否 3D 决定模态挂到看板还是 2D；准星每帧射线命中看板 → 用 `SubViewport.push_input()` 合成鼠标/键盘事件。坐标换算抽成纯函数 `BoardInput` 以便 headless 测试。

**Tech Stack:** Godot 4.6 / GDScript；headless 单元测试（`godot --headless --path . res://tests/xxx.tscn`）；既有 `Table3dPicker`（屏幕中心射线）与 `Table3dLayout.PICK_MASK`。

## Global Constraints

- **平台/版本**：Godot 4.6，macOS 引擎路径 `/Applications/Godot.app/Contents/MacOS/Godot`，项目路径 `~/dev/gameDev/cambio-rouglike/`。
- **分支**：`feature/3d-hologram-board`（已建）。
- **纯客户端展示层**：不改规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*`。
- **2D 路径逐字不动**：`game_view.gd` / `card_view.gd` / `card_animator.gd` / `reveal_controller.gd` / `scenes/ui/game_board.tscn` 不改；3D 未激活时行为与现状完全一致。
- **不启动 GUI**：全部用 headless 单测验证。
- **不新增第三方依赖**；不新增场景文件（`Board3d` 全代码构建，不改开发者拥有的 `scenes/ui/table3d.tscn`）。
- **命名**：新 `class_name` 为 `BoardInput`、`Board3d`，避免与既有冲突。
- 每个任务结束必须通过其测试、单独提交（`feat`/`fix`/`doc` 前缀）。
- 关键复用接口：
  - `Table3dPicker.pick_hit(cam: Camera3D, world: World3D, screen_center: Vector2) -> Dictionary`（返回 `{"pick","collider","position"}`，未命中 `{}`）
  - `Table3dLayout.PICK_MASK == 2`
  - `Table3dCamera.camera_node() -> Camera3D`
  - `main` 现有：`_hint_for(phase: int, is_current: bool) -> String`、`overlay: Control`、`table3d: Node3D`

---

## 文件结构

| 文件 | 责任 | 变更 |
| --- | --- | --- |
| `scripts/ui/board_input.gd`（新） | 看板坐标纯换算（local↔uv↔viewport） | 创建 |
| `scripts/ui/board3d.gd`（新） | 看板宿主：SubViewport 承载面板、billboard quad、拾取、输入合成、banner | 创建 |
| `scripts/ui/main.gd` | 挂载路由 `_mount_modal`、恒定捕获、输入转发、banner 文本、F10 重挂回 2D | 修改 |
| `scripts/ui/shop_panel.gd` | `setup(..., dim := true)`；`dim=false` 隐藏 `Dim` | 修改 |
| `scripts/ui/duel_bar.gd` | `setup(..., dim := true)`；`dim=false` 不加全屏遮罩（命名 `Dim`） | 修改 |
| `tests/verify_board3d.gd` + `.tscn`（新） | 看板纯函数 + 宿主 + main 路由测试 | 创建 |
| `tools/run_all_tests.sh` | 纳入 `verify_board3d` | 修改 |
| `docs/功能实现文档.md` | 补 `board_input.gd` / `board3d.gd` 映射 | 修改 |

---

## Task 1: `BoardInput` 坐标纯函数

**Files:**
- Create: `scripts/ui/board_input.gd`
- Test: `tests/verify_board3d.gd`（新建，只含本任务的测试）+ `tests/verify_board3d.tscn`

**Interfaces:**
- Produces:
  - `BoardInput.local_to_uv(local: Vector3, size: Vector2) -> Vector2`
  - `BoardInput.uv_to_viewport(uv: Vector2, viewport_size: Vector2i) -> Vector2i`
  - `BoardInput.world_to_local(board_xform: Transform3D, world_pos: Vector3) -> Vector3`

- [ ] **Step 1: 写失败测试**

创建 `tests/verify_board3d.gd`：

```gdscript
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
```

创建 `tests/verify_board3d.tscn`：

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/verify_board3d.gd" id="1"]

[node name="VerifyBoard3d" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: 编译/运行报错（`BoardInput` 未定义）或 FAIL。

- [ ] **Step 3: 实现 `BoardInput`**

创建 `scripts/ui/board_input.gd`：

```gdscript
class_name BoardInput
extends RefCounted
## 全息看板坐标换算（纯函数，可 headless 测）。
## 约定：看板 local 为 quad 平面 XY 坐标（原点在中心，+X 右、+Y 上）；
## uv 左上为 (0,0)、右下为 (1,1)；viewport 为 SubViewport 像素坐标。

## local（XY 平面）→ uv（左上 0,0）。
static func local_to_uv(local: Vector3, size: Vector2) -> Vector2:
	return Vector2(
		(local.x + size.x * 0.5) / size.x,
		(size.y * 0.5 - local.y) / size.y)

## uv → SubViewport 像素坐标。
static func uv_to_viewport(uv: Vector2, viewport_size: Vector2i) -> Vector2i:
	return Vector2i(int(round(uv.x * float(viewport_size.x))), int(round(uv.y * float(viewport_size.y))))

## 世界坐标 → 看板 local（用看板全局变换的逆）。
static func world_to_local(board_xform: Transform3D, world_pos: Vector3) -> Vector3:
	return board_xform.affine_inverse() * world_pos
```

- [ ] **Step 4: 运行测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: `=== BOARD3D RESULT: 7/7 passed ===`，退出码 0。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/board_input.gd tests/verify_board3d.gd tests/verify_board3d.tscn
git commit -m "feat: 全息看板坐标纯函数 BoardInput + 测试骨架"
```

---

## Task 2: `Board3d` 宿主节点

**Files:**
- Create: `scripts/ui/board3d.gd`
- Test: `tests/verify_board3d.gd`（追加 `_test_board3d`）

**Interfaces:**
- Consumes: `BoardInput.*`（Task 1）、`Table3dPicker.pick_hit()`、`Table3dLayout.PICK_MASK`。
- Produces（`Board3d extends Node3D`）：
  - `mount_panel(control: Control) -> void`
  - `unmount_panel(control: Control) -> void`
  - `detach_all() -> Array`
  - `has_panel() -> bool`
  - `set_banner(text: String) -> void`
  - `set_facing(cam: Camera3D) -> void`
  - `hit_viewport_coord(cam: Camera3D) -> Vector2i`（未命中 `Vector2i(-1,-1)`）
  - `push_motion(pos: Vector2i, rel := Vector2.ZERO) -> void`
  - `push_motion_out() -> void`
  - `push_click(pos: Vector2i) -> void`
  - `push_key(event: InputEventKey) -> void`
  - `viewport() -> SubViewport`、`screen_mesh() -> MeshInstance3D`（测试访问器）
  - 常量：`BOARD_W=2.6`、`BOARD_H=1.8`、`BOARD_Y=1.6`、`BOARD_ALPHA=0.92`、`VIEWPORT_SIZE=Vector2i(1024,708)`

- [ ] **Step 1: 写失败测试（追加到 `tests/verify_board3d.gd`）**

把 `_run()` 改为：

```gdscript
func _run() -> void:
	await _test_board_input()
	await _test_board3d()
```

在文件末尾追加以内容：

```gdscript
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


class KeyCatcher extends Control:
	var events: Array = []
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey:
			events.append(event.keycode)
```

> 说明：`KeyCatcher` 是测试内的嵌套类，捕获送入 `SubViewport` 的键事件。

- [ ] **Step 2: 运行测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: 报错 `Board3d` 未定义 / FAIL。

- [ ] **Step 3: 实现 `Board3d`**

创建 `scripts/ui/board3d.gd`：

```gdscript
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
```

- [ ] **Step 4: 运行测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: 全部 PASS（`BOARD3D RESULT: 20/20 passed`），退出码 0。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/board3d.gd tests/verify_board3d.gd
git commit -m "feat: 全息看板宿主 Board3d（SubViewport + billboard quad + 拾取 + 输入合成）"
```

---

## Task 3: 面板去黑底参数（`shop_panel` / `duel_bar`）

**Files:**
- Modify: `scripts/ui/shop_panel.gd`（`setup` 加 `dim` 参数）
- Modify: `scripts/ui/duel_bar.gd`（`setup` 加 `dim` 参数 + 命名遮罩 `Dim`）
- Test: `tests/verify_board3d.gd`（追加 `_test_modals_dim`）

**Interfaces:**
- Produces:
  - `ShopPanel.setup(state: Dictionary, on_buy: Callable, on_skip: Callable, dim := true) -> void`
  - `DuelBar.setup(owner_main: Node, duel: Dictionary, on_stop: Callable, dim := true) -> void`

- [ ] **Step 1: 写失败测试**

把 `_run()` 改为：

```gdscript
func _run() -> void:
	await _test_board_input()
	await _test_board3d()
	await _test_modals_dim()
```

追加：

```gdscript
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: 报错 `setup` 参数不匹配 / FAIL。

- [ ] **Step 3a: 改 `shop_panel.gd`**

把签名与首行改为：

```gdscript
func setup(state: Dictionary, on_buy: Callable, on_skip: Callable, dim := true) -> void:
	_state = state
	_on_buy = on_buy
	_on_skip = on_skip
	get_node("Dim").visible = dim
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
```

（其余函数体逐字不动。）

- [ ] **Step 3b: 改 `duel_bar.gd`**

签名：

```gdscript
func setup(owner_main: Node, duel: Dictionary, on_stop: Callable, dim := true) -> void:
	main = owner_main
	_on_stop = on_stop
	_build_ui(duel, dim)
	_start_sweep()
```

`_build_ui` 签名与遮罩段：

```gdscript
func _build_ui(duel: Dictionary, dim := true) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var duration_ms := int(duel.get("duration_ms", 2000))
	var target := clampf(float(duel.get("target", 0.5)), 0.0, 1.0)
	var is_contestant: bool = int(duel.get("viewer_contestant", 0)) == 1

	# 全屏半透明遮罩（仅 2D；3D 看板模式不加）
	if dim:
		var overlay := ColorRect.new()
		overlay.name = "Dim"
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.color = Color(0, 0, 0, 0.55)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay)
```

（其余逐字不动；把原来创建 `dim` 变量的那段替换为上面 `overlay` 段，避免与参数 `dim` 同名。）

- [ ] **Step 4: 运行测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: 全部 PASS（`BOARD3D RESULT: 23/23 passed`），退出码 0。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/shop_panel.gd scripts/ui/duel_bar.gd tests/verify_board3d.gd
git commit -m "feat: 商店/比拼面板支持去黑底（3D 看板模式 dim=false）"
```

---

## Task 4: `main` 挂载路由 + 指针/输入转发 + banner + F10 重挂

**Files:**
- Modify: `scripts/ui/main.gd`
- Test: `tests/verify_board3d.gd`（追加 `_test_main_routing`）

**Interfaces:**
- Consumes: `Board3d.*`（Task 2）、`ShopPanel.setup(...,dim)`、`DuelBar.setup(...,dim)`（Task 3）。
- Produces（`main`）：
  - 字段 `board: Board3d = null`
  - `_ensure_board() -> void`、`_mount_modal(control: Control, parent_2d: Node = null) -> void`
  - `_board_has_panel() -> bool`、`_board_banner_text() -> String`
  - `_sync_table3d_pointer()` 在 3D 下恒定 `CAPTURED`、准星恒显示

- [ ] **Step 1: 写失败测试**

把 `_run()` 改为：

```gdscript
func _run() -> void:
	await _test_board_input()
	await _test_board3d()
	await _test_modals_dim()
	await _test_main_routing()
```

追加：

```gdscript
func _tournament_state() -> Dictionary:
	return {
		"phase": 2, "phase_name": "p", "viewer_id": 0, "current_player": 1, "current_name": "B",
		"players": [{"id": 0, "name": "A", "slots": [], "health": 2, "currency": 100, "count": 0,
			"ready": false, "eliminated": false}],
		"draw_count": 40, "discard": {}, "pending": {}, "run": {}, "match_number": 1,
		"result": {}, "event_log": [], "slap_open": false, "slap_rank": "",
		"slap_exchange_actor": 0, "kong_caller": -1, "ready_count": 0, "offline_players": [],
	}

func _test_main_routing() -> void:
	await get_tree().process_frame
	Network.is_host = true
	var main: Node = preload("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	main.latest_state = _tournament_state()
	main._set_table3d(true)
	await get_tree().process_frame
	_check("3D 下有 board 节点", main.board != null and is_instance_valid(main.board))

	main._open_shop_panel()
	await get_tree().process_frame
	_check("模态挂到看板 SubViewport", main.shop_panel.get_parent() == main.board.viewport())
	_check("board.has_panel()", main.board.has_panel())
	_check("有面板时 banner 文本为空", main._board_banner_text() == "")

	main.board.set_banner("等待其他玩家…")
	_check("无面板时 banner 可见", main.board.visible)

	main._set_table3d(false)
	await get_tree().process_frame
	_check("切回 2D 后模态重新挂到 main", main.shop_panel.get_parent() == main)
	main.queue_free()
```

- [ ] **Step 2: 运行测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: FAIL（`main.board` 为 null 等）。

- [ ] **Step 3a: `main` 新增字段与看板辅助**

在 `var table3d: Node3D = null` 附近加：

```gdscript
var board: Board3d = null
```

在 `_set_table3d` 之前新增：

```gdscript
## 确保看板存在（挂在 table3d 下，随 3D 世界显隐/释放）。
func _ensure_board() -> void:
	if board != null and is_instance_valid(board):
		return
	if table3d == null or not is_instance_valid(table3d):
		return
	board = Board3d.new()
	board.name = "HologramBoard"
	table3d.add_child(board)

## 模态挂载：3D 激活挂到看板，否则沿用 2D 父节点（默认 main）。
func _mount_modal(control: Control, parent_2d: Node = null) -> void:
	if _table3d_active:
		_ensure_board()
		if board != null and is_instance_valid(board):
			board.mount_panel(control)
			return
	(parent_2d if parent_2d != null else self).add_child(control)

func _board_has_panel() -> bool:
	return board != null and is_instance_valid(board) and board.has_panel()

## 看板等待提示文本：无面板时用当前 hint，其余情况为空。
func _board_banner_text() -> String:
	if _board_has_panel():
		return ""
	var phase := int(latest_state.get("phase", PHASE_LOBBY))
	if phase == PHASE_LOBBY:
		return ""
	var viewer := int(latest_state.get("viewer_id", 0))
	var current := int(latest_state.get("current_player", -1))
	return _hint_for(phase, viewer == current)
```

- [ ] **Step 3b: `_set_table3d` 接入看板与重挂**

在 `_set_table3d(true)` 分支里、`table3d.set_hud_buttons(...)` 之前插入 `_ensure_board()`；在 `_sync_table3d_pointer()` 之后加 banner 刷新：

```gdscript
		_ensure_board()
		table3d.set_hud_buttons(_hud_buttons())
		table3d.render(latest_state, interaction.card_actionable)
		_sync_table3d_pointer()
		if board != null and is_instance_valid(board):
			board.set_banner(_board_banner_text())
```

`_set_table3d(false)` 分支里，在 `table3d.clear_hover()`/`set_active(false)` 之后、`background.visible = true` 之前，把看板面板重挂回 2D：

```gdscript
		if board != null and is_instance_valid(board):
			for c in board.detach_all():
				if c != null and is_instance_valid(c):
					add_child(c)
			board.set_banner("")
```

- [ ] **Step 3c: 输入指针与转发**

把 `_sync_table3d_pointer()` 整体替换为：

```gdscript
## 3D 激活时恒定捕获鼠标（看板交互走准星），准星恒显示。
func _sync_table3d_pointer() -> void:
	if not _table3d_active:
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _crosshair != null and is_instance_valid(_crosshair):
		_crosshair.visible = true
```

把 `_input()` 整体替换为：

```gdscript
func _input(event: InputEvent) -> void:
	if not _table3d_active:
		return
	var board_panel := _board_has_panel()
	if event is InputEventKey and event.pressed and not event.echo:
		# F10/V 任何时候都可切回 2D（含看板面板打开时；面板会被重挂回 2D）。
		if event.keycode == KEY_F10 or event.keycode == KEY_V:
			_set_table3d(false)
			get_viewport().set_input_as_handled()
			return
		# 有看板面板时，Enter/Esc 交给面板（Joker/商店）；否则 Esc 退出 3D。
		if board_panel and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_ESCAPE):
			if board != null and is_instance_valid(board):
				board.push_key(event)
			get_viewport().set_input_as_handled()
			return
		if not board_panel and event.keycode == KEY_ESCAPE:
			_set_table3d(false)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		if table3d != null and is_instance_valid(table3d):
			table3d.camera.look(event.relative)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_table3d_click()
		get_viewport().set_input_as_handled()
```

把 `_table3d_click()` 改为（开头加看板分支）：

```gdscript
func _table3d_click() -> void:
	if table3d == null or not is_instance_valid(table3d):
		return
	if _board_has_panel():
		var coord := board.hit_viewport_coord(table3d.camera.camera_node())
		if coord.x >= 0:
			board.push_click(coord)
		return
	var pick: Dictionary = table3d.pick_center()
	match str(pick.get("kind", "")):
		"slot":
			interaction.on_card_pressed(int(pick.get("seat", 0)), int(pick.get("slot", -1)))
		"deck":
			_on_deck_pressed()
		"discard":
			_on_discard_pressed()
		"pending":
			_on_pending_action()
		"hud":
			_on_action(str(pick.get("action", "")))
```

- [ ] **Step 3d: `_process` 悬停与朝向**

把 `_process()` 整体替换为：

```gdscript
func _process(_delta: float) -> void:
	if not _table3d_active:
		return
	if table3d == null or not is_instance_valid(table3d):
		return
	if board != null and is_instance_valid(board):
		board.set_facing(table3d.camera.camera_node())
	if _board_has_panel():
		table3d.clear_hover()
		var coord := board.hit_viewport_coord(table3d.camera.camera_node())
		if coord.x >= 0:
			board.push_motion(coord)
			if _crosshair != null and is_instance_valid(_crosshair):
				_crosshair.set_active(true)
		else:
			board.push_motion_out()
			if _crosshair != null and is_instance_valid(_crosshair):
				_crosshair.set_active(false)
		return
	var on_target: bool = table3d.update_hover()
	if _crosshair != null and is_instance_valid(_crosshair):
		_crosshair.set_active(on_target)
```

- [ ] **Step 3e: 模态创建点改走 `_mount_modal`**

- `_open_settlement()`：`add_child(page)` → `_mount_modal(page)`（保留 `page.z_index = 100` 与 `page.name`）。
- `_open_shop_panel()`：`add_child(panel)` → `_mount_modal(panel)`；两处 `setup(...)` 末尾加 `, not _table3d_active`。
- `_open_joker_transform_panel()`：`add_child(panel)` → `_mount_modal(panel)`。
- `_render_duel()`：`overlay.add_child(_duel_panel)` → `_mount_modal(_duel_panel, overlay)`；`setup(self, duel, _on_slap_duel_stop)` → `setup(self, duel, _on_slap_duel_stop, not _table3d_active)`。
- `_show_reconnect_panel()`：`overlay.add_child(panel)` → `_mount_modal(panel, overlay)`。

> 注：重连面板是紧凑 `PanelContainer`（无 CenterContainer），在 3D 看板上会出现在视口左上角；v1 接受（重连是边缘场景），后续可加居中包装。

- [ ] **Step 3f: 删除已弃用的 `_table3d_modal_open()`**

`_table3d_modal_open()` 已无调用点，整段删除（避免与看板逻辑混淆）。若编译报"未使用"无妨，但直接删除更清晰。

- [ ] **Step 3g: `_on_state_updated` 刷新 banner**

在 `_on_state_updated()` 末尾 `_sync_table3d_pointer()` 之后加：

```gdscript
	if _table3d_active and board != null and is_instance_valid(board):
		board.set_banner(_board_banner_text())
```

- [ ] **Step 4: 运行测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: 全部 PASS（`BOARD3D RESULT: 29/29 passed`），退出码 0。

- [ ] **Step 5: 回归**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_settlement.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_shop.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_interaction.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_mouse.tscn
```
Expected: 各自末尾 `RESULT: n/n passed`，退出码 0。

- [ ] **Step 6: 提交**

```bash
git add scripts/ui/main.gd tests/verify_board3d.gd
git commit -m "feat: main 接入全息看板（模态改挂/准星转发/banner/F10 重挂回 2D）"
```

---

## Task 5: 全量回归脚本与文档

**Files:**
- Modify: `tools/run_all_tests.sh`
- Modify: `docs/功能实现文档.md`

- [ ] **Step 1: 纳入测试脚本**

在 `tools/run_all_tests.sh` 的单进程段落里（`run_single "table3d_exchange" ...` 之后、`run_single "hint" ...` 之前）加：

```bash
run_single "board3d"    res://tests/verify_board3d.tscn
```

- [ ] **Step 2: 更新功能实现文档**

在 `docs/功能实现文档.md` 的 UI 文件表（`card_atlas.gd` / `table3d_layout.gd` 等所在表）追加两行：

```
| `board_input.gd` | 全息看板坐标纯换算（local↔uv↔viewport） |
| `board3d.gd` | 3D 全息看板宿主：SubViewport 承载模态面板 + billboard quad + 准星拾取 + 输入合成 + 等待提示 |
```

- [ ] **Step 3: 运行一键全量回归**

Run: `tools/run_all_tests.sh`
Expected: 汇总 `== 汇总：n 过 / 0 败 ==`，退出码 0。若失败，按脚本打印的失败项修复后重跑（不要跳过 FAIL）。

- [ ] **Step 4: 提交**

```bash
git add tools/run_all_tests.sh docs/功能实现文档.md
git commit -m "doc: 全息看板纳入全量回归 + 功能实现文档映射"
```

---

## Task 6: 验收闸门（最终检查）

**Files:** 无（只做检查）

- [ ] **Step 1: 确认 2D 与核心文件零改动**

Run:
```bash
git diff --stat main...HEAD -- scripts/core scripts/net scripts/ui/game_view.gd scripts/ui/card_view.gd scripts/ui/card_animator.gd scripts/ui/reveal_controller.gd scenes/ui/table3d.tscn scenes/ui/game_board.tscn
```
Expected: 无输出（这些文件相对 `main` 零改动）。

- [ ] **Step 2: 确认新增/修改文件符合预期**

Run:
```bash
git diff --stat main...HEAD
```
Expected: 只包含 `board_input.gd`、`board3d.gd`、`main.gd`、`shop_panel.gd`、`duel_bar.gd`、`tests/verify_board3d.*`、`tools/run_all_tests.sh`、`docs/功能实现文档.md` 与两份设计/计划文档。

- [ ] **Step 3: 复跑一键全量**

Run: `tools/run_all_tests.sh`
Expected: `0 败`。

- [ ] **Step 4: 按仓库约定推送**

```bash
git push origin feature/3d-hologram-board
```

---

## 自检记录（写计划时已核对）

- **Spec 覆盖**：§2 `BoardInput`/`Board3d` → Task 1/2；§3 挂载路由 → Task 4 Step 3a/3e/3g；§4 输入转发 → Task 4 Step 3c/3d；§5 视觉布局 → Task 2 Step 3（`BOARD_W/H/Y/ALPHA`、光晕、no_depth_test）；§6 边界（F10 重挂、多面板 `_panels` 数组、切出 3D）→ Task 2/4；§7 测试 → 全任务；§8 文件清单 → 各任务；§9 参数 → Task 2 常量。
- **类型一致**：`local_to_uv/local_to_uv/uv_to_viewport/world_to_local`、`mount_panel/unmount_panel/detach_all/has_panel/set_banner/set_facing/hit_viewport_coord/push_motion/push_motion_out/push_click/push_key/viewport/screen_mesh` 在 Task 1–4 中名称与签名一致。
- **无占位符**：所有步骤含可运行代码或精确命令。
