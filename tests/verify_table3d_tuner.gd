extends Node
## headless 单元测试：Table3D 调参工具（纯函数 + 写回引擎 + 场景应用）。

var failures := 0
var checks := 0

func _ready() -> void:
	await _run()
	print("=== TABLE3D TUNER RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	_test_params()
	_test_parse()
	_test_apply()
	_test_apply_scene_mesh()
	_test_writer()
	await _test_scene_apply()
	await _test_ui()
	await get_tree().process_frame

func _test_params() -> void:
	var p := Table3dTunerModel.params()
	_check("参数表含相机眼高", p.has("camera_eye_height"))
	_check("参数表含座位半径", p.has("seat_radius"))
	_check("参数表含 pending_y", p.has("pending_y"))
	_check("每个参数有 default", _all_have(p, "default"))
	var d := Table3dTunerModel.defaults()
	_check("defaults 键数一致", d.size() == p.size())
	_check("默认眼高 3.5", is_equal_approx(float(d["camera_eye_height"]), 3.5))
	_check("默认座位半径 2.4", is_equal_approx(float(d["seat_radius"]), 2.4))
	_check("分组非空", Table3dTunerModel.groups().size() >= 4)

func _test_parse() -> void:
	var layout := """
const BLOCK_SIZE := Vector3(0.70, 0.04, 1.00)   # 平铺桌面
const BLOCK_GAP := Vector3(0.06, 0.0, 0.06)
const TABLE_RADIUS := 3.5  # 半边长
const SEAT_RADIUS := 2.4
const ANGLE_ORDER := [0.0, 270.0, 90.0, 180.0]
"""
	var pl := Table3dTunerModel.parse_layout(layout)
	_check("解析 SEAT_RADIUS", is_equal_approx(float(pl["seat_radius"]), 2.4))
	_check("解析 TABLE_RADIUS", is_equal_approx(float(pl["table_radius"]), 3.5))
	_check("解析 BLOCK_SIZE", is_equal_approx(float(pl["block_w"]), 0.7)
		and is_equal_approx(float(pl["block_h"]), 0.04) and is_equal_approx(float(pl["block_d"]), 1.0))
	_check("解析 ANGLE_ORDER", (pl["angles"] as Array).size() == 4
		and is_equal_approx(float(pl["angles"][1]), 270.0))
	var scene := """
[node name="CameraRig" type="Node3D" parent="."]
EYE_HEIGHT = 3.5
CAMERA_BACK = 1.5
MOUSE_SENSITIVITY = 0.35
[node name="Body" type="MeshInstance3D" parent="Seats/Seat0/Avatar"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.6, 0)
"""
	var ps := Table3dTunerModel.parse_scene(scene)
	_check("解析相机眼高", is_equal_approx(float(ps["camera_eye_height"]), 3.5))
	_check("解析灵敏度", is_equal_approx(float(ps["camera_sensitivity"]), 0.35))
	_check("解析 Body.y", is_equal_approx(float(ps["body_y"]), -0.6))
	var view := """
const HUD_OFFSET := 0.55
const HUD_HEIGHT := 0.5
const PENDING_Y := 0.75  # 大牌高度
"""
	var pv := Table3dTunerModel.parse_view(view)
	_check("解析 HUD_OFFSET", is_equal_approx(float(pv["hud_offset"]), 0.55))
	_check("解析 PENDING_Y", is_equal_approx(float(pv["pending_y"]), 0.75))
	var merged := Table3dTunerModel.parse_sources({Table3dTunerModel.LAYOUT_FILE: layout,
		Table3dTunerModel.SCENE_FILE: scene, Table3dTunerModel.VIEW_FILE: view})
	_check("合并解析含全部键", merged.size() == Table3dTunerModel.params().size())
	_check("seat_angle_offset 解析为 0", is_equal_approx(float(merged["seat_angle_offset"]), 0.0))

func _test_apply() -> void:
	var v := Table3dTunerModel.defaults()
	v["seat_radius"] = 3.0
	v["block_w"] = 0.8
	v["block_d"] = 1.2
	v["table_radius"] = 4.0
	var layout := """
const BLOCK_SIZE := Vector3(0.7, 0.04, 1.0)   # 保留注释
const BLOCK_GAP := Vector3(0.06, 0.0, 0.06)
const TABLE_RADIUS := 3.5
const SEAT_RADIUS := 2.4
const ANGLE_ORDER := [0.0, 270.0, 90.0, 180.0]
const OTHER := 99
"""
	var rl := Table3dTunerModel.apply_layout(layout, v)
	_check("写回 SEAT_RADIUS", (rl["text"] as String).contains("const SEAT_RADIUS := 3.0"))
	_check("保留注释", (rl["text"] as String).contains("# 保留注释"))
	_check("保留无关常量", (rl["text"] as String).contains("const OTHER := 99"))
	_check("写回 BLOCK_SIZE", (rl["text"] as String).contains("const BLOCK_SIZE := Vector3(0.8, 0.04, 1.2)"))
	_check("无遗漏", (rl["missed"] as Array).is_empty())
	# 角度偏移 bake 进 ANGLE_ORDER
	v["seat_angle_offset"] = 5.0
	var rl2 := Table3dTunerModel.apply_layout(layout, v)
	_check("角度偏移写入 ANGLE_ORDER", (rl2["text"] as String).contains("[5.0, 275.0, 95.0, 185.0]"))
	# scene
	var scene := """
[node name="CameraRig" type="Node3D" parent="."]
EYE_HEIGHT = 3.5
CAMERA_BACK = 1.5
MOUSE_SENSITIVITY = 0.35
[node name="Body" type="MeshInstance3D" parent="Seats/Seat0/Avatar"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -0.6, 0)
"""
	v["camera_eye_height"] = 4.0
	v["body_y"] = -0.7
	var rs := Table3dTunerModel.apply_scene(scene, v)
	_check("写回 EYE_HEIGHT", (rs["text"] as String).contains("EYE_HEIGHT = 4.0"))
	_check("写回 Body.y", (rs["text"] as String).contains(", -0.7, 0)"))
	# view
	var view := """
const HUD_OFFSET := 0.55
const HUD_HEIGHT := 0.5
const PENDING_Y := 0.75  # 注释
"""
	v["pending_y"] = 0.9
	var rv := Table3dTunerModel.apply_view(view, v)
	_check("写回 PENDING_Y", (rv["text"] as String).contains("const PENDING_Y := 0.9"))
	_check("view 保留注释", (rv["text"] as String).contains("# 注释"))
	# fragment
	var frag := Table3dTunerModel.format_fragment(v)
	_check("片段含 SEAT_RADIUS", frag.contains("const SEAT_RADIUS := 3.0"))
	_check("片段含 EYE_HEIGHT", frag.contains("EYE_HEIGHT = 4.0"))
	# 锚点缺失 → missed 记录且原文本不变
	var bad := Table3dTunerModel.apply_layout("no constants here", v)
	_check("锚点缺失记 missed", (bad["missed"] as Array).size() > 0)
	_check("缺失时不改文本", bad["text"] == "no constants here")
	# 空格与注释保留（BLOCK_SIZE 只替换 Vector3(...)，不吃掉后面空格）
	_check("BLOCK_SIZE 注释前空格保留", (rl["text"] as String).contains("Vector3(0.8, 0.04, 1.2)   # 保留注释"))

## 回归：桌面网格/边框 BoxMesh 的 size 写回不得多包一层 Vector3（曾写成 Vector3(Vector3(...)) 致场景解析失败）。
func _test_apply_scene_mesh() -> void:
	var v := Table3dTunerModel.defaults()
	v["table_radius"] = 3.8
	var scene := """
[sub_resource type="BoxMesh" id="TableMesh"]
size = Vector3(7, 0.08, 7)

[sub_resource type="BoxMesh" id="TableEdgeMesh"]
size = Vector3(7.375, 0.12, 7.375)

[node name="CameraRig" type="Node3D" parent="."]
EYE_HEIGHT = 3.5
"""
	var rs := Table3dTunerModel.apply_scene(scene, v)
	var txt: String = rs["text"]
	_check("桌面网格 = 2×table_radius", txt.contains("size = Vector3(7.6, 0.08, 7.6)"))
	_check("桌面边框 = 网格+0.375", txt.contains("size = Vector3(7.975, 0.12, 7.975)"))
	_check("无双重 Vector3", not txt.contains("Vector3(Vector3"))
	# 幂等：再写一次结果一致
	var rs2 := Table3dTunerModel.apply_scene(txt, v)
	_check("scene 写回幂等", rs2["text"] == txt)

func _test_writer() -> void:
	var dir := "user://tuner_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := dir + "/sample.txt"
	var fw := FileAccess.open(f, FileAccess.WRITE)
	fw.store_string("hello")
	fw.close()
	# 注入脏检查 stub
	var dirty := {"v": true}
	var w := Table3dTunerWriter.new(func(_p): return dirty["v"])
	var blocked := w.write(f, "blocked", false)
	_check("脏文件默认拦截", not blocked["ok"] and blocked["error"] == "dirty")
	var okw := w.write(f, "written", true)
	_check("force 可写", okw["ok"])
	var f2 := FileAccess.open(f, FileAccess.READ)
	_check("内容已写", f2.get_as_text() == "written")
	f2.close()
	_check("备份存在", FileAccess.file_exists(w.backup_path(f)))
	var force_write := w.write(f, "written2", true)
	_check("force 写时 bak 保留旧内容", force_write["ok"])
	var bak := FileAccess.open(w.backup_path(f), FileAccess.READ)
	_check("bak 内容=旧值", bak.get_as_text() == "written")
	bak.close()
	_check("路径 .bak 后缀", w.backup_path("res://a.gd") == "res://a.gd.bak")

func _test_scene_apply() -> void:
	var scene: PackedScene = load("res://scenes/dev/table3d_tuner.tscn")
	var tuner = scene.instantiate()
	add_child(tuner)
	await get_tree().process_frame
	tuner.set_value("seat_radius", 3.0)
	tuner.set_value("camera_eye_height", 4.0)
	tuner.set_value("camera_back", 1.2)
	tuner.set_value("block_w", 0.8)
	tuner.apply_values()
	await get_tree().process_frame
	var seats: Array = tuner.seat_nodes()
	_check("4 个座位", seats.size() == 4)
	_check("座位半径应用", seats[0].position.is_equal_approx(Vector3(0.0, 0.0, 3.0)))
	var cam = tuner.table3d.camera
	_check("相机眼高应用", is_equal_approx(cam.EYE_HEIGHT, 4.0))
	_check("相机后退应用", is_equal_approx(cam.CAMERA_BACK, 1.2))
	_check("相机臂随座位半径（eye=4, dist=3+1.2）", cam.position.is_equal_approx(Vector3(0.0, 4.0, 4.2)))
	_check("Avatar 随相机抬到眼高", tuner.avatar_nodes()[1].position.y == 4.0)
	_check("样例牌已建（每席 4~6 张）", seats[0].get_node("HandAnchor").get_child_count() >= 4)

func _test_ui() -> void:
	var scene: PackedScene = load("res://scenes/dev/table3d_tuner.tscn")
	var tuner = scene.instantiate()
	add_child(tuner)
	await get_tree().process_frame
	tuner.build_ui()
	await get_tree().process_frame
	_check("UI 为每个参数建滑条", tuner.slider_count() == Table3dTunerModel.params().size())
	_check("写回目标含 layout/scene/view",
		tuner.write_targets().has(Table3dTunerModel.LAYOUT_FILE)
		and tuner.write_targets().has(Table3dTunerModel.SCENE_FILE)
		and tuner.write_targets().has(Table3dTunerModel.VIEW_FILE))

func _all_have(p: Dictionary, k: String) -> bool:
	for key in p.keys():
		if not (p[key] as Dictionary).has(k):
			return false
	return true
