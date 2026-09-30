# 3D 桌面只读预览（Milestone 1）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有对局界面按 `F10` 切换到 3D 桌面只读预览，用方块 + `Label3D` 渲染公开快照并支持鼠标环视。

**Architecture:** 纯客户端展示层新增。`Table3dLayout` 提供 headless 可测的纯布局数学；`CardBlock` 是一个方块视图；`Table3dCamera` 是座位相机 rig；`Table3dView` 用代码构建 3D 节点树并按快照**全量瞬时重建**。`main.gd` 负责切换（显隐 2D、鼠标捕获）与状态转发。服务器权威 / 快照 / 协议 / 现有测试**零改动**。

**Tech Stack:** Godot 4.6（Forward Plus + Jolt）、GDScript、`Node3D`/`MeshInstance3D`/`BoxMesh`/`StandardMaterial3D`/`Label3D`/`Camera3D`/`WorldEnvironment`、headless `.tscn` 测试。

## Global Constraints

- 分支 `feature/3d-table`（已创建）。提交按 `feat:` / `test:` / `doc:` 分类。
- 每新增一个 `.gd`，Godot 会生成同名 `.uid`；提交时**一并 `git add` 该 `.uid`**（仓库既有脚本均纳入版本）。若 `class_name` 首次编译报未声明，先跑一次 `--headless --path . --import` 重建全局类缓存（本地缓存为 gitignore 产物，不影响提交）。
- **不改** `scripts/core/*`、`scripts/net/*`、`tests/*`（现有）、`docs/网络协议_V1.md`、`scripts/core/hidden_info.gd`。
- **不做** 点击交互、动画、贴图卡面、3D 菜单/遗物栏（Milestone 2+）。
- 已知 vs 未知牌**只**由快照 slot 是否含 `"card"` 决定，3D 层不做隐私判断。
- 按项目 code-built MVP 约定，3D 节点树由 `table3d_view.gd` 在代码里构建；`scenes/ui/table3d.tscn` 仅承载 `Node3D` 根 + 脚本。
- 验证命令（引擎路径按需覆盖）：
  - 编译：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5`
  - 单测：`... --headless --path . res://tests/<scene>.tscn`
  - 全量：`tools/run_all_tests.sh`
- 不启动 GUI 做自动化验证；`F10` 环视手感由人工确认。

---

## File Structure

| 文件 | 职责 |
| --- | --- |
| `scripts/ui/table3d_layout.gd`（新） | 纯函数：座位角度、槽位网格坐标、已知牌分类色、尺寸常量 |
| `scripts/ui/card_block.gd`（新） | 单张牌方块视图（`BoxMesh` + 材质 + `Label3D`） |
| `scripts/ui/table3d_camera.gd`（新） | 相机 rig：`frame_for_seat` + `look`（yaw/pitch 夹取） |
| `scripts/ui/table3d_view.gd`（新） | 代码构建 3D 树 + `render(state)` 全量重建 |
| `scenes/ui/table3d.tscn`（新） | `Node3D` 根 + `table3d_view.gd` |
| `tests/verify_table3d_layout.gd` + `.tscn`（新） | 布局纯函数断言 |
| `tests/verify_table3d.gd` + `.tscn`（新） | `CardBlock` / 相机 / `render` 节点断言 |
| `scripts/ui/main.gd`（改） | `F10` 切换、状态转发、显隐 2D、鼠标捕获、退出路径 |
| `scripts/ui/dev_tools.gd`（改） | `F10` 键 + 开发者面板「3D 预览」按钮 |
| `tools/run_all_tests.sh`（改） | 注册两个新测试 |

---

### Task 1: Table3dLayout 纯布局函数

**Files:**
- Create: `scripts/ui/table3d_layout.gd`
- Create: `tests/verify_table3d_layout.gd`
- Create: `tests/verify_table3d_layout.tscn`
- Modify: `tools/run_all_tests.sh:85`（在 `card_skin` 后加一行）

**Interfaces:**
- Consumes: 无
- Produces:
  - `Table3dLayout.BLOCK_SIZE: Vector3`、`BLOCK_GAP: Vector3`、`TABLE_RADIUS: float`、`SEAT_RADIUS: float`、`UNKNOWN_COLOR: Color`
  - `static func seat_angles(count: int) -> Array`
  - `static func slot_grid_pos(slot_index: int) -> Vector2`
  - `static func known_color_for_rank(rank: String) -> Color`
  - `static func slot_color(slot: Dictionary) -> Color`

- [ ] **Step 1: 写失败测试**

Create `tests/verify_table3d_layout.gd`:

```gdscript
extends Node
## headless 单元测试：3D 桌面只读预览的纯布局数学。

var failures := 0
var checks := 0

func _ready() -> void:
	_run()
	print("=== TABLE3D LAYOUT RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _arr_eq(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not is_equal_approx(float(a[i]), float(b[i])):
			return false
	return true

func _run() -> void:
	_check("seat_angles(2)", _arr_eq(Table3dLayout.seat_angles(2), [0.0, 180.0]))
	_check("seat_angles(3)", _arr_eq(Table3dLayout.seat_angles(3), [0.0, 120.0, 240.0]))
	_check("seat_angles(4)", _arr_eq(Table3dLayout.seat_angles(4), [0.0, 90.0, 180.0, 270.0]))
	_check("seat_angles(0)", Table3dLayout.seat_angles(0).is_empty())
	_check("slot_grid_pos 0", Table3dLayout.slot_grid_pos(0) == Vector2(0, 0))
	_check("slot_grid_pos 1", Table3dLayout.slot_grid_pos(1) == Vector2(1, 0))
	_check("slot_grid_pos 2", Table3dLayout.slot_grid_pos(2) == Vector2(0, 1))
	_check("slot_grid_pos 3", Table3dLayout.slot_grid_pos(3) == Vector2(1, 1))
	_check("slot_grid_pos 4 追加", Table3dLayout.slot_grid_pos(4) == Vector2(0, -1))
	_check("slot_grid_pos 5 追加", Table3dLayout.slot_grid_pos(5) == Vector2(1, -1))
	_check("slot_grid_pos 6 追加", Table3dLayout.slot_grid_pos(6) == Vector2(0, -2))
	var joker := Table3dLayout.known_color_for_rank("JOKER")
	var ace := Table3dLayout.known_color_for_rank("A")
	var king := Table3dLayout.known_color_for_rank("K")
	var seven := Table3dLayout.known_color_for_rank("7")
	var two := Table3dLayout.known_color_for_rank("2")
	_check("分类色 JOKER 红", joker.r > joker.b and joker.r > joker.g)
	_check("分类色 A 金", ace.r > 0.8 and ace.g > 0.7 and ace.b < 0.5)
	_check("分类色两两不同", joker != ace and ace != king and king != seven and seven != two and joker != seven)
	_check("JOKER != A", joker != ace)
	_check("slot_color 已知 A", Table3dLayout.slot_color({"card": {"rank": "A"}}) == ace)
	_check("slot_color 未知空", Table3dLayout.slot_color({}) == Table3dLayout.UNKNOWN_COLOR)
	_check("slot_color 只有 card_id 视为未知", Table3dLayout.slot_color({"card_id": "x"}) == Table3dLayout.UNKNOWN_COLOR)
	_check("方块 5:7 比例", is_equal_approx(Table3dLayout.BLOCK_SIZE.x / Table3dLayout.BLOCK_SIZE.y, 0.7))
```

Create `tests/verify_table3d_layout.tscn`:

```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/verify_table3d_layout.gd" id="1"]
[node name="VerifyTable3dLayout" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_layout.tscn`
Expected: 报错 `Table3dLayout` 未定义 / 编译错误。

- [ ] **Step 3: 写最小实现**

Create `scripts/ui/table3d_layout.gd`:

```gdscript
class_name Table3dLayout
extends RefCounted
## 3D 桌面只读预览的纯布局数学（Milestone 1）
## 职责：座位角度、槽位网格坐标、已知牌分类色、尺寸常量。
## 纯函数、无节点依赖 → headless 可测。

const BLOCK_SIZE := Vector3(0.7, 1.0, 0.04)
const BLOCK_GAP := Vector3(0.06, 0.06, 0.0)
const TABLE_RADIUS := 3.2
const SEAT_RADIUS := 2.4
const UNKNOWN_COLOR := Color(0.20, 0.20, 0.22)
const LOW_COLOR := Color(0.45, 0.55, 0.62)  # 2-6 灰蓝

const COLOR_BY_RANK := {
	"JOKER": Color(0.85, 0.25, 0.25),  # 红
	"A": Color(0.90, 0.78, 0.35),      # 金
	"K": Color(0.62, 0.45, 0.85),      # 紫
	"Q": Color(0.62, 0.45, 0.85),
	"J": Color(0.62, 0.45, 0.85),
	"10": Color(0.35, 0.60, 0.85),     # 蓝
	"9": Color(0.35, 0.60, 0.85),
	"8": Color(0.35, 0.60, 0.85),
	"7": Color(0.35, 0.60, 0.85),
}

## 座位角度（度）：viewer 恒为 0°（近侧，正对相机），其余沿圆均分。
static func seat_angles(count: int) -> Array:
	var angles: Array = []
	if count <= 0:
		return angles
	for i in count:
		angles.append(float(i) * 360.0 / float(count))
	return angles

## 槽位 -> 网格坐标（列, 行）：前 4 张 2×2（列=i%2, 行=i/2）；
## 第 5+ 张（罚牌）向上追加（idx=i-4, 列=idx%2, 行=-(1+idx/2)）。行向下为正。
static func slot_grid_pos(slot_index: int) -> Vector2:
	if slot_index < 4:
		return Vector2(float(slot_index % 2), float(slot_index / 2))
	var idx := slot_index - 4
	return Vector2(float(idx % 2), float(-(1 + idx / 2)))

## 已知牌分类色（仅展示区分）。
static func known_color_for_rank(rank: String) -> Color:
	if COLOR_BY_RANK.has(rank):
		return COLOR_BY_RANK[rank]
	return LOW_COLOR

## slot 字典 -> 方块颜色：含非空 "card" 用已知牌分类色，否则 UNKNOWN_COLOR。
static func slot_color(slot: Dictionary) -> Color:
	var card: Dictionary = slot.get("card", {})
	if card.is_empty():
		return UNKNOWN_COLOR
	return known_color_for_rank(str(card.get("rank", "")))
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... --headless --path . res://tests/verify_table3d_layout.tscn`
Expected: `=== TABLE3D LAYOUT RESULT: 19/19 passed ===`，exit 0。

