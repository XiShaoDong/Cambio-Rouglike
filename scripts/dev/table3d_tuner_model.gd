class_name Table3dTunerModel
extends RefCounted
## Table3D 调参工具的纯函数层：参数定义、源文件解析、写回文本变换、片段生成。
## 无 I/O、无节点依赖 → headless 可测。

const LAYOUT_FILE := "res://scripts/ui/table3d_layout.gd"
const SCENE_FILE := "res://scenes/ui/table3d.tscn"
const VIEW_FILE := "res://scripts/ui/table3d_view.gd"

## key -> {group, label, min, max, step, default}
static func params() -> Dictionary:
	return {
		"camera_eye_height": _p("相机", "眼高 EYE_HEIGHT", 0.5, 8.0, 0.05, 3.5),
		"camera_back": _p("相机", "后退 CAMERA_BACK", 0.0, 5.0, 0.05, 1.5),
		"camera_sensitivity": _p("相机", "灵敏度", 0.05, 2.0, 0.05, 0.35),
		"seat_radius": _p("座位", "座位半径 SEAT_RADIUS", 0.5, 6.0, 0.05, 2.4),
		"seat_angle_offset": _p("座位", "整体角度偏移", -45.0, 45.0, 1.0, 0.0),
		"table_radius": _p("桌面·卡牌", "桌面半径 TABLE_RADIUS", 1.0, 6.0, 0.05, 3.5),
		"block_w": _p("桌面·卡牌", "卡宽 BLOCK_SIZE.x", 0.2, 1.5, 0.01, 0.7),
		"block_h": _p("桌面·卡牌", "卡厚 BLOCK_SIZE.y", 0.01, 0.2, 0.005, 0.04),
		"block_d": _p("桌面·卡牌", "卡深 BLOCK_SIZE.z", 0.2, 2.0, 0.01, 1.0),
		"gap_x": _p("桌面·卡牌", "列距 BLOCK_GAP.x", 0.0, 0.5, 0.005, 0.06),
		"gap_z": _p("桌面·卡牌", "行距 BLOCK_GAP.z", 0.0, 0.5, 0.005, 0.06),
		"body_y": _p("玩家建模", "身体高 Body.y", -1.5, 0.5, 0.01, -0.6),
		"head_y": _p("玩家建模", "头高 Head.y", -1.0, 1.0, 0.01, 0.0),
		"hud_offset": _p("HUD", "HUD_OFFSET", 0.0, 2.0, 0.05, 0.55),
		"hud_height": _p("HUD", "HUD_HEIGHT", 0.0, 2.0, 0.05, 0.5),
		"pending_y": _p("HUD", "PENDING_Y", 0.0, 2.0, 0.05, 0.75),
	}

static func _p(group: String, label: String, mn: float, mx: float, st: float, default: float) -> Dictionary:
	return {"group": group, "label": label, "min": mn, "max": mx, "step": st, "default": default}

static func groups() -> Array:
	var out: Array = []
	for key in params().keys():
		var g := str((params()[key] as Dictionary)["group"])
		if not out.has(g):
			out.append(g)
	return out

static func defaults() -> Dictionary:
	var out := {}
	for key in params().keys():
		out[key] = float((params()[key] as Dictionary)["default"])
	return out

static func _first_float(text: String, pattern: String) -> float:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return 0.0
	var m := re.search(text)
	return float(m.get_string(1)) if m != null else 0.0

static func _vec3(text: String, name: String) -> Array:
	var re := RegEx.new()
	if re.compile("const %s := Vector3\\(([^)]*)\\)" % name) != OK:
		return [0.0, 0.0, 0.0]
	var m := re.search(text)
	if m == null:
		return [0.0, 0.0, 0.0]
	var out: Array = []
	for part in m.get_string(1).split(","):
		out.append(float(part.strip_edges()))
	return out

static func parse_layout(text: String) -> Dictionary:
	var b := _vec3(text, "BLOCK_SIZE")
	var g := _vec3(text, "BLOCK_GAP")
	var angles: Array = []
	var re := RegEx.new()
	if re.compile("const ANGLE_ORDER := \\[([^\\]]*)\\]") == OK:
		var m := re.search(text)
		if m != null:
			for part in m.get_string(1).split(","):
				angles.append(float(part.strip_edges()))
	return {
		"seat_radius": _first_float(text, "const SEAT_RADIUS := ([0-9.]+)"),
		"table_radius": _first_float(text, "const TABLE_RADIUS := ([0-9.]+)"),
		"block_w": float(b[0]), "block_h": float(b[1]), "block_d": float(b[2]),
		"gap_x": float(g[0]), "gap_z": float(g[2]),
		"angles": angles,
	}

