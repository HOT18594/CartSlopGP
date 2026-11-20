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
const WIN_INSTALL_SCRIPT_PATH: String = "user://updates/update_install.bat"
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

## "idle" | "checking" | "up_to_date" | "available" | "offline" | "error".
## A web build is the served page itself, so it settles on "up_to_date": there
## is never a downloadable file and never a state the menus do not know.
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
## Optional mirror server base URL override (used by automated tests or custom
## deployments without mutating process-wide environment variables).
var mirror_override: String = ""

var _check_request: HTTPRequest
var _server_request: HTTPRequest
var _server_candidate: Dictionary = {}
var _active_mirror_base: String = ""
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
## Cached version.txt contents; see local_version().
var _version_cache: String = ""


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
	if FileAccess.file_exists(WIN_INSTALL_SCRIPT_PATH):
		DirAccess.remove_absolute(WIN_INSTALL_SCRIPT_PATH)
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
		total = _expected_size
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
	## version.txt is read once: it ships inside the .pck and cannot change while
	## this process runs, so re-reading it for every menu footer is wasted I/O.
	if _version_cache == "":
		_version_cache = read_version_file()
	return _version_cache


func version_string() -> String:
	## Ready-to-print build version for a menu footer, e.g. "v0.7.1". A missing
	## or malformed version.txt still prints a valid, sortable string.
	var normalized: String = normalize_version(local_version())
	return "v" + normalized if normalized != "" else "v0.0.0"


func read_version_file() -> String:
	## version.txt ships inside the .pck, so it always matches the running build.
	if not FileAccess.file_exists("res://version.txt"):
		return "0.0.0"
	var file: FileAccess = FileAccess.open("res://version.txt", FileAccess.READ)
	if file == null:
		return "0.0.0"
	var text: String = file.get_as_text().strip_edges()
	return text if text != "" else "0.0.0"


const CHECK_COOLDOWN_MS: int = 6 * 60 * 60 * 1000 ## Six hours after a good check.
## A failed or offline automatic check only rests for a minute. It used to arm
## the six-hour cooldown too, so a single offline boot hid every later update
## for the rest of the launch even after the network came back.
const RETRY_COOLDOWN_MS: int = 60 * 1000
## Tick time of the last COMPLETED good check (0 = none this launch).
var _last_check_ms: int = 0
## Tick time of the last attempt, successful or not.
var _last_attempt_ms: int = 0
## Whether the last attempt produced a real answer. Only then is the long
## cooldown correct; a failed attempt gets the short retry cooldown instead.
var _last_attempt_ok: bool = false


func check_for_updates(force: bool = false) -> void:
	## Fire and forget. The main menu is rebuilt often, so an automatic check
	## is rate-limited; SETTINGS > CHECK FOR UPDATES passes force=true.
	if OS.has_feature("web"):
		## The browser build is the install: reloading the served page is the
		## update, so never offer a download the page cannot apply. Report the
		## documented "up_to_date" state and the usual finished signal, so the
		## settings screen stops waiting on "Checking..." forever.
		_last_attempt_ms = Time.get_ticks_msec()
		_last_check_ms = _last_attempt_ms
		_last_attempt_ok = true
		status = "up_to_date"
		check_finished.emit(false)
		return
	if not enable_update_checks or _checking or _downloading:
		return
	if github_owner == "" or github_repo == "":
		return
	var now: int = Time.get_ticks_msec()
	if not force:
		if _last_attempt_ok:
			if _last_check_ms != 0 and now - _last_check_ms < CHECK_COOLDOWN_MS:
				return
		elif _last_attempt_ms != 0 and now - _last_attempt_ms < RETRY_COOLDOWN_MS:
			return
	_last_attempt_ms = now
	_checking = true
	status = "checking"
	last_error = ""
	_server_candidate.clear()
	_active_mirror_base = ""

	# A configured Pi/server is the migration path. If it has no update
	# manifest (404) or cannot be reached, fall through to GitHub.
	var server_base: String = _configured_server_base()
	if server_base != "":
		_check_server(server_base)
	else:
		_check_github()


static func _parse_http_url(raw_url: String, default_http_port: int = 80) -> Dictionary:
	## Strict HTTP/HTTPS URL parser with host/port/userinfo validation.
	## Rejects control characters, whitespace, backslashes and userinfo (@) so
	## tricks like https://github.com@evil.example/asset.zip never pass.
	var text: String = raw_url.strip_edges()
	if text == "" or text.length() > 2048:
		return {"ok": false}
	for index in text.length():
		var code: int = text.unicode_at(index)
		if code <= 0x20 or code == 0x7F:
			return {"ok": false}
	var lower: String = text.to_lower()
	var scheme: String = ""
	var rest: String = ""
	if lower.begins_with("https://"):
		scheme = "https"
		rest = text.substr(8)
	elif lower.begins_with("http://"):
		scheme = "http"
		rest = text.substr(7)
	else:
		return {"ok": false}
	var before_query: String = rest
	var q_idx: int = before_query.find("?")
	if q_idx >= 0:
		before_query = before_query.substr(0, q_idx)
	var h_idx: int = before_query.find("#")
	if h_idx >= 0:
		before_query = before_query.substr(0, h_idx)
	var slash_idx: int = before_query.find("/")
	var authority: String = before_query if slash_idx < 0 else before_query.substr(0, slash_idx)
	var path: String = "/" if slash_idx < 0 else before_query.substr(slash_idx)
	if authority == "" or authority.contains("@") or authority.contains("\\") or path.contains("\\"):
		return {"ok": false}
	var host: String = ""
	var host_out: String = ""
	var port: int = 443 if scheme == "https" else default_http_port
	var explicit_port: bool = false
	if authority.begins_with("["):
		var close_idx: int = authority.find("]")
		if close_idx <= 1:
			return {"ok": false}
		host = authority.substr(1, close_idx - 1).to_lower()
		for ch: String in host:
			if not "0123456789abcdef:.".contains(ch):
				return {"ok": false}
		host_out = "[" + host + "]"
		if close_idx + 1 < authority.length():
			if authority[close_idx + 1] != ":":
				return {"ok": false}
			var port_str: String = authority.substr(close_idx + 2)
			if port_str == "" or not port_str.is_valid_int():
				return {"ok": false}
			port = int(port_str)
			explicit_port = true
	elif authority.contains(":"):
		var parts: PackedStringArray = authority.split(":")
		if parts.size() != 2 or parts[0] == "" or parts[1] == "" or not parts[1].is_valid_int():
			return {"ok": false}
		host = parts[0].to_lower()
		host_out = host
		port = int(parts[1])
		explicit_port = true
	else:
		host = authority.to_lower()
		host_out = host
	if host == "" or port <= 0 or port > 65535:
		return {"ok": false}
	if not authority.begins_with("["):
		if host.begins_with(".") or host.ends_with(".") \
				or host.begins_with("-") or host.ends_with("-") \
				or host.contains(".."):
			return {"ok": false}
		for ch: String in host:
			if not "abcdefghijklmnopqrstuvwxyz0123456789.-".contains(ch):
				return {"ok": false}
	var default_port: int = 443 if scheme == "https" else 80
	var origin: String = scheme + "://" + host_out + ("" if port == default_port else ":" + str(port))
	return {
		"ok": true,
		"scheme": scheme,
		"host": host,
		"host_out": host_out,
		"port": port,
		"explicit_port": explicit_port,
		"path": path,
		"origin": origin,
	}


