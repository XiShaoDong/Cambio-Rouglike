# Mark v2（轮盘选标）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 3D 按住 D 出四扇区轮盘（上眼/右问/下数/左叹），拖拽松 D 在准星落点放置 mark（指针=鼻子或波纹+悬浮图标），单点无标记；mark 同步、3s 消失。

**Architecture:** 纯展示层。`MarkWheel`(2D 轮盘)+`Mark3dMath.sector_for`(命中)；`Mark3D` 增 icon/`show_pointer`；`Table3dView.show_mark` 扩展并驱动鼻子；`GameState` 5 参事件 RPC；`main` D 长按轮盘。

**Tech Stack:** Godot 4.6 / GDScript；headless 测试。

## Global Constraints
- 纯展示层：不改规则/状态机/快照/`HiddenInfo`/`scripts/net/*`。
- 不改 `scenes/ui/table3d.tscn`、`Robot.blend`、2D 渲染文件。
- 新脚本跨文件引用用 `preload` 常量。
- 颜色按玩家 `players[].color`（`Table3dView._mark_color_for`）。
- 轮盘圆心=准星落点（屏幕中心）；中心中空；单点=无标记。
- 数字扇区文本 = `latest_state.discard.rank`，空 → `"-1"`。
- `show_mark` 新参带默认值（旧调用兼容）；`GameState.mark_placed` 改 5 参（同步改测试）。

---

### Task 1: `Mark3dMath.sector_for`

**Files:** Modify `scripts/ui/mark3d_math.gd`; Modify `tests/verify_mark.gd`.

**Interfaces:** Produces `Mark3dMath.sector_for(offset: Vector2, inner: float, outer: float) -> String`（`` / eye / question / number / exclaim）。

- [ ] **Step 1: 写失败测试** — `_test_math()` 末尾追加：
```gdscript
	_check("sector 上=eye", Mark3dMathScript.sector_for(Vector2(0, -1), 0.1, 1.0) == "eye")
	_check("sector 右=question", Mark3dMathScript.sector_for(Vector2(1, 0), 0.1, 1.0) == "question")
	_check("sector 下=number", Mark3dMathScript.sector_for(Vector2(0, 1), 0.1, 1.0) == "number")
	_check("sector 左=exclaim", Mark3dMathScript.sector_for(Vector2(-1, 0), 0.1, 1.0) == "exclaim")
	_check("sector 中空=''", Mark3dMathScript.sector_for(Vector2(0.02, 0), 0.1, 1.0) == "")
	_check("sector 超范围=''", Mark3dMathScript.sector_for(Vector2(2, 0), 0.1, 1.0) == "")
```
- [ ] **Step 2: 运行确认失败** — `res://tests/verify_mark.tscn` → FAIL（`sector_for` 未定义）。
- [ ] **Step 3: 实现** — `mark3d_math.gd` 末尾追加：
```gdscript
## 轮盘命中：offset=cursor-center；中空/超范围返回 ""，否则 eye(上)/question(右)/number(下)/exclaim(左)。
static func sector_for(offset: Vector2, inner: float, outer: float) -> String:
	var r := offset.length()
	if r < inner or r > outer:
		return ""
	var ang := rad_to_deg(atan2(offset.y, offset.x))  # 屏幕坐标 y 向下
	if ang >= -135.0 and ang < -45.0:
		return "eye"
	if ang >= -45.0 and ang < 45.0:
		return "question"
	if ang >= 45.0 and ang < 135.0:
		return "number"
	return "exclaim"
```
- [ ] **Step 4: 运行确认通过** — `verify_mark` → 29/29（23+6）。
- [ ] **Step 5: 提交**
```bash
git add scripts/ui/mark3d_math.gd tests/verify_mark.gd
git commit -m "feat: Mark3dMath.sector_for 轮盘命中"
```

---

### Task 2: `MarkWheel`（四扇区轮盘）

**Files:** Create `scripts/ui/mark_wheel.gd`; Modify `tests/verify_mark.gd`.

**Interfaces:** `class_name MarkWheel extends Control`；`open(center: Vector2, number_text: String)` / `close()` / `update_cursor(pos: Vector2)` / `selected() -> String`。

