extends Control
## Minigame picker.
##
## Only events that actually ship are listed. Every card uses a real in-game
## preview image; if an event has no preview, no artwork is drawn. There are no
## illustrated placeholders or "coming soon" cards pretending to be content.

const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")

const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const PILL_CYCLER: String = "res://scripts/ui/pill_cycler.gd"
const PREVIEW_DIR: String = "res://assets/ui/minigames/"
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const EVENTS: Array[Dictionary] = [
	{
		"id": "meadow_loop",
		"name": "MEADOW LOOP",
		"meta": "3 LAPS  ·  3 RIVALS  ·  4 BOOST PADS",
		"desc": "A winding dirt circuit through a dense grassy forest. Three laps, four boost pads, three rivals and a lot of dust.",
		"preview": "meadow_loop.png",
		"scene": "res://scenes/minigames/grass_race.tscn",
		"available": true,
		"accent": UiPalette.GRASS,
	},
]

var _body: VBoxContainer
var _preview_panel: PanelContainer
var _detail_name: Label
var _detail_meta: Label
var _detail_desc: Label
var _vehicle_button: Button
var _play_button: Button
var _back_button: Button
var _selected: int = 0


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_body = $Center/Panel/Body
	_build_ui()
	_select(0)
	_play_button.grab_focus()


func _build_ui() -> void:
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", UiPalette.INK)
	title.text = "MINIGAMES"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(title)

	var feature := HBoxContainer.new()
	feature.add_theme_constant_override("separation", 18)
	feature.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(feature)

	_preview_panel = PanelContainer.new()
	_preview_panel.custom_minimum_size = Vector2(430, 250)
	_preview_panel.clip_contents = true
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = UiPalette.OUTLINE
	preview_style.corner_radius_top_left = 20
	preview_style.corner_radius_top_right = 20
	preview_style.corner_radius_bottom_left = 20
	preview_style.corner_radius_bottom_right = 20
	preview_style.border_width_left = 5
	preview_style.border_width_top = 5
	preview_style.border_width_right = 5
	preview_style.border_width_bottom = 5
	preview_style.border_color = UiPalette.OUTLINE
	_preview_panel.add_theme_stylebox_override("panel", preview_style)
	feature.add_child(_preview_panel)

	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_panel.add_child(preview)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 6)
	feature.add_child(details)

	_detail_name = Label.new()
	_detail_name.theme_type_variation = &"TitleLabel"
	_detail_name.add_theme_font_size_override("font_size", 34)
	_detail_name.add_theme_color_override("font_color", UiPalette.INK)
	details.add_child(_detail_name)

	_detail_meta = Label.new()
	_detail_meta.add_theme_font_size_override("font_size", 14)
	_detail_meta.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	details.add_child(_detail_meta)

	_detail_desc = Label.new()
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.add_theme_font_size_override("font_size", 16)
	_detail_desc.add_theme_color_override("font_color", UiPalette.INK)
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(_detail_desc)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	details.add_child(action_row)

	_vehicle_button = Button.new()
	_vehicle_button.set_script(load(PILL_CYCLER))
	_vehicle_button.set("corner_radius", 24)
	_vehicle_button.set("shadow_offset", 6)
	_vehicle_button.custom_minimum_size = Vector2(250, 54)
	_vehicle_button.add_theme_font_size_override("font_size", 18)
	var vehicle_names := PackedStringArray()
	var vehicle_ids: Array[String] = []
	for entry: Dictionary in Catalog.all():
		vehicle_names.append(str(entry.get("name", "?")))
		vehicle_ids.append(str(entry.get("id", Catalog.DEFAULT_ID)))
	_vehicle_button.call("configure", vehicle_names, vehicle_ids,
		Catalog.index_of(GameSettings.minigame_vehicle))
	_vehicle_button.connect("option_changed", _on_vehicle_changed)
	action_row.add_child(_vehicle_button)

	_play_button = _button("RACE", UiPalette.YELLOW, 54, 21)
	_play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_button.pressed.connect(_on_play)
	action_row.add_child(_play_button)

	_back_button = _button("BACK", UiPalette.RED, 54, 20)
	_back_button.pressed.connect(_on_back)
	_body.add_child(_back_button)

	_refresh_vehicle()


func _button(text: String, color: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _select(index: int) -> void:
	_selected = clampi(index, 0, EVENTS.size() - 1)
	var data: Dictionary = EVENTS[_selected]
	var available: bool = bool(data.get("available", false))
	_detail_name.text = str(data["name"])
	_detail_meta.text = str(data["meta"])
	_detail_desc.text = str(data["desc"])

	# Preview policy: show the real screenshot when it exists, otherwise show
	# no image at all. Never substitute a drawing for a missing preview.
	var texture_path: String = PREVIEW_DIR + str(data.get("preview", ""))
	var has_preview: bool = texture_path != PREVIEW_DIR and ResourceLoader.exists(texture_path)
	_preview_panel.visible = has_preview
	if has_preview:
		var preview: TextureRect = _preview_panel.get_node("Preview")
		preview.texture = load(texture_path)

	_play_button.disabled = not available
	var verb: String = "SELECT" if Network.is_session_active() else "RACE"
	_play_button.text = "%s  ·  %s" % [verb, str(data["name"])] if available else "UNAVAILABLE"
	_play_button.set("fill_color", data.get("accent", UiPalette.YELLOW) if available
		else UiPalette.TEXT_DIM)


func _refresh_vehicle() -> void:
	var entry: Dictionary = Catalog.find(GameSettings.minigame_vehicle)
	if entry.is_empty():
		entry = Catalog.find(Catalog.DEFAULT_ID)
	_vehicle_button.call("set_index", Catalog.index_of(str(entry.get("id", Catalog.DEFAULT_ID))))
	_vehicle_button.set("fill_color", Color("8ed8f6"))


func _on_vehicle_changed(vehicle_id: Variant) -> void:
	GameSettings.set_minigame_options(GameSettings.minigame_difficulty,
		GameSettings.minigame_rounds, str(vehicle_id))
	_refresh_vehicle()


func _on_play() -> void:
	var data: Dictionary = EVENTS[_selected]
	if not bool(data.get("available", false)):
		return
	GameSettings.set_selected_minigame(str(data.get("id", "meadow_loop")))
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
	SceneLoader.go_to(str(data["scene"]), "MEADOW LOOP", "3 LAPS TO WIN")


func _on_back() -> void:
	if Network.is_session_active():
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "Back to the lobby")
	else:
		SceneLoader.go_to(PLAY_MENU_SCENE, "PLAY")
