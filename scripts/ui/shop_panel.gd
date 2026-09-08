class_name ShopPanel
extends Control
## 商店盲拍面板：点击/数字键选遗物，W/S 调出价（+1 步进，下限起拍价，上限货币），Enter 确认，Esc/按钮跳过。

var _selected := 0
var _amount := 0
var _currency := 0
var _min_bids: Array = []
var _on_bid: Callable = Callable()
var _on_skip: Callable = Callable()

func setup(state: Dictionary, on_bid: Callable, on_skip: Callable) -> void:
	_on_bid = on_bid
	_on_skip = on_skip
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_currency = 0
	for player in state.get("players", []):
		if int(player.id) == int(state.get("viewer_id", -1)):
			_currency = int(player.get("currency", 0))
			break
	var title: Label = get_node("Center/Panel/VBox/Title")
	var limit: int = int((state.get("run", {}) as Dictionary).get("match_limit", KongRules.DEFAULT_MATCH_LIMIT))
	title.text = "商店 · 第 %d / %d 局" % [int(state.get("match_number", 1)), limit]
	_build_offers(state.get("shop", {}))
	_refresh()

func _build_offers(shop: Dictionary) -> void:
	var box: VBoxContainer = get_node("Center/Panel/VBox/Offers")
	for child in box.get_children():
		child.queue_free()
	_min_bids.clear()
	var offers: Array = shop.get("offers", [])
	for i in offers.size():
		var offer: Dictionary = offers[i]
		_min_bids.append(int(offer.get("min_bid", 2)))
		var btn := Button.new()
		btn.text = "%s　起拍 %d　·　%d 人选择" % [str(offer.name), int(offer.min_bid), int(offer.get("bidders", 0))]
		btn.pressed.connect(func() -> void: _select(i))
		box.add_child(btn)
	if _min_bids.is_empty():
		_min_bids.append(2)
	_amount = _min_bids[_selected]

func _select(i: int) -> void:
	_selected = i
	_amount = _min_bids[i]
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_W or event.keycode == KEY_UP:
			_change_step(1); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S or event.keycode == KEY_DOWN:
			_change_step(-1); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_confirm(); get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_skip(); get_viewport().set_input_as_handled()

func _ready() -> void:
	var panel: PanelContainer = get_node("Center/Panel")
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.color("bg_elevated")
	style.bg_color.a = 1.0
	style.set_corner_radius_all(12)
	style.set_content_margin_all(20)
	style.border_color = UITheme.color("border")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	var hint: Label = get_node("Center/Panel/VBox/Hint")
	var minus: Button = get_node("Center/Panel/VBox/Buttons/Minus")
	var plus: Button = get_node("Center/Panel/VBox/Buttons/Plus")
	var confirm: Button = get_node("Center/Panel/VBox/Actions/Confirm")
	var skip: Button = get_node("Center/Panel/VBox/Actions/Skip")
	minus.mouse_entered.connect(func() -> void: hint.text = "S/↓　出价 −1（下限起拍价）")
	minus.mouse_exited.connect(func() -> void: hint.text = "")
	plus.mouse_entered.connect(func() -> void: hint.text = "W/↑　出价 +1（上限 %d 货币）" % _currency)
	plus.mouse_exited.connect(func() -> void: hint.text = "")
	confirm.mouse_entered.connect(func() -> void: hint.text = "Enter　确认出价（%d）" % _amount)
	confirm.mouse_exited.connect(func() -> void: hint.text = "")
	skip.mouse_entered.connect(func() -> void: hint.text = "Esc　跳过商店")
	skip.mouse_exited.connect(func() -> void: hint.text = "")
	minus.pressed.connect(func() -> void: _change_step(-1))
	plus.pressed.connect(func() -> void: _change_step(1))
	confirm.pressed.connect(_confirm)
	skip.pressed.connect(_skip)

func _refresh() -> void:
	var cur: Label = get_node("Center/Panel/VBox/Currency")
	cur.text = "当前货币：%d" % _currency
	var amount_lbl: Label = get_node("Center/Panel/VBox/BidAmount")
	amount_lbl.text = "出价：%d" % _amount
	var confirm: Button = get_node("Center/Panel/VBox/Actions/Confirm")
	confirm.text = "确认出价（%d）" % _amount
	var status: Label = get_node("Center/Panel/VBox/Status")
	status.text = "选择一件遗物出价（密封，仅显示人数）…"

func _change_step(dir: int) -> void:
	var max_bid := mini(100, _currency)  # 上限 100 或货币
	_amount = clampi(_amount + dir, _min_bids[_selected], max_bid)
	_refresh()

func _confirm() -> void:
	if _on_bid.is_valid():
		_on_bid.call(_selected, _amount)
	visible = false

func _skip() -> void:
	if _on_skip.is_valid():
		_on_skip.call()
	visible = false