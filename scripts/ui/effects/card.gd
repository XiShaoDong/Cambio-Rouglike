class_name KongCard
extends Button
## 场景化卡牌节点（参考 balatro 动效）：
##  - hover 放大 + 3D 倾斜（fake_3D shader）
##  - 弹簧回弹、拖拽跟随
##  - 发牌动画（draw_in）
## 正面：左上点数 / 中央花色 / 右下分数；背面：白边深底。

const CARD_W := 57.0
const CARD_H := 89.0

@export var angle_max := 12.0
@export var spring := 150.0
@export var damp := 10.0
@export var velocity_multiplier := 2.0
@export var show_shadow := true

var card_data: Dictionary = {}
var is_face_up := false

var displacement := 0.0
var oscillator_velocity := 0.0
var tween_hover: Tween
var tween_rot: Tween
var last_mouse_pos := Vector2.ZERO
var following_mouse := false
var last_pos := Vector2.ZERO
var velocity := Vector2.ZERO

@onready var shadow: TextureRect = $Shadow
@onready var card_texture: TextureRect = $CardTexture
@onready var back_panel: PanelContainer = $BackPanel
@onready var rank_label: Label = $CardTexture/Face/RankLabel
@onready var suit_label: Label = $CardTexture/Face/SuitLabel
@onready var value_label: Label = $CardTexture/Face/ValueLabel

var slot_index := -1

func _ready() -> void:
	pivot_offset = size / 2.0
	angle_max = deg_to_rad(angle_max)
	apply_card()
	if _pending_highlight:
		highlight(true)

func _process(delta: float) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	_rotate_velocity(delta)
	_follow_mouse(delta)
	_handle_shadow(delta)

func setup(data: Dictionary, face_up: bool, index: int, size_override := Vector2.ZERO) -> void:
	card_data = data
	is_face_up = face_up
	slot_index = index
	if size_override != Vector2.ZERO:
		custom_minimum_size = size_override
		pivot_offset = size_override / 2.0
	if is_node_ready():
		apply_card()

func apply_card() -> void:
	if card_data.is_empty():
		# 背面
		card_texture.visible = false
		back_panel.visible = true
		var style := StyleBoxFlat.new()
		style.bg_color = UITheme.color("card_back_bg")
		style.border_color = UITheme.color("card_back_border")
		style.set_border_width_all(clampi(int(size.x * 0.05), 2, 5))
		style.set_corner_radius_all(8)
		back_panel.add_theme_stylebox_override("panel", style)
		return
	# 正面
	card_texture.visible = true
	back_panel.visible = false
	var is_red := str(card_data.get("suit", "")) in ["♥", "♦"]
	var suit_color: Color = UITheme.color("card_rank_red") if is_red else UITheme.color("card_rank_black")
	rank_label.text = str(card_data.get("rank", "?"))
	rank_label.add_theme_color_override("font_color", suit_color)
	suit_label.text = str(card_data.get("suit", ""))
	suit_label.add_theme_color_override("font_color", suit_color)
	value_label.text = str(card_data.get("value", 0))
	value_label.add_theme_color_override("font_color", UITheme.color("card_value"))
	# 阴影
	shadow.visible = show_shadow

func highlight(on: bool) -> void:
	if not is_inside_tree():
		_pending_highlight = on
		return
	_pending_highlight = on
	var glow := UITheme.color("highlight_glow")
	if on:
		modulate = Color(1.35, 1.25, 1.0, 1.0)
		if is_instance_valid(shadow):
			shadow.self_modulate = glow
		return
	modulate = Color.WHITE
	if is_instance_valid(shadow):
		shadow.self_modulate = Color(1, 1, 1, 0.168627)

var _pending_highlight := false

func draw_in(from_pos: Vector2, delay: float, target_pos: Vector2, rot := 0.0) -> void:
	global_position = from_pos
	rotation = rot
	modulate.a = 0.0
	await get_tree().create_timer(delay).timeout
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", target_pos, 0.3)
	tween.tween_property(self, "rotation", 0.0, 0.3)
	tween.tween_property(self, "modulate:a", 1.0, 0.2)

func _rotate_velocity(delta: float) -> void:
	if not following_mouse:
		return
	velocity = (position - last_pos) / delta
	last_pos = position
	oscillator_velocity += velocity.normalized().x * velocity_multiplier
	var force := -spring * displacement - damp * oscillator_velocity
	oscillator_velocity += force * delta
	displacement += oscillator_velocity * delta
	rotation = displacement

func _handle_shadow(_delta: float) -> void:
	if not show_shadow or not is_instance_valid(shadow):
		return
	var center: Vector2 = get_viewport_rect().size / 2.0
	var distance: float = global_position.x - center.x
	shadow.position.x = lerp(0.0, -sign(distance) * 30.0, abs(distance / center.x))

func _follow_mouse(_delta: float) -> void:
	if not following_mouse:
		return
	var mouse_pos: Vector2 = get_global_mouse_position()
	global_position = mouse_pos - (size / 2.0)

func _handle_mouse_click(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.is_pressed():
		following_mouse = true
	else:
		following_mouse = false
		if tween_hover and tween_hover.is_running():
			tween_hover.kill()
		tween_hover = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween_hover.tween_property(self, "rotation", 0.0, 0.3)

func _alive() -> bool:
	return is_inside_tree() and not is_queued_for_deletion()

func _on_gui_input(event: InputEvent) -> void:
	if not _alive():
		return
	_handle_mouse_click(event)
	if following_mouse:
		return
	if not event is InputEventMouseMotion:
		return
	var mouse_pos: Vector2 = get_local_mouse_position()
	var lerp_val_x := remap(mouse_pos.x, 0.0, size.x, 0.0, 1.0)
	var lerp_val_y := remap(mouse_pos.y, 0.0, size.y, 0.0, 1.0)
	var rot_x := rad_to_deg(lerp_angle(-angle_max, angle_max, lerp_val_x))
	var rot_y := rad_to_deg(lerp_angle(angle_max, -angle_max, lerp_val_y))
	if not is_instance_valid(card_texture):
		return
	var shader_material := card_texture.material as ShaderMaterial
	if shader_material:
		shader_material.set_shader_parameter("x_rot", rot_y)
		shader_material.set_shader_parameter("y_rot", rot_x)

func _on_mouse_entered() -> void:
	if not _alive():
		return
	if tween_hover and tween_hover.is_running():
		tween_hover.kill()
	tween_hover = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween_hover.tween_property(self, "scale", Vector2(1.2, 1.2), 0.5)

func _on_mouse_exited() -> void:
	if not _alive():
		return
	if tween_rot and tween_rot.is_running():
		tween_rot.kill()
	tween_rot = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_parallel(true)
	if not is_instance_valid(card_texture):
		return
	var shader_material := card_texture.material as ShaderMaterial
	if shader_material:
		tween_rot.tween_property(shader_material, "shader_parameter/x_rot", 0.0, 0.5)
		tween_rot.tween_property(shader_material, "shader_parameter/y_rot", 0.0, 0.5)
	if tween_hover and tween_hover.is_running():
		tween_hover.kill()
	tween_hover = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween_hover.tween_property(self, "scale", Vector2.ONE, 0.55)
