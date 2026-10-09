class_name DeckBackConfig
extends RefCounted
## 抽牌堆模型卡背投影参数（集中配置；代码不出现散落魔法数）。
## 与 assets/shaders/deck_back_projection.gdshader 的 uniform 同名一一对应。

var project_card_size := Vector2(1.86, 1.90)  # 一张卡背在世界 XZ 的投影尺寸
var rotation_deg := 0.0                       # 卡背绕 Y 旋转
var layer_height := 0.01                      # 每层堆叠厚度（≈模型 Y 步进）
var layer_offset := Vector2(0.03, 0.02)       # 逐层 XZ 偏移幅度
var layer_shuffle := 1.0                      # 逐层偏移随机种子
var layer_ao := 0.25                          # 最底层相对顶层压暗比例 [0,1]
var edge_darken := 0.35                       # 卡边相对边框色压暗 [0,1]
var edge_softness := 0.40                     # 顶面↔侧面法线过渡带
var model_height := 0.25                      # 模型高度（AO 归一化基准）
var tint := Color.WHITE                       # 整体染色
var tile := false                             # 是否平铺（备用观感）

const KEYS := [
	"project_card_size", "rotation_deg", "layer_height", "layer_offset",
	"layer_shuffle", "layer_ao", "edge_darken", "edge_softness",
	"model_height", "tint", "tile",
]

func to_dict() -> Dictionary:
	var d := {}
	for k in KEYS:
		d[k] = get(k)
	return d

## 返回非法字段名数组。
func validate() -> Array:
	var bad: Array = []
	var size := project_card_size as Vector2
	if not (is_finite(size.x) and is_finite(size.y)) or size.x <= 0.0 or size.y <= 0.0:
		bad.append("project_card_size")
	if not is_finite(layer_height) or layer_height <= 0.0:
		bad.append("layer_height")
	if not is_finite(model_height) or model_height <= 0.0:
		bad.append("model_height")
	if not is_finite(rotation_deg):
		bad.append("rotation_deg")
	var off := layer_offset as Vector2
	if not (is_finite(off.x) and is_finite(off.y)):
		bad.append("layer_offset")
	if not is_finite(layer_shuffle):
		bad.append("layer_shuffle")
	for k in ["layer_ao", "edge_darken", "edge_softness"]:
		var v := float(get(k))
		if not is_finite(v) or v < 0.0 or v > 1.0:
			bad.append(k)
	return bad
