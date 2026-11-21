extends RefCounted
## Designed treeline, scrub and underbrush for the Dockyard Quay theme.
##
## A working port is not a park, so the green here is authored, not sprinkled:
##
##   * one continuous belt of trees outside the catch fence, four metres past the
##     fence line and thirty-six metres deep, packed by three octaves of value
##     noise plus a minimum spacing so it reads as stands and clearings rather
##     than an even scatter; the outer edge is noise-ragged so the horizon is a
##     bay line instead of a surveyed rectangle;
##   * the belt is biased to the fence line (a hedge the port can actually own),
##     to the longest straight's midpoint (a framed vista gap with tall trees
##     either side), away from the four grandstands (the crowd must be visible)
##     and towards the tightest corner (a thicket closes that view);
##   * a few windswept trees INSIDE the site, in the concrete pockets the yard
##     leaves between container rows, deliberately sparse so the dock still reads
##     as a dock;
##   * undergrowth at four depths: bramble clumps on the outboard face of the
##     real catch-fence panels, a scrub row at the foot of the treeline, a skirt
##     around every trunk, and a low skirt around each in-site tree.
##
## Placement rules, in order of authority:
##   1. every instance is at least TREE_CLEARANCE / SCRUB_CLEARANCE metres from
##      the centreline, so nothing can reach the barrier ring or the road;
##   2. a candidate is kept RESERVED_INSIDE / RESERVED_OUTSIDE metres off the
##      cells the yard dressed outside the fence (offices, containers, cranes,
##      mooring clutter, signage), so no canopy grows through a prop;
##   3. band candidates are seated on a jittered 4.2 m lattice and thinned by a
##      greedy minimum-spacing pass, so stands are dense and gaps stay real.
##
## Cost: one MultiMesh per species per band side (eleven batches for the band,
## eight for the scrub, two for the in-site trees), never a node per tree. Each
## batch carries a visibility range and chunks by side, so the renderer can drop
## the band behind the camera; the single shared trunk body keeps physics to one
## broadphase island.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const Parts := preload("res://scripts/minigames/maps/dockyard/dockyard_parts.gd")
## The yard publishes the cells it left empty for the in-site trees; reading the
## key from the yard keeps the two passes from drifting apart.
const DockyardYard := preload("res://scripts/minigames/maps/dockyard/dockyard_yard.gd")

## Metres per model unit for the two kits. Nature trees are authored ~1.5 units
## tall (a 10-12 m tree), racing kit trees are authored at 16 m.
const NATURE: float = TileKit.NATURE_SCALE
const PROP: float = TileKit.PROP_SCALE
const TILE: float = TileKit.TILE_SIZE

# --------------------------------------------------------------------------
# belt geometry

## The belt starts this far outside the catch-fence rectangle. The fence ring is
## one lattice cell deep, so four metres keeps the first row out of the panels
## while leaving room for the fence-foot brambles.
const BAND_INNER: float = 4.0
## How deep the belt runs on the land sides, and how deep the seaward side runs.
## The quay side is thinner on purpose: cranes and mooring keep that horizon
## industrial instead of wooded.
const BAND_DEPTH: float = 36.0
const BAND_DEPTH_QUAY: float = 30.0
## Candidate lattice and how far a candidate may wander from it. 4.2 m against
## the 3.0 m minimum spacing gives roughly two candidates per accepted tree, so
## the noise field has room to carve stands and clearings.
const CANDIDATE_STEP: float = 4.2
const CANDIDATE_JITTER: float = 2.0
const MIN_SPACING: float = 3.0
## Band trees wanted. The in-site windswept trees are on top of this.
const TREE_TARGET: int = 330
## Share of the target each band side takes: north, east, south (harbour water = 0), west.
const SIDE_SHARE: Array[float] = [0.38, 0.28, 0.0, 0.34]
## Hard clearance from the centreline: barrier clearance (8.02 m) plus a full
## tree canopy and the fence itself. The belt's inner edge lands near 28 m on
## this layout, so the number only matters on the legacy spline fallback.
const TREE_CLEARANCE: float = TileKit.ROAD_HALF + 11.0
const SCRUB_CLEARANCE: float = TileKit.ROAD_HALF + 6.5
## A band candidate may not stand this close to a dressed cell outside the fence.
## In-grid claims are the outer-band offices/containers, and a cell footprint is
## 16 m wide, so 8.5 m keeps a canopy off one. Off-grid claims are the sparse
## quay posts, bollards, lamps and mooring clutter: those are small, and a five
## metre margin is enough to keep a trunk out of a post while still letting the
## belt share their rings. Crane bases are published separately because a boom
## reaches 11 m.
const RESERVED_INSIDE: float = 8.5
const RESERVED_OUTSIDE: float = 5.0
const CRANE_CLEAR: float = 14.0

# --------------------------------------------------------------------------
# design modifiers

## Depth of the fence-line hedge bonus, and how strongly it pulls the belt's
## inner edge into a continuous row.
const EDGE_DEPTH: float = 14.0
const EDGE_BONUS: float = 0.22
## The outer edge of the belt is noise-ragged by up to this many metres, so the
## treeline has bays and points instead of a surveyed rectangle.
const OUTER_RAGGED: float = 12.0
const OUTER_TAPER: float = 10.0
const OUTER_PENALTY: float = 0.20
## The side opposite the pits grows the visual-break forest.
const GREEN_BONUS: float = 0.11
## Radius and strength of the thicket behind the tightest corner.
const THICKET_RADIUS: float = 34.0
const THICKET_BONUS: float = 0.30
## Seaward thinning so the quay horizon stays open.
const QUAY_PENALTY: float = 0.06
## Clearings at the grandstands and at the framed long straight: no tree inside
## the radius, a denser frame ring just outside it.
const STAND_CLEARING: float = 19.0
const VISTA_CLEARING: float = 15.0
const VISTA_OFFSET: float = 20.0
const FRAME_RING: float = 16.0
const FRAME_BONUS: float = 0.16

# --------------------------------------------------------------------------
# in-site trees and undergrowth

