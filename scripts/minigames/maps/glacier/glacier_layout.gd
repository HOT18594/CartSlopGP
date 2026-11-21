extends RefCounted
## Trackside dressing for the Glacier Pass alpine circuit.
##
## Everything solid is placed either through scripts/minigames/tile_kit.gd (which
## owns the barrier line, the batching and the WORLD colliders) or through the
## glacier prop layer, which applies the same batching and collider rules. The
## pass, outside in:
##
##   barriers      a continuous red barrier ring on both road edges. It follows
##                 the real tile edge geometry at BARRIER_CLEARANCE, so even on
##                 the inside of an 8 m corner it is a mitre, never a chord onto
##                 the racing surface.
##   snowbanks     a bank of ice-grey boulders outside the barrier, both sides,
##                 grounded on the snow at 13 m so the wall has something to
##                 protect and the run-off reads ploughed.
##   fences        avalanche catch fencing along the outside of the lap, set on
##                 the shoulder at 10.4 m and following the deck height, so it
##                 climbs with the pass.
##   summit flags  checkered and coloured flags at the highest point of the lap,
##                 plus the start flags beside the line.
##   split         a paved pit-lane split off the longest straight: an apron
##                 that forks away from the racing lane and runs behind the
##                 barrier, with garages and marker pylons. It is scenery, not a
##                 second racing line: the barrier ring still separates it.
##   structures    a start gantry over the line, two grandstands, ten floodlight
##                 posts, banner towers and ice-warning pylons.
##
## The pine forest and the mountains are separate modules (glacier_forest,
## glacier_terrain); this file owns the road furniture. Nothing here names a
## texture: the art is the Kenney racing and nature kits only.
##
## The build is idempotent: the theme creates the holder once, so a scene reload
## can never double the props.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const GlacierProps := preload("res://scripts/minigames/maps/glacier/glacier_props.gd")
const GlacierSurface := preload("res://scripts/minigames/maps/glacier/glacier_surface.gd")

const TILE: float = TileKit.TILE_SIZE
const ROAD_HALF: float = TileKit.ROAD_HALF
const QUARTER: float = TileKit.SNAP_STEP
const NATURE: float = TileCatalog.NATURE_SCALE

const BARRIER_KIND: String = "barrierRed"
const START_FLAG: String = "flagCheckers"
const ICE_FLAG: String = "flagRed"
const ICE_MARKER: String = "pylon"
const START_TOWERS: Array[String] = ["bannerTowerRed", "bannerTowerGreen"]

## Ploughed snow banks. The kit has no snow block, so the coldest rock shapes
## stand in for a bank; they read ice-grey against the snow.
const SNOWBANK_MODELS: Array[String] = [
	"rock_largeA", "rock_largeB", "rock_largeF",
]
const SNOWBANK_LATERAL: float = 19.2
const SNOWBANK_STEP: float = 15.0
const SNOWBANK_SCALE_MIN: float = 0.78
const SNOWBANK_SCALE_MAX: float = 1.20
const SNOWBANK_MAX: int = 56

## Avalanche fencing: low sparse clusters rather than enclosing corridors.
const FENCE_MODEL: String = "fenceStraight"
const FENCE_LATERAL: float = 16.4
const FENCE_LENGTH: float = 7.0
const FENCE_HEIGHT: float = 3.4
const FENCE_SPACING: float = 9.0
const FENCE_EVERY: int = 5
const FENCE_MAX: int = 18
const FENCE_MAX_TURN: float = 0.07

## Floodlights, ten of them, on the outside of the lap.
const LIGHT_FRACTIONS: Array[float] = [
	0.04, 0.13, 0.22, 0.31, 0.40, 0.55, 0.64, 0.73, 0.82, 0.93,
]
const LIGHT_SIDE: float = -1.0

## Start flags sit one tile before and after the line so they flank the grid.
const START_FLAG_OFFSETS: Array[float] = [TILE, -TILE]
const SUMMIT_FLAGS: int = 6

## Clearance a foliage cell centre needs from the centreline, in metres.
const FOLIAGE_CLEARANCE: float = ROAD_HALF + TILE * 0.5
## Clearance for an upright prop that the kit places by cell (>= 7.5 m outside
## clearance_path so snapped cell props never encroach on the road or barriers).
const PROP_CLEARANCE: float = ROAD_HALF + TileKit.BARRIER_OFFSET + 8.5

