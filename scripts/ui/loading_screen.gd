extends Control
## Drawing half of the loading overlay: a little SlopMart scene with a cart
## driving along the progress road, drifting clouds, a sun, hills, exhaust
## puffs and rotating tips.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CartDrawing := preload("res://scripts/ui/cart_drawing.gd")
const DISPLAY_FONT := "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"

const TIPS: PackedStringArray = [
	"TIP: Hold SPACE to drift around corners.",
	"TIP: Boost pads refill your meter instantly.",
	"TIP: You can drive over the speed bumps - floor it.",
	"TIP: Press R to reset the cart if you get stuck.",
	"TIP: Crates and cones are light - ram them.",
]

var progress: float = 0.0
var indeterminate: bool = false

var _time: float = 0.0
var _tip_index: int = 0
var _tip_timer: float = 0.0
var _tip_label: Label
var _display: Font


func _ready() -> void:
	_display = load(DISPLAY_FONT)
	# Swallow clicks while the overlay is up: the menu underneath is about to
	# be replaced, and a blind click must not trigger its buttons.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_tip_label = get_node_or_null("Tip") as Label
	_show_tip()


func set_progress(value: float) -> void:
	progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func set_indeterminate(value: bool) -> void:
	indeterminate = value
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	_tip_timer += delta
	if _tip_timer >= 4.5:
		_tip_timer = 0.0
		_tip_index = (_tip_index + 1) % TIPS.size()
		_show_tip()
	queue_redraw()


func _show_tip() -> void:
	if _tip_label != null:
		_tip_label.text = TIPS[_tip_index]


func _fill_ratio() -> float:
	if indeterminate:
		return 0.5 + 0.32 * sin(_time * 2.2)
	return progress


func _draw() -> void:
	var area: Vector2 = size
	if area.x < 4.0 or area.y < 4.0:
		return
	_draw_sky(area)
	_draw_sun(area)
	_draw_clouds(area)
	_draw_hills(area)
	_draw_backdrop(area)
	_draw_road(area)
	_draw_checker(area)


func _draw_sky(area: Vector2) -> void:
	var bands: int = 40
	for band in bands:
		var t: float = float(band) / float(bands - 1)
		var color: Color = UiPalette.SKY_TOP.lerp(UiPalette.SKY_BOTTOM, t)
		draw_rect(Rect2(0.0, area.y * float(band) / float(bands), area.x, area.y / float(bands) + 1.0), color)


func _draw_sun(area: Vector2) -> void:
	var center := Vector2(area.x * 0.80, area.y * 0.20)
	var radius: float = area.y * 0.085
	draw_circle(center, radius * 1.5, Color(UiPalette.YELLOW, 0.16))
	draw_circle(center, radius, Color(UiPalette.YELLOW, 0.95))
	for i in 3:
		var y: float = center.y + radius * (0.25 + 0.22 * i)
		var half: float = sqrt(maxf(radius * radius - pow(y - center.y, 2.0), 0.0))
		draw_rect(Rect2(center.x - half, y, half * 2.0, radius * 0.06), Color(UiPalette.RED, 0.35))


func _draw_clouds(area: Vector2) -> void:
	var clouds: Array[Vector4] = [
		Vector4(0.10, 0.16, 1.0, 12.0),
		Vector4(0.36, 0.10, 0.7, 18.0),
		Vector4(0.62, 0.22, 0.55, 8.0),
		Vector4(0.90, 0.30, 0.8, 14.0),
	]
	for cloud: Vector4 in clouds:
		var x: float = fposmod(area.x * cloud.x + _time * cloud.w, area.x + 260.0) - 130.0
		var center := Vector2(x, area.y * cloud.y)
		var radius: float = area.y * 0.04 * cloud.z
		var white := Color(1, 1, 1, 0.92)
		draw_circle(center, radius, white)
		draw_circle(center + Vector2(-radius * 1.1, radius * 0.2), radius * 0.75, white)
		draw_circle(center + Vector2(radius * 1.05, radius * 0.25), radius * 0.65, white)


func _draw_hills(area: Vector2) -> void:
	var base_y: float = area.y * 0.58
	for layer in 2:
		var color := Color(0.24, 0.55, 0.34, 0.55) if layer == 0 else Color(0.19, 0.45, 0.29, 0.75)
		var points := PackedVector2Array()
		var steps: int = 32
		var amp: float = area.y * (0.055 - layer * 0.015)
		var phase: float = layer * 1.7
		for step in steps + 1:
			var t: float = float(step) / float(steps)
			var y: float = base_y + layer * 10.0 - sin(t * PI * 2.0 + phase) * amp \
				- sin(t * PI * 5.0 + phase) * amp * 0.25
			points.append(Vector2(t * area.x, y))
		points.append(Vector2(area.x, area.y))
		# Close along the bottom edge. Using Vector2.ZERO here made the last
		# edge cross the wavy top edge, so triangulation failed and Godot
		# logged "Invalid polygon data" on every scene load.
		points.append(Vector2(0.0, area.y))
		draw_colored_polygon(points, color)
	draw_rect(Rect2(0.0, area.y * 0.58, area.x, area.y * 0.42), Color(0.80, 0.75, 0.81, 0.58))


