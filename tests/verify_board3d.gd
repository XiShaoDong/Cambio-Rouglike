extends Node
## headless 单元测试：3D 全息看板宿主（坐标换算 / 挂载 / 朝向 / 输入合成 / 等待提示 / main 路由）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== BOARD3D RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	await _test_board_input()

func _test_board_input() -> void:
	var size := Vector2(2.6, 1.8)
	_check("中心 → uv(0.5,0.5)", BoardInput.local_to_uv(Vector3.ZERO, size).is_equal_approx(Vector2(0.5, 0.5)))
	_check("左上角 → uv(0,0)", BoardInput.local_to_uv(Vector3(-1.3, 0.9, 0.0), size).is_equal_approx(Vector2(0.0, 0.0)))
	_check("右下角 → uv(1,1)", BoardInput.local_to_uv(Vector3(1.3, -0.9, 0.0), size).is_equal_approx(Vector2(1.0, 1.0)))
	_check("uv(0.5,0.5) → 视口中心", BoardInput.uv_to_viewport(Vector2(0.5, 0.5), Vector2i(1024, 708)) == Vector2i(512, 354))
	_check("uv(0,0) → (0,0)", BoardInput.uv_to_viewport(Vector2(0.0, 0.0), Vector2i(1024, 708)) == Vector2i(0, 0))
	_check("uv(1,1) → 右下角", BoardInput.uv_to_viewport(Vector2(1.0, 1.0), Vector2i(1024, 708)) == Vector2i(1024, 708))
	var xf := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.6, 0.0))
	_check("world_to_local 平移", BoardInput.world_to_local(xf, Vector3(0.0, 1.6, 0.0)).is_equal_approx(Vector3.ZERO))
