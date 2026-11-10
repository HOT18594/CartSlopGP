extends Control
## Clean waving checkered banner used on the menu, the race lobby and the
## result card. Optional pole for the menu; banners stay centred without it.

@export var columns: int = 6
@export var rows: int = 4
@export var wave_amount: float = 7.0
@export var wave_frequency: float = 0.05
@export var dark: Color = Color("1e1b3a")
@export var light: Color = Color("fff6e3")
@export var show_pole: bool = true

var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if columns <= 0 or rows <= 0:
		return
	var pole_width: float = 12.0 if show_pole else 0.0
	var flag_width: float = maxf(size.x - pole_width, 1.0)
	var cell_width: float = flag_width / float(columns)
	var cell_height: float = size.y / float(rows)
	var origin := Vector2(pole_width, 0.0)

	for row in rows:
		for column in columns:
			var color: Color = light if (row + column) % 2 == 0 else dark
			draw_colored_polygon(_cell(origin, row, column, cell_width, cell_height), color)

	# One closed outline around the whole banner, so it reads as a sticker
	# instead of loose squares.
	var edge := PackedVector2Array()
	var steps: int = 18
	for step in steps + 1:
		var x: float = origin.x + flag_width * float(step) / float(steps)
		edge.append(Vector2(x, _wave(x - origin.x)))
	for step in range(steps, -1, -1):
		var x: float = origin.x + flag_width * float(step) / float(steps)
		edge.append(Vector2(x, size.y + _wave(x - origin.x)))
	edge.append(edge[0])
	draw_polyline(edge, dark, 6.0, true)

	if show_pole:
		# A short pole and cream cap make the menu flag read as a real flag.
		draw_rect(Rect2(0.0, -10.0, 10.0, size.y + 24.0), dark)
		draw_rect(Rect2(3.0, -8.0, 4.0, size.y + 20.0), light.darkened(0.08))
		draw_circle(Vector2(5.0, -13.0), 7.0, dark)
		draw_circle(Vector2(5.0, -13.0), 4.0, light)


func _cell(origin: Vector2, row: int, column: int, cell_width: float,
		cell_height: float) -> PackedVector2Array:
	var x0: float = origin.x + float(column) * cell_width
	var x1: float = x0 + cell_width
	var y0: float = float(row) * cell_height
	var y1: float = y0 + cell_height
	return PackedVector2Array([
		Vector2(x0, y0 + _wave(x0 - origin.x)),
		Vector2(x1, y0 + _wave(x1 - origin.x)),
		Vector2(x1, y1 + _wave(x1 - origin.x)),
		Vector2(x0, y1 + _wave(x0 - origin.x)),
	])


func _wave(x: float) -> float:
	return sin(x * wave_frequency + _time * 2.2) * wave_amount
