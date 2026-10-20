extends Node
const Mark3dMathScript := preload("res://scripts/ui/mark3d_math.gd")
var failures := 0
var checks := 0
func _ready() -> void:
	await _run()
	print("=== EMOTE RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)
func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok: print("[PASS] " + name)
	else: failures += 1; printerr("[FAIL] " + name)
func _run() -> void:
	_test_math()
	await _test_wheel()
	await _test_display()
	await _test_view()
	_test_sync()

func _test_sync() -> void:
	var got: Array = []
	var cb := func(seat, index): got.append([seat, index])
	GameState.emote_played.connect(cb)
	GameState._apply_emote(2, 3)
	_check("_apply_emote 发信号", got.size() == 1 and int(got[0][0]) == 2 and int(got[0][1]) == 3)
	GameState.receive_emote(4, 5)
	_check("receive_emote 发信号", got.size() == 2 and int(got[1][1]) == 5)
	GameState.emote_played.disconnect(cb)

func _test_math() -> void:
	_check("idx 上=0", Mark3dMathScript.sector_index_for(Vector2(0, -1), 0.1, 1.0, 6) == 0)
	_check("idx 顺时针(右偏上)=1", Mark3dMathScript.sector_index_for(Vector2(0.5, -0.866), 0.1, 1.0, 6) == 1)
	_check("idx 下=3", Mark3dMathScript.sector_index_for(Vector2(0, 1), 0.1, 1.0, 6) == 3)
	_check("idx 中空=-1", Mark3dMathScript.sector_index_for(Vector2(0.02, 0), 0.1, 1.0, 6) == -1)
	_check("idx 超范围=-1", Mark3dMathScript.sector_index_for(Vector2(2, 0), 0.1, 1.0, 6) == -1)

func _test_wheel() -> void:
	var w = load("res://scripts/ui/emote_wheel.gd").new()
	add_child(w)
	await get_tree().process_frame
	w.size = Vector2(1280, 760)
	w.open(Vector2(400, 300))
	var ro = w._outer_px()
	w.update_cursor(Vector2(400, 300 - ro * 0.7))
	_check("轮盘 上=0", w.selected() == 0)
	w.update_cursor(Vector2(400, 300 + ro * 0.7))
	_check("轮盘 下=3", w.selected() == 3)
	w.update_cursor(Vector2(400, 300))
	_check("轮盘 中空=-1", w.selected() == -1)
	w.close()
	_check("轮盘 close 隐藏", not w.visible)
	w.queue_free()
	await get_tree().process_frame

func _test_display() -> void:
	var d = load("res://scripts/ui/emote_display.gd").new()
	add_child(d)
	await get_tree().process_frame
	d.set_process(false)
	d.play(2)
	_check("生成数字标签", d._label != null and d._label.text == "3")
	_check("billboard", d._label.billboard == BaseMaterial3D.BILLBOARD_ENABLED)
	var done := [false]
	d.finished.connect(func(): done[0] = true)
	var t := 0.0
	while t < d.DURATION + d.FADE_OUT + 0.2:
		d._process(0.1)
		t += 0.1
	_check("到时 finished", done[0])
	await get_tree().process_frame
	_check("释放", not is_instance_valid(d))

func _test_view() -> void:
	var view = load("res://scenes/ui/table3d.tscn").instantiate()
	add_child(view)
	await get_tree().process_frame
	view.render({
		"viewer_id": 0, "current_player": 1,
		"players": [
			{"id": 0, "name": "甲", "count": 2, "currency": 0, "health": 2, "slots": [{"card_id": "c1"}]},
			{"id": 1, "name": "乙", "count": 2, "currency": 0, "health": 2, "slots": [{"card_id": "c2"}]},
		],
		"draw_count": 30, "discard": {}, "pending": {}, "phase": 2,
	})
	await get_tree().process_frame
	view.show_emote(1, 4)
	await get_tree().process_frame
	_check("remote 生成表情", view._emotes.has(1) and is_instance_valid(view._emotes[1]))
	var first = view._emotes[1]
	view.show_emote(1, 2)
	await get_tree().process_frame
	_check("同席替换表情", view._emotes[1] != first and not is_instance_valid(first))
	view.show_emote(0, 1)
	_check("viewer 席忽略", not view._emotes.has(0))
	view.clear_emotes()
	_check("clear_emotes 清空", view._emotes.is_empty())
	view.queue_free()
	await get_tree().process_frame
