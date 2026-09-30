# KONG CardBlock 真实 3D 揭示翻面（双面几何）设计 v1

> **前置**：承接 `docs/superpowers/specs/2026-09-25-table3d-hover-animation-design.md`。本设计把 CardBlock 揭示（看牌/贴牌 `reveal`/`restore`）从 **`scale.x` 水平压扁翻转** 换成 **沙盒同款 3D 翻转**（抬起 + 朝玩家倾斜 + 绕卡长轴 0→180°），并**把卡改成双面几何**以保证翻出牌面正确、不镜像。**规则 / 协议 / 快照 / `request_*` 零改动**。分支 `feature/card-animation`。

## 1. 目标与非目标

**目标**

1. `CardBlock.reveal()/restore()` 采用 3D 翻转：抬起弧线 + 朝玩家倾斜 + 绕卡长轴 0→180°，边对相机时自然换面，末了平放显示新面。
2. 卡为**双面几何**（正面板 + 背面板），翻转后显示的**牌面正确、不左右镜像**。
3. hover 抬起/倾斜（已实现）与揭示翻转**互不冲突**（分节点）。
4. 既有 `has_face_texture/has_back_texture/label_text/block_color/albedo_texture` 语义保持（反映当前**朝上可见面**）。

**非目标**

- 不做 press 压缩、不做 hover 缩放。
- 不改 2D 棋盘（`card_view.gd` 的 2D 翻转不动）。
- 不改规则/协议/快照/`request_*`。
- 不改揭示的**时机/时长契约**（`FLIP_DURATION` 仍用于揭示动画总时长，测试按它等待）。

## 2. 现状

- `CardBlock`：单片 `_mesh`（`PlaneMesh FACE_Y`）+ `cull_disabled` + 单一 `_material`；`reveal`→`_flip_to` 用 `self.scale:x` 1→0（回调换面）→1。
- 已加 `_visual` 视觉 pivot（hover 用 pos/rot），mesh/label/glow 挂其下；拾取 `Area3D` 在根。
- 测试 `verify_table3d_interaction`：`_test_card_block` 断言 `reveal` 后 `label_text`、`has_face_texture`、发光色；`_test_view` 断言 `reveal_slot` 后标签。均按 `CardBlock.FLIP_DURATION` 等待。

## 3. 设计

### 3.1 双面几何（两片 plane，均"正面朝上"）

- `_front`：`PlaneMesh(FACE_Y)`，尺寸 = `BLOCK_SIZE(x,z)`，`_front_mat`，位置 `y = +0.002`；沿用现有 UV 旋转设置。
- `_back`：同样 `PlaneMesh(FACE_Y)` 建为"正面朝上"，`_back_mat`，位置 `y = -0.002`，节点**预旋转 180° 绕卡长轴（本地 Z）** → 静止时其法线朝下（被正面片遮住不可见），整卡翻 180° 后它转到朝上、贴图**正向不镜像**。
- 两片 `cull_mode = CULL_DISABLED`（与现状一致，避免斜视丢面）。
- 保留 `_material` 名指向**正面**材质（减少改动面）；新增 `_back_material`。

### 3.2 节点层级

```
CardBlock(root: PickArea)
└── _visual                # hover 位移/旋转（CardAnimationMath.compose）
    ├── Glow0..2           # 边缘发光（随 hover，不随揭示旋转）
    └── _flip              # 揭示翻转：绕长轴旋转 + 抬起 + 朝玩家倾斜
        ├── _front
        ├── _back
        └── _label
```

- hover 写 `_visual.transform`；揭示写 `_flip.transform`；二者分节点不冲突。
- Glow 放 `_visual` 下（跟随抬手，但不在揭示时被翻成侧立）。

### 3.3 揭示翻转（替换 `_flip_to` 的 scale.x）

- 新增标量 `_reveal_p`（0→1）；`_process` 每帧应用到 `_flip`：
  - `angle = _reveal_p * 180°`（绕本地 Z）
  - `pitch = cfg.hover_pitch * sin(_reveal_p*π)`（朝玩家，包络进/出；末了回到 0）
  - `lift = cfg.flip_lift * sin(_reveal_p*π)`（抬起弧线）
  - `_flip.transform = Transform3D(Basis.from_euler(Vector3(-deg_to_rad(pitch),0,0)) * Basis(Vector3(0,0,1), deg_to_rad(angle)), Vector3(0,lift,0))`
