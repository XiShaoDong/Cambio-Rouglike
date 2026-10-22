class_name ItemHandMath
extends RefCounted
## 道具手牌纯数学/纯函数：扇形布局、Q/E 循环、目标顺序。
## 不依赖节点，headless 可测。

static func cycle(index: int, count: int, dir: int) -> int:
	if count <= 0:
		return -1
	return posmod(index + dir, count)

## 扇形布局：返回 [{index, pos, rot_deg, scale, z}]（pos 为卡片左上角）。
static func fan_layout(count: int, card_size: Vector2, center: Vector2,
		spread_deg := 18.0, spacing := 92.0, selected := -1, lift := 30.0) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	for i in count:
		var t := 0.0 if count == 1 else (float(i) / float(count - 1)) * 2.0 - 1.0
		var pos := center + Vector2(t * spacing, -absf(t) * 6.0)
		var rot := t * spread_deg * 0.5
		var scale := 1.0
		var z := i + 1
		if i == selected:
			pos.y -= lift
			scale = 1.08
			z = 100
		pos -= card_size * 0.5
		out.append({"index": i, "pos": pos, "rot_deg": rot, "scale": scale, "z": z})
	return out

## 对手目标顺序：按快照 players 顺序（= turn_order），从 viewer 下一位开始，跳过自己与已淘汰者。
static func target_order(players: Array, viewer: int) -> Array[int]:
	var ids: Array[int] = []
	var start := -1
	for i in players.size():
		if int((players[i] as Dictionary).get("id", -1)) == viewer:
			start = i
			break
	if start < 0:
		return ids
	var n := players.size()
	for offset in range(1, n):
		var p: Dictionary = players[(start + offset) % n]
		var seat := int(p.get("id", -1))
		if seat < 0 or seat == viewer:
			continue
		if bool(p.get("eliminated", false)):
			continue
		ids.append(seat)
	return ids
