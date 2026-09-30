# CardBlock 真实 3D 揭示翻面（双面几何）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 CardBlock 揭示从 `scale.x` 压扁翻转换成沙盒同款 3D 翻转（抬起 + 朝玩家倾斜 + 绕长轴 0→180°），并用双面几何让翻出的牌面正确不镜像。

**Architecture:** 两片 plane（正面/背面，均"正面朝上"，背面片预旋 180° 绕 Z）；新增 `_flip` pivot 承载揭示旋转/抬起/倾斜（hover 仍用 `_visual`）；用标量 `_reveal_p` 每帧套 `sin` 包络驱动。

**Tech Stack:** Godot 4.6 GDScript、`Node3D`/`Basis`/`PlaneMesh`/`Tween`、headless 测试。

**Spec:** `docs/superpowers/specs/2026-09-25-cardblock-3d-reveal-flip-design.md`

## Global Constraints

- 分支 `feature/card-animation`。提交 `feat:`/`test:`/`doc:`。
- **不改**：`scripts/core/*`、`scripts/net/*`、`main.gd`、`table3d_view.gd`、`table3d.tscn`、`card_view.gd`、`card_animation*.gd`、`verify_card_animation.gd`、`verify_table3d.gd`（仅回归）。
- 揭示总时长沿用 `CardBlock.FLIP_DURATION`（0.25s）——测试按它等待，不改。
- `_flip` 只写 pos/rot（不写 scale）；hover 仍写 `_visual`。
- 验证：`--headless --path . res://tests/verify_table3d_interaction.tscn` 等；`tools/run_all_tests.sh --quick`。

---

## File Structure

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/card_block.gd`（改） | 双面几何 + `_flip` pivot；`reveal/restore` 改 3D 翻转；访问器 |
| `tests/verify_table3d_interaction.gd`（改） | 结构 / 翻转 / 末态 / restore 断言 |
| `docs/AI_AGENT_交接说明.md`（改） | 记一笔 |

---

### Task 1: CardBlock 双面几何 + `_flip` pivot（揭示仍用 scale.x）

**Files:**
- Modify: `scripts/ui/card_block.gd`
- Modify: `tests/verify_table3d_interaction.gd`

**Interfaces:**
- Produces: `CardBlock.back_node() -> MeshInstance3D`、`CardBlock.flip_node() -> Node3D`
- 保持：`reveal/restore` 仍走 `_flip_to`（scale.x），既有测试不变

- [ ] **Step 1: 写失败测试**

在 `_test_card_block()` 已有的视觉 pivot 断言之后追加：

```gdscript
	# 双面几何：背面板 + 揭示 pivot
	_check("有背面板", vb.back_node() != null)
	_check("背面板预旋转 180°(绕卡长轴)", absf(vb.back_node().rotation_degrees.z - 180.0) < 0.01)
	_check("揭示 pivot 在 visual 下", vb.flip_node() != null and vb.flip_node().get_parent() == vb.visual_node())
```

- [ ] **Step 2: 运行确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: 报 `back_node`/`flip_node` 未定义。

- [ ] **Step 3: 实现**

在 `scripts/ui/card_block.gd`：

① 字段区（`var _visual` 之后）加：

```gdscript
var _flip: Node3D
var _back_node: MeshInstance3D
var _back_material: StandardMaterial3D
```

② `_build()`：把 `_visual` 建好后，先建 `_flip` 挂到 `_visual` 下：

```gdscript
	# 揭示 pivot：绕卡长轴旋转 + 抬起 + 朝玩家倾斜（与 hover 的 _visual 分节点）。
	_flip = Node3D.new()
	_flip.name = "Flip"
	_visual.add_child(_flip)
```

③ 把 `_mesh` 与其后的 `_label` 从 `_visual.add_child(...)` 改为 `_flip.add_child(...)`（Glow 循环仍 `_visual.add_child(glow)` 不动）；`_mesh.position = Vector3(0.0, 0.002, 0.0)`。

④ 在 `_mesh` 建好之后、`_label` 之前，建背面板（同样"正面朝上"，预旋 180° 绕 Z）：

```gdscript
	_back_node = MeshInstance3D.new()
	_back_node.name = "Back"
	var bplane := PlaneMesh.new()
	bplane.orientation = PlaneMesh.FACE_Y
	bplane.size = Vector2(Table3dLayout.BLOCK_SIZE.x, Table3dLayout.BLOCK_SIZE.z)
	_back_node.mesh = bplane
	_back_node.position = Vector3(0.0, -0.002, 0.0)
	_back_node.rotation_degrees = Vector3(0.0, 0.0, 180.0)  # 净旋转 360° → 翻面后正向不镜像
	_back_material = StandardMaterial3D.new()
	_back_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_back_material.uv1_scale = Vector3(-1.0, -1.0, 1.0)
	_back_material.uv1_offset = Vector3(1.0, 1.0, 0.0)
	_back_material.albedo_texture = _back_texture()
	_back_material.albedo_color = Color.WHITE
	_back_node.material_override = _back_material
	_flip.add_child(_back_node)
