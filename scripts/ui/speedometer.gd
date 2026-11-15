extends Control

@export var max_speed_kmh: float = 120.0:
	set(value):
		max_speed_kmh = maxf(value, 20.0)
		queue_redraw()
@export var speed_kmh: float = 0.0:
	set(value):
		speed_kmh = maxf(value, 0.0)
@export var boosting: bool = false

const START_ANGLE: float = PI * 0.75
const SWEEP_ANGLE: float = PI * 1.5
const SURFACE := Color("101e32")
const MUTED := Color("71859a")
const CYAN := Color("55dfef")
const GOLD := Color("ffd166")

var _display_speed: float = 0.0
var _boost_blend: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	var next_speed: float = lerpf(_display_speed, speed_kmh, 1.0 - exp(-delta * 16.0))
	if absf(next_speed - speed_kmh) < 0.05:
		next_speed = speed_kmh
	var next_boost: float = move_toward(_boost_blend, 1.0 if boosting else 0.0, delta * 5.0)
	if not is_equal_approx(_display_speed, next_speed) or not is_equal_approx(_boost_blend, next_boost):
		_display_speed = next_speed
		_boost_blend = next_boost
		queue_redraw()


func _draw() -> void:
	var radius: float = minf(size.x, size.y) * 0.5 - 5.0
	if radius < 20.0:
		return
	var center: Vector2 = size * 0.5
	var ratio: float = clampf(_display_speed / max_speed_kmh, 0.0, 1.0)
	var accent: Color = CYAN.lerp(GOLD, _boost_blend)
	draw_circle(center + Vector2(0, 4), radius + 3.0, Color(0.02, 0.04, 0.08, 0.22))
	draw_circle(center, radius, Color(SURFACE, 0.96))
	draw_arc(center, radius - 1.0, 0.0, TAU, 80, Color(0.7, 0.85, 1.0, 0.16), 1.5, true)
	draw_arc(center, radius * 0.88, START_ANGLE, START_ANGLE + SWEEP_ANGLE, 72,
		Color(0.55, 0.7, 0.85, 0.14), 8.0, true)
	if ratio > 0.001:
		draw_arc(center, radius * 0.88, START_ANGLE, START_ANGLE + SWEEP_ANGLE * ratio,
			maxi(2, int(72.0 * ratio)), accent, 8.0, true)
	var font: Font = get_theme_font("font", "Label")
	var font_size: int = maxi(10, int(radius * 0.11))
	for index in 25:
		var fraction: float = float(index) / 24.0
		var angle: float = START_ANGLE + SWEEP_ANGLE * fraction
		var direction := Vector2(cos(angle), sin(angle))
		var major: bool = index % 6 == 0
		var inner: float = 0.71 if major else 0.76
		var tick_color: Color = accent if fraction <= ratio else MUTED
		draw_line(center + direction * radius * inner, center + direction * radius * 0.81,
			tick_color, 2.0 if major else 1.0, true)
		if major:
			var text: String = str(roundi(max_speed_kmh * fraction))
			var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var text_pos: Vector2 = center + direction * radius * 0.59
			text_pos += Vector2(-text_size.x * 0.5, font.get_ascent(font_size) * 0.35)
			draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, MUTED)
	var needle_angle: float = START_ANGLE + SWEEP_ANGLE * ratio
	var direction := Vector2(cos(needle_angle), sin(needle_angle))
	var tangent := Vector2(-direction.y, direction.x)
	var tip: Vector2 = center + direction * radius * 0.99
	var base: Vector2 = center + direction * radius * 0.89
	draw_colored_polygon(PackedVector2Array([tip, base + tangent * 4.0, base - tangent * 4.0]), Color.WHITE)
	draw_arc(center, radius * 0.40, PI * 0.18, PI * 0.82, 24, Color(accent, 0.25), 1.5, true)
