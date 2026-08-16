extends Node

## E1 双实例自动化验证（headless）：
##   host  : godot --headless --path . res://tests/verify_net.tscn -- -role host
##   client: godot --headless --path . res://tests/verify_net.tscn -- -role client
## 验证：建房→加入→注册→开局→抽牌→替换→贴牌超时→轮转，共 4 次行动。

var role := ""
var latest_state: Dictionary = {}
var lobby_count := 0
var turn_draw_count := 0
var last_phase := -1
var deadline := 90.0
var started := false
var ready_sent := false
const TARGET_TURNS := 4
var done := false

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg == "-role":
			continue
		if arg == "host" or arg == "client":
			role = arg
	if role.is_empty():
		print("VERIFY FAIL: need -role host|client")
		get_tree().quit(1)
		return
	GameState.state_updated.connect(_on_state)
	GameState.lobby_updated.connect(_on_lobby)
	GameState.toast_received.connect(func(m): print("[%s] toast: %s" % [role, m]))
	if role == "host":
		Network.host_game({"name": "房主A"})
	else:
		Network.join_game("127.0.0.1", {"name": "玩家B"})
	print("[%s] starting" % role)

func _process(delta: float) -> void:
	if done:
		return
	deadline -= delta
	if deadline <= 0.0:
		print("VERIFY %s FAIL: timeout at phase=%d turn_draw=%d" % [role, last_phase, turn_draw_count])
		get_tree().quit(1)

func _on_lobby(lobby: Dictionary) -> void:
	lobby_count = lobby.players.size()
	print("[%s] lobby update: %d players" % [role, lobby_count])
	if role == "host" and lobby_count >= 2 and not started:
		started = true
		_run_host()

func _on_state(state: Dictionary) -> void:
	latest_state = state
	var phase := int(state.phase)
	if phase != last_phase:
		print("[%s] phase -> %d (%s)" % [role, phase, state.phase_name])
		last_phase = phase
	if phase == 1 and not ready_sent:
		ready_sent = true
		GameState.request_initial_ready()
		print("[%s] initial ready sent" % role)
		return
	if phase == 2:
		turn_draw_count += 1
		print("[%s] TURN_DRAW #%d current=%d viewer=%d" % [role, turn_draw_count, int(state.current_player), int(state.viewer_id)])
		if turn_draw_count >= TARGET_TURNS and not done:
			done = true
			print("VERIFY %s PASS: reached %d turn draws" % [role, TARGET_TURNS])
			get_tree().quit(0)
			return
		if role == "host":
			_run_host_turn()
		else:
			_run_client_turn()
	if phase == 3 and role == "host" and int(state.current_player) == int(state.viewer_id):
		GameState.request_replace(0)
		print("[host] replace slot 0")
	if phase == 3 and role == "client" and int(state.current_player) == int(state.viewer_id):
		GameState.request_replace(0)
		print("[client] replace slot 0")

func _run_host() -> void:
	await get_tree().create_timer(0.5).timeout
	GameState.request_start_match()
	print("[host] start match sent")

func _run_host_turn() -> void:
	if int(latest_state.current_player) == int(latest_state.viewer_id):
		GameState.request_take("draw")
		print("[host] take draw")

func _run_client_turn() -> void:
	if int(latest_state.current_player) == int(latest_state.viewer_id):
		GameState.request_take("draw")
		print("[client] take draw")
