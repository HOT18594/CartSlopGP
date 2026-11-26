extends SceneTree
## Headless theme + layout audit for every menu, overlay and the HUD.
##
## Instantiates each UI screen, shows its overlays, then checks at the
## 1280x720 design box and at a 1920x1080 window (same design box because the
## project uses `canvas_items` stretch with `expand`):
##   1. THEME   - every Button / CheckButton / Panel / input / slider / scrollbar
##                resolves to a slanted (skewed) dark-glass style, not a legacy
##                rounded or cream box.
##   2. LAYOUT  - no visible control leaves the viewport.
##   3. FOCUS   - MenuNav's focus map closes into one ring covering every
##                focusable control (keyboard / gamepad reachability).
##
## Exit code = number of failures. Run:
##   godot --headless --path godot_project --script res://scripts/ui/ui_layout_audit.gd
##
## This lives under scripts/ui/ (not scripts/tools/) because WS2 owns the UI
## scope; it is the UI workstream's own verification harness.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
## WS3 Phase-3 integration modules (in-room lobby audit below).
const LobbyEmoteOverlay := preload("res://scripts/ui/lobby_emote_overlay.gd")
const LobbyMapPreview := preload("res://scripts/ui/lobby_map_preview.gd")
const PAUSE_MENU_SCRIPT := "res://scripts/ui/pause_menu.gd"
const RESULT_SCREEN_SCRIPT := "res://scripts/ui/result_screen.gd"

const DESIGN_WIDTH: float = 1280.0 ## 1280x720 authoring box (project.godot).
const DESIGN_HEIGHT: float = 720.0

const SCREENS: Array[Dictionary] = [
	{"id": "main_menu", "path": "res://scenes/ui/main_menu.tscn"},
	# WS2: the MAPMAKER "COMING SOON :D" overlay is a real focus scope that can
	# be opened from the main menu, so it is measured like any other page.
	{"id": "mapmaker_teaser", "path": "res://scenes/ui/mapmaker_teaser.tscn",
		"reveal": true, "open": true},
	{"id": "play_menu", "path": "res://scenes/ui/play_menu.tscn"},
	{"id": "minigames_menu", "path": "res://scenes/ui/minigames_menu.tscn",
		"states": [
			{"id": "select_racing", "method": "_show_selector", "args": ["racing"]},
			{"id": "select_cargo", "method": "_show_selector", "args": ["cargo_rush"]},
			{"id": "select_knockout", "method": "_show_selector", "args": ["knockout"]},
			{"id": "select_bomb", "method": "_show_selector", "args": ["bomb_tag"]},
		]},
	{"id": "vehicle_select", "path": "res://scenes/ui/vehicle_select.tscn"},
	{"id": "lobby_menu", "path": "res://scenes/ui/lobby_menu.tscn",
		"states": [
			# WS4 in-room lobby + seeded reactions; the state also runs the WS3
			# Phase-B integration audit (text-only emotes, slanted preview card,
			# autonomous hover-independent backdrop) at both resolutions.
			{"id": "room_reactions", "method": "audit_room_state", "args": [],
				"audit": "lobby_integration"},
		]},
	{"id": "pause_menu", "path": "res://scenes/ui/pause_menu.tscn", "reveal": true},
	{"id": "settings_menu", "path": "res://scenes/ui/settings_menu.tscn", "reveal": true,
		"states": [
			{"id": "page_audio", "method": "_show_page", "args": [0]},
			{"id": "page_video", "method": "_show_page", "args": [1]},
			{"id": "page_gameplay", "method": "_show_page", "args": [2]},
			{"id": "page_access", "method": "_show_page", "args": [3]},
			{"id": "page_updates", "method": "_show_page", "args": [4]},
		]},
	{"id": "room_browser", "path": "res://scenes/ui/room_browser.tscn", "reveal": true,
		"states": [{"id": "rooms", "method": "set_rooms", "args": []}]},
	{"id": "update_panel", "path": "res://scenes/ui/update_panel.tscn", "reveal": true,
		"open": true},
	{"id": "changelog_panel", "path": "res://scenes/ui/changelog_panel.tscn", "open": true,
		"states": [{"id": "release_detail", "method": "_show_release", "args": [0]}]},
	# WS4: the loading overlay is a real visible screen on every scene load, so
	# its heading/tip/bar are measured at both resolutions like any other page.
	{"id": "loading_screen", "path": "res://scenes/ui/scene_loader.tscn", "reveal": true},
	{"id": "hud", "path": "res://scenes/ui/hud.tscn"},
]

