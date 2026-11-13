class_name TutorialOverlay
extends Control
## 教程引导层：进度 / 任务条 / 对话气泡 / 贴牌倒计时 / toast / 暂停菜单 / 完成卡。

signal resume_pressed
signal restart_pressed
signal skip_step_pressed
signal skip_all_pressed
signal exit_pressed
signal summary_done_pressed
signal ready_pressed

const SLAP_SECONDS := 3.0
const GLASS_BG := Color(0.05, 0.06, 0.09, 0.86)
const GLASS_BORDER := Color(1, 1, 1, 0.12)
const TEXT_MUTED := Color(1, 1, 1, 0.62)

var _progress: Label
var _title: Label
var _task_panel: PanelContainer
var _task_label: Label
var _speech_panel: PanelContainer
var _speaker: Label
var _speech_text: Label
var _continue_hint: Label
var _slap_panel: PanelContainer
var _slap_label: Label
var _slap_bar_bg: Control
var _slap_bar_fill: ColorRect
var _toast_panel: PanelContainer
var _toast: Label
var _toast_timer := 0.0
var _pause_root: Control
var _summary_root: Control
var _ready_btn: Button
var _ready_warn: Label
var _ready_warn_timer := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	_build_progress()
	_build_task()
	_build_speech()
	_build_slap()
	_build_toast()
	_build_ready()
	_build_pause()
	_build_summary()


func _glass(border := GLASS_BORDER, radius := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = GLASS_BG
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(14)
	return s


func _build_progress() -> void:
	var row := HBoxContainer.new()
	row.name = "ProgressRow"
	row.position = Vector2(24, 20)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _glass(GLASS_BORDER, 10))
	row.add_child(chip)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	chip.add_child(box)
	_progress = Label.new()
	_progress.add_theme_font_size_override("font_size", 15)
	box.add_child(_progress)
	var sep := Label.new()
	sep.text = "·"
	sep.modulate = TEXT_MUTED
	box.add_child(sep)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 15)
	_title.add_theme_color_override("font_color", UITheme.color("accent"))
	box.add_child(_title)
	var esc := Label.new()
	esc.text = "Esc 菜单"
	esc.add_theme_font_size_override("font_size", 13)
	esc.add_theme_color_override("font_color", TEXT_MUTED)
	row.add_child(esc)


func _build_task() -> void:
	_task_panel = PanelContainer.new()
	_task_panel.name = "Task"
	_task_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_task_panel.offset_left = -300
	_task_panel.offset_right = 300
	_task_panel.offset_top = 16
	_task_panel.offset_bottom = 74
	_task_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := _glass(UITheme.color("accent_soft"), 12)
	s.set_border_width_all(2)
	s.border_color = UITheme.color("accent")
	_task_panel.add_theme_stylebox_override("panel", s)
	add_child(_task_panel)
	_task_label = Label.new()
	_task_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_task_label.add_theme_font_size_override("font_size", 18)
	_task_panel.add_child(_task_label)


func _build_speech() -> void:
	_speech_panel = PanelContainer.new()
	_speech_panel.name = "Speech"
	_speech_panel.custom_minimum_size = Vector2(740, 0)
	_speech_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speech_panel.add_theme_stylebox_override("panel", _glass(GLASS_BORDER, 14))
	var holder := CenterContainer.new()
	holder.name = "SpeechHolder"
	holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -300
	holder.offset_bottom = -20
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	holder.add_child(_speech_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_speech_panel.add_child(box)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 14)
	_speaker.add_theme_color_override("font_color", UITheme.color("accent"))
	box.add_child(_speaker)
	_speech_text = Label.new()
	_speech_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech_text.custom_minimum_size = Vector2(700, 0)
	_speech_text.add_theme_font_size_override("font_size", 18)
	box.add_child(_speech_text)
	_continue_hint = Label.new()
	_continue_hint.text = "点击 / Enter 继续"
	_continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue_hint.add_theme_font_size_override("font_size", 13)
	_continue_hint.add_theme_color_override("font_color", TEXT_MUTED)
	box.add_child(_continue_hint)


