extends SceneTree
## Dev-only: prove the auto-updater can unpack a release zip.
## Run with CARTSLOP_TEST_ZIP pointing at a built game zip.

func _init() -> void:
	var zip: String = OS.get_environment("CARTSLOP_TEST_ZIP").strip_edges()
	if zip == "" or not FileAccess.file_exists(zip):
		print("EXTRACT skipped (set CARTSLOP_TEST_ZIP)")
		quit(0)
		return
	var checker: Node = load("res://scripts/systems/update_checker.gd").new()
	root.add_child(checker)
	var out: String = ProjectSettings.globalize_path("user://updates/test_staging")
	checker.call("_clear_directory", out)
	DirAccess.make_dir_recursive_absolute(out)
	var ok: bool = checker.call("_extract_zip", zip, out)
	var exe: bool = FileAccess.file_exists(out + "/CartSlopGP.exe")
	var pck: bool = FileAccess.file_exists(out + "/CartSlopGP.pck")
	print("EXTRACT ok=", ok, " exe=", exe, " pck=", pck, " dir=", out)
	checker.call("_clear_directory", out)
	checker.free()
	quit(0 if ok and exe and pck else 1)