## Grandstands: a 16 m kit footprint two cells out, facing the track.
const STAND_MODELS: Array[String] = ["grandStandCovered", "grandStand"]
const STAND_LATERAL: float = 25.5

## The split: a pit apron and garages behind the verge on the longest
## straight, so the base of the pass has a lane fork.
const SPLIT_APRON_MODEL: String = "roadPitStraight"
const SPLIT_GARAGE_MODEL: String = "pitsGarage"
const SPLIT_APRON_LATERAL: float = 26.0
const SPLIT_GARAGE_LATERAL: float = 45.0
const SPLIT_APRON_PIECES: int = 4
const SPLIT_PYLONS: int = 3
const SPLIT_APRON_Y: float = 0.07

const INVALID_CELL: Vector2i = Vector2i(-999999, -999999)
const SEED: int = 20261113


## Builds the whole trackside pass under `holder` and returns the statistics.
static func build(holder: Node3D, spline: RefCounted,
		preset: Dictionary) -> Dictionary:
	var stats: Dictionary = {
		"barriers": 0, "stands": 0, "gantry": 0, "lights": 0, "flags": 0,
		"signage": 0, "snowbanks": 0, "fences": 0, "split": 0,
		"objects": 0, "draws": 0,
	}
	if holder == null or spline == null:
		return stats
	var total: float = maxf(float(spline.total_length), 1.0)
	var reserved: Dictionary = {}
	# 1. The barrier ring first: it defines the edge props may not cross.
	stats["barriers"] = _barrier_ring(holder, spline, total)
	# 2. Structures claim their cells before the small props.
	stats["stands"] = _grandstands(holder, spline, total, reserved)
	stats["gantry"] = TileKit.gantry(holder, spline, 0.0)
	stats["split"] = _split(holder, spline)
	# 3. Lamps, flags and signage fill the trackside cells.
	stats["lights"] = _lights(holder, spline, total, reserved)
	stats["flags"] = _flags(holder, spline, total, preset, reserved)
	stats["signage"] = _signage(holder, spline, total, preset, reserved)
	# 4. Banks and fences follow the road edge itself.
	stats["snowbanks"] = _snowbanks(holder, spline)
	stats["fences"] = _fences(holder, spline)
	stats["objects"] = int(stats["barriers"]) + int(stats["stands"]) \
		+ int(stats["gantry"]) + int(stats["lights"]) + int(stats["flags"]) \
		+ int(stats["signage"]) + int(stats["snowbanks"]) \
		+ int(stats["fences"]) + int(stats["split"])
	stats["draws"] = _draw_estimate(stats)
	return stats


# --------------------------------------------------------------------------
# barrier ring
# --------------------------------------------------------------------------


## Two continuous barrier runs per side. A full-lap span wraps to a near-zero
## arc length inside TileKit's snapping, so the ring is split at the last
## quarter-tile seam and the final short run carries the line across the start.
static func _barrier_ring(holder: Node3D, spline: RefCounted,
		_total: float) -> int:
	# Open alpine circuit: crisp cobalt/snow safety rails only on steep summit
	# ledges (y >= 2.2) and tight outside hairpins, plus far outer containment.
	var rails: int = TileKit.selective_safety_rails(holder, spline, {
		"bridge_y": 2.2,
		"curve_min": 0.032,
		"rail_color": Color("eef6fc"),
		"accent_color": Color("2a86b8"),
		"post_color": Color("475a6b"),
	})
	TileKit.build_outer_soft_containment(holder, spline, 13.0)
	return rails


# --------------------------------------------------------------------------
# structures
# --------------------------------------------------------------------------


