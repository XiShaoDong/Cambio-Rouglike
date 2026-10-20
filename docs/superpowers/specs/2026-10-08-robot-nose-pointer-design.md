# KONG Robot 鼻子指针（中键伸缩）设计 v1

> **目的**：3D 对局里给每个 Robot 角色在**双眼中间、眼睛下方、嘴巴上方**加一个程序化"鼻子"。玩家准星悬停在**任意可拾取卡牌**上时按**鼠标中键（或 D 键）**，该玩家角色的鼻子会沿**头部朝向**前伸（长度 = 鼻根到该卡的世界距离），伸出后**方向实时跟随头部晃动**、长度不变，**再次按中键/D 键缩回**。**所有玩家**（含本机第一人称）都能看到对应角色的鼻子。
> **纯客户端展示层**：不改规则 / 状态机 / 快照 / `scripts/core/*`（除 `game_state.gd` 的 `look` 表现层通道加一个可选字段）/ `scripts/net/*`；2D 逻辑零改动。

## 1. 目标与非目标

**目标**

1. 在 Robot 模型脸上加一个**加载时程序化生成**的鼻子（不动 `Robot.blend`），位置在两眼中间、眼下、嘴上（模型空间 `≈(0, 1.99, 0.24)`，`+Z`=脸朝向）。
2. 3D 对局中，准星悬停在可拾取卡牌（pick kind ∈ `slot`/`deck`/`discard`/`pending`）上时按**中键（或 D 键）**：
   - 计算鼻根→该卡世界距离 `d`，鼻子沿当前头朝向前伸，约 `NOSE_DURATION` 到达（**时长固定 → 远则速度快**）。
   - 伸出后方向**实时跟随头部**（远程=其同步注视方向推导的头姿势；本机=相机），长度保持不变。
   - **再次按中键/D 键 → 缩回**（不自动收回）。
   - 未悬停卡牌时中键/D 键无效；缩回途中忽略。
3. **本机第一人称也能看到自己的鼻子**（挂在相机上）；其他玩家通过同步看到每席鼻子。
4. 鼻子**不挂碰撞层**、不参与准星拾取，不影响既有卡牌/牌堆点击。
5. 复用既有 `look` 表现层通道同步"鼻子长度"（每席角色表现，和 `zoom`/`talking` 同类），不新增 RPC。
6. 2D 逻辑与 2D 渲染逐字不变（仅 3D 生效）。

**非目标**

- 不改规则 / 状态机 / 快照字段 / `HiddenInfo` / `scripts/net/*`。
- 不改 `scenes/ui/table3d.tscn` 结构与既有节点契约。
- 不修改 `assets/characters/source/Robot.blend`（二进制资产）。
- 不新增独立 RPC（沿用 `look`）。
- 鼻子不锁定卡牌位置；不做射线命中判定；不做卡牌标记物。

## 2. 架构与组件（均纯客户端展示层）

### 2.1 `scripts/ui/nose_avatar.gd`（新增，`class_name NoseAvatar extends Node3D`）

可复用的"单条鼻子"控制器：

- **几何**：`CylinderMesh` 圆锥（底半径 `NOSE_BASE_RADIUS`、顶半径 `NOSE_TIP_RADIUS`、高 `1.0`），单位长度沿**本地 +Z**，底面在原点（`MeshInstance3D` 内置变换把圆柱旋转到 +Z 并前移 0.5）。材质 `StandardMaterial3D`（albedo 可设、轻微 emission），无碰撞。
- **状态机**：`IDLE / EXTENDING / EXTENDED / RETRACTING`。
- **API**：
  - `set_target(len: float)`：`len>0` 且当前非伸出 → 进入 `EXTENDING`（目标长度 `len`）；`len<=0` 且当前在 `EXTENDED`/`EXTENDING` → 进入 `RETRACTING`（目标 0）。
  - `_process(delta)`：按 `NOSE_DURATION` 从 `_from_len` 线性插值到 `_target_len`（缓动可选），写子网格 `scale.z`；到达后切状态；`IDLE`/长度 0 时隐藏。
  - `set_color(c: Color)`：设材质 albedo。
  - `length() -> float`：当前长度（测试用）。
  - `state_name() -> String`：当前状态名（测试用）。
  - `is_active() -> bool`：长度 > 0。
