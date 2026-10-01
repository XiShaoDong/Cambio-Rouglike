# Table3D 调参工具（Table3D Tuner）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提供一个独立沙盒场景，实时调整 3D 桌面的相机/座位/桌面卡牌/玩家建模/HUD 参数，并由开发者手动把数值写回源文件。

**Architecture:** 纯客户端开发工具，只新增文件。`table3d_tuner_model.gd` 是纯函数（参数表 + 从源文件文本解析 + 文本写回变换 + 片段生成，可 headless 测）；`table3d_tuner_writer.gd` 只做文件 I/O（脏检查/备份/写入）；`table3d_tuner.gd` 实例化真实的 `table3d.tscn`、自建样例牌、按与运行时相同的公式应用参数、构建调参 dock。写回完全由开发者触发。

**Tech Stack:** Godot 4.6 · GDScript · headless 单元测试（`--headless --path . res://tests/verify_*.tscn`）。

## Global Constraints

- **只新增文件**：`scenes/dev/table3d_tuner.tscn`、`scripts/dev/table3d_tuner.gd`、`scripts/dev/table3d_tuner_model.gd`、`scripts/dev/table3d_tuner_writer.gd`、`tests/verify_table3d_tuner.gd`、`tests/verify_table3d_tuner.tscn`。**运行期不得修改任何既有文件**；既有文件只在开发者于工具 UI 中显式点「写回」时被数值替换。
- 不改 `scripts/core/*`、`scripts/net/*`、规则/协议/快照；不改 `main.gd`、`table3d_view.gd`、`card_block.gd`、`board3d.gd`、`table3d_hud.gd`、`table3d_layout.gd`、`table3d_camera.gd`、`table3d.tscn` 的**代码/结构**（仅写回数值）。
- 不新增 `addons/`，不改 `project.godot`。
- 沙盒**不调用** `Table3dView.render()`。
- 写回规则：用**锚点正则**定位，仅替换目标数值；写前 `git status --porcelain` 脏检查（默认拦截，需 `force` 才覆盖）；写前备份 `<file>.bak`。
- 测试使用 `user://` 临时文件，**不得写 `res://` 或修改仓库文件**。
- 提交遵循项目约定 `feat/fix/doc`；是否提交/推送由用户决定，计划中的 commit 步骤在实际执行时先征得用户同意。
- 引擎路径（本机 macOS）：`/Applications/Godot.app/Contents/MacOS/Godot`。

---

## 文件结构

| 文件 | 职责 |
| --- | --- |
| `scripts/dev/table3d_tuner_model.gd` | 纯函数：参数定义/默认值、`parse_sources`、`apply_layout/apply_scene/apply_view`、`format_fragment` |
| `scripts/dev/table3d_tuner_writer.gd` | I/O：`is_dirty`（可注入）、`backup`、`write` |
| `scripts/dev/table3d_tuner.gd` | 场景主控：加载 `table3d.tscn`、样例牌、`apply_values`、dock UI、写回编排 |
| `scenes/dev/table3d_tuner.tscn` | 沙盒根场景（Node3D + 脚本） |
| `tests/verify_table3d_tuner.gd` / `.tscn` | headless 单测 |

参数键（`values` 字典）：

```
camera_eye_height, camera_back, camera_sensitivity,
seat_radius, seat_angle_offset,
table_radius, block_w, block_h, block_d, gap_x, gap_z,
body_y, head_y,
hud_offset, hud_height, pending_y
```

---

### Task 1: 参数表与默认值

**Files:**
- Create: `scripts/dev/table3d_tuner_model.gd`
- Test: `tests/verify_table3d_tuner.gd`, `tests/verify_table3d_tuner.tscn`

**Interfaces:**
- Produces: `Table3dTunerModel.params() -> Dictionary`（键 → `{group,label,min,max,step,default}`）、`Table3dTunerModel.groups() -> Array[String]`、`Table3dTunerModel.defaults() -> Dictionary`、常量 `LAYOUT_FILE`/`SCENE_FILE`/`VIEW_FILE`。

- [ ] **Step 1: 建测试骨架与场景**

`tests/verify_table3d_tuner.tscn`：

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/verify_table3d_tuner.gd" id="1"]

[node name="VerifyTable3dTuner" type="Node"]
script = ExtResource("1")
```

`tests/verify_table3d_tuner.gd`：

```gdscript
extends Node
## headless 单元测试：Table3D 调参工具（纯函数 + 写回引擎 + 场景应用）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TABLE3D TUNER RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_params()
	await get_tree().process_frame

func _test_params() -> void:
	var p := Table3dTunerModel.params()
	_check("参数表含相机眼高", p.has("camera_eye_height"))
	_check("参数表含座位半径", p.has("seat_radius"))
	_check("参数表含 pending_y", p.has("pending_y"))
	_check("每个参数有 default", _all_have(p, "default"))
	var d := Table3dTunerModel.defaults()
	_check("defaults 键数一致", d.size() == p.size())
	_check("默认眼高 3.5", is_equal_approx(float(d["camera_eye_height"]), 3.5))
	_check("默认座位半径 2.4", is_equal_approx(float(d["seat_radius"]), 2.4))
	_check("分组非空", Table3dTunerModel.groups().size() >= 4)

func _all_have(p: Dictionary, k: String) -> bool:
	for key in p.keys():
		if not (p[key] as Dictionary).has(k):
			return false
	return true
```

- [ ] **Step 2: 运行测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_tuner.tscn`
Expected: 解析错误/`Table3dTunerModel` 未定义。

- [ ] **Step 3: 实现 model 的参数表**

`scripts/dev/table3d_tuner_model.gd`：

