class_name Table3dView
extends Node3D
## 3D 桌面渲染器（Milestone 1/2）
## 职责：静态骨架（环境/相机/桌面/座位/中央牌堆/HUD）来自场景 scenes/ui/table3d.tscn，
## 本类负责按快照填充动态内容（每槽 CardBlock、HUD 按钮、染色/揭示/高亮）。
## 只读 + 拾取分发：不做规则/隐私判断（已知/未知由快照 slot 是否含 "card" 决定）。

const CardBlockScript := preload("res://scripts/ui/card_block.gd")
const NoseAvatarScript := preload("res://scripts/ui/nose_avatar.gd")
const EmoteDisplayScript := preload("res://scripts/ui/emote_display.gd")
const Mark3DScript := preload("res://scripts/ui/mark3d.gd")
const Mark3dMathScript := preload("res://scripts/ui/mark3d_math.gd")
const NOSE_PICK_KINDS := ["slot", "deck", "discard", "pending"]  # 可被中键"标记"的拾取类型
const LOCAL_NOSE_POS := Vector3(0.0, -0.06, -0.15)               # 本机鼻根（相机本地，-Z=前）

const SEAT_COUNT := 4
const HUD_OFFSET := 0.55
const HUD_HEIGHT := 0.5
const AVATAR_DIM_COLOR := Color(0.0, 0.0, 0.0, 0.55)     # 出局/离线变暗
const HOVER_COLOR := Color(0.7, 0.95, 1.0, 0.35)         # 非卡牌目标（HUD 等）的叠加薄色
## hover 虚线边框颜色：无选择上下文=白；有上下文且目标可操作=绿；否则=红。
const BORDER_WHITE := Color(1.0, 1.0, 1.0, 0.9)
const BORDER_GREEN := Color(0.53, 0.85, 0.63)
const BORDER_RED := Color(1.0, 0.48, 0.48)
## 弃牌堆"用能力"（弃掉抽到的牌发动 7/8/9/10/J/Q）的提示色：橙色（区别于取弃牌顶的金色）。
const USE_POWER_COLOR := Color(1.0, 0.55, 0.15)
## 中央牌堆顶牌相对桌面的极小抬升：贴桌（y=0）时炫光平面（本地 y=-0.002）会被桌面遮住。
const STACK_BASE_LIFT := 0.004
## 手牌槽距放大倍数（列距/行距 = (卡尺寸+间隙) × 该值）；默认 +1/10。
const HAND_SPACING_SCALE := 1.1
## 铃铛拾取盒随模型一起缩小（避免误触）。
const BELL_PICK_SCALE := 2.0 / 3.0
const STAT_VIEWPORT_SIZE := Vector2i(320, 120)
const STAT_PANEL_OFFSET := Vector3(0.0, 0.75, 0.0)
const STAT_PANEL_PIXEL_SIZE := 0.005
const PENDING_Y := 0.95  # 大牌竖立悬浮中心离桌高度（牌高 1.0 → 底≈0.45、顶≈1.45）
const DEAL_INTERVAL := 0.15  # 开局发牌：每张间隔（秒，按 _deal_speed 缩放）
const STAT_PANEL_ABOVE := 0.45   # 状态面板相对机器人头顶的上方间隙
const MARKER_ABOVE_PANEL := 0.5  # 回合标识相对状态面板的上方间隙

# 回合标识：当前行动者名字面板上方的红色倒三角（黑色描边，billboard，纯展示），顶部提示「看牌」
const TURN_MARKER_COLOR := Color(0.92, 0.15, 0.15)         # 填充：红色
const TURN_MARKER_OUTLINE_COLOR := Color(0.02, 0.02, 0.02)  # 描边：黑色（空心环，不遮红心）
const TURN_MARKER_SIZE := Vector2(0.45, 0.34)             # 宽 × 高
const TURN_MARKER_OUTLINE_SCALE := 1.35                   # 描边外扩
const TURN_MARKER_OFFSET := Vector3(0.0, 1.22, 0.0)       # 紧贴名字面板上方（避免与名字重叠）
const TURN_MARKER_HINT := "看牌"
const TURN_MARKER_HINT_COLOR := Color(1.0, 1.0, 1.0)     # 白色
const TURN_MARKER_HINT_OFFSET := Vector3(0.0, 0.42, 0.0)  # 三角顶部上方
const TURN_MARKER_HIDDEN_PHASES := [0, 7, 10]             # LOBBY / GAME_OVER / SHOP 不显示

var camera = null  # Table3dCamera（场景 CameraRig）
var _bind_done := false
var _bound := false
var _seat_nodes: Array = []
var _deck_label: Label3D
var _discard_block = null  # CardBlock（场景 Center/DiscardTop）
var _pending_block = null  # CardBlock（场景 Center/Pending）
var _hud = null  # Table3dHud（场景 Hud）
var _restart_button: Node3D = null  # 房主重开按钮（牌桌右后角，准星可点）
var _item_target_ring: MeshInstance3D = null  # 道具卡选目标时的金色目标环
var _card_blocks := {}  # {seat: {slot: CardBlock}}
var _viewer := 0
var _sel_active := false           # 当前是否有"选择"上下文（决定 hover 边框红/绿/白）
var _hover_slot := {}
var _hover_ray_local := Vector2.ZERO
var _avatar_dim_mat: StandardMaterial3D = null
var _hover_collider: Object = null
var _hover_kind := ""              # 当前悬停拾取类型（供 hovered_card_world）
var _hover_card = null             # 当前悬停的卡牌节点（CardBlock，取其中心作鼻尖目标）
var _local_nose = null             # NoseAvatar（挂本机相机，第一人称）
var _emotes := {}  # seat -> EmoteDisplay
var _marks := {}  # seat -> Mark3D（桌面标记，独立节点、跨 render 保留）
var _hover_mat: StandardMaterial3D = null
var _seat_panels: Array = []      # PlayerStatPanel per slot
var _stat_viewports: Array = []
var _seat_markers: Array = []     # 回合标识 Node3D per slot（供外部查询）
var _reveals := {}                # "seat_slot" -> {card, color, token}（跨 render 保持揭示/翻牌）
var _reveal_seq := 0
var _flashes := {}                # "seat_slot" -> {color, until_ms}（跨 render 保持短暂光晕，如 peek_highlight）
var _bell_model = null  # BellModel（call-bell.glb + 金属着色器；旧占位隐藏）
var _deck_node: Node3D = null
var _deck_block = null  # CardBlock（场景 Center/Deck）＝ 牌堆顶那张（卡背/光晕/拾取）
var _deck_pile = null  # DeckPile（牌堆视觉：下方叠的卡边薄盒）
var _discard_node: Node3D = null
var _discard_pile = null  # DeckPile（弃牌堆视觉：下方叠的卡边薄盒，不画卡背）
var _discard_shown := {}  # 弃牌顶变换动画期间的"上一张"（保留显示，避免下方为空）
var _pending_node: Node3D = null
var _seat_node_by_id := {}     # seat -> Node3D（render 登记）
var _hand_node_by_id := {}     # seat -> HandAnchor Node3D（render 登记；未渲染槽的槽位变换基准）
var _slot_cards := {}          # {seat: {slot: card}}（render 登记，供 slap_gift 自身视角取牌面）
var _relic_baskets_by_seat := {}  # seat -> Node3D（3 个 RelicBasket）
var _anim_slots := {}          # "seat_slot" -> true（在途动画槽位，render 跳过）
var _flyers: Array = []        # 在途 CardFly
var _discard_hold := false     # 飞向弃牌堆期间隐藏弃牌顶
var _pending_hold := false     # 抽牌飞行期间隐藏大牌
var _prev_pending := {}        # 上一帧快照的 pending（检测新抽牌）
var _prev_discard := {}        # 上一帧快照的弃牌顶（判断抽牌 vs 取弃牌顶）
var _pending_seen := false     # 已见过一次 pending（避免进入 3D 首帧误触发抽牌飞牌）
var _last_state: Dictionary = {}
var _last_actionable := Callable()
var _deal_speed := 1.0
var _dealing := false

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
	if deck_block != null and deck_block.has_method("setup"):
		deck_block.setup({})  # 空槽 → 正面显示卡背（否则默认白面盖住卡背）
	_deck_node = deck_block
	_deck_block = deck_block
	# 牌堆视觉（卡边薄盒）挂在桌心 Center 下、与 Deck 同 XZ；最上面那张仍由 Deck 的 CardBlock 充当。
	if _deck_node != null:
		_deck_pile = get_node_or_null("Center/DeckPile")
		if _deck_pile == null:
			_deck_pile = DeckPile.new()
			_deck_pile.name = "DeckPile"
			_deck_node.get_parent().add_child(_deck_pile)
			_deck_pile.position = Vector3(_deck_node.position.x, 0.0, _deck_node.position.z)
	_discard_node = _discard_block
	# 弃牌堆视觉（卡边薄盒，正面朝上 → 不画卡背）挂在桌心 Center 下、与 DiscardTop 同 XZ。
	if _discard_node != null:
		_discard_pile = get_node_or_null("Center/DiscardPile")
		if _discard_pile == null:
			_discard_pile = DeckPile.new()
			_discard_pile.name = "DiscardPile"
			_discard_pile.with_back = false
			_discard_node.get_parent().add_child(_discard_pile)
			_discard_pile.position = Vector3(_discard_node.position.x, 0.0, _discard_node.position.z)
	_pending_node = _pending_block
	if _pending_node != null and _deck_node != null and _discard_node != null:
		var mid := (_deck_node.position + _discard_node.position) * 0.5
		_pending_node.position = Vector3(mid.x, PENDING_Y, mid.z)
	if _pending_block != null and _pending_block.has_method("set_upright"):
		_pending_block.set_upright(true)
	var bell := get_node_or_null("Center/KongBell")
	if bell != null:
		# 旧占位（Base/Dome/Knob）隐藏，改挂 call-bell.glb 模型 + 金属着色器。
		for old_name in ["Base", "Dome", "Knob"]:
			var old := bell.get_node_or_null(old_name)
			if old is Node3D:
				(old as Node3D).visible = false
		_bell_model = bell.get_node_or_null("BellModel")
		if _bell_model == null:
			_bell_model = BellModel.new()
			_bell_model.name = "BellModel"
			bell.add_child(_bell_model)
		var bell_pick := bell.get_node_or_null("PickArea")
		if bell_pick != null:
			bell_pick.collision_layer = Table3dLayout.PICK_MASK
			bell_pick.collision_mask = 0
			bell_pick.set_meta("pick", {"kind": "hud", "action": "kongbaya"})
			# 拾取盒随铃铛一起缩小 1/3（降低误触）。
			var pick_shape := bell_pick.get_node_or_null("PickShape") as CollisionShape3D
			if pick_shape != null:
				pick_shape.scale = Vector3.ONE * BELL_PICK_SCALE
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
		_attach_robot(avatar)
		# 手牌区抬到桌面高度（机器人脚仍在 y=0，桌子在腰间）。
		var hand = seat.get_node_or_null("HandAnchor")
		if hand != null and hand is Node3D:
			(hand as Node3D).position.y = Table3dLayout.TABLE_HEIGHT + 0.03
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
		var marker := _make_turn_marker(TURN_MARKER_SIZE)
		marker.position = TURN_MARKER_OFFSET
		marker.visible = false
		if avatar != null:
			avatar.add_child(marker)
		_seat_panels.append(panel)
		_stat_viewports.append(sub)
		_seat_markers.append(marker)
	_ensure_restart_button()
	_bound = true
	_ensure_local_nose()

