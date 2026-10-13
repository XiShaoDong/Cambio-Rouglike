# L1 大厅改造（Ready / 槽位 / 房主控制 / 动态 host_seat）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`).
> 相关：设计见 `docs/superpowers/specs/2026-10-10-lobby-redesign.md`；本任务是其中的 **L1**（无中心服务，可独立先做）。分支建议 `agent/feature-online`（从最新 main 拉）。
> 原则见 `docs/AI_AGENT_交接说明.md` §3/§9：先方案→确认→再动代码；不改规则/状态机/快照牌面投影/`HiddenInfo`；一次只解决一个可验证问题；用 headless 单测验证。

**Goal:** 把"一屏调试面板"式大厅改造成**两态大厅**（主菜单 / 房间），房间内含**固定槽位 + 每人 Ready + 房主控制（开始/踢在线/设置可见/解散）**；并把"房主"从写死座位 0 改为**动态 `host_seat`**（含离开转移）。

**Architecture:** 服务器权威。`ready` 与 `host_seat` 都存在 `GameState` 并随 **lobby 快照** 下发；客户端只发 `request_*`。`_broadcast_lobby` 改为**逐 peer** 下发（带 `your_id`），客户端据此判"我是不是房主"。UI 拆两态，房间态复用快照渲染槽位。

**Tech Stack:** Godot 4.6.x / GDScript；headless 单测（`verify_lobby`）。**不涉及**中心服务/随机码（那是 L2）。

## Global Constraints
- **不改** 规则/状态机/`Phase`/对局快照(`match_snapshot`)/`HiddenInfo`/牌面投影。
- 复用 **seat 身份**，**不**用 peer 判玩家；房主一律读 **`host_seat`**，**禁止**再写死 `0`。
- lobby 字段**只读附加**、**不进对局快照**（避免污染 `state_revision` 去重）。
- **不改** `scripts/net/*`（L1 不需要）、`scenes/ui/table3d.tscn`、`Robot.blend`、2D 渲染文件。
- 跨文件引用用 `preload` 常量；纯逻辑 headless 可测。
- **双模式语义**：LAN 玩家-host 行为保持可用。

## 决策记录（见 spec §4.7）
- **开始对局必须全员 Ready**；每局结束 ready **重置**。
- **房主 = 创建者 = 首个进入者**，动态 `host_seat`；**离开→转移**给 `turn_order` 下一在线玩家（**仅 LOBBY**；对局中掉线仍走"离线+暂停+重连"）。
- **解散 = 销毁/重置房间资源**（不做"只踢人、房间留着"）。

## 关键事实（现状锚点）
- `GameState._lobby_snapshot()`（`game_state.gd:1498`）、`_broadcast_lobby()`（:1504）目前**同一份**广播给所有人，`host_id: 0` 写死。
- `players[seat]` 结构见 `_add_player`（:279，字段含 seat/peer_id/token/name/color/cards/has_acted/offline/health/currency/wins/protected_slot）——**加 `ready:false`**。
- LOBBY 离开处理：`_on_peer_left`（:139）→ LOBBY 分支 `players.erase + turn_order.erase + _broadcast_lobby`。
- 房主校验写死 0：`_server_start_match`（:474）、`_server_next_match`（:537）、`_server_dev_eliminate`（:979）、`request_kick_offline`/`server_kick_offline`（:995/1003）、`request_abort_match`/`request_close_room`（:1051/1068 房主本地）。
- 客户端大厅 UI：`scripts/ui/lobby_view.gd`（`build()` 全量构建；`update_lobby()` 动态加 开始/解散/退出 按钮；`host_id` 用于 [房主] 标；`Network.is_host` 决定房主/客人分支）。
- `main.gd` 大厅成员：`lobby_panel`(VBox,:1153)、`lobby_members`(RichTextLabel)、`name_input`/`address_input`/`port_input`、`match_limit_spin`、`start_button`/`close_room_button`/`leave_room_button`、`latest_lobby`、`_button()`、`_set_status()`、`_show_toast()`；`lobby_updated` → `lobby.update_lobby`（:952）。
- 客户端"房主"UI：`game_view.gd:292`、`dev_tools.gd:37`、`main.gd:1326`（结算再来一局）用 `Network.is_host`。

---

### Task 1: 服务器权威 Ready + lobby 快照字段（`your_id`）
**Files:** Modify `scripts/core/game_state.gd`; Create `tests/verify_lobby.gd`/`.tscn`; Modify `tools/run_all_tests.sh`。

- [ ] **Step 1 写失败测试** `tests/verify_lobby.gd`（headless，驱动 autoload，参照 `tests/verify_reconnect.gd` 的驱动方式）：
  - `_server_set_ready(0,true)` 后 `players[0].ready == true` 且收到 lobby 广播（连接 `lobby_updated`）。
  - 非 LOBBY（改 `phase`）时 ready 被拒。
  - `_lobby_snapshot(0)` 含 `your_id==0`、`room_host==host_seat`；`players[].ready` 存在。
