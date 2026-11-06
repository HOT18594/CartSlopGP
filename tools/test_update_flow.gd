extends Node
## Headless updater flow test. Drives the REAL update panel against a local
## mock mirror (tools/mock_update_server.py).
##
##   SCENARIO=happy  manifest + zip      -> panel must reach RESTART & UPDATE
##   SCENARIO=stall  zip stalls mid-body -> TRY AGAIN (never greyed forever)
##
## Set CARTSLOP_UPDATE_SERVER before launching Godot.

var _panel: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var scenario: String = OS.get_environment("SCENARIO")
	if scenario == "":
		scenario = "happy"
	var checker: Node = get_node("/root/UpdateChecker")
	# Drop any zips/state left by a previous scenario so the download actually
	# starts (an existing zip for the version short-circuits to RESTART).
	_clear_update_state(checker)
	checker.status = "available"
	checker.latest_version = "9.9.9"
	if scenario == "stall":
		checker.latest_asset_name = "CartSlopGP_stall_windows.zip"
		checker.latest_asset_url = _base() + "/updates/CartSlopGP_stall_windows.zip"
	else:
		checker.latest_asset_name = "CartSlopGP_v9.9.9_windows.zip"
		checker.latest_asset_url = _base() + "/updates/CartSlopGP_v9.9.9_windows.zip"
	_panel = (load("res://scenes/ui/update_panel.tscn") as PackedScene).instantiate()
	add_child(_panel)
	_panel.call("open")
	print("FLOW scenario=%s opened downloading=%s" % [scenario, checker.is_downloading()])
	_watchdog()
	_run(scenario, checker)


func _base() -> String:
	var raw: String = OS.get_environment("CARTSLOP_UPDATE_SERVER").strip_edges()
	return raw if raw != "" else "http://127.0.0.1:42999"


func _clear_update_state(checker: Node) -> void:
	checker._downloaded_file = ""
	checker._downloaded_version = ""
	var state: String = "user://updates/download.cfg"
	if FileAccess.file_exists(state):
		DirAccess.remove_absolute(state)
	var dir := DirAccess.open("user://updates")
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.to_lower().ends_with(".zip"):
			DirAccess.remove_absolute("user://updates/" + entry)
		entry = dir.get_next()
	dir.list_dir_end()


func _watchdog() -> void:
	await get_tree().create_timer(90.0).timeout
	print("FLOW watchdog timeout")
	get_tree().quit(2)


func _run(scenario: String, checker: Node) -> void:
	var finished: Array = [false]
	var failed: Array = [""]
	checker.download_finished.connect(func(_p: String) -> void: finished[0] = true)
	checker.download_failed.connect(func(reason: String) -> void:
		finished[0] = true
		failed[0] = reason)
	var waited: float = 0.0
	while not finished[0] and waited < 70.0:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
		if int(waited) % 5 == 0:
			print("FLOW hb t=%.0f downloading=%s" % [waited, checker.is_downloading()])
	# Give the panel's self-heal loop a beat to promote the dialog.
	await get_tree().create_timer(1.5).timeout
	var primary: Button = _panel.get_node("%PrimaryButton")
	var notes: Label = _panel.get_node("%NotesLabel")
	print("FLOW waited=%.0fs finished=%s failed=%s button=%s disabled=%s" % [
		waited, finished[0], failed[0], primary.text, primary.disabled])
	var ok: bool = false
	if scenario == "happy":
		ok = finished[0] and failed[0] == "" \
			and primary.text == "RESTART & UPDATE" and not primary.disabled \
			and checker.has_downloaded_update("9.9.9")
	else:
		ok = finished[0] and failed[0] == "stalled_connection" \
			and primary.text == "TRY AGAIN" and not primary.disabled
	print("FLOW: %s (%s)" % ["PASS" if ok else "FAIL", notes.text])
	get_tree().quit(0 if ok else 1)
