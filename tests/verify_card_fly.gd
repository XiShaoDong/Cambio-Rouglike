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
	_test_math()
	await _test_controller()

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

func _test_math() -> void:
	var cfg := CardFlyConfig.new().to_dict()
	_check("duration 短距取下限", is_equal_approx(CardFlyMath.duration_for(0.0, cfg), cfg["duration_min"]))
	_check("duration 长距取上限", is_equal_approx(CardFlyMath.duration_for(1000.0, cfg), cfg["duration_max"]))
	_check("duration 中距单调不减", CardFlyMath.duration_for(100.0, cfg) <= CardFlyMath.duration_for(300.0, cfg))
	_check("ease_in_out_cubic 端点", is_equal_approx(CardFlyMath.ease_in_out_cubic(0.0), 0.0) and is_equal_approx(CardFlyMath.ease_in_out_cubic(1.0), 1.0))
	_check("smoothstep 端点", is_equal_approx(CardFlyMath.smoothstep(0.0), 0.0) and is_equal_approx(CardFlyMath.smoothstep(1.0), 1.0))
	_check("arc p=0 ≈0", absf(CardFlyMath.arc_lift(0.0, cfg)) < 0.0001)
	_check("arc p=1 ≈0", absf(CardFlyMath.arc_lift(1.0, cfg)) < 0.0001)
	_check("arc p=0.5 峰值", is_equal_approx(CardFlyMath.arc_lift(0.5, cfg), cfg["arc_height"]))
	_check("flip_t 窗口前=0", is_equal_approx(CardFlyMath.flip_t(0.0, cfg), 0.0))
	_check("flip_t 窗口后=1", is_equal_approx(CardFlyMath.flip_t(1.0, cfg), 1.0))
	_check("flip_t 窗口内单调", CardFlyMath.flip_t(0.4, cfg) < CardFlyMath.flip_t(0.6, cfg))
	var s := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.03, 0.0))
	var e := Transform3D(Basis.from_euler(Vector3(0.0, PI, 0.0)), Vector3(2.0, 0.03, 1.0))
	var c0 := CardFlyMath.compose(s, e, 0.0, 0.0, 180.0, cfg)
	_check("compose p=0 起点", c0["origin"].distance_to(s.origin) < 0.0001)
	var c1 := CardFlyMath.compose(s, e, 1.0, 0.0, 180.0, cfg)
	_check("compose p=1 终点", c1["origin"].distance_to(e.origin) < 0.0001)
	var cm := CardFlyMath.compose(s, e, 0.5, 0.0, 180.0, cfg)
	_check("compose p=0.5 抬升", cm["origin"].y > s.origin.y + 0.1)
	# 无额外滚转时：p=1 的 basis 与 end 一致
	var n0 := CardFlyMath.compose(s, e, 1.0, 0.0, 0.0, cfg)
	_check("roll_delta=0 终点 basis=end", n0["basis"].is_equal_approx(e.basis))
	# roll_start=180 把正面法线翻到朝下
	var r0 := CardFlyMath.compose(s, e, 0.0, 0.0, 0.0, cfg)
	var r180 := CardFlyMath.compose(s, e, 0.0, 180.0, 0.0, cfg)
	_check("roll_start=180 法线反向", (r0["basis"] * Vector3(0.0, 1.0, 0.0)).dot(r180["basis"] * Vector3(0.0, 1.0, 0.0)) < 0.0)

func _test_controller() -> void:
	var fly := CardFly.new()
	add_child(fly)
	var s := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.03, 0.0))
	var e := Transform3D(Basis.IDENTITY, Vector3(2.0, 0.03, 1.0))
	var done := {"v": false}
	fly.finished.connect(func(): done["v"] = true)
	fly.play(s, e, {"rank": "A", "suit": "♥"}, true, true)
	_check("play 后在飞", fly.is_flying() and fly.progress() == 0.0)
	await get_tree().create_timer(1.2).timeout
	_check("飞完 finished 触发", done["v"])
	_check("飞完节点已释放", not is_instance_valid(fly))
	# 空 data 显示卡背（标签为空）
	var back := CardFly.new()
	add_child(back)
	back.play(s, e, {}, false, false)
	_check("空 data 背面无标签", back.card_block() != null and back.card_block().label_text() == "")
	back.queue_free()
	# 背面起飞：初始已滚转 180°（正面法线朝下）
	var flip := CardFly.new()
	add_child(flip)
	flip.play(s, e, {"rank": "Q", "suit": "♦"}, false, true)
	_check("背面起飞法线朝下", (flip.global_transform.basis * Vector3(0.0, 1.0, 0.0)).y < 0.0)
	flip.queue_free()
