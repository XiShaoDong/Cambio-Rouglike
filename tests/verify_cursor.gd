extends Node

## 光标状态解析 headless 验证（纯静态函数，不依赖节点/viewport）：
##   resolve_card_state（卡牌语义）/ resolve_state（通用 hover 优先级）/ apply_hold（按住升级）。
## 方案 A 混合式修正版：无原生箭头，默认=pointer(open_hand)；贴牌 flip 覆盖任意卡牌（自己/他人）。

var failures := 0
var checks := 0
var CursorScript: GDScript

func _ready() -> void:
	CursorScript = load("res://scripts/ui/cursor.gd")
	_check("默认光标系统关闭", bool(Settings.get_setting("cursor", "enabled", false)) == false)
	_test_card_state()
	_test_generic_state()
	_test_hold()
	print("=== CURSOR RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _cs(state: Dictionary, action_mode: String, actionable: bool) -> String:
	return CursorScript.resolve_card_state(state, action_mode, actionable)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("[FAIL] " + name)
	else:
		print("[PASS] " + name)

func _test_card_state() -> void:
	var st := {"phase": 2, "slap_open": false}
	_check("可点牌→pointer(open_hand)", _cs(st, "", true) == "pointer")
	_check("不可点→pointer(默认,无原生箭头)", _cs(st, "", false) == "pointer")
	_check("slap_open悬停任意卡→flip", _cs({"phase": 2, "slap_open": true}, "", false) == "flip")
	_check("slap_open非TURN_DRAW不flip", _cs({"phase": 3, "slap_open": true}, "", false) == "pointer")
	_check("peek_own可点→peek", _cs(st, "peek_own", true) == "peek")
	_check("peek_other可点→peek", _cs(st, "peek_other", true) == "peek")
	_check("queen_target可点→peek", _cs(st, "queen_target", true) == "peek")
	_check("peek能力不可点→pointer", _cs(st, "peek_own", false) == "pointer")
	_check("replace可点→pointer", _cs(st, "replace", true) == "pointer")
	_check("slap_open时flip优先于peek", _cs({"phase": 2, "slap_open": true}, "peek_own", true) == "flip")

func _test_generic_state() -> void:
	_check("卡牌resolver返回peek→peek", CursorScript.resolve_state(true, "peek") == "peek")
	_check("卡牌resolver返回flip→flip", CursorScript.resolve_state(true, "flip") == "flip")
	_check("卡牌resolver返回pointer→pointer", CursorScript.resolve_state(true, "pointer") == "pointer")
	_check("非卡牌→pointer(open_hand)", CursorScript.resolve_state(false, "") == "pointer")

func _test_hold() -> void:
	_check("peek+按住→flip", CursorScript.apply_hold("peek", true) == "flip")
	_check("peek+松开→peek", CursorScript.apply_hold("peek", false) == "peek")
	_check("pointer+按住不升级", CursorScript.apply_hold("pointer", true) == "pointer")
	_check("flip+按住→flip", CursorScript.apply_hold("flip", true) == "flip")