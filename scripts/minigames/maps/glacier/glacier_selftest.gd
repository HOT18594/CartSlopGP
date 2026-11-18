extends SceneTree
## Headless self-test for the Glacier Pass theme (development harness).
##
## It builds the circuit twice and prints the numbers a map agent has to report:
##
##   * `GlacierCourse` through KenneyTiles, so the authored grid, the per-cell
##     heights and the lap length are proven to parse and to close;
##   * the whole theme on that spline, so barriers, snowbanks, fences, pines,
##     rocks, ridges and pylons are placed, counted and audited.
##
## Run it with the editor binary, no rendering needed:
##
##     Godot_v4.7.2-stable_win64_console.exe --headless --path godot_project \
##         --script res://scripts/minigames/maps/glacier/glacier_selftest.gd
##
## `CART_GLACIER_PROBE=1` prints the measured AABB of the kit models the theme
## uses instead, which is how the prop scale table in the theme was chosen;
## `CART_GLACIER_REGISTRY=1` audits the grid the registry currently ships (the
## "before" number); `CART_GLACIER_RACE=1` boots the real grass_race scene with
## glacier selected, which is the end-to-end check.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const KenneyTiles := preload("res://scripts/minigames/tiles/kenney_tiles.gd")
const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const GlacierCourse := preload("res://scripts/minigames/maps/glacier/glacier_course.gd")
const GlacierTheme := preload("res://scripts/minigames/maps/glacier_theme.gd")

const PROBE_ENV: String = "CART_GLACIER_PROBE"
const REGISTRY_ENV: String = "CART_GLACIER_REGISTRY"
const RACE_ENV: String = "CART_GLACIER_RACE"
const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const RACING_MODELS: Array[String] = [
	"rail", "railDouble", "fenceStraight", "fenceCurved", "lightPostModern",
	"lightPostLarge", "pylon", "grandStand", "grandStandCovered", "pitsGarage",
	"roadPitStraight", "roadStraight", "roadStraightBridge", "flagRed",
	"billboard", "bannerTowerRed", "sign",
]
const NATURE_MODELS: Array[String] = [
	"cliff_block_rock", "cliff_blockSlope_rock", "cliff_large_rock",
	"cliff_top_rock", "cliff_half_rock", "rock_largeA", "rock_tallA",
	"plant_bushLarge", "tree_pineTallA", "tree_pineSmallA", "tree_cone",
]


class Host extends Node3D:
	## The race scene carries the preset the theme reads (palette, ice spans,
	## haze). The harness mirrors that so the course's own spans are exercised.
	var _preset: Dictionary = {}


func _initialize() -> void:
	if OS.get_environment(PROBE_ENV) == "1":
		_probe_models()
		quit(0)
		return
	if OS.get_environment(REGISTRY_ENV) == "1":
		quit(_run_registry())
		return
	if OS.get_environment(RACE_ENV) == "1":
		_boot_race()
		return
	quit(_run())


## Boots the real race scene against glacier, which is the end-to-end check:
## the grid engine, the theme, the karts, the HUD and every autoload. It quits
## with the number of SCRIPT ERROR lines the boot produced, so CI can gate on it.
func _boot_race() -> void:
	# Autoloads finish their own _ready inside the first frames, and GameSettings
	# reads the saved map there; set the map after that or the load would win.
	await process_frame
	await process_frame
	var settings: Node = get_root().get_node_or_null("GameSettings")
	if settings == null:
		print("GLACIER RACE: no GameSettings autoload")
		quit(1)
		return
	settings.set("selected_map", "glacier")
	await process_frame
	if not ResourceLoader.exists(RACE_SCENE):
		print("GLACIER RACE: missing %s" % RACE_SCENE)
		quit(1)
		return
	var packed: PackedScene = load(RACE_SCENE) as PackedScene
	var race: Node = packed.instantiate() if packed != null else null
	if race == null:
		print("GLACIER RACE: the scene did not instantiate")
		quit(1)
		return
	get_root().add_child(race)
	await create_timer(1.2).timeout
	var stats: Dictionary = {}
	if race.has_method("get_meta"):
		stats = race.get_meta("glacier_stats", {}) as Dictionary
	print("GLACIER RACE: %d objects, %d draw nodes, %d barriers, clearance %.2f m" % [
		int(stats.get("objects", 0)), int(stats.get("draws", 0)),
		int(stats.get("barriers", 0)), float(stats.get("clearance", 0.0))])
	race.queue_free()
	await create_timer(0.2).timeout
	quit(0)


