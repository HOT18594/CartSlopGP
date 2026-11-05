extends SceneTree
## Verifies the generated update_install.bat uses real Windows paths.

func _init() -> void:
	var checker: Node = load("res://scripts/systems/update_checker.gd").new()
	root.add_child(checker)
	var stage: String = ProjectSettings.globalize_path("user://updates/staging")
	print("STAGE_WINDOWS=", stage)
	var ok: bool = checker.call("_write_installer", "user://test_install.bat",
		"C:/Games/CartSlopGP", stage, "CartSlopGP.exe")
	print("BAT written=", ok)
	if ok:
		print(FileAccess.get_file_as_string("user://test_install.bat"))
	DirAccess.remove_absolute("user://test_install.bat")
	checker.free()
	quit(0)