- [ ] **Step 1: 写失败测试** — `_run()` 加 `await _test_wheel()`；新增：
```gdscript
func _test_wheel() -> void:
	var w = load("res://scripts/ui/mark_wheel.gd").new()
	add_child(w)
	await get_tree().process_frame
	w.open(Vector2(400, 300), "5")
	var ro := w._outer_px()
	w.update_cursor(Vector2(400, 300 - ro * 0.7))
	_check("轮盘 上=eye", w.selected() == "eye")
	w.update_cursor(Vector2(400 + ro * 0.7, 300))
	_check("轮盘 右=question", w.selected() == "question")
	w.update_cursor(Vector2(400, 300 + ro * 0.7))
	_check("轮盘 下=number", w.selected() == "number")
	w.update_cursor(Vector2(400 - ro * 0.7, 300))
	_check("轮盘 左=exclaim", w.selected() == "exclaim")
	w.update_cursor(Vector2(400, 300))
	_check("轮盘 中空=''", w.selected() == "")
	_check("轮盘 数字文本", w._number_text == "5")
	w.close()
	_check("轮盘 close 隐藏", not w.visible)
	w.queue_free()
	await get_tree().process_frame
```
- [ ] **Step 2: 运行确认失败** → FAIL（文件不存在）。
- [ ] **Step 3: 实现 `scripts/ui/mark_wheel.gd`**：
```gdscript
class_name MarkWheel
extends Control
## 四扇区轮盘（上眼/右问/下数/左叹，中心中空）。纯视觉：mouse_filter=IGNORE，由 main 喂光标位置。

const Mark3dMathScript := preload("res://scripts/ui/mark3d_math.gd")

const INNER_RATIO := 0.16   # 中空内半径 = min(屏幕边)/2 * ratio
const OUTER_RATIO := 0.34
const FONT_SIZE := 28
const BG := Color(0.06, 0.07, 0.10, 0.72)
const SECTOR := Color(0.20, 0.22, 0.28, 0.85)
const SECTOR_HL := Color(0.95, 0.82, 0.35, 0.95)
const TXT := Color(0.95, 0.96, 1.0)

var _center := Vector2.ZERO
var _cursor := Vector2.ZERO
var _number_text := ""
var _selected := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func open(center: Vector2, number_text: String) -> void:
	_center = center
	_cursor = center
	_number_text = number_text
	_selected = ""
	visible = true
	queue_redraw()

func close() -> void:
	visible = false

func update_cursor(pos: Vector2) -> void:
	_cursor = pos
	_selected = Mark3dMathScript.sector_for(pos - _center, _inner_px(), _outer_px())
	queue_redraw()

func selected() -> String:
	return _selected

func _inner_px() -> float:
	return minf(size.x, size.y) * 0.5 * INNER_RATIO

func _outer_px() -> float:
	return minf(size.x, size.y) * 0.5 * OUTER_RATIO

func _draw() -> void:
	if not visible:
		return
	var inner := _inner_px()
	var outer := _outer_px()
	# 背景圆盘
	draw_circle(_center, outer, BG)
	var names := ["eye", "question", "number", "exclaim"]
	# 屏幕角：上 -90°、右 0°、下 90°、左 180°；扇区以各自角为中心 ±45°
	var base := [-90.0, 0.0, 90.0, 180.0]
	for i in 4:
		_draw_annular_sector(base[i], inner, outer, SECTOR_HL if _selected == names[i] else SECTOR)
	# 图标
	var mid := outer - (outer - inner) * 0.5
	for i in 4:
		var a := deg_to_rad(base[i])
		var p := _center + Vector2(cos(a), sin(a)) * mid
		_draw_icon(names[i], p)
	# 中空
	draw_circle(_center, inner, BG)

func _draw_annular_sector(center_deg: float, inner: float, outer: float, col: Color) -> void:
	var a0 := deg_to_rad(center_deg - 45.0)
	var a1 := deg_to_rad(center_deg + 45.0)
	var pts := PackedVector2Array()
	var steps := 20
	for k in steps + 1:
		var a := a0 + (a1 - a0) * float(k) / float(steps)
		pts.append(_center + Vector2(cos(a), sin(a)) * outer)
	for k in range(steps, -1, -1):
		var a := a0 + (a1 - a0) * float(k) / float(steps)
		pts.append(_center + Vector2(cos(a), sin(a)) * inner)
	draw_colored_polygon(pts, col)

func _draw_icon(kind: String, p: Vector2) -> void:
	var f := ThemeDB.fallback_font
	if kind == "eye":
		draw_circle(p, 10.0, TXT)
		draw_circle(p, 4.0, Color(0.1, 0.1, 0.12))
	elif kind == "number":
		var s := _number_text if not _number_text.is_empty() else "-1"
		var sz := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		draw_string(f, p - Vector2(sz.x * 0.5, -sz.y * 0.28), s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TXT)
	else:
		var s := "?" if kind == "question" else "!"
		var sz := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		draw_string(f, p - Vector2(sz.x * 0.5, -sz.y * 0.28), s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TXT)
```
- [ ] **Step 4: 运行确认通过** → 29+7=36/36。
- [ ] **Step 5: 提交**
```bash
git add scripts/ui/mark_wheel.gd tests/verify_mark.gd
git commit -m "feat: MarkWheel 四扇区轮盘"
```

