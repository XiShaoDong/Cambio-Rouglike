# KONG 3D 换牌动画（3D 沙盒原型）设计 v1

> **前置**：本设计只做一个**独立 3D 沙盒原型**，用于锁定"换牌飞牌"手感——直线位移 + 抬升弧线 + 飞行中翻面，覆盖服务器 `card_exchange_animated` 的全部 6 种 `kind`。**不接入** `main.gd` / `table3d_view`，**规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*` / 现有测试零改动**。复用既有 `CardBlock`（双面几何）、`Table3dLayout`（布局常量）、`table3d_camera.gd`（自由环视）。分支 `feature/card-animation`。

## 1. 目标与非目标

**目标**

1. 一套**标量进度 + 纯函数合成**的飞牌架构（与 `CardAnimation` 同思路，但更轻）：Tween 只驱动飞行进度 `p`，每帧唯一写 `transform` 处是 `compose()`。
2. 3D 沙盒：**复刻对局布局**（4 座位手牌区 + 中央抽牌堆/弃牌堆/大牌位，尺寸与间距取 `Table3dLayout`），顶部 6 个按钮分别触发 6 种 `kind`。
3. 飞牌运动：**直线位移 + 世界 +Y 抬升弧线 + 飞行中绕卡长轴翻面**；时长按起止距离给出（沿用 2D `_fly` 的公式量级）。
4. 全部参数集中到 `CardFlyConfig`，代码不出现散落魔法数；纯函数抽到 `CardFlyMath` 配 headless 单测。
5. 飞牌单元 `CardFly` 自包含（自带 `CardBlock`），便于日后接入 `table3d_view`。

**非目标**

- 不接入游戏（不接 `main.gd` / `table3d_view` / 快照 / 网络）。真实接入方式见 §7，本次不做。
- 不做粒子 / 金币 / 数字弹出 / SFX。
- 不改 2D 棋盘（`card_animator.gd` / `card_view.gd` / `reveal_controller.gd`）。
- 不改 `card_block.gd`（翻面复用其既有双面几何，见 §3）。
- 不做真实光照 / 阴影贴图（本次**不做**阴影，保持最小）。

## 2. 架构与文件 / 节点结构

**四层职责**

| 层 | 文件 | 职责 | 可测 |
| --- | --- | --- | --- |
| 纯数学 | `scripts/ui/card_fly_math.gd`（`CardFlyMath`） | 距离→时长、路径进度缓动、弧线高度、翻面角、变换合成 → 输出飞行参数 | ✅ headless |
| 配置 | `scripts/ui/card_fly_config.gd`（`CardFlyConfig`） | 全部参数默认值（见 §8）+ 取值校验 | ✅ |
| 控制器 | `scripts/ui/card_fly.gd`（`CardFly`） | 单张飞牌：持有标量 `p`；每帧调纯函数并应用；结束发 `finished` 信号并 `queue_free` | ❌ 薄 |
| 沙盒 | `scripts/ui/card_fly_sandbox.gd` + `scenes/ui/card_fly_sandbox.tscn` | 复刻布局 / 6 按钮 / HUD / `play(kind)` 测试入口 | ✅ 加载 |

**`CardFly` 节点结构**

```
CardFly (Node3D, 挂 card_fly.gd)         ← 每帧由 compose 唯一写 global_transform
└── CardBody (CardBlock)                 ← setup(card_data)；禁用拾取；利用其双面几何显示正/背
```

要点：

- **起点/终点是世界 `Transform3D`**（含朝向），由沙盒（日后由 `table3d_view`）在动画开始前抓取。
- **朝向插值**用 `Basis.slerp`（或 `Transform3D.interpolate_with` 的 basis 部分），保证从牌堆朝向平滑转到目标座位朝向。
- **位置**：`origin` 直线插值后再叠加世界 +Y 的 `arc_lift`。
- **翻面**：绕卡长轴（local Z）0→180°。`CardBlock` 既有双面几何（前面板 + 预旋 180° 的背面板）会把背面自然翻上来 → **不需要 `show_back()`、不需要改 `card_block.gd`**。
- 飞牌期间自身**不挂拾取**（`body.set_pick_enabled(false)`），不干扰沙盒准星。

## 3. 飞行数学与翻面

**标量进度**：单个 `p ∈ [0,1]`，由 `Tween` 以 `TRANS_CUBIC / EASE_IN_OUT` 从 0 推到 1；`_process` 每帧用 `p` 调 `compose` 应用。`p` 是唯一被 Tween 写的属性。

**纯函数**

```gdscript
# 距离 → 时长（秒）；与 2D CardAnimator._fly 同量级
static func duration_for(dist: float, cfg: Dictionary) -> float
# 路径进度 = 缓动(p)
static func path_t(p: float, cfg: Dictionary) -> float
# 弧线抬升：世界 +Y 偏移 = arc_height * sin(p*PI)（起止为 0，p=0.5 峰值）
static func arc_lift(p: float, cfg: Dictionary) -> float
# 翻面进度：p 落在 [flip_start, flip_end] 内做 smoothstep，返回 0..1
static func flip_t(p: float, cfg: Dictionary) -> float
# 合成：起止世界变换 + p + 滚转偏置 → {origin, basis}
# roll_start_deg：起始面为背面时传 180（把 CardBlock 的背面翻上来），否则 0。
# roll_delta_deg：起面≠终面时传 180（沿翻面窗口多滚 180°），否则 0。
static func compose(start: Transform3D, end: Transform3D, p: float,
        roll_start_deg: float, roll_delta_deg: float, cfg: Dictionary) -> Dictionary
