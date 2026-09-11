# KONG：AI Agent 交接说明（Agent 必读 · 工程现状与工作方式）

> **本文档职责**：只给 **AI Agent**。用于让下一个 Agent 快速理解当前工程，在不重构既有基础的前提下继续开发。开始任何改动前，按第 1 节文档地图顺序阅读对应文档。规则/协议/测试权威见各文档，本文件不重复，只给"工程现状、架构不变量、工作方式、验证命令、关键 bug 档案入口"。

---

## 1. 文档地图（每个文档职责 + 给谁看）

| 文档 | 职责 | 给谁看 |
| --- | --- | --- |
| `AI_AGENT_交接说明.md`（本文件） | 工程现状、架构不变量、工作方式、验证命令、文档地图 | Agent 必读 |
| `BUG档案.md` | 已解决 bug + 根因/修复/诊断方法（防复发） | Agent + 开发者 |
| `KONG_开发文档.md` | 规则/产品/架构**权威**主规格（R-01~R-09 等） | 权威 |
| `网络协议_V1.md` | RPC/快照字段、错误码、隐私/幂等契约 | 权威 |
| `验收与测试计划.md` | T/P0-N 用例、验证闸门 | 权威 |
| `功能实现文档.md` | 文件树 + 16 Feature 映射 + 待开发清单 | Agent + 开发者 |
| `UI主题规范.md` | 主题令牌（dark/light） | 开发者 |
| `问题档案.md` | 未决/待确认问题登记 | Agent + 开发者 |
| `未解决的BUG.md` | **未复现/原因未确认**的 bug（含代码路径分析与排查建议；确认根因后迁入 BUG 档案） | Agent + 开发者 |
| `遗物设计卡模板.md` | Roguelike 设计卡填写模板 | 开发者 |
| `修改日志.md` | **开发者个人**追踪（request→实现→反馈，gitignore，不纳入版本） | 开发者，非 Agent |

> 开发者用途文档（修改日志、UI主题、遗物模板）对 Agent 只需知道"存在 + 各自职责"，不强制读全文。

---

## 2. 当前基线

