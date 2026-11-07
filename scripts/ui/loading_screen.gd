extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Themed loading overlay. Everything sits directly on the SlopMart parking
## lot illustration. There is NO card or panel: the sky, store, trees and
## checker strip stay visible around the progress bar.
##
## Contrast comes from a soft vertical scrim and font outlines, not a box.
## The fill is damped toward the real load value, so the bar never snaps and
## the number always agrees with what is drawn.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CartDrawing := preload("res://scripts/ui/cart_drawing.gd")
const DISPLAY_FONT := "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"
const ART_PATH: String = "res://assets/ui/art/bg_parking.png"

const TIPS: PackedStringArray = [
	"TIP: Hold SPACE to drift around corners.",
	"TIP: Boost pads refill your meter instantly.",
	"TIP: You can drive over the speed bumps - floor it.",
	"TIP: Press R to reset the cart if you get stuck.",
	"TIP: Crates and cones are light - ram them.",
]

const SEGMENTS: int = 10
const BAR_X: float = 0.175
const BAR_W: float = 0.65
const BAR_TOP: float = 0.655
const BAR_HEIGHT: float = 0.055

var progress: float = 0.0
var indeterminate: bool = false

var _time: float = 0.0
var _shown: float = 0.0
var _tip_index: int = 0
var _tip_timer: float = 0.0
var _tip_label: Label
var _percent_label: Label
var _caption_label: Label
var _message_label: Label
var _display: Font
var _art: Texture2D


func _ready() -> void:
	_display = load(DISPLAY_FONT)
	if ResourceLoader.exists(ART_PATH):
		_art = load(ART_PATH) as Texture2D
	# Swallow clicks while the overlay is up: the menu underneath is about to
	# be replaced, and a blind click must not trigger its buttons.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_tip_label = get_node_or_null("Tip") as Label
	_percent_label = get_node_or_null("Percent") as Label
	_caption_label = get_node_or_null("Caption") as Label
	_message_label = get_node_or_null("Message") as Label
	resized.connect(queue_redraw)
	_show_tip()
	_refresh_labels()


func set_progress(value: float, immediate: bool = false) -> void:
	progress = clampf(value, 0.0, 1.0)
	if immediate:
		_shown = progress
		_refresh_labels()
	queue_redraw()


func set_indeterminate(value: bool) -> void:
	indeterminate = value
	if value:
		_shown = 0.0
	else:
		_shown = progress
	_refresh_labels()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	if not indeterminate:
		_shown = UiAnim.damp(_shown, progress, delta, 14.0)
		if absf(_shown - progress) < 0.001:
			_shown = progress
	_tip_timer += delta
	if _tip_timer >= 4.5:
		_tip_timer = 0.0
		_tip_index = (_tip_index + 1) % TIPS.size()
		_show_tip()
	_refresh_labels()
	queue_redraw()


func _refresh_labels() -> void:
	if _percent_label != null:
		if indeterminate:
			_percent_label.text = "· · ·"
		else:
			_percent_label.text = "%d%%" % int(round(_shown * 100.0))
	if _caption_label != null:
		_caption_label.text = "GETTING READY" if indeterminate else "LOADING SCENE"
	if _message_label != null:
		_message_label.modulate.a = 0.80 + 0.20 * sin(_time * 1.6)


func _show_tip() -> void:
	if _tip_label != null:
		_tip_label.text = TIPS[_tip_index]


func _fill_ratio() -> float:
	if indeterminate:
		return 0.5 + 0.32 * sin(_time * 1.5)
	return _shown


func _bar_rect(area: Vector2) -> Rect2:
	return Rect2(area.x * BAR_X, area.y * BAR_TOP, area.x * BAR_W,
		maxf(area.y * BAR_HEIGHT, 28.0))


func _draw() -> void:
	var area: Vector2 = size
	if area.x < 4.0 or area.y < 4.0:
		return
	if _art != null:
		_draw_art(area)
	else:
		_draw_sky(area)
		_draw_sun(area)
		_draw_clouds(area)
		_draw_hills(area)
		_draw_backdrop(area)
	_draw_scrim(area)
	_draw_bar(area)
	_draw_checker(area)



func _draw_art(area: Vector2) -> void:
	## Aspect-cover the AI lot instead of stretching it.
	var source: Vector2 = _art.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return
	var scale: float = maxf(area.x / source.x, area.y / source.y)
	var drawn: Vector2 = source * scale
	var origin: Vector2 = (area - drawn) * 0.5
	draw_texture_rect(_art, Rect2(origin, drawn), false)


func _draw_sky(area: Vector2) -> void:
	var bands: int = 40
	for band in bands:
		var t: float = float(band) / float(bands - 1)
		var color: Color = UiPalette.SKY_TOP.lerp(UiPalette.SKY_BOTTOM, t)
		draw_rect(Rect2(0.0, area.y * float(band) / float(bands) * 0.62,
			area.x, area.y * 0.62 / float(bands) + 1.0), color)


