# feature-online P1：中立专用服务器（Dedicated Headless Server）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`).
> 分支：`agent/feature-online`。原则见 `docs/AI_AGENT_交接说明.md` §3/§9：先方案→确认→再动代码；不改协议语义、不改规则、快照/HiddenInfo 不动；一次只解决一个可验证问题。

**Goal:** 让权威进程能**脱离玩家**跑在公网 VPS 上：客户端 `IP:端口` 直连即对战；服务器**不占玩家座位**；保留现有 LAN「玩家当 host」模式作为另一条启动路径。

**Architecture:** 现状把「权威(ENet server = peer 1)」与「座位(seat 0)」绑死（`_on_host_started` → `_add_player(1,…)`）。P1 只做**解耦**：
1. `Network` 增加「host 是否作为玩家」开关 + `start_dedicated(port)`；
2. `GameState` 在 dedicated 下**不注册 host 座位**；**房主 = 房间创建者 = 首个进入的玩家**，存为**动态 `host_seat`**（默认 0；房主离开→转移给下一玩家），所有房主校验由写死 `0` 改为读 `host_seat`；
3. 新增 headless 入口场景 `scenes/server.tscn`（无 UI），端口从命令行读入；
4. 客户端「我是不是房主」判定从 `Network.is_host`（=本进程是不是 ENet server）改为**房间房主 = viewer 是否等于 `room_host`(=`host_seat`)**。

**Tech Stack:** Godot 4.6.x / GDScript；ENet/UDP（复用，不换 WebRTC）；headless 单测。

## 决策记录（2026-10-10 已拍板）
1. **P1 = 单房 demo；目标 = 多房并发**（多房归 P2，含房间目录/生命周期）。
2. **房主离开 → 转移**给下一玩家（不做"解散式"销毁）；房主为**动态 `host_seat`**（不再写死 0）。**转移只在 LOBBY 生效**；对局中房主掉线仍走"标记离线+暂停+重连"。
3. **开始对局必须全员 Ready**（`request_set_ready` 服务器权威；每局结束后 ready 重置）。
4. **断线重连宽限 60s**。
5. **短码 TTL 30 分钟**（**仅限制"用码加入"**；与断线重连无关）＋ **空房回收 60s**（多房，P2）。
   - **三者独立**：码 TTL（能否用码加入）≠ 房间存活（有无玩家）≠ 断线重连（用 token，与码无关）。码过期不影响已入座玩家或重连。

## Global Constraints
- **不改规则/状态机/快照字段/`HiddenInfo`**：`GameState` 权威模型、`_snapshot_for`、`Phase` 数值全部不动。
- **不改协议语义**：现有 RPC 名/参数不变；P1 最多新增**发送端**入口与**lobby 快照**一个只读字段。
- **保留双模式**：LAN 玩家当 host 逐字不变；dedicated 为新增路径。
- **`scripts/net/*` 仅 `network.gd` 改动**，`proxy_relay.gd` 不动。
- 不改 `scenes/ui/table3d.tscn`、2D 渲染文件、`Robot.blend`。
- 跨文件引用用 `preload` 常量；headless 可测（纯逻辑不依赖显示）。
- 每个 Task 结束跑题注测试；整套结束跑 §验收 全量回归。

## 关键事实（现状，供实现对照）
- 自动加载：`Network`(`scripts/net/network.gd`)、`GameState`(`scripts/core/game_state.gd`)、`Settings`/`Loc`/`UITheme`/`AudioManager`/`MCPRuntimeProbe`（`project.godot:18`）。`run/main_scene="res://scenes/main.tscn"`。
- host 起点：`lobby_view.host_game()` → `Network.host_game(profile, port)`（`network.gd:22`）→ `host_started` → `GameState._on_host_started`（`game_state.gd:134`）→ `_add_player(1, "房主")`（seat 0）。
- 房主=seat0 的校验：`_server_start_match` `sender != 0 → NOT_HOST`（`game_state.gd:474`）；`_server_next_match`（537）；`_server_dev_eliminate`（979）。
- 房主本地入口：`request_start_match`/`request_next_match` 的 `if is_server(): _server_*(_peer_to_seat(1), …)`（460/520）；`request_abort_match`/`request_close_room` `if not is_server() or not Network.is_host: return`（1052/1069）。
- 转发时 `peer == 1` 当"本机/房主客户端"本地发射：`_reject`(274)、`_broadcast_state` 的 `_receive_state.call_deferred`(1526)、各 broadcast(1537/1552/1564/1581/1590)、`_send_reveal`/`_send_toast`。
- `create_server` 客户端上限 = `KongRules.MAX_PLAYERS - 1`（`network.gd:26`，因 host 占 1 席）。`MAX_PLAYERS=4`、`MIN_PLAYERS=2`、`DEFAULT_PORT=7007`（`game_rules.gd`）。
- 客户端"房主"UI 依赖 `Network.is_host`：`lobby_view.gd:153`、`game_view.gd:292`、`dev_tools.gd:37`、`main.gd:29/1003/1037/1326`、`game_state.gd:130`。
- `_lobby_snapshot()` 广播给所有人且无"你是几号"字段（`host_id: 0` 固定，`game_state.gd:1498/1504`）。

