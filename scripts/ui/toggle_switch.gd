class_name ToggleSwitch
extends Control
## Compact modern switch used by Settings. Draws its own track and knob so it
## cannot inherit the oversized CheckButton padding or white candy text.

signal toggled(on: bool)

const INK := Color("1e1b3a")
const TRACK_OFF := Color("d8d2c4")
const TRACK_ON := Color("4fbf52")
const KNOB := Color("fff6e3")

var on: bool = false:
	set(value):
		on = value
		queue_redraw()
var _hovered: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(58, 30)
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		_hovered = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hovered = false
		queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			on = not on
			toggled.emit(on)
			accept_event()


func _draw() -> void:
	var radius: float = size.y * 0.5
	var track := StyleBoxFlat.new()
	track.bg_color = TRACK_ON if on else TRACK_OFF
	if _hovered:
		track.bg_color = track.bg_color.lightened(0.08)
	track.border_color = INK
	track.set_border_width_all(2)
	track.set_corner_radius_all(int(radius))
	draw_style_box(track, Rect2(Vector2.ZERO, size))
	var knob_radius: float = radius - 5.0
	var knob_x: float = size.x - radius if on else radius
	draw_circle(Vector2(knob_x, radius), knob_radius, KNOB)
	draw_arc(Vector2(knob_x, radius), knob_radius, 0.0, TAU, 24, INK, 1.5, true)
