class_name CardFlyConfig
extends RefCounted
## 3D 换牌飞牌参数（集中配置；代码不出现散落魔法数）。
## 控制器与纯数学均按 to_dict() 访问。

var duration_base := 0.30
var duration_per_dist := 0.002
var duration_min := 0.30
var duration_max := 0.90
var arc_height := 0.35
var flip_start := 0.35
var flip_end := 0.65

const KEYS := [
	"duration_base", "duration_per_dist", "duration_min", "duration_max",
	"arc_height", "flip_start", "flip_end",
]

func to_dict() -> Dictionary:
	var d := {}
	for k in KEYS:
		d[k] = get(k)
	return d

## 字段值是否全部有限且非负，且 flip_start <= flip_end；返回非法/不一致字段名数组。
func validate() -> Array:
	var bad: Array = []
	for k in KEYS:
		var v := float(get(k))
		if not is_finite(v) or v < 0.0:
			bad.append(k)
	if flip_start > flip_end and not bad.has("flip_start"):
		bad.append("flip_start")
	return bad
