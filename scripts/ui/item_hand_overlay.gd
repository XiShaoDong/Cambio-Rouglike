class_name ItemHandOverlay
extends Control
## 屏幕空间道具手牌：底部中央手部 + 扇形卡 + 说明 + 目标 HUD。
## 手部美术通过 hand_art_scene（ItemHandArt 子类）注入，未来可直接替换。

signal target_changed(seat: int)

const CARD_SIZE := Vector2(110, 154)
const HAND_W := 520.0
const HAND_H := 300.0
const FAN_CENTER_LIFT := 120.0
const DESC_W := 460.0

var hand_art_scene: PackedScene = preload("res://scenes/ui/hand_silhouette_2d.tscn")
var model := ItemHandModel.new()
var _viewer := -1
var _built := false
var _pending_cards: Array = []
var _hand_art: ItemHandArt
var _cards_layer: Control
var _card_views: Array = []
var _desc: PanelContainer
var _desc_title: Label
var _desc_body: Label
var _hint: Label
var _target_panel: PanelContainer
var _target_label: Label
var _target_hint: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false

func _build() -> void:
	if _built:
		return
	_built = true
	_hand_art = _instantiate_hand_art()
	add_child(_hand_art)
	_cards_layer = Control.new()
	_cards_layer.name = "Cards"
	_cards_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cards_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards_layer)
	_desc = PanelContainer.new()
	_desc.name = "Description"
	_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var desc_style := StyleBoxFlat.new()
	desc_style.bg_color = Color(0.06, 0.07, 0.10, 0.88)
	desc_style.set_corner_radius_all(10)
	desc_style.set_content_margin_all(10)
	desc_style.border_color = Color(1, 1, 1, 0.18)
	desc_style.set_border_width_all(1)
	_desc.add_theme_stylebox_override("panel", desc_style)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	_desc.add_child(vb)
	_desc_title = Label.new()
	_desc_title.name = "Title"
	_desc_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_title.add_theme_font_size_override("font_size", 20)
	_desc_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	vb.add_child(_desc_title)
	_desc_body = Label.new()
	_desc_body.name = "Body"
	_desc_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_body.add_theme_font_size_override("font_size", 14)
	_desc_body.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	vb.add_child(_desc_body)
	add_child(_desc)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	add_child(_hint)
	_target_panel = PanelContainer.new()
	_target_panel.name = "TargetPanel"
	_target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_panel.add_theme_stylebox_override("panel", desc_style.duplicate())
	_target_panel.visible = false
	var tvb := VBoxContainer.new()
	tvb.add_theme_constant_override("separation", 6)
	_target_panel.add_child(tvb)
	_target_label = Label.new()
	_target_label.name = "TargetName"
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_label.add_theme_font_size_override("font_size", 24)
	_target_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	tvb.add_child(_target_label)
	_target_hint = Label.new()
	_target_hint.text = "Q / E 切换目标 · Enter 确认 · Esc 取消"
	_target_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_hint.add_theme_font_size_override("font_size", 13)
	_target_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	tvb.add_child(_target_hint)
	add_child(_target_panel)
	resized.connect(_layout)
	if not _pending_cards.is_empty():
		set_cards(_pending_cards)

func _instantiate_hand_art() -> ItemHandArt:
	if hand_art_scene != null:
		var node = hand_art_scene.instantiate()
		if node is ItemHandArt:
			(node as ItemHandArt).name = "HandArt"
			return node as ItemHandArt
		if node != null:
			node.queue_free()
	var fallback := HandSilhouette2D.new()
	fallback.name = "HandArt"
	return fallback

## 替换手部美术：未来传入手部场景（必须 extends ItemHandArt）。
func set_hand_art_scene(scene: PackedScene) -> void:
	hand_art_scene = scene
	if not _built:
		return
	if _hand_art != null and is_instance_valid(_hand_art):
		remove_child(_hand_art)
		_hand_art.queue_free()
	_hand_art = _instantiate_hand_art()
	add_child(_hand_art)
	move_child(_hand_art, 0)
	_layout()

func hand_art() -> ItemHandArt:
	return _hand_art

func selected_title_text() -> String:
	return _desc_title.text if _desc_title != null else ""

func selected_body_text() -> String:
	return _desc_body.text if _desc_body != null else ""

func target_panel_visible() -> bool:
	return _target_panel != null and _target_panel.visible

func setup(state: Dictionary, viewer: int) -> void:
	_viewer = viewer
	var ids: Array = state.get("item_cards", [])
	if _built:
		set_cards(ids)
	else:
		_pending_cards = ids.duplicate()

