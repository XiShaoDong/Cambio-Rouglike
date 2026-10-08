class_name CardFly
extends Node3D
## 单张飞牌控制器：Tween 只驱动标量 p，每帧 compose 唯一写 transform。
## 纯展示层：不做规则/隐私判断。复用 CardBlock 双面几何做翻面（不改 card_block.gd）。

signal finished

var config: CardFlyConfig = CardFlyConfig.new()
var body: CardBlock

var _p := 0.0
var _flying := false
var _start := Transform3D.IDENTITY
var _end := Transform3D.IDENTITY
var _roll_start := 0.0
var _roll_delta := 0.0
var _card_data: Dictionary = {}
var _start_up := false
var _end_up := false
var _face_shown := false
var _face_init := false
var _tween: Tween = null

func play(start: Transform3D, end: Transform3D, card_data: Dictionary,
		start_face_up: bool, end_face_up: bool) -> void:
	_build()
	_start = start
	_end = end
	_start_up = start_face_up
	_end_up = end_face_up
	_card_data = card_data
	_roll_start = 0.0 if start_face_up else 180.0
	_roll_delta = 0.0 if start_face_up == end_face_up else 180.0
	_p = 0.0
	_flying = true
	_face_init = false
	_update_visible_face()
	_apply()
	var dur := CardFlyMath.duration_for(start.origin.distance_to(end.origin), config.to_dict())
	set_process(true)
	_tween = create_tween()
	_tween.tween_property(self, "_p", 1.0, dur).set_trans(Tween.TRANS_LINEAR)
	_tween.finished.connect(_on_done)

func _build() -> void:
	if body != null:
		return
	body = CardBlock.new()
	body.name = "CardBody"
	add_child(body)
	body.set_pick_enabled(false)

func _apply() -> void:
	if body == null:
		return
	_update_visible_face()
	var c := CardFlyMath.compose(_start, _end, _p, _roll_start, _roll_delta, config.to_dict())
	global_transform = Transform3D(c["basis"], c["origin"])

## 当前可见面是否正面：翻转窗口外按起/终面；无需翻转时恒为起面。
## 起面与终面都非正面（如私人交换、罚牌）时，全程不显牌面/点数标签，避免泄漏。
func _face_up_now() -> bool:
	if _roll_delta == 0.0:
		return _start_up
	return _start_up if CardFlyMath.flip_t(_p, config.to_dict()) < 0.5 else _end_up

## 按"当前可见面"设置 body 的牌面/点数标签（可见面变才刷新）。
## 关键：点数标签是 billboard，翻到背面也会浮在卡上——必须随可见面切换，否则交换/抽牌时泄漏牌面。
func _update_visible_face() -> void:
	if body == null:
		return
	var up := _face_up_now()
	if _face_init and up == _face_shown:
		return
	var data: Dictionary = _card_data if up else {}
	body.setup({"card": data} if not data.is_empty() else {})
	_face_shown = up
	_face_init = true

func _process(_delta: float) -> void:
	_apply()

func _on_done() -> void:
	_flying = false
	set_process(false)
	_apply()
	finished.emit()
	queue_free()

func progress() -> float:
	return _p

func is_flying() -> bool:
	return _flying

func card_block() -> CardBlock:
	return body
