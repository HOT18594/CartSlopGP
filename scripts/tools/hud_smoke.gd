extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var hud: Control = load("res://scenes/ui/hud.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	hud.set_race_position(6, 8)
	hud.set_lap(1, 3)
	hud.set_race_time(59.9999)
	_check(hud._plaque_time.text == "1:00.000", "Race clock must carry rounded milliseconds into the next minute")
	var entries: Array[Dictionary] = []
	for index in 8:
		entries.append({"name": "Driver %d" % index, "progress": 800.0 - index * 20.0,
			"local": index == 6, "color": Color.CYAN})
	hud.set_standings(entries)
	## The HUD gives every cart a row now (STANDINGS_MAX_ROWS is 12). The old
	## five-row cap deleted the back of the field, so this asserts the new
	## contract instead of the retired one.
	_check(hud._standings_rows.get_child_count() == 8, "Live standings must give every cart a row")
	var local_row: Dictionary = hud._standings_row_cache[6]
	_check((local_row["name"] as Label).text.ends_with("YOU"), "Standings must show the local cart in its real slot")
	_check((local_row["place"] as Label).text == "7", "Pinned local row must preserve its actual race position")
	var first_row: Node = hud._standings_rows.get_child(0)
	entries[0]["progress"] = 805.0
	hud.set_standings(entries)
	_check(hud._standings_rows.get_child(0) == first_row, "Standings updates must reuse row controls")
	var empty_entries: Array[Dictionary] = []
	hud.set_standings(empty_entries)
	_check(not hud._standings_panel.visible, "An empty standings feed must clear stale standings")
	hud.set_standings(entries)
	for viewport_size: Vector2 in [Vector2(1280, 720), Vector2(960, 540)]:
		hud.size = viewport_size
		hud._apply_display_settings()
		await process_frame
		for child: Node in hud.get_children():
			if child is Control and (child as Control).visible:
				var rect: Rect2 = (child as Control).get_global_rect()
				_check(rect.position.x >= -1.0 and rect.position.y >= -1.0
					and rect.end.x <= viewport_size.x + 1.0 and rect.end.y <= viewport_size.y + 1.0,
					"HUD cluster %s exceeds viewport %s: %s" % [child.name, viewport_size, rect])
	## The gauge no longer exposes max_speed_kmh; the dial top lives on the HUD
	## as _dial_max_kmh and is recomputed from the cart each frame. Assert the
	## invariant the gauge actually relies on: never a dial range below 20.
	_check(hud._dial_max_kmh >= 20.0, "Speedometer must keep a positive dial range")
	hud._boost_meter.ratio = -1.0
	_check(hud._boost_meter.ratio == 0.0, "Boost meter must clamp depletion")
	hud.queue_free()
	await process_frame
	print("HUD_SMOKE: %s" % ("PASS" if _failures == 0 else "%d failures" % _failures))
	quit(0 if _failures == 0 else 1)
