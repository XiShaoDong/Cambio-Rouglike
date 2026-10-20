# KONG 开局发牌动画 + 重开按钮 设计 v1

> **目的**：① **开局发牌动画**（3D，复用 `CardFly`）：每局开始时从中央抽牌堆一张张飞到四个座位手牌区（**一个玩家一个玩家**：seat 升序、从房主 seat0 开始，每人的 `HAND_SIZE` 张发完再下一个），**按住空格 2 倍速**；② **重开按钮**（仅房主）：圆形 `↻`，点击在**提示板**（同 J/Q 确认）弹「是否重开 [确认][取消]」，确认后**重开本局**（保留系列赛/经济/生命），全员重新发牌。
> **纯表现层 + 一个服务器 RPC**：发牌动画纯客户端；重开新增服务器 RPC `request_restart_match`（复用 `_deal_new_match`，不改规则/快照结构）。

## 1. 目标与非目标
**目标**
1. **发牌动画（3D）**：客户端检测快照 `match_id` 变化 → 播发牌：中央 `deck` → 每席手牌槽，**一个玩家一个玩家**（seat 升序从房主开始；每人的手牌槽发完再下一个），每张间隔 `0.15s`。
   - 实现：发牌开始把所有目标槽标为"在途"（复用 `_anim_slots`，`render` 跳过）；逐张用 `CardFly`（背面、`{}`）从 `center_xform("deck")` 飞到 `slot_xform(seat,slot)`；每张落地 → 撤销该槽标记 + `_refresh()`（露出该卡）。
   - **按住空格 → 2 倍速**（间隔 ÷2，松手恢复）；发牌**不锁**操作；纯 3D（2D 不做）。
2. **重开按钮（仅房主）**：圆形 `↻`。3D 放**牌桌右角**可拾取圆盘（`kind:"hud", action:"restart"`，仅房主视角可见）；2D 放**房主界面右侧**圆形按钮。
3. **重开确认**：点击 `↻` → **提示板**（3D `hint3d` / 2D `HintActions`）显示「是否重开 [确认][取消]」（与 J/Q 同一处，互斥：确认板打开时当前其它提示让位）；确认 → `request_restart_match`；取消 → 收起。
4. **重开本局**：服务器 `_server_restart_match`（仅房主、`phase != LOBBY`、人数 ≥ `MIN_PLAYERS`）→ `_deal_new_match()`：新 `match_id`、重发手牌、回 `INITIAL_PEEK`；**保留** `match_number`/货币/生命/系列赛/`run_state`（护盾遗物等按局钩子照常）。

**非目标**
- 不改规则判定/协议字段语义/`HiddenInfo`/快照结构（仅新增一个 RPC）。
- 不做 2D 发牌动画；不改结算页「再来一局」。

## 2. 服务器（`scripts/core/game_state.gd`）
- `func request_restart_match(action_id := "")`：房主走 `_server_restart_match(_peer_to_seat(1), action_id)`，否则 `server_restart_match.rpc_id(1, action_id)`。
- `@rpc("any_peer","reliable") func server_restart_match(action_id)` → `_server_restart_match(_peer_to_seat(sender), action_id)`。
- `func _server_restart_match(sender, action_id)`：`phase == LOBBY` → `ROOM_NOT_OPEN`；`sender != 0` → `NOT_HOST`；`players.size() < MIN_PLAYERS` → `NOT_ENOUGH_PLAYERS`；否则 `_deal_new_match()`（**不**改 match_number）。
- 说明：`_deal_new_match()` 已生成新 `match_id`、清按局状态、重发 `HAND_SIZE` 手牌、`_apply_match_start_relics()`、回 `INITIAL_PEEK`。

## 3. 发牌动画（`scripts/ui/table3d_view.gd`）
- 常量：`DEAL_INTERVAL := 0.15`。
- 成员：`var _deal_speed := 1.0`；`var _dealing := false`。
- `func play_deal(state: Dictionary) -> void`：
  - 若 `_last_state` 为空或已在发牌 → 忽略；`_dealing = true`；
  - 收集座位（`_seat_node_by_id.keys()` 排序）与每个座位的手牌槽数（`players[seat].slots.size()`，取各席最大值，通常 `HAND_SIZE`）；按座位升序（从房主）**一个玩家一个玩家**生成目标列表（seat 外层、slot 内层）；
  - 对每个目标 `_mark_anim_slot(seat,slot)`；`render(state)`（目标槽隐藏）；
  - `_run_deal(targets)`（async）。
- `func _run_deal(targets) -> void`：逐个：`await get_tree().create_timer(DEAL_INTERVAL / maxf(_deal_speed,0.01)).timeout`；`if not is_inside_tree() or not _dealing: return`；`_spawn_fly(center_xform("deck"), slot_xform(seat,slot), {}, false, false, Callable(...).bind(seat,slot))`（落地撤销该槽标记 + `_refresh`）。
  - 落地回调：`func _on_deal_land(seat, slot): _unmark_anim_slot(seat,slot)`；`_spawn_fly` 已在其后 `_refresh()`。
  - 全部发完后 `_dealing = false`。
- `func set_deal_speed(s: float) -> void: _deal_speed = maxf(s, 0.01)`（main 每帧按空格设置 2.0/1.0）。
- `_clear_exchange_anim()`（切出 3D）已清 `_anim_slots`/飞牌；加 `_dealing=false`。
- **注意**：`_refresh()` 会重渲染；`_mark_anim_slot` 的槽在 render 中跳过；落地后撤销即显示。

