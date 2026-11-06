extends Node
## Dev check: host sandbox through the Pi and start after a peer joins.

func _ready() -> void:
	Network.host_started.connect(_on_host)
	Network.host_failed.connect(func(reason: String) -> void:
		print("SB_HOST_FAILED=", reason)
		get_tree().quit(1))
	Network.host_game("pi")
	await get_tree().create_timer(30.0).timeout
	get_tree().quit(0)


func _on_host(code: String) -> void:
	print("SB_HOST_CODE=", code)
	var file := FileAccess.open("user://host_code.txt", FileAccess.WRITE)
	if file != null:
		file.store_string(code)
		file.close()
	for i in 60:
		if Network.peer_count() > 1:
			break
		await get_tree().create_timer(0.5).timeout
	print("SB_HOST_PEERS=", Network.peer_count())
	await get_tree().create_timer(1.0).timeout
	Network.start_game(Network.GAME_SCENE, GameSettings.GAME_SANDBOX)
	await get_tree().create_timer(3.0).timeout
	print("SB_HOST_READY=", Network.scene_ready_peers)
	await get_tree().create_timer(15.0).timeout
	print("SB_HOST_DONE")
