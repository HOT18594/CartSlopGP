extends SceneTree
## Builds res://assets/ui/theme.tres from the palette below.
## Run:  godot --headless --path . --script tools/build_ui_theme.gd
## Re-run after changing colours or fonts; scenes only reference the Theme.

const OUTLINE := Color("1e1b3a")
const CREAM := Color("fff6e3")
const INK := Color("1e1b3a")
const WHITE := Color("ffffff")
const BLUE := Color("45b6f0")
const BLUE_HOVER := Color("6cc8f7")
const BLUE_PRESSED := Color("2a8fc4")
const YELLOW := Color("ffd22e")


func _init() -> void:
	# Static instances of Fredoka (see tools/README-fonts.md): Godot ignores the
	# variable weight axis, so the weights are baked with fontTools instead.
	var body_medium: FontFile = load("res://assets/ui/fonts/Fredoka-Medium.ttf")
	var display: FontFile = load("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")
	if body_medium == null or display == null:
		push_error("Missing UI fonts")
		quit(1)
		return

	var theme := Theme.new()
	theme.default_font = body_medium
	theme.default_font_size = 22

	_label(theme, display)
	_button(theme, display)
	_panel(theme)
	_progress(theme)
	_slider(theme)
	_checkbutton(theme)

	var error := ResourceSaver.save(theme, "res://assets/ui/theme.tres")
	print("theme saved: ", error, " -> res://assets/ui/theme.tres")
	quit(0 if error == OK else 1)


func _flat(color: Color, radius: int, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	if border_width > 0:
		box.border_width_left = border_width
		box.border_width_top = border_width
		box.border_width_right = border_width
		box.border_width_bottom = border_width
		box.border_color = border
	box.anti_aliasing = true
	return box


func _label(theme: Theme, display: Font) -> void:
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.25))
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_constant("outline_size", "Label", 0)

	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", display)
	theme.set_font_size("font_size", "TitleLabel", 96)
	theme.set_color("font_color", "TitleLabel", WHITE)
	theme.set_color("font_outline_color", "TitleLabel", OUTLINE)


func _button(theme: Theme, display: Font) -> void:
	theme.set_font("font", "Button", display)
	theme.set_font_size("font_size", "Button", 30)

	var normal := _flat(BLUE, 30, OUTLINE, 6)
	normal.content_margin_left = 30
	normal.content_margin_right = 30
	normal.content_margin_top = 14
	normal.content_margin_bottom = 16
	normal.shadow_color = Color(0.12, 0.1, 0.23, 0.45)
	normal.shadow_size = 0
	normal.shadow_offset = Vector2(0, 9)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = BLUE_HOVER

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = BLUE_PRESSED
	pressed.shadow_offset = Vector2(0, 3)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("9a94b4")
	disabled.border_color = Color("4b4566")
	disabled.shadow_offset = Vector2(0, 5)

	var focus := _flat(Color(0, 0, 0, 0), 30, WHITE, 4)
	focus.draw_center = false

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", WHITE)
	theme.set_color("font_hover_color", "Button", WHITE)
	theme.set_color("font_pressed_color", "Button", WHITE)
	theme.set_color("font_focus_color", "Button", WHITE)
	theme.set_color("font_disabled_color", "Button", Color("cfc9e0"))
	theme.set_color("font_outline_color", "Button", OUTLINE)
	theme.set_constant("outline_size", "Button", 10)
	theme.set_constant("shadow_offset_x", "Button", 0)
	theme.set_constant("shadow_offset_y", "Button", 0)


func _panel(theme: Theme) -> void:
	var panel := _flat(CREAM, 26, OUTLINE, 5)
	panel.content_margin_left = 36
	panel.content_margin_right = 36
	panel.content_margin_top = 30
	panel.content_margin_bottom = 30
	panel.shadow_color = Color(0.12, 0.1, 0.23, 0.45)
	panel.shadow_size = 0
	panel.shadow_offset = Vector2(0, 10)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)


func _progress(theme: Theme) -> void:
	var background := _flat(Color("0e2a45"), 14, OUTLINE, 4)
	background.content_margin_top = 0
	background.content_margin_bottom = 0

	var fill := _flat(Color("38d6f0"), 14, OUTLINE, 4)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0

	theme.set_stylebox("background", "ProgressBar", background)
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_color("font_color", "ProgressBar", WHITE)


func _slider(theme: Theme) -> void:
	var track := _flat(Color("d8cdb8"), 8, OUTLINE, 3)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var filled := _flat(YELLOW, 8, OUTLINE, 3)
	filled.content_margin_top = 6
	filled.content_margin_bottom = 6
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_constant("center_grabber", "HSlider", 1)


func _checkbutton(theme: Theme) -> void:
	var normal := _flat(Color("f4e8cd"), 20, OUTLINE, 4)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("fff4dd")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("e8d9b8")
	var focus := _flat(Color(0, 0, 0, 0), 20, Color("2a8fc4"), 3)
	focus.draw_center = false
	theme.set_stylebox("normal", "CheckButton", normal)
	theme.set_stylebox("hover", "CheckButton", hover)
	theme.set_stylebox("pressed", "CheckButton", pressed)
	theme.set_stylebox("focus", "CheckButton", focus)
	theme.set_constant("outline_size", "CheckButton", 0)
	theme.set_color("font_color", "CheckButton", INK)
	theme.set_color("font_hover_color", "CheckButton", INK)
	theme.set_color("font_pressed_color", "CheckButton", INK)
	theme.set_font_size("font_size", "CheckButton", 18)
