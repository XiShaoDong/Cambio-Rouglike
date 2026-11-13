extends Node
## 服务器侧热点基准（headless）：
##   Godot --headless --path . res://tests/bench_server.tscn
## 只测纯服务器逻辑：4 人快照投影 + JSON 体积；不建立真实 ENet 连接。

const PLAYERS := 4
const SNAPSHOTS := 5000

var failures := 0

func _ready() -> void:
	GameState.turn_effect_rules_enabled = false
	GameState._reset_match()
	for i in PLAYERS:
		GameState._add_player(1, "P%d" % i)
	GameState._server_start_match(0)
	for i in PLAYERS:
		GameState._server_initial_ready(i)
	# 制造 pending + 弃牌，覆盖更真实的快照路径
	GameState._server_take(0, "draw", "bench-draw")
	GameState._server_discard_draw(0, "bench-discard")
	# 预热
	for i in 1000:
		for v in PLAYERS:
			GameState._snapshot_for(v)

	var t0 := Time.get_ticks_usec()
	for i in SNAPSHOTS:
		for v in PLAYERS:
			GameState._snapshot_for(v)
	var t1 := Time.get_ticks_usec()
	var total_us := t1 - t0
	var per_snapshot := float(total_us) / float(SNAPSHOTS * PLAYERS)
	var per_broadcast := float(total_us) / float(SNAPSHOTS)
	var json_bytes := JSON.stringify(GameState._snapshot_for(0)).length()
	var snap := GameState._snapshot_for(0)

	print("=== SERVER BENCH ===")
	print("players=%d snapshots=%d viewers=%d" % [PLAYERS, SNAPSHOTS, PLAYERS])
	print("snapshot_us_avg=%.2f" % per_snapshot)
	print("4view_broadcast_us_avg=%.2f" % per_broadcast)
	print("4view_broadcast_per_sec=%.0f" % (1_000_000.0 / maxf(per_broadcast, 0.001)))
	print("snapshot_json_bytes=%d" % json_bytes)
	print("snapshot_keys=%d" % snap.size())
	print("snapshot_players=%d" % (snap.get("players", []) as Array).size())
	print("per_action_4view_kb=%.1f" % (json_bytes * PLAYERS / 1024.0))
	# 60fps 单帧预算 16.7ms；一次 4 人广播占帧预算比例
	print("broadcast_pct_of_60fps_frame=%.3f%%" % (per_broadcast / 16666.7 * 100.0))
	print("=== END ===")
	get_tree().quit(1 if failures else 0)
