# 3D 桌面 hover 抬起/倾斜动效接入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把沙盒验证过的 hover 抬起+朝玩家倾斜接到正式 3D 桌面，仅 viewer 自己的手牌，拾取判定不受动画影响、跨 render 重建保持。

**Architecture:** `CardBlock` 内新增视觉子节点 `_visual`（承载 mesh/glow/label + hover pose），拾取 `Area3D` 留在根（不随动画移动）；hover pose 复用 `CardAnimationMath.compose` 的位移/旋转。`Table3dView` 记录 `_viewer`/`_hover_slot`，只对自己槽启用，并在每次 `render()` 后即时重放。

**Tech Stack:** Godot 4.6 GDScript、`Node3D`/`Basis`/`Tween`、headless `.tscn` 测试。

**Spec:** `docs/superpowers/specs/2026-09-25-table3d-hover-animation-design.md`

## Global Constraints

- 分支 `feature/card-animation`。提交 `feat:`/`test:`/`fix:`/`doc:`。
- **不改**：`scripts/core/*`、`scripts/net/*`、`scripts/ui/main.gd`、`scenes/ui/table3d.tscn`、`card_animation_math.gd`、`card_animation.gd`、`card_animation_sandbox.gd`、`verify_card_animation.gd`、`verify_table3d.gd`（只回归）。
- hover 只作用 viewer 自己手牌；不写 `_visual.scale`；揭示的 `self.scale.x` 翻转保持不动。
- 验证命令：
  - 编译：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5`
  - 单测：`... --headless --path . res://tests/<scene>.tscn`
  - 全量（快）：`tools/run_all_tests.sh --quick`
  - 报 `Identifier "X" not declared` 时先 `--headless --path . --import`。
- 不启 GUI 验证。

---

## File Structure

| 文件 | 职责 |
| --- | --- |
| `scripts/ui/card_block.gd`（改） | 新增 `_visual` 视觉 pivot；`set_hover_pose`+`_process` 应用 hover pose；访问器 |
| `scripts/ui/table3d_view.gd`（改） | `_viewer`/`_hover_slot`/`_hover_ray_local`；own 槽启用动画；`update_hover` 驱动；`render` 后重放；`clear_hover` 复位 |
| `tests/verify_table3d_interaction.gd`（改） | 结构/抬起/落回/拾取不动/跨 render 保持 |
| `docs/AI_AGENT_交接说明.md`（改） | §4/§8 记一笔 |

---

### Task 1: CardBlock 视觉 pivot（不改揭示）

**Files:**
- Modify: `scripts/ui/card_block.gd`
- Modify: `tests/verify_table3d_interaction.gd`

**Interfaces:**
- Produces: `CardBlock.visual_node() -> Node3D`（返回 `_visual`）
- 保持：`_area` 仍为根直接子节点、名为 `PickArea`；`reveal/restore/setup` 的 `self.scale.x` 翻转不变

- [ ] **Step 1: 写失败测试**

在 `tests/verify_table3d_interaction.gd` 的 `_test_card_block()` 末尾（`flash` 断言之后）追加：

```gdscript
	# 视觉 pivot：hover 只动 _visual，拾取盒留根
	var vb := CardBlock.new()
	add_child(vb)
	vb.setup({"card": {"rank": "A", "suit": "♥"}})
	_check("视觉 pivot 为根子节点", vb.visual_node() != null and vb.visual_node().get_parent() == vb)
	_check("拾取盒仍在根", vb.get_node("PickArea") != null and vb.get_node("PickArea").get_parent() == vb)
	_check("Mesh 挂在视觉 pivot 下", vb.visual_node().has_node("Mesh"))
```

- [ ] **Step 2: 运行确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: 报 `visual_node` 未定义。

- [ ] **Step 3: 实现**

在 `scripts/ui/card_block.gd`：

① 字段区（`var _mesh` 上方）加：

```gdscript
var _visual: Node3D
```

② `_build()` 里，在 `_built = true` 之后、创建 Glow 循环之前，创建 pivot：

```gdscript
	# 视觉 pivot：hover 位移/旋转作用于它；拾取 Area3D 留在根，不随动画移动。
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
```

③ 把 Glow、Mesh、Label 的挂载从 `add_child(...)` 改为 `_visual.add_child(...)`：

- Glow 循环内：`glow` 的 `add_child(glow)` → `_visual.add_child(glow)`
- `add_child(_mesh)` → `_visual.add_child(_mesh)`
- `add_child(_label)` → `_visual.add_child(_label)`

④ `setup(slot)` 里（`_kill_flip()` 之后、`_apply_slot(slot)` 之前）加复位：

```gdscript
	if _visual != null:
		_visual.transform = Transform3D.IDENTITY
```

⑤ 文件末尾加访问器：