- [ ] **Step 2** `_add_player`（:279）在 `players[seat]` 字典里加 `"ready": false`。
- [ ] **Step 3** `_lobby_snapshot(viewer_seat := -1)`（:1498）：
  - `players` 每项加 `"ready"`；返回体加 `"your_id": viewer_seat`、`"room_host": host_seat`、保留 `"host_id": host_seat`、`"min_players"/"max_players"`（`match_limit` 可选加 `run_state.match_limit`）。
- [ ] **Step 4** `_broadcast_lobby()`（:1504）改**逐 peer**：
  ```
  for seat in turn_order:
      var peer := int(players[seat].peer_id)
      var snap := _lobby_snapshot(seat)
      if peer == 1: _receive_lobby.call_deferred(snap)   # 玩家-host 房主本人
      elif peer > 1: receive_lobby.rpc_id(peer, snap)
  ```
  （当前实现是"先 `_receive_lobby(lobby)` 再循环"；改成上面逐 peer。离线 peer<=0 跳过。）
- [ ] **Step 5** 新增 Ready 请求：
  ```
  func request_set_ready(on: bool) -> void:
      if multiplayer.is_server(): _server_set_ready(_peer_to_seat(1), on)
      else: server_set_ready.rpc_id(1, on)
  @rpc("any_peer","reliable")
  func server_set_ready(on: bool) -> void:
      if multiplayer.is_server(): _server_set_ready(_peer_to_seat(multiplayer.get_remote_sender_id()), on)
  func _server_set_ready(sender: int, on: bool) -> void:
      if phase != Phase.LOBBY or not players.has(sender): return
      players[sender].ready = on
      _broadcast_lobby()
  ```
- [ ] **Step 6** ready 重置：`_deal_new_match()`（:484）循环里 `players[seat].ready = false`。
- [ ] **Step 7** 跑 `res://tests/verify_lobby.tscn`（先过 Step 1）。

### Task 2: 动态 `host_seat`（去写死 0 + 离开转移）
**Files:** Modify `scripts/core/game_state.gd`。

- [ ] **Step 1** 新增 `var host_seat := 0`；`_reset_match()` 里 `host_seat = 0`。
- [ ] **Step 2** 首个进入者成为房主：`_add_player` 末尾，若 `players.size()==1`（或 `host_seat` 未定）→ `host_seat = seat`。（玩家-host：host 是首个 `_add_player(1,…)`=0；dedicated：首个客户端=0。）
- [ ] **Step 3** 把房主校验 `sender != 0`/`== 0` 全部改成 `sender != host_seat`/`== host_seat`：`_server_start_match`（:474）、`_server_next_match`（:537）、`_server_dev_eliminate`（:979）、`server_kick_offline`（:1003）。
- [ ] **Step 4** 房主离开转移：`_on_peer_left`（:139）**LOBBY 分支**里，若离开的 `seat == host_seat` → 从 `turn_order` 取下一个在线玩家设 `host_seat`；无人则保持（房间空，回收留给 P2）。
- [ ] **Step 5** `request_start_match`/`request_next_match` 服务器本地分支（:460/520）：玩家-host 用 `_peer_to_seat(1)`（=host_seat）不变；确认改用 `host_seat`（或保留 `_peer_to_seat(1)`，二者在玩家模式等价）。
- [ ] **Step 6** 断言（Task 6）：首个注册者 `host_seat==0`；`_server_start_match(host_seat,…)` 成功、非房主 → `NOT_HOST`；房主 `_on_peer_left` 后 `host_seat` 转移且新房主可开始。

### Task 3: 在线踢人 `request_kick`
**Files:** Modify `scripts/core/game_state.gd`。

- [ ] **Step 1** 新增：
  ```
  func request_kick(target_seat: int) -> void:
      if multiplayer.is_server(): _server_kick(_peer_to_seat(1), target_seat)
      else: server_kick.rpc_id(1, target_seat)
  @rpc("any_peer","reliable")
  func server_kick(target_seat: int) -> void:
      if multiplayer.is_server(): _server_kick(_peer_to_seat(multiplayer.get_remote_sender_id()), target_seat)
  func _server_kick(sender: int, target_seat: int) -> void:
      if phase != Phase.LOBBY: return
      if sender != host_seat: _reject(sender, RejectCode.NOT_HOST); return
      if target_seat == host_seat or not players.has(target_seat): return
      var peer := int(players[target_seat].peer_id)
      # 断开该 peer → 触发 _on_peer_left（LOBBY 分支移除座位 + 广播）
      if peer > 1 and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
          multiplayer.multiplayer_peer.disconnect_peer(peer)
  ```
  （断连后由 `_on_peer_left` 统一移除，避免两处改座位。）
- [ ] **Step 2** 断言：非房主踢 → `NOT_HOST`；踢房主 → 无效；踢后目标座位从快照消失。

### Task 4: 大厅 UI 两态重构 + 槽位 / Ready / 房主控制 / 设置可见
**Files:** Modify `scripts/ui/lobby_view.gd`; Modify `scripts/ui/main.gd`。

