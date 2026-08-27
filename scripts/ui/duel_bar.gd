class_name DuelBar
extends Control
## 贴牌比拼 bar（Feature 10 · SLAP_DUEL）
## 布局：横条 + 随机位置加粗区（中心红心为目标）+ 来回扫动的标记 + STOP 按钮。
## 标记扫动与服务器同函数（0→1→0）；胜负由服务器按到达时间判定，本地仅作瞄准/反馈。

const TRACK_W := 420.0
const TRACK_H := 40.0
const BAND_W := 72.0
const MARKER_W := 5.0

var main: Node
var _marker: ColorRect
var _stop_button: Button
var _tween: Tween
var _stopped := false
var _on_stop: Callable = Callable()

func setup(owner_main: Node, duel: Dictionary, on_stop: Callable) -> void:
	main = owner_main
	_on_stop = on_stop
	_build_ui(duel)
	_start_sweep()

func _build_ui(duel: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var duration_ms := int(duel.get("duration_ms", 2000))
	var target := clampf(float(duel.get("target", 0.5)), 0.0, 1.0)
	var is_contestant: bool = int(duel.get("viewer_contestant", 0)) == 1

	# 全屏半透明遮罩，突出比拼窗口
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# 居中窗口（CenterContainer 自动按内容居中）
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var win := PanelContainer.new()
	win.mouse_filter = Control.MOUSE_FILTER_STOP
	var win_style := StyleBoxFlat.new()
	win_style.bg_color = Color(0.09, 0.1, 0.14, 1.0)
	win_style.set_corner_radius_all(14)
	win_style.set_content_margin_all(24)
	win_style.border_color = Color(1.0, 0.84, 0.48, 0.85)
	win_style.set_border_width_all(2)
	win.add_theme_stylebox_override("panel", win_style)
	center.add_child(win)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(TRACK_W + 80, 0)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	win.add_child(vbox)

	var title := Label.new()
	title.text = "贴牌比拼！谁最接近红色标记谁获胜"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", UITheme.color("text_primary"))
	vbox.add_child(title)

	# 轨道
	var track := Control.new()
	track.custom_minimum_size = Vector2(TRACK_W, TRACK_H)
	track.size = Vector2(TRACK_W, TRACK_H)
	vbox.add_child(track)
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.13, 0.17, 1.0)
	bg_style.set_corner_radius_all(6)
	bg.add_theme_stylebox_override("panel", bg_style)
	track.add_child(bg)
	# 加粗区（随机位置，中心 = 目标）
	var band := ColorRect.new()
	band.color = Color(1.0, 0.84, 0.48, 0.35)
	band.position = Vector2(target * TRACK_W - BAND_W / 2.0, 0)
	band.size = Vector2(BAND_W, TRACK_H)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(band)
	# 中心红点（恒在加粗区正中）
	var red := ColorRect.new()
	red.color = Color(1.0, 0.22, 0.22, 1.0)
	red.position = Vector2(target * TRACK_W - 2.0, 0)
	red.size = Vector2(4.0, TRACK_H)
	red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(red)
	# 移动标记（绿）
	_marker = ColorRect.new()
	_marker.color = Color(0.3, 0.95, 0.45, 1.0)
	_marker.size = Vector2(MARKER_W, TRACK_H)
	_marker.position = Vector2(-MARKER_W / 2.0, 0)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_marker)

	var hint := Label.new()
	hint.text = "扫动 %s 秒 · 最接近红心者贴牌成功" % ("%.1f" % (duration_ms / 1000.0))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", UITheme.color("text_secondary"))
	vbox.add_child(hint)

	if is_contestant:
		_stop_button = Button.new()
		_stop_button.text = "■ STOP"
		_stop_button.custom_minimum_size = Vector2(120, 44)
		_stop_button.add_theme_font_size_override("font_size", 18)
		_stop_button.pressed.connect(_on_stop_pressed)
		vbox.add_child(_stop_button)
		var key_hint := Label.new()
		key_hint.text = "提示：按 空格 或点击 STOP 停止"
		key_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key_hint.add_theme_font_size_override("font_size", 12)
		key_hint.add_theme_color_override("font_color", UITheme.color("text_secondary"))
		vbox.add_child(key_hint)
	else:
		var wait := Label.new()
		wait.text = "比拼进行中，等待结果…"
		wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wait.add_theme_color_override("font_color", UITheme.color("text_secondary"))
		vbox.add_child(wait)

## 公开停止入口（main 的空格快捷键调用）。
func stop() -> void:
	_on_stop_pressed()

## 0→1→0 一趟来回（总时长 = duration_ms）。
func _start_sweep() -> void:
	_tween = create_tween()
	var half_sec: float = 1.0  # 2s 总时长：半程各 1s
	_tween.tween_property(_marker, "position:x", TRACK_W - MARKER_W / 2.0, half_sec)
	_tween.tween_property(_marker, "position:x", -MARKER_W / 2.0, half_sec)

func _on_stop_pressed() -> void:
	if _stopped:
		return
	_stopped = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_stop_button.disabled = true
	_stop_button.text = "已停止"
	if _on_stop.is_valid():
		_on_stop.call()