- 项目：Godot 4.6，KONG（Cambio + 轻度 Roguelike）LAN MVP。
- 当前目标：系列赛框架、押注经济、商店固定价购买、**遗物效果 v1** 已完成（见下）；基础模式（无遗物）始终可独立运行。
- 联网：ENet/UDP，房主权威，默认端口 `7007`。
- 状态：大厅、对局界面、服务器权威状态机、规则、动效系统均已实现；已有自动化验证（见第 8 节）。
- 当前工作分支：`feature/store`（未合入 main）。本会话在 `feature/store` 上完成**系列赛框架 / 押注经济 / 商店固定价购买 / 遗物效果 v1**（见基线各条），设计在 `docs/superpowers/specs/2026-09-07-series-shop-relics-design.md`，各里程碑计划在 `docs/superpowers/plans/`。此前 `feature/internet-reconnect` 的 seat 身份重构 + 断线重连 + 结算页 + 音效/设置菜单均已合入（见 3.5 节与 B18-B26）。
- **贴牌系统（已重做动画）**：固定 2.5s 窗口 → `slap_open` 标志（弃牌/用技能后开启，下一玩家抽牌关闭）；同一窗口**不限次数**尝试（贴错每次罚牌，贴对先到者胜）；多人同时贴中 → 400ms 收集 → `SLAP_DUEL` 比拼 bar（随机加粗区中心红心，服务器到达时间判最近者）；调试开关 **O 键**切换 `debug_duel`（不判正确性 + 双贴即比拼）。
- **贴牌动画事件（`card_exchange_animated` 新 kind）**：`slap_penalty`（罚牌 fly 抽牌堆→手牌）、`slap_resolved`（赢家被贴的牌 fly→弃牌堆，弃牌堆延迟显示）、`slap_gift`（交换时行动者的牌 fly→对方槽，不带牌面防泄漏）。贴牌 reveal target 带 `correct` 标记 → 客户端打**绿（对）/红（错）炫光**；正确贴牌**绿光 hold**（v2，不翻回）等结算后 fly，比拼输家翻回。
- **手牌超限规则（R-07）**：任一玩家手牌总数 `> MAX_HAND_CARDS(6)` 时对局立即结束（GAME_OVER），该玩家判定失败并扣 1 生命，其余玩家按各自手牌点数结算排名（失败者不参与排名）。触发点：贴错罚抽后 `game_state._check_over_hand(seat)`。
- **结算页（同步轮记分，R-08）**：GAME_OVER 后弹出居中浮动排名窗口（`scenes/ui/settlement_page.tscn` 场景实体 + `settlement_page.gd`，不遮挡棋盘卡牌区）；**棋盘卡牌结算时初始为背面**，由算分动画**逐张联动翻面**（`_on_settlement_flip` → `CardView.flip_reveal`，与行内记分同一时刻，每张间隔 `FLIP_STEP`）；行内累计分滚动累加，每轮后排名表整行上移/下移实时重排（数据来自 `settlement_model.gd` 纯计算 `layout_order`/`rounds`/`ranking`）；全部翻完冠军行名字金色脉冲光环 + ★ 徽章，胜利音效（Winner01-04 随机）**延迟到冠军时刻**播放（`main._pending_winner_sfx`）；房主可「再来一局」（`request_next_match`，GAME_OVER 后直接开新局，`match_number` 递增）/「返回大厅」，客户端显示等待提示。reason-only 结算（无 ranking）不弹结算页。
- **结算页输入约定（B23）**：结算页根节点 `mouse_filter=STOP` 且**直挂 main 末尾 + z100**（不可挂 overlay/IGNORE，否则 4.6 picking 判不可点）；对局进入 GAME_OVER 时先 `_clear_settlement_anim_state()` 清残留动画再渲染；动画完成回调一律走 `_render_game_if_active()`（GAME_OVER 时跳过，防在途揭示延迟重渲染把翻开的牌翻回，见 B26）。
- **Kongbaya 最终轮**：一场对局只允许喊一次（`kong_caller != -1` 后任何玩家再喊均拒绝）；喊出者不再行动，其余玩家按顺时针各执行一轮最终行动后统一结算。`kong_caller` 哨兵值为 **-1**（不能用 0，房主座位是 0）。
- **系列赛框架（已完成）**：房主开局设定 `match_limit` X（2-10 默认 5）把单局扩展为多局系列赛。`_server_start_match(match_limit)` 存 `run.match_limit`；每局 GAME_OVER 非把末由服务器 Timer 自动开下一局、把末（`_series_finished()`）不启动；`health==0` 者出局观战（`eliminated==true`，保留座位、仅公开信息、不可操作，`_guard_spectator()` 接入全部动作 RPC）；把末总排名 `series_ranking.gd` `SeriesRanking.final_ranking()`（存活者胜场降序→同胜场货币降序，淘汰不入榜），`result.series` 只在把末存在。测试 `verify_series.gd`。
- **押注经济（已完成）**：起始 100 货币 + 1 灵魂币（`health` 默认 1）。每局开局确认后进入 `Phase.BET`（值 9）押注阶段：存活玩家押注（入场 20，+5 递增，上限 100 且 ≤ 货币，货币 < 入场自动 all-in）；结算 `_settle_economy`：第一名(并列平分) 2× 返还 + 垫底者押注、其他非最后 1.5× 返还、最后一名全失、差额系统补足；all-in 且垫底（含超限 R-07、首回合 Kong 失败按最后一名处理）→ `health→0` 出局；`bets` 为空时 no-op。押注面板 `scenes/ui/bet_panel.tscn`（W/S 调整 + Enter 确认 + 自动 all-in）；快照 `bet_ready`/`players[].currency`/`result.economy`/`result.penalized`。测试 `verify_economy.gd`（33/33）。
- **商店固定价购买（已完成）**：系列赛非把末结算后进入 `Phase.SHOP`（值 10），展示至多 3 件随机遗物（v1 池 2 件，`scripts/core/relics.gd` 数据 + `pool()`/`def_by_id()`，各固定价 `RELIC_PRICE=50`）。每位存活玩家**限购 1 件**：点击遗物且货币 ≥ 售价即 `_server_shop_buy` 扣款、`run_state.relics[relic_id]` 入库并记持有者 `run_state.relic_owners[relic_id]=seat`，同件**先到先得**（`shop.sold[offer]` 售出后他人不可再买）；也可「跳过购买」（`request_shop_skip`）。全员完成（购买或跳过，`shop.done`）→ `_deal_next_match` 开下一局；货币不足只能跳过。把末不进商店。新 RPC：`request_shop_buy(offer)`/`request_shop_skip()`；错误码 `INVALID_OFFER`（越界/已售出）/`INVALID_AMOUNT`（钱不够）。快照 `shop` 公开投影 `offers:[{id,name,price,sold_by}]` + `done`（固定价无密封字段）；`shop_result` 公开（谁以多少购买）。客户端 `scenes/ui/shop_panel.tscn` + `shop_panel.gd`（点击遗物购买 / 已售出·货币不足·已完成状态 / 「跳过购买」按钮，随快照刷新）+ `main.gd`（`_open_shop_panel` 开/刷新、`_on_shop_buy`、`_show_shop_result_toast`）；`settlement_page.gd` 非把末 footer"即将进入商店…"。规则见 `KONG_开发文档.md` §3.7 R-10；测试 `verify_shop.gd`（23/23）。
- **遗物效果 v1（已完成）**：`Joker 变换`（持有者在抽牌阶段抽到 Joker——抽牌堆或弃牌堆顶——可选变换为任意牌；未变换时其手中 JOKER 分值 +2，`_relic_card_value` 统一结算与揭示）与 `防守护盾`（购买后**下一局开局**随机护盾持有者一格并消耗，该格免疫其他玩家贴牌与 J/Q 交换，看牌/自操作不受影响，一局后失效）。钩子落点：`_apply_match_start_relics`（局开始消耗护盾）/`_server_joker_transform`（Joker 变换 RPC）/`_relic_card_value`（结算统一计分）/`_is_protected`/`_is_relic_owner`（持有者判定，`run_state.relic_owners`）；`RejectCode.PROTECTED`；护盾格快照 `protected`；`ScoreSystem.calculate_ranking` 加 `joker_bonus` 参数。客户端 `JokerTransformPanel`（`scenes/ui/joker_transform_panel.tscn`）+ "变换 Joker" 按钮；**遗物 UI**：护盾受保护格常驻紫色描边光晕 + ◈ 紫角标（`game_view._render_card_slot`），每玩家区域左侧遗物物品栏（`RelicBar`：3 槽 + `n/3` + 程序化盾/星图标 `RelicIcon` + Hover Tooltip 名称/描述/状态，数据全部来自快照公开字段，纯展示无协议改动）。规则见 `KONG_开发文档.md` §3.7 R-11；测试 `verify_relics.gd`（19/19）。
- **卡牌视图重建约定**：`game_view._clear_area` 一律先 `remove_child` 立即移出网格、再 `queue_free` 延迟释放（**不要直接 `free()`**——卡牌点击触发重建时被点击的卡正被信号锁定，free 会报 "Object is locked"）。
- **罚牌附加卡布局**：前 4 张主网格固定 2 列永不位移；第 5+ 张在 `ExtraLayer` 按**槽号固定绝对定位**（统一向上增长、行列固定，加新罚牌已存在卡不移动）。
- Git：仓库 `git@github.com:XiShaoDong/Cambio-Rouglike.git`，分支 `main`。
- 项目路径：`~/dev/gameDev/cambio-rouglike/`。