```gdscript
class_name Table3dTunerModel
extends RefCounted
## Table3D 调参工具的纯函数层：参数定义、源文件解析、写回文本变换、片段生成。
## 无 I/O、无节点依赖 → headless 可测。

const LAYOUT_FILE := "res://scripts/ui/table3d_layout.gd"
const SCENE_FILE := "res://scenes/ui/table3d.tscn"
const VIEW_FILE := "res://scripts/ui/table3d_view.gd"

## key -> {group, label, min, max, step, default}
static func params() -> Dictionary:
	return {
		"camera_eye_height": _p("相机", "眼高 EYE_HEIGHT", 0.5, 8.0, 0.05, 3.5),
		"camera_back": _p("相机", "后退 CAMERA_BACK", 0.0, 5.0, 0.05, 1.5),
		"camera_sensitivity": _p("相机", "灵敏度", 0.05, 2.0, 0.05, 0.35),
		"seat_radius": _p("座位", "座位半径 SEAT_RADIUS", 0.5, 6.0, 0.05, 2.4),
		"seat_angle_offset": _p("座位", "整体角度偏移", -45.0, 45.0, 1.0, 0.0),
		"table_radius": _p("桌面·卡牌", "桌面半径 TABLE_RADIUS", 1.0, 6.0, 0.05, 3.5),
		"block_w": _p("桌面·卡牌", "卡宽 BLOCK_SIZE.x", 0.2, 1.5, 0.01, 0.7),
		"block_h": _p("桌面·卡牌", "卡厚 BLOCK_SIZE.y", 0.01, 0.2, 0.005, 0.04),
		"block_d": _p("桌面·卡牌", "卡深 BLOCK_SIZE.z", 0.2, 2.0, 0.01, 1.0),
		"gap_x": _p("桌面·卡牌", "列距 BLOCK_GAP.x", 0.0, 0.5, 0.005, 0.06),
		"gap_z": _p("桌面·卡牌", "行距 BLOCK_GAP.z", 0.0, 0.5, 0.005, 0.06),
		"body_y": _p("玩家建模", "身体高 Body.y", -1.5, 0.5, 0.01, -0.6),
		"head_y": _p("玩家建模", "头高 Head.y", -1.0, 1.0, 0.01, 0.0),
		"hud_offset": _p("HUD", "HUD_OFFSET", 0.0, 2.0, 0.05, 0.55),
		"hud_height": _p("HUD", "HUD_HEIGHT", 0.0, 2.0, 0.05, 0.5),
		"pending_y": _p("HUD", "PENDING_Y", 0.0, 2.0, 0.05, 0.75),
	}

static func _p(group: String, label: String, mn: float, mx: float, st: float, default: float) -> Dictionary:
	return {"group": group, "label": label, "min": mn, "max": mx, "step": st, "default": default}

static func groups() -> Array:
	var out: Array = []
	for key in params().keys():
		var g := str((params()[key] as Dictionary)["group"])
		if not out.has(g):
			out.append(g)
	return out

static func defaults() -> Dictionary:
	var out := {}
	for key in params().keys():
		out[key] = float((params()[key] as Dictionary)["default"])
	return out
```

- [ ] **Step 4: 运行测试确认通过**

Run: `... res://tests/verify_table3d_tuner.tscn`
Expected: `TABLE3D TUNER RESULT: 8/8 passed`（具体数字以断言数为准，全部 PASS）。

- [ ] **Step 5: Commit（征得用户同意后）**

```bash
git add scripts/dev/table3d_tuner_model.gd tests/verify_table3d_tuner.gd tests/verify_table3d_tuner.tscn
git commit -m "feat: Table3D 调参工具参数表与测试骨架"
```

---

### Task 2: 从源文件文本解析当前值

**Files:**
- Modify: `scripts/dev/table3d_tuner_model.gd`
- Test: `tests/verify_table3d_tuner.gd`

**Interfaces:**
- Consumes: Task 1 的 `params()`/`defaults()`。
- Produces:
  - `Table3dTunerModel.parse_layout(text: String) -> Dictionary`（`seat_radius, table_radius, block_w, block_h, block_d, gap_x, gap_z, angles: Array[float]`）
  - `Table3dTunerModel.parse_scene(text: String) -> Dictionary`（`camera_eye_height, camera_back, camera_sensitivity, body_y, head_y`）
  - `Table3dTunerModel.parse_view(text: String) -> Dictionary`（`hud_offset, hud_height, pending_y`）
  - `Table3dTunerModel.parse_sources(texts: Dictionary) -> Dictionary`（合并三者为完整 `values` 键集；`seat_angle_offset` 恒为 0.0）

- [ ] **Step 1: 写失败测试**

在 `tests/verify_table3d_tuner.gd` 的 `_run()` 中加 `_test_parse()`，并实现：

```gdscript
func _test_parse() -> void:
	var layout := """
const BLOCK_SIZE := Vector3(0.70, 0.04, 1.00)   # 平铺桌面
const BLOCK_GAP := Vector3(0.06, 0.0, 0.06)
const TABLE_RADIUS := 3.5  # 半边长
const SEAT_RADIUS := 2.4
const ANGLE_ORDER := [0.0, 270.0, 90.0, 180.0]
"""
	var pl := Table3dTunerModel.parse_layout(layout)
	_check("解析 SEAT_RADIUS", is_equal_approx(float(pl["seat_radius"]), 2.4))
	_check("解析 TABLE_RADIUS", is_equal_approx(float(pl["table_radius"]), 3.5))
	_check("解析 BLOCK_SIZE", is_equal_approx(float(pl["block_w"]), 0.7)
		and is_equal_approx(float(pl["block_h"]), 0.04) and is_equal_approx(float(pl["block_d"]), 1.0))
	_check("解析 ANGLE_ORDER", (pl["angles"] as Array).size() == 4
		and is_equal_approx(float(pl["angles"][1]), 270.0))
	var scene := """
[node name="CameraRig" type="Node3D" parent="."]
EYE_HEIGHT = 3.5
CAMERA_BACK = 1.5
MOUSE_SENSITIVITY = 0.35
[node name="Body" type="MeshInstance3D" parent="Seats/Seat0/Avatar"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.6, 0)
"""
	var ps := Table3dTunerModel.parse_scene(scene)
	_check("解析相机眼高", is_equal_approx(float(ps["camera_eye_height"]), 3.5))
	_check("解析灵敏度", is_equal_approx(float(ps["camera_sensitivity"]), 0.35))
	_check("解析 Body.y", is_equal_approx(float(ps["body_y"]), -0.6))
	var view := """
const HUD_OFFSET := 0.55
const HUD_HEIGHT := 0.5
const PENDING_Y := 0.75  # 大牌高度
"""
	var pv := Table3dTunerModel.parse_view(view)
	_check("解析 HUD_OFFSET", is_equal_approx(float(pv["hud_offset"]), 0.55))
	_check("解析 PENDING_Y", is_equal_approx(float(pv["pending_y"]), 0.75))
	var merged := Table3dTunerModel.parse_sources({Table3dTunerModel.LAYOUT_FILE: layout,
		Table3dTunerModel.SCENE_FILE: scene, Table3dTunerModel.VIEW_FILE: view})
	_check("合并解析含全部键", merged.size() == Table3dTunerModel.params().size())
	_check("seat_angle_offset 解析为 0", is_equal_approx(float(merged["seat_angle_offset"]), 0.0))
```

- [ ] **Step 2: 运行确认失败**

Run: `... res://tests/verify_table3d_tuner.tscn`
Expected: FAIL（`parse_layout` 未定义）。

- [ ] **Step 3: 实现解析**

追加到 `table3d_tuner_model.gd`：

