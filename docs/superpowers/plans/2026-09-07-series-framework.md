# KONG 系列赛框架（Milestone 1）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有单局结算之上加入**多局系列赛**：房主设定局数 X、局间自动衔接下一局、把末（赛满 X 局或存活≤1）展示系列赛总排名、`health==0` 的玩家出局观战（保留空标签、仅公开信息）。

**Architecture:** 全服务器权威。系列赛状态落在 `run_state`（`match_limit`）与 `players[seat]`（`wins`/`currency`）；新增统一存活谓词 `_is_alive`/`_alive_order`，发牌、回合推进、开局确认、结算排名全部走存活者集合；`_finish_game` 后由服务器 Timer 自动开下一局（把末不启动）；新增纯函数 `SeriesRanking.final_ranking` 计算把末总排名；观战者沿用现有快照权限模型（无手牌 → 天然只见公开信息）+ 服务器拒绝其一切操作。客户端：大厅局数配置（SpinBox）、对局进度"第 N / X 局"、结算页把末总榜（扩展 `settlement_page.tscn` 场景实体）。

**Tech Stack:** Godot 4.6 / GDScript / ENet。headless 单测（`tests/verify_series.tscn`）。

**Spec:** `docs/superpowers/specs/2026-09-07-series-shop-relics-design.md` §3-4、§7-8。

## Global Constraints

- 保持 `GameState` 服务器权威、私有快照（`HiddenInfo._snapshot_for(viewer_id)`）、贴牌服务器时序三条架构不变量不变。
- `enable_relics` 基础模式（本里程碑不含遗物）不受影响；`run_state` 仍可序列化。
- 客户端只能调 `request_*` 意图方法；服务器校验调用者、阶段、目标。
- 新 UI 优先 `.tscn` 场景实体，不纯代码生成（结算页扩展沿用 `settlement_page.tscn`）。
- 每次改动后跑回归：`tools/run_all_tests.sh --quick`；提交按 `feat/fix/doc` 分类。
- 改动规则前更新 `docs/KONG_开发文档.md`；改协议前更新 `docs/网络协议_V1.md`。

---

### Task 1: 服务器系列赛字段 + 存活谓词 + 观战守卫

**Files:**
- Modify: `scripts/core/game_rules.gd`
- Modify: `scripts/core/game_state.gd`（`RejectCode` 枚举、`_reject_code_message`、`_add_player`、helpers 区）
- Create: `tests/verify_series.gd`、`tests/verify_series.tscn`

**Interfaces:**
- Consumes: 现有 `GameState`（autoload）`players[seat]` 结构、`RejectCode` 枚举、`KongRules.new_default_run()`。
- Produces: `KongRules.DEFAULT_MATCH_LIMIT/MIN_MATCH_LIMIT/MAX_MATCH_LIMIT/START_CURRENCY`；`GameState._is_alive(seat)->bool`、`GameState._alive_order()->Array[int]`、`GameState._alive_count()->int`、`GameState._guard_spectator(sender, action_id)->bool`；`RejectCode.SPECTATOR`。测试：`_open(limit)`、`_check(name, ok)`、`_test_lifecycle`、`_test_guard`。

- [ ] **Step 1: 写失败测试**

`tests/verify_series.gd`：

```gdscript
extends Node
## headless 单元测试：系列赛框架（Milestone 1）

var failures := 0
var checks := 0
var _rejections := 0

func _ready() -> void:
	await _test_lifecycle()
	await _test_guard()
	var status: String = " (FAILURES!)" if failures > 0 else ""
	print("=== SERIES RESULT: %d/%d passed%s ===" % [checks - failures, checks, status])
	get_tree().quit(1 if failures > 0 else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _open(_limit := 0) -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0)

func _test_lifecycle() -> void:
	GameState.command_rejected.connect(func(_c: int, _m: String) -> void: _rejections += 1)
	_rejections = 0
	_open()
	_check("默认 match_limit=5", int(GameState.run_state.get("match_limit", 0)) == 5)
	_check("初始 currency=10", int(GameState.players[0].get("currency", 0)) == 10)
	_check("初始 wins=0", int(GameState.players[0].get("wins", -1)) == 0)
	_check("三人生存计数=3", GameState._alive_count() == 3)
	GameState.players[2].health = 0
	_check("淘汰后存活计数=2", GameState._alive_count() == 2)
	_check("淘汰者不在存活序", GameState._alive_order() == [0, 1])

func _test_guard() -> void:
	_rejections = 0
	_open()
	GameState.players[0].health = 0
	_check("guard 拦截观战者", GameState._guard_spectator(0, "g-0"))
	_check("guard 放行存活者", not GameState._guard_spectator(1, "g-1"))
	_check("SPECTATOR 拒绝已发", _rejections == 1)
```

`tests/verify_series.tscn`：

```
[gd_scene format=3 uid="uid://bseries0000001"]

[ext_resource type="Script" path="res://tests/verify_series.gd" id="1"]

[node name="VerifySeries" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_series.tscn`
Expected: FAIL（`match_limit`/`currency`/`wins` 不存在、`_is_alive`/`_alive_order`/`_guard_spectator` 未定义、`RejectCode.SPECTATOR` 缺失）。

- [ ] **Step 3: 实现**

