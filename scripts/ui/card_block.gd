class_name CardBlock
extends Node3D
## 3D 卡牌方块视图（Milestone 1 只读预览 + Milestone 2 拾取/高亮/瞬时揭示）
## 职责：方块 + Label3D 展示 slot；提供拾取标记、可操作高亮、瞬时揭示。
## 纯展示层：不做规则/隐私判断（已知/未知由快照 slot 是否含 "card" 决定）。
## 高亮/炫光：与 2D 同策略——只在卡牌**周围**发光（多层半透明外扩平面垫在卡面下），
## 不整牌染色/自发光，避免遮住牌面。

const PROTECTED_COLOR := Color(0.62, 0.35, 0.85)
const BACK_TEXTURE_PATH := "res://assets/Cards/back07.png"
const PEEK_HIDDEN_TEXTURE_PATH := "res://assets/Cards/peek_hidden.svg"  # 他人 peek 时的"黑底闭眼"占位面
const CARD_DIR := "res://assets/Cards/"
const SUIT_FILE := {"♠": "spades", "♥": "hearts", "♣": "clubs", "♦": "diamonds"}
const RANK_FILE := {"A": "ace", "J": "jack", "Q": "queen", "K": "king", "10": "10"}

## 外发光：单层圆角矩形（{grow=相对卡边的外扩距离, alpha=不透明度}）。
const GLOW_LAYERS := [
	{"grow": 0.06, "alpha": 0.45},
]
const GLOW_RADIUS := 0.09            # 外发光圆角半径

## 炫光呼吸闪烁（作用于所有炫光态：黄/红/绿/紫）。从**全灭(0)**到**最亮(AMP)**。
const GLOW_FLICKER_AMP := 1.0
const GLOW_FLICKER_SPEED := 2.0      # 角速度 rad/s

## hover 外延虚线边框（卡外一圈虚线；颜色由 table3d_view 按状态给）。
const BORDER_WHITE := Color(1.0, 1.0, 1.0, 0.9)
const BORDER_GAP := 0.06             # 边框距卡边外扩（贴近卡边）
const BORDER_T := 0.018              # 线粗
const BORDER_DASH_MIN := 0.025       # dash 长度下限（手绘感：长短不一）
const BORDER_DASH_MAX := 0.085       # dash 长度上限
const BORDER_SPACE := 0.04           # 段基准间隙
const BORDER_Y := 0.006              # 离桌面（位于卡外，不被遮挡）
const BORDER_RADIUS := 0.09          # 边框圆角半径
const BORDER_STEP := 0.01            # 路径采样步长
const BORDER_GAP_VARY := 0.20        # 间隙 ±20%
const BORDER_SEED := 20261016        # 固定随机种子（每帧/每次重建一致）
const BORDER_CAP := true             # 段端极轻微圆头

static var _back_tex: Texture2D = null
static var _peek_hidden_tex: Texture2D = null
static var _face_cache := {}

var _built := false
var _visual: Node3D
var _flip: Node3D
var _back_node: MeshInstance3D
var _back_material: StandardMaterial3D
var _mesh: MeshInstance3D
var _label: Label3D
var _label_shadow: Label3D
var _bomb_badge: Sprite3D
var _bomb_on := false
var _material: StandardMaterial3D
var _area: Area3D
var _pick_shape: CollisionShape3D
var _last_slot: Dictionary = {}
var _reveal_known: Dictionary = {}   # 临时揭示的牌面（看牌/贴牌），供 hover 气泡读取
var _actionable := false
var _actionable_color := Table3dLayout.ACTIONABLE_COLOR
var _pick_enabled := true
var _showing_back := true
var _glow_nodes: Array = []      # [{node: MeshInstance3D, mat: StandardMaterial3D, alpha: float}]
var _glow_base := Color(0, 0, 0, 0)
var _flash_color := Color(0, 0, 0, 0)
var _reveal_color := Color(0, 0, 0, 0)   # 揭示炫光色（绿/红/蓝），优先于 actionable/hover
var _upright := false
var _border_mesh: MeshInstance3D
var _border_mat: StandardMaterial3D
var _show_border := false
var _border_color := BORDER_WHITE
const BORDER_LOCKED := Color(1.0, 0.42, 0.47, 0.95)  # 结算贴牌窗口锁死：红色虚线框
var _locked_dash := false
var _border_offset_y := 0.0     # 边框相对卡面的额外高度（如抽牌堆要压到牌堆底部）
var _glow_t := 0.0
var _glow_on := false
var _flip_tween: Tween = null
static var _anim_cfg: CardAnimationConfig = null
var hover_anim_enabled := false
var _hover_p := 0.0
var _ray_local := Vector2.ZERO
var _hover_tween: Tween = null
var _reveal_p := 0.0
var _front_is_back := true
var _back_is_back := true