---

### Task 3: `Mark3D` 图标与 `show_pointer`

**Files:** Modify `scripts/ui/mark3d.gd`; Modify `tests/verify_mark.gd`.

**Interfaces:** `Mark3D.setup(owner_dir, icon := "eye", text := "", show_pointer := true)`；`_icon_kind`；`_label`。

- [ ] **Step 1: 写失败测试** — `_run()` 加 `await _test_mark_icon()`；新增：
```gdscript
func _test_mark_icon() -> void:
	var m = Mark3DScript.new()
	add_child(m)
	await get_tree().process_frame
	m.set_process(false)
	m.setup(Vector3(1, 0, 0), "eye", "", true)
	_check("eye 用 Sprite3D", m._icon_kind == "eye" and m._eye.visible)
	m.setup(Vector3(1, 0, 0), "question", "", true)
	_check("question 用 Label3D ?", m._icon_kind == "question" and m._label.visible and m._label.text == "?")
	m.setup(Vector3(1, 0, 0), "exclaim", "", true)
	_check("exclaim 文本 !", m._label.text == "!")
	m.setup(Vector3(1, 0, 0), "number", "5", true)
	_check("number 文本 5", m._label.text == "5")
	m.setup(Vector3(1, 0, 0), "eye", "", false)
	_check("show_pointer=false 隐藏波纹/箭头", not (m._rings[0] as Node3D).visible and not m._arrow.visible)
	m.queue_free()
	await get_tree().process_frame
```
- [ ] **Step 2: 运行确认失败** → FAIL。
- [ ] **Step 3: 改 `scripts/ui/mark3d.gd`**：
  - 成员加 `var _icon_kind := "eye"`、`var _label: Label3D`。
  - `_build()` 的 eye 段改为：创建 `_eye`（Sprite3D，同现在），并创建 `_label := Label3D.new()`：`billboard=BILLBOARD_ENABLED`、`no_depth_test=true`、`pixel_size=0.004`、`font_size=64`、`position=Vector3(0,EYE_HEIGHT,0)`、`outline_size=8`、`outline_modulate=Color(0,0,0,0.6)`、`visible=false`、`add_child`。
  - 新方法：
```gdscript
func setup(owner_dir: Vector3, icon := "eye", text := "", show_pointer := true) -> void:
	_build()
	var d := Vector3(owner_dir.x, 0.0, owner_dir.z)
	if d.length_squared() < 0.000001:
		d = Vector3.FORWARD
	d = d.normalized()
	_arrow.rotation.y = atan2(d.x, d.z)
	_icon_kind = icon
	for r in _rings:
		(r as Node3D).visible = show_pointer
	_arrow.visible = show_pointer
	_eye.visible = icon == "eye"
	_label.visible = icon != "eye"
	match icon:
		"question": _label.text = "?"
		"exclaim": _label.text = "!"
		"number": _label.text = text if not text.is_empty() else "-1"
```
  - `set_color(c)`：额外 `_label.modulate = c`（并 `_label.outline_modulate = Color(0,0,0,0.6)` 保持）。
  - `_process` 里 eye bob 仅对 eye；label 不动（或同样 bob）。可保留 `_eye.position.y` bob，并给 `_label.position.y = EYE_HEIGHT`。
- [ ] **Step 4: 运行确认通过** → 36+6=42/42。
- [ ] **Step 5: 提交**
```bash
git add scripts/ui/mark3d.gd tests/verify_mark.gd
git commit -m "feat: Mark3D 多图标(眼/问/数/叹) + show_pointer"
```

