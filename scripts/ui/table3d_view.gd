class_name Table3dView
extends Node3D
## 3D 桌面渲染器（Milestone 1/2）
## 职责：静态骨架（环境/相机/桌面/座位/中央牌堆/HUD）来自场景 scenes/ui/table3d.tscn，
## 本类负责按快照填充动态内容（每槽 CardBlock、HUD 按钮、染色/揭示/高亮）。
## 只读 + 拾取分发：不做规则/隐私判断（已知/未知由快照 slot 是否含 "card" 决定）。

const CardBlockScript := preload("res://scripts/ui/card_block.gd")

const SEAT_COUNT := 4
const HUD_OFFSET := 0.55
const HUD_HEIGHT := 0.5
const AVATAR_GLOW_COLOR := Color(1.0, 0.85, 0.35, 0.30)  # 当前回合高亮
const AVATAR_DIM_COLOR := Color(0.0, 0.0, 0.0, 0.55)     # 出局/离线变暗
const STAT_VIEWPORT_SIZE := Vector2i(320, 96)
const STAT_PANEL_OFFSET := Vector3(0.0, 0.75, 0.0)
const STAT_PANEL_PIXEL_SIZE := 0.005

var camera = null  # Table3dCamera（场景 CameraRig）
var _bind_done := false
var _bound := false
var _seat_nodes: Array = []
var _deck_label: Label3D
var _discard_block = null  # CardBlock（场景 Center/DiscardTop）
var _pending_block = null  # CardBlock（场景 Center/Pending）
var _hud = null  # Table3dHud（场景 Hud）
var _card_blocks := {}  # {seat: {slot: CardBlock}}
var _avatar_glow_mat: StandardMaterial3D = null
var _avatar_dim_mat: StandardMaterial3D = null
var _seat_panels: Array = []      # PlayerStatPanel per slot
var _stat_viewports: Array = []
var _bell_dome: MeshInstance3D = null
var _bell_mat: StandardMaterial3D = null

func _ready() -> void:
	_bind()

## 解析场景节点（静态骨架）。节点名/路径是契约，改动需同步本函数与测试。
func _bind() -> void:
	if _bind_done:
		return
	_bind_done = true
	camera = get_node_or_null("CameraRig")
	_seat_nodes.clear()
	for i in SEAT_COUNT:
		_seat_nodes.append(get_node_or_null("Seats/Seat%d" % i))
	_deck_label = get_node_or_null("Center/DeckCount")
	_discard_block = get_node_or_null("Center/DiscardTop")
	_pending_block = get_node_or_null("Center/Pending")
	_hud = get_node_or_null("Hud")
	var deck_block := get_node_or_null("Center/Deck")
	if deck_block != null and deck_block.has_method("set_pick"):
		deck_block.set_pick({"kind": "deck"})
	var bell := get_node_or_null("Center/KongBell")
	if bell != null:
		_bell_dome = bell.get_node_or_null("Dome")
		if _bell_dome != null:
			_bell_mat = _bell_dome.material_override
		var bell_pick := bell.get_node_or_null("PickArea")
		if bell_pick != null:
			bell_pick.collision_layer = Table3dLayout.PICK_MASK
			bell_pick.collision_mask = 0
			bell_pick.set_meta("pick", {"kind": "hud", "action": "kongbaya"})
	if camera == null or _deck_label == null or _discard_block == null \
			or _pending_block == null or _hud == null:
		push_error("[Table3dView] 场景缺少必需节点：CameraRig/Center/DeckCount/DiscardTop/Pending/Hud")
		return
	for i in _seat_nodes.size():
		var seat = _seat_nodes[i]
		if seat == null:
			push_error("[Table3dView] 场景缺少 Seats/SeatN 节点")
			return
		var avatar = seat.get_node_or_null("Avatar")
		var sub := SubViewport.new()
		sub.name = "StatViewport%d" % i
		sub.size = STAT_VIEWPORT_SIZE
		sub.transparent_bg = true
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(sub)
		var panel := PlayerStatPanel.new()
		panel.name = "Panel"
		sub.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var sprite := Sprite3D.new()
		sprite.name = "StatPanel"
		sprite.texture = sub.get_texture()
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.no_depth_test = true
		sprite.pixel_size = STAT_PANEL_PIXEL_SIZE
		sprite.position = STAT_PANEL_OFFSET
		if avatar != null:
			avatar.add_child(sprite)
		_seat_panels.append(panel)
		_stat_viewports.append(sub)
	_bound = true

