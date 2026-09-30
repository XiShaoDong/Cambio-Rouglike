class_name CardBlock
extends Node3D
## 3D 卡牌方块视图（Milestone 1 只读预览 + Milestone 2 拾取/高亮/瞬时揭示）
## 职责：方块 + Label3D 展示 slot；提供拾取标记、可操作高亮、瞬时揭示。
## 纯展示层：不做规则/隐私判断（已知/未知由快照 slot 是否含 "card" 决定）。
## 高亮/炫光：与 2D 同策略——只在卡牌**周围**发光（多层半透明外扩平面垫在卡面下），
## 不整牌染色/自发光，避免遮住牌面。

const PROTECTED_COLOR := Color(0.62, 0.35, 0.85)
const BACK_TEXTURE_PATH := "res://assets/Cards/back07.png"
const CARD_DIR := "res://assets/Cards/"
const SUIT_FILE := {"♠": "spades", "♥": "hearts", "♣": "clubs", "♦": "diamonds"}
const RANK_FILE := {"A": "ace", "J": "jack", "Q": "queen", "K": "king", "10": "10"}

## 外发光层：{grow=相对卡边的外扩距离, alpha=该层不透明度}，从外到内。
const GLOW_LAYERS := [
	{"grow": 0.10, "alpha": 0.15},
	{"grow": 0.06, "alpha": 0.25},
	{"grow": 0.03, "alpha": 0.40},
]

static var _back_tex: Texture2D = null
static var _face_cache := {}

var _built := false
var _visual: Node3D
var _flip: Node3D
var _back_node: MeshInstance3D
var _back_material: StandardMaterial3D
var _mesh: MeshInstance3D
var _label: Label3D
var _material: StandardMaterial3D
var _area: Area3D
var _pick_shape: CollisionShape3D
var _last_slot: Dictionary = {}
var _actionable := false
var _pick_enabled := true
var _showing_back := true
var _glow_nodes: Array = []      # [{node: MeshInstance3D, mat: StandardMaterial3D, alpha: float}]
var _glow_base := Color(0, 0, 0, 0)
var _flash_color := Color(0, 0, 0, 0)
var _hovered := false
var _hover_color := Color(0.7, 0.95, 1.0)
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
	# 外发光层：垫在卡面下方、略大的平面，仅在卡边露出（随卡朝向/朝向一致）。
	for i in GLOW_LAYERS.size():
		var spec: Dictionary = GLOW_LAYERS[i]
		var grow := float(spec["grow"])
		var glow := MeshInstance3D.new()
		glow.name = "Glow%d" % i
		var gplane := PlaneMesh.new()
		gplane.orientation = PlaneMesh.FACE_Y
		gplane.size = Vector2(
			Table3dLayout.BLOCK_SIZE.x + grow * 2.0,
			Table3dLayout.BLOCK_SIZE.z + grow * 2.0)
		glow.mesh = gplane
		glow.position = Vector3(0.0, -0.002 * float(i + 1), 0.0)
		var gmat := StandardMaterial3D.new()
		gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		gmat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
		glow.material_override = gmat
		glow.visible = false
		_visual.add_child(glow)
		_glow_nodes.append({"node": glow, "mat": gmat, "alpha": float(spec["alpha"])})
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
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.0025
	_label.font_size = 96
	_label.position = Vector3(0.0, Table3dLayout.BLOCK_SIZE.y * 0.5 + 0.08, 0.0)
	_flip.add_child(_label)
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

## 应用槽位内容（不动画/不打断 tween，供翻牌中点回调复用）。
func _apply_slot(slot: Dictionary) -> void:
	_last_slot = slot
	_flash_color = Color(0, 0, 0, 0)
	var card: Dictionary = slot.get("card", {})
	_label.text = "" if card.is_empty() else card_text(card)
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

## 可操作高亮（金色边缘发光）。
func set_actionable(on: bool) -> void:
	_build()
	_actionable = on
	_paint_glow()

## 准星悬停高亮（青色边缘发光；有更强状态时被覆盖）。
func set_hover(on: bool, color := Color(0.7, 0.95, 1.0)) -> void:
	_build()
	_hovered = on
	_hover_color = color
	_paint_glow()

## 揭示翻转到 card（写到底面板，几何连续换面）；color.a>0 时用该色边缘发光。
## from_p 为起始翻转进度：0（默认）= 从背面播放完整翻转；>0 用于跨 render 重放时**续播**
## （=1 直接呈现正面、不再翻转），避免状态广播/落地刷新把揭示重播一次（翻完又翻）。
func reveal(card: Dictionary, color := Color(0, 0, 0, 0), from_p := 0.0) -> void:
	_build()
	_back_material.albedo_texture = _face_texture(card) if not card.is_empty() else _back_texture()
	_back_material.albedo_color = Color.WHITE
	_back_is_back = card.is_empty()
	_label.text = card_text(card)
	if color.a > 0.0:
		_apply_glow_layers(color)
	else:
		_paint_glow()
	if from_p <= 0.0:
		_reveal_to(1.0)
	else:
		_reveal_from(clampf(from_p, 0.0, 1.0))

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
	var card: Dictionary = _last_slot.get("card", {})
	_label.text = "" if card.is_empty() else card_text(card)
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
		_label.text = ""
		_paint_glow()
	else:
		_apply_slot(_last_slot)

## 按优先级决定边缘发光颜色：flash > protected > actionable > hover。
func _paint_glow() -> void:
	if _flash_color.a > 0.0:
		_apply_glow_layers(_flash_color)
	elif bool(_last_slot.get("protected", false)):
		_apply_glow_layers(PROTECTED_COLOR)
	elif _actionable:
		_apply_glow_layers(Table3dLayout.ACTIONABLE_COLOR)
	elif _hovered:
		_apply_glow_layers(_hover_color)
	else:
		_apply_glow_layers(Color(0, 0, 0, 0))

## color.a<=0 关闭；否则每层用自身 alpha，颜色取 color.rgb。
func _apply_glow_layers(color: Color) -> void:
	_glow_base = color
	var on := color.a > 0.0
	for g in _glow_nodes:
		var node: MeshInstance3D = g["node"]
		node.visible = on
		if on:
			var mat: StandardMaterial3D = g["mat"]
			mat.albedo_color = Color(color.r, color.g, color.b, float(g["alpha"]))

static func _back_texture() -> Texture2D:
	if _back_tex == null:
		_back_tex = load(BACK_TEXTURE_PATH)
	return _back_tex

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

func _process(_delta: float) -> void:
	_apply_hover_pose()
	_apply_flip_pose()
	var hb := _hover_tween != null and _hover_tween.is_valid()
	var fb := _flip_tween != null and _flip_tween.is_valid()
	if not hb and not fb and _hover_p <= 0.0 and _reveal_p <= 0.0:
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
