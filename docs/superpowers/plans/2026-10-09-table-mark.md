# 桌面标记（波纹 ping）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 3D 对局按 D 在准星指向的桌面位置放置一个同步标记：两层声呐波纹 + 内圈箭头（尖端指圆心、朝向=标记者→圆心）+ 上方程序化红眼 billboard，3 秒自动消失；由设置「鼻子点击」选择风格（开=鼻子 / 关=波纹，默认波纹）。

**Architecture:** 纯客户端展示层。新增 `Mark3D`（节点）+ `Mark3dMath`（纯函数）渲染标记；`Table3dPicker.ray_plane_y` 求桌面交点；`Table3dView.show_mark()` 生成/替换；新增表现层事件 RPC `server_mark`→`receive_mark` + `mark_placed` 信号广播；`main` 按设置分派 D。

**Tech Stack:** Godot 4.6 / GDScript；headless 场景测试。

## Global Constraints

- 引擎 Godot 4.6（`/Applications/Godot.app/Contents/MacOS/Godot`），headless。
- **纯展示层**：不改规则/状态机/快照/`HiddenInfo`/`scripts/net/*`；`game_state.gd` 仅新增表现层 RPC + 信号（不入快照）。
- 不改 `scenes/ui/table3d.tscn`、`assets/characters/source/Robot.blend`、2D 渲染文件。
- 跨文件引用新脚本一律用 `preload` 常量（避免全局类缓存未更新导致 headless 报错）。
- 标记只在 3D 生效；2D 下 D 无效。
- `Settings.gameplay.nose_click` 语义：`true`=鼻子风格、`false`=波纹风格（默认 false）。
- 参数：`MARK_LIFETIME=3.0`、`FADE_OUT=0.3`、`PERIOD=1.2`、`MARK_COLOR=#ff3b3b`、`TABLE_RADIUS=Table3dLayout.TABLE_RADIUS`。

---

## File Structure

| 文件 | 职责 |
| --- | --- |
| `scripts/ui/mark3d_math.gd`（新增） | 纯函数：箭头方向 / 桌内判定 / 波纹相位 |
| `scripts/ui/mark3d.gd`（新增） | 标记节点（两层波纹 + 箭头 + 红眼 + 生命周期） |
| `scripts/ui/table3d_picker.gd`（改） | `ray_plane_y` 射线-水平面求交 |
| `scripts/ui/table3d_view.gd`（改） | `show_mark`/`clear_marks` |
| `scripts/core/game_state.gd`（改） | `mark_placed` 信号 + `server_mark`/`_apply_mark`/`receive_mark` |
| `scripts/ui/main.gd`（改） | D 风格分派、射线落点、发送、显示 |
| `tests/verify_mark.gd`/`.tscn`（新增） | 纯函数/节点/视图/同步/拾取 |
| `tools/run_all_tests.sh`（改） | 注册 `mark` |
| docs × 4（改） | 记录标记功能 |

---

### Task 1: `Mark3dMath` 纯函数

**Files:**
- Create: `scripts/ui/mark3d_math.gd`
- Create: `tests/verify_mark.gd`
- Create: `tests/verify_mark.tscn`
- Modify: `tools/run_all_tests.sh`

**Interfaces:**
- Produces: `class_name Mark3dMath extends RefCounted`；`arrow_dir_xz(center, owner) -> Vector3`；`on_table(pos, radius) -> bool`；`ring_scale(phase, base, max_scale) -> float`；`ring_alpha(phase, peak) -> float`；`wrap_phase(t, period) -> float`。

- [ ] **Step 1: 写失败测试** — 创建 `tests/verify_mark.gd`：

