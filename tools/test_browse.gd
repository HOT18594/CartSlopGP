extends SceneTree
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var net: Node = root.get_node("Network")
	net.set_relay_server("192.168.1.22:42777")
	var rooms: Array = await net.fetch_lobbies()
	print("BROWSE_ROOMS=", rooms)
	quit(0 if not rooms.is_empty() else 1)
