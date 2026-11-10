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
const STAGING_DIR: String = "user://updates/staging"
const INSTALL_SCRIPT_PATH: String = "user://updates/update_install.sh"
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
## SHA-256 and byte size of the advertised asset, when the source provides
## them. GitHub does (assets[].digest / .size); the Pi manifest can too.
var latest_asset_sha256: String = ""
var latest_asset_size: int = 0
var last_error: String = ""
## True once the shell has auto-opened the update dialog this run. Returning
## to the main menu should not pop the same dialog repeatedly.
var auto_prompted: bool = false

var _check_request: HTTPRequest
var _server_request: HTTPRequest
var _server_candidate: Dictionary = {}
var _download_request: HTTPRequest
var _checking: bool = false
var _downloading: bool = false
var _downloaded_file: String = ""
var _downloaded_version: String = ""
var _downloaded_sha256: String = ""
var _downloaded_size: int = 0
var _download_target: String = "" ## Absolute user:// path chosen at download start.
var _download_final: String = "" ## Final .zip path; _download_target is a .part file.
var _expected_sha256: String = "" ## Captured at download start, checked at the end.
var _expected_size: int = 0
var _progress_accum: float = 0.0
var _stall_timer: float = 0.0
var _last_progress_bytes: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	_load_download_state()
	_cleanup_after_install()


func _cleanup_after_install() -> void:
	## install_downloaded_update() quits immediately after launching the
	## installer, so a leftover zip + download.cfg from a build that is already
	## running must not make the menu offer to install that same version again.
	## Only specific, verified files inside user://updates are removed here; the
	## generated installer scripts clear the staging tree after the swap.
	if _downloaded_version == "":
		return
	if version_greater(_downloaded_version, local_version()):
		# A genuinely newer build is still waiting to be installed - keep it.
		return
	_discard_download_state()


func _discard_download_state() -> void:
	if _path_inside_updates(_downloaded_file) and FileAccess.file_exists(_downloaded_file):
		DirAccess.remove_absolute(_downloaded_file)
	if _path_inside_updates(_download_target) and FileAccess.file_exists(_download_target):
		DirAccess.remove_absolute(_download_target)
	if FileAccess.file_exists(INSTALL_SCRIPT_PATH):
		DirAccess.remove_absolute(INSTALL_SCRIPT_PATH)
	if FileAccess.file_exists(DOWNLOAD_STATE_PATH):
		DirAccess.remove_absolute(DOWNLOAD_STATE_PATH)
	_downloaded_file = ""
	_downloaded_version = ""
	_downloaded_sha256 = ""
	_downloaded_size = 0


func _path_inside_updates(path: String) -> bool:
	## Keep every stored/deleted path inside user://updates. A crafted
	## download.cfg must not be able to delete an arbitrary user file.
	if path == "":
		return false
	var absolute: String = ProjectSettings.globalize_path(path).simplify_path()
	var root: String = ProjectSettings.globalize_path(UPDATE_DIR).simplify_path().trim_suffix("/") + "/"
	if OS.get_name() == "Windows":
		return absolute.to_lower().begins_with(root.to_lower())
	return absolute.begins_with(root)


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


const CHECK_COOLDOWN_MS: int = 6 * 60 * 60 * 1000 ## Six hours per launch.
var _last_check_ms: int = 0


func check_for_updates(force: bool = false) -> void:
	## Fire and forget. The main menu is rebuilt often, so an automatic check
	## is rate-limited; SETTINGS > CHECK FOR UPDATES passes force=true.
	if not enable_update_checks or _checking or _downloading:
		return
	if github_owner == "" or github_repo == "":
		return
	if not force and _last_check_ms != 0 and Time.get_ticks_msec() - _last_check_ms < CHECK_COOLDOWN_MS:
		return
	_last_check_ms = Time.get_ticks_msec()
	_checking = true
	status = "checking"
	last_error = ""
	_server_candidate.clear()

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
			# A LAN Pi discovered by the lobby is a trusted (private) mirror.
			# Prefer it over any configured relay when it is available.
			var discovered: String = str(net.get("relay_base")).strip_edges()
			if discovered != "" and _trusted_mirror_base(discovered):
				raw = discovered
			if raw == "":
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
	if host == "" or port <= 0 or port > 65535:
		return ""
	return ("https://" if secure else "http://") + host + ":" + str(port)


func _trusted_mirror_base(base: String) -> bool:
	## The Pi mirror is plain HTTP by default. A public HTTP manifest is not a
	## trust anchor: an on-path attacker can advertise any version/checksum and
	## have the client install their zip. Only HTTPS, loopback and RFC1918
	## mirrors are allowed to drive an in-game install; the public HTTP Pi is
	## still used by the game relay, but updates fall back to GitHub.
	var text: String = base.strip_edges().to_lower()
	if text.begins_with("https://"):
		return true
	if not text.begins_with("http://"):
		return false
	var host: String = text.trim_prefix("http://").get_slice("/", 0)
	if host.contains(":"):
		host = host.get_slice(":", 0)
	if host == "localhost" or host == "::1":
		return true
	if host == "":
		return false
	var parts: PackedStringArray = host.split(".")
	if parts.size() != 4:
		return false
	for part: String in parts:
		if part == "" or not part.is_valid_int():
			return false
		var value: int = int(part)
		if value < 0 or value > 255:
			return false
	var first: int = int(parts[0])
	var second: int = int(parts[1])
	return first == 10 or first == 127 \
		or (first == 172 and second >= 16 and second <= 31) \
		or (first == 192 and second == 168)


static func _safe_int(value: Variant, fallback: int = 0) -> int:
	## JSON null/object/string must never reach int() and abort a check.
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		var number: float = float(value)
		if is_finite(number) and number >= -2147483648.0 and number <= 2147483647.0:
			return int(number)
	return fallback


func _check_server(base: String) -> void:
	var platform: String = _platform_keyword()
	if platform == "":
		_check_github()
		return
	_server_request = HTTPRequest.new()
	_server_request.timeout = mini(update_check_timeout, 4.0)
	# Poll on the main loop. A threaded HTTPRequest stuck in recv() keeps a
	# worker alive at quit, which can hang RESTART & UPDATE on a stalled host.
	_server_request.use_threads = false
	_server_request.body_size_limit = 64 * 1024
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
			if version != "" and _trusted_mirror_base(base):
				# Keep the mirror as a CANDIDATE only. A stale but still newer
				# mirror must never hide a newer GitHub release.
				_server_candidate = manifest.duplicate()
				_server_candidate["version"] = version
				_server_candidate["base"] = base
	# Always ask GitHub too, then pick whichever version is actually newest.
	_check_github()


func _check_github() -> void:
	_check_request = HTTPRequest.new()
	_check_request.timeout = update_check_timeout
	_check_request.use_threads = false
	_check_request.body_size_limit = 1024 * 1024
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
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 			or not (JSON.parse_string(body.get_string_from_utf8()) is Dictionary):
		# GitHub is unreachable/rate-limited/broken. The Pi mirror can still
		# offer a valid update instead of leaving the player on an old build.
		if _apply_server_candidate():
			return
		if result != HTTPRequest.RESULT_SUCCESS:
			_finish_check("offline", "no_connection")
		else:
			_finish_check("offline" if response_code == 403 else "error",
				"http_%d" % response_code if response_code != 200 else "bad_json")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var release: Dictionary = parsed as Dictionary
	var tag: String = str(release.get("tag_name", "")).strip_edges()
	latest_version = normalize_version(tag)
	latest_release_url = str(release.get("html_url", ""))
	latest_asset_url = ""
	latest_asset_name = ""
	latest_asset_sha256 = ""
	latest_asset_size = 0
	_pick_asset(release.get("assets", []))
	if latest_version == "":
		if _apply_server_candidate():
			return
		_finish_check("error", "missing_tag")
		return
	# Prefer the mirror only when it is genuinely newer than GitHub.
	if not _server_candidate.is_empty():
		var mirror_version: String = str(_server_candidate.get("version", ""))
		var mirror_sha: String = str(_server_candidate.get("sha256", "")).strip_edges().to_lower()
		var mirror_size: int = _safe_int(_server_candidate.get("size", 0))
		var mirror_ok: bool = version_greater(mirror_version, latest_version) \
			and _valid_sha256(mirror_sha) and mirror_size > 0 \
			and _trusted_mirror_base(str(_server_candidate.get("base", "")))
		if mirror_ok:
			var asset_path: String = str(_server_candidate.get("asset_path", ""))
			var base: String = str(_server_candidate.get("base", ""))
			var mirror_url: String = ""
			if _safe_asset_path(asset_path):
				mirror_url = base + asset_path
			elif _safe_asset_name(str(_server_candidate.get("asset_name", ""))) != "":
				mirror_url = base + "/updates/" + _safe_asset_name(str(_server_candidate.get("asset_name", "")))
			# Never advertise a mirror update whose asset URL is invalid: it
			# would hide a perfectly good GitHub download behind a dead button.
			if mirror_url != "":
				latest_version = mirror_version
				latest_release_url = str(_server_candidate.get("release_url", ""))
				latest_asset_name = str(_server_candidate.get("asset_name", ""))
				latest_asset_sha256 = mirror_sha
				latest_asset_size = mirror_size
				latest_asset_url = mirror_url
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
		# GitHub publishes "digest": "sha256:<hex>" for every uploaded asset.
		var digest_value: Variant = asset.get("digest", "")
		var digest_text: String = str(digest_value) if typeof(digest_value) == TYPE_STRING else ""
		var digest: String = digest_text.trim_prefix("sha256:").strip_edges().to_lower()
		var size: int = _safe_int(asset.get("size", 0))
		# Do not select an asset we cannot verify. A missing/null digest used
		# to skip checksum verification entirely; fail closed instead.
		if not _valid_sha256(digest) or size <= 0:
			continue
		latest_asset_name = str(asset.get("name", ""))
		latest_asset_url = str(asset.get("browser_download_url", ""))
		latest_asset_sha256 = digest
		latest_asset_size = size
		return


func _safe_asset_name(name: String) -> String:
	## Never trust a manifest filename as a path. Keep one flat .zip name made
	## of a small allow-list, so "../../Startup/evil.zip" cannot escape.
	var base: String = name.get_file()
	if base != name or not base.to_lower().ends_with(".zip"):
		return ""
	if base.length() > 128:
		return ""
	for character in base:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(character):
			return ""
	return base


func _valid_sha256(text: String) -> bool:
	if text.length() != 64:
		return false
	for character: String in text:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _safe_release_url(url: String) -> bool:
	## OS.shell_open runs whatever the OS associates with the string. Only
	## open GitHub release pages, never file:// or a local executable path.
	return url.begins_with("https://github.com/") 		or url.begins_with("https://objects.githubusercontent.com/")


func _safe_asset_path(path: String) -> bool:
	if not path.begins_with("/updates/"):
		return false
	var name: String = path.trim_prefix("/updates/")
	return _safe_asset_name(name) == name


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



func _apply_server_candidate() -> bool:
	## Fallback path: GitHub failed, but the Pi mirror had a usable manifest.
	if _server_candidate.is_empty():
		return false
	var version: String = str(_server_candidate.get("version", ""))
	if version == "" or not version_greater(version, local_version()):
		return false
	if not _trusted_mirror_base(str(_server_candidate.get("base", ""))):
		return false
	var sha: String = str(_server_candidate.get("sha256", "")).strip_edges().to_lower()
	var size: int = _safe_int(_server_candidate.get("size", 0))
	if not _valid_sha256(sha) or size <= 0:
		# A mirror without integrity data is not a trust anchor.
		return false
	latest_version = version
	latest_release_url = str(_server_candidate.get("release_url", ""))
	latest_asset_name = str(_server_candidate.get("asset_name", ""))
	latest_asset_sha256 = sha
	latest_asset_size = size
	var asset_path: String = str(_server_candidate.get("asset_path", ""))
	var base: String = str(_server_candidate.get("base", ""))
	latest_asset_url = ""
	if _safe_asset_path(asset_path):
		latest_asset_url = base + asset_path
	elif _safe_asset_name(latest_asset_name) != "":
		latest_asset_url = base + "/updates/" + _safe_asset_name(latest_asset_name)
	if latest_asset_url == "":
		return false
	status = "available"
	update_available.emit(latest_version, latest_release_url, latest_asset_url)
	_finish_check("available", "")
	return true


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
	if _safe_release_url(latest_release_url):
		OS.shell_open(latest_release_url)


func open_download_in_browser() -> void:
	if latest_asset_url.begins_with("https://"):
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
	_expected_sha256 = latest_asset_sha256
	_expected_size = latest_asset_size
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	var target_name: String = _safe_asset_name(latest_asset_name)
	if target_name == "":
		_downloading = false
		download_failed.emit("unsafe_asset_name")
		return
	_download_final = "%s/%s" % [UPDATE_DIR, target_name]
	# Download to a unique .part and rename only after verification. A retry
	# can then never interleave with a stalled/aborted transfer, and the
	# installer never sees a half-written file under the final name.
	_download_target = _download_final + ".part"
	_delete_file(_download_target)
	_delete_file(_download_final)

	_download_request = HTTPRequest.new()
	_download_request.timeout = download_timeout
	# Main-loop polling, not a worker thread: a stalled peer must never keep a
	# non-daemon engine thread alive and hang the quit/restart path.
	_download_request.use_threads = false
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
		_delete_file(_download_target)
		download_failed.emit("request_error_%d" % error)


