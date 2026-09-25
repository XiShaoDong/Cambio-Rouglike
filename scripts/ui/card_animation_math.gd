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
