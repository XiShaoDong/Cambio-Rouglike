# KONG：AI Agent 交接说明（Agent 必读 · 工程现状与工作方式）

> **本文档职责**：只给 **AI Agent**。用于让下一个 Agent 快速理解当前工程，在不重构既有基础的前提下继续开发。开始任何改动前，按第 1 节文档地图顺序阅读对应文档。规则/协议/测试权威见各文档，本文件不重复，只给"工程现状、架构不变量、工作方式、验证命令、关键 bug 档案入口"。

---

## 1. 文档地图（每个文档职责 + 给谁看）

| 文档 | 职责 | 给谁看 |
| --- | --- | --- |
| `AI_AGENT_交接说明.md`（本文件） | 工程现状、架构不变量、工作方式、验证命令、文档地图 | Agent 必读 |
| `BUG档案.md` | 已解决 bug + 根因/修复/诊断方法（防复发） | Agent + 开发者 |
| `KONG_开发文档.md` | 规则/产品/架构**权威**主规格（R-01~R-06 等） | 权威 |
| `网络协议_V1.md` | RPC/快照字段、错误码、隐私/幂等契约 | 权威 |
| `验收与测试计划.md` | T/P0-N 用例、验证闸门 | 权威 |
| `功能实现文档.md` | 文件树 + 16 Feature 映射 + 待开发清单 | Agent + 开发者 |
| `UI主题规范.md` | 主题令牌（dark/light） | 开发者 |
| `问题档案.md` | 未决/待确认问题登记 | Agent + 开发者 |
| `遗物设计卡模板.md` | Roguelike 设计卡填写模板 | 开发者 |
| `修改日志.md` | **开发者个人**追踪（request→实现→反馈，gitignore，不纳入版本） | 开发者，非 Agent |

> 开发者用途文档（修改日志、UI主题、遗物模板）对 Agent 只需知道"存在 + 各自职责"，不强制读全文。

---

## 2. 当前基线

- 项目：Godot 4.6，KONG（Cambio + 轻度 Roguelike）LAN MVP。
- 当前目标：先验证 2–4 人纯基础牌局；Roguelike 尚未启用（`enable_relics = false`）。
- 联网：ENet/UDP，房主权威，默认端口 `7007`。
- 状态：大厅、对局界面、服务器权威状态机、规则、动效系统均已实现；已有自动化验证（见第 8 节）。
- Git：仓库 `git@github.com:XiShaoDong/Cambio-Rouglike.git`，分支 `main`。
- 项目路径：`~/dev/gameDev/cambio-rouglike/`。

## 3. 架构不变量（禁止无理由重构）

1. `GameState` 保存完整 `deck`/`discard_pile`/`cards`/各玩家手牌；客户端不保存权威牌面。
2. 客户端只能调 `request_*` 意图方法；服务器收到 RPC 后再校验调用者、阶段、目标。
3. `HiddenInfo._snapshot_for(viewer_id)` 按接收者生成状态；结算前普通手牌槽位不含 `rank/suit/value`。
4. 看牌走 `receive_reveal` 定向消息，一次性展示；不要把已知牌写入公共状态。
5. 贴牌胜负以服务器收到第一条有效请求为准。
6. 规则层不依赖 IP/UI 节点/房主画面；未来 Headless VPS 复用 `GameState`。
7. `run_state`/`RunModifier` 是扩展缝，默认不启用。

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
| `slap_system.gd` | 贴牌窗口 |
| `kongbaya_system.gd` | Kongbaya 最终轮 |
| `network.gd` | ENet 连接/大厅/断线 |

UI 层已拆分（main.gd 是组合根）：

| 文件 | 职责 |
| --- | --- |
| `main.gd` | 组合根：App 生命周期 + signal 转发 + 工具 |
| `game_interaction.gd` | 交互状态机（action_mode/selected） |
| `lobby_view.gd` | 大厅构建/建房/加入/双开 |
| `game_view.gd` | 对局构建 + 状态投影渲染 |
| `reveal_controller.gd` | 看牌翻转动画 |
| `card_animator.gd` | 卡牌移动/交换/落位动画（副本 + 隐藏源卡 + 虚线占位） |
| `dev_tools.gd` | F12 布局调试 / T 主题切换 |
| `card_view.gd` / `card_factory.gd` | 卡牌视图节点 / 构建 |
| `dashed_border.gd` | 虚线边框占位 |

## 5. 状态机（`GameState.Phase` 数值不可随意变更，需同步 UI 与测试）

| 值 | 名称 | 允许主要动作 |
| ---: | --- | --- |
| 0 | LOBBY | 注册、房主开始 |
| 1 | INITIAL_PEEK | 玩家确认记住开局两张牌 |
| 2 | TURN_DRAW | 当前玩家抽牌/取弃牌顶/喊 Kongbaya |
| 3 | TURN_DECISION | 替换、弃抽到的牌、发动技能 |
| 4 | Q_DECISION | Q 操作者决定不换或交换 |
| 5 | SLAP_WINDOW | 所有人尝试贴任意一张牌 |
| 6 | SLAP_EXCHANGE | 贴中他人者交出一个槽位 |
| 7 | GAME_OVER | 公开所有牌并显示结果 |

## 6. 网络与隐私契约（详见 `网络协议_V1.md`）

- 房主 `Network.host_game`（ENet peer ID = 1）；客户端 `Network.join_game` + 注册昵称。
- 命令进入 server `server_*` RPC → 私有 `_server_*` 验证。
- 状态消息：`receive_lobby`/`receive_state`/`receive_reveal`/`receive_toast`，牌面仅允许在弃牌顶、行动者的待处理抽牌、结算牌中出现。
- 交换动画：server 广播 `card_exchange_animated` 事件，各 client 用**自己视角的 `_card_slots`** 定位播放。

## 7. 关键 bug 档案（已解决，复现时按诊断方法修复）

> 完整档案见 `BUG档案.md`。核心三条，容易因后续需求复发：

- **B1 大牌位移**：`Control.scale`+`pivot_offset`+`global_position` 组合位置漂移 → 用**实际尺寸定位**，不用 scale。
- **B2 槽位永久虚线**：GDScript lambda 捕获 int 计数器不累积 → 用**字典计数器 + bind**。
- **B3/B4 hint 问题**：RichTextLabel 不显示 → 回退 Label；每字一行 → 设固定宽度。

## 8. 验证命令（headless 单元测试，不启动 GUI）

```bash
# 编译检查
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
# 协议测试（27/27）
... --headless --path . res://tests/verify_protocol.tscn
# 交换动画测试（10/10）
... --headless --path . res://tests/verify_swap.tscn
# hint 生成测试
... --headless --path . res://tests/verify_hint.tscn
# 双实例网络回归（host + client 各跑，均 exit 0）
... --headless --path . res://tests/verify_net.tscn -- -role host
... --headless --path . res://tests/verify_net.tscn -- -role client
```

> **开发约定**：按用户的指示**不启动 GUI**，用上述 unit test 验证后总结。每次改动后跑 `verify_protocol` + `verify_swap` + 双实例 `verify_net`。

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
