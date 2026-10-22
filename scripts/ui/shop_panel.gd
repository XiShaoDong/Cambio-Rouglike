class_name ShopPanel
extends Control
## 商店面板：每人独立 3 张道具卡 + 2 件遗物；两区各自购买/刷新/锁定；
## 底部「结束商店」= 跳过整个商店。数据来自 viewer 自己的快照。

const SLOT_COUNT := 2
const CARD_SLOT_COUNT := 3

var _currency := 0
var _viewer := -1
var _done := false
var _state: Dictionary = {}
var _owned_relics := {}
var _relic_count := 0
var _owned_cards := {}
var _card_count := 0
var _on_buy: Callable = Callable()
var _on_skip: Callable = Callable()
var _on_refresh: Callable = Callable()
var _on_lock: Callable = Callable()
var _on_card_buy: Callable = Callable()
var _on_card_refresh: Callable = Callable()
var _on_card_lock: Callable = Callable()
var _relic_refresh_btn: Button = null
var _card_refresh_btn: Button = null

func setup(state: Dictionary, on_buy: Callable, on_skip: Callable,
		on_refresh: Callable, on_lock: Callable,
		on_card_buy: Callable, on_card_refresh: Callable, on_card_lock: Callable,
		dim := true) -> void:
	_state = state
	_on_buy = on_buy
	_on_skip = on_skip
	_on_refresh = on_refresh
	_on_lock = on_lock
	_on_card_buy = on_card_buy
	_on_card_refresh = on_card_refresh
	_on_card_lock = on_card_lock
	get_node("Dim").visible = dim
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewer = int(state.get("viewer_id", -1))
	_currency = 0
	_owned_relics.clear()
	_relic_count = 0
	_owned_cards.clear()
	_card_count = 0
	for player in state.get("players", []):
		if int(player.id) == _viewer:
			_currency = int(player.get("currency", 0))
			for id in player.get("relics", []):
				if not str(id).is_empty():
					_owned_relics[str(id)] = true
					_relic_count += 1
			break
	for id in state.get("item_cards", []):
		if not str(id).is_empty():
			_owned_cards[str(id)] = true
			_card_count += 1
	_done = false
	for seat in state.get("shop", {}).get("done", []):
		if int(seat) == _viewer:
			_done = true
	_clear_rows()
	_fill_cards()
	_fill_relics()
	_refresh_bottom()

func _clear_rows() -> void:
	for path in ["Center/Panel/VBox/CardsRow", "Center/Panel/VBox/RelicsRow"]:
		var row: Node = get_node(path)
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()

func _shop() -> Dictionary:
	return _state.get("shop", {})

func _fill_cards() -> void:
	var row: HBoxContainer = get_node("Center/Panel/VBox/CardsRow")
	var offers: Array = _shop().get("card_offers", [])
	for slot in CARD_SLOT_COUNT:
		var offer: Dictionary = offers[slot] if slot < offers.size() else {}
		row.add_child(_make_card_slot(slot, offer))
	# 卡牌刷新按钮：与卡牌同一行末尾（常规尺寸，accent 边可点态）
	_card_refresh_btn = _make_button("⟳  刷新卡牌", bool(_shop().get("card_can_refresh", false)), true)
	_card_refresh_btn.name = "CardRefresh"
	_card_refresh_btn.custom_minimum_size = Vector2(150, 36)
	_card_refresh_btn.add_theme_font_size_override("font_size", 13)
	_card_refresh_btn.pressed.connect(_card_refresh)
	row.add_child(_card_refresh_btn)
	_refresh_bottom()

func _fill_relics() -> void:
	var row: HBoxContainer = get_node("Center/Panel/VBox/RelicsRow")
	var offers: Array = _shop().get("offers", [])
	for slot in SLOT_COUNT:
		var offer: Dictionary = offers[slot] if slot < offers.size() else {}
		row.add_child(_make_relic_slot(slot, offer))
	# 遗物刷新按钮：与遗物同一行末尾
	_relic_refresh_btn = _make_button("⟳  刷新遗物", bool(_shop().get("can_refresh", false)), true)
	_relic_refresh_btn.name = "Refresh"
	_relic_refresh_btn.custom_minimum_size = Vector2(150, 36)
	_relic_refresh_btn.add_theme_font_size_override("font_size", 13)
	_relic_refresh_btn.pressed.connect(_refresh)
	row.add_child(_relic_refresh_btn)
	_refresh_bottom()

