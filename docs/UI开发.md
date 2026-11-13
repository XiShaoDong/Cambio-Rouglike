# KONG UI 开发指南（表现层专用）

> **本文档职责**：给只做 UI / 表现层的 Agent 使用。读完本文即可开始改 UI，**不需要理解规则、状态机、服务器与网络实现**。
>
> **权威顺序**：规则看 `KONG_开发文档.md`，协议看 `网络协议_V1.md`，测试看 `验收与测试计划.md`；本文只描述 UI 侧的文件、职责与边界。若本文与上述权威冲突，以权威文档为准。

---

## 0. 一分钟上手

- **UI = 全部表现层**：2D 对局界面、3D 牌桌与运镜、四角 HUD、倒计时、hint、结算页、商店页、大厅/房间、设置、手册、教学、卡牌动画/飞牌/标记/表情，都属于 UI。
- **组合根**：`scripts/ui/main.gd`。所有 UI 挂载、信号转发、2D/3D 切换、输入分发都在这里；改 UI 通常先从这里找入口。
- **唯一数据来源**：`GameState.state_updated` 推送的 `latest_state` 快照、`GameState.lobby_updated` 推送的 `latest_lobby`，以及若干表现层信号。
- **唯一写操作**：调用 `GameState.request_*()` 表达玩家意图；服务器校验后才生效。UI 不直接改牌、不改阶段、不改经济。
- **默认视图是 3D**：进入对局首次自动切到 3D（`main._view_defaulted_3d`），`V` / `F10` 切回 2D。
- **不要启动 GUI 验证**：项目约定用 headless 单测（见第 7 节）。

---

## 1. 铁律：UI 边界

### 1.1 可以改

- `scripts/ui/**`：所有 UI 脚本。
- `scenes/ui/**`、`scenes/tutorial/**`：UI 场景。
- `assets/ui/**`、`assets/shaders/**`、`assets/Cards/**`、`assets/TypeCards/**`、`assets/3Dmodels/**`、`assets/characters/**`：纯展示资源。
- `scripts/tutorial/**`：教学流程与文案。
- `scripts/core/settlement_model.gd`：结算纯计算（UI 域，但放在 core）。
- `scripts/core/keybind_model.gd`、`scripts/core/keybind_store.gd`：按键映射（UI 设置域）。
- `scripts/core/settings.gd`、`scripts/core/loc.gd`：设置项与本地化（只改 UI 相关键值）。
- `scripts/ui/ui_theme.gd`：主题令牌。

### 1.2 不要改（规则 / 服务器 / 协议）

- `scripts/core/game_state.gd`、`hidden_info.gd`、`game_rules.gd`、`score_system.gd`、`turn_system.gd`、`effect_system.gd`、`peek_system.gd`、`swap_system.gd`、`slap_system.gd`、`kongbaya_system.gd`、`run_modifier.gd`、`series_ranking.gd`。
- `scripts/net/**`、`server/**`、`scenes/server.tscn`。
- `scripts/core/item_cards.gd`、`relics.gd`：这是玩法内容定义（名称/描述/价格/效果），UI 只读，不为了视觉去改。
- 测试用例不要为了“让 UI 过”而放宽断言。

### 1.3 三条硬约束

1. **不复制规则**：UI 不判断“这张牌能不能贴/能不能换/该不该赢”。需要展示可用性时，只用 `scripts/ui/action_model.gd` 这类“从快照推导展示态”的纯函数；真正的合法性仍由服务器判定。
2. **不推导隐藏信息**：快照里没有的牌面，UI 不得通过牌堆、`card_id`、历史事件等侧信道推算或展示。未知牌只能显示背面。
3. **需要新数据时先提协议**：如果 UI 需要快照里没有的字段，先改 `网络协议_V1.md` 并在服务器侧投影；不要在客户端临时计算隐藏信息。

### 1.4 允许的表现层 RPC（例外）

以下 RPC 只用于表现层同步，**不进入快照**，改动前必须同步 `网络协议_V1.md`：

- 注视/放大/说话/抬手：`server_look` → `receive_look` → `GameState.remote_looks`。
- 桌面标记：`server_mark` → `receive_mark` → `GameState.mark_placed`。
- 表情：`server_emote` → `receive_emote` → `GameState.emote_played`。

---

## 2. 唯一入口：`scripts/ui/main.gd`

`main.gd` 是组合根，不要求通读全部，但必须知道这些入口：

| 入口 | 作用 |
| --- | --- |
| `_on_state_updated(state)` | 收到对局快照：刷新 `latest_state`、交互态、2D/3D、结算/商店/效果面板、发牌动画、首局提示。**UI 的主刷新循环。** |
| `_render_game()` | 2D 全量渲染（`game_view.render` + 结算比拼 + 罚牌补飞 + 3D 刷新）。 |
| `_refresh_table3d()` | 3D 激活时把快照与本地交互态投影到 3D：卡牌、HUD、自身面板、回合徽标、提示板。 |
| `_set_table3d(on)` | 2D ↔ 3D 切换、鼠标捕获、看板重挂、相机取景。 |
| `_mount_modal(control)` / `_unmount_modal(control)` | 模态面板挂载：2D 挂 `main`，3D 自动挂到全息看板 `board3d`。 |
| `_click_route(board_hit)` / `_table3d_click()` | 3D 点击路由：看板 → 模态拦截 → 牌桌。 |
| `_input` / `_unhandled_input` | 3D 环视、键盘快捷键、设置开关、轮盘、飞行相机等。 |
| `_ensure_*` | 懒创建 HUD：`HintHud`、`KeyHintPanel`、回合徽标、自身面板、卡牌 tooltip、牌序面板、效果面板、`board3d`/`hint3d`。 |
| `_update_hint_hud(...)` | 把阶段/当前玩家/贴牌窗口喂给 `HintHud`。 |
| `_update_self_panel()` / `_update_round_badge()` | 右下角自身面板与右上角回合徽标。 |
| `_update_card_tooltip()` / `_update_relic_tooltip()` | 3D 准星悬停信息框。 |
| `_hint_for(...)` | 2D/3D 通用提示文案入口，内部委托 `HintText.hint()`。 |
| `_corner_margin()` | 四角 HUD 到屏幕边缘的统一 75 屏幕像素边距。 |