static func parse_scene(text: String) -> Dictionary:
	return {
		"camera_eye_height": _first_float(text, "(?m)^EYE_HEIGHT = ([0-9.]+)"),
		"camera_back": _first_float(text, "(?m)^CAMERA_BACK = ([0-9.]+)"),
		"camera_sensitivity": _first_float(text, "(?m)^MOUSE_SENSITIVITY = ([0-9.]+)"),
		"body_y": _first_float(text, "\\[node name=\"Body\"[^\\n]*\\]\\ntransform = Transform3D\\([^)]*, ([0-9.\\-]+), 0\\)"),
		"head_y": _first_float(text, "\\[node name=\"Head\"[^\\n]*\\]\\ntransform = Transform3D\\([^)]*, ([0-9.\\-]+), 0\\)"),
	}

static func parse_view(text: String) -> Dictionary:
	return {
		"hud_offset": _first_float(text, "const HUD_OFFSET := ([0-9.]+)"),
		"hud_height": _first_float(text, "const HUD_HEIGHT := ([0-9.]+)"),
		"pending_y": _first_float(text, "const PENDING_Y := ([0-9.]+)"),
	}

static func parse_sources(texts: Dictionary) -> Dictionary:
	var out := {}
	out.merge(parse_layout(str(texts.get(LAYOUT_FILE, ""))), true)
	out.merge(parse_scene(str(texts.get(SCENE_FILE, ""))), true)
	out.merge(parse_view(str(texts.get(VIEW_FILE, ""))), true)
	out.erase("angles")
	out["seat_angle_offset"] = 0.0
	return out

## 替换 text 中 pattern 的第 group 组为 new_text。group 组无匹配返回 (ok=false, text 原样)。
static func _sub_group(text: String, pattern: String, group: int, new_text: String, all := false) -> Dictionary:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return {"ok": false, "text": text}
	var out := ""
	var pos := 0
	var hit := false
	while true:
		var m := re.search(text, pos)
		if m == null:
			break
		out += text.substr(pos, m.get_start(group) - pos)
		out += new_text
		pos = m.get_end(group)
		hit = true
		if not all:
			break
	out += text.substr(pos)
	return {"ok": hit, "text": out} if hit else {"ok": false, "text": text}

static func _fmt(f: float, decimals := 3) -> String:
	var s := String.num(f, decimals)
	if not s.contains("."):
		return s + ".0"
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s += "0"
	return s

static func apply_layout(text: String, values: Dictionary) -> Dictionary:
	var t := text
	var missed: Array = []
	var steps := [
		["const SEAT_RADIUS := ([0-9.]+)", "seat_radius"],
		["const TABLE_RADIUS := ([0-9.]+)", "table_radius"],
	]
	for s in steps:
		var r := _sub_group(t, s[0], 1, _fmt(float(values.get(s[1], 0.0))))
		t = r["text"]
		if not r["ok"]:
			missed.append(s[1])
	var b := _sub_group(t, "const BLOCK_SIZE := (Vector3\\([^)]*\\))", 1,
		"Vector3(%s, %s, %s)" % [_fmt(float(values["block_w"])), _fmt(float(values["block_h"])), _fmt(float(values["block_d"]))])
	t = b["text"]
	if not b["ok"]:
		missed.append("block_size")
	var g := _sub_group(t, "const BLOCK_GAP := (Vector3\\([^)]*\\))", 1,
		"Vector3(%s, 0.0, %s)" % [_fmt(float(values["gap_x"])), _fmt(float(values["gap_z"]))])
	t = g["text"]
	if not g["ok"]:
		missed.append("block_gap")
	# 角度：解析基准 + 偏移 → 覆盖 ANGLE_ORDER
	var base: Array = parse_layout(text)["angles"]
	var off := float(values.get("seat_angle_offset", 0.0))
	var parts: Array = []
	for a in base:
		parts.append(_fmt(float(a) + off))
	var an := _sub_group(t, "const ANGLE_ORDER := (\\[[^\\]]*\\])", 1, "[%s]" % ", ".join(parts))
	t = an["text"]
	if not an["ok"]:
		missed.append("angle_order")
	return {"text": t, "missed": missed}