func _make_card_slot(slot: int, offer: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = "CardSlot%d" % slot
	box.add_theme_constant_override("separation", 5)
	box.custom_minimum_size = Vector2(150, 0)
	var card_id := str(offer.get("id", ""))
	var card_def := ItemCards.def_by_id(card_id)
	var card_name := str(offer.get("name", card_def.get("name", "空卡位")))
	var desc := str(offer.get("desc", card_def.get("desc", "")))
	var price := int(offer.get("price", ItemCards.PRICE))
	var locked := bool(offer.get("locked", false))
	var card_bought := bool(_shop().get("card_bought", false))
	var view := ItemCardView.new()
	view.name = "Card"
	view.custom_minimum_size = Vector2(110, 154)
	view.size = view.custom_minimum_size
	view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var view_def := card_def.duplicate()
	if view_def.is_empty():
		view_def = {"id": "", "name": "空卡位", "desc": "", "glyph": "·", "color": "border_strong"}
	view.setup(view_def)
	box.add_child(view)
	var name_lbl := Label.new()
	name_lbl.text = card_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", UITheme.color("text_primary"))
	box.add_child(name_lbl)
	var price_lbl := Label.new()
	price_lbl.text = "$%d" % price if not card_id.is_empty() else "—"
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 15)
	price_lbl.add_theme_color_override("font_color", UITheme.color("accent"))
	box.add_child(price_lbl)
	var status := "可购买"
	if card_id.is_empty():
		status = "空卡位"
	elif _done:
		status = "商店已结束"
	elif card_bought:
		status = "本店已买卡"
	elif _owned_cards.has(card_id):
		status = "已拥有"
	elif _card_count >= ItemCards.SLOT_LIMIT:
		status = "卡牌栏已满"
	elif _currency < price:
		status = "货币不足"
	elif locked:
		status = "已锁定"
	var can_buy := not _done and not card_bought and not card_id.is_empty() \
		and not _owned_cards.has(card_id) and _card_count < ItemCards.SLOT_LIMIT and _currency >= price
	var buy := _make_button("购买" if can_buy else status, can_buy)
	buy.name = "Buy"
	if can_buy:
		buy.pressed.connect(_card_buy.bind(slot))
	box.add_child(buy)
	var can_lock := not _done and not card_id.is_empty()
	var lock_btn := _make_button("解锁" if locked else "锁定", can_lock, locked)
	lock_btn.name = "Lock"
	if can_lock:
		lock_btn.pressed.connect(_card_lock.bind(slot, not locked))
	box.add_child(lock_btn)
	if locked:
		var lock_lbl := Label.new()
		lock_lbl.text = "已锁定 · 刷新不替换"
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.add_theme_font_size_override("font_size", 10)
		lock_lbl.add_theme_color_override("font_color", UITheme.color("accent"))
		box.add_child(lock_lbl)
	var tip := "%s\n%s\n%s" % [card_name, desc, status]
	box.tooltip_text = tip
	for child in box.get_children():
		if child is Control:
			(child as Control).tooltip_text = tip
	return box

