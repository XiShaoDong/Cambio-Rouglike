class_name TurnTimer
extends RefCounted
## 回合倒计时纯模型（纯展示：不联网、不写快照、不触发规则）。
## 数据源与展示解耦：v2 换服务器 deadline_ms 时，只改"谁来喂 remaining"，UI 不动。

var limit: float = 30.0
var remaining: float = 30.0

func reset(sec: float = 30.0) -> void:
	limit = sec
	remaining = sec

func tick(delta: float) -> void:
	remaining -= delta

## 显示用整数秒，向下取整：30.0→30、-0.3→-1。
func seconds_left() -> int:
	return int(floor(remaining))

## 0=正常(>10) 1=临近(1..10) 2=超时(<=0)。
func phase() -> int:
	if remaining <= 0.0:
		return 2
	if remaining <= 10.0:
		return 1
	return 0