- [ ] **Step 5: 注册到全量回归**

Modify `tools/run_all_tests.sh`，在 `run_single "card_skin" ...` 之后加：

```bash
run_single "table3d_layout" res://tests/verify_table3d_layout.tscn
```

- [ ] **Step 6: 提交**

```bash
git add scripts/ui/table3d_layout.gd tests/verify_table3d_layout.gd tests/verify_table3d_layout.tscn tools/run_all_tests.sh
git commit -m "feat: 3D 预览布局纯函数 + headless 测试"
```

---

### Task 2: CardBlock 方块视图

**Files:**
- Create: `scripts/ui/card_block.gd`
- Create: `tests/verify_table3d.gd`
- Create: `tests/verify_table3d.tscn`
- Modify: `tools/run_all_tests.sh`（在 `table3d_layout` 行后加 `table3d` 行）

**Interfaces:**
- Consumes: `Table3dLayout.BLOCK_SIZE`、`Table3dLayout.slot_color()`、`Table3dLayout.known_color_for_rank()`、`Table3dLayout.UNKNOWN_COLOR`
- Produces:
  - `CardBlock.PROTECTED_COLOR: Color`
  - `func setup(slot: Dictionary) -> void`
  - `static func card_text(card: Dictionary) -> String`
  - `func label_text() -> String`
  - `func block_color() -> Color`
  - `func is_emissive() -> bool`

- [ ] **Step 1: 写失败测试**

Create `tests/verify_table3d.gd`:

```gdscript
extends Node
## headless 单元测试：3D 预览的节点层（CardBlock / 相机 / 快照渲染）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TABLE3D RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_card_block()

func _test_card_block() -> void:
	var known := CardBlock.new()
	add_child(known)
	known.setup({"card": {"rank": "A", "suit": "♥"}})
	_check("CardBlock 已知牌文本 A♥", known.label_text() == "A♥")
	_check("CardBlock 已知牌颜色", known.block_color() == Table3dLayout.known_color_for_rank("A"))
	_check("CardBlock 非保护不自发光", not known.is_emissive())
	var unknown := CardBlock.new()
	add_child(unknown)
	unknown.setup({})
	_check("CardBlock 未知牌无文本", unknown.label_text() == "")
	_check("CardBlock 未知牌颜色", unknown.block_color() == Table3dLayout.UNKNOWN_COLOR)
	var prot := CardBlock.new()
	add_child(prot)
	prot.setup({"protected": true, "card": {"rank": "K", "suit": "♠"}})
	_check("CardBlock 护盾自发光", prot.is_emissive())
	_check("CardBlock 护盾紫色", prot.block_color() == CardBlock.PROTECTED_COLOR)
	_check("CardBlock 护盾仍显示点数", prot.label_text() == "K♠")
	_check("CardBlock Joker 文本", CardBlock.card_text({"rank": "JOKER", "suit": "red"}) == "JOKER")
	_check("CardBlock 空卡文本", CardBlock.card_text({}) == "")
```

Create `tests/verify_table3d.tscn`:

```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/verify_table3d.gd" id="1"]
[node name="VerifyTable3d" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... --headless --path . res://tests/verify_table3d.tscn`
Expected: `CardBlock` 未定义 / 编译错误。

- [ ] **Step 3: 写最小实现**

Create `scripts/ui/card_block.gd`:

```gdscript
class_name CardBlock
extends Node3D
## 3D 卡牌方块视图（Milestone 1 只读预览）
## 职责：把快照 slot 投影成一个方块 + 一个 Label3D（显示 rank+suit）。
## 纯展示层：不做规则/隐私判断（slot 是否含 "card" 由快照决定）。

const PROTECTED_COLOR := Color(0.62, 0.35, 0.85)

var _built := false
var _mesh: MeshInstance3D
var _label: Label3D
var _material: StandardMaterial3D

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Table3dLayout.BLOCK_SIZE
	_mesh.mesh = box
	_material = StandardMaterial3D.new()
	_mesh.material_override = _material
	add_child(_mesh)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.0025
	_label.font_size = 96
	_label.position = Vector3(0.0, 0.0, Table3dLayout.BLOCK_SIZE.z * 0.5 + 0.02)
	add_child(_label)

## 设置槽位内容：已知牌显示点数标签 + 分类色；未知牌深灰无标签。
## protected 槽位叠加紫色自发光。
func setup(slot: Dictionary) -> void:
	_build()
	var is_protected := bool(slot.get("protected", false))
	var color := PROTECTED_COLOR if is_protected else Table3dLayout.slot_color(slot)
	_material.albedo_color = color
	_material.emission_enabled = is_protected
	if is_protected:
		_material.emission = color
		_material.emission_energy_multiplier = 1.5
	var card: Dictionary = slot.get("card", {})
	_label.text = "" if card.is_empty() else card_text(card)

## 卡片显示文本（"A♥"；Joker 显示 "JOKER"；空卡空串）。
static func card_text(card: Dictionary) -> String:
	if card.is_empty():
		return ""
	var rank := str(card.get("rank", "?"))
	if rank == "JOKER":
		return "JOKER"
	return "%s%s" % [rank, str(card.get("suit", ""))]

func label_text() -> String:
	return _label.text if _label != null else ""

func block_color() -> Color:
	return _material.albedo_color if _material != null else Color.BLACK

func is_emissive() -> bool:
	return _material != null and _material.emission_enabled
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... --headless --path . res://tests/verify_table3d.tscn`
Expected: `=== TABLE3D RESULT: 10/10 passed ===`，exit 0。

