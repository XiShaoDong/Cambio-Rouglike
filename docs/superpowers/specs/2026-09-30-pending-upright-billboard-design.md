# KONG 3D 大牌（Pending）竖立悬浮 + 面向玩家 设计 v1

> **目的**：3D 对局中那张"大牌"（`Center/Pending`，当前行动者的待处理抽牌）当前与抽牌堆同一位置、平铺桌面。本设计把它改为**竖立在桌上（垂直于牌桌）、悬浮在抽牌堆与弃牌堆之间、每个玩家视角都正对（朝本机相机的 yaw-billboard）**；当前行动者看到正面、其他人看到背面。
> **纯客户端展示层**：不改规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*`；2D 大牌与 2D 逻辑逐字不动。

## 1. 目标与非目标

**目标**

1. 3D `Center/Pending` 大牌从"抽牌堆上方平铺"改为**竖立悬浮**，XZ 落在抽牌堆与弃牌堆的中点，抬高到 `y=PENDING_Y`。
2. **始终竖直**（卡面法线水平），并**绕世界 Y 朝向本机相机**（每位玩家在自己屏幕上都是正对；不用含俯仰的完全 billboard）。
3. 正/反面沿用现有快照语义：当前行动者 `pending` 含 `rank` → 正面，其他人 → 背面。
4. 复用现有 `Center/Pending` 节点，故 `center_xform("pending")` 自动携带新变换 → **换牌 / 弃牌飞牌动画零改动即兼容**（飞牌从竖立姿态起飞、落到平铺槽位）。
5. 竖立后仍可被准星点击（拾取盒随节点旋转），`pending` 动作入口不变。
6. 2D 路径与 2D 大牌保持逐字不变（只在 3D 生效）。

**非目标**

- 不改规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*`。
- 不改 `scenes/ui/table3d.tscn`（开发者拥有；位置由代码按场景中牌堆位置计算）。
- 不改 2D 大牌（`game_view.gd` / `pending_card_box`）渲染。
- 不做"完全 billboard"（会含俯仰、不再垂直于牌桌）。

## 2. 架构与组件（均纯客户端展示层）

### 2.1 `scripts/ui/table3d_view.gd`

- 新增常量 `PENDING_Y := 0.75`（大牌中心离桌高度）。
- `_bind()` 解析完 `_deck_node` / `_discard_node` / `_pending_node` 后，设置大牌根节点本地位置：

  ```
  _pending_node.position = Vector3(
      (_deck_node.position.x + _discard_node.position.x) * 0.5,
      PENDING_Y,
      (_deck_node.position.z + _discard_node.position.z) * 0.5)
  ```

  （`Deck`/`DiscardTop`/`Pending` 同为 `Center` 子节点，本地坐标可直接取；开发者拖动牌堆时中点自动跟随。）

- 新增 `update_facing() -> void`：不改位置，只重写大牌根节点的 basis。由 `main._process()`（仅 3D 激活时）每帧调用。

  ```
  fwd  = (cam.global_position - pending.global_position)，取 y=0 后归一化
  up   = Vector3.UP
  x    = fwd.cross(up)                      # 本地 +X（卡宽）
  basis = Basis(x, fwd, up)                 # 列：X=x, Y=fwd（法向朝相机）, Z=up（卡高）
  pending.global_transform = Transform3D(basis, pending.global_position)
  ```

  - 本地 +Y 是卡面法线（`PlaneMesh(FACE_Y)`），指向相机 → 卡面正对镜头；本地 +Z 是卡高，对齐世界向上 → 保持竖直。
  - `Basis(x, y, z)` 满足 `x = y × z`，右手系、行列式 +1，贴图不镜像（经 UV 翻转后图案正立：见现有 `_material.uv1_scale=(-1,-1)`）。
  - 相机与卡几乎同 XZ（`fwd` 过短）时 `fwd` 退化：回退 `x=Vector3.RIGHT`（与 `Board3d.set_facing` 同策略）。
  - 空 `pending`（不可见）时重写 transform 无害；反之可避免相机转动后残留旧朝向。

- `render()` 中设置大牌为竖立标签模式：`_pending_block.set_upright(true)`（见 2.2）。其余 `setup`/`set_pick` 逻辑不变。

### 2.2 `scripts/ui/card_block.gd`

新增 opt-in `set_upright(on: bool) -> void`（默认 `false`，不影响手牌 / 弃牌 / 飞牌等其他卡）：

- `on=true`：把牌面文字标签从"法向正上方（本地 +Y）"改到"卡高方向顶端（本地 +Z）"，即 `_label.position = Vector3(0.0, 0.0, BLOCK_SIZE.z * 0.5 + 0.08)`，使竖立时文字浮在牌顶而非叠在牌面。
- `on=false`：恢复默认 `Vector3(0.0, BLOCK_SIZE.y * 0.5 + 0.08, 0.0)`。
- 外发光层（沿本地 +Y 微偏移的 `FACE_Y` 平面）在竖立后落到卡面背后、边缘仍外扩可见，无需改动。

## 3. 与现有动画/拾取的关系

- **换牌 / 弃牌飞牌**：`_anim_replace` / `_anim_discard` 均以 `center_xform("pending")` 为起点，现返回竖立 billboard 变换 → `CardFlyMath.compose` 在起止变换间 slerp，卡牌天然从"竖立"转到"平铺槽位 / 弃牌堆"。飞牌代码零改动。
- **拾取**：拾取 `Area3D` 挂在 `CardBlock` 根、随节点一起旋转 → 立起后拾取盒变竖直（约 0.7 宽 × 1.0 高 × 0.3 厚），准星仍能命中；`set_pick({"kind":"pending"})` 与 `main` 的 `_on_pending_action()` 分发不变。
- **hover 抬起**：`hover_anim_enabled` 仅对手牌槽开启，大牌不开，无影响。
- **揭示翻转**：大牌不经 `reveal()`，无影响。

## 4. 生命周期

- `main._process()` 在 `_table3d_active` 且 `table3d` 有效时，已有 `board.set_facing(...)`；在其后追加 `table3d.update_facing()`。
- 切出 3D（`_table3d_active=false`）→ `_process` 早退，不再更新，无副作用。

## 5. 视觉与参数

- 大牌仍用现有尺寸 `BLOCK_SIZE = (0.7, 0.04, 1.0)`；竖立后约 0.7 宽 × 1.0 高，中心 `y=0.95` → 底≈0.45、顶≈1.45，悬浮于桌面上方。
- **位置 = 两堆中点 = 桌心**：实现期把抽牌堆/弃牌堆改为沿 X 关于桌心对称（抽牌堆 `x=-0.45`、弃牌堆 `x=+0.45`，`z=0`，`DeckCount` 跟到 `x=-0.45`，`KongBell` 移到 `x=-1.2` 避免重叠）。中点即 `(0,0,0)` → 大牌落在 `(0, 0.95, 0)`，正好在每个座位相机的**视线中轴**上，消除竖排牌的透视侧斜。
- `PENDING_Y` 为常量（可调）。

## 6. 边界与决策

- **相机俯视角度**：卡面法线只水平（不抬到相机高度），故相机从上向下看是"斜看一块竖牌"，符合"垂直于牌桌"。
- **非行动者视角**：`pending` 无 `rank` → `setup({})` → 显示卡背；朝向仍正对镜头。
- **位置与朝向解耦**：位置来自场景牌堆中点（一次性），朝向每帧刷新；`render()` 不重设 transform，billboard 不被状态广播冲掉。
- **默认准星**：相机取景仍对准桌心。两堆对称挪开后桌心不再有牌堆，默认准星落在桌心（空桌面），抽牌时需瞄准左侧抽牌堆；`verify_table3d_interaction` 的"默认准星指向牌堆"改为"瞄准抽牌堆后命中"。
- **不做**：完全 billboard、随行动者座位固定朝向（用户已选"每客户端面向自己镜头"）。

## 7. 测试与验收

更新 `tests/verify_table3d_interaction.gd`（headless，实例化 `table3d.tscn` + 真实 `Camera3D`）：

- **位置**：`render()` 后大牌本地位置 ≈ 抽牌堆/弃牌堆 XZ 中点、`y == PENDING_Y`。
- **竖立**：`update_facing()` 后大牌 basis 的 +Z（`basis.z`）与 `Vector3.UP` 夹角 ≈ 0（容差）。
- **朝向相机**：basis 的 +Y 与"卡→相机水平方向"夹角 ≈ 0，且 `basis.y.y ≈ 0`（水平、无俯仰）。
- **标签**：`CardBlock.set_upright(true)` 后 `_label.position.z > 0`、`y ≈ 0`；`set_upright(false)` 恢复。
- **拾取**：竖立后大牌仍可被准星命中（可选：`pick_center` 指向大牌返回 `kind=="pending"`）。
- **回归**：`verify_table3d`、`verify_table3d_mouse`、`verify_table3d_exchange`、`verify_card_fly` 全绿（大牌位置变化仅影响飞牌起点，断言不依赖固定起点）。

**验收闸门**

1. 新增断言全绿；
2. `tools/run_all_tests.sh` 全量全绿；
3. `git diff` 确认 `scripts/core/*`、`scripts/net/*`、`scenes/ui/table3d.tscn`、2D 相关文件（`game_view.gd`/`card_view.gd`/`card_animator.gd`/`reveal_controller.gd`）零改动。

## 8. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/table3d_view.gd` | `PENDING_Y` 常量；`_bind()` 设大牌中点位置；`update_facing()` 每帧 yaw-billboard；`render()` 设 `set_upright(true)` |
| `scenes/ui/table3d.tscn` | 两堆沿 X 关于桌心对称：`Deck`/`DeckCount` → `x=-0.45`、`DiscardTop` → `x=+0.45`、`KongBell` → `x=-1.2` |
| `scripts/ui/card_block.gd` | 新增 `set_upright(on)`（标签 +Z / +Y 切换，默认关） |
| `scripts/ui/main.gd` | `_process()` 追加 `table3d.update_facing()` |
| `tests/verify_table3d_interaction.gd` / `verify_table3d.gd` | 竖立/朝向/位置/标签/拾取断言；大牌位于桌心正上方、两堆对称、默认准星改为瞄准抽牌堆后判定 |
| `docs/功能实现文档.md` / `docs/AI_AGENT_交接说明.md` | 补一句"3D 大牌竖立悬浮 + 面向玩家" |

**不改**：`scripts/core/*`、`scripts/net/*`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`、`card_fly*.gd`。

## 9. 参数（初值，可调）

| 常量 | 初值 | 说明 |
| --- | --- | --- |
| `PENDING_Y` | `0.95` | 大牌中心离桌高度（竖直后底≈0.45、顶≈1.45） |
| 中点 | 抽牌堆/弃牌堆 XZ 中点 | 当前 ≈ `(0.45, -, 0)`，随场景牌堆位置自动计算 |
