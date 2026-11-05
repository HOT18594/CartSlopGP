extends Control
## Drawing half of the loading overlay: themed backdrop, a road with a cart
## that drives from left to right as the scene loads.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")

var progress: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var area: Vector2 = size
	if area.x < 4.0 or area.y < 4.0:
		return
	_draw_sky(area)
	_draw_clouds(area)
	_draw_road(area)
	_draw_checker(area)


func _draw_sky(area: Vector2) -> void:
	var bands: int = 40
	for band in bands:
		var t: float = float(band) / float(bands - 1)
		var color: Color = UiPalette.SKY_TOP.lerp(UiPalette.SKY_BOTTOM, t)
		draw_rect(Rect2(0.0, area.y * float(band) / float(bands), area.x, area.y / float(bands) + 1.0), color)


func _draw_clouds(area: Vector2) -> void:
	for spot: Vector3 in [Vector3(0.12, 0.16, 1.0), Vector3(0.84, 0.12, 0.8), Vector3(0.68, 0.26, 0.55)]:
		var center := Vector2(area.x * spot.x, area.y * spot.y)
		var radius: float = area.y * 0.045 * spot.z
		var white := Color(1, 1, 1, 0.9)
		draw_circle(center, radius, white)
		draw_circle(center + Vector2(-radius * 1.1, radius * 0.2), radius * 0.75, white)
		draw_circle(center + Vector2(radius * 1.05, radius * 0.25), radius * 0.65, white)


func _draw_road(area: Vector2) -> void:
	var width: float = area.x * 0.62
	var height: float = area.y * 0.12
	var origin := Vector2((area.x - width) * 0.5, area.y * 0.49)
	var track := Rect2(origin.x, origin.y + height * 1.15, width, height)

	var style := StyleBoxFlat.new()
	style.bg_color = Color("102a4a")
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.border_width_left = 6
	style.border_width_top = 6
	style.border_width_right = 6
	style.border_width_bottom = 6
	style.border_color = UiPalette.OUTLINE
	style.shadow_color = Color(0.07, 0.06, 0.15, 0.4)
	style.shadow_size = 0
	style.shadow_offset = Vector2(0, 8)
	draw_style_box(style, track)

	# progress fill: bright band across the lower half of the track
	var fill_width: float = (track.size.x - 16.0) * progress
	var fill := Rect2(track.position.x + 8.0, track.position.y + track.size.y * 0.52,
		fill_width, track.size.y * 0.40)
	draw_rect(fill, Color(UiPalette.CYAN, 0.38))
	if fill_width > 2.0:
		draw_line(Vector2(fill.position.x + fill_width, fill.position.y),
			Vector2(fill.position.x + fill_width, fill.end.y), Color.WHITE, 3.0, true)

	# dashed centre line, scrolling
	var dash_y: float = track.position.y + track.size.y * 0.5
	var offset: float = fmod(_time * 90.0, 64.0)
	var x: float = track.position.x + 24.0 + offset
	while x < track.end.x - 24.0:
		draw_line(Vector2(x, dash_y), Vector2(minf(x + 30.0, track.end.x - 24.0), dash_y),
			Color(UiPalette.YELLOW, 0.65), 4.0, true)
		x += 64.0

	# cart driving along the road
	var cart_x: float = track.position.x + 44.0 + (track.size.x - 88.0) * progress
	var cart_y: float = track.position.y + track.size.y - 10.0
	var bounce: float = sin(_time * 14.0) * 3.0 * (0.4 + progress * 0.6)
	_draw_cart(Vector2(cart_x, cart_y + bounce), 0.9)


func _draw_cart(origin: Vector2, scale: float) -> void:
	var ink := UiPalette.OUTLINE
	var metal := Color(0.9, 0.92, 0.97)
	var red := Color(0.87, 0.22, 0.25)
	var basket := PackedVector2Array([
		origin + Vector2(-46, -70) * scale, origin + Vector2(46, -70) * scale,
		origin + Vector2(34, -28) * scale, origin + Vector2(-34, -28) * scale,
	])
	draw_colored_polygon(basket, metal)
	draw_polyline(PackedVector2Array([basket[0], basket[1], basket[2], basket[3], basket[0]]), ink, 2.5, true)
	for step in range(1, 4):
		var t: float = float(step) / 4.0
		draw_line(basket[0].lerp(basket[1], t), basket[3].lerp(basket[2], t), ink, 1.5, true)
	for step in range(1, 3):
		var t2: float = float(step) / 3.0
		draw_line(basket[0].lerp(basket[3], t2), basket[1].lerp(basket[2], t2), ink, 1.5, true)
	draw_line(origin + Vector2(-44, -68) * scale, origin + Vector2(-44, -84) * scale, red, 6.0, true)
	for wheel: float in [-30.0, 30.0]:
		draw_line(origin + Vector2(wheel, -28) * scale, origin + Vector2(wheel, -8) * scale, ink, 3.0, true)
		draw_circle(origin + Vector2(wheel, 0) * scale, 7.5 * scale, ink)
		draw_circle(origin + Vector2(wheel, 0) * scale, 3.0 * scale, Color(0.7, 0.72, 0.8))


func _draw_checker(area: Vector2) -> void:
	var band: float = maxf(area.y * 0.035, 12.0)
	var square: float = band
	var y: float = area.y - band
	var index: int = 0
	var x: float = 0.0
	while x < area.x:
		draw_rect(Rect2(x, y, square, band),
			UiPalette.CREAM if index % 2 == 0 else UiPalette.OUTLINE)
		x += square
		index += 1