- [ ] **Step 5: 注册到全量回归**

Modify `tools/run_all_tests.sh`，在 `run_single "table3d_layout" ...` 之后加：

```bash
run_single "table3d" res://tests/verify_table3d.tscn
```

- [ ] **Step 6: 提交**

```bash
git add scripts/ui/card_block.gd tests/verify_table3d.gd tests/verify_table3d.tscn tools/run_all_tests.sh
git commit -m "feat: 3D 卡牌方块视图 CardBlock + 测试"
```

---

### Task 3: Table3dCamera 相机 rig

**Files:**
- Create: `scripts/ui/table3d_camera.gd`
- Modify: `tests/verify_table3d.gd`（新增 `_test_camera()` 并在 `_run()` 调用）

**Interfaces:**
- Consumes: `Table3dLayout.SEAT_RADIUS`
- Produces:
  - `Table3dCamera.PITCH_LIMIT: float`、`YAW_LIMIT: float`、`DEFAULT_PITCH: float`
  - `var base_yaw: float`、`var yaw: float`、`var pitch: float`
  - `func frame_for_seat(seat_angle_deg: float) -> void`
  - `func look(rel: Vector2) -> void`

- [ ] **Step 1: 写失败测试**

Modify `tests/verify_table3d.gd`：把 `_run()` 改为

```gdscript
func _run() -> void:
	_test_card_block()
	_test_camera()
```

并在 `_test_card_block()` 之后新增：

```gdscript
func _test_camera() -> void:
	var rig := Table3dCamera.new()
	add_child(rig)
	rig.frame_for_seat(0.0)
	_check("相机基准朝向 0°", is_equal_approx(rig.base_yaw, 0.0))
	_check("相机默认俯角", is_equal_approx(rig.pitch, Table3dCamera.DEFAULT_PITCH))
	_check("相机座位位置", rig.position.is_equal_approx(Vector3(0.0, 1.6, Table3dLayout.SEAT_RADIUS)))
	rig.look(Vector2(1000.0, 1000.0))
	_check("yaw 上夹 90", is_equal_approx(rig.yaw, Table3dCamera.YAW_LIMIT))
	_check("pitch 上夹 60", is_equal_approx(rig.pitch, Table3dCamera.PITCH_LIMIT))
	rig.look(Vector2(-5000.0, -5000.0))
	_check("yaw 下夹 -90", is_equal_approx(rig.yaw, -Table3dCamera.YAW_LIMIT))
	_check("pitch 下夹 -60", is_equal_approx(rig.pitch, -Table3dCamera.PITCH_LIMIT))
	rig.frame_for_seat(180.0)
	_check("对面基准朝向 180°", is_equal_approx(rig.base_yaw, 180.0))
	_check("对面座位位置", rig.position.is_equal_approx(Vector3(0.0, 1.6, -Table3dLayout.SEAT_RADIUS)))
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... --headless --path . res://tests/verify_table3d.tscn`
Expected: `Table3dCamera` 未定义 / 编译错误。

- [ ] **Step 3: 写最小实现**

Create `scripts/ui/table3d_camera.gd`:

```gdscript
class_name Table3dCamera
extends Node3D
## 3D 预览相机 rig（Milestone 1）
## 结构：CameraRig(yaw, 本节点) → PitchPivot(pitch) → Camera3D。
## 职责：把 rig 摆到某座位并朝桌心，随后由鼠标相对位移驱动 yaw/pitch（夹取）。

const PITCH_LIMIT := 60.0
const YAW_LIMIT := 90.0
const DEFAULT_PITCH := 20.0  # 正=俯视
const EYE_HEIGHT := 1.6

var base_yaw := 0.0
var yaw := 0.0
var pitch := DEFAULT_PITCH

var _built := false
var _pivot: Node3D
var _camera: Camera3D

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	_pivot = Node3D.new()
	_pivot.name = "PitchPivot"
	add_child(_pivot)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_pivot.add_child(_camera)

## 把相机摆到角度 seat_angle_deg 对应的座位后方，基准朝向桌心。
## 座位在圆上角度 a（0°=近侧 +Z），rig +Z 沿径向外，故 -Z（相机视线）朝桌心。
func frame_for_seat(seat_angle_deg: float) -> void:
	_build()
	var a := deg_to_rad(seat_angle_deg)
	var dir := Vector3(sin(a), 0.0, cos(a))
	position = dir * Table3dLayout.SEAT_RADIUS + Vector3(0.0, EYE_HEIGHT, 0.0)
	base_yaw = rad_to_deg(atan2(dir.x, dir.z))
	yaw = base_yaw
	pitch = DEFAULT_PITCH
	_apply()

## 鼠标相对位移（像素）驱动环视：yaw 夹在基准 ±YAW_LIMIT，pitch 夹 ±PITCH_LIMIT。
func look(rel: Vector2) -> void:
	yaw = clampf(yaw + rel.x, base_yaw - YAW_LIMIT, base_yaw + YAW_LIMIT)
	pitch = clampf(pitch + rel.y, -PITCH_LIMIT, PITCH_LIMIT)
	_apply()

func _apply() -> void:
	rotation_degrees = Vector3(0.0, yaw, 0.0)
	_pivot.rotation_degrees = Vector3(-pitch, 0.0, 0.0)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... --headless --path . res://tests/verify_table3d.tscn`
