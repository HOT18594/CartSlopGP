extends SceneTree

var _checker: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_checker = load("res://scripts/systems/update_checker.gd").new()
	root.add_child(_checker)
	_checker.github_owner = "godotengine"
	_checker.github_repo = "godot"
	_checker.update_check_timeout = 10.0
	_checker.check_finished.connect(_on_done)
	_checker.check_for_updates()


func _on_done(available: bool) -> void:
	print("NET status=", _checker.status, " latest=", _checker.latest_version,
		" asset=", _checker.latest_asset_name, " err=", _checker.last_error,
		" available=", available, " local=", _checker.local_version())
	quit(0)
