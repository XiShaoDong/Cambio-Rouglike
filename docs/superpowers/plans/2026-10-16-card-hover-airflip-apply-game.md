# 沙盒 hover/揭示手感应用到对局 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`).

**Goal:** 对局 `CardBlock` 的 hover 改纯竖直抬起（≈0.16、无倾斜、平稳降落），揭示翻转改"抬起→空中翻→落回贴桌且不倾斜"。

**Architecture:** 只改共享 `CardAnimationConfig` 默认值（`CardBlock` 与沙盒都用它 → 一处生效）；移除沙盒冗余覆写；`compose`/控制器/`CardBlock` 代码不动。

**Tech Stack:** Godot 4.6 / GDScript；headless 测试。

## Global Constraints
- 工作目录 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard2/`。
- 不启动 GUI；headless 验证。
- **不改** `card_animation_math.gd`、`card_animation.gd`、`card_block.gd`、`table3d_view.gd`、`scripts/core`、`scripts/net`。
- 提交 `feat:`。

---

### Task 1: 改默认值 + 移除沙盒覆写 + 更新测试

**Files:**
- Modify: `scripts/ui/card_animation_config.gd`
- Modify: `scripts/ui/card_animation_sandbox.gd`
- Modify: `tests/verify_card_animation.gd`

- [ ] **Step 1: 改 `scripts/ui/card_animation_config.gd` 默认值**

```gdscript
var hover_lift := 0.16
var hover_clearance := 0.03
var hover_scale := 1.06
var hover_pitch := 0.0
var max_tilt := 0.0
var hover_in_dur := 0.5
var hover_out_dur := 0.35
```
（其余字段不变。）

- [ ] **Step 2: 移除 `scripts/ui/card_animation_sandbox.gd` 的冗余覆写**

删除这三行 `@export`（`var _hud: Label` 之后）：
```gdscript
## 沙盒 hover 手感覆写（不改 config 默认值 → 对局不受影响）。
@export var hover_lift := 0.16
@export var hover_out_dur := 0.35
@export var no_tilt := true
```
删除 `_build()` 里的 `_apply_sandbox_config(actor)` 调用行。
删除整个 `_apply_sandbox_config()` 函数。

- [ ] **Step 3: 更新 `tests/verify_card_animation.gd`**

`_test_config()` 中：
```gdscript
	_check("config 默认 hover_lift", is_equal_approx(c.hover_lift, 0.16))
```

`_test_height_shadow_compose()` 中，把原"compose 准星 tilt 方向"两条改为无倾斜断言（`max_tilt` 默认 0 → 不再随准星倾斜）：
```gdscript
	var ct := M.compose({"hover": 0.0, "press": 0.0, "flip": 0.0, "land": 0.0}, cd, 0.0, Vector2(0.5, -0.5))
	var ct_rot: Vector3 = ct["visual_rot_deg"]
	_check("compose 默认不随准星倾斜", is_equal_approx(ct_rot.x, 0.0) and is_equal_approx(ct_rot.y, 0.0))
```
（原 `_check("compose 准星 tilt 方向", ...)` 那行删除/替换。）

`_test_sandbox()` 中把两条文案改准确（默认已无倾斜，非"覆写"）：
```gdscript
	_check("沙盒 hover 默认无倾斜", is_equal_approx(s.actors[0].config.hover_pitch, 0.0) and is_equal_approx(s.actors[0].config.max_tilt, 0.0))
	_check("沙盒 hover 高度≈hover_lift", absf(s.actors[0].visual.position.y - s.actors[0].config.hover_lift) < 0.03)
	_check("沙盒 hover 纯竖直（无旋转）", absf(s.actors[0].visual.rotation.x) < 0.01 and absf(s.actors[0].visual.rotation.z) < 0.01)
```

- [ ] **Step 4: 运行测试**
```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_animation.tscn
```
Expected: 无 `[FAIL]`。

- [ ] **Step 5: 回归**
```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
for t in verify_table3d_interaction verify_table3d verify_card_fly verify_table3d_exchange; do
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . "res://tests/$t.tscn" | grep -E "RESULT|FAIL"
done
```
Expected: 全部无 `[FAIL]`。

- [ ] **Step 6: 提交**
```
git add scripts/ui/card_animation_config.gd scripts/ui/card_animation_sandbox.gd tests/verify_card_animation.gd docs/superpowers/specs/2026-10-16-card-hover-airflip-apply-game-design.md docs/superpowers/plans/2026-10-16-card-hover-airflip-apply-game.md
git commit -m "feat: 对局卡牌 hover 纯竖直抬起 + 揭示空中翻转（去倾斜），沙盒与对局统一"
```

## Self-Review
- 覆盖 spec：hover 抬起/无倾斜/慢降落 + 揭示去倾斜 → Step1 默认值；沙盒单一来源 → Step2；测试 → Step3。无缺口。
- 类型/命名一致：字段名沿用 `hover_lift/hover_pitch/max_tilt/hover_out_dur`。
- 边界：仅 3 个文件；`math`/控制器/`card_block`/对局文件零改动。
