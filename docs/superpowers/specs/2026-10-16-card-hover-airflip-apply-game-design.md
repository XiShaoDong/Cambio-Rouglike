# 沙盒 hover/揭示手感应用到对局 设计 v1

> **目的**：把沙盒验证过的卡牌手感应用到**对局真实卡牌**（`CardBlock`）：
> ① hover = **纯竖直抬起（无倾斜）**，高度≈0.16；
> ② 揭示翻转（看牌/贴牌绕卡长轴 180°）= **抬起 → 空中翻 → 平稳落回贴桌**，且**不再倾斜**；
> ③ hover 离开 = 平稳降落。
> **范围**：改共享 `CardAnimationConfig` 默认值（对局 `CardBlock` 与沙盒都用它 → 一处生效）；`CardAnimationMath.compose` 语义不变（仍由参数驱动）。点击"翻个面"是沙盒演示，**不搬**到对局（对局点击是游戏动作）。
> **分支**：`agent/feature-uiboard2`。

## 1. 背景与约束

- 对局 `CardBlock` 的 **hover 姿态**（`_apply_hover_pose` → `CardAnimationMath.compose`）与**揭示翻转**（`_apply_flip_pose`，用 `cfg.hover_pitch * arc` 做"朝玩家倾斜"）**共用** `CardBlock._cfg()` 返回的共享 `CardAnimationConfig`。
- 因此把默认值改成"无倾斜 + 高抬起 + 慢降落"即**同时**作用于 hover 与揭示翻转；`compose` / `_apply_flip_pose` 代码不用改。
- 之前为**隔离沙盒**而在沙盒里覆写 config；现在两者要一致 → **改为单一来源（config 默认值）**，移除沙盒冗余覆写。

## 2. 目标

| 项 | 变更 |
| --- | --- |
| hover 抬起高度 | `hover_lift` `0.12 → 0.16`（≈原倾斜时近边高度） |
| hover 倾斜 | `hover_pitch` `14 → 0`、`max_tilt` `2 → 0`（不朝玩家、不随准星指向） |
| hover 离开降落 | `hover_out_dur` `0.20 → 0.35`（平稳，cubic ease-out） |
| 揭示翻转 | 因 `hover_pitch=0` 自动变为**不倾斜**的绕长轴 180°；高度仍走 `flip_lift`（0.25）`sin` 弧线 = **抬起→空中翻→落回贴桌** |

## 3. 设计

### 3.1 `scripts/ui/card_animation_config.gd`（改默认值）
```gdscript
var hover_lift := 0.16
var hover_clearance := 0.03   # 不变
var hover_scale := 1.06       # 不变
var hover_pitch := 0.0
var max_tilt := 0.0
var hover_in_dur := 0.5       # 不变
var hover_out_dur := 0.35
```
- `flip_lift`（0.25）`press_*`/`land_*`/`flip_dur` 等**不变** → 揭示翻转的"抬起-翻-落回"时长与弧线不变，只是去掉倾斜。
- 对局 `CardBlock._cfg()` 是 `CardAnimationConfig.new()` → 自动采用新默认值（hover 与揭示同时生效）。
- 沙盒 `CardAnimation.new()` 也用默认值 → 与对局一致。

### 3.2 `scripts/ui/card_animation_sandbox.gd`（移除冗余覆写）
- 删除 `@export hover_lift/hover_out_dur/no_tilt`、`_apply_sandbox_config()`、以及 `_build()` 里的调用——默认值已即所需（单一来源）。
- 沙盒行为与对局一致（后续要再调手感，直接改 config 默认值）。

### 3.3 不改
- `CardAnimationMath.compose` / `card_animation.gd` 控制器逻辑 / `CardBlock` / `table3d_view.gd`。
- `card_animation.gd` 上一版为沙盒加的"点击空中翻+回落+dock"照旧（仅沙盒用，不搬对局）。

## 4. 测试

- `tests/verify_card_animation.gd`：
  - `_test_config`：`hover_lift` 断言 `0.12 → 0.16`。
  - `_test_height_shadow_compose`：原"准星 tilt 方向"（依赖 `max_tilt`）改为**无倾斜**断言（`rot.x≈0 and rot.y≈0`）；hover 仰角断言 `-hover_pitch`（0）仍成立。
  - `_test_sandbox`：无倾斜/抬起高度断言仍成立（改文案为"默认无倾斜"）。
  - 控制器（点击落回/dock）断言不变。
- 回归：`verify_table3d_interaction`（hover 抬起/落回、揭示翻转、own 槽 hover）、`verify_table3d`、`verify_card_fly`、`tools/run_all_tests.sh --quick` 全绿。

## 5. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/card_animation_config.gd` | 改默认值（hover_lift/hover_pitch/max_tilt/hover_out_dur） |
| `scripts/ui/card_animation_sandbox.gd` | 移除冗余覆写（exports/`_apply_sandbox_config`/调用） |
| `tests/verify_card_animation.gd` | 更新 hover_lift 与 tilt 断言 |

**不改**：`card_animation_math.gd`、`card_animation.gd`、`card_block.gd`、`table3d_view.gd`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`、`scripts/core`、`scripts/net`。

## 6. 参数（新默认值）

| 参数 | 旧 | 新 |
| --- | --- | --- |
| `hover_lift` | 0.12 | 0.16 |
| `hover_pitch` | 14.0 | 0.0 |
| `max_tilt` | 2.0 | 0.0 |
| `hover_out_dur` | 0.20 | 0.35 |
