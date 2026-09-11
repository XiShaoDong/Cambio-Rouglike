class_name ShopPanel
extends Control
## 商店面板（固定价购买）：SHOP 标题 + CARDS 区（3 张卡 + 价格，仅展示）+ RELICS 区（遗物固定价，可点击购买）
## + 底部 💰 货币 + 跳过购买。
## 每位存活玩家限购 1 件；同件先到先得（售出后不可再买）；全员完成（购买或跳过）后开下一局。
## 数据来自快照 shop.offers（id/name/price/sold_by）+ shop.done。

const CARD_SCENE := preload("res://scenes/ui/card.tscn")
const CARD_PRICES := [80, 95, 65]

var _currency := 0
var _viewer := -1
var _done := false
var _state: Dictionary = {}
var _on_buy: Callable = Callable()
var _on_skip: Callable = Callable()

func setup(state: Dictionary, on_buy: Callable, on_skip: Callable) -> void:
	_state = state
	_on_buy = on_buy
	_on_skip = on_skip
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewer = int(state.get("viewer_id", -1))
	_currency = 0
	for player in state.get("players", []):
		if int(player.id) == _viewer:
			_currency = int(player.get("currency", 0))
			break
	_done = false
	for seat in state.get("shop", {}).get("done", []):
		if int(seat) == _viewer:
			_done = true
	_clear_rows()
	_fill_cards()
	_fill_relics()
	var cur_lbl: Label = get_node("Center/Panel/VBox/Bottom/Currency")
	cur_lbl.text = "💰 %d" % _currency
	var leave: Button = get_node("Center/Panel/VBox/Bottom/Leave")
	leave.text = "已跳过" if _done else "跳过购买"
	leave.disabled = _done

## 清空动态行（刷新时复用面板，避免重复堆叠）。
func _clear_rows() -> void:
	for path in ["Center/Panel/VBox/CardsRow", "Center/Panel/VBox/RelicsRow"]:
		var row: Node = get_node(path)
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()

func _fill_cards() -> void:
	var row: HBoxContainer = get_node("Center/Panel/VBox/CardsRow")
	for price in CARD_PRICES:
		row.add_child(_make_card_slot(int(price)))

func _make_card_slot(price: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var card: Button = CARD_SCENE.instantiate()
	card.custom_minimum_size = Vector2(92, 132)
	box.add_child(card)
	# CardView._ready 会把 mouse_filter 设为 STOP；入树后再改 IGNORE 并禁用按钮，保证卡牌不可点击
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.disabled = true
	var price_lbl := Label.new()
	price_lbl.text = "$%d" % price
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 18)
	price_lbl.add_theme_color_override("font_color", UITheme.color("accent"))
	box.add_child(price_lbl)
	return box

func _fill_relics() -> void:
	var row: HBoxContainer = get_node("Center/Panel/VBox/RelicsRow")
	for offer in _state.get("shop", {}).get("offers", []):
		row.add_child(_make_relic_slot(offer))

func _make_relic_slot(offer: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var relic_id := str(offer.get("id", ""))
	var relic_name := str(offer.get("name", ""))
	var offer_index := int(offer.get("index", -1))
	var price := int(offer.get("price", 0))
	var sold_by := int(offer.get("sold_by", -1))
	# 程序化图标（盾紫/星金），与对局物品栏视觉一致
	var icon := RelicIcon.new()
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size = Vector2(36, 36)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var is_shield := relic_id == Relics.GUARD_SHIELD_ID
	icon.setup(RelicIcon.Kind.SHIELD if is_shield else RelicIcon.Kind.JOKER,
		UITheme.color("relic_shield") if is_shield else UITheme.color("accent"))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 60)
	btn.text = relic_name
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", UITheme.color("text_primary"))
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.color("bg_elevated")
	style.bg_color.a = 0.85
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	style.border_color = UITheme.color("border")
	style.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", style)
	var hover: StyleBoxFlat = style.duplicate()
	hover.border_color = UITheme.color("accent")
	btn.add_theme_stylebox_override("hover", hover)
	var down: StyleBoxFlat = style.duplicate()
	down.bg_color.a = 1.0
	down.border_color = UITheme.color("success")
	btn.add_theme_stylebox_override("pressed", down)
	var can_buy := not _done and sold_by < 0 and _currency >= price
	btn.disabled = not can_buy
	if sold_by >= 0:
		btn.text = "%s\n已售出" % relic_name
	elif _done:
		btn.text = "%s\n（已完成）" % relic_name
	elif _currency < price:
		btn.text = "%s\n货币不足" % relic_name
	if can_buy:
		btn.pressed.connect(_buy.bind(offer_index))
	box.add_child(btn)
	var price_lbl := Label.new()
	price_lbl.text = "$%d" % price
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 18)
	price_lbl.add_theme_color_override("font_color", UITheme.color("accent"))
	box.add_child(price_lbl)
	return box

func _buy(offer_index: int) -> void:
	if _on_buy.is_valid():
		_on_buy.call(offer_index)

func _ready() -> void:
	var panel: PanelContainer = get_node("Center/Panel")
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.color("bg_elevated")
	style.bg_color.a = 1.0
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	style.border_color = UITheme.color("border")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	get_node("Center/Panel/VBox/Bottom/Leave").pressed.connect(_leave)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_leave()
		get_viewport().set_input_as_handled()

## 跳过购买（不买，视为完成）。面板保持显示，由服务器快照刷新为"已跳过"。
func _leave() -> void:
	if _done:
		return
	if _on_skip.is_valid():
		_on_skip.call()