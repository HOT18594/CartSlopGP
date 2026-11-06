extends Control
## Settings overlay used by both the main menu and the pause menu.

signal closed

@onready var _master_slider: HSlider = %MasterSlider
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _master_value: Label = %MasterValue
@onready var _sfx_value: Label = %SfxValue
@onready var _fullscreen_toggle: CheckButton = %FullscreenToggle
@onready var _cursor_toggle: CheckButton = %CursorToggle
@onready var _offline_note: Label = %OfflineNote
@onready var _check_button: Button = %CheckUpdatesButton
@onready var _update_status: Label = %UpdateStatus
@onready var _back_button: Button = %BackButton

var _refreshing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_master_slider.value_changed.connect(_on_master_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	_cursor_toggle.toggled.connect(_on_cursor_toggled)
	_check_button.pressed.connect(_on_check_updates)
	_update_status.text = ""
	_back_button.pressed.connect(_on_back_pressed)
	UpdateChecker.check_finished.connect(_on_check_finished)
	# Keep Tab focus inside the overlay instead of leaking to the menu behind.
	_master_slider.focus_previous = _master_slider.get_path_to(_back_button)
	_back_button.focus_next = _back_button.get_path_to(_master_slider)


func open() -> void:
	_refresh()
	show()
	visible = true
	_offline_note.visible = UpdateChecker.status == "offline" or UpdateChecker.status == "error"
	_check_button.disabled = false
	if UpdateChecker.status == "available":
		_update_status.text = "v%s available" % UpdateChecker.latest_version
	elif UpdateChecker.status == "up_to_date":
		_update_status.text = "Up to date (v%s)" % UpdateChecker.local_version()
	else:
		_update_status.text = ""
	_master_slider.grab_focus()


func _on_check_updates() -> void:
	if UpdateChecker.is_downloading():
		_update_status.text = "Update downloading..."
		return
	_check_button.disabled = true
	_update_status.text = "Checking for updates..."
	UpdateChecker.check_for_updates()
	get_tree().create_timer(8.0).timeout.connect(_re_enable_check)


func _re_enable_check() -> void:
	if is_instance_valid(_check_button):
		_check_button.disabled = false


func _on_check_finished(available: bool) -> void:
	if not visible:
		return
	_check_button.disabled = false
	if available:
		_update_status.text = "v%s available - open it from the main menu" % UpdateChecker.latest_version
	elif UpdateChecker.status == "up_to_date":
		_update_status.text = "Up to date (v%s)" % UpdateChecker.local_version()
	elif UpdateChecker.status == "offline":
		_update_status.text = "Offline - couldn't reach the update server"
	else:
		_update_status.text = "Check failed - try again later"


func _refresh() -> void:
	_refreshing = true
	_master_slider.value = GameSettings.master_volume * 100.0
	_sfx_slider.value = GameSettings.sfx_volume * 100.0
	_fullscreen_toggle.button_pressed = GameSettings.fullscreen
	_cursor_toggle.button_pressed = GameSettings.custom_cursor
	_update_value_labels()
	_refreshing = false


func _update_value_labels() -> void:
	_master_value.text = "%d%%" % int(round(_master_slider.value))
	_sfx_value.text = "%d%%" % int(round(_sfx_slider.value))


func _on_master_changed(value: float) -> void:
	if _refreshing:
		return
	GameSettings.set_master_volume(value / 100.0)
	_update_value_labels()


func _on_sfx_changed(value: float) -> void:
	if _refreshing:
		return
	GameSettings.set_sfx_volume(value / 100.0)
	_update_value_labels()


func _on_fullscreen_toggled(pressed: bool) -> void:
	if _refreshing:
		return
	GameSettings.set_fullscreen(pressed)


func _on_cursor_toggled(pressed: bool) -> void:
	if _refreshing:
		return
	GameSettings.set_custom_cursor(pressed)
	CursorController.set_menu_mode(CursorController.is_menu_mode())


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	close()


func close() -> void:
	hide()
	closed.emit()
