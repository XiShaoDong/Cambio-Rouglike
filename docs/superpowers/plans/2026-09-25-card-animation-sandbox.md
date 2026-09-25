# 卡牌交互动效系统（3D 沙盒原型）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用「分层 Offset 合成 + 标量进度 + 纯函数」在独立 3D 沙盒里实现 IDLE 悬浮 / HOVER 抬起倾斜 / PRESS / 真实 3D 翻牌 / LAND 回弹 + blob 阴影响应。

**Architecture:** 三层——`CardAnimationConfig`（集中参数）、`CardAnimationMath`（纯函数：状态机/缓动/高度/阴影/compose）、`CardAnimation`（控制器：Tween 只驱动标量，唯一写 transform 处是每帧调 compose）。沙盒 `CardAnimationSandbox` 复用 `Table3dCamera` / `Table3dPicker` / `Crosshair`，一排 5 张卡，中心准星 + 鼠标转相机，左键翻牌。不接游戏逻辑。

**Tech Stack:** Godot 4.6 GDScript、`Node3D`/`Basis`/`PlaneMesh`/`Tween`、headless `.tscn` 测试。

**Spec:** `docs/superpowers/specs/2026-09-25-card-animation-sandbox-design.md`

## Global Constraints

- 分支 `feature/3d-table`。提交按 `feat:` / `test:` / `fix:` / `doc:` 分类；新增 `.gd` 同时 `git add` 其 `.uid`（用 `--headless --path . --import` 生成）。
- **不改**：`scripts/core/*`、`scripts/net/*`、`scripts/ui/main.gd`、`scripts/ui/table3d_view.gd`、`scenes/ui/table3d.tscn`、2D 卡牌相关、现有测试（`verify_table3d_interaction` 仅作回归，不改）。
- 沙盒为独立场景，**不接入**游戏；规则/协议/快照零改动。
- 3D 位移用**卡牌相对单位**（1.0 = `Table3dLayout.BLOCK_SIZE.z`）。
- 验证命令：
  - 编译：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5`
  - 单测：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/<scene>.tscn`
  - 全量（快）：`tools/run_all_tests.sh --quick`
  - 若报 `Identifier "X" not declared`：先 `--headless --path . --import` 重建类缓存。
- 不启 GUI 做自动化验证。

---

## File Structure

| 文件 | 职责 |
| --- | --- |
| `scripts/ui/card_animation_config.gd`（新） | 全部动效参数默认值 + `to_dict()` + `validate()` |
| `scripts/ui/card_animation_math.gd`（新） | 纯函数：状态机 / 缓动 / 高度 / 阴影 / `compose` |
| `scripts/ui/card_animation.gd`（新） | 控制器：标量进度 + 每帧应用 + 输入事件 + `play` 语义 |
| `scripts/ui/card_animation_sandbox.gd`（新） | 沙盒根：建 5 卡 / 输入 / 准星 / HUD / `play()` |
| `scenes/ui/card_animation_sandbox.tscn`（新） | 沙盒静态骨架（环境/相机/桌） |
| `scripts/ui/card_block.gd`（改） | 新增 `show_back(back: bool)` |
| `scripts/ui/table3d_picker.gd`（改） | `pick_hit` 返回值增加 `"position"`（命中点） |
| `tests/verify_card_animation.gd` + `.tscn`（新） | 纯函数 + 节点测试 |
| `tools/run_all_tests.sh`（改） | 注册新测试 |
| `docs/AI_AGENT_交接说明.md`（改） | §4 类表 + §8 测试命令 |

---

### Task 1: CardAnimationConfig（参数集中 + 校验）

**Files:**
- Create: `scripts/ui/card_animation_config.gd`
- Create: `tests/verify_card_animation.gd`
- Create: `tests/verify_card_animation.tscn`

**Interfaces:**
- Consumes: 无
- Produces:
  - `CardAnimationConfig`：字段 `idle_amp: float`、`idle_speed: float`、`idle_rot_z: float`、`idle_rot_x: float`、`hover_lift: float`、`hover_scale: float`、`hover_pitch: float`、`max_tilt: float`、`hover_in_dur: float`、`hover_out_dur: float`、`press_dur: float`、`press_min: float`、`press_over: float`、`flip_dur: float`、`flip_lift: float`、`land_dur: float`、`land_over: float`、`land_under: float`、`shadow_base_alpha: float`、`shadow_scale_loss: float`、`shadow_alpha_loss: float`
  - `const KEYS: Array`
  - `func to_dict() -> Dictionary`（键同字段名）
  - `func validate() -> Array`（返回非法字段名）

- [ ] **Step 1: 写失败测试**

Create `tests/verify_card_animation.gd`:

```gdscript
extends Node
## headless 单元测试：卡牌交互动效（配置 / 纯数学 / 控制器 / 沙盒）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== CARD ANIMATION RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_config()

func _test_config() -> void:
	var c := CardAnimationConfig.new()
	_check("config 默认值合法", c.validate().is_empty())
	_check("config to_dict 键数", c.to_dict().size() == CardAnimationConfig.KEYS.size())
	_check("config 默认 hover_lift", is_equal_approx(c.hover_lift, 0.12))
	var bad := CardAnimationConfig.new()
	bad.hover_lift = -1.0
	_check("config 非法值被抓", bad.validate().has("hover_lift"))
```

Create `tests/verify_card_animation.tscn`:

```
[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://tests/verify_card_animation.gd" id="1"]
[node name="VerifyCardAnimation" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_animation.tscn`
Expected: 报 `CardAnimationConfig` 未声明 / 脚本解析失败。

- [ ] **Step 3: 实现**

Create `scripts/ui/card_animation_config.gd`:

```gdscript
class_name CardAnimationConfig
extends RefCounted
## 卡牌交互动效参数（集中配置；代码不出现散落魔法数）。
## 控制器按字段访问；纯数学按 to_dict() 访问。

var idle_amp := 0.03
var idle_speed := 1.2
var idle_rot_z := 0.5
var idle_rot_x := 0.3
var hover_lift := 0.12
var hover_scale := 1.06
var hover_pitch := 28.0
var max_tilt := 4.0
var hover_in_dur := 0.12
var hover_out_dur := 0.20
var press_dur := 0.08
var press_min := 0.97
var press_over := 1.02
var flip_dur := 0.34
var flip_lift := 0.25
var land_dur := 0.12
var land_over := 1.04
var land_under := 0.99
var shadow_base_alpha := 0.5
var shadow_scale_loss := 0.30
var shadow_alpha_loss := 0.50

const KEYS := [
	"idle_amp", "idle_speed", "idle_rot_z", "idle_rot_x",
	"hover_lift", "hover_scale", "hover_pitch", "max_tilt",
	"hover_in_dur", "hover_out_dur", "press_dur", "press_min", "press_over",
	"flip_dur", "flip_lift", "land_dur", "land_over", "land_under",
	"shadow_base_alpha", "shadow_scale_loss", "shadow_alpha_loss",
]

func to_dict() -> Dictionary:
	var d := {}
	for k in KEYS:
		d[k] = get(k)
	return d

## 字段值是否全部有限且非负；返回非法字段名数组。
func validate() -> Array:
	var bad: Array = []
	for k in KEYS:
		var v := float(get(k))
		if not is_finite(v) or v < 0.0:
			bad.append(k)
	return bad
```

- [ ] **Step 4: 生成 .uid 并运行测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import`
Then: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_animation.tscn`
Expected: `=== CARD ANIMATION RESULT: 4/4 passed ===`

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/card_animation_config.gd scripts/ui/card_animation_config.gd.uid tests/verify_card_animation.gd tests/verify_card_animation.gd.uid tests/verify_card_animation.tscn
git commit -m "feat: CardAnimationConfig 动效参数集中配置 + 测试"
```

---

### Task 2: CardAnimationMath（状态机 + 缓动）

**Files:**
- Create: `scripts/ui/card_animation_math.gd`
- Modify: `tests/verify_card_animation.gd`

**Interfaces:**
- Consumes: 无
- Produces（`CardAnimationMath`，全 `static`）：
  - 状态常量：`IDLE := 0`、`HOVER := 1`、`PRESS := 2`、`FLIP := 3`、`LAND := 4`
  - 事件常量：`EV_ENTER := "enter"`、`EV_EXIT := "exit"`、`EV_CLICK := "click"`、`EV_TIMER := "timer"`
  - `static func next_state(cur: int, event: String, hovering: bool, flip_done: bool, land_done: bool) -> int`
  - `static func ease_out_cubic(t: float) -> float`
  - `static func ease_in_out_cubic(t: float) -> float`
  - `static func ease_out_back(t: float, s := 1.70158) -> float`
  - `static func lerp_f(a: float, b: float, t: float) -> float`

- [ ] **Step 1: 写失败测试**

在 `tests/verify_card_animation.gd` 的 `_run()` 追加：

```gdscript
	_test_state_machine()
	_test_easing()
```

追加函数：

```gdscript
func _test_state_machine() -> void:
	var M := CardAnimationMath
	_check("IDLE + enter → HOVER", M.next_state(M.IDLE, M.EV_ENTER, true, false, false) == M.HOVER)
	_check("IDLE + click 无效", M.next_state(M.IDLE, M.EV_CLICK, false, false, false) == M.IDLE)
	_check("HOVER + exit → IDLE", M.next_state(M.HOVER, M.EV_EXIT, false, false, false) == M.IDLE)
	_check("HOVER + click → PRESS", M.next_state(M.HOVER, M.EV_CLICK, true, false, false) == M.PRESS)
	_check("PRESS + exit 不中断", M.next_state(M.PRESS, M.EV_EXIT, false, false, false) == M.PRESS)
	_check("PRESS + timer → FLIP", M.next_state(M.PRESS, M.EV_TIMER, true, false, false) == M.FLIP)
	_check("FLIP + click 无效", M.next_state(M.FLIP, M.EV_CLICK, true, false, false) == M.FLIP)
	_check("FLIP + timer 未完成仍 FLIP", M.next_state(M.FLIP, M.EV_TIMER, true, false, false) == M.FLIP)
	_check("FLIP + timer 完成 → LAND", M.next_state(M.FLIP, M.EV_TIMER, true, true, false) == M.LAND)
	_check("LAND + timer 完成且悬停 → HOVER", M.next_state(M.LAND, M.EV_TIMER, true, true, true) == M.HOVER)
	_check("LAND + timer 完成且未悬停 → IDLE", M.next_state(M.LAND, M.EV_TIMER, false, true, true) == M.IDLE)

func _test_easing() -> void:
	var M := CardAnimationMath
	_check("ease_out_cubic 端点", is_equal_approx(M.ease_out_cubic(0.0), 0.0) and is_equal_approx(M.ease_out_cubic(1.0), 1.0))
	_check("ease_out_cubic 单调", M.ease_out_cubic(0.3) < M.ease_out_cubic(0.6))
	_check("ease_in_out_cubic 端点", is_equal_approx(M.ease_in_out_cubic(0.0), 0.0) and is_equal_approx(M.ease_in_out_cubic(1.0), 1.0))
	_check("ease_out_back 端点", is_equal_approx(M.ease_out_back(0.0), 0.0) and is_equal_approx(M.ease_out_back(1.0), 1.0))
	_check("ease_out_back 过冲", M.ease_out_back(0.7) > 1.0)
	_check("lerp_f 中点", is_equal_approx(M.lerp_f(0.0, 10.0, 0.5), 5.0))
