extends Control
## Segmented boost bar with a lightning bolt, styled after the HUD mockup.
## hud.gd feeds `ratio` (0-1) and `boosting` for the glow tint.

@export var ratio: float = 1.0:
	set(value):
		var clamped: float = clampf(value, 0.0, 1.0)
		if is_equal_approx(clamped, ratio) and is_node_ready():
			return
		ratio = clamped
		if is_node_ready():
			queue_redraw()
@export var boosting: bool = false:
	set(value):
		boosting = value
		if is_node_ready():
			queue_redraw()

const SEGMENTS: int = 12
const INK := Color("1e1b3a")
const BOLT := Color("ffd22e")
const FILL_HI := Color("8ef0ff")
const FILL_LO := Color("2fa9e8")
const EMPTY := Color("213d63")

var _frame := StyleBoxFlat.new()
var _segment := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.bg_color = Color("102a4a")
	_frame.corner_radius_top_left = 16
	_frame.corner_radius_top_right = 16
	_frame.corner_radius_bottom_left = 16
	_frame.corner_radius_bottom_right = 16
	_frame.border_width_left = 5
	_frame.border_width_top = 5
	_frame.border_width_right = 5
	_frame.border_width_bottom = 5
	_frame.border_color = INK
	_frame.shadow_color = Color(0.12, 0.1, 0.23, 0.4)
	_frame.shadow_size = 0
	_frame.shadow_offset = Vector2(0, 6)

	_segment.corner_radius_top_left = 7
	_segment.corner_radius_top_right = 7
	_segment.corner_radius_bottom_left = 7
	_segment.corner_radius_bottom_right = 7

	resized.connect(queue_redraw)


func _draw() -> void:
	var bolt_width: float = size.y * 0.95
	_draw_bolt(Rect2(0.0, 0.0, bolt_width, size.y))

	var bar := Rect2(bolt_width * 0.78, size.y * 0.12, size.x - bolt_width * 0.78, size.y * 0.76)
	draw_style_box(_frame, bar)

	var inner := bar.grow(-11.0)
	var gap: float = 4.0
	var seg_width: float = (inner.size.x - gap * float(SEGMENTS - 1)) / float(SEGMENTS)
	var lit: float = ratio * float(SEGMENTS)
	for index in SEGMENTS:
		var rect := Rect2(inner.position.x + float(index) * (seg_width + gap), inner.position.y,
			seg_width, inner.size.y)
		if float(index) + 0.999 <= lit:
			_segment.bg_color = FILL_HI.lerp(FILL_LO, float(index) / float(SEGMENTS - 1))
			if boosting:
				_segment.bg_color = _segment.bg_color.lightened(0.2)
		elif float(index) < lit:
			_segment.bg_color = FILL_HI.lerp(FILL_LO, float(index) / float(SEGMENTS - 1)) \
				.lerp(EMPTY, 1.0 - (lit - float(index)))
		else:
			_segment.bg_color = EMPTY
		draw_style_box(_segment, rect)


func _draw_bolt(rect: Rect2) -> void:
	var points: Array[Vector2] = [
		Vector2(0.56, 0.02), Vector2(0.14, 0.56), Vector2(0.42, 0.56),
		Vector2(0.28, 0.98), Vector2(0.88, 0.42), Vector2(0.58, 0.42),
	]
	var outline := PackedVector2Array()
	var fill := PackedVector2Array()
	var center := rect.position + rect.size * 0.5
	for point: Vector2 in points:
		var scaled := rect.position + point * rect.size
		fill.append(scaled)
		outline.append(center + (scaled - center) * 1.12)
	draw_colored_polygon(outline, INK)
	draw_colored_polygon(fill, BOLT)
