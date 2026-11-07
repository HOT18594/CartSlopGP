extends Node
## Headless validation for the 0.6.3 UI pass. Run with:
##   godot --headless --path . res://tools/ui_pass_check.tscn
## Checks scene instantiation, changelog formatting, loading percentage,
## stat-bar ratios and the new centralised arrow-key navigation.

const SCENES: PackedStringArray = [
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/play_menu.tscn",
	"res://scenes/ui/lobby_menu.tscn",
	"res://scenes/ui/minigames_menu.tscn",
	"res://scenes/ui/vehicle_select.tscn",
	"res://scenes/ui/settings_menu.tscn",
	"res://scenes/ui/update_panel.tscn",
	"res://scenes/ui/changelog_panel.tscn",
	"res://scenes/ui/scene_loader.tscn",
	"res://scenes/ui/room_browser.tscn",
]

var _failures: PackedStringArray = []


func _ok(condition: bool, message: String) -> void:
	if condition:
		print("  OK  ", message)
	else:
		_failures.append(message)
		print(" FAIL ", message)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	await _check_scenes()
	await _check_changelog()
	await _check_loading()
	await _check_stats()
	await _check_lobby()
	await _check_browser()
	await _check_play_states()
	await _check_art()
	await _check_nav()
	print("UI_PASS_CHECK: %d failure(s)" % _failures.size())
	for failure: String in _failures:
		print("  - ", failure)
	get_tree().quit(1 if _failures.size() > 0 else 0)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _check_scenes() -> void:
	print("[scenes]")
	for path: String in SCENES:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			_ok(false, "load " + path)
			continue
		var node: Node = packed.instantiate()
		add_child(node)
		await _frames(3)
		_ok(is_instance_valid(node), "instantiate " + path.get_file())
		if path.ends_with("changelog_panel.tscn") and node.has_method("open"):
			node.call("open")
			await _frames(3)
		if path.ends_with("settings_menu.tscn") and node.has_method("open"):
			node.call("open")
			await _frames(3)
		node.queue_free()
		await _frames(2)


func _check_changelog() -> void:
	print("[changelog]")
	var packed: PackedScene = load("res://scenes/ui/changelog_panel.tscn") as PackedScene
	var panel: Node = packed.instantiate()
	add_child(panel)
	panel.add_to_group("nav_scope")
	await _frames(2)
	panel.call("open")
	await _frames(3)
	var pages: Array = panel.get("_pages")
	_ok(pages.size() >= 1 and pages.size() <= 5,
		"compact player notes fit in %d page(s)" % pages.size())
	var text: RichTextLabel = panel.get_node("Panel/Body/ChangelogText")
	_ok(text.text.contains("•"), "bullets use a dot glyph")
	var indented: int = 0
	for line: String in text.text.split("\n"):
		if line.begins_with("    ") or line.begins_with("   "):
			indented += 1
	_ok(indented == 0, "no indented bullet lines (found %d)" % indented)
	_ok(not text.text.contains("[b]v0.7.0"), "version is 0.6.3 in the changelog")
	var nav: Node = get_node_or_null("/root/MenuNav")
	if nav != null:
		nav.call("refresh")
	var back: Button = panel.get_node("Panel/Body/PageRow/BackButton")
	back.grab_focus()
	await _frames(3)
	var before: int = int(panel.get("_page_index"))
	_press(KEY_RIGHT)
	await _frames(3)
	var after: int = int(panel.get("_page_index"))
	# A deliberately compact changelog may fit on one page, in which case
	# RIGHT must simply stay put instead of crashing or wrapping.
	if pages.size() > 1:
		_ok(after == before + 1, "RIGHT turned one changelog page (%d -> %d)" % [before, after])
	else:
		_ok(after == before, "single-page changelog stays on page 1")
	_ok(_name(get_viewport().gui_get_focus_owner()) == "BackButton",
		"paging did not also move focus (%s)" % _name(get_viewport().gui_get_focus_owner()))
	panel.call("close")
	panel.queue_free()
	await _frames(2)


func _check_loading() -> void:
	print("[loading]")
	var packed: PackedScene = load("res://scenes/ui/scene_loader.tscn") as PackedScene
	var layer: Node = packed.instantiate()
	add_child(layer)
	layer.show()
	var ui: Control = layer.get_node("UI")
	ui.set_progress(0.62, true)
	await _frames(3)
	var percent: Label = ui.get_node("Percent")
	_ok(percent.text == "62%", "percentage label reads 62%% (got '%s')" % percent.text)
	ui.set_indeterminate(true)
	await _frames(2)
	_ok(percent.text != "62%", "indeterminate mode replaces the number")
	ui.set_indeterminate(false)
	ui.set_progress(1.0, true)
	await _frames(2)
	_ok(percent.text == "100%", "100% snaps immediately")
	layer.queue_free()
	await _frames(2)


