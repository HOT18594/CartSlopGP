extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Minigame and map picker.
##
## The list is generated from TrackDefs, so every map and minigame in the
## registry appears here with its name, blurb and preview. A minigame card is
## labelled MINIGAME and opens a theme picker instead of a race blurb; its
## chosen theme id is written to GameSettings.selected_minigame, the same field
## cargo_rush.gd already reads. A missing preview falls back to the existing
## meadow_loop.png image; no illustrated placeholder is invented.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")

const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const PREVIEW_DIR: String = "res://assets/ui/minigames/"
const FALLBACK_PREVIEW: String = "meadow_loop.png"
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

var _body: VBoxContainer
var _title: Label
var _map_list: VBoxContainer
var _map_cards: Array[Button] = []
var _detail_panel: PanelContainer
var _detail_title: Label
var _theme_pill: Button
var _theme_ids: PackedStringArray = PackedStringArray()
var _selected_theme: String = ""
var _vehicle_button: Button
var _play_button: Button
var _back_button: Button
var _selected: int = 0


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_body = $Center/Panel/Body
	_build_ui()
	_initial_index()
	call_deferred("_enter")
	if OS.get_environment("CART_MINIGAMES_SELFTEST") == "1":
		_run_selftest.call_deferred()


func _enter() -> void:
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()
	MenuNav.focus(_play_button if not _play_button.disabled else _back_button)


func _unhandled_input(event: InputEvent) -> void:
	## Escape is the same as BACK, with the lobby routing handled by _on_back.
	if event.is_action_pressed("ui_cancel") and not SceneLoader.is_busy():
		_on_back()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override("font_size", UiKit.TITLE_SIZE)
	_title.add_theme_color_override("font_color", UiPalette.INK)
	# The screen hosts map cards and minigame cards, so the title names the
	# event picker rather than only the race maps.
	_title.text = "MINIGAMES"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	header.add_child(_title)
	_back_button = _button("BACK", UiPalette.RED, 46, 17)
	_back_button.custom_minimum_size = Vector2(124, 46)
	_back_button.pressed.connect(_on_back)
	header.add_child(_back_button)
	_body.add_child(header)

	# Vertical cards, not a single hero image: every map keeps its own name,
	# blurb and preview visible at the same time. The CentreContainer sizes the
	# panel to its minimum, and a ScrollContainer's minimum height is zero, so
	# without an explicit floor the whole card list would collapse.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(scroll)
	_map_list = VBoxContainer.new()
	_map_list.custom_minimum_size = Vector2(640, 0)
	_map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_map_list)
	_map_cards.clear()
	for index in TrackDefs.PRESETS.size():
		var card: Button = _make_map_card(index, TrackDefs.PRESETS[index])
		_map_list.add_child(card)
		_map_cards.append(card)

	_build_detail_panel()

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(action_row)

	_vehicle_button = _button("VEHICLE: SHOPPING CART", Color("8ed8f6"), 60, 17)
	_vehicle_button.custom_minimum_size = Vector2(230, 60)
	_vehicle_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_vehicle_button.tooltip_text = "Pick the cart you will race."
	_vehicle_button.pressed.connect(_on_change_vehicle)
	# Hosts already pick a car in the lobby's HOST SETTINGS. Showing a second
	# vehicle button here was a pointless extra click.
	_vehicle_button.visible = not Network.is_session_active()
	action_row.add_child(_vehicle_button)

	_play_button = _button("RACE", UiPalette.YELLOW, 60, 22)
	_play_button.custom_minimum_size = Vector2(300, 60)
	_play_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_play_button.pressed.connect(_on_play)
	action_row.add_child(_play_button)

	_refresh_vehicle()


