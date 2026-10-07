class_name Table3dLayout
extends RefCounted
## 3D 桌面只读预览的纯布局数学（Milestone 1）
## 职责：座位角度、槽位网格坐标、已知牌分类色、尺寸常量。
## 纯函数、无节点依赖 → headless 可测。

const BLOCK_SIZE := Vector3(0.7, 0.04, 1.0)   # 平铺桌面：X 宽 × Y 厚 × Z 深
const BLOCK_GAP := Vector3(0.06, 0.0, 0.06)
const TABLE_RADIUS := 3.8  # 桌面半边长（场景 Table 网格 7×7）×2 前基准
const SEAT_RADIUS := 3.0
const TABLE_HEIGHT := 1.0  # 桌面世界高度（玩家腰/手高度）；机器人脚在 y=0，故桌子在腰间
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

## 座位角度（度，0°=近侧 +Z）。**按 seat_id 固定**：seat0=0°、seat1=270°、seat2=90°、
## seat3=180°（见 `seat_angle()`）——所有客户端世界坐标一致，观看者总把自己的座位放在相机处
## （视觉上仍是"自己近侧"），这样同步来的世界注视方向才能被一致解释（否则会镜像）。
## `seat_angles(count)` 仅用于需要"按序取前 N 个角度"的展示（沙盒/纯函数），不参与座位分配。
const ANGLE_ORDER := [0.0, 270.0, 90.0, 180.0]

static func seat_angles(count: int) -> Array:
	var angles: Array = []
	if count <= 0:
		return angles
	for i in mini(count, ANGLE_ORDER.size()):
		angles.append(float(ANGLE_ORDER[i]))
	return angles

## 固定座位角度（按 seat_id，与观看者无关）→ 所有客户端共享同一世界坐标。
## seat0=0°(近侧 +Z)、seat1=270°、seat2=90°、seat3=180°。观看者总把自己的座位放到
## 相机处，故视觉上仍是"自己近侧"，但世界坐标一致（同步注视方向才能被一致解释）。
static func seat_angle(seat_id: int) -> float:
	if seat_id < 0:
		return 0.0
	return float(ANGLE_ORDER[seat_id % ANGLE_ORDER.size()])

## 槽位 -> 网格坐标（列, 行）：主牌 4 张 2×2（与 2D 同：0/1 上排、2/3 下排，
## 故开局揭示的 2/3 落在下排）；第 5+ 张（罚牌）向右追新列，每列先上格后下格：
## idx=i-4, 列=2+idx/2, 行=idx%2。row 0 = 远离自己（上/远），row 1 = 靠近自己（下/近）。
@warning_ignore("integer_division")
static func slot_grid_pos(slot_index: int) -> Vector2:
	if slot_index < 4:
		return Vector2(float(slot_index % 2), float(slot_index / 2))
	var idx := slot_index - 4
	return Vector2(float(2 + idx / 2), float(idx % 2))

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
