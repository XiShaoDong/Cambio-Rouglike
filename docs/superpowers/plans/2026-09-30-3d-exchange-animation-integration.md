# 3D 换牌动画接入对局 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把沙盒 `CardFly` 接入对局 3D 视图，播放 `card_exchange_animated` 全部 6 种飞牌；2D 逻辑一行不改。

**Architecture:** 编排放在 `table3d_view`（其拥有 `_card_blocks` 与跨 render 状态）。`main.gd` 只在事件处理器加 3D 分支。新增 `_anim_slots`（在途槽位跨 render 隐藏）+ `_discard_hold`（延迟弃牌顶）+ `CardFly` 落地回调重渲染。

**Tech Stack:** Godot 4.6 GDScript；headless 单测。

## Global Constraints

- 引擎路径：`/Applications/Godot.app/Contents/MacOS/Godot`；所有验证 **headless**，**不启动 GUI**。
- **2D 逻辑零改动**：`card_animator.gd`、`game_view.gd`、`card_view.gd`、`reveal_controller.gd` 不动；`main.gd` 的 2D 分支（`animator.handle_exchange`）逐字不动。
- 不改：`scripts/core/*`、`scripts/net/*`、`card_block.gd`、`card_fly*.gd`、`scenes/ui/table3d.tscn`、现有测试。
- 命名沿用项目风格；中文注释；**不写 emoji**。
- 提交按 `feat:` / `doc:` 分类。
- 已知陷阱：GDScript 未限定 `smoothstep(...)` 会解析到内建 3 参全局函数（本计划不新增此类调用）；新增 `class_name` 后若 `--headless` 报未声明，先跑 `--headless --editor --quit` 刷新类缓存。

---

### Task 1: 接入飞牌（table3d_view + main）+ 测试

**Files:**
- Modify: `scripts/ui/table3d_view.gd`
- Modify: `scripts/ui/main.gd`（约 355-358 行的事件处理器）
- Test: `tests/verify_table3d_exchange.gd`、`tests/verify_table3d_exchange.tscn`

**Interfaces:**
- Consumes: `CardFly`（`play(finished)`）、`Table3dLayout`（`slot_grid_pos`/`BLOCK_SIZE`/`BLOCK_GAP`）。
- Produces（供测试与未来复用）：`Table3dView.animate_exchange(data)`、`slot_xform(seat,slot)`、`center_xform(kind)`、`slot_face_up(seat,slot)`、`slot_card(seat,slot)`、`_has_anim_slot(seat,slot)`、`_flyers`、`_anim_slots`、`_discard_hold`。

- [ ] **Step 1: 写失败测试**

创建 `tests/verify_table3d_exchange.gd`：

