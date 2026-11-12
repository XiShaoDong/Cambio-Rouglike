extends Node
## headless：HoverState 纯状态模型（贴牌/能力目标/抽牌堆/弃牌提醒）。

var failures := 0
var checks := 0

func _ready() -> void:
	_run()
	print("=== HOVER STATE RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _state() -> Dictionary:
	return {
		"phase": 3, "viewer_id": 0, "current_player": 0, "slap_open": false,
		"draw_count": 30, "discard": {"rank": "7", "suit": "♣"}, "discard_count": 1,
		"pending": {"rank": "9", "suit": "♥", "source": "draw"},
		"players": [
			{"id": 0, "slots": [{"protected": false}, {"protected": false}]},
			{"id": 1, "slots": [{"protected": false}, {"protected": true}]},
		],
	}

func _slot(seat: int, slot: int) -> Dictionary:
	return {"kind": "slot", "seat": seat, "slot": slot}

func _run() -> void:
	var s := _state()
	# 抽牌堆：仅当前玩家 TURN_DRAW
	s["phase"] = 2
	s["pending"] = {}
	var d := HoverState.resolve(s, "", {"kind": "deck"})
	_check("抽牌堆 ACTION", str(d.get("state")) == HoverState.ACTION and str(d.get("title")) == "抽取一张卡牌")
	var s_other := s.duplicate(true); s_other["viewer_id"] = 1
	_check("其他玩家抽牌堆无状态", HoverState.resolve(s_other, "", {"kind": "deck"}).is_empty())
	s["phase"] = 3
	_check("抽牌后抽牌堆无状态", HoverState.resolve(s, "", {"kind": "deck"}).is_empty())

	# 抽牌阶段弃牌提醒（黄）
	s = _state(); s["phase"] = 2; s["pending"] = {}
	var w := HoverState.resolve(s, "", {"kind": "discard"})
	_check("抽牌阶弃牌 WARNING", str(w.get("state")) == HoverState.WARNING and "无法使用其能力" in str(w.get("body")))
	var s_other2 := s.duplicate(true); s_other2["viewer_id"] = 1
	_check("其他玩家弃牌顶无 WARNING", HoverState.resolve(s_other2, "", {"kind": "discard"}).is_empty())

	# 当前玩家抽牌后：弃牌堆显示当前大牌能力（ACTION）
	s = _state()
	var a := HoverState.resolve(s, "", {"kind": "discard"})
	_check("抽牌后弃牌 ACTION", str(a.get("state")) == HoverState.ACTION and "9" in str(a.get("body")))
	_check("有能力时提示触发", "触发能力" in str(a.get("note")))
	s["pending"] = {"rank": "K", "suit": "♠", "source": "draw"}
	var a2 := HoverState.resolve(s, "", {"kind": "discard"})
	_check("无能力仍显示大牌", "K：无能力" in str(a2.get("body")) and "弃掉" in str(a2.get("note")))
	s["pending"] = {"rank": "9", "suit": "♥", "source": "discard"}
	var a3 := HoverState.resolve(s, "", {"kind": "discard"})
	_check("弃牌来源 WARNING", str(a3.get("state")) == HoverState.WARNING and "无法发动牌面能力" in str(a3.get("body")))
	_check("弃牌来源仍可弃掉", "仍可弃掉" in str(a3.get("note")))

	# 贴牌
	s = _state(); s["phase"] = 2; s["slap_open"] = true; s["pending"] = {}
	var sl := HoverState.resolve(s, "", _slot(1, 0))
	_check("贴牌 SLAP", str(sl.get("state")) == HoverState.SLAP and str(sl.get("title")) == "贴牌")
	var prot := HoverState.resolve(s, "", _slot(1, 1))
	_check("受保护 INVALID", str(prot.get("state")) == HoverState.INVALID)

	# 7/8
	s = _state(); s["slap_open"] = false
	var own_ok := HoverState.resolve(s, "peek_own", _slot(0, 0))
	var own_bad := HoverState.resolve(s, "peek_own", _slot(1, 0))
	_check("7/8 自己 VALID", str(own_ok.get("state")) == HoverState.VALID and "只能查看自己" in str(own_ok.get("body")))
	_check("7/8 敌方 INVALID", str(own_bad.get("state")) == HoverState.INVALID and "只能查看自己" in str(own_bad.get("body")))

	# 9/10
	var other_ok := HoverState.resolve(s, "peek_other", _slot(1, 0))
	var other_bad := HoverState.resolve(s, "peek_other", _slot(0, 0))
	_check("9/10 敌方 VALID", str(other_ok.get("state")) == HoverState.VALID)
	_check("9/10 自己 INVALID", str(other_bad.get("state")) == HoverState.INVALID)

	# Q 两阶段
	var q1_ok := HoverState.resolve(s, "queen_target", _slot(1, 0))
	var q1_bad := HoverState.resolve(s, "queen_target", _slot(0, 0))
	var q2_ok := HoverState.resolve(s, "q_view_own", _slot(0, 0))
	var q2_bad := HoverState.resolve(s, "q_view_own", _slot(1, 0))
	_check("Q 第一步敌方 VALID", str(q1_ok.get("state")) == HoverState.VALID and "先查看其他玩家" in str(q1_ok.get("body")))
	_check("Q 第一步自己 INVALID", str(q1_bad.get("state")) == HoverState.INVALID)
	_check("Q 第二步自己 VALID", str(q2_ok.get("state")) == HoverState.VALID and "再查看自己" in str(q2_ok.get("body")))
	_check("Q 第二步敌方 INVALID", str(q2_bad.get("state")) == HoverState.INVALID)

	# 饰品 peek_any
	_check("peek_any 双方都 VALID", str(HoverState.resolve(s, "peek_any", _slot(0, 0)).get("state")) == HoverState.VALID \
		and str(HoverState.resolve(s, "peek_any", _slot(1, 0)).get("state")) == HoverState.VALID)
	_check("J 不接管", HoverState.resolve(s, "jack_target", _slot(0, 0)).is_empty())
	var rep_ok := HoverState.resolve(s, "replace", _slot(0, 0))
	var rep_bad := HoverState.resolve(s, "replace", _slot(1, 0))
	_check("replace 自己 ACTION", str(rep_ok.get("state")) == HoverState.ACTION and str(rep_ok.get("title")) == "替换卡牌")
	_check("replace 敌方 INVALID", str(rep_bad.get("state")) == HoverState.INVALID and str(rep_bad.get("title")) == "无法替换")
