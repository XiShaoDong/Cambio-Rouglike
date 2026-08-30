class_name SettingsMenu
extends Control
## 设置菜单（ESC 呼出，全屏遮罩 + 居中面板）
## 职责：读写 Settings 的编辑器界面；当前管理 音量/静音/主题/语言。
## 对齐 duel_bar 弹窗模式：_build_ui 开头先 PRESET_FULL_RECT（防 B9 尺寸为 0）。
## 文案走 Loc.t(key)，控件用 meta "text_key" 记录键，语言切换时统一重刷。

var _dim: ColorRect
var _panel: PanelContainer
var _volume_slider: HSlider
var _volume_label: Label
var _mute_check: CheckButton
var _theme_option: OptionButton
var _lang_option: OptionButton

func _ready() -> void:
	z_index = 100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	Loc.language_changed.connect(_refresh_texts)
	_refresh_texts()

func _build_ui() -> void:
	# 遮罩：挡住后面点击，点遮罩空白处关闭
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(360, 0)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_panel.add_child(vbox)

	var title := Label.new()
	title.set_meta("text_key", "settings_title")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UITheme.color("accent"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# 音量
	vbox.add_child(_row_label("volume"))
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0
	_volume_slider.max_value = 100
	_volume_slider.step = 1
	_volume_slider.value = float(Settings.get_setting("audio", "volume", 1.0)) * 100.0
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(_on_volume_changed)
	_volume_slider.drag_ended.connect(_on_volume_drag_ended)
	vbox.add_child(_volume_slider)
	_volume_label = Label.new()
	_volume_label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_volume_label)
	_update_volume_label()

	# 静音
	_mute_check = CheckButton.new()
	_mute_check.set_meta("text_key", "mute")
	_mute_check.button_pressed = bool(Settings.get_setting("audio", "muted", false))
	_mute_check.toggled.connect(_on_mute_toggled)
	vbox.add_child(_mute_check)

	# 主题
	vbox.add_child(_row_label("theme"))
	_theme_option = OptionButton.new()
	_theme_option.add_item("", 0)
	_theme_option.add_item("", 1)
	_theme_option.select(0 if UITheme.current == "dark" else 1)
	_theme_option.item_selected.connect(_on_theme_selected)
	vbox.add_child(_theme_option)

	# 语言（选项用母语显示）
	vbox.add_child(_row_label("language"))
	_lang_option = OptionButton.new()
	_lang_option.add_item("中文", 0)
	_lang_option.add_item("English", 1)
	_lang_option.select(0 if Loc.language == "zh" else 1)
	_lang_option.item_selected.connect(_on_language_selected)
	vbox.add_child(_lang_option)

	# 关闭
	var close := Button.new()
	close.set_meta("text_key", "close")
	close.pressed.connect(func(): visible = false)
	vbox.add_child(close)

	# ESC 提示
	var hint := Label.new()
	hint.set_meta("text_key", "esc_hint")
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UITheme.color("text_muted"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.color("bg_elevated")
	style.set_corner_radius_all(12)
	style.set_content_margin_all(24)
	style.border_color = UITheme.color("border")
	style.set_border_width_all(1)
	return style

func _row_label(key: String) -> Label:
	var label := Label.new()
	label.set_meta("text_key", key)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", UITheme.color("text_primary"))
	return label

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		visible = false

func _on_volume_changed(value: float) -> void:
	Settings.set_setting("audio", "volume", value / 100.0)
	_update_volume_label()

func _on_volume_drag_ended(_changed: bool) -> void:
	AudioManager.play_select()

func _update_volume_label() -> void:
	_volume_label.text = "%d%%" % int(_volume_slider.value)

func _on_mute_toggled(on: bool) -> void:
	Settings.set_setting("audio", "muted", on)

func _on_theme_selected(index: int) -> void:
	var theme_name := "dark" if index == 0 else "light"
	Settings.set_setting("display", "theme", theme_name)
	UITheme.switch_theme(theme_name)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	var main_node := get_tree().current_scene
	if main_node != null and main_node.has_method("apply_theme"):
		main_node.apply_theme()

func _on_language_selected(index: int) -> void:
	Loc.set_language("zh" if index == 0 else "en")

## 语言切换后重刷所有带 text_key 的控件文案 + 主题选项名。
func _refresh_texts(_language := "") -> void:
	for child in _panel.get_children():
		_recurse_texts(child)
	if _theme_option != null:
		_theme_option.set_item_text(0, Loc.t("theme_dark"))
		_theme_option.set_item_text(1, Loc.t("theme_light"))

func _recurse_texts(node: Node) -> void:
	if node is Control and node.has_meta("text_key"):
		var text := Loc.t(str(node.get_meta("text_key")))
		if node is Button:
			node.text = text
		elif node is Label:
			node.text = text
	for child in node.get_children():
		_recurse_texts(child)