## 揭示 3D 翻转总时长（抬起+倾斜+绕长轴 180° 的整段）。调大 = 更慢。
const FLIP_DURATION := 0.5

## 点数标签：抬离牌面 + 一层深色底部投影，营造"悬浮在牌上"的立体感。
const LABEL_LIFT := 0.16
const LABEL_SHADOW_OFFSET := Vector3(0.03, -0.035, 0.03)
const LABEL_SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.35)

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	# 视觉 pivot：hover 位移/旋转作用于它；拾取 Area3D 留在根，不随动画移动。
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	# 揭示 pivot：绕卡长轴旋转 + 抬起 + 朝玩家倾斜（与 hover 的 _visual 分节点）。
	_flip = Node3D.new()
	_flip.name = "Flip"
	_visual.add_child(_flip)
	# 外发光：单层圆角矩形（垫在卡面下、仅在卡边露出圆角外圈）。
	var spec: Dictionary = GLOW_LAYERS[0]
	var grow := float(spec["grow"])
	var glow := MeshInstance3D.new()
	glow.name = "Glow0"
	var gim := ImmediateMesh.new()
	gim.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_rounded_fill(gim, Table3dLayout.BLOCK_SIZE.x * 0.5 + grow, Table3dLayout.BLOCK_SIZE.z * 0.5 + grow, GLOW_RADIUS)
	gim.surface_end()
	glow.mesh = gim
	glow.position = Vector3(0.0, -0.002, 0.0)
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	gmat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	glow.material_override = gmat
	glow.visible = false
	_visual.add_child(glow)
	_glow_nodes.append({"node": glow, "mat": gmat, "alpha": float(spec["alpha"])})
	_build_border()
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	# 卡面用平面（UV 完整 0–1）。BoxMesh 的 UV 是十字展开，顶面只采样一条线 → 贴图被裁。
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Y
	plane.size = Vector2(Table3dLayout.BLOCK_SIZE.x, Table3dLayout.BLOCK_SIZE.z)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	_mesh.mesh = plane
	_material = StandardMaterial3D.new()
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # 两面可见，避免看到背面消失
	# PlaneMesh(FACE_Y)：u=0 在本地 -X、v=0 在本地 -Z；座位本地 +X = 持有者左侧、
	# +Z = 朝桌心（远离持有者）。故 UV 绕中心旋转 180°（U、V 都翻），
	# 使图案顶部朝桌心、左侧在持有者左手侧 → 持有者看为正、不镜像。
	_material.uv1_scale = Vector3(-1.0, -1.0, 1.0)
	_material.uv1_offset = Vector3(1.0, 1.0, 0.0)
	_mesh.material_override = _material
	_mesh.position = Vector3(0.0, 0.002, 0.0)
	_flip.add_child(_mesh)
	# 背面板：同样"正面朝上"，预旋 180° 绕 Z（净 360° → 翻面后正向不镜像）。
	_back_node = MeshInstance3D.new()
	_back_node.name = "Back"
	var bplane := PlaneMesh.new()
	bplane.orientation = PlaneMesh.FACE_Y
	bplane.size = Vector2(Table3dLayout.BLOCK_SIZE.x, Table3dLayout.BLOCK_SIZE.z)
	_back_node.mesh = bplane
	_back_node.position = Vector3(0.0, -0.002, 0.0)
	_back_node.rotation_degrees = Vector3(0.0, 0.0, 180.0)
	_back_material = StandardMaterial3D.new()
	_back_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_back_material.uv1_scale = Vector3(-1.0, -1.0, 1.0)
	_back_material.uv1_offset = Vector3(1.0, 1.0, 0.0)
	_back_material.albedo_texture = _back_texture()
	_back_material.albedo_color = Color.WHITE
	_back_node.material_override = _back_material
	_flip.add_child(_back_node)
	_label_shadow = Label3D.new()
	_label_shadow.name = "LabelShadow"
	_label_shadow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label_shadow.no_depth_test = true
	_label_shadow.pixel_size = 0.0025
	_label_shadow.font_size = 96
	_label_shadow.modulate = LABEL_SHADOW_COLOR
	_label_shadow.position = Vector3(0.0, Table3dLayout.BLOCK_SIZE.y * 0.5 + LABEL_LIFT, 0.0) + LABEL_SHADOW_OFFSET
	_flip.add_child(_label_shadow)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.0025
	_label.font_size = 96
	_label.position = Vector3(0.0, Table3dLayout.BLOCK_SIZE.y * 0.5 + LABEL_LIFT, 0.0)
	_flip.add_child(_label)
	# 炸弹角标（随机增强）：卡牌右上角，billboard 始终朝向相机。
	_bomb_badge = Sprite3D.new()
	_bomb_badge.name = "BombBadge"
	_bomb_badge.texture = BombIcon.texture(64)
	_bomb_badge.pixel_size = 0.0028
	_bomb_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bomb_badge.no_depth_test = true
	_bomb_badge.position = Vector3(-Table3dLayout.BLOCK_SIZE.x * 0.5 + 0.13, 0.06,
		Table3dLayout.BLOCK_SIZE.z * 0.5 - 0.13)
	_bomb_badge.visible = false
	_visual.add_child(_bomb_badge)
	# 拾取标记：独立物理层，仅用于射线拾取
	_area = Area3D.new()
	_area.name = "PickArea"
	var shape := CollisionShape3D.new()
	var pick_box := BoxShape3D.new()
	pick_box.size = Vector3(Table3dLayout.BLOCK_SIZE.x, Table3dLayout.PICK_HEIGHT, Table3dLayout.BLOCK_SIZE.z)
	shape.shape = pick_box
	_pick_shape = shape
	_area.add_child(shape)
	_area.collision_layer = Table3dLayout.PICK_MASK
	_area.collision_mask = 0
	add_child(_area)
	set_process(false)

