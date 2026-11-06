extends Control
## Round arcade speedometer: coloured sweep, tick marks and a needle.
## hud.gd feeds `speed_kmh`; the big number is a Label in the scene.

@export var max_speed_kmh: float = 120.0
@export var speed_kmh: float = 0.0:
	set(value):
		var clamped: float = clampf(value, 0.0, max_speed_kmh)
		if is_equal_approx(clamped, speed_kmh) and is_node_ready():
			return
		speed_kmh = clamped
		if is_node_ready():
			queue_redraw()

const START_DEG: float = 140.0
const SWEEP_DEG: float = 260.0
const INK := Color("1e1b3a")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var radius: float = minf(size.x, size.y) * 0.5 - 4.0
	if radius <= 8.0:
		return
	var center: Vector2 = size * 0.5
	var start := deg_to_rad(START_DEG)
	var end := deg_to_rad(START_DEG + SWEEP_DEG)

	# Dark dial with one clean coloured sweep. No needle forest, no tick ring:
	# the big number is the read, the arc is the context.
	draw_circle(center, radius, Color(0.97, 0.97, 0.99))
	draw_arc(center, radius - 1.5, 0.0, TAU, 72, INK, 5.0, true)
	draw_circle(center, radius * 0.88, Color("132a4a"))
	draw_arc(center, radius * 0.88, 0.0, TAU, 72, INK, 4.0, true)

	var segments: int = 28
	for index in segments:
		var t0: float = float(index) / float(segments)
		var t1: float = float(index + 1) / float(segments)
		draw_arc(center, radius * 0.73, start + (end - start) * t0,
			start + (end - start) * t1 + 0.01, 6,
			_sweep_color(t0), radius * 0.11, true)

	var ratio: float = clampf(speed_kmh / maxf(max_speed_kmh, 1.0), 0.0, 1.0)
	var needle_angle: float = start + (end - start) * ratio
	var direction := Vector2(cos(needle_angle), sin(needle_angle))
	var tip: Vector2 = center + direction * radius * 0.68
	var tail: Vector2 = center - direction * radius * 0.12
	# Proper sweeping arm, not just a floating dot.
	draw_line(tail, tip, INK, maxf(4.0, radius * 0.045), true)
	draw_line(tail, tip, Color("ffd22e"), maxf(2.0, radius * 0.026), true)
	draw_circle(center, radius * 0.095, INK)
	draw_circle(center, radius * 0.062, Color("38d6f0"))
	draw_circle(center - Vector2(radius * 0.018, radius * 0.018), radius * 0.022,
		Color(1, 1, 1, 0.45))


func _sweep_color(t: float) -> Color:
	var cyan := Color("38d6f0")
	var yellow := Color("ffd22e")
	var red := Color("f2545b")
	if t < 0.55:
		return cyan.lerp(yellow, t / 0.55)
	return yellow.lerp(red, (t - 0.55) / 0.45)
