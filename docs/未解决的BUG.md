# KONG 未解决的 BUG（待排查档案）

> **本文档职责**：记录**尚未复现/原因未完全确认**的 bug，附代码路径分析、可能触发原因、排查建议。
> 与 `BUG档案.md`（已解决+根因）区分：本文档条目在确认根因并修复后，应迁移到 `BUG档案.md`。
> 登记格式：现象 → 代码路径 → 可能原因（按可能性）→ 排查建议。

---

## U1：贴牌判对但进度卡死（罕见）——"弃牌堆为 10，贴对方 3 却显示绿色，游戏卡住"

### 现象

1. 当前弃牌堆顶为 `10`（`slap_rank = "10"`），进入贴牌窗口。
2. 点击**其他玩家的一张 `3`** 尝试贴牌。
3. 该牌显示**绿色**（判定为"正确"）。
4. 但贴牌**没有真正完成**，游戏进度卡住。
5. **其他玩家也无法点击抽牌堆**推进到下一回合。

### 代码路径分析

**1) 贴牌对错判定（服务器，`slap_system.gd:40`）**

```gdscript
var correct: bool = game.debug_duel or game.cards[target_card].rank == game.slap_rank
```

- rank 为字符串（`game_state.gd:266`：`["A","2",...,"10","J","Q","K"]`），`"3" == "10"` 在 GDScript 中**必为 false**。
- 因此非调试模式下，贴 `3` 对 `10` 应判定为**错误（红色）**。
- **未发现能让 `"3"` 匹配 `"10"` 的代码路径**（唯一的例外是 `game.debug_duel == true`）。

**2) 绿色（正确）炫光的含义（`reveal_controller.gd` `_play_slap_flip`）**

```gdscript
if correct:
    cv.set_glow(main.SLAP_CORRECT_GLOW, main.SLAP_GLOW_SIZE)  # 绿色
    _held_slap[...] = {...}   # 登记 hold，不翻回
    return
cv.set_glow(main.SLAP_WRONG_GLOW, ...)  # 红色，稍后翻回
```

绿色 = `correct` 为 true。**正确贴牌会登记 `_held_slap` 并 hold（不翻回），等待结算事件 `slap_resolved`。**

**3) "卡住"的两种可能状态**

- **收集窗未结束**：`_add_to_collection`（`slap_system.gd:56`）首个正确贴牌启动收集计时器。
  - 非调试：`SLAP_DUEL_COLLECT_MS = 400ms`。
  - **调试（debug_duel）：`DEBUG_DUEL_COLLECT_MS = 30000ms`（30 秒）**。
- **SLAP_EXCHANGE 等待**：正确贴牌目标是他人 → `_resolve_correct_slap` 切到 `SLAP_EXCHANGE`，行动者（贴牌者）必须交出一张自己的牌（`game_interaction.gd:37`），未交则一直等待。

**4) 无法点击抽牌堆**

- `main.gd:209` `_on_deck_pressed` / `main.gd:215` `_on_discard_pressed` 开头有 `if _slap_reveal_lock: return`（此前为防翻牌中误取牌而加）。
- 正确贴牌绿光 hold 期间 `_slap_reveal_lock` 为 true → **牌堆/弃牌堆点击被锁**。
- 若 `slap_resolved` 结算事件未到达/未处理，`_slap_reveal_lock` 会**一直为 true**，永久锁住牌堆。

### 可能触发原因（按可能性排序）

| # | 原因 | 与症状吻合度 | 说明 |
|---|---|---|---|
| 1 | **`debug_duel` 被误开启（O 键调试开关）** | 极高（全部吻合） | `dev_tools.gd:27` 按 O 切换。开启后 `correct` 恒为 true → **任何贴牌都绿**；收集窗 **30s** → "没有真的成功贴牌"；绿光 hold → 锁牌堆 → "无法点抽牌堆/进度卡住"。用户只在误按 O 时才遇到，故表现为"罕见"。 |
| 2 | **SLAP_EXCHANGE 行动者未交牌** | 中 | 若贴牌确实判对（可能**看错牌面**：那张牌 rank 实为 `10`，或上一条 debug_duel 开启），目标为他人 → 进入交换阶段，行动者必须交一张牌；未交则卡住，其他人因阶段非 TURN_DRAW 无法抽牌。提示语在 `main.gd:368-370`。 |
| 3 | **`_slap_reveal_lock` 永久锁牌堆** | 中 | 正确贴牌绿光 hold，若 `slap_resolved` 因网络/处理失败未释放 `free_slap`（`reveal_controller.gd`），锁不解除 → 牌堆永久不可点。 |

### 排查建议

1. **先确认是否误按了 O 键**：观察贴牌窗口期间右上/状态提示是否显示"调试贴牌 ON"（`dev_tools.gd:28` 的 toast）。开启时**任何贴牌都绿**且收集窗 30s——这正是本次症状。
2. **若非 debug_duel**：复现时查看贴中后是否进入 `SLAP_EXCHANGE` 阶段（顶栏阶段名"贴中他人：交出一张牌"）。若是，行动者需点击自己一张牌交出；这是正常流程，只是提示不明显。
3. **检查锁**：若卡住时 `main._slap_reveal_count > 0`（客户端），说明有未释放的 hold 揭示；对比服务器是否已广播 `slap_resolved`（`_broadcast_exchange`）。

### 结论

- 未发现能让 `"3"` 匹配 `"10"` 的**确定代码缺陷**（rank 为字符串比较，逻辑正确）。
- 最可能是 **`debug_duel` 误开启**（O 键），其行为（全绿 + 30s 收集 + 锁牌堆）与所有症状完全一致。
- 次要因素：SLAP_EXCHANGE 交牌等待（提示不够明显）、`_slap_reveal_lock` 在结算事件缺失时永久锁牌堆。
- **待办**：若能复现，确认 debug_duel 状态后再定论；若为 SLAP_EXCHANGE 交牌卡住，可考虑给行动者更明显的引导（高亮自己的可交牌）。

---

### 更新（2026-09-01）：debug_duel 下收集窗锁死已确认并修复

- 现象"贴牌后全员无法点击"在 `debug_duel` 下为**必然复现**，根因已确认：正确贴牌绿光 hold 使 `_slap_reveal_lock` 在收集窗内不释放，`game_interaction.on_card_pressed` 贴牌分支被该锁拦截，第二名玩家无法补拍 → 比拼永不触发。
- **修复**：贴牌分支不再检查 `_slap_reveal_lock`（收集窗内允许继续贴牌），判定锁继续挡抽牌/弃牌堆。详见 `BUG档案.md` B14。
- 本条目（U1）的"debug_duel 误开启导致锁牌堆"分支随 B14 修复解除；遗留的仅剩"SLAP_EXCHANGE 行动者交牌引导不明显"与"结算事件缺失锁死牌堆"（后者本身已由计数管理缓解）。