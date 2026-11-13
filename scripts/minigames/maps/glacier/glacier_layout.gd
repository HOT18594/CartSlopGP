extends RefCounted
## Trackside dressing for the Glacier Pass grid map.
##
## Every solid piece is placed through scripts/minigames/tile_kit.gd, which
## owns the batching and the WORLD colliders:
##   * a continuous red barrier ring on both sides of the lane,
##   * two grandstands (one covered) facing opposite straights,
##   * an overhead start gantry, eight floodlight posts,
##   * checkered start flags and red ice-warning flags,
##   * start banner towers and ice warning pylons,
##   * snowbank boulders around the outside of the four tightest corners,
##   * a four-cell-deep pine band packed outside the loop's plan bounds.
##
## Grid discipline is inherited from TileKit (quarter-tile arc distances,
## half-metre lateral offsets, cell-centre props) plus the reservation table
## below: a structure claims its cells before the foliage pass, so two props can
## never be planted in the same 16 m cell. The pine band only uses cells outside
## the loop's plan bounds, which is what guarantees it sits outside the barrier
## ring rather than in the infield.
##
## Returns the build statistics the theme prints and stores as race metadata.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const GlacierSurface := preload("res://scripts/minigames/maps/glacier/glacier_surface.gd")

const TILE: float = TileKit.TILE_SIZE
const ROAD_HALF: float = TileKit.ROAD_HALF
const QUARTER: float = TileKit.SNAP_STEP

const BARRIER_KIND: String = "barrierRed"
const START_FLAG: String = "flagCheckers"
const ICE_FLAG: String = "flagRed"
const ICE_MARKER: String = "pylon"
const START_TOWERS: Array[String] = ["bannerTowerRed", "bannerTowerGreen"]

## Pine band models. The nature kit's pines are the only trees on the map.
const PINE_MODELS: Array[String] = [
	"tree_pineTallA", "tree_pineTallB", "tree_pineTallC", "tree_pineTallD",
	"tree_pineSmallA", "tree_pineSmallB", "tree_pineRoundA",
]
## Snowbank boulders. The kit has no snow-specific block, so the coldest rock
## shapes stand in for ploughed banks; they read as ice-grey against the snow.
const SNOWBANK_MODELS: Array[String] = [
	"rock_largeA", "rock_largeB", "rock_largeF", "rock_tallA",
]

## How many cells of pine forest ring the loop.
const PINE_BAND: int = 4
## Fraction of eligible cells left empty so the forest edge is not a perfect
## checkerboard.
const PINE_SKIP: float = 0.04
const TREE_SCALE_MIN: float = 0.85
const TREE_SCALE_MAX: float = 1.15
const SNOWBANK_SCALE_MIN: float = 0.55
const SNOWBANK_SCALE_MAX: float = 0.85
const SNOWBANKS_PER_CORNER: int = 6
const CORNER_COUNT: int = 4
const CURVE_THRESHOLD: float = 0.02
const CURVE_WINDOW: float = 5.0

## Floodlight spacing. Every post sits on the outside of the loop.
const LIGHT_FRACTIONS: Array[float] = [
	0.06, 0.18, 0.31, 0.42, 0.66, 0.78, 0.88, 0.96,
]
const LIGHT_SIDE: float = -1.0

## Start flags sit one tile before and after the line so they flank the grid.
const START_FLAG_OFFSETS: Array[float] = [TILE, -TILE]

## Clearance a foliage cell centre needs from the centreline, in metres. It is
## wider than TileKit's own 12.7 m rejection radius so the kit never has to skip
## (and warn about) a position this module proposed.
const FOLIAGE_CLEARANCE: float = ROAD_HALF + TILE * 0.5
## Clearance for an upright prop. The barrier's outer face is about 7.5 m from
## the centreline, so 8.2 m keeps a post or flag pole clear of it.
const PROP_CLEARANCE: float = ROAD_HALF + TileKit.BARRIER_OFFSET + 1.8
## Boulders are wider than a post, but a bank cell just outside the barrier is
## safe: TileKit rejects foliage under 12.72 m and a bank collider is at most
## ~3.5 m across, so 12.9 m leaves the barrier face untouched.
const SNOWBANK_CLEARANCE: float = ROAD_HALF + TILE * 0.46