```gdscript
static func _first_float(text: String, pattern: String) -> float:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return 0.0
	var m := re.search(text)
	return float(m.get_string(1)) if m != null else 0.0

static func _vec3(text: String, name: String) -> Array:
	var re := RegEx.new()
	if re.compile("const %s := Vector3\\(([^)]*)\\)" % name) != OK:
		return [0.0, 0.0, 0.0]
	var m := re.search(text)
	if m == null:
		return [0.0, 0.0, 0.0]
	var out: Array = []
	for part in m.get_string(1).split(","):
		out.append(float(part.strip_edges()))
	return out

static func parse_layout(text: String) -> Dictionary:
	var b := _vec3(text, "BLOCK_SIZE")
	var g := _vec3(text, "BLOCK_GAP")
	var angles: Array = []
	var re := RegEx.new()
	if re.compile("const ANGLE_ORDER := \\[([^\\]]*)\\]") == OK:
		var m := re.search(text)
		if m != null:
			for part in m.get_string(1).split(","):
				angles.append(float(part.strip_edges()))
	return {
		"seat_radius": _first_float(text, "const SEAT_RADIUS := ([0-9.]+)"),
		"table_radius": _first_float(text, "const TABLE_RADIUS := ([0-9.]+)"),
		"block_w": float(b[0]), "block_h": float(b[1]), "block_d": float(b[2]),
		"gap_x": float(g[0]), "gap_z": float(g[2]),
		"angles": angles,
	}

static func parse_scene(text: String) -> Dictionary:
	return {
		"camera_eye_height": _first_float(text, "(?m)^EYE_HEIGHT = ([0-9.]+)"),
		"camera_back": _first_float(text, "(?m)^CAMERA_BACK = ([0-9.]+)"),
		"camera_sensitivity": _first_float(text, "(?m)^MOUSE_SENSITIVITY = ([0-9.]+)"),
		"body_y": _first_float(text, "\\[node name=\"Body\"[^\\n]*\\]\\ntransform = Transform3D\\([^)]*, ([0-9.\\-]+), 0\\)"),
		"head_y": _first_float(text, "\\[node name=\"Head\"[^\\n]*\\]\\ntransform = Transform3D\\([^)]*, ([0-9.\\-]+), 0\\)"),
	}

static func parse_view(text: String) -> Dictionary:
	return {
		"hud_offset": _first_float(text, "const HUD_OFFSET := ([0-9.]+)"),
		"hud_height": _first_float(text, "const HUD_HEIGHT := ([0-9.]+)"),
		"pending_y": _first_float(text, "const PENDING_Y := ([0-9.]+)"),
	}

static func parse_sources(texts: Dictionary) -> Dictionary:
	var out := {}
	out.merge(parse_layout(str(texts.get(LAYOUT_FILE, ""))), true)
	out.merge(parse_scene(str(texts.get(SCENE_FILE, ""))), true)
	out.merge(parse_view(str(texts.get(VIEW_FILE, ""))), true)
	out["seat_angle_offset"] = 0.0
	return out
```

> 注：`body_y`/`head_y` 的正则用 `[^)]*, ...` 捕获最后一个逗号前的值；`.tscn` 的 `Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.6, 0)` 中第 10 个分量是 Y。

- [ ] **Step 4: 运行确认通过**

Run: `... res://tests/verify_table3d_tuner.tscn`
Expected: 全部 PASS。

- [ ] **Step 5: Commit（征得用户同意后）**

```bash
git add scripts/dev/table3d_tuner_model.gd tests/verify_table3d_tuner.gd
git commit -m "feat: 调参工具源文件数值解析"
```

---

### Task 3: 写回文本变换 + 片段生成

**Files:**
- Modify: `scripts/dev/table3d_tuner_model.gd`
- Test: `tests/verify_table3d_tuner.gd`

**Interfaces:**
- Consumes: Task 2 的解析函数、Task 1 的 `defaults()`。
- Produces:
  - `Table3dTunerModel.apply_layout(text, values) -> Dictionary` `{text, missed}`
  - `Table3dTunerModel.apply_scene(text, values) -> Dictionary`
  - `Table3dTunerModel.apply_view(text, values) -> Dictionary`
  - `Table3dTunerModel.format_fragment(values) -> String`
  - `Table3dTunerModel._sub_group(text, pattern, group, new_text, all) -> String`

- [ ] **Step 1: 写失败测试**

```gdscript
func _test_apply() -> void:
	var v := Table3dTunerModel.defaults()
	v["seat_radius"] = 3.0
	v["block_w"] = 0.8
	v["block_d"] = 1.2
	v["table_radius"] = 4.0
	var layout := """
const BLOCK_SIZE := Vector3(0.7, 0.04, 1.0)   # 保留注释
const BLOCK_GAP := Vector3(0.06, 0.0, 0.06)
const TABLE_RADIUS := 3.5
const SEAT_RADIUS := 2.4
const ANGLE_ORDER := [0.0, 270.0, 90.0, 180.0]
const OTHER := 99
"""
	var rl := Table3dTunerModel.apply_layout(layout, v)
	_check("写回 SEAT_RADIUS", (rl["text"] as String).contains("const SEAT_RADIUS := 3.0"))
	_check("保留注释", (rl["text"] as String).contains("# 保留注释"))
	_check("保留无关常量", (rl["text"] as String).contains("const OTHER := 99"))
	_check("写回 BLOCK_SIZE", (rl["text"] as String).contains("const BLOCK_SIZE := Vector3(0.8, 0.04, 1.2)"))
	_check("无遗漏", (rl["missed"] as Array).is_empty())
	# 角度偏移 bake 进 ANGLE_ORDER
	v["seat_angle_offset"] = 5.0
	var rl2 := Table3dTunerModel.apply_layout(layout, v)
	_check("角度偏移写入 ANGLE_ORDER", (rl2["text"] as String).contains("[5.0, 275.0, 95.0, 185.0]"))
	# scene
	var scene := """
[node name="CameraRig" type="Node3D" parent="."]
EYE_HEIGHT = 3.5
CAMERA_BACK = 1.5
MOUSE_SENSITIVITY = 0.35
[node name="Body" type="MeshInstance3D" parent="Seats/Seat0/Avatar"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.6, 0)
"""
	v["camera_eye_height"] = 4.0
	v["body_y"] = -0.7
	var rs := Table3dTunerModel.apply_scene(scene, v)
	_check("写回 EYE_HEIGHT", (rs["text"] as String).contains("EYE_HEIGHT = 4.0"))
	_check("写回 Body.y", (rs["text"] as String).contains(", -0.7, 0)"))
	# view
	var view := """
const HUD_OFFSET := 0.55
const HUD_HEIGHT := 0.5
const PENDING_Y := 0.75  # 注释
"""
	v["pending_y"] = 0.9
	var rv := Table3dTunerModel.apply_view(view, v)
	_check("写回 PENDING_Y", (rv["text"] as String).contains("const PENDING_Y := 0.9"))
	_check("view 保留注释", (rv["text"] as String).contains("# 注释"))
	# fragment
	var frag := Table3dTunerModel.format_fragment(v)
	_check("片段含 SEAT_RADIUS", frag.contains("const SEAT_RADIUS := 3.0"))
	_check("片段含 EYE_HEIGHT", frag.contains("EYE_HEIGHT = 4.0"))
	# 锚点缺失 → missed 记录且原文本不变
	var bad := Table3dTunerModel.apply_layout("no constants here", v)
	_check("锚点缺失记 missed", (bad["missed"] as Array).size() > 0)
	_check("缺失时不改文本", bad["text"] == "no constants here")
```

