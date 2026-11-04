class_name CardTiltSandbox
extends Control
## 2D 伪 3D 卡牌沙盒：中央一张卡，鼠标绕卡移动 → 透视倾斜 + 固定光高光。
## 右侧调参面板实时改 CardTiltView 参数。纯展示原型，不接游戏逻辑。

const FACE_TEX := preload("res://assets/Cards/hearts_ace.png")
const BACK_TEX := preload("res://assets/Cards/back07.png")
const CARD_SIZE := Vector2(250.0, 350.0)
const PANEL_WIDTH := 320.0

var _card: CardTiltView
var _face := true
var _angle_label: Label
var _title: Labelwo
var _preset_status: Label
var _sliders := {}
var _demo := false
var _demo_time := 0.0
var _defaults := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_demo = OS.get_cmdline_user_args().has("--demo")
	_build_card()
	_remember_defaults()
	_card.load_preset()
	_build_panel()
	_layout_card()
	resized.connect(_layout_card)
	if _demo and OS.get_cmdline_user_args().has("--shot"):
		_capture_shot.call_deferred()


func _process(delta: float) -> void:
	if not _demo or _card == null:
		return
	_demo_time += delta
	var norm := Vector2(sin(_demo_time * 0.9), cos(_demo_time * 0.62)) * 0.95
	_card.set_pointer_normalized(norm)


func _capture_shot() -> void:
	await get_tree().create_timer(2.0).timeout
	var image := get_viewport().get_texture().get_image()
	image.save_png("/tmp/card_tilt_shot.png")
	get_tree().quit()


func _build_card() -> void:
	_card = CardTiltView.new()
	_card.name = "Card"
	_card.texture = FACE_TEX
	_card.card_aspect = CARD_SIZE.y / CARD_SIZE.x
	_card.size = CardTiltMath.padded_size(CARD_SIZE, _card.pad)
	_card.tilt_changed.connect(_on_tilt_changed)
	add_child(_card)


func _layout_card() -> void:
	if _card == null:
		return
	_card.size = CardTiltMath.padded_size(CARD_SIZE, _card.pad)
	var free_width := maxf(size.x - PANEL_WIDTH, 320.0)
	_card.position = Vector2((free_width - _card.size.x) * 0.5, (size.y - _card.size.y) * 0.5)


func _remember_defaults() -> void:
	_defaults = {
		"max_tilt_deg": _card.max_tilt_deg,
		"cam_dist": _card.cam_dist,
		"response": _card.response,
		"pad": _card.pad,
		"spec_strength": _card.spec_strength,
		"gloss_strength": _card.gloss_strength,
		"rim_strength": _card.rim_strength,
		"shadow_strength": _card.shadow_strength,
		"base_gain": _card.base_gain,
	}


func _reset_params() -> void:
	_card.max_tilt_deg = float(_defaults.get("max_tilt_deg", _card.max_tilt_deg))
	_card.cam_dist = float(_defaults.get("cam_dist", _card.cam_dist))
	_card.response = float(_defaults.get("response", _card.response))
	_card.pad = float(_defaults.get("pad", _card.pad))
	_card.spec_strength = float(_defaults.get("spec_strength", _card.spec_strength))
	_card.gloss_strength = float(_defaults.get("gloss_strength", _card.gloss_strength))
	_card.rim_strength = float(_defaults.get("rim_strength", _card.rim_strength))
	_card.shadow_strength = float(_defaults.get("shadow_strength", _card.shadow_strength))
	_card.base_gain = float(_defaults.get("base_gain", _card.base_gain))
	_sync_sliders()


