class_name KeybindStore
extends RefCounted
## 按键映射本地持久化薄壳：ConfigFile 读写 user://（仅本机当前用户，不联网）。
## 路径可注入（测试用），未来接入账户只需换 path/profile。

const DEFAULT_PATH := "user://keybinds.cfg"
const SECTION := "keybinds"
const VERSION := 1

var path := DEFAULT_PATH
var map: Dictionary = {}

func _init(p := DEFAULT_PATH) -> void:
	path = p
	map = KeybindModel.defaults()

## 读文件；缺文件 / 版本不符 / 解析失败 → 回退默认（无副作用）。
func load() -> void:
	map = KeybindModel.defaults()
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	if int(cf.get_value(SECTION, "version", 0)) != VERSION:
		return
	var raw := {}
	for id in KeybindModel.action_ids():
		if cf.has_section_key(SECTION, id):
			raw[id] = int(cf.get_value(SECTION, id))
	map = KeybindModel.from_dict(raw)

## 写文件（含 version；预留 profile 键，未来按账户分文件）。
func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "version", VERSION)
	cf.set_value(SECTION, "profile", "")
	for id in map.keys():
		cf.set_value(SECTION, str(id), int(map[id]))
	cf.save(path)

func key_of(id: String) -> int:
	return int(map.get(id, -1))

func action_for(keycode: int) -> String:
	return KeybindModel.resolve(map, keycode)

## 只改内存（不落盘）；由调用方决定何时 save。
func apply(new_map: Dictionary) -> void:
	map = new_map.duplicate()

func reset_to_defaults() -> void:
	map = KeybindModel.defaults()
