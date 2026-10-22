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
var _nose_check: CheckButton
var _directory_edit: LineEdit
var _theme_option: OptionButton
var _lobby_layout_option: OptionButton
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

	# 鼻子点击（彩蛋，默认关闭）
	_nose_check = CheckButton.new()
	_nose_check.set_meta("text_key", "nose_click")
	_nose_check.button_pressed = bool(Settings.get_setting("gameplay", "nose_click", false))
	_nose_check.toggled.connect(_on_nose_toggled)
	vbox.add_child(_nose_check)

	# 目录地址（P2：房间码联机）
	vbox.add_child(_row_label("directory"))
	_directory_edit = LineEdit.new()
	_directory_edit.placeholder_text = "http://<服务器IP>:8080"
	_directory_edit.text = str(Settings.get_setting("network", "directory_url", ""))
	_directory_edit.text_submitted.connect(func(_t: String): _apply_directory())
	_directory_edit.focus_exited.connect(_apply_directory)
	_style_input(_directory_edit)
	vbox.add_child(_directory_edit)

	# 主题
	vbox.add_child(_row_label("theme"))
	_theme_option = OptionButton.new()
	_theme_option.add_item("", 0)
	_theme_option.add_item("", 1)
	_theme_option.add_item("", 2)
	_theme_option.select(0 if UITheme.current == "dark" else (1 if UITheme.current == "dark-1" else 2))
	_theme_option.item_selected.connect(_on_theme_selected)
	vbox.add_child(_theme_option)

	# 房间布局（宽屏 / 紧凑 / 自动）
	vbox.add_child(_row_label("lobby_layout"))
	_lobby_layout_option = OptionButton.new()
	_lobby_layout_option.add_item("", 0)
	_lobby_layout_option.add_item("", 1)
	_lobby_layout_option.add_item("", 2)
	var layout_mode := str(Settings.get_setting("display", "lobby_layout", "auto"))
	_lobby_layout_option.select(0 if layout_mode == "auto" else (1 if layout_mode == "wide" else 2))
	_lobby_layout_option.item_selected.connect(_on_lobby_layout_selected)
	vbox.add_child(_lobby_layout_option)

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
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(func(): visible = false)
	_style_button(close)
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
	style.bg_color.a = 0.98
	style.set_corner_radius_all(14)
	style.set_content_margin_all(24)
	style.border_color = UITheme.color("border")
	style.set_border_width_all(1)
	return style

## 与大厅输入框同款样式（半透明深蓝底 + 1px 边框 + 圆角，聚焦 accent 边框）。
func _style_input(edit: LineEdit) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = UITheme.color("bg_elevated")
	st.set_corner_radius_all(10)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 10
	st.content_margin_bottom = 10
	st.border_color = UITheme.color("border")
	st.set_border_width_all(1)
	edit.add_theme_stylebox_override("normal", st)
	var focus: StyleBoxFlat = st.duplicate()
	focus.border_color = UITheme.color("accent_focus")
	edit.add_theme_stylebox_override("focus", focus)

## 与大厅次级按钮同款样式。
func _style_button(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = UITheme.color("bg_elevated")
	normal.bg_color.a = 0.92
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(10)
	normal.border_color = UITheme.color("border")
	normal.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = UITheme.color("bg_surface_alt")
	btn.add_theme_stylebox_override("hover", hover)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = UITheme.color("bg_hover")
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", UITheme.color("text_primary"))

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

func _on_nose_toggled(on: bool) -> void:
	Settings.set_setting("gameplay", "nose_click", on)

func _apply_directory() -> void:
	var url := _directory_edit.text.strip_edges()
	Settings.set_setting("network", "directory_url", url)
	var main_node := get_tree().current_scene
	if main_node != null and main_node.has_method("set_directory_url"):
		main_node.set_directory_url(url)

func _on_theme_selected(index: int) -> void:
	var theme_name := "dark" if index == 0 else ("dark-1" if index == 1 else "light")
	Settings.set_setting("display", "theme", theme_name)
	UITheme.switch_theme(theme_name)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	var main_node := get_tree().current_scene
	if main_node != null and main_node.has_method("apply_theme"):
		main_node.apply_theme()

func _on_lobby_layout_selected(index: int) -> void:
	var mode := "auto" if index == 0 else ("wide" if index == 1 else "compact")
	Settings.set_setting("display", "lobby_layout", mode)
	var main_node := get_tree().current_scene
	if main_node != null and main_node.has_method("refresh_lobby_layout"):
		main_node.refresh_lobby_layout()

func _on_language_selected(index: int) -> void:
	Loc.set_language("zh" if index == 0 else "en")

## 语言切换后重刷所有带 text_key 的控件文案 + 主题选项名。
func _refresh_texts(_language := "") -> void:
	for child in _panel.get_children():
		_recurse_texts(child)
	if _theme_option != null:
		_theme_option.set_item_text(0, Loc.t("theme_dark"))
		_theme_option.set_item_text(1, Loc.t("theme_dark_1"))
		_theme_option.set_item_text(2, Loc.t("theme_light"))
	if _lobby_layout_option != null:
		_lobby_layout_option.set_item_text(0, Loc.t("lobby_layout_auto"))
		_lobby_layout_option.set_item_text(1, Loc.t("lobby_layout_wide"))
		_lobby_layout_option.set_item_text(2, Loc.t("lobby_layout_compact"))

func _recurse_texts(node: Node) -> void:
	if node is Control and node.has_meta("text_key"):
		var text := Loc.t(str(node.get_meta("text_key")))
		if node is Button:
			node.text = text
		elif node is Label:
			node.text = text
	for child in node.get_children():
		_recurse_texts(child)