- `reveal(card,color)`：把**揭示目标贴图写到底面板** `_back_material`（`card` 为空/未知则写卡背；否则写该牌面），顶面板 `_front_material` 保持当前；`_apply_glow_layers(color)`（保留发光提示）；tween `_reveal_p` 0→1（`FLIP_DURATION`，`TRANS_CUBIC`）。
- `restore()`：tween `_reveal_p` 1→0；顶面板回当前面。
- 无 mid 回调交换（几何连续性自然换面）；`_kill_flip` 改为 kill `_reveal_p` tween。
- `setup(slot)`：`_reveal_p = 0`、`_flip.transform = IDENTITY`、`_back_material` 复位为卡背贴图，再 `_apply_slot`。

### 3.4 可见面语义与访问器

- `_showing_back := _reveal_p < 0.5`（朝上可见面：<0.5 见正面片、≥0.5 见背面片）。
- `_display_material()` 返回当前朝上片的材质（`_front_mat` 或 `_back_mat`）。
- `block_color()/albedo_texture()/has_face_texture()/has_back_texture()` 改用 `_display_material()`；`has_back_texture` 仍要求 `_showing_back`。
- `_front_mat`/`_back_mat` 的贴图设置：
  - `_apply_color()`：`_front_mat` = 当前 slot 的可见贴图（已知牌=牌面，`original`/图集；未知=卡背）；`_back_mat` = 卡背贴图（复位）。
  - `show_back(bool)`（保留）：切 `_front_mat` 贴图 + label 显隐（不变）。

### 3.5 config

- 复用 `CardAnimationConfig`：`flip_lift`、`hover_pitch`。揭示总时长沿用 `CardBlock.FLIP_DURATION`（0.25s，测试契约不变）。

## 4. 测试与验收

扩展 `tests/verify_table3d_interaction.gd`：

1. **双面几何**：`_test_card_block` 加断言——存在 `_flip` 下的 `Mesh`（正面）与背面片；`_back` 节点本地旋转绕 Z ≈180°（预转）。为可测，暴露 `func back_node() -> Node3D`、`func flip_node() -> Node3D`。
2. **揭示翻转是 3D**：`reveal(card,color)` 后中段（约 `FLIP_DURATION/2`）`flip_node().rotation_degrees.z` 介于 60~120；结束后 ≈180；`root.scale` 保持 `Vector3.ONE`（不再用 scale.x）。
3. **末态显示新面**：结束后 `has_face_texture()` 且 `label_text()` == 该牌面。
4. **restore 复位**：`restore()` 后 `flip_node().rotation_degrees.z` ≈0、`has_back_texture()`。
5. **不镜像**：无法在 headless 目视，仅断言背面片预旋转 180°（结构保证）；镜像由人工验收。
6. **既有断言不回归**：`verify_table3d`（36/36）、`verify_table3d_interaction` 其余全绿。

**验收闸门**：三项测试 + `run_all_tests.sh --quick` 全绿；**人工**：3D 下看牌/贴牌揭示时卡抬起+朝你倾斜+3D 翻转，牌面正向不镜像；揭示结束回平面。

## 5. 文件

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/card_block.gd`（改） | 双面几何（`_front`/`_back`/`_back_mat`）+ `_flip` pivot；`reveal/restore` 改 3D 翻转（`_reveal_p`）；访问器/`_display_material`；`back_node/flip_node` |
| `tests/verify_table3d_interaction.gd`（改） | 上述断言 |
| `docs/superpowers/plans/2026-09-25-cardblock-3d-reveal-flip.md`（新） | 实现计划 |

**不改**：`scripts/core/*`、`scripts/net/*`、`main.gd`、`table3d_view.gd`、`table3d.tscn`、`card_view.gd`、`card_animation*.gd`、`verify_table3d.gd`（仅回归）、`verify_card_animation.gd`。

## 6. 风险与边界

| 风险 | 处理 |
| --- | --- |
| 背面片贴图朝向/镜像 | 背面片建为"正面朝上"并预旋转 180° 绕 Z；翻转 180° 后净旋转 360° → 正向。头测结构 + 人工目视 |
| 与 hover 抢属性 | 揭示写 `_flip`，hover 写 `_visual`，分节点；`_flip` 不写 scale |
| 访问器语义变化 | `_display_material()` 按朝上面取；既有测试按 `FLIP_DURATION` 等待后读，保持通过 |
| 揭示中途状态广播重建 | `setup()` 复位 `_reveal_p`/`_flip`；`table3d_view._reveals` 跨 render 重放走 `reveal_slot`（不变） |
| 发光层在翻转中侧立消失 | 已知可接受（发光是地面提示）；Glow 留 `_visual` 不随揭示旋转 |
| 结算/2D 翻面 | 不受影响（走 CardView / 2D） |

**明确不做**：press、hover 缩放、2D 棋盘翻转改动。