```gdscript
extends Node
## headless 单元测试：3D 对局换牌飞牌接入（animate_exchange / 跨 render 标记 / 落地恢复）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TABLE3D EXCHANGE RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	await _test_exchange()

func _base_state() -> Dictionary:
	return {
		"viewer_id": 0, "current_player": 0, "phase": 3,
		"draw_count": 30, "discard": {}, "pending": {},
		"players": [
			{"id": 0, "name": "甲", "count": 4, "currency": 0, "health": 2, "eliminated": false,
			 "slots": [{"card_id": "a", "card": {"rank": "K", "suit": "♠"}},
			           {"card_id": "b", "card": {"rank": "A", "suit": "♥"}},
			           {"card_id": "c"}, {"card_id": "d"}]},
			{"id": 1, "name": "乙", "count": 4, "currency": 0, "health": 2, "eliminated": false,
			 "slots": [{"card_id": "e"}, {"card_id": "f", "card": {"rank": "Q", "suit": "♦"}},
			           {"card_id": "g"}, {"card_id": "h"}]},
		],
	}

func _wait_flyers(view, timeout := 3.0) -> void:
	var t := 0.0
	while t < timeout and not view._flyers.is_empty():
		await get_tree().create_timer(0.05).timeout
		t += 0.05

func _test_exchange() -> void:
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	view.render(_base_state())
	await get_tree().process_frame

	# replace：2 段 + 标记槽 + 弃牌锁
	view.animate_exchange({"kind": "replace", "actor": 0, "slot": 0,
		"old_data": {"rank": "K", "suit": "♠"}, "big_data": {"rank": "7", "suit": "♦"}})
	_check("replace 生成 2 张飞牌", view._flyers.size() == 2)
	_check("replace 标记槽位", view._has_anim_slot(0, 0))
	_check("replace 弃牌锁", view._discard_hold)
	view.render(_base_state())
	await get_tree().process_frame
	_check("replace 标记槽不渲染", not view._card_blocks[0].has(0))
	await _wait_flyers(view)
	_check("replace 落地清标记/解锁/释放", not view._has_anim_slot(0, 0) and not view._discard_hold and view._flyers.is_empty())
	_check("replace 落地后槽位恢复", view._card_blocks[0].has(0))

	# swap：2 段，两段全落地才清标记
	view.animate_exchange({"kind": "swap", "a": 0, "a_slot": 1, "b": 1, "b_slot": 1,
		"a_data": {"rank": "A", "suit": "♥"}, "b_data": {"rank": "Q", "suit": "♦"}})
	_check("swap 生成 2 张飞牌", view._flyers.size() == 2)
	_check("swap 标记双槽", view._has_anim_slot(0, 1) and view._has_anim_slot(1, 1))
	await _wait_flyers(view)
	_check("swap 落地清双标记", not view._has_anim_slot(0, 1) and not view._has_anim_slot(1, 1))

	# discard：1 段 + 弃牌锁
	view.animate_exchange({"kind": "discard", "actor": 0, "big_data": {"rank": "8", "suit": "♠"}})
	_check("discard 生成 1 张飞牌", view._flyers.size() == 1)
	_check("discard 弃牌锁", view._discard_hold)
	await _wait_flyers(view)
	_check("discard 落理解锁", not view._discard_hold and view._flyers.is_empty())

	# slap_penalty：未渲染槽 + 背面
	view.animate_exchange({"kind": "slap_penalty", "peer": 1, "slot": 4})
	_check("penalty 生成 1 张飞牌", view._flyers.size() == 1)
	_check("penalty 背面无标签", view._flyers[0].card_block().label_text() == "")
	_check("未渲染槽 xform 非零", not view.slot_xform(1, 4).origin.is_zero_approx())
	await _wait_flyers(view)
	_check("penalty 落地清标记", not view._has_anim_slot(1, 4))

	# slap_resolved：槽→弃牌，牌面公开 + 弃牌锁
	view.animate_exchange({"kind": "slap_resolved", "target": 0, "target_slot": 2, "card": {"rank": "Q", "suit": "♦"}})
	_check("resolved 生成 1 张飞牌", view._flyers.size() == 1)
	_check("resolved 弃牌锁", view._discard_hold)
	await _wait_flyers(view)
	_check("resolved 落地清标记/解锁", not view._has_anim_slot(0, 2) and not view._discard_hold)

	# slap_gift：非 viewer 背面；viewer==actor 带牌面
	view.animate_exchange({"kind": "slap_gift", "actor": 1, "own_slot": 0, "target": 0, "target_slot": 3})
	_check("gift 非 actor 背面", view._flyers[0].card_block().label_text() == "")
	await _wait_flyers(view)
	view.animate_exchange({"kind": "slap_gift", "actor": 0, "own_slot": 0, "target": 1, "target_slot": 3})
	_check("gift viewer==actor 带牌面", view._flyers[0].card_block().label_text() == "K♠")
	await _wait_flyers(view)
	_check("gift 落地清双标记", not view._has_anim_slot(0, 0) and not view._has_anim_slot(1, 3))

	# set_active(false) 清理
	view.animate_exchange({"kind": "discard", "actor": 0, "big_data": {}})
	_check("清理前有飞牌", view._flyers.size() > 0)
	view.set_active(false)
	_check("set_active(false) 清飞牌/锁/标记", view._flyers.is_empty() and not view._discard_hold and view._anim_slots.is_empty())
	view.set_active(true)

	# 无状态安全跳过
	var bare = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(bare)
	await get_tree().process_frame
	bare.animate_exchange({"kind": "discard", "actor": 0, "big_data": {}})
	_check("无状态时安全跳过", bare._flyers.is_empty())
	bare.queue_free()
	view.queue_free()
```