```

- [ ] **Step 2: 运行测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_animation.tscn`
Expected: 报 `CardAnimationMath` 未声明。

- [ ] **Step 3: 实现**

Create `scripts/ui/card_animation_math.gd`:

```gdscript
class_name CardAnimationMath
extends RefCounted
## 卡牌交互动效纯数学：状态机 / 缓动 / 高度 / 阴影 / 变换合成。
## 无节点依赖 → headless 可测。唯一写 transform 处由控制器调用 compose 完成。

const IDLE := 0
const HOVER := 1
const PRESS := 2
const FLIP := 3
const LAND := 4

const EV_ENTER := "enter"
const EV_EXIT := "exit"
const EV_CLICK := "click"
const EV_TIMER := "timer"

## 状态转移（纯函数）。PRESS/FLIP/LAND 中的 EXIT/CLICK 不打断（防连击）。
static func next_state(cur: int, event: String, hovering: bool, flip_done: bool, land_done: bool) -> int:
	match cur:
		IDLE:
			return HOVER if event == EV_ENTER else IDLE
		HOVER:
			if event == EV_EXIT:
				return IDLE
			if event == EV_CLICK:
				return PRESS
			return HOVER
		PRESS:
			return FLIP if event == EV_TIMER else PRESS
		FLIP:
			if event == EV_TIMER and flip_done:
				return LAND
			return FLIP
		LAND:
			if event == EV_TIMER and land_done:
				return HOVER if hovering else IDLE
			return LAND
	return cur

static func ease_out_cubic(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)

static func ease_in_out_cubic(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if t < 0.5:
		return 4.0 * t * t * t
	return 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0

static func ease_out_back(t: float, s := 1.70158) -> float:
	t = clampf(t, 0.0, 1.0)
	var c3 := s + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + s * pow(t - 1.0, 2.0)

static func lerp_f(a: float, b: float, t: float) -> float:
	return a + (b - a) * clampf(t, 0.0, 1.0)
```

- [ ] **Step 4: 生成 .uid 并运行测试确认通过**

Run: `--headless --path . --import` then `--headless --path . res://tests/verify_card_animation.tscn`
Expected: `21/21 passed`（4 + 17）。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/card_animation_math.gd scripts/ui/card_animation_math.gd.uid tests/verify_card_animation.gd
git commit -m "feat: CardAnimationMath 状态机与缓动纯函数 + 测试"
```

---

### Task 3: CardAnimationMath（高度 / 阴影 / compose）

**Files:**
- Modify: `scripts/ui/card_animation_math.gd`
- Modify: `tests/verify_card_animation.gd`

**Interfaces:**
- Consumes: `CardAnimationConfig.KEYS`（字典键）
- Produces（追加到 `CardAnimationMath`）：
  - `static func press_scale(p: float, cfg: Dictionary) -> float`
  - `static func land_scale(l: float, cfg: Dictionary) -> float`
  - `static func height(progress: Dictionary, cfg: Dictionary, idle_time: float) -> float`
  - `static func shadow_scale_for(height_value: float, cfg: Dictionary) -> float`
  - `static func shadow_alpha_for(height_value: float, cfg: Dictionary) -> float`
  - `static func compose(progress: Dictionary, cfg: Dictionary, idle_time: float, ray_local: Vector2) -> Dictionary` → 键 `visual_pos: Vector3`、`visual_rot_deg: Vector3`、`flip_deg: float`、`visual_scale: float`、`shadow_scale: float`、`shadow_alpha: float`

- [ ] **Step 1: 写失败测试**

在 `_run()` 追加 `_test_height_shadow_compose()`，并追加：

```gdscript
func _test_height_shadow_compose() -> void:
	var M := CardAnimationMath
	var cd := CardAnimationConfig.new().to_dict()
	_check("height t=0 ≈0", absf(M.height({"hover": 0.0, "flip": 0.0}, cd, 0.0)) < 0.0001)
	_check("height hover=1 抑制 idle", is_equal_approx(M.height({"hover": 1.0, "flip": 0.0}, cd, 1.0), cd["hover_lift"]))
	_check("height flip=0.5 峰值", is_equal_approx(M.height({"hover": 0.0, "flip": 0.5}, cd, 0.0), cd["flip_lift"]))
	_check("shadow h=0 scale=1", is_equal_approx(M.shadow_scale_for(0.0, cd), 1.0))
	_check("shadow h=0 alpha=base", is_equal_approx(M.shadow_alpha_for(0.0, cd), cd["shadow_base_alpha"]))
	var maxh: float = cd["hover_lift"] + cd["flip_lift"]
	_check("shadow h=max scale", is_equal_approx(M.shadow_scale_for(maxh, cd), 1.0 - cd["shadow_scale_loss"]))
	_check("shadow h=max alpha", is_equal_approx(M.shadow_alpha_for(maxh, cd), cd["shadow_base_alpha"] * (1.0 - cd["shadow_alpha_loss"])))
	_check("press 0 → 1", is_equal_approx(M.press_scale(0.0, cd), 1.0))
	_check("press 1 → 1", is_equal_approx(M.press_scale(1.0, cd), 1.0))
	_check("press 三段最低 ≈ min", M.press_scale(0.33, cd) <= cd["press_min"] + 0.001)
	_check("press 三段过冲 ≈ over", M.press_scale(0.66, cd) >= cd["press_over"] - 0.001)
	_check("land 0 → 1", is_equal_approx(M.land_scale(0.0, cd), 1.0))
	_check("land 1 → 1", is_equal_approx(M.land_scale(1.0, cd), 1.0))
	var c := M.compose({"hover": 1.0, "press": 0.0, "flip": 0.0, "land": 0.0}, cd, 0.0, Vector2.ZERO)
	_check("compose hover 位移", is_equal_approx((c["visual_pos"] as Vector3).y, cd["hover_lift"]))
	_check("compose hover 缩放", is_equal_approx(float(c["visual_scale"]), cd["hover_scale"]))
	_check("compose hover 仰角", is_equal_approx((c["visual_rot_deg"] as Vector3).x, cd["hover_pitch"]))
	var cf := M.compose({"hover": 0.0, "press": 0.0, "flip": 0.5, "land": 0.0}, cd, 0.0, Vector2.ZERO)
	_check("compose flip_deg 90", is_equal_approx(float(cf["flip_deg"]), 90.0))
	_check("compose flip 高度峰值", is_equal_approx((cf["visual_pos"] as Vector3).y, cd["flip_lift"]))
	var ct := M.compose({"hover": 0.0, "press": 0.0, "flip": 0.0, "land": 0.0}, cd, 0.0, Vector2(0.5, -0.5))
	_check("compose 准星 tilt 方向", (ct["visual_rot_deg"] as Vector3).x > 0.0 and (ct["visual_rot_deg"] as Vector3).y > 0.0)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `--headless --path . res://tests/verify_card_animation.tscn`
