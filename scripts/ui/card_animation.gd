class_name CardAnimation
extends Node3D
## 卡牌动效控制器：Tween 只驱动标量进度，每帧唯一写 transform 处是 compose。
## 纯展示层：不做规则/隐私判断。

@export var card_data: Dictionary = {"rank": "A", "suit": "♥"}

var config: CardAnimationConfig = CardAnimationConfig.new()
var state := CardAnimationMath.IDLE
var hovering := false
var showing_back := false
var ray_local := Vector2.ZERO

var hover_p := 0.0
var press_p := 0.0
var flip_p := 0.0
var land_p := 0.0
var flip_turns := 0

var visual: Node3D
var body: CardBlock
var shadow: MeshInstance3D

var _idle_time := 0.0
var _tweens := {}

func _ready() -> void:
	_build()
	set_process(true)

func _build() -> void:
	if visual != null:
		return
	visual = Node3D.new()
	visual.name = "VisualRoot"
	add_child(visual)
	body = CardBlock.new()
	body.name = "CardBody"
	visual.add_child(body)
	body.setup({"card": card_data})
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Y
	plane.size = Vector2(Table3dLayout.BLOCK_SIZE.x, Table3dLayout.BLOCK_SIZE.z)
	shadow = MeshInstance3D.new()
	shadow.name = "Shadow"
	shadow.mesh = plane
	shadow.position = Vector3(0.0, 0.002, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.0, 0.0, 0.0, config.shadow_base_alpha)
	shadow.material_override = mat
	add_child(shadow)
	_apply()

func _progress() -> Dictionary:
	return {"hover": hover_p, "press": press_p, "flip": flip_p, "land": land_p}

func _process(delta: float) -> void:
	_idle_time += delta
	_apply()

func _apply() -> void:
	if visual == null:
		return
	var c := CardAnimationMath.compose(_progress(), config.to_dict(), _idle_time, ray_local)
	var rot: Vector3 = c["visual_rot_deg"]
	var rot_basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
	# 翻牌绕卡长轴（local Z），叠加在 hover 仰角之后；flip_turns 累计避免下一次翻牌回弹
	rot_basis = rot_basis * Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(float(flip_turns) * 180.0 + float(c["flip_deg"])))
	visual.transform = Transform3D(rot_basis.scaled(Vector3.ONE * float(c["visual_scale"])), c["visual_pos"])
	shadow.scale = Vector3(float(c["shadow_scale"]), 1.0, float(c["shadow_scale"]))
	var mat: StandardMaterial3D = shadow.material_override
	mat.albedo_color = Color(0.0, 0.0, 0.0, float(c["shadow_alpha"]))
	var vis_back := (flip_turns % 2) == 1
	if state == CardAnimationMath.FLIP:
		vis_back = ((flip_turns + (1 if flip_p >= 0.5 else 0)) % 2) == 1
	if vis_back != showing_back:
		showing_back = vis_back
		body.show_back(showing_back)

func _tween_prop(prop: String, to: float, dur: float, trans: int, ease: int) -> Tween:
	if _tweens.has(prop):
		var old: Tween = _tweens[prop]
		if old != null and old.is_valid():
			old.kill()
	var tw := create_tween()
	_tweens[prop] = tw
	tw.tween_property(self, prop, to, dur).set_trans(trans).set_ease(ease)
	return tw

func enter_hover() -> void:
	hovering = true
	if state == CardAnimationMath.FLIP or state == CardAnimationMath.LAND:
		return
	state = CardAnimationMath.HOVER
	_tween_prop("hover_p", 1.0, config.hover_in_dur, Tween.TRANS_BACK, Tween.EASE_OUT)

func exit_hover() -> void:
	hovering = false
	if state == CardAnimationMath.FLIP or state == CardAnimationMath.LAND:
		return
	state = CardAnimationMath.IDLE
	_tween_prop("hover_p", 0.0, config.hover_out_dur, Tween.TRANS_CUBIC, Tween.EASE_OUT)

func click() -> void:
	if state != CardAnimationMath.HOVER:
		return
	state = CardAnimationMath.PRESS
	var tw := _tween_prop("press_p", 1.0, config.press_dur, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	tw.finished.connect(_on_press_done)

func _on_press_done() -> void:
	press_p = 0.0
	state = CardAnimationMath.FLIP
	var tw := _tween_prop("flip_p", 1.0, config.flip_dur, Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
	tw.finished.connect(_on_flip_done)

func _on_flip_done() -> void:
	flip_turns += 1
	flip_p = 0.0
	state = CardAnimationMath.LAND
	var tw := _tween_prop("land_p", 1.0, config.land_dur, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.finished.connect(_on_land_done)

func _on_land_done() -> void:
	land_p = 0.0
	state = CardAnimationMath.HOVER if hovering else CardAnimationMath.IDLE

func reset() -> void:
	for k in _tweens:
		var tw: Tween = _tweens[k]
		if tw != null and tw.is_valid():
			tw.kill()
	state = CardAnimationMath.IDLE
	hovering = false
	hover_p = 0.0
	press_p = 0.0
	flip_p = 0.0
	land_p = 0.0
	flip_turns = 0
	showing_back = false
	_idle_time = 0.0
	if body != null:
		body.show_back(false)
	_apply()
