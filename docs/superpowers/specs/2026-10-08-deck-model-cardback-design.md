# KONG 抽牌堆模型卡背拟合（3D 沙盒原型）设计 v1

> **前置**：本设计只做一个**独立 3D 沙盒原型**，把 `assets/3Dmodels/DeckCardPile.glb` 用 `assets/Cards/back07.png` 卡背拟合成"真实堆叠"观感。**不接入** `main.gd` / `table3d_view`，**规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*` / `scenes/ui/table3d.tscn` / 现有测试零改动**。分支当前为 `feature/3d-ui`。

## 1. 目标与非目标

**目标**

1. 纯 **Godot 着色器**方案：不改模型、不重做 UV，用世界/局部空间投影把 `back07.png` 贴成"一摞被推歪的牌"。
2. 视觉规格（**真实堆叠**）：顶层显示一张完整卡背（含圆角/边框）；下面每层错位露出的窄边也带卡背纹理并按层高做偏移，边缘压暗；越低的层越暗（纵深质感）。
3. 独立 3D 沙盒：实例化模型 + 套 `ShaderMaterial` + 环视相机 + 实时调参面板，便于锁定观感。
4. 全部参数集中到 `DeckBackConfig`，代码不出现散落魔法数；投影/分层/明暗数学抽成纯函数配 headless 单测。
5. 场景 headless 可加载不报错（同既有沙盒约定）。

**非目标**

- 不接进对局（替换 `Center/Deck` 是**下一步**，本次不做）。
- 不碰 Blender、不减面（1M 面优化是后续"按需第 2 步"）。
- 不处理 call-bell 模型。
- 不改规则 / 协议 / 快照 / 2D 棋盘 / 现有 3D 对局代码。

## 2. 模型与素材事实（勘察结论，作为设计前提）

- `DeckCardPile.glb`：单 mesh、单 primitive，**671,240 顶点 / 1,000,000 三角面**（约 33MB）；属性有 POSITION / NORMAL / TEXCOORD_0；材质只有灰底（`baseColorFactor=[0.5,0.5,0.5]`），**无贴图**。
- 自带 UV 是**自动展开的杂乱图集**（约 3 万碎片散布 0–1）→ **不可用**，故用空间投影绕过 UV。
- 局部包围盒 X `-0.924..0.934`、Y `0.0..0.251`、Z `-0.948..0.948`（footprint ≈ 1.86 × 1.90，高 ≈ 0.25）；Y 层步进 ≈ 0.01（约 25 层堆叠）。
- `back07.png`：352×512 RGBA，圆角透明角、浅色边框（≈`#EBF0F5`）+ 蓝青底纹（中心 ≈`#00A8DE`）。宽高比 ≈ 0.6875。

## 3. 架构与文件结构

**三层职责**

| 层 | 文件 | 职责 | 可测 |
| --- | --- | --- | --- |
| 纯数学 | `scripts/ui/deck_back_math.gd`（`DeckBackMath`） | 投影 UV / 分层索引 / 逐层偏移 hash / 侧边混合 / 层高 AO → 纯函数 | ✅ headless |
| 配置 | `scripts/ui/deck_back_config.gd`（`DeckBackConfig`） | 全部参数默认值（见 §7）+ 取值校验 | ✅ |
| 着色器 | `assets/shaders/deck_back_projection.gdshader` | GLSL 实现，是纯函数逻辑的镜像；作为 `material_override` | ❌（由纯函数测试覆盖等价逻辑） |

**沙盒文件**

- `scenes/ui/deck_model_sandbox.tscn` + `scripts/ui/deck_model_sandbox.gd`（根 `Node3D`）。
- 复用 `table3d_camera.gd`（环视/缩放）与 `crosshair.gd`；加载 `DeckCardPile.glb` 场景实例。

## 4. 着色器算法（"真实堆叠"）

按**模型局部坐标**计算，不读模型 UV。顶点阶段把局部 `VERTEX` / `NORMAL` 传到片元（Godot 4 `vertex()` 内 `VERTEX`/`NORMAL` 为局部空间）。

