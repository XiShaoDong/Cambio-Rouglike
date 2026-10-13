# P2：中心房间服务 + 随机短码 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`).
> 设计见 `docs/superpowers/specs/2026-10-13-p2-room-directory-design.md`（本计划是其实现拆解）。分支 `agent/feature-online`。
> 原则见 `docs/AI_AGENT_交接说明.md` §3/§9：先方案→确认→再动代码；不改对局规则/快照/`HiddenInfo`；一次只解决一个可验证问题。

**Goal:** 建房得**随机短码**、输码加入。中心**目录服务（Directory，HTTP/JSON 独立服务）**负责码↔地址登记；客户端接入（输码加入 / 建房显码 / 心跳 / 关房）。**不改游戏规则/对局快照。**

**Architecture（拍板：目录=A 独立 HTTP/JSON 服务）**
- 目录服务：Python 标准库 `http.server`（零依赖），内存 `code → {host, port, mode, max_players, last_seen}`；端点 `create/heartbeat/close/join`。
- **房间地址 = 请求方的公网源 IP**（目录从 HTTP 连接读 `client_address`）——宿主**无需自探测公网 IP**；`port` 由宿主上报。dedicated=服务器上报自身端口；player-host=房主上报其游戏端口（需端口可达）。
- 客户端：Godot `HTTPRequest` 调目录；游戏流量仍 ENet 直连。
- 生命周期：码 **TTL 30min**（仅限"用码加入"）；心跳超时（30s）回收码；空房 60s（宿主侧 close）；房主离开转移/解散重置沿用 L1/P1。

**Tech Stack:** Python 3（stdlib，服务端）+ Godot 4.6/GDScript（客户端接入）。

## Global Constraints
- 不改对局规则/状态机/`match_snapshot` 字段/`HiddenInfo`。
- 目录服务**独立进程**，不接触牌局数据；与游戏仅"码↔地址"。
- 客户端接入只新增**大厅/连接层**（`DirectoryClient` + 主菜单/建房流程），复用 L1 大厅两态与 P1 `Network`。
- 目录地址是**可配置项**（`Settings`），VPS 信息留作部署参数。

## 实现进度（2026-10-13）
- ✅ **P2a**：目录服务 `server/directory/directory.py`（`DirectoryStore` + `RateLimiter` + HTTP 端点）+ `test_directory.py`（13/13）+ `README.md`/systemd 模板；curl 冒烟通过。
- ✅ **P2b**：`DirectoryClient`（`scripts/net/directory_client.gd`，含纯函数 `parse_response`）+ 设置 `network.directory_url`；大厅"加入房间"输码加入；建房登记/显码/复制/心跳/关房；dedicated `server_main.gd` 登记。测试 `verify_directory_client`（9/9，含本地 Python 目录集成）。
- ⏳ **P2c 空房回收**：目录侧心跳超时/TTL 回收已具备；**房间对象级空房回收/多房归 P2d**（单房下不适用）。
- ✅ **B4 文档/设置**：协议 §8 / 功能 / 交接已更新；设置菜单加"目录地址"输入项（`Settings.network.directory_url`），`main.set_directory_url()` 即时生效。
- ✅ **端到端验证**：`tests/verify_e2e_code.gd`（目录 + 双实例）——host 建房得码写入 `user://e2e_code.txt`、client 读码→目录查地址→连接→同房；本地实测双方 PASS。已接入 `run_all_tests.sh`（"P2 输码联机 E2E"，需 python3）。

## 关键事实（现状锚点）
- `Network.join_game(address, profile, port)` 直连；`Network.host_game(...)`/`start_dedicated(...)`（P1）。
- L1 大厅：`lobby_view.gd`（主菜单/房间两态；"房间地址"位 + 复制）、`main.latest_lobby`、`main.is_room_host()`。
- `ServerMain`（`scenes/server.tscn`）= headless 专用服务器入口（P1）。
- `Settings`（`scripts/core/settings.gd`）可加配置项；`loc.gd` 文案表。