信号连接集中在 `main.gd` 约 1555 行；新增表现层信号时在附近接线。

---

## 3. 文件地图

### 3.1 对局界面（2D 棋盘 + 屏幕空间 HUD）

| 文件 | 职责 |
| --- | --- |
| `scripts/ui/game_view.gd` | 2D 对局视图：构建棋盘、把快照投影成 4 个玩家区、中央牌堆、大牌、Ready/操作按钮、停滞面板；`render(state)` 是入口。 |
| `scenes/ui/game_board.tscn` | 2D 棋盘静态骨架（TitleBar / HintArea / 4×PlayerArea / MiddleRow / PileArea / Corner），布局可在编辑器拖拽。 |
| `scripts/ui/player_area.gd` + `scenes/ui/player_area.tscn` | 单个玩家区域模板：手牌网格、名字、金钱/生命/遗物挂点；`@export card_size`。 |
| `scripts/ui/game_interaction.gd` | 2D 点击交互状态机：选牌、J 两段交换、Q 决策、目标选择；只产生 UI 状态与 `request_*`。 |
| `scripts/ui/action_model.gd` | 纯函数：从快照 + 本地交互态推导条件按钮与可用性（Q/J、Joker 变换、铃铛、抽牌、弃牌堆、Ready）。2D/3D 共用。 |
| `scripts/ui/hint_hud.gd` | **3D 屏幕空间顶部 HUD**：倒计时胶囊 + hint 文本 + SLAP 状态行/进度条；只动 `position.y`/`modulate`。 |
| `scripts/ui/hint_text.gd` | 所有 action hint 文案集中处；新增/修改文案只改这里。 |
| `scripts/ui/turn_timer.gd` | 回合倒计时纯模型（`reset/tick/seconds_left/phase`），不联网、不写快照。 |
| `scripts/ui/key_hint_panel.gd` | 3D 左下角按键提示（说明 + 圆角 chip）；提供 `make_chip`/`chip_style_box` 给其他角落复用。 |
| `scripts/ui/card_order_panel.gd` | 3D 左下角「牌序」面板（牌序 + Shift 提示）。 |
| `scripts/ui/crosshair.gd` | 3D 屏幕中心准星；悬停可点目标时变金放大。 |
| `scripts/ui/player_stat_panel.gd` | 玩家状态面板（名字、生命、金钱、卡牌数）；3D 右下角自身面板用 `set_corner_style(true)`。 |
| `scripts/ui/stat_hud.gd` | 每玩家区域金钱/生命 HUD 容器。 |
| `scripts/ui/coin_icon.gd` / `life_icon.gd` / `card_count_icon.gd` | 程序化铜钱 / 心形 / 卡牌数图标，无图片依赖。 |
| `scripts/ui/relic_bar.gd` / `relic_icon.gd` / `relic_basket.gd` | 遗物栏（2D 3 格） / 遗物图标字符 / 3D 饰品篮。 |
| `scripts/ui/card_view.gd` | 2D 卡牌视图：正/背面、点击、高亮、翻牌、发牌动画、炸弹角标、伪 3D 倾斜入口。 |
| `scripts/ui/card_factory.gd` | 2D 卡牌构建工厂。 |
| `scripts/ui/card_atlas.gd` | TypeCards 图集查表（`original`/`normal`/`stone`/`paper`/`glass`），带 `AtlasTexture` 缓存。 |
| `scripts/ui/card_tooltip.gd` | 3D 准星悬停信息框（能力框 + 第二框操作提示）。 |
| `scripts/ui/card_ability_text.gd` | 卡牌能力文案纯函数。 |
| `scripts/ui/dashed_border.gd` | 虚线边框占位（当前空槽主要用透明占位）。 |
| `scripts/ui/card_tilt_math.gd` / `card_tilt_view.gd` / `card_tilt_preset.gd` | 2D 伪 3D 大牌倾斜：纯数学 + 视图 + 调参存档（`assets/config/card_tilt_preset.cfg`）。 |
| `scripts/ui/reveal_controller.gd` | 2D 看牌/贴牌翻转动画、绿/红炫光、正确贴牌 hold、Q 看牌 hold/释放。 |
| `scripts/ui/card_animator.gd` | 2D 卡牌移动/交换/落位/贴牌事件动画（副本 + 隐藏源卡 + 占位）。 |
| `scripts/ui/settlement_page.gd` + `scenes/ui/settlement_page.tscn` | 结算弹层：排名行、同步轮算分、逐张翻牌、实时重排、冠军特效；`setup(model, callbacks)`。 |
| `scripts/core/settlement_model.gd` | 结算纯计算（`layout_order`/`rounds`/`ranking`），headless 可测；UI 只读。 |
| `scripts/ui/shop_panel.gd` + `scenes/ui/shop_panel.tscn` | 商店面板：本人 3 张道具卡 + 2 件遗物；购买/刷新/锁定/结束商店，数据来自 viewer 自己的 `shop` 快照。 |
| `scripts/ui/duel_bar.gd` | 贴牌比拼 bar 弹窗（全屏遮罩 + 扫动 + STOP）。 |
| `scripts/ui/joker_transform_panel.gd` + `scenes/ui/joker_transform_panel.tscn` | Joker 变换选牌面板。 |
| `scripts/ui/turn_effect.gd` / `turn_effect_panel.gd` | 本局随机增强展示（数据 + 中央放大 5s 后缩到右上角）。 |
| `scripts/ui/bomb_icon.gd` | 程序化炸弹图标，2D/3D 共用贴图。 |
| `scripts/ui/slap_success_burst.gd` | 贴牌成功/炸弹爆炸/6 触发 的齿状爆炸弹层。 |
| `scripts/ui/item_hand_overlay.gd` | 屏幕空间道具手牌：底部手部 + 扇形卡 + 说明 + 目标 HUD + A/D 提示 chip。 |
| `scripts/ui/item_hand_model.gd` / `item_hand_math.gd` | 道具手牌模型与扇形/切换纯数学。 |
| `scripts/ui/item_card_view.gd` | 道具卡卡面视图。 |
| `scripts/ui/item_hand_art.gd` / `hand_silhouette_2d.gd` / `item_arm_hand_3d.gd` | 手部美术基类 / 2D 圆手 / 3D 透明手臂（可替换）。 |
| `scripts/ui/avatar_hand.gd` | 机器人右手粗模（挂在 `RobotAvatar` 的 `hand.R` 上）。 |

