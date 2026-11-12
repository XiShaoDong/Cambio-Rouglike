class_name TutorialController
extends RefCounted
## 教学步骤机：回放段 advance()，真操作段 pick()/action() 校验；含跳过/重来。

const STEPS := [
	{"id": "intro", "mode": "replay", "state": "initial"},
	{"id": "memorize", "mode": "replay", "state": "memorized"},
	{"id": "draw", "mode": "interact", "state": "ready_draw"},
	{"id": "replace", "mode": "interact", "state": "drawn"},
	{"id": "opponent", "mode": "replay", "state": "replaced"},
	{"id": "slap", "mode": "interact", "state": "opponent_discard"},
	{"id": "abilities", "mode": "replay", "state": "after_slap"},
	{"id": "kongbaya", "mode": "interact", "state": "after_slap"},
	{"id": "final", "mode": "replay", "state": "kongbaya"},
	{"id": "settle", "mode": "replay", "state": "game_over"},
	{"id": "summary", "mode": "replay", "state": "game_over"},
]

var step_index := 0
var _replace_armed := false

func step() -> Dictionary:
	if step_index >= STEPS.size():
		return STEPS[STEPS.size() - 1]
	return STEPS[step_index]

func step_id() -> String:
	return str(step().get("id", ""))

func mode() -> String:
	return str(step().get("mode", "replay"))

func is_interact() -> bool:
	return mode() == "interact"

func is_done() -> bool:
	return step_index >= STEPS.size()

func state() -> Dictionary:
	if is_done():
		return TutorialSteps.state_game_over()
	return TutorialSteps.state_by_id(str(step().get("state", "initial")))

func advance() -> bool:
	if is_done():
		return false
	if is_interact():
		return false
	step_index += 1
	_replace_armed = false
	return true

func skip_step() -> void:
	if is_done():
		return
	step_index += 1
	_replace_armed = false

func restart() -> void:
	step_index = 0
	_replace_armed = false

func action(id: String) -> Dictionary:
	if step_id() == "replace":
		if id == "replace":
			_replace_armed = true
			return {"ok": true, "message": ""}
		return {"ok": false, "message": TutorialText.toast("replace_wrong_action")}
	return {"ok": false, "message": ""}

func pick(meta: Dictionary) -> Dictionary:
	var kind := str(meta.get("kind", ""))
	match step_id():
		"draw":
			if kind == "deck":
				step_index += 1
				return {"ok": true, "message": ""}
			if kind == "discard":
				return {"ok": false, "message": TutorialText.toast("draw_need_deck")}
		"replace":
			if kind == "slot":
				if not _replace_armed:
					return {"ok": false, "message": TutorialText.toast("replace_need_arm")}
				if int(meta.get("seat", -1)) == TutorialSteps.PLAYER and int(meta.get("slot", -1)) == 1:
					step_index += 1
					_replace_armed = false
					return {"ok": true, "message": ""}
				return {"ok": false, "message": TutorialText.toast("replace_need_target")}
			if kind == "deck" or kind == "discard":
				return {"ok": false, "message": TutorialText.toast("replace_wrong_action")}
		"slap":
			if kind == "slot":
				if int(meta.get("seat", -1)) == TutorialSteps.PLAYER and int(meta.get("slot", -1)) == 2:
					step_index += 1
					return {"ok": true, "message": ""}
				return {"ok": false, "message": TutorialText.toast("slap_wrong")}
			return {"ok": false, "message": TutorialText.toast("slap_wrong_target")}
		"kongbaya":
			if kind == "hud" and str(meta.get("action", "")) == "kongbaya":
				step_index += 1
				return {"ok": true, "message": ""}
			if kind == "deck":
				return {"ok": false, "message": TutorialText.toast("kong_need_bell")}
	return {"ok": false, "message": ""}
