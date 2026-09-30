# KONG 3D 桌面对局（Milestone 2：准星点击 / 可玩）设计 v1

> **前置**：承接 Milestone 1（`docs/superpowers/specs/2026-09-21-table3d-readonly-preview-design.md`）。本里程碑把只读预览做成**可点击、可完整打完一局**的 3D 视角。**规则 / 服务器权威 / 私有快照 / 网络协议 / `scripts/core/*` / `scripts/net/*` / 现有测试零改动**：点击只把既有 `request_*` 意图接上新的输入源。交互逻辑复用 `GameInteraction`（架构不变量 #2）。无动画（瞬时）。分支 `feature/3d-table`。

## 1. 目标与非目标

**目标**

1. 屏幕中心准星；左键从相机沿准星发射线拾取 3D 对象。
2. 可点对象：玩家手牌槽、抽牌堆、弃牌堆、中央 pending 大牌、3D 操作面板按钮。
3. 点击分发到**既有**入口：`GameInteraction.on_card_pressed` / `GameState.request_take` / `main._on_pending_action` / HUD 动作回调。
4. 3D 操作面板（准星可点）：`Ready`、`Kongbaya`、Q 决策（不交换 / 交换）、`变换 Joker`。提示文案/回合/日志用 `Label3D`（复用 `main._hint_for`）。
5. 可操作性高亮：`GameInteraction.card_actionable` → 方块材质变色。
6. 瞬时揭示：看牌/贴牌判定把目标方块**瞬时**翻到正面点数 + 着色（绿/红/蓝），~1.5s 后恢复；无动画。
7. 2D 模态（结算 / 商店 / Joker / 比拼 / 重连）打开时指针可用（见 §6）。

**非目标**

- 不做动画 / 飞牌 / 翻牌过渡 / 光晕描边。
- 不做 3D 结算页 / 商店 / 大厅（继续用 2D 覆盖层）。
- 不做贴图卡面（继续方块 + `Label3D`）。
- 不做遗物栏 3D 交互。
- 不改任何 `request_*` / RPC / 快照字段。

## 2. 拾取（Picking）

- **层**：`Table3dLayout.PICK_LAYER := 2`（物理层 2），`PICK_MASK := 1 << (PICK_LAYER - 1)`。所有可点 `Area3D` 用 `collision_layer = PICK_MASK`，`collision_mask = 0`。
- **可点对象**：每个 `CardBlock` 内挂 `Area3D` + `CollisionShape3D(BoxShape3D = BLOCK_SIZE)`；抽牌堆/弃牌堆/pending/HUD 按钮同样挂 `Area3D` + 对应 `BoxShape3D`。
- **metadata**：`Area3D.set_meta("pick", {...})`：
  - `{"kind": "slot", "seat": int, "slot": int}`
  - `{"kind": "deck"}` / `{"kind": "discard"}` / `{"kind": "pending"}` / `{"kind": "hud", "action": String}`
- **射线**：从相机屏幕中心投射：
  ```gdscript
  var from := cam.project_ray_origin(center)
  var to := from + cam.project_ray_normal(center) * RAY_LENGTH   # RAY_LENGTH=100
  var q := PhysicsRayQueryParameters3D.create(from, to)
  q.collide_with_areas = true
  q.collide_with_bodies = false
  q.collision_mask = Table3dLayout.PICK_MASK
  var hit := get_world_3d().direct_space_state.intersect_ray(q)
  ```
  命中则取 `hit.collider.get_meta("pick")`，否则空字典。

## 3. 点击分发（逻辑零改动）

`main._table3d_click()` 按 `kind` 分发：

| kind | 调用 |
| --- | --- |
| `slot` | `interaction.on_card_pressed(seat, slot)`（复用现成状态机 → `request_replace/use_ability/slap/...`） |
| `deck` | `_on_deck_pressed()` |
| `discard` | `_on_discard_pressed()` |
| `pending` | `_on_pending_action()`（能力牌 → `_begin_ability()`；否则弃抽到的牌） |
| `hud` | `_on_table3d_hud(action)` |

