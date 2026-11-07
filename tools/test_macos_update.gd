extends SceneTree
## Validates the macOS self-update installer WITHOUT needing a Mac. Run:
##   godot --headless --path . --script tools/test_macos_update.gd
##
## It checks the generated shell script for the four things that broke the
## old one-click update: quitting the game, executable bits, quarantine /
## ad-hoc signing, and rollback if the new bundle will not launch.

var _failures: int = 0


func _expect(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1


func _init() -> void:
	print("--- MACOS UPDATER ---")
	var checker: Node = load("res://scripts/systems/update_checker.gd").new()
	var lines: PackedStringArray = checker.call("_macos_install_script_lines",
		"/Applications/Cart Slop GP.app", "/staged/Cart Slop GP.app",
		"Cart Slop GP", 4242)
	var script: String = "\n".join(lines)

	_expect(script.contains("APP=\"/Applications/Cart Slop GP.app\""),
		"bundle path with spaces is quoted")
	_expect(script.contains("while kill -0 \"$PID\""), "waits for the game to quit")
	_expect(script.contains("chmod +x \"$APP/Contents/MacOS/\""),
		"restores executable bits lost by ZIPReader")
	_expect(script.contains("xattr -dr com.apple.quarantine"),
		"clears Gatekeeper quarantine")
	_expect(script.contains("codesign --verify --deep"),
		"verifies the copied bundle signature")
	_expect(not script.contains("chmod -R"),
		"no blanket chmod that would invalidate the signature every update")
	_expect(script.contains("no re-sign needed"),
		"skips re-signing when the signature is intact")
	_expect(script.contains("open -n \"$APP\""), "launches a fresh instance")
	_expect(script.contains("mv \"$BACKUP\" \"$APP\""),
		"restores the previous build on failure")
	_expect(script.contains("rm -rf \"$BACKUP\""), "cleans up backup on success")

	var source: String = ""
	var file: FileAccess = FileAccess.open(
		"res://scripts/systems/update_checker.gd", FileAccess.READ)
	if file != null:
		source = file.get_as_text()
		file.close()
	_expect(not source.contains("return _install_macos("),
		"macOS branch no longer skips get_tree().quit()")
	_expect(source.contains("get_tree().quit()"), "installer quits the game")
	_expect(source.contains("read_only_app_location"),
		"read-only app location is detected before quitting")

	checker.free()
	if _failures == 0:
		print("MACOS UPDATER TESTS: all passed")
	else:
		print("MACOS UPDATER TESTS: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)
