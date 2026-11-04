class_name CardTiltView
extends TextureRect
## 2D 伪 3D 卡牌视图：鼠标在卡面内移动 → 透视倾斜 + 打光。
## 透视由 card_tilt.gdshader 在片元里用逆单应完成；本类只负责角度/阻尼/uniform。
## 画布尺寸应为 卡面尺寸 * pad（静止时卡面占画布的 1/pad）。

const SHADER_PATH := "res://assets/shaders/card_tilt.gdshader"
## 项目内预设：沙盒保存到这里，实际游戏里 CardTiltView / CardView 启动时自动读取。
const PRESET_PATH := CardTiltPreset.PROJECT_PATH
## 导出包内 res:// 只读时的兜底位置。
const USER_PRESET_PATH := CardTiltPreset.USER_PATH

@export_range(1.0, 3.0, 0.01) var card_aspect := 1.4
@export_range(1.0, 3.0, 0.01) var pad := 1.8
@export_range(0.0, 45.0, 0.5) var max_tilt_deg := 14.0
@export_range(1.0, 12.0, 0.1) var cam_dist := 3.0
@export_range(0.0, 40.0, 0.5) var response := 9.0

@export_range(0.0, 2.0, 0.01) var spec_strength := 0.55
@export_range(0.0, 2.0, 0.01) var gloss_strength := 0.35
@export_range(0.0, 2.0, 0.01) var rim_strength := 0.30
@export_range(0.0, 1.0, 0.01) var shadow_strength := 0.35
@export_range(0.0, 2.0, 0.01) var base_gain := 1.0
@export var gloss_tint := Color(0.62, 0.78, 1.0, 1.0)

@export var follow_mouse := true
@export var light_dir := CardTiltMath.LIGHT_DIR

signal tilt_changed(yaw_deg: float, pitch_deg: float)

var yaw_deg := 0.0
var pitch_deg := 0.0

var persist := true

var _mat: ShaderMaterial
var _target_norm := Vector2.ZERO
var _external := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	material = _mat
	if persist:
		load_preset()
	_apply_uniforms()


func _process(delta: float) -> void:
	if follow_mouse and not _external:
		_update_target_from_mouse()
	var target := CardTiltMath.target_angles(_target_norm, max_tilt_deg)
	var smoothed := CardTiltMath.smooth_angles(Vector2(yaw_deg, pitch_deg), target, response, delta)
	yaw_deg = smoothed.x
	pitch_deg = smoothed.y
	_apply_uniforms()
	tilt_changed.emit(yaw_deg, pitch_deg)


## 外部驱动（例如对局里用卡牌 hover 位置而不是系统鼠标）。
func set_pointer_normalized(norm: Vector2) -> void:
	_external = true
	_target_norm = Vector2(clampf(norm.x, -1.0, 1.0), clampf(norm.y, -1.0, 1.0))


func reset_tilt() -> void:
	_external = true
	_target_norm = Vector2.ZERO


func set_material_texture(tex: Texture2D) -> void:
	texture = tex


func _update_target_from_mouse() -> void:
	var rect := get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_target_norm = Vector2.ZERO
		return
	var mouse := get_global_mouse_position()
	var local := (mouse - rect.get_center()) / (rect.size * 0.5)
	var card_half := 1.0 / maxf(pad, 0.001)
	if absf(local.x) <= card_half + 0.02 and absf(local.y) <= card_half + 0.02:
		_target_norm = Vector2(clampf(local.x * pad, -1.0, 1.0), clampf(local.y * pad, -1.0, 1.0))
	else:
		_target_norm = Vector2.ZERO


func params() -> Dictionary:
	return {
		"card_aspect": card_aspect,
		"pad": pad,
		"max_tilt_deg": max_tilt_deg,
		"cam_dist": cam_dist,
		"response": response,
		"spec_strength": spec_strength,
		"gloss_strength": gloss_strength,
		"rim_strength": rim_strength,
		"shadow_strength": shadow_strength,
		"base_gain": base_gain,
		"gloss_tint": gloss_tint,
		"light_dir": light_dir,
	}


func set_params(values: Dictionary) -> void:
	card_aspect = float(values.get("card_aspect", card_aspect))
	pad = float(values.get("pad", pad))
	max_tilt_deg = float(values.get("max_tilt_deg", max_tilt_deg))
	cam_dist = float(values.get("cam_dist", cam_dist))
	response = float(values.get("response", response))
	spec_strength = float(values.get("spec_strength", spec_strength))
	gloss_strength = float(values.get("gloss_strength", gloss_strength))
	rim_strength = float(values.get("rim_strength", rim_strength))
	shadow_strength = float(values.get("shadow_strength", shadow_strength))
	base_gain = float(values.get("base_gain", base_gain))
	gloss_tint = values.get("gloss_tint", gloss_tint)
	light_dir = values.get("light_dir", light_dir)


## 保存当前参数。path 为空时优先写项目内预设，失败则退回 user://。
## 返回实际写入的路径（失败返回空串）。
func save_preset(path: String = "") -> String:
	return CardTiltPreset.save_params(params(), path)


## 读取预设。path 为空时先读项目内预设，再读 user:// 兜底。
func load_preset(path: String = "") -> bool:
	var values := CardTiltPreset.load_params(path)
	if values.is_empty():
		return false
	set_params(values)
	return true


func _apply_uniforms() -> void:
	apply_uniforms(_mat, params(), yaw_deg, pitch_deg)


## 把一组参数与倾斜角写进任意卡牌材质（CardTiltView 与 CardView 共用）。
static func apply_uniforms(mat: ShaderMaterial, values: Dictionary, p_yaw: float, p_pitch: float) -> void:
	if mat == null:
		return
	var aspect := float(values.get("card_aspect", 1.4))
	var p_pad := maxf(float(values.get("pad", 1.8)), 0.001)
	var cam := float(values.get("cam_dist", 3.0))
	var inv := CardTiltMath.inverse_uv_map(aspect, p_yaw, p_pitch, cam, p_pad)
	mat.set_shader_parameter("inv_row0", Vector3(inv[0], inv[1], inv[2]))
	mat.set_shader_parameter("inv_row1", Vector3(inv[3], inv[4], inv[5]))
	mat.set_shader_parameter("inv_row2", Vector3(inv[6], inv[7], inv[8]))
	mat.set_shader_parameter("card_normal", CardTiltMath.surface_normal(p_yaw, p_pitch))
	mat.set_shader_parameter("light_dir", (values.get("light_dir", CardTiltMath.LIGHT_DIR) as Vector3).normalized())
	mat.set_shader_parameter("tilt_deg", Vector3(p_yaw, p_pitch, 0.0))
	mat.set_shader_parameter("spec_strength", float(values.get("spec_strength", 0.55)))
	mat.set_shader_parameter("gloss_strength", float(values.get("gloss_strength", 0.35)))
	mat.set_shader_parameter("rim_strength", float(values.get("rim_strength", 0.30)))
	mat.set_shader_parameter("shadow_strength", float(values.get("shadow_strength", 0.35)))
	mat.set_shader_parameter("base_gain", float(values.get("base_gain", 1.0)))
	mat.set_shader_parameter("gloss_tint", values.get("gloss_tint", Color(0.62, 0.78, 1.0, 1.0)))
	var denom := maxf(float(values.get("max_tilt_deg", 14.0)), 1.0)
	mat.set_shader_parameter("shadow_offset", Vector2(0.02, 0.018) + Vector2(-p_yaw, -p_pitch) / denom * 0.012)
