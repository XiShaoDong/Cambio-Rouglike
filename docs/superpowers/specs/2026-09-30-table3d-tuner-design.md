# KONG 3D 桌面调参工具（Table3D Tuner）设计 v1

> **目的**：为开发者提供一个**独立沙盒场景**，实时调整 3D 桌面的**相机参数**、**座位半径/整体角度**、**桌面与卡牌尺寸**、**玩家建模（Avatar）位置**、**HUD/大牌高度**，并把结果**由开发者手动**写回源文件。
> **纯开发工具**：不改规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*`；**不修改任何既有文件**（只新增），运行时通过实例化 `table3d.tscn` 复用真实骨架。

## 1. 背景与问题

- 相机关键参数 `EYE_HEIGHT` / `CAMERA_BACK` / `MOUSE_SENSITIVITY` 是 `CameraRig` 上的 `@export`，值存在 `scenes/ui/table3d.tscn`。
- 座位半径 `SEAT_RADIUS`、角度 `ANGLE_ORDER`、桌面/卡牌尺寸 `TABLE_RADIUS` / `BLOCK_SIZE` / `BLOCK_GAP` 是 `scripts/ui/table3d_layout.gd` 的**常量**。
- `Table3dView.render()` 每帧用这些常量重算座位与 Avatar 位置，因此在编辑器里拖动 `SeatN` / `Avatar` 节点**会被运行时覆盖**；HUD 位置、大牌高度同样是代码算的。
- 结果：只改编辑器不可行，只改代码要反复重启验证，**调起来很难**。

## 2. 目标与非目标

**目标**

1. 独立场景打开即见真实 3D 桌面（复用 `table3d.tscn` 静态骨架 + 自建样例牌），无需连服务器。
2. 实时滑条调参，改一下立刻看到结果。
3. 参数分五组：相机、座位、桌面/卡牌、玩家建模、HUD。
4. **写回完全由开发者手动触发**：逐文件勾选 + 点「写回」才写；工具绝不自动改文件。
5. 写回前做冲突检查，避免覆盖其他 agent 正在编辑的文件。
6. 提供「重新解析」从源文件读回当前值、「重置默认」、「复制片段」。

**非目标**

- 不改任何既有文件的**代码逻辑**（写回仅替换既有常量/属性行的数值）。
- 不做编辑器插件（不新增 `addons/`、不改 `project.godot`）。
- 不做运行时对局内调参浮层（不碰 `main.gd` / `dev_tools.gd`）。
- 不做规则的实时仿真（样例牌为静态展示）。

## 3. 隔离原则（多 agent 无冲突）

- **本工具只新增文件**，运行期不触碰 `main.gd` / `table3d_view.gd` / `card_block.gd` / `board3d.gd` 等被其他 agent 占用的文件。
- 沙盒**不调用** `Table3dView.render()`（避免依赖正在改动的动态渲染路径）。座位/Avatar 由工具按与运行时**相同的公式**自行定位；样例牌用 `CardBlock.new()` 自建。
- 写回是**运行时按开发者指令**发生的动作，不预先改任何文件。

## 4. 架构与组件（均为新增文件）

| 文件 | 职责 |
| --- | --- |
| `scenes/dev/table3d_tuner.tscn` | 沙盒根场景：`Node3D` + `table3d_tuner.gd`，并内嵌 `table3d.tscn` 实例与左侧 UI 层 |
| `scripts/dev/table3d_tuner.gd` | 主控：加载/实例化 `table3d.tscn`、自建样例牌、按参数应用节点变换、构建调参 UI、处理按钮 |
| `scripts/dev/table3d_tuner_model.gd` | **纯数据 / 纯函数**：参数表 + 默认值 + 从源文件解析当前值 + 生成「写回片段」+ 序列化文本（headless 可测） |
| `scripts/dev/table3d_tuner_writer.gd` | 写回引擎：锚点正则替换、目标文件状态检查（git 脏）、`.bak` 备份、只替换目标数值 |
| `tests/verify_table3d_tuner.gd` + `.tscn` | headless 单测 |

### 4.1 沙盒如何摆出画面

1. 实例化 `res://scenes/ui/table3d.tscn` 作为子节点（静态骨架：WorldEnvironment / CameraRig / Table / TableEdge / Seats(Seat0..3 + HandAnchor + Avatar(Head+Body)) / Center(Deck/DiscardTop/Pending/KongBell) / Hud 全部来自场景）。
2. 通过公开 API 填充可视内容：`Hud.set_buttons([...])`、`Camera.frame_for_seat(angle)`、`Center` 节点沿用场景坐标。
3. 自建样例牌：对每个 `Seats/SeatN/HandAnchor` 用 `Table3dLayout.slot_grid_pos()` 的同一套定位规则放 4-6 张 `CardBlock`（正/背面混合，便于看尺寸与朝向）。
4. 应用参数时，用与运行时一致的公式：
   - 座位世界坐标：`dir(angle) * SEAT_RADIUS`，朝向 `angle + 180`（`Table3dView._seat_world` 同式）。
   - Avatar 本地位置：`Vector3(0, EYE_HEIGHT, -CAMERA_BACK)`（`Table3dView._apply_avatar` 同式，故相机与建模位置物理一致）。
   - 相机：`CameraRig.EYE_HEIGHT/CAMERA_BACK/MOUSE_SENSITIVITY` 直接赋值；基准朝向 `frame_for_seat(angle + 角度偏移)`。
   - HUD：`Hud.position = dir * (SEAT_RADIUS - HUD_OFFSET) + (0, HUD_HEIGHT, 0)`，朝向 `angle + 180`（同 `render()`）。
   - 大牌：`Center/Pending.position` 的 XZ 取抽牌堆/弃牌堆中点，`y = PENDING_Y`。
