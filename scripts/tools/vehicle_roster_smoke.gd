extends SceneTree
## Verifies that every curated chassis is selectable, tunable and renderable in racing.

const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")


func _initialize() -> void:
	var failures: int = 0
	var entries: Array[Dictionary] = Catalog.racing_all()
	var ids: Dictionary = {}
	if entries.size() != Catalog.VEHICLES.size() + Catalog.RACING_VEHICLES.size():
		failures += 1
		push_error("ROSTER: racing catalog does not contain every vehicle")
	if str(entries[0].get("id", "")) != Catalog.DEFAULT_ID:
		failures += 1
		push_error("ROSTER: shopping cart must remain the default")
	for entry: Dictionary in entries:
		var id: String = str(entry.get("id", ""))
		if id == "" or ids.has(id) or not Catalog.is_racing_choice(id):
			failures += 1
			push_error("ROSTER: invalid or duplicate id " + id)
		ids[id] = true
		if not ResourceLoader.exists(str(entry.get("scene", ""))):
			failures += 1
			push_error("ROSTER: missing model for " + id)
		var composed: Dictionary = Catalog.compose_racing_entry(id,
			Catalog.default_allocation())
		if str(composed.get("id", "")) != id:
			failures += 1
			push_error("ROSTER: composition failed for " + id)
			continue
		for key: String in ["max_speed", "mass", "grip", "steering"]:
			var value: float = float(composed.get(key, 0.0))
			if not is_finite(value) or value <= 0.0:
				failures += 1
				push_error("ROSTER: invalid %s for %s" % [key, id])
		var visual: Node3D = VehicleVisual.build(composed)
		if visual == null:
			failures += 1
		else:
			visual.free()
	if Catalog.is_racing_choice("../vehicle") or Catalog.is_racing_choice(""):
		failures += 1
		push_error("ROSTER: invalid id accepted")
	print("VEHICLE_ROSTER_SMOKE: %d vehicles, %d failure(s)" % [entries.size(), failures])
	quit(failures)
