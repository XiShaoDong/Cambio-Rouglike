class_name EmoteDisplay
extends Node3D
## 表情占位：角色头顶悬浮数字 billboard，持续 DURATION 秒后淡出消失。

signal finished

const DURATION := 2.5
const FADE_OUT := 0.3
const FONT_SIZE := 96
const COLOR := Color(1.0, 0.96, 0.85)

var _label: Label3D
var _t := 0.0
var _done := false

func _ready() -> void:
	_build()

func _build() -> void:
	if _label != null:
		return
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.006
	_label.font_size = FONT_SIZE
	_label.outline_size = 12
	_label.outline_modulate = Color(0, 0, 0, 0.7)
	_label.modulate = COLOR
	add_child(_label)

## 播放表情（index 0..N-1，占位显示 index+1）。由宿主设置节点位置到头顶。
func play(index: int, _duration := DURATION) -> void:
	_build()
	_label.text = str(index + 1)
	_label.modulate = COLOR
	_t = 0.0
	_done = false

func _process(delta: float) -> void:
	if _done or _label == null:
		return
	_t += delta
	if _t > DURATION:
		_label.modulate.a = clampf(1.0 - (_t - DURATION) / FADE_OUT, 0.0, 1.0)
	_label.position.y = sin(_t * 3.0) * 0.06
	if _t >= DURATION + FADE_OUT:
		_done = true
		finished.emit()
		queue_free()
