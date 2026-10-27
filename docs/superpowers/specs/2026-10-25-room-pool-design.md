# 房间池（Room Pool）设计 v1

> **目的**：让跨网络的玩家也能"点创建房间 → 立刻拿到房间码 → 分享加入"，且**不依赖房主的公网可达性**（不碰 NAT/端口转发）。做法是在 VPS 上常驻一组专用服务器实例组成**房间池**，由现有目录服务分配空闲实例并下发房间码。
> **前置**：P1（dedicated 中立服务器）、P2（目录 + 随机短码）、P2 收尾（`_end_room` 在 dedicated 下保留进程并重置房间）均已完成。
> **权威不变**：对局规则、状态机、快照投影、`HiddenInfo`、RPC 协议**零改动**；本设计只加"目录的池分配"与"建/回收流程"。

## 1. 背景与目标

现状两种宿主模式各有硬伤：

- **player-host**：朋友直连房主 IP，家庭 NAT 下入站 UDP 7007 被丢，跨网络不可用（需端口转发）。
- **dedicated**：VPS 上可直达，但一个进程只服务一间房，且码只出现在服务器日志里，玩家点不到"创建房间"。

**目标**

1. **创建者点一下就拿到码**：客户端向目录申请 → 目录挑一个空闲实例 → 返回 `{code, host, port}` → 客户端直连并成为房主（dedicated 首个连入者 = seat0 = 房主）。
2. **固定 4 房常驻池**，房间结束回收复用；池满明确提示"稍后再试"。
3. **保留局域网模式**：创建时可选"在线房间 / 局域网房间"，本地 host 完全保留。
4. 断线重连、房主转移、Ready、系列赛等既有能力不受影响。

**非目标**

- 不做 NAT 穿透/中继/打洞（池模式已绕开）。
- 不做按需 spawn（本期固定池；接口预留，见 §11）。
- 不做匹配/排队/一进程多房。
- 不改 RPC、快照、规则。

## 2. 架构

```
 创建者 A                                   朋友 B
   │ 1. POST /allocate_room                     │
   │ 2. 拿 {code, host, port}                    │
   │ 3. POST /join_room(code)                    │
   │ 4. ENet 直连 host:port ─────────────┐       │
   ▼                                     ▼       ▼
 ┌──────────── 目录服务（VPS :8080）────────────┐
 │ code → {host, port, mode, state, 心跳, 预约}  │
 │ state: idle | reserved | in_use              │
 └──────────────────────────────────────────────┘
        ▲ 启动登记 idle / 心跳 / 结束换码
        │
   ┌────┴─────────────────────────────┐
   │ 房间池：4 个 dedicated Godot 实例  │
   │ UDP 7007 / 7008 / 7009 / 7010    │
   └──────────────────────────────────┘
```

### 2.1 实例状态机

```
idle ──allocate──▶ reserved ──join_room──▶ in_use ──房间结束──▶ idle(新码)
                      │
                      └── 30s 无人连入 ──▶ idle（保留原码）
```

- `idle`：可被分配，**不可加入**（`join_room` 返回 `ROOM_NOT_FOUND`，防止陌生人闯进空实例当房主）。
- `reserved`：已被某次创建占用，30s 内必须有人连入（调用 `join_room` 即转 `in_use`）。
- `in_use`：正常房间；解散/中止后实例自动重新登记为 `idle` 并换新码。
- 码在**实例本轮存活期内固定**；房间结束重新登记时才换新码，旧码立即失效。

### 2.2 时序（创建 → 加入）

1. 4 个实例启动：`--pool` → `POST /create_room {port, mode:"dedicated", state:"idle"}` → 各自拿到码并心跳。
2. A 点"在线房间" → `POST /allocate_room {}` → 目录选最久未分配的 `idle`，置 `reserved`（30s），返回 `{code, host, port}`。
3. A 调 `POST /join_room {code}`：目录把该房间置 `in_use`，返回 `{host, port}`（顺带校验，避免分配后码失效）。
4. A `Network.join_game(host, port)` → 首个连入者 = seat0 = 房主。
5. B 用码加入 → `join_room` 命中 → 直连同一地址。
6. 房主解散/中止 → 实例 `_end_room` → `POST /close_room` → `POST /create_room(state:"idle")` → 新码 → 回到池。

