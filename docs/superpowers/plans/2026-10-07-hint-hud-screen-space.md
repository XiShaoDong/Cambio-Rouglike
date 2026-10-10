# 3D Action Hint 屏幕空间化 + 回合倒计时 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 3D 对局的 action hint 从世界空间看板改为屏幕空间顶部居中面板，并在其上新增一个从 30 递减（可为负）的回合倒计时胶囊，附带掉落/回弹换字动画。

**Architecture:** 三个纯客户端小单元：`TurnTimer`（纯计时模型）、`HintText`（集中 hint 文案）、`HintHud`（屏幕空间控件，自带布局与 Tween 动画）；`main.gd` 在 3D 激活时创建/显隐，并在既有 `_refresh_hint_panel()` 里驱动文本与「新回合」重置。计时数据源与 UI 解耦，未来换服务器 `deadline_ms` 时只改喂值处。

**Tech Stack:** Godot 4.6 / GDScript；自定义 headless 测试场景（`tests/verify_*.tscn` + `.gd`，root Node 脚本在 `_ready` 跑断言并 `get_tree().quit`）。

## Global Constraints

- Godot 4.6；所有路径以 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/` 为根，`res://` 即该根。
- **不启动 GUI**：一律 headless 单测验证：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/<scene>.tscn`。
- **不改**：`scripts/core/*`、`scripts/net/*`、`scenes/ui/table3d.tscn`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`、`board3d.gd`、`key_hint_panel.gd`。
- 2D 对局界面（`HintArea` / `CenterHint`）逐字不动；本功能**仅 3D** 生效。
- hint 文案英文逐字不变（只集中，不翻译），保证 `verify_hint` / `verify_j_swap` 继续通过。
- 倒计时为纯展示：不联网、不写快照、不触发任何规则。
- 提交信息按 `feat:` / `fix:` / `doc:` 分类；每个 Task 末尾单独提交。
- **仓库跟踪 `.gd.uid` 文件**（Godot 4 自动生成）：新增/修改脚本时，其 `.gd.uid` 必须一并 `git add`。
- 项目内绝对路径用于文档/交接；代码内用 `res://`。

---

### Task 1: `TurnTimer` 纯计时模型 + 测试脚手架

**Files:**
- Create: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/turn_timer.gd`
- Create: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.gd`
- Create: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.tscn`

**Interfaces:**
- Produces: `class_name TurnTimer extends RefCounted`；`limit: float`、`remaining: float`、`reset(sec: float = 30.0) -> void`、`tick(delta: float) -> void`、`seconds_left() -> int`（`int(floor(remaining))`）、`phase() -> int`（0 正常 / 1 临近 / 2 超时）。

- [ ] **Step 1: 写失败测试（测试场景 + TurnTimer 断言）**

创建 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.tscn`：

```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/verify_hint_hud.gd" id="1"]
[node name="VerifyHintHud" type="Node"]
script = ExtResource("1")
```

创建 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.gd`：

```gdscript
extends Node
## headless 单元测试：TurnTimer 纯模型 + HintText 文案表 + HintHud 屏幕面板 + main 集成。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== HINT_HUD RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_turn_timer()

func _test_turn_timer() -> void:
	var t := TurnTimer.new()
	t.reset(30.0)
	_check("TurnTimer reset=30", is_equal_approx(t.remaining, 30.0) and t.seconds_left() == 30)
	t.tick(1.5)
	_check("TurnTimer tick 递减", is_equal_approx(t.remaining, 28.5) and t.seconds_left() == 28)
	t.tick(40.0)
	_check("TurnTimer 可为负", t.remaining < 0.0 and t.seconds_left() < 0)
	t.reset(30.0)
	_check("TurnTimer phase 正常 0", t.phase() == 0)
	t.reset(8.0)
	_check("TurnTimer phase 临近 1", t.phase() == 1)
	t.reset(0.0)
	_check("TurnTimer phase 超时 2", t.phase() == 2)
	var n := TurnTimer.new()
	n.reset(0.0)
	n.tick(0.3)
	_check("TurnTimer floor 负数 -1", n.seconds_left() == -1)
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint_hud.tscn`
Expected: 解析报错 / 运行失败（`TurnTimer` 未定义），非 0 退出或 `FAILURES`。

- [ ] **Step 3: 写最小实现**

创建 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/turn_timer.gd`：

```gdscript
class_name TurnTimer
extends RefCounted
## 回合倒计时纯模型（纯展示：不联网、不写快照、不触发规则）。
## 数据源与展示解耦：v2 换服务器 deadline_ms 时，只改"谁来喂 remaining"，UI 不动。

var limit: float = 30.0
var remaining: float = 30.0

func reset(sec: float = 30.0) -> void:
	limit = sec
	remaining = sec

func tick(delta: float) -> void:
	remaining -= delta

## 显示用整数秒，向下取整：30.0→30、-0.3→-1。
func seconds_left() -> int:
	return int(floor(remaining))

## 0=正常(>10) 1=临近(1..10) 2=超时(<=0)。
func phase() -> int:
	if remaining <= 0.0:
		return 2
	if remaining <= 10.0:
		return 1
	return 0
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint_hud.tscn`
Expected: `=== HINT_HUD RESULT: 7/7 passed ===`，退出码 0。

- [ ] **Step 5: 编译检查 + 提交**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
git add scripts/ui/turn_timer.gd scripts/ui/turn_timer.gd.uid tests/verify_hint_hud.gd tests/verify_hint_hud.gd.uid tests/verify_hint_hud.tscn
git commit -m "feat: TurnTimer 回合倒计时纯模型 + headless 测试脚手架"
```

---

### Task 2: `HintText` 集中文案表 + `main._hint_for` 委托

**Files:**
- Create: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/hint_text.gd`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/main.gd`（`_hint_for` 1248-1281 与 `_decision_hint` 1283-1325 替换为薄委托）
- Test: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.gd`

**Interfaces:**
- Consumes: `TurnTimer`（Task 1，无直接依赖）。
- Produces: `class_name HintText extends RefCounted`；`static func hint(state: Dictionary, phase: int, is_current: bool, action_mode: String) -> String`、`static func decision(state: Dictionary, is_current: bool, name: String, action_mode: String) -> String`。`main._hint_for(phase, is_current)` 保留签名并委托。

- [ ] **Step 1: 写失败测试（追加 HintText 断言）**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.gd` 的 `_run()` 中追加一行调用，并新增两个辅助函数与测试函数：

```gdscript
func _run() -> void:
	_test_turn_timer()
	_test_hint_text()
```

```gdscript
func _hint_state(phase: int, viewer: int, current: int, pending: Dictionary = {}) -> Dictionary:
	return {
		"phase": phase, "viewer_id": viewer, "current_player": current, "current_name": "Bob",
		"players": [], "discard": {}, "pending": pending, "event_log": [], "match_number": 1,
		"slap_rank": "", "slap_open": false, "slap_exchange_actor": 0, "kong_caller": -1,
		"ready_count": 0, "result": {}, "run": {}, "q_decision": {},
	}

func _test_hint_text() -> void:
	_check("HintText INITIAL_PEEK", HintText.hint(_hint_state(1, 0, 0), 1, true, "") == "Remember your two bottom cards, then click Ready")
	_check("HintText TURN_DRAW 当前", "discard pile" in HintText.hint(_hint_state(2, 0, 0), 2, true, ""))
	_check("HintText TURN_DRAW 他人含 Bob", "Bob" in HintText.hint(_hint_state(2, 1, 0), 2, false, ""))
	var replace_state := _hint_state(3, 0, 0, {"rank": "9", "source": "draw"})
	_check("HintText decision replace 含 replace", "replace" in HintText.hint(replace_state, 3, true, "replace").to_lower())
	_check("HintText decision 他人含 Bob", "Bob" in HintText.hint(replace_state, 3, false, ""))
	_check("HintText GAME_OVER 非空", not HintText.hint(_hint_state(7, 0, 0), 7, true, "").is_empty())
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint_hud.tscn`
Expected: `HintText` 未定义 → FAIL/解析错误。

- [ ] **Step 3: 写 `HintText` 实现（字符串逐字搬自 `_hint_for`/`_decision_hint`）**

创建 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/hint_text.gd`：

```gdscript
class_name HintText
extends RefCounted
## 集中所有 action hint 文案（英文，暂不翻译）。main._hint_for 委托到此；将来统一翻译只改本文件。

static func hint(state: Dictionary, phase: int, is_current: bool, action_mode: String) -> String:
	var name := str(state.get("current_name", ""))
	match phase:
		GameState.Phase.INITIAL_PEEK:
			return "Remember your two bottom cards, then click Ready"
		GameState.Phase.TURN_DRAW:
			var slap_note := ""
			if bool(state.get("slap_open", false)):
				slap_note = " · SLAP open: click matching card"
			if is_current:
				return "Draw from the deck or the discard pile (discard top only replaces)" + slap_note
			return "Waiting for %s to draw a card" % name + slap_note
		GameState.Phase.TURN_DECISION:
			return decision(state, is_current, name, action_mode)
		GameState.Phase.Q_DECISION:
			var qd: Dictionary = state.get("q_decision", {})
			if is_current:
				if not bool(qd.get("own_viewed", false)):
					return "Peeked their card. Now pick one of your own cards to peek"
				return "Swap the two viewed cards, or keep yours?"
			if not bool(qd.get("own_viewed", false)):
				return "Waiting for %s to peek one of their own cards" % name
			return "Waiting for %s to decide" % name
		GameState.Phase.SLAP_WINDOW:
			return "Slap: click a card of the same rank. Wrong slap draws a penalty"
		GameState.Phase.SLAP_EXCHANGE:
			if is_current:
				return "Choose one of your cards to give to the slapped player"
			return "Waiting for %s to give a card" % name
		GameState.Phase.SLAP_DUEL:
			return "Duel: stop closest to the red mark to win the slap"
		GameState.Phase.GAME_OVER:
			return "Ranked by total score, then card count, then highest single card"
	return "Waiting for %s to act" % name

static func decision(state: Dictionary, is_current: bool, name: String, action_mode: String) -> String:
	var pending: Dictionary = state.get("pending", {})
	var rank := str(pending.get("rank", ""))
	var source := str(pending.get("source", "draw"))
	if not is_current:
		if source == "discard":
			return "%s took a card from the Discard" % name
		if rank == "J":
			return "%s drew a card and is choosing cards to swap" % name
		if rank in ["7", "8", "9", "10", "Q"]:
			return "%s drew a card and is choosing a card to look at" % name
		return "%s drew a card from the Deck" % name
	if source == "discard":
		return "Replace one of your cards with the drawn card"
	match action_mode:
		"replace":
			return "Replace one of your cards, or discard the drawn card"
		"peek_own":
			return "Choose one of your own cards to peek"
		"peek_other":
			return "Choose another player's card to peek"
		"queen_target":
			return "Peek another player's card, then peek one of your own cards"
		"q_view_own":
			return "Peek one of your own cards, then decide to swap"
		"jack_target":
			return "J: pick an opponent's card to swap"
		"jack_own":
			return "J: pick one of your own cards, then confirm"
		"jack_ready":
			return "J: two cards picked — click Swap or Keep"
	if rank == "J":
		return "Discard to swap two cards, or replace one of your cards"
	if rank in ["7", "8"]:
		return "Discard to peek your own card, or replace one of your cards"
	if rank in ["9", "10"]:
		return "Discard to peek someone's card, or replace one of your cards"
	if rank == "Q":
		return "Discard to peek and decide to swap, or replace one of your cards"
	return "Discard the drawn card, or replace one of your cards"
```

- [ ] **Step 4: 把 `main._hint_for` 改为薄委托，删除 `_decision_hint`**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/main.gd` 中，把现有 `func _hint_for(...)` 整个函数体（原 1248-1281）与紧随的 `func _decision_hint(...)`（原 1283-1325）替换为：

```gdscript
func _hint_for(phase: int, is_current: bool) -> String:
	return HintText.hint(latest_state, phase, is_current, interaction.action_mode)
```

- [ ] **Step 5: 运行新测试 + 回归（文案必须不变）**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint_hud.tscn`
Expected: `=== HINT_HUD RESULT: 13/13 passed ===`

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint.tscn`
Expected: `=== HINT RESULT: 8/8 passed ===`

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_j_swap.tscn`
Expected: `=== J_SWAP RESULT: 11/11 passed ===`（或该测试既有通过数）

- [ ] **Step 6: 提交**

```bash
git add scripts/ui/hint_text.gd scripts/ui/hint_text.gd.uid scripts/ui/main.gd scripts/ui/main.gd.uid tests/verify_hint_hud.gd
git commit -m "feat: HintText 集中 hint 文案表，main._hint_for 改为委托"
```

---

### Task 3: `HintHud` 屏幕空间面板（布局 + 计时展示 + 掉落/回弹动画）

**Files:**
- Create: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/hint_hud.gd`
- Test: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.gd`

**Interfaces:**
- Consumes: `TurnTimer`（Task 1）。
- Produces: `class_name HintHud extends Control`；常量 `PILL_H`、`PILL_H_PAD`、`SEP`、`RISE`、`TOP_MARGIN`、`COLOR_NORMAL/COLOR_WARN/COLOR_OVER`、`PHASE_TURN_SECONDS`；方法 `set_hint(text: String)`、`reset_turn(seconds := PHASE_TURN_SECONDS)`、`set_phase_visible(phase: int)`、`show_hud(on: bool)`；测试访问器 `pill()`、`pill_label()`、`timer()`、`cur_label()`、`next_label()`、`hint_base_y()`。

- [ ] **Step 1: 写失败测试（追加 HintHud 断言）**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.gd` 的 `_run()` 追加 `await _test_hint_hud()`，并新增：

```gdscript
func _run() -> void:
	_test_turn_timer()
	_test_hint_text()
	await _test_hint_hud()

func _test_hint_hud() -> void:
	var hud := HintHud.new()
	add_child(hud)
	await get_tree().process_frame
	hud.show_hud(true)
	_check("HintHud 顶部居中锚点", is_equal_approx(hud.anchor_left, 0.5) and is_equal_approx(hud.anchor_right, 0.5) and is_equal_approx(hud.anchor_top, 0.0))
	_check("HintHud 初始隐藏于建造后 show", hud.visible)
	hud.set_phase_visible(2)
	hud.reset_turn(30.0)
	var pill: PanelContainer = hud.pill()
	_check("胶囊存在且可见", pill != null and pill.visible)
	var st: StyleBoxFlat = pill.get_theme_stylebox("panel")
	_check("胶囊圆角=高/2", is_equal_approx(float(st.corner_radius_top_left), HintHud.PILL_H * 0.5))
	_check("胶囊左右留白", is_equal_approx(st.content_margin_left, HintHud.PILL_H_PAD) and is_equal_approx(st.content_margin_right, HintHud.PILL_H_PAD))
	_check("胶囊有边框", st.border_width_top >= 2)
	_check("倒计时文本=30", hud.pill_label().text == "30")
	_check("进场：胶囊从上方掉落", pill.position.y < 0.0)
	hud.set_hint("First")
	hud.set_hint("Second")
	_check("换字：旧片仍在", hud.cur_label().text == "First")
	_check("换字：新片从上方进入", hud.next_label().text == "Second" and hud.next_label().position.y < hud.hint_base_y())
	hud.set_phase_visible(7)
	_check("GAME_OVER 隐藏胶囊", not pill.visible)
	hud.set_phase_visible(2)
	hud.reset_turn(1.0)
	hud.timer().tick(2.0)
	hud._process(0.0)
	_check("负秒红色", hud.pill_label().get_theme_color("font_color") == HintHud.COLOR_OVER)
	hud.show_hud(false)
	_check("show_hud(false) 不可见", not hud.visible)
	_check("show_hud(false) 停止计时", not hud.is_processing())
	hud.queue_free()
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint_hud.tscn`
Expected: `HintHud` 未定义 → FAIL/解析错误。

- [ ] **Step 3: 写 `HintHud` 实现**

创建 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/hint_hud.gd`：

```gdscript
class_name HintHud
extends Control
## 3D action hint 屏幕空间面板：顶部居中的「回合倒计时胶囊 + 提示文本」。
## 纯客户端展示层，仅 3D 激活时显示；倒计时为本地纯展示（不联网、不触发规则）。
## 动画只改 position.y / modulate.a，不用 Control.scale（规避 B1 位置漂移）。

const TOP_MARGIN := 40.0
const PILL_H := 48.0
const PILL_H_PAD := 30.0
const PILL_V_PAD := 8.0
const PILL_FONT := 26
const HINT_FONT := 18
const HINT_MAX_W := 560.0
const SEP := 12.0
const RISE := 70.0
const RISE_UP := 50.0
const DROP_DUR := 0.30
const UP_DUR := 0.18
const PHASE_TURN_SECONDS := 30.0
const COLOR_NORMAL := Color(0.95, 0.97, 1.0)
const COLOR_WARN := Color(1.0, 0.78, 0.30)
const COLOR_OVER := Color(1.0, 0.36, 0.34)
## 胶囊显示阶段（GameState.Phase 数值）：INITIAL_PEEK / TURN_DRAW / TURN_DECISION / Q_DECISION / SLAP_EXCHANGE / SLAP_DUEL。
const ACTIVE_PHASES := [1, 2, 3, 4, 6, 8]

var _timer := TurnTimer.new()
var _pill: PanelContainer
var _pill_label: Label
var _hint_a: Label
var _hint_b: Label
var _cur: Label
var _next: Label
var _hint_text := ""
var _pill_x := 0.0
var _hint_base_y := 0.0
var _animating := false
var _tween: Tween = null

func _ready() -> void:
	_build()
	_layout()
	visible = false
	set_process(false)

func _process(delta: float) -> void:
	_timer.tick(delta)
	_update_pill_text()

func _build() -> void:
	if _pill != null:
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill = PanelContainer.new()
	_pill.name = "CountdownPill"
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.custom_minimum_size = Vector2(0.0, PILL_H)
	_pill.add_theme_stylebox_override("panel", _pill_style())
	_pill_label = Label.new()
	_pill_label.name = "Label"
	_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pill_label.add_theme_font_size_override("font_size", PILL_FONT)
	_pill_label.add_theme_color_override("font_color", COLOR_NORMAL)
	_pill.add_child(_pill_label)
	add_child(_pill)
	_hint_a = _make_hint_label("HintLabelA")
	_hint_b = _make_hint_label("HintLabelB")
	add_child(_hint_a)
	add_child(_hint_b)
	_cur = _hint_a
	_next = _hint_b
	_next.visible = false

func _pill_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.09, 0.12, 0.75)
	s.set_corner_radius_all(int(PILL_H * 0.5))
	s.content_margin_left = PILL_H_PAD
	s.content_margin_right = PILL_H_PAD
	s.content_margin_top = PILL_V_PAD
	s.content_margin_bottom = PILL_V_PAD
	s.border_color = Color(0.42, 0.72, 0.95, 0.85)
	s.set_border_width_all(2)
	return s

func _make_hint_label(n: String) -> Label:
	var l := Label.new()
	l.name = n
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(HINT_MAX_W, 0.0)
	l.add_theme_font_size_override("font_size", HINT_FONT)
	l.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	return l

## 顶部居中锚点 + 按内容宽度/高度设置矩形；非动画中则把子节点落到基准位。
func _layout() -> void:
	if _pill == null:
		return
	var pill_size := _pill.get_combined_minimum_size()
	var hint_h := _cur.get_combined_minimum_size().y
	var w := maxf(pill_size.x, HINT_MAX_W)
	var h := PILL_H + SEP + hint_h
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = TOP_MARGIN
	offset_bottom = TOP_MARGIN + h
	_pill_x = (w - pill_size.x) * 0.5
	_hint_base_y = PILL_H + SEP
	if not _animating:
		_place_all()

func _place_all() -> void:
	_pill.position = Vector2(_pill_x, 0.0)
	_hint_a.position = Vector2(0.0, _hint_base_y)
	_hint_b.position = Vector2(0.0, _hint_base_y)

func _update_pill_text() -> void:
	if _pill_label == null:
		return
	_pill_label.text = str(_timer.seconds_left())
	var c := COLOR_NORMAL
	match _timer.phase():
		1:
			c = COLOR_WARN
		2:
			c = COLOR_OVER
	_pill_label.add_theme_color_override("font_color", c)

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_animating = false

func show_hud(on: bool) -> void:
	visible = on
	set_process(on)
	if on:
		_update_pill_text()
		_layout()
	else:
		_kill_tween()
		_place_all()

func set_phase_visible(phase: int) -> void:
	if _pill != null:
		_pill.visible = phase in ACTIVE_PHASES

func set_hint(text: String) -> void:
	if text == _hint_text:
		return
	_hint_text = text
	if not is_visible_in_tree() or _cur.text.is_empty():
		_cur.text = text
		_layout()
		return
	_play_swap(text)

func reset_turn(seconds := PHASE_TURN_SECONDS) -> void:
	_timer.reset(seconds)
	_update_pill_text()
	if not is_visible_in_tree():
		return
	_play_entry()

## 每回合进场：胶囊先掉落，随后 hint 掉落（TRANS_BACK 回弹）。
func _play_entry() -> void:
	_kill_tween()
	_layout()
	_animating = true
	_pill.position = Vector2(_pill_x, -RISE)
	_cur.position = Vector2(0.0, _hint_base_y - RISE)
	_cur.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_tween = create_tween()
	_tween.tween_property(_pill, "position:y", 0.0, DROP_DUR).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_cur, "position:y", _hint_base_y, DROP_DUR).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_cur, "modulate:a", 1.0, DROP_DUR)
	_tween.finished.connect(_on_entry_done)

func _on_entry_done() -> void:
	_animating = false
	_layout()

## 换 hint：旧片上移淡出，新片从上掉落回弹。
func _play_swap(text: String) -> void:
	_kill_tween()
	var old := _cur
	var inc := _next
	inc.text = text
	inc.visible = true
	inc.modulate = Color(1.0, 1.0, 1.0, 0.0)
	old.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_layout()
	_animating = true
	inc.position = Vector2(0.0, _hint_base_y - RISE)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(inc, "position:y", _hint_base_y, DROP_DUR).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(inc, "modulate:a", 1.0, DROP_DUR)
	_tween.tween_property(old, "position:y", _hint_base_y - RISE_UP, UP_DUR).set_ease(Tween.EASE_IN)
	_tween.tween_property(old, "modulate:a", 0.0, UP_DUR)
	_tween.finished.connect(_on_swap_done.bind(old, inc))

func _on_swap_done(old: Label, inc: Label) -> void:
	if not is_instance_valid(old) or not is_instance_valid(inc):
		return
	old.visible = false
	old.text = ""
	old.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_cur = inc
	_next = old
	_animating = false
	_layout()

## 测试/调试访问器。
func pill() -> PanelContainer:
	return _pill

func pill_label() -> Label:
	return _pill_label

func timer() -> TurnTimer:
	return _timer

func cur_label() -> Label:
	return _cur

func next_label() -> Label:
	return _next

func hint_base_y() -> float:
	return _hint_base_y
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint_hud.tscn`
Expected: `=== HINT_HUD RESULT: 26/26 passed ===`（Task 1+2 的 13 + 本 Task 13）。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/hint_hud.gd scripts/ui/hint_hud.gd.uid tests/verify_hint_hud.gd
git commit -m "feat: HintHud 屏幕空间提示面板（倒计时胶囊 + 掉落回弹动画）"
```

---

### Task 4: `main.gd` 集成（3D 建/显隐 + 驱动文本与回合重置 + 移除 hint3d 的 HintLabel）

**Files:**
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/main.gd`（变量区 ~632、`_set_table3d` ~405/426、`_make_hint_panel` ~275、`_refresh_hint_panel` ~335）
- Test: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.gd`

**Interfaces:**
- Consumes: `HintHud`（Task 3）、`HintText`（Task 2）。
- Produces: `main._hint_hud: HintHud`、`main._hud_turn_key: String`、`main._ensure_hint_hud()`、`main._update_hint_hud(phase, viewer, current)`。

- [ ] **Step 1: 写失败测试（追加 main 集成断言）**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.gd` 的 `_run()` 追加 `await _test_main_integration()`，并新增：

```gdscript
func _main_state() -> Dictionary:
	return {
		"phase": 2, "phase_name": "抽牌", "viewer_id": 0, "current_player": 0, "current_name": "A",
		"players": [
			{"id": 0, "name": "A", "slots": [{}, {}, {}, {}], "health": 2, "currency": 100, "count": 4, "eliminated": false},
			{"id": 1, "name": "B", "slots": [{}, {}, {}, {}], "health": 2, "currency": 100, "count": 4, "eliminated": false},
		],
		"draw_count": 40, "discard": {}, "pending": {}, "event_log": [], "match_number": 1,
		"slap_rank": "", "slap_open": false, "slap_exchange_actor": 0, "kong_caller": -1,
		"ready_count": 0, "result": {}, "run": {"match_limit": 5}, "q_decision": {},
	}

func _test_main_integration() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main_node: Node = scene.instantiate()
	add_child(main_node)
	await get_tree().process_frame
	await get_tree().process_frame
	main_node.latest_state = _main_state()
	main_node._set_table3d(true)
	await get_tree().process_frame
	_check("main 已建 HintHud", main_node._hint_hud != null and is_instance_valid(main_node._hint_hud))
	_check("3D 下 HintHud 可见", main_node._hint_hud.visible)
	_check("hint3d 不再有 HintLabel", main_node._hint_panel.get_node_or_null("VBox/HintLabel") == null)
	_check("hint3d 仍有 Ready", main_node._hint_panel.get_node_or_null("VBox/ReadyButton") != null)
	_check("HintHud 文本=_hint_for", main_node._hint_hud.cur_label().text == main_node._hint_for(2, true))
	_check("回合 key 记录 1:0", main_node._hud_turn_key == "1:0")
	main_node._set_table3d(false)
	await get_tree().process_frame
	_check("退出 3D 后 HintHud 隐藏", not main_node._hint_hud.visible)
	main_node.queue_free()
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint_hud.tscn`
Expected: `main` 无 `_hint_hud` → FAIL（`Invalid access` 或断言失败）。

- [ ] **Step 3: 加变量**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/main.gd` 变量区（`var _round_badge: Control = null` 之后，约 632 行）追加：

```gdscript
var _hint_hud: HintHud = null
var _hud_turn_key := ""
```

- [ ] **Step 4: 加 `_ensure_hint_hud` 与 `_update_hint_hud`，定义阶段常量**

在 `_ensure_key_hints()` 附近（约 144 行之前）的 `_corner_margin` 之后插入：

```gdscript
## 3D action hint 屏幕面板：顶部居中的「倒计时 + 提示文本」。
func _ensure_hint_hud() -> void:
	if _hint_hud != null and is_instance_valid(_hint_hud):
		return
	_hint_hud = HintHud.new()
	_hint_hud.name = "HintHud"
	_hint_hud.z_index = 80
	add_child(_hint_hud)

## 驱动 HintHud：文本随 hint 变化，进入新回合（key 变化）时重置 30 并播进场。
func _update_hint_hud(phase: int, viewer: int, current: int) -> void:
	if _hint_hud == null or not is_instance_valid(_hint_hud):
		return
	_hint_hud.set_hint(_hint_for(phase, viewer == current))
	_hint_hud.set_phase_visible(phase)
	var key := "%d:%d" % [int(latest_state.get("match_number", 1)), current]
	if phase in _HUD_ACTIVE_PHASES and key != _hud_turn_key:
		_hud_turn_key = key
		_hint_hud.reset_turn(HintHud.PHASE_TURN_SECONDS)
```

在 `main.gd` 的 `const PHASE_*` 常量区（约 527-536 行，`const PHASE_SHOP := 10` 之后）追加：

```gdscript
## HintHud 胶囊显示 + 倒计时重置的阶段（与 HintHud.ACTIVE_PHASES 一致）。
const _HUD_ACTIVE_PHASES := [PHASE_INITIAL_PEEK, PHASE_TURN_DRAW, PHASE_TURN_DECISION, PHASE_Q_DECISION, PHASE_SLAP_EXCHANGE, PHASE_SLAP_DUEL]
```

- [ ] **Step 5: `_set_table3d(true)` 建/显示；`(false)` 隐藏**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/main.gd` 的 `_set_table3d(true)` 分支中，把这一行：

```gdscript
		_sync_table3d_pointer()
		_refresh_hint_panel()
```

替换为：

```gdscript
		_sync_table3d_pointer()
		_ensure_hint_hud()
		_hint_hud.show_hud(true)
		_refresh_hint_panel()
```

在同一函数 `else` 分支中（`if _round_badge != null and is_instance_valid(_round_badge): _round_badge.visible = false` 之后）加入：

```gdscript
		if _hint_hud != null and is_instance_valid(_hint_hud):
			_hint_hud.show_hud(false)
```

- [ ] **Step 6: `_make_hint_panel` 移除 `HintLabel`**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/main.gd` 的 `_make_hint_panel()` 中，删除以下创建 HintLabel 并加入 `vb` 的片段（原 275-280 行）：

```gdscript
	var lbl := Label.new()
	lbl.name = "HintLabel"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	vb.add_child(lbl)
```

- [ ] **Step 7: `_refresh_hint_panel` 驱动 HintHud（替换 HintLabel 刷新）**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/main.gd` 的 `_refresh_hint_panel()` 中，删除：

```gdscript
	var lbl: Label = _hint_panel.get_node_or_null("VBox/HintLabel")
	if lbl != null:
		lbl.text = _hint_for(phase, viewer == current)
```

替换为：

```gdscript
	_update_hint_hud(phase, viewer, current)
```

（`viewer`/`current` 已在该函数上方定义，保留不动。）

- [ ] **Step 8: 运行测试，确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint_hud.tscn`
Expected: `=== HINT_HUD RESULT: 33/33 passed ===`（26 + 本 Task 7）。

- [ ] **Step 9: 回归（3D 看板/手动/交互不受影响）**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: 既有全绿（52/52 或当前数）。

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_manual.tscn`
Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint.tscn`
Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_j_swap.tscn`

- [ ] **Step 10: 提交**

```bash
git add scripts/ui/main.gd tests/verify_hint_hud.gd
git commit -m "feat: main 接入 HintHud（3D 显隐 + 文本/回合重置驱动），hint3d 移除 HintLabel"
```

---

### Task 5: 文档更新 + 全量回归

**Files:**
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/docs/AI_AGENT_交接说明.md`（§2 基线追加一条）
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/docs/功能实现文档.md`（UI 文件表追加两行）

**Interfaces:** 无代码接口变更。

- [ ] **Step 1: 更新交接说明**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/docs/AI_AGENT_交接说明.md` 的 §2 基线中，`- **3D 大牌竖立 ...` 那条之后追加一条：

```markdown
- **3D action hint 屏幕空间化 + 回合倒计时（分支 `agent/feature-uiboard`，纯客户端展示层，规则/协议/快照零改动）**：3D 提示文本从世界空间看板 `hint3d` 改为**屏幕空间顶部居中面板** `HintHud`（`scripts/ui/hint_hud.gd`）：上方**椭圆胶囊倒计时**（默认 30 递减、可为负、边框、左右留白；>10 白 / 1..10 琥珀 / ≤0 红），下方 **hint 文本**。换 hint 播「旧片上移淡出 + 新片掉落回弹」；每回合（`TURN_DRAW` 且 `match_number:current_player` 变化）重置并重播「胶囊先落、hint 后落」。文案集中到 `HintText`（`scripts/ui/hint_text.gd`，英文不变），计时为 `TurnTimer` 纯模型（`scripts/ui/turn_timer.gd`，本地纯展示，未来换服务器 deadline 只改数据源）。2D 与 Ready/条件按钮不动；`hint3d` 只保留按钮。测试 `verify_hint_hud`。
```

- [ ] **Step 2: 更新功能实现文档**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/docs/功能实现文档.md` 的 UI 文件表中（`manual_panel.gd` 行之后）追加两行：

```markdown
| `hint_hud.gd` | 3D action hint 屏幕空间面板（顶部居中：倒计时胶囊 + hint 文本 + 掉落/回弹动画），仅 3D |
| `hint_text.gd` / `turn_timer.gd` | **纯函数/纯模型**：集中 hint 文案表（英文，`main._hint_for` 委托）/ 回合倒计时模型（可负，本地展示） |
```

- [ ] **Step 3: 全量回归**

Run: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tools/run_all_tests.sh --quick`
Expected: 全部 PASS。

Run（核心单进程集，逐个确认全绿）：
```bash
for t in verify_protocol verify_swap verify_duel verify_reconnect verify_kongbaya verify_economy verify_shop verify_relics verify_card_skin verify_table3d_layout verify_table3d verify_table3d_mouse verify_table3d_interaction verify_actions verify_stat_panel verify_card_animation verify_card_fly verify_table3d_exchange verify_q_hold verify_j_swap verify_board3d verify_manual verify_hint verify_hint_hud; do
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . "res://tests/$t.tscn" | tail -1
done
```

- [ ] **Step 4: `git diff` 确认边界**

Run: `git diff origin/main --stat`
Expected: 仅涉及 `scripts/ui/turn_timer.gd`、`scripts/ui/hint_text.gd`、`scripts/ui/hint_hud.gd`、`scripts/ui/main.gd`、`tests/verify_hint_hud.*`、`docs/*`；**无** `scripts/core/*`、`scripts/net/*`、`scenes/ui/table3d.tscn`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`、`board3d.gd`、`key_hint_panel.gd`。

- [ ] **Step 5: 提交**

```bash
git add docs/AI_AGENT_交接说明.md docs/功能实现文档.md
git commit -m "doc: 记录 3D action hint 屏幕空间化 + 回合倒计时"
```

---

## Self-Review

**Spec coverage：**
- §2.1 TurnTimer → Task 1；§2.2 HintText → Task 2；§2.3 HintHud → Task 3；§2.4 main 接线 → Task 4；§3 布局/视觉 → Task 3（胶囊圆角/留白/边框、顶部居中）；§4 计时行为（重置点、可负、配色、显示阶段）→ Task 3 + Task 4；§5 动画（进场 + 换字）→ Task 3；§6 生命周期 → Task 4；§7 测试 → Task 1-5；§8 文件清单 → 全 Task；§9 v2 预留 → TurnTimer 独立 + `_hud_turn_key`；§10 参数 → Task 3 常量。**无缺口。**

**Placeholder scan：** 无 TBD/TODO；每个代码步骤给出完整文件内容或精确 old→new 片段与命令。

**Type consistency：** `TurnTimer.reset/tick/seconds_left/phase/remaining/limit` 在 Task 1 定义并在 Task 3 使用；`HintText.hint/decision` 在 Task 2 定义、Task 4 经 `main._hint_for` 间接使用；`HintHud` 常量与方法名（`PILL_H`/`PILL_H_PAD`/`COLOR_OVER`/`PHASE_TURN_SECONDS`/`set_hint`/`reset_turn`/`set_phase_visible`/`show_hud`/`pill`/`pill_label`/`timer`/`cur_label`/`next_label`/`hint_base_y`）在 Task 3 定义并在 Task 3 测试、Task 4 与 `main` 使用，命名一致。