创建 `tests/verify_table3d_exchange.tscn`：

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/verify_table3d_exchange.gd" id="1_test"]

[node name="VerifyTable3dExchange" type="Node"]
script = ExtResource("1_test")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_exchange.tscn`
Expected: 失败（`animate_exchange`/`_flyers` 未定义 → 运行时错误，非 0 退出）。

- [ ] **Step 3: 改 `table3d_view.gd` —— 新增字段**

在 `var _bell_mat: StandardMaterial3D = null` 之后插入：

```gdscript
var _deck_node: Node3D = null
var _discard_node: Node3D = null
var _pending_node: Node3D = null
var _seat_node_by_id := {}     # seat -> Node3D（render 登记）
var _slot_cards := {}          # {seat: {slot: card}}（render 登记，供 slap_gift 自身视角取牌面）
var _anim_slots := {}          # "seat_slot" -> true（在途动画槽位，render 跳过）
var _flyers: Array = []        # 在途 CardFly
var _discard_hold := false     # 飞向弃牌堆期间隐藏弃牌顶
var _last_state: Dictionary = {}
var _last_actionable := Callable()
```

- [ ] **Step 4: 改 `table3d_view.gd` —— `_bind` 登记中央节点**

在 `_bind()` 里 `var deck_block := get_node_or_null("Center/Deck")` 与其后的 `set_pick` 块之后插入：

```gdscript
	_deck_node = deck_block
	_discard_node = _discard_block
	_pending_node = _pending_block
```

- [ ] **Step 5: 改 `table3d_view.gd` —— `render` 登记 + 弃牌锁**

在 `render()` 中 `_viewer = viewer` 之后插入：

```gdscript
	_last_state = state
	_last_actionable = actionable
	_seat_node_by_id.clear()
	_slot_cards.clear()
```

在玩家循环中 `var a := float(seat_angle.get(seat, 0.0))` 之后插入：

```gdscript
		_seat_node_by_id[seat] = node
		_slot_cards[seat] = {}
```

把弃牌顶段落：

```gdscript
	var discard: Dictionary = state.get("discard", {})
	_discard_block.setup({"card": discard} if not discard.is_empty() else {})
	_discard_block.set_pick({"kind": "discard"})
	_discard_block.set_pick_enabled(not discard.is_empty())
```

替换为：

```gdscript
	var discard: Dictionary = state.get("discard", {})
	if _discard_hold:
		_discard_block.visible = false
		_discard_block.set_pick_enabled(false)
	else:
		_discard_block.visible = true
		_discard_block.setup({"card": discard} if not discard.is_empty() else {})
		_discard_block.set_pick({"kind": "discard"})
		_discard_block.set_pick_enabled(not discard.is_empty())
```

- [ ] **Step 6: 改 `table3d_view.gd` —— `_render_seat` 登记牌面 + 跳过标记槽**

把 `_render_seat` 的槽位循环首两行：

```gdscript
	for i in slots.size():
		var slot: Dictionary = slots[i]
		# 空槽（贴牌成功/交出后卡片被清掉）不渲染 → 卡牌消失（与 2D 空槽透明占位一致）
		if str(slot.get("card_id", "")).is_empty() and not slot.has("card"):
			continue
```

替换为：

```gdscript
	for i in slots.size():
		var slot: Dictionary = slots[i]
		# 登记槽位牌面（含被动画隐藏的槽，供 slap_gift 自身视角取牌面）
		_slot_cards[int(p.id)][i] = slot.get("card", {})
		# 在途动画槽位跳过（等价 2D mark_anim_slot）
		if _has_anim_slot(int(p.id), i):
			continue
		# 空槽（贴牌成功/交出后卡片被清掉）不渲染 → 卡牌消失（与 2D 空槽透明占位一致）
		if str(slot.get("card_id", "")).is_empty() and not slot.has("card"):
			continue
