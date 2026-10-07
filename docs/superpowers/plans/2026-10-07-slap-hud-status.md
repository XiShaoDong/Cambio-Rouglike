# SLAP 状态行 + 装饰进度条 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 3D `HintHud` 顶部居中面板中，把 "SLAP open" 拆成独立一行（绿色 `SLAP OPEN` / 成功贴牌后红色 `SLAP CLOSE`），并在其下方加一条固定时长（10s）满→空的装饰进度条；文字与条全部居中；走空即整行消失。

**Architecture:** 纯客户端展示层，仅改 `HintHud`（新增 `_slap_label` + `_slap_bar` 与状态机）、`main._update_hint_hud`（喂状态）、`HintText`（移除后缀）。零协议/快照改动；只用已有的 `slap_open` 与 `phase`。

**Tech Stack:** Godot 4.6 / GDScript；自定义 headless 测试（`tests/verify_hint_hud.tscn`）。

## Global Constraints

- Godot binary：`/Applications/Godot.app/Contents/MacOS/Godot`；测试一律 `--headless`，**不启动 GUI**。
- **仅 3D**（`HintHud`）；不改 2D、`scripts/core/*`、`scripts/net/*`、`scenes/ui/*`。
- 新 `class_name` 不需要；`HintHud` 已存在。仓库跟踪 `.gd.uid`，本次无新增脚本。
- 提交信息按 `feat:` / `fix:` / `doc:`；每 Task 末尾单独提交。
- 装饰条是**纯视觉**，不对应真实窗口时长。

---

### Task 1: `HintHud` 新增 SLAP 状态行 + 装饰进度条

**Files:**
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/hint_hud.gd`
- Test: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.gd`

**Interfaces:**
- Produces（供 Task 2 与测试使用）：常量 `SLAP_HIDDEN=0`/`SLAP_OPEN=1`/`SLAP_CLOSE=2`、`SLAP_BAR_SECONDS`、`SLAP_BAR_W`、`SLAP_BAR_H`、`SLAP_OPEN_COLOR`、`SLAP_CLOSE_COLOR`、`SLAP_TEXT_OPEN`、`SLAP_TEXT_CLOSE`；方法 `set_slap_state(state: int) -> void`；访问器 `slap_label() -> Label`、`slap_bar() -> ProgressBar`、`slap_state() -> int`、`slap_exhausted() -> bool`、`slap_row_visible() -> bool`。

- [ ] **Step 1: 写失败测试**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.gd` 的 `_run()` 中追加一行 `await _test_slap_row()`（放在 `await _test_main_integration()` 之前），并新增函数：

```gdscript
func _test_slap_row() -> void:
	var hud := HintHud.new()
	add_child(hud)
	await get_tree().process_frame
	hud.show_hud(true)
	hud.set_hint("Draw")
	_check("SLAP 初始隐藏", not hud.slap_row_visible())
	hud.set_slap_state(HintHud.SLAP_OPEN)
	_check("OPEN：行可见", hud.slap_row_visible())
	_check("OPEN：绿 SLAP OPEN", hud.slap_label().text == "SLAP OPEN" and hud.slap_label().get_theme_color("font_color") == HintHud.SLAP_OPEN_COLOR)
	_check("OPEN：条可见 value≈1", hud.slap_bar().visible and is_equal_approx(hud.slap_bar().value, 1.0))
	_check("状态行水平居中", hud.slap_label().horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER)
	hud._process(3.0)
	var v_mid: float = hud.slap_bar().value
	hud.set_slap_state(HintHud.SLAP_OPEN)
	_check("同状态重发不重置条", is_equal_approx(hud.slap_bar().value, v_mid) and v_mid < 1.0)
	hud.set_slap_state(HintHud.SLAP_CLOSE)
	_check("CLOSE：红 SLAP CLOSE", hud.slap_label().text == "SLAP CLOSE" and hud.slap_label().get_theme_color("font_color") == HintHud.SLAP_CLOSE_COLOR)
	_check("CLOSE：条隐藏", not hud.slap_bar().visible)
	hud.set_slap_state(HintHud.SLAP_HIDDEN)
	_check("HIDDEN：整行隐藏", not hud.slap_row_visible())
	hud.set_slap_state(HintHud.SLAP_OPEN)
	_check("重开窗口条重置满", is_equal_approx(hud.slap_bar().value, 1.0) and not hud.slap_exhausted())
	hud._process(HintHud.SLAP_BAR_SECONDS + 0.1)
	_check("走空：整行消失", not hud.slap_row_visible() and hud.slap_exhausted())
	hud.set_slap_state(HintHud.SLAP_HIDDEN)
	hud.set_slap_state(HintHud.SLAP_OPEN)
	await get_tree().process_frame
	var w: float = maxf(maxf(hud.pill().get_combined_minimum_size().x, HintHud.HINT_MAX_W), HintHud.SLAP_BAR_W)
	_check("条水平居中", is_equal_approx(hud.slap_bar().position.x, (w - HintHud.SLAP_BAR_W) * 0.5))
	hud.queue_free()