func set_cards(ids: Array) -> void:
	_pending_cards = ids.duplicate()
	model.set_cards(ids)
	if not _built:
		return
	for view in _card_views:
		if view != null and is_instance_valid(view):
			_cards_layer.remove_child(view)
			view.queue_free()
	_card_views.clear()
	for id in model.cards:
		var view := ItemCardView.new()
		view.name = "Card%d" % _card_views.size()
		view.custom_minimum_size = CARD_SIZE
		view.size = CARD_SIZE
		view.pivot_offset = CARD_SIZE * 0.5
		view.setup(ItemCards.def_by_id(id))
		_cards_layer.add_child(view)
		_card_views.append(view)
	_update_selection()

func open() -> void:
	if not _built:
		_build()
	if model.count() <= 0:
		close()
		return
	visible = true
	model.end_target()
	_target_panel.visible = false
	_cards_layer.visible = true
	_hand_art.visible = true
	_desc.visible = true
	_hint.visible = true
	_hand_art.play_open()
	_update_selection()
	_layout()

func close(_immediate := true) -> void:
	visible = false
	model.end_target()
	if _hand_art != null:
		_hand_art.play_close(true)

func is_open() -> bool:
	return visible

func select_next(dir: int) -> void:
	if model.target_mode:
		return
	model.cycle_card(dir)
	_update_selection()

func selected_index() -> int:
	return model.selected

func selected_id() -> String:
	return model.selected_id()

func selected_def() -> Dictionary:
	return model.selected_def()

func card_count() -> int:
	return model.count()

func card_view(index: int) -> ItemCardView:
	if index < 0 or index >= _card_views.size():
		return null
	return _card_views[index]

func begin_target(targets: Array) -> void:
	model.begin_target(targets)
	_cards_layer.visible = false
	_hand_art.visible = false
	_desc.visible = false
	_hint.visible = false
	_target_panel.visible = true
	_update_target_label()
	_layout()
	target_changed.emit(model.target_seat())

func cycle_target(dir: int) -> void:
	model.cycle_target(dir)
	_update_target_label()
	target_changed.emit(model.target_seat())

func target_seat() -> int:
	return model.target_seat()

func is_target_mode() -> bool:
	return model.target_mode

func set_target_name(name: String) -> void:
	_target_label.text = "目标：%s" % name

func cancel_target() -> void:
	model.end_target()
	_target_panel.visible = false
	_cards_layer.visible = true
	_hand_art.visible = true
	_desc.visible = true
	_hint.visible = true
	target_changed.emit(-1)
	_layout()

func _update_selection() -> void:
	if not _built or _card_views.is_empty():
		return
	for i in _card_views.size():
		_card_views[i].set_selected(i == model.selected)
	var def := model.selected_def()
	if def.is_empty():
		_desc_title.text = "没有道具卡"
		_desc_body.text = "在商店购买道具卡后，按空格查看。"
	else:
		_desc_title.text = str(def.get("name", ""))
		_desc_body.text = str(def.get("desc", ""))
	var target_text := _target_mode_text(def)
	if not target_text.is_empty():
		_desc_body.text += "\n" + target_text
	_hint.text = "空格 收起 · Q / E 选择 · Enter 使用"
	if _hand_art != null:
		_hand_art.set_selected_hint(model.selected, model.count())
	_layout()

func _target_mode_text(def: Dictionary) -> String:
	match str(def.get("target_mode", ItemCards.TARGET_NONE)):
		ItemCards.TARGET_NEXT:
			return "目标：下一位玩家"
		ItemCards.TARGET_OPPONENT:
			return "目标：选择一名对手"
		ItemCards.TARGET_SELF:
			return "目标：自己"
	return ""

func _update_target_label() -> void:
	var seat := model.target_seat()
	_target_label.text = "目标：玩家 %d" % seat if seat >= 0 else "目标：无"

func _layout() -> void:
	if not _built:
		return
	var center := Vector2(size.x * 0.5, size.y - FAN_CENTER_LIFT)
	if _hand_art != null:
		_hand_art.setup(Rect2(Vector2(size.x * 0.5 - HAND_W * 0.5, size.y - HAND_H), Vector2(HAND_W, HAND_H)))
	var layout := ItemHandMath.fan_layout(model.count(), CARD_SIZE, center, 18.0, 92.0, model.selected, 30.0)
	for i in layout.size():
		var item: Dictionary = layout[i]
		var view: ItemCardView = _card_views[i]
		view.position = item.pos
		view.rotation_degrees = float(item.rot_deg)
		view.scale = Vector2.ONE * float(item.scale)
		view.z_index = int(item.z)
	_desc.position = Vector2(size.x * 0.5 - DESC_W * 0.5, size.y - 348.0)
	_desc.size = Vector2(DESC_W, 92.0)
	_hint.position = Vector2(0, size.y - 36.0)
	_hint.size = Vector2(size.x, 24.0)
	_target_panel.position = Vector2(size.x * 0.5 - 280.0, size.y * 0.5 - 80.0)
	_target_panel.size = Vector2(560.0, 160.0)