## 4. 3D 重开按钮（`scripts/ui/table3d_view.gd`）
- 在 `_bind()` 建一个 `Center/PileArea`？否——放**牌桌右角**：新增节点 `RestartButton`（`Node3D`）：一个圆形底盘（`CylinderMesh` 扁平）+ `↻` 文字（`Label3D` billboard）+ `Area3D`（`PICK_MASK`、meta `{"kind":"hud","action":"restart"}`）。
  - 位置：桌子右角 `Vector3(TABLE_RADIUS*0.85, TABLE_HEIGHT+0.02, TABLE_RADIUS*0.85)`（右后角，具体可调）。
  - 可见性：仅 **房主**（`Network.is_host`）；`render` 里按 `Network.is_host` 设 `visible`。
- `main._table3d_click` 的 `"hud"` 分支已路由 `_on_action(action)`；新增 `"restart"` → `_request_restart_confirm()`。

## 5. 2D 重开按钮（`scripts/ui/game_view.gd`）
- 房主 + 对局中：在棋盘**右侧**放圆形 `↻` 按钮（`Button`，`custom_minimum_size` 方，`StyleBoxFlat` 圆角=半边长 → 圆形；`text="↻"`）；`pressed` → `main._request_restart_confirm()`。非房主/非对局隐藏。

## 6. 重开确认（`scripts/ui/main.gd`）
- 成员：`var _restart_confirm := false`。
- `func _request_restart_confirm(seat)`: 仅房主；`_restart_confirm = true`；`_refresh_hint_panel()`（3D 更新 hint3d）。
- `_hint_for(state)`：若 `_restart_confirm` → 返回 `"是否重开？"`（优先于其它提示）。
- 条件动作按钮：`_refresh_hint_panel` 用 `ActionModel.conditional_actions` 渲染；`_restart_confirm` 时改为渲染 `[{text:"确认",action:"restart_yes"},{text:"取消",action:"restart_no"}]`。
- `_on_action`：`"restart_yes"` → `_restart_confirm=false`；`GameState.request_restart_match(_next_action_id())`；`"restart_no"` → `_restart_confirm=false`；两者后 `_refresh_hint_panel()`。
- 发牌触发：`_on_state_updated`（或 `_process`）检测 `latest_state.match_id` 变化 → 记录 `_last_match_id`；若变化且非空且 `_table3d_active` → `table3d.play_deal(latest_state)`。
- 空格 2 倍速：3D 激活且正在发牌时，`_process` 里 `table3d.set_deal_speed(2.0 if Input.is_key_pressed(KEY_SPACE) else 1.0)`。（比拼 STOP 用空格；发牌与比拼不同时。）

## 7. 数据流
1. 服务器 `_server_start_match`/`_deal_next_match`/`_server_restart_match` → `_deal_new_match()` → 新 `match_id` + 快照。
2. 客户端收快照，`match_id` 变化 → `table3d.play_deal` → 逐张飞牌发到各席、落地露出；空格 2 倍速。
3. 房主点 `↻`（2D/3D）→ 提示板「是否重开」→ 确认 → `request_restart_match` → 服务器重开本局 → 新 `match_id` → 全员重发。

## 8. 边界
- 2D 不发牌；发牌中途切 2D/退出 3D → `_clear_exchange_anim` 清在途。
- 重开限房主、非 LOBBY；无「确认」不做任何事。
- 隐私：发牌用卡背（`{}`），不泄漏牌面。
- 重连：`match_id` 未变则不重放发牌（除非首见；见风险）。

## 9. 参数（初值，可调）
| 常量 | 初值 | 说明 |
| --- | --- | --- |
| `DEAL_INTERVAL` | `0.15` s | 每张间隔（空格时 ÷2） |
| 重开按钮位置 | 牌桌右后角 / 2D 右侧 | 可调 |

## 10. 测试与验收
- `tests/verify_restart.gd`：服务器 `_server_restart_match` 重开（保留 match_number/货币/生命/系列赛；新 match_id；手牌重发到 HAND_SIZE；回 INITIAL_PEEK）；拒绝非房主/LOBBY/人数不足。
- 发牌：`Table3dView.play_deal` 标记在途 → render 跳过；落地回调撤销；`set_deal_speed` 生效；`_dealing` 生命周期。
- `main`：`match_id` 变化触发；`_restart_confirm` → hint 文案与按钮；确认/取消走 RPC。
- 回归：全量 `tools/run_all_tests.sh` 全绿；`git diff` 确认 `scripts/net/*`、`table3d.tscn`、2D 渲染文件（除 game_view 加按钮）零无关改动。

## 11. 文件清单
| 文件 | 变更 |
| --- | --- |
| `scripts/core/game_state.gd` | `request_restart_match`/`server_restart_match`/`_server_restart_match` |
| `scripts/ui/table3d_view.gd` | `play_deal`/`_run_deal`/`_on_deal_land`/`set_deal_speed` + 3D 重开按钮 |
| `scripts/ui/main.gd` | `match_id` 变化触发发牌、空格倍速、`_restart_confirm`、`_on_action` restart* |
| `scripts/ui/game_view.gd` | 2D 房主重开按钮 |
| `tests/verify_restart.gd`/`.tscn`、`tools/run_all_tests.sh` | 测试与注册 |
| docs × 4 | 记录 |

**不改**：`scripts/net/*`、`HiddenInfo` 快照结构、`scenes/ui/table3d.tscn`。