- [ ] **Step 2: 运行确认失败**

Run: `... res://tests/verify_table3d_tuner.tscn` → FAIL。

- [ ] **Step 3: 实现写回**

```gdscript
## 替换 text 中 pattern 的第 group 组为 new_text。group 组无匹配返回 (ok=false, text 原样)。
static func _sub_group(text: String, pattern: String, group: int, new_text: String, all := false) -> Dictionary:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return {"ok": false, "text": text}
	var out := ""
	var pos := 0
	var hit := false
	while true:
		var m := re.search(text, pos)
		if m == null:
			break
		out += text.substr(pos, m.get_start(group) - pos)
		out += new_text
		pos = m.get_end(group)
		hit = true
		if not all:
			break
	out += text.substr(pos)
	return {"ok": hit, "text": out} if hit else {"ok": false, "text": text}

static func _fmt(f: float, decimals := 3) -> String:
	var s := String.num(f, decimals)
	return s.trim_suffix("0").trim_suffix(".") if s.contains(".") else s

static func apply_layout(text: String, values: Dictionary) -> Dictionary:
	var t := text
	var missed: Array = []
	var steps := [
		["const SEAT_RADIUS := ([0-9.]+)", "seat_radius"],
		["const TABLE_RADIUS := ([0-9.]+)", "table_radius"],
	]
	for s in steps:
		var r := _sub_group(t, s[0], 1, _fmt(float(values.get(s[1], 0.0))))
		t = r["text"]
		if not r["ok"]:
			missed.append(s[1])
	var b := _sub_group(t, "const BLOCK_SIZE := ([^\\n#]+)", 1,
		"Vector3(%s, %s, %s)" % [_fmt(float(values["block_w"])), _fmt(float(values["block_h"])), _fmt(float(values["block_d"]))])
	t = b["text"]
	if not b["ok"]:
		missed.append("block_size")
	var g := _sub_group(t, "const BLOCK_GAP := ([^\\n#]+)", 1,
		"Vector3(%s, 0.0, %s)" % [_fmt(float(values["gap_x"])), _fmt(float(values["gap_z"]))])
	t = g["text"]
	if not g["ok"]:
		missed.append("block_gap")
	# 角度：解析基准 + 偏移 → 覆盖 ANGLE_ORDER
	var base: Array = parse_layout(text)["angles"]
	var off := float(values.get("seat_angle_offset", 0.0))
	var parts: Array = []
	for a in base:
		parts.append(_fmt(float(a) + off))
	var an := _sub_group(t, "const ANGLE_ORDER := (\\[[^\\]]*\\])", 1, "[%s]" % ", ".join(parts))
	t = an["text"]
	if not an["ok"]:
		missed.append("angle_order")
	return {"text": t, "missed": missed}

static func apply_scene(text: String, values: Dictionary) -> Dictionary:
	var t := text
	var missed: Array = []
	var scalars := [
		[["camera_eye_height"], "(?m)^EYE_HEIGHT = ([0-9.]+)"],
		[["camera_back"], "(?m)^CAMERA_BACK = ([0-9.]+)"],
		[["camera_sensitivity"], "(?m)^MOUSE_SENSITIVITY = ([0-9.]+)"],
	]
	for s in scalars:
		var r := _sub_group(t, s[1], 1, _fmt(float(values.get(s[0][0], 0.0))))
		t = r["text"]
		if not r["ok"]:
			missed.append(s[0][0])
	# 桌面网格尺寸 = 2 × table_radius；边框 = 网格 + 0.375（块锚定，见下方辅助函数）
	var d := float(values["table_radius"]) * 2.0
	t = _apply_table_size(t, d)
	t = _apply_edge_size(t, d + 0.375)
	# Body / Head 局部 Y（块锚定，4 席全部）
	var body_re := "\\[node name=\"Body\" type=\"MeshInstance3D\" parent=\"Seats/Seat\\d+/Avatar\"\\]\\ntransform = Transform3D\\([^)]*, ([0-9.\\-]+), 0\\)"
	var rb := _sub_group(t, body_re, 1, _fmt(float(values["body_y"])), true)
	t = rb["text"]
	if not rb["ok"]:
		missed.append("body_y")
	var head_re := "\\[node name=\"Head\" type=\"MeshInstance3D\" parent=\"Seats/Seat\\d+/Avatar\"\\]\\ntransform = Transform3D\\([^)]*, ([0-9.\\-]+), 0\\)"
	var rh := _sub_group(t, head_re, 1, _fmt(float(values["head_y"])), true)
	t = rh["text"]
	if not rh["ok"]:
		missed.append("head_y")
	return {"text": t, "missed": missed}
```

上面 `_apply_table_size`/`_apply_edge_size` 用**块锚定 + size 组替换**实现（避免依赖 `TableEdge` 前瞻，且可重复执行）：

```gdscript
static func _box_mesh_size_pattern(id: String) -> String:
	return "(\\[sub_resource type=\"BoxMesh\" id=\"%s\"\\]\\n(?:[^\\n]*\\n)*?size = )Vector3\\(([^)]*)\\)" % id

static func _apply_box_size(text: String, id: String, size: Vector3) -> Dictionary:
	var pat := _box_mesh_size_pattern(id)
	var re := RegEx.new()
	if re.compile(pat) != OK:
		return {"ok": false, "text": text}
	var m := re.search(text)
	if m == null:
		return {"ok": false, "text": text}
	var new_line := "Vector3(%s, %s, %s)" % [_fmt(size.x), _fmt(size.y), _fmt(size.z)]
	var start := m.get_start(2)
	var end := m.get_end(2)
	return {"ok": true, "text": text.substr(0, start) + new_line + text.substr(end)}

static func _apply_table_size(text: String, side: float) -> String:
	return _apply_box_size(text, "TableMesh", Vector3(side, 0.08, side))["text"]

static func _apply_edge_size(text: String, side: float) -> String:
	return _apply_box_size(text, "TableEdgeMesh", Vector3(side, 0.12, side))["text"]
```

> 删除上面 `apply_scene` 中 `tbl`/`r_t` 的占位两行（它们是草稿），保留 `_apply_table_size`/`_apply_edge_size` 调用。

`apply_view` 与 `format_fragment`：

