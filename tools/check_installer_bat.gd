extends SceneTree
## Verifies the generated update_install.bat template and clears test files.

func _init() -> void:
	var checker: Node = load("res://scripts/systems/update_checker.gd").new()
	root.add_child(checker)
	var ok: bool = checker.call("_write_installer", "user://test_install.bat",
		"C:/Games/CartSlopGP", "C:/Users/ethan/AppData/Roaming/CartSlopGP/updates/staging",
		"CartSlopGP.exe")
	print("BAT written=", ok)
	if ok:
		print(FileAccess.get_file_as_string("user://test_install.bat"))
	DirAccess.remove_absolute("user://test_install.bat")
	DirAccess.remove_absolute("user://updates/CartSlopGP_v0.1.0_windows.zip")
	print("cleanup done")
	checker.free()
	quit(0)
