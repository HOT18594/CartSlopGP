extends Control
## Update dialog: check result, download with a real progress bar, then
## "RESTART & UPDATE" (desktop builds install and relaunch in place).

signal closed

@onready var _version_label: Label = %VersionLabel
@onready var _notes_label: Label = %NotesLabel
@onready var _progress_bar: ProgressBar = %UpdateProgress
@onready var _progress_label: Label = %ProgressLabel
@onready var _primary_button: Button = %PrimaryButton
@onready var _secondary_button: Button = %SecondaryButton

var _install_ready: bool = false
var _busy: bool = false
var _secondary_opens_page: bool = false
var _auto_started_version: String = ""
var _heal_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_primary_button.pressed.connect(_on_primary)
	_secondary_button.pressed.connect(_on_secondary)
	UpdateChecker.download_progress.connect(_on_progress)
	UpdateChecker.download_finished.connect(_on_download_finished)
	UpdateChecker.download_failed.connect(_on_download_failed)
	# Two-button focus loop so Tab never escapes behind the dim.
	_primary_button.focus_next = _primary_button.get_path_to(_secondary_button)
	_primary_button.focus_previous = _primary_button.get_path_to(_secondary_button)
	_secondary_button.focus_next = _secondary_button.get_path_to(_primary_button)
	_secondary_button.focus_previous = _secondary_button.get_path_to(_primary_button)


func _process(delta: float) -> void:
	# Self-healing: if the download finished while this panel was hidden,
	# freed by a scene change, or its finished signal was otherwise missed,
	# the RESTART & UPDATE button used to stay greyed out forever. Whenever
	# the zip for the advertised version is actually on disk, promote the
	# dialog to the ready-to-install state no matter what happened before.
	if _install_ready or _busy:
		return
	_heal_timer += delta
	if _heal_timer < 0.5:
		return
	_heal_timer = 0.0
	if UpdateChecker.latest_version == "":
		return
	if not UpdateChecker.has_downloaded_update(UpdateChecker.latest_version):
		return
	_show_install_state()
	if visible:
		_primary_button.grab_focus()


func _desktop_updates() -> bool:
	var platform: String = OS.get_name()
	return platform == "Windows" or platform == "macOS" or platform == "Linux"


func open() -> void:
	_busy = false
	_secondary_opens_page = false
	_version_label.text = "v%s  ->  v%s" % [UpdateChecker.local_version(), UpdateChecker.latest_version]
	_progress_bar.value = 0.0
	_progress_bar.visible = false
	_progress_label.visible = false
	if UpdateChecker.is_downloading():
		_busy = true
		_notes_label.text = "The update is still downloading in the background."
		_primary_button.text = "DOWNLOADING..."
		_primary_button.disabled = true
		_secondary_button.text = "HIDE"
		_progress_bar.visible = true
		_progress_label.visible = true
		var ratio: float = UpdateChecker.get_download_ratio()
		_progress_bar.value = ratio * 100.0
		_progress_label.text = "%d%%" % int(round(ratio * 100.0))
		show()
		_secondary_button.grab_focus()
		return
	_install_ready = _desktop_updates() and UpdateChecker.has_downloaded_update(UpdateChecker.latest_version)
	if _install_ready:
		_show_install_state()
	elif _desktop_updates() and UpdateChecker.latest_asset_url != "":
		_notes_label.text = "Downloading automatically. Press RESTART when it is ready; no unzipping."
		_primary_button.text = "UPDATE NOW"
		_primary_button.disabled = false
		_secondary_button.text = "LATER"
	else:
		if _desktop_updates():
			_notes_label.text = "No build for this platform was found in the release. Open the release page to download it manually."
		else:
			_notes_label.text = "Browsers update themselves - open the release page to get the new build."
		_primary_button.text = "OPEN DOWNLOAD PAGE"
		_primary_button.disabled = false
		_secondary_button.text = "LATER"
	show()
	_primary_button.grab_focus()
	# Start the download as soon as the update surfaces. The player can hide
	# this panel or keep playing while it runs; the actual swap waits for the
	# explicit RESTART & UPDATE press.
	if (_desktop_updates() and not _install_ready
			and UpdateChecker.latest_asset_url != ""
			and _auto_started_version != UpdateChecker.latest_version):
		_auto_started_version = UpdateChecker.latest_version
		_on_primary()


func _show_install_state() -> void:
	_install_ready = true
	_busy = false
	_secondary_opens_page = true
	_notes_label.text = "Update downloaded. Press RESTART & UPDATE; the game will close, install it and reopen itself."
	_primary_button.text = "RESTART & UPDATE"
	_primary_button.disabled = false
	_secondary_button.text = "RELEASE NOTES"
	_progress_bar.visible = true
	_progress_bar.value = 100.0
	_progress_label.visible = true
	_progress_label.text = "100% - ready to install"


func _on_primary() -> void:
	if _install_ready:
		_notes_label.text = "Installing and restarting..."
		if not UpdateChecker.install_downloaded_update():
			_notes_label.text = "Could not install automatically - opening the release page."
			UpdateChecker.open_release_page()
		return
	if not _desktop_updates() or UpdateChecker.latest_asset_url == "":
		UpdateChecker.open_release_page()
		close()
		return
	_busy = true
	_primary_button.disabled = true
	_primary_button.text = "DOWNLOADING..."
	_secondary_button.text = "HIDE"
	_progress_bar.visible = true
	_progress_label.visible = true
	_progress_bar.value = 0.0
	_progress_label.text = "0% - starting..."
	UpdateChecker.download_update()


func _on_secondary() -> void:
	if _busy:
		close()
		return
	if _secondary_opens_page:
		UpdateChecker.open_release_page()
		close()
		return
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_progress(ratio: float, received: int, total: int) -> void:
	if not visible:
		return
	_progress_bar.value = ratio * 100.0
	_progress_label.text = "%d%% - %.1f / %.1f MB" % [
		int(round(ratio * 100.0)),
		float(received) / 1048576.0,
		float(total) / 1048576.0,
	]


func _on_download_finished(_path: String) -> void:
	_busy = false
	# Ask before closing the game. The installer waits for this process to
	# exit, swaps the files and relaunches the new build.
	_show_install_state()
	if not visible:
		show()
		_primary_button.grab_focus()


func _on_download_failed(reason: String) -> void:
	_busy = false
	_secondary_opens_page = true
	_primary_button.disabled = false
	_primary_button.text = "TRY AGAIN"
	_secondary_button.text = "OPEN RELEASE PAGE"
	if reason == "stalled_connection":
		_notes_label.text = "The download stalled. Press TRY AGAIN to retry, or use the release page."
	else:
		_notes_label.text = "Download failed (%s). You can retry or use the release page." % reason


func close() -> void:
	hide()
	closed.emit()