```

并把该循环内的局部定位：

```gdscript
		var grid: Vector2 = Table3dLayout.slot_grid_pos(i)
		# 卡牌平铺桌面（对齐 2D 观感）：列向「持有者右手侧」增长、行 0 远离持有者 / 行 1 靠近。
		# 座位节点朝向 a+180°，本地 -X → 持有者右侧，本地 +Z → 桌心（即远离持有者），
		# 故列取 -X、行取 (1-行) 的 +Z，新槽位向右（持有者右手侧）追加。
		block.position = Vector3(
			-grid.x * (Table3dLayout.BLOCK_SIZE.x + Table3dLayout.BLOCK_GAP.x),
			0.0,
			(1.0 - grid.y) * (Table3dLayout.BLOCK_SIZE.z + Table3dLayout.BLOCK_GAP.z))
```

替换为（复用 `_slot_local`，行为不变）：

```gdscript
		# 卡牌平铺桌面（对齐 2D 观感）：见 _slot_local。
		block.position = _slot_local(i).origin
```

- [ ] **Step 7: 改 `table3d_view.gd` —— `set_active` 清理**

把：

```gdscript
func set_active(on: bool) -> void:
	visible = on
```

替换为：

```gdscript
func set_active(on: bool) -> void:
	visible = on
	if not on:
		_clear_exchange_anim()
```

- [ ] **Step 8: 改 `table3d_view.gd` —— 文件末尾新增飞牌编排**

在文件末尾（`_hover_material()` 之后）追加：

```gdscript
## ===== 3D 换牌飞牌（card_exchange_animated 接入）=====

## 播放一条交换动画事件。3D 分支入口；2D 逻辑不受影响。
func animate_exchange(data: Dictionary) -> void:
	_bind()
	if not _bound or _last_state.is_empty():
		return
	match str(data.get("kind", "")):
		"replace":
			_anim_replace(data)
		"swap":
			_anim_swap(data)
		"discard":
			_anim_discard(data)
		"slap_penalty":
			_anim_slap_penalty(data)
		"slap_resolved":
			_anim_slap_resolved(data)
		"slap_gift":
			_anim_slap_gift(data)

## 槽位世界变换（未渲染时按布局计算）。
func slot_xform(seat_id: int, slot: int) -> Transform3D:
	var b = _find_block(seat_id, slot)
	if b != null and is_instance_valid(b):
		return (b as Node3D).global_transform
	var node: Node3D = _seat_node_by_id.get(seat_id)
	if node == null or not is_instance_valid(node):
		return Transform3D.IDENTITY
	return node.global_transform * _slot_local(slot)

## 座位本地槽位变换（与 _render_seat 定位一致：列 -X、行 (1-行) +Z）。
func _slot_local(slot: int) -> Transform3D:
	var grid := Table3dLayout.slot_grid_pos(slot)
	return Transform3D(Basis.IDENTITY, Vector3(
		-grid.x * (Table3dLayout.BLOCK_SIZE.x + Table3dLayout.BLOCK_GAP.x),
		0.0,
		(1.0 - grid.y) * (Table3dLayout.BLOCK_SIZE.z + Table3dLayout.BLOCK_GAP.z)))

## 中央节点世界变换（"deck" | "discard" | "pending"）。
func center_xform(kind: String) -> Transform3D:
	var node: Node3D = null
	match kind:
		"deck":
			node = _deck_node
		"discard":
			node = _discard_node
		"pending":
			node = _pending_node
	if node == null or not is_instance_valid(node):
		return Transform3D.IDENTITY
	return node.global_transform

## 槽位当前显示面是否正面（未知牌为 false）。
func slot_face_up(seat_id: int, slot: int) -> bool:
	var b = _find_block(seat_id, slot)
	return b != null and is_instance_valid(b) and (b as CardBlock).has_face_texture()

## 槽位牌面数据（render 登记；空/未知返回 {}）。
func slot_card(seat_id: int, slot: int) -> Dictionary:
	if _slot_cards.has(seat_id) and _slot_cards[seat_id].has(slot):
		return _slot_cards[seat_id][slot]
	return {}

func _mark_anim_slot(seat: int, slot: int) -> void:
	_anim_slots["%d_%d" % [seat, slot]] = true