static func _is_trusted_github_host(host: String) -> bool:
	if host == "github.com" \
			or host == "api.github.com" \
			or host == "codeload.github.com" \
			or host == "objects.githubusercontent.com" \
			or host == "release-assets.githubusercontent.com":
		return true
	if host.ends_with(".githubusercontent.com") and host.length() > 22:
		return true
	return false


static func _trusted_private_http_host(host: String) -> bool:
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


static func _normalize_mirror_base(raw: String) -> String:
	var trimmed: String = raw.strip_edges()
	if trimmed == "":
		return ""
	var lower: String = trimmed.to_lower()
	if not lower.begins_with("http://") and not lower.begins_with("https://"):
		trimmed = "http://" + trimmed
	var parsed: Dictionary = _parse_http_url(trimmed, 42777)
	if not bool(parsed.get("ok", false)):
		return ""
	var scheme: String = str(parsed["scheme"])
	var host_out: String = str(parsed["host_out"])
	var port: int = int(parsed["port"])
	if scheme == "https" and port == 443 and not bool(parsed["explicit_port"]):
		return "https://" + host_out
	return scheme + "://" + host_out + ":" + str(port)


func _configured_server_base() -> String:
	# Explicit property or environment override is useful for a managed/Pi
	# install and for deterministic automated tests.
	var raw: String = mirror_override.strip_edges()
	if raw == "":
		raw = OS.get_environment("CARTSLOP_UPDATE_SERVER").strip_edges()
	if raw == "":
		# Prefer the Cart Slop Pi mirror, then fall back to GitHub. This is the
		# same server the multiplayer lobby uses; no address is shown in the UI.
		var net: Node = get_node_or_null("/root/Network") if is_inside_tree() else null
		if net != null and net.get_script() != null:
			# A LAN Pi discovered by the lobby is a trusted (private) mirror.
			# Only use a trusted mirror base automatically; probing a plain-HTTP
			# WAN relay only wastes a round-trip because _trusted_mirror_base()
			# rejects unencrypted public mirrors anyway.
			var discovered: String = str(net.get("relay_base")).strip_edges()
			if discovered != "" and _trusted_mirror_base(discovered):
				raw = discovered
	var built: String = _normalize_mirror_base(raw)
	if built == "" or not _trusted_mirror_base(built):
		return ""
	return built


func _trusted_mirror_base(base: String) -> bool:
	## The Pi mirror is plain HTTP by default. A public HTTP manifest is not a
	## trust anchor: an on-path attacker can advertise any version/checksum and
	## have the client install their zip. Only HTTPS, loopback and RFC1918
	## mirrors are allowed to drive an in-game install; the public HTTP Pi is
	## still used by the game relay, but updates fall back to GitHub.
	var parsed: Dictionary = _parse_http_url(base, 42777)
	if not bool(parsed.get("ok", false)):
		return false
	var scheme: String = str(parsed["scheme"])
	if scheme == "https":
		return true
	if scheme != "http":
		return false
	return _trusted_private_http_host(str(parsed["host"]))


func is_trusted_download_url(url: String, mirror_base: String = "") -> bool:
	## Allowlist for update asset URLs. Accepts:
	##   1. HTTPS GitHub release/asset hosts (github.com, codeload.github.com,
	##      objects.githubusercontent.com, release-assets.githubusercontent.com,
	##      and *.githubusercontent.com CDN subdomains).
	##   2. The configured Pi mirror (HTTPS, or loopback/RFC1918 HTTP) serving
	##      a flat /updates/<safe_name>.zip path.
	## Rejects untrusted third-party domains and plain HTTP to non-mirror hosts.
	var parsed: Dictionary = _parse_http_url(url)
	if not bool(parsed.get("ok", false)):
		return false
	var scheme: String = str(parsed["scheme"])
	var host: String = str(parsed["host"])
	var port: int = int(parsed["port"])
	var path: String = str(parsed["path"])
	if scheme == "https" and port == 443 and _is_trusted_github_host(host):
		return path.begins_with("/") and path.length() > 1 and not path.contains("..")
	if not _safe_asset_path(path):
		return false
	var allowed_base: String = _normalize_mirror_base(mirror_base) if mirror_base != "" \
		else _configured_server_base()
	if allowed_base == "" or not _trusted_mirror_base(allowed_base):
		return false
	var allowed_parsed: Dictionary = _parse_http_url(allowed_base, 42777)
	if not bool(allowed_parsed.get("ok", false)):
		return false
	return str(parsed["origin"]) == str(allowed_parsed["origin"])


static func _safe_int(value: Variant, fallback: int = 0) -> int:
	## JSON null/object/string must never reach int() and abort a check.
	if typeof(value) == TYPE_INT:
		return int(value)
	if typeof(value) == TYPE_FLOAT:
		var number: float = float(value)
		if is_finite(number) and number >= -2147483648.0 and number <= 2147483647.0:
			return int(number)
	return fallback


func _check_server(base: String, try_static_manifest: bool = false) -> void:
	var platform: String = _platform_keyword()
	if platform == "":
		_check_github()
		return
	_server_request = HTTPRequest.new()
	_server_request.timeout = minf(update_check_timeout, 4.0)
	# Poll on the main loop. A threaded HTTPRequest stuck in recv() keeps a
	# worker alive at quit, which can hang RESTART & UPDATE on a stalled host.
	_server_request.use_threads = false
	_server_request.body_size_limit = 64 * 1024
	add_child(_server_request)
	_server_request.request_completed.connect(
		_on_server_check_completed.bind(base, try_static_manifest), CONNECT_ONE_SHOT)
	var url: String = (base + "/updates/manifest.json") if try_static_manifest \
		else (base + "/api/update?platform=" + platform)
	var error: Error = _server_request.request(url, ["User-Agent: " + user_agent],
		HTTPClient.METHOD_GET)
	if error != OK:
		_free_server_request()
		_check_github()


func _on_server_check_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray, base: String,
		tried_static_manifest: bool = false) -> void:
	_free_server_request()
	if not _checking:
		return
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if parsed is Dictionary:
			var candidate: Dictionary = parse_mirror_manifest(parsed as Dictionary, base)
			if bool(candidate.get("ok", false)):
				# Keep the mirror as a CANDIDATE so a stale mirror can never
				# hide a newer GitHub release.
				_server_candidate = candidate
	elif result == HTTPRequest.RESULT_SUCCESS and response_code == 404 and not tried_static_manifest:
		# Support static mirrors that host /updates/manifest.json directly
		# without cartslop_server.py's /api/update route.
		_check_server(base, true)
		return
	# Always ask GitHub too, then pick whichever version is actually newest.
	_check_github()


