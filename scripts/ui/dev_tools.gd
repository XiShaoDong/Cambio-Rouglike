class_name DevTools
extends RefCounted
## 开发工具（main.gd 拆分 · 第五优先级）
## 职责：F12 布局调试、T 主题切换。正式构建可直接移除。

var main: Node
var _layout_debug := false
var _theme_index := 0

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
			_theme_index = (_theme_index + 1) % UITheme.TOKENS.size()
			var names: Array = UITheme.TOKENS.keys()
			UITheme.switch_theme(str(names[_theme_index]))
			_rebuild_theme()
			return true
		elif event.keycode == KEY_O:
			GameState.debug_duel = not GameState.debug_duel
			main._show_toast("调试贴牌 %s：不判正确性，双贴即比拼" % ("ON" if GameState.debug_duel else "OFF"))
			return true
	return false

func _apply_layout_debug() -> void:
	var colors := [Color(1, 0, 0, 0.45), Color(0, 1, 0, 0.45), Color(0, 0, 1, 0.45), Color(1, 1, 0, 0.45), Color(1, 0, 1, 0.45)]
	var index := 0
	_tint_children(main, colors, index)

func _rebuild_theme() -> void:
	main.background.color = UITheme.color("bg_table")
	if not main.latest_state.is_empty():
		main._render_game()
	else:
		main._set_status("主题已切换：%s" % UITheme.current)

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
