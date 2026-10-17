# 沙盒卡牌 hover「纯竖直抬起 + 空中翻转回落」Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 沙盒里把 hover 改成纯竖直抬起（≈原翘起边高度）、点击后空中翻转再平稳回落贴桌并保持不动、hover 离开平稳降落。

**Architecture:** 手感差异全部经**沙盒内的 config 实例覆写**（`CardAnimationConfig` 默认值与 `CardAnimationMath.compose` 都不动 → 对局不变）；点击流程只在沙盒专用的 `card_animation.gd` 里改（新增 `docked` 标记 + FLIP 后下沉回落）。

**Tech Stack:** Godot 4.6 / GDScript；headless 测试 `tests/verify_card_animation.tscn`。

## Global Constraints
- 工作目录 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard2/`。
- **不改** `card_animation_config.gd` 默认值、`card_animation_math.gd`、`card_block.gd`、`table3d_view.gd`、`scripts/core`、`scripts/net`。
- 不启动 GUI；用 headless：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_animation.tscn`。
- 提交 `feat:`；`.gd.uid` 随新增脚本提交（本次无新增脚本）。

---

### Task 1: 控制器点击落回流程 + 沙盒参数覆写 + 测试

**Files:**
- Modify: `scripts/ui/card_animation.gd`
- Modify: `scripts/ui/card_animation_sandbox.gd`
- Modify: `tests/verify_card_animation.gd`
- Spec: `docs/superpowers/specs/2026-10-16-card-hover-lift-flip-design.md`

**Interfaces:**
- Produces: `CardAnimation.docked: bool`；`enter_hover/exit_hover/_on_flip_done/_on_land_done/reset` 新语义。
- Produces: `CardAnimationSandbox` `@export var hover_lift := 0.16` / `hover_out_dur := 0.35` / `no_tilt := true`。

- [ ] **Step 1: 改 `scripts/ui/card_animation.gd`**

加字段（`var flip_turns := 0` 之后）：
```gdscript
var docked := false
```

`enter_hover`：
```gdscript
func enter_hover() -> void:
	hovering = true
	if docked:
		return
	if state == CardAnimationMath.PRESS or state == CardAnimationMath.FLIP or state == CardAnimationMath.LAND:
		return
	state = CardAnimationMath.HOVER
	_tween_prop("hover_p", 1.0, config.hover_in_dur, Tween.TRANS_BACK, Tween.EASE_OUT)
```

`exit_hover`：
```gdscript
func exit_hover() -> void:
	hovering = false
	docked = false
	if state == CardAnimationMath.PRESS or state == CardAnimationMath.FLIP or state == CardAnimationMath.LAND:
		return
	state = CardAnimationMath.IDLE
	_tween_prop("hover_p", 0.0, config.hover_out_dur, Tween.TRANS_CUBIC, Tween.EASE_OUT)
```

`_on_flip_done`：
```gdscript
func _on_flip_done() -> void:
	flip_turns += 1
	flip_p = 0.0
	state = CardAnimationMath.LAND
	# 空中翻完后下沉回落：hover_p 1→0（平稳），同时 land_p 缩放落定
	_tween_prop("hover_p", 0.0, config.land_dur, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	var tw := _tween_prop("land_p", 1.0, config.land_dur, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.finished.connect(_on_land_done)
```

`_on_land_done`：
```gdscript
func _on_land_done() -> void:
	land_p = 0.0
	hover_p = 0.0
	state = CardAnimationMath.IDLE
	# 落回后保持不动：准星仍在其上则锁定(docked)，待 exit_hover 解除
	docked = hovering
```

`reset`：在 `flip_turns = 0` 之后加：
```gdscript
	docked = false
```

- [ ] **Step 2: 改 `scripts/ui/card_animation_sandbox.gd`**

加导出（`var _hud: Label` 附近）：
```gdscript
## 沙盒 hover 手感覆写（不改 config 默认值 → 对局不受影响）。
@export var hover_lift := 0.16
@export var hover_out_dur := 0.35
@export var no_tilt := true
```

在 `_build()` 里 `actor.set_pick(...)` 之后、`actors.append(actor)` 之前加：
```gdscript
		_apply_sandbox_config(actor)
```

新增函数：
```gdscript
## 覆写单卡 config：纯竖直抬起、平稳降落（compose/math 与 config 默认值均不改）。
func _apply_sandbox_config(a: CardAnimation) -> void:
	a.config.hover_lift = hover_lift
	a.config.hover_out_dur = hover_out_dur
	if no_tilt:
		a.config.hover_pitch = 0.0
		a.config.max_tilt = 0.0
```

