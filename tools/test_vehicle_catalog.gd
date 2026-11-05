extends SceneTree
## Validates the per-vehicle data and audio. Run:
##   godot --headless --path . --script tools/test_vehicle_catalog.gd

const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")

var _failures: int = 0


func _init() -> void:
	for entry: Dictionary in Catalog.all():
		var id: String = str(entry.get("id", "?"))
		var mass: float = float(entry.get("mass", 0.0))
		var top_speed: float = float(entry.get("max_speed", 0.0))
		var loop: String = str(entry.get("loop_sound", ""))
		var engine_power: float = float(entry.get("engine_power", 0.0))
		_expect(mass > 0.0, "%s has mass" % id)
		_expect(top_speed > 0.0, "%s has top speed" % id)
		_expect(float(entry.get("skid_width", 0.0)) > 0.0, "%s has skid width" % id)
		_expect(ResourceLoader.exists(loop), "%s loop exists (%s)" % [id, loop])
		if ResourceLoader.exists(loop):
			var stream: AudioStream = load(loop) as AudioStream
			_expect(stream != null and stream.get_length() > 1.0, "%s loop length" % id)
		if engine_power > 0.0:
			var accel: float = engine_power * 1200.0 / mass
			print("  %-16s mass %5.0f kg  top %4.1f m/s  accel %5.1f m/s2" % [id, mass, top_speed, accel])
			_expect(accel > 4.0 and accel < 45.0, "%s acceleration sane" % id)
		else:
			_expect(bool(entry.get("has_engine", true)) == false, "%s has no engine" % id)
			print("  %-16s mass %5.0f kg  top %4.1f m/s  push %5.1f m/s2" % [
				id, mass, top_speed, float(entry.get("push_accel", 0.0))])
	if _failures == 0:
		print("VEHICLE CATALOG TESTS: all passed")
	else:
		printerr("VEHICLE CATALOG TESTS: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _expect(value: bool, label: String) -> void:
	if value:
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)
