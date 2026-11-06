extends Node
## Update check against the Cart Slop Pi mirror, then GitHub Releases.
##
## The check runs automatically. If there is no internet (or GitHub rate-limits
## us) the game simply carries on. Three tiers are supported:
##   1. open the release page in the browser,
##   2. download the release zip into user://updates/,
##   3. hand the swap to a generated update_install.bat and quit.
## Tier 3 exists because a running Windows .exe cannot overwrite itself.

signal update_available(version: String, release_url: String, download_url: String)
signal check_finished(available: bool)
signal download_progress(ratio: float, received: int, total: int)
signal download_finished(path: String)
signal download_failed(reason: String)

const UPDATE_DIR: String = "user://updates"
const DOWNLOAD_STATE_PATH: String = "user://updates/download.cfg"
const API_HOST: String = "https://api.github.com"
## A healthy download moves bytes constantly; if nothing arrives for this
## long the connection is treated as dead instead of hanging the dialog on
## DOWNLOADING... forever.
const DOWNLOAD_STALL_SECONDS: float = 20.0

@export_group("Update Checks")
@export var enable_update_checks: bool = true ## Master switch for the silent menu check.
@export var update_check_timeout: float = 5.0 ## Seconds before the version check is abandoned.
@export var github_owner: String = "HOT18594" ## GitHub account that owns the repo.
@export var github_repo: String = "CartSlopGP" ## Repository name.
@export var user_agent: String = "CartSlopGP-UpdateChecker"

@export_group("Downloads")
@export var download_timeout: float = 600.0 ## Seconds allowed for the zip download.

## "idle" | "checking" | "up_to_date" | "available" | "offline" | "error"
var status: String = "idle"
var latest_version: String = ""
var latest_release_url: String = ""
var latest_asset_url: String = ""
var latest_asset_name: String = ""
var last_error: String = ""
## True once the shell has auto-opened the update dialog this run. Returning
## to the main menu should not pop the same dialog repeatedly.
var auto_prompted: bool = false

var _check_request: HTTPRequest
var _server_request: HTTPRequest
var _download_request: HTTPRequest
var _checking: bool = false
var _downloading: bool = false
var _downloaded_file: String = ""
var _downloaded_version: String = ""
var _download_target: String = "" ## Absolute user:// path chosen at download start.
var _progress_accum: float = 0.0
var _stall_timer: float = 0.0
var _last_progress_bytes: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	_load_download_state()


func _process(delta: float) -> void:
	if not _downloading or _download_request == null:
		return
	var received: int = _download_request.get_downloaded_bytes()
	if received != _last_progress_bytes:
		_last_progress_bytes = received
		_stall_timer = 0.0
	else:
		_stall_timer += delta
	if _stall_timer >= DOWNLOAD_STALL_SECONDS:
		# The connection stopped delivering bytes. Tear the request down so
		# the dialog offers TRY AGAIN instead of sitting greyed out on
		# DOWNLOADING... forever.
		_abort_download("stalled_connection")
		return
	_progress_accum += delta
	if _progress_accum < 0.1:
		return
	_progress_accum = 0.0
	var total: int = _download_request.get_body_size()
	if total <= 0:
		# No Content-Length from the CDN: don't fake 100% while bytes still
		# arrive; the final download_finished signal is authoritative.
		return
	var ratio: float = clampf(float(received) / float(total), 0.0, 1.0)
	download_progress.emit(ratio, received, total)


func is_downloading() -> bool:
	return _downloading


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

	# A configured Pi/server is the migration path. If it has no update
	# manifest (404) or cannot be reached, fall through to GitHub.
	var server_base: String = _configured_server_base()
	if server_base != "":
		_check_server(server_base)
	else:
		_check_github()


func _configured_server_base() -> String:
	# Environment override is useful for a managed/Pi install and for tests.
	var raw: String = OS.get_environment("CARTSLOP_UPDATE_SERVER").strip_edges()
	if raw == "":
		# Prefer the Cart Slop Pi mirror, then fall back to GitHub. This is the
		# same server the multiplayer lobby uses; no address is shown in the UI.
		var net: Node = get_node_or_null("/root/Network") if is_inside_tree() else null
		if net != null and net.get_script() != null:
			var constants: Dictionary = net.get_script().get_script_constant_map()
			raw = str(constants.get("DEFAULT_RELAY_SERVER", "")).strip_edges()
	if raw == "":
		return ""
	var secure: bool = raw.to_lower().begins_with("https://")
	var rest: String = raw.trim_prefix("https://").trim_prefix("http://").trim_suffix("/")
	var host: String = rest.get_slice("/", 0)
	if host == "":
		return ""
	var port: int = 42777
	if host.contains(":"):
		var parts: PackedStringArray = host.split(":")
		host = parts[0]
		port = int(parts[1]) if parts.size() > 1 else 42777
	if host == "" or port <= 0:
		return ""
	return ("https://" if secure else "http://") + host + ":" + str(port)