`scripts/core/game_rules.gd` —— 新增常量，并在 `new_default_run()` 加 `match_limit`：

```gdscript
const START_CURRENCY := 10
const DEFAULT_MATCH_LIMIT := 5
const MIN_MATCH_LIMIT := 2
const MAX_MATCH_LIMIT := 10
```
```gdscript
	return {
		"health": 3,
		"relic_slots": 2,
		"relics": {},
		"mutator_ids": [],
		"enable_relics": false,
		"match_limit": DEFAULT_MATCH_LIMIT,
	}
```

`scripts/core/game_state.gd` —— 枚举末尾追加 `SPECTATOR`：

```gdscript
	MATCH_SUSPENDED,
	INVALID_TOKEN,
	SPECTATOR,
}
```

`_reject_code_message` 追加分支：

```gdscript
		RejectCode.SPECTATOR: return "你已出局，只能观战。"
```

`_add_player` 的 `players[seat]` 字典追加两个字段（放 `"health"` 之后）：

```gdscript
		"currency": KongRules.START_CURRENCY,
		"wins": 0,
```

新增存活谓词与观战守卫（放在 `_peer_to_seat` 之后）：

```gdscript
## 玩家是否存活（health=灵魂币>0；本里程碑沿用现有 health 扣血机制，economy 里程碑再替换）。
func _is_alive(seat: int) -> bool:
	return players.has(seat) and int(players[seat].get("health", 0)) > 0

## 存活座位按 turn_order 顺序。
func _alive_order() -> Array[int]:
	var arr: Array[int] = []
	for seat in turn_order:
		if _is_alive(int(seat)):
			arr.append(int(seat))
	return arr

func _alive_count() -> int:
	return _alive_order().size()

## 已出局（观战）玩家操作拦截：返回 true 表示已拒绝。
func _guard_spectator(sender: int, action_id: String) -> bool:
	if not _is_alive(sender):
		_reject(sender, RejectCode.SPECTATOR, action_id)
		return true
	return false
```

- [ ] **Step 4: 运行测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_series.tscn`
Expected: PASS，9/9。

- [ ] **Step 5: 提交**

```bash
git add scripts/core/game_rules.gd scripts/core/game_state.gd tests/verify_series.gd tests/verify_series.tscn
git commit -m "feat: 系列赛基础字段 + 存活谓词 + 观战守卫（SPECTATOR）"
```

---

### Task 2: 房主设定局数 X（start_match 带参）

**Files:**
- Modify: `scripts/core/game_state.gd`（`request_start_match`/`server_start_match`/`_server_start_match`）
- Modify: `tests/verify_series.gd`（追加 `_test_match_limit`，`_ready` 注册）

**Interfaces:**
- Consumes: Task 1 的 `KongRules.MIN/MAX_MATCH_LIMIT`。
- Produces: `GameState.request_start_match(match_limit := 0)`、`GameState.server_start_match(match_limit: int)`（RPC）、`GameState._server_start_match(sender, match_limit := 0)`。旧调用 `_server_start_match(0)` 行为不变（默认 5）。

- [ ] **Step 1: 写失败测试**

`_ready` 中 `await _test_lifecycle()` 之前插入 `await _test_match_limit()`；新增：

```gdscript
func _test_match_limit() -> void:
	_rejections = 0
	_open(3)
	_check("start_match 设定局数=3", int(GameState.run_state.get("match_limit", 0)) == 3)
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(0, 99)
	_check("局数超上限被夹到10", int(GameState.run_state.get("match_limit", 0)) == 10)
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(0, 1)
	_check("局数低于下限回退默认5", int(GameState.run_state.get("match_limit", 0)) == 5)
	GameState._server_start_match(1, 7)
	_check("非房主拒绝(状态不变)", GameState.phase == GameState.Phase.LOBBY and int(GameState.run_state.get("match_limit", 0)) == 5)
```

- [ ] **Step 2: 运行确认失败**

Expected: FAIL（`_server_start_match` 只收 1 参，传 2 参报错 / 参数被忽略）。

- [ ] **Step 3: 实现**

替换 `game_state.gd` 三处函数：

```gdscript
func request_start_match(match_limit := 0) -> void:
	if multiplayer.is_server():
		_server_start_match(_peer_to_seat(1), match_limit)
	else:
		server_start_match.rpc_id(1, match_limit)

@rpc("any_peer", "reliable")
func server_start_match(match_limit: int) -> void:
	if multiplayer.is_server():
		_server_start_match(_peer_to_seat(multiplayer.get_remote_sender_id()), match_limit)

func _server_start_match(sender: int, match_limit := 0) -> void:
	if phase != Phase.LOBBY:
		_reject(sender, RejectCode.ROOM_NOT_OPEN)
		return
	if sender != 0:
		_reject(sender, RejectCode.NOT_HOST)
		return
	if players.size() < KongRules.MIN_PLAYERS:
		_reject(sender, RejectCode.NOT_ENOUGH_PLAYERS)
		return
	var limit: int = match_limit if match_limit >= KongRules.MIN_MATCH_LIMIT else KongRules.DEFAULT_MATCH_LIMIT
	run_state["match_limit"] = clampi(limit, KongRules.MIN_MATCH_LIMIT, KongRules.MAX_MATCH_LIMIT)
	_deal_new_match()
```

同时更新 Task 1 的测试助手 `_open`，使其把局数传下去：

```gdscript
func _open(limit := 0) -> void:
	...
	GameState._server_start_match(0, limit)
```

- [ ] **Step 4: 运行确认通过**

Expected: PASS，累计 13/13。

- [ ] **Step 5: 提交**

```bash
git add scripts/core/game_state.gd tests/verify_series.gd
git commit -m "feat: start_match 携带系列赛局数 X（夹取 2-10，默认 5）"
```

---

### Task 3: 系列赛结束判定 + 胜场计数 + 把末总排名

**Files:**
- Create: `scripts/core/series_ranking.gd`
- Modify: `scripts/core/game_state.gd`（`_series_finished`、`_finish_game` 胜场累加与 series 结果）
- Modify: `tests/verify_series.gd`（追加 `_test_series_end`、`_test_ranking`，`_ready` 注册）

**Interfaces:**
- Consumes: Task 1 的 `_is_alive`/`_alive_order`；现有 `ScoreSystem`。
- Produces: `GameState._series_finished()->bool`；`SeriesRanking.final_ranking(players: Dictionary, turn_order: Array) -> Array`（每项 `{id,name,wins,currency}`，存活者按 wins 降序 → currency 降序 → seat 升序）；`_finish_game` 在 `last_result.series` 写入 `{"finished": true, "ranking": [...]}`（仅把末）。

- [ ] **Step 1: 写失败测试**

`_ready` 中 `await _test_lifecycle()` 之后追加 `await _test_series_end()`、`await _test_ranking()`：

```gdscript
func _test_series_end() -> void:
	_rejections = 0
	_open(1)  # match_limit=1，match_number 起步 1 → 一局即把末
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._finish_game()
	_check("赛满局数后 _series_finished", GameState._series_finished())
	_check("把末 last_result.series.finished", bool(GameState.last_result.get("series", {}).get("finished", false)))
	var series: Dictionary = GameState.last_result.get("series", {})
	_check("把末 series.ranking 含 3 人", (series.get("ranking", []) as Array).size() == 3)

func _test_ranking() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState.players[0].wins = 2
	GameState.players[0].currency = 5
	GameState.players[1].wins = 3
	GameState.players[1].currency = 9
	GameState.players[2].wins = 3
	GameState.players[2].currency = 7
	var r: Array = SeriesRanking.final_ranking(GameState.players, GameState.turn_order)
	_check("排名按胜场降序、同胜场按货币降序", [int(r[0].id), int(r[1].id), int(r[2].id)] == [1, 2, 0])
	GameState.players[2].health = 0
	r = SeriesRanking.final_ranking(GameState.players, GameState.turn_order)
	_check("淘汰者不入总排名", r.size() == 2 and int(r[0].id) != 2 and int(r[1].id) != 2)
```

- [ ] **Step 2: 运行确认失败**

Expected: FAIL（`_series_finished` 未定义、`SeriesRanking` 不存在、`last_result.series` 为空）。

- [ ] **Step 3: 实现**

新建 `scripts/core/series_ranking.gd`：

```gdscript
class_name SeriesRanking
extends RefCounted
## 系列赛把末总排名（纯计算，不持有状态）。
## 存活者：胜场降序 → 货币降序 → seat 升序；淘汰者不入榜。

static func final_ranking(players: Dictionary, turn_order: Array) -> Array:
	var entries: Array = []
	for seat in turn_order:
		var p: Dictionary = players[int(seat)]
		if int(p.get("health", 0)) <= 0:
			continue
		entries.append({
			"id": int(seat),
			"name": str(p.get("name", "")),
			"wins": int(p.get("wins", 0)),
			"currency": int(p.get("currency", 0)),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.wins) != int(b.wins):
			return int(a.wins) > int(b.wins)
		if int(a.currency) != int(b.currency):
			return int(a.currency) > int(b.currency)
		return int(a.id) < int(b.id))
	return entries
```

`game_state.gd` —— 新增判定（放在 `_finish_game` 之前）：

```gdscript
## 系列赛是否已结束：赛满局数 或 存活数<=1。
func _series_finished() -> bool:
	return match_number >= int(run_state.get("match_limit", KongRules.DEFAULT_MATCH_LIMIT)) or _alive_count() <= 1
```

`_finish_game`（reason-only 分支返回前不动）：在 `_broadcast_sfx` 前插入胜场累加与 series 结果；**胜场在广播前写入，series 在广播前写入快照**：

```gdscript
	for entry in winners:
		players[entry].wins = int(players[entry].get("wins", 0)) + 1
	if _series_finished():
		last_result["series"] = {"finished": true, "ranking": SeriesRanking.final_ranking(players, turn_order)}
```

- [ ] **Step 4: 运行确认通过**

Expected: PASS，累计 18/18。

- [ ] **Step 5: 提交**

```bash
git add scripts/core/series_ranking.gd scripts/core/game_state.gd tests/verify_series.gd
git commit -m "feat: 系列赛结束判定 + 胜场计数 + 把末总排名（SeriesRanking）"
```

---

### Task 4: 淘汰处理（发牌/回合/开局确认/排名走存活者）+ 观战快照

**Files:**
- Modify: `scripts/core/game_state.gd`（`_deal_new_match`、`_server_initial_ready`、`_advance_turn`、`_calculate_ranking`、各 `_server_*` 守卫）
- Modify: `scripts/core/kongbaya_system.gd`（`build_final_queue` 用存活序）
- Modify: `scripts/core/hidden_info.gd`（`_player_snapshot` 加 `eliminated`）
- Modify: `tests/verify_series.gd`（追加 `_test_elimination`、`_test_spectator_snapshot`，`_ready` 注册）

**Interfaces:**
- Consumes: Task 1 的 `_alive_order`/`_alive_count`/`_guard_spectator`。
- Produces: `_deal_new_match` 只给存活者发牌；`_server_initial_ready` 按存活数判定；`_advance_turn`/kongbaya 最终轮队列走 `_alive_order`；`_calculate_ranking` 走存活序；玩家快照新增 `eliminated` 布尔。

- [ ] **Step 1: 写失败测试**

`_ready` 追加 `await _test_elimination()`、`await _test_spectator_snapshot()`：

```gdscript
func _test_elimination() -> void:
	_open()
	GameState.players[2].health = 0
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	_check("存活者就绪即开局(不需淘汰者确认)", GameState.phase == GameState.Phase.TURN_DRAW)
	_check("淘汰者未被发牌", GameState.players[2].cards.is_empty())
	_check("存活者各发4张", GameState.players[0].cards.size() == KongRules.HAND_SIZE and GameState.players[1].cards.size() == KongRules.HAND_SIZE)
	var d: Dictionary = TurnSystem.decide(GameState._alive_order(), 0, -1, [])
	_check("回合跳过淘汰者 0->1", int(d.next_player) == 1)

func _test_spectator_snapshot() -> void:
	_open()
	GameState.players[2].health = 0
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	var snap: Dictionary = GameState._snapshot_for(2)
	var leak := false
	for p in snap.players:
		for s in p.slots:
			if (s as Dictionary).has("card"):
				leak = true
	_check("观战快照无任何暗牌面", not leak)
	_check("观战者本人 eliminated 标记", bool(snap.players[2].get("eliminated", false)))
```

- [ ] **Step 2: 运行确认失败**

Expected: FAIL（淘汰者仍被发牌 / 开局仍等 3 人确认 / 快照无 `eliminated`）。

- [ ] **Step 3: 实现**

`game_state.gd` `_deal_new_match` —— 改为先清全部手牌、只给存活者发牌：

```gdscript
	for seat in turn_order:
		players[seat].cards.clear()
		players[seat].has_acted = false
	for seat in _alive_order():
		for _slot in KongRules.HAND_SIZE:
			players[seat].cards.append(_draw_from_deck())
```

`_server_initial_ready` —— 加观战守卫 + 存活数判定 + 首个存活者开局：

```gdscript
	if _guard_spectator(sender, ""):
		return
	...
	if initial_confirmed.size() < _alive_count():
		_broadcast_state()
		return
	current_player_id = _alive_order()[0]
```

`_advance_turn` —— NEXT 分支用存活序：

```gdscript
	else:
		decision = TurnSystem.decide(_alive_order(), current_player_id, kong_caller, [])
```

`_calculate_ranking`：

```gdscript
func _calculate_ranking() -> Array:
	return ScoreSystem.calculate_ranking(players, cards, _alive_order())
```

在所有动作 `_server_*` 处理器中，于 `_guard_suspended(sender, action_id)` 之后插入 `_guard_spectator`（涉及：`_server_take`、`_server_replace`、`_server_discard_draw`、`_server_use_ability`、`_server_q_decision`、`_server_slap`、`_server_slap_exchange`、`_server_slap_duel_stop`、`_server_kongbaya`）：

```gdscript
	if _guard_spectator(sender, action_id):
		return
```

`kongbaya_system.gd` `declare` 第 30 行：

```gdscript
	game.final_queue = TurnSystem.build_final_queue(game._alive_order(), sender)
```

`hidden_info.gd` `_player_snapshot` 返回值追加：

```gdscript
	return {"id": seat, "name": player.name, "count": player.cards.size(), "health": player.health,
		"eliminated": int(player.get("health", 1)) <= 0,
		"ready": state.initial_confirmed.has(seat), "slots": slots}
```

- [ ] **Step 4: 运行确认通过**

Expected: PASS，累计 24/24。随后跑 `verify_settlement`/`verify_reconnect`/`verify_kongbaya`/`verify_duel` 确认无回归（`_deal_new_match` 行为对全存活局不变）。

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_settlement.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_reconnect.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_kongbaya.tscn
```
Expected: 全部 PASS（settlement 38、reconnect 41、kongbaya 15）。

- [ ] **Step 5: 提交**

```bash
git add scripts/core/game_state.gd scripts/core/kongbaya_system.gd scripts/core/hidden_info.gd tests/verify_series.gd
git commit -m "feat: 淘汰者跳过发牌/回合/开局确认/排名 + 观战快照（eliminated）+ 观战守卫接入全部动作 RPC"
```

---

### Task 5: 局间自动衔接（服务器 Timer 开下一局）

**Files:**
- Modify: `scripts/core/game_rules.gd`（`SERIES_AUTO_ADVANCE_MS`）
- Modify: `scripts/core/game_state.gd`（`series_timer`、`_ready`、`_reset_match`、`_deal_new_match`、`_finish_game`、`_server_next_match`）
- Modify: `tests/verify_series.gd`（追加 `_test_auto_advance`、`_test_next_match_guard`，`_ready` 注册）

**Interfaces:**
- Consumes: Task 3 的 `_series_finished`；现有 `_server_next_match(sender, action_id)`。
- Produces: `GameState.series_timer`（one_shot Timer）；`_start_series_timer()`；`_on_series_auto_advance()`（timeout 回调）；`_finish_game` 中"非把末且非 reason-only 时启动自动衔接"；`_server_next_match` 把末时拒绝。

- [ ] **Step 1: 写失败测试**

`_ready` 追加 `await _test_auto_advance()`、`await _test_next_match_guard()`：

```gdscript
func _test_auto_advance() -> void:
	_open(5)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._finish_game()
	_check("非把末启动自动衔接 Timer", not GameState.series_timer.is_stopped())
	GameState._on_series_auto_advance()
	_check("自动开下一局 match_number 递增", GameState.match_number == 2)
	_check("回 INITIAL_PEEK", GameState.phase == GameState.Phase.INITIAL_PEEK)
	GameState._finish_game()
	GameState._server_next_match(0, "nm-ok")
	_check("未把末仍可手动 next", GameState.phase == GameState.Phase.INITIAL_PEEK)

func _test_next_match_guard() -> void:
	_rejections = 0
	_open(1)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
	GameState._finish_game()
	_check("把末 Timer 不启动", GameState.series_timer.is_stopped())
	GameState._server_next_match(0, "nm-x")
	_check("把末 next_match 被拒", _rejections == 1 and GameState.phase == GameState.Phase.GAME_OVER)
```

- [ ] **Step 2: 运行确认失败**

Expected: FAIL（无 `series_timer` 属性；`_finish_game` 不启动 Timer）。

- [ ] **Step 3: 实现**

`game_rules.gd` 常量追加：

```gdscript
## 局间自动衔接：结算展示多久后服务器自动开下一局（毫秒）。商店里程碑将替换为等全员。
const SERIES_AUTO_ADVANCE_MS := 10000
```

`game_state.gd` 成员与初始化：

```gdscript
var series_timer := Timer.new()
```
`_ready` 中（`slap_duel_timer` 之后）：

```gdscript
	series_timer.one_shot = true
	add_child(series_timer)
	series_timer.timeout.connect(_on_series_auto_advance)
```

`_reset_match`（清 `slap_duel_timer.stop()` 之后）与 `_deal_new_match`（同样位置）各加 `series_timer.stop()`。

`_finish_game` —— 在 `_broadcast_state()` 之后追加（reason-only 与把末不启动）：

```gdscript
	if not last_result.get("ranking", []).is_empty() and not _series_finished():
		_start_series_timer()
```

新增函数（放 `_finish_game` 附近）：

```gdscript
func _start_series_timer() -> void:
	series_timer.start(KongRules.SERIES_AUTO_ADVANCE_MS / 1000.0)

## 局间自动衔接：到点且仍处结算、未把末时由服务器（房主权威）开下一局。
func _on_series_auto_advance() -> void:
	if phase != Phase.GAME_OVER or _series_finished():
		return
	if _alive_count() < KongRules.MIN_PLAYERS:
		return
	_server_next_match(0)
```

`_server_next_match` —— 在 `phase != GAME_OVER` 检查之后插入：

```gdscript
	if _series_finished():
		_reject(sender, RejectCode.INVALID_PHASE, action_id)
		return
```

- [ ] **Step 4: 运行确认通过**

Expected: PASS，累计 30/30。跑 `verify_settlement`（38/38）确认 `_server_next_match` 旧路径（非把末）不回归。

- [ ] **Step 5: 提交**

```bash
git add scripts/core/game_rules.gd scripts/core/game_state.gd tests/verify_series.gd
git commit -m "feat: 局间自动衔接（GAME_OVER 后 Timer 开下一局，把末不启动）+ next_match 把末拒绝"
```

---

### Task 6: 客户端大厅局数配置 + 对局进度与观战显示

**Files:**
- Modify: `scripts/ui/main.gd`（`var match_limit_spin: SpinBox = null`）
- Modify: `scripts/ui/lobby_view.gd`（SpinBox、start 包装）
- Modify: `scripts/ui/game_view.gd`（round label 显示 X；观战者隐藏操作 + 空标签）
- Test: 手动（headless 编译检查 + verify_series 冒烟保持绿）

**Interfaces:**
- Consumes: `GameState.request_start_match(match_limit)`；快照 `state.run.match_limit`、`state.players[].eliminated`。
- Produces: `main.match_limit_spin`；大厅"系列赛局数 X"SpinBox（仅房主可见）；对局顶部"第 N / X 局"；观战者提示"你已出局，正在观战。"

- [ ] **Step 1: 大厅局数配置**

`main.gd` 变量区新增：

```gdscript
var match_limit_spin: SpinBox = null
```

`lobby_view.gd` `build()` 末尾（`main.lobby_members` 之前）新增：

```gdscript
	var spin_row := HBoxContainer.new()
	spin_row.add_theme_constant_override("separation", 8)
	main.lobby_panel.add_child(spin_row)
	var spin_lbl := Label.new()
	spin_lbl.text = "系列赛局数 X："
	spin_row.add_child(spin_lbl)
	main.match_limit_spin = SpinBox.new()
	main.match_limit_spin.min_value = KongRules.MIN_MATCH_LIMIT
	main.match_limit_spin.max_value = KongRules.MAX_MATCH_LIMIT
	main.match_limit_spin.step = 1
	main.match_limit_spin.value = KongRules.DEFAULT_MATCH_LIMIT
	main.match_limit_spin.custom_minimum_size = Vector2(100, 0)
	main.match_limit_spin.visible = false
	spin_row.add_child(main.match_limit_spin)
```

`update_lobby()` 中房主分支（`main.start_button` 创建处）改绑定，并加 spin 显隐：

```gdscript
		main.start_button.pressed.connect(_start_with_limit)
		main.match_limit_spin.visible = true
```
非房主分支末尾加 `main.match_limit_spin.visible = false`。

新增方法：

```gdscript
func _start_with_limit() -> void:
	GameState.request_start_match(int(main.match_limit_spin.value))
```

- [ ] **Step 2: 对局进度显示**

`game_view.gd` `render()` 第 114 行替换：

```gdscript
	var limit: int = int((state.get("run", {}) as Dictionary).get("match_limit", KongRules.DEFAULT_MATCH_LIMIT))
	main.round_label.text = "第 %d / %d 局" % [int(state.get("match_number", 1)), limit]
```

- [ ] **Step 3: 观战者显示**

`game_view.gd` `render()` 顶部（`var is_current` 之后）计算观战者，并令其不显示 Ready / 不可操作：

```gdscript
	var viewer_eliminated := false
	for player in state.players:
		if int(player.id) == viewer and bool(player.get("eliminated", false)):
			viewer_eliminated = true
			break
	if viewer_eliminated:
		main.ready_button.visible = false
		main.bell_button.disabled = true
		main.deck_button.disabled = true
		main._highlight(main.deck_button, false)
		main.center_hint.text = "你已出局，正在观战。"
	else:
		if phase == PHASE_INITIAL_PEEK:
			var ready_count: int = int(state.get("ready_count", 0))
			main.ready_button.visible = true
			main.ready_button.disabled = ready_count >= total_players or _ready_clicked
			if _ready_clicked:
				main.ready_button.text = "已准备（%d/%d）" % [ready_count, total_players]
			else:
				main.ready_button.text = "Ready（%d/%d）" % [ready_count, total_players]
		else:
			main.ready_button.visible = false
			_ready_clicked = false
		main.center_hint.text = main._hint_for(phase, is_current)
```

`_render_player_section` 名字标签（原 372 行附近）追加淘汰标记并置灰：

```gdscript
	var eliminated := bool(player.get("eliminated", false))
	var elim_suffix := "  [已淘汰·观战]" if eliminated else ""
	name_label.text = "%s%s%s%s" % [player.name, suffix, ready_mark, elim_suffix]
	if eliminated:
		name_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
```

- [ ] **Step 4: 验证**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_series.tscn
```
Expected: 编译无错；verify_series 全绿。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/main.gd scripts/ui/lobby_view.gd scripts/ui/game_view.gd
git commit -m "feat: 大厅局数X配置 + 对局进度显示 + 观战者空标签/隐藏操作"
```

---

### Task 7: 结算页系列进度 + 把末总榜（场景实体扩展）

**Files:**
- Modify: `scenes/ui/settlement_page.tscn`（新增 `StatusLabel`、`SeriesBox`）
- Modify: `scripts/ui/settlement_page.gd`（setup 新参、标题带 X、系列总榜、footer 状态）
- Modify: `scripts/ui/main.gd`（`_open_settlement` 传新参）
- Modify: `tests/verify_series.gd`（追加 `_test_page_series`，`_ready` 注册）

**Interfaces:**
- Consumes: 快照 `state.result.series`、`state.run.match_limit`；`SettlementModel.build`。
- Produces: `settlement_page.setup(..., match_limit := 0, series := {})`；`_show_series_summary(series)`；标题"结算 · 第 N / X 局"；footer：把末→（房主仅"返回大厅"、提示"系列赛结束"），非把末→（房主"返回大厅"、提示"下一局即将自动开始…"，客户端"等待进入下一局…"）。

- [ ] **Step 1: 场景实体扩展**

`settlement_page.tscn` 的 `Center/Panel/VBox` 内、`RankingArea` 之后追加：

```
[node name="StatusLabel" type="Label" parent="Center/Panel/VBox"]
layout_mode = 2
visible = false
horizontal_alignment = 1
theme_override_font_sizes/font_size = 14
theme_override_colors/font_color = Color(0.85, 0.85, 0.85, 1)

[node name="SeriesBox" type="VBoxContainer" parent="Center/Panel/VBox"]
layout_mode = 2
visible = false
theme_override_constants/separation = 4

[node name="SeriesTitle" type="Label" parent="Center/Panel/VBox/SeriesBox"]
layout_mode = 2
text = "系列赛总排名"
horizontal_alignment = 1
theme_override_font_sizes/font_size = 18
theme_override_colors/font_color = Color(0.96, 0.84, 0.48, 1)

[node name="SeriesRows" type="VBoxContainer" parent="Center/Panel/VBox/SeriesBox"]
layout_mode = 2
```