func _check_stats() -> void:
	print("[stats]")
	var Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
	var ranges: Dictionary = Catalog.stat_ranges()
	_ok(ranges.size() == Catalog.STAT_KEYS.size(), "stat ranges cover every key")
	var bad: int = 0
	for entry: Dictionary in Catalog.all():
		for key: String in Catalog.STAT_KEYS:
			var ratio: float = Catalog.stat_ratio(entry, key, ranges)
			if ratio < 0.0 or ratio > 1.0:
				bad += 1
	_ok(bad == 0, "all vehicle stat ratios stay in 0..1")
	var bar: Control = (load("res://scripts/ui/stat_bar.gd") as GDScript).new()
	add_child(bar)
	bar.set_ratio(0.7, true)
	await _frames(2)
	_ok(is_instance_valid(bar), "10-section bar instantiates")
	bar.queue_free()
	await _frames(2)



func _check_lobby() -> void:
	print("[lobby cleanup]")
	var packed: PackedScene = load("res://scenes/ui/lobby_menu.tscn") as PackedScene
	var lobby: Node = packed.instantiate()
	add_child(lobby)
	await _frames(4)
	var filler: int = 0
	var accent_bars: int = 0
	var stack: Array[Node] = [lobby]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label:
			var label_text: String = (node as Label).text.to_upper()
			if label_text.contains("HOW IT WORKS") or label_text.contains("CONTROLS") \
					or label_text.contains("ARROWS / WASD"):
				filler += 1
		if node is ColorRect:
			var rect: ColorRect = node as ColorRect
			var color: Color = rect.color
			var is_dark_rule: bool = color.r < 0.2 and color.g < 0.2 and color.b < 0.3
			if not is_dark_rule and rect.custom_minimum_size.y > 0.0 \
					and rect.custom_minimum_size.y <= 8.0:
				accent_bars += 1
		for child: Node in node.get_children():
			stack.append(child)
	_ok(filler == 0, "no filler cards or navigation hint text (found %d)" % filler)
	_ok(accent_bars == 0, "no coloured accent bars on cards (found %d)" % accent_bars)
	_ok(lobby.get("_browser") != null, "room browser popup is attached")
	_ok(lobby.get_node_or_null("%ServerPill") == null,
		"no PI SERVER status pill")
	var status_label: Label = lobby.get_node("%StatusLabel") as Label
	_ok(not status_label.visible or status_label.text.contains("Game server is down"),
		"status shows only a plain error, never server info")
	_ok((lobby.get("_code_label") as Control).get_parent()
			!= (lobby.get("_players_box") as Control).get_parent(),
		"room code and players sit in different columns")
	lobby.queue_free()
	await _frames(2)


func _check_browser() -> void:
	print("[room browser]")
	var packed: PackedScene = load("res://scenes/ui/room_browser.tscn") as PackedScene
	var browser: Node = packed.instantiate()
	add_child(browser)
	await _frames(3)
	browser.set("_mode", "online")
	browser.call("set_rooms", [
		{"name": "ETHAN", "players": 2, "room_code": "ABCDE", "state": "lobby"},
		{"name": "MIKE", "players": 1, "room_code": "ZZZZZ", "state": "lobby"},
	])
	await _frames(2)
	var list: VBoxContainer = browser.get_node("Center/Panel/Body/ListScroll/List")
	_ok(list.get_child_count() == 2, "both rooms listed")
	browser.set("_query", "ABCDE")
	browser.call("_rebuild_list")
	await _frames(2)
	_ok(list.get_child_count() == 1, "search filters by room code")
	browser.set("_query", "MIKE")
	browser.call("_rebuild_list")
	await _frames(2)
	_ok(list.get_child_count() == 1, "search filters by host name")
	browser.queue_free()
	await _frames(2)