Expected: 报 `press_scale` / `compose` 未声明。

- [ ] **Step 3: 实现**

追加到 `scripts/ui/card_animation_math.gd`：

```gdscript
## 压缩曲线：0→press_min→press_over→1（t 0..1，三段 ease_out_cubic）。
static func press_scale(p: float, cfg: Dictionary) -> float:
	p = clampf(p, 0.0, 1.0)
	var mn: float = cfg["press_min"]
	var ov: float = cfg["press_over"]
	if p < 0.33:
		return lerp_f(1.0, mn, ease_out_cubic(p / 0.33))
	if p < 0.66:
		return lerp_f(mn, ov, ease_out_cubic((p - 0.33) / 0.33))
	return lerp_f(ov, 1.0, ease_out_cubic((p - 0.66) / 0.34))

## 落牌回弹曲线：0→land_over→land_under→1。
static func land_scale(l: float, cfg: Dictionary) -> float:
	l = clampf(l, 0.0, 1.0)
	var ov: float = cfg["land_over"]
	var un: float = cfg["land_under"]
	if l < 0.4:
		return lerp_f(1.0, ov, ease_out_cubic(l / 0.4))
	if l < 0.75:
		return lerp_f(ov, un, ease_out_cubic((l - 0.4) / 0.35))
	return lerp_f(un, 1.0, ease_out_cubic((l - 0.75) / 0.25))

## 离桌高度：idle 悬浮（hover 时抑制）+ hover 抬升 + 翻牌弧线。
static func height(progress: Dictionary, cfg: Dictionary, idle_time: float) -> float:
	var hover := float(progress.get("hover", 0.0))
	var flip := float(progress.get("flip", 0.0))
	var idle := float(cfg["idle_amp"]) * (1.0 - hover) * sin(idle_time * float(cfg["idle_speed"]))
	var flip_arc := float(cfg["flip_lift"]) * sin(flip * PI)
	return idle + float(cfg["hover_lift"]) * hover + flip_arc

static func _height_norm(height_value: float, cfg: Dictionary) -> float:
	var max_h := float(cfg["hover_lift"]) + float(cfg["flip_lift"])
	return clampf(height_value / max_h, 0.0, 1.0) if max_h > 0.0 else 0.0

static func shadow_scale_for(height_value: float, cfg: Dictionary) -> float:
	return 1.0 - _height_norm(height_value, cfg) * float(cfg["shadow_scale_loss"])

static func shadow_alpha_for(height_value: float, cfg: Dictionary) -> float:
	return float(cfg["shadow_base_alpha"]) * (1.0 - _height_norm(height_value, cfg) * float(cfg["shadow_alpha_loss"]))

## 合成本帧变换偏移。flip 单独返回（控制器按卡长轴用 Basis 组合，不受仰角影响）。
static func compose(progress: Dictionary, cfg: Dictionary, idle_time: float, ray_local: Vector2) -> Dictionary:
	var hover := clampf(float(progress.get("hover", 0.0)), 0.0, 1.0)
	var press := clampf(float(progress.get("press", 0.0)), 0.0, 1.0)
	var flip := clampf(float(progress.get("flip", 0.0)), 0.0, 1.0)
	var land := clampf(float(progress.get("land", 0.0)), 0.0, 1.0)
	var h := height(progress, cfg, idle_time)
	var hold_x := cos(idle_time * 0.5) * float(cfg["idle_rot_x"]) * (1.0 - hover)
	var hold_z := sin(idle_time * 0.7) * float(cfg["idle_rot_z"]) * (1.0 - hover)
	var rot_x := hold_x + float(cfg["hover_pitch"]) * hover - ray_local.y * float(cfg["max_tilt"])
	var rot_y := ray_local.x * float(cfg["max_tilt"])
	var scale := (1.0 + (float(cfg["hover_scale"]) - 1.0) * hover) * press_scale(press, cfg) * land_scale(land, cfg)
	return {
		"visual_pos": Vector3(0.0, h, 0.0),
		"visual_rot_deg": Vector3(rot_x, rot_y, hold_z),
		"flip_deg": flip * 180.0,
		"visual_scale": scale,
		"shadow_scale": shadow_scale_for(h, cfg),
		"shadow_alpha": shadow_alpha_for(h, cfg),
	}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `--headless --path . res://tests/verify_card_animation.tscn`
