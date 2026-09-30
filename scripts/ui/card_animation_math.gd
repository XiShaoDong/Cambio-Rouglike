class_name CardAnimationMath
extends RefCounted
## 卡牌交互动效纯数学：状态机 / 缓动 / 高度 / 阴影 / 变换合成。
## 无节点依赖 → headless 可测。唯一写 transform 处由控制器调用 compose 完成。

const IDLE := 0
const HOVER := 1
const PRESS := 2
const FLIP := 3
const LAND := 4

const EV_ENTER := "enter"
const EV_EXIT := "exit"
const EV_CLICK := "click"
const EV_TIMER := "timer"

## 状态转移（纯函数）。PRESS/FLIP/LAND 中的 EXIT/CLICK 不打断（防连击）。
static func next_state(cur: int, event: String, hovering: bool, flip_done: bool, land_done: bool) -> int:
	match cur:
		IDLE:
			return HOVER if event == EV_ENTER else IDLE
		HOVER:
			if event == EV_EXIT:
				return IDLE
			if event == EV_CLICK:
				return PRESS
			return HOVER
		PRESS:
			return FLIP if event == EV_TIMER else PRESS
		FLIP:
			if event == EV_TIMER and flip_done:
				return LAND
			return FLIP
		LAND:
			if event == EV_TIMER and land_done:
				return HOVER if hovering else IDLE
			return LAND
	return cur

static func ease_out_cubic(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)

static func ease_in_out_cubic(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	if t < 0.5:
		return 4.0 * t * t * t
	return 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0

static func ease_out_back(t: float, s := 1.70158) -> float:
	t = clampf(t, 0.0, 1.0)
	var c3 := s + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + s * pow(t - 1.0, 2.0)

static func lerp_f(a: float, b: float, t: float) -> float:
	return a + (b - a) * clampf(t, 0.0, 1.0)

## 压缩曲线：0→press_min→press_over→1（t 0..1，三段 ease_out_cubic）。
static func press_scale(p: float, cfg: Dictionary) -> float:
	p = clampf(p, 0.0, 1.0)
	var mn: float = cfg["press_min"]
	var ov: float = cfg["press_over"]
	if p < 0.33:
		return lerp_f(1.0, mn, ease_out_cubic(p / 0.33))
	if p < 0.66:
		return lerp_f(mn, ov, ease_out_cubic((p - 0.33) / 0.33))
	return lerp_f(ov, 1.0, ease_out_cubic((p - 0.66) / 0.34))

## 落牌回弹曲线：0→land_over→land_under→1。
static func land_scale(l: float, cfg: Dictionary) -> float:
	l = clampf(l, 0.0, 1.0)
	var ov: float = cfg["land_over"]
	var un: float = cfg["land_under"]
	if l < 0.4:
		return lerp_f(1.0, ov, ease_out_cubic(l / 0.4))
	if l < 0.75:
		return lerp_f(ov, un, ease_out_cubic((l - 0.4) / 0.35))
	return lerp_f(un, 1.0, ease_out_cubic((l - 0.75) / 0.25))

## 离桌高度：idle 悬浮（hover 时抑制）+ hover 抬升 + 翻牌弧线。
static func height(progress: Dictionary, cfg: Dictionary, idle_time: float) -> float:
	var hover := float(progress.get("hover", 0.0))
	var flip := float(progress.get("flip", 0.0))
	var idle := float(cfg["idle_amp"]) * (1.0 - hover) * sin(idle_time * float(cfg["idle_speed"]))
	var flip_arc := float(cfg["flip_lift"]) * sin(flip * PI)
	return idle + float(cfg["hover_lift"]) * hover + flip_arc

static func _height_norm(height_value: float, cfg: Dictionary) -> float:
	var max_h := float(cfg["hover_lift"]) + float(cfg["flip_lift"])
	return clampf(height_value / max_h, 0.0, 1.0) if max_h > 0.0 else 0.0

static func shadow_scale_for(height_value: float, cfg: Dictionary) -> float:
	return 1.0 - _height_norm(height_value, cfg) * float(cfg["shadow_scale_loss"])

static func shadow_alpha_for(height_value: float, cfg: Dictionary) -> float:
	return float(cfg["shadow_base_alpha"]) * (1.0 - _height_norm(height_value, cfg) * float(cfg["shadow_alpha_loss"]))

## 合成本帧变换偏移。flip 单独返回（控制器按卡长轴用 Basis 组合，不受仰角影响）。
static func compose(progress: Dictionary, cfg: Dictionary, idle_time: float, ray_local: Vector2) -> Dictionary:
	var hover := clampf(float(progress.get("hover", 0.0)), 0.0, 1.0)
	var press := clampf(float(progress.get("press", 0.0)), 0.0, 1.0)
	var flip := clampf(float(progress.get("flip", 0.0)), 0.0, 1.0)
	var land := clampf(float(progress.get("land", 0.0)), 0.0, 1.0)
	var hold_x := cos(idle_time * 0.5) * float(cfg["idle_rot_x"]) * (1.0 - hover)
	var hold_z := sin(idle_time * 0.7) * float(cfg["idle_rot_z"]) * (1.0 - hover)
	# hover_pitch 正值 = 卡面向玩家（本地帧下需取负 rot_x；见沙盒实测）
	var rot_x := hold_x - float(cfg["hover_pitch"]) * hover - ray_local.y * float(cfg["max_tilt"])
	var rot_y := ray_local.x * float(cfg["max_tilt"])
	var scale := (1.0 + (float(cfg["hover_scale"]) - 1.0) * hover) * press_scale(press, cfg) * land_scale(land, cfg)
	# 倾斜离桌补偿：近端下沉 (卡长/2·scale)·sin(|rot_x|)，抬高中心使近端始终留 hover_clearance 缝隙
	var h := height(progress, cfg, idle_time)
	var half_len := Table3dLayout.BLOCK_SIZE.z * 0.5 * scale
	var near_drop := half_len * sin(deg_to_rad(absf(rot_x)))
	var comp_hover := maxf(float(cfg["hover_lift"]), float(cfg["hover_clearance"]) + near_drop)
	h = h - float(cfg["hover_lift"]) * hover + comp_hover * hover
	return {
		"visual_pos": Vector3(0.0, h, 0.0),
		"visual_rot_deg": Vector3(rot_x, rot_y, hold_z),
		"flip_deg": flip * 180.0,
		"visual_scale": scale,
		"shadow_scale": shadow_scale_for(h, cfg),
		"shadow_alpha": shadow_alpha_for(h, cfg),
	}
