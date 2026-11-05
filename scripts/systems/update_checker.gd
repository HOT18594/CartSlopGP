extends Node
## Free, optional update check against GitHub Releases.
##
## The check is silent and short: if there is no internet (or GitHub rate-limits
## us) the game simply carries on. Three tiers are supported:
##   1. open the release page in the browser,
##   2. download the release zip into user://updates/,
##   3. hand the swap to a generated update_install.bat and quit.
## Tier 3 exists because a running Windows .exe cannot overwrite itself.

signal update_available(version: String, release_url: String, download_url: String)
signal check_finished(available: bool)
signal download_progress(ratio: float)
signal download_finished(path: String)
signal download_failed(reason: String)

const UPDATE_DIR: String = "user://updates"
const API_HOST: String = "https://api.github.com"

@export_group("Update Checks")
@export var enable_update_checks: bool = true ## Master switch for the silent menu check.
@export var update_check_timeout: float = 5.0 ## Seconds before the version check is abandoned.
@export var github_owner: String = "HOT18594" ## GitHub account that owns the repo.
@export var github_repo: String = "CartSlopGP" ## Repository name.
@export var user_agent: String = "CartSlopGP-UpdateChecker"

@export_group("Downloads")
@export var download_timeout: float = 120.0 ## Seconds allowed for the zip download.
@export var require_windows_asset: bool = true ## Only offer assets whose name mentions windows.

## "idle" | "checking" | "up_to_date" | "available" | "offline" | "error"
var status: String = "idle"
var latest_version: String = ""
var latest_release_url: String = ""
var latest_asset_url: String = ""
var latest_asset_name: String = ""
var last_error: String = ""

var _check_request: HTTPRequest
var _download_request: HTTPRequest
var _checking: bool = false
var _downloading: bool = false
var _downloaded_file: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)


func has_update() -> bool:
	return status == "available" and latest_version != ""


func local_version() -> String:
	return read_version_file()


func read_version_file() -> String:
	## version.txt ships inside the .pck, so it always matches the running build.
	if not FileAccess.file_exists("res://version.txt"):
		return "0.0.0"
	var file: FileAccess = FileAccess.open("res://version.txt", FileAccess.READ)
	if file == null:
		return "0.0.0"
	var text: String = file.get_as_text().strip_edges()
	return text if text != "" else "0.0.0"


func check_for_updates() -> void:
	## Fire and forget: safe to call every time the main menu loads.
	if not enable_update_checks or _checking or _downloading:
		return
	if github_owner == "" or github_repo == "":
		return
	_checking = true
	status = "checking"
	last_error = ""

	_check_request = HTTPRequest.new()
	_check_request.timeout = update_check_timeout
	_check_request.use_threads = true
	add_child(_check_request)
	_check_request.request_completed.connect(_on_check_completed, CONNECT_ONE_SHOT)

	var url: String = "%s/repos/%s/%s/releases/latest" % [API_HOST, github_owner, github_repo]
	var headers: PackedStringArray = [
		"User-Agent: " + user_agent,
		"Accept: application/vnd.github+json",
	]
	var error: Error = _check_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		_finish_check("error", "request_error_%d" % error)