---

### Task 4: `Table3dView.show_mark` 扩展（含驱动鼻子）

**Files:** Modify `scripts/ui/table3d_view.gd`; Modify `tests/verify_mark.gd`.

**Interfaces:** `Table3dView.show_mark(seat_id, pos, style := "ripple", icon := "eye", text := "")`。

- [ ] **Step 1: 写失败测试** — `_test_view()` 末尾（`clear_marks` 前）加：
```gdscript
	view._last_state = {"players": [{"id": 1, "color": "#3ABA64"}]}
	view.show_mark(1, Vector3(0.5, Table3dLayout.TABLE_HEIGHT, 0.5), "nose", "question", "")
	await get_tree().process_frame
	var nm = view._marks[1]
	_check("nose 标记隐藏波纹", not (nm._rings[0] as Node3D).visible)
	var r1 = view._seat_nodes[1].get_node("Avatar").get_node("RobotAvatar")
	_check("nose 标记驱动该席鼻子", r1._nose_target_world.is_equal_approx(Vector3(0.5, Table3dLayout.TABLE_HEIGHT, 0.5)))
```
- [ ] **Step 2: 运行确认失败** → FAIL。
- [ ] **Step 3: 改 `scripts/ui/table3d_view.gd`** `show_mark`：
```gdscript
func show_mark(seat_id: int, pos: Vector3, style := "ripple", icon := "eye", text := "") -> void:
	_bind()
	if not _bound or not pos.is_finite():
		return
	var old = _marks.get(seat_id)
	if old != null and is_instance_valid(old):
		old.queue_free()
	var mark = Mark3DScript.new()
	var owner_pos := Vector3.ZERO
	var seat_node = _seat_node_by_id.get(seat_id)
	if seat_node != null and is_instance_valid(seat_node):
		owner_pos = (seat_node as Node3D).global_position
	add_child(mark)
	mark.global_position = pos
	mark.setup(Mark3dMathScript.arrow_dir_xz(pos, owner_pos), icon, text, style != "nose")
	var col = _mark_color_for(seat_id)
	if col != null:
		mark.set_color(col)
	if style == "nose":
		_set_seat_nose_target(seat_id, pos)
	mark.finished.connect(func():
		if _marks.get(seat_id) == mark:
			_marks.erase(seat_id)
			if style == "nose":
				_set_seat_nose_target(seat_id, Vector3.ZERO))
	_marks[seat_id] = mark
```
新增 `_set_seat_nose_target`：
```gdscript
## 驱动某席鼻子到目标世界点（本机席→第一人称相机鼻；他人→其角色鼻）。
func _set_seat_nose_target(seat_id: int, pos: Vector3) -> void:
	if seat_id == _viewer:
		if pos == Vector3.ZERO:
			clear_local_nose()
		else:
			set_local_nose_target_world(pos)
		return
	var node = _seat_node_by_id.get(seat_id)
	if node == null or not is_instance_valid(node):
		return
	var robot = (node as Node3D).get_node_or_null("Avatar/RobotAvatar")
	if robot != null:
		robot.set_nose_target_world(pos)
```
`clear_marks()` 末尾加复位：对 `_marks` 里 nose 风格的席位复位鼻子（简化：遍历时记录 style；或统一对所有席 `_set_seat_nose_target(s, ZERO)` + `clear_local_nose()`）。
- [ ] **Step 4: 运行确认通过** → 42+2=44/44。回归 `verify_table3d_interaction` 76/76。
- [ ] **Step 5: 提交**
```bash
git add scripts/ui/table3d_view.gd tests/verify_mark.gd
git commit -m "feat: show_mark 支持 style/icon/text 并驱动鼻子"
```

---

### Task 5: `GameState` 5 参同步

**Files:** Modify `scripts/core/game_state.gd`; Modify `tests/verify_mark.gd`.

**Interfaces:** `mark_placed(seat,pos,style,icon,text)`；`server_mark(pos,style,icon,text)`；`_apply_mark(...)`；`receive_mark(...)`。