```gdscript
static func apply_view(text: String, values: Dictionary) -> Dictionary:
	var t := text
	var missed: Array = []
	var steps := [
		["const HUD_OFFSET := ([0-9.]+)", "hud_offset"],
		["const HUD_HEIGHT := ([0-9.]+)", "hud_height"],
		["const PENDING_Y := ([0-9.]+)", "pending_y"],
	]
	for s in steps:
		var r := _sub_group(t, s[0], 1, _fmt(float(values.get(s[1], 0.0))))
		t = r["text"]
		if not r["ok"]:
			missed.append(s[1])
	return {"text": t, "missed": missed}

static func format_fragment(values: Dictionary) -> String:
	var lines := [
		"# 由 Table3D Tuner 生成",
		"const SEAT_RADIUS := %s" % _fmt(float(values["seat_radius"])),
		"const TABLE_RADIUS := %s" % _fmt(float(values["table_radius"])),
		"const BLOCK_SIZE := Vector3(%s, %s, %s)" % [_fmt(float(values["block_w"])), _fmt(float(values["block_h"])), _fmt(float(values["block_d"]))],
		"const BLOCK_GAP := Vector3(%s, 0.0, %s)" % [_fmt(float(values["gap_x"])), _fmt(float(values["gap_z"]))],
		"# table3d.tscn / CameraRig",
		"EYE_HEIGHT = %s" % _fmt(float(values["camera_eye_height"])),
		"CAMERA_BACK = %s" % _fmt(float(values["camera_back"])),
		"MOUSE_SENSITIVITY = %s" % _fmt(float(values["camera_sensitivity"])),
		"# table3d_view.gd",
		"HUD_OFFSET := %s" % _fmt(float(values["hud_offset"])),
		"HUD_HEIGHT := %s" % _fmt(float(values["hud_height"])),
		"PENDING_Y := %s" % _fmt(float(values["pending_y"])),
	]
	return "\n".join(lines)
```

- [ ] **Step 4: 运行确认通过**

Run: `... res://tests/verify_table3d_tuner.tscn`
Expected: 全部 PASS。

- [ ] **Step 5: Commit（征得用户同意后）**

```bash
git add scripts/dev/table3d_tuner_model.gd tests/verify_table3d_tuner.gd
git commit -m "feat: 调参工具写回文本变换与片段生成"
```

---

### Task 4: 写回引擎（脏检查 / 备份 / 写入）

**Files:**
- Create: `scripts/dev/table3d_tuner_writer.gd`
- Test: `tests/verify_table3d_tuner.gd`

**Interfaces:**
- Consumes: 无（独立于 model）。
- Produces:
  - `Table3dTunerWriter.new(dirty_checker := Callable())`
  - `writer.is_dirty(path) -> bool`（默认查 git；`res://` 前缀剥离为仓库相对路径）
  - `writer.write(path, new_text, force := false) -> Dictionary`（`{ok, error}`；脏且非 force → `{ok:false, error:"dirty"}`；写前备份 `<path>.bak`；写 `user://`/`res://` 均可用 `FileAccess`）
  - `writer.backup_path(path) -> String`

- [ ] **Step 1: 写失败测试**

```gdscript
func _test_writer() -> void:
	var dir := "user://tuner_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := dir + "/sample.txt"
	var fw := FileAccess.open(f, FileAccess.WRITE)
	fw.store_string("hello")
	fw.close()
	# 注入脏检查 stub
	var dirty := {"v": true}
	var w := Table3dTunerWriter.new(func(_p): return dirty["v"])
	var blocked := w.write(f, "blocked", false)
	_check("脏文件默认拦截", not blocked["ok"] and blocked["error"] == "dirty")
	var okw := w.write(f, "written", true)
	_check("force 可写", okw["ok"])
	var f2 := FileAccess.open(f, FileAccess.READ)
	_check("内容已写", f2.get_as_text() == "written")
	f2.close()
	_check("备份存在", FileAccess.file_exists(w.backup_path(f)))
	var force_write := w.write(f, "written2", false)
	_check("force 写时 bak 保留旧内容", force_write["ok"])
	var bak := FileAccess.open(w.backup_path(f), FileAccess.READ)
	_check("bak 内容=旧值", bak.get_as_text() == "written")
	bak.close()
	_check("路径 .bak 后缀", w.backup_path("res://a.gd") == "res://a.gd.bak")
```

- [ ] **Step 2: 运行确认失败**

Run: `... res://tests/verify_table3d_tuner.tscn` → FAIL（`Table3dTunerWriter` 未定义）。

- [ ] **Step 3: 实现 writer**

```gdscript
class_name Table3dTunerWriter
extends RefCounted
## 写回引擎：脏检查 + 备份 + 写入。不负责计算新文本（由 model.apply_* 提供）。

var _dirty_checker: Callable
var _git_ok := true

func _init(dirty_checker := Callable()) -> void:
	_dirty_checker = dirty_checker

func backup_path(path: String) -> String:
	return path + ".bak"

func is_dirty(path: String) -> bool:
	if _dirty_checker.is_valid():
		return bool(_dirty_checker.call(path))
	return _git_dirty(path)

func _git_dirty(path: String) -> bool:
	if not _git_ok:
		return false
	var rel := path.trim_prefix("res://")
	var out: Array = []
	var code := OS.execute("git", ["status", "--porcelain", "--", rel], out, true)
	if code != 0:
		_git_ok = false
		return false   # git 不可用时不阻断（由用户判断）
	return not str(out[0] if out.size() > 0 else "").strip_edges().is_empty()

func write(path: String, new_text: String, force := false) -> Dictionary:
	if not force and is_dirty(path):
		return {"ok": false, "error": "dirty"}
	if FileAccess.file_exists(path):
		var src := FileAccess.open(path, FileAccess.READ)
		var old := src.get_as_text() if src != null else ""
		if src != null:
			src.close()
		var bak := FileAccess.open(backup_path(path), FileAccess.WRITE)
		if bak != null:
			bak.store_string(old)
			bak.close()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "open_failed"}
	f.store_string(new_text)
	f.close()
	return {"ok": true, "error": ""}
```

- [ ] **Step 4: 运行确认通过**

Run: `... res://tests/verify_table3d_tuner.tscn` → 全部 PASS。

- [ ] **Step 5: Commit（征得用户同意后）**

```bash
git add scripts/dev/table3d_tuner_writer.gd tests/verify_table3d_tuner.gd
git commit -m "feat: 调参工具写回引擎（脏检查/备份/写入）"
```

---

### Task 5: 调参场景与实时应用

**Files:**
- Create: `scenes/dev/table3d_tuner.tscn`, `scripts/dev/table3d_tuner.gd`
- Test: `tests/verify_table3d_tuner.gd`

**Interfaces:**
- Consumes: `Table3dTunerModel`、`Table3dTunerWriter`、`Table3dLayout`、`Table3dCamera`、`CardBlock`。
- Produces（供 UI 与测试用）：
  - `Table3dTuner.values: Dictionary`、`Table3dTuner.table3d: Node3D`
  - `Table3dTuner.set_value(key, value) -> void`（仅改值不应用）
  - `Table3dTuner.apply_values() -> void`（按当前 `values` 重摆节点/重建样例牌）
  - `Table3dTuner.reload_from_sources() -> void`
  - `Table3dTuner.reset_defaults() -> void`
  - `Table3dTuner.seat_nodes() -> Array`、`Table3dTuner.avatar_nodes() -> Array`

