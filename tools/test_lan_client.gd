extends Node
## Dev check: discover a LAN room (no typed IP) and join it.

func _ready() -> void:
	Network.join_succeeded.connect(func() -> void:
		print("LAN_CLIENT_JOINED id=", multiplayer.get_unique_id(),
			" peers=", multiplayer.get_peers())
		get_tree().quit(0))
	Network.join_failed.connect(func(reason: String) -> void:
		print("LAN_CLIENT_FAILED=", reason)
		get_tree().quit(1))
	var rooms: Array = await Network.scan_lan_rooms(2.5)
	print("LAN_SCAN_ROOMS=", rooms.size(), " ROOMS=", rooms)
	if rooms.is_empty():
		print("LAN_CLIENT_NO_ROOMS")
		get_tree().quit(1)
		return
	var room: Dictionary = rooms[0] as Dictionary
	print("LAN_CLIENT_PICK name=", room.get("name", ""), " players=", room.get("players", 0))
	Network.join_lan_room(room)
	await get_tree().create_timer(12.0).timeout
	if Network.is_client:
		print("LAN_CLIENT_STILL_CONNECTED peers=", Network.peer_count())
		get_tree().quit(0)
	print("LAN_CLIENT_TIMEOUT")
	get_tree().quit(1)