### 3.2 3D 桌面与角色

| 文件 | 职责 |
| --- | --- |
| `scenes/ui/table3d.tscn` | 3D 静态骨架（环境/相机 rig/牌桌/4 座位/角色/中央牌堆/铃铛/HUD）。**归开发者所有**，节点名/路径是契约；Agent 改结构前先重读并 `git diff`。 |
| `scripts/ui/table3d_view.gd` | 3D 渲染器：`_bind()` 按固定路径解析场景；按快照填每槽 `CardBlock`、状态面板、铃铛、角色可见性；拾取/高亮/揭示/发牌/飞牌编排；`render(state, ...)` 是入口。 |
| `scripts/ui/table3d_layout.gd` | 3D 布局纯数学：座位角度、槽位网格、分类色、拾取层与盒高、高亮色。 |
| `scripts/ui/table3d_camera.gd` | 相机 rig：`frame_for_seat`、`aim_pitch_deg`、鼠标环视、Command/Alt 放大、道具目标锁定。 |
| `scripts/ui/table3d_picker.gd` | 屏幕中心射线拾取（返回命中 `pick` meta / 落点）。 |
| `scripts/ui/table3d_hud.gd` | 3D 操作按钮组（通用；当前条件动作/Ready 已移到常驻提示板下方）。 |
| `scripts/ui/card_block.gd` | 3D 单卡方块：双面几何、真实牌面/卡背、边缘炫光、hover 虚线边框、揭示翻转、拾取 `Area3D`、炸弹角标、侧壁。 |
| `scripts/ui/card_fly_config.gd` / `card_fly_math.gd` / `card_fly.gd` | 3D 飞牌：参数 / 纯数学（恒定速度、弧线、翻面、变换合成）/ 单张控制器。 |
| `scripts/ui/card_animation_config.gd` / `card_animation_math.gd` / `card_animation.gd` | 3D 桌面 hover/按压/翻牌/落位动效：参数 / 纯函数 / 控制器（标量进度 + compose）。 |
| `scripts/ui/deck_pile.gd` | 抽牌堆/弃牌堆视觉叠层（顶牌仍由 `CardBlock` 充当）。 |
| `scripts/ui/poker_table_model.gd` | 扑克桌模型包装。 |
| `scripts/ui/bell_model.gd` | Kong 铃铛模型 + 金属着色器 + 可用性金光。 |
| `scripts/ui/robot_avatar.gd` | 每席 Robot：模型实例化、待机手臂、机体配色、出局/离线变暗、眼动/头动/说话/抬手、冠军皇冠挂点。 |
| `scripts/ui/robot_avatar_math.gd` | 眼动/眨眼/说话纯数学（ARKit blendshape 权重）。 |
| `scripts/ui/nose_avatar.gd` | 程序化鼻子（Mark 的 nose 指针风格 / 本机第一人称鼻）。 |
| `scripts/ui/mark_wheel.gd` | 按住 D 的四扇区标记轮盘（眼/问/数/叹）。 |
| `scripts/ui/mark3d.gd` / `mark3d_math.gd` | 桌面标记渲染（波纹/鼻子 + 图标）/ 轮盘命中与桌面判定纯函数。 |
| `scripts/ui/emote_wheel.gd` | 按住 Y 的六扇区表情轮盘。 |
| `scripts/ui/emote_display.gd` | 头顶表情数字占位显示。 |
| `scripts/ui/board3d.gd` / `board_input.gd` | 3D 全息看板宿主（SubViewport → billboard，`set_shown` 同步拾取盒）/ 坐标换算纯函数。 |
| `scripts/ui/camera_fly_tool.gd` | 开发用飞行相机纯逻辑（G 开关、WASD/UJ、R/F 视角）。 |

### 3.3 大厅 / 设置 / 主题 / 全局

| 文件 | 职责 |
| --- | --- |
| `scripts/ui/lobby_view.gd` | 两态大厅：主菜单（创建/加入/重连）与房间（席位/Ready/房主控制/局数/玩法/商店/对局详情）；宽屏 + 紧凑双布局。 |
| `scripts/ui/lobby_seat_card.gd` | 房间席位卡（空席虚线、占席实线、房主徽章、踢人、准备状态）。 |
| `scripts/ui/lobby_dashed_border.gd` | 房间空席虚线边框（四直边 + 四段虚线圆弧）。 |
| `scripts/ui/lobby_stage_art.gd` | 房间中央卡背视觉。 |
| `scripts/ui/settings_menu.gd` | ESC 设置菜单：音量/静音/鼻子点击/目录地址/主题/房间布局/语言；全屏遮罩 + 居中卡片。 |
| `scripts/ui/ui_theme.gd` | **主题令牌 autoload**：`UITheme.color("accent")`；`switch_theme("dark" / "dark-1" / "light")`。`current` 初值 `dark`，但用户默认主题由 `Settings` 设为 `dark-1`，启动时统一应用。 |
| `scripts/ui/ui_style.gd` | **3D UI StyleBox 工厂**：`UIStyle.panel/board/chip/pill/row/tab/primary_button/...`；3D HUD/看板统一从这里取圆角、描边、透明度与阴影。 |
| `scripts/ui/hover_state.gd` | **3D hover 状态纯模型**：`HoverState.resolve(...)` 从快照 + `action_mode` + 拾取对象推导 `neutral/slap/action/valid/invalid/warning`，并给出 info 标题/正文/note；不读写规则。 |
| `scripts/ui/audio_manager.gd` | 全局音效 autoload（`select/flip/flip_quick/fly/...`），避免每张卡挂播放器。 |
| `scripts/ui/dev_tools.gd` | T 开发者面板（抢牌调试 / 卡牌皮肤 / 测试模式 / 强制效果 / 重开 / 判出局 / 摄像机视角）。 |
| `scripts/ui/manual_panel.gd` + `scenes/ui/manual_panel.tscn` | 手册/Stats/按键 三页签面板（3D 全息看板）。 |
| `scripts/ui/manual_model.gd` | 手册数据纯函数（牌序 / 能力文案 / 分数）。 |
| `scripts/ui/stats_board.gd` | 弃牌堆统计扇形牌面。 |
| `scripts/ui/keymap_board.gd` | 按键映射页（键行 + 捕获 + 保存确认浮层）。 |
| `scripts/core/keybind_model.gd` / `keybind_store.gd` | 按键动作表 / 解析、重绑（冲突自动交换、保留键拒绝）/ `user://keybinds.cfg`。 |

