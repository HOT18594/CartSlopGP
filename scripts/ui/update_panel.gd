extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
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
	add_to_group("nav_scope")
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
		pass


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
		UiAnim.pop($Center/Panel)
		MenuNav.refresh()
		pass
		return
	_install_ready = _desktop_updates() and UpdateChecker.has_downloaded_update(UpdateChecker.latest_version)
	if _install_ready:
		_show_install_state()
	elif _desktop_updates() and UpdateChecker.latest_asset_url != "":
		var size_text: String = ""
		if UpdateChecker.latest_asset_size > 0:
			size_text = " (%.0f MB)" % (float(UpdateChecker.latest_asset_size) / 1048576.0)
		_notes_label.text = "Download the update%s, then press RESTART. No unzipping needed." % size_text
		_primary_button.text = "DOWNLOAD UPDATE"
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
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()
	pass
	# No automatic download: a 100 MB transfer is the player's choice. The
	# panel shows the size and waits for DOWNLOAD UPDATE.


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
			if UpdateChecker.last_error == "read_only_app_location":
				_notes_label.text = "Cannot replace the app in this folder. Move Cart Slop GP somewhere writable (for example your Applications folder with an admin account), or install from the release page."
			else:
				_notes_label.text = "Could not install automatically (%s). Use RELEASE NOTES to download it manually." % UpdateChecker.last_error
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
		pass


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
	if not visible:
		# A failure that happens while the panel is hidden must not be silent.
		show()
		UiAnim.pop($Center/Panel)
		MenuNav.refresh()


func close() -> void:
	hide()
	$Center/Panel.scale = Vector2.ONE
	$Center/Panel.modulate = Color.WHITE
	MenuNav.refresh()
	closed.emit()
