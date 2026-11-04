class_name PokerTableModel
extends Node3D
## 桌面模型（assets/3Dmodels/poker_table.blend）：
## - 剔除模型自带 Camera；隐藏装饰件（cards/chip/chips/Plane）
## - 为 table 的 5 个面按名义嗓色（blend 导出材质全白、无颜色）：
##   cloth=深蓝台布 / main=深木 / black / foot=近黑 / sides.001=深木边
## - 桌面顶面对齐 Table3dLayout.TABLE_HEIGHT（卡牌/铃铛所在的世界高度）

const TABLE_SCENE := preload("res://assets/3Dmodels/poker_table.blend")
const TABLE_TOP_Y := 1.0
const TARGET_WIDTH := 7.6
const LEG_DEPTH_WORLD := 1.03  # 桌腿世界深度：桌面(1.0)到腿底的距离（y 轴独立缩放贴地，原模型腿太长）

const SURFACE_COLORS := {
	"cloth": {"color": Color(0.27, 0.41, 0.29), "metallic": 0.0, "roughness": 0.98, "sheen": 0.03, "rim": 0.006, "grain": 0.055},
	"main": {"color": Color(0.16, 0.10, 0.06), "metallic": 0.0, "roughness": 0.86, "sheen": 0.08, "rim": 0.02, "grain": 0.035},
	"black": {"color": Color(0.05, 0.05, 0.06), "metallic": 0.05, "roughness": 0.88, "sheen": 0.06, "rim": 0.02, "grain": 0.02},
	"foot": {"color": Color(0.04, 0.04, 0.05), "metallic": 0.0, "roughness": 0.92, "sheen": 0.05, "rim": 0.015, "grain": 0.02},
	"sides.001": {"color": Color(0.13, 0.09, 0.06), "metallic": 0.0, "roughness": 0.86, "sheen": 0.07, "rim": 0.02, "grain": 0.03},
}
const TABLE_SHADER := preload("res://assets/shaders/table_surface.gdshader")

var _built := false

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	var root := TABLE_SCENE.instantiate()
	add_child(root)
	# 剔除模型自带相机（避免抢主相机）
	for n in ["Camera"]:
		var node := root.get_node_or_null(n)
		if node != null:
			root.remove_child(node)
			node.free()
	# 装饰/辅助件隐藏（只保留 table 本体）
	for n in ["cards", "chip", "chips", "Plane"]:
		var node := root.get_node_or_null(n)
		if node != null and node is MeshInstance3D:
			(node as MeshInstance3D).visible = false
	var table := root.get_node_or_null("table") as MeshInstance3D
	if table == null:
		table = root.get_node_or_null("Table") as MeshInstance3D
	if table == null or table.mesh == null:
		push_error("[PokerTableModel] 缺少 table mesh")
		return
	# 按面名上色（共享 mesh 资源 → 用实例级 surface override 避免互相影响）
	var aabb: AABB = table.mesh.get_aabb()
	for s in table.mesh.get_surface_count():
		var mat = table.mesh.surface_get_material(s)
		var name: String = mat.resource_name if mat != null else ""
		if SURFACE_COLORS.has(name):
			var spec: Dictionary = SURFACE_COLORS[name]
			var m := ShaderMaterial.new()
			m.shader = TABLE_SHADER
			m.set_shader_parameter("albedo_color", spec["color"])
			m.set_shader_parameter("metallic", spec["metallic"])
			m.set_shader_parameter("roughness", spec["roughness"])
			m.set_shader_parameter("light_dir_world", Vector3(-0.4, 0.82, 0.41))
			var look := CardTiltPreset.load_params()
			if look.is_empty():
				look = CardTiltPreset.DEFAULTS
			var gloss := 0.6 + float(look.get("gloss_strength", 0.35)) * 1.2
			var rim := 0.5 + float(look.get("rim_strength", 0.30)) * 1.5
			m.set_shader_parameter("sheen_strength", float(spec["sheen"]) * gloss)
			m.set_shader_parameter("rim_strength", float(spec["rim"]) * rim)
			m.set_shader_parameter("sheen_tint", look.get("gloss_tint", Color(0.62, 0.78, 1.0, 1.0)))
			m.set_shader_parameter("grain_amount", float(spec.get("grain", 0.03)))
			table.set_surface_override_material(s, m)
	# 缩放：x/z 至目标宽度；y 轴独立压扁让桌腿贴地（腿过长原先伸到世界 -2.97）
	# 桌面顶=topy_local*sy + position.y = TABLE_TOP_Y，腿底=POSITION.y - (-aabb.position.y)*sy ≈ 地面
	var sx := TARGET_WIDTH / aabb.size.x
	var sy := LEG_DEPTH_WORLD / aabb.size.y
	scale = Vector3(sx, sy, sx)
	position.y = TABLE_TOP_Y - (aabb.position.y + aabb.size.y) * sy