func _unmark_anim_slot(seat: int, slot: int) -> void:
	_anim_slots.erase("%d_%d" % [seat, slot])

func _has_anim_slot(seat: int, slot: int) -> bool:
	return _anim_slots.has("%d_%d" % [seat, slot])

## 生成一张飞牌；on_land 在落地（finished）时先于重渲染调用。
func _spawn_fly(from: Transform3D, to: Transform3D, data: Dictionary,
		start_up: bool, end_up: bool, on_land := Callable()) -> CardFly:
	var f := CardFly.new()
	add_child(f)
	f.finished.connect(func():
		_flyers = _live_flyers()
		if on_land.is_valid():
			on_land.call()
		_refresh())
	f.play(from, to, data, start_up, end_up)
	_flyers.append(f)
	return f

func _live_flyers() -> Array:
	var out: Array = []
	for f in _flyers:
		if is_instance_valid(f) and (f as CardFly).is_flying():
			out.append(f)
	return out

## 用最近一次 state 重渲染（落地恢复显示）。
func _refresh() -> void:
	if _last_state.is_empty():
		return
	render(_last_state, _last_actionable)

## 切出 3D 时清空在途飞牌与标记（防残留隐藏槽）。
func _clear_exchange_anim() -> void:
	for f in _flyers:
		if is_instance_valid(f):
			f.queue_free()
	_flyers.clear()
	_anim_slots.clear()
	_discard_hold = false

func _anim_replace(data: Dictionary) -> void:
	var actor := int(data.get("actor", 0))
	var slot := int(data.get("slot", -1))
	if slot < 0:
		return
	var slot_up := slot_face_up(actor, slot)
	var from_x := slot_xform(actor, slot)
	_pending_block.visible = false
	_mark_anim_slot(actor, slot)
	_discard_hold = true
	# 旧牌 → 弃牌顶
	_spawn_fly(from_x, center_xform("discard"), data.get("old_data", {}), slot_up, true, func():
		_discard_hold = false)
	# 大牌 → 槽位（背面/正面按 viewer 是否行动者）
	_spawn_fly(center_xform("pending"), from_x, data.get("big_data", {}), _viewer == actor, slot_up, func():
		_unmark_anim_slot(actor, slot))

func _anim_swap(data: Dictionary) -> void:
	var a := int(data.get("a", 0))
	var a_slot := int(data.get("a_slot", -1))
	var b := int(data.get("b", 0))
	var b_slot := int(data.get("b_slot", -1))
	if a_slot < 0 or b_slot < 0:
		return
	var a_up := slot_face_up(a, a_slot)
	var b_up := slot_face_up(b, b_slot)
	var xa := slot_xform(a, a_slot)
	var xb := slot_xform(b, b_slot)
	_mark_anim_slot(a, a_slot)
	_mark_anim_slot(b, b_slot)
	var counter := {"n": 2}
	var done := func():
		counter["n"] = int(counter["n"]) - 1
		if int(counter["n"]) <= 0:
			_unmark_anim_slot(a, a_slot)
			_unmark_anim_slot(b, b_slot)
	_spawn_fly(xa, xb, data.get("a_data", {}), a_up, b_up, done)
	_spawn_fly(xb, xa, data.get("b_data", {}), b_up, a_up, done)

func _anim_discard(data: Dictionary) -> void:
	var actor := int(data.get("actor", 0))
	_pending_block.visible = false
	_discard_hold = true
	_spawn_fly(center_xform("pending"), center_xform("discard"), data.get("big_data", {}),
		_viewer == actor, true, func():
			_discard_hold = false)

func _anim_slap_penalty(data: Dictionary) -> void:
	var peer := int(data.get("peer", 0))
	var slot := int(data.get("slot", -1))
	if slot < 0:
		return
	var to_x := slot_xform(peer, slot)
	_mark_anim_slot(peer, slot)
	# 罚牌不含牌面 → 背面飞入
	_spawn_fly(center_xform("deck"), to_x, {}, false, false, func():
		_unmark_anim_slot(peer, slot))

