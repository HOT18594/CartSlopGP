extends SceneTree
## Dev check: a room that is already playing rejects new code joins.

var _reason: String = ""

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var net: Node = root.get_node("Network")
	net.set_relay_server("192.168.1.22:42777")
	net.join_failed.connect(func(text: String) -> void: _reason = text)
	net.join_game(OS.get_environment("CODE"))
	await create_timer(8.0).timeout
	print("JOIN_STARTED reason=", _reason)
	var ok: bool = _reason.to_lower().contains("already started")
	print("JOIN_STARTED: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