```gdscript
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

func _test_math() -> void:
	var d: Vector3 = Mark3dMathScript.arrow_dir_xz(Vector3(0, 1, 0), Vector3(0, 1, 5))
	_check("箭头方向 owner(+z)→center", d.is_equal_approx(Vector3(0, 0, -1)))
	_check("箭头方向退化回退", Mark3dMathScript.arrow_dir_xz(Vector3(0, 1, 0), Vector3(0, 1, 0)).is_equal_approx(Vector3.FORWARD))
	_check("on_table 内", Mark3dMathScript.on_table(Vector3(3, 1, 3), 3.8))
	_check("on_table 外", not Mark3dMathScript.on_table(Vector3(4, 1, 0), 3.8))
	_check("ring_scale 端点", is_equal_approx(Mark3dMathScript.ring_scale(0.0, 0.3, 2.0), 0.3) and is_equal_approx(Mark3dMathScript.ring_scale(1.0, 0.3, 2.0), 2.0))
	_check("ring_alpha 端点", is_equal_approx(Mark3dMathScript.ring_alpha(0.0, 0.8), 0.8) and is_equal_approx(Mark3dMathScript.ring_alpha(1.0, 0.8), 0.0))
	_check("wrap_phase", is_equal_approx(Mark3dMathScript.wrap_phase(1.25, 1.0), 0.25))
```

创建 `tests/verify_mark.tscn`：
```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/verify_mark.gd" id="1"]
[node name="VerifyMark" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 运行确认失败**
Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_mark.tscn`
Expected: 解析失败（`mark3d_math.gd` 不存在）。

- [ ] **Step 3: 实现 `scripts/ui/mark3d_math.gd`**

```gdscript
class_name Mark3dMath
extends RefCounted
## 桌面标记（波纹 ping）纯函数，headless 可测。

## 从 owner 指向 center 的水平（XZ）单位方向（owner→center）；退化回退 +Z。
static func arrow_dir_xz(center: Vector3, owner: Vector3) -> Vector3:
	var d := Vector3(center.x - owner.x, 0.0, center.z - owner.z)
	if d.length_squared() < 0.000001:
		return Vector3.FORWARD
	return d.normalized()

## 落点是否在桌面范围内（正方形 |x|,|z| <= radius）。
static func on_table(pos: Vector3, radius: float) -> bool:
	return absf(pos.x) <= radius and absf(pos.z) <= radius

## 相位 -> 环缩放。
static func ring_scale(phase: float, base: float, max_scale: float) -> float:
	return lerpf(base, max_scale, clampf(phase, 0.0, 1.0))

## 相位 -> 环透明度（向外扩散同时淡出）。
static func ring_alpha(phase: float, peak: float) -> float:
	return peak * (1.0 - clampf(phase, 0.0, 1.0))

## 归一化循环相位。
static func wrap_phase(t: float, period: float) -> float:
	if period <= 0.0:
		return 0.0
	return fmod(t, period) / period
```

- [ ] **Step 4: 注册 + 运行**
`tools/run_all_tests.sh` 在 `run_single "nose" ...` 之后加：
```bash
run_single "mark" res://tests/verify_mark.tscn
```
Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_mark.tscn`
Expected: `=== MARK RESULT: 7/7 passed ===`

- [ ] **Step 5: 提交**
```bash
git add scripts/ui/mark3d_math.gd tests/verify_mark.gd tests/verify_mark.tscn tools/run_all_tests.sh
git commit -m "feat: 桌面标记纯函数 Mark3dMath + headless 测试脚手架"
```

---

### Task 2: `Mark3D` 节点（波纹 + 箭头 + 红眼）

**Files:**
- Create: `scripts/ui/mark3d.gd`
- Modify: `tests/verify_mark.gd`

**Interfaces:**
- Consumes: `Mark3dMath`。
- Produces: `class_name Mark3D extends Node3D`；常量 `LIFETIME`/`FADE_OUT`；`setup(owner_dir: Vector3)`；`set_color(c: Color)`；`signal finished`；成员 `_rings`/`_arrow`/`_eye`。

- [ ] **Step 1: 写失败测试** — 在 `tests/verify_mark.gd` 的 `_run()` 里加 `await _test_mark3d()`，并新增：

```gdscript
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
```

- [ ] **Step 2: 运行确认失败**
Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_mark.tscn`
Expected: FAIL（`Mark3D` 未定义 / `mark3d.gd` 不存在）。

