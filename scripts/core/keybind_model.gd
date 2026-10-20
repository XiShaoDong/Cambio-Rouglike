class_name KeybindModel
extends RefCounted
## 按键映射纯函数模型（headless 可测，无节点/网络/InputMap 依赖）。
## 只覆盖界面/展示类动作；游戏操作键列为保留键，不可绑定。

const ERR_RESERVED := "reserved"
const ERR_UNKNOWN := "unknown_action"

## 有序动作表（id / label / desc / default）。default 用 Godot Key 常量。
const ACTIONS := [
	{"id": "kb_manual",   "label": "手册",     "desc": "开/关 手册页",            "default": KEY_TAB},
	{"id": "kb_stats",    "label": "Stats",    "desc": "开/关 弃牌堆 Stats 页",   "default": KEY_S},
	{"id": "kb_keymap",   "label": "按键映射", "desc": "开/关 按键映射页",        "default": KEY_K},
	{"id": "kb_talk",     "label": "说话",     "desc": "按住/切换 说话（嘴开合）", "default": KEY_M},
	{"id": "kb_zoom",     "label": "放大",     "desc": "按住 拉近视场（放大）",    "default": KEY_META},
	{"id": "kb_toggle3d", "label": "切换 3D",  "desc": "在 2D 与 3D 桌面间切换",  "default": KEY_V},
]
## 保留键：不可被界面动作绑定（游戏操作 / 系统 / 修饰键）。
## KEY_ALT 为 kb_zoom 的固定第二键，故列入保留。
const RESERVED := [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_F10, KEY_ALT]

static func defaults() -> Dictionary:
	var out := {}
	for a in ACTIONS:
		out[str(a["id"])] = int(a["default"])
	return out

static func action_ids() -> Array:
	var out: Array = []
	for a in ACTIONS:
		out.append(str(a["id"]))
	return out

static func action_def(id: String) -> Dictionary:
	for a in ACTIONS:
		if str(a["id"]) == id:
			return a
	return {}

static func resolve(map: Dictionary, keycode: int) -> String:
	for id in map:
		if int(map[id]) == keycode:
			return str(id)
	return ""

## 重绑：未知动作/保留键拒绝；与已占用键冲突则**自动交换**。
## 返回 {ok, error, map, swapped}；map 为新字典，不就地改入参。
static func rebind(map: Dictionary, id: String, keycode: int) -> Dictionary:
	if not defaults().has(id):
		return {"ok": false, "error": ERR_UNKNOWN, "map": map, "swapped": ""}
	if keycode in RESERVED:
		return {"ok": false, "error": ERR_RESERVED, "map": map, "swapped": ""}
	var out := map.duplicate()
	var old_key := int(map.get(id, -1))
	var swapped := ""
	for other in out.keys():
		if str(other) != id and int(out[other]) == keycode:
			swapped = str(other)
			break
	if swapped != "":
		out[swapped] = old_key
	out[id] = keycode
	return {"ok": true, "error": "", "map": out, "swapped": swapped}

static func to_dict(map: Dictionary) -> Dictionary:
	var out := {}
	for id in map:
		out[str(id)] = int(map[id])
	return out

## 校验：未知 id 丢弃、缺失补默认、非法（保留键）值回退默认。
static func from_dict(d: Dictionary) -> Dictionary:
	var out := defaults()
	for id in out.keys():
		if d.has(id):
			var k := int(d[id])
			if not (k in RESERVED):
				out[id] = k
	return out
