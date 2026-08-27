class_name PlayerArea
extends Control
## 玩家区域视图（Feature 16 / UI）
## 职责：定义该玩家区域的卡牌尺寸等可调试属性。
## 在 game_board.tscn 中每个玩家区域实例可独立调整；game_view 读取本属性渲染卡牌。

@export var card_size: Vector2 = Vector2(62, 90)
