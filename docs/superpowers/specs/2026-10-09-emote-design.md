# KONG 表情系统（Emote · Y 长按轮盘）设计 v1

> **目的**：新增"表情/动作"系统，复用标记轮盘同款**按键 + 鼠标拖拽**交互：**按住 Y** 出 **6 扇区轮盘**（数字 `1–6` 占位），拖到扇区松 Y → 该玩家角色**头顶悬浮数字 billboard**，持续 **2.5s**，**其他玩家实时可见**；占位为主，**重点预留网络接口**，后续把 `index` 映射到真实 avatar 动作（抬手/指人等）。
> **纯客户端展示层**：不改规则/状态机/快照/`HiddenInfo`/`scripts/net/*`；`game_state.gd` 仅新增表现层 RPC/信号。

## 1. 目标与非目标
**目标**
1. 3D 下**按住 Y** → 释放鼠标、在**屏幕中心**显示 6 扇区轮盘（`1`–`6`，中心中空、虚线分界）；拖到扇区松 Y 播放；**单点/中空 → 不播放**。
2. 表现（占位）：该玩家角色**头顶悬浮数字 billboard**（`Label3D`，`1–6`，朝相机），随角色/头转向；**`EMOTE_DURATION=2.5s`** 后消失。自己角色第一人称隐藏 → 自己看不到、其他玩家实时看到。
3. **网络接口（重点）**：表现层事件 RPC `server_emote(index: int)` → `receive_emote(seat, index)` → 客户端信号 `GameState.emote_played(seat, index)`。**不入快照**、不判定。将来真实动作只改 `show_emote`/`EmoteDisplay` 按 `index` 播放，协议不变。
4. 表情数 **6**、时长 **2.5s**、触发键 **Y**（可调）。

**非目标**
- 不接真实动画/blendshape（后续）；不做 target/指人参数（`index` 即动作本身）。
- 不改规则/快照/`table3d.tscn`/`Robot.blend`。

## 2. 架构与组件（纯客户端展示层）
### 2.1 `scripts/ui/mark3d_math.gd`（改，纯函数）
- 新增 `sector_index_for(offset: Vector2, inner: float, outer: float, count: int) -> int`：`|offset|<inner` 或 `>outer` → `-1`；否则按角度返回 `0..count-1`（**扇区 0 以正上 -90° 为中心、顺时针递增**）。用 `rel = fposmod(atan2(offset.y,offset.x)_deg + 90 + w/2, 360)`、`idx = int(rel / w)`，`w = 360.0/count`。

### 2.2 `scripts/ui/emote_wheel.gd`（新增，`class_name EmoteWheel extends Control`）
- 6 扇区轮盘（文案 `1`–`6`，中心中空、扇区之间虚线分界）。`open(center: Vector2)` / `close()` / `update_cursor(pos)` / `selected() -> int`（-1 无）。命中用 `Mark3dMath.sector_index_for`。绘制风格同 `MarkWheel`（扇区多边形 + 虚线分界 + 中空 + 文本）。

### 2.3 `scripts/ui/emote_display.gd`（新增，`class_name EmoteDisplay extends Node3D`）
- `play(index: int, duration := 2.5)`：建 `Label3D`（billboard、`no_depth_test`、文本 `str(index+1)`），位于本地 `y=HEAD_OFFSET`；`_process` 计时，结束前淡出，发 `finished` + `queue_free`。
- 常量 `EMOTE_DURATION=2.5`、`FADE_OUT=0.3`、`HEAD_OFFSET`、`COLOR`（默认白/亮）。

### 2.4 `scripts/ui/table3d_view.gd`（改）
- `show_emote(seat_id: int, index: int)`：`seat==_viewer` 忽略（自己角色隐藏）；否则取该席 `Avatar`，在其上建 `EmoteDisplay`（`y = 头顶`），保存 `_emotes[seat]`（同席替换），`finished` → 移除。
- `clear_emotes()`：释放全部；`set_active(false)` 时调用（退出 3D 清空）。
- 成员 `_emotes := {}`。

### 2.5 `scripts/core/game_state.gd`（改，表现层事件）
- `signal emote_played(seat: int, index: int)`。
- `@rpc("any_peer","call_remote","reliable") server_emote(index: int)` → 校验发送者 → `_apply_emote(seat,index)`。
- `_apply_emote(seat,index)`：`emote_played.emit(seat,index)`；`for s in players.keys(): peer>1 → receive_emote.rpc_id(peer, seat, index)`。
- `@rpc("authority","call_remote","reliable") receive_emote(seat,index)`：`emote_played.emit(seat,index)`。不入快照。

