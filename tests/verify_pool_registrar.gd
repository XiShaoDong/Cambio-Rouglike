extends Node
## 池登记器纯逻辑测试（无网络，注入假回调）。

var failures := 0
var checks := 0
var created := []
var closed := []
var next_code := "AAA111"

func _ready() -> void:
	await get_tree().process_frame
	var r := PoolRegistrar.new()
	r.setup(
		func(port: int, _mode: String, _max: int, state: String, cb: Callable):
			created.append({"port": port, "state": state})
			cb.call(true, {"code": next_code}),
		func(code: String, cb: Callable):
			closed.append(code)
			if cb.is_valid():
				cb.call(true, {}))

	r.register_idle(7007, "dedicated", 4, Callable())
	_check("register_idle 存码", r.code == "AAA111")
	_check("register_idle 状态 idle", r.state == "idle")
	_check("register_idle 传 state=idle", created.size() == 1 and created[0]["state"] == "idle")

	next_code = "BBB222"
	var box := {"done": false}
	r.rotate_after_room(7007, "dedicated", 4, func(_ok: bool, _d: Dictionary): box["done"] = true)
	_check("轮换关闭旧码", closed == ["AAA111"])
	_check("轮换后新码", r.code == "BBB222")
	_check("轮换后仍 idle", r.state == "idle")
	_check("轮换回调触发", bool(box["done"]))

	closed.clear()
	r.code = ""
	next_code = "CCC333"
	r.rotate_after_room(7007, "dedicated", 4, Callable())
	_check("无码时不发 close", closed.is_empty() and r.code == "CCC333")

	r.re_register(7007, "dedicated", 4, true, Callable())
	_check("re_register in_use 状态", r.state == "in_use" and created[-1]["state"] == "in_use")

	print("=== POOL REGISTRAR RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)
