# 新手教程（3D 教学局 + 首局轻提示）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个可从主菜单进入的 3D 新手教学局：3–5 分钟、2 人桌、预置回放为主，玩家亲手完成抽牌/替换/抢贴/Kongbaya 四个关键步，并附带首次对局的 5 条一次性轻提示。

**Architecture:** 教学局是**纯客户端本地时间线**：`TutorialController` 驱动步骤，`TutorialSteps` 产出与 `HiddenInfo` 同形状的快照字典，直接喂 `Table3dView.render()`。教学场景自己实例化 `table3d.tscn`，用固定镜头 + 鼠标指针点击（`Table3dPicker.pick(cam, world, mouse_pos)`）；不碰 `GameState` / 网络 / 协议 / 快照。结算步骤复用 `SettlementPage` 与 `SettlementModel`。

**Tech Stack:** Godot 4.6 / GDScript / headless 单元测试（`res://tests/verify_tutorial.tscn`）/ 现有 `Table3dView`、`Table3dPicker`、`CardFly`、`SettlementPage`、`SettlementModel`、`KongRules`。

## Global Constraints

- 只做**纯客户端展示层**：不改 `scripts/core/game_state.gd`、`hidden_info.gd`、网络协议或既有快照字段。
- 教学局固定 2 人（seat 0 = 玩家，seat 1 = 脚本对手）；其余座位由 `Table3dView.render` 自动隐藏（`players` 只传 2 个）。
- 教学局**固定镜头 + 鼠标指针可见**（`MOUSE_MODE_VISIBLE`），不响应鼠标环视；结束页提示真局用准星。
- 覆盖范围仅基础牌局：记忆、抽/换/弃、能力一览、贴牌、Kongbaya、结算；不教商店/遗物/道具/随机效果。
- 牌值统一读 `KongRules.card_value`；不要在教学数据里硬编码分值。
- 教学状态必须可复现：固定牌序见 `TutorialSteps`，不得使用随机数。
- 所有教学文案集中在 `TutorialText`；不要在场景/控制器里散落字符串。
- 不启动 GUI 做自动化验证；headless 命令统一用 `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/ee/dev/gameDev/cambio-rouglike ...`。
- 提交（commit）只在用户明确授权后执行；未授权时跳过 commit 步骤，把改动留在工作区。

---

## File Structure

| 文件（绝对路径） | 责任 |
| --- | --- |
| `/Users/ee/dev/gameDev/cambio-rouglike/scripts/core/tutorial_progress.gd` | 教程进度持久化（`seen`/`completed`/5 条首局提示），路径可注入 |
| `/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_steps.gd` | 固定牌序 + 各步骤快照 + 结算模型（纯数据） |
| `/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_text.gd` | 全部教学文案（标题/正文/toast） |
| `/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_controller.gd` | 步骤机：推进、交互校验、纠错、跳过/重来 |
| `/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_overlay.gd` | 顶部进度、提示卡、动作按钮、继续、toast、角落菜单、总结页 |
| `/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_view.gd` | 场景根：实例化 `table3d.tscn`、固定镜头、鼠标拾取、渲染、结算页 |
| `/Users/ee/dev/gameDev/cambio-rouglike/scenes/tutorial/tutorial_3d.tscn` | 教学场景（Control 根 + 脚本） |
| `/Users/ee/dev/gameDev/cambio-rouglike/scripts/ui/lobby_view.gd` | 主菜单加「新手教程」按钮（wide/compact） |
| `/Users/ee/dev/gameDev/cambio-rouglike/scripts/ui/main.gd` | 打开/关闭教程、输入门控、首局轻提示接线 |
| `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.gd` | headless 测试：进度/数据/步骤机/场景/主菜单集成 |
| `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.tscn` | 测试场景 |
| `/Users/ee/dev/gameDev/cambio-rouglike/tools/run_all_tests.sh` | 注册 `verify_tutorial` |

---

### Task 1: 教程进度持久化

**Files:**
- Create: `/Users/ee/dev/gameDev/cambio-rouglike/scripts/core/tutorial_progress.gd`
- Create: `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.gd`
- Create: `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.tscn`

**Interfaces:**
- Produces: `TutorialProgress.new(path := "user://tutorial.cfg")`、`load()`、`save()`、`mark_seen()`、`mark_completed()`、`reset()`、`hint_done(id: String) -> bool`、`mark_hint(id: String)`；常量 `HINTS: Array[String]`（`initial_peek/first_turn/first_slap/first_shop/first_settle`）。

- [ ] **Step 1: 写失败测试**

`/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.gd`：

```gdscript
extends Node
## headless 单元测试：教程进度 / 固定牌序快照 / 步骤机 / 教学场景。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TUTORIAL RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_progress()

func _test_progress() -> void:
	var p := "user://test_tutorial.cfg"
	DirAccess.remove_absolute(p)
	var store := TutorialProgress.new(p)
	store.load()
	_check("缺文件→未看", not store.seen and not store.completed)
	_check("5 条首局提示默认未看", TutorialProgress.HINTS.size() == 5 and not store.hint_done("first_slap"))
	store.mark_seen()
	store.mark_hint("first_slap")
	store.mark_completed()
	var store2 := TutorialProgress.new(p)
	store2.load()
	_check("seen 持久化", store2.seen)
	_check("completed 持久化", store2.completed)
	_check("hint 持久化", store2.hint_done("first_slap"))
	_check("其他 hint 仍未看", not store2.hint_done("first_shop"))
	store2.reset()
	var store3 := TutorialProgress.new(p)
	store3.load()
	_check("reset 清空", not store3.seen and not store3.completed and not store3.hint_done("first_slap"))
	DirAccess.remove_absolute(p)
```

`/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.tscn`：

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/verify_tutorial.gd" id="1"]

[node name="VerifyTutorial" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/ee/dev/gameDev/cambio-rouglike res://tests/verify_tutorial.tscn
```

Expected: 解析失败/运行时报 `TutorialProgress` 未定义。

- [ ] **Step 3: 实现**

`/Users/ee/dev/gameDev/cambio-rouglike/scripts/core/tutorial_progress.gd`：

```gdscript
class_name TutorialProgress
extends RefCounted
## 教程进度本地持久化（仅本机用户）：seen/completed + 5 条首局轻提示。
## 路径可注入（测试用），与 KeybindStore 同模式。

const DEFAULT_PATH := "user://tutorial.cfg"
const SECTION := "tutorial"
const VERSION := 1
const HINTS := ["initial_peek", "first_turn", "first_slap", "first_shop", "first_settle"]

var path := DEFAULT_PATH
var seen := false
var completed := false
var hints: Dictionary = {}

func _init(p := DEFAULT_PATH) -> void:
	path = p
	for id in HINTS:
		hints[id] = false

func load() -> void:
	seen = false
	completed = false
	for id in HINTS:
		hints[id] = false
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	if int(cf.get_value(SECTION, "version", 0)) != VERSION:
		return
	seen = bool(cf.get_value(SECTION, "seen", false))
	completed = bool(cf.get_value(SECTION, "completed", false))
	for id in HINTS:
		hints[id] = bool(cf.get_value(SECTION, "hint_" + id, false))

func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "version", VERSION)
	cf.set_value(SECTION, "seen", seen)
	cf.set_value(SECTION, "completed", completed)
	for id in HINTS:
		cf.set_value(SECTION, "hint_" + id, bool(hints.get(id, false)))
	cf.save(path)

