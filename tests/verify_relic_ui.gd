extends Node
## headless UI 测试：14 件饰品定义 / 2D 遗物栏 3 格 / 商店 2 格 + 刷新 + 锁定。

var failures := 0
var checks := 0

func _ready() -> void:
	GameState.turn_effect_rules_enabled = false
	_test_defs()
	_test_relic_bar()
	await _test_shop_panel()
	var status: String = " (FAILURES!)" if failures > 0 else ""
	print("=== RELIC UI RESULT: %d/%d passed%s ===" % [checks - failures, checks, status])
	get_tree().quit(1 if failures > 0 else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _test_defs() -> void:
	var pool: Array = Relics.pool()
	var ids := {}
	var fields_ok := true
	for relic in pool:
		var id := str(relic.get("id", ""))
		if id.is_empty() or ids.has(id):
			fields_ok = false
		ids[id] = true
		if str(relic.get("glyph", "")).is_empty() or str(relic.get("desc", "")).is_empty():
			fields_ok = false
	_check("14 件饰品定义", pool.size() == 14)
	_check("id 唯一 + glyph/desc 齐全", fields_ok)
	_check("刷新价格 10", Relics.SHOP_REFRESH_COST == 10)
	_check("glyph_for 返回占位字符", Relics.glyph_for("relic_tax_hand") == "-1")

func _test_relic_bar() -> void:
	var bar = load("res://scenes/ui/relic_bar.tscn").instantiate()
	add_child(bar)
	var state := {
		"players": [{"id": 0, "relics": ["relic_tax_hand", "", ""], "protected_slot": -1}],
	}
	bar.setup(state, 0)
	_check("遗物栏固定 3 格 + 计数", bar.get_child_count() == 4)
	var icon = bar.get_child(0)
	_check("遗物栏使用占位字符", icon.get("kind") == RelicIcon.Kind.GLYPH and str(icon.get("glyph")) == "-1")
	_check("遗物栏 tooltip 含名称/说明", str(icon.tooltip_text).contains("手牌税") and str(icon.tooltip_text).contains("手牌大于"))
	_check("遗物栏计数 1/3", str(bar.get_child(3).text) == "1/3")
	bar.queue_free()

func _test_shop_panel() -> void:
	var panel = load("res://scenes/ui/shop_panel.tscn").instantiate()
	add_child(panel)
	var state := {
		"viewer_id": 0,
		"players": [{"id": 0, "currency": 80, "relics": ["", "", ""]}],
		"item_cards": [],
		"shop": {
			"offers": [
				{"index": 0, "id": "relic_odd_hand", "name": "奇数惩罚", "price": 50, "locked": true},
				{"index": 1, "id": "relic_joker_transform", "name": "Joker 变换", "price": 50, "locked": false},
			],
			"card_offers": [
				{"index": 0, "id": ItemCards.FATE_PLUS2_ID, "name": "命运·加二", "desc": "下一位玩家抽到的手牌点数 +2", "price": 50, "locked": true},
				{"index": 1, "id": ItemCards.INTERFERE_ID, "name": "干扰", "desc": "选择一名对手", "price": 50, "locked": false},
				{"index": 2, "id": ItemCards.CHARM_ID, "name": "护符", "desc": "对自己使用", "price": 50, "locked": false},
			],
			"done": [],
			"refresh_cost": 10,
			"card_refresh_cost": 10,
			"can_refresh": true,
			"card_can_refresh": true,
			"relic_bought": false,
			"card_bought": false,
		},
	}
	panel.setup(state, Callable(), Callable(), Callable(), Callable(), Callable(), Callable(), Callable(), true)
	var row: Node = panel.get_node("Center/Panel/VBox/RelicsRow")
	_check("商店 2 个饰品位（+ 行尾刷新）", row.get_child_count() == 3 \
		and row.get_node_or_null("RelicSlot0") != null and row.get_node_or_null("RelicSlot1") != null)
	var slot0: Node = row.get_child(0)
	var slot1: Node = row.get_child(1)
	_check("锁定货位显示解锁按钮", str(slot0.get_node("Lock").text) == "解锁")
	_check("未锁货位显示锁定按钮", str(slot1.get_node("Lock").text) == "锁定")
	_check("slot tooltip 含饰品说明", str(slot0.tooltip_text).contains("奇数惩罚") and str(slot0.tooltip_text).contains("总分 -6"))
	var cards_row: Node = panel.get_node("Center/Panel/VBox/CardsRow")
	_check("商店 3 张真实道具卡（+ 行尾刷新）", cards_row.get_child_count() == 4 \
		and cards_row.get_child(3).name == "CardRefresh")
	_check("道具卡卡面存在", cards_row.get_child(0).get_node_or_null("Card") is ItemCardView)
	_check("道具卡锁按钮", str(cards_row.get_child(0).get_node("Lock").text) == "解锁")
	var refresh: Button = row.get_node("Refresh")
	_check("遗物刷新按钮文本", str(refresh.text).contains("刷新遗物") and not refresh.disabled)
	var card_refresh: Button = cards_row.get_node("CardRefresh")
	_check("卡牌刷新按钮文本", str(card_refresh.text).contains("刷新卡牌") and not card_refresh.disabled)
	_check("底部结束商店", str(panel.get_node("Center/Panel/VBox/Bottom/Leave").text).contains("结束商店"))
	panel.queue_free()
