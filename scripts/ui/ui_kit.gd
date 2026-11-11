extends Node
## One source of truth for menu sizing, focus feedback and small type tokens.
## Any normal Button/LineEdit that enters the tree is snapped to the same height
## and type scale, so screens cannot drift apart again. Large preview cards
## (>= 120 px tall) are left alone.
##
## Controls are keyboard/gamepad focusable. This kit installs one bright,
## high-contrast focus ring (a yellow outline with a dark halo) so the engine's
## focus navigation and MenuNav's explicit neighbour map are always visible,
## including on yellow candy buttons where the old white ring disappeared.

const BUTTON_HEIGHT: float = 54.0
const FIELD_HEIGHT: float = 50.0
const BUTTON_FONT: int = 22
const FIELD_FONT: int = 18
const CORNER_RADIUS: int = 24
const SPACING: int = 14 ## Gap between form rows / screen blocks.
const SPACING_TIGHT: int = 8 ## Gap inside one row or card.
const CAPTION_SIZE: int = 14 ## Secondary explanation line.
const FOCUS_RING: Color = Color("ffd22e")
const FOCUS_RING_DARK: Color = Color("1e1b3a")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

var _focus_styles: Dictionary = {} ## corner radius -> StyleBoxFlat


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_normalize_tree", get_tree().root)


func _on_node_added(node: Node) -> void:
	if node is Button or node is LineEdit or node is CheckButton:
		call_deferred("_style_node", node)


func _normalize_tree(root: Node) -> void:
	_style_node(root)
	for child: Node in root.get_children():
		_normalize_tree(child)


func _style_node(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is Button or node is CheckButton:
		var focusable := node as Control
		if not focusable.has_meta("nav_skip"):
			focusable.focus_mode = Control.FOCUS_ALL
	# Small colour swatches opt out of the size tokens but still need a ring.
	if node.has_meta("skip_kit"):
		if node is Button:
			apply_focus_ring(node as Control, _corner_radius_of(node as Control))
		return
	if node is OptionButton or node is MenuButton:
		return
	if node is CheckButton:
		var toggle := node as CheckButton
		toggle.custom_minimum_size.y = BUTTON_HEIGHT
		toggle.add_theme_font_size_override("font_size", 18)
		toggle.alignment = HORIZONTAL_ALIGNMENT_CENTER
		apply_focus_ring(toggle, CORNER_RADIUS)
		return
	if node is Button:
		var button := node as Button
		# Minigame preview cards are Buttons too; keep their card size.
		if button.custom_minimum_size.y < 120.0:
			# Floor, not override: a screen that authored a 78 px PLAY button or
			# a 28 px RESUME keeps its hierarchy. Only buttons with no size/type
			# set fall back to the shared token.
			if button.custom_minimum_size.y <= 0.0:
				button.custom_minimum_size.y = BUTTON_HEIGHT
			if not button.has_theme_font_size_override("font_size"):
				button.add_theme_font_size_override("font_size", BUTTON_FONT)
			# Every action label is optically centred in its pill. The styleboxes
			# use symmetric top/bottom content margins, so vertical centring
			# comes from Button itself; this pins the horizontal side.
			button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		apply_focus_ring(button, _corner_radius_of(button))
	elif node is LineEdit:
		var field := node as LineEdit
		field.custom_minimum_size.y = FIELD_HEIGHT
		field.add_theme_font_size_override("font_size", FIELD_FONT)
		apply_focus_ring(field, 14)


func apply_focus_ring(control: Control, corner_radius: int = CORNER_RADIUS) -> void:
	## Install the shared focus ring. Safe to call again when a control changes
	## its own corner radius; the stylebox is cached per radius.
	if control == null or not is_instance_valid(control):
		return
	var radius: int = clampi(corner_radius, 2, 40)
	control.add_theme_stylebox_override("focus", _focus_style(radius))
	if control is LineEdit:
		control.add_theme_color_override("caret_color", FOCUS_RING_DARK)
		control.add_theme_color_override("selection_color", Color(FOCUS_RING, 0.35))


func _focus_style(radius: int) -> StyleBoxFlat:
	if _focus_styles.has(radius):
		return _focus_styles[radius] as StyleBoxFlat
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = FOCUS_RING
	style.set_border_width_all(4)
	style.set_corner_radius_all(radius + 4)
	# Matching content margins keep a focused LineEdit's text in the same spot;
	# Button ignores focus-style margins for layout.
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	# The stylebox is grown a few pixels so the ring lines up outside the
	# control's own candy border instead of eating into the label.
	style.expand_margin_left = 3.0
	style.expand_margin_top = 3.0
	style.expand_margin_right = 3.0
	style.expand_margin_bottom = 3.0
	style.shadow_color = Color(0.06, 0.05, 0.12, 0.65)
	style.shadow_size = 2
	style.shadow_offset = Vector2.ZERO
	style.anti_aliasing = true
	_focus_styles[radius] = style
	return style


func _corner_radius_of(control: Control) -> int:
	var normal: StyleBox = control.get_theme_stylebox("normal")
	if normal is StyleBoxFlat:
		var flat := normal as StyleBoxFlat
		if flat.corner_radius_top_left > 0:
			return flat.corner_radius_top_left
	return CORNER_RADIUS


func label(text: String, font_size: int, color: Color) -> Label:
	## Shared non-interactive text used by menu rows and captions.
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func caption(text: String) -> Label:
	## Quiet one-line explanation under a setting or section heading.
	var node := label(text, CAPTION_SIZE, UiPalette.MUTED)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node