Expected: `=== TABLE3D RESULT: 19/19 passed ===`，exit 0。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/table3d_camera.gd tests/verify_table3d.gd
git commit -m "feat: 3D 预览相机 rig（座位取景 + 鼠标环视夹取）"
```

---

### Task 4: Table3dView 渲染器 + table3d.tscn

**Files:**
- Create: `scripts/ui/table3d_view.gd`
- Create: `scenes/ui/table3d.tscn`
- Modify: `tests/verify_table3d.gd`（新增 `_test_view_render()` 并在 `_run()` 调用）

**Interfaces:**
- Consumes: `CardBlock`、`Table3dCamera`、`Table3dLayout.seat_angles/slot_grid_pos/BLOCK_SIZE/BLOCK_GAP/TABLE_RADIUS/SEAT_RADIUS`
- Produces:
  - `Table3dView.set_active(on: bool) -> void`
  - `Table3dView.render(state: Dictionary) -> void`
  - `Table3dView.camera`（untyped，实为 `Table3dCamera`）、`Table3dView._seat_nodes: Array`

- [ ] **Step 1: 写失败测试**

Modify `tests/verify_table3d.gd`：把 `_run()` 改为

```gdscript
func _run() -> void:
	_test_card_block()
	_test_camera()
	await _test_view_render()
```

并新增：

```gdscript
func _test_view_render() -> void:
	var scene: PackedScene = load("res://scenes/ui/table3d.tscn")
	var view := scene.instantiate()
	add_child(view)
	await get_tree().process_frame
	var state := {
		"viewer_id": 0,
		"players": [
			{"id": 0, "name": "甲", "count": 2, "currency": 100, "health": 2, "eliminated": false,
			 "slots": [{"card_id": "c1"}, {"card_id": "c2"}, {"card_id": "c3"},
			           {"card_id": "c4", "card": {"rank": "A", "suit": "♥"}}]},
			{"id": 1, "name": "乙", "count": 1, "currency": 80, "health": 2, "eliminated": false,
			 "slots": [{"card_id": "c9"}, {"card_id": "c10"}, {"card_id": "c11"}, {"card_id": "c12"}]},
		],
		"draw_count": 30,
		"discard": {},
		"pending": {},
		"phase": 2,
	}
	view.render(state)
	await get_tree().process_frame
	_check("viewer 座位可见", view._seat_nodes[0].visible)
	_check("对手座位可见", view._seat_nodes[1].visible)
	_check("空座位隐藏", not view._seat_nodes[2].visible and not view._seat_nodes[3].visible)
	_check("viewer 手牌 4 槽", view._seat_nodes[0].get_node("HandAnchor").get_child_count() == 4)
	_check("viewer 名字标签", view._seat_nodes[0].get_node("NameLabel").text == "甲")
	_check("viewer 货币标签含 ¥100", view._seat_nodes[0].get_node("StatLabel").text.contains("¥100"))
	_check("对手名字标签", view._seat_nodes[1].get_node("NameLabel").text == "乙")
	_check("viewer 相机基准 0°", is_equal_approx(view.camera.base_yaw, 0.0))
	var found_ace := false
	for child in view._seat_nodes[0].get_node("HandAnchor").get_children():
		if child is CardBlock and child.label_text() == "A♥":
			found_ace = true
	_check("已知牌 A♥ 渲染", found_ace)
	var hidden_ok := true
	for child in view._seat_nodes[1].get_node("HandAnchor").get_children():
		if child is CardBlock and child.label_text() != "":
			hidden_ok = false
	_check("他人未知牌无点数标签", hidden_ok)
	# 弃牌顶与 pending 已知牌渲染
	view.render({
		"viewer_id": 0,
		"players": state.players,
		"draw_count": 29,
		"discard": {"rank": "7", "suit": "♣"},
		"pending": {"rank": "Q", "suit": "♦", "source": "draw"},
		"phase": 3,
	})
	await get_tree().process_frame
	var center = view.get_node("Center")
	_check("弃牌顶标签 7♣", (center.get_node("DiscardTop") as CardBlock).label_text() == "7♣")
	_check("pending 标签 Q♦", (center.get_node("Pending") as CardBlock).label_text() == "Q♦")
	_check("pending 可见", (center.get_node("Pending") as Node3D).visible)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... --headless --path . res://tests/verify_table3d.tscn`
Expected: `res://scenes/ui/table3d.tscn` 加载失败 / 编译错误。

