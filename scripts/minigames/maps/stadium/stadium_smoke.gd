extends SceneTree
## Headless smoke boot for the STADIUM CIRCUIT race map.
##
## Run with:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot_project \
##       --script res://scripts/minigames/maps/stadium/stadium_smoke.gd
##
## It selects the stadium preset, boots the real race scene for 120 frames and
## exits. The caller greps the output for SCRIPT ERROR lines; the theme's own
## build line, the woodland report and the clearance line are printed by the
## live scene, so a regression in any of them is visible without a window.

const MAP_ID: String = "stadium"
const FRAMES: int = 120


func _initialize() -> void:
	# Autoloads load their saved settings on the first frame; wait for that so
	# the test map is not overwritten by the profile's saved pick.
	await process_frame
	var settings: Node = root.get_node_or_null("GameSettings")
	if settings != null:
		settings.set("selected_map", MAP_ID)
	var packed: PackedScene = load("res://scenes/minigames/grass_race.tscn")
	if packed == null:
		push_error("stadium_smoke: race scene did not load")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	for _frame in FRAMES:
		await process_frame
	print("STADIUM SMOKE: booted %d frames" % FRAMES)
	quit(0)
