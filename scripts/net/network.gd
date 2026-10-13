class_name KongNetwork
extends Node

signal host_started(profile: Dictionary)
signal join_started()
signal joined_server()
signal connection_failed(message: String)
signal peer_left(peer_id: int)
signal connection_status_changed(message: String)

const DEFAULT_PORT := 7007

var local_profile: Dictionary = {"name": "玩家"}
var is_host := false
var host_is_player := true   # host 是否作为玩家占座：玩家-host=true；专用服务器=false
var dedicated := false       # 是否专用（中立）服务器模式

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

## 每局允许的客户端数：玩家-host 时房主占 1 席（-1），专用服务器不占席。
func max_clients() -> int:
	return KongRules.MAX_PLAYERS - (1 if host_is_player else 0)

## 创建房间。as_player=false 时本进程只做权威、不占玩家座位（专用服务器）。
func host_game(profile: Dictionary, port := DEFAULT_PORT, as_player := true) -> void:
	disconnect_game(false)
	host_is_player = as_player
	dedicated = not as_player
	local_profile = profile
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_clients())
	if error != OK:
		connection_failed.emit("无法在端口 %d 创建房间（错误 %d）" % [port, error])
		return
	multiplayer.multiplayer_peer = peer
	is_host = true
	connection_status_changed.emit("房间已创建，等待玩家加入")
	host_started.emit(local_profile)

## 专用（中立）服务器：不占玩家座位。供 headless 入口调用。
func start_dedicated(port := DEFAULT_PORT) -> void:
	host_game({"name": "服务器"}, port, false)

func join_game(address: String, profile: Dictionary, port := DEFAULT_PORT) -> void:
	disconnect_game(false)
	local_profile = profile
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address.strip_edges(), port)
	if error != OK:
		connection_failed.emit("无法连接 %s:%d（错误 %d）" % [address, port, error])
		return
	multiplayer.multiplayer_peer = peer
	is_host = false
	connection_status_changed.emit("正在连接 %s:%d…" % [address, port])
	join_started.emit()

func disconnect_game(show_message := true) -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_host = false
	host_is_player = true
	dedicated = false
	if show_message:
		connection_status_changed.emit("已断开连接")

func _on_connected_to_server() -> void:
	connection_status_changed.emit("已加入房间")
	joined_server.emit()

func _on_connection_failed() -> void:
	connection_failed.emit("连接失败：请确认主机 IP、端口和局域网防火墙设置。")

func _on_server_disconnected() -> void:
	is_host = false
	connection_status_changed.emit("与房主的连接已断开")

func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)
