# 结算页面 + 算分动画 + 再来一局（设计）

> 日期：2026-09-04
> 分支：`tab-winner`
> 目的：把对局结束（GAME_OVER）时堆在右下角的结算信息，升级为居中的结算弹层；加入 Balatro 式逐张翻牌算分动画（左上顺时针、实时排名重排）、冠军特效（名字光环 + 徽章），并新增「再来一局」流程。
> 方案：A（纯客户端结算弹层 + 纯计算模型类 + 1 个新服务器 RPC）。符合项目「代码构建 UI + 逻辑纯计算可测试」的既有模式。

## 1. 现状与问题

- 结算信息目前全部堆在右下角 `Corner/ControlsBox`（`game_view.gd:_render_controls` PHASE_GAME_OVER 分支）：只有一行「获胜：xxx」摘要，不居中、无算分过程、无冠军表现。
- GAME_OVER 阶段快照已 `reveal_all=true`（所有玩家手牌含 rank/suit/value 对所有人公开），`last_result` 含 `ranking`/`winners`/`penalized`。**结算页无需协议新增数据**，只需新加「再来一局」流程的 RPC。
- `match_number` 目前只在 `_reset_match` 置 1，从无递增；`_server_start_match` 要求 `phase == LOBBY`。对局结束后没有直接开新局的路径。
- 结算页打开后需在收到新局快照（phase 离开 GAME_OVER）时自动关闭。

## 2. 目标

1. GAME_OVER 时自动弹出居中的结算弹层（全屏遮罩 + 宽面板，仿 `settings_menu` 但更宽），替代右下角摘要。
2. 弹层内播放 Balatro 式算分动画：按左上顺时针顺序，每名玩家手牌**逐张翻面**、每张弹 `+值` 气泡、总分数字滚动累加；每算完一名玩家，排名榜**实时重排**（低分=冠军置顶）。
3. 全部算完 → 排名榜首名字播放**金色脉冲光环 + ★ 徽章**，并同步播放胜利音效（`AudioManager.play_winner()` 随机 1-4）。
4. 新增「再来一局」：房主在结算页一键开新局（无需回大厅），`match_number` 递增、重发手牌、回 INITIAL_PEEK。

## 3. 架构与新增文件

### 3.1 新增文件

| 文件 | 职责 | 可测试性 |
| --- | --- | --- |
| `scripts/core/settlement_model.gd` | 纯计算（RefCounted，不依赖 Node）：算分顺序、逐张翻牌增量序列、实时排名重排。 | headless 单测 |
| `scripts/ui/settlement_page.gd` | 结算弹层（Control，代码构建，仿 `settings_menu`/`duel_bar`）：布局 + 动画时序 + 冠军特效 + 出口按钮。 | 不单测（UI 动画） |
| `tests/verify_settlement.gd`（+`.tscn`） | 验证结算模型 + `_server_next_match` 流程。 | headless |

### 3.2 修改文件

| 文件 | 修改 |
| --- | --- |
| `scripts/core/game_state.gd` | 新增 `request_next_match`/`server_next_match`/`_server_next_match`；抽出共用 `_deal_new_match()`；`match_number += 1`。 |
| `scripts/ui/main.gd` | GAME_OVER 阶段创建/关闭结算页；缓存 `sfx_played("winner")` 到冠军时刻再播；`request_next_match` 转发。 |
| `scenes/ui/game_board.tscn`（可选） | 若用现有 Corner 按钮，无需改；结算页为独立弹层。 |
| `docs/网络协议_V1.md` | 新增 `next_match` RPC 说明。 |
| `docs/KONG_开发文档.md` | 补充结算页展示规则（R-xx）。 |
| `docs/功能实现文档.md` | 文件树 + Feature 映射补记。 |

## 4. 服务器：再来一局流程（`game_state.gd`）

```gdscript
func request_next_match(action_id := "") -> void:
    if multiplayer.is_server():
        _server_next_match(_peer_to_seat(1), action_id)
    else:
        server_next_match.rpc_id(1, action_id)

@rpc("any_peer", "reliable")
func server_next_match(action_id: String) -> void:
    if multiplayer.is_server():
        _server_next_match(_peer_to_seat(multiplayer.get_remote_sender_id()), action_id)

func _server_next_match(sender: int, action_id := "") -> void:
    if phase != Phase.GAME_OVER:
        _reject(sender, RejectCode.INVALID_PHASE, action_id)
        return
    if sender != 0:
        _reject(sender, RejectCode.NOT_HOST, action_id)
        return
    if players.size() < KongRules.MIN_PLAYERS:
        _reject(sender, RejectCode.NOT_ENOUGH_PLAYERS, action_id)
        return
    _deal_new_match()
```

`_deal_new_match()` 抽自 `_server_start_match` 的发牌段：新 `match_id`、建牌组、清每人手牌/`has_acted`、发 `HAND_SIZE` 张、`phase=INITIAL_PEEK`、清 `initial_confirmed`、`match_number += 1`、写日志、`_broadcast_state()`。`_server_start_match` 改为调用同一函数（保 LOBBY 校验不变）。

