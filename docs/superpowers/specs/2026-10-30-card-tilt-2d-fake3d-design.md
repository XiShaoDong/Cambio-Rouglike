# 2D 伪 3D 卡牌倾斜 + 打光（沙盒）设计

> 纯客户端展示层原型：不改规则 / 协议 / 快照 / 现有组件。目标是把"鼠标上下左右移动 → 卡片对应倾斜 + 光斑滑动"做成可复用组件，先在独立沙盒里调参。

## 1. 目标

- 鼠标在卡面内移动时，卡片按位置做 **真透视** 倾斜（不是剪切/缩放）。
- 固定光源（左上偏前），倾斜时产生随动的镜面高光、反光条、边缘轮廓光。
- 倾斜带阻尼回中；鼠标离开卡片回正。
- 参数（最大角度、跟随速度、高光/反光/轮廓/投影强度）可在沙盒实时调。

## 2. 方案

**片元着色器里做逆单应映射**：GDScript 每帧按倾斜角把卡片四角做 3D 投影，得到目标梯形，再求「单位方 → 梯形」的单应矩阵并求逆，作为 3 行 `vec3` uniform 传给 shader。片元用自身 UV 反查源图 UV：落在卡面内的采样卡面并打光，落在梯形外则透明（或画投影）。

这样透视是逐像素正确的（不是 4 顶点仿射导致的假透视），且整张卡片在同一个 `TextureRect` 上完成，不需要 3D 场景或多边形。

画布尺寸 = 卡面 × `pad`（默认 1.8），给近边外扩留空间；卡面静止时占画布的 `1/pad`。梯形轮廓用源 UV 边界 + 抗锯齿遮罩裁切。

## 3. 组件

| 文件 | 职责 |
| --- | --- |
| `assets/shaders/card_tilt.gdshader` | 逆单应采样 + 固定光 Lambert/Blinn 高光 + 反光条 + 轮廓光 + 源 UV 边缘 AA + 可选投影 |
| `assets/shaders/card_face_3d.gdshader` | 3D 卡面 spatial 打光：unshaded 常亮漫反射 + Blinn 高光 + 反光条 + Fresnel 轮廓光 |
| `assets/shaders/avatar_body.gdshader` | 玩家机器人机体：金属 PBR + 随视角滑动的眼神高光/边缘光 |
| `assets/shaders/table_surface.gdshader` | 牌桌台布/木头/黑边：PBR + 随 gaze 的低频柔光带 + 边缘光 |
| `scripts/ui/card_tilt_math.gd`（`CardTiltMath`） | 纯函数：鼠标→角度、平滑、旋转、3D 投影、单应求解/求逆、法线 |
| `scripts/ui/card_tilt_view.gd`（`CardTiltView`） | `TextureRect` 包装：鼠标跟随、阻尼、每帧刷新 uniform、参数 `@export`、预设保存/读取 |
| `scripts/ui/card_tilt_preset.gd`（`CardTiltPreset`） | 调参存档：`res://assets/config/card_tilt_preset.cfg`（只读时回退 `user://`） |
| `scripts/ui/card_tilt_sandbox.gd` + `scenes/ui/card_tilt_sandbox.tscn` | 沙盒：深色背景、中央卡牌、右侧滑条调参 |
| `scripts/ui/card_view.gd`（`CardView`） | 2D 大牌接入：`set_tilt_enabled(true)` 后前后卡面贴 shader，按鼠标位置倾斜（顶点扩展画布，不裁切） |
| `tests/verify_card_tilt_math.gd` / `.tscn` | 纯数学 + shader 加载断言；注册到 `tools/run_all_tests.sh` |

## 4. 数学约定

- 卡片局部坐标：`x` 右、`y` 下（与 2D 一致）、`z` 朝观察者；宽度 1，高度 = `aspect`（高/宽）。
- 相机在 `(0, 0, cam_dist)`，焦距取 `cam_dist`，故静止时卡宽正好占画布 `1/pad`。
- 角度：鼠标右 → `yaw > 0`（右边缘远离），鼠标下 → `pitch > 0`（下边缘靠近），与 CSS `rotateY/rotateX` 观感一致。
- 单应：源 UV 四角 `(0,0)(1,0)(1,1)(0,1)` ↔ 投影梯形四角，Heckbert 公式求 H，再 3×3 求逆。
- 法线：`basis * (0,0,1)`，直接传 shader；光源方向固定 `(-0.45,-0.35,0.82)`。