`hud` action 映射：`ready` → `game_view._ready_clicked = true; GameState.request_initial_ready()`；`kongbaya` → `_request_kongbaya()`；`q_keep` → `GameState.request_q_decision(false, -1, _next_action_id())`；`q_exchange` → `request_q_decision(true, -1, ...)`；`joker` → `_open_joker_transform_panel()`。

## 4. 3D 操作面板（HUD）

- 位置：viewer 座位内侧上方，一组沿水平排列的扁方块（`BoxMesh`，如 `0.9 × 0.28 × 0.04`），每个上方/前方 `Label3D` 显示文字。
- 内容由快照+阶段决定，**复用现有判定**：
  - `INITIAL_PEEK` 且未 ready → `Ready（n/N）`
  - `TURN_DRAW` 且当前玩家 → `🔔 KONGBAYA`（`current` 时可用）
  - `Q_DECISION` 且 `own_viewed` → `不交换` / `交换`
  - `TURN_DECISION` 持 Joker 遗物且 pending 为 JOKER → `变换 Joker`
- 按钮可点性（禁用态）由同一逻辑决定；禁用时材质变暗。
- HUD 与座位标签同属 viewer 视角（`Label3D` billboard）。

## 5. 高亮与揭示（瞬时）

- **可操作高亮**：`Table3dView.render(state, actionable: Callable = Callable())`；对每个槽位调用 `actionable.call(seat, slot)` → `CardBlock.set_actionable(on)`（金色 albedo；与 `protected` 紫色、未知灰冲突时优先级：protected > actionable > 分类色）。
- **瞬时揭示**：`CardBlock` 记住最近一次 `setup(slot)` 的数据，并提供 `reveal(card)`（瞬时正面 + 可选着色）与 `restore()`（回到最近 slot 状态）。
  - `Table3dView.reveal_slot(seat, slot, card, color, dur)`：查 `_card_blocks[seat][slot]` → `reveal(card)`；`dur` 秒后 `restore()`（回调前 `is_instance_valid` 检查）。
  - `Table3dView.flash_slot(seat, slot, color, dur)`：仅染色的短暂高亮（不翻面），用于他人查看提示。
  - `main` 在 3D 激活时接管：
    - `_show_private_reveal` → 若 3D 激活且 `target` 含 `slot`，对每张 reveal 调 `reveal_slot`（看牌=蓝，贴牌 `correct` → 绿 / 否则红）；`target` 缺 `slot` 时回退原 2D 揭示（不静默丢弃）。
    - `_on_peek_highlight` → 3D 激活时 `flash_slot(pid, slot, PEEK_GLOW_COLOR, ...)`。
- 目标槽位在 3D 中不存在（如已重建）则忽略，不报错。

## 6. 指针与 2D 模态（对草案的优化，请重点审）

草案为「模态打开时自动退出 3D」。**优化为**：保持在 3D，仅在模态打开期间**释放鼠标捕获**（`MOUSE_MODE_VISIBLE`，隐藏准星，暂停环视与准星点击），关闭后自动恢复捕获。理由：系列赛每局结束都会开商店，自动退出会导致每局被踢回 2D，体验断裂。

- `_table3d_modal_open()`：`settlement_page` / `shop_panel` / `joker_panel` / `_duel_panel` / `_reconnect_panel` 任一存在且可见 → true。
- `_sync_table3d_pointer()`：3D 激活时按上式设置鼠标模式与准星可见性；在 `_set_table3d(true)`、模态开/关（`_on_state_updated` 内）各调一次。
- `main._input` 在 3D 激活时：若 `_table3d_modal_open()` → 不消费、不环视（交给 2D 模态）；否则处理退出键 / 环视 / 左键拾取。

