extends Node
## One source of truth for menu sizing, focus feedback and type tokens.
## Any normal Button/LineEdit that enters the tree is snapped to the same height
## and type scale, so screens cannot drift apart again. Large preview cards
## (>= 120 px tall) are left alone.
##
## The system is deliberately small: one corner radius (16), one spacing scale
## (10 / 14 / 18 / 28), one accent (yellow) and three text sizes (title, label,
## caption). Pages group content with gaps and tint blocks, never with rules or
## boxed-in rows. Every modal shell and result card is built from
## `modal_panel()` / `row_style()` / `banner_style()` so screens cannot drift
## apart again.
##
## Controls are keyboard/gamepad focusable. This kit installs one bright,
## high-contrast focus ring (a yellow outline with a dark halo) so the engine's
## focus navigation and MenuNav's explicit neighbour map are always visible,
## including on yellow candy buttons where the old white ring disappeared.
##
## Every LineEdit that enters the tree is also snapped to the shared text-cursor
## contract in `style_text_input()`: a 0.5 s blink (a caret that never blinks
## reads as frozen text) and a caret colour picked for real contrast against the
## field's own fill. The old shared override used `FOCUS_RING_DARK` (#1e1b3a),
## which is ~1.3:1 on the dark input wells — effectively an invisible caret.

const BUTTON_HEIGHT: float = 60.0
const BUTTON_MIN_HEIGHT: float = 44.0 ## Floor: roomy enough for crisp slanted typography.
const BUTTON_MAX_WIDTH: float = 460.0 ## Cap: a longer label shrinks instead of widening.
const LABEL_MIN_FONT: int = 14 ## Floor for the shrink-to-fit type ramp.
const FIELD_HEIGHT: float = 50.0
const BUTTON_FONT: int = 22
const FIELD_FONT: int = 19
const CORNER_RADIUS: int = 16 ## One radius for every tile, control and row.
const SPACING: int = 18 ## Gap between form rows / screen blocks.
const SPACING_TIGHT: int = 10 ## Gap inside one row or card.
const SPACING_MED: int = 14 ## Gap between related rows inside one section.
const SPACING_WIDE: int = 28 ## Gap between a page and the next big block.
const MODAL_PAD_H: float = 36.0 ## Inner horizontal padding of a modal shell.
const MODAL_PAD_V: float = 26.0 ## Inner vertical padding of a modal shell.
const MODAL_MARGIN: float = 44.0 ## Safe inset around a centered modal page.
const COMPACT_FONT: int = 18 ## Font size for secondary / compact action pills.
const TITLE_OUTLINE: int = 8 ## Ink outline on the one page-title style.
const CAPTION_SIZE: int = 15 ## Secondary explanation line.
const TITLE_SIZE: int = 40 ## The one page-title size.
const TILE_MIN_WIDTH: float = 76.0 ## Equal square tiles in an option strip.
const SCREEN_WIDTH: float = 1280.0 ## Design box every menu must fit inside.
const SCREEN_HEIGHT: float = 720.0
const SCREEN_MARGIN: float = 28.0 ## Safe gap between a control and the design edge.
const CONTENT_WIDTH: float = 1000.0 ## Widest page column allowed at the design box.
const FOCUS_RING: Color = Color("ffd22e")
const FOCUS_RING_DARK: Color = Color("1e1b3a")
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const OPTION_TILES: String = "res://scripts/ui/pill_cycler.gd"
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
## Text-cursor contract (see the file docstring): 0.5 s = two blinks a second,
## fast enough to read as a live cursor and slow enough to stay calm.
const CARET_BLINK_SECONDS: float = 0.5
## Caret on a dark input well. UiPalette.YELLOW is ~13:1 against FIELD_FILL
## (#0d1022) and is visibly different from the cream/white field text.
const CARET_ON_DARK: Color = UiPalette.YELLOW
## Caret on a light field (no current screen has one, but the helper must stay
## correct if a theme ever inverts a field): ink on cream.
const CARET_ON_LIGHT: Color = UiPalette.INK
const CARET_LIGHT_LUMINANCE: float = 0.35 ## Above this the field counts as light.
const SFX_HOVER_PATH: String = "res://assets/audio/sfx/ui/ui_hover.wav"
const SFX_CLICK_PATH: String = "res://assets/audio/sfx/ui/ui_click.wav"
const SFX_CONFIRM_PATH: String = "res://assets/audio/sfx/ui/ui_confirm.ogg"