```gdscript
## 视觉子节点（hover 位移/旋转作用于它；拾取盒在根，不受影响）。
func visual_node() -> Node3D:
	_build()
	return _visual
```

- [ ] **Step 4: 运行确认通过 + 回归**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_interaction.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d.tscn
```
Expected: interaction 由 48 增至 51/51（+3）；table3d 36/36。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/card_block.gd tests/verify_table3d_interaction.gd
git commit -m "feat: CardBlock 视觉 pivot（hover 动效不影响拾取盒）+ 测试"
```

---

### Task 2: CardBlock hover pose 驱动

**Files:**
- Modify: `scripts/ui/card_block.gd`
- Modify: `tests/verify_table3d_interaction.gd`

**Interfaces:**
- Consumes: `CardAnimationMath.compose`、`CardAnimationConfig`
- Produces:
  - `CardBlock.hover_anim_enabled: bool`
  - `CardBlock.set_hover_pose(on: bool, ray_local: Vector2, immediate := false) -> void`
  - `CardBlock.hover_progress() -> float`

- [ ] **Step 1: 写失败测试**

在 `_run()` 追加 `await _test_hover_pose()`，并追加函数：

```gdscript
func _test_hover_pose() -> void:
	var cfg := CardAnimationConfig.new()
	var b := CardBlock.new()
	b.hover_anim_enabled = true
	add_child(b)
	b.setup({"card": {"rank": "A", "suit": "♥"}})
	b.set_hover_pose(true, Vector2.ZERO)
	await get_tree().create_timer(cfg.hover_in_dur + 0.1).timeout
	_check("own hover 抬起", b.hover_progress() > 0.9 and b.visual_node().position.y > 0.0)
	b.set_hover_pose(false, Vector2.ZERO)
	await get_tree().create_timer(cfg.hover_out_dur + 0.1).timeout
	_check("离开落回", b.hover_progress() < 0.1 and absf(b.visual_node().position.y) < 0.001)
	var c := CardBlock.new()
	add_child(c)
	c.setup({"card": {"rank": "2", "suit": "♣"}})
	c.set_hover_pose(true, Vector2.ZERO)
	await get_tree().create_timer(cfg.hover_in_dur + 0.1).timeout
	_check("未启用动画的块不抬", c.visual_node().position.is_equal_approx(Vector3.ZERO))
```

- [ ] **Step 2: 运行确认失败**

Run: `... --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: 报 `hover_anim_enabled`/`set_hover_pose` 未定义。

- [ ] **Step 3: 实现**

在 `scripts/ui/card_block.gd`：

① 字段区加：

```gdscript
static var _anim_cfg: CardAnimationConfig = null
var hover_anim_enabled := false
var _hover_p := 0.0
var _ray_local := Vector2.ZERO
var _hover_tween: Tween = null
```

② `_build()` 末尾（`_visual` 建好、`_area` 之后）加：`set_process(false)`

③ `setup(slot)` 里复位处补：

```gdscript
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null
	_hover_p = 0.0
	_ray_local = Vector2.ZERO
```

④ 新增方法（放在 `visual_node()` 附近）：

```gdscript
static func _cfg() -> CardAnimationConfig:
	if _anim_cfg == null:
		_anim_cfg = CardAnimationConfig.new()
	return _anim_cfg

func hover_progress() -> float:
	return _hover_p

## hover 抬起/倾斜：on=true 抬到 hover 姿态，false 落回；immediate 直接置值不缓动（跨 render 重放用）。
func set_hover_pose(on: bool, ray_local: Vector2, immediate := false) -> void:
	_build()
	_ray_local = ray_local
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null
	var target := 1.0 if on else 0.0
	if immediate:
		_hover_p = target
		_apply_hover_pose()
		return
	if is_equal_approx(_hover_p, target):
		_apply_hover_pose()
		return
	var cfg := _cfg()
	var dur := cfg.hover_in_dur if on else cfg.hover_out_dur
	var trans := Tween.TRANS_BACK if on else Tween.TRANS_CUBIC
	if hover_anim_enabled:
		set_process(true)
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "_hover_p", target, dur).set_trans(trans).set_ease(Tween.EASE_OUT)

func _process(_delta: float) -> void:
	if not hover_anim_enabled:
		set_process(false)
		return
	_apply_hover_pose()

## 用 compose 的位移/旋转驱动 `_visual`（不写 scale，避免与揭示翻转抢属性）。
func _apply_hover_pose() -> void:
	if _visual == null:
		return
	if _hover_p <= 0.0:
		_visual.transform = Transform3D.IDENTITY
		return
	var c := CardAnimationMath.compose(
		{"hover": _hover_p, "press": 0.0, "flip": 0.0, "land": 0.0},
		_cfg().to_dict(), 0.0, _ray_local)
	var rot: Vector3 = c["visual_rot_deg"]
	_visual.transform = Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))),
		c["visual_pos"])
