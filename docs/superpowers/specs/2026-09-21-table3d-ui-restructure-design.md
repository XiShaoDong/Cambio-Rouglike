# 3D 对局 UI 重构 + 动作模型抽取 设计 v1

> **前置**：承接 Milestone 1/2（`feature/3d-table`）。**规则 / 协议 / 快照 / 网络 / `core` 零改动**；**2D 行为与视觉不变**（仅内部改走共用 `ActionModel`）。3D 观感允许与 2D 完全不同。分支 `feature/3d-table`。

## 1. 目标

1. 抽取纯函数 **`ActionModel`**：2D 控制区与 3D HUD/铃铛共用同一份「动作与可用性」判定，消灭重复（尤其 Kongbaya 判定）。
2. 玩家状态 UI 拆「自己 / 其他玩家」：
   - **自己**：屏幕右下角一行 = 生命 / 金钱 / 卡牌数（带图标），**无名字**。
   - **其他**：头顶面板（`SubViewport → billboard Sprite3D`），**名字在面板上方**；自己那席不显示。
   - 面板底色：**透明白灰 + 黑边框**。
3. **Kongbaya 改为 3D 金色圆顶铃铛**，放抽牌堆左侧，准星可点；从 HUD 按钮组移除。
4. **pending 大牌改为与抽牌堆同尺寸、贴在抽牌堆上**。

## 2. ActionModel（新，纯函数）

文件 `scripts/ui/action_model.gd`（`class_name ActionModel extends RefCounted`）：

```gdscript
const Q_KEEP := "q_keep"
const Q_EXCHANGE := "q_exchange"
const JOKER := "joker"

# 条件动作按钮（需要时出现；点了触发 request_*）
static func conditional_actions(state: Dictionary) -> Array   # [{action, text, enabled}]
# 铃铛可用：TURN_DRAW 且 viewer 为当前玩家
static func kongbaya_available(state: Dictionary) -> bool
# Ready 文案/可用（2D 固定按钮与 3D HUD 共用）
static func ready_text(state: Dictionary, ready_clicked: bool) -> String
static func ready_enabled(state: Dictionary, ready_clicked: bool) -> bool
```

规则（**与现 2D 完全一致**，阶段数值 `INITIAL_PEEK=1, TURN_DRAW=2, TURN_DECISION=3, Q_DECISION=4`）：
- `conditional_actions`：
  - `Q_DECISION` 且 `viewer==current` 且 `q_decision.own_viewed` → `[Q_KEEP「Q：不交换」, Q_EXCHANGE「Q：交换」]`
  - `TURN_DECISION` 且 `viewer==current` 且 `pending.rank=="JOKER"` 且 `run.relics` 含 `Relics.JOKER_TRANSFORM_ID` → `[JOKER「变换 Joker」]`
- `kongbaya_available` = `phase==2 and viewer==current`（现 2D 铃铛 `disabled = not (...)`）。
- `ready_text` = `ready_clicked ? "已准备（n/N）" : "Ready（n/N）"`；`ready_enabled` = `not ready_clicked and ready_count < total`。

**统一分发**：`main._on_action(action: String)`（原 `_on_table3d_hud` 提升为 2D/3D 共用）：
`ready`→`game_view._ready_clicked=true; GameState.request_initial_ready()`；`kongbaya`→`_request_kongbaya()`；`q_keep`/`q_exchange`→`GameState.request_q_decision(...)`；`joker`→`_open_joker_transform_panel()`。

**接线（2D 行为不变）**：
- `game_view._render_controls`：Q/Joker 按钮由 `ActionModel.conditional_actions(main.latest_state)` 生成，`pressed` 连 `main._on_action.bind(action)`。
- `game_view.render`：Ready 文案/禁用改读 `ActionModel.ready_text/ready_enabled`；铃铛 `disabled` 改读 `not ActionModel.kongbaya_available(state)`。
- `main._hud_buttons`（原 `_table3d_hud_buttons`，改私有名）：`ActionModel.conditional_actions(...)` +（`INITIAL_PEEK` 时）Ready 条目；**不含 kongbaya**。

## 3. PlayerStatPanel（新，2D 复用组件）

`scripts/ui/player_stat_panel.gd`（`class_name PlayerStatPanel extends PanelContainer`）：
- `StyleBoxFlat`：`bg_color = Color(0.86,0.88,0.92,0.22)`（透明白灰）、`border_color = Color(0,0,0,0.85)`、`set_border_width_all(2)`、圆角 6、内容边距 6。
- 结构：`VBox`（间距 2）→ 可选 `NameLabel`（`Label`，居中，`UITheme.color("text_primary")`，字号 14）；`Row`（`HBox`，间距 12）→ 三组 `[icon + number]`：
  - 生命 `LifeIcon`(`danger`) + 数字
  - 金钱 `CoinIcon`(`accent`) + 数字
  - 卡牌数 `CardCountIcon`(`text_secondary`) + 数字
