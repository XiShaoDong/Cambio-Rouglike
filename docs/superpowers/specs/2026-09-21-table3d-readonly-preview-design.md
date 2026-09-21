# KONG 3D 桌面只读预览（Milestone 1）设计 v1

> **前置**：纯客户端展示层新增，目标是把现有 2D 对局投影改为可切换的 3D 桌面**只读预览**，用于验证 3D 布局与鼠标环视手感。**不改**服务器权威 / 私有快照 / 网络协议 / RPC / 任何 `core` 系统；**不做**点击交互与动画（Milestone 2+ 再做）。3D 只消费 `GameState.state_updated` 已有的公开快照字段。分支 `feature/3d-table`。不启 GUI 验证，以编译检查 + 新增 headless 布局单测 + 现有回归兜底。

## 1. 目标与非目标

**目标**

1. 在现有 `scenes/main.tscn`（`Control` 根）内按 `F10` 在 **2D 对局界面**与 **3D 桌面预览**之间切换。
2. 3D 预览只读渲染公开快照：4 个座位的手牌方块、牌堆（抽牌堆数量 / 弃牌顶）、中央 pending 大牌、座位信息（名字 / 张数 / 货币 / 生命）。
3. 鼠标环视：本机座位固定视角，左右（yaw）上下（pitch）查看桌面。
4. 布局数学抽成纯函数 `Table3dLayout`，headless 可断言、可回归。

**非目标（YAGNI，留给后续里程碑）**

- 不做点击 / 拖拽 / 任何交互（`GameInteraction` 完全不动）。
- 不做动画：每次快照全量瞬时重建，无 tween、无插值、无飞牌。
- 不做贴图卡面（`QuadMesh` + `CardAtlas`，留 Milestone 2；届时换 `CardBlock` 实现即可）。
- 不做 3D 大厅 / 商店 / 结算 / 比拼，这些仍用现有 2D 覆盖层。
- 不做遗物栏 3D 展示（座位标签只含名字 / 张数 / 货币 / 生命）。

**零改动**

`scripts/core/*`、`scripts/net/*`、`tests/*`（现有）、`docs/网络协议_V1.md`、`scripts/core/hidden_info.gd`。

## 2. 文件清单

**新增**

| 文件 | 职责 |
| --- | --- |
| `scenes/ui/table3d.tscn` | 3D 场景实体：`Node3D` 根 + `WorldEnvironment` + 相机 rig + 桌面 + `Seats` / `Center` 锚点容器 |
| `scripts/ui/table3d_view.gd`（`class_name Table3dView`） | 预览渲染器：`set_active(bool)`、`render(state)` 全量重建方块、座位标签 |
| `scripts/ui/table3d_camera.gd`（`class_name Table3dCamera`） | 相机 rig：`frame_for_seat(seat, count)` + 鼠标环视（yaw/pitch 夹取） |
| `scripts/ui/card_block.gd`（`class_name CardBlock`） | 单张牌方块视图：`BoxMesh` + 材质 + `Label3D` |
| `scripts/ui/table3d_layout.gd`（`class_name Table3dLayout`） | **纯函数**布局：座位角度、槽位网格坐标、已知牌分类色、尺寸常量 |
| `tests/verify_table3d_layout.gd` + `.tscn` | 布局数学 headless 断言 |

**修改**

| 文件 | 改动 |
| --- | --- |
| `scripts/ui/main.gd` | 懒加载/持有 `table3d`；`_toggle_table3d()`；`_on_state_updated` 在 3D 激活时追加 `table3d.render(state)`；切换时显隐 2D（`background` + `game_panel`）与鼠标模式；`_unhandled_input` 优先处理 3D 环视与 `F10` |
| `scripts/ui/dev_tools.gd` | `F10` 切换 3D 预览；`T` 开发者面板新增「3D 预览」按钮 |

## 3. 3D 场景与布局

```
Table3D (Node3D)
├─ WorldEnvironment                      # 环境光 + 背景色（取 UITheme bg_table），保证方块可辨
├─ CameraRig (Node3D)                    # yaw 绕 Y
│   └─ PitchPivot (Node3D)               # pitch 绕 X，pitch 挂子节点避免 yaw 影响 pitch 轴
│       └─ Camera3D
├─ Table (MeshInstance3D)                # BoxMesh 扁方块当桌面
├─ Seats (Node3D)
│   ├─ Seat0 (Node3D) → NameLabel/StatLabel(Label3D) + HandAnchor(Node3D)
│   ├─ Seat1 ...
│   └─ Seat3 ...
└─ Center (Node3D) → DeckAnchor / DiscardAnchor / PendingAnchor
```

