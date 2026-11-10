extends Control
## Clean, unbroken boost bar. No bolt icon, no segment noise: one rounded
## frame and a bright cyan fill. hud.gd feeds `ratio` and `boosting`.

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
		if boosting == value:
			return
		boosting = value
		if is_node_ready():
			queue_redraw()

const INK := Color("1e1b3a")
const FRAME := Color(0.06, 0.16, 0.30, 0.94)
const FILL_HI := Color("9af4ff")
const FILL_LO := Color("2fa9e8")

var _frame := StyleBoxFlat.new()
var _fill := StyleBoxFlat.new()
var _glow_box := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.bg_color = FRAME
	_frame.border_width_left = 4
	_frame.border_width_top = 4
	_frame.border_width_right = 4
	_frame.border_width_bottom = 4
	_frame.border_color = INK
	_glow_box.bg_color = Color(0.22, 0.88, 1.0, 0.16)
	_glow_box.set_corner_radius_all(14)
	resized.connect(queue_redraw)


func _draw() -> void:
	var radius: int = maxi(int(size.y * 0.5), 2)
	_frame.corner_radius_top_left = radius
	_frame.corner_radius_top_right = radius
	_frame.corner_radius_bottom_left = radius
	_frame.corner_radius_bottom_right = radius
	if boosting:
		draw_style_box(_glow_box, Rect2(Vector2(-3.0, -3.0),
			size + Vector2(6.0, 6.0)))
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))

	var inner := Rect2(Vector2(5.0, 5.0), Vector2(size.x - 10.0, size.y - 10.0))
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var fill_width: float = inner.size.x * clampf(ratio, 0.0, 1.0)
	if fill_width > 0.5:
		_fill.bg_color = FILL_HI.lerp(FILL_LO, 1.0 - clampf(ratio, 0.0, 1.0))
		if boosting:
			_fill.bg_color = _fill.bg_color.lightened(0.22)
		_fill.corner_radius_top_left = maxi(int(inner.size.y * 0.5), 2)
		_fill.corner_radius_top_right = maxi(int(inner.size.y * 0.5), 2)
		_fill.corner_radius_bottom_left = maxi(int(inner.size.y * 0.5), 2)
		_fill.corner_radius_bottom_right = maxi(int(inner.size.y * 0.5), 2)
		draw_style_box(_fill, Rect2(inner.position, Vector2(fill_width, inner.size.y)))
		# A thin top highlight makes the fill feel like liquid rather than a block.
		draw_line(inner.position + Vector2(3.0, 3.0),
			inner.position + Vector2(maxf(fill_width - 3.0, 3.0), 3.0),
			Color(1, 1, 1, 0.35), 2.0, true)
	# Five 20% cells: readable at a glance and still one continuous bar.
	for i in range(1, 5):
		var x: float = inner.position.x + inner.size.x * float(i) / 5.0
		draw_line(Vector2(x, inner.position.y + 1.0),
			Vector2(x, inner.end.y - 1.0), Color(INK, 0.42), 2.0, true)