Expected: `40/40 passed`（21 + 19）。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/card_animation_math.gd tests/verify_card_animation.gd
git commit -m "feat: CardAnimationMath 高度/阴影/compose 纯函数 + 测试"
```

---

### Task 4: CardBlock.show_back（切面）

**Files:**
- Modify: `scripts/ui/card_block.gd`
- Modify: `tests/verify_card_animation.gd`

**Interfaces:**
- Consumes: `CardBlock._build()`、`_apply_slot(slot)`、`_back_texture()`、`_last_slot`
- Produces: `CardBlock.show_back(back: bool) -> void` —— `true` 显示卡背并清空点数；`false` 恢复最近 `setup(slot)` 的正面
- 既有 `setup` / `label_text` / `has_face_texture` / `has_back_texture` 保持不变

- [ ] **Step 1: 写失败测试**

在 `_run()` 追加 `_test_show_back()`，并追加：

```gdscript
func _test_show_back() -> void:
	var b := CardBlock.new()
	add_child(b)
	b.setup({"card": {"rank": "A", "suit": "♥"}})
	_check("初始正面点数", b.label_text() == "A♥" and b.has_face_texture())
	b.show_back(true)
	_check("切背面：卡背贴图", b.has_back_texture())
	_check("切背面：隐藏点数", b.label_text() == "")
	b.show_back(false)
	_check("回正面：点数恢复", b.label_text() == "A♥" and b.has_face_texture())
```

- [ ] **Step 2: 运行测试确认失败**

Run: `--headless --path . res://tests/verify_card_animation.tscn`
Expected: 报 `show_back` 未定义（Invalid call）。

- [ ] **Step 3: 实现**

在 `scripts/ui/card_block.gd` 的 `_apply_color()` 之后（`_paint_glow()` 之前）插入：

```gdscript
## 切换显示面：back=true 显示卡背并隐藏点数；false 恢复最近 setup(slot) 的正面。
## 供 CardAnimation 控制器独占的真实 3D 翻牌使用（不触发自带 scale.x 翻转）。
func show_back(back: bool) -> void:
	_build()
	if back:
		_showing_back = true
		_material.albedo_texture = _back_texture()
		_material.albedo_color = Color.WHITE
		_label.text = ""
		_paint_glow()
	else:
		_apply_slot(_last_slot)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `--headless --path . res://tests/verify_card_animation.tscn`
Expected: `44/44 passed`（40 + 4）。

- [ ] **Step 5: 回归既有 CardBlock 测试并提交**

Run: `--headless --path . res://tests/verify_table3d.tscn`
Expected: 36/36 passed。

```bash
git add scripts/ui/card_block.gd tests/verify_card_animation.gd
git commit -m "feat: CardBlock.show_back 切面（供 3D 真实翻牌）+ 测试"
```

---

### Task 5: CardAnimation 控制器

**Files:**
- Create: `scripts/ui/card_animation.gd`
- Modify: `tests/verify_card_animation.gd`

**Interfaces:**
- Consumes: `CardAnimationConfig`、`CardAnimationMath`、`CardBlock`、`Table3dLayout.BLOCK_SIZE`
- Produces（`CardAnimation : Node3D`）：
  - `@export var card_data: Dictionary`
  - `var config: CardAnimationConfig`
  - `var state: int`、`var hovering: bool`、`var showing_back: bool`、`var ray_local: Vector2`
  - `var hover_p: float`、`var press_p: float`、`var flip_p: float`、`var land_p: float`、`var flip_turns: int`
  - `var visual: Node3D`、`var shadow: MeshInstance3D`、`var body: CardBlock`
  - `func enter_hover() -> void`、`func exit_hover() -> void`、`func click() -> void`、`func reset() -> void`

- [ ] **Step 1: 写失败测试**

在 `_run()` 追加 `await _test_controller()`，并追加：

```gdscript
func _test_controller() -> void:
	var a := CardAnimation.new()
	a.config = CardAnimationConfig.new()
	add_child(a)
	await get_tree().process_frame
	_check("控制器已建节点", a.visual != null and a.shadow != null and a.body != null)
	a.enter_hover()
	await get_tree().create_timer(a.config.hover_in_dur + 0.05).timeout
	_check("hover 抬升", a.visual.position.y > 0.0)
	_check("hover 阴影缩小", a.shadow.scale.x < 1.0)
	var mat: StandardMaterial3D = a.shadow.material_override
	_check("hover 阴影变淡", mat.albedo_color.a < a.config.shadow_base_alpha)
	a.click()
	await get_tree().create_timer(a.config.press_dur + 0.03).timeout
	_check("点击后进入 FLIP", a.state == CardAnimationMath.FLIP)
	a.click()
	await get_tree().create_timer(0.02).timeout
	_check("FLIP 中点击被忽略", a.state == CardAnimationMath.FLIP)
	await get_tree().create_timer(a.config.flip_dur + a.config.land_dur + 0.15).timeout
	_check("翻牌后显示背面", a.showing_back)
	_check("翻牌后仍悬停 → HOVER", a.state == CardAnimationMath.HOVER)
	_check("land 后缩放≈hover_scale", absf(a.visual.scale.x - a.config.hover_scale) < 0.03)
	a.exit_hover()
	await get_tree().create_timer(a.config.hover_out_dur + 0.05).timeout
	# IDLE 会恢复 idle 悬浮（±idle_amp），故只校验状态与不再抬升
	_check("离开悬停 → IDLE", a.state == CardAnimationMath.IDLE and absf(a.visual.position.y) <= a.config.idle_amp + 0.001)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `--headless --path . res://tests/verify_card_animation.tscn`
Expected: 报 `CardAnimation` 未声明。

- [ ] **Step 3: 实现**

Create `scripts/ui/card_animation.gd`:

