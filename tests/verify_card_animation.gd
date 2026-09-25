extends Node
## headless 单元测试：卡牌交互动效（配置 / 纯数学 / 控制器 / 沙盒）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== CARD ANIMATION RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_config()
	_test_state_machine()
	_test_easing()

func _test_config() -> void:
	var c := CardAnimationConfig.new()
	_check("config 默认值合法", c.validate().is_empty())
	_check("config to_dict 键数", c.to_dict().size() == CardAnimationConfig.KEYS.size())
	_check("config 默认 hover_lift", is_equal_approx(c.hover_lift, 0.12))
	var bad := CardAnimationConfig.new()
	bad.hover_lift = -1.0
	_check("config 非法值被抓", bad.validate().has("hover_lift"))

func _test_state_machine() -> void:
	var M := CardAnimationMath
	_check("IDLE + enter → HOVER", M.next_state(M.IDLE, M.EV_ENTER, true, false, false) == M.HOVER)
	_check("IDLE + click 无效", M.next_state(M.IDLE, M.EV_CLICK, false, false, false) == M.IDLE)
	_check("HOVER + exit → IDLE", M.next_state(M.HOVER, M.EV_EXIT, false, false, false) == M.IDLE)
	_check("HOVER + click → PRESS", M.next_state(M.HOVER, M.EV_CLICK, true, false, false) == M.PRESS)
	_check("PRESS + exit 不中断", M.next_state(M.PRESS, M.EV_EXIT, false, false, false) == M.PRESS)
	_check("PRESS + timer → FLIP", M.next_state(M.PRESS, M.EV_TIMER, true, false, false) == M.FLIP)
	_check("FLIP + click 无效", M.next_state(M.FLIP, M.EV_CLICK, true, false, false) == M.FLIP)
	_check("FLIP + timer 未完成仍 FLIP", M.next_state(M.FLIP, M.EV_TIMER, true, false, false) == M.FLIP)
	_check("FLIP + timer 完成 → LAND", M.next_state(M.FLIP, M.EV_TIMER, true, true, false) == M.LAND)
	_check("LAND + timer 完成且悬停 → HOVER", M.next_state(M.LAND, M.EV_TIMER, true, true, true) == M.HOVER)
	_check("LAND + timer 完成且未悬停 → IDLE", M.next_state(M.LAND, M.EV_TIMER, false, true, true) == M.IDLE)

func _test_easing() -> void:
	var M := CardAnimationMath
	_check("ease_out_cubic 端点", is_equal_approx(M.ease_out_cubic(0.0), 0.0) and is_equal_approx(M.ease_out_cubic(1.0), 1.0))
	_check("ease_out_cubic 单调", M.ease_out_cubic(0.3) < M.ease_out_cubic(0.6))
	_check("ease_in_out_cubic 端点", is_equal_approx(M.ease_in_out_cubic(0.0), 0.0) and is_equal_approx(M.ease_in_out_cubic(1.0), 1.0))
	_check("ease_out_back 端点", is_equal_approx(M.ease_out_back(0.0), 0.0) and is_equal_approx(M.ease_out_back(1.0), 1.0))
	_check("ease_out_back 过冲", M.ease_out_back(0.7) > 1.0)
	_check("lerp_f 中点", is_equal_approx(M.lerp_f(0.0, 10.0, 0.5), 5.0))