const INVALID_CELL: Vector2i = Vector2i(-999999, -999999)
const SEED: int = 20261113


## Builds the whole trackside pass under `holder` and returns the statistics.
static func build(holder: Node3D, spline: RefCounted,
		preset: Dictionary) -> Dictionary:
	var stats: Dictionary = {
		"barriers": 0, "stands": 0, "gantry": 0, "lights": 0, "flags": 0,
		"signage": 0, "snowbanks": 0, "pines": 0, "objects": 0, "draws": 0,
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
	# 3. Lamps, flags and signage fill the trackside cells.
	stats["lights"] = _lights(holder, spline, total, reserved)
	stats["flags"] = _flags(holder, spline, total, preset, reserved)
	stats["signage"] = _signage(holder, spline, total, preset, reserved)
	# 4. Foliage last, on the cells nobody claimed.
	stats["snowbanks"] = _snowbanks(holder, spline, reserved)
	stats["pines"] = _pines(holder, spline, reserved)
	stats["objects"] = int(stats["barriers"]) + int(stats["stands"]) \
		+ int(stats["gantry"]) + int(stats["lights"]) + int(stats["flags"]) \
		+ int(stats["signage"]) + int(stats["snowbanks"]) + int(stats["pines"])
	stats["draws"] = _draw_estimate(stats)
	return stats


# --------------------------------------------------------------------------
# barrier ring


## Two continuous barrier runs per side. A full-lap span wraps to a near-zero
## arc length inside TileKit's snapping, so the ring is split at the last
## quarter-tile seam and the final short run carries the line across the start.
static func _barrier_ring(holder: Node3D, spline: RefCounted,
		total: float) -> int:
	var seam: float = fposmod(round((total - TILE * 0.5) / QUARTER) * QUARTER,
		total)
	if seam < TILE:
		seam = fposmod(round(total * 0.5 / QUARTER) * QUARTER, total)
	var placed: int = 0
	for side: float in [-1.0, 1.0]:
		placed += TileKit.barrier_line(holder, spline, 0.0, seam, side,
			BARRIER_KIND)
		placed += TileKit.barrier_line(holder, spline, seam, total, side,
			BARRIER_KIND)
	return placed


# --------------------------------------------------------------------------
# structures


## One covered stand on the start straight and one open stand on the back
## straight. The helper faces both at the track from the requested side.
static func _grandstands(holder: Node3D, spline: RefCounted, total: float,
		reserved: Dictionary) -> int:
	var specs: Array[Dictionary] = [
		{"fraction": 0.18, "side": 1.0, "covered": true},
		{"fraction": 0.55, "side": -1.0, "covered": false},
	]
	var placed: int = 0
	for spec: Dictionary in specs:
		var distance: float = total * float(spec["fraction"])
		var side: float = float(spec["side"])
		var anchor: Vector3 = _sample_point(spline, distance,
			TileKit.STAND_OFFSET * side)
		_reserve(reserved, _cell_of(anchor), 1)
		placed += TileKit.grandstand(holder, spline, distance, side,
			bool(spec["covered"]))
	return placed


# --------------------------------------------------------------------------
# small props


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
		positions.append(_cell_point(cell))
		_reserve(reserved, cell, 1)
	if positions.is_empty():
		return 0
	return TileKit.lights(holder, positions)


## Checkered flags flanking the start, then a red flag on both sides of every
## ice boundary so the slippery section is announced before the grip drops.
static func _flags(holder: Node3D, spline: RefCounted, total: float,
		preset: Dictionary, reserved: Dictionary) -> int:
	var entries: Array = []
	for offset: float in START_FLAG_OFFSETS:
		for side: float in [-1.0, 1.0]:
			var cell: Vector2i = _free_cell(spline, total + offset, side,
				reserved, PROP_CLEARANCE)
			if cell == INVALID_CELL:
				continue
			entries.append({"position": _cell_point(cell),
				"kind": START_FLAG, "yaw": 0.0})
			_reserve(reserved, cell, 0)
	for fraction: float in GlacierSurface.boundary_fractions(preset):
		for side: float in [-1.0, 1.0]:
			var cell: Vector2i = _free_cell(spline, total * fraction, side,
				reserved, PROP_CLEARANCE)
			if cell == INVALID_CELL:
				continue
			entries.append({"position": _cell_point(cell),
				"kind": ICE_FLAG, "yaw": 0.0})
			_reserve(reserved, cell, 0)
	if entries.is_empty():
		return 0
	return TileKit.flags(holder, entries)


## Two banner towers either side of the gantry and a pylon at every ice
## boundary, alternating sides so the markers never mirror each other.
static func _signage(holder: Node3D, spline: RefCounted, total: float,
		preset: Dictionary, reserved: Dictionary) -> int:
	var entries: Array = []
	for index in START_TOWERS.size():
		var side: float = -1.0 if index == 0 else 1.0
		var cell: Vector2i = _free_cell(spline, 0.0, side, reserved,
			PROP_CLEARANCE)
		if cell == INVALID_CELL:
			continue
		entries.append({"position": _cell_point(cell),
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
		entries.append({"position": _cell_point(cell), "kind": ICE_MARKER,
			"yaw": 0.0})
		_reserve(reserved, cell, 0)
	if entries.is_empty():
		return 0
	return TileKit.signage(holder, entries)


# --------------------------------------------------------------------------
# foliage


## Boulders banked around the outside of the four tightest corners. The bank is
## a block of cells just beyond the barrier on the corner's outside, so it hugs
## the run-off without ever reaching the lane.
static func _snowbanks(holder: Node3D, spline: RefCounted,
		reserved: Dictionary) -> int:
	var corners: Array[Dictionary] = _corners(spline)
	var entries: Array = []
	for corner: Dictionary in corners:
		var distance: float = float(corner["d"])
		var outside: float = 1.0 if float(corner["curve"]) > 0.0 else -1.0
		var corner_cell: Vector2i = _cell_of(_sample_point(spline, distance,
			0.0))
		var outside_cell: Vector2i = corner_cell
		for lateral_tiles: float in [1.15, 1.8, 2.5]:
			outside_cell = _cell_of(_sample_point(spline, distance,
				(ROAD_HALF + TILE * lateral_tiles) * outside))
			if outside_cell != corner_cell:
				break
		var candidates: Array[Vector2i] = []
		for step_x in range(-1, 2):
			for step_z in range(-1, 2):
				candidates.append(Vector2i(outside_cell.x + step_x,
					outside_cell.y + step_z))
		var cells: Array[Vector2i] = []
		for cell: Vector2i in candidates:
			if cells.has(cell) or _is_reserved(reserved, cell):
				continue
			if _distance(spline, cell) < SNOWBANK_CLEARANCE:
				continue
			cells.append(cell)
		var take: int = mini(cells.size(), SNOWBANKS_PER_CORNER)
		for index in take:
			var cell: Vector2i = cells[index]
			var model: String = SNOWBANK_MODELS[index % SNOWBANK_MODELS.size()]
			var scale: float = SNOWBANK_SCALE_MIN \
				+ (SNOWBANK_SCALE_MAX - SNOWBANK_SCALE_MIN) \
				* float((index * 37 + int(distance)) % 100) / 100.0
			entries.append({"position": _cell_point(cell), "kind": model,
				"scale": scale})
			_reserve(reserved, cell, 0)
	if entries.is_empty():
		return 0
	return TileKit.trees(holder, entries, spline)


## Pines packed outside the loop's plan bounds. A cell inside the bounds is the
## track or its infield, so skipping the bounds rectangle is what keeps every
## pine outside the barrier ring. TileKit batches them per model and gives each
## trunk a cylinder on WORLD.
static func _pines(holder: Node3D, spline: RefCounted,
		reserved: Dictionary) -> int:
	var bounds: Rect2i = _plan_bounds(spline)
	var entries: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var min_col: int = bounds.position.x - PINE_BAND
	var max_col: int = bounds.position.x + bounds.size.x - 1 + PINE_BAND
	var min_row: int = bounds.position.y - PINE_BAND
	var max_row: int = bounds.position.y + bounds.size.y - 1 + PINE_BAND
	for row in range(min_row, max_row + 1):
		for col in range(min_col, max_col + 1):
			var cell := Vector2i(col, row)
			if bounds.has_point(cell):
				continue
			if _is_reserved(reserved, cell):
				continue
			if _distance(spline, cell) < FOLIAGE_CLEARANCE:
				continue
			if rng.randf() < PINE_SKIP:
				continue
			var model: String = PINE_MODELS[_cell_hash(cell) \
				% PINE_MODELS.size()]
			var scale: float = TREE_SCALE_MIN \
				+ (TREE_SCALE_MAX - TREE_SCALE_MIN) \
				* float(_cell_hash(cell + Vector2i(13, 29)) % 100) / 100.0
			entries.append({"position": _cell_point(cell), "kind": model,
				"scale": scale})
	if entries.is_empty():
		return 0
	return TileKit.trees(holder, entries, spline)


# --------------------------------------------------------------------------
# corner detection


## The bends that get a snowbank. A grid spline names its corner tiles exactly,
## so those are used; the legacy spline is scanned for curvature instead. The
## sign of the curve says which side is outside (TileKit's side -1 is the left).
static func _corners(spline: RefCounted) -> Array[Dictionary]:
	var corners: Array[Dictionary] = []
	var tiles: Variant = spline.get("tiles")
	if tiles is Array and not (tiles as Array).is_empty():
		for tile: Variant in tiles as Array:
			if not (tile is Dictionary):
				continue
			var data: Dictionary = tile as Dictionary
			var tile_char: String = str(data.get("tile", ""))
			if tile_char != "L" and tile_char != "R" and tile_char != "W":
				continue
			var from: float = float(data.get("from", 0.0))
			var to: float = float(data.get("to", from))
			var mid: float = (from + to) * 0.5
			var curve: float = _curve(spline, mid)
			if absf(curve) < 0.001:
				curve = -0.1
			corners.append({"d": mid, "curve": curve})
		return corners
	return _tight_corners(spline)


## The tightest bends, spaced apart so one corner never gets two banks. Used
## only for a spline without tile data.
static func _tight_corners(spline: RefCounted) -> Array[Dictionary]:
	var total: float = maxf(float(spline.total_length), 1.0)
	var candidates: Array[Dictionary] = []
	var step: float = TILE * 0.5
	var distance: float = step
	while distance < total - step:
		var curve: float = _curve(spline, distance)
		if absf(curve) >= CURVE_THRESHOLD:
			candidates.append({"d": distance, "curve": curve})
		distance += step
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a["curve"])) > absf(float(b["curve"])))
	var chosen: Array[Dictionary] = []
	var spacing: float = maxf(total * 0.10, TILE * 3.0)
	for candidate: Dictionary in candidates:
		var ok: bool = true
		for other: Dictionary in chosen:
			var raw: float = absf(fposmod(float(candidate["d"])
				- float(other["d"]), total))
			if minf(raw, total - raw) < spacing:
				ok = false
				break
		if ok:
			chosen.append(candidate)
		if chosen.size() >= CORNER_COUNT:
			break
	return chosen


