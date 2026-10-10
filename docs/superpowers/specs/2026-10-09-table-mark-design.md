# KONG 桌面标记（波纹 ping）设计 v1

> **目的**：3D 对局里按 **D** 在准星指向的桌面位置放置一个**标记**：桌面出现**两层向外扩散的圆形波纹**（声呐脉冲），中心**内圈上有箭头**（尖端指向圆心，朝向 = 标记者→圆心 的水平方向），上方悬浮一个**红色眼睛**图案（程序化 billboard）。标记**同步给所有玩家**、**3 秒后自动消失**（再按 D 替换并重置）。
> **与鼻子互斥**：两种"标记"风格同时只生效一种，由设置项 **`鼻子点击`（`Settings.gameplay.nose_click`）** 选择——**开=鼻子标记**（现有），**关=波纹标记**（本设计，默认）。D 触发当前风格对应的标记。
> **纯客户端展示层**：不改规则/状态机/快照/`HiddenInfo`/`scripts/net/*`；`game_state.gd` 仅新增表现层 RPC + 信号。

## 1. 目标与非目标

**目标**

1. 3D 下按 **D**：若当前风格为**波纹**，则取**准星（屏幕中心）射线与桌面平面 `y=TABLE_HEIGHT` 的交点**作为标记落点；仅当落点在桌面范围内（`|x|,|z| ≤ TABLE_RADIUS`）才放置，桌外/无效忽略。
2. 标记视觉：桌面 `y≈TABLE_HEIGHT` 处**两层圆环**持续向外扩散循环（两环相位错开，声呐脉冲）；**内圈箭头**尖端指向圆心、朝向取「标记者座位世界位置 → 圆心」的水平方向；中心上方悬浮**红色眼睛**（程序化生成贴图，billboard）。
3. 标记 **`MARK_LIFETIME=3.0s`** 后淡出消失；同一玩家（seat）在存续期内再按 D → **替换**旧标记并**重置计时**。
4. **所有玩家可见**：新增表现层 RPC `server_mark(pos)` → 服务器转发 `receive_mark(seat,pos)`；每个客户端据此在对应位置生成标记。事件式（无状态存储、不入快照）。
5. 风格分派：`main._on_mark_click()` 按 `Settings.gameplay.nose_click` 分派——开→走现有鼻子逻辑；关→波纹标记。D 为唯一触发键。
6. 2D 路径零改动；2D 下 D 无效。

**非目标**

- 不改规则/状态机/快照字段/`HiddenInfo`/`scripts/net/*`。
- 不改 `scenes/ui/table3d.tscn` 结构、不改 `Robot.blend`、不改 2D。
- 不做多标记样式库（后续可扩展图案）；不做标记命名/聊天。

## 2. 架构与组件（均纯客户端展示层）

### 2.1 `scripts/ui/mark3d_math.gd`（新增，纯函数）

- `static func arrow_dir_xz(center: Vector3, owner: Vector3) -> Vector3`：返回从 owner 指向 center 的**水平（XZ）单位方向**；退化（同一 XZ）时回退 `Vector3.FORWARD`。
- `static func on_table(pos: Vector3, radius: float) -> bool`：`absf(pos.x) <= radius and absf(pos.z) <= radius`。
- `static func ring_scale(phase: float, base: float, max_scale: float) -> float`：`lerpf(base, max_scale, clampf(phase,0,1))`。
- `static func ring_alpha(phase: float, peak: float) -> float`：`peak * (1.0 - clampf(phase,0,1))`（向外扩散同时淡出）。
- `static func wrap_phase(t: float, period: float) -> float`：`fmod(t, period)/period`。

### 2.2 `scripts/ui/mark3d.gd`（新增，`class_name Mark3D extends Node3D`）

- **几何**：
  - **两层圆环**：`MeshInstance3D` × 2，`TorusMesh`（`inner_radius`/`outer_radius` 细环），绕 X 转 -90° 平贴桌面；`StandardMaterial3D`（`SHADING_MODE_UNSHADED`、`TRANSPARENCY_ALPHA`、`CULL_DISABLED`）albedo=标记色（红）。
  - **内圈箭头**：`MeshInstance3D`，`ArrayMesh` 三角（扁平箭头，位于本地 +Z，尖端朝 +Z）或细长锥；材质同上。
  - **红色眼睛**：`Sprite3D`（`billboard=BILLBOARD_ENABLED`、`no_depth_test=true`），贴图由 `_build_eye_texture()` 程序化生成（`Image` RGBA8，画眼白/红虹膜/瞳孔/高光；尺寸 `EYE_TEX=(96,64)`）；悬浮于中心上方 `EYE_HEIGHT`，轻微上下浮动。
