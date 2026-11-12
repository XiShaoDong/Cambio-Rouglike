class_name TutorialController
extends RefCounted
## 教学步骤机：talk 逐句推进，interact 真操作校验，auto 由视图播完动画后推进，summary 收尾。

const STEPS := [
	{"id": "intro_1", "mode": "talk", "state": "dealt", "focus": ""},
	{"id": "intro_2", "mode": "talk", "state": "initial", "focus": ""},
	{"id": "intro_3", "mode": "talk", "state": "memorized", "focus": ""},
	{"id": "draw", "mode": "interact", "state": "ready_draw", "focus": "deck"},
	{"id": "replace", "mode": "interact", "state": "drawn_7", "focus": "own_hand"},
	{"id": "opponent_replace", "mode": "auto", "state": "player_replaced",
		"end_state": "opponent_replaced", "focus": "opponent_hand"},
	{"id": "opponent_replace_explain", "mode": "talk", "state": "opponent_replaced",
		"focus": "discard"},
	{"id": "draw2", "mode": "interact", "state": "opponent_replaced", "focus": "deck"},
	{"id": "discard", "mode": "interact", "state": "drawn_9", "focus": "discard"},
	{"id": "opponent_discard", "mode": "auto", "state": "player_discarded_9",
		"end_state": "opponent_discarded_2", "focus": "opponent_hand"},
	{"id": "slap_explain", "mode": "talk", "state": "opponent_discarded_2",
		"focus": "discard", "slap": "explain"},
	{"id": "slap_race_intro", "mode": "talk", "state": "opponent_discarded_2",
		"focus": "own_hand"},
	{"id": "slap_prompt", "mode": "interact", "state": "opponent_discarded_2",
		"focus": "own_hand", "slap": "race"},
	{"id": "risk", "mode": "talk", "state": "slap_success", "focus": "opponent"},
	{"id": "wrong_slap_demo", "mode": "auto", "state": "slap_success",
		"end_state": "opponent_penalty_1", "focus": "opponent_two"},
	{"id": "slap_other_setup", "mode": "auto", "state": "opponent_penalty_1",
		"end_state": "slap_other_window", "focus": "opponent_hand"},
	{"id": "slap_other_tell", "mode": "talk", "state": "slap_other_window",
		"focus": "opponent_hand"},
	{"id": "slap_other_click", "mode": "interact", "state": "slap_other_window",
		"focus": "opponent_hand", "slap": "explain"},
	{"id": "slap_other_exchange", "mode": "interact", "state": "slap_other_exchange",
		"focus": "own_hand"},
	{"id": "slap_other_done", "mode": "talk", "state": "after_gift", "focus": "opponent"},
	{"id": "overflow", "mode": "talk", "state": "after_gift", "focus": "opponent_two"},
	{"id": "overflow_demo", "mode": "auto", "state": "after_gift",
		"end_state": "game_over_gift", "focus": "opponent_two"},
	{"id": "settle", "mode": "talk", "state": "game_over_gift", "focus": ""},
	{"id": "summary", "mode": "summary", "state": "game_over_gift", "focus": ""},
]

var step_index := 0
## 贴别人牌后交给对手的槽位（0/1/3）。
var gift_slot := 0

func step() -> Dictionary:
	if step_index >= STEPS.size():
		return STEPS[STEPS.size() - 1]
	return STEPS[step_index]


func step_id() -> String:
	return str(step().get("id", ""))


func mode() -> String:
	return str(step().get("mode", "talk"))


func is_interact() -> bool:
	return mode() == "interact"


func is_talk() -> bool:
	return mode() == "talk"


func is_auto() -> bool:
	return mode() == "auto"


func is_summary() -> bool:
	return mode() == "summary"


func is_done() -> bool:
	return step_index >= STEPS.size()


func focus() -> String:
	return str(step().get("focus", ""))


func slap_mode() -> String:
	return str(step().get("slap", "off"))


func start_state_id() -> String:
	return str(step().get("state", "initial"))


func end_state_id() -> String:
	return str(step().get("end_state", start_state_id()))


func state() -> Dictionary:
	if is_done():
		return TutorialSteps.state_game_over(gift_slot)
	return _state_by_id(start_state_id())


func end_state() -> Dictionary:
	return _state_by_id(end_state_id())


func _state_by_id(id: String) -> Dictionary:
	if id == "after_gift":
		return TutorialSteps.state_after_gift(gift_slot)
	if id == "game_over_gift":
		return TutorialSteps.state_game_over(gift_slot)
	return TutorialSteps.state_by_id(id)


func advance() -> bool:
	if is_done():
		return false
	if is_interact() or is_summary():
		return false
	step_index += 1
	return true


func skip_step() -> void:
	if is_done():
		return
	step_index += 1


func restart() -> void:
	step_index = 0
	gift_slot = 0


## interact 步骤的真操作校验。成功时返回 effect 供视图播放动画。
func pick(meta: Dictionary) -> Dictionary:
	var kind := str(meta.get("kind", ""))
	match step_id():
		"draw", "draw2":
			if kind == "deck":
				_advance_forced()
				return {"ok": true, "message": "", "effect": "draw"}
			return {"ok": false, "message": TutorialText.toast("draw_wrong")}
		"replace":
			if kind == "slot":
				if int(meta.get("seat", -1)) == TutorialSteps.PLAYER \
						and int(meta.get("slot", -1)) == 3:
					_advance_forced()
					return {"ok": true, "message": "", "effect": "replace"}
			return {"ok": false, "message": TutorialText.toast("replace_wrong")}
		"discard":
			if kind == "discard":
				_advance_forced()
				return {"ok": true, "message": "", "effect": "discard"}
			return {"ok": false, "message": TutorialText.toast("discard_wrong")}
		"slap_prompt":
			if kind == "slot" and int(meta.get("seat", -1)) == TutorialSteps.PLAYER \
					and int(meta.get("slot", -1)) == 2:
				_advance_forced()
				return {"ok": true, "message": "", "effect": "slap"}
			return {"ok": false, "message": TutorialText.toast("slap_wrong")}
		"slap_other_click":
			if kind == "slot" and int(meta.get("seat", -1)) == TutorialSteps.OPPONENT \
					and int(meta.get("slot", -1)) == 3:
				_advance_forced()
				return {"ok": true, "message": "", "effect": "slap_other", "slot": 3}
			return {"ok": false, "message": TutorialText.toast("slap_other_hint")}
		"slap_other_exchange":
			if kind == "slot" and int(meta.get("seat", -1)) == TutorialSteps.PLAYER:
				var own := int(meta.get("slot", -1))
				if own == 0 or own == 1 or own == 3:
					gift_slot = own
					_advance_forced()
					return {"ok": true, "message": "", "effect": "slap_gift", "slot": own}
			return {"ok": false, "message": TutorialText.toast("slap_gift_hint")}
	return {"ok": false, "message": ""}


func _advance_forced() -> void:
	if step_index < STEPS.size() - 1:
		step_index += 1
