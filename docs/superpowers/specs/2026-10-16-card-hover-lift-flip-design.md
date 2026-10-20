# 沙盒卡牌 hover「纯竖直抬起 + 空中翻转回落」设计 v1

> **目的**：在**动效沙盒**里改 hover 手感——hover 时卡牌**纯竖直抬起、不倾斜**（高度≈现在一边翘起时近边的高度）；点击后在**空中翻转**（沿用现有点击的翻转效果）然后**平稳回落贴桌并保持不动**；hover 离开时**平稳降落**。
> **范围**：只动沙盒。**不改** `card_animation_config.gd` 默认值、**不改** `card_animation_math.gd`（`compose` 被对局 `CardBlock` 复用）、不改任何对局文件。纯展示原型。
> **分支**：`agent/feature-uiboard2`。

## 1. 背景与约束

- `CardAnimation`（`scripts/ui/card_animation.gd`）**仅沙盒使用**；对局用 `CardBlock`+`CardFly`。
- `CardBlock._cfg()` 是**共享的** `CardAnimationConfig`（`static var`）；`CardAnimationMath.compose` 也被对局复用。故：
  - 改 config **默认值**会波及对局 hover；
  - 改 `compose` 语义会波及对局 hover 与揭示翻转。
- 结论：hover 手感差异**通过沙盒内的 config 实例覆写**实现；控制器（点击流程）改动只在 `card_animation.gd`（沙盒专用）；`math`/`config` 默认值零改动。

## 2. 目标行为

1. **hover**：卡牌竖直抬起，无倾斜（不朝玩家、不随准星指向），抬起高度≈当前倾斜时近边高度。
2. **hover 离开**：平稳降落（无回弹），回到贴桌。
3. **点击（hover 后）**：保留现有「压缩 press → 翻转 flip → 落定 land」效果，但翻转发生在**空中**，随后**下沉回落贴桌并保持不动**（docked）；准星仍在其上也不自动再抬，需**移开准星再移回**才重新抬起。
4. **翻牌途中移开准星**：不打断翻转；落定后回 IDLE 且不 dock（可再悬停抬起）。

## 3. 设计

### 3.1 沙盒参数覆写（`scripts/ui/card_animation_sandbox.gd`）

新增 `@export`（Inspector 可调），`_build()` 建卡后对每张卡覆写其 `config`：

| 字段 | 值 | 作用 |
| --- | --- | --- |
| `hover_lift` | `0.16` | 纯竖直抬起高度 ≈ 原倾斜近边高度（`0.5·1.06·sin14° + 0.03 ≈ 0.16`） |
| `hover_pitch` | `0.0` | 不朝玩家抬头 |
| `max_tilt` | `0.0` | 不随准星指向倾斜 |
| `hover_out_dur` | `0.35` | 离开时更平稳（原 0.20） |

- `ray_local` 仍由沙盒喂给控制器，但 `max_tilt=0` 使其不再影响姿态。
- `CardAnimationMath` / `CardAnimationConfig` 默认值**零改动** → 对局不变。

### 3.2 控制器点击流程（`scripts/ui/card_animation.gd`，仅沙盒）

新增 `var docked := false`（落回后锁定，保持贴桌）。

- `enter_hover()`：`hovering=true`；若 `docked` 或处于 `PRESS/FLIP/LAND` → 直接返回（不抬）；否则进入 `HOVER` 并 tween `hover_p→1`。
- `exit_hover()`：`hovering=false` **且 `docked=false`**；若处于 `PRESS/FLIP/LAND` → 直接返回；否则 `IDLE` 并 tween `hover_p→0`（`hover_out_dur`，cubic ease-out＝平稳）。
- `click()`（不变，要求 `HOVER`）：`PRESS`。
- `_on_press_done()`（不变）：`FLIP`，tween `flip_p→1`（**此时 `hover_p` 仍=1，卡在空中** + `flip_lift` 弧线）。
- `_on_flip_done()`（改）：`flip_turns += 1`，`flip_p=0`，`state=LAND`；tween **`hover_p→0`（`land_dur`，cubic ease-out＝下落回落）** 与 `land_p→1`（缩放落定），`land_p` 完成接 `_on_land_done`。
- `_on_land_done()`（改）：`land_p=0`、`hover_p=0`、`state=IDLE`；若此刻 `hovering` → `docked=true`（保持不动），否则 `docked=false`。
- `reset()`：追加 `docked=false`。

状态机常量不改（`IDLE/HOVER/PRESS/FLIP/LAND` 语义不变；`LAND` 结束一律回 `IDLE`，`docked` 是控制器附加标记）。

### 3.3 行为流程

```
hover:      IDLE --enter--> HOVER (升起, 无倾斜)
离开:       HOVER --exit--> IDLE  (平稳降下)
点击:       HOVER --click--> PRESS --> FLIP (空中翻) --> LAND (hover_p→0 下沉回落) --> IDLE(docked)
dock 解除:  IDLE(docked) --exit_hover--> docked=false  → 再 --enter_hover--> 升起
翻牌中移开:  FLIP 中 exit → hovering=false, docked=false (不打断) → LAND → IDLE(非 dock)
```

## 4. 测试（`tests/verify_card_animation.gd`）

- `_test_height_shadow_compose` / `_test_config` / `_test_state_machine` / `_test_easing` / `_test_show_back`：**不变**（用默认 config，未改）。
- `_test_controller`（更新）：点击翻牌后「落回 IDLE（`hover_p≈0`）」「贴桌高度≈0」；`docked` 时 `enter_hover` 不抬；`exit_hover` 后 `enter_hover` 可再抬；翻牌途中 `exit_hover` → 落定 IDLE 且 hover 归零、可再抬。
- `_test_sandbox`（新增）：覆写生效——`config.hover_pitch==0`、`max_tilt==0`；hover 后 `visual` 旋转≈0（无倾斜）、高度≈`hover_lift`。
- 回归：`verify_card_animation` 全绿。

## 5. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/card_animation.gd` | 改：`docked` + 点击落回流程（FLIP 后下沉、LAND 落定、dock） |
| `scripts/ui/card_animation_sandbox.gd` | 改：`@export` 沙盒参数 + `_build()` 覆写各卡 config |
| `tests/verify_card_animation.gd` | 改：控制器/沙盒断言 |

**不改**：`scripts/ui/card_animation_config.gd`（默认值）、`scripts/ui/card_animation_math.gd`、`scripts/ui/card_block.gd`、`scripts/ui/table3d_view.gd`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`、`scripts/core`、`scripts/net`。

## 6. 参数（沙盒初值，可调）

| 常量 | 初值 |
| --- | --- |
| `hover_lift`（沙盒覆写） | `0.16` |
| `hover_pitch` / `max_tilt`（沙盒覆写） | `0.0` / `0.0` |
| `hover_out_dur`（沙盒覆写） | `0.35` |
