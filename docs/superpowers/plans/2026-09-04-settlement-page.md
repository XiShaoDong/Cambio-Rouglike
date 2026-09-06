# 结算页面 + 算分动画 + 再来一局 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 GAME_OVER 时弹出居中的结算弹层，播放 Balatro 式同步轮算分动画（每轮全员同时翻一张牌、累计分实时累加、排名表整行上移/下移实时重排）、冠军特效（名字金色脉冲光环 + ★ 徽章 + 胜利音效），并新增「再来一局」流程（房主一键开新局，无需回大厅）。

**Architecture:** 纯客户端结算弹层（`settlement_page.gd`，代码构建仿 `settings_menu`/`duel_bar`）+ 纯计算模型（`settlement_model.gd`，同步轮记分，headless 可测）+ 1 个新服务器 RPC（`request_next_match`/`server_next_match`，从 GAME_OVER 重发一局）。GAME_OVER 快照已公开全部牌面与 ranking，结算页零协议新数据；「再来一局」只做回合重置与发牌复用。保持 `GameState` 服务器权威与私有快照不变量不变。

**Tech Stack:** Godot 4.6 / GDScript / ENet（`multiplayer` RPC）/ `create_tween` 动画 / headless 单元测试（`--headless --path . res://tests/*.tscn`）。

## Global Constraints

- 项目路径：`~/dev/gameDev/Cambio-rouglike/`；分支 `tab-winner`。
- 验证命令一律 headless，不启动 GUI：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . ...`。
- `GameState` 服务器权威：客户端只能调 `request_*`；服务器在 `_server_*` 校验调用者/阶段。
- 玩家身份一律 `seat_id`（0..N-1），`peer_id` 只是瞬态连接；`kong_caller` 哨兵为 `-1`。
- `KongRules.HAND_SIZE = 4`（每人初始 4 张），`MAX_HAND_CARDS = 6`；`card_value`：A=1、J/Q=10、K=-1、2-10=其数字（得分可为负，低分胜）。
- 排序低分在前 = 冠军（复用 `ScoreSystem._is_lower_score`，总分→牌数→从小到大逐张比→id 兜底）。
- UI 代码构建（不用 .tscn 编辑器布局动态层）；弹窗 `_build_ui` 开头 `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`（防 B9）。
- 改动规则前更新 `docs/KONG_开发文档.md`；改协议前更新 `docs/网络协议_V1.md`。
- 提交分类 `feat:`/`fix:`/`doc:`；用户每次 request 结束向 `docs/修改日志.md`（gitignore）追加记录。

---

### Task 1: 结算模型 `settlement_model.gd`（同步轮记分）

**Files:**
- Create: `scripts/core/settlement_model.gd`
- Create: `tests/verify_settlement.gd`
- Create: `tests/verify_settlement.tscn`

**Interfaces:**
- Consumes: `ScoreSystem._is_lower_score(a: Dictionary, b: Dictionary) -> bool`（`scripts/core/score_system.gd`，已有）；快照 `players` 数组形状 `{id, name, count, health, ready, slots: [{card_id, card: {id, rank, suit, value, label}}]}`（`HiddenInfo._player_snapshot`，GAME_OVER 时 `reveal_all=true`，`card` 恒在）。
- Produces: `SettlementModel.build(players: Array) -> Dictionary`，返回 `{layout_order: Array[int], rounds: Array[Dictionary]}`，其中每轮 `round = {slot: int, flips: Array[Dictionary], ranking: Array[Dictionary]}`，`flip = {seat: int, value: int, rank: String, suit: String, total: int}`（total = 翻完该张后的累计分），`ranking` 条目 = `{id, name, score, count, values}`（values 为已翻牌值**升序**，供 `_is_lower_score` 比较）。

- [ ] **Step 1: 写失败测试 `tests/verify_settlement.gd`（模型部分）**

```gdscript
extends Node

var failures := 0
var checks := 0

func _ready() -> void:
	await _test_model_even()
	await _test_model_uneven()
	await _test_model_final_matches_score_system()
	print("=== SETTLEMENT RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[FAIL] " + name)
	else:
		print("[PASS] " + name)

## 手工构造 GAME_OVER 快照 players（等长手牌）。
func _players_even() -> Array:
	return [
		{"id": 0, "name": "A", "count": 2, "slots": [
			{"card_id": "a0", "card": {"rank": "7", "suit": "♠", "value": 7, "label": "7♠"}},
			{"card_id": "a1", "card": {"rank": "7", "suit": "♥", "value": 7, "label": "7♥"}}]},
		{"id": 1, "name": "B", "count": 2, "slots": [
			{"card_id": "b0", "card": {"rank": "2", "suit": "♠", "value": 2, "label": "2♠"}},
			{"card_id": "b1", "card": {"rank": "10", "suit": "♠", "value": 10, "label": "10♠"}}]},
		{"id": 2, "name": "C", "count": 2, "slots": [
			{"card_id": "c0", "card": {"rank": "5", "suit": "♠", "value": 5, "label": "5♠"}},
			{"card_id": "c1", "card": {"rank": "K", "suit": "♠", "value": -1, "label": "K♠"}}]},
	]

