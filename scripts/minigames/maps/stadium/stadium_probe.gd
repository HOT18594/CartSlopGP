extends SceneTree
## Headless measurement harness for the Stadium Circuit theme.
##
## Run it with the editor binary, no rendering needed:
##
##     Godot_v4.7.2-stable_win64_console.exe --headless --path godot_project \
##         --script res://scripts/minigames/maps/stadium/stadium_probe.gd \
##         -- models
##
## The first user argument selects the job:
##   models  measured footprint and mesh-part count of every kit model the
##           stadium dressing may use, so the draw-call budget can be planned
##   build   builds the stadium grid and the theme, then prints the object and
##           draw-call counts plus the closest approach of every solid collider
##           to the racing surface. This is the invariant the owner cares about.
##   both    models then build (default)
##
## It never writes to the project: the probe only proves the dressing is legal.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const KenneyTiles := preload("res://scripts/minigames/tiles/kenney_tiles.gd")
const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const StadiumGrid := preload("res://scripts/minigames/maps/stadium/stadium_grid.gd")

## Theme id audited by `build`.
const THEME_ID: String = "stadium"
## A solid prop must stay at least this far from the centreline: the lane edge
## is TileKit.ROAD_HALF, so this leaves a metre of real margin past the road.
const SOLID_MARGIN: float = 6.52
## Colliders whose lowest point is above this are overhead (gantry beams,
## footbridge decks): a kart drives under them, so they are not on the surface.
const DRIVE_UNDER: float = 3.2

const MODELS_RACING: Array[String] = [
	"barrierRed", "barrierWall", "barrierWhite", "grandStand",
	"grandStandCovered", "grandStandRound", "grandStandCoveredRound",
	"grandStandAwning", "pitsGarage", "pitsGarageClosed", "pitsGarageCorner",
	"pitsOffice", "pitsOfficeCorner", "pitsOfficeRoof", "pylon", "billboard",
	"billboardLow", "bannerTowerRed", "bannerTowerGreen", "lightPostLarge",
	"lightPostModern", "overheadLights", "fenceStraight", "fenceCurved",
	"rail", "railDouble", "flagRed", "flagGreen", "flagCheckers",
	"flagCheckersSmall", "flagTankco", "tent", "tentClosed", "tentLong",
	"tentRoof", "tentRoofDouble", "camera_exclusive", "radarEquipment",
	"treeLarge", "treeSmall", "lightColored", "lightRed", "raceCarRed",
	"raceCarWhite", "roadPitStraight", "roadStraight", "roadCurved",
]

const MODELS_NATURE: Array[String] = [
	"tree_default", "tree_oak", "tree_pineTallA", "tree_cone", "tree_fat",
	"tree_detailed", "tree_pineRoundA", "plant_bush", "plant_bushLarge",
	"rock_largeA", "rock_tallA", "cliff_block_rock", "cliff_blockCave_rock",
	"bridge_side_stone", "bridge_center_stone", "bridge_side_wood",
	"bridge_center_wood", "grass", "fence_simple", "sign",
]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var job: String = args[0].to_lower() if args.size() > 0 else "both"
	var failures: int = 0
	if job == "models":
		_print_models()
	elif job == "layout":
		failures += _audit_build(true)
	elif job == "both":
		_print_models()
		failures += _audit_build(false)
	else:
		failures += _audit_build(false)
	print("stadium_probe: %d failure(s)" % failures)
	quit(failures)


## Prints footprint and part count for every candidate model, so the theme can
## group repeated pieces into few MultiMeshes.
func _print_models() -> void:
	print("MODELS racing (name, size in m, parts):")
	for model: String in MODELS_RACING:
		_print_model(model, false)
	print("MODELS nature (name, size in m, parts):")
	for model: String in MODELS_NATURE:
		_print_model(model, true)