1. **分层索引**：`layer = floor(v_local.y / layer_height)`。
2. **逐层偏移**：`off = (hash22(vec2(layer, layer_shuffle)) * 2.0 - 1.0) * layer_offset`（确定性，同层同偏移）→ 下面露出的窄边读作错位牌面。
3. **顶面投影**：`xz` 按 `rotation_deg` 绕 Y 旋转后，`uv = xz / project_card_size + 0.5 + off`；`project_card_size` 默认≈模型 footprint，使**顶层显示一张完整卡背**。`tile=true` 时 `uv = fract(uv)`（备用"摊开"观感，默认关）。
4. **卡背采样**：`back = texture(back_tex, uv)`；圆角透明（`a<0.5`）处混合到边缘色，**保持不透明**（避免在实心堆上开洞）：`col = mix(edge_color, back.rgb, back.a)`。
5. **侧面（卡边）**：`up = clamp(v_norm.y, 0, 1)`；边框色取卡背素材浅色边采样 `border_color = texture(back_tex, vec2(0.5, 0.02)).rgb`，`edge = border_color * (1 - edge_darken)`，`col = mix(edge, col, smoothstep(0, edge_softness, up))`。
6. **层高 AO**：`depth = 1 - clamp(v_local.y / model_height, 0, 1)`，`col *= mix(1, 1 - layer_ao, depth)`（越低越暗）。
7. `ALBEDO = col * tint.rgb`。`render_mode` 用 `cull_disabled`（贴合模型 `doubleSided`）；其余走 `StandardMaterial3D` 光照（受场景灯光）。

> 说明：**不做平铺**是"真实堆叠"的关键——一张卡背映射到顶层，下面层的窄边取到的是图像的边缘（浅色边框）→ 天然读作卡边；逐层偏移提供"推歪"错位感。

## 5. 纯函数（`DeckBackMath`，测试的权威镜像）

```gdscript
static func hash22(v: Vector2) -> Vector2                     # 确定性 [0,1)，与 shader 同算法
static func layer_index(y: float, layer_height: float) -> float
static func layer_offset(layer_index: float, layer_offset: Vector2, shuffle: float) -> Vector2
static func project_uv(local: Vector3, card_size: Vector2, rotation_deg: float) -> Vector2  # 含 +0.5 居中
static func side_blend(normal_y: float, edge_softness: float) -> float   # 0..1
static func layer_ao_factor(y: float, model_height: float, layer_ao: float) -> float  # 1..1-layer_ao
static func compose(local: Vector3, normal: Vector3, cfg: Dictionary) -> Dictionary
    # 返回 {uv, tile_uv, side, ao}
```

- `hash22` 与 shader 内实现**逐字对齐**（同一常数、同一 fract-sin 式），保证镜像可测。
- `compose` 供单测断言端到端映射（顶层中心 → uv≈0.5；同层同偏移；`side` 对朝上法线≈1、对竖直法线≈0）。

## 6. 沙盒场景与交互

**场景** `scenes/ui/deck_model_sandbox.tscn`（根 `Node3D`，挂 `deck_model_sandbox.gd`）

```
DeckModelSandbox
├── WorldEnvironment        复用 table3d 环境（Sky + KeyLight）
├── CameraRig               table3d_camera.gd（PitchPivot/Camera3D），EYE_HEIGHT≈3.5
├── Table (MeshInstance3D)  7×7 桌面 + 边框（复用 table3d 尺寸），模型坐于桌面 y=Table3dLayout.TABLE_HEIGHT
├── DeckModel               DeckCardPile.glb 实例 + ShaderMaterial（本次主角）
├── RefCard                 CardBlock 单张卡背（比例对照）
├── Crosshair               crosshair.gd
└── TunerPanel (Control)    右侧调参面板
```

**调参面板**（极简，实时改 `DeckBackConfig` 并写 shader uniforms）

- 数值滑条：`project_card_size.x/y`、`rotation_deg`、`layer_height`、`layer_offset.x/y`、`layer_shuffle`、`layer_ao`、`edge_darken`、`edge_softness`、`model_height`、`tint`（色板）、`tile`（勾选）。
- 「Reset」按钮回默认；「打印参数」按钮把当前 config `to_dict()` 打到控制台（便于固化默认值）。

**输入**：鼠标拖拽环视、滚轮缩放（复用 `table3d_camera` / `main._input` 同款策略）；ESC 释放鼠标。

