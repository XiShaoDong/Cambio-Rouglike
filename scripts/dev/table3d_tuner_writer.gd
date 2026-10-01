class_name Table3dTunerWriter
extends RefCounted
## 写回引擎：脏检查 + 备份 + 写入。不负责计算新文本（由 model.apply_* 提供）。

var _dirty_checker: Callable
var _git_ok := true

func _init(dirty_checker := Callable()) -> void:
	_dirty_checker = dirty_checker

func backup_path(path: String) -> String:
	return path + ".bak"

func is_dirty(path: String) -> bool:
	if _dirty_checker.is_valid():
		return bool(_dirty_checker.call(path))
	return _git_dirty(path)

func _git_dirty(path: String) -> bool:
	if not _git_ok:
		return false
	var rel := path.trim_prefix("res://")
	var out: Array = []
	var code := OS.execute("git", ["status", "--porcelain", "--", rel], out, true)
	if code != 0:
		_git_ok = false
		return false   # git 不可用时不阻断（由用户判断）
	return not str(out[0] if out.size() > 0 else "").strip_edges().is_empty()

func write(path: String, new_text: String, force := false) -> Dictionary:
	if not force and is_dirty(path):
		return {"ok": false, "error": "dirty"}
	if FileAccess.file_exists(path):
		var src := FileAccess.open(path, FileAccess.READ)
		var old := src.get_as_text() if src != null else ""
		if src != null:
			src.close()
		var bak := FileAccess.open(backup_path(path), FileAccess.WRITE)
		if bak != null:
			bak.store_string(old)
			bak.close()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "open_failed"}
	f.store_string(new_text)
	f.close()
	return {"ok": true, "error": ""}