func _build_detail_panel() -> void:
	## A minigame is not a spline track, so it gets its own detail block with
	## the arena theme picker. The selected id is the exact value cargo_rush.gd
	## resolves from GameSettings.selected_minigame; no second store is added.
	_detail_panel = PanelContainer.new()
	_detail_panel.name = "MinigameDetails"
	_detail_panel.visible = false
	_detail_panel.add_theme_stylebox_override("panel",
		UiKit.flat_card(Color(1.0, 1.0, 1.0, 0.42)))
	_body.add_child(_detail_panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 12)
	_detail_panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	pad.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	_detail_title = Label.new()
	_detail_title.theme_type_variation = &"TitleLabel"
	_detail_title.add_theme_font_size_override("font_size", 24)
	_detail_title.add_theme_color_override("font_color", UiPalette.INK)
	_detail_title.add_theme_constant_override("outline_size", 0)
	header.add_child(_detail_title)
	var badge := PanelContainer.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = UiPalette.YELLOW
	badge_style.set_corner_radius_all(8)
	badge_style.content_margin_left = 8.0
	badge_style.content_margin_right = 8.0
	badge_style.content_margin_top = 2.0
	badge_style.content_margin_bottom = 3.0
	badge.add_theme_stylebox_override("panel", badge_style)
	header.add_child(badge)
	var badge_label := Label.new()
	badge_label.text = "MINIGAME"
	badge_label.add_theme_font_size_override("font_size", 12)
	badge_label.add_theme_color_override("font_color", UiPalette.INK)
	badge.add_child(badge_label)

	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 12)
	column.add_child(theme_row)
	var theme_label := Label.new()
	theme_label.text = "ARENA THEME"
	theme_label.add_theme_font_size_override("font_size", 14)
	theme_label.add_theme_color_override("font_color", UiPalette.INK)
	theme_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	theme_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theme_row.add_child(theme_label)
	_theme_pill = UiKit.segmented(PackedStringArray(), [], 0, 150.0, 46.0)
	_theme_pill.name = "ThemePill"
	_theme_pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	_theme_pill.tooltip_text = "Pick which arena this minigame is played in."
	_theme_pill.connect("option_changed", _on_theme_changed)
	theme_row.add_child(_theme_pill)


