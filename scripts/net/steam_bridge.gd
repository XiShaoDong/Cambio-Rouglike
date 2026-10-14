class_name SteamBridge
extends Node
## Steam 桥（P3b/P3c，**桩先行**）。检测是否装了 GodotSteam 单例（"Steam"）；
## 未装则全部走桩——**不硬依赖 GodotSteam**，游戏照常编译/运行。
## 真机联调：装 GodotSteam 后，把下方"真实现"接上其 API 即可，上层逻辑不变。

func available() -> bool:
	return Engine.has_singleton("Steam")

## 取 Steam 认证票据（cb(ticket: String)，桩返回空串）。
func get_auth_ticket(cb: Callable) -> void:
	if cb.is_null() or not cb.is_valid():
		return
	if not available():
		cb.call("")
		return
	var steam := Engine.get_singleton("Steam")
	if steam != null and steam.has_method("getAuthSessionTicket"):
		# 真实现（GodotSteam 为异步信号，此处为占位取用，联调时按插件 API 调整）
		var res = steam.getAuthSessionTicket()
		cb.call(str((res as Dictionary).get("ticket", "")) if res is Dictionary else "")
	else:
		cb.call("")

## 取 Steam 好友（cb(friends: Array)，桩返回空数组）。
func get_friends(cb: Callable) -> void:
	if cb.is_null() or not cb.is_valid():
		return
	if not available():
		cb.call([])
		return
	var steam := Engine.get_singleton("Steam")
	if steam != null and steam.has_method("getFriendsList"):
		cb.call(steam.getFriendsList())
	else:
		cb.call([])

## 邀请好友进房（桩返回 false=未启用）。真实现：Steam 邀请/Overlay 带 room_code。
func invite_friend(steam_id: String, room_code: String) -> bool:
	if not available():
		return false
	var steam := Engine.get_singleton("Steam")
	if steam != null and steam.has_method("activateGameOverlayInviteDialog"):
		steam.activateGameOverlayInviteDialog(steam_id)
		return true
	return false

## 需在有 Steam 时每帧驱动其回调（GodotSteam.run_callbacks）。
func poll() -> void:
	if available():
		var steam := Engine.get_singleton("Steam")
		if steam != null and steam.has_method("run_callbacks"):
			steam.run_callbacks()