## 3. 架构不变量（禁止无理由重构）

1. `GameState` 保存完整 `deck`/`discard_pile`/`cards`/各玩家手牌；客户端不保存权威牌面。
2. 客户端只能调 `request_*` 意图方法；服务器收到 RPC 后再校验调用者、阶段、目标。
3. `HiddenInfo._snapshot_for(viewer_id)` 按接收者生成状态；结算前普通手牌槽位不含 `rank/suit/value`。
4. 看牌走 `receive_reveal` 定向消息，一次性展示；不要把已知牌写入公共状态。
5. 贴牌窗口无固定时长：弃牌/用技能后 `slap_open=true` 并推进回合，**下一玩家抽牌时关闭**；同一窗口内可**多次**尝试，正确且先到者立即关窗，贴错每次罚牌，判定翻牌期间客户端锁点击（`_slap_reveal_lock` 计数）。多人同时贴中 → 400ms 收集 → `SLAP_DUEL` 比拼（`slap_system.resolve_duel`，服务器到达时间判最近红心）。
   - 贴牌动画走 `card_exchange_animated` 事件（`slap_penalty`/`slap_resolved`/`slap_gift`），服务器在 `_broadcast_state` **之前**广播，客户端用旧布局定位。正确贴牌客户端绿光 hold（`reveal_controller._held_slap`）等结算事件；结算事件缺失会锁死牌堆（见 `未解决的BUG.md` U1）。
   - 贴他人时规则微调：进 `SLAP_EXCHANGE` 之际即把被贴的牌清出槽位并弃牌（动画与状态一致），交换阶段只把行动者的牌补进空槽；`slap_gift` 事件**不含牌面**（防泄漏，他人看背面）。
