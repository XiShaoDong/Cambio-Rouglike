extends Node
## headless 单元测试：P3b/P3c 桩 —— SteamBridge 在无 GodotSteam 时全部走桩，不崩、不阻塞。

var failures := 0
var checks := 0

func _ready() -> void:
	await get_tree().process_frame
	_test_bridge_stub()
	_test_parse()
	print("=== STEAM STUB RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _test_bridge_stub() -> void:
	var b := SteamBridge.new()
	add_child(b)
	_check("无 GodotSteam → available()=false", not b.available())
	var ticket := {"v": "unset"}
	b.get_auth_ticket(func(t: String): ticket["v"] = t)
	_check("桩 get_auth_ticket → 空串", str(ticket["v"]) == "")
	var friends := {"n": -1}
	b.get_friends(func(f: Array): friends["n"] = f.size())
	_check("桩 get_friends → 空数组", int(friends["n"]) == 0)
	_check("桩 invite_friend → false", not b.invite_friend("765", "ABCDEF"))
	_check("桩 poll 不崩", true)
	b.poll()
	b.queue_free()

func _test_parse() -> void:
	_check("parse STEAM_AUTH_FAILED → 失败",
		not bool(AccountClient.parse_response(200, '{"error":"STEAM_AUTH_FAILED"}').get("ok", false)))
	var r := AccountClient.parse_response(200, '{"ok":true,"steam_id":"76561198000000000"}')
	_check("parse steam_auth 成功", bool(r.get("ok", false)) and str(r.get("data", {}).get("steam_id", "")) == "76561198000000000")
