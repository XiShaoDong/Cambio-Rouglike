# KONG：AI Agent 交接说明（Agent 必读 · 工程现状与工作方式）

> **本文档职责**：只给 **AI Agent**。用于让下一个 Agent 快速理解当前工程，在不重构既有基础的前提下继续开发。开始任何改动前，按第 1 节文档地图顺序阅读对应文档。规则/协议/测试权威见各文档，本文件不重复，只给"工程现状、架构不变量、工作方式、验证命令、关键 bug 档案入口"。

---

## 1. 文档地图（每个文档职责 + 给谁看）

| 文档 | 职责 | 给谁看 |
| --- | --- | --- |
| `AI_AGENT_交接说明.md`（本文件） | 工程现状、架构不变量、工作方式、验证命令、文档地图 | Agent 必读 |
| `BUG档案.md` | 已解决 bug + 根因/修复/诊断方法（防复发） | Agent + 开发者 |
| `KONG_开发文档.md` | 规则/产品/架构**权威**主规格（R-01~R-12 等） | 权威 |
| `网络协议_V1.md` | RPC/快照字段、错误码、隐私/幂等契约 | 权威 |
| `验收与测试计划.md` | T/P0-N 用例、验证闸门 | 权威 |
| `功能实现文档.md` | 文件树 + 16 Feature 映射 + 待开发清单 | Agent + 开发者 |
| `3D角色与场景说明.md` | 3D 对局场景布局/文件地图 + Robot 角色系统（模型嵌入/眼动）+ 三阶段路线图（Robot→眼部追踪→手部动作） | Agent + 开发者 |
| `UI主题规范.md` | 主题令牌（dark/light） | 开发者 |
| `问题档案.md` | 未决/待确认问题登记 | Agent + 开发者 |
| `未解决的BUG.md` | **未复现/原因未确认**的 bug（含代码路径分析与排查建议；确认根因后迁入 BUG 档案） | Agent + 开发者 |
| `遗物设计卡模板.md` | Roguelike 设计卡填写模板 | 开发者 |
| `修改日志.md` | **开发者个人**追踪（request→实现→反馈，gitignore，不纳入版本） | 开发者，非 Agent |

> 开发者用途文档（修改日志、UI主题、遗物模板）对 Agent 只需知道"存在 + 各自职责"，不强制读全文。

---

## 2. 当前基线

