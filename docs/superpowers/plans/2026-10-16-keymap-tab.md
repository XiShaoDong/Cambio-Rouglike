# 按键映射页签 + 页签可点击（部分穿透）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 3D 全息看板手册面板新增第三页签「按键」——列出界面/展示类按键映射、支持重绑（冲突自动交换、保留键拒绝）、经确认浮层保存到本机 `user://`；并让手册页打开时页签/按钮可点击、其余区域穿透到牌桌。

**Architecture:** 纯函数 `KeybindModel`（动作表/resolve/rebind）+ 薄壳 `KeybindStore`（`ConfigFile` 读写）+ 独立页内容 `KeymapBoard`（键行 + 捕获态 + 保存）+ `ManualPanel`（第三页签 + 确认浮层）。`Board3d` 增 `interactive_at` 判定"该点落在可交互控件上"，`main` 只在该点命中时把点击交给看板，否则穿透（`_board_hit` 小改）。

**Tech Stack:** Godot 4.6 / GDScript；自定义 headless 测试场景（`tests/verify_*.tscn` + `.gd`，root `Node` 脚本在 `_ready` 跑断言并 `get_tree().quit`）。

## Global Constraints

- Godot 4.6；工作目录为 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard2/`（`res://` 即该根）。
- **不启动 GUI**：一律 headless 单测：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/<scene>.tscn`。
- **不改**：`scripts/core` 既有子系统（`game_state.gd`/`hidden_info.gd`/`score_system.gd`/`slap_system.gd` 等）、`scripts/net/*`、`scenes/ui/table3d.tscn`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`、`key_hint_panel.gd`。
- 本功能**仅 3D 生效**（与现有 Tab/S 一致）；2D 界面逐字不动。
- 键盘映射纯客户端：不联网、不进快照、不下发其他玩家。
- **保留键不可绑定**：空格 `KEY_SPACE`、`KEY_ENTER`、`KEY_KP_ENTER`、`KEY_ESCAPE`、`KEY_F10`、`KEY_ALT`。
- 提交信息按 `feat:` / `fix:` / `doc:` 分类；每个 Task 末尾单独提交。
- **仓库跟踪 `.gd.uid`**（Godot 4 自动生成）：新增脚本时其 `.gd.uid` 必须一并 `git add`。
- 代码内用 `res://`；文档/交接用绝对路径。

---

### Task 1: `KeybindModel` 纯函数模型 + `verify_keybind` 测试脚手架

**Files:**
- Create: `scripts/core/keybind_model.gd`
- Create: `tests/verify_keybind.gd`
- Create: `tests/verify_keybind.tscn`

**Interfaces:**
- Produces: `class_name KeybindModel extends RefCounted`；`const ACTIONS` / `RESERVED` / `ERR_RESERVED` / `ERR_UNKNOWN`；`defaults() -> Dictionary`、`action_ids() -> Array`、`action_def(id) -> Dictionary`、`resolve(map, keycode) -> String`、`rebind(map, id, keycode) -> Dictionary`（`{ok, error, map, swapped}`）、`to_dict(map) -> Dictionary`、`from_dict(d) -> Dictionary`。

- [ ] **Step 1: 写失败测试**

创建 `tests/verify_keybind.tscn`：

```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/verify_keybind.gd" id="1"]
[node name="VerifyKeybind" type="Node"]
script = ExtResource("1")
```

创建 `tests/verify_keybind.gd`：

```gdscript
extends Node
## headless 单元测试：KeybindModel 纯函数 + KeybindStore 持久化 + KeymapBoard 页内容。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== KEYBIND RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_model()

func _test_model() -> void:
	var m: Dictionary = KeybindModel.defaults()
	_check("默认 6 个动作", m.size() == 6)
	_check("Tab 绑手册", int(m["kb_manual"]) == KEY_TAB)
	_check("S 绑 Stats", int(m["kb_stats"]) == KEY_S)
	_check("K 绑按键映射", int(m["kb_keymap"]) == KEY_K)
	_check("resolve Tab→kb_manual", KeybindModel.resolve(m, KEY_TAB) == "kb_manual")
	_check("resolve 未绑定→空", KeybindModel.resolve(m, KEY_Z) == "")
	_check("动作表有序", str(KeybindModel.action_ids()[0]) == "kb_manual")
	_check("action_def 有说明", str(KeybindModel.action_def("kb_manual")["desc"]) != "")
	# rebind 成功（KEY_T 不在动作表里）
	var r: Dictionary = KeybindModel.rebind(m, "kb_stats", KEY_T)
	_check("rebind 成功", bool(r["ok"]) and int(r["map"]["kb_stats"]) == KEY_T)
	_check("rebind 不就地改入参", int(m["kb_stats"]) == KEY_S)
	# 自动交换：kb_stats → KEY_M（当前属 kb_talk）
	var r2: Dictionary = KeybindModel.rebind(m, "kb_stats", KEY_M)
	_check("自动交换 swapped=kb_talk", bool(r2["ok"]) and str(r2["swapped"]) == "kb_talk")
	_check("交换后 kb_talk 得到旧键 S", int(r2["map"]["kb_talk"]) == KEY_S)
	_check("交换后 kb_stats=M", int(r2["map"]["kb_stats"]) == KEY_M)
	# 保留键
	var r3: Dictionary = KeybindModel.rebind(m, "kb_stats", KEY_SPACE)
	_check("保留键拒绝", not bool(r3["ok"]) and str(r3["error"]) == "reserved")
	# 未知动作
	var r4: Dictionary = KeybindModel.rebind(m, "nope", KEY_Z)
	_check("未知动作拒绝", not bool(r4["ok"]) and str(r4["error"]) == "unknown_action")
	# 往返
	_check("to/from dict 往返", KeybindModel.from_dict(KeybindModel.to_dict(m)) == m)
	# from_dict 回退
	var bad: Dictionary = KeybindModel.from_dict({"kb_stats": KEY_SPACE, "ghost": KEY_Z})
	_check("非法保留值回退默认", int(bad["kb_stats"]) == KEY_S)
	_check("未知 id 不进入", not bad.has("ghost"))
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_keybind.tscn`
Expected: `KeybindModel` 未定义 → 解析报错/非 0 退出。

- [ ] **Step 3: 写实现**

创建 `scripts/core/keybind_model.gd`：

```gdscript
class_name KeybindModel
extends RefCounted
## 按键映射纯函数模型（headless 可测，无节点/网络/InputMap 依赖）。
## 只覆盖界面/展示类动作；游戏操作键列为保留键，不可绑定。

const ERR_RESERVED := "reserved"
const ERR_UNKNOWN := "unknown_action"

## 有序动作表（id / label / desc / default）。default 用 Godot Key 常量。
const ACTIONS := [
	{"id": "kb_manual",   "label": "手册",     "desc": "开/关 手册页",            "default": KEY_TAB},
	{"id": "kb_stats",    "label": "Stats",    "desc": "开/关 弃牌堆 Stats 页",   "default": KEY_S},
	{"id": "kb_keymap",   "label": "按键映射", "desc": "开/关 按键映射页",        "default": KEY_K},
	{"id": "kb_talk",     "label": "说话",     "desc": "按住/切换 说话（嘴开合）", "default": KEY_M},
	{"id": "kb_zoom",     "label": "放大",     "desc": "按住 拉近视场（放大）",    "default": KEY_META},
	{"id": "kb_toggle3d", "label": "切换 3D",  "desc": "在 2D 与 3D 桌面间切换",  "default": KEY_V},
]
## 保留键：不可被界面动作绑定（游戏操作 / 系统 / 修饰键）。
## KEY_ALT 为 kb_zoom 的固定第二键，故列入保留。
const RESERVED := [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_F10, KEY_ALT]

static func defaults() -> Dictionary:
	var out := {}
	for a in ACTIONS:
		out[str(a["id"])] = int(a["default"])
	return out

static func action_ids() -> Array:
	var out: Array = []
	for a in ACTIONS:
		out.append(str(a["id"]))
	return out

static func action_def(id: String) -> Dictionary:
	for a in ACTIONS:
		if str(a["id"]) == id:
			return a
	return {}

static func resolve(map: Dictionary, keycode: int) -> String:
	for id in map:
		if int(map[id]) == keycode:
			return str(id)
	return ""

## 重绑：未知动作/保留键拒绝；与已占用键冲突则**自动交换**。
## 返回 {ok, error, map, swapped}；map 为新字典，不就地改入参。
static func rebind(map: Dictionary, id: String, keycode: int) -> Dictionary:
	if not defaults().has(id):
		return {"ok": false, "error": ERR_UNKNOWN, "map": map, "swapped": ""}
	if keycode in RESERVED:
		return {"ok": false, "error": ERR_RESERVED, "map": map, "swapped": ""}
	var out := map.duplicate()
	var old_key := int(map.get(id, -1))
	var swapped := ""
	for other in out.keys():
		if str(other) != id and int(out[other]) == keycode:
			swapped = str(other)
			break
	if swapped != "":
		out[swapped] = old_key
	out[id] = keycode
	return {"ok": true, "error": "", "map": out, "swapped": swapped}

static func to_dict(map: Dictionary) -> Dictionary:
	var out := {}
	for id in map:
		out[str(id)] = int(map[id])
	return out

## 校验：未知 id 丢弃、缺失补默认、非法（保留键）值回退默认。
static func from_dict(d: Dictionary) -> Dictionary:
	var out := defaults()
	for id in out.keys():
		if d.has(id):
			var k := int(d[id])
			if not (k in RESERVED):
				out[id] = k
	return out
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_keybind.tscn`
Expected: `=== KEYBIND RESULT: 18/18 passed ===`，退出码 0。

- [ ] **Step 5: 编译检查 + 提交**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
git add scripts/core/keybind_model.gd scripts/core/keybind_model.gd.uid tests/verify_keybind.gd tests/verify_keybind.gd.uid tests/verify_keybind.tscn
git commit -m "feat: KeybindModel 按键映射纯函数模型 + headless 测试"
```

---

### Task 2: `KeybindStore` 本地持久化薄壳

**Files:**
- Create: `scripts/core/keybind_store.gd`
- Modify: `tests/verify_keybind.gd`（`_run()` 追加 `_test_store()`）

**Interfaces:**
- Consumes: `KeybindModel`（Task 1）。
- Produces: `class_name KeybindStore extends RefCounted`；`const DEFAULT_PATH` / `SECTION` / `VERSION`；`_init(p := DEFAULT_PATH)`；`map: Dictionary`；`load()`、`save()`、`key_of(id) -> int`、`action_for(keycode) -> String`、`apply(new_map) -> void`（不落盘）、`reset_to_defaults() -> void`。

- [ ] **Step 1: 写失败测试**

在 `tests/verify_keybind.gd` 的 `_run()` 改为：

```gdscript
func _run() -> void:
	_test_model()
	_test_store()
```

追加：

```gdscript
func _test_store() -> void:
	var p := "user://test_keybinds.cfg"
	# 清理上一轮残留
	DirAccess.remove_absolute(p)
	var store := KeybindStore.new(p)
	store.load()
	_check("缺文件→默认", int(store.key_of("kb_manual")) == KEY_TAB)
	_check("action_for 默认", store.action_for(KEY_TAB) == "kb_manual")
	var r: Dictionary = KeybindModel.rebind(store.map, "kb_stats", KEY_T)
	store.apply(r["map"])
	store.save()
	var store2 := KeybindStore.new(p)
	store2.load()
	_check("save/load 持久化", int(store2.key_of("kb_stats")) == KEY_T)
	_check("load 后 action_for", store2.action_for(KEY_T) == "kb_stats")
	# apply 不落盘：改内存后未 save，重新 load 应读到旧值
	store2.apply(KeybindModel.defaults())
	var store3 := KeybindStore.new(p)
	store3.load()
	_check("apply 不落盘", int(store3.key_of("kb_stats")) == KEY_T)
	DirAccess.remove_absolute(p)
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_keybind.tscn`
Expected: `KeybindStore` 未定义 → FAIL/解析错误。

- [ ] **Step 3: 写实现**

创建 `scripts/core/keybind_store.gd`：

```gdscript
class_name KeybindStore
extends RefCounted
## 按键映射本地持久化薄壳：ConfigFile 读写 user://（仅本机当前用户，不联网）。
## 路径可注入（测试用），未来接入账户只需换 path/profile。

const DEFAULT_PATH := "user://keybinds.cfg"
const SECTION := "keybinds"
const VERSION := 1

var path := DEFAULT_PATH
var map: Dictionary = {}

func _init(p := DEFAULT_PATH) -> void:
	path = p
	map = KeybindModel.defaults()

## 读文件；缺文件 / 版本不符 / 解析失败 → 回退默认（无副作用）。
func load() -> void:
	map = KeybindModel.defaults()
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	if int(cf.get_value(SECTION, "version", 0)) != VERSION:
		return
	var raw := {}
	for id in KeybindModel.action_ids():
		if cf.has_section_key(SECTION, id):
			raw[id] = int(cf.get_value(SECTION, id))
	map = KeybindModel.from_dict(raw)

## 写文件（含 version；预留 profile 键，未来按账户分文件）。
func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "version", VERSION)
	cf.set_value(SECTION, "profile", "")
	for id in map.keys():
		cf.set_value(SECTION, str(id), int(map[id]))
	cf.save(path)

func key_of(id: String) -> int:
	return int(map.get(id, -1))

func action_for(keycode: int) -> String:
	return KeybindModel.resolve(map, keycode)

## 只改内存（不落盘）；由调用方决定何时 save。
func apply(new_map: Dictionary) -> void:
	map = new_map.duplicate()

func reset_to_defaults() -> void:
	map = KeybindModel.defaults()
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_keybind.tscn`
Expected: `=== KEYBIND RESULT: 23/23 passed ===`。

- [ ] **Step 5: 提交**

```bash
git add scripts/core/keybind_store.gd scripts/core/keybind_store.gd.uid tests/verify_keybind.gd
git commit -m "feat: KeybindStore 本地持久化薄壳（user://，可注入路径）"
```

---

### Task 3: `KeymapBoard` 页内容（键行 + 捕获态 + 保存）

**Files:**
- Create: `scripts/ui/keymap_board.gd`
- Modify: `tests/verify_keybind.gd`（`_run()` 追加 `await _test_board()`）

**Interfaces:**
- Consumes: `KeybindModel`（Task 1）；`KeyHintPanel.chip_style_box()` / `chip_text_color()`（既有静态方法，不改）。
- Produces: `class_name KeymapBoard extends Control`；`signal save_requested(new_map: Dictionary)` / `signal changed()`；`const CAPTURE_TEXT` / `RESERVED_TEXT`；`setup(current_map, reserved := [])`、`begin_capture(id)`、`capture_key(keycode)`、`cancel_capture()`、`capturing() -> String`、`pending_map() -> Dictionary`、`has_changes() -> bool`、`commit()`、`set_save_enabled(on)`、`refresh_chips()`；访问器 `row_count()`、`chip_text(id)`、`status_text(id)`；可交互控件带 `set_meta("board_interactive", true)`。

- [ ] **Step 1: 写失败测试**

在 `tests/verify_keybind.gd` 的 `_run()` 改为：

```gdscript
func _run() -> void:
	_test_model()
	_test_store()
	await _test_board()
```

追加：

```gdscript
func _test_board() -> void:
	var board := KeymapBoard.new()
	add_child(board)
	await get_tree().process_frame
	board.setup(KeybindModel.defaults(), KeybindModel.RESERVED)
	await get_tree().process_frame
	_check("行数=动作数", board.row_count() == KeybindModel.action_ids().size())
	_check("chip 显示 Tab", board.chip_text("kb_manual") == OS.get_keycode_string(KEY_TAB))
	_check("初始无改动", not board.has_changes())
	# 捕获
	board.begin_capture("kb_stats")
	_check("进入捕获", board.capturing() == "kb_stats")
	_check("捕获态 chip 文案", board.chip_text("kb_stats") == KeymapBoard.CAPTURE_TEXT)
	board.capture_key(KEY_T)
	_check("捕获后 chip=T", board.chip_text("kb_stats") == OS.get_keycode_string(KEY_T))
	_check("结束捕获", board.capturing() == "")
	_check("有待保存改动", board.has_changes())
	# 保留键
	board.begin_capture("kb_talk")
	board.capture_key(KEY_SPACE)
	_check("保留键留在捕获态", board.capturing() == "kb_talk")
	_check("保留键提示", board.status_text("kb_talk") == KeymapBoard.RESERVED_TEXT)
	board.cancel_capture()
	_check("取消捕获", board.capturing() == "" and board.chip_text("kb_talk") == OS.get_keycode_string(KEY_M))
	# commit 后无改动
	board.commit()
	_check("commit 后无改动", not board.has_changes())
	board.queue_free()
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_keybind.tscn`
Expected: `KeymapBoard` 未定义 → FAIL/解析错误。

- [ ] **Step 3: 写实现**

创建 `scripts/ui/keymap_board.gd`：

```gdscript
class_name KeymapBoard
extends Control
## 按键映射页内容（3D 全息看板第三页）：列可重绑动作 + 当前键 + 保存按钮。
## 纯展示 + 本地待保存状态；真正落盘由 ManualPanel/main 驱动。
## 可交互控件（键 chip / 保存按钮）带 meta("board_interactive")，供 Board3d 部分穿透判定。

signal save_requested(new_map: Dictionary)
signal changed()

const CAPTURE_TEXT := "按键中…"
const RESERVED_TEXT := "保留键，不可绑定"
const ERR_COLOR := Color(0.82, 0.24, 0.24)

var _pending: Dictionary = {}
var _baseline: Dictionary = {}
var _capturing := ""
var _chip_btns := {}     # id -> Button
var _status := {}        # id -> Label
var _save_btn: Button = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	changed.connect(_on_changed)

func _on_changed() -> void:
	set_save_enabled(has_changes())

## 用当前映射重建所有行 + 保存按钮（打开页时调用；同时重置待保存状态）。
func setup(current_map: Dictionary, _reserved: Array = []) -> void:
	_baseline = current_map.duplicate()
	_pending = current_map.duplicate()
	_capturing = ""
	_chip_btns.clear()
	_status.clear()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.name = "KeymapVBox"
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	for id in KeybindModel.action_ids():
		vb.add_child(_make_row(str(id), KeybindModel.action_def(str(id))))
	_save_btn = Button.new()
	_save_btn.name = "SaveButton"
	_save_btn.text = "保存"
	_save_btn.custom_minimum_size = Vector2(0, 40)
	_save_btn.add_theme_font_size_override("font_size", 20)
	_save_btn.set_meta("board_interactive", true)
	_save_btn.disabled = true
	_save_btn.pressed.connect(func(): save_requested.emit(pending_map()))
	vb.add_child(_save_btn)
	custom_minimum_size = vb.get_combined_minimum_size()

func _make_row(id: String, def: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row_" + id
	row.add_theme_constant_override("separation", 10)
	var l := Label.new()
	l.text = str(def.get("label", id))
	l.custom_minimum_size = Vector2(96, 0)
	l.add_theme_font_size_override("font_size", 18)
	row.add_child(l)
	var d := Label.new()
	d.text = str(def.get("desc", ""))
	d.custom_minimum_size = Vector2(280, 0)
	d.add_theme_font_size_override("font_size", 15)
	row.add_child(d)
	var chip := Button.new()
	chip.name = "Chip"
	chip.text = OS.get_keycode_string(int(_pending.get(id, 0)))
	chip.custom_minimum_size = Vector2(112, 32)
	chip.add_theme_font_size_override("font_size", 16)
	chip.set_meta("board_interactive", true)
	for st_name in ["normal", "hover", "pressed", "disabled"]:
		chip.add_theme_stylebox_override(st_name, KeyHintPanel.chip_style_box())
	chip.add_theme_color_override("font_color", KeyHintPanel.chip_text_color())
	chip.pressed.connect(begin_capture.bind(id))
	row.add_child(chip)
	var status := Label.new()
	status.name = "Status"
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", ERR_COLOR)
	row.add_child(status)
	_chip_btns[id] = chip
	_status[id] = status
	return row

func begin_capture(id: String) -> void:
	if _capturing != "":
		cancel_capture()
	_capturing = id
	_chip_btns[id].text = CAPTURE_TEXT

## 由 main 捕获下一个 keydown 后调用。
func capture_key(keycode: int) -> void:
	if _capturing == "":
		return
	var id := _capturing
	var res: Dictionary = KeybindModel.rebind(_pending, id, keycode)
	if not bool(res.get("ok", false)):
		_status[id].text = RESERVED_TEXT if str(res.get("error", "")) == KeybindModel.ERR_RESERVED else "无效"
		return
	_pending = res.get("map")
	_capturing = ""
	_status[id].text = ""
	refresh_chips()
	changed.emit()

func cancel_capture() -> void:
	if _capturing == "":
		return
	var id := _capturing
	_capturing = ""
	_status[id].text = ""
	_refresh_chip(id)

func capturing() -> String:
	return _capturing

func pending_map() -> Dictionary:
	return _pending.duplicate()

func has_changes() -> bool:
	return _pending != _baseline

func commit() -> void:
	_baseline = _pending.duplicate()

func set_save_enabled(on: bool) -> void:
	if _save_btn != null:
		_save_btn.disabled = not on

func refresh_chips() -> void:
	for id in _chip_btns.keys():
		_refresh_chip(str(id))

func _refresh_chip(id: String) -> void:
	if _chip_btns.has(id):
		_chip_btns[id].text = CAPTURE_TEXT if id == _capturing else OS.get_keycode_string(int(_pending.get(id, 0)))

## 测试访问器。
func row_count() -> int:
	return _chip_btns.size()

func chip_text(id: String) -> String:
	return _chip_btns[id].text if _chip_btns.has(id) else ""

func status_text(id: String) -> String:
	return _status[id].text if _status.has(id) else ""
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_keybind.tscn`
Expected: `=== KEYBIND RESULT: 35/35 passed ===`。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/keymap_board.gd scripts/ui/keymap_board.gd.uid tests/verify_keybind.gd
git commit -m "feat: KeymapBoard 按键映射页内容（键行 + 捕获 + 保存）"
```

---

### Task 4: `ManualPanel` 第三页签 + 保存确认浮层

**Files:**
- Modify: `scripts/ui/manual_panel.gd`
- Modify: `tests/verify_manual.gd`（追加按键页/确认浮层断言）

**Interfaces:**
- Consumes: `KeymapBoard`（Task 3）。
- Produces: `ManualPanel.TAB_KEYS := 2`；`signal save_confirmed(new_map: Dictionary)`；`setup_keymap(current_map, reserved)`、`keymap_board() -> KeymapBoard`、`open_confirm()`、`confirm_visible() -> bool`、`on_confirm_save()`、`on_confirm_cancel()`、`capturing()`、`capture_key(keycode)`、`cancel_capture()`；页签按钮带 `set_meta("board_interactive", true)`。

- [ ] **Step 1: 写失败测试**

在 `tests/verify_manual.gd` 的 `_run()` 中，`main_node._toggle_manual(ManualPanel.TAB_STATS)` 关闭 Stats 之后（原 116 行 `_check("再按 S 关闭 Stats"...)` 之后）插入：

```gdscript
	# K：打开按键映射页（第三页签）
	main_node._toggle_manual(ManualPanel.TAB_KEYS)
	await get_tree().process_frame
	_check("K 打开按键页", main_node.manual_panel != null and main_node.manual_panel.current_tab() == ManualPanel.TAB_KEYS)
	var km = main_node.manual_panel.keymap_board()
	_check("按键板存在且可见", km != null and km.visible)
	_check("按键页行数=动作数", km != null and km.row_count() == KeybindModel.action_ids().size())
	_check("按键页时手册网格隐藏", not (main_node.manual_panel.get_node("Center/Panel/VBox/Grid") as Control).visible)
	var tab_manual: Button = main_node.manual_panel.get_node("Center/Panel/VBox/Tabs").get_child(0)
	_check("页签带 board_interactive", tab_manual.has_meta("board_interactive") and bool(tab_manual.get_meta("board_interactive")))
	# 保存确认浮层
	_check("初始无确认浮层", not main_node.manual_panel.confirm_visible())
	main_node.manual_panel.open_confirm()
	_check("打开确认浮层", main_node.manual_panel.confirm_visible())
	main_node.manual_panel.on_confirm_cancel()
	_check("取消关闭浮层", not main_node.manual_panel.confirm_visible())
	main_node._toggle_manual(ManualPanel.TAB_KEYS)
	await get_tree().process_frame
	_check("再按 K 关闭按键页", main_node.manual_panel == null)
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_manual.tscn`
Expected: `TAB_KEYS` / `KeymapBoard` 未定义 → FAIL/解析错误。

- [ ] **Step 3: 改 `manual_panel.gd`**

在 `scripts/ui/manual_panel.gd` 顶部常量区（`const TAB_STATS := 1` 之后）追加：

```gdscript
const TAB_KEYS := 2
```

在 `var _stats: StatsBoard` 之后追加：

```gdscript
signal save_confirmed(new_map: Dictionary)
var _keymap: KeymapBoard
var _tab_keys: Button
var _confirm: Control
```

在 `_ready()` 的 `_build_stats()` 之后追加：

```gdscript
	_build_keymap()
	_build_confirm()
```

把 `_build_tabs()` 中创建 `_tab_stats` 的片段（`bar.add_child(_tab_stats)` 之后）改为：

```gdscript
	_tab_keys = _tab_button("按键")
	_tab_keys.pressed.connect(func(): set_tab(TAB_KEYS))
	bar.add_child(_tab_keys)
```

并把 `_build_tabs()` 里的提示文案改为：

```gdscript
	hint.text = "Tab 手册 / S Stats / K 按键 / Esc 关闭"
```

在 `_tab_button` 内、`return btn` 之前加一行：

```gdscript
	btn.set_meta("board_interactive", true)
```

新增：

```gdscript
func _build_keymap() -> void:
	_keymap = KeymapBoard.new()
	_keymap.name = "Keymap"
	var vbox: VBoxContainer = get_node("Center/Panel/VBox")
	vbox.add_child(_keymap)
	_keymap.visible = false
	_keymap.save_requested.connect(func(_m): open_confirm())

func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.name = "ConfirmOverlay"
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.visible = false
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.set_meta("board_interactive", true)
	_confirm.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(center)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.90, 0.92, 0.96, 0.97)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(24)
	style.border_color = Color(1, 1, 1, 0.6)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)
	var lbl := Label.new()
	lbl.text = "确认保存当前按键映射？"
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", HEADER)
	vb.add_child(lbl)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	var ok := Button.new()
	ok.name = "ConfirmOk"
	ok.text = "确认"
	ok.custom_minimum_size = Vector2(120, 44)
	ok.add_theme_font_size_override("font_size", 20)
	ok.set_meta("board_interactive", true)
	ok.pressed.connect(on_confirm_save)
	hb.add_child(ok)
	var cancel := Button.new()
	cancel.name = "ConfirmCancel"
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(120, 44)
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.set_meta("board_interactive", true)
	cancel.pressed.connect(on_confirm_cancel)
	hb.add_child(cancel)
	add_child(_confirm)

func setup_keymap(current_map: Dictionary, reserved: Array) -> void:
	if _keymap != null:
		_keymap.setup(current_map, reserved)

func keymap_board() -> KeymapBoard:
	return _keymap

func open_confirm() -> void:
	if _confirm != null:
		_confirm.visible = true

func confirm_visible() -> bool:
	return _confirm != null and _confirm.visible

func on_confirm_save() -> void:
	if _confirm != null:
		_confirm.visible = false
	if _keymap != null:
		_keymap.commit()
		_keymap.set_save_enabled(false)
		save_confirmed.emit(_keymap.pending_map())

func on_confirm_cancel() -> void:
	if _confirm != null:
		_confirm.visible = false

func capturing() -> String:
	return _keymap.capturing() if _keymap != null else ""

func capture_key(keycode: int) -> void:
	if _keymap != null:
		_keymap.capture_key(keycode)

func cancel_capture() -> void:
	if _keymap != null:
		_keymap.cancel_capture()
```

把 `set_tab()` 改为支持第三页：

```gdscript
func set_tab(index: int) -> void:
	_tab = index if index in [TAB_MANUAL, TAB_STATS, TAB_KEYS] else TAB_MANUAL
	var title: Label = get_node("Center/Panel/VBox/Title")
	if _grid != null:
		_grid.visible = _tab == TAB_MANUAL
	if _stats != null:
		_stats.visible = _tab == TAB_STATS
	if _keymap != null:
		_keymap.visible = _tab == TAB_KEYS
	if title != null:
		title.text = "Stats · 弃牌堆" if _tab == TAB_STATS else ("按键映射" if _tab == TAB_KEYS else "手册")
	if _tab_manual != null:
		_tab_manual.disabled = _tab == TAB_MANUAL
	if _tab_stats != null:
		_tab_stats.disabled = _tab == TAB_STATS
	if _tab_keys != null:
		_tab_keys.disabled = _tab == TAB_KEYS
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_manual.tscn`
Expected: 无 `[FAIL]`（新增 9 条 + 既有断言全绿）。

- [ ] **Step 5: 回归（手册既有断言不破）**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_manual.tscn`
Expected: 无 `[FAIL]`。

- [ ] **Step 6: 提交**

```bash
git add scripts/ui/manual_panel.gd tests/verify_manual.gd scripts/ui/keymap_board.gd.uid
git commit -m "feat: ManualPanel 第三页签「按键」+ 保存确认浮层"
```

---

### Task 5: `Board3d.interactive_at` 部分穿透判定

**Files:**
- Modify: `scripts/ui/board3d.gd`（末尾追加方法）
- Modify: `tests/verify_board3d.gd`（`_run()` 追加 `await _test_interactive_at()`）

**Interfaces:**
- Produces: `Board3d.interactive_at(coord: Vector2i) -> bool`；私有 `_interactive_hit(node, p) -> bool`。

- [ ] **Step 1: 写失败测试**

在 `tests/verify_board3d.gd` 的 `_run()` 中 `await _test_main_routing()` 之后追加 `await _test_interactive_at()`，并新增：

```gdscript
## 手册页部分穿透：仅带 meta("board_interactive") 的控件处才"接管点击"。
func _test_interactive_at() -> void:
	var b := Board3d.new()
	add_child(b)
	await get_tree().process_frame
	var panel := PanelContainer.new()
	var vb := VBoxContainer.new()
	var lbl := Label.new()
	lbl.name = "Lbl"
	lbl.text = "read only"
	lbl.custom_minimum_size = Vector2(120, 30)
	vb.add_child(lbl)
	var btn := Button.new()
	btn.name = "Btn"
	btn.text = "x"
	btn.custom_minimum_size = Vector2(80, 40)
	btn.set_meta("board_interactive", true)
	vb.add_child(btn)
	panel.add_child(vb)
	b.mount_panel(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	var br: Rect2 = btn.get_global_rect()
	_check("命中可交互控件", b.interactive_at(Vector2i(br.position + br.size * 0.5)))
	var lr: Rect2 = lbl.get_global_rect()
	_check("无 meta 标签不命中", not b.interactive_at(Vector2i(lr.position + Vector2(2, 2))))
	_check("空白区域不命中", not b.interactive_at(Vector2i(0, 0)))
	b.queue_free()
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: `interactive_at` 未定义 → FAIL/解析错误。

- [ ] **Step 3: 写实现**

在 `scripts/ui/board3d.gd` 末尾（`push_key` 之后）追加：

```gdscript
## 该视口像素坐标是否位于某个带 meta("board_interactive") 的可见控件矩形内。
## 用于手册/Stats/按键页的"部分穿透"：命中可交互控件才接管点击，其余穿透到牌桌。
func interactive_at(coord: Vector2i) -> bool:
	_prune_panels()
	var p := Vector2(coord)
	for panel in _panels:
		if _interactive_hit(panel, p):
			return true
	return false

func _interactive_hit(node: Node, p: Vector2) -> bool:
	if node is Control:
		var c := node as Control
		if c.visible and bool(c.get_meta("board_interactive", false)) and c.get_global_rect().has_point(p):
			return true
	for child in node.get_children():
		if _interactive_hit(child, p):
			return true
	return false
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: 现有断言 + 新增 3 条全绿。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/board3d.gd tests/verify_board3d.gd
git commit -m "feat: Board3d.interactive_at 供手册页部分穿透判定"
```

---

### Task 6: `main.gd` 接线（keybinds + K 键 + 捕获转发 + 保存落盘 + 部分穿透）

**Files:**
- Modify: `scripts/ui/main.gd`
- Modify: `tests/verify_manual.gd`（追加 main 集成断言）

**Interfaces:**
- Consumes: `KeybindStore`（Task 2）、`ManualPanel.TAB_KEYS` / `setup_keymap` / `save_confirmed` / `capturing` / `capture_key` / `cancel_capture`（Task 4）、`Board3d.interactive_at`（Task 5）、`KeybindModel`（Task 1）。
- Produces: `main.keybinds: KeybindStore`；`main._on_keymap_saved(new_map)`；`_board_hit()` 部分穿透；`_input` 界面键改走 `keybinds.action_for`。

- [ ] **Step 1: 写失败测试**

在 `tests/verify_manual.gd` 的 `_run()` 中，Task 4 插入的块之后（`_check("再按 K 关闭按键页"...)` 之后）插入：

```gdscript
	# main 集成：keybinds 存在；K 经 keybinds 打开按键页；保存落盘
	_check("main 持有 keybinds", main_node.keybinds != null)
	main_node.keybinds.reset_to_defaults()   # 防开发者本机 keybinds.cfg 干扰断言
	main_node._toggle_manual(ManualPanel.TAB_KEYS)
	await get_tree().process_frame
	_check("K 键动作解析为 kb_keymap", main_node.keybinds.action_for(KEY_K) == "kb_keymap")
	var km2 = main_node.manual_panel.keymap_board()
	km2.begin_capture("kb_stats")
	km2.capture_key(KEY_T)
	main_node.manual_panel.open_confirm()
	main_node.manual_panel.on_confirm_save()
	await get_tree().process_frame
	_check("确认保存后 kb_stats=T 已生效", int(main_node.keybinds.key_of("kb_stats")) == KEY_T)
	# 还原默认，避免污染后续
	main_node.keybinds.reset_to_defaults()
	main_node._toggle_manual(ManualPanel.TAB_KEYS)
	await get_tree().process_frame
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_manual.tscn`
Expected: `main` 无 `keybinds` → FAIL。

- [ ] **Step 3: 加变量 + `_ready` 加载**

在 `scripts/ui/main.gd` 变量区（`var manual_panel: Control = null` 之后，约 742 行）追加：

```gdscript
var keybinds := KeybindStore.new()
```

在 `_ready()` 中 `UITheme.switch_theme(...)` 之后追加：

```gdscript
	keybinds.load()
```

- [ ] **Step 4: `_toggle_manual` / `_open_manual` 注入 keymap + 连接保存**

把 `scripts/ui/main.gd` 的 `_toggle_manual` 改为：

```gdscript
func _toggle_manual(tab := ManualPanel.TAB_MANUAL) -> void:
	if manual_panel != null and is_instance_valid(manual_panel):
		if manual_panel.current_tab() == tab:
			_close_manual()
		else:
			manual_panel.setup_keymap(keybinds.map, KeybindModel.RESERVED)
			manual_panel.set_tab(tab)
			manual_panel.setup_stats(latest_state.get("discard_history", []))
	else:
		_open_manual(tab)
```

把 `_open_manual` 改为：

```gdscript
func _open_manual(tab := ManualPanel.TAB_MANUAL) -> void:
	if manual_panel != null and is_instance_valid(manual_panel):
		manual_panel.setup_keymap(keybinds.map, KeybindModel.RESERVED)
		manual_panel.set_tab(tab)
		manual_panel.setup_stats(latest_state.get("discard_history", []))
		return
	var panel := ManualPanelScript.instantiate()
	panel.name = "ManualPanel"
	panel.z_index = 92
	_mount_modal(panel)
	manual_panel = panel
	manual_panel.save_confirmed.connect(_on_keymap_saved)
	manual_panel.setup_keymap(keybinds.map, KeybindModel.RESERVED)
	manual_panel.set_tab(tab)
	manual_panel.setup_stats(latest_state.get("discard_history", []))
```

在 `_close_manual` 之后新增：

```gdscript
func _on_keymap_saved(new_map: Dictionary) -> void:
	keybinds.apply(new_map)
	keybinds.save()
	_show_toast("按键已保存")
```

- [ ] **Step 5: `_input` 改走 keybinds + 捕获转发 + K 键**

把 `scripts/ui/main.gd` 的 `func _input(event: InputEvent) -> void:` 整个函数体替换为：

```gdscript
func _input(event: InputEvent) -> void:
	if not _table3d_active:
		return
	# 按键捕获：正在重绑时拦截键盘/点击，不给游戏与牌桌
	if manual_panel != null and is_instance_valid(manual_panel) and manual_panel.capturing() != "":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				manual_panel.cancel_capture()
			else:
				manual_panel.capture_key(event.keycode)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed:
			get_viewport().set_input_as_handled()
			return
	var board_panel := _board_has_panel()
	var act := keybinds.action_for(event.keycode) if event is InputEventKey else ""
	# 按住 Command/Alt（或自定义 kb_zoom）：拉近视场（放大）；松开恢复。不标记 handled。
	if event is InputEventKey and not event.echo and (act == "kb_zoom" or event.keycode == KEY_ALT):
		if table3d != null and is_instance_valid(table3d):
			table3d.camera.set_zoom(event.pressed)
	if event is InputEventKey and event.pressed and not event.echo:
		# F10 固定别名 + kb_toggle3d：任何时候都可切回 2D
		if event.keycode == KEY_F10 or act == "kb_toggle3d":
			_set_table3d(false)
			get_viewport().set_input_as_handled()
			return
		if act == "kb_manual":
			_toggle_manual(ManualPanel.TAB_MANUAL)
			get_viewport().set_input_as_handled()
			return
		if act == "kb_stats":
			_toggle_manual(ManualPanel.TAB_STATS)
			get_viewport().set_input_as_handled()
			return
		if act == "kb_keymap":
			_toggle_manual(ManualPanel.TAB_KEYS)
			get_viewport().set_input_as_handled()
			return
		if act == "kb_talk":
			_talking_local = not _talking_local
			get_viewport().set_input_as_handled()
			return
		# 手册打开时 Esc 先关手册（优先于退出 3D）
		if event.keycode == KEY_ESCAPE and manual_panel != null and is_instance_valid(manual_panel):
			_close_manual()
			get_viewport().set_input_as_handled()
			return
		# 有模态面板时，Enter/Esc 交给面板；否则 Esc 退出 3D。
		if board_panel and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_ESCAPE):
			if board3d != null and is_instance_valid(board3d):
				board3d.push_key(event)
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

- [ ] **Step 6: `_board_hit` 部分穿透**

把 `scripts/ui/main.gd` 的 `func _board_hit() -> Dictionary:` 整个函数替换为：

```gdscript
func _board_hit() -> Dictionary:
	if table3d == null or not is_instance_valid(table3d):
		return {}
	var cam: Camera3D = table3d.camera.camera_node()
	for host in [board3d, hint3d]:
		if host != null and is_instance_valid(host) and host.visible:
			var c: Vector2i = host.hit_viewport_coord(cam)
			if c.x >= 0:
				# 手册/Stats/按键页：仅可交互控件（页签/按钮/键行）接管点击，其余穿透到牌桌
				if host == board3d and _manual_transparent() and not board3d.interactive_at(c):
					continue
				return {"host": host, "coord": c}
	return {}
```

- [ ] **Step 7: 运行测试，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_manual.tscn`
Expected: 全绿（无 `[FAIL]`）。

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: 全绿。

- [ ] **Step 8: 回归（3D 交互/换牌/看板）**

```bash
for t in verify_table3d verify_table3d_interaction verify_table3d_exchange verify_hint_hud verify_actions; do
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . "res://tests/$t.tscn" | tail -1
done
```
Expected: 每个都 PASS 且退出码 0。

- [ ] **Step 9: 提交**

```bash
git add scripts/ui/main.gd tests/verify_manual.gd
git commit -m "feat: main 接入按键映射（keybinds + K 键 + 捕获转发 + 保存落盘 + 手册页部分穿透）"
```

---

### Task 7: 文档更新 + 全量回归

**Files:**
- Modify: `docs/AI_AGENT_交接说明.md`（§2 基线追加一条）
- Modify: `docs/功能实现文档.md`（UI 文件表追加行）

**Interfaces:** 无代码接口变更。

- [ ] **Step 1: 更新交接说明**

在 `docs/AI_AGENT_交接说明.md` §2 基线末尾追加一条：

```markdown
- **按键映射页签 + 手册页部分穿透（分支 `agent/feature-uiboard2`，纯客户端展示层，规则/协议/快照零改动）**：手册面板新增第三页签「按键」（默认 **K** 打开），列出界面/展示类按键（Tab 手册 / S Stats / K 按键映射 / M 说话 / Command·Alt 放大 / V 切 3D）并可重绑——点键行进入捕获、按新键即改（冲突**自动交换**、**保留键**（空格/Enter/Esc/F10/Alt）拒绝），底部「保存」经**页内确认浮层**后落盘 `user://keybinds.cfg`（仅本机用户，预留 `profile` 供未来账户绑定）。键处理抽到纯函数 `KeybindModel`（`scripts/core/keybind_model.gd`）+ 薄壳 `KeybindStore`（`scripts/core/keybind_store.gd`，可注入路径）；页内容 `KeymapBoard`（`scripts/ui/keymap_board.gd`）。**手册/Stats/按键页打开时不再完全接管点击**：`Board3d.interactive_at` 只让带 `meta("board_interactive")` 的控件（页签/按钮/键行）接管，`main._board_hit` 对非交互处穿透到牌桌——可一边看手册一边点卡牌。测试 `verify_keybind`（新增）。
```

- [ ] **Step 2: 更新功能实现文档**

在 `docs/功能实现文档.md` 的 UI 文件表 `manual_panel.gd` 行之后追加：

```markdown
| `keybind_model.gd` / `keybind_store.gd` | **纯函数/薄壳**：界面按键动作表 + `resolve`/`rebind`（自动交换/保留键拒绝）/`from_dict` 回退；`user://keybinds.cfg` 读写（可注入路径，`scripts/core/`） |
| `keymap_board.gd` | 按键映射页内容（`KeymapBoard`：键行 + 捕获态 + 保存按钮；可交互控件带 `board_interactive` 标记） |
```

- [ ] **Step 3: 全量回归**

Run: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard2/tools/run_all_tests.sh --quick`
Expected: 全部 PASS。

```bash
for t in verify_keybind verify_manual verify_board3d verify_hint_hud verify_table3d verify_table3d_interaction verify_table3d_exchange verify_hint verify_j_swap verify_actions verify_protocol; do
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . "res://tests/$t.tscn" | tail -1
done
```

- [ ] **Step 4: `git diff` 确认边界**

Run: `git diff origin/main --stat`
Expected: 仅涉及 `scripts/core/keybind_model.gd`、`scripts/core/keybind_store.gd`、`scripts/ui/keymap_board.gd`、`scripts/ui/manual_panel.gd`、`scripts/ui/board3d.gd`、`scripts/ui/main.gd`、`tests/verify_keybind.*`、`tests/verify_manual.gd`、`tests/verify_board3d.gd`、`docs/*`；**无** `scripts/core` 既有子系统、`scripts/net/*`、`scenes/ui/table3d.tscn`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`、`key_hint_panel.gd`。

- [ ] **Step 5: 提交**

```bash
git add docs/AI_AGENT_交接说明.md docs/功能实现文档.md
git commit -m "doc: 记录按键映射页签 + 手册页部分穿透"
```

---

## Self-Review

**Spec coverage：**
- §2.1 `KeybindModel` → Task 1；§2.2 `KeybindStore` → Task 2；§2.3 `KeymapBoard` → Task 3；§2.4 `ManualPanel`（第三页签 + 确认浮层）→ Task 4；§2.5 `Board3d.interactive_at` → Task 5；§2.6 `main` 接线 → Task 6。
- §3 捕获与自动交换 → Task 1（模型）+ Task 3（捕获态）+ Task 6（main 捕获转发）。
- §4 保存与确认浮层（页内浮层、丢弃未保存、toast）→ Task 3/4/6。
- §5 页签点击 + 部分穿透（`board_interactive` 标记、`interactive_at`、`_board_hit` 小改、`_board_has_panel`/`_click_route` 不变）→ Task 3/4（标记）+ Task 5（判定）+ Task 6（路由）。
- §6 生命周期（打开时快照、关闭丢弃、即时生效）→ Task 6。
- §7 测试（`verify_keybind` 新增；`verify_manual`/`verify_board3d` 扩展）→ Task 1-6；§8 文件清单 → 全 Task；§9 账户绑定预留（`path`/`profile`）→ Task 2；§10 参数/保留键 → Task 1。**无缺口。**

**Placeholder scan：** 无 TBD/TODO；每个代码步骤给出完整文件内容或精确 old→new 片段与命令。

**Type consistency：** `KeybindModel` 的 `ACTIONS`/`RESERVED`/`defaults`/`resolve`/`rebind`（返回 `{ok,error,map,swapped}`）在 Task 1 定义，Task 2/3/6 一致使用；`KeybindStore` 的 `map`/`key_of`/`action_for`/`apply`/`load`/`save`/`reset_to_defaults`/`_init(path)` 在 Task 2 定义并在 Task 6 使用；`KeymapBoard` 的 `setup`/`begin_capture`/`capture_key`/`cancel_capture`/`capturing`/`pending_map`/`has_changes`/`commit`/`set_save_enabled`/`refresh_chips`/`row_count`/`chip_text`/`status_text` + `CAPTURE_TEXT`/`RESERVED_TEXT` 在 Task 3 定义，Task 4 经 `ManualPanel` 委托（`setup_keymap`/`keymap_board`/`capturing`/`capture_key`/`cancel_capture`/`on_confirm_save`/`on_confirm_cancel`/`open_confirm`/`confirm_visible`/`save_confirmed`）在 Task 4 定义并在 Task 6 使用；`Board3d.interactive_at` 在 Task 5 定义、Task 6 使用。命名一致。