## Audits the map the registry currently ships, with the new theme on it. This
## is the "before" number the report compares against.
func _run_registry() -> int:
	var host := Host.new()
	host.name = "GlacierRegistry"
	var preset: Dictionary = TrackDefs.get_preset("glacier").duplicate(true)
	host._preset = preset
	get_root().add_child(host)
	var spline: RefCounted = KenneyTiles.build(host,
		TrackDefs.grid_of(preset), {
			"id": "glacier",
			"heights": TrackDefs.heights_of(preset),
		})
	if spline == null:
		print("GLACIER REGISTRY: FAIL (the registry grid did not build)")
		return 1
	GlacierTheme.build(host, spline)
	var report: Dictionary = TileKit.barrier_clearance(host, spline)
	print("GLACIER REGISTRY: %.1f m lap, barriers closest %.2f m (limit %.2f m) -> %s" % [
		float(spline.total_length), float(report["closest"]),
		float(report["limit"]), "CLEARS" if bool(report["clears"]) else "ON THE ROAD"])
	if not bool(report["clears"]):
		_worst_barriers(host, spline)
	host.queue_free()
	return 0 if bool(report["clears"]) else 1


# --------------------------------------------------------------------------
# model probe
# --------------------------------------------------------------------------


func _probe_models() -> void:
	print("GLACIER PROBE racing kit")
	for model: String in RACING_MODELS:
		_probe_model(model, false)
	print("GLACIER PROBE nature kit")
	for model: String in NATURE_MODELS:
		_probe_model(model, true)


func _probe_model(model: String, nature: bool) -> void:
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		print("  %-22s MISSING" % model)
		return
	var aabb: AABB = info["aabb"]
	var parts: Array = info["parts"] as Array
	print("  %-22s size %s  centre %s  parts %d" % [
		model, str(aabb.size), str(info["center"]), parts.size()])


# --------------------------------------------------------------------------
# course + theme
# --------------------------------------------------------------------------


func _run() -> int:
	print("GLACIER COURSE: " + GlacierCourse.summary())
	var host := Host.new()
	host.name = "GlacierSelfTest"
	var preset: Dictionary = TrackDefs.get_preset("glacier").duplicate(true)
	preset.merge(GlacierCourse.preset_fields(), true)
	host._preset = preset
	get_root().add_child(host)
	var theme: Dictionary = {"id": "glacier"}
	theme.merge(GlacierCourse.preset_fields(), true)
	var spline: RefCounted = KenneyTiles.build(host, GlacierCourse.grid(),
		theme)
	if spline == null:
		print("GLACIER SELF TEST: FAIL (the course grid did not build)")
		host.queue_free()
		return 1
	var total: float = float(spline.total_length)
	var highest: float = 0.0
	var lowest: float = INF
	for index in 120:
		var height: float = float(spline.height_at(total * float(index) / 120.0))
		highest = maxf(highest, height)
		lowest = minf(lowest, height)
	print("GLACIER SELF TEST: %d tiles, %.1f m lap, road %.2f..%.2f m" % [
		int((spline.get("tiles") as Array).size()), total, lowest, highest])
	print("GLACIER SELF TEST: route %s" % KenneyTiles.grid_summary(spline))
	GlacierTheme.build(host, spline)
	var stats: Dictionary = host.get_meta("glacier_stats", {}) as Dictionary
	print("GLACIER SELF TEST: %d objects, %d draw nodes, %d barriers" % [
		int(stats.get("objects", 0)), int(stats.get("draws", 0)),
		int(stats.get("barriers", 0))])
	var report: Dictionary = TileKit.barrier_clearance(host, spline)
	var ok: bool = bool(report["clears"]) \
		and float(report["closest"]) >= TileKit.BARRIER_CLEARANCE - 0.02 \
		and highest > 4.0
	print("GLACIER SELF TEST: barriers closest %.2f m (limit %.2f m) -> %s" % [
		float(report["closest"]), float(report["limit"]),
		"OK" if ok else "FAIL"])
	if not bool(report["clears"]):
		_worst_barriers(host, spline)
	host.queue_free()
	return 0 if ok else 1