**约束**：headless 实例化不报错；暴露 `play()` / `set_param(name, value)` / `apply_config(cfg)` 供测试驱动（不走 UI）。

## 7. 参数默认值（`DeckBackConfig`）

| 字段 | 默认 | 说明 |
| --- | ---: | --- |
| `project_card_size` | (1.86, 1.90) | 一张卡背在世界 XZ 的投影尺寸（≈模型 footprint） |
| `rotation_deg` | 0.0 | 卡背绕 Y 旋转 |
| `layer_height` | 0.01 | 每层堆叠厚度（≈模型 Y 步进） |
| `layer_offset` | (0.03, 0.02) | 逐层 XZ 偏移幅度 |
| `layer_shuffle` | 1.0 | 逐层偏移随机种子 |
| `layer_ao` | 0.25 | 最底层相对顶层的压暗比例 [0,1] |
| `edge_darken` | 0.35 | 卡边相对边框色压暗 [0,1] |
| `edge_softness` | 0.40 | 顶面↔侧面的法线过渡带 |
| `model_height` | 0.25 | 模型高度（AO 归一化基准） |
| `tint` | Color.WHITE | 整体染色 |
| `tile` | false | 是否平铺（备用观感） |

`validate()` 返回非法字段：非有限、`project_card_size`/`layer_height` ≤0、`layer_ao`/`edge_darken`/`edge_softness` 越界 [0,1]。

## 8. 测试与验收（`tests/verify_deck_back.gd` + `.tscn`）

**A. 纯函数段**

- `hash22`：确定性（同输入同输出）、输出落在 [0,1)；`layer_shuffle` 变化改变结果。
- `layer_index`：y=0→0；y=0.01→1；边界取整正确。
- `layer_offset`：同层同值；不同层不同值；幅度受 `layer_offset` 缩放。
- `project_uv`：`local=(0,·,0)` → uv≈(0.5,0.5)；`rotation_deg=0` 与 90° 对调 X/Z 分量；缩放随 `card_size` 反比。
- `side_blend`：`normal_y=1`→1、`normal_y=0`→0、中间单调。
- `layer_ao_factor`：`y=model_height`→1、`y=0`→`1-layer_ao`、单调。
- config：默认值通过 `validate()`；注入非法值（负尺寸 / AO>1）返回对应字段。

**B. 节点段**

- headless 实例化沙盒不报错；`DeckModel` 子节点存在且材质为 `ShaderMaterial`。
- `apply_config(cfg)` 后 shader uniform 值与 config 一致。
- `set_param("layer_ao", 0.5)` 改变对应 uniform。

**验收闸门**：`verify_deck_back` 全绿；`tools/run_all_tests.sh` 全量回归全绿；对规则 / 协议 / 快照 / 对局 3D 零改动。

## 9. 文件清单

| 文件 | 变更 |
| --- | --- |
| `assets/shaders/deck_back_projection.gdshader`（新） | 卡背空间投影着色器 |
| `scripts/ui/deck_back_config.gd`（新） | `DeckBackConfig`：参数 + `KEYS`/`to_dict`/`validate` |
| `scripts/ui/deck_back_math.gd`（新） | `DeckBackMath`：投影 / 分层 / 明暗纯函数 |
| `scripts/ui/deck_model_sandbox.gd`（新） | 沙盒根：加载模型 / 套材质 / 相机 / 调参面板 / `play`·`set_param`·`apply_config` |
| `scenes/ui/deck_model_sandbox.tscn`（新） | 沙盒场景 |
| `tests/verify_deck_back.gd` + `.tscn`（新） | 纯函数 + 节点测试 |

**不改**：`scripts/core/*`、`scripts/net/*`、`main.gd`、`table3d_view.gd`、`scenes/ui/table3d.tscn`、`card_block.gd`、2D 卡牌相关、现有测试。

## 10. 后续（非本次范围）

1. **接入对局**：把 `Center/Deck`（现 `CardBlock`）替换为 `DeckCardPile.glb` + 本材质，保留 `DeckCount` 标签与拾取/光晕逻辑（需处理拾取盒与 `DeckCount` 相对位置）。
2. **性能优化（按需第 2 步，Blender）**：对 1M 面模型减面 / 重拓扑，保留外观；power 目前 Blender 5.2 CLI 可用。