func _build_panel() -> void:
	_title = Label.new()
	_title.text = "2D 伪 3D 卡牌 · 移动鼠标倾斜"
	_title.add_theme_font_size_override("font_size", 20)
	_title.position = Vector2(28.0, 22.0)
	add_child(_title)

	var hint := Label.new()
	hint.text = "鼠标绕卡片移动 → 透视倾斜 / 高光 / 反光 / 投影\n鼠标离开卡面自动回正"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.72, 0.76, 0.86))
	hint.position = Vector2(28.0, 52.0)
	add_child(hint)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -PANEL_WIDTH - 20.0
	panel.offset_right = -20.0
	panel.anchor_bottom = 1.0
	panel.offset_top = 20.0
	panel.offset_bottom = -20.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.13, 0.94)
	style.border_color = Color(1.0, 1.0, 1.0, 0.08)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(16.0)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	_add_header(box, "倾斜")
	_add_slider(box, "最大角度", 2.0, 40.0, 0.5, _card.max_tilt_deg, func(v: float) -> void: _card.max_tilt_deg = v, "max_tilt_deg")
	_add_slider(box, "跟随速度", 0.0, 30.0, 0.5, _card.response, func(v: float) -> void: _card.response = v, "response")
	_add_slider(box, "透视强度", 1.4, 8.0, 0.1, _card.cam_dist, func(v: float) -> void: _card.cam_dist = v, "cam_dist")
	_add_slider(box, "画布留白", 1.0, 2.6, 0.05, _card.pad, func(v: float) -> void: _card.pad = v; _layout_card(), "pad")

	_add_header(box, "光照")
	_add_slider(box, "高光", 0.0, 2.0, 0.01, _card.spec_strength, func(v: float) -> void: _card.spec_strength = v, "spec_strength")
	_add_slider(box, "反光条", 0.0, 2.0, 0.01, _card.gloss_strength, func(v: float) -> void: _card.gloss_strength = v, "gloss_strength")
	_add_slider(box, "轮廓光", 0.0, 2.0, 0.01, _card.rim_strength, func(v: float) -> void: _card.rim_strength = v, "rim_strength")
	_add_slider(box, "整体亮度", 0.5, 1.5, 0.01, _card.base_gain, func(v: float) -> void: _card.base_gain = v, "base_gain")

	_add_header(box, "投影")
	_add_slider(box, "投影强度", 0.0, 1.0, 0.01, _card.shadow_strength, func(v: float) -> void: _card.shadow_strength = v, "shadow_strength")

	_angle_label = Label.new()
	_angle_label.add_theme_font_size_override("font_size", 12)
	_angle_label.add_theme_color_override("font_color", Color(0.65, 0.70, 0.82))
	box.add_child(_angle_label)
	_on_tilt_changed(0.0, 0.0)

	box.add_child(HSeparator.new())

	var face_button := Button.new()
	face_button.text = "切换卡面（正面 / 卡背）"
	face_button.pressed.connect(_toggle_face)
	box.add_child(face_button)

	var reset_button := Button.new()
	reset_button.text = "重置倾斜"
	reset_button.pressed.connect(func() -> void: _card.reset_tilt())
	box.add_child(reset_button)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 8)
	box.add_child(save_row)

	var save_button := Button.new()
	save_button.text = "保存到项目"
	save_button.tooltip_text = "写入 res://assets/config/card_tilt_preset.cfg，游戏内 CardTiltView 启动时自动读取"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_on_save_pressed)
	save_row.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "读取已保存"
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.pressed.connect(_on_load_pressed)
	save_row.add_child(load_button)

	_preset_status = Label.new()
	_preset_status.add_theme_font_size_override("font_size", 11)
	_preset_status.add_theme_color_override("font_color", Color(0.62, 0.68, 0.80))
	_preset_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preset_status.text = "未保存 · 存档：%s" % CardTiltView.PRESET_PATH
	box.add_child(_preset_status)

	var reset_params_button := Button.new()
	reset_params_button.text = "重置调节"
	reset_params_button.pressed.connect(_reset_params)
	box.add_child(reset_params_button)


func _add_header(box: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.62, 0.78, 1.0))
	box.add_child(label)


func _add_slider(box: VBoxContainer, label_text: String, min_v: float, max_v: float, step_v: float, value: float, on_change: Callable, prop: String) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = value
	slider.custom_minimum_size = Vector2(0.0, 18.0)
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	box.add_child(row)
	_sliders[prop] = slider


func _sync_sliders() -> void:
	for prop in _sliders:
		var slider: HSlider = _sliders[prop]
		slider.set_value_no_signal(float(_card.get(prop)))


func _on_save_pressed() -> void:
	var path := _card.save_preset()
	if path.is_empty():
		_preset_status.text = "保存失败：项目目录不可写，也未写入 user://"
		_preset_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		return
	_preset_status.text = "已保存：%s\n游戏内 CardTiltView（persist=true）启动时自动读取" % ProjectSettings.globalize_path(path)
	_preset_status.add_theme_color_override("font_color", Color(0.55, 0.9, 0.65))


func _on_load_pressed() -> void:
	if not _card.load_preset():
		_preset_status.text = "还没有保存过预设"
		_preset_status.add_theme_color_override("font_color", Color(1.0, 0.75, 0.45))
		return
	_layout_card()
	_sync_sliders()
	_preset_status.text = "已读取：%s" % ProjectSettings.globalize_path(_find_existing_preset())
	_preset_status.add_theme_color_override("font_color", Color(0.55, 0.9, 0.65))


func _find_existing_preset() -> String:
	for path in [CardTiltView.PRESET_PATH, CardTiltView.USER_PRESET_PATH]:
		if FileAccess.file_exists(path):
			return path
	return CardTiltView.PRESET_PATH


func _toggle_face() -> void:
	_face = not _face
	_card.texture = FACE_TEX if _face else BACK_TEX


func _on_tilt_changed(yaw: float, pitch: float) -> void:
	if _angle_label != null:
		_angle_label.text = "当前倾斜  yaw %+.1f°   pitch %+.1f°" % [yaw, pitch]
