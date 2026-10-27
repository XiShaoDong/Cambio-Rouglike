extends Node
## headless 单元测试：P2b —— DirectoryClient（响应解析 + 对本地 Python 目录服务的集成）。
## 注意：GDScript lambda 按值捕获，回调结果写进"容器字典的键"而非重新赋值外层变量。

var failures := 0
var checks := 0

func _ready() -> void:
	await get_tree().process_frame
	_test_parse()
	await _test_integration()
	print("=== DIRECTORY CLIENT RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _test_parse() -> void:
	var r := DirectoryClient.parse_response(200, '{"code":"ABC123","expires_in":1800}')
	_check("2xx 成功解析", bool(r.get("ok", false)) and str(r.get("data", {}).get("code", "")) == "ABC123")
	_check("HTTP 429 → 失败", not bool(DirectoryClient.parse_response(429, "{}").get("ok", false)))
	_check("业务 error → 失败", not bool(DirectoryClient.parse_response(200, '{"error":"ROOM_NOT_FOUND"}').get("ok", false)))
	_check("坏 JSON → 失败", not bool(DirectoryClient.parse_response(200, "not json").get("ok", false)))

func _wait_box(box: Dictionary) -> void:
	var n := 0
	while not bool(box.get("done", false)) and n < 60:
		await get_tree().create_timer(0.1).timeout
		n += 1

func _test_integration() -> void:
	var script_path := ProjectSettings.globalize_path("res://server/directory/directory.py")
	var pid := OS.create_process("python3", [script_path, "--port", "18091"])
	if pid <= 0:
		print("[SKIP] python3 不可用，跳过目录集成测试")
		return
	await get_tree().create_timer(1.2).timeout  # 等目录起来
	var dc := DirectoryClient.new()
	add_child(dc)
	dc.setup("http://127.0.0.1:18091")

	var c := {"done": false, "ok": false, "data": {}}
	dc.create_room(7007, "dedicated", 4, func(ok: bool, data: Dictionary):
		c["done"] = true; c["ok"] = ok; c["data"] = data)
	await _wait_box(c)
	_check("集成：create_room 成功", bool(c["ok"]) and (c["data"] as Dictionary).has("code"))
	var code := str((c["data"] as Dictionary).get("code", ""))

	var j := {"done": false, "ok": false, "data": {}}
	dc.join_room(code, func(ok: bool, data: Dictionary):
		j["done"] = true; j["ok"] = ok; j["data"] = data)
	await _wait_box(j)
	_check("集成：join_room 命中且 host=127.0.0.1", bool(j["ok"]) and str((j["data"] as Dictionary).get("host", "")) == "127.0.0.1")
	_check("集成：join 端口正确", int((j["data"] as Dictionary).get("port", 0)) == 7007)

	var h := {"done": false, "ok": false, "data": {}}
	dc.heartbeat(code, func(ok: bool, data: Dictionary):
		h["done"] = true; h["ok"] = ok; h["data"] = data)
	await _wait_box(h)
	_check("集成：heartbeat 成功", bool(h["ok"]))

	var cl := {"done": false, "ok": false, "data": {}}
	dc.close_room(code, func(ok: bool, data: Dictionary):
		cl["done"] = true; cl["ok"] = ok; cl["data"] = data)
	await _wait_box(cl)
	_check("集成：close_room 成功", bool(cl["ok"]))

	# 池模式：idle 登记 + allocate
	var p := {"done": false, "ok": false, "data": {}}
	var cb_pool := func(ok: bool, data: Dictionary):
		p["done"] = true; p["ok"] = ok; p["data"] = data
	dc.create_room(7011, "dedicated", 4, cb_pool, "", "", "idle")
	await _wait_box(p)
	_check("集成：create idle 成功", bool(p["ok"]))

	var idle_join := {"done": false, "ok": false, "data": {}}
	var cb_idle_join := func(ok: bool, data: Dictionary):
		idle_join["done"] = true; idle_join["ok"] = ok; idle_join["data"] = data
	dc.join_room(str((p["data"] as Dictionary).get("code", "")), cb_idle_join)
	await _wait_box(idle_join)
	_check("集成：idle 不可 join", not bool(idle_join["ok"]))

	var a := {"done": false, "ok": false, "data": {}}
	var cb_alloc := func(ok: bool, data: Dictionary):
		a["done"] = true; a["ok"] = ok; a["data"] = data
	dc.allocate_room(cb_alloc)
	await _wait_box(a)
	_check("集成：allocate_room 返回码与端口",
		bool(a["ok"]) and int((a["data"] as Dictionary).get("port", 0)) == 7011)

	var b := {"done": false, "ok": false, "data": {}}
	var cb_alloc2 := func(ok: bool, data: Dictionary):
		b["done"] = true; b["ok"] = ok; b["data"] = data
	dc.allocate_room(cb_alloc2)
	await _wait_box(b)
	_check("集成：无 idle → NO_ROOM",
		not bool(b["ok"]) and str((b["data"] as Dictionary).get("error", "")) == "NO_ROOM")

	OS.kill(pid)