const YARD_TREE_LIMIT: int = 14
## A pocket cell on this pinched layout sits 16-23 m from the centreline, so the
## in-site tree is allowed that close: the barrier is at 8.02 m and a 4 m canopy
## still clears it. The band trees keep the wider TREE_CLEARANCE.
const YARD_CLEARANCE: float = TileKit.ROAD_HALF + 9.5
const YARD_STAND_CLEAR: float = 16.0
## Uniform wind direction for the in-site trees and the bent-palm species; the
## quay's dominant onshore breeze, matching the flags on the apron.
const WIND_YAW: float = 0.62
const CLUMP_CHANCE: float = 0.38
const CLUMP_REACH: float = 4.2
## Both fence scrub layers sit around the one-cell ring the catch fence occupies.
## A ring cell can also hold a container or a floodlight, so brambles are only
## grown in the cells dockyard_yard actually put a panel in, and a front scrub
## row outside the belt edge carries the texture on the rest of the perimeter.
const FENCE_BRAMBLES: int = 3
const FENCE_SCRUB_LATERAL: float = 5.0
const FENCE_SCRUB_INNER: float = 1.8
const FENCE_SCRUB_OUTER: float = 6.0
const FRONT_SCRUB_STEP: float = 4.5
const FRONT_SCRUB_INNER: float = 3.0
const FRONT_SCRUB_OUTER: float = 11.0
const FRONT_SCRUB_LIMIT: int = 90
## Scrub keeps this far from a dressed cell centre, so a bush never grows out of
## a bollard, a sign post or a wharf pad. A fence cell only holds the thin panel,
## so its radius is just wide enough to keep off the post.
const SCRUB_PROP_RADIUS: float = 3.2
const FENCE_POST_RADIUS: float = 1.6
const SCRUB_SPACING: float = 2.8
const TREE_RANGE: float = 260.0
const SCRUB_RANGE: float = 150.0
const YARD_TREE_RANGE: float = 220.0

const SEED: int = 260314

## Tree species keyed by the palette name used by the band sides. The band mixes
## seven nature-kit stems with the racing kit's `treeLarge` / `treeSmall`, so the
## port edge reads as a mixed stand instead of one cloned model. The `_dark` and
## `_fall` stems are the colour-variation stand-ins: Kenney bakes bark and leaf
## colours into two flat surfaces, so an instance tint would discolour both.
const SPECIES: Dictionary = {
	"pineTallA": {"model": "tree_pineTallA", "racing": false, "low": 0.80,
		"high": 1.24},
	"pineTallB": {"model": "tree_pineTallB", "racing": false, "low": 0.78,
		"high": 1.20},
	"thin": {"model": "tree_thin", "racing": false, "low": 0.82,
		"high": 1.26},
	"simple": {"model": "tree_simple", "racing": false, "low": 0.86,
		"high": 1.30},
	"tall": {"model": "tree_tall", "racing": false, "low": 0.82,
		"high": 1.20},
	"oak": {"model": "tree_oak", "racing": false, "low": 0.82, "high": 1.22},
	"oakDark": {"model": "tree_oak_dark", "racing": false, "low": 0.80,
		"high": 1.18},
	"palm": {"model": "tree_palm", "racing": false, "low": 0.80, "high": 1.10},
	"racingLarge": {"model": "treeLarge", "racing": true, "low": 0.34,
		"high": 0.52},
	"racingSmall": {"model": "treeSmall", "racing": true, "low": 0.40,
		"high": 0.62},
	"yardPalm": {"model": "tree_palmBend", "racing": false, "low": 0.95,
		"high": 1.20},
	"yardThin": {"model": "tree_thin", "racing": false, "low": 0.98,
		"high": 1.26},
}

## Undergrowth species. Bushes, bramble and grass only: the quay has no ferns in
## the kit, and porcelain flowers on a dock read wrong.
const SCRUB: Dictionary = {
	"bushLarge": {"model": "plant_bushLarge", "low": 0.34, "high": 0.62},
	"bushDetailed": {"model": "plant_bushDetailed", "low": 0.30,
		"high": 0.55},
	"grassLarge": {"model": "grass_large", "low": 0.28, "high": 0.52},
	"flatTall": {"model": "plant_flatTall", "low": 0.30, "high": 0.58},
	"flatShort": {"model": "plant_flatShort", "low": 0.30, "high": 0.55},
}

## Species on each band side: north (pines with the racing kit's big tree),
## east (the small racing tree), south (palms, the quay read), west (broadleaf
## with the dark oak for colour variation). The first key is the tall frame
## species used by the designed vista and thicket seats.
const SIDE_SPECIES: Array = [
	["pineTallA", "thin", "racingLarge"],
	["pineTallB", "simple", "racingSmall"],
	["palm", "thin"],
	["oak", "tall", "oakDark"],
]
const SIDE_SCRUB: Array = [
	["bushLarge", "grassLarge"],
	["bushDetailed", "flatTall"],
	["bushLarge", "flatShort"],
	["bushDetailed", "grassLarge"],
]


## Builds the belt, the in-site trees and the undergrowth, returning
## {objects, draws, trees, undergrowth, trunks, surfaces}.
static func build(parent: Node3D, spline: RefCounted,
		plan: RefCounted) -> Dictionary:
	var stats: Dictionary = {"objects": 0, "draws": 0, "trees": 0,
		"undergrowth": 0, "trunks": 0, "surfaces": 0, "clearings": 0}
	if parent == null or spline == null or plan == null:
		return stats
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var fence: Rect2 = _fence_rect(plan)
	var reserved: Dictionary = _reserved_points(plan, fence)
	var design: Dictionary = _design(spline, plan, fence)
	stats["clearings"] = (design["clearings"] as Array).size()
	var trees: Array = _select_trees(spline, plan, fence, reserved, design, rng)
	_scatter_trees(trees, fence, rng)
	var yard: Array = _yard_trees(spline, plan, fence, design, rng)
	for entry: Dictionary in yard:
		entry["key"] = "yardPalm" if int(entry["index"]) % 2 == 0 \
			else "yardThin"
		entry["yaw"] = WIND_YAW + rng.randf_range(-0.22, 0.22)
		entry["scale"] = NATURE * rng.randf_range(0.98, 1.24)
		entry["size"] = _size(SPECIES[str(entry["key"])],
			float(entry["scale"]))
	var scrub: Array = _scrub_points(trees, yard, spline, plan, fence, rng,
		stats)
	var trunk_body := Parts.body(parent, "DockyardForestTrunks")
	_emit_trees(parent, trees, stats)
	_emit_yard_trees(parent, yard, stats)
	_emit_scrub(parent, scrub, stats)
	stats["trees"] = trees.size() + yard.size()
	stats["undergrowth"] = scrub.size()
	stats["trunks"] = trees.size() + yard.size()
	stats["objects"] = int(stats["trees"]) + int(stats["undergrowth"])
	for tree: Dictionary in trees:
		_trunk(trunk_body, tree)
	for entry: Dictionary in yard:
		_trunk(trunk_body, entry)
	return stats