func mark_seen() -> void:
	seen = true
	save()

func mark_completed() -> void:
	completed = true
	seen = true
	save()

func hint_done(id: String) -> bool:
	return bool(hints.get(id, false))

func mark_hint(id: String) -> void:
	if hints.has(id):
		hints[id] = true
		save()

func reset() -> void:
	seen = false
	completed = false
	for id in HINTS:
		hints[id] = false
	save()
```

- [ ] **Step 4: 运行测试，确认通过**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/ee/dev/gameDev/cambio-rouglike res://tests/verify_tutorial.tscn
```

Expected: `=== TUTORIAL RESULT: 8/8 passed ===`

- [ ] **Step 5: Commit（需用户授权）**

```bash
cd /Users/ee/dev/gameDev/cambio-rouglike
git add scripts/core/tutorial_progress.gd tests/verify_tutorial.gd tests/verify_tutorial.tscn
git commit -m "feat: add tutorial progress store"
```

---

### Task 2: 固定牌序与教学快照

**Files:**
- Create: `/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_steps.gd`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.gd`（新增 `_test_steps()` 并加入 `_run()`）

**Interfaces:**
- Consumes: `KongRules.card_value(rank) -> int`、`KongRules.display_name(card) -> String`、`GameState.Phase` 常量、`SettlementModel.build(players: Array) -> Dictionary`。
- Produces: `TutorialSteps.state_by_id(id: String) -> Dictionary`；`state_initial()/state_memorized()/state_ready_draw()/state_drawn()/state_replaced()/state_opponent_discard()/state_after_slap()/state_kongbaya()/state_game_over()`；`result_model() -> Dictionary`；常量 `PLAYER=0`、`OPPONENT=1`。

- [ ] **Step 1: 写失败测试**

在 `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.gd` 的 `_run()` 里加 `_test_steps()`，并追加：

```gdscript
func _test_steps() -> void:
	var initial: Dictionary = TutorialSteps.state_initial()
	_check("viewer=玩家", int(initial.viewer_id) == 0)
	_check("2 人桌", (initial.players as Array).size() == 2)
	_check("玩家下排可见 5", str(initial.players[0].slots[2].card.rank) == "5")
	_check("玩家下排可见 K", str(initial.players[0].slots[3].card.rank) == "K")
	_check("上排不可见", not initial.players[0].slots[0].has("card"))
	_check("对手牌不可见", not initial.players[1].slots[0].has("card"))

	var memorized: Dictionary = TutorialSteps.state_memorized()
	_check("记忆后下排盖回", not memorized.players[0].slots[2].has("card") and not memorized.players[0].slots[3].has("card"))

	var ready: Dictionary = TutorialSteps.state_ready_draw()
	_check("抽牌前无大牌", (ready.pending as Dictionary).is_empty())
	var drawn: Dictionary = TutorialSteps.state_drawn()
	_check("抽牌大牌=7", str(drawn.pending.rank) == "7")
	_check("抽牌后牌堆-1", int(drawn.draw_count) == int(initial.draw_count) - 1)

	var replaced: Dictionary = TutorialSteps.state_replaced()
	_check("替换后槽1有牌", not str(replaced.players[0].slots[1].card_id).is_empty())
	_check("弃牌顶=2", str(replaced.discard.rank) == "2")
	_check("弃牌后轮到对手", int(replaced.current_player) == 1)
	_check("替换开贴牌窗口", bool(replaced.slap_open))

	var opp: Dictionary = TutorialSteps.state_opponent_discard()
	_check("对手弃 5 → 弃牌顶=5", str(opp.discard.rank) == "5")
	_check("窗口跨到玩家回合", int(opp.current_player) == 0 and bool(opp.slap_open))

	var slapped: Dictionary = TutorialSteps.state_after_slap()
	_check("贴掉后玩家 3 张", int(slapped.players[0].count) == 3)
	_check("槽2 清空", str(slapped.players[0].slots[2].card_id).is_empty())
	_check("贴牌后窗口关闭", not bool(slapped.slap_open))

	var kong: Dictionary = TutorialSteps.state_kongbaya()
	_check("喊话者=玩家", int(kong.kong_caller) == 0)
	_check("喊话后轮到对手", int(kong.current_player) == 1)

	var over: Dictionary = TutorialSteps.state_game_over()
	_check("结算公开全部牌", over.players[0].slots[0].has("card") and over.players[1].slots[3].has("card"))
	var model: Dictionary = TutorialSteps.result_model()
	var last: Dictionary = model.rounds[model.rounds.size() - 1]
	_check("玩家总分 15", int(last.ranking[0].score) == 15)
	_check("玩家排名第一", int(last.ranking[0].id) == 0)
	_check("对手总分 26", int(last.ranking[1].score) == 26)

	_check("state_by_id 路由", str(TutorialSteps.state_by_id("drawn").pending.rank) == "7")
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/ee/dev/gameDev/cambio-rouglike res://tests/verify_tutorial.tscn
```

Expected: `TutorialSteps` 未定义。

- [ ] **Step 3: 实现**

`/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_steps.gd`：

```gdscript
class_name TutorialSteps
extends RefCounted
## 教程固定牌序与快照（与 HiddenInfo 同形状，纯数据、可复现）。
## 玩家 seat0 [9,2,5,K]（下排 5/K 开局可见）；对手 seat1 [4,5,7,J]（始终不可见）。

const PLAYER := 0
const OPPONENT := 1
const PLAYER_NAME := "你"
const OPPONENT_NAME := "阿岚"

const CARDS := {
	"p0": ["9", "♠"], "p1": ["2", "♥"], "p2": ["5", "♦"], "p3": ["K", "♣"],
	"p7": ["7", "♠"],
	"o0": ["4", "♣"], "o1": ["5", "♠"], "o2": ["7", "♥"], "o3": ["J", "♦"],
	"d2": ["2", "♥"], "d5": ["5", "♠"], "d2b": ["2", "♦"],
}

static func _card(id: String) -> Dictionary:
	var rs: Array = CARDS[id]
	var rank := str(rs[0])
	var d := {"id": id, "rank": rank, "suit": str(rs[1]), "value": KongRules.card_value(rank)}
	d["label"] = KongRules.display_name(d)
	return d

static func _slot(id: String, revealed := false) -> Dictionary:
	var s := {"card_id": id, "protected": false, "bomb": false}
	if revealed and not id.is_empty():
		s["card"] = _card(id)
	return s