func parse_mirror_manifest(manifest: Dictionary, base: String,
		platform_override: String = "") -> Dictionary:
	## Parse either a Pi /updates/manifest.json document (multi-platform maps
	## written by make_manifest.py) OR a /api/update?platform=<p> response.
	var norm_base: String = _normalize_mirror_base(base)
	if norm_base == "" or not _trusted_mirror_base(norm_base):
		return {"ok": false, "error": "untrusted_mirror"}
	var platform: String = platform_override.strip_edges().to_lower() \
		if platform_override != "" else _platform_keyword()
	if platform == "":
		return {"ok": false, "error": "unsupported_platform"}
	var version: String = normalize_version(str(manifest.get("version", "")))
	if version == "":
		return {"ok": false, "error": "invalid_version"}

	var raw_asset_name: String = ""
	var raw_asset_path: String = str(manifest.get("asset_path", "")).strip_edges()
	var assets_field: Variant = manifest.get("assets", null)
	if assets_field is Dictionary:
		raw_asset_name = str((assets_field as Dictionary).get(platform, "")).strip_edges()
	if raw_asset_name == "":
		raw_asset_name = str(manifest.get("asset_name", "")).strip_edges()
	if raw_asset_name == "" and _safe_asset_path(raw_asset_path):
		raw_asset_name = raw_asset_path.trim_prefix("/updates/")
	var safe_name: String = _safe_asset_name(raw_asset_name)
	if safe_name == "":
		return {"ok": false, "error": "missing_platform_asset"}

	var raw_sha: String = ""
	var sha_field: Variant = manifest.get("sha256", "")
	if sha_field is Dictionary:
		var sha_entry: Variant = (sha_field as Dictionary).get(platform, "")
		raw_sha = str(sha_entry) if typeof(sha_entry) == TYPE_STRING else ""
	elif typeof(sha_field) == TYPE_STRING:
		raw_sha = str(sha_field)
	var sha: String = raw_sha.strip_edges().to_lower().trim_prefix("sha256:").strip_edges()

	var size: int = 0
	var sizes_field: Variant = manifest.get("sizes", null)
	if sizes_field is Dictionary:
		size = _safe_int((sizes_field as Dictionary).get(platform, 0))
	if size <= 0:
		size = _safe_int(manifest.get("size", 0))
	if not _valid_sha256(sha) or size <= 0:
		return {"ok": false, "error": "unverified_asset"}

	var asset_url: String = ""
	if _safe_asset_path(raw_asset_path) and raw_asset_path == "/updates/" + safe_name:
		asset_url = norm_base + raw_asset_path
	else:
		asset_url = norm_base + "/updates/" + safe_name
	if not is_trusted_download_url(asset_url, norm_base):
		return {"ok": false, "error": "untrusted_asset"}

	var raw_release_url: String = str(manifest.get("release_url", "")).strip_edges()
	var clean_release_url: String = raw_release_url \
		if _safe_release_url(raw_release_url, norm_base) else ""
	return {
		"ok": true,
		"version": version,
		"release_url": clean_release_url,
		"asset_name": safe_name,
		"asset_path": "/updates/" + safe_name,
		"asset_url": asset_url,
		"sha256": sha,
		"size": size,
		"base": norm_base,
		"source": "pi",
	}


func parse_github_release(release: Dictionary,
		platform_override: String = "") -> Dictionary:
	## Parse a GitHub /repos/<owner>/<repo>/releases/latest JSON document.
	## Selects the matching platform zip when it carries a valid SHA-256 digest
	## and trusted GitHub URL; on older releases without an asset digest, fails
	## closed for automatic zip download while preserving version + release_url.
	if bool(release.get("draft", false)):
		return {"ok": false, "error": "draft_release"}
	var tag: String = str(release.get("tag_name", "")).strip_edges()
	var version: String = normalize_version(tag)
	if version == "":
		return {"ok": false, "error": "missing_tag"}
	var raw_html_url: String = str(release.get("html_url", "")).strip_edges()
	var clean_html_url: String = raw_html_url if _safe_release_url(raw_html_url) else ""
	var out: Dictionary = {
		"ok": true,
		"version": version,
		"release_url": clean_html_url,
		"asset_name": "",
		"asset_url": "",
		"sha256": "",
		"size": 0,
		"unverified_asset": false,
		"source": "github",
	}
	var keyword: String = platform_override.strip_edges().to_lower() \
		if platform_override != "" else _platform_keyword()
	var assets: Variant = release.get("assets", [])
	if keyword == "" or not (assets is Array):
		return out
	var saw_unverified: bool = false
	for entry: Variant in assets as Array:
		if not (entry is Dictionary):
			continue
		var asset: Dictionary = entry as Dictionary
		var safe_name: String = _safe_asset_name(str(asset.get("name", "")).strip_edges())
		if safe_name == "":
			continue
		var lower_name: String = safe_name.to_lower()
		if not lower_name.contains(keyword):
			continue
		var download_url: String = str(asset.get("browser_download_url", "")).strip_edges()
		if not is_trusted_download_url(download_url):
			continue
		var size: int = _safe_int(asset.get("size", 0))
		if size <= 0:
			continue
		# GitHub publishes "digest": "sha256:<hex>" on release assets; older
		# releases return null or "". Fail closed rather than installing an
		# unverified zip, while keeping release_url for manual browser download.
		var digest_value: Variant = asset.get("digest", "")
		var digest_text: String = str(digest_value) if typeof(digest_value) == TYPE_STRING else ""
		var digest: String = digest_text.strip_edges().to_lower().trim_prefix("sha256:").strip_edges()
		if not _valid_sha256(digest):
			saw_unverified = true
			continue
		out["asset_name"] = safe_name
		out["asset_url"] = download_url
		out["asset_sha256"] = digest
		out["sha256"] = digest
		out["size"] = size
		out["unverified_asset"] = false
		return out
	out["unverified_asset"] = saw_unverified
	return out


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
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 \
			or not (JSON.parse_string(body.get_string_from_utf8()) is Dictionary):
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
	var gh: Dictionary = parse_github_release(parsed as Dictionary)
	if not bool(gh.get("ok", false)):
		if _apply_server_candidate():
			return
		_finish_check("error", str(gh.get("error", "missing_tag")))
		return
	var github_version: String = str(gh["version"])
	## Prefer the verified Pi mirror when it is newer than GitHub OR at the
	## exact same version (fast LAN mirror, or tag pushed while GitHub assets
	## are still uploading), while letting a newer GitHub release win over a
	## stale mirror.
	if _server_candidate.has("version") \
			and not version_greater(github_version, str(_server_candidate["version"])):
		if str(_server_candidate.get("release_url", "")) == "" and str(gh.get("release_url", "")) != "":
			_server_candidate["release_url"] = str(gh["release_url"])
		if _apply_server_candidate():
			return
	_active_mirror_base = ""
	latest_version = github_version
	latest_release_url = str(gh.get("release_url", ""))
	latest_asset_name = str(gh.get("asset_name", ""))
	latest_asset_url = str(gh.get("asset_url", ""))
	latest_asset_sha256 = str(gh.get("sha256", ""))
	latest_asset_size = int(gh.get("size", 0))
	if version_greater(latest_version, local_version()):
		status = "available"
		update_available.emit(latest_version, latest_release_url, latest_asset_url)
	else:
		status = "up_to_date"
	_finish_check(status, "")