var _focus_styles: Dictionary = {} ## corner radius -> StyleBoxFlat
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cursor: int = 0
var _sfx_hover: AudioStream
var _sfx_click: AudioStream
var _sfx_confirm: AudioStream
var _last_hover_ms: int = -1000
var _boot_ms: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_boot_ms = Time.get_ticks_msec()
	_init_ui_sfx()
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_normalize_tree", get_tree().root)


func _init_ui_sfx() -> void:
	if ResourceLoader.exists(SFX_HOVER_PATH):
		_sfx_hover = load(SFX_HOVER_PATH) as AudioStream
	if ResourceLoader.exists(SFX_CLICK_PATH):
		_sfx_click = load(SFX_CLICK_PATH) as AudioStream
	if ResourceLoader.exists(SFX_CONFIRM_PATH):
		_sfx_confirm = load(SFX_CONFIRM_PATH) as AudioStream
	for _i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx_players.append(p)


func _play_sfx(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		return
	var p: AudioStreamPlayer = _sfx_players[_sfx_cursor % _sfx_players.size()]
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	if not is_instance_valid(p):
		return
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") != -1 else "Master"
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func play_hover() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _boot_ms < 250 or now - _last_hover_ms < 42:
		return
	_last_hover_ms = now
	_play_sfx(_sfx_hover, -14.0, randf_range(0.97, 1.06))


func play_click() -> void:
	_play_sfx(_sfx_click, -8.5, randf_range(0.98, 1.04))


func play_confirm() -> void:
	_play_sfx(_sfx_confirm if _sfx_confirm != null else _sfx_click, -7.0, 1.02)


func play_back() -> void:
	_play_sfx(_sfx_click, -9.5, 0.78)


func wire_button_sfx(button: BaseButton) -> void:
	if button == null or not is_instance_valid(button) or button.has_meta("ui_sfx_wired"):
		return
	button.set_meta("ui_sfx_wired", true)
	button.mouse_entered.connect(func() -> void:
		if is_instance_valid(button) and not button.disabled:
			play_hover())
	button.pressed.connect(func() -> void:
		if not is_instance_valid(button):
			return
		if button.has_meta("sfx_confirm"):
			play_confirm()
			return
		var label_up: String = ""
		if button is Button:
			label_up = (button as Button).text.strip_edges().to_upper()
		if label_up in ["BACK", "CANCEL", "QUIT", "CLOSE", "LEAVE ROOM", "QUIT TO MENU"]:
			play_back()
		elif label_up in ["PLAY", "SOLO", "MULTIPLAYER", "START", "START MATCH", "DRIVE", "LET'S DRIVE", "SAVE & RETURN", "LAUNCH"]:
			play_confirm()
		else:
			play_click())


func consume_input(node: Node) -> void:
	## Safe wrapper for Viewport.set_input_as_handled(). Calling get_viewport()
	## after a synchronous scene change or tree exit returns null, which in
	## Godot 4.7 release builds triggers a null-pointer deref at offset 0x450.
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var vp: Viewport = node.get_viewport()
	if vp != null:
		vp.set_input_as_handled()


func slanted_panel(bg: Color = Color(0.064, 0.074, 0.162, 0.94),
		border: Color = Color(0.24, 0.80, 0.96, 0.48),
		skew_x: float = 0.045, border_w: int = 4, radius: int = 6,
		pad_h: float = 34.0, pad_v: float = 24.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_w)
	style.set_corner_radius_all(radius)
	style.skew = Vector2(skew_x, 0.0)
	style.content_margin_left = pad_h
	style.content_margin_right = pad_h
	style.content_margin_top = pad_v
	style.content_margin_bottom = pad_v
	style.shadow_color = Color(0.02, 0.02, 0.08, 0.68)
	style.shadow_size = 12
	style.shadow_offset = Vector2(5, 10)
	style.anti_aliasing = true
	return style


func slanted_card(bg: Color = Color(0.095, 0.112, 0.228, 0.92),
		border: Color = Color(0.32, 0.78, 0.95, 0.28),
		skew_x: float = 0.11, border_w: int = 2, radius: int = 5,
		pad_h: float = 16.0, pad_v: float = 12.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_w)
	style.set_corner_radius_all(radius)
	style.skew = Vector2(skew_x, 0.0)
	style.content_margin_left = pad_h
	style.content_margin_right = pad_h
	style.content_margin_top = pad_v
	style.content_margin_bottom = pad_v
	style.shadow_color = Color(0.02, 0.02, 0.08, 0.45)
	style.shadow_size = 5
	style.shadow_offset = Vector2(3, 4)
	style.anti_aliasing = true
	return style


func glass_panel(bg: Color = UiPalette.SURFACE_GLASS, border: Color = UiPalette.OUTLINE,
		radius: int = 6, border_w: int = 4) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_w)
	style.set_corner_radius_all(radius)
	style.skew = Vector2(0.045, 0.0)
	style.shadow_color = Color(0.03, 0.03, 0.10, 0.58)
	style.shadow_size = 10
	style.shadow_offset = Vector2(4, 8)
	style.anti_aliasing = true
	return style