## One covered stand and one open stand, both on the flattest part of the lap so
## a grandstand is never left standing on stilts under an elevated deck. The
## model is based on the snow at y = 0 and sealed with one box collider.
static func _grandstands(holder: Node3D, spline: RefCounted, total: float,
		reserved: Dictionary) -> int:
	var specs: Array[Dictionary] = [
		{"fraction": 0.53, "side": -1.0},
		{"fraction": 0.67, "side": -1.0},
	]
	var entries: Array = []
	var points: Array = []
	var body: StaticBody3D = GlacierProps.body(holder, "GlacierStands")
	for index in specs.size():
		var spec: Dictionary = specs[index]
		var fraction: float = float(spec["fraction"])
		if _deck_at(spline, total * fraction) > 2.5:
			# The chosen stretch is a high shelf; move the stand to the base.
			fraction = 0.60
		var distance: float = total * fraction
		var side: float = float(spec["side"])
		var forward: Vector3 = spline.sample(distance)["forward"] as Vector3
		var right: Vector3 = spline.sample(distance)["right"] as Vector3
		var base: Vector3 = (spline.sample(distance)["position"] as Vector3) \
			+ right * (STAND_LATERAL * side)
		base.y = 0.0
		if GlacierProps.clearance(spline, base) < 20.5:
			continue
		var model: String = STAND_MODELS[index % STAND_MODELS.size()]
		var yaw: float = atan2(-forward.x, -forward.z) \
			+ (PI * 0.5 if side > 0.0 else -PI * 0.5)
		var scale: float = TileCatalog.PROP_SCALE
		entries.append({"model": model,
			"transform": GlacierProps.fit(model, base, yaw, scale)})
		points.append(base)
		var plan: Vector2 = GlacierProps.footprint(model, scale)
		var height: float = GlacierProps.height(model, scale)
		GlacierProps.box(body, base + Vector3.UP * (height * 0.5),
			Vector3(plan.x, height, plan.y), yaw)
		_reserve(reserved, _cell_of(base), 1)
	if entries.is_empty():
		body.free()
		return 0
	GlacierProps.batch(holder, entries, "GlacierStands", true)
	GlacierProps.assert_clearance("GlacierStands", points, spline)
	return entries.size()


## The split off the longest straight: an apron of pit-lane slabs that forks out
## of the racing lane, a garage block, and marker pylons. The slabs are flat
## road plates (not solid), so only the garages and the pylons carry colliders.
## The whole fork is skipped when either side of the straight has another part
## of the lap close enough that a garage would stand on it.
static func _split(holder: Node3D, spline: RefCounted) -> int:
	var straight: Dictionary = _longest_straight(spline)
	if straight.is_empty():
		return 0
	var distance: float = float(straight["distance"])
	var span: float = float(straight["span"])
	var frame: Dictionary = spline.sample(distance)
	var centre: Vector3 = frame["position"] as Vector3
	var right: Vector3 = (frame["right"] as Vector3)
	right.y = 0.0
	var forward: Vector3 = frame["forward"] as Vector3
	right = right.normalized()
	forward.y = 0.0
	forward = forward.normalized()
	if forward.length() < 0.01 or right.length() < 0.01:
		return 0
	var yaw: float = atan2(-forward.x, -forward.z)
	for side: float in [1.0, -1.0]:
		var plan: Dictionary = _split_plan(spline, centre, forward, right, yaw,
			side, span)
		if not plan.is_empty():
			return _commit_split(holder, plan)
	return 0


## Candidate pieces for one side of the straight, or an empty dictionary when a
## garage or pylon would sit inside the solid clearance of any part of the lap.
static func _split_plan(spline: RefCounted, centre: Vector3, forward: Vector3,
		right: Vector3, yaw: float, side: float, span: float) -> Dictionary:
	var entries: Array = []
	var solids: Array = []
	for index in SPLIT_APRON_PIECES:
		var along: float = (float(index) - float(SPLIT_APRON_PIECES - 1) * 0.5) \
			* TILE
		var flank: float = SPLIT_APRON_LATERAL
		var turn: float = 0.0
		if index == 0:
			flank -= 5.0
			turn = 0.30
		elif index == SPLIT_APRON_PIECES - 1:
			flank -= 1.5
		var at: Vector3 = centre + forward * along + right * (flank * side)
		at.y = centre.y + SPLIT_APRON_Y
		entries.append({"model": SPLIT_APRON_MODEL, "kind": "apron",
			"position": at, "yaw": yaw + turn * side})
	for index in 2:
		var along: float = (float(index) - 0.5) * TILE * 1.2
		var base: Vector3 = centre + forward * along \
			+ right * (SPLIT_GARAGE_LATERAL * side)
		base.y = centre.y
		if GlacierProps.clearance(spline, base) < GlacierProps.SOLID_CLEARANCE:
			return {}
		entries.append({"model": SPLIT_GARAGE_MODEL, "kind": "garage",
			"position": base,
			"yaw": yaw + (PI * 0.5 if side > 0.0 else -PI * 0.5)})
		solids.append(base)
	for index in SPLIT_PYLONS:
		var along: float = (float(index) - float(SPLIT_PYLONS - 1) * 0.5) \
			* (span * 0.22)
		var at: Vector3 = centre + forward * along \
			+ right * ((SPLIT_APRON_LATERAL - 6.5) * side)
		at.y = centre.y + SPLIT_APRON_Y
		if GlacierProps.clearance(spline, at) < 16.8:
			return {}
		entries.append({"model": ICE_MARKER, "kind": "pylon", "position": at,
			"yaw": yaw})
		solids.append(at)
	if entries.is_empty():
		return {}
	return {"entries": entries, "solids": solids}