- [ ] **Step 1: 写失败测试** — `_test_sync()` 改为：
```gdscript
func _test_sync() -> void:
	var got: Array = []
	var cb := func(seat, pos, style, icon, text): got.append([seat, pos, style, icon, text])
	GameState.mark_placed.connect(cb)
	GameState._apply_mark(2, Vector3(1, 1, 1), "ripple", "number", "5")
	_check("_apply_mark 5 参信号", got.size() == 1 and int(got[0][0]) == 2 and str(got[0][2]) == "ripple" and str(got[0][3]) == "number" and str(got[0][4]) == "5")
	GameState._apply_mark(3, Vector3(INF, 0, 0), "nose", "eye", "")
	_check("_apply_mark 非有限忽略", got.size() == 1)
	GameState.receive_mark(4, Vector3(2, 1, 3), "nose", "exclaim", "")
	_check("receive_mark 发信号", got.size() == 2 and str(got[1][3]) == "exclaim")
	GameState.mark_placed.disconnect(cb)
```
- [ ] **Step 2: 运行确认失败** → FAIL。
- [ ] **Step 3: 改 `scripts/core/game_state.gd`**：把 `signal mark_placed` 与 `server_mark`/`_apply_mark`/`receive_mark` 改为 5 参：
```gdscript
signal mark_placed(seat: int, pos: Vector3, style: String, icon: String, text: String)

@rpc("any_peer", "call_remote", "reliable")
func server_mark(pos: Vector3, style: String, icon: String, text: String) -> void:
	var seat := _peer_to_seat(multiplayer.get_remote_sender_id())
	if seat < 0:
		return
	_apply_mark(seat, pos, style, icon, text)

func _apply_mark(seat: int, pos: Vector3, style: String, icon: String, text: String) -> void:
	if not pos.is_finite():
		return
	mark_placed.emit(seat, pos, style, icon, text)
	for s in players.keys():
		var peer := int(players[s].peer_id)
		if peer > 1:
			receive_mark.rpc_id(peer, seat, pos, style, icon, text)

@rpc("authority", "call_remote", "reliable")
func receive_mark(seat: int, pos: Vector3, style: String, icon: String, text: String) -> void:
	mark_placed.emit(seat, pos, style, icon, text)
```
- [ ] **Step 4: 运行确认通过** → 44/44。回归 `verify_protocol` 51/51。
- [ ] **Step 5: 提交**
```bash
git add scripts/core/game_state.gd tests/verify_mark.gd
git commit -m "feat: mark 同步扩展 style/icon/text"
```

---

### Task 6: `main.gd` D 长按轮盘

**Files:** Modify `scripts/ui/main.gd`.

**Interfaces:** Consumes `MarkWheel`/`Table3dPicker.ray_plane_y`/`Mark3dMath.on_table`/`GameState.server_mark`/`_apply_mark`/`mark_placed`/`Table3dView.show_mark`。

- [ ] **Step 1: 常量/成员**：preload 区加 `const MarkWheelScript := preload("res://scripts/ui/mark_wheel.gd")`；成员加 `var _wheel_open := false`、`var _wheel_pos := Vector3.ZERO`、`var _mark_wheel = null`。
- [ ] **Step 2: `_ready`**：`GameState.mark_placed.connect(_on_mark_placed)` 已有 → 签名改 5 参（见 Step 4）。
- [ ] **Step 3: 替换旧标记逻辑**：删除 `_on_mark_click()`（及 `_input` 中 `KEY_D` 调 `_on_mark_click` 的分支），改为长按轮盘：
  - `_input` 3D 键分支加（在 KEY_D 处）：
```gdscript
		if event.keycode == KEY_D:
			_open_mark_wheel()
			get_viewport().set_input_as_handled()
			return
```
  - `_input` 3D 键分支之外（处理**松开**）：
```gdscript
	if event is InputEventKey and not event.echo and event.keycode == KEY_D and not event.pressed:
		if _wheel_open:
			_finish_mark_wheel()
			get_viewport().set_input_as_handled()
		return
```
  - `_input` 顶部、`if _settings_open(): return` 之后加：轮盘打开时只处理 motion：
```gdscript
	if _wheel_open:
		if event is InputEventMouseMotion and _mark_wheel != null:
			_mark_wheel.update_cursor(event.position)
		return
```
  - `_process` 里删除 `update_noses(...)`/`_nose_target_world` 两段（鼻子改由 mark 驱动）。
