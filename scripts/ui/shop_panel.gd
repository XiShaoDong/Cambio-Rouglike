class_name ShopPanel
extends Control
## 商店面板（按指定 layout 的 UI 版）：SHOP 标题 + CARDS 区（3 张卡 + 价格）+ RELICS 区（2 件遗物 + 价格）
## + 底部 💰 货币 + LEAVE SHOP。
## 目前仅 UI 展示，不可购买；LEAVE SHOP 走 on_leave（跳过商店）。
## 后续接入购买：卡牌加入全局牌组、遗物固定价购买。

const CARD_SCENE := preload("res://scenes/ui/card.tscn")
const CARD_PRICES := [80, 95, 65]
const RELIC_PRICES := [80, 95]
const RELIC_ICONS := ["◈", "◇"]

var _currency := 0
var _on_leave: Callable = Callable()

func setup(state: Dictionary, on_leave: Callable) -> void:
	_on_leave = on_leave
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_currency = 0
	for player in state.get("players", []):
		if int(player.id) == int(state.get("viewer_id", -1)):
			_currency = int(player.get("currency", 0))
			break
	_fill_cards()
	_fill_relics()
	var cur_lbl: Label = get_node("Center/Panel/VBox/Bottom/Currency")
	cur_lbl.text = "💰 %d" % _currency

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
	var pool: Array = Relics.pool()
	for i in mini(RELIC_PRICES.size(), pool.size()):
		var relic: Dictionary = pool[i]
		row.add_child(_make_relic_slot(RELIC_ICONS[i], str(relic.get("name", "")), RELIC_PRICES[i]))

func _make_relic_slot(icon: String, name: String, price: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	# 遗物可点击（toggle 选中态，购买流程占位）；卡牌不可点击
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 118)
	btn.toggle_mode = true
	btn.text = "%s\n%s" % [icon, name]
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
	box.add_child(btn)
	var price_lbl := Label.new()
	price_lbl.text = "$%d" % price
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 18)
	price_lbl.add_theme_color_override("font_color", UITheme.color("accent"))
	box.add_child(price_lbl)
	return box

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

func _leave() -> void:
	if _on_leave.is_valid():
		_on_leave.call()
	visible = false