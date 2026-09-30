class_name RelicBar
extends Control
## 遗物物品栏：3 槽 + n/3 计数，程序化图标，Hover Tooltip（名称+描述+状态）。
## 纯展示：数据全部来自快照公开字段（run.relics / run.relic_owners / players[].protected_slot）。

const SLOT_COUNT := 3
const SLOT_SIZE := 32
const SLOT_GAP := 4
const COUNT_H := 16

## 填充本玩家（seat）的遗物栏。护盾按生效中（protected_slot>=0）显示，Joker 按持有显示。
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
			icon.setup(int(it.kind), it.color)
			icon.tooltip_text = "%s\n%s\n%s" % [it.name, it.desc, it.status]
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

## 收集该玩家当前应显示的遗物（Joker 持有一件；护盾生效一件；未来遗物依序追加）。
func _collect_items(state: Dictionary, seat: int) -> Array:
	var run: Dictionary = state.get("run", {})
	var relics: Dictionary = run.get("relics", {})
	var owners: Dictionary = run.get("relic_owners", {})
	var items: Array = []
	if str(owners.get(Relics.JOKER_TRANSFORM_ID, -1)) == str(seat) and relics.has(Relics.JOKER_TRANSFORM_ID):
		var def: Dictionary = relics[Relics.JOKER_TRANSFORM_ID]
		items.append({"kind": RelicIcon.Kind.JOKER, "color": UITheme.color("accent"),
			"name": str(def.get("name", "Joker 变换")), "desc": str(def.get("desc", "")),
			"status": "状态：本局可用"})
	var shield_slot := -1
	for p in state.get("players", []):
		if int(p.id) == seat:
			shield_slot = int(p.get("protected_slot", -1))
			break
	if shield_slot >= 0:
		var def: Dictionary = Relics.def_by_id(Relics.GUARD_SHIELD_ID)
		items.append({"kind": RelicIcon.Kind.SHIELD, "color": UITheme.color("relic_shield"),
			"name": str(def.get("name", "防守护盾")), "desc": str(def.get("desc", "")),
			"status": "状态：本局保护第 %d 格" % shield_slot})
	return items
