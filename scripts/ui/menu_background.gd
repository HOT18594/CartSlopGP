extends Control

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
## Vector menu backdrop: bright sky over the SlopMart parking lot, drawn with
## CanvasItem primitives so it stays crisp at any window size.

const DISPLAY_FONT := "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"

@export var show_store: bool = true
@export var show_carts: bool = true

var _display: FontFile


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display = load(DISPLAY_FONT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var area: Vector2 = size
	if area.x < 4.0 or area.y < 4.0:
		return
	var horizon: float = area.y * 0.60
	_draw_sky(area, horizon)
	_draw_clouds(area)
	_draw_skyline(area, horizon)
	_draw_lot(area, horizon)
	if show_store:
		_draw_store(area, horizon)
	_draw_trees(area, horizon)
	_draw_lamps(area, horizon)
	if show_carts:
		_draw_carts(area)
	_draw_speed_marks(area)


func _draw_sky(area: Vector2, horizon: float) -> void:
	var bands: int = 48
	for band in bands:
		var t: float = float(band) / float(bands - 1)
		var color: Color = UiPalette.SKY_TOP.lerp(UiPalette.SKY_BOTTOM, t)
		draw_rect(Rect2(0.0, horizon * float(band) / float(bands), area.x, horizon / float(bands) + 1.0), color)


func _draw_clouds(area: Vector2) -> void:
	var clouds: Array[Vector3] = [
		Vector3(0.10, 0.12, 1.0),
		Vector3(0.34, 0.07, 0.7),
		Vector3(0.62, 0.16, 0.85),
		Vector3(0.86, 0.08, 1.1),
		Vector3(0.94, 0.30, 0.6),
	]
	for cloud: Vector3 in clouds:
		_cloud(Vector2(area.x * cloud.x, area.y * cloud.y), area.y * 0.05 * cloud.z)


func _cloud(center: Vector2, radius: float) -> void:
	var white := Color(1, 1, 1, 0.95)
	draw_circle(center + Vector2(-radius * 1.1, radius * 0.15), radius * 0.75, white)
	draw_circle(center + Vector2(radius * 1.05, radius * 0.2), radius * 0.68, white)
	draw_circle(center, radius, white)
	draw_circle(center + Vector2(-radius * 0.55, -radius * 0.35), radius * 0.62, white)
	draw_circle(center + Vector2(radius * 0.5, -radius * 0.4), radius * 0.58, white)


func _draw_skyline(area: Vector2, horizon: float) -> void:
	var color := Color(0.42, 0.66, 0.85, 0.45)
	var buildings: Array[Vector3] = [
		Vector3(0.02, 0.075, 0.10), Vector3(0.10, 0.11, 0.05),
		Vector3(0.16, 0.08, 0.13), Vector3(0.26, 0.13, 0.07),
	]
	for building: Vector3 in buildings:
		var x: float = area.x * building.x
		var w: float = area.x * building.z
		var h: float = area.y * building.y
		draw_rect(Rect2(x, horizon - h, w, h), color)


func _draw_lot(area: Vector2, horizon: float) -> void:
	draw_rect(Rect2(0.0, horizon, area.x, area.y - horizon), UiPalette.LOT)

	# Parking bay lines radiate from a vanishing point for a bit of depth.
	var vanish := Vector2(area.x * 0.52, horizon)
	var line_color := Color(1, 1, 1, 0.55)
	for index in range(-7, 6):
		var offset: float = float(index) * area.x * 0.045
		draw_line(vanish + Vector2(offset * 0.12, 0.0), vanish + Vector2(offset * 2.6, area.y - horizon),
			line_color, 5.0, true)
	draw_line(Vector2(area.x * 0.06, area.y * 0.88), Vector2(area.x * 0.15, area.y * 0.83),
		Color(1, 0.83, 0.18, 0.9), 7.0, true)
	draw_line(Vector2(area.x * 0.10, area.y * 0.90), Vector2(area.x * 0.19, area.y * 0.855),
		Color(1, 0.83, 0.18, 0.9), 7.0, true)

	draw_rect(Rect2(0.0, horizon - area.y * 0.012, area.x, area.y * 0.012), Color(0.78, 0.73, 0.8))


func _draw_store(area: Vector2, horizon: float) -> void:
	var left: float = area.x * 0.68
	var right: float = area.x * 0.94
	var top: float = horizon - area.y * 0.30
	var bottom: float = horizon + area.y * 0.06
	draw_rect(Rect2(left, top, right - left, bottom - top), Color(0.96, 0.79, 0.76))
	draw_rect(Rect2(left - 8.0, top, right - left + 16.0, area.y * 0.035), Color(0.85, 0.5, 0.46))
	draw_rect(Rect2(left, bottom - 6.0, right - left, 6.0), Color(0.72, 0.62, 0.68))

	var sign_box := Rect2(left + (right - left) * 0.12, top + area.y * 0.035, (right - left) * 0.76, area.y * 0.065)
	var sign_style := StyleBoxFlat.new()
	sign_style.bg_color = Color(0.91, 0.27, 0.24)
	sign_style.corner_radius_top_left = 8
	sign_style.corner_radius_top_right = 8
	sign_style.corner_radius_bottom_left = 8
	sign_style.corner_radius_bottom_right = 8
	sign_style.border_width_left = 4
	sign_style.border_width_top = 4
	sign_style.border_width_right = 4
	sign_style.border_width_bottom = 4
	sign_style.border_color = Color(0.66, 0.16, 0.15)
	draw_style_box(sign_style, sign_box)
	if _display != null:
		draw_string(_display, Vector2(sign_box.position.x, sign_box.position.y + sign_box.size.y * 0.82),
			"SlopMart", HORIZONTAL_ALIGNMENT_CENTER, sign_box.size.x, int(sign_box.size.y * 0.58),
			Color(1, 1, 1))

	var window_color := Color(0.72, 0.88, 0.96)
	var frame_color := Color(0.9, 0.55, 0.5)
	for index in 3:
		var wx: float = left + area.x * 0.015 + float(index) * (right - left) * 0.22
		var wy: float = top + area.y * 0.14
		draw_rect(Rect2(wx, wy, (right - left) * 0.16, area.y * 0.09), window_color)
		draw_rect(Rect2(wx, wy, (right - left) * 0.16, area.y * 0.09), frame_color, false, 3.0)
	var door := Rect2(left + (right - left) * 0.38, bottom - area.y * 0.115, (right - left) * 0.24, area.y * 0.115)
	draw_rect(door, Color(0.62, 0.82, 0.92))
	draw_rect(door, frame_color, false, 4.0)
	draw_line(Vector2(door.position.x + door.size.x * 0.5, door.position.y),
		Vector2(door.position.x + door.size.x * 0.5, door.end.y), frame_color, 3.0)


func _draw_trees(area: Vector2, horizon: float) -> void:
	var spots: Array[Vector3] = [
		Vector3(0.015, 0.0, 1.0), Vector3(0.07, 0.01, 0.8), Vector3(0.98, 0.02, 1.1),
		Vector3(0.93, 0.0, 0.9), Vector3(0.24, 0.0, 0.55),
	]
	for spot: Vector3 in spots:
		_tree(Vector2(area.x * spot.x, horizon + area.y * 0.02), area.y * 0.06 * spot.z)
	_bush(Vector2(area.x * 0.06, area.y * 1.02), area.y * 0.14)
	_bush(Vector2(area.x * 0.93, area.y * 1.04), area.y * 0.16)


func _tree(base: Vector2, radius: float) -> void:
	draw_rect(Rect2(base.x - radius * 0.12, base.y - radius * 0.7, radius * 0.24, radius * 0.7),
		Color(0.45, 0.32, 0.25))
	draw_circle(base + Vector2(0.0, -radius * 1.05), radius, UiPalette.TREE)
	draw_circle(base + Vector2(-radius * 0.7, -radius * 0.75), radius * 0.7, UiPalette.TREE)
	draw_circle(base + Vector2(radius * 0.7, -radius * 0.75), radius * 0.7, UiPalette.TREE)


func _bush(center: Vector2, radius: float) -> void:
	var color := Color(0.31, 0.66, 0.31)
	draw_circle(center + Vector2(-radius * 0.9, 0.0), radius * 0.7, color)
	draw_circle(center + Vector2(radius * 0.9, 0.0), radius * 0.75, color)
	draw_circle(center, radius, color)


func _draw_lamps(area: Vector2, horizon: float) -> void:
	_lamp(Vector2(area.x * 0.045, horizon + area.y * 0.03), area.y * 0.30)
	_lamp(Vector2(area.x * 0.955, horizon + area.y * 0.09), area.y * 0.34)


func _lamp(base: Vector2, height: float) -> void:
	var pole_color := Color(0.55, 0.57, 0.68)
	var lamp_color := Color(0.75, 0.78, 0.9)
	draw_line(base, base + Vector2(0.0, -height), pole_color, maxf(height * 0.035, 4.0))
	var head := base + Vector2(0.0, -height)
	draw_line(head + Vector2(-height * 0.16, 0.0), head + Vector2(height * 0.16, 0.0), pole_color, maxf(height * 0.03, 3.0))
	for side: float in [-1.0, 1.0]:
		var lamp := Rect2(head + Vector2(side * height * 0.16 - height * 0.07, -height * 0.02),
			Vector2(height * 0.14, height * 0.05))
		draw_rect(lamp, lamp_color)
		draw_rect(lamp, pole_color, false, 2.0)


func _draw_carts(area: Vector2) -> void:
	_cart(Vector2(area.x * 0.145, area.y * 0.95), area.y * 0.0026, false)
	_cart(Vector2(area.x * 0.30, area.y * 0.76), area.y * 0.0015, false)
	_cart(Vector2(area.x * 0.855, area.y * 0.87), area.y * 0.0020, true)


func _cart(origin: Vector2, scale: float, flip: bool) -> void:
	var flip_x: float = -1.0 if flip else 1.0
	var dark := Color(0.12, 0.11, 0.23)
	var metal := Color(0.85, 0.87, 0.93)
	var red := Color(0.87, 0.22, 0.25)

	var top_left := Vector2(-52.0, -62.0)
	var top_right := Vector2(52.0, -62.0)
	var bottom_right := Vector2(38.0, -10.0)
	var bottom_left := Vector2(-38.0, -10.0)
	# Ground shadow.
	draw_set_transform(origin + Vector2(0.0, 22.0 * scale), 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, 58.0 * scale, Color(0.2, 0.15, 0.3, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var basket := PackedVector2Array([
		origin + Vector2(top_left.x * flip_x, top_left.y) * scale,
		origin + Vector2(top_right.x * flip_x, top_right.y) * scale,
		origin + Vector2(bottom_right.x * flip_x, bottom_right.y) * scale,
		origin + Vector2(bottom_left.x * flip_x, bottom_left.y) * scale,
	])
	draw_colored_polygon(basket, metal)
	draw_polyline(PackedVector2Array([basket[0], basket[1], basket[2], basket[3], basket[0]]), dark,
		maxf(3.0 * scale, 2.0), true)

	for step in range(1, 4):
		var t: float = float(step) / 4.0
		var top: Vector2 = basket[0].lerp(basket[1], t)
		var bottom: Vector2 = basket[3].lerp(basket[2], t)
		draw_line(top, bottom, dark, maxf(1.8 * scale, 1.0), true)
	for step in range(1, 3):
		var t2: float = float(step) / 3.0
		var left: Vector2 = basket[0].lerp(basket[3], t2)
		var right: Vector2 = basket[1].lerp(basket[2], t2)
		draw_line(left, right, dark, maxf(1.8 * scale, 1.0), true)

	var handle_top: Vector2 = origin + Vector2(-50.0 * flip_x, -74.0) * scale
	var handle_bottom: Vector2 = origin + Vector2(-50.0 * flip_x, -60.0) * scale
	draw_line(handle_bottom, handle_top, red, maxf(9.0 * scale, 3.0), true)
	draw_line(handle_bottom, origin + Vector2(-52.0 * flip_x, -62.0) * scale, dark, maxf(3.0 * scale, 1.5), true)

	var wheel_y: float = 26.0
	for x: float in [-34.0, 34.0]:
		var leg_top: Vector2 = origin + Vector2(x * flip_x, -10.0) * scale
		var leg_bottom: Vector2 = origin + Vector2(x * flip_x, wheel_y - 6.0) * scale
		draw_line(leg_top, leg_bottom, metal, maxf(6.0 * scale, 2.0), true)
		draw_line(leg_top, leg_bottom, dark, maxf(2.0 * scale, 1.0), true)
		draw_circle(origin + Vector2(x * flip_x, wheel_y) * scale, maxf(8.0 * scale, 3.0), dark)
		draw_circle(origin + Vector2(x * flip_x, wheel_y) * scale, maxf(3.5 * scale, 1.5), Color(0.7, 0.72, 0.8))


func _draw_speed_marks(area: Vector2) -> void:
	var marks: Array[Vector4] = [
		Vector4(0.26, 0.10, 0.055, -0.25),
		Vector4(0.285, 0.155, 0.04, -0.25),
		Vector4(0.735, 0.14, 0.05, 0.25),
		Vector4(0.755, 0.195, 0.035, 0.25),
	]
	for mark: Vector4 in marks:
		var center := Vector2(area.x * mark.x, area.y * mark.y)
		var half: float = area.x * mark.z * 0.5
		draw_set_transform(center, mark.w, Vector2.ONE)
		draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), UiPalette.YELLOW, area.y * 0.022, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