### 3.4 教学

| 文件 | 职责 |
| --- | --- |
| `scenes/tutorial/tutorial_3d.tscn` / `scripts/tutorial/tutorial_view.gd` | 3D 教学局：正式对局同款鼠标捕获 + 中心准星、自由环视、红色箭头、Ready/翻牌、悬停能力/Tab 手册/Shift 牌序、贴牌比赛/贴别人牌；本地时间线，**不接网络/GameState**。 |
| `scripts/tutorial/tutorial_controller.gd` | 教学步骤机（talk/interact/auto/summary；比赛/贴别人 Q/交牌 `gift_slot`；跳过/重来）。 |
| `scripts/tutorial/tutorial_overlay.gd` | 引导层（进度、任务条、对话气泡、贴牌倒计时、Ready 按钮/红字警告、纠错 toast、Esc 暂停菜单、完成卡）。 |
| `scripts/tutorial/tutorial_steps.gd` | 固定牌序与各阶段快照（含阿岚的 2、贴牌比赛、贴别人牌、动态交牌/结算）。 |
| `scripts/tutorial/tutorial_text.gd` | 教学文案集中处（含比赛/贴错/交牌）。 |
| `scripts/tutorial/tutorial_pointer.gd` | 教程屏幕空间红色箭头（目标屏内悬停/屏外贴边；不移动相机）。 |
| `scripts/tutorial/animalese_voice.gd` | 逐字语音（`assets/animalese/light`，跟随对话气泡字母播放）。 |

### 3.5 沙盒（独立场景，不影响对局）

| 文件 | 用途 |
| --- | --- |
| `scripts/ui/card_animation_sandbox.gd` + `scenes/ui/card_animation_sandbox.tscn` | 卡牌 hover/按压/翻牌/落位动效调参。 |
| `scripts/ui/card_fly_sandbox.gd` + `scenes/ui/card_fly_sandbox.tscn` | 3D 飞牌 6 种 kind 演示。 |
| `scripts/ui/card_tilt_sandbox.gd` + `scenes/ui/card_tilt_sandbox.tscn` | 2D 伪 3D 大牌倾斜调参。 |

### 3.6 场景与资源

- 场景：`scenes/ui/{game_board, player_area, table3d, settlement_page, shop_panel, joker_transform_panel, manual_panel, relic_bar, card, audio_manager, hand_silhouette_2d, item_arm_hand_3d, *sandbox}.tscn`；教学 `scenes/tutorial/tutorial_3d.tscn`。
- 资源：`assets/ui/slap_burst.svg`；卡牌 `assets/Cards/`、图集 `assets/TypeCards/`；3D 模型 `assets/3Dmodels/`、`assets/characters/source/Robot.blend`。
- 着色器：`assets/shaders/board_holo.gdshader`、`assets/shaders/board_beam.gdshader`、`assets/shaders/card_face_3d.gdshader`、`card_tilt.gdshader`、`table_surface.gdshader`、`bell_metal.gdshader`、`avatar_body.gdshader`、`crown_gold.gdshader`、`arm_overlay_3d.gdshader`。

---

## 4. UI 只读数据契约

### 4.1 对局快照 `latest_state`（`HiddenInfo.snapshot_for`）

> 客户端拿到的都是**按 viewer 投影后的快照**。所有键用 `.get(key, default)` 读取，不要假设一定存在。

| 键 | 说明 |
| --- | --- |
| `viewer_id` | 本机座位 |
| `phase` / `phase_name` | 阶段数值 / 中文名（数值见第 5 节） |
| `current_player` / `current_name` | 当前行动者 seat / 名字 |
| `room_host` | 房主 seat（只读，用于 UI 判权） |
| `match_id` / `match_number` | 本局 id / 第几局 |
| `players[]` | 玩家数组（见下） |
| `draw_count` / `discard` / `discard_count` / `discard_history` | 抽牌堆数量 / 弃牌顶 / 弃牌数量 / 弃牌历史（公开） |
| `slap_rank` / `slap_open` | 贴牌目标点数 / 贴牌窗口是否开启 |
| `settle_deadline_server_ms` | 最终轮/超限结算贴牌窗口 deadline（服务器 ms，0=无） |
| `slap_duel` / `slap_exchange_actor` | 比拼数据 / 贴牌交换行动者 |
| `q_decision` | Q 决策公开进度（actor/target/target_slot/own_viewed，不含牌面） |
| `pending` | 待处理大牌：当前玩家含牌面 + `source`/`granted_ability`；他人只有 `card_id` + `hidden:true` |
| `effect_pass` / `turn_effect` / `effect_reveal_deadline_server_ms` | 6 传递进度 / 本局效果 id / 效果展示 deadline |
| `kong_caller` / `ready_count` / `turn_index` | 已喊 Kongbaya 的 seat / Ready 人数 / 回合序号 |
| `suspended` / `offline_players` | 是否条件暂停 / 离线座位 |
| `result` / `run` / `shop` / `shop_result` | 结算结果 / 系列赛公开数据 / 本人商店货架 / 商店结果 |
| `item_cards` / `item_card_used` | 本人道具卡 id 列表 / 本回合是否已用道具 |
| `event_log` | 公开事件日志（UI 可展示，不要当隐藏信息来源） |

`players[]` 字段：`id`(seat)、`name`、`count`、`health`、`color`、`eliminated`、`currency`、`relics[3]`、`ready`、`slots[]`。