const VIEWPORTS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
const TOLERANCE: float = 2.0 ## Sub-pixel layout rounding slack.
const SETTLE_SECONDS: float = 0.65 ## Let modal pop / stagger tweens finish.

var _failures: int = 0
var _screen_failures: int = 0
var _measured: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		_screen_failures += 1
		print("UI_AUDIT_FAIL %s" % message)


func _run() -> void:
	if not ProjectSettings.get_setting("application/run/main_scene", ""):
		_fail("No main scene configured")
	for screen: Dictionary in SCREENS:
		await _audit_screen(screen)
	await _audit_result_cards()
	if OS.get_environment("CART_UI_MODE_CARDS") == "1":
		await _audit_live_mode_cards()
	print("UI_AUDIT: %d screens measured, %d failures"
		% [_measured, _failures])
	print("UI_AUDIT: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else _failures)


func _fail(message: String) -> void:
	_failures += 1
	_screen_failures += 1
	print("UI_AUDIT_FAIL %s" % message)


func _audit_screen(screen: Dictionary) -> void:
	var scene_path: String = str(screen.get("path", ""))
	if not ResourceLoader.exists(scene_path):
		_fail("%s: scene missing (%s)" % [screen.get("id"), scene_path])
		return
	for size: Vector2i in VIEWPORTS:
		var instance: Node = (load(scene_path) as PackedScene).instantiate()
		if instance == null:
			_fail("%s: failed to instantiate" % screen.get("id"))
			return
		root.add_child(instance)
		current_scene = instance
		await process_frame
		if bool(screen.get("reveal", false)) or bool(screen.get("open", false)):
			_reveal(instance)
			if bool(screen.get("open", false)) and instance.has_method("open"):
				instance.call("open")
		await create_timer(SETTLE_SECONDS).timeout
		await process_frame
		await _audit_viewport(str(screen.get("id", "")), size, instance, "")
		var states: Array = screen.get("states", [])
		for state: Dictionary in states:
			if not _apply_state(instance, state):
				_fail("%s: state '%s' could not be applied"
					% [screen.get("id"), state.get("id")])
				continue
			await create_timer(0.35).timeout
			await process_frame
			await _audit_viewport(str(screen.get("id", "")), size, instance,
				str(state.get("id", "")))
			if str(state.get("audit", "")) == "lobby_integration":
				var audit_label: String = "%s:%s@%dx%d" % [screen.get("id"),
					state.get("id"), size.x, size.y]
				await _audit_lobby_integration(instance, audit_label)
		instance.queue_free()
		await process_frame
		await process_frame


func _reveal(instance: Node) -> void:
	var target: Node = instance
	if instance is CanvasLayer:
		for child: Node in instance.get_children():
			if child is Control:
				target = child
				break
	if target is Control:
		(target as Control).show()
		(target as Control).visible = true


func _apply_state(instance: Node, state: Dictionary) -> bool:
	var method_name: String = str(state.get("method", ""))
	if method_name == "" or not instance.has_method(method_name):
		return false
	var args: Array = state.get("args", [])
	if method_name == "set_rooms":
		args = [_sample_rooms()]
	instance.callv(method_name, args)
	return true


func _sample_rooms() -> Array[Dictionary]:
	## Enough rows to force the room-browser scrollbar visible, exactly the
	## state where the legacy rounded scrollbar used to show up.
	var version: String = str(ProjectSettings.get_setting(
		"application/config/version", ""))
	var rooms: Array[Dictionary] = []
	for index in 9:
		rooms.append({
			"name": "SLOP ROOM %d" % (index + 1),
			"host": "HOST %d" % (index + 1),
			"players": 1 + index % 7,
			"ping": 8 + index * 9,
			"state": "lobby" if index % 3 != 2 else "racing",
			"version": version,
			"public": true,
			"_source": "lan" if index % 2 == 0 else "online",
		})
	return rooms


func _audit_viewport(screen_id: String, window_size: Vector2i, instance: Node,
		state_id: String = "") -> void:
	root.size = window_size
	await process_frame
	await create_timer(0.1).timeout
	var design: Vector2 = root.get_visible_rect().size
	var label: String = "%s@%dx%d" % [screen_id, window_size.x, window_size.y]
	if state_id != "":
		label += ":" + state_id
	# The design box may grow on non-16:9 windows but it must never shrink below
	# the 1280x720 box the screens are authored against.
	_check(design.x >= DESIGN_WIDTH - TOLERANCE
		and design.y >= DESIGN_HEIGHT - TOLERANCE,
		"%s design box %.0fx%.0f shrank below the 1280x720 authoring box"
		% [label, design.x, design.y])
	var issues: Dictionary = {"legacy": [], "overflow": [], "counts": {}}
	_collect(instance, design, issues)
	var legacy: Array = issues["legacy"]
	var overflow: Array = issues["overflow"]
	_check(legacy.is_empty(), "%s legacy theme controls: %s"
		% [label, ", ".join(legacy)])
	_check(overflow.is_empty(), "%s controls outside the viewport: %s"
		% [label, ", ".join(overflow)])
	var expected: Array[Control] = []
	_collect_focusables(instance, expected)
	var focus_state: String = await _focus_state(instance, expected)
	_check(focus_state == "ok" or focus_state == "none",
		"%s focus unavailable: %s" % [label, focus_state])
	print("UI_AUDIT %s design=%.0fx%.0f buttons=%d focusables=%d expected=%d legacy=%d overflow=%d focus=%s"
		% [label, design.x, design.y, int(issues["counts"].get("buttons", 0)),
		_focusable_count(), expected.size(), legacy.size(), overflow.size(), focus_state])
	_measured += 1


func _collect(node: Node, design: Vector2, issues: Dictionary) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		var control := node as Control
		_note_theme(control, issues)
		_note_overflow(control, design, issues)
	if node is ScrollContainer:
		_note_scrollbars(node as ScrollContainer, issues)
	for child: Node in node.get_children():
		_collect(child, design, issues)


func _note_theme(control: Control, issues: Dictionary) -> void:
	if control is Button:
		var counts: Dictionary = issues["counts"]
		counts["buttons"] = int(counts.get("buttons", 0)) + 1
		var issue: String = _button_theme_issue(control as Button)
		if issue != "":
			_legacy(issues, "%s('%s')" % [issue, control.name])
	elif control is PanelContainer or control is Panel:
		var panel_box: StyleBox = control.get_theme_stylebox("panel")
		var issue: String = _style_issue(panel_box, "panel")
		if issue != "":
			_legacy(issues, "%s('%s')" % [issue, control.name])
	elif control is LineEdit:
		var input_box: StyleBox = control.get_theme_stylebox("normal")
		var input_issue: String = _style_issue(input_box, "input")
		if input_issue != "":
			_legacy(issues, "%s('%s')" % [input_issue, control.name])
	elif control is HSlider:
		if control.get_script() == null:
			var slider_box: StyleBox = control.get_theme_stylebox("slider")
			var slider_issue: String = _style_issue(slider_box, "slider")
			if slider_issue != "":
				_legacy(issues, "%s('%s')" % [slider_issue, control.name])
	elif control is ProgressBar:
		var fill_box: StyleBox = control.get_theme_stylebox("fill")
		var fill_issue: String = _style_issue(fill_box, "progress")
		if fill_issue != "":
			_legacy(issues, "%s('%s')" % [fill_issue, control.name])


func _button_theme_issue(button: Button) -> String:
	if button.has_meta("custom_focus") or button.has_meta("skip_kit"):
		return ""
	if button.has_meta("theme_ok"):
		return ""
	var normal: StyleBox = button.get_theme_stylebox("normal")
	if normal is StyleBoxFlat:
		var flat := normal as StyleBoxFlat
		if _is_cream(flat.bg_color) and flat.draw_center:
			return "CREAM_BUTTON"
		if absf(flat.skew.x) >= 0.015:
			return ""
		if flat.corner_radius_top_left >= 10 or flat.corner_radius_bottom_left >= 10:
			return "ROUNDED_BUTTON"
		return ""
	if normal is StyleBoxEmpty:
		# A custom-drawn button (script class) deliberately empties the theme.
		if button.get_script() != null:
			return ""
		return "DEFAULT_THEME_BUTTON"
	if button.flat:
		return ""
	return "DEFAULT_THEME_BUTTON"


func _style_issue(style: StyleBox, role: String) -> String:
	if style == null or not (style is StyleBoxFlat):
		return ""
	var flat := style as StyleBoxFlat
	if _is_cream(flat.bg_color) and flat.draw_center:
		return "CREAM_" + role.to_upper()
	if absf(flat.skew.x) >= 0.015:
		return ""
	if role == "progress" or role == "slider":
		return "ROUNDED_" + role.to_upper()
	if flat.corner_radius_top_left >= 10 or flat.corner_radius_bottom_left >= 10:
		return "ROUNDED_" + role.to_upper()
	return ""


func _is_cream(color: Color) -> bool:
	# UiPalette.CREAM is #fff6e3; legacy cream boxes sit in the same band.
	return color.r > 0.92 and color.g > 0.86 and color.b > 0.66 \
		and color.a > 0.5 and color.r >= color.g and color.g >= color.b


func _note_overflow(control: Control, design: Vector2, issues: Dictionary) -> void:
	if not control.is_visible_in_tree():
		return
	# Rows inside a ScrollContainer are clipped by the scroll viewport, so they
	# may legitimately extend past it; only the container itself must fit.
	if _inside_scroll(control):
		return
	var rect: Rect2 = control.get_global_rect()
	if rect.size.x < 0.5 or rect.size.y < 0.5:
		return
	if rect.position.x >= -TOLERANCE and rect.position.y >= -TOLERANCE \
			and rect.end.x <= design.x + TOLERANCE and rect.end.y <= design.y + TOLERANCE:
		return
	var overflow: Array = issues["overflow"]
	if overflow.size() < 12:
		overflow.append("%s(%.0f,%.0f %.0fx%.0f)"
			% [control.name, rect.position.x, rect.position.y, rect.size.x, rect.size.y])


func _inside_scroll(control: Control) -> bool:
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false


func _note_scrollbars(scroll: ScrollContainer, issues: Dictionary) -> void:
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	if bar == null or not bar.is_visible_in_tree():
		return
	var grabber: StyleBox = bar.get_theme_stylebox("grabber")
	var issue: String = _style_issue(grabber, "scrollbar")
	if issue != "":
		_legacy(issues, "%s('%s')" % [issue, scroll.name])


func _legacy(issues: Dictionary, tag: String) -> void:
	var legacy: Array = issues["legacy"]
	if legacy.size() < 12 and not legacy.has(tag):
		legacy.append(tag)


func _menu_nav() -> Node:
	return root.get_node_or_null("MenuNav")


func _focusable_count() -> int:
	var nav: Node = _menu_nav()
	if nav == null:
		return 0
	return (nav.get("_focusables") as Array).size()


func _collect_focusables(node: Node, out: Array[Control]) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		var control := node as Control
		if control.focus_mode != Control.FOCUS_NONE and not control.has_meta("nav_skip"):
			if not (control is BaseButton and (control as BaseButton).disabled):
				out.append(control)
	for child: Node in node.get_children():
		_collect_focusables(child, out)


func _focus_state(instance: Node, expected: Array[Control]) -> String:
	var nav: Node = _menu_nav()
	if nav == null:
		return "no-menu-nav-autoload"
	nav.call("refresh")
	# Two frames: one for MenuNav._process to rebuild, one for the grab.
	await process_frame
	await process_frame
	var focusables: Array = nav.get("_focusables")
	if expected.is_empty():
		return "none" if focusables.is_empty() else "unexpected-focusables"
	if focusables.is_empty():
		return "no-scope-or-focusables"
	# A scope with exactly one control (e.g. the Mapmaker popup's OK button) has
	# no ring to close; MenuNav deliberately leaves focus_next empty there.
	if focusables.size() == 1 and expected.size() == 1:
		return "ok" if focusables[0] == expected[0] else "wrong-single-focusable"
	var expected_ids: Dictionary = {}
	for control: Control in expected:
		expected_ids[control.get_instance_id()] = true
	var ring_ids: Dictionary = {}
	var current: Control = focusables[0] as Control
	for _step in focusables.size() + 1:
		if not is_instance_valid(current):
			return "ring-has-freed-control"
		var id: int = current.get_instance_id()
		if ring_ids.has(id):
			break
		ring_ids[id] = true
		var next_path: NodePath = current.focus_next
		if next_path.is_empty():
			return "ring-breaks-at-" + str(current.name)
		current = current.get_node_or_null(next_path) as Control
		if current == null:
			return "ring-dangling-path-" + str(next_path)
	if ring_ids.size() != focusables.size():
		return "ring-does-not-cover-all (%d/%d)" % [ring_ids.size(), focusables.size()]
	var missing: int = 0
	for id: int in expected_ids:
		if not ring_ids.has(id):
			missing += 1
	if missing > 0:
		return "unreachable-controls=%d" % missing
	if focusables.size() != expected.size():
		return "foreign-focusables=%d" % (focusables.size() - expected.size())
	return "ok"


# --------------------------------------------------------------------------
# WS3 Phase-B in-room lobby integration proof (emotes / map preview /
# autonomous backdrop). Runs after the layout measurement of the room state.
# --------------------------------------------------------------------------


func _strip_comments(source: String) -> String:
	var kept: PackedStringArray = PackedStringArray()
	for line: String in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)


