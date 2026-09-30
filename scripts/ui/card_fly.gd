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
var _tween: Tween = null

func play(start: Transform3D, end: Transform3D, card_data: Dictionary,
		start_face_up: bool, end_face_up: bool) -> void:
	_build()
	_start = start
	_end = end
	_roll_start = 0.0 if start_face_up else 180.0
	_roll_delta = 0.0 if start_face_up == end_face_up else 180.0
	_p = 0.0
	_flying = true
	body.setup({"card": card_data} if not card_data.is_empty() else {})
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
	var c := CardFlyMath.compose(_start, _end, _p, _roll_start, _roll_delta, config.to_dict())
	global_transform = Transform3D(c["basis"], c["origin"])

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
