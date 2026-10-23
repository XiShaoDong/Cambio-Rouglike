class_name DevTools
extends RefCounted
## 开发工具（main.gd 拆分 · 第五优先级）
## 职责：T 开发者模式（房主面板：直接判玩家出局 / 抢牌调试）、F12 布局调试。
## 主题切换走 ESC 设置菜单；正式构建可直接移除。

## 测试效果选项（id 与 GameState.TURN_EFFECT_IDS 对齐；空 = 正常随机）。
const TEST_EFFECTS := [
	{"id": "", "name": "随机效果"},
	{"id": "none", "name": "无效果"},
	{"id": "six_swap", "name": "6（抽牌堆全 6）"},
	{"id": "plus_one", "name": "左下角 +1（手牌全 A）"},
	{"id": "bomb", "name": "炸弹（抽牌堆全炸弹）"},
]

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
		elif event.keycode == KEY_F10 or event.keycode == KEY_V:
			main._toggle_table3d()
			return true
	return false

## 开发者面板刷新：dev 模式 + 房主 + 对局中时显示（右上角），否则移除。
## 由 main._on_state_updated 每帧快照渲染后调用。
func refresh_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
		_panel = null
	if not main.dev_mode or not main.is_room_host() or main.latest_state.is_empty():
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
	# 内容可能超过屏幕（4 人 + 皮肤 + 测试项）：用 ScrollContainer 限制高度并滚动。
	var content_w := 260.0
	var panel_w := content_w + 16.0  # 加上 PanelContainer 左右 content margin
	var max_h := maxf(240.0, main.size.y - 48.0)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(content_w, max_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)
	var title := Label.new()
	title.text = "开发者工具（房主）"
	title.add_theme_color_override("font_color", UITheme.color("accent"))
	box.add_child(title)
	_build_test_mode_row(box)
	_build_camera_row(box)
	var slap_btn := Button.new()
	slap_btn.text = "抢牌调试（不限时不限牌）：%s" % ("ON" if GameState.debug_duel else "OFF")
	slap_btn.clip_text = true
	slap_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	slap_btn.pressed.connect(_toggle_slap_debug)
	box.add_child(slap_btn)
	_build_skin_row(box)
	var preview_btn := Button.new()
	preview_btn.text = "3D 预览（F10 / V）"
	preview_btn.pressed.connect(main._toggle_table3d)
	box.add_child(preview_btn)
	for player in main.latest_state.players:
		var seat := int(player.id)
		var alive := not bool(player.get("eliminated", false))
		var btn := Button.new()
		btn.text = "出局 %s%s" % [str(player.name), "" if alive else "（已出局）"]
		btn.disabled = not alive
		btn.clip_text = true
		btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		btn.pressed.connect(main._dev_eliminate.bind(seat))
		box.add_child(btn)
	main.add_child(panel)
	# 放左上角：右上角留给「本局效果」面板，避免 dev 面板把效果 UI 挡住。
	# z_index 高于四角 HUD（左下按键/回合徽标），开发模式下面板始终可点。
	panel.z_index = 100
	panel.position = Vector2(12, 12)
	_panel = panel

## 测试模式：强制本局效果 + 按效果准备固定牌堆/手牌（下一局/重开生效）。
func _build_test_mode_row(box: VBoxContainer) -> void:
	var toggle := Button.new()
	toggle.text = "测试模式：%s" % ("ON" if GameState.dev_test_mode else "OFF")
	toggle.pressed.connect(_toggle_test_mode)
	box.add_child(toggle)
	var label := Label.new()
	label.text = "测试效果（选择后自动重开）"
	label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	box.add_child(label)
	var opt := OptionButton.new()
	opt.clip_text = true
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected := 0
	for i in TEST_EFFECTS.size():
		var entry: Dictionary = TEST_EFFECTS[i]
		opt.add_item(str(entry["name"]), i)
		if str(entry["id"]) == str(GameState.dev_test_effect):
			selected = i
	opt.selected = selected
	opt.disabled = not GameState.dev_test_mode
	opt.item_selected.connect(_on_test_effect_selected)
	box.add_child(opt)
	var restart := Button.new()
	restart.text = "重开本局（应用测试）"
	restart.pressed.connect(_restart_with_test)
	box.add_child(restart)