- 数字 `Label` 用 `UITheme.color("text_primary")`，字号 14，垂直居中。
- API：`set_data(player_name: String, health: int, currency: int, cards: int) -> void`；`player_name == ""` 时隐藏名字行。存 `data := {"name","health","currency","cards"}` 供测试断言。

新 `scripts/ui/card_count_icon.gd`（`class_name CardCountIcon extends Control`）：程序化小卡片（圆角矩形描边 + 内框），风格同 `CoinIcon`/`LifeIcon`。

## 4. 自己面板（屏幕右下角）

`main`：懒建一个 `PlayerStatPanel`（**无名字**），加到屏幕层，锚定 `PRESET_BOTTOM_RIGHT` + 边距 16，`mouse_filter = IGNORE`（3D 下鼠标被捕获，纯展示），`z_index` 高于棋盘。
- 3D 激活时显示，退出时隐藏。
- `_on_state_updated` 与进入 3D 时用 viewer 的 `health/currency/count` 调 `set_data("", ...)`。

## 5. 其他玩家面板（头顶）

`table3d_view._bind()` 为每席创建（代码构建，位置/尺寸用常量，后续可上提场景）：
- `SubViewport`（`transparent_bg=true`、`render_target_update_mode=UPDATE_ALWAYS`、`size` 如 `Vector2i(320, 96)`）挂视图根，内含 `PlayerStatPanel`（**带名字**）。
- `Sprite3D`（名 `StatPanel`，挂 `Avatar` 下，local `(0, 0.75, 0)`，`billboard=ENABLED`、`no_depth_test=true`、`texture = sub.get_texture()`、`pixel_size ≈ 0.005`）。
- `render` 每帧 `panel.set_data(name, health, currency, count)`。
- **自己那席 `Avatar.visible=false`** → 面板与角色一起隐藏（因此自己无名字 UI）。
- 场景中 `NameLabel` / `StatLabel`（Label3D）**删除**，由面板取代。

## 6. Kongbaya 铃铛（3D）

场景 `Center/KongBell`（`Node3D`）：
- `Base`：薄圆柱/盒（`CylinderMesh` 或 `BoxMesh`）深金；
- `Dome`：`SphereMesh`（`is_hemisphere = true`，`radius≈0.26`）金色（`accent`），`scale.y≈0.75` 压扁成铃形；
- `Knob`：顶部小球（`SphereMesh` `radius≈0.05`）；
- `PickArea`：`Area3D` + `BoxShape3D`（覆盖铃铛），`metadata` 由代码设 `{"kind":"hud","action":"kongbaya"}`。
- 位置：**抽牌堆左侧**（deck 在 `Center/Deck` x=0；铃铛约 `x=-0.75`，y≈0.15）。
- `render`：`ActionModel.kongbaya_available(state)` → 金色亮（emission）/暗（albedo 调暗）；点击走 `_on_action("kongbaya")`。
- HUD 按钮组移除 KONGBAYA（Ready / Q / 变换 Joker 保留）。

## 7. pending 贴到抽牌堆

场景 `Center/Pending`：`scale` 1.5→1.0、位置改到抽牌堆上方（deck 的卡面在 deck 原点 ≈ y=0.03 → pending ≈ y=0.05、同 XZ）。
- 拾取 meta 仍 `{"kind":"pending"}`；无 pending 时 `visible=false` → 点击落到 deck。**仅 3D**，不碰 2D。

## 8. 测试与验证

- 新 `tests/verify_actions.gd` + `.tscn`：`conditional_actions` 各阶段（Q 两按钮 / Joker / 空）、`kongbaya_available`、`ready_text/enabled`。
- `tests/verify_table3d.gd`：`_test_view_render` 的 `NameLabel/StatLabel` 断言改为**面板 data**（如 `view._seat_panels[0].data`）；保留座次/相机断言。
- `tests/verify_table3d_interaction.gd`：新增「自己 Avatar/面板隐藏、对手可见」「铃铛 pick 返回 `{kind:hud, action:kongbaya}`」；既有 34 条保持。
- `tools/run_all_tests.sh --quick` 全绿；编译无错误。
- **人工复核**：2D 界面行为/外观不变；3D 右下角自己面板、他方头顶面板+名字、金色铃铛、pending 贴堆。

## 9. 非目标与风险

- **不改 2D 行为与视觉**；不碰规则/协议/快照/网络。
- 不做 3D 动画、不做 3D 遗物栏、不做 3D 商店/结算。
- 风险：`game_view._render_controls` / `render` 被改动可能影响 2D → **以现有行为为准**（逐条对齐），并跑回归 + 人工复核 2D。
- `SubViewport → ViewportTexture` 已实测 headless 可用（不阻断测试）。