- **位姿**：`NoseAvatar` 自身由宿主每帧设置**世界变换**（鼻根位置 + 朝向），鼻子网格沿其本地 +Z 生长。本机实例作为 `Camera3D` 子节点时由局部变换决定（见 2.4）。

### 2.2 `scripts/ui/robot_avatar.gd`（改）

- `_build()` 里在 `RobotAvatar`（本节点）下创建 `_nose := NoseAvatar.new()`，`set_color(_body_color)`；`_apply_body_color()`/`set_body_color()` 同步鼻子颜色。
- 新增 `nose_base_world() -> Transform3D`：由 **Head 骨骼当前姿势**推出鼻根世界位姿，使鼻子**随头转**：
  - `base_model = head_pose * (head_rest.affine_inverse() * NOSE_BASE_MODEL)`（与既有 `_eye_origin_model()` 同法）；
  - 朝向 basis = `(head_pose.basis * head_rest.basis.inverse())` 作用到模型前向 +Z，再乘 `_skeleton.global_transform.basis`；
  - 返回 `Transform3D(world_basis.normalized(), _skeleton.global_transform * base_model)`。
  - 头未转 / 无骨架时退化为 `global_transform * NOSE_BASE_MODEL` 与模型前向。
- `_process(delta)` 中每帧把 `_nose.global_transform = nose_base_world()`（鼻子位姿自持，宿主无需介入）。
- 新增 `set_nose_target(len: float)` / `nose_length() -> float` / `nose_state_name()` / `is_nose_active()`：转发给 `_nose`。
- 常量：`NOSE_BASE_MODEL := Vector3(0.0, 1.99, 0.24)`（可调）。

### 2.3 `scripts/ui/table3d_view.gd`（改）

- `update_hover()` 缓存当前悬停命中信息：新增 `_hover_world_pos: Vector3` 与 `_hover_kind: String`（来自 `hit.position` / `hit.pick.kind`），`clear_hover()`/离开时清空。
- 新增 `hovered_card_world() -> Variant`：pick kind ∈ {`slot`,`deck`,`discard`,`pending`} 时返回命中卡的世界位置（`(collider.get_parent() as Node3D).global_position`，退化用 `hit.position`），否则 `null`。
- `_attach_robot()` 无需变（鼻子在 `RobotAvatar._build` 内部，位姿自持）。
- 新增 `update_noses(remote_nose: Dictionary) -> void`（每帧，由 `main._process` 调）：逐**可见席** `robot.set_nose_target(remote_nose.get(seat, 0.0))`（本机席角色隐藏，本机鼻子单独管理，见下）。
- 本机鼻子：`_ensure_local_nose()` 在 `_bind()` 时把 `NoseAvatar.new()` 挂到 `camera.camera_node()` 下，局部变换 `LOCAL_NOSE_XFORM`（`position=(0,-0.06,-0.15)`、绕 Y 转 180° 使本地 +Z = 相机前向）。
  - `set_local_nose_target(len)` / `local_nose_length()` / `local_nose_state_name()`：转发给本机相机鼻子。
  - `local_nose_base_world() -> Vector3`：本机鼻根世界位置（供 `main` 算到卡距离）。
  - `clear_local_nose()`：目标清零（退出 3D / `set_active(false)` 时调）。
- `set_active(false)` / 退出 3D 时 `clear_local_nose()`。

### 2.4 `scripts/ui/main.gd`（改）

- `_input()` 的 3D 分支新增 `InputEventMouseButton` **中键**：
  ```
  if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
      _on_nose_click()
      get_viewport().set_input_as_handled()
  ```
- `_on_nose_click()`：
  - 看板面板打开 / 无 `table3d` → 忽略。
  - 若本机鼻子当前 `IDLE`（未伸出）：取 `table3d.hovered_card_world()`；为 `null` → 忽略；否则 `d = table3d.local_nose_base_world().distance_to(card_world)`，设 `_nose_local_target = d`，并 `_send_nose(d)`。
  - 若本机鼻子在 `EXTENDED`/`EXTENDING` → 设 `_nose_local_target = 0.0`，并 `_send_nose(0.0)`。
  - 若在 `RETRACTING` → 忽略。
