# 3D 桌面对局（Milestone 2：准星点击 / 可玩）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 3D 预览里用屏幕中心准星点击卡牌/牌堆/HUD 按钮，把点击接到既有 `GameInteraction`/`request_*`，实现可完整打完一局的 3D 视角（无动画）。

**Architecture:** 在 Milestone 1 的展示层上加「拾取 + 分发」。`Area3D` 只作拾取标记（独立物理层 2，metadata 携带语义），`Table3dPicker` 用纯函数从相机屏幕中心发射线取 metadata；`main` 把命中结果分发到既有入口。3D 操作面板（`Table3dHud`）与中央牌堆同样挂拾取标记。高亮/揭示为瞬时材质与标签改写。

**Tech Stack:** Godot 4.6 GDScript、`Area3D`/`BoxShape3D`/`PhysicsRayQueryParameters3D`/`intersect_ray`、`Label3D`、headless `.tscn` 测试。

**Spec:** `docs/superpowers/specs/2026-09-21-table3d-interaction-design.md`

## Global Constraints

- 分支 `feature/3d-table`。提交按 `feat:` / `test:` / `fix:` / `doc:` 分类；新增 `.gd` 同时 `git add` 其 `.uid`。
- **不改**：`scripts/core/*`、`scripts/net/*`、`scripts/core/hidden_info.gd`、`scripts/ui/game_interaction.gd`、现有测试（`verify_table3d*` 只在指定任务里按需扩展）。
- 不做动画、不做 3D 菜单、不做贴图卡面。
- 点击只走既有入口：`GameInteraction.on_card_pressed` / `GameState.request_*` / `main._on_pending_action`。
- 拾取层：`Table3dLayout.PICK_LAYER == 2`，`PICK_MASK == 1 << (PICK_LAYER - 1) == 2`。
- 颜色优先级：`protected`(紫) > `actionable`(金) > 分类色/未知灰。
- 验证命令：
  - 编译：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5`
  - 测试：`... --headless --path . res://tests/<scene>.tscn`
  - 全量：`tools/run_all_tests.sh --quick`
  - 若报 `Identifier "X" not declared`：先 `--headless --path . --import` 重建类缓存。
- 不启 GUI 做自动化验证；准星手感与整局流程由人工验收。

---

## File Structure

| 文件 | 职责 |
| --- | --- |
| `scripts/ui/table3d_layout.gd`（改） | 新增 `PICK_LAYER`/`PICK_MASK`/`ACTIONABLE_COLOR` |
| `scripts/ui/card_block.gd`（改） | 拾取 Area3D + `set_pick`/`pick_meta`；`set_actionable`；`reveal`/`restore`/`flash`；颜色优先级 |
| `scripts/ui/table3d_camera.gd`（改） | `camera_node() -> Camera3D` |
| `scripts/ui/table3d_picker.gd`（新） | 纯函数：屏幕中心射线拾取 → metadata |
| `scripts/ui/table3d_hud.gd`（新） | 3D 按钮组（可点扁方块 + `Label3D`） |
| `scripts/ui/crosshair.gd`（新） | 屏幕中心准星（2D `Control`，`_draw`） |
| `scripts/ui/table3d_view.gd`（改） | 登记 `_card_blocks`；中央/HUD 拾取标记；`pick_center`；`reveal_slot`/`flash_slot`；`render(state, actionable)`；`set_hud_buttons` |
| `scripts/ui/main.gd`（改） | 准星；点击分发；HUD 动作；揭示接管；指针与模态同步；`_input` 左键/模态分支 |
| `tests/verify_table3d_interaction.gd` + `.tscn`（新） | 拾取/高亮/揭示/HUD 断言 |
| `tools/run_all_tests.sh`（改） | 注册新测试 |

---

### Task 1: CardBlock 拾取标记 + 高亮 + 瞬时揭示

**Files:**
- Modify: `scripts/ui/table3d_layout.gd`
- Modify: `scripts/ui/card_block.gd`
- Create: `tests/verify_table3d_interaction.gd`
- Create: `tests/verify_table3d_interaction.tscn`

**Interfaces:**
- Consumes: `Table3dLayout.BLOCK_SIZE`、`slot_color()`、`known_color_for_rank()`、`UNKNOWN_COLOR`
- Produces:
  - `Table3dLayout.PICK_LAYER: int`、`PICK_MASK: int`、`ACTIONABLE_COLOR: Color`
  - `CardBlock.set_pick(meta: Dictionary) -> void`、`CardBlock.pick_meta() -> Dictionary`
  - `CardBlock.set_actionable(on: bool) -> void`
  - `CardBlock.reveal(card: Dictionary, color := Color(0,0,0,0)) -> void`、`CardBlock.restore() -> void`
  - `CardBlock.flash(color: Color, dur: float) -> void`
  - 既有 `setup/label_text/block_color/is_emissive/card_text` 保持

- [ ] **Step 1: 写失败测试**

Create `tests/verify_table3d_interaction.gd`:

```gdscript
extends Node
## headless 单元测试：3D 对局交互（拾取标记 / 高亮 / 揭示 / 相机 / HUD / 视图）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TABLE3D INTERACTION RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_layout_pick()
	await _test_card_block()
	_test_camera_accessor()
	await _test_picker()
	_test_hud()
	await _test_view()

func _test_layout_pick() -> void:
	_check("PICK_LAYER == 2", Table3dLayout.PICK_LAYER == 2)
	_check("PICK_MASK == 2", Table3dLayout.PICK_MASK == 2)

func _test_card_block() -> void:
	var block := CardBlock.new()
	add_child(block)
	block.setup({"card": {"rank": "A", "suit": "♥"}})
	block.set_pick({"kind": "slot", "seat": 1, "slot": 2})
	_check("set_pick/pick_meta 往返", block.pick_meta().get("kind", "") == "slot" and int(block.pick_meta().get("seat", -1)) == 1 and int(block.pick_meta().get("slot", -1)) == 2)
	_check("拾取 Area 在 PICK_LAYER", block.get_node("PickArea").collision_layer == Table3dLayout.PICK_MASK)
	# 高亮
	block.set_actionable(true)
	_check("可操作高亮色", block.block_color() == Table3dLayout.ACTIONABLE_COLOR)
	block.set_actionable(false)
	_check("取消高亮回分类色", block.block_color() == Table3dLayout.known_color_for_rank("A"))
	# protected 优先于 actionable
	var prot := CardBlock.new()
	add_child(prot)
	prot.setup({"protected": true, "card": {"rank": "K", "suit": "♠"}})
	prot.set_actionable(true)
	_check("protected 优先于 actionable", prot.block_color() == CardBlock.PROTECTED_COLOR)
	# 揭示 / 恢复
	var hidden := CardBlock.new()
	add_child(hidden)
	hidden.setup({"card_id": "c1"})
	_check("未知牌初始无文本", hidden.label_text() == "")
	hidden.reveal({"rank": "Q", "suit": "♦"}, Color(0.2, 0.9, 0.4))
	_check("reveal 后显示 Q♦", hidden.label_text() == "Q♦")
	_check("reveal 带色", hidden.block_color() == Color(0.2, 0.9, 0.4))
	hidden.restore()
	_check("restore 后回到未知（无文本）", hidden.label_text() == "")
	_check("restore 后回到未知灰", hidden.block_color() == Table3dLayout.UNKNOWN_COLOR)
	# flash 短暂染色后恢复
	hidden.flash(Color(0.2, 0.6, 1.0), 0.05)
	_check("flash 立即染色", hidden.block_color() == Color(0.2, 0.6, 1.0))
	await get_tree().create_timer(0.15).timeout
	_check("flash 结束后恢复", hidden.block_color() == Table3dLayout.UNKNOWN_COLOR)

func _test_camera_accessor() -> void:
	var rig := Table3dCamera.new()
	add_child(rig)
	_check("camera_node 非空且为 Camera3D", rig.camera_node() != null and rig.camera_node() is Camera3D)
```

Create `tests/verify_table3d_interaction.tscn`:

```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/verify_table3d_interaction.gd" id="1"]
[node name="VerifyTable3dInteraction" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: 报 `Table3dLayout.PICK_LAYER` 不存在 / `CardBlock.set_pick` 不存在 等错误。

- [ ] **Step 3: 写实现**

Modify `scripts/ui/table3d_layout.gd`，在 `UNKNOWN_COLOR` 附近新增：

```gdscript
const PICK_LAYER := 2
const PICK_MASK := 1 << (PICK_LAYER - 1)  # 2
const ACTIONABLE_COLOR := Color(0.95, 0.82, 0.35)  # 可操作高亮（金）
```

Modify `scripts/ui/card_block.gd` 为完整内容：

```gdscript
class_name CardBlock
extends Node3D
## 3D 卡牌方块视图（Milestone 1 只读预览 + Milestone 2 拾取/高亮/瞬时揭示）
## 职责：方块 + Label3D 展示 slot；提供拾取标记、可操作高亮、瞬时揭示。
## 纯展示层：不做规则/隐私判断（已知/未知由快照 slot 是否含 "card" 决定）。

const PROTECTED_COLOR := Color(0.62, 0.35, 0.85)

var _built := false
var _mesh: MeshInstance3D
var _label: Label3D
var _material: StandardMaterial3D
var _area: Area3D
var _last_slot: Dictionary = {}
var _actionable := false

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
	# 拾取标记：独立物理层，仅用于射线拾取
	_area = Area3D.new()
	_area.name = "PickArea"
	var shape := CollisionShape3D.new()
	var pick_box := BoxShape3D.new()
	pick_box.size = Table3dLayout.BLOCK_SIZE
	shape.shape = pick_box
	_area.add_child(shape)
	_area.collision_layer = Table3dLayout.PICK_MASK
	_area.collision_mask = 0
	add_child(_area)

## 设置槽位内容：已知牌显示点数标签；颜色按 protected > actionable > 分类色。
func setup(slot: Dictionary) -> void:
	_build()
	_last_slot = slot
	var card: Dictionary = slot.get("card", {})
	_label.text = "" if card.is_empty() else card_text(card)
	_apply_color()

## 设置拾取元数据（{"kind":"slot","seat":..,"slot":..} 或 hud/deck/...）。
func set_pick(meta: Dictionary) -> void:
	_build()
	_area.set_meta("pick", meta)