```

- [ ] **Step 4: 运行确认通过**

Run: `... --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: 54/54（51 + 3）。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/card_block.gd tests/verify_table3d_interaction.gd
git commit -m "feat: CardBlock hover pose 驱动（复用 compose，仅 pos/rot）+ 测试"
```

---

### Task 3: Table3dView 接入（仅 own 槽 + 跨 render 保持）

**Files:**
- Modify: `scripts/ui/table3d_view.gd`
- Modify: `tests/verify_table3d_interaction.gd`

**Interfaces:**
- Consumes: `CardBlock.set_hover_pose`、`CardBlock.hover_anim_enabled`、`Table3dPicker.pick_hit`（含 `position`）
- Produces: `Table3dView._viewer: int`、`Table3dView._hover_slot: Dictionary`、`Table3dView._hover_ray_local: Vector2`

- [ ] **Step 1: 写失败测试**

在 `tests/verify_table3d_interaction.gd` 的 `_test_view()` 末尾追加（注意该函数里 `view` 与 fixture 已存在）：

```gdscript
	# hover 动效：仅 own 槽启用；抬起时拾取盒不动；跨 render 保持
	var players_h := [
		{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2,
		 "slots": [{"card_id": "c1"}, {"card_id": "c2"}, {"card_id": "c3"}, {"card_id": "c4"}]},
		{"id": 1, "name": "乙", "count": 4, "currency": 0, "health": 2,
		 "slots": [{"card_id": "c9"}, {"card_id": "c10"}, {"card_id": "c11"}, {"card_id": "c12"}]},
	]
	view.render({"viewer_id": 0, "players": players_h, "draw_count": 30, "discard": {}, "pending": {}, "phase": 2})
	await get_tree().process_frame
	_check("own 槽启用 hover 动画", view._card_blocks[0][0].hover_anim_enabled)
	_check("非 own 槽不启用", not view._card_blocks[1][0].hover_anim_enabled)
	var hb = view._card_blocks[0][0]
	var base_pos: Vector3 = hb.position
	var area_pos: Vector3 = hb.get_node("PickArea").global_position
	hb.set_hover_pose(true, Vector2.ZERO)
	await get_tree().create_timer(CardAnimationConfig.new().hover_in_dur + 0.1).timeout
	_check("own hover 抬起", hb.visual_node().position.y > 0.0)
	_check("抬起时拾取盒不移动", hb.position.is_equal_approx(base_pos) and hb.get_node("PickArea").global_position.is_equal_approx(area_pos))
	view._hover_slot = {"seat": 0, "slot": 0}
	view._hover_ray_local = Vector2.ZERO
	view.render({"viewer_id": 0, "players": players_h, "draw_count": 30, "discard": {}, "pending": {}, "phase": 2})
	await get_tree().process_frame
	_check("跨 render 保持 hover 抬起", view._card_blocks[0][0].hover_progress() == 1.0)
	_check("跨 render 后视觉抬起", view._card_blocks[0][0].visual_node().position.y > 0.0)
```

- [ ] **Step 2: 运行确认失败**

Run: `... --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: `hover_anim_enabled` 恒 false / `_hover_slot` 不存在 → 失败。

- [ ] **Step 3: 实现**

在 `scripts/ui/table3d_view.gd`：

① 字段区（`var _card_blocks := {}` 附近）加：

```gdscript
var _viewer := 0
var _hover_slot := {}
var _hover_ray_local := Vector2.ZERO
```

② `render()` 中 `var viewer := int(state.get("viewer_id", 0))` 之后加：`_viewer = viewer`。

③ `_render_seat(node, p)` 中 `block.set_pick({"kind": "slot", ...})` 之后加：

```gdscript
		block.hover_anim_enabled = int(p.id) == _viewer
```

④ `render()` 末尾（`_update_bell(state)` 之前）加 `_reapply_hover_pose()`；并新增方法：

```gdscript
## 重建后重放在途 hover（immediate，避免广播导致弹跳）。
func _reapply_hover_pose() -> void:
	if _hover_slot.is_empty():
		return
	var b = _find_block(int(_hover_slot.get("seat", -1)), int(_hover_slot.get("slot", -1)))
	if b != null and b.hover_anim_enabled:
		b.set_hover_pose(true, _hover_ray_local, true)

func _ray_local_for_block(b, hit_pos: Vector3) -> Vector2:
	var p: Vector3 = b.global_transform.affine_inverse() * hit_pos
	return Vector2(
		clampf(p.x / (Table3dLayout.BLOCK_SIZE.x * 0.5), -1.0, 1.0),
		clampf(p.z / (Table3dLayout.BLOCK_SIZE.z * 0.5), -1.0, 1.0))

func _leave_hover_slot() -> void:
	if _hover_slot.is_empty():
		return
	var b = _find_block(int(_hover_slot.get("seat", -1)), int(_hover_slot.get("slot", -1)))
	if b != null:
		b.set_hover_pose(false, Vector2.ZERO)
	_hover_slot = {}
```

