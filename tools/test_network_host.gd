extends Node
## Dev check: Network.host_game() with the local Pi server and TCP tunnel.

var _started: bool = false


func _ready() -> void:
	Network.host_started.connect(func(code: String) -> void:
		_started = true
		print("HOST_STARTED=", code, " RELAY=", Network.relay_active,
			" TUNNEL_TOKEN=", Network.relay_tunnel_token.length()))
	Network.host_failed.connect(func(reason: String) -> void:
		print("HOST_FAILED=", reason)
		get_tree().quit(1))
	Network.host_game("online")
	await get_tree().create_timer(2.5).timeout
	print("TUNNEL_ACTIVE_AFTER_2S=", Network.relay_tunnel_active,
		" READY=", Network.relay_tunnel_active)
	await get_tree().create_timer(2.0).timeout
	print("TUNNEL_ACTIVE_FINAL=", Network.relay_tunnel_active)
	get_tree().quit(0 if _started else 1)
