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
var _heal_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("nav_scope")
	hide()
	var panel := get_node_or_null("Center/Panel") as PanelContainer
	if panel != null:
		panel.add_theme_stylebox_override("panel",
			UiKit.slanted_panel(Color(0.056, 0.068, 0.156, 0.95),
				Color(0.24, 0.84, 0.96, 0.56), 0.06, 4, 6, 36.0, 28.0))
	_primary_button.pressed.connect(_on_primary)
	_secondary_button.pressed.connect(_on_secondary)
	UpdateChecker.download_progress.connect(_on_progress)
	UpdateChecker.download_finished.connect(_on_download_finished)
	UpdateChecker.download_failed.connect(_on_download_failed)
	_primary_button.focus_next = _primary_button.get_path_to(_secondary_button)
	_primary_button.focus_previous = _primary_button.get_path_to(_secondary_button)
	_secondary_button.focus_next = _secondary_button.get_path_to(_primary_button)
	_secondary_button.focus_previous = _secondary_button.get_path_to(_primary_button)


func _fit_buttons() -> void:
	if _primary_button != null and _primary_button.has_method("fit_text"):
		_primary_button.call("fit_text")
	if _secondary_button != null and _secondary_button.has_method("fit_text"):
		_secondary_button.call("fit_text")


func _process(delta: float) -> void:
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


func _desktop_updates() -> bool:
	var platform: String = OS.get_name()
	return platform == "Windows" or platform == "macOS" or platform == "Linux"


func open() -> void:
	_busy = false
	_secondary_opens_page = false
	_version_label.text = "v%s  →  v%s" % [UpdateChecker.local_version(), UpdateChecker.latest_version]
	_progress_bar.value = 0.0
	_progress_bar.visible = false
	_progress_label.visible = false
	if UpdateChecker.is_downloading():
		_busy = true
		_notes_label.text = "Downloading update..."
		_primary_button.text = "DOWNLOADING..."
		_primary_button.disabled = true
		_secondary_button.text = "HIDE"
		_fit_buttons()
		_progress_bar.visible = true
		_progress_label.visible = true
		var ratio: float = UpdateChecker.get_download_ratio()
		_progress_bar.value = ratio * 100.0
		_progress_label.text = "%d%%" % int(round(ratio * 100.0))
		show()
		UiAnim.pop($Center/Panel)
		MenuNav.refresh()
		MenuNav.focus(_secondary_button)
		return
	_install_ready = _desktop_updates() and UpdateChecker.has_downloaded_update(UpdateChecker.latest_version)
	if _install_ready:
		_show_install_state()
	elif _desktop_updates() and UpdateChecker.latest_asset_url != "":
		var size_text: String = ""
		if UpdateChecker.latest_asset_size > 0:
			size_text = " (%.0f MB)" % (float(UpdateChecker.latest_asset_size) / 1048576.0)
		_notes_label.text = "Ready to download%s and install automatically." % size_text
		_primary_button.text = "DOWNLOAD UPDATE"
		_primary_button.disabled = false
		_secondary_button.text = "LATER"
	else:
		_notes_label.text = "Open the release page to get the latest build."
		_primary_button.text = "RELEASE PAGE"
		_primary_button.disabled = false
		_secondary_button.text = "LATER"
	_fit_buttons()
	show()
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()
	MenuNav.focus(_primary_button)


func request_close() -> void:
	close()


func _show_install_state() -> void:
	_install_ready = true
	_busy = false
	_secondary_opens_page = true
	_notes_label.text = "Ready to install — restarts automatically."
	_primary_button.text = "RESTART & UPDATE"
	_primary_button.disabled = false
	_secondary_button.text = "RELEASE NOTES"
	_fit_buttons()
	_progress_bar.visible = true
	_progress_bar.value = 100.0
	_progress_label.visible = true
	_progress_label.text = "100% — ready to install"


func _on_primary() -> void:
	if _install_ready:
		_notes_label.text = "Installing and restarting..."
		if not UpdateChecker.install_downloaded_update():
			if UpdateChecker.last_error == "read_only_app_location":
				_notes_label.text = "Cannot replace the app in this folder. Move Cart Slop GP somewhere writable, or install from the release page."
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
	_fit_buttons()
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
		UiKit.consume_input(self)
		close()


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
	_show_install_state()
	if not visible:
		show()
		UiAnim.pop($Center/Panel)
		MenuNav.refresh()
		MenuNav.focus(_primary_button)


func _on_download_failed(reason: String) -> void:
	_busy = false
	_secondary_opens_page = true
	_primary_button.disabled = false
	_primary_button.text = "TRY AGAIN"
	_secondary_button.text = "OPEN RELEASE PAGE"
	_fit_buttons()
	if reason == "stalled_connection":
		_notes_label.text = "The download stalled. Press TRY AGAIN to retry, or use the release page."
	else:
		_notes_label.text = "Download failed (%s). You can retry or use the release page." % reason
	if not visible:
		show()
		UiAnim.pop($Center/Panel)
		MenuNav.refresh()
		MenuNav.focus(_primary_button)


func close() -> void:
	hide()
	$Center/Panel.scale = Vector2.ONE
	$Center/Panel.modulate = Color.WHITE
	MenuNav.refresh()
	closed.emit()
