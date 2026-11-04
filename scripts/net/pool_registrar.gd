class_name PoolRegistrar
extends RefCounted
## 专用服务器在房间池中的登记/轮换。
## 目录调用以 Callable 注入（create_cb/close_cb），不依赖 SceneTree，便于 headless 单测。
## create_cb(port:int, mode:String, max_players:int, state:String, cb:Callable)
## close_cb(code:String, cb:Callable)

const STATE_IDLE := "idle"
const STATE_IN_USE := "in_use"

var code := ""
var state := STATE_IDLE
var last_error := ""

var _create: Callable
var _close: Callable

func setup(create_cb: Callable, close_cb: Callable) -> void:
	_create = create_cb
	_close = close_cb

## 以 idle 登记，拿到可分配的房间码。
func register_idle(port: int, mode: String, max_players: int, cb := Callable()) -> void:
	_register(port, mode, max_players, STATE_IDLE, cb)

## 心跳发现码失效时重新登记（按当前是否有玩家决定 idle / in_use）。
func re_register(port: int, mode: String, max_players: int, in_use: bool, cb := Callable()) -> void:
	_register(port, mode, max_players, STATE_IN_USE if in_use else STATE_IDLE, cb)

## 房间结束：关闭旧码 → 重新登记 idle（换新码）。
func rotate_after_room(port: int, mode: String, max_players: int, cb := Callable()) -> void:
	if not code.is_empty() and _close.is_valid():
		_close.call(code, Callable())
	code = ""
	register_idle(port, mode, max_players, cb)

func _register(port: int, mode: String, max_players: int, new_state: String, cb: Callable) -> void:
	state = new_state
	code = ""
	if not _create.is_valid():
		last_error = "NO_CLIENT"
		if cb.is_valid():
			cb.call(false, {"error": last_error})
		return
	_create.call(port, mode, max_players, new_state, func(ok: bool, data: Dictionary):
		if ok and data.has("code"):
			code = str(data["code"])
			last_error = ""
		else:
			last_error = str(data.get("error", "?"))
		if cb.is_valid():
			cb.call(ok, data))