## 房主重开按钮（牌桌右后角）：扁平半透明圆盘 + ↻ 图标（billboard）+ 拾取区。
## 动作经「hud」拾取 → main._on_action("restart")；显隐由 render 按房主/阶段控制。
func _ensure_restart_button() -> void:
	if _restart_button != null and is_instance_valid(_restart_button):
		return
	var root := Node3D.new()
	root.name = "RestartButton"
	var base := MeshInstance3D.new()
	base.name = "Base"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.18
	disc.bottom_radius = 0.18
	disc.height = 0.04
	base.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.14, 0.18, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	base.material_override = mat
	root.add_child(base)
	var icon := Label3D.new()
	icon.name = "Icon"
	icon.text = "↻"
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	icon.pixel_size = 0.0025
	icon.font_size = 128
	icon.modulate = Color(1.0, 1.0, 1.0)
	icon.position = Vector3(0.0, 0.06, 0.0)
	root.add_child(icon)
	var area := Area3D.new()
	area.name = "PickArea"
	area.collision_layer = Table3dLayout.PICK_MASK
	area.collision_mask = 0
	area.set_meta("pick", {"kind": "hud", "action": "restart"})
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	shape.shape = sphere
	area.add_child(shape)
	root.add_child(area)
	root.position = Vector3(
		Table3dLayout.TABLE_RADIUS * 0.8,
		Table3dLayout.TABLE_HEIGHT + 0.03,
		Table3dLayout.TABLE_RADIUS * 0.8)
	add_child(root)
	_restart_button = root

## 显示/隐藏预览（不处理点击与动画）。
func set_active(on: bool) -> void:
	visible = on
	if not on:
		_clear_exchange_anim()
		clear_local_nose()
		clear_marks()
		clear_emotes()

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
	_viewer = viewer
	_last_state = state
	_last_actionable = actionable
	# GAME_OVER：手牌全部保持背面，由结算算分动画逐张翻面（reveal_slot_settle）
	var face_all := int(state.get("phase", 0)) != 7
	_seat_node_by_id.clear()
	_hand_node_by_id.clear()
	_relic_baskets_by_seat.clear()
	_slot_cards.clear()
	# 固定座位角度（按 seat_id，与观看者无关）→ 所有客户端共享同一世界坐标，
	# 这样同步来的世界注视方向才能被一致解释（否则各客户端座位相对位置不同 → 镜像）。
	# 相机取景
	if camera != null:
		camera.frame_for_seat(Table3dLayout.seat_angle(viewer), Table3dLayout.TABLE_HEIGHT)
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
		var a := Table3dLayout.seat_angle(seat)
		_seat_node_by_id[seat] = node
		_hand_node_by_id[seat] = node.get_node_or_null("HandAnchor")
		_slot_cards[seat] = {}
		node.visible = true
		node.position = _seat_world(a)
		node.rotation_degrees = Vector3(0.0, a + 180.0, 0.0)
		_render_seat(node, p, face_all)
		_ensure_relic_baskets(node, seat)
		_update_relic_baskets(seat, p)
		_apply_avatar(node, p, viewer, state)
		if slot_i < _seat_panels.size():
			_seat_panels[slot_i].set_data(str(p.get("name", "")), int(p.get("health", 0)), int(p.get("currency", 0)), int(p.get("count", 0)))
		if actionable.is_valid():
			for slot_index in (p.get("slots", []) as Array).size():
				if _card_blocks.has(seat) and _card_blocks[seat].has(slot_index):
					_card_blocks[seat][slot_index].set_actionable(bool(actionable.call(seat, slot_index)))
		slot_i += 1
	# 重建后重新应用在途揭示（否则状态广播会把翻牌冲回背面）
	for key in _reveals.keys():
		var parts: PackedStringArray = str(key).split("_")
		if parts.size() == 2:
			_apply_reveal(int(parts[0]), int(parts[1]))
	# 重建后重新应用在途光晕提醒（peek_highlight），否则状态广播重建会冲掉蓝光
	for key in _flashes.keys():
		var fparts: PackedStringArray = str(key).split("_")
		if fparts.size() == 2:
			_apply_flash(int(fparts[0]), int(fparts[1]))
	# 中央
	# 抽牌堆剩余/总数（如 45/54）
	var draw_n := int(state.get("draw_count", 0))
	_deck_label.text = "%d/%d" % [draw_n, KongRules.DECK_SIZE]
	# 牌堆视觉随 draw_count 变矮；顶牌 CardBlock 抬到堆顶
	if _deck_pile != null and is_instance_valid(_deck_pile):
		_deck_pile.set_count(maxi(draw_n - 1, 0))
	if _deck_node != null and is_instance_valid(_deck_node):
		_deck_node.position.y = draw_n * DeckPile.CARD_THICKNESS + STACK_BASE_LIFT
		# 抽牌堆：hover 虚线圈压到牌堆底部（贴桌面），而不是浮在顶牌上
		if _deck_node.has_method("set_border_offset"):
			_deck_node.set_border_offset(-_deck_node.position.y)
	# 抽牌堆：轮到自己抽牌（TURN_DRAW）时金色光晕；结算贴牌窗口锁死（红色虚线框见 _set_locked_dash）
	var locked_dash := ActionModel.settle_pending(state)
	if _deck_block != null and is_instance_valid(_deck_block):
		_deck_block.set_actionable(ActionModel.draw_available(state))
	var discard: Dictionary = state.get("discard", {})
	var discard_count := int(state.get("discard_count", 0))
	# 弃牌堆视觉随 discard_count 变高；顶牌 CardBlock 抬到堆顶
	if _discard_pile != null and is_instance_valid(_discard_pile):
		_discard_pile.set_count(maxi(discard_count - 1, 0))
	if _discard_node != null and is_instance_valid(_discard_node):
		# + 极小抬升：空弃牌堆贴桌时炫光会被桌面遮住（橙光/金光都看不到）。
		_discard_node.position.y = discard_count * DeckPile.CARD_THICKNESS + STACK_BASE_LIFT
	# 弃牌堆可点：取弃牌顶（金）/ 弃掉抽到的牌·用能力（橙）；可点时对应光晕
	var discard_actionable := ActionModel.discard_pile_actionable(state)
	var use_power := ActionModel.pending_discard_available(state)
	if _discard_hold:
		# 顶牌变换动画期间：保留显示"上一张"，避免下方为空（无上一张则隐藏）
		var held: Dictionary = _discard_shown if not _discard_shown.is_empty() else discard
		_discard_block.visible = not held.is_empty()
		if not held.is_empty():
			_discard_block.setup({"card": held})
		_discard_block.set_pick_enabled(false)
		_discard_block.set_actionable(false)
	else:
		_discard_block.visible = true
		_discard_block.setup({"card": discard} if not discard.is_empty() else {})
		_discard_block.set_pick({"kind": "discard"})
		_discard_block.set_pick_enabled(discard_actionable)
		_discard_block.set_actionable_color(USE_POWER_COLOR if use_power else Table3dLayout.ACTIONABLE_COLOR)
		_discard_block.set_actionable(discard_actionable)
	_set_locked_dash(locked_dash)
	var pending: Dictionary = state.get("pending", {})
	_detect_draw(pending, discard)
	_prev_pending = pending.duplicate()
	_prev_discard = discard.duplicate()
	_pending_seen = true
	_pending_block.visible = not pending.is_empty() and not _pending_hold
	_pending_block.set_pick({"kind": "pending"})
	# 大牌不可点（弃牌/用能力由弃牌堆触发），但保留拾取用于 hover 解释气泡
	_pending_block.set_pick_enabled(not pending.is_empty())
	if not pending.is_empty():
		_pending_block.setup({"card": pending} if pending.has("rank") else {})
	# HUD 放在 viewer 座位内侧、朝向 viewer
	var v_angle := Table3dLayout.seat_angle(viewer)
	var v_dir := Vector3(sin(deg_to_rad(v_angle)), 0.0, cos(deg_to_rad(v_angle)))
	_hud.position = v_dir * (Table3dLayout.SEAT_RADIUS - HUD_OFFSET) + Vector3(0.0, HUD_HEIGHT, 0.0)
	_hud.rotation_degrees = Vector3(0.0, v_angle + 180.0, 0.0)
	_reapply_hover_pose()
	_update_bell(state)
	# 房主重开按钮：仅房主且对局中（非大厅/结算）可见。
	if _restart_button != null and is_instance_valid(_restart_button):
		var phase := int(state.get("phase", 0))
		_restart_button.visible = Network.is_host and phase != 0 and phase != 7