static func _empty_slot() -> Dictionary:
	return {"card_id": "", "protected": false, "bomb": false}

static func _player(seat: int, name: String, slots: Array) -> Dictionary:
	var count := 0
	for s in slots:
		if not str(s.get("card_id", "")).is_empty():
			count += 1
	return {"id": seat, "name": name, "count": count, "health": 2, "color": "",
		"eliminated": false, "currency": 100, "relics": ["", "", ""], "ready": true, "slots": slots}

static func _state(phase: int, p_slots: Array, o_slots: Array, extra := {}) -> Dictionary:
	var st := {
		"viewer_id": PLAYER,
		"current_player": PLAYER,
		"phase": phase,
		"match_id": "tutorial",
		"match_number": 1,
		"draw_count": 44,
		"discard": {},
		"discard_count": 0,
		"discard_history": [],
		"pending": {},
		"slap_open": false,
		"kong_caller": -1,
		"offline_players": [],
		"run": {"match_limit": 5},
		"turn_effect": "none",
		"players": [_player(PLAYER, PLAYER_NAME, p_slots), _player(OPPONENT, OPPONENT_NAME, o_slots)],
	}
	for k in extra.keys():
		st[k] = extra[k]
	return st

static func _player_hand() -> Array:
	return [_slot("p0"), _slot("p1"), _slot("p2"), _slot("p3")]

static func _opponent_hand() -> Array:
	return [_slot("o0"), _slot("o1"), _slot("o2"), _slot("o3")]

static func state_initial() -> Dictionary:
	return _state(GameState.Phase.INITIAL_PEEK,
		[_slot("p0"), _slot("p1"), _slot("p2", true), _slot("p3", true)], _opponent_hand())

static func state_memorized() -> Dictionary:
	return _state(GameState.Phase.INITIAL_PEEK, _player_hand(), _opponent_hand())

static func state_ready_draw() -> Dictionary:
	return _state(GameState.Phase.TURN_DRAW, _player_hand(), _opponent_hand())

static func state_drawn() -> Dictionary:
	var pending := _card("p7")
	pending["source"] = "draw"
	return _state(GameState.Phase.TURN_DRAW, _player_hand(), _opponent_hand(),
		{"draw_count": 43, "pending": pending})

static func state_replaced() -> Dictionary:
	var slots := [_slot("p0"), _slot("p7"), _slot("p2"), _slot("p3")]
	return _state(GameState.Phase.TURN_DRAW, slots, _opponent_hand(), {
		"current_player": OPPONENT, "draw_count": 42,
		"discard": _card("d2"), "discard_count": 1, "discard_history": [_card("d2")],
		"slap_open": true,
	})

static func state_opponent_discard() -> Dictionary:
	var slots := [_slot("p0"), _slot("p7"), _slot("p2"), _slot("p3")]
	return _state(GameState.Phase.TURN_DRAW, slots, _opponent_hand(), {
		"current_player": PLAYER, "draw_count": 41,
		"discard": _card("d5"), "discard_count": 2,
		"discard_history": [_card("d2"), _card("d5")], "slap_open": true,
	})

static func state_after_slap() -> Dictionary:
	var slots := [_slot("p0"), _slot("p7"), _empty_slot(), _slot("p3")]
	return _state(GameState.Phase.TURN_DRAW, slots, _opponent_hand(), {
		"current_player": PLAYER, "draw_count": 41,
		"discard": _card("p2"), "discard_count": 3,
		"discard_history": [_card("d2"), _card("d5"), _card("p2")],
		"slap_open": false,
	})

static func state_kongbaya() -> Dictionary:
	var st := state_after_slap()
	st["kong_caller"] = PLAYER
	st["current_player"] = OPPONENT
	return st

static func state_game_over() -> Dictionary:
	var p := [_slot("p0", true), _slot("p7", true), _empty_slot(), _slot("p3", true)]
	var o := [_slot("o0", true), _slot("o1", true), _slot("o2", true), _slot("o3", true)]
	return _state(GameState.Phase.GAME_OVER, p, o, {
		"current_player": PLAYER, "draw_count": 41,
		"discard": _card("p2"), "discard_count": 3,
		"discard_history": [_card("d2"), _card("d5"), _card("p2")],
		"kong_caller": PLAYER,
	})

static func result_model() -> Dictionary:
	return SettlementModel.build(state_game_over().players)

static func state_by_id(id: String) -> Dictionary:
	match id:
		"initial": return state_initial()
		"memorized": return state_memorized()
		"ready_draw": return state_ready_draw()
		"drawn": return state_drawn()
		"replaced": return state_replaced()
		"opponent_discard": return state_opponent_discard()
		"after_slap": return state_after_slap()
		"kongbaya": return state_kongbaya()
		"game_over": return state_game_over()
	return state_initial()
```

- [ ] **Step 4: 运行测试，确认通过**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/ee/dev/gameDev/cambio-rouglike res://tests/verify_tutorial.tscn
```

Expected: 全部 PASS（进度 + 快照）。

- [ ] **Step 5: Commit（需用户授权）**

```bash
cd /Users/ee/dev/gameDev/cambio-rouglike
git add scripts/tutorial/tutorial_steps.gd tests/verify_tutorial.gd
git commit -m "feat: add tutorial fixed deck and state snapshots"
```

---

### Task 3: 文案 + 步骤机

