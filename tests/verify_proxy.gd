extends Node

## 网络条件注入（ProxyRelay UDP 中继）headless 验证：双实例（host + client 各跑一个进程）。
##   host  : godot --headless --path . res://tests/verify_proxy.tscn -- -role host -scenario <name> [-mode basic|reconnect]
##   client: godot --headless --path . res://tests/verify_proxy.tscn -- -role client -scenario <name> [-mode basic|reconnect]
## host 进程内会挂一个 ProxyRelay 中继（监听 7011 → 转发到真实服务器 7007），客户端连 7011。
##
## 场景（中继对双向数据报注入；每个场景打印"人话"说明，失败时打印提示）：
##   baseline     无注入（链路自检，等价 verify_net）
##   latency      固定 200ms 延迟：回合制对局在公网级延迟下能否正常推进
##   loss         20% 丢包：ENet 可靠通道重发后，状态是否最终一致、对局不卡死
##   jitter       0~150ms 抖动：延迟随机波动下回合推进/快照是否正常
##
## 模式：
##   basic     在注入条件下打完 target_turns 轮抽牌，验证对局正常收敛
##   reconnect 中继"拔网线"（黑障）→ ENet 超时掉线 → 服务器标记离线
##             → 客户端凭 token 重连 → 手牌恢复 → 对局继续
##
## 说明：丢包/乱序/重复发生在数据报层会被 ENet 可靠通道吸收（重传/排序/去重），
## 因此这里验证的是"链路物理特性（延迟/丢包/抖动/中断）下的健壮性"；
## RPC 层重复请求的幂等由 verify_protocol 的拒绝校验覆盖。

const RELAY_PORT := 7011

const SCENARIOS := {
	"baseline": {},
	"latency": {"latency": 200.0},
	"loss": {"loss": 0.2},
	"jitter": {"jitter": 150.0},
}

var role := ""
var scenario := "baseline"
var mode := "basic"
var deadline := 60.0
var done := false
var last_phase := -1
var turn_draw_count := 0
var started := false
var ready_sent := false
var lobby_count := 0
var latest_state: Dictionary = {}
var target_turns := 4

# reconnect 模式状态
var my_token := ""
var disconnect_handled := false
var offline_seen := false        # host：快照出现 offline_players 非空
var reconnected_seen := false    # host：offline 后快照恢复为空
var disconnect_seen := false     # client：检测到与服务器断开
var resume_seen := false         # client：重连后收到手牌恢复
var game_resumed := false        # client：重连后收到对局快照
var rejoin_timer := -1.0
var rejoin_started := false
var _retrying := false
var _retry_count := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var overrides := {}
	for i in range(args.size()):
		var a := args[i]
		if a == "-role" and i + 1 < args.size():
			role = args[i + 1]
		elif a == "-scenario" and i + 1 < args.size():
			scenario = args[i + 1]
		elif a == "-mode" and i + 1 < args.size():
			mode = args[i + 1]
		elif a == "-latency" and i + 1 < args.size():
			overrides["latency"] = float(args[i + 1])
		elif a == "-loss" and i + 1 < args.size():
			overrides["loss"] = float(args[i + 1])
		elif a == "-jitter" and i + 1 < args.size():
			overrides["jitter"] = float(args[i + 1])
		elif a == "-seed" and i + 1 < args.size():
			overrides["seed"] = int(args[i + 1])
	if role.is_empty():
		printerr("VERIFY FAIL: need -role host|client")
		get_tree().quit(1)
		return
	if not SCENARIOS.has(scenario):
		printerr("VERIFY FAIL: unknown scenario %s" % scenario)
		get_tree().quit(1)
		return
	var relay_params: Dictionary = SCENARIOS[scenario].duplicate()
	for k in overrides:
		relay_params[k] = overrides[k]
	relay_params["seed"] = int(relay_params.get("seed", 12345))
	if mode == "reconnect":
		target_turns = 3
		relay_params["blackout_at"] = 3000.0
		relay_params["blackout_duration"] = 8000.0
	_relay_params = relay_params
	print("[%s] 场景「%s」：%s" % [role, scenario, _scenario_label(scenario)])
	GameState.state_updated.connect(_on_state)
	GameState.lobby_updated.connect(_on_lobby)
	GameState.toast_received.connect(func(m): print("[%s] toast: %s" % [role, m]))
	GameState.registered_token_received.connect(func(t): my_token = t)
	GameState.resume_hand_received.connect(_on_resume_hand)
	GameState.command_rejected.connect(_on_rejected)
	Network.connection_status_changed.connect(_on_net_status)
	Network.joined_server.connect(_on_joined_server)
	if role == "host":
		Network.host_game({"name": "房主A"})
		# host 进程内挂中继：客户端连 RELAY_PORT，中继转发到真实服务器 7007
		var relay: Node = load("res://scripts/net/proxy_relay.gd").new()
		relay.configure(_relay_params)
		relay.listen_port = RELAY_PORT
		add_child(relay)
	else:
		Network.join_game("127.0.0.1", {"name": "玩家B"}, RELAY_PORT)
	print("[%s] starting (%s mode, 中继注入=%s)" % [role, mode, str(relay_params)])