## Writes one side of the split: batched models plus the solid colliders.
static func _commit_split(holder: Node3D, plan: Dictionary) -> int:
	var entries: Array = []
	var body: StaticBody3D = GlacierProps.body(holder, "GlacierSplit")
	var scale: float = TileCatalog.PROP_SCALE
	for entry: Variant in plan["entries"] as Array:
		var piece: Dictionary = entry as Dictionary
		var model: String = str(piece["model"])
		var at: Vector3 = piece["position"]
		var piece_yaw: float = float(piece["yaw"])
		entries.append({"model": model,
			"transform": GlacierProps.fit(model, at, piece_yaw, scale)})
		var kind: String = str(piece["kind"])
		if kind == "apron":
			continue
		if kind == "garage":
			var footprint: Vector2 = GlacierProps.footprint(model, scale)
			var height: float = GlacierProps.height(model, scale)
			GlacierProps.box(body, at + Vector3.UP * (height * 0.5),
				Vector3(footprint.x, height, footprint.y), piece_yaw)
			continue
		GlacierProps.box(body, at + Vector3.UP * 1.1,
			Vector3(1.9, 2.2, 1.9), piece_yaw)
	if entries.is_empty():
		body.free()
		return 0
	GlacierProps.batch(holder, entries, "GlacierSplit", true)
	return entries.size()


# --------------------------------------------------------------------------
# small props
# --------------------------------------------------------------------------


## Floodlight posts down the outside of the loop. `TileKit.lights` batches the
## posts into one MultiMesh and gives each a cylinder on WORLD.
static func _lights(holder: Node3D, spline: RefCounted, total: float,
		reserved: Dictionary) -> int:
	var positions: Array = []
	for fraction: float in LIGHT_FRACTIONS:
		var cell: Vector2i = _free_cell(spline, total * fraction, LIGHT_SIDE,
			reserved, PROP_CLEARANCE)
		if cell == INVALID_CELL:
			continue
		positions.append(_ground_point(cell, spline))
		_reserve(reserved, cell, 1)
	if positions.is_empty():
		return 0
	return TileKit.lights(holder, positions)


## Checkered flags flanking the start, red flags on both sides of every ice
## boundary, and a cluster of summit flags at the highest point of the lap.
static func _flags(holder: Node3D, spline: RefCounted, total: float,
		preset: Dictionary, reserved: Dictionary) -> int:
	var entries: Array = []
	for offset: float in START_FLAG_OFFSETS:
		for side: float in [-1.0, 1.0]:
			var distance: float = total + offset
			var cell: Vector2i = _free_cell(spline, distance, side,
				reserved, PROP_CLEARANCE)
			if cell == INVALID_CELL:
				continue
			entries.append({"position": _deck_point(cell, spline),
				"kind": START_FLAG, "yaw": 0.0})
			_reserve(reserved, cell, 0)
	for fraction: float in GlacierSurface.boundary_fractions(preset):
		for side: float in [-1.0, 1.0]:
			var cell: Vector2i = _free_cell(spline, total * fraction, side,
				reserved, PROP_CLEARANCE)
			if cell == INVALID_CELL:
				continue
			entries.append({"position": _deck_point(cell, spline),
				"kind": ICE_FLAG, "yaw": 0.0})
			_reserve(reserved, cell, 0)
	# Summit flags: the highest stretch of the lap gets a flag line of its own.
	var summit: float = _highest_distance(spline, total)
	for index in SUMMIT_FLAGS:
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var distance: float = summit + TILE * float(index / 2) * (1.0 \
			if index % 4 < 2 else -1.0)
		var cell: Vector2i = _free_cell(spline, distance, side, reserved,
			PROP_CLEARANCE)
		if cell == INVALID_CELL:
			continue
		entries.append({"position": _deck_point(cell, spline),
			"kind": START_FLAG if index % 2 == 0 else ICE_FLAG, "yaw": 0.0})
		_reserve(reserved, cell, 0)
	if entries.is_empty():
		return 0
	return TileKit.flags(holder, entries)


