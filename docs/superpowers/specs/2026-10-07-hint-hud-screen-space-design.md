# KONG 3D Action Hint 屏幕空间化 + 回合倒计时 设计 v1

> **目的**：3D 对局里的 action hint 现在是挂在牌桌中央的**世界空间看板**（`hint3d`，`Board3d` 的 `HintLabel`），相机会随玩家环视晃动。本设计把「**提示文本**」改到**屏幕空间、顶部居中固定**，并在上方新增一条**回合倒计时**（椭圆胶囊，从 30 递减、可为负）。
> **本次范围**：只重整 action hint UI。Ready / 条件动作按钮（Q、变换 Joker）仍留在原处（2D 在 `HintArea`，3D 在 `hint3d`）。2D 对局界面**逐字不动**。
> **纯客户端展示层**：不改规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*`。倒计时为**纯展示、不联网、不触发规则**；数据源与展示层解耦，为未来「服务器权威回合计时」预留接口。
> **分支**：从 `main` 拉出的 `agent/feature-uiboard`。

## 1. 目标与非目标

**目标**

1. 3D 下提示文本移到**屏幕空间**：顶部居中、固定，不随相机环视移动。
2. 顶部新增**回合倒计时胶囊**：默认 30 起、逐帧递减、可为负；椭圆/药丸形、带边框、左右留白。
3. 提示文本换行放在胶囊**下方**（例：`Draw from the deck or the discard pile`）。
4. 换 hint 时播**旧上、新下（带回弹）**动画；新回合进场时**倒计时先掉下来，再 hint 掉下来（带回弹）**。
5. 把 hint 文案集中到一个表（英文不变），为将来统一翻译留缝。
6. 倒计时数据源与 UI 解耦：v1 本地计时；未来换成服务器 `deadline_ms` 时 UI / 动画零改动。

**非目标**

- 不改规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*`。
- 不改 2D 对局界面（`HintArea`/`CenterHint`/Ready/条件按钮及其布局）。
- 不把 Ready / 条件动作按钮搬进屏幕空间面板（保持现状；3D 的鼠标捕获与准星交互不变）。
- 不做服务器权威计时（v2 方向，见 §9）。
- 不移除 `hint3d` 看板本体（它仍承载 Ready/条件按钮）。

## 2. 架构与组件（均纯客户端展示层）

采用「独立屏幕控件 + 独立计时模型 + 集中文案表」的松耦合结构。

### 2.1 `scripts/ui/turn_timer.gd`（新增，`class_name TurnTimer extends RefCounted`）

纯计时模型，headless 可测，不依赖节点/网络。

```
var limit: float = 30.0      # 起始秒数
var remaining: float = 30.0  # 剩余（可为负）

func reset(sec := 30.0) -> void   # remaining = sec
func tick(delta: float) -> void   # remaining -= delta
func seconds_left() -> int        # int(floor(remaining))，可为负
func phase() -> int               # 0 正常 / 1 临近 / 2 超时（给 UI 上色）
```

- 默认 `limit = 30.0`。
- `seconds_left()` 用 `floor`：`30.0 → 30`、`-0.3 → -1`。
- 纯数据，无副作用；v2 只需改「谁来喂 remaining」。

### 2.2 `scripts/ui/hint_text.gd`（新增，`class_name HintText extends RefCounted`）

把现 `main._hint_for(phase, is_current)` 与 `main._decision_hint(is_current, name)` 的字符串生成逻辑**搬入集中表**（英文文本逐字不变）。签名保持可静态调用：

```
static func hint(state: Dictionary, phase: int, is_current: bool) -> String
static func decision(state: Dictionary, is_current: bool, action_mode: String, name: String) -> String
```

- `main._hint_for()` 改为**薄委托** `return HintText.hint(latest_state, phase, is_current)`，现有调用方（`game_view.render`、`_refresh_hint_panel`）与测试断言（`verify_hint` / `verify_j_swap`）零改动。
- 只集中、不翻译（用户决定）。将来翻译只改本文件。

### 2.3 `scripts/ui/hint_hud.gd`（新增，`class_name HintHud extends Control`）

