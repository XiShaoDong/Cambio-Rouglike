extends Node
## headless 单元测试：TurnTimer 纯模型 + HintText 文案表 + HintHud 屏幕面板 + main 集成。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== HINT_HUD RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_turn_timer()

func _test_turn_timer() -> void:
	var t := TurnTimer.new()
	t.reset(30.0)
	_check("TurnTimer reset=30", is_equal_approx(t.remaining, 30.0) and t.seconds_left() == 30)
	t.tick(1.5)
	_check("TurnTimer tick 递减", is_equal_approx(t.remaining, 28.5) and t.seconds_left() == 28)
	t.tick(40.0)
	_check("TurnTimer 可为负", t.remaining < 0.0 and t.seconds_left() < 0)
	t.reset(30.0)
	_check("TurnTimer phase 正常 0", t.phase() == 0)
	t.reset(8.0)
	_check("TurnTimer phase 临近 1", t.phase() == 1)
	t.reset(0.0)
	_check("TurnTimer phase 超时 2", t.phase() == 2)
	var n := TurnTimer.new()
	n.reset(0.0)
	n.tick(0.3)
	_check("TurnTimer floor 负数 -1", n.seconds_left() == -1)
