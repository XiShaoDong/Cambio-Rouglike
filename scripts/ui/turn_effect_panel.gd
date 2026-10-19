class_name TurnEffectPanel
extends PanelContainer
## 每回合随机增强展示面板：
## 内容 = 标题「本局效果」+ 小牌（左）+ 效果说明（右）。
## 出场动画：屏幕中央放大 → 停顿 5s → 缩小移动到右上角并停留。

signal docked

const REVEAL_SCALE := 1.8
const HOLD_SECS := 5.0
const MOVE_SECS := 0.8
const CARD_SIZE := Vector2(40, 56)
const DESC_W := 190.0

const BG := Color(0.08, 0.09, 0.12, 0.90)
const BORDER := Color(1.0, 1.0, 1.0, 0.30)

var _title: Label
var _card_box: Control
var _card_tex: TextureRect
var _bomb: BombIcon
var _desc: Label
var _effect_id := ""
var _tween: Tween = null
var _revealing := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false

func _build() -> void:
	if _title != null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.set_corner_radius_all(14)
	style.set_content_margin_all(12)
	style.border_color = BORDER
	style.set_border_width_all(1)
	add_theme_stylebox_override("panel", style)
	var vb := VBoxContainer.new()
	vb.name = "VBox"
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	_title = Label.new()
	_title.name = "Title"
	_title.text = "本局效果"
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Color(1, 1, 1))
	vb.add_child(_title)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	_card_box = Control.new()
	_card_box.name = "CardBox"
	_card_box.custom_minimum_size = CARD_SIZE
	_card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_card_box)
	_card_tex = TextureRect.new()
	_card_tex.name = "Card"
	_card_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_tex.position = Vector2.ZERO
	_card_tex.size = CARD_SIZE
	_card_box.add_child(_card_tex)
	_bomb = BombIcon.new()
	_bomb.name = "Bomb"
	_bomb.position = Vector2(CARD_SIZE.x - 12.0, -6.0)
	_bomb.visible = false
	_card_box.add_child(_bomb)
	_desc = Label.new()
	_desc.name = "Desc"
	_desc.custom_minimum_size.x = DESC_W
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 15)
	_desc.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	_desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_desc)

## 更新展示内容（不发动画）。
func set_effect(effect: Dictionary) -> void:
	_build()
	_effect_id = str(effect.get("id", ""))
	var path := str(effect.get("card", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		_card_tex.texture = load(path)
		_card_tex.visible = true
	else:
		_card_tex.texture = null
		_card_tex.visible = false
	_bomb.visible = bool(effect.get("bomb", false))
	_desc.text = str(effect.get("desc", ""))

## 中央放大 → 停顿 5s → 缩小移动到 dock 点（右上角），并停留。
func reveal(effect: Dictionary, center: Vector2, dock: Vector2) -> void:
	set_effect(effect)
	visible = true
	reset_size()
	var sz := size
	pivot_offset = sz * 0.5
	scale = Vector2.ONE * REVEAL_SCALE
	position = center - sz * 0.5
	_kill_tween()
	_revealing = true
	var end_pos := dock - sz
	_tween = create_tween()
	_tween.tween_interval(HOLD_SECS)
	_tween.tween_property(self, "position", end_pos, MOVE_SECS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(self, "scale", Vector2.ONE, MOVE_SECS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.finished.connect(_on_docked)

func _on_docked() -> void:
	_revealing = false
	docked.emit()

## 直接停在右上角（无动画；切回 3D 时恢复当前效果用）。
func dock_at(dock: Vector2) -> void:
	_build()
	reset_size()
	pivot_offset = size * 0.5
	scale = Vector2.ONE
	position = dock - size
	visible = true
	_kill_tween()
	_revealing = false

func hide_panel() -> void:
	_kill_tween()
	_revealing = false
	visible = false

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

func effect_id() -> String:
	return _effect_id

func is_revealing() -> bool:
	return _revealing

func description_text() -> String:
	return _desc.text if _desc != null else ""
