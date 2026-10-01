# KONG 3D 全息看板（悬浮 UI 宿主）设计 v1

> **目的**：3D 模式下，当前所有 2D 模态（结算 / 商店 / Joker 变换 / 比拼 bar / 重连）以及"等待提示"都以全屏 `Control` 挂在 `main` 上，渲染在屏幕空间 → 看起来"像一面墙贴在相机里"，且模态打开时 `_sync_table3d_pointer()` 释放鼠标、`_input` 提前 return → **3D 视角锁死**。
> 本设计把这些 UI 改为**牌桌中心上方、朝向每位玩家（billboard）的半透明全息看板**，交互走**屏幕中心准星**，相机保持可自由环视。
> **纯客户端展示层**：不改规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*`；2D 界面观感与 2D 逻辑逐字不动。

## 1. 目标与非目标

**目标**

1. 3D 模式下所有 2D 模态改为挂载到牌桌中心的 3D 看板上（`SubViewport` 承载现有 `Control` 场景，原样复用）。
2. 看板悬浮于桌面上方、billboard 朝向相机（每位玩家都正面）、半透明全息观感。
3. 交互走准星：相机仍可环视（鼠标保持捕获），用屏幕中心准星悬停/点击看板按钮；键事件（Enter/Esc/空格）仍生效。
4. 无模态时，看板显示一条居中"等待/提示"文本（复用 `main._hint_for()`），否则看板隐藏。
5. 2D 路径与 2D 界面保持逐字不变（只在 3D 分支生效）。

**非目标**

- 不改规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*`。
- 不重写面板 UI（不做原生 3D 按钮/文字重建）。
- 不做 3D 棋盘结算逐张翻牌联动（当前 3D 本就没有，另立需求）。
- 不改 2D 棋盘渲染与 2D 模态观感。

## 2. 架构与组件

新增两个**纯客户端展示层**文件：

### 2.1 `scripts/ui/board_input.gd`（`class_name BoardInput`，纯函数，可 headless 测）

只做坐标换算，无节点依赖：

```gdscript
## 看板本地坐标（quad 平面，XY）→ 归一化 UV（左上为 0,0）。
static func local_to_uv(local: Vector3, size: Vector2) -> Vector2
## 归一化 UV → SubViewport 像素坐标。
static func uv_to_viewport(uv: Vector2, viewport_size: Vector2i) -> Vector2i
## 命中点（世界坐标）→ 看板本地坐标；越界时不 clamp（由调用方判定是否命中）。
static func world_to_local(board_xform: Transform3D, world_pos: Vector3) -> Vector3
```

### 2.2 `scripts/ui/board3d.gd`（`class_name Board3d extends Node3D`）

运行时由 `main` 实例化并 `add_child` 到 `table3d` 下（复用 3D 世界，随 `table3d` 显隐/释放）。全代码构建，不改开发者拥有的 `scenes/ui/table3d.tscn`。

节点结构：

```
Board3d (Node3D)                          # 每帧朝相机（见 set_facing）
├── Screen (MeshInstance3D)               # QuadMesh(BOARD_W × BOARD_H)
│       material_override: albedo_texture = viewport.get_texture()
│                          UNSHADED / TRANSPARENCY_ALPHA / CULL_DISABLED / no_depth_test
├── Pick (Area3D)                         # collision_layer = PICK_MASK
│   └── Shape (CollisionShape3D)          # BoxShape3D(BOARD_W, BOARD_H, 0.02) 薄盒
│         meta "pick" = {"kind": "board"}
├── Viewport (SubViewport)                # 尺寸 BOARD_VIEWPORT，transparent_bg, disable_3d, UPDATE_ALWAYS
│   └── [挂载的面板 Control / 等待提示 Control]
└── Frame (MeshInstance3D, 可选)          # 细发光描边框（accent 色）营造全息感
```

API：

```gdscript
func mount_panel(control: Control) -> void     # reparent 进 Viewport，重设 FULL_RECT，显示看板
func unmount_panel() -> void                    # 取出面板（不 free，调用方决定），隐藏看板
func has_panel() -> bool
func panel() -> Control
func set_banner(text: String) -> void           # 设置等待提示文本（空 → 无内容）
func show_board() / hide_board()
func set_facing(camera: Camera3D) -> void       # 根节点朝向相机（billboard）
func hit_viewport_coord(camera: Camera3D) -> Vector2i   # 屏幕中心射线 → 命中则返回看板像素坐标，未命中返回 (-1,-1)
func push_motion(pos: Vector2i, rel: Vector2) -> void
func push_motion_out() -> void                          # 发送一次移出视口事件，清除面板内 hover
func push_click(pos: Vector2i) -> void
func push_key(event: InputEventKey) -> void
```