## 重建后重放在途 hover（immediate，避免广播导致弹跳）。
func _reapply_hover_pose() -> void:
	if _hover_slot.is_empty():
		return
	var b = _find_block(int(_hover_slot.get("seat", -1)), int(_hover_slot.get("slot", -1)))
	if b != null and b.hover_anim_enabled:
		b.set_hover_pose(true, _hover_ray_local, true)

func _ray_local_for_block(b, hit_pos: Vector3) -> Vector2:
	var p: Vector3 = b.global_transform.affine_inverse() * hit_pos
	return Vector2(
		clampf(p.x / (Table3dLayout.BLOCK_SIZE.x * 0.5), -1.0, 1.0),
		clampf(p.z / (Table3dLayout.BLOCK_SIZE.z * 0.5), -1.0, 1.0))

func _leave_hover_slot() -> void:
	if _hover_slot.is_empty():
		return
	var b = _find_block(int(_hover_slot.get("seat", -1)), int(_hover_slot.get("slot", -1)))
	if b != null:
		b.set_hover_pose(false, Vector2.ZERO)
	_hover_slot = {}

## 铃铛可用性：可用时加金色辉光（金属底色不变）。
## 结算贴牌窗口锁死：抽/弃两堆常驻红色虚线框（等待 slap close；两堆均为假时不画）。
func _set_locked_dash(on: bool) -> void:
	for block in [_deck_block, _discard_block]:
		if block != null and is_instance_valid(block):
			block.set_locked_dash(on)

func _update_bell(state: Dictionary) -> void:
	if _bell_model == null:
		return
	_bell_model.set_glow(ActionModel.kongbaya_available(state))

## 座位世界坐标（与相机基准同一角度约定）。
func _seat_world(angle_deg: float) -> Vector3:
	var a := deg_to_rad(angle_deg)
	return Vector3(sin(a), 0.0, cos(a)) * Table3dLayout.SEAT_RADIUS

## 开局发牌动画是否进行中（空格优先给 2× 速）。
func is_dealing() -> bool:
	return _dealing

## 道具卡目标模式：相机锁定到目标角色 + 金色目标环。
func begin_item_target(seat: int) -> void:
	_bind()
	_ensure_item_target_ring()
	_place_item_target_ring(seat)
	if camera != null:
		camera.lock_aim_at(_item_target_focus(seat))

func update_item_target(seat: int) -> void:
	_bind()
	if _item_target_ring == null or not is_instance_valid(_item_target_ring):
		return
	_place_item_target_ring(seat)
	if camera != null:
		camera.lock_aim_at(_item_target_focus(seat))

func end_item_target() -> void:
	if _item_target_ring != null and is_instance_valid(_item_target_ring):
		_item_target_ring.visible = false
	if camera != null:
		camera.restore_view()

func _item_target_focus(seat: int) -> Vector3:
	var node: Node3D = _seat_node_by_id.get(seat)
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	var avatar = node.get_node_or_null("Avatar")
	if avatar is Node3D and (avatar as Node3D).visible:
		return (avatar as Node3D).global_position + Vector3(0.0, 0.1, 0.0)
	return node.global_position + Vector3(0.0, 1.5, 0.0)

func _place_item_target_ring(seat: int) -> void:
	if _item_target_ring == null or not is_instance_valid(_item_target_ring):
		return
	var node: Node3D = _seat_node_by_id.get(seat)
	if node == null or not is_instance_valid(node):
		_item_target_ring.visible = false
		return
	_item_target_ring.global_position = node.global_position + Vector3(0.0, Table3dLayout.TABLE_HEIGHT + 0.06, 0.0)
	_item_target_ring.visible = true

func _ensure_item_target_ring() -> void:
	if _item_target_ring != null and is_instance_valid(_item_target_ring):
		return
	_item_target_ring = MeshInstance3D.new()
	_item_target_ring.name = "ItemTargetRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.62
	torus.outer_radius = 0.70
	torus.rings = 32
	torus.ring_segments = 12
	_item_target_ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.95, 0.82, 0.35, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.82, 0.35)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_item_target_ring.material_override = mat
	_item_target_ring.visible = false
	add_child(_item_target_ring)

## 重建单个座位的方块与标签。
func _render_seat(node: Node3D, p: Dictionary, face_all := true) -> void:
	var hand: Node3D = node.get_node("HandAnchor")
	for child in hand.get_children():
		hand.remove_child(child)
		child.queue_free()
	var slots: Array = p.get("slots", [])
	for i in slots.size():
		var slot: Dictionary = slots[i]
		# 登记槽位牌面（含被动画隐藏的槽，供 slap_gift 自身视角取牌面）
		_slot_cards[int(p.id)][i] = slot.get("card", {})
		# 在途动画槽位跳过（等价 2D mark_anim_slot）
		if _has_anim_slot(int(p.id), i):
			continue
		# 空槽（贴牌成功/交出后卡片被清掉）不渲染 → 卡牌消失（与 2D 空槽透明占位一致）
		if str(slot.get("card_id", "")).is_empty() and not slot.has("card"):
			continue
		var block = CardBlockScript.new()
		# 卡牌平铺桌面（对齐 2D 观感）：见 _slot_local。
		block.position = _slot_local(i).origin
		hand.add_child(block)
		# GAME_OVER：不渲染牌面（保持背面），由结算页 reveal_slot_settle 逐张翻开
		var display: Dictionary = slot.duplicate()
		if not face_all:
			display.erase("card")
		block.setup(display)
		block.set_pick({"kind": "slot", "seat": int(p.id), "slot": i})
		block.hover_anim_enabled = int(p.id) == _viewer
		if not _card_blocks.has(int(p.id)):
			_card_blocks[int(p.id)] = {}
		_card_blocks[int(p.id)][i] = block

## 每席 3 个饰品篮：放在该玩家视角的左手边（本地 +X），沿 Z 排开。
const RELIC_BASKET_X := 1.15
const RELIC_BASKET_Z := [-0.55, 0.0, 0.55]

func _ensure_relic_baskets(seat_node: Node3D, seat: int) -> Node3D:
	var root: Node3D = seat_node.get_node_or_null("RelicBaskets")
	if root == null:
		root = Node3D.new()
		root.name = "RelicBaskets"
		seat_node.add_child(root)
		for i in 3:
			var basket := RelicBasket.new()
			basket.name = "Basket%d" % i
			basket.position = Vector3(RELIC_BASKET_X, Table3dLayout.TABLE_HEIGHT + 0.04, float(RELIC_BASKET_Z[i]))
			root.add_child(basket)
			basket.setup(i, "")
			var pick := basket.get_node_or_null("PickArea")
			if pick != null:
				pick.set_meta("pick", {"kind": "relic", "seat": seat, "slot": i})
	_relic_baskets_by_seat[seat] = root
	return root

func _update_relic_baskets(seat: int, p: Dictionary) -> void:
	var root: Node3D = _relic_baskets_by_seat.get(seat)
	if root == null or not is_instance_valid(root):
		return
	var relics: Array = p.get("relics", [])
	for i in 3:
		var basket := root.get_node_or_null("Basket%d" % i) as RelicBasket
		if basket == null:
			continue
		basket.setup(i, str(relics[i]) if i < relics.size() else "")
		var pick := basket.get_node_or_null("PickArea")
		if pick != null:
			pick.set_meta("pick", {"kind": "relic", "seat": seat, "slot": i})

## 供测试/工具查询某席的 3 个篮子。
func relic_baskets(seat: int) -> Array:
	var root: Node3D = _relic_baskets_by_seat.get(seat)
	if root == null or not is_instance_valid(root):
		return []
	var out: Array = []
	for i in 3:
		out.append(root.get_node_or_null("Basket%d" % i))
	return out

## 当前悬停的饰品篮（{} = 未悬停饰品）。
func hovered_relic() -> Dictionary:
	var meta := hovered_pick()
	if str(meta.get("kind", "")) != "relic":
		return {}
	var basket = _hover_collider.get_parent() if _hover_collider != null and is_instance_valid(_hover_collider) else null
	if basket is RelicBasket:
		return {"seat": int(meta.get("seat", -1)), "slot": int(meta.get("slot", -1)),
			"id": (basket as RelicBasket).relic()}
	return {}