屏幕空间控件，自成一体：布局 + 计时展示 + 动画。

```
# 子节点（代码构建，不用自动排版容器，避免动画被容器每帧覆盖 → 规避 B1）
CountdownPill : PanelContainer   # 椭圆胶囊，内含 Label 显示整数
HintLabelA    : Label            # 两片交替，用于换字动画
HintLabelB    : Label

func set_hint(text: String) -> void        # 文本变→播「旧上/新下」；变则更新
func reset_turn(seconds := 30.0) -> void   # 重置计时 + 播进场（胶囊掉落→hint 掉落）
func set_phase_visible(phase: int) -> void # 控胶囊是否显示（见 §4）
func show_hud(on: bool) -> void            # 3D 显隐；关时 set_process(false)
```

- `_process(delta)`：`_timer.tick(delta)`；刷新胶囊数字与颜色。
- 尺寸/位置变化时在 `_layout()` 内按子节点实际宽度算居中 x；动画只改各自 `position.y` 偏移 + `modulate.a`。
- 重播动画前 `Tween.kill()` 旧 tween。

### 2.4 `scripts/ui/main.gd`

- 新增 `_ensure_hint_hud()`：建 `HintHud`，挂 `main`，锚点顶部居中，`z_index=80`，`mouse_filter=IGNORE`。
- `_set_table3d(true)`：`_ensure_hint_hud()` + `hint_hud.show_hud(true)`；`(false)`：`show_hud(false)`。
- `_refresh_hint_panel()` 内追加：
  - `hint_hud.set_hint(HintText.hint(latest_state, phase, viewer == current))`；
  - 新回合判定（§4）→ `hint_hud.reset_turn(HUD_TURN_SECONDS)`；
  - `hint_hud.set_phase_visible(phase)`。
- `_make_hint_panel()`：移除 `VBox/HintLabel`（`hint3d` 只保留 Ready `VBox/ReadyButton` 与 `VBox/HintActions`）。`_refresh_hint_panel()` 不再设置 `HintLabel`。
- `_hint_center_on_crosshair()`、`hint3d` 放置/按钮逻辑不变。

## 3. 布局与视觉

- 根：`Control`，锚点 `PRESET_CENTER_TOP`，`offset_top = TOP_MARGIN`（初值 40 设计坐标，可调），宽高按内容（`grow` 向两侧）。
- 胶囊：
  - `PanelContainer` + `StyleBoxFlat`；`corner_radius_all = 高/2` → 药丸/椭圆观感；
  - `border_width_all = 2`、`border_color = accent(0.42,0.72,0.95)`；
  - `bg_color = (0.08,0.09,0.12,0.75)`（与现有面板一致）；
  - 左右 `content_margin = 30`（"两边有一点宽度"）、上下 `8`；
  - 内文：整数秒，字号 26 粗体纯白，居中。
- hint 文本：`Label` 字号 18、色 `(0.92,0.95,1.0)`、居中、`autowrap`、最大宽 ≈ 560；与胶囊垂直间距 ≈ 12。
- 两子节点**非** `VBoxContainer` 子项：由 `_layout()` 在 `resized`/文本变化时居中摆放，动画改 `position.y`。
- dark / light 主题沿用 `UITheme`；本次默认用现有深色半透明底 + accent 边框，二者皆可读（不做主题分叉，除非后续需要）。

## 4. 计时行为

- 默认 `HUD_TURN_SECONDS = 30`。
- **重置判定**：`main` 内字段 `_hud_turn_key`（初值空 `""`）。每次 `_refresh_hint_panel()` 计算 `key = "%d:%d" % [match_number, current_player]`；当 `phase` 属于**胶囊显示集合**（§4 下）且 `key != _hud_turn_key` → `reset_turn(30)` 并 `_hud_turn_key = key`。
- "第一次来"由此自然覆盖：对局首帧 `_hud_turn_key` 为空，首次进入可行动阶段（首回合 `TURN_DRAW`）即触发一次重置与进场动画。
- 同一回合内 hint 子步骤变化（选对方牌→选自己牌等）`key` 不变 → **不重置**，只播换字动画。
- `_hud_turn_key` **跨 3D 显隐保留**：F10 切出再切回 3D 不重播；仅真正进入新回合（`current_player` 变化）或新一局（`match_number` 变化）才重置。
- `_process` 每帧 `tick`；显示 `seconds_left()`：`30 → … → 0 → -1 → …`，可为负，**不触发任何规则**。
- 颜色（`TurnTimer.phase()`）：
  - `remaining > 10` → 纯白；
  - `1 ≤ remaining ≤ 10` → 琥珀（如 `Color(1.0,0.78,0.30)`）；
  - `remaining ≤ 0` → 红（如 `Color(1.0,0.36,0.34)`）。
- **显示范围**（`set_phase_visible`）：
  - 胶囊显示：`TURN_DRAW / TURN_DECISION / Q_DECISION / SLAP_EXCHANGE / SLAP_DUEL`；
  - 胶囊隐藏：`LOBBY / INITIAL_PEEK / GAME_OVER / SHOP`（`INITIAL_PEEK` 即"进房间直到全员 ready"阶段不显示、不计时；hint 文本在 `INITIAL_PEEK`/`GAME_OVER` 仍显示）。
- 仅 3D：`show_hud(false)` 时 `set_process(false)`，不再计时。

## 5. 动画行为

统一用 `Tween` 驱动 `position.y` 与 `modulate:a`；**不用 `Control.scale`**（B1 教训）。每次播放前 `kill()` 旧 tween。

- **新回合**：`reset_turn(seconds, text)` 直接把最新文本**提交到单片 label**（不播换字），再播进场——避免"换字 Tween 被进场 `kill` 后旧片残留在顶层、且意图文本已更新导致早退永久遗留"（bugfix）。
- **进场（`reset_turn`，每回合重播）**：
  1. 胶囊：起点 `base.y - RISE(70)`、`alpha 0` → `base.y`、`alpha 1`，`TRANS_BACK / EASE_OUT`，时长 ≈ 0.30s（回弹）。
  2. hint 片：延迟 ≈ 0.18s，同样 `base.y - RISE → base.y`、`alpha 0 → 1`，时长 ≈ 0.32s。
- **换 hint（同回合，`set_hint` 且文本变化）**：
  1. 当前片：`base.y → base.y - RISE_UP(50)`、`alpha 1 → 0`，≈ 0.18s，`EASE_IN`；
  2. 新片：`base.y - RISE → base.y`、`alpha 0 → 1`，`TRANS_BACK / EASE_OUT`，≈ 0.30s；
  3. 两片交替使用，完成后交换引用，保证重叠平滑。
- 数字变化本身**不**触发动画，只更新胶囊文字/颜色。

## 6. 生命周期与接线

```
_set_table3d(true)
  └─ _ensure_hint_hud(); hint_hud.show_hud(true)
     _refresh_table3d() → _refresh_hint_panel()  # 首帧即触发 INITIAL_PEEK 的 reset
_process(delta) in HintHud  # 递减 + 刷新胶囊
_set_table3d(false)
  └─ hint_hud.show_hud(false)   # 隐藏 + set_process(false) + kill tween
```

- `_refresh_hint_panel()` 已在服务器广播与本地交互（B41 的 `_refresh_table3d`）两条路径上被调用，故换 hint 动画与倒计时重置都能即时响应。
- `hint3d` 放置与按钮：`_place_boards()` / `_hint_center_on_crosshair()` **不改**。

## 7. 测试与验收

新增 `tests/verify_hint_hud.tscn` + `tests/verify_hint_hud.gd`（headless）：

