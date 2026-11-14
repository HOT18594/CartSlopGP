extends SceneTree
## Headless smoke boot for the Dockyard Quay race map.
##
## Run with:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot_project \
##       --script res://scripts/minigames/maps/dockyard/dockyard_smoke.gd
##
## It selects the dockyard preset, boots the real race scene for 150 frames and
## exits. The caller greps the output for SCRIPT ERROR lines; the theme's own
## build line and barrier-clearance report are printed by the live scene, so a
## regression in either is visible without a window.

const MAP_ID: String = "dockyard"
const FRAMES: int = 150


func _initialize() -> void:
	# Autoloads load their saved settings on the first frame; wait for that so
	# the test map is not overwritten by the profile's saved stadium pick.
	await process_frame
	var settings: Node = root.get_node_or_null("GameSettings")
	if settings != null:
		settings.set("selected_map", MAP_ID)
	var packed: PackedScene = load("res://scenes/minigames/grass_race.tscn")
	if packed == null:
		push_error("dockyard_smoke: race scene did not load")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	for _frame in FRAMES:
		await process_frame
	print("DOCKYARD SMOKE: booted %d frames" % FRAMES)
	quit(0)
