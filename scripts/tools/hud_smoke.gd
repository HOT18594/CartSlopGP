extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var gs: Node = root.get_node_or_null("/root/GameSettings")
	var saved_scale: float = float(gs.get("hud_scale")) if gs != null else 1.0
	if gs != null:
		gs.set("hud_scale", 1.0)
	var hud: Control = load("res://scenes/ui/hud.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	hud.set_race_position(6, 8)
	hud.set_lap(1, 3)
	hud.set_race_time(59.9999)
	_check(hud._plaque_time.text == "1:00.000", "Race clock must carry rounded milliseconds into the next minute")
	hud.set_best_lap(42.5)
	hud.set_last_lap(41.9, -0.6)
	var entries: Array[Dictionary] = []
	for index in 8:
		entries.append({"name": "Driver %d" % index, "progress": 800.0 - index * 20.0,
			"local": index == 6, "color": Color.CYAN})
	hud.set_standings(entries)
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

	# Wrong-way alert banner contract: hidden by default, fits viewport when active.
	_check(not hud._wrong_way_banner.visible, "Wrong-way banner must stay hidden by default")
	hud.set_wrong_way(true)
	_check(hud._wrong_way_banner.visible, "set_wrong_way(true) must show the wrong-way banner")

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
		_check(not hud._standings_panel.get_global_rect().intersects(hud._speed_gauge.get_global_rect()),
			"LiveStandings must not overlap SpeedGauge at %s" % viewport_size)

	hud.set_wrong_way(false)
	_check(not hud._wrong_way_banner.visible, "set_wrong_way(false) must hide the wrong-way banner")

	# Full 13-cart field at 135% HUD scale on 1280x720 must never overlap SpeedGauge.
	var crowded_entries: Array[Dictionary] = []
	for index in 13:
		crowded_entries.append({"name": "Racer %d" % index, "progress": 1200.0 - index * 25.0,
			"local": index == 11, "color": Color.ORANGE})
	hud.size = Vector2(1280, 720)
	if gs != null:
		gs.set("hud_scale", 1.35)
	hud.set_standings(crowded_entries)
	hud._apply_display_settings()
	await process_frame
	var standings_rect: Rect2 = hud._standings_panel.get_global_rect()
	var gauge_rect: Rect2 = hud._speed_gauge.get_global_rect()
	_check(not standings_rect.intersects(gauge_rect) and standings_rect.end.y <= gauge_rect.position.y,
		"13-entry LiveStandings (%s) overlapped SpeedGauge (%s) at 1.35x scale" % [standings_rect, gauge_rect])
	for child: Node in hud.get_children():
		if child is Control and (child as Control).visible:
			var rect: Rect2 = (child as Control).get_global_rect()
			_check(rect.position.x >= -1.0 and rect.position.y >= -1.0
				and rect.end.x <= 1281.0 and rect.end.y <= 721.0,
				"1.35x HUD cluster %s exceeds 1280x720: %s" % [child.name, rect])

	_check(hud._dial_max_kmh >= 20.0, "Speedometer must keep a positive dial range")
	hud._boost_meter.ratio = -1.0
	_check(hud._boost_meter.ratio == 0.0, "Boost meter must clamp depletion")
	if gs != null:
		gs.set("hud_scale", saved_scale)
	hud.queue_free()
	await process_frame
	print("HUD_SMOKE: %s" % ("PASS" if _failures == 0 else "%d failures" % _failures))
	quit(0 if _failures == 0 else 1)
