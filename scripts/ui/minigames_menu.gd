extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## GAMES screen: one card per game, and a selector page inside RACING and DELIVER.
##
## The top page lists games, never individual maps: RACING groups every grid
## circuit in TrackDefs, DELIVER is the cargo minigame and owns the arena theme
## strip, and any other registry minigame gets its own game card. Choosing
## RACING or DELIVER opens that game's page inside this screen; BACK and Escape
## walk back one page and never leave the games list. The free-roam park has its
## own door in PLAY -> SINGLE, so it is not repeated as a game card here.
##
## A map card carries the real preview image, the circuit name, a one-line
## tagline, the built lap length and a difficulty chip. The chosen card is
## painted with the one accent (yellow) and shows a SELECTED chip, so the pick is
## readable without the focus ring. Confirming writes GameSettings and loads the
## same scene the old flat card list loaded, so the race contract is unchanged.
##
## Preview resolution: the preview_render tool writes
## res://assets/ui/art/preview_<id>.png, which wins over a map's registry image;
## with neither, the meadow fallback keeps a card from showing a blank frame.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const VehicleSelect := preload("res://scripts/ui/vehicle_select.gd")

const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const PREVIEW_DIR: String = "res://assets/ui/minigames/"
const ART_PREVIEW_DIR: String = "res://assets/ui/art/"
const FALLBACK_PREVIEW: String = "meadow_loop.png"
const SANDBOX_PREVIEW: String = "res://assets/ui/art/scene_track_aerial.png"

const PAGE_GAMES: String = "games"
const GAME_RACING: String = "racing"
const GAME_MINIGAME: String = "minigame"

const MAP_CARD_WIDTH: float = 268.0
const MAP_CARD_HEIGHT: float = 300.0
const MAP_PREVIEW_HEIGHT: float = 150.0
const GAME_CARD_HEIGHT: float = 150.0
const GAME_CARD_PAD: float = 16.0 ## Card padding: one step on the 24/16/8 scale.
const GRID_COLUMNS: int = 3
const GRID_GAP: int = 16 ## Row gap; the tight step is 8 (chips, captions).
const CHIP_RADIUS: int = 8
## Caps, not floors: _fit_page_heights() gives each page the height its content
## needs, so a two-card list cannot leave a hole under itself.
const GAMES_SCROLL_HEIGHT: float = 500.0
const MAPS_SCROLL_HEIGHT: float = 340.0
const DELIVER_SCROLL_HEIGHT: float = 340.0
const GAME_LIST_WIDTH: float = 760.0 ## Card row width; the page centres it.
const MAP_GRID_WIDTH: float = MAP_CARD_WIDTH * 3.0 + float(GRID_GAP) * 2.0

var _body: VBoxContainer
var _title: Label
var _back_button: Button

var _page: String = PAGE_GAMES
var _games: Array[Dictionary] = []

var _games_page: VBoxContainer
var _games_scroll: ScrollContainer
var _game_list: VBoxContainer
var _game_cards: Array[Button] = []

var _selector_page: VBoxContainer
var _selector_caption: Label
var _selector_scroll: ScrollContainer
var _selector_list: VBoxContainer
var _arena_empty: Label
var _map_grid: GridContainer
var _map_cards: Array[Button] = []
var _map_badges: Array[PanelContainer] = []
var _map_indexes: Array[int] = []
var _selected: int = 0

var _deliver_panel: PanelContainer
var _deliver_theme: PanelContainer
var _deliver_entry: Dictionary = {}
var _selector_game: Dictionary = {}
var _theme_pill: Button
var _theme_ids: PackedStringArray = PackedStringArray()
var _selected_theme: String = ""

var _vehicle_button: Button
var _play_button: Button

## Page and picks carried through the vehicle picker, so returning lands on the
## game that was being configured with the circuit and arena that were
## highlighted, instead of the saved ones. Process-local on purpose: a fresh
## launch always opens on GAMES with the saved selection.
static var _return_page: String = ""
static var _return_map: String = ""
static var _return_theme: String = ""

var _restored_map_id: String = ""
var _restored_theme: String = ""


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_body = $Center/Panel/Body
	# Read what the vehicle round trip carried before anything is built: the
	# games list resolves the RACING preview from this map.
	var resume: String = _consume_return_state()
	_build_ui()
	_initial_state()
	if resume != "" and not _game_entry_for(resume).is_empty():
		_show_selector(resume)
	else:
		_show_games(false)
	call_deferred("_enter")
	if OS.get_environment("CART_UI_MEASURE") == "1":
		_report_layout.call_deferred()
	if OS.get_environment("CART_MINIGAMES_SELFTEST") == "1":
		_run_selftest.call_deferred()


func _consume_return_state() -> String:
	## Read and clear what the garage trip carried, so it is restored exactly
	## once. The statics are process-local: a fresh launch has nothing to read.
	var resume: String = _return_page
	_restored_map_id = _return_map
	_restored_theme = _return_theme
	_return_page = ""
	_return_map = ""
	_return_theme = ""
	return resume


func _report_layout() -> void:
	## Verification hook (CART_UI_MEASURE=1): measures the game list, then the
	## RACING and minigame selector pages, in one boot.
	await UiKit.report_screen(self, "minigames:games")
	_report_blocks("minigames:games")
	if not _game_cards.is_empty():
		_show_selector(GAME_RACING)
		await UiKit.report_screen(self, "minigames:racing")
		_report_blocks("minigames:racing")
	if not _deliver_entry.is_empty():
		_show_selector(str(_deliver_entry.get("id", "")))
		await UiKit.report_screen(self, "minigames:minigame")
		_report_blocks("minigames:minigame")


func _report_blocks(tag: String) -> void:
	## Verification hook: the page frame and its scroll, which the button sweep
	## cannot describe. The panel height is what decides whether 720 clips.
	var panel: Control = $Center/Panel
	print("UI_BLOCKS %s panel=%.0fx%.0f body=%.0fx%.0f games_scroll=%.0f selector_scroll=%.0f fits720=%s"
		% [tag, panel.size.x, panel.size.y, _body.size.x, _body.size.y,
		_games_scroll.custom_minimum_size.y,
		_selector_scroll.custom_minimum_size.y,
		str(panel.size.y <= UiKit.SCREEN_HEIGHT - UiKit.SCREEN_MARGIN * 2.0)])


func _fit_page_heights() -> void:
	## Content-driven page heights within the caps. A fixed 476 px floor left a
	## 120 px hole under a two-card list, which reads as an orphan margin.
	if _games_scroll != null:
		_games_scroll.custom_minimum_size.y = minf(
			_scroll_content_height(_games_scroll), GAMES_SCROLL_HEIGHT)
	if _selector_scroll != null and _selector_page.visible:
		var cap: float = MAPS_SCROLL_HEIGHT if _page == GAME_RACING \
			else DELIVER_SCROLL_HEIGHT
		_selector_scroll.custom_minimum_size.y = minf(
			_scroll_content_height(_selector_scroll), cap)


func _scroll_content_height(scroll: ScrollContainer) -> float:
	## The padded wrapper, not the list: the 8/16 px pad is what keeps a
	## hover-scaled card and its drop shadow inside the scroll's clip rect.
	if scroll.get_child_count() == 0:
		return 0.0
	return scroll.get_child(0).get_combined_minimum_size().y


func _padded(scroll: ScrollContainer, pad_name: String) -> MarginContainer:
	## Scrolling clips at its rect, so the content gets a small pad: 8 px for
	## the 3 % hover scale and 16 px at the bottom for the candy drop shadow.
	var pad := MarginContainer.new()
	pad.name = pad_name
	pad.add_theme_constant_override("margin_left", UiKit.SPACING_TIGHT)
	pad.add_theme_constant_override("margin_right", UiKit.SPACING_TIGHT)
	pad.add_theme_constant_override("margin_top", UiKit.SPACING_TIGHT)
	pad.add_theme_constant_override("margin_bottom", UiKit.SPACING)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	return pad


func _enter() -> void:
	# Re-fit once the first layout is real: an autowrapped label reports a
	# different height before it knows its width.
	_fit_page_heights()
	_refresh_vehicle()
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()
	_focus_page()


func _focus_page() -> void:
	## Focus the action this page is for. Resuming from the garage used to leave
	## the ring on BACK, because only the games page grabbed focus.
	if _page == PAGE_GAMES:
		var first: Button = _game_cards[0] if not _game_cards.is_empty() \
			else _back_button
		MenuNav.focus(first)
	elif _page == GAME_RACING and not _map_cards.is_empty():
		MenuNav.focus(_map_cards[clampi(_selected, 0, _map_cards.size() - 1)])
	elif _theme_pill != null and _theme_pill.visible \
			and not _theme_ids.is_empty():
		MenuNav.focus(_theme_pill)
	else:
		MenuNav.focus(_play_button)


func _page_in(page: Control) -> void:
	## Page transition: fade plus a small settle, so a page change never snaps.
	## The VBox owns position, not scale, so this cannot be snapped back.
	page.pivot_offset = page.size * 0.5
	page.scale = Vector2.ONE * 0.98
	UiAnim.fade_in(page, 0.18)
	var tween: Tween = page.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(page, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	## Escape is the same as BACK: one page back, then out of the screen.
	if event.is_action_pressed("ui_cancel") and not SceneLoader.is_busy():
		_on_back()
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# build


func _build_ui() -> void:
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override("font_size", UiKit.TITLE_SIZE)
	_title.add_theme_color_override("font_color", UiPalette.INK)
	_title.text = "GAMES"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiKit.SPACING)
	header.add_child(_title)
	_back_button = _button("BACK", UiPalette.RED, 46, 17)
	_back_button.name = "BackButton"
	UiKit.cap_button(_back_button, 124.0)
	_back_button.tooltip_text = "Back to PLAY."
	_back_button.pressed.connect(_on_back)
	header.add_child(_back_button)
	_body.add_child(header)

	_build_games()
	_build_games_page()
	_build_selector_page()
	_refresh_vehicle()


func _build_games() -> void:
	## The games list is data first, nodes second: one entry per game, in menu
	## order. Racing collects every registry map, then each minigame becomes its
	## own game (its optional `game` field names it). The free-roam park has its
	## own door in PLAY -> SINGLE, so it is not a card here.
	_games.clear()
	_map_indexes.clear()
	for index in TrackDefs.PRESETS.size():
		if TrackDefs.is_map(TrackDefs.PRESETS[index]):
			_map_indexes.append(index)
	# Restore the remembered circuit before the RACING card picks its preview,
	# so the game tile shows the track the page would open. A circuit carried
	# through the garage wins over the saved one, so the pick survives the trip.
	_selected = 0
	if not _map_indexes.is_empty():
		var saved: String = _restored_map_id if _restored_map_id != "" \
			else GameSettings.selected_map
		var registered: int = TrackDefs.index_of(saved)
		_selected = maxi(_map_indexes.find(registered), 0)
	if not _map_indexes.is_empty():
		_games.append(_racing_entry())
	for index in TrackDefs.PRESETS.size():
		var preset: Dictionary = TrackDefs.PRESETS[index]
		if TrackDefs.is_minigame(preset):
			_games.append(_minigame_entry(preset))
	_deliver_entry = {}
	for entry: Dictionary in _games:
		if str(entry.get("kind", "")) == GAME_MINIGAME:
			_deliver_entry = entry
			break


func _racing_entry() -> Dictionary:
	## One RACING card for every circuit. Its preview follows the remembered
	## map, so the tile shows the track the player would open.
	return {
		"id": GAME_RACING,
		"kind": GAME_RACING,
		"name": "RACING",
		"desc": "Three cartoon circuits. Pick a map, then race the field.",
		"detail": _racing_detail(),
		"accent": UiPalette.GRASS,
		"preview": _preview_for_preset(_current_map()),
	}


func _racing_detail() -> String:
	var count: int = _map_indexes.size()
	var shortest: int = 0
	var longest: int = 0
	for index in _map_indexes:
		var length: int = int(TrackDefs.PRESETS[index].get("lap_length", 0))
		if length <= 0:
			continue
		shortest = length if shortest <= 0 else mini(shortest, length)
		longest = maxi(longest, length)
	var text: String = "%d CIRCUIT%s" % [count, "" if count == 1 else "S"]
	if longest > 0:
		text += "  ·  %d-%d M LAPS" % [shortest, longest]
	return text


func _minigame_entry(preset: Dictionary) -> Dictionary:
	var themes: PackedStringArray = TrackDefs.theme_names(preset)
	var detail: String = "%s  ·  %d ARENA%s" % [
		str(preset.get("name", "MINIGAME")),
		themes.size(), "" if themes.size() == 1 else "S"]
	return {
		"id": str(preset.get("id", "minigame")),
		"kind": GAME_MINIGAME,
		"name": str(preset.get("game", preset.get("name", "MINIGAME"))),
		"desc": str(preset.get("desc", "")),
		"detail": detail,
		"tag": "2 TEAMS",
		"accent": UiPalette.CYAN,
		"preview": _preview_for_preset(preset),
		"preset": preset,
	}


func _build_games_page() -> void:
	_games_page = VBoxContainer.new()
	_games_page.name = "GamesPage"
	_games_page.add_theme_constant_override("separation", UiKit.SPACING)
	_body.add_child(_games_page)
	# A ScrollContainer's minimum height is zero, so the list needs an explicit
	# floor or the whole page collapses and no game card is focusable. The floor
	# is fitted to the real list in _fit_page_heights(); these are the caps.
	_games_scroll = ScrollContainer.new()
	_games_scroll.name = "GamesScroll"
	_games_scroll.custom_minimum_size = Vector2(0, GAMES_SCROLL_HEIGHT)
	_games_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_games_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_games_scroll.follow_focus = true
	_games_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Card rows are centred at a readable width instead of stretching the whole
	# 960 px page: a 915 px game card is what made the screen look broken.
	_games_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_games_page.add_child(_games_scroll)
	_game_list = VBoxContainer.new()
	_game_list.name = "GameList"
	_game_list.custom_minimum_size = Vector2(GAME_LIST_WIDTH, 0)
	_game_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_list.add_theme_constant_override("separation", UiKit.SPACING)
	_padded(_games_scroll, "GamesPad").add_child(_game_list)
	_game_cards.clear()
	for entry: Dictionary in _games:
		var card: Button = _make_game_card(entry)
		_game_list.add_child(card)
		_game_cards.append(card)
	if _game_cards.is_empty():
		_empty_state(_game_list, "NO GAMES REGISTERED YET.")


