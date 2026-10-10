# KONG 3D Hint HUD：SLAP 状态行 + 装饰进度条 设计 v1

> **目的**：在 3D 的 `HintHud`（顶部居中：倒计时胶囊 + hint 文本）中新增一行 **SLAP 状态**（绿色 `SLAP OPEN` / 红色 `SLAP CLOSE`）与其下方一条**装饰性进度条**。文字全部**居中**。
> **范围**：仅 3D（`HintHud`）。纯客户端展示层：**不改**规则 / 协议 / 快照 / `scripts/core/*` / `scripts/net/*`。2D 对局界面不动。
> **分支**：`agent/feature-uiboard`。

## 1. 目标与非目标

**目标**

1. 3D 下把原先拼在 hint 文本里的 "SLAP open" 拆成**独立一行**（在 hint 文本下方）；`SLAP OPEN` 绿色。
2. 成功贴牌后该行变红色 `SLAP CLOSE`。
3. 该行下方一条**装饰性进度条**（固定时长、满→空递减），走空即**整行消失**。
4. 所有文字（hint、SLAP 状态）**水平居中**；进度条也居中。
5. 零协议改动：只用快照已有的 `slap_open` 与 `phase`。

**非目标**

- 不改协议 / 快照 / 服务器（进度条是纯装饰，不对应真实窗口时长）。
- 不改 2D 对局界面。
- 不改倒计时胶囊语义（回合计时）。
- 不做真实 slap 窗口计时（未来若服务器加时长再接）。

## 2. 数据（客户端已有）

| 字段 | 含义 |
| --- | --- |
| `slap_open`（bool） | 贴牌窗口开（上一玩家弃牌/用技能后，直到下一玩家抽牌） |
| `phase` | `SLAP_EXCHANGE` / `SLAP_DUEL` = 成功贴牌后的交接/比拼阶段 |

无需新增任何字段。

## 3. SLAP 行状态机（`HintHud` 内，`main` 每帧/每渲染喂状态）

常量：`SLAP_HIDDEN = 0`、`SLAP_OPEN = 1`、`SLAP_CLOSE = 2`。

| 状态 | 进入条件（`main` 计算） | 视觉 |
| --- | --- | --- |
| `OPEN` | `slap_open == true`（且非下条） | 绿 `SLAP OPEN` + 装饰条满→空递减 |
| `CLOSE` | `phase ∈ {SLAP_EXCHANGE, SLAP_DUEL}` | 红 `SLAP CLOSE`（无条） |
| `HIDDEN` | 其余（含 `slap_open==false` 静默关闭） | 整行隐藏 |

规则：

- **新窗口重置**：`OPEN` 由非 `OPEN` 转入时（`HIDDEN/CLOSE → OPEN`）重置装饰条为满、`_slap_exhausted=false`、重新计时（用状态转换检测，避免每次状态广播重播）。
- **装饰条走空**：`OPEN` 且计时到 0 → `_slap_exhausted=true`，整行隐藏（状态仍是 `OPEN` 但视觉 `HIDDEN`，直到窗口真实关闭或新窗口）。
- **成功贴牌**：`OPEN → CLOSE`（红），装饰条隐藏；离开 `SLAP_EXCHANGE/SLAP_DUEL` → `HIDDEN`。
- **静默关闭**（下一玩家抽牌，无人贴中）：`OPEN → HIDDEN`，不弹红。

## 4. 布局与视觉（顶部居中，自上而下）

```
[ 倒计时胶囊 ]                （现有，居中）
[ hint 文本 ]                 （现有，居中，可换行）
[ SLAP OPEN / SLAP CLOSE ]    （新增，居中，绿/红，字号 ~16 粗体）
[ ━━━━━━━━━━━░░░░ ]           （新增，居中，细条满→空）
```

- `HintHud` 新增子节点：`_slap_label`（`Label`，`HORIZONTAL_ALIGNMENT_CENTER`）、`_slap_bar`（宽度固定、居中）。
- `_layout()` 只按**当前可见行**累计高度：`pill + (hint) + (slap 行若可见) + (bar 若可见)`；行隐藏时不占高度。
- 文字居中：`_slap_label` 水平居中；条宽度固定（如 260）在根宽内居中。
- 颜色：`SLAP_OPEN_COLOR = UITheme success（绿，如 #87d9a1）`、`SLAP_CLOSE_COLOR = UITheme danger（红，如 #ff7b7b）`；条填充绿色、底为半透明深色。
- 出现/消失可加极短淡入淡出（≤0.15s），与面板风格一致（可选，默认直接切换也可）。