6. 规则层不依赖 IP/UI 节点/房主画面；未来 Headless VPS 复用 `GameState`。
7. `run_state`/`RunModifier` 是扩展缝，默认不启用。
8. **身份与连接解耦**：玩家身份为 `seat_id`（0..N-1，注册顺序分配），`players`/`turn_order`/`current_player_id`/快照玩家字段一律用 seat；`peer_id`（ENet 连接 id）只是当前连接，存于 `players[seat].peer_id`，掉线重连会变化而 seat 不变。所有 RPC 入口用 `_peer_to_seat(sender)` 转换。此为未来 VPS/跨网络重连的基础（VPS 上 peer id 同样是瞬态连接 id）。
9. **断线 = 标记离线 + 条件暂停，可重连恢复**：非当前行动者掉线游戏继续；当前行动者（或开局记忆阶段任一玩家）离线时 `suspended=true` 暂停并拒绝所有操作（`MATCH_SUSPENDED`）。注册时服务器发 `player_token`，客户端持久化到 `user://identity.cfg`；断线玩家凭 token 调 `request_reconnect` 认领原座位（更新 peer_id、置回在线、定向补发本人手牌面 + 待处理牌并广播快照）。房主可 `request_kick_offline(seat)` 踢出继续 / `request_abort_match` 中止（销毁房间回初始界面）/ `request_close_room` 解散房间。**踢出后剩余人数 < MIN_PLAYERS 自动中止回大厅**。
10. **遗物效果只对持有者生效（`run_state.relics` 共享字典 + `run_state.relic_owners` 记持有者）**：未持遗物一律 no-op（基础模式零影响）。护盾保护的是**槽位**（不随卡移动），局开始 `_apply_match_start_relics` 随机选格并消耗；他人贴牌/J·Q 交换指定受护盾格 → `RejectCode.PROTECTED` 拒绝（看牌/自操作不受影响）。Joker +2 只作用于**牌面仍是 JOKER 且持有者存活**的结算/揭示分值（`_relic_card_value` 与 `ScoreSystem.calculate_ranking(joker_bonus)` 一致）；变换后不再是 JOKER 按新点数计。

## 3.5 断线重连功能修改摘要（当前分支已完成）

> 目的：为下一个 Agent 快速定位"断线重连"涉及哪些文件/改了什么。详细协议见 `网络协议_V1.md`，bug 根因见 `BUG档案.md`（B14/B15/B16），实现拆解见 `功能实现文档.md`。

