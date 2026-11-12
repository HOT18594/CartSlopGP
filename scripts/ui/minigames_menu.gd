extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Minigame map picker.
##
## The list is generated from TrackDefs, so every map in the registry appears
## here with its name, blurb and preview. A missing preview falls back to the
## existing meadow_loop.png image; no illustrated placeholder is invented.

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
	# From the lobby this screen is a map picker, not a vehicle picker.
	_title.text = "MAP SELECT"
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
	# blurb and preview visible at the same time.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
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


func _make_map_card(index: int, preset: Dictionary) -> Button:
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
	desc.max_lines_visible = 2
	desc.clip_text = true
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.custom_minimum_size = Vector2(0, 38)
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", UiPalette.MUTED)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(desc)
	return card


func _button(text: String, color: Color, height: int, font_size: int) -> Button:
	return UiKit.tile(text, color, float(height), font_size)


func _initial_index() -> void:
	_selected = TrackDefs.index_of(GameSettings.selected_minigame)
	_select(_selected)


func _accent_for(preset: Dictionary) -> Color:
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
	var available: bool = bool(data.get("available", true))
	_play_button.disabled = not available
	var verb: String = "SELECT MAP" if Network.is_session_active() else "RACE"
	_play_button.text = "%s  ·  %s" % [verb, str(data.get("name", "MAP"))] \
		if available else "UNAVAILABLE"


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
	var map_id: String = str(data.get("id", TrackDefs.DEFAULT_ID))
	# GameSettings.set_selected_minigame() still clamps to the legacy id, so set
	# the registry id directly and save through the same public path.
	GameSettings.selected_minigame = map_id
	GameSettings.save_settings()
	if Network.is_session_active():
		if not Network.is_host:
			return
		GameSettings.set_multiplayer_mode(GameSettings.GAME_MINIGAMES)
		Network.configure_session(GameSettings.GAME_MINIGAMES, GameSettings.bots_enabled,
			GameSettings.effective_bot_count())
		# Picking a map only updates the lobby. The host starts from START.
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "Map selected")
		return
	GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	SceneLoader.go_to(RACE_SCENE, str(data.get("name", "RACE")), "3 LAPS TO WIN")


func _on_back() -> void:
	if Network.is_session_active():
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "Back to the lobby")
	else:
		SceneLoader.go_to(PLAY_MENU_SCENE, "PLAY")