```

- `duration_for`：`clampf(base + dist * per_dist, min, max)`，默认 `base=0.30, per_dist=0.002, min=0.30, max=0.90`（对齐 2D）。
- `path_t`：默认 `ease_in_out_cubic(p)`（自实现，避免依赖 `CardAnimationMath` 语义耦合）。
- `arc_lift`：默认 `arc_height=0.35`（世界单位），`sin(p*PI)` 包络，故起止贴桌、中点最高。
- `flip_t`：默认窗口 `[0.35, 0.65]`，窗口内 `smoothstep` 0→1、窗口外夹取，避免起止瞬间翻。
- **合成**：`compose` 先对 origin 直线插值 + 叠加 `arc_lift`；basis 取 `start.basis.slerp(end.basis, path_t)`，再右乘 `Basis(Vector3(0,0,1), deg_to_rad(roll_start_deg + roll_delta_deg * flip_t(p)))`（绕卡局部长轴）。`CardBlock` 的双面几何决定可见面。
- **面状态 → 滚转偏置**（控制器在调用 `compose` 前算好）：

  | 起面 → 终面 | `roll_start_deg` | `roll_delta_deg` | 读感 |
  | --- | ---: | ---: | --- |
  | 正 → 正 | 0 | 0 | 全程正面，不翻 |
  | 背 → 背 | 180 | 0 | 全程背面，不翻 |
  | 正 → 背 | 0 | 180 | 飞行中翻到背面 |
  | 背 → 正 | 180 | 180 | 背面起飞，飞行中翻到正面（180°→360°） |

## 4. `CardFly` 控制器 API

```gdscript
class_name CardFly extends Node3D

signal finished

# 启动一次飞行。card_data 为空 {} → 显示背面（未知牌）。
func play(start: Transform3D, end: Transform3D, card_data: Dictionary,
        start_face_up: bool, end_face_up: bool) -> void