func _build_selector_page() -> void:
	_selector_page = VBoxContainer.new()
	_selector_page.name = "SelectorPage"
	_selector_page.add_theme_constant_override("separation", UiKit.SPACING)
	_selector_page.visible = false
	_body.add_child(_selector_page)

	_selector_caption = UiKit.label("", 14, UiPalette.MUTED)
	_selector_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selector_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selector_page.add_child(_selector_caption)

	_selector_scroll = ScrollContainer.new()
	_selector_scroll.name = "SelectorScroll"
	_selector_scroll.custom_minimum_size = Vector2(0, MAPS_SCROLL_HEIGHT)
	_selector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_selector_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_selector_scroll.follow_focus = true
	_selector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_selector_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_selector_page.add_child(_selector_scroll)

	_selector_list = VBoxContainer.new()
	_selector_list.name = "SelectorList"
	_selector_list.custom_minimum_size = Vector2(GAME_LIST_WIDTH, 0)
	_selector_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selector_list.add_theme_constant_override("separation", UiKit.SPACING)
	_padded(_selector_scroll, "SelectorPad").add_child(_selector_list)

	# The three circuits share one row of large cards so lap length, difficulty
	# and the preview art can be compared at a glance. A fixed grid width keeps
	# the rightmost card clear of the scrollbar and the panel edge.
	_map_grid = GridContainer.new()
	_map_grid.name = "MapGrid"
	_map_grid.custom_minimum_size = Vector2(MAP_GRID_WIDTH, 0)
	_map_grid.columns = GRID_COLUMNS
	_map_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_map_grid.add_theme_constant_override("v_separation", GRID_GAP)
	_selector_list.add_child(_map_grid)
	_map_cards.clear()
	_map_badges.clear()
	for position in _map_indexes.size():
		var card: Button = _make_map_card(position,
			TrackDefs.PRESETS[_map_indexes[position]])
		_map_grid.add_child(card)
		_map_cards.append(card)
	_update_map_cards()

	_deliver_theme = _build_theme_block()
	_deliver_theme.visible = false
	_selector_list.add_child(_deliver_theme)

	# A game can register no arena variants: say so instead of leaving a blank
	# page under the game header.
	_arena_empty = _empty_state(_selector_list, "THIS GAME HAS NO ARENA VARIANTS.")
	_arena_empty.visible = false

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", UiKit.SPACING)
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_selector_page.add_child(action_row)

	_vehicle_button = _button("VEHICLE: SHOPPING CART", Color("8ed8f6"), 60, 17)
	_vehicle_button.name = "VehicleButton"
	UiKit.cap_button(_vehicle_button, 230.0)
	_vehicle_button.tooltip_text = "Pick the cart you will race."
	_vehicle_button.pressed.connect(_on_change_vehicle)
	# Hosts already pick a car in the lobby's HOST SETTINGS. Showing a second
	# vehicle button here was a pointless extra click.
	_vehicle_button.visible = not Network.is_session_active()
	action_row.add_child(_vehicle_button)

	_play_button = _button("RACE", UiPalette.YELLOW, 60, 22)
	_play_button.name = "PlayButton"
	UiKit.cap_button(_play_button, 300.0)
	_play_button.pressed.connect(_on_confirm)
	action_row.add_child(_play_button)


func _build_theme_block() -> PanelContainer:
	## DELIVER keeps its arena selector in the same page pattern as the map
	## grid: one confirmed choice, saved to GameSettings.selected_minigame, the
	## exact field cargo_rush.gd resolves.
	var panel := PanelContainer.new()
	panel.name = "ArenaTheme"
	panel.add_theme_stylebox_override("panel",
		UiKit.flat_card(Color(1.0, 1.0, 1.0, 0.42)))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", int(UiKit.SPACING))
	pad.add_theme_constant_override("margin_right", int(UiKit.SPACING))
	pad.add_theme_constant_override("margin_top", int(UiKit.SPACING))
	pad.add_theme_constant_override("margin_bottom", int(UiKit.SPACING))
	panel.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiKit.SPACING)
	pad.add_child(row)
	var label := UiKit.label("ARENA THEME", 14, UiPalette.INK)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_theme_pill = UiKit.segmented(PackedStringArray(), [], 0, 150.0, 46.0)
	_theme_pill.name = "ThemePill"
	_theme_pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	_theme_pill.tooltip_text = "Pick which arena this minigame is played in."
	_theme_pill.connect("option_changed", _on_theme_changed)
	row.add_child(_theme_pill)
	return panel


func _make_game_card(entry: Dictionary) -> Button:
	var accent: Color = entry.get("accent", UiPalette.GRASS) as Color
	var card: Button = _button("", accent.lightened(0.35),
		int(GAME_CARD_HEIGHT), 22)
	card.name = "GameCard_%s" % str(entry.get("id", "game"))
	card.custom_minimum_size = Vector2(0, GAME_CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = str(entry.get("desc", ""))
	card.pressed.connect(_on_game_pressed.bind(str(entry.get("id", ""))))
	_fill_game_row(card, entry)
	return card


func _make_game_panel(entry: Dictionary) -> PanelContainer:
	## The same row layout as a game card, without the button: the game already
	## owns the page, so its card is a header, not a second way to select it.
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UiKit.flat_card(Color(1.0, 1.0, 1.0, 0.42)))
	_fill_game_row(panel, entry)
	return panel


func _fill_game_row(target: Control, entry: Dictionary) -> void:
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", int(GAME_CARD_PAD))
	pad.add_theme_constant_override("margin_right", int(GAME_CARD_PAD))
	pad.add_theme_constant_override("margin_top", int(GAME_CARD_PAD))
	pad.add_theme_constant_override("margin_bottom", int(GAME_CARD_PAD))
	if target is Container:
		target.add_child(pad)
	else:
		pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		target.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiKit.SPACING)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)
	row.add_child(_preview_frame(entry.get("preview", null) as Texture2D,
		Vector2(250.0, GAME_CARD_HEIGHT - GAME_CARD_PAD * 2.0), UiPalette.OUTLINE))
	row.add_child(_game_text(entry, 28, str(entry.get("tag", ""))))


func _game_text(entry: Dictionary, name_size: int, tag: String) -> VBoxContainer:
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := Label.new()
	name_label.text = str(entry.get("name", "GAME"))
	name_label.theme_type_variation = &"TitleLabel"
	name_label.add_theme_font_size_override("font_size", name_size)
	name_label.add_theme_color_override("font_color", UiPalette.INK)
	name_label.add_theme_constant_override("outline_size", 0)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(name_label)
	var desc := Label.new()
	desc.text = str(entry.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.max_lines_visible = 2
	desc.clip_text = true
	desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	desc.custom_minimum_size = Vector2(0, 38)
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", UiPalette.MUTED)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(desc)
	var detail := Label.new()
	detail.text = str(entry.get("detail", ""))
	detail.clip_text = true
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", UiPalette.BODY_BLUE)
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(detail)
	if tag != "":
		var tag_row := HBoxContainer.new()
		tag_row.add_theme_constant_override("separation", 8)
		tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_row.add_child(_chip(tag, UiPalette.YELLOW, UiPalette.INK))
		text.add_child(tag_row)
	return text


func _make_map_card(position: int, preset: Dictionary) -> Button:
	var accent: Color = _accent_for(preset)
	var card: Button = _button("", accent.lightened(0.35),
		int(MAP_CARD_HEIGHT), 20)
	card.name = "MapCard_%s" % str(preset.get("id", "map"))
	card.custom_minimum_size = Vector2(MAP_CARD_WIDTH, MAP_CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = str(preset.get("desc", ""))
	card.pressed.connect(_on_map_pressed.bind(position))

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", int(GAME_CARD_PAD))
	pad.add_theme_constant_override("margin_right", int(GAME_CARD_PAD))
	pad.add_theme_constant_override("margin_top", int(GAME_CARD_PAD))
	pad.add_theme_constant_override("margin_bottom", int(GAME_CARD_PAD))
	card.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(column)
	column.add_child(_preview_frame(_preview_for_preset(preset),
		Vector2(0.0, MAP_PREVIEW_HEIGHT), UiPalette.OUTLINE))

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	var name_label := Label.new()
	name_label.text = str(preset.get("name", "MAP"))
	name_label.theme_type_variation = &"TitleLabel"
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", UiPalette.INK)
	name_label.add_theme_constant_override("outline_size", 0)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(name_label)

	var tagline := Label.new()
	tagline.text = str(preset.get("tagline", preset.get("desc", "")))
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.max_lines_visible = 2
	tagline.clip_text = true
	tagline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tagline.custom_minimum_size = Vector2(0, 36)
	tagline.add_theme_font_size_override("font_size", 14)
	tagline.add_theme_color_override("font_color", UiPalette.MUTED)
	tagline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tagline)

	# A flexible spacer pins the statistics row to the card's bottom edge, so
	# the three cards line up even when a tagline wraps to two lines.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)
	var lap := Label.new()
	lap.text = _lap_text(preset)
	lap.add_theme_font_size_override("font_size", 13)
	lap.add_theme_color_override("font_color", UiPalette.BODY_BLUE)
	lap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(lap)
	var difficulty: String = str(preset.get("difficulty", ""))
	if difficulty != "":
		var chip: PanelContainer = _chip(difficulty, UiPalette.YELLOW, UiPalette.INK)
		chip.name = "Difficulty"
		bottom.add_child(chip)
	# The selected chip lives on the statistics row, not beside the name: three
	# cards share one row, so the circuit name must keep its full width.
	var badge: PanelContainer = _chip("SELECTED", UiPalette.INK, UiPalette.CREAM)
	badge.name = "Selected"
	badge.visible = false
	bottom.add_child(badge)
	_map_badges.append(badge)
	return card


func _lap_text(preset: Dictionary) -> String:
	var length: int = int(preset.get("lap_length", 0))
	if length <= 0:
		return ""
	return "%d M LAP" % length


func _preview_frame(texture: Texture2D, minimum: Vector2,
		fallback: Color) -> PanelContainer:
	## A dark cartoon mat inset behind the capture. The 5 px content margin is
	## what lets the panel's rounded 16 corner read around an image, because a
	## TextureRect can only be clipped to a rectangle.
	var frame := PanelContainer.new()
	frame.custom_minimum_size = minimum
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = fallback
	style.set_corner_radius_all(UiKit.CORNER_RADIUS)
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	style.anti_aliasing = true
	frame.add_theme_stylebox_override("panel", style)
	if texture != null:
		var preview := TextureRect.new()
		preview.texture = texture
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(preview)
	return frame


func _empty_state(parent: Control, text: String) -> Label:
	## A list can be empty (no game registered, no arena variant): say so in one
	## line instead of presenting a blank page with a live BACK button.
	var label := UiKit.label(text, int(UiKit.CAPTION_SIZE), UiPalette.MUTED)
	label.name = "EmptyState"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(GAME_LIST_WIDTH, 120.0)
	parent.add_child(label)
	return label


func _chip(text: String, background: Color, foreground: Color) -> PanelContainer:
	## Small inline tag. Eight is the chip radius, not a second tile radius: the
	## shared 16 belongs to tiles, cards and rows.
	var chip := PanelContainer.new()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.set_corner_radius_all(CHIP_RADIUS)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 3.0
	style.anti_aliasing = true
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", foreground)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)
	return chip


func _button(text: String, color: Color, height: int, font_size: int) -> Button:
	return UiKit.tile(text, color, float(height), font_size)


# --------------------------------------------------------------------------
# data


func _initial_state() -> void:
	## Restore the remembered arena so reopening the screen lands on the theme
	## the player last confirmed, unless the garage trip carried a live pick.
	## The circuit is restored in _build_games() because the RACING card's
	## preview depends on it.
	_selected_theme = _restored_theme
	var deliver: Dictionary = _deliver_game_preset()
	if not deliver.is_empty():
		_configure_theme_pill(deliver)


func _current_map() -> Dictionary:
	if _map_indexes.is_empty():
		return {}
	return TrackDefs.PRESETS[_map_indexes[clampi(_selected, 0,
		_map_indexes.size() - 1)]]


func _deliver_game_preset() -> Dictionary:
	## The minigame the selector page is currently showing, so the confirm acts
	## on that game and not on whichever minigame happens to be first.
	if _selector_game.is_empty():
		_selector_game = _deliver_entry
	return _selector_game.get("preset", {}) as Dictionary


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


func _preview_for_preset(preset: Dictionary) -> Texture2D:
	return _preview_texture(str(preset.get("id", "")),
		str(preset.get("preview", "")))


func _preview_texture(id: String, file: String) -> Texture2D:
	## The preview_render tool's per-map capture wins, then the registry image,
	## then the shared fallback. ResourceLoader.exists() is the only test: an
	## unimported PNG is not loadable at runtime and must not blank a card.
	var art: String = ART_PREVIEW_DIR + "preview_" + id + ".png"
	var texture: Texture2D = _texture_at(art)
	if texture != null:
		return texture
	if file != "":
		texture = _texture_at(PREVIEW_DIR + file)
		if texture != null:
			return texture
	return _texture_at(PREVIEW_DIR + FALLBACK_PREVIEW)


func _texture_at(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# --------------------------------------------------------------------------
# pages


func _show_games(animate: bool = true) -> void:
	var came_from: String = _page
	_page = PAGE_GAMES
	_games_page.visible = true
	_selector_page.visible = false
	_title.text = "GAMES"
	_back_button.tooltip_text = "Back to PLAY."
	_fit_page_heights()
	_refresh_vehicle()
	if animate:
		_page_in(_games_page)
	MenuNav.refresh()
	MenuNav.focus(_game_card_for(came_from))


func _show_selector(game_id: String) -> void:
	var entry: Dictionary = _game_entry_for(game_id)
	if entry.is_empty():
		# No such game: never open a selector with nothing on it.
		_show_games(true)
		return
	var racing: bool = game_id == GAME_RACING
	_page = game_id
	_games_page.visible = false
	_selector_page.visible = true
	_map_grid.visible = racing
	if racing:
		if _deliver_panel != null:
			_deliver_panel.visible = false
		_deliver_theme.visible = false
		_arena_empty.visible = false
	else:
		_show_minigame_page(entry)
	_title.text = "RACING" if racing else str(entry.get("name", "GAME"))
	_selector_caption.text = "PICK A CIRCUIT  ·  3 LAPS TO WIN" if racing \
		else "PICK AN ARENA  ·  ONE CONFIRMED CHOICE"
	_back_button.tooltip_text = "Back to the game list."
	_selector_scroll.scroll_vertical = 0
	_fit_page_heights()
	_refresh_vehicle()
	_refresh_play_label()
	_page_in(_selector_page)
	MenuNav.refresh()
	_focus_page()


func _show_minigame_page(entry: Dictionary) -> void:
	## A minigame page is built from its own registry entry, so a second
	## minigame added later gets the right card and theme strip instead of
	## reusing the cargo arena's.
	if entry.is_empty():
		return
	var game_id: String = str(entry.get("id", ""))
	if _deliver_panel == null or str(_selector_game.get("id", "")) != game_id:
		_selector_game = entry
		_rebuild_deliver_panel(entry)
		_configure_theme_pill(_deliver_game_preset())
	_deliver_panel.visible = true
	_deliver_theme.visible = not _theme_ids.is_empty()
	_arena_empty.visible = _theme_ids.is_empty()


func _rebuild_deliver_panel(entry: Dictionary) -> void:
	if _deliver_panel != null and is_instance_valid(_deliver_panel):
		_selector_list.remove_child(_deliver_panel)
		_deliver_panel.queue_free()
		_deliver_panel = null
	var panel: PanelContainer = _make_game_panel(entry)
	panel.name = "DeliverCard"
	_selector_list.add_child(panel)
	_selector_list.move_child(panel, _deliver_theme.get_index())
	_deliver_panel = panel


func _game_entry_for(game_id: String) -> Dictionary:
	for entry: Dictionary in _games:
		if str(entry.get("id", "")) == game_id:
			return entry
	return {}


func _game_card_for(game_id: String) -> Button:
	for index in _games.size():
		if str(_games[index].get("id", "")) == game_id \
				and index < _game_cards.size():
			return _game_cards[index]
	if not _game_cards.is_empty():
		return _game_cards[0]
	return _back_button


func _on_back() -> void:
	if _page != PAGE_GAMES:
		_show_games()
		return
	if Network.is_session_active():
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "Back to the lobby")
	else:
		SceneLoader.go_to(PLAY_MENU_SCENE, "PLAY")


func _on_game_pressed(game_id: String) -> void:
	_show_selector(game_id)


func _on_map_pressed(position: int) -> void:
	if _map_cards.is_empty():
		return
	_selected = clampi(position, 0, _map_cards.size() - 1)
	_update_map_cards()
	_refresh_play_label()
	MenuNav.refresh()


func _update_map_cards() -> void:
	for index in _map_cards.size():
		var selected: bool = index == _selected
		var preset: Dictionary = TrackDefs.PRESETS[_map_indexes[index]] \
			if index < _map_indexes.size() else {}
		var fill: Color = UiPalette.YELLOW if selected \
			else _accent_for(preset).lightened(0.35)
		_map_cards[index].set("fill_color", fill)
		_outline_selected(_map_cards[index], selected)
		if index < _map_badges.size() and _map_badges[index] != null:
			_map_badges[index].visible = selected


func _outline_selected(card: Button, selected: bool) -> void:
	## The accent fill already marks the pick; a heavier ink outline makes it
	## readable in a row of three without introducing a second accent colour.
	for state: String in ["normal", "hover", "pressed"]:
		var base: StyleBox = card.get_theme_stylebox(state)
		if not (base is StyleBoxFlat):
			continue
		var ring: StyleBoxFlat = (base as StyleBoxFlat).duplicate() as StyleBoxFlat
		ring.set_border_width_all(9 if selected else 6)
		card.add_theme_stylebox_override(state, ring)


func _on_confirm() -> void:
	if _play_button == null or _play_button.disabled:
		return
	if _page == GAME_RACING:
		_launch(_current_map(), false)
	elif _page != PAGE_GAMES:
		_launch(_deliver_game_preset(), true)


func _confirm_target(data: Dictionary, minigame: bool) -> Dictionary:
	## The scene, title and id a confirm would use, without loading anything.
	## The launch path and the selftest both read this one dictionary, so the
	## measured target cannot drift from the real one.
	if data.is_empty():
		return {}
	return {
		"scene": _scene_for(data),
		"title": str(data.get("name", "RACE")),
		"hint": str(data.get("hint", "3 LAPS TO WIN")),
		"id": str(data.get("id", TrackDefs.DEFAULT_ID)),
		"theme": _theme_for(data) if minigame else "",
	}


func _scene_for(data: Dictionary) -> String:
	## Maps live in the race scene; a minigame names the scene it loads.
	return str(data.get("scene", RACE_SCENE))


func _launch(data: Dictionary, minigame: bool) -> void:
	if data.is_empty() or not bool(data.get("available", true)):
		return
	if Network.is_session_active() and not Network.is_host:
		return
	var target: Dictionary = _confirm_target(data, minigame)
	var scene: String = str(target.get("scene", ""))
	if scene not in [Network.RACE_SCENE, Network.CARGO_SCENE]:
		return
	if minigame:
		# The arena theme travels in selected_minigame, the exact field
		# cargo_rush.gd resolves; configure_session copies it into
		# Network.session_minigame for online peers. The race map is untouched.
		GameSettings.set_selected_minigame(str(target.get("theme", "")))
	else:
		# Maps live in their dedicated field, which grass_race.gd reads.
		GameSettings.set_selected_map(str(target.get("id", TrackDefs.DEFAULT_ID)))
	if Network.is_session_active():
		if not Network.is_host:
			return
		GameSettings.set_multiplayer_mode(GameSettings.GAME_MINIGAMES)
		Network.configure_session(GameSettings.GAME_MINIGAMES,
			GameSettings.bots_enabled, GameSettings.effective_bot_count())
		# Picking a card only updates the lobby. The host starts from START.
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER",
			"Minigame selected" if minigame else "Map selected")
		return
	GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	SceneLoader.go_to(str(target["scene"]), str(target["title"]),
		str(target["hint"]))


# --------------------------------------------------------------------------
# theme strip


func _configure_theme_pill(preset: Dictionary) -> void:
	if _theme_pill == null:
		return
	var themes: PackedStringArray = TrackDefs.theme_ids(preset)
	if themes != _theme_ids:
		_theme_ids = themes
		var labels: PackedStringArray = TrackDefs.theme_names(preset)
		var values: Array = []
		for id: String in themes:
			values.append(id)
		_theme_pill.call("configure", labels, values, 0)
	_theme_pill.visible = not _theme_ids.is_empty()
	var wanted: String = _theme_for(preset)
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
	_refresh_play_label()


func _refresh_play_label() -> void:
	if _play_button == null:
		return
	var data: Dictionary = _current_map() if _page == GAME_RACING \
		else _deliver_game_preset()
	if data.is_empty():
		_play_button.disabled = true
		_play_button.text = "UNAVAILABLE"
		_play_button.fit_text()
		return
	# Only the host can launch a room. A client used to get an enabled button
	# that silently did nothing when pressed.
	if Network.is_session_active() and not Network.is_host:
		_play_button.disabled = true
		_play_button.text = "HOST STARTS THE RACE"
		_play_button.fit_text()
		return
	_play_button.disabled = not bool(data.get("available", true))
	if _play_button.disabled:
		_play_button.text = "UNAVAILABLE"
		_play_button.fit_text()
		return
	var minigame: bool = TrackDefs.is_minigame(data)
	var verb: String = "PLAY" if minigame else "RACE"
	if Network.is_session_active():
		verb = "SELECT MINIGAME" if minigame else "SELECT MAP"
	_play_button.text = "%s  ·  %s" % [verb, str(data.get("name", "MAP"))]
	# The pill keeps its cap; a long circuit name shrinks the label instead.
	_play_button.fit_text()


# --------------------------------------------------------------------------
# vehicle


func _refresh_vehicle() -> void:
	## The garage roster follows the page: RACING saves the racing class, an
	## arena page saves the minigame car. Reading one slot for both meant a
	## saved chassis never appeared on the page that owned it.
	var id: String = GameSettings.racing_vehicle_id() \
		if _page == GAME_RACING else GameSettings.minigame_vehicle
	var entry: Dictionary = Catalog.find(id)
	if entry.is_empty():
		entry = Catalog.find(Catalog.DEFAULT_ID)
	_vehicle_button.text = "VEHICLE: " + str(entry.get("name", "SHOPPING CART"))
	_vehicle_button.set("fill_color", Color("8ed8f6"))
	_vehicle_button.fit_text()


func _on_change_vehicle() -> void:
	## Hand the page and the live picks to the garage, so coming back restores
	## the configuration instead of the last confirmed one.
	_return_page = _page
	_return_map = str(_current_map().get("id", ""))
	_return_theme = _selected_theme
	GameSettings.vehicle_return_scene = MINIGAMES_SCENE
	GameSettings.vehicle_return_title = "RACING" if _page == GAME_RACING \
		else "GAMES"
	GameSettings.vehicle_edit_minigame = true
	# The garage cannot know which page sent it for it to infer the roster:
	# GameSettings flips to the sandbox roster once a DELIVER arena is saved.
	VehicleSelect.set_racing_intent(_page == GAME_RACING)
	SceneLoader.go_to(VEHICLE_SCENE, "VEHICLE", "Choose your ride")


