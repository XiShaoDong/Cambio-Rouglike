class_name Mark3dMath
extends RefCounted
## 桌面标记（波纹 ping）纯函数，headless 可测。

## 从 owner 指向 center 的水平（XZ）单位方向（owner→center）；退化回退 +Z。
static func arrow_dir_xz(center: Vector3, owner: Vector3) -> Vector3:
	var d := Vector3(center.x - owner.x, 0.0, center.z - owner.z)
	if d.length_squared() < 0.000001:
		return Vector3.FORWARD
	return d.normalized()

## 落点是否在桌面范围内（正方形 |x|,|z| <= radius）。
static func on_table(pos: Vector3, radius: float) -> bool:
	return absf(pos.x) <= radius and absf(pos.z) <= radius

## 相位 -> 环缩放。
static func ring_scale(phase: float, base: float, max_scale: float) -> float:
	return lerpf(base, max_scale, clampf(phase, 0.0, 1.0))

## 相位 -> 环透明度（向外扩散同时淡出）。
static func ring_alpha(phase: float, peak: float) -> float:
	return peak * (1.0 - clampf(phase, 0.0, 1.0))

## 归一化循环相位。
static func wrap_phase(t: float, period: float) -> float:
	if period <= 0.0:
		return 0.0
	return fmod(t, period) / period

## 轮盘命中：offset=cursor-center；中空/超范围返回 ""，否则 eye(上)/question(右)/number(下)/exclaim(左)。
static func sector_for(offset: Vector2, inner: float, outer: float) -> String:
	var r := offset.length()
	if r < inner or r > outer:
		return ""
	var ang := rad_to_deg(atan2(offset.y, offset.x))  # 屏幕坐标 y 向下
	if ang >= -135.0 and ang < -45.0:
		return "eye"
	if ang >= -45.0 and ang < 45.0:
		return "question"
	if ang >= 45.0 and ang < 135.0:
		return "number"
	return "exclaim"

## 通用径向命中：count 扇区，扇区 0 以正上(-90°)为中心、顺时针递增；中空/超范围返回 -1。
static func sector_index_for(offset: Vector2, inner: float, outer: float, count: int) -> int:
	if count <= 0:
		return -1
	var r := offset.length()
	if r < inner or r > outer:
		return -1
	var w := 360.0 / float(count)
	var a := rad_to_deg(atan2(offset.y, offset.x))
	var rel := fposmod(a + 90.0 + w * 0.5, 360.0)
	var idx := int(rel / w)
	return clampi(idx, 0, count - 1)
