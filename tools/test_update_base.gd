extends SceneTree
## Dev-only: confirm the updater prefers the Cart Slop Pi mirror.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var checker: Node = load("res://scripts/systems/update_checker.gd").new()
	root.add_child(checker)
	await process_frame
	var base: String = str(checker.call("_configured_server_base"))
	print("UPDATE_BASE=", base)
	quit(0 if base.contains("42777") else 1)
