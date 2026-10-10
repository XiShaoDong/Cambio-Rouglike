# 开局发牌动画 + 重开按钮 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use `- [ ]`.

**Goal:** 每局开始 3D 逐张发牌动画（按住空格 2×）；房主圆形 ↻ 按钮 → 提示板「是否重开」→ 服务器重开本局（保留系列赛/经济）。

**Architecture:** 发牌纯客户端（检测 `match_id` 变化，复用 `CardFly` + `_anim_slots` 隐藏/落地露出）；重开新增服务器 RPC 复用 `_deal_new_match`；确认复用提示板。

**Tech Stack:** Godot 4.6 / GDScript；headless 测试。

## Global Constraints
- 不改规则判定/协议字段/`HiddenInfo` 结构；只加一个 RPC。
- `_deal_new_match()` 已生成新 `match_id`、重发手牌、回 INITIAL_PEEK、保留 match_number/经济。
- 发牌不锁操作；纯 3D；发牌用卡背（不泄漏）。
- 重开限房主、非 LOBBY。

---

### Task 1: 服务器重开 RPC + verify_restart
**Files:** Modify `scripts/core/game_state.gd`; Create `tests/verify_restart.gd`/`.tscn`; Modify `tools/run_all_tests.sh`.
- [ ] **Step 1 失败测试**（`tests/verify_restart.gd`，参考 `tests/verify_protocol.gd` 的 GameState 直调风格：`_server_start_match` 后调 `_server_restart_match`）：
```gdscript
extends Node
var failures := 0
var checks := 0
func _ready() -> void:
	await get_tree().process_frame
	_test()
	print("=== RESTART RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)
func _check(n: String, ok: bool) -> void:
	checks += 1
	if ok: print("[PASS] " + n)
	else: failures += 1; printerr("[FAIL] " + n)
func _test() -> void:
	# 直构服务器状态（无需网络）：HAND_SIZE=4
	GameState._reset_match()
	GameState.phase = GameState.Phase.LOBBY
	GameState._add_player(1, "房主")
	GameState._add_player(2, "乙")
	GameState._server_start_match(0, 5)
	var mid0 := GameState.match_id
	var num0 := GameState.match_number
	GameState.players[1].currency = 123
	GameState.players[1].health = 2
	GameState.players[1].cards = ["x"]
	GameState._server_restart_match(0, "a1")
	_check("重开生成新 match_id", GameState.match_id != mid0 and not GameState.match_id.is_empty())
	_check("match_number 保留", GameState.match_number == num0)
	_check("货币保留", int(GameState.players[1].currency) == 123)
	_check("生命保留", int(GameState.players[1].health) == 2)
	_check("手牌重发 HAND_SIZE", GameState.players[1].cards.size() == KongRules.HAND_SIZE)
	_check("回 INITIAL_PEEK", GameState.phase == GameState.Phase.INITIAL_PEEK)
	# 非房主拒绝（seat 1=乙）
	var mid1 := GameState.match_id
	GameState._server_restart_match(1, "a2")
	_check("非房主拒绝", GameState.match_id == mid1 or GameState.phase == GameState.Phase.INITIAL_PEEK)
```
- [ ] **Step 2 运行确认失败** → FAIL（`_server_restart_match` 未定义）。
- [ ] **Step 3 实现** `game_state.gd`（在 `_server_next_match` 之后）：
```gdscript
## 重开本局（仅房主；保留系列赛/经济/生命/局号，重新发牌）。
func request_restart_match(action_id := "") -> void:
	if multiplayer.is_server():
		_server_restart_match(_peer_to_seat(1), action_id)
	else:
		server_restart_match.rpc_id(1, action_id)

@rpc("any_peer", "reliable")
func server_restart_match(action_id: String) -> void:
	if multiplayer.is_server():
		_server_restart_match(_peer_to_seat(multiplayer.get_remote_sender_id()), action_id)

func _server_restart_match(sender: int, action_id := "") -> void:
	if phase == Phase.LOBBY:
		_reject(sender, RejectCode.ROOM_NOT_OPEN, action_id)
		return
	if sender != 0:
		_reject(sender, RejectCode.NOT_HOST, action_id)
		return
	if players.size() < KongRules.MIN_PLAYERS:
		_reject(sender, RejectCode.NOT_ENOUGH_PLAYERS, action_id)
		return
	_deal_new_match()
```
- [ ] **Step 4** `run_all_tests.sh` 加 `run_single "restart" res://tests/verify_restart.tscn`。运行 → 全 PASS。
- [ ] **Step 5 提交** `git commit -m "feat: 服务器重开本局 RPC + 测试"`