func progress() -> float          # 当前 p
func is_flying() -> bool
func card_block() -> CardBlock    # 供测试查询可见面/标签
```

- `play` 内：`body.setup(...)`（始终以牌面数据 setup；显隐面由滚转偏置决定）、按 §3 表格算出 `roll_start_deg` / `roll_delta_deg`、创建 `Tween` 推 `p`、每帧调 `compose` 应用、`finished` 后 `queue_free`。
- `card_data` 为空 `{}` 时 `CardBlock` 显示卡背；此时两张面都是背面，滚转偏置无视觉影响。
- 无需 `_ready` 时自动播放；由调用方触发。

**面显示约定**：`CardBlock` 默认正面朝上显示 `setup` 的牌；背面由绕卡长轴滚转 180° 后其预旋背面板朝上呈现。控制器据 §3 表算出的两个滚转偏置即可实现四种起终面组合，**无需 `show_back()`、无需改 `card_block.gd`**。

## 5. 沙盒场景与输入

**场景** `scenes/ui/card_fly_sandbox.tscn`（根 `Node3D`，挂 `card_fly_sandbox.gd`）

```
CardFlySandbox
├── WorldEnvironment          复用 table3d 深浅背景 + 环境光（无定向光）
├── CameraRig                 table3d_camera.gd（PitchPivot/Camera3D）
├── Table (MeshInstance3D)    7×7 桌面 + 深色边框（复用 table3d 尺寸）
├── Center                    Deck / DiscardTop / Pending（静态 CardBlock，坐标同 table3d.tscn）
├── Seats                     4× SeatN（HandAnchor，按 SEAT_RADIUS + slot_grid_pos 摆 4 张示例牌）
└── UI (CanvasLayer)          顶部 6 按钮 + Reset + HUD Label
```

- 座位角度复用 `Table3dLayout.seat_angles(4)`（`[0,270,90,180]`），座位朝向 `a+180°`，与 `table3d_view._render_seat` 一致的本地坐标换算。
- 座位静态牌：每席 4 张，槽位坐标取 `slot_grid_pos(i)`（列 `-X`、行 `(1-行)` 的 `+Z`）；示例牌面各不相同便于辨认。
- 中央 `Deck(0,0.03,0)`、`DiscardTop(0.9,0.03,0)`、`Pending(0,0.05,0)`，与 `table3d.tscn` 一致。
- `CameraRig` 自由环视（鼠标转相机，走 `_input`）；测试可 `frame_for_seat(0)`。

**6 按钮 → 演示映射**（用示例牌/槽位；源卡在飞行期间隐藏，结束后复位）

| 按钮 | kind | 源 → 目标 | 翻面 |
| --- | --- | --- | --- |
| Replace | `replace` | seat0.slot0 → DiscardTop；Deck → seat0.slot0 | 两段：旧牌正面飞弃牌堆；抽牌背面→正面落座位 |
| Swap | `swap` | seat0.slot1 ↔ seat1.slot1 | 正面→正面（不翻） |
| Discard | `discard` | Pending → DiscardTop | 正面→正面 |
| Penalty | `slap_penalty` | Deck → seat1 追加槽（第 5 槽） | 背面→背面（不翻） |
| Resolved | `slap_resolved` | seat2.slot0 → DiscardTop | 正面→正面 |
| Gift | `slap_gift` | seat0.slot2 → seat3.slot2 | 背面→背面（不翻） |

**沙盒 API（供测试直接驱动，不走鼠标）**

```gdscript
func play(kind: String) -> void       # 触发某一 kind 的演示
func flying_count() -> int            # 当前在途飞牌数
func demo_all() -> void               # 顺序跑全部 6 种（可选，供人工）
```

**约束**：场景 headless 可加载不报错；飞牌节点在结束时全部 `queue_free`，源卡复位。

## 6. 测试与验收

新增 `tests/verify_card_fly.gd` + `.tscn`：

**A. 纯函数段（`CardFlyMath`）**

- `duration_for`：短距取到 `min`、长距取到 `max`、中距随距离单调不减。
- `arc_lift`：`p=0/1 ≈ 0`、`p=0.5 ≈ arc_height`。
- `flip_t`：`p<=flip_start` 为 0、`p>=flip_end` 为 1、窗口内单调。
- `flip_angle`：端点 0 / 180。
- `compose`：`p=0` origin≈start.origin、`p=1` origin≈end.origin；`p=0.5` 时 origin.y 高于两端（弧线）；`roll_delta_deg=0` 时任意 p 的额外滚转为 0；`roll_delta_deg=180` 时 p=0 与 p=1 的滚转相差 180°。
- `CardFlyConfig`：默认值合法（`validate()` 空）、`to_dict()` 键数、非法负值被抓。

**B. 节点段**

- headless 实例化 `card_fly_sandbox.tscn` 不报错。
- `play(kind)` 对 6 种各跑一次：开始时 `flying_count()>0`；等待超过 `max` 时长后 `flying_count()==0`、无残留飞牌节点。
- `CardFly`：手动 `play(...)` 后 `is_flying()` 为真；跑完后 `finished` 触发且节点被释放。
- 翻面：`flip_to_face=true` 的飞行跑完后，`card_block().label_text()` 显示目标牌；背面飞行的目标标签为空。

**验收闸门**：新测试全绿；`tools/run_all_tests.sh` 全量回归全绿；对规则/协议/快照零改动。

## 7. 移植说明与风险（沙盒之外，非本次范围）

最大风险：`table3d_view.render()` 每次快照**全量销毁重建** `CardBlock`，在途飞牌会被广播重置。日后接入方式：

- **抓取起止变换**：在 `main.gd` 收到 `card_exchange_animated`（服务器在 `_broadcast_state` **之前**广播）时，用**旧布局**从 `_card_blocks` / 中央节点取世界 `Transform3D`（与 2D `CardAnimator` 用旧布局定位同理）。
- **隐藏源卡**：复用现有"动画槽位"思路（3D 侧需新增等价于 `_anim_slots` 的槽位隐藏集合，或在 `render` 时跳过被标记槽位）。
- **单一 tick / 生命周期**：飞牌与场景树同时存在，`render()` 重建静态卡时应跳过"在途飞牌覆盖的槽位"，避免源卡与飞牌同时出现。
- **翻转冲突**：`CardBlock.reveal()`（看牌/贴牌揭示）与飞牌翻面不会同时占用同一卡；接入时明确优先级。
- **接线点**：`main.gd:356` 的 `if not _table3d_active:` 分支改为——2D 走 `CardAnimator`，3D 走新的 3D 换牌动画入口。
- **性能**：单次事件最多 2 张飞牌（`replace`/`swap`），复用 `CardBlock`，无虞。

**明确不做**：真实接入游戏、阴影、粒子/SFX、2D 棋盘改动。

## 8. 参数默认值（`CardFlyConfig`）

| 字段 | 默认 | 说明 |
| --- | ---: | --- |
| `duration_base` | 0.30 | 时长基准（秒） |
| `duration_per_dist` | 0.002 | 每单位距离增加秒数 |
| `duration_min` | 0.30 | 时长下限 |
| `duration_max` | 0.90 | 时长上限 |
| `arc_height` | 0.35 | 弧线顶点抬升（世界单位） |
| `flip_start` | 0.35 | 翻面窗口起点（p） |
| `flip_end` | 0.65 | 翻面窗口终点（p） |

## 9. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/card_fly_math.gd`（新） | 纯函数：时长 / 路径缓动 / 弧线 / 翻面 / compose |
| `scripts/ui/card_fly_config.gd`（新） | 参数默认值 + 校验 |
| `scripts/ui/card_fly.gd`（新） | 控制器：标量进度 + 每帧应用 + `finished` |
| `scripts/ui/card_fly_sandbox.gd`（新） | 沙盒根：复刻布局 / 6 按钮 / `play()` |
| `scenes/ui/card_fly_sandbox.tscn`（新） | 沙盒场景 |
| `tests/verify_card_fly.gd` + `.tscn`（新） | 纯函数 + 节点测试 |

**不改**：`scripts/core/*`、`scripts/net/*`、`main.gd`、`table3d_view.gd`、`table3d_layout.gd`、`card_block.gd`、`scenes/ui/table3d.tscn`、2D 卡牌相关、现有测试。
