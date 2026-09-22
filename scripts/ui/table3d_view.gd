class_name Table3dView
extends Node3D
## 3D 桌面只读预览渲染器（Milestone 1）
## 职责：代码构建 3D 节点树（环境/相机/桌面/座位/中央牌堆），按快照全量重建方块。
## 只读：不处理点击、不做动画、不做隐私判断（已知/未知由快照 slot 是否含 "card" 决定）。

const CardBlockScript := preload("res://scripts/ui/card_block.gd")
const CameraScript := preload("res://scripts/ui/table3d_camera.gd")

const SEAT_COUNT := 4
const HAND_BASE_HEIGHT := 1.0
const CENTER_DECK := Vector3(0.0, 0.15, 0.0)
const CENTER_DISCARD := Vector3(0.9, 0.08, 0.0)
const CENTER_PENDING := Vector3(-0.9, 0.9, -0.0)
const BACKGROUND_COLOR := Color(0.07, 0.08, 0.10)
const HUD_OFFSET := 0.55
const HUD_HEIGHT := 0.5

var camera = null  # Table3dCamera
var _built := false
var _seat_nodes: Array = []
var _deck_label: Label3D
var _discard_block = null  # CardBlock
var _pending_block = null  # CardBlock
var _hud = null  # Table3dHud
var _card_blocks := {}  # {seat: {slot: CardBlock}}
var _hud_offset := Vector3.ZERO

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	# 环境光：保证方块与护盾自发光可见
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BACKGROUND_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 1.2
	env.environment = e
	add_child(env)
	# 相机
	camera = CameraScript.new()
	camera.name = "CameraRig"
	add_child(camera)
	# 桌面
	var table := MeshInstance3D.new()
	table.name = "Table"
	var box := BoxMesh.new()
	box.size = Vector3(Table3dLayout.TABLE_RADIUS * 2.0, 0.08, Table3dLayout.TABLE_RADIUS * 2.0)
	table.mesh = box
	table.position = Vector3(0.0, -0.04, 0.0)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.16, 0.18, 0.22)
	table.material_override = tmat
	add_child(table)
	# 座位（持久锚点，仅内容每次重建）
	var seats := Node3D.new()
	seats.name = "Seats"
	add_child(seats)
	for i in SEAT_COUNT:
		var seat := Node3D.new()
		seat.name = "Seat%d" % i
		var hand := Node3D.new()
		hand.name = "HandAnchor"
		hand.position = Vector3(0.0, HAND_BASE_HEIGHT, 0.0)
		seat.add_child(hand)
		var name_label := Label3D.new()
		name_label.name = "NameLabel"
		name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_label.no_depth_test = true
		name_label.pixel_size = 0.004
		name_label.font_size = 64
		name_label.position = Vector3(0.0, 0.55, 0.0)
		seat.add_child(name_label)
		var stat_label := Label3D.new()
		stat_label.name = "StatLabel"
		stat_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stat_label.no_depth_test = true
		stat_label.pixel_size = 0.003
		stat_label.font_size = 64
		stat_label.position = Vector3(0.0, 0.30, 0.0)
		seat.add_child(stat_label)
		seats.add_child(seat)
		_seat_nodes.append(seat)
	# 中央：抽牌堆（摞方块 + 数量标签）/ 弃牌顶 / pending
	var center := Node3D.new()
	center.name = "Center"
	add_child(center)
	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	var deck_box := BoxMesh.new()
	deck_box.size = Vector3(0.7, 0.25, 1.0)
	deck.mesh = deck_box
	deck.position = CENTER_DECK
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.30, 0.32, 0.38)
	deck.material_override = dmat
	center.add_child(deck)
	_deck_label = Label3D.new()
	_deck_label.name = "DeckCount"
	_deck_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_deck_label.no_depth_test = true
	_deck_label.pixel_size = 0.004
	_deck_label.font_size = 64
	_deck_label.position = CENTER_DECK + Vector3(0.0, 0.6, 0.0)
	center.add_child(_deck_label)
	_discard_block = CardBlockScript.new()
	_discard_block.name = "DiscardTop"
	_discard_block.position = CENTER_DISCARD
	center.add_child(_discard_block)
	_pending_block = CardBlockScript.new()
	_pending_block.name = "Pending"
	_pending_block.position = CENTER_PENDING
	_pending_block.scale = Vector3(1.5, 1.5, 1.5)
	center.add_child(_pending_block)
	# 3D 操作面板（准星可点）
	_hud = load("res://scripts/ui/table3d_hud.gd").new()
	_hud.name = "Hud"
	add_child(_hud)
	# 抽牌堆拾取标记
	var deck_area := Area3D.new()
	deck_area.name = "DeckPick"
	var deck_shape := CollisionShape3D.new()
	var deck_pick := BoxShape3D.new()
	deck_pick.size = Vector3(0.7, 0.25, 1.0)
	deck_shape.shape = deck_pick
	deck_area.add_child(deck_shape)
	deck_area.collision_layer = Table3dLayout.PICK_MASK
	deck_area.collision_mask = 0
	deck_area.set_meta("pick", {"kind": "deck"})
	deck_area.position = CENTER_DECK
	center.add_child(deck_area)

## 显示/隐藏预览（不处理点击与动画）。
func set_active(on: bool) -> void:
	visible = on