- [ ] **Step 1: 写失败测试**

```gdscript
func _test_scene_apply() -> void:
	var scene: PackedScene = load("res://scenes/dev/table3d_tuner.tscn")
	var tuner = scene.instantiate()
	add_child(tuner)
	await get_tree().process_frame
	tuner.set_value("seat_radius", 3.0)
	tuner.set_value("camera_eye_height", 4.0)
	tuner.set_value("camera_back", 1.2)
	tuner.set_value("block_w", 0.8)
	tuner.apply_values()
	await get_tree().process_frame
	var seats: Array = tuner.seat_nodes()
	_check("4 个座位", seats.size() == 4)
	_check("座位半径应用", seats[0].position.is_equal_approx(Vector3(0.0, 0.0, 3.0)))
	var cam = tuner.table3d.camera
	_check("相机眼高应用", is_equal_approx(cam.EYE_HEIGHT, 4.0))
	_check("相机后退应用", is_equal_approx(cam.CAMERA_BACK, 1.2))
	_check("相机臂随座位半径（eye=4, dist=3+1.2）", cam.position.is_equal_approx(Vector3(0.0, 4.0, 4.2)))
	_check("Avatar 随相机抬到眼高", tuner.avatar_nodes()[1].position.y == 4.0)
	_check("样例牌已建（每席 4~6 张）", seats[0].get_node("HandAnchor").get_child_count() >= 4)
```

- [ ] **Step 2: 运行确认失败**

Run: `... res://tests/verify_table3d_tuner.tscn` → FAIL（场景不存在）。

- [ ] **Step 3: 建场景与主控**

`scenes/dev/table3d_tuner.tscn`：

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/dev/table3d_tuner.gd" id="1"]

[node name="Table3dTuner" type="Node3D"]
script = ExtResource("1")
```

`scripts/dev/table3d_tuner.gd`：

```gdscript
class_name Table3dTuner
extends Node3D
## Table3D 调参沙盒：实例化真实 table3d.tscn，按参数实时重摆节点，并提供写回 UI。

const TABLE3D_SCENE := "res://scenes/ui/table3d.tscn"
const SAMPLE_CARDS := [
	{"rank": "A", "suit": "♥"}, {"rank": "K", "suit": "♠"},
	{"rank": "Q", "suit": "♦"}, {"rank": "J", "suit": "♣"},
	{"rank": "10", "suit": "♥"}, {"rank": "7", "suit": "♠"},
]

var values: Dictionary = Table3dTunerModel.defaults()
var table3d: Node3D = null
var writer := Table3dTunerWriter.new()
var show_viewer_avatar := false

func _ready() -> void:
	table3d = load(TABLE3D_SCENE).instantiate()
	add_child(table3d)   # add_child 同步触发 table3d 的 _ready，节点立即可用
	reload_from_sources()
	apply_values()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func set_value(key: String, value: float) -> void:
	values[key] = value

func seat_nodes() -> Array:
	var out: Array = []
	for i in 4:
		out.append(table3d.get_node_or_null("Seats/Seat%d" % i))
	return out

func avatar_nodes() -> Array:
	var out: Array = []
	for s in seat_nodes():
		if s != null:
			out.append(s.get_node_or_null("Avatar"))
	return out

func reload_from_sources() -> void:
	var texts := {
		Table3dTunerModel.LAYOUT_FILE: _read(Table3dTunerModel.LAYOUT_FILE),
		Table3dTunerModel.SCENE_FILE: _read(Table3dTunerModel.SCENE_FILE),
		Table3dTunerModel.VIEW_FILE: _read(Table3dTunerModel.VIEW_FILE),
	}
	values = Table3dTunerModel.parse_sources(texts)

func reset_defaults() -> void:
	values = Table3dTunerModel.defaults()

func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""

func _viewer_angle() -> float:
	var base: Array = Table3dTunerModel.parse_layout(_read(Table3dTunerModel.LAYOUT_FILE)).get("angles", [0.0])
	var a: float = float(base[0]) if base.size() > 0 else 0.0
	return a + float(values["seat_angle_offset"])

func _angles_for_display() -> Array:
	var base: Array = Table3dTunerModel.parse_layout(_read(Table3dTunerModel.LAYOUT_FILE)).get("angles", [0.0, 270.0, 90.0, 180.0])
	var out: Array = []
	for a in base:
		out.append(float(a) + float(values["seat_angle_offset"]))
	return out

func apply_values() -> void:
	if table3d == null:
		return
	_apply_scene_nodes()
	_apply_camera()
	_apply_seats()
	_apply_pending()
	_rebuild_sample_cards()
	_apply_hud()

func _apply_scene_nodes() -> void:
	var table := table3d.get_node_or_null("Table") as MeshInstance3D
	var edge := table3d.get_node_or_null("TableEdge") as MeshInstance3D
	var side := float(values["table_radius"]) * 2.0
	if table != null:
		(table.mesh as BoxMesh).size = Vector3(side, 0.08, side)
	if edge != null:
		(edge.mesh as BoxMesh).size = Vector3(side + 0.375, 0.12, side + 0.375)
	for av in avatar_nodes():
		var body := av.get_node_or_null("Body")
		var head := av.get_node_or_null("Head")
		if body != null:
			body.position.y = float(values["body_y"])
		if head != null:
			head.position.y = float(values["head_y"])

func _apply_camera() -> void:
	var cam = table3d.get_node_or_null("CameraRig")
	if cam == null:
		return
	cam.EYE_HEIGHT = float(values["camera_eye_height"])
	cam.CAMERA_BACK = float(values["camera_back"])
	cam.MOUSE_SENSITIVITY = float(values["camera_sensitivity"])
	var angle := _viewer_angle()
	cam.set("_framed", false)
	cam.frame_for_seat(angle)   # 取基准朝向 + 复位环视
	# frame_for_seat 用的是 Table3dLayout.SEAT_RADIUS 常量；用调参后的半径与眼高重摆相机臂。
	var rad := deg_to_rad(angle)
	var dir := Vector3(sin(rad), 0.0, cos(rad))
	var dist := float(values["seat_radius"]) + float(values["camera_back"])
	cam.position = dir * dist + Vector3(0.0, float(values["camera_eye_height"]), 0.0)
	cam.set("pitch", Table3dCamera.aim_pitch_deg(float(values["camera_eye_height"]), dist))
	cam.look(Vector2.ZERO)   # rel=0：不改 yaw/pitch，仅应用上面设的相机臂与俯角