⑤ `update_hover()` 改为每帧都更新 pose（保留原发光逻辑）：

```gdscript
func update_hover() -> bool:
	if camera == null:
		return false
	var center := get_viewport().get_visible_rect().size * 0.5
	var hit := Table3dPicker.pick_hit(camera.camera_node(), get_world_3d(), center)
	var collider = hit.get("collider")
	var prev = _hover_collider if (_hover_collider != null and is_instance_valid(_hover_collider)) else null
	if collider != prev:
		_apply_hover(prev, false)
		_hover_collider = collider
		_apply_hover(collider, true)
	_update_hover_pose(hit)
	return collider != null

## 仅 viewer 自己手牌槽驱动抬起/倾斜；其他 kind/座位不动 pose。
func _update_hover_pose(hit: Dictionary) -> void:
	var meta: Dictionary = hit.get("pick", {})
	var is_slot := str(meta.get("kind", "")) == "slot"
	if not is_slot:
		_leave_hover_slot()
		return
	var seat := int(meta.get("seat", -1))
	var slot := int(meta.get("slot", -1))
	var b = _find_block(seat, slot)
	if b == null or not b.hover_anim_enabled:
		_leave_hover_slot()
		return
	var rl := _ray_local_for_block(b, hit.get("position", Vector3.ZERO))
	_hover_ray_local = rl
	var same := not _hover_slot.is_empty() and int(_hover_slot.get("seat", -1)) == seat and int(_hover_slot.get("slot", -1)) == slot
	if same:
		b.set_hover_pose(true, rl)
	else:
		_leave_hover_slot()
		_hover_slot = {"seat": seat, "slot": slot}
		b.set_hover_pose(true, rl, false)
```

⑥ `clear_hover()` 末尾加：`_leave_hover_slot()`

- [ ] **Step 4: 运行确认通过 + 回归**

Run:
```bash
... --headless --path . res://tests/verify_table3d_interaction.tscn   # 60/60
... --headless --path . res://tests/verify_table3d.tscn               # 36/36
... --headless --path . res://tests/verify_card_animation.tscn        # 68/68
```
Expected: interaction 60/60（54 + 6）。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/table3d_view.gd tests/verify_table3d_interaction.gd
git commit -m "feat: 3D 桌面 hover 抬起/倾斜接入（仅 own 手牌 + 跨 render 保持）+ 测试"
```

---

### Task 4: 全量回归 + 交接文档

**Files:**
- Modify: `docs/AI_AGENT_交接说明.md`

- [ ] **Step 1: 全量（快）回归**

Run: `tools/run_all_tests.sh --quick`（给足超时，如 600000ms）
Expected: 全部 PASS，含 `table3d_interaction 60/60`、`table3d 36/36`、`card_animation 68/68`。

- [ ] **Step 2: 更新交接说明**

在 `docs/AI_AGENT_交接说明.md` §4 的 UI 层表格追加一行：

```
| `card_block.gd`（hover pose）/ `table3d_view.gd`（_hover_slot） | 3D 桌面 hover 抬起/倾斜：仅 viewer 自己手牌；`_visual` 视觉 pivot 保证拾取盒不随动画移动；`_hover_slot` 跨 `render()` 重建即时重放 |
```

并在 §8 的「开发约定」每轮测试列表里确认 `verify_card_animation` 已在，追加一句：3D hover 由 `verify_table3d_interaction` 覆盖。

- [ ] **Step 3: 提交**

```bash
git add docs/AI_AGENT_交接说明.md
git commit -m "doc: 记录 3D 桌面 hover 抬起/倾斜接入"
```

---

## Self-Review

**Spec coverage：**
- §3.1 视觉 pivot → Task 1；§3.2 hover pose 驱动 → Task 2；§3.3 view 接入（own/重定向/重放/clear） → Task 3；§4 测试 1–6 → Task 1/2/3；§5 文件 → File Structure；§6 风险（拾取不动/重建保持/不写 scale）→ Task 1/3 断言。
- §3.4 main.gd 不改、§1 非目标（press/flip/shadow/idle/他人）→ 无对应任务（正确）。

**Placeholder scan：** 无 TBD/TODO；代码步骤含完整代码。

**Type consistency：** `set_hover_pose(on, ray_local, immediate)` 三处在 Task 2/3 一致；`hover_anim_enabled`/`hover_progress`/`visual_node` 名称一致；`_hover_slot` 键 `seat/slot` 一致；`pick_hit` 的 `position` 键与沙盒一致。
