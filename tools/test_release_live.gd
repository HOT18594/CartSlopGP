extends SceneTree
## Dev-only: check the real GitHub release feed the shipped updater uses.

var _checker: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_checker = load("res://scripts/systems/update_checker.gd").new()
	root.add_child(_checker)
	_checker.check_finished.connect(_on_done)
	_checker.check_for_updates()


func _on_done(available: bool) -> void:
	print("LIVE status=", _checker.status, " local=", _checker.local_version(),
		" latest=", _checker.latest_version, " asset=", _checker.latest_asset_name,
		" err=", _checker.last_error, " available=", available)
	quit(0)
