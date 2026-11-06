extends Node
## Dev check: host an ENet server through the local Pi relay tunnel.


func _ready() -> void:
	# Optional: point the test at a remote Pi instead of a local server.
	var relay := OS.get_environment("CARTSLOP_RELAY")
	if relay != "":
		Network.set_relay_server(relay)
	Network.host_started.connect(func(code: String) -> void:
		var file := FileAccess.open("user://host_code.txt", FileAccess.WRITE)
		if file != null:
			file.store_string(Network.relay_room_code)
			file.close()
		print("HOST_CODE=", Network.relay_room_code, " TUNNEL_TOKEN=",
			Network.relay_tunnel_token.length()))
	Network.host_failed.connect(func(reason: String) -> void:
		print("HOST_FAILED=", reason)
		get_tree().quit(1))
	Network.peers_changed.connect(func() -> void:
		print("HOST_PEERS=", Network.peer_count()))
	Network.host_game("online")
	await get_tree().create_timer(22.0).timeout
	print("HOST_DONE TUNNEL_ACTIVE=", Network.relay_tunnel_active)
	get_tree().quit(0)
