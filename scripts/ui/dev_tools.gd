class_name DevTools
extends RefCounted
## 开发工具（main.gd 拆分 · 第五优先级）
## 职责：T 开发者模式（房主面板：直接判玩家出局 / 抢牌调试）、F12 布局调试。
## 主题切换走 ESC 设置菜单；正式构建可直接移除。

var main: Node
var _layout_debug := false
var _panel: Control = null

func _init(owner_node: Node) -> void:
	main = owner_node

## 处理开发快捷键；返回 true 表示已消费。
func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			_layout_debug = not _layout_debug
			_apply_layout_debug()
			return true
		elif event.keycode == KEY_T:
			main.dev_mode = not main.dev_mode
			main._show_toast("开发者模式 %s" % ("ON" if main.dev_mode else "OFF"))
			refresh_panel()
			return true
	return false

## 开发者面板刷新：dev 模式 + 房主 + 对局中时显示（右上角），否则移除。
## 由 main._on_state_updated 每帧快照渲染后调用。
func refresh_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
		_panel = null
	if not main.dev_mode or not Network.is_host or main.latest_state.is_empty():
		return
	if int(main.latest_state.get("phase", 0)) == GameState.Phase.LOBBY:
		return
	var panel := PanelContainer.new()
	panel.name = "DevPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.color("bg_elevated")
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	style.border_color = UITheme.color("accent")
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := Label.new()
	title.text = "开发者工具（房主）"
	title.add_theme_color_override("font_color", UITheme.color("accent"))
	box.add_child(title)
	var slap_btn := Button.new()
	slap_btn.text = "抢牌调试（不限时不限牌）：%s" % ("ON" if GameState.debug_duel else "OFF")
	slap_btn.pressed.connect(_toggle_slap_debug)
	box.add_child(slap_btn)
	for player in main.latest_state.players:
		var seat := int(player.id)
		var alive := not bool(player.get("eliminated", false))
		var btn := Button.new()
		btn.text = "出局 %s%s" % [str(player.name), "" if alive else "（已出局）"]
		btn.disabled = not alive
		btn.pressed.connect(main._dev_eliminate.bind(seat))
		box.add_child(btn)
	main.add_child(panel)
	panel.z_index = 60
	panel.position = Vector2(main.size.x - 232, 12)
	_panel = panel

## 抢牌调试开关：debug_duel（不判正确性→贴错无罚牌；收集窗 400ms→30s 不限时）。
func _toggle_slap_debug() -> void:
	GameState.debug_duel = not GameState.debug_duel
	main._show_toast("抢牌调试 %s：不判正确性，双贴即比拼" % ("ON" if GameState.debug_duel else "OFF"))
	refresh_panel()

func _apply_layout_debug() -> void:
	var colors := [Color(1, 0, 0, 0.45), Color(0, 1, 0, 0.45), Color(0, 0, 1, 0.45), Color(1, 1, 0, 0.45), Color(1, 0, 1, 0.45)]
	var index := 0
	_tint_children(main, colors, index)

func _tint_children(node: Node, colors: Array, depth: int) -> void:
	if node is Control:
		var ctl: Control = node
		if _layout_debug:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(1, 1, 1, 0.04)
			style.border_color = colors[depth % colors.size()]
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
			ctl.add_theme_stylebox_override("panel", style)
			ctl.add_theme_stylebox_override("normal", style)
			ctl.set_meta("debug_style", style)
		else:
			if ctl.has_meta("debug_style"):
				ctl.remove_theme_stylebox_override("panel")
				ctl.remove_theme_stylebox_override("normal")
				ctl.remove_meta("debug_style")
	for child in node.get_children():
		_tint_children(child, colors, depth + 1)