func _anim_slap_resolved(data: Dictionary) -> void:
	var target := int(data.get("target", 0))
	var slot := int(data.get("target_slot", -1))
	if slot < 0:
		return
	var from_x := slot_xform(target, slot)
	_mark_anim_slot(target, slot)
	_discard_hold = true
	# 被贴的牌已公开 → 正面飞去弃牌堆
	_spawn_fly(from_x, center_xform("discard"), data.get("card", {}), true, true, func():
		_unmark_anim_slot(target, slot)
		_discard_hold = false)

func _anim_slap_gift(data: Dictionary) -> void:
	var actor := int(data.get("actor", 0))
	var own_slot := int(data.get("own_slot", -1))
	var target := int(data.get("target", 0))
	var target_slot := int(data.get("target_slot", -1))
	if own_slot < 0 or target_slot < 0:
		return
	var face_up := _viewer == actor
	var card: Dictionary = slot_card(actor, own_slot) if face_up else {}
	var from_x := slot_xform(actor, own_slot)
	var to_x := slot_xform(target, target_slot)
	_mark_anim_slot(actor, own_slot)
	_mark_anim_slot(target, target_slot)
	_spawn_fly(from_x, to_x, card, face_up, face_up, func():
		_unmark_anim_slot(actor, own_slot)
		_unmark_anim_slot(target, target_slot))
```

- [ ] **Step 9: 改 `main.gd` —— 事件处理器加 3D 分支**

把：

```gdscript
	# 3D 下不播 2D 换牌/贴牌 fly（3D 尚无这些动画，2D 副本会浮在 3D 画面上）
	GameState.card_exchange_animated.connect(func(data: Dictionary):
		if not _table3d_active:
			animator.handle_exchange(data))
```

替换为：

```gdscript
	# 2D 走 CardAnimator（原逻辑逐字不动）；3D 走 table3d 的飞牌编排。
	GameState.card_exchange_animated.connect(func(data: Dictionary):
		if _table3d_active:
			if table3d != null and is_instance_valid(table3d):
				table3d.animate_exchange(data)
		else:
			animator.handle_exchange(data))
```

- [ ] **Step 10: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_exchange.tscn`
Expected: ZERO 失败，退出码 0。

- [ ] **Step 11: 回归 3D 相关测试**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_table3d_interaction.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_fly.tscn
```
Expected: 分别 36/36、69/69、40/40，退出码 0。

- [ ] **Step 12: 确认 2D 逻辑零改动**

Run: `git diff --stat -- scripts/ui/card_animator.gd scripts/ui/game_view.gd scripts/ui/card_view.gd scripts/ui/reveal_controller.gd`
Expected: 无输出（这些文件未被修改）。

- [ ] **Step 13: 提交**

```bash
git add scripts/ui/table3d_view.gd scripts/ui/main.gd tests/verify_table3d_exchange.gd tests/verify_table3d_exchange.tscn tests/verify_table3d_exchange.gd.uid
git commit -m "feat: 3D 换牌动画接入对局（table3d_view 飞牌编排 + main 3D 分支）+ 测试"
```

（若 `tests/verify_table3d_exchange.gd.uid` 尚未生成则不加；`git status` 确认后按需 `git add`。）

---

### Task 2: 文档 + 全量回归

**Files:**
- Modify: `docs/AI_AGENT_交接说明.md`（§2 条目改写 + §8 命令 + 开发约定句）
- Modify: `docs/功能实现文档.md`（沙盒条目补"已接入" + 未来功能表更新 + 回归基准）
- Modify: `tools/run_all_tests.sh`（纳入 `verify_table3d_exchange`）
- Modify: `docs/修改日志.md`（个人追踪，**不提交**）

**Interfaces:**
- Consumes: Task 1 产物。
- Produces: 无代码接口。

- [ ] **Step 1: `tools/run_all_tests.sh` 纳入新测试**

在 `run_single "card_fly"   res://tests/verify_card_fly.tscn` 之后插入：

```bash
run_single "table3d_exchange" res://tests/verify_table3d_exchange.tscn
```

- [ ] **Step 2: 交接说明 §2 更新沙盒条目**

把 §2 中「**3D 换牌动画沙盒（分支 `feature/card-animation`…尚未接入** `main.gd`/`table3d_view`（接入方式见设计 §7）。测试 `verify_card_fly`…」这条的**末尾**改为：

