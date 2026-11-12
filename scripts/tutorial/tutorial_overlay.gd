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