## 设置槽位内容（立即生效、打断在途翻牌）。
func setup(slot: Dictionary) -> void:
	_build()
	_kill_flip()
	_reveal_p = 0.0
	_reveal_color = Color(0, 0, 0, 0)
	_reveal_known = {}
	if _flip != null:
		_flip.transform = Transform3D.IDENTITY
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null
	_hover_p = 0.0
	_ray_local = Vector2.ZERO
	if _visual != null:
		_visual.transform = Transform3D.IDENTITY
	scale = Vector3.ONE
	_apply_slot(slot)

## 显示/隐藏右上角炸弹角标（公开炸弹标记，不涉及牌面）。
func set_bomb(on: bool) -> void:
	_bomb_on = on
	if _bomb_badge != null and is_instance_valid(_bomb_badge):
		_bomb_badge.visible = on

func has_bomb() -> bool:
	return _bomb_on

## 应用槽位内容（不动画/不打断 tween，供翻牌中点回调复用）。
func _apply_slot(slot: Dictionary) -> void:
	_last_slot = slot
	_flash_color = Color(0, 0, 0, 0)
	var card: Dictionary = slot.get("card", {})
	_set_label_text("" if card.is_empty() else card_text(card))
	set_bomb(bool(slot.get("bomb", false)) or bool(card.get("bomb", false)))
	_apply_color()

## 设置拾取元数据（{"kind":"slot","seat":..,"slot":..} 或 hud/deck/...）。
func set_pick(meta: Dictionary) -> void:
	_build()
	_area.set_meta("pick", meta)

func pick_meta() -> Dictionary:
	if _area == null:
		return {}
	return _area.get_meta("pick", {})

## 启用/禁用拾取（隐藏的卡不应被准星命中）。
func set_pick_enabled(on: bool) -> void:
	_build()
	if _pick_shape != null:
		_pick_shape.disabled = not on
	_pick_enabled = on

func is_pick_enabled() -> bool:
	return _pick_enabled

## 可操作高亮（默认金色边缘发光）。
func set_actionable(on: bool) -> void:
	_build()
	_actionable = on
	_paint_glow()

## 可操作高亮的颜色（如弃牌堆"用能力"用橙色、取弃牌顶用金色）。
func set_actionable_color(c: Color) -> void:
	_actionable_color = c
	if _actionable:
		_paint_glow()

## 准星悬停反馈：卡外一圈虚线边框（颜色由 table3d_view 按状态给：白/绿/红）。
## 注意：hover 不再驱动炫光（炫光留给 黄=可用 / 红·绿=贴牌对错 / 紫=护盾 提示）。
func set_hover(on: bool, color := BORDER_WHITE) -> void:
	_build()
	_show_border = on
	_border_color = color
	_apply_border()

## 该卡当前是否可操作（供 table3d_view 决定 hover 边框红/绿）。
func is_actionable() -> bool:
	return _actionable

## 结算贴牌窗口锁锁死态：常驻红色虚线框（不受 hover 影响；settle 结束时恢复）。
func set_locked_dash(on: bool) -> void:
	_build()
	_locked_dash = on
	_border_color = BORDER_LOCKED if on else BORDER_WHITE
	_apply_border()

## 当前"对该 viewer 已知"的牌面（槽位公开牌 或 临时揭示牌）；未知返回 {}。
func known_card() -> Dictionary:
	var slot_card: Dictionary = _last_slot.get("card", {})
	if not slot_card.is_empty():
		return slot_card
	return _reveal_known