func modal_panel(pad_h: float = MODAL_PAD_H, pad_v: float = MODAL_PAD_V,
		skew: float = 0.045, border_w: int = 4) -> StyleBoxFlat:
	## The one dark-glass slanted modal shell: canonical fill, cyan glass rim and
	## the shared drop shadow. Every modal and page panel calls this instead of
	## re-typing the same six magic numbers.
	return slanted_panel(UiPalette.SURFACE_MODAL, UiPalette.MODAL_BORDER, skew,
		border_w, 6, pad_h, pad_v)


func modal_shell_style(pad_h: float = MODAL_PAD_H + 6.0,
		pad_v: float = MODAL_PAD_V + 4.0) -> StyleBoxFlat:
	## Transparent content-padding box for a PanelContainer whose plate is drawn
	## by scripts/ui/slanted_shell.gd (Pause / Settings / result cards).
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.bg_color = Color(0, 0, 0, 0)
	style.content_margin_left = pad_h
	style.content_margin_right = pad_h
	style.content_margin_top = pad_v
	style.content_margin_bottom = pad_v + 4.0
	return style


func apply_scrim(rect: ColorRect) -> void:
	## One dim colour for every modal / result card; never hand-pick a scrim.
	if rect == null or not is_instance_valid(rect):
		return
	rect.color = UiPalette.SCRIM
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func row_style(local: bool = false, border: Color = UiPalette.ROW_BORDER,
		border_w: int = 1) -> StyleBoxFlat:
	## One list / standings / telemetry row plate: slanted dark glass, cyan rim
	## when the row belongs to the local player.
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.SURFACE_ROW_LOCAL if local else UiPalette.SURFACE_ROW
	style.border_color = UiPalette.CYAN if local else border
	style.set_border_width_all(2 if local else border_w)
	style.set_corner_radius_all(5)
	style.skew = Vector2(0.14, 0.0)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	style.anti_aliasing = true
	return style


func banner_style(color: Color) -> StyleBoxFlat:
	## Accent banner behind a result / page headline: accent plate, ink border
	## and the same 0.14 slant as the button family.
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = UiPalette.OUTLINE
	style.set_border_width_all(3)
	style.set_corner_radius_all(5)
	style.skew = Vector2(0.14, 0.0)
	style.content_margin_left = float(SPACING)
	style.content_margin_right = float(SPACING)
	style.content_margin_top = float(SPACING_TIGHT)
	style.content_margin_bottom = float(SPACING_TIGHT)
	style.anti_aliasing = true
	return style