func _draw_sun(area: Vector2) -> void:
	var center := Vector2(area.x * 0.82, area.y * 0.15)
	var radius: float = area.y * 0.075
	draw_circle(center, radius * 1.5, Color(UiPalette.YELLOW, 0.16))
	draw_circle(center, radius, Color(UiPalette.YELLOW, 0.95))
	for i in 3:
		var y: float = center.y + radius * (0.25 + 0.22 * i)
		var half: float = sqrt(maxf(radius * radius - pow(y - center.y, 2.0), 0.0))
		draw_rect(Rect2(center.x - half, y, half * 2.0, radius * 0.06),
			Color(UiPalette.RED, 0.35))


func _draw_clouds(area: Vector2) -> void:
	var clouds: Array[Vector4] = [
		Vector4(0.10, 0.15, 1.0, 12.0),
		Vector4(0.36, 0.10, 0.7, 18.0),
		Vector4(0.62, 0.20, 0.55, 8.0),
		Vector4(0.90, 0.27, 0.8, 14.0),
	]
	for cloud: Vector4 in clouds:
		var x: float = fposmod(area.x * cloud.x + _time * cloud.w, area.x + 260.0) - 130.0
		var center := Vector2(x, area.y * cloud.y)
		var radius: float = area.y * 0.035 * cloud.z
		var white := Color(1, 1, 1, 0.92)
		draw_circle(center, radius, white)
		draw_circle(center + Vector2(-radius * 1.1, radius * 0.2), radius * 0.75, white)
		draw_circle(center + Vector2(radius * 1.05, radius * 0.25), radius * 0.65, white)


func _draw_hills(area: Vector2) -> void:
	var base_y: float = area.y * 0.46
	for layer in 2:
		var color := Color(0.24, 0.55, 0.34, 0.55) if layer == 0 \
			else Color(0.19, 0.45, 0.29, 0.75)
		var points := PackedVector2Array()
		var steps: int = 32
		var amp: float = area.y * (0.045 - layer * 0.012)
		var phase: float = layer * 1.7
		for step in steps + 1:
			var t: float = float(step) / float(steps)
			var y: float = base_y + layer * 10.0 - sin(t * PI * 2.0 + phase) * amp \
				- sin(t * PI * 5.0 + phase) * amp * 0.25
			points.append(Vector2(t * area.x, y))
		points.append(Vector2(area.x, area.y))
		# Close along the bottom edge; crossing the wavy top would make the
		# triangulation fail and Godot logs "Invalid polygon data".
		points.append(Vector2(0.0, area.y))
		draw_colored_polygon(points, color)
	draw_rect(Rect2(0.0, base_y, area.x, area.y - base_y), Color(0.80, 0.75, 0.81, 0.58))


func _draw_backdrop(area: Vector2) -> void:
	# Parking-bay lines and a small SlopMart fill the strip above the bar.
	var vanish := Vector2(area.x * 0.50, area.y * 0.47)
	for index in range(-4, 5):
		if index == 0:
			continue
		var bottom := vanish + Vector2(float(index) * area.x * 0.18, area.y * 0.30)
		draw_line(vanish, bottom, Color(1, 1, 1, 0.32), 2.0, true)

	var left: float = area.x * 0.79
	var right: float = area.x * 0.975
	var top: float = area.y * 0.315
	var bottom: float = area.y * 0.465
	draw_rect(Rect2(left, top, right - left, bottom - top), Color(0.96, 0.79, 0.76))
	draw_rect(Rect2(left - 5.0, top, right - left + 10.0, area.y * 0.022),
		Color(0.85, 0.50, 0.46))
	draw_rect(Rect2(left, bottom - 4.0, right - left, 4.0), Color(0.72, 0.62, 0.68))
	var sign_box := Rect2(left + (right - left) * 0.10, top + area.y * 0.022,
		(right - left) * 0.80, area.y * 0.040)
	var sign_style := StyleBoxFlat.new()
	sign_style.bg_color = Color(0.91, 0.27, 0.24)
	sign_style.set_corner_radius_all(6)
	sign_style.set_border_width_all(3)
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
	_small_tree(Vector2(area.x * 0.06, area.y * 0.470), area.y * 0.028)
	_small_tree(Vector2(area.x * 0.15, area.y * 0.466), area.y * 0.022)


func _small_tree(base: Vector2, radius: float) -> void:
	draw_rect(Rect2(base.x - radius * 0.10, base.y - radius * 0.7,
		radius * 0.20, radius * 0.7), Color(0.45, 0.32, 0.25))
	draw_circle(base + Vector2(0.0, -radius), radius, UiPalette.TREE)
	draw_circle(base + Vector2(-radius * 0.65, -radius * 0.75), radius * 0.65,
		UiPalette.TREE)
	draw_circle(base + Vector2(radius * 0.65, -radius * 0.75), radius * 0.65,
		UiPalette.TREE)


func _draw_scrim(area: Vector2) -> void:
	## A soft vertical darkening, NOT a rectangle. It fades in and out so the
	## illustration stays visible while the outlined labels remain readable.
	var top: float = area.y * 0.44
	var height: float = area.y * 0.48
	var bands: int = 80
	var step: float = height / float(bands)
	for band in bands:
		var t: float = (float(band) + 0.5) / float(bands)
		var falloff: float = sin(t * PI)
		var alpha: float = 0.20 * pow(falloff, 1.4)
		# Exact float height, no +1 overlap: overlapping translucent bands
		# showed up as visible horizontal stripes over flat AI artwork.
		draw_rect(Rect2(0.0, top + step * float(band), area.x, step),
			Color(0.06, 0.08, 0.18, alpha))


