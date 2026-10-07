extends Node
## headless 单元测试：3D 桌面只读预览的纯布局数学。

var failures := 0
var checks := 0

func _ready() -> void:
	_run()
	print("=== TABLE3D LAYOUT RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _arr_eq(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not is_equal_approx(float(a[i]), float(b[i])):
			return false
	return true

func _run() -> void:
	_check("seat_angles(2)", _arr_eq(Table3dLayout.seat_angles(2), [0.0, 270.0]))
	_check("seat_angles(3)", _arr_eq(Table3dLayout.seat_angles(3), [0.0, 270.0, 90.0]))
	_check("seat_angles(4)", _arr_eq(Table3dLayout.seat_angles(4), [0.0, 270.0, 90.0, 180.0]))
	_check("seat_angles(0)", Table3dLayout.seat_angles(0).is_empty())
	_check("slot_grid_pos 0", Table3dLayout.slot_grid_pos(0) == Vector2(0, 0))
	_check("slot_grid_pos 1", Table3dLayout.slot_grid_pos(1) == Vector2(1, 0))
	_check("slot_grid_pos 2", Table3dLayout.slot_grid_pos(2) == Vector2(0, 1))
	_check("slot_grid_pos 3", Table3dLayout.slot_grid_pos(3) == Vector2(1, 1))
	_check("slot_grid_pos 4 第三列上", Table3dLayout.slot_grid_pos(4) == Vector2(2, 0))
	_check("slot_grid_pos 5 第三列下", Table3dLayout.slot_grid_pos(5) == Vector2(2, 1))
	_check("slot_grid_pos 6 第四列上", Table3dLayout.slot_grid_pos(6) == Vector2(3, 0))
	var joker := Table3dLayout.known_color_for_rank("JOKER")
	var ace := Table3dLayout.known_color_for_rank("A")
	var king := Table3dLayout.known_color_for_rank("K")
	var seven := Table3dLayout.known_color_for_rank("7")
	var two := Table3dLayout.known_color_for_rank("2")
	_check("分类色 JOKER 红", joker.r > joker.b and joker.r > joker.g)
	_check("分类色 A 金", ace.r > 0.8 and ace.g > 0.7 and ace.b < 0.5)
	_check("分类色两两不同", joker != ace and ace != king and king != seven and seven != two and joker != seven)
	_check("JOKER != A", joker != ace)
	_check("slot_color 已知 A", Table3dLayout.slot_color({"card": {"rank": "A"}}) == ace)
	_check("slot_color 未知空", Table3dLayout.slot_color({}) == Table3dLayout.UNKNOWN_COLOR)
	_check("slot_color 只有 card_id 视为未知", Table3dLayout.slot_color({"card_id": "x"}) == Table3dLayout.UNKNOWN_COLOR)
	_check("方块 5:7 比例", is_equal_approx(Table3dLayout.BLOCK_SIZE.x / Table3dLayout.BLOCK_SIZE.z, 0.7))
	# 看板深度锚点：本机座位(0,0,3) 前向 = 朝桌心
	var seat := Vector3(0.0, 0.0, 3.0)
	_check("board_depth_pos 0=近端桌边", Table3dLayout.board_depth_pos(seat, 0.0, 3.8).is_equal_approx(Vector3(0.0, 0.0, 3.8)))
	_check("board_depth_pos 0.5=桌心", Table3dLayout.board_depth_pos(seat, 0.5, 3.8).is_equal_approx(Vector3.ZERO))
	_check("board_depth_pos 1=对端桌边", Table3dLayout.board_depth_pos(seat, 1.0, 3.8).is_equal_approx(Vector3(0.0, 0.0, -3.8)))
	_check("board_depth_pos 0.4 在玩家侧", Table3dLayout.board_depth_pos(seat, 0.4, 3.8).is_equal_approx(Vector3(0.0, 0.0, 0.76)))
	_check("board_depth_pos 退化安全", Table3dLayout.board_depth_pos(Vector3.ZERO, 0.4, 3.8) == Vector3.ZERO)