func _check_server(base: String) -> void:
	var platform: String = _platform_keyword()
	if platform == "":
		_check_github()
		return
	_server_request = HTTPRequest.new()
	_server_request.timeout = mini(update_check_timeout, 4.0)
	_server_request.use_threads = true
	add_child(_server_request)
	_server_request.request_completed.connect(
		_on_server_check_completed.bind(base), CONNECT_ONE_SHOT)
	var url: String = base + "/api/update?platform=" + platform
	var error: Error = _server_request.request(url, ["User-Agent: " + user_agent],
		HTTPClient.METHOD_GET)
	if error != OK:
		_free_server_request()
		_check_github()


func _on_server_check_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray, base: String) -> void:
	_free_server_request()
	if not _checking:
		return
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if parsed is Dictionary:
			var manifest: Dictionary = parsed as Dictionary
			var version: String = normalize_version(str(manifest.get("version", "")))
			if version != "":
				if version_greater(version, local_version()):
					latest_version = version
					latest_release_url = str(manifest.get("release_url", ""))
					latest_asset_name = str(manifest.get("asset_name", ""))
					var asset_path: String = str(manifest.get("asset_path", ""))
					if asset_path.begins_with("/"):
						latest_asset_url = base + asset_path
					elif latest_asset_name != "":
						latest_asset_url = base + "/updates/" + latest_asset_name
					status = "available"
					update_available.emit(latest_version, latest_release_url, latest_asset_url)
					_finish_check("available", "")
					return
	# Server said current/older, or has no usable manifest. GitHub stays the
	# source of truth so a stale Pi mirror cannot hide a newer release.
	_check_github()


func _check_github() -> void:
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
	## Pick the zip that matches the running platform. Never offer another OS's
	## build - installing it would break the app.
	if not (assets is Array):
		return
	var keyword: String = _platform_keyword()
	if keyword == "":
		return
	for entry: Variant in assets as Array:
		if not (entry is Dictionary):
			continue
		var asset: Dictionary = entry as Dictionary
		var name: String = str(asset.get("name", "")).to_lower()
		if not name.ends_with(".zip"):
			continue
		if not name.contains(keyword):
			continue
		# "macos" must not also match an unrelated "mac" file; keyword is exact.
		latest_asset_name = str(asset.get("name", ""))
		latest_asset_url = str(asset.get("browser_download_url", ""))
		return


func _platform_keyword() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "macos"
		"Linux":
			return "linux"
		_:
			return ""


func _finish_check(new_status: String, error_text: String) -> void:
	_checking = false
	status = new_status
	last_error = error_text
	if is_instance_valid(_check_request):
		_check_request.queue_free()
		_check_request = null
	_free_server_request()
	check_finished.emit(new_status == "available")


func _free_server_request() -> void:
	if is_instance_valid(_server_request):
		_server_request.queue_free()
		_server_request = null


func open_release_page() -> void:
	if latest_release_url != "":
		OS.shell_open(latest_release_url)


func open_download_in_browser() -> void:
	if latest_asset_url != "":
		OS.shell_open(latest_asset_url)


