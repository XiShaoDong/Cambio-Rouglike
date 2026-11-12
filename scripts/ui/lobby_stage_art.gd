class_name LobbyStageArt
extends Control
## Resolution-independent backdrop for the lobby and waiting-room card stage.
## It deliberately uses vector drawing plus the existing high-resolution card backs,
## so the visual stays smooth at every window scale instead of relying on a small
## raster UI decoration.

var card_texture: Texture2D
var card_count := 5
var compact := false
var _cards: Array[TextureRect] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(func():
		_layout_cards()
		queue_redraw())
	queue_redraw()
	call_deferred("_layout_cards")

func setup(texture: Texture2D, count := 5, is_compact := false) -> void:
	card_texture = texture
	card_count = count
	compact = is_compact
	for child in _cards:
		child.queue_free()
	_cards.clear()
	for i in card_count:
		var card := TextureRect.new()
		card.texture = card_texture
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.z_index = 2 + i
		add_child(card)
		_cards.append(card)
	call_deferred("_layout_cards")

func _layout_cards() -> void:
	if _cards.is_empty() or size.x < 4.0 or size.y < 4.0:
		return
	var short_side := minf(size.x, size.y)
	var card_h := short_side * (0.48 if compact else 0.64)
	var card_w := card_h * 0.6875
	var cx := size.x * 0.5
	var cy := size.y * (0.48 if compact else 0.45)
	for i in _cards.size():
		var card := _cards[i]
		var t := float(i) / maxf(float(_cards.size() - 1), 1.0)
		var spread := (t - 0.5) * (size.x * (0.70 if compact else 0.76))
		var distance := absf(t - 0.5) * 2.0
		var scale := 1.0 - distance * 0.26
		card.size = Vector2(card_w, card_h) * scale
		card.pivot_offset = card.size * 0.5
		card.position = Vector2(cx + spread - card.size.x * 0.5, cy + distance * size.y * 0.11 - card.size.y * 0.5)
		card.rotation_degrees = (t - 0.5) * (34.0 if compact else 28.0)
		card.modulate = Color(0.72 + (1.0 - distance) * 0.28, 0.80 + (1.0 - distance) * 0.20, 1.0, 0.66 + (1.0 - distance) * 0.34)

func _draw() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return
	var center := Vector2(size.x * 0.5, size.y * 0.54)
	var radius := minf(size.x * 0.42, size.y * 0.42)
	# Soft concentric glow, rendered as vectors rather than a scaled bitmap.
	for i in 12:
		var p := float(i) / 11.0
		draw_circle(center, radius * (1.0 - p * 0.82), Color(0.10, 0.24, 0.76, 0.010 + p * 0.006), true, -1.0, true)
	for i in 12:
		var a := TAU * float(i) / 12.0 - 0.25
		var inner := center + Vector2(cos(a), sin(a)) * radius * 0.20
		var outer := center + Vector2(cos(a), sin(a)) * radius * 0.92
		draw_line(inner, outer, Color(0.33, 0.49, 1.0, 0.14), 1.2, true)
	for ring in 3:
		var r := radius * (0.48 + ring * 0.18)
		draw_arc(center, r, -0.12, TAU - 0.12, 96, Color(0.32, 0.48, 1.0, 0.28 - ring * 0.05), 1.4, true)
	draw_circle(center, radius * 0.18, Color(0.38, 0.52, 1.0, 0.12), true, -1.0, true)
	draw_circle(center, radius * 0.075, Color(0.66, 0.76, 1.0, 0.55), true, -1.0, true)
	for i in 18:
		var a := float(i * 37 % 360) * PI / 180.0
		var r := radius * (0.58 + float(i % 4) * 0.10)
		var point := center + Vector2(cos(a), sin(a)) * r
		draw_circle(point, 1.2 + float(i % 3) * 0.45, Color(0.63, 0.73, 1.0, 0.50), true, -1.0, true)
