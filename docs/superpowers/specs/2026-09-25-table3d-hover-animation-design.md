# KONG 3D 桌面 hover 抬起/倾斜动效接入 设计 v1

> **前置**：承接沙盒动效 spec（`docs/superpowers/specs/2026-09-25-card-animation-sandbox-design.md`）。本设计把沙盒验证过的 **hover 抬起 + 朝玩家倾斜** 接入正式 3D 桌面（`table3d`），**仅作用于 viewer 自己的手牌槽**。**规则 / 协议 / 快照 / `request_*` / `scripts/core/*` / `scripts/net/*` 零改动**；纯客户端展示层。分支 `feature/card-animation`。

## 1. 目标与非目标

**目标**

1. 3D 桌面中，准星 hover 到 **viewer 自己的手牌** 时：卡牌抬起 + 朝玩家倾斜（含离桌补偿），离开时缓动落回。
2. 拾取判定**不受动画影响**（拾取盒固定在基准位，不随动画移动）→ 不出现 hover 边缘抖动。
3. 跨 `table3d_view.render()` 全量重建**保持** hover 态（不因每次快照重建而弹跳）。
4. 非 viewer 手牌、中央牌堆（deck/discard/pending）、HUD 行为保持不变（仅既有边缘发光）。

**非目标**

- 不做 press 压缩、真实 3D 翻转替换揭示、blob 阴影、idle 悬浮。
- 不做他人手牌 / 中央牌堆的抬起。
- 不改 2D 棋盘、不动规则/协议/快照/`request_*`。
- **本期不做 hover 缩放**（`hover_scale`）：先只做位移 + 旋转；后续可在 `_visual` 上安全补加（与揭示已分节点）。

## 2. 现状（关键约束）

- `table3d_view.render(state, actionable)` 每次状态广播**全量销毁重建**所有 `CardBlock`（`_card_blocks` 重建）。
- `main._process` 每帧调 `table3d.update_hover()`；`update_hover()` 用屏幕中心 `Table3dPicker.pick_hit` 命中带 `pick` meta 的 `Area3D`，经 `_apply_hover` → `CardBlock.set_hover(on,color)`（边缘发光）。
- `CardBlock` 当前结构：`Glow*` / `Mesh` / `Label3D` / 拾取 `Area3D` 均为**根的直接子节点** → 移动根会同时移动拾取盒。
- `CardBlock.reveal/restore` 用 `self.scale.x` 做水平翻转；`setup(slot)` 会 `scale = Vector3.ONE`。
- `Table3dPicker.pick_hit` 已返回命中点 `"position"`（沙盒阶段新增）。
- `CardAnimationMath.compose(progress, cfg, idle_time, ray_local)` 为纯函数，可复用其 hover 位移/旋转（含离桌补偿）。

## 3. 设计

### 3.1 CardBlock 视觉 pivot（防抖核心）

- `_build()` 新增根子节点 `_visual: Node3D`，把 `Glow*` / `Mesh` / `Label3D` 挂到 `_visual` 下；**拾取 `Area3D` 留在根**。
- 揭示的 `scale.x` 水平翻转**保持作用于根 `self.scale`（不改）**，与 `_visual` 的 hover 位移/旋转不抢属性（`Basis` 会重置 scale，故两者必须分节点）；`setup(slot)` 额外复位 `_visual` 的 hover pose。
- 结果：hover 动画只移动 `_visual`，根与拾取盒静止 → hover 判定稳定。

### 3.2 CardBlock hover pose 驱动

- 字段：
  - `var hover_anim_enabled := false`（仅 viewer 自己槽置 true；关闭时 `_process` 不工作）
  - `var _hover_p := 0.0`、`var _ray_local := Vector2.ZERO`
- 方法 `set_hover_pose(on: bool, ray_local: Vector2, immediate := false) -> void`：
  - 记录 `_ray_local`；
  - `immediate=true` 直接 `_hover_p = 1/0`（跨 render 重放用，不缓动）；
  - 否则用 tween 缓动 `_hover_p`（进 `TRANS_BACK/EASE_OUT`、出 `TRANS_CUBIC/EASE_OUT`，时长取 `CardAnimationConfig.hover_in_dur/hover_out_dur`）。
- `_process(delta)`：若 `hover_anim_enabled` 且 `_visual != null` → 调
  `CardAnimationMath.compose({"hover": _hover_p, "press": 0, "flip": 0, "land": 0}, cfg, 0.0, _ray_local)`，把 `visual_pos`（`Vector3`）与 `visual_rot_deg`（Euler→`Basis`）应用到 `_visual`；**不动 `_visual.scale`**（留给揭示翻转）。
- 配置：CardBlock 持有共享 `static var _anim_cfg: CardAnimationConfig`（懒建），仅用 hover 相关参数；不启用 idle/阴影。
- 测试访问器：`func visual_node() -> Node3D`（返回 `_visual`）、`func hover_progress() -> float`（返回 `_hover_p`）——避免测试直接摸私有字段。

