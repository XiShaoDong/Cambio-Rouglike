class_name RobotAvatarMath
extends RefCounted
## Robot 角色纯函数层：ARKit 眼部 blendshape 权重映射。
## 无节点依赖，headless 可测。
##
## 模型本地坐标约定（见 docs/3D角色与场景说明.md）：
##   +X = 机器人**左**侧（骨骼 shoulder.L 在 +X），-X = 右侧；
##   +Y = 上；+Z = 前方（眼球中心 z≈+0.215，为脸朝向）。

## 眼球朝向 blendshape 名称（与模型 Eyes 网格 0..7 一致）。
const LOOK_NAMES := [
	"eyeLookOutRight", "eyeLookOutLeft", "eyeLookInRight", "eyeLookInLeft",
	"eyeLookUpLeft", "eyeLookUpRight", "eyeLookDownLeft", "eyeLookDownRight",
]
const BLINK_NAMES := ["eyeBlinkLeft", "eyeBlinkRight"]

## 由机器人本地朝向（dir_local，无需归一化）算出眼球朝向权重。
## 返回 {name: weight}，覆盖全部 LOOK_NAMES（未用到的为 0，范围 0..1）。
## h>0 = 向机器人左侧看，v>0 = 向上看；yaw/pitch 除以各自上限后夹取到 [-1,1]。
static func eye_look_weights(dir_local: Vector3, yaw_max_deg := 32.0, pitch_max_deg := 18.0, gain := 1.0) -> Dictionary:
	var horiz := Vector2(dir_local.x, dir_local.z).length()
	var h := 0.0
	if horiz > 0.000001:
		h = atan2(dir_local.x, dir_local.z) / deg_to_rad(maxf(yaw_max_deg, 0.01))
	var v := 0.0
	if horiz > 0.000001:
		v = atan2(dir_local.y, horiz) / deg_to_rad(maxf(pitch_max_deg, 0.01))
	h = clampf(h * gain, -1.0, 1.0)
	v = clampf(v * gain, -1.0, 1.0)
	var out := {}
	for n in LOOK_NAMES:
		out[n] = 0.0
	# 水平：向左看 → 左眼外展(OutLeft) + 右眼内收(InRight)；向右看反之。
	out["eyeLookOutLeft"] = maxf(h, 0.0)
	out["eyeLookInRight"] = maxf(h, 0.0)
	out["eyeLookInLeft"] = maxf(-h, 0.0)
	out["eyeLookOutRight"] = maxf(-h, 0.0)
	# 垂直：双眼共向上/下。
	out["eyeLookUpLeft"] = maxf(v, 0.0)
	out["eyeLookUpRight"] = maxf(v, 0.0)
	out["eyeLookDownLeft"] = maxf(-v, 0.0)
	out["eyeLookDownRight"] = maxf(-v, 0.0)
	return out

## 眨眼权重：p∈[0,1]（1=完全闭合）。
static func blink_weights(p: float) -> Dictionary:
	var q := clampf(p, 0.0, 1.0)
	return {"eyeBlinkLeft": q, "eyeBlinkRight": q}

## 说话时的"开合嘴"权重（jawOpen, 0..1）：无音素输入时用多正弦叠加 + 慢包络
## 模拟说话的节奏（约 4~10Hz 抖动，包络让说话有起伏/停顿感）。
static func talk_jaw(t: float) -> float:
	if t < 0.0:
		t = 0.0
	var v := 0.0
	v += 0.55 * (0.5 + 0.5 * sin(TAU * 6.0 * t))
	v += 0.30 * (0.5 + 0.5 * sin(TAU * 9.7 * t + 1.3))
	v += 0.15 * (0.5 + 0.5 * sin(TAU * 4.1 * t + 2.1))
	var env := 0.60 + 0.40 * (0.5 + 0.5 * sin(TAU * 0.35 * t + 0.7))
	return clampf(v * env, 0.0, 1.0)
