extends "res://scripts/ui/candy_button.gd"
## Segmented control: a small discrete choice drawn as equal tiles side by side.
##
## It is one focus stop, exactly like the old cycling pill, so MenuNav and the
## keyboard ring keep working unchanged: left/right (or the d-pad) change the
## value in place, Enter steps forward, and a click selects the tile under the
## pointer. The file name and public API are unchanged (configure / set_index /
## get_value / step / option_changed) so every existing call site keeps working.
##
## Only the selected tile is filled with the accent, over one quiet track, so a
## row reads as equal squares instead of N bordered pills. `_draw()` allocates
## nothing: two cached styleboxes and the theme font are reused.

signal option_changed(value: Variant)

const TRACK: Color = Color(0.117647, 0.105882, 0.227451, 0.10)
const TEXT_OFF: Color = Color("5a5470")
const TEXT_ON: Color = Color("1e1b3a")

@export var options: PackedStringArray = PackedStringArray()
@export var values: Array = []
@export var tile_min_width: float = 68.0 ## Equal width for every tile.
var selected_index: int = 0

var _track := StyleBoxFlat.new()
var _cell := StyleBoxFlat.new()


func _ready() -> void:
	super._ready()
	# The inherited candy background would paint one solid pill behind the
	# tiles; the strip draws its own track instead.
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, _blank_style())
	_track.bg_color = TRACK
	_track.set_corner_radius_all(corner_radius)
	_track.anti_aliasing = true
	_cell.set_corner_radius_all(corner_radius)
	_cell.anti_aliasing = true
	text = ""
	pressed.connect(_cycle)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
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
	## Left/right arrow keys (and the d-pad) change the value in place instead
	## of moving focus away. Clicking a tile selects that tile directly.
	if options.is_empty():
		return
	var next: int = wrapi(selected_index + direction, 0, options.size())
	if next == selected_index:
		return
	selected_index = next
	queue_redraw()
	option_changed.emit(get_value())


func _gui_input(event: InputEvent) -> void:
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
	## Pick the tile under a point. Public so a screen can drive the strip from
	## a test or a touch event without faking a button press.
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
	## Reserves the same padding the old pill used, so the strip cannot collapse
	## to the height of its text.
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
	_track.bg_color = TRACK
	if _hovered or has_focus():
		_track.bg_color = Color(TRACK.r, TRACK.g, TRACK.b, TRACK.a + 0.05)
	draw_style_box(_track, Rect2(Vector2.ZERO, size))
	var font: Font = get_theme_font("font")
	if font == null:
		return
	var base_size: int = get_theme_font_size("font_size")
	var tile_width: float = size.x / float(options.size())
	var inset: float = 3.0
	for index in options.size():
		var selected: bool = index == selected_index
		if selected:
			_cell.bg_color = fill_color
			draw_style_box(_cell, Rect2(
				Vector2(tile_width * float(index) + inset, inset),
				Vector2(tile_width - inset * 2.0, size.y - inset * 2.0)))
		var font_size: int = _fit_font(font, options[index], base_size,
			tile_width - inset * 4.0)
		var ascent: float = font.get_ascent(font_size)
		var descent: float = font.get_descent(font_size)
		var baseline: float = (size.y + ascent - descent) * 0.5
		draw_string(font, Vector2(tile_width * float(index), baseline),
			options[index], HORIZONTAL_ALIGNMENT_CENTER, tile_width, font_size,
			TEXT_ON if selected else TEXT_OFF)


func _fit_font(font: Font, text_value: String, base_size: int,
		available: float) -> int:
	## Shrink one long label instead of clipping it. Measured only while the
	## strip redraws, never per frame.
	var font_size: int = base_size
	while font_size > 11:
		if font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size).x <= available:
			break
		font_size -= 1
	return font_size
