class_name CardFactory
extends RefCounted
## 卡牌视图工厂（Feature 16 / UI）
## 职责：构建 CardView 实例、设置高亮。纯展示层，不含规则判断。

var _scene_cache: PackedScene = null

func scene() -> PackedScene:
	if _scene_cache == null:
		_scene_cache = load("res://scenes/ui/card.tscn")
	return _scene_cache

## 创建一张卡牌视图；card 为空则显示背面。
func make_card(card: Dictionary, card_size: Vector2) -> Button:
	var btn: Button = scene().instantiate()
	btn.custom_minimum_size = card_size
	btn.size = card_size
	if btn is CardView:
		(btn as CardView).setup(card)
	return btn

## 高亮（金色光晕）；关闭时恢复基础样式。
func highlight(button: Button, on: bool) -> void:
	if button is CardView:
		button.set_highlight(on)
		return
	var base: StyleBoxFlat = button.get_meta("base_style", null) as StyleBoxFlat
	if on:
		var style := (base.duplicate() if base else StyleBoxFlat.new()) as StyleBoxFlat
		style.shadow_color = UITheme.color("highlight_glow")
		style.shadow_size = 10
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_stylebox_override("pressed", style)
	else:
		button.add_theme_stylebox_override("normal", base)
		button.add_theme_stylebox_override("hover", base)
		button.add_theme_stylebox_override("pressed", base)
