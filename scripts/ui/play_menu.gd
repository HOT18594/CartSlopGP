extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## PLAY is a picker. Two big square cards (SINGLE / MULTIPLAYER), each with an
## icon and a label underneath, and one full-width BACK bar below.
##
## MULTIPLAYER goes straight to the lobby. There is no intermediate "click
## multiplayer again" screen. SINGLE keeps one short state because it has two
## real destinations (SANDBOX and MINIGAMES) plus the BOTS setting.
##
## Opening SINGLE is a page change, not a mode change: the mode is written when
## one of its destinations launches, so BACK out of the page never rewinds the
## player's saved mode. The card of the mode that was launched last keeps a
## heavier outline, which is the picker's one selected state.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const PLAY_CARD := "res://scripts/ui/play_card.gd"

const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"

const BOT_LABELS: PackedStringArray = ["NONE", "1", "2", "3", "4", "5"]
const BOT_VALUES: Array[int] = [0, 1, 2, 3, 4, 5]
## Wide enough for "BACK TO PLAY" at the authored 19 px, so the one exit bar
## never changes type size between the two states of the screen.
const BACK_BAR_WIDTH: float = 280.0

@onready var _body: VBoxContainer = $Center/Panel/Body

var _title: Label
var _cards_row: HBoxContainer
var _single_box: VBoxContainer
var _back_bar: Button
var _bots_pill: Button
var _state: String = "picker" ## "picker" | "single"
var _single_card: Button
var _multi_card: Button
var _sandbox_button: Button
var _minigames_button: Button


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_build_ui()
	_show_state("picker", false)
	_refresh_bots()
	call_deferred("_enter")
	if OS.get_environment("CART_UI_MEASURE") == "1":
		_report_layout.call_deferred()


func _report_layout() -> void:
	## Verification hook (CART_UI_MEASURE=1): measures both states of the screen
	## in one boot and restores the picker, so nothing is left half-built. The
	## state change runs the real transition, so its tween is exercised too.
	await UiKit.report_screen(self, "play_menu:picker")
	_report_blocks("play_menu:picker")
	_show_state("single")
	await UiKit.report_screen(self, "play_menu:single")
	_report_blocks("play_menu:single")
	_show_state("picker", false)


func _report_blocks(tag: String) -> void:
	## Verification hook: the button sweep cannot describe the page frame, and
	## it is the panel height that decides whether 720 clips.
	var panel: Control = $Center/Panel
	print("UI_BLOCKS %s panel=%.0fx%.0f body=%.0fx%.0f fits720=%s"
		% [tag, panel.size.x, panel.size.y, _body.size.x, _body.size.y,
		str(panel.size.y <= UiKit.SCREEN_HEIGHT - UiKit.SCREEN_MARGIN * 2.0)])


func _enter() -> void:
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()
	if _state == "picker":
		var preferred: Button = _single_card
		if GameSettings.play_mode == GameSettings.MODE_MULTIPLAYER:
			preferred = _multi_card
		MenuNav.focus(preferred)


func _build_ui() -> void:
	_body.add_theme_constant_override("separation", UiKit.SPACING_WIDE)

	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override("font_size", UiKit.TITLE_SIZE)
	_title.add_theme_color_override("font_color", UiPalette.INK)
	_title.text = "PLAY"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_child(_title)

	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", UiKit.SPACING_WIDE)
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(_cards_row)
	_single_card = _card("SINGLE", UiPalette.YELLOW, false)
	_single_card.pressed.connect(_on_single_card)
	_cards_row.add_child(_single_card)
	_multi_card = _card("MULTIPLAYER", UiPalette.BLUE, true)
	_multi_card.pressed.connect(_on_multi_card)
	_cards_row.add_child(_multi_card)

	_single_box = VBoxContainer.new()
	_single_box.add_theme_constant_override("separation", UiKit.SPACING)
	_body.add_child(_single_box)
	# A small choice is a strip of equal tiles, not one pill stretched across
	# the screen. The caption above it names the setting, so it takes the tight
	# 8 px gap; the strip as a whole keeps the 16 px row gap.
	var bots_group := VBoxContainer.new()
	bots_group.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
	_single_box.add_child(bots_group)
	var bots_caption := Label.new()
	bots_caption.text = "BOTS"
	bots_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bots_caption.add_theme_font_size_override("font_size", UiKit.CAPTION_SIZE)
	bots_caption.add_theme_color_override("font_color", UiPalette.MUTED)
	bots_group.add_child(bots_caption)
	_bots_pill = UiKit.segmented(BOT_LABELS, BOT_VALUES,
		GameSettings.effective_bot_count(), 76.0, 52.0)
	_bots_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bots_pill.tooltip_text = "How many AI carts join the race."
	_bots_pill.connect("option_changed", _on_bots_changed)
	bots_group.add_child(_bots_pill)
	var single_row := HBoxContainer.new()
	single_row.add_theme_constant_override("separation", UiKit.SPACING)
	single_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_single_box.add_child(single_row)
	var sandbox := _button("SANDBOX", UiPalette.YELLOW, 72, 22)
	UiKit.cap_button(sandbox, 236.0)
	sandbox.tooltip_text = "Drive around the park on your own. No laps, no rivals."
	sandbox.pressed.connect(_on_single_sandbox)
	single_row.add_child(sandbox)
	_sandbox_button = sandbox
	var minigames := _button("MINIGAMES", UiPalette.GRASS, 72, 22)
	UiKit.cap_button(minigames, 236.0)
	minigames.tooltip_text = "Race the field on a real track."
	minigames.pressed.connect(_on_single_minigames)
	single_row.add_child(minigames)
	_minigames_button = minigames

	# One exit bar under everything, whatever state we are in.
	_back_bar = _button("BACK", UiPalette.RED, 54, 19)
	UiKit.cap_button(_back_bar, BACK_BAR_WIDTH)
	_back_bar.tooltip_text = "Back to the mode picker, then the main menu."
	_back_bar.pressed.connect(_on_back)
	_body.add_child(_back_bar)


