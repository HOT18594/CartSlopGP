extends Control
## Mode select shown after PLAY.
##
## PLAY now branches into SINGLE PLAYER and MULTIPLAYER. Both branches offer
## SANDBOX and MINIGAMES, and both share the same opt-in AI BOTS controls.
## Multiplayer goes through the network lobby, where the host picks LAN/Wi-Fi
## or Online and can open the minigame menu for the whole session.
##
## The panel is built in code so the two tabs can share one layout.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CANDY_BUTTON := "res://scripts/ui/candy_button.gd"

const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"

var _body: VBoxContainer
var _single_tab: Button
var _multi_tab: Button
var _bots_button: Button
var _count_button: Button
var _bots_hint: Label
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
	title.add_theme_font_size_override("font_size", 50)
	title.add_theme_color_override("font_color", UiPalette.INK)
	title.text = "PLAY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(title)

	var subtitle := Label.new()
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	subtitle.text = "SINGLE PLAYER OR MULTIPLAYER"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(subtitle)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	_body.add_child(tabs)
	_single_tab = _button("SINGLE PLAYER", UiPalette.YELLOW, 48, 22)
	_single_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_single_tab.pressed.connect(_show_tab.bind(GameSettings.MODE_SINGLE))
	tabs.add_child(_single_tab)
	_multi_tab = _button("MULTIPLAYER", UiPalette.BLUE, 48, 22)
	_multi_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_multi_tab.pressed.connect(_show_tab.bind(GameSettings.MODE_MULTIPLAYER))
	tabs.add_child(_multi_tab)

	var bots_row := HBoxContainer.new()
	bots_row.add_theme_constant_override("separation", 10)
	_body.add_child(bots_row)
	_bots_button = _button("BOTS: OFF", UiPalette.RED, 46, 19)
	_bots_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bots_button.pressed.connect(_on_bots_toggled)
	bots_row.add_child(_bots_button)
	_count_button = _button("BOTS: 3", UiPalette.TEXT_DIM, 46, 19)
	_count_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_button.pressed.connect(_on_bot_count)
	bots_row.add_child(_count_button)

	_bots_hint = Label.new()
	_bots_hint.add_theme_font_size_override("font_size", 13)
	_bots_hint.add_theme_color_override("font_color", UiPalette.INK)
	_bots_hint.text = "AI carts are OFF. Turn them on for company in the sandbox."
	_bots_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bots_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_bots_hint)

	_single_box = VBoxContainer.new()
	_single_box.add_theme_constant_override("separation", 10)
	_body.add_child(_single_box)
	var sandbox := _button("SANDBOX", UiPalette.YELLOW, 62, 28)
	sandbox.pressed.connect(_on_single_sandbox)
	_single_box.add_child(sandbox)
	var minigames := _button("MINIGAMES", UiPalette.GRASS, 62, 28)
	minigames.pressed.connect(_on_single_minigames)
	_single_box.add_child(minigames)
	_single_box.add_child(_hint("Drive the open arena, or pick a minigame and race. Bots are optional."))

	_multi_box = VBoxContainer.new()
	_multi_box.add_theme_constant_override("separation", 10)
	_body.add_child(_multi_box)
	var mp_sandbox := _button("SANDBOX SESSION", UiPalette.BLUE, 54, 23)
	mp_sandbox.pressed.connect(_on_multi.bind(GameSettings.GAME_SANDBOX))
	_multi_box.add_child(mp_sandbox)
	var mp_minigames := _button("MINIGAME SESSION", UiPalette.CYAN, 54, 23)
	mp_minigames.pressed.connect(_on_multi.bind(GameSettings.GAME_MINIGAMES))
	_multi_box.add_child(mp_minigames)
	_multi_box.add_child(_hint("Host or join over Wi-Fi (LAN) or Online. The host picks the mode; everyone loads the same world."))

	var back := _button("BACK", UiPalette.RED, 52, 22)
	back.pressed.connect(_on_back)
	_body.add_child(back)


func _hint(text: String) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(text: String, color: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _show_tab(tab: int) -> void:
	_tab = tab
	GameSettings.set_play_mode(tab)
	_single_box.visible = tab == GameSettings.MODE_SINGLE
	_multi_box.visible = tab == GameSettings.MODE_MULTIPLAYER
	_single_tab.set("fill_color", UiPalette.YELLOW if tab == GameSettings.MODE_SINGLE else UiPalette.TEXT_DIM)
	_multi_tab.set("fill_color", UiPalette.BLUE if tab == GameSettings.MODE_MULTIPLAYER else UiPalette.TEXT_DIM)


func _refresh_bots() -> void:
	var on: bool = GameSettings.bots_enabled
	_bots_button.text = "BOTS: ON" if on else "BOTS: OFF"
	_bots_button.set("fill_color", UiPalette.GRASS if on else UiPalette.RED)
	_count_button.text = "BOTS: %d" % GameSettings.bot_count
	_count_button.set("fill_color", UiPalette.YELLOW if on else UiPalette.TEXT_DIM)
	_count_button.disabled = not on
	_bots_hint.text = "%d AI carts will cruise the sandbox with you." % GameSettings.bot_count \
		if on else "AI carts are OFF. Turn them on for company in the sandbox."


func _on_bots_toggled() -> void:
	GameSettings.set_bots_enabled(not GameSettings.bots_enabled)
	_refresh_bots()


func _on_bot_count() -> void:
	GameSettings.set_bot_count((GameSettings.bot_count + 1) % 6)
	_refresh_bots()


# --------------------------------------------------------------------------
# navigation


func _leave_session() -> void:
	if Network.is_session_active():
		Network.leave()


func _on_single_sandbox() -> void:
	_leave_session()
	GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	SceneLoader.go_to(VEHICLE_SCENE, "SANDBOX", "PICK A VEHICLE")


func _on_single_minigames() -> void:
	_leave_session()
	GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	SceneLoader.go_to(MINIGAMES_SCENE, "MINIGAMES")


func _on_multi(mode: String) -> void:
	GameSettings.set_play_mode(GameSettings.MODE_MULTIPLAYER)
	GameSettings.set_multiplayer_mode(mode)
	SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER",
		"Wi-Fi (LAN) or Online - host picks the mode")


func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