- [ ] **Step 1** `lobby_view.build()` 拆成两容器（都在 `lobby_panel` 下）：
  - `_menu`：昵称 + **创建房间** + **加入房间**（加入行：输入房间码 **或** 直连 `IP:端口`；L1 用直连，留"房间码"占位提示）+ 开发者双开（保留）。
  - `_room`：**房间信息行**（`IP:端口` + **复制** 按钮，`DisplayServer.clipboard_set`；L2 换成短码）+ **槽位列表** + 底部控制。
- [ ] **Step 2** 槽位渲染（`update_lobby`）：按 `lobby.max_players` 渲染 N 行；占用行显示 昵称 +（房主标）+（`ready`→"✔ 已准备"）；空行显示"等待加入…"。
- [ ] **Step 3** 控制区（依 `is_room_host = your_id == room_host`）：
  - 非房主：**准备/取消准备**（`GameState.request_set_ready(!mine)`）+ **退出房间**（`_leave_room`）。
  - 房主：**开始对局**（`disabled = players.size() < min_players or not all_ready`）+ **局数 SpinBox**（对其他成员**只读展示**）+ 每行**踢出**按钮（`GameState.request_kick(seat)`）+ **解散房间**（`GameState.request_close_room`，见 P1 语义）。
- [ ] **Step 4** `main.gd`：
  - 移除 `update_lobby` 里动态 new 按钮的旧逻辑（改由 `_room` 内固定按钮）。
  - `match_limit_spin` 对非房主：`editable=false` 但仍可见（展示当前值）。
  - `lobby_updated` 仍连 `lobby.update_lobby`。
- [ ] **Step 5** 保留 `_dev_launch_second`/`apply_dev_join`（开发用）。

### Task 5: 客户端房主判定改 `is_room_host`
**Files:** Modify `scripts/ui/game_view.gd`; `scripts/ui/dev_tools.gd`; `scripts/ui/main.gd`; `scripts/ui/lobby_view.gd`。

- [ ] **Step 1** 加统一助手（`main.gd`）：
  ```
  func is_room_host() -> bool:
      if not latest_lobby.is_empty():
          return int(latest_lobby.get("your_id", -1)) == int(latest_lobby.get("room_host", 0))
      return int(latest_state.get("viewer_id", -1)) == int(latest_state.get("room_host", latest_state.get("host_id", 0)))
  ```
- [ ] **Step 2** 替换 `Network.is_host`（仅"房主角色"用途处）：
  - `lobby_view.gd:153` → `main.is_room_host()`。
  - `game_view.gd:292`（暂停时房主按钮）→ `main.is_room_host()`。
  - `dev_tools.gd:37`（开发者面板 host-only）→ `main.is_room_host()`。
  - `main.gd:1326`（结算再来一局 host 位）→ `main.is_room_host()`。
- [ ] **Step 3** **保留** `Network.is_host` 用于"本进程是不是 ENet server"（`main.gd:29/1003/1037`、`game_state.gd:130`），**不改**。
- [ ] **Step 4** 断言：`your_id==room_host` 的端 `is_room_host()==true`；房主转移后跟随。

### Task 6: 文档 + 测试注册 + 回归
**Files:** Modify `docs/网络协议_V1.md`（lobby 快照加 `ready`/`your_id`/`room_host`，标注只读；新增 `set_ready`/`kick` 请求）、`docs/功能实现文档.md`、`docs/AI_AGENT_交接说明.md`；Modify `tools/run_all_tests.sh`（注册 `verify_lobby`）。

- [ ] **Step 1** 文档记录字段/请求（体现层，不碰对局规则）。
- [ ] **Step 2** `verify_lobby` 覆盖：ready 广播/重置、非 LOBBY 拒绝、`your_id`、房主转移、踢在线、开局门槛（未全 ready 拒）。
- [ ] **Step 3** 全量回归（见下）。

---

## 验收闸门
1. `verify_lobby` 新增断言全绿。
2. 全量回归 `tools/run_all_tests.sh`：`verify_protocol`/`verify_reconnect`/`verify_swap`/`verify_duel`/`verify_kongbaya`/`verify_economy`/`verify_shop`/`verify_relics`/`verify_series`/`verify_restart` + 3D/UI 全套 + 双实例 `verify_net` 全绿。
3. `git diff` 确认：规则/状态机/对局快照字段/`HiddenInfo`/`scripts/net/*`/`table3d.tscn`/2D 渲染零改动；`game_state.gd` 仅 lobby 只读字段 + ready/host_seat/kick 生命周期；UI 仅大厅相关。
4. 手动（可选）：本地双开跑通"建房→两人 ready→开始；房主离开→转移；踢人"。

## 非目标（L1 不做，留给 L2/P2）
- 随机短码 + 中心房间目录（L2 = P2）。
- 好友邀请 / 账号 / 匹配 / 房间生命周期自动回收（多房 P2）。
- 观战系统、房主转移的"对局中"版本。
