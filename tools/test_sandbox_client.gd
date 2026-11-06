extends Node
## Dev check: join sandbox through the Pi and stay in the scene.

func _ready() -> void:
	var code: String = ""
	for i in 80:
		var file := FileAccess.open("user://host_code.txt", FileAccess.READ)
		if file != null:
			code = file.get_as_text().strip_edges()
			file.close()
		if code != "":
			break
		await get_tree().create_timer(0.2).timeout
	print("SB_CLIENT_CODE=", code)
	Network.set_relay_server("192.168.1.22:42777")
	Network.join_succeeded.connect(func() -> void:
		print("SB_CLIENT_JOINED")
		await get_tree().create_timer(16.0).timeout
		print("SB_CLIENT_DONE scene=", get_tree().current_scene.name if get_tree().current_scene else "none")
		get_tree().quit(0))
	Network.join_failed.connect(func(reason: String) -> void:
		print("SB_CLIENT_FAILED=", reason)
		get_tree().quit(1))
	Network.join_game(code)
	await get_tree().create_timer(20.0).timeout
	print("SB_CLIENT_TIMEOUT")
	get_tree().quit(1)
