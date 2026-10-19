extends Node
## headless 单元测试：大牌能力文案（CardAbilityText）+ 聊天气泡（CardTooltip）。

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
	_test_ability_text()
	await _test_tooltip()

func _test_ability_text() -> void:
	_check("7 看自己", CardAbilityText.ability("7", "draw") == "看自己一张牌")
	_check("8 看自己", CardAbilityText.ability("8", "draw") == "看自己一张牌")
	_check("9 看别人", CardAbilityText.ability("9", "draw") == "看别人一张牌")
	_check("10 看别人", CardAbilityText.ability("10", "draw") == "看别人一张牌")
	_check("J 盲换", "盲换" in CardAbilityText.ability("J", "draw"))
	_check("Q 看后决定", "决定是否交换" in CardAbilityText.ability("Q", "draw"))
	_check("A 无解释", CardAbilityText.ability("A", "draw") == "")
	_check("弃牌堆取到不可用能力", CardAbilityText.ability("9", "discard") == "")
	_check("气泡前缀点数", CardAbilityText.bubble_text("9", "draw") == "9：看别人一张牌")
	_check("无解释时气泡为空", CardAbilityText.bubble_text("A", "draw") == "")

func _test_tooltip() -> void:
	var tip := CardTooltip.new()
	add_child(tip)
	await get_tree().process_frame
	_check("初始隐藏", not tip.is_shown() and not tip.visible)
	tip.show_text("9：看别人一张牌", Vector2(200, 200))
	_check("show 后可见", tip.is_shown() and tip.visible)
	_check("文本正确", tip.text() == "9：看别人一张牌")
	_check("气泡有宽度", tip.bubble_size().x > 0.0)
	tip.show_beside("Q：看别人一张牌，再看自己一张，决定是否交换", Rect2(100, 100, 60, 80))
	_check("show_beside 可见", tip.is_shown() and tip.visible)
	_check("长文本气泡有宽度", tip.bubble_size().x > 0.0)
	_check("有指向卡牌的三角形尖角", tip.tail_points().size() == 3)
	tip.hide_tip()
	_check("hide 后隐藏", not tip.is_shown() and not tip.visible)
	# 空文本不显示
	tip.show_text("", Vector2(10, 10))
	_check("空文本不弹", not tip.is_shown())
	tip.queue_free()
