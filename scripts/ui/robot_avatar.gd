class_name RobotAvatar
extends Node3D
## Robot 角色包装（每个座位一个）。实例化 Blender Robot 模型、剔除其自带
## Camera/Light、摆出待机手臂姿势，并暴露 overlay 染色 + ARKit 眼球追踪。
## 纯客户端展示层：不涉及规则/协议/快照，也不参与拾取（不挂碰撞）。

const ROBOT_SCENE := preload("res://assets/characters/source/Robot.blend")
const BODY_SHADER := preload("res://assets/shaders/avatar_body.gdshader")
const CROWN_SCENE := preload("res://assets/3Dmodels/champion_crown.glb")
const CROWN_SHADER := preload("res://assets/shaders/crown_gold.gdshader")
const STRIP_NODES := ["Camera", "Light"]

# 模型空间尺度/锚点（见 docs/3D角色与场景说明.md）
const MODEL_EYE := Vector3(0.0, 2.038, 0.215)  # 眼球中心（+Z = 脸朝向）
const MODEL_HEAD_TOP := 2.2                     # 头顶高度（模型空间）
const NOSE_BASE_MODEL := Vector3(0.0, 1.80, 0.34)   # 鼻根回退值（眼下方/脸前）；实际由 Eyes 网格 AABB 推出
const NoseAvatarScript := preload("res://scripts/ui/nose_avatar.gd")
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
# 右手抬臂（看道具牌）：上臂朝前上方、小臂折起；模型空间 +Z 为脸朝向、右手在 -X。
const ARM_UP_UPPER_DIR := Vector3(-0.30, -0.92, 0.25)
const ARM_UP_FORE_DIR := Vector3(-0.05, -0.85, 0.52)
const ARM_UP_SPEED := 5.5                       # 抬/落速度（每秒进度）

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
var _nose = null                # NoseAvatar（挂在 Skeleton3D 下，随头）
var _hand = null                # AvatarHand（挂在 hand.R 骨骼，随右臂抬/弯）
var _nose_base_model: Vector3 = NOSE_BASE_MODEL  # 鼻根（模型/骨架空间，由 Eyes AABB 推出）
var _nose_target_world: Vector3 = Vector3.ZERO   # 鼻子目标世界坐标（ZERO=未伸出）
var _eye_index := {}          # blendshape name -> index
var _jaw_targets: Array = []  # [[MeshInstance3D, jawOpen_idx], ...]（嘴在下巴网格，不在 Eyes）
var _eye_zoom := false
var _body_color: Color = BODY_COLOR
var _body_mat: ShaderMaterial = null
var _talking := false
var _talk_t := 0.0
var _blink_t := 0.0
var _gaze_frozen := false     # 离线/出局：头与眼回正，不再跟随注视目标
var _halo: MeshInstance3D = null
var _halo_t := 0.0
var _halo_a := 0.0
var _halo_target_a := 0.0
var _crown: Node3D = null
var _crown_on := false
var _crown_t := 0.0
var _arm_up := false
var _arm_p := 0.0

# 光环（离线/出局头顶 😇 式金环）：大小/位置在“状态面板（♥$卡）之下、头上一点”
const HALO_Y_MODEL := 2.32     # 头顶(2.2) 上一点，低于头顶状态面板
const HALO_COLOR := Color("FFE9A8")
const CROWN_Y_MODEL := 2.20    # 皇冠底座套在头顶（上一局冠军）
const CROWN_HALO_LIFT := 0.62  # 有皇冠时把光环抬高，避免与冠尖相交

func _ready() -> void:
	_build()

func _process(delta: float) -> void:
	_update_arm(delta)
	_update_nose()
	if _talking:
		_talk_t += delta
		_set_jaw(RobotAvatarMath.talk_jaw(_talk_t))
	if _halo != null and _halo.visible:
		_halo_t += delta
		# 淡入 + 悬浮呼吸 + 缓慢旋转
		_halo_a = move_toward(_halo_a, _halo_target_a, delta * 1.6)
		(_halo.material_override as StandardMaterial3D).albedo_color.a = _halo_a
		if _halo_a <= 0.0 and _halo_target_a <= 0.0:
			_halo.visible = false
		var bob := sin(_halo_t * 1.6) * 0.02
		var lift := CROWN_HALO_LIFT if (_crown != null and _crown.visible) else 0.0
		_halo.position = Vector3(0.0, HALO_Y_MODEL + lift + bob, 0.0)
		_halo.rotation.y += delta * 0.7
	if _crown != null and _crown.visible:
		_crown_t += delta
		_crown.position.y = CROWN_Y_MODEL + sin(_crown_t * 1.8) * 0.025
		_crown.rotation.y += delta * 0.6
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
		# 鼻根：由眼球网格 AABB 推出——两眼中间、眼球下方、靠近脸前（+Z 为脸朝向）。
		var a: AABB = _eyes.mesh.get_aabb()
		_nose_base_model = Vector3(0.0, a.position.y + a.size.y * 0.20, a.position.z + a.size.z * 0.70)
	# 嘴（jawOpen）驱动 Face + Eyes：Eyes 的 jawOpen 让眼睛跟着面部一起动（保留原有观感）。
	# Robot.blend 的 jawOpen 形状被导出到了整身网格；Arms/Legs/Body 不再驱动，
	# 否则说话时胳膊和腿会被这个表情形变带着摆动（夸张）。
	for mesh_name in ["Face", "Eyes"]:
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
	_rerig_right_elbow()
	_build_hand()
	if _skeleton != null:
		_nose = NoseAvatarScript.new()
		_nose.name = "Nose"
		_skeleton.add_child(_nose)
		_nose.set_color(_body_color)

