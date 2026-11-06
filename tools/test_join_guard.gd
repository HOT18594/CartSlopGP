extends SceneTree
## Dev check: IP addresses / old address codes are rejected before any network.

var _reason: String = ""

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var net: Node = root.get_node("Network")
	net.join_failed.connect(func(text: String) -> void: _reason = text)
	net.join_game("192.168.1.4:8910")
	await process_frame
	print("JOIN_GUARD reason=", _reason)
	var ok: bool = _reason.contains("5-letter")
	print("JOIN_GUARD: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
