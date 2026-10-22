extends Node
## headless 单元测试：L1 大厅（Task 1）——服务器权威 Ready + lobby 快照字段（ready/your_id/room_host）。

var failures := 0
var checks := 0
var last_lobby: Dictionary = {}

func _ready() -> void:
	GameState.lobby_updated.connect(func(l: Dictionary): last_lobby = l)
	_test_ready_default()
	_test_set_ready_broadcast()
	_test_snapshot_fields()
	_test_non_lobby_rejected()
	_test_ready_reset_on_match()
	_test_host_seat()
	_test_kick()
	_test_match_limit_sync()
	_test_dark1_theme()
	await _test_lobby_ui()
	print("=== LOBBY RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _setup_two() -> void:
	GameState._reset_match()
	GameState._add_player(1, "Host")
	GameState._add_player(2, "Client")

func _test_ready_default() -> void:
	_setup_two()
	_check("默认 ready=false", not bool(GameState.players[0].get("ready", false)) and not bool(GameState.players[1].get("ready", false)))

func _test_set_ready_broadcast() -> void:
	_setup_two()
	last_lobby = {}
	GameState._server_set_ready(1, true)
	_check("set_ready 写座位", bool(GameState.players[1].get("ready", false)))
	_check("set_ready 广播 lobby", not last_lobby.is_empty())
	var found := false
	for e in last_lobby.get("players", []):
		if int(e.get("id", -1)) == 1 and bool(e.get("ready", false)):
			found = true
	_check("广播快照含 ready=true", found)

func _test_snapshot_fields() -> void:
	_setup_two()
	var snap: Dictionary = GameState._lobby_snapshot(1)
	_check("snapshot your_id", int(snap.get("your_id", -1)) == 1)
	_check("snapshot room_host", int(snap.get("room_host", -1)) == 0)
	_check("snapshot host_id == room_host", int(snap.get("host_id", -1)) == int(snap.get("room_host", -2)))

func _test_non_lobby_rejected() -> void:
	_setup_two()
	GameState.phase = GameState.Phase.TURN_DRAW
	GameState._server_set_ready(1, true)
	_check("非 LOBBY 不改 ready", not bool(GameState.players[1].get("ready", false)))

func _test_ready_reset_on_match() -> void:
	_setup_two()
	GameState._server_set_ready(0, true)
	GameState._server_set_ready(1, true)
	_check("开局前 ready=true", bool(GameState.players[0].get("ready", false)) and bool(GameState.players[1].get("ready", false)))
	GameState._server_start_match(0)
	_check("开局后 ready 重置", not bool(GameState.players[0].get("ready", false)) and not bool(GameState.players[1].get("ready", false)))

func _test_host_seat() -> void:
	# 首个进入者 = 房主 = seat 0（三人：seat0/1/2）
	GameState._reset_match()
	GameState._add_player(1, "Host")
	GameState._add_player(2, "B")
	GameState._add_player(3, "C")
	_check("首个进入者 host_seat=0", GameState.host_seat == 0)
	# 非房主开局：被拒 → 仍在 LOBBY
	GameState._server_start_match(1)
	_check("非房主开局被拒（仍 LOBBY）", GameState.phase == GameState.Phase.LOBBY)
	# 房主离开（LOBBY）→ 转移
	GameState._on_peer_left(1)  # peer1 = seat0 = 房主离开
	_check("房主离开后转移 host_seat=1", GameState.host_seat == 1)
	_check("离开者座位移除", not GameState.players.has(0))
	# 新房主（seat1）现在可开局（剩 seat1/2 共 2 人）
	GameState._server_start_match(1)
	_check("转移后新房主可开局", GameState.phase != GameState.Phase.LOBBY)
	# 房间清空后，下一批首进入者重认房主
	GameState._reset_match()
	GameState._add_player(5, "New")
	_check("清空后首进入者重认房主", GameState.host_seat == 0 and GameState.players.has(0))

func _test_kick() -> void:
	GameState._reset_match()
	GameState._add_player(1, "Host")  # seat0
	GameState._add_player(2, "B")     # seat1
	GameState._add_player(3, "C")     # seat2
	GameState._server_kick(1, 2)
	_check("非房主踢无效", GameState.players.has(2))
	GameState._server_kick(0, 0)
	_check("踢房主无效", GameState.players.has(0))
	GameState._server_kick(0, 2)
	_check("房主踢出在线者", not GameState.players.has(2))
	_check("被踢者不在 turn_order", not 2 in GameState.turn_order)
	_check("踢非房主后 host_seat 不变", GameState.host_seat == 0)
	# 踢出唯一非房主后仍剩 host → 房间不销毁
	GameState._server_kick(0, 1)
	_check("踢出后剩房主一人", GameState.players.size() == 1 and GameState.players.has(0))

func _test_match_limit_sync() -> void:
	_setup_two()
	GameState.run_state["match_limit"] = 5
	last_lobby = {}
	GameState._server_set_match_limit(1, 7, "ml1")
	_check("非房主修改局数被拒", int(GameState.run_state["match_limit"]) == 5)
	GameState._server_set_match_limit(0, 8, "ml2")
	_check("房主修改局数同步", int(GameState.run_state["match_limit"]) == 8 and not last_lobby.is_empty())
	var snap: Dictionary = GameState._lobby_snapshot(0)
	_check("lobby 快照含同步局数", int(snap.get("match_limit", 0)) == 8)
	GameState._server_set_match_limit(0, 99, "ml3")
	_check("局数夹到上限", int(GameState.run_state["match_limit"]) == KongRules.MAX_MATCH_LIMIT)

func _test_dark1_theme() -> void:
	var before := UITheme.current
	UITheme.switch_theme("dark-1")
	_check("dark-1 底色/靛蓝强调", UITheme.color("bg_table") == Color("151821") \
		and UITheme.color("accent") == Color("526BDE"))
	_check("dark-1 主按钮文字色", UITheme.color("text_on_accent") == Color("FFFFFF"))
	var sm := SettingsMenu.new()
	add_child(sm)
	_check("设置菜单有 dark/dark-1/light 三项", sm._theme_option.item_count == 3)
	_check("设置菜单有自动/宽屏/紧凑布局", sm._lobby_layout_option.item_count == 3)
	sm.queue_free()
	UITheme.switch_theme(before)

## 大厅 UI 两态 + 槽位 + 按钮可见性（headless 实例化 main 场景驱动）。
func _test_lobby_ui() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	scene.lobby.layout_mode_override = "compact"
	scene.lobby.refresh_layout()
	_check("大厅主面板居中容器存在", scene.lobby._panel != null)
	_check("玩家信息框昵称/编辑按钮存在", scene.lobby._nickname_label != null and scene.lobby._edit_button != null)
	_check("高级连接折叠栏存在", scene.lobby._advanced_toggle != null and scene.lobby._advanced_box != null)
	_check("重连入口默认隐藏", scene.lobby._rejoin_button != null and not scene.lobby._rejoin_button.visible)
	_check("昵称显示与输入一致", scene.lobby._nickname_label.text == scene.name_input.text.strip_edges())
	var snap_guest := {
		"players": [{"id": 0, "name": "Host", "ready": false}, {"id": 1, "name": "Me", "ready": true}],
		"host_id": 0, "room_host": 0, "your_id": 1,
		"min_players": 2, "max_players": 4, "match_limit": 5,
	}
	scene.lobby.update_lobby(snap_guest)
	_check("客人：显示房间态", scene.lobby._room_box.visible and not scene.lobby._menu_box.visible)
	_check("房间无滚动容器", scene.lobby._room_box.get_parent() == scene.lobby_panel)
	_check("大厅背景图存在且不拦截输入", scene.lobby_bg != null and scene.lobby_bg.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("槽位数量 = max_players", scene.lobby._slots_box.get_child_count() == 4)
	_check("客人：见准备按钮、无开始", scene.lobby._ready_button.visible and not scene.lobby._start_button.visible)
	_check("客人：准备按钮文案=取消准备", scene.lobby._ready_button.text == "取消准备")
	var seats: GridContainer = scene.lobby._slots_box
	_check("固定 4 个席位", seats.get_child_count() == 4)
	_check("座位初始为 2×2", seats.columns == 2)
	_check("席位号码稳定", (seats.get_child(0) as LobbySeatCard).seat_number() == 1 \
		and (seats.get_child(3) as LobbySeatCard).seat_number() == 4)
	_check("房主席位显示房主徽章", (seats.get_child(0) as LobbySeatCard).has_host_badge())
	_check("空席位显示等待加入", (seats.get_child(3) as LobbySeatCard).is_empty_seat() \
		and (seats.get_child(3) as LobbySeatCard).status_text().contains("等待加入"))
	_check("客人局数只读", scene.lobby._match_minus.disabled and scene.lobby._match_plus.disabled)
	_check("客人无解散、有离开", not scene.lobby._disband_button.visible and scene.lobby._leave_button.visible)

	var snap_host_ready := snap_guest.duplicate(true)
	snap_host_ready["your_id"] = 0
	scene.lobby.update_lobby(snap_host_ready)
	_check("房主：见开始/解散", scene.lobby._start_button.visible and scene.lobby._disband_button.visible)
	_check("房主：全员 ready → 开始可用", not scene.lobby._start_button.disabled)
	_check("房主：可改局数", not scene.lobby._match_minus.disabled or scene.lobby._match_limit_value <= KongRules.MIN_MATCH_LIMIT)
	_check("房主：解散按钮存在且带确认", scene.lobby._disband_button.visible and scene.lobby._disband_dialog != null)

	var snap_host_wait := snap_host_ready.duplicate(true)
	snap_host_wait["players"] = [{"id": 0, "name": "Host", "ready": false}, {"id": 1, "name": "Me", "ready": false}]
	scene.lobby.update_lobby(snap_host_wait)
	_check("房主：有人未 ready → 开始禁用", scene.lobby._start_button.disabled)

	scene.lobby.reset_lobby()
	_check("reset_lobby 回主菜单态", scene.lobby._menu_box.visible and not scene.lobby._room_box.visible)
	# 主题切换重建大厅后仍保持 4 个稳定席位
	scene.lobby.update_lobby(snap_guest)
	UITheme.switch_theme("dark-1")
	scene.lobby.apply_theme()
	_check("dark-1 切换后大厅重建", scene.lobby._slots_box != null and scene.lobby._slots_box.get_child_count() == 4)
	UITheme.switch_theme("dark")
	scene.lobby.apply_theme()
	# 宽屏布局：三列、席位纵向列表、中央舞台、右侧设置
	scene.lobby.layout_mode_override = "wide"
	scene.lobby.refresh_layout()
	scene.lobby.update_lobby(snap_guest)
	_check("宽屏：面板变宽", scene.lobby._panel.custom_minimum_size.x > 700.0)
	_check("宽屏：席位纵向列表", scene.lobby._slots_box is VBoxContainer and scene.lobby._slots_box.get_child_count() == 4)
	_check("宽屏：中央舞台存在", scene.lobby._center_art != null and scene.lobby._center_art.get_child_count() == 3)
	_check("宽屏：中央房间码卡", not scene.lobby._share_field.text.is_empty())
	_check("宽屏：右侧主按钮", scene.lobby._start_button != null and scene.lobby._invite_button != null)
	scene.queue_free()
	await get_tree().process_frame