## 右手低模：挂到 hand.R 骨骼（无蒙皮权重也能跟随小臂/手腕），共用机体材质。
func _build_hand() -> void:
	if _skeleton == null or _hand != null:
		return
	if _skeleton.find_bone("hand.R") < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "HandR"
	_skeleton.add_child(attach)
	attach.bone_name = "hand.R"
	_hand = AvatarHand.new()
	_hand.name = "RightHand"
	attach.add_child(_hand)
	_hand.set_material(_body_mat)


## 原模型的小臂/手没有蒙皮权重（整条手臂刚性绑在上臂），无法弯肘。
## 在实例网格上把右臂远端顶点的权重从上臂渐变到 lower_arm.R，得到可弯折的肘部。
func _rerig_right_elbow() -> void:
	var arms := _robot.get_node_or_null("Armature/Skeleton3D/Arms") as MeshInstance3D
	if arms == null or arms.mesh == null or arms.skin == null:
		return
	var skin := arms.skin
	var bind_upper := -1
	var bind_lower := -1
	for bi in skin.get_bind_count():
		match skin.get_bind_name(bi):
			"upper_arm.R": bind_upper = bi
			"lower_arm.R": bind_lower = bi
	if bind_upper < 0 or bind_lower < 0:
		return
	var mesh := arms.mesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	for v in verts.size():
		var x: float = verts[v].x
		if x > -0.74:
			continue
		var t := clampf((-x - 0.74) / 0.22, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)  # smoothstep
		var inf := {}
		for k in 4:
			var idx := v * 4 + k
			var b := bones[idx]
			var w := weights[idx]
			if w > 0.00001:
				inf[b] = float(inf.get(b, 0.0)) + w
		var w_up := float(inf.get(bind_upper, 0.0))
		if w_up <= 0.0:
			continue
		var move := w_up * t
		inf[bind_upper] = w_up - move
		inf[bind_lower] = float(inf.get(bind_lower, 0.0)) + move
		# 取权重最大的 4 个影响写回（保持 4 槽格式）
		var keys := inf.keys()
		keys.sort_custom(func(a, b): return float(inf[a]) > float(inf[b]))
		var total := 0.0
		for k in mini(4, keys.size()):
			total += float(inf[keys[k]])
		if total <= 0.0:
			continue
		for k in 4:
			var idx := v * 4 + k
			if k < mini(4, keys.size()):
				bones[idx] = int(keys[k])
				weights[idx] = float(inf[keys[k]]) / total
			else:
				bones[idx] = 0
				weights[idx] = 0.0
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var new_mesh := ArrayMesh.new()
	for b in mesh.get_blend_shape_count():
		new_mesh.add_blend_shape(mesh.get_blend_shape_name(b))
	new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, mesh.surface_get_blend_shape_arrays(0))
	for si in mesh.get_surface_count():
		new_mesh.surface_set_material(si, mesh.surface_get_material(si))
	arms.mesh = new_mesh


## 机体外观：逐实例覆盖 Body 表面材质（不改共享网格/材质），支持每个玩家不同颜色。
## Arms/Body/Legs 单面；Face 面 0 = Body、面 1 = Mouth（保留）。
func _apply_body_color() -> void:
	if _body_mat == null:
		_body_mat = ShaderMaterial.new()
		_body_mat.shader = BODY_SHADER
		_body_mat.set_shader_parameter("metallic", BODY_METALLIC)
		_body_mat.set_shader_parameter("roughness", BODY_ROUGHNESS)
		_body_mat.set_shader_parameter("light_dir_world", Vector3(-0.4, 0.82, 0.41))
		var look := CardTiltPreset.load_params()
		if look.is_empty():
			look = CardTiltPreset.DEFAULTS
		_body_mat.set_shader_parameter("eye_spec", 0.35 + float(look.get("gloss_strength", 0.35)) * 1.2)
		_body_mat.set_shader_parameter("rim_strength", 0.1 + float(look.get("rim_strength", 0.30)) * 0.4)
	_body_mat.set_shader_parameter("albedo_color", _body_color)
	for nm in ["Arms", "Body", "Legs"]:
		var mi = _robot.get_node_or_null("Armature/Skeleton3D/" + nm)
		if mi != null:
			mi.set_surface_override_material(0, _body_mat)
	var face = _robot.get_node_or_null("Armature/Skeleton3D/Face")
	if face != null:
		face.set_surface_override_material(0, _body_mat)
	if _nose != null:
		_nose.set_color(_body_color)

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

## 右手抬臂/放下（看道具牌）：平滑过渡到"上臂前伸 + 肘部弯折"的姿势。
func set_arm_up(on: bool) -> void:
	_build()
	_arm_up = on


func arm_up() -> bool:
	return _arm_up


func arm_progress() -> float:
	return _arm_p


func _update_arm(delta: float) -> void:
	if _skeleton == null:
		return
	var target := 1.0 if _arm_up else 0.0
	if is_equal_approx(_arm_p, target):
		return
	_arm_p = move_toward(_arm_p, target, delta * ARM_UP_SPEED)
	_apply_arm_pose()


## 右手姿势：idle（竖直下垂）↔ 抬起（上臂朝前 + 肘部弯折）。
func _apply_arm_pose() -> void:
	var up_i := _skeleton.find_bone("upper_arm.R")
	var lo_i := _skeleton.find_bone("lower_arm.R")
	var hand_i := _skeleton.find_bone("hand.R")
	if up_i < 0 or lo_i < 0 or hand_i < 0:
		return
	var up_rest := _skeleton.get_bone_global_rest(up_i)
	var lo_rest := _skeleton.get_bone_global_rest(lo_i)
	var hand_rest := _skeleton.get_bone_global_rest(hand_i)
	var lo_local := up_rest.affine_inverse() * lo_rest
	var hand_local := lo_rest.affine_inverse() * hand_rest
	# idle：上臂绕 Z 放下 82°；小臂/手自然继承。
	var up_idle := Transform3D(Basis(Vector3(0, 0, 1), deg_to_rad(ARM_DOWN_DEG)) * up_rest.basis, up_rest.origin)
	var lo_idle := up_idle * lo_local
	var hand_idle := lo_idle * hand_local
	# 抬起：上臂朝下前方；小臂再折向前，手腕放平到桌面高度。
	var up_raised := Transform3D(_aim_basis(up_rest.basis, ARM_UP_UPPER_DIR), up_rest.origin)
	var lo_inherited := up_raised * lo_local
	var lo_raised := Transform3D(_aim_basis(lo_inherited.basis, ARM_UP_FORE_DIR), lo_inherited.origin)
	var hand_inherited := lo_raised * hand_local
	# 手背朝上、手指朝前，平放在桌面上（模型空间 +Z 为前、-Y 为下）。
	var hand_basis := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
	var hand_raised := Transform3D(hand_basis, hand_inherited.origin)
	var up_t := _blend_xform(up_idle, up_raised, _arm_p)
	var lo_t := _blend_xform(lo_idle, lo_raised, _arm_p)
	var hand_t := _blend_xform(hand_idle, hand_raised, _arm_p)
	_skeleton.set_bone_global_pose_override(up_i, up_t, 1.0, true)
	_skeleton.set_bone_global_pose_override(lo_i, lo_t, 1.0, true)
	_skeleton.set_bone_global_pose_override(hand_i, hand_t, 1.0, true)


## 把骨骼的"长度轴"（本地 Y）从当前朝向转到目标方向，保留 roll。
func _aim_basis(rest_basis: Basis, dir: Vector3) -> Basis:
	var cur := rest_basis.y.normalized()
	var to := dir.normalized()
	if cur.dot(to) < -0.9999:
		return rest_basis
	return Basis(Quaternion(cur, to)) * rest_basis


func _blend_xform(a: Transform3D, b: Transform3D, t: float) -> Transform3D:
	var qa := a.basis.get_rotation_quaternion()
	var qb := b.basis.get_rotation_quaternion()
	return Transform3D(Basis(qa.slerp(qb, t)), a.origin.lerp(b.origin, t))


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

## 离线/出局：头眼回正冻结（正前方），by table3d 不再喂注视目标。
func set_gaze_frozen(on: bool) -> void:
	if _gaze_frozen == on:
		return
	_gaze_frozen = on
	if on:
		reset_eyes()

func gaze_frozen() -> bool:
	return _gaze_frozen

func _apply_crown_material(root: Node) -> void:
	var tex: Texture2D = null
	var meshes: Array = []
	_collect_meshes(root, meshes)
	for mi in meshes:
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			var src = mi.mesh.surface_get_material(0)
			if tex == null and src is StandardMaterial3D:
				tex = (src as StandardMaterial3D).albedo_texture
	if tex == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = CROWN_SHADER
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("spec_strength", 1.1)
	mat.set_shader_parameter("rim_strength", 0.35)
	mat.set_shader_parameter("light_dir_world", Vector3(-0.45, 0.82, 0.36))
	for mi in meshes:
		mi.material_override = mat


## 上一局冠军皇冠：套在头顶；和离线光环可同时存在（光环会自动抬高）。
func set_crown(on: bool) -> void:
	_build()
	_crown_on = on
	if on and _crown == null:
		_crown = CROWN_SCENE.instantiate()
		_crown.name = "ChampionCrown"
		_crown.position = Vector3(0.0, CROWN_Y_MODEL, 0.0)
		_crown.scale = Vector3.ONE * (2.0 / 3.0)
		add_child(_crown)
		_apply_crown_material(_crown)
	if _crown != null:
		_crown.visible = on


func crown_visible() -> bool:
	return _crown != null and _crown.visible


## 头顶光环（离线/出局 😇 式金环）：淡入、悬浮呼吸、缓慢旋转。
func set_halo(on: bool) -> void:
	_build()
	if _halo == null:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.33
		torus.outer_radius = 0.375
		_halo = MeshInstance3D.new()
		_halo.name = "Halo"
		_halo.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(HALO_COLOR, 0.0)
		mat.emission_enabled = true
		mat.emission = HALO_COLOR
		mat.emission_energy_multiplier = 1.6
		_halo.material_override = mat
		_halo.position = Vector3(0.0, HALO_Y_MODEL, 0.0)
		add_child(_halo)
	_halo_target_a = 0.85 if on else 0.0
	if on:
		_halo.visible = true  # 由 _process 淡入到目标透明度
	else:
		# 淡出后隐藏（目标 alpha=0，此帧起继续衰减）
		_halo.visible = _halo_a > 0.0

func halo_visible() -> bool:
	return _halo != null and _halo.visible

func halo_enabled() -> bool:
	return _halo_target_a > 0.0

## ===== 鼻子（中键 / D 键指针）=====
## 目标为**世界坐标点**（hover 卡牌中心）；Vector3.ZERO 表示未伸出。
## 鼻根随头移动，鼻子朝目标点定向、长度=鼻根到目标点距离 → 鼻尖落在目标点上。
func set_nose_target_world(target_world: Vector3) -> void:
	_build()
	_nose_target_world = target_world if target_world.is_finite() else Vector3.ZERO

## 当前鼻子长度（世界单位）。
func nose_length() -> float:
	if _nose == null:
		return 0.0
	return _nose.length() * SCALE

func nose_state_name() -> String:
	if _nose == null:
		return "IDLE"
	return _nose.state_name()

## 鼻根世界变换（由 Head 当前姿势推出）。
func nose_base_world() -> Transform3D:
	_build()
	if _skeleton == null or _head_idx < 0:
		return Transform3D(global_transform.basis, global_transform * _nose_base_model)
	var hpose: Transform3D = _skeleton.get_bone_global_pose(_head_idx)
	var hrest: Transform3D = _skeleton.get_bone_global_rest(_head_idx)
	var base_skel: Vector3 = hpose * (hrest.affine_inverse() * _nose_base_model)
	return Transform3D(_skeleton.global_transform.basis, _skeleton.global_transform * base_skel)

## 每帧：按头姿势 + 目标点重算鼻子的基与长度（随头摆、鼻尖指向目标）。
func _update_nose() -> void:
	if _nose == null or _skeleton == null or _head_idx < 0:
		return
	if _nose_target_world == Vector3.ZERO:
		if _nose.is_active():
			_nose.set_target(0.0)
		return
	var hpose: Transform3D = _skeleton.get_bone_global_pose(_head_idx)
	var hrest: Transform3D = _skeleton.get_bone_global_rest(_head_idx)
	var base_skel: Vector3 = hpose * (hrest.affine_inverse() * _nose_base_model)
	var target_skel: Vector3 = _skeleton.global_transform.affine_inverse() * _nose_target_world
	var delta: Vector3 = target_skel - base_skel
	var dist := delta.length()
	if dist <= 0.0001:
		_nose.set_target(0.0)
		return
	var dn := delta / dist
	var up := Vector3.UP
	if absf(dn.dot(up)) > 0.99:
		up = Vector3.RIGHT
	_nose.transform = Transform3D(Basis.looking_at(dn, up, true), base_skel)
	_nose.set_target(dist)

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