| 涉及文件 | 修改内容 |
| --- | --- |
| `scripts/core/game_state.gd` | ① **seat 身份重构**：`players` 以 `seat_id` 为 key（0..N-1），内部存 `{seat, peer_id, token, name, cards, offline, health}`；`turn_order`/`current_player_id` 全改 seat；新增 `_peer_to_seat()`/`_seat_by_token()`；所有 RPC 入口 `_server_*` 的 sender 经 `_peer_to_seat` 转换；`_reject`/广播/`_send_reveal`/动画事件按 `players[seat].peer_id` 路由，离线（peer=0）跳过。② **离线标记 + 条件暂停**：`_on_peer_left` 非 LOBBY 改为 `offline=true`（保留 token），`_is_suspended()` 动态判断，`_guard_suspended()` 统一拦截。③ **重连**：`request_reconnect`/`server_reconnect`/`_server_reconnect` 按 token 认领座位 + `_send_resume_hand` 补回手牌；`_add_player` 生成 token 并经 `receive_registered` 定向发回。④ **房主操作**：`request_kick_offline` / `request_abort_match`（中止=销毁房间） / `request_close_room`（解散关服务器）。⑤ 新错误码 `MATCH_SUSPENDED`/`INVALID_TOKEN`；`last_seen_revision` 在中止时重置（修复 B16） |
| `scripts/core/hidden_info.gd` | 快照输出 seat 语义（`viewer_id`/`current_player`/`player.id`）；新增 `suspended`/`offline_players` 字段；`_player_snapshot` 参数改 seat |
| `scripts/core/peek_system.gd` | `send_reveal` 由 peer 改为 seat，经 `players[seat].peer_id` 路由 |
| `scripts/ui/main.gd` | token 持久化（`user://identity.cfg`）、断线重连入口（"重连上次对局"）、`_on_joined_server_for_reconnect` 连接后凭 token 尝试重连、`_on_resume_hand` 刷新界面、窗口关闭拦截（`NOTIFICATION_WM_CLOSE_REQUEST`：房间中回大厅、初始大厅才退出） |
| `scripts/ui/game_view.gd` | 暂停时房主"踢出离线者并继续 / 中止并回大厅 / 解散房间"按钮；本人手牌渲染支持 `_resume_hand_map` 恢复牌面 |
| `scripts/ui/lobby_view.gd` | 大厅房主"解散房间"按钮、客户端"退出房间"按钮（保留 token 供重连）；`reset_lobby()` 复位 |
| `tests/verify_reconnect.gd`/`.tscn` | 新增：seat 身份 / 非当前回合掉线继续 / 轮到离线者暂停 / 房主踢出 / 踢出后剩 1 人中止 / 解散房间 / token 认领 / 手牌恢复（41/41） |
| `tests/verify_protocol.gd` | 翻成 seat 语义；断线断言改为"标记离线不中止" |
| `tests/verify_duel.gd` | 翻成 seat 语义（peer1→seat0, peer2→seat1） |

**验证命令**（新增）：`--headless --path . res://tests/verify_reconnect.tscn`（41/41）。全量回归基准见第 8 节。

## 4. 服务器权威子系统（16 Feature 已拆分）

核心逻辑已按 16 Feature 拆成独立类（详见 `功能实现文档.md` 二节）：

| 文件 | 职责 |
| --- | --- |
| `game_state.gd` | 状态机 + RPC 端点 + 命令校验（唯一权威） |
| `hidden_info.gd` | 快照投影（server 完整 → viewer 视角） |
| `score_system.gd` | 结算/排名 |
| `turn_system.gd` | 回合推进决策 |
| `effect_system.gd` | 卡牌能力执行（7/8/9/10/J/Q） |
| `peek_system.gd` | 看牌揭示 |
| `swap_system.gd` | J/Q 交换 |
| `slap_system.gd` | 贴牌窗口（`slap_open`）+ 400ms 收集 + 比拼（`SLAP_DUEL` 裁决）+ 动画事件广播（slap_penalty/resolved/gift）+ `add_penalty` 返回槽号 |
| `kongbaya_system.gd` | Kongbaya 最终轮 |
| `network.gd` | ENet 连接/大厅/断线 |

UI 层已拆分（main.gd 是组合根）：

| 文件 | 职责 |
| --- | --- |
| `main.gd` | 组合根：App 生命周期 + signal 转发 + 工具 |
| `game_interaction.gd` | 交互状态机（action_mode/selected） |
| `lobby_view.gd` | 大厅构建/建房/加入/双开 |
| `game_view.gd` | 对局构建 + 状态投影渲染（前 4 张固定 2 列网格 + 第 5+ 张 `ExtraLayer` 按槽号固定定位） |
| `reveal_controller.gd` | 看牌/贴牌翻转动画（`_play_flip_at`/`_play_slap_flip`，贴牌绿/红炫光 + 正确 hold `_held_slap`） |
| `card_animator.gd` | 卡牌移动/交换/落位动画 + 贴牌事件（slap_penalty/resolved/gift）处理（副本 + 隐藏源卡 + 占位） |
| `dev_tools.gd` | F12 布局调试 / T 主题切换 / O 调试贴牌开关 |
| `duel_bar.gd` | 比拼 bar（全屏遮罩+居中弹窗；随机加粗区+中心红心+扫动标记+STOP；空格停止由 main 转发） |
| `settlement_model.gd` | 结算纯计算（同步轮记分：`layout_order`/`rounds`/`ranking`，headless 可测） |
| `settlement_page.gd` + `scenes/ui/settlement_page.tscn` | 结算弹层（居中排名窗口场景实体；逐张翻牌/实时重排/冠军特效；回调解耦 main） |
| `card_view.gd` / `card_factory.gd` | 卡牌视图节点 / 构建 |
| `dashed_border.gd` | 虚线边框占位（当前对局空槽已改透明占位，不用虚线） |
| `scenes/ui/game_board.tscn` | 对局棋盘静态骨架（锚点+容器，布局可在编辑器拖拽）：TitleBar/HintArea/4×PlayerArea/MiddleRow·PileArea/Corner |
| `scenes/ui/player_area.tscn` + `scripts/ui/player_area.gd` | 玩家区域模板，`@export var card_size`（默认 62×90），名字在卡牌正下方；GameBoard 直接子节点，运行时复用填充 |