func download_update() -> void:
	## Tier 2: pull the release zip into user://updates/.
	if _downloading:
		return
	if latest_asset_url == "":
		download_failed.emit("no_asset")
		return
	_downloading = true
	_downloaded_file = ""
	_progress_accum = 0.0
	_stall_timer = 0.0
	_last_progress_bytes = -1
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	var target_name: String = latest_asset_name if latest_asset_name != "" else "CartSlopGP_update.zip"
	_download_target = "%s/%s" % [UPDATE_DIR, target_name]

	_download_request = HTTPRequest.new()
	_download_request.timeout = download_timeout
	_download_request.use_threads = true
	_download_request.download_file = _download_target
	add_child(_download_request)
	_download_request.request_completed.connect(_on_download_completed, CONNECT_ONE_SHOT)

	var headers: PackedStringArray = ["User-Agent: " + user_agent]
	var error: Error = _download_request.request(latest_asset_url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		_downloading = false
		if is_instance_valid(_download_request):
			_download_request.queue_free()
			_download_request = null
		download_failed.emit("request_error_%d" % error)


func _abort_download(reason: String) -> void:
	## HTTPRequest has no cancel() in Godot 4.7, and freeing a request while
	## its threaded download is still running can block the main loop on the
	## thread join. Instead: detach our handler, shorten the request's own
	## timeout so the engine ends the transfer, and free the node when it
	## reports back (safe once the transfer is finished).
	print("UPDATE_ABORT stall fired, detaching request")
	_downloading = false
	_stall_timer = 0.0
	_last_progress_bytes = -1
	var request: HTTPRequest = _download_request
	_download_request = null
	if is_instance_valid(request):
		if request.request_completed.is_connected(_on_download_completed):
			request.request_completed.disconnect(_on_download_completed)
		request.timeout = 5.0
		request.request_completed.connect(func(_r: int, _c: int,
				_h: PackedStringArray, _b: PackedByteArray) -> void:
			request.queue_free(), CONNECT_ONE_SHOT)
	_delete_file(_download_target)
	download_failed.emit(reason)


func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_downloading = false
	var target_path: String = _download_target
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_delete_file(target_path)
		download_failed.emit("download_failed")
	elif not FileAccess.file_exists(target_path):
		download_failed.emit("missing_file")
	else:
		_downloaded_file = target_path
		_downloaded_version = latest_version
		_save_download_state()
		_prune_old_downloads(target_path)
		download_finished.emit(target_path)
	_stall_timer = 0.0
	_last_progress_bytes = -1
	if is_instance_valid(_download_request):
		_download_request.queue_free()
		_download_request = null


func _delete_file(path: String) -> void:
	## Partial zips are useless; never leave one behind for the next check.
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _prune_old_downloads(keep_path: String) -> void:
	var dir: DirAccess = DirAccess.open(UPDATE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.to_lower().ends_with(".zip"):
			var full: String = UPDATE_DIR + "/" + entry
			if full != keep_path:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()


func get_download_ratio() -> float:
	if _download_request == null:
		return 0.0
	var total: float = float(_download_request.get_body_size())
	if total <= 0.0:
		return 0.0
	return clampf(float(_download_request.get_downloaded_bytes()) / total, 0.0, 1.0)


func downloaded_zip_path() -> String:
	return _downloaded_file


func downloaded_version() -> String:
	return _downloaded_version


func has_downloaded_update(version: String) -> bool:
	## True when the zip for this exact version is already on disk.
	if _downloaded_file == "" or _downloaded_version != version:
		return false
	return FileAccess.file_exists(_downloaded_file)


func _load_download_state() -> void:
	var config := ConfigFile.new()
	if config.load(DOWNLOAD_STATE_PATH) != OK:
		return
	_downloaded_file = str(config.get_value("download", "path", ""))
	_downloaded_version = str(config.get_value("download", "version", ""))
	if _downloaded_file == "" or not FileAccess.file_exists(_downloaded_file):
		_downloaded_file = ""
		_downloaded_version = ""


func _save_download_state() -> void:
	var config := ConfigFile.new()
	config.set_value("download", "path", _downloaded_file)
	config.set_value("download", "version", _downloaded_version)
	config.save(DOWNLOAD_STATE_PATH)


func install_downloaded_update(zip_path: String = "") -> bool:
	## Tier 3: stage the zip, write a small launcher script and quit. The script
	## waits for this process to exit, swaps the files, relaunches and deletes
	## itself. Windows uses .bat, macOS/Linux use bash.
	if not OS.has_feature("template"):
		last_error = "install_only_in_exported_build"
		return false
	var platform: String = OS.get_name()
	if platform != "Windows" and platform != "macOS" and platform != "Linux":
		last_error = "install_unsupported_platform"
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

	var exe_path: String = OS.get_executable_path().replace("\\", "/")
	var pid: int = OS.get_process_id()
	if platform == "macOS":
		return _install_macos(exe_path, staging, pid)

	var exe_name: String = exe_path.get_file()
	var exe_dir: String = staging
	if not FileAccess.file_exists(staging + "/" + exe_name):
		exe_dir = _find_directory_containing(staging, exe_name)
		if exe_dir == "":
			last_error = "exe_not_in_zip"
			return false
	var game_dir: String = exe_path.get_base_dir()
	if platform == "Windows":
		var bat_path: String = game_dir + "/update_install.bat"
		if not _write_installer(bat_path, game_dir, ProjectSettings.globalize_path(exe_dir), exe_name):
			last_error = "cannot_write_bat"
			return false
		OS.create_process("cmd.exe", ["/c", bat_path.replace("/", "\\"), str(pid)], false)
	else:
		if not _write_unix_installer(exe_dir, game_dir, exe_name, pid):
			return false
	get_tree().quit()
	return true


func _install_macos(exe_path: String, staging: String, pid: int) -> bool:
	## An .app is a folder: swap the whole bundle from the staged zip.
	var app_path: String = exe_path.get_base_dir().get_base_dir().get_base_dir()
	if not app_path.ends_with(".app"):
		last_error = "not_inside_app_bundle"
		return false
	var staged_app: String = _find_app_bundle(staging)
	if staged_app == "":
		last_error = "app_not_in_zip"
		return false
	var script_path: String = ProjectSettings.globalize_path(UPDATE_DIR + "/update_install.sh")
	var lines: PackedStringArray = [
		"#!/bin/bash",
		"trap '' HUP",
		"APP=\"%s\"" % ProjectSettings.globalize_path(app_path),
		"STAGED=\"%s\"" % ProjectSettings.globalize_path(staged_app),
		"PID=%d" % pid,
		"while kill -0 \"$PID\" 2>/dev/null; do sleep 1; done",
		"sleep 1",
		"rm -rf \"$APP\"",
		"cp -R \"$STAGED\" \"$APP\"",
		"xattr -dr com.apple.quarantine \"$APP\" 2>/dev/null",
		"codesign --force --deep --sign - \"$APP\" 2>/dev/null",
		"open \"$APP\"",
		"rm -f \"$0\"",
	]
	if not _write_script(script_path, lines):
		return false
	OS.create_process("/bin/bash", [script_path, ""], false)
	return true


func _write_unix_installer(stage_dir: String, game_dir: String, exe_name: String, pid: int) -> bool:
	var script_path: String = ProjectSettings.globalize_path(UPDATE_DIR + "/update_install.sh")
	var lines: PackedStringArray = [
		"#!/bin/bash",
		"trap '' HUP",
		"stage=\"%s\"" % ProjectSettings.globalize_path(stage_dir),
		"game=\"%s\"" % ProjectSettings.globalize_path(game_dir),
		"exe=\"%s\"" % exe_name,
		"PID=%d" % pid,
		"while kill -0 \"$PID\" 2>/dev/null; do sleep 1; done",
		"sleep 1",
		"cp -a \"$stage\"/. \"$game\"/",
		"chmod +x \"$game/$exe\"",
		"cd \"$game\"",
		"nohup \"$game/$exe\" >/dev/null 2>&1 &",
		"disown",
		"rm -f \"$0\"",
	]
	if not _write_script(script_path, lines):
		return false
	OS.create_process("/bin/bash", [script_path, ""], false)
	return true


func _write_script(path: String, lines: PackedStringArray) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_error = "cannot_write_script"
		return false
	file.store_string("\n".join(lines) + "\n")
	file.close()
	OS.execute("chmod", ["+x", path])
	return true


func _find_app_bundle(root: String) -> String:
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and entry.ends_with(".app"):
			dir.list_dir_end()
			return root + "/" + entry
		entry = dir.get_next()
	dir.list_dir_end()
	return ""


func _extract_zip(zip_path: String, destination: String) -> bool:
	var reader: ZIPReader = ZIPReader.new()
	if reader.open(zip_path) != OK:
		return false
	var files: PackedStringArray = reader.get_files()
	var root: String = destination.simplify_path() + "/"
	for file_name: String in files:
		if file_name.ends_with("/"):
			continue
		var safe_name: String = file_name.replace("\\", "/")
		if safe_name.begins_with("/") or safe_name.contains("..") or safe_name.contains(":"):
			reader.close()
			return false
		var target: String = (destination + "/" + safe_name).simplify_path()
		if not target.begins_with(root):
			reader.close()
			return false
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
		"start \"\" /D \"%GAME_DIR%\" \"%GAME_DIR%\\%EXE_NAME%\"",
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
