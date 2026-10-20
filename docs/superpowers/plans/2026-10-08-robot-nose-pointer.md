# Robot 鼻子指针（中键伸缩）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 3D 对局的 Robot 角色加一个"鼻子"，准星悬停卡牌时按鼠标中键（或 D 键）让该玩家角色的鼻子沿头部朝向前伸到卡牌距离、再次按中键/D 键缩回，所有玩家（含本机第一人称）可见。

**Architecture:** 纯客户端展示层。新增可复用 `NoseAvatar`（程序化圆锥 + 伸缩状态机）；远程席鼻子挂在各席 `RobotAvatar` 骨架下、每帧按 Head 骨骼姿势定位（随头）；本机鼻子挂在相机上（第一人称）。长度经既有 `look` 表现层通道（新增可选 `nose` 字段）同步，方向由已同步的注视点在各客户端确定性推出。

**Tech Stack:** Godot 4.6 / GDScript；headless 场景测试（`tests/*.tscn` + `verify_*.gd`）。

## Global Constraints

- 引擎：Godot 4.6（`/Applications/Godot.app/Contents/MacOS/Godot`），headless 测试。
- **纯展示层**：不改规则 / 状态机 / 快照 / `HiddenInfo` / `scripts/net/*`；`scripts/core/game_state.gd` 仅新增 `remote_nose` 与 `look` 的可选 `nose` 参数（不入快照）。
- 不改 `scenes/ui/table3d.tscn`（节点名/路径契约，开发者所有）、不改 `assets/characters/source/Robot.blend`。
- 2D 路径零改动。
- 新脚本 `class_name NoseAvatar`；跨文件引用一律用 `preload` 常量（避免全局类缓存未更新导致 headless 报错）。
- 时长固定语义：`NOSE_DURATION = 0.35s` 内从 `from_len` 线性到 `target_len`（远则速度快）。
- 长度一律以**世界单位**存储/同步；`RobotAvatar` 内部按 `SCALE` 折算到骨架局部。
- 新增/改动脚本后若出现 `Identifier "X" not declared`，需让编辑器重扫文件系统（打开编辑器或触发扫描）后再跑 headless。

---

## File Structure

| 文件 | 职责 |
| --- | --- |
| `scripts/ui/nose_avatar.gd`（新增） | 单条鼻子的程序化几何 + 伸缩状态机（IDLE/EXTENDING/EXTENDED/RETRACTING） |
| `scripts/ui/robot_avatar.gd`（改） | 在骨架下建鼻子、每帧按 Head 姿势摆位（随头）、世界↔局部长度折算、颜色同步 |
| `scripts/ui/table3d_view.gd`（改） | hover 缓存世界位置/kind、`hovered_card_world()`、`update_noses()`、本机相机鼻子 |
| `scripts/core/game_state.gd`（改） | `remote_nose` + `look` 可选 `nose` 参数（表现层） |
| `scripts/ui/main.gd`（改） | 中键分支、`_on_nose_click()`、本地目标、每帧下发、`look` 携带 nose |
| `tests/verify_nose.gd` / `.tscn`（新增） | 状态机 / 长度折算 / 随头 / 同步 / 本机可见 / 非卡牌不触发 |
| `tools/run_all_tests.sh`（改） | 注册 `nose` 单进程测试 |
| `docs/网络协议_V1.md`、`docs/3D角色与场景说明.md`、`docs/功能实现文档.md`、`docs/AI_AGENT_交接说明.md`（改） | 记录功能与协议扩展 |

---

### Task 1: `NoseAvatar` 核心（程序化圆锥 + 伸缩状态机）

**Files:**
- Create: `scripts/ui/nose_avatar.gd`
- Create: `tests/verify_nose.gd`
- Create: `tests/verify_nose.tscn`
- Modify: `tools/run_all_tests.sh`（在 `robot_avatar` 之后加一行）

**Interfaces:**
- Consumes: 无。
- Produces: `class_name NoseAvatar extends Node3D`；`set_target(len: float) -> void`；`length() -> float`；`is_active() -> bool`；`state_name() -> String`；`set_color(c: Color) -> void`；常量 `NOSE_BASE_RADIUS` / `NOSE_TIP_RADIUS` / `NOSE_DURATION` / `NOSE_COLOR`。

- [ ] **Step 1: 写失败测试**

创建 `tests/verify_nose.gd`：

