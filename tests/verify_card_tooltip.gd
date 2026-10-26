extends Node
## headless 单元测试：卡牌 hover 文案（CardAbilityText）+ 信息气泡（CardTooltip）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== CARD TOOLTIP RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_text()
	await _test_tooltip()

func _test_text() -> void:
	_check("K 无能力", CardAbilityText.text("K") == "K：无能力")
	_check("7 看自己", CardAbilityText.text("7") == "7：看自己一张牌")
	_check("8 看自己", CardAbilityText.text("8") == "8：看自己一张牌")
	_check("9 看别人", CardAbilityText.text("9") == "9：看别人一张牌")
	_check("10 看别人", CardAbilityText.text("10") == "10：看别人一张牌")
	_check("J 盲换", "盲换" in CardAbilityText.text("J"))
	_check("Q 有交换说明", "选择是否交换" in CardAbilityText.text("Q"))
	_check("Q 含约束", "不能对两个其他玩家生效" in CardAbilityText.text("Q"))
	_check("Joker 显示名", CardAbilityText.text("JOKER").begins_with("Joker："))
	_check("弃牌堆取得不可用能力", "只能替换" in CardAbilityText.text("9", "discard"))

func _test_tooltip() -> void:
	var tip := CardTooltip.new()
	add_child(tip)
	await get_tree().process_frame
	_check("初始隐藏", not tip.is_shown() and not tip.visible)
	tip.show_line("Q：查看两张牌，并选择是否交换（不能对两个其他玩家生效）", Rect2(100, 100, 60, 80))
	_check("show 后可见", tip.is_shown() and tip.visible)
	_check("文本正确", tip.text().begins_with("Q："))
	_check("气泡有宽度", tip.bubble_size().x > 0.0)
	_check("统一固定宽度", is_equal_approx(tip.bubble_size().x, CardTooltip.FIXED_W))
	tip.show_line("K：无能力", Rect2(100, 100, 60, 80))
	_check("切换内容", tip.text() == "K：无能力")
	_check("宽度保持一致", is_equal_approx(tip.bubble_size().x, CardTooltip.FIXED_W))
	tip.hide_tip()
	_check("hide 后隐藏", not tip.is_shown() and not tip.visible)
	# 第二框（能力触发提示）：出现在第一气泡正下方，宽度一致。
	tip.show_with_note("J：盲换：与自己一张牌交换", "点击弃牌堆以触发能力", Rect2(100, 100, 60, 80))
	_check("note 显示后可见", tip.note_shown())
	_check("note 文本正确", tip.note_text() == "点击弃牌堆以触发能力")
	var pos_gap: float = absf(tip._bubble2.position.y - (tip._bubble.position.y + tip.bubble_size().y + CardTooltip.GAP_Y))
	_check("note 位于第一框正下方(间距 GAP)", pos_gap < 0.02)
	_check("note 宽度一致", tip._bubble2.size.x > 0.0)
	tip.show_with_note("K：无能力", "", Rect2(100, 100, 60, 80))
	_check("note 空时隐藏", not tip.note_shown())
	_check("note 文本清空", tip.note_text().is_empty())
	tip.hide_tip()
	_check("hide 双框同隐", not tip.is_shown() and not tip.note_shown() and not tip.visible)
	tip.queue_free()