## 悬停饰品篮的屏幕矩形（用于说明气泡）。
func hovered_relic_screen_rect(cam: Camera3D) -> Rect2:
	if cam == null or _hover_collider == null or not is_instance_valid(_hover_collider):
		return Rect2()
	var parent = _hover_collider.get_parent()
	if parent is Node3D:
		var center := cam.unproject_position((parent as Node3D).global_position)
		return Rect2(center - Vector2(24, 24), Vector2(48, 48))
	return Rect2()

## 角色（Robot 模型）：放到「眼睛」位置（径向外移 CAMERA_BACK、头心抬到
## EYE_HEIGHT，相机即在头心）；隐藏自己那席；出局/离线变暗、当前回合金色高亮。
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
	var seat := int(p.id)
	# 自己那席整个角色隐藏（机器人也不出现在自己视角）
	avatar.visible = seat != viewer
	# 机器人原点在脚：avatar 原点在眼高 → 局部 y=-eye 让脚落在桌面。
	var robot := avatar.get_node_or_null("RobotAvatar")
	var head_top_local := RobotAvatar.MODEL_HEAD_TOP * RobotAvatar.SCALE - eye
	if robot != null:
		robot.position.y = -eye
	var overlay: StandardMaterial3D = null
	var offline: Array = state.get("offline_players", [])
	if bool(p.get("eliminated", false)) or offline.has(seat):
		overlay = _avatar_dim()
	if robot != null:
		var col := str(p.get("color", ""))
		if not col.is_empty() and Color.html_is_valid(col):
			robot.set_body_color(Color.html(col))
		robot.set_overlay(overlay)
	# 头顶状态面板与回合标识随机器人高度定位（占位 Head/Body 已在 _attach_robot 隐藏）。
	var sprite := avatar.get_node_or_null("StatPanel")
	if sprite != null:
		sprite.position.y = head_top_local + STAT_PANEL_ABOVE
	var marker := avatar.get_node_or_null("TurnMarker")
	if marker != null:
		marker.position.y = head_top_local + STAT_PANEL_ABOVE + MARKER_ABOVE_PANEL
		marker.visible = avatar.visible and _is_current_turn(state, seat)

## 在座位 Avatar 下挂 Robot 角色（替代原 Body/Head 占位），并隐藏占位节点
## （保留节点供 tuner/测试定位；节点名/路径契约不变）。
func _attach_robot(avatar) -> void:
	if avatar == null or not (avatar is Node3D):
		return
	if avatar.has_node("RobotAvatar"):
		return
	var robot := RobotAvatar.new()
	robot.name = "RobotAvatar"
	avatar.add_child(robot)
	for n in ["Head", "Body"]:
		var m = avatar.get_node_or_null(n)
		if m is Node3D:
			(m as Node3D).visible = false

## 每帧更新各席机器人眼睛：
##  - 有该席玩家同步来的注视方向（remote_looks[seat]）+ 放大状态（remote_zoom[seat]）→ 跟随其主人；
##  - 无同步（离线 / 2D 玩家 / 旧客户端）→ 稳定看向本机相机 + 用本机放大状态。
## 注意：环视只改相机朝向、位置基本不动，故本地目标不能直接用相机位置。
func update_avatars(cam: Camera3D, remote_looks := {}, remote_zoom := {}, local_zoom := false, remote_talk := {}, local_talk := false) -> void:
	_bind()
	if not _bound or cam == null:
		return
	for seat in _seat_node_by_id.keys():
		var node = _seat_node_by_id[seat]
		if node == null or not is_instance_valid(node) or not (node as Node3D).visible:
			continue
		var avatar = node.get_node_or_null("Avatar")
		if avatar == null or not (avatar as Node3D).visible:
			continue
		var robot = avatar.get_node_or_null("RobotAvatar")
		if robot == null:
			continue
		if remote_looks.has(seat) and remote_looks[seat] is Vector3:
			robot.set_gaze_target_world(remote_looks[seat])
			robot.set_eye_zoom(bool(remote_zoom.get(seat, false)))
			robot.set_talking(bool(remote_talk.get(seat, false)))
		else:
			robot.set_gaze_target_world(cam.global_position)
			robot.set_eye_zoom(local_zoom)
			robot.set_talking(local_talk)

## 本机放大状态联动（所有可见机器人眼睛用小眼）；主路径由 update_avatars 逐席下发。
func set_eye_zoom(on: bool) -> void:
	_bind()
	if not _bound:
		return
	for seat in _seat_node_by_id.keys():
		var node = _seat_node_by_id[seat]
		if node == null or not is_instance_valid(node) or not (node as Node3D).visible:
			continue
		var avatar = node.get_node_or_null("Avatar")
		if avatar == null or not (avatar as Node3D).visible:
			continue
		var robot = avatar.get_node_or_null("RobotAvatar")
		if robot != null and robot.has_method("set_eye_zoom"):
			robot.set_eye_zoom(on)

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

## 是否当前行动者的回合（LOBBY/GAME_OVER/SHOP 不显示）。
func _is_current_turn(state: Dictionary, seat: int) -> bool:
	if seat != int(state.get("current_player", -1)):
		return false
	return not TURN_MARKER_HIDDEN_PHASES.has(int(state.get("phase", -1)))

## 倒三角网格（XY 平面，apex 朝下），配合 billboard 始终面向相机。
static func _triangle_mesh(size: Vector2) -> ArrayMesh:
	var w := size.x
	var h := size.y
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-w * 0.5, h * 0.5, 0.0),
		Vector3(w * 0.5, h * 0.5, 0.0),
		Vector3(0.0, -h * 0.5, 0.0),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 1.0),
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## 倒三角空心边环（外三角 - 内三角），用于「黑边不遮红心」。
static func _triangle_ring_mesh(size: Vector2, scale: float) -> ArrayMesh:
	var hw := size.x * 0.5
	var hh := size.y * 0.5
	var ow := hw * scale
	var oh := hh * scale
	var inner := [Vector3(-hw, hh, 0.0), Vector3(hw, hh, 0.0), Vector3(0.0, -hh, 0.0)]
	var outer := [Vector3(-ow, oh, 0.0), Vector3(ow, oh, 0.0), Vector3(0.0, -oh, 0.0)]
	var verts := PackedVector3Array()
	for k in 3:
		var n := (k + 1) % 3
		verts.push_back(outer[k]); verts.push_back(outer[n]); verts.push_back(inner[n])
		verts.push_back(outer[k]); verts.push_back(inner[n]); verts.push_back(inner[k])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## 回合标识：加粗描边的黑色倒三角 + 顶部「看牌」提示（各自 billboard）。
