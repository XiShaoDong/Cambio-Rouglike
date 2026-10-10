class_name SlapSuccessBurst
extends Control
## 贴牌成功爆炸弹层（仅 3D 的屏幕空间 overlay）：
## 红色齿状爆炸背景（黑色描边）+ 卡牌正面 + 第一行「贴牌成功」大字 + 第二行玩家名。
## 屏幕右侧、垂直居中；弹出放大 → 停留 → 淡出后自动释放。纯展示层。

const BURST_PATH := "res://assets/ui/slap_burst.svg"
const SIZE := Vector2(360.0, 400.0)
const CENTER_X_RATIO := 0.75  # 屏幕横向四等份，容器中线落在 3/4 处
const CARD_SIZE := Vector2(120.0, 168.0)
const TITLE_FONT := 34
const NAME_FONT := 20
const TITLE_TEXT := "贴牌成功"
const POP_DUR := 0.30
const HOLD := 1.8
const FADE_DUR := 0.35

var _cards := CardFactory.new()

## 构建并播放。card 为成功贴到的那张牌（含 rank/suit/label），player_name 为贴中者名字。
func setup(card: Dictionary, player_name: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 横向：屏幕四等份，容器中线落在 3/4；纵向：垂直居中
	anchor_left = CENTER_X_RATIO
	anchor_right = CENTER_X_RATIO
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -SIZE.x * 0.5
	offset_right = SIZE.x * 0.5
	offset_top = -SIZE.y * 0.5
	offset_bottom = SIZE.y * 0.5
	pivot_offset = SIZE * 0.5

	var bg := TextureRect.new()
	bg.name = "Burst"
	bg.texture = load(BURST_PATH)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vb := VBoxContainer.new()
	vb.name = "VBox"
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)

	var title := Label.new()
	title.name = "Title"
	title.text = TITLE_TEXT
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	vb.add_child(title)

	var nm := Label.new()
	nm.name = "Name"
	nm.text = player_name
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", NAME_FONT)
	nm.add_theme_color_override("font_color", Color(1, 1, 1))
	vb.add_child(nm)

	var center := CenterContainer.new()
	center.name = "CardCenter"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cv: Control = _cards.make_card(card, CARD_SIZE)
	cv.name = "Card"
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(cv)
	vb.add_child(center)

	# 弹出放大（回弹）→ 停留 → 淡出 → 自动释放
	scale = Vector2(0.6, 0.6)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, POP_DUR).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(HOLD)
	t.tween_property(self, "modulate:a", 0.0, FADE_DUR)
	t.finished.connect(queue_free)

## 测试访问器。
func title_text() -> String:
	var l := get_node_or_null("VBox/Title")
	return (l as Label).text if l != null else ""
