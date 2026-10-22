# 道具卡 / 手持扇形 / 目标锁定（Phase 1）设计

日期：2026-10-20
分支：`agent/feature-game-rule`
状态：已与用户确认 UI + 数据/协议骨架；实际卡牌效果下一轮实现。

## 1. 目标

- 商店 `CARDS` 区变为真实可购买的**道具卡**（与扑克手牌、遗物分开）。
- 道具卡是私有持有物：最多 3 张、跨局保留；别人只在“使用”时通过贴牌成功弹层看到卡面。
- 空格展开屏幕下方中央的**手部扇形**；Q/E 切卡；Enter 使用；放下立即消失。
- 需要选目标的卡：扇形收起，进入目标模式；Q/E 在 3 名对手间切换；3D 相机转向并拉近目标 avatar，2D 高亮玩家区域；Enter 确认，Esc/Space 取消。
- 本轮只做购买/持有/查看/选目标/消耗/提示；卡牌效果先占位。

## 2. 道具卡数据

`scripts/core/item_cards.gd`（`ItemCards`）：

- `SLOT_LIMIT = 3`、`PRICE = 50`。
- target_mode：`next` / `opponent` / `self` / `none`。
- 占位池 3 张：
  - `item_fate_plus2`「命运·加二」：选择一名对手（`opponent`，效果待接入）
  - `item_interfere`「干扰」：选择一名对手（`opponent`，效果待接入）
  - `item_charm`「护符」：选择一名对手（`opponent`，演示无实际效果）
  - `next` / `self` / `none` 常量保留给后续真实效果卡；Demo 阶段统一 `opponent`，保证都能 Q/E 切镜头。

## 3. 数据模型

```gdscript
# run_state（跨局保留）
"item_slots": 3,
"item_inventories": {seat: [card_id]},
"item_locks": {seat: {slot: card_id}},

# shop
"seats": {seat: {
    "offers": [...], "relic_bought": false,
    "card_offers": [...], "card_bought": false,
}},
"done": {seat: true},
```

- 道具卡库存私有：`HiddenInfo` 只在顶层 `item_cards` 给 viewer 本人的卡 id 列表；`item_inventories`/`item_locks` 不进 `run` 快照。
- 商店卡牌货架逐 viewer：`shop.card_offers`（含 `locked`）、`card_refresh_cost`、`card_can_refresh`、`card_bought`。
- 遗物与道具卡各自限购 1；购买不自动结束商店。底部「结束商店」= 跳过整个商店（遗物+卡牌），全员结束才开下一局。

## 4. 服务器协议

新增：

- `shop_buy_card(slot)`：$50、卡牌栏 <3、未拥有、本店未买卡。
- `shop_card_refresh()`：$10、只重掷未锁卡位；卡牌栏满/已买卡/全锁拒绝。
- `shop_card_lock(slot, locked)`：免费；锁跨刷新/商店保留。
- `shop_skip()`：语义改为“结束商店”，标记整体完成。
- `use_item_card(slot, target_seat, action_id)`：仅自己回合 `TURN_DRAW/TURN_DECISION`；每回合 1 张；消耗；目标按卡 `target_mode` 校验；广播 `item_card_used`。
- 事件 `item_card_used`：`{actor, card(定义), target}`，所有客户端弹出贴牌成功样式提示；道具卡库存仍私有，使用后卡面才公开。

`SlapSuccessBurst` 扩展：可选 `description` 与外部 `card_control`；标题=卡名、名字=使用者、中间=道具卡正面、爆炸下方小字说明框（先做占位版）。

## 5. 展示层（可替换手部）

- `ItemHandMath`（纯函数）：扇形位置/旋转、选中抬起、Q/E 循环、目标顺序。
- `ItemHandModel`（纯状态）：卡列表、选中索引、目标模式、目标索引。
- `ItemHandArt extends Control`（可替换接口）：

  ```gdscript
  func setup(hand_rect: Rect2) -> void
  func play_open() -> void
  func play_close(immediate: bool) -> void
  func set_selected_hint(index: int, count: int) -> void
  ```

- 当前实现 `HandSilhouette2D`（程序化袖口+手掌+拇指）。未来美术/3D 手只需实现同一接口，并替换 `ItemHandOverlay.hand_art_scene`，不改输入/模型/卡布局。
- `ItemCardView` 独立于扑克 `CardView`，商店/扇形/提示弹层共用；未来换卡面美术只改它。
- `ItemHandOverlay`：底部中央扇形、选中卡抬起、说明面板、目标 HUD、提示行；对 main 暴露 open/close/select_next/begin_target/cycle_target/confirm/cancel 与 `use_requested` 信号。
- 输入：空格开关；Q/E 切卡；Enter 使用；目标模式 Q/E 切目标、Enter 确认、Esc/Space 取消。比拼中空格优先 STOP；3D 发牌动画期间不展开。

## 6. 3D 目标锁定

- `Table3dCamera`：`save_view/restore_view/lock_aim_at`；锁定绕过 ±90° yaw 限制、最短角度转向、FOV → 58；`look()` 锁定时忽略。
- `Table3dView`：目标 avatar 焦点、金色目标环、`begin_item_target/update_item_target/end_item_target`；`is_dealing()` 供空格冲突判断。
- 2D：`GameView` 给目标玩家区域加金色边框；Q/E 更新。

## 7. 测试

- `verify_item_cards`：定义/私有快照/卡牌货架/刷新/锁/购买/结束商店/使用消耗/每回合一次/目标校验/提示事件。
- `verify_item_hand`：扇形纯函数/模型/overlay 开合/切卡/目标模式/手部接口。
- 扩展 `verify_table3d_mouse` 或新增相机 lock 测试（yaw 越界、FOV 58、恢复）。
- 更新 `verify_shop`、`verify_board3d`、`verify_slap_burst`。
- 全量 `tools/run_all_tests.sh`。

## 8. 非目标

- 不实现 3 张道具卡的实际效果。
- 不做 3D 手部模型；只保留可替换接口。
- 不改扑克手牌、贴牌、Kongbaya、系列赛、遗物规则的既有语义。