## Two banner towers either side of the gantry, a pylon at every ice boundary,
## and two billboards out in the run-off.
static func _signage(holder: Node3D, spline: RefCounted, total: float,
		preset: Dictionary, reserved: Dictionary) -> int:
	var entries: Array = []
	for index in START_TOWERS.size():
		var side: float = -1.0 if index == 0 else 1.0
		var cell: Vector2i = _free_cell(spline, 0.0, side, reserved,
			PROP_CLEARANCE)
		if cell == INVALID_CELL:
			continue
		entries.append({"position": _deck_point(cell, spline),
			"kind": START_TOWERS[index], "yaw": 0.0})
		_reserve(reserved, cell, 0)
	var boundaries: PackedFloat32Array = \
		GlacierSurface.boundary_fractions(preset)
	for index in boundaries.size():
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var cell: Vector2i = _free_cell(spline, total * boundaries[index],
			side, reserved, PROP_CLEARANCE)
		if cell == INVALID_CELL:
			continue
		entries.append({"position": _deck_point(cell, spline),
			"kind": ICE_MARKER, "yaw": 0.0})
		_reserve(reserved, cell, 0)
	for fraction: float in [0.33, 0.83]:
		var cell: Vector2i = _free_cell(spline, total * fraction, -1.0,
			reserved, PROP_CLEARANCE + TILE)
		if cell == INVALID_CELL:
			continue
		entries.append({"position": _ground_point(cell, spline),
			"kind": "billboard", "yaw": 0.0})
		_reserve(reserved, cell, 0)
	if entries.is_empty():
		return 0
	return TileKit.signage(holder, entries)


# --------------------------------------------------------------------------
# banks and fences
# --------------------------------------------------------------------------


## Ploughed snow banks outside the barrier, both sides of the whole lap. Every
## boulder is based on the snow (y = 0) so nothing floats, and every one sits
## SNOWBANK_LATERAL from the centreline, which clears the barrier's outer face
## by more than a metre on each side.
static func _snowbanks(holder: Node3D, spline: RefCounted) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var entries: Array = []
	var points: Array = []
	var body: StaticBody3D = GlacierProps.body(holder, "GlacierSnowBanks")
	for side: float in [-1.0, 1.0]:
		var path: Dictionary = GlacierProps.constant_path(spline, side,
			SNOWBANK_LATERAL)
		if not bool(path.get("ok", false)):
			continue
		var length: float = float(path["total_length"])
		var count: int = int(floor(length / SNOWBANK_STEP))
		for index in count:
			if entries.size() >= SNOWBANK_MAX:
				break
			var at: Vector3 = GlacierProps.path_point(path,
				(float(index) + 0.5) * SNOWBANK_STEP)
			var jitter := Vector3(rng.randf_range(-1.2, 1.2), 0.0,
				rng.randf_range(-1.2, 1.2))
			var base := Vector3(at.x + jitter.x, 0.0, at.z + jitter.z)
			if GlacierProps.clearance(spline, base) < 18.2:
				continue
			var model: String = SNOWBANK_MODELS[index \
				% SNOWBANK_MODELS.size()]
			var scale: float = NATURE * rng.randf_range(SNOWBANK_SCALE_MIN,
				SNOWBANK_SCALE_MAX)
			entries.append({"model": model, "nature": true,
				"transform": GlacierProps.fit(model, base,
					rng.randf_range(0.0, TAU), scale, true)})
			points.append(base)
			var plan: Vector2 = GlacierProps.footprint(model, scale, true)
			var height: float = GlacierProps.height(model, scale, true)
			GlacierProps.box(body, base + Vector3.UP * (height * 0.5),
				Vector3(minf(plan.x, 4.2), height, minf(plan.y, 4.2)))
	if entries.is_empty():
		body.free()
		return 0
	GlacierProps.batch(holder, entries, "GlacierSnowBanks", true)
	GlacierProps.assert_clearance("GlacierSnowBanks", points, spline)
	return entries.size()


