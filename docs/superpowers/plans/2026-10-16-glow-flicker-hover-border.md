# 卡牌炫光呼吸闪烁 + hover 外延虚线边框 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use `- [ ]`.

**Goal:** 3D 卡牌炫光加呼吸正弦闪烁；hover 反馈由炫光改为卡外一圈虚线边框（白/绿/红）。

**Architecture:** `CardBlock` 加闪烁（每帧 alpha 乘正弦）与程序化虚线边框（ImmediateMesh 一次性构建，仅改色/显隐）；`set_hover` 改驱边框；炫光优先级去掉 hover；`table3d_view` 按"是否有选择上下文 + 目标是否可操作"算边框色。

**Tech Stack:** Godot 4.6 / GDScript；headless 测试。

## Global Constraints
- 工作目录 `/Users/ee/dev/gameDev/cambio-rouglike-feature-uiboard/`。
- 不启动 GUI；headless 验证。
- **不改** `scripts/core`、`scripts/net`、`card_animation*.gd`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`。
- 提交 `feat:`。

---

### Task 1: CardBlock 闪烁 + 虚线边框

**Files:** `scripts/ui/card_block.gd`；测试 `tests/verify_table3d.gd`、`tests/verify_table3d_interaction.gd`

- [ ] **Step 1**：加常量（§3.1）与成员 `_border_mesh/_border_mat/_show_border/_border_color/_glow_t`。
- [ ] **Step 2**：`_build()` 末尾调 `_build_border()`；实现 `_build_border()`（ImmediateMesh 绕卡周画 dash）+ `_apply_border()`。
- [ ] **Step 3**：`set_hover(on, color := BORDER_WHITE)` 改为驱动边框；`_paint_glow()` 去 hover 分支；`_apply_glow_layers` 乘 `_glow_pulse()`；`_process` 推进 `_glow_t` 并在开启时重放炫光；停机条件加 `_glow_base.a <= 0.0`。
- [ ] **Step 4**：加 `has_border()/border_color()/is_actionable()`。
- [ ] **Step 5**：测试：
  - `verify_table3d.gd`：护盾/揭示炫光断言不变；新增"多次 `_process` 后 `glow_color()` 不变（闪烁只改 alpha）"。
  - `verify_table3d_interaction.gd`：`_check("可操作边缘高亮色", ...ACTIONABLE_COLOR)` 保留；把 hover 相关改为边框断言。
- [ ] **Step 6**：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d.tscn` 与 `.../verify_table3d_interaction.tscn` 全绿。

### Task 2: table3d_view hover 边框颜色

**Files:** `scripts/ui/table3d_view.gd`

- [ ] **Step 1**：`HOVER_COLOR` 改为 `BORDER_WHITE/GREEN/RED`；加 `_sel_active`。
- [ ] **Step 2**：`update_hover(selection_active := false)` 记 `_sel_active`。
- [ ] **Step 3**：`_apply_hover(collider, on)`：`on` 时按 `_sel_active` 与 `parent.is_actionable()` 选色，`set_hover(on, color)`。
- [ ] **Step 4**：`tests/verify_table3d_interaction.gd` 更新/新增：`update_hover()`→`has_border()` 白；`clear_hover()`→无边框；`update_hover(true)` 且可操作→绿 / 不可操作→红。
- [ ] **Step 5**：`verify_table3d_interaction` 全绿。

### Task 3: main 传选择上下文 + exchange 断言

**Files:** `scripts/ui/main.gd`；`tests/verify_table3d_exchange.gd`

- [ ] **Step 1**：`main._process` → `table3d.update_hover(interaction.action_mode != "")`。
- [ ] **Step 2**：`verify_table3d_exchange.gd` 的 "hover 覆盖 actionable" 断言改为"hover 不改炫光（仍金）+ 显示边框"；揭示炫光仍最高；恢复后回 actionable 金。
- [ ] **Step 3**：回归：
```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
for t in verify_table3d verify_table3d_interaction verify_table3d_exchange verify_card_animation verify_table3d_mouse; do
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . "res://tests/$t.tscn" | grep -E "RESULT|FAIL"
done
```
- [ ] **Step 4**：`tools/run_all_tests.sh --quick` 全绿。

### Task 4: 文档 + 提交
- [ ] 更新 `docs/AI_AGENT_交接说明.md` §2 追加一条；提交 `feat:`。

## Self-Review
- 覆盖 spec §2/§3：闪烁→Task1；边框→Task1+2；颜色映射→Task2；main 上下文→Task3；测试→各 Task。无缺口。
- 类型一致：`set_hover(on, color)`、`has_border/border_color/is_actionable`、`update_hover(selection_active)` 命名一致。
- 边界：仅 card_block/table3d_view/main/tests/docs。