```

⑤ 访问器（放在 `visual_node()` 附近）：

```gdscript
## 背面片（揭示翻面后朝上）。
func back_node() -> MeshInstance3D:
	_build()
	return _back_node

## 揭示翻转 pivot。
func flip_node() -> Node3D:
	_build()
	return _flip
```

- [ ] **Step 4: 运行确认通过 + 回归**

Run:
```bash
... --headless --path . res://tests/verify_table3d_interaction.tscn   # 63/63
... --headless --path . res://tests/verify_table3d.tscn               # 36/36
```
Expected: interaction 60→63（+3）。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/card_block.gd tests/verify_table3d_interaction.gd
git commit -m "feat: CardBlock 双面几何 + 揭示 pivot 骨架 + 测试"
```

---

### Task 2: 揭示改用 3D 翻转（替换 scale.x）

**Files:**
- Modify: `scripts/ui/card_block.gd`
- Modify: `tests/verify_table3d_interaction.gd`

**Interfaces:**
- Produces: `CardBlock.reveal_progress() -> float`
- 保持：`reveal(card, color)`/`restore()` 签名；`has_face_texture/has_back_texture/label_text/block_color/albedo_texture` 语义

- [ ] **Step 1: 写失败测试**

在 `_run()` 追加 `await _test_reveal_flip()`，并追加：

```gdscript
func _test_reveal_flip() -> void:
	var b := CardBlock.new()
	add_child(b)
	b.setup({"card_id": "x"})
	b.reveal({"rank": "Q", "suit": "♦"})
	await get_tree().create_timer(CardBlock.FLIP_DURATION * 0.5).timeout
	_check("揭示中途进度 ~0.5", absf(b.reveal_progress() - 0.5) < 0.2)
	_check("揭示中途 flip 节点已变换", not b.flip_node().transform.is_equal_approx(Transform3D.IDENTITY))
	await get_tree().create_timer(CardBlock.FLIP_DURATION * 0.5 + 0.08).timeout
	_check("揭示结束进度 1", is_equal_approx(b.reveal_progress(), 1.0))
	_check("揭示不用 scale.x", b.scale.is_equal_approx(Vector3.ONE))
	_check("揭示末态显示牌面", b.has_face_texture() and b.label_text() == "Q♦")
	b.restore()
	await get_tree().create_timer(CardBlock.FLIP_DURATION + 0.08).timeout
	_check("restore 后进度 0 且回卡背", is_equal_approx(b.reveal_progress(), 0.0) and b.has_back_texture())
```

- [ ] **Step 2: 运行确认失败**

Run: `... --headless --path . res://tests/verify_table3d_interaction.tscn`
Expected: `reveal_progress` 未定义 / 揭示不用 scale.x 失败。

- [ ] **Step 3: 实现**

在 `scripts/ui/card_block.gd`：

① 字段区加：

```gdscript
var _reveal_p := 0.0
var _front_is_back := true
var _back_is_back := true
```

② 删除旧的 `_flip_to()` 与 `_show_face()`，新增：

```gdscript
## 揭示翻转到 card（写到底面板，几何连续换面）；color.a>0 时用该色边缘发光。
func reveal(card: Dictionary, color := Color(0, 0, 0, 0)) -> void:
	_build()
	_back_material.albedo_texture = _face_texture(card) if not card.is_empty() else _back_texture()
	_back_material.albedo_color = Color.WHITE
	_back_is_back = card.is_empty()
	_label.text = card_text(card)
	if color.a > 0.0:
		_apply_glow_layers(color)
	else:
		_paint_glow()
	_reveal_to(1.0)

## 翻回最近一次 setup(slot) 的状态（贴图/标签/高亮）。
func restore() -> void:
	_build()
	var card: Dictionary = _last_slot.get("card", {})
	_label.text = "" if card.is_empty() else card_text(card)
	_paint_glow()
	_reveal_to(0.0)

func _reveal_to(target: float) -> void:
	_kill_flip()
	if not is_inside_tree():
		_reveal_p = target
		_apply_flip_pose()
		return
	set_process(true)
	_flip_tween = create_tween()
	_flip_tween.tween_property(self, "_reveal_p", target, FLIP_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

## 揭示翻转姿态：绕长轴 0→180° + 抬起 + 朝玩家倾斜（sin 包络，末了回平）。
func _apply_flip_pose() -> void:
	if _flip == null:
		return
	if _reveal_p <= 0.0:
		_flip.transform = Transform3D.IDENTITY
		return
	var cfg := _cfg()
	var arc := sin(_reveal_p * PI)
	var basis := Basis.from_euler(Vector3(-deg_to_rad(cfg.hover_pitch * arc), 0.0, 0.0)) \
			* Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(_reveal_p * 180.0))
	_flip.transform = Transform3D(basis, Vector3(0.0, cfg.flip_lift * arc, 0.0))

func reveal_progress() -> float:
	return _reveal_p
```