- 项目：Godot 4.6，KONG（Cambio + 轻度 Roguelike）LAN MVP。
- 当前目标：系列赛框架、名次奖励经济（R-12）、商店固定价购买、**遗物效果 v1** 已完成（见下）；基础模式（无遗物）始终可独立运行。
- 联网：ENet/UDP，房主权威，默认端口 `7007`。
- 状态：大厅、对局界面、服务器权威状态机、规则、动效系统均已实现；已有自动化验证（见第 8 节）。
- 当前工作分支：`feature/card-animation`（从 `feature/3d-table` 拉出，均未合入 main）。该分支完成**卡牌交互动效系统**：独立 3D 沙盒原型 + 3D 桌面 hover 抬起/倾斜接入（仅 viewer 自己手牌）+ `CardBlock` 揭示改用真实 3D 翻转（双面几何）。另有**实验分支 `feature/hover-curve`**（hover 顶点弯曲，未合并）。`feature/card-template` 完成**卡牌皮肤 / TypeCards 图集 + 开发者面板皮肤切换**（见下条）；`feature/store` 完成**系列赛框架 / 名次奖励经济（R-12）/ 商店固定价购买 / 遗物效果 v1**，设计在 `docs/superpowers/specs/2026-09-07-series-shop-relics-design.md`，各里程碑计划在 `docs/superpowers/plans/`。此前 `feature/internet-reconnect` 的 seat 身份重构 + 断线重连 + 结算页 + 音效/设置菜单均已合入（见 3.5 节与 B18-B26）。当前分支 **`feature/3d-ui`**（从 `main` 拉出）完成 **3D 交互与 HUD 打磨**：行动提示/高亮随本地交互即时刷新（B41）、Q 看牌 hold + 释放翻回动画 + 交换飞牌正面起飞（B42）、3D peek 蓝光跨 render 保持（B43）、J 盲换改确认式（与 Q 同款）、决策按钮放大+hover、Ready 加大+hover+交互时提示板贴准星、Command/Alt 拉近视场、左下按键提示 + 右上回合徽标 + Tab 手册、四角 HUD 边距 75 + dark 纯白底白字（纯客户端展示层，见下末条与 §7）。此前分支 **`feature/3d-hologram-board`** 完成 **3D 全息看板（悬浮 UI 宿主）** + **3D 大牌（Pending）竖立悬浮朝相机 / 两堆对称于桌心 / 手牌两列居中** + **Table3D Tuner 调参工具**。
- **贴牌系统（已重做动画）**：固定 2.5s 窗口 → `slap_open` 标志（弃牌/用技能后开启，下一玩家抽牌关闭）；同一窗口**不限次数**尝试（贴错每次罚牌，贴对先到者胜）；多人同时贴中 → 400ms 收集 → `SLAP_DUEL` 比拼 bar（随机加粗区中心红心，服务器到达时间判最近者）；调试开关 **O 键**切换 `debug_duel`（不判正确性 + 双贴即比拼）。
- **贴牌动画事件（`card_exchange_animated` 新 kind）**：`slap_penalty`（罚牌 fly 抽牌堆→手牌）、`slap_resolved`（赢家被贴的牌 fly→弃牌堆，弃牌堆延迟显示）、`slap_gift`（交换时行动者的牌 fly→对方槽，不带牌面防泄漏）。贴牌 reveal target 带 `correct` 标记 → 客户端打**绿（对）/红（错）炫光**；正确贴牌**绿光 hold**（v2，不翻回）等结算后 fly，比拼输家翻回。
- **手牌超限规则（R-07）**：任一玩家手牌总数 `> MAX_HAND_CARDS(6)` 时对局立即结束（GAME_OVER），该玩家判定失败并扣 1 生命，其余玩家按各自手牌点数结算排名（失败者不参与排名）。触发点：贴错罚抽后 `game_state._check_over_hand(seat)`。
- **结算页（同步轮记分，R-08）**：GAME_OVER 后弹出居中浮动排名窗口（`scenes/ui/settlement_page.tscn` 场景实体 + `settlement_page.gd`，不遮挡棋盘卡牌区）；**棋盘卡牌结算时初始为背面**，由算分动画**逐张联动翻面**（`_on_settlement_flip` → `CardView.flip_reveal`，与行内记分同一时刻，每张间隔 `FLIP_STEP`）；行内累计分滚动累加，每轮后排名表整行上移/下移实时重排（数据来自 `settlement_model.gd` 纯计算 `layout_order`/`rounds`/`ranking`）；全部翻完冠军行名字金色脉冲光环 + ★ 徽章，胜利音效（Winner01-04 随机）**延迟到冠军时刻**播放（`main._pending_winner_sfx`）；房主可「再来一局」（`request_next_match`，GAME_OVER 后直接开新局，`match_number` 递增）/「返回大厅」，客户端显示等待提示。reason-only 结算（无 ranking）不弹结算页。
- **结算页输入约定（B23）**：结算页根节点 `mouse_filter=STOP` 且**直挂 main 末尾 + z100**（不可挂 overlay/IGNORE，否则 4.6 picking 判不可点）；对局进入 GAME_OVER 时先 `_clear_settlement_anim_state()` 清残留动画再渲染；动画完成回调一律走 `_render_game_if_active()`（GAME_OVER 时跳过，防在途揭示延迟重渲染把翻开的牌翻回，见 B26）。
- **J 盲换 = 与 Q 同款确认流程**：用能力（点弃牌堆）后出现「J：不交换」「J：交换」（`ActionModel.conditional_actions(state, ctx)`，`ctx` 来自本地 `interaction`）；先选对方牌再选自己牌（`jack_target`→`jack_own`→`jack_ready`），**两张都选齐前「交换」禁用**、选齐后**不自动交换**，需点「交换」(`jack_swap_now` → `request_use_ability`) 或「不交换」(`jack_cancel` → `request_discard_draw`，弃掉抽到的 J)，仍可点卡改选；hint 提示选两张牌。与 Q 的唯一区别是 J 需玩家各选一张（Q 是服务器先给看牌再出按钮）。
- **Kongbaya 最终轮**：一场对局只允许喊一次（`kong_caller != -1` 后任何玩家再喊均拒绝）；喊出者不再行动，其余玩家按顺时针各执行一轮最终行动后统一结算。`kong_caller` 哨兵值为 **-1**（不能用 0，房主座位是 0）。
- **系列赛框架（已完成）**：房主开局设定 `match_limit` X（2-10 默认 5）把单局扩展为多局系列赛。`_server_start_match(match_limit)` 存 `run.match_limit`；每局 GAME_OVER 非把末由服务器 Timer 自动开下一局、把末（`_series_finished()`）不启动；`health==0` 者出局观战（`eliminated==true`，保留座位、仅公开信息、不可操作，`_guard_spectator()` 接入全部动作 RPC）；把末总排名 `series_ranking.gd` `SeriesRanking.final_ranking()`（存活者胜场降序→同胜场货币降序，淘汰不入榜），`result.series` 只在把末存在。测试 `verify_series.gd`。
- **名次奖励经济（R-12，已完成）**：取消开局押注阶段（`Phase.BET`（值 9）**保留为弃用值**，任何流程不再进入），开局记忆全员确认后直接进入 `TURN_DRAW`。起始 **100 货币 + 2 生命**（`health` 默认 2）。每局结算 `_settle_rewards` 按名次由系统发钱：第一 +40、中间 +10、垫底 0（并列组按区间奖励平分，全员同分各 +10、无人扣血）；**垫底（含并列）扣 1 生命**，`health==0` 出局观战；手牌超限（R-07）与首回合 Kongbaya 失败者按垫底处理（0 金钱、−1 生命）；货币不扣、下限 0，出局者保留货币参与把末排名。快照移除 `bet_ready`，`result.economy` 改为 `result.rewards = {SeatId: {money, life_lost}}`，`result.penalized` 为扣血者。局内货币/生命 HUD 在每玩家区域手牌右侧（`coin_icon`/`life_icon`/`stat_hud`），名字标签不再显示货币。测试 `verify_economy.gd`（29/29）。
- **商店固定价购买（已完成）**：系列赛非把末结算后进入 `Phase.SHOP`（值 10），展示至多 3 件随机遗物（v1 池 2 件，`scripts/core/relics.gd` 数据 + `pool()`/`def_by_id()`，各固定价 `RELIC_PRICE=50`）。每位存活玩家**限购 1 件**：点击遗物且货币 ≥ 售价即 `_server_shop_buy` 扣款、`run_state.relics[relic_id]` 入库并记持有者 `run_state.relic_owners[relic_id]=seat`，同件**先到先得**（`shop.sold[offer]` 售出后他人不可再买）；也可「跳过购买」（`request_shop_skip`）。全员完成（购买或跳过，`shop.done`）→ `_deal_next_match` 开下一局；货币不足只能跳过。把末不进商店。新 RPC：`request_shop_buy(offer)`/`request_shop_skip()`；错误码 `INVALID_OFFER`（越界/已售出）/`INVALID_AMOUNT`（钱不够）。快照 `shop` 公开投影 `offers:[{id,name,price,sold_by}]` + `done`（固定价无密封字段）；`shop_result` 公开（谁以多少购买）。客户端 `scenes/ui/shop_panel.tscn` + `shop_panel.gd`（点击遗物购买 / 已售出·货币不足·已完成状态 / 「跳过购买」按钮，随快照刷新）+ `main.gd`（`_open_shop_panel` 开/刷新、`_on_shop_buy`、`_show_shop_result_toast`）；`settlement_page.gd` 非把末 footer"即将进入商店…"。规则见 `KONG_开发文档.md` §3.7 R-10；测试 `verify_shop.gd`（23/23）。
- **遗物效果 v1（已完成）**：`Joker 变换`（持有者在抽牌阶段抽到 Joker——抽牌堆或弃牌堆顶——可选变换为任意牌；未变换时其手中 JOKER 分值 +2，`_relic_card_value` 统一结算与揭示）与 `防守护盾`（购买后**下一局开局**随机护盾持有者一格并消耗，该格免疫其他玩家贴牌与 J/Q 交换，看牌/自操作不受影响，一局后失效）。钩子落点：`_apply_match_start_relics`（局开始消耗护盾）/`_server_joker_transform`（Joker 变换 RPC）/`_relic_card_value`（结算统一计分）/`_is_protected`/`_is_relic_owner`（持有者判定，`run_state.relic_owners`）；`RejectCode.PROTECTED`；护盾格快照 `protected`；`ScoreSystem.calculate_ranking` 加 `joker_bonus` 参数。客户端 `JokerTransformPanel`（`scenes/ui/joker_transform_panel.tscn`）+ "变换 Joker" 按钮；**遗物 UI**：护盾受保护格常驻紫色描边光晕 + ◈ 紫角标（`game_view._render_card_slot`），每玩家区域左侧遗物物品栏（`RelicBar`：3 槽 + `n/3` + 程序化盾/星图标 `RelicIcon` + Hover Tooltip 名称/描述/状态，数据全部来自快照公开字段，纯展示无协议改动）。规则见 `KONG_开发文档.md` §3.7 R-11；测试 `verify_relics.gd`（19/19）。
- **卡牌皮肤 / TypeCards 图集（已完成，客户端展示层）**：卡牌正/背面**默认使用原始素材**（`assets/Cards/*.png` + `back07.png`），保持既有观感。开发者面板（`T` 开发者模式 · 房主对局中）新增"卡牌皮肤"全局单选：**原始 / 普通 / 石头 / 纸牌 / 玻璃**，后四者来自 4× 高清图集 `assets/TypeCards/opersze-cards-full-clear-4x.png`（3080×4928，每格 220×308；14 列 × 16 行，4 行一组 normal/stone/paper/glass，组内行 ♥♠♦♣，列 c0..c12=2..A，c13=组首行卡背 / 组第 3 行红 Joker / 组第 4 行黑 Joker；stone/paper 无黑 Joker → 回退红 Joker）。落点：`scripts/ui/card_atlas.gd`（`CardAtlas`：`face/back/joker` → 带缓存 `AtlasTexture`；`ORIGINAL/TYPES/SKINS` 常量；`static var preview_type` 默认 `original`）；`card_view.gd`（`type==original` 走旧素材，其余走图集，图集缺失回退旧素材；`card_data["type"]` 可显式覆盖预览）；`dev_tools.gd`（3 列网格皮肤按钮）。卡牌显示尺寸统一为图集原生比例 5:7（`CARD_SELF_SIZE` 64×90 / `CARD_PILE_SIZE` 76×107 / `CARD_BIG_SIZE` 110×154 / `player_area.card_size` 64×90 / 商店卡位 94×132）。**不改**服务器/协议/快照——`card_data["type"]` 为预留字段，未来接入玩法零改渲染层。测试 `verify_card_skin.gd`（35/35）；设计见 `docs/superpowers/specs/2026-09-16-card-template-design.md`。
- **卡牌交互动效系统（沙盒 + 3D 接入，分支 `feature/card-animation`，纯客户端展示层，规则/协议/快照零改动）**：
  - ① **独立 3D 沙盒**：`scripts/ui/card_animation_config.gd`（参数集中 + `validate`）/`card_animation_math.gd`（纯函数：状态机/缓动/高度/阴影/`compose`）/`card_animation.gd`（控制器）+ `card_animation_sandbox.gd` + `scenes/ui/card_animation_sandbox.tscn`。架构 = **分层 Offset 合成 + 标量进度 + 纯函数**：Tween 只驱动 `hover/press/flip/land` 标量，唯一写 transform 处是每帧 `CardAnimationMath.compose()`（`visual_pos`/`visual_rot_deg`/`flip_deg`/`visual_scale`/阴影），解决多个 Tween 争抢同一属性；状态机 `IDLE/HOVER/PRESS/FLIP/LAND`；**离桌补偿**（倾斜时抬高中心，近边始终留 `hover_clearance` 缝隙）；blob 阴影（`shadow_enabled` 默认关）；相机环视 + 屏幕中心准星拾取自身槽的 pick pose。测试 `verify_card_animation`（68/68）。
  - ② **3D 桌面 hover 抬起/倾斜**：`CardBlock` 加 `_visual` 视觉 pivot（`Mesh`/`Glow*`/`Label` 挂其下，**拾取 `Area3D` 留在根、不随动画移动** → 不抖）+ `set_hover_pose(on, ray_local, immediate)`；`table3d_view` 记 `_viewer`/`_hover_slot`/`_hover_ray_local`，只对 **viewer 自己手牌**启用，`render()` 重建后**即时重放**（不弹跳），`clear_hover` 复位。`table3d_picker.pick_hit` 返回值增加命中点 `"position"`。
  - ③ **揭示真实 3D 翻转**：`CardBlock` 改**双面几何**（`_front` + 预旋 180° 绕卡长轴的 `_back`，翻面后正向**不镜像**）；`reveal/restore` 从 `scale.x` 压扁换成**抬起 + 朝玩家倾斜 + 绕长轴 0→180°**（标量 `_reveal_p` + `_flip` pivot，`FLIP_DURATION=0.5s` 整段）；访问器按"朝上可见面"（`_display_material`）。
  - 设计/计划：`docs/superpowers/specs|plans/2026-09-25-card-animation-sandbox-design.md`、`…-table3d-hover-animation-design.md`、`…-cardblock-3d-reveal-flip-design.md` 及对应 plans。
  - **实验分支 `feature/hover-curve`（未合并）**：hover 顶点弯曲——`CardBlock.set_bend(height)` + `set_bend_profile(start, exponent)`（起点比例 0=整段/0.5=从中心、曲度指数 1=直线/2=抛物线），**CPU 顶点形变无 shader**（细分平面重建顶点，远端贴桌、近端上翘）；`CardAnimation.hover_bend*` + 沙盒根同名 `@export` 面板可调。该分支 `verify_card_animation` 73/73。