## 5. 参数（默认）

`max_tilt_deg=14`、`cam_dist=3.0`、`pad=1.8`、`response=9.0`、`spec=0.55`、`gloss=0.35`、`rim=0.30`、`shadow=0.35`。

## 6. 调参持久化（应用到实际游戏）

- 沙盒右侧「保存到项目」把当前滑条值写入 **`res://assets/config/card_tilt_preset.cfg`**（项目内文件，可随仓库提交）；若 `res://` 不可写（导出包）则自动退回 `user://card_tilt_preset.cfg`。保存后按钮下方显示实际路径。
- 「读取已保存」重新读取并把滑条同步到存档值。
- 存档字段：`card_aspect / pad / max_tilt_deg / cam_dist / response / spec_strength / gloss_strength / rim_strength / shadow_strength / base_gain / gloss_tint / light_dir`。
- **游戏内接入（只给大牌）**：`CardView` 默认**不挂** tilt 材质；只有抽牌后竖起的 pending 大牌在 `game_view._rebuild_pending_card()` 里显式 `set_tilt_enabled(true)` 才启用。2D 大牌 `mouse_filter=IGNORE`，因此每帧按鼠标是否落在卡面矩形内驱动指针（不依赖 hover 事件）；离开回正。普通手牌/弃牌堆/结算看板保持原样。
- **画布不裁切**：`card_tilt.gdshader` 新增顶点阶段 `rect_size`/`canvas_pad`，把绘制四边形按 `pad` 放大（配合逆映射的 `pad`，静止视觉尺寸不变），倾斜外扩、反光与投影不会画到节点矩形外就被截断。`CardTiltView` 自身已预留画布，保持默认 `canvas_pad = 1.0`。
- 自定义场景也可直接用 `CardTiltView`：默认 `persist = true` 自动读预设，或显式 `card.load_preset(path)`。
- 以后改手感只需回沙盒调完「保存到项目」，游戏侧下一次进对局自动生效。
- **3D 桌面（所有卡）**：`CardBlock` 默认材质统一为 `card_face_3d.gdshader`，手牌/弃牌/牌堆/对手手牌/中央大牌全部覆盖；不再有“只给大牌”的特例。
- **3D 眼神光影**：`unshaded` 自算——常亮漫反射 + **随相机注视方向滑动的柔和反光条** + **源 UV 边缘轮廓光**；反光相位 = 卡面 UV + 相机 gaze（`INV_VIEW_MATRIX`）+ 卡牌世界位置偏移，因此转头/抬低头时高光在卡面滑动，且同桌每张牌的相位略有差别，不像一张固定贴图。`gloss/rim/base_gain/gloss_tint` 来自同一存档。注意 `unshaded` 下 `EMISSION` 不参与输出，高光/反光必须并进 `ALBEDO`（之前写 EMISSION 就是“完全没效果”的根因）；平放卡镜面高光会整张均匀提亮，所以不做 spec。反光用乘法提亮，避免把红色花色冲粉。光影不跟 hover 走。
- **投影**：沿用 3D 场景真实阴影（`KeyLight`），不叠加 2D 假投影。
- **道具手牌弹层（3D 右手臂）**：空格打开的 `ItemHandOverlay` 默认手部从 2D 圆手换成 `ItemArmHand3D`：透明 `SubViewport` + 俯视正交相机渲染，右下大臂袖口 → 手肘折角 → 小臂斜向前 → 复用 `AvatarHand` 的手掌/四指/拇指；掌心朝上（正对相机）、拇指在左，颜色取该玩家机体色。为给手臂让位，卡扇中心上移（`FAN_CENTER_LIFT`）、说明框上移、提示文字放到说明与卡扇之间。旧的 `HandSilhouette2D` 保留作可替换 fallback。
- **上一局冠军皇冠**：`run.prev_winners` 在**结算时**写入（`last_result.winners`），随快照下发；`table3d_view` 按 seat 调 `RobotAvatar.set_crown(true)`。皇冠素材 `assets/3Dmodels/champion_crown.glb`（Brass 贴图）缩到原 2/3，底座套在头顶；`crown_gold.gdshader` 叠加随视角的金属高光/金边；缓慢自转 + 上下轻浮。与离线光环可共存（光环自动抬高）。**显示时机**：进入 GAME_OVER 先隐藏，结算冠军音结束（`play_winner` 返回时长）后 `crown_ready=true` 并由 `_refresh_table3d` 放上皇冠，不等商店结束。
- **玩家机器人**：`RobotAvatar` 机体改用 `avatar_body.gdshader`（保留金属 PBR），叠加与卡面/铃铛同光向的 Blinn「眼神高光」+ Fresnel 边缘光，随相机转动在肩/头上滑动；`eye_spec / rim_strength` 从同一存档换算，逐玩家机体颜色仍走 shader 参数。
- **牌桌（磨砂）**：`PokerTableModel` 的 5 个面改用 `table_surface.gdshader`；金属度归零、粗糙度 0.86–0.98，去掉镜面高光，只留极弱的 gaze 柔光带 + Fresnel 边光，并叠加世界坐标细颗粒（grain）模拟磨砂台布/木面。台布最哑、木质/黑边稍亮，避免整片被洗白。
- **右手抬臂（看道具牌，全房可见）**：空格打开/关闭道具手牌时，`RobotAvatar` 右臂平滑放到桌面高度（上臂朝下前方、小臂再折向前，手腕放平），再按空格放回身侧。右手末端挂 `AvatarHand` 低模（手掌 + 四指 + 拇指 BoxMesh，挂在 `hand.R` 骨骼上、共用机体材质），替代原来的锥形手尖。原模型小臂/手没有蒙皮权重（整条手臂刚性绑在上臂），运行时把 Arms 网格远端顶点按位置渐变重绑到 `lower_arm.R`，肘部才真正可弯。同步复用注视 RPC：`server_look/receive_look/_apply_look` 增加 `arm_up`，存 `GameState.remote_arm`，`update_avatars` 逐席下发；只有 viewer 自己无远程数据时才回退本机状态。
- **Kong 铃铛**：`bell_metal.gdshader` 增加与卡面同光向的 Blinn「眼神高光」，弧面法线让亮点随相机转动在铃身滑动；黑底座不参与。`eye_spec / fresnel_lift` 从卡面同一存档的 `gloss_strength / rim_strength` 换算，保证桌面整体光感一致。
- **边界**：2D 用片元逆单应 + 固定光；3D 用真实网格旋转 + 自制 spatial 打光。两者都只作用于「大牌」，共用调参存档，手感同源但实现独立。

