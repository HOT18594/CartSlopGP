extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Minigame picker.
##
## Only events that actually ship are listed. Every card uses a real in-game
## preview image; if an event has no preview, no artwork is drawn. There are no
## illustrated placeholders or "coming soon" cards pretending to be content.

const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")

const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const PREVIEW_DIR: String = "res://assets/ui/minigames/"
const ART_BACKDROP := preload("res://scripts/ui/art_backdrop.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const EVENTS: Array[Dictionary] = [
	{
		"id": "meadow_loop",
		"name": "MEADOW LOOP",
		"desc": "Farms, ponds and pine ridges. Hit the boost pads and two dirt ramps, then outdrive the field.",
		"preview": "meadow_loop.png",
		"scene": "res://scenes/minigames/grass_race.tscn",
		"available": true,
		"accent": UiPalette.GRASS,
	},
]

var _body: VBoxContainer
var _title: Label
var _preview_panel: PanelContainer
var _slideshow: Control
var _detail_name: Label
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
	pass
	call_deferred("_enter")


func _enter() -> void:
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()


func _build_ui() -> void:
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override("font_size", 44)
	_title.add_theme_color_override("font_color", UiPalette.INK)
	# From the lobby this screen is a map picker, not a vehicle picker.
	_title.text = "MAP SELECT"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	header.add_child(_title)
	_back_button = _button("BACK", UiPalette.RED, 46, 18)
	_back_button.custom_minimum_size = Vector2(150, 46)
	_back_button.pressed.connect(_on_back)
	header.add_child(_back_button)
	_body.add_child(header)

	var feature := HBoxContainer.new()
	feature.add_theme_constant_override("separation", 18)
	feature.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(feature)

	_preview_panel = PanelContainer.new()
	_preview_panel.custom_minimum_size = Vector2(470, 270)
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

	# Real views of the current circuit, not concept art. The AI art set is
	# reserved for the randomized loading/transition screens.
	var slideshow: Control = ART_BACKDROP.new()
	slideshow.set("texture_names", PackedStringArray([
		"meadow_loop_start.png", "meadow_loop_track.png",
		"meadow_loop_boost.png", "meadow_loop_farm.png",
		"meadow_loop_overview.png",
	]))
	slideshow.set("slide_seconds", 4.5)
	slideshow.set("fade_seconds", 0.8)
	_preview_panel.add_child(slideshow)
	_slideshow = slideshow

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	feature.add_child(details)

	_detail_name = Label.new()
	_detail_name.theme_type_variation = &"TitleLabel"
	_detail_name.add_theme_font_size_override("font_size", 34)
	_detail_name.add_theme_color_override("font_color", UiPalette.INK)
	details.add_child(_detail_name)

	_detail_desc = Label.new()
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.add_theme_font_size_override("font_size", 18)
	_detail_desc.add_theme_color_override("font_color", UiPalette.INK)
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(_detail_desc)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	details.add_child(action_row)

	_vehicle_button = _button("VEHICLE: SHOPPING CART", Color("8ed8f6"), 54, 18)
	_vehicle_button.custom_minimum_size = Vector2(230, 54)
	_vehicle_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_vehicle_button.pressed.connect(_on_change_vehicle)
	# Hosts already pick a car in the lobby's HOST SETTINGS. Showing a second
	# vehicle button here was a pointless extra click.
	_vehicle_button.visible = not Network.is_session_active()
	action_row.add_child(_vehicle_button)

	_play_button = _button("RACE", UiPalette.YELLOW, 60, 24)
	_play_button.custom_minimum_size = Vector2(220, 60)
	_play_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_play_button.pressed.connect(_on_play)
	action_row.add_child(_play_button)

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
	if EVENTS.is_empty():
		# A future build may gate events behind a flag. Never index an empty
		# list: show an honest empty state instead of a script error.
		_selected = 0
		_detail_name.text = "NO EVENTS AVAILABLE"
		_detail_desc.text = "This build has no playable events yet."
		_play_button.disabled = true
		_vehicle_button.visible = false
		return
	_selected = clampi(index, 0, EVENTS.size() - 1)
	var data: Dictionary = EVENTS[_selected]
	var available: bool = bool(data.get("available", false))
	_detail_name.text = str(data["name"])
	_detail_desc.text = str(data["desc"])

	# Preview policy: show the real screenshot when it exists, otherwise show
	# no image at all. Never substitute a drawing for a missing preview.
	_preview_panel.visible = _slideshow != null and _slideshow.has_art()

	_play_button.disabled = not available
	var verb: String = "SELECT MAP" if Network.is_session_active() else "RACE"
	_play_button.text = verb if available else "UNAVAILABLE"
	_play_button.set("fill_color", UiPalette.YELLOW if available else UiPalette.TEXT_DIM)


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
