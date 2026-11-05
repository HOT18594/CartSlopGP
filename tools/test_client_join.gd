extends Node
## Dev check: join the host through the local Pi relay tunnel by room code.


func _ready() -> void:
	var code: String = ""
	for i in 60:
		if FileAccess.file_exists("user://host_code.txt"):
			var file := FileAccess.open("user://host_code.txt", FileAccess.READ)
			if file != null:
				code = file.get_as_text().strip_edges()
				file.close()
			if code != "":
				break
		await get_tree().create_timer(0.2).timeout
	print("CLIENT_CODE=", code)
	if code == "":
		get_tree().quit(1)
		return
	Network.set_relay_server("127.0.0.1:42777")
	Network.join_succeeded.connect(func() -> void:
		print("CLIENT_JOIN_SUCCEEDED")
		get_tree().quit(0))
	Network.join_failed.connect(func(reason: String) -> void:
		print("CLIENT_JOIN_FAILED=", reason)
		get_tree().quit(1))
	Network.join_game(code)
	await get_tree().create_timer(14.0).timeout
	print("CLIENT_TIMEOUT")
	get_tree().quit(1)