- **3D 桌面只读预览（Milestone 1，分支 `feature/3d-table`）**：对局中按 `F10`（**macOS 上 F1-F12 默认是媒体键，F10 会被系统截走收不到；备用键 `V` 同样切换**）在 2D 界面与 3D 桌面间切换；3D 用方块 + `Label3D` 渲染公开快照（座位手牌、抽牌堆数量、弃牌顶、中央 pending、名字/张数/货币/生命），鼠标环视（pitch ±60°、yaw 基准 ±90°、灵敏度 0.5 度/像素，鼠标右移=向右转）；**按住 Command/Alt 拉近视场（放大，`Table3dCamera.set_zoom` FOV→`ZOOM_FOV`），松开恢复，退出 3D `reset_zoom`**。纯客户端展示层：`scripts/ui/table3d_layout.gd`（纯函数布局）/`card_block.gd`/`table3d_camera.gd`/`table3d_view.gd` + `scenes/ui/table3d.tscn`。**不改**规则/协议/快照/现有测试。测试 `verify_table3d_layout`（19/19）、`verify_table3d`（39/39）、`verify_table3d_mouse`（10/10）。环视输入走 `main._input`（避免 GUI 吞事件）。不做点击交互与动画（Milestone 2+）。
- **3D 桌面对局（Milestone 2，分支 `feature/3d-table`）**：3D 预览内用**屏幕中心准星**点击（默认俯角对准桌心，准星起始落在牌堆；悬停可点目标时准星变金 + 目标 3D 高亮 `table3d_view.update_hover`）（`Area3D` 拾取层 2 + `Table3dPicker` 射线）→ 分发到既有 `GameInteraction.on_card_pressed` / `request_take` / `_on_pending_action`；**条件动作按钮（Q 交换/不交换、变换 Joker）与 Ready 均在常驻提示板（`hint3d`）提示文本下方**（与 2D `HintArea/HintActions` 一致）；3D 桌面 HUD（`Table3dHud`）不再承载按钮（Kongbaya 由 3D 铃铛负责）；可操作/悬停/护盾/揭示均走**卡牌边缘发光**（多层半透明外扩平面，不整牌染色，与 2D 同策略）；**揭示走水平翻转**（`scale.x` 1→0 换面→0→1，与 2D `flip_to_face` 同策略；`reveal_slot` 记录在 `_reveals`，**`render` 重建卡牌后重新应用**，否则状态广播会冲掉翻牌；`flash_slot` 传色）。2D 模态（结算/商店/Joker/比拼/重连）打开时自动释放鼠标、关闭后恢复准星环视。**角色**：每席 `Avatar`(椭圆头 `SphereMesh` + 方体身 `BoxMesh`，身体在头心正下方)；**角色放在眼位**——径向外移 `CAMERA_BACK`、头心抬到 `EYE_HEIGHT`（场景实例 `EYE_HEIGHT=3.5`、`CAMERA_BACK=1.5`、`MOUSE_SENSITIVITY=0.35`，可在检视面板调），`table3d_view._apply_avatar` 按相机参数摆位，故相机即在 viewer 头心；**viewer 自己那席整个角色隐藏（头+身体都不出现）**；出局/离线加暗 overlay（**不再按回合染色**）。**回合标识**：当前行动者（且非自己那席）名字面板上方挂**红色倒三角 `TurnMarker`**（程序化 `ArrayMesh` 3 顶点 + **黑色空心边环**（18 顶点，不遮红心）；顶部「看牌」`Label3D`（白色）；均 billboard + `no_depth_test` + emission；无动画；紧贴名字面板上方；LOBBY/GAME_OVER/SHOP 不显示）。角色不挂拾取层，不影响准星。**动作判定统一走 `ActionModel`；玩家状态 UI 自己=屏幕右下、他人=头顶 SubViewport 面板；Kongbaya=3D 金铃铛；大牌（Pending）竖立悬浮于桌心正上方（两堆中点）、每帧朝向本机相机（table3d_view.update_facing() + CardBlock.set_upright()）**。规则/协议/快照零改动。测试 `verify_table3d_interaction`（76/76）。不做飞牌过渡与 3D 菜单/3D 商店结算/遗物栏（揭示翻转已有）；**3D 下不播 2D 换牌/贴牌 fly**（`card_exchange_animated`/罚牌在 3D 直接跳过，避免 2D 副本浮在 3D 画面上）。
- **3D 静态骨架已入场景（场景+代码混合，分支 `feature/3d-table`）**：环境/相机 rig/**桌面(7×7 方桌 + `TableEdge` 深色边框)**/4 座位(HandAnchor + **Avatar(Body+Head)** + 头顶 `StatPanel` Sprite3D)/Center(Deck·DeckCount·DiscardTop·Pending·KongBell 金铃铛)/Hud 全部在 `scenes/ui/table3d.tscn`（可在编辑器拖拽调位置）。**卡牌平铺桌面**：`Table3dLayout.BLOCK_SIZE = (0.7, 0.04, 1.0)`（X 宽×Y 厚×Z 深），**座位角度按 2D 箱位对齐**（`seat_angles` = `[0,270,90,180]`：viewer 近侧、其余依次对应 2D 左/右/上箱，**不再沿圆均分**），**槽位主牌 2×2 行优先（0/1 上、2/3 下，与 2D 同；开局揭示的 2/3 即下排），罚牌向右追新列、每列先上（远）后下（近）**（`slot_grid_pos`：`slot<4`→`(slot%2,slot/2)`、`slot>=4`→`(2+(slot-4)/2,(slot-4)%2)`；`table3d_view._slot_local` 取本地 `(0.5-列)`×X（主牌两列以列中点居中于座位 x 中轴，故两列落在 ±半个列距）与 `(1-行)`×Z，故新槽位向持有者右手侧追加），`HandAnchor` 贴近桌面（y≈0.03），`DiscardTop`/`Deck` 平铺（两堆沿 X 关于桌心对称：Deck/DeckCount 在 -0.45、DiscardTop 在 +0.45，KongBell 在 -1.2；`Pending` 竖立悬浮于桌心正上方，见 Milestone 2 段）；**未知牌用现有卡背贴图** `assets/Cards/back07.png`，**已知牌用真实牌面**（`original` 皮肤读旧素材 `assets/Cards/{suit}_{rank}.png`，其余皮肤走 `CardAtlas.face`；贴图缺失回退分类色）；**卡面用 `PlaneMesh(FACE_Y)`** —— 注意 `BoxMesh` 的 UV 是十字展开会裁掉贴图，不能用。点数标签 billboard 悬于卡上方。**相机**：`Table3dCamera` 的 `EYE_HEIGHT/CAMERA_BACK/MOUSE_SENSITIVITY` 为 `@export`（场景实例 3.5/1.5/0.35，可在检视面板调）；`frame_for_seat` 默认俯角 `aim_pitch_deg()` **对准桌心**（准星起始落在牌堆，否则点不到东西）。**节点名/路径是契约**，`Table3dView._bind()` 按固定路径解析、缺节点 `push_error` 不静默；`Table3dCamera` 不自建 `PitchPivot/Camera3D`（由场景提供）。**代码仍负责**：每槽 `CardBlock`（动态）、HUD 按钮内容、染色/揭示/高亮、座位位置与朝向、相机取景、HUD 跟随 viewer、角色可见性/状态 overlay、`_card_blocks`、`pick_center`。**布局数学仍在 `table3d_layout.gd`**。约定：该 `.tscn` 由开发者拥有视觉调整，Agent 改其结构前先 `git diff`/重读；动态对象（卡/按钮）不得搬进场景。
- **3D 换牌动画（沙盒 + 已接入对局；分支 `feature/card-animation`，纯客户端展示层，规则/协议/快照零改动）**：独立 3D 沙盒原型 `scripts/ui/card_fly_sandbox.gd` + `scenes/ui/card_fly_sandbox.tscn`（复刻对局布局：4 座位手牌区 + 中央 `Deck`/`DiscardTop`/`Pending`），顶部 6 按钮分别演示 `card_exchange_animated` 的 6 种 kind（replace/swap/discard/slap_penalty/slap_resolved/slap_gift）。四层架构：`card_fly_math.gd`（纯函数：**恒定速度** `dist/speed` / 路径缓动 / `sin(p*PI)` 弧线 / 翻面窗口 / `compose` 变换合成）+ `card_fly_config.gd`（参数 + 校验；`speed=3.0`、`duration_min=0.15`）+ `card_fly.gd`（单张飞牌控制器：Tween 只驱动标量 `p`，每帧 `compose` 唯一写 transform；复用 `CardBlock` 双面几何绕卡长轴翻面，飞牌本身不改 `card_block.gd`；结束发 `finished` 并 `queue_free`）。**已接入对局 3D**：`main.gd` 在 `card_exchange_animated` 处理器加 3D 分支 → `table3d_view.animate_exchange(data)`；编排放 `table3d_view` 内（`_anim_slots` 跨 render 隐藏在途槽位、`_discard_hold` 延迟弃牌顶、`slot_xform` 布局兜底支持未渲染新槽、`CardFly.finished` 落地后用 `_last_state` 重渲染），6 kind 与 2D 面/隐私策略逐条对齐。**抽牌飞牌**（新增）：快照检测 `pending` 由空→非空即播「抽牌堆/弃牌堆 → 竖立大牌」飞牌（**所有人可见**；行动者飞行中翻正面、他人背面）；来源判定用「弃牌顶是否变化」区分抽/取弃牌顶（**不改协议/快照**）；`_pending_hold` 飞行期间隐藏大牌、落地显示；进入 3D 首帧不触发（`_pending_seen`）；`main._on_deck_pressed` 仅在非 3D 置 `_draw_flip_pending`（避免 2D 抽牌副本浮在 3D 上）。**2D 逻辑零改动**。测试 `verify_card_fly`（40/40）+ `verify_table3d_exchange`（54/54）；设计见 `docs/superpowers/specs/2026-09-30-3d-exchange-animation-integration-design.md`。
- **3D 全息看板（悬浮 UI 宿主，分支 `feature/3d-hologram-board`，纯客户端展示层，规则/协议/快照零改动）**：3D 下把所有 2D 模态（结算/商店/Joker/比拼/重连）从"贴相机的全屏 2D 层"改为**牌桌中央的悬浮看板**；交互走**屏幕中心准星**、**相机不再锁死**（恒定捕获 + 自由环视）。**双宿主**：`board3d`（模态大板，**仅模态出现**）+ `hint3d`（**常驻小提示板**，显示 `_hint_for` 文本；下方内嵌 **Ready 按钮**（开局记忆阶段，`260×66`、字号 26、hover 变亮白边）与**条件动作按钮**（Q/J 交换·不交换、变换 Joker，`VBox/HintActions`，用 `main._decision_button` 大尺寸+明显 accent hover），Ready 与条件动作均已从 3D HUD 移除）。**注意**：提示板**默认抬高**（`BOARD_LIFT`/`HINT_RISE`）以不挡牌桌；但当"下一步是点看板按钮"时（`_hint_center_on_crosshair`：开局记忆 Ready / `Q_DECISION` 有交换按钮 / J `jack_ready`）会**贴到准星**（`base` 在相机→桌心射线上，默认准星直接命中）——修复"3D 点不到 Ready"；`Board3d._pick_box` 另外扩 `PICK_PAD`(0.18) 降低命中难度。`scripts/ui/board3d.gd`（`Board3d`）：`SubViewport` 承载现有 `Control` → 半透明 `QuadMesh`，**按内容 wrap**（视口=内容最小尺寸+内边距、quad=视口×`PIXEL_SCALE`）、**完全竖直（仅绕世界 Y 朝相机）**、自身拾取消歧、`push_input` 合成鼠标/键事件；`scripts/ui/board_input.gd`（`BoardInput`）纯坐标换算。`main.gd`：`_mount_modal`/`_unmount_modal`（关模态先卸下）、`_click_route`（`board`/`blocked`/`table`，常驻提示板不吞牌桌点击）、`_place_boards`（相机→桌心连线上放置 + `BOARD_LIFT` 抬高）、`_refresh_hint_panel`/`_board_hit`/`_update_board_hover`；F10/V 切回 2D 时把看板面板重挂回 `main`。`shop_panel`/`duel_bar` 的 `setup(...,dim)` 在 3D 去全屏黑底。参数 `BOARD_DIST=3.0`/`BOARD_LIFT=0.8`/`HINT_RISE=0.5`/`PIXEL_SCALE=0.0022`/`PICK_PAD=0.18`。测试 `verify_board3d`（52/52）；设计/计划 `docs/superpowers/specs|plans/2026-09-30-3d-hologram-board*`。
- **3D 左下角按键提示 + Tab 手册（纯客户端展示层，3D only，规则/协议/快照零改动）**：`KeyHintPanel`（`scripts/ui/key_hint_panel.gd`）在 3D 激活时于**左下角**显示两行「说明（纯白无边框）+ 按键 chip（圆角半透明底+细边框）」：`放大 Command`、`手册 Tab`（content-fit）；**右上角**另有同款 chip 回合徽标 **`回合 N/M`**（实时；字号 `ROUND_FONT_SIZE=21` = chip 两倍再缩小 1/3；左右内边距 `ROUND_H_PAD=18` 更宽，`_update_round_badge`）。chip 共用 `KeyHintPanel.make_chip`/`chip_style_box`（`make_chip(text, font_size, h_pad)` 可覆盖左右内边距）。**四角 HUD 统一**：到屏幕边缘目标 **75 屏幕像素**（`main.CORNER_MARGIN=75`，经 `_corner_margin()` 除以 canvas_items 拉伸比例换算成设计坐标，避免窗口大于 1280×760 时被放大）；三个角 = 左下按键提示 / 右上回合徽标 / 右下自身面板；**dark mode** 下这三个角落 UI 背景统一**纯白**（保留各自原透明度：chip 0.45 / 自身面板 0.22）+ 字体纯白（`KeyHintPanel.chip_bg/chip_text_color`、`PlayerStatPanel.set_corner_style`；light 与其它 UI、头顶座位面板不受影响）。Tab 开/关**手册**（`manual_panel.tscn`+`manual_panel.gd`，`_mount_modal` 走 `board3d` 全息看板弹在面前）：透明毛玻璃、三列 **牌 / 能力 / 分数**，数据来自纯函数 `ManualModel.rows()`（顺序 A,2…10,J,Q,K,Joker；分数取 `KongRules.card_value`，K=-1/Joker=0；能力 7/8 看自己、9/10 看别人、J 盲换、Q 看后决定换，其余 —）。输入：`main._input` 3D 分支监听 `KEY_TAB`（开/关）与 Esc（先关手册）；退出 3D 关闭手册并隐藏提示。测试 `verify_manual`（41/41）。
- **3D 大牌竖立 + 两堆对称 + 手牌两列居中（分支 `feature/3d-hologram-board`，纯客户端展示层，规则/协议/快照零改动）**：`Center/Pending` 大牌由平铺改为**竖立悬浮**——位置取抽牌堆/弃牌堆**中点**（两堆沿 X 关于桌心对称：`Deck`/`DeckCount` `-0.45`、`DiscardTop` `+0.45`，`KongBell` 移到 `-1.2`，中点即桌心），中心 `table3d_view.PENDING_Y=0.95`；每帧 `table3d_view.update_facing()` 把根节点重写为**绕世界 Y 朝向本机相机**（本地 +Y→水平指向相机、本地 +Z→世界上方，保持竖直、不镜像；不用含俯仰的完全 billboard），正/反面沿用快照（行动者正面、其他人背面），`CardBlock.set_upright(true)` 把点数标签从法线方向(+Y)移到牌顶(+Z)。飞牌/拾取沿用同一节点（`center_xform("pending")`）→ 换牌/弃牌飞牌**零改动兼容**（从竖立姿态起飞、落到平铺槽位）；**抽牌飞牌**也以该竖立节点为终点（从抽牌堆/弃牌堆平铺起飞、飞向竖直朝相机的大牌位）。**手牌居中**：`table3d_view._slot_local` 列坐标由 `-列×列距` 改为 `(0.5-列)×列距`，主牌两列关于座位 x 中轴居中（罚牌仍向右追列、主牌不位移）。**默认准星**仍对准桌心（两堆挪开后桌心无牌堆，抽牌需瞄左侧）。测试 `verify_table3d`（39/39）+ `verify_table3d_interaction`（76/76）；设计/计划 `docs/superpowers/specs|plans/2026-09-30-pending-upright-billboard*`。
- **3D 堆可点 + 光晕（弃牌堆按上下文 / 抽牌堆轮到自己）（分支 `feature/3d-discard-pile-action`，纯客户端展示层，规则/协议/快照零改动）**：① **弃牌/use power 改点弃牌堆**——`main._table3d_click` 的 `"discard"` 分支按上下文路由（`ActionModel.pending_discard_available` → `_on_pending_action()` 弃大牌/用能力；否则 `_on_discard_pressed()` 取弃牌顶）；**大牌本身不再可点**（`_pending_block.set_pick_enabled(false)`）。弃牌堆可点（取弃牌顶 ∨ 弃大牌）时**金色光晕** + 可拾取（`ActionModel.discard_pile_actionable`）。② **抽牌堆**在轮到自己抽牌时（`ActionModel.draw_available` = TURN_DRAW ∧ 当前）**金色光晕**（`_deck_block.set_actionable`，不改拾取）。新增纯函数在 `action_model.gd`（2D/3D 共用；`kongbaya_available` 现复用 `draw_available`）。**悬停确认**：`CardBlock._paint_glow` 优先级调为 `flash > reveal > protected > hover > actionable` —— 可点堆不悬停显金色、**悬停改显浅蓝**（确认准星对准），揭示红绿光仍最高（不冲突）。测试 `verify_actions`（30/30）、`verify_table3d_exchange`（54/54）。
- **Robot 3D 角色（已完成，纯客户端展示层）**：对局 3D 每个座位 `Avatar` 下挂 `RobotAvatar`（`scripts/ui/robot_avatar.gd`）——实例化 `assets/characters/source/Robot.blend`、剔除模型自带 Camera/Light、把 T-pose 手臂放下为待机姿势（`set_bone_global_pose_override`）、递归 `material_overlay` 仅做**出局/离线变暗**（**不再按回合染色**）；旧占位 `Body/Head` 隐藏（保留节点供 tuner/测试）。**眼部追踪**：`RobotAvatarMath.eye_look_weights`（纯函数）把朝向映射到 ARKit 眼球 blendshape，`Table3dView.update_avatars(cam, remote_looks, remote_zoom, local_zoom)` 每帧让每席机器人用其“主人”同步来的世界注视点（客户端 ~12Hz 上报 `GameState.server_look` → 服务器 `receive_look` 写入 `remote_looks`，不入快照；无则**稳定看向本机相机**，不套用本机瞄准点），含自动眨眼。**眼动采用 VRM 1.0 LookAt 语义（head-relative）**：`set_gaze_target_world(target)` 先做 **Head Tracking**（头 clamp 到 `HEAD_YAW_MAX_DEG`/`HEAD_PITCH_MAX_DEG` 跟随注视点）再做**相对头**的眼残余（`HEAD_*`/`EYE_*`；头/眼独立不叠加）；`set_eye_direction`/`set_eye_look` 为仅眼低层 API。头无需额外同步（世界统一，可由 gaze target 确定性推出）。模型脸朝 +Z、眼球中心 y≈2.038、20 骨骼（手部动画 Phase 3 预留）。**座位角度改为按 seat_id 固定**（`Table3dLayout.seat_angle()`：seat0=0°/1=270°/2=90°/3=180°，所有客户端共享同一世界坐标，修复"注视方向镜像"；`seat_angles` 仅留沙盒等按序取角度用）。另修 `Crosshair` 居中（原 `set_anchors_preset` 未设偏移→停在左上角，改 `set_anchors_and_offsets_preset(PRESET_CENTER)`）。**机体颜色每玩家随机**（进入游戏从 `KongRules.PLAYER_COLORS`(8 色) 随机取未占用色写入 `players[seat].color` 随快照下发；`RobotAvatar.set_body_color` 用逐实例 `set_surface_override_material` 上色，不改共享材质；默认 `#496AFE`）；**按住 Command/Alt 放大时眼睛变小**（`Tiny_Eyes` 形状键，且随注视同步 `GameState.remote_zoom` → `update_avatars(..., remote_zoom, local_zoom, remote_talk, local_talk)`）；**按 M 说话**（`set_talking` 驱动下巴 `jawOpen`，`RobotAvatarMath.talk_jaw` 多正弦开合 + 慢包络；状态随 `remote_talk` 同步）；3D 场景新增 `KeyLight`(DirectionalLight3D)+环境 `Sky` 反射（原场景无灯光→发平）。详见 `docs/3D角色与场景说明.md` §2.1/§4.2/§4.5/§4.6/§4.7/§4.8；协议见 `网络协议_V1.md` §4.8；测试 `verify_robot_avatar`（62/62）。
- **卡牌贴图分辨率坑（防复发）**：图集 1× 源图 `opersze-cards-full.png` 每卡仅 **55×77 像素**，在游戏里是**放大**显示（手牌 ≈1.16×、大牌 2×，HiDPI/窗口缩放再 ×2）→ 糊；旧素材 352×512 是缩小显示故清晰。**运行时必须用 4× 高清版**（每卡 220×308，显示尺寸小于格子 → 缩小采样、清晰）。`TextureRect` 一直是 `KEEP_ASPECT_CENTERED`（等比、无变形），故糊的原因是像素不足而非拉伸变形。
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
| `game_interaction.gd` | 交互状态机（action_mode/selected）；J 盲换 = 选对方牌→选自己牌→`jack_ready` 确认（`jack_swap_now`/`jack_cancel`），**不再选齐即自动交换** |
| `lobby_view.gd` | 大厅构建/建房/加入/双开 |
| `game_view.gd` | 对局构建 + 状态投影渲染（前 4 张固定 2 列网格 + 第 5+ 张 `ExtraLayer` 按槽号固定定位） |
| `reveal_controller.gd` | 看牌/贴牌翻转动画（`_play_flip_at`/`_play_slap_flip`，贴牌绿/红炫光 + 正确 hold `_held_slap`） |
| `card_animator.gd` | 卡牌移动/交换/落位动画 + 贴牌事件（slap_penalty/resolved/gift）处理（副本 + 隐藏源卡 + 占位） |
| `dev_tools.gd` | F12 布局调试 / T 主题切换 / O 调试贴牌开关 |
| `duel_bar.gd` | 比拼 bar（全屏遮罩+居中弹窗；随机加粗区+中心红心+扫动标记+STOP；空格停止由 main 转发） |
| `coin_icon.gd` / `life_icon.gd` / `stat_hud.gd` | 每玩家区域手牌右侧金钱/生命 HUD（程序化铜钱/心形图标 + 数字，纯展示读快照公开字段 `players[].currency`/`health`） |
| `settlement_model.gd` | 结算纯计算（同步轮记分：`layout_order`/`rounds`/`ranking`，headless 可测） |
| `settlement_page.gd` + `scenes/ui/settlement_page.tscn` | 结算弹层（居中排名窗口场景实体；逐张翻牌/实时重排/冠军特效；回调解耦 main） |
| `card_view.gd` / `card_factory.gd` | 卡牌视图节点 / 构建 |
| `card_atlas.gd` | TypeCards 4× 图集查表（`CardAtlas`：卡牌皮肤；默认 `original` 走旧素材，其余 type 走图集） |
| `dashed_border.gd` | 虚线边框占位（当前对局空槽已改透明占位，不用虚线） |
| `scenes/ui/game_board.tscn` | 对局棋盘静态骨架（锚点+容器，布局可在编辑器拖拽）：TitleBar/HintArea/4×PlayerArea/MiddleRow·PileArea/Corner |
| `scenes/ui/player_area.tscn` + `scripts/ui/player_area.gd` | 玩家区域模板，`@export var card_size`（默认 62×90），名字在卡牌正下方；GameBoard 直接子节点，运行时复用填充 |
| `action_model.gd` | **纯函数**：2D/3D 共用动作与可用性判定（`conditional_actions(state, ctx)` 含 Q/J 确认按钮（J 需 ctx 记的两张已选）/ `kongbaya_available` / `ready_text` / `ready_enabled` / `discard_take_available` / `pending_discard_available` / `discard_pile_actionable`） |
| `table3d_layout.gd` | **纯函数**：3D 布局数学（座位角度/槽位网格/分类色/拾取层与盒高/高亮色；`seat_angle()` 按 seat_id 固定；`TABLE_HEIGHT=1.0` 桌面腰高） |
| `table3d_view.gd` | 3D 视图：`_bind()` 按固定路径解析场景骨架；按快照填每槽 `CardBlock`、头顶状态面板、铃铛发光、角色可见性与状态 overlay；`pick_center`/`update_hover`/`reveal_slot`/`flash_slot`；换牌/抽牌飞牌编排与堆光晕（见下） |
| `robot_avatar.gd` | Robot 角色包装（每席 `Avatar` 下）：实例化 `assets/characters/source/Robot.blend`、剔除自带 Camera/Light、待机放下手臂（T-pose→idle，`set_bone_global_pose_override`）、递归 `set_overlay` 染色、`set_eye_look`/`reset_eyes` 眼动 + 自动眨眼；常量 `SCALE`/`MODEL_EYE`/`MODEL_HEAD_TOP`/`ARM_DOWN_DEG`/`EYE_*` |
| `robot_avatar_math.gd` | **纯函数**：眼球朝向（本地 +X 左/+Y 上/+Z 前）→ ARKit 眼球 blendshape 权重（`eye_look_weights`/`blink_weights`），headless 可测 |
| `card_block.gd` | 3D 单卡方块：`PlaneMesh(FACE_Y)` 面 + 卡背/真实牌面贴图 + **边缘发光**（多层外扩平面；优先级 `flash > reveal > protected > hover > actionable`）+ **真实 3D 揭示翻转**（揭示（看牌/贴牌）双面几何、抬起+倾斜，不镜像；`setup`/`reveal`/`restore` 走 `_reveal_p`，`FLIP_DURATION`）+ 拾取 `Area3D` + `set_pick/set_pick_enabled/set_actionable/set_hover/reveal/restore/flash` |
| `table3d_camera.gd` | 3D 相机 rig：`frame_for_seat`（含 `aim_pitch_deg` 对准桌心）+ `look`（yaw/pitch 夹取）；`PitchPivot/Camera3D` 由场景提供 |
| `table3d_picker.gd` | 屏幕中心射线拾取（`pick_hit` 返回 `{pick, collider}` / `pick` 只取 meta） |
| `table3d_hud.gd` | 3D 操作面板按钮组（通用；当前条件动作/Ready 已移到常驻提示板 `hint3d` 下方，HUD 传空；Kongbaya 由 3D 铃铛负责） |
| `crosshair.gd` | 屏幕中心准星（悬停可点目标时变金放大） |
| `player_stat_panel.gd` / `card_count_icon.gd` | 玩家状态面板（名字在框上方、放大 2×；框内透明白灰底+黑边框，**框宽自适应内容**，生命/金钱/卡牌数）+ 程序化卡牌图标；`set_corner_style(true)` 用于 3D 右下角自身面板（dark 下 #FEF0E4 底 + 白字） |
| `scenes/ui/table3d.tscn` | 3D 对局静态骨架（环境/相机/方桌+边框/4 座位+角色/中央牌堆+金铃铛/Hud）；**归开发者所有**，节点名路径是契约 |
| `card_animation_config.gd` / `card_animation_math.gd` / `card_animation.gd` / `card_animation_sandbox.gd` | 卡牌交互动效沙盒：参数集中配置 + 纯函数（状态机/缓动/高度/阴影/compose）+ 控制器（标量进度驱动）+ 沙盒（5 卡/准星/左键翻牌） |
| `card_block.gd`（hover pose）/ `table3d_view.gd`（_hover_slot） | 3D 桌面 hover 抬起/倾斜：仅 viewer 自己手牌；`_visual` 视觉 pivot 保证拾取盒不随动画移动；`_hover_slot` 跨 `render()` 重建即时重放 |
| `card_fly_config.gd` | 3D 换牌飞牌参数（`speed`/`duration_min`/`arc_height`/翻面窗口）+ 校验 |
| `card_fly_math.gd` | **纯函数**：3D 换牌飞牌时长（恒定速度）/缓动/弧线/翻面/变换合成 |
| `card_fly.gd` | 3D 单张飞牌控制器（标量 `p` + 每帧 compose 写 transform + `finished`） |
| `card_fly_sandbox.gd` + `scenes/ui/card_fly_sandbox.tscn` | 3D 换牌动画沙盒（复刻对局布局 + 6 kind 按钮；接入前的手感原型） |
| `table3d_view.gd`（换牌/抽牌飞牌段 + 堆光晕） | 对局 3D 飞牌编排：`animate_exchange(data)` + `slot_xform`/`center_xform`/`slot_face_up`/`slot_card` + `_anim_slots`/`_discard_hold`/`_flyers` 跨 render 管理（`main.gd` 3D 分支调用）；**抽牌飞牌** `_detect_draw`/`_anim_draw`（快照 pending 空→非空，所有人可见）；抽牌堆/弃牌堆可点**金色光晕**（`ActionModel.draw_available`/`discard_pile_actionable`） |
| `board_input.gd` | 3D 全息看板坐标纯函数（`local↔uv↔viewport`） |
| `board3d.gd` | 3D 全息看板宿主：`SubViewport`→半透明 billboard quad（按内容 wrap / 竖直仅绕 Y 朝相机 / 自身拾取消歧 / `push_input` 合成鼠标·键事件）；`main` 建 `board3d`（模态）+ `hint3d`（常驻提示+Ready）两实例 |
| `key_hint_panel.gd` | 3D 左下角按键提示（说明纯白无边框 + 按键 chip 圆角半透明灰底+边框黑字，content-fit）：`放大 【Command】`/`手册 【Tab】` |
| `manual_model.gd` | **纯函数**：手册数据 `rows()`（牌序 A..K/Joker + 能力文案 + `KongRules.card_value` 分数），headless 可测 |
| `manual_panel.gd` + `scenes/ui/manual_panel.tscn` | Tab 手册（3D 全息看板弹在面前）：透明毛玻璃 + 三列 牌/能力/分数 |

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
| 9 | BET | 已弃用（R-12 取消押注阶段，任何流程不再进入，仅保留枚举值以保证 `Phase.SHOP`=10 稳定） |
| 10 | SHOP | 系列赛非把末结算后进入商店：存活玩家限购 1 件固定价遗物（`shop_buy`）或跳过（`shop_skip`），全员完成后开下一局；把末不进商店 |