```

- [ ] **Step 2: 运行确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint_hud.tscn`
Expected: `SLAP_*` / `set_slap_state` / `slap_label` 未定义 → FAIL/解析错误（非 0 退出）。

- [ ] **Step 3: 实现**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/hint_hud.gd`：

(a) 在现有 `const ACTIVE_PHASES := [2, 3, 4, 6, 8]` 之后追加常量：

```gdscript
## SLAP 状态行 + 装饰条（纯展示，固定时长不对应真实窗口）。
const SLAP_HIDDEN := 0
const SLAP_OPEN := 1
const SLAP_CLOSE := 2
const SLAP_BAR_SECONDS := 10.0
const SLAP_BAR_W := 260.0
const SLAP_BAR_H := 8.0
const SLAP_FONT := 16
const SLAP_GAP := 6.0
const SLAP_OPEN_COLOR := Color("87d9a1")
const SLAP_CLOSE_COLOR := Color("ff7b7b")
const SLAP_TEXT_OPEN := "SLAP OPEN"
const SLAP_TEXT_CLOSE := "SLAP CLOSE"
```

(b) 在 `var _tween: Tween = null` 之后追加：

```gdscript
var _slap_label: Label
var _slap_bar: ProgressBar
var _slap_state := SLAP_HIDDEN
var _slap_left := 0.0
var _slap_exhausted := false
var _slap_base_y := 0.0
var _slap_bar_y := 0.0
```

(c) 把 `func _process(delta: float) -> void:` 整个函数替换为：

```gdscript
func _process(delta: float) -> void:
	_timer.tick(delta)
	_update_pill_text()
	if _slap_state == SLAP_OPEN and not _slap_exhausted:
		_slap_left -= delta
		if _slap_left <= 0.0:
			_slap_left = 0.0
			_slap_exhausted = true
			_update_slap_visuals()
			_layout()
		elif _slap_bar != null and _slap_bar.visible:
			_slap_bar.value = clampf(_slap_left / SLAP_BAR_SECONDS, 0.0, 1.0)
```

(d) 在 `_build()` 末尾（`_next.visible = false` 之后、函数结束前）追加：

```gdscript
	_slap_label = Label.new()
	_slap_label.name = "SlapLabel"
	_slap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slap_label.custom_minimum_size = Vector2(HINT_MAX_W, 0.0)
	_slap_label.add_theme_font_size_override("font_size", SLAP_FONT)
	_slap_label.add_theme_color_override("font_color", SLAP_OPEN_COLOR)
	_slap_label.visible = false
	add_child(_slap_label)
	_slap_bar = ProgressBar.new()
	_slap_bar.name = "SlapBar"
	_slap_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slap_bar.min_value = 0.0
	_slap_bar.max_value = 1.0
	_slap_bar.value = 1.0
	_slap_bar.show_percentage = false
	_slap_bar.custom_minimum_size = Vector2(SLAP_BAR_W, SLAP_BAR_H)
	_slap_bar.size = Vector2(SLAP_BAR_W, SLAP_BAR_H)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1, 1, 1, 0.18)
	bar_bg.set_corner_radius_all(int(SLAP_BAR_H * 0.5))
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = SLAP_OPEN_COLOR
	bar_fill.set_corner_radius_all(int(SLAP_BAR_H * 0.5))
	_slap_bar.add_theme_stylebox_override("background", bar_bg)
	_slap_bar.add_theme_stylebox_override("fill", bar_fill)
	_slap_bar.visible = false
	add_child(_slap_bar)
```

(e) 把 `func _layout() -> void:` 的函数体替换为（新增 slap 行高度与 y 计算）：

```gdscript
func _layout() -> void:
	if _pill == null:
		return
	var pill_size := _pill.get_combined_minimum_size()
	var hint_h := _cur.get_combined_minimum_size().y
	var slap_h := 0.0
	if _slap_row_visible():
		slap_h = SEP + _slap_label.get_combined_minimum_size().y + SLAP_GAP + SLAP_BAR_H
	var w := maxf(maxf(pill_size.x, HINT_MAX_W), SLAP_BAR_W)
	var h := PILL_H + SEP + hint_h + slap_h
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
	_slap_base_y = _hint_base_y + hint_h + SEP
	_slap_bar_y = _slap_base_y + _slap_label.get_combined_minimum_size().y + SLAP_GAP
	if not _animating:
		_place_all()
