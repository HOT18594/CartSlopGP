extends Control
## Reusable custom-drawn dark-glass slanted shell: skewed parallelogram plate,
## hard drop shadow, top gloss band, ink outline and a cyan inner hairline.
##
## Screens drop this in as the first child of a PanelContainer whose own panel
## style is `UiKit.modal_shell_style()` (transparent padding box). The shell
## paints around the content rect using its exported padding, so every modal in
## the game shares one shell implementation instead of three near-identical
## copies (Pause, Settings, result cards).
##
## Colours come from UiPalette so the black-slanted theme cannot drift.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")

@export var skew_px: float = 20.0 ## Horizontal slant of the plate in px.
@export var pad_x: float = 28.0 ## How far the plate overshoots the content rect.
@export var pad_y: float = 22.0
@export var plate_color: Color = UiPalette.SHELL_FILL
@export var shadow_color: Color = UiPalette.MODAL_SHADE
@export var rim_color: Color = UiPalette.SHELL_RIM
@export var gloss_color: Color = UiPalette.SHELL_GLOSS
@export var gloss_height: float = 34.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 16.0 or h < 16.0:
		return
	var sk: float = skew_px
	var x0: float = -pad_x - sk * 0.5
	var y0: float = -pad_y
	var bw: float = w + pad_x * 2.0
	var bh: float = h + pad_y * 2.0
	var pts := PackedVector2Array([
		Vector2(x0 + sk, y0),
		Vector2(x0 + sk + bw, y0),
		Vector2(x0 + bw, y0 + bh),
		Vector2(x0, y0 + bh),
	])
	var shadow := PackedVector2Array([
		pts[0] + Vector2(6.0, 9.0), pts[1] + Vector2(6.0, 9.0),
		pts[2] + Vector2(6.0, 9.0), pts[3] + Vector2(6.0, 9.0),
	])
	draw_colored_polygon(shadow, shadow_color)
	draw_colored_polygon(pts, plate_color)
	# Subtle inner top glass highlight band.
	var band: float = clampf(gloss_height / maxf(bh, 1.0), 0.0, 1.0)
	var gloss := PackedVector2Array([
		pts[0],
		pts[1],
		pts[1].lerp(pts[2], band),
		pts[0].lerp(pts[3], band),
	])
	draw_colored_polygon(gloss, gloss_color)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, UiPalette.OUTLINE, 4.5, true)
	var inner := PackedVector2Array([
		pts[0] + Vector2(3.0, 3.0),
		pts[1] + Vector2(-4.0, 3.0),
		pts[2] + Vector2(-3.0, -3.0),
		pts[3] + Vector2(4.0, -3.0),
		pts[0] + Vector2(3.0, 3.0),
	])
	draw_polyline(inner, rim_color, 1.6, true)
