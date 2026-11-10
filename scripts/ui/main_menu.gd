extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Main menu: PLAY / SETTINGS / QUIT and the update badge.

const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"

@onready var _play_button: Button = %PlayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _changelog_button: Button = %ChangelogButton
@onready var _quit_button: Button = %QuitButton
@onready var _version_label: Label = %VersionLabel
@onready var _update_button: Button = %UpdateButton
@onready var _status_label: Label = %StatusLabel
@onready var _settings_menu: Control = %SettingsMenu
@onready var _update_panel: Control = %UpdatePanel
@onready var _changelog_panel: Control = %ChangelogPanel

var _update_auto_opened: bool = false


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_version_label.text = "v" + UpdateChecker.read_version_file()
	_update_button.visible = false
	_status_label.text = ""

	_play_button.pressed.connect(_on_play_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_changelog_button.pressed.connect(_on_changelog_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_update_button.pressed.connect(_on_update_pressed)
	_settings_menu.closed.connect(_on_settings_closed)
	_update_panel.closed.connect(_on_update_panel_closed)
	_changelog_panel.closed.connect(_on_changelog_closed)

	UpdateChecker.update_available.connect(
		func(version: String, _release_url: String, _download_url: String) -> void:
			_on_update_available(version))
	if UpdateChecker.has_update():
		_on_update_available(UpdateChecker.latest_version)

	pass
	UpdateChecker.check_for_updates()
	call_deferred("_enter")


func _enter() -> void:
	UiAnim.pop($Center/Column/Buttons)
	MenuNav.refresh()


func _on_play_pressed() -> void:
	SceneLoader.go_to(PLAY_MENU_SCENE, "PLAY", "Choose a mode")


func _on_settings_pressed() -> void:
	_settings_menu.open()


func _on_settings_closed() -> void:
	pass


func _on_changelog_pressed() -> void:
	_changelog_panel.open()


func _on_changelog_closed() -> void:
	pass


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_update_available(version: String) -> void:
	_update_button.text = "UPDATE AVAILABLE  v%s" % version
	_update_button.tooltip_text = "Download and install v%s" % version
	_update_button.visible = true
	_status_label.text = "New version %s is out" % version
	# Surface the update automatically instead of waiting for the player to
	# notice the badge. Only once per launch; LATER keeps it as a badge.
	if not _update_auto_opened and not UpdateChecker.auto_prompted \
			and not _update_panel.visible and not _modal_visible():
		_update_auto_opened = true
		UpdateChecker.auto_prompted = true
		_open_update_soon()


func _modal_visible() -> bool:
	## Settings/Changelog are full-screen Controls in this same scene. Opening
	## the update dialog on top of one produced two overlapping modals (and the
	## update panel is declared before Changelog, so it could open underneath).
	return _settings_menu.visible or _changelog_panel.visible


func _open_update_soon() -> void:
	await get_tree().create_timer(0.45).timeout
	if not is_inside_tree() or _update_panel == null:
		return
	# The player may have opened Settings/Changelog during the prompt delay.
	# Keep the badge; do not stack a second full-screen dialog.
	if _modal_visible() or _update_panel.visible:
		return
	_update_panel.open()


func _on_update_pressed() -> void:
	_update_panel.open()


func _on_update_panel_closed() -> void:
	pass