- `set_facing`：令根节点看向相机（`look_at(camera.global_position, Vector3.UP)` 后仅保留 yaw/pitch 中的朝向，使 quad 正对相机）；**不用材质 billboard**，这样 `Pick` 碰撞盒随根一起转，射线命中与贴图一致。
- 看板仅在 `has_panel()` 或 `banner 非空` 时 `visible`，其余隐藏。
- 所有尺寸/位置/透明度为 `@export` 常量，可后续在检视面板微调。

## 3. 挂载与生命周期（`main.gd` 改动）

**统一挂载入口**：新增 `_mount_modal(control: Control) -> void`：

- `_table3d_active` 且 `table3d` 有效 → 确保看板存在 → `board.mount_panel(control)`；
- 否则保持现状：`add_child` 到 `main`（比拼 bar 仍 `overlay.add_child`）。

改动的创建点（仅替换挂载父节点，其余逐字不动）：

| 位置 | 现状 | 改为 |
| --- | --- | --- |
| `_open_settlement()` | `add_child(page)` + `z_index=100` | `_mount_modal(page)` |
| `_open_shop_panel()` | `add_child(panel)` + `z_index=90` | `_mount_modal(panel)` |
| `_open_joker_transform_panel()` | `add_child(panel)` + `z_index=95` | `_mount_modal(panel)` |
| `_render_duel()` | `overlay.add_child(_duel_panel)` | `_mount_modal(_duel_panel)` |
| `_show_reconnect_panel()` | `add_child(panel)` | `_mount_modal(panel)` |

面板脚本本身不改（`set_anchors_and_offsets_preset(FULL_RECT)` 在 `SubViewport` 内按视口尺寸解析、`CenterContainer` 自动居中）。**唯二的小改**（去黑底，保留全息观感）：

- `shop_panel.setup(..., dim := true)`：`dim=false` 时 `get_node("Dim").visible = false`。
- `duel_bar.setup(..., dim := true)`：`dim=false` 时不添加全屏半透明遮罩 `ColorRect`。
- 两个面板的 `setup` 调用点上由 `main` 传 `not _table3d_active`。
- `settlement_page` 本就无全屏暗幕，不改。

**指针同步** `_sync_table3d_pointer()`：3D 激活时**恒定 `MOUSE_MODE_CAPTURED`**（不再因模态释放鼠标）；**准星在 3D 激活时恒显示**——无看板面板时作为牌桌拾取准星，有看板面板时作为看板指针（命中看板变金）。

**等待/提示（banner）**：`_on_state_updated()` 末尾（3D 激活时）调用 `board.set_banner(_board_banner_text())`：
- 无任何模态挂载 → `_hint_for(phase, viewer == current_player)` 文本；
- 有模态 → 清空 banner（面板已承载信息）。
- 文本为空（如 LOBBY）→ 看板隐藏。

## 4. 输入转发（准星操控）

3D 激活时 `main._input` 不再对模态整体 `return`：

- **环视**：`InputEventMouseMotion` → 照常 `table3d.camera.look(event.relative)`（视角解锁）。
- **悬停**：`main._process()`（3D、看板有面板时）每帧取屏幕中心 → `board.hit_viewport_coord(camera)`：
  - 命中（坐标非 `(-1,-1)`）→ `board.push_motion(coord, rel)`（按钮 hover 高亮）+ 准星变金；
  - 未命中 → `board.push_motion_out()` 清除看板内 hover；
  - 未命中时仍走既有 `table3d.update_hover()`（可在看板外看/点牌桌）。
- **左键**：`InputEventMouseButton(LEFT, pressed)` → 屏幕中心射线：
  - 命中看板 → `board.push_click(coord)`（合成 `MOUSE_BUTTON_LEFT` 按下+抬起）；
  - 未命中 → 既有 `_table3d_click()`（看/抽/弃/pending/HUD）。
- **键事件**：`InputEventKey` → 当看板有面板时 `board.push_key(event)`（Joker 的 Enter/Esc、商店 Esc）；**空格**继续由 `main._unhandled_input` 处理（比拼 STOP），不转发以防重复触发。
- 面板的回调（`_on_shop_buy` / `_on_joker_confirm` / 结算按钮等）逻辑不变，只是事件来源由真实鼠标变为合成事件。

## 5. 视觉与布局

- **位置**：牌桌中心 `(0, 0, BOARD_Y)`，`BOARD_Y ≈ 1.6`；`set_facing` 每帧朝向相机。
- **尺寸**：quad `BOARD_W ≈ 2.6` × `BOARD_H ≈ 1.8`（约 13:9）；`SubViewport` 尺寸 `1024 × 708`（视觉宽高比一致，避免拉伸）。
- **全息观感**：材质 `albedo_color.a ≈ 0.92` + 细发光描边框；`no_depth_test=true`（不被角色/卡牌遮挡）。
- **居中**：面板的 `CenterContainer` 在 `SubViewport` 内自动居中；等待提示为居中的半透明圆角小面板 + 文本。
- **参数外置**：`BOARD_W/BOARD_H/BOARD_Y/BOARD_VIEWPORT/ALPHA` 等为 `@export` 常量。