```

(f) 把 `func _place_all() -> void:` 替换为：

```gdscript
func _place_all() -> void:
	_pill.position = Vector2(_pill_x, 0.0)
	_hint_a.position = Vector2(0.0, _hint_base_y)
	_hint_b.position = Vector2(0.0, _hint_base_y)
	var w := maxf(maxf(_pill.get_combined_minimum_size().x, HINT_MAX_W), SLAP_BAR_W)
	_slap_label.position = Vector2(0.0, _slap_base_y)
	_slap_bar.position = Vector2((w - SLAP_BAR_W) * 0.5, _slap_bar_y)
```

(g) 在 `_on_swap_done` 之后、访问器区之前追加状态机与视觉：

```gdscript
## SLAP 行是否可见：CLOSE 恒可见；OPEN 且未走空可见；其余隐藏。
func _slap_row_visible() -> bool:
	if _slap_state == SLAP_CLOSE:
		return true
	return _slap_state == SLAP_OPEN and not _slap_exhausted

## 由 main 喂入状态；HIDDEN/CLOSE → OPEN 视为"新窗口"，重置装饰条。
func set_slap_state(state: int) -> void:
	if state == _slap_state:
		return
	var entering_open := state == SLAP_OPEN and _slap_state != SLAP_OPEN
	_slap_state = state
	if entering_open:
		_slap_left = SLAP_BAR_SECONDS
		_slap_exhausted = false
	_update_slap_visuals()
	_layout()

func _update_slap_visuals() -> void:
	if _slap_label == null:
		return
	var vis := _slap_row_visible()
	_slap_label.visible = vis
	_slap_bar.visible = vis and _slap_state == SLAP_OPEN
	if not vis:
		return
	if _slap_state == SLAP_CLOSE:
		_slap_label.text = SLAP_TEXT_CLOSE
		_slap_label.add_theme_color_override("font_color", SLAP_CLOSE_COLOR)
	else:
		_slap_label.text = SLAP_TEXT_OPEN
		_slap_label.add_theme_color_override("font_color", SLAP_OPEN_COLOR)
		_slap_bar.value = clampf(_slap_left / SLAP_BAR_SECONDS, 0.0, 1.0)
```

(h) 在访问器区末尾追加：

```gdscript
func slap_label() -> Label:
	return _slap_label

func slap_bar() -> ProgressBar:
	return _slap_bar

func slap_state() -> int:
	return _slap_state

func slap_exhausted() -> bool:
	return _slap_exhausted

func slap_row_visible() -> bool:
	return _slap_row_visible()
```

- [ ] **Step 4: 运行确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint_hud.tscn`
Expected: 新断言全 PASS（在既有 44 基础上 +约 14 → `HINT_HUD RESULT: 58/58 passed` 左右），退出码 0。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/hint_hud.gd tests/verify_hint_hud.gd
git commit -m "feat: HintHud 新增 SLAP 状态行 + 装饰进度条（绿 OPEN / 红 CLOSE，走空即消失）"
```

---

### Task 2: `main` 接线 + `HintText` 移除后缀 + 文档

**Files:**
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/main.gd`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/hint_text.gd`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/docs/功能实现文档.md`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/docs/AI_AGENT_交接说明.md`
- Test: `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.gd`

**Interfaces:**
- Consumes: `HintHud.set_slap_state` 与 `SLAP_*`（Task 1）。
- Produces: 无新 API。

- [ ] **Step 1: 写失败测试（main 集成）**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/tests/verify_hint_hud.gd` 的 `_test_main_integration()` 中，`_check("3D 下 HintHud 可见", ...)` 之后插入：

```gdscript
	_check("slap_open=false → HUD slap HIDDEN", main_node._hint_hud.slap_state() == HintHud.SLAP_HIDDEN)
	main_node.latest_state = _main_state()
	main_node.latest_state["slap_open"] = true
	main_node._refresh_hint_panel()
	await get_tree().process_frame
	_check("slap_open=true → HUD slap OPEN", main_node._hint_hud.slap_state() == HintHud.SLAP_OPEN)
	main_node.latest_state["phase"] = 6
	main_node.latest_state["slap_open"] = false
	main_node._refresh_hint_panel()
	await get_tree().process_frame
	_check("SLAP_EXCHANGE → HUD slap CLOSE", main_node._hint_hud.slap_state() == HintHud.SLAP_CLOSE)
```

