extends Node
## headless 单元测试：PlayerStatPanel（状态面板）。

var failures := 0
var checks := 0

func _ready() -> void:
	_run()
	print("=== STAT PANEL RESULT: %d/%d passed%s ===" % [checks - failures, checks, " (FAILURES!)" if failures else ""])
	get_tree().quit(1 if failures else 0)

func _check(name: String, ok: bool) -> void:
	checks += 1
	if ok:
		print("[PASS] " + name)
	else:
		failures += 1
		printerr("[FAIL] " + name)

func _run() -> void:
	var panel := PlayerStatPanel.new()
	add_child(panel)
	panel.set_data("甲", 2, 100, 4)
	_check("data 记录", panel.data.get("name") == "甲" and int(panel.data.get("health")) == 2 and int(panel.data.get("currency")) == 100 and int(panel.data.get("cards")) == 4)
	_check("名字显示", panel.name_visible() and panel.name_text() == "甲")
	panel.set_data("", 1, 0, 0)
	_check("无名字时隐藏名字行", not panel.name_visible())
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
	_check("黑边框 2px", style != null and style.border_width_left == 2 and style.border_color.a > 0.8)
	_check("透明白灰底", style != null and style.bg_color.a > 0.0 and style.bg_color.a < 0.5)
