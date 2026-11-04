class_name DirectoryClient
extends Node
## 中心房间目录服务（P2·方案A：HTTP/JSON）客户端。
## 异步回调，自动管理 HTTPRequest 生命周期；回调签名 cb(ok: bool, data: Dictionary)。
## data 为解析后的响应体（成功为业务字段；失败含 "error" 字符串）。

var base_url := ""

func setup(url: String) -> void:
	base_url = url.strip_edges().trim_suffix("/")

func is_configured() -> bool:
	return not base_url.is_empty()

## host：可选，显式上报对外地址（专用服务器传公网 IP）；留空则服务端用请求源 IP。
## code：可选，固定房间码（专用服务器用，如 "KONG"）；留空则服务端随机生成。
## state：池模式传 "idle"（可被分配、不可加入）；留空 = 普通房间（in_use）。
func create_room(port: int, mode: String, max_players: int, cb: Callable, host := "", code := "", state := "") -> void:
	var body := {"port": port, "mode": mode, "max_players": max_players}
	if not str(host).is_empty():
		body["host"] = str(host)
	if not str(code).is_empty():
		body["code"] = str(code)
	if not str(state).is_empty():
		body["state"] = str(state)
	_post("/create_room", body, cb)

## 池模式：申请一个空闲房间（目录选实例并返回码/地址）。池满 → ok=false, error="NO_ROOM"。
func allocate_room(cb: Callable) -> void:
	_post("/allocate_room", {}, cb)

func join_room(code: String, cb: Callable) -> void:
	_post("/join_room", {"code": code.strip_edges().to_upper()}, cb)

func heartbeat(code: String, cb := Callable()) -> void:
	_post("/heartbeat", {"code": code}, cb)

func close_room(code: String, cb := Callable()) -> void:
	_post("/close_room", {"code": code}, cb)

## 纯函数：解析响应 → {ok, ...}。可 headless 单测。
static func parse_response(response_code: int, body_text: String) -> Dictionary:
	if response_code < 200 or response_code >= 300:
		return {"ok": false, "error": "HTTP_%d" % response_code}
	var json := JSON.new()
	if json.parse(body_text) != OK or not (json.data is Dictionary):
		return {"ok": false, "error": "BAD_RESPONSE"}
	var data: Dictionary = json.data
	if data.has("error") and data["error"] != null:
		return {"ok": false, "error": str(data["error"])}
	return {"ok": true, "data": data}

func _post(path: String, body: Dictionary, cb: Callable) -> void:
	if not is_configured():
		if cb.is_valid():
			cb.call(false, {"error": "NO_DIRECTORY"})
		return
	var req := HTTPRequest.new()
	req.timeout = 6.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, data: PackedByteArray):
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			if cb.is_valid():
				cb.call(false, {"error": "REQUEST_FAILED"})
			return
		var parsed := parse_response(code, data.get_string_from_utf8())
		if cb.is_valid():
			cb.call(bool(parsed.get("ok", false)), parsed.get("data", parsed)))
	var err := req.request(base_url + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		req.queue_free()
		if cb.is_valid():
			cb.call(false, {"error": "REQUEST_FAILED"})