## Avalanche fencing along the shoulder, following the deck height so the line
## climbs the pass. Pieces are short and only placed where the road is straight
## enough for a straight panel to stay parallel to the barrier.
static func _fences(holder: Node3D, spline: RefCounted) -> int:
	var scale: float = FENCE_LENGTH
	var entries: Array = []
	var points: Array = []
	var body: StaticBody3D = GlacierProps.body(holder, "GlacierFences")
	for side: float in [-1.0, 1.0]:
		var path: Dictionary = GlacierProps.constant_path(spline, side,
			FENCE_LATERAL)
		if not bool(path.get("ok", false)):
			continue
		var length: float = float(path["total_length"])
		var count: int = int(floor(length / FENCE_SPACING))
		for index in count:
			if entries.size() >= FENCE_MAX or index % FENCE_EVERY != 0:
				continue
			var at: float = (float(index) + 0.5) * FENCE_SPACING
			var point: Vector3 = GlacierProps.path_point(path, at)
			var forward: Vector3 = GlacierProps.path_forward(path, at)
			var behind: Vector3 = GlacierProps.path_forward(path,
				at - FENCE_LENGTH * 0.5)
			var ahead: Vector3 = GlacierProps.path_forward(path,
				at + FENCE_LENGTH * 0.5)
			if behind.angle_to(ahead) > FENCE_MAX_TURN:
				continue
			if GlacierProps.clearance(spline, point) < 15.4:
				continue
			var yaw: float = GlacierProps.axis_yaw(FENCE_MODEL, scale,
				forward)
			entries.append({"model": FENCE_MODEL,
				"transform": GlacierProps.fit(FENCE_MODEL, point, yaw,
					scale)})
			points.append(point)
			GlacierProps.box(body, point + Vector3.UP * (FENCE_HEIGHT * 0.5),
				Vector3(FENCE_LENGTH * 0.94, FENCE_HEIGHT, 0.5), yaw)
	if entries.is_empty():
		body.free()
		return 0
	GlacierProps.batch(holder, entries, "GlacierFences", true)
	GlacierProps.assert_clearance("GlacierFences", points, spline)
	return entries.size()


# --------------------------------------------------------------------------
# placement helpers
# --------------------------------------------------------------------------


## Nearest cell centre that clears the barrier and is not reserved, carrying the
## road deck height at that arc position so a prop on the shoulder sits on it.
static func _free_cell(spline: RefCounted, distance: float, side: float,
		reserved: Dictionary, clearance: float) -> Vector2i:
	var total: float = maxf(float(spline.total_length), 1.0)
	var base: float = fposmod(round(distance / QUARTER) * QUARTER, total)
	for step in 5:
		var probe: float = fposmod(base + float(step) * TILE * 0.5, total)
		for lateral_step in 4:
			var lateral: float = TileKit.ROAD_HALF + TileKit.BARRIER_OFFSET \
				+ TILE * (0.65 + 0.55 * float(lateral_step))
			var cell: Vector2i = _cell_of(_sample_point(spline, probe,
				lateral * side))
			if _is_reserved(reserved, cell):
				continue
			if _distance(spline, cell) >= clearance:
				return cell
	return INVALID_CELL


## Longest low/valley straight run of the lap (falling back to overall longest),
## which the split apron is laid along so pit garages sit on the valley floor
## rather than floating off the 9 m summit ridge.
static func _longest_straight(spline: RefCounted) -> Dictionary:
	if spline != null:
		var tiles: Variant = spline.get("tiles")
		if tiles is Array and not (tiles as Array).is_empty():
			var best_low: Dictionary = {}
			var run_from: float = 0.0
			var run_to: float = 0.0
			var in_run: bool = false
			for entry: Variant in tiles as Array:
				if not (entry is Dictionary):
					continue
				var tile: Dictionary = entry as Dictionary
				var kind: String = str(tile.get("tile", ""))
				var straight: bool = kind == "S" or kind == "P" or kind == "E" \
					or kind == "B" or kind == "J"
				var low_deck: bool = float(tile.get("height", 0.0)) <= 2.5
				var from: float = float(tile.get("from", 0.0))
				var to: float = float(tile.get("to", from))
				if straight and low_deck:
					if not in_run:
						run_from = from
						in_run = true
					run_to = to
					continue
				if in_run and run_to - run_from > float(best_low.get("span", 0.0)):
					best_low = {"distance": (run_from + run_to) * 0.5,
						"span": run_to - run_from}
				in_run = false
			if in_run and run_to - run_from > float(best_low.get("span", 0.0)):
				best_low = {"distance": (run_from + run_to) * 0.5,
					"span": run_to - run_from}
			if float(best_low.get("span", 0.0)) >= TILE * 3.0:
				return best_low
	return GlacierProps.longest_straight(spline)