## 7. 文件

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/card_block.gd`（改） | 挂 `Area3D`+`BoxShape3D`；`set_pick(meta)`；`set_actionable(on)`；`reveal(card, color)`/`restore()`（记住最近 `setup(slot)`）；`flash(color, dur)` |
| `scripts/ui/table3d_camera.gd`（改） | `camera_node() -> Camera3D` 访问器 |
| `scripts/ui/table3d_picker.gd`（新） | 纯拾取：`static func pick(camera: Camera3D, world: World3D, screen_center: Vector2) -> Dictionary` |
| `scripts/ui/crosshair.gd`（新） | 屏幕中心准星 `Control`（`_draw`，IGNORE） |
| `scripts/ui/table3d_hud.gd`（新） | 3D 按钮组：`set_buttons(Array)`（`[{text, action, enabled}]`）→ 生成可点扁方块 + `Label3D` |
| `scripts/ui/table3d_view.gd`（改） | 建 HUD/准星挂点；`pick_center()`；`reveal_slot`/`flash_slot`；`render(state, actionable)`；登记 `_card_blocks` |
| `scripts/ui/main.gd`（改） | 准星；`_table3d_click`/`_on_table3d_hud`；reveal 接管；`_sync_table3d_pointer`；`_input` 增加左键与模态分支 |
| `tests/verify_table3d_interaction.gd` + `.tscn`（新） | 拾取命中 / 未命中 / HUD 拾取 / 高亮 / 揭示恢复 |

**不改**：`scripts/core/*`、`scripts/net/*`、`scripts/core/hidden_info.gd`、`GameInteraction`、现有测试。

## 8. 测试与验证

`tests/verify_table3d_interaction.gd`（headless）：

1. 拾取命中：构造含 `CardBlock` 的 `Table3dView`，相机朝方块，`pick_center()` 返回 `{kind:"slot", seat, slot}`。
2. 未命中：准星指向空处 → 空字典。
3. HUD 拾取：HUD 按钮在准星下 → `{kind:"hud", action}`。
4. 高亮：`set_actionable(true)` 后 `block.block_color()` 为高亮色；`protected` 优先于 `actionable`。
5. 揭示：`reveal_slot(seat, slot, {"rank":"A","suit":"♥"}, 0.01)` 后该块 `label_text()=="A♥"`；等待后恢复为原（未知→空串）。
6. 相机访问器：`Table3dCamera.camera_node()` 非空且为 `Camera3D`。

**回归**：`tools/run_all_tests.sh --quick`（新增 `table3d_interaction`）+ 编译检查。
**人工验收**：3D 下用准星完成 开局记忆 → 抽牌 → 替牌/弃牌 → 技能 → 贴牌 → 结算；商店/结算等 2D 模态出现时鼠标可用、关闭后自动回到准星环视。

## 9. 风险与边界

| 风险 | 处理 |
| --- | --- |
| 射线命中顺序：同一点命中多个 Area | 取最近命中（`intersect_ray` 默认返回最近）；必要时按距离排序，本轮不做 |
| 准星对准小方块较难 | 卡方块保留原尺寸；HUD 按钮加大；不做吸附/放大（非目标） |
| 模态期间鼠标释放导致 3D 环视卡住 | `_sync_table3d_pointer` 在每次快照后同步，闭合即恢复捕获 |
| 揭示与重建竞态：`render` 重建方块时揭示定时器回调到已释放节点 | 恢复前 `is_instance_valid` 检查；`_card_blocks` 每次 render 重建 |
| `_ready_clicked` 属 `GameView` 私有 | HUD ready 动作显式设置 `game_view._ready_clicked`，与 2D 行为一致 |
| 玩家名等中文 `Label3D` | 依赖系统回退（同 M1），缺字时后续单独处理字体 |

**明确不做**：动画、3D 菜单、贴图卡面、遗物栏、鼠标吸附、多视角同步。
