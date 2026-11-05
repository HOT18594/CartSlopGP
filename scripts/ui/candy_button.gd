extends Button
## Chunky outlined candy button: thick dark border, coloured fill, hard drop
## shadow and white outlined text (font comes from the theme).

@export var fill_color: Color = Color("45b6f0"):
	set(value):
		fill_color = value
		if is_node_ready():
			_apply_styles()
@export var shadow_offset: int = 9 ## Vertical offset of the hard shadow in px.
@export var corner_radius: int = 30


var _gloss := StyleBoxFlat.new()


func _ready() -> void:
	_gloss.bg_color = Color(1, 1, 1, 0.22)
	_gloss.corner_radius_top_left = 20
	_gloss.corner_radius_top_right = 20
	_gloss.corner_radius_bottom_left = 14
	_gloss.corner_radius_bottom_right = 14
	_apply_styles()


func _draw() -> void:
	# Glossy sheen across the top half, like the candy buttons in the mockup.
	var inset: float = 14.0
	var height: float = size.y * 0.30
	draw_style_box(_gloss, Rect2(inset, 8.0, size.x - inset * 2.0, height))


func _apply_styles() -> void:
	add_theme_stylebox_override("normal", _make(fill_color, shadow_offset))
	add_theme_stylebox_override("hover", _make(fill_color.lightened(0.14), shadow_offset + 2))
	add_theme_stylebox_override("pressed", _make(fill_color.darkened(0.10), maxi(shadow_offset - 6, 2)))
	add_theme_stylebox_override("disabled", _make(Color("9a94b4"), 5))


func _make(color: Color, drop: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = corner_radius
	box.corner_radius_top_right = corner_radius
	box.corner_radius_bottom_left = corner_radius
	box.corner_radius_bottom_right = corner_radius
	box.border_width_left = 6
	box.border_width_top = 6
	box.border_width_right = 6
	box.border_width_bottom = 6
	box.border_color = Color("1e1b3a")
	box.shadow_color = Color(0.12, 0.1, 0.23, 0.5)
	box.shadow_size = 0
	box.shadow_offset = Vector2(0, drop)
	box.content_margin_left = 26
	box.content_margin_right = 26
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	box.anti_aliasing = true
	return box
