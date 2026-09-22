class_name Table3dPicker
extends RefCounted
## 屏幕中心射线拾取（Milestone 2，纯工具）。
## 用相机屏幕中心发射线，命中带 "pick" metadata 的 Area3D → 返回该 metadata。

const RAY_LENGTH := 100.0

## 屏幕中心射线命中：返回 {"pick": meta, "collider": Area3D}；未命中返回 {}。
static func pick_hit(cam: Camera3D, world: World3D, screen_center: Vector2) -> Dictionary:
	if cam == null or world == null:
		return {}
	var from := cam.project_ray_origin(screen_center)
	var to := from + cam.project_ray_normal(screen_center) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = Table3dLayout.PICK_MASK
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Object = hit.get("collider")
	if collider == null or not collider.has_meta("pick"):
		return {}
	return {"pick": collider.get_meta("pick"), "collider": collider}

## 只取拾取元数据（点击分发用）。
static func pick(cam: Camera3D, world: World3D, screen_center: Vector2) -> Dictionary:
	var hit := pick_hit(cam, world, screen_center)
	return hit.get("pick", {})
