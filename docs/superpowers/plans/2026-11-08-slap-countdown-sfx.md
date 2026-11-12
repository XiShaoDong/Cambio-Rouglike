# 结算贴牌倒计时 + 音效强化 Implementation Plan

> **For agentic workers:** 本计划改动集中在 3 个脚本 + 1 个场景 + 2 个测试。逐任务实现、每步跑 headless 测试。

**Goal:** 3s 结算贴牌窗口显示 3/2/1 倒计时（绿/黄/红）并播放 countdown 音；抽牌/弃牌/贴牌成功失败/触发/点击使用 `assets/Sounds2` 对应音效且更明显。

**Architecture:** 纯客户端展示层。`HintHud` 负责倒计时视觉，`AudioManager` 负责音效资源与增益，`main` 负责事件接线（pending 变化 / 弃牌事件 / 贴牌 reveal / 触发事件 / settle deadline）。

**Tech Stack:** Godot 4.6 / GDScript / headless 测试 / 现有 `HintHud`、`AudioManager`、`GameState` 信号。

## Global Constraints

- 不改 `game_state.gd` / 协议 / 快照 / 规则。
- 只使用 `/Users/ee/dev/gameDev/cambio-rouglike/assets/Sounds2/` 下素材：`card-place.ogg`、`card-slide.ogg`、`click.ogg`、`countdown.wav`、`notification.ogg`、`slap-fail.ogg`、`slap-success.wav`。
- 不做逐秒 countdown 重复播放：`countdown.wav` 从 **1s 开始播 3s**（素材在 0/1/2/3s 各有 beep，跳过最开始的 0s 那声，保留 1/2/3s 三声）。
- 倒计时只用于结算窗口（`settle_deadline_server_ms > 0`）；普通 `slap_open` 保持 `SLAP OPEN`。
- 不启动 GUI；测试用 `/Applications/Godot.app/Contents/MacOS/Godot --headless ...`。
- 不 commit（未获授权）。

---

### Task 1: AudioManager 新音效

**Files:**
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/scripts/ui/audio_manager.gd`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/scenes/ui/audio_manager.tscn`
- Create: `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_audio_sfx.gd` + `.tscn`

**Interfaces:**
- 新增 `@export`：`card_place_sfx`、`card_slide_sfx`、`click_sfx`、`countdown_sfx`、`notification_sfx`、`slap_fail_sfx`、`slap_success_sfx`。
- 新增方法：`play_draw()`、`play_discard()`、`play_slap_success()`、`play_slap_fail()`、`play_trigger()`、`play_countdown()`、`stop_countdown()`。
- 新增 `last_event: String`；`POOL_SIZE=10`；`_base_db`；独立 `_countdown_player`。
- `play_select()` 优先 `click_sfx`（无则回退旧 `select_sfx`）。

**步骤：**
- [ ] 写 `verify_audio_sfx.gd`：断言 7 个 stream 非空；依次调用 7 个 play 方法并断言 `last_event`；`stop_countdown()` 不报错。
- [ ] 运行确认失败（方法不存在）。
- [ ] 实现 `audio_manager.gd`（按设计 §3：增益 map、`_play(stream, pitch, gain_db)`、countdown 独立播放器）。
- [ ] 在 `audio_manager.tscn` 绑定 7 个 `Sounds2` 资源。
- [ ] 运行 `verify_audio_sfx` 确认通过。

### Task 2: HintHud 倒计时视觉

**Files:**
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/scripts/ui/hint_hud.gd`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_hint_hud.gd`

**Interfaces:**
- `set_slap_state(state: int, window := 0.0, settle := false)`（新增第三参，默认 false，兼容旧调用）。
- 常量 `SLAP_SETTLE_TEXT="SLAP SETTLE"`、`SLAP_SETTLE_GREEN/YELLOW/RED`、`SLAP_SETTLE_FONT=24`。
- `slap_label()` 在 settle 模式文本 `SLAP SETTLE  3/2/1`，颜色按档位；bar fill 同色。

**步骤：**
- [ ] 扩展 `verify_hint_hud._test_slap_row()`：普通 OPEN 文案/颜色不变；`set_slap_state(OPEN, 3.0, true)` → 3 绿；`_process(1.01)` → 2 黄；再 1.0 → 1 红；再 1.0 → 走空隐藏。
- [ ] 运行确认失败。
- [ ] 实现：`_slap_settle`、`_slap_last_count`、`_slap_bar_fill` 引用；`entering_open` 逻辑兼容"同状态重发不重置"；`_process` 整数秒变化时刷新；`_update_slap_visuals` 按档位设置文字/字体/颜色/bar。
- [ ] 运行 `verify_hint_hud` 确认全过。

### Task 3: main 事件接线

**Files:**
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/scripts/ui/main.gd`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_hint_hud.gd`（main 集成断言）

**Interfaces:**
- 新增 `_last_pending_sfx_id := ""`、`_settle_countdown_active := false`、`_sync_sfx_state(state: Dictionary)`。
- `_update_hint_hud` 读取 `settle_deadline_server_ms > 0` 并传 `settle=true, window=3.0`。
- 音效接线：`_sync_sfx_state`（draw/countdown）、`card_exchange_animated` lambda（discard）、`_show_private_reveal`（slap success/fail）、`_show_effect_trigger`/`_handle_bomb_explode`/`_maybe_new_turn_effect`（trigger）。

**步骤：**
- [ ] 扩展 `verify_hint_hud._test_main_integration()`：调用 `_sync_sfx_state({"pending":{"id":"x"}})` 断言 `AudioManager.last_event=="draw"`；`{"settle_deadline_server_ms":1}` 断言 `"countdown"`；`{}` 断言 `_settle_countdown_active==false`。
- [ ] 运行确认失败。
- [ ] 实现 `_sync_sfx_state` 并在 `_on_state_updated` 调用；在 `_show_private_reveal` / 弃牌事件 / 触发事件加 3 行调用；`_update_hint_hud` 传 settle。
- [ ] 运行 `verify_hint_hud` 确认全过。

### Task 4: 注册 + 文档 + quick 回归

- [ ] `tools/run_all_tests.sh` 加 `run_single "audio_sfx" res://tests/verify_audio_sfx.tscn`。
- [ ] 更新 `docs/AI_AGENT_交接说明.md` / `docs/功能实现文档.md` / `docs/修改日志.md`（日志不提交）。
- [ ] `tools/run_all_tests.sh --quick` 无 FAIL。

## Self-Review

- 覆盖：倒计时视觉（Task 2）、countdown 音（Task 1/3）、7 条音效映射（Task 1/3）、增益与池（Task 1）。
- 无占位；所有新增方法/字段/常量都给了名称与调用点。
- 兼容：`set_slap_state` 第三参默认 false，旧测试/调用不受影响。