## 按快照全量重建（无增量、无插值）。state 为 HiddenInfo 投影出的公开快照。
func render(state: Dictionary, actionable := Callable()) -> void:
	_build()
	if state.is_empty():
		return
	var players: Array = state.get("players", [])
	if players.is_empty():
		return
	var viewer := int(state.get("viewer_id", 0))
	var angles := Table3dLayout.seat_angles(players.size())
	var others: Array = []
	for p in players:
		if int(p.id) != viewer:
			others.append(int(p.id))
	others.sort()
	var seat_angle := {viewer: float(angles[0])}
	for i in others.size():
		seat_angle[int(others[i])] = float(angles[i + 1])
	# 相机取景
	if camera != null:
		camera.frame_for_seat(float(seat_angle.get(viewer, 0.0)))
	# 座位
	_card_blocks.clear()
	for i in SEAT_COUNT:
		_seat_nodes[i].visible = false
	var slot_i := 0
	for p in players:
		if slot_i >= SEAT_COUNT:
			break
		var node: Node3D = _seat_nodes[slot_i]
		var seat := int(p.id)
		var a := float(seat_angle.get(seat, 0.0))
		node.visible = true
		node.position = _seat_world(a)
		node.rotation_degrees = Vector3(0.0, a + 180.0, 0.0)
		_render_seat(node, p)
		if actionable.is_valid():
			for slot_index in (p.get("slots", []) as Array).size():
				if _card_blocks.has(seat) and _card_blocks[seat].has(slot_index):
					_card_blocks[seat][slot_index].set_actionable(bool(actionable.call(seat, slot_index)))
		slot_i += 1
	# 中央
	_deck_label.text = str(int(state.get("draw_count", 0)))
	var discard: Dictionary = state.get("discard", {})
	_discard_block.setup({"card": discard} if not discard.is_empty() else {})
	_discard_block.set_pick({"kind": "discard"})
	var pending: Dictionary = state.get("pending", {})
	_pending_block.visible = not pending.is_empty()
	_pending_block.set_pick({"kind": "pending"})
	if not pending.is_empty():
		_pending_block.setup({"card": pending} if pending.has("rank") else {})
	# HUD 放在 viewer 座位内侧、朝向 viewer
	var v_angle := float(seat_angle.get(viewer, 0.0))
	var v_dir := Vector3(sin(deg_to_rad(v_angle)), 0.0, cos(deg_to_rad(v_angle)))
	_hud.position = v_dir * (Table3dLayout.SEAT_RADIUS - HUD_OFFSET) + Vector3(0.0, HUD_HEIGHT, 0.0)
	_hud.rotation_degrees = Vector3(0.0, v_angle + 180.0, 0.0)

## 座位世界坐标（与相机基准同一角度约定）。
func _seat_world(angle_deg: float) -> Vector3:
	var a := deg_to_rad(angle_deg)
	return Vector3(sin(a), 0.0, cos(a)) * Table3dLayout.SEAT_RADIUS

## 重建单个座位的方块与标签。
func _render_seat(node: Node3D, p: Dictionary) -> void:
	var hand: Node3D = node.get_node("HandAnchor")
	for child in hand.get_children():
		hand.remove_child(child)
		child.queue_free()
	var slots: Array = p.get("slots", [])
	for i in slots.size():
		var block = CardBlockScript.new()
		var grid: Vector2 = Table3dLayout.slot_grid_pos(i)
		block.position = Vector3(
			grid.x * (Table3dLayout.BLOCK_SIZE.x + Table3dLayout.BLOCK_GAP.x),
			-grid.y * (Table3dLayout.BLOCK_SIZE.y + Table3dLayout.BLOCK_GAP.y),
			0.0)
		hand.add_child(block)
		block.setup(slots[i])
		block.set_pick({"kind": "slot", "seat": int(p.id), "slot": i})
		if not _card_blocks.has(int(p.id)):
			_card_blocks[int(p.id)] = {}
		_card_blocks[int(p.id)][i] = block
	var name_label: Label3D = node.get_node("NameLabel")
	var stat_label: Label3D = node.get_node("StatLabel")
	name_label.text = str(p.get("name", ""))
	stat_label.text = "%d张  ¥%d  ♥%d" % [int(p.get("count", 0)), int(p.get("currency", 0)), int(p.get("health", 0))]
	var tint := Color(1, 1, 1, 0.5) if bool(p.get("eliminated", false)) else Color(1, 1, 1, 1)
	name_label.modulate = tint
	stat_label.modulate = tint

## 屏幕中心射线拾取（准星）。
func pick_center() -> Dictionary:
	if camera == null:
		return {}
	var center := get_viewport().get_visible_rect().size * 0.5
	return Table3dPicker.pick(camera.camera_node(), get_world_3d(), center)

## 瞬时揭示某槽位（dur 秒后恢复）。槽位不存在则忽略。
func reveal_slot(seat_id: int, slot: int, card: Dictionary, color := Color(0, 0, 0, 0), dur := 1.5) -> void:
	var block = _find_block(seat_id, slot)
	if block == null:
		return
	block.reveal(card, color)
	get_tree().create_timer(dur).timeout.connect(func():
		if is_instance_valid(block):
			block.restore())

## 短暂染色提醒（不翻面）。
func flash_slot(seat_id: int, slot: int, color: Color, dur: float) -> void:
	var block = _find_block(seat_id, slot)
	if block != null:
		block.flash(color, dur)

## 设置 3D 操作面板按钮（[{text, action, enabled}]）。
func set_hud_buttons(buttons: Array) -> void:
	_build()
	_hud.set_buttons(buttons)

func _find_block(seat_id: int, slot: int):
	if not _card_blocks.has(seat_id) or not _card_blocks[seat_id].has(slot):
		return null
	var block = _card_blocks[seat_id][slot]
	return block if is_instance_valid(block) else null