func _make_turn_marker(size: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "TurnMarker"
	var outline := MeshInstance3D.new()
	outline.name = "Outline"
	outline.mesh = _triangle_ring_mesh(size, TURN_MARKER_OUTLINE_SCALE)
	outline.material_override = _marker_material(TURN_MARKER_OUTLINE_COLOR)
	root.add_child(outline)
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	fill.mesh = _triangle_mesh(size)
	fill.material_override = _marker_material(TURN_MARKER_COLOR)
	root.add_child(fill)
	var hint := Label3D.new()
	hint.name = "LookHint"
	hint.text = TURN_MARKER_HINT
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint.no_depth_test = true
	hint.pixel_size = 0.002
	hint.font_size = 96
	hint.modulate = TURN_MARKER_HINT_COLOR
	hint.position = TURN_MARKER_HINT_OFFSET
	root.add_child(hint)
	return root

func _marker_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	return mat

## 屏幕中心射线拾取（准星）。
func pick_center() -> Dictionary:
	if camera == null:
		return {}
	var center := get_viewport().get_visible_rect().size * 0.5
	return Table3dPicker.pick(camera.camera_node(), get_world_3d(), center)

## 每帧让大牌绕世界 Y 朝向本机相机（保持竖直，不用含俯仰的完全 billboard）。
## 位置不变，只重写 basis：本地 +Y（卡面法向）→ 水平指向相机；本地 +Z（卡高）→ 世界向上。
func update_facing() -> void:
	if _pending_node == null or not is_instance_valid(_pending_node) or camera == null:
		return
	var cam: Camera3D = camera.camera_node()
	if cam == null:
		return
	var node := _pending_node as Node3D
	var origin := node.global_position
	var to_cam := cam.global_position - origin
	to_cam.y = 0.0
	if to_cam.length_squared() < 0.0001:
		return
	var fwd := to_cam.normalized()
	var up := Vector3.UP
	var x := fwd.cross(up)
	if x.length_squared() < 0.0001:
		x = Vector3.RIGHT
	x = x.normalized()
	node.global_transform = Transform3D(Basis(x, fwd, up), origin)

## 瞬时揭示某槽位（水平翻到正面，dur 秒后翻回）。槽位不存在则忽略；
## 记录在 `_reveals`，`render` 重建卡牌后会重新应用（否则状态广播会把翻牌冲掉）。
func reveal_slot(seat_id: int, slot: int, card: Dictionary, color := Color(0, 0, 0, 0), dur := 1.5) -> void:
	var key := "%d_%d" % [seat_id, slot]
	_reveal_seq += 1
	var token := _reveal_seq
	_reveals[key] = {"card": card, "color": color, "token": token, "start_ms": Time.get_ticks_msec()}
	_apply_reveal(seat_id, slot)
	get_tree().create_timer(dur).timeout.connect(func():
		if not _reveals.has(key):
			return
		if int(_reveals[key].get("token", -1)) != token:
			return   # 已被更新的揭示取代
		_reveals.erase(key)
		var b = _find_block(seat_id, slot)
		if b != null:
			b.restore())

## 他人 peek 占位揭示：翻到"黑底闭眼"面 + 颜色光晕，到时翻回。跨 render 重放（同 reveal_slot）。
## hold=true 时不自动翻回（用于 Q 的两张看牌：保持到本次决策），由 release_hidden_reveals() 释放。
func reveal_hidden_slot(seat_id: int, slot: int, color := Color(0, 0, 0, 0), dur := 1.5, hold := false) -> void:
	var key := "%d_%d" % [seat_id, slot]
	_reveal_seq += 1
	var token := _reveal_seq
	var entry := {"hidden": true, "color": color, "token": token, "start_ms": Time.get_ticks_msec()}
	if hold:
		entry["hold"] = true
	_reveals[key] = entry
	_apply_reveal(seat_id, slot)
	if hold:
		return
	get_tree().create_timer(dur).timeout.connect(func():
		if not _reveals.has(key):
			return
		if int(_reveals[key].get("token", -1)) != token:
			return   # 已被更新的揭示取代
		_reveals.erase(key)
		var b = _find_block(seat_id, slot)
		if b != null:
			b.restore())

## 释放所有 hold 的闭眼占位揭示（Q 决策结束时调用）：翻回背面。
func release_hidden_reveals() -> void:
	var keys: Array = []
	for key in _reveals.keys():
		var r: Dictionary = _reveals[key]
		if bool(r.get("hidden", false)) and bool(r.get("hold", false)):
			keys.append(key)
	for key in keys:
		_reveals.erase(key)
		var parts := str(key).split("_")
		var b = _find_block(int(parts[0]), int(parts[1]))
		if b != null:
			b.restore()

## 持续揭示某槽位（翻到正面并**保持**，不自动翻回；Q 能力确认交换/不交换前用）。
## 同样登记在 `_reveals`，render 重建后 `_apply_reveal` 重放（elapsed 已过翻转时长 → 直接呈现正面）。
func reveal_slot_held(seat_id: int, slot: int, card: Dictionary, color := Color(0, 0, 0, 0)) -> void:
	var key := "%d_%d" % [seat_id, slot]
	_reveal_seq += 1
	_reveals[key] = {"card": card, "color": color, "token": _reveal_seq, "start_ms": Time.get_ticks_msec(), "hold": true}
	_apply_reveal(seat_id, slot)

## 某槽位是否为 Q hold 揭示。
func has_held_reveal(seat_id: int, slot: int) -> bool:
	var key := "%d_%d" % [seat_id, slot]
	return _reveals.has(key) and bool(_reveals[key].get("hold", false))

## 结算联动翻面：把背面槽位翻到 card 正面并**保持**（跨 render 重放；标记 settle）。
## 持续到下一局开始 / 房间重置时由 clear_settle_reveals() 显式清理。
func reveal_slot_settle(seat_id: int, slot: int, card: Dictionary) -> void:
	var key := "%d_%d" % [seat_id, slot]
	if _reveals.has(key) and bool(_reveals[key].get("settle", false)):
		return  # 已翻过（同一局多次 render 不会重播翻面）
	_reveal_seq += 1
	_reveals[key] = {"card": card, "color": Color(0, 0, 0, 0), "token": _reveal_seq,
		"start_ms": Time.get_ticks_msec(), "hold": true, "settle": true}
	_apply_reveal(seat_id, slot)

## 清除结算翻转（下一局开始/房间重置时调用）：直接翻回背面（不播动画）。
func clear_settle_reveals() -> void:
	for key in _reveals.keys():
		if bool(_reveals[key].get("settle", false)):
			_reveals.erase(key)
	for seat in _card_blocks.keys():
		for slot in _card_blocks[seat].keys():
			var b = _card_blocks[seat][slot]
			if b != null and is_instance_valid(b):
				(b as CardBlock).restore()

## 取走某槽位的 hold 揭示（不翻回，供交换飞牌从正面起飞），返回揭示牌面（无则 {}）。
func take_held_reveal(seat_id: int, slot: int) -> Dictionary:
	var key := "%d_%d" % [seat_id, slot]
	if not _reveals.has(key) or not bool(_reveals[key].get("hold", false)):
		return {}
	var card: Dictionary = _reveals[key].get("card", {})
	_reveals.erase(key)
	return card

## 释放全部 hold 揭示：animate_back=true 翻回背面（跨 render 续播，不瞬切），false 立即清除。
func release_held_reveals(animate_back := true) -> void:
	var now := Time.get_ticks_msec()
	for key in _reveals.keys():
		var r: Dictionary = _reveals[key]
		if not bool(r.get("hold", false)):
			continue
		if animate_back:
			r["hold"] = false
			r["releasing"] = true
			r["release_ms"] = now
			var token := int(r.get("token", -1))
			var k := str(key)
			get_tree().create_timer(CardBlock.FLIP_DURATION + 0.05).timeout.connect(func():
				if _reveals.has(k) and int(_reveals[k].get("token", -1)) == token:
					_reveals.erase(k)
					_refresh())
			var parts := str(key).split("_")
			_apply_reveal(int(parts[0]), int(parts[1]))
		else:
			_reveals.erase(key)
			var parts2 := str(key).split("_")
			var b = _find_block(int(parts2[0]), int(parts2[1]))
			if b != null:
				b.restore()

## 对当前（可能刚重建的）卡牌应用登记中的揭示。
## 按揭示已过时间计算翻转进度：重放时**续播**而非从 0 重播（已完成则直接呈现正面、不再翻），
## 避免状态广播 / 飞牌落地刷新把揭示重播一次（表现为翻完又显示正面 + 重新打炫光，见 B37）。
func _apply_reveal(seat_id: int, slot: int) -> void:
	var key := "%d_%d" % [seat_id, slot]
	if not _reveals.has(key):
		return
	var r: Dictionary = _reveals[key]
	var b = _find_block(seat_id, slot)
	if b == null:
		return
	if bool(r.get("releasing", false)):
		# Q hold 释放：按距 release_ms 的已过时间算当前进度并续播到背面
		var rel_elapsed := (Time.get_ticks_msec() - int(r.get("release_ms", 0))) / 1000.0
		var rp := 1.0 - clampf(rel_elapsed / CardBlock.FLIP_DURATION, 0.0, 1.0)
		(b as CardBlock).reveal_from_to(r.get("card", {}), r.get("color", Color(0, 0, 0, 0)), rp, 0.0)
		return
	if bool(r.get("hidden", false)):
		# 他人 peek 占位面：按已过时间续播到闭眼面
		var h_elapsed := (Time.get_ticks_msec() - int(r.get("start_ms", 0))) / 1000.0
		var hp := clampf(h_elapsed / CardBlock.FLIP_DURATION, 0.0, 1.0)
		(b as CardBlock).reveal_hidden(r.get("color", Color(0, 0, 0, 0)), hp)
		return
	var elapsed := (Time.get_ticks_msec() - int(r.get("start_ms", 0))) / 1000.0
	var p := clampf(elapsed / CardBlock.FLIP_DURATION, 0.0, 1.0)
	(b as CardBlock).reveal(r.get("card", {}), r.get("color", Color(0, 0, 0, 0)), p)

## 短暂染色提醒（不翻面）。登记到 `_flashes`，render 重建卡牌后按剩余时间重新应用
## （等价 2D `_peek_glow_slots`）——否则 peek_highlight 紧跟着的状态广播会重建卡牌、冲掉光晕。
func flash_slot(seat_id: int, slot: int, color: Color, dur: float) -> void:
	_flashes["%d_%d" % [seat_id, slot]] = {"color": color, "until_ms": Time.get_ticks_msec() + int(dur * 1000.0)}
	_apply_flash(seat_id, slot)

## 对当前（可能刚重建的）卡牌应用登记中的光晕；已过期则清除登记。
func _apply_flash(seat_id: int, slot: int) -> void:
	var key := "%d_%d" % [seat_id, slot]
	if not _flashes.has(key):
		return
	var f: Dictionary = _flashes[key]
	var remain_ms := int(f.get("until_ms", 0)) - Time.get_ticks_msec()
	if remain_ms <= 0:
		_flashes.erase(key)
		return
	var block = _find_block(seat_id, slot)
	if block != null:
		block.flash(f.get("color", Color(0, 0, 0, 0)), remain_ms / 1000.0)

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

## 每帧准星悬停：命中可点对象时显示边框，返回是否命中。命中目标未变则不重复操作。
## selection_active：当前是否处于"需要选择"的上下文（interaction.action_mode != ""）。
func update_hover(selection_active := false) -> bool:
	_sel_active = selection_active
	if camera == null:
		return false
	var center := get_viewport().get_visible_rect().size * 0.5
	var hit := Table3dPicker.pick_hit(camera.camera_node(), get_world_3d(), center)
	_hover_kind = str((hit.get("pick", {}) as Dictionary).get("kind", ""))
	_hover_card = null
	if NOSE_PICK_KINDS.has(_hover_kind):
		var hc = hit.get("collider")
		if hc != null and is_instance_valid(hc):
			var hp = (hc as Node).get_parent()
			if hp is Node3D and is_instance_valid(hp):
				_hover_card = hp
	var collider = hit.get("collider")
	# 上一次悬停对象可能已被 render 重建释放 → 先判有效（避免传已释放对象触发类型错误）
	var prev = _hover_collider if (_hover_collider != null and is_instance_valid(_hover_collider)) else null
	if collider != prev:
		_apply_hover(prev, false)
		_hover_collider = collider
		_apply_hover(collider, true)
	_update_hover_pose(hit)
	return collider != null

## 仅 viewer 自己手牌槽驱动抬起/倾斜；其他 kind/座位不动 pose。
func _update_hover_pose(hit: Dictionary) -> void:
	var meta: Dictionary = hit.get("pick", {})
	var is_slot := str(meta.get("kind", "")) == "slot"
	if not is_slot:
		_leave_hover_slot()
		return
	var seat := int(meta.get("seat", -1))
	var slot := int(meta.get("slot", -1))
	var b = _find_block(seat, slot)
	if b == null or not b.hover_anim_enabled:
		_leave_hover_slot()
		return
	var rl := _ray_local_for_block(b, hit.get("position", Vector3.ZERO))
	_hover_ray_local = rl
	var same := not _hover_slot.is_empty() and int(_hover_slot.get("seat", -1)) == seat and int(_hover_slot.get("slot", -1)) == slot
	if same:
		b.set_hover_pose(true, rl)
	else:
		_leave_hover_slot()
		_hover_slot = {"seat": seat, "slot": slot}
		b.set_hover_pose(true, rl, false)

## 清除悬停高亮。
func clear_hover() -> void:
	var prev = _hover_collider if (_hover_collider != null and is_instance_valid(_hover_collider)) else null
	_apply_hover(prev, false)
	_hover_collider = null
	_hover_kind = ""
	_hover_card = null
	_leave_hover_slot()

## 当前悬停对象的 pick 元数据（{} = 无）。
func hovered_pick() -> Dictionary:
	if _hover_collider == null or not is_instance_valid(_hover_collider):
		return {}
	return _hover_collider.get_meta("pick", {}) if _hover_collider.has_meta("pick") else {}

## 中央大牌的世界坐标（用于把解释气泡投影到屏幕上）。
func pending_global_position() -> Vector3:
	if _pending_block == null or not is_instance_valid(_pending_block):
		return Vector3.ZERO
	return _pending_block.global_position

## 当前悬停卡牌的已知牌面（未知/非卡牌返回 {}）。
func hovered_card() -> Dictionary:
	if _hover_collider == null or not is_instance_valid(_hover_collider):
		return {}
	var parent = _hover_collider.get_parent()
	if parent != null and parent.has_method("known_card"):
		return parent.known_card()
	return {}

## 当前悬停卡牌的屏幕外接矩形（视口像素）。
func hovered_screen_rect(cam: Camera3D) -> Rect2:
	if _hover_collider == null or not is_instance_valid(_hover_collider):
		return Rect2()
	var parent = _hover_collider.get_parent()
	if parent is Node3D:
		return _node_screen_rect(parent, cam)
	return Rect2()

## 中央大牌投影到屏幕的外接矩形（视口像素坐标）。
func pending_screen_rect(cam: Camera3D) -> Rect2:
	return _node_screen_rect(_pending_block, cam)

func _node_screen_rect(node: Node3D, cam: Camera3D) -> Rect2:
	if node == null or not is_instance_valid(node) or cam == null:
		return Rect2()
	var xf: Transform3D = node.global_transform
	var hx := Table3dLayout.BLOCK_SIZE.x * 0.5
	var hz := Table3dLayout.BLOCK_SIZE.z * 0.5
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for p in [Vector3(-hx, 0.0, -hz), Vector3(hx, 0.0, -hz), Vector3(hx, 0.0, hz), Vector3(-hx, 0.0, hz)]:
		var sp := cam.unproject_position(xf * p)
		mn = Vector2(minf(mn.x, sp.x), minf(mn.y, sp.y))
		mx = Vector2(maxf(mx.x, sp.x), maxf(mx.y, sp.y))
	return Rect2(mn, mx - mn)

## 高亮/取消：卡牌类（CardBlock）显示外延虚线边框（白/绿/红）；其余用叠加薄色。
## ===== 桌面标记（波纹 ping）=====
## 在 pos 生成标记；style=ripple 出波纹+箭头，style=nose 驱动该席鼻子并只显示图标。
## icon: eye/question/number/exclaim；text 仅 number 用。同席替换。
func show_mark(seat_id: int, pos: Vector3, style := "ripple", icon := "eye", text := "") -> void:
	_bind()
	if not _bound or not pos.is_finite():
		return
	var old = _marks.get(seat_id)
	if old != null and is_instance_valid(old):
		old.queue_free()
	var mark = Mark3DScript.new()
	var owner_pos := Vector3.ZERO
	var seat_node = _seat_node_by_id.get(seat_id)
	if seat_node != null and is_instance_valid(seat_node):
		owner_pos = (seat_node as Node3D).global_position
	add_child(mark)
	mark.global_position = pos
	mark.setup(Mark3dMathScript.arrow_dir_xz(pos, owner_pos), icon, text, style != "nose")
	var col = _mark_color_for(seat_id)
	if col != null:
		mark.set_color(col)
	if style == "nose":
		_set_seat_nose_target(seat_id, pos)
	mark.finished.connect(func():
		if _marks.get(seat_id) == mark:
			_marks.erase(seat_id)
			if style == "nose":
				_set_seat_nose_target(seat_id, Vector3.ZERO))
	_marks[seat_id] = mark

## 驱动某席鼻子到目标世界点（本机席→第一人称相机鼻；他人→其角色鼻）。ZERO=缩回。
func _set_seat_nose_target(seat_id: int, pos: Vector3) -> void:
	if seat_id == _viewer:
		if pos == Vector3.ZERO:
			clear_local_nose()
		else:
			set_local_nose_target_world(pos)
		return
	var node = _seat_node_by_id.get(seat_id)
	if node == null or not is_instance_valid(node):
		return
	var robot = (node as Node3D).get_node_or_null("Avatar/RobotAvatar")
	if robot != null:
		robot.set_nose_target_world(pos)

func clear_marks() -> void:
	for s in _marks.keys():
		var m = _marks[s]
		if m != null and is_instance_valid(m):
			m.queue_free()
	_marks.clear()
	clear_local_nose()
	for seat in _seat_node_by_id.keys():
		var n = _seat_node_by_id[seat]
		if n != null and is_instance_valid(n):
			var rb = (n as Node3D).get_node_or_null("Avatar/RobotAvatar")
			if rb != null:
				rb.set_nose_target_world(Vector3.ZERO)

## ===== 表情（占位：头顶数字 billboard）=====
## 生成某席表情；自己角色隐藏 → 忽略自己；同席替换。
func show_emote(seat_id: int, index: int) -> void:
	_bind()
	if not _bound or seat_id == _viewer:
		return
	var node = _seat_node_by_id.get(seat_id)
	if node == null or not is_instance_valid(node):
		return
	var avatar = (node as Node3D).get_node_or_null("Avatar")
	if avatar == null:
		return
	var old = _emotes.get(seat_id)
	if old != null and is_instance_valid(old):
		old.queue_free()
	var eye := 1.5
	if camera != null and camera.get("EYE_HEIGHT") != null:
		eye = float(camera.get("EYE_HEIGHT"))
	var head_top := RobotAvatar.MODEL_HEAD_TOP * RobotAvatar.SCALE - eye
	var disp = EmoteDisplayScript.new()
	avatar.add_child(disp)
	disp.position = Vector3(0.0, head_top + 0.5, 0.0)
	disp.play(index)
	disp.finished.connect(func():
		if _emotes.get(seat_id) == disp:
			_emotes.erase(seat_id))
	_emotes[seat_id] = disp

func clear_emotes() -> void:
	for s in _emotes.keys():
		var d = _emotes[s]
		if d != null and is_instance_valid(d):
			d.queue_free()
	_emotes.clear()

## 该席玩家的标记颜色（快照 players[].color，HTML）；无/非法返回 null（用默认红）。
func _mark_color_for(seat_id: int):
	for p in _last_state.get("players", []):
		if int(p.get("id", -1)) == seat_id:
			var c := str(p.get("color", ""))
			if not c.is_empty() and Color.html_is_valid(c):
				return Color.html(c)
	return null

## ===== 鼻子指针（中键）=====
## 建立本机第一人称鼻子（挂相机；本地 +Z 转到相机前向 -Z）。
func _ensure_local_nose() -> void:
	if _local_nose != null and is_instance_valid(_local_nose):
		return
	if camera == null:
		return
	var cam: Camera3D = camera.camera_node()
	if cam == null:
		return
	_local_nose = NoseAvatarScript.new()
	_local_nose.name = "LocalNose"
	_local_nose.transform = Transform3D(Basis(Vector3.UP, PI), LOCAL_NOSE_POS)
	cam.add_child(_local_nose)
	_local_nose.set_color(Color("F2C14E"))

## 当前悬停卡牌的**中心**世界坐标；非卡牌/无悬停返回 null。
func hovered_card_world():
	if _hover_card != null and is_instance_valid(_hover_card):
		return (_hover_card as Node3D).global_position
	return null

## 本机鼻根世界位置（供 main 用）。
func local_nose_base_world() -> Vector3:
	if _local_nose == null or not is_instance_valid(_local_nose):
		return Vector3.ZERO
	return _local_nose.global_position

## 本机第一人称鼻子：朝目标世界点定向、长度=鼻根到目标距离（ZERO=缩回）。
func set_local_nose_target_world(target_world: Vector3) -> void:
	_ensure_local_nose()
	if _local_nose == null:
		return
	if target_world == Vector3.ZERO or not target_world.is_finite():
		_local_nose.set_target(0.0)
		return
	var cam: Camera3D = camera.camera_node() if camera != null else null
	if cam == null:
		return
	var target_local: Vector3 = cam.global_transform.affine_inverse() * target_world
	var delta: Vector3 = target_local - LOCAL_NOSE_POS
	var dist := delta.length()
	if dist <= 0.0001:
		_local_nose.set_target(0.0)
		return
	var dn := delta / dist
	var up := Vector3.UP
	if absf(dn.dot(up)) > 0.99:
		up = Vector3.RIGHT
	_local_nose.transform = Transform3D(Basis.looking_at(dn, up, true), LOCAL_NOSE_POS)
	_local_nose.set_target(dist)

func local_nose_length() -> float:
	if _local_nose == null:
		return 0.0
	return _local_nose.length()

func local_nose_state_name() -> String:
	if _local_nose == null:
		return "IDLE"
	return _local_nose.state_name()

func clear_local_nose() -> void:
	if _local_nose != null:
		_local_nose.set_target(0.0)

## 每帧下发：远程各席鼻子目标世界坐标 + 本机相机鼻子目标世界坐标。
func update_noses(remote_nose: Dictionary, local_target: Vector3 = Vector3.ZERO) -> void:
	_bind()
	if not _bound:
		return
	for seat in _seat_node_by_id.keys():
		var node = _seat_node_by_id[seat]
		if node == null or not is_instance_valid(node):
			continue
		var avatar = (node as Node3D).get_node_or_null("Avatar")
		if avatar == null:
			continue
		var robot = avatar.get_node_or_null("RobotAvatar")
		if robot == null:
			continue
		var t = remote_nose.get(seat, Vector3.ZERO)
		robot.set_nose_target_world(t if t is Vector3 else Vector3.ZERO)
	set_local_nose_target_world(local_target)

## 高亮/取消：作用于该拾取对象父节点下所有 MeshInstance3D。
## 形参不标注类型：可能是已释放对象（传参处不做类型检查，函数内 is_instance_valid 兜底）。
func _apply_hover(collider, on: bool) -> void:
	if collider == null or not is_instance_valid(collider):
		return
	# 大牌（pending）只用于 hover 解释气泡，不显示虚线边框。
	if collider.has_meta("pick") and str((collider.get_meta("pick") as Dictionary).get("kind", "")) == "pending":
		return
	var parent = (collider as Node).get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	if parent.has_method("set_hover"):
		var col := Color(0, 0, 0, 0)
		if on:
			col = _hover_border_color(parent)
		parent.call("set_hover", on, col)
		return
	var meshes: Array = []
	_collect_meshes(parent, meshes)
	for m in meshes:
		m.material_overlay = _hover_material() if on else null

## hover 边框颜色：无选择上下文=白；有上下文且目标可操作=绿；否则=红。
func _hover_border_color(block) -> Color:
	if not _sel_active:
		return BORDER_WHITE
	var actionable: bool = block.has_method("is_actionable") and bool(block.call("is_actionable"))
	return BORDER_GREEN if actionable else BORDER_RED

func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)

