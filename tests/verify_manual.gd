extends Node
## headless 单元测试：手册数据（ManualModel）+ 左下角按键提示（KeyHintPanel）+ 3D 手册面板开关。

var failures := 0
var checks := 0
var main_node: Node

func _ready() -> void:
	await _run()
	print("=== MANUAL RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _state() -> Dictionary:
	return {
		"phase": 2, "phase_name": "p", "viewer_id": 0, "current_player": 0, "current_name": "A",
		"players": [
			{"id": 0, "name": "A", "slots": [{}, {}, {}, {}], "health": 2, "currency": 100, "count": 4, "eliminated": false},
			{"id": 1, "name": "B", "slots": [{}, {}, {}, {}], "health": 2, "currency": 100, "count": 4, "eliminated": false},
		],
		"draw_count": 40, "discard": {}, "pending": {}, "event_log": [], "match_number": 2,
		"slap_rank": "", "slap_open": false, "slap_exchange_actor": 0, "kong_caller": -1,
		"ready_count": 0, "result": {}, "run": {"match_limit": 5}, "q_decision": {},
	}

func _run() -> void:
	UITheme.current = "dark"
	# ManualModel：顺序 / 分数 / 能力
	var rows: Array = ManualModel.rows()
	_check("手册 14 行", rows.size() == 14)
	_check("顺序 A 开头", str(rows[0].rank) == "A")
	_check("顺序 Joker 结尾", str(rows[13].rank) == "Joker")
	_check("A 分 1", int(rows[0].score) == 1)
	_check("J 分 10", int(rows[10].score) == 10)
	_check("K 分 -1", int(rows[12].score) == -1)
	_check("Joker 分 0", int(rows[13].score) == 0)
	_check("7 有能力", str(rows[6].power) != ManualModel.NO_POWER)
	_check("A 无能力", str(rows[0].power) == ManualModel.NO_POWER)
	_check("K 无能力", str(rows[12].power) == ManualModel.NO_POWER)
	_check("Joker 无能力", str(rows[13].power) == ManualModel.NO_POWER)
	_check("J 能力含盲换", "盲换" in str(rows[10].power))

	# KeyHintPanel：说明纯白无边框 + 按键 chip 圆角半透明灰底黑字
	var kh := KeyHintPanel.new()
	add_child(kh)
	kh.setup([["放大", "Command"], ["手册", "Tab"]])
	await get_tree().process_frame
	_check("提示 2 行", kh.row_count() == 2)
	_check("行1 说明=放大", kh.desc_text(0) == "放大")
	_check("行1 按键=Command（无括号）", kh.key_text(0) == "Command")
	_check("行2 按键=Tab（无括号）", kh.key_text(1) == "Tab")
	var st: StyleBoxFlat = kh.chip_style(0)
	_check("chip 半透明灰底", st.bg_color.a > 0.0 and st.bg_color.a < 1.0)
	_check("chip 圆角", st.corner_radius_top_left > 0)
	_check("chip 有边框", st.border_width_top >= 1)
	kh.queue_free()

	# 3D 下：左下角提示存在；Tab 开/关手册
	var scene: PackedScene = load("res://scenes/main.tscn")
	main_node = scene.instantiate()
	add_child(main_node)
	await get_tree().process_frame
	await get_tree().process_frame
	main_node.latest_state = _state()
	main_node._set_table3d(true)
	await get_tree().process_frame
	_check("3D 左下角按键提示存在", main_node._key_hints != null and is_instance_valid(main_node._key_hints))
	_check("3D 按键提示可见", main_node._key_hints.visible)
	_check("3D 按键提示 2 行", main_node._key_hints.row_count() == 2)
	# 右上角回合徽标（同款 chip 样式，字号 = Command ×2，实时）
	_check("3D 右上角回合徽标存在", main_node._round_badge != null and is_instance_valid(main_node._round_badge))
	_check("回合徽标可见", main_node._round_badge.visible)
	var rl: Label = main_node._round_badge.get_node_or_null("Key")
	_check("回合徽标文本 回合 2/5", rl != null and rl.text == "回合 2/5")
	_check("回合徽标字号 = 原两倍再缩小 1/3", rl != null and rl.get_theme_font_size("font_size") == KeyHintPanel.ROUND_FONT_SIZE)
	_check("回合徽标左右内边距更宽", (main_node._round_badge.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left >= 12.0)
	# 四个角 UI 统一边距（目标屏幕像素 75 → 补偿拉伸后的设计坐标）
	var m: float = float(int(round(main_node._corner_margin())))
	_check("左下角边距=75px 换算值", is_equal_approx(main_node._key_hints.offset_left, m) and is_equal_approx(main_node._key_hints.offset_bottom, -m))
	_check("右上角边距=75px 换算值", is_equal_approx(main_node._round_badge.offset_right, -m) and is_equal_approx(main_node._round_badge.offset_top, m))
	_check("右下角边距=75px 换算值", is_equal_approx(main_node._self_panel.offset_right, -m) and is_equal_approx(main_node._self_panel.offset_bottom, -m))
	# 背景纯白（保留透明度）+ 字体纯白
	var chip_bg := KeyHintPanel.chip_style_box().bg_color
	_check("chip 背景纯白", chip_bg.r > 0.999 and chip_bg.g > 0.999 and chip_bg.b > 0.999)
	_check("chip 保留透明度", is_equal_approx(chip_bg.a, KeyHintPanel.CORNER_BG_ALPHA))
	var chip = KeyHintPanel.make_chip("x")
	_check("chip 字体纯白", (chip.get_node("Key") as Label).get_theme_color("font_color") == Color(1, 1, 1))
	var self_bg: StyleBoxFlat = main_node._self_panel.frame_panel().get_theme_stylebox("panel")
	_check("自身面板背景纯白", self_bg.bg_color.r > 0.999 and self_bg.bg_color.g > 0.999 and self_bg.bg_color.b > 0.999)
	main_node._toggle_manual()
	await get_tree().process_frame
	_check("Tab 打开手册", main_node.manual_panel != null and is_instance_valid(main_node.manual_panel))
	var grid: GridContainer = main_node.manual_panel.get_node_or_null("Center/Panel/VBox/Grid")
	_check("手册三列", grid != null and grid.columns == 3)
	_check("手册 1 表头 + 14 行 = 45 格", grid != null and grid.get_child_count() == 45)
	main_node._toggle_manual()
	await get_tree().process_frame
	_check("再按 Tab 关闭手册", main_node.manual_panel == null)
	# S：打开 Stats 页（复用同一面板）
	main_node._toggle_manual(ManualPanel.TAB_STATS)
	await get_tree().process_frame
	_check("S 打开 Stats 页", main_node.manual_panel != null and is_instance_valid(main_node.manual_panel) and main_node.manual_panel.current_tab() == ManualPanel.TAB_STATS)
	var stats = main_node.manual_panel.stats_board()
	_check("Stats 板存在且可见", stats != null and stats.visible)
	_check("Stats 页时手册网格隐藏", not (main_node.manual_panel.get_node("Center/Panel/VBox/Grid") as Control).visible)
	_check("Stats 打开时看板对点击透明（可点卡牌）", main_node._manual_transparent() and not main_node._board_has_panel())
	main_node._toggle_manual(ManualPanel.TAB_STATS)
	await get_tree().process_frame
	_check("再按 S 关闭 Stats", main_node.manual_panel == null)
	# StatsBoard：分组 + 去重
	var sb := StatsBoard.new()
	add_child(sb)
	sb.setup([
		{"id": "s1", "rank": "A", "suit": "♠"},
		{"id": "h1", "rank": "K", "suit": "♥"},
		{"id": "jr", "rank": "JOKER", "suit": "red"},
		{"id": "jb", "rank": "JOKER", "suit": "black"},
		{"id": "s1", "rank": "A", "suit": "♠"},
	])
	await get_tree().process_frame
	_check("StatsBoard 去重后 4 张", sb.card_count() == 4)
	sb.queue_free()
	main_node._set_table3d(false)
	await get_tree().process_frame
	_check("退出 3D 后提示隐藏", not main_node._key_hints.visible)
	_check("退出 3D 后回合徽标隐藏", not main_node._round_badge.visible)
	_check("退出 3D 后手册已关", main_node.manual_panel == null)
	main_node.queue_free()
