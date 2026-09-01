extends Node
## 通用设置存储（autoload，scene 无需 @export）
## 职责：游戏设置的单一数据源 + ConfigFile 持久化 + 变更信号。
## 子系统（AudioManager/Loc 等）监听 setting_changed 即时生效；
## 设置菜单只是"编辑器"，读写本节点。
## 扩展新设置 = 默认值加 key + 菜单加一行。

signal setting_changed(section: String, key: String, value: Variant)

const PATH := "user://settings.cfg"

var _data := {
	"audio": {
		"volume": 1.0,
		"muted": false,
	},
	"display": {
		"theme": "dark",
		"language": "zh",
	},
}

func _ready() -> void:
	load_settings()

func get_setting(section: String, key: String, default: Variant = null) -> Variant:
	if _data.has(section) and _data[section].has(key):
		return _data[section][key]
	return default

func set_setting(section: String, key: String, value: Variant) -> void:
	if not _data.has(section):
		_data[section] = {}
	if _data[section].has(key) and _data[section][key] == value:
		return
	_data[section][key] = value
	save_settings()
	setting_changed.emit(section, key, value)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for section in cfg.get_sections():
		if not _data.has(section):
			_data[section] = {}
		for key in cfg.get_section_keys(section):
			_data[section][key] = cfg.get_value(section, key)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for section in _data:
		for key in _data[section]:
			cfg.set_value(section, key, _data[section][key])
	cfg.save(PATH)