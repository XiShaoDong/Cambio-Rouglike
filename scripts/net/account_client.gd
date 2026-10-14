class_name AccountClient
extends Node
## 账号服务（P3a·方案A：HTTP/JSON）客户端。异步回调 cb(ok: bool, data: Dictionary)。

var base_url := ""

func setup(url: String) -> void:
	base_url = url.strip_edges().trim_suffix("/")

func is_configured() -> bool:
	return not base_url.is_empty()

func register(name: String, cb: Callable) -> void:
	_post("/register_device", {"name": name}, cb)

func login(account_id: String, secret: String, cb: Callable) -> void:
	_post("/login", {"account_id": account_id, "secret": secret}, cb)

func change_name(account_id: String, secret: String, name: String, cb := Callable()) -> void:
	_post("/set_name", {"account_id": account_id, "secret": secret, "name": name}, cb)

func get_profile(account_id: String, cb: Callable) -> void:
	_post("/get_profile", {"account_id": account_id}, cb)

## P3b：用 Steam 票据绑定账号（服务端校验）。cb(ok, {steam_id} | {error})。
func steam_auth(account_id: String, secret: String, ticket: String, cb: Callable) -> void:
	_post("/steam_auth", {"account_id": account_id, "secret": secret, "ticket": ticket}, cb)

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
			cb.call(false, {"error": "NO_ACCOUNT_SERVICE"})
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
