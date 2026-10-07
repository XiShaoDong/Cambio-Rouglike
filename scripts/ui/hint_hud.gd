class_name HintHud
extends Control
## 3D action hint 屏幕空间面板：顶部居中的「回合倒计时胶囊 + 提示文本」。
## 纯客户端展示层，仅 3D 激活时显示；倒计时为本地纯展示（不联网、不触发规则）。
## 动画只改 position.y / modulate.a，不用 Control.scale（规避 B1 位置漂移）。

const TOP_MARGIN := 40.0
const PILL_H := 48.0
const PILL_H_PAD := 30.0
const PILL_V_PAD := 8.0
const PILL_FONT := 26
const HINT_FONT := 18
const HINT_MAX_W := 560.0
const SEP := 12.0
const RISE := 70.0
const RISE_UP := 50.0
const DROP_DUR := 0.30
const UP_DUR := 0.18
const PHASE_TURN_SECONDS := 30.0
const COLOR_NORMAL := Color(0.95, 0.97, 1.0)
const COLOR_WARN := Color(1.0, 0.78, 0.30)
const COLOR_OVER := Color(1.0, 0.36, 0.34)
## 胶囊显示 / 计时的阶段（GameState.Phase 数值）：TURN_DRAW / TURN_DECISION / Q_DECISION / SLAP_EXCHANGE / SLAP_DUEL。
## 不含 INITIAL_PEEK：进入房间直到全员 ready 后才开始计时。
const ACTIVE_PHASES := [2, 3, 4, 6, 8]

var _timer := TurnTimer.new()
var _pill: PanelContainer
var _pill_label: Label
var _hint_a: Label
var _hint_b: Label
var _cur: Label
var _next: Label
var _hint_text := ""
var _pill_x := 0.0
var _hint_base_y := 0.0
var _animating := false
var _tween: Tween = null

func _ready() -> void:
	_build()
	_layout()
	visible = false
	set_process(false)

func _process(delta: float) -> void:
	_timer.tick(delta)
	_update_pill_text()

func _build() -> void:
	if _pill != null:
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill = PanelContainer.new()
	_pill.name = "CountdownPill"
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.custom_minimum_size = Vector2(0.0, PILL_H)
	_pill.add_theme_stylebox_override("panel", _pill_style())
	_pill_label = Label.new()
	_pill_label.name = "Label"
	_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pill_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pill_label.add_theme_font_size_override("font_size", PILL_FONT)
	_pill_label.add_theme_color_override("font_color", COLOR_NORMAL)
	_pill.add_child(_pill_label)
	add_child(_pill)
	_hint_a = _make_hint_label("HintLabelA")
	_hint_b = _make_hint_label("HintLabelB")
	add_child(_hint_a)
	add_child(_hint_b)
	_cur = _hint_a
	_next = _hint_b
	_next.visible = false

func _pill_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.08, 0.09, 0.12, 0.75)
	s.set_corner_radius_all(int(PILL_H * 0.5))
	s.content_margin_left = PILL_H_PAD
	s.content_margin_right = PILL_H_PAD
	s.content_margin_top = PILL_V_PAD
	s.content_margin_bottom = PILL_V_PAD
	s.border_color = Color(0.42, 0.72, 0.95, 0.85)
	s.set_border_width_all(2)
	return s

func _make_hint_label(n: String) -> Label:
	var l := Label.new()
	l.name = n
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(HINT_MAX_W, 0.0)
	l.add_theme_font_size_override("font_size", HINT_FONT)
	l.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	return l

## 顶部居中锚点 + 按内容宽度/高度设置矩形；非动画中则把子节点落到基准位。
func _layout() -> void:
	if _pill == null:
		return
	var pill_size := _pill.get_combined_minimum_size()
	var hint_h := _cur.get_combined_minimum_size().y
	var w := maxf(pill_size.x, HINT_MAX_W)
	var h := PILL_H + SEP + hint_h
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = TOP_MARGIN
	offset_bottom = TOP_MARGIN + h
	_pill_x = (w - pill_size.x) * 0.5
	_hint_base_y = PILL_H + SEP
	if not _animating:
		_place_all()

func _place_all() -> void:
	_pill.position = Vector2(_pill_x, 0.0)
	_hint_a.position = Vector2(0.0, _hint_base_y)
	_hint_b.position = Vector2(0.0, _hint_base_y)