## hover 虚线边框是否存在。
func has_border() -> bool:
	return _border_mesh != null and _border_mesh.visible

func border_color() -> Color:
	return _border_color

## 揭示翻转到 card（写到底面板，几何连续换面）；color.a>0 时用该色边缘发光。
## from_p 为起始翻转进度：0（默认）= 从背面播放完整翻转；>0 用于跨 render 重放时**续播**
## （=1 直接呈现正面、不再翻转），避免状态广播/落地刷新把揭示重播一次（翻完又翻）。
func reveal(card: Dictionary, color := Color(0, 0, 0, 0), from_p := 0.0) -> void:
	_build()
	_back_material.albedo_texture = _face_texture(card) if not card.is_empty() else _back_texture()
	_back_material.albedo_color = Color.WHITE
	_back_is_back = card.is_empty()
	_set_label_text(card_text(card))
	set_bomb(bool(card.get("bomb", false)) or bool(_last_slot.get("bomb", false)))
	_reveal_known = card.duplicate() if not card.is_empty() else {}
	_reveal_color = color
	_paint_glow()
	if from_p <= 0.0:
		_reveal_to(1.0)
	else:
		_reveal_from(clampf(from_p, 0.0, 1.0))

## 他人 peek 占位揭示：翻到"黑底闭眼"面（不显示牌面/点数），可带颜色边缘光晕。
## 用于 7/8/9/10/Q 看牌时向其他玩家表达"此牌正被人看"，比单纯蓝光更明显。
func reveal_hidden(color := Color(0, 0, 0, 0), from_p := 0.0) -> void:
	_build()
	_reveal_known = {}
	_back_material.albedo_texture = _peek_hidden_texture()
	_back_material.albedo_color = Color.WHITE
	_back_is_back = false
	_set_label_text("")
	_reveal_color = color
	_paint_glow()
	if from_p <= 0.0:
		_reveal_to(1.0)
	else:
		_reveal_from(clampf(from_p, 0.0, 1.0))

