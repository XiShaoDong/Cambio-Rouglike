# KONG 名次奖励经济 + 生命值 + 局内金钱/生命 HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 取消开局押注，改为结算时按名次由系统发放金钱、垫底扣 1 生命（默认 2 命）；并把金钱/生命从名字标签移到每个玩家区域手牌右侧的紧凑 HUD（铜钱数字 + 心形生命图标）。

**Architecture:** 全服务器权威。`GameState` 删除押注阶段，`_finish_game`/`_finish_game_over_hand` 改用纯计算 `_settle_rewards(ranking, extra_last)`；`_server_initial_ready` 全员确认后直接进入 `TURN_DRAW`。客户端 HUD 只读快照公开字段 `players[].currency`/`players[].health`，新增程序化图标 `CoinIcon`/`LifeIcon` 与 `StatHud`，定位方式复用 `RelicBar`（`HandGrid` 左侧栏的反向镜像）。

**Tech Stack:** Godot 4.6 / GDScript / ENet。headless 单测（`tests/verify_economy.tscn` 等）。

**Spec:** `docs/superpowers/specs/2026-09-14-rank-reward-economy-design.md`

## Global Constraints

- 保持三条架构不变量：`GameState` 服务器权威、`HiddenInfo` 私有快照、贴牌服务器时序。
- `Phase.BET`（值 9）**保留为弃用值**：不删除、不挪动数值，任何流程不再进入；`Phase.SHOP`（值 10）不变。
- 起始 **100 货币 + 2 生命**；垫底 **0 金钱、−1 生命**；第一 **+40**、中间 **+10**；并列组平分区间奖励（全员同分例外：各 +10、无人扣血）。
- 生命为 0 → 出局观战；出局者**保留货币**参与把末排名（R-08 不变）。
- HUD 只读公开快照字段，不新增/不泄漏隐藏信息。
- 每次改动跑 `tools/run_all_tests.sh --quick`；提交按 `feat/fix/doc` 分类。
- 编译检查：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5`。

---

### Task 1: 服务器规则 + 快照（取消押注 / 起始 2 命 / 名次发钱扣血）

**Files:**
- Modify: `scripts/core/game_rules.gd`
- Modify: `scripts/core/game_state.gd`
- Modify: `scripts/core/hidden_info.gd`
- Rewrite: `tests/verify_economy.gd`

**Interfaces:**
- Consumes: `ScoreSystem.calculate_ranking`、`_alive_order`、`_same_score`、`_calculate_ranking`。
- Produces: `KongRules.START_HEALTH := 2`、`KongRules.RANK_REWARD_FIRST := 40`、`KongRules.RANK_REWARD_MIDDLE := 10`；`GameState._settle_rewards(ranking: Array, extra_last: Array = []) -> Dictionary` 返回 `{seat: {"money": int, "life_lost": int}}`；`last_result.rewards`；`last_result.penalized`。

- [ ] **Step 1: 写失败测试（重写 `tests/verify_economy.gd`）**

```gdscript
extends Node
## headless 单元测试：名次奖励经济（rank-reward economy，替代押注）

var failures := 0
var checks := 0

func _ready() -> void:
	await _test_defaults()
	await _test_direct_turn_after_ready()
	await _test_rank_rewards()
	await _test_tie_split()
	await _test_all_tie()
	await _test_last_life_and_elimination()
	await _test_kong_first_turn()
	await _test_over_hand()
	var status: String = " (FAILURES!)" if failures > 0 else ""
	print("=== ECONOMY RESULT: %d/%d passed%s ===" % [checks - failures, checks, status])
	get_tree().quit(1 if failures > 0 else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _set_hand(seat: int, vals: Array) -> void:
	GameState.players[seat].cards = []
	for i in vals.size():
		var cid := "t%d_%d_%d" % [seat, i, randi() % 100000]
		GameState.cards[cid] = {"id": cid, "rank": str(vals[i]), "suit": "♠", "value": int(vals[i])}
		GameState.players[seat].cards.append(cid)

## 3 人：seat0 最低分(胜)、seat1 中、seat2 最高分(垫底)
func _open_three() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	_set_hand(0, [3, 4])
	_set_hand(1, [5, 6])
	_set_hand(2, [7, 8])

func _test_defaults() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	_check("起始货币=100", int(GameState.players[0].currency) == KongRules.START_CURRENCY)
	_check("起始生命=2", int(GameState.players[0].health) == KongRules.START_HEALTH)
	_check("START_HEALTH 常量=2", KongRules.START_HEALTH == 2)

func _test_direct_turn_after_ready() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	_check("记忆确认后直接进入抽牌", GameState.phase == GameState.Phase.TURN_DRAW)
	_check("先手为 seat0", int(GameState.current_player_id) == 0)
	_check("快照不再含 bet_ready", not GameState._snapshot_for(0).has("bet_ready"))

func _test_rank_rewards() -> void:
	_open_three()
	GameState._finish_game()
	_check("第一名 +40", int(GameState.players[0].currency) == 140)
	_check("中间 +10", int(GameState.players[1].currency) == 110)
	_check("垫底 +0", int(GameState.players[2].currency) == 100)
	_check("垫底 -1 生命", int(GameState.players[2].health) == 1)
	_check("非垫底不掉血", int(GameState.players[0].health) == 2 and int(GameState.players[1].health) == 2)
	_check("rewards 记录", int(GameState.last_result.rewards[0].money) == 40 and int(GameState.last_result.rewards[1].money) == 10 and int(GameState.last_result.rewards[2].money) == 0)
	_check("penalized 含垫底", (GameState.last_result.penalized as Array).has(2))
	_check("胜场+1", int(GameState.players[0].wins) == 1)

func _test_tie_split() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._add_player(4, "D")
	_set_hand(0, [3, 3]); _set_hand(1, [3, 3])
	_set_hand(2, [9, 9]); _set_hand(3, [9, 9])
	GameState._finish_game()
	_check("并列第一平分(40+10)/2=25", int(GameState.players[0].currency) == 125 and int(GameState.players[1].currency) == 125)
	_check("并列垫底 +0", int(GameState.players[2].currency) == 100 and int(GameState.players[3].currency) == 100)
	_check("并列垫底同扣血", int(GameState.players[2].health) == 1 and int(GameState.players[3].health) == 1)

func _test_all_tie() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._add_player(4, "D")
	for s in [0, 1, 2, 3]:
		_set_hand(s, [4, 4])
	GameState._finish_game()
	_check("全员同分每人 +10", int(GameState.players[0].currency) == 110 and int(GameState.players[3].currency) == 110)
	_check("全员同分无人掉血", int(GameState.players[0].health) == 2 and int(GameState.players[3].health) == 2)
	_check("全员同分无胜场", int(GameState.players[0].wins) == 0)

func _test_last_life_and_elimination() -> void:
	_open_three()
	GameState.players[2].health = 1
	GameState._finish_game()
	_check("垫底第二次扣血出局", int(GameState.players[2].health) == 0)
	_check("出局者 _is_alive=false", not GameState._is_alive(2))
	_check("出局者保留货币", int(GameState.players[2].currency) == 100)

func _test_kong_first_turn() -> void:
	_open_three()
	GameState.kong_called_first_turn = true
	GameState.kong_caller = 1
	GameState._finish_game()
	_check("Kong 首回合失败者 0 金钱", int(GameState.players[1].currency) == 100)
	_check("Kong 首回合失败者 -1 命", int(GameState.players[1].health) == 1)
	_check("真正垫底者也 -1 命", int(GameState.players[2].health) == 1)

func _test_over_hand() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	_set_hand(0, [7, 7, 7, 7, 7, 7, 7])
	_set_hand(1, [3, 4]); _set_hand(2, [5, 6])
	GameState._finish_game_over_hand(0)
	_check("超限者 0 金钱", int(GameState.players[0].currency) == 100)
	_check("超限者 -1 命", int(GameState.players[0].health) == 1)
	_check("超限失败不参与排名", GameState.last_result.ranking.size() == 2)
```

- [ ] **Step 2: 运行确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_economy.tscn`
Expected: FAIL（`START_HEALTH` 未定义 / `rewards` 缺失 / 仍是押注阶段）。

- [ ] **Step 3: 改 `scripts/core/game_rules.gd`**

在 `START_CURRENCY` 附近新增常量（保留既有押注常量不动，供尚未删除的 `bet_panel.gd` 编译）：

```gdscript
const START_CURRENCY := 100
const START_HEALTH := 2
## 名次奖励（R-12）：第一 / 中间 / 垫底。
const RANK_REWARD_FIRST := 40
const RANK_REWARD_MIDDLE := 10
```

把 `new_default_run()` 的 `"health": 1` 改为 `"health": START_HEALTH`。

- [ ] **Step 4: 改 `scripts/core/game_state.gd` — 起始生命与取消押注**

`_add_player` 的 health 默认值改为 `KongRules.START_HEALTH`：

```gdscript
		"health": int(run_state.get("health", KongRules.START_HEALTH)),
```

删除变量 `var bets: Dictionary = {}`（约第 77 行）及全部 `bets.clear()`（第 170、473、581 行），删除函数 `_start_bet_phase`、`request_bet`、`server_bet`、`_server_bet`、`_commit_bet`（约第 579–640 行）。

`_server_initial_ready` 末尾（原 `_start_bet_phase()` 处）改为直接进入回合：

```gdscript
	initial_confirmed[sender] = true
	if initial_confirmed.size() < _alive_count():
		_broadcast_state()
		return
	# 记忆确认后直接开始正式回合（押注阶段已取消，R-12）
	current_player_id = _alive_order()[0]
	phase = Phase.TURN_DRAW
	_add_log("轮到 %s 行动。" % players[current_player_id].name)
	_broadcast_state()
```

- [ ] **Step 5: 改 `scripts/core/game_state.gd` — 名次发钱扣血**

删除 `_settle_economy`，新增 `_settle_rewards` 与 `_rank_reward_at`：

```gdscript
## 名次奖励结算（R-12）：按名次发钱，给垫底（及 extra_last）扣 1 生命。
## ranking：ScoreSystem 排序结果（索引 0 = 最低分）；extra_last：额外按垫底处理者（超限/首回合 Kong）。
## 返回 {seat: {"money": int, "life_lost": int}}，并已写回 currency/health。
func _settle_rewards(ranking: Array, extra_last: Array = []) -> Dictionary:
	var rewards: Dictionary = {}
	var n := ranking.size()
	var all_tied := n > 1 and _same_score(ranking[0], ranking[n - 1])
	if all_tied:
		for e in ranking:
			rewards[int(e.id)] = {"money": KongRules.RANK_REWARD_MIDDLE, "life_lost": 0}
	else:
		var i := 0
		while i < n:
			var j := i
			while j + 1 < n and _same_score(ranking[j + 1], ranking[i]):
				j += 1
			var total := 0
			for k in range(i, j + 1):
				total += _rank_reward_at(k, n)
			var share := int(floor(float(total) / float(j - i + 1)))
			for k in range(i, j + 1):
				rewards[int(ranking[k].id)] = {"money": share, "life_lost": 0}
			i = j + 1
		for e in ranking:
			if _same_score(e, ranking[n - 1]):
				rewards[int(e.id)].life_lost = 1
	for seat in extra_last:
		var s := int(seat)
		if rewards.has(s):
			rewards[s].money = 0
			rewards[s].life_lost = 1
		else:
			rewards[s] = {"money": 0, "life_lost": 1}
	for seat in rewards:
		var r: Dictionary = rewards[seat]
		players[seat].currency = maxi(0, int(players[seat].currency) + int(r.money))
		if int(r.life_lost) > 0:
			players[seat].health = maxi(0, int(players[seat].health) - int(r.life_lost))
	return rewards

func _rank_reward_at(index: int, n: int) -> int:
	if n <= 1:
		return 0
	if index == 0:
		return KongRules.RANK_REWARD_FIRST
	if index == n - 1:
		return 0
	return KongRules.RANK_REWARD_MIDDLE
```

- [ ] **Step 6: 改 `scripts/core/game_state.gd` — `_finish_game`**

把 `_finish_game` 中从 `var ranking := _calculate_ranking()` 到 `for entry in winners: players[entry].wins ...` 之间替换为：

```gdscript
	var ranking := _calculate_ranking()
	var all_tied := ranking.size() > 1 and _same_score(ranking[0], ranking[ranking.size() - 1])
	var winners: Array[int] = []
	if not ranking.is_empty() and not all_tied:
		for entry in ranking:
			if _same_score(entry, ranking[0]):
				winners.append(int(entry.id))
	var extra_last: Array = []
	if kong_called_first_turn and kong_caller >= 0:
		extra_last.append(kong_caller)
	var rewards: Dictionary = _settle_rewards(ranking, extra_last)
	var penalized: Array = []
	for seat in rewards:
		if int(rewards[seat].life_lost) > 0:
			penalized.append(int(seat))
	last_result = {"ranking": ranking, "winners": winners, "penalized": penalized,
		"first_turn_kong": kong_called_first_turn, "rewards": rewards}
	_add_log("对局结束，所有手牌已翻开。")
	for entry in winners:
		players[entry].wins = int(players[entry].get("wins", 0)) + 1
```

（`if _series_finished(): ...` 及其后的 `_broadcast_sfx`/`_broadcast_state`/`_start_series_timer` 保持不变。）

- [ ] **Step 7: 改 `scripts/core/game_state.gd` — `_finish_game_over_hand`**

把 `var economy := _settle_economy(...)` 起至 `penalized` 段替换为：

```gdscript
	var rewards: Dictionary = _settle_rewards(ranking, [failed_seat])
	var winners: Array[int] = []
	if not ranking.is_empty():
		for entry in ranking:
			if _same_score(entry, ranking[0]):
				winners.append(int(entry.id))
	var penalized: Array = [failed_seat]
```

并把 `last_result` 里的 `"economy": economy` 改为 `"rewards": rewards`。

- [ ] **Step 8: 改 `scripts/core/hidden_info.gd`**

删除快照字段 `"bet_ready": ...` 一行；`_player_snapshot` 的 `"eliminated": int(player.get("health", 1)) <= 0` 改为 `int(player.get("health", 0)) <= 0`。（`_phase_name` 的 `Phase.BET` 分支保留。）

- [ ] **Step 9: 运行测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_economy.tscn`
Expected: `=== ECONOMY RESULT: N/N passed ===`（全 PASS）。

- [ ] **Step 10: 提交**

```bash
git add scripts/core/game_rules.gd scripts/core/game_state.gd scripts/core/hidden_info.gd tests/verify_economy.gd
git commit -m "feat(economy): rank-reward settlement, 2 lives, remove betting phase"
```

---

### Task 2: 更新其余测试套件（移除 BET / health 默认 2）

**Files:**
- Modify: `tests/verify_protocol.gd`、`tests/verify_series.gd`、`tests/verify_settlement.gd`、`tests/verify_shop.gd`、`tests/verify_reconnect.gd`、`tests/verify_kongbaya.gd`、`tests/verify_relics.gd`、`tests/verify_duel.gd`、`tests/verify_net.gd`

**Interfaces:**
- Consumes: Task 1 的新流程（`_server_initial_ready` 后即 `TURN_DRAW`）。
- Produces: 全套回归全绿。

- [ ] **Step 1: 全局替换押注驱动**

在下列文件中，**删除**所有 `GameState._server_bet(...)` 行（现在 `_server_initial_ready` 后已直接是 `TURN_DRAW`）：

`tests/verify_series.gd`（3 处）、`tests/verify_settlement.gd`、`tests/verify_shop.gd`、`tests/verify_reconnect.gd`、`tests/verify_kongbaya.gd`（2 处）、`tests/verify_relics.gd`（2 处）。

- [ ] **Step 2: 修正阶段断言**

- `tests/verify_protocol.gd`：`_check("全员确认后进入押注阶段", GameState.phase == GameState.Phase.BET)` → `_check("全员确认后直接进入抽牌", GameState.phase == GameState.Phase.TURN_DRAW)`，并删除其后 `_server_bet` 两行。
- `tests/verify_series.gd`：第 117 行断言同理改为 `GameState.Phase.TURN_DRAW`，文案改"存活者就绪即进入抽牌"。

- [ ] **Step 3: 修 `tests/verify_duel.gd` 超限断言**

第 168 行改为按新规则（超限按垫底 −1 生命）：

```gdscript
	_check("超限玩家按垫底扣 1 生命", int(GameState.players[0].health) == health_before - 1)
```

- [ ] **Step 4: 修 `tests/verify_net.gd`**

删除 `var bet_sent := false`（第 16 行）与 `_on_state` 中的 BET 分支（第 66–70 行）。`phase == 1` 分支改为发 ready 后 `return`；`phase == 2` 分支照旧（phase 1 → 2 直接衔接）。

```gdscript
	if phase == 1 and not ready_sent:
		ready_sent = true
		GameState.request_initial_ready()
		print("[%s] initial ready sent" % role)
		return
	if phase == 2:
```

- [ ] **Step 5: 运行单进程核心回归**

Run: `./tools/run_all_tests.sh --quick`
Expected: 全绿（protocol/swap/duel/reconnect/kongbaya/settlement/series/economy/shop/relics/hint）。

- [ ] **Step 6: 运行双实例网络回归**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_net.tscn -- -role host
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_net.tscn -- -role client
```
Expected: 两侧均 `VERIFY ... PASS` 且 exit 0。

- [ ] **Step 7: 提交**

```bash
git add tests/
git commit -m "test: drop betting phase from suites, update over-hand life assert"
```

---

### Task 3: 局内金钱/生命 HUD（程序化图标 + 每玩家区域右侧）

**Files:**
- Create: `scripts/ui/coin_icon.gd`、`scripts/ui/life_icon.gd`、`scripts/ui/stat_hud.gd`
- Modify: `scripts/ui/game_view.gd`

**Interfaces:**
- Consumes: `main.latest_state`（`players[].currency`/`players[].health`）、`UITheme.color`、`RelicBar` 的定位模式。
- Produces: `class_name CoinIcon`、`class_name LifeIcon`、`class_name StatHud`（`setup(state, seat)`）；`GameView._render_stat_hud(area, player, hand)`、`_position_stat_hud(area)`。

- [ ] **Step 1: 创建 `scripts/ui/coin_icon.gd`**

```gdscript
class_name CoinIcon
extends Control
## 程序化铜钱图标：外圆 + 内方孔。无图片资源依赖。

var color := Color.WHITE

func setup(p_color: Color) -> void:
	color = p_color
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 1.5
	draw_arc(c, r, 0.0, TAU, 32, color, 2.0, true)
	var h := r * 0.45
	var hole := Rect2(c - Vector2(h, h), Vector2(h * 2.0, h * 2.0))
	draw_rect(hole, color, false, 2.0)
```

- [ ] **Step 2: 创建 `scripts/ui/life_icon.gd`**

```gdscript
class_name LifeIcon
extends Control
## 程序化心形生命图标。无图片资源依赖。

var color := Color.WHITE

func setup(p_color: Color) -> void:
	color = p_color
	queue_redraw()

func _draw() -> void:
	var s := minf(size.x, size.y)
	var center := size * 0.5
	var r := s * 0.26
	draw_circle(center + Vector2(-r * 0.9, -r * 0.5), r, color)
	draw_circle(center + Vector2(r * 0.9, -r * 0.5), r, color)
	var pts := PackedVector2Array([
		center + Vector2(-r * 1.85, -r * 0.1),
		center + Vector2(r * 1.85, -r * 0.1),
		center + Vector2(0, r * 1.9),
	])
	draw_colored_polygon(pts, color)
```

- [ ] **Step 3: 创建 `scripts/ui/stat_hud.gd`**

```gdscript
class_name StatHud
extends Control
## 玩家区域右侧 HUD：上排 铜钱+货币数字，下排 生命心形×N。纯展示，读快照公开字段。

const COIN_SIZE := 22
const LIFE_SIZE := 16
const LIFE_GAP := 3
const ROW_GAP := 6

func setup(state: Dictionary, seat: int) -> void:
	for child in get_children():
		child.queue_free()
	var currency := 0
	var health := 0
	for p in state.get("players", []):
		if int(p.id) == seat:
			currency = int(p.get("currency", 0))
			health = maxi(0, int(p.get("health", 0)))
			break
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var coin := CoinIcon.new()
	coin.custom_minimum_size = Vector2(COIN_SIZE, COIN_SIZE)
	coin.size = coin.custom_minimum_size
	coin.setup(UITheme.color("accent"))
	row.add_child(coin)
	var num := Label.new()
	num.text = str(currency)
	num.add_theme_font_size_override("font_size", 14)
	num.add_theme_color_override("font_color", UITheme.color("accent"))
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(num)
	row.position = Vector2.ZERO
	add_child(row)
	var lives := HBoxContainer.new()
	lives.add_theme_constant_override("separation", LIFE_GAP)
	for _i in health:
		var h := LifeIcon.new()
		h.custom_minimum_size = Vector2(LIFE_SIZE, LIFE_SIZE)
		h.size = h.custom_minimum_size
		h.setup(UITheme.color("danger"))
		lives.add_child(h)
	lives.position = Vector2(0, COIN_SIZE + ROW_GAP)
	add_child(lives)
	custom_minimum_size = Vector2(COIN_SIZE + 36, COIN_SIZE + LIFE_SIZE + ROW_GAP)
	size = custom_minimum_size
```

- [ ] **Step 4: 改 `scripts/ui/game_view.gd` — 名字标签去货币 + 挂载 HUD**

在 `_render_player_section` 中，把名字标签文本行的货币部分删掉：

```gdscript
	name_label.text = "%s%s%s%s" % [player.name, suffix, ready_mark, elim_suffix]
```

并在 `_render_player_section` 末尾 `_render_relic_bar(area, player, hand)` 之后加：

```gdscript
	_render_stat_hud(area, player, hand)
```

新增两个函数（放在 `_position_relic_bar` 附近）：

```gdscript
## 玩家区域右侧金钱/生命 HUD：复用单实例，定位到手牌右侧、垂直居中（RelicBar 镜像）。
func _render_stat_hud(area: Control, player: Dictionary, hand: GridContainer) -> void:
	var hud := area.get_node_or_null("StatHud")
	if hud == null:
		hud = StatHud.new()
		hud.name = "StatHud"
		hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		area.add_child(hud)
		hand.resized.connect(_position_stat_hud.bind(area))
	hud.setup(main.latest_state, int(player.id))
	_position_stat_hud(area)

func _position_stat_hud(area: Control) -> void:
	var hud := area.get_node_or_null("StatHud")
	var hand: GridContainer = area.get_node_or_null("VBox/HandCenter/HandGrid")
	if hud == null or hand == null:
		return
	var rect: Rect2 = hand.get_global_rect()
	hud.global_position = rect.position + Vector2(rect.size.x + 8, (rect.size.y - hud.size.y) / 2.0)
```

- [ ] **Step 5: 编译检查**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5`
Expected: 无脚本错误（无 "Parse Error" / "Invalid call"）。

- [ ] **Step 6: 跑 quick 回归（确认 UI 改动未破坏编译/测试）**

Run: `./tools/run_all_tests.sh --quick`
Expected: 全绿。

- [ ] **Step 7: 提交**

```bash
git add scripts/ui/coin_icon.gd scripts/ui/life_icon.gd scripts/ui/stat_hud.gd scripts/ui/game_view.gd
git commit -m "feat(ui): per-player coin/life HUD right of hand"
```

---

### Task 4: 结算页奖励明细 + 下线押注面板

**Files:**
- Modify: `scripts/ui/settlement_page.gd`
- Modify: `scripts/ui/main.gd`
- Delete: `scripts/ui/bet_panel.gd`（+ `.uid`）、`scenes/ui/bet_panel.tscn`

**Interfaces:**
- Consumes: `last_result.rewards`（`{seat: {"money": int, "life_lost": int}}`）。
- Produces: 结算页 "本局奖励" 标签；`main.gd` 不再引用 `BetPanel`。

- [ ] **Step 1: 改 `scripts/ui/settlement_page.gd`**

把 `var _economy: Dictionary = {}` / 参数 `economy := {}` / `_economy = economy` 改名为 `_rewards` / `rewards`。把 `_show_economy` 替换为：

```gdscript
func _show_rewards(rewards: Dictionary) -> void:
	if rewards.is_empty():
		return
	var parts: Array = []
	for seat in rewards:
		var r: Dictionary = rewards[seat]
		var money := int(r.get("money", 0))
		var lives := int(r.get("life_lost", 0))
		var name := ""
		for row in _rows:
			if int(row) == int(seat):
				name = str(_rows[row].name.text).replace("★ ", "").replace("▼ ", "").replace("▲ ", "")
				break
		var text := "%s %+d" % [name, money]
		if lives > 0:
			text += "（-%d♥）" % lives
		parts.append(text)
	var lbl: Label = get_node("Center/Panel/VBox/EconomyLabel")
	lbl.text = "本局奖励：%s" % "　".join(parts)
	lbl.visible = true
```

把调用 `_show_economy(...)` 处改为 `_show_rewards(_rewards)`（`_run_sequence` 内）。

- [ ] **Step 2: 改 `scripts/ui/main.gd`**

删除 `const BetPanelScript := preload("res://scenes/ui/bet_panel.tscn")`、`var bet_panel: Control = null`、`_open_bet_panel`/`_close_bet_panel`/`_on_bet_confirm` 三个函数，以及 `_on_state_updated` 中的：

```gdscript
	if int(state.phase) == PHASE_BET:
		_open_bet_panel()
	else:
		_close_bet_panel()
```

把结算页构造处的 `var economy := (latest_state.get(...)).get("economy", {})` 改为：

```gdscript
	var rewards: Dictionary = (latest_state.get("result", {}) as Dictionary).get("rewards", {})
```

并把传参 `..., economy)` 改为 `..., rewards)`。若 `PHASE_BET` 常量（=9）仅在上述分支使用，一并删除其定义。

- [ ] **Step 3: 删除押注面板文件**

```bash
git rm scripts/ui/bet_panel.gd scripts/ui/bet_panel.gd.uid scenes/ui/bet_panel.tscn
```

- [ ] **Step 4: 编译检查**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5`
Expected: 无脚本错误（确认无残留 `BetPanel` 引用）。

