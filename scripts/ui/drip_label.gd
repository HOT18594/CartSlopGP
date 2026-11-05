extends Label
## Label that drips paint from the bottom of its glyphs (the "SLOP" title).

@export var drip_color: Color = Color("f26ca7")
@export var drip_outline: Color = Color("1e1b3a")
@export var drip_fractions: PackedFloat32Array = PackedFloat32Array([0.10, 0.28, 0.46, 0.63, 0.8, 0.94])
@export var drip_lengths: PackedFloat32Array = PackedFloat32Array([0.16, 0.09, 0.22, 0.12, 0.18, 0.08])
@export var drip_width: float = 0.085 ## Drip thickness as a fraction of font size.


func _ready() -> void:
	resized.connect(queue_redraw)
	item_rect_changed.connect(queue_redraw)


func _draw() -> void:
	if text.is_empty():
		return
	var font: Font = get_theme_font("font")
	var font_size: int = get_theme_font_size("font_size")
	if font == null or font_size <= 0:
		return
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var left: float = (size.x - text_width) * 0.5
	var ascent: float = font.get_ascent(font_size)
	var descent: float = font.get_descent(font_size)
	var baseline: float = (size.y - (ascent + descent)) * 0.5 + ascent
	var radius: float = float(font_size) * drip_width * 0.5
	for index in drip_fractions.size():
		var x: float = left + text_width * drip_fractions[index]
		var length: float = float(font_size) * drip_lengths[index]
		_draw_drip(Vector2(x, baseline - float(font_size) * 0.04), length, radius)


func _draw_drip(top: Vector2, length: float, radius: float) -> void:
	var bottom: Vector2 = top + Vector2(0.0, length)
	draw_line(top, bottom, drip_outline, radius * 2.0 + 6.0, true)
	draw_circle(bottom, radius + 3.0, drip_outline)
	draw_line(top, bottom, drip_color, radius * 2.0, true)
	draw_circle(bottom, radius, drip_color)
