extends Node
## headless 单元测试：3D 换牌飞牌（配置 / 纯数学 / 控制器 / 沙盒）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== CARD FLY RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
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
	var c := CardFlyConfig.new()
	_check("config 默认值合法", c.validate().is_empty())
	_check("config to_dict 键数", c.to_dict().size() == CardFlyConfig.KEYS.size())
	_check("config 默认 arc_height", is_equal_approx(c.arc_height, 0.35))
	var bad := CardFlyConfig.new()
	bad.arc_height = -1.0
	_check("config 非法值被抓", bad.validate().has("arc_height"))
	var swapped := CardFlyConfig.new()
	swapped.flip_start = 0.9
	swapped.flip_end = 0.2
	_check("flip_start > flip_end 被抓", swapped.validate().has("flip_start"))
