extends Control
## Art-only cart used by the boot splash and window icon renderer.

const CartDrawing := preload("res://scripts/ui/cart_drawing.gd")

@export var cart_scale: float = 1.0
@export var bottom_fraction: float = 0.90
@export var flip: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	CartDrawing.draw_cart(self, Vector2(size.x * 0.5, size.y * bottom_fraction),
		cart_scale, flip)
