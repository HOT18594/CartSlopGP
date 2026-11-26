extends "res://scripts/ui/candy_button.gd"
## Slanted Parallelogram Segmented Control:
## Discrete racing-sim choice drawn as equal slanted parallelogram cells inside
## a skewed dark-glass track, with a bright glossy active parallelogram tile
## and a matching slanted parallelogram focus outline.

signal option_changed(value: Variant)

const TRACK: Color = Color(0.065, 0.078, 0.175, 0.90)
const TRACK_HOVER: Color = Color(0.100, 0.120, 0.245, 0.94)
const TEXT_OFF: Color = Color(0.84, 0.90, 0.98, 0.86)
const TEXT_ON: Color = Color("1e1b3a")

@export var options: PackedStringArray = PackedStringArray()
@export var values: Array = []
@export var tile_min_width: float = 76.0 ## Equal width for every tile.
var selected_index: int = 0


func _ready() -> void:
	skew_px = 9.0
	super._ready()
	set_meta("custom_focus", true)
	var blank := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, blank)
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
	var sk: float = minf(skew_px, size.x * 0.12)
	var usable_w: float = maxf(size.x - sk - 6.0, 1.0)
	var tile_width: float = usable_w / float(options.size())
	var index: int = clampi(int(floor((pointer.x - sk * 0.5) / maxf(tile_width, 1.0))), 0,
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


func _draw() -> void:
	if options.is_empty() or size.x < 18.0 or size.y < 14.0:
		return
	var focused: bool = has_focus() and not disabled
	var sk: float = minf(skew_px, size.x * 0.12)
	var x0: float = 3.0
	var y0: float = 3.0
	var bw: float = maxf(size.x - sk - 6.0, 12.0)
	var bh: float = maxf(size.y - 6.0, 12.0)

	var track_pts: PackedVector2Array = _para(x0, y0, bw, bh, sk)

	# Focus slanted halo (soft outward glow, no hard clipped line)
	if focused:
		var halo: PackedVector2Array = _para(x0 - 3.0, y0 - 2.5, bw + 6.0, bh + 5.0, sk)
		UiAnim.draw_soft_outline(self, _closed(halo), UiPalette.YELLOW, 3.2,
			UiPalette.YELLOW, 3, 2.0, 0.14)

	# Dark slanted track background
	var track_col: Color = TRACK_HOVER if ((_hovered or focused) and not disabled) else TRACK
	draw_colored_polygon(track_pts, track_col)

	var font: Font = get_theme_font("font")
	if font == null:
		return
	var base_size: int = maxi(get_theme_font_size("font_size"), 12)
	var tile_w: float = bw / float(options.size())
	var inset: float = 3.5
	var available_w: float = maxf(tile_w - inset * 2.0 - 8.0, 8.0)
	var font_size: int = base_size
	for index in options.size():
		font_size = mini(font_size, _fit_font(font, options[index], base_size, available_w))
	var ascent: float = font.get_ascent(font_size)
	var descent: float = font.get_descent(font_size)
	var baseline: float = y0 + (bh + ascent - descent) * 0.5

	# Slanted dividers between inactive options
	for index in range(1, options.size()):
		if index == selected_index or index - 1 == selected_index:
			continue
		var dx: float = x0 + tile_w * float(index)
		draw_line(Vector2(dx + sk * 0.85, y0 + 5.0), Vector2(dx + sk * 0.15, y0 + bh - 5.0),
			Color(1.0, 1.0, 1.0, 0.16), 1.5, true)

	# Active slanted cell + crisp labels
	for index in options.size():
		var selected: bool = index == selected_index
		var cx: float = x0 + tile_w * float(index)
		if selected:
			var cell_col: Color = Color("646a82") if disabled else fill_color
			var cell_pts: PackedVector2Array = _para(cx + inset, y0 + inset,
				maxf(tile_w - inset * 2.0, 6.0), maxf(bh - inset * 2.0, 6.0), sk * 0.85)
			draw_colored_polygon(cell_pts, cell_col)
			var gh: float = maxf((bh - inset * 2.0) * 0.36, 2.0)
			var gloss: PackedVector2Array = _para(cx + inset + sk * 0.50, y0 + inset + 1.0,
				maxf(tile_w - inset * 2.0 - 2.0, 4.0), gh, sk * 0.32)
			# Vertical alpha fade: the active tile's gloss melts into the plate
			# instead of ending on a hard horizontal line.
			UiAnim.draw_vertical_fade(self, gloss, Color.WHITE, 0.28)
			draw_polyline(_closed(cell_pts), UiPalette.INK, 2.5, true)
		var txt_col: Color = TEXT_ON if selected else TEXT_OFF
		if disabled and not selected:
			txt_col = Color(0.60, 0.64, 0.74, 0.55)
		draw_string(font, Vector2(cx + sk * 0.5, baseline),
			options[index], HORIZONTAL_ALIGNMENT_CENTER, tile_w, font_size, txt_col)

	# Crisp outer ink border around track
	draw_polyline(_closed(track_pts), UiPalette.INK, 3.2, true)


func _fit_font(font: Font, text_value: String, base_size: int,
		available: float) -> int:
	var font_size: int = base_size
	while font_size > 11:
		if font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size).x <= available:
			break
		font_size -= 1
	return font_size