- [ ] **Step 5: 跑 quick 回归**

Run: `./tools/run_all_tests.sh --quick`
Expected: 全绿（`verify_settlement` 覆盖结算页）。

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "feat(ui): settlement shows rank rewards; remove bet panel"
```

---

### Task 5: 文档基线（规则 R-12 / 协议 / 交接 / 问题档案）

**Files:**
- Modify: `docs/KONG_开发文档.md`、`docs/网络协议_V1.md`、`docs/AI_AGENT_交接说明.md`、`docs/功能实现文档.md`、`docs/问题档案.md`

**Interfaces:**
- Consumes: Task 1–4 的最终行为。
- Produces: 文档与实现一致。

- [ ] **Step 1: `docs/KONG_开发文档.md`**

- R-09 行标注 **（已作废，见 R-12）**；新增 R-12 行（照抄 spec §3.6 的条文）。
- §3.6 「Kongbaya 与结算」中"押注/all-in/返还"描述改按新规则（名次发钱、垫底 −1 命、起始 2 命）。
- 若 §6/§6.3 等处出现"押注/灵魂币"表述，改为"名次奖励/生命"。

- [ ] **Step 2: `docs/网络协议_V1.md`**

- 删除 `bet` RPC 行与 `request_bet` 相关描述。
- 快照字段：删除 `bet_ready`；`players[].health` 默认标注为 2。
- `result.economy` → `result.rewards = {SeatId: {money, life_lost}}`；`result.penalized` 语义更新。

- [ ] **Step 3: `docs/AI_AGENT_交接说明.md`**

- §2 基线：把"押注经济"条目改写为"名次奖励经济（R-12）"；状态机表 `9 BET` 标注"已弃用"；§5/§8 验证命令保持 `verify_economy`。（按 spec §4 更新经济估计要点。）

- [ ] **Step 4: `docs/功能实现文档.md`**

- 更新经济/押注相关段落为名次奖励；把 `bet_panel` 从文件树移除，新增 `coin_icon`/`life_icon`/`stat_hud`。

- [ ] **Step 5: `docs/问题档案.md`**

- Q-01 状态改为"已解决（押注阶段随 R-12 移除，BET 卡死不复存在）"。

- [ ] **Step 6: 提交**

```bash
git add docs/
git commit -m "doc: R-12 rank-reward economy, protocol and baseline updates"
```

---

## 自检（Self-Review）

- **Spec 覆盖**：R-12 规则（Task 1）、`result.rewards`（Task 1/4）、快照去 `bet_ready` 与 health 默认 2（Task 1）、HUD（Task 3）、押注面板下线（Task 4）、文档（Task 5）、Q-01 附带修复（Task 5）。经济估计为设计文档内容，无需代码任务。
- **占位扫描**：无 TBD/TODO；所有代码步骤含可执行代码。
- **类型一致性**：`_settle_rewards` 返回 `{seat: {money, life_lost}}` 在 Task 1 定义，Task 4 的 `_show_rewards` 按同结构读取；`START_HEALTH`/`RANK_REWARD_*` 名称在 Task 1 定义并被测试引用；`StatHud.setup(state, seat)` 与 `game_view` 调用一致。
