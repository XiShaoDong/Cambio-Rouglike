class_name CardAnimationConfig
extends RefCounted
## 卡牌交互动效参数（集中配置；代码不出现散落魔法数）。
## 控制器按字段访问；纯数学按 to_dict() 访问。

var idle_amp := 0.03
var idle_speed := 1.2
var idle_rot_z := 0.5
var idle_rot_x := 0.3
var hover_lift := 0.12
var hover_scale := 1.06
var hover_pitch := 28.0
var max_tilt := 4.0
var hover_in_dur := 0.12
var hover_out_dur := 0.20
var press_dur := 0.08
var press_min := 0.97
var press_over := 1.02
var flip_dur := 0.34
var flip_lift := 0.25
var land_dur := 0.12
var land_over := 1.04
var land_under := 0.99
var shadow_base_alpha := 0.5
var shadow_scale_loss := 0.30
var shadow_alpha_loss := 0.50

const KEYS := [
	"idle_amp", "idle_speed", "idle_rot_z", "idle_rot_x",
	"hover_lift", "hover_scale", "hover_pitch", "max_tilt",
	"hover_in_dur", "hover_out_dur", "press_dur", "press_min", "press_over",
	"flip_dur", "flip_lift", "land_dur", "land_over", "land_under",
	"shadow_base_alpha", "shadow_scale_loss", "shadow_alpha_loss",
]

func to_dict() -> Dictionary:
	var d := {}
	for k in KEYS:
		d[k] = get(k)
	return d

## 字段值是否全部有限且非负；返回非法字段名数组。
func validate() -> Array:
	var bad: Array = []
	for k in KEYS:
		var v := float(get(k))
		if not is_finite(v) or v < 0.0:
			bad.append(k)
	return bad