func _print_model(model: String, nature: bool) -> void:
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		print("  %-24s MISSING" % model)
		return
	var size: Vector3 = (info["size"] as Vector3) * TrackDefsScale(nature)
	var parts: int = (info["parts"] as Array).size()
	print("  %-24s %6.1f x %5.1f x %6.1f  parts %d" % [
		model, size.x, size.y, size.z, parts])


static func TrackDefsScale(nature: bool) -> float:
	return TileKit.NATURE_SCALE if nature else TileKit.PROP_SCALE


## Builds the stadium grid and the theme exactly as grass_race does, then
## measures the dressing against the racing surface. `canonical` builds the
## layout from stadium_grid.gd instead of the registry preset, so a layout can
## be proven before the registry copy is updated.
func _audit_build(canonical: bool) -> int:
	var preset: Dictionary = TrackDefs.get_preset(THEME_ID)
	var host := Node3D.new()
	host.name = "StadiumProbe"
	var rows: PackedStringArray = TrackDefs.grid_of(preset)
	var theme: Dictionary = {"id": TrackDefs.theme_id_of(preset)}
	var preset_heights: PackedStringArray = TrackDefs.heights_of(preset)
	if not preset_heights.is_empty():
		theme["heights"] = preset_heights
	var label: String = "registry"
	if canonical:
		rows = StadiumGrid.grid_rows()
		theme = StadiumGrid.theme_dict()
		label = "canonical"
	var spline: RefCounted = KenneyTiles.build(host, rows, theme)
	if spline == null:
		print("BUILD %s stadium: FAIL (the grid did not build)" % label)
		host.free()
		return 1
	if canonical:
		var mismatch: int = StadiumGrid.mismatch_row(rows)
		if mismatch >= 0:
			print("BUILD %s: row %d differs from the registry copy" % [
				label, mismatch])
	var theme_path: String = TrackDefs.theme_path_of(preset)
	var stats: Dictionary = {}
	if ResourceLoader.exists(theme_path):
		var script: Script = load(theme_path) as Script
		if script != null and script.has_method("build"):
			script.call("build", host, spline)
			stats = host.get_meta("stadium_dressing_stats", {}) as Dictionary
	var total: float = maxf(float(spline.total_length), 1.0)
	var tile_count: int = (spline.get("tiles") as Array).size()
	print("BUILD %s stadium: %.0f m lap, %d tiles, road half %.2f m" % [
		label, total, tile_count, TileKit.ROAD_HALF])
	var objects: int = int(stats.get("objects", 0))
	var draws: int = int(stats.get("draws", 0))
	if draws == 0:
		draws = _count_geometry(host)
	print("BUILD stadium: %d object(s), %d draw node(s), draws/object %.2f" % [
		objects, draws, float(draws) / float(maxi(objects, 1))])
	var barrier: Dictionary = TileKit.barrier_clearance(host, spline)
	print("BUILD barriers: %d piece(s), closest %.2f m (limit %.2f m) -> %s" % [
		int(barrier["pieces"]), float(barrier["closest"]),
		float(barrier["limit"]),
		"CLEARS" if bool(barrier["clears"]) else "ON THE ROAD"])
	_report_weak_barriers(host, spline)
	var solids: Dictionary = _solid_props(host, spline)
	print("BUILD solids: %d collider(s), closest %.2f m (%s) -> %s" % [
		int(solids["pieces"]), float(solids["closest"]), str(solids["worst"]),
		"OK" if float(solids["closest"]) >= SOLID_MARGIN else "TOO CLOSE"])
	_report_weak_solids(host, spline)
	var heights: Array[float] = _road_heights(spline)
	print("BUILD heights: road %.2f .. %.2f m" % [
		heights[0], heights[1]])
	var failures: int = 0
	if float(barrier["closest"]) < TileKit.BARRIER_CLEARANCE - 0.12 \
			or int(barrier["pieces"]) == 0:
		failures += 1
	if float(solids["closest"]) < SOLID_MARGIN:
		failures += 1
	if objects < 700 or objects > 1950:
		print("BUILD budget: %d object(s) outside the 700-1950 target" % objects)
		failures += 1
	if draws >= 115:
		print("BUILD budget: %d draw node(s) at or over the 115 target" % draws)
		failures += 1
	host.free()
	return failures