- [ ] **Step 2: 写失败测试**

`_ready` 追加 `await _test_page_series()`：

```gdscript
func _test_page_series() -> void:
	await get_tree().process_frame
	var model: Dictionary = SettlementModel.build([
		{"id": 0, "name": "A", "count": 2, "slots": [
			{"card_id": "a0", "card": {"rank": "7", "suit": "♠", "value": 7, "label": "7♠"}},
			{"card_id": "a1", "card": {"rank": "2", "suit": "♥", "value": 2, "label": "2♥"}}]},
		{"id": 1, "name": "B", "count": 2, "slots": [
			{"card_id": "b0", "card": {"rank": "3", "suit": "♠", "value": 3, "label": "3♠"}},
			{"card_id": "b1", "card": {"rank": "4", "suit": "♥", "value": 4, "label": "4♥"}}]},
	])
	var series: Dictionary = {"finished": true, "ranking": [
		{"id": 1, "name": "B", "wins": 3, "currency": 9},
		{"id": 0, "name": "A", "wins": 2, "currency": 5}]}
	var page: Control = preload("res://scenes/ui/settlement_page.tscn").instantiate()
	get_tree().root.add_child(page)
	page.setup(model, true, 3, Callable(), Callable(), Callable(), Callable(), false, 5, series)
	await get_tree().process_frame
	_check("结算页标题带局数X", page._title.text == "结算 · 第 3 / 5 局")
	page._show_series_summary(series)
	_check("把末总榜已显示", page.get_node("Center/Panel/VBox/SeriesBox").visible)
	var rows: VBoxContainer = page.get_node("Center/Panel/VBox/SeriesBox/SeriesRows")
	_check("总榜行数=排名数", rows.get_child_count() == 2)
	page.queue_free()
```

- [ ] **Step 3: 实现**

`settlement_page.gd` —— 存 `_series`，`setup` 追加两参，标题带 X：

```gdscript
var _series: Dictionary = {}
```
```gdscript
func setup(model: Dictionary, is_host: bool, match_number: int,
		on_winner: Callable, on_next_match: Callable, on_abort: Callable,
		on_flip := Callable(), auto_play := true, match_limit := 0, series := {}) -> void:
	_series = series
	...
	_bind_ui(match_number, match_limit)
```
`_bind_ui(match_number: int, match_limit := 0)` 标题行：

```gdscript
	if match_limit > 0:
		_title.text = "结算 · 第 %d / %d 局" % [match_number, match_limit]
	else:
		_title.text = "结算 · 第 %d 局" % match_number
```

`_run_sequence()` 末尾（`_show_footer()` 之前）加：

```gdscript
	if not _series.is_empty():
		_show_series_summary(_series)
```

新增方法：

```gdscript
func _show_series_summary(series: Dictionary) -> void:
	var box: VBoxContainer = get_node("Center/Panel/VBox/SeriesBox")
	var rows: VBoxContainer = get_node("Center/Panel/VBox/SeriesBox/SeriesRows")
	for child in rows.get_children():
		child.queue_free()
	var ranking: Array = series.get("ranking", [])
	for index in ranking.size():
		var entry: Dictionary = ranking[index]
		var row := Label.new()
		row.text = "%d. %s　胜场 %d · 货币 %d" % [index + 1, str(entry.name), int(entry.wins), int(entry.currency)]
		row.add_theme_font_size_override("font_size", 15)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if index == 0:
			row.add_theme_color_override("font_color", UITheme.color("accent"))
		rows.add_child(row)
	box.visible = true
```

`_show_footer()` 整段替换为（非把末不显示"再来一局"，自动衔接）：

```gdscript
func _show_footer() -> void:
	_footer.visible = true
	var status: Label = get_node("Center/Panel/VBox/StatusLabel")
	var series_done := not _series.is_empty()
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_footer.add_child(box)
	if _is_host:
		var exit := Button.new()
		exit.text = "返回大厅"
		exit.pressed.connect(func() -> void:
			if _on_abort.is_valid():
				_on_abort.call())
		box.add_child(exit)
		status.text = "系列赛结束" if series_done else "下一局即将自动开始…"
	else:
		var wait := Label.new()
		wait.text = "系列赛结束" if series_done else "等待进入下一局…"
		wait.add_theme_color_override("font_color", UITheme.color("text_secondary"))
		box.add_child(wait)
	status.visible = true
```

`main.gd` `_open_settlement` 的 `page.setup(...)` 调用追加实参：

```gdscript
	var run: Dictionary = latest_state.get("run", {})
	var match_limit: int = int(run.get("match_limit", KongRules.DEFAULT_MATCH_LIMIT))
	var series: Dictionary = (latest_state.get("result", {}) as Dictionary).get("series", {})
	page.setup(model, Network.is_host, int(latest_state.get("match_number", 1)),
		_play_pending_winner, _request_next_match, GameState.request_abort_match,
		_on_settlement_flip, true, match_limit, series)
```