5. 每帧仅做 `set_facing` 性质的朝向刷新（大牌/HUD）与鼠标环视（沿用 `Table3dCamera.look`）。

## 5. 调参项与写回映射

| 组 | 参数 | 源文件（写回目标） | 锚点 |
| --- | --- | --- | --- |
| 相机 | `EYE_HEIGHT` / `CAMERA_BACK` / `MOUSE_SENSITIVITY` | `scenes/ui/table3d.tscn`（CameraRig） | `EYE_HEIGHT = <num>` 等 |
| 座位 | `SEAT_RADIUS`、**整体角度偏移**（统一旋转四座） | `scripts/ui/table3d_layout.gd` | `const SEAT_RADIUS := <num>` |
| 桌面/卡牌 | `TABLE_RADIUS` + 桌面网格尺寸、`BLOCK_SIZE`、`BLOCK_GAP` | `scripts/ui/table3d_layout.gd` + `table3d.tscn` | `const TABLE_RADIUS := <num>` / `size = Vector3(...)` |
| 玩家建模 | Body / Head 局部高度（Avatar 整体随相机 eye/back，二者物理一致） | `scenes/ui/table3d.tscn` | Body/Head 的 `Transform3D(...)` translation |
| HUD | `HUD_OFFSET` / `HUD_HEIGHT` / `PENDING_Y` | `scripts/ui/table3d_view.gd` | `const HUD_OFFSET := <num>` 等 |

- 座位角度：**四座统一**。暴露一个「整体角度偏移」滑块，作用于所有座位（旋转整个圆环）；不逐座编辑，避免与 2D 箱位对齐语义冲突。
- 桌面网格尺寸与 `TABLE_RADIUS` 语义一致（边长 = 2 × TABLE_RADIUS），工具保持二者联动。

## 6. 写回：完全由开发者触发（关键）

- **绝不自动写**。UI 列出所有写回目标文件，每个带勾选框，默认**不勾选**；只有开发者勾选后点「写回」才执行。
- **冲突检查**：写回前对每个被勾选文件执行 `git status --porcelain -- <file>`：
  - 干净 → 可写；
  - **有未提交改动（可能正被其他 agent 编辑）→ 默认拦截**，该行标红「占用中」并禁用；提供显式「仍要覆盖」开关，由开发者判断后手动打开（默认关）。
