extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
## Esc shows RESUME / SETTINGS / QUIT TO MENU.
##
## Single player: the world pauses.
## Multiplayer: the world keeps running in the background, Minecraft-style.
## Opening this menu never changes the room state on the Pi and never pauses
## the server. Settings still work because this layer is PROCESS_MODE_ALWAYS.

const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const SINGLE_HINT: String = "SINGLE PLAYER  -  THE RACE IS PAUSED"
const MULTIPLAYER_HINT: String = "MULTIPLAYER  -  THE GAME KEEPS RUNNING"
const QUIT_WARNING: String = "HOST: QUITTING CLOSES THE ROOM FOR EVERYONE"
const CLOSE_HINT: String = "ESC OR START CLOSES THIS MENU"

@onready var _title: Label = $Center/Panel/Body/Title
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %PauseSettingsButton
@onready var _quit_button: Button = %QuitToMenuButton
@onready var _settings_menu: Control = %SettingsMenu

var _is_open: bool = false
var _multiplayer: bool = false
var _mode_hint: Label
var _quit_armed: bool = false
var _quit_ticket: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("nav_scope")
	_mode_hint = Label.new()
	_mode_hint.name = "ModeHint"
	_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_hint.add_theme_font_size_override("font_size", 15)
	_mode_hint.add_theme_color_override("font_color", UiPalette.MUTED)
	_mode_hint.text = SINGLE_HINT
	_mode_hint.visible = false
	_mode_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.get_parent().add_child(_mode_hint)
	_title.get_parent().move_child(_mode_hint, _title.get_index() + 1)
	_add_close_hint()
	hide()
	_resume_button.pressed.connect(close)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_menu.closed.connect(_on_settings_closed)


func _add_close_hint() -> void:
	## One quiet footer line, matching Settings' help line: the menu explains
	## the key that dismisses it instead of leaving the player to guess.
	var hint := Label.new()
	hint.name = "CloseHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", UiPalette.MUTED)
	hint.text = CLOSE_HINT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.get_parent().add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		# The loading overlay owns input while a scene is being swapped. An
		# old pause menu can still be in the tree during that transition;
		# opening it there paused the tree and the next scene came up frozen.
		if SceneLoader.is_busy():
			get_viewport().set_input_as_handled()
			return
		if _settings_menu.visible:
			# Escape closes the topmost overlay only: Settings, then this menu
			# on the next press. Close it here instead of relying on the child
			# handler's tree order, so one Escape can never close both layers.
			_settings_menu.close()
			get_viewport().set_input_as_handled()
			return
		if _is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	if _is_open or SceneLoader.is_busy():
		return
	_is_open = true
	_multiplayer = Network.is_session_active()
	# Show and lay out the menu *before* pausing: a paused tree does not flush
	# the redraw of a Control that only just became visible.
	visible = true
	_title.text = "MENU" if _multiplayer else "PAUSED"
	_resume_button.text = "BACK TO GAME" if _multiplayer else "RESUME"
	# The label changes with the mode, so the candy shrink-to-fit has to run
	# again; a stale fit left the longer multiplayer label uncapped.
	_fit(_resume_button)
	_quit_ticket += 1
	_reset_quit_button()
	# Multiplayer is a live world: do not pause the tree or the server.
	# Lock driving input while the menu is open.
	Network.input_locked = _multiplayer
	get_tree().paused = not _multiplayer
	CursorController.set_menu_mode(true)
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()
	MenuNav.focus(_resume_button)


func close() -> void:
	if not _is_open:
		return
	if _settings_menu.visible:
		_settings_menu.close()
	_quit_ticket += 1
	_reset_quit_button()
	_is_open = false
	visible = false
	$Center/Panel.scale = Vector2.ONE
	$Center/Panel.modulate = Color.WHITE
	MenuNav.refresh()
	Network.input_locked = false
	get_tree().paused = false
	# The result card can be underneath the pause menu. Keep the cursor in
	# menu mode if another nav_scope overlay is still visible, or the player
	# is stranded on the finish screen with a captured mouse.
	CursorController.set_menu_mode(_another_menu_visible())


func _another_menu_visible() -> bool:
	for node: Node in get_tree().get_nodes_in_group("nav_scope"):
		if node == self or not (node is CanvasItem):
			continue
		if (node as CanvasItem).visible:
			return true
	return false


func _on_settings_pressed() -> void:
	if _settings_menu.visible:
		return
	_settings_menu.open()


func _on_settings_closed() -> void:
	## Escape/Back from Settings returns the ring to the button that opened it
	## instead of leaving the pause menu without a visible selection.
	MenuNav.refresh()
	MenuNav.focus(_settings_button)


func _on_quit_pressed() -> void:
	# In a live session the host owns the room: one click used to drop every
	# client with no warning. Match the lobby's two-click LEAVE confirmation.
	if Network.is_host and Network.is_session_active() and not _quit_armed:
		_quit_armed = true
		_quit_ticket += 1
		var ticket: int = _quit_ticket
		_quit_button.text = "CONFIRM QUIT"
		_fit(_quit_button)
		_mode_hint.text = QUIT_WARNING
		_mode_hint.visible = true
		await get_tree().create_timer(3.0).timeout
		if is_inside_tree() and _quit_armed and ticket == _quit_ticket:
			_reset_quit_button()
		return
	_quit_ticket += 1
	_reset_quit_button()
	_is_open = false
	visible = false
	Network.input_locked = false
	get_tree().paused = false
	if Network.is_session_active():
		Network.leave()
	SceneLoader.go_to(MAIN_MENU_SCENE, "MAIN MENU")


func _reset_quit_button() -> void:
	_quit_armed = false
	if _quit_button != null:
		_quit_button.text = "QUIT TO MENU"
		_fit(_quit_button)
	if _mode_hint != null:
		# The mode line is part of the menu, not a multiplayer-only warning:
		# single player says plainly that the race is paused.
		_mode_hint.text = MULTIPLAYER_HINT if _multiplayer else SINGLE_HINT
		_mode_hint.visible = true


func _fit(button: Button) -> void:
	## Candy buttons shrink their label to the authored width. Labels rewritten
	## at runtime have to ask for that fit again.
	if button != null and button.has_method("fit_text"):
		button.call("fit_text")


func _exit_tree() -> void:
	Network.input_locked = false
	# A pause menu destroyed by a scene swap must never leave the new scene
	# frozen. The SceneLoader also clears this defensively.
	get_tree().paused = false