func _card(text: String, color: Color, two_carts: bool) -> Button:
	## Two cards plus one 24 px gap stay well inside the 538 px body, so the
	## cards never touch the panel border (their 9 px drop shadow needs room).
	var button := Button.new()
	button.set_script(load(PLAY_CARD))
	button.set("fill_color", color)
	button.set("label_text", text)
	button.set("two_carts", two_carts)
	button.custom_minimum_size = Vector2(232, 216)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


func _button(text: String, color: Color, height: int, font_size: int) -> Button:
	return UiKit.tile(text, color, float(height), font_size)


func _show_state(state: String, animate: bool = true) -> void:
	_state = state
	_cards_row.visible = state == "picker"
	_single_box.visible = state == "single"
	if state == "single":
		_title.text = "SINGLE PLAYER"
	else:
		_title.text = "PLAY"
	_back_bar.text = "BACK" if state == "picker" else "BACK TO PLAY"
	# The bar keeps its authored width; the longer label shrinks into it.
	_back_bar.fit_text()
	_mark_mode_cards()
	if animate:
		_transition(_cards_row if state == "picker" else _single_box)
	MenuNav.refresh()
	# Land on the action the state is for, not on whatever was focused before.
	if state == "single" and _sandbox_button != null:
		MenuNav.focus(_sandbox_button)
	elif state == "picker" and _single_card != null:
		MenuNav.focus(_single_card)


func _transition(page: Control) -> void:
	## Page change: fade plus a small settle, so an incoming page never snaps.
	## Scale and modulate are not owned by the VBox, unlike position.
	page.pivot_offset = page.size * 0.5
	page.scale = Vector2.ONE * 0.97
	UiAnim.fade_in(page, 0.20)
	var tween: Tween = page.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(page, "scale", Vector2.ONE, 0.24) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _mark_mode_cards() -> void:
	## The picker remembers the mode that was launched last: that card carries a
	## heavier ink outline, while the fill and the drop shadow stay play_card's.
	## This is the only selected state the picker has, so it never changes hue.
	if _single_card == null or _multi_card == null:
		return
	var single_selected: bool = GameSettings.play_mode != GameSettings.MODE_MULTIPLAYER
	_outline(_single_card, single_selected)
	_outline(_multi_card, not single_selected)


func _outline(card: Button, selected: bool) -> void:
	## Duplicate the card's authored boxes and only change the border weight, so
	## the card keeps every other authored style value.
	for state: String in ["normal", "hover", "pressed"]:
		var base: StyleBox = card.get_theme_stylebox(state)
		if not (base is StyleBoxFlat):
			continue
		var ring: StyleBoxFlat = (base as StyleBoxFlat).duplicate() as StyleBoxFlat
		ring.set_border_width_all(9 if selected else 6)
		card.add_theme_stylebox_override(state, ring)


func _refresh_bots() -> void:
	var total: int = GameSettings.effective_bot_count()
	_bots_pill.call("set_index", total)


func _on_bots_changed(value: Variant) -> void:
	GameSettings.set_bot_total(int(value))
	_refresh_bots()


func _unhandled_input(event: InputEvent) -> void:
	## Escape walks one step back, exactly like the BACK bar.
	if event.is_action_pressed("ui_cancel") and not SceneLoader.is_busy():
		_on_back()
		get_viewport().set_input_as_handled()


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