```gdscript
class_name CardAnimation
extends Node3D
## 卡牌动效控制器：Tween 只驱动标量进度，每帧唯一写 transform 处是 compose。
## 纯展示层：不做规则/隐私判断。

@export var card_data: Dictionary = {"rank": "A", "suit": "♥"}

var config: CardAnimationConfig = CardAnimationConfig.new()
var state := CardAnimationMath.IDLE
var hovering := false
var showing_back := false
var ray_local := Vector2.ZERO

var hover_p := 0.0
var press_p := 0.0
var flip_p := 0.0
var land_p := 0.0
var flip_turns := 0

var visual: Node3D
var body: CardBlock
var shadow: MeshInstance3D

var _idle_time := 0.0
var _tweens := {}

func _ready() -> void:
	_build()
	set_process(true)

func _build() -> void:
	if visual != null:
		return
	visual = Node3D.new()
	visual.name = "VisualRoot"
	add_child(visual)
	body = CardBlock.new()
	body.name = "CardBody"
	visual.add_child(body)
	body.setup({"card": card_data})
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Y
	plane.size = Vector2(Table3dLayout.BLOCK_SIZE.x, Table3dLayout.BLOCK_SIZE.z)
	shadow = MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = plane
	shadow.position = Vector3(0.0, 0.002, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.0, 0.0, 0.0, config.shadow_base_alpha)
	shadow.material_override = mat
	add_child(shadow)
	_apply()

func _progress() -> Dictionary:
	return {"hover": hover_p, "press": press_p, "flip": flip_p, "land": land_p}

func _process(delta: float) -> void:
	_idle_time += delta
	_apply()

func _apply() -> void:
	if visual == null:
		return
	var c := CardAnimationMath.compose(_progress(), config.to_dict(), _idle_time, ray_local)
	var rot: Vector3 = c["visual_rot_deg"]
	var rot_basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	# 翻牌绕卡长轴（local Z），叠加在 hover 仰角之后；flip_turns 累计避免下一次翻牌回弹
	rot_basis = rot_basis * Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(float(flip_turns) * 180.0 + float(c["flip_deg"])))
	visual.transform = Transform3D(rot_basis.scaled(Vector3.ONE * float(c["visual_scale"])), c["visual_pos"])
	shadow.scale = Vector3(float(c["shadow_scale"]), 1.0, float(c["shadow_scale"]))
	var mat: StandardMaterial3D = shadow.material_override
	mat.albedo_color = Color(0.0, 0.0, 0.0, float(c["shadow_alpha"]))
	var vis_back := (flip_turns % 2) == 1
	if state == CardAnimationMath.FLIP:
		vis_back = ((flip_turns + (1 if flip_p >= 0.5 else 0)) % 2) == 1
	if vis_back != showing_back:
		showing_back = vis_back
		body.show_back(showing_back)

func _tween_prop(prop: String, to: float, dur: float, trans: int, ease: int) -> Tween:
	if _tweens.has(prop):
		var old: Tween = _tweens[prop]
		if old != null and old.is_valid():
			old.kill()
	var tw := create_tween()
	_tweens[prop] = tw
	tw.tween_property(self, prop, to, dur).set_trans(trans).set_ease(ease)
	return tw

func enter_hover() -> void:
	hovering = true
	if state == CardAnimationMath.FLIP or state == CardAnimationMath.LAND:
		return
	state = CardAnimationMath.HOVER
	_tween_prop("hover_p", 1.0, config.hover_in_dur, Tween.TRANS_BACK, Tween.EASE_OUT)

func exit_hover() -> void:
	hovering = false
	if state == CardAnimationMath.FLIP or state == CardAnimationMath.LAND:
		return
	state = CardAnimationMath.IDLE
	_tween_prop("hover_p", 0.0, config.hover_out_dur, Tween.TRANS_CUBIC, Tween.EASE_OUT)

func click() -> void:
	if state != CardAnimationMath.HOVER:
		return
	state = CardAnimationMath.PRESS
	var tw := _tween_prop("press_p", 1.0, config.press_dur, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	tw.finished.connect(_on_press_done)

func _on_press_done() -> void:
	press_p = 0.0
	state = CardAnimationMath.FLIP
	var tw := _tween_prop("flip_p", 1.0, config.flip_dur, Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	tw.finished.connect(_on_flip_done)

func _on_flip_done() -> void:
	flip_turns += 1
	flip_p = 0.0
	state = CardAnimationMath.LAND
	var tw := _tween_prop("land_p", 1.0, config.land_dur, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.finished.connect(_on_land_done)

func _on_land_done() -> void:
	land_p = 0.0
	state = CardAnimationMath.HOVER if hovering else CardAnimationMath.IDLE

func reset() -> void:
	for k in _tweens:
		var tw: Tween = _tweens[k]
		if tw != null and tw.is_valid():
			tw.kill()
	state = CardAnimationMath.IDLE
	hovering = false
	hover_p = 0.0
	press_p = 0.0
	flip_p = 0.0
	land_p = 0.0
	flip_turns = 0
	showing_back = false
	_idle_time = 0.0
	if body != null:
		body.show_back(false)
	_apply()
```

- [ ] **Step 4: 运行测试确认通过**

