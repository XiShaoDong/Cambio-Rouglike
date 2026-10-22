class_name ItemHandArt
extends Control
## 可替换手部美术接口：未来 2D 美术或 3D 手（渲染到 SubViewport 后作为 Control）都实现本接口。
## ItemHandOverlay 只通过这些方法驱动手部，不把手部形状/动画写进手牌逻辑。

func setup(_hand_rect: Rect2) -> void:
	pass

func play_open() -> void:
	pass

func play_close(_immediate: bool) -> void:
	pass

func set_selected_hint(_index: int, _count: int) -> void:
	pass
