extends SceneTree

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("user://updates")
	var file := FileAccess.open("user://updates/fake.zip", FileAccess.WRITE)
	if file == null:
		print("cannot write fake zip")
	else:
		file.store_string("x")
		file.close()
	var config := ConfigFile.new()
	config.set_value("download", "path", "user://updates/fake.zip")
	config.set_value("download", "version", "9.9.9")
	print("save err=", config.save("user://updates/download.cfg"))
	print("exists=", FileAccess.file_exists("user://updates/download.cfg"), " zip=", FileAccess.file_exists("user://updates/fake.zip"))
	var checker: Node = load("res://scripts/systems/update_checker.gd").new()
	root.add_child(checker)
	print("state path=", checker.downloaded_zip_path(), " version=", checker.downloaded_version(), " has=", checker.has_downloaded_update("9.9.9"))
	DirAccess.remove_absolute("user://updates/fake.zip")
	DirAccess.remove_absolute("user://updates/download.cfg")
	checker.free()
	quit(0)