## 5. 状态机（`GameState.Phase` 数值不可随意变更，需同步 UI 与测试）

| 值 | 名称 | 允许主要动作 |
| ---: | --- | --- |
| 0 | LOBBY | 注册、房主开始 |
| 1 | INITIAL_PEEK | 玩家确认记住开局两张牌 |
| 2 | TURN_DRAW | 当前玩家抽牌/取弃牌顶/喊 Kongbaya；`slap_open` 时也允许所有人贴牌 |
| 3 | TURN_DECISION | 替换、弃抽到的牌、发动技能 |
| 4 | Q_DECISION | Q 操作者决定不换或交换 |
| 5 | SLAP_WINDOW | 已弃用（不再进入）；贴牌窗口改为 `slap_open` 标志 |
| 6 | SLAP_EXCHANGE | 贴中他人者交出一个槽位 |
| 7 | GAME_OVER | 公开所有牌并显示结果 |
| 8 | SLAP_DUEL | 多人同时贴中 → 比拼 bar，比谁最接近随机加粗区中心红心 |
| 9 | BET | 存活玩家押注（入场 20，+5 递增，上限 100 且 ≤ 货币；货币 < 入场自动 all-in，`bet` RPC） |
| 10 | SHOP | 系列赛非把末结算后进入商店：存活玩家限购 1 件固定价遗物（`shop_buy`）或跳过（`shop_skip`），全员完成后开下一局；把末不进商店 |

## 6. 网络与隐私契约（详见 `网络协议_V1.md`）

- 房主 `Network.host_game`（ENet peer ID = 1）；客户端 `Network.join_game` + 注册昵称。
- 命令进入 server `server_*` RPC → 私有 `_server_*` 验证。
- 状态消息：`receive_lobby`/`receive_state`/`receive_reveal`/`receive_toast`/`receive_peek_highlight`，牌面仅允许在弃牌顶、行动者的待处理抽牌、结算牌中出现。
- 请求方向：`slap`（`TURN_DRAW` 且 `slap_open`）、`slap_exchange`（`SLAP_EXCHANGE`）、`slap_duel_stop`（`SLAP_DUEL`，仅候选人）。快照 `slap_duel` 仅在 `SLAP_DUEL` 存在（`contestants`/`duration_ms`/`deadline_server_ms`/`target`，均公开）。
- 查看高亮 `peek_highlight`：仅含 `{player_id, slot}` 位置、**不含牌面**（详见 `网络协议_V1.md` 4.6）。非当前玩家看到的大牌为**背面**（`pending.hidden=true`，Feature0）。
- 交换动画：server 广播 `card_exchange_animated` 事件（kind: `replace`/`swap`/`discard`/`slap_penalty`/`slap_resolved`/`slap_gift`），各 client 用**自己视角的 `_card_slots`** 定位播放。`slap_gift`/`slap_penalty` **不含牌面**（防泄漏）；`slap_resolved` 含 card（被贴的牌已通过贴牌 reveal 公开）。
- 贴牌 reveal target 携带 `correct: Boolean`（客户端据此打绿/红炫光）。

## 7. 关键 bug 档案（已解决，复现时按诊断方法修复）

> 完整档案见 `BUG档案.md`。核心三条，容易因后续需求复发：