- **TurnTimer**：`reset(30)` 后 `remaining==30`；`tick(1.5)` → `28.5`；`seconds_left()` 取整（含 `-0.3 → -1`）；可减到负；`phase()` 阈值。
- **HintText**：`HintText.hint(...)` 与旧 `main._hint_for` 语义一致（英文断言不变）。
- **HintHud**：存在；锚点顶部居中（`anchor_top≈0`、`anchor_left/right≈0.5`）；胶囊 `corner_radius == 高/2`、左右 `content_margin≈30`；`set_hint` 后文本落位；`reset_turn` 后胶囊 `position.y` 起点 < 终值（掉落过）；换字后可用片位置变化断言；`seconds_left() <= 0` 时文字/颜色为红；`show_hud(false)` 后不可见且 `is_processing()==false`。
- **main 集成**：`_set_table3d(true)` → `hint_hud` 可见；`_hint_panel` 不再有 `VBox/HintLabel`；Ready 仍在 `VBox/ReadyButton`。
- **回归**：`verify_hint`、`verify_j_swap`、`verify_board3d`、`verify_manual`、`verify_table3d_interaction` 全绿。

**验收闸门**

1. 新增断言全绿；
2. `tools/run_all_tests.sh`（或 §8 交接说明列出的单进程核心集）全绿；
3. `git diff` 确认 `scripts/core/*`、`scripts/net/*`、2D 相关文件（`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`）零改动。

## 8. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/turn_timer.gd` | 新增：纯计时模型（reset/tick/remaining/seconds_left/phase） |
| `scripts/ui/hint_text.gd` | 新增：集中 hint 文案（英文不变），`main._hint_for` 薄委托 |
| `scripts/ui/hint_hud.gd` | 新增：屏幕空间顶部居中控件（胶囊+双片 hint+动画+计时展示） |
| `scripts/ui/main.gd` | `_ensure_hint_hud`；`_set_table3d` 显隐；`_refresh_hint_panel` 驱动文本/重置/胶囊显示；`_make_hint_panel` 移除 `HintLabel` |
| `tests/verify_hint_hud.tscn` / `.gd` | 新增：TurnTimer/HintText/HintHud/main 集成断言 |
| `docs/功能实现文档.md` / `docs/AI_AGENT_交接说明.md` | 补一句「3D action hint 屏幕空间化 + 回合倒计时」 |

**不改**：`scripts/core/*`、`scripts/net/*`、`scenes/ui/table3d.tscn`、`game_view.gd`、`card_view.gd`、`card_animator.gd`、`reveal_controller.gd`、`board3d.gd`、`key_hint_panel.gd`。

## 9. 边界与未来（服务器权威计时 v2）

- **v1（本次）**：本地 `TurnTimer` 纯展示。负数只是"没强制"的副产品（玩家超时也不受罚）。
- **v2（未来）**：服务器在快照加 `turn_deadline_ms`（或 `turn_started_ms` + 时长），客户端 `remaining = deadline_ms - now_ms`。届时：
  - `HintHud` 只把数据源从 `TurnTimer` 换成"快照时间戳 → 剩余秒数"，**UI/布局/动画零改动**；
  - 若服务器在 0 秒自动推进，则不再出现负数，删除负数展示即可；
  - **唯一要对齐**：重置触发点。v1 用 `TURN_DRAW` + `(match_number, current_player)` 近似"服务器 turn 起点"，v2 直接以服务器 deadline 为准。二者语义一致，切换时只改 `reset` 的调用处。
- 不做：倒计时到 0 自动跳过/判负；不改 Ready/条件按钮交互；不改 2D。

## 10. 参数（初值，可调）

| 常量 | 初值 | 说明 |
| --- | --- | --- |
| `HUD_TURN_SECONDS` | `30` | 回合倒计时起始秒数 |
| `TOP_MARGIN` | `40` | 面板距屏幕顶部（设计坐标） |
| `PILL_H` / `PILL_H_PAD` | `48` / `30` | 胶囊高 / 左右内边距 |
| `PILL_FONT` / `HINT_FONT` | `26` / `18` | 秒数字号 / hint 字号 |
| `HINT_MAX_W` | `560` | hint 最大宽（自动换行） |
| `RISE` / `RISE_UP` | `70` / `50` | 掉落高度 / 上移高度 |
| `DROP_DUR` / `UP_DUR` / `DELAY` | `0.30` / `0.18` / `0.18` | 掉落时长 / 上移时长 / hint 延迟 |
| 颜色阈值 | `>10` 白 / `1..10` 琥珀 / `≤0` 红 | 秒数配色 |
