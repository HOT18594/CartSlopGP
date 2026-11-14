extends SceneTree
## Headless self-test for the raised, split Dockyard Quay layout.
##
## Run with:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot_project \
##       --script res://scripts/minigames/maps/dockyard/dockyard_selftest.gd
##
## It builds DockyardGrid through the real KenneyTiles engine with the authored
## heights, calls the real theme, then checks the owner's invariants:
##
##   * 38 drivable cells, about 567 m and 3.0 m of wharf elevation;
##   * a crossing cell and a jump ramp on the lap;
##   * every barrier clears the road edge by TileKit.BARRIER_CLEARANCE;
##   * every solid collider stays at least 6.02 m from the centreline;
##   * the dressing lands in the 600-900 object / under-120-draw budget.
##
## The exit code is 0 on PASS and 1 on any failure, so a build can gate on it.

const Grid := preload("res://scripts/minigames/maps/dockyard/dockyard_grid.gd")
const KenneyTiles := preload("res://scripts/minigames/tiles/kenney_tiles.gd")
const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const DockyardTheme := preload("res://scripts/minigames/maps/dockyard_theme.gd")

const EXPECTED_TILES: int = 38
const EXPECTED_LAP: float = 567.0
const EXPECTED_HEIGHT: float = 3.0
## A solid prop must stay at least this far from the centreline. The lane edge
## is TileKit.ROAD_HALF, so 6.02 m leaves half a metre of real margin.
const SOLID_MARGIN: float = 6.02
## Colliders whose lowest point is above this are overhead (gantry beams).
const DRIVE_UNDER: float = 3.2
const MIN_OBJECTS: int = 600
const MAX_OBJECTS: int = 900
const MAX_DRAWS: int = 120


func _initialize() -> void:
	var failures: int = 0
	var host := Node3D.new()
	host.name = "DockyardSelfTest"
	var spline: RefCounted = KenneyTiles.build(host, Grid.grid_rows(),
		{"id": "dockyard", "heights": Grid.heights()})
	if spline == null:
		print("DOCKYARD SELFTEST: FAIL - the grid did not build")
		quit(1)
		return
	var tiles: Array = spline.get("tiles") as Array
	var length: float = float(spline.total_length)
	var highest: float = 0.0
	var has_crossing: bool = false
	var has_ramp: bool = false
	for tile: Dictionary in tiles:
		highest = maxf(highest, float(tile.get("height", 0.0)))
		var glyph: String = str(tile.get("tile", "X"))
		if glyph == "C":
			has_crossing = true
		elif glyph == "J":
			has_ramp = true
	print("DOCKYARD SELFTEST GRID: %d tiles, %.1f m, highest %.2f m, C=%s J=%s" % [
		tiles.size(), length, highest, str(has_crossing), str(has_ramp)])
	if tiles.size() != EXPECTED_TILES:
		print("DOCKYARD SELFTEST: FAIL - %d tiles (want %d)" % [
			tiles.size(), EXPECTED_TILES])
		failures += 1
	if absf(length - EXPECTED_LAP) > 3.0:
		print("DOCKYARD SELFTEST: FAIL - lap %.1f m (want %.0f)" % [
			length, EXPECTED_LAP])
		failures += 1
	if absf(highest - EXPECTED_HEIGHT) > 0.1:
		print("DOCKYARD SELFTEST: FAIL - highest deck %.2f m (want %.1f)" % [
			highest, EXPECTED_HEIGHT])
		failures += 1
	if not has_crossing or not has_ramp:
		print("DOCKYARD SELFTEST: FAIL - the crossing or ramp cell is missing")
		failures += 1
	DockyardTheme.build(host, spline)
	var barriers: Dictionary = TileKit.barrier_clearance(host, spline)
	var solids: Dictionary = _solid_clearance(host, spline)
	var stats: Dictionary = host.get_meta("dockyard_stats", {})
	print("DOCKYARD SELFTEST STATS: %s" % str(stats))
	var objects: int = int(stats.get("objects", 0))
	var draws: int = int(stats.get("draws", 0))
	print("DOCKYARD SELFTEST DRESSING: %d objects, %d draws, barriers %.2f m (limit %.2f), solids %.2f m (limit %.2f)" % [
		objects, draws, float(barriers["closest"]),
		float(barriers["limit"]), float(solids["closest"]), SOLID_MARGIN])
	if not bool(barriers["clears"]) or int(barriers["pieces"]) == 0:
		print("DOCKYARD SELFTEST: FAIL - a barrier is on the racing surface")
		failures += 1
	if float(solids["closest"]) < SOLID_MARGIN:
		print("DOCKYARD SELFTEST: FAIL - solid %s is %.2f m from the centreline" % [
			str(solids["worst"]), float(solids["closest"])])
		failures += 1
	if objects < MIN_OBJECTS or objects > MAX_OBJECTS:
		print("DOCKYARD SELFTEST: FAIL - %d objects outside %d..%d" % [
			objects, MIN_OBJECTS, MAX_OBJECTS])
		failures += 1
	if draws > MAX_DRAWS:
		print("DOCKYARD SELFTEST: FAIL - %d draws over the %d budget" % [
			draws, MAX_DRAWS])
		failures += 1
	print("DOCKYARD SELFTEST: %s (%d failure(s))" % [
		"PASS" if failures == 0 else "FAIL", failures])
	host.free()
	quit(failures)


# --------------------------------------------------------------------------
# solid collider audit


## Closest plan approach of every non-road solid collider. Overhead pieces are
## skipped, exactly like the preview audit, so a gantry beam over the road does
## not count as an on-track prop.
func _solid_clearance(root: Node, spline: RefCounted) -> Dictionary:
	var closest: float = INF
	var worst: String = "none"
	for body: Node in _all_nodes(root):
		var static_body := body as StaticBody3D
		if static_body == null or str(static_body.name) == "RoadCollision":
			continue
		for child: Node in static_body.get_children():
			var collision := child as CollisionShape3D
			if collision == null:
				continue
			var samples: Array[Vector3] = []
			var xform: Transform3D = _world_transform(collision)
			var box := collision.shape as BoxShape3D
			var cylinder := collision.shape as CylinderShape3D
			if box != null:
				if xform.origin.y - box.size.y * 0.5 > DRIVE_UNDER:
					continue
				samples = TileKit.box_samples(box.size * 0.5)
			elif cylinder != null:
				if xform.origin.y - cylinder.height * 0.5 > DRIVE_UNDER:
					continue
				for step in 8:
					var angle: float = TAU * float(step) / 8.0
					samples.append(Vector3(cos(angle) * cylinder.radius, 0.0,
						sin(angle) * cylinder.radius))
			else:
				continue
			for sample: Vector3 in samples:
				var distance: float = TileKit.spline_distance(spline,
					xform * sample)
				if distance < closest:
					closest = distance
					worst = str(static_body.name)
	if closest == INF:
		closest = 0.0
	return {"closest": closest, "worst": worst}


static func _all_nodes(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	for child: Node in root.get_children():
		found.append_array(_all_nodes(child))
	return found


## Composes the parent chain so an off-tree theme still measures world space.
static func _world_transform(node: Node3D) -> Transform3D:
	var xform: Transform3D = node.transform
	var current: Node = node.get_parent()
	while current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform
