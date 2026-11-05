extends Control
## Minigames hub, rebuilt as a scroll-free grid of preview cards.
##
## Only MEADOW LOOP is playable today; the other cards are clearly marked
## COMING SOON. When the host opened this screen from a live lobby, PLAY starts
## the race for the whole session instead of entering the solo waiting room.

const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")

const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MEADOW_LOBBY: String = "res://scenes/minigames/meadow_lobby.tscn"
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const PREVIEW_DIR: String = "res://assets/ui/minigames/"
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const EVENTS: Array[Dictionary] = [
	{
		"id": "meadow_loop",
		"name": "MEADOW LOOP",
		"tag": "3 LAPS · READY",
		"desc": "A winding dirt circuit through a dense grassy forest. Three laps, four boost pads, three rivals and a lot of dust.",
		"preview": "meadow_loop.png",
		"scene": MEADOW_LOBBY,
		"available": true,
		"accent": UiPalette.GRASS,
	},
	{
		"id": "slalom",
		"name": "CONE SLALOM",
		"tag": "SOLO · SOON",
		"desc": "Weave through a long cone lane without clipping a single cone.",
		"preview": "slalom.png",
		"available": false,
		"accent": UiPalette.CYAN,
	},
	{
		"id": "crates",
		"name": "CRATE SMASH",
		"tag": "SOLO · SOON",
		"desc": "Shatter the crate wall in as few hits as possible.",
		"preview": "crates.png",
		"available": false,
		"accent": UiPalette.YELLOW,
	},
	{
		"id": "drift",
		"name": "DRIFT SCORE",
		"tag": "SOLO · SOON",
		"desc": "Chain drifts around the ring and bank the highest score before time runs out.",
		"preview": "drift.png",
		"available": false,
		"accent": UiPalette.PINK,
	},
	{
		"id": "boost",
		"name": "BOOST RUN",
		"tag": "SOLO · SOON",
		"desc": "Hit every boost pad down the straight and finish under the target time.",
		"preview": "boost.png",
		"available": false,
		"accent": UiPalette.BLUE,
	},
]

var _body: VBoxContainer
var _grid: GridContainer
var _cards: Array[Button] = []
var _selected: int = 0
var _detail_name: Label
var _detail_desc: Label
var _detail_meta: Label
var _vehicle_button: Button
var _play_button: Button
var _back_button: Button


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_body = $Center/Panel/Body
	_build_ui()
	_select(0)
	_play_button.grab_focus()


func _build_ui() -> void:
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	_body.add_child(title_row)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", UiPalette.INK)
	title.text = "MINIGAMES"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var count := Label.new()
	count.text = "%d EVENTS" % EVENTS.size()
	count.add_theme_font_size_override("font_size", 15)
	count.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(count)

	var subtitle := Label.new()
	subtitle.text = "PICK AN EVENT  ·  MEADOW LOOP IS READY TO RACE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	_body.add_child(subtitle)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_body.add_child(_grid)
	for index in EVENTS.size():
		var card: Button = _make_card(EVENTS[index], index)
		_grid.add_child(card)
		_cards.append(card)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 3)
	rule.color = UiPalette.INK
	_body.add_child(rule)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	_body.add_child(bottom)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	bottom.add_child(info)
	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 24)
	_detail_name.add_theme_color_override("font_color", UiPalette.INK)
	info.add_child(_detail_name)
	_detail_meta = Label.new()
	_detail_meta.add_theme_font_size_override("font_size", 13)
	_detail_meta.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	info.add_child(_detail_meta)
	_detail_desc = Label.new()
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.add_theme_font_size_override("font_size", 13)
	_detail_desc.add_theme_color_override("font_color", UiPalette.INK)
	info.add_child(_detail_desc)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	bottom.add_child(actions)
	_vehicle_button = _button("VEHICLE: SHOPPING CART", UiPalette.CYAN, 34, 14)
	_vehicle_button.pressed.connect(_on_vehicle_pressed)
	actions.add_child(_vehicle_button)
	_play_button = _button("PLAY  ·  MEADOW LOOP", UiPalette.YELLOW, 54, 21)
	_play_button.pressed.connect(_on_play)
	actions.add_child(_play_button)

	_back_button = _button("BACK", UiPalette.RED, 46, 20)
	_back_button.pressed.connect(_on_back)
	_body.add_child(_back_button)

	_refresh_vehicle()


func _make_card(data: Dictionary, index: int) -> Button:
	var card := Button.new()
	card.set_script(load(CANDY_BUTTON))
	card.set("fill_color", UiPalette.CREAM)
	card.set("corner_radius", 20)
	card.set("shadow_offset", 6)
	card.custom_minimum_size = Vector2(320, 168)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_ALL
	card.pressed.connect(_select.bind(index))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(0, 98)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.clip_contents = true
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture_path: String = PREVIEW_DIR + str(data.get("preview", ""))
	if ResourceLoader.exists(texture_path):
		preview.texture = load(texture_path)
	column.add_child(preview)

	var name_label := Label.new()
	name_label.text = str(data["name"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", UiPalette.INK)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)

	var tag := Label.new()
	tag.text = str(data["tag"])
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", UiPalette.BLUE_DARK if bool(data.get("available", false)) else UiPalette.TEXT_DIM)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tag)
	return card


func _button(text: String, color: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.text = text
	button.custom_minimum_size = Vector2(280, height)
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _select(index: int) -> void:
	_selected = index
	var data: Dictionary = EVENTS[index]
	var available: bool = bool(data.get("available", false))
	_detail_name.text = str(data["name"])
	_detail_meta.text = str(data["tag"])
	_detail_desc.text = str(data["desc"])
	_play_button.disabled = not available
	_play_button.text = "PLAY  ·  %s" % str(data["name"]) if available \
		else "COMING SOON"
	_play_button.set("fill_color", UiPalette.YELLOW if available else UiPalette.TEXT_DIM)
	for card_index in _cards.size():
		var card: Button = _cards[card_index]
		var accent: Color = EVENTS[card_index].get("accent", UiPalette.CREAM)
		card.set("fill_color", accent if card_index == index else UiPalette.CREAM)


func _refresh_vehicle() -> void:
	var entry: Dictionary = Catalog.find(GameSettings.minigame_vehicle)
	if entry.is_empty():
		entry = Catalog.find(Catalog.DEFAULT_ID)
	_vehicle_button.text = "VEHICLE: " + str(entry.get("name", "SHOPPING CART"))
	_vehicle_button.set("fill_color", Color("8ed8f6"))


func _on_vehicle_pressed() -> void:
	var options: Array[Dictionary] = Catalog.all()
	if options.is_empty():
		return
	var index: int = Catalog.index_of(GameSettings.minigame_vehicle)
	index = wrapi(index + 1, 0, options.size())
	GameSettings.set_minigame_options(GameSettings.minigame_difficulty,
		GameSettings.minigame_rounds, str(options[index].get("id", Catalog.DEFAULT_ID)))
	_refresh_vehicle()


func _on_play() -> void:
	var data: Dictionary = EVENTS[_selected]
	if not bool(data.get("available", false)):
		return
	if Network.is_session_active():
		if not Network.is_host:
			return
		Network.configure_session(GameSettings.GAME_MINIGAMES, GameSettings.bots_enabled,
			GameSettings.effective_bot_count())
		Network.start_game(Network.RACE_SCENE, GameSettings.GAME_MINIGAMES)
		return
	SceneLoader.go_to(str(data["scene"]), "WAITING ROOM", "3 LAPS TO WIN")


func _on_back() -> void:
	if Network.is_session_active():
		get_tree().change_scene_to_file(LOBBY_SCENE)
	else:
		get_tree().change_scene_to_file(PLAY_MENU_SCENE)
