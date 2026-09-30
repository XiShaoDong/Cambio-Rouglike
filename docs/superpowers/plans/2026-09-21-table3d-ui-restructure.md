# 3D 对局 UI 重构 + ActionModel 抽取 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 抽取共享的 `ActionModel`（2D/3D 动作判定单一来源），并把 3D 玩家状态 UI 拆成「自己（屏幕右下）/其他玩家（头顶面板）」，Kongbaya 改为 3D 金色铃铛，pending 贴到抽牌堆上。

**Architecture:** 纯函数 `ActionModel` 提供动作与可用性判定；2D 控制区与 3D HUD/铃铛都消费它。`PlayerStatPanel` 是 2D 复用组件，自己放屏幕层、其他玩家经 `SubViewport → billboard Sprite3D` 贴到头顶。铃铛与 pending 是场景静态节点 + 少量代码驱动。

**Tech Stack:** Godot 4.6 GDScript、`PanelContainer`/`StyleBoxFlat`/`SubViewport`/`Sprite3D`/`SphereMesh`、headless `.tscn` 测试。

**Spec:** `docs/superpowers/specs/2026-09-21-table3d-ui-restructure-design.md`

## Global Constraints

- 分支 `feature/3d-table`。提交按 `feat:`/`fix:`/`test:`/`doc:`；新增 `.gd` 同时 `git add` 其 `.uid`。
- **不改** 规则 / 协议 / 快照 / 网络 / `core` / `hidden_info`；**2D 行为以现有为准**（仅内部改走 `ActionModel`）。
- 字段名保持：`players[].name/health/currency/count/eliminated/offline`、`viewer_id/current_player/phase/ready_count/q_decision/pending/run.relics`。
- 阶段数值：`INITIAL_PEEK=1`、`TURN_DRAW=2`、`TURN_DECISION=3`、`Q_DECISION=4`。
- 验证命令：
  - 编译：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5`
  - 单测：`... --headless --path . res://tests/<scene>.tscn`
  - 全量：`tools/run_all_tests.sh --quick`
  - 报 `Identifier "X" not declared` 时先 `--headless --path . --import`。
- 场景 `scenes/ui/table3d.tscn` 由开发者拥有：改结构要精确、最小。

---

## File Structure

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/action_model.gd`（新） | 纯函数：条件动作 / 铃铛可用 / Ready 文案与可用 |
| `scripts/ui/card_count_icon.gd`（新） | 程序化「卡牌数」图标 |
| `scripts/ui/player_stat_panel.gd`（新） | 状态面板（可选名字 + 生命/金钱/卡牌数） |
| `scripts/ui/game_view.gd`（改） | `_render_controls`/`render` 改走 `ActionModel`（行为不变） |
| `scripts/ui/main.gd`（改） | `_on_action` 统一分发；`_hud_buttons`；自己面板（右下角） |
| `scripts/ui/table3d_view.gd`（改） | 每席 `SubViewport`+`Sprite3D` 面板；铃铛拾取/发光；移除 NameLabel/StatLabel 用法 |
| `scenes/ui/table3d.tscn`（改） | 删 NameLabel/StatLabel；加 `Center/KongBell`；`Pending` 贴到牌堆 |
| `tests/verify_actions.gd`+`.tscn`（新） | ActionModel 断言 |
| `tests/verify_stat_panel.gd`+`.tscn`（新） | PlayerStatPanel 断言 |
| `tests/verify_table3d.gd`（改） | 面板 data 取代 NameLabel/StatLabel 断言 |
| `tests/verify_table3d_interaction.gd`（改） | 铃铛标记 / pending 尺寸断言 |
| `tools/run_all_tests.sh`（改） | 注册两个新测试 |

---

### Task 1: ActionModel 纯函数 + verify_actions

**Files:** Create `scripts/ui/action_model.gd`、`tests/verify_actions.gd`、`tests/verify_actions.tscn`；Modify `tools/run_all_tests.sh`

**Interfaces:**
- Produces: `ActionModel.Q_KEEP/Q_EXCHANGE/JOKER`；`conditional_actions(state)->Array[{action,text,enabled}]`；`kongbaya_available(state)->bool`；`ready_text(state, clicked)->String`；`ready_enabled(state, clicked)->bool`

- [ ] **Step 1: 写失败测试**

Create `tests/verify_actions.gd`:

```gdscript
extends Node
## headless 单元测试：ActionModel（2D/3D 共用的动作与可用性判定）。

