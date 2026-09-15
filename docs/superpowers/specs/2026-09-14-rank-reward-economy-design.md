# KONG 名次奖励经济 + 生命值 + 局内金钱/生命 HUD 设计稿

> **状态**：已批准（2026-09-14）· 仅设计稿，未实现
> **关联文档**：`KONG_开发文档.md`（规则权威）、`AI_AGENT_交接说明.md`（工程现状）、`网络协议_V1.md`（协议契约）
> **前置**：本文替代 `2026-09-07-series-shop-relics-design.md` §4（押注经济）与 `KONG_开发文档.md` R-09。实现前需按 `KONG_开发文档.md` §9 的流程登记规则变更（新增 R-12、标记 R-09 作废）、更新协议文档、补测试项。

---

## 1. 目标

把"押注博弈"换成**更直观的名次经济**：取消开局押注阶段，结算时**直接按名次**发放金钱、由垫底扣生命。同时把金钱/生命从玩家名字标签下移，改为每个玩家区域**手牌右侧的紧凑 HUD**（铜钱数字 + 生命图标个数）。

- 基础不变量不变：服务器权威、私有快照、贴牌时序。
- 金钱与生命均为**公开信息**，HUD 只读快照公开字段（`players[].currency` / `players[].health`），不新增隐藏信息。
- 不引入新遗物、不改贴牌时序、不改商店固定价与 R-10/R-11。

## 2. 术语

- **名次奖励（rank reward）**：结算时按玩家最终排名发放的金钱（系统发放，非零和）。
- **生命（life）**：复用 `health` 字段，默认 **2**（替代原"灵魂币"），垫底扣 1，为 0 出局观战。
- **中间名次**：名次既非第一、也非垫底的所有玩家。
- **HUD**：每个玩家区域手牌右侧的金钱/生命展示块（纯展示）。

## 3. 规则裁定（新增 R-12，R-09 作废）

### 3.1 流程改动

- **取消押注阶段**：`Phase.BET`（值 9）**保留为弃用值**（不删除、不挪动数值），保证 `Phase.SHOP`（值 10）及协议/测试的数值稳定；任何流程不再进入该阶段。
- 开局记忆（`INITIAL_PEEK`）全员确认后，**直接进入正式回合**：`current_player_id = _alive_order()[0]`、`phase = TURN_DRAW`。

### 3.2 结算发钱（系统，纯名次）

设一局存活人数 `N`（`N >= 2`）。把存活玩家按现有 `ScoreSystem` 排序（总分 → 牌数 → 逐张大牌 → id）得到名次 `0..N-1`：

| 名次 | 金钱 |
| --- | ---: |
| 第 1（index 0，最低分） | **+40** |
| 中间名次（0 < index < N-1） | **+10** |
| 垫底（index N-1，最高分） | **0** |

- **并列处理**：同分玩家组成并列组，占据连续名次区间 `[a..b]`。
  - **非垫底组**：每人 = 区间内各名次奖励之和 ÷ 组人数（向下取整，余数丢弃）。
  - **垫底组（含并列垫底）**：即组触及末位（`b == N-1`）时，整组奖励为 **0**（不参与均分，末位奖励本就为 0）。
  - 例（4 人）：2 人并列第 1 → `(40 + 10) / 2 = 25` 每人；2 人并列垫底 → `0` 每人。
- **全员同分（显式例外，沿用 R-03 精神）**：无人第一、无人垫底 → **不套用上面的区间平分**，全部 `+10`，且**无人扣生命**。
- 货币**下限 0**（本规则下不再有扣钱，仍保留保护，不允许负数）。
- **仅一名玩家参与排名**（`N == 1`，如手牌超限后只剩一人）：该玩家**不算垫底**，不扣生命、不惩罚；奖励按末位规则为 0。

### 3.3 生命与淘汰

- 起始 **2 生命**（`health` 默认 2）。
- **垫底（含并列垫底）每人 −1 生命**；`health == 0` → 出局观战（`eliminated` 保留座位、仅公开信息、不可操作）。
- **淘汰延后一局生效**：某玩家在结算中生命归零时，**本局仍按正常参与者结算与展示**（计入本局排名与结算页），从**下一局**起才标记观战、不参与排名。实现上以 `eliminated_match`（出局局号）判定：仅当 `match_number > eliminated_match` 时快照 `eliminated=true`。
- 一局中一名玩家最多因"垫底"扣 1 生命（不叠加名次）。
- 出局玩家**保留其货币**，参与把末最终排名。
- 一局后 `health` 不会自动恢复（跨局累计消耗）。

### 3.4 特殊失败并入

- **R-07 手牌超限失败者**：按"垫底"处理 → 本局金钱奖励 **0** 且 **−1 生命**；其余玩家按其手牌点数正常排名发钱。
- **首回合 Kongbaya 失败者**（R-06 相关）：按"垫底"处理 → **0 金钱、−1 生命**。
- 若失败者与其他垫底同名次，同罚（不重复扣血：一名玩家一局最多扣 1）。

### 3.5 系列赛与其他不变项

- 系列赛结束（把末）判定、出局观战、把末排名（胜场降序 → 货币降序）**沿用 R-08 不变**。
- 商店固定价、遗物效果 **沿用 R-10/R-11 不变**；商店是货币的唯一回收点。
- `wins` 累加：第一（并列每组）各计 1 胜场。

### 3.6 R-12 条文（写入 `KONG_开发文档.md`）

> **R-12**（替代 R-09）：取消开局押注。每位玩家起始 **100 货币 + 2 生命**。每局结算按名次由系统发放金钱：第一 +40、中间 +10、垫底 0；并列组平分区间奖励。**垫底（含并列）扣 1 生命**，生命为 0 出局观战；手牌超限失败者与首回合 Kongbaya 失败者按垫底处理。货币不扣、下限 0，出局者保留货币参与把末排名；把末与商店沿用 R-08/R-10/R-11。

## 4. 经济模型与估计

**每局系统净注入**（4 人桌，无货币惩罚）：`40 + 10 + 10 + 0 = +60`。

| | 每局（4 人桌） | 5 局累计 | 人均 |
| --- | ---: | ---: | ---: |
| 系统注入 | +60 | +300 | +75 |
| 起始 → 终局均值 | | | 100 → **~175** |

- 商店 50：起始即可买 2 件；平均每局 +15，约每 3 局再攒 1 件。**轻度到中度通胀**。
- 唯一回收点是商店（v1 池 2 件×50 = 最多 100/局）。遗物池扩大后回收能力增强。
- 调节旋钮（以后按需）：中间名次 +10 可降为 0、或商店涨价、或扩充遗物池。
- 生命经济：起始 2，垫底两次即出局；一个系列赛（默认 5 局）足以产生淘汰与把末提前结束。

## 5. 协议 / 快照改动（`网络协议_V1.md`）

- **移除**：`bet` RPC、`request_bet` 入口、快照 `bet_ready`、内部 `bets`。
- **字段**：`players[].health` 默认值由 1 改 **2**；`run_state.health` 默认 2。
- **结果字段**：`result.economy`（旧押注明细）**替换为** `result.rewards`：
  ```
  result.rewards = { <SeatId>: { "money": Integer, "life_lost": Integer } }
  ```
  非 GAME_OVER 时为空；`result.penalized` 语义改为"本局因垫底/超限/首回合 Kong 扣血者"。
- 快照仍**公开** `currency` / `health`（HUD 只读）。
- 错误码 `INVALID_AMOUNT`（押注专用）**保留但不再触发**（不删，避免动错误码枚举）；不新增错误码。

## 6. UI 设计（每玩家区域 HUD）

### 6.1 位置

- 从玩家名字标签**移除**货币文案（`game_view._render_player_section` 的 `name_label.text` 去掉 `· 货币 %d`）。
- 每个玩家区域手牌**右侧**新增一个紧凑 HUD；左侧已有遗物栏 `RelicBar`，左右对称。
- 复用 `RelicBar` 的定位模式：`_render_player_section` 末尾按 `HandGrid.get_global_rect()` 定位，并监听 `HandGrid.resized` 在容器布局落定时重新定位（与 `RelicBar` 的定位/时序修复同法）。

### 6.2 内容

- **上排：铜钱图标 + 数字**（如 `🪙 175`）。
- **下排：生命 = N 个心形图标**（个数 = `players[].health`）。
- 出局玩家（`health == 0`）：生命图标全暗/空，名字保持 `[已淘汰·观战]`。

### 6.3 图标（程序化，不引入图片资源）

- `scripts/ui/coin_icon.gd`（`class_name CoinIcon`，`extends Control`，`_draw()` 画**外圆内方**铜钱：外圆描边 + 方孔）。
- `scripts/ui/life_icon.gd`（`class_name LifeIcon`，`extends Control`，`_draw()` 画心形）。
- 与现有 `relic_icon.gd` 同风格。颜色取 `UITheme`：铜钱用金色/`accent`，生命用红色/`danger`。
- 封装到 `scripts/ui/stat_hud.gd`（`class_name StatHud`，`setup(state, seat)` 填充），可选 `scenes/ui/stat_hud.tscn`。

### 6.4 数据来源

- 全部来自 `main.latest_state` 的公开字段：`players[].currency`、`players[].health`。
- 纯展示、无协议改动；不读取暗牌，不破坏 B1/B6/B7 等既有 UI 约束。

## 7. 架构落点

| 组件 | 落点 |
| --- | --- |
| 取消押注、记忆后直入回合 | `game_state.gd`（`_server_initial_ready` 分支；移除 `_start_bet_phase`/`_server_bet`/`_commit_bet`/`bets` 调用） |
| 名次发钱 + 扣血 | `game_state.gd`（`_finish_game` → 新 `_settle_rewards`，替代 `_settle_economy`） |
| 名次→奖励纯计算 | 可放 `score_system.gd` 或独立纯函数（headless 可测） |
| 起始生命 2 | `game_rules.gd`（`new_default_run` / `START_HEALTH`）、`game_state.gd` 默认值 |
| 快照字段 | `hidden_info.gd`（移除 `bet_ready`、补 `result.rewards`、`health` 默认 2） |
| 每玩家 HUD | `game_view.gd` + 新增 `stat_hud.gd`/`coin_icon.gd`/`life_icon.gd` |
| 押注面板下线 | `main.gd` 移除 `_open_bet_panel`/`_close_bet_panel` 调用；`bet_panel.tscn`/`bet_panel.gd` 可保留但不再实例化 |
| 结算页 | `settlement_page.gd` 展示名次奖励明细（用 `result.rewards` 替代 `result.economy`） |

## 8. 影响文件清单

**改**
- `scripts/core/game_rules.gd`（停用押注常量 `MIN_BET/MAX_BET/BET_STEP/SAFE_RETURN/WINNER_RETURN`；若保留 `INVALID_AMOUNT` 文案则同步改写其依赖的常量引用；新增 `START_HEALTH=2`、名次奖励常量）
- `scripts/core/game_state.gd`（删押注流程、新增 `_settle_rewards`、起始生命、`result.rewards`）
- `scripts/core/hidden_info.gd`（快照字段）
- `scripts/core/settlement_model.gd`（如需展示奖励）
- `scripts/ui/game_view.gd`（名字标签去货币、挂载 HUD）
- `scripts/ui/main.gd`（移除押注面板调用、关闭押注相关）
- `scripts/ui/settlement_page.gd`（奖励明细）
- `docs/KONG_开发文档.md`（R-12，R-09 标记作废）
- `docs/网络协议_V1.md`（移除 bet、`result.rewards`、health 默认 2）
- `docs/AI_AGENT_交接说明.md`、`docs/功能实现文档.md`（基线更新）

**新增**
- `scripts/ui/coin_icon.gd`、`scripts/ui/life_icon.gd`、`scripts/ui/stat_hud.gd`（+ 可选 `scenes/ui/stat_hud.tscn`）
- `docs/superpowers/specs/2026-09-14-rank-reward-economy-design.md`（本文）

**测试**
- 重写 `tests/verify_economy.gd`（名次发钱/并列平分/垫底扣血/2 命淘汰/超限与首回合 Kong 并入/货币下限）
- 更新 `tests/verify_series.gd`、`verify_settlement.gd`、`verify_shop.gd`、`verify_protocol.gd`（移除 BET 假设、`health` 默认 2、`result.rewards`）

## 9. 测试计划（headless，不启 GUI）

| 套件 | 覆盖 |
| --- | --- |
| `verify_economy`（重写） | 首名 +40、中间 +10、垫底 0 且 −1 命；并列平分/同罚；全员同分不扣血；2 命垫底两次出局；超限/首回合 Kong 按垫底；货币下限 0；出局保留货币；`result.rewards` |
| `verify_series` | 系列赛生命周期不变项回归（把末/观战/总排名） |
| `verify_settlement` | 结算页读取 `result.rewards` 无回归 |
| `verify_shop` | 商店购买不受影响 |
| `verify_protocol` | 移除 `bet` 相关断言，`health` 默认 2 |

- 回归基准：`tools/run_all_tests.sh` 全量保持全绿。
- **附带修复**：`docs/问题档案.md` Q-01（`verify_proxy` 在 BET 阶段卡死）随押注阶段移除**自然消失**，proxy 五场景应恢复全绿。

## 10. 里程碑（每阶段独立可测）

1. **服务器规则**：删押注、起始 2 命、`_settle_rewards`、`result.rewards`；重写 `verify_economy`。
2. **快照与协议文档**：`hidden_info` + `网络协议_V1.md` + `KONG_开发文档.md` R-12。
3. **局内 HUD**：`coin_icon`/`life_icon`/`stat_hud` + `game_view` 接入 + 名字标签去货币。
4. **结算页/清理**：`settlement_page` 奖励明细、移除押注面板调用、全量回归。

## 11. 未决项

- 名次奖励数值（+40/+10/0）为初值，封测后按胜率/经济曲线调整。
- 中间名次是否长期 +10，或后续改为只奖第一（抑制通胀的旋钮）。
- 商店是否随遗物池扩大而浮动定价。
- 生命上限是否固定 2，或后续遗物/事件可增减。