- [ ] **Step 3: 写最小实现**

Create `scripts/ui/table3d_view.gd`:

```gdscript
class_name Table3dView
extends Node3D
## 3D 桌面只读预览渲染器（Milestone 1）
## 职责：代码构建 3D 节点树（环境/相机/桌面/座位/中央牌堆），按快照全量重建方块。
## 只读：不处理点击、不做动画、不做隐私判断（已知/未知由快照 slot 是否含 "card" 决定）。

const CardBlockScript := preload("res://scripts/ui/card_block.gd")
const CameraScript := preload("res://scripts/ui/table3d_camera.gd")

const SEAT_COUNT := 4
const HAND_BASE_HEIGHT := 1.0
const CENTER_DECK := Vector3(0.0, 0.15, 0.0)
const CENTER_DISCARD := Vector3(0.9, 0.08, 0.0)
const CENTER_PENDING := Vector3(-0.9, 0.9, -0.0)
const BACKGROUND_COLOR := Color(0.07, 0.08, 0.10)

var camera = null  # Table3dCamera
var _built := false
var _seat_nodes: Array = []
var _deck_label: Label3D
var _discard_block = null  # CardBlock
var _pending_block = null  # CardBlock

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	# 环境光：保证方块与护盾自发光可见
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BACKGROUND_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.2
	env.environment = e
	add_child(env)
	# 相机
	camera = CameraScript.new()
	camera.name = "CameraRig"
	add_child(camera)
	# 桌面
	var table := MeshInstance3D.new()
	table.name = "Table"
	var box := BoxMesh.new()
	box.size = Vector3(Table3dLayout.TABLE_RADIUS * 2.0, 0.08, Table3dLayout.TABLE_RADIUS * 2.0)
	table.mesh = box
	table.position = Vector3(0.0, -0.04, 0.0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.16, 0.18, 0.22)
	table.material_override = tmat
	add_child(table)
	# 座位（持久锚点，仅内容每次重建）
	var seats := Node3D.new()
	seats.name = "Seats"
	add_child(seats)
	for i in SEAT_COUNT:
		var seat := Node3D.new()
		seat.name = "Seat%d" % i
		var hand := Node3D.new()
		hand.name = "HandAnchor"
		hand.position = Vector3(0.0, HAND_BASE_HEIGHT, 0.0)
		seat.add_child(hand)
		var name_label := Label3D.new()
		name_label.name = "NameLabel"
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.no_depth_test = true
		name_label.pixel_size = 0.004
		name_label.font_size = 64
		name_label.position = Vector3(0.0, 0.55, 0.0)
		seat.add_child(name_label)
		var stat_label := Label3D.new()
		stat_label.name = "StatLabel"
		stat_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stat_label.no_depth_test = true
		stat_label.pixel_size = 0.003
		stat_label.font_size = 64
		stat_label.position = Vector3(0.0, 0.30, 0.0)
		seat.add_child(stat_label)
		seats.add_child(seat)
		_seat_nodes.append(seat)
	# 中央：抽牌堆（摞方块 + 数量标签）/ 弃牌顶 / pending
	var center := Node3D.new()
	center.name = "Center"
	add_child(center)
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	var deck_box := BoxMesh.new()
	deck_box.size = Vector3(0.7, 0.25, 1.0)
	deck.mesh = deck_box
	deck.position = CENTER_DECK
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.30, 0.32, 0.38)
	deck.material_override = dmat
	center.add_child(deck)
	_deck_label = Label3D.new()
	_deck_label.name = "DeckCount"
	_deck_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_deck_label.no_depth_test = true
	_deck_label.pixel_size = 0.004
	_deck_label.font_size = 64
	_deck_label.position = CENTER_DECK + Vector3(0.0, 0.6, 0.0)
	center.add_child(_deck_label)
	_discard_block = CardBlockScript.new()
	_discard_block.name = "DiscardTop"
	_discard_block.position = CENTER_DISCARD
	center.add_child(_discard_block)
	_pending_block = CardBlockScript.new()
	_pending_block.name = "Pending"
	_pending_block.position = CENTER_PENDING
	_pending_block.scale = Vector3(1.5, 1.5, 1.5)
	center.add_child(_pending_block)

## 显示/隐藏预览（不处理点击与动画）。
func set_active(on: bool) -> void:
	visible = on

## 按快照全量重建（无增量、无插值）。state 为 HiddenInfo 投影出的公开快照。
func render(state: Dictionary) -> void:
	_build()
	if state.is_empty():
		return
	var players: Array = state.get("players", [])
	if players.is_empty():
		return
	var viewer := int(state.get("viewer_id", 0))
	var angles := Table3dLayout.seat_angles(players.size())
	var others: Array = []
	for p in players:
		if int(p.id) != viewer:
			others.append(int(p.id))
	others.sort()
	var seat_angle := {viewer: float(angles[0])}
	for i in others.size():
		seat_angle[int(others[i])] = float(angles[i + 1])
	# 相机取景
	if camera != null:
		camera.frame_for_seat(float(seat_angle.get(viewer, 0.0)))
	# 座位
	for i in SEAT_COUNT:
		_seat_nodes[i].visible = false
	var slot_i := 0
	for p in players:
		if slot_i >= SEAT_COUNT:
			break
		var node: Node3D = _seat_nodes[slot_i]
		var seat := int(p.id)
		var a := float(seat_angle.get(seat, 0.0))
		node.visible = true
		node.position = _seat_world(a)
		node.rotation_degrees = Vector3(0.0, a + 180.0, 0.0)
		_render_seat(node, p)
		slot_i += 1
	# 中央
	_deck_label.text = str(int(state.get("draw_count", 0)))
	var discard: Dictionary = state.get("discard", {})
	_discard_block.setup({"card": discard} if not discard.is_empty() else {})
	var pending: Dictionary = state.get("pending", {})
	_pending_block.visible = not pending.is_empty()
	if not pending.is_empty():
		_pending_block.setup({"card": pending} if pending.has("rank") else {})

## 座位世界坐标（与相机基准同一角度约定）。
func _seat_world(angle_deg: float) -> Vector3:
	var a := deg_to_rad(angle_deg)
	return Vector3(sin(a), 0.0, cos(a)) * Table3dLayout.SEAT_RADIUS

## 重建单个座位的方块与标签。
func _render_seat(node: Node3D, p: Dictionary) -> void:
	var hand: Node3D = node.get_node("HandAnchor")
	for child in hand.get_children():
		hand.remove_child(child)
		child.queue_free()
	var slots: Array = p.get("slots", [])
	for i in slots.size():
		var block = CardBlockScript.new()
		var grid: Vector2 = Table3dLayout.slot_grid_pos(i)
		block.position = Vector3(
			grid.x * (Table3dLayout.BLOCK_SIZE.x + Table3dLayout.BLOCK_GAP.x),
			-grid.y * (Table3dLayout.BLOCK_SIZE.y + Table3dLayout.BLOCK_GAP.y),
			0.0)
		hand.add_child(block)
		block.setup(slots[i])
	var name_label: Label3D = node.get_node("NameLabel")
	var stat_label: Label3D = node.get_node("StatLabel")
	name_label.text = str(p.get("name", ""))
	stat_label.text = "%d张  ¥%d  ♥%d" % [int(p.get("count", 0)), int(p.get("currency", 0)), int(p.get("health", 0))]
	var tint := Color(1, 1, 1, 0.5) if bool(p.get("eliminated", false)) else Color(1, 1, 1, 1)
	name_label.modulate = tint
	stat_label.modulate = tint
```

