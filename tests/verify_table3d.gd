extends Node
## headless 单元测试：3D 预览的节点层（CardBlock / 相机 / 快照渲染）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TABLE3D RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_card_block()
	_test_camera()

func _test_card_block() -> void:
	var known := CardBlock.new()
	add_child(known)
	known.setup({"card": {"rank": "A", "suit": "♥"}})
	_check("CardBlock 已知牌文本 A♥", known.label_text() == "A♥")
	_check("CardBlock 已知牌颜色", known.block_color() == Table3dLayout.known_color_for_rank("A"))
	_check("CardBlock 非保护不自发光", not known.is_emissive())
	var unknown := CardBlock.new()
	add_child(unknown)
	unknown.setup({})
	_check("CardBlock 未知牌无文本", unknown.label_text() == "")
	_check("CardBlock 未知牌颜色", unknown.block_color() == Table3dLayout.UNKNOWN_COLOR)
	var prot := CardBlock.new()
	add_child(prot)
	prot.setup({"protected": true, "card": {"rank": "K", "suit": "♠"}})
	_check("CardBlock 护盾自发光", prot.is_emissive())
	_check("CardBlock 护盾紫色", prot.block_color() == CardBlock.PROTECTED_COLOR)
	_check("CardBlock 护盾仍显示点数", prot.label_text() == "K♠")
	_check("CardBlock Joker 文本", CardBlock.card_text({"rank": "JOKER", "suit": "red"}) == "JOKER")
	_check("CardBlock 空卡文本", CardBlock.card_text({}) == "")

func _test_camera() -> void:
	var rig := Table3dCamera.new()
	add_child(rig)
	rig.frame_for_seat(0.0)
	_check("相机基准朝向 0°", is_equal_approx(rig.base_yaw, 0.0))
	_check("相机默认俯角", is_equal_approx(rig.pitch, Table3dCamera.DEFAULT_PITCH))
	_check("相机座位位置", rig.position.is_equal_approx(Vector3(0.0, 1.6, Table3dLayout.SEAT_RADIUS)))
	rig.look(Vector2(1000.0, 1000.0))
	_check("yaw 上夹 90", is_equal_approx(rig.yaw, Table3dCamera.YAW_LIMIT))
	_check("pitch 上夹 60", is_equal_approx(rig.pitch, Table3dCamera.PITCH_LIMIT))
	rig.look(Vector2(-5000.0, -5000.0))
	_check("yaw 下夹 -90", is_equal_approx(rig.yaw, -Table3dCamera.YAW_LIMIT))
	_check("pitch 下夹 -60", is_equal_approx(rig.pitch, -Table3dCamera.PITCH_LIMIT))
	rig.frame_for_seat(180.0)
	_check("对面基准朝向 180°", is_equal_approx(rig.base_yaw, 180.0))
	_check("对面座位位置", rig.position.is_equal_approx(Vector3(0.0, 1.6, -Table3dLayout.SEAT_RADIUS)))
