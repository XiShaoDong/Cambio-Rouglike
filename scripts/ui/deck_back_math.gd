class_name DeckBackMath
extends RefCounted
## 抽牌堆卡背投影纯函数（着色器 GLSL 逻辑的可测镜像）。
## 注意：GDScript 无 fract()，用 fposmod(x, 1.0)。着色器同名函数用 GLSL fract()。

## 确定性 2D hash，输出分量 ∈ [0,1)。与 deck_back_projection.gdshader 的 hash22 同式。
static func hash22(v: Vector2) -> Vector2:
	return Vector2(
		fposmod(sin(v.x * 127.1 + v.y * 311.7) * 43758.5453, 1.0),
		fposmod(sin(v.x * 269.5 + v.y * 183.3) * 28001.8384, 1.0))

## 层索引：y / layer_height 向下取整；layer_height<=0 兜底为 0。
static func layer_index(y: float, layer_height: float) -> float:
	if layer_height <= 0.0:
		return 0.0
	return floor(y / layer_height)

## 逐层确定性偏移：同层同值、不同层不同，幅度受 layer_offset 缩放，落在 [-layer_offset, +layer_offset]。
static func layer_offset(layer_index_value: float, layer_offset_value: Vector2, shuffle: float) -> Vector2:
	var h := hash22(Vector2(layer_index_value, shuffle))
	return (h * 2.0 - Vector2.ONE) * layer_offset_value

## XZ 平面投影：绕 Y 旋转 rotation_deg 后按 card_size 归一化并居中（+0.5）。
static func project_uv(local: Vector3, card_size: Vector2, rotation_deg: float) -> Vector2:
	var a := deg_to_rad(rotation_deg)
	var c := cos(a)
	var s := sin(a)
	var x := local.x * c - local.z * s
	var z := local.x * s + local.z * c
	return Vector2(x / maxf(card_size.x, 0.0001) + 0.5, z / maxf(card_size.y, 0.0001) + 0.5)

## 顶面↔侧面混合权重：法线越朝上越接近 1。
static func side_blend(normal_y: float, edge_softness: float) -> float:
	var e := maxf(edge_softness, 0.0001)
	return smoothstep(0.0, e, clampf(normal_y, 0.0, 1.0))

## 层高 AO：y=model_height→1（顶层不压暗），y=0→1-layer_ao。
static func layer_ao_factor(y: float, model_height: float, layer_ao: float) -> float:
	var depth := 1.0 - clampf(y / maxf(model_height, 0.0001), 0.0, 1.0)
	return 1.0 - layer_ao * depth

## 端到端：返回 {uv, tile_uv, side, ao}。
static func compose(local: Vector3, normal: Vector3, cfg: Dictionary) -> Dictionary:
	var size := cfg["project_card_size"] as Vector2
	var li := layer_index(local.y, cfg["layer_height"])
	var off := layer_offset(li, cfg["layer_offset"], cfg["layer_shuffle"])
	var uv := project_uv(local, size, cfg["rotation_deg"]) + off
	var tile_uv := uv
	if bool(cfg["tile"]):
		tile_uv = Vector2(fposmod(uv.x, 1.0), fposmod(uv.y, 1.0))
	return {
		"uv": uv,
		"tile_uv": tile_uv,
		"side": side_blend(normal.y, cfg["edge_softness"]),
		"ao": layer_ao_factor(local.y, cfg["model_height"], cfg["layer_ao"]),
	}
