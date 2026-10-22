# 道具卡 / 手持扇形 / 目标锁定（Phase 1）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 商店真实道具卡 + 私有卡牌栏 + 空格扇形查看 + Q/E 切卡 + 目标锁定 + 贴牌样式使用提示。

**Architecture:** `ItemCards` 数据 + `GameState` 权威商店/库存/使用；`ItemHandModel/Math` 纯逻辑；`ItemHandOverlay` 组合可替换 `ItemHandArt` 与 `ItemCardView`；`main` 路由输入；`Table3dCamera/View` 负责目标锁定；`SlapSuccessBurst` 复用为使用提示。

## Global Constraints

- 道具卡库存私有；只在 `item_card_used` 事件中公开使用的卡。
- 每人 3 张、跨局保留；每店限购 1 张；$50/张；刷新 $10；锁跨商店保留。
- 每回合最多使用 1 张；仅自己回合 `TURN_DRAW/TURN_DECISION`；免费动作、不推进回合。
- 空格：比拼 STOP 优先；3D 发牌期间不展开；其余对局时间可查看。
- 2D 手部美术必须通过 `ItemHandArt` 接口注入，未来可直接替换。
- 本轮不实现卡牌效果；使用后消耗并广播占位事件。

---

### Task 1: 道具卡数据 + 服务器商店/库存

**Files:** `scripts/core/item_cards.gd`(new)、`game_rules.gd`、`game_state.gd`、`hidden_info.gd`、`tests/verify_item_cards.gd/.tscn`(new)

- [ ] 定义 `ItemCards` 3 张卡（id/name/desc/glyph/color/price/target_mode）。
- [ ] `run_state` 加 `item_slots=3`、`item_inventories`、`item_locks`。
- [ ] `shop.seats` 加 `card_offers/card_bought/relic_bought`；`_start_shop` 生成 3 张卡。
- [ ] 实现 `shop_buy_card/shop_card_refresh/shop_card_lock`；`shop_skip` 改为结束商店。
- [ ] 购买不自动结束；全员 `done` 才开下一局。
- [ ] `HiddenInfo` 下发私有 `item_cards`、`shop.card_offers`；`run` 去除 item 私有字段。
- [ ] 测试卡池/货架/刷新/锁/购买/结束/私有快照。

### Task 2: 使用道具卡 RPC + 事件

**Files:** `game_state.gd`、`tests/verify_item_cards.gd`

- [ ] `use_item_card(slot,target_seat,action_id)`：阶段/当前玩家/每回合一次/库存/目标模式校验。
- [ ] 消耗卡牌、记录 `item_used_turn[seat]=turn_index`、日志。
- [ ] `item_card_used` signal + RPC + 广播 `{actor,card,target}`。
- [ ] 测试 next/opponent/self/非法目标/重复使用/消耗。

### Task 3: 商店 UI

**Files:** `scripts/ui/item_card_view.gd`(new)、`shop_panel.gd`、`shop_panel.tscn`、`main.gd`、`tests/verify_relic_ui.gd`

- [ ] `ItemCardView` 占位卡面（背景/边框/glyph/名称）。
- [ ] CARDS 区 3 个真实卡位：购买/锁定/价格/tooltip。
- [ ] 卡牌刷新按钮 `刷新卡牌 $10`；遗物刷新按钮 `刷新遗物 $10`。
- [ ] 底部 `结束商店`；购买不自动结束。
- [ ] main 新回调；更新测试。

### Task 4: 手牌模型/纯函数/可替换手部

**Files:** `scripts/ui/item_hand_math.gd`、`item_hand_model.gd`、`item_hand_art.gd`、`hand_silhouette_2d.gd`、`item_hand_overlay.gd`、`scenes/ui/hand_silhouette_2d.tscn`(new)、`tests/verify_item_hand.gd/.tscn`(new)

- [ ] `ItemHandMath.fan_layout/cycle/target_order`。
- [ ] `ItemHandModel` 选卡/目标状态。
- [ ] `ItemHandArt` 接口 + `HandSilhouette2D` 程序化手。
- [ ] `ItemHandOverlay` 扇形/说明/目标 HUD/`hand_art_scene` 注入。
- [ ] 测试纯函数/模型/接口/开合/切卡。

### Task 5: 输入 + 2D 高亮 + 3D 相机锁定

**Files:** `main.gd`、`game_view.gd`、`table3d_view.gd`、`table3d_camera.gd`、`tests/verify_item_hand.gd`、`verify_table3d_mouse.gd`

- [ ] main `_input/_unhandled_input` 增加道具手牌路由（2D/3D 共用）。
- [ ] 2D `GameView` 目标玩家金光边框。
- [ ] `Table3dCamera.save_view/restore_view/lock_aim_at`（FOV 58、最短角度、锁定忽略鼠标）。
- [ ] `Table3dView` 目标环 + 焦点 + `is_dealing()`。
- [ ] 测试输入分支/2D 高亮/相机越界与恢复。

### Task 6: 使用提示（贴牌弹层复用）

**Files:** `scripts/ui/slap_success_burst.gd`、`main.gd`、`tests/verify_slap_burst.gd`

- [ ] `SlapSuccessBurst.setup` 支持 `description` 与外部 `card_control`。
- [ ] 爆炸下方小字说明框（目标名/说明）。
- [ ] main 连接 `item_card_used`，构建 `ItemCardView` 作为卡面。
- [ ] 测试标题/名字/卡面/说明/自动释放。

### Task 7: 文档 + 全量回归

- [ ] `KONG_开发文档.md` 增加道具卡规则。
- [ ] `网络协议_V1.md` 增加卡牌货架/使用/事件字段。
- [ ] `功能实现文档.md` / `AI_AGENT_交接说明.md` 更新。
- [ ] 运行 `tools/run_all_tests.sh` 全量通过。
