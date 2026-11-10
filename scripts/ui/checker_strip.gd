extends Control
## Small black/white checkered strip used behind the race position badge.

@export var columns: int = 6
@export var rows: int = 2
@export var cell_color: Color = Color("1e1b3a")
@export var light_color: Color = Color("ffffff")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if columns <= 0 or rows <= 0:
		return
	var cell := Vector2(size.x / float(columns), size.y / float(rows))
	for row in rows:
		for column in columns:
			if (row + column) % 2 == 0:
				draw_rect(Rect2(column * cell.x, row * cell.y, cell.x + 1.0, cell.y + 1.0), cell_color)
