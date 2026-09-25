# KONG 卡牌交互动效系统（3D 沙盒原型）设计 v1

> **前置**：本设计只做一个**独立 3D 沙盒原型**，用于锁定"悬浮 / 悬停倾斜 / 起伏翻牌 / 弹性落牌"手感。**不接入** `main.gd` / `table3d_view`，**规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*` / 现有测试零改动**。灵感来自 *This Ain't Even Poker, Ya Joker*（公开资料未披露实现，本设计为可实现的逆向设计，参数为实现起点而非原游戏测量值）。分支 `feature/3d-table`。

## 1. 目标与非目标

**目标**

1. 一套**分层 Offset 合成 + 标量进度 + 纯函数**架构（方案 A），解决 hover / flip / press 等多个 Tween 争抢同一 transform 的问题。
2. 3D 沙盒：桌面上一排 5 张平放卡；**屏幕中心准星 + 鼠标转相机**（与游戏 3D 交互一致，手感可移植）；左键翻牌。
3. 实现 Phase 1+2 核心闭环：
   - IDLE 持续悬浮（位移 + 微旋转）
   - blob 阴影随高度缩放变淡
   - HOVER 抬升 / 放大 / 跟随准星交点的 3D 倾斜
   - PRESS 压缩
   - FLIP 真实 3D 旋转翻面 + 翻牌悬浮高度曲线 + 阴影响应
   - LAND 过冲回弹 settle
4. 全部参数集中到 `CardAnimationConfig`，代码不出现散落魔法数。
5. 可测部分抽成纯函数，配 headless 单测。

**非目标**

- 不做 Phase 3 反馈（粒子 / 金币 / 数字弹出 / SFX）。
- 不做 Phase 4 多卡连续发牌 / 牌型判定 / 奖励。
- 不改 2D 棋盘（`card_view.gd` / `card_animator.gd` / `reveal_controller.gd`）。
- 不接入游戏（不接 `main.gd` / `table3d_view` / 快照）。
- 不做真实光照 / 阴影贴图（用 blob 阴影）。

## 2. 架构与文件 / 节点结构

**三层职责**

| 层 | 文件 | 职责 | 可测 |
| --- | --- | --- | --- |
| 纯数学 | `scripts/ui/card_animation_math.gd`（`CardAnimationMath`） | 状态机转移、缓动、高度曲线、阴影响应、offset 合成 → 输出变换偏移 | ✅ headless |
| 配置 | `scripts/ui/card_animation_config.gd`（`CardAnimationConfig`） | 全部参数默认值（见 §8）+ 取值校验 | ✅ |
| 控制器 | `scripts/ui/card_animation.gd`（`CardAnimation`） | 持有每张卡的标量进度；每帧调纯函数并应用；驱动 blob 阴影；接收输入事件 | ❌ 薄 |

**每张卡的节点结构**

```
CardActor (Node3D, 挂 card_animation.gd)   ← 基准变换 Base（沙盒布局设定，动画不碰）
├── Shadow (MeshInstance3D)                ← blob 阴影（贴桌面，只跟 x/z，scale/alpha 由高度驱动）
└── VisualRoot (Node3D)                    ← 动画只写这里：position/rotation/scale = Base 相对偏移
    └── CardBody (复用 CardBlock)           ← 牌面/卡背贴图 + 边缘发光
```

要点：

- **Base 与 Offset 物理分离**：`CardActor` 是基准；`VisualRoot` 只承载偏移；`Shadow` 是 `CardActor` 的子节点，**不随 `VisualRoot` 旋转/缩放**一起翻。
- **Tween 只驱动标量**（`hover` / `press` / `flip` / `land`），唯一写 transform 的地方是 `compose()`。
- **卡牌本体复用 `CardBlock`**（保留贴图 / 边缘发光），但**控制器独占翻转**（不调用 `CardBlock._flip_to` 的 `scale.x`）；`CardBlock` 仅新增 `show_back(bool)` 用于切面。

**沙盒文件**

- `scenes/ui/card_animation_sandbox.tscn` + `scripts/ui/card_animation_sandbox.gd`
- 复用 `table3d_picker.gd`（准星拾取）与 `table3d_camera.gd`、`crosshair.gd`；不依赖 `table3d_view`。

## 3. 状态机与合成数学

**状态（Phase 1+2，5 态）**

```
IDLE ⇄ HOVER ──点击── PRESS ──(50~90ms)── FLIP ──(翻牌完)── LAND ──(settle 完)──┐
  ▲                                                                              │
  └──────────────── 指针仍悬停 → HOVER；离开 → IDLE ◄───────────────────────────┘
