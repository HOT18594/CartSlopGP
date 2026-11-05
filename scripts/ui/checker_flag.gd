extends Control
## Waving black/white checkered flag drawn behind the menu title.

@export var columns: int = 7
@export var rows: int = 4
@export var wave_amount: float = 8.0
@export var wave_frequency: float = 0.045
@export var dark: Color = Color("1e1b3a")
@export var light: Color = Color("ffffff")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if columns <= 0 or rows <= 0:
		return
	var cell_width: float = size.x / float(columns)
	var cell_height: float = size.y / float(rows)
	for row in rows:
		for column in columns:
			var color: Color = light if (row + column) % 2 == 0 else dark
			draw_colored_polygon(_cell(row, column, cell_width, cell_height), color)

	# Outline the top and bottom edges so the flag reads as one sticker.
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var steps: int = 14
	for step in steps + 1:
		var x: float = size.x * float(step) / float(steps)
		var offset: float = _wave(x)
		top.append(Vector2(x, offset))
		bottom.append(Vector2(x, size.y + offset))
	draw_polyline(top, dark, 6.0, true)
	draw_polyline(bottom, dark, 6.0, true)


func _cell(row: int, column: int, cell_width: float, cell_height: float) -> PackedVector2Array:
	var x0: float = float(column) * cell_width
	var x1: float = x0 + cell_width
	var y0: float = float(row) * cell_height
	var y1: float = y0 + cell_height
	return PackedVector2Array([
		Vector2(x0, y0 + _wave(x0)),
		Vector2(x1, y0 + _wave(x1)),
		Vector2(x1, y1 + _wave(x1)),
		Vector2(x0, y1 + _wave(x0)),
	])


func _wave(x: float) -> float:
	return sin(x * wave_frequency) * wave_amount