- **座位布局**：本机 `viewer` 固定在近侧（正对相机，角度 `0°`），其余座位沿圆桌**均分**剩余角度（见 §6 `seat_angles`）。座位与角度的对应顺序固定为：`seat` 升序（排除 viewer）依次取 `seat_angles(count)[1..]`，保证同一快照下座位/相机基准一致。2/3/4 人时只启用对应数量的座位锚点，其余隐藏。
- **座位标签**：`Label3D`，`billboard = enabled`（始终朝向相机可读）。文本 = `名字 · n张 · ¥货币 · ♥生命`；离线 / 出局（`offline_players` / `eliminated`）将标签颜色调暗。
- **手牌方块**：卡方块尺寸 `BLOCK_SIZE = Vector3(0.7, 1.0, 0.04)`（5:7 比例）。前 4 张按 2×2 网格，第 5+ 张（罚牌）在网格**上方**按槽号固定向上追加（与 2D `_extra_slot_pos` 同一套概念）。
- **牌堆**：
  - 抽牌堆 = 单块，`Label3D` 显示 `draw_count`。
  - 弃牌堆顶 = 单块；快照 `discard` 非空时按已知牌显示点数标签，否则显示背面。
- **中央 pending 大牌**：单块，略大于手牌；`state.pending` 存在时显示：自己（含 `rank`）显示点数标签 + 分类色；他人（`hidden: true`）显示背面。

## 4. 快照字段 → 3D 表现映射

| 快照字段 | 3D 表现 |
| --- | --- |
| `players[].id` / `name` | 座位锚点选择 + 名字标签 |
| `players[].count` | 标签张数 |
| `players[].currency` / `health` | 标签 `¥` / `♥` |
| `players[].eliminated` / `offline_players` | 标签与方块整体调暗 |
| `players[].slots[]` 有 `"card"` | **已知牌**：`Label3D` 显示 `rank + suit`（如 `A♥`），方块用分类色 |
| `players[].slots[]` 无 `"card"` | **未知牌**：深灰背面方块，无标签 |
| `players[].slots[].protected` | 紫色自发光材质（护盾槽位） |
| `state.draw_count` | 抽牌堆方块标签 |
| `state.discard` | 弃牌顶方块（有 `rank` 则显示点数） |
| `state.pending` | 中央大牌（自己正面 / 他人背面） |
| `state.phase` | 仅用于判断 `GAME_OVER`（此时快照全亮 → 所有槽位显示点数） |

> 已知 vs 未知完全由快照是否含 `"card"` 决定，3D 层不做任何隐私判断（保持架构不变量 #3/#4）。

## 5. 相机与输入

- **取景**：`frame_for_seat(seat, count)` 把 `CameraRig` 放到 viewer 座位位置并朝桌心；yaw 基准 = 朝桌心方向。左右对手在画面两侧、对面在正前方。
- **环视**：3D 模式下 `Input.mouse_mode = MOUSE_MODE_CAPTURED`；`InputEventMouseMotion` → `yaw += relative.x * sens`，`pitch += relative.y * sens`。
  - `pitch` 夹在 `±60°`（看不到桌底）。
  - `yaw` 夹在基准朝向 `±90°`（看不到身后）。
- **切换**：`F10`（`dev_tools` 转发 `main._toggle_table3d()`）：
  - 进入 3D：隐藏 `background` + `game_panel`（**必须隐藏 `background`**——Godot 4 中 `CanvasItem` 恒绘制在 3D 之上），`table3d.set_active(true)`，`render(latest_state)`，捕获鼠标。
  - 退出 3D：`set_active(false)`，恢复 `MOUSE_MODE_VISIBLE`，显回 2D 并 `_render_game()`。
  - 3D 模式下 `ESC` 先退出 3D（不开设置菜单），再按 `ESC` 才开设置。
- **不破坏既有输入**：3D 模式下不接管空格 / 比拼 / 看牌等；离开 3D 或对局中止 / 回大厅 / 窗口关闭时强制退出 3D 模式并恢复鼠标。

