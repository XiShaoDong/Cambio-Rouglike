class_name UIStyle
extends RefCounted
## 3D UI 统一 StyleBox 工厂。颜色全部来自 UITheme.TOKENS，尺寸/圆角集中在这里。
## 只服务表现层：不读写快照、不判断规则。2D 棋盘仍用原有样式。

const R_CHIP := 6
const R_ROW := 8
const R_BTN := 12
const R_PANEL := 12
const R_BOARD := 16
const R_PILL := 24

static func _with_alpha(c: Color, a: float) -> Color:
	var out := c
	out.a = a
	return out

static func _shadow(s: StyleBoxFlat) -> void:
	s.shadow_color = UITheme.color("hud_shadow")
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 4)

static func _btn_shadow(s: StyleBoxFlat) -> void:
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 3)

static func panel(radius: int = R_PANEL, pad_h: int = 12, pad_v: int = 10, shadow := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UITheme.color("hud_surface")
	s.border_color = UITheme.color("border_strong")
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	if shadow:
		_shadow(s)
	return s

static func board(pad: int = 20, shadow := true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UITheme.color("board_surface")
	s.border_color = UITheme.color("border_strong")
	s.set_border_width_all(1)
	s.set_corner_radius_all(R_BOARD)
	s.set_content_margin_all(pad)
	if shadow:
		_shadow(s)
	return s

static func chip(active := false, shadow := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UITheme.color("accent_soft") if active else _with_alpha(UITheme.color("bg_elevated"), 0.94)
	s.border_color = UITheme.color("accent_focus") if active else UITheme.color("border_strong")
	s.set_border_width_all(1)
	s.set_corner_radius_all(R_CHIP)
	s.set_content_margin_all(5)
	s.content_margin_left = 10
	s.content_margin_right = 10
	if shadow:
		_shadow(s)
	return s

static func chip_text(active := false) -> Color:
	return UITheme.color("accent_focus") if active else UITheme.color("text_primary")

static func hover_color(state: String) -> Color:
	match state:
		"slap":
			return UITheme.color("hover_slap")
		"action":
			return UITheme.color("hover_action")
		"valid":
			return UITheme.color("hover_valid")
		"invalid":
			return UITheme.color("hover_invalid")
		"warning":
			return UITheme.color("hover_warning")
	return UITheme.color("hover_neutral")

static func info_box(state: String) -> StyleBoxFlat:
	if state.is_empty():
		return tooltip(false)
	var s := StyleBoxFlat.new()
	s.bg_color = UITheme.color("board_surface")
	s.border_color = hover_color(state)
	s.set_border_width_all(2)
	s.set_corner_radius_all(R_PANEL)
	s.set_content_margin_all(10)
	_shadow(s)
	return s

static func tooltip(note := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UITheme.color("accent_soft") if note else UITheme.color("board_surface")
	s.border_color = UITheme.color("accent_focus") if note else UITheme.color("border_strong")
	s.set_border_width_all(1)
	s.set_corner_radius_all(R_PANEL)
	s.set_content_margin_all(10)
	_shadow(s)
	return s

static func pill(state := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UITheme.color("hud_surface")
	s.border_color = UITheme.color("border_strong")
	if state == 1:
		s.border_color = UITheme.color("warning")
	elif state == 2:
		s.bg_color = _with_alpha(UITheme.color("danger_soft"), 0.94)
		s.border_color = UITheme.color("danger")
	s.set_border_width_all(2)
	s.set_corner_radius_all(R_PILL)
	s.content_margin_left = 30
	s.content_margin_right = 30
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

static func row(state := "normal") -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(R_ROW)
	s.set_border_width_all(1)
	match state:
		"hover":
			s.bg_color = _with_alpha(UITheme.color("bg_hover"), 0.92)
			s.border_color = UITheme.color("border_strong")
		"capture":
			s.bg_color = UITheme.color("accent_soft")
			s.border_color = UITheme.color("accent_focus")
			s.set_border_width_all(2)
		"bad":
			s.bg_color = _with_alpha(UITheme.color("danger_soft"), 0.72)
			s.border_color = UITheme.color("danger")
			s.set_border_width_all(2)
		"champion":
			s.bg_color = UITheme.color("accent_soft")
			s.border_color = UITheme.color("accent_focus")
			s.set_border_width_all(2)
		"ok":
			s.bg_color = _with_alpha(UITheme.color("hud_surface"), 0.86)
			s.border_color = UITheme.color("accent_focus")
			s.set_border_width_all(2)
		_:
			s.bg_color = _with_alpha(UITheme.color("bg_elevated"), 0.55)
			s.border_color = UITheme.color("border")
	return s

static func tab(active := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(R_ROW)
	s.set_content_margin_all(8)
	if active:
		s.bg_color = UITheme.color("accent_soft")
		s.border_color = UITheme.color("accent_focus")
		s.set_border_width_all(1)
	else:
		s.bg_color = Color(0, 0, 0, 0)
		s.border_color = Color(0, 0, 0, 0)
	return s

static func tab_hover() -> StyleBoxFlat:
	var s := tab(false)
	s.bg_color = UITheme.color("bg_hover")
	s.border_color = UITheme.color("border_strong")
	s.set_border_width_all(1)
	return s

static func tab_text(active := false) -> Color:
	return UITheme.color("accent_focus") if active else UITheme.color("text_secondary")

static func primary_button(state := "normal") -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(R_BTN)
	s.set_content_margin_all(12)
	s.set_border_width_all(2)
	match state:
		"hover":
			s.bg_color = UITheme.color("accent_hover")
			s.border_color = UITheme.color("accent_focus")
			s.set_border_width_all(3)
			_btn_shadow(s)
		"pressed":
			s.bg_color = UITheme.color("accent_pressed")
			s.border_color = UITheme.color("accent_focus")
			_btn_shadow(s)
		"disabled":
			s.bg_color = UITheme.color("bg_elevated")
			s.border_color = UITheme.color("text_muted")
		_:
			s.bg_color = UITheme.color("accent")
			s.border_color = UITheme.color("accent_pressed")
			_btn_shadow(s)
	return s

static func secondary_button(state := "normal") -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.set_corner_radius_all(R_BTN)
	s.set_content_margin_all(12)
	s.set_border_width_all(1)
	match state:
		"hover":
			s.bg_color = UITheme.color("bg_hover")
			s.border_color = UITheme.color("accent_focus")
			s.set_border_width_all(2)
			_btn_shadow(s)
		"pressed":
			s.bg_color = UITheme.color("accent_soft")
			s.border_color = UITheme.color("accent_focus")
			s.set_border_width_all(2)
			_btn_shadow(s)
		"disabled":
			s.bg_color = UITheme.color("bg_elevated")
			s.border_color = UITheme.color("text_muted")
		_:
			s.bg_color = UITheme.color("bg_elevated")
			s.border_color = UITheme.color("border_strong")
			_btn_shadow(s)
	return s

static func prepared_button() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = UITheme.color("accent_soft")
	s.border_color = UITheme.color("success")
	s.set_border_width_all(2)
	s.set_corner_radius_all(R_BTN)
	s.set_content_margin_all(12)
	_btn_shadow(s)
	return s

static func apply_primary(btn: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, primary_button(state))
	btn.add_theme_color_override("font_color", UITheme.color("text_on_accent"))
	btn.add_theme_color_override("font_hover_color", UITheme.color("text_on_accent"))
	btn.add_theme_color_override("font_pressed_color", UITheme.color("text_on_accent"))
	btn.add_theme_color_override("font_focus_color", UITheme.color("text_on_accent"))
	btn.add_theme_color_override("font_disabled_color", UITheme.color("text_muted"))

static func apply_secondary(btn: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, secondary_button(state))
	btn.add_theme_color_override("font_color", UITheme.color("text_primary"))
	btn.add_theme_color_override("font_hover_color", UITheme.color("text_primary"))
	btn.add_theme_color_override("font_pressed_color", UITheme.color("text_primary"))
	btn.add_theme_color_override("font_focus_color", UITheme.color("text_primary"))
	btn.add_theme_color_override("font_disabled_color", UITheme.color("text_muted"))

static func apply_prepared(btn: Button) -> void:
	var s := prepared_button()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, s)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		btn.add_theme_color_override(key, UITheme.color("success"))

static func apply_tab(btn: Button, active: bool) -> void:
	btn.add_theme_stylebox_override("normal", tab(active))
	btn.add_theme_stylebox_override("disabled", tab(active))
	btn.add_theme_stylebox_override("hover", tab(active) if active else tab_hover())
	btn.add_theme_stylebox_override("pressed", tab(active) if active else tab_hover())
	btn.add_theme_stylebox_override("focus", tab(active))
	var c := tab_text(active)
	btn.add_theme_color_override("font_color", c)
	btn.add_theme_color_override("font_disabled_color", c)
	btn.add_theme_color_override("font_hover_color", c)
	btn.add_theme_color_override("font_pressed_color", c)

static func apply_chip_button(btn: Button, active := false) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, chip(active))
	var c := chip_text(active)
	btn.add_theme_color_override("font_color", c)
	btn.add_theme_color_override("font_hover_color", c)
	btn.add_theme_color_override("font_pressed_color", c)
	btn.add_theme_color_override("font_disabled_color", c)
	btn.add_theme_color_override("font_focus_color", c)
