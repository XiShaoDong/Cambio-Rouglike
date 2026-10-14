extends Node
## headless 单元测试：P3a —— AccountClient（响应解析 + 对本地 Python 账号服务的集成）。

var failures := 0
var checks := 0

func _ready() -> void:
	await get_tree().process_frame
	_test_parse()
	await _test_integration()
	print("=== ACCOUNT CLIENT RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _test_parse() -> void:
	var r := AccountClient.parse_response(200, '{"account_id":"acc_x","name":"A"}')
	_check("2xx 成功解析", bool(r.get("ok", false)) and str(r.get("data", {}).get("account_id", "")) == "acc_x")
	_check("业务 error → 失败", not bool(AccountClient.parse_response(200, '{"error":"AUTH_FAILED"}').get("ok", false)))
	_check("坏 JSON → 失败", not bool(AccountClient.parse_response(200, "nope").get("ok", false)))

func _wait_box(box: Dictionary) -> void:
	var n := 0
	while not bool(box.get("done", false)) and n < 60:
		await get_tree().create_timer(0.1).timeout
		n += 1

func _test_integration() -> void:
	var script_path := ProjectSettings.globalize_path("res://server/account/account.py")
	var data_path := "/tmp/kong_acc_verify.json"
	DirAccess.remove_absolute(data_path)
	var pid := OS.create_process("python3", [script_path, "--port", "18094", "--data", data_path])
	if pid <= 0:
		print("[SKIP] python3 不可用，跳过账号集成测试")
		return
	await get_tree().create_timer(1.2).timeout
	var ac := AccountClient.new()
	add_child(ac)
	ac.setup("http://127.0.0.1:18094")

	var reg := {"done": false, "ok": false, "data": {}}
	ac.register("测试玩家", func(ok: bool, data: Dictionary):
		reg["done"] = true; reg["ok"] = ok; reg["data"] = data)
	await _wait_box(reg)
	_check("集成：register 成功", bool(reg["ok"]) and (reg["data"] as Dictionary).has("account_id") and (reg["data"] as Dictionary).has("secret"))
	var aid := str((reg["data"] as Dictionary).get("account_id", ""))
	var sec := str((reg["data"] as Dictionary).get("secret", ""))

	var log := {"done": false, "ok": false, "data": {}}
	ac.login(aid, sec, func(ok: bool, data: Dictionary):
		log["done"] = true; log["ok"] = ok; log["data"] = data)
	await _wait_box(log)
	_check("集成：login 命中且名=测试玩家", bool(log["ok"]) and str((log["data"] as Dictionary).get("name", "")) == "测试玩家")

	var bad := {"done": false, "ok": false, "data": {}}
	ac.login(aid, "wrong", func(ok: bool, data: Dictionary):
		bad["done"] = true; bad["ok"] = ok; bad["data"] = data)
	await _wait_box(bad)
	_check("集成：login 错误 secret → 失败", not bool(bad["ok"]))

	# P3b：客户端↔服务端 steam_auth（服务端 MockVerifier，无 Steam 资源）
	var sa := {"done": false, "ok": false, "data": {}}
	ac.steam_auth(aid, sec, "mock:76561198000000000", func(ok: bool, data: Dictionary):
		sa["done"] = true; sa["ok"] = ok; sa["data"] = data)
	await _wait_box(sa)
	_check("集成：steam_auth(mock) 绑定成功", bool(sa["ok"]) and str((sa["data"] as Dictionary).get("steam_id", "")) == "76561198000000000")

	var sb := {"done": false, "ok": false, "data": {}}
	ac.steam_auth(aid, sec, "garbage", func(ok: bool, data: Dictionary):
		sb["done"] = true; sb["ok"] = ok; sb["data"] = data)
	await _wait_box(sb)
	_check("集成：坏票据 → STEAM_AUTH_FAILED", not bool(sb["ok"]) and str((sb["data"] as Dictionary).get("error", "")) == "STEAM_AUTH_FAILED")

	var pf := {"done": false, "ok": false, "data": {}}
	ac.get_profile(aid, func(ok: bool, data: Dictionary):
		pf["done"] = true; pf["ok"] = ok; pf["data"] = data)
	await _wait_box(pf)
	_check("集成：profile 反映 steam_id", str((pf["data"] as Dictionary).get("steam_id", "")) == "76561198000000000")

	OS.kill(pid)
	DirAccess.remove_absolute(data_path)