func _abort_download(reason: String) -> void:
	## HTTPRequest.cancel_request() exists in 4.7, but the threaded download
	## may still be inside the engine's worker. Detach our handler, cancel,
	## shorten the timeout and free the node when it reports back. The unique
	## .part target means a retry cannot share the file with this transfer.
	print("UPDATE_ABORT stall fired, cancelling request")
	_downloading = false
	_stall_timer = 0.0
	_last_progress_bytes = -1
	var request: HTTPRequest = _download_request
	_download_request = null
	if is_instance_valid(request):
		if request.request_completed.is_connected(_on_download_completed):
			request.request_completed.disconnect(_on_download_completed)
		# No worker thread is involved now, so freeing immediately is safe.
		request.queue_free()
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
		# Never hand a corrupt or truncated zip to the installer. GitHub sends
		# the SHA-256 digest with the release; the Pi manifest can carry one too.
		var problem: String = _verify_download(target_path)
		if problem != "":
			_delete_file(target_path)
			download_failed.emit(problem)
		else:
			# Publish the verified file atomically. The installer and the
			# self-heal loop only ever see the final .zip name.
			_delete_file(_download_final)
			var rename_error: Error = DirAccess.rename_absolute(target_path, _download_final)
			if rename_error != OK:
				_delete_file(target_path)
				download_failed.emit("rename_failed")
			else:
				_downloaded_file = _download_final
				_downloaded_version = latest_version
				_downloaded_sha256 = _expected_sha256
				_downloaded_size = _expected_size
				_save_download_state()
				_prune_old_downloads(_download_final)
				download_finished.emit(_download_final)
	_stall_timer = 0.0
	_last_progress_bytes = -1
	if is_instance_valid(_download_request):
		_download_request.queue_free()
		_download_request = null


func _verify_download(path: String) -> String:
	## Returns "" when the file is safe to install, or a failure reason.
	if _expected_size > 0:
		var actual_size: int = _file_size(path)
		if actual_size != _expected_size:
			return "size_mismatch"
	if _expected_sha256 != "":
		var actual_sha: String = _sha256_of_file(path)
		if actual_sha == "" or actual_sha != _expected_sha256:
			return "checksum_mismatch"
	return ""