func _toggle_test_mode() -> void:
	GameState.dev_test_mode = not GameState.dev_test_mode
	if GameState.dev_test_mode and GameState.dev_test_effect.is_empty():
		# 默认用 +1 做可见的测试；可再选其他效果/随机。
		GameState.dev_test_effect = "plus_one"
	main._show_toast("测试模式 %s" % ("ON（已应用）" if GameState.dev_test_mode else "OFF"))
	if not GameState.dev_test_mode and main._fly_tool.active:
		# 测试模式关闭：飞行相机一并停（ belonging to T 开发者功能）
		main._fly_tool.stop()
		if main.table3d != null and is_instance_valid(main.table3d):
			main.table3d.set_fly_mode(false)
	if GameState.dev_test_mode and Network.is_host:
		_restart_with_test()
	else:
		refresh_panel()

func _on_test_effect_selected(index: int) -> void:
	if index < 0 or index >= TEST_EFFECTS.size():
		return
	GameState.dev_test_effect = str(TEST_EFFECTS[index]["id"])
	var label := str(TEST_EFFECTS[index]["name"])
	main._show_toast("测试效果：%s" % label)
	# 测试模式下选效果立即重开本局，避免玩家以为没生效。
	if GameState.dev_test_mode and Network.is_host:
		_restart_with_test()
	else:
		refresh_panel()

func _restart_with_test() -> void:
	if not Network.is_host:
		return
	GameState.request_restart_match(main._next_action_id())
	main._show_toast("已重开本局，应用测试设置")

## 「摄像机视角」：默认视角 / 自由视角 1（F 保存）。
func _build_camera_row(box: VBoxContainer) -> void:
	var lbl := Label.new()
	lbl.text = "摄像机视角"
	lbl.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	box.add_child(lbl)
	var default_btn := Button.new()
	default_btn.text = "默认视角（R）"
	default_btn.pressed.connect(func(): main._fly_camera_set_default())
	box.add_child(default_btn)
	var saved_btn := Button.new()
	saved_btn.text = "自由视角 1（%s）" % ("已保存，F=重设" if main._fly_tool.has_saved() else "未保存，飞行中按 F")
	saved_btn.disabled = not main._fly_tool.has_saved()
	saved_btn.pressed.connect(func(): main._fly_camera_set_saved())
	box.add_child(saved_btn)

## 抢牌调试开关：debug_duel（不判正确性→贴错无罚牌；收集窗 400ms→30s 不限时）。
func _toggle_slap_debug() -> void:
	GameState.debug_duel = not GameState.debug_duel
	main._show_toast("抢牌调试 %s：不判正确性，双贴即比拼" % ("ON" if GameState.debug_duel else "OFF"))
	refresh_panel()

## 卡牌皮肤：全局单选（原始/普通/石头/纸牌/玻璃），仅影响客户端渲染，默认 original。
func _build_skin_row(box: VBoxContainer) -> void:
	var label := Label.new()
	label.text = "卡牌皮肤"
	label.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	box.add_child(label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for type in CardAtlas.SKINS:
		var btn := Button.new()
		btn.text = _skin_label(type)
		btn.disabled = CardAtlas.preview() == type
		btn.pressed.connect(_set_skin.bind(type))
		grid.add_child(btn)

func _set_skin(type: String) -> void:
	CardAtlas.set_preview_type(type)
	main._show_toast("卡牌皮肤：%s" % _skin_label(type))
	main._render_game_if_active()
	refresh_panel()

func _skin_label(type: String) -> String:
	match type:
		"stone": return "石头"
		"paper": return "纸牌"
		"glass": return "玻璃"
		"normal": return "普通"
		_: return "原始"

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
