extends SceneTree
## Headless audit for the map previews, the barrier clearance invariant and the
## tile engine's elevation support.
##
## Run it with the editor binary, no rendering needed:
##
##     Godot_v4.7.2-stable_win64_console.exe --headless --path godot_project \
##         --script res://scripts/tools/preview_verify.gd
##
## It does three independent jobs and exits with the number of failures:
##
##   * builds every grid race map from its ASCII grid plus its theme, then
##     measures the closest approach of every barrier collider to the centreline
##     and prints whether the barrier clears the racing surface;
##   * builds one grid again with a rolling elevation profile and checks that
##     the spline, the road colliders and the barriers all follow the height;
##   * reloads every generated preview PNG and checks it is a 1600x900 picture
##     over 120 KB that is not a flat colour.
##
## Building a theme is placement only, so a headless run exercises the same
## colliders and spline the race scene uses.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const KenneyTiles := preload("res://scripts/minigames/tiles/kenney_tiles.gd")
const TileKit := preload("res://scripts/minigames/tile_kit.gd")

const OUT_DIR: String = "res://assets/ui/art/"
const PREVIEW_PREFIX: String = "preview_"
const PREVIEW_WIDTH: int = 1600
const PREVIEW_HEIGHT: int = 900
const MIN_PNG_BYTES: int = 120 * 1024
const MIN_COLOURS: int = 24
const MAX_FLAT_RATIO: float = 0.94
const SAMPLE_STEP: int = 12
## A solid prop must stay at least this far from the centreline; the lane edge
## is TileKit.ROAD_HALF, so 6.02 m leaves half a metre of real margin.
const SOLID_MARGIN: float = 6.02
## Colliders whose lowest point is above this are overhead (start gantry beam).
const DRIVE_UNDER: float = 3.2

## A hill profile used by the terrain audit: two 3 m rises per lap.
const TEST_ELEVATION: Array[Dictionary] = [
	{"at": 0.0, "height": 0.0},
	{"at": 0.25, "height": 3.0},
	{"at": 0.50, "height": 0.0},
	{"at": 0.75, "height": 3.0},
]
const TERRAIN_MAP: String = "stadium"


func _initialize() -> void:
	var failures: int = 0
	failures += _audit_barriers()
	failures += _audit_terrain()
	failures += _audit_previews()
	print("preview_verify: %d failure(s)" % failures)
	quit(failures)


# --------------------------------------------------------------------------
# barrier clearance audit
# --------------------------------------------------------------------------


## Builds every grid map headless and reports the closest a barrier collider
## comes to the racing line. A barrier that clears the road is at least
## BARRIER_CLEARANCE away; the old chorded walls measured 4.20 m, 0.00 m and
## 3.63 m on these same three maps.
func _audit_barriers() -> int:
	var failures: int = 0
	for preset: Dictionary in TrackDefs.PRESETS:
		if not TrackDefs.is_map(preset):
			continue
		var map_id: String = str(preset.get("id", TrackDefs.DEFAULT_ID))
		var host := Node3D.new()
		host.name = "Audit_" + map_id
		var spline: RefCounted = KenneyTiles.build(host,
			TrackDefs.grid_of(preset), {"id": TrackDefs.theme_id_of(preset)})
		if spline == null:
			print("BARRIERS %s: FAIL (the grid did not build)" % map_id)
			host.free()
			failures += 1
			continue
		var theme_path: String = TrackDefs.theme_path_of(preset)
		if ResourceLoader.exists(theme_path):
			var theme: Script = load(theme_path) as Script
			if theme != null and theme.has_method("build"):
				theme.call("build", host, spline)
		var report: Dictionary = TileKit.barrier_clearance(host, spline)
		var closest: float = float(report["closest"])
		var solids: Dictionary = _solid_props(host, spline)
		print("BARRIERS %s: %d piece(s), closest %.2f m from the centreline (limit %.2f m, road half %.2f m) -> %s" % [
			map_id, int(report["pieces"]), closest,
			float(report["limit"]), TileKit.ROAD_HALF,
			"CLEARS" if bool(report["clears"]) else "ON THE ROAD"])
		print("SOLIDS %s: %d collider(s), closest %.2f m (%s) -> %s" % [
			map_id, int(solids["pieces"]), float(solids["closest"]),
			str(solids["worst"]),
			"OK" if float(solids["closest"]) >= SOLID_MARGIN else "TOO CLOSE"])
		if not bool(report["clears"]) or int(report["pieces"]) == 0 \
				or float(solids["closest"]) < SOLID_MARGIN:
			failures += 1
		host.free()
	return failures