func _hover_material() -> StandardMaterial3D:
	if _hover_mat == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = HOVER_COLOR
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_hover_mat = mat
	return _hover_mat

## ===== 3D 换牌飞牌（card_exchange_animated 接入）=====

## 播放一条交换动画事件。3D 分支入口；2D 逻辑不受影响。
func animate_exchange(data: Dictionary) -> void:
	_bind()
	if not _bound or _last_state.is_empty():
		return
	match str(data.get("kind", "")):
		"replace":
			_anim_replace(data)
		"swap":
			_anim_swap(data)
		"discard":
			_anim_discard(data)
		"slap_penalty":
			_anim_slap_penalty(data)
		"slap_resolved":
			_anim_slap_resolved(data)
		"slap_gift":
			_anim_slap_gift(data)
		"effect_pass":
			_anim_effect_pass(data)
		"bomb_explode":
			_anim_bomb_explode(data)

## 座位世界坐标（render 登记；未渲染返回 ZERO）。用于把浮空面板锚到本机座位。
func seat_world(seat_id: int) -> Vector3:
	var node: Node3D = _seat_node_by_id.get(seat_id)
	if node == null or not is_instance_valid(node):
		return Vector3.ZERO
	return node.global_position

## 槽位世界变换（未渲染时按布局计算）。
## 基准必须是 **HandAnchor**（卡牌实际挂载点，已抬到桌面高度），不能用座位根节点
## （座位根在 y=0 地面）——否则未渲染槽（追加的第 5+/空槽）的目标会落到地面，
## 飞牌朝桌面下方扎、穿桌消失（罚牌飞牌"飞到一半消失"的根因）。
func slot_xform(seat_id: int, slot: int) -> Transform3D:
	var b = _find_block(seat_id, slot)
	if b != null and is_instance_valid(b):
		return (b as Node3D).global_transform
	var hand: Node3D = _hand_node_by_id.get(seat_id)
	if hand == null or not is_instance_valid(hand):
		return Transform3D.IDENTITY
	return hand.global_transform * _slot_local(slot)

