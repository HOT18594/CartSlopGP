extends Label
## Label that drips paint from the bottom of its glyphs (the "SLOP" title).
##
## Drips are positioned from real glyph advances, so each one attaches to the
## bottom of a letter instead of being sprinkled across the label rectangle.

@export var drip_color: Color = Color("f26ca7")
@export var drip_outline: Color = Color("1e1b3a")
@export var drip_letters: String = "SLOP" ## Letters that get a drip.
@export var drip_lengths: PackedFloat32Array = PackedFloat32Array([0.24, 0.13, 0.30, 0.16])
@export var drip_widths: PackedFloat32Array = PackedFloat32Array([0.082, 0.052, 0.094, 0.062])
@export var drip_slant: float = 0.012 ## Sideways drift as a fraction of font size.


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
	var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
		-1, font_size).x
	var left: float = (size.x - text_width) * 0.5
	var ascent: float = font.get_ascent(font_size)
	var descent: float = font.get_descent(font_size)
	var baseline: float = (size.y - (ascent + descent)) * 0.5 + ascent
	var drip_index: int = 0
	var cursor: float = 0.0
	for index in text.length():
		var character: String = text[index]
		var char_width: float = font.get_string_size(character,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if character != " " and drip_letters.find(character.to_upper()) >= 0:
			var length_scale: float = _at(drip_lengths, drip_index, 0.16)
			var width_scale: float = _at(drip_widths, drip_index, 0.065)
			var slant: float = drip_slant * float(font_size) \
				* (1.0 if drip_index % 2 == 0 else -0.65)
			_draw_drip(Vector2(left + cursor + char_width * 0.5,
				baseline - float(font_size) * 0.012),
				float(font_size) * length_scale,
				float(font_size) * width_scale * 0.5, slant)
			drip_index += 1
		cursor += char_width


func _at(values: PackedFloat32Array, index: int, fallback: float) -> float:
	return values[index % values.size()] if values.size() > 0 else fallback


func _draw_drip(top: Vector2, length: float, radius: float, slant: float) -> void:
	# A tapered blob, not a straight line: narrow where it joins the glyph,
	# with a soft belly and a round bead at the end.
	var steps: int = 8
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var outline_left := PackedVector2Array()
	var outline_right := PackedVector2Array()
	for index in steps:
		var t: float = float(index) / float(steps - 1)
		var centre: Vector2 = top + Vector2(slant * t * t, length * t)
		var half: float = radius * (0.42 + 0.58 * t + 0.10 * sin(t * PI))
		left.append(centre + Vector2(-half, 0.0))
		right.append(centre + Vector2(half, 0.0))
		outline_left.append(centre + Vector2(-half - 3.0, 0.0))
		outline_right.append(centre + Vector2(half + 3.0, 0.0))
	var outline := _joined(outline_left, outline_right)
	var fill := _joined(left, right)
	var bottom: Vector2 = top + Vector2(slant, length)
	draw_colored_polygon(outline, drip_outline)
	draw_circle(bottom, radius + 3.0, drip_outline)
	draw_colored_polygon(fill, drip_color)
	draw_circle(bottom, radius, drip_color)
	# A quiet highlight makes the goo read as a rounded bead of paint.
	draw_line(top + Vector2(-radius * 0.18, 0.0), bottom + Vector2(-radius * 0.18, 0.0),
		Color(1, 1, 1, 0.20), maxf(1.0, radius * 0.38), true)


func _joined(first: PackedVector2Array, second: PackedVector2Array) -> PackedVector2Array:
	var out := first.duplicate()
	for index in range(second.size() - 1, -1, -1):
		out.append(second[index])
	return out