## Every solid collider outside the road body, sampled in plan and skipped when
## its lowest point is above a kart (the gantry beam). Proves the wider invariant
## that stands, lights, signage and tyres stay off the racing surface.
func _solid_props(root: Node, spline: RefCounted) -> Dictionary:
	var closest: float = INF
	var worst: String = "none"
	var pieces: int = 0
	for node: Node in _all_nodes(root):
		var body := node as StaticBody3D
		if body == null or str(body.name) == "RoadCollision":
			continue
		for child: Node in body.get_children():
			var collision := child as CollisionShape3D
			if collision == null:
				continue
			var samples: Array[Vector3] = []
			var box := collision.shape as BoxShape3D
			var cylinder := collision.shape as CylinderShape3D
			if box != null:
				for point: Vector3 in TileKit.box_samples(box.size * 0.5):
					samples.append(point)
				if _lowest(box.size, collision) > DRIVE_UNDER:
					continue
			elif cylinder != null:
				for step in 8:
					var angle: float = TAU * float(step) / 8.0
					samples.append(Vector3(cos(angle) * cylinder.radius, 0.0,
						sin(angle) * cylinder.radius))
				if _world_transform(collision).origin.y \
						- cylinder.height * 0.5 > DRIVE_UNDER:
					continue
			else:
				continue
			var xform: Transform3D = _world_transform(collision)
			pieces += 1
			for point: Vector3 in samples:
				var distance: float = TileKit.spline_distance(spline,
					xform * point)
				if distance < closest:
					closest = distance
					worst = str(body.name)
	if closest == INF:
		closest = 0.0
	return {"closest": closest, "worst": worst, "pieces": pieces}


static func _lowest(size: Vector3, collision: CollisionShape3D) -> float:
	return _world_transform(collision).origin.y - size.y * 0.5


# --------------------------------------------------------------------------
# terrain audit
# --------------------------------------------------------------------------


## Builds one grid with a rolling elevation profile and checks the whole chain:
## the spline carries the height, the road colliders sit on it, and a barrier
## run placed on it follows the slope while keeping its clearance.
func _audit_terrain() -> int:
	var preset: Dictionary = TrackDefs.get_preset(TERRAIN_MAP)
	var host := Node3D.new()
	host.name = "AuditTerrain"
	var spline: RefCounted = KenneyTiles.build(host,
		TrackDefs.grid_of(preset), {"id": TERRAIN_MAP,
		"elevation": TEST_ELEVATION})
	if spline == null:
		print("TERRAIN %s: FAIL (the elevated grid did not build)" % TERRAIN_MAP)
		host.free()
		return 1
	var total: float = float(spline.total_length)
	var sampled: float = 0.0
	var highest: float = -INF
	var lowest: float = INF
	for index in 120:
		var height: float = float(spline.height_at(total * float(index) / 120.0))
		highest = maxf(highest, height)
		lowest = minf(lowest, height)
	var placed: int = 0
	for side: float in [-1.0, 1.0]:
		placed += TileKit.barrier_line(host, spline, 0.0, total, side,
			"barrierRed")
	var report: Dictionary = TileKit.barrier_clearance(host, spline)
	var barrier_heights: Array[float] = _barrier_heights(host)
	# Terrain berms are the cheap elevation dressing the kit exposes; they must
	# clear the same barrier line.
	var banks: int = 0
	for side: float in [-1.0, 1.0]:
		banks += TileKit.terrain_banks(host, spline, 0.0, total, side, 1.8)
	var bank_closest: float = _solid_clearance(host, spline, "TerrainBanks_")
	var flat_ok: bool = absf(highest) > 0.5 and absf(lowest) < 0.5
	var slopes_ok: bool = not barrier_heights.is_empty() \
		and highest > barrier_heights[0]
	var collider_ok: bool = _road_collider_heights(host) > 1.0
	var banks_ok: bool = banks > 0 \
		and bank_closest >= TileKit.BARRIER_CLEARANCE - 0.02
	print("TERRAIN %s: road height %.2f..%.2f m, %d barrier piece(s) %.2f..%.2f m, road collider top %.2f m, %d bank(s) closest %.2f m, barriers closest %.2f m -> %s" % [
		TERRAIN_MAP, lowest, highest, placed,
		barrier_heights[0] if not barrier_heights.is_empty() else 0.0,
		barrier_heights[barrier_heights.size() - 1] if not barrier_heights.is_empty() else 0.0,
		_road_collider_heights(host), banks, bank_closest,
		float(report["closest"]),
		"OK" if flat_ok and slopes_ok and collider_ok and banks_ok \
			and bool(report["clears"]) else "FAIL"])
	var ok: bool = flat_ok and slopes_ok and collider_ok and banks_ok \
		and bool(report["clears"]) and placed > 0
	host.free()
	return 0 if ok else 1


