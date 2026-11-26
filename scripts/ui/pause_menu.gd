extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const SlantedShell := preload("res://scripts/ui/slanted_shell.gd")
## Esc shows RESUME / SETTINGS / QUIT TO MENU in the 0.8.5 dark-glass slanted
## parallelogram racing-sim telemetry shell.
##
## Single player: the world pauses.
## Multiplayer: the world keeps running in the background, Minecraft-style.
## Opening this menu never changes the room state on the Pi and never pauses
## the server. Settings still work because this layer is PROCESS_MODE_ALWAYS.

const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const SINGLE_HINT: String = "SINGLE PLAYER  ·  THE RACE IS PAUSED"
const MULTIPLAYER_HINT: String = "MULTIPLAYER  ·  THE GAME KEEPS RUNNING"
const QUIT_WARNING: String = "HOST: QUITTING CLOSES THE ROOM FOR EVERYONE"
const CLOSE_HINT: String = "ESC OR START CLOSES THIS MENU"

@onready var _panel: PanelContainer = $Center/Panel
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
## WS5-07: the host dropped out of a live match. The match scene (and its local
## standings) is kept frozen behind this overlay; only MAIN MENU leaves.
var _host_lost: bool = false
## WS5P3-14: while the result card's Cancel/Leave confirm gate is open, ESC must
## cancel THAT dialog and may never open this menu behind it. The gate calls
## `set_input_suspended(true)` instead of reaching in and toggling node flags, so
## the isolation no longer depends on which node of the scene owns the script.
var _input_suspended: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("nav_scope")
	UiKit.apply_scrim(get_node_or_null("Dim") as ColorRect)
	_apply_dark_parallelogram_shell()
	_mode_hint = Label.new()
	_mode_hint.name = "ModeHint"
	_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_hint.add_theme_font_size_override("font_size", 15)
	_mode_hint.add_theme_color_override("font_color", UiPalette.RED)
	_mode_hint.text = ""
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
	# WS5-07: Network keeps the match scene when the host leaves, so this menu
	# owns the HOST DISCONNECTED overlay for every match scene.
	Network.match_host_lost.connect(_on_match_host_lost)
	# WS5P3-01: if the host-left signal fired while the previous scene was being
	# swapped out, the notice was parked on Network instead of being lost. Pick it
	# up now that this overlay exists for the scene that actually mounted.
	if Network.has_method("consume_match_host_lost_pending"):
		var pending: String = str(Network.consume_match_host_lost_pending())
		if pending != "":
			call_deferred("_on_match_host_lost", pending)


func _apply_dark_parallelogram_shell() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(520, 0)
	_panel.add_theme_stylebox_override("panel", UiKit.modal_shell_style(42.0, 28.0))
	var bg: Control = SlantedShell.new()
	bg.name = "SlantedBackdrop"
	bg.set("skew_px", 20.0)
	bg.set("pad_x", 28.0)
	bg.set("pad_y", 22.0)
	_panel.add_child(bg)
	_panel.move_child(bg, 0)
	if _title != null:
		_title.add_theme_font_size_override("font_size", UiKit.TITLE_SIZE)
		_title.add_theme_color_override("font_color", UiPalette.TEXT)
		_title.add_theme_color_override("font_outline_color", UiPalette.OUTLINE)
		_title.add_theme_constant_override("outline_size", UiKit.TITLE_OUTLINE)


func _add_close_hint() -> void:
	var hint := Label.new()
	hint.name = "CloseHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	hint.text = CLOSE_HINT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.get_parent().add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	# WS5P3-14: a modal above this menu (the result card's confirm gate) owns
	# ESC/START while it is open. Refuse every action, including open().
	if _input_suspended:
		return
	if _host_lost:
		# The match is over and the local result is frozen: ESC/START must not
		# close the overlay onto an unpaused, empty race. MAIN MENU is the exit.
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		UiKit.consume_input(self)
		if SceneLoader.is_busy():
			return
		if _settings_menu.visible:
			_settings_menu.close()
			return
		if _is_open:
			close()
		else:
			open()