# --------------------------------------------------------------------------
# fence rectangle and band geometry


## The port fence rectangle in plan view: one cell outside the track box, which
## is where the yard lays the catch fence. It is the boundary the treeline must
## stay outside, and it is measured from the real ring cells so a layout edit
## moves the belt with the track.
static func _fence_rect(plan: RefCounted) -> Rect2:
	var cells: Array = plan.ring_cells()
	if not cells.is_empty():
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for entry: Variant in cells:
			if not (entry is Vector2i):
				continue
			var point: Vector3 = plan.cell_point(entry as Vector2i)
			low = Vector2(minf(low.x, point.x), minf(low.y, point.z))
			high = Vector2(maxf(high.x, point.x), maxf(high.y, point.z))
		var half: float = TILE * 0.5
		return Rect2(low - Vector2(half, half), high - low + Vector2(TILE, TILE))
	# Legacy spline fallback: bound the control points and add a fence verge so
	# the belt still starts outside whatever ribbon the race painted.
	var raw: Variant = plan.spline.get("points")
	if raw is PackedVector3Array:
		var points: PackedVector3Array = raw
		if not points.is_empty():
			var low := Vector2(points[0].x, points[0].z)
			var high := low
			for point: Vector3 in points:
				low = Vector2(minf(low.x, point.x), minf(low.y, point.z))
				high = Vector2(maxf(high.x, point.x), maxf(high.y, point.z))
			return Rect2(low, high - low).grow(TILE * 0.75)
	return Rect2(-64.0, -64.0, 128.0, 128.0)


## One rectangular slice of the belt for a side: 0 north, 1 east, 2 south,
## 3 west. North and south own the corners; east and west start past them.
static func _side_box(fence: Rect2, side: int) -> Rect2:
	match side:
		0:
			return Rect2(fence.position.x - BAND_DEPTH, fence.position.y
				- BAND_DEPTH, fence.size.x + BAND_DEPTH * 2.0,
				BAND_DEPTH - BAND_INNER)
		1:
			return Rect2(fence.end.x + BAND_INNER, fence.position.y
				- BAND_INNER, BAND_DEPTH - BAND_INNER, fence.size.y
				+ BAND_INNER * 2.0)
		2:
			return Rect2(fence.position.x - BAND_DEPTH, fence.end.y
				+ BAND_INNER, fence.size.x + BAND_DEPTH * 2.0,
				BAND_DEPTH_QUAY - BAND_INNER)
		_:
			return Rect2(fence.position.x - BAND_DEPTH, fence.position.y
				- BAND_INNER, BAND_DEPTH - BAND_INNER, fence.size.y
				+ BAND_INNER * 2.0)


static func _side_depth(side: int) -> float:
	return BAND_DEPTH_QUAY if side == 2 else BAND_DEPTH


## Depth at which a side's belt ends at `point`. A low-frequency noise pulls the
## limit in and out by OUTER_RAGGED metres, so the horizon edge is a natural bay
## line rather than the side box's rectangle.
static func _depth_limit(point: Vector3, side: int) -> float:
	var jag: float = _value_noise(point.x / 58.0, point.z / 58.0, SEED + 9)
	return _side_depth(side) - OUTER_RAGGED * jag


static func _side_normal(side: int) -> Vector3:
	match side:
		0:
			return Vector3(0.0, 0.0, -1.0)
		1:
			return Vector3(1.0, 0.0, 0.0)
		2:
			return Vector3(0.0, 0.0, 1.0)
		_:
			return Vector3(-1.0, 0.0, 0.0)


## Nearest side of the fence rectangle to a world point, in the same 0..3 order.
static func _side_index(point: Vector3, fence: Rect2) -> int:
	var centre: Vector2 = fence.get_center()
	var dx: float = (point.x - centre.x) / maxf(fence.size.x * 0.5, 1.0)
	var dz: float = (point.z - centre.y) / maxf(fence.size.y * 0.5, 1.0)
	if absf(dx) > absf(dz):
		return 1 if dx > 0.0 else 3
	return 2 if dz > 0.0 else 0


## Distance from a fence edge to a band point, using the side's own axis.
static func _band_depth(point: Vector3, fence: Rect2, side: int) -> float:
	match side:
		0:
			return fence.position.y - point.z
		1:
			return point.x - fence.end.x
		2:
			return point.z - fence.end.y
		_:
			return fence.position.x - point.x


## A point `offset` metres outside the fence on the nearest side, clamped along
## that side. Used to seat every designed clearing behind the fence it belongs
## to instead of at a hard-coded coordinate.
static func _band_point(point: Vector3, fence: Rect2, offset: float) -> Vector3:
	var centre: Vector2 = fence.get_center()
	var dx: float = (point.x - centre.x) / maxf(fence.size.x * 0.5, 1.0)
	var dz: float = (point.z - centre.y) / maxf(fence.size.y * 0.5, 1.0)
	if absf(dx) > absf(dz):
		var x: float = fence.position.x - offset if dx < 0.0 \
			else fence.end.x + offset
		return Vector3(x, 0.0, clampf(point.z, fence.position.y, fence.end.y))
	var z: float = fence.position.y - offset if dz < 0.0 \
		else fence.end.y + offset
	return Vector3(clampf(point.x, fence.position.x, fence.end.x), 0.0, z)


