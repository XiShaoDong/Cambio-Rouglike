class_name TurnSystem
extends RefCounted
## 回合系统（Feature 05）
## 职责：决定"下一个行动者是谁、阶段如何推进"。
## 本类是纯决策器：不直接改状态，返回决策结果，由 GameState 执行副作用
## （广播、记日志、结算等），保持权威状态单一来源在 GameState。

## 决策结果：Dict
##   type: "next" | "final" | "finish"
##   next_player: 下一个行动者（type=finish 时为 0）
enum Decision { NEXT, FINAL, FINISH }

## 判断下一步。
## turn_order: 玩家顺序；current_player_id: 当前行动者；kong_caller: Kongbaya 喊出者（0=无）；
## final_queue: 最终轮剩余队列。返回决策。
static func decide(turn_order: Array, current_player_id: int, kong_caller: int, final_queue: Array) -> Dictionary:
	if kong_caller != 0:
		if final_queue.is_empty():
			return {"type": Decision.FINISH, "next_player": 0}
		return {"type": Decision.FINAL, "next_player": int(final_queue[0])}
	var current_index := turn_order.find(current_player_id)
	if current_index < 0:
		return {"type": Decision.FINISH, "next_player": 0}
	var next_index := (current_index + 1) % turn_order.size()
	return {"type": Decision.NEXT, "next_player": int(turn_order[next_index])}

## 生成 Kongbaya 的最终轮队列：从喊出者之后按顺序排列其他玩家。
static func build_final_queue(turn_order: Array, caller: int) -> Array[int]:
	var queue: Array[int] = []
	var start_index := turn_order.find(caller)
	if start_index < 0:
		return queue
	for offset in range(1, turn_order.size()):
		queue.append(int(turn_order[(start_index + offset) % turn_order.size()]))
	return queue