func _pick_asset(assets: Variant) -> void:
	## Backwards-compatible wrapper around parse_github_release's asset picker.
	var gh: Dictionary = parse_github_release({"tag_name": "0.0.0", "assets": assets})
	latest_asset_name = str(gh.get("asset_name", ""))
	latest_asset_url = str(gh.get("asset_url", ""))
	latest_asset_sha256 = str(gh.get("sha256", ""))
	latest_asset_size = int(gh.get("size", 0))


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


func _safe_release_url(url: String, mirror_base: String = "") -> bool:
	## OS.shell_open runs whatever the OS associates with the string. Only
	## open HTTPS GitHub release pages (or an HTTPS configured mirror page),
	## never file://, http:// or untrusted third-party domains.
	var parsed: Dictionary = _parse_http_url(url)
	if not bool(parsed.get("ok", false)):
		return false
	if str(parsed["scheme"]) != "https":
		return false
	var host: String = str(parsed["host"])
	if int(parsed["port"]) == 443 and _is_trusted_github_host(host):
		return true
	var allowed_base: String = _normalize_mirror_base(mirror_base) if mirror_base != "" \
		else _configured_server_base()
	if allowed_base != "" and allowed_base.begins_with("https://"):
		var allowed_parsed: Dictionary = _parse_http_url(allowed_base, 443)
		if bool(allowed_parsed.get("ok", false)) \
				and str(parsed["origin"]) == str(allowed_parsed["origin"]):
			return true
	return false


func _safe_asset_path(path: String) -> bool:
	if not path.begins_with("/updates/"):
		return false
	var name: String = path.trim_prefix("/updates/")
	return name != "" and _safe_asset_name(name) == name


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
	## Apply a verified Pi mirror candidate when it is newer than local_version().
	if _server_candidate.is_empty():
		return false
	var candidate: Dictionary = _server_candidate
	if not candidate.has("asset_url"):
		candidate = parse_mirror_manifest(_server_candidate, str(_server_candidate.get("base", "")))
	if not bool(candidate.get("ok", false)):
		return false
	var version: String = str(candidate.get("version", ""))
	if version == "" or not version_greater(version, local_version()):
		return false
	var base: String = str(candidate.get("base", ""))
	var asset_url: String = str(candidate.get("asset_url", ""))
	var sha: String = str(candidate.get("sha256", ""))
	var size: int = _safe_int(candidate.get("size", 0))
	if not _valid_sha256(sha) or size <= 0 or not is_trusted_download_url(asset_url, base):
		return false
	_active_mirror_base = base
	latest_version = version
	latest_release_url = str(candidate.get("release_url", ""))
	latest_asset_name = str(candidate.get("asset_name", ""))
	latest_asset_sha256 = sha
	latest_asset_size = size
	latest_asset_url = asset_url
	status = "available"
	update_available.emit(latest_version, latest_release_url, latest_asset_url)
	_finish_check("available", "")
	return true


func _finish_check(new_status: String, error_text: String) -> void:
	_checking = false
	status = new_status
	last_error = error_text
	# Only a real answer earns the long cooldown. Offline/error checks fall back
	# to RETRY_COOLDOWN_MS so a reconnect is noticed on the next menu visit.
	_last_attempt_ok = new_status == "available" or new_status == "up_to_date"
	if _last_attempt_ok:
		_last_check_ms = Time.get_ticks_msec()
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
	if _safe_release_url(latest_release_url, _active_mirror_base):
		OS.shell_open(latest_release_url)


func open_download_in_browser() -> void:
	if latest_asset_url.begins_with("https://") \
			and is_trusted_download_url(latest_asset_url, _active_mirror_base):
		OS.shell_open(latest_asset_url)


func download_update() -> void:
	## Tier 2: pull the release zip into user://updates/.
	if OS.has_feature("web"):
		download_failed.emit("web_build")
		return
	if _downloading:
		return
	if latest_asset_url == "":
		download_failed.emit("no_asset")
		return
	# Fail closed: an unverified zip must never be downloaded and then offered
	# for install, and bytes may only come from trusted GitHub HTTPS hosts or a
	# trusted configured mirror.
	if not _valid_sha256(latest_asset_sha256) or latest_asset_size <= 0:
		download_failed.emit("unverified_asset")
		return
	if not is_trusted_download_url(latest_asset_url, _active_mirror_base):
		download_failed.emit("untrusted_asset")
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
	# Explicitly permit HTTP 302 hops from github.com/.../releases/download/...
	# to objects.githubusercontent.com / release-assets.githubusercontent.com.
	_download_request.max_redirects = 8
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


func verify_zip_integrity(path: String, expected_sha256: String,
		expected_size: int) -> String:
	## Returns "" when `path` matches `expected_size` and `expected_sha256`,
	## or a short machine-readable failure code ("unverified", "missing_file",
	## "size_mismatch", "checksum_mismatch"). Fails closed when checksum or
	## size metadata is missing.
	var clean_sha: String = expected_sha256.strip_edges().to_lower().trim_prefix("sha256:").strip_edges()
	if not _valid_sha256(clean_sha) or expected_size <= 0:
		return "unverified"
	var actual_size: int = _file_size(path)
	if actual_size < 0:
		return "missing_file"
	if actual_size != expected_size:
		return "size_mismatch"
	var actual_sha: String = _sha256_of_file(path)
	if actual_sha == "" or actual_sha != clean_sha:
		return "checksum_mismatch"
	return ""


func _verify_download(path: String) -> String:
	## Returns "" when the file is safe to install, or a failure reason.
	return verify_zip_integrity(path, _expected_sha256, _expected_size)


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
		total = float(_expected_size)
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
	_downloaded_version = normalize_version(str(config.get_value("download", "version", "")))
	_downloaded_sha256 = str(config.get_value("download", "sha256", "")).strip_edges().to_lower()
	_downloaded_size = _safe_int(config.get_value("download", "size", 0))
	# A state file that cannot be verified must be discarded, not published:
	# has_downloaded_update() would otherwise promise a RESTART & UPDATE button
	# that install_downloaded_update() always rejects as "unverified_download".
	if not _path_inside_updates(_downloaded_file) \
			or not FileAccess.file_exists(_downloaded_file) \
			or _downloaded_version == "" \
			or not _valid_sha256(_downloaded_sha256) \
			or _downloaded_size <= 0:
		_discard_download_state()


func _save_download_state() -> void:
	var config := ConfigFile.new()
	config.set_value("download", "path", _downloaded_file)
	config.set_value("download", "version", _downloaded_version)
	config.set_value("download", "sha256", _downloaded_sha256)
	config.set_value("download", "size", _downloaded_size)
	var error: Error = config.save(DOWNLOAD_STATE_PATH)
	if error != OK:
		# The zip is downloaded but not recorded: say so instead of letting the
		# next boot silently forget a verified update.
		push_warning("UpdateChecker: could not write download.cfg (%d)" % error)