- **API**：`setup(owner_dir: Vector3)`（按方向设箭头 `rotation.y = atan2(dir.x, dir.z)`）；`set_color(c)`；`finished` 信号（到时/淡出后发）。
- **动画**：`_process(delta)` 累加 `_t`；两环 `phase = wrap_phase(_t/PERIOD + offset_i)` → `scale`/`alpha`；`_t >= LIFETIME` 起淡出（最后 `FADE_OUT` 秒整体 alpha 降），`_t >= LIFETIME+FADE_OUT` → `finished.emit()` + `queue_free()`。
- **常量**：`LIFETIME=3.0`、`FADE_OUT=0.3`、`PERIOD=1.2`、`RIPPLE_MAX_SCALE`、`EYE_HEIGHT`、`EYE_TEX`、`MARK_COLOR=Color("ff3b3b")`。

### 2.3 `scripts/ui/table3d_view.gd`（改）

- 新增 `_marks := {}`（`seat -> Mark3D`）与 `_owner_dir_for(seat) -> Vector3`（用 `_seat_node_by_id[seat].global_position` 与标记位置算 `Mark3dMath.arrow_dir_xz`）。
- `show_mark(seat_id: int, pos: Vector3) -> void`：
  - 同席已有有效 `Mark3D` → `queue_free()` 后替换；
  - `Mark3D.new()`，`global_position = pos`，`setup(owner_dir)`，`add_child` 到本视图；`finished` → 从 `_marks` 移除并释放；
  - `_marks[seat_id] = node`。
- `clear_marks()`：释放全部并清空；在 `set_active(false)` 里调用（退出 3D 清空）。
- 标记为独立节点（非每帧 `render` 重建），状态广播不冲掉。

### 2.4 `scripts/ui/table3d_picker.gd`（改）

- 新增 `static func ray_plane_y(cam: Camera3D, screen_center: Vector2, plane_y: float) -> Vector3`：屏幕中心射线与水平面 `y=plane_y` 求交；`|dir.y|` 过小或 `t<=0` → 返回 `Vector3.INF`（调用方用 `is_finite()` 判定失败）。

### 2.5 `scripts/core/game_state.gd`（改，表现层事件）

- `signal mark_placed(seat: int, pos: Vector3)`。
- `@rpc("any_peer","call_remote","reliable") func server_mark(pos: Vector3)` → 校验发送者 `_peer_to_seat` → `_apply_mark(seat, pos)`。
- `func _apply_mark(seat: int, pos: Vector3)`：非有限忽略；`mark_placed.emit(seat, pos)`（房主本地即显）；`for s in players.keys(): peer>1 → receive_mark.rpc_id(peer, seat, pos)`。
- `@rpc("authority","call_remote","reliable") func receive_mark(seat: int, pos: Vector3)`：`mark_placed.emit(seat, pos)`。
- 不存状态、不入快照。（发送者经服务器转发回来看到自己的标记，LAN 延迟可接受。）

### 2.6 `scripts/ui/main.gd`（改）

- `_ready`：`GameState.mark_placed.connect(_on_mark_placed)`。
- 风格分派：`_on_mark_click()`：
  - `if _nose_enabled(): _on_nose_click(); return`（鼻子风格，现有 toggle）
  - 波纹风格：`table3d` 有效、无看板面板、非设置打开；`pos = Table3dPicker.ray_plane_y(cam, center, Table3dLayout.TABLE_HEIGHT)`；`pos.is_finite()` 且 `Mark3dMath.on_table(pos, Table3dLayout.TABLE_RADIUS)`；`seat = viewer_id`；`if multiplayer.is_server(): GameState._apply_mark(seat, pos) else: GameState.server_mark.rpc_id(1, pos)`。
- `_input`：`KEY_D` → `_on_mark_click()`（原 D/中键鼻子分派改为按风格；**中键不再是触发键**）。
- `_on_mark_placed(seat, pos)`：3D 激活且 `table3d` 有效时 `table3d.show_mark(seat, pos)`。

### 2.7 设置（`settings.gd` / `settings_menu.gd` / `loc.gd`）

- `Settings.gameplay.nose_click`（已存在，默认 false）语义明确为**风格开关**：`true`=鼻子标记、`false`=波纹标记。
- 设置菜单项文案保持 **「鼻子点击」**（ON=鼻子 / OFF=波纹）；`loc.gd` 不变（已含 `nose_click`）。菜单可加一行说明（可选）。

## 3. 数据流

1. 波纹风格玩家在 3D 按 D → `main._on_mark_click()` 算桌面交点 → 命中桌面 → 上报 `server_mark(pos)`（房主直接 `_apply_mark`）。
2. 服务器 `_apply_mark`：本地 `mark_placed`（房主可见）+ 转发 `receive_mark(seat,pos)` 给其他客户端（含原发送者）。
3. 各客户端 `_on_mark_placed` → `Table3dView.show_mark(seat,pos)`：生成 `Mark3D`（波纹循环 + 箭头 + 红眼），3s 后自动释放；同席再标记则替换重置。

## 4. 依赖与边界

- **纯表现**：D 只在 3D 生效；2D 无标记。
- **落点**：仅桌面内（`|x|,|z|≤TABLE_RADIUS`）；射线与桌面平行/朝上（`t<=0`）忽略。
- **隐私**：标记只是桌面坐标（公开），不含牌面。
- **互斥**：设置 ON 时 D 走鼻子、不发 `server_mark`；设置 OFF 时 D 走波纹、不驱动鼻子（`_process` 里 `not _nose_enabled()` 分支清空本机/远程鼻子）。
- **退出 3D**：`clear_marks()` 清空；重进 3D 不复活旧标记（事件已过期）。
- **同席唯一**：`_marks[seat]` 单条，替换即重置 3s。

## 5. 参数（初值，可调）

| 常量 | 初值 | 说明 |
| --- | --- | --- |
| `MARK_LIFETIME` | `3.0` s | 标记存续时长 |
| `FADE_OUT` | `0.3` s | 结束前淡出时长 |
| `PERIOD` | `1.2` s | 单环扩散周期（两环相位差 0.5） |
| `MARK_COLOR` | `#ff3b3b` | 红色（波纹/箭头/眼） |
| `TABLE_RADIUS` | `Table3dLayout.TABLE_RADIUS`(3.8) | 桌面范围 |
| `EYE_HEIGHT` | `0.5` | 红眼悬浮高度（桌面之上） |
| `EYE_TEX` | `(96,64)` | 程序化红眼贴图尺寸 |

## 6. 测试与验收

新增 `tests/verify_mark.gd` + `.tscn`（headless）：

- **纯函数**：`arrow_dir_xz` 方向正确（owner 在 +Z，center 原点 → 指向 -Z）、退化回退；`on_table` 内外判定；`ring_scale/ring_alpha` 范围与单调；`wrap_phase`。
- **Mark3D**：`setup` 后箭头 `rotation.y` 对齐方向；手动 `_process` 步进到 `LIFETIME+FADE_OUT` → `finished` 且节点被释放；两环 scale/alpha 随相位变化。
- **Table3dView**：`show_mark` 生成节点并置于 pos；同席再次 `show_mark` 替换旧节点（旧释放）；`clear_marks` 清空。
- **GameState**：`_apply_mark` 发 `mark_placed(seat,pos)` 且忽略非有限；`receive_mark` 发信号。
- **拾取**：`ray_plane_y` 相机俯视时命中桌面平面返回正确点；平行/朝上返回非有限。
- **回归**：`verify_nose`、`verify_table3d`、`verify_table3d_interaction`、`verify_table3d_exchange`、`verify_board3d`、`verify_actions`、双实例 `verify_net` 全绿。

**验收闸门**

1. 新增断言全绿；2. `tools/run_all_tests.sh` 全量全绿；3. `git diff` 确认 `scripts/net/*`、`scenes/ui/table3d.tscn`、`Robot.blend`、2D 渲染文件零改动；`game_state.gd` 仅新增表现层 RPC/信号。

## 7. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/mark3d_math.gd` | **新增**：纯函数（箭头方向/桌内判定/波纹相位） |
| `scripts/ui/mark3d.gd` | **新增**：标记节点（两层波纹 + 箭头 + 红眼 billboard + 3s 生命周期） |
| `scripts/ui/table3d_view.gd` | `show_mark`/`clear_marks`/`_marks`/`_owner_dir_for`；`set_active(false)` 清空 |
| `scripts/ui/table3d_picker.gd` | 新增 `ray_plane_y` 静态射线-平面求交 |
| `scripts/core/game_state.gd` | `mark_placed` 信号 + `server_mark`/`_apply_mark`/`receive_mark`（表现层，不入快照） |
| `scripts/ui/main.gd` | `_on_mark_click` 风格分派、`KEY_D` 触发、`_on_mark_placed` 连接与显示 |
| `tests/verify_mark.gd` / `.tscn` | **新增**：纯函数/节点/视图/同步/拾取 |
| `tools/run_all_tests.sh` | 注册 `mark` |
| `docs/网络协议_V1.md`、`docs/3D角色与场景说明.md`、`docs/功能实现文档.md`、`docs/AI_AGENT_交接说明.md` | 记录标记功能 + `server_mark` |

**不改**：`scripts/net/*`、`scenes/ui/table3d.tscn`、`assets/characters/source/Robot.blend`、`game_view.gd`、`card_view.gd`、`card_block.gd`、`card_animator.gd`、`reveal_controller.gd`、`card_fly*.gd`。
