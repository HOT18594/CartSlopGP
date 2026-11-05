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
@onready var _back_button: Button = %BackButton

var _refreshing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_master_slider.value_changed.connect(_on_master_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	_cursor_toggle.toggled.connect(_on_cursor_toggled)
	_back_button.pressed.connect(_on_back_pressed)


func open() -> void:
	_refresh()
	show()
	visible = true
	_offline_note.visible = UpdateChecker.status == "offline" or UpdateChecker.status == "error"
	_master_slider.grab_focus()


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


func _on_back_pressed() -> void:
	close()


func close() -> void:
	hide()
	closed.emit()