func install_downloaded_update(zip_path: String = "") -> bool:
	## Tier 3: stage the zip, write a small launcher script and quit. The script
	## waits for this process to exit, swaps the files, relaunches and deletes
	## itself. Windows uses .bat, macOS/Linux use bash.
	if OS.has_feature("web"):
		last_error = "install_unsupported_platform"
		return false
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
	var problem: String = verify_zip_integrity(source, _downloaded_sha256, _downloaded_size)
	if problem != "":
		last_error = "unverified_download" if problem == "unverified" else problem
		return false

	var exe_path: String = OS.get_executable_path().replace("\\", "/")
	var staging: String = STAGING_DIR
	var staged: Dictionary = stage_update_zip(source, staging, exe_path, platform)
	if not bool(staged.get("ok", false)):
		last_error = str(staged.get("error", "extract_failed"))
		return false

	var pid: int = OS.get_process_id()
	# Every platform must reach this quit. The old macOS branch returned early,
	# so the installer script sat in `while kill -0 $PID` forever and the
	# "RESTART & UPDATE" button never actually restarted anything.
	var launched: bool
	if platform == "macOS":
		launched = _install_macos(exe_path, staging, pid, source,
			str(staged.get("staged_app", "")))
	else:
		launched = _install_desktop(exe_path, staging, pid, platform, source,
			str(staged.get("stage_dir", "")))
	if not launched:
		# The installer never ran, so nothing will clear the staged files.
		_clear_directory(staging)
		return false
	get_tree().quit()
	return true


func stage_update_zip(zip_path: String, staging: String, exe_path: String,
		platform_override: String = "") -> Dictionary:
	## Extract `zip_path` into `staging` and locate the platform payload.
	## Works cleanly for v0.8.0 single-file embedded builds (ONLY CartSlopGP.exe
	## or CartSlopGP.x86_64, no .pck) as well as macOS .app bundles.
	_clear_directory(staging)
	DirAccess.make_dir_recursive_absolute(staging)
	if not _extract_zip(zip_path, staging):
		# A zip bomb / truncated zip can leave a half-extracted tree behind.
		_clear_directory(staging)
		return {"ok": false, "error": "extract_failed"}

	var platform: String = platform_override if platform_override != "" else OS.get_name()
	if platform == "macOS" or platform.to_lower() == "macos":
		var staged_app: String = _find_app_bundle(staging)
		if staged_app == "":
			_clear_directory(staging)
			return {"ok": false, "error": "app_not_in_zip"}
		var macos_bin_dir: String = staged_app + "/Contents/MacOS"
		if not _directory_has_files(macos_bin_dir):
			_clear_directory(staging)
			return {"ok": false, "error": "exe_not_in_zip"}
		return {
			"ok": true,
			"platform": "macOS",
			"staged_app": staged_app,
		}

	var exe_name: String = exe_path.replace("\\", "/").get_file()
	if exe_name == "":
		_clear_directory(staging)
		return {"ok": false, "error": "exe_not_in_zip"}
	var exe_dir: String = ""
	if FileAccess.file_exists(staging + "/" + exe_name):
		exe_dir = staging
	else:
		exe_dir = _find_directory_containing(staging, exe_name)
	if exe_dir == "":
		# Player may have renamed CartSlopGP.exe (e.g. "CartSlopGP (1).exe")
		# or CartSlopGP.x86_64. Match a single unambiguous platform binary in
		# the staged archive and rename it to match the running executable.
		var fallback_bin: String = _find_single_platform_binary(staging, platform)
		if fallback_bin != "":
			exe_dir = fallback_bin.get_base_dir()
			var target_bin: String = exe_dir + "/" + exe_name
			if fallback_bin != target_bin:
				if DirAccess.rename_absolute(fallback_bin, target_bin) != OK:
					_clear_directory(staging)
					return {"ok": false, "error": "exe_not_in_zip"}
	if exe_dir == "":
		_clear_directory(staging)
		return {"ok": false, "error": "exe_not_in_zip"}
	var pck_name: String = exe_name.get_basename() + ".pck"
	return {
		"ok": true,
		"platform": platform,
		"stage_dir": exe_dir,
		"exe_name": exe_name,
		"pck_name": pck_name,
		"has_pck": FileAccess.file_exists(exe_dir + "/" + pck_name),
	}


func _directory_has_files(path: String) -> bool:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and not entry.begins_with("."):
			dir.list_dir_end()
			return true
		entry = dir.get_next()
	dir.list_dir_end()
	return false


