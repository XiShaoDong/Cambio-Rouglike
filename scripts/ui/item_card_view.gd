class_name ItemCardView
extends Control
## 道具卡占位卡面：背景 + 边框 + 占位字符 + 卡名。
## 独立于扑克 CardView：未来替换卡面美术只改本文件，不影响商店/手牌/弹层逻辑。

const DEFAULT_SIZE := Vector2(110, 154)
const GLYPH_FONT := 38
const NAME_FONT := 14

var def: Dictionary = {}
var selected := false
var _panel: Panel
var _glyph: Label
var _name: Label
var _pending := false

func _ready() -> void:
	_build()
	if _pending:
		_pending = false
		_refresh()

func setup(p_def: Dictionary) -> void:
	def = p_def
	if not is_inside_tree():
		_pending = true
		return
	_build()
	_refresh()

func set_selected(on: bool) -> void:
	selected = on
	_refresh_style()

func card_id() -> String:
	return str(def.get("id", ""))

func card_name() -> String:
	return str(def.get("name", ""))

func glyph_text() -> String:
	return str(def.get("glyph", "?"))

func _build() -> void:
	if _panel != null:
		return
	custom_minimum_size = DEFAULT_SIZE
	size = DEFAULT_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_glyph = Label.new()
	_glyph.name = "Glyph"
	_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glyph.offset_bottom = -26
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph.add_theme_font_size_override("font_size", GLYPH_FONT)
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glyph)
	_name = Label.new()
	_name.name = "Name"
	_name.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_name.offset_top = -30
	_name.offset_bottom = -6
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", NAME_FONT)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)

func _refresh() -> void:
	if _panel == null:
		return
	_refresh_style()
	var color: Color = UITheme.color(str(def.get("color", "accent")))
	_glyph.text = glyph_text()
	_glyph.add_theme_color_override("font_color", color)
	_name.text = card_name()
	_name.add_theme_color_override("font_color", UITheme.color("text_primary"))
	tooltip_text = "%s\n%s" % [card_name(), str(def.get("desc", ""))]
	for c in [_panel, _glyph, _name]:
		if c is Control:
			(c as Control).tooltip_text = tooltip_text

func _refresh_style() -> void:
	if _panel == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.color("bg_elevated")
	style.bg_color.a = 0.96
	style.set_corner_radius_all(10)
	style.set_content_margin_all(6)
	style.border_color = UITheme.color("accent") if selected else UITheme.color("border")
	style.set_border_width_all(3 if selected else 1)
	_panel.add_theme_stylebox_override("panel", style)