---

### Task 1: `Network` 中立 host 开关 + `start_dedicated`
**Files:** Modify `scripts/net/network.gd`; Create `tests/verify_dedicated.gd` + `.tscn`; Modify `tools/run_all_tests.sh`。

- [ ] **Step 1 写失败测试** `tests/verify_dedicated.gd`（headless，直接驱动 autoload）：
  - 断言 `Network.host_game({"name":"房主"}, port, true)` 后 `Network.host_is_player == true`；`Network.start_dedicated(port)` 后 `host_is_player == false` 且 `is_host == true`。
  - 用 `Network` 暴露的只读 computed 属性断言 max_clients：玩家模式 = `MAX_PLAYERS-1`；dedicated = `MAX_PLAYERS`。
  - 复用 `verify_net` 的双实例骨架做真实 ENet 校验（见 Task 6）。
- [ ] **Step 2** 改 `network.gd`：
  - 新增 `var host_is_player := true`、`var dedicated := false`。
  - `func host_game(profile: Dictionary, port := DEFAULT_PORT, as_player := true) -> void`：`host_is_player = as_player`；`create_server(port, KongRules.MAX_PLAYERS - (1 if as_player else 0))`。
  - 新增 `func start_dedicated(port := DEFAULT_PORT) -> void:` → `host_game({"name":"服务器"}, port, false)`；`dedicated = true`。
  - `disconnect_game()` 复位 `host_is_player=true`/`dedicated=false`。
  - `const SEAT_MAX_FOR_MODE` 之类计算封装为 `func max_clients() -> int`（测试可断言，不依赖引擎内部值）。
- [ ] **Step 3** `tools/run_all_tests.sh` 注册 `verify_dedicated`。
- [ ] **Step 4** 跑 `res://tests/verify_dedicated.tscn` 通过（先只过 Step 1 的纯属性断言）。

### Task 2: `GameState` dedicated 下不占座位
**Files:** Modify `scripts/core/game_state.gd`（仅表现层/生命周期，不碰规则）。

- [ ] **Step 1** `_on_host_started`（`game_state.gd:134`）：
```
func _on_host_started(profile):
    _reset_match()
    if Network.host_is_player:
        _add_player(1, str(profile.get("name","房主")))
    _broadcast_lobby()
```
  → dedicated 下 `players` 为空起步，服务器**无座位**。
- [ ] **Step 2** `request_start_match`/`request_next_match` 的服务器本地分支（460/520）：dedicated 下该分支不应再假定 `_peer_to_seat(1)` 有意义——改为 `if Network.host_is_player: _server_*(_peer_to_seat(1), …) else: return`（dedicated 的启动一律经 `server_start_match` RPC 由 seat 0 客户端触发）。
- [ ] **Step 3** `request_abort_match`/`request_close_room`（1051/1068）：
  - **守卫**：玩家模式保持仅房主本地可调；dedicated 改为经 RPC（`server_abort_match`/`server_close_room`）由**房主**（`sender == host_seat`）触发。
  - **解散语义（拍板）**：`_server_close_room` = 通知全员回大厅 + **销毁/重置该房间资源**（单房 dedicated = 重置为空闲态，不退出进程；多房 = 移除登记）。**不再做"只踢人回大厅、房间留着"**，以杜绝 zombie。
  - **房主离开**（`_on_peer_left`，仅 LOBBY）：不销毁房间，**转移 `host_seat`** 给 `turn_order` 中下一个在线玩家；无人则房间回收（多房 P2）。对局中房主掉线仍走"离线标记+暂停+重连"。