func pick_meta() -> Dictionary:
	if _area == null:
		return {}
	return _area.get_meta("pick", {})

## 可操作高亮（金色）。
func set_actionable(on: bool) -> void:
	_build()
	_actionable = on
	_apply_color()

## 瞬时揭示：临时显示 card 正面；color.a>0 时同时染色。用 restore() 回到最近 setup(slot)。
func reveal(card: Dictionary, color := Color(0, 0, 0, 0)) -> void:
	_build()
	_label.text = card_text(card)
	if color.a > 0.0:
		_material.albedo_color = color
		_material.emission_enabled = false

## 回到最近一次 setup(slot) 的状态（标签 + 颜色）。
func restore() -> void:
	_build()
	setup(_last_slot)

## 短暂染色（不改标签），dur 秒后恢复。
func flash(color: Color, dur: float) -> void:
	_build()
	_material.albedo_color = color
	_material.emission_enabled = false
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(self):
			_apply_color())

func _apply_color() -> void:
	var is_protected := bool(_last_slot.get("protected", false))
	if is_protected:
		_material.albedo_color = PROTECTED_COLOR
		_material.emission_enabled = true
		_material.emission = PROTECTED_COLOR
		_material.emission_energy_multiplier = 1.5
	elif _actionable:
		_material.albedo_color = Table3dLayout.ACTIONABLE_COLOR
		_material.emission_enabled = true
		_material.emission = Table3dLayout.ACTIONABLE_COLOR
		_material.emission_energy_multiplier = 0.6
	else:
		_material.albedo_color = Table3dLayout.slot_color(_last_slot)
		_material.emission_enabled = false

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

> 注意：既有 `verify_table3d.gd` 对 `CardBlock` 的断言（未知灰 / 护盾紫 / 非护盾不自发光 / 文本）必须继续通过。

- [ ] **Step 4: 跑测试确认通过**

Run: `... --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: `=== TABLE3D INTERACTION RESULT: 15/15 passed ===`（Task 1 部分）。
Run: `... --headless --path . res://tests/verify_table3d.tscn`
Expected: 仍 `34/34`（`CardBlock` 既有断言未回归）。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/table3d_layout.gd scripts/ui/card_block.gd \
  tests/verify_table3d_interaction.gd tests/verify_table3d_interaction.gd.uid tests/verify_table3d_interaction.tscn
git commit -m "feat: CardBlock 拾取标记 + 可操作高亮 + 瞬时揭示"
```

---

### Task 2: Table3dPicker 纯拾取 + 相机访问器

**Files:**
- Modify: `scripts/ui/table3d_camera.gd`（新增 `camera_node()`）
- Create: `scripts/ui/table3d_picker.gd`
- Modify: `tests/verify_table3d_interaction.gd`（`_run` 调 `_test_picker`；新增 `_test_picker`）

**Interfaces:**
- Consumes: `Table3dLayout.PICK_MASK`、`CardBlock.set_pick`
- Produces: `Table3dCamera.camera_node() -> Camera3D`；`Table3dPicker.pick(cam: Camera3D, world: World3D, screen_center: Vector2) -> Dictionary`

- [ ] **Step 1: 写失败测试**

Modify `tests/verify_table3d_interaction.gd` 的 `_run()`，在 `_test_camera_accessor()` 后加 `await _test_picker()`，并新增：

```gdscript
func _test_picker() -> void:
	var root := Node3D.new()
	add_child(root)
	var block := CardBlock.new()
	root.add_child(block)
	block.setup({"card_id": "c9"})
	block.set_pick({"kind": "slot", "seat": 2, "slot": 1})
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0.0, 0.0, 2.0)
	cam.look_at(Vector3.ZERO)
	await get_tree().physics_frame
	var center := get_viewport().get_visible_rect().size * 0.5
	var hit := Table3dPicker.pick(cam, root.get_world_3d(), center)
	_check("拾取命中槽位", str(hit.get("kind", "")) == "slot" and int(hit.get("seat", -1)) == 2 and int(hit.get("slot", -1)) == 1)
	cam.position = Vector3(0.0, 5.0, 5.0)
	cam.look_at(Vector3(0.0, 3.0, 0.0))
	await get_tree().physics_frame
	var miss := Table3dPicker.pick(cam, root.get_world_3d(), center)
	_check("准星指空处未命中", miss.is_empty())
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: `Table3dPicker` 未定义 / 编译错误。

- [ ] **Step 3: 写实现**

Modify `scripts/ui/table3d_camera.gd`，在 `_build()` 之后新增：

```gdscript
## 相机节点访问器（供射线拾取用）。
func camera_node() -> Camera3D:
	_build()
	return _camera
```

Create `scripts/ui/table3d_picker.gd`:

```gdscript
class_name Table3dPicker
extends RefCounted
## 屏幕中心射线拾取（Milestone 2，纯工具）。
## 用相机屏幕中心发射线，命中带 "pick" metadata 的 Area3D → 返回该 metadata。

const RAY_LENGTH := 100.0

static func pick(cam: Camera3D, world: World3D, screen_center: Vector2) -> Dictionary:
	if cam == null or world == null:
		return {}
	var from := cam.project_ray_origin(screen_center)
	var to := from + cam.project_ray_normal(screen_center) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = Table3dLayout.PICK_MASK
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Object = hit.get("collider")
	if collider == null or not collider.has_meta("pick"):
		return {}
	return collider.get_meta("pick")
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: `=== TABLE3D INTERACTION RESULT: 17/17 passed ===`。
（若命中不稳定，确认在 `pick` 前已 `await get_tree().physics_frame`。）

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/table3d_camera.gd scripts/ui/table3d_picker.gd scripts/ui/table3d_picker.gd.uid tests/verify_table3d_interaction.gd
git commit -m "feat: 屏幕中心射线拾取 Table3dPicker + 相机访问器"
```

---

### Task 3: Table3dHud 3D 按钮组

**Files:**
- Create: `scripts/ui/table3d_hud.gd`
- Modify: `tests/verify_table3d_interaction.gd`（`_run` 调 `_test_hud`；新增 `_test_hud`）

**Interfaces:**
- Consumes: `Table3dLayout.PICK_MASK`
- Produces:
  - `Table3dHud.BUTTON_SIZE: Vector3`、`Table3dHud.ENABLED_COLOR: Color`、`Table3dHud.DISABLED_COLOR: Color`
  - `Table3dHud.set_buttons(buttons: Array) -> void`（`[{text, action, enabled}]`）
  - `Table3dHud.button_count() -> int`、`Table3dHud.button_action(index) -> String`、`Table3dHud.button_color(index) -> Color`

- [ ] **Step 1: 写失败测试**

Modify `tests/verify_table3d_interaction.gd` 的 `_run()`，加 `_test_hud()`（无 await），并新增：

```gdscript
func _test_hud() -> void:
	var hud := Table3dHud.new()
	add_child(hud)
	hud.set_buttons([
		{"text": "Ready（1/2）", "action": "ready", "enabled": true},
		{"text": "🔔 KONGBAYA", "action": "kongbaya", "enabled": false},
	])
	_check("HUD 按钮数", hud.button_count() == 2)
	_check("HUD action 0", hud.button_action(0) == "ready")
	_check("HUD action 1", hud.button_action(1) == "kongbaya")
	_check("HUD 禁用按钮颜色", hud.button_color(1) == Table3dHud.DISABLED_COLOR)
	_check("HUD 启用按钮颜色", hud.button_color(0) == Table3dHud.ENABLED_COLOR)
	var area: Area3D = hud.get_child(0).get_node("PickArea")
	_check("HUD 按钮可拾取", area.get_meta("pick", {}).get("action", "") == "ready")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: `Table3dHud` 未定义。

- [ ] **Step 3: 写实现**

Create `scripts/ui/table3d_hud.gd`:

```gdscript
class_name Table3dHud
extends Node3D
## 3D 操作面板（Milestone 2）：准星可点的一组扁方块按钮 + Label3D。
## 纯展示 + 拾取标记；动作由 main 处理。

const BUTTON_SIZE := Vector3(1.15, 0.34, 0.05)
const BUTTON_GAP := 0.16
const ENABLED_COLOR := Color(0.30, 0.55, 0.85)
const DISABLED_COLOR := Color(0.22, 0.22, 0.26)

var _buttons: Array = []