func _find_single_platform_binary(root: String, platform: String, depth: int = 0) -> String:
	if depth > 2:
		return ""
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return ""
	var is_win: bool = platform.to_lower().begins_with("win")
	var matches: PackedStringArray = PackedStringArray()
	var subdirs: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			if dir.current_is_dir():
				subdirs.append(root + "/" + entry)
			else:
				var lower: String = entry.to_lower()
				if is_win and lower.ends_with(".exe"):
					matches.append(root + "/" + entry)
				elif not is_win and (lower.ends_with(".x86_64") or lower.ends_with(".arm64") or lower.ends_with(".x86_32")):
					matches.append(root + "/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()
	if matches.size() == 1:
		return matches[0]
	if matches.size() > 1:
		return ""
	for sub: String in subdirs:
		var found: String = _find_single_platform_binary(sub, platform, depth + 1)
		if found != "":
			matches.append(found)
	return matches[0] if matches.size() == 1 else ""


func _is_directory_writable(dir_path: String) -> bool:
	var probe: String = dir_path.trim_suffix("/") + "/.cartslop_write_probe_" + str(OS.get_process_id())
	var probe_file: FileAccess = FileAccess.open(probe, FileAccess.WRITE)
	if probe_file == null:
		return false
	probe_file.close()
	DirAccess.remove_absolute(probe)
	return true


func _install_desktop(exe_path: String, staging: String, pid: int,
		platform: String, zip_path: String = "", pre_staged_dir: String = "") -> bool:
	var exe_name: String = exe_path.get_file()
	var exe_dir: String = pre_staged_dir
	if exe_dir == "":
		exe_dir = staging
		if not FileAccess.file_exists(staging + "/" + exe_name):
			exe_dir = _find_directory_containing(staging, exe_name)
			if exe_dir == "":
				last_error = "exe_not_in_zip"
				return false
	var game_dir: String = exe_path.get_base_dir()
	if not _is_directory_writable(game_dir):
		last_error = "read_only_app_location"
		return false
	if platform == "Windows":
		var bat_path: String = ProjectSettings.globalize_path(WIN_INSTALL_SCRIPT_PATH)
		var stage_root: String = ProjectSettings.globalize_path(staging)
		var zip_global: String = ProjectSettings.globalize_path(zip_path) if zip_path != "" else ""
		if not _write_installer(bat_path, ProjectSettings.globalize_path(game_dir),
				ProjectSettings.globalize_path(exe_dir), exe_name, stage_root, zip_global):
			last_error = "cannot_write_bat"
			return false
		var spawn: int = OS.create_process("cmd.exe", ["/c", bat_path.replace("/", "\\"), str(pid)], false)
		if spawn <= 0:
			if FileAccess.file_exists(bat_path):
				DirAccess.remove_absolute(bat_path)
			last_error = "cannot_launch_installer"
			return false
		return true
	return _write_unix_installer(exe_dir, game_dir, exe_name, pid, staging, zip_path)


func _install_macos(exe_path: String, staging: String, pid: int,
		zip_path: String = "", pre_staged_app: String = "") -> bool:
	## An .app is a folder, so swap the whole bundle. Unsigned / ad-hoc signed
	## builds need three extra things the old script missed: a writable
	## location check, restored executable bits (ZIPReader drops Unix modes),
	## and a rollback if the new bundle will not launch.
	var app_path: String = exe_path.get_base_dir().get_base_dir().get_base_dir()
	if not app_path.ends_with(".app"):
		last_error = "not_inside_app_bundle"
		return false
	var staged_app: String = pre_staged_app if pre_staged_app != "" else _find_app_bundle(staging)
	if staged_app == "":
		last_error = "app_not_in_zip"
		return false
	# A standard macOS account cannot write to /Applications. Detect that now
	# and let the dialog offer the manual download instead of lying.
	if not _is_directory_writable(app_path.get_base_dir()):
		last_error = "read_only_app_location"
		return false

	var script_path: String = ProjectSettings.globalize_path(INSTALL_SCRIPT_PATH)
	var lines: PackedStringArray = _macos_install_script_lines(
		app_path, staged_app, exe_path.get_file(), pid, staging, zip_path)
	if lines.is_empty() or not _write_script(script_path, lines):
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
	for value: String in [app_path, staged_app, exe_name, staging_root, zip_path]:
		if value.contains("\n") or value.contains("\r") or value.contains("\u0000"):
			return PackedStringArray()
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
		"for _i in $(seq 1 30); do kill -0 \"$PID\" 2>/dev/null || break; sleep 1; done",
		"sleep 1",
		"rm -rf \"$BACKUP\"",
		"if ! mv \"$APP\" \"$BACKUP\"; then log 'backup failed'; exit 1; fi",
		"rm -rf \"$APP\"",
		"if ! cp -R \"$STAGED\" \"$APP\"; then log 'copy failed'; rm -rf \"$APP\"; mv \"$BACKUP\" \"$APP\"; open -n \"$APP\"; exit 1; fi",
		# ZIPReader recreates every file as 0644. Restore the executable bit on
		# the launcher ONLY. A blanket `chmod -R` here rewrites the sealed
		# resource modes, invalidates the code signature and forces an ad-hoc
		# re-sign on every single update.
		"chmod +x \"$APP/Contents/MacOS/\"* 2>/dev/null",
		# Locally created bundles are not quarantined, but clear it anyway so
		# replacing a signed/notarized previous build never trips Gatekeeper.
		"xattr -dr com.apple.quarantine \"$APP\" 2>/dev/null || true",
		"xattr -cr \"$APP\" 2>/dev/null || true",
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
		"has_bin=0",
		"for _bin in \"$APP/Contents/MacOS/\"*; do [ -f \"$_bin\" ] && [ -x \"$_bin\" ] && has_bin=1 && break; done",
		"if [ \"$has_bin\" -eq 1 ] && open -n \"$APP\"; then",
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


func _linux_install_script_lines(stage_dir: String, game_dir: String,
		exe_name: String, pid: int, staging_root: String = "",
		zip_path: String = "") -> PackedStringArray:
	## Pure Linux installer generator. Never copies or deletes `$game` itself
	## (which could be ~/Downloads!): backs up only the executable (+ optional
	## sidecar .pck), stages a temp file next to the binary, chmod +x's it, and
	## atomically `mv -f`s over the target executable before relaunching.
	var stage_path: String = ProjectSettings.globalize_path(stage_dir)
	var game_path: String = ProjectSettings.globalize_path(game_dir)
	var zip_global: String = ProjectSettings.globalize_path(zip_path) if zip_path != "" else ""
	var pck_name: String = exe_name.get_basename() + ".pck"
	var backup_dir: String = ProjectSettings.globalize_path(UPDATE_DIR + "/linux_backup")
	for value: String in [stage_path, game_path, exe_name, pck_name, zip_global, backup_dir]:
		if value.contains("\n") or value.contains("\r") or value.contains("\u0000"):
			return PackedStringArray()
	var lines: PackedStringArray = PackedStringArray([
		"#!/bin/bash",
		"trap '' HUP",
		"stage=" + _sh_quote(stage_path),
		"game=" + _sh_quote(game_path),
		"exe=" + _sh_quote(exe_name),
		"pck=" + _sh_quote(pck_name),
		"backup_dir=" + _sh_quote(backup_dir),
		"PID=%d" % pid,
		"for _i in $(seq 1 30); do kill -0 \"$PID\" 2>/dev/null || break; sleep 1; done",
		"sleep 1",
		"rm -rf \"$backup_dir\"",
		"mkdir -p \"$backup_dir\" || exit 1",
		"if [ -f \"$game/$exe\" ]; then cp -f \"$game/$exe\" \"$backup_dir/$exe\" || { rm -rf \"$backup_dir\"; exit 1; }; fi",
		"if [ -f \"$game/$pck\" ]; then cp -f \"$game/$pck\" \"$backup_dir/$pck\" || { rm -rf \"$backup_dir\"; exit 1; }; fi",
		"tmp_exe=\"$game/.${exe}.new.$$\"",
		"if cp -f \"$stage/$exe\" \"$tmp_exe\" && chmod +x \"$tmp_exe\" && mv -f \"$tmp_exe\" \"$game/$exe\"; then",
		"  chmod +x \"$game/$exe\"",
		"  for item in \"$stage\"/*; do",
		"    [ -e \"$item\" ] || continue",
		"    base_item=$(basename \"$item\")",
		"    [ \"$base_item\" = \"$exe\" ] && continue",
		"    cp -rf \"$item\" \"$game/$base_item\"",
		"  done",
		# v0.8.0+ embeds the data pack inside CartSlopGP.x86_64. Remove any
		# leftover sidecar .pck from v0.7.x when the new release omits one, so
		# Godot does not load the stale external pack ahead of the embedded one.
		"  if [ ! -f \"$stage/$pck\" ] && [ -f \"$game/$pck\" ]; then rm -f \"$game/$pck\"; fi",
		"  rm -rf \"$backup_dir\"",
		"else",
		"  rm -f \"$tmp_exe\"",
		"  if [ -f \"$backup_dir/$exe\" ]; then mv -f \"$backup_dir/$exe\" \"$game/$exe\"; chmod +x \"$game/$exe\"; fi",
		"  if [ -f \"$backup_dir/$pck\" ]; then mv -f \"$backup_dir/$pck\" \"$game/$pck\"; fi",
		"  rm -rf \"$backup_dir\"",
		"fi",
		"cd \"$game\" || exit 1",
		"nohup \"$game/$exe\" >/dev/null 2>&1 &",
		"disown 2>/dev/null || true",
	])
	if staging_root != "":
		lines.append("rm -rf " + _sh_quote(ProjectSettings.globalize_path(staging_root)))
	if zip_global != "":
		lines.append("rm -f " + _sh_quote(zip_global))
	lines.append("rm -f \"$0\"")
	return lines


func _write_unix_installer(stage_dir: String, game_dir: String, exe_name: String,
		pid: int, staging_root: String = "", zip_path: String = "") -> bool:
	var lines: PackedStringArray = _linux_install_script_lines(
		stage_dir, game_dir, exe_name, pid, staging_root, zip_path)
	if lines.is_empty():
		last_error = "unsafe_install_path"
		return false
	var script_path: String = ProjectSettings.globalize_path(INSTALL_SCRIPT_PATH)
	if not _write_script(script_path, lines):
		return false
	var spawn: int = OS.create_process("/bin/bash", [script_path], false)
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
	if OS.get_name() != "Windows":
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
	var clean_dest: String = destination.simplify_path().trim_suffix("/")
	var root: String = clean_dest + "/"
	for file_name: String in files:
		if file_name.ends_with("/"):
			continue
		var safe_name: String = file_name.replace("\\", "/")
		if safe_name.begins_with("/") or safe_name.contains("..") or safe_name.contains(":"):
			reader.close()
			return false
		var target: String = (clean_dest + "/" + safe_name).simplify_path()
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


func _windows_install_script_lines(game_dir: String, stage_dir: String,
		exe_name: String, staging_root: String = "",
		zip_path: String = "") -> PackedStringArray:
	## Pure Windows .bat installer generator. Works cleanly for single-file
	## embedded CartSlopGP.exe releases (no .pck in zip), removes any stale
	## v0.7.x sidecar .pck when the staged release embeds its pack, uses `ping`
	## instead of `timeout` (which errors out when stdin is non-console), and
	## retries `xcopy` across brief post-exit file locks.
	var pck_name: String = exe_name.get_basename() + ".pck"
	for value: String in [game_dir, stage_dir, exe_name, pck_name, staging_root, zip_path]:
		if value.contains("\"") or value.contains("%") \
				or value.contains("\n") or value.contains("\r") or value.contains("\u0000"):
			return PackedStringArray()
	return PackedStringArray([
		"@echo off",
		"setlocal",
		"title Cart Slop GP update",
		"set \"GAME_DIR=%s\"" % game_dir.replace("/", "\\").trim_suffix("\\"),
		"set \"STAGE=%s\"" % stage_dir.replace("/", "\\").trim_suffix("\\"),
		"set \"STAGE_ROOT=%s\"" % staging_root.replace("/", "\\").trim_suffix("\\"),
		"set \"ZIP=%s\"" % zip_path.replace("/", "\\"),
		"set \"EXE_NAME=%s\"" % exe_name,
		"set \"PCK_NAME=%s\"" % pck_name,
		"set \"GAME_PID=%~1\"",
		"set \"BACKUP=%TEMP%\\CartSlopGP_update_backup_%GAME_PID%\"",
		"echo Waiting for Cart Slop GP to close...",
		"set /a WAIT_TRIES=0",
		":wait",
		"if \"%GAME_PID%\"==\"\" goto install",
		"tasklist /FI \"PID eq %GAME_PID%\" /FO CSV /NH 2>nul | findstr /I \",\\\"%GAME_PID%\\\",\" >nul",
		"if not errorlevel 1 (",
		"  set /a WAIT_TRIES+=1",
		"  if %WAIT_TRIES% GEQ 30 goto install",
		"  ping -n 2 127.0.0.1 >nul 2>&1",
		"  goto wait",
		")",
		":install",
		"echo Backing up the current build...",
		"if exist \"%BACKUP%\" rmdir /S /Q \"%BACKUP%\"",
		"mkdir \"%BACKUP%\"",
		"if not exist \"%BACKUP%\" goto backup_failed",
		"xcopy \"%GAME_DIR%\\*\" \"%BACKUP%\\\" /E /I /Y /Q >nul",
		"if errorlevel 1 goto backup_failed",
		"echo Installing update...",
		"set /a COPY_TRIES=0",
		":copy_retry",
		"xcopy \"%STAGE%\\*\" \"%GAME_DIR%\\\" /E /I /Y /Q >nul",
		"if errorlevel 1 (",
		"  set /a COPY_TRIES+=1",
		"  if %COPY_TRIES% GEQ 5 goto failed",
		"  ping -n 2 127.0.0.1 >nul 2>&1",
		"  goto copy_retry",
		")",
		"if not exist \"%STAGE%\\%PCK_NAME%\" if exist \"%GAME_DIR%\\%PCK_NAME%\" del /F /Q \"%GAME_DIR%\\%PCK_NAME%\" >nul 2>&1",
		"if not exist \"%GAME_DIR%\\%EXE_NAME%\" goto failed",
		"start \"\" /D \"%GAME_DIR%\" \"%GAME_DIR%\\%EXE_NAME%\"",
		"if errorlevel 1 goto failed",
		"ping -n 3 127.0.0.1 >nul 2>&1",
		"rmdir /S /Q \"%BACKUP%\" >nul 2>&1",
		"if not \"%STAGE_ROOT%\"==\"\" rmdir /S /Q \"%STAGE_ROOT%\" >nul 2>&1",
		"if not \"%ZIP%\"==\"\" del /F /Q \"%ZIP%\" >nul 2>&1",
		"(goto) 2>nul & del \"%~f0\"",
		"exit /b 0",
		":failed",
		"echo Update failed. Restoring your previous build...",
		"cd /d \"%TEMP%\"",
		"xcopy \"%BACKUP%\\*\" \"%GAME_DIR%\\\" /E /I /Y /Q >nul",
		"start \"\" /D \"%GAME_DIR%\" \"%GAME_DIR%\\%EXE_NAME%\"",
		"ping -n 3 127.0.0.1 >nul 2>&1",
		"rmdir /S /Q \"%BACKUP%\" >nul 2>&1",
		"echo The previous build was restored.",
		"ping -n 4 127.0.0.1 >nul 2>&1",
		"if not \"%STAGE_ROOT%\"==\"\" rmdir /S /Q \"%STAGE_ROOT%\" >nul 2>&1",
		"if not \"%ZIP%\"==\"\" del /F /Q \"%ZIP%\" >nul 2>&1",
		"(goto) 2>nul & del \"%~f0\"",
		"exit /b 1",
		":backup_failed",
		"echo Could not back up the current build, so nothing was changed.",
		"echo Launch the game normally and update again, or download the zip manually.",
		"ping -n 5 127.0.0.1 >nul 2>&1",
		"if not \"%STAGE_ROOT%\"==\"\" rmdir /S /Q \"%STAGE_ROOT%\" >nul 2>&1",
		"if not \"%ZIP%\"==\"\" del /F /Q \"%ZIP%\" >nul 2>&1",
		"(goto) 2>nul & del \"%~f0\"",
		"exit /b 1",
	])


func _write_installer(bat_path: String, game_dir: String, stage_dir: String,
		exe_name: String, staging_root: String = "", zip_path: String = "") -> bool:
	var lines: PackedStringArray = _windows_install_script_lines(
		game_dir, stage_dir, exe_name, staging_root, zip_path)
	if lines.is_empty():
		return false
	var file: FileAccess = FileAccess.open(bat_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("\r\n".join(lines) + "\r\n")
	file.close()
	return true


static func _parse_semver(tag: String) -> Dictionary:
	## Strict SemVer parser. Accepts optional "v" or "release-[v]" prefix, 2..4
	## dot-separated numeric core segments, optional "-prerelease" identifiers
	## and optional "+build" metadata. Rejects date tags ("release-2026-11-07")
	## and malformed strings ("0..8", "1..", ".0.8", "0.8.0_bad").
	var text: String = tag.strip_edges().to_lower()
	if text == "" or text.length() > 64:
		return {"ok": false}
	if text.begins_with("release-v"):
		text = text.substr(9)
	elif text.begins_with("release_v"):
		text = text.substr(9)
	elif text.begins_with("release-"):
		text = text.substr(8)
	elif text.begins_with("release_"):
		text = text.substr(8)
	elif text.begins_with("v"):
		text = text.substr(1)
	if text == "":
		return {"ok": false}

	# Strip and validate optional +build metadata (ignored for precedence).
	var plus_idx: int = text.find("+")
	if plus_idx >= 0:
		var build_meta: String = text.substr(plus_idx + 1)
		text = text.substr(0, plus_idx)
		if build_meta == "" or build_meta.begins_with(".") or build_meta.ends_with(".") \
				or build_meta.contains(".."):
			return {"ok": false}
		for ch: String in build_meta:
			if not "0123456789abcdefghijklmnopqrstuvwxyz.-".contains(ch):
				return {"ok": false}

	var core_str: String = text
	var pre_str: String = ""
	var dash_idx: int = text.find("-")
	if dash_idx >= 0:
		core_str = text.substr(0, dash_idx)
		pre_str = text.substr(dash_idx + 1)
		if pre_str == "" or pre_str.begins_with(".") or pre_str.ends_with(".") \
				or pre_str.contains(".."):
			return {"ok": false}
		for ch: String in pre_str:
			if not "0123456789abcdefghijklmnopqrstuvwxyz.-".contains(ch):
				return {"ok": false}

	if core_str == "" or core_str.begins_with(".") or core_str.ends_with(".") \
			or core_str.contains(".."):
		return {"ok": false}
	var raw_parts: PackedStringArray = core_str.split(".", true)
	if raw_parts.size() < 2 or raw_parts.size() > 4:
		return {"ok": false}
	var nums: PackedInt64Array = PackedInt64Array()
	var clean_parts: PackedStringArray = PackedStringArray()
	for part: String in raw_parts:
		if part == "" or part.length() > 9:
			return {"ok": false}
		for ch: String in part:
			if ch < "0" or ch > "9":
				return {"ok": false}
		var val: int = int(part)
		nums.append(val)
		clean_parts.append(str(val))
	var normalized: String = ".".join(clean_parts)
	if pre_str != "":
		normalized += "-" + pre_str
	return {
		"ok": true,
		"nums": nums,
		"pre": pre_str,
		"normalized": normalized,
	}


static func _compare_prerelease_token(left: String, right: String) -> int:
	if left == right:
		return 0
	var left_digits: bool = left != "" and left.length() <= 9
	for ch: String in left:
		if ch < "0" or ch > "9":
			left_digits = false
			break
	var right_digits: bool = right != "" and right.length() <= 9
	for ch: String in right:
		if ch < "0" or ch > "9":
			right_digits = false
			break
	if left_digits and right_digits:
		var a: int = int(left)
		var b: int = int(right)
		return 1 if a > b else (-1 if a < b else 0)
	if left_digits != right_digits:
		# Per SemVer 2.0.0: numeric identifiers have lower precedence than non-numeric.
		return -1 if left_digits else 1
	# Natural comparison for combined alpha+number tokens such as "rc2" vs "rc10".
	var l_split: int = left.length()
	while l_split > 0 and left[l_split - 1] >= "0" and left[l_split - 1] <= "9":
		l_split -= 1
	var r_split: int = right.length()
	while r_split > 0 and right[r_split - 1] >= "0" and right[r_split - 1] <= "9":
		r_split -= 1
	if l_split > 0 and l_split == r_split \
			and l_split < left.length() and r_split < right.length() \
			and left.substr(0, l_split) == right.substr(0, r_split):
		var l_tail: String = left.substr(l_split)
		var r_tail: String = right.substr(r_split)
		if l_tail.length() <= 9 and r_tail.length() <= 9:
			var ln: int = int(l_tail)
			var rn: int = int(r_tail)
			if ln != rn:
				return 1 if ln > rn else -1
	return 1 if left > right else -1


func normalize_version(tag: String) -> String:
	## "v0.2.1" / "release-0.2.1" -> "0.2.1". A date tag such as
	## "release-2026-11-07" or a corrupt string returns "".
	var parsed: Dictionary = _parse_semver(tag)
	if not bool(parsed.get("ok", false)):
		return ""
	return str(parsed["normalized"])


func version_greater(candidate: String, current: String) -> bool:
	## Numeric SemVer comparison; missing trailing core segments count as 0,
	## and pre-release suffixes sort below their final release (0.8.0 > 0.8.0-rc1).
	var left_parsed: Dictionary = _parse_semver(candidate)
	if not bool(left_parsed.get("ok", false)):
		return false
	var right_parsed: Dictionary = _parse_semver(current)
	if not bool(right_parsed.get("ok", false)):
		# Allow a valid release to replace a build with a corrupt version.txt.
		return true
	var left: PackedInt64Array = left_parsed["nums"] as PackedInt64Array
	var right: PackedInt64Array = right_parsed["nums"] as PackedInt64Array
	var count: int = maxi(left.size(), right.size())
	for index in count:
		var a: int = int(left[index]) if index < left.size() else 0
		var b: int = int(right[index]) if index < right.size() else 0
		if a != b:
			return a > b
	var left_pre: String = str(left_parsed["pre"])
	var right_pre: String = str(right_parsed["pre"])
	if left_pre == right_pre:
		return false
	if left_pre == "":
		return true
	if right_pre == "":
		return false
	var l_tokens: PackedStringArray = left_pre.split(".", false)
	var r_tokens: PackedStringArray = right_pre.split(".", false)
	var pre_count: int = mini(l_tokens.size(), r_tokens.size())
	for index in pre_count:
		var cmp: int = _compare_prerelease_token(l_tokens[index], r_tokens[index])
		if cmp != 0:
			return cmp > 0
	return l_tokens.size() > r_tokens.size()