- [ ] **Step 3: 实现 `scripts/ui/mark3d.gd`**

```gdscript
class_name Mark3D
extends Node3D
## 桌面标记（波纹 ping）：两层向外扩散的圆环 + 内圈箭头（尖端指向圆心）+ 上方红色眼睛 billboard。
## 纯客户端展示层；存活 MARK_LIFETIME 秒后淡出并发出 finished。本地 +Z = 指向圆心。

signal finished

const Mark3dMathScript := preload("res://scripts/ui/mark3d_math.gd")

const LIFETIME := 3.0
const FADE_OUT := 0.3
const PERIOD := 1.2
const RING_INNER := 0.28
const RING_OUTER := 0.34
const RING_BASE_SCALE := 0.35
const RING_MAX_SCALE := 2.4
const RING_PEAK_ALPHA := 0.85
const ARROW_RADIUS := 0.30
const EYE_HEIGHT := 0.5
const EYE_TEX := Vector2i(96, 64)
const MARK_COLOR := Color("ff3b3b")

var _rings: Array = []
var _ring_mats: Array = []
var _arrow: Node3D
var _eye: Sprite3D
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
		tm.rings = 8
		tm.ring_segments = 48
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := _unlit(_color)
		mi.material_override = mat
		add_child(mi)
		_rings.append(mi)
		_ring_mats.append(mat)
	_arrow = Node3D.new()
	_arrow.position = Vector3(0, 0.002, 0)
	add_child(_arrow)
	var shaft := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.012, ARROW_RADIUS)
	shaft.mesh = bm
	shaft.position = Vector3(0, 0, ARROW_RADIUS * 0.5)
	shaft.material_override = _unlit(_color)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.add_child(shaft)
	var head := MeshInstance3D.new()
	head.mesh = _head_mesh()
	head.position = Vector3(0, 0, ARROW_RADIUS)
	head.material_override = _unlit(_color)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.add_child(head)
	_eye = Sprite3D.new()
	_eye.texture = _eye_texture(_color)
	_eye.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_eye.no_depth_test = true
	_eye.pixel_size = 0.006
	_eye.position = Vector3(0, EYE_HEIGHT, 0)
	_eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_eye)

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

## 扁平三角箭头（+Z 尖），位于 XZ 平面。
func _head_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var w := 0.10
	var l := 0.12
	st.add_vertex(Vector3(-w, 0, -l))
	st.add_vertex(Vector3(w, 0, -l))
	st.add_vertex(Vector3(0, 0, l))
	return st.commit()

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

## 由 owner→center 水平方向设定内圈箭头朝向。
func setup(owner_dir: Vector3) -> void:
	_build()
	var d := Vector3(owner_dir.x, 0.0, owner_dir.z)
	if d.length_squared() < 0.000001:
		d = Vector3.FORWARD
	d = d.normalized()
	_arrow.rotation.y = atan2(d.x, d.z)

func set_color(c: Color) -> void:
	_build()
	_color = c
	for m in _ring_mats:
		(m as StandardMaterial3D).albedo_color = c
		(m as StandardMaterial3D).emission = c
	if _eye != null:
		_eye.texture = _eye_texture(c)

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
```

- [ ] **Step 4: 运行确认通过**
Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_mark.tscn`
Expected: `=== MARK RESULT: 13/13 passed ===`

- [ ] **Step 5: 提交**
```bash
git add scripts/ui/mark3d.gd tests/verify_mark.gd
git commit -m "feat: Mark3D 标记节点（两层波纹+内圈箭头+红眼 billboard+生命周期）"
```

---

### Task 3: 拾取射线-平面 + `Table3dView.show_mark`

**Files:**
- Modify: `scripts/ui/table3d_picker.gd`
- Modify: `scripts/ui/table3d_view.gd`
- Modify: `tests/verify_mark.gd`

**Interfaces:**
- Consumes: `Mark3D`、`Mark3dMath`。
- Produces: `Table3dPicker.ray_plane_y(cam, screen_center, plane_y) -> Vector3`（失败返回 `Vector3.INF`）；`Table3dView.show_mark(seat_id, pos) -> void`；`Table3dView.clear_marks() -> void`；成员 `_marks`。

- [ ] **Step 1: 写失败测试** — `_run()` 里加 `await _test_view()` 与 `await _test_ray()`（后者见 Task 内代码），新增：

```gdscript
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
```

- [ ] **Step 2: 运行确认失败**
Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_mark.tscn`
Expected: FAIL（`show_mark`/`ray_plane_y` 未定义）。