**Files:**
- Create: `/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_text.gd`
- Create: `/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_controller.gd`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.gd`（新增 `_test_controller()`）

**Interfaces:**
- Consumes: `TutorialSteps`。
- Produces: `TutorialController.new()`、`step() -> Dictionary`、`step_id() -> String`、`mode() -> String`、`state() -> Dictionary`、`is_interact() -> bool`、`is_done() -> bool`、`advance() -> bool`、`pick(meta: Dictionary) -> Dictionary`、`action(id: String) -> Dictionary`、`skip_step()`、`restart()`；`TutorialText.title(id) -> String`、`body(id) -> String`。

- [ ] **Step 1: 写失败测试**

在 `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.gd` 的 `_run()` 里加 `_test_controller()`，并追加：

```gdscript
func _test_controller() -> void:
	var c := TutorialController.new()
	_check("初始步骤 intro", c.step_id() == "intro" and not c.is_interact())
	c.advance()
	_check("intro→memorize", c.step_id() == "memorize")
	c.advance()
	_check("memorize→draw", c.step_id() == "draw" and c.is_interact())
	var r_bad: Dictionary = c.pick({"kind": "discard"})
	_check("抽牌点弃牌堆被纠正", not bool(r_bad.ok) and c.step_id() == "draw")
	var r_draw: Dictionary = c.pick({"kind": "deck"})
	_check("抽牌点抽牌堆通过", bool(r_draw.ok) and c.step_id() == "replace")
	var r_no_arm: Dictionary = c.pick({"kind": "slot", "seat": 0, "slot": 1})
	_check("未点替换先点牌位被纠正", not bool(r_no_arm.ok) and c.step_id() == "replace")
	_check("点弃掉被纠正", not bool(c.action("discard").ok))
	var r_arm: Dictionary = c.action("replace")
	_check("点替换进入选牌", bool(r_arm.ok))
	_check("点错槽位被纠正", not bool(c.pick({"kind": "slot", "seat": 0, "slot": 0}).ok))
	var r_slot: Dictionary = c.pick({"kind": "slot", "seat": 0, "slot": 1})
	_check("替换成功→对手回合", bool(r_slot.ok) and c.step_id() == "opponent")
	c.advance()
	_check("对手→贴牌", c.step_id() == "slap")
	_check("贴错牌被纠正", not bool(c.pick({"kind": "slot", "seat": 0, "slot": 1}).ok))
	var r_slap: Dictionary = c.pick({"kind": "slot", "seat": 0, "slot": 2})
	_check("贴对→能力", bool(r_slap.ok) and c.step_id() == "abilities")
	c.advance()
	_check("能力→kongbaya", c.step_id() == "kongbaya")
	_check("先抽牌被纠正", not bool(c.pick({"kind": "deck"}).ok))
	var r_kong: Dictionary = c.pick({"kind": "hud", "action": "kongbaya"})
	_check("点铃铛通过→final", bool(r_kong.ok) and c.step_id() == "final")
	c.advance()
	_check("final→settle", c.step_id() == "settle")
	c.advance()
	_check("settle→summary", c.step_id() == "summary")
	c.advance()
	_check("summary 后完成", c.is_done())

	var c2 := TutorialController.new()
	c2.skip_step()
	_check("skip_step 前进一格", c2.step_id() == "memorize")
	c2.restart()
	_check("restart 回 intro", c2.step_id() == "intro" and not c2.is_done())
	_check("文本非空", TutorialText.title("draw") != "" and TutorialText.body("draw").contains("抽牌堆"))
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/ee/dev/gameDev/cambio-rouglike res://tests/verify_tutorial.tscn
```

Expected: `TutorialController` 未定义。

- [ ] **Step 3: 实现**

`/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_text.gd`：

```gdscript
class_name TutorialText
extends RefCounted
## 教学文案集中处（便于审校/本地化）。

const TITLES := {
	"intro": "开局与记忆",
	"memorize": "记住下排两张",
	"draw": "抽一张牌",
	"replace": "替换手牌",
	"opponent": "对手回合",
	"slap": "抢贴牌",
	"abilities": "特殊牌能力",
	"kongbaya": "喊 Kongbaya",
	"final": "最终轮",
	"settle": "结算",
	"summary": "要点回顾",
}

const BODIES := {
	"intro": "你的 4 张牌全程背面朝上，只能靠记忆。",
	"memorize": "记住下排两张。之后除了用能力，不会再给你看。",
	"draw": "轮到你。点抽牌堆拿一张牌。",
	"replace": "把这张牌换进手牌。点「替换」，再点高亮的牌位。",
	"opponent": "别人的回合你不能操作，但贴牌窗口里可以随时抢。",
	"slap": "弃牌堆顶是 5。你记得哪张背面牌是 5？点它！",
	"abilities": "7/8 看自己一张；9/10 看别人一张；J 盲换；Q 看了再决定。",
	"kongbaya": "觉得自己的分够低了？点铃铛喊 Kongbaya。",
	"final": "对手完成最后一次行动，随后进入结算贴牌窗口。",
	"settle": "低分获胜：第一 +40，中间 +10，垫底 0 且 −1 生命。",
	"summary": "记住：牌是背面的、低分获胜、弃牌就开抢贴窗口、想收手就喊 Kongbaya。",
}

const TOAST := {
	"draw_need_deck": "这次先点抽牌堆。弃牌顶也能拿，但只能用来替换。",
	"replace_need_arm": "先点「替换」，再选牌位。",
	"replace_need_target": "把这张牌换进高亮的那个位置。",
	"replace_wrong_action": "先学替换，弃牌和能力本章跳过。",
	"slap_wrong": "贴错罚抽 1 张，窗口继续，可以再试。",
	"slap_wrong_target": "看看弃牌堆顶是几，再点你记得的那张。",
	"kong_need_bell": "先别抽，试着喊 Kongbaya。",
}

const HINTS := {
	"initial_peek": "看下排两张，记住它们，之后不会再显示。",
	"first_turn": "点抽牌堆或弃牌堆顶。",
	"first_slap": "弃牌堆顶是 X，记得哪张是 X 就点它抢贴。",
	"first_shop": "货币可买遗物/道具卡；遗物只对持有者生效。",
	"first_settle": "低分获胜；垫底扣 1 生命。",
}

static func title(id: String) -> String:
	return str(TITLES.get(id, ""))

static func body(id: String) -> String:
	return str(BODIES.get(id, ""))

static func toast(id: String) -> String:
	return str(TOAST.get(id, ""))

static func hint(id: String) -> String:
	return str(HINTS.get(id, ""))
```

`/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_controller.gd`：

```gdscript
class_name TutorialController
extends RefCounted
## 教学步骤机：回放段 advance()，真操作段 pick()/action() 校验；含跳过/重来。

const STEPS := [
	{"id": "intro", "mode": "replay", "state": "initial"},
	{"id": "memorize", "mode": "replay", "state": "memorized"},
	{"id": "draw", "mode": "interact", "state": "ready_draw"},
	{"id": "replace", "mode": "interact", "state": "drawn"},
	{"id": "opponent", "mode": "replay", "state": "replaced"},
	{"id": "slap", "mode": "interact", "state": "opponent_discard"},
	{"id": "abilities", "mode": "replay", "state": "after_slap"},
	{"id": "kongbaya", "mode": "interact", "state": "after_slap"},
	{"id": "final", "mode": "replay", "state": "kongbaya"},
	{"id": "settle", "mode": "replay", "state": "game_over"},
	{"id": "summary", "mode": "replay", "state": "game_over"},
]

var step_index := 0
var _replace_armed := false

func step() -> Dictionary:
	if step_index >= STEPS.size():
		return STEPS[STEPS.size() - 1]
	return STEPS[step_index]

func step_id() -> String:
	return str(step().get("id", ""))

func mode() -> String:
	return str(step().get("mode", "replay"))

func is_interact() -> bool:
	return mode() == "interact"

func is_done() -> bool:
	return step_index >= STEPS.size()

func state() -> Dictionary:
	if is_done():
		return TutorialSteps.state_game_over()
	return TutorialSteps.state_by_id(str(step().get("state", "initial")))

func advance() -> bool:
	if is_done():
		return false
	if is_interact():
		return false
	step_index += 1
	_replace_armed = false
	return true

func skip_step() -> void:
	if is_done():
		return
	step_index += 1
	_replace_armed = false

func restart() -> void:
	step_index = 0
	_replace_armed = false