```gdscript
extends Node
## headless 单元测试：Robot 鼻子指针（NoseAvatar + RobotAvatar + table3d + 注视同步）。

const NoseAvatarScript := preload("res://scripts/ui/nose_avatar.gd")

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== NOSE RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	await _test_nose_avatar()

## 手动步进 _process 以获得确定性时间。
func _step(nose, seconds: float, dt := 0.1) -> void:
	var t := 0.0
	while t < seconds:
		nose._process(dt)
		t += dt

func _test_nose_avatar() -> void:
	var nose = NoseAvatarScript.new()
	add_child(nose)
	await get_tree().process_frame
	nose.set_process(false)
	_check("初始 IDLE 长度 0", nose.state_name() == "IDLE" and absf(nose.length()) < 0.001)
	nose.set_target(2.0)
	_check("set_target>0 → EXTENDING", nose.state_name() == "EXTENDING")
	_step(nose, NoseAvatarScript.NOSE_DURATION + 0.15)
	_check("到时 → EXTENDED 且长度≈2", nose.state_name() == "EXTENDED" and absf(nose.length() - 2.0) < 0.01)
	nose.set_target(2.0)
	_check("EXTENDED 再设同值不改变状态", nose.state_name() == "EXTENDED")
	nose.set_target(0.0)
	_check("set_target(0) → RETRACTING", nose.state_name() == "RETRACTING")
	_step(nose, NoseAvatarScript.NOSE_DURATION + 0.15)
	_check("缩回 → IDLE 长度≈0", nose.state_name() == "IDLE" and absf(nose.length()) < 0.01)
	nose.set_target(0.0)
	_check("IDLE 设 0 无变化", nose.state_name() == "IDLE")
	nose.set_color(Color("3ABA64"))
	_check("set_color 改材质色", nose._mat.albedo_color.is_equal_approx(Color("3ABA64")))
	nose.queue_free()
	await get_tree().process_frame
```

创建 `tests/verify_nose.tscn`：

```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/verify_nose.gd" id="1"]
[node name="VerifyNose" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 运行确认失败**

Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_nose.tscn`
Expected: 报错/失败（`nose_avatar.gd` 不存在 → 解析失败或 `set_target` 未定义）。

- [ ] **Step 3: 实现 `scripts/ui/nose_avatar.gd`**

```gdscript
class_name NoseAvatar
extends Node3D
## 单条程序化鼻子：底在原点的圆锥沿本地 +Z 生长，按固定时长伸缩。
## 纯客户端展示层，无碰撞、不参与拾取。长度单位为"本节点所在空间"的单位。

enum { IDLE, EXTENDING, EXTENDED, RETRACTING }

const NOSE_BASE_RADIUS := 0.05    # 锥底半径
const NOSE_TIP_RADIUS := 0.015    # 锥尖半径
const NOSE_DURATION := 0.35       # 伸出/缩回固定时长（秒）→ 速度随距离
const NOSE_SEGMENTS := 16
const NOSE_COLOR := Color("F2C14E")

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _state := IDLE
var _from_len := 0.0
var _target_len := 0.0
var _len := 0.0
var _t := 0.0

func _ready() -> void:
	_build()
	_apply_len()

func _build() -> void:
	if _mesh != null:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = NOSE_TIP_RADIUS
	cyl.bottom_radius = NOSE_BASE_RADIUS
	cyl.height = 1.0
	cyl.radial_segments = NOSE_SEGMENTS
	cyl.rings = 1
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = NOSE_COLOR
	_mat.emission_enabled = true
	_mat.emission = NOSE_COLOR
	_mat.emission_energy_multiplier = 0.25
	_mat.metallic = 0.3
	_mat.roughness = 0.5
	_mesh = MeshInstance3D.new()
	_mesh.name = "NoseMesh"
	_mesh.mesh = cyl
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 圆柱沿 +Y 居中 → 绕 X 转 +90° 使 +Y=+Z（锥尖朝 +Z）；长度经 scale.y 拉伸、position.z 把底面挪到原点。
	_mesh.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3.ZERO)
	add_child(_mesh)

## 目标长度：>0 伸出，<=0 缩回。IDLE/RETRACTING 收到 >0 开始伸出；EXTENDING/EXTENDED 收到 <=0 开始缩回。
func set_target(len: float) -> void:
	_build()
	var t := maxf(len, 0.0)
	if t > 0.0:
		if _state == IDLE or _state == RETRACTING:
			_state = EXTENDING
			_from_len = _len
			_target_len = t
			_t = 0.0
	else:
		if _state == EXTENDING or _state == EXTENDED:
			_state = RETRACTING
			_from_len = _len
			_target_len = 0.0
			_t = 0.0

func _process(delta: float) -> void:
	if _state == IDLE:
		return
	_t += delta
	var p := clampf(_t / NOSE_DURATION, 0.0, 1.0)
	_len = lerpf(_from_len, _target_len, p)
	if p >= 1.0:
		_len = _target_len
		_state = EXTENDED if _target_len > 0.0 else IDLE
	_apply_len()

func _apply_len() -> void:
	if _mesh == null:
		return
	_mesh.visible = _len > 0.0001
	_mesh.scale = Vector3(1.0, maxf(_len, 0.0001), 1.0)
	_mesh.position = Vector3(0.0, 0.0, _len * 0.5)

func length() -> float:
	return _len

func is_active() -> bool:
	return _len > 0.0001 or _state != IDLE

func state_name() -> String:
	match _state:
		EXTENDING: return "EXTENDING"
		EXTENDED: return "EXTENDED"
		RETRACTING: return "RETRACTING"
		_: return "IDLE"

func set_color(c: Color) -> void:
	_build()
	_mat.albedo_color = c
	_mat.emission = c
```

