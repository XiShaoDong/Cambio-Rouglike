# P3：账号 + Steam（Identity & Friends）设计 v1

> **目的**：给玩家**持久身份**（跨房间/跨会话）并接入 **Steam**（认证 + 好友/邀请）。权威仍在你的 VPS；Steam 只做"身份与社交"。
> **前置**：P1（中立专用服务器）、P2（中心目录 + 输码联机，已有中心服务模式）。
> **现状**：只有 **seat_id（每局）** + **player_token（断线重连）**，**没有跨会话账号**。`run_state`（货币/生命/局数）是"一场系列赛内"的，不落库。

## 1. 目标与非目标

**目标**
1. **持久账号**：跨会话/跨房间的 `account_id` + 昵称 + 持久战绩（为 P4 ranked 铺路）。
2. **Steam 认证**：用 Steam 身份登录（SteamID + 拥有校验），把 `account_id ↔ steam_id` 绑定。
3. **好友/邀请**：Steam 好友列表 + 邀请进房（复用 P2 房间码/地址）。
4. 不改对局规则/快照牌面投影/`HiddenInfo`；座位仍用 `seat_id`。

**非目标**
- Ranked 匹配/MMR（P4）；反作弊加固（P5）。
- 跨平台非 Steam 登录的完整体系（P3 先设备匿名账号 + Steam 绑定）。

## 2. 分期（强烈建议按此顺序）

| 子阶段 | 内容 | 可本地/headless 自测 | 依赖 |
| --- | --- | --- | --- |
| **P3a 账号/身份** | 设备匿名账号（首启生成，存 `user://`）+ 账号服务（注册/昵称/校验）+ seat↔account 关联 + 持久战绩字段 | ✅ 能 | 无 |
| **P3b Steam 认证** | 客户端取 Steam auth ticket → 服务器经 **Steam Web API** 校验（app 拥有）→ 绑定 `account↔steam_id` | ❌ 需 SDK+Steam | Steamworks App ID + Web API Key + GodotSteam |
| **P3c 好友/邀请** | Steam 好友 + 邀请（把房间码/地址通过 Steam lobby 分享） | ❌ 需 Steam | 同上 |

> **P3a 独立于 Steam**，可先全测；**P3b/P3c 需要 Steamworks 资源**（账号/App ID/Web API Key）才能实现与联调。

## 3. 架构

```
客户端 ──(P3a) 登录/注册匿名账号──▶ 账号服务（中心，VPS）
      ──(P3b) Steam auth ticket ──▶ 你的服务器 ──▶ Steam Web API 校验 → 绑定
房间/对局：seat_id 不变；连接建立时把 seat 关联到 account_id
社交（P3c）：Steam 好友/邀请 → 分享房间码（P2）
```

### 3.1 账号服务（P3a）
- 复用"中心服务"模式（可并入 `server/directory` 或另起 `server/account`，见决策点）。
- 端点（草案）：`register_device`（首启匿名注册 → 返回 `account_id`+`device_secret`）、`login`、`set_name`、`get_profile`（含持久战绩）。
- **设备匿名**：`account_id`（随机）+ `device_secret`（校验用）存 `user://identity.cfg`（与现有 token 同级）。无密码、无邮箱（轻量）。
- **持久战绩**：`{ wins, matches, ... }` 落库（JSON/文件或 sqlite）；P4 的 MMR 在此扩展。

### 3.2 身份关联
- 客户端连接房间时带上 `account_id`（+ secret）；服务器把该连接/座位关联到账号（`players[seat].account_id`）。
- 快照可加只读 `players[].account_id`（或仅用于服务端统计，不下发）。**默认不下发**（隐私），内部用。

### 3.3 Steam 认证（P3b）
- 客户端（GodotSteam）：`getAuthSessionTicket()` → 把 `ticket` 发给你的服务器。
- 服务器：调 Steam Web API `ISteamUserAuth/AuthenticateUserTicket`（用你的 **Web API Key** + App ID）→ 得 `steamid` + `owner`；校验通过 → 把 `account_id ↔ steamid` 绑定。
- 客户端需**由 Steam 启动**（`steam_appid.txt` 或发布版）；开发期用 GodotSteam + 测试 App ID。

### 3.4 好友/邀请（P3c）
- Steam 好友列表 + `SteamMatchmaking` lobby/invite：把"房间码/服务器地址"塞进 lobby 数据，好友点邀请即加入（复用 P2 输码/解析）。
- 需要 Steam Overlay/回调循环（GodotSteam `run_callbacks`）。

## 4. 前置与依赖（决策点）
1. **Steamworks 合作账号**：你**是否已注册**并拿到 **App ID**？（注册费 $100，可回收）——决定 P3b/P3c 现在能否落地。
2. **Steam Web API Key**：用于服务端 ticket 校验（你 Steamworks 后台申请）。
3. **GodotSteam**：客户端插件（GDExtension，非官方；需与其 Godot 版本匹配）。
4. 账号服务承载：**并入 `server/directory`** vs **另起 `server/account`**。

## 5. 协议/数据（草案）
- 账号服务（HTTP/JSON，同 P2 风格）：`register_device`/`login`/`set_name`/`get_profile` → `{account_id, name, stats}`；错误码 `AUTH_FAILED`/`RATE_LIMITED`。
- 连接握手扩展：`request_register_player` 增加可选 `account_id`/`account_secret`（缺失=匿名/兼容旧客户端）。
- Steam 校验：服务器内部调用，不走游戏协议。

## 6. 测试
- **P3a**：账号服务纯逻辑单测（注册/登录/改昵称/战绩）；客户端 `AccountClient` 解析；关联 seat↔account（headless）。
- **P3b/P3c**：**无法 headless 自测**（需 Steam 环境）——用手动清单 + 开发期用测试 App ID；代码路径用桩（stub）单测解析/错误分支。
- 回归：P1/P2 + 既有全量不变。

## 7. 部署
- 账号服务与目录服务同机（VPS），各自端口；持久数据落盘（`/var/lib/kong/...`）。
- Steam Web API Key 存服务器环境变量（**不入库/不入仓**）。

## 8. 风险与坑
- Steam 相关**无法在本机自动化**：不要把 P3b/P3c 的成败绑在 CI 上。
- 隐私：`steam_id`/`account_id` 默认不下发快照。
- 兼容：老客户端无账号 → 仍可匿名加入（不破坏 P2）。
- GodotSteam 版本耦合 Godot 4.6；需确认插件版本。
