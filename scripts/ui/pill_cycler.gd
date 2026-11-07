extends "res://scripts/ui/candy_button.gd"
## Pill-shaped button that cycles through a small list of options on click.
## Used for BOTS (NO BOTS -> 1 BOT -> ...), mode and game selectors.

signal option_changed(value: Variant)

@export var options: PackedStringArray = PackedStringArray()
@export var values: Array = []
var selected_index: int = 0


func _ready() -> void:
	super._ready()
	pressed.connect(_cycle)
	_refresh()


func configure(new_options: PackedStringArray, new_values: Array, start_index: int = 0) -> void:
	options = new_options
	values = new_values
	selected_index = clampi(start_index, 0, maxi(options.size() - 1, 0))
	_refresh()


func set_index(index: int, emit_signal: bool = false) -> void:
	if options.is_empty():
		return
	selected_index = clampi(index, 0, options.size() - 1)
	_refresh()
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
	## of moving focus away. Clicking still always steps forward.
	if options.is_empty():
		return
	var next: int = wrapi(selected_index + direction, 0, options.size())
	if next == selected_index:
		return
	selected_index = next
	_refresh()
	option_changed.emit(get_value())


func _refresh() -> void:
	if options.is_empty():
		return
	text = options[selected_index] + "  >"
	tooltip_text = "Click to change"
