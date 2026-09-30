class_name CardFlyMath
extends RefCounted
## 3D 换牌飞牌纯数学：时长 / 路径缓动 / 弧线 / 翻面 / 变换合成。
## 无节点依赖 → headless 可测。唯一写 transform 处由控制器调用 compose 完成。

static func ease_in_out_cubic(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if t < 0.5:
		return 4.0 * t * t * t
	return 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0

static func smoothstep(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## 距离 → 时长（秒）：恒定速度 —— 时长 = 距离 / speed（距离越远时长越长，速度不变）。
## duration_min 仅作下限，防止同位置飞行的零时长。
static func duration_for(dist: float, cfg: Dictionary) -> float:
	var sp := float(cfg["speed"])
	if sp <= 0.0:
		return float(cfg["duration_min"])
	return maxf(dist / sp, float(cfg["duration_min"]))

## 路径进度 = 缓动(p)。
static func path_t(p: float, _cfg: Dictionary = {}) -> float:
	return ease_in_out_cubic(p)

## 弧线抬升：世界 +Y 偏移 = arc_height * sin(p*PI)（起止为 0，p=0.5 峰值）。
static func arc_lift(p: float, cfg: Dictionary) -> float:
	return float(cfg["arc_height"]) * sin(clampf(p, 0.0, 1.0) * PI)

## 翻面进度：p 落在 [flip_start, flip_end] 内 smoothstep 0→1，窗口外夹取。
static func flip_t(p: float, cfg: Dictionary) -> float:
	var a := float(cfg["flip_start"])
	var b := float(cfg["flip_end"])
	if b <= a:
		return 1.0 if p >= b else 0.0
	return CardFlyMath.smoothstep((p - a) / (b - a))

## 合成：起止世界变换 + p + 滚转偏置 → {origin, basis}。
## roll_start_deg：起始面为背面时传 180，否则 0；roll_delta_deg：起面≠终面时传 180，否则 0。
static func compose(start: Transform3D, end: Transform3D, p: float,
		roll_start_deg: float, roll_delta_deg: float, cfg: Dictionary) -> Dictionary:
	var t := path_t(p)
	var origin := start.origin.lerp(end.origin, t)
	origin.y += arc_lift(p, cfg)
	var basis := start.basis.slerp(end.basis, t)
	var roll := deg_to_rad(roll_start_deg + roll_delta_deg * flip_t(p, cfg))
	basis = basis * Basis(Vector3(0.0, 0.0, 1.0), roll)
	return {"origin": origin, "basis": basis}