③ `_kill_flip()` 保持只 kill tween：

```gdscript
func _kill_flip() -> void:
	if _flip_tween != null and _flip_tween.is_valid():
		_flip_tween.kill()
	_flip_tween = null
```

④ `setup(slot)` 复位揭示：在 `_kill_flip()` 后加 `_reveal_p = 0.0`、`if _flip != null: _flip.transform = Transform3D.IDENTITY`。

⑤ `_process` 改为同时驱动 hover 与揭示，并在都空闲时停：

```gdscript
func _process(_delta: float) -> void:
	_apply_hover_pose()
	_apply_flip_pose()
	var hb := _hover_tween != null and _hover_tween.is_valid()
	var fb := _flip_tween != null and _flip_tween.is_valid()
	if not hb and not fb and _hover_p <= 0.0 and _reveal_p <= 0.0:
		set_process(false)
```

⑥ `_apply_color()` 增加背面板复位与正面标记：

```gdscript
func _apply_color() -> void:
	var card: Dictionary = _last_slot.get("card", {})
	if card.is_empty():
		_showing_back = true
		_front_is_back = true
		_material.albedo_texture = _back_texture()
		_material.albedo_color = Color.WHITE
	else:
		_showing_back = false
		_front_is_back = false
		var face := _face_texture(card)
		_material.albedo_texture = face
		_material.albedo_color = Color.WHITE if face != null else Table3dLayout.slot_color(_last_slot)
	if _back_material != null and _reveal_p <= 0.0:
		_back_material.albedo_texture = _back_texture()
		_back_material.albedo_color = Color.WHITE
		_back_is_back = true
	_paint_glow()
```

⑦ 访问器改用"朝上可见面"：

```gdscript
func _display_material() -> StandardMaterial3D:
	return _material if _reveal_p < 0.5 else _back_material

func _display_is_back() -> bool:
	return _front_is_back if _reveal_p < 0.5 else _back_is_back

func block_color() -> Color:
	var m := _display_material()
	return m.albedo_color if m != null else Color.BLACK

func albedo_texture() -> Texture2D:
	var m := _display_material()
	return m.albedo_texture if m != null else null

func has_back_texture() -> bool:
	var m := _display_material()
	return m != null and m.albedo_texture != null and _display_is_back()

func has_face_texture() -> bool:
	var m := _display_material()
	return m != null and m.albedo_texture != null and not _display_is_back()
```

⑧ `show_back(back)` 保持（写正面 `_material`）：无需改（其内部用 `_material`）。

- [ ] **Step 4: 运行确认通过 + 回归**

Run:
```bash
... --headless --path . res://tests/verify_table3d_interaction.tscn   # 70/70
... --headless --path . res://tests/verify_table3d.tscn               # 36/36
... --headless --path . res://tests/verify_card_animation.tscn        # 68/68
```
Expected: interaction 63→70（+7）。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/card_block.gd tests/verify_table3d_interaction.gd
git commit -m "feat: CardBlock 揭示改用真实 3D 翻转（双面几何，不镜像）+ 测试"
```

---

### Task 3: 全量回归 + 交接文档

**Files:**
- Modify: `docs/AI_AGENT_交接说明.md`

- [ ] **Step 1: 全量（快）回归**

Run: `tools/run_all_tests.sh --quick`（给足超时 600000ms）
Expected: 全部 PASS，含 `table3d_interaction 70/70`、`table3d 36/36`、`card_animation 68/68`。

- [ ] **Step 2: 文档**

在 `docs/AI_AGENT_交接说明.md` §4 UI 层表格的卡片行补充：揭示（看牌/贴牌）改用真实 3D 翻转（双面几何、抬起+倾斜，不镜像）；并在 §8「开发约定」追一句「揭示翻转由 `verify_table3d_interaction` 覆盖」。

- [ ] **Step 3: 提交**

```bash
git add docs/AI_AGENT_交接说明.md
git commit -m "doc: 记录 CardBlock 真实 3D 揭示翻面"
```

---

## Self-Review

**Spec coverage：** §3.1 双面几何 → Task1；§3.2 层级 → Task1；§3.3 翻转 → Task2；§3.4 访问器 → Task2；§4 测试 → Task1/2；§5 文件 → File Structure。
**Placeholder scan：** 无 TBD/TODO；代码完整。
**Type consistency：** `_flip`/`_back_node`/`_back_material`/`_reveal_p`/`_front_is_back`/`_back_is_back` 全程一致；`reveal/restore` 签名不变；`FLIP_DURATION` 不变。
**注意：** 双面几何的"背面朝上不镜像"依赖背面板预旋 180°（Task1 断言 180）；最终镜像正确性由**人工目视**确认。
