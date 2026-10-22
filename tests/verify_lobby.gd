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
	_test_effect_mode_sync()
	_test_effect_phase_flow()
	_test_shop_enabled_gate()
	_test_back_to_lobby()
	_test_match_options()
	_test_refresh_price_curve()
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

## 玩法设置：效果模式（房间权威 + 快照下发）。
func _test_effect_mode_sync() -> void:
	_setup_two()
	last_lobby = {}
	GameState._server_set_effect_mode(1, "fixed", "bomb", "em1")
	_check("非房主设固定特效被拒", str(GameState.run_state["effect_mode"]) == "normal")
	GameState._server_set_effect_mode(0, "fixed", "bomb", "em2")
	_check("房主设 fixed 同步", str(GameState.run_state["effect_mode"]) == "fixed" \
		and str(GameState.run_state["fixed_effect"]) == "bomb" and not last_lobby.is_empty())
	var snap: Dictionary = GameState._lobby_snapshot(0)
	_check("lobby 快照含 effect_mode/fixed_effect", str(snap.get("effect_mode", "")) == "fixed" \
		and str(snap.get("fixed_effect", "")) == "bomb")
	GameState._server_set_effect_mode(0, "fixed", "none", "em3")
	_check("fixed 拒绝 none（==普通）", str(GameState.run_state["fixed_effect"]) == "bomb")
	GameState._server_set_effect_mode(0, "unknown", "", "em4")
	_check("非法 mode 拒绝", str(GameState.run_state["effect_mode"]) == "fixed")
	GameState._server_set_effect_mode(0, "normal", "", "em5")
	_check("房主切回 normal", str(GameState.run_state["effect_mode"]) == "normal")
	GameState.dev_test_mode = false
	GameState.turn_effect_id = ""
	GameState._roll_turn_effect()
	_check("normal 模式特效=none", GameState.turn_effect_id == "none")
	GameState._server_set_effect_mode(0, "fixed", "plus_one", "em6")
	GameState._roll_turn_effect()
	_check("fixed 模式特效=指定", GameState.turn_effect_id == "plus_one")
	GameState._server_set_effect_mode(0, "random", "", "em7")
	GameState.turn_effect_id = ""
	GameState._roll_turn_effect()
	_check("random 模式抽到合法 id", GameState.TURN_EFFECT_IDS.has(GameState.turn_effect_id))
	var prev := GameState.turn_effect_id
	var all_differ := true
	for i in 8:
		GameState._roll_turn_effect()
		if GameState.turn_effect_id == prev:
			all_differ = false
		prev = GameState.turn_effect_id
	_check("random 连抽不与上一局相同", all_differ)

## 玩法设置：效果阶段流（normal 直开回合 / fixed 走展示阶段）。
func _test_effect_phase_flow() -> void:
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_start_match(0, 2)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	_check("normal：全员 Ready 直开首回合（不进效果展示）", \
		GameState.phase == GameState.Phase.TURN_DRAW and GameState.turn_index == 1)
	GameState._reset_match()
	GameState._add_player(1, "A")
	GameState._add_player(2, "B")
	GameState._server_set_effect_mode(0, "fixed", "plus_one", "ef1")
	GameState._server_start_match(0, 2)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	_check("fixed：全员 Ready 进效果展示", GameState.phase == GameState.Phase.EFFECT_REVEAL)
	GameState._on_effect_reveal_timeout()
	_check("fixed：展示结束开首回合", GameState.phase == GameState.Phase.TURN_DRAW and GameState.turn_index == 1)

## 玩法设置：商店开关（非把末结算自动衔接）。
func _test_shop_enabled_gate() -> void:
	_setup_two()
	last_lobby = {}
	GameState._server_set_shop_enabled(1, false, "sh1")
	_check("非房主关商店被拒", bool(GameState.run_state["shop_enabled"]))
	GameState._server_set_shop_enabled(0, false, "sh2")
	_check("房主关商店同步", not bool(GameState.run_state["shop_enabled"]))
	var snap: Dictionary = GameState._lobby_snapshot(0)
	_check("lobby 快照含 shop_enabled", not bool(snap.get("shop_enabled", true)))
	# 关商店：GAME_OVER → 自动衔接直接开下一局（不进 SHOP）
	GameState._server_start_match(0, 3)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState.phase = GameState.Phase.GAME_OVER
	GameState._on_series_auto_advance()
	_check("关商店：结算直接开下一局", \
		GameState.phase == GameState.Phase.INITIAL_PEEK and GameState.match_number == 2)
	# 开商店：对照走 SHOP（match_limit=3，此刻第 2 局非把末）
	GameState.phase = GameState.Phase.LOBBY  # 回大厅（上一分支已开出第 2 局；设置仅 LOBBY 可改）
	GameState._server_set_shop_enabled(0, true, "sh3")
	GameState._server_start_match(0, 3)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	GameState.phase = GameState.Phase.GAME_OVER
	GameState._on_series_auto_advance()
	_check("开商店：结算进 SHOP", GameState.phase == GameState.Phase.SHOP)

## 系列赛把末 → 全体回到等待房间（保留座位/连接，新一届系列赛）。
func _test_back_to_lobby() -> void:
	_setup_two()
	GameState._server_set_effect_mode(0, "fixed", "bomb", "b1")
	GameState._server_start_match(0, 2)
	GameState._server_initial_ready(0)
	GameState._server_initial_ready(1)
	# 模拟把末：第 1 局、系列赛限一局（match_limit ≤2 越界由服务器回退，这里直改模拟结算态）
	GameState.run_state["match_limit"] = 1
	GameState.phase = GameState.Phase.GAME_OVER
	_check("把末：_series_finished 成立", GameState._series_finished())
	# 非房主被拒：状态不变
	GameState._server_back_to_lobby(1, "r1")
	_check("非房主回大厅被拒", GameState.phase == GameState.Phase.GAME_OVER)
	# 房主成功：回 LOBBY、保留座位、清空系列赛态、保留玩法设置
	GameState._server_back_to_lobby(0, "r2")
	_check("房主回大厅成功", GameState.phase == GameState.Phase.LOBBY)
	_check("座位保留且全员未准备", GameState.players.size() == 2 \
		and not bool(GameState.players[0].get("ready", false)) \
		and not bool(GameState.players[1].get("ready", false)))
	_check("系列赛数据清零（wins/货币/生命重置）", \
		int(GameState.players[0].get("wins", -1)) == 0 \
		and int(GameState.players[0].get("currency", -1)) == KongRules.START_CURRENCY \
		and int(GameState.players[1].get("health", -1)) == KongRules.START_HEALTH)
	_check("玩法设置沿用", str(GameState.run_state["effect_mode"]) == "fixed" \
		and str(GameState.run_state["fixed_effect"]) == "bomb" \
		and int(GameState.run_state["match_limit"]) == 1)
	var snap: Dictionary = GameState._lobby_snapshot(0)
	_check("回大厅广播快照", snap.get("players", []).size() == 2 and str(snap.get("effect_mode", "")) == "fixed")
	# 回大厅后可立即开新一届系列赛
	GameState._server_start_match(0, 1)
	_check("回大厅后可以重新开局", GameState.phase == GameState.Phase.INITIAL_PEEK)

## 对局详情：房主 set_match_options + 快照 + 新一届开局按设置重置经济。
func _test_match_options() -> void:
	_setup_two()
	last_lobby = {}
	GameState._server_set_match_options(1, 5, 300, 80, "mo1")
	_check("非房主改详情被拒", int(GameState.run_state["start_health"]) == KongRules.START_HEALTH)
	GameState._server_set_match_options(0, 5, 300, 80, "mo2")
	_check("房主改详情同步", int(GameState.run_state["start_health"]) == 5 \
		and int(GameState.run_state["start_currency"]) == 300 \
		and int(GameState.run_state["shop_price"]) == 80 and not last_lobby.is_empty())
	var snap: Dictionary = GameState._lobby_snapshot(0)
	_check("lobby 快照含详情字段", int(snap.get("start_health", 0)) == 5 \
		and int(snap.get("start_currency", 0)) == 300 and int(snap.get("shop_price", 0)) == 80)
	GameState._server_set_match_options(0, 99, -3, -50, "mo3")
	_check("详情数值 clamp", int(GameState.run_state["start_health"]) == 10 \
		and int(GameState.run_state["start_currency"]) == 0 \
		and int(GameState.run_state["shop_price"]) == 5)
	# 新一届开局：currency/health 按设置重置
	GameState._server_set_match_options(0, 3, 200, 50, "mo4")
	GameState._server_start_match(0, 2)
	_check("开局按详情重置经济", int(GameState.players[0].health) == 3 \
		and int(GameState.players[0].currency) == 200 \
		and int(GameState.players[1].currency) == 200)
	# 商店物价用 run_state.shop_price
	GameState._reset_match()
	GameState.run_state["shop_price"] = 70
	var def := Relics.joker_transform()
	var offer: Dictionary = GameState._offer_from_relic(0, def, false)
	_check("遗物货架价=设置价格", int(offer["price"]) == 70)
	var icard: Dictionary = ItemCards.pool()[0]
	var card_offer: Dictionary = GameState._offer_from_item_card(0, icard, false)
	_check("卡牌货架价=设置价格", int(card_offer["price"]) == 70)

## 刷新价格曲线：10 → 15 → 25 → 40 → 60（5 的倍数、增额递增）；逐店计数生效。
func _test_refresh_price_curve() -> void:
	_setup_two()
	GameState.phase = GameState.Phase.SHOP
	GameState.shop = {"seats": {}, "done": {}, "refresh_counts": {}, "card_refresh_counts": {}}
	_check("曲线 10/15/25/40/60", GameState._refresh_price_curve(0) == 10 \
		and GameState._refresh_price_curve(1) == 15 \
		and GameState._refresh_price_curve(2) == 25 \
		and GameState._refresh_price_curve(3) == 40 \
		and GameState._refresh_price_curve(4) == 60)
	GameState.shop["refresh_counts"][0] = 2
	_check("按玩家已刷次数计价", GameState._shop_refresh_cost(0) == 25)
	_check("他人计数独立", GameState._shop_refresh_cost(1) == 10)
	GameState.shop["card_refresh_counts"][1] = 4
	_check("卡牌计数独立", GameState._shop_card_refresh_cost(1) == 60)

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