func _check_play_states() -> void:
	print("[play states]")
	var packed: PackedScene = load("res://scenes/ui/play_menu.tscn") as PackedScene
	var menu: Node = packed.instantiate()
	add_child(menu)
	await _frames(4)
	_ok(menu.get("_state") == "picker", "PLAY opens on the two-card picker")
	_ok((menu.get("_cards_row") as Control).visible, "picker cards visible")
	menu.call("_on_single_card")
	await _frames(2)
	_ok(menu.get("_state") == "single", "SINGLE opens its own state")
	_ok((menu.get("_single_box") as Control).visible, "single options visible")
	_ok(not (menu.get("_cards_row") as Control).visible, "cards hidden in sub-state")
	menu.call("_on_back")
	await _frames(2)
	_ok(menu.get("_state") == "picker", "BACK returns to the picker")
	_ok(not menu.has_method("_on_multi"),
		"no redundant OPEN MULTIPLAYER LOBBY step")
	var play_source: String = ""
	var play_file: FileAccess = FileAccess.open(
		"res://scripts/ui/play_menu.gd", FileAccess.READ)
	if play_file != null:
		play_source = play_file.get_as_text()
		play_file.close()
	_ok(play_source.contains("SceneLoader.go_to(LOBBY_SCENE"),
		"MULTIPLAYER card goes straight to the lobby")
	var source: String = ""
	var file: FileAccess = FileAccess.open("res://scripts/ui/candy_button.gd", FileAccess.READ)
	if file != null:
		source = file.get_as_text()
		file.close()
	_ok(source.contains("base_x - side * reach"),
		"focus chevrons point inward, not outward")
	menu.queue_free()
	await _frames(2)



func _check_art() -> void:
	print("[ai art]")
	var packed: PackedScene = load("res://scenes/ui/minigames_menu.tscn") as PackedScene
	var menu: Node = packed.instantiate()
	add_child(menu)
	await _frames(3)
	var panel: Control = menu.get("_preview_panel")
	var slideshow: Node = null
	for child: Node in panel.get_children():
		if child.has_method("has_art"):
			slideshow = child
			break
	_ok(slideshow != null and bool(slideshow.call("has_art")),
		"game selector preview loads the AI art")
	if slideshow != null:
		var before: int = int(slideshow.get("_index"))
		slideshow.call("_advance")
		_ok(int(slideshow.get("_index")) != before,
			"preview slideshow advances to the next scene")
	var art_count: int = 0
	for file_name: String in ["bg_parking.png", "scene_arena.png", "scene_road.png",
			"scene_track_aerial.png", "scene_finish.png"]:
		if ResourceLoader.exists("res://assets/ui/art/" + file_name):
			art_count += 1
	_ok(art_count == 5, "all 5 supplied images are imported")
	var bg_source: String = ""
	var bg_file: FileAccess = FileAccess.open(
		"res://scripts/ui/menu_background.gd", FileAccess.READ)
	if bg_file != null:
		bg_source = bg_file.get_as_text()
		bg_file.close()
	_ok(bg_source.contains("bg_parking.png"),
		"menu shell uses the AI parking lot instead of the vector drawing")
	menu.queue_free()
	await _frames(2)


func _check_nav() -> void:
	print("[navigation]")
	var packed: PackedScene = load("res://scenes/ui/main_menu.tscn") as PackedScene
	var menu: Control = packed.instantiate()
	add_child(menu)
	menu.add_to_group("nav_scope")
	await _frames(6)
	var nav: Node = get_node_or_null("/root/MenuNav")
	_ok(nav != null, "MenuNav autoload exists")
	if nav != null:
		nav.call("refresh")
		await _frames(2)
		var items: Array = nav.get("_items")
		_ok(items.size() >= 4, "focus map found %d controls" % items.size())
	var viewport: Viewport = get_viewport()
	var play: Button = menu.get_node("%PlayButton")
	play.grab_focus()
	await _frames(2)
	if nav != null:
		for item: Control in nav.get("_items"):
			print("    focus map: ", item.name, " @ ", item.get_global_rect().get_center())
	var start: Control = viewport.gui_get_focus_owner()
	_press(KEY_DOWN)
	await _frames(3)
	var after_down: Control = viewport.gui_get_focus_owner()
	_ok(["SettingsButton", "ChangelogButton"].has(_name(after_down)),
		"DOWN from PLAY lands on the next row, got %s" % _name(after_down))
	_press(KEY_DOWN)
	await _frames(3)
	var after_down2: Control = viewport.gui_get_focus_owner()
	_ok(_name(after_down2) == "QuitButton",
		"second DOWN lands on QUIT, got %s" % _name(after_down2))
	_press(KEY_UP)
	await _frames(3)
	var after_up: Control = viewport.gui_get_focus_owner()
	_ok(["SettingsButton", "ChangelogButton"].has(_name(after_up)),
		"UP from QUIT returns to the middle row, got %s" % _name(after_up))
	_press(KEY_DOWN)
	_press(KEY_DOWN)
	await _frames(3)
	_press(KEY_D)
	await _frames(3)
	_ok(viewport.gui_get_focus_owner() != null, "WASD D keeps a valid focus")
	_press(KEY_TAB)
	await _frames(3)
	_ok(viewport.gui_get_focus_owner() != null, "Tab keeps a valid focus")
	menu.queue_free()
	await _frames(2)


func _name(control: Control) -> String:
	return control.name if control != null else "none"


func _press(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	var release := InputEventKey.new()
	release.keycode = keycode
	release.physical_keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)