- [ ] **Step 3: 改 `scripts/ui/table3d_picker.gd`**（在 `pick` 之后追加）

```gdscript
## 屏幕中心射线与水平面 y=plane_y 的交点；|dir.y| 过小或 t<=0 返回 Vector3.INF。
static func ray_plane_y(cam: Camera3D, screen_center: Vector2, plane_y: float) -> Vector3:
	if cam == null:
		return Vector3.INF
	var origin := cam.project_ray_origin(screen_center)
	var dir := cam.project_ray_normal(screen_center)
	if absf(dir.y) < 0.000001:
		return Vector3.INF
	var t := (plane_y - origin.y) / dir.y
	if t <= 0.0:
		return Vector3.INF
	return origin + dir * t
```

- [ ] **Step 4: 改 `scripts/ui/table3d_view.gd`**

顶部 preload 区（`NoseAvatarScript` 附近）加：
```gdscript
const Mark3DScript := preload("res://scripts/ui/mark3d.gd")
const Mark3dMathScript := preload("res://scripts/ui/mark3d_math.gd")
```
成员区加：
```gdscript
var _marks := {}  # seat -> Mark3D（桌面标记，独立节点、跨 render 保留）
```
`set_active(on)` 关闭分支改为：
```gdscript
	if not on:
		_clear_exchange_anim()
		clear_local_nose()
		clear_marks()
```
在 `clear_hover()` 之后新增：
```gdscript
## ===== 桌面标记（波纹 ping）=====
## 在 pos 生成标记；同席已有则替换。owner 方向由该席座位世界坐标推出。
func show_mark(seat_id: int, pos: Vector3) -> void:
	_bind()
	if not _bound or not pos.is_finite():
		return
	var old = _marks.get(seat_id)
	if old != null and is_instance_valid(old):
		old.queue_free()
	var mark = Mark3DScript.new()
	var owner_pos := Vector3.ZERO
	var seat_node = _seat_node_by_id.get(seat_id)
	if seat_node != null and is_instance_valid(seat_node):
		owner_pos = (seat_node as Node3D).global_position
	add_child(mark)
	mark.global_position = pos
	mark.setup(Mark3dMathScript.arrow_dir_xz(pos, owner_pos))
	mark.finished.connect(func():
		if _marks.get(seat_id) == mark:
			_marks.erase(seat_id))
	_marks[seat_id] = mark

func clear_marks() -> void:
	for s in _marks.keys():
		var m = _marks[s]
		if m != null and is_instance_valid(m):
			m.queue_free()
	_marks.clear()
```

- [ ] **Step 5: 运行确认通过**
Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_mark.tscn`
Expected: `=== MARK RESULT: 19/19 passed ===`

- [ ] **Step 6: 回归**
Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: `76/76 passed`

- [ ] **Step 7: 提交**
```bash
git add scripts/ui/table3d_picker.gd scripts/ui/table3d_view.gd tests/verify_mark.gd
git commit -m "feat: 射线-桌面求交 + Table3dView.show_mark/clear_marks"
```

---

### Task 4: `GameState` 标记同步

**Files:**
- Modify: `scripts/core/game_state.gd`
- Modify: `tests/verify_mark.gd`

**Interfaces:**
- Produces: `signal mark_placed(seat, pos)`；`server_mark(pos)`；`_apply_mark(seat, pos)`；`receive_mark(seat, pos)`。

- [ ] **Step 1: 写失败测试** — `_run()` 里加 `await _test_sync()`，新增：

```gdscript
func _test_sync() -> void:
	var got: Array = []
	var cb := func(seat, pos): got.append([seat, pos])
	GameState.mark_placed.connect(cb)
	GameState._apply_mark(2, Vector3(1, 1, 1))
	_check("_apply_mark 发信号", got.size() == 1 and int(got[0][0]) == 2 and (got[0][1] as Vector3).is_equal_approx(Vector3(1, 1, 1)))
	GameState._apply_mark(3, Vector3(INF, 0, 0))
	_check("_apply_mark 非有限忽略", got.size() == 1)
	GameState.receive_mark(4, Vector3(2, 1, 3))
	_check("receive_mark 发信号", got.size() == 2 and (got[1][1] as Vector3).is_equal_approx(Vector3(2, 1, 3)))
	GameState.mark_placed.disconnect(cb)