### 2.6 `scripts/ui/main.gd`（改）
- 复用 D 的轮盘框架，扩为两种轮盘：`_wheel_open` / `_wheel_kind`（`"mark"`/`"emote"`）+ `_mark_wheel`/`_emote_wheel`。
- `_input`：轮盘打开时 —— 松开对应键（mark→`KEY_D`、emote→`KEY_Y`）→ `_finish_wheel()`；motion → 活动轮盘 `update_cursor`；其余忽略。未打开时：`KEY_D` 按下 → `_open_mark_wheel()`；`KEY_Y` 按下 → `_open_emote_wheel()`。
- `_open_emote_wheel()`：非 3D/看板/设置 → 忽略；释放鼠标；`_emote_wheel.open(屏幕中心)`；`_wheel_open=true`、`_wheel_kind="emote"`。
- `_finish_wheel()`：取所选（mark→扇区名/落点放置；emote→`index`）；关轮盘、恢复捕获；emote 时 `index>=0` → `_send_emote(index)`。
- `_send_emote(index)`：房主 `GameState._apply_emote(seat,index)`；否则 `GameState.server_emote.rpc_id(1,index)`。
- `_on_emote_played(seat,index)` → `table3d.show_emote(seat,index)`。`_ready` 连接 `GameState.emote_played`。

## 3. 数据流
1. 玩家 3D 按住 Y → 释放鼠标、屏幕中心出 6 扇区轮盘。
2. 拖到扇区松 Y → `_send_emote(index)` → 服务器 `_apply_emote`（本地 `emote_played` + 转发 `receive_emote`）。
3. 各客户端 `_on_emote_played` → `table3d.show_emote(seat,index)`：该席角色头顶数字 billboard，2.5s 后消失。

## 4. 边界
- 2D 不生效；自己看不到自己的表情（角色隐藏）；同席一个表情（替换重置）；退出 3D `clear_emotes()`。
- 隐私：只同步 `index`（无牌面/位置）；不入快照。

## 5. 参数（初值，可调）
| 常量 | 初值 | 说明 |
| --- | --- | --- |
| 表情数 | `6` | 轮盘扇区数 |
| `EMOTE_DURATION` | `2.5` s | 持续 |
| `EMOTE_FADE_OUT` | `0.3` s | 结束淡出 |
| 触发键 | `Y` | 长按出轮盘 |

## 6. 测试与验收
新增 `tests/verify_emote.gd` + `.tscn`：
- `Mark3dMath.sector_index_for`：6 扇区上/右/下/左/中空/超范围；0 在正上、顺时针。
- `EmoteWheel`：open/update_cursor/selected（各扇区、中空 -1）/close。
- `EmoteDisplay`：`play` 生成数字 billboard、计时到 `EMOTE_DURATION` 后 `finished` + 释放。
- `Table3dView.show_emote`：remote 席生成、同席替换、`clear_emotes` 清空；viewer 席忽略。
- `GameState`：`_apply_emote` 发信号、`receive_emote` 发信号。
- 回归：`verify_mark`、`verify_nose`、`verify_table3d_interaction`、`verify_table3d_exchange`、`verify_protocol`、双实例 `verify_net` 全绿。
- 注册到 `tools/run_all_tests.sh`。

**验收闸门**：新增断言全绿；`run_all_tests.sh` 全量全绿；`git diff` 确认 `scripts/net/*`、`table3d.tscn`、`Robot.blend`、2D 渲染文件零改动。

## 7. 文件清单
| 文件 | 变更 |
| --- | --- |
| `scripts/ui/emote_wheel.gd` | **新增**：6 扇区轮盘 |
| `scripts/ui/emote_display.gd` | **新增**：头顶数字 billboard + 生命周期 |
| `scripts/ui/mark3d_math.gd` | 新增 `sector_index_for` |
| `scripts/ui/table3d_view.gd` | `show_emote`/`clear_emotes`/`_emotes` |
| `scripts/core/game_state.gd` | `emote_played` 信号 + `server_emote`/`_apply_emote`/`receive_emote` |
| `scripts/ui/main.gd` | Y 长按轮盘、`_send_emote`、`_on_emote_played`；D/Y 轮盘框架统一 |
| `tests/verify_emote.gd`/`.tscn`、`tools/run_all_tests.sh` | 测试与注册 |
| docs × 4 | 记录表情系统 |

**不改**：`scripts/net/*`、`scenes/ui/table3d.tscn`、`assets/characters/source/Robot.blend`、2D 渲染文件。
