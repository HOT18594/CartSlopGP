extends SceneTree
## Validates that a stale Pi update mirror can never hide a newer GitHub
## release, and that the mirror still works when GitHub is unreachable.

var _failures: int = 0


func _expect(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	if not condition:
		_failures += 1


func _init() -> void:
	print("--- UPDATE MIRROR ARBITRATION ---")
	var checker: Node = load("res://scripts/systems/update_checker.gd").new()
	root.add_child(checker)
	var github_body: PackedByteArray = JSON.stringify({
		"tag_name": "v0.6.3",
		"html_url": "https://github.com/HOT18594/CartSlopGP/releases/tag/v0.6.3",
		"assets": [{"name": "CartSlopGP_v0.6.3_windows.zip",
			"browser_download_url": "https://example.invalid/windows.zip"}],
	}).to_utf8_buffer()

	# 1. Stale mirror (0.6.2) must not override GitHub 0.6.3.
	checker.set("_server_candidate", {
		"version": "0.6.2", "base": "http://pi:42777",
		"asset_name": "CartSlopGP_v0.6.2_windows.zip",
		"asset_path": "", "release_url": "",
	})
	checker.call("_on_check_completed", HTTPRequest.RESULT_SUCCESS, 200,
		PackedStringArray(), github_body)
	_expect(checker.get("latest_version") == "0.6.3",
		"GitHub 0.6.3 wins over stale mirror 0.6.2")
	_expect(str(checker.get("latest_asset_name")) == "CartSlopGP_v0.6.3_windows.zip",
		"GitHub asset is used")

	# 2. A genuinely newer mirror must win.
	checker.set("_server_candidate", {
		"version": "0.7.0", "base": "http://pi:42777",
		"asset_name": "CartSlopGP_v0.7.0_windows.zip",
		"asset_path": "", "release_url": "",
	})
	checker.call("_on_check_completed", HTTPRequest.RESULT_SUCCESS, 200,
		PackedStringArray(), github_body)
	_expect(checker.get("latest_version") == "0.7.0",
		"newer mirror 0.7.0 wins over GitHub 0.6.3")
	_expect(str(checker.get("latest_asset_url")).contains("/updates/"),
		"mirror asset URL is built from the manifest")

	# 3. GitHub offline, mirror still offers a valid update.
	checker.set("_server_candidate", {
		"version": "0.6.5", "base": "http://pi:42777",
		"asset_name": "CartSlopGP_v0.6.5_windows.zip",
		"asset_path": "", "release_url": "",
	})
	checker.call("_on_check_completed", HTTPRequest.RESULT_CANT_CONNECT, 0,
		PackedStringArray(), PackedByteArray())
	_expect(checker.get("status") == "available",
		"mirror keeps updates available when GitHub is offline")
	_expect(checker.get("latest_version") == "0.6.5",
		"mirror version is offered")

	checker.free()
	if _failures == 0:
		print("UPDATE MIRROR TESTS: all passed")
	else:
		print("UPDATE MIRROR TESTS: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)