func _test_model_even() -> void:
	var model: Dictionary = SettlementModel.build(_players_even())
	_check("layout_order=座位顺序[0,1,2]", model.layout_order == [0, 1, 2])
	_check("轮数=最大手牌数=2", model.rounds.size() == 2)
	var r0: Dictionary = model.rounds[0]
	_check("第0轮 flips 顺序=玩家数组顺序", r0.flips[0].seat == 0 and r0.flips[1].seat == 1 and r0.flips[2].seat == 2)
	_check("第0轮每人 total=自身值", r0.flips[0].total == 7 and r0.flips[1].total == 2 and r0.flips[2].total == 5)
	_check("第0轮排名按累计分升序 B,C,A", [r0.ranking[0].id, r0.ranking[1].id, r0.ranking[2].id] == [1, 2, 0])
	var r1: Dictionary = model.rounds[1]
	_check("第1轮累计 A=14 B=12 C=4", r1.flips[0].total == 14 and r1.flips[1].total == 12 and r1.flips[2].total == 4)
	_check("第1轮排名 C,B,A", [r1.ranking[0].id, r1.ranking[1].id, r1.ranking[2].id] == [2, 1, 0])
	_check("冠军=最低分 C", r1.ranking[0].id == 2)

## 不等长手牌：A:[1,2] B:[1] C:[3,4,5]
func _players_uneven() -> Array:
	return [
		{"id": 0, "name": "A", "count": 2, "slots": [
			{"card_id": "a0", "card": {"rank": "A", "suit": "♠", "value": 1, "label": "A♠"}},
			{"card_id": "a1", "card": {"rank": "2", "suit": "♥", "value": 2, "label": "2♥"}}]},
		{"id": 1, "name": "B", "count": 1, "slots": [
			{"card_id": "b0", "card": {"rank": "A", "suit": "♣", "value": 1, "label": "A♣"}}]},
		{"id": 2, "name": "C", "count": 3, "slots": [
			{"card_id": "c0", "card": {"rank": "3", "suit": "♠", "value": 3, "label": "3♠"}},
			{"card_id": "c1", "card": {"rank": "4", "suit": "♠", "value": 4, "label": "4♠"}},
			{"card_id": "c2", "card": {"rank": "5", "suit": "♠", "value": 5, "label": "5♠"}}]},
	]

func _test_model_uneven() -> void:
	var model: Dictionary = SettlementModel.build(_players_uneven())
	_check("轮数=最大手牌数=3", model.rounds.size() == 3)
	_check("第1轮只有 A,C 翻牌（B 无第2张）", model.rounds[1].flips.size() == 2)
	_check("第2轮只有 C 翻牌", model.rounds[2].flips.size() == 1 and model.rounds[2].flips[0].seat == 2)
	_check("B 无牌轮总分保持不变", model.rounds[1].flips[0].total == 3 and model.rounds[1].flips[1].total == 7)
	_check("未翻牌玩家 total 不回退（B=1）", model.rounds[2].flips[0].total == 12)

## 最终轮排名应与 ScoreSystem.calculate_ranking 全量一致（同分 A/B 时 id 兜底）。
func _test_model_final_matches_score_system() -> void:
	var players: Array = _players_even()
	var model: Dictionary = SettlementModel.build(players)
	var final_ranking: Array = model.rounds[model.rounds.size() - 1].ranking
	var full: Array = []
	for player in players:
		var values: Array[int] = []
		for slot in player.slots:
			if slot.has("card"):
				values.append(int(slot.card.value))
		values.sort()
		var total := 0
		for v in values:
			total += v
		full.append({"id": int(player.id), "name": str(player.name), "score": total, "count": values.size(), "values": values})
	full.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return ScoreSystem._is_lower_score(a, b))
	var ids_full: Array = []
	for entry in full:
		ids_full.append(int(entry.id))
	var ids_final: Array = []
	for entry in final_ranking:
		ids_final.append(int(entry.id))
	_check("最终排名与 ScoreSystem 全量一致", ids_final == ids_full)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_settlement.tscn`
Expected: FAIL — "Identifier 'SettlementModel' not declared"（`verify_settlement.tscn` 与模型尚不存在）。

- [ ] **Step 3: 创建 `tests/verify_settlement.tscn`**

```
[gd_scene format=3 uid="uid://bsettlement0001"]

