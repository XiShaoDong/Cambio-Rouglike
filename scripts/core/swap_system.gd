class_name SwapSystem
extends RefCounted
## 交换系统（Feature 09）
## 职责：两名玩家之间的卡牌交换（J 盲换、Q 看后换）。纯动作，不做合法性校验。
## 持有 GameState 引用，操作其 players 状态并记录日志。

var game: Node

func _init(state: Node) -> void:
	game = state

## 交换玩家 a 的 a_slot 与玩家 b 的 b_slot 两张牌，并写入日志。
func swap(a: int, a_slot: int, b: int, b_slot: int, log_message: String) -> void:
	var mine: String = game.players[a].cards[a_slot]
	game.players[a].cards[a_slot] = game.players[b].cards[b_slot]
	game.players[b].cards[b_slot] = mine
	game._add_log(log_message)