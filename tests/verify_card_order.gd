extends Node
## headless 单元测试：右下角「牌序」面板（CardOrderPanel）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== CARD ORDER RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	var p := CardOrderPanel.new()
	add_child(p)
	await get_tree().process_frame
	_check("14 张卡", p.card_count() == 14)
	_check("牌序卡片宽=26", is_equal_approx(CardOrderPanel.CARD_W, 26.0))
	_check("牌序卡片高=34", is_equal_approx(CardOrderPanel.CARD_H, 34.0))
	_check("默认展开", p.is_expanded())
	_check("首张 Q", p.rank_at(0) == "Q")
	_check("第三张 10", p.rank_at(2) == "10")
	_check("Joker 显示 JK", p.rank_at(12) == "JK")
	_check("末张 K", p.rank_at(13) == "K")
	_check("SHIFT 按钮存在", p.shift_button() != null)
	p.toggle()
	_check("点 SHIFT 收起", not p.is_expanded())
	p.toggle()
	_check("再点展开", p.is_expanded())
	p.queue_free()