func _draw_bar(area: Vector2) -> void:
	var bar: Rect2 = _bar_rect(area)
	var ratio: float = _fill_ratio()
	var inset: float = 8.0
	var inner: Rect2 = Rect2(bar.position.x + inset, bar.position.y + inset,
		bar.size.x - inset * 2.0, bar.size.y - inset * 2.0)
	var radius: float = inner.size.y * 0.5

	# A soft ground shadow keeps the track anchored to the lot.
	draw_rect(Rect2(bar.position.x + 4.0, bar.end.y - 4.0,
		bar.size.x - 8.0, 12.0), Color(0.06, 0.05, 0.14, 0.20))

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.07, 0.15, 1.0)
	track.set_corner_radius_all(int(radius))
	track.set_border_width_all(5)
	track.border_color = UiPalette.OUTLINE
	track.shadow_color = Color(0.03, 0.03, 0.08, 0.45)
	track.shadow_size = 14
	track.shadow_offset = Vector2(0, 8)
	draw_style_box(track, inner)

	var fill_width: float = maxf(inner.size.x * clampf(ratio, 0.0, 1.0), 0.0)
	if fill_width > 2.0:
		var fill := StyleBoxFlat.new()
		var tint: Color = UiPalette.CYAN.lerp(UiPalette.YELLOW, clampf(ratio, 0.0, 1.0))
		fill.bg_color = tint
		fill.set_corner_radius_all(int(radius))
		draw_style_box(fill, Rect2(inner.position, Vector2(fill_width, inner.size.y)))
		var shine_x: float = inner.position.x + fposmod(_time * 150.0, inner.size.x + 120.0) - 120.0
		for stripe in 3:
			var sx: float = shine_x + float(stripe) * 34.0
			if sx < inner.position.x + radius or sx > inner.position.x + fill_width - radius:
				continue
			draw_rect(Rect2(sx, inner.position.y + 3.0, 9.0, inner.size.y - 6.0),
				Color(1, 1, 1, 0.13))
		var head_x: float = inner.position.x + fill_width
		draw_circle(Vector2(head_x, inner.get_center().y), radius + 5.0,
			Color(UiPalette.YELLOW, 0.14 + 0.06 * sin(_time * 6.0)))

	# Ten evenly spaced sections: light dividers on the unfilled part, dark
	# dividers on the filled part, so progress always reads as discrete steps.
	for index in range(1, SEGMENTS):
		var x: float = inner.position.x + inner.size.x * float(index) / float(SEGMENTS)
		var on_fill: bool = x < inner.position.x + fill_width
		draw_line(Vector2(x, inner.position.y + 3.0),
			Vector2(x, inner.end.y - 3.0),
			Color(0.06, 0.07, 0.14, 0.55) if on_fill else Color(1, 1, 1, 0.22),
			2.0, true)

	# Finish flag at the right end of the track.
	var flag_x: float = inner.end.x - 20.0
	for row in 2:
		for column in 2:
			var color: Color = UiPalette.CREAM if (row + column) % 2 == 0 \
				else UiPalette.OUTLINE
			draw_rect(Rect2(flag_x + column * 7.0,
				inner.position.y - 13.0 + row * 7.0, 7.0, 7.0), color)

	# Animated road dashes above the bar give the background some motion.
	var dash_y: float = inner.position.y - 22.0
	var offset: float = fmod(_time * 80.0, 60.0)
	var x: float = inner.position.x + 10.0 + offset
	while x < inner.end.x - 40.0:
		draw_line(Vector2(x, dash_y), Vector2(minf(x + 26.0, inner.end.x - 40.0), dash_y),
			Color(UiPalette.YELLOW, 0.55), 3.0, true)
		x += 60.0

	_draw_cart(area, inner, ratio)


func _draw_cart(area: Vector2, inner: Rect2, ratio: float) -> void:
	var scale: float = area.y / 2100.0
	var head_x: float = inner.position.x + inner.size.x * clampf(ratio, 0.0, 1.0)
	var cart_x: float = clampf(head_x, inner.position.x + 82.0 * scale,
		inner.end.x - 90.0 * scale)
	var cart_y: float = inner.position.y - 7.0
	var bounce: float = sin(_time * 13.0) * 2.0
	for i in 3:
		var age: float = fmod(_time * 2.0 + i * 0.33, 1.0)
		var alpha: float = (1.0 - age) * 0.28
		draw_circle(Vector2(cart_x - (78.0 + age * 40.0) * scale,
			cart_y - (26.0 + age * 14.0) * scale + bounce),
			(3.0 + age * 7.0) * maxf(scale * 2.0, 0.6),
			Color(0.88, 0.90, 0.95, alpha))
	CartDrawing.draw_cart(self, Vector2(cart_x, cart_y + bounce), scale, false)


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