# --------------------------------------------------------------------------
# verification


func _run_selftest() -> void:
	## Headless hook (CART_MINIGAMES_SELFTEST=1): walks the real pressed signals
	## games -> RACING -> a map -> BACK -> DELIVER and prints the scene and map
	## id the confirm path would load. It never calls SceneLoader, so the race is
	## not built under --quit-after.
	if _game_cards.is_empty() or _map_cards.is_empty():
		print("MINIGAMES_SELFTEST missing_cards")
		get_tree().quit(1)
		return
	_game_card_for(GAME_RACING).emit_signal("pressed")
	await get_tree().process_frame
	var racing_page: bool = _page == GAME_RACING and _map_grid.visible
	var pick: int = clampi(1, 0, _map_cards.size() - 1)
	_map_cards[pick].emit_signal("pressed")
	await get_tree().process_frame
	var map_target: Dictionary = _confirm_target(_current_map(), false)
	var focus_ok: bool = MenuNav.focus(_map_cards[pick]) \
		and MenuNav.focused_control() == _map_cards[pick]
	_on_back()
	await get_tree().process_frame
	var back_ok: bool = _page == PAGE_GAMES and _games_page.visible
	var deliver_ok: bool = true
	var deliver_target: Dictionary = {}
	if not _deliver_entry.is_empty():
		_game_card_for(str(_deliver_entry.get("id", ""))).emit_signal("pressed")
		await get_tree().process_frame
		var deliver: Dictionary = _deliver_game_preset()
		deliver_target = _confirm_target(deliver, true)
		var theme_ok: bool = _theme_pill.has_theme_stylebox_override("focus") \
			and MenuNav.focus(_theme_pill) \
			and MenuNav.focused_control() == _theme_pill
		deliver_ok = theme_ok \
			and str(deliver_target.get("theme", "")) != "" \
			and not TrackDefs.theme_ids(deliver).is_empty()
	var map_ok: bool = str(map_target.get("scene", "")) == RACE_SCENE \
		and str(map_target.get("id", "")) != ""
	# Garage round trip: the page and the live picks must come back, not the
	# last confirmed ones.
	var return_map: String = str(_current_map().get("id", ""))
	_return_page = GAME_RACING
	_return_map = return_map
	_return_theme = "farmyard"
	var resume: String = _consume_return_state()
	_build_games()
	_initial_state()
	var restore_ok: bool = resume == GAME_RACING \
		and _restored_theme == "farmyard" \
		and str(_current_map().get("id", "")) == return_map
	print("MINIGAMES_SELFTEST page=%s scene=%s map=%s racing_page=%s back=%s "
		% [_page, str(map_target.get("scene", "")),
		str(map_target.get("id", "")), str(racing_page), str(back_ok)]
		+ "deliver_scene=%s deliver_theme=%s focus=%s restore=%s"
		% [str(deliver_target.get("scene", "")),
		str(deliver_target.get("theme", "")), str(focus_ok), str(restore_ok)])
	get_tree().quit(0 if map_ok and racing_page and back_ok and focus_ok \
		and deliver_ok and restore_ok else 1)
