extends SceneTree
## Exercises tier 2 (download) against the real release. Local only.

var _checker: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_checker = load("res://scripts/systems/update_checker.gd").new()
	root.add_child(_checker)
	_checker.check_finished.connect(_on_check)
	_checker.download_finished.connect(_on_download)
	_checker.download_failed.connect(_on_fail)
	_checker.check_for_updates()


func _on_check(_available: bool) -> void:
	print("CHECK status=", _checker.status, " asset=", _checker.latest_asset_name)
	_checker.download_update()


func _on_download(path: String) -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var reader := ZIPReader.new()
	var listed: PackedStringArray = []
	if reader.open(path) == OK:
		listed = reader.get_files()
		reader.close()
	print("DOWNLOAD ok path=", path, " bytes=", bytes.size(), " files=", listed)
	quit(0)


func _on_fail(reason: String) -> void:
	print("DOWNLOAD failed: ", reason)
	quit(1)
