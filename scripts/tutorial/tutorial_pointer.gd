class_name TutorialPointer
extends Control
## 屏幕空间红色箭头：指向当前步骤的目标（不移动相机）。
## 目标在屏幕内时悬在目标上方朝下；目标在屏幕外时贴边指向目标方向。

const COLOR := Color("ff4242")
const OUTLINE := Color(0.0, 0.0, 0.0, 0.88)
const MARGIN := 34.0
const SIZE := 19.0

var _target := Vector2.ZERO
var _has_target := false
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 205


func set_target(screen_pos: Vector2) -> void:
	_target = screen_pos
	_has_target = true
	queue_redraw()


func hide_target() -> void:
	_has_target = false
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _has_target:
		queue_redraw()


func _draw() -> void:
	if not _has_target:
		return
	var vp := get_viewport_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	var inside := _target.x >= 0.0 and _target.y >= 0.0 \
		and _target.x <= vp.x and _target.y <= vp.y
	var center: Vector2
	var dir: Vector2
	if inside:
		center = Vector2(
			clampf(_target.x, MARGIN, vp.x - MARGIN),
			clampf(_target.y - 78.0 + sin(_t * 4.0) * 5.0, MARGIN, vp.y - MARGIN))
		dir = Vector2.DOWN
	else:
		var c := Vector2(
			clampf(_target.x, MARGIN, vp.x - MARGIN),
			clampf(_target.y, MARGIN, vp.y - MARGIN))
		dir = (_target - c)
		dir = dir.normalized() if dir.length_squared() > 0.001 else Vector2.DOWN
		center = c + dir * (SIZE + 6.0)
	var tip := center + dir * SIZE
	var base := center - dir * SIZE
	var perp := Vector2(-dir.y, dir.x) * SIZE * 0.72
	var pts := PackedVector2Array([tip, base + perp, base - perp])
	draw_colored_polygon(pts, COLOR)
	draw_polyline(PackedVector2Array([tip, base + perp, base - perp, tip]), OUTLINE, 3.0, true)