func page_title(text_val: String, color: Color = UiPalette.YELLOW) -> Label:
	## The one page-title style: display font, TITLE_SIZE, ink outline.
	var node := label(text_val, TITLE_SIZE, color)
	node.theme_type_variation = &"TitleLabel"
	node.add_theme_color_override("font_outline_color", UiPalette.OUTLINE)
	node.add_theme_constant_override("outline_size", TITLE_OUTLINE)
	return node


func compact_button(text_val: String, fill: Color, height: float = 48.0) -> Button:
	## Secondary / compact action pill (Back, Refresh, All Versions...).
	return tile(text_val, fill, height, COMPACT_FONT)


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
	if node is BaseButton:
		wire_button_sfx(node as BaseButton)
	if node is Button or node is CheckButton:
		var focusable := node as Control
		if not focusable.has_meta("nav_skip"):
			focusable.focus_mode = Control.FOCUS_ALL
	# Controls that draw their own slanted parallelogram focus outline opt out of
	# the rounded-rectangle focus ring completely.
	if node.has_meta("custom_focus"):
		if node is Control:
			(node as Control).add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		return
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
		style_text_input(control as LineEdit)


func style_text_input(field: LineEdit) -> void:
	## One caret policy for every text input in the game. Screens that build
	## their own LineEdit (lobby name/join, room-browser search, the meadow
	## waiting room) get this through `_style_node`, so nobody has to remember a
	## per-screen caret token. It is safe to call again after a screen re-styles
	## its field: the colour is re-derived from that field's own background.
	if field == null or not is_instance_valid(field):
		return
	field.caret_blink = true ## Godot defaults to true, but a screen could disable it.
	field.caret_blink_interval = CARET_BLINK_SECONDS
	field.add_theme_color_override("caret_color", caret_color_for(field))
	field.add_theme_color_override("selection_color", Color(FOCUS_RING, 0.35))


func caret_color_for(field: LineEdit) -> Color:
	## Crisp caret against the field's OWN fill: bright yellow on the dark input
	## wells, ink if a screen ever inverts the well to a light colour.
	if field == null or not is_instance_valid(field):
		return CARET_ON_DARK
	return CARET_ON_LIGHT if _relative_luminance(field_background(field)) \
		> CARET_LIGHT_LUMINANCE else CARET_ON_DARK


func field_background(field: LineEdit) -> Color:
	## The fill the text actually sits on (ignoring alpha, the window behind the
	## menu is always darker than the field itself).
	if field == null or not is_instance_valid(field):
		return UiPalette.FIELD_FILL
	var box: StyleBox = field.get_theme_stylebox("normal")
	if box is StyleBoxFlat:
		var flat := box as StyleBoxFlat
		return Color(flat.bg_color.r, flat.bg_color.g, flat.bg_color.b, 1.0)
	return UiPalette.FIELD_FILL


func _relative_luminance(color: Color) -> float:
	## WCAG relative luminance, used only to pick a caret colour per field.
	var channels: Array[float] = [color.r, color.g, color.b]
	for index in 3:
		var value: float = channels[index]
		channels[index] = value / 12.92 if value <= 0.03928 \
			else pow((value + 0.055) / 1.055, 2.4)
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


func _focus_style(radius: int) -> StyleBoxFlat:
	if _focus_styles.has(radius):
		return _focus_styles[radius] as StyleBoxFlat
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = FOCUS_RING
	style.set_border_width_all(3)
	style.set_corner_radius_all(mini(radius, 8))
	style.skew = Vector2(0.11, 0.0)
	# Matching content margins keep a focused LineEdit's text in the same spot;
	# Button ignores focus-style margins for layout.
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	# The stylebox is grown a few pixels so the ring lines up outside the
	# control's own border instead of eating into the label.
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
	var available: float = maxf(cap - padding - 12.0, 16.0)
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