## Signed curvature at an arc-length position, in radians per metre. Negative
## means a right-hand bend, which is the side TileKit calls the left.
static func _curve(spline: RefCounted, distance: float) -> float:
	var before: float = float(spline.yaw_at(distance - CURVE_WINDOW))
	var after: float = float(spline.yaw_at(distance + CURVE_WINDOW))
	return wrapf(after - before, -PI, PI) / (CURVE_WINDOW * 2.0)


# --------------------------------------------------------------------------
# grid helpers


## Nearest cell centre that clears the barrier and is not reserved. The search
## walks a few quarter tiles along the track and then steps outwards, so a
## boundary marker shifts rather than overlapping a light or a stand.
static func _free_cell(spline: RefCounted, distance: float, side: float,
		reserved: Dictionary, clearance: float) -> Vector2i:
	var total: float = maxf(float(spline.total_length), 1.0)
	var base: float = fposmod(round(distance / QUARTER) * QUARTER, total)
	for step in 5:
		var probe: float = fposmod(base + float(step) * TILE * 0.5, total)
		for lateral_step in 3:
			var lateral: float = TileKit.ROAD_HALF + TileKit.BARRIER_OFFSET \
				+ TILE * (0.55 + 0.5 * float(lateral_step))
			var cell: Vector2i = _cell_of(_sample_point(spline, probe,
				lateral * side))
			if _is_reserved(reserved, cell):
				continue
			if _distance(spline, cell) >= clearance:
				return cell
	return INVALID_CELL


