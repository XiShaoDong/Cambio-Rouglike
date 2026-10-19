extends Node
## headless 单元测试：卡牌信息内容（CardAbilityText.info）+ 信息气泡（CardTooltip）。

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
	_test_info()
	await _test_tooltip()

func _test_info() -> void:
	var k := CardAbilityText.info("K")
	_check("K 牌名", str(k["rank"]) == "K")
	_check("K 分数 -1", int(k["value"]) == -1)
	_check("K 无能力", k["lines"] == ["无能力"])
	var q := CardAbilityText.info("Q")
	_check("Q 分数 10", int(q["value"]) == 10)
	_check("Q 能力首行", str(q["lines"][0]) == "查看两张牌，并选择是否交换")
	_check("Q 约束行", str(q["lines"][1]) == "不能对两个其他玩家生效")
	_check("7 看自己", CardAbilityText.info("7")["lines"] == ["看自己一张牌"])
	_check("8 看自己", CardAbilityText.info("8")["lines"] == ["看自己一张牌"])
	_check("9 看别人", CardAbilityText.info("9")["lines"] == ["看别人一张牌"])
	_check("10 看别人", CardAbilityText.info("10")["lines"] == ["看别人一张牌"])
	_check("J 盲换", "盲换" in str(CardAbilityText.info("J")["lines"][0]))
	var joker := CardAbilityText.info("JOKER")
	_check("Joker 显示名", str(joker["rank"]) == "Joker")
	_check("Joker 分数 0", int(joker["value"]) == 0)
	_check("弃牌堆取得不可用能力", "只能替换" in str(CardAbilityText.info("9", "discard")["lines"][0]))

func _test_tooltip() -> void:
	var tip := CardTooltip.new()
	add_child(tip)
	await get_tree().process_frame
	_check("初始隐藏", not tip.is_shown() and not tip.visible)
	tip.show_card(CardAbilityText.info("Q"), Rect2(100, 100, 60, 80))
	_check("show 后可见", tip.is_shown() and tip.visible)
	_check("第一行左=牌名", tip.rank_text() == "Q")
	_check("第一行右=分数", tip.score_text() == "10")
	_check("能力行数 2", tip.line_texts().size() == 2)
	_check("气泡有宽度", tip.bubble_size().x > 0.0)
	tip.show_card(CardAbilityText.info("K"), Rect2(100, 100, 60, 80))
	_check("切换内容 K", tip.rank_text() == "K" and tip.score_text() == "-1")
	_check("K 显示无能力", tip.line_texts() == ["无能力"])
	tip.hide_tip()
	_check("hide 后隐藏", not tip.is_shown() and not tip.visible)
	tip.queue_free()
