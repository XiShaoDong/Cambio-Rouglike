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

func create_room(port: int, mode: String, max_players: int, cb: Callable) -> void:
	_post("/create_room", {"port": port, "mode": mode, "max_players": max_players}, cb)

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
