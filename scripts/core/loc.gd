extends Node
## 语言引擎（autoload，无 class_name）
## 职责：按 Settings.display/language 提供 tr(key) 翻译。
## 本阶段只覆盖设置菜单文案；其余 UI 文案迁移是后续独立任务
## （key 缺失时回退返回 key 本身，迁移包装安全）。
## 语言选项自身用母语显示（中文 / English），不做翻译。

signal language_changed(language: String)

const LANGUAGES := ["zh", "en"]

const STRINGS := {
	"zh": {
		"settings_title": "设置",
		"volume": "音量",
		"mute": "静音",
		"theme": "主题",
		"theme_dark": "深色",
		"theme_light": "浅色",
		"language": "语言",
		"close": "关闭",
		"esc_hint": "按 ESC 关闭",
	},
	"en": {
		"settings_title": "Settings",
		"volume": "Volume",
		"mute": "Mute",
		"theme": "Theme",
		"theme_dark": "Dark",
		"theme_light": "Light",
		"language": "Language",
		"close": "Close",
		"esc_hint": "Press ESC to close",
	},
}

var language := "zh"

func _ready() -> void:
	language = str(Settings.get_setting("display", "language", "zh"))
	if not STRINGS.has(language):
		language = "zh"

func t(key: String) -> String:
	return STRINGS.get(language, {}).get(key, key)

## 切换语言并持久化（经 Settings），同时广播 language_changed。
func set_language(lang: String) -> void:
	if not STRINGS.has(lang) or language == lang:
		return
	language = lang
	Settings.set_setting("display", "language", lang)
	language_changed.emit(language)