`slots[]` 字段：`card_id`、`card`（仅本人/开局记忆 peek/结算公开时存在）、`protected`、`bomb`。**`card` 不存在时只能画背面。**

### 4.2 大厅快照 `latest_lobby`（`GameState._lobby_snapshot`）

`players[{id,name,ready}]`、`host_id`、`room_host`、`your_id`、`min_players`、`max_players`、`match_limit`、`effect_mode`、`fixed_effect`、`shop_enabled`、`start_health`、`start_currency`、`shop_price`。

### 4.3 表现层信号（`GameState`）

| 信号 | UI 用途 |
| --- | --- |
| `state_updated(state)` | 对局快照主入口 |
| `lobby_updated(lobby)` | 大厅/房间刷新 |
| `private_reveal_received(title, cards, target)` | 本人看牌真实牌面 |
| `card_exchange_animated(data)` | 2D/3D 换牌/贴牌/抽牌飞牌事件 |
| `peek_highlighted(data)` | 他人看牌高亮（不含牌面） |
| `ability_start_received(seat)` | “用能力”表现层事件 |
| `item_card_used(data)` | 道具使用弹层 |
| `toast_received(message)` / `command_rejected(code, message)` | 顶部提示 / 拒绝提示 |
| `match_aborted` / `room_reset` | 中止回大厅 / 系列赛把末回房间 |
| `registered_token_received(token)` / `resume_hand_received(hand, pending)` | 重连 token / 恢复手牌 |
| `sfx_played(kind)` | 音效 |
| `mark_placed(...)` / `emote_played(seat, index)` | 标记 / 表情表现层同步 |
| `Network.connection_status_changed` / `connection_failed` / `joined_server` | 连接状态 UI |

### 4.4 阶段数值（与 `GameState.Phase` 对齐，UI 常用）

`0 LOBBY` / `1 INITIAL_PEEK` / `2 TURN_DRAW` / `3 TURN_DECISION` / `4 Q_DECISION` / `5 SLAP_WINDOW`（弃用）/ `6 SLAP_EXCHANGE` / `7 GAME_OVER` / `8 SLAP_DUEL` / `9 BET`（弃用）/ `10 SHOP` / `11 EFFECT_PASS` / `12 EFFECT_REVEAL`。

---

## 5. 常见 UI 任务操作手册

### 5.1 加一个 3D 四角 / 屏幕空间 HUD

1. 在 `main.gd` 的 `_ensure_*` 里懒创建（`Control` / `PanelContainer` / `Label`）。
2. 定位用 `main._corner_margin()` 或 `set_anchors_and_offsets_preset`，**不要用 `Control.scale` 做位置**（B1）。
3. 在 `_refresh_table3d()` / `_update_self_panel()` / `_update_round_badge()` / `_process` 里更新。
4. 颜色用 `UITheme.color(...)` / `UIStyle`，不要硬编码；3D 四角 HUD 统一使用 `UIStyle` 的深色玻璃（dark/dark-1）或浅色玻璃（light）。
5. 若只在 3D 显示，检查 `_set_table3d(on)` 的显隐。

### 5.2 加一个模态面板（结算 / 商店 / 手册类）

1. 建 `scenes/ui/xxx.tscn` + `scripts/ui/xxx.gd`，脚本提供 `setup(data, callbacks...)`。
2. 根节点 `mouse_filter=STOP`，`_build_ui()` 开头 `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`（B9）。
3. 用 `main._mount_modal(panel)` 挂载；关闭用 `main._unmount_modal(panel)`。
4. 3D 下会自动进全息看板 `board3d`；需要准星点击的控件带 `meta("board_interactive", true)`。
5. 结算页额外规则：直挂 `main` 末尾 + `z_index=100`，动画完成回调走 `_render_game_if_active()`（B23/B26）。

### 5.3 改 hint 文案 / 倒计时

- 文案只改 `scripts/ui/hint_text.gd`；`main._hint_for()` 只做委托与少量条件。
- 倒计时只改 `scripts/ui/turn_timer.gd`（纯模型）与 `hint_hud.gd`（展示）；**不要为了倒计时去改服务器**。
- 回合重置条件在 `HintHud` / `main._update_hint_hud`，不要把规则写进计时器。

### 5.4 改 2D 棋盘 / 卡牌

- 静态布局改 `scenes/ui/game_board.tscn` / `player_area.tscn`；动态渲染改 `game_view.gd`。
- 卡牌尺寸统一 5:7：`CARD_SELF_SIZE` / `CARD_PILE_SIZE` / `CARD_BIG_SIZE`。
- 卡牌重建一律 `remove_child` + `queue_free`，不要 `free()`（点击中释放会报 Object is locked，B18）。
- 大牌必须挂在 `GameBoard` 顶层，避免被容器裁剪/点击拦截（B6）。

### 5.5 改 3D 桌面 / 加交互对象

- 布局数学改 `table3d_layout.gd`；动态卡牌/按钮在 `table3d_view.gd` 代码创建，**不要搬进 `table3d.tscn`**（场景由开发者拥有）。
- 可拾取对象挂 `Area3D`，`meta` 带 `{kind, seat, slot/action}`；点击分发在 `main._table3d_click()`。
- 可用性只从 `ActionModel` 读取；拾取盒固定在根节点，不要挂在动画 pivot 上（B34）。
- 卡面用 `PlaneMesh`，不要用 `BoxMesh`（UV 十字展开会裁图，B29）。

### 5.6 改结算 / 商店

- 结算：`settlement_page.gd` 负责展示与动画，`settlement_model.gd` 负责纯计算；数据来自 `result`、`run`。
- 商店：`shop_panel.gd` 只读本人 `shop.offers/card_offers/done/refresh_cost/...` 与 `item_cards`；按钮回调走 `main` 的转发。
- 不要在前端改价格/限购/货币；显示什么就画什么。

### 5.7 改主题 / 卡牌皮肤 / 按键