func _on_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish_check("offline", "no_connection")
		return
	if response_code != 200:
		# 404 = no releases yet, 403 = rate limited. Neither is worth showing.
		_finish_check("offline" if response_code == 403 else "error", "http_%d" % response_code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		_finish_check("error", "bad_json")
		return
	var release: Dictionary = parsed as Dictionary
	var tag: String = str(release.get("tag_name", "")).strip_edges()
	latest_version = normalize_version(tag)
	latest_release_url = str(release.get("html_url", ""))
	latest_asset_url = ""
	latest_asset_name = ""
	_pick_asset(release.get("assets", []))
	if latest_version == "":
		_finish_check("error", "missing_tag")
		return
	if version_greater(latest_version, local_version()):
		status = "available"
		update_available.emit(latest_version, latest_release_url, latest_asset_url)
	else:
		status = "up_to_date"
	_finish_check(status, "")


func _pick_asset(assets: Variant) -> void:
	## Prefer the Windows zip; GitHub lists assets in upload order otherwise.
	if not (assets is Array):
		return
	var fallback: Dictionary = {}
	for entry: Variant in assets as Array:
		if not (entry is Dictionary):
			continue
		var asset: Dictionary = entry as Dictionary
		var name: String = str(asset.get("name", ""))
		if not name.to_lower().ends_with(".zip"):
			continue
		if fallback.is_empty():
			fallback = asset
		if name.to_lower().contains("windows"):
			latest_asset_name = name
			latest_asset_url = str(asset.get("browser_download_url", ""))
			return
	if not require_windows_asset and not fallback.is_empty():
		latest_asset_name = str(fallback.get("name", ""))
		latest_asset_url = str(fallback.get("browser_download_url", ""))


func _finish_check(new_status: String, error_text: String) -> void:
	_checking = false
	status = new_status
	last_error = error_text
	if is_instance_valid(_check_request):
		_check_request.queue_free()
		_check_request = null
	check_finished.emit(new_status == "available")


func open_release_page() -> void:
	if latest_release_url != "":
		OS.shell_open(latest_release_url)


func open_download_in_browser() -> void:
	if latest_asset_url != "":
		OS.shell_open(latest_asset_url)


func download_update() -> void:
	## Tier 2: pull the release zip into user://updates/.
	if _downloading or latest_asset_url == "":
		return
	_downloading = true
	_downloaded_file = ""
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	var target_name: String = latest_asset_name if latest_asset_name != "" else "CartSlopGP_update.zip"
	var target_path: String = "%s/%s" % [UPDATE_DIR, target_name]

	_download_request = HTTPRequest.new()
	_download_request.timeout = download_timeout
	_download_request.use_threads = true
	_download_request.download_file = target_path
	add_child(_download_request)
	_download_request.request_completed.connect(_on_download_completed, CONNECT_ONE_SHOT)

	var headers: PackedStringArray = ["User-Agent: " + user_agent]
	var error: Error = _download_request.request(latest_asset_url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		_downloading = false
		download_failed.emit("request_error_%d" % error)


func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_downloading = false
	var target_name: String = latest_asset_name if latest_asset_name != "" else "CartSlopGP_update.zip"
	var target_path: String = "%s/%s" % [UPDATE_DIR, target_name]
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		download_failed.emit("download_failed")
	elif not FileAccess.file_exists(target_path):
		download_failed.emit("missing_file")
	else:
		_downloaded_file = target_path
		download_finished.emit(target_path)
	if is_instance_valid(_download_request):
		_download_request.queue_free()
		_download_request = null


func get_download_ratio() -> float:
	if _download_request == null:
		return 0.0
	var total: float = float(_download_request.get_body_size())
	if total <= 0.0:
		return 0.0
	return clampf(float(_download_request.get_downloaded_bytes()) / total, 0.0, 1.0)


func downloaded_zip_path() -> String:
	return _downloaded_file


func install_downloaded_update(zip_path: String = "") -> bool:
	## Tier 3: unpack next to the game, write update_install.bat, launch it and quit.
	## Returns false when there is nothing safe to swap (e.g. running from the editor).
	if not OS.has_feature("template"):
		last_error = "install_only_in_exported_build"
		return false
	var source: String = zip_path if zip_path != "" else _downloaded_file
	if source == "" or not FileAccess.file_exists(source):
		last_error = "no_downloaded_zip"
		return false

	var staging: String = UPDATE_DIR + "/staging"
	_clear_directory(staging)
	DirAccess.make_dir_recursive_absolute(staging)
	if not _extract_zip(source, staging):
		last_error = "extract_failed"
		return false

	var exe_dir: String = staging
	var exe_path: String = OS.get_executable_path().replace("\\", "/")
	var exe_name: String = exe_path.get_file()
	if not FileAccess.file_exists(staging + "/" + exe_name):
		exe_dir = _find_directory_containing(staging, exe_name)
		if exe_dir == "":
			last_error = "exe_not_in_zip"
			return false

	var game_dir: String = exe_path.get_base_dir()
	var bat_path: String = game_dir + "/update_install.bat"
	if not _write_installer(bat_path, game_dir, exe_dir, exe_name):
		last_error = "cannot_write_bat"
		return false

	var pid: int = OS.get_process_id()
	OS.create_process("cmd.exe", ["/c", bat_path.replace("/", "\\"), str(pid)], false)
	get_tree().quit()
	return true


func _extract_zip(zip_path: String, destination: String) -> bool:
	var reader: ZIPReader = ZIPReader.new()
	if reader.open(zip_path) != OK:
		return false
	var files: PackedStringArray = reader.get_files()
	for file_name: String in files:
		if file_name.ends_with("/"):
			continue
		var target: String = destination + "/" + file_name
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var data: PackedByteArray = reader.read_file(file_name)
		var out: FileAccess = FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			reader.close()
			return false
		out.store_buffer(data)
		out.close()
	reader.close()
	return true


func _find_directory_containing(root: String, file_name: String) -> String:
	## Release zips usually wrap everything in one top-level folder.
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var candidate: String = root + "/" + entry
			if FileAccess.file_exists(candidate + "/" + file_name):
				dir.list_dir_end()
				return candidate
			var nested: String = _find_directory_containing(candidate, file_name)
			if nested != "":
				dir.list_dir_end()
				return nested
		entry = dir.get_next()
	dir.list_dir_end()
	return ""


func _clear_directory(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full: String = path + "/" + entry
			if dir.current_is_dir():
				_clear_directory(full)
				DirAccess.remove_absolute(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _write_installer(bat_path: String, game_dir: String, stage_dir: String, exe_name: String) -> bool:
	var file: FileAccess = FileAccess.open(bat_path, FileAccess.WRITE)
	if file == null:
		return false
	var lines: PackedStringArray = [
		"@echo off",
		"setlocal",
		"title Cart Slop GP update",
		"set \"GAME_DIR=%s\"" % game_dir.replace("/", "\\"),
		"set \"STAGE=%s\"" % stage_dir.replace("/", "\\"),
		"set \"EXE_NAME=%s\"" % exe_name,
		"set \"GAME_PID=%~1\"",
		"echo Waiting for Cart Slop GP to close...",
		":wait",
		"if \"%GAME_PID%\"==\"\" goto install",
		"tasklist /FI \"PID eq %GAME_PID%\" 2>nul | find \"%GAME_PID%\" >nul",
		"if not errorlevel 1 (",
		"  timeout /t 1 /nobreak >nul",
		"  goto wait",
		")",
		":install",
		"echo Installing update...",
		"xcopy \"%STAGE%\\*\" \"%GAME_DIR%\\\" /E /I /Y /Q >nul",
		"if errorlevel 1 goto failed",
		"start \"\" \"%GAME_DIR%\\%EXE_NAME%\"",
		"timeout /t 2 /nobreak >nul",
		"(goto) 2>nul & del \"%~f0\"",
		"exit /b 0",
		":failed",
		"echo Update failed. Your previous build is untouched.",
		"echo Launch the game normally and try again, or download the zip manually.",
		"pause",
		"(goto) 2>nul & del \"%~f0\"",
	]
	file.store_string("\r\n".join(lines) + "\r\n")
	file.close()
	return true


func normalize_version(tag: String) -> String:
	## "v0.2.1" / "release-0.2.1" -> "0.2.1".
	var text: String = tag.strip_edges().to_lower().trim_prefix("v")
	var start: int = -1
	for index in text.length():
		var character: String = text[index]
		if character >= "0" and character <= "9":
			start = index
			break
	if start < 0:
		return ""
	var result: String = ""
	for index in range(start, text.length()):
		var character: String = text[index]
		if (character >= "0" and character <= "9") or character == ".":
			result += character
		else:
			break
	return result.trim_suffix(".")


func version_greater(candidate: String, current: String) -> bool:
	## Numeric semver comparison; missing segments count as 0.
	var left: PackedStringArray = normalize_version(candidate).split(".", false)
	var right: PackedStringArray = normalize_version(current).split(".", false)
	var count: int = maxi(left.size(), right.size())
	for index in count:
		var a: int = int(left[index]) if index < left.size() else 0
		var b: int = int(right[index]) if index < right.size() else 0
		if a != b:
			return a > b
	return false
