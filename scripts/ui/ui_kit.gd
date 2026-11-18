extends Node
## One source of truth for menu sizing, focus feedback and type tokens.
## Any normal Button/LineEdit that enters the tree is snapped to the same height
## and type scale, so screens cannot drift apart again. Large preview cards
## (>= 120 px tall) are left alone.
##
## The system is deliberately small: one corner radius (16), one spacing scale
## (8 / 16 / 24), one accent (yellow) and three text sizes (title, label,
## caption). Pages group content with gaps and tint blocks, never with rules or
## boxed-in rows.
##
## Controls are keyboard/gamepad focusable. This kit installs one bright,
## high-contrast focus ring (a yellow outline with a dark halo) so the engine's
## focus navigation and MenuNav's explicit neighbour map are always visible,
## including on yellow candy buttons where the old white ring disappeared.

const BUTTON_HEIGHT: float = 56.0
const BUTTON_MIN_HEIGHT: float = 40.0 ## Floor: below this an action reads as a tag.
const BUTTON_MAX_WIDTH: float = 440.0 ## Cap: a longer label shrinks instead of widening.
const LABEL_MIN_FONT: int = 13 ## Floor for the shrink-to-fit type ramp.
const FIELD_HEIGHT: float = 48.0
const BUTTON_FONT: int = 20
const FIELD_FONT: int = 18
const CORNER_RADIUS: int = 16 ## One radius for every tile, control and row.
const SPACING: int = 16 ## Gap between form rows / screen blocks.
const SPACING_TIGHT: int = 8 ## Gap inside one row or card.
const SPACING_WIDE: int = 24 ## Gap between a page and the next big block.
const CAPTION_SIZE: int = 15 ## Secondary explanation line.
const TITLE_SIZE: int = 40 ## The one page-title size.
const TILE_MIN_WIDTH: float = 68.0 ## Equal square tiles in an option strip.
const SCREEN_WIDTH: float = 1280.0 ## Design box every menu must fit inside.
const SCREEN_HEIGHT: float = 720.0
const SCREEN_MARGIN: float = 24.0 ## Safe gap between a control and the design edge.
const CONTENT_WIDTH: float = 1000.0 ## Widest page column allowed at the design box.
const FOCUS_RING: Color = Color("ffd22e")
const FOCUS_RING_DARK: Color = Color("1e1b3a")
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const OPTION_TILES: String = "res://scripts/ui/pill_cycler.gd"
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
	# Small colour swatches and custom LineEdits opt out of size tokens but still need a ring.
	if node.has_meta("skip_kit"):
		if node is Button:
			apply_focus_ring(node as Control, _corner_radius_of(node as Control))
		elif node is LineEdit:
			var line := node as Control
			var line_normal: StyleBox = line.get_theme_stylebox("normal")
			var radius: int = 14
			if line_normal is StyleBoxFlat and (line_normal as StyleBoxFlat).corner_radius_top_left > 0:
				radius = (line_normal as StyleBoxFlat).corner_radius_top_left
			apply_focus_ring(line, radius)
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
			# Every action label is optically centred in its pill unless a list
			# or team row explicitly preserves left alignment via keep_align.
			if not bool(button.get_meta("keep_align", false)):
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
	style.shadow_color = Color(0.06, 0.05, 0.14, 0.72)
	style.shadow_size = 4
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


func tile(text: String, fill: Color, height: float = BUTTON_HEIGHT,
		font_size: int = BUTTON_FONT) -> Button:
	## Shared action tile: the candy look, one corner radius and one font size.
	## Screens pass the accent; the shadow, border and focus ring are the kit's.
	## The height is floored so no screen can author an unclickable 20 px pill,
	## and the authored font size is remembered for fit_button()'s shrink ramp.
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", fill)
	button.set("corner_radius", CORNER_RADIUS)
	button.text = text
	button.custom_minimum_size = Vector2(0, maxf(height, BUTTON_MIN_HEIGHT))
	button.set_meta("kit_font_size", font_size)
	button.add_theme_font_size_override("font_size", font_size)
	return button


func cap_button(button: Button, width: float = BUTTON_MAX_WIDTH) -> void:
	## Give an action pill a real width and hold it there: the kit floor (68)
	## at one end, BUTTON_MAX_WIDTH at the other. Anything wider is a card or a
	## bar, not a pill; long labels shrink with fit_button() instead.
	if button == null or not is_instance_valid(button):
		return
	button.custom_minimum_size.x = clampf(width, TILE_MIN_WIDTH, BUTTON_MAX_WIDTH)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func fit_button(button: Button, max_width: float = BUTTON_MAX_WIDTH,
		min_font: int = LABEL_MIN_FONT) -> void:
	## Shrink one long label to fit its pill instead of letting the pill grow.
	## Measured only when the text or the cap changes, never per frame.
	if button == null or not is_instance_valid(button) or button.text.is_empty():
		return
	var cap: float = clampf(max_width, 1.0, CONTENT_WIDTH)
	var padding: float = 0.0
	var normal: StyleBox = button.get_theme_stylebox("normal")
	if normal != null:
		padding = normal.get_minimum_size().x
	var available: float = maxf(cap - padding - 6.0, 16.0)
	var authored: int = _authored_font(button)
	var fitted: int = fitted_font_size(button.get_theme_font("font"), button.text,
		authored, available, min_font)
	button.add_theme_font_size_override("font_size", fitted)