- 主题：改 `ui_theme.gd` 的 `TOKENS`；新增 token 同步 `docs/UI主题规范.md`。
- 卡牌皮肤：`card_atlas.gd` 负责图集 region；`card_view.gd` 优先 `card_data.type`，否则 `CardAtlas.preview_type`；图集缺失自动回退旧素材。
- 按键：`scripts/core/keybind_model.gd` 增动作/保留键，`keymap_board.gd` 展示；键处理在 `main._input` / `_unhandled_input`。

### 5.8 改 3D 角色 / 标记 / 表情 / 飞牌

- 角色：`robot_avatar.gd`（模型、配色、眼动/头动/说话/抬手），数学在 `robot_avatar_math.gd`；不要改 `Robot.blend`。
- 标记/表情：轮盘 UI 在 `mark_wheel.gd`/`emote_wheel.gd`，渲染在 `mark3d.gd`/`emote_display.gd`；协议见 `网络协议_V1.md` §4.9/§4.10。
- 飞牌：参数 `card_fly_config.gd`、数学 `card_fly_math.gd`、控制器 `card_fly.gd`；对局编排在 `table3d_view.animate_exchange()`。
- 详细 3D 章节直接看 `docs/3D角色与场景说明.md`，本文不重复。

---

## 6. UI 相关坑（防复发）

| 编号 | 症状 | 规则 |
| --- | --- | --- |
| B1 | 大牌/控件位置漂移 | 不用 `Control.scale` + `pivot_offset` + `global_position` 组合定位；用实际尺寸定位。 |
| B6 | 大牌被裁剪 / 看得见点不到 | 大牌挂 `GameBoard` 顶层；board `mouse_filter=PASS`，大牌卡 `IGNORE`。 |
| B9 | 弹窗不可见（尺寸 0） | `_build_ui` 开头 `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`。 |
| B18 | 卡牌重建报 Object is locked / freed instance | `remove_child` 后 `queue_free`；渲染前清空 `_card_slots`。 |
| B23/B26 | 结算页按钮点不到 / 翻开的牌又被翻回 | 根 `STOP` + 直挂 main + `z100`；动画回调走 `_render_game_if_active()`。 |
| B29 | 3D 卡背被裁掉 | 卡面用 `PlaneMesh(FACE_Y)`，不用 `BoxMesh`。 |
| B30 | 隐藏的牌仍被准星命中 | 显隐时同步 `CardBlock.set_pick_enabled`。 |
| B32 | hover 对象释放后报错 | 形参去类型 + `is_instance_valid`。 |
| B34 | hover 边缘抖动 | 拾取盒固定在根节点，不随动画 pivot 移动。 |
| B37 | 揭示翻完又重播 | `reveal(... from_p)` 按已过时间续播，不从头播。 |
| B38 | 炫光优先级错 | `flash > reveal > protected > hover > actionable`。 |
| B39 | 常驻提示板吞掉牌桌点击 | 用 `main._click_route()` 三态路由，不要用 `hint3d.visible` 直接拦。 |
| B40 | 退出 3D 时已释放面板崩溃 | `Board3d._prune_panels()`；关模态前先 `_unmount_modal`。 |
| B44 | 罚牌飞到一半穿桌 | 未渲染槽用 `HandAnchor.global_transform * _slot_local()`。 |
| B45 | 3D 交换飞牌泄漏牌面 | `CardFly` 按“当前可见面”门控牌面/标签。 |
| B46/B48 | 隐藏看板仍抢射线 / 商店点不中 | 显隐一律走 `Board3d.set_shown(on)`，不要直接改 `visible`。 |
| — | 卡背露出点数 | `CardBlock._sync_label_visibility()` 翻面 <0.5 不显示点数。 |

---

## 7. 验证（headless，不启动 GUI）

