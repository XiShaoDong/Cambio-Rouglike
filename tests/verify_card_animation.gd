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

func _test_config() -> void:
	var c := CardAnimationConfig.new()
	_check("config 默认值合法", c.validate().is_empty())
	_check("config to_dict 键数", c.to_dict().size() == CardAnimationConfig.KEYS.size())
	_check("config 默认 hover_lift", is_equal_approx(c.hover_lift, 0.12))
	var bad := CardAnimationConfig.new()
	bad.hover_lift = -1.0
	_check("config 非法值被抓", bad.validate().has("hover_lift"))