func set_input_suspended(suspended: bool) -> void:
	## WS5P3-14: called by the result card's confirm gate (result_screen.gd) for
	## the lifetime of the Cancel/Leave dialog. While suspended this menu keeps
	## processing (so its state is untouched) but every ESC/START is refused, so
	## the dialog always wins regardless of unhandled-input dispatch order.
	_input_suspended = suspended


func is_input_suspended() -> bool:
	return _input_suspended


func open() -> void:
	if _is_open or SceneLoader.is_busy():
		return
	_is_open = true
	_multiplayer = Network.is_session_active()
	visible = true
	_title.text = "MENU" if _multiplayer else "PAUSED"
	_resume_button.text = "BACK TO GAME" if _multiplayer else "RESUME"
	_fit(_resume_button)
	_quit_ticket += 1
	_reset_quit_button()
	# WS5P3-06: the mode hint was dead code before. A normal multiplayer pause
	# must tell the player the world keeps running; a solo pause says it froze.
	_mode_hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	_mode_hint.text = MULTIPLAYER_HINT if _multiplayer else SINGLE_HINT
	_mode_hint.visible = true
	Network.input_locked = _multiplayer
	get_tree().paused = not _multiplayer
	CursorController.set_menu_mode(true)
	UiAnim.modal_open($Center/Panel, get_node_or_null("Dim"))
	UiAnim.stagger_slide([_resume_button, _settings_button, _quit_button],
		Vector2(-24.0, 0.0), 0.045, 0.22)
	MenuNav.refresh()
	MenuNav.focus(_resume_button)


func close() -> void:
	if not _is_open or _host_lost:
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
	MenuNav.refresh()
	MenuNav.focus(_settings_button)


func _on_quit_pressed() -> void:
	if Network.is_host and Network.is_session_active() and not _quit_armed:
		_quit_armed = true
		_quit_ticket += 1
		var ticket: int = _quit_ticket
		_quit_button.text = "CONFIRM QUIT"
		_fit(_quit_button)
		_mode_hint.add_theme_color_override("font_color", UiPalette.RED)
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
		_quit_button.text = "QUIT"
		_fit(_quit_button)
	if _mode_hint != null:
		_mode_hint.text = ""
		_mode_hint.visible = false


func _fit(button: Button) -> void:
	if button != null and button.has_method("fit_text"):
		button.call("fit_text")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# Deferred: a menu must never be opened from inside a notification, and
		# the deferred frame lets an in-flight window/scene transition settle.
		call_deferred("_on_application_focus_out")


func _on_application_focus_out() -> void:
	## WS5-04: auto-pause a SOLO game when the app loses focus (Alt-Tab, or a
	## browser tab losing focus). Multiplayer never pauses - the world keeps
	## running for everyone else, and this menu's MP branch only locks local
	## input anyway. Scene loads, an already-paused tree, an open menu/modal
	## (the race result card) and the COMFORT setting all opt out.
	if not is_inside_tree() or _is_open or SceneLoader.is_busy():
		return
	if not GameSettings.pause_on_focus_loss:
		return
	if Network.is_session_active():
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return
	var scene: Node = tree.current_scene
	if scene == null or not (scene == self or scene.is_ancestor_of(self)):
		return
	if _another_menu_visible():
		return
	open()


func _on_match_host_lost(reason: String) -> void:
	## WS5-07: the host left mid-match. Network keeps this match scene alive, so
	## freeze it behind a clear overlay that leaves the local standings readable
	## instead of destroying the result screen with a lobby reload.
	## WS5P3-01: consume the parked notice (the same event may have been delivered
	## through the pending path when this scene mounted after the signal fired).
	if Network.has_method("consume_match_host_lost_pending"):
		Network.consume_match_host_lost_pending()
	if not is_inside_tree() or _host_lost:
		return
	_host_lost = true
	if not _is_open:
		open()
	_title.text = "HOST DISCONNECTED"
	_resume_button.visible = false
	_quit_button.text = "MAIN MENU"
	_fit(_quit_button)
	_mode_hint.add_theme_color_override("font_color", UiPalette.RED)
	_mode_hint.text = reason if reason != "" \
		else "The host left the room. The match result stays on screen."
	_mode_hint.visible = true
	MenuNav.refresh()
	MenuNav.focus(_quit_button)


func _exit_tree() -> void:
	Network.input_locked = false
	get_tree().paused = false