---

## 阶段 P2a：目录服务（Python，独立，可脱离游戏单测）

### Task A1：目录服务骨架 + 码生成 + 核心端点
**Files:** Create `server/directory/directory.py`; Create `server/directory/test_directory.py`; Create `server/directory/README.md`.

- [ ] **Step 1 纯逻辑先写测试** `test_directory.py`（可直接 `python3 test_directory.py` 断言，或 pytest）：
  - 码生成：6 位 Crockford base32（字符集 `0123456789ABCDEFGHJKMNPQRSTVWXYZ`）；N 次生成全部唯一（无碰撞重试生效）。
  - `create_room(port, mode, max_players, host)` → 返回 `code`；存储 `host/port/mode/max_players/last_seen`。
  - `join_room(code)` → 命中返回 `{host, port, mode}`；未命中 → `ROOM_NOT_FOUND`。
  - `close_room(code)` → 之后 `join_room` 失败。
- [ ] **Step 2** 实现 `directory.py`：内存字典 + 锁（threading）；`DirectoryStore` 纯逻辑类（与 HTTP 解耦，便于单测）+ `http.server` 处理器。
  - `DirectoryStore.create(host, port, mode, max_players) -> code`
  - `DirectoryStore.join(code) -> dict|None`
  - `DirectoryStore.heartbeat(code) -> bool`
  - `DirectoryStore.close(code) -> bool`
  - `DirectoryStore.sweep(now) -> removed`（TTL）
- [ ] **Step 3** HTTP 路由：`POST /create_room`、`POST /heartbeat`、`POST /close_room`、`POST /join_room`；JSON 请求/响应；**host 取 `self.client_address[0]`**（公网源 IP）。
- [ ] **Step 4** 跑 `test_directory.py` 全绿。

### Task A2：TTL + 心跳超时回收 + 限速
**Files:** Modify `server/directory/directory.py`; `test_directory.py`.

- [ ] **Step 1** 测试：`now` 注入；无心跳 TTL（默认 30s）后 `join` 失败；`heartbeat` 续命；码 **TTL 30min** 后失效（与心跳区分：心跳=宿活在，TTL=码最长寿命）。
- [ ] **Step 2** 实现：`sweep(now)` 清理超时房间；`/join_room` 前 sweep；`heartbeat` 更新 `last_seen`；`created` 用于 TTL。
- [ ] **Step 3** 限速：按源 IP 记录请求时间窗（如 10 次/分）；超限 → `RATE_LIMITED`；测试覆盖。
- [ ] **Step 4** 跑测试全绿。

### Task A3：运行与部署
**Files:** Create `server/directory/kong-directory.service`（systemd 模板，占位）; Modify `README.md`.

- [ ] **Step 1** CLI/env：`--port`（默认 8080）、`--ttl`、`--heartbeat-timeout`、`--rate`；`argparse`。
- [ ] **Step 2** README：运行方法、systemd、**两层防火墙放行 TCP 8080**、VPS 参数待填。
- [ ] **Step 3** 手动冒烟：本地 `python3 directory.py --port 8080` + `curl` create/join/heartbeat/close。

---

## 阶段 P2b：客户端接入（Godot）

### Task B1：`DirectoryClient` + 设置项
**Files:** Create `scripts/net/directory_client.gd`; Modify `scripts/core/settings.gd`（默认 `network/directory_url`）; `scripts/core/loc.gd`.

- [ ] **Step 1** `DirectoryClient`（Node 或 RefCounted + 内部 `HTTPRequest`）：`create_room(port, mode, cb)`、`join_room(code, cb)`、`heartbeat(code, cb)`、`close_room(code, cb)`；异步回调（成功/失败/错误码）；超时处理。
- [ ] **Step 2** `Settings` 增 `network.directory_url`（默认空，指向 VPS）。设置菜单可加一行（可选）。
- [ ] **Step 3** 单测（headless）：用一个**本地假目录**（起一个最小 HTTP 或被替换的 stub）验证 client 解析成功/失败 JSON；或对 `directory.py` 起的实例做集成（可跳过网络，测 JSON 解析纯函数）。