# --------------------------------------------------------------------------
# level design


## Reads the lap and turns it into the green plan: a framed gap at the longest
## straight, open fronts at the four grandstands, a thicket behind the tightest
## corner, a visual-break forest opposite the pits, and the forced tall trees
## that guarantee the two designed frame lines.
static func _design(spline: RefCounted, plan: RefCounted,
		fence: Rect2) -> Dictionary:
	var design: Dictionary = {"clearings": [], "thicket": Vector3.ZERO,
		"green_side": 0, "forced": [], "stands": []}
	var longest: Dictionary = {}
	for run: Dictionary in plan.straight_runs():
		if longest.is_empty() or float(run["length"]) \
				> float(longest["length"]):
			longest = run
	if not longest.is_empty():
		var middle: float = float(longest["from"]) \
			+ float(longest["length"]) * 0.5
		var frame: Dictionary = spline.sample(middle)
		var point: Vector3 = frame["position"]
		var side: int = _side_index(point, fence)
		design["green_side"] = _opposite_side(side)
		var vista: Vector3 = _band_point(point, fence, VISTA_OFFSET)
		(design["clearings"] as Array).append({
			"point": vista, "radius": VISTA_CLEARING,
		})
		# Tall trees either side of the gap: the straight is framed by two
		# deliberate pylons of foliage instead of a ragged noise edge.
		var tangent := Vector3(-_side_normal(side).z, 0.0,
			_side_normal(side).x)
		for direction: float in [-1.0, 1.0]:
			for index in 2:
				var flank: Vector3 = vista + tangent * (direction
					* (VISTA_CLEARING + 3.0 + float(index) * 6.0))
				(design["forced"] as Array).append({
					"point": flank + _side_normal(side) * (2.0
						+ float(index) * 3.0),
					"side": side,
				})
	for corner: Dictionary in plan.major_corners(4):
		var curve: float = float(corner["curve"])
		if absf(curve) < 0.02:
			continue
		var stand_side: float = 1.0 if curve > 0.0 else -1.0
		var frame: Dictionary = spline.sample(float(corner["distance"]))
		var stand: Vector3 = frame["position"] \
			+ frame["right"] * (stand_side * TileKit.STAND_OFFSET)
		(design["stands"] as Array).append(stand)
		(design["clearings"] as Array).append({
			"point": _band_point(stand, fence, VISTA_OFFSET),
			"radius": STAND_CLEARING,
		})
	# The tightest corner gets the thicket: the view behind it is closed with a
	# stand of pines instead of a lit container yard.
	var tightest: Dictionary = {}
	var tightest_curve: float = 0.0
	for corner: Dictionary in plan.major_corners(12):
		var curve: float = absf(float(corner["curve"]))
		if curve > tightest_curve:
			tightest_curve = curve
			tightest = corner
	if not tightest.is_empty():
		var curve: float = float(tightest["curve"])
		var thicket_side: float = 1.0 if curve > 0.0 else -1.0
		var frame: Dictionary = spline.sample(float(tightest["distance"]))
		var anchor: Vector3 = frame["position"] \
			+ frame["right"] * (thicket_side * TileKit.STAND_OFFSET)
		var seat: Vector3 = _band_point(anchor, fence, 26.0)
		design["thicket"] = seat
		var side: int = _side_index(seat, fence)
		var tangent := Vector3(-_side_normal(side).z, 0.0,
			_side_normal(side).x)
		for direction: float in [-1.0, 1.0]:
			for index in 2:
				(design["forced"] as Array).append({
					"point": seat + tangent * (direction * (5.0
						+ float(index) * 8.0)) + _side_normal(side)
						* (float(index) * 5.0),
					"side": side,
				})
	return design


static func _opposite_side(side: int) -> int:
	match side:
		0:
			return 2
		1:
			return 3
		2:
			return 0
		_:
			return 1


## Density field: three octaves of value noise, then the design modifiers.
## Returns a negative score for a point inside a clearing so the seat stays real.
static func _score(point: Vector3, side: int, fence: Rect2,
		design: Dictionary) -> float:
	for clearing: Dictionary in (design["clearings"] as Array):
		var centre: Vector3 = clearing["point"]
		var radius: float = float(clearing["radius"])
		var gap: float = _flat_distance(point, centre)
		if gap < radius:
			return -99.0
	var value: float = 0.58 * _value_noise(point.x / 47.0, point.z / 47.0,
		SEED) + 0.28 * _value_noise(point.x / 17.0, point.z / 17.0,
		SEED + 17) + 0.14 * _value_noise(point.x / 6.5, point.z / 6.5,
		SEED + 41)
	for clearing: Dictionary in (design["clearings"] as Array):
		var centre: Vector3 = clearing["point"]
		var radius: float = float(clearing["radius"])
		var gap: float = _flat_distance(point, centre) - radius
		if gap < FRAME_RING:
			value += FRAME_BONUS * (1.0 - gap / FRAME_RING)
	var thicket: Vector3 = design["thicket"]
	if thicket != Vector3.ZERO:
		var gap: float = _flat_distance(point, thicket)
		if gap < THICKET_RADIUS:
			value += THICKET_BONUS * (1.0 - gap / THICKET_RADIUS)
	if side == int(design["green_side"]):
		value += GREEN_BONUS
	var edge: float = 1.0 - clampf(_band_depth(point, fence, side)
		/ EDGE_DEPTH, 0.0, 1.0)
	value += EDGE_BONUS * edge
	# Thin the last ten metres before the ragged limit, so the treeline fades
	# out through scrub-sized stands instead of stopping dead.
	var depth: float = _band_depth(point, fence, side)
	var taper: float = (depth - (_depth_limit(point, side) - OUTER_TAPER)) \
		/ OUTER_TAPER
	if taper > 0.0:
		value -= OUTER_PENALTY * clampf(taper, 0.0, 1.0)
	if side == 2:
		value -= QUAY_PENALTY
	return value


# --------------------------------------------------------------------------
# band trees