func _make_map_card(index: int, preset: Dictionary) -> Button:
	var minigame: bool = TrackDefs.is_minigame(preset)
	var card: Button = _button("", _accent_for(preset).lightened(0.35), 120, 20)
	card.name = "MapCard_%s" % str(preset.get("id", "map"))
	card.tooltip_text = str(preset.get("desc", ""))
	card.pressed.connect(_select.bind(index))

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	card.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(176, 96)
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = UiPalette.OUTLINE
	frame_style.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", frame_style)
	row.add_child(frame)

	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture: Texture2D = _preview_texture(preset)
	if texture != null:
		preview.texture = texture
	frame.add_child(preview)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 2)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var name_label := Label.new()
	name_label.text = str(preset.get("name", "MAP"))
	name_label.theme_type_variation = &"TitleLabel"
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", UiPalette.INK)
	name_label.add_theme_constant_override("outline_size", 0)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_label)
	var desc := Label.new()
	desc.text = str(preset.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.max_lines_visible = 1 if minigame else 2
	desc.clip_text = true
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.custom_minimum_size = Vector2(0, 20 if minigame else 38)
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", UiPalette.MUTED)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(desc)
	if minigame:
		# The detail line names every arena variant, so the card reads as a
		# minigame event instead of a fourth race track.
		var detail := Label.new()
		detail.name = "Detail"
		detail.text = _minigame_detail(preset)
		detail.clip_text = true
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		detail.add_theme_font_size_override("font_size", 13)
		detail.add_theme_color_override("font_color", UiPalette.BODY_BLUE)
		detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.add_child(detail)
	return card


func _minigame_detail(preset: Dictionary) -> String:
	var names: PackedStringArray = TrackDefs.theme_names(preset)
	if names.is_empty():
		return "MINIGAME"
	return "MINIGAME  ·  " + " · ".join(names)


func _button(text: String, color: Color, height: int, font_size: int) -> Button:
	return UiKit.tile(text, color, float(height), font_size)


func _initial_index() -> void:
	# selected_map is the dedicated race map. selected_minigame carries the
	# cargo arena theme, so only that field can restore the minigame card.
	var selection: String = GameSettings.selected_minigame
	if TrackDefs.has_theme_id(selection):
		_selected = TrackDefs.index_of(selection)
	else:
		_selected = TrackDefs.index_of(GameSettings.selected_map)
	_select(_selected)


func _accent_for(preset: Dictionary) -> Color:
	# A minigame is not a surface-driven track, so it gets the event accent
	# instead of the grass default.
	if TrackDefs.is_minigame(preset):
		return UiPalette.CYAN
	var raw: Variant = preset.get("surfaces", [])
	if raw is Array:
		for entry: Variant in raw as Array:
			if not (entry is Dictionary):
				continue
			match str((entry as Dictionary).get("kind", "normal")):
				"wet":
					return UiPalette.BLUE
				"ice":
					return UiPalette.CYAN
	return UiPalette.GRASS


func _preview_texture(preset: Dictionary) -> Texture2D:
	var file: String = str(preset.get("preview", ""))
	var path: String = PREVIEW_DIR + file
	if file.is_empty() or not ResourceLoader.exists(path):
		path = PREVIEW_DIR + FALLBACK_PREVIEW
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _select(index: int) -> void:
	if TrackDefs.PRESETS.is_empty():
		_selected = 0
		_play_button.disabled = true
		_play_button.text = "UNAVAILABLE"
		return
	_selected = clampi(index, 0, TrackDefs.PRESETS.size() - 1)
	for i in _map_cards.size():
		var preset: Dictionary = TrackDefs.PRESETS[mini(i, TrackDefs.PRESETS.size() - 1)]
		var fill: Color = UiPalette.YELLOW if i == _selected \
			else _accent_for(preset).lightened(0.35)
		_map_cards[i].set("fill_color", fill)
	var data: Dictionary = TrackDefs.PRESETS[_selected]
	_update_detail(data)
	_play_button.disabled = not bool(data.get("available", true))
	_refresh_play_label(data)
	# The minigame detail block appears and disappears with the card, so the
	# focus map must be rebuilt to include or drop the theme strip.
	MenuNav.refresh()


func _update_detail(data: Dictionary) -> void:
	if _detail_panel == null:
		return
	var minigame: bool = TrackDefs.is_minigame(data)
	_detail_panel.visible = minigame
	if not minigame:
		return
	var themes: PackedStringArray = TrackDefs.theme_ids(data)
	if themes != _theme_ids:
		_theme_ids = themes
		var labels: PackedStringArray = TrackDefs.theme_names(data)
		var values: Array = []
		for id: String in themes:
			values.append(id)
		_theme_pill.call("configure", labels, values, 0)
	_theme_pill.visible = not _theme_ids.is_empty()
	_detail_title.text = str(data.get("name", "MINIGAME"))
	var wanted: String = _theme_for(data)
	var theme_index: int = maxi(_theme_ids.find(wanted), 0)
	_theme_pill.call("set_index", theme_index)
	_selected_theme = wanted


func _theme_for(preset: Dictionary) -> String:
	## cargo_rush.gd resolves its arena from GameSettings.selected_minigame, so
	## the picker writes that same field. The screen's live choice wins over the
	## saved one, then the registry default is the last resort.
	var themes: PackedStringArray = TrackDefs.theme_ids(preset)
	if themes.has(_selected_theme):
		return _selected_theme
	if themes.has(GameSettings.selected_minigame):
		return GameSettings.selected_minigame
	return TrackDefs.default_theme(preset)


func _on_theme_changed(value: Variant) -> void:
	_selected_theme = str(value)
	if _selected >= 0 and _selected < TrackDefs.PRESETS.size():
		_refresh_play_label(TrackDefs.PRESETS[_selected])


func _refresh_play_label(data: Dictionary) -> void:
	if not bool(data.get("available", true)):
		_play_button.text = "UNAVAILABLE"
		return
	var minigame: bool = TrackDefs.is_minigame(data)
	var verb: String = "PLAY" if minigame else "RACE"
	if Network.is_session_active():
		verb = "SELECT MINIGAME" if minigame else "SELECT MAP"
	_play_button.text = "%s  ·  %s" % [verb, str(data.get("name", "MAP"))]


func _scene_for(data: Dictionary) -> String:
	## Maps live in the race scene; a minigame names the scene it loads.
	return str(data.get("scene", RACE_SCENE))


func _refresh_vehicle() -> void:
	var entry: Dictionary = Catalog.find(GameSettings.minigame_vehicle)
	if entry.is_empty():
		entry = Catalog.find(Catalog.DEFAULT_ID)
	_vehicle_button.text = "VEHICLE: " + str(entry.get("name", "SHOPPING CART"))
	_vehicle_button.set("fill_color", Color("8ed8f6"))


func _on_change_vehicle() -> void:
	GameSettings.vehicle_return_scene = MINIGAMES_SCENE
	GameSettings.vehicle_return_title = "MINIGAMES"
	GameSettings.vehicle_edit_minigame = true
	SceneLoader.go_to(VEHICLE_SCENE, "VEHICLE", "Choose your ride")


func _on_play() -> void:
	if TrackDefs.PRESETS.is_empty():
		return
	var data: Dictionary = TrackDefs.PRESETS[_selected]
	if not bool(data.get("available", true)):
		return
	var minigame: bool = TrackDefs.is_minigame(data)
	if minigame:
		# A minigame stores its chosen arena theme in selected_minigame, the
		# exact field cargo_rush.gd resolves; configure_session copies it into
		# Network.session_minigame for online peers. The race map is untouched.
		GameSettings.set_selected_minigame(_theme_for(data))
	else:
		# Maps live in their dedicated field, which grass_race.gd now reads.
		GameSettings.set_selected_map(str(data.get("id", TrackDefs.DEFAULT_ID)))
	if Network.is_session_active():
		if not Network.is_host:
			return
		GameSettings.set_multiplayer_mode(GameSettings.GAME_MINIGAMES)
		Network.configure_session(GameSettings.GAME_MINIGAMES, GameSettings.bots_enabled,
			GameSettings.effective_bot_count())
		# Picking a card only updates the lobby. The host starts from START.
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER",
			"Minigame selected" if minigame else "Map selected")
		return
	GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	SceneLoader.go_to(_scene_for(data), str(data.get("name", "RACE")),
		str(data.get("hint", "3 LAPS TO WIN")))