Create `scenes/ui/table3d.tscn`:

```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://scripts/ui/table3d_view.gd" id="1"]
[node name="Table3D" type="Node3D"]
script = ExtResource("1")
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... --headless --path . res://tests/verify_table3d.tscn`
Expected: `=== TABLE3D RESULT: 32/32 passed ===`，exit 0。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/table3d_view.gd scenes/ui/table3d.tscn tests/verify_table3d.gd
git commit -m "feat: 3D 预览渲染器与场景实体（快照全量重建）"
```

---

### Task 5: main.gd / dev_tools.gd 集成（F10 切换）

**Files:**
- Modify: `scripts/ui/main.gd`（`_unhandled_input`、新增 `_toggle_table3d`/`_set_table3d`、`_on_state_updated`、`_notification`、`_on_match_aborted`、`_leave_to_main_menu`）
- Modify: `scripts/ui/dev_tools.gd`（`handle_input` 加 F10；`refresh_panel` 加按钮）
- Modify: `docs/AI_AGENT_交接说明.md`（基线补一行）

**Interfaces:**
- Consumes: `Table3dView.set_active/render`、`Table3dView.camera`、`Table3dCamera.look`
- Produces: `main._toggle_table3d()`、`main._set_table3d(on: bool)`

- [ ] **Step 1: 加成员变量**

Modify `scripts/ui/main.gd`，在 `var board: Control` 之后加：

```gdscript
var table3d: Node3D = null
var _table3d_active := false
```

- [ ] **Step 2: 输入优先处理 3D 环视与 F10**

Modify `scripts/ui/main.gd` 的 `_unhandled_input(event)`，在函数体最前面插入：

```gdscript
	# 3D 只读预览：F10/ESC 退出，鼠标环视；期间不接管其它对局输入
	if _table3d_active:
		if event is InputEventKey and event.pressed and not event.echo \
				and (event.keycode == KEY_F10 or event.keycode == KEY_ESCAPE):
			_set_table3d(false)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if table3d != null and is_instance_valid(table3d):
				table3d.camera.look(event.relative)
				get_viewport().set_input_as_handled()
			return
```

- [ ] **Step 3: 新增切换方法**

Modify `scripts/ui/main.gd`，在 `_leave_to_main_menu()` 之后加：

```gdscript
## F10：在 2D 对局界面与 3D 只读预览之间切换。
func _toggle_table3d() -> void:
	_set_table3d(not _table3d_active)