var failures := 0
var checks := 0

func _ready() -> void:
	_run()
	print("=== ACTIONS RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	var q_ready := {"phase": 4, "viewer_id": 0, "current_player": 0, "q_decision": {"own_viewed": true}}
	var q_acts := ActionModel.conditional_actions(q_ready)
	_check("Q 两按钮", q_acts.size() == 2 and q_acts[0].action == ActionModel.Q_KEEP and q_acts[1].action == ActionModel.Q_EXCHANGE)
	_check("Q 未看自己牌无按钮", ActionModel.conditional_actions({"phase": 4, "viewer_id": 0, "current_player": 0, "q_decision": {"own_viewed": false}}).is_empty())
	_check("非当前玩家无动作", ActionModel.conditional_actions({"phase": 4, "viewer_id": 1, "current_player": 0, "q_decision": {"own_viewed": true}}).is_empty())
	var j_state := {"phase": 3, "viewer_id": 1, "current_player": 1, "pending": {"rank": "JOKER"}, "run": {"relics": {Relics.JOKER_TRANSFORM_ID: 1}}}
	var j_acts := ActionModel.conditional_actions(j_state)
	_check("Joker 变换按钮", j_acts.size() == 1 and j_acts[0].action == ActionModel.JOKER)
	_check("无遗物无 Joker 按钮", ActionModel.conditional_actions({"phase": 3, "viewer_id": 1, "current_player": 1, "pending": {"rank": "JOKER"}, "run": {"relics": {}}}).is_empty())
	_check("非 JOKER pending 无按钮", ActionModel.conditional_actions({"phase": 3, "viewer_id": 1, "current_player": 1, "pending": {"rank": "7"}, "run": {"relics": {Relics.JOKER_TRANSFORM_ID: 1}}}).is_empty())
	_check("空快照无动作", ActionModel.conditional_actions({}).is_empty())
	_check("kongbaya 可用", ActionModel.kongbaya_available({"phase": 2, "viewer_id": 0, "current_player": 0}))
	_check("kongbaya 非当前不可用", not ActionModel.kongbaya_available({"phase": 2, "viewer_id": 1, "current_player": 0}))
	_check("kongbaya 非抽牌阶段不可用", not ActionModel.kongbaya_available({"phase": 3, "viewer_id": 0, "current_player": 0}))
	_check("空快照 kongbaya 不可用", not ActionModel.kongbaya_available({}))
	var r := {"ready_count": 1, "players": [{}, {}]}
	_check("Ready 文案", ActionModel.ready_text(r, false) == "Ready（1/2）")
	_check("已准备文案", ActionModel.ready_text(r, true) == "已准备（1/2）")
	_check("Ready 可用", ActionModel.ready_enabled(r, false))
	_check("点击后不可用", not ActionModel.ready_enabled(r, true))
	_check("全员 ready 不可用", not ActionModel.ready_enabled({"ready_count": 2, "players": [{}, {}]}, false))
```

Create `tests/verify_actions.tscn`:

```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/verify_actions.gd" id="1"]
[node name="VerifyActions" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... --headless --path . res://tests/verify_actions.tscn`
Expected: `ActionModel` 未定义 / 编译错误。

- [ ] **Step 3: 写实现**

Create `scripts/ui/action_model.gd`:

```gdscript
class_name ActionModel
extends RefCounted
## 纯函数：由快照推导「条件动作按钮」与关键可用性；2D 控制区与 3D HUD/铃铛共用。
## 不依赖任何节点；阶段数值与 GameState.Phase 对齐。

const Q_KEEP := "q_keep"
const Q_EXCHANGE := "q_exchange"
const JOKER := "joker"

const PHASE_TURN_DRAW := 2
const PHASE_TURN_DECISION := 3
const PHASE_Q_DECISION := 4

## 条件动作按钮：需要时出现，点了触发 request_*。
## - Q_DECISION 且当前玩家且已看自己牌 → 「Q：不交换」「Q：交换」
## - TURN_DECISION 且当前玩家且 pending 为 JOKER 且持有 Joker 遗物 → 「变换 Joker」
static func conditional_actions(state: Dictionary) -> Array:
	var out: Array = []
	if state.is_empty():
		return out
	var phase := int(state.get("phase", 0))
	var viewer := int(state.get("viewer_id", 0))
	if viewer != int(state.get("current_player", -1)):
		return out
	if phase == PHASE_Q_DECISION:
		var qd: Dictionary = state.get("q_decision", {})
		if bool(qd.get("own_viewed", false)):
			out.append({"action": Q_KEEP, "text": "Q：不交换", "enabled": true})
			out.append({"action": Q_EXCHANGE, "text": "Q：交换", "enabled": true})
	elif phase == PHASE_TURN_DECISION:
		var pending: Dictionary = state.get("pending", {})
		if str(pending.get("rank", "")) == "JOKER":
			var run: Dictionary = state.get("run", {})
			if (run.get("relics", {}) as Dictionary).has(Relics.JOKER_TRANSFORM_ID):
				out.append({"action": JOKER, "text": "变换 Joker", "enabled": true})
	return out

## 铃铛（Kongbaya）可用：TURN_DRAW 且 viewer 为当前玩家。
static func kongbaya_available(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	return int(state.get("phase", 0)) == PHASE_TURN_DRAW \
		and int(state.get("viewer_id", 0)) == int(state.get("current_player", -1))

## Ready 按钮文案（2D 固定按钮与 3D HUD 共用）。
static func ready_text(state: Dictionary, ready_clicked: bool) -> String:
	var ready_count := int(state.get("ready_count", 0))
	var total: int = (state.get("players", []) as Array).size()
	if ready_clicked:
		return "已准备（%d/%d）" % [ready_count, total]
	return "Ready（%d/%d）" % [ready_count, total]

## Ready 按钮可用性。
static func ready_enabled(state: Dictionary, ready_clicked: bool) -> bool:
	var ready_count := int(state.get("ready_count", 0))
	var total: int = (state.get("players", []) as Array).size()
	return not ready_clicked and ready_count < total
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... --headless --path . res://tests/verify_actions.tscn`
Expected: `=== ACTIONS RESULT: 16/16 passed ===`，exit 0。

- [ ] **Step 5: 注册全量回归**

Modify `tools/run_all_tests.sh`，在 `run_single "table3d_mouse" ...` 之后加：

```bash
run_single "actions" res://tests/verify_actions.tscn
```

- [ ] **Step 6: 提交**

```bash
git add scripts/ui/action_model.gd scripts/ui/action_model.gd.uid tests/verify_actions.gd tests/verify_actions.gd.uid tests/verify_actions.tscn tools/run_all_tests.sh
git commit -m "feat: ActionModel 纯函数（2D/3D 共用动作判定）+ 测试"
```

---

### Task 2: 2D 控制区与 3D HUD 改走 ActionModel（行为不变）

**Files:** Modify `scripts/ui/game_view.gd`、`scripts/ui/main.gd`

**Interfaces:**
- Consumes: `ActionModel.*`
- Produces: `main._on_action(action: String) -> void`（原 `_on_table3d_hud` 更名并共用）、`main._hud_buttons() -> Array`

- [ ] **Step 1: main 统一分发 + HUD 列表**

Modify `scripts/ui/main.gd`：
1. 把 `func _on_table3d_hud(action: String) -> void:` 更名为 `func _on_action(action: String) -> void:`（函数体不变）。
2. 把 `_table3d_click()` 里 `"hud": _on_table3d_hud(str(pick.get("action", "")))` 改为 `"hud": _on_action(str(pick.get("action", "")))`。
3. 把 `func _table3d_hud_buttons() -> Array:` 整体替换为：

```gdscript
## 3D 操作面板按钮（Ready + 条件动作；Kongbaya 由 3D 铃铛负责，不在面板里）。
func _hud_buttons() -> Array:
	var out: Array = []
	if int(latest_state.get("phase", PHASE_LOBBY)) == PHASE_INITIAL_PEEK:
		out.append({"text": ActionModel.ready_text(latest_state, game_view._ready_clicked),
			"action": "ready",
			"enabled": ActionModel.ready_enabled(latest_state, game_view._ready_clicked)})
	out.append_array(ActionModel.conditional_actions(latest_state))
	return out
```
4. 把两处 `table3d.set_hud_buttons(_table3d_hud_buttons())` 改为 `table3d.set_hud_buttons(_hud_buttons())`。

- [ ] **Step 2: game_view 控制区改走 ActionModel**

Modify `scripts/ui/game_view.gd` 的 `_render_controls`：删除 `if phase == PHASE_Q_DECISION ...` 与 `elif phase == PHASE_TURN_DECISION ...` 两个分支（保留 suspended 处理与 GAME_OVER 摘要），改为：

```gdscript
	for entry in ActionModel.conditional_actions(main.latest_state):
		var action := str(entry.get("action", ""))
		if action == ActionModel.Q_KEEP:
			main.interaction.action_mode = ""
		var btn: Button = main._button(str(entry.get("text", "")))
		btn.disabled = not bool(entry.get("enabled", true))
		btn.pressed.connect(main._on_action.bind(action))
		main._hint_actions.add_child(btn)
```

Modify `game_view.render()` 的 Ready/铃铛判定（保持可见性逻辑不变）：

```gdscript
		if phase == PHASE_INITIAL_PEEK:
			main.ready_button.visible = true
			main.ready_button.disabled = not ActionModel.ready_enabled(state, _ready_clicked)
			main.ready_button.text = ActionModel.ready_text(state, _ready_clicked)
		else:
			main.ready_button.visible = false
			_ready_clicked = false
```
并把 `main.bell_button.disabled = not (phase == PHASE_TURN_DRAW and is_current)` 改为：

```gdscript
	main.bell_button.disabled = not ActionModel.kongbaya_available(state)
```
删除 `render()` 开头已不再使用的 `var total_players: int = state.players.size()`。

- [ ] **Step 3: 编译 + 回归**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
... --headless --path . res://tests/verify_actions.tscn
tools/run_all_tests.sh --quick
```
Expected: 无脚本错误；`actions` 15/15；全量 0 败。

> 注意：2D 里 Q「交换」按钮文案由 `Q：交换（两张已查看的牌）` 变为 `Q：交换`（与 ActionModel/3D 对齐，已获批准）。

- [ ] **Step 4: 提交**

```bash
git add scripts/ui/main.gd scripts/ui/game_view.gd
git commit -m "refactor: 2D 控制区与 3D HUD 统一走 ActionModel"
```

---

### Task 3: PlayerStatPanel + CardCountIcon

**Files:** Create `scripts/ui/card_count_icon.gd`、`scripts/ui/player_stat_panel.gd`、`tests/verify_stat_panel.gd`、`tests/verify_stat_panel.tscn`；Modify `tools/run_all_tests.sh`

- [ ] **Step 1: 写失败测试**

Create `tests/verify_stat_panel.gd`:

```gdscript
extends Node
## headless 单元测试：PlayerStatPanel（状态面板）。

var failures := 0
var checks := 0

func _ready() -> void:
	_run()
	print("=== STAT PANEL RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	var panel := PlayerStatPanel.new()
	add_child(panel)
	panel.set_data("甲", 2, 100, 4)
	_check("data 记录", panel.data.get("name") == "甲" and int(panel.data.get("health")) == 2 and int(panel.data.get("currency")) == 100 and int(panel.data.get("cards")) == 4)
	_check("名字显示", panel.name_visible() and panel.name_text() == "甲")
	panel.set_data("", 1, 0, 0)
	_check("无名字时隐藏名字行", not panel.name_visible())
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	_check("黑边框 2px", style != null and style.border_width_left == 2 and style.border_color.a > 0.8)
	_check("透明白灰底", style != null and style.bg_color.a > 0.0 and style.bg_color.a < 0.5)
```

Create `tests/verify_stat_panel.tscn`:

```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/verify_stat_panel.gd" id="1"]
[node name="VerifyStatPanel" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... --headless --path . res://tests/verify_stat_panel.tscn` → `PlayerStatPanel` 未定义。

- [ ] **Step 3: 写实现**

Create `scripts/ui/card_count_icon.gd`:

```gdscript
class_name CardCountIcon
extends Control
## 程序化「卡牌数」图标：圆角矩形描边 + 内框。风格同 CoinIcon/LifeIcon。

var color := Color.WHITE

func setup(p_color: Color) -> void:
	color = p_color
	queue_redraw()

func _draw() -> void:
	var m := 3.0
	var r := Rect2(Vector2(m, m), size - Vector2(m, m) * 2.0)
	draw_rect(r, color, false, 2.0)
	var pad := Vector2(r.size.x, r.size.y) * 0.26
	draw_rect(Rect2(r.position + pad, r.size - pad * 2.0), color, false, 1.5)
```

Create `scripts/ui/player_stat_panel.gd`:

```gdscript
class_name PlayerStatPanel
extends PanelContainer
## 玩家状态面板（2D）：可选名字 + 生命/金钱/卡牌数（图标+数字）。
## 自己面板无名字；其他玩家面板带名字。底色透明白灰 + 黑边框。

const ICON_SIZE := 22
const FONT_SIZE := 14
const BG_COLOR := Color(0.86, 0.88, 0.92, 0.22)
const BORDER_COLOR := Color(0.0, 0.0, 0.0, 0.85)

var data := {}

var _name_label: Label
var _row: HBoxContainer

func _ready() -> void:
	_build()

func _build() -> void:
	if _row != null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_name_label.add_theme_color_override("font_color", UITheme.color("text_primary"))
	_name_label.visible = false
	box.add_child(_name_label)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_row)

## 更新内容；player_name 为空则隐藏名字行。
func set_data(player_name: String, health: int, currency: int, cards: int) -> void:
	_build()
	data = {"name": player_name, "health": health, "currency": currency, "cards": cards}
	_name_label.text = player_name
	_name_label.visible = player_name != ""
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_add_group(LifeIcon.new(), UITheme.color("danger"), health)
	_add_group(CoinIcon.new(), UITheme.color("accent"), currency)
	_add_group(CardCountIcon.new(), UITheme.color("text_secondary"), cards)

func _add_group(icon: Control, color: Color, value: int) -> void:
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size = icon.custom_minimum_size
	icon.call("setup", color)
	_row.add_child(icon)
	var num := Label.new()
	num.text = str(value)
	num.add_theme_font_size_override("font_size", FONT_SIZE)
	num.add_theme_color_override("font_color", UITheme.color("text_primary"))
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row.add_child(num)

func name_visible() -> bool:
	return _name_label != null and _name_label.visible

func name_text() -> String:
	return _name_label.text if _name_label != null else ""
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... --headless --path . res://tests/verify_stat_panel.tscn` → `=== STAT PANEL RESULT: 5/5 passed ===`。

- [ ] **Step 5: 注册 + 提交**

Modify `tools/run_all_tests.sh`，在 `run_single "actions" ...` 之后加：

```bash
run_single "stat_panel" res://tests/verify_stat_panel.tscn
```

```bash
git add scripts/ui/card_count_icon.gd scripts/ui/card_count_icon.gd.uid scripts/ui/player_stat_panel.gd scripts/ui/player_stat_panel.gd.uid tests/verify_stat_panel.gd tests/verify_stat_panel.gd.uid tests/verify_stat_panel.tscn tools/run_all_tests.sh
git commit -m "feat: PlayerStatPanel 状态面板 + CardCountIcon + 测试"
```

---

### Task 4: 3D 头顶玩家面板（SubViewport → Sprite3D）+ 场景删旧标签

**Files:** Modify `scripts/ui/table3d_view.gd`、`scenes/ui/table3d.tscn`、`tests/verify_table3d.gd`

**Interfaces:**
- Consumes: `PlayerStatPanel.set_data`
- Produces: `Table3dView._seat_panels: Array`（下标 = 座位槽位 0..3）、`_stat_viewports: Array`

- [ ] **Step 1: 改 table3d_view 建面板**

Modify `scripts/ui/table3d_view.gd`：
1. 常量与成员：

```gdscript
const STAT_VIEWPORT_SIZE := Vector2i(320, 96)
const STAT_PANEL_OFFSET := Vector3(0.0, 0.75, 0.0)
const STAT_PANEL_PIXEL_SIZE := 0.005
```
```gdscript
var _seat_panels: Array = []      # PlayerStatPanel per slot
var _stat_viewports: Array = []
```
2. `_bind()` 中，座位循环里为每席建 SubViewport+Panel+Sprite3D：

```gdscript
		var avatar := seat.get_node_or_null("Avatar")
		var sub := SubViewport.new()
		sub.name = "StatViewport%d" % i
		sub.size = STAT_VIEWPORT_SIZE
		sub.transparent_bg = true
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(sub)
		var panel := PlayerStatPanel.new()
		panel.name = "Panel"
		sub.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var sprite := Sprite3D.new()
		sprite.name = "StatPanel"
		sprite.texture = sub.get_texture()
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.no_depth_test = true
		sprite.pixel_size = STAT_PANEL_PIXEL_SIZE
		sprite.position = STAT_PANEL_OFFSET
		if avatar != null:
			avatar.add_child(sprite)
		_seat_panels.append(panel)
		_stat_viewports.append(sub)
```
3. `render()` 座位循环里，`_apply_avatar(...)` 之后加：

```gdscript
		if slot_i < _seat_panels.size():
			_seat_panels[slot_i].set_data(str(p.get("name", "")), int(p.get("health", 0)), int(p.get("currency", 0)), int(p.get("count", 0)))
```
4. `_render_seat()` 删除设置 `NameLabel`/`StatLabel` 的整段（精确删除以下 7 行）：

```gdscript
	var name_label: Label3D = node.get_node("NameLabel")
	var stat_label: Label3D = node.get_node("StatLabel")
	name_label.text = str(p.get("name", ""))
	stat_label.text = "%d张  ¥%d  ♥%d" % [int(p.get("count", 0)), int(p.get("currency", 0)), int(p.get("health", 0))]
	var tint := Color(1, 1, 1, 0.5) if bool(p.get("eliminated", false)) else Color(1, 1, 1, 1)
	name_label.modulate = tint
	stat_label.modulate = tint
```

- [ ] **Step 2: 场景删除 4 组 NameLabel/StatLabel**

Modify `scenes/ui/table3d.tscn`：删除每个 `Seats/SeatN` 下的 `NameLabel` 与 `StatLabel` 两个节点块（共 8 个节点），其余不动。

- [ ] **Step 3: 更新测试**

Modify `tests/verify_table3d.gd` 的 `_test_view_render()`：把
```gdscript
	_check("viewer 名字标签", view._seat_nodes[0].get_node("NameLabel").text == "甲")
	_check("viewer 货币标签含 ¥100", view._seat_nodes[0].get_node("StatLabel").text.contains("¥100"))
	_check("对手名字标签", view._seat_nodes[1].get_node("NameLabel").text == "乙")
```
替换为：
```gdscript
	_check("viewer 面板 data", view._seat_panels[0].data.get("name") == "甲" and int(view._seat_panels[0].data.get("currency")) == 100)
	_check("对手面板 data", view._seat_panels[1].data.get("name") == "乙")
	_check("每席面板各一", view._seat_panels.size() == 4)
```

- [ ] **Step 4: 跑测试确认通过**

Run:
```bash
... --headless --path . res://tests/verify_table3d.tscn          # 34/34（计数不变）
... --headless --path . res://tests/verify_table3d_interaction.tscn  # 34/34
```
Expected: 均全绿，无 `SCRIPT ERROR`。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/table3d_view.gd scenes/ui/table3d.tscn tests/verify_table3d.gd
git commit -m "feat: 3D 头顶玩家面板（SubViewport+Sprite3D），移除旧 NameLabel/StatLabel"
```

---

### Task 5: 自己面板（屏幕右下角）

**Files:** Modify `scripts/ui/main.gd`

**Interfaces:**
- Produces: `main._self_panel: PlayerStatPanel`、`main._update_self_panel() -> void`

- [ ] **Step 1: 成员与方法**

Modify `scripts/ui/main.gd`，在 `var _crosshair: Control = null` 之后加：

```gdscript
var _self_panel: PlayerStatPanel = null
```

在 `_sync_table3d_pointer()` 之后加：

```gdscript
## 3D 自己面板（屏幕右下角）：生命/金钱/卡牌数（无名字）。
func _ensure_self_panel() -> void:
	if _self_panel != null and is_instance_valid(_self_panel):
		return
	_self_panel = PlayerStatPanel.new()
	_self_panel.name = "SelfStatPanel"
	_self_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_self_panel.z_index = 80
	add_child(_self_panel)
	_self_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_self_panel.offset_left = -272.0
	_self_panel.offset_top = -84.0
	_self_panel.offset_right = -16.0
	_self_panel.offset_bottom = -16.0

func _update_self_panel() -> void:
	if _self_panel == null or not is_instance_valid(_self_panel):
		return
	var viewer := int(latest_state.get("viewer_id", 0))
	for p in latest_state.get("players", []):
		if int(p.id) == viewer:
			_self_panel.set_data("", int(p.get("health", 0)), int(p.get("currency", 0)), int(p.get("count", 0)))
			return
```

- [ ] **Step 2: 进入/更新/退出 3D 时同步**

Modify `_set_table3d(on)`：
- `if on:` 分支里 `_sync_table3d_pointer()` 之后加：

```gdscript
		_ensure_self_panel()
		_self_panel.visible = true
		_update_self_panel()
```
- `else:` 分支里加：

```gdscript
		if _self_panel != null and is_instance_valid(_self_panel):
			_self_panel.visible = false
```

Modify `_on_state_updated` 的 3D 渲染块之后加：

```gdscript
	if _table3d_active:
		_update_self_panel()
```

- [ ] **Step 3: 编译 + 回归**

Run: 编译 + `tools/run_all_tests.sh --quick` → 无错误、0 败。

- [ ] **Step 4: 提交**

```bash
git add scripts/ui/main.gd
git commit -m "feat: 3D 自己状态面板（屏幕右下角）"
```

---

### Task 6: Kongbaya 金色铃铛 + pending 贴堆

**Files:** Modify `scenes/ui/table3d.tscn`、`scripts/ui/table3d_view.gd`、`tests/verify_table3d_interaction.gd`

**Interfaces:**
- Produces: `Table3dView._bell_dome: MeshInstance3D`、`Table3dView._bell_mat: StandardMaterial3D`

- [ ] **Step 1: 场景加铃铛 + pending 贴堆**

Modify `scenes/ui/table3d.tscn`：
1. 新增子资源（放在 `TableEdgeMesh` 之后）：

```
[sub_resource type="SphereMesh" id="BellDomeMesh"]
radius = 0.26
height = 0.52
is_hemisphere = true
radial_segments = 24
rings = 12

[sub_resource type="SphereMesh" id="BellKnobMesh"]
radius = 0.05
height = 0.1

[sub_resource type="CylinderMesh" id="BellBaseMesh"]
top_radius = 0.3
bottom_radius = 0.32
height = 0.04

[sub_resource type="StandardMaterial3D" id="BellMat"]
albedo_color = Color(0.96, 0.84, 0.48, 1)
emission_enabled = true
emission = Color(0.55, 0.45, 0.2, 1)

[sub_resource type="BoxShape3D" id="BellShape"]
size = Vector3(0.66, 0.5, 0.66)
```
2. `Center` 下新增：

```
[node name="KongBell" type="Node3D" parent="Center"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -0.75, 0, 0)

[node name="Base" type="MeshInstance3D" parent="Center/KongBell"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.02, 0)
mesh = SubResource("BellBaseMesh")
material_override = SubResource("BellMat")

[node name="Dome" type="MeshInstance3D" parent="Center/KongBell"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.04, 0)
mesh = SubResource("BellDomeMesh")
material_override = SubResource("BellMat")

[node name="Knob" type="MeshInstance3D" parent="Center/KongBell"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.30, 0)
mesh = SubResource("BellKnobMesh")
material_override = SubResource("BellMat")

[node name="PickArea" type="Area3D" parent="Center/KongBell"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.15, 0)
collision_layer = 2
collision_mask = 0

[node name="PickShape" type="CollisionShape3D" parent="Center/KongBell/PickArea"]
shape = SubResource("BellShape")
```
3. `Pending` 改为贴堆：`transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.05, 0)`（原 scale 1.5 / `(-0.9, 0.03, 0)`）。

- [ ] **Step 2: table3d_view 绑定铃铛 + 发光**

Modify `scripts/ui/table3d_view.gd`：
1. 成员：

```gdscript
var _bell_dome: MeshInstance3D = null
var _bell_mat: StandardMaterial3D = null
```
2. `_bind()` 里（deck 之后）加：

```gdscript
	var bell := get_node_or_null("Center/KongBell")
	if bell != null:
		_bell_dome = bell.get_node_or_null("Dome")
		if _bell_dome != null:
			_bell_mat = _bell_dome.material_override
		var bell_pick := bell.get_node_or_null("PickArea")
		if bell_pick != null:
			bell_pick.collision_layer = Table3dLayout.PICK_MASK
			bell_pick.collision_mask = 0
			bell_pick.set_meta("pick", {"kind": "hud", "action": "kongbaya"})
```
3. `render()` 末尾加：

```gdscript
	_update_bell(state)
```
并新增方法：

```gdscript
## 铃铛可用性：金色亮 / 暗。
func _update_bell(state: Dictionary) -> void:
	if _bell_mat == null:
		return
	var avail := ActionModel.kongbaya_available(state)
	_bell_mat.emission_enabled = avail
	_bell_mat.albedo_color = Color(0.96, 0.84, 0.48) if avail else Color(0.42, 0.38, 0.28)
```

- [ ] **Step 3: 测试加断言**

Modify `tests/verify_table3d_interaction.gd` 的 `_test_view()`：在 HUD 断言之后加：

```gdscript
	_check("铃铛拾取标记", view.get_node("Center/KongBell/PickArea").get_meta("pick", {}).get("action", "") == "kongbaya")
	_check("pending 与牌堆同尺寸（scale 1）", view.get_node("Center/Pending").scale.is_equal_approx(Vector3.ONE))
```
（计数 34 → 36。）

- [ ] **Step 4: 跑测试确认通过**

Run:
```bash
... --headless --path . res://tests/verify_table3d_interaction.tscn   # 36/36
... --headless --path . res://tests/verify_table3d.tscn               # 34/34
tools/run_all_tests.sh --quick
```
Expected: 全绿。

- [ ] **Step 5: 更新交接说明 + 提交**

Modify `docs/AI_AGENT_交接说明.md`：把 Milestone 2 条目的「角色/相机」段与测试计数更新（`verify_table3d_interaction` 36/36），并补一句「动作判定统一走 `ActionModel`；玩家状态 UI 自己=屏幕右下、他人=头顶 SubViewport 面板；Kongbaya=3D 金铃铛；pending 贴堆」。

```bash
git add scenes/ui/table3d.tscn scripts/ui/table3d_view.gd tests/verify_table3d_interaction.gd docs/AI_AGENT_交接说明.md
git commit -m "feat: Kongbaya 金色铃铛（抽牌堆左侧）+ pending 贴堆"
```

---

## 人工验收（不纳入自动化）

- **2D 不变**：进 2D 对局，Ready/Kongbaya 铃铛/Q 决策按钮/变换 Joker 行为与外观基本不变（Q「交换」文案略短）。
- **3D**：右下角自己面板（生命/金钱/卡牌数，透明白灰底+黑边框、无名字）；其他玩家头顶面板带名字；自己角色与面板都不显示。
- 铃铛在抽牌堆左侧，轮到你抽牌时金色发亮、可点；非你回合变暗。
- 抽到 pending 时大牌与抽牌堆同尺寸、贴在堆上，可点。
- `F10` 进出 3D 时自己面板正确显隐。

## Self-Review 结论

- **Spec 覆盖**：§2 ActionModel → Task 1/2/6；§3 面板 → Task 3；§4 自己面板 → Task 5；§5 他方面板 → Task 4；§6 铃铛 → Task 6；§7 pending → Task 6；§8 测试 → Task 1/3/4/6。
- **占位符**：无 TBD/TODO；代码步骤给完整代码。
- **类型一致性**：`ActionModel`（`conditional_actions/kongbaya_available/ready_text/ready_enabled`，键 `action/text/enabled`）、`PlayerStatPanel.set_data/name_visible/name_text/data`、`main._on_action/_hud_buttons/_self_panel/_update_self_panel`、`Table3dView._seat_panels/_stat_viewports/_bell_dome/_bell_mat` 跨任务一致；测试计数 16 / 5 / 34 / 36。