## 7. 验证

- `verify_robot_avatar`（78 项，含右臂重绑、抬/放进度、远程 `arm_up` 同步）。
- `verify_card_tilt_math`（46 项）：角度钳制 / 平滑收敛 / 正反单应往返 / 静止对称 / 正 yaw 右边缘内收 / 正 pitch 下边缘外扩 / 90° 不产生 NaN / 法线 / shader 可加载 / 参数 save-load 往返（含 `gloss_tint`）/ 普通卡不挂材质、大牌 `CardView` 挂材质/画布扩展/指针倾斜/ uniform 同步 / 3D 卡面统一 spatial shader、光影固定无 tilt uniform、贴图走 shader 参数。
- `tools/run_all_tests.sh --quick` 全量 53/53。
- 人工：`godot --path . res://scenes/ui/card_tilt_sandbox.tscn`，鼠标绕卡移动看倾斜/高光/投影，拖滑条实时变化，移开回正；「保存到项目」后重启场景确认滑条仍是保存值。

## 8. 非目标

- 不改规则 / 协议 / 快照；不替换现有卡面美术与 CardView/CardBlock 动画。
- 不做新的点击/拾取逻辑（沿用现有 Button 悬停与准星拾取）。
- 不为倾斜引入后处理或额外 3D 场景。