- `_process()` 3D 分支：`table3d.update_noses(GameState.remote_nose)` + `table3d.set_local_nose_target(_nose_local_target)`。缩回到零后本机状态回 `IDLE`（读 `table3d.local_nose_state_name()`）以便下次触发。
- `_send_nose(len)`：`seat = latest_state.viewer_id`；房主走 `GameState._apply_look(seat, 现有注视点, zoom, talking, len)`；否则把 `len` 并入下一次 `server_look`（见 3）。
- 新增本地字段 `_nose_local_target := 0.0`、`_last_look_nose := 0.0`。

## 3. 同步（扩展 `look` 表现层通道）

- `scripts/core/game_state.gd`：
  - 新增 `var remote_nose: Dictionary = {}`（`{seat: float}`），在 `remote_looks` 同处（座位移除 / 房间清空）一并 `erase`/`clear`。
  - `server_look(target: Vector3, zoom: bool, talking: bool, nose := 0.0)` → `_apply_look(seat, target, zoom, talking, nose)`。
  - `_apply_look(seat, target, zoom := false, talking := false, nose := 0.0)`：写 `remote_nose[seat] = maxf(nose, 0.0)`，转发 `receive_look.rpc_id(peer, seat, target, zoom, talking, nose)`。
  - `receive_look(seat, target, zoom, talking, nose := 0.0)`：同样写 `remote_nose[seat]`。
  - 默认参数保证既有调用（含 `verify_robot_avatar` 的 4 参调用）向后兼容。
- `main._update_look_send()`：把本机当前鼻子目标长度 `_nose_local_target` 一并发送，并纳入"变化即发"判断（`nose != _last_look_nose`）；`LOOK_SEND_INTERVAL` 12Hz 上限不变（toggle 会被最近一次上报携带，≤83ms 延迟可接受）。
- 说明：`look` 是可靠的 per-seat 表现状态通道（已带 `zoom`/`talking`），鼻子长度与其同类，故复用；方向无需同步——各客户端已由 `remote_looks` 推出该席头姿势，鼻子方向据此确定性推出。

## 4. 数据流

1. 本机悬停卡牌 → 中键 → `_on_nose_click()` 算 `d` → 本地 `_nose_local_target=d`（本机相机鼻子立即开始伸），并随下一次 `look` 上报 `nose=d`。
2. 服务器 `_apply_look` 写 `remote_nose[actor]=d` 并转发 `receive_look` 给其他客户端。
3. 各客户端 `_process` → `table3d.update_noses(GameState.remote_nose, _nose_local_target)`：
   - 远程席：`robot.set_nose_target(d)` + 每帧 `robot.nose_base_world()` 设鼻子位姿（随头）。
   - 本机：`set_local_nose_target(_nose_local_target)`（相机鼻子，随相机）。
4. 再次中键 → 本地与远程 `target=0` → 缩回 → 状态回 `IDLE`。

## 5. 依赖与边界

- **隐私**：鼻子只指向"卡牌位置"（位置本就公开），不上报牌面；无泄漏。
- **2D 玩家**：无 3D 输入、不触发；其角色无鼻子动画（`remote_nose` 缺省 0）。
- **离线 / 出局**：`remote_nose` 随座位数据清理；出局者角色仍可被渲染但不触发。
- **看板模态打开**：中键被忽略（与左键路由一致）。
- **`update_hover` 只在无看板时运行**（`main._process` 已有早退），故 `hovered_card_world()` 在看板打开时为旧值；`_on_nose_click` 额外用 `_board_has_panel()` 早退兜底。
- **每帧位姿**：远程鼻子位姿每帧由 `nose_base_world()` 重设；`render()` 重建不影响（鼻子在 `RobotAvatar` 内、非每 render 重建；若重建 `RobotAvatar` 则鼻子随之重建）。

## 6. 参数（初值，可调）

| 常量 | 初值 | 说明 |
| --- | --- | --- |
| `NOSE_BASE_MODEL` | `(0, 1.99, 0.24)` | 模型空间鼻根（两眼中间、眼下、嘴上） |
| `NOSE_BASE_RADIUS` / `NOSE_TIP_RADIUS` | `0.05` / `0.015` | 锥底/锥尖半径（模型空间） |
| `NOSE_DURATION` | `0.35` s | 伸出/缩回固定时长（→ 速度随距离） |
| 本机相机偏移 `LOCAL_NOSE_XFORM` | `pos(0,-0.06,-0.15)`，绕 Y 180° | 第一人称鼻根位置与朝向 |
| `NOSE_COLOR` | 该玩家机体色（+轻微 emission） | 鼻子颜色，`set_body_color` 同步 |

## 7. 测试与验收

新增 `tests/verify_nose.gd` + `.tscn`（headless）：

- **状态机**：`set_target(d>0)` → `EXTENDING`，经 `NOSE_DURATION` 后 `EXTENDED` 且 `length≈d`；`set_target(0)` → `RETRACTING` → `IDLE` 且 `length≈0`；`IDLE` 时 `set_target(0)` 无变化。
- **长度=距离**：主算 `d = base.distance_to(card)`（可在纯函数 / view 层断言）。
- **头部跟随**：`RobotAvatar` 在头姿势变化（`_apply_head_tracking` 后）时 `nose_base_world()` 的 origin/basis 随之变化。
- **同步**：`GameState._apply_look(seat, t, z, tk, nose)` / `receive_look(...)` 写入 `remote_nose[seat]`；默认参数兼容 4 参旧调用。
- **本机第一人称**：本地鼻子节点存在、可见、`set_local_nose_target` 驱动。
- **非卡牌不触发**：`hovered_card_world()` 对 `hud` / 空命中返回 `null`。
- **采集**：`update_noses` 对可见席下发远程长度、对无数据席为 0。
- **回归**：`verify_robot_avatar`、`verify_table3d_interaction`、`verify_table3d_exchange`、`verify_table3d`、`verify_actions`、双实例 `verify_net` 全绿。

**验收闸门**

1. 新增断言全绿；
2. `tools/run_all_tests.sh` 全量全绿；
3. `git diff` 确认 `scripts/net/*`、`scenes/ui/table3d.tscn`、`Robot.blend`、2D 渲染文件零改动；`game_state.gd` 仅表现层改动（`remote_nose` 字典、`look` 可选 `nose` 参数、座位/房间清理各一行），不触碰规则/快照/状态机。

## 8. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/nose_avatar.gd` | **新增**：程序化鼻子 + 伸缩状态机 |
| `scripts/ui/robot_avatar.gd` | 创建鼻子、`nose_base_world()`（随头）、`set_nose_target`/查询、颜色同步、`NOSE_BASE_MODEL` |
| `scripts/ui/table3d_view.gd` | hover 缓存世界位置/kind、`hovered_card_world()`、`update_noses()`、本机相机鼻子 |
| `scripts/ui/main.gd` | 中键分支、`_on_nose_click()`、本地目标、`update_noses`/`set_local_nose_target`、`look` 携带 nose |
| `scripts/core/game_state.gd` | `remote_nose` + `look` 增可选 `nose` 参数（表现层，不入快照） |
| `tests/verify_nose.gd` / `.tscn` | **新增**：状态机/长度/跟随/同步/本机可见/非卡牌不触发 |
| `docs/网络协议_V1.md` / `docs/3D角色与场景说明.md` / `docs/功能实现文档.md` / `docs/AI_AGENT_交接说明.md` | 记录 `look` 增 `nose` + 鼻子指针功能 |

**不改**：`scripts/net/*`、`scripts/core/game_state.gd` 以外的 core 文件、`HiddenInfo`、`scenes/ui/table3d.tscn`、`Robot.blend`、`game_view.gd`、`card_view.gd`、`card_block.gd`、`card_animator.gd`、`reveal_controller.gd`、`card_fly*.gd`。
