class_name TutorialProgress
extends RefCounted
## 教程进度本地持久化（仅本机用户）：seen/completed + 5 条首局轻提示。
## 路径可注入（测试用），与 KeybindStore 同模式。

const DEFAULT_PATH := "user://tutorial.cfg"
const SECTION := "tutorial"
const VERSION := 1
const HINTS := ["initial_peek", "first_turn", "first_slap", "first_shop", "first_settle"]

var path := DEFAULT_PATH
var seen := false
var completed := false
var hints: Dictionary = {}

func _init(p := DEFAULT_PATH) -> void:
	path = p
	for id in HINTS:
		hints[id] = false

func load() -> void:
	seen = false
	completed = false
	for id in HINTS:
		hints[id] = false
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	if int(cf.get_value(SECTION, "version", 0)) != VERSION:
		return
	seen = bool(cf.get_value(SECTION, "seen", false))
	completed = bool(cf.get_value(SECTION, "completed", false))
	for id in HINTS:
		hints[id] = bool(cf.get_value(SECTION, "hint_" + id, false))

func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value(SECTION, "version", VERSION)
	cf.set_value(SECTION, "seen", seen)
	cf.set_value(SECTION, "completed", completed)
	for id in HINTS:
		cf.set_value(SECTION, "hint_" + id, bool(hints.get(id, false)))
	cf.save(path)

func mark_seen() -> void:
	seen = true
	save()

func mark_completed() -> void:
	completed = true
	seen = true
	save()

func hint_done(id: String) -> bool:
	return bool(hints.get(id, false))

func mark_hint(id: String) -> void:
	if hints.has(id):
		hints[id] = true
		save()

func reset() -> void:
	seen = false
	completed = false
	for id in HINTS:
		hints[id] = false
	save()
