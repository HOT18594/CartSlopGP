extends SceneTree
## WS2 headless checks: main-menu hero-rail structure + Mapmaker teaser contract,
## the text-input caret inventory and the responsive rail metrics.
##
## Exit code = number of failures (same contract as the other suites).
## Run from the workspace root:
##   downloads/godot_editor/Godot_v4.7.2-stable_win64_console.exe --headless \
##     --path godot_project --script res://scripts/ui/ws2_ui_checks.gd
## Add CSGP_WS2_METRICS=1 to also dump play/minigames/garage panel metrics.
##
## This lives under scripts/ui/ (not scripts/tools/) because WS2 owns the UI
## scope; it is the UI workstream's own verification harness, next to
## ui_layout_audit.gd and ws4_ui_smoke.gd.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const ROOM_BROWSER_SCENE: String = "res://scenes/ui/room_browser.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MEADOW_LOBBY_SCENE: String = "res://scenes/minigames/meadow_lobby.tscn"
const MAPMAKER_MESSAGE: String = "COMING SOON :D"

const VIEWPORTS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1080), ## Ultrawide: 21:9, design box grows horizontally.
]

const EXPECTED_HERO_LABELS: Array[String] = [
	"SINGLEPLAYER", "MULTIPLAYER", "MAPMAKER", "GARAGE",
]
const HERO_PRIMARY_HEIGHT: float = 70.0
const HERO_TILE_SLACK: float = 4.0
const CARET_BLINK_SECONDS: float = 0.5
const CARET_BLINK_TOLERANCE: float = 0.05
const MIN_CARET_CONTRAST: float = 4.5 ## WCAG AA large-text / UI-component floor.
const MIN_CARET_FONT_DISTANCE: float = 0.2 ## Caret must not melt into the typed text.

var _failures: int = 0
var _checks: int = 0
var _caret_rows: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print("%s  %s" % ["OK  " if condition else "FAIL", message])
	if not condition:
		_failures += 1
		push_error("WS2_UI: " + message)