- [ ] **Step 4: 新增方法**（替换 `_on_mark_click`/`_on_mark_placed`）：
```gdscript
func _open_mark_wheel() -> void:
	if _wheel_open or table3d == null or not is_instance_valid(table3d):
		return
	if _board_has_panel() or _settings_open():
		return
	var cam: Camera3D = table3d.camera.camera_node()
	if cam == null:
		return
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var pos: Vector3 = Table3dPicker.ray_plane_y(cam, center, Table3dLayout.TABLE_HEIGHT)
	if not pos.is_finite() or not Mark3dMathScript.on_table(pos, Table3dLayout.TABLE_RADIUS):
		return
	_wheel_pos = pos
	if _mark_wheel == null or not is_instance_valid(_mark_wheel):
		_mark_wheel = MarkWheelScript.new()
		add_child(_mark_wheel)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_mark_wheel.open(center, _discard_number_text())
	_wheel_open = true

func _finish_mark_wheel() -> void:
	_wheel_open = false
	var sel := ""
	if _mark_wheel != null and is_instance_valid(_mark_wheel):
		sel = _mark_wheel.selected()
		_mark_wheel.close()
	_sync_table3d_pointer()
	if sel == "":
		return
	var style := "nose" if _nose_enabled() else "ripple"
	var text := _discard_number_text() if sel == "number" else ""
	var seat := int(latest_state.get("viewer_id", -1))
	if seat < 0:
		return
	_send_mark(seat, _wheel_pos, style, sel, text)

func _send_mark(seat: int, pos: Vector3, style: String, icon: String, text: String) -> void:
	if multiplayer.is_server():
		GameState._apply_mark(seat, pos, style, icon, text)
	else:
		GameState.server_mark.rpc_id(1, pos, style, icon, text)

func _discard_number_text() -> String:
	var discard: Dictionary = latest_state.get("discard", {})
	var r := str(discard.get("rank", ""))
	return r if not r.is_empty() else "-1"

func _on_mark_placed(seat: int, pos: Vector3, style: String, icon: String, text: String) -> void:
	if _table3d_active and table3d != null and is_instance_valid(table3d):
		table3d.show_mark(seat, pos, style, icon, text)
```
  - `_set_table3d(false)` 分支加：若 `_wheel_open` 先 `_finish_mark_wheel()`（或关闭轮盘 + 复位鼠标）。
  - 数字文本：若 `latest_state.discard` 不可用时返回 `-1`。
- [ ] **Step 5: 编译 + 回归**：`verify_mark` 44/44、`verify_nose` 31/31、`verify_table3d_interaction` 76/76、`verify_table3d_exchange` 66/66。
- [ ] **Step 6: 提交**
```bash
git add scripts/ui/main.gd
git commit -m "feat: D 长按出轮盘选标 + 数字取自弃牌顶"
```

---

### Task 7: 文档 + 全量

**Files:** `docs/网络协议_V1.md`、`docs/3D角色与场景说明.md`、`docs/功能实现文档.md`、`docs/AI_AGENT_交接说明.md`.

- [ ] **Step 1**：协议 §3 `mark` 行改 `{pos,style,icon,text}`；§4.9 更新为轮盘/图标/鼻子并归。
- [ ] **Step 2**：3D 文档 §4.10 更新（轮盘交互/四图标/数字来源/style；`MarkWheel`/`sector_for` 入文件地图与参数）。
- [ ] **Step 3**：功能实现/交接说明 各补一句；验证命令加 `verify_mark`。
- [ ] **Step 4**：`tools/run_all_tests.sh --quick`（网络用例需先停掉运行中的游戏）全绿。
- [ ] **Step 5: 提交**
```bash
git add docs/
git commit -m "doc: 记录 Mark v2 轮盘选标"
```

---

## Self-Review
**Spec coverage**：轮盘→Task 2；sector→Task 1；图标/指针→Task 3；驱动鼻子→Task 4；5 参同步→Task 5；D 长按/数字→Task 6；文档→Task 7。
**Placeholder scan**：无 TBD。
**Type consistency**：`show_mark(seat,pos,style,icon,text)`（Task 4/6）；`setup(dir,icon,text,show_pointer)`（Task 3/4）；`mark_placed(5参)`（Task 5/6）；`sector_for`（Task 1/2）。
**已知取舍**：`look.nose` 保留兼容但停用（nose 改由 mark 驱动）；`update_noses` 仍保留供测试/兼容。