### 进度条实现

- 用 `ProgressBar`（`max_value = 1.0`，`value` 由剩余比例驱动；`show_percentage = false`），或 `Panel` + `ColorRect` 手动宽度。
- 时长常量 `SLAP_BAR_SECONDS := 10.0`（可调）；`_process` 里在 `OPEN` 且未 exhausted 时递减并刷新。
- 走空：`value=0`，随即整行隐藏。

## 5. 文案

- `HintText.hint` 的 `TURN_DRAW` 分支：**移除** `" · SLAP open: click matching card"` 后缀（改由状态行表达）。
- 状态行文本：`"SLAP OPEN"` / `"SLAP CLOSE"`。如需"点击同点数牌"提示，可拼在 `SLAP OPEN` 行尾。

## 6. 接线（`main._update_hint_hud`）

```
var slap_state := HintHud.SLAP_HIDDEN
if phase == PHASE_SLAP_EXCHANGE or phase == PHASE_SLAP_DUEL:
    slap_state = HintHud.SLAP_CLOSE
elif bool(latest_state.get("slap_open", false)):
    slap_state = HintHud.SLAP_OPEN
_hint_hud.set_slap_state(slap_state)
```

- `HintHud._process` 增加装饰条递减（与倒计时胶囊同在 `_process`）。
- `set_slap_state` 内做状态转换检测与重置。

## 7. 测试与验收

`tests/verify_hint_hud.gd` 新增：

- `set_slap_state(OPEN)` → 行可见、绿、文本 `SLAP OPEN`、条可见且 `value≈1`。
- 转换进 `OPEN` 时重置条（模拟中途 render 重发 `OPEN`，条不重置；`HIDDEN→OPEN` 才重置）。
- `set_slap_state(CLOSE)` → 红、文本 `SLAP CLOSE`、条隐藏。
- `set_slap_state(HIDDEN)` → 整行隐藏且不占布局高度。
- 走空：把时长调小/直接 tick 到 0 → 整行隐藏（状态仍 `OPEN` 但视觉隐藏）。
- 居中：`_slap_label.horizontal_alignment == CENTER`；条在根宽内居中。
- 回归：`verify_hint`（`_hint_for` TURN_DRAW 不再含 slap 后缀，检查仍成立）/ `verify_board3d` / `verify_table3d_exchange` 全绿。

**验收闸门**：新增断言全绿；`tools/run_all_tests.sh --quick` 全绿；`git diff` 确认 `scripts/core/*`、`scripts/net/*`、2D 文件零改动。

## 8. 文件清单

| 文件 | 变更 |
| --- | --- |
| `scripts/ui/hint_hud.gd` | 新增 `_slap_label` + `_slap_bar`、`SLAP_*` 状态与常量、`set_slap_state`、装饰条计时、`_layout()` 计入可见行 |
| `scripts/ui/main.gd` | `_update_hint_hud` 计算并喂 `set_slap_state` |
| `scripts/ui/hint_text.gd` | `TURN_DRAW` 移除 slap 后缀 |
| `tests/verify_hint_hud.gd` | 新增 SLAP 行/条断言 |
| `docs/功能实现文档.md` / `docs/AI_AGENT_交接说明.md` | 补一句 |

**不改**：`scripts/core/*`、`scripts/net/*`、`scenes/ui/*`、2D 文件。

## 9. 参数（初值，可调）

| 常量 | 初值 | 说明 |
| --- | --- | --- |
| `SLAP_BAR_SECONDS` | `10.0` | 装饰条满→空时长 |
| `SLAP_BAR_W` | `260.0` | 条宽（居中） |
| `SLAP_BAR_H` | `8.0` | 条高 |
| `SLAP_FONT` | `16` | 状态行字号 |
| `SLAP_OPEN_COLOR` | `#87d9a1`（success） | 绿 |
| `SLAP_CLOSE_COLOR` | `#ff7b7b`（danger） | 红 |