- [ ] **Step 2: 运行确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint_hud.tscn`
Expected: 三条新断言 FAIL（`_update_hint_hud` 尚未喂 slap 状态）。

- [ ] **Step 3: `main._update_hint_hud` 喂状态**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/main.gd` 的 `_update_hint_hud` 中，把：

```gdscript
	var text := _hint_for(phase, viewer == current)
	_hint_hud.set_phase_visible(phase)
```

替换为：

```gdscript
	var text := _hint_for(phase, viewer == current)
	_hint_hud.set_phase_visible(phase)
	var slap_state := HintHud.SLAP_HIDDEN
	if phase == PHASE_SLAP_EXCHANGE or phase == PHASE_SLAP_DUEL:
		slap_state = HintHud.SLAP_CLOSE
	elif bool(latest_state.get("slap_open", false)):
		slap_state = HintHud.SLAP_OPEN
	_hint_hud.set_slap_state(slap_state)
```

- [ ] **Step 4: `HintText` 移除 slap 后缀**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/scripts/ui/hint_text.gd` 中，把 `TURN_DRAW` 分支：

```gdscript
		GameState.Phase.TURN_DRAW:
			var slap_note := ""
			if bool(state.get("slap_open", false)):
				slap_note = " · SLAP open: click matching card"
			if is_current:
				return "Draw from the deck or the discard pile (discard top only replaces)" + slap_note
			return "Waiting for %s to draw a card" % name + slap_note
```

替换为：

```gdscript
		GameState.Phase.TURN_DRAW:
			if is_current:
				return "Draw from the deck or the discard pile (discard top only replaces)"
			return "Waiting for %s to draw a card" % name
```

- [ ] **Step 5: 运行新测试 + 回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint_hud.tscn`
Expected: `HINT_HUD RESULT: 61/61 passed` 左右，全绿。

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_hint.tscn`
Expected: `HINT RESULT: 8/8 passed`。

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_board3d.tscn`
Expected: 全绿（52/52 或当前数）。

- [ ] **Step 6: 文档**

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/docs/AI_AGENT_交接说明.md` 的 §2 中「3D action hint 屏幕空间化 + 回合倒计时」那条末尾追加：

```markdown
另新增 **SLAP 状态行 + 装饰进度条**：hint 文本下方独立一行（绿 `SLAP OPEN` / 成功贴牌后红 `SLAP CLOSE`，仅 3D），其下固定 10s 满→空的**装饰**进度条（纯视觉、不对应真实窗口时长）；走空即整行消失；`HintText` 的 TURN_DRAW 后缀已移除。状态由 `main._update_hint_hud` 依 `slap_open`/`phase` 喂入 `HintHud.set_slap_state`。
```

在 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/docs/功能实现文档.md` 的「3D action hint 屏幕空间化 + 回合倒计时」blockquote 末尾追加：

```markdown
另含 **SLAP 状态行 + 装饰进度条**（绿 OPEN / 红 CLOSE，固定 10s 满→空、走空整行消失，仅 3D）。
```

- [ ] **Step 7: 提交**

```bash
git add scripts/ui/main.gd scripts/ui/hint_text.gd tests/verify_hint_hud.gd docs/AI_AGENT_交接说明.md docs/功能实现文档.md
git commit -m "feat: main 接线 SLAP 状态行/装饰条；HintText 移除 slap 后缀；文档"
```

---

## Self-Review

**Spec coverage：** §2 数据 → 无代码（已存在）；§3 状态机 → Task 1 `set_slap_state`/`_slap_row_visible` + Task 2 喂状态；§4 布局/居中/条 → Task 1 `_layout`/`_place_all`/`_build`（`horizontal_alignment=CENTER`、条居中）；§5 文案 → Task 2 HintText；§6 接线 → Task 2；§7 测试 → Task 1 + Task 2；§8 文件 → 全 Task；§9 参数 → Task 1 常量。**无缺口。**

**Placeholder scan：** 无 TBD/TODO；每步给出完整代码或精确 old→new。

**Type consistency：** `SLAP_*` 常量、`set_slap_state`、`slap_label/slap_bar/slap_state/slap_exhausted/slap_row_visible` 在 Task 1 定义、Task 1 测试与 Task 2 使用，命名一致。`HINT_MAX_W`/`SEP`/`PILL_H` 为既有常量。
