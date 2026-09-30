# 3D 换牌动画（沙盒原型）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建独立 3D 沙盒原型，锁定"换牌飞牌"手感（直线位移 + 弧线 + 翻面），覆盖 `card_exchange_animated` 全部 6 种 kind，为日后接入 `table3d_view` 打好可复用单元。

**Architecture:** 四层——`CardFlyMath`（纯函数：时长/缓动/弧线/翻面/变换合成）、`CardFlyConfig`（参数 + 校验）、`CardFly`（单张飞牌控制器，Tween 只驱动标量 `p`，每帧 `compose` 唯一写 transform）、`CardFlySandbox`（复刻对局布局 + 6 按钮演示 + `play(kind)` 测试入口）。飞牌复用 `CardBlock` 的双面几何做翻面，`card_block.gd` 零改动。

**Tech Stack:** Godot 4.6（GDScript）、ENet 无关；headless 单元测试（`--headless --path . res://tests/verify_card_fly.tscn`）。

## Global Constraints

- 引擎路径：`/Applications/Godot.app/Contents/MacOS/Godot`；所有验证均在 **headless** 下进行，**不启动 GUI**。
- **零改动**：`scripts/core/*`、`scripts/net/*`、`main.gd`、`table3d_view.gd`、`table3d_layout.gd`、`card_block.gd`、`scenes/ui/table3d.tscn`、2D 卡牌相关、现有测试。
- 命名：沿用项目 `class_name` + 蛇形字段风格；注释用中文；**不写 emoji**。
- 纯函数层（`CardFlyMath`/`CardFlyConfig`）不得依赖任何节点，保证 headless 可测。
- 复用既有常量：`Table3dLayout.BLOCK_SIZE/BLOCK_GAP/SEAT_RADIUS/seat_angles/slot_grid_pos`。
- 提交信息按 `feat:` / `doc:` 分类（项目约定）。

---

### Task 1: CardFlyConfig（参数 + 校验）

**Files:**
- Create: `scripts/ui/card_fly_config.gd`
- Test: `tests/verify_card_fly.gd`、`tests/verify_card_fly.tscn`

**Interfaces:**
- Produces: `class_name CardFlyConfig`（`RefCounted`）；字段 `duration_base, duration_per_dist, duration_min, duration_max, arc_height, flip_start, flip_end`；方法 `to_dict() -> Dictionary`、`validate() -> Array`；常量 `KEYS: Array`。

- [ ] **Step 1: 写失败测试**

创建 `tests/verify_card_fly.gd`：

```gdscript
extends Node
## headless 单元测试：3D 换牌飞牌（配置 / 纯数学 / 控制器 / 沙盒）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== CARD FLY RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_config()

func _test_config() -> void:
	var c := CardFlyConfig.new()
	_check("config 默认值合法", c.validate().is_empty())
	_check("config to_dict 键数", c.to_dict().size() == CardFlyConfig.KEYS.size())
	_check("config 默认 arc_height", is_equal_approx(c.arc_height, 0.35))
	var bad := CardFlyConfig.new()
	bad.arc_height = -1.0
	_check("config 非法值被抓", bad.validate().has("arc_height"))
	var swapped := CardFlyConfig.new()
	swapped.flip_start = 0.9
	swapped.flip_end = 0.2
	_check("flip_start > flip_end 被抓", swapped.validate().has("flip_start"))
```

创建 `tests/verify_card_fly.tscn`：

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/verify_card_fly.gd" id="1_test"]

[node name="VerifyCardFly" type="Node"]
script = ExtResource("1_test")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_fly.tscn`
Expected: 失败（`CardFlyConfig` 未定义 → 脚本解析错误，非 0 退出）。

- [ ] **Step 3: 实现 CardFlyConfig**

创建 `scripts/ui/card_fly_config.gd`：

```gdscript
class_name CardFlyConfig
extends RefCounted
## 3D 换牌飞牌参数（集中配置；代码不出现散落魔法数）。
## 控制器与纯数学均按 to_dict() 访问。

var duration_base := 0.30
var duration_per_dist := 0.002
var duration_min := 0.30
var duration_max := 0.90
var arc_height := 0.35
var flip_start := 0.35
var flip_end := 0.65