func action(id: String) -> Dictionary:
	if step_id() == "replace":
		if id == "replace":
			_replace_armed = true
			return {"ok": true, "message": ""}
		return {"ok": false, "message": TutorialText.toast("replace_wrong_action")}
	return {"ok": false, "message": ""}

func pick(meta: Dictionary) -> Dictionary:
	var kind := str(meta.get("kind", ""))
	match step_id():
		"draw":
			if kind == "deck":
				step_index += 1
				return {"ok": true, "message": ""}
			if kind == "discard":
				return {"ok": false, "message": TutorialText.toast("draw_need_deck")}
		"replace":
			if kind == "slot":
				if not _replace_armed:
					return {"ok": false, "message": TutorialText.toast("replace_need_arm")}
				if int(meta.get("seat", -1)) == TutorialSteps.PLAYER and int(meta.get("slot", -1)) == 1:
					step_index += 1
					_replace_armed = false
					return {"ok": true, "message": ""}
				return {"ok": false, "message": TutorialText.toast("replace_need_target")}
			if kind == "deck" or kind == "discard":
				return {"ok": false, "message": TutorialText.toast("replace_wrong_action")}
		"slap":
			if kind == "slot":
				if int(meta.get("seat", -1)) == TutorialSteps.PLAYER and int(meta.get("slot", -1)) == 2:
					step_index += 1
					return {"ok": true, "message": ""}
				return {"ok": false, "message": TutorialText.toast("slap_wrong")}
			return {"ok": false, "message": TutorialText.toast("slap_wrong_target")}
		"kongbaya":
			if kind == "hud" and str(meta.get("action", "")) == "kongbaya":
				step_index += 1
				return {"ok": true, "message": ""}
			if kind == "deck":
				return {"ok": false, "message": TutorialText.toast("kong_need_bell")}
	return {"ok": false, "message": ""}
```

- [ ] **Step 4: 运行测试，确认通过**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/ee/dev/gameDev/cambio-rouglike res://tests/verify_tutorial.tscn
```

Expected: 全部 PASS。

- [ ] **Step 5: Commit（需用户授权）**

```bash
cd /Users/ee/dev/gameDev/cambio-rouglike
git add scripts/tutorial/tutorial_text.gd scripts/tutorial/tutorial_controller.gd tests/verify_tutorial.gd
git commit -m "feat: add tutorial step machine and copy"
```

---

### Task 4: 教学场景（3D + 引导层 + 结算）

**Files:**
- Create: `/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_overlay.gd`
- Create: `/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_view.gd`
- Create: `/Users/ee/dev/gameDev/cambio-rouglike/scenes/tutorial/tutorial_3d.tscn`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.gd`（新增 `_test_view()`）

**Interfaces:**
- Consumes: `TutorialController`、`TutorialText`、`TutorialSteps`、`table3d.tscn`（`Table3dView`）、`Table3dPicker.pick(cam, world, screen_pos)`、`SettlementPage.setup(...)`。
- Produces: `TutorialView`（`Control`）：`closed` 信号；`controller: TutorialController`；`_refresh()`；`handle_action(id)`；`handle_pick(meta)`；`finish_skip()`。

- [ ] **Step 1: 写失败测试**

在 `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.gd` 的 `_run()` 里加 `await _test_view()`，并追加：

```gdscript
func _test_view() -> void:
	var view = load("res://scenes/tutorial/tutorial_3d.tscn").instantiate()
	var completed := [false]
	view.completed.connect(func(): completed[0] = true)
	add_child(view)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("教学场景有 3D 桌", view.get_node_or_null("Table3D") != null)
	_check("教学场景有引导层", view.get_node_or_null("Overlay") != null)
	_check("初始步骤 intro", view.controller.step_id() == "intro")
	view.handle_continue()
	await get_tree().process_frame
	_check("继续→memorize", view.controller.step_id() == "memorize")
	view.handle_continue()
	_check("继续→draw", view.controller.step_id() == "draw")
	view.handle_pick({"kind": "deck"})
	_check("点抽牌堆→replace", view.controller.step_id() == "replace")
	view.handle_action("replace")
	view.handle_pick({"kind": "slot", "seat": 0, "slot": 1})
	_check("替换→opponent", view.controller.step_id() == "opponent")
	view.handle_continue()
	_check("opponent→slap", view.controller.step_id() == "slap")
	view.handle_pick({"kind": "slot", "seat": 0, "slot": 2})
	_check("贴牌→abilities", view.controller.step_id() == "abilities")
	view.handle_continue()
	_check("abilities→kongbaya", view.controller.step_id() == "kongbaya")
	view.handle_pick({"kind": "hud", "action": "kongbaya"})
	_check("hud→final", view.controller.step_id() == "final")
	view.handle_continue()
	view.handle_continue()
	_check("进入 summary", view.controller.step_id() == "summary")
	_check("summary 发 completed", completed[0])
	view.finish_skip()
	_check("finish_skip 发 closed", view.skip_requested)
	view.queue_free()
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/ee/dev/gameDev/cambio-rouglike res://tests/verify_tutorial.tscn
```

Expected: 场景加载失败/`TutorialView` 未定义。

- [ ] **Step 3: 实现**

`/Users/ee/dev/gameDev/cambio-rouglike/scenes/tutorial/tutorial_3d.tscn`：

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/tutorial/tutorial_view.gd" id="1"]

[node name="Tutorial3D" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")
```

`/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_overlay.gd`：