- [ ] **Step 4: 注册到全量脚本**

修改 `tools/run_all_tests.sh`，在 `run_single "robot_avatar" ...` 行之后插入：

```bash
run_single "nose" res://tests/verify_nose.tscn
```

- [ ] **Step 5: 运行确认通过**

Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_nose.tscn`
Expected: `=== NOSE RESULT: 8/8 passed ===`（若报 `NoseAvatar` 类未声明，先让编辑器重扫文件系统再跑；本测试用 preload 不应触发）。

- [ ] **Step 6: 提交**

```bash
git add scripts/ui/nose_avatar.gd tests/verify_nose.gd tests/verify_nose.tscn tools/run_all_tests.sh
git commit -m "feat: 新增 NoseAvatar 程序化鼻子 + 伸缩状态机（含 headless 测试）"
```

---

### Task 2: `RobotAvatar` 挂鼻子（随头 + 世界↔局部长度折算）

**Files:**
- Modify: `scripts/ui/robot_avatar.gd`
- Modify: `tests/verify_nose.gd`（新增 `_test_robot_nose`，并在 `_run` 里调用）

**Interfaces:**
- Consumes: `NoseAvatar`（Task 1）。
- Produces（供 Task 3 / 5 使用）：`RobotAvatar.set_nose_target(world_len: float) -> void`；`nose_length() -> float`（世界）；`nose_state_name() -> String`；`nose_base_world() -> Transform3D`；公开成员 `_nose`；常量 `NOSE_BASE_MODEL`。

- [ ] **Step 1: 写失败测试**

在 `tests/verify_nose.gd` 的 `_run()` 里、`await _test_nose_avatar()` 之后加 `await _test_robot_nose()`，并新增：

```gdscript
func _test_robot_nose() -> void:
	var robot := RobotAvatar.new()
	add_child(robot)
	await get_tree().process_frame
	_check("Robot 建立了鼻子", robot._nose != null)
	# 世界长度经 SCALE 折算到骨架局部：目标世界 2.0 → 局部 2.0/SCALE
	robot._nose.set_process(false)
	robot.set_nose_target(2.0)
	robot._nose.set_target(2.0 / RobotAvatar.SCALE)
	_step(robot._nose, NoseAvatarScript.NOSE_DURATION + 0.15)
	_check("鼻子世界长度≈2.0", absf(robot.nose_length() - 2.0) < 0.02)
	# 随头：头姿势变化后鼻子局部变换随之变化
	var t0: Transform3D = robot._nose.transform
	var eye: Vector3 = robot.eye_world_position()
	var left_w: Vector3 = robot._skeleton.global_transform.basis * Vector3(1, 0, 0)
	robot.set_gaze_target_world(eye + left_w * 100.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var t1: Transform3D = robot._nose.transform
	_check("鼻子随 Head 转动", not t0.basis.is_equal_approx(t1.basis))
	# 颜色同步
	robot.set_body_color(Color("3ABA64"))
	_check("鼻子随机体色", robot._nose._mat.albedo_color.is_equal_approx(Color("3ABA64")))
	robot.queue_free()
	await get_tree().process_frame
```

- [ ] **Step 2: 运行确认失败**

Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_nose.tscn`
Expected: FAIL（`robot._nose` 为 null / `set_nose_target` 未定义）。

- [ ] **Step 3: 改 `scripts/ui/robot_avatar.gd`**

在常量区（`MODEL_HEAD_TOP` 附近）加：

```gdscript
const NOSE_BASE_MODEL := Vector3(0.0, 1.99, 0.24)   # 两眼中间、眼下、嘴上（模型空间，+Z=脸朝向）
const NoseAvatarScript := preload("res://scripts/ui/nose_avatar.gd")
```

在成员区（`_eyes` 附近）加：

```gdscript
var _nose = null                # NoseAvatar（挂在 Skeleton3D 下，随头）
```

在 `_process(delta)` 开头（`_talking` 判断之前）加鼻子位姿更新：

```gdscript
	if _nose != null and _skeleton != null and _head_idx >= 0:
		var hpose: Transform3D = _skeleton.get_bone_global_pose(_head_idx)
		var hrest: Transform3D = _skeleton.get_bone_global_rest(_head_idx)
		_nose.transform = Transform3D(
			hpose.basis * hrest.basis.inverse(),
			hpose * (hrest.affine_inverse() * NOSE_BASE_MODEL))
```

在 `_build()` 末尾（`_apply_body_color()` 之后）加：

```gdscript
	if _skeleton != null:
		_nose = NoseAvatarScript.new()
		_nose.name = "Nose"
		_skeleton.add_child(_nose)
		_nose.set_color(_body_color)
```

在 `_apply_body_color()` 末尾（`face` 块之后）加：

```gdscript
	if _nose != null:
		_nose.set_color(_body_color)
```

新增方法（放在 `reset_eyes()` 之后）：

```gdscript
## ===== 鼻子（中键指针）=====
## 目标长度为世界单位；骨架被 SCALE 缩放，故折算为局部长度。
func set_nose_target(world_len: float) -> void:
	_build()
	if _nose != null:
		_nose.set_target(world_len / SCALE)

## 当前鼻子长度（世界单位）。
func nose_length() -> float:
	if _nose == null:
		return 0.0
	return _nose.length() * SCALE

func nose_state_name() -> String:
	if _nose == null:
		return "IDLE"
	return _nose.state_name()

func nose_base_world() -> Transform3D:
	_build()
	if _nose == null:
		return Transform3D()
	return _nose.global_transform
```

- [ ] **Step 4: 运行确认通过**

Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_nose.tscn`
Expected: 全部 PASS（Task 1+2 合计 8+5=13 项）。

- [ ] **Step 5: 回归**

Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_robot_avatar.tscn`
Expected: `62/62 passed`（鼻子不影响既有眼动/说话）。

- [ ] **Step 6: 提交**

```bash
git add scripts/ui/robot_avatar.gd tests/verify_nose.gd
git commit -m "feat: RobotAvatar 挂载随头鼻子并做长度折算"
```

---

### Task 3: `Table3dView`（hover 缓存 + 本机相机鼻子 + 远程下发）

**Files:**
- Modify: `scripts/ui/table3d_view.gd`
- Modify: `tests/verify_nose.gd`（新增 `_test_view_nose`）

**Interfaces:**
- Consumes: `RobotAvatar.set_nose_target` / `nose_length`（Task 2）、`NoseAvatar`（Task 1）。
- Produces（供 Task 5 使用）：`Table3dView.hovered_card_world()`（返回 `Vector3` 或 `null`）；`update_noses(remote_nose: Dictionary) -> void`；`set_local_nose_target(len: float) -> void`；`local_nose_length() -> float`；`local_nose_state_name() -> String`；`local_nose_base_world() -> Vector3`；`clear_local_nose() -> void`；成员 `_local_nose` / `_hover_kind` / `_hover_world_pos`。

- [ ] **Step 1: 写失败测试**

在 `_run()` 里 `await _test_robot_nose()` 之后加 `await _test_view_nose()`，并新增：

```gdscript
func _test_view_nose() -> void:
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	_check("本机相机鼻子已建立", view._local_nose != null)
	# 无悬停 / 非卡牌 → null
	view._hover_kind = ""
	view._hover_world_pos = Vector3.ZERO
	_check("无悬停 → null", view.hovered_card_world() == null)
	view._hover_kind = "hud"
	view._hover_world_pos = Vector3(1, 2, 3)
	_check("hud → null", view.hovered_card_world() == null)
	view._hover_kind = "slot"
	_check("slot → 世界位置", (view.hovered_card_world() as Vector3).is_equal_approx(Vector3(1, 2, 3)))
	_check("deck/discard/pending 认可", view.NOSE_PICK_KINDS.has("deck") and view.NOSE_PICK_KINDS.has("discard") and view.NOSE_PICK_KINDS.has("pending"))
	# 本机鼻子驱动（无缩放 → 世界长度=局部长度）
	view.set_local_nose_target(2.0)
	_check("本机鼻子 EXTENDING", view.local_nose_state_name() == "EXTENDING")
	_step(view._local_nose, NoseAvatarScript.NOSE_DURATION + 0.15)
	_check("本机鼻子长度≈2.0", absf(view.local_nose_length() - 2.0) < 0.02)
	_check("本机鼻根世界位置有效", view.local_nose_base_world().length() > 0.1)
	# 远程下发
	view.render({
		"viewer_id": 0, "current_player": 1,
		"players": [
			{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2, "slots": [{"card_id": "c1"}]},
			{"id": 1, "name": "乙", "count": 2, "currency": 0, "health": 2, "slots": [{"card_id": "c2"}]},
		],
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 2,
	})
	await get_tree().process_frame
	var robot1 = view._seat_nodes[1].get_node("Avatar").get_node("RobotAvatar")
	robot1._nose.set_process(false)
	view.update_noses({1: 2.0})
	_step(robot1._nose, NoseAvatarScript.NOSE_DURATION + 0.15)
	_check("远程鼻子长度≈2.0（世界）", absf(robot1.nose_length() - 2.0) < 0.02)
	# 清空
	view.clear_local_nose()
	_step(view._local_nose, NoseAvatarScript.NOSE_DURATION + 0.15)
	_check("clear_local_nose 缩回", absf(view.local_nose_length()) < 0.02)
	view.queue_free()
	await get_tree().process_frame
```

- [ ] **Step 2: 运行确认失败**

Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_nose.tscn`
Expected: FAIL（`_local_nose`/`hovered_card_world` 未定义）。

- [ ] **Step 3: 实现 `scripts/ui/table3d_view.gd`**

在文件顶部 preload 区（`CardBlockScript` 附近）加：

```gdscript
const NoseAvatarScript := preload("res://scripts/ui/nose_avatar.gd")
const NOSE_PICK_KINDS := ["slot", "deck", "discard", "pending"]  # 可被中键"标记"的拾取类型
const LOCAL_NOSE_POS := Vector3(0.0, -0.06, -0.15)               # 本机鼻根（相机本地，-Z=前）
```

在成员区（`_hover_collider` 附近）加：

```gdscript
var _hover_kind := ""              # 当前悬停拾取类型（供 hovered_card_world）
var _hover_world_pos := Vector3.ZERO
var _local_nose = null             # NoseAvatar（挂本机相机，第一人称）
```

在 `_bind()` 末尾 `_bound = true` 之后加：

```gdscript
	_ensure_local_nose()
```

新增方法（放在 `clear_hover()` 之后）：

```gdscript
## ===== 鼻子指针（中键）=====
## 建立本机第一人称鼻子（挂相机；本地 +Z 转到相机前向 -Z）。
func _ensure_local_nose() -> void:
	if _local_nose != null and is_instance_valid(_local_nose):
		return
	if camera == null:
		return
	var cam: Camera3D = camera.camera_node()
	if cam == null:
		return
	_local_nose = NoseAvatarScript.new()
	_local_nose.name = "LocalNose"
	_local_nose.transform = Transform3D(Basis(Vector3.UP, PI), LOCAL_NOSE_POS)
	cam.add_child(_local_nose)
	_local_nose.set_color(Color("F2C14E"))

## 当前悬停的可标记卡牌世界位置；非卡牌/无悬停返回 null。
func hovered_card_world():
	if NOSE_PICK_KINDS.has(_hover_kind):
		return _hover_world_pos
	return null

## 本机鼻根世界位置（供 main 算到卡距离）。
func local_nose_base_world() -> Vector3:
	if _local_nose == null or not is_instance_valid(_local_nose):
		return Vector3.ZERO
	return _local_nose.global_position

func set_local_nose_target(len: float) -> void:
	_ensure_local_nose()
	if _local_nose != null:
		_local_nose.set_target(len)

func local_nose_length() -> float:
	if _local_nose == null:
		return 0.0
	return _local_nose.length()

func local_nose_state_name() -> String:
	if _local_nose == null:
		return "IDLE"
	return _local_nose.state_name()

func clear_local_nose() -> void:
	if _local_nose != null:
		_local_nose.set_target(0.0)

## 每帧把各远程席的鼻子目标长度（世界单位）下发给其 RobotAvatar。
func update_noses(remote_nose: Dictionary) -> void:
	_bind()
	if not _bound:
		return
	for seat in _seat_node_by_id.keys():
		var node = _seat_node_by_id[seat]
		if node == null or not is_instance_valid(node):
			continue
		var avatar = (node as Node3D).get_node_or_null("Avatar")
		if avatar == null:
			continue
		var robot = avatar.get_node_or_null("RobotAvatar")
		if robot == null:
			continue
		robot.set_nose_target(float(remote_nose.get(seat, 0.0)))
```

在 `update_hover()` 里记录悬停类型与世界位置（在 `var hit := Table3dPicker.pick_hit(...)` 之后加）：

```gdscript
	_hover_kind = str((hit.get("pick", {}) as Dictionary).get("kind", ""))
	_hover_world_pos = hit.get("position", Vector3.ZERO)
```

在 `clear_hover()` 里清空（`_hover_collider = null` 之后加）：

```gdscript
	_hover_kind = ""
	_hover_world_pos = Vector3.ZERO
```

在 `set_active(on)` 中关闭时清本机鼻子：

```gdscript
	if not on:
		_clear_exchange_anim()
		clear_local_nose()
```

- [ ] **Step 4: 运行确认通过**

Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_nose.tscn`
Expected: 全部 PASS（13+8=21 项）。

- [ ] **Step 5: 回归**

Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: `76/76 passed`（hover 缓存不影响既有交互）。

- [ ] **Step 6: 提交**

```bash
git add scripts/ui/table3d_view.gd tests/verify_nose.gd
git commit -m "feat: Table3dView 支持 hover 卡牌查询、本机相机鼻子与远程鼻子下发"
```

---

### Task 4: `GameState` 同步（`remote_nose` + `look` 可选 nose）

**Files:**
- Modify: `scripts/core/game_state.gd`
- Modify: `tests/verify_nose.gd`（新增 `_test_game_state_nose`）

**Interfaces:**
- Consumes: 无。
- Produces（供 Task 5 使用）：`GameState.remote_nose: Dictionary`；`server_look(target, zoom, talking, nose := 0.0)`；`_apply_look(seat, target, zoom := false, talking := false, nose := 0.0)`；`receive_look(seat, target, zoom, talking, nose := 0.0)`。

- [ ] **Step 1: 写失败测试**

在 `_run()` 末尾加 `_test_game_state_nose()`，并新增：

```gdscript
func _test_game_state_nose() -> void:
	GameState.remote_nose.clear()
	GameState._apply_look(1, Vector3(0, 0, 5), true, true, 2.5)
	_check("_apply_look 存 nose", absf(float(GameState.remote_nose.get(1, 0.0)) - 2.5) < 0.001)
	GameState.receive_look(2, Vector3(1, 0, 0), false, false, 1.25)
	_check("receive_look 存 nose", absf(float(GameState.remote_nose.get(2, 0.0)) - 1.25) < 0.001)
	GameState._apply_look(3, Vector3(0, 0, 5), false, false)
	_check("旧 4 参调用向后兼容（nose=0）", absf(float(GameState.remote_nose.get(3, -1.0))) < 0.001)
	GameState.remote_looks.clear()
	GameState.remote_zoom.clear()
	GameState.remote_talk.clear()
	GameState.remote_nose.clear()
```

- [ ] **Step 2: 运行确认失败**

Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_nose.tscn`
Expected: FAIL（`remote_nose` 未定义 / `_apply_look` 参数数量不符）。

- [ ] **Step 3: 实现 `scripts/core/game_state.gd`**

在 `remote_talk` 声明行（约 86 行）之后加：

```gdscript
var remote_nose: Dictionary = {}   # {seat: float} 各玩家鼻子目标长度（世界单位），纯表现层
```

在 `_on_peer_left` 的 `remote_talk.erase(seat)` 之后加：

```gdscript
	remote_nose.erase(seat)
```

在 `_reset_match()` 的 `remote_talk.clear()` 之后加：

```gdscript
	remote_nose.clear()
```

替换 `server_look` / `_apply_look` / `receive_look` 三个函数为：

```gdscript
@rpc("any_peer", "call_remote", "reliable")
func server_look(target: Vector3, zoom: bool, talking: bool, nose := 0.0) -> void:
	var seat := _peer_to_seat(multiplayer.get_remote_sender_id())
	if seat < 0:
		return
	_apply_look(seat, target, zoom, talking, nose)

## 服务器权威应用注视：记录本机 remote_looks/remote_zoom/remote_talk/remote_nose 并转发（房主本人经此路径）。
func _apply_look(seat: int, target: Vector3, zoom := false, talking := false, nose := 0.0) -> void:
	if not target.is_finite():
		return
	remote_looks[seat] = target
	remote_zoom[seat] = zoom
	remote_talk[seat] = talking
	remote_nose[seat] = maxf(nose, 0.0)
	for s in players.keys():
		var peer := int(players[s].peer_id)
		if peer > 1:
			receive_look.rpc_id(peer, seat, target, zoom, talking, maxf(nose, 0.0))

@rpc("authority", "call_remote", "reliable")
func receive_look(seat: int, target: Vector3, zoom: bool, talking: bool, nose := 0.0) -> void:
	remote_looks[seat] = target
	remote_zoom[seat] = zoom
	remote_talk[seat] = talking
	remote_nose[seat] = maxf(nose, 0.0)
```

- [ ] **Step 4: 运行确认通过**

Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_nose.tscn`
Expected: 全部 PASS（21+4=25 项）。

- [ ] **Step 5: 回归**

Run:
```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_robot_avatar.tscn
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . res://tests/verify_protocol.tscn
```
Expected: `62/62`、`38/38`（4 参调用向后兼容）。

- [ ] **Step 6: 提交**

```bash
git add scripts/core/game_state.gd tests/verify_nose.gd
git commit -m "feat: look 表现层通道新增 nose 字段并存储 remote_nose"
```

---

### Task 5: `main.gd` 中键接线（触发 / 每帧下发 / 上报）

**Files:**
- Modify: `scripts/ui/main.gd`

**Interfaces:**
- Consumes: `Table3dView.hovered_card_world()` / `set_local_nose_target` / `update_noses` / `local_nose_base_world` / `local_nose_state_name` / `clear_local_nose`（Task 3）；`GameState.remote_nose` / `_apply_look` / `server_look`（Task 4）。
- Produces: 中键触发行为（无可供后续消费的公开接口）。

- [ ] **Step 1: 加成员变量**

在 `var _last_look_talk := false`（约 636 行）之后加：

```gdscript
var _nose_local_target := 0.0    # 本机鼻子目标长度（世界单位）
var _last_look_nose := 0.0       # 上次上报的鼻子长度（变化即发）
```

- [ ] **Step 2: 中键输入分支**

在 `_input()` 中，左键分支（`InputEventMouseButton ... MOUSE_BUTTON_LEFT`）之前 / 之后加：

```gdscript
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		_on_nose_click()
		get_viewport().set_input_as_handled()
		return
```

- [ ] **Step 3: 实现触发逻辑**

在 `_table3d_click()` 之后加：

```gdscript
## 鼠标中键：悬停卡牌时伸出鼻子（长度=鼻根→卡世界距离）；已伸出时缩回；缩回中忽略。
## 看板模态打开时忽略（与左键路由一致）。
func _on_nose_click() -> void:
	if table3d == null or not is_instance_valid(table3d):
		return
	if _board_has_panel():
		return
	var st: String = table3d.local_nose_state_name()
	if st == "IDLE":
		var card = table3d.hovered_card_world()
		if card == null:
			return
		var d: float = table3d.local_nose_base_world().distance_to(card)
		if d <= 0.001:
			return
		_nose_local_target = d
	elif st == "EXTENDED" or st == "EXTENDING":
		_nose_local_target = 0.0
	# RETRACTING：忽略
```

- [ ] **Step 4: 每帧下发**

在 `_process()` 中 `table3d.update_avatars(...)` 之后加：

```gdscript
	table3d.update_noses(GameState.remote_nose)
	table3d.set_local_nose_target(_nose_local_target)
	if _nose_local_target == 0.0 and table3d.local_nose_state_name() == "IDLE":
		_nose_local_target = 0.0
```

（最后一行是显式归位，避免浮点残留。）

- [ ] **Step 5: `look` 上报携带 nose**

把 `_update_look_send()` 中从 `var talking := _talking_local` 到 `server_look.rpc_id(...)` 的段落替换为：

```gdscript
	var talking := _talking_local
	var nose := _nose_local_target
	var dir_changed := _last_look_dir == Vector3.ZERO or _last_look_dir.dot(dir) <= LOOK_SEND_EPS_DOT
	if not dir_changed and zoomed == _last_look_zoom and talking == _last_look_talk \
			and is_equal_approx(nose, _last_look_nose):
		return
	_last_look_dir = dir
	_last_look_zoom = zoomed
	_last_look_talk = talking
	_last_look_nose = nose
	var seat := int(latest_state.get("viewer_id", -1))
	if seat < 0:
		return
	var target := cam.global_position + dir * LOOK_TARGET_DISTANCE
	if multiplayer.is_server():
		GameState._apply_look(seat, target, zoomed, talking, nose)
	else:
		GameState.server_look.rpc_id(1, target, zoomed, talking, nose)
```

- [ ] **Step 6: 退出 3D 清理**

在 `_set_table3d(false)` 分支中 `table3d.set_active(false)` 之前加：

```gdscript
			table3d.clear_local_nose()
```

并把 `_nose_local_target = 0.0` 放在 `_table3d_active = on` 之后（进入/退出都归零）：

```gdscript
	_table3d_active = on
	_nose_local_target = 0.0
```

- [ ] **Step 7: 编译 + 全量备份回归**

Run: `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --path . --quit-after 5`
Expected: 退出码 0、无 `SCRIPT ERROR` / `Parse Error`。

Run: `tools/run_all_tests.sh --quick`
Expected: 单进程核心全 PASS（含新增 `nose`）。

- [ ] **Step 8: 提交**

```bash
git add scripts/ui/main.gd
git commit -m "feat: 3D 中键触发鼻子伸缩并随 look 上报"
```

---

### Task 6: 文档与最终验收

**Files:**
- Modify: `docs/网络协议_V1.md`
- Modify: `docs/3D角色与场景说明.md`
- Modify: `docs/功能实现文档.md`
- Modify: `docs/AI_AGENT_交接说明.md`

**Interfaces:**
- Consumes: 全部实现。
- Produces: 文档与最终验证。

- [ ] **Step 1: 更新 `docs/网络协议_V1.md`**

在 §3 请求表 `look` 行与 §4.8 注视点小节中，把签名补上 `nose: Float`（默认 0），说明：`nose` 为目标鼻子长度（世界单位），纯表现层、不入快照、不参与规则；`receive_look` 转发同样携带。

- [ ] **Step 2: 更新 `docs/3D角色与场景说明.md`**

在 §4 角色系统下新增一小节「4.9 鼻子指针（中键）」：程序化 `NoseAvatar`、远程挂骨架随头、本机挂相机第一人称、长度=hover 卡距、时长固定 0.35s、再次中键缩回、经 `look` 同步 `remote_nose`；参数表补 `NOSE_BASE_MODEL` / `NOSE_DURATION` / `LOCAL_NOSE_POS`。

- [ ] **Step 3: 更新 `docs/功能实现文档.md` 与 `docs/AI_AGENT_交接说明.md`**

各补一条：3D Robot 鼻子指针（中键悬停卡牌伸缩、随头、`look` 增 `nose`）；文件地图加 `scripts/ui/nose_avatar.gd` 与 `tests/verify_nose.*`；验证命令加 `res://tests/verify_nose.tscn`。

- [ ] **Step 4: 全量回归**

Run: `tools/run_all_tests.sh`
Expected: 汇总全 PASS（含 `nose`、`robot_avatar`、`table3d_interaction`、双实例 `net`）。

- [ ] **Step 5: 提交**

```bash
git add docs/网络协议_V1.md docs/3D角色与场景说明.md docs/功能实现文档.md docs/AI_AGENT_交接说明.md
git commit -m "doc: 记录 Robot 鼻子指针与 look nose 字段"
```

---

## Self-Review

**1. Spec coverage**

- 程序化鼻子在眼下方嘴上（`NOSE_BASE_MODEL`）→ Task 2。
- 中键触发、仅 hover 卡牌生效 → Task 5 + Task 3（`hovered_card_world`）。
- 长度=鼻根→卡世界距离、时长固定速度随距 → Task 1（`NOSE_DURATION`）+ Task 5（`d`）。
- 方向随头 / 长度不变 → Task 2（每帧 `_nose.transform` 由 Head 姿势）+ 不重设目标。
- 再次中键缩回 → Task 1 状态机 + Task 5.
- 本机第一人称可见 → Task 3（相机鼻子）。
- 所有玩家可见 → Task 4（`look.nose`）+ Task 3（`update_noses`）。
- 纯展示、不改规则/协议语义 → Task 4 仅表现层字段；Global Constraints。
- 测试与文档 → Task 1–6。

**2. Placeholder scan**：无 TBD/TODO；每个代码步骤给出完整代码。

**3. Type consistency**：`set_nose_target(world_len)`（Task 2/3/5 一致，世界单位）；`_nose.set_target`（局部单位，Task 1/2）；`update_noses(remote_nose)`（Task 3/5）；`local_nose_state_name()`（Task 3/5）；`remote_nose`（Task 4/5）。`NoseAvatarScript` preload 常量在 test/robot/table3d 三处同名同源。

**已知取舍（非计划缺陷）**：方向"纯随头"故鼻尖不保证精确停在卡上（用户已确认）；main 的中键逻辑为薄接线，不单独 headless 断言，由 Task 1–4 的单元覆盖 + 全量回归兜底。