## 座位本地槽位变换（与 _render_seat 定位一致：列关于座位中轴居中、行 (1-行) +Z）。
## 主牌 2 列（grid.x 0/1）以列中点对齐座位 x 中轴（x=0），故两列落在 ±半个列距。
func _slot_local(slot: int) -> Transform3D:
	var grid := Table3dLayout.slot_grid_pos(slot)
	var pitch := Vector2(
		Table3dLayout.BLOCK_SIZE.x + Table3dLayout.BLOCK_GAP.x,
		Table3dLayout.BLOCK_SIZE.z + Table3dLayout.BLOCK_GAP.z) * HAND_SPACING_SCALE
	return Transform3D(Basis.IDENTITY, Vector3(
		(0.5 - grid.x) * pitch.x,
		0.0,
		(1.0 - grid.y) * pitch.y))

## 中央节点世界变换（"deck" | "discard" | "pending"）。
func center_xform(kind: String) -> Transform3D:
	var node: Node3D = null
	match kind:
		"deck":
			node = _deck_node
		"discard":
			node = _discard_node
		"pending":
			node = _pending_node
	if node == null or not is_instance_valid(node):
		return Transform3D.IDENTITY
	return node.global_transform

## 槽位当前显示面是否正面（未知牌为 false）。
func slot_face_up(seat_id: int, slot: int) -> bool:
	var b = _find_block(seat_id, slot)
	return b != null and is_instance_valid(b) and (b as CardBlock).has_face_texture()

## 槽位牌面数据（render 登记；空/未知返回 {}）。
func slot_card(seat_id: int, slot: int) -> Dictionary:
	if _slot_cards.has(seat_id) and _slot_cards[seat_id].has(slot):
		return _slot_cards[seat_id][slot]
	return {}

func _mark_anim_slot(seat: int, slot: int) -> void:
	_anim_slots["%d_%d" % [seat, slot]] = true

func _unmark_anim_slot(seat: int, slot: int) -> void:
	_anim_slots.erase("%d_%d" % [seat, slot])

func _has_anim_slot(seat: int, slot: int) -> bool:
	return _anim_slots.has("%d_%d" % [seat, slot])

## 生成一张飞牌；on_land 在落地（finished）时先于重渲染调用。
func _spawn_fly(from: Transform3D, to: Transform3D, data: Dictionary,
		start_up: bool, end_up: bool, on_land := Callable()) -> CardFly:
	var f := CardFly.new()
	add_child(f)
	f.finished.connect(func():
		_flyers = _live_flyers()
		if on_land.is_valid():
			on_land.call()
		_refresh())
	f.play(from, to, data, start_up, end_up)
	_flyers.append(f)
	return f

func _live_flyers() -> Array:
	var out: Array = []
	for f in _flyers:
		if is_instance_valid(f) and (f as CardFly).is_flying():
			out.append(f)
	return out

## 用最近一次 state 重渲染（落地恢复显示）。
func _refresh() -> void:
	if _last_state.is_empty():
		return
	render(_last_state, _last_actionable)

## 切出 3D 时清空在途飞牌与标记（防残留隐藏槽）。
func _clear_exchange_anim() -> void:
	for f in _flyers:
		if is_instance_valid(f):
			f.queue_free()
	_flyers.clear()
	_anim_slots.clear()
	_discard_hold = false
	_discard_shown = {}
	_pending_hold = false
	_pending_seen = false
	_prev_pending = {}
	_prev_discard = {}
	_dealing = false

## 开局发牌动画：从中央抽牌堆逐张飞到各席手牌槽（按座位轮转），落地露出。
func play_deal(state: Dictionary) -> void:
	_bind()
	if not _bound or state.is_empty() or _dealing:
		return
	var seats: Array = _seat_node_by_id.keys()
	seats.sort()
	if seats.is_empty():
		return
	var max_slots := 0
	for p in state.get("players", []):
		max_slots = maxi(max_slots, (p.get("slots", []) as Array).size())
	if max_slots <= 0:
		return
	# 一个玩家一个玩家地发：按座位升序（从房主 seat0 开始），每人的手牌发完再下一个。
	var targets: Array = []
	for seat in seats:
		for r in max_slots:
			targets.append([int(seat), r])
	for t in targets:
		_mark_anim_slot(int(t[0]), int(t[1]))
	_dealing = true
	render(state)
	_run_deal(targets)

func _run_deal(targets: Array) -> void:
	for t in targets:
		await get_tree().create_timer(DEAL_INTERVAL / maxf(_deal_speed, 0.01)).timeout
		if not is_inside_tree() or not _dealing:
			return
		_spawn_fly(center_xform("deck"), slot_xform(int(t[0]), int(t[1])), {}, false, false,
			func(): _unmark_anim_slot(int(t[0]), int(t[1])))
	await get_tree().create_timer(DEAL_INTERVAL / maxf(_deal_speed, 0.01)).timeout
	_dealing = false

