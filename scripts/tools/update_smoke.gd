extends SceneTree
## Headless end-to-end smoke test for UpdateChecker.
##
## Run:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot_project --script res://scripts/tools/update_smoke.gd

const UpdateCheckerScript := preload("res://scripts/systems/update_checker.gd")

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("UPDATE_SMOKE FAIL: " + message)
		print("FAIL  " + message)


func _sha256_bytes(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()


func _build_zip(zip_path: String, entries: Dictionary) -> bool:
	var packer := ZIPPacker.new()
	var error: Error = packer.open(zip_path, ZIPPacker.APPEND_CREATE)
	if error != OK:
		print("ZIP open failed for ", zip_path, ": ", error)
		return false
	for raw_name: Variant in entries.keys():
		var entry_name: String = str(raw_name)
		error = packer.start_file(entry_name)
		if error != OK:
			print("ZIP start_file failed for ", entry_name, ": ", error)
			packer.close()
			return false
		var payload: PackedByteArray = entries[raw_name] as PackedByteArray
		error = packer.write_file(payload)
		if error != OK:
			print("ZIP write_file failed for ", entry_name, ": ", error)
			packer.close()
			return false
		error = packer.close_file()
		if error != OK:
			print("ZIP close_file failed for ", entry_name, ": ", error)
			packer.close()
			return false
	packer.close()
	return FileAccess.file_exists(zip_path) and FileAccess.get_file_as_bytes(zip_path).size() > 0


func _remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir != null:
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if entry != "." and entry != "..":
				var full: String = path + "/" + entry
				if dir.current_is_dir():
					_remove_tree(full)
				else:
					DirAccess.remove_absolute(full)
			entry = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(path)


func _run() -> void:
	var saved_env: String = OS.get_environment("CARTSLOP_UPDATE_SERVER")
	OS.set_environment("CARTSLOP_UPDATE_SERVER", "")
	var checker = UpdateCheckerScript.new()
	var scratch_base: String = ProjectSettings.globalize_path("res://.godot").replace("\\", "/").trim_suffix("/")
	var scratch: String = "%s/cartslop_update_smoke_%d_%d" % [
		scratch_base, OS.get_process_id(), Time.get_ticks_usec()
	]
	DirAccess.make_dir_recursive_absolute(scratch)

	# ------------------------------------------------------------------
	# 1. Version file check (the shipped version, not a hard-coded number, so a
	#    version bump never makes this suite lie)
	# ------------------------------------------------------------------
	var shipped: String = checker.read_version_file()
	_check(shipped != "" and not shipped.begins_with("0.0"),
		"read_version_file() must return the shipped version, got '%s'" % shipped)
	_check(checker.local_version() == shipped,
		"local_version() must equal '%s', got '%s'" % [shipped, checker.local_version()])
	_check(checker.version_string() == "v" + shipped,
		"version_string() must equal 'v%s', got '%s'" % [shipped, checker.version_string()])

	# ------------------------------------------------------------------
	# 2. Version comparator & parser edge cases
	# ------------------------------------------------------------------
	_check(checker.version_greater("0.8.0", "0.7.3"), "0.8.0 must be > 0.7.3")
	_check(not checker.version_greater("0.7.3", "0.8.0"), "0.7.3 must be < 0.8.0")
	_check(not checker.version_greater("0.8.0", "0.8.0"), "0.8.0 == 0.8.0 must not compare greater")
	_check(not checker.version_greater("v0.8.0", "0.8.0"), "v0.8.0 == 0.8.0 must strip tag prefix")
	_check(not checker.version_greater("0.8", "0.8.0"), "0.8 == 0.8.0 missing patch segment must equal 0")
	_check(checker.version_greater("0.8.1", "0.8.0"), "0.8.1 must be > 0.8.0")
	_check(not checker.version_greater("0.8.0", "0.8.1"), "0.8.0 must be < 0.8.1")
	_check(checker.version_greater("0.10.0", "0.8.0"), "0.10.0 must be > 0.8.0 (numeric, not lexical)")
	_check(not checker.version_greater("0.8.0", "0.10.0"), "0.8.0 must be < 0.10.0")

	# Tag prefixes & pre-release suffixes
	_check(checker.normalize_version("v0.8.0") == "0.8.0", "v0.8.0 normalizes to 0.8.0")
	_check(checker.normalize_version("  V0.8.0\n") == "0.8.0", "V0.8.0 with whitespace normalizes to 0.8.0")
	_check(checker.normalize_version("release-0.8.0") == "0.8.0", "release-0.8.0 normalizes to 0.8.0")
	_check(checker.normalize_version("release-v0.8.0") == "0.8.0", "release-v0.8.0 normalizes to 0.8.0")
	_check(checker.normalize_version("v0.8.0-rc1") == "0.8.0-rc1", "pre-release suffix is preserved")
	_check(checker.version_greater("0.8.0-rc1", "0.7.3"), "0.8.0-rc1 must be > 0.7.3")
	_check(checker.version_greater("0.8.0", "0.8.0-rc1"), "final 0.8.0 must be > 0.8.0-rc1")
	_check(not checker.version_greater("0.8.0-rc1", "0.8.0"), "0.8.0-rc1 must not outrank final 0.8.0")
	_check(checker.version_greater("0.8.0-rc10", "0.8.0-rc2"), "0.8.0-rc10 must be > 0.8.0-rc2")
	_check(checker.version_greater("0.8.0-rc.1", "0.8.0-beta.9"), "rc must outrank beta")

	# Corrupt / date tags must normalize to "" and never compare greater
	for bad_tag: String in ["", "   ", "v", "corrupt", "release-2026-11-07", "2026",
			"0..8.0", "1..", ".0.8", "0.8.", "0.8.0-", "0.8.0+", "0.8.0_evil",
			"999999999999999999.0.0"]:
		_check(checker.normalize_version(bad_tag) == "",
			"corrupt version '%s' must normalize to empty string" % bad_tag)
		_check(not checker.version_greater(bad_tag, "0.7.3"),
			"corrupt version '%s' must never be > 0.7.3" % bad_tag)

	# ------------------------------------------------------------------
	# 3. Trusted URL / host validation
	# ------------------------------------------------------------------
	checker.mirror_override = ""
	_check(checker.is_trusted_download_url(
		"https://github.com/HOT18594/CartSlopGP/releases/download/v0.8.0/CartSlopGP_v0.8.0_windows.zip"),
		"GitHub release download URL must be trusted")
	_check(checker.is_trusted_download_url(
		"https://objects.githubusercontent.com/github-production-release-asset-12345/abcdef?X-Amz-Signature=deadbeef"),
		"objects.githubusercontent.com redirect URL must be trusted")
	_check(checker.is_trusted_download_url(
		"https://release-assets.githubusercontent.com/github-production-release-asset-999/fedcba?sp=r&sv=2018-11-09"),
		"release-assets.githubusercontent.com redirect URL must be trusted")
	_check(checker.is_trusted_download_url(
		"https://codeload.github.com/HOT18594/CartSlopGP/zip/refs/tags/v0.8.0"),
		"codeload.github.com URL must be trusted")

	# Reject untrusted third-party domains, userinfo bypasses, and plain HTTP to non-mirrors
	for untrusted_url: String in [
		"https://evil.example.com/CartSlopGP_v0.8.0_windows.zip",
		"https://github.com.evil.example.com/CartSlopGP_v0.8.0_windows.zip",
		"https://evilgithubusercontent.com/CartSlopGP_v0.8.0_windows.zip",
		"https://github.com@evil.example.com/CartSlopGP_v0.8.0_windows.zip",
		"http://github.com/HOT18594/CartSlopGP/releases/download/v0.8.0/CartSlopGP_v0.8.0_windows.zip",
		"http://objects.githubusercontent.com/asset.zip",
		"http://release-assets.githubusercontent.com/asset.zip",
		"http://68.204.45.1:42777/updates/CartSlopGP_v0.8.0_windows.zip",
		"file:///C:/Windows/System32/calc.exe",
		"",
	]:
		_check(not checker.is_trusted_download_url(untrusted_url),
			"untrusted URL '%s' must be rejected" % untrusted_url)

	# Configured LAN Pi mirror (RFC1918 HTTP) and HTTPS mirror
	checker.mirror_override = "http://192.168.1.22:42777"
	_check(checker.is_trusted_download_url(
		"http://192.168.1.22:42777/updates/CartSlopGP_v0.8.0_windows.zip"),
		"Configured LAN Pi mirror /updates/*.zip must be trusted")
	_check(not checker.is_trusted_download_url(
		"http://192.168.1.99:42777/updates/CartSlopGP_v0.8.0_windows.zip"),
		"Unconfigured LAN host must be rejected when a different mirror is configured")
	_check(not checker.is_trusted_download_url(
		"http://192.168.1.22:42777/updates/../evil.zip"),
		"Mirror path traversal must be rejected")
	_check(not checker.is_trusted_download_url(
		"http://192.168.1.22:42777/CartSlopGP.exe"),
		"Mirror non-/updates/ path must be rejected")

	checker.mirror_override = "https://mirror.cartslop.example"
	_check(checker.is_trusted_download_url(
		"https://mirror.cartslop.example/updates/CartSlopGP_v0.8.0_macos.zip"),
		"Configured HTTPS mirror must be trusted on default port 443")
	_check(not checker.is_trusted_download_url(
		"https://other.cartslop.example/updates/CartSlopGP_v0.8.0_macos.zip"),
		"Different HTTPS host must not match configured mirror")

	checker.mirror_override = "http://203.0.113.10:42777"
	_check(checker._configured_server_base() == "",
		"Public plain-HTTP mirror override must be rejected as untrusted")
	_check(not checker.is_trusted_download_url(
		"http://203.0.113.10:42777/updates/CartSlopGP_v0.8.0_linux.zip"),
		"Public plain-HTTP mirror URL must be rejected")
	checker.mirror_override = ""

	# ------------------------------------------------------------------
	# 4. Parsing Pi manifest.json AND GitHub /releases/latest for Win/Mac/Linux
	# ------------------------------------------------------------------
	var sha_win: String = "a".repeat(64)
	var sha_mac: String = "b".repeat(64)
	var sha_lin: String = "c".repeat(64)

	var pi_manifest: Dictionary = {
		"version": "0.8.0",
		"release_url": "https://github.com/HOT18594/CartSlopGP/releases/tag/v0.8.0",
		"notes": "Cart Slop GP v0.8.0",
		"assets": {
			"windows": "CartSlopGP_v0.8.0_windows.zip",
			"macos": "CartSlopGP_v0.8.0_macos.zip",
			"linux": "CartSlopGP_v0.8.0_linux.zip",
			"web": "CartSlopGP_v0.8.0_web.zip",
		},
		"sha256": {
			"windows": sha_win,
			"macos": sha_mac,
			"linux": sha_lin,
			"web": "d".repeat(64),
		},
		"sizes": {
			"windows": 118797006,
			"macos": 140442396,
			"linux": 108847358,
			"web": 90232204,
		},
	}
	var expected_by_plat: Dictionary = {
		"windows": {"name": "CartSlopGP_v0.8.0_windows.zip", "sha": sha_win, "size": 118797006},
		"macos": {"name": "CartSlopGP_v0.8.0_macos.zip", "sha": sha_mac, "size": 140442396},
		"linux": {"name": "CartSlopGP_v0.8.0_linux.zip", "sha": sha_lin, "size": 108847358},
	}
	for plat: String in ["windows", "macos", "linux"]:
		var exp: Dictionary = expected_by_plat[plat]
		var parsed_pi: Dictionary = checker.parse_mirror_manifest(
			pi_manifest, "http://192.168.1.22:42777", plat)
		_check(bool(parsed_pi.get("ok", false)),
			"Pi manifest.json must parse for %s" % plat)
		_check(str(parsed_pi.get("version", "")) == "0.8.0",
			"Pi manifest version must be 0.8.0 for %s" % plat)
		_check(str(parsed_pi.get("asset_name", "")) == str(exp["name"]),
			"Pi manifest asset_name mismatch for %s" % plat)
		_check(str(parsed_pi.get("asset_url", "")) == "http://192.168.1.22:42777/updates/" + str(exp["name"]),
			"Pi manifest asset_url mismatch for %s" % plat)
		_check(str(parsed_pi.get("sha256", "")) == str(exp["sha"]),
			"Pi manifest sha256 mismatch for %s" % plat)
		_check(int(parsed_pi.get("size", 0)) == int(exp["size"]),
			"Pi manifest size mismatch for %s" % plat)

	# Also verify the flattened /api/update?platform=windows JSON structure
	var api_update_doc: Dictionary = {
		"version": "v0.8.0",
		"asset_name": "CartSlopGP_v0.8.0_windows.zip",
		"asset_path": "/updates/CartSlopGP_v0.8.0_windows.zip",
		"release_url": "https://github.com/HOT18594/CartSlopGP/releases/tag/v0.8.0",
		"sha256": sha_win,
		"size": 118797006,
		"source": "pi",
	}
	var parsed_api: Dictionary = checker.parse_mirror_manifest(
		api_update_doc, "http://127.0.0.1:42777", "windows")
	_check(bool(parsed_api.get("ok", false))
		and str(parsed_api.get("asset_url", "")) == "http://127.0.0.1:42777/updates/CartSlopGP_v0.8.0_windows.zip",
		"Flattened /api/update response must parse cleanly")

	# GitHub /releases/latest payload (modern release with sha256 digest)
	var github_release: Dictionary = {
		"tag_name": "v0.8.0",
		"draft": false,
		"prerelease": false,
		"html_url": "https://github.com/HOT18594/CartSlopGP/releases/tag/v0.8.0",
		"assets": [
			{
				"name": "SHA256SUMS",
				"size": 376,
				"digest": "sha256:" + "e".repeat(64),
				"browser_download_url": "https://github.com/HOT18594/CartSlopGP/releases/download/v0.8.0/SHA256SUMS",
			},
			{
				"name": "CartSlopGP_v0.8.0_windows.zip",
				"size": 118797006,
				"digest": "sha256:" + sha_win,
				"browser_download_url": "https://github.com/HOT18594/CartSlopGP/releases/download/v0.8.0/CartSlopGP_v0.8.0_windows.zip",
			},
			{
				"name": "CartSlopGP_v0.8.0_macos.zip",
				"size": 140442396,
				"digest": "SHA256:" + sha_mac.to_upper(),
				"browser_download_url": "https://github.com/HOT18594/CartSlopGP/releases/download/v0.8.0/CartSlopGP_v0.8.0_macos.zip",
			},
			{
				"name": "CartSlopGP_v0.8.0_linux.zip",
				"size": 108847358,
				"digest": "sha256:" + sha_lin,
				"browser_download_url": "https://github.com/HOT18594/CartSlopGP/releases/download/v0.8.0/CartSlopGP_v0.8.0_linux.zip",
			},
		],
	}
	for plat: String in ["windows", "macos", "linux"]:
		var exp: Dictionary = expected_by_plat[plat]
		var gh_parsed: Dictionary = checker.parse_github_release(github_release, plat)
		_check(bool(gh_parsed.get("ok", false)),
			"GitHub /releases/latest must parse for %s" % plat)
		_check(str(gh_parsed.get("version", "")) == "0.8.0",
			"GitHub version must normalize v0.8.0 -> 0.8.0 for %s" % plat)
		_check(str(gh_parsed.get("asset_name", "")) == str(exp["name"]),
			"GitHub asset_name mismatch for %s" % plat)
		_check(str(gh_parsed.get("asset_url", "")).ends_with("/" + str(exp["name"])),
			"GitHub asset_url mismatch for %s" % plat)
		_check(str(gh_parsed.get("sha256", "")) == str(exp["sha"]),
			"GitHub sha256 digest mismatch for %s" % plat)
		_check(int(gh_parsed.get("size", 0)) == int(exp["size"]),
			"GitHub asset size mismatch for %s" % plat)
		_check(checker.version_greater(str(gh_parsed["version"]), "0.7.3"),
			"0.7.3 client must detect GitHub 0.8.0 as newer for %s" % plat)

	# Older GitHub release with null / empty digest: must fail closed on auto-zip
	# while preserving version + release_url cleanly without errors.
	var legacy_github_release: Dictionary = {
		"tag_name": "v0.8.0",
		"draft": false,
		"html_url": "https://github.com/HOT18594/CartSlopGP/releases/tag/v0.8.0",
		"assets": [
			{
				"name": "CartSlopGP_v0.8.0_windows.zip",
				"size": 118797006,
				"digest": null,
				"browser_download_url": "https://github.com/HOT18594/CartSlopGP/releases/download/v0.8.0/CartSlopGP_v0.8.0_windows.zip",
			},
		],
	}
	var legacy_gh: Dictionary = checker.parse_github_release(legacy_github_release, "windows")
	_check(bool(legacy_gh.get("ok", false))
		and str(legacy_gh.get("version", "")) == "0.8.0"
		and str(legacy_gh.get("release_url", "")) == "https://github.com/HOT18594/CartSlopGP/releases/tag/v0.8.0"
		and str(legacy_gh.get("asset_url", "")) == ""
		and bool(legacy_gh.get("unverified_asset", false)),
		"Older GitHub release without digest must fail closed for auto-install while keeping release_url")

	# ------------------------------------------------------------------
	# 5. Synthetic single-file embedded-exe zip + SHA-256 + tamper + staging
	# ------------------------------------------------------------------
	var fake_win_exe: PackedByteArray = ("MZ_CARTSLOP_EMBEDDED_PCK_V080_" + "X".repeat(4096)).to_utf8_buffer()
	var win_zip_path: String = scratch + "/CartSlopGP_v0.8.0_windows.zip"
	var win_zip_created: bool = _build_zip(win_zip_path, {"CartSlopGP.exe": fake_win_exe})
	_check(win_zip_created, "Synthetic single-file Windows embedded-exe zip must be created")
	if not win_zip_created:
		_remove_tree(scratch)
		OS.set_environment("CARTSLOP_UPDATE_SERVER", saved_env)
		checker.free()
		print("UPDATE_SMOKE: FAIL (%d/%d failed; ZIP fixture creation aborted the run)" % [_failures, _checks])
		quit(1)
		return

	var win_zip_bytes: PackedByteArray = FileAccess.get_file_as_bytes(win_zip_path)
	var win_zip_sha: String = _sha256_bytes(win_zip_bytes)
	var win_zip_size: int = win_zip_bytes.size()
	_check(checker.verify_zip_integrity(win_zip_path, win_zip_sha, win_zip_size) == "",
		"Valid synthetic Windows zip must pass SHA-256 + size verification")
	_check(checker.verify_zip_integrity(win_zip_path, "sha256:" + win_zip_sha.to_upper(), win_zip_size) == "",
		"SHA-256 verification must accept 'sha256:' prefix and uppercase hex")
	_check(checker.verify_zip_integrity(win_zip_path, "", win_zip_size) == "unverified",
		"Empty SHA-256 must fail closed as 'unverified'")
	_check(checker.verify_zip_integrity(win_zip_path, win_zip_sha, win_zip_size + 4) == "size_mismatch",
		"Wrong byte size must fail with 'size_mismatch'")

	# Tamper 1 byte in a copy of the zip and confirm checksum rejection
	var tampered_path: String = scratch + "/CartSlopGP_v0.8.0_tampered.zip"
	var tampered_bytes: PackedByteArray = win_zip_bytes.duplicate()
	var mid: int = tampered_bytes.size() >> 1
	tampered_bytes[mid] = tampered_bytes[mid] ^ 0xFF
	var tampered_out: FileAccess = FileAccess.open(tampered_path, FileAccess.WRITE)
	tampered_out.store_buffer(tampered_bytes)
	tampered_out.close()
	_check(checker.verify_zip_integrity(tampered_path, win_zip_sha, win_zip_size) == "checksum_mismatch",
		"Tampered zip must be rejected with 'checksum_mismatch'")

	# Stage Windows single-file embedded exe (NO .pck!)
	var win_stage_dir: String = scratch + "/stage_win"
	var win_staged: Dictionary = checker.stage_update_zip(
		win_zip_path, win_stage_dir, scratch + "/game_win/CartSlopGP.exe", "Windows")
	_check(bool(win_staged.get("ok", false)),
		"Windows staging must succeed with ONLY CartSlopGP.exe and NO .pck")
	_check(not bool(win_staged.get("has_pck", true)),
		"Windows single-file staging must report has_pck == false")
	_check(FileAccess.get_file_as_bytes(win_stage_dir + "/CartSlopGP.exe") == fake_win_exe,
		"Extracted CartSlopGP.exe bytes must match embedded binary")

	# Stage Linux single-file embedded binary (NO .pck!)
	var fake_lin_exe: PackedByteArray = ("ELF_CARTSLOP_EMBEDDED_V080_" + "L".repeat(2048)).to_utf8_buffer()
	var lin_zip_path: String = scratch + "/CartSlopGP_v0.8.0_linux.zip"
	_check(_build_zip(lin_zip_path, {"CartSlopGP.x86_64": fake_lin_exe}),
		"Synthetic single-file Linux zip must be created")
	var lin_stage_dir: String = scratch + "/stage_lin"
	var lin_staged: Dictionary = checker.stage_update_zip(
		lin_zip_path, lin_stage_dir, "/home/player/Downloads/CartSlopGP.x86_64", "Linux")
	_check(bool(lin_staged.get("ok", false)) and not bool(lin_staged.get("has_pck", true)),
		"Linux staging must succeed with ONLY CartSlopGP.x86_64 and NO .pck")
	_check(FileAccess.get_file_as_bytes(lin_stage_dir + "/CartSlopGP.x86_64") == fake_lin_exe,
		"Extracted CartSlopGP.x86_64 bytes must match embedded binary")

	# Stage macOS .app bundle
	var fake_mac_bin: PackedByteArray = ("MACHO_CARTSLOP_V080_" + "M".repeat(1024)).to_utf8_buffer()
	var mac_zip_path: String = scratch + "/CartSlopGP_v0.8.0_macos.zip"
	_check(_build_zip(mac_zip_path, {
		"Cart Slop GP.app/Contents/Info.plist": "<plist/>".to_utf8_buffer(),
		"Cart Slop GP.app/Contents/MacOS/Cart Slop GP": fake_mac_bin,
		"Cart Slop GP.app/Contents/Resources/Cart Slop GP.pck": "PCK".to_utf8_buffer(),
	}), "Synthetic macOS .app zip must be created")
	var mac_stage_dir: String = scratch + "/stage_mac"
	var mac_staged: Dictionary = checker.stage_update_zip(
		mac_zip_path, mac_stage_dir,
		"/Users/player/Games/Cart Slop GP.app/Contents/MacOS/Cart Slop GP", "macOS")
	_check(bool(mac_staged.get("ok", false))
		and str(mac_staged.get("staged_app", "")).ends_with("Cart Slop GP.app"),
		"macOS staging must locate 'Cart Slop GP.app' bundle")

	# Reject Zip-Slip path traversal inside zip
	var traversal_zip: String = scratch + "/evil.zip"
	_check(_build_zip(traversal_zip, {"../../evil.exe": "bad".to_utf8_buffer()}),
		"Synthetic traversal zip built for negative test")
	var traversal_staged: Dictionary = checker.stage_update_zip(
		traversal_zip, scratch + "/stage_evil", scratch + "/game_win/CartSlopGP.exe", "Windows")
	_check(not bool(traversal_staged.get("ok", true)),
		"Zip-Slip traversal archive must be rejected during extraction")

	# Audit generated self-install scripts for all 3 desktop platforms
	var win_lines: String = "\n".join(checker._windows_install_script_lines(
		"C:\\Games\\CartSlopGP", "C:\\Temp\\stage", "CartSlopGP.exe", "C:\\Temp\\stage", "C:\\Temp\\u.zip"))
	_check(win_lines.contains("xcopy \"%STAGE%\\*\" \"%GAME_DIR%\\\"")
		and not win_lines.to_lower().contains("copy *.pck")
		and not win_lines.to_lower().contains("timeout /t")
		and win_lines.contains("if not exist \"%STAGE%\\%PCK_NAME%\" if exist \"%GAME_DIR%\\%PCK_NAME%\" del"),
		"Windows installer script must copy single-exe stage without *.pck failure and purge stale v0.7.x .pck")

	var lin_lines: String = "\n".join(checker._linux_install_script_lines(
		"/tmp/stage", "/home/player/Downloads", "CartSlopGP.x86_64", 4242, "/tmp/stage", "/tmp/u.zip"))
	_check(lin_lines.contains("chmod +x \"$tmp_exe\"")
		and lin_lines.contains("mv -f \"$tmp_exe\" \"$game/$exe\"")
		and not lin_lines.contains("rm -rf \"$game\"")
		and lin_lines.contains("nohup \"$game/$exe\""),
		"Linux installer script must chmod +x, atomically mv over executable, never rm -rf $game, and relaunch")

	var mac_lines: String = "\n".join(checker._macos_install_script_lines(
		"/Users/player/Cart Slop GP.app", "/tmp/stage/Cart Slop GP.app", "Cart Slop GP", 4242, "/tmp/stage", "/tmp/u.zip"))
	_check(mac_lines.contains("chmod +x \"$APP/Contents/MacOS/\"*")
		and mac_lines.contains("com.apple.quarantine")
		and mac_lines.contains("open -n \"$APP\""),
		"macOS installer script must chmod +x Contents/MacOS/*, clear quarantine xattr, and relaunch")

	OS.set_environment("CARTSLOP_UPDATE_SERVER", "http://127.0.0.1:42777")
	_check(checker._configured_server_base() == "http://127.0.0.1:42777"
		and checker.is_trusted_download_url("http://127.0.0.1:42777/updates/CartSlopGP_v0.8.0_windows.zip"),
		"CARTSLOP_UPDATE_SERVER loopback mirror must be accepted")
	OS.set_environment("CARTSLOP_UPDATE_SERVER", "")

	_remove_tree(scratch)
	OS.set_environment("CARTSLOP_UPDATE_SERVER", saved_env)
	checker.free()

	if _failures == 0:
		print("UPDATE_SMOKE: PASS (%d checks)" % _checks)
		quit(0)
	else:
		print("UPDATE_SMOKE: FAIL (%d/%d failed)" % [_failures, _checks])
		quit(1)