func _rects_inside(rects: Array, safe: Rect2, slack: float = 0.75) -> bool:
	var grown: Rect2 = safe.grow(slack)
	for raw: Variant in rects:
		if not grown.encloses(raw as Rect2):
			return false
	return true


func _points_inside(points: PackedVector2Array, bounds: Rect2,
		slack: float = 1.5) -> bool:
	var grown: Rect2 = bounds.grow(slack)
	for point: Vector2 in points:
		if not grown.has_point(point):
			return false
	return true


func _audit_lobby_integration(lobby: Node, label: String) -> void:
	var source: String = FileAccess.get_file_as_string(
		"res://scripts/ui/lobby_menu.gd")
	_check(not source.contains("_ReactionBubbles")
		and not source.contains("_lobby_preview_tex")
		and not source.contains("para_mat")
		and not source.contains("parallelogram_clip"),
		"%s lobby_menu.gd still references a legacy bubble/preview stack"
			% label)
	var code_only: String = _strip_comments(source)
	_check(not code_only.contains("menu_hover_backdrop")
		and not code_only.contains("MenuHoverBackdrop")
		and not code_only.contains("hover_art")
		and not code_only.contains("focus_art")
		and not code_only.contains("crossfade_to"),
		"%s lobby backdrop still has hover/focus wiring" % label)
	# --- text-only emotes ---------------------------------------------------
	var bubbles: Node = lobby.get("_bubbles") as Node
	_check(bubbles != null and bubbles.get_script() == LobbyEmoteOverlay,
		"%s in-room lobby does not use the text-only LobbyEmoteOverlay"
			% label)
	if bubbles != null:
		_check(bubbles.get_child_count() == 0,
			"%s in-room emote overlay owns chrome nodes" % label)
		_check((bubbles as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"%s in-room emote overlay can steal a click" % label)
		var safe: Rect2 = bubbles.call("safe_rect") as Rect2
		var rects: Array = bubbles.call("debug_rects") as Array
		_check(not rects.is_empty(),
			"%s in-room lobby has no seeded synced emotes" % label)
		_check(_rects_inside(rects, safe),
			"%s in-room emote spawns leave the safe margins (safe=%s rects=%s)"
				% [label, str(safe), str(rects)])
	# --- slanted map preview ------------------------------------------------
	var preview: Node = lobby.get("_map_preview") as Node
	_check(preview != null and preview.get_script() == LobbyMapPreview,
		"%s in-room map preview is not the slanted LobbyMapPreview" % label)
	if preview != null:
		var base: PackedVector2Array = preview.call("base_points") \
			as PackedVector2Array
		_check(base.size() == 4 and base[0].x - base[3].x >= 8.0,
			"%s in-room preview plate is not visibly slanted" % label)
		var bounds: Rect2 = preview.call("content_bounds") as Rect2
		_check(_points_inside(preview.call("frame_points") as PackedVector2Array,
			bounds), "%s in-room preview motion leaves its bounds" % label)
		var info: Dictionary = preview.call("motion_info") as Dictionary
		var limits: Dictionary = preview.call("motion_bounds") as Dictionary
		_check(absf(float(info.get("sway_px", 0.0)))
			<= float(limits.get("max_sway_px", 0.0)) + 0.01
			and absf(float(info.get("tilt_px", 0.0)))
			<= float(limits.get("max_tilt_px", 0.0)) + 0.01,
			"%s in-room preview motion exceeds its declared bounds" % label)
		_check(bounds.encloses(preview.call("title_band_rect") as Rect2),
			"%s in-room preview title scrim band sits outside the card" % label)
		var title: Label = lobby.get("_lobby_map_title") as Label
		var chip: Label = lobby.get("_lobby_mode_chip_label") as Label
		var stack: Control = preview.get_parent() as Control
		_check(title != null and title.is_visible_in_tree() and title.text != "",
			"%s in-room map title missing or hidden" % label)
		_check(chip != null and chip.is_visible_in_tree() and chip.text != "",
			"%s in-room mode chip missing or hidden" % label)
		if title != null and stack != null:
			_check(stack.get_global_rect().grow(3.0).encloses(
				title.get_global_rect()),
				"%s in-room map title is clipped by the preview card" % label)
	# --- independent, hover/focus-free backdrop -----------------------------
	var background: Node = lobby.get_node_or_null("Background")
	var art: Node = null
	if background != null:
		art = lobby.call("_find_art_backdrop", background) as Node
	_check(art != null, "%s lobby backdrop ArtBackdrop unreachable" % label)
	if art != null:
		_check(bool(art.get("auto_advance")),
			"%s lobby backdrop auto-advance is OFF" % label)
		var names: PackedStringArray = art.call("slide_names") as PackedStringArray
		_check(names.size() >= 2,
			"%s lobby backdrop pool has fewer than two plates (%d)"
				% [label, names.size()])
		art.set("slide_seconds_min", 600.0)
		art.set("slide_seconds_max", 600.0)
		art.call("reset_schedule")
		var index_before: int = int(art.call("current_index"))
		var name_before: String = str(art.call("current_slide_name"))
		for key: String in ["_leave_button", "_start_button", "_map_button",
				"_change_mode_button"]:
			var control := lobby.get(key) as Control
			if control == null:
				continue
			control.grab_focus()
			control.mouse_entered.emit()
			control.mouse_exited.emit()
		var buttons: Array = lobby.get("_reaction_buttons") as Array
		for raw: Variant in buttons:
			var button := raw as Button
			if button != null:
				button.grab_focus()
				button.mouse_entered.emit()
				button.mouse_exited.emit()
		if preview != null:
			preview.call("set_hover", true)
		await process_frame
		await process_frame
		_check(int(art.call("current_index")) == index_before
			and str(art.call("current_slide_name")) == name_before,
			"%s hover/focus changed the lobby backdrop slide" % label)
		_check(bool(art.get("auto_advance")),
			"%s hover/focus paused the lobby slideshow" % label)
		if preview != null:
			preview.call("set_hover", false)
	var emote_count: int = 0
	if bubbles != null and bubbles.has_method("bubble_count"):
		emote_count = int(bubbles.call("bubble_count"))
	print("UI_AUDIT %s lobby-integration emotes=%d preview=%s backdrop=%s"
		% [label, emote_count,
		"slanted" if preview != null else "MISSING",
		"autonomous" if art != null else "MISSING"])


# --------------------------------------------------------------------------
# Result-card layout proof (the Phase B end-screen helper).
# --------------------------------------------------------------------------


func _audit_result_cards() -> void:
	var helper_path: String = RESULT_SCREEN_SCRIPT
	if not ResourceLoader.exists(helper_path):
		print("UI_AUDIT result-cards: helper not present yet, skipped")
		return
	# WS5P3-14: the client's LEAVE LOBBY gate must own ESC. The gate now asks the
	# pause menu to suspend itself through a real API instead of reaching into a
	# CanvasLayer, so both ends of that contract must stay wired.
	var result_source: String = FileAccess.get_file_as_string(helper_path)
	_check(result_source.contains("set_input_suspended")
		and result_source.contains("pause_isolation"),
		"result-card confirm gate lost its PauseMenu ESC-suspension wiring")
	var pause_script: GDScript = load(PAUSE_MENU_SCRIPT) as GDScript
	var pause_api: bool = false
	if pause_script != null:
		for method: Dictionary in pause_script.get_script_method_list():
			if str(method.get("name", "")) == "set_input_suspended":
				pause_api = true
				break
	_check(pause_api,
		"pause_menu.gd lost set_input_suspended (WS5P3-14 isolation API)")
	var helper_script: GDScript = load(helper_path) as GDScript
	var helper: RefCounted = helper_script.new() as RefCounted
	var cases: Array[Dictionary] = [
		# WS3 0.8.7: every mode's host AND non-host action set is measured, plus
		# the solo variants, so the "Waiting for host..." + LEAVE LOBBY card and
		# the unchanged host card can never regress in layout.
		{"mode": "racing", "multiplayer": true, "is_host": true},
		{"mode": "racing", "multiplayer": true, "is_host": false},
		{"mode": "racing", "multiplayer": false, "is_host": false},
		{"mode": "knockout", "multiplayer": true, "is_host": true},
		{"mode": "knockout", "multiplayer": true, "is_host": false},
		{"mode": "cargo_rush", "multiplayer": true, "is_host": true},
		{"mode": "cargo_rush", "multiplayer": true, "is_host": false},
		{"mode": "bomb_tag", "multiplayer": true, "is_host": true},
		{"mode": "bomb_tag", "multiplayer": true, "is_host": false},
		{"mode": "bomb_tag", "multiplayer": false, "is_host": false},
	]
	for case: Dictionary in cases:
		for size: Vector2i in VIEWPORTS:
			root.size = size
			await process_frame
			var host := Control.new()
			host.size = root.get_visible_rect().size
			root.add_child(host)
			var card: Dictionary = helper.call("build_audit_card", host, case)
			await create_timer(0.3).timeout
			var nav: Node = _menu_nav()
			if nav != null:
				nav.call("refresh")
			await process_frame
			await process_frame
			var role: String = ""
			if bool(case.get("multiplayer", false)):
				role = ":host" if bool(case.get("is_host", true)) else ":client"
			var label: String = "result:%s%s%s@%dx%d" % [case.get("mode"),
				":mp" if bool(case.get("multiplayer")) else ":solo", role,
				size.x, size.y]
			var design: Vector2 = root.get_visible_rect().size
			var outside: Array[String] = helper.call("audit_outside", card, design)
			_check(outside.is_empty(), "%s result-card controls outside the viewport: %s"
				% [label, ", ".join(outside)])
			var ring_ok: bool = bool(helper.call("audit_focus_ring", card))
			_check(ring_ok, "%s result-card focus ring is broken" % label)
			await _audit_result_actions(helper, card, case, label)
			print("UI_AUDIT %s design=%.0fx%.0f fit=%s focus=%s actions=%s"
				% [label, design.x, design.y,
				"ok" if outside.is_empty() else "OVERFLOW",
				"ok" if ring_ok else "BROKEN",
				str(helper.call("action_set", card))])
			_measured += 1
			host.queue_free()
			await process_frame


func _audit_result_actions(helper: RefCounted, card: Dictionary, case: Dictionary,
		label: String) -> void:
	## WS3: the host keeps its navigation; a multiplayer client only ever sees the
	## animated waiting status + LEAVE LOBBY, and its leave action is confirm-
	## gated by the shared dark-slanted Cancel/Leave dialog.
	var actions: Array = helper.call("action_set", card)
	var multiplayer: bool = bool(case.get("multiplayer", false))
	var is_host: bool = bool(case.get("is_host", true))
	if multiplayer and not is_host:
		_check(actions == ["LEAVE LOBBY"],
			"%s client action set must be [LEAVE LOBBY], got %s"
				% [label, str(actions)])
		var waiting: String = str(helper.call("waiting_text", card))
		_check(waiting.begins_with("Waiting for host"),
			"%s client waiting status missing (got '%s')" % [label, waiting])
		helper.call("request_leave", card)
		await create_timer(0.08).timeout
		await process_frame
		var confirm: Dictionary = helper.call("confirm_state", card) as Dictionary
		_check(bool(confirm.get("visible", false)),
			"%s LEAVE LOBBY did not open the confirm gate" % label)
		_check(str(confirm.get("question", ""))
			== "Leave lobby and return to Main Menu?",
			"%s confirm question is wrong (%s)" % [label, confirm.get("question")])
		var buttons: Array = confirm.get("buttons", []) as Array
		_check(buttons == ["Cancel", "Leave"],
			"%s confirm buttons must be [Cancel, Leave], got %s"
				% [label, str(buttons)])
		var design: Vector2 = root.get_visible_rect().size
		var outside: Array[String] = helper.call("audit_outside", card, design)
		_check(outside.is_empty(),
			"%s open confirm escapes the viewport: %s" % [label, ", ".join(outside)])
		helper.call("confirm_cancel", card)
		await process_frame
		_check(not bool(helper.call("confirm_visible", card)),
			"%s Cancel did not close the confirm gate" % label)
		return
	# Host / solo keep the unchanged action contract.
	var expected: Array[String] = []
	if str(case.get("mode", "")) in ["cargo_rush", "knockout", "bomb_tag"]:
		expected.append("PLAY AGAIN")
	else:
		expected.append("RACE AGAIN")
	if multiplayer:
		expected.append("BACK TO LOBBY")
	else:
		expected.append("BACK TO MODES")
	expected.append("MAIN MENU")
	_check(actions == expected, "%s host action set changed: expected %s, got %s"
		% [label, str(expected), str(actions)])
	_check(str(helper.call("waiting_text", card)) == "",
		"%s host card must not show the client waiting status" % label)



# --------------------------------------------------------------------------
# Live mode-scene cards (slow: boots real 3D minigame scenes).
# Enabled with CART_UI_MODE_CARDS=1 so the default audit stays fast.
# --------------------------------------------------------------------------


func _audit_live_mode_cards() -> void:
	var cases: Array[Dictionary] = [
		{"id": "cargo_rush", "path": "res://scenes/minigames/cargo_rush.tscn",
			"method": "_show_result"},
		{"id": "knockout", "path": "res://scenes/minigames/knockout.tscn",
			"method": "_show_result_card"},
		{"id": "bomb_tag", "path": "res://scenes/minigames/bomb_tag.tscn",
			"method": "_show_result_card"},
	]
	for case: Dictionary in cases:
		var path: String = str(case["path"])
		if not ResourceLoader.exists(path):
			_fail("%s: scene missing" % case["id"])
			continue
		for window_size: Vector2i in VIEWPORTS:
			root.size = window_size
			await process_frame
			var instance: Node = (load(path) as PackedScene).instantiate()
			root.add_child(instance)
			current_scene = instance
			await create_timer(2.5).timeout
			if not instance.has_method(str(case["method"])):
				_fail("%s: %s missing" % [case["id"], case["method"]])
				instance.queue_free()
				continue
			instance.callv(str(case["method"]), [])
			await create_timer(0.6).timeout
			var card_root: Node = instance.get("_result_root") as Node
			if card_root == null:
				_fail("%s: no result card built" % case["id"])
				instance.queue_free()
				continue
			var nav: Node = _menu_nav()
			if nav != null:
				nav.call("refresh")
			await process_frame
			await process_frame
			var design: Vector2 = root.get_visible_rect().size
			var issues: Dictionary = {"legacy": [], "overflow": [], "counts": {}}
			_collect(card_root, design, issues)
			var expected: Array[Control] = []
			_collect_focusables(card_root, expected)
			var focus_state: String = await _focus_state(card_root, expected)
			var label: String = "live-card:%s@%dx%d" % [case["id"],
				window_size.x, window_size.y]
			_check((issues["legacy"] as Array).is_empty(),
				"%s legacy theme controls: %s" % [label,
				", ".join(issues["legacy"] as Array)])
			_check((issues["overflow"] as Array).is_empty(),
				"%s controls outside the viewport: %s" % [label,
				", ".join(issues["overflow"] as Array)])
			_check(focus_state == "ok",
				"%s focus unavailable: %s" % [label, focus_state])
			print("UI_AUDIT %s legacy=%d overflow=%d focus=%s"
				% [label, (issues["legacy"] as Array).size(),
				(issues["overflow"] as Array).size(), focus_state])
			_measured += 1
			instance.queue_free()
			await process_frame
			await process_frame