- [ ] **Step 4** `_reject`(274) 的 `peer == 1 → 本地 emit`：dedicated 下不存在 peer 1 座位（`_peer_to_seat(1) = -1`），该分支自然不触发；确认无副作用（seat→peer 路由照旧走 `players[seat].peer_id`）。
- [ ] **Step 5** 断言（Task 6 测试）：`start_dedicated` 后 `players.is_empty()`；首个注册者 = seat 0 且 `host_seat == 0`；`_server_start_match(host_seat, …)` 成功、非房主 → `NOT_HOST`；**房主离开后 `host_seat` 转移到下一在线玩家**。

### Task 3: lobby 快照告知"你的座位/房主"，客户端房主 UI 改判
**Files:** Modify `scripts/core/game_state.gd`（`_lobby_snapshot`/`_broadcast_lobby`）; `scripts/ui/lobby_view.gd`; `scripts/ui/game_view.gd`; `scripts/ui/dev_tools.gd`; `scripts/ui/main.gd`。

- [ ] **Step 1** `_broadcast_lobby` 改为**逐 peer** 发 lobby（每个接收者带 `your_id`）：
  - `_lobby_snapshot()` 增参 `viewer_seat := -1`，返回体加 `"your_id": viewer_seat`、`"room_host": host_seat`（**动态房主座位**，不再写死 0）、`"dedicated": Network.dedicated`。
  - 循环里对 `peer == 1` 用 `viewer_seat=0`（玩家模式房主本人），其余用其 seat；离线跳过。
  - **只读附加字段**，不改既有字段语义。
- [ ] **Step 2** 客户端"我是不是房主"统一为：`is_room_host = (latest_lobby.get("your_id", -1) == latest_lobby.get("room_host", 0))`（大厅阶段）；对局中可用 `state.viewer_id == room_host`。
  - `lobby_view.gd:153` 建房/开始/解散/退出按钮的显隐 → 用 `is_room_host`。
  - `game_view.gd:292` 暂停时房主按钮 → `is_room_host`。
  - `dev_tools.gd:37` 开发者面板 host-only → `is_room_host`（= 当前 `host_seat`）。
  - `main.gd` 1326 结算页"再来一局"host 位 → `is_room_host`。
- [ ] **Step 3** `main.gd:29/1003/1037`、`game_state.gd:130` 处保留 `Network.is_host` 语义（"本进程是 ENet server"），**不**改（与"房主角色"区分）。
- [ ] **Step 4** 测试断言：dedicated lobby 快照每位接收者拿到正确 `your_id`；`your_id == host_seat` 的客户端 `is_room_host==true`，其余 false；**房主转移后随之变化**。

### Task 4: headless 入口（无 UI）+ 端口/参数外置
**Files:** Create `scripts/server_main.gd`, `scenes/server.tscn`; Modify `scripts/ui/lobby_view.gd`（仅把现有 `--dev-join` 解析风格复用，不改 UI 行为）。

- [ ] **Step 1** `scripts/server_main.gd`（`extends Node`）：
  - `_ready()`：解析命令行 user args：`--port <n>`（默认 `KongNetwork.DEFAULT_PORT`）；调 `Network.start_dedicated(port)`；`print` 一行"KONG dedicated server listening on UDP <port>"。
  - 不实例化任何 UI；`GameState`/`Network` 作为 autoload 自动就绪。
- [ ] **Step 2** `scenes/server.tscn`：根 `Node` 名 `ServerMain`，挂 `server_main.gd`。
- [ ] **Step 3** 运行方式（写入 §部署手顺）：`godot --headless --path . res://scenes/server.tscn -- --port 7007`。
- [ ] **Step 4** 断言（Task 6）：headless 起 `server.tscn` 后 `Network.is_host==true && Network.host_is_player==false && GameState.players.is_empty()`。

### Task 5: 文档
**Files:** Modify `docs/网络协议_V1.md`（新增 §"部署形态/中立服务器"说明；lobby 快照加 `your_id`/`room_host`/`dedicated` 字段，标注只读）；Modify `docs/功能实现文档.md`、`docs/AI_AGENT_交接说明.md`（feature-online 现状与 P1）。

### Task 6: 测试与验收
**Files:** `tests/verify_dedicated.gd`/`.tscn`（单进程驱动 GameState/Network 逻辑 + 双实例 ENet 冒烟）。