### Task B2：输入房间码加入
**Files:** Modify `scripts/ui/lobby_view.gd`（主菜单"加入房间"）; `scripts/ui/main.gd`（转发/回调）。

- [ ] **Step 1** 主菜单"加入房间"：`address_input` 改为**房间码输入**（label 改"房间码"；保留"直连 IP"作为折叠高级项，可选）。
- [ ] **Step 2** 点击加入 → `DirectoryClient.join_room(code)` → 成功 → `Network.join_game(host, port)`；失败 → toast（"房间不存在或已过期"/"请求过多"）。
- [ ] **Step 3** 无 `directory_url` 或目录不可达 → 明确提示（回退提示可输 IP 直连）。

### Task B3：建房/宿主登记 + 显码 + 心跳 + 关房
**Files:** Modify `scripts/ui/lobby_view.gd`/`main.gd`（player-host 登记）; Modify `scripts/server_main.gd`（dedicated 登记）。

- [ ] **Step 1 玩家-host**：`Network.host_game` 成功（`host_started`）后 → `DirectoryClient.create_room(port, "player_host", MAX)` → 得 `code` 存 `main.room_code`；房间态"房间码"位显示 + 复制。
- [ ] **Step 2 dedicated**：`ServerMain._ready` `start_dedicated(port)` 后 → `create_room(port, "dedicated", MAX)` → `print` 码（日志）；Timer 心跳；进程退出 close。
- [ ] **Step 3 心跳**：`main` 侧 Timer（10s）对当前 `room_code` 发 `heartbeat`；房间关闭（解散/中止/退出） → `close_room`。
- [ ] **Step 4** 房间态 UI：复用 L1 的"房间地址/复制"，改为显示**房间码**（`main.room_code`）。

### Task B4：文案/设置/文档
**Files:** `loc.gd`; `docs/网络协议_V1.md`（新增"目录服务协议"章节）; `docs/功能实现文档.md`; `docs/AI_AGENT_交接说明.md`.

- [ ] **Step 1** 新增文案（房间码、目录不可达等）；设置项"目录地址"。
- [ ] **Step 2** 协议文档记录目录端点/字段/错误码（独立于游戏 ENet 协议）。
- [ ] **Step 3** 功能/交接文档记录 P2。

---

## 阶段 P2c：生命周期收尾
- [ ] **C1 空房回收**：宿主侧统计在线客户端，0 人满 60s → `close_room`（player-host 回大厅；dedicated 重置房间/保留进程）。
- [ ] **C2（可选）多房/房间列表**：dedicated 一进程多房 或 一房一进程 + 目录 `list_rooms`。**后置。**

## 测试与验收
1. **目录单测**（`test_directory.py`）：码唯一/碰撞、create/join/close、TTL、心跳超时、限速。
2. **客户端单测**：`DirectoryClient` JSON 解析/错误码（假目录）；输码→地址→连接（假目录）。
3. **本地 E2E**：起 `directory.py` + `server.tscn`(dedicated) + 两个 Godot 客户端，客户端 A 建房得码、B 输码加入、开一局。
4. **回归**：P1/L1 + 既有全量（`verify_dedicated`/`verify_lobby`/`verify_net` 等）。

## 部署（参数待填，届时你提供 VPS 信息）
- VPS 上常驻：**目录服务**（TCP 8080）+ **专用服务器**（UDP 7007）。
- 两层防火墙：云 Security List + 系统 ufw 放行 TCP 8080 + UDP 7007。
- 客户端设置 `directory_url = http://<VPS公网IP>:8080`。
- 待填：实例架构（x86_64/ARM）、OS 版本、公网 IP、域名(可选)、SSH 方式。

## 非目标
- NAT 穿透/中继、账号/Steam、ranked、多房编排最优形态、跨平台。