## Plan bounds of the loop in cells. The grid spline exposes its placed tiles;
## the legacy spline is bounded from its sampled points. Either way the result
## is the rectangle the pine band must stay outside of.
static func _plan_bounds(spline: RefCounted) -> Rect2i:
	var min_col: int = 1 << 30
	var min_row: int = 1 << 30
	var max_col: int = -(1 << 30)
	var max_row: int = -(1 << 30)
	var tiles: Variant = spline.get("tiles")
	if tiles is Array and not (tiles as Array).is_empty():
		for tile: Variant in tiles as Array:
			if not (tile is Dictionary):
				continue
			var cell: Variant = (tile as Dictionary).get("cell")
			if cell is Vector2i:
				var key: Vector2i = cell
				min_col = mini(min_col, key.x)
				min_row = mini(min_row, key.y)
				max_col = maxi(max_col, key.x)
				max_row = maxi(max_row, key.y)
	else:
		var points: Variant = spline.get("points")
		if points is PackedVector3Array:
			for point: Vector3 in points as PackedVector3Array:
				var cell: Vector2i = _cell_of(point)
				min_col = mini(min_col, cell.x)
				min_row = mini(min_row, cell.y)
				max_col = maxi(max_col, cell.x)
				max_row = maxi(max_row, cell.y)
	if min_col > max_col or min_row > max_row:
		return Rect2i(-PINE_BAND, -PINE_BAND, PINE_BAND * 2 + 1,
			PINE_BAND * 2 + 1)
	return Rect2i(min_col, min_row, max_col - min_col + 1,
		max_row - min_row + 1)


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


## Deterministic per-cell hash used for model and scale variety, so a rebuild
## produces exactly the same forest.
static func _cell_hash(cell: Vector2i) -> int:
	return absi(cell.x * 73856093 + cell.y * 19349663)


static func _reserve(reserved: Dictionary, cell: Vector2i, radius: int) -> void:
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			reserved[Vector2i(cell.x + dx, cell.y + dy)] = true


static func _is_reserved(reserved: Dictionary, cell: Vector2i) -> bool:
	return reserved.has(cell)


## One MultiMesh per model part: barrier runs, two unique stands, the gantry,
## one light batch, one batch per flag model, one per sign model and one per
## foliage model.
static func _draw_estimate(stats: Dictionary) -> int:
	var draws: int = 0
	if int(stats["barriers"]) > 0:
		draws += 4
	draws += int(stats["stands"]) + int(stats["gantry"])
	if int(stats["lights"]) > 0:
		draws += 1
	if int(stats["flags"]) > 0:
		draws += 4
	if int(stats["signage"]) > 0:
		draws += START_TOWERS.size() + 1
	if int(stats["snowbanks"]) > 0:
		draws += SNOWBANK_MODELS.size()
	if int(stats["pines"]) > 0:
		draws += PINE_MODELS.size()
	return draws
