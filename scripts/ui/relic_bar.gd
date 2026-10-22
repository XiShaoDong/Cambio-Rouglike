class_name RelicBar
extends Control
## 遗物物品栏：固定 3 槽 + n/3 计数，占位字符图标，Hover Tooltip（名称+描述+状态）。
## 纯展示：数据来自快照公开字段 players[].relics / players[].protected_slot。

const SLOT_COUNT := 3
const SLOT_SIZE := 32
const SLOT_GAP := 4
const COUNT_H := 16

## 填充本玩家（seat）的遗物栏。
func setup(state: Dictionary, seat: int) -> void:
	for child in get_children():
		child.queue_free()
	var items: Array = _collect_items(state, seat)
	var y := 0.0
	for i in SLOT_COUNT:
		var icon := RelicIcon.new()
		icon.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		icon.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		icon.position = Vector2(0, y)
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		if i < items.size():
			var it: Dictionary = items[i]
			var relic_id := str(it.get("id", ""))
			var color: Color = UITheme.color(str(it.get("color_key", "accent")))
			if relic_id == Relics.GUARD_SHIELD_ID:
				icon.setup(RelicIcon.Kind.SHIELD, color)
			elif relic_id == Relics.JOKER_TRANSFORM_ID:
				icon.setup(RelicIcon.Kind.JOKER, color)
			else:
				icon.setup_glyph(str(it.get("glyph", "?")), color)
			icon.tooltip_text = "%s\n%s\n%s" % [it.get("name", ""), it.get("desc", ""), it.get("status", "")]
		else:
			icon.setup(RelicIcon.Kind.EMPTY, UITheme.color("border_strong"))
			icon.tooltip_text = "空遗物栏位"
		add_child(icon)
		y += SLOT_SIZE + SLOT_GAP
	var count := Label.new()
	count.text = "%d/%d" % [items.size(), SLOT_COUNT]
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.position = Vector2(0, y)
	count.custom_minimum_size = Vector2(SLOT_SIZE, COUNT_H)
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	add_child(count)
	custom_minimum_size = Vector2(SLOT_SIZE, y + COUNT_H)
	size = custom_minimum_size

## 收集该玩家当前应显示的遗物：快照 players[].relics 的 3 格，外加生效中的护盾状态。
func _collect_items(state: Dictionary, seat: int) -> Array:
	var ids: Array = []
	var protected_slot := -1
	for p in state.get("players", []):
		if int(p.get("id", -1)) == seat:
			ids = (p.get("relics", []) as Array).duplicate()
			protected_slot = int(p.get("protected_slot", -1))
			break
	var items: Array = []
	for id in ids:
		var relic_id := str(id)
		if relic_id.is_empty():
			continue
		var def := Relics.def_by_id(relic_id)
		if def.is_empty():
			continue
		var status := "状态：已持有"
		if relic_id == Relics.JOKER_TRANSFORM_ID:
			status = "状态：本局可用"
		items.append({"id": relic_id, "name": str(def.get("name", "")), "desc": str(def.get("desc", "")),
			"glyph": str(def.get("glyph", "?")), "color_key": str(def.get("color", "accent")), "status": status})
	if protected_slot >= 0 and items.size() < SLOT_COUNT:
		var has_shield := false
		for it in items:
			if str(it.get("id", "")) == Relics.GUARD_SHIELD_ID:
				has_shield = true
				break
		if not has_shield:
			var def := Relics.def_by_id(Relics.GUARD_SHIELD_ID)
			items.append({"id": Relics.GUARD_SHIELD_ID, "name": str(def.get("name", "防守护盾")),
				"desc": str(def.get("desc", "")), "glyph": str(def.get("glyph", "◇")),
				"color_key": "relic_shield", "status": "状态：本局保护第 %d 格" % protected_slot})
	return items