func _run_selftest() -> void:
	## Headless verification hook (CART_MINIGAMES_SELFTEST=1): press the
	## minigame card through the same signal a player uses, then report the
	## scene the normal PLAY path would load. Costs one env lookup per open.
	var minigame_index: int = -1
	for index in TrackDefs.PRESETS.size():
		if TrackDefs.is_minigame(TrackDefs.PRESETS[index]):
			minigame_index = index
			break
	if minigame_index < 0 or minigame_index >= _map_cards.size():
		print("MINIGAMES_SELFTEST missing_minigame")
		get_tree().quit(1)
		return
	_map_cards[minigame_index].emit_signal("pressed")
	await get_tree().process_frame
	var data: Dictionary = TrackDefs.PRESETS[_selected]
	# Simulate picking the last arena tile: the value the normal PLAY path would
	# write must be that exact theme id, and grass_race must still get a map.
	var picked: String = _selected_theme
	if _theme_ids.size() > 1:
		_theme_pill.call("set_index", _theme_ids.size() - 1, true)
		picked = _theme_for(data)
	var theme_ok: bool = not _theme_ids.is_empty() \
		and picked == _theme_ids[_theme_ids.size() - 1]
	# The new theme strip has to be a real focus stop with the shared ring.
	var focus_ok: bool = _theme_pill.has_theme_stylebox_override("focus") \
		and MenuNav.focus(_theme_pill) \
		and MenuNav.focused_control() == _theme_pill
	var race_preset: Dictionary = TrackDefs.get_preset(picked)
	var race_ok: bool = TrackDefs.is_map(race_preset)
	var scene_path: String = _scene_for(data)
	var expected: String = str(data.get("scene", ""))
	print("MINIGAMES_SELFTEST card=%s kind=%s scene=%s theme=%s detail=%s "
		% [_map_cards[minigame_index].name, TrackDefs.kind_of(data), scene_path,
		picked, str(_detail_panel.visible)]
		+ "themes=%s race_preset=%s focus=%s"
		% [str(TrackDefs.theme_ids(data)), str(race_preset.get("id", "")),
		str(focus_ok)])
	get_tree().quit(0 if scene_path == expected and expected != "" \
		and not TrackDefs.is_map(data) and theme_ok and race_ok \
		and focus_ok else 1)


func _on_back() -> void:
	if Network.is_session_active():
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "Back to the lobby")
	else:
		SceneLoader.go_to(PLAY_MENU_SCENE, "PLAY")
