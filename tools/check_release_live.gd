extends SceneTree
## Live check against the real repo. Run:
##   godot --headless --path . --script tools/check_release_live.gd

var _checker: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_checker = load("res://scripts/systems/update_checker.gd").new()
	root.add_child(_checker)
	_checker.check_finished.connect(_on_done)
	_checker.check_for_updates()


func _on_done(available: bool) -> void:
	print("LIVE status=", _checker.status,
		" local=", _checker.local_version(),
		" latest=", _checker.latest_version,
		" asset=", _checker.latest_asset_name,
		" asset_url=", _checker.latest_asset_url != "",
		" available=", available,
		" error=", _checker.last_error)
	quit(0)