## 3D 只读预览开关（仅对局中可用）。激活时隐藏 2D 棋盘（含 background，
## 否则 CanvasItem 会盖住 3D）并捕获鼠标；退出时恢复并重绘 2D。
func _set_table3d(on: bool) -> void:
	if on and (latest_state.is_empty() or int(latest_state.get("phase", PHASE_LOBBY)) == PHASE_LOBBY):
		return
	_table3d_active = on
	if on:
		if table3d == null or not is_instance_valid(table3d):
			table3d = load("res://scenes/ui/table3d.tscn").instantiate()
			table3d.name = "Table3D"
			add_child(table3d)
			move_child(table3d, 0)
		table3d.set_active(true)
		background.visible = false
		game_panel.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		table3d.render(latest_state)
	else:
		if table3d != null and is_instance_valid(table3d):
			table3d.set_active(false)
		background.visible = true
		game_panel.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_render_game()
```

- [ ] **Step 4: 状态更新时转发给 3D，并在 3D 下不显示 2D 棋盘**

Modify `scripts/ui/main.gd` 的 `_on_state_updated`：

1. 把 `game_panel.visible = true` 改为 `game_panel.visible = not _table3d_active`。
2. 在 `dev.refresh_panel()` 之后加：

```gdscript
	if _table3d_active and table3d != null and is_instance_valid(table3d):
		table3d.render(state)
```

- [ ] **Step 5: 离开/中止/关窗时强制退出 3D**

Modify `scripts/ui/main.gd`：

1. `_notification` 的 `NOTIFICATION_WM_CLOSE_REQUEST` 分支，在 `if _in_room():` 之前加：

```gdscript
		if _table3d_active:
			_set_table3d(false)
```

2. `_leave_to_main_menu()` 开头加：

```gdscript
	if _table3d_active:
		_set_table3d(false)
```

3. `_on_match_aborted(_code, message)` 开头加：

```gdscript
	if _table3d_active:
		_set_table3d(false)
```

- [ ] **Step 6: dev_tools 加 F10 与面板按钮**

Modify `scripts/ui/dev_tools.gd` 的 `handle_input`，在 `elif event.keycode == KEY_T:` 分支之后加：

```gdscript
		elif event.keycode == KEY_F10:
			main._toggle_table3d()
			return true
```

Modify `refresh_panel()`，在 `_build_skin_row(box)` 之后加：

```gdscript
	var preview_btn := Button.new()
	preview_btn.text = "3D 预览（F10）"
	preview_btn.pressed.connect(main._toggle_table3d)
	box.add_child(preview_btn)
```

- [ ] **Step 7: 编译检查 + 新增测试**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_layout.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d.tscn
```
Expected: 编译无 `SCRIPT ERROR` / `Parse Error`；两个测试分别 19/19、32/32。

- [ ] **Step 8: 回归（确认零影响）**

Run:
```bash
tools/run_all_tests.sh --quick
```
Expected: 全 PASS，新增 `table3d_layout` / `table3d` 两项亦 PASS。

- [ ] **Step 9: 更新交接说明**

Modify `docs/AI_AGENT_交接说明.md` 第 2 节「当前基线」，在卡牌皮肤条目之后加一行：

```markdown
- **3D 桌面只读预览（Milestone 1，分支 `feature/3d-table`）**：对局中按 `F10` 在 2D 界面与 3D 桌面间切换；3D 用方块 + `Label3D` 渲染公开快照（座位手牌、抽牌堆数量、弃牌顶、中央 pending、名字/张数/货币/生命），鼠标环视（pitch ±60°、yaw 基准 ±90°）。纯客户端展示层：`scripts/ui/table3d_layout.gd`（纯函数布局）/`card_block.gd`/`table3d_camera.gd`/`table3d_view.gd` + `scenes/ui/table3d.tscn`。**不改**规则/协议/快照/现有测试。测试 `verify_table3d_layout`（19/19）、`verify_table3d`（32/32）。不做点击交互与动画（Milestone 2+）。
```

- [ ] **Step 10: 提交**

```bash
git add scripts/ui/main.gd scripts/ui/dev_tools.gd docs/AI_AGENT_交接说明.md
git commit -m "feat: F10 切换 3D 桌面只读预览（main/dev_tools 集成）"
```

---

## 人工验收（不纳入自动化）

- 启动对局后按 `F10`：应进入 3D 桌面，鼠标移动可环视，`F10`/`ESC` 退出回 2D。
- 进入时 2D 棋盘与背景不可见（无 2D 盖住 3D）；退出后 2D 正常重绘。
- 座次：自己在一侧，对手按人数分布在圆桌上；自己的可看牌显示点数，他人显示深灰方块。
- 对局中换人行动 / 抽牌 / 结算后切到 3D，方块与标签应反映当前快照。

## Self-Review 结论

- **Spec 覆盖**：§2 文件 → Task 1–5；§3 布局 → Task 1/4；§4 映射 → Task 2/4；§5 输入 → Task 3/5；§6 接口 → Task 1；§7 测试 → Task 1/2（+4 扩展）；§8 风险（background 遮盖、ESC/鼠标、退出路径）→ Task 5 Step 2/4/5。无缺口。
- **占位符**：无 TBD/TODO；所有代码步骤均给完整代码。
- **类型一致性**：`Table3dLayout.*` 常量与静态方法在两处测试与两个实现文件中名称一致；`CardBlock.setup/label_text/block_color/is_emissive`、`Table3dCamera.frame_for_seat/look/base_yaw/pitch/yaw`、`Table3dView.set_active/render/camera/_seat_nodes` 跨任务一致。