func _apply_seats() -> void:
	var angles := _angles_for_display()
	var r := float(values["seat_radius"])
	for i in seat_nodes().size():
		var s: Node3D = seat_nodes()[i]
		if s == null:
			continue
		var a: float = float(angles[i]) if i < angles.size() else 0.0
		var rad := deg_to_rad(a)
		s.position = Vector3(sin(rad), 0.0, cos(rad)) * r
		s.rotation_degrees = Vector3(0.0, a + 180.0, 0.0)
		var av := s.get_node_or_null("Avatar")
		if av != null:
			av.position = Vector3(0.0, float(values["camera_eye_height"]), -float(values["camera_back"]))
			av.visible = (i != 0) or show_viewer_avatar

func _apply_pending() -> void:
	var deck := table3d.get_node_or_null("Center/Deck") as Node3D
	var disc := table3d.get_node_or_null("Center/DiscardTop") as Node3D
	var pend := table3d.get_node_or_null("Center/Pending") as Node3D
	if deck == null or disc == null or pend == null:
		return
	pend.position = Vector3((deck.position.x + disc.position.x) * 0.5, float(values["pending_y"]),
		(deck.position.z + disc.position.z) * 0.5)

func _slot_local(slot: int) -> Vector3:
	var grid := Table3dLayout.slot_grid_pos(slot)
	return Vector3(
		-grid.x * (float(values["block_w"]) + float(values["gap_x"])),
		0.0,
		(1.0 - grid.y) * (float(values["block_d"]) + float(values["gap_z"])))

func _rebuild_sample_cards() -> void:
	var count := 4
	for i in seat_nodes().size():
		var s: Node3D = seat_nodes()[i]
		if s == null:
			continue
		var hand: Node3D = s.get_node("HandAnchor")
		for child in hand.get_children():
			hand.remove_child(child)
			child.queue_free()
		for slot in count:
			var block := CardBlock.new()
			block.name = "Sample%d" % slot
			block.position = _slot_local(slot)
			hand.add_child(block)
			block.setup({"card": SAMPLE_CARDS[(i + slot) % SAMPLE_CARDS.size()]})

func _apply_hud() -> void:
	var hud = table3d.get_node_or_null("Hud")
	if hud == null:
		return
	hud.set_buttons([
		{"text": "Ready", "action": "ready", "enabled": true},
		{"text": "Kongbaya", "action": "kongbaya", "enabled": true},
		{"text": "Q", "action": "q", "enabled": false},
	])
	var rad := deg_to_rad(_viewer_angle())
	var dir := Vector3(sin(rad), 0.0, cos(rad))
	hud.position = dir * (float(values["seat_radius"]) - float(values["hud_offset"])) + Vector3(0.0, float(values["hud_height"]), 0.0)
	hud.rotation_degrees = Vector3(0.0, _viewer_angle() + 180.0, 0.0)

func _input(event: InputEvent) -> void:
	var cam = table3d.get_node_or_null("CameraRig") if table3d != null else null
	if cam == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam.look(event.relative)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
```

- [ ] **Step 4: 运行确认通过**

Run: `... res://tests/verify_table3d_tuner.tscn` → 全部 PASS。

- [ ] **Step 5: Commit（征得用户同意后）**

```bash
git add scripts/dev/table3d_tuner.gd scenes/dev/table3d_tuner.tscn tests/verify_table3d_tuner.gd
git commit -m "feat: Table3D 调参沙盒场景与实时应用"
```

---

### Task 6: 调参 UI（dock）

**Files:**
- Modify: `scripts/dev/table3d_tuner.gd`
- Test: `tests/verify_table3d_tuner.gd`

**Interfaces:**
- Consumes: Task 5 的 `values`/`apply_values`/`reload_from_sources`/`reset_defaults`、`Table3dTunerModel.params/groups/apply_*`、`Table3dTunerWriter`。
- Produces: `Table3dTuner.build_ui() -> void`、`Table3dTuner.slider_count() -> int`、`Table3dTuner.write_back(force := false) -> Array`（对勾选目标文件写回，返回每文件结果）。

- [ ] **Step 1: 写失败测试**

```gdscript
func _test_ui() -> void:
	var scene: PackedScene = load("res://scenes/dev/table3d_tuner.tscn")
	var tuner = scene.instantiate()
	add_child(tuner)
	await get_tree().process_frame
	tuner.build_ui()
	await get_tree().process_frame
	_check("UI 为每个参数建滑条", tuner.slider_count() == Table3dTunerModel.params().size())
	_check("写回目标含 layout/scene/view",
		tuner.write_targets().has(Table3dTunerModel.LAYOUT_FILE)
		and tuner.write_targets().has(Table3dTunerModel.SCENE_FILE)
		and tuner.write_targets().has(Table3dTunerModel.VIEW_FILE))
```

- [ ] **Step 2: 运行确认失败**

Run: `... res://tests/verify_table3d_tuner.tscn` → FAIL（`build_ui`/`slider_count` 未定义）。

- [ ] **Step 3: 实现 UI**

在 `table3d_tuner.gd` 追加：