- [ ] **Step 1** 单进程断言：dedicated 无座位 / 客户端注册 seat 递增 / seat0 房主权限 / 非 seat0 被拒 / lobby `your_id` / abort·close 由 seat0 经 RPC 生效（dedicated 保留进程）。
- [ ] **Step 2** 双实例 ENet 冒烟（复用 `verify_net` 骨架）：host 以 `start_dedicated` 起，client 连 → 注册 → 开一局 → 收到私有手牌快照 → 走一步 RPC → 退出。
- [ ] **Step 3** 注册到 `tools/run_all_tests.sh`。

---

## 实现进度（2026-10-10）
- ✅ **Task 1** `Network` 中立 host 开关 + `start_dedicated` + `max_clients`（`verify_dedicated` 覆盖）。
- ✅ **Task 2（核心）** `GameState._on_host_started` dedicated 不占座；`request_start_match`/`request_next_match` 本地房主分支加 `host_is_player` 守卫。
- ✅ **Task 3** lobby 快照 `your_id`/`room_host`（随大厅 L1 完成；`dedicated` 字段未加，非必需）。
- ✅ **Task 4** headless 入口 `scripts/server_main.gd` + `scenes/server.tscn`（`-- --port`）。
- ✅ **Task 2（Step 3）abort/close 的 dedicated RPC 语义（已补）**：`request_abort_match`/`request_close_room` dedicated 下经 RPC 由房主（`host_seat`）触发；`server_abort_match`/`server_close_room` 加 `sender == host_seat` 校验；新增 `_end_room(code,message)`——广播中止 → 断开在座客户端 → 重置房间：**玩家-host** 关闭服务器连接、**dedicated 保留服务器进程**（无 zombie）。测试 `verify_dedicated`（18/18）。
- ✅ **Task 5/6** 文档已随 P1 更新；核心回归已跑。

## 部署手顺（占位，参数如后定）
> 架构/OS 默认 **Ubuntu 22.04 LTS + Ampere ARM(aarch64)**，回退 **Ubuntu 22.04 + x86_64**。Godot 与本地开发同小版本（4.6.x）。

1. **导出/运行**（二选一）：
   - A. 本地 macOS 交叉导出 Linux 包（导出预设 `Linux`，架构选 `arm64`/`x86_64`），上传 VPS，`./KongServer.x86_64 --headless -- --port 7007`；
   - B. VPS 装 **Godot 4.6 Linux arm64 编辑器**，`godot --headless --path . res://scenes/server.tscn -- --port 7007`。
2. **放行 UDP 7007**（两层）：
   - Oracle 控制台 **Security List / NSG**：Ingress `UDP 7007`（测试加 `7011`）。
   - 系统防火墙（Ubuntu）：`sudo ufw allow 7007/udp`（或 iptables/Oracle 镜像默认规则）。
3. **systemd 常驻**：`/etc/systemd/system/kong.service`（`ExecStart=… --headless …`、`Restart=always`、`User=`），`systemctl enable --now kong`。
4. 客户端：加入界面填 `VPS公网IP:7007`。
5. （待定）域名/静态 IP 确认、日志落盘、`MCPRuntimeProbe`/`AudioManager` 在 headless 下确认无副作用。

## 验收闸门
1. `verify_dedicated` 新增断言全绿。
2. 全量回归（`tools/run_all_tests.sh`）：`verify_protocol`/`verify_swap`/`verify_duel`/`verify_reconnect`/`verify_kongbaya`/`verify_economy`/`verify_shop`/`verify_relics`/`verify_card_skin` + 3D/UI 全套 + 双实例 `verify_net` 全绿（**双模式：玩家 host 行为逐字不变**）。
3. `git diff` 确认：规则/状态机/快照字段/`HiddenInfo`/`proxy_relay.gd`/`table3d.tscn`/2D 渲染文件零改动；`game_state.gd` 仅生命周期 + lobby 只读字段 + 房主任职解耦；`network.gd` 仅新增开关/入口。

## 非目标（P1 不做，留给后续）
- NAT 穿透（STUN/hole punching）、中继 SDR、WebRTC 传输。
- 账号体系、房间码、匹配队列、MMR/Elo、排行榜。
- Steam 集成、SDR、跨平台。
- 一进程多房 / 专用编排 / 反作弊加固。
