class_name DeckPile
extends Node3D
## 抽牌堆视觉：把 draw_count 张卡叠成一摞（每张＝薄卡边盒 + 顶面 back07 卡背），随抽牌变矮。
## 纯展示层：最上面那张仍由场景里的 Center/Deck（CardBlock，带卡背/光晕/拾取）充当。
## 供 table3d_view 依 draw_count 调用 set_count()。

const CARD_THICKNESS := 0.0035                  # 单张卡厚度（世界单位）
const EDGE_COLOR := Color(0.94, 0.95, 0.97)     # 卡片侧边（纸白）
const JITTER := 0.006                           # 每张极小错位，露出下层卡背，读作"一摞牌"
const BACK_TEX_PATH := "res://assets/Cards/back07.png"

var _count := -1
var _mesh: BoxMesh
var _edge_mat: StandardMaterial3D
var _back_mesh: PlaneMesh
var _back_mat: StandardMaterial3D
var _cards: Array = []
## 是否给每张卡的顶面贴卡背（抽牌堆 true；弃牌堆 false——正面朝上，顶牌由 CardBlock 显示正面）。
var with_back := true

func _ready() -> void:
	_ensure_res()

func _ensure_res() -> void:
	if _mesh != null:
		return
	_mesh = BoxMesh.new()
	_mesh.size = Vector3(Table3dLayout.BLOCK_SIZE.x, CARD_THICKNESS, Table3dLayout.BLOCK_SIZE.z)
	_edge_mat = StandardMaterial3D.new()
	_edge_mat.albedo_color = EDGE_COLOR
	_edge_mat.roughness = 0.55
	_back_mesh = PlaneMesh.new()
	_back_mesh.orientation = PlaneMesh.FACE_Y
	_back_mesh.size = Vector2(Table3dLayout.BLOCK_SIZE.x, Table3dLayout.BLOCK_SIZE.z)
	_back_mat = StandardMaterial3D.new()
	_back_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_back_mat.uv1_scale = Vector3(-1.0, -1.0, 1.0)
	_back_mat.uv1_offset = Vector3(1.0, 1.0, 0.0)
	_back_mat.albedo_texture = load(BACK_TEX_PATH)
	_back_mat.albedo_color = Color.WHITE

## 设置堆叠张数（仅在数量变化时重建）。
func set_count(n: int) -> void:
	_ensure_res()
	n = clampi(n, 0, KongRules.DECK_SIZE)
	if n == _count:
		return
	_count = n
	_rebuild()

func count() -> int:
	return maxi(_count, 0)

func card_nodes() -> int:
	return _cards.size()

## 堆顶高度（相对本节点基面）。
func top_height() -> float:
	return count() * CARD_THICKNESS

func _rebuild() -> void:
	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()
	for i in _count:
		var body := MeshInstance3D.new()
		body.name = "Card%d" % i
		body.mesh = _mesh
		body.material_override = _edge_mat
		body.position = Vector3(_jitter(i, 12.9898), (i + 0.5) * CARD_THICKNESS, _jitter(i, 78.233))
		if with_back:
			# 顶面卡背（露出下层错位卡背，读作一摞牌面朝下的牌）
			var back := MeshInstance3D.new()
			back.name = "Back"
			back.mesh = _back_mesh
			back.material_override = _back_mat
			back.position = Vector3(0.0, CARD_THICKNESS * 0.5 + 0.0002, 0.0)
			body.add_child(back)
		add_child(body)
		_cards.append(body)

func _jitter(i: int, seed: float) -> float:
	return (fposmod(sin(i * seed) * 43758.5453, 1.0) - 0.5) * JITTER
