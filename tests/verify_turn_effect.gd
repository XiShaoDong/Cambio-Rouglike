extends Node
## headless 单元测试：每回合随机增强数据（TurnEffect）+ 展示面板（TurnEffectPanel）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TURN EFFECT RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_data()
	await _test_panel()

func _test_data() -> void:
	_check("5 种效果", TurnEffect.all().size() == 5)
	_check("无效果 id", str(TurnEffect.by_id("none")["id"]) == "none")
	_check("红 Joker", str(TurnEffect.by_id("joker_red")["name"]).contains("红"))
	_check("黑 Joker", str(TurnEffect.by_id("joker_black")["name"]).contains("黑"))
	_check("炸弹标记", bool(TurnEffect.by_id("bomb")["bomb"]))
	var ids := {}
	for e in TurnEffect.all():
		ids[str(e["id"])] = true
	_check("随机结果合法", ids.has(str(TurnEffect.random()["id"])))

func _test_panel() -> void:
	var p := TurnEffectPanel.new()
	add_child(p)
	await get_tree().process_frame
	_check("初始隐藏", not p.visible)
	p.set_effect(TurnEffect.by_id("bomb"))
	_check("内容 id=bomb", p.effect_id() == "bomb")
	_check("说明非空", not p.description_text().is_empty())
	p.reveal(TurnEffect.by_id("joker_red"), Vector2(400, 300), Vector2(1100, 75))
	_check("reveal 可见", p.visible)
	_check("reveal 播放中", p.is_revealing())
	_check("中央放大", p.scale.x > 1.0)
	p.dock_at(Vector2(1100, 75))
	_check("dock 后不再播放", not p.is_revealing() and p.visible)
	_check("dock 缩放 1", is_equal_approx(p.scale.x, 1.0))
	_check("dock 右上角贴住 dock 点（不跑出屏幕）", is_equal_approx(p.position.x + p.size.x, 1100.0) and is_equal_approx(p.position.y, 75.0))
	p.hide_panel()
	_check("hide 后不可见", not p.visible)
	p.queue_free()
