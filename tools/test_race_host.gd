extends Node
## Dev-only: host a Meadow Loop race through the Pi and wait for a peer.

func _ready() -> void:
	var relay := OS.get_environment("CARTSLOP_RELAY")
	if relay != "":
		Network.set_relay_server(relay)
	Network.host_started.connect(_on_host)
	Network.host_failed.connect(func(reason: String) -> void:
		print("RACE_HOST_FAILED=", reason)
		get_tree().quit(1))
	Network.host_game("online")
	await get_tree().create_timer(30.0).timeout
	print("RACE_HOST_DONE")
	get_tree().quit(0)


func _on_host(code: String) -> void:
	print("RACE_HOST_CODE=", code)
	var file := FileAccess.open("user://host_code.txt", FileAccess.WRITE)
	if file != null:
		file.store_string(code)
		file.close()
	# Give the client time to discover and join the room.
	for i in 40:
		if Network.peer_count() > 1:
			break
		await get_tree().create_timer(0.5).timeout
	print("RACE_HOST_PEERS=", Network.peer_count())
	Network.start_game(Network.RACE_SCENE, GameSettings.GAME_MINIGAMES)
