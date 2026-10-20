class_name BombIcon
extends Control
## 程序化炸弹小图标（无需素材）：黑色圆身 + 引线 + 火花。纯展示。
##
## [随机增强接入点 · 后续对接] 炸弹效果实现时：给卡牌右上角加炸弹角标（`CardBlock`）
## 时复用本图标的绘制逻辑；3D 卡面可用 `Sprite3D` 贴本程序化纹理。目前仅用于效果面板预览。

const BODY := Color(0.05, 0.05, 0.06)
const FUSE := Color(0.45, 0.33, 0.12)
const SPARK := Color(1.0, 0.62, 0.12)

static var _tex: ImageTexture = null

## 生成程序化炸弹纹理（3D 卡牌右上角徽标用；与 2D 绘制同风格）。
static func texture(size := 64) -> ImageTexture:
	if _tex != null:
		return _tex
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(size * 0.5, size * 0.60)
	var r := size * 0.26
	_fill_circle(img, c, r + maxf(2.0, size * 0.04), Color(1, 1, 1, 0.92))
	_fill_circle(img, c, r, BODY)
	var a := c + Vector2(r * 0.55, -r * 0.55)
	var b := c + Vector2(r * 1.25, -r * 1.55)
	_draw_line(img, a, b, FUSE, maxi(2, int(size * 0.07)))
	_fill_circle(img, b, maxf(2.0, size * 0.075), SPARK)
	_tex = ImageTexture.create_from_image(img)
	return _tex

static func _fill_circle(img: Image, center: Vector2, radius: float, color: Color) -> void:
	var x0 := maxi(0, int(center.x - radius))
	var x1 := mini(img.get_width() - 1, int(center.x + radius))
	var y0 := maxi(0, int(center.y - radius))
	var y1 := mini(img.get_height() - 1, int(center.y + radius))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				img.set_pixel(x, y, color)

static func _draw_line(img: Image, a: Vector2, b: Vector2, color: Color, thickness: float) -> void:
	var steps := maxi(1, int(a.distance_to(b) * 2.0))
	for i in steps + 1:
		_fill_circle(img, a.lerp(b, float(i) / float(steps)), thickness * 0.5, color)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(18, 18)

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.30
	draw_circle(c + Vector2(0.0, r * 0.25), r + maxf(1.0, r * 0.16), Color(1, 1, 1, 0.92))
	draw_circle(c + Vector2(0.0, r * 0.25), r, BODY)
	draw_line(c + Vector2(r * 0.55, -r * 0.55), c + Vector2(r * 1.25, -r * 1.55), FUSE, 2.0)
	draw_circle(c + Vector2(r * 1.25, -r * 1.55), 2.0, SPARK)