func _draw_backdrop(area: Vector2) -> void:
	# Parking-bay lines and a small SlopMart give the lower half some depth
	# without competing with the progress road.
	var vanish := Vector2(area.x * 0.50, area.y * 0.60)
	for index in range(-4, 5):
		if index == 0:
			continue
		var bottom := vanish + Vector2(float(index) * area.x * 0.18, area.y * 0.42)
		draw_line(vanish, bottom, Color(1, 1, 1, 0.20), 2.0, true)

	var left: float = area.x * 0.79
	var right: float = area.x * 0.975
	var top: float = area.y * 0.455
	var bottom: float = area.y * 0.605
	draw_rect(Rect2(left, top, right - left, bottom - top), Color(0.96, 0.79, 0.76))
	draw_rect(Rect2(left - 5.0, top, right - left + 10.0, area.y * 0.022),
		Color(0.85, 0.50, 0.46))
	draw_rect(Rect2(left, bottom - 4.0, right - left, 4.0), Color(0.72, 0.62, 0.68))
	var sign_box := Rect2(left + (right - left) * 0.10, top + area.y * 0.022,
		(right - left) * 0.80, area.y * 0.040)
	var sign_style := StyleBoxFlat.new()
	sign_style.bg_color = Color(0.91, 0.27, 0.24)
	sign_style.corner_radius_top_left = 6
	sign_style.corner_radius_top_right = 6
	sign_style.corner_radius_bottom_left = 6
	sign_style.corner_radius_bottom_right = 6
	sign_style.border_width_left = 3
	sign_style.border_width_top = 3
	sign_style.border_width_right = 3
	sign_style.border_width_bottom = 3
	sign_style.border_color = Color(0.66, 0.16, 0.15)
	draw_style_box(sign_style, sign_box)
	if _display != null:
		draw_string(_display, Vector2(sign_box.position.x,
			sign_box.position.y + sign_box.size.y * 0.82), "SLOPMART",
			HORIZONTAL_ALIGNMENT_CENTER, sign_box.size.x,
			int(sign_box.size.y * 0.62), Color(1, 1, 1))
	for index in 2:
		var window := Rect2(left + (right - left) * (0.15 + float(index) * 0.46),
			top + area.y * 0.085, (right - left) * 0.24, area.y * 0.050)
		draw_rect(window, Color(0.72, 0.88, 0.96))
		draw_rect(window, Color(0.90, 0.55, 0.50), false, 2.0)

	# A couple of small trees anchor the left horizon.
	_small_tree(Vector2(area.x * 0.06, area.y * 0.605), area.y * 0.030)
	_small_tree(Vector2(area.x * 0.15, area.y * 0.600), area.y * 0.024)


func _small_tree(base: Vector2, radius: float) -> void:
	draw_rect(Rect2(base.x - radius * 0.10, base.y - radius * 0.7,
		radius * 0.20, radius * 0.7), Color(0.45, 0.32, 0.25))
	draw_circle(base + Vector2(0.0, -radius), radius, UiPalette.TREE)
	draw_circle(base + Vector2(-radius * 0.65, -radius * 0.75), radius * 0.65,
		UiPalette.TREE)
	draw_circle(base + Vector2(radius * 0.65, -radius * 0.75), radius * 0.65,
		UiPalette.TREE)


func _draw_road(area: Vector2) -> void:
	var width: float = area.x * 0.66
	var height: float = area.y * 0.10
	var track := Rect2((area.x - width) * 0.5, area.y * 0.62, width, height)

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

	var ratio: float = _fill_ratio()
	var fill_width: float = (track.size.x - 16.0) * ratio
	draw_rect(Rect2(track.position.x + 8.0, track.position.y + track.size.y * 0.52,
		fill_width, track.size.y * 0.40), Color(UiPalette.CYAN, 0.40))
	if fill_width > 2.0:
		draw_line(Vector2(track.position.x + 8.0 + fill_width, track.position.y + track.size.y * 0.52),
			Vector2(track.position.x + 8.0 + fill_width, track.position.y + track.size.y * 0.92),
			Color.WHITE, 3.0, true)

	# Finish flag at the right end.
	var flag_x: float = track.end.x - 26.0
	for row in 2:
		for column in 2:
			var color: Color = UiPalette.CREAM if (row + column) % 2 == 0 else UiPalette.OUTLINE
			draw_rect(Rect2(flag_x + column * 8.0, track.position.y + 10.0 + row * 8.0, 8.0, 8.0), color)

	var dash_y: float = track.position.y + track.size.y * 0.5
	var offset: float = fmod(_time * 90.0, 64.0)
	var x: float = track.position.x + 24.0 + offset
	while x < track.end.x - 44.0:
		draw_line(Vector2(x, dash_y), Vector2(minf(x + 30.0, track.end.x - 44.0), dash_y),
			Color(UiPalette.YELLOW, 0.65), 4.0, true)
		x += 64.0

	var cart_scale: float = area.y / 880.0
	var cart_x: float = track.position.x + 46.0 + (track.size.x - 110.0) * ratio
	var cart_y: float = track.end.y - 7.0
	var bounce: float = sin(_time * 14.0) * 2.5 * (0.35 + ratio * 0.65)
	_draw_exhaust(Vector2(cart_x - 78.0 * cart_scale, cart_y - 24.0 * cart_scale + bounce))
	CartDrawing.draw_cart(self, Vector2(cart_x, cart_y + bounce), cart_scale, false)


func _draw_exhaust(origin: Vector2) -> void:
	for i in 3:
		var age: float = fmod(_time * 2.2 + i * 0.33, 1.0)
		var alpha: float = (1.0 - age) * 0.35
		draw_circle(origin + Vector2(-age * 46.0, -age * 16.0), 3.0 + age * 8.0,
			Color(0.85, 0.85, 0.88, alpha))


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
