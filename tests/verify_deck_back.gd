extends Node
## headless 单元测试：抽牌堆模型卡背投影（配置 / 纯数学 / 着色器 / 沙盒）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== DECK BACK RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
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
	_test_layering()
	_test_projection()
	_test_shader()
	await _test_sandbox()

func _test_layering() -> void:
	var h1 := DeckBackMath.hash22(Vector2(3.0, 1.0))
	var h2 := DeckBackMath.hash22(Vector2(3.0, 1.0))
	_check("hash22 确定性", h1.is_equal_approx(h2))
	_check("hash22 范围 [0,1)", h1.x >= 0.0 and h1.x < 1.0 and h1.y >= 0.0 and h1.y < 1.0)
	_check("hash22 换种子变值", not DeckBackMath.hash22(Vector2(3.0, 2.0)).is_equal_approx(h1))
	_check("layer_index y=0", is_equal_approx(DeckBackMath.layer_index(0.0, 0.01), 0.0))
	_check("layer_index y=0.011", is_equal_approx(DeckBackMath.layer_index(0.011, 0.01), 1.0))
	_check("layer_index layer_height=0 兜底", is_equal_approx(DeckBackMath.layer_index(0.5, 0.0), 0.0))
	var o := Vector2(0.03, 0.02)
	var a := DeckBackMath.layer_offset(2.0, o, 1.0)
	var b := DeckBackMath.layer_offset(2.0, o, 1.0)
	_check("layer_offset 同层同值", a.is_equal_approx(b))
	_check("layer_offset 不同层不同值", not DeckBackMath.layer_offset(2.0, o, 1.0).is_equal_approx(DeckBackMath.layer_offset(5.0, o, 1.0)))
	_check("layer_offset 幅度受限", absf(a.x) <= o.x + 0.0001 and absf(a.y) <= o.y + 0.0001)
	_check("layer_offset 零幅度为零", DeckBackMath.layer_offset(4.0, Vector2.ZERO, 1.0).is_equal_approx(Vector2.ZERO))

func _test_projection() -> void:
	var size := Vector2(1.86, 1.90)
	var uv0 := DeckBackMath.project_uv(Vector3(0.0, 0.0, 0.0), size, 0.0)
	_check("project_uv 中心→0.5", uv0.is_equal_approx(Vector2(0.5, 0.5)))
	var uvx := DeckBackMath.project_uv(Vector3(size.x, 0.0, 0.0), size, 0.0)
	_check("project_uv x=size → u=1.5", is_equal_approx(uvx.x, 1.5))
	var uv90 := DeckBackMath.project_uv(Vector3(1.0, 0.0, 0.0), size, 90.0)
	_check("project_uv 90° 把 +X 转到 +Z", is_equal_approx(uv90.y, 0.5 + 1.0 / size.y) and absf(uv90.x - 0.5) < 0.0001)
	_check("side_blend 朝上=1", is_equal_approx(DeckBackMath.side_blend(1.0, 0.4), 1.0))
	_check("side_blend 竖直=0", is_equal_approx(DeckBackMath.side_blend(0.0, 0.4), 0.0))
	_check("side_blend 单调", DeckBackMath.side_blend(0.1, 0.4) < DeckBackMath.side_blend(0.3, 0.4))
	_check("ao 顶部=1", is_equal_approx(DeckBackMath.layer_ao_factor(0.25, 0.25, 0.25), 1.0))
	_check("ao 底部=1-ao", is_equal_approx(DeckBackMath.layer_ao_factor(0.0, 0.25, 0.25), 0.75))
	_check("ao 单调", DeckBackMath.layer_ao_factor(0.05, 0.25, 0.25) < DeckBackMath.layer_ao_factor(0.2, 0.25, 0.25))
	var cfg := DeckBackConfig.new().to_dict()
	var c := DeckBackMath.compose(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), cfg)
	_check("compose 顶部中心 uv≈0.5", absf((c["uv"] as Vector2).x - 0.5) < 0.2)
	_check("compose 朝上 side=1", is_equal_approx(c["side"] as float, 1.0))
	_check("compose 底部 ao=1-layer_ao", absf((c["ao"] as float) - 0.75) < 0.001)
	var off_cfg := DeckBackConfig.new().to_dict()
	off_cfg["tile"] = true
	var ct := DeckBackMath.compose(Vector3(1.5, 0.0, 0.0), Vector3(0.0, 1.0, 0.0), off_cfg)
	_check("compose tile 后 uv∈[0,1)", (ct["tile_uv"] as Vector2).x >= 0.0 and (ct["tile_uv"] as Vector2).x < 1.0)

func _test_sandbox() -> void:
	var sb = load("res://scenes/ui/deck_model_sandbox.tscn").instantiate()
	add_child(sb)
	await get_tree().process_frame
	_check("沙盒实例化", sb != null and sb.get_node_or_null("CameraRig") != null)
	_check("模型节点存在", sb.model_node() != null)
	_check("材质为 ShaderMaterial", sb.material() is ShaderMaterial)
	var cfg := DeckBackConfig.new()
	cfg.layer_ao = 0.5
	cfg.rotation_deg = 33.0
	sb.apply_config(cfg)
	_check("apply_config 写 layer_ao", is_equal_approx(float(sb.material().get_shader_parameter("layer_ao")), 0.5))
	_check("apply_config 写 rotation_deg", is_equal_approx(float(sb.material().get_shader_parameter("rotation_deg")), 33.0))
	sb.set_param("layer_offset", Vector2(0.1, 0.1))
	_check("set_param 写 layer_offset", (sb.material().get_shader_parameter("layer_offset") as Vector2).is_equal_approx(Vector2(0.1, 0.1)))
	sb.queue_free()

func _test_shader() -> void:
	var sh := load("res://assets/shaders/deck_back_projection.gdshader") as Shader
	_check("shader 可加载", sh != null)
	if sh == null:
		return
	var names := {}
	for u in sh.get_shader_uniform_list():
		names[u["name"]] = true
	for k in DeckBackConfig.KEYS:
		_check("shader uniform %s" % k, names.has(k))

func _test_config() -> void:
	var c := DeckBackConfig.new()
	_check("config 默认值合法", c.validate().is_empty())
	_check("config to_dict 键数", c.to_dict().size() == DeckBackConfig.KEYS.size())
	_check("config 默认 project_card_size", (c.project_card_size as Vector2).is_equal_approx(Vector2(1.86, 1.90)))
	_check("config 默认 layer_height", is_equal_approx(c.layer_height, 0.01))
	var bad := DeckBackConfig.new()
	bad.project_card_size = Vector2(-1.0, 1.0)
	_check("负尺寸被抓", bad.validate().has("project_card_size"))
	var bad2 := DeckBackConfig.new()
	bad2.layer_ao = 1.5
	_check("AO>1 被抓", bad2.validate().has("layer_ao"))
	var bad3 := DeckBackConfig.new()
	bad3.layer_height = 0.0
	_check("layer_height=0 被抓", bad3.validate().has("layer_height"))
