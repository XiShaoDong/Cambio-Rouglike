class_name NoseAvatar
extends Node3D
## 单条程序化鼻子：底在原点的圆锥沿本地 +Z 生长，按固定时长伸缩。
## 纯客户端展示层，无碰撞、不参与拾取。长度单位为"本节点所在空间"的单位。

enum { IDLE, EXTENDING, EXTENDED, RETRACTING }

const NOSE_BASE_RADIUS := 0.05    # 锥底半径
const NOSE_TIP_RADIUS := 0.015    # 锥尖半径
const NOSE_DURATION := 0.35       # 伸出/缩回固定时长（秒）→ 速度随距离
const NOSE_SEGMENTS := 16
const NOSE_COLOR := Color("F2C14E")

var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _state := IDLE
var _from_len := 0.0
var _target_len := 0.0
var _len := 0.0
var _t := 0.0

func _ready() -> void:
	_build()
	_apply_len()

func _build() -> void:
	if _mesh != null:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = NOSE_TIP_RADIUS
	cyl.bottom_radius = NOSE_BASE_RADIUS
	cyl.height = 1.0
	cyl.radial_segments = NOSE_SEGMENTS
	cyl.rings = 1
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = NOSE_COLOR
	_mat.emission_enabled = true
	_mat.emission = NOSE_COLOR
	_mat.emission_energy_multiplier = 0.25
	_mat.metallic = 0.3
	_mat.roughness = 0.5
	_mesh = MeshInstance3D.new()
	_mesh.name = "NoseMesh"
	_mesh.mesh = cyl
	_mesh.material_override = _mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 圆柱沿 +Y 居中 → 绕 X 转 +90° 使 +Y=+Z（锥尖朝 +Z）；长度经 scale.y 拉伸、position.z 把底面挪到原点。
	_mesh.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3.ZERO)
	add_child(_mesh)

## 目标长度：>0 伸出，<=0 缩回。IDLE/RETRACTING 收到 >0 开始伸出；EXTENDING/EXTENDED 收到 <=0 开始缩回。
## 已伸出（EXTENDED）时若目标变化则**直接对齐**新长度（跟随头部/目标时让鼻尖保持在目标点上）。
func set_target(len: float) -> void:
	_build()
	var t := maxf(len, 0.0)
	if t > 0.0:
		if _state == IDLE or _state == RETRACTING:
			_state = EXTENDING
			_from_len = _len
			_target_len = t
			_t = 0.0
		elif _state == EXTENDED:
			_target_len = t
			_len = t
			_apply_len()
		else:  # EXTENDING：更新目标，继续插值
			_target_len = t
	else:
		if _state == EXTENDING or _state == EXTENDED:
			_state = RETRACTING
			_from_len = _len
			_target_len = 0.0
			_t = 0.0

func _process(delta: float) -> void:
	if _state == IDLE:
		return
	_t += delta
	var p := clampf(_t / NOSE_DURATION, 0.0, 1.0)
	_len = lerpf(_from_len, _target_len, p)
	if p >= 1.0:
		_len = _target_len
		_state = EXTENDED if _target_len > 0.0 else IDLE
	_apply_len()

func _apply_len() -> void:
	if _mesh == null:
		return
	_mesh.visible = _len > 0.0001
	_mesh.scale = Vector3(1.0, maxf(_len, 0.0001), 1.0)
	_mesh.position = Vector3(0.0, 0.0, _len * 0.5)

func length() -> float:
	return _len

func is_active() -> bool:
	return _len > 0.0001 or _state != IDLE

func state_name() -> String:
	match _state:
		EXTENDING: return "EXTENDING"
		EXTENDED: return "EXTENDED"
		RETRACTING: return "RETRACTING"
		_: return "IDLE"

func set_color(c: Color) -> void:
	_build()
	_mat.albedo_color = c
	_mat.emission = c
