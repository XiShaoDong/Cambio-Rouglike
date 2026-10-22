# 商店刷新/锁定 + 饰品栏 UI（Phase 1）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 商店改为每人独立 2 格，支持 $10 刷新与跨商店锁定；新增 12 件饰品占位展示、hover 说明；3D 每席手牌左侧显示 3 个可 hover 的饰品篮。

**Architecture:** 服务器权威的 `GameState` 维护每人 `relic_inventories` 与 `shop_locks`；`HiddenInfo` 按 viewer 投影自己的商店；客户端 `ShopPanel`/`RelicBar`/`Table3dView` 只读快照展示，不实现规则效果。

**Tech Stack:** Godot 4.6 / GDScript / headless 单元测试。

## Global Constraints

- 不改 `Phase` 枚举既有数值；新错误码只能追加。
- 客户端不保存权威牌面/价格/购买结果；所有购买、刷新、锁定走服务器 RPC。
- 每件饰品价格先统一 `50`；刷新 `10`。
- 每人遗物栏 3 格；不同玩家可重复持有同一饰品，同一玩家不可重复。
- 锁跨刷新、跳过、商店结束、下一局商店保留；买走或解锁才清除。
- 不实现 12 件饰品的实际规则效果（Phase 2）。
- 不启动 GUI；用 headless 测试验证。

---

### Task 1: 饰品定义与 run_state 数据模型

**Files:**
- Modify: `scripts/core/relics.gd`
- Modify: `scripts/core/game_rules.gd`
- Test: `tests/verify_relic_ui.gd`（新建）

**Interfaces:**
- Produces: `Relics.pool() -> Array`（14 件）、`Relics.def_by_id(id)`、`Relics.glyph_for(id) -> String`、`Relics.SHOP_REFRESH_COST := 10`。
- Produces: `KongRules.new_default_run()` 含 `relic_slots = 3`、`relic_inventories = {}`、`shop_locks = {}`、`relics = {}`。

- [ ] 在 `relics.gd` 添加 12 件定义（id/name/desc/price/glyph/color/category），保留现有 2 件；`pool()` 返回 14 件；`glyph_for` 按 id 查 glyph。
- [ ] `game_rules.gd` 的 `new_default_run()` 增加 `relic_slots: 3`、`relic_inventories: {}`、`shop_locks: {}`；移除 `relic_owners`。
- [ ] 新建 `tests/verify_relic_ui.gd` + `.tscn`，断言 14 件、id 唯一、glyph/desc 非空、默认 run 字段。
- [ ] 运行 `godot --headless --path . res://tests/verify_relic_ui.tscn`，预期通过。

### Task 2: 每人独立商店 + 刷新/锁定服务器逻辑

**Files:**
- Modify: `scripts/core/game_state.gd`
- Modify: `scripts/core/hidden_info.gd`
- Test: `tests/verify_shop.gd`（改写）

**Interfaces:**
- Produces: `shop.seats: {seat: {offers: Array, done: bool}}`、`shop.done: {seat: true}`。
- Produces: `request_shop_refresh(action_id)` / `request_shop_lock(slot, locked, action_id)`。
- Produces: `_is_relic_owner(seat, relic_id)` 查 `run_state.relic_inventories`。
- Produces: 快照 `shop.offers`（仅 viewer）、`shop.refresh_cost`、`shop.can_refresh`、`players[].relics`。

- [ ] `_start_shop` 为每名存活玩家生成 2 个 offer；锁定货位优先；随机货位排除已持有/另一格。
- [ ] 购买改为从 `shop.seats[seat].offers` 取；扣款、加入 `relic_inventories`、清该槽锁、标记 done；`shop_result` key `"<seat>_<slot>"`。
- [ ] 跳过只标记 done，不清锁。
- [ ] 新增 `_server_shop_refresh`：扣 10、只重掷未锁货位；无未锁/栏满/钱不足拒绝。
- [ ] 新增 `_server_shop_lock`：写/清 `run_state.shop_locks[seat][slot]`。
- [ ] `Relics` 后 `_is_relic_owner` 改为查 inventory；护盾消耗从 inventory 移除。
- [ ] `HiddenInfo._shop_snapshot(state, viewer_id)` 按 viewer 投影；`_player_snapshot` 加 `relics` 固定 3 格。
- [ ] `RejectCode` 追加 `SHOP_REFRESH_UNAVAILABLE` 与中文消息。
- [ ] 改写 `verify_shop.gd`：独立货架、刷新扣款/只动未锁、锁跨刷新、买走清锁、全员完成。
- [ ] 运行 `verify_shop` + `verify_relics`，修正旧断言。