## buttons: [{text: String, action: String, enabled: bool}]
func set_buttons(buttons: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons = buttons.duplicate(true)
	var count := _buttons.size()
	for i in count:
		var spec: Dictionary = _buttons[i]
		var holder := Node3D.new()
		holder.name = "HudBtn%d" % i
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		var box := BoxMesh.new()
		box.size = BUTTON_SIZE
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = ENABLED_COLOR if bool(spec.get("enabled", true)) else DISABLED_COLOR
		mesh.material_override = mat
		holder.add_child(mesh)
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.004
		label.font_size = 64
		label.text = str(spec.get("text", ""))
		label.position = Vector3(0.0, 0.0, BUTTON_SIZE.z * 0.5 + 0.02)
		holder.add_child(label)
		var area := Area3D.new()
		area.name = "PickArea"
		var shape := CollisionShape3D.new()
		var pick_box := BoxShape3D.new()
		pick_box.size = BUTTON_SIZE
		shape.shape = pick_box
		area.add_child(shape)
		area.collision_layer = Table3dLayout.PICK_MASK
		area.collision_mask = 0
		area.set_meta("pick", {"kind": "hud", "action": str(spec.get("action", ""))})
		holder.add_child(area)
		holder.position = Vector3(
			(float(i) - (float(count) - 1.0) / 2.0) * (BUTTON_SIZE.x + BUTTON_GAP), 0.0, 0.0)
		add_child(holder)

func button_count() -> int:
	return _buttons.size()

func button_action(index: int) -> String:
	return str(_buttons[index].get("action", ""))

func button_color(index: int) -> Color:
	var mesh: MeshInstance3D = get_child(index).get_node("Mesh")
	return (mesh.material_override as StandardMaterial3D).albedo_color
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: `=== TABLE3D INTERACTION RESULT: 23/23 passed ===`。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/table3d_hud.gd scripts/ui/table3d_hud.gd.uid tests/verify_table3d_interaction.gd
git commit -m "feat: 3D 操作面板 Table3dHud（准星可点按钮组）"
```

---

### Task 4: Table3dView 集成（拾取登记 / pick_center / 揭示 / HUD）

**Files:**
- Modify: `scripts/ui/table3d_view.gd`
- Modify: `tests/verify_table3d_interaction.gd`（`_run` 调 `_test_view`；新增 `_test_view`）

**Interfaces:**
- Consumes: `CardBlock.set_pick/set_actionable/reveal/restore/flash`、`Table3dPicker.pick`、`Table3dHud`、`Table3dCamera.camera_node`
- Produces:
  - `Table3dView._card_blocks: Dictionary`（`{seat: {slot: CardBlock}}`）
  - `Table3dView.pick_center() -> Dictionary`
  - `Table3dView.reveal_slot(seat, slot, card, color, dur) -> void`
  - `Table3dView.flash_slot(seat, slot, color, dur) -> void`
  - `Table3dView.set_hud_buttons(buttons: Array) -> void`
  - `Table3dView.render(state: Dictionary, actionable := Callable()) -> void`

- [ ] **Step 1: 写失败测试**

Modify `tests/verify_table3d_interaction.gd` 的 `_run()`，加 `await _test_view()`，并新增：

```gdscript
func _test_view() -> void:
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	view.render({
		"viewer_id": 0,
		"players": [
			{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2,
			 "slots": [{"card_id": "c1"}, {"card_id": "c2"}, {"card_id": "c3"}, {"card_id": "c4"}]},
			{"id": 1, "name": "乙", "count": 4, "currency": 0, "health": 2,
			 "slots": [{"card_id": "c9"}, {"card_id": "c10"}, {"card_id": "c11"}, {"card_id": "c12"}]},
		],
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 2,
	})
	await get_tree().physics_frame
	_check("_card_blocks 登记", view._card_blocks.has(0) and view._card_blocks[0].has(0))
	# 把相机对准 seat0/slot0 方块 → pick_center 命中 slot
	var block = view._card_blocks[0][0]
	view.camera.get_node("PitchPivot").rotation_degrees = Vector3.ZERO
	view.camera.rotation_degrees = Vector3.ZERO
	view.camera.global_position = block.global_position + Vector3(0.0, 0.0, 1.2)
	await get_tree().physics_frame
	var pick: Dictionary = view.pick_center()
	_check("pick_center 命中槽位", str(pick.get("kind", "")) == "slot" and int(pick.get("seat", -1)) == 0 and int(pick.get("slot", -1)) == 0)
	# 高亮
	view.render({
		"viewer_id": 0,
		"players": [
			{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2,
			 "slots": [{"card_id": "c1"}, {"card_id": "c2"}, {"card_id": "c3"}, {"card_id": "c4"}]},
			{"id": 1, "name": "乙", "count": 4, "currency": 0, "health": 2,
			 "slots": [{"card_id": "c9"}, {"card_id": "c10"}, {"card_id": "c11"}, {"card_id": "c12"}]},
		],
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 2,
	}, func(seat: int, slot: int) -> bool: return seat == 0 and slot == 0)
	await get_tree().process_frame
	_check("render(actionable) 高亮", view._card_blocks[0][0].block_color() == Table3dLayout.ACTIONABLE_COLOR)
	_check("非可操作不高亮", view._card_blocks[0][1].block_color() == Table3dLayout.UNKNOWN_COLOR)
	# 揭示 / 恢复
	view.reveal_slot(0, 0, {"rank": "A", "suit": "♥"}, Color(0.2, 0.9, 0.4), 0.05)
	_check("reveal_slot 显示 A♥", view._card_blocks[0][0].label_text() == "A♥")
	await get_tree().create_timer(0.15).timeout
	_check("reveal_slot 后恢复无文本", view._card_blocks[0][0].label_text() == "")
	# HUD 可拾取
	view.set_hud_buttons([{"text": "Ready", "action": "ready", "enabled": true}])
	await get_tree().process_frame
	var hud_btn = view._hud.get_child(0)
	view.camera.get_node("PitchPivot").rotation_degrees = Vector3.ZERO
	view.camera.rotation_degrees = Vector3.ZERO
	view.camera.global_position = hud_btn.global_position + Vector3(0.0, 0.0, 1.0)
	await get_tree().physics_frame
	var hud_pick: Dictionary = view.pick_center()
	_check("pick_center 命中 HUD", str(hud_pick.get("kind", "")) == "hud" and str(hud_pick.get("action", "")) == "ready")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: `view._card_blocks` / `pick_center` / `_hud` 不存在 → 失败。

- [ ] **Step 3: 写实现**

Modify `scripts/ui/table3d_view.gd`：

1. `const HUD_OFFSET := 0.55`、`const HUD_HEIGHT := 0.5` 常量；新增成员 `var _hud = null`、`var _card_blocks := {}`、`var _hud_offset := Vector3.ZERO`。
2. 在 `_build()` 末尾（Center 之后）加：

```gdscript
	# 3D 操作面板（准星可点）
	_hud = load("res://scripts/ui/table3d_hud.gd").new()
	_hud.name = "Hud"
	add_child(_hud)
	# 抽牌堆拾取标记
	var deck_area := Area3D.new()
	deck_area.name = "DeckPick"
	var deck_shape := CollisionShape3D.new()
	var deck_pick := BoxShape3D.new()
	deck_pick.size = Vector3(0.7, 0.25, 1.0)
	deck_shape.shape = deck_pick
	deck_area.add_child(deck_shape)
	deck_area.collision_layer = Table3dLayout.PICK_MASK
	deck_area.collision_mask = 0
	deck_area.set_meta("pick", {"kind": "deck"})
	deck_area.position = CENTER_DECK
	center.add_child(deck_area)
```

（`center` 变量在 `_build()` 内已有；`_discard_block`/`_pending_block` 在 `render` 里设 pick。）

3. `render` 签名改为 `func render(state: Dictionary, actionable := Callable()) -> void:`；在 `for i in SEAT_COUNT: _seat_nodes[i].visible = false` 之前加 `_card_blocks.clear()`；座位循环里传 actionable：

```gdscript
		_render_seat(node, p)
		if actionable.is_valid():
			for slot_index in (p.get("slots", []) as Array).size():
				if _card_blocks.has(seat) and _card_blocks[seat].has(slot_index):
					_card_blocks[seat][slot_index].set_actionable(bool(actionable.call(seat, slot_index)))
```

4. 中央部分补 pick 标记与 HUD 定位：

```gdscript
	var discard: Dictionary = state.get("discard", {})
	_discard_block.setup({"card": discard} if not discard.is_empty() else {})
	_discard_block.set_pick({"kind": "discard"})
	var pending: Dictionary = state.get("pending", {})
	_pending_block.visible = not pending.is_empty()
	_pending_block.set_pick({"kind": "pending"})
	if not pending.is_empty():
		_pending_block.setup({"card": pending} if pending.has("rank") else {})
	# HUD 放在 viewer 座位内侧、朝向 viewer
	var v_angle := float(seat_angle.get(viewer, 0.0))
	var v_dir := Vector3(sin(deg_to_rad(v_angle)), 0.0, cos(deg_to_rad(v_angle)))
	_hud.position = v_dir * (Table3dLayout.SEAT_RADIUS - HUD_OFFSET) + Vector3(0.0, HUD_HEIGHT, 0.0)
	_hud.rotation_degrees = Vector3(0.0, v_angle + 180.0, 0.0)
```

5. `_render_seat` 里登记与标记：

```gdscript
		var block = CardBlockScript.new()
		...
		hand.add_child(block)
		block.setup(slots[i])
		block.set_pick({"kind": "slot", "seat": int(p.id), "slot": i})
		if not _card_blocks.has(int(p.id)):
			_card_blocks[int(p.id)] = {}
		_card_blocks[int(p.id)][i] = block
```

6. 新增方法（文件末尾）：

```gdscript
## 屏幕中心射线拾取（准星）。
func pick_center() -> Dictionary:
	if camera == null:
		return {}
	var center := get_viewport().get_visible_rect().size * 0.5
	return Table3dPicker.pick(camera.camera_node(), get_world_3d(), center)

## 瞬时揭示某槽位（dur 秒后恢复）。槽位不存在则忽略。
func reveal_slot(seat_id: int, slot: int, card: Dictionary, color := Color(0, 0, 0, 0), dur := 1.5) -> void:
	var block = _find_block(seat_id, slot)
	if block == null:
		return
	block.reveal(card, color)
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(block):
			block.restore())

## 短暂染色提醒（不翻面）。
func flash_slot(seat_id: int, slot: int, color: Color, dur: float) -> void:
	var block = _find_block(seat_id, slot)
	if block != null:
		block.flash(color, dur)

## 设置 3D 操作面板按钮（[{text, action, enabled}]）。
func set_hud_buttons(buttons: Array) -> void:
	_build()
	_hud.set_buttons(buttons)

func _find_block(seat_id: int, slot: int):
	if not _card_blocks.has(seat_id) or not _card_blocks[seat_id].has(slot):
		return null
	var block = _card_blocks[seat_id][slot]
	return block if is_instance_valid(block) else null
```

- [ ] **Step 4: 跑测试确认通过**

Run:
```bash
... --headless --path . res://tests/verify_table3d_interaction.tscn   # 30/30
... --headless --path . res://tests/verify_table3d.tscn               # 仍 34/34
```

- [ ] **Step 5: 注册全量回归**

Modify `tools/run_all_tests.sh`，在 `run_single "table3d_mouse" ...` 之后加：

```bash
run_single "table3d_interaction" res://tests/verify_table3d_interaction.tscn
```

- [ ] **Step 6: 提交**

```bash
git add scripts/ui/table3d_view.gd tests/verify_table3d_interaction.gd tools/run_all_tests.sh
git commit -m "feat: Table3dView 拾取登记/准星拾取/瞬时揭示/HUD 定位"
```

---

### Task 5: main.gd 接线（准星 / 点击分发 / HUD 动作 / 揭示接管 / 指针同步）

**Files:**
- Create: `scripts/ui/crosshair.gd`
- Modify: `scripts/ui/main.gd`
- Modify: `docs/AI_AGENT_交接说明.md`

**Interfaces:**
- Consumes: `Table3dView.pick_center/set_hud_buttons/reveal_slot/flash_slot`、`GameInteraction.on_card_pressed/card_actionable`、`GameState.request_*`
- Produces: `main._table3d_click()`、`main._on_table3d_hud(action)`、`main._table3d_modal_open()`、`main._sync_table3d_pointer()`

- [ ] **Step 1: 新建准星**

Create `scripts/ui/crosshair.gd`:

```gdscript
class_name Crosshair
extends Control
## 屏幕中心准星（仅 3D 预览时显示）。

func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var col := Color(1, 1, 1, 0.9)
	draw_line(Vector2(-11, 0), Vector2(-3, 0), col, 2.0)
	draw_line(Vector2(3, 0), Vector2(11, 0), col, 2.0)
	draw_line(Vector2(0, -11), Vector2(0, -3), col, 2.0)
	draw_line(Vector2(0, 3), Vector2(0, 11), col, 2.0)
	draw_circle(Vector2.ZERO, 1.5, col)
```

- [ ] **Step 2: main.gd 成员与切换**

在 `var _table3d_active := false` 之后加：

```gdscript
var _crosshair: Control = null
```

在 `_set_table3d(on)` 的 `if on:` 分支里，`table3d.set_active(true)` 之后插入：

```gdscript
		if _crosshair == null or not is_instance_valid(_crosshair):
			_crosshair = Crosshair.new()
			_crosshair.name = "Crosshair"
			_crosshair.z_index = 80
			add_child(_crosshair)
		table3d.set_hud_buttons(_table3d_hud_buttons())
		table3d.render(latest_state, interaction.card_actionable)
		_sync_table3d_pointer()
```

删除同分支里原有的 `Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)` 与 `table3d.render(latest_state)`（已由上面替换）。

在 `else:`（退出）分支里，`table3d.set_active(false)` 之后加：

```gdscript
		if _crosshair != null and is_instance_valid(_crosshair):
			_crosshair.visible = false
```

- [ ] **Step 3: 新增分发与同步方法**

在 `_toggle_table3d()` 之后插入：

```gdscript
## 准星点击分发：只调用既有入口，不改规则。
func _table3d_click() -> void:
	if table3d == null or not is_instance_valid(table3d):
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
			_on_table3d_hud(str(pick.get("action", "")))

## 3D 操作面板动作（与 2D 控制按钮行为一致）。
func _on_table3d_hud(action: String) -> void:
	match action:
		"ready":
			game_view._ready_clicked = true
			GameState.request_initial_ready()
		"kongbaya":
			_request_kongbaya()
		"q_keep":
			GameState.request_q_decision(false, -1, _next_action_id())
		"q_exchange":
			GameState.request_q_decision(true, -1, _next_action_id())
		"joker":
			_open_joker_transform_panel()

## 3D 面板内容（复用与 2D 相同的阶段判定）。
func _table3d_hud_buttons() -> Array:
	var out: Array = []
	var phase := int(latest_state.get("phase", PHASE_LOBBY))
	var viewer := int(latest_state.get("viewer_id", 0))
	var is_current := viewer == int(latest_state.get("current_player", -1))
	if phase == PHASE_INITIAL_PEEK:
		var ready_count := int(latest_state.get("ready_count", 0))
		var total: int = (latest_state.get("players", []) as Array).size()
		out.append({"text": "Ready（%d/%d）" % [ready_count, total], "action": "ready",
			"enabled": not game_view._ready_clicked})
	elif phase == PHASE_TURN_DRAW and is_current:
		out.append({"text": "🔔 KONGBAYA", "action": "kongbaya", "enabled": true})
	elif phase == PHASE_Q_DECISION and is_current:
		var qd: Dictionary = latest_state.get("q_decision", {})
		if bool(qd.get("own_viewed", false)):
			out.append({"text": "Q：不交换", "action": "q_keep", "enabled": true})
			out.append({"text": "Q：交换", "action": "q_exchange", "enabled": true})
	elif phase == PHASE_TURN_DECISION and is_current:
		var pending: Dictionary = latest_state.get("pending", {})
		if str(pending.get("rank", "")) == "JOKER":
			var run: Dictionary = latest_state.get("run", {})
			if (run.get("relics", {}) as Dictionary).has(Relics.JOKER_TRANSFORM_ID):
				out.append({"text": "变换 Joker", "action": "joker", "enabled": true})
	return out

## 是否有 2D 模态打开（打开时释放鼠标，让模态可点）。
func _table3d_modal_open() -> bool:
	for panel in [settlement_page, shop_panel, joker_panel, _duel_panel, _reconnect_panel]:
		if panel != null and is_instance_valid(panel) and (panel as CanvasItem).visible:
			return true
	return false

## 3D 激活时同步鼠标模式与准星：模态打开 → 可见（交还 2D）；否则捕获（准星环视）。
func _sync_table3d_pointer() -> void:
	if not _table3d_active:
		return
	var modal := _table3d_modal_open()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if modal else Input.MOUSE_MODE_CAPTURED)
	if _crosshair != null and is_instance_valid(_crosshair):
		_crosshair.visible = not modal
```

- [ ] **Step 4: `_input` 增加模态/左键分支**

把 `_input(event)` 里 `if not _table3d_active:` 之后、F10/ESC 判断之前插入：

```gdscript
	if _table3d_modal_open():
		return   # 交给 2D 模态
```

并在鼠标移动分支之后追加：

```gdscript
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_table3d_click()
		get_viewport().set_input_as_handled()
```

- [ ] **Step 5: 状态更新时刷新 HUD/指针/揭示接管**

Modify `_on_state_updated`：把已有的 3D 渲染行替换为

```gdscript
	if _table3d_active and table3d != null and is_instance_valid(table3d):
		table3d.render(state, interaction.card_actionable)
		table3d.set_hud_buttons(_table3d_hud_buttons())
```

并在该函数**末尾**（`_show_shop_result_toast(state)` 之后）加：

```gdscript
	_sync_table3d_pointer()
```

Modify `_show_private_reveal(title, revealed_cards, target := {})`：

```gdscript
func _show_private_reveal(title: String, revealed_cards: Array, target: Dictionary = {}) -> void:
	if _table3d_active and target.has("slot") and table3d != null and is_instance_valid(table3d):
		var seat := int(target.get("player_id", 0))
		var slot := int(target.get("slot", -1))
		var color := Color(0, 0, 0, 0)
		if target.has("correct"):
			color = SLAP_CORRECT_GLOW if bool(target.get("correct", false)) else SLAP_WRONG_GLOW
		else:
			color = PEEK_GLOW_COLOR
		for card in revealed_cards:
			table3d.reveal_slot(seat, slot, card, color, PEEK_GLOW_DURATION)
		return
	reveal.show_private_reveal(title, revealed_cards, target)
```

Modify `_on_peek_highlight(data)` 开头：

```gdscript
	if _table3d_active and table3d != null and is_instance_valid(table3d):
		table3d.flash_slot(int(data.get("player_id", 0)), int(data.get("slot", -1)), PEEK_GLOW_COLOR, PEEK_GLOW_DURATION)
		return
```

- [ ] **Step 6: 编译 + 全量回归**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
tools/run_all_tests.sh --quick
```
Expected: 编译无 `SCRIPT ERROR`/`Parse Error`；全量 PASS（含 `table3d_interaction`），0 败。

- [ ] **Step 7: 更新交接说明**

Modify `docs/AI_AGENT_交接说明.md`，在 Milestone 1 条目之后加一行：

```markdown
- **3D 桌面对局（Milestone 2，分支 `feature/3d-table`）**：3D 预览内用**屏幕中心准星**点击（`Area3D` 拾取层 2 + `Table3dPicker` 射线）→ 分发到既有 `GameInteraction.on_card_pressed` / `request_take` / `_on_pending_action`；3D 操作面板（`Table3dHud`：Ready / Kongbaya / Q 决策 / 变换 Joker）；可操作高亮（`ACTIONABLE_COLOR`）与瞬时揭示/闪色（无动画，`reveal_slot`/`flash_slot`）。2D 模态（结算/商店/Joker/比拼/重连）打开时自动释放鼠标、关闭后恢复准星环视。规则/协议/快照零改动。测试 `verify_table3d_interaction`（30/30）。不做动画与 3D 菜单/贴图卡面。
```

- [ ] **Step 8: 提交**

```bash
git add scripts/ui/crosshair.gd scripts/ui/crosshair.gd.uid scripts/ui/main.gd docs/AI_AGENT_交接说明.md
git commit -m "feat: 3D 准星点击接线（分发/HUD/揭示接管/指针同步）"
```

---

## 人工验收（不纳入自动化）

- `F10` 进 3D：准星可见，鼠标移动环视。
- 开局记忆：准星点 `Ready` → 可进入抽牌；自己 2/3 号牌显示点数。
- 抽牌：准星点抽牌堆 → 抽到；点弃牌堆 → 取弃牌顶。
- 处理抽到的牌：准星点自己手牌替换；点 pending 大牌使用能力/弃牌。
- 技能：9/10 点他人牌查看（瞬时显示点数）；J 点他人牌再点自己牌交换；Q 用面板按钮；有 Joker 遗物时用 `变换 Joker`。
- 贴牌：`slap_open` 时点他人牌，正确绿/错误红瞬时提示。
- 结算/商店出现时：鼠标变为可见可点，关闭后自动恢复准星环视。

## Self-Review 结论

- **Spec 覆盖**：§2 拾取 → Task 1/2/4；§3 分发 → Task 5；§4 HUD → Task 3/5；§5 高亮+揭示 → Task 1/4/5；§6 指针与模态 → Task 5；§7 文件 → 各任务；§8 测试 → Task 1–4；§9 风险（射线最近命中 / 揭示竞态 / `_ready_clicked`）→ Task 4/5。
- **占位符**：无 TBD/TODO；代码步骤均给完整代码。
- **类型一致性**：`Table3dLayout.PICK_LAYER/PICK_MASK/ACTIONABLE_COLOR`、`CardBlock.set_pick/pick_meta/set_actionable/reveal/restore/flash`、`Table3dPicker.pick`、`Table3dHud.set_buttons/button_count/button_action/button_color`、`Table3dView._card_blocks/pick_center/reveal_slot/flash_slot/set_hud_buttons/render(state, actionable)`、`main._table3d_click/_on_table3d_hud/_table3d_modal_open/_sync_table3d_pointer` 跨任务命名一致；测试计数逐任务累加（15 → 17 → 23 → 30）。
