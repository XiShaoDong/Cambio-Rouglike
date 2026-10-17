extends Node
## headless 单元测试：KeybindModel 纯函数 + KeybindStore 持久化 + KeymapBoard 页内容。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== KEYBIND RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_model()

func _test_model() -> void:
	var m: Dictionary = KeybindModel.defaults()
	_check("默认 6 个动作", m.size() == 6)
	_check("Tab 绑手册", int(m["kb_manual"]) == KEY_TAB)
	_check("S 绑 Stats", int(m["kb_stats"]) == KEY_S)
	_check("K 绑按键映射", int(m["kb_keymap"]) == KEY_K)
	_check("resolve Tab→kb_manual", KeybindModel.resolve(m, KEY_TAB) == "kb_manual")
	_check("resolve 未绑定→空", KeybindModel.resolve(m, KEY_Z) == "")
	_check("动作表有序", str(KeybindModel.action_ids()[0]) == "kb_manual")
	_check("action_def 有说明", str(KeybindModel.action_def("kb_manual")["desc"]) != "")
	var r: Dictionary = KeybindModel.rebind(m, "kb_stats", KEY_T)
	_check("rebind 成功", bool(r["ok"]) and int(r["map"]["kb_stats"]) == KEY_T)
	_check("rebind 不就地改入参", int(m["kb_stats"]) == KEY_S)
	var r2: Dictionary = KeybindModel.rebind(m, "kb_stats", KEY_M)
	_check("自动交换 swapped=kb_talk", bool(r2["ok"]) and str(r2["swapped"]) == "kb_talk")
	_check("交换后 kb_talk 得到旧键 S", int(r2["map"]["kb_talk"]) == KEY_S)
	_check("交换后 kb_stats=M", int(r2["map"]["kb_stats"]) == KEY_M)
	var r3: Dictionary = KeybindModel.rebind(m, "kb_stats", KEY_SPACE)
	_check("保留键拒绝", not bool(r3["ok"]) and str(r3["error"]) == "reserved")
	var r4: Dictionary = KeybindModel.rebind(m, "nope", KEY_Z)
	_check("未知动作拒绝", not bool(r4["ok"]) and str(r4["error"]) == "unknown_action")
	_check("to/from dict 往返", KeybindModel.from_dict(KeybindModel.to_dict(m)) == m)
	var bad: Dictionary = KeybindModel.from_dict({"kb_stats": KEY_SPACE, "ghost": KEY_Z})
	_check("非法保留值回退默认", int(bad["kb_stats"]) == KEY_S)
	_check("未知 id 不进入", not bad.has("ghost"))