## 6. Table3dLayout 纯函数接口

```gdscript
class_name Table3dLayout
extends RefCounted

const BLOCK_SIZE := Vector3(0.7, 1.0, 0.04)
const BLOCK_GAP := Vector3(0.06, 0.06, 0.0)
const TABLE_RADIUS := 3.2
const SEAT_RADIUS := 2.4
const UNKNOWN_COLOR := Color(0.20, 0.20, 0.22)

# 座位角度（度）：viewer 固定 0°（近侧，正对相机），其余沿圆均分。
# count=2 -> [0,180]；count=3 -> [0,120,240]；count=4 -> [0,90,180,270]。
static func seat_angles(count: int) -> Array

# 槽位 -> 网格坐标（列, 行）：前 4 张 2×2（列=i%2, 行=i/2）；
# 第 5+ 张向上追加（idx=i-4, 列=idx%2, 行=-(1+idx/2)）。行向下为正，追加行为负。
static func slot_grid_pos(slot_index: int) -> Vector2

# 已知牌分类色（仅展示区分）：JOKER 红、A 金、J/Q/K 紫、7-10 蓝、2-6 灰蓝。
static func known_color_for_rank(rank: String) -> Color

# slot 字典 -> 颜色：含 "card" 用 known_color_for_rank(rank)，否则 UNKNOWN_COLOR；
# protected 由 CardBlock 另行叠加紫色自发光。
static func slot_color(slot: Dictionary) -> Color
```

- `seat_angles` 由 `table3d_camera` / `table3d_view` 共同使用，保证座位与相机基准一致。
- 布局数学与 2D 的 `_extra_slot_pos` 概念一致但独立实现，避免耦合。

## 7. 测试与验证

`tests/verify_table3d_layout.gd`（headless，不启 GUI）：

1. `seat_angles(2) == [0,180]`、`(3) == [0,120,240]`、`(4) == [0,90,180,270]`。
2. `slot_grid_pos`：`0→(0,0)`、`1→(1,0)`、`2→(0,1)`、`3→(1,1)`、`4→(0,-1)`、`5→(1,-1)`、`6→(0,-2)`。
3. `known_color_for_rank("JOKER"|"A"|"K"|"7"|"2")` 两两不同且为预期色。
4. `slot_color({"card":{"rank":"A"}})` == `known_color_for_rank("A")`；`slot_color({})` == `UNKNOWN_COLOR`；`slot_color({"card_id":"x"})` == `UNKNOWN_COLOR`（无 `card` 视为未知）。
5. `BLOCK_SIZE` 宽高比 ≈ 0.7（5:7）。

**验证命令**

```bash
# 编译检查
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
# 新增布局单测
... --headless --path . res://tests/verify_table3d_layout.tscn
# 回归（确认零影响）
... --headless --path . res://tests/verify_protocol.tscn
... --headless --path . res://tests/verify_net.tscn -- -role host
... --headless --path . res://tests/verify_net.tscn -- -role client
```

> 3D 渲染本身不做 headless 断言；布局数学由 §7 覆盖。GUI 手感（环视、取景）由人工在编辑器/运行时确认。

## 8. 风险与边界

| 风险 | 处理 |
| --- | --- |
| `CanvasItem` 恒在 3D 之上，2D `background` 会盖住 3D | 进入 3D 模式必须隐藏 `background`（硬性步骤），并在退出时恢复 |
| 鼠标捕获与 `ESC` 设置菜单冲突 | 3D 模式下 `ESC` 先退出 3D；退出后恢复 `MOUSE_MODE_VISIBLE` |
| `Label3D` 中文字体 | 项目无自定义字体，依赖系统回退；若缺字，给 `Label3D` 显式指定项目/系统字体（不改 2D 主题） |
| `Node3D` 挂在 `Control` 根下 | 同一 `Viewport` 的 `World3D` 内正常渲染；用 `set_active` 控制可见性与处理开销 |
| `GAME_OVER` 时 2D 结算页会盖在 3D 上 | 视为期望行为（只读预览 + 2D 结算），不专门处理 |
| 对局中止 / 回大厅 / 关窗时仍处 3D | 统一在离开路径调用退出 3D 并恢复鼠标 |

**明确不做**：交互、动画、贴图卡面、3D 菜单、遗物栏、多人视角同步（每人本地各看各的座位）。
