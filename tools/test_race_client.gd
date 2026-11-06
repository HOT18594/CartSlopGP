extends Node
## Dev-only: join the hosted Meadow Loop room and let the race scene load.

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
	print("RACE_CLIENT_CODE=", code)
	if code == "":
		get_tree().quit(1)
		return
	Network.set_relay_server("127.0.0.1:42777")
	Network.join_succeeded.connect(func() -> void:
		print("RACE_CLIENT_JOINED"))
	Network.join_failed.connect(func(reason: String) -> void:
		print("RACE_CLIENT_FAILED=", reason)
		get_tree().quit(1))
	Network.join_game(code)
	await get_tree().create_timer(24.0).timeout
	print("RACE_CLIENT_DONE")
	get_tree().quit(0)