## Prints the barrier boxes that sit closest to the racing line, with the tile
## they hang off, so a clearance regression names the corner it comes from.
func _worst_barriers(root: Node, spline: RefCounted) -> void:
	_audit_paths(spline)
	var rows: Array[Dictionary] = []
	for node: Node in _descendants(root):
		var body := node as StaticBody3D
		if body == null or not bool(body.get_meta(TileKit.BARRIER_META, false)):
			continue
		for child: Node in body.get_children():
			var collision := child as CollisionShape3D
			if collision == null:
				continue
			var box := collision.shape as BoxShape3D
			if box == null:
				continue
			var xform: Transform3D = _world(collision)
			var closest: float = INF
			var worst: Vector3 = Vector3.ZERO
			for point: Vector3 in TileKit.box_samples(box.size * 0.5):
				var sampled: Vector3 = xform * point
				var sampled_distance: float = TileKit.spline_distance(spline,
					sampled)
				if sampled_distance < closest:
					closest = sampled_distance
					worst = sampled
			var hit: Dictionary = spline.call("plan_closest", worst) as Dictionary
			rows.append({"distance": closest, "at": xform.origin,
				"body": str(body.name), "size": box.size, "worst": worst,
				"s": float(hit.get("s", 0.0)),
				"tile": spline.tile_at(float(hit.get("s", 0.0))).get("tile", "?")})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance"]) < float(b["distance"]))
	for index in mini(rows.size(), 6):
		var row: Dictionary = rows[index]
		print("GLACIER BARRIER %d: %.2f m at %s (tile %s, s %.1f, size %s, body %s, worst %s)" % [
			index, float(row["distance"]), str(row["at"]), str(row["tile"]),
			float(row["s"]), str(row["size"]), str(row["body"]),
			str(row["worst"])])


static func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


## Plan-distance audit of the clearance path itself, per side, so a mitre that
## could not be pushed out of a tight corner is visible before the barrier is
## blamed for it.
func _audit_paths(spline: RefCounted) -> void:
	for side: float in [-1.0, 1.0]:
		var path: Dictionary = KenneyTiles.clearance_path(spline, side,
			TileKit.BARRIER_CLEARANCE + TileKit.BARRIER_SAG)
		if not bool(path.get("ok", false)):
			print("GLACIER PATH %s: unusable" % ("right" if side > 0.0 else "left"))
			continue
		var points: PackedVector3Array = path["points"]
		var closest: float = INF
		var worst: Vector3 = Vector3.ZERO
		for point: Vector3 in points:
			var distance: float = TileKit.spline_distance(spline, point)
			if distance < closest:
				closest = distance
				worst = point
		print("GLACIER PATH %s: %d point(s), closest %.2f m at %s (limit %.2f m)" % [
			"right" if side > 0.0 else "left", points.size(), closest,
			str(worst), TileKit.BARRIER_CLEARANCE + TileKit.BARRIER_SAG])
		var tight: int = 0
		for point: Vector3 in points:
			if TileKit.spline_distance(spline, point) < 8.30:
				tight += 1
				print("  tight %s" % str(point))
		if tight == 0:
			print("  no path point inside 8.30 m")


static func _world(node: Node3D) -> Transform3D:
	var xform: Transform3D = node.transform
	var current: Node = node.get_parent()
	while current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform
