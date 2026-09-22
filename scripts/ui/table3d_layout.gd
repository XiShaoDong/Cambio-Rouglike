class_name Table3dLayout
extends RefCounted
## 3D 桌面只读预览的纯布局数学（Milestone 1）
## 职责：座位角度、槽位网格坐标、已知牌分类色、尺寸常量。
## 纯函数、无节点依赖 → headless 可测。

const BLOCK_SIZE := Vector3(0.7, 0.04, 1.0)   # 平铺桌面：X 宽 × Y 厚 × Z 深
const BLOCK_GAP := Vector3(0.06, 0.0, 0.06)
const TABLE_RADIUS := 2.8
const SEAT_RADIUS := 2.4
const UNKNOWN_COLOR := Color(0.20, 0.20, 0.22)
const LOW_COLOR := Color(0.45, 0.55, 0.62)  # 2-6 灰蓝

const PICK_LAYER := 2
const PICK_MASK := 1 << (PICK_LAYER - 1)  # 2
const PICK_HEIGHT := 0.3  # 拾取盒高度（薄卡从斜角也易命中）
const ACTIONABLE_COLOR := Color(0.95, 0.82, 0.35)  # 可操作高亮（金）

const COLOR_BY_RANK := {
	"JOKER": Color(0.85, 0.25, 0.25),  # 红
	"A": Color(0.90, 0.78, 0.35),      # 金
	"K": Color(0.62, 0.45, 0.85),      # 紫
	"Q": Color(0.62, 0.45, 0.85),
	"J": Color(0.62, 0.45, 0.85),
	"10": Color(0.35, 0.60, 0.85),     # 蓝
	"9": Color(0.35, 0.60, 0.85),
	"8": Color(0.35, 0.60, 0.85),
	"7": Color(0.35, 0.60, 0.85),
}

## 座位角度（度）：viewer 恒为 0°（近侧，正对相机），其余沿圆均分。
static func seat_angles(count: int) -> Array:
	var angles: Array = []
	if count <= 0:
		return angles
	for i in count:
		angles.append(float(i) * 360.0 / float(count))
	return angles

## 槽位 -> 网格坐标（列, 行）：前 4 张 2×2（列=i%2, 行=i/2）；
## 第 5+ 张（罚牌）向上追加（idx=i-4, 列=idx%2, 行=-(1+idx/2)）。行向下为正。
@warning_ignore("integer_division")
static func slot_grid_pos(slot_index: int) -> Vector2:
	if slot_index < 4:
		return Vector2(float(slot_index % 2), float(slot_index / 2))
	var idx := slot_index - 4
	return Vector2(float(idx % 2), float(-(1 + idx / 2)))

## 已知牌分类色（仅展示区分）。
static func known_color_for_rank(rank: String) -> Color:
	if COLOR_BY_RANK.has(rank):
		return COLOR_BY_RANK[rank]
	return LOW_COLOR

## slot 字典 -> 方块颜色：含非空 "card" 用已知牌分类色，否则 UNKNOWN_COLOR。
static func slot_color(slot: Dictionary) -> Color:
	var card: Dictionary = slot.get("card", {})
	if card.is_empty():
		return UNKNOWN_COLOR
	return known_color_for_rank(str(card.get("rank", "")))
