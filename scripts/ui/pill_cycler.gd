extends "res://scripts/ui/candy_button.gd"
## Segmented control: discrete choice drawn as equal tactile tiles inside a
## recessed capsule track, with a bordered glossy active pill.

signal option_changed(value: Variant)

const TRACK: Color = Color(0.12, 0.13, 0.24, 0.13)
const TRACK_HOVER: Color = Color(0.12, 0.13, 0.24, 0.19)
const TRACK_BORDER: Color = Color(0.12, 0.11, 0.23, 0.28)
const TEXT_OFF: Color = Color("4e4964")
const TEXT_ON: Color = Color("1e1b3a")

@export var options: PackedStringArray = PackedStringArray()
@export var values: Array = []
@export var tile_min_width: float = 76.0 ## Equal width for every tile.
var selected_index: int = 0

var _track := StyleBoxFlat.new()
var _cell := StyleBoxFlat.new()
var _cell_gloss := StyleBoxFlat.new()


func _ready() -> void:
	super._ready()
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, _blank_style())
	_track.bg_color = TRACK
	_track.set_border_width_all(2)
	_track.border_color = TRACK_BORDER
	_track.set_corner_radius_all(corner_radius)
	_track.anti_aliasing = true
	_cell.set_corner_radius_all(maxi(corner_radius - 3, 6))
	_cell.set_border_width_all(3)
	_cell.border_color = UiPalette.OUTLINE
	_cell.shadow_color = Color(0.08, 0.06, 0.18, 0.28)
	_cell.shadow_size = 1
	_cell.shadow_offset = Vector2(0, 2)
	_cell.anti_aliasing = true
	_cell_gloss.bg_color = Color(1.0, 1.0, 1.0, 0.28)
	_cell_gloss.set_corner_radius_all(maxi(corner_radius - 6, 4))
	_cell_gloss.anti_aliasing = true
	text = ""
	pressed.connect(_cycle)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	resized.connect(queue_redraw)
	_refresh()


func configure(new_options: PackedStringArray, new_values: Array,
		start_index: int = 0) -> void:
	options = new_options
	values = new_values
	selected_index = clampi(start_index, 0, maxi(options.size() - 1, 0))
	_refresh()


func set_index(index: int, emit_signal: bool = false) -> void:
	if options.is_empty():
		return
	var next: int = clampi(index, 0, options.size() - 1)
	if next == selected_index:
		return
	selected_index = next
	queue_redraw()
	if emit_signal:
		option_changed.emit(get_value())


func get_value() -> Variant:
	if selected_index >= 0 and selected_index < values.size():
		return values[selected_index]
	return selected_index


func _cycle() -> void:
	step(1)


func step(direction: int) -> void:
	if options.is_empty():
		return
	var next: int = wrapi(selected_index + direction, 0, options.size())
	if next == selected_index:
		return
	selected_index = next
	queue_redraw()
	option_changed.emit(get_value())


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			grab_focus()
			select_at(click.position)
			accept_event()
		return
	if not has_focus():
		return
	if event.is_action_pressed("ui_left"):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		step(1)
		accept_event()


func select_at(pointer: Vector2) -> void:
	if options.is_empty() or size.x <= 0.0:
		return
	var tile_width: float = size.x / float(options.size())
	var index: int = clampi(int(floor(pointer.x / maxf(tile_width, 1.0))), 0,
		options.size() - 1)
	if index == selected_index:
		return
	selected_index = index
	queue_redraw()
	option_changed.emit(get_value())


func _refresh() -> void:
	text = ""
	custom_minimum_size.x = maxf(custom_minimum_size.x,
		float(options.size()) * tile_min_width)
	queue_redraw()


func _blank_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _draw() -> void:
	if options.is_empty() or size.x <= 0.0:
		return
	_track.bg_color = TRACK_HOVER if ((_hovered or has_focus()) and not disabled) else TRACK
	draw_style_box(_track, Rect2(Vector2.ZERO, size))
	var font: Font = get_theme_font("font")
	if font == null:
		return
	var base_size: int = get_theme_font_size("font_size")
	var tile_width: float = size.x / float(options.size())
	var inset: float = 5.0
	var available_w: float = maxf(tile_width - inset * 4.0 - 10.0, 8.0)
	var font_size: int = base_size
	for index in options.size():
		font_size = mini(font_size, _fit_font(font, options[index], base_size, available_w))
	var ascent: float = font.get_ascent(font_size)
	var descent: float = font.get_descent(font_size)
	var baseline: float = (size.y + ascent - descent) * 0.5

	# Subtle dividers between inactive cells.
	for index in range(1, options.size()):
		if index == selected_index or index - 1 == selected_index:
			continue
		var dx: float = tile_width * float(index)
		draw_line(Vector2(dx, 9.0), Vector2(dx, size.y - 9.0),
			Color(0.12, 0.11, 0.23, 0.14), 1.5, true)

	for index in options.size():
		var selected: bool = index == selected_index
		if selected:
			_cell.bg_color = Color("cfc9da") if disabled else fill_color
			var cell_rect := Rect2(
				Vector2(tile_width * float(index) + inset, inset),
				Vector2(tile_width - inset * 2.0, size.y - inset * 2.0))
			draw_style_box(_cell, cell_rect)
			if cell_rect.size.x > 14.0 and cell_rect.size.y > 14.0:
				draw_style_box(_cell_gloss, Rect2(
					cell_rect.position.x + 5.0,
					cell_rect.position.y + 3.0,
					cell_rect.size.x - 10.0,
					cell_rect.size.y * 0.36))
		draw_string(font, Vector2(tile_width * float(index), baseline),
			options[index], HORIZONTAL_ALIGNMENT_CENTER, tile_width, font_size,
			TEXT_ON if selected else TEXT_OFF)


func _fit_font(font: Font, text_value: String, base_size: int,
		available: float) -> int:
	var font_size: int = base_size
	while font_size > 11:
		if font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size).x <= available:
			break
		font_size -= 1
	return font_size
