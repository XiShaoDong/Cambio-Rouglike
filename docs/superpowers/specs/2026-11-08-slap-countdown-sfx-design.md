# 结算贴牌倒计时 + 音效强化 设计

> 纯客户端展示层：不改规则 / 协议 / 快照 / 服务器。目标：把 3s 结算贴牌窗口做得更有压迫感，并让抽牌/弃牌/贴牌成功失败/触发/倒计时/点击的声音更明显。

## 1. 贴牌窗口倒计时（普通 + 结算）

- `HintHud` 新增 `settle` 模式：`SLAP SETTLE 3 → 2 → 1`，大字号（24px），条填充色同步。
  - 3 → 绿 `#87d9a1`
  - 2 → 黄 `#ffc857`
  - 1 → 红 `#ff6b6b`
- **普通贴牌窗口同样显示 `SLAP OPEN 3/2/1`**（纯视觉 3s；窗口可能长于 3s）。走空后保留 `SLAP OPEN`（隐藏数字/条），直到窗口关闭。
- 结算窗口文案用 `SLAP SETTLE 3/2/1`。
- 窗口结束/提前贴中：行隐藏或切 `SLAP CLOSE`，倒计时音停止。
- 快照 `settle_deadline_server_ms` 只用来判断"是否处于结算窗口"；普通/结算的秒数都用本地 3s 递减。

## 2. 倒计时音

- 素材 `assets/Sounds2/countdown.wav`：波形在 0/1/2/3 秒各有一声 beep（其后静音）。
- 3s 窗口只需要 3 声：**跳过最开始的 1s，从 1s 播到 4s**（`COUNTDOWN_START_SEC=1.0`、`COUNTDOWN_PLAY_SECONDS=3.0`），不逐秒重复播；窗口提前结束时 `stop()`。
- 由 `main._sync_sfx_state(state)` 触发：**只有结算窗口** `settle_deadline_server_ms` 0→>0 播一次；普通窗口只显示视觉 3/2/1，不播 countdown（避免每轮都响）。窗口关闭/结束停止。2D/3D 都生效。

## 3. 音效映射（`assets/Sounds2/`）

| 事件 | 文件 | 触发点 | 增益 |
| --- | --- | --- | --- |
| 抽牌 | `card-slide-8.ogg` | `main` 检测 `pending` 空→非空 | +2 dB |
| 弃牌 | `card-place.ogg` | `card_exchange_animated` 的 `replace`/`discard`/`slap_resolved` | +2 dB |
| 贴牌成功 | `slap-success.wav` | `_show_private_reveal` 且 `target.correct == true` | +4 dB |
| 贴牌失败 | `slap-fail.ogg` | `_show_private_reveal` 且 `target.correct == false` | +4 dB |
| 触发 | `notification.ogg` | `effect_trigger` / `bomb_explode` / 开局特效展示 | +3 dB |
| 倒计时 | `countdown.wav` | 结算贴牌窗口开始 | +3 dB |
| 点击 | `tech-click.wav` | `play_select()`：Ready（2D/3D）、商店所有按钮、设置 | +1 dB |
| 发牌 | `card-shuffle.ogg` | 新局 `match_id` 变化且 `phase=INITIAL_PEEK`；只播前 1.8s | +2 dB |

- 旧音效（翻牌/飞牌/铃铛/胜利）保持不变。
- 播放器池 6 → 10，避免叠音被抢；倒计时使用**独立播放器**，不被池覆盖，且可单独停止。
- `AudioManager` 增加 `last_event` 调试字段，供 headless 测试断言。

## 4. 测试

- `verify_hint_hud`：普通 OPEN 无倒计时；settle 3 绿 / 2 黄 / 1 红；走空隐藏。
- 新增 `verify_audio_sfx`：7 个 Sounds2 资源已绑定；`play_draw/discard/slap_success/slap_fail/trigger/countdown/select` 更新 `last_event`；`stop_countdown` 不报错。
- `main._sync_sfx_state`：pending 触发 draw；`settle_deadline_server_ms` 触发 countdown/stop。
- `tools/run_all_tests.sh --quick` 无回归。

## 5. 版本

- 2026-11-08：初版。
