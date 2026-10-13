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

## 大厅 UI 两态 + 槽位 + 按钮可见性（headless 实例化 main 场景驱动）。
func _test_lobby_ui() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	var snap_guest := {
		"players": [{"id": 0, "name": "Host", "ready": false}, {"id": 1, "name": "Me", "ready": true}],
		"host_id": 0, "room_host": 0, "your_id": 1,
		"min_players": 2, "max_players": 4, "match_limit": 5,
	}
	scene.lobby.update_lobby(snap_guest)
	_check("客人：显示房间态", scene.lobby._room_box.visible and not scene.lobby._menu_box.visible)
	_check("槽位数量 = max_players", scene.lobby._slots_box.get_child_count() == 4)
	_check("客人：见准备按钮、无开始", scene.lobby._ready_button.visible and not scene.lobby._start_button.visible)
	_check("客人：准备按钮文案=取消准备", scene.lobby._ready_button.text == "取消准备")

	var snap_host_ready := snap_guest.duplicate(true)
	snap_host_ready["your_id"] = 0
	scene.lobby.update_lobby(snap_host_ready)
	_check("房主：见开始/解散", scene.lobby._start_button.visible and scene.lobby._disband_button.visible)
	_check("房主：全员 ready → 开始可用", not scene.lobby._start_button.disabled)

	var snap_host_wait := snap_host_ready.duplicate(true)
	snap_host_wait["players"] = [{"id": 0, "name": "Host", "ready": false}, {"id": 1, "name": "Me", "ready": false}]
	scene.lobby.update_lobby(snap_host_wait)
	_check("房主：有人未 ready → 开始禁用", scene.lobby._start_button.disabled)

	scene.lobby.reset_lobby()
	_check("reset_lobby 回主菜单态", scene.lobby._menu_box.visible and not scene.lobby._room_box.visible)
	scene.queue_free()
	await get_tree().process_frame