- **只替换目标数值**：用属性名/常量名锚定的正则，仅替换匹配行，不新增/删除其他内容；`.tscn` 变换只替换 translation 分量，不改结构与 UID。
- **备份**：写入前把原文件复制为 `<file>.bak`。
- **反馈**：写回后在 UI 显示每个文件的「已写 / 已拦截（原因）/ 失败」，并提示可用 `git diff` 复核。

## 7. UI（左侧开发者面板）

- 五组折叠区（相机 / 座位 / 桌面·卡牌 / 玩家建模 / HUD），每项一行：标签 + `Slider` + 数值 `Label`（可精确输入 `SpinBox`）。
- 底部按钮：**重置默认** / **重新解析源文件** / **复制参数片段**（GDScript 片段到剪贴板）。
- 写回区：目标文件列表（勾选框 + 状态徽标）；**写回** 按钮。
- 顶部提示：鼠标移动环视（`Input.MOUSE_MODE_CAPTURED`），`Esc` 释放鼠标以便操作 UI。
- 键盘（开发者自用）：`R` 重置、`Enter` 写回（仅在鼠标释放态生效，避免误触）。

## 8. 测试与验收

headless 单测 `tests/verify_table3d_tuner.gd`：

- **model**：默认值表完整；解析现有源文件得到预期当前值；生成片段文本与参数一致。
- **writer**：锚点正则只替换目标行、相邻行/注释/格式不变；`.tscn` 属性替换正确且不破坏 `Transform3D` 其余分量；脏文件默认拦截；`force` 才写；写出与 `.bak` 内容。
- **隔离**：测试运行后 `git status` 仅显示新增文件（断言不产生对既有文件的意外改动）。
- **回归**：`verify_table3d_layout`、`verify_table3d`、`verify_table3d_mouse` 不受影响（本工具不改其代码）。

**验收闸门**

1. 手动打开 `scenes/dev/table3d_tuner.tscn`，可见真实桌面并能实时调参。
2. 新增单测全绿。
3. `git status` / `git diff` 确认本次仅新增文件，未改动既有文件。

## 9. 边界与决策

- **相机与建模位置物理一致**：当前设计里相机就在 viewer 头心，故「调相机」与「调模型眼位」是同一组值；不想解耦（解耦需改 `table3d_view.gd`，属被占用文件）。
- **样例数据静态**：不模拟对局，仅用于几何调参。
- **写回是文本替换**：不通过编辑器 API 保存场景；锚点不匹配时该文件写回失败并提示，绝不猜测。
- **`table3d_view.gd` 被占用时**：HUD/`PENDING_Y` 写回会被冲突检查拦下；开发者可先只写其他文件，待该文件空闲再写。

## 10. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scenes/dev/table3d_tuner.tscn` | 新增：沙盒场景 |
| `scripts/dev/table3d_tuner.gd` | 新增：主控 |
| `scripts/dev/table3d_tuner_model.gd` | 新增：纯数据/纯函数 |
| `scripts/dev/table3d_tuner_writer.gd` | 新增：写回引擎 |
| `tests/verify_table3d_tuner.gd` / `.tscn` | 新增：单测 |

**不改**：`scripts/core/*`、`scripts/net/*`、`scenes/ui/table3d.tscn`（仅由工具在开发者指令下写回数值）、`scripts/ui/*`（同上）。

## 11. 参数（默认值，解析前）

| 组 | 参数 | 初值 |
| --- | --- | --- |
| 相机 | `EYE_HEIGHT` / `CAMERA_BACK` / `MOUSE_SENSITIVITY` | 3.5 / 1.5 / 0.35 |
| 座位 | `SEAT_RADIUS` / 整体角度偏移 | 2.4 / 0.0 |
| 桌面·卡牌 | `TABLE_RADIUS` / `BLOCK_SIZE` / `BLOCK_GAP` | 3.5 / (0.7,0.04,1.0) / (0.06,0,0.06) |
| 玩家建模 | Body Y / Head Y | -0.6 / 0.0 |
| HUD | `HUD_OFFSET` / `HUD_HEIGHT` / `PENDING_Y` | 0.55 / 0.5 / 0.75 |

（初值仅用于首次显示；打开时以「重新解析」读到的源文件实际值为准。）