## 从 from_p 继续翻动到 target（0=背面 / 1=正面）。用于 Q hold 释放的翻回：
## render 重建后按已过时间算出当前进度，再续播到背面（跨 render 不重播、不瞬切）。
## target<=0 时结束不保留揭示炫光（`_reveal_color` 置空）。
func reveal_from_to(card: Dictionary, color: Color, from_p: float, target: float) -> void:
	_build()
	_back_material.albedo_texture = _face_texture(card) if not card.is_empty() else _back_texture()
	_back_material.albedo_color = Color.WHITE
	_back_is_back = card.is_empty()
	_set_label_text(card_text(card))
	_reveal_color = Color(0, 0, 0, 0) if target <= 0.0 else color
	_paint_glow()
	_kill_flip()
	_reveal_p = clampf(from_p, 0.0, 1.0)
	_apply_flip_pose()
	if is_inside_tree() and not is_equal_approx(_reveal_p, target):
		set_process(true)
		_flip_tween = create_tween()
		_flip_tween.tween_property(self, "_reveal_p", target, absf(target - _reveal_p) * FLIP_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

## 从给定进度续播到正面（from_p>=1 直接落位、不翻）。
func _reveal_from(from_p: float) -> void:
	_kill_flip()
	_reveal_p = from_p
	_apply_flip_pose()
	if from_p < 1.0 and is_inside_tree():
		set_process(true)
		_flip_tween = create_tween()
		_flip_tween.tween_property(self, "_reveal_p", 1.0, (1.0 - from_p) * FLIP_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

## 翻回最近一次 setup(slot) 的状态（贴图/标签/高亮）。
func restore() -> void:
	_build()
	_reveal_color = Color(0, 0, 0, 0)
	_reveal_known = {}
	var card: Dictionary = _last_slot.get("card", {})
	_set_label_text("" if card.is_empty() else card_text(card))
	_paint_glow()
	_reveal_to(0.0)

func _reveal_to(target: float) -> void:
	_kill_flip()
	if not is_inside_tree():
		_reveal_p = target
		_apply_flip_pose()
		return
	set_process(true)
	_flip_tween = create_tween()
	_flip_tween.tween_property(self, "_reveal_p", target, FLIP_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

## 揭示翻转姿态：绕长轴 0→180° + 抬起 + 朝玩家倾斜（sin 包络，末了回平）。
func _apply_flip_pose() -> void:
	if _flip == null:
		return
	if _reveal_p <= 0.0:
		_flip.transform = Transform3D.IDENTITY
		return
	var cfg := _cfg()
	var arc := sin(_reveal_p * PI)
	var basis := Basis.from_euler(Vector3(-deg_to_rad(cfg.hover_pitch * arc), 0.0, 0.0)) \
			* Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(_reveal_p * 180.0))
	_flip.transform = Transform3D(basis, Vector3(0.0, cfg.flip_lift * arc, 0.0))

func reveal_progress() -> float:
	return _reveal_p

func _kill_flip() -> void:
	if _flip_tween != null and _flip_tween.is_valid():
		_flip_tween.kill()
	_flip_tween = null

## 短暂边缘发光（不改标签/牌面），dur 秒后恢复。
func flash(color: Color, dur: float) -> void:
	_build()
	_flash_color = color
	_paint_glow()
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(self):
			_flash_color = Color(0, 0, 0, 0)
			_paint_glow())

## 未知牌（无 "card"）用卡背贴图；已知牌用真实牌面（original 旧素材 / 图集）。
## 贴图缺失时回退分类色，保证仍可辨识。
func _apply_color() -> void:
	var card: Dictionary = _last_slot.get("card", {})
	if card.is_empty():
		_showing_back = true
		_front_is_back = true
		_material.albedo_texture = _back_texture()
		_material.albedo_color = Color.WHITE
	else:
		_showing_back = false
		_front_is_back = false
		var face := _face_texture(card)
		_material.albedo_texture = face
		_material.albedo_color = Color.WHITE if face != null else Table3dLayout.slot_color(_last_slot)
	if _back_material != null and _reveal_p <= 0.0:
		_back_material.albedo_texture = _back_texture()
		_back_material.albedo_color = Color.WHITE
		_back_is_back = true
	_paint_glow()

## 切换显示面：back=true 显示卡背并隐藏点数；false 恢复最近 setup(slot) 的正面。
## 供 CardAnimation 控制器独占的真实 3D 翻牌使用（不触发自带 scale.x 翻转）。
func show_back(back: bool) -> void:
	_build()
	if back:
		_showing_back = true
		_front_is_back = true
		_material.albedo_texture = _back_texture()
		_material.albedo_color = Color.WHITE
		_set_label_text("")
		_paint_glow()
	else:
		_apply_slot(_last_slot)

## 按优先级决定边缘发光颜色：flash > reveal（揭示绿/红/蓝）> protected > hover > actionable。
## reveal 最高（仅次于 flash）：贴牌对错炫光不被选中/hover/可点高亮覆盖（B38）。
## hover 高于 actionable：可点目标（金）在准星悬停时改显浅蓝，便于确认"是否对准了"（否则金光盖住蓝光无法确认选中）。
## 炫光优先级：flash > reveal > protected > actionable（hover 已改为虚线边框，不再走炫光）。
func _paint_glow() -> void:
	if _flash_color.a > 0.0:
		_apply_glow_layers(_flash_color)
	elif _reveal_color.a > 0.0:
		_apply_glow_layers(_reveal_color)
	elif bool(_last_slot.get("protected", false)):
		_apply_glow_layers(PROTECTED_COLOR)
	elif _actionable:
		_apply_glow_layers(_actionable_color)
	else:
		_apply_glow_layers(Color(0, 0, 0, 0))
	if _glow_base.a > 0.0:
		set_process(true)

## 呼吸闪烁系数：正弦，从 0（全灭）到 AMP（最亮）。
func _glow_pulse() -> float:
	return GLOW_FLICKER_AMP * 0.5 * (1.0 - cos(_glow_t * GLOW_FLICKER_SPEED))

## color.a<=0 关闭；否则每层用自身 alpha × 闪烁系数，颜色取 color.rgb。
func _apply_glow_layers(color: Color) -> void:
	var on := color.a > 0.0
	# 炫光从关闭→开启时直接置到最亮相位，避免"刚亮起时看起来没亮"（之后继续呼吸到全灭）。
	if on and not _glow_on:
		_glow_t = PI / GLOW_FLICKER_SPEED
	_glow_on = on
	_glow_base = color
	var pulse := _glow_pulse()
	for g in _glow_nodes:
		var node: MeshInstance3D = g["node"]
		node.visible = on
		if on:
			var mat: StandardMaterial3D = g["mat"]
			mat.albedo_color = Color(color.r, color.g, color.b, float(g["alpha"]) * pulse)

## hover 虚线边框：绕卡周 4 边生成小矩形 dash（ImmediateMesh），一次性构建。
func _build_border() -> void:
	_border_mesh = MeshInstance3D.new()
	_border_mesh.name = "HoverBorder"
	var im := ImmediateMesh.new()
	var hx := Table3dLayout.BLOCK_SIZE.x * 0.5 + BORDER_GAP
	var hz := Table3dLayout.BLOCK_SIZE.z * 0.5 + BORDER_GAP
	var t := BORDER_T * 0.5
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_dashed_ring(im, hx, hz, BORDER_RADIUS, t)
	im.surface_end()
	_border_mesh.mesh = im
	_border_mat = StandardMaterial3D.new()
	_border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_border_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_border_mat.albedo_color = BORDER_WHITE
	_border_mesh.material_override = _border_mat
	_border_mesh.position = Vector3(0.0, BORDER_Y + _border_offset_y, 0.0)
	_border_mesh.visible = false
	add_child(_border_mesh)

## 设置边框相对卡面的高度偏移（如抽牌堆把 dash line 压到牌堆底部：传 -堆高）。
func set_border_offset(dy: float) -> void:
	_border_offset_y = dy
	if _border_mesh != null and is_instance_valid(_border_mesh):
		_border_mesh.position = Vector3(0.0, BORDER_Y + dy, 0.0)

## 圆角矩形周长采样点（XZ 平面，顺时针，含 4 段圆角 + 4 条直边，间距≈step）。
static func _rounded_rect_samples(hx: float, hz: float, r: float, step: float) -> PackedVector2Array:
	var rr := clampf(r, 0.0, minf(hx, hz))
	var pts := PackedVector2Array()
	var corners := [
		[Vector2(hx - rr, -hz + rr), -PI * 0.5],
		[Vector2(hx - rr, hz - rr), 0.0],
		[Vector2(-hx + rr, hz - rr), PI * 0.5],
		[Vector2(-hx + rr, -hz + rr), PI],
	]
	var n := corners.size()
	for k in n:
		var cc: Vector2 = corners[k][0]
		var a0: float = corners[k][1]
		var arc_n := maxi(2, int(ceil((PI * 0.5 * rr) / step)))
		for i in range(arc_n + 1):
			var ang := a0 + (PI * 0.5) * float(i) / float(arc_n)
			pts.append(cc + Vector2(cos(ang), sin(ang)) * rr)
		var nc: Vector2 = corners[(k + 1) % n][0]
		var a1: float = corners[(k + 1) % n][1]
		var e0 := cc + Vector2(cos(a0 + PI * 0.5), sin(a0 + PI * 0.5)) * rr
		var e1 := nc + Vector2(cos(a1), sin(a1)) * rr
		var en := maxi(1, int(ceil(e0.distance_to(e1) / step)))
		for i in range(1, en):
			pts.append(e0.lerp(e1, float(i) / float(en)))
	return pts

## 填充圆角矩形（中心扇形三角化）。
func _emit_rounded_fill(im: ImmediateMesh, hx: float, hz: float, r: float) -> void:
	var path := _rounded_rect_samples(hx, hz, r, 0.04)
	for i in path.size():
		var a := path[i]
		var b := path[(i + 1) % path.size()]
		im.surface_add_vertex(Vector3(0.0, 0.0, 0.0))
		im.surface_add_vertex(Vector3(a.x, 0.0, a.y))
		im.surface_add_vertex(Vector3(b.x, 0.0, b.y))

## 沿「完整圆角矩形路径」按累计弧长 s 依次布 dash：dash 用多段折线跟随曲线（过弯连续），
## 长度/间隙/粗细轻微随机（固定种子，每帧一致），端部极轻微圆头。不整体抖动。
func _emit_dashed_ring(im: ImmediateMesh, hx: float, hz: float, r: float, half_t: float) -> void:
	var path := _rounded_rect_samples(hx, hz, r, BORDER_STEP)
	var n := path.size()
	if n < 2:
		return
	var cum := PackedFloat32Array()
	cum.resize(n + 1)
	cum[0] = 0.0
	for i in n:
		cum[i + 1] = cum[i] + path[i].distance_to(path[(i + 1) % n])
	var total := cum[n]
	var rng := RandomNumberGenerator.new()
	rng.seed = BORDER_SEED
	var s := 0.0
	while s < total - 0.001:
		var dash_len := rng.randf_range(BORDER_DASH_MIN, BORDER_DASH_MAX)
		var thick := half_t * rng.randf_range(0.9, 1.1)
		var e := minf(s + dash_len, total)
		_emit_path_strip(im, path, cum, s, e, thick)
		if BORDER_CAP:
			_emit_cap(im, _point_at_len(path, cum, s), thick)
			_emit_cap(im, _point_at_len(path, cum, e), thick)
		s = e + BORDER_SPACE * rng.randf_range(1.0 - BORDER_GAP_VARY, 1.0 + BORDER_GAP_VARY)

## 沿路径弧长 s 取点（线性插值）。
func _point_at_len(path: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	var n := path.size()
	var total := cum[n]
	s = clampf(s, 0.0, total)
	var i := 0
	while i < n - 1 and cum[i + 1] < s:
		i += 1
	var seg := cum[i + 1] - cum[i]
	var t := 0.0 if seg <= 0.0 else (s - cum[i]) / seg
	return path[i].lerp(path[(i + 1) % n], t)

## 弧长区间 [s0,s1] 的 dash：细分为折线，逐段出四边形（经过圆角时自动跟随曲线）。
func _emit_path_strip(im: ImmediateMesh, path: PackedVector2Array, cum: PackedFloat32Array, s0: float, s1: float, half_t: float) -> void:
	if s1 <= s0:
		return
	var steps := maxi(2, int(ceil((s1 - s0) / BORDER_STEP)))
	var prev := _point_at_len(path, cum, s0)
	for k in range(1, steps + 1):
		var s := lerpf(s0, s1, float(k) / float(steps))
		var cur := _point_at_len(path, cum, s)
		_emit_segment_quad(im, prev, cur, half_t)
		prev = cur

## 极轻微圆头（正八边形小圆盘，半径 = 线半宽）。
func _emit_cap(im: ImmediateMesh, c: Vector2, r: float) -> void:
	var seg := 8
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		im.surface_add_vertex(Vector3(c.x, 0.0, c.y))
		im.surface_add_vertex(Vector3(c.x + cos(a0) * r, 0.0, c.y + sin(a0) * r))
		im.surface_add_vertex(Vector3(c.x + cos(a1) * r, 0.0, c.y + sin(a1) * r))

## 单段 dash：p→q 沿线、垂直方向半宽 half_t 的矩形。
func _emit_segment_quad(im: ImmediateMesh, p: Vector2, q: Vector2, half_t: float) -> void:
	var dir := q - p
	if dir.length_squared() < 1e-9:
		return
	dir = dir.normalized()
	var nrm := Vector2(-dir.y, dir.x) * half_t
	var v0 := Vector3(p.x + nrm.x, 0.0, p.y + nrm.y)
	var v1 := Vector3(q.x + nrm.x, 0.0, q.y + nrm.y)
	var v2 := Vector3(q.x - nrm.x, 0.0, q.y - nrm.y)
	var v3 := Vector3(p.x - nrm.x, 0.0, p.y - nrm.y)
	im.surface_add_vertex(v0)
	im.surface_add_vertex(v1)
	im.surface_add_vertex(v2)
	im.surface_add_vertex(v0)
	im.surface_add_vertex(v2)
	im.surface_add_vertex(v3)

func _apply_border() -> void:
	if _border_mesh == null:
		return
	var on := (_show_border or _locked_dash) and _border_color.a > 0.0
	_border_mesh.visible = on
	if on:
		_border_mat.albedo_color = _border_color

static func _back_texture() -> Texture2D:
	if _back_tex == null:
		_back_tex = load(BACK_TEXTURE_PATH)
	return _back_tex

static func _peek_hidden_texture() -> Texture2D:
	if _peek_hidden_tex == null:
		_peek_hidden_tex = load(PEEK_HIDDEN_TEXTURE_PATH)
	return _peek_hidden_tex

## 真实牌面贴图：非 original 皮肤走 `CardAtlas`，original 走旧素材 assets/Cards/*.png；
## 均缺失时回退卡背。
func _face_texture(card: Dictionary) -> Texture2D:
	var rank := str(card.get("rank", ""))
	var suit := str(card.get("suit", ""))
	var type := str(card.get("type", CardAtlas.preview()))
	if type != CardAtlas.ORIGINAL:
		var atlas := CardAtlas.face(type, suit, rank)
		if atlas != null:
			return atlas
	var tex := _load_face(_original_face_path(suit, rank))
	return tex if tex != null else _back_texture()

static func _original_face_path(suit: String, rank: String) -> String:
	if rank == "JOKER":
		return CARD_DIR + ("Joker1.png" if suit == "red" else "Joker2.png")
	var suit_file: String = SUIT_FILE.get(suit, "spades")
	var rank_file: String = RANK_FILE.get(rank, "")
	if rank_file == "":
		rank_file = "0" + rank
	return CARD_DIR + "%s_%s.png" % [suit_file, rank_file]

static func _load_face(path: String) -> Texture2D:
	if _face_cache.has(path):
		return _face_cache[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_face_cache[path] = tex
	return tex

## 卡片显示文本（"A♥"；Joker 显示 "JOKER"；空卡空串）。
static func card_text(card: Dictionary) -> String:
	if card.is_empty():
		return ""
	var rank := str(card.get("rank", "?"))
	if rank == "JOKER":
		return "JOKER"
	return "%s%s" % [rank, str(card.get("suit", ""))]

func label_text() -> String:
	return _label.text if _label != null else ""

func shadow_text() -> String:
	return _label_shadow.text if _label_shadow != null else ""

## 当前显示面是否为"他人 peek 闭眼占位面"。
func is_peek_hidden() -> bool:
	var m := _display_material()
	return m != null and m.albedo_texture != null and m.albedo_texture == _peek_hidden_texture()

## 同步设置主标签与投影标签的文本。
func _set_label_text(text: String) -> void:
	if _label != null:
		_label.text = text
	if _label_shadow != null:
		_label_shadow.text = text

## 竖立显示模式：标签从卡面法向正上方（本地 +Y）改到卡高方向顶端（本地 +Z）。
## 仅用于竖立的大牌；默认关闭，不影响手牌/弃牌/飞牌等平铺卡。
func set_upright(on: bool) -> void:
	_build()
	_upright = on
	if _label == null:
		return
	if on:
		_label.position = Vector3(0.0, 0.0, Table3dLayout.BLOCK_SIZE.z * 0.5 + LABEL_LIFT)
	else:
		_label.position = Vector3(0.0, Table3dLayout.BLOCK_SIZE.y * 0.5 + LABEL_LIFT, 0.0)
	if _label_shadow != null:
		_label_shadow.position = _label.position + LABEL_SHADOW_OFFSET

## 视觉子节点（hover 位移/旋转作用于它；拾取盒在根，不受影响）。
func visual_node() -> Node3D:
	_build()
	return _visual

## 背面片（揭示翻面后朝上）。
func back_node() -> MeshInstance3D:
	_build()
	return _back_node

## 揭示翻转 pivot。
func flip_node() -> Node3D:
	_build()
	return _flip

static func _cfg() -> CardAnimationConfig:
	if _anim_cfg == null:
		_anim_cfg = CardAnimationConfig.new()
	return _anim_cfg

func hover_progress() -> float:
	return _hover_p

## hover 抬起/倾斜：on=true 抬到 hover 姿态，false 落回；immediate 直接置值不缓动（跨 render 重放用）。
func set_hover_pose(on: bool, ray_local: Vector2, immediate := false) -> void:
	_build()
	_ray_local = ray_local
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null
	var target := 1.0 if on else 0.0
	if immediate:
		_hover_p = target
		_apply_hover_pose()
		return
	if is_equal_approx(_hover_p, target):
		_apply_hover_pose()
		return
	var cfg := _cfg()
	var dur := cfg.hover_in_dur if on else cfg.hover_out_dur
	var trans := Tween.TRANS_BACK if on else Tween.TRANS_CUBIC
	if hover_anim_enabled:
		set_process(true)
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "_hover_p", target, dur).set_trans(trans).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	_glow_t += delta
	_apply_hover_pose()
	_apply_flip_pose()
	if _glow_base.a > 0.0:
		_apply_glow_layers(_glow_base)   # 每帧按闪烁系数重放炫光 alpha
	var hb := _hover_tween != null and _hover_tween.is_valid()
	var fb := _flip_tween != null and _flip_tween.is_valid()
	if not hb and not fb and _hover_p <= 0.0 and _reveal_p <= 0.0 and _glow_base.a <= 0.0:
		set_process(false)

## 用 compose 的位移/旋转驱动 `_visual`（不写 scale，避免与揭示翻转抢属性）。
func _apply_hover_pose() -> void:
	if _visual == null:
		return
	if _hover_p <= 0.0:
		_visual.transform = Transform3D.IDENTITY
		return
	var c := CardAnimationMath.compose(
		{"hover": _hover_p, "press": 0.0, "flip": 0.0, "land": 0.0},
		_cfg().to_dict(), 0.0, _ray_local)
	var rot: Vector3 = c["visual_rot_deg"]
	_visual.transform = Transform3D(
		Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z))),
		c["visual_pos"])

func _display_material() -> StandardMaterial3D:
	return _material if _reveal_p < 0.5 else _back_material

func _display_is_back() -> bool:
	return _front_is_back if _reveal_p < 0.5 else _back_is_back

func block_color() -> Color:
	var m := _display_material()
	return m.albedo_color if m != null else Color.BLACK

func albedo_texture() -> Texture2D:
	var m := _display_material()
	return m.albedo_texture if m != null else null

## 当前是否有边缘发光，及其基色（rgb；a 为 0/1 表示开关）。
func has_glow() -> bool:
	return _glow_base.a > 0.0

func glow_color() -> Color:
	return _glow_base

## 当前是否使用卡背贴图（未知牌）。
func has_back_texture() -> bool:
	var m := _display_material()
	return m != null and m.albedo_texture != null and _display_is_back()

## 当前是否使用真实牌面贴图（已知牌且贴图可用）。
func has_face_texture() -> bool:
	var m := _display_material()
	return m != null and m.albedo_texture != null and not _display_is_back()