func _run() -> void:
	await _test_main_menu_structure()
	await _test_mapmaker_teaser()
	await _test_text_caret_inventory()
	if OS.get_environment("CSGP_WS2_METRICS") == "1":
		await _dump_screen_metrics(PLAY_MENU_SCENE, "play_menu")
		await _dump_screen_metrics(MINIGAMES_SCENE, "minigames_menu")
		await _dump_screen_metrics(VEHICLE_SCENE, "vehicle_select")
	print("WS2_UI: %d checks, %d failures" % [_checks, _failures])
	for row: String in _caret_rows:
		print("WS2_CARET %s" % row)
	print("WS2_UI: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else _failures)


# --------------------------------------------------------------------------
# Main menu hero rail: exact order, labels, responsive geometry.
# --------------------------------------------------------------------------


func _make_menu() -> Node:
	var menu: Node = (load(MAIN_MENU_SCENE) as PackedScene).instantiate()
	root.add_child(menu)
	current_scene = menu as Node
	return menu


func _settle(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame
	await process_frame


func _test_main_menu_structure() -> void:
	print("--- main menu hero rail")
	var menu: Node = _make_menu()
	await _settle(0.45)
	if not menu.has_method("hero_option_buttons"):
		_check(false, "main menu exposes hero_option_buttons() for its rail")
		menu.queue_free()
		await process_frame
		return
	var buttons: Array = menu.call("hero_option_buttons")
	_check(buttons.size() == EXPECTED_HERO_LABELS.size(),
		"hero rail holds %d options (got %d)" % [EXPECTED_HERO_LABELS.size(),
		buttons.size()])
	var labels: Array = []
	for raw: Variant in buttons:
		if raw is Button:
			labels.append(str((raw as Button).get("label_text")))
	_check(labels == EXPECTED_HERO_LABELS,
		"hero order/labels are exactly SINGLEPLAYER, MULTIPLAYER, MAPMAKER, GARAGE (got %s)"
			% str(labels))
	var rail: Control = menu.get("_hero_rail") as Control
	_check(rail != null, "main menu built its HeroRail container")
	if rail == null or buttons.size() != EXPECTED_HERO_LABELS.size():
		menu.queue_free()
		await process_frame
		return

	# The teaser is clickable (not disabled) but advertises its locked state.
	var teaser_button: Button = buttons[2] as Button
	_check(teaser_button != null and not teaser_button.disabled,
		"MAPMAKER teaser stays clickable (not a disabled Button)")
	if teaser_button != null:
		_check(bool(teaser_button.get_meta("locked_teaser", false)),
			"MAPMAKER teaser is tagged as a locked/soon tile for drawing")
		_check(bool(teaser_button.get_meta("nav_default", false)) == false,
			"MAPMAKER teaser does not steal the default focus")
	# 0.8.7 background correction: the menu backdrop shuffles its own hero-art
	# pool on an 8-12 s beat. Hover/focus is NOT allowed to retarget or pause it:
	# no tile carries hover-backdrop metadata and no menu script references the
	# retired hover driver.
	for raw: Variant in buttons:
		var tile := raw as Control
		_check(tile != null and not tile.has_meta("hover_art"),
			"hero tile carries no hover-backdrop metadata (backdrop is autonomous)")
	var menu_script: String = FileAccess.get_file_as_string(
		"res://scripts/ui/main_menu.gd")
	_check(not menu_script.contains("menu_hover_backdrop")
			and not menu_script.contains("MenuHoverBackdrop")
			and not menu_script.contains("focus_art")
			and not menu_script.contains("hover_art"),
		"main_menu.gd has no hover/focus backdrop wiring")
	var background: Control = menu.get_node_or_null("Background") as Control
	_check(background != null, "main menu has a MenuBackground node")
	var art: Node = background.call("art_backdrop_node") if background != null else null
	_check(art != null, "MenuBackground exposes its self-timed ArtBackdrop")
	if art != null:
		_check(bool(art.get("auto_advance")),
			"menu backdrop auto-advance is ON (self-shuffling)")
		_check(bool(art.get("shuffle")),
			"menu backdrop uses shuffled playback order")
		var names: PackedStringArray = art.call("slide_names")
		_check(names.size() == 4,
			"main menu cycles all four hero art plates (got %d: %s)"
				% [names.size(), str(names)])
		var all_hero: bool = not names.is_empty()
		for file_name: String in names:
			if not file_name.begins_with("bg_hero_"):
				all_hero = false
		_check(all_hero, "every main-menu slide is a bg_hero_* plate")
		var slide_min: float = float(art.get("slide_seconds_min"))
		var slide_max: float = float(art.get("slide_seconds_max"))
		_check(slide_min >= 8.0 and slide_max <= 12.0 and slide_max > slide_min,
			"menu slide cadence is the 8-12 s band (got %.1f-%.1f s)"
				% [slide_min, slide_max])
		_check(float(art.get("fade_seconds")) >= 0.2,
			"menu slide crossfade is smooth (%.2f s)"
				% float(art.get("fade_seconds")))

		# Hover/focus independence: freeze the cadence, then synthesize focus and
		# hover across every hero option and dock card. Provenance: the buttons
		# no longer carry any backdrop metadata and the menu script has no such
		# call sites (checked above); this proves the live backdrop stays put.
		art.set("slide_seconds_min", 600.0)
		art.set("slide_seconds_max", 600.0)
		art.call("reset_schedule")
		var before_name: String = str(art.call("current_slide_name"))
		var before_index: int = int(art.call("current_index"))
		for raw: Variant in buttons:
			var tile := raw as Button
			if tile != null:
				tile.grab_focus()
				tile.mouse_entered.emit()
				tile.mouse_exited.emit()
		var dock: Control = menu.get("_dock_bar") as Control
		if dock != null:
			for child: Node in dock.get_children():
				if child is Button:
					(child as Button).grab_focus()
					(child as Button).mouse_entered.emit()
		await _settle(0.12)
		_check(str(art.call("current_slide_name")) == before_name
				and int(art.call("current_index")) == before_index,
			"hover/focus never swaps the autonomous backdrop (still %s)"
				% before_name)
		_check(bool(art.get("auto_advance")),
			"slideshow auto-advance stays on while options are hovered/focused")

		# The backdrop really does advance by itself: short cadence window.
		art.set("fade_seconds", 0.04)
		art.set("slide_seconds_min", 0.06)
		art.set("slide_seconds_max", 0.08)
		art.call("reset_schedule")
		await create_timer(0.5).timeout
		var transitions: int = int(art.call("advance_count"))
		_check(transitions >= 2,
			"menu backdrop advanced on its own (%d crossfades in 0.5 s)"
				% transitions)

		# Reduced motion is respected: the plate is held still (no auto crossfade,
		# no Ken Burns drift) while the artwork stays on screen.
		var settings: Node = root.get_node_or_null("GameSettings")
		if settings != null:
			var previous_reduced: bool = bool(settings.get("reduce_motion"))
			settings.set("reduce_motion", true)
			# Let any in-flight crossfade finish, then prove the plate is held.
			await create_timer(0.15).timeout
			var still_index: int = int(art.call("current_index"))
			var still_count: int = int(art.call("advance_count"))
			await create_timer(0.35).timeout
			_check(int(art.call("current_index")) == still_index
					and int(art.call("advance_count")) == still_count,
				"reduced motion holds a still plate (no auto crossfade)")
			_check(not bool(art.call("ken_burns_active")),
				"reduced motion disables Ken Burns drift")
			settings.set("reduce_motion", previous_reduced)

	for size: Vector2i in VIEWPORTS:
		root.size = size
		await _settle(0.20)
		var design: Vector2 = root.get_visible_rect().size
		var label: String = "main_menu@%dx%d" % [size.x, size.y]
		var rail_rect: Rect2 = rail.get_global_rect()
		var prev_bottom: float = -INF
		var gaps_ok: bool = true
		var widths_ok: bool = true
		var widths: Array[float] = []
		var order_ok: bool = true
		for index in buttons.size():
			var button := buttons[index] as Control
			var rect: Rect2 = button.get_global_rect()
			# Layout width, not the hover/focus-scaled global rect: the focused
			# primary tile is drawn 2.8% larger on purpose.
			widths.append(button.size.x)
			if rect.position.y < prev_bottom - 0.5:
				order_ok = false
			prev_bottom = rect.end.y
			var inset_ok: bool = rect.position.x >= 0.0 and rect.position.y >= 0.0 \
				and rect.end.x <= design.x and rect.end.y <= design.y
			_check(inset_ok, "%s %s tile leaves the viewport: %s"
				% [label, str(button.get("label_text")), str(rect)])
		for width: float in widths:
			if absf(width - widths[0]) > 0.5:
				widths_ok = false
		_check(order_ok, "%s hero tiles are stacked top-to-bottom in order" % label)
		_check(widths_ok, "%s hero tiles share one width (got %s)"
			% [label, str(widths)])
		_check(rail_rect.position.y >= 0.0 and rail_rect.end.y <= design.y,
			"%s hero rail fits vertically (%.1f..%.1f of %.0f)"
				% [label, rail_rect.position.y, rail_rect.end.y, design.y])
		_check(rail_rect.size.y >= float(buttons.size()) * HERO_PRIMARY_HEIGHT * 0.6,
			"%s hero rail grew for the 4th tile (height %.1f)" % [label, rail_rect.size.y])
		var first: Control = buttons[0] as Control
		var second: Control = buttons[1] as Control
		var gap: float = second.get_global_rect().position.y - first.get_global_rect().end.y
		_check(gap >= 0.0 and gap <= 24.0,
			"%s hero gap between SINGLEPLAYER and MULTIPLAYER is intentional (%.1f px)"
				% [label, gap])
		var dock: Control = menu.get("_dock_bar") as Control
		if dock != null:
			var dock_rect: Rect2 = dock.get_global_rect()
			_check(dock_rect.end.y <= design.y + 0.5 and dock_rect.position.x >= -0.5,
				"%s dock row stays inside the viewport (%s)" % [label, str(dock_rect)])
			_check(dock_rect.position.y > rail_rect.end.y - 2.0,
				"%s dock row does not collide with the hero rail" % label)
		var tiles: Array = []
		for index in buttons.size():
			var button := buttons[index] as Control
			var rect: Rect2 = button.get_global_rect()
			tiles.append("%s=%.0fx%.0f@%.0f,%.0f" % [
				str(button.get("label_text")), rect.size.x, rect.size.y,
				rect.position.x, rect.position.y])
		print("WS2_METRIC %s design=%.0fx%.0f rail=%.0fx%.0f@%.0f,%.0f hero=[%s] gap=%.1f"
			% [label, design.x, design.y, rail_rect.size.x, rail_rect.size.y,
			rail_rect.position.x, rail_rect.position.y, ", ".join(tiles), gap])
	menu.queue_free()
	await process_frame
	await process_frame
	root.size = Vector2i(1280, 720)


# --------------------------------------------------------------------------
# Mapmaker teaser popup: exact copy, OK button, one confetti burst per open.
# --------------------------------------------------------------------------


func _find_control_with_meta(node: Node, meta: String) -> Array[Node]:
	var found: Array[Node] = []
	if node.has_meta(meta):
		found.append(node)
	for child: Node in node.get_children():
		found.append_array(_find_control_with_meta(child, meta))
	return found


func _test_mapmaker_teaser() -> void:
	print("--- mapmaker teaser")
	var menu: Node = _make_menu()
	await _settle(0.45)
	if not menu.has_method("open_mapmaker_teaser"):
		_check(false, "main menu exposes open_mapmaker_teaser()")
		menu.queue_free()
		await process_frame
		return
	var hero: Array = menu.call("hero_option_buttons")
	var teaser_button: Button = hero[2] as Button if hero.size() > 2 else null
	_check(teaser_button != null, "MAPMAKER tickes is reachable from the rail")
	if teaser_button == null:
		menu.queue_free()
		await process_frame
		return
	# Drive the real click path (button press), not just the public method.
	teaser_button.pressed.emit()
	await _settle(0.15)
	var popup: Node = menu.call("mapmaker_teaser_node")
	_check(popup != null and is_instance_valid(popup), "Mapmaker popup instance exists")
	if popup == null or not is_instance_valid(popup):
		menu.queue_free()
		await process_frame
		return
	_check((popup as Control).visible, "Mapmaker popup is visible after the tile click")
	_check(str(popup.call("message_text")) == MAPMAKER_MESSAGE,
		"popup copy is exactly '%s' (got '%s')"
			% [MAPMAKER_MESSAGE, str(popup.call("message_text"))])
	var ok: Button = popup.call("ok_button") as Button
	_check(ok != null and ok.text == "OK", "popup has an OK button")
	_check(ok != null and ok.is_visible_in_tree(), "OK button is visible/clickable")

	# Exactly one confetti burst per open, and it is a one-shot emitter.
	_check(int(popup.call("burst_count")) == 1,
		"one confetti burst fired on open (got %d)" % int(popup.call("burst_count")))
	_check(int(popup.call("live_burst_count")) == 1,
		"exactly one live confetti emitter (got %d)"
			% int(popup.call("live_burst_count")))
	var bursts: Array[Node] = _find_control_with_meta(popup, "ws2_confetti")
	_check(bursts.size() == 1, "one tagged confetti node (got %d)" % bursts.size())
	if bursts.size() == 1:
		var particles := bursts[0] as CPUParticles2D
		_check(particles != null and particles.one_shot,
			"confetti emitter is a CPUParticles2D one-shot (no continuous emitter)")
		if particles != null:
			_check(particles.amount > 0 and particles.lifetime > 0.0,
				"confetti burst has a positive amount/lifetime (%d, %.2fs)"
					% [particles.amount, particles.lifetime])
			_check(particles.emitting,
				"burst is actively emitting its single shot on open")
	var nav: Node = root.get_node_or_null("MenuNav")
	_check(nav != null, "MenuNav autoload present")
	if nav != null:
		await _settle(0.10)
		_check(nav.call("current_scope") == popup,
			"open popup owns the keyboard/gamepad focus scope")
		_check(nav.call("focused_control") == ok,
			"focus lands on the OK button")

	# Close with OK, wait for the one-shot to finish and be freed, reopen.
	ok.pressed.emit()
	await _settle(0.20)
	_check(not (popup as Control).visible, "OK closes the popup")
	await create_timer(2.6).timeout
	_check(int(popup.call("live_burst_count")) == 0,
		"confetti particles are freed after the burst (got %d live)"
			% int(popup.call("live_burst_count")))
	teaser_button.pressed.emit()
	await _settle(0.20)
	_check((popup as Control).visible, "second tile click reopens the popup")
	_check(int(popup.call("burst_count")) == 2,
		"a second open fires exactly one more burst (total %d)"
			% int(popup.call("burst_count")))
	_check(int(popup.call("live_burst_count")) == 1,
		"reopening never stacks emitters (got %d live)"
			% int(popup.call("live_burst_count")))

	# Reduced motion: no particle burst, but the popup still opens.
	var settings: Node = root.get_node_or_null("GameSettings")
	var previous_reduced: bool = false
	if settings != null:
		previous_reduced = bool(settings.get("reduce_motion"))
		# Direct property write: the public setter also persists settings.cfg,
		# which a headless audit must not touch.
		settings.set("reduce_motion", true)
	popup.call("close")
	await _settle(0.10)
	teaser_button.pressed.emit()
	await _settle(0.10)
	_check(int(popup.call("skipped_burst_count")) >= 1,
		"reduced motion skips the confetti burst")
	_check(int(popup.call("live_burst_count")) == 0,
		"reduced motion spawns no particle nodes")
	if settings != null:
		settings.set("reduce_motion", previous_reduced)
	popup.call("close")
	await _settle(0.10)
	menu.queue_free()
	await process_frame
	await process_frame


# --------------------------------------------------------------------------
# Caret inventory: every LineEdit in every scene that owns one.
# --------------------------------------------------------------------------


func _collect_line_edits(node: Node, out: Array[LineEdit]) -> void:
	if node is LineEdit:
		out.append(node as LineEdit)
	for child: Node in node.get_children():
		_collect_line_edits(child, out)


func _relative_luminance(color: Color) -> float:
	var channels: Array[float] = [color.r, color.g, color.b]
	for index in 3:
		var value: float = channels[index]
		channels[index] = value / 12.92 if value <= 0.03928 \
			else pow((value + 0.055) / 1.055, 2.4)
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


func _contrast_ratio(a: Color, b: Color) -> float:
	var la: float = _relative_luminance(a)
	var lb: float = _relative_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _color_distance(a: Color, b: Color) -> float:
	var dr: float = a.r - b.r
	var dg: float = a.g - b.g
	var db: float = a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


func _field_background(field: LineEdit) -> Color:
	var box: StyleBox = field.get_theme_stylebox("normal")
	if box is StyleBoxFlat:
		var flat := box as StyleBoxFlat
		return Color(flat.bg_color.r, flat.bg_color.g, flat.bg_color.b, 1.0)
	return Color(UiPalette.FIELD_FILL.r, UiPalette.FIELD_FILL.g,
		UiPalette.FIELD_FILL.b, 1.0)


func _audit_caret(site: String, field: LineEdit) -> void:
	_check(field.caret_blink, "%s: caret_blink is true (caret never sits static)" % site)
	_check(absf(field.caret_blink_interval - CARET_BLINK_SECONDS)
			<= CARET_BLINK_TOLERANCE,
		"%s: caret_blink_interval is ~%.2fs (got %.3f)"
			% [site, CARET_BLINK_SECONDS, field.caret_blink_interval])
	_check(field.has_theme_color_override("caret_color"),
		"%s: caret_color is set explicitly (not inherited)" % site)
	var caret: Color = field.get_theme_color("caret_color")
	var field_bg: Color = _field_background(field)
	var text_col: Color = field.get_theme_color("font_color")
	var contrast: float = _contrast_ratio(caret, field_bg)
	var text_distance: float = _color_distance(caret, text_col)
	_check(contrast >= MIN_CARET_CONTRAST,
		"%s: caret %s has >= %.1f:1 contrast against its field %s (got %.1f:1)"
			% [site, caret.to_html(false), MIN_CARET_CONTRAST,
			field_bg.to_html(false), contrast])
	_check(text_distance >= MIN_CARET_FONT_DISTANCE,
		"%s: caret colour differs from its text colour (distance %.2f)"
			% [site, text_distance])
	_caret_rows.append("%s caret=#%s field=#%s text=#%s contrast=%.1f:1 blink=%.2fs dist=%.2f"
		% [site, caret.to_html(false), field_bg.to_html(false),
		text_col.to_html(false), contrast, field.caret_blink_interval, text_distance])


func _instantiate_scene(path: String) -> Node:
	var scene: Resource = load(path)
	if scene == null:
		return null
	return (scene as PackedScene).instantiate()


func _test_text_caret_inventory() -> void:
	print("--- text caret inventory")
	var settings: Node = root.get_node_or_null("GameSettings")
	_check(settings != null, "GameSettings autoload present for reduced-motion state")

	# 1. The shared UiKit hook must style a bare LineEdit that enters the tree:
	#    this is how scene-authored and runtime-built fields (meadow lobby) are
	#    covered without every screen remembering the caret token.
	var bare := LineEdit.new()
	bare.name = "Ws2BareLineEdit"
	root.add_child(bare)
	await _settle(0.10)
	_audit_caret("ui_kit-hook:synthetic", bare)
	bare.queue_free()
	await process_frame

	# 2. Every UI scene that owns a LineEdit, plus the meadow waiting room.
	var scenes: Array[Dictionary] = [
		{"id": "room_browser", "path": ROOM_BROWSER_SCENE},
		{"id": "lobby_menu", "path": LOBBY_SCENE},
		{"id": "meadow_lobby", "path": MEADOW_LOBBY_SCENE},
	]
	for entry: Dictionary in scenes:
		var path: String = str(entry["path"])
		var id: String = str(entry["id"])
		if not ResourceLoader.exists(path):
			_check(false, "%s: scene missing (%s)" % [id, path])
			continue
		var instance: Node = _instantiate_scene(path)
		if instance == null:
			_check(false, "%s: failed to instantiate" % id)
			continue
		root.add_child(instance)
		current_scene = instance
		await _settle(0.40)
		var fields: Array[LineEdit] = []
		_collect_line_edits(instance, fields)
		_check(not fields.is_empty(), "%s: has at least one text input" % id)
		for index in fields.size():
			var field: LineEdit = fields[index]
			var site: String = "%s:%s" % [id,
				field.name if field.name != "" else "LineEdit%d" % index]
			_audit_caret(site, field)
		var text_edits: Array[TextEdit] = []
		var stack: Array[Node] = [instance]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if node is TextEdit:
				text_edits.append(node as TextEdit)
			for child: Node in node.get_children():
				stack.append(child)
		_check(text_edits.is_empty(),
			"%s: no TextEdit inputs outside the shared contract (got %d)"
				% [id, text_edits.size()])
		instance.queue_free()
		current_scene = null
		await process_frame
		await process_frame
	print("    caret inputs checked: %d" % _caret_rows.size())


# --------------------------------------------------------------------------
# Optional metrics dump for closely related screens.
# --------------------------------------------------------------------------


func _dump_screen_metrics(path: String, id: String) -> void:
	if not ResourceLoader.exists(path):
		return
	for size: Vector2i in VIEWPORTS:
		root.size = size
		await process_frame
		var instance: Node = _instantiate_scene(path)
		if instance == null:
			continue
		root.add_child(instance)
		current_scene = instance
		await _settle(0.45)
		var design: Vector2 = root.get_visible_rect().size
		var panel: Control = instance.get_node_or_null("Center/Panel") as Control
		var buttons: Array[Button] = []
		_collect_buttons(instance, buttons)
		var widest: String = ""
		var widest_w: float = 0.0
		var outside: int = 0
		for button: Button in buttons:
			if not button.is_visible_in_tree():
				continue
			var rect: Rect2 = button.get_global_rect()
			var text: String = button.text if button.text != "" else str(button.name)
			if rect.size.x > widest_w:
				widest_w = rect.size.x
				widest = text
			if rect.position.x < -2.0 or rect.position.y < -2.0 \
					or rect.end.x > design.x + 2.0 or rect.end.y > design.y + 2.0:
				outside += 1
		print("WS2_METRIC %s@%dx%d design=%.0fx%.0f panel=%.0fx%.0f buttons=%d widest=%s width=%.0f outside=%d"
			% [id, size.x, size.y, design.x, design.y,
			panel.size.x if panel != null else 0.0,
			panel.size.y if panel != null else 0.0,
			buttons.size(), widest, widest_w, outside])
		instance.queue_free()
		await process_frame
		await process_frame
	root.size = Vector2i(1280, 720)


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	if node is Button:
		out.append(node as Button)
	for child: Node in node.get_children():
		_collect_buttons(child, out)