- [ ] **Step 4: 运行确认通过**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_series.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_settlement.tscn
```
Expected: verify_series 全绿（含 page 测试）；verify_settlement 38/38 不回归（旧 `setup` 调用走默认参）。

- [ ] **Step 5: 提交**

```bash
git add scenes/ui/settlement_page.tscn scripts/ui/settlement_page.gd scripts/ui/main.gd tests/verify_series.gd
git commit -m "feat: 结算页系列进度(第N/X局) + 把末总榜 + 局间自动衔接提示（场景实体扩展）"
```

---

### Task 8: 文档更新 + 回归接入 + 全量回归

**Files:**
- Modify: `docs/KONG_开发文档.md`（§3 新增 R-08 系列赛规则）
- Modify: `docs/网络协议_V1.md`（`start_match` 参数、快照新字段、SPECTATOR 错误码）
- Modify: `docs/功能实现文档.md`、`docs/AI_AGENT_交接说明.md`
- Modify: `tools/run_all_tests.sh`（加入 verify_series）

**Interfaces:** 无（纯文档 + 脚本）。

- [ ] **Step 1: 更新 `KONG_开发文档.md`**

§3.7 冻结决定表追加一行，并附规则变更说明：

```markdown
| R-08 | 系列赛：房主开局设定局数 X（2-10，默认 5）。每局结算后（GAME_OVER）非把末时由服务器自动开下一局；赛满 X 局或存活数≤1 时结束系列赛。`health==0` 者出局观战（保留座位、仅公开信息、不可操作）。把末总排名：存活者按胜场数降序→同胜场按货币降序（当前货币恒等，待 economy 里程碑生效），淘汰者不入榜。 | 把单局扩展为多局系列赛，死亡玩家不踢出房间。 |
```

并在 §5.6 断线行为表补注：系列赛中出局玩家断线重连后仍为观战者。

- [ ] **Step 2: 更新 `网络协议_V1.md`**

- 命令表 `start_match` 行：参数由 `{}` 改为 `{ match_limit: Integer }`（2-10，越界回退默认 5；客户端可不传）。
- 快照字段说明追加：`run.match_limit`（系列赛局数）、`players[].eliminated`（出局观战标记）、`result.series`（把末：`{finished, ranking:[{id,name,wins,currency}]}`，非把末不存在）。
- 错误码表追加 `SPECTATOR`：出局玩家尝试操作时返回。
- `next_match` 行补注：把末（`_series_finished`）后调用被拒；非把末由服务器 Timer 自动触发，客户端无需手动调用。

- [ ] **Step 3: 更新 `功能实现文档.md` 与 `AI_AGENT_交接说明.md`**

- 功能实现文档：二节"待开发"前新增"系列赛框架（已完成）"说明（文件落点、verify_series 计数）；回归基准补 `verify_series`。
- 交接说明：第 2 节基线补一条系列赛框架摘要；第 8 节验证命令补 verify_series 一行。

- [ ] **Step 4: 更新 `tools/run_all_tests.sh`**

`run_single "settlement"` 行之后加：

```bash
run_single "series"     res://tests/verify_series.tscn
```

- [ ] **Step 5: 全量回归**

Run: `tools/run_all_tests.sh --quick`
Expected: 全部 PASS（含新 verify_series；`verify_settlement`/`reconnect`/`kongbaya`/`duel`/`swap`/`protocol`/`hint` 保持全绿）。

- [ ] **Step 6: 提交**

```bash
git add docs/KONG_开发文档.md docs/网络协议_V1.md docs/功能实现文档.md docs/AI_AGENT_交接说明.md tools/run_all_tests.sh
git commit -m "doc: 系列赛框架规则/协议/功能文档同步 + 回归接入 verify_series"
```

---

## Self-Review

**Spec 覆盖核对：**
- §3 系列赛生命周期（局间自动衔接、把末判定、中途禁止加入）→ Task 2/3/5；中途禁止加入为现状（`_server_start_match` 仅 LOBBY，系列中无加入 RPC，维持不变）。
- §4 存活谓词/出局观战（空标签、仅公开信息、无操作权）→ Task 1/4/6；`health` 复用为灵魂币 → Task 1 `_is_alive`（economy 里程碑替换扣血来源，已预留）。
- §4 把末排名（胜场→货币、淘汰不入榜）→ Task 3 `SeriesRanking`。
- §7 架构落点（run_state/players 字段、系列排名独立函数、观战 hidden_info）→ Task 1/3/4。
- §8 测试 verify_series → Task 1-7 内建 + Task 8 接入回归。
- 用户要求"新 UI 优先 .tscn" → Task 7 扩展 `settlement_page.tscn`；大厅 SpinBox 为代码构建（延续现有大厅 UI 模式，无独立场景实体，属可接受例外）。

**占位符扫描：** 无 TBD/TODO；所有代码步骤给出具体 GDScript。

**类型一致性：** `_alive_order()`/`_is_alive()`/`_guard_spectator()`/`_series_finished()`/`SeriesRanking.final_ranking()` 命名在各任务间一致；`setup(..., match_limit, series)` 追加参数带默认值，旧调用（settlement/测试）兼容。

**范围：** 本计划仅 Milestone 1（系列赛框架）。economy / shop / relics 属后续独立计划（各产出可测软件），不在本计划内。