extends SceneTree
## Dev-only: verify the Pi update manifest path. Run with
## CARTSLOP_UPDATE_SERVER=http://127.0.0.1:43777.

var _checker: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_checker = load("res://scripts/systems/update_checker.gd").new()
	root.add_child(_checker)
	_checker.check_finished.connect(_on_done)
	_checker.check_for_updates()


func _on_done(available: bool) -> void:
	print("PI_UPDATE available=", available, " status=", _checker.status,
		" latest=", _checker.latest_version, " asset=", _checker.latest_asset_name,
		" url=", _checker.latest_asset_url, " err=", _checker.last_error)
	var ok: bool = available and str(_checker.latest_version) == "0.6.1" \
		and str(_checker.latest_asset_url).contains("/updates/")
	quit(0 if ok else 1)