func _make_relic_slot(slot: int, offer: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.name = "RelicSlot%d" % slot
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size = Vector2(180, 0)
	var relic_id := str(offer.get("id", ""))
	var relic_name := str(offer.get("name", "空货位"))
	var offer_index := int(offer.get("index", slot))
	var price := int(offer.get("price", 0))
	var locked := bool(offer.get("locked", false))
	var def := Relics.def_by_id(relic_id)
	var desc := str(def.get("desc", "该货位暂无商品。"))
	var relic_bought := bool(_shop().get("relic_bought", false))
	var status := "可购买"
	if relic_id.is_empty():
		status = "空货位"
	elif _done:
		status = "商店已结束"
	elif relic_bought:
		status = "本店已买遗物"
	elif _owned_relics.has(relic_id):
		status = "已拥有"
	elif _relic_count >= 3:
		status = "遗物栏已满"
	elif _currency < price:
		status = "货币不足"
	elif locked:
		status = "已锁定"
	var tip := "%s\n%s\n%s" % [relic_name, desc, status]

	var icon := RelicIcon.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.size = Vector2(48, 48)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var color: Color = UITheme.color(str(def.get("color", "accent")))
	if relic_id == Relics.GUARD_SHIELD_ID:
		icon.setup(RelicIcon.Kind.SHIELD, color)
	elif relic_id == Relics.JOKER_TRANSFORM_ID:
		icon.setup(RelicIcon.Kind.JOKER, color)
	elif relic_id.is_empty():
		icon.setup(RelicIcon.Kind.EMPTY, UITheme.color("border_strong"))
	else:
		icon.setup_glyph(str(def.get("glyph", "?")), color)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = relic_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", UITheme.color("text_primary"))
	box.add_child(name_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "$%d" % price if not relic_id.is_empty() else "—"
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 16)
	price_lbl.add_theme_color_override("font_color", UITheme.color("accent"))
	box.add_child(price_lbl)

	var can_buy := not _done and not relic_bought and not relic_id.is_empty() \
		and not _owned_relics.has(relic_id) and _relic_count < 3 and _currency >= price
	var buy := _make_button("购买" if can_buy else status, can_buy)
	buy.name = "Buy"
	if can_buy:
		buy.pressed.connect(_buy.bind(offer_index))
	box.add_child(buy)

	var can_lock := not _done and not relic_id.is_empty()
	var lock_btn := _make_button("解锁" if locked else "锁定", can_lock, locked)
	lock_btn.name = "Lock"
	if can_lock:
		lock_btn.pressed.connect(_lock.bind(offer_index, not locked))
	box.add_child(lock_btn)

	if locked:
		var lock_lbl := Label.new()
		lock_lbl.text = "已锁定 · 刷新不替换"
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.add_theme_font_size_override("font_size", 11)
		lock_lbl.add_theme_color_override("font_color", UITheme.color("accent"))
		box.add_child(lock_lbl)

	box.tooltip_text = tip
	for child in box.get_children():
		if child is Control:
			(child as Control).tooltip_text = tip
	return box

func _make_button(text: String, enabled: bool, active := false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(150, 34)
	btn.disabled = not enabled
	btn.add_theme_font_size_override("font_size", 14)
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.color("bg_elevated")
	style.bg_color.a = 0.85
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6)
	style.border_color = UITheme.color("accent") if active else UITheme.color("border")
	style.set_border_width_all(1)
	btn.add_theme_stylebox_override("normal", style)
	var hover: StyleBoxFlat = style.duplicate()
	hover.bg_color = UITheme.color("bg_surface_alt")
	hover.border_color = UITheme.color("accent")
	btn.add_theme_stylebox_override("hover", hover)
	var down: StyleBoxFlat = style.duplicate()
	down.bg_color.a = 1.0
	down.border_color = UITheme.color("success")
	btn.add_theme_stylebox_override("pressed", down)
	# 禁用态：降透明度 + 灰字（不退回默认主题暗色，可读）
	var off: StyleBoxFlat = style.duplicate()
	off.bg_color.a = 0.4
	btn.add_theme_stylebox_override("disabled", off)
	btn.add_theme_color_override("font_color", UITheme.color("text_primary"))
	btn.add_theme_color_override("font_disabled_color", UITheme.color("text_muted"))
	return btn

func _refresh_bottom() -> void:
	var cur_lbl: Label = get_node("Center/Panel/VBox/Bottom/Currency")
	cur_lbl.text = "$ %d" % _currency
	var shop := _shop()
	if _relic_refresh_btn != null and is_instance_valid(_relic_refresh_btn):
		_relic_refresh_btn.text = "⟳  刷新遗物 $%d" % int(shop.get("refresh_cost", Relics.SHOP_REFRESH_COST))
		_relic_refresh_btn.disabled = not bool(shop.get("can_refresh", false))
		_relic_refresh_btn.tooltip_text = _refresh_tip("遗物", bool(shop.get("can_refresh", false)), _relic_count, 3)
	if _card_refresh_btn != null and is_instance_valid(_card_refresh_btn):
		_card_refresh_btn.text = "⟳  刷新卡牌 $%d" % int(shop.get("card_refresh_cost", ItemCards.REFRESH_COST))
		_card_refresh_btn.disabled = not bool(shop.get("card_can_refresh", false))
		_card_refresh_btn.tooltip_text = _refresh_tip("道具卡", bool(shop.get("card_can_refresh", false)), _card_count, ItemCards.SLOT_LIMIT)
	var leave: Button = get_node("Center/Panel/VBox/Bottom/Leave")
	leave.text = "已结束商店" if _done else "结束商店（跳过剩余）"
	leave.disabled = _done

func _refresh_tip(label: String, can: bool, count: int, limit: int) -> String:
	if can:
		return "花 %d 刷新未锁定的%s货位；已锁货位保持不变。" % [ItemCards.REFRESH_COST, label]
	if _done:
		return "商店已结束。"
	if count >= limit:
		return "%s栏已满，无法刷新。" % label
	if _currency < ItemCards.REFRESH_COST:
		return "货币不足，无法刷新。"
	return "没有可刷新的%s货位（可能都已锁定）。" % label

func _buy(offer_index: int) -> void:
	if _on_buy.is_valid():
		_on_buy.call(offer_index)

func _lock(offer_index: int, locked: bool) -> void:
	if _on_lock.is_valid():
		_on_lock.call(offer_index, locked)

func _card_buy(slot: int) -> void:
	if _on_card_buy.is_valid():
		_on_card_buy.call(slot)

func _card_lock(slot: int, locked: bool) -> void:
	if _on_card_lock.is_valid():
		_on_card_lock.call(slot, locked)

func _refresh() -> void:
	if _on_refresh.is_valid():
		_on_refresh.call()

func _card_refresh() -> void:
	if _on_card_refresh.is_valid():
		_on_card_refresh.call()

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
	# "结束商店" = 唯一主操作：放大靠右下角、accent 高亮
	var leave: Button = get_node("Center/Panel/VBox/Bottom/Leave")
	leave.custom_minimum_size = Vector2(240, 52)
	leave.add_theme_font_size_override("font_size", 17)
	leave.add_theme_stylebox_override("normal", _big_accent_style())
	var leave_hover: StyleBoxFlat = _big_accent_style()
	leave_hover.bg_color = UITheme.color("accent_hover")
	leave.add_theme_stylebox_override("hover", leave_hover)
	leave.add_theme_stylebox_override("pressed", leave_hover)
	var leave_disabled: StyleBoxFlat = _big_accent_style()
	leave_disabled.bg_color.a = 0.4
	leave.add_theme_stylebox_override("disabled", leave_disabled)
	leave.add_theme_color_override("font_color", UITheme.color("text_on_accent"))
	leave.add_theme_color_override("font_disabled_color", UITheme.color("text_on_accent"))
	leave.pressed.connect(_leave)

## 结束商店大按钮的 accent 样式（alpha 控制正常/悬停/禁用）。
func _big_accent_style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = UITheme.color("accent")
	st.set_corner_radius_all(10)
	st.set_content_margin_all(10)
	st.border_color = UITheme.color("accent_hover")
	st.set_border_width_all(1)
	return st

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_leave()
		get_viewport().set_input_as_handled()

## 结束商店（跳过剩余遗物+道具卡）。面板保持显示，由快照刷新为“已结束”。
func _leave() -> void:
	if _done:
		return
	if _on_skip.is_valid():
		_on_skip.call()