Run: `--headless --path . --import` then `--headless --path . res://tests/verify_card_animation.tscn`
Expected: `54/54 passed`（44 + 10）。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/card_animation.gd scripts/ui/card_animation.gd.uid tests/verify_card_animation.gd
git commit -m "feat: CardAnimation 控制器（标量进度 + compose 应用）+ 测试"
```

---

### Task 6: 拾取命中点 + 沙盒场景/脚本

**Files:**
- Modify: `scripts/ui/table3d_picker.gd`
- Create: `scripts/ui/card_animation_sandbox.gd`
- Create: `scenes/ui/card_animation_sandbox.tscn`
- Modify: `tests/verify_card_animation.gd`

**Interfaces:**
- Consumes: `CardAnimation`、`Table3dCamera`、`Table3dPicker`、`Crosshair`、`Table3dLayout.BLOCK_SIZE`
- Produces:
  - `Table3dPicker.pick_hit(...)` 返回值增加 `"position: Vector3"`（既有键不变）
  - `CardAnimationSandbox : Node3D`：`var actors: Array`、`var camera: Table3dCamera`、`var hovered: int`、`var auto_hover: bool`、`func play(card_index: int, action: String) -> void`

- [ ] **Step 1: 写失败测试**

在 `_run()` 追加 `await _test_sandbox()`，并追加：

```gdscript
func _test_sandbox() -> void:
	var scene: PackedScene = load("res://scenes/ui/card_animation_sandbox.tscn")
	var s = scene.instantiate()
	add_child(s)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_check("沙盒 5 张卡", s.actors.size() == 5)
	_check("沙盒相机已取景", s.camera != null and s.camera.camera_node() != null)
	_check("准星命中某张卡", s.hovered >= 0)
	var center := s.get_viewport().get_visible_rect().size * 0.5
	var hit := Table3dPicker.pick_hit(s.camera.camera_node(), s.get_world_3d(), center)
	_check("pick_hit 含命中点 position", hit.has("position") and hit.get("position") is Vector3)
	s.auto_hover = false
	if s.hovered >= 0:
		s.actors[s.hovered].exit_hover()
	s.play(0, "hover")
	await get_tree().create_timer(s.actors[0].config.hover_in_dur + 0.05).timeout
	_check("沙盒 play hover 抬升", s.actors[0].visual.position.y > 0.0)
	s.play(0, "flip")
	await get_tree().create_timer(s.actors[0].config.press_dur + s.actors[0].config.flip_dur + s.actors[0].config.land_dur + 0.15).timeout
	_check("沙盒 play flip 显示背面", s.actors[0].showing_back)
	s.play(0, "reset")
	await get_tree().process_frame
	_check("沙盒 reset 回正面", not s.actors[0].showing_back and s.actors[0].flip_turns == 0)
```

- [ ] **Step 2: 运行测试确认失败**

Run: `--headless --path . res://tests/verify_card_animation.tscn`
Expected: 报场景加载失败 / `position` 键缺失 / `CardAnimationSandbox` 未声明。

- [ ] **Step 3: 实现**

修改 `scripts/ui/table3d_picker.gd` 的 `pick_hit` 返回行：

```gdscript
	return {"pick": collider.get_meta("pick"), "collider": collider, "position": hit.get("position", Vector3.ZERO)}
```

Create `scenes/ui/card_animation_sandbox.tscn`:

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/ui/card_animation_sandbox.gd" id="1_sandbox"]
[ext_resource type="Script" path="res://scripts/ui/table3d_camera.gd" id="2_cam"]

[sub_resource type="Environment" id="Environment_1"]
background_mode = 1
background_color = Color(0.07, 0.08, 0.1, 1)
ambient_light_source = 2
ambient_light_color = Color(1, 1, 1, 1)
ambient_light_energy = 1.2

[sub_resource type="StandardMaterial3D" id="TableMat"]
albedo_color = Color(0.16, 0.18, 0.22, 1)

[sub_resource type="BoxMesh" id="TableMesh"]
size = Vector3(7, 0.08, 7)

[node name="CardAnimationSandbox" type="Node3D"]
script = ExtResource("1_sandbox")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_1")

[node name="CameraRig" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3.5, 3.9)
script = ExtResource("2_cam")
EYE_HEIGHT = 3.5
CAMERA_BACK = 1.5
MOUSE_SENSITIVITY = 0.35

[node name="PitchPivot" type="Node3D" parent="CameraRig"]

[node name="Camera3D" type="Camera3D" parent="CameraRig/PitchPivot"]

[node name="Table" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.04, 0)
material_override = SubResource("TableMat")
mesh = SubResource("TableMesh")
```

Create `scripts/ui/card_animation_sandbox.gd`:

```gdscript
class_name CardAnimationSandbox
extends Node3D
## 卡牌交互动效沙盒：一排 5 张平放卡；屏幕中心准星 + 鼠标转相机；左键翻牌。
## 纯展示原型：不接游戏逻辑/协议/快照。

const SAMPLE_CARDS := [
	{"rank": "A", "suit": "♥"},
	{"rank": "K", "suit": "♠"},
	{"rank": "Q", "suit": "♦"},
	{"rank": "J", "suit": "♣"},
	{"rank": "10", "suit": "♥"},
]

var actor_gap := Table3dLayout.BLOCK_SIZE.x + 0.15
var actors: Array = []
var camera: Table3dCamera
var crosshair: Crosshair
var hovered := -1
var auto_hover := true
var _hud: Label

func _ready() -> void:
	_build()
	set_process(true)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build() -> void:
	camera = get_node_or_null("CameraRig")
	if camera != null:
		camera.frame_for_seat(0.0)
	var count := SAMPLE_CARDS.size()
	for i in count:
		var actor := CardAnimation.new()
		actor.name = "Card%d" % i
		actor.card_data = SAMPLE_CARDS[i]
		actor.position = Vector3((float(i) - float(count - 1) * 0.5) * actor_gap, 0.03, 0.0)
		actor.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		add_child(actor)
		actors.append(actor)
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	crosshair = Crosshair.new()
	crosshair.name = "Crosshair"
	layer.add_child(crosshair)
	crosshair.set_active(false)
	_hud = Label.new()
	_hud.name = "Hud"
	_hud.position = Vector2(12, 8)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	layer.add_child(_hud)

func _process(_delta: float) -> void:
	if crosshair == null:
		return
	if auto_hover and camera != null:
		_update_hover()
	_update_hud()