```gdscript
class_name TutorialOverlay
extends Control
## 教学引导层：顶部进度 + 提示卡 + 动作按钮 + 继续 + 纠错 toast + 角落菜单 + 总结页。

signal action_pressed(id: String)
signal continue_pressed
signal skip_step_pressed
signal skip_all_pressed
signal restart_pressed
signal exit_pressed

var _title: Label
var _progress: Label
var _body: Label
var _toast: Label
var _continue_btn: Button
var _actions: HBoxContainer
var _menu: VBoxContainer
var _skip_step_btn: Button
var _skip_all_btn: Button
var _toast_timer := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func _build() -> void:
	var top := PanelContainer.new()
	top.name = "TopCard"
	top.position = Vector2(24, 20)
	top.custom_minimum_size = Vector2(520, 0)
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.05, 0.06, 0.09, 0.82)
	ts.set_corner_radius_all(12)
	ts.set_content_margin_all(14)
	top.add_theme_stylebox_override("panel", ts)
	add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	tv.add_child(_title)
	_progress = Label.new()
	_progress.add_theme_font_size_override("font_size", 12)
	_progress.modulate = Color(1, 1, 1, 0.7)
	tv.add_child(_progress)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(520, 0)
	_body.add_theme_font_size_override("font_size", 16)
	tv.add_child(_body)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	tv.add_child(_actions)
	for pair in [["replace", "替换"], ["discard", "弃掉"], ["ability", "使用能力"]]:
		var b := Button.new()
		b.text = str(pair[1])
		b.custom_minimum_size = Vector2(120, 44)
		b.pressed.connect(func(): action_pressed.emit(str(pair[0])))
		_actions.add_child(b)
	var bottom := HBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("separation", 10)
	add_child(bottom)
	_continue_btn = Button.new()
	_continue_btn.text = "▶ 继续（Enter）"
	_continue_btn.custom_minimum_size = Vector2(180, 44)
	_continue_btn.pressed.connect(func(): continue_pressed.emit())
	bottom.add_child(_continue_btn)
	_skip_step_btn = Button.new()
	_skip_step_btn.text = "跳过本步"
	_skip_step_btn.pressed.connect(func(): skip_step_pressed.emit())
	bottom.add_child(_skip_step_btn)
	var restart := Button.new()
	restart.text = "再练一次"
	restart.pressed.connect(func(): restart_pressed.emit())
	bottom.add_child(restart)
	_skip_all_btn = Button.new()
	_skip_all_btn.text = "跳过教程"
	_skip_all_btn.pressed.connect(func(): skip_all_pressed.emit())
	bottom.add_child(_skip_all_btn)
	var exit_btn := Button.new()
	exit_btn.text = "返回主菜单"
	exit_btn.pressed.connect(func(): exit_pressed.emit())
	bottom.add_child(exit_btn)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-220, 250)
	_toast.custom_minimum_size = Vector2(440, 0)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", Color("ff7b7b"))
	_toast.visible = false
	add_child(_toast)
	_menu = VBoxContainer.new()
	_menu.visible = false
	add_child(_menu)

func set_step(title: String, progress: String, body: String, is_interact: bool, step_id: String) -> void:
	_title.text = title
	_progress.text = progress
	_body.text = body
	_continue_btn.visible = not is_interact and step_id != "summary"
	_actions.visible = step_id == "replace"
	_skip_step_btn.visible = step_id != "summary"
	_skip_all_btn.text = "开始第一局" if step_id == "summary" else "跳过教程"

func show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast_timer = 2.6

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast.visible = false
```

`/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_view.gd`：

```gdscript
class_name TutorialView
extends Control
## 3D 教学局：固定镜头 + 鼠标指针点击；本地时间线，不接网络/GameState。

signal closed
signal completed
var skip_requested := false

const TABLE3D_SCENE := "res://scenes/ui/table3d.tscn"
const SETTLEMENT_SCENE := "res://scenes/ui/settlement_page.tscn"

var controller := TutorialController.new()
var _table3d: Node3D
var _overlay: TutorialOverlay
var _settlement: Control
var _confirm: ConfirmationDialog
var _completed_emitted := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_table3d = load(TABLE3D_SCENE).instantiate()
	_table3d.name = "Table3D"
	add_child(_table3d)
	_table3d.set_active(true)
	_overlay = TutorialOverlay.new()
	_overlay.name = "Overlay"
	_overlay.action_pressed.connect(handle_action)
	_overlay.continue_pressed.connect(handle_continue)
	_overlay.skip_step_pressed.connect(_skip_step)
	_overlay.skip_all_pressed.connect(finish_skip)
	_overlay.restart_pressed.connect(_restart)
	_overlay.exit_pressed.connect(func(): closed.emit())
	add_child(_overlay)
	_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
			handle_continue()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_ensure_confirm()
			_confirm.popup_centered()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if get_viewport().gui_get_hovered_control() != null:
			return
		handle_pick(_pick_at_mouse())
		get_viewport().set_input_as_handled()

func _pick_at_mouse() -> Dictionary:
	if _table3d == null or _table3d.camera == null:
		return {}
	var cam: Camera3D = _table3d.camera.camera_node()
	if cam == null:
		return {}
	return Table3dPicker.pick(cam, _table3d.get_world_3d(), get_viewport().get_mouse_position())

func handle_continue() -> void:
	if controller.is_interact():
		return
	controller.advance()
	_refresh()

func handle_action(id: String) -> void:
	var r: Dictionary = controller.action(id)
	if not bool(r.get("ok", false)):
		_overlay.show_toast(str(r.get("message", "")))
	_refresh()

func handle_pick(meta: Dictionary) -> void:
	var r: Dictionary = controller.pick(meta)
	if not bool(r.get("ok", false)) and not str(r.get("message", "")).is_empty():
		_overlay.show_toast(str(r.get("message", "")))
	_refresh()

func _skip_step() -> void:
	controller.skip_step()
	_refresh()

func _restart() -> void:
	controller.restart()
	if _settlement != null and is_instance_valid(_settlement):
		_settlement.queue_free()
		_settlement = null
	_refresh()

func finish_skip() -> void:
	skip_requested = true
	closed.emit()

func _ensure_confirm() -> void:
	if _confirm != null and is_instance_valid(_confirm):
		return
	_confirm = ConfirmationDialog.new()
	_confirm.title = "跳过教程"
	_confirm.dialog_text = "确定要跳过新手教程吗？"
	_confirm.confirmed.connect(finish_skip)
	add_child(_confirm)

func _refresh() -> void:
	if _settlement != null and is_instance_valid(_settlement) and controller.step_id() != "settle":
		_settlement.queue_free()
		_settlement = null
	var st: Dictionary = controller.state()
	_table3d.render(st, _actionable_for_step(), false)
	if controller.step_id() == "settle":
		_show_settlement()
	if controller.step_id() == "summary" and not _completed_emitted:
		_completed_emitted = true
		completed.emit()
	var total := TutorialController.STEPS.size()
	_overlay.set_step(
		TutorialText.title(controller.step_id()),
		"%d / %d" % [mini(controller.step_index + 1, total), total],
		TutorialText.body(controller.step_id()),
		controller.is_interact(),
		controller.step_id()
	)

func _actionable_for_step() -> Callable:
	var id := controller.step_id()
	if id == "replace":
		return func(seat: int, slot: int) -> bool: return seat == 0 and slot == 1
	if id == "slap":
		return func(seat: int, slot: int) -> bool: return seat == 0 and slot == 2
	return func(_seat: int, _slot: int) -> bool: return false

func _show_settlement() -> void:
	if _settlement != null and is_instance_valid(_settlement):
		return
	_settlement = load(SETTLEMENT_SCENE).instantiate()
	_settlement.name = "TutorialSettlement"
	add_child(_settlement)
	var flip := func(seat: int, slot: int, card: Dictionary) -> void:
		_table3d.reveal_slot_settle(seat, slot, card)
	_settlement.setup(TutorialSteps.result_model(), false, 1,
		Callable(), Callable(), Callable(), flip)
	var footer := _settlement.get_node_or_null("Center/Panel/VBox/Footer")
	if footer != null:
		footer.visible = false
```

> 换牌/贴牌的飞牌动画：V1 只做状态切换（卡牌直接落位），不阻塞流程；`Table3dView.animate_exchange` 的 `replace`/`slap_*` 可作为后续增强（传入 `actor/slot/old_data/big_data`）。抽牌飞牌由 `Table3dView._detect_draw` 在 `pending` 空→非空时自动播放。

