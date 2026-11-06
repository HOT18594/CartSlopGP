extends Node
## Dev check: singleplayer pauses, multiplayer keeps the world running.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var packed: PackedScene = load("res://scenes/ui/pause_menu.tscn") as PackedScene
	var menu: Node = packed.instantiate()
	add_child(menu)
	await get_tree().process_frame
	var root: Node = menu.get_node("Root")

	Network.is_host = true
	root.call("open")
	var multiplayer_paused: bool = get_tree().paused
	root.call("close")
	Network.is_host = false

	root.call("open")
	var single_paused: bool = get_tree().paused
	root.call("close")

	print("PAUSE_TEST multiplayer_paused=", multiplayer_paused, " single_paused=", single_paused)
	var ok: bool = not multiplayer_paused and single_paused
	print("PAUSE_TEST: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