- **B1 大牌位移**：`Control.scale`+`pivot_offset`+`global_position` 组合位置漂移 → 用**实际尺寸定位**，不用 scale。
- **B2 槽位永久虚线**：GDScript lambda 捕获 int 计数器不累积 → 用**字典计数器 + bind**。
- **B3/B4 hint 问题**：RichTextLabel 不显示 → 回退 Label；每字一行 → 设固定宽度。
- **B6 大牌被裁剪 / “看得见点不到”**：大牌在容器内被裁剪、点击被上层拦截 → 大牌挂 **GameBoard 顶层**（`pending_overlay = board`），board `mouse_filter=PASS`、大牌卡 `IGNORE`。
- **B7 贴牌揭示露默认背面**：翻牌期间底层原卡暴露 → 揭示期间 `mark_anim_slot` + 隐藏原卡，结束后恢复。
- **B8 比拼无人 STOP 崩溃**：`resolve_duel` 里 `best` 初值 0，全员未按 STOP 时访问 `slap_duel.correct[0]` 报错 → 结算后 `best==0` 时兜底选第一个候选人。
- **B9 DuelBar 弹窗不可见**：弹层加进 `overlay` 时自身尺寸为 0（默认锚点），内部全屏遮罩/居中容器随之 0 尺寸 → `_build_ui` 开头 `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`。
- **B10-B13（贴牌动画）**：贴错无红光/罚牌无 fly（reveal 按"是否贴牌"分发 + 罚牌槽挂起补飞）、罚牌 fly 位置错/提前落位（同步定位 + 先标记动画槽）、罚牌附加卡随卡数重排（按槽号固定绝对定位）、罚牌持久正面（已回退为背面 fly）。详见 `BUG档案.md`。
- **B18-B22（本次会话新增）**：重连后手牌永久正面（移除 `_resume_hand_map` 渲染）、replace 落位后闪烁（每段 fly 各自落位刷新 `_replace_landed`）、discard-replace 后所有手牌两行 gap + J 能力 locked 报错（`_clear_area` 改为 remove_child + queue_free）、Kongbaya 不结算/可重复喊叫（`kong_caller` 哨兵 0→-1 + declare 拦截）。详见 `BUG档案.md`。
- **B23-B26（结算页相关，本次会话新增）**：结算页按钮点不到（根 STOP + 直挂 main 末尾 + z100）；再来一局泄漏旧卡 id 致 public_card 错（`_deal_new_match` 补按局清理）；`_card_slots` 残留已释放节点致贴牌 freed instance（渲染前清空）；结算时被 peek 的牌翻回背面（`_render_game_if_active` 守卫 + 结算渲染前清动画残留）。详见 `BUG档案.md`。

## 8. 验证命令（headless 单元测试，不启动 GUI）

> **一键全量回归**：`tools/run_all_tests.sh`（编译检查 + 全部单进程/双实例/网络注入测试，汇总 PASS/FAIL；`--quick` 只跑单进程核心；`--include-hint` 连已知失败的 hint 一起跑；`GODOT=/path` 覆盖引擎路径）。

```bash
# 编译检查
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
# 协议测试（38/38）
... --headless --path . res://tests/verify_protocol.tscn
# 交换动画测试（10/10）
... --headless --path . res://tests/verify_swap.tscn
# 贴牌比拼测试（31/31：单正确/双正确比拼/超时/无人 STOP/调试模式/错误码）
... --headless --path . res://tests/verify_duel.tscn
# 断线重连测试（41/41：seat 身份/离线标记/条件暂停/踢出/中止/解散/token 认领/手牌恢复）
... --headless --path . res://tests/verify_reconnect.tscn
# Kongbaya 最终轮测试（15/15：正常最终轮结算/重复喊叫被拒/首·非首回合标记）
... --headless --path . res://tests/verify_kongbaya.tscn
# 结算模型 + 再来一局 + 结算页/棋盘联动 + 回归（38/38）
... --headless --path . res://tests/verify_settlement.tscn
# 系列赛框架（41/41：多局/把末判定/出局观战/把末总排名）
... --headless --path . res://tests/verify_series.tscn
# 货币经济（33/33：结算2x+垫底/安全1.5x/垫底全失/系统补足/all-in出局/并列/首回合Kong/超限/押注阶段）
... --headless --path . res://tests/verify_economy.tscn
# 商店固定价购买（遗物定义/流程进店/购买扣款入库/售出先到先得/钱不够拒绝/限购1件/全员完成后下一局）
... --headless --path . res://tests/verify_shop.tscn
# 遗物效果 v1（19/19：护盾局开始生效并消耗/贴牌与J·Q交换免疫(PROTECTED)/快照护盾标记/无遗物no-op/Joker变换/未变换+2/已变换清除加成）
... --headless --path . res://tests/verify_relics.tscn
# hint 生成测试（8/8）
... --headless --path . res://tests/verify_hint.tscn
# 双实例网络回归（host + client 各跑，均 exit 0）
... --headless --path . res://tests/verify_net.tscn -- -role host
... --headless --path . res://tests/verify_net.tscn -- -role client
```