## Builds every band candidate, then seats the target number with a greedy
## minimum-spacing pass. Each side fills its share first so no side can be starved
## by a noisy neighbour; a second global pass tops the total up.
static func _select_trees(spline: RefCounted, plan: RefCounted, fence: Rect2,
		reserved: Dictionary, design: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var by_side: Array = [[], [], [], []]
	for forced: Dictionary in (design["forced"] as Array):
		var point: Vector3 = forced["point"]
		var side: int = int(forced["side"])
		if _tree_allowed(spline, plan, reserved, point, side, fence, design) < 0.0:
			continue
		(by_side[side] as Array).append({"point": point, "side": side,
			"score": 9.0, "forced": true})
	for side in 4:
		var box: Rect2 = _side_box(fence, side)
		var cols: int = int(floor(box.size.x / CANDIDATE_STEP)) + 1
		var rows: int = int(floor(box.size.y / CANDIDATE_STEP)) + 1
		for column in cols:
			for row in rows:
				var point := Vector3(box.position.x
					+ float(column) * CANDIDATE_STEP
					+ rng.randf_range(-CANDIDATE_JITTER, CANDIDATE_JITTER),
					0.0, box.position.y + float(row) * CANDIDATE_STEP
					+ rng.randf_range(-CANDIDATE_JITTER, CANDIDATE_JITTER))
				var score: float = _tree_allowed(spline, plan, reserved, point,
					side, fence, design)
				if score < 0.0:
					continue
				(by_side[side] as Array).append({"point": point, "side": side,
					"score": score, "forced": false})
	var chosen: Array = []
	var grid: Dictionary = {}
	for side in 4:
		var list: Array = by_side[side]
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["score"]) > float(b["score"]))
		var quota: int = int(round(float(TREE_TARGET) * SIDE_SHARE[side]))
		for entry: Dictionary in list:
			if _side_count(chosen, side) >= quota:
				break
			var point: Vector3 = entry["point"]
			if not _spaced(grid, point):
				continue
			_remember(grid, point)
			chosen.append(entry)
	var rest: Array = []
	for side in 4:
		rest.append_array(by_side[side] as Array)
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))
	for entry: Dictionary in rest:
		if chosen.size() >= TREE_TARGET:
			break
		var point: Vector3 = entry["point"]
		if not _spaced(grid, point):
			continue
		_remember(grid, point)
		chosen.append(entry)
	return chosen


## Clearance, reserve and density test for one band seat. Returns the score, or
## a negative number when the seat is not allowed.
static func _tree_allowed(spline: RefCounted, plan: RefCounted,
		reserved: Dictionary, point: Vector3, side: int, fence: Rect2,
		design: Dictionary) -> float:
	if TileKit.spline_distance(spline, point) < TREE_CLEARANCE:
		return -99.0
	var depth: float = _band_depth(point, fence, side)
	if depth < BAND_INNER - CANDIDATE_JITTER \
			or depth > _depth_limit(point, side):
		return -99.0
	if _reserved(plan, reserved, point):
		return -99.0
	return _score(point, side, fence, design)


static func _side_count(chosen: Array, side: int) -> int:
	var count: int = 0
	for entry: Dictionary in chosen:
		if int(entry["side"]) == side:
			count += 1
	return count


## Gives every seated tree its species, yaw and scale. Scale leans slightly
## larger towards the back of the belt, which keeps the fence row low and the
## horizon row heroic.
static func _scatter_trees(trees: Array, fence: Rect2,
		rng: RandomNumberGenerator) -> void:
	for entry: Dictionary in trees:
		var side: int = int(entry["side"])
		var keys: Array = SIDE_SPECIES[side]
		var key: String = str(keys[0]) if bool(entry["forced"]) \
			else str(keys[rng.randi_range(0, keys.size() - 1)])
		var spec: Dictionary = SPECIES[key]
		var racing: bool = bool(spec["racing"])
		var base: float = PROP if racing else NATURE
		var depth: float = _band_depth(entry["point"] as Vector3, fence, side)
		var lift: float = clampf(depth / _side_depth(side), 0.0, 1.0) * 0.08
		var scale: float = base * (float(spec["low"]) + rng.randf()
			* (float(spec["high"]) - float(spec["low"])) + lift)
		entry["key"] = key
		entry["yaw"] = rng.randf() * TAU
		entry["scale"] = scale
		entry["size"] = _size(spec, scale)


# --------------------------------------------------------------------------
# in-site windswept trees


## The in-site windswept trees stand in the overgrown pockets the yard reserved
## (dockyard_yard.TREE_ISLAND_META): cells the container packing left empty, so a
## tree can land between container rows without taking a stack's footprint or a
## prop's cell. One tree per pocket, jittered inside the cell, is deliberately
## sparse: the dock must keep reading as a dock.
static func _yard_trees(spline: RefCounted, plan: RefCounted, fence: Rect2,
		design: Dictionary, rng: RandomNumberGenerator) -> Array:
	var chosen: Array = []
	if not plan.is_grid():
		return chosen
	var raw: Variant = plan.get_meta(DockyardYard.TREE_ISLAND_META, [])
	if not (raw is Array):
		return chosen
	var stands: Array = design["stands"] as Array
	for entry: Variant in raw as Array:
		if chosen.size() >= YARD_TREE_LIMIT:
			break
		if not (entry is Vector2i):
			continue
		var cell: Vector2i = entry
		var centre: Vector3 = plan.cell_point(cell)
		# The pockets sit between two track strands, so pushing away from one
		# only closes on the other; a small jitter around the cell centre is the
		# honest seat.
		var point: Vector3 = centre + Vector3(
			rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2))
		if TileKit.spline_distance(spline, point) < YARD_CLEARANCE:
			continue
		if _flat_clearance(point, stands) < YARD_STAND_CLEAR:
			continue
		chosen.append({"point": point, "side": _side_index(point, fence),
			"index": chosen.size()})
	return chosen


# --------------------------------------------------------------------------
# undergrowth


