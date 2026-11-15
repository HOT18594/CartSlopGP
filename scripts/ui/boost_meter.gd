extends Control

@export var ratio: float = 1.0:
	set(value):
		var clamped: float = clampf(value, 0.0, 1.0)
		if not is_equal_approx(clamped, ratio):
			ratio = clamped
			queue_redraw()
@export var boosting: bool = false:
	set(value):
		if boosting != value:
			boosting = value
			queue_redraw()

const CYAN := Color("55dfef")
const GOLD := Color("ffd166")
const LOW := Color("ff887e")

var _frame := StyleBoxFlat.new()
var _cell := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.bg_color = Color(0.04, 0.08, 0.14, 0.94)
	_frame.set_corner_radius_all(7)
	_frame.set_border_width_all(1)
	_frame.border_color = Color(0.6, 0.8, 1.0, 0.23)
	_cell.set_corner_radius_all(2)
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	var inner := Rect2(Vector2(5.0, 5.0), size - Vector2(10.0, 10.0))
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	var cell_width: float = (inner.size.x - 27.0) / 10.0
	var fill_color: Color = GOLD if boosting else (LOW if ratio <= 0.15 else CYAN)
	for index in 10:
		var position: Vector2 = inner.position + Vector2(float(index) * (cell_width + 3.0), 0.0)
		_cell.bg_color = Color(0.5, 0.7, 0.85, 0.14)
		draw_style_box(_cell, Rect2(position, Vector2(cell_width, inner.size.y)))
		var amount: float = clampf(ratio * 10.0 - float(index), 0.0, 1.0)
		if amount > 0.001:
			_cell.bg_color = fill_color
			draw_style_box(_cell, Rect2(position, Vector2(cell_width * amount, inner.size.y)))
