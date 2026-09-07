class_name ProxyRelay
extends Node

## UDP 中继代理：在客户端与服务器之间转发原始 UDP 报文，并按配置注入网络条件。
## 相比"在引擎里包一层 MultiplayerPeer"，本方案在【数据报】层做手脚：
##   - ENet 自身的 keepalive / ACK / 重传也会被真实地丢包、延迟、截断，
##     所以模拟的是真实公网链路的物理层行为；
##   - "黑障/拔网线"（blackout）会真正导致 ENet 连接超时掉线 → 触发离线/重连路径。
## 生产代码零改动：host 正常监听 7007，本中继监听 listen_port（如 7011），
## 客户端连中继地址即可，中继把数据报转发给真实服务器。
##
## 注意（诚实说明）：丢包/乱序/重复发生在数据报层时，会被 ENet 自身的
## 可靠通道吸收（重传/按序列排序/去重）。所以本中继适合验证：
##   延迟 / 丢包 / 抖动下对局能否收敛、链路中断后能否离线+重连。
## RPC 层的"重复请求幂等"不在本中继覆盖范围（那需要应用层注入，见 verify_protocol 的拒绝校验）。

var listen_port := 7011
var target_host := "127.0.0.1"
var target_port := 7007

var loss_rate := 0.0          # 丢包概率 0..1（双向）
var latency_ms := 0.0         # 固定延迟（毫秒，双向）
var jitter_ms := 0.0          # 额外随机延迟上限（毫秒，双向）
var duplicate_rate := 0.0     # 重复报文概率 0..1
var blackout_at_ms := -1.0    # 自启动起的黑障开始毫秒（-1 = 不启用）
var blackout_duration_ms := 0.0

var _sock_client := PacketPeerUDP.new()  # 面向客户端（监听 listen_port）
var _sock_host := PacketPeerUDP.new()    # 面向服务器（连接 target:target_port）
var _client_addr: Array = []             # [ip, port]
var _rng := RandomNumberGenerator.new()
var _queue: Array = []                   # {at, kind, pkt, ip, port}

func configure(p: Dictionary) -> void:
	loss_rate = float(p.get("loss", 0.0))
	latency_ms = float(p.get("latency", 0.0))
	jitter_ms = float(p.get("jitter", 0.0))
	duplicate_rate = float(p.get("duplicate", 0.0))
	blackout_at_ms = float(p.get("blackout_at", -1.0))
	blackout_duration_ms = float(p.get("blackout_duration", 0.0))
	_rng.seed = int(p.get("seed", 12345))

func _ready() -> void:
	if _sock_client.bind(listen_port) != OK:
		push_error("ProxyRelay: 无法绑定端口 %d" % listen_port)
		return
	_sock_host.connect_to_host(target_host, target_port)
	print("[relay] listening on %d -> %s:%d (loss=%s latency=%sms jitter=%sms dup=%s blackout=%sms@%sms)" % [
		listen_port, target_host, target_port, loss_rate, latency_ms, jitter_ms, duplicate_rate,
		blackout_duration_ms, blackout_at_ms])

func _process(_delta: float) -> void:
	_flush_queue()
	# 客户端 -> 服务器
	while _sock_client.get_available_packet_count() > 0:
		var pkt := _sock_client.get_packet()
		_client_addr = [_sock_client.get_packet_ip(), _sock_client.get_packet_port()]
		_route("to_host", pkt, _client_addr[0], _client_addr[1])
	# 服务器 -> 客户端
	while _sock_host.get_available_packet_count() > 0:
		var pkt := _sock_host.get_packet()
		if _client_addr.is_empty():
			continue
		_route("to_client", pkt, _client_addr[0], _client_addr[1])

func _in_blackout() -> bool:
	if blackout_at_ms < 0.0:
		return false
	var t := Time.get_ticks_msec()
	return t >= blackout_at_ms and t < blackout_at_ms + blackout_duration_ms

func _route(kind: String, pkt: PackedByteArray, ip: String, port: int) -> void:
	if _in_blackout():
		return
	if loss_rate > 0.0 and _rng.randf() < loss_rate:
		return
	var delay := 0.0
	if latency_ms > 0.0:
		delay += latency_ms
	if jitter_ms > 0.0:
		delay += _rng.randf() * jitter_ms
	if duplicate_rate > 0.0 and _rng.randf() < duplicate_rate:
		_queue.append({"at": Time.get_ticks_msec() + delay, "kind": kind, "pkt": pkt.duplicate(), "ip": ip, "port": port})
	_queue.append({"at": Time.get_ticks_msec() + delay, "kind": kind, "pkt": pkt, "ip": ip, "port": port})

func _flush_queue() -> void:
	if _queue.is_empty():
		return
	var t := Time.get_ticks_msec()
	var keep: Array = []
	for item in _queue:
		if item["at"] <= t:
			if item["kind"] == "to_host":
				_sock_host.put_packet(item["pkt"])
			else:
				_sock_client.set_dest_address(item["ip"], item["port"])
				_sock_client.put_packet(item["pkt"])
		else:
			keep.append(item)
	_queue = keep