# P3b/P3c：Steam 认证 + 好友/邀请（桩先行）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`).
> 设计见 `docs/superpowers/specs/2026-10-13-p3-account-steam-design.md`。分支 `agent/feature-online`。
> **前提**：暂无 Steamworks 资源（App ID/Web API Key）→ **桩先行**：把 Steam 相关做成**可替换接口**，用 Mock 跑测试；真机联调待资源到位，**只换实现、不动上层**。

**Goal:** 让上层逻辑（账号绑定 Steam、好友邀请进房）**现在就完整可测**：服务端用 `MockVerifier` 顶替 Steam 校验，客户端用 `SteamBridge` 在无 GodotSteam 时走桩。

**Architecture**
- **服务端**：`SteamVerifier` 接口 + `SteamWebApiVerifier`（真，调 Steam Web API，需 Web API Key）+ `MockVerifier`（`ticket = "mock:<steamid>"` 即通过）。账号服务端点 `POST /steam_auth {account_id, secret, ticket}` → 校验 → `bind_steam(account_id, steamid)`。
- **客户端**：`SteamBridge`（检测 `Engine.has_singleton("Steam")`/GodotSteam；有则真实现，无则桩：`available()=false`）+ `AccountClient.steam_auth()`；好友/邀请同封装。
- **不硬依赖 GodotSteam**：未装插件也能编译/运行（走桩）。

**Tech Stack:** Python 3（stdlib）+ Godot 4.6/GDScript。

## Global Constraints
- 不改对局规则/`match_snapshot` 牌面投影/`HiddenInfo`。
- `steam_id` 默认不下发快照；Web API Key **存环境变量/参数，不入库/不入仓**。
- 无 Steam 资源时**全流程走桩**，测试 headless 全绿。

---

## 实现进度（2026-10-14）
- ✅ **S1**：`server/account/steam.py`（`MockVerifier`/`SteamWebApiVerifier`）+ `account.py` `bind_steam` + `/steam_auth` + `--steam-webapi-key/--steam-appid`；`test_account.py` 21/21；curl（mock）通过。
- ✅ **S2**：`scripts/net/steam_bridge.gd`（检测 GodotSteam，未装走桩）+ `AccountClient.steam_auth` + `main._try_steam_bind()`。
- ✅ **S3**：房间态（房主）"邀请好友"按钮 → 桩下提示"Steam 未启用"（`main._on_invite_friends`）。
- ✅ **S4**：协议 §10 / 功能 / 交接 已更新；runner 加 `steam_stub`。
- ⏸ **真机联调**：待 Steamworks 资源（App ID/Web API Key + GodotSteam），只换实现。

### Task S1: 服务端校验抽象 + `/steam_auth` + 绑定
**Files:** Create `server/account/steam.py`; Modify `server/account/account.py`; Modify `server/account/test_account.py`; `server/account/README.md`.

- [ ] **Step 1 测试** `test_account.py` 增：
  - `MockVerifier.verify("mock:76561198000000000")` → `{steamid, owner:true}`；非 `mock:` → None。
  - `AccountStore.bind_steam(aid, secret, steamid)` → True；`get_profile` 主体含 `steam_id`（仅服务端/绑定接口返回；**不下发到游戏**）。
  - 端点 `/steam_auth {account_id,secret,ticket}` → mock 票据 → `{ok:true, steam_id}`；错 secret → `AUTH_FAILED`；坏票据 → `STEAM_AUTH_FAILED`。
- [ ] **Step 2** `steam.py`：`SteamVerifier` 基类；`MockVerifier`；`SteamWebApiVerifier(web_api_key, app_id)`（`urllib` POST `ISteamUserAuth/AuthenticateUserTicket/v1/`，解析 `response.params.{result,steamid,owner}`）。
- [ ] **Step 3** `account.py`：`AccountStore.bind_steam`；`Handler.verifier`（按 `--steam-webapi-key` 选 真/Mock）；`/steam_auth` 路由；CLI `--steam-webapi-key`/`--steam-appid`。
- [ ] **Step 4** 跑 `test_account.py` 全绿。

### Task S2: 客户端 `SteamBridge` + `AccountClient.steam_auth`
**Files:** Create `scripts/net/steam_bridge.gd`; Modify `scripts/net/account_client.gd`; `scripts/core/settings.gd`.

- [ ] **Step 1** `SteamBridge`（Node）：`available()`（检测 GodotSteam 单例/`Engine.has_singleton`）；桩实现 `get_auth_ticket(cb)`→空、`get_friends(cb)`→[]、`invite_friend(...)`→false、`poll()`（真实现时 `run_callbacks`）。**不硬依赖插件**。
- [ ] **Step 2** `AccountClient.steam_auth(account_id, secret, ticket, cb)` → `POST /steam_auth`。
- [ ] **Step 3** main：账号就绪后，若 `SteamBridge.available()` → 取票据 → `steam_auth` 绑定；无则忽略（桩）。
- [ ] **Step 4** 单测：`SteamBridge` 桩 `available()==false`、`get_auth_ticket` 回调空；`AccountClient.parse_response` 覆盖 `STEAM_AUTH_FAILED`。

### Task S3: 好友/邀请（桩先行）
**Files:** Modify `scripts/ui/lobby_view.gd`（房间态加"邀请好友"）+`main.gd`; `scripts/net/steam_bridge.gd`.

- [ ] **Step 1** 房间态（房主）加**邀请好友**按钮：`SteamBridge.available()`→列出好友/发邀请（把 `room_code` 带入）；不可用→toast"Steam 未启用"。
- [ ] **Step 2** 接收邀请：`SteamBridge` 事件 → 自动/提示加入（用房间码走 P2）。
- [ ] **Step 3** 单测：桩下按钮走"未启用"分支（不崩）。

### Task S4: 文档
**Files:** `docs/网络协议_V1.md`（§10 Steam 认证，`/steam_auth`）、`docs/功能实现文档.md`、`docs/AI_AGENT_交接说明.md`。

---

## 真机联调（待 Steamworks 资源）
1. 取得 **App ID + Web API Key**；`steam_appid.txt`/发布配置；装 **GodotSteam**（匹配 Godot 4.6）。
2. 服务端以 `--steam-webapi-key <KEY> --steam-appid <ID>` 启动（切换为真校验）。
3. 客户端由 Steam 启动 → 取票据 → `/steam_auth` 真校验 → 绑定。
4. 好友/邀请走 GodotSteam 真实现（S2/S3 已留接口，仅替换桩）。

## 测试与验收
- 服务端 `test_account.py`（含 mock steam）；客户端 `verify_account_client`/`verify_steam_stub`。
- 回归：P1/P2/P3a + 既有全量不变。

## 非目标
- 真 Steam 往返（待资源）；Steam 成就/云存档；跨平台账号。