```

- 转移为纯函数：`CardAnimationMath.next_state(cur, event, hovering, flip_done, land_done) -> int`，`event` ∈ `{ENTER, EXIT, CLICK, TIMER}`。
- **打断规则**：FLIP / LAND 中 `CLICK` 被忽略（防连击）；PRESS 中 `EXIT` 不中断本次点击。

**每张卡的标量进度**（Tween 只动这些）

| 标量 | 含义 | 驱动 |
| --- | --- | --- |
| `idle_time` | 连续秒数 | 每帧 `+= delta`，非 Tween |
| `hover` | 0→1 | ENTER/EXIT 时 tween（进 `ease_out_back` / 出 `ease_out_cubic`） |
| `press` | 0→1 | CLICK 时 tween（`ease_out_cubic`，固定时长） |
| `flip` | 0→1 | PRESS 完成后启动（`ease_in_out_cubic`） |
| `land` | 0→1 | FLIP 完成后启动（`ease_out_back`，含过冲） |

**合成（纯函数）**

```gdscript
# progress = {hover, press, flip, land}; ray_local = 准星交点在该卡基准下的局部坐标，clamp(-1..1)
static func compose(progress: Dictionary, cfg: Dictionary,
        idle_time: float, ray_local: Vector2) -> Dictionary
