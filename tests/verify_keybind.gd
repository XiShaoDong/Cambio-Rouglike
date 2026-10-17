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
	_test_store()
	await _test_board()

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

func _test_store() -> void:
	var p := "user://test_keybinds.cfg"
	# 清理上一轮残留
	DirAccess.remove_absolute(p)
	var store := KeybindStore.new(p)
	store.load()
	_check("缺文件→默认", int(store.key_of("kb_manual")) == KEY_TAB)
	_check("action_for 默认", store.action_for(KEY_TAB) == "kb_manual")
	var r: Dictionary = KeybindModel.rebind(store.map, "kb_stats", KEY_T)
	store.apply(r["map"])
	store.save()
	var store2 := KeybindStore.new(p)
	store2.load()
	_check("save/load 持久化", int(store2.key_of("kb_stats")) == KEY_T)
	_check("load 后 action_for", store2.action_for(KEY_T) == "kb_stats")
	# apply 不落盘：改内存后未 save，重新 load 应读到旧值
	store2.apply(KeybindModel.defaults())
	var store3 := KeybindStore.new(p)
	store3.load()
	_check("apply 不落盘", int(store3.key_of("kb_stats")) == KEY_T)
	DirAccess.remove_absolute(p)

func _test_board() -> void:
	var board := KeymapBoard.new()
	add_child(board)
	await get_tree().process_frame
	board.setup(KeybindModel.defaults(), KeybindModel.RESERVED)
	await get_tree().process_frame
	_check("行数=动作数", board.row_count() == KeybindModel.action_ids().size())
	_check("chip 显示 Tab", board.chip_text("kb_manual") == OS.get_keycode_string(KEY_TAB))
	_check("初始无改动", not board.has_changes())
	# 捕获
	board.begin_capture("kb_stats")
	_check("进入捕获", board.capturing() == "kb_stats")
	_check("捕获态 chip 文案", board.chip_text("kb_stats") == KeymapBoard.CAPTURE_TEXT)
	board.capture_key(KEY_T)
	_check("捕获后 chip=T", board.chip_text("kb_stats") == OS.get_keycode_string(KEY_T))
	_check("结束捕获", board.capturing() == "")
	_check("有待保存改动", board.has_changes())
	# 保留键
	board.begin_capture("kb_talk")
	board.capture_key(KEY_SPACE)
	_check("保留键留在捕获态", board.capturing() == "kb_talk")
	_check("保留键提示", board.status_text("kb_talk") == KeymapBoard.RESERVED_TEXT)
	board.cancel_capture()
	_check("取消捕获", board.capturing() == "" and board.chip_text("kb_talk") == OS.get_keycode_string(KEY_M))
	# commit 后无改动
	board.commit()
	_check("commit 后无改动", not board.has_changes())
	board.queue_free()
