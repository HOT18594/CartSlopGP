extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## PLAY is a picker. Two big square cards (SINGLE / MULTIPLAYER), each with an
## icon and a label underneath, and one full-width BACK bar below.
##
## MULTIPLAYER goes straight to the lobby. There is no intermediate "click
## multiplayer again" screen. SINGLE keeps one short state because it has two
## real destinations (SANDBOX and MINIGAMES) plus the BOTS setting.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CANDY_BUTTON := "res://scripts/ui/candy_button.gd"
const PILL_CYCLER := "res://scripts/ui/pill_cycler.gd"
const PLAY_CARD := "res://scripts/ui/play_card.gd"

const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"

const BOT_LABELS: PackedStringArray = ["NO BOTS", "1 BOT", "2 BOTS", "3 BOTS", "4 BOTS", "5 BOTS"]
const BOT_VALUES: Array[int] = [0, 1, 2, 3, 4, 5]

@onready var _body: VBoxContainer = $Center/Panel/Body

var _title: Label
var _cards_row: HBoxContainer
var _single_box: VBoxContainer
var _back_bar: Button
var _bots_pill: Button
var _state: String = "picker" ## "picker" | "single"


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_build_ui()
	_show_state("picker", false)
	_refresh_bots()
	call_deferred("_enter")


func _enter() -> void:
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()


func _build_ui() -> void:
	_body.add_theme_constant_override("separation", 16)

	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override("font_size", 48)
	_title.add_theme_color_override("font_color", UiPalette.INK)
	_title.text = "PLAY"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(_title)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 24)
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(_cards_row)
	var single_card: Button = _card("SINGLE", UiPalette.YELLOW, false)
	single_card.pressed.connect(_on_single_card)
	_cards_row.add_child(single_card)
	var multi_card: Button = _card("MULTIPLAYER", UiPalette.BLUE, true)
	multi_card.pressed.connect(_on_multi_card)
	_cards_row.add_child(multi_card)

	_single_box = VBoxContainer.new()
	_single_box.add_theme_constant_override("separation", 12)
	_body.add_child(_single_box)
	_bots_pill = Button.new()
	_bots_pill.set_script(load(PILL_CYCLER))
	_bots_pill.set("corner_radius", 22)
	_bots_pill.set("shadow_offset", 6)
	_bots_pill.custom_minimum_size = Vector2(320, 48)
	_bots_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bots_pill.add_theme_font_size_override("font_size", 19)
	_bots_pill.call("configure", BOT_LABELS, BOT_VALUES, GameSettings.effective_bot_count())
	_bots_pill.connect("option_changed", _on_bots_changed)
	_single_box.add_child(_bots_pill)
	var single_row := HBoxContainer.new()
	single_row.add_theme_constant_override("separation", 12)
	single_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_single_box.add_child(single_row)
	var sandbox := _button("SANDBOX", UiPalette.YELLOW, 60, 24)
	sandbox.custom_minimum_size.x = 280
	sandbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sandbox.pressed.connect(_on_single_sandbox)
	single_row.add_child(sandbox)
	var minigames := _button("MINIGAMES", UiPalette.GRASS, 60, 24)
	minigames.custom_minimum_size.x = 280
	minigames.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	minigames.pressed.connect(_on_single_minigames)
	single_row.add_child(minigames)

	# One exit bar under everything, whatever state we are in.
	_back_bar = _button("BACK", UiPalette.RED, 54, 21)
	_back_bar.custom_minimum_size.x = 260
	_back_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back_bar.pressed.connect(_on_back)
	_body.add_child(_back_bar)


func _card(text: String, color: Color, two_carts: bool) -> Button:
	var button := Button.new()
	button.set_script(load(PLAY_CARD))
	button.set("fill_color", color)
	button.set("label_text", text)
	button.set("two_carts", two_carts)
	button.custom_minimum_size = Vector2(280, 270)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


func _button(text: String, color: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.set("corner_radius", mini(int(height / 2), 28))
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _show_state(state: String, animate: bool = true) -> void:
	_state = state
	_cards_row.visible = state == "picker"
	_single_box.visible = state == "single"
	if state == "single":
		_title.text = "SINGLE PLAYER"
		GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	else:
		_title.text = "PLAY"
	_back_bar.text = "BACK" if state == "picker" else "BACK TO PLAY"
	if animate:
		UiAnim.fade_in(_cards_row if state == "picker" else _single_box, 0.22)
	MenuNav.refresh()


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


func _on_single_card() -> void:
	_show_state("single")


func _on_multi_card() -> void:
	## No extra screen: the card IS the multiplayer button.
	GameSettings.set_play_mode(GameSettings.MODE_MULTIPLAYER)
	SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "Host or join a room")


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


func _on_back() -> void:
	if _state != "picker":
		_show_state("picker")
		return
	SceneLoader.go_to(MAIN_MENU_SCENE, "MAIN MENU")