## Closest plan approach of every box collider under bodies whose name starts
## with `prefix`, for props that have to stay off the racing surface.
func _solid_clearance(root: Node, spline: RefCounted,
		prefix: String) -> float:
	var closest: float = INF
	for node: Node in _all_nodes(root):
		var body := node as StaticBody3D
		if body == null or not str(body.name).begins_with(prefix):
			continue
		for child: Node in body.get_children():
			var collision := child as CollisionShape3D
			if collision == null:
				continue
			var box := collision.shape as BoxShape3D
			if box == null:
				continue
			var xform: Transform3D = _world_transform(collision)
			var half: Vector3 = box.size * 0.5
			for point: Vector3 in TileKit.box_samples(half):
				closest = minf(closest,
					TileKit.spline_distance(spline, xform * point))
	return closest


## Lowest and highest barrier piece origin under `root`, in metres.
func _barrier_heights(root: Node) -> Array[float]:
	var heights: Array[float] = []
	for body: Node in _all_nodes(root):
		if body is StaticBody3D \
				and bool(body.get_meta(TileKit.BARRIER_META, false)):
			for child: Node in body.get_children():
				if child is CollisionShape3D:
					heights.append(_world_transform(child as Node3D).origin.y)
	heights.sort()
	return heights


## Highest road collider box top under `root`, in metres. Proves the physics
## followed the road surface.
func _road_collider_heights(root: Node) -> float:
	var top: float = 0.0
	for node: Node in _all_nodes(root):
		var body := node as StaticBody3D
		if body == null or str(body.name) != "RoadCollision":
			continue
		for child: Node in body.get_children():
			var collision := child as CollisionShape3D
			if collision == null:
				continue
			var box := collision.shape as BoxShape3D
			if box == null:
				continue
			top = maxf(top,
				_world_transform(collision).origin.y + box.size.y * 0.5)
	return top


# --------------------------------------------------------------------------
# node helpers
# --------------------------------------------------------------------------


static func _all_nodes(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	for child: Node in root.get_children():
		found.append_array(_all_nodes(child))
	return found


## Composes the parent chain, so a collider under a themed holder is measured in
## world space even though the audit never adds the tree to the scene.
static func _world_transform(node: Node3D) -> Transform3D:
	var xform: Transform3D = node.transform
	var current: Node = node.get_parent()
	while current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


# --------------------------------------------------------------------------
# preview image audit
# --------------------------------------------------------------------------


func _audit_previews() -> int:
	var failures: int = 0
	var seen: int = 0
	for preset: Dictionary in TrackDefs.PRESETS:
		var map_id: String = str(preset.get("id", TrackDefs.DEFAULT_ID))
		var path: String = OUT_DIR + PREVIEW_PREFIX + map_id + ".png"
		if not FileAccess.file_exists(path):
			print("PREVIEW %s: missing (%s)" % [map_id, path])
			failures += 1
			continue
		seen += 1
		var record: Dictionary = _verify_image(map_id, path)
		print("PREVIEW %s: %d bytes, %d colours, flat %.0f%%, %s" % [
			map_id, int(record["bytes"]), int(record["colours"]),
			float(record["flat"]) * 100.0,
			"OK" if bool(record["ok"]) else "FAIL " + str(record["note"])])
		if not bool(record["ok"]):
			failures += 1
	if seen == 0:
		print("preview_verify: no preview images to check")
	return failures


func _verify_image(map_id: String, path: String) -> Dictionary:
	var record: Dictionary = {"id": map_id, "path": path, "ok": false,
		"bytes": 0, "colours": 0, "flat": 1.0, "note": ""}
	var absolute: String = ProjectSettings.globalize_path(path)
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null:
		record["note"] = "cannot open"
		return record
	record["bytes"] = file.get_length()
	file.close()
	var image := Image.new()
	var error: Error = image.load(absolute)
	if error != OK:
		record["note"] = "cannot decode (%s)" % error_string(error)
		return record
	if image.get_width() != PREVIEW_WIDTH \
			or image.get_height() != PREVIEW_HEIGHT:
		record["note"] = "wrong size %dx%d" % [image.get_width(),
			image.get_height()]
		return record
	var buckets: Dictionary = {}
	var samples: int = 0
	var dominant: int = 0
	for y: int in range(0, PREVIEW_HEIGHT, SAMPLE_STEP):
		for x: int in range(0, PREVIEW_WIDTH, SAMPLE_STEP):
			var colour: Color = image.get_pixel(x, y)
			var key: int = (int(colour.r * 31.0) << 10) \
				| (int(colour.g * 31.0) << 5) | int(colour.b * 31.0)
			var seen: int = int(buckets.get(key, 0)) + 1
			buckets[key] = seen
			dominant = maxi(dominant, seen)
			samples += 1
	var flat: float = float(dominant) / float(maxi(samples, 1))
	record["colours"] = buckets.size()
	record["flat"] = flat
	record["ok"] = int(record["bytes"]) >= MIN_PNG_BYTES \
		and buckets.size() >= MIN_COLOURS and flat < MAX_FLAT_RATIO
	if not bool(record["ok"]):
		record["note"] = "too small, too flat or too few colours"
	return record