func _build_slap() -> void:
	_slap_panel = PanelContainer.new()
	_slap_panel.name = "Slap"
	_slap_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_slap_panel.offset_left = -200
	_slap_panel.offset_right = 200
	_slap_panel.offset_top = 84
	_slap_panel.offset_bottom = 168
	_slap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := _glass(GLASS_BORDER, 12)
	s.set_border_width_all(2)
	_slap_panel.add_theme_stylebox_override("panel", s)
	add_child(_slap_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_slap_panel.add_child(box)
	_slap_label = Label.new()
	_slap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slap_label.add_theme_font_size_override("font_size", 18)
	box.add_child(_slap_label)
	_slap_bar_bg = Control.new()
	_slap_bar_bg.custom_minimum_size = Vector2(330, 6)
	_slap_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_slap_bar_bg)
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slap_bar_bg.add_child(bg)
	_slap_bar_fill = ColorRect.new()
	_slap_bar_fill.color = Color("87d9a1")
	_slap_bar_fill.size = Vector2(330, 6)
	_slap_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slap_bar_bg.add_child(_slap_bar_fill)
	_slap_panel.visible = false


func _build_toast() -> void:
	_toast_panel = PanelContainer.new()
	_toast_panel.name = "Toast"
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.offset_left = -270
	_toast_panel.offset_right = 270
	_toast_panel.offset_top = 180
	_toast_panel.offset_bottom = 244
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := _glass(Color("ff6b6b"), 10)
	s.set_border_width_all(1)
	_toast_panel.add_theme_stylebox_override("panel", s)
	add_child(_toast_panel)
	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.custom_minimum_size = Vector2(490, 0)
	_toast.add_theme_font_size_override("font_size", 16)
	_toast.add_theme_color_override("font_color", Color("ffb3b3"))
	_toast_panel.add_child(_toast)
	_toast_panel.visible = false


func _menu_button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 46)
	if primary:
		b.add_theme_stylebox_override("normal", _button_style(UITheme.color("accent"), UITheme.color("text_on_accent")))
		b.add_theme_stylebox_override("hover", _button_style(UITheme.color("accent_hover"), UITheme.color("text_on_accent")))
		b.add_theme_stylebox_override("pressed", _button_style(UITheme.color("accent_pressed"), UITheme.color("text_on_accent")))
		b.add_theme_color_override("font_color", UITheme.color("text_on_accent"))
		b.add_theme_color_override("font_hover_color", UITheme.color("text_on_accent"))
		b.add_theme_color_override("font_pressed_color", UITheme.color("text_on_accent"))
	b.pressed.connect(cb)
	return b


func _button_style(bg: Color, text_color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(10)
	s.set_content_margin_all(10)
	s.set_border_width_all(1)
	s.border_color = Color(1, 1, 1, 0.15)
	return s


func _build_ready() -> void:
	_ready_btn = _menu_button("READY", func(): ready_pressed.emit(), true)
	_ready_btn.name = "ReadyButton"
	_ready_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ready_btn.offset_left = -300
	_ready_btn.offset_right = -24
	_ready_btn.offset_top = -104
	_ready_btn.offset_bottom = -24
	_ready_btn.add_theme_font_size_override("font_size", 26)
	_ready_btn.visible = false
	add_child(_ready_btn)
	_ready_warn = Label.new()
	_ready_warn.name = "ReadyWarn"
	_ready_warn.set_anchors_preset(Control.PRESET_CENTER)
	_ready_warn.offset_left = -340
	_ready_warn.offset_right = 340
	_ready_warn.offset_top = -150
	_ready_warn.offset_bottom = -90
	_ready_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_warn.add_theme_font_size_override("font_size", 34)
	_ready_warn.add_theme_color_override("font_color", Color("ff4b4b"))
	_ready_warn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_ready_warn.add_theme_constant_override("outline_size", 8)
	_ready_warn.text = "先翻开下方的两张牌！"
	_ready_warn.visible = false
	_ready_warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ready_warn)


func _build_pause() -> void:
	_pause_root = Control.new()
	_pause_root.name = "Pause"
	_pause_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_root.visible = false
	add_child(_pause_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.58)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.add_theme_stylebox_override("panel", _glass(GLASS_BORDER, 16))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "教程已暂停"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	var tip := Label.new()
	tip.text = "继续后鼠标会重新捕获，移动鼠标环视，左键交互。"
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(340, 0)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_font_size_override("font_size", 13)
	tip.add_theme_color_override("font_color", TEXT_MUTED)
	box.add_child(tip)
	box.add_child(_menu_button("继续教程", func(): resume_pressed.emit(), true))
	box.add_child(_menu_button("重新开始", func(): restart_pressed.emit()))
	box.add_child(_menu_button("跳过本步", func(): skip_step_pressed.emit()))
	box.add_child(_menu_button("跳过教程", func(): skip_all_pressed.emit()))
	box.add_child(_menu_button("返回主菜单", func(): exit_pressed.emit()))


