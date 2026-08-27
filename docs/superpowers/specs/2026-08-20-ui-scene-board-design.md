# UI 对局棋盘场景实体化转型（设计）

> 日期：2026-08-20
> 分支：`refactor/ui-scene-board`
> 目的：把对局棋盘静态骨架从代码堆叠转型为可编辑 `.tscn` 场景实体，让布局位置可在 Godot 编辑器直接拖拽，同时保持动态元素由代码填充。方案 1（静态骨架实体化），可后续演进到方案 2（手牌槽位也实体化）。

## 1. 现状与问题

- `main.tscn` 只有根 `Control`，整个 UI 由代码 `build_*` 构建。
- `main.gd:_build_interface()`（L116）建全屏骨架 + margin + page。
- `game_view.gd:build()`（L22）建对局棋盘，全部用嵌套 `VBoxContainer`/`HBoxContainer` 代码堆叠。
- 唯一场景实体是 `scenes/ui/card.tscn`（CardView）。
- 布局位置（对手区、牌堆、右下角、大牌）全部在代码里动态计算，无法在编辑器拖拽，难以维护。

## 2. 目标

把对局棋盘**静态骨架**抽成 `scenes/ui/game_board.tscn` 场景实体，用**锚点+容器混合**定位（静态区域锚点钉住、内部容器排布、窗口自适应）。动态元素（玩家手牌、大牌、动画副本、揭示、日志、hint 文本、按钮启用态）继续由代码填充。

## 3. 转型边界

骨架场景只承载：**固定区域容器 + 锚点 + 相对位置关系 + 静态外观**。
代码只负责：**往容器里填动态内容**。

**命名约定**：骨架场景内每个动态区用固定 node_name（`PlayerTop`/`PlayerLeft`/`PlayerRight`/`PlayerBottom`/`PileArea`/`PendingBox`/`Corner`/`HintArea`），`game_view.gd` 通过 `board.get_node` 取容器填内容。未来演进到方案 2（手牌槽位实体化）时，只需把"往 `HandGrid` 里逐个 new 卡"替换为"实例化带槽位的手牌场景"，骨架与动画层不动。

## 4. 场景结构 `game_board.tscn`

```
GameBoard (Control, 锚点全屏)          # 根
├── TitleBar (VBox, 锚点顶部)            # KONG LAN MVP + 状态信息
│   ├── Title (Label)
│   └── StatusLabel (Label)
├── PileArea (VBox, 锚点居中上区)        # 牌堆 + 大牌槽
│   ├── PileRow (HBox)                 # DeckButton / DiscardButton 容器
│   └── PendingBox (Control)           # 大牌 + Use Power 按钮槽
├── PlayerTop (player_area 实例, 锚点顶部居中)    # 上方对手
├── PlayerLeft (player_area 实例, 锚点左中)       # 左对手
├── PlayerRight (player_area 实例, 锚点右中)      # 右对手
├── PlayerBottom (player_area 实例, 锚点底部居中) # 自己
├── Corner (VBox, 锚点右下)              # 铃铛/回合/controls/log
└── HintArea (VBox, 锚点顶部)           # 提示 + Ready + hint 动作区
```

> 四个 `Player*` 是 `player_area` 子场景实例，**直接作为 GameBoard 的子节点**，用锚点自由定位（非容器内），可在编辑器拖拽整体位置与内部布局。

**玩家区域子场景 `player_area.tscn`**（每个玩家一个，可拖拽调试）：

```
PlayerArea (Control)                 # 根，可拖整体
├── VBox (VBoxContainer)
│   ├── HandCenter (HBoxContainer)      # 居中包裹手牌网格
│   │   └── HandGrid (GridContainer)   # 代码填卡（排布逻辑由代码）
│   └── NameLabel (Label)              # 代码设名字/背景，随卡牌高度排布
```

运行时 `_render_player_section` **复用场景内已有的四个 `player_area` 实例**填充：卡牌格子排布（GridContainer 列数/间距/卡尺寸/空槽透明占位）与名字由代码写入 `HandGrid`/`NameLabel`；区域位置、锚点、内部容器由场景编辑器调试。`card_size` 为 PlayerArea 导出属性（默认 62×90），代码优先读取该值渲染卡牌尺寸。**卡牌排布逻辑保留在代码，玩家区域组件位置可在编辑器调试。**


**锚点分配**（静态区域锚点钉住，窗口自适应）：
- `PlayerTop`：`PRESET_TOP_WIDE`，水平居中
- `PlayerLeft` / `PlayerRight`：`PRESET_LEFT_CENTER` / `PRESET_RIGHT_CENTER`
- `PlayerBottom`：`PRESET_BOTTOM_WIDE`，居中
- `Corner`：`PRESET_BOTTOM_RIGHT`（沿用现有 offset `-360,-150,-12,-8`）
- `PileArea`：`PRESET_CENTER_TOP` 偏下，居中
- `HintArea`：`PRESET_TOP_WIDE`

> 相对拓扑与现有 `game_view.gd:build()` 一致，不做行为变更。

## 5. 改造点（代码侧）

| 文件 | 改动 |
|---|---|
| `scenes/ui/game_board.tscn` | **新增**：静态骨架实体 |
| `main.gd` | `_build_interface()`：实例化 `game_board.tscn` 作为 `game_panel` 内容；保留成员引用赋值 |
| `game_view.gd:build()` | 精简为从骨架取容器引用 + 绑定 deck/discard 信号 |
| `game_view.gd:render/_render_player_section` | 填充逻辑不变，改为复用 `PlayerTop/Left/Right/Bottom` 实例，向 `HandGrid`/`NameLabel` 填充 |
| `card_animator.gd` / `reveal_controller.gd` | **不改**（只读 `_card_slots` + 用 overlay 播动画） |

**关键兼容点**：
- `main.deck_button` / `main.discard_button` / `main.pending_card_box` / `main.pending_action_button` 等成员名**保持不变**，动画器/渲染器依赖它们。
- `card_animator._big_card_rect()` 依赖 deck/discard 的 `get_global_rect()`，只要它们仍在场景且有正确位置即照常工作。
- 大牌定位 `_apply_pending_setup` 仍按"两堆中心"算，不依赖骨架结构。

## 6. 验证（保持全绿，不启动 GUI 为主）

改造前后跑交接说明第 8 节 headless 测试：
- `verify_protocol` (27/27)
- `verify_swap` (10/10)
- `verify_hint`
- 双实例 `verify_net`

改造完成后**临时启动一次 GUI 目视确认**布局没跑飞，确认后关闭。

## 7. 不做的事（范围控制）

- 不改 `card.tscn` / `card_view.gd`（已是实体）
- 不改大厅 `lobby_view.gd`（本次只转对局棋盘，大厅可后续同类处理）
- 不改任何规则/网络/状态机（第 3 节不变量全部保持）

## 8. 演进到方案 2

本方案保留四个 `Player*` 实例与"填内容"边界。未来把 `_render_player_section` 里"逐个 new 卡"替换为"实例化带槽位标记的手牌场景"即可，骨架与动画层不需改。