- 一键全量：`tools/run_all_tests.sh`；快速核心：`tools/run_all_tests.sh --quick`（近期基准 53/53）。
- 单测入口示例：

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --headless --path . res://tests/verify_hint_hud.tscn
$GODOT --headless --path . res://tests/verify_manual.tscn
$GODOT --headless --path . res://tests/verify_actions.tscn
$GODOT --headless --path . res://tests/verify_hover_state.tscn
$GODOT --headless --path . res://tests/verify_discard_take_discard.tscn
$GODOT --headless --path . res://tests/verify_board3d.tscn
$GODOT --headless --path . res://tests/verify_table3d.tscn
$GODOT --headless --path . res://tests/verify_table3d_layout.tscn
$GODOT --headless --path . res://tests/verify_table3d_mouse.tscn
$GODOT --headless --path . res://tests/verify_table3d_interaction.tscn
$GODOT --headless --path . res://tests/verify_table3d_exchange.tscn
$GODOT --headless --path . res://tests/verify_robot_avatar.tscn
$GODOT --headless --path . res://tests/verify_nose.tscn
$GODOT --headless --path . res://tests/verify_mark.tscn
$GODOT --headless --path . res://tests/verify_emote.tscn
$GODOT --headless --path . res://tests/verify_card_skin.tscn
$GODOT --headless --path . res://tests/verify_card_animation.tscn
$GODOT --headless --path . res://tests/verify_card_fly.tscn
$GODOT --headless --path . res://tests/verify_card_tilt_math.tscn
$GODOT --headless --path . res://tests/verify_settlement.tscn
$GODOT --headless --path . res://tests/verify_shop.tscn
$GODOT --headless --path . res://tests/verify_relic_ui.tscn
$GODOT --headless --path . res://tests/verify_item_cards.tscn
$GODOT --headless --path . res://tests/verify_item_hand.tscn
$GODOT --headless --path . res://tests/verify_lobby.tscn
$GODOT --headless --path . res://tests/verify_restart.tscn
$GODOT --headless --path . res://tests/verify_q_hold.tscn
$GODOT --headless --path . res://tests/verify_stat_panel.tscn
$GODOT --headless --path . res://tests/verify_keybind.tscn
$GODOT --headless --path . res://tests/verify_hint.tscn
```

- 新增纯展示逻辑时，优先抽成 `RefCounted` 纯函数并加 headless 用例；不要把可测逻辑塞进 `_process` 或节点树。

---

## 8. 参考文档

- `docs/3D角色与场景说明.md`：3D 对局场景布局、Robot 角色/眼动、标记/表情、发牌、皇冠等章节（**3D UI 必读**）。
- `docs/UI主题规范.md`：主题令牌 dark / dark-1 / light。
- `docs/网络协议_V1.md`：§4.8 注视、§4.9 标记、§4.10 表情、§4.11 重开；表现层 RPC 改动前必看。
- `docs/BUG档案.md`：本文第 6 节坑位的完整根因与修复。
- `docs/功能实现文档.md`：16 Feature 文件树与待开发清单。
- `docs/superpowers/specs/`：各 UI 批次的设计稿（结算页、全息看板、hint HUD、卡牌动画、卡牌皮肤、商店/遗物、Room Pool 等）。
- `docs/AI_AGENT_交接说明.md` §4：UI 层拆分表与当前工程现状。

---

## 9. 2026-11-11 3D HUD / Hover / 商店 / 投影看板批次

> 以 3D 表现层为主，附一条“取自弃牌堆可弃掉”的规则变更。规则/协议以 `KONG_开发文档.md`、`网络协议_V1.md` 为准。

### 9.1 令牌与 StyleBox 工厂
- 新增 `scripts/ui/ui_style.gd`：`panel/board/chip/pill/row/tab/primary_button/secondary_button/tooltip/hover_color/info_box`。
- `ui_theme.gd` 新增 `hud_surface`、`board_surface`、`hud_text_muted`、`currency`、`danger_text`、`danger_soft`、`hud_shadow`；新增 `hover_neutral/slap/action/valid/invalid/warning`（dark/dark-1/light 三套）。
- 3D HUD / 看板 / 商店 / 结算 / 手册统一走 `UIStyle`；2D 棋盘不改。

### 9.2 3D HUD
- `HintHud`：倒计时直接显示秒数（24 / 9 / 0），正常/警告/超时三态；SLAP 颜色令牌化。
- `KeyHintPanel`：去掉外框，顺序改为 **放大 / 标记 / 手册 / 道具**；chip 改深色玻璃。
- `CardOrderPanel`：叠放浅色小牌，忽略花色，Joker 显示 `JK` 红字。
- `PlayerStatPanel` / 回合徽标：玻璃面板；货币改用 `currency`。
- `TurnEffectPanel`：玻璃底板 + 标题/名称/多行说明。
- `CardTooltip`：统一 360 宽；状态气泡含标题/正文/note/4px 状态条/10% 状态色底；默认牌面 info 改为“点数标题 + 能力正文”。
- `Crosshair`：圆环 + 中心点；Ready/条件按钮：主/次统一 UIStyle，已准备为绿色正向态。

### 9.3 3D 看板投影
- `Board3d` 屏幕由 `QuadMesh` 换成 **24×16 细分 PlaneMesh**，顶点做轻微弧度。
- 新增 `assets/shaders/board_holo.gdshader`：**圆角 SDF 贴边发光 + 外发光壳 + 屏幕空间扫描线 + 轻微色差**；扫描线用 `FRAGCOORD.y`，移动视角时不会跟着面板歪斜/断线。
- 新增 `assets/shaders/board_beam.gdshader`：看板下方交叉梯形光锥（加法混合）。
- `Board3d` 视觉层挂 `Visual` 节点：背板投影、光锥、地面辉光、四角支架、`GPUParticles3D` 尘埃、漂浮（只动 `Visual`，根节点锚点/拾取不变；屏幕坐标换算用 `_screen.global_transform`）。
- `set_frame_enabled` 控制发光边与全部增强层：模态看板开，常驻提示板关（只留按钮）。

### 9.4 Hover 状态
- 新增 `scripts/ui/hover_state.gd`（纯函数）：`neutral/slap/action/valid/invalid/warning`。
- 覆盖 7/8、9/10、Q 两阶段、replace、slap_open、抽牌阶弃牌、取自弃牌堆后的 warning。
- `Table3dView.set_hover_state` 统一虚线框颜色；`main` 每帧 `HoverState.resolve`；`CardTooltip.show_state` 展示状态 info。
- 其他玩家弃牌顶只读；抽牌堆仅当前玩家抽牌前可 hover/点击；替换大牌时 hover 自己的手牌提示“替换卡牌”。

### 9.5 规则变更（UI 同步）
- 取自弃牌堆的 pending 现在可以再次弃掉：`_server_discard_draw` 放行 `source=discard`；仍禁止发动牌面能力；Joker 变换遗物按 R-11 保留。
- `ActionModel.pending_discard_available` 对 draw/discard 两种来源为 true；`main._on_pending_action` 只有 draw 才进入能力流程。
- 弃掉后牌回到弃牌顶、开贴牌窗口并换人；新增 `verify_discard_take_discard`。

### 9.6 商店
- `shop_panel.gd` + `shop_panel.tscn`：玻璃 board、1000 宽；标题「商店」与副标题「SHOP · 道具与遗物」水平居中；3 道具槽 + 2 遗物槽；购买 primary、锁定/刷新 secondary；价格用 `currency`；只保留底部货币。

### 9.7 测试与设计稿
- 新增 `verify_hover_state`（24/24）、`verify_discard_take_discard`（8/8）；`verify_card_tooltip` 30/30、`verify_board3d` 70/70；`tools/run_all_tests.sh --quick` **58/58**。
- 设计稿：`docs/superpowers/specs/2026-11-10-hud-unify-mockup-v2.svg`（F 商店 / G 默认卡牌 Info / H 投影看板 H1–H4）。

### 9.8 未完成
- 面板内部真实景深（分层 SubViewport / 3D 按钮）未做。
- 真正 3D Tab（带厚度/抬起）未做；当前只有扁平角标。
- Web 客户端未做。


### 9.9 2026-11-11 追加：看板全息增强 / 尺寸与排版

#### 3D 看板全息增强
- `board3d.gd` 新增 `Visual` 子节点承载视觉层：背板投影（软边径向暗块）、交叉光锥、地面辉光、四角 L 支架、18 粒 `GPUParticles3D` 尘埃；漂浮只动 `Visual`（±1cm，0.75 rad/s），根节点锚点与拾取盒不动。
- `board_holo.gdshader`：保留圆角 SDF 贴边发光，新增外发光壳、屏幕空间扫描线（`FRAGCOORD.y`，转动视角不断线）、周期扫描带、色差 0.00035；`tint` alpha 0.96。
- 新增 `assets/shaders/board_beam.gdshader`：上窄下宽梯形 + 两侧淡出 + 顶部亮/底部透明；两片交叉摆放近似体积光。
- `set_frame_enabled(false)`（常驻提示板）同时关闭发光边与全部增强层；`set_shown` / `_sync_visible` 同步尘埃 `emitting` 与拾取盒。
- `set_ground_drop(BOARD_FLOAT_H)` 让光锥/地面辉光对齐桌面；准星坐标换算用 `_screen.global_transform`，漂浮时点击映射仍准确。
- 常驻提示板（Ready/条件按钮）不漂浮、不加光锥，保持只显示按钮。

#### 看板锚点
- `BOARD_FLOAT_H` `2.1 → 1.8`：整体 Y 下移 0.30m。
- 新增 `BOARD_FORWARD` `0 → 0.35`：沿“桌心→本机座位”方向外推（靠近玩家/相机）。
- seat0 示例（座位 `(0,0,2.4)`）：中心 X 0 / Y 4.001→3.701 / Z +2.28→+2.63；其他座位按座位径向旋转（seat1 X +0.35、seat2 Z -0.35、seat3 X -0.35），Y 统一 -0.30。
- 提示板与模态板共用锚点，会一起移动。

#### Hover 修复
- `Table3dView._apply_hover` 跳过 `pick.kind == "board"`：看板不再被牌桌 hover 逻辑整块叠灰/描边（此前会连光锥、地面辉光一起被盖住）。
- `Board3d.hit_viewport_coord` 把视口坐标夹到板内：拾取盒边缘命中仍归本板，不再掉回牌桌触发 hover。
- 回归：`verify_board3d` 新增「看板 pick 不叠加 hover 材质」「普通拾取对象仍显示 hover 材质」。

#### 尺寸与排版
- 手册/Stats/按键板最小尺寸 `1000×795`，与商店板一致（`Board3d` wrap 后世界尺寸、锚点高度相同）；表格列 100/720/100，行高纵向均分，字号 18/16。
- Stats：牌面 64×90、`STEP_FRAC 0.94`、`ROW_GAP 30`、`ARC 8`（约 890×450），行标签 16。
- 按键：行高 64、列 90/90/430/170、行内左右 14px；字号 18/15/16/13；保存按钮 200×50。
- 结算：面板 600→840、行 520×46→760×58、内边距 20→28、行内左右 16px；标题 26、名次/名字/总分 22/20/22、卡片 chip 38×50、状态/奖励 16、底部按钮 240×52。

#### 验证
- `verify_board3d` 72/72、`verify_manual` 74/74、`verify_keybind` 37/37、`verify_settlement` 40/40；受影响用例全部通过（上次全量 `--quick` 58/58）。

---

## 10. 2026-11-11 教程 V2（正式对局操作 + 贴牌比赛 / 贴别人牌）

### 10.1 输入与镜头

- `TutorialView` 使用正式对局同款**鼠标捕获 + 屏幕中心准星**：移动鼠标自由环视，左键按中心射线交互，`Esc` 暂停/释放鼠标。
- 开局/重新开局用**可见鼠标 + 屏幕 Ready 按钮**：点任意位置翻开下排两张；没翻开就点 Ready → 加大红字「先翻开下方的两张牌！」。
- 不再 `aim_at` / `lock_aim_at` 强制转镜头；目标只做金色 glow + `TutorialPointer` 红色箭头（屏内悬在目标上方、屏外贴边指向）。点错统一提示「请跟随提示」。
- 大牌每次渲染前 `Table3dView.update_facing(current_player)`，并在 `_process` 每帧同步，保证竖立且朝向行动者；卡牌 hover 恢复完整幅度（`hover_amp=1.0`）。

### 10.2 流程

- **欢迎/规则演示**：欢迎文案 + 翻开下排两张 + Ready；抽 9 演示「替换 / 弃掉」两个选择；讲解 A—Q=1—12、K=-1、Joker=0，Shift 开关牌序；Tab 打开手册或瞄准公开牌看能力；「重新开始」重发同样的牌。
- **正式局**：再次翻开 + Ready；玩家先手抽 A，提示「你好像有一张 10」并替换（`part2_replace`）；阿岚抽 Q/换牌均至少等 1s，只说明换牌与弃牌（此步不提 slap）；接回第二次抽 9/弃牌。
- 阿岚弃 2 → `slap_explain` → **贴牌比赛**：阿岚手里也有 2，1.5s 后自动贴；玩家必须更快，失败提示「只有最快翻开牌的人才可以成功贴牌哦，再试一次！」并重置重试。
- 阿岚抽/弃 4 后自己贴她的 2（错）→ 罚到 6；`slap_other_setup` 换一张 Q 出去；`slap_other_tell` 提示右下角还有 Q；玩家贴她的 Q → `SLAP_EXCHANGE`；`slap_other_exchange` 玩家选自己的 slot0/1/3 交给她（`slap_gift`）；阿岚再贴错到 7 → 动态 `game_over_gift` 结算。
- `RobotAvatar` 说话只驱动 `Face+Eyes`（`Arms/Legs/Body` 不驱动）。
- 完成卡：`回到主界面`（可点击；结算页设为点击穿透，看板/完成卡移到输入最前）；`重看教程` 保留。
- 贴牌表现：自己贴牌/贴别人 Q 都先 `reveal_slot` 真翻牌（绿光）→ 等待 → `slap_resolved` 飞到弃牌堆；不再直接进弃牌堆。
- 悬停：只显示公开/真实已知牌（pending/弃牌顶）；手牌背面不再从教程记忆表反推点数。

### 10.3 文件与测试

- `scripts/tutorial/{tutorial_steps,tutorial_controller,tutorial_text,tutorial_overlay,tutorial_view,tutorial_pointer,animalese_voice}.gd`；`assets/animalese/light/`。
- `verify_tutorial` **154/154**、`verify_robot_avatar` **87/87**、`verify_table3d_interaction` **101/101**。