- [ ] **Step 4: 运行测试，确认通过**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/ee/dev/gameDev/cambio-rouglike res://tests/verify_tutorial.tscn
```

Expected: 视图测试 PASS。若 `table3d.tscn` 在 headless 下需要额外一帧，测试里已有两帧等待。

- [ ] **Step 5: Commit（需用户授权）**

```bash
cd /Users/ee/dev/gameDev/cambio-rouglike
git add scripts/tutorial/tutorial_overlay.gd scripts/tutorial/tutorial_view.gd scenes/tutorial/tutorial_3d.tscn tests/verify_tutorial.gd
git commit -m "feat: add 3D tutorial scene and overlay"
```

---

### Task 5: 主菜单入口 + 打开/关闭 + 首局轻提示

**Files:**
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/scripts/ui/lobby_view.gd`（`_build_menu_wide` 与 `_build_menu_compact` 加按钮）
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/scripts/ui/main.gd`（变量、`_open_tutorial`/`_close_tutorial`、输入门控、首局提示）
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/scripts/tutorial/tutorial_text.gd`（补 `HINTS` 字典与 `hint(id)`，Task 3 已建文件）
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.gd`（新增 `_test_main_integration()`）

**Interfaces:**
- Consumes: `TutorialProgress`、`TutorialView`（`scenes/tutorial/tutorial_3d.tscn`）。
- Produces: `Main._open_tutorial() -> void`、`Main._close_tutorial() -> void`、`Main._maybe_first_hint(id: String) -> bool`、`Main.tutorial_active: bool`、`Main.tutorial_progress: TutorialProgress`。

- [ ] **Step 1: 写失败测试**

在 `/Users/ee/dev/gameDev/cambio-rouglike/tests/verify_tutorial.gd` 的 `_run()` 里加 `await _test_main_integration()`，并追加：

```gdscript
func _test_main_integration() -> void:
	var tp := "user://test_tutorial_main.cfg"
	DirAccess.remove_absolute(tp)
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.tutorial_progress = TutorialProgress.new(tp)
	main.tutorial_progress.load()
	main.tutorial_progress.reset()
	main._open_tutorial()
	await get_tree().process_frame
	_check("教程已打开", main.tutorial_active)
	_check("教程场景挂载", main.get_node_or_null("Tutorial3D") != null)
	_check("大厅隐藏", not main.lobby_root.visible)
	_check("mark_seen 已写", main.tutorial_progress.seen)
	_check("首局提示弹出", main._maybe_first_hint("first_slap"))
	_check("提示 HUD 可见", main._tip_hud != null and main._tip_hud.visible)
	_check("首局提示只弹一次", not main._maybe_first_hint("first_slap"))
	main._close_tutorial()
	await get_tree().process_frame
	_check("教程关闭", not main.tutorial_active and main.get_node_or_null("Tutorial3D") == null)
	_check("大厅恢复", main.lobby_root.visible)
	DirAccess.remove_absolute(tp)
	main.queue_free()
```

> 注意：`_maybe_first_hint` 返回 `bool`，测试中的 `await` 仅用于让 toast 有时间创建；若实现为同步函数，可直接调用。

- [ ] **Step 2: 运行测试，确认失败**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/ee/dev/gameDev/cambio-rouglike res://tests/verify_tutorial.tscn
```

Expected: `_open_tutorial` 不存在。

- [ ] **Step 3: 实现**

在 `/Users/ee/dev/gameDev/cambio-rouglike/scripts/ui/lobby_view.gd` 的宽屏 `_build_menu_wide()` 中，`lv.add_child(host)` 之后加：

```gdscript
	var tutorial: Button = main._button("新手教程")
	tutorial.name = "TutorialButton"
	tutorial.custom_minimum_size = Vector2(0, 48)
	tutorial.tooltip_text = "3 分钟学会基础牌局"
	tutorial.pressed.connect(main._open_tutorial)
	_apply_secondary_style(tutorial)
	if not main.tutorial_progress.seen:
		tutorial.text = "★ 新手教程（推荐先玩）"
	lv.add_child(tutorial)
```

在紧凑 `_build_menu_compact()` 中，`_menu_box.add_child(host)` 之后加同样的按钮（`_menu_box.add_child(tutorial)`）。

在 `/Users/ee/dev/gameDev/cambio-rouglike/scripts/ui/main.gd`：

1. 顶部常量区加：

```gdscript
const TutorialViewScene := preload("res://scenes/tutorial/tutorial_3d.tscn")
```

2. 成员变量区加：

```gdscript
var tutorial_active := false
var tutorial_view: Control = null
var tutorial_progress: TutorialProgress
var _tip_hud: Label = null
var _tip_timer: SceneTreeTimer = null
```

3. `_ready()` 里 `keybinds.load()` 之后加：

```gdscript
	tutorial_progress = TutorialProgress.new()
	tutorial_progress.load()
```

4. `_input(event)` 第一行加：

```gdscript
	if tutorial_active:
		return
```

5. `_unhandled_input(event)` 第一行加：

```gdscript
	if tutorial_active:
		return
```

6. `_notification()` 的 `NOTIFICATION_WM_CLOSE_REQUEST` 分支开头加：

```gdscript
		if tutorial_active:
			_close_tutorial()
			return
```

7. 新增方法（放在 `_toggle_table3d` 附近）：

```gdscript
func _open_tutorial() -> void:
	if tutorial_active:
		return
	if _in_room():
		_leave_to_main_menu()
	tutorial_active = true
	tutorial_progress.mark_seen()
	if lobby_root != null:
		lobby_root.visible = false
	if lobby_bg != null:
		lobby_bg.visible = false
	_set_table3d(false)
	if background != null:
		background.visible = false
	game_panel.visible = false
	tutorial_view = TutorialViewScene.instantiate()
	tutorial_view.name = "Tutorial3D"
	add_child(tutorial_view)
	tutorial_view.closed.connect(_close_tutorial)
	tutorial_view.completed.connect(func(): tutorial_progress.mark_completed())

func _close_tutorial() -> void:
	if tutorial_view != null and is_instance_valid(tutorial_view):
		tutorial_view.queue_free()
	tutorial_view = null
	tutorial_active = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if lobby_root != null:
		lobby_root.visible = true
	if lobby_bg != null:
		lobby_bg.visible = true
	if background != null:
		background.visible = true
	game_panel.visible = false

## 首局轻提示：每个 id 只弹一次；返回是否真的弹出。
func _maybe_first_hint(id: String) -> bool:
	if tutorial_progress == null or tutorial_progress.hint_done(id):
		return false
	tutorial_progress.mark_hint(id)
	var text := TutorialText.hint(id)
	if id == "first_slap":
		var top_rank := str((latest_state.get("discard", {}) as Dictionary).get("rank", "?"))
		text = text.replace("X", top_rank)
	_show_tip(text)
	return true

## 屏幕顶部轻提示（2D/3D 通用，不锁操作）。复用同一个 Label，4s 自动隐藏。
func _show_tip(text: String, seconds := 4.0) -> void:
	if _tip_hud == null or not is_instance_valid(_tip_hud):
		_tip_hud = Label.new()
		_tip_hud.name = "TipHud"
		_tip_hud.z_index = 90
		_tip_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_tip_hud.position = Vector2(-260, 96)
		_tip_hud.custom_minimum_size = Vector2(520, 0)
		_tip_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tip_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tip_hud.add_theme_font_size_override("font_size", 16)
		_tip_hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.94))
		add_child(_tip_hud)
	_tip_hud.text = text
	_tip_hud.visible = true
	if _tip_timer != null and _tip_timer.timeout.is_connected(_hide_tip):
		_tip_timer.timeout.disconnect(_hide_tip)
	_tip_timer = get_tree().create_timer(seconds)
	_tip_timer.timeout.connect(_hide_tip)

func _hide_tip() -> void:
	if _tip_hud != null and is_instance_valid(_tip_hud):
		_tip_hud.visible = false
```

8. 首局提示接线（在 `_on_state_updated` 或 `_render_game` 中已有的状态分支里，选一处只加调用，不改原逻辑）：

```gdscript
	# 首局轻提示（每个只一次）
	if int(latest_state.get("phase", 0)) == PHASE_INITIAL_PEEK:
		_maybe_first_hint("initial_peek")
	elif int(latest_state.get("phase", 0)) == PHASE_TURN_DRAW \
			and int(latest_state.get("current_player", -1)) == int(latest_state.get("viewer_id", -1)):
		_maybe_first_hint("first_turn")
	if bool(latest_state.get("slap_open", false)):
		_maybe_first_hint("first_slap")
	if int(latest_state.get("phase", 0)) == PHASE_SHOP:
		_maybe_first_hint("first_shop")
	if int(latest_state.get("phase", 0)) == PHASE_GAME_OVER:
		_maybe_first_hint("first_settle")
```

> 放在 `_on_state_updated` 函数体末尾即可；`_show_toast` 已存在。若 `_show_toast` 签名不是 `(text: String)`，按实际签名调整（现有 `GameState.toast_received.connect(_show_toast)` 说明它接受一个字符串/字典，见 `main.gd` 实际定义）。

- [ ] **Step 4: 运行测试，确认通过**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/ee/dev/gameDev/cambio-rouglike res://tests/verify_tutorial.tscn
```

Expected: 主菜单集成 PASS。

- [ ] **Step 5: 运行大厅回归（防止主菜单改动破坏布局）**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/ee/dev/gameDev/cambio-rouglike res://tests/verify_lobby.tscn
```

Expected: `=== LOBBY RESULT: ... passed ===` 全过。

- [ ] **Step 6: Commit（需用户授权）**

```bash
cd /Users/ee/dev/gameDev/cambio-rouglike
git add scripts/ui/lobby_view.gd scripts/ui/main.gd tests/verify_tutorial.gd
git commit -m "feat: add tutorial entry and first-match hints"
```

---

### Task 6: 注册测试 + 文档 + 全量回归

**Files:**
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/tools/run_all_tests.sh`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/docs/AI_AGENT_交接说明.md`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/docs/功能实现文档.md`
- Modify: `/Users/ee/dev/gameDev/cambio-rouglike/docs/修改日志.md`（gitignore，追加即可，不提交）

**Interfaces:**
- Consumes: `verify_tutorial.tscn`。

- [ ] **Step 1: 注册测试**

在 `tools/run_all_tests.sh` 的 `run_single "card_tilt" ...` 之后加：

```bash
run_single "tutorial"   res://tests/verify_tutorial.tscn
```

- [ ] **Step 2: 运行 quick 全量回归**

```bash
/Users/ee/dev/gameDev/cambio-rouglike/tools/run_all_tests.sh --quick
```

Expected: 无 FAIL；`tutorial` 行 PASS。

- [ ] **Step 3: 更新交接文档**

在 `/Users/ee/dev/gameDev/cambio-rouglike/docs/AI_AGENT_交接说明.md` 第 2 节基线列表追加一条：

```markdown
- **新手教程（2026-11-08，纯客户端本地时间线）**：主菜单「新手教程」→ `scenes/tutorial/tutorial_3d.tscn`（固定镜头 + 鼠标指针，2 人桌，预置回放 + 抽牌/替换/抢贴/Kongbaya 4 个真操作点）；`TutorialProgress` 持久化 `user://tutorial.cfg`；首局 5 条一次性轻提示。不改 `GameState`/协议/快照；测试 `verify_tutorial`。
```

在 `/Users/ee/dev/gameDev/cambio-rouglike/docs/功能实现文档.md` 的文件树中补 6 个新文件（`scripts/tutorial/*`、`scenes/tutorial/tutorial_3d.tscn`、`scripts/core/tutorial_progress.gd`）。

- [ ] **Step 4: 追加修改日志（不提交）**

在 `/Users/ee/dev/gameDev/cambio-rouglike/docs/修改日志.md` 追加本次 request → 实现 → 验证记录。

- [ ] **Step 5: Commit（需用户授权）**

```bash
cd /Users/ee/dev/gameDev/cambio-rouglike
git add tools/run_all_tests.sh docs/AI_AGENT_交接说明.md docs/功能实现文档.md
git commit -m "docs: register tutorial test and document onboarding"
```

---

## 人工验收（不启动自动化 GUI）

1. 主菜单点「新手教程」→ 3D 教学局出现，鼠标可见、镜头固定。
2. 第 0/1 章能看到下排 `5`/`K` 翻开 2 秒后盖回。
3. 抽牌步：点抽牌堆通过，点弃牌堆出现红色纠正；抽到大牌 `7`。
4. 替换步：点「替换」后槽 1 高亮，点对后大牌飞入弃牌堆。
5. 对手回合后弃牌顶为 `5`；贴牌步点槽 2 的 `5` 通过，点错出现罚牌 + 纠正。
6. 铃铛步点铃铛通过，点抽牌堆出现纠正。
7. 结算页出现且玩家第一（15 vs 26）；总结页三个出口可用。
8. 跳过本步/重新开始/跳过教程/返回主菜单都不卡死。
9. 首次进入真对局各触发一次轻提示，第二次不再出现。

## Self-Review

- **Spec coverage**：入口/章节/4 个动手点/纠错/跳过重来/首局提示/验收均有任务对应；§5 第 5 章能力蒙太奇落在 `state_after_slap` 与 `abilities` 步骤；结算复用 `SettlementPage`（Task 4）。
- **Placeholder scan**：无 TBD/TODO；所有代码步骤都给了可落地片段。
- **Type consistency**：`TutorialController.STEPS` 的 id/state 与 `TutorialSteps.state_by_id` 一致；`handle_continue/handle_pick/handle_action/finish_skip` 在测试与实现中同名；`TutorialProgress.HINTS` 的 5 个 id 与 Task 5 的调用一致。