const KEYS := [
	"duration_base", "duration_per_dist", "duration_min", "duration_max",
	"arc_height", "flip_start", "flip_end",
]

func to_dict() -> Dictionary:
	var d := {}
	for k in KEYS:
		d[k] = get(k)
	return d

## 字段值是否全部有限且非负，且 flip_start <= flip_end；返回非法/不一致字段名数组。
func validate() -> Array:
	var bad: Array = []
	for k in KEYS:
		var v := float(get(k))
		if not is_finite(v) or v < 0.0:
			bad.append(k)
	if flip_start > flip_end and not bad.has("flip_start"):
		bad.append("flip_start")
	return bad
```

- [ ] **Step 4: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_fly.tscn`
Expected: `=== CARD FLY RESULT: 5/5 passed ===`，退出码 0。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/card_fly_config.gd tests/verify_card_fly.gd tests/verify_card_fly.tscn
git commit -m "feat: 3D 换牌飞牌参数配置 CardFlyConfig + 测试"
```

---

### Task 2: CardFlyMath（纯函数）

**Files:**
- Create: `scripts/ui/card_fly_math.gd`
- Test: `tests/verify_card_fly.gd`（新增 `_test_math`）

**Interfaces:**
- Consumes: `CardFlyConfig.to_dict()` 的键（Task 1）。
- Produces: `class_name CardFlyMath`（`RefCounted`）；静态方法
  `ease_in_out_cubic(t: float) -> float`、
  `smoothstep(t: float) -> float`、
  `duration_for(dist: float, cfg: Dictionary) -> float`、
  `path_t(p: float, cfg := {}) -> float`、
  `arc_lift(p: float, cfg: Dictionary) -> float`、
  `flip_t(p: float, cfg: Dictionary) -> float`、
  `compose(start: Transform3D, end: Transform3D, p: float, roll_start_deg: float, roll_delta_deg: float, cfg: Dictionary) -> Dictionary`（返回 `{"origin": Vector3, "basis": Basis}`）。

- [ ] **Step 1: 写失败测试**

在 `tests/verify_card_fly.gd` 的 `_run()` 末尾追加 `	_test_math()`，并新增函数：

```gdscript
func _test_math() -> void:
	var cfg := CardFlyConfig.new().to_dict()
	_check("duration 短距取下限", is_equal_approx(CardFlyMath.duration_for(0.0, cfg), cfg["duration_min"]))
	_check("duration 长距取上限", is_equal_approx(CardFlyMath.duration_for(1000.0, cfg), cfg["duration_max"]))
	_check("duration 中距单调不减", CardFlyMath.duration_for(100.0, cfg) <= CardFlyMath.duration_for(300.0, cfg))
	_check("ease_in_out_cubic 端点", is_equal_approx(CardFlyMath.ease_in_out_cubic(0.0), 0.0) and is_equal_approx(CardFlyMath.ease_in_out_cubic(1.0), 1.0))
	_check("smoothstep 端点", is_equal_approx(CardFlyMath.smoothstep(0.0), 0.0) and is_equal_approx(CardFlyMath.smoothstep(1.0), 1.0))
	_check("arc p=0 ≈0", absf(CardFlyMath.arc_lift(0.0, cfg)) < 0.0001)
	_check("arc p=1 ≈0", absf(CardFlyMath.arc_lift(1.0, cfg)) < 0.0001)
	_check("arc p=0.5 峰值", is_equal_approx(CardFlyMath.arc_lift(0.5, cfg), cfg["arc_height"]))
	_check("flip_t 窗口前=0", is_equal_approx(CardFlyMath.flip_t(0.0, cfg), 0.0))
	_check("flip_t 窗口后=1", is_equal_approx(CardFlyMath.flip_t(1.0, cfg), 1.0))
	_check("flip_t 窗口内单调", CardFlyMath.flip_t(0.4, cfg) < CardFlyMath.flip_t(0.6, cfg))
	var s := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.03, 0.0))
	var e := Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)), Vector3(2.0, 0.03, 1.0))
	var c0 := CardFlyMath.compose(s, e, 0.0, 0.0, 180.0, cfg)
	_check("compose p=0 起点", c0["origin"].distance_to(s.origin) < 0.0001)
	var c1 := CardFlyMath.compose(s, e, 1.0, 0.0, 180.0, cfg)
	_check("compose p=1 终点", c1["origin"].distance_to(e.origin) < 0.0001)
	var cm := CardFlyMath.compose(s, e, 0.5, 0.0, 180.0, cfg)
	_check("compose p=0.5 抬升", cm["origin"].y > s.origin.y + 0.1)
	# 无额外滚转时：p=1 的 basis 与 end 一致
	var n0 := CardFlyMath.compose(s, e, 1.0, 0.0, 0.0, cfg)
	_check("roll_delta=0 终点 basis=end", n0["basis"].is_equal_approx(e.basis))
	# roll_start=180 把正面法线翻到朝下
	var r0 := CardFlyMath.compose(s, e, 0.0, 0.0, 0.0, cfg)
	var r180 := CardFlyMath.compose(s, e, 0.0, 180.0, 0.0, cfg)
	_check("roll_start=180 法线反向", (r0["basis"] * Vector3(0.0, 1.0, 0.0)).dot(r180["basis"] * Vector3(0.0, 1.0, 0.0)) < 0.0)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_fly.tscn`
Expected: 失败（`CardFlyMath` 未定义 → 解析错误，非 0 退出）。

- [ ] **Step 3: 实现 CardFlyMath**

创建 `scripts/ui/card_fly_math.gd`：

```gdscript
class_name CardFlyMath
extends RefCounted
## 3D 换牌飞牌纯数学：时长 / 路径缓动 / 弧线 / 翻面 / 变换合成。
## 无节点依赖 → headless 可测。唯一写 transform 处由控制器调用 compose 完成。

