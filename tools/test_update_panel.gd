extends SceneTree
## Dev check: the update dialog opens, and skips auto-download when no asset.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var uc: Node = root.get_node("UpdateChecker")
	uc.status = "available"
	uc.latest_version = "9.9.9"
	uc.latest_asset_url = ""
	var panel: Node = (load("res://scenes/ui/update_panel.tscn") as PackedScene).instantiate()
	root.add_child(panel)
	await process_frame
	panel.call("open")
	await process_frame
	print("UPDATE_PANEL visible=", panel.visible, " downloading=", uc.is_downloading())
	var ok: bool = panel.visible and not uc.is_downloading()
	print("UPDATE_PANEL: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
