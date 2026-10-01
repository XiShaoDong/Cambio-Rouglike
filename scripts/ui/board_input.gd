class_name BoardInput
extends RefCounted
## 全息看板坐标换算（纯函数，可 headless 测）。
## 约定：看板 local 为 quad 平面 XY 坐标（原点在中心，+X 右、+Y 上）；
## uv 左上为 (0,0)、右下为 (1,1)；viewport 为 SubViewport 像素坐标。

## local（XY 平面）→ uv（左上 0,0）。
static func local_to_uv(local: Vector3, size: Vector2) -> Vector2:
	return Vector2(
		(local.x + size.x * 0.5) / size.x,
		(size.y * 0.5 - local.y) / size.y)

## uv → SubViewport 像素坐标。
static func uv_to_viewport(uv: Vector2, viewport_size: Vector2i) -> Vector2i:
	return Vector2i(int(round(uv.x * float(viewport_size.x))), int(round(uv.y * float(viewport_size.y))))

## 世界坐标 → 看板 local（用看板全局变换的逆）。
static func world_to_local(board_xform: Transform3D, world_pos: Vector3) -> Vector3:
	return board_xform.affine_inverse() * world_pos
