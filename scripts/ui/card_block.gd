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

## 翻牌半程时长（水平翻转：scale.x 1→0 换面 →0→1），与 2D `flip_to_face` 同策略。
const FLIP_DURATION := 0.25

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
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
		add_child(glow)
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
	add_child(_mesh)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.0025
	_label.font_size = 96
	_label.position = Vector3(0.0, Table3dLayout.BLOCK_SIZE.y * 0.5 + 0.08, 0.0)
	add_child(_label)
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

## 设置槽位内容（立即生效、打断在途翻牌）。
func setup(slot: Dictionary) -> void:
	_build()
	_kill_flip()
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

## 瞬时揭示：水平翻转到 card 正面；color.a>0 时用该色**边缘发光**（保留牌面），否则回当前高亮。
## 用 restore() 翻回最近 setup(slot)。
func reveal(card: Dictionary, color := Color(0, 0, 0, 0)) -> void:
	_build()
	_flip_to(func(): _show_face(card, color))

## 回到最近一次 setup(slot) 的状态（标签 + 贴图/颜色 + 高亮），水平翻转回去。
func restore() -> void:
	_build()
	_flip_to(func(): _apply_slot(_last_slot))

## 翻牌中点：切到 card 正面。
func _show_face(card: Dictionary, color: Color) -> void:
	_label.text = card_text(card)
	_showing_back = false
	var face := _face_texture(card)
	_material.albedo_texture = face
	_material.albedo_color = Color.WHITE if face != null else Table3dLayout.known_color_for_rank(str(card.get("rank", "")))
	if color.a > 0.0:
		_apply_glow_layers(color)
	else:
		_paint_glow()

## 水平翻转（scale.x 1→0 → mid() 换面 →0→1），与 2D 同策略。不在树内则直接执行。
func _flip_to(mid: Callable) -> void:
	_kill_flip()
	if not is_inside_tree():
		mid.call()
		return
	_flip_tween = create_tween()
	_flip_tween.tween_property(self, "scale:x", 0.0, FLIP_DURATION)
	_flip_tween.tween_callback(mid)
	_flip_tween.tween_property(self, "scale:x", 1.0, FLIP_DURATION)

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
		_material.albedo_texture = _back_texture()
		_material.albedo_color = Color.WHITE
	else:
		_showing_back = false
		var face := _face_texture(card)
		_material.albedo_texture = face
		_material.albedo_color = Color.WHITE if face != null else Table3dLayout.slot_color(_last_slot)
	_paint_glow()

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

func block_color() -> Color:
	return _material.albedo_color if _material != null else Color.BLACK

func albedo_texture() -> Texture2D:
	return _material.albedo_texture if _material != null else null

## 当前是否有边缘发光，及其基色（rgb；a 为 0/1 表示开关）。
func has_glow() -> bool:
	return _glow_base.a > 0.0

func glow_color() -> Color:
	return _glow_base

## 当前是否使用卡背贴图（未知牌）。
func has_back_texture() -> bool:
	return _material != null and _material.albedo_texture != null and _showing_back

## 当前是否使用真实牌面贴图（已知牌且贴图可用）。
func has_face_texture() -> bool:
	return _material != null and _material.albedo_texture != null and not _showing_back