## Lap fraction of the highest deck, sampled finely enough that the summit flag
## line lands on the summit and not next to it.
static func _highest_distance(spline: RefCounted, total: float) -> float:
	var best: float = 0.0
	var best_height: float = -INF
	for index in 96:
		var distance: float = total * float(index) / 96.0
		var height: float = _deck_at(spline, distance)
		if height > best_height:
			best_height = height
			best = distance
	return best


static func _deck_at(spline: RefCounted, distance: float) -> float:
	var frame: Dictionary = spline.sample(distance)
	return (frame["position"] as Vector3).y


## Cell centre at the road deck height, for a prop that belongs to the road
## (flags, signage, gantry-adjacent towers).
static func _deck_point(cell: Vector2i, spline: RefCounted) -> Vector3:
	var point: Vector3 = _cell_point(cell)
	point.y = _deck_at(spline, _distance_of(spline, point))
	return point


## Cell centre on the flat snow, for a prop that stands on the ground.
static func _ground_point(cell: Vector2i, _spline: RefCounted) -> Vector3:
	return _cell_point(cell)


static func _distance_of(spline: RefCounted, point: Vector3) -> float:
	if spline.has_method("plan_closest"):
		var hit: Dictionary = spline.call("plan_closest", point) as Dictionary
		return float(hit.get("s", 0.0))
	return float((spline.closest(point) as Dictionary).get("s", 0.0))


## Cell centre for a grid cell, matching TileKit's convention.
static func _cell_point(cell: Vector2i) -> Vector3:
	return Vector3((float(cell.x) + 0.5) * TILE, 0.0,
		(float(cell.y) + 0.5) * TILE)


## Cell a world point falls in, matching TileKit's snapping.
static func _cell_of(point: Vector3) -> Vector2i:
	return Vector2i(int(floor(point.x / TILE)), int(floor(point.z / TILE)))


## Plan position on the centreline plus a lateral offset, flattened to y = 0.
static func _sample_point(spline: RefCounted, distance: float,
		lateral: float) -> Vector3:
	var frame: Dictionary = spline.sample(distance)
	var position: Vector3 = frame["position"]
	var right: Vector3 = frame["right"]
	var point: Vector3 = position + right * lateral
	point.y = 0.0
	return point


## Distance from a cell centre to the centreline.
static func _distance(spline: RefCounted, cell: Vector2i) -> float:
	return TileKit.spline_distance(spline, _cell_point(cell))


static func _reserve(reserved: Dictionary, cell: Vector2i, radius: int) -> void:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			reserved[Vector2i(cell.x + dx, cell.y + dy)] = true


static func _is_reserved(reserved: Dictionary, cell: Vector2i) -> bool:
	return reserved.has(cell)


## One MultiMesh per model part: barrier runs, two stands, the gantry, the light
## batch, one per flag model, one per sign model, the bank models, the fence and
## the split pieces.
static func _draw_estimate(stats: Dictionary) -> int:
	var draws: int = 0
	if int(stats["barriers"]) > 0:
		draws += 4
	if int(stats["stands"]) > 0:
		draws += STAND_MODELS.size()
	draws += int(stats["gantry"])
	if int(stats["split"]) > 0:
		draws += 3
	if int(stats["lights"]) > 0:
		draws += 1
	if int(stats["flags"]) > 0:
		draws += 4
	if int(stats["signage"]) > 0:
		draws += START_TOWERS.size() + 2
	if int(stats["snowbanks"]) > 0:
		draws += SNOWBANK_MODELS.size()
	if int(stats["fences"]) > 0:
		draws += 1
	return draws