## 3. 目录服务改动（`server/directory/directory.py`）

复用现有码生成（6 位 Crockford base32）、TTL、心跳、限速；只增加池状态与分配端点。

| 接口 | 载荷 | 响应 | 说明 |
| --- | --- | --- | --- |
| `POST /create_room` | `{port, mode, max_players, state?, host?, code?}` | `{code, expires_in}` | 新增可选 `state`，默认 `in_use`；池实例传 `idle` |
| `POST /allocate_room` | `{}` | `{code, host, port}` 或 `{error:"NO_ROOM"}` | **新增**：选 `idle` 中最久未分配的，置 `reserved` |
| `POST /join_room` | `{code}` | `{host, port, mode}` 或 `{error:"ROOM_NOT_FOUND"}` | 仅 `reserved`/`in_use` 可加入；命中后置 `in_use` |
| `POST /heartbeat` | `{code}` | `{ok}` | 不变；`ok=false` 表示码已失效，实例需重登记 |
| `POST /close_room` | `{code}` | `{ok}` | 不变；实例结束房间时调用 |
| `GET /health` | — | `{ok, rooms, idle, busy}` | 增加池计数，便于运维观测 |

状态规则：

- `allocate_room`：加锁 → `sweep` → 从 `state=="idle"` 中按 `last_alloc` 升序取第一个 → `state="reserved"`、`reserved_at=now`、`last_alloc=now`。
- `sweep` 增加：`state=="reserved"` 且 `now - reserved_at > 30` → `state="idle"`（码保留）。
- `join_room`：命中且状态不是 `idle` → `state="in_use"`、清 `reserved_at`。
- 原有"心跳超时 30s / 码 TTL 30min"逻辑不变（心跳会续期，常驻实例不会过期）。
- 新增错误码 `NO_ROOM`（池满）；`ROOM_NOT_FOUND` 同时覆盖"码不存在"和"实例空闲"。

限速：`/allocate_room` 与 `/join_room` 共用现有按 IP 限速（10 次/分钟）。**建议默认提到 30 次/分钟**（同一 NAT 后多人同时建房/加入容易被误伤），仍可通过 `--rate` 配置。

## 4. 专用服务器改动

| 文件 | 改动 |
| --- | --- |
| `scripts/server_main.gd` | 新增 `--pool`；池模式下以 `state="idle"` 登记、保存 `room_code`、打印；订阅 `GameState.room_ended` 做"关房 → 重新登记 idle（新码）"；心跳失败时按当前是否有玩家重登记 |
| `scripts/net/pool_registrar.gd` | **新增**（`RefCounted`）：池生命周期薄封装——持有 `code/state`，注入 `create/close/heartbeat` 回调；纯状态转换可 headless 单测（不依赖 HTTP） |
| `scripts/core/game_state.gd` | 新增信号 `room_ended`，在 `_end_room()` 末尾 emit（仅 dedicated 需要消费；玩家-host 无副作用） |

要点：

- 不改 `_end_room` 行为（仍保留进程、重置房间），只是**多一个信号**让入口层通知目录。
- 换码失败（目录不可达）不阻塞对局：实例继续存活，日志告警，下次心跳/结束再重试。
- 玩家-host 的 `main._on_directory_host_started` 保留（局域网模式若配了目录仍会登记拿码，行为不变）。

## 5. 客户端改动

| 位置 | 改动 |
| --- | --- |
| `scripts/net/directory_client.gd` | 新增 `allocate_room(cb)` |
| `scripts/ui/lobby_view.gd` `host_game()` | 改为弹窗二选一：**在线房间**（走池）/ **局域网房间**（现有 `Network.host_game`）。两套主菜单（宽屏/紧凑）共用该入口，一处改动即覆盖 |
| `scripts/ui/lobby_view.gd` `join_by_code()` | 加入成功后把 `main.room_code` 设为所用码（现在只有房主有码，加入者会退回显示 IP:端口） |
| `scripts/ui/main.gd` | 新增 `create_online_room()`：`allocate_room` → `join_room` → `Network.join_game`；失败分别提示"服务器已满，请稍后再试"/"无法连接房间服务" |