func _file_size(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size: int = file.get_length()
	file.close()
	return size


func _sha256_of_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return ""
	# 1 MB chunks: a single read of a 100 MB+ zip would spike memory for no
	# reason on lower-end machines.
	const CHUNK: int = 1024 * 1024
	while file.get_position() < file.get_length():
		var chunk: PackedByteArray = file.get_buffer(CHUNK)
		if chunk.is_empty():
			break
		if context.update(chunk) != OK:
			file.close()
			return ""
	file.close()
	return context.finish().hex_encode()


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
	_downloaded_sha256 = str(config.get_value("download", "sha256", "")).strip_edges().to_lower()
	_downloaded_size = _safe_int(config.get_value("download", "size", 0))
	if not _path_inside_updates(_downloaded_file) \
			or not FileAccess.file_exists(_downloaded_file):
		_downloaded_file = ""
		_downloaded_version = ""
		_downloaded_sha256 = ""
		_downloaded_size = 0


func _save_download_state() -> void:
	var config := ConfigFile.new()
	config.set_value("download", "path", _downloaded_file)
	config.set_value("download", "version", _downloaded_version)
	config.set_value("download", "sha256", _downloaded_sha256)
	config.set_value("download", "size", _downloaded_size)
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
	if not _path_inside_updates(source):
		last_error = "unsafe_download_path"
		return false
	# Re-verify immediately before extraction. A same-user process (or disk
	# corruption) could replace the zip after the download-time check.
	if not _valid_sha256(_downloaded_sha256) or _downloaded_size <= 0:
		last_error = "unverified_download"
		return false
	if _file_size(source) != _downloaded_size:
		last_error = "size_mismatch"
		return false
	var actual_sha: String = _sha256_of_file(source)
	if actual_sha == "" or actual_sha != _downloaded_sha256:
		last_error = "checksum_mismatch"
		return false

	var staging: String = STAGING_DIR
	_clear_directory(staging)
	DirAccess.make_dir_recursive_absolute(staging)
	if not _extract_zip(source, staging):
		last_error = "extract_failed"
		# A zip bomb / truncated zip can leave a half-extracted tree behind.
		_clear_directory(staging)
		return false

	var exe_path: String = OS.get_executable_path().replace("\\", "/")
	var pid: int = OS.get_process_id()
	# Every platform must reach this quit. The old macOS branch returned early,
	# so the installer script sat in `while kill -0 $PID` forever and the
	# "RESTART & UPDATE" button never actually restarted anything.
	var launched: bool
	if platform == "macOS":
		launched = _install_macos(exe_path, staging, pid, source)
	else:
		launched = _install_desktop(exe_path, staging, pid, platform, source)
	if not launched:
		# The installer never ran, so nothing will clear the staged files.
		_clear_directory(staging)
		return false
	get_tree().quit()
	return true


func _install_desktop(exe_path: String, staging: String, pid: int,
		platform: String, zip_path: String = "") -> bool:
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
		var stage_root: String = ProjectSettings.globalize_path(staging)
		var zip_global: String = ProjectSettings.globalize_path(zip_path) if zip_path != "" else ""
		if not _write_installer(bat_path, game_dir,
				ProjectSettings.globalize_path(exe_dir), exe_name, stage_root, zip_global):
			last_error = "cannot_write_bat"
			return false
		var spawn: int = OS.create_process("cmd.exe", ["/c", bat_path.replace("/", "\\"), str(pid)], false)
		if spawn <= 0:
			# cmd.exe was blocked (AV/policy). Do not leave a stale installer
			# next to the executable forever.
			if FileAccess.file_exists(bat_path):
				DirAccess.remove_absolute(bat_path)
			last_error = "cannot_launch_installer"
			return false
		return true
	return _write_unix_installer(exe_dir, game_dir, exe_name, pid, staging, zip_path)


func _install_macos(exe_path: String, staging: String, pid: int,
		zip_path: String = "") -> bool:
	## An .app is a folder, so swap the whole bundle. Unsigned / ad-hoc signed
	## builds need three extra things the old script missed: a writable
	## location check, restored executable bits (ZIPReader drops Unix modes),
	## and a rollback if the new bundle will not launch.
	var app_path: String = exe_path.get_base_dir().get_base_dir().get_base_dir()
	if not app_path.ends_with(".app"):
		last_error = "not_inside_app_bundle"
		return false
	var staged_app: String = _find_app_bundle(staging)
	if staged_app == "":
		last_error = "app_not_in_zip"
		return false
	# A standard macOS account cannot write to /Applications. Detect that now
	# and let the dialog offer the manual download instead of lying.
	var probe: String = app_path.get_base_dir() + "/.cartslop_write_probe"
	var probe_file: FileAccess = FileAccess.open(probe, FileAccess.WRITE)
	if probe_file == null:
		last_error = "read_only_app_location"
		return false
	probe_file.close()
	DirAccess.remove_absolute(probe)

	var script_path: String = ProjectSettings.globalize_path(INSTALL_SCRIPT_PATH)
	if not _write_script(script_path, _macos_install_script_lines(
			app_path, staged_app, exe_path.get_file(), pid, staging, zip_path)):
		return false
	var spawn: int = OS.create_process("/bin/bash", [script_path], false)
	if spawn <= 0:
		last_error = "cannot_launch_installer"
		return false
	return true


func _macos_install_script_lines(app_path: String, staged_app: String,
		exe_name: String, pid: int, staging_root: String = "",
		zip_path: String = "") -> PackedStringArray:
	## Kept as a pure function so the generated shell script can be unit tested
	## on Windows, where /bin/bash does not exist.
	var lines: PackedStringArray = PackedStringArray([
		"#!/bin/bash",
		"trap '' HUP",
		"APP=" + _sh_quote(ProjectSettings.globalize_path(app_path)),
		"STAGED=" + _sh_quote(ProjectSettings.globalize_path(staged_app)),
		"BACKUP=" + _sh_quote(ProjectSettings.globalize_path(UPDATE_DIR + "/previous.app")),
		"EXE=" + _sh_quote(exe_name),
		"LOG=" + _sh_quote(ProjectSettings.globalize_path(UPDATE_DIR + "/update_install.log")),
		"PID=%d" % pid,
		"log() { echo \"$1\" >> \"$LOG\"; }",
		": > \"$LOG\"",
		"log 'waiting for the game to quit'",
		"while kill -0 \"$PID\" 2>/dev/null; do sleep 1; done",
		"sleep 1",
		"rm -rf \"$BACKUP\"",
		"if ! mv \"$APP\" \"$BACKUP\"; then log 'backup failed'; exit 1; fi",
		"if ! cp -R \"$STAGED\" \"$APP\"; then log 'copy failed'; rm -rf \"$APP\"; mv \"$BACKUP\" \"$APP\"; open -n \"$APP\"; exit 1; fi",
		# ZIPReader recreates every file as 0644. Restore the executable bit on
		# the launcher ONLY. A blanket `chmod -R` here rewrites the sealed
		# resource modes, invalidates the code signature and forces an ad-hoc
		# re-sign on every single update.
		"chmod +x \"$APP/Contents/MacOS/\"* 2>/dev/null",
		# Locally created bundles are not quarantined, but clear it anyway so
		# replacing a signed/notarized previous build never trips Gatekeeper.
		"xattr -dr com.apple.quarantine \"$APP\" 2>/dev/null",
		"xattr -cr \"$APP\" 2>/dev/null",
		# Godot exports are already ad-hoc signed. Verify first, and re-sign
		# only if the copy actually broke the signature. No --strict: ad-hoc
		# bundles legitimately fail strict resource-envelope checks.
		"if command -v codesign >/dev/null 2>&1; then",
		"  if ! codesign --verify --deep \"$APP\" >/dev/null 2>&1; then",
		"    log 'signature invalid, re-signing ad-hoc'",
		"    codesign --force --deep --sign - \"$APP\" >/dev/null 2>&1 || true",
		"  else",
		"    log 'signature intact, no re-sign needed'",
		"  fi",
		"fi",
		"if [ -x \"$APP/Contents/MacOS/$EXE\" ] && open -n \"$APP\"; then",
		"  log 'update installed'",
		"  rm -rf \"$BACKUP\"",
		"else",
		"  log 'launch failed, restoring previous build'",
		"  rm -rf \"$APP\"",
		"  mv \"$BACKUP\" \"$APP\"",
		"  open -n \"$APP\"",
		"fi",
	])
	# The installer is the last actor: once it has swapped (or rolled back) the
	# bundle, the staged tree and the consumed zip are no longer needed.
	if staging_root != "":
		lines.append("rm -rf " + _sh_quote(ProjectSettings.globalize_path(staging_root)))
	if zip_path != "":
		lines.append("rm -f " + _sh_quote(ProjectSettings.globalize_path(zip_path)))
	lines.append("rm -f \"$0\"")
	return lines


static func _sh_quote(text: String) -> String:
	## Bundle paths contain spaces ("Cart Slop GP.app"). Quote and escape them.
	var safe: String = text.replace("\\", "\\\\")
	safe = safe.replace("\"", "\\\"")
	safe = safe.replace("$", "\\$")
	safe = safe.replace("`", "\\`")
	return "\"" + safe + "\""


func _write_unix_installer(stage_dir: String, game_dir: String, exe_name: String,
		pid: int, staging_root: String = "", zip_path: String = "") -> bool:
	var stage_path: String = ProjectSettings.globalize_path(stage_dir)
	var game_path: String = ProjectSettings.globalize_path(game_dir)
	var zip_global: String = ProjectSettings.globalize_path(zip_path) if zip_path != "" else ""
	for value: String in [stage_path, game_path, exe_name, zip_global]:
		# These become shell words. Reject control characters rather than
		# trying to quote a newline into a generated script.
		if value.contains("\n") or value.contains("\r") or value.contains("\u0000"):
			last_error = "unsafe_install_path"
			return false
	var script_path: String = ProjectSettings.globalize_path(INSTALL_SCRIPT_PATH)
	var lines: PackedStringArray = [
		"#!/bin/bash",
		"trap '' HUP",
		"stage=" + _sh_quote(stage_path),
		"game=" + _sh_quote(game_path),
		"exe=" + _sh_quote(exe_name),
		"backup=\"${game}.update_backup\"",
		"PID=%d" % pid,
		"while kill -0 \"$PID\" 2>/dev/null; do sleep 1; done",
		"sleep 1",
		# Keep a sibling copy so a failed copy can be rolled back. The backup
		# lives next to the game folder, never inside it.
		"rm -rf \"$backup\"",
		"if ! cp -a \"$game\" \"$backup\"; then rm -rf \"$backup\"; exit 1; fi",
		"if cp -a \"$stage\"/. \"$game\"/; then",
		"  chmod +x \"$game/$exe\"",
		"  rm -rf \"$backup\"",
		"else",
		"  rm -rf \"$game\"",
		"  mv \"$backup\" \"$game\"",
		"fi",
		"cd \"$game\"",
		"nohup \"$game/$exe\" >/dev/null 2>&1 &",
		"disown",
	]
	if staging_root != "":
		lines.append("rm -rf " + _sh_quote(ProjectSettings.globalize_path(staging_root)))
	if zip_global != "":
		lines.append("rm -f " + _sh_quote(zip_global))
	lines.append("rm -f \"$0\"")
	if not _write_script(script_path, lines):
		return false
	var spawn: int = OS.create_process("/bin/bash", [script_path, ""], false)
	if spawn <= 0:
		last_error = "cannot_launch_installer"
		return false
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


func _find_app_bundle(root: String, depth: int = 0) -> String:
	if depth > 8:
		return ""
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			if entry.ends_with(".app"):
				dir.list_dir_end()
				return root + "/" + entry
			var nested: String = _find_app_bundle(root + "/" + entry, depth + 1)
			if nested != "":
				dir.list_dir_end()
				return nested
		entry = dir.get_next()
	dir.list_dir_end()
	return ""


const MAX_ZIP_ENTRIES: int = 4096
const MAX_UNCOMPRESSED: int = 600 * 1024 * 1024


func _zip_declared_uncompressed(zip_path: String) -> int:
	## Parse the ZIP central directory before ZIPReader materialises entries.
	## ZIPReader.read_file() returns the whole decompressed file, so checking
	## sizes afterwards cannot prevent a single-entry zip bomb from OOMing.
	var file: FileAccess = FileAccess.open(zip_path, FileAccess.READ)
	if file == null:
		return -1
	var size: int = file.get_length()
	if size < 22 or size > MAX_UNCOMPRESSED:
		file.close()
		return -1
	var tail_len: int = mini(size, 65557)
	file.seek(size - tail_len)
	var tail: PackedByteArray = file.get_buffer(tail_len)
	var eocd: int = -1
	for index in range(tail.size() - 22, -1, -1):
		if tail[index] == 0x50 and tail[index + 1] == 0x4B \
				and tail[index + 2] == 0x05 and tail[index + 3] == 0x06:
			eocd = index
			break
	if eocd < 0:
		file.close()
		return -1
	var cd_size: int = tail.decode_u32(eocd + 12)
	var cd_offset: int = tail.decode_u32(eocd + 16)
	if cd_size == 0xFFFFFFFF or cd_offset == 0xFFFFFFFF \
			or cd_offset + cd_size > size:
		# ZIP64 is not used by these builds; refuse rather than guess.
		file.close()
		return -1
	file.seek(cd_offset)
	var total: int = 0
	var entries: int = 0
	var end: int = cd_offset + cd_size
	while file.get_position() < end:
		if file.get_32() != 0x02014B50:
			file.close()
			return -1
		file.get_16()  # version made by
		file.get_16()  # version needed
		file.get_16()  # flags
		file.get_16()  # compression method
		file.get_16()  # mod time
		file.get_16()  # mod date
		file.get_32()  # crc32
		var compressed: int = file.get_32()
		var uncompressed: int = file.get_32()
		var name_len: int = file.get_16()
		var extra_len: int = file.get_16()
		var comment_len: int = file.get_16()
		file.get_16()  # disk number start
		file.get_16()  # internal attributes
		file.get_32()  # external attributes
		file.get_32()  # local header offset
		if compressed == 0xFFFFFFFF or uncompressed == 0xFFFFFFFF:
			file.close()
			return -1
		entries += 1
		total += uncompressed
		if entries > MAX_ZIP_ENTRIES or total > MAX_UNCOMPRESSED:
			file.close()
			return -1
		file.seek(file.get_position() + name_len + extra_len + comment_len)
	file.close()
	return total


func _extract_zip(zip_path: String, destination: String) -> bool:
	var declared: int = _zip_declared_uncompressed(zip_path)
	if declared < 0 or declared > MAX_UNCOMPRESSED:
		return false
	var reader: ZIPReader = ZIPReader.new()
	if reader.open(zip_path) != OK:
		return false
	var files: PackedStringArray = reader.get_files()
	if files.size() > MAX_ZIP_ENTRIES:
		reader.close()
		return false
	var total_written: int = 0
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
		total_written += data.size()
		if total_written > MAX_UNCOMPRESSED:
			reader.close()
			return false
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


func _write_installer(bat_path: String, game_dir: String, stage_dir: String,
		exe_name: String, staging_root: String = "", zip_path: String = "") -> bool:
	# cmd.exe expands %VAR% and treats quotes as string delimiters. Reject
	# values that could break out of `set "VAR=..."` instead of trying to
	# invent a universal batch escaping scheme.
	for value: String in [game_dir, stage_dir, exe_name, staging_root, zip_path]:
		if value.contains("\"") or value.contains("%") \
				or value.contains("\n") or value.contains("\r"):
			return false
	var file: FileAccess = FileAccess.open(bat_path, FileAccess.WRITE)
	if file == null:
		return false
	var lines: PackedStringArray = [
		"@echo off",
		"setlocal",
		"title Cart Slop GP update",
		"set \"GAME_DIR=%s\"" % game_dir.replace("/", "\\"),
		"set \"STAGE=%s\"" % stage_dir.replace("/", "\\"),
		"set \"STAGE_ROOT=%s\"" % staging_root.replace("/", "\\"),
		"set \"ZIP=%s\"" % zip_path.replace("/", "\\"),
		"set \"EXE_NAME=%s\"" % exe_name,
		"set \"GAME_PID=%~1\"",
		"set \"BACKUP=%TEMP%\\CartSlopGP_update_backup\"",
		"echo Waiting for Cart Slop GP to close...",
		":wait",
		"if \"%GAME_PID%\"==\"\" goto install",
		"tasklist /FI \"PID eq %GAME_PID%\" 2>nul | find \"%GAME_PID%\" >nul",
		"if not errorlevel 1 (",
		"  timeout /t 1 /nobreak >nul",
		"  goto wait",
		")",
		":install",
		"echo Backing up the current build...",
		"if exist \"%BACKUP%\" rmdir /S /Q \"%BACKUP%\"",
		"mkdir \"%BACKUP%\"",
		"xcopy \"%GAME_DIR%\\*\" \"%BACKUP%\\\" /E /I /Y /Q >nul",
		"if errorlevel 1 goto backup_failed",
		"echo Installing update...",
		"xcopy \"%STAGE%\\*\" \"%GAME_DIR%\\\" /E /I /Y /Q >nul",
		"if errorlevel 1 goto failed",
		"start \"\" /D \"%GAME_DIR%\" \"%GAME_DIR%\\%EXE_NAME%\"",
		"timeout /t 6 /nobreak >nul",
		"tasklist /FI \"IMAGENAME eq %EXE_NAME%\" 2>nul | find /I \"%EXE_NAME%\" >nul",
		"if errorlevel 1 goto failed",
		"rmdir /S /Q \"%BACKUP%\"",
		"if not \"%STAGE_ROOT%\"==\"\" rmdir /S /Q \"%STAGE_ROOT%\"",
		"if not \"%ZIP%\"==\"\" del /F /Q \"%ZIP%\" >nul 2>&1",
		"(goto) 2>nul & del \"%~f0\"",
		"exit /b 0",
		":failed",
		"echo Update failed. Restoring your previous build...",
		"cd /d \"%TEMP%\"",
		"if exist \"%GAME_DIR%\" rmdir /S /Q \"%GAME_DIR%\"",
		"xcopy \"%BACKUP%\\*\" \"%GAME_DIR%\\\" /E /I /Y /Q >nul",
		"start \"\" /D \"%GAME_DIR%\" \"%GAME_DIR%\\%EXE_NAME%\"",
		"timeout /t 2 /nobreak >nul",
		"rmdir /S /Q \"%BACKUP%\"",
		"echo The previous build was restored.",
		"timeout /t 4 /nobreak >nul",
		"if not \"%STAGE_ROOT%\"==\"\" rmdir /S /Q \"%STAGE_ROOT%\"",
		"if not \"%ZIP%\"==\"\" del /F /Q \"%ZIP%\" >nul 2>&1",
		"(goto) 2>nul & del \"%~f0\"",
		"exit /b 1",
		":backup_failed",
		"echo Could not back up the current build, so nothing was changed.",
		"echo Launch the game normally and update again, or download the zip manually.",
		"timeout /t 5 /nobreak >nul",
		"if not \"%STAGE_ROOT%\"==\"\" rmdir /S /Q \"%STAGE_ROOT%\"",
		"if not \"%ZIP%\"==\"\" del /F /Q \"%ZIP%\" >nul 2>&1",
		"(goto) 2>nul & del \"%~f0\"",
		"exit /b 1",
	]
	file.store_string("\r\n".join(lines) + "\r\n")
	file.close()
	return true


func normalize_version(tag: String) -> String:
	## "v0.2.1" / "release-0.2.1" -> "0.2.1". A date tag such as
	## "release-2026-11-07" is not a version and must not outrank a real one.
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
	result = result.trim_suffix(".")
	# Require at least major.minor; a bare "2026" from a date tag is rejected.
	if result.count(".") < 1:
		return ""
	return result


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