## Four layers of scrub: bramble on the outboard face of the real fence panels,
## a front row at the foot of the treeline, a clump at roughly one band tree in
## three, and a skirt around every in-site tree. None of them carries a collider:
## they stand outside the barrier, and a bush is not a wall.
static func _scrub_points(trees: Array, yard: Array, spline: RefCounted,
		plan: RefCounted, fence: Rect2, rng: RandomNumberGenerator,
		stats: Dictionary) -> Array:
	var points: Array = []
	var placed: Array[Vector3] = []
	var allowed: Dictionary = {}
	for entry: Dictionary in yard:
		var point: Vector3 = entry["point"]
		allowed[Vector2i(floori(point.x / TILE), floori(point.z / TILE))] = true
	var before: int = points.size()
	_fence_brambles(points, placed, spline, plan, fence, rng)
	stats["scrub_fence"] = points.size() - before
	before = points.size()
	for tree: Dictionary in trees:
		if rng.randf() > CLUMP_CHANCE:
			continue
		var point: Vector3 = (tree["point"] as Vector3) + Vector3(
			rng.randf_range(-CLUMP_REACH, CLUMP_REACH), 0.0,
			rng.randf_range(-CLUMP_REACH, CLUMP_REACH))
		if not _scrub_allowed(spline, plan, placed, point, false, allowed):
			continue
		_add_scrub(points, int(tree["side"]), point, rng)
		placed.append(point)
	stats["scrub_clumps"] = points.size() - before
	before = points.size()
	for entry: Dictionary in yard:
		for index in 2:
			var angle: float = TAU * float(index) / 2.0 + rng.randf_range(
				-0.6, 0.6)
			var point: Vector3 = (entry["point"] as Vector3) + Vector3(
				cos(angle), 0.0, sin(angle)) * rng.randf_range(2.2, 4.4)
			if not _scrub_allowed(spline, plan, placed, point, false, allowed):
				continue
			_add_scrub(points, int(entry["side"]), point, rng)
			placed.append(point)
	stats["scrub_yard"] = points.size() - before
	before = points.size()
	_front_scrub(points, placed, spline, plan, fence, rng)
	stats["scrub_front"] = points.size() - before
	return points


## One scrub instance with its species, scale and yaw chosen here, so the
## emission pass is a pure batching loop and the scatter stays deterministic.
static func _add_scrub(points: Array, side: int, point: Vector3,
		rng: RandomNumberGenerator) -> void:
	var keys: Array = SIDE_SCRUB[side]
	var key: String = str(keys[rng.randi_range(0, keys.size() - 1)])
	var spec: Dictionary = SCRUB[key]
	points.append({
		"point": point, "side": side, "key": key,
		"scale": NATURE * rng.randf_range(float(spec["low"]),
			float(spec["high"])),
		"yaw": rng.randf() * TAU,
	})


## Bramble clumps on the outboard face of the panels the yard actually built.
## The plan publishes those cells (dockyard_yard.FENCE_META) because a ring cell
## can just as well hold a container, and a bush must not grow through a stack.
static func _fence_brambles(points: Array, placed: Array[Vector3],
		spline: RefCounted, plan: RefCounted, fence: Rect2,
		rng: RandomNumberGenerator) -> void:
	var raw: Variant = plan.get_meta(DockyardYard.FENCE_META, [])
	if not (raw is Array):
		return
	var allowed: Dictionary = {}
	for entry: Variant in raw as Array:
		if entry is Vector2i:
			allowed[entry] = true
	for entry: Variant in raw as Array:
		if not (entry is Vector2i):
			continue
		var centre: Vector3 = plan.cell_point(entry as Vector2i)
		var side: int = _side_index(centre, fence)
		var normal: Vector3 = _side_normal(side)
		var tangent := Vector3(-normal.z, 0.0, normal.x)
		for index in FENCE_BRAMBLES:
			var point: Vector3 = centre + normal * rng.randf_range(
				FENCE_SCRUB_INNER, FENCE_SCRUB_OUTER) + tangent \
				* rng.randf_range(-FENCE_SCRUB_LATERAL,
					FENCE_SCRUB_LATERAL)
			if not _scrub_allowed(spline, plan, placed, point, true, allowed):
				continue
			_add_scrub(points, side, point, rng)
			placed.append(point)


## A point `along` metres down one side of the fence rectangle.
static func _fence_seat(fence: Rect2, side: int, along: float) -> Vector3:
	match side:
		0:
			return Vector3(fence.position.x + along, 0.0, fence.position.y)
		1:
			return Vector3(fence.end.x, 0.0, fence.position.y + along)
		2:
			return Vector3(fence.end.x - along, 0.0, fence.end.y)
		_:
			return Vector3(fence.position.x, 0.0, fence.end.y - along)


## A row of scrub along the foot of the treeline, just outside the belt's front
## rank. This is the layer that stops the forest starting abruptly from flat
## concrete: from the karts it reads as a bramble verge under the first trees.
static func _front_scrub(points: Array, placed: Array[Vector3],
		spline: RefCounted, plan: RefCounted, fence: Rect2,
		rng: RandomNumberGenerator) -> void:
	var sides: Array = [fence.size.x, fence.size.y, fence.size.x,
		fence.size.y]
	var found: int = 0
	for side in 4:
		if found >= FRONT_SCRUB_LIMIT:
			return
		var span: float = float(sides[side])
		var count: int = maxi(int(span / FRONT_SCRUB_STEP), 3)
		var normal: Vector3 = _side_normal(side)
		var tangent := Vector3(-normal.z, 0.0, normal.x)
		for index in count:
			if found >= FRONT_SCRUB_LIMIT:
				return
			var along: float = (float(index) + 0.5) * span / float(count) \
				+ rng.randf_range(-2.2, 2.2)
			var point: Vector3 = _fence_seat(fence, side, along) \
				+ normal * rng.randf_range(FRONT_SCRUB_INNER,
					FRONT_SCRUB_OUTER) + tangent * rng.randf_range(-1.4,
					1.4)
			if not _scrub_allowed(spline, plan, placed, point, false, {}):
				continue
			_add_scrub(points, side, point, rng)
			placed.append(point)
			found += 1


