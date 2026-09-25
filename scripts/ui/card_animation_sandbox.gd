class_name CardAnimationSandbox
extends Node3D
## 卡牌交互动效沙盒：一排 5 张平放卡；屏幕中心准星 + 鼠标转相机；左键翻牌。
## 纯展示原型：不接游戏逻辑/协议/快照。

const SAMPLE_CARDS := [
	{"rank": "A", "suit": "♥"},
	{"rank": "K", "suit": "♠"},
	{"rank": "Q", "suit": "♦"},
	{"rank": "J", "suit": "♣"},
	{"rank": "10", "suit": "♥"},
]

var actor_gap := Table3dLayout.BLOCK_SIZE.x + 0.15
var actors: Array = []
var camera: Table3dCamera
var crosshair: Crosshair
var hovered := -1
var auto_hover := true
var _hud: Label

func _ready() -> void:
	_build()
	set_process(true)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build() -> void:
	camera = get_node_or_null("CameraRig")
	if camera != null:
		camera.frame_for_seat(0.0)
	var count := SAMPLE_CARDS.size()
	for i in count:
		var actor := CardAnimation.new()
		actor.name = "Card%d" % i
		actor.card_data = SAMPLE_CARDS[i]
		actor.position = Vector3((float(i) - float(count - 1) * 0.5) * actor_gap, 0.03, 0.0)
		actor.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		add_child(actor)
		# _ready 已在 add_child 时同步执行 → body 可用；挂 pick 元数据供准星拾取
		actor.body.set_pick({"kind": "card", "index": i})
		actors.append(actor)
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	crosshair = Crosshair.new()
	crosshair.name = "Crosshair"
	layer.add_child(crosshair)
	crosshair.set_active(false)
	_hud = Label.new()
	_hud.name = "Hud"
	_hud.position = Vector2(12, 8)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	layer.add_child(_hud)

func _process(_delta: float) -> void:
	if crosshair == null:
		return
	if auto_hover and camera != null:
		_update_hover()
	_update_hud()

func _update_hover() -> void:
	var center := get_viewport().get_visible_rect().size * 0.5
	var hit := Table3dPicker.pick_hit(camera.camera_node(), get_world_3d(), center)
	var idx := actors.find(_actor_from_collider(hit.get("collider")))
	if idx != hovered:
		if hovered >= 0 and hovered < actors.size():
			actors[hovered].exit_hover()
		hovered = idx
		if hovered >= 0:
			actors[hovered].enter_hover()
	if hovered >= 0:
		actors[hovered].ray_local = _ray_local_for(hit.get("position", Vector3.ZERO), actors[hovered])
	crosshair.set_active(hovered >= 0)

func _actor_from_collider(collider) -> Node:
	if collider == null or not is_instance_valid(collider):
		return null
	var n: Node = collider.get_parent()
	while n != null:
		if n is CardAnimation:
			return n
		n = n.get_parent()
	return null

func _ray_local_for(hit_pos: Vector3, actor: Node3D) -> Vector2:
	var p: Vector3 = actor.global_transform.affine_inverse() * hit_pos
	return Vector2(
		clampf(p.x / (Table3dLayout.BLOCK_SIZE.x * 0.5), -1.0, 1.0),
		clampf(p.z / (Table3dLayout.BLOCK_SIZE.z * 0.5), -1.0, 1.0))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and camera != null:
		camera.look(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hovered >= 0:
			actors[hovered].click()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## 测试/脚本入口：驱动指定卡。（"hover"/"unhover"/"flip"/"reset"）
func play(card_index: int, action: String) -> void:
	if card_index < 0 or card_index >= actors.size():
		return
	var a: CardAnimation = actors[card_index]
	match action:
		"hover":
			a.enter_hover()
		"unhover":
			a.exit_hover()
		"flip":
			a.enter_hover()
			a.click()
		"reset":
			a.reset()

func _update_hud() -> void:
	if _hud == null:
		return
	if hovered >= 0 and hovered < actors.size():
		var a: CardAnimation = actors[hovered]
		_hud.text = "card %d  state=%d  hover=%.2f press=%.2f flip=%.2f" % [hovered, a.state, a.hover_p, a.press_p, a.flip_p]
	else:
		_hud.text = "准星对准卡牌，左键翻牌"