func fitted_font_size(font: Font, text: String, base_size: int, available: float,
		min_font: int = LABEL_MIN_FONT) -> int:
	## Largest size in [min_font, base_size] whose run of `text` fits the width.
	if font == null or text.is_empty():
		return maxi(base_size, min_font)
	var font_size: int = maxi(base_size, min_font)
	while font_size > min_font:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size).x <= available:
			break
		font_size -= 1
	return font_size


func _authored_font(button: Button) -> int:
	if not button.has_meta("kit_font_size"):
		button.set_meta("kit_font_size", maxi(button.get_theme_font_size("font_size"), 1))
	return int(button.get_meta("kit_font_size"))


func segmented(labels: PackedStringArray, values: Array, start_index: int = 0,
		tile_width: float = TILE_MIN_WIDTH, height: float = 48.0) -> Button:
	## Equal square tiles side by side for a small discrete choice. One focus
	## stop: left/right changes the value, Enter steps, clicking picks a tile.
	## The selected tile uses the shared yellow accent, like every other
	## selected state in the UI.
	var button := Button.new()
	button.set_script(load(OPTION_TILES))
	button.set("fill_color", UiPalette.YELLOW)
	button.set("tile_min_width", tile_width)
	button.set("corner_radius", CORNER_RADIUS)
	button.custom_minimum_size = Vector2(labels.size() * tile_width, height)
	button.add_theme_font_size_override("font_size", 17)
	button.call("configure", labels, values, start_index)
	return button


func flat_card(bg: Color, radius: int = CORNER_RADIUS) -> StyleBoxFlat:
	## Borderless block used for grouped content. A gap plus a tint groups a
	## section; a 1 px rule never does.
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style


func report_screen(root: Control, label: String) -> void:
	## Verification hook, enabled with CART_UI_MEASURE=1: prints the widest
	## button, the rightmost button edge and any button that leaves the
	## 1280x720 safe box. Runs once, three frames after the screen is built.
	if root == null or not is_instance_valid(root):
		return
	for _frame in 18:
		await get_tree().process_frame
	var report: Dictionary = {"count": 0, "widest": "", "width": 0.0,
		"right": 0.0, "bottom": 0.0, "outside": [], "rects": []}
	_measure_buttons(root, report)
	var viewport: Vector2 = root.get_viewport_rect().size
	print("UI_MEASURE %s viewport=%.0fx%.0f root=%.0fx%.0f buttons=%d widest='%s' width=%.1f right=%.1f bottom=%.1f"
		% [label, viewport.x, viewport.y, root.size.x, root.size.y,
		int(report["count"]), str(report["widest"]), float(report["width"]),
		float(report["right"]), float(report["bottom"])])
	print("UI_MEASURE_RECTS %s %s" % [label, ", ".join(report["rects"] as Array)])
	var outside: Array = report["outside"]
	print("UI_MEASURE_OUTSIDE %s %s" % [label,
		", ".join(outside) if not outside.is_empty() else "none"])


func _measure_buttons(node: Node, report: Dictionary) -> void:
	## Walks live controls, so the numbers are the laid-out rectangles the
	## player actually sees, not the authored minimum sizes.
	if node is Button and (node as Button).is_visible_in_tree():
		var rect: Rect2 = (node as Control).get_global_rect()
		var button := node as Button
		var tag: String = button.text if not button.text.is_empty() else button.name
		report["count"] = int(report["count"]) + 1
		if rect.size.x > float(report["width"]):
			report["width"] = rect.size.x
			report["widest"] = tag
		report["right"] = maxf(float(report["right"]), rect.end.x)
		report["bottom"] = maxf(float(report["bottom"]), rect.end.y)
		var rects: Array = report["rects"]
		if rects.size() < 14:
			rects.append("%s=%.0f,%.0f %.0fx%.0f" % [tag, rect.position.x,
				rect.position.y, rect.size.x, rect.size.y])
		var left: float = rect.position.x
		var top: float = rect.position.y
		if left < SCREEN_MARGIN or top < SCREEN_MARGIN \
				or rect.end.x > SCREEN_WIDTH - SCREEN_MARGIN \
				or rect.end.y > SCREEN_HEIGHT - SCREEN_MARGIN:
			var outside: Array = report["outside"]
			outside.append("%s@%.0f,%.0f-%.0f,%.0f" % [tag, left, top,
				rect.end.x, rect.end.y])
	for child: Node in node.get_children():
		_measure_buttons(child, report)