## 6. 边界与决策

- **F10/V 在模态打开时**：仍允许切回 2D；切换时把看板上的面板 `unmount_panel()` 后重新挂到 `main`（避免卡死在 3D）；面板状态（如商店已刷新内容）保留。
- **多面板叠加**（重连 + 商店等）：`SubViewport` 内后挂者在上，允许共存；`_mount_modal` 各自独立，不互斥。
- **面板刷新**：`_open_shop_panel` 命中已存在面板时仍调 `setup` 刷新（在视口内同样生效）。
- **切出 3D**：`_set_table3d(false)` 时 `unmount_panel` + 隐看板；在途动画/状态由既有逻辑处理。
- **无状态 / 未激活**：3D 未激活 → 全部走 2D 现状路径（零影响）。
- **GDScript**：`SubViewport.push_input(ev, true)` 传本地坐标即视口像素；`Area3D` 使用既有 `Table3dLayout.PICK_MASK`。
- **性能**：单个 `SubViewport`（`disable_3d`、`UPDATE_ALWAYS`）与既有的 4 个 stat `SubViewport` 同量级，无虞；无面板时 `Screen` 不可见。

## 7. 测试与验收

新增 `tests/verify_board3d.gd` + `.tscn`（headless；实例化 `Board3d`，构造真实 `Camera3D`/`SubViewport`，不启动 GUI）：

- **坐标换算**：`BoardInput.local_to_uv`（四角/中心/尺寸映射）、`uv_to_viewport`（角/中心）、`world_to_local`。
- **挂载/卸载**：`mount_panel` 后面板为 `Viewport` 子节点且 `has_panel()`、看板 `visible`；`unmount_panel` 后无面板、隐藏；面板未被 free。
- **贴图**：`Screen` 材质 `albedo_texture` 来自 `Viewport.get_texture()`。
- **朝向**：`set_facing(cam)` 后看板 `-Z`（或正面法线）与"指向相机"方向夹角 ≈ 0（容差）。
- **输入合成**：看板内放一个 `Button`（或计数 Label），`push_click`(中心坐标) 后按钮 `pressed` 信号触发一次；`push_key(Enter)` 被视口内 `Control` 收到。
- **等待提示**：`set_banner("x")` 后看板可见；`set_banner("")` 且无面板 → 隐藏。
- **回归**：更新受影响的 `verify_table3d_interaction`/`verify_table3d_mouse`（若断言了"模态释放鼠标/丢弃输入"改为"3D 恒定捕获 + 转发"）；`verify_table3d*`、`verify_settlement`、`verify_shop`、`verify_actions` 全绿。

**验收闸门**：

1. 新测试全绿；
2. `tools/run_all_tests.sh` 全量全绿；
3. `git diff` 确认 2D 相关文件（`game_view.gd`/`card_view.gd`/`card_animator.gd`/`reveal_controller.gd`）与 `scripts/core/*`、`scripts/net/*`、`scenes/ui/table3d.tscn` 零改动。

## 8. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/board_input.gd`（新） | 纯函数坐标换算 |
| `scripts/ui/board3d.gd`（新） | 全息看板宿主（SubViewport + billboard quad + 拾取 + 输入合成） |
| `scripts/ui/main.gd` | `_mount_modal` 路由；`_sync_table3d_pointer` 恒定捕获；`_input` 转发（环视/悬停/点击/键）；banner 文本；F10 重挂回 2D |
| `scripts/ui/shop_panel.gd` | `setup(..., dim := true)`，`dim=false` 隐藏 `Dim` |
| `scripts/ui/duel_bar.gd` | `setup(..., dim := true)`，`dim=false` 不加全屏遮罩 |
| `tests/verify_board3d.gd` + `.tscn`（新） | 看板宿主与输入转发测试 |
| `tools/run_all_tests.sh` | 纳入 `verify_board3d` |
| `docs/功能实现文档.md` | 补 `board_input.gd` / `board3d.gd` 映射 |

**不改**：`scripts/core/*`、`scripts/net/*`、`scenes/ui/table3d.tscn`、`settlement_page.*`、`joker_transform_panel.*`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`、`scenes/ui/game_board.tscn`、2D 相关与现有测试（除第 7 节列出的必要断言更新）。

## 9. 参数（初值，可调）

| 常量 | 初值 | 说明 |
| --- | --- | --- |
| `BOARD_W` / `BOARD_H` | `2.6` / `1.8` | 看板世界尺寸（宽 × 高） |
| `BOARD_Y` | `1.6` | 看板中心高度（牌桌中心上方） |
| `BOARD_VIEWPORT` | `1024 × 708` | SubViewport 像素尺寸（与宽高比一致） |
| `BOARD_ALPHA` | `0.92` | 全息透明度 |
| `PICK_MASK` | `Table3dLayout.PICK_MASK` | 复用现有拾取层 |