## Prints the barrier pieces that come inside the design clearance, with the lap
## distance they start at, so a layout can be fixed at the right corner.
func _report_weak_barriers(root: Node, spline: RefCounted) -> void:
	for node: Node in _all_nodes(root):
		var body := node as StaticBody3D
		if body == null or not bool(body.get_meta(TileKit.BARRIER_META, false)):
			continue
		var closest: float = INF
		var where: Vector3 = Vector3.ZERO
		for child: Node in body.get_children():
			var collision := child as CollisionShape3D
			if collision == null:
				continue
			var box := collision.shape as BoxShape3D
			if box == null:
				continue
			var xform: Transform3D = _world_transform(collision)
			for point: Vector3 in TileKit.box_samples(box.size * 0.5):
				var world: Vector3 = xform * point
				var distance: float = TileKit.spline_distance(spline, world)
				if distance < closest:
					closest = distance
					where = world
		if closest < TileKit.BARRIER_CLEARANCE - 0.02:
			print("  weak barrier %s: %.2f m at (%.1f, %.1f)" % [
				str(body.name), closest, where.x, where.z])


## Prints the solid pieces that come inside the clearance limit, with the world
## position of their closest sample, so a rogue placement can be found fast.
func _report_weak_solids(root: Node, spline: RefCounted) -> void:
	var shown: int = 0
	for node: Node in _all_nodes(root):
		var body := node as StaticBody3D
		if body == null or str(body.name) == "RoadCollision":
			continue
		var closest: float = INF
		var where: Vector3 = Vector3.ZERO
		var overhead: bool = false
		for child: Node in body.get_children():
			var collision := child as CollisionShape3D
			if collision == null:
				continue
			var box := collision.shape as BoxShape3D
			if box == null:
				continue
			var xform: Transform3D = _world_transform(collision)
			for point: Vector3 in TileKit.box_samples(box.size * 0.5):
				var world: Vector3 = xform * point
				var distance: float = TileKit.spline_distance(spline, world)
				if distance < closest:
					closest = distance
					where = world
			if xform.origin.y - box.size.y * 0.5 > DRIVE_UNDER:
				overhead = true
		if closest < SOLID_MARGIN and not overhead and shown < 12:
			shown += 1
			print("  weak solid %s: %.2f m at (%.1f, %.1f)" % [
				str(body.name), closest, where.x, where.z])


## Every solid collider outside the road body, sampled in plan and skipped when
## its lowest point is above a kart (gantry beams, footbridge decks).
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
				if _world_transform(collision).origin.y - box.size.y * 0.5 \
						> DRIVE_UNDER:
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
					worst = "%s (%s)" % [str(body.name), str(collision.shape)]
	if closest == INF:
		closest = 0.0
	return {"closest": closest, "worst": worst, "pieces": pieces}


## Lowest and highest road deck height along the lap, in metres.
func _road_heights(spline: RefCounted) -> Array[float]:
	var low: float = INF
	var high: float = -INF
	for index in 180:
		var height: float = float(spline.height_at(
			float(spline.total_length) * float(index) / 180.0))
		low = minf(low, height)
		high = maxf(high, height)
	return [low, high]


func _count_geometry(node: Node) -> int:
	var count: int = 1 if node is GeometryInstance3D else 0
	for child: Node in node.get_children():
		count += _count_geometry(child)
	return count


static func _all_nodes(root: Node) -> Array[Node]:
	var found: Array[Node] = [root]
	for child: Node in root.get_children():
		found.append_array(_all_nodes(child))
	return found


## Composes the parent chain, so a collider under the themed holder measures in
## world space even though the probe never adds the tree to the scene.
static func _world_transform(node: Node3D) -> Transform3D:
	var xform: Transform3D = node.transform
	var current: Node = node.get_parent()
	while current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform
