# 3D 大牌（Pending）竖立悬浮 + 面向玩家 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 3D 对局中的大牌（`Center/Pending`）竖立悬浮在抽牌堆与弃牌堆之间，并每帧绕世界 Y 朝向本机相机（当前行动者看正面、其他人看背面）。

**Architecture:** 复用现有 `Center/Pending` 节点（故换牌/弃牌飞牌零改动）。`table3d_view` 在 `_bind()` 设置其本地点为牌堆中点、抬高到 `PENDING_Y`；新增 `update_facing()` 由 `main._process` 每帧把根节点 basis 重写为 yaw-billboard（本地 +Y→水平指向相机、本地 +Z→世界向上），保持竖直。`CardBlock` 增加 opt-in `set_upright(true)` 让文字标签浮到牌顶。纯客户端展示层，规则/协议/快照零改动。

**Tech Stack:** Godot 4.6 GDScript，headless 单元测试（`.tscn` + `_check` 断言）。

## Global Constraints

- 纯客户端展示层：**不改** `scripts/core/*`、`scripts/net/*`、`scenes/ui/table3d.tscn`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`、`card_fly*.gd`。
- 不改规则 / 协议 / 快照；2D 大牌与 2D 逻辑逐字不动。
- **不启动 GUI**；只用 headless 单测验证。
- 新增常量 `PENDING_Y := 0.75`；中点 = 抽牌堆(`Deck`) 与弃牌堆(`DiscardTop`) 的 XZ 中点（当前 ≈ `(0.45, 0.75, 0)`）。
- Godot 引擎路径：`/Applications/Godot.app/Contents/MacOS/Godot`（可用 `$GODOT` 覆盖）。
- 提交按 `feat/fix/doc` 分类；**本项目未获用户明确要求前不执行 git commit**（下述提交步骤仅在用户授权后执行）。

---

### Task 1: CardBlock 竖立标签方向 `set_upright(on)`

**Files:**
- Modify: `scripts/ui/card_block.gd`（新增 `_upright` 变量 + `set_upright()` 方法）
- Test: `tests/verify_table3d_interaction.gd`（`_test_card_block` 内追加断言）

**Interfaces:**
- Produces: `CardBlock.set_upright(on: bool) -> void`（默认状态等价 `set_upright(false)`；`on=true` 时 `_label.position = (0, 0, BLOCK_SIZE.z*0.5+0.08)`，`on=false` 时恢复 `(0, BLOCK_SIZE.y*0.5+0.08, 0)`）。
- Produces: `CardBlock._label: Label3D`（已存在；测试通过它检查位置）。

- [ ] **Step 1: 写失败测试**

在 `tests/verify_table3d_interaction.gd` 的 `_test_card_block()` 末尾（第 80 行 `_check("揭示 pivot 在 visual 下", ...)` 之后）追加：

```gdscript
	# 竖立模式：标签从法向正上方(+Y) 移到牌高顶端(+Z)
	var ub := CardBlock.new()
	add_child(ub)
	ub.set_upright(true)
	_check("upright 标签移到牌顶(+Z)", ub._label.position.z > 0.0 and is_zero_approx(ub._label.position.y))
	ub.set_upright(false)
	_check("upright 关闭恢复标签(+Y)", ub._label.position.y > 0.0 and is_zero_approx(ub._label.position.z))
```

- [ ] **Step 2: 运行测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: FAIL（`Invalid call. Nonexistent function 'set_upright'`），进程非 0 退出。

- [ ] **Step 3: 最小实现**

在 `scripts/ui/card_block.gd` 的变量区（`var _hovered := false` 附近、第 43 行后）加：

```gdscript
var _upright := false
```

在 `label_text()`（第 392-393 行）之后新增方法：

```gdscript
## 竖立显示模式：标签从卡面法向正上方（本地 +Y）改到卡高方向顶端（本地 +Z）。
## 仅用于竖立的大牌；默认关闭，不影响手牌/弃牌/飞牌等平铺卡。
func set_upright(on: bool) -> void:
	_build()
	_upright = on
	if _label == null:
		return
	if on:
		_label.position = Vector3(0.0, 0.0, Table3dLayout.BLOCK_SIZE.z * 0.5 + 0.08)
	else:
		_label.position = Vector3(0.0, Table3dLayout.BLOCK_SIZE.y * 0.5 + 0.08, 0.0)
```

（`setup()` 不重置 `_upright`，使其在 `render()` 重建内容后保持。）

- [ ] **Step 4: 运行测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: PASS（全部通过，进程 0 退出）。

- [ ] **Step 5: 提交（仅在用户授权后）**

```bash
git add scripts/ui/card_block.gd tests/verify_table3d_interaction.gd
git commit -m "feat: CardBlock 竖立标签方向 set_upright"
```

---

### Task 2: table3d_view 大牌中点位置 + `update_facing()`

**Files:**
- Modify: `scripts/ui/table3d_view.gd`（常量 `PENDING_Y`；`_bind()` 设位置与 upright；新增 `update_facing()`）
- Test: `tests/verify_table3d_interaction.gd`（`_test_view` 内追加断言）

**Interfaces:**
- Consumes: `CardBlock.set_upright(on)`（Task 1）。
- Produces: `Table3dView.PENDING_Y: float`（= 0.75）。
- Produces: `Table3dView.update_facing() -> void`（按本机相机把 `Center/Pending` 根节点 global basis 重写为 yaw-billboard；不改位置）。
- Produces: `_bind()` 副作用——`Center/Pending.position == (mid.x, PENDING_Y, mid.z)`（mid = `Deck`/`DiscardTop` 本地位置中点），且 `Pending` 进入 `set_upright(true)`。

- [ ] **Step 1: 写失败测试**

在 `tests/verify_table3d_interaction.gd` 的 `_test_view()` 中，找到断言 `_check("默认准星指向牌堆", ...)`（第 157 行）之前，插入一段（`view` 已在第 136 行实例化并 `add_child`）：

```gdscript
	# 大牌竖立悬浮 + 面向本机相机
	var pnode: Node3D = view.get_node("Center/Pending")
	var dnode: Node3D = view.get_node("Center/Deck")
	var xnode: Node3D = view.get_node("Center/DiscardTop")
	var mid := Vector3((dnode.position.x + xnode.position.x) * 0.5, Table3dView.PENDING_Y, (dnode.position.z + xnode.position.z) * 0.5)
	_check("大牌位于牌堆中点/悬浮高度", pnode.position.distance_to(mid) < 0.001)
	view.update_facing()
	var b := pnode.global_transform.basis
	_check("大牌竖直(+Z 对齐世界上方)", b.z.dot(Vector3.UP) > 0.99)
	_check("大牌无俯仰(+Y.y≈0)", absf(b.y.y) < 0.01)
	var cam: Camera3D = view.camera.camera_node()
	var horiz := cam.global_position - pnode.global_position
	horiz.y = 0.0
	_check("大牌朝向相机(+Y 指向相机水平方向)", horiz.length_squared() > 0.0001 and b.y.dot(horiz.normalized()) > 0.99)
	_check("大牌标签竖立在牌顶", (view.get_node("Center/Pending") as CardBlock)._label.position.z > 0.0)
```

注意：`_test_view()` 第 136 行实例化 `view` 后已渲染快照（含 `pending` 空）。若该函数对 `pending` 未渲染（保持不可见），`update_facing()` 仍应正常工作（不依赖可见性），断言成立。

- [ ] **Step 2: 运行测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: FAIL（`Nonexistent function 'update_facing'` / 位置不匹配）。

- [ ] **Step 3: 最小实现**

在 `scripts/ui/table3d_view.gd` 常量区（第 18 行 `STAT_PANEL_PIXEL_SIZE` 之后）加：

```gdscript
const PENDING_Y := 0.75  # 大牌竖立悬浮中心离桌高度（牌高 1.0 → 底≈0.25、顶≈1.25）
```

在 `_bind()` 中第 86 行 `_pending_node = _pending_block` 之后追加：

```gdscript
	if _pending_node != null and _deck_node != null and _discard_node != null:
		var mid := (_deck_node.position + _discard_node.position) * 0.5
		_pending_node.position = Vector3(mid.x, PENDING_Y, mid.z)
	if _pending_block != null and _pending_block.has_method("set_upright"):
		_pending_block.set_upright(true)
```

在 `_bind()` 之外（例如 `pick_center()` 之后）新增：

```gdscript
## 每帧让大牌绕世界 Y 朝向本机相机（保持竖直，不用含俯仰的完全 billboard）。
## 位置不变，只重写 basis：本地 +Y（卡面法向）→ 水平指向相机；本地 +Z（卡高）→ 世界向上。
func update_facing() -> void:
	if _pending_node == null or not is_instance_valid(_pending_node) or camera == null:
		return
	var cam: Camera3D = camera.camera_node()
	if cam == null:
		return
	var node := _pending_node as Node3D
	var origin := node.global_position
	var to_cam := cam.global_position - origin
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.0001:
		return
	var fwd := to_cam.normalized()
	var up := Vector3.UP
	var x := fwd.cross(up)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	node.global_transform = Transform3D(Basis(x, fwd, up), origin)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: PASS。

- [ ] **Step 5: 提交（仅在用户授权后）**

```bash
git add scripts/ui/table3d_view.gd tests/verify_table3d_interaction.gd
git commit -m "feat: 3D 大牌竖立悬浮于牌堆中点并朝向本机相机"
```

---

### Task 3: main 每帧调用 `update_facing()` + 文档 + 全量回归

**Files:**
- Modify: `scripts/ui/main.gd:231-252`（`_process` 内追加调用）
- Modify: `docs/AI_AGENT_交接说明.md`（3D 桌面对局/大牌一句）
- Modify: `docs/功能实现文档.md`（补 `update_facing` / `set_upright` 映射）

**Interfaces:**
- Consumes: `Table3dView.update_facing() -> void`（Task 2）。

- [ ] **Step 1: 接线**

在 `scripts/ui/main.gd` 的 `_process()` 中，第 236-237 行 `board.set_facing(...)` 块之后追加：

```gdscript
	if table3d != null and is_instance_valid(table3d):
		table3d.update_facing()
```

- [ ] **Step 2: 编译检查**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5`
Expected: 无脚本错误。

- [ ] **Step 3: 全量回归**

Run: `tools/run_all_tests.sh`
Expected: 全部 PASS（含 `verify_table3d_interaction`、`verify_table3d`、`verify_table3d_mouse`、`verify_table3d_exchange`、`verify_card_fly`、双实例 `verify_net`）。

- [ ] **Step 4: 文档**

- `docs/AI_AGENT_交接说明.md`：在 3D 桌面对局段补一句「大牌（`Center/Pending`）竖立悬浮于抽牌堆/弃牌堆中点并每帧朝向本机相机（`table3d_view.update_facing()` + `CardBlock.set_upright()`）」。
- `docs/功能实现文档.md`：`table3d_view.gd` 行补 `update_facing/PENDING_Y`；`card_block.gd` 行补 `set_upright`。

- [ ] **Step 5: 提交（仅在用户授权后）**

```bash
git add scripts/ui/main.gd "docs/AI_AGENT_交接说明.md" "docs/功能实现文档.md"
git commit -m "feat: 3D 大牌每帧朝向本机相机接入 + 文档"
```

---

## Self-Review

- **Spec 覆盖**：位置中点/高度（Task 2）、竖直 + 朝向相机（Task 2）、正/反沿用快照（无代码改动，验证于现有 `verify_table3d.gd`）、标签竖立（Task 1）、动画兼容（复用同一节点，Task 2 不新增/搬移节点）、拾取随旋转（不改）、每帧刷新（Task 3）、测试与验收（Task 1/2 + Task 3 全量）——均有对应任务。
- **占位符扫描**：无 TBD/TODO；所有步骤含具体代码与命令。
- **类型一致性**：`set_upright(on: bool)`、`update_facing()`、`PENDING_Y` 在 Task 1/2/3 命名与签名一致；`_label.position` 断言与实现一致。