static func apply_scene(text: String, values: Dictionary) -> Dictionary:
	var t := text
	var missed: Array = []
	var scalars := [
		[["camera_eye_height"], "(?m)^EYE_HEIGHT = ([0-9.]+)"],
		[["camera_back"], "(?m)^CAMERA_BACK = ([0-9.]+)"],
		[["camera_sensitivity"], "(?m)^MOUSE_SENSITIVITY = ([0-9.]+)"],
	]
	for s in scalars:
		var r := _sub_group(t, s[1], 1, _fmt(float(values.get(s[0][0], 0.0))))
		t = r["text"]
		if not r["ok"]:
			missed.append(s[0][0])
	# 桌面网格尺寸 = 2 × table_radius；边框 = 网格 + 0.375（块锚定，见下方辅助函数）
	var d := float(values["table_radius"]) * 2.0
	t = _apply_table_size(t, d)
	t = _apply_edge_size(t, d + 0.375)
	# Body / Head 局部 Y（块锚定，4 席全部）
	var body_re := "\\[node name=\"Body\" type=\"MeshInstance3D\" parent=\"Seats/Seat\\d+/Avatar\"\\]\\ntransform = Transform3D\\([^)]*, ([0-9.\\-]+), 0\\)"
	var rb := _sub_group(t, body_re, 1, _fmt(float(values["body_y"])), true)
	t = rb["text"]
	if not rb["ok"]:
		missed.append("body_y")
	var head_re := "\\[node name=\"Head\" type=\"MeshInstance3D\" parent=\"Seats/Seat\\d+/Avatar\"\\]\\ntransform = Transform3D\\([^)]*, ([0-9.\\-]+), 0\\)"
	var rh := _sub_group(t, head_re, 1, _fmt(float(values["head_y"])), true)
	t = rh["text"]
	if not rh["ok"]:
		missed.append("head_y")
	return {"text": t, "missed": missed}

static func _box_mesh_size_pattern(id: String) -> String:
	return "(\\[sub_resource type=\"BoxMesh\" id=\"%s\"\\]\\n(?:[^\\n]*\\n)*?size = )(Vector3\\([^)]*\\))" % id

static func _apply_box_size(text: String, id: String, size: Vector3) -> Dictionary:
	var pat := _box_mesh_size_pattern(id)
	var re := RegEx.new()
	if re.compile(pat) != OK:
		return {"ok": false, "text": text}
	var m := re.search(text)
	if m == null:
		return {"ok": false, "text": text}
	var new_line := "Vector3(%s, %s, %s)" % [_fmt(size.x), _fmt(size.y), _fmt(size.z)]
	var start := m.get_start(2)
	var end := m.get_end(2)
	return {"ok": true, "text": text.substr(0, start) + new_line + text.substr(end)}

static func _apply_table_size(text: String, side: float) -> String:
	return _apply_box_size(text, "TableMesh", Vector3(side, 0.08, side))["text"]

static func _apply_edge_size(text: String, side: float) -> String:
	return _apply_box_size(text, "TableEdgeMesh", Vector3(side, 0.12, side))["text"]

static func apply_view(text: String, values: Dictionary) -> Dictionary:
	var t := text
	var missed: Array = []
	var steps := [
		["const HUD_OFFSET := ([0-9.]+)", "hud_offset"],
		["const HUD_HEIGHT := ([0-9.]+)", "hud_height"],
		["const PENDING_Y := ([0-9.]+)", "pending_y"],
	]
	for s in steps:
		var r := _sub_group(t, s[0], 1, _fmt(float(values.get(s[1], 0.0))))
		t = r["text"]
		if not r["ok"]:
			missed.append(s[1])
	return {"text": t, "missed": missed}

static func format_fragment(values: Dictionary) -> String:
	var lines := [
		"# 由 Table3D Tuner 生成",
		"const SEAT_RADIUS := %s" % _fmt(float(values["seat_radius"])),
		"const TABLE_RADIUS := %s" % _fmt(float(values["table_radius"])),
		"const BLOCK_SIZE := Vector3(%s, %s, %s)" % [_fmt(float(values["block_w"])), _fmt(float(values["block_h"])), _fmt(float(values["block_d"]))],
		"const BLOCK_GAP := Vector3(%s, 0.0, %s)" % [_fmt(float(values["gap_x"])), _fmt(float(values["gap_z"]))],
		"# table3d.tscn / CameraRig",
		"EYE_HEIGHT = %s" % _fmt(float(values["camera_eye_height"])),
		"CAMERA_BACK = %s" % _fmt(float(values["camera_back"])),
		"MOUSE_SENSITIVITY = %s" % _fmt(float(values["camera_sensitivity"])),
		"# table3d_view.gd",
		"HUD_OFFSET := %s" % _fmt(float(values["hud_offset"])),
		"HUD_HEIGHT := %s" % _fmt(float(values["hud_height"])),
		"PENDING_Y := %s" % _fmt(float(values["pending_y"])),
	]
	return "\n".join(lines)