```

- [ ] **Step 2: 运行确认失败**
Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_mark.tscn`
Expected: FAIL（`mark_placed` 未定义）。

- [ ] **Step 3: 改 `scripts/core/game_state.gd`**（在 `receive_look` 之后追加；信号加在文件顶部 signal 区）

```gdscript
signal mark_placed(seat: int, pos: Vector3)

## ===== 桌面标记（纯表现层，不入快照）=====
@rpc("any_peer", "call_remote", "reliable")
func server_mark(pos: Vector3) -> void:
	var seat := _peer_to_seat(multiplayer.get_remote_sender_id())
	if seat < 0:
		return
	_apply_mark(seat, pos)

## 服务器权威应用标记：本地发信号（房主可见）+ 转发给其他客户端。
func _apply_mark(seat: int, pos: Vector3) -> void:
	if not pos.is_finite():
		return
	mark_placed.emit(seat, pos)
	for s in players.keys():
		var peer := int(players[s].peer_id)
		if peer > 1:
			receive_mark.rpc_id(peer, seat, pos)

@rpc("authority", "call_remote", "reliable")
func receive_mark(seat: int, pos: Vector3) -> void:
	mark_placed.emit(seat, pos)
```

- [ ] **Step 4: 运行确认通过**
Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_mark.tscn`
Expected: `=== MARK RESULT: 22/22 passed ===`

- [ ] **Step 5: 回归**
Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_protocol.tscn`
Expected: `51/51 passed`

- [ ] **Step 6: 提交**
```bash
git add scripts/core/game_state.gd tests/verify_mark.gd
git commit -m "feat: 桌面标记表现层同步 server_mark/receive_mark + mark_placed 信号"
```

---

### Task 5: `main.gd` D 分派与显示

**Files:**
- Modify: `scripts/ui/main.gd`

**Interfaces:**
- Consumes: `Table3dPicker.ray_plane_y`、`Mark3dMath.on_table`、`GameState.server_mark`/`_apply_mark`/`mark_placed`、`Table3dView.show_mark`。
- Produces: D 键触发标记（无可供后续消费的公开接口）。

- [ ] **Step 1: 连接信号** — `main._ready()` 中（与其它 `GameState.*.connect` 并列）加：
```gdscript
	GameState.mark_placed.connect(_on_mark_placed)
```

- [ ] **Step 2: 新增分派与显示**（在 `_nose_enabled()` 之后）：

```gdscript
## D 触发标记：按设置分派风格（开=鼻子，关=波纹）。
func _on_mark_click() -> void:
	if _nose_enabled():
		_on_nose_click()
		return
	if table3d == null or not is_instance_valid(table3d):
		return
	if _board_has_panel() or _settings_open():
		return
	var cam: Camera3D = table3d.camera.camera_node()
	if cam == null:
		return
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var pos: Vector3 = Table3dPicker.ray_plane_y(cam, center, Table3dLayout.TABLE_HEIGHT)
	if not pos.is_finite():
		return
	if not Mark3dMath.on_table(pos, Table3dLayout.TABLE_RADIUS):
		return
	var seat := int(latest_state.get("viewer_id", -1))
	if seat < 0:
		return
	if multiplayer.is_server():
		GameState._apply_mark(seat, pos)
	else:
		GameState.server_mark.rpc_id(1, pos)

## 收到标记（自己/他人）→ 3D 下显示。
func _on_mark_placed(seat: int, pos: Vector3) -> void:
	if _table3d_active and table3d != null and is_instance_valid(table3d):
		table3d.show_mark(seat, pos)
```