### 8.1 网络条件注入测试（`verify_proxy`，ProxyRelay UDP 中继）

> **作用**：在本地确定性复现公网问题。host 进程内挂 `scripts/net/proxy_relay.gd`（监听 7011 → 转发到真实服务器 7007），客户端连 7011。中继在**数据报层**注入条件，会真实影响 ENet 自身的 keepalive/ACK/重传——比"引擎内包一层 peer"更接近真实链路。
> **语义注意**：丢包/乱序/重复发生在数据报层会被 ENet 可靠通道吸收（重传/排序/去重），所以中继验证的是"链路物理特性（延迟/丢包/抖动/中断）下的健壮性"；RPC 层重复请求幂等由 `verify_protocol` 的拒绝校验覆盖。启动参数可覆盖：`-latency X -loss X -jitter X -seed N`。
> 场景与"人话"解释（每个场景启动时会打印本行，失败时打印对应排查提示）：

| 命令（host / client 各一行，成对跑） | 人话：在测什么 | 失败时大概率说明什么 |
| --- | --- | --- |
| `... -role host -scenario baseline` / `... -role client -scenario baseline` | 基准无注入：链路与测试脚本自检（等价 verify_net） | 测试链路本身有问题，先查 verify_net |
| `... -scenario latency` | 固定 200ms 延迟：回合制在公网级延迟下能否正常推进 | 某流程在等即时响应，或 ENet 超时过紧（可放宽 set_timeout） |
| `... -scenario loss` | 20% 丢包：ENet 重发后状态是否最终一致、对局不卡死 | ENet 未按时收敛，超时太紧或 RPC 依赖瞬时到达 |
| `... -scenario jitter` | 0~150ms 抖动：延迟波动下回合推进/快照是否正常 | 存在基于固定延时的逻辑 |
| `... -scenario baseline -mode reconnect` | 中继"拔网线"（黑障 3s~11s）→ ENet 超时掉线 → 服务器标记离线 → 客户端凭 token 重连 → 手牌恢复 → 对局继续 | 离线标记 / token 认领 / 手牌恢复某环断裂 |

```bash
# 每个场景跑两遍（host 与 client 分别），例如：
... --headless --path . res://tests/verify_proxy.tscn -- -role host -scenario latency
... --headless --path . res://tests/verify_proxy.tscn -- -role client -scenario latency
# 断线重连（relay 黑障模拟拔网线）：
... --headless --path . res://tests/verify_proxy.tscn -- -role host -scenario baseline -mode reconnect
... --headless --path . res://tests/verify_proxy.tscn -- -role client -scenario baseline -mode reconnect
```

> **开发约定**：按用户的指示**不启动 GUI**，用上述 unit test 验证后总结。每次改动后跑 `verify_protocol` + `verify_swap` + `verify_duel` + `verify_reconnect` + `verify_kongbaya` + `verify_economy` + `verify_shop` + `verify_relics` + 双实例 `verify_net`。

## 9. 给后续 Agent 的工作方式

1. 先说明改哪个模块、为何不破坏第 3 节不变量。
2. 改动规则前更新 `KONG_开发文档.md`；改协议前更新 `网络协议_V1.md`。
3. 一次只解决一个可验证问题；保留文件名/RPC 名/状态机，除非迁移计划写清楚。
4. 每次提交按 **功能/修复/文档** 分类（`feat/fix/doc`），并 `git push origin main`。
5. 若用户只要求文档/设计，**不得顺手重构或补写游戏代码**。
6. 未决/歧义项入 `docs/问题档案.md`；系统级/冻结规则问题暂停等待确认。
7. **用户每次 request 结束，向 `docs/修改日志.md`（开发者个人追踪）追加记录**，但不提交（该文件 gitignore）。

建议接手的首句：

> 请先阅读 `docs/AI_AGENT_交接说明.md`（本文件）、`docs/BUG档案.md`、`docs/KONG_开发文档.md`、`docs/功能实现文档.md`。保持 `GameState` 服务器权威与私有快照架构不变；先验证，再只修复已复现问题。
