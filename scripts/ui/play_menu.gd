extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## PLAY screen: two hero cards (SOLO / MULTIPLAYER) with zero middleman submenus.
## SOLO jumps straight to SELECT MODE (all 5 modes front-and-center);
## MULTIPLAYER jumps straight to the room lobby.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const PLAY_CARD := "res://scripts/ui/play_card.gd"

const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const BACK_BAR_WIDTH: float = 220.0

@onready var _body: VBoxContainer = $Center/Panel/Body

var _title: Label
var _cards_row: HBoxContainer
var _back_bar: Button
var _single_card: Button
var _multi_card: Button


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_build_ui()
	_mark_mode_cards()
	call_deferred("_enter")
	if OS.get_environment("CART_UI_MEASURE") == "1":
		_report_layout.call_deferred()


func _report_layout() -> void:
	await UiKit.report_screen(self, "play_menu:picker")
	_report_blocks("play_menu:picker")


func _report_blocks(tag: String) -> void:
	var panel: Control = $Center/Panel
	print("UI_BLOCKS %s panel=%.0fx%.0f body=%.0fx%.0f fits720=%s"
		% [tag, panel.size.x, panel.size.y, _body.size.x, _body.size.y,
		str(panel.size.y <= UiKit.SCREEN_HEIGHT - UiKit.SCREEN_MARGIN * 2.0)])


func _enter() -> void:
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()
	var preferred: Button = _single_card
	if GameSettings.play_mode == GameSettings.MODE_MULTIPLAYER:
		preferred = _multi_card
	MenuNav.focus(preferred)


func _build_ui() -> void:
	_body.add_theme_constant_override("separation", 20)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 4)
	_body.add_child(title_box)

	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override("font_size", UiKit.TITLE_SIZE)
	_title.add_theme_color_override("font_color", UiPalette.INK)
	_title.text = "PLAY"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(_title)

	var sub := UiKit.label("RACING  ·  DELIVER  ·  KNOCKOUT  ·  BLAST TAG  ·  SANDBOX",
		13, UiPalette.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_box.add_child(sub)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", UiKit.SPACING_WIDE)
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(_cards_row)

	_single_card = _card("SOLO", "SINGLE PLAYER", UiPalette.YELLOW, false)
	_single_card.name = "SoloCard"
	_single_card.pressed.connect(_on_solo_card)
	_cards_row.add_child(_single_card)

	_multi_card = _card("MULTIPLAYER", "ONLINE · LAN", UiPalette.BLUE, true)
	_multi_card.name = "MultiplayerCard"
	_multi_card.pressed.connect(_on_multi_card)
	_cards_row.add_child(_multi_card)

	_back_bar = _button("BACK", UiPalette.RED, 52, 19)
	_back_bar.name = "BackButton"
	UiKit.cap_button(_back_bar, BACK_BAR_WIDTH)
	_back_bar.pressed.connect(_on_back)
	_body.add_child(_back_bar)


func _card(text: String, badge: String, color: Color, two_carts: bool) -> Button:
	var button := Button.new()
	button.set_script(load(PLAY_CARD))
	button.set("fill_color", color)
	button.set("label_text", text)
	button.set("badge_text", badge)
	button.set("two_carts", two_carts)
	button.custom_minimum_size = Vector2(252, 240)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


func _button(text: String, color: Color, height: int, font_size: int) -> Button:
	return UiKit.tile(text, color, float(height), font_size)


func _mark_mode_cards() -> void:
	if _single_card == null or _multi_card == null:
		return
	var single_selected: bool = GameSettings.play_mode != GameSettings.MODE_MULTIPLAYER
	_outline(_single_card, single_selected)
	_outline(_multi_card, not single_selected)


func _outline(card: Button, selected: bool) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var base: StyleBox = card.get_theme_stylebox(state)
		if not (base is StyleBoxFlat):
			continue
		var ring: StyleBoxFlat = (base as StyleBoxFlat).duplicate() as StyleBoxFlat
		ring.set_border_width_all(9 if selected else 6)
		card.add_theme_stylebox_override(state, ring)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not SceneLoader.is_busy():
		_on_back()
		get_viewport().set_input_as_handled()


func _leave_session() -> void:
	if Network.is_session_active():
		Network.leave()


func _on_solo_card() -> void:
	_leave_session()
	GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	SceneLoader.go_to(MINIGAMES_SCENE, "SELECT MODE", "Pick a game mode")


func _on_multi_card() -> void:
	GameSettings.set_play_mode(GameSettings.MODE_MULTIPLAYER)
	SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "Create or join a room")


func _on_back() -> void:
	SceneLoader.go_to(MAIN_MENU_SCENE, "MAIN MENU")
