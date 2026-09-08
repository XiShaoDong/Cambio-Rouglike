class_name BetPanel
extends Control
## 押注面板：W/S 调整押注额（入场 20，+5 递增，上限 100 或 ≤ 货币），Enter/按钮确认。
## 场景实体承载骨架；货币 < 入场时自动 all-in（amount=0）。

var _amount := KongRules.MIN_BET
var _currency := 0
var _all_in := false
var _on_confirm: Callable = Callable()

func setup(state: Dictionary, on_confirm: Callable) -> void:
	_on_confirm = on_confirm
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_currency = 0
	for player in state.get("players", []):
		if int(player.id) == int(state.get("viewer_id", -1)):
			_currency = int(player.get("currency", 0))
			break
	var title: Label = get_node("Center/Panel/VBox/Title")
	var limit: int = int((state.get("run", {}) as Dictionary).get("match_limit", KongRules.DEFAULT_MATCH_LIMIT))
	title.text = "押注 · 第 %d / %d 局" % [int(state.get("match_number", 1)), limit]
	if _currency < KongRules.MIN_BET:
		_all_in = true
		_amount = _currency
		var bet_lbl: Label = get_node("Center/Panel/VBox/BetAmount")
		bet_lbl.text = "ALL-IN %d" % _amount
		var hint: Label = get_node("Center/Panel/VBox/Hint")
		hint.text = "货币不足入场，自动全押 + 灵魂币（输则出局）"
		var confirm: Button = get_node("Center/Panel/VBox/Confirm")
		confirm.text = "确认 ALL-IN"
		get_node("Center/Panel/VBox/Buttons").visible = false
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_W or event.keycode == KEY_UP:
			_change_step(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_S or event.keycode == KEY_DOWN:
			_change_step(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_confirm()
			get_viewport().set_input_as_handled()

func _ready() -> void:
	get_node("Center/Panel/VBox/Buttons/Minus").pressed.connect(func() -> void: _change_step(-1))
	get_node("Center/Panel/VBox/Buttons/Plus").pressed.connect(func() -> void: _change_step(1))
	get_node("Center/Panel/VBox/Confirm").pressed.connect(_confirm)

func _refresh() -> void:
	if _all_in:
		return
	var cur: Label = get_node("Center/Panel/VBox/Currency")
	cur.text = "当前货币：%d" % _currency
	var bet_lbl: Label = get_node("Center/Panel/VBox/BetAmount")
	bet_lbl.text = "押注：%d" % _amount
	var confirm: Button = get_node("Center/Panel/VBox/Confirm")
	confirm.text = "确认押注（%d）" % _amount
	var status: Label = get_node("Center/Panel/VBox/Status")
	status.text = "等待其他玩家押注…"

func _change_step(dir: int) -> void:
	if _all_in:
		return
	var max_bet := mini(KongRules.MAX_BET, _currency)
	_amount = clampi(_amount + dir * KongRules.BET_STEP, KongRules.MIN_BET, max_bet)
	_refresh()

func _confirm() -> void:
	if _on_confirm.is_valid():
		_on_confirm.call(0 if _all_in else _amount)