---

### Task 2: `Table3dView.play_deal`（发牌动画）
**Files:** Modify `scripts/ui/table3d_view.gd`; Modify `tests/verify_restart.gd`.
- [ ] **Step 1 失败测试**（在 `verify_restart.gd` `_test()` 末尾加，用 table3d 场景）：
```gdscript
	# 发牌编排
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	var st := {"viewer_id": 0, "current_player": 0, "players": [
		{"id": 0, "name": "甲", "count": 4, "currency": 0, "health": 2, "slots": [{"card_id":"c0"},{"card_id":"c1"},{"card_id":"c2"},{"card_id":"c3"}]},
		{"id": 1, "name": "乙", "count": 4, "currency": 0, "health": 2, "slots": [{"card_id":"d0"},{"card_id":"d1"},{"card_id":"d2"},{"card_id":"d3"}]},
	], "draw_count": 30, "discard": {}, "pending": {}, "phase": 1}
	view.render(st)
	await get_tree().process_frame
	view.set_deal_speed(99.0)
	view.play_deal(st)
	_check("发牌标记在途", view._dealing and view._anim_slots.size() > 0)
	await get_tree().create_timer(0.6).timeout
	_check("发牌结束清空在途", not view._dealing and view._anim_slots.is_empty())
	view.queue_free()
	await get_tree().process_frame
```
- [ ] **Step 2 失败。**
- [ ] **Step 3 实现** `table3d_view.gd`：
  - 常量 `const DEAL_INTERVAL := 0.15`；成员 `var _deal_speed := 1.0`、`var _dealing := false`。
  - 方法：
```gdscript
## 开局发牌动画：从抽牌堆逐张飞到各席手牌槽（一个玩家一个玩家，seat 升序从房主），落地露出。
func play_deal(state: Dictionary) -> void:
	_bind()
	if not _bound or state.is_empty() or _dealing:
		return
	var seats: Array = _seat_node_by_id.keys()
	seats.sort()
	if seats.is_empty():
		return
	var max_slots := 0
	for p in state.get("players", []):
		max_slots = maxi(max_slots, (p.get("slots", []) as Array).size())
	if max_slots <= 0:
		return
	var targets: Array = []
	for r in max_slots:
		for seat in seats:
			targets.append([int(seat), r])
	for t in targets:
		_mark_anim_slot(int(t[0]), int(t[1]))
	_dealing = true
	render(state)
	_run_deal(targets)

func _run_deal(targets: Array) -> void:
	for t in targets:
		await get_tree().create_timer(DEAL_INTERVAL / maxf(_deal_speed, 0.01)).timeout
		if not is_inside_tree() or not _dealing:
			return
		_spawn_fly(center_xform("deck"), slot_xform(int(t[0]), int(t[1])), {}, false, false,
			func(): _unmark_anim_slot(int(t[0]), int(t[1])))
	await get_tree().create_timer(DEAL_INTERVAL / maxf(_deal_speed, 0.01)).timeout
	_dealing = false

func set_deal_speed(s: float) -> void:
	_deal_speed = maxf(s, 0.01)
```
  - `_clear_exchange_anim()` 末尾加 `_dealing = false`。
- [ ] **Step 4** 运行 → 全 PASS。回归 `verify_table3d_exchange`。
- [ ] **Step 5 提交** `git commit -m "feat: 3D 开局发牌动画 play_deal + 空格倍速接口"`

---

### Task 3: main 触发发牌 + 空格倍速 + 重开确认
**Files:** Modify `scripts/ui/main.gd`.
- [ ] **Step 1** 成员：`var _last_match_id := ""`、`var _restart_confirm := false`。
- [ ] **Step 2** 在 `_on_state_updated`（或 `_process` 3D 分支持久处）检测：
```gdscript
	var mid := str(latest_state.get("match_id", ""))
	if mid != "" and mid != _last_match_id and int(latest_state.get("phase", 0)) != PHASE_LOBBY:
		if _last_match_id != "" and _table3d_active and table3d != null and is_instance_valid(table3d):
			table3d.play_deal(latest_state)
		_last_match_id = mid
```
  （首见仅记录，不播；后续变化才播。放 `_on_state_updated` 末尾。）
