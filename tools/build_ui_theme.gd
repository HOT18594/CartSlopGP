extends SceneTree
## Builds res://assets/ui/theme.tres from the palette below.
## Run:  godot --headless --path . --script tools/build_ui_theme.gd
## Re-run after changing colours or fonts; scenes only reference the Theme.

const BG_TOP := Color("120f24")
const BG_BOTTOM := Color("2a1a3d")
const PANEL := Color("1b2140")
const PANEL_SOFT := Color("232a4d")
const OUTLINE := Color("090c18")
const TEXT := Color("fff6e5")
const TEXT_DIM := Color("b9b2c9")
const ACCENT := Color("ffc93c")
const ACCENT_DARK := Color("d99a12")
const CORAL := Color("ff6b57")


func _init() -> void:
	# Static instances of Fredoka (see tools/README-fonts.md): Godot ignores the
	# variable weight axis, so the weights are baked with fontTools instead.
	var body_medium: FontFile = load("res://assets/ui/fonts/Fredoka-Medium.ttf")
	var body_semibold: FontFile = load("res://assets/ui/fonts/Fredoka-Bold.ttf")
	var display: FontFile = load("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")
	if body_medium == null or body_semibold == null or display == null:
		push_error("Missing UI fonts")
		quit(1)
		return

	var theme := Theme.new()
	theme.default_font = body_medium
	theme.default_font_size = 22

	_label(theme, TEXT)
	_button(theme, body_semibold, display)
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


func _label(theme: Theme, color: Color) -> void:
	theme.set_color("font_color", "Label", color)
	theme.set_color("font_shadow_color", "Label", Color(OUTLINE, 0.55))
	theme.set_constant("shadow_offset_x", "Label", 0)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_constant("outline_size", "Label", 0)


func _button(theme: Theme, body: Font, display: Font) -> void:
	theme.set_font("font", "Button", body)
	theme.set_font_size("font_size", "Button", 28)

	var normal := _flat(PANEL_SOFT, 18, OUTLINE, 4)
	normal.content_margin_left = 28
	normal.content_margin_right = 28
	normal.content_margin_top = 14
	normal.content_margin_bottom = 14
	normal.shadow_color = Color(0, 0, 0, 0.35)
	normal.shadow_size = 6
	normal.shadow_offset = Vector2(0, 6)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("2f3a68")
	hover.border_color = ACCENT

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("141a30")
	pressed.border_color = ACCENT_DARK
	pressed.shadow_size = 2
	pressed.shadow_offset = Vector2(0, 2)

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("1a1f33")
	disabled.border_color = Color("2c3350")
	disabled.shadow_size = 0

	var focus := _flat(Color(0, 0, 0, 0), 18, ACCENT, 3)
	focus.draw_center = false

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", ACCENT)
	theme.set_color("font_focus_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", Color("6f7690"))
	theme.set_color("font_outline_color", "Button", OUTLINE)
	theme.set_constant("outline_size", "Button", 0)

	# Title variation: declare the base type so Label properties still resolve.
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", display)
	theme.set_font_size("font_size", "TitleLabel", 96)
	theme.set_color("font_color", "TitleLabel", TEXT)


func _panel(theme: Theme) -> void:
	var panel := _flat(Color(PANEL, 0.94), 26, OUTLINE, 4)
	panel.content_margin_left = 34
	panel.content_margin_right = 34
	panel.content_margin_top = 28
	panel.content_margin_bottom = 28
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 14
	panel.shadow_offset = Vector2(0, 10)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)


func _progress(theme: Theme) -> void:
	var background := _flat(Color(OUTLINE, 0.85), 12, Color("343c60"), 3)
	background.content_margin_top = 0
	background.content_margin_bottom = 0

	var fill := _flat(ACCENT, 12, ACCENT_DARK, 3)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0

	theme.set_stylebox("background", "ProgressBar", background)
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_color("font_color", "ProgressBar", OUTLINE)


func _slider(theme: Theme) -> void:
	var track := _flat(Color("0d1224"), 8, OUTLINE, 3)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var filled := _flat(ACCENT, 8, ACCENT_DARK, 3)
	filled.content_margin_top = 6
	filled.content_margin_bottom = 6
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_constant("center_grabber", "HSlider", 1)


func _checkbutton(theme: Theme) -> void:
	theme.set_color("font_color", "CheckButton", TEXT)
	theme.set_color("font_hover_color", "CheckButton", Color.WHITE)
	theme.set_color("font_pressed_color", "CheckButton", ACCENT)
	theme.set_font_size("font_size", "CheckButton", 22)
