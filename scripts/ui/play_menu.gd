extends Control
## Compact PLAY menu: SOLO / MULTIPLAYER tabs, one cycling BOTS pill and the
## two mode cards for the selected tab.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CANDY_BUTTON := "res://scripts/ui/candy_button.gd"
const PILL_CYCLER := "res://scripts/ui/pill_cycler.gd"

const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"

const BOT_LABELS: PackedStringArray = ["NO BOTS", "1 BOT", "2 BOTS", "3 BOTS", "4 BOTS", "5 BOTS"]
const BOT_VALUES: Array[int] = [0, 1, 2, 3, 4, 5]

var _body: VBoxContainer
var _single_tab: Button
var _multi_tab: Button
var _bots_pill: Button
var _single_box: VBoxContainer
var _multi_box: VBoxContainer
var _tab: int = GameSettings.MODE_SINGLE


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_body = $Center/Panel/Body
	_build_ui()
	_tab = GameSettings.play_mode
	_show_tab(_tab)
	_refresh_bots()


func _build_ui() -> void:
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", UiPalette.INK)
	title.text = "PLAY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	_body.add_child(tabs)
	_single_tab = _button("SINGLE PLAYER", UiPalette.YELLOW, 44, 20)
	_single_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_single_tab.pressed.connect(_show_tab.bind(GameSettings.MODE_SINGLE))
	tabs.add_child(_single_tab)
	_multi_tab = _button("MULTIPLAYER", UiPalette.BLUE, 44, 20)
	_multi_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_multi_tab.pressed.connect(_show_tab.bind(GameSettings.MODE_MULTIPLAYER))
	tabs.add_child(_multi_tab)

	_bots_pill = Button.new()
	_bots_pill.set_script(load(PILL_CYCLER))
	_bots_pill.set("corner_radius", 22)
	_bots_pill.set("shadow_offset", 6)
	_bots_pill.custom_minimum_size = Vector2(0, 44)
	_bots_pill.add_theme_font_size_override("font_size", 18)
	_bots_pill.call("configure", BOT_LABELS, BOT_VALUES, GameSettings.effective_bot_count())
	_bots_pill.connect("option_changed", _on_bots_changed)
	_body.add_child(_bots_pill)

	_single_box = VBoxContainer.new()
	_single_box.add_theme_constant_override("separation", 8)
	_body.add_child(_single_box)
	var single_row := HBoxContainer.new()
	single_row.add_theme_constant_override("separation", 8)
	_single_box.add_child(single_row)
	var sandbox := _button("SANDBOX", UiPalette.YELLOW, 54, 24)
	sandbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sandbox.pressed.connect(_on_single_sandbox)
	single_row.add_child(sandbox)
	var minigames := _button("MINIGAMES", UiPalette.GRASS, 54, 24)
	minigames.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minigames.pressed.connect(_on_single_minigames)
	single_row.add_child(minigames)

	_multi_box = VBoxContainer.new()
	_multi_box.add_theme_constant_override("separation", 8)
	_body.add_child(_multi_box)
	var multiplayer := _button("MULTIPLAYER LOBBY", UiPalette.BLUE, 56, 24)
	multiplayer.pressed.connect(_on_multi)
	_multi_box.add_child(multiplayer)
	var multiplayer_hint := Label.new()
	multiplayer_hint.text = "Host on your Wi-Fi, or join with a 5-letter room code."
	multiplayer_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	multiplayer_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	multiplayer_hint.add_theme_font_size_override("font_size", 14)
	multiplayer_hint.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	_multi_box.add_child(multiplayer_hint)

	var back := _button("BACK", UiPalette.RED, 48, 20)
	back.pressed.connect(_on_back)
	_body.add_child(back)


func _button(text: String, color: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.set("corner_radius", mini(int(height / 2), 28))
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _show_tab(tab: int) -> void:
	_tab = tab
	GameSettings.set_play_mode(tab)
	_single_box.visible = tab == GameSettings.MODE_SINGLE
	_multi_box.visible = tab == GameSettings.MODE_MULTIPLAYER
	_bots_pill.visible = tab == GameSettings.MODE_SINGLE
	_single_tab.set("fill_color", UiPalette.YELLOW if tab == GameSettings.MODE_SINGLE else UiPalette.TEXT_DIM)
	_multi_tab.set("fill_color", UiPalette.BLUE if tab == GameSettings.MODE_MULTIPLAYER else UiPalette.TEXT_DIM)


func _refresh_bots() -> void:
	var total: int = GameSettings.effective_bot_count()
	_bots_pill.call("set_index", total)
	_bots_pill.set("fill_color", UiPalette.GRASS if total > 0 else UiPalette.TEXT_DIM)


func _on_bots_changed(value: Variant) -> void:
	GameSettings.set_bot_total(int(value))
	_refresh_bots()


# --------------------------------------------------------------------------
# navigation


func _leave_session() -> void:
	if Network.is_session_active():
		Network.leave()


func _on_single_sandbox() -> void:
	_leave_session()
	GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	GameSettings.vehicle_edit_minigame = false
	GameSettings.vehicle_return_scene = ""
	SceneLoader.go_to(VEHICLE_SCENE, "SANDBOX", "PICK A VEHICLE")


func _on_single_minigames() -> void:
	_leave_session()
	GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	SceneLoader.go_to(MINIGAMES_SCENE, "MINIGAMES")


func _on_multi() -> void:
	GameSettings.set_play_mode(GameSettings.MODE_MULTIPLAYER)
	SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER",
		"Host on Wi-Fi or create a room on the Cart Slop server")


func _on_back() -> void:
	SceneLoader.go_to(MAIN_MENU_SCENE, "MAIN MENU")
