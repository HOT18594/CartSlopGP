extends Control
## Main menu: PLAY / SETTINGS / QUIT, disabled multiplayer placeholders and the
## update badge fed by the UpdateChecker autoload.

const PLAY_MENU_SCENE: String = "res://scenes/ui/play_menu.tscn"

@onready var _play_button: Button = %PlayButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _version_label: Label = %VersionLabel
@onready var _update_button: Button = %UpdateButton
@onready var _status_label: Label = %StatusLabel
@onready var _notes_button: Button = %NotesButton
@onready var _settings_menu: Control = %SettingsMenu

var _install_ready: bool = false


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_version_label.text = "v" + UpdateChecker.read_version_file()
	_update_button.visible = false
	_status_label.text = ""

	_play_button.pressed.connect(_on_play_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_update_button.pressed.connect(_on_update_pressed)
	_notes_button.pressed.connect(UpdateChecker.open_release_page)
	_settings_menu.closed.connect(_on_settings_closed)

	UpdateChecker.update_available.connect(_on_update_available)
	UpdateChecker.download_finished.connect(_on_download_finished)
	UpdateChecker.download_failed.connect(_on_download_failed)

	if UpdateChecker.has_update():
		if _can_auto_install() and UpdateChecker.has_downloaded_update(UpdateChecker.latest_version):
			_mark_install_ready()
		else:
			_on_update_available(UpdateChecker.latest_version, UpdateChecker.latest_release_url, UpdateChecker.latest_asset_url)

	_play_button.grab_focus()
	UpdateChecker.check_for_updates()


func _process(_delta: float) -> void:
	if not _install_ready and _update_button.visible and UpdateChecker.status == "checking":
		return
	if _update_button.visible and _update_button.disabled:
		var percent: int = int(round(UpdateChecker.get_download_ratio() * 100.0))
		_update_button.text = "DOWNLOADING %d%%" % percent


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(PLAY_MENU_SCENE)


func _on_settings_pressed() -> void:
	_settings_menu.open()


func _on_settings_closed() -> void:
	_play_button.grab_focus()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _can_auto_install() -> bool:
	## Only the Windows build can swap its own files (via update_install.bat).
	return OS.get_name() == "Windows"


func _on_update_available(version: String, release_url: String, download_url: String) -> void:
	if _can_auto_install() and UpdateChecker.has_downloaded_update(version):
		_mark_install_ready()
		return
	_install_ready = false
	_update_button.disabled = false
	_update_button.text = "UPDATE AVAILABLE  v%s" % version
	_update_button.tooltip_text = "Click to get v%s" % version
	_update_button.visible = true
	_notes_button.visible = release_url != ""
	_status_label.text = "New version %s is out" % version
	if download_url == "" and release_url != "":
		_update_button.tooltip_text = "Opens the GitHub release page"


func _on_update_pressed() -> void:
	if _install_ready:
		_install_update()
		return
	if not _can_auto_install():
		UpdateChecker.open_release_page()
		return
	if UpdateChecker.latest_asset_url == "":
		UpdateChecker.open_release_page()
		return
	_update_button.disabled = true
	_update_button.text = "DOWNLOADING 0%"
	UpdateChecker.download_update()


func _on_download_finished(_path: String) -> void:
	_mark_install_ready()


func _on_download_failed(_reason: String) -> void:
	_update_button.disabled = false
	_update_button.text = "UPDATE FAILED — OPEN PAGE"
	_update_button.tooltip_text = "Download failed. Click to open the release page instead."
	_update_button.pressed.disconnect(_on_update_pressed)
	_update_button.pressed.connect(UpdateChecker.open_release_page)


func _mark_install_ready() -> void:
	_install_ready = true
	_update_button.visible = true
	_update_button.disabled = false
	_update_button.text = "RESTART TO INSTALL  v%s" % UpdateChecker.latest_version
	_update_button.tooltip_text = "Unpacks the update, closes the game and relaunches it."
	_status_label.text = "Update downloaded — ready to install"


func _install_update() -> void:
	_status_label.text = "Installing update..."
	if not UpdateChecker.install_downloaded_update():
		_status_label.text = "Could not install automatically — use the release page."
		UpdateChecker.open_release_page()