> 不变量保持：仅房主、仅 GAME_OVER 允许；seat/peer 语义不变；不新增其它协议字段。

## 5. 结算弹层 UI（`settlement_page.gd`）

- 全屏遮罩 `ColorRect`（点击不关闭，防误触）+ 居中 `CenterContainer` + 宽面板（`custom_minimum_size` ~ 720×540，`StyleBoxFlat` 圆角 + 边框，复用 UITheme token）。
- 布局：
  - 顶部：标题「结算」+ 第 N 局。
  - 中部：**中央牌桌区**——玩家按座位围成圆圈（seat0 在左上，其余顺时针排），每位玩家显示名字 + 手牌（初始全部背面）。
  - 右侧：**排名榜**（纵向列表）实时重排，低分在前（冠军置顶），初始显示「…」待算。
- 关闭时机：收到新局快照（phase != GAME_OVER）或房主点「返回大厅」（`request_abort_match`）。

## 6. 算分动画（Balatro 式，逐张翻牌）

### 6.1 算分顺序（`settlement_model.gd`）

- 座位按「左上为 seat0、顺时针」排布；**算分顺序 = 座位顺序 0,1,2,…（顺时针）**。
- 模型输入：`turn_order`（座位数组）+ 快照 players（含手牌值）+ `result.ranking`。
- 产出：
  1. `scoring_order`：座位顺序（顺时针起点左上）。
  2. 每玩家 `steps`：逐张牌的 `{slot, value, running_total}` 增量序列。
  3. 每玩家算完后的 `ranking_states`：每次插入后已算完玩家的排名重排结果（复用 `ScoreSystem._is_lower_score` 排序）。

### 6.2 动画时序（`settlement_page.gd` 本地播放）

- 对算分顺序中每名玩家：
  1. 依次翻开其每张手牌（正面显示 rank/suit），每张弹出 `+值` 气泡（缩放淡出），总分 Label 数字滚动到新值。
  2. 每张间隔 ~0.6s（`create_tween` 串联）。
- 该玩家算完 → 把其条目插入排名榜，按 `_is_lower_score` 实时重排（条目做位移动画或直接刷新）。
- 全部算完 → 进入冠军特效。整场动画目标 ≤10s（2-4 人 × 2-6 张 × 0.6s，上限 N 大时抽样加速：每张间隔可降到 0.3s）。

### 6.3 冠军特效

- 排名榜首名字：金色脉冲光环（`scale` 呼吸 + `modulate` 明暗闪烁）+ 名字旁 ★ 徽章 Label。
- 胜利音效：`main.gd:_on_sfx("winner")` 改为先缓存标志，冠军时刻由结算页回调触发 `AudioManager.play_winner()`（随机 1-4）。
- 例外：GAME_OVER 由 `reason` 路径触发（无 ranking，如全员离开）时结算页直接显示 reason 文本，不播放算分动画与冠军特效（reason 路径不广播 `winner` 事件，维持现状静默）。

## 7. 出口

- 冠军特效结束后显示出口区：
  - 房主：「再来一局」（`request_next_match`）+「返回大厅」（`request_abort_match`）。
  - 客户端：「等待房主开始下一局」提示（不显示按钮）。
- 收到新局快照（phase 离开 GAME_OVER）→ `main` 关闭结算页。
- 对局中止（abort）→ `_on_match_aborted` 已处理回大厅，结算页一并关闭。

## 8. 测试（`tests/verify_settlement.gd`）

1. 算分顺序：`scoring_order` = 座位顺序（左上起顺时针）；2/3/4 人均正确。
2. 增量序列：每玩家 steps 求和 = 快照 score；running_total 单调递增。
3. 实时排名重排：每次插入后的 `ranking_states` 与全量 `calculate_ranking` 一致（低分在前）。
4. `_server_next_match`：GAME_OVER + 房主 → 成功，`match_number`+1、回 INITIAL_PEEK、手牌重发（每人 6 张）、`initial_confirmed` 清空。
5. 拒绝分支：非 GAME_OVER（TURN_DRAW）拒绝；非房主（seat1）拒绝；`_reject` 走 `command_rejected`。
6. 回归：`verify_protocol`/`verify_swap`/`verify_duel`/`verify_reconnect`/`verify_kongbaya`/`verify_hint`/双实例 `verify_net` 全绿。

## 9. 文档与提交

- 改协议前先更新 `docs/网络协议_V1.md`（新增 `server_next_match`/`request_next_match` 契约与错误码）。
- 更新 `docs/KONG_开发文档.md`（补结算展示规则条目，随实现按现有编号续排）、`docs/功能实现文档.md`（文件树 + Feature 映射）。
- 提交按 `feat:` 分类，`git push origin tab-winner`（经用户确认后）。
- 用户每次 request 结束向 `docs/修改日志.md`（gitignore）追加记录。