# 返回 {visual_pos, visual_rot_deg, flip_deg, visual_scale, shadow_scale, shadow_alpha}
```

- `height = idle_amp*(1-hover)*sin(idle_time*idle_speed) + hover_lift*hover + flip_lift*sin(flip*PI)`
- `hold_rot = (微旋转向量) *(1-hover)`
- `hover_pitch_rot = Vector3(hover_pitch*hover, 0, 0)` —— hover 时固定仰角，使卡面转向玩家
- `tilt_rot = Vector3(-ray_local.y*max_tilt, ray_local.x*max_tilt, 0)` —— 准星交点追踪微倾，叠加在仰角之上
- `flip_rot = 卡长轴 * (flip*180°)`
- `scale = (1 + (hover_scale-1)*hover) * press_scale(press) * land_scale(land)`
- **旋转合成用 `Basis`/`Quaternion` 组合（非裸 Euler 赋值）**：`visual.basis = 仰角/tilt 的 Basis * 绕卡长轴翻转的 Basis`，保证翻轴始终是卡的长轴、不受仰角影响。
- `shadow_scale = 1 - heightNorm*shadow_scale_loss`，`shadow_alpha = shadow_base_alpha*(1 - heightNorm*shadow_alpha_loss)`，`heightNorm = clamp(height/(hover_lift+flip_lift), 0, 1)`
- 阴影位置由控制器置于卡基准 x/z、桌面 y（`Shadow` 是 `CardActor` 子节点，**不随高度/旋转移动**；只有 `scale`/`alpha` 随高度变化）

所有效果都化为标量在公式里相加/相乘，Tween 之间不可能争抢同一属性。

## 4. 各效果参数与规格

> 3D 无稳定"px→世界"换算，故位移用**卡牌相对单位**（1.0 = 卡长 `BLOCK_SIZE.z`）；默认值见 §8。

**IDLE（持续）**：`idle_amp*(1-hover)*sin(t*idle_speed)` 垂直位移；`rot_z = sin(t*0.7)*idle_rot_z`、`rot_x = cos(t*0.5)*idle_rot_x`，均 `*(1-hover)`；幅度保持卡长约 3%。

**HOVER**：`hover_lift` 抬升 + `hover_scale` 放大 + **`hover_pitch` 固定仰角（卡面转向玩家）** + 跟随准星交点的 tilt（`max_tilt`，方向符号在沙盒目视 + §6 单测确认）；进入 `ease_out_back`（抬得干脆），离开 `ease_out_cubic`（缓慢落回，不瞬间归零）。tilt 的 `ray_local` 用 **CardActor 基准变换求逆**（非动画中的 VisualRoot），避免卡片移动时抖。仰角与 tilt 的旋转用 `Basis` 组合（见 §3）。

**PRESS（50~90ms）**：`press_scale(p) = 1 → press_min → press_over → 1`（分段纯函数）；结束后触发 FLIP。

**FLIP（默认 0.34s）**：

- 旋转轴 = **卡牌长轴（local Z）**。卡抬起转向玩家后该轴≈屏幕竖轴，绕它 0→180° 读作"左右翻面"，与 2D `scale.x` 翻转同语义。
- `flip_lift = sin(flip*PI) * flip_lift_height` —— 90° 时最高，形成"被拿起来翻过去"。
- 阴影随总高度自动缩小变淡。
- **翻面实现（相对草案的修正）**：**不需要双面几何**。单面 `PlaneMesh(cull_disabled)` 在 `flip` 跨过 0.5（≈90° 侧对相机、看不见面）时切换 `albedo_texture`（正面 ↔ 卡背）。因此 `CardBlock` 改动很小：
  - 新增 `show_back(back: bool)`：切贴图 + 显隐点数 `Label3D`，**不触发**自带 `scale.x` 翻转。
  - 自带 `reveal/restore` 在沙盒不使用（控制器独占翻转）。
  - 绕 Z 180° 后卡背可能左右镜像：沙盒目视 + 单测确认，必要时对背面贴图加 180° roll。

**LAND（80~150ms）**：缩放过冲 `1 → land_over → land_under → 1`；高度平滑落回；结束按指针是否仍悬停 → HOVER 或 IDLE。

**Blob 阴影**：`Shadow` 平面（`PlaneMesh FACE_Y`）贴桌 `y = table + 0.002`，尺寸≈卡；材质 unshaded + `TRANSPARENCY_ALPHA`，颜色黑、`albedo_color.a = shadow_alpha`；`local scale = shadow_scale`；位置取卡基准 x/z 投影。为省材质，同一 `StandardMaterial3D` 在多卡间复用（按卡单独设 a 时需实例化，见 §7 性能注）。

## 5. 沙盒场景与输入

**场景** `scenes/ui/card_animation_sandbox.tscn`（根 `Node3D`，挂 `card_animation_sandbox.gd`）

```
CardAnimationSandbox
├── WorldEnvironment         复用 table3d 环境光（无定向光）
├── CameraRig                table3d_camera.gd（PitchPivot/Camera3D），EYE_HEIGHT≈3.5
├── Table (MeshInstance3D)   7×7 桌面 + 边框（复用 table3d 尺寸）
├── Cards                     5× CardActor 沿 X 排开、面向近侧 +Z
└── Crosshair                crosshair.gd，屏幕中心固定
```

- 5 张示例牌面 `A♥ K♠ Q♦ J♣ 10♥`，间距 `BLOCK_SIZE.x + 0.15`。
- 根节点暴露 `play(card_index: int, action: String)`：`"hover"` / `"flip"` / `"reset"`，供测试直接驱动（不走鼠标）。

**输入（与游戏 3D 交互一致）**

- 鼠标转相机：走 `_input` 的 motion（避开 GUI 吞事件，同 `main.gd` 3D 环视策略）。
- hover 判定：每帧 `Table3dPicker.pick_hit(camera, world, 屏幕中心)` 找命中 `CardActor`；命中卡进 HOVER，其余回 IDLE。
- tilt：射线交点 → `CardActor.global_transform.affine_inverse() * hit_pos` → 按卡半尺寸归一化 clamp(−1..1) → `ray_local`。
- 点击：左键 → 当前 hover 卡 `CLICK`；ESC 释放鼠标 / 退出（GUI 调试）。
- 准星悬停在可翻卡上时变金（复用 crosshair 逻辑）。

**沙盒 HUD（极简）**：左上角 `Label` 显示当前卡状态 + 关键标量，便于调参；无按钮/面板。

**约束**：场景 headless 可加载不报错（同 `verify_table3d` 约定）；测试直接调 `play()` 或纯函数。

## 6. 测试与验收

新增 `tests/verify_card_animation.gd` + `.tscn`：

**A. 纯函数段**

- `next_state`：覆盖 IDLE⇄HOVER、HOVER→PRESS→FLIP→LAND→HOVER/IDLE 全边；断言 FLIP/LAND 中 `CLICK` 被忽略、PRESS 中 `EXIT` 不中断。
- 缓动：各 easing 端点（0→0、1→1）与单调性。
- `height`：t=0 ≈0；hover=1 时 idle 分量被抑制；flip=0.5 取到 `flip_lift` 峰值。
- 阴影响应：h=0 → scale=1、alpha=base；h=max → scale≈`1-shadow_scale_loss`、alpha≈`base*(1-shadow_alpha_loss)`。
- `compose`：hover=1 → 位移=`hover_lift`、scale=`hover_scale`、仰角≈`hover_pitch`；flip=0.5 → 旋转≈90°、高度≈`flip_lift`；press 曲线端点。
- config：默认值落在文档区间内（防量级写错）。

**B. 节点段**

- headless 实例化沙盒不报错。
- `play(0,"hover")` → 步进若干帧 → `VisualRoot` 高度 >0 且 `Shadow` scale <1、alpha < base。
- `play(0,"flip")` → 跑到结束 → `flip`→1、`CardBlock` 显示卡背、LAND 后 scale≈1。
- 控制器状态机：ENTER→HOVER、CLICK→PRESS→FLIP→LAND→HOVER。
- `CardBlock.show_back(true/false)` → 贴图切换 + Label 显隐。
- `ray_local` 给定交点 → tilt 方向符号正确。

**验收闸门**：新测试全绿；`tools/run_all_tests.sh` 全量回归全绿；对规则/协议/快照零改动。

## 7. 移植说明与风险（沙盒之外，非本次范围）

最大风险：`table3d_view.render()` 每次快照**全量销毁重建** CardBlock，连续 idle 浮动与在途动画会被广播重置。移植时衔接方式：

- **状态外部键化**：进度按 `(seat, slot)` 键存，重建后重放（与既有 `_reveals` 跨 render 保持同一模式），不挂在被销毁的 CardBlock 上。
- **单一 tick**：所有卡的 compose 在一个 `_process` 推进，不每卡各挂 `_process`。
- **翻转冲突**：现有 `CardBlock._flip_to`/`reveal`（`scale.x`）用于看牌/贴牌揭示；移植时需决策——保留揭示旧翻转、仅"用户翻牌"走控制器真实 3D 翻转，或统一到控制器。
- **场景契约**：blob 阴影需在 `table3d.tscn` 每座位加节点；该场景归开发者所有、节点路径是契约，改动需同步 `_bind()` 与测试。
- **性能**：5 卡无虞；table3d 满座（16 座 × 6 槽）单 tick compose 仍轻量，但阴影平面增多，需注意材质复用（避免逐卡 new 材质）。

**明确不做**：Phase 3 反馈、Phase 4 多卡连续发牌、2D 棋盘、真实接入游戏。

## 8. 参数默认值（`CardAnimationConfig`）

| 字段 | 默认 | 说明 |
| --- | ---: | --- |
| `idle_amp` | 0.03 | 悬浮幅度（卡长比） |
| `idle_speed` | 1.2 | 悬浮速度 |
| `idle_rot_z` | 0.5° | 微旋转 Z |
| `idle_rot_x` | 0.3° | 微旋转 X |
| `hover_lift` | 0.12 | hover 抬升 |
| `hover_scale` | 1.06 | hover 放大 |
| `hover_pitch` | 28.0° | hover 固定仰角（卡面转向玩家） |
| `max_tilt` | 4.0° | 跟随准星的最大倾斜 |
| `hover_in_dur` | 0.12s | 进入时长 |
| `hover_out_dur` | 0.20s | 离开时长 |
| `press_dur` | 0.08s | 压缩时长 |
| `press_min` | 0.97 | 压缩最低 |
| `press_over` | 1.02 | 压缩回弹 |
| `flip_dur` | 0.34s | 翻牌时长 |
| `flip_lift` | 0.25 | 翻牌悬浮高度 |
| `land_dur` | 0.12s | settle 时长 |
| `land_over` | 1.04 | 落牌过冲 |
| `land_under` | 0.99 | 落牌回压 |
| `shadow_base_alpha` | 0.5 | 阴影基础不透明度 |
| `shadow_scale_loss` | 0.30 | 高度最大时阴影缩小比例 |
| `shadow_alpha_loss` | 0.50 | 高度最大时阴影变淡比例 |

## 9. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/card_animation_math.gd`（新） | 纯函数：状态机 / 缓动 / 高度 / 阴影 / compose |
| `scripts/ui/card_animation_config.gd`（新） | 参数默认值 + 校验 |
| `scripts/ui/card_animation.gd`（新） | 控制器：标量进度 + 每帧应用 + 输入事件 |
| `scripts/ui/card_animation_sandbox.gd`（新） | 沙盒根：建 5 卡 / 输入 / 准星 / HUD / `play()` |
| `scenes/ui/card_animation_sandbox.tscn`（新） | 沙盒场景 |
| `scripts/ui/card_block.gd`（改） | 新增 `show_back(back: bool)`（切贴图 + Label 显隐） |
| `tests/verify_card_animation.gd` + `.tscn`（新） | 纯函数 + 节点测试 |

**不改**：`scripts/core/*`、`scripts/net/*`、`main.gd`、`table3d_view.gd`、`scenes/ui/table3d.tscn`、2D 卡牌相关、现有测试。