func _build_summary() -> void:
	_summary_root = Control.new()
	_summary_root.name = "Summary"
	_summary_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_summary_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_summary_root.visible = false
	_summary_root.z_index = 400
	add_child(_summary_root)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = 24
	panel.offset_bottom = 200
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _glass(UITheme.color("accent"), 16))
	_summary_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "教程完成"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UITheme.color("accent"))
	box.add_child(title)
	var body := Label.new()
	body.text = "低分获胜 · 弃牌开抢贴 · 贴错罚牌 · 超过 6 张立即结算"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(540, 0)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 15)
	box.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(_menu_button("回到主界面", func(): summary_done_pressed.emit(), true))
	row.add_child(_menu_button("重看教程", func(): restart_pressed.emit()))


func set_step(title: String, progress: String, task: String, is_talk: bool, _step_id: String) -> void:
	_progress.text = progress
	_title.text = title
	_task_label.text = task
	_task_panel.visible = not task.is_empty()
	_continue_hint.visible = is_talk and _speech_panel.visible
	if not is_talk:
		_continue_hint.visible = false


func set_speech(speaker: String, text: String, show_hint := false) -> void:
	if text.is_empty():
		_speech_panel.visible = false
		return
	_speaker.text = speaker
	_speech_text.text = text
	_speech_text.visible_characters = -1
	_continue_hint.visible = show_hint
	_speech_panel.visible = true


func set_speech_visible_chars(count: int) -> void:
	_speech_text.visible_characters = count


func hide_speech() -> void:
	_speech_panel.visible = false


func set_slap(mode: String, seconds := 0.0, total := SLAP_SECONDS) -> void:
	if mode == "off":
		_slap_panel.visible = false
		return
	_slap_panel.visible = true
	var s := _glass(GLASS_BORDER, 12)
	s.set_border_width_all(2)
	if mode == "explain":
		_slap_label.text = "SLAP OPEN · 讲解中（不计时）"
		_slap_label.add_theme_color_override("font_color", Color("87d9a1"))
		_slap_bar_bg.visible = false
		s.border_color = Color("87d9a1")
	elif mode == "timeout":
		_slap_label.text = "SLAP CLOSE"
		_slap_label.add_theme_color_override("font_color", Color("ff6b6b"))
		_slap_bar_bg.visible = false
		s.border_color = Color("ff6b6b")
	else:
		var left := maxf(seconds, 0.0)
		_slap_label.text = "SLAP OPEN · %d" % int(ceil(left))
		var col := Color("87d9a1")
		if left <= 1.0:
			col = Color("ff6b6b")
		elif left <= 2.0:
			col = Color("ffc857")
		_slap_label.add_theme_color_override("font_color", col)
		s.border_color = col
		_slap_bar_bg.visible = true
		_slap_bar_fill.color = col
		var ratio := clampf(left / maxf(total, 0.001), 0.0, 1.0)
		_slap_bar_fill.size = Vector2(330.0 * ratio, 6.0)
	_slap_panel.add_theme_stylebox_override("panel", s)


func show_toast(text: String) -> void:
	if text.is_empty():
		return
	_toast.text = text
	_toast_panel.visible = true
	_toast_timer = 2.8


func show_ready(on: bool) -> void:
	if _ready_btn != null:
		_ready_btn.visible = on


func is_over_ready(pos: Vector2) -> bool:
	if _ready_btn == null or not _ready_btn.visible:
		return false
	return Rect2(_ready_btn.global_position, _ready_btn.size).has_point(pos)


func set_task(text: String) -> void:
	_task_label.text = text
	_task_panel.visible = not text.is_empty()


func flash_ready_warning() -> void:
	if _ready_warn == null:
		return
	_ready_warn.visible = true
	_ready_warn_timer = 2.2


func show_pause(on: bool) -> void:
	_pause_root.visible = on


func show_summary(on: bool) -> void:
	_summary_root.visible = on


func is_paused_visible() -> bool:
	return _pause_root.visible


func _process(delta: float) -> void:
	if _ready_warn_timer > 0.0:
		_ready_warn_timer -= delta
		if _ready_warn_timer <= 0.0 and _ready_warn != null:
			_ready_warn.visible = false
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_panel.visible = false
