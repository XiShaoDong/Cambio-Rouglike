class_name CardTiltMath
extends RefCounted
## 2D 伪 3D 卡牌倾斜的纯数学：鼠标→角度、阻尼、3D 投影、单应矩阵求逆、光照法线。
## 全部静态、不依赖节点，headless 可测。uniform 约定与 assets/shaders/card_tilt.gdshader 同步。
##
## 坐标约定：卡片局部 x 右 / y 下（与 2D 一致）/ z 朝观察者；卡宽 1，高 = aspect（高/宽）。
## 相机在 (0, 0, cam_dist)，焦距取 cam_dist → 静止时卡宽占画布 1/pad。

const LIGHT_DIR := Vector3(-0.45, -0.35, 0.82)
const IDENTITY_ROWS := [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]


## 鼠标归一化位置（卡面内 [-1,1]）→ 目标倾斜角（度）：Vector2(yaw, pitch)。
static func target_angles(mouse_norm: Vector2, max_angle_deg: float) -> Vector2:
	var m := Vector2(clampf(mouse_norm.x, -1.0, 1.0), clampf(mouse_norm.y, -1.0, 1.0))
	return m * maxf(max_angle_deg, 0.0)


## 指数阻尼：response 越大越快；delta 为帧间隔秒。
static func smooth_angles(current: Vector2, target: Vector2, response: float, delta: float) -> Vector2:
	if response <= 0.0:
		return target
	var t := 1.0 - exp(-response * maxf(delta, 0.0))
	return current.lerp(target, clampf(t, 0.0, 1.0))


## 倾斜角（度）→ 旋转矩阵。YXZ 顺序：先 yaw 再 pitch。
static func rotation_basis(yaw_deg: float, pitch_deg: float) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))


## 卡片四角（局部平面，顺序：左上、右上、右下、左下）。
static func card_corners(card_aspect: float) -> PackedVector2Array:
	var hy := maxf(card_aspect, 0.001) * 0.5
	return PackedVector2Array([
		Vector2(-0.5, -hy),
		Vector2(0.5, -hy),
		Vector2(0.5, hy),
		Vector2(-0.5, hy),
	])


## 透视投影到屏幕（卡宽单位，x 右 y 下）。
static func project_point(point: Vector3, cam_dist: float, focal: float) -> Vector2:
	var denom := cam_dist - point.z
	if denom <= 0.0001:
		return Vector2.ZERO
	return Vector2(focal * point.x / denom, focal * point.y / denom)


## 四角投影后归一化到画布 UV（画布宽 = pad 个卡宽，高 = pad * aspect）。
static func projected_quad(card_aspect: float, basis: Basis, cam_dist: float, pad: float) -> PackedVector2Array:
	var safe_pad := maxf(pad, 0.001)
	var canvas_h := safe_pad * maxf(card_aspect, 0.001)
	var out := PackedVector2Array()
	for corner in card_corners(card_aspect):
		var p := basis * Vector3(corner.x, corner.y, 0.0)
		var s := project_point(p, cam_dist, cam_dist)
		out.append(Vector2(0.5 + s.x / safe_pad, 0.5 + s.y / canvas_h))
	return out


## Heckbert：单位方 (0,0)(1,0)(1,1)(0,1) → 任意四边形，返回行主序 3x3。
static func homography_unit_to_quad(quad: PackedVector2Array) -> PackedFloat64Array:
	var p0 := quad[0]
	var p1 := quad[1]
	var p2 := quad[2]
	var p3 := quad[3]
	var sx := p0.x - p1.x + p2.x - p3.x
	var sy := p0.y - p1.y + p2.y - p3.y
	var a := 0.0
	var b := 0.0
	var c := 0.0
	var d := 0.0
	var e := 0.0
	var f := 0.0
	var g := 0.0
	var h := 0.0
	if absf(sx) < 1e-9 and absf(sy) < 1e-9:
		a = p1.x - p0.x
		b = p3.x - p0.x
		c = p0.x
		d = p1.y - p0.y
		e = p3.y - p0.y
		f = p0.y
	else:
		var dx1 := p1.x - p2.x
		var dx2 := p3.x - p2.x
		var dy1 := p1.y - p2.y
		var dy2 := p3.y - p2.y
		var den := dx1 * dy2 - dx2 * dy1
		if absf(den) < 1e-12:
			return PackedFloat64Array(IDENTITY_ROWS)
		g = (sx * dy2 - dx2 * sy) / den
		h = (dx1 * sy - sx * dy1) / den
		a = p1.x - p0.x + g * p1.x
		b = p3.x - p0.x + h * p3.x
		c = p0.x
		d = p1.y - p0.y + g * p1.y
		e = p3.y - p0.y + h * p3.y
		f = p0.y
	return PackedFloat64Array([a, b, c, d, e, f, g, h, 1.0])


## 3x3（行主序）求逆；奇异时返回单位阵。
static func invert3(m: PackedFloat64Array) -> PackedFloat64Array:
	var a := m[0]
	var b := m[1]
	var c := m[2]
	var d := m[3]
	var e := m[4]
	var f := m[5]
	var g := m[6]
	var h := m[7]
	var i := m[8]
	var c00 := e * i - f * h
	var c01 := -(d * i - f * g)
	var c02 := d * h - e * g
	var det := a * c00 + b * c01 + c * c02
	if absf(det) < 1e-12:
		return PackedFloat64Array(IDENTITY_ROWS)
	var inv_det := 1.0 / det
	var r0 := Vector3(c00, -(b * i - c * h), b * f - c * e) * inv_det
	var r1 := Vector3(c01, a * i - c * g, -(a * f - c * d)) * inv_det
	var r2 := Vector3(c02, -(a * h - b * g), a * e - b * d) * inv_det
	return PackedFloat64Array([r0.x, r0.y, r0.z, r1.x, r1.y, r1.z, r2.x, r2.y, r2.z])


## 行主序 3x3 作用于二维点（齐次）。
static func apply3(m: PackedFloat64Array, point: Vector2) -> Vector2:
	var w := m[6] * point.x + m[7] * point.y + m[8]
	if absf(w) < 1e-12:
		return Vector2.ZERO
	return Vector2(
		(m[0] * point.x + m[1] * point.y + m[2]) / w,
		(m[3] * point.x + m[4] * point.y + m[5]) / w)


## 画布 UV → 源 UV 的逆映射矩阵（行主序 9 个 float，直接喂 shader 的三行 vec3）。
static func inverse_uv_map(card_aspect: float, yaw_deg: float, pitch_deg: float, cam_dist: float, pad: float) -> PackedFloat64Array:
	var basis := rotation_basis(yaw_deg, pitch_deg)
	var quad := projected_quad(card_aspect, basis, cam_dist, pad)
	return invert3(homography_unit_to_quad(quad))


## 卡片法线（视空间，静止时为 (0,0,1)）。
static func surface_normal(yaw_deg: float, pitch_deg: float) -> Vector3:
	return (rotation_basis(yaw_deg, pitch_deg) * Vector3(0.0, 0.0, 1.0)).normalized()


## 画布尺寸 = 卡面尺寸 * pad。
static func padded_size(card_size: Vector2, pad: float) -> Vector2:
	return card_size * maxf(pad, 0.001)


## 光源方向（与 shader 默认一致）。
static func light_direction() -> Vector3:
	return LIGHT_DIR.normalized()