## 显示/隐藏预览（不处理点击与动画）。
func set_active(on: bool) -> void:
	visible = on

## 按快照全量重建（无增量、无插值）。state 为 HiddenInfo 投影出的公开快照。
func render(state: Dictionary, actionable := Callable()) -> void:
	_bind()
	if not _bound:
		return
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
		_apply_avatar(node, p, viewer, state)
		if slot_i < _seat_panels.size():
			_seat_panels[slot_i].set_data(str(p.get("name", "")), int(p.get("health", 0)), int(p.get("currency", 0)), int(p.get("count", 0)))
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
	_update_bell(state)

## 铃铛可用性：金色亮 / 暗。
func _update_bell(state: Dictionary) -> void:
	if _bell_mat == null:
		return
	var avail := ActionModel.kongbaya_available(state)
	_bell_mat.emission_enabled = avail
	_bell_mat.albedo_color = Color(0.96, 0.84, 0.48) if avail else Color(0.42, 0.38, 0.28)

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
		# 卡牌平铺桌面：列沿 X，行沿 Z（+Z 朝桌心，罚牌追加行向玩家侧）
		block.position = Vector3(
			grid.x * (Table3dLayout.BLOCK_SIZE.x + Table3dLayout.BLOCK_GAP.x),
			0.0,
			grid.y * (Table3dLayout.BLOCK_SIZE.z + Table3dLayout.BLOCK_GAP.z))
		hand.add_child(block)
		block.setup(slots[i])
		block.set_pick({"kind": "slot", "seat": int(p.id), "slot": i})
		if not _card_blocks.has(int(p.id)):
			_card_blocks[int(p.id)] = {}
		_card_blocks[int(p.id)][i] = block

## 角色（场景 Avatar/Head+Body）：放到「眼睛」位置（径向外移 CAMERA_BACK、头心抬到
## EYE_HEIGHT，相机即在头心）；隐藏自己脑袋（身体在其正下方）；出局/离线变暗、当前回合金色高亮。
func _apply_avatar(seat_node: Node3D, p: Dictionary, viewer: int, state: Dictionary) -> void:
	var avatar := seat_node.get_node_or_null("Avatar")
	if avatar == null:
		return
	var eye := 1.5
	var back := 0.0
	if camera != null:
		var eye_v = camera.get("EYE_HEIGHT")
		if eye_v != null:
			eye = float(eye_v)
		var back_v = camera.get("CAMERA_BACK")
		if back_v != null:
			back = float(back_v)
	avatar.position = Vector3(0.0, eye, -back)
	var head := avatar.get_node_or_null("Head")
	var body := avatar.get_node_or_null("Body")
	var seat := int(p.id)
	# 自己那席整个角色隐藏（脑袋+身体都不出现在自己视角）
	avatar.visible = seat != viewer
	if head != null:
		head.visible = true
	var overlay: StandardMaterial3D = null
	var offline: Array = state.get("offline_players", [])
	if bool(p.get("eliminated", false)) or offline.has(seat):
		overlay = _avatar_dim()
	elif seat == int(state.get("current_player", -1)):
		overlay = _avatar_glow()
	if head != null:
		head.material_overlay = overlay
	if body != null:
		body.material_overlay = overlay

func _avatar_glow() -> StandardMaterial3D:
	if _avatar_glow_mat == null:
		_avatar_glow_mat = _make_overlay(AVATAR_GLOW_COLOR)
	return _avatar_glow_mat

func _avatar_dim() -> StandardMaterial3D:
	if _avatar_dim_mat == null:
		_avatar_dim_mat = _make_overlay(AVATAR_DIM_COLOR)
	return _avatar_dim_mat

func _make_overlay(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

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
	_bind()
	if _bound:
		_hud.set_buttons(buttons)

func _find_block(seat_id: int, slot: int):
	if not _card_blocks.has(seat_id) or not _card_blocks[seat_id].has(slot):
		return null
	var block = _card_blocks[seat_id][slot]
	return block if is_instance_valid(block) else null