细节：

- 在线创建**不再**调用 `Network.host_game`，因此不会触发 `_on_directory_host_started`（不会重复登记）。
- 首个连入者即房主：沿用 dedicated 的 `host_seat` 语义，无需新协议。
- 创建者拿到码后照常走房间界面（中央房间码卡），可复制转发。

## 6. 部署

- `kong-directory.service` 不变（可调 `--rate 30`）。
- 新增 systemd 模板 `deploy/kong-room@.service`：

```ini
[Unit]
Description=KONG room instance %i
After=network-online.target kong-directory.service
Wants=network-online.target

[Service]
User=kong
WorkingDirectory=/home/kong/kong
ExecStart=/usr/local/bin/godot --headless --path /home/kong/kong res://scenes/server.tscn -- \
  --port %i --pool --directory http://127.0.0.1:8080 --advertise <VPS公网IP>
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
```

- 启用：`systemctl enable --now kong-room@{7007,7008,7009,7010}`
- VPS 安全组/防火墙放行 UDP `7007-7010`；目录 TCP 8080 已有。
- VPS 公网直达，**无需任何端口转发**。

## 7. 测试

**目录单测**（`server/directory/test_directory.py` 扩展）

- `create_room(state="idle")` → 房间存在且不可 join（`ROOM_NOT_FOUND`）
- `allocate_room` 选中 idle、置 reserved、返回码与地址
- 无 idle → `NO_ROOM`
- reserved 30s 超时 → 回 idle、码不变、可再次分配
- `join_room` 命中 reserved → `in_use`；再 `allocate` 不会选到它
- `close_room` 后不可 join；重新 `create_room` 得新码、旧码失效
- `/health` 返回 idle/busy 计数

**客户端单测**（`tests/verify_directory_client.gd` 扩展）

- `allocate_room` 成功解析 `{code, host, port}`
- `NO_ROOM` → `ok=false` 且 error 正确

**E2E**（新增 `tests/verify_room_pool_e2e.gd` + `.tscn`，沿用 `verify_e2e_code` 的双进程角色模式）

- 起本地目录 + 一个 `--pool` 实例（测试端口）
- `-role creator`：`allocate_room` → `join_room` → 连接 → 写码到 `user://pool_code.txt` → 断言成为房主（`room_host == your_id`）
- `-role joiner`：读码 → `join_room` → 连接 → 断言两人同房
- 结束后断言目录 `/health` 的 busy 归零、实例换码（可选）

**回归**：`tools/run_all_tests.sh`（重点 `verify_protocol`、`verify_dedicated`、`verify_lobby`、`verify_reconnect`、`verify_net`）。

## 8. 风险与取舍

| 风险 | 说明 | 处理 |
| --- | --- | --- |
| 上限 4 房 | 同时最多 4 间在线房 | 池大小可配（systemd 启用几个实例）；满了提示稍后再试 |
| 预约 30s | 分配后 30s 未连入，实例回池 | 客户端拿到码后立即连接（正常 <1s）；超时可重试创建 |
| **僵尸房占用槽位** | 房主直接关掉进程（不点解散）时，dedicated 保留房间等重连，实例会一直 `in_use` | 本期按约定不做"全员离线超时回收"；运维可用重启实例兜底。后续可加"0 在线玩家 N 分钟后自动 `_end_room`"（默认关闭） |
| 目录单点 | 目录挂掉则无法创建（已在进行的房间不受影响） | 目录已有 systemd + 重启策略；实例心跳失败会自动重登记 |
| 码随房间轮换 | 房间结束后旧码立即失效 | 符合"码=一次性邀请"的直觉；已在房内的人不受影响 |
| 同 IP 限速 | 同一 NAT 后多人同时操作可能触发限速 | 默认提到 30 次/分钟，可配置 |

## 9. 分期

- **P1（本期）**：固定 4 实例 + 目录分配 + 客户端在线/局域网二选一 + 回收换码 + 测试。
- **P2（后续）**：按需 spawn（`idle` 不足时由 supervisor 拉起新实例）、空闲实例缩容。
- **P3（后续，可选）**：僵尸房自动回收（0 在线玩家超时）、房间列表/排队。