[ext_resource type="Script" path="res://tests/verify_settlement.gd" id="1"]

[node name="VerifySettlement" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 4: 实现 `scripts/core/settlement_model.gd`**

```gdscript
class_name SettlementModel
extends RefCounted
## 结算模型（同步轮记分，纯计算）
## 职责：把 GAME_OVER 快照 players 投影成结算页所需的同步轮算分序列。
## 每轮所有玩家一起翻开各自第 N 张牌，各自 running_total 累加，随后整表按累计分实时重排。
## 不依赖 Node，可 headless 单测。排序复用 ScoreSystem._is_lower_score（低分=冠军在前）。

## players: GAME_OVER 快照 players（已按 turn_order 排序，槽位 card 恒在）。
## 返回 {layout_order: 座位顺序(左上起顺时针=座位顺序), rounds: [...]}。
## round = {slot, flips: [{seat, value, rank, suit, total}], ranking: [{id,name,score,count,values}]}
## ranking.values 为已翻牌值升序（供 _is_lower_score 比较）。
static func build(players: Array) -> Dictionary:
	var layout_order: Array = []
	for player in players:
		layout_order.append(int(player.id))
	var max_slots := 0
	for player in players:
		max_slots = maxi(max_slots, int(player.slots.size()))
	var rounds: Array = []
	var totals: Dictionary = {}
	var revealed: Dictionary = {}
	for slot in max_slots:
		var flips: Array = []
		for player in players:
			var seat := int(player.id)
			var entry: Dictionary = player.slots[slot] if slot < player.slots.size() else {}
			if entry.has("card"):
				var value := int(entry.card.value)
				totals[seat] = int(totals.get(seat, 0)) + value
				revealed[seat] = (revealed.get(seat, []) as Array) + [value]
				flips.append({
					"seat": seat,
					"value": value,
					"rank": str(entry.card.rank),
					"suit": str(entry.card.suit),
					"total": int(totals[seat]),
				})
		rounds.append({"slot": slot, "flips": flips, "ranking": _ranking(players, totals, revealed)})
	return {"layout_order": layout_order, "rounds": rounds}

static func _ranking(players: Array, totals: Dictionary, revealed: Dictionary) -> Array:
	var entries: Array = []
	for player in players:
		var seat := int(player.id)
		var values: Array = (revealed.get(seat, []) as Array).duplicate()
		values.sort()
		entries.append({
			"id": seat,
			"name": str(player.name),
			"score": int(totals.get(seat, 0)),
			"count": values.size(),
			"values": values,
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return ScoreSystem._is_lower_score(a, b))
	return entries
```

- [ ] **Step 5: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_settlement.tscn`
Expected: PASS（约 13/13）。

- [ ] **Step 6: 提交**

```bash
git add scripts/core/settlement_model.gd tests/verify_settlement.gd tests/verify_settlement.tscn
git commit -m "feat: 结算模型（同步轮记分 rounds + ranking_states）"
```

---

### Task 2: 服务器「再来一局」RPC + `_deal_new_match` 抽取

**Files:**
- Modify: `scripts/core/game_state.gd`（`request_start_match`/`_server_start_match` 段 ~L348-380；新增 `request_next_match`/`server_next_match`/`_server_next_match`/`_deal_new_match`）
- Modify: `tests/verify_settlement.gd`（追加 `_test_next_match_*` 并在 `_ready` 调用）

**Interfaces:**
- Consumes: `_create_deck()`、`_draw_from_deck()`、`_new_match_id()`、`_reject(seat, code, action_id)`、`RejectCode`、`Phase`、`KongRules.HAND_SIZE/MIN_PLAYERS`（均已有）。
- Produces: `GameState.request_next_match(action_id: String)`（客户端入口）、`GameState.server_next_match(action_id: String)`（RPC）、`GameState._server_next_match(sender: int, action_id: String)`（权威）；`GameState._deal_new_match()`（公共发牌重置，供 start/next 复用）。
- **前置修正**：`settlement_model.gd` 已提交后，本任务新增测试依赖 `_server_start_match` 现在调用 `_deal_new_match()`（行为不变）。

- [ ] **Step 1: 重构 `_server_start_match` 并抽取 `_deal_new_match`**

在 `scripts/core/game_state.gd`，把 `_server_start_match` 的发牌段抽成 `_deal_new_match()`，并保持 LOBBY 校验不变：

```gdscript
func _server_start_match(sender: int) -> void:
	if phase != Phase.LOBBY:
		_reject(sender, RejectCode.ROOM_NOT_OPEN)
		return
	if sender != 0:
		_reject(sender, RejectCode.NOT_HOST)
		return
	if players.size() < KongRules.MIN_PLAYERS:
		_reject(sender, RejectCode.NOT_ENOUGH_PLAYERS)
		return
	_deal_new_match()

## 新建一局公共发牌重置：新 match_id、建牌组、清每人手牌/has_acted、发 HAND_SIZE 张、
## phase=INITIAL_PEEK、清 initial_confirmed 与 last_result、广播。
## 首局由 _server_start_match 调用；「再来一局」由 _server_next_match 调用（后者先 match_number += 1）。
func _deal_new_match() -> void:
	match_id = _new_match_id()
	_create_deck()
	for seat in turn_order:
		players[seat].cards.clear()
		players[seat].has_acted = false
		for _slot in KongRules.HAND_SIZE:
			players[seat].cards.append(_draw_from_deck())
	phase = Phase.INITIAL_PEEK
	initial_confirmed.clear()
	last_result.clear()
	_add_log("对局开始：请记住自己下方的两张牌。")
	_broadcast_state()
```

- [ ] **Step 2: 新增再来一局 RPC（放在 `request_start_match` 之后）**

```gdscript
## 再来一局：GAME_OVER 后房主一键开新局（无需回大厅）。match_number 递增。
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
	match_number += 1
	_deal_new_match()
```

- [ ] **Step 3: 追加测试（`tests/verify_settlement.gd`）**

在 `_ready` 中 `await _test_next_match()` 追加到 `_test_model_final_matches_score_system()` 之后；新增函数：

```gdscript
var _rejections := 0

func _test_next_match() -> void:
	GameState.command_rejected.connect(func(_code: int, _msg: String) -> void: _rejections += 1)

	# 拒绝：非 GAME_OVER 阶段（INITIAL_PEEK）
	_rejections = 0
	_open()
	GameState._server_next_match(0, "nm-1")
	_check("非 GAME_OVER 拒绝", GameState.phase == GameState.Phase.INITIAL_PEEK and _rejections == 1)

	# 正常：房主在 GAME_OVER 开新局
	GameState._finish_game()
	_check("已进入 GAME_OVER", GameState.phase == GameState.Phase.GAME_OVER)
	var before_number: int = GameState.match_number
	GameState._server_next_match(0, "nm-2")
	_check("match_number 递增", GameState.match_number == before_number + 1)
	_check("回 INITIAL_PEEK", GameState.phase == GameState.Phase.INITIAL_PEEK)
	_check("手牌重发每人 HAND_SIZE 张", GameState.players[0].cards.size() == KongRules.HAND_SIZE and GameState.players[1].cards.size() == KongRules.HAND_SIZE and GameState.players[2].cards.size() == KongRules.HAND_SIZE)
	_check("initial_confirmed 清空", GameState.initial_confirmed.is_empty())

	# 拒绝：非房主（seat1，peer2 为假 RPC 目标，不走 command_rejected 信号，用状态不变断言）
	GameState._finish_game()
	var before_phase: int = GameState.phase
	var before_number2: int = GameState.match_number
	GameState._server_next_match(1, "nm-3")
	_check("非房主拒绝（阶段与局数不变）", GameState.phase == before_phase and GameState.match_number == before_number2)

func _open() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	GameState._server_start_match(0)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState._server_initial_ready(2)
```

- [ ] **Step 4: 跑测试**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_settlement.tscn`
Expected: PASS（模型 13 + next_match 6 ≈ 19/19）。

- [ ] **Step 5: 回归基础套件**

Run 以下均须通过（逐条，退出码 0）：
`verify_protocol.tscn`（37/37）、`verify_kongbaya.tscn`（15/15）、`verify_reconnect.tscn`（41/41）。

- [ ] **Step 6: 提交**

```bash
git add scripts/core/game_state.gd tests/verify_settlement.gd
git commit -m "feat: 再来一局 RPC（GAME_OVER 后房主开新局）+ 抽取 _deal_new_match"
```

---

### Task 3: 结算弹层 `settlement_page.tscn` 场景实体 + `settlement_page.gd`

**Files:**
- Create: `scenes/ui/settlement_page.tscn`（静态骨架进编辑器，仿 `game_board.tscn`/`player_area.tscn` 惯例）
- Create: `scripts/ui/settlement_page.gd`

**Interfaces:**
- Consumes: `SettlementModel.build()` 产出（`layout_order`/`rounds`）；`UITheme.color(token)`；`main.overlay`；`AudioManager`。
- Produces: `class_name SettlementPage extends Control`；`setup(model: Dictionary, is_host: bool, match_number: int, on_winner: Callable, on_next_match: Callable, on_abort: Callable, auto_play := true) -> void`。`setup` 同步构建 UI；`auto_play=true` 时启动算分动画协程。冠军时刻回调 `on_winner`；footer 按钮回调 `on_next_match`/`on_abort`。
- **场景实体约定**：场景只承载静态骨架（容器、锚点、尺寸、占位文本、mouse_filter）；动态内容（排名行数、行内容、主题样式、标题、按钮）由脚本填充。主题颜色走代码 `UITheme.color()` 运行时覆写（与 `game_board.tscn` 一致，保证 dark/light 切换正确）。整页根节点 `mouse_filter = 2`（IGNORE，不挡棋盘），Footer `mouse_filter = 0`（STOP，按钮可点）。居中面板宽度 `ROW_W + 56`，**不遮挡四块玩家手牌区**。

- [ ] **Step 1: 创建 `scenes/ui/settlement_page.tscn` 静态骨架**

```
[gd_scene format=3 uid="uid://csettlementp0001"]

[ext_resource type="Script" path="res://scripts/ui/settlement_page.gd" id="1"]

[node name="SettlementPage" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2

[node name="Center" type="CenterContainer" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2

[node name="Panel" type="PanelContainer" parent="Center"]
custom_minimum_size = Vector2(536, 0)
layout_mode = 2

[node name="VBox" type="VBoxContainer" parent="Center/Panel"]
layout_mode = 2
theme_override_constants/separation = 10

[node name="Title" type="Label" parent="Center/Panel/VBox"]
custom_minimum_size = Vector2(0, 30)
layout_mode = 2
theme_override_font_sizes/font_size = 20
text = "结算"
horizontal_alignment = 1

[node name="RankingArea" type="Control" parent="Center/Panel/VBox"]
custom_minimum_size = Vector2(480, 184)
layout_mode = 2
mouse_filter = 2

[node name="Footer" type="Control" parent="Center/Panel/VBox"]
custom_minimum_size = Vector2(480, 46)
layout_mode = 2
mouse_filter = 0
visible = false
```

> `RankingArea` 高度 `184 = 4×46` 为占位，脚本在 `setup` 按实际人数覆盖 `custom_minimum_size.y = layout_order.size() × ROW_H`。

- [ ] **Step 2: 实现 `scripts/ui/settlement_page.gd`（绑骨架 + 填动态行）**

```gdscript
class_name SettlementPage
extends Control
## 结算弹层：居中排名窗口 + 同步轮算分动画（Balatro 式）+ 冠军特效。
## 场景实体承载静态骨架（scenes/ui/settlement_page.tscn），脚本负责：
##   - 填动态排名行（每行 = 一名玩家）
##   - 主题样式/标题/按钮运行时注入（UITheme token）
##   - 同步轮算分动画 + 冠军特效（回调解耦 main）

const ROW_H := 46
const ROW_W := 480
const FLIP_STEP := 0.35   # 同轮内每张牌翻开的间隔（秒）
const ROUND_DELAY := 0.55 # 每轮翻完到重排的等待（秒）
const RESORT_DURATION := 0.35

var _model: Dictionary = {}
var _is_host := false
var _on_winner: Callable = Callable()
var _on_next_match: Callable = Callable()
var _on_abort: Callable = Callable()
var _rows: Dictionary = {}   # seat -> {row, rank, name, cards, total}
var _rank_area: Control
var _footer: Control
var _title: Label

func setup(model: Dictionary, is_host: bool, match_number: int,
		on_winner: Callable, on_next_match: Callable, on_abort: Callable, auto_play := true) -> void:
	_model = model
	_is_host = is_host
	_on_winner = on_winner
	_on_next_match = on_next_match
	_on_abort = on_abort
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bind_ui(match_number)
	if auto_play:
		_run_sequence()

## 绑定场景节点 + 填动态内容（行、主题样式、标题）。
func _bind_ui(match_number: int) -> void:
	var center: CenterContainer = get_node("Center")
	var panel: PanelContainer = center.get_node("Panel")
	panel.add_theme_stylebox_override("panel", _panel_style())
	_title = get_node("Center/Panel/VBox/Title")
	_title.text = "结算 · 第 %d 局" % match_number
	_title.add_theme_color_override("font_color", UITheme.color("accent"))
	_rank_area = get_node("Center/Panel/VBox/RankingArea")
	_footer = get_node("Center/Panel/VBox/Footer")

	var n := _model.layout_order.size()
	_rank_area.custom_minimum_size = Vector2(ROW_W, n * ROW_H)
	var layout_order: Array = _model.layout_order
	for index in layout_order.size():
		_rank_area.add_child(_make_row(int(layout_order[index]), index))

func _make_row(seat: int, index: int) -> Control:
	var row := Control.new()
	row.name = "Row%d" % seat
	row.position = Vector2(0, index * ROW_H)
	row.size = Vector2(ROW_W, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(hbox)

	var rank_lbl := Label.new()
	rank_lbl.custom_minimum_size = Vector2(44, ROW_H)
	rank_lbl.text = str(index + 1)
	rank_lbl.add_theme_font_size_override("font_size", 18)
	rank_lbl.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	hbox.add_child(rank_lbl)

	var name_lbl := Label.new()
	name_lbl.custom_minimum_size = Vector2(130, ROW_H)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", UITheme.color("text_primary"))
	hbox.add_child(name_lbl)

	var cards_box := HBoxContainer.new()
	cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_box.add_theme_constant_override("separation", 6)
	cards_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(cards_box)

	var total_lbl := Label.new()
	total_lbl.custom_minimum_size = Vector2(70, ROW_H)
	total_lbl.text = "0"
	total_lbl.add_theme_font_size_override("font_size", 18)
	total_lbl.add_theme_color_override("font_color", UITheme.color("accent"))
	total_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(total_lbl)

	_rows[seat] = {"row": row, "rank": rank_lbl, "name": name_lbl, "cards": cards_box, "total": total_lbl}
	return row

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.color("bg_elevated")
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)
	style.border_color = UITheme.color("border")
	style.set_border_width_all(1)
	return style

## 同步轮算分：每轮全员同时翻牌 → 重排 → 下一轮 → 冠军特效 → footer。
func _run_sequence() -> void:
	for round in _model.rounds:
		var flips: Array = round.flips
		for flip in flips:
			_reveal_flip(int(flip.seat), flip, flips.find(flip) * FLIP_STEP)
		await get_tree().create_timer(ROUND_DELAY).timeout
		await _resort(round.ranking)
		await get_tree().create_timer(0.2).timeout
	await _champion()
	_show_footer()

func _reveal_flip(seat: int, flip: Dictionary, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not _rows.has(seat):
		return
	var entry: Dictionary = _rows[seat]
	var card_lbl := Label.new()
	card_lbl.text = "%s%s" % [str(flip.rank), str(flip.suit)]
	card_lbl.add_theme_font_size_override("font_size", 14)
	card_lbl.add_theme_color_override("font_color", UITheme.color("text_primary"))
	card_lbl.modulate.a = 0.0
	entry.cards.add_child(card_lbl)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(card_lbl, "modulate:a", 1.0, 0.25)
	tween.tween_property(card_lbl, "scale", Vector2.ONE, 0.25)
	_count_total(entry, int(flip.total))

func _count_total(entry: Dictionary, target: int) -> void:
	var from := int(entry.total.text)
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		entry.total.text = str(roundi(v)),
		float(from), float(target), 0.3)

func _resort(ranking: Array) -> void:
	for index in ranking.size():
		var seat := int(ranking[index].id)
		if not _rows.has(seat):
			continue
		var entry: Dictionary = _rows[seat]
		entry.rank.text = str(index + 1)
		var tween := create_tween()
		tween.tween_property(entry.row, "position:y", float(index * ROW_H), RESORT_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(RESORT_DURATION + 0.05).timeout

func _champion() -> void:
	if _model.rounds.is_empty():
		return
	var final_ranking: Array = _model.rounds[_model.rounds.size() - 1].ranking
	if final_ranking.is_empty():
		return
	var entry: Dictionary = _rows.get(int(final_ranking[0].id), {})
	if entry.is_empty():
		return
	entry.name.text = "★ %s" % str(entry.name.text)
	entry.name.add_theme_color_override("font_color", Color("f6d77a"))
	var tween := create_tween()
	tween.set_loops(6)
	tween.tween_property(entry.name, "modulate", Color(1.6, 1.35, 0.4), 0.22)
	tween.tween_property(entry.name, "modulate", Color(1.0, 1.0, 1.0), 0.22)
	if _on_winner.is_valid():
		_on_winner.call()
	await tween.finished

func _show_footer() -> void:
	_footer.visible = true
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_footer.add_child(box)
	if _is_host:
		var again := Button.new()
		again.text = "再来一局"
		again.pressed.connect(func() -> void:
			if _on_next_match.is_valid():
				_on_next_match.call())
		box.add_child(again)
		var exit := Button.new()
		exit.text = "返回大厅"
		exit.pressed.connect(func() -> void:
			if _on_abort.is_valid():
				_on_abort.call())
		box.add_child(exit)
	else:
		var wait := Label.new()
		wait.text = "等待房主开始下一局"
		wait.add_theme_color_override("font_color", UITheme.color("text_secondary"))
		box.add_child(wait)
```

- [ ] **Step 3: 编译检查**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 5`
Expected: 无 ERROR（`settlement_page.tscn` 与脚本可正常解析）。

- [ ] **Step 4: 提交**

```bash
git add scenes/ui/settlement_page.tscn scripts/ui/settlement_page.gd
git commit -m "feat: 结算弹层场景实体 + 同步轮算分动画 + 冠军特效"
```

---

### Task 4: main.gd 接入（开/关结算页、延迟胜利音效、再来一局转发、右下角摘要去重）

**Files:**
- Modify: `scripts/ui/main.gd`（常量区、`_ready` 信号区已接 `sfx_played`；`_on_state_updated`、`_on_match_aborted`、`_on_sfx`、新增 `_open_settlement`/`_close_settlement`/`_play_pending_winner`/`_request_next_match`）
- Modify: `scripts/ui/game_view.gd`（`_render_controls` PHASE_GAME_OVER 分支去重）
- Modify: `tests/verify_settlement.gd`（追加结算页构建冒烟测试）

**Interfaces:**
- Consumes: `SettlementPageScript`（preload）、`SettlementModel.build(players)`、`Network.is_host`、`GameState.request_next_match(action_id)`、`GameState.request_abort_match`、`AudioManager.play_winner()`、`latest_state.result.ranking`。
- Produces: `main._open_settlement()`/`_close_settlement()`、`main._play_pending_winner()`、`main._request_next_match()`；`main.settlement_page` 变量；`game_view` 结算去重。

- [ ] **Step 1: main.gd 常量与变量**

在 `main.gd` 常量区（`DuelBarScript` 附近）追加：

```gdscript
const SettlementPageScript := preload("res://scripts/ui/settlement_page.gd")
```

在 `_duel_panel`/`_reconnect_panel` 变量区追加：

```gdscript
var settlement_page: Control = null
var _pending_winner_sfx := false
```

- [ ] **Step 2: main.gd `_on_state_updated` 末尾接入开/关**

`_on_state_updated` 中 `_render_game()` 之后追加：

```gdscript
	if int(state.phase) == PHASE_GAME_OVER:
		_open_settlement()
	else:
		_close_settlement()
```

- [ ] **Step 3: main.gd 新增结算页方法（放在 `_render_duel` 之后）**

```gdscript
## GAME_OVER 时打开结算弹层（幂等：已打开则跳过）。reason-only 结算不开弹层，保留右下角摘要。
func _open_settlement() -> void:
	if settlement_page != null and is_instance_valid(settlement_page):
		return
	var result: Dictionary = latest_state.get("result", {})
	if result.get("ranking", []).is_empty():
		return
	var model: Dictionary = SettlementModel.build(latest_state.players)
	var page := SettlementPageScript.new()
	page.name = "SettlementPage"
	overlay.add_child(page)
	page.setup(model, Network.is_host, int(latest_state.get("match_number", 1)),
		_play_pending_winner, _request_next_match, GameState.request_abort_match)
	settlement_page = page

## 关闭结算弹层（收到新局/中止时调用）。
func _close_settlement() -> void:
	if settlement_page != null and is_instance_valid(settlement_page):
		settlement_page.queue_free()
	settlement_page = null

## 冠军时刻：若服务器已广播过 winner 音效事件，此刻播放（延迟到冠军出场）。
func _play_pending_winner() -> void:
	if _pending_winner_sfx:
		AudioManager.play_winner()
		_pending_winner_sfx = false

## 结算页「再来一局」→ 服务器开新局。
func _request_next_match() -> void:
	GameState.request_next_match(_next_action_id())
```

- [ ] **Step 4: main.gd `_on_sfx` 改为延迟**

`_on_sfx` 的 `"winner"` 分支改为只设标志（冠军时刻由结算页回调播放）：

```gdscript
func _on_sfx(kind: String) -> void:
	match kind:
		"bell":
			AudioManager.play_bell()
		"winner":
			_pending_winner_sfx = true
```

- [ ] **Step 5: main.gd `_on_match_aborted` 关闭结算页**

在 `_on_match_aborted` 中 `_set_status` 之前追加：

```gdscript
	_close_settlement()
```

- [ ] **Step 6: game_view.gd 右下角结算摘要去重**

`_render_controls` 的 PHASE_GAME_OVER 分支改为：有 ranking（结算页接管）则跳过，否则只显示 reason：

```gdscript
	elif phase == PHASE_GAME_OVER:
		var result: Dictionary = main.latest_state.result
		if not result.get("ranking", []).is_empty():
			return  # 结算页接管排名展示，右下角不重复
		var summary := Label.new()
		summary.text = str(result.get("reason", "对局结束"))
		summary.add_theme_font_size_override("font_size", 20)
		summary.add_theme_color_override("font_color", UITheme.color("success"))
		main.controls_box.add_child(summary)
```

- [ ] **Step 7: 追加结算页构建冒烟测试（`tests/verify_settlement.gd`）**

在 `_ready` 中 `await _test_next_match()` 之后追加 `await _test_page_construct()`；新增：

```gdscript
func _test_page_construct() -> void:
	var model: Dictionary = SettlementModel.build(_players_even())
	var page: Control = preload("res://scenes/ui/settlement_page.tscn").instantiate()
	get_tree().root.add_child(page)
	page.setup(model, true, 1, Callable(), Callable(), Callable(), false)
	await get_tree().process_frame
	_check("结算页行数=玩家数", page._rows.size() == 3)
	_check("结算页标题正确", page._title.text == "结算 · 第 1 局")
	_check("初始每行累计分=0", page._rows[0].total.text == "0" and page._rows[1].total.text == "0" and page._rows[2].total.text == "0")
	_check("footer 初始隐藏", page._footer.visible == false)
	page.queue_free()
```

- [ ] **Step 8: 跑全套测试**

Run 逐条，均须通过：
`verify_settlement.tscn`（模型 13 + next_match 6 + 冒烟 4 ≈ 23/23）、`verify_protocol.tscn`、`verify_kongbaya.tscn`、`verify_swap.tscn`、`verify_duel.tscn`、`verify_reconnect.tscn`、`verify_hint.tscn`（7/8 为既有失败）。
双实例 `verify_net.tscn`（host 与 client 并行，均 PASS）：
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_net.tscn -- -role host > /tmp/net_host.log 2>&1 &
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_net.tscn -- -role client > /tmp/net_client.log 2>&1 &
wait
```
- [ ] **Step 9: 提交**

```bash
git add scripts/ui/main.gd scripts/ui/game_view.gd tests/verify_settlement.gd
git commit -m "feat: 结算页接入 main（开/关、延迟胜利音效、再来一局）+ 右下角摘要去重"
```

---

### Task 5: 文档更新 + 全量回归 + 提交

**Files:**
- Modify: `docs/网络协议_V1.md`（新增 `request_next_match`/`server_next_match` 契约）
- Modify: `docs/KONG_开发文档.md`（补结算展示规则条目）
- Modify: `docs/功能实现文档.md`（文件树补 `settlement_model.gd`/`settlement_page.gd`/`verify_settlement.*`，16 Feature 映射补记）
- Modify: `docs/AI_AGENT_交接说明.md`（基线补结算页 + 再来一局；验证命令表补 `verify_settlement`）

- [ ] **Step 1: 更新 `docs/网络协议_V1.md`**

新增小节（仿现有 `request_kongbaya` 描述格式），内容要点：
- 命令 `request_next_match` / RPC `server_next_match(action_id)`，仅 GAME_OVER 阶段、仅房主（seat0）允许。
- 拒绝错误码：`INVALID_PHASE`（非 GAME_OVER）、`NOT_HOST`（非房主）、`NOT_ENOUGH_PLAYERS`。
- 成功效果：`match_number += 1`，phase → INITIAL_PEEK，全员重发 `HAND_SIZE` 张牌，广播快照；快照 `result` 清空。

- [ ] **Step 2: 更新 `docs/KONG_开发文档.md`**

补一条结算展示规则（随现有规则编号续排）：「GAME_OVER 后客户端弹出居中结算页，按同步轮记分（每轮全员同时翻开第 N 张，累计分实时累加），排名表低分在前实时重排；冠军行金色光环 + ★ 徽章 + 胜利音效；房主可『再来一局』（需 GAME_OVER + 房主）。」

- [ ] **Step 3: 更新 `docs/功能实现文档.md` 文件树与 Feature 映射**

文件树补：`scripts/core/settlement_model.gd`、`scenes/ui/settlement_page.tscn`、`scripts/ui/settlement_page.gd`、`tests/verify_settlement.gd/.tscn`；Feature 映射补「结算页展示 + 再来一局」。

- [ ] **Step 4: 更新 `docs/AI_AGENT_交接说明.md`**

第 2 节基线补一句：结算页（居中排名窗口 + 同步轮算分动画 + 冠军特效）；第 4 节 UI 拆分表补 `settlement_page.gd`；第 8 节验证命令表补：
```
# 结算模型+再来一局+结算页冒烟测试
... --headless --path . res://tests/verify_settlement.tscn
```

- [ ] **Step 5: 全量回归（确认分支可交付）**

Run 逐条全绿（`verify_hint` 7/8 为既有失败，非本次引入）：`verify_settlement`/`verify_protocol`/`verify_swap`/`verify_duel`/`verify_reconnect`/`verify_kongbaya`/双实例 `verify_net`。

- [ ] **Step 6: 提交**

```bash
git add docs/网络协议_V1.md docs/KONG_开发文档.md docs/功能实现文档.md docs/AI_AGENT_交接说明.md
git commit -m "doc: 结算页展示规则 + 再来一局协议 + 文件树/验证命令同步"
```

- [ ] **Step 7: 追加 `docs/修改日志.md`（gitignore，不提交）**

按项目约定记录本次 request：结算页 + 算分动画 + 冠军特效 + 再来一局实现与验证结果。