## Shared scrub rules: outside the barrier with a canopy's margin; not inside a
## full-footprint in-grid cell; off-grid cells, fence-panel cells and reserved
## yard pockets are allowed at a post-sized margin; and clear of the scrub
## already seated.
static func _scrub_allowed(spline: RefCounted, plan: RefCounted,
		placed: Array[Vector3], point: Vector3, inside_fence: bool,
		allowed: Dictionary) -> bool:
	if plan.is_grid() and point.z >= float(plan.rows) * TILE - 2.5:
		return false
	if TileKit.spline_distance(spline, point) < SCRUB_CLEARANCE:
		return false
	var cell := Vector2i(floori(point.x / TILE), floori(point.z / TILE))
	var ring: bool = inside_fence and plan.is_ring_cell(cell)
	if plan.is_used(cell) and not ring and not allowed.has(cell):
		# An in-grid cell holds a full 16 m footprint (office, wharf pad,
		# container); only off-grid cells hold sparse posts, which the radius
		# check below is enough to clear.
		if plan.in_grid(cell):
			return false
	# A fence panel or a reserved yard pocket is thin ground: its own cell is
	# allowed at a post-sized margin, not the full container margin.
	var radius: float = FENCE_POST_RADIUS if (ring or allowed.has(cell)) \
		else SCRUB_PROP_RADIUS
	if _near_prop(plan, point, radius):
		return false
	for other: Vector3 in placed:
		if other.distance_squared_to(point) < SCRUB_SPACING * SCRUB_SPACING:
			return false
	return true


## True when any dressed cell centre is within `radius` of the point. Scrub is
## allowed to share a cell with a floodlight or a sign, just not its base.
static func _near_prop(plan: RefCounted, point: Vector3,
		radius: float) -> bool:
	if not plan.is_grid():
		return false
	var cell := Vector2i(floori(point.x / TILE), floori(point.z / TILE))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var probe := Vector2i(cell.x + dx, cell.y + dz)
			if not plan.is_used(probe):
				continue
			if _flat_distance(plan.cell_point(probe), point) < radius:
				return true
	return false


# --------------------------------------------------------------------------
# emission


## Writes one batch per species per side, applies the view range, and records the
## MultiMesh and surface counts on `stats`.
static func _emit_trees(parent: Node3D, trees: Array,
		stats: Dictionary) -> void:
	for side in 4:
		var container := Node3D.new()
		container.name = "DockyardForest_%d" % side
		parent.add_child(container)
		var buckets: Dictionary = {}
		for entry: Dictionary in trees:
			if int(entry["side"]) != side:
				continue
			var key: String = str(entry["key"])
			if not buckets.has(key):
				buckets[key] = []
			(buckets[key] as Array).append(entry)
		for key: String in buckets:
			var spec: Dictionary = SPECIES[key]
			var transforms: Array = []
			for entry: Dictionary in (buckets[key] as Array):
				transforms.append(_fit(spec, entry["point"] as Vector3,
					float(entry["yaw"]), float(entry["scale"])))
			var model: String = str(spec["model"])
			stats["draws"] = int(stats["draws"]) \
				+ (Parts.part_count_nature(model) if not bool(spec["racing"])
					else Parts.part_count(model))
			if bool(spec["racing"]):
				Parts.batch(container, model, transforms, "Band_" + key, false)
			else:
				Parts.batch_nature(container, model, transforms, "Band_" + key,
					false)
		stats["surfaces"] = int(stats["surfaces"]) \
			+ _apply_view(container, TREE_RANGE)


## The in-site trees, one batch per stem, at a closer view range.
static func _emit_yard_trees(parent: Node3D, yard: Array,
		stats: Dictionary) -> void:
	if yard.is_empty():
		return
	var container := Node3D.new()
	container.name = "DockyardYardTrees"
	parent.add_child(container)
	var buckets: Dictionary = {}
	for entry: Dictionary in yard:
		var key: String = str(entry["key"])
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(entry)
	for key: String in buckets:
		var spec: Dictionary = SPECIES[key]
		var model: String = str(spec["model"])
		var transforms: Array = []
		for entry: Dictionary in (buckets[key] as Array):
			transforms.append(_fit(spec, entry["point"] as Vector3,
				float(entry["yaw"]), float(entry["scale"])))
		stats["draws"] = int(stats["draws"]) + Parts.part_count_nature(model)
		Parts.batch_nature(container, model, transforms, "Yard_" + key, false)
	stats["surfaces"] = int(stats["surfaces"]) \
		+ _apply_view(container, YARD_TREE_RANGE)


## Undergrowth batches, two species per side, at the closest view range.
static func _emit_scrub(parent: Node3D, scrub: Array,
		stats: Dictionary) -> void:
	if scrub.is_empty():
		return
	for side in 4:
		var container := Node3D.new()
		container.name = "DockyardScrub_%d" % side
		parent.add_child(container)
		var buckets: Dictionary = {}
		for entry: Dictionary in scrub:
			if int(entry["side"]) != side:
				continue
			var key: String = str(entry["key"])
			if not buckets.has(key):
				buckets[key] = []
			(buckets[key] as Array).append(entry)
		for key: String in buckets:
			var spec: Dictionary = SCRUB[key]
			var model: String = str(spec["model"])
			var transforms: Array = []
			for entry: Dictionary in (buckets[key] as Array):
				transforms.append(Parts.fit_nature(model,
					entry["point"] as Vector3, float(entry["yaw"]),
					Vector3.ONE * float(entry["scale"])))
			stats["draws"] = int(stats["draws"]) \
				+ Parts.part_count_nature(model)
			Parts.batch_nature(container, model, transforms, "Scrub_" + key,
				false)
		stats["surfaces"] = int(stats["surfaces"]) \
			+ _apply_view(container, SCRUB_RANGE)


static func _fit(spec: Dictionary, point: Vector3, yaw: float,
		scale: float) -> Transform3D:
	var model: String = str(spec["model"])
	var unit := Vector3.ONE * scale
	if bool(spec["racing"]):
		return Parts.fit(model, point, yaw, unit)
	return Parts.fit_nature(model, point, yaw, unit)


static func _size(spec: Dictionary, scale: float) -> Vector3:
	var model: String = str(spec["model"])
	var unit := Vector3.ONE * scale
	if bool(spec["racing"]):
		return Parts.size(model, unit)
	return Parts.size_nature(model, unit)


## Sets the view range on every MultiMesh a batch just added and returns the
## number of surfaces those meshes draw. Split by side, the band behind the camera
## is rejected by distance even when it stays inside the frustum; the fade is
## disabled because a blended tree edge costs more than a hard cut at racing
## speed.
static func _apply_view(container: Node3D, view_end: float) -> int:
	var surfaces: int = 0
	for child: Node in container.get_children():
		var view := child as GeometryInstance3D
		if view == null:
			continue
		view.visibility_range_end = view_end
		view.visibility_range_end_margin = 16.0
		view.visibility_range_fade_mode = \
			GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		var multi := child as MultiMeshInstance3D
		if multi != null and multi.multimesh != null \
				and multi.multimesh.mesh != null:
			surfaces += multi.multimesh.mesh.get_surface_count()
	return surfaces


## One slim WORLD trunk per tree. The canopy is not collided: a kart-sized
## trunk is the only part a kart could ever reach, and the fence and barrier
## already hold the karts off this ground.
static func _trunk(body: StaticBody3D, entry: Dictionary) -> void:
	if body == null:
		return
	var size: Vector3 = entry.get("size", Vector3(1.0, 8.0, 1.0))
	var radius: float = clampf(minf(size.x, size.z) * 0.07, 0.26, 0.62)
	var height: float = clampf(size.y * 0.62, 2.4, 9.0)
	Parts.cylinder(body, entry["point"] as Vector3, radius, height)


# --------------------------------------------------------------------------
# reserves and spacing


## Cell centres the yard claimed outside the fence, split by where they sit. The
## fence ring itself is inside the fence rectangle and never appears here: trees
## may share a ring cell's outer half with a fence post, which is what lets the
## belt start a few metres off the fence instead of one empty ring away.
## Returns {inside, outside, cranes}, all Array[Vector3].
static func _reserved_points(plan: RefCounted, fence: Rect2) -> Dictionary:
	var inside: Array[Vector3] = []
	var outside: Array[Vector3] = []
	var cranes: Array[Vector3] = []
	if not plan.is_grid():
		return {"inside": inside, "outside": outside, "cranes": cranes}
	var raw_cranes: Variant = plan.get_meta(DockyardYard.CRANE_META, [])
	if raw_cranes is Array:
		for entry: Variant in raw_cranes as Array:
			if entry is Vector2i:
				cranes.append(plan.cell_point(entry as Vector2i))
	var min_col: int = int(floor((fence.position.x - TILE * 4.0) / TILE))
	var max_col: int = int(ceil((fence.end.x + TILE * 4.0) / TILE))
	var min_row: int = int(floor((fence.position.y - TILE * 4.0) / TILE))
	var max_row: int = int(ceil((fence.end.y + TILE * 4.0) / TILE))
	for row in range(min_row, max_row + 1):
		for col in range(min_col, max_col + 1):
			var cell := Vector2i(col, row)
			var point := Vector3((float(col) + 0.5) * TILE, 0.0,
				(float(row) + 0.5) * TILE)
			if fence.has_point(Vector2(point.x, point.z)):
				continue
			if not plan.is_used(cell):
				continue
			if plan.in_grid(cell):
				inside.append(point)
			else:
				outside.append(point)
	return {"inside": inside, "outside": outside, "cranes": cranes}


static func _reserved(plan: RefCounted, reserved: Dictionary,
		point: Vector3) -> bool:
	if plan.is_track(Vector2i(floori(point.x / TILE),
			floori(point.z / TILE))):
		return true
	for other: Vector3 in (reserved["inside"] as Array):
		if _flat_distance(point, other) < RESERVED_INSIDE:
			return true
	for other: Vector3 in (reserved["outside"] as Array):
		if _flat_distance(point, other) < RESERVED_OUTSIDE:
			return true
	for other: Vector3 in (reserved["cranes"] as Array):
		if _flat_distance(point, other) < CRANE_CLEAR:
			return true
	return false


## True when no seated point is closer than MIN_SPACING.
static func _spaced(grid: Dictionary, point: Vector3) -> bool:
	var key := Vector2i(floori(point.x / MIN_SPACING),
		floori(point.z / MIN_SPACING))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var bucket: Variant = grid.get(Vector2i(key.x + dx, key.y + dz))
			if not (bucket is Array):
				continue
			for other: Vector3 in (bucket as Array):
				if other.distance_squared_to(point) < MIN_SPACING * MIN_SPACING:
					return false
	return true


static func _remember(grid: Dictionary, point: Vector3) -> void:
	var key := Vector2i(floori(point.x / MIN_SPACING),
		floori(point.z / MIN_SPACING))
	if not grid.has(key):
		grid[key] = []
	(grid[key] as Array).append(point)


## Closest plan distance from `point` to any of `others`, or INF.
static func _flat_clearance(point: Vector3, others: Array) -> float:
	var closest: float = INF
	for other: Variant in others:
		if not (other is Vector3):
			continue
		closest = minf(closest, (other as Vector3).distance_to(point))
	return closest


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --------------------------------------------------------------------------
# deterministic noise


## Cheap deterministic value noise: hashed lattice corners, smoothstep blend.
## Three octaves are combined by the caller into the forest density field.
static func _value_noise(x: float, y: float, salt: int) -> float:
	var xi: int = floori(x)
	var yi: int = floori(y)
	var tx: float = _smooth(x - float(xi))
	var ty: float = _smooth(y - float(yi))
	var low: float = lerpf(_hash(xi, yi, salt), _hash(xi + 1, yi, salt), tx)
	var high: float = lerpf(_hash(xi, yi + 1, salt),
		_hash(xi + 1, yi + 1, salt), tx)
	return lerpf(low, high, ty)


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


static func _hash(x: int, y: int, salt: int) -> float:
	var value: int = (x * 374761393 + y * 668265263 + salt * 1442695041) \
		& 0x7FFFFFFF
	value = (value ^ (value >> 13)) & 0x7FFFFFFF
	value = (value * 1274126177) & 0x7FFFFFFF
	value = (value ^ (value >> 16)) & 0xFFFF
	return float(value) / 65535.0