```gdscript
var _sliders: Dictionary = {}     # key -> HSlider
var _value_labels: Dictionary = {} # key -> Label
var _target_checks: Dictionary = {} # file -> CheckBox
var _force_check: CheckBox


func write_targets() -> Array:
	return [Table3dTunerModel.LAYOUT_FILE, Table3dTunerModel.SCENE_FILE, Table3dTunerModel.VIEW_FILE]

func slider_count() -> int:
	return _sliders.size()

func build_ui() -> void:
	if not _sliders.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.name = "TunerUI"
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	margin.custom_minimum_size = Vector2(330, 0)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	layer.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(320, 0)
	margin.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var groups := Table3dTunerModel.groups()
	var params := Table3dTunerModel.params()
	for g in groups:
		var header := Label.new()
		header.text = "— %s —" % g
		root.add_child(header)
		for key in params.keys():
			if str((params[key] as Dictionary)["group"]) != g:
				continue
			_add_row(root, key, params[key])

	root.add_child(HSeparator.new())
	var reset_btn := Button.new()
	reset_btn.text = "重置默认"
	reset_btn.pressed.connect(func(): reset_defaults(); _sync_sliders(); apply_values())
	root.add_child(reset_btn)
	var reload_btn := Button.new()
	reload_btn.text = "重新解析源文件"
	reload_btn.pressed.connect(func(): reload_from_sources(); _sync_sliders(); apply_values())
	root.add_child(reload_btn)
	var copy_btn := Button.new()
	copy_btn.text = "复制参数片段"
	copy_btn.pressed.connect(func(): DisplayServer.clipboard_set(Table3dTunerModel.format_fragment(values)))
	root.add_child(copy_btn)

	root.add_child(HSeparator.new())
	root.add_child(_label("写回目标（手动勾选）"))
	for path in write_targets():
		var cb := CheckBox.new()
		cb.text = path
		cb.button_pressed = true
		root.add_child(cb)
		_target_checks[path] = cb
	_force_check = CheckBox.new()
	_force_check.text = "仍要覆盖占用中文件"
	_force_check.button_pressed = false
	root.add_child(_force_check)
	var write_btn := Button.new()
	write_btn.text = "写回源文件"
	write_btn.pressed.connect(func(): _report(write_back(_force_check.button_pressed)))
	root.add_child(write_btn)
	_write_log = _label("")
	root.add_child(_write_log)

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _add_row(root: VBoxContainer, key: String, meta: Dictionary) -> void:
	var row := VBoxContainer.new()
	var top := HBoxContainer.new()
	var name := _label(str(meta["label"]))
	name.custom_minimum_size = Vector2(180, 0)
	top.add_child(name)
	var value_label := _label("")
	top.add_child(value_label)
	row.add_child(top)
	var slider := HSlider.new()
	slider.min_value = float(meta["min"])
	slider.max_value = float(meta["max"])
	slider.step = float(meta["step"])
	slider.value = float(values.get(key, meta["default"]))
	slider.custom_minimum_size = Vector2(300, 0)
	slider.value_changed.connect(func(v: float):
		set_value(key, v)
		value_label.text = Table3dTunerModel._fmt(v)
		apply_values())
	row.add_child(slider)
	root.add_child(row)
	_sliders[key] = slider
	_value_labels[key] = value_label
	value_label.text = Table3dTunerModel._fmt(slider.value)

func _sync_sliders() -> void:
	for key in _sliders.keys():
		(_sliders[key] as HSlider).set_value_no_signal(float(values.get(key, 0.0)))
		(_value_labels[key] as Label).text = Table3dTunerModel._fmt(float(values.get(key, 0.0)))

var _write_log: Label = null

func write_back(force := false) -> Array:
	var results: Array = []
	var texts := {
		Table3dTunerModel.LAYOUT_FILE: _read(Table3dTunerModel.LAYOUT_FILE),
		Table3dTunerModel.SCENE_FILE: _read(Table3dTunerModel.SCENE_FILE),
		Table3dTunerModel.VIEW_FILE: _read(Table3dTunerModel.VIEW_FILE),
	}
	for path in write_targets():
		var cb: CheckBox = _target_checks.get(path)
		if cb == null or not cb.button_pressed:
			continue
		var new_text := ""
		match path:
			Table3dTunerModel.LAYOUT_FILE:
				new_text = Table3dTunerModel.apply_layout(texts[path], values)["text"]
			Table3dTunerModel.SCENE_FILE:
				new_text = Table3dTunerModel.apply_scene(texts[path], values)["text"]
			Table3dTunerModel.VIEW_FILE:
				new_text = Table3dTunerModel.apply_view(texts[path], values)["text"]
		var r := writer.write(path, new_text, force)
		r["file"] = path
		results.append(r)
	return results

func _report(results: Array) -> void:
	if _write_log == null:
		return
	var lines: Array = []
	for r in results:
		lines.append("%s → %s%s" % [str(r["file"]).get_file(), "OK" if r["ok"] else "拒绝", "" if r["ok"] else " (" + str(r["error"]) + ")"])
	_write_log.text = "写回结果:\n" + "\n".join(lines)
```

在 `_ready()` 末尾（`apply_values()` 之后）调用 `build_ui()`。

- [ ] **Step 4: 运行确认通过**

Run: `... res://tests/verify_table3d_tuner.tscn` → 全部 PASS。

- [ ] **Step 5: 手动验收（GUI）**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/dev/table3d_tuner.tscn`
Expected: 左侧出现分组滑条；拖动「座位半径/眼高/后退/卡宽」即时看到桌面、座位、角色移动；`Esc` 释放鼠标可操作滑条；点「复制参数片段」后剪贴板含片段。

- [ ] **Step 6: Commit（征得用户同意后）**

```bash
git add scripts/dev/table3d_tuner.gd tests/verify_table3d_tuner.gd
git commit -m "feat: 调参工具 dock UI 与手动写回编排"
```

---

### Task 7: 文档与全量回归

**Files:**
- Modify: `docs/AI_AGENT_交接说明.md`（补一句工具入口）、`docs/功能实现文档.md`（文件树）
- Test: 全量回归

**Interfaces:**
- Consumes: 全部前序任务。
- Produces: 无新 API。

- [ ] **Step 1: 补文档（仅追加描述，不改结构）**

在 `docs/功能实现文档.md` 的文件树/UI 段追加：`scenes/dev/table3d_tuner.tscn` + `scripts/dev/table3d_tuner*.gd`（开发者调参沙盒，手动写回）。
在 `docs/AI_AGENT_交接说明.md` 第 8 节验证命令处追加：

```
# Table3D 调参工具（参数表/解析/写回/场景应用；含 GUI 手动验收）
... --headless --path . res://tests/verify_table3d_tuner.tscn
```

- [ ] **Step 2: 跑工具单测**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_tuner.tscn`
Expected: 全部 PASS。

- [ ] **Step 3: 跑受影响回归**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_layout.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_mouse.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_interaction.tscn
```
Expected: 全绿（本工具不改其代码）。

- [ ] **Step 4: 确认零污染**

Run: `git status --short`
Expected: 仅 `scenes/dev/`、`scripts/dev/`、`tests/verify_table3d_tuner.*`、两份 docs 为新增/修改；**无其它既有代码文件被改动**。

- [ ] **Step 5: Commit（征得用户同意后）**

```bash
git add docs/AI_AGENT_交接说明.md docs/功能实现文档.md
git commit -m "doc: Table3D 调参工具入口与验证命令"
```

---

## Self-Review

**Spec coverage：** 相机（Task 5/3 scene）、座位半径+整体角度（Task 2/3 layout）、桌面卡牌尺寸（Task 3 scene+layout）、玩家建模 Body/Head（Task 3 scene）、HUD/PENDING（Task 3 view）、写回由开发者手动触发（Task 6 UI + Task 4 writer 脏检查）、只新增文件（Global Constraints + Task 7 验证）、headless 测试（各 Task）——均有对应任务。

**Placeholder scan：** Task 3 的 `tbl`/`r_t` 两行草稿已显式标注删除并给出正确实现；无其它 TODO。

**Type consistency：** `apply_*` 统一返回 `{text, missed}`；writer.write 返回 `{ok, error}`，编排层补 `file`；键名在 `params()/defaults()/parse_*` 与 UI 一致（`camera_eye_height`/`seat_radius`/`pending_y` 等）。

**已知风险：** `body_y`/`head_y` 的块锚定依赖 `table3d.tscn` 保持 `[node name="Head" ...]` 后紧跟 `transform = ...` 的写法；若开发者手改 `.tscn` 使锚点失效，写回会记入 `missed` 并在 UI 拒绝该文件（不静默破坏）。