- [ ] **Step 3: D 触发 + 移除中键** — 把 `_input` 里：
```gdscript
		# D / 鼠标中键：鼻子指针（悬停卡牌时伸出，再按缩回）
		if event.keycode == KEY_D:
			_on_nose_click()
			get_viewport().set_input_as_handled()
			return
```
改为：
```gdscript
		# D：标记（按设置分派：开=鼻子，关=波纹）
		if event.keycode == KEY_D:
			_on_mark_click()
			get_viewport().set_input_as_handled()
			return
```
并删除鼠标中键分支：
```gdscript
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		_on_nose_click()
		get_viewport().set_input_as_handled()
		return
```

- [ ] **Step 4: 编译 + 回归**
Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . --quit-after 5`
Expected: 退出码 0、无 SCRIPT ERROR / Parse Error。
Run:
```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_mark.tscn
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_nose.tscn
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_table3d_interaction.tscn
```
Expected: 分别 22/22、31/31、76/76。

- [ ] **Step 5: 提交**
```bash
git add scripts/ui/main.gd
git commit -m "feat: D 按风格分派标记；波纹标记按准星落点生成并显示"
```

---

### Task 6: 文档与全量验收

**Files:**
- Modify: `docs/网络协议_V1.md`、`docs/3D角色与场景说明.md`、`docs/功能实现文档.md`、`docs/AI_AGENT_交接说明.md`

- [ ] **Step 1: `网络协议_V1.md`** — §3 请求表加 `mark` 行（`{pos: Vector3}`，任意对局中，纯表现层，`pos` 须有限，不入快照）；§4.8 后加「4.9 桌面标记 `mark`」小节（`server_mark`→`receive_mark`，事件式、无状态存储）。
- [ ] **Step 2: `3D角色与场景说明.md`** — 新增「4.10 桌面标记（D）」，说明波纹/箭头/红眼/3s/同步/风格分派/桌内判定；参数表加 `MARK_*`。
- [ ] **Step 3: `功能实现文档.md` / `AI_AGENT_交接说明.md`** — 各补一条标记功能（D、风格、同步、测试 `verify_mark`）；文件地图加 `mark3d.gd`/`mark3d_math.gd`/`verify_mark.*`；验证命令加 `res://tests/verify_mark.tscn`。
- [ ] **Step 4: 全量回归** — `tools/run_all_tests.sh` → 汇总全 PASS。
- [ ] **Step 5: 提交**
```bash
git add docs/网络协议_V1.md docs/3D角色与场景说明.md docs/功能实现文档.md docs/AI_AGENT_交接说明.md
git commit -m "doc: 记录桌面标记（波纹 ping）与 mark 表现层 RPC"
```

---

## Self-Review

**1. Spec coverage**：波纹两层扩散→Task 2；内圈箭头指向/朝向→Task 1+2+3；红眼 billboard→Task 2；D 触发/风格分派→Task 5；射线桌面交点/桌内→Task 3+5；同步所有人→Task 4；3s 消失/替换→Task 2+3；设置语义→Task 5；测试/文档→Task 1-6。

**2. Placeholder scan**：无 TBD；代码步骤均给完整代码。

**3. Type consistency**：`show_mark(seat_id, pos)`（Task 3/5）；`Mark3dMath` 函数签名（Task 1/2/3）；`mark_placed(seat,pos)`（Task 4/5）；`setup(owner_dir)`（Task 2/3）；`LIFETIME`（Task 2/3）。

**已知取舍**：中键不再是触发键（仅 D）；标记事件不持久化（3s 生命周期，切 2D 期间到达的事件丢弃）。
