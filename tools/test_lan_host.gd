extends Node
## Dev check: host a LAN room and wait for a nearby client to find it.

func _ready() -> void:
	Network.host_started.connect(func(code: String) -> void:
		print("LAN_HOST_READY code=", code, " mode=", Network.connection_mode,
			" state=", Network.room_state))
	Network.host_failed.connect(func(reason: String) -> void:
		print("LAN_HOST_FAILED=", reason)
		get_tree().quit(1))
	Network.peers_changed.connect(func() -> void:
		print("LAN_HOST_PEERS=", Network.peer_count()))
	Network.host_game("lan")
	await get_tree().create_timer(24.0).timeout
	print("LAN_HOST_DONE peers=", Network.peer_count())
	get_tree().quit(0)