func _update_pill_text() -> void:
	if _pill_label == null:
		return
	_pill_label.text = str(_timer.seconds_left())
	var c := COLOR_NORMAL
	match _timer.phase():
		1:
			c = COLOR_WARN
		2:
			c = COLOR_OVER
	_pill_label.add_theme_color_override("font_color", c)

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_animating = false

func show_hud(on: bool) -> void:
	visible = on
	set_process(on)
	if on:
		_update_pill_text()
		_layout()
	else:
		_kill_tween()
		_place_all()

func set_phase_visible(phase: int) -> void:
	if _pill != null:
		_pill.visible = phase in ACTIVE_PHASES

## 把文本直接落到单片 label（吸附到干净状态，不做换字动画）。
func _commit(text: String) -> void:
	_kill_tween()
	_cur.text = text
	_hint_text = text
	_cur.visible = true
	_cur.modulate = Color(1, 1, 1, 1)
	_next.visible = false
	_next.text = ""
	_next.modulate = Color(1, 1, 1, 1)
	_layout()

## 吸附当前动画到"单片可见"的干净状态（保留当前片文本），供换字重启动画前调用。
func _snap_current() -> void:
	_kill_tween()
	_cur.visible = true
	_cur.modulate = Color(1, 1, 1, 1)
	_next.visible = false
	_next.text = ""
	_next.modulate = Color(1, 1, 1, 1)
	_layout()

func set_hint(text: String) -> void:
	if text == _hint_text and _cur.text == text:
		return
	_hint_text = text
	if not is_visible_in_tree():
		_commit(text)
		return
	if _animating:
		_snap_current()
	if _cur.text.is_empty():
		_commit(text)
		return
	_play_swap(text)

## 新回合：重置计时；直接提交最新文本到单片（不做换字），再播进场掉落。
## 避免"换字 Tween 被进场 kill 后旧片残留在顶层、且 _hint_text 已更新导致早退永久遗留"。
func reset_turn(seconds := PHASE_TURN_SECONDS, text := "") -> void:
	if text != "":
		_hint_text = text
	_timer.reset(seconds)
	_update_pill_text()
	if not is_visible_in_tree():
		return
	_commit(_hint_text)
	_play_entry()

## 每回合进场：胶囊先掉落，随后 hint 掉落（TRANS_BACK 回弹）。
func _play_entry() -> void:
	_kill_tween()
	_layout()
	_animating = true
	_pill.position = Vector2(_pill_x, -RISE)
	_cur.position = Vector2(0.0, _hint_base_y - RISE)
	_cur.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_tween = create_tween()
	_tween.tween_property(_pill, "position:y", 0.0, DROP_DUR).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_cur, "position:y", _hint_base_y, DROP_DUR).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_cur, "modulate:a", 1.0, DROP_DUR)
	_tween.finished.connect(_on_entry_done)

func _on_entry_done() -> void:
	_animating = false
	_layout()

## 换 hint：旧片上移淡出，新片从上掉落回弹。
func _play_swap(text: String) -> void:
	_kill_tween()
	var old := _cur
	var inc := _next
	inc.text = text
	inc.visible = true
	inc.modulate = Color(1.0, 1.0, 1.0, 0.0)
	old.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_layout()
	_animating = true
	inc.position = Vector2(0.0, _hint_base_y - RISE)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(inc, "position:y", _hint_base_y, DROP_DUR).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(inc, "modulate:a", 1.0, DROP_DUR)
	_tween.tween_property(old, "position:y", _hint_base_y - RISE_UP, UP_DUR).set_ease(Tween.EASE_IN)
	_tween.tween_property(old, "modulate:a", 0.0, UP_DUR)
	_tween.finished.connect(_on_swap_done.bind(old, inc))

func _on_swap_done(old: Label, inc: Label) -> void:
	if not is_instance_valid(old) or not is_instance_valid(inc):
		return
	old.visible = false
	old.text = ""
	old.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_cur = inc
	_next = old
	_animating = false
	_layout()

## 测试/调试访问器。
func pill() -> PanelContainer:
	return _pill

func pill_label() -> Label:
	return _pill_label

func timer() -> TurnTimer:
	return _timer

func cur_label() -> Label:
	return _cur

func next_label() -> Label:
	return _next

func hint_base_y() -> float:
	return _hint_base_y