- [ ] **Step 3** `_process` 3D 分支：`if _table3d_active and table3d != null and is_instance_valid(table3d): table3d.set_deal_speed(2.0 if Input.is_key_pressed(KEY_SPACE) else 1.0)`。
- [ ] **Step 4** 重开确认：
```gdscript
func _request_restart_confirm() -> void:
	if not Network.is_host:
		return
	_restart_confirm = true
	_refresh_hint_panel()

func _restart_actions() -> Array:
	return [
		{"text": "确认重开", "action": "restart_yes", "enabled": true},
		{"text": "取消", "action": "restart_no", "enabled": true},
	]
```
  `_hint_for()`：`if _restart_confirm: return "是否重开本局？"`（放最前）。
  `_refresh_hint_panel()` 里：`if _restart_confirm: actions = _restart_actions() else: actions = ActionModel.conditional_actions(latest_state, _interaction_ctx())`。
  `_on_action()` 加：
```gdscript
		"restart_yes":
			_restart_confirm = false
			GameState.request_restart_match(_next_action_id())
			_refresh_hint_panel()
		"restart_no":
			_restart_confirm = false
			_refresh_hint_panel()
```
  （3D 提示板按钮 `_on_action` 已在 click 路由 `"hud"` 里；2D 的 HintActions 也走 `_on_action`。）
- [ ] **Step 5** 编译 + 回归 `verify_hint`/`verify_manual`/`verify_actions`/`verify_board3d`。
- [ ] **Step 6 提交** `git commit -m "feat: main 触发发牌 + 空格 2x + 重开确认板"`

---

### Task 4: 3D 重开按钮（牌桌右角，仅房主）
**Files:** Modify `scripts/ui/table3d_view.gd`.
- [ ] **Step 1** `_bind()` 末尾建 `RestartButton`：`CylinderMesh` 扁平圆盘 + `Label3D("↻")` billboard + `Area3D`（`collision_layer=Table3dLayout.PICK_MASK`、`collision_mask=0`、`set_meta("pick", {"kind":"hud","action":"restart"})`）；位置 `Vector3(Table3dLayout.TABLE_RADIUS*0.8, Table3dLayout.TABLE_HEIGHT+0.02, Table3dLayout.TABLE_RADIUS*0.8)`；保存 `_restart_button`。
- [ ] **Step 2** `render()` 里（或每帧）`_restart_button.visible = Network.is_host`（+ 阶段非 LOBBY/GAME_OVER）。
- [ ] **Step 3** 测试：`view.render(st)` 后非房主 `_restart_button.visible==false`；（`Network.is_host` 默认？测试环境非房主）。断言按钮存在与 meta。
- [ ] **Step 4 提交** `git commit -m "feat: 3D 房主重开按钮（牌桌右角）"`

---

### Task 5: 2D 房主重开按钮
**Files:** Modify `scripts/ui/game_view.gd`.
- [ ] **Step 1** 在棋盘右侧建圆形 `Button`（`text="↻"`、方形 min size、`StyleBoxFlat` 全圆角、`pressed` → `main._request_restart_confirm()`）；仅 `Network.is_host` 且对局中显示（`_render` 里置 visible）。
- [ ] **Step 2** 编译 + 回归 `verify_protocol`/双实例 `verify_net`。
- [ ] **Step 3 提交** `git commit -m "feat: 2D 房主重开按钮"`

---

### Task 6: 文档 + 全量
**Files:** `docs/网络协议_V1.md`（加 `restart_match` 行/§）、`docs/3D角色与场景说明.md`（发牌动画 + 重开按钮）、`docs/功能实现文档.md`、`docs/AI_AGENT_交接说明.md`（总览 + 测试）。
- [ ] **Step 1** 各文档补条目；验证命令加 `verify_restart`。
- [ ] **Step 2** `tools/run_all_tests.sh` 全量全绿。
- [ ] **Step 3 提交** `git commit -m "doc: 记录发牌动画 + 重开按钮"`

---

## Self-Review
**Spec coverage**：服务器重开→T1；发牌编排→T2；触发/倍速/确认→T3；3D/2D 按钮→T4/T5；文档→T6。
**Placeholder scan**：无 TBD。
**Type consistency**：`_server_restart_match(sender,action_id)`；`request_restart_match`；`play_deal(state)`/`set_deal_speed(s)`/`_dealing`/`_anim_slots`；`_restart_confirm`/`_request_restart_confirm`/`restart_yes|restart_no`。
**风险**：首见 `match_id` 不播（重连不误播）；如需首局也播可改为"phase 由 LOBBY 进入且 `_table3d_active`"。