var _relay_params := {}

func _scenario_label(name: String) -> String:
	match name:
		"baseline":
			return "基准无注入：验证链路与测试脚本本身可用"
		"latency":
			return "高延迟 200ms：回合制对局在公网级延迟下能否正常推进"
		"loss":
			return "20% 丢包：ENet 可靠通道重发后，状态是否最终一致、对局不卡死"
		"jitter":
			return "抖动 0~150ms：延迟随机波动下回合推进/快照是否正常"
	return "未知场景"

func _process(delta: float) -> void:
	if done:
		return
	deadline -= delta
	if deadline <= 0.0:
		print("VERIFY %s FAIL: 超时 (phase=%d turn_draw=%d mode=%s)\n  → %s" % [role, last_phase, turn_draw_count, mode, _fail_message()])
		get_tree().quit(1)
	# 重连模式：客户端断开后定时重新连接
	if mode == "reconnect" and role == "client" and disconnect_seen and not rejoin_started:
		rejoin_started = true
		rejoin_timer = 5.0
		print("[client] 5 秒后重新连接并重连")
	if rejoin_started and rejoin_timer > 0.0:
		rejoin_timer -= delta
		if rejoin_timer <= 0.0:
			rejoin_timer = 0.0
			Network.join_game("127.0.0.1", {"name": "玩家B"}, RELAY_PORT)
			print("[client] 已重新连接服务器，等待认领座位")

func _fail_message() -> String:
	if mode == "reconnect":
		if role == "host":
			return "重连模式超时：可能中继黑障未生效、服务器没标记离线(offline_seen=%s)，或客户端没重连上(reconnected_seen=%s)" % [offline_seen, reconnected_seen]
		return "重连模式超时：检查是否收到断开信号(disconnect_seen=%s)、token 是否保存、重连后是否收到手牌恢复(resume_seen=%s)" % [disconnect_seen, resume_seen]
	match scenario:
		"baseline":
			return "基准失败：测试链路本身有问题（连接/注册/开局），先确认 verify_net 是否通过"
		"latency":
			return "高延迟下超时：回合制不该受延迟影响——若失败说明某流程在等即时响应，或 ENet 超时配置过紧（可调 set_timeout 放宽）"
		"loss":
			return "丢包下未在时限内收敛：ENet 可靠通道未能按时重发到位，可能超时太紧，或某 RPC 依赖瞬时到达"
		"jitter":
			return "抖动下超时：延迟随机波动触发了错误分支，检查是否有基于固定延时的逻辑"
	return "未知场景失败"

func _on_lobby(lobby: Dictionary) -> void:
	lobby_count = lobby.players.size()
	print("[%s] lobby: %d 人" % [role, lobby_count])
	if role == "host" and lobby_count >= 2 and not started:
		started = true
		_run_host()

func _run_host() -> void:
	await get_tree().create_timer(0.5).timeout
	GameState.request_start_match()
	print("[host] 开局 sent")