func _update_hover() -> void:
	var center := get_viewport().get_visible_rect().size * 0.5
	var hit := Table3dPicker.pick_hit(camera.camera_node(), get_world_3d(), center)
	var idx := actors.find(_actor_from_collider(hit.get("collider")))
	if idx != hovered:
		if hovered >= 0 and hovered < actors.size():
			actors[hovered].exit_hover()
		hovered = idx
		if hovered >= 0:
			actors[hovered].enter_hover()
	if hovered >= 0:
		actors[hovered].ray_local = _ray_local_for(hit.get("position", Vector3.ZERO), actors[hovered])
	crosshair.set_active(hovered >= 0)

func _actor_from_collider(collider) -> Node:
	if collider == null or not is_instance_valid(collider):
		return null
	var n: Node = collider.get_parent()
	while n != null:
		if n is CardAnimation:
			return n
		n = n.get_parent()
	return null

func _ray_local_for(hit_pos: Vector3, actor: Node3D) -> Vector2:
	var p: Vector3 = actor.global_transform.affine_inverse() * hit_pos
	return Vector2(
		clampf(p.x / (Table3dLayout.BLOCK_SIZE.x * 0.5), -1.0, 1.0),
		clampf(p.z / (Table3dLayout.BLOCK_SIZE.z * 0.5), -1.0, 1.0))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and camera != null:
		camera.look(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hovered >= 0:
			actors[hovered].click()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## 测试/脚本入口：驱动指定卡。（"hover"/"unhover"/"flip"/"reset"）
func play(card_index: int, action: String) -> void:
	if card_index < 0 or card_index >= actors.size():
		return
	var a: CardAnimation = actors[card_index]
	match action:
		"hover":
			a.enter_hover()
		"unhover":
			a.exit_hover()
		"flip":
			a.enter_hover()
			a.click()
		"reset":
			a.reset()

func _update_hud() -> void:
	if _hud == null:
		return
	if hovered >= 0 and hovered < actors.size():
		var a: CardAnimation = actors[hovered]
		_hud.text = "card %d  state=%d  hover=%.2f press=%.2f flip=%.2f" % [hovered, a.state, a.hover_p, a.press_p, a.flip_p]
	else:
		_hud.text = "准星对准卡牌，左键翻牌"
```

- [ ] **Step 4: 生成 .uid 并运行测试确认通过**

Run: `--headless --path . --import` then `--headless --path . res://tests/verify_card_animation.tscn`
Expected: `61/61 passed`（54 + 7）。

若「准星命中某张卡」失败：确认卡片在桌面中心（中间卡 x=0）且相机 `frame_for_seat(0.0)` 已对准桌心；可用 `--headless` 打印 `s.hovered` 调试，不要改共享 `table3d_view`。

- [ ] **Step 5: 回归并提交**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_interaction.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d.tscn
```
Expected: 48/48 与 36/36。

```bash
git add scripts/ui/table3d_picker.gd scripts/ui/card_animation_sandbox.gd scripts/ui/card_animation_sandbox.gd.uid scenes/ui/card_animation_sandbox.tscn tests/verify_card_animation.gd
git commit -m "feat: 卡牌动效沙盒场景/输入 + pick_hit 命中点 + 测试"
```

---

### Task 7: 注册测试 + 全量回归 + 文档

**Files:**
- Modify: `tools/run_all_tests.sh`
- Modify: `docs/AI_AGENT_交接说明.md`

**Interfaces:**
- Consumes: `tests/verify_card_animation.tscn`
- Produces: 无（集成/文档）

- [ ] **Step 1: 注册测试**

在 `tools/run_all_tests.sh` 的 `run_single "table3d_interaction" ...` 行之后追加：

```bash
run_single "card_animation" res://tests/verify_card_animation.tscn
```

- [ ] **Step 2: 运行全量（快）回归**

Run: `tools/run_all_tests.sh --quick`
Expected: 全部 PASS，含 `card_animation 61/61`。

- [ ] **Step 3: 更新文档**

在 `docs/AI_AGENT_交接说明.md`：
- §4 的 UI 层表格追加一行：

```
| `card_animation_config.gd` / `card_animation_math.gd` / `card_animation.gd` / `card_animation_sandbox.gd` | 卡牌交互动效沙盒：参数集中配置 + 纯函数（状态机/缓动/高度/阴影/compose）+ 控制器（标量进度驱动）+ 沙盒（5 卡/准星/左键翻牌） |
```

- §8 验证命令列表追加：

```bash
# 卡牌交互动效沙盒（61/61：配置/状态机/缓动/高度/阴影/compose/控制器/沙盒）
... --headless --path . res://tests/verify_card_animation.tscn
```

并在 §8 的"开发约定"每轮测试列表中加入 `verify_card_animation`。

- [ ] **Step 4: 提交**

```bash
git add tools/run_all_tests.sh docs/AI_AGENT_交接说明.md
git commit -m "doc: 注册卡牌动效沙盒测试并更新交接说明"
```

---

## Self-Review

**Spec coverage：**
- §2 三层架构 → Task 1/2/3/5；节点结构 → Task 5（VisualRoot/Shadow/CardBody）。
- §3 状态机/标量/compose → Task 2/3/5。
- §4 IDLE/HOVER/PRESS/FLIP/LAND/阴影规格 → Task 3（数学）+ Task 5（时间轴/Tween）+ Task 4（切面）。
- §5 沙盒场景/输入/`play()` → Task 6。
- §6 测试与闸门 → 各 Task Step 4/5 + Task 7。
- §7 移植说明 → 不在实现范围（仅文档说明）。
- §8 参数默认值 → Task 1。
- §9 文件清单 → File Structure + Tasks。

**Placeholder scan：** 无 TBD/TODO；所有代码步骤含完整代码。

**Type consistency：** `compose` 返回键与 Task 5 使用一致；`show_back` 签名 Task 4=Task 5；`pick_hit` 新键 `position` 与沙盒 `_update_hover` 一致；`CardAnimationMath.IDLE/HOVER/...` 与控制器一致。
