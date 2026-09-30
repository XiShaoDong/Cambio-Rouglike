class_name StatHud
extends Control
## 玩家区域右侧 HUD：上排 铜钱+货币数字，下排 生命心形×N。纯展示，读快照公开字段。

const COIN_SIZE := 22
const LIFE_SIZE := 16
const LIFE_GAP := 3
const ROW_GAP := 6

func setup(state: Dictionary, seat: int) -> void:
	for child in get_children():
		child.queue_free()
	var currency := 0
	var health := 0
	for p in state.get("players", []):
		if int(p.id) == seat:
			currency = int(p.get("currency", 0))
			health = maxi(0, int(p.get("health", 0)))
			break
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var coin := CoinIcon.new()
	coin.custom_minimum_size = Vector2(COIN_SIZE, COIN_SIZE)
	coin.size = coin.custom_minimum_size
	coin.setup(UITheme.color("accent"))
	row.add_child(coin)
	var num := Label.new()
	num.text = str(currency)
	num.add_theme_font_size_override("font_size", 14)
	num.add_theme_color_override("font_color", UITheme.color("accent"))
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(num)
	row.position = Vector2.ZERO
	add_child(row)
	var lives := HBoxContainer.new()
	lives.add_theme_constant_override("separation", LIFE_GAP)
	for _i in health:
		var h := LifeIcon.new()
		h.custom_minimum_size = Vector2(LIFE_SIZE, LIFE_SIZE)
		h.size = h.custom_minimum_size
		h.setup(UITheme.color("danger"))
		lives.add_child(h)
	lives.position = Vector2(0, COIN_SIZE + ROW_GAP)
	add_child(lives)
	custom_minimum_size = Vector2(COIN_SIZE + 36, COIN_SIZE + LIFE_SIZE + ROW_GAP)
	size = custom_minimum_size