- [ ] **Step 3: 更新 `tests/verify_card_animation.gd`**

替换整个 `_test_controller()`：
```gdscript
func _test_controller() -> void:
	var a := CardAnimation.new()
	a.config = CardAnimationConfig.new()
	add_child(a)
	await get_tree().process_frame
	_check("控制器已建节点", a.visual != null and a.shadow != null and a.body != null)
	_check("控制器基准拾取盒(不随动画)", a.pick_area != null and not a.body.is_pick_enabled())
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
	await get_tree().create_timer(a.config.flip_dur + a.config.land_dur + 0.2).timeout
	_check("翻牌后显示背面", a.showing_back)
	_check("空中翻完落回 IDLE（保持不动）", a.state == CardAnimationMath.IDLE and a.hover_p < 0.02)
	_check("落回后贴桌（高度≈0）", absf(a.visual.position.y) <= a.config.idle_amp + 0.02)
	a.enter_hover()
	await get_tree().create_timer(a.config.hover_in_dur + 0.05).timeout
	_check("docked：准星仍在也不重新抬起", a.state == CardAnimationMath.IDLE and absf(a.visual.position.y) <= a.config.idle_amp + 0.02)
	a.exit_hover()
	await get_tree().create_timer(a.config.hover_out_dur + 0.05).timeout
	_check("离开悬停 → IDLE", a.state == CardAnimationMath.IDLE)
	a.enter_hover()
	await get_tree().create_timer(a.config.hover_in_dur + 0.05).timeout
	_check("离开后再悬停可重新抬起", a.visual.position.y > 0.0)
	# 翻牌途中移开准星：不打断，落定回 IDLE 且不 dock（可再抬）
	a.click()
	await get_tree().create_timer(a.config.press_dur + 0.02).timeout
	_check("第二次翻牌处于 FLIP", a.state == CardAnimationMath.FLIP)
	a.exit_hover()
	await get_tree().create_timer(a.config.flip_dur + a.config.land_dur + a.config.hover_out_dur + 0.25).timeout
	_check("翻牌途中离开 → 落定 IDLE", a.state == CardAnimationMath.IDLE)
	_check("翻牌途中离开 → hover 归零", a.hover_p < 0.02)
	a.enter_hover()
	await get_tree().create_timer(a.config.hover_in_dur + 0.05).timeout
	_check("翻牌途中离开后仍可再抬", a.visual.position.y > 0.0)
```

在 `_test_sandbox()` 的 `_check("沙盒 play hover 抬升", ...)` 之后加：
```gdscript
	_check("沙盒覆写：无倾斜参数", is_equal_approx(s.actors[0].config.hover_pitch, 0.0) and is_equal_approx(s.actors[0].config.max_tilt, 0.0))
	_check("沙盒覆写：抬起高度≈hover_lift", absf(s.actors[0].visual.position.y - s.actors[0].config.hover_lift) < 0.03)
	_check("沙盒 hover 纯竖直（无旋转）", absf(s.actors[0].visual.rotation.x) < 0.01 and absf(s.actors[0].visual.rotation.z) < 0.01)
```

- [ ] **Step 4: 运行测试**
```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_animation.tscn
```
Expected: 无 `[FAIL]`，退出码 0。

- [ ] **Step 5: 回归 + 编译检查**
```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_interaction.tscn | grep -E "RESULT|FAIL"
```
Expected: 对局 hover 测试仍全绿（默认值/compose 未改）。

- [ ] **Step 6: 提交**
```
git add scripts/ui/card_animation.gd scripts/ui/card_animation_sandbox.gd tests/verify_card_animation.gd docs/superpowers/specs/2026-10-16-card-hover-lift-flip-design.md docs/superpowers/plans/2026-10-16-card-hover-lift-flip.md
git commit -m "feat: 沙盒 hover 纯竖直抬起 + 点击空中翻转回落（不改对局）"
```

## Self-Review
- 覆盖 spec §2/§3/§4：hover 无倾斜→覆写；点击空中翻+回落+dock→控制器；hover 离开平稳→`hover_out_dur` 覆写；测试→Task1 Step3。无缺口。
- 类型一致：`docked: bool`、`enter_hover/exit_hover/_on_flip_done/_on_land_done` 名与 spec 一致；沙盒 `hover_lift/hover_out_dur/no_tilt` 与 spec §3.1 一致。
- 边界：只改 3 个文件；config 默认值、math、对局文件零改动。