## 6. 网络与隐私契约（详见 `网络协议_V1.md`）

- 房主 `Network.host_game`（ENet peer ID = 1）；客户端 `Network.join_game` + 注册昵称。
- 命令进入 server `server_*` RPC → 私有 `_server_*` 验证。
- 状态消息：`receive_lobby`/`receive_state`/`receive_reveal`/`receive_toast`/`receive_peek_highlight`，牌面仅允许在弃牌顶、行动者的待处理抽牌、结算牌中出现。
- 请求方向：`slap`（`TURN_DRAW` 且 `slap_open`）、`slap_exchange`（`SLAP_EXCHANGE`）、`slap_duel_stop`（`SLAP_DUEL`，仅候选人）。快照 `slap_duel` 仅在 `SLAP_DUEL` 存在（`contestants`/`duration_ms`/`deadline_server_ms`/`target`，均公开）。
- 查看高亮 `peek_highlight`：仅含 `{player_id, slot}` 位置、**不含牌面**（详见 `网络协议_V1.md` 4.6）。非当前玩家看到的大牌为**背面**（`pending.hidden=true`，Feature0）。
- 交换动画：server 广播 `card_exchange_animated` 事件（kind: `replace`/`swap`/`discard`/`slap_penalty`/`slap_resolved`/`slap_gift`），各 client 用**自己视角的 `_card_slots`** 定位播放。`slap_gift`/`slap_penalty` **不含牌面**（防泄漏）；`slap_resolved` 含 card（被贴的牌已通过贴牌 reveal 公开）。
- 贴牌 reveal target 携带 `correct: Boolean`（客户端据此打绿/红炫光）。
- 注视点 `look`（纯表现层，**不入快照**）：客户端 3D 下按 ~12Hz `server_look(target, zoom)` → 服务器校验发送者后 `receive_look(seat, target, zoom)` 转发给其他客户端，写 `GameState.remote_looks`（世界注视点）；用于每席机器人眼睛跟随其"主人"自己的鼠标/相机（详见 `网络协议_V1.md` §4.8）。

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
- **B28-B32（3D 视图相关，本次会话新增）**：3D 环视在捕获态收不到 `_unhandled_input` 的 motion + 重复取景复位视角（改走 `main._input` + 同座位不复位，B28）；`BoxMesh` 十字 UV 裁掉卡背（卡面改 `PlaneMesh(FACE_Y)`，B29）；隐藏的 pending 卡 `Area3D` 仍参与射线命中（`visible=false` 不关碰撞 → `CardBlock.set_pick_enabled`，B30）；默认取景俯角指向桌外致「点不到任何东西」（默认对准桌心，B31）；悬停对象被 render 释放后传带类型 `Object` 形参报错并中断 `clear_hover`（形参去类型 + `is_instance_valid`，B32）。详见 `BUG档案.md`。
- **B33（3D 座位/手牌镜像，本次会话新增）**：3D 座位左右/前后与 2D 相反（`seat_angles` 均分递增 → 改按 2D 箱位 `[0,270,90,180]`；`slot_grid_pos` 改按列向右、每列先上后下 + `_render_seat` 取本地 `-列`/`(1-行)`）。详见 `BUG档案.md`。
- **B34（hover 边缘抖动，本次会话新增）**：hover 动画移动卡牌使挂在卡上的拾取盒跟随移动 → 边缘"命中→抬起→打不中→落下"来回抖。修复：**拾取盒固定在基准位不随动画移动**（沙盒用 `CardAnimation` 根上的静态 `PickArea`；3D 用 `CardBlock._visual` 视觉 pivot，`Area3D` 留根）。详见 `BUG档案.md`。
- **B35（翻牌途中离开卡在 hover 态，本次会话新增）**：揭示/翻牌途中移开准星时 `exit_hover()` 提前 return，`hover_p` 停在 1 → 卡永久抬起、再进入才重置。修复：`_on_land_done` 按 `hovering` 回正 `hover_p`。详见 `BUG档案.md`。
- **B36（揭示翻快了一倍，本次会话新增）**：旧揭示 = 两段各 `FLIP_DURATION(0.25)`（共 0.5s）；改 3D 翻转后用单段 `FLIP_DURATION` → 只有 0.25s 显得快。修复：`FLIP_DURATION := 0.5`（整段时长），并同步测试等待时长。详见 `BUG档案.md`。
- **B37（3D 揭示翻完又显示一次正面 + 重新打炫光，本次会话新增）**：`render()` 重放 `_reveals` 时 `CardBlock.reveal()` 每次从 0 重播翻转（非保持正面）；换牌飞牌接入的落地 `_refresh()` 在揭示窗口内触发 render，使这次重播可见（"翻完又翻 + red 光晕"）。修复：`reveal(card,color,from_p:=0)` 支持续播/直接呈现（`_reveal_from`）+ `table3d_view.reveal_slot` 记 `start_ms`、`_apply_reveal` 按已过时间算进度。详见 `BUG档案.md`。
- **B38（发光优先级：揭示炫光 > hover > actionable，设计缺陷，本次会话新增）**：原 `_paint_glow()` 缺"揭示色"档且 hover 低于 actionable——① 贴牌揭示绿/红被 hover/重绘覆盖；② 抽牌/弃牌堆金色"可点"高亮盖住准星悬停浅蓝、无法确认选中。修复：揭示色提为 `_reveal_color` 一等状态，优先级定为 **`flash > reveal > protected > hover > actionable`**（`setup`/`restore` 清空 `_reveal_color`）；揭示炫光最高、hover 用于确认选中、不悬停时才显可点金色。详见 `BUG档案.md`。
- **B39（常驻提示板吞掉牌桌点击，本次会话新增）**：3D 全息看板引入常驻提示板 `hint3d` 后，`hint3d.visible` 恒真，`_table3d_click` 里 `if _board_has_panel() or hint3d.visible:` 恒成立且未命中板时也 `return` → 卡牌完全点不了。修复：引入显式点击路由 `_click_route(board_hit)` → `board`/`blocked`/`table`。详见 `BUG档案.md`。
- **B40（退出 3D 时对已释放模态面板崩溃，本次会话新增）**：模态（如 Joker）在 3D 中被状态变化 `queue_free` 后仍留在 `Board3d._panels`，退出 3D 时 `detach_all()` 把已释放对象传给类型化参数 `unmount_panel(control: Control)` → "argument 1 (previously freed)" 报错。修复：`Board3d._prune_panels()` 清理失效条目 + `main._unmount_modal()` 关模态前先卸下。详见 `BUG档案.md`。
- **B41（3D 行动提示/高亮不随本地交互更新）**：`interaction.action_mode` 为本地状态（用能力/J 两段交换只调 `_render_game()`），而 3D 渲染+提示板只在 `_on_state_updated` 刷新 → 3D 提示/高亮停留旧态，切 2D→3D 才更新。修复：`main._refresh_table3d()` 在 `_render_game()` 末尾统一刷新 3D（`_on_state_updated` 去重）。详见 `BUG档案.md`。
- **B43（3D peek 蓝光看不到）**：其他玩家看不到当前玩家 peek 的蓝色光晕——3D `Table3dView.flash_slot` 只临时染色、不登记，紧随的 `_broadcast_state` 重建卡牌即冲掉。修复：增 `_flashes`（`"seat_slot" -> {color, until_ms}`）登记，`render` 重建后按剩余时间重放（同 `_reveals` 模式），过期清除。详见 `BUG档案.md`。
- **B42（Q 看牌不保持正面 + 释放动画/交换飞牌衔接）**：Q 的两张揭示 **hold** 到玩家确认交换/不交换：2D `RevealController._held_peek`/`release_held_peeks`，3D `Table3dView.reveal_slot_held`/`release_held_reveals`；`main` 用本地标志 `_hold_next_reveal`（`game_interaction` 在 `queen_target`/`q_view_own` 置位）。**不交换**：`release_held_peeks(true)` 播翻回动画（2D overlay / 3D `releasing` 跨 render 续播 `CardBlock.reveal_from_to`）后才清理，不再瞬切。**交换**：`q_exchange` 不预释放，保留正面由交换飞牌 `consume_held`/`take_held_reveal` 取牌面 → 从正面起飞、背面落地。纯展示层。详见 `BUG档案.md`。

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
# 名次奖励经济（29/29：首名+40/中间+10/垫底0且−1命/并列平分/全员同分不扣血/2命垫底两次出局/超限与首回合Kong按垫底/result.rewards）
... --headless --path . res://tests/verify_economy.tscn
# 商店固定价购买（遗物定义/流程进店/购买扣款入库/售出先到先得/钱不够拒绝/限购1件/全员完成后下一局）
... --headless --path . res://tests/verify_shop.tscn
# 遗物效果 v1（19/19：护盾局开始生效并消耗/贴牌与J·Q交换免疫(PROTECTED)/快照护盾标记/无遗物no-op/Joker变换/未变换+2/已变换清除加成）
... --headless --path . res://tests/verify_relics.tscn
# 卡牌皮肤（35/35：4× 图集 region 映射/默认 original 走旧素材/类型切换重绘/显式 type 覆盖）
... --headless --path . res://tests/verify_card_skin.tscn
# 3D 布局纯函数（19/19：座位角度/槽位网格/分类色/拾取层）
... --headless --path . res://tests/verify_table3d_layout.tscn
# 3D 渲染（39/39：CardBlock 贴图/护盾/相机取景/HUD/面板 data/空槽不渲染/场景契约/大牌桌心正上方/两堆对称/手牌两列居中）
... --headless --path . res://tests/verify_table3d.tscn
# 3D 环视与相机（10/10：事件可达/相机为当前/取景/朝向/按住 Command·Alt 放大 FOV/松开恢复/reset）
... --headless --path . res://tests/verify_table3d_mouse.tscn
# Robot 角色（62/62：眼动权重/头部 follow/VRM LookAt head-relative/说话 jawOpen/随机配色/逐实例材质/共享世界/远程同步）
... --headless --path . res://tests/verify_robot_avatar.tscn
# 3D 交互（76/76：拾取/高亮/揭示真实 3D 翻转/翻牌跨render保持/双面几何/own 槽 hover 抬起且拾取盒不动/HUD/铃铛/悬停/回合标识/默认准星指向牌堆/大牌竖立朝向）
... --headless --path . res://tests/verify_table3d_interaction.tscn
# 3D 全息看板（52/52：坐标换算 / 挂载+wrap / 竖直朝向 / 输入合成 / 拾取消歧 / 双宿主+Ready（加大+hover）/ Q 按钮在提示板下方（更大+有 hover）/ main 路由）
... --headless --path . res://tests/verify_board3d.tscn
# 手册 + 左下角按键提示（41/41：牌序/分数/能力、chip 样式、3D 提示两行、Tab 开/关手册、退出清理）
... --headless --path . res://tests/verify_manual.tscn
# 动作模型（35/35：Q/J 确认按钮（J 未选齐禁用）、Joker 条件、铃铛/抽牌可用、Ready 文案与可用、弃牌堆取/弃可用性）
... --headless --path . res://tests/verify_actions.tscn
# J 盲换确认流程（11/11：用能力出现交换/不交换、未选齐禁用、选两张后可交换、不自动交换、hint）
... --headless --path . res://tests/verify_j_swap.tscn
# 玩家状态面板（7/7：data/名字显隐/黑边框/透明白灰底/名字在框外/字号放大）
... --headless --path . res://tests/verify_stat_panel.tscn
# hint 生成测试（8/8）
... --headless --path . res://tests/verify_hint.tscn
# 卡牌交互动效沙盒（68/68：配置/状态机/缓动/高度/阴影/compose/控制器/沙盒；feature/hover-curve 上含弯曲为 73/73）
... --headless --path . res://tests/verify_card_animation.tscn
# 3D 换牌动画沙盒（40/40：配置/纯数学/控制器/沙盒；复刻布局 + 6 种 kind 演示）
... --headless --path . res://tests/verify_card_fly.tscn
# 3D 换牌动画接入对局（66/66：跨 render 标记/6 kind 落地恢复/隐私/未渲染槽/揭示重放不重播/炫光优先级/抽牌飞牌/弃牌堆可点/抽牌堆光晕/Q hold 释放翻回动画/peek 蓝光跨 render 保持）
... --headless --path . res://tests/verify_table3d_exchange.tscn
# Q 看牌 hold（12/12：2D hold 登记/交换 consume 返回牌面与撤标记/不交换翻回动画后清理）
... --headless --path . res://tests/verify_q_hold.tscn
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

> **开发约定**：按用户的指示**不启动 GUI**，用上述 unit test 验证后总结。每次改动后跑 `verify_protocol` + `verify_swap` + `verify_duel` + `verify_reconnect` + `verify_kongbaya` + `verify_economy` + `verify_shop` + `verify_relics` + `verify_card_skin` + **3D/UI：`verify_table3d_layout` + `verify_table3d` + `verify_table3d_mouse` + `verify_table3d_interaction` + `verify_actions` + `verify_stat_panel` + `verify_card_animation` + `verify_card_fly` + `verify_table3d_exchange` + `verify_q_hold` + `verify_j_swap` + `verify_board3d` + `verify_manual` + `verify_robot_avatar`** + 双实例 `verify_net`。3D hover 由 `verify_table3d_interaction` 覆盖。揭示翻转由 `verify_table3d_interaction` 覆盖。3D 换牌飞牌（沙盒 + 接入）由 `verify_card_fly` + `verify_table3d_exchange` 覆盖。3D 全息看板由 `verify_board3d` 覆盖。

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
