class_name RobotAvatar
extends Node3D
## Robot 角色包装（每个座位一个）。实例化 Blender Robot 模型、剔除其自带
## Camera/Light、摆出待机手臂姿势，并暴露 overlay 染色 + ARKit 眼球追踪。
## 纯客户端展示层：不涉及规则/协议/快照，也不参与拾取（不挂碰撞）。

const ROBOT_SCENE := preload("res://assets/characters/source/Robot.blend")
const STRIP_NODES := ["Camera", "Light"]

# 模型空间尺度/锚点（见 docs/3D角色与场景说明.md）
const MODEL_EYE := Vector3(0.0, 2.038, 0.215)  # 眼球中心（+Z = 脸朝向）
const MODEL_HEAD_TOP := 2.2                     # 头顶高度（模型空间）
const SCALE := 1.65                             # 整体缩放（原 1.1 × 1.5；脚在原点，越大越高、过高会出画）

# 待机姿势 / 眼球追踪参数
const ARM_DOWN_DEG := 82.0                      # 上臂由 T-pose 放下角度
const EYE_YAW_MAX_DEG := 32.0                   # 水平满权重对应偏航角
const EYE_PITCH_MAX_DEG := 18.0                 # 垂直满权重对应俯仰角
const EYE_GAIN := 1.0
const HEAD_YAW_MAX_DEG := 30.0                  # Head Tracking 水平上限（头先吸收，眼睛做剩余）
const HEAD_PITCH_MAX_DEG := 20.0                # Head Tracking 垂直上限
const BLINK_PERIOD := 4.2                       # 自动眨眼周期（秒）
const BLINK_DURATION := 0.14                    # 单次眨眼时长（秒）

# 机体外观（覆盖模型自带 Body 材质）
const BODY_COLOR := Color("496AFE")             # 深蓝
const BODY_METALLIC := 0.7
const BODY_ROUGHNESS := 0.35
const BODY_SPECULAR := 0.5

var _built := false
var _robot: Node3D
var _skeleton: Skeleton3D
var _head_idx := -1
var _eyes: MeshInstance3D
var _eye_index := {}          # blendshape name -> index
var _jaw_targets: Array = []  # [[MeshInstance3D, jawOpen_idx], ...]（嘴在下巴网格，不在 Eyes）
var _eye_zoom := false
var _body_color: Color = BODY_COLOR
var _body_mat: StandardMaterial3D = null
var _talking := false
var _talk_t := 0.0
var _blink_t := 0.0

func _ready() -> void:
	_build()

func _process(delta: float) -> void:
	if _talking:
		_talk_t += delta
		_set_jaw(RobotAvatarMath.talk_jaw(_talk_t))
	if _eyes == null:
		return
	_blink_t = fmod(_blink_t + delta, BLINK_PERIOD)
	var p := 0.0
	if _blink_t < BLINK_DURATION:
		p = sin(PI * _blink_t / BLINK_DURATION)
	var w := RobotAvatarMath.blink_weights(p)
	for name in w.keys():
		_set_blend(str(name), float(w[name]))

## 构建（幂等）：实例化模型 → 剔除 Camera/Light → 缓存骨架/眼球/形状键 → 待机姿势。
func _build() -> void:
	if _built:
		return
	_built = true
	scale = Vector3.ONE * SCALE
	_robot = ROBOT_SCENE.instantiate()
	_robot.name = "Robot"
	# 未入树时剔除自带相机/灯光，避免成为当前相机或多打一盏灯。
	for n in STRIP_NODES:
		var node := _robot.get_node_or_null(n)
		if node != null:
			_robot.remove_child(node)
			node.free()
	add_child(_robot)
	_skeleton = _robot.get_node_or_null("Armature/Skeleton3D")
	_eyes = _robot.get_node_or_null("Armature/Skeleton3D/Eyes")
	if _skeleton != null:
		_head_idx = _skeleton.find_bone("Head")
	if _eyes != null and _eyes.mesh != null:
		for i in _eyes.mesh.get_blend_shape_count():
			_eye_index[_eyes.mesh.get_blend_shape_name(i)] = i
	# 嘴（jawOpen）在下巴网格：收集所有含该形状的网格
	for mesh_name in ["Face", "Body", "Arms", "Legs", "Eyes"]:
		var mi := _robot.get_node_or_null("Armature/Skeleton3D/" + mesh_name)
		if mi != null and mi.mesh != null:
			var ji := -1
			for k in mi.mesh.get_blend_shape_count():
				if mi.mesh.get_blend_shape_name(k) == "jawOpen":
					ji = k
					break
			if ji >= 0:
				_jaw_targets.append([mi, ji])
	_apply_idle_pose()
	_apply_body_color()

## 机体外观：逐实例覆盖 Body 表面材质（不改共享网格/材质），支持每个玩家不同颜色。
## Arms/Body/Legs 单面；Face 面 0 = Body、面 1 = Mouth（保留）。
func _apply_body_color() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = _body_color
	m.metallic = BODY_METALLIC
	m.roughness = BODY_ROUGHNESS
	m.metallic_specular = BODY_SPECULAR
	_body_mat = m
	for nm in ["Arms", "Body", "Legs"]:
		var mi = _robot.get_node_or_null("Armature/Skeleton3D/" + nm)
		if mi != null:
			mi.set_surface_override_material(0, m)
	var face = _robot.get_node_or_null("Armature/Skeleton3D/Face")
	if face != null:
		face.set_surface_override_material(0, m)

## 设置该玩家机体颜色（进游戏随机分配；默认 `BODY_COLOR`）。
func set_body_color(color: Color) -> void:
	_build()
	if color.is_equal_approx(_body_color) and _body_mat != null:
		return
	_body_color = color
	_apply_body_color()

## 放大时眼睛采用「小眼睛」（Tiny_Eyes 形状键）；松开归零。
func set_eye_zoom(on: bool) -> void:
	_build()
	if _eye_zoom == on:
		return
	_eye_zoom = on
	_set_blend("Tiny_Eyes", 1.0 if on else 0.0)

## 说话：驱动下巴 jawOpen（多正弦开合，见 RobotAvatarMath.talk_jaw）；关闭归零。
func set_talking(on: bool) -> void:
	_build()
	if _talking == on:
		return
	_talking = on
	if on:
		_talk_t = 0.0
	else:
		_set_jaw(0.0)

## 当前 jawOpen 值（测试用）。
func jaw_value() -> float:
	if _jaw_targets.is_empty():
		return 0.0
	return (_jaw_targets[0][0] as MeshInstance3D).get_blend_shape_value(int(_jaw_targets[0][1]))

func _set_jaw(v: float) -> void:
	for e in _jaw_targets:
		(e[0] as MeshInstance3D).set_blend_shape_value(int(e[1]), v)

## 待机手臂姿势：绕世界 Z 轴把 T-pose 上臂放下（左侧 -，右侧 +）。
## 用 global pose override 直接给出目标全局姿势，子骨骼（小臂/手）随之联动。
func _apply_idle_pose() -> void:
	if _skeleton == null:
		return
	for bone_name in ["upper_arrm.L", "upper_arm.R"]:
		var i := _skeleton.find_bone(bone_name)
		if i < 0:
			continue
		var rest: Transform3D = _skeleton.get_bone_global_rest(i)
		var sign := -1.0 if bone_name.ends_with(".L") else 1.0
		var rot := Basis(Vector3(0, 0, 1), deg_to_rad(ARM_DOWN_DEG * sign))
		_skeleton.set_bone_global_pose_override(i, Transform3D(rot * rest.basis, rest.origin), 1.0, true)

## 染色/状态 overlay（出局/离线变暗、当前回合金色）：作用于模型全部 MeshInstance3D。
## 传 null 清除。与 2D/3D 既有 material_overlay 策略一致。
func set_overlay(mat: StandardMaterial3D) -> void:
	_build()
	var meshes: Array = []
	_collect_meshes(_robot, meshes)
	for m in meshes:
		(m as MeshInstance3D).material_overlay = mat

## ===== VRM 1.0 风格 LookAt =====
## 本模型非 VRM（无 eye 骨骼 / 无 VRMC_vrm.lookAt 配置），眼睛走 ARKit 形状键，
## 对应 VRM lookAt 的 `type:"expression"` 路径。参照 `VRMC_vrm.lookAt`：
##   - LookAt space = Head 骨骼（rest 旋转取逆）→ 以头为参照，头的转动自然继承、不叠加到眼；
##   - origin ≈ offsetFromHeadBone（此处用两眼中心 `MODEL_EYE`）；
##   - RangeMap：inputMax = `EYE_YAW_MAX_DEG` / `EYE_PITCH_MAX_DEG`，outputScale = 1。

## 世界坐标注视点 → Head Tracking（头在限定范围内跟随）+ 眼残余 LookAt。
## 头先吸收（clamp 到 `HEAD_YAW/PITCH_MAX`），眼睛只做相对头的剩余部分（VRM：head/eye 独立）。
func set_gaze_target_world(target_world: Vector3) -> void:
	_build()
	if _skeleton == null:
		return
	var sk := _skeleton.global_transform
	# 用 rest 眼位算方向（避免与当前头姿势形成反馈）。
	var d_model := sk.basis.inverse() * (target_world - sk * MODEL_EYE)
	_apply_head_tracking(d_model)
	if _eyes != null:
		_apply_look_dir(_lookat_basis_model().inverse() * d_model)

## 头跟随注视点（限定 yaw/pitch），仅动 Head 骨骼；眼睛随后做相对头的残余。
func _apply_head_tracking(d_model: Vector3) -> void:
	if _skeleton == null or _head_idx < 0 or d_model.length_squared() < 0.000001:
		return
	var d := d_model.normalized()
	var yaw := clampf(atan2(d.x, d.z), deg_to_rad(-HEAD_YAW_MAX_DEG), deg_to_rad(HEAD_YAW_MAX_DEG))
	var horiz := sqrt(d.x * d.x + d.z * d.z)
	var pitch := clampf(atan2(d.y, horiz), deg_to_rad(-HEAD_PITCH_MAX_DEG), deg_to_rad(HEAD_PITCH_MAX_DEG))
	# 模型轴：左=+X（yaw 绕 +Y，向左为正）；上=+Y（pitch 绕右轴 -X，向上为正）。
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3(-1, 0, 0), pitch)
	var rest: Transform3D = _skeleton.get_bone_global_rest(_head_idx)
	_skeleton.set_bone_global_pose_override(_head_idx, Transform3D(rot * rest.basis, rest.origin), 1.0, true)

## 沿世界方向看（仅眼，不动头；低层 API）。
func set_eye_direction(dir_world: Vector3) -> void:
	_build()
	if _eyes == null or _skeleton == null:
		return
	var d_model := _skeleton.global_transform.basis.inverse() * dir_world
	_apply_look_dir(_lookat_basis_model().inverse() * d_model)

## 看向世界点（仅眼，不动头；兼容旧调用名）。
func set_eye_look(target_world: Vector3) -> void:
	_build()
	if _eyes == null or _skeleton == null:
		return
	var sk := _skeleton.global_transform
	var d_model := sk.basis.inverse() * (target_world - sk * MODEL_EYE)
	_apply_look_dir(_lookat_basis_model().inverse() * d_model)

## LookAt space 方向基底（模型空间）：Head 当前姿势 × Head rest 旋转的逆。
## 头未转动时为单位阵（+Z = 模型前向）；头转动时随头旋转 → 眼睛相对头补偿。
func _lookat_basis_model() -> Basis:
	if _skeleton == null or _head_idx < 0:
		return Basis.IDENTITY
	var pose: Transform3D = _skeleton.get_bone_global_pose(_head_idx)
	var rest: Transform3D = _skeleton.get_bone_global_rest(_head_idx)
	return (pose.basis * rest.basis.inverse()).orthonormalized()

## LookAt origin（模型空间）：两眼中心随 Head 姿势移动（rest 时 = MODEL_EYE）。
func _eye_origin_model() -> Vector3:
	if _skeleton == null or _head_idx < 0:
		return MODEL_EYE
	var pose: Transform3D = _skeleton.get_bone_global_pose(_head_idx)
	var rest: Transform3D = _skeleton.get_bone_global_rest(_head_idx)
	return pose * (rest.affine_inverse() * MODEL_EYE)

func _apply_look_dir(dir_lookat: Vector3) -> void:
	var w := RobotAvatarMath.eye_look_weights(dir_lookat, EYE_YAW_MAX_DEG, EYE_PITCH_MAX_DEG, EYE_GAIN)
	for name in w.keys():
		_set_blend(str(name), float(w[name]))

## 眼球回到正前 + 头回正（无目标时）。
func reset_eyes() -> void:
	_build()
	for name in RobotAvatarMath.LOOK_NAMES:
		_set_blend(name, 0.0)
	if _skeleton != null and _head_idx >= 0:
		var rest: Transform3D = _skeleton.get_bone_global_rest(_head_idx)
		_skeleton.set_bone_global_pose_override(_head_idx, rest, 1.0, true)

## 当前某形状键权重（测试用）。
func blend_value(name: String) -> float:
	if _eyes == null:
		return 0.0
	var idx = _eye_index.get(name, -1)
	if idx < 0:
		return 0.0
	return _eyes.get_blend_shape_value(int(idx))

func eye_world_position() -> Vector3:
	_build()
	if _skeleton == null:
		return global_transform * MODEL_EYE
	return _skeleton.global_transform * _eye_origin_model()

func _set_blend(name: String, value: float) -> void:
	var idx = _eye_index.get(name, -1)
	if idx >= 0:
		_eyes.set_blend_shape_value(int(idx), value)

func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)
