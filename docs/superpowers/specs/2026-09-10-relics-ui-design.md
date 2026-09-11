# KONG 遗物 UI 设计（物品栏 + 护盾卡面紫光）

> **前置**：本设计为 M4 遗物效果 v1（已实现，`2026-09-07-series-shop-relics-design.md` §6 / `docs/superpowers/plans/2026-09-07-relics.md`）的**客户端展示层**补充。纯 UI，不改服务器权威 / 私有快照 / 贴牌时序；数据全部来自现有快照公开字段（`run.relics`/`run.relic_owners`/`players[].protected_slot`）。不启 GUI，以 headless 编译检查 + `tools/run_all_tests.sh --quick` 回归验证。

## 1. 目标

1. 让防守护盾在卡面有**直观视觉体现**：受保护格常驻紫色描边光晕 + ◈ 角标（现状只有 ◈ 字符）。
2. 在每个玩家区域左侧提供**遗物物品栏**：透明背景、最多 3 个图标槽、`n/3` 计数、程序化图标（无图片资源）、Hover Tooltip（名称+描述+当前状态）。

## 2. 视觉方案

### 2.1 护盾卡面（常驻紫光描边 + ◈ 角标）

- `game_view._render_card_slot`：当 `slot.protected == true` 且卡面存在时：
  - 保留 ◈ 角标 Label（改主题色紫色，见 2.3 token）。
  - 新增常驻光晕：在卡 `CardView` 上叠加一个 `mouse_filter=IGNORE`、全 rect 的 `Panel`（`StyleBoxFlat`：透明底 + 紫边框 `relic_shield`，边框宽 3，圆角 6）。**常驻**，不随贴牌窗口开关变化。
- 光晕颜色随主题（dark/light 各配一套紫）。

### 2.2 遗物物品栏（每玩家区域左侧一条）

- 位置：四个玩家区域（`PlayerTop`/`PlayerLeft`/`PlayerRight`/`PlayerBottom`）各自**手牌 `HandGrid` 左侧**，垂直居中于该区域手牌高度。由 `game_view._render_player_section` 在渲染时创建/复用并按 `HandGrid.get_global_rect()` 绝对定位（与罚牌 `ExtraLayer` 同思路，不重排手牌）。
- 场景实体：`scenes/ui/relic_bar.tscn`（根 `Control` 定宽 ~44px） + 脚本 `scripts/ui/relic_bar.gd`（`class_name RelicBar`，`setup(state, seat)`）。
- 结构（垂直）：
  - 3 个图标槽（每个 32×32，间距 4），`scripts/ui/relic_icon.gd`（`class_name RelicIcon`，`extends Control`，`_draw()` 程序化绘制）。
  - 底部小字 `n/3`（`Label`，`text_secondary`，居中对齐）。
  - 背景：**透明**（不铺面板；可加极淡半透明圆角底 `bg_surface` alpha~0.25 提升可读性，属可选）。
- 图标绘制（`relic_icon.gd` `_draw()`）：
  - 盾形：`"shield"`，紫色 `relic_shield`——盾形多边形（外沿 + 内沿两层，或纯描边 + 半透明填充）。
  - 星形：`"joker"`，金色（复用 `accent`）——五角星多边形描边 + 半透明填充。
  - 空槽：`"empty"`，`border_strong` 极淡——空心圆角方块。
- 数据填充（`relic_bar.gd`，全部来自快照公开字段，`state = latest_state`）：
  - **Joker 变换**：`state.run.relic_owners` 中 `relic_joker_transform → seat`，且 `state.run.relics` 仍含该 id → 槽 1 金色星，tooltip `Joker 变换` + desc + `状态：本局可用`。
  - **防守护盾**：`state.players[seat].protected_slot >= 0` → 槽 2 紫色盾，tooltip `防守护盾` + desc + `状态：本局保护第 N 格`。
  - 其余空槽 → 空占位，tooltip `空遗物栏位`。
  - `n/3` = 已填充槽数 / 3。
  - **说明**：护盾被消耗后不在 `run.relics`/`relic_owners` 中，故盾图标按 `protected_slot>=0`（生效中）显示而非库存；Joker 按持有显示。两者均真实反映当前状态。
- Hover Tooltip：Godot 原生 `Control.tooltip_text`（多行文本，`\n` 分隔；`Joker 变换\n抽到 Joker 时可变换为任意牌（未变换时 Joker +2 分）\n状态：本局可用`；护盾同理，状态行带当前保护格号）。

### 2.3 主题 token（`ui_theme.gd`）

- dark：`"relic_shield": Color("b07be0")`；light：`"relic_shield": Color("8a5bbf")`。
- 金色沿用现有 `accent`（dark `f6d77a` / light `D9714F`）。
- 卡面光晕描边用 `relic_shield`；物品栏星/盾图标用对应色。

## 3. 组件与文件

| 文件 | 职责 |
| --- | --- |
| `scripts/ui/relic_icon.gd`（新增，`class_name RelicIcon`） | 程序化绘制盾/星/空槽图标（`_draw()`），`kind` + `color` 属性 |
| `scripts/ui/relic_bar.gd` + `scenes/ui/relic_bar.tscn`（新增，`class_name RelicBar`） | 3 槽 + `n/3` + tooltip；`setup(state, seat)` 填充 |
| `scripts/ui/game_view.gd`（改） | `_render_card_slot`：护盾紫光描边 + ◈ 改紫；`_render_player_section`：挂载并定位 RelicBar（`HandGrid` 左侧） |
| `scripts/ui/ui_theme.gd`（改） | 新增 `relic_shield` token（dark/light） |
| `scripts/ui/shop_panel.gd`（改，可选） | 商店遗物图标复用紫盾/金星（保持一致性） |

**不改**：服务器（`game_state.gd` 等）、协议、快照结构、贴牌时序。物品栏数据只读 `latest_state` 公开字段。

## 4. 数据流

```
snapshot (latest_state) --run.relics / run.relic_owners / players[].protected_slot--> RelicBar.setup(state, seat)
    -> 3 槽：Joker(金星) / 护盾(紫盾，按 protected_slot) / 空
    -> tooltip_text：名称 + 描述 + 状态
    -> n/3 计数
render 时机：game_view.render(state) 每次重建（与手牌同步，护盾槽/持有变化即时反映）
```

## 5. 测试与验证

- 纯客户端，无新增 headless 逻辑测试（不启 GUI）。验证：
  - `tools/run_all_tests.sh --quick` 全绿（12/12，含 verify_relics 19/19），确认 UI 改动不破坏编译/回归。
  - `--headless --path . --quit-after 5` 编译检查（新增 `relic_bar.gd`/`relic_icon.gd` 无脚本错误）。
- 手动（双开，开发者自行）：
  - 持 Joker 遗物 → 本人区域左侧金色星 + tooltip + `1/3`。
  - 护盾生效局 → 本人区域紫色盾 + tooltip 显示保护格号 + 卡面紫光描边 + ◈ 紫角标；他人可见。
  - 贴牌窗口开/关不影响紫光（常驻）。

## 6. 边界与不做

- 不做图片图标资源、不做物品栏拖拽/交互（纯展示）。
- 不做服务器端"护盾保留在库存"改动——护盾消耗即显示"生效中"。
- 物品栏只显示 v1 两件（3 槽为未来遗物预留）。
- 不启 GUI 开发验证（遵循交接说明 §8 约定）。