### 3.3 table3d_view 接入

- 新增 `var _viewer := 0`、`var _hover_slot := {}`（`{"seat":int,"slot":int}` 或空）。
- `render()`：
  - 记 `_viewer = int(state.get("viewer_id", 0))`；
  - 每个槽创建后：`block.hover_anim_enabled = (seat == _viewer)`；
  - 全部座位渲染完成后：若 `_hover_slot` 仍存在且属 viewer，调该块 `set_hover_pose(true, ray_local, true)`（**immediate**，避免重建后弹跳）。
- `update_hover()`：
  - 命中 `{"kind":"slot", seat, slot}` 时，算 `ray_local`（`block.global_transform.affine_inverse() * hit.position` 按卡尺寸归一化 clamp −1..1）；
  - 维护 `_hover_slot`：变更时对旧槽（若 own）`set_hover_pose(false)`、对新槽（若 own）`set_hover_pose(true, ray_local, false)`；未变更且 own 时每帧 `set_hover_pose(true, ray_local)` 跟新倾斜；
  - 既有边缘发光（`set_hover`）行为不变（所有卡）。
- `clear_hover()`：清 `_hover_slot` 并对旧槽 `set_hover_pose(false)`。

### 3.4 main.gd

- 不改（`_process` 已每帧 `update_hover`；`_on_state_updated` 已调 `render`）。

## 4. 测试与验收

扩展 `tests/verify_table3d_interaction.gd`（headless）：

1. **own 槽 hover 抬起**：构造含 viewer 自己槽的 `Table3dView`，对 own 槽 `set_hover_pose(true, 0)` → 步进若干帧 → `block.visual_node().position.y > 0`。
2. **非 own 槽不动**：对非 viewer 槽 `set_hover_pose(true,0)`（或 `hover_anim_enabled=false`）→ `visual_node().position` 保持不变。
3. **拾取盒不位移**：own 槽 hover 抬起后，`block.position`（基准）不变、其 `Area3D` 全局位置不变。
4. **跨 render 保持**：设 `_hover_slot` 为 own 槽 → 再 `render()` → 该槽 `hover_progress() == 1` 且 `visual_node().position.y > 0`（即时，不缓动）。
5. **离开落回**：`set_hover_pose(false)` → 步进 → `visual_node().position.y` 回落 ≈0（`hover_progress() == 0`）。
6. **既有能力不回归**：reveal 水平翻转仍生效（标签/贴图状态正确）；`verify_table3d`（36/36）与 `verify_table3d_interaction` 原有断言全绿。

**验收闸门**：`verify_table3d` + `verify_table3d_interaction` + `verify_card_animation` + 全量 `run_all_tests.sh --quick` 全绿；人工：3D 下准星移到自己手牌抬起/倾斜、移开落回、每次动作后不弹跳。

## 5. 文件

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/card_block.gd`（改） | `_visual` 视觉 pivot；`reveal/restore/setup` 作用于 `_visual`；`hover_anim_enabled` + `set_hover_pose` + `_process` |
| `scripts/ui/table3d_view.gd`（改） | `_viewer`/`_hover_slot`；own 槽启用动画；`update_hover` 触发/重定向；`render` 后重放；`clear_hover` 复位 |
| `tests/verify_table3d_interaction.gd`（改） | 上述 6 项 |
| `docs/superpowers/plans/2026-09-25-table3d-hover-animation.md`（新） | 实现计划 |

**不改**：`scripts/core/*`、`scripts/net/*`、`main.gd`、`scenes/ui/table3d.tscn`、`card_animation_math.gd`、`card_animation.gd`、`card_animation_sandbox.gd`、`verify_card_animation.gd`。

## 6. 风险与边界

| 风险 | 处理 |
| --- | --- |
| CardBlock 结构改动影响既有渲染/揭示/拾取 | 回归 `verify_table3d` + `verify_table3d_interaction`；`_visual` 承载原 mesh/label/glow，`Area3D`/材质接口不变 |
| 同一时刻只 hover 一个槽 | 准星唯一，`_hover_slot` 单值 |
| `ray_local` tilt 方向 | 与沙盒同帧（viewer 自己的座位朝向 + 相机在座后），复用同样符号；测试与人工确认 |
| 重建瞬间弹跳 | `_hover_slot` 跨 render 重放，且用 `immediate=true` |
| 与揭示 flip 抢属性 | hover 只写 `_visual` 的 pos/rot；揭示写根 `self.scale.x`，二者分节点不冲突（根缩放会带动 `_visual`，符合揭示整体翻转语义）；hover 不写 `_visual.scale` |
| 打开 2D 模态时 | `main` 已 `clear_hover()` → pose 复位 |

**明确不做**：press、真实翻转、阴影、idle、他人/中央卡抬起、hover 缩放。