static func ease_in_out_cubic(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if t < 0.5:
		return 4.0 * t * t * t
	return 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0

static func smoothstep(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## 距离 → 时长（秒）。与 2D CardAnimator._fly 同量级。
static func duration_for(dist: float, cfg: Dictionary) -> float:
	return clampf(float(cfg["duration_base"]) + dist * float(cfg["duration_per_dist"]),
		float(cfg["duration_min"]), float(cfg["duration_max"]))

## 路径进度 = 缓动(p)。
static func path_t(p: float, _cfg: Dictionary = {}) -> float:
	return ease_in_out_cubic(p)

## 弧线抬升：世界 +Y 偏移 = arc_height * sin(p*PI)（起止为 0，p=0.5 峰值）。
static func arc_lift(p: float, cfg: Dictionary) -> float:
	return float(cfg["arc_height"]) * sin(clampf(p, 0.0, 1.0) * PI)

## 翻面进度：p 落在 [flip_start, flip_end] 内 smoothstep 0→1，窗口外夹取。
static func flip_t(p: float, cfg: Dictionary) -> float:
	var a := float(cfg["flip_start"])
	var b := float(cfg["flip_end"])
	if b <= a:
		return 1.0 if p >= b else 0.0
	return smoothstep((p - a) / (b - a))

## 合成：起止世界变换 + p + 滚转偏置 → {origin, basis}。
## roll_start_deg：起始面为背面时传 180，否则 0；roll_delta_deg：起面≠终面时传 180，否则 0。
static func compose(start: Transform3D, end: Transform3D, p: float,
		roll_start_deg: float, roll_delta_deg: float, cfg: Dictionary) -> Dictionary:
	var t := path_t(p)
	var origin := start.origin.lerp(end.origin, t)
	origin.y += arc_lift(p, cfg)
	var basis := start.basis.slerp(end.basis, t)
	var roll := deg_to_rad(roll_start_deg + roll_delta_deg * flip_t(p, cfg))
	basis = basis * Basis(Vector3(0.0, 0.0, 1.0), roll)
	return {"origin": origin, "basis": basis}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_fly.tscn`
Expected: `=== CARD FLY RESULT: 20/20 passed ===`，退出码 0。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/card_fly_math.gd tests/verify_card_fly.gd
git commit -m "feat: 3D 换牌飞牌纯数学 CardFlyMath + 测试"
```

---

### Task 3: CardFly（单张飞牌控制器）

**Files:**
- Create: `scripts/ui/card_fly.gd`
- Test: `tests/verify_card_fly.gd`（新增 `_test_controller`）

**Interfaces:**
- Consumes: `CardFlyMath.compose(...)`、`CardFlyMath.duration_for(...)`（Task 2）；`CardBlock`（既有）。
- Produces: `class_name CardFly`（`Node3D`）；信号 `finished`；方法
  `play(start: Transform3D, end: Transform3D, card_data: Dictionary, start_face_up: bool, end_face_up: bool) -> void`、
  `progress() -> float`、`is_flying() -> bool`、`card_block() -> CardBlock`；字段 `config: CardFlyConfig`。

- [ ] **Step 1: 写失败测试**

在 `tests/verify_card_fly.gd` 的 `_run()` 末尾追加 `	await _test_controller()`，并新增函数：

```gdscript
func _test_controller() -> void:
	var fly := CardFly.new()
	add_child(fly)
	var s := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.03, 0.0))
	var e := Transform3D(Basis.IDENTITY, Vector3(2.0, 0.03, 1.0))
	var done := {"v": false}
	fly.finished.connect(func(): done["v"] = true)
	fly.play(s, e, {"rank": "A", "suit": "♥"}, true, true)
	_check("play 后在飞", fly.is_flying() and fly.progress() == 0.0)
	await get_tree().create_timer(1.2).timeout
	_check("飞完 finished 触发", done["v"])
	_check("飞完节点已释放", not is_instance_valid(fly))
	# 空 data 显示卡背（标签为空）
	var back := CardFly.new()
	add_child(back)
	back.play(s, e, {}, false, false)
	_check("空 data 背面无标签", back.card_block() != null and back.card_block().label_text() == "")
	back.queue_free()
	# 背面起飞：初始已滚转 180°（正面法线朝下）
	var flip := CardFly.new()
	add_child(flip)
	flip.play(s, e, {"rank": "Q", "suit": "♦"}, false, true)
	_check("背面起飞法线朝下", (flip.global_transform.basis * Vector3(0.0, 1.0, 0.0)).y < 0.0)
	flip.queue_free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_fly.tscn`
Expected: 失败（`CardFly` 未定义 → 解析错误，非 0 退出）。

- [ ] **Step 3: 实现 CardFly**

创建 `scripts/ui/card_fly.gd`：

```gdscript
class_name CardFly
extends Node3D
## 单张飞牌控制器：Tween 只驱动标量 p，每帧 compose 唯一写 transform。
## 纯展示层：不做规则/隐私判断。复用 CardBlock 双面几何做翻面（不改 card_block.gd）。

signal finished

var config: CardFlyConfig = CardFlyConfig.new()
var body: CardBlock

var _p := 0.0
var _flying := false
var _start := Transform3D.IDENTITY
var _end := Transform3D.IDENTITY
var _roll_start := 0.0
var _roll_delta := 0.0
var _tween: Tween = null

func play(start: Transform3D, end: Transform3D, card_data: Dictionary,
		start_face_up: bool, end_face_up: bool) -> void:
	_build()
	_start = start
	_end = end
	_roll_start = 0.0 if start_face_up else 180.0
	_roll_delta = 0.0 if start_face_up == end_face_up else 180.0
	_p = 0.0
	_flying = true
	body.setup({"card": card_data} if not card_data.is_empty() else {})
	_apply()
	var dur := CardFlyMath.duration_for(start.origin.distance_to(end.origin), config.to_dict())
	set_process(true)
	_tween = create_tween()
	_tween.tween_property(self, "_p", 1.0, dur).set_trans(Tween.TRANS_LINEAR)
	_tween.finished.connect(_on_done)

func _build() -> void:
	if body != null:
		return
	body = CardBlock.new()
	body.name = "CardBody"
	add_child(body)
	body.set_pick_enabled(false)

func _apply() -> void:
	if body == null:
		return
	var c := CardFlyMath.compose(_start, _end, _p, _roll_start, _roll_delta, config.to_dict())
	global_transform = Transform3D(c["basis"], c["origin"])

func _process(_delta: float) -> void:
	_apply()

func _on_done() -> void:
	_flying = false
	set_process(false)
	_apply()
	finished.emit()
	queue_free()

func progress() -> float:
	return _p

func is_flying() -> bool:
	return _flying

func card_block() -> CardBlock:
	return body
```

- [ ] **Step 4: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_fly.tscn`
Expected: `=== CARD FLY RESULT: 25/25 passed ===`，退出码 0。

- [ ] **Step 5: 提交**

```bash
git add scripts/ui/card_fly.gd tests/verify_card_fly.gd
git commit -m "feat: 3D 换牌飞牌控制器 CardFly + 测试"
```

---

### Task 4: CardFlySandbox（场景 + 脚本 + 6 kind 演示）

**Files:**
- Create: `scripts/ui/card_fly_sandbox.gd`
- Create: `scenes/ui/card_fly_sandbox.tscn`
- Test: `tests/verify_card_fly.gd`（新增 `_test_sandbox`）

**Interfaces:**
- Consumes: `CardFly`（Task 3）、`Table3dLayout`（既有）、`Table3dCamera`（既有）。
- Produces: `class_name CardFlySandbox`（`Node3D`）；常量 `KIND_ORDER: Array`；方法
  `play(kind: String) -> void`、`flying_count() -> int`。

- [ ] **Step 1: 写失败测试**

在 `tests/verify_card_fly.gd` 的 `_run()` 末尾追加 `	await _test_sandbox()`，并新增函数：

```gdscript
func _test_sandbox() -> void:
	var sandbox = load("res://scenes/ui/card_fly_sandbox.tscn").instantiate()
	add_child(sandbox)
	await get_tree().process_frame
	_check("沙盒实例化", sandbox != null and sandbox.get_node_or_null("CameraRig") != null)
	for kind in CardFlySandbox.KIND_ORDER:
		sandbox.play(kind)
		_check("play %s 有飞牌" % kind, sandbox.flying_count() > 0)
		await get_tree().create_timer(1.2).timeout
		_check("play %s 结束无残留" % kind, sandbox.flying_count() == 0)
	sandbox.queue_free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_fly.tscn`
Expected: 失败（场景/脚本不存在 → 加载失败，非 0 退出）。

- [ ] **Step 3: 实现沙盒脚本**

创建 `scripts/ui/card_fly_sandbox.gd`：

```gdscript
class_name CardFlySandbox
extends Node3D
## 3D 换牌动画沙盒：复刻对局布局（4 座位手牌区 + 中央抽牌堆/弃牌堆/大牌位），
## 顶部 6 个按钮分别触发 6 种 card_exchange_animated kind。
## 纯展示原型：不接游戏逻辑/协议/快照。

const SAMPLE_CARDS := [
	{"rank": "A", "suit": "♥"},
	{"rank": "K", "suit": "♠"},
	{"rank": "Q", "suit": "♦"},
	{"rank": "J", "suit": "♣"},
	{"rank": "10", "suit": "♥"},
	{"rank": "9", "suit": "♠"},
]
const KIND_ORDER := ["replace", "swap", "discard", "slap_penalty", "slap_resolved", "slap_gift"]
const SEAT_COUNT := 4
const CARDS_PER_SEAT := 4
const DECK_POS := Vector3(0.0, 0.03, 0.0)
const DISCARD_POS := Vector3(0.9, 0.03, 0.0)
const PENDING_POS := Vector3(0.0, 0.05, 0.0)
const PENDING_CARD := {"rank": "8", "suit": "♠"}

var camera: Table3dCamera
var _seat_nodes: Array = []
var _seat_blocks := {}
var _deck: Node3D
var _discard: Node3D
var _pending: Node3D
var _flying: Array = []
var _hidden := {}
var _hud: Label

func _ready() -> void:
	_build()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build() -> void:
	if not _seat_nodes.is_empty():
		return
	camera = get_node_or_null("CameraRig")
	_deck = _make_center("Deck", DECK_POS, {})
	_discard = _make_center("DiscardTop", DISCARD_POS, {"rank": "3", "suit": "♥"})
	_pending = _make_center("Pending", PENDING_POS, PENDING_CARD)
	var angles := Table3dLayout.seat_angles(SEAT_COUNT)
	for i in SEAT_COUNT:
		var a := float(angles[i])
		var node := Node3D.new()
		node.name = "Seat%d" % i
		add_child(node)
		node.position = Vector3(sin(deg_to_rad(a)), 0.0, cos(deg_to_rad(a))) * Table3dLayout.SEAT_RADIUS
		node.rotation_degrees = Vector3(0.0, a + 180.0, 0.0)
		_seat_nodes.append(node)
		_seat_blocks[i] = {}
		for slot in CARDS_PER_SEAT:
			var block := CardBlock.new()
			var grid := Table3dLayout.slot_grid_pos(slot)
			block.position = Vector3(
				-grid.x * (Table3dLayout.BLOCK_SIZE.x + Table3dLayout.BLOCK_GAP.x),
				0.0,
				(1.0 - grid.y) * (Table3dLayout.BLOCK_SIZE.z + Table3dLayout.BLOCK_GAP.z))
			node.add_child(block)
			block.setup({"card": SAMPLE_CARDS[(i * CARDS_PER_SEAT + slot) % SAMPLE_CARDS.size()]})
			_seat_blocks[i][slot] = block
	_build_ui()

func _make_center(node_name: String, pos: Vector3, card: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = pos
	add_child(node)
	var block := CardBlock.new()
	node.add_child(block)
	block.setup({"card": card} if not card.is_empty() else {})
	return node

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.position = Vector2(12.0, 8.0)
	layer.add_child(row)
	for kind in KIND_ORDER:
		var b := Button.new()
		b.text = kind
		b.pressed.connect(play.bind(kind))
		row.add_child(b)
	var reset := Button.new()
	reset.text = "reset"
	reset.pressed.connect(_reset)
	row.add_child(reset)
	_hud = Label.new()
	_hud.name = "Hud"
	_hud.position = Vector2(12.0, 48.0)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	layer.add_child(_hud)

func _process(_delta: float) -> void:
	if _hud != null:
		_hud.text = "在途飞牌: %d" % flying_count()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and camera != null:
		camera.look(event.relative)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## 触发某一 kind 的演示。
func play(kind: String) -> void:
	match kind:
		"replace":
			_play_replace()
		"swap":
			_play_swap()
		"discard":
			_hide(_pending.get_child(0))
			_fly(_pending.global_transform, _discard.global_transform, PENDING_CARD, true, true)
		"slap_penalty":
			_fly(_deck.global_transform, _seat_slot_xform(1, CARDS_PER_SEAT), {}, false, false)
		"slap_resolved":
			_hide(_seat_blocks[2][0])
			_fly(_seat_slot_xform(2, 0), _discard.global_transform, SAMPLE_CARDS[2], true, true)
		"slap_gift":
			_hide(_seat_blocks[0][2])
			_fly(_seat_slot_xform(0, 2), _seat_slot_xform(3, 2), {}, false, false)

func _play_replace() -> void:
	_hide(_seat_blocks[0][0])
	_fly(_seat_slot_xform(0, 0), _discard.global_transform, SAMPLE_CARDS[0], true, true)
	_fly(_deck.global_transform, _seat_slot_xform(0, 0), {"rank": "7", "suit": "♦"}, false, true)

func _play_swap() -> void:
	_hide(_seat_blocks[0][1])
	_hide(_seat_blocks[1][1])
	_fly(_seat_slot_xform(0, 1), _seat_slot_xform(1, 1), SAMPLE_CARDS[1], true, true)
	_fly(_seat_slot_xform(1, 1), _seat_slot_xform(0, 1), SAMPLE_CARDS[5], true, true)

func _reset() -> void:
	for f in _flying:
		if is_instance_valid(f):
			f.queue_free()
	_flying.clear()
	_restore_hidden()

## 座位槽位的世界变换（不依赖该槽是否已渲染）。
func _seat_slot_xform(seat: int, slot: int) -> Transform3D:
	var node: Node3D = _seat_nodes[seat]
	var grid := Table3dLayout.slot_grid_pos(slot)
	var local := Transform3D(Basis.IDENTITY, Vector3(
		-grid.x * (Table3dLayout.BLOCK_SIZE.x + Table3dLayout.BLOCK_GAP.x),
		0.0,
		(1.0 - grid.y) * (Table3dLayout.BLOCK_SIZE.z + Table3dLayout.BLOCK_GAP.z)))
	return node.global_transform * local

func _fly(from: Transform3D, to: Transform3D, data: Dictionary, start_up: bool, end_up: bool) -> CardFly:
	var f := CardFly.new()
	add_child(f)
	f.finished.connect(_on_flyer_done)
	f.play(from, to, data, start_up, end_up)
	_flying.append(f)
	return f

func _on_flyer_done() -> void:
	_flying = _live_flying()
	if _flying.is_empty():
		_restore_hidden()

func _live_flying() -> Array:
	var out: Array = []
	for f in _flying:
		if is_instance_valid(f) and (f as CardFly).is_flying():
			out.append(f)
	return out

func flying_count() -> int:
	return _live_flying().size()

func _hide(block) -> void:
	if block == null or not is_instance_valid(block):
		return
	_hidden[block] = true
	block.visible = false

func _restore_hidden() -> void:
	for b in _hidden.keys():
		if is_instance_valid(b):
			b.visible = true
	_hidden.clear()
```

- [ ] **Step 4: 实现沙盒场景**

创建 `scenes/ui/card_fly_sandbox.tscn`：

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/ui/card_fly_sandbox.gd" id="1_sandbox"]
[ext_resource type="Script" path="res://scripts/ui/table3d_camera.gd" id="2_cam"]

[sub_resource type="Environment" id="Environment_1"]
background_mode = 1
background_color = Color(0.07, 0.08, 0.1, 1)
ambient_light_source = 2
ambient_light_color = Color(1, 1, 1, 1)
ambient_light_energy = 1.2

[sub_resource type="StandardMaterial3D" id="TableMat"]
albedo_color = Color(0.16, 0.18, 0.22, 1)

[sub_resource type="BoxMesh" id="TableMesh"]
size = Vector3(7, 0.08, 7)

[node name="CardFlySandbox" type="Node3D"]
script = ExtResource("1_sandbox")

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_1")

[node name="CameraRig" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 3.5, 3.9)
script = ExtResource("2_cam")
EYE_HEIGHT = 3.5
CAMERA_BACK = 1.5
MOUSE_SENSITIVITY = 0.35

[node name="PitchPivot" type="Node3D" parent="CameraRig"]

[node name="Camera3D" type="Camera3D" parent="CameraRig/PitchPivot"]

[node name="Table" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.04, 0)
material_override = SubResource("TableMat")
mesh = SubResource("TableMesh")
```

- [ ] **Step 5: 跑测试确认通过**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/verify_card_fly.tscn`
Expected: `=== CARD FLY RESULT: 38/38 passed ===`，退出码 0（数字以实际打印为准，必须 0 失败）。

- [ ] **Step 6: 提交**

```bash
git add scripts/ui/card_fly_sandbox.gd scenes/ui/card_fly_sandbox.tscn tests/verify_card_fly.gd
git commit -m "feat: 3D 换牌动画沙盒（复刻布局 + 6 kind 演示）+ 测试"
```

---

### Task 5: 文档更新 + 全量回归

**Files:**
- Modify: `docs/AI_AGENT_交接说明.md`（§2 当前基线新增一条；§4 文件表新增三行；§8 验证命令新增一条）
- Modify: `docs/功能实现文档.md`（文件树 + 相应 Feature 映射，按现有格式）
- Modify: `docs/修改日志.md`（开发者个人追踪，**不提交**）

**Interfaces:**
- Consumes: Task 1–4 全部产物。
- Produces: 无代码接口。

- [ ] **Step 1: 新增测试命令记录到交接说明 §8**

在 `docs/AI_AGENT_交接说明.md` 第 8 节代码块末尾（`verify_card_animation` 一行之后）加入：

```bash
# 3D 换牌动画沙盒（配置/纯数学/控制器/沙盒；ready 后打印实际总数）
... --headless --path . res://tests/verify_card_fly.tscn
```

并在同段末尾"开发约定"句的测试清单中追加 `+ verify_card_fly`。

- [ ] **Step 2: 在 §2 当前基线新增一条**

在 §2 末尾（`3D 静态骨架`/`卡牌贴图分辨率坑` 等条目附近，按其格式）加入：

```markdown
- **3D 换牌动画沙盒（分支 `feature/card-animation`，纯客户端展示层，规则/协议/快照零改动）**：独立 3D 沙盒原型 `scripts/ui/card_fly_sandbox.gd` + `scenes/ui/card_fly_sandbox.tscn`（复刻对局布局：4 座位手牌区 + 中央 `Deck`/`DiscardTop`/`Pending`），顶部 6 按钮分别演示 `card_exchange_animated` 的 6 种 kind。四层架构：`card_fly_math.gd`（纯函数：距离→时长 / 路径缓动 / `sin(p*PI)` 弧线 / 翻面窗口 / `compose` 变换合成）+ `card_fly_config.gd`（参数 + 校验）+ `card_fly.gd`（单张飞牌控制器：Tween 只驱动标量 `p`，每帧 `compose` 唯一写 transform；复用 `CardBlock` 双面几何绕卡长轴翻面，**不改 `card_block.gd`**；结束发 `finished` 并 `queue_free`）。**尚未接入** `main.gd`/`table3d_view`（接入方式见设计 §7）。测试 `verify_card_fly`。
```

- [ ] **Step 3: 在 §4 服务器权威子系统/UI 层文件表新增三行**

在 `docs/AI_AGENT_交接说明.md` §4 的 UI 层表格末尾加入：

```markdown
| `card_fly_math.gd` | **纯函数**：3D 换牌飞牌时长/缓动/弧线/翻面/变换合成 |
| `card_fly.gd` | 3D 单张飞牌控制器（标量 `p` + 每帧 compose 写 transform + `finished`） |
| `card_fly_sandbox.gd` + `scenes/ui/card_fly_sandbox.tscn` | 3D 换牌动画沙盒（复刻对局布局 + 6 kind 按钮；纯展示，未接入对局） |
```

- [ ] **Step 4: 更新 `docs/功能实现文档.md`**

按该文档既有格式，在文件树/Feature 映射处补上 4 个新文件与 1 个新场景，并把"待开发清单"中与 3D 换牌动画相关的条目标注为"沙盒原型已完成，未接入"。

- [ ] **Step 5: 全量回归**

Run: `tools/run_all_tests.sh`
Expected: 全部 PASS（含新增 `verify_card_fly`）。

- [ ] **Step 6: 提交文档**

```bash
git add docs/AI_AGENT_交接说明.md docs/功能实现文档.md
git commit -m "doc: 记录 3D 换牌动画沙盒原型"
```

- [ ] **Step 7: 追加修改日志（不提交）**

向 `docs/修改日志.md`（gitignore，开发者个人追踪）按 `request → 实现 → 反馈` 追加本次记录，**不执行 `git add`**。

---

## Self-Review

**1. Spec coverage：**

| Spec 节 | 对应 Task |
| --- | --- |
| §1 目标（4 层 / 复刻布局 / 6 kind / 参数集中 / 纯函数可测） | Task 1–4 |
| §2 架构与文件 / 节点结构 | Task 3（CardFly 结构）、Task 4（沙盒布局） |
| §3 飞行数学与翻面（duration/path/arc/flip/compose + 滚转偏置表） | Task 2 |
| §4 CardFly API 与面显示约定 | Task 3 |
| §5 沙盒场景、输入、6 kind 映射、API | Task 4 |
| §6 测试与验收 | Task 1–4（测试）+ Task 5（全量回归） |
| §7 移植说明（本次不做） | 不在计划内（明确非目标） |
| §8 参数默认值 | Task 1（CardFlyConfig 默认值） |
| §9 文件清单 | Task 1–4 |

无遗漏。

**2. Placeholder scan：** 无 TBD/TODO；所有代码步骤均给出完整可运行代码。

**3. Type consistency：** `CardFlyMath.compose` 六参签名在 Task 2/3/4 一致；`CardFlyConfig.KEYS` 与 `to_dict()` 键在 Task 1/2/4 一致；`CardFly.play/progress/is_flying/card_block` 与 `CardFlySandbox.play/flying_count/KIND_ORDER` 在 Task 3/4 一致。`_seat_slot_xform` 与 `table3d_view._render_seat` 的本地坐标换算方向一致（列 `-X`、行 `(1-行)` 的 `+Z`）。

**已知取舍**：`CardFlyMath.arc_lift` 用原始 `p`（非 `path_t`），与设计 §3 一致；弧线时间包络与水平缓动略有差异，为可接受的原型观感。

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-30-3d-exchange-animation-sandbox.md`.