```markdown
**已接入对局 3D**（分支 `feature/card-animation`）：`main.gd` 在 `card_exchange_animated` 处理器加 3D 分支 → `table3d_view.animate_exchange(data)`；编排放 `table3d_view` 内（`_anim_slots` 跨 render 隐藏在途槽位、`_discard_hold` 延迟弃牌顶、`slot_xform` 布局兜底支持未渲染新槽、`CardFly.finished` 落地后用 `_last_state` 重渲染），6 kind 与 2D 面/隐私策略逐条对齐。**2D 逻辑零改动**。测试 `verify_card_fly`（40/40）+ `verify_table3d_exchange`；设计见 `docs/superpowers/specs/2026-09-30-3d-exchange-animation-integration-design.md`。
```

- [ ] **Step 3: 交接说明 §8 新增命令**

在 `verify_card_fly` 命令之后插入：

```bash
# 3D 换牌动画接入对局（跨 render 标记/6 kind 落地恢复/隐私）
... --headless --path . res://tests/verify_table3d_exchange.tscn
```

并在同段"开发约定"句的测试清单追加 `+ verify_table3d_exchange`。

- [ ] **Step 4: 功能实现文档更新**

在「3D 换牌动画沙盒」条目末尾把"**尚未接入** `main.gd`/`table3d_view`（接入方式见设计 §7…）"改为"**已接入对局 3D**：`table3d_view.animate_exchange` + `main.gd` 3D 分支（2D 逻辑零改动）；测试 `verify_table3d_exchange`"。

并把 §二 C 表"3D 飞牌过渡接入…"一行中"但**尚未接入对局**（接入方式见设计 §7）"改为"**已接入对局 3D**（`table3d_view.animate_exchange`）"。

并在 §三 回归基准追加 `+ verify_table3d_exchange`。

- [ ] **Step 5: 全量回归**

Run: `tools/run_all_tests.sh`
Expected: 全部 PASS（0 败），含新增 `table3d_exchange`。

- [ ] **Step 6: 提交文档与脚本**

```bash
git add docs/AI_AGENT_交接说明.md docs/功能实现文档.md tools/run_all_tests.sh
git commit -m "doc: 记录 3D 换牌动画接入对局 + 纳入全量回归"
```

- [ ] **Step 7: 追加修改日志（不提交）**

向 `docs/修改日志.md` 追加本次记录（request→实现→反馈），**不执行 `git add`**。

---

## Self-Review

**1. Spec coverage：**

| Spec 节 | 对应 Task |
| --- | --- |
| §2 落点（main 分支 + table3d_view 状态/接口） | Task 1 Step 3–9 |
| §3 渲染与生命周期（登记/跳过/弃牌锁/落地刷新/set_active） | Task 1 Step 5–8 |
| §4 6 kind 映射与隐私 | Task 1 Step 8（`_anim_*`）+ 测试断言 |
| §5 边界（未渲染槽/无状态/切回 2D） | Task 1 Step 8（`slot_xform`/`animate_exchange` guard/`_clear_exchange_anim`）+ 测试 |
| §6 测试与验收 | Task 1 Step 1/10/11/12 + Task 2 Step 5 |
| §7 文件清单 | Task 1、Task 2 |
| §8 参数沿用 | 未改 `CardFlyConfig`（符合） |

无遗漏。

**2. Placeholder scan：** 无 TBD/TODO；所有步骤含完整代码。

**3. Type consistency：** `animate_exchange`/`slot_xform`/`center_xform`/`slot_face_up`/`slot_card`/`_has_anim_slot`/`_flyers`/`_anim_slots`/`_discard_hold` 在实现与测试中命名一致；`CardFly.play(start,end,data,start_up,end_up)` 与沙盒定义一致；`_slot_local` 与 `_render_seat` 定位一致。

**已知取舍**：`slap_resolved` 不主动释放 3D 揭示 hold（3D 揭示为定时自动翻回，非 2D hold 语义），故实现更简；与 2D 观感差异可接受（贴牌揭示在 3D 本就定时结束）。