func _on_state(state: Dictionary) -> void:
	latest_state = state
	var phase := int(state.phase)
	if phase != last_phase:
		print("[%s] phase -> %d (%s)" % [role, phase, state.phase_name])
		last_phase = phase
	var offline: Array = state.get("offline_players", [])
	if not offline.is_empty():
		if not offline_seen:
			print("[host] 服务器检测到玩家离线: %s" % str(offline))
		offline_seen = true
	elif offline_seen and not reconnected_seen:
		reconnected_seen = true
		print("[host] 离线者已重连，对局恢复在线")
	if phase == 1 and not ready_sent:
		ready_sent = true
		GameState.request_initial_ready()
		print("[%s] initial ready sent" % role)
		return
	if phase == 2:
		turn_draw_count += 1
		print("[%s] TURN_DRAW #%d current=%d viewer=%d" % [role, turn_draw_count, int(state.current_player), int(state.viewer_id)])
		_drive_turn()
		_check_done()
		return
	if phase == 3 and int(state.current_player) == int(state.viewer_id):
		GameState.request_replace(0)
		print("[%s] replace slot 0" % role)
	# 重连模式：客户端重连后确认对局继续
	if mode == "reconnect" and role == "client" and resume_seen and not game_resumed and phase in [1, 2, 3, 4, 5, 6, 7, 8]:
		game_resumed = true
		print("[client] 重连后收到对局快照，对局继续")
		_check_done()

func _drive_turn() -> void:
	if int(latest_state.current_player) == int(latest_state.viewer_id):
		GameState.request_take("draw")
		print("[%s] take draw" % role)

func _check_done() -> void:
	if done:
		return
	if mode == "basic":
		if turn_draw_count >= target_turns:
			done = true
			print("VERIFY %s PASS: 场景「%s」— %s" % [role, scenario, _scenario_label(scenario)])
			await get_tree().create_timer(2.0).timeout
			get_tree().quit(0)
		return
	# reconnect
	if role == "host":
		if offline_seen and reconnected_seen and turn_draw_count >= target_turns:
			done = true
			print("VERIFY host PASS: 断线重连 — 服务器标记离线 → 客户端重连 → 对局继续轮转")
			await get_tree().create_timer(2.0).timeout
			get_tree().quit(0)
	else:
		if disconnect_seen and resume_seen and game_resumed:
			done = true
			print("VERIFY client PASS: 断线重连 — 拔线 → 凭 token 重连 → 手牌恢复 → 对局继续")
			await get_tree().create_timer(2.0).timeout
			get_tree().quit(0)

func _on_resume_hand(_hand: Array, _pending: Dictionary) -> void:
	if mode == "reconnect" and role == "client":
		resume_seen = true
		print("[client] 重连后收到手牌恢复数据（resume_hand）")

func _on_net_status(message: String) -> void:
	print("[%s] 连接状态: %s" % [role, message])
	if mode == "reconnect" and role == "client" and message.contains("断开"):
		disconnect_seen = true
		print("[client] 检测到连接断开")

func _on_joined_server() -> void:
	if mode == "reconnect" and role == "client" and disconnect_seen:
		_try_reconnect()

func _try_reconnect() -> void:
	if my_token.is_empty():
		printerr("VERIFY %s FAIL: 未保存 token，无法重连" % role)
		get_tree().quit(1)
		return
	if _retry_count >= 5:
		printerr("VERIFY %s FAIL: 重连重试超限" % role)
		get_tree().quit(1)
		return
	_retry_count += 1
	print("[client] 重连服务器，凭 token 认领原座位 (#%d)" % _retry_count)
	GameState.request_reconnect(my_token, "玩家B")

func _on_rejected(code: int, _message: String) -> void:
	if mode == "reconnect" and role == "client" and disconnect_seen \
			and code == GameState.RejectCode.INVALID_TOKEN and not _retrying:
		_retrying = true
		print("[client] 服务器尚未把旧连接标记离线（INVALID_TOKEN），稍后重试")
		await get_tree().create_timer(0.5).timeout
		_retrying = false
		if not done:
			_try_reconnect()