## main 每帧按空格设置（2.0 / 1.0）。
func set_deal_speed(s: float) -> void:
	_deal_speed = maxf(s, 0.01)

## 开始弃牌顶变换：记住"上一张"用于动画期间保留显示（避免下方为空）。
func _begin_discard_hold() -> void:
	_discard_shown = _prev_discard.duplicate()
	_discard_hold = true

## 弃牌顶变换结束：恢复显示新顶。
func _end_discard_hold() -> void:
	_discard_hold = false
	_discard_shown = {}

## 快照检测：pending 由空→非空 = 有人抽牌/取弃牌顶 → 播飞牌（viewer 无关，所有人可见）。
## 来源判定（无需协议字段）：弃牌顶未变 = 抽牌堆；弃牌顶变了 = 取弃牌顶。
func _detect_draw(pending: Dictionary, discard: Dictionary) -> void:
	if not _pending_seen or _pending_hold:
		return   # 进入 3D 首帧 / 已有在途抽牌飞牌：不触发
	if pending.is_empty():
		return
	if not _prev_pending.is_empty() and str(_prev_pending.get("card_id", "")) == str(pending.get("card_id", "")):
		return   # 同一张大牌，非新抽牌
	_anim_draw(pending, str(discard) != str(_prev_discard))

## 抽牌飞牌：牌从抽牌堆（或弃牌堆）飞到竖立大牌位置。行动者（可见牌面）飞行中翻到正面，他人一直背面。
func _anim_draw(pending: Dictionary, from_discard: bool) -> void:
	var face_up := pending.has("rank")
	var data: Dictionary = pending.duplicate()
	data.erase("source")
	data.erase("hidden")
	var from_x := center_xform("discard") if from_discard else center_xform("deck")
	var to_x := center_xform("pending")
	_pending_hold = true
	_spawn_fly(from_x, to_x, data if face_up else {}, false, face_up, func():
		_pending_hold = false)

func _anim_replace(data: Dictionary) -> void:
	var actor := int(data.get("actor", 0))
	var slot := int(data.get("slot", -1))
	if slot < 0:
		return
	var slot_up := slot_face_up(actor, slot)
	var from_x := slot_xform(actor, slot)
	_pending_block.visible = false
	_mark_anim_slot(actor, slot)
	_begin_discard_hold()
	# 旧牌 → 弃牌顶
	_spawn_fly(from_x, center_xform("discard"), data.get("old_data", {}), slot_up, true, func():
		_end_discard_hold())
	# 大牌 → 槽位（背面/正面按 viewer 是否行动者）
	_spawn_fly(center_xform("pending"), from_x, data.get("big_data", {}), _viewer == actor, slot_up, func():
		_unmark_anim_slot(actor, slot))

func _anim_swap(data: Dictionary) -> void:
	var a := int(data.get("a", 0))
	var a_slot := int(data.get("a_slot", -1))
	var b := int(data.get("b", 0))
	var b_slot := int(data.get("b_slot", -1))
	if a_slot < 0 or b_slot < 0:
		return
	var a_data: Dictionary = data.get("a_data", {})
	var b_data: Dictionary = data.get("b_data", {})
	var a_start := slot_face_up(a, a_slot)
	var b_start := slot_face_up(b, b_slot)
	# Q hold：行动者视角两张牌保持正面 → 从正面起飞、背面落地（落点是新的站牌）。
	var a_held := has_held_reveal(a, a_slot)
	var b_held := has_held_reveal(b, b_slot)
	if a_held:
		a_data = take_held_reveal(a, a_slot)
		a_start = true
	if b_held:
		b_data = take_held_reveal(b, b_slot)
		b_start = true
	var a_end := slot_face_up(b, b_slot)
	var b_end := slot_face_up(a, a_slot)
	if a_held:
		a_end = false
	if b_held:
		b_end = false
	var xa := slot_xform(a, a_slot)
	var xb := slot_xform(b, b_slot)
	_mark_anim_slot(a, a_slot)
	_mark_anim_slot(b, b_slot)
	# hold 的源卡正面朝上：起飞前隐藏，避免飞牌离场后源位残留正面（render 落地时重建）
	if a_held:
		var ba = _find_block(a, a_slot)
		if ba != null:
			ba.visible = false
	if b_held:
		var bb = _find_block(b, b_slot)
		if bb != null:
			bb.visible = false
	var counter := {"n": 2}
	var done := func():
		counter["n"] = int(counter["n"]) - 1
		if int(counter["n"]) <= 0:
			_unmark_anim_slot(a, a_slot)
			_unmark_anim_slot(b, b_slot)
	_spawn_fly(xa, xb, a_data, a_start, a_end, done)
	_spawn_fly(xb, xa, b_data, b_start, b_end, done)

func _anim_discard(data: Dictionary) -> void:
	var actor := int(data.get("actor", 0))
	_pending_block.visible = false
	_begin_discard_hold()
	_spawn_fly(center_xform("pending"), center_xform("discard"), data.get("big_data", {}),
		_viewer == actor, true, func():
			_end_discard_hold())

func _anim_slap_penalty(data: Dictionary) -> void:
	var peer := int(data.get("peer", 0))
	var slot := int(data.get("slot", -1))
	if slot < 0:
		return
	var to_x := slot_xform(peer, slot)
	_mark_anim_slot(peer, slot)
	# 罚牌不含牌面 → 背面飞入
	_spawn_fly(center_xform("deck"), to_x, {}, false, false, func():
		_unmark_anim_slot(peer, slot))

func _anim_slap_resolved(data: Dictionary) -> void:
	var target := int(data.get("target", 0))
	var slot := int(data.get("target_slot", -1))
	if slot < 0:
		return
	var from_x := slot_xform(target, slot)
	_mark_anim_slot(target, slot)
	_begin_discard_hold()
	# 被贴的牌已公开 → 正面飞去弃牌堆
	_spawn_fly(from_x, center_xform("discard"), data.get("card", {}), true, true, func():
		_unmark_anim_slot(target, slot)
		_end_discard_hold())

## 炸弹爆炸：隐藏爆炸槽位，0.7s 后恢复渲染（爆炸贴图由 main 播）。
func _anim_bomb_explode(data: Dictionary) -> void:
	var seat := int(data.get("seat", -1))
	var slots: Array = data.get("slots", [])
	if seat < 0 or slots.is_empty():
		return
	for s in slots:
		var slot := int(s)
		_mark_anim_slot(seat, slot)
		var b = _find_block(seat, slot)
		if b != null and is_instance_valid(b):
			(b as Node3D).visible = false
	get_tree().create_timer(0.7).timeout.connect(func():
		if not is_instance_valid(self) or not is_inside_tree():
			return
		for s in slots:
			_unmark_anim_slot(seat, int(s))
		_refresh())

## 6 效果：每名玩家选中的牌同时顺时针飞到下家槽位（隐私：非本人始终背面）。
func _anim_effect_pass(data: Dictionary) -> void:
	var moves: Array = data.get("moves", [])
	if moves.is_empty():
		return
	var slots := {}
	for m in moves:
		var fs := int(m.get("from_seat", -1))
		var fslot := int(m.get("from_slot", -1))
		var ts := int(m.get("to_seat", -1))
		var tslot := int(m.get("to_slot", -1))
		if fs < 0 or fslot < 0 or ts < 0 or tslot < 0:
			continue
		_mark_anim_slot(fs, fslot)
		_mark_anim_slot(ts, tslot)
		slots["%d_%d" % [fs, fslot]] = [fs, fslot]
		slots["%d_%d" % [ts, tslot]] = [ts, tslot]
	if slots.is_empty():
		return
	var remaining := {"n": 0}
	for m in moves:
		var fs := int(m.get("from_seat", -1))
		var fslot := int(m.get("from_slot", -1))
		var ts := int(m.get("to_seat", -1))
		var tslot := int(m.get("to_slot", -1))
		if fs < 0 or fslot < 0 or ts < 0 or tslot < 0:
			continue
		var face_up := _viewer == fs and slot_face_up(fs, fslot)
		var card: Dictionary = slot_card(fs, fslot) if face_up else {}
		remaining["n"] = int(remaining["n"]) + 1
		_spawn_fly(slot_xform(fs, fslot), slot_xform(ts, tslot), card, face_up, false, func():
			remaining["n"] = int(remaining["n"]) - 1
			if int(remaining["n"]) <= 0:
				for key in slots:
					var pair: Array = slots[key]
					_unmark_anim_slot(int(pair[0]), int(pair[1])))

func _anim_slap_gift(data: Dictionary) -> void:
	var actor := int(data.get("actor", 0))
	var own_slot := int(data.get("own_slot", -1))
	var target := int(data.get("target", 0))
	var target_slot := int(data.get("target_slot", -1))
	if own_slot < 0 or target_slot < 0:
		return
	var face_up := _viewer == actor
	var card: Dictionary = slot_card(actor, own_slot) if face_up else {}
	var from_x := slot_xform(actor, own_slot)
	var to_x := slot_xform(target, target_slot)
	_mark_anim_slot(actor, own_slot)
	_mark_anim_slot(target, target_slot)
	_spawn_fly(from_x, to_x, card, face_up, face_up, func():
		_unmark_anim_slot(actor, own_slot)
		_unmark_anim_slot(target, target_slot))
