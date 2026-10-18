# 卡牌炫光呼吸闪烁 + hover 外延虚线边框 设计 v1

> **目的**：① 3D 卡牌的**炫光**加"呼吸式正弦闪烁"；② **hover 反馈**从"炫光"改为**卡外一圈虚线边框**（白=无上下文 / 绿=可选 / 红=有选择上下文但不可选）。
> **纯客户端展示层**：不改规则/协议/快照。作用于对局 `CardBlock`（沙盒共用同一 body）。
> **分支**：`agent/feature-uiboard`。

## 1. 背景

- 炫光 = `CardBlock` 卡下方 3 张半透明外扩平面（`GLOW_LAYERS`）；颜色优先级 `flash > reveal > protected > hover > actionable`。
- 黄色=可操作提示；红/绿=贴牌错误/正确；紫=护盾。
- hover 目前走炫光（浅蓝 `HOVER_COLOR`，并覆盖黄色 actionable，见 B38）。
- `table3d_view._apply_hover()` 命中时 `parent.call("set_hover", on, HOVER_COLOR)`。

## 2. 目标行为

1. **炫光闪烁**：所有炫光态（黄/红/绿/紫）按正弦**呼吸**（峰=原亮度，谷=×(1−AMP)）；`glow_color()`/`has_glow()` 语义不变（仍基色/开关）。
2. **hover 虚线边框**：hover 时在卡外 `BORDER_GAP` 处显示一圈虚线（替代 hover 炫光）；颜色：
   - 无选择上下文 → **白**
   - 有选择上下文且该卡可操作 → **绿**
   - 有选择上下文且该卡不可操作 → **红**
3. 炫光优先级去掉 `hover` → `flash > reveal > protected > actionable`。

## 3. 设计

### 3.1 `scripts/ui/card_block.gd`

常量：
```gdscript
const GLOW_FLICKER_AMP := 0.35       # 闪烁幅度（谷 = 亮度 ×(1-AMP)）
const GLOW_FLICKER_SPEED := 4.0      # 角速度 rad/s
const BORDER_WHITE := Color(1.0, 1.0, 1.0, 0.9)
const BORDER_GAP := 0.14             # 虚线距卡边外扩
const BORDER_T := 0.02               # 线粗
const BORDER_DASH := 0.06            # 每段长
const BORDER_SPACE := 0.05           # 段间隙
const BORDER_Y := 0.006              # 离桌面（卡外，不被遮挡）
```
成员：`_border_mesh: MeshInstance3D`、`_border_mat: StandardMaterial3D`、`_show_border := false`、`_border_color := BORDER_WHITE`、`_glow_t := 0.0`。

- **闪烁**：`_glow_pulse() -> float = 1.0 - GLOW_FLICKER_AMP * 0.5 * (1.0 - cos(_glow_t*GLOW_FLICKER_SPEED))`。`_apply_glow_layers()` 每层 alpha 乘 pulse。`_process` 推进 `_glow_t` 并在 `_glow_base.a>0` 时重放（`_apply_glow_layers(_glow_base)`）；`_paint_glow()` 在炫光开启时 `set_process(true)`；`_process` 的自动停机条件加 `and _glow_base.a <= 0.0`。
- **虚线边框**（`_build()` 内建，挂 **root**（非 `_visual`），铺在桌面平面）：
  - `ImmediateMesh`（`PRIMITIVE_TRIANGLES`）绕卡周 4 边生成小矩形 dash（沿边 `BORDER_DASH` 亮 + `BORDER_SPACE` 空，居中布满每边）。
  - 单材质 `StandardMaterial3D`（unshaded/alpha/cull-disabled）；`position = (0, BORDER_Y, 0)`；初始 `visible=false`。
- **`set_hover(on, color := BORDER_WHITE)`**：改为驱动边框（`_show_border=on`、`_border_color=color`、`_apply_border()`）；**不再**影响炫光。
- `_paint_glow()` 去掉 `hover` 分支：`flash > reveal > protected > actionable > off`。
- 新增访问器：`has_border() -> bool`、`border_color() -> Color`、`is_actionable() -> bool`（= `_actionable`）。

### 3.2 `scripts/ui/table3d_view.gd`

```gdscript
const BORDER_WHITE := Color(1.0, 1.0, 1.0, 0.9)
const BORDER_GREEN := Color(0.53, 0.85, 0.63)
const BORDER_RED := Color(1.0, 0.48, 0.48)
var _sel_active := false
```
- `update_hover(selection_active := false) -> bool`：记 `_sel_active = selection_active`，其余不变。
- `_apply_hover(collider, on)`：命中时颜色 = `_sel_active ? (block.is_actionable() ? GREEN : RED) : WHITE`；`parent.call("set_hover", on, color)`（off 传 `Color(0,0,0,0)`）。删除 `HOVER_COLOR` 用法。

### 3.3 `scripts/ui/main.gd`
- `_process` 调 `table3d.update_hover(interaction.action_mode != "")`。

## 4. 视觉/参数

| 常量 | 值 |
| --- | --- |
| 闪烁幅度 / 速度 | `0.35` / `4.0` (rad/s) |
| 边框外扩 / 线粗 / 段长 / 间隙 / 高度 | `0.14` / `0.02` / `0.06` / `0.05` / `0.006` |
| 白 / 绿 / 红 | `(1,1,1,0.9)` / `(0.53,0.85,0.63)` / `(1,0.48,0.48)` |

## 5. 测试

- `tests/verify_table3d_exchange.gd`：把"hover 覆盖 actionable 浅蓝"等断言改为——hover **不**改炫光（仍金）+ **显示边框**；揭示炫光仍最高；恢复后回 actionable 金。
- `tests/verify_table3d_interaction.gd`：`update_hover()` 命中 → 断言 `has_border()`（白）；`clear_hover` → 无边框；新增边框颜色映射（`update_hover(false)`→白，`update_hover(true)` 且目标 actionable→绿 / 不可操作→红）。
- `tests/verify_table3d.gd`：护盾/揭示炫光断言不变；新增"闪烁不改变 `glow_color()`"（多次 `_process` 后基色不变）。
- 回归：`verify_table3d*`、`verify_card_animation`、`run_all_tests.sh --quick`。

## 6. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/card_block.gd` | 炫光呼吸闪烁 + 程序化虚线边框 + `set_hover` 改驱边框 + 访问器 |
| `scripts/ui/table3d_view.gd` | hover 边框颜色（白/绿/红）+ `update_hover(selection_active)` |
| `scripts/ui/main.gd` | 传 `interaction.action_mode != ""` |
| `tests/verify_table3d_exchange.gd` / `verify_table3d_interaction.gd` / `verify_table3d.gd` | 更新/新增断言 |

**不改**：`scripts/core`、`scripts/net`、`card_animation*.gd`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`。

## 7. 边界
- 纯展示：不改规则/协议/快照。
- 边框几何一次性构建、仅改颜色/显隐；闪烁只在炫光开启时每帧改 alpha。
