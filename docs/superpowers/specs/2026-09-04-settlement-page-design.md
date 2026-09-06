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
2. 弹层内播放 Balatro 式算分动画：**同步轮记分**——每轮所有玩家手牌的第 N 张**同时翻面**、各自累计分实时累加，每轮翻完排名表**实时重排**（低分=冠军置顶，整行上移/下移）。
3. 全部算完 → 排名榜首行名字播放**金色脉冲光环 + ★ 徽章**，并同步播放胜利音效（`AudioManager.play_winner()` 随机 1-4）。
4. 新增「再来一局」：房主在结算页一键开新局（无需回大厅），`match_number` 递增、重发手牌、回 INITIAL_PEEK。

## 3. 架构与新增文件

### 3.1 新增文件

| 文件 | 职责 | 可测试性 |
| --- | --- | --- |
| `scripts/core/settlement_model.gd` | 纯计算（RefCounted，不依赖 Node）：`layout_order`（左上顺时针）、`rounds`（同步轮记分）、`ranking_states`（每轮实时排名）。 | headless 单测 |
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

- 无全屏遮罩拦截（避免挡棋盘）：结算页为**居中浮动排名窗口**，`StyleBoxFlat` 圆角 + 边框（复用 UITheme token），宽度紧凑（~520px），**不遮挡四块玩家手牌区**（棋盘卡牌全程可见，逐个翻牌需看到棋盘）。
- 布局：
  - 顶部：标题「结算 · 第 N 局」。
  - 中央：**排名表（tab）**，表头 `名次 / 玩家 / 已翻开的牌 / 累计分`，**每行 = 一名玩家**：`[名次] [名字] [已翻开的牌] [累计分]`。
  - 已翻开的牌 v1 用**字母/数字文本**展示（如 `♠7`），后续可升级为 `assets/SmallCards` 小牌图（本期不做）。
- 关闭时机：收到新局快照（phase != GAME_OVER）或房主点「返回大厅」（`request_abort_match`）。

## 6. 算分动画（Balatro 式，同步轮记分）

### 6.1 模型（`settlement_model.gd`）

- 座位按「左上为 seat0、顺时针」排布（仅作视觉排布，非算分次序）。
- **算分 = 同步轮记分**：每轮所有玩家一起翻开各自第 N 张牌，各人 `running_total += 该牌值`；每轮翻完按累计分实时重排（低分=冠军置顶）。
- 模型输入：`turn_order`（座位数组）+ 快照 players（含手牌值）+ `result.ranking`。
- 产出：
  1. `layout_order`：座位顺序（左上起顺时针，视觉排布用）。
  2. `rounds`：每轮 = `{slot, flips: [{seat, value}], totals: [{seat, running_total}]}`（第 N 轮 = 所有人第 N 张牌的值 + 翻完后累计分）。
  3. `ranking_states`：每轮结束后的全量排名（复用 `ScoreSystem._is_lower_score` 排序，低分在前）。

### 6.2 动画时序（`settlement_page.gd` 本地播放）

- 对每一轮：
  1. 所有玩家该轮卡在各自行内**同时翻转**（v1 文本出现，带缩放/淡入），行内累计分 Label 数字滚动到新 `running_total`。
  2. 每轮间隔 ~0.6s（`create_tween` 串联）。
- 每轮翻完 → 排名表按 `ranking_states` **实时重排**：整行（含已翻的牌）做纵向上升/下降位移动画（如 ABC → CAB：C 上移、A/B 下移）。
- 全部轮次算完 → 进入冠军特效。整场动画目标 ≤10s（轮数 = 最大手牌数 ≤6，每轮 0.6s + 重排 0.4s）。

### 6.3 冠军特效

- 排名榜首行（冠军）：行内名字**金色脉冲光环**（`scale` 呼吸 + `modulate` 明暗闪烁）+ 名字旁 ★ 徽章 Label。
- 胜利音效：`main.gd:_on_sfx("winner")` 改为先缓存标志，冠军时刻由结算页回调触发 `AudioManager.play_winner()`（随机 1-4）。
- 例外：GAME_OVER 由 `reason` 路径触发（无 ranking，如全员离开）时结算页直接显示 reason 文本，不播放算分动画与冠军特效（reason 路径不广播 `winner` 事件，维持现状静默）。

## 7. 出口

- 冠军特效结束后显示出口区：
  - 房主：「再来一局」（`request_next_match`）+「返回大厅」（`request_abort_match`）。
  - 客户端：「等待房主开始下一局」提示（不显示按钮）。
- 收到新局快照（phase 离开 GAME_OVER）→ `main` 关闭结算页。
- 对局中止（abort）→ `_on_match_aborted` 已处理回大厅，结算页一并关闭。

## 8. 测试（`tests/verify_settlement.gd`）

1. `layout_order`：座位顺序（左上起顺时针）；2/3/4 人均正确。
2. `rounds`：轮数 = 最大手牌数；每轮 flips 含全员该张牌值；每轮 totals 的 running_total = 前几轮累计 + 本轮值。
3. `ranking_states`：每轮结束排名与全量 `calculate_ranking`（按已翻牌的累计分）一致，低分在前。
4. `_server_next_match`：GAME_OVER + 房主 → 成功，`match_number`+1、回 INITIAL_PEEK、手牌重发（每人 6 张）、`initial_confirmed` 清空。
5. 拒绝分支：非 GAME_OVER（TURN_DRAW）拒绝；非房主（seat1）拒绝；`_reject` 走 `command_rejected`。
6. 回归：`verify_protocol`/`verify_swap`/`verify_duel`/`verify_reconnect`/`verify_kongbaya`/`verify_hint`/双实例 `verify_net` 全绿。

## 9. 文档与提交

- 改协议前先更新 `docs/网络协议_V1.md`（新增 `server_next_match`/`request_next_match` 契约与错误码）。
- 更新 `docs/KONG_开发文档.md`（补结算展示规则条目，随实现按现有编号续排）、`docs/功能实现文档.md`（文件树 + Feature 映射）。
- 提交按 `feat:` 分类，`git push origin tab-winner`（经用户确认后）。
- 用户每次 request 结束向 `docs/修改日志.md`（gitignore）追加记录。