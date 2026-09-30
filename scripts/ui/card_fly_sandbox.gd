class_name CardFlySandbox
extends Node3D
## 3D 换牌动画沙盒：复刻对局布局（4 座位手牌区 + 中央抽牌堆/弃牌堆/大牌位），
## 顶部 6 个按钮分别触发 6 种 card_exchange_animated kind。
## 纯展示原型：不接游戏逻辑/协议/快照。

const SAMPLE_CARDS := [
	{"rank": "A", "suit": "♥"},
	{"rank": "K", "suit": "♠"},
	{"rank": "Q", "suit": "♦"},
	{"rank": "J", "suit": "♣"},
	{"rank": "10", "suit": "♥"},
	{"rank": "9", "suit": "♠"},
]
const KIND_ORDER := ["replace", "swap", "discard", "slap_penalty", "slap_resolved", "slap_gift"]
const SEAT_COUNT := 4
const CARDS_PER_SEAT := 4
const DECK_POS := Vector3(0.0, 0.03, 0.0)
const DISCARD_POS := Vector3(0.9, 0.03, 0.0)
const PENDING_POS := Vector3(0.0, 0.05, 0.0)
const PENDING_CARD := {"rank": "8", "suit": "♠"}

var camera: Table3dCamera
var _seat_nodes: Array = []
var _seat_blocks := {}
var _deck: Node3D
var _discard: Node3D
var _pending: Node3D
var _flying: Array = []
var _hidden := {}
var _hud: Label

func _ready() -> void:
	_build()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build() -> void:
	if not _seat_nodes.is_empty():
		return
	camera = get_node_or_null("CameraRig")
	_deck = _make_center("Deck", DECK_POS, {})
	_discard = _make_center("DiscardTop", DISCARD_POS, {"rank": "3", "suit": "♥"})
	_pending = _make_center("Pending", PENDING_POS, PENDING_CARD)
	var angles := Table3dLayout.seat_angles(SEAT_COUNT)
	for i in SEAT_COUNT:
		var a := float(angles[i])
		var node := Node3D.new()
		node.name = "Seat%d" % i
		add_child(node)
		node.position = Vector3(sin(deg_to_rad(a)), 0.0, cos(deg_to_rad(a))) * Table3dLayout.SEAT_RADIUS
		node.rotation_degrees = Vector3(0.0, a + 180.0, 0.0)
		_seat_nodes.append(node)
		_seat_blocks[i] = {}
		for slot in CARDS_PER_SEAT:
			var block := CardBlock.new()
			var grid := Table3dLayout.slot_grid_pos(slot)
			block.position = Vector3(
				-grid.x * (Table3dLayout.BLOCK_SIZE.x + Table3dLayout.BLOCK_GAP.x),
				0.0,
				(1.0 - grid.y) * (Table3dLayout.BLOCK_SIZE.z + Table3dLayout.BLOCK_GAP.z))
			node.add_child(block)
			block.setup({"card": SAMPLE_CARDS[(i * CARDS_PER_SEAT + slot) % SAMPLE_CARDS.size()]})
			_seat_blocks[i][slot] = block
	_build_ui()

func _make_center(node_name: String, pos: Vector3, card: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = pos
	add_child(node)
	var block := CardBlock.new()
	node.add_child(block)
	block.setup({"card": card} if not card.is_empty() else {})
	return node

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.position = Vector2(12.0, 8.0)
	layer.add_child(row)
	for kind in KIND_ORDER:
		var b := Button.new()
		b.text = kind
		b.pressed.connect(play.bind(kind))
		row.add_child(b)
	var reset := Button.new()
	reset.text = "reset"
	reset.pressed.connect(_reset)
	row.add_child(reset)
	_hud = Label.new()
	_hud.name = "Hud"
	_hud.position = Vector2(12.0, 48.0)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	layer.add_child(_hud)

func _process(_delta: float) -> void:
	if _hud != null:
		_hud.text = "在途飞牌: %d" % flying_count()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and camera != null:
		camera.look(event.relative)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## 触发某一 kind 的演示。
func play(kind: String) -> void:
	match kind:
		"replace":
			_play_replace()
		"swap":
			_play_swap()
		"discard":
			_hide(_pending.get_child(0))
			_fly(_pending.global_transform, _discard.global_transform, PENDING_CARD, true, true)
		"slap_penalty":
			_fly(_deck.global_transform, _seat_slot_xform(1, CARDS_PER_SEAT), {}, false, false)
		"slap_resolved":
			_hide(_seat_blocks[2][0])
			_fly(_seat_slot_xform(2, 0), _discard.global_transform, SAMPLE_CARDS[2], true, true)
		"slap_gift":
			_hide(_seat_blocks[0][2])
			_fly(_seat_slot_xform(0, 2), _seat_slot_xform(3, 2), {}, false, false)

func _play_replace() -> void:
	_hide(_seat_blocks[0][0])
	_fly(_seat_slot_xform(0, 0), _discard.global_transform, SAMPLE_CARDS[0], true, true)
	_fly(_deck.global_transform, _seat_slot_xform(0, 0), {"rank": "7", "suit": "♦"}, false, true)

func _play_swap() -> void:
	_hide(_seat_blocks[0][1])
	_hide(_seat_blocks[1][1])
	_fly(_seat_slot_xform(0, 1), _seat_slot_xform(1, 1), SAMPLE_CARDS[1], true, true)
	_fly(_seat_slot_xform(1, 1), _seat_slot_xform(0, 1), SAMPLE_CARDS[5], true, true)

func _reset() -> void:
	for f in _flying:
		if is_instance_valid(f):
			f.queue_free()
	_flying.clear()
	_restore_hidden()

## 座位槽位的世界变换（不依赖该槽是否已渲染）。
func _seat_slot_xform(seat: int, slot: int) -> Transform3D:
	var node: Node3D = _seat_nodes[seat]
	var grid := Table3dLayout.slot_grid_pos(slot)
	var local := Transform3D(Basis.IDENTITY, Vector3(
		-grid.x * (Table3dLayout.BLOCK_SIZE.x + Table3dLayout.BLOCK_GAP.x),
		0.0,
		(1.0 - grid.y) * (Table3dLayout.BLOCK_SIZE.z + Table3dLayout.BLOCK_GAP.z)))
	return node.global_transform * local

func _fly(from: Transform3D, to: Transform3D, data: Dictionary, start_up: bool, end_up: bool) -> CardFly:
	var f := CardFly.new()
	add_child(f)
	f.finished.connect(_on_flyer_done)
	f.play(from, to, data, start_up, end_up)
	_flying.append(f)
	return f

func _on_flyer_done() -> void:
	_flying = _live_flying()
	if _flying.is_empty():
		_restore_hidden()

func _live_flying() -> Array:
	var out: Array = []
	for f in _flying:
		if is_instance_valid(f) and (f as CardFly).is_flying():
			out.append(f)
	return out

func flying_count() -> int:
	return _live_flying().size()

func _hide(block) -> void:
	if block == null or not is_instance_valid(block):
		return
	_hidden[block] = true
	block.visible = false

func _restore_hidden() -> void:
	for b in _hidden.keys():
		if is_instance_valid(b):
			b.visible = true
	_hidden.clear()
