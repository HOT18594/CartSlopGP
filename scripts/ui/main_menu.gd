extends Control
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

	_play_button.grab_focus()
	UpdateChecker.check_for_updates()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(PLAY_MENU_SCENE)


func _on_settings_pressed() -> void:
	_settings_menu.open()


func _on_settings_closed() -> void:
	_settings_button.grab_focus()


func _on_changelog_pressed() -> void:
	_changelog_panel.open()


func _on_changelog_closed() -> void:
	_changelog_button.grab_focus()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_update_available(version: String) -> void:
	_update_button.text = "UPDATE AVAILABLE  v%s" % version
	_update_button.tooltip_text = "Download and install v%s" % version
	_update_button.visible = true
	_status_label.text = "New version %s is out" % version


func _on_update_pressed() -> void:
	_update_panel.open()


func _on_update_panel_closed() -> void:
	_play_button.grab_focus()
