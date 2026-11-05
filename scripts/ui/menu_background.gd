extends Control

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
## Vector menu backdrop: dusk sky, sun, rolling hills, a road running to the
## horizon and a checkered strip. Everything is drawn, so it scales cleanly and
## costs no textures.

@export var horizon_ratio: float = 0.56 ## Where the sky meets the ground (0-1).
@export var show_road: bool = true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var area: Vector2 = size
	if area.x < 4.0 or area.y < 4.0:
		return
	var horizon: float = area.y * horizon_ratio
	_draw_sky(area, horizon)
	_draw_sun(area, horizon)
	_draw_hills(area, horizon)
	if show_road:
		_draw_road(area, horizon)
	_draw_checker(area)


func _draw_sky(area: Vector2, horizon: float) -> void:
	var bands: int = 64
	var top: Color = UiPalette.BG_TOP
	var bottom: Color = Color("4a2450")
	for band in bands:
		var t: float = float(band) / float(bands - 1)
		var color: Color = top.lerp(bottom, t)
		draw_rect(Rect2(0.0, horizon * float(band) / float(bands), area.x, horizon / float(bands) + 1.0), color)


func _draw_sun(area: Vector2, horizon: float) -> void:
	var center := Vector2(area.x * 0.72, horizon * 0.66)
	var radius: float = area.y * 0.17
	draw_circle(center, radius * 1.55, Color(UiPalette.CORAL, 0.10))
	draw_circle(center, radius * 1.2, Color(UiPalette.CORAL, 0.16))
	draw_circle(center, radius, Color(UiPalette.ACCENT, 0.85))
	# Retro sun stripes.
	var stripe_color := Color(UiPalette.BG_BOTTOM, 0.22)
	for i in 4:
		var y: float = center.y + radius * (0.22 + 0.18 * i)
		var half: float = sqrt(maxf(radius * radius - pow(y - center.y, 2.0), 0.0))
		draw_rect(Rect2(center.x - half, y, half * 2.0, radius * 0.045), stripe_color)


func _draw_hills(area: Vector2, horizon: float) -> void:
	_hill_layer(area, horizon + 4.0, area.y * 0.10, 0.9, Color("2a1740"), 0.0032)
	_hill_layer(area, horizon + 22.0, area.y * 0.07, 1.7, Color("221232"), 0.0051)


func _hill_layer(area: Vector2, base_y: float, amplitude: float, phase: float, color: Color, freq: float) -> void:
	var points := PackedVector2Array()
	var steps: int = 64
	for step in steps + 1:
		var t: float = float(step) / float(steps)
		var x: float = t * area.x
		var y: float = base_y - sin(t * PI * 2.0 * freq * 40.0 + phase) * amplitude * 0.25 \
			- sin(t * PI * 1.3 + phase) * amplitude
		points.append(Vector2(x, y))
	points.append(Vector2(area.x, area.y))
	points.append(Vector2(0.0, area.y))
	draw_colored_polygon(points, color)


func _draw_road(area: Vector2, horizon: float) -> void:
	var vanishing := Vector2(area.x * 0.58, horizon + 10.0)
	var bottom_left := Vector2(area.x * 0.18, area.y)
	var bottom_right := Vector2(area.x * 1.15, area.y)
	var edge_left := vanishing + Vector2(-14.0, 0.0)
	var edge_right := vanishing + Vector2(14.0, 0.0)
	draw_colored_polygon(PackedVector2Array([edge_left, edge_right, bottom_right, bottom_left]), Color("141022"))
	draw_line(bottom_left, edge_left, Color(UiPalette.TEXT, 0.10), 3.0, true)
	draw_line(bottom_right, edge_right, Color(UiPalette.TEXT, 0.10), 3.0, true)

	# Dashes that grow as they come toward the camera.
	var dashes: int = 9
	for i in dashes:
		var t0: float = float(i) / float(dashes)
		var t1: float = t0 + 0.045
		if t0 > 1.0:
			break
		var a: Vector2 = vanishing.lerp((bottom_left + bottom_right) * 0.5, t0 * t0)
		var b: Vector2 = vanishing.lerp((bottom_left + bottom_right) * 0.5, t1 * t1)
		var width: float = lerpf(1.5, 14.0, t0 * t0)
		draw_line(a, b, Color(UiPalette.ACCENT, 0.55), width, true)


func _draw_checker(area: Vector2) -> void:
	var band_height: float = maxf(area.y * 0.035, 14.0)
	var square: float = band_height
	var y: float = area.y - band_height
	var index: int = 0
	var x: float = 0.0
	while x < area.x:
		draw_rect(Rect2(x, y, square, band_height), UiPalette.TEXT if index % 2 == 0 else UiPalette.OUTLINE)
		x += square
		index += 1
