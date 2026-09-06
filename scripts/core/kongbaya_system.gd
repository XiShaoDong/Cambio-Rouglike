class_name KongbayaSystem
extends RefCounted
## Kongbaya 系统（Feature 11）
## 职责：处理喊出 Kongbaya（铃铛），进入最终轮。
## 校验 + 设置状态 + 推进回合。与 TurnSystem 协作构建最终轮队列。
## 持有 GameState 引用。

var game: Node

func _init(state: Node) -> void:
	game = state

## 喊出 Kongbaya。sender 为行动者。
## 一场对局只允许一次：已有人喊过（kong_caller != -1）即拒绝，最终轮玩家不可再喊。
func declare(sender: int, action_id := "") -> void:
	if game.kong_caller != -1:
		game._reject(sender, game.RejectCode.INVALID_PHASE, action_id)
		return
	if game.phase != game.Phase.TURN_DRAW:
		game._reject(sender, game.RejectCode.INVALID_PHASE, action_id)
		return
	if sender != game.current_player_id:
		game._reject(sender, game.RejectCode.NOT_CURRENT_PLAYER, action_id)
		return
	if not game._check_action_id(sender, action_id):
		game._reject(sender, game.RejectCode.DUPLICATE_OR_EXPIRED_ACTION, action_id)
		return
	game.kong_caller = sender
	game.kong_called_first_turn = not bool(game.players[sender].has_acted)
	game.final_queue = TurnSystem.build_final_queue(game.turn_order, sender)
	game.slap_open = false
	game._add_log("%s 喊出了 Kongbaya！其他玩家各有最后一次行动。" % game.players[sender].name)
	game._broadcast_sfx("bell")
	game._advance_turn(true)
