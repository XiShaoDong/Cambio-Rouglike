extends Node
## headless 测试：3D 每席 3 个饰品篮（位置 / 占位字符 / pick meta / hover 数据）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TABLE3D RELICS RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/ui/table3d.tscn")
	var view := scene.instantiate()
	add_child(view)
	await get_tree().process_frame
	var state := {
		"viewer_id": 0,
		"players": [
			{"id": 0, "name": "甲", "count": 4, "currency": 100, "health": 2, "eliminated": false,
			 "relics": ["relic_tax_hand", "relic_odd_hand", ""],
			 "slots": [{"card_id": "c1"}, {"card_id": "c2"}, {"card_id": "c3"}, {"card_id": "c4"}]},
			{"id": 1, "name": "乙", "count": 4, "currency": 80, "health": 2, "eliminated": false,
			 "relics": ["relic_joker_transform", "", ""],
			 "slots": [{"card_id": "c9"}, {"card_id": "c10"}, {"card_id": "c11"}, {"card_id": "c12"}]},
		],
		"draw_count": 30,
		"discard": {},
		"pending": {},
		"phase": 2,
	}
	view.render(state)
	await get_tree().process_frame
	var baskets: Array = view.relic_baskets(0)
	_check("每席 3 个饰品篮", baskets.size() == 3)
	_check("饰品篮在本地 +X（手牌左侧）", baskets.size() == 3 and is_equal_approx((baskets[0] as Node3D).position.x, Table3dView.RELIC_BASKET_X))
	_check("饰品篮整组上移（第一颗顶边与手牌顶边齐平）", baskets.size() == 3 and is_equal_approx((baskets[0] as Node3D).position.z, -0.12) \
		and is_equal_approx((baskets[1] as Node3D).position.z, 0.38) and is_equal_approx((baskets[2] as Node3D).position.z, 0.88))
	_check("非空篮显示占位字符", baskets.size() == 3 and (baskets[0] as RelicBasket).relic() == "relic_tax_hand" \
		and (baskets[0] as RelicBasket).get_node("Glyph").text == "-1")
	_check("空篮显示空样式", baskets.size() == 3 and (baskets[2] as RelicBasket).relic() == "" \
		and (baskets[2] as RelicBasket).get_node("Glyph").text == "·")
	var meta: Dictionary = (baskets[1] as RelicBasket).get_node("PickArea").get_meta("pick")
	_check("pick meta 含 seat/slot/kind", str(meta.get("kind", "")) == "relic" and int(meta.get("seat", -1)) == 0 and int(meta.get("slot", -1)) == 1)
	_check("他人饰品篮公开", (view.relic_baskets(1)[0] as RelicBasket).relic() == "relic_joker_transform")
	# 模拟 hover：直接指定 collider（真实射线交互由 verify_table3d_interaction 覆盖）
	view._hover_collider = baskets[1].get_node("PickArea")
	var hover: Dictionary = view.hovered_relic()
	_check("hovered_relic 返回 seat/slot/id", int(hover.get("seat", -1)) == 0 and int(hover.get("slot", -1)) == 1 \
		and str(hover.get("id", "")) == "relic_odd_hand")
	var def := Relics.def_by_id("relic_odd_hand")
	_check("tooltip 数据来自定义", str(def.get("name", "")) == "奇数惩罚" and str(def.get("desc", "")).contains("总分 -6"))
	(baskets[0] as RelicBasket).set_highlight(true)
	_check("hover 高亮环可见", (baskets[0] as RelicBasket).get_node("HighlightRing").visible)
	view.queue_free()