### Task 3: 2D 商店 UI（2 格、刷新、锁定、hover）

**Files:**
- Modify: `scripts/ui/shop_panel.gd`
- Modify: `scenes/ui/shop_panel.tscn`
- Modify: `scripts/ui/main.gd`
- Test: `tests/verify_relic_ui.gd`（扩展）

**Interfaces:**
- `ShopPanel.setup(state, on_buy, on_skip, on_refresh, on_lock, dim)`。
- `main._on_shop_refresh()` / `_on_shop_lock(slot, locked)`。

- [ ] 场景 `Bottom` 加 `Refresh` 按钮；`RelicsRow` 由代码生成 2 个 slot。
- [ ] 每个 slot：占位字符、名称、价格、购买、锁定/解锁、tooltip（名称+说明+状态）。
- [ ] 刷新按钮文本 `刷新 $10`；禁用条件与 tooltip 原因。
- [ ] `main.gd` 连接新回调并传参。
- [ ] 扩展 `verify_relic_ui` 断言 2 个 slot、刷新/锁定按钮、锁定文本、tooltip。

### Task 4: 2D 遗物栏改为 3 格 + 占位字符

**Files:**
- Modify: `scripts/ui/relic_bar.gd`
- Modify: `scripts/ui/relic_icon.gd`
- Modify: `scripts/ui/action_model.gd`
- Test: `tests/verify_relic_ui.gd`

**Interfaces:**
- `RelicIcon.setup_glyph(text, color)`；`RelicBar` 读 `players[].relics`。

- [ ] `RelicIcon` 支持 glyph 字符绘制。
- [ ] `RelicBar.setup` 固定 3 格，读取 `players[].relics`；tooltip 来自 `Relics`。
- [ ] 护盾生效时临时显示护盾状态；计数 `持有数/3`。
- [ ] `ActionModel` 的 Joker 遗物判断改为看 `viewer` 自己的 relics。
- [ ] 扩展测试断言 3 格、空槽、名称/说明。

### Task 5: 3D 饰品篮 + hover

**Files:**
- Create: `scripts/ui/relic_basket.gd`
- Modify: `scripts/ui/table3d_view.gd`
- Modify: `scripts/ui/main.gd`
- Test: `tests/verify_table3d_relics.gd`（新建）

**Interfaces:**
- `RelicBasket.setup(slot, relic_id)`、`set_highlight(on)`、`pick_meta() -> Dictionary`。
- `Table3dView.relic_baskets(seat) -> Array`、`hovered_relic() -> Dictionary`、`hovered_relic_screen_rect(cam) -> Rect2`。
- `main._update_relic_tooltip()`。

- [ ] 每席 `Seat` 下建 `RelicBaskets`，3 个篮子位于本地 `+X`（x=1.15，z=-0.55/0/0.55，y=桌面+0.03）。
- [ ] 篮子显示 glyph/空槽；`Area3D` 拾取 meta `{"kind":"relic","seat","slot"}`。
- [ ] `render` 按 `players[].relics` 更新；hover 高亮。
- [ ] `main` 命中 relic 时用 `CardTooltip` 显示名称+说明；与卡牌 tooltip 互斥。
- [ ] 新建测试断言 3 个篮子、位置、pick meta、hover 文本数据。

### Task 6: 文档 + 全量回归

**Files:**
- Modify: `docs/KONG_开发文档.md`（R-10/商店刷新/锁定）
- Modify: `docs/网络协议_V1.md`（shop 快照/RPC）
- Modify: `docs/功能实现文档.md`（文件职责）

- [ ] 更新规则文档：每人独立 2 格、$10 刷新、锁跨商店、12 件饰品占位。
- [ ] 更新协议：`shop_refresh`/`shop_lock`、`shop.offers` 逐 viewer、`players[].relics`。
- [ ] 跑 `tools/run_all_tests.sh --quick`（或相关测试集合），确认无回归。
