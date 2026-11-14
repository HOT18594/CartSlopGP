extends RefCounted
## Designed alpine pine forest for Glacier Pass.
##
## The pass is dressed as a valley rather than a snowfield with a ring of trees
## on it. The forest is this map's main level-design tool, so every stand, edge
## and clearing is authored against the course itself:
##
##   wall      the high west side of the climb carries a solid pine wall, so the
##             summit reads as a road cut into a forested mountainside;
##   vista     the high north-east shelf is cleared, which opens the summit out
##             over the ski-lift line and the pit block to the far ridge;
##   descent   the east drop off the summit thins to scattered pines, so the ice
##             descent reads fast and open;
##   base      the low south side closes in again, doubled into a dense stand at
##             the base hairpin, which is what shuts off the view behind the
##             tightest corner of the lap;
##   stands    one clearing at each grandstand, so the crowd is visible from the
##             road instead of sitting behind trunks;
##   ridge     a ring of oversized pines 150-230 m out, behind the fog line, so
##             the horizon reads as a valley wall instead of empty snow;
##   brush     grass, ferns, bushes and snow-flattened pines along the fence line
##             and the foot of the treeline, so the forest does not start
##             abruptly out of flat ground.
##
## Placement is deliberately not a uniform scatter. Every candidate is scored by
## three octaves of value noise (40 m stands, 14 m copses, 5 m thickets) and
## accepted against that score, then spaced against the trees already planted, so
## the band breaks into dense stands, thin edges and clearings.
##
## Cost: one MultiMesh per model part for the whole map, no per-tree node and no
## per-tree collider - the barrier ring is continuous and the race already pulls
## a kart back once it is 13 m off the centreline, so a trunk past
## TREE_CLEARANCE is unreachable and a collider on it would only cost broad-phase
## work. Nothing here casts a shadow, and each band carries its own visibility
## range: the small cover drops out first, the treeline last.
##
## The trunk invariant: a candidate starts on the offset row, but another leg of
## the pinched eight can be nearer than the one being offset from, so every
## accepted trunk is measured against the whole centreline and refused inside
## TREE_CLEARANCE. The gate is in the planting loop, not a post-hoc audit, so a
## tree can never stand on the racing surface even when the course changes.

const GlacierProps := preload("res://scripts/minigames/maps/glacier/glacier_props.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")

## Near belt: the treeline the driver reads as a wall. Five offset rows, so the
## band is 16 m deep and a gap cannot show through to the horizon.
const INNER_CLEARANCE: float = 22.5
const SCREEN_LATERALS: Array[float] = [22.5, 26.5, 30.5, 34.5, 38.5]
## Backdrop: the darker mass behind the treeline, thinner and taller.
const BACKDROP_LATERALS: Array[float] = [43.0, 48.5, 54.0, 59.5]
## Undergrowth rows: the fence line, then the foot of the treeline.
const BRUSH_LATERALS: Array[float] = [12.6, 14.8, 17.0, 19.6, 23.0, 27.0]
## Ridge rings around the lap centre, in metres and metres between trees.
const RIDGE_RINGS: Array[Dictionary] = [
	{"radius": 152.0, "spacing": 13.0},
	{"radius": 188.0, "spacing": 16.0},
	{"radius": 224.0, "spacing": 19.0},
]

## Species tables. Height is the target tree height in metres and stretch widens
## or narrows the model's authored plan silhouette: alpine stands are famously
## uneven, so both ranges are wide. Weight is the relative share of the mix.
## `_dark` stems are the only colour variation the kit offers - the nature kit's
## materials are a baked atlas, so a per-instance tint would mean replacing the
## textured material on every trunk.
const SCREEN_SPECIES: Array[Dictionary] = [
	{"model": "tree_pineTallD", "height_min": 13.0, "height_max": 25.0,
		"stretch_min": 0.78, "stretch_max": 1.22, "weight": 5},
	{"model": "tree_pineTallB", "height_min": 11.0, "height_max": 23.0,
		"stretch_min": 0.80, "stretch_max": 1.28, "weight": 5},
	{"model": "tree_pineTallA", "height_min": 8.0, "height_max": 18.0,
		"stretch_min": 0.85, "stretch_max": 1.35, "weight": 4},
	{"model": "tree_pineTallC", "height_min": 10.0, "height_max": 20.0,
		"stretch_min": 0.85, "stretch_max": 1.30, "weight": 3},
	{"model": "tree_cone", "height_min": 5.0, "height_max": 13.0,
		"stretch_min": 0.90, "stretch_max": 1.45, "weight": 3},
	{"model": "tree_cone_dark", "height_min": 5.0, "height_max": 13.0,
		"stretch_min": 0.90, "stretch_max": 1.45, "weight": 2},
	{"model": "tree_pineSmallA", "height_min": 4.0, "height_max": 10.0,
		"stretch_min": 0.90, "stretch_max": 1.45, "weight": 2},
]
const BACKDROP_SPECIES: Array[Dictionary] = [
	{"model": "tree_pineTallD", "height_min": 16.0, "height_max": 30.0,
		"stretch_min": 0.75, "stretch_max": 1.15, "weight": 4},
	{"model": "tree_pineTallB", "height_min": 15.0, "height_max": 28.0,
		"stretch_min": 0.78, "stretch_max": 1.20, "weight": 3},
	{"model": "tree_default", "height_min": 12.0, "height_max": 22.0,
		"stretch_min": 0.85, "stretch_max": 1.25, "weight": 1},
]
const RIDGE_SPECIES: Array[Dictionary] = [
	{"model": "tree_pineTallD", "height_min": 24.0, "height_max": 42.0,
		"stretch_min": 0.85, "stretch_max": 1.15, "weight": 4},
	{"model": "tree_cone", "height_min": 20.0, "height_max": 34.0,
		"stretch_min": 0.90, "stretch_max": 1.20, "weight": 1},
]
## Low cover for the fence line, then the taller edge plants for the treeline.
const BRUSH_LOW: Array[Dictionary] = [
	{"model": "grass_large", "height_min": 0.35, "height_max": 0.90,
		"stretch_min": 0.90, "stretch_max": 1.30, "weight": 4},
	{"model": "plant_flatShort", "height_min": 0.35, "height_max": 1.00,
		"stretch_min": 0.90, "stretch_max": 1.30, "weight": 3},
	{"model": "rock_smallFlatA", "height_min": 0.15, "height_max": 0.45,
		"stretch_min": 0.90, "stretch_max": 1.40, "weight": 2},
]
const BRUSH_TALL: Array[Dictionary] = [
	{"model": "plant_bushLarge", "height_min": 0.70, "height_max": 2.00,
		"stretch_min": 0.90, "stretch_max": 1.30, "weight": 3},
	{"model": "plant_bushDetailed", "height_min": 0.80, "height_max": 2.20,
		"stretch_min": 0.90, "stretch_max": 1.30, "weight": 2},
	{"model": "plant_flatTall", "height_min": 0.35, "height_max": 1.00,
		"stretch_min": 0.90, "stretch_max": 1.30, "weight": 2},
	{"model": "tree_pineGroundA", "height_min": 2.60, "height_max": 5.50,
		"stretch_min": 0.90, "stretch_max": 1.25, "weight": 2},
]

## Acceptance before the gains and the noise are applied. The bands are walked on
## a 3 m lattice, so the chance - not the spacing test - is what sets the density,
## and a pinned stand is not fought by it.
const SCREEN_CHANCE: float = 0.29
const BACKDROP_CHANCE: float = 0.13
const BRUSH_CHANCE: float = 0.46
const RIDGE_CHANCE: float = 0.62
const TREE_STEP: float = 3.0
const TREE_JITTER: float = 1.1
const MIN_SPACING: float = 1.4
const BRUSH_STEP: float = 6.0
const BRUSH_JITTER: float = 1.5
const BRUSH_SPACING: float = 1.15
## Layers thin out with depth so the back of the band never reads as one wall.
const SCREEN_DEPTH_FADE: float = 0.80
const BACKDROP_DEPTH_FADE: float = 0.55

## Level-design gains. Each one is a multiplier on the acceptance chance, tuned
## against the measured area of each sector: the wall ends up about three times
## denser than the open band, the base stand about twice, the descent under it
## and the infield at half.
const WALL_GAIN: float = 14.0
const OPENING_GAIN: float = 0.20
const DESCENT_GAIN: float = 0.80
const BASE_GAIN: float = 6.4
const HAIRPIN_GAIN: float = 1.8
const INFIELD_GAIN: float = 1.25
const CLUSTER_FLOOR: float = 0.12
const CLUSTER_TOP: float = 1.55
## The base hairpin within this arc length of the tightest low corner gets the
## extra gain that makes its stand read as a wall of its own.
const HAIRPIN_SPAN: float = 60.0
## How far along the summit plateau the vista sits: past the middle, on the lip
## the descent falls away from.
const VISTA_BIAS: float = 0.72

## Hard clearance gates, in plan metres from the racing centreline. The barrier
## ring's outer face is ~9 m out, so 20 m leaves eleven metres of run-off and a
## full crown width of margin: no trunk, bough or root plate can reach the road.
## The underbrush gate is the same rule at plant scale: the widest low clump is
## about 3.8 m across, so its own centre has to stay outside 11.4 m for no leaf to
## poke through the wall.
const TREE_CLEARANCE: float = 20.0
const BRUSH_CLEARANCE: float = 11.4
const RIDGE_CLEARANCE: float = 64.0
const RIDGE_SPACING: float = 9.0

## Clearings, in metres. The summit shelf is cut as a chain so the vista is a
## corridor and not a bald circle, and each grandstand gets a disc plus a lane
## that opens the sightline from the road to the crowd.
const SUMMIT_REACH: Array[float] = [32.0, 50.0]
const SUMMIT_RADIUS: Array[float] = [30.0, 26.0]
const STAND_LATERAL: float = 23.0
const STAND_SITES: Array[Dictionary] = [
	{"fraction": 0.02, "side": 1.0},
	{"fraction": 0.52, "side": -1.0},
]
## Mirrors glacier_layout: a stand on a deck above this is moved to the base.
const STAND_DECK_LIMIT: float = 2.5
const STAND_FALLBACK: float = 0.40
const STAND_CLEARING: float = 26.0
const STAND_LANE: float = 20.0
const CLEAR_FLOOR: float = 0.04

## Visibility ranges. The treeline is the horizon, so its band is generous; the
## small cover and the backdrop are given the tighter clips.
const SCREEN_VIEW: float = 420.0
const BACKDROP_VIEW: float = 520.0
const RIDGE_VIEW: float = 760.0
const BRUSH_VIEW: float = 190.0
const VIEW_MARGIN: float = 24.0

const SEED: int = 20261114


## Plan clearance straight off the grid spline, in metres.
##
## This is `GlacierProps.clearance` with the dispatch shortcut: that helper has to
## go through `Object.call` because its parameter is untyped, and the reflective
## call is by far the most expensive step here - the gate runs about 1,300 times a
## build, and the dispatch alone was two thirds of it. The rule is still the
## shared one; only the call is cheaper.
static func _clearance(spline: RefCounted, point: Vector3) -> float:
	if spline.has_method("plan_distance"):
		return float(spline.plan_distance(point))
	return GlacierProps.clearance(spline, point)


## Builds the forest under `holder`. Returns {pines, brush, ridge, draws,
## objects, rejected}.
static func build(holder: Node3D, spline: RefCounted) -> Dictionary:
	var stats: Dictionary = {"pines": 0, "brush": 0, "ridge": 0, "draws": 0,
		"objects": 0, "rejected": 0}
	if holder == null or spline == null:
		return stats
	var tiles: Variant = spline.get("tiles")
	if not (tiles is Array) or (tiles as Array).is_empty():
		return stats
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var ctx: Dictionary = _sites(spline)
	ctx["spline"] = spline
	ctx["rng"] = rng
	ctx["pine_closest"] = INF
	ctx["ridge_closest"] = INF
	ctx["brush_closest"] = INF
	ctx["rejected"] = 0
	ctx["counts"] = _sector_counts()
	var grid: Dictionary = {}
	var screen: Array = []
	var backdrop: Array = []
	for side: float in [-1.0, 1.0]:
		_band(ctx, grid, side, SCREEN_LATERALS, SCREEN_SPECIES, SCREEN_CHANCE,
			SCREEN_DEPTH_FADE, screen)
	for side: float in [-1.0, 1.0]:
		_band(ctx, grid, side, BACKDROP_LATERALS, BACKDROP_SPECIES,
			BACKDROP_CHANCE, BACKDROP_DEPTH_FADE, backdrop)
	var ridge: Array = []
	_ridge(ctx, grid, ridge)
	var brush: Array = []
	var brush_grid: Dictionary = {}
	for side: float in [-1.0, 1.0]:
		_brush_line(ctx, brush_grid, side, brush)
	_flush(holder, screen, "PineScreen", SCREEN_VIEW, false)
	_flush(holder, backdrop, "PineBackdrop", BACKDROP_VIEW, false)
	_flush(holder, ridge, "PineRidge", RIDGE_VIEW, false)
	_flush(holder, brush, "Underbrush", BRUSH_VIEW, false)
	stats["pines"] = screen.size() + backdrop.size() + ridge.size()
	stats["brush"] = brush.size()
	stats["ridge"] = ridge.size()
	stats["rejected"] = int(ctx["rejected"])
	stats["objects"] = int(stats["pines"]) + int(stats["brush"])
	stats["draws"] = _draw_estimate([screen, backdrop, ridge, brush])
	_report("GlacierPines", screen.size() + backdrop.size(),
		float(ctx["pine_closest"]), TREE_CLEARANCE)
	_report("GlacierRidge", ridge.size(), float(ctx["ridge_closest"]),
		RIDGE_CLEARANCE)
	_report("GlacierBrush", brush.size(), float(ctx["brush_closest"]),
		BRUSH_CLEARANCE)
	print("GLACIER FOREST: %d screen + %d backdrop + %d ridge, %d underbrush; %d refused at the clearance gate" % [
		screen.size(), backdrop.size(), ridge.size(), brush.size(),
		int(ctx["rejected"])])
	print("GLACIER FOREST: wall %d, base %d, descent %d, opening %d, infield %d, other %d" % [
		int((ctx["counts"] as Dictionary)["wall"]),
		int((ctx["counts"] as Dictionary)["base"]),
		int((ctx["counts"] as Dictionary)["descent"]),
		int((ctx["counts"] as Dictionary)["opening"]),
		int((ctx["counts"] as Dictionary)["infield"]),
		int((ctx["counts"] as Dictionary)["other"])])
	return stats


# --------------------------------------------------------------------------
# bands
# --------------------------------------------------------------------------


## Grows one band on one side of the lap: walks the lap in TREE_STEP steps and
## plants a candidate on every requested offset row whenever the density field
## accepts it. The offset row is measured from the racing centreline at that arc
## position, and the accepted point is then measured against the whole line, so
## the clearance gate sees a leg the row was not offset from.
static func _band(ctx: Dictionary, grid: Dictionary, side: float,
		laterals: Array[float], species: Array[Dictionary], chance: float,
		depth_fade: float, entries: Array) -> void:
	var spline: RefCounted = ctx["spline"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var clearings: Array = ctx["clearings"] as Array
	var total: float = maxf(float(spline.total_length), 1.0)
	var steps: int = maxi(8, int(round(total / TREE_STEP)))
	for lateral: float in laterals:
		var phase: float = rng.randf() * TREE_STEP
		var depth: float = lerpf(1.0, depth_fade, clampf(
			(lateral - INNER_CLEARANCE) / (BACKDROP_LATERALS[
				BACKDROP_LATERALS.size() - 1] - INNER_CLEARANCE), 0.0, 1.0))
		for step in steps:
			var s: float = fposmod(phase + float(step) * TREE_STEP, total)
			var frame: Dictionary = spline.sample(s)
			var centreline: Vector3 = frame["position"] as Vector3
			var point: Vector3 = centreline \
				+ (frame["right"] as Vector3) * (lateral * side)
			point += Vector3(rng.randf_range(-TREE_JITTER, TREE_JITTER), 0.0,
				rng.randf_range(-TREE_JITTER, TREE_JITTER))
			point.y = 0.0
			var sector: Dictionary = _sector(ctx, point, centreline,
				centreline.y)
			var tag: String = str(sector["tag"])
			var roll: float = _chance(clearings, point, chance,
				float(sector["gain"]), float(sector["settle"]), depth)
			if rng.randf() > roll:
				continue
			if not _room(grid, point, MIN_SPACING):
				continue
			var clearance: float = _clearance(spline, point)
			if clearance < TREE_CLEARANCE:
				ctx["rejected"] = int(ctx["rejected"]) + 1
				continue
			ctx["pine_closest"] = minf(float(ctx["pine_closest"]), clearance)
			var counts: Dictionary = ctx["counts"] as Dictionary
			counts[tag] = int(counts.get(tag, 0)) + 1
			_plant_pine(rng, point, species, float(sector["height"]), entries,
				grid)


## Plants one pine: species, height and plan width sampled from the table, yaw
## fully random.
static func _plant_pine(rng: RandomNumberGenerator, point: Vector3,
		species: Array[Dictionary], height_bias: float, entries: Array,
		grid: Dictionary) -> void:
	var pick: Dictionary = _pick(rng, species)
	if pick.is_empty():
		return
	var model: String = str(pick["model"])
	var info: Dictionary = TileCatalog.model_info(model, true)
	if not bool(info.get("ok", false)):
		return
	var base: float = maxf((info["aabb"] as AABB).size.y, 0.0001)
	var tall: float = rng.randf_range(float(pick["height_min"]),
		float(pick["height_max"])) * height_bias
	var vertical: float = tall / base
	var stretch: float = rng.randf_range(float(pick["stretch_min"]),
		float(pick["stretch_max"]))
	entries.append({"model": model, "nature": true,
		"transform": _stretched(model, point, rng.randf_range(0.0, TAU),
			vertical * stretch, vertical)})
	_occupy(grid, point, MIN_SPACING)


## The distant ridge: oversized pines on three rings around the lap centre, with
## noise-gated gaps so the horizon reads as a treed valley wall and not a fence
## of trees. They are the far LOD of the forest, not scenery the driver can
## reach, so they are planted wide apart and far outside the barrier.
static func _ridge(ctx: Dictionary, grid: Dictionary, entries: Array) -> void:
	var spline: RefCounted = ctx["spline"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var centre: Vector3 = ctx["centre"] as Vector3
	for ring: Dictionary in RIDGE_RINGS:
		var radius: float = float(ring["radius"])
		var spacing: float = float(ring["spacing"])
		var count: int = maxi(8, int(round(TAU * radius / spacing)))
		for index in count:
			var angle: float = TAU * (float(index) + rng.randf_range(0.0, 0.8)) \
				/ float(count)
			var reach: float = radius + rng.randf_range(-8.0, 8.0)
			var point := Vector3(centre.x + cos(angle) * reach, 0.0,
				centre.z + sin(angle) * reach)
			if rng.randf() > RIDGE_CHANCE:
				continue
			if _cluster(point.x * 0.4, point.z * 0.4) < 0.30:
				continue
			var clearance: float = _clearance(spline, point)
			if clearance < RIDGE_CLEARANCE:
				continue
			ctx["ridge_closest"] = minf(float(ctx["ridge_closest"]), clearance)
			if not _room(grid, point, RIDGE_SPACING):
				continue
			_plant_pine(rng, point, RIDGE_SPECIES, 1.0, entries, grid)


## Underbrush: one row family along the fence line and the foot of the treeline,
## so the forest edge grows out of cover instead of starting on bare snow. Low
## plants sit by the barrier and the taller edge plants by the trunks.
static func _brush_line(ctx: Dictionary, grid: Dictionary, side: float,
		entries: Array) -> void:
	var spline: RefCounted = ctx["spline"]
	var rng: RandomNumberGenerator = ctx["rng"]
	var clearings: Array = ctx["clearings"] as Array
	var total: float = maxf(float(spline.total_length), 1.0)
	var steps: int = maxi(8, int(round(total / BRUSH_STEP)))
	for lateral: float in BRUSH_LATERALS:
		var phase: float = rng.randf() * BRUSH_STEP
		var edge: float = smoothstep(11.0, 14.0, lateral) \
			* (1.0 - smoothstep(16.0, 20.0, lateral))
		var under: float = smoothstep(19.0, 23.0, lateral) \
			* (1.0 - smoothstep(28.0, 34.0, lateral))
		var profile: float = clampf(0.85 * edge + 0.55 * under + 0.16, 0.0, 1.0)
		for step in steps:
			var s: float = fposmod(phase + float(step) * BRUSH_STEP, total)
			var frame: Dictionary = spline.sample(s)
			var point: Vector3 = (frame["position"] as Vector3) \
				+ (frame["right"] as Vector3) * (lateral * side)
			point += Vector3(rng.randf_range(-BRUSH_JITTER, BRUSH_JITTER), 0.0,
				rng.randf_range(-BRUSH_JITTER, BRUSH_JITTER))
			point.y = 0.0
			var clearing: float = _clearing_scale(clearings, point)
			# Open ground grows more cover than the forest floor does.
			var open: float = lerpf(1.0, 1.3, 1.0 - clearing)
			var patch: float = lerpf(CLUSTER_FLOOR, CLUSTER_TOP,
				smoothstep(0.28, 0.72, _cluster(point.x + 31.0,
					point.z - 17.0)))
			if rng.randf() > BRUSH_CHANCE * profile * open * patch:
				continue
			if not _room(grid, point, BRUSH_SPACING):
				continue
			var clearance: float = _clearance(spline, point)
			if clearance < BRUSH_CLEARANCE:
				continue
			ctx["brush_closest"] = minf(float(ctx["brush_closest"]),
				clearance)
			var table: Array[Dictionary] = BRUSH_TALL if lateral > 18.0 \
				else BRUSH_LOW
			_plant_brush(rng, point, table, entries, grid)


## Plants one underbrush clump with a uniform scale.
static func _plant_brush(rng: RandomNumberGenerator, point: Vector3,
		species: Array[Dictionary], entries: Array, grid: Dictionary) -> void:
	var pick: Dictionary = _pick(rng, species)
	if pick.is_empty():
		return
	var model: String = str(pick["model"])
	var info: Dictionary = TileCatalog.model_info(model, true)
	if not bool(info.get("ok", false)):
		return
	var base: float = maxf((info["aabb"] as AABB).size.y, 0.0001)
	var tall: float = rng.randf_range(float(pick["height_min"]),
		float(pick["height_max"]))
	var vertical: float = tall / base
	entries.append({"model": model, "nature": true,
		"transform": _stretched(model, point, rng.randf_range(0.0, TAU),
			vertical * rng.randf_range(float(pick["stretch_min"]),
				float(pick["stretch_max"])), vertical)})
	_occupy(grid, point, BRUSH_SPACING)


# --------------------------------------------------------------------------
# level design
# --------------------------------------------------------------------------


## Everything the layout needs once per lap: the ring centre, the highest deck,
## and the authored clearings. The clearings are the level design made explicit,
## so the gains in `_sector` shape the mass and these cut the holes.
static func _sites(spline: RefCounted) -> Dictionary:
	var centre: Vector3 = _map_centre(spline)
	var total: float = maxf(float(spline.total_length), 1.0)
	var max_deck: float = 0.0
	for index in 96:
		max_deck = maxf(max_deck, _deck_at(spline, total * float(index) / 96.0))
	var hairpin: Vector3 = _tightest_corner(spline, total, max_deck)
	var clearings: Array = []
	if max_deck > 0.5:
		var summit: float = _summit_vista(spline, total, max_deck)
		var frame: Dictionary = spline.sample(summit)
		var at: Vector3 = frame["position"] as Vector3
		at.y = 0.0
		var outward: Vector3 = _outward(at, centre, frame["right"] as Vector3)
		for index in SUMMIT_REACH.size():
			var reach: float = SUMMIT_REACH[index]
			clearings.append({"at": at + outward * reach,
				"radius": SUMMIT_RADIUS[index]})
	for site: Dictionary in _stand_sites(spline, total):
		var at: Vector3 = site["at"] as Vector3
		var road: Vector3 = site["road"] as Vector3
		clearings.append({"at": at, "radius": STAND_CLEARING})
		clearings.append({"at": road.lerp(at, 0.55), "radius": STAND_LANE})
	return {"centre": centre, "max_deck": max_deck, "clearings": clearings,
		"hairpin": hairpin}


## Plan position of the tightest corner on the low half of the lap, which is the
## base hairpin: the corner a driver exits blind, so it gets the dense stand.
## Curvature is measured on the spline itself, so this follows a re-authored
## course instead of being pinned to the cells this one happens to use.
static func _tightest_corner(spline: RefCounted, total: float,
		max_deck: float) -> Vector3:
	var best: float = 0.0
	var at: Vector3 = spline.sample(0.0)["position"] as Vector3
	for index in 96:
		var distance: float = total * float(index) / 96.0
		# On a flat course every corner is a candidate: there is no low half to
		# prefer, and the tightest corner is still the one worth closing.
		if max_deck > 0.5 and _deck_at(spline, distance) > max_deck * 0.5:
			continue
		var bend: float = absf(spline.curvature_at(distance))
		if bend > best:
			best = bend
			at = spline.sample(distance)["position"] as Vector3
	at.y = 0.0
	return at


## The authored shape of the forest for one candidate, as a gain on its
## acceptance chance plus a height bias. It reads the plan direction out from the
## lap centre and the deck height under the point, which is what separates the
## uphill side of the pass from the summit shelf and the base. `settle` is the
## floor the cluster noise is held at, so a pinned gain cannot be broken up by a
## patch of thin noise.
static func _sector(ctx: Dictionary, point: Vector3, centreline: Vector3,
		deck: float) -> Dictionary:
	var centre: Vector3 = ctx["centre"] as Vector3
	var max_deck: float = float(ctx["max_deck"])
	var flat := Vector3(point.x - centre.x, 0.0, point.z - centre.z)
	var road := Vector3(centreline.x - centre.x, 0.0, centreline.z - centre.z)
	var outside: bool = flat.length_squared() > road.length_squared()
	var high: float = 0.0
	if max_deck > 0.5:
		high = clampf(deck / max_deck, 0.0, 1.0)
	var gain: float = 1.0
	var height: float = 1.0
	var settle: float = CLUSTER_FLOOR
	var tag: String = "other"
	if flat.length_squared() < 0.01:
		return {"gain": gain, "height": height, "settle": settle, "tag": tag}
	var dir: Vector3 = flat.normalized()
	var west: float = clampf(-dir.x, 0.0, 1.0)
	var north: float = clampf(-dir.z, 0.0, 1.0)
	var east: float = clampf(dir.x, 0.0, 1.0)
	var south: float = clampf(dir.z, 0.0, 1.0)
	if outside:
		# The pine wall on the uphill side: the west of the pass is the climb,
		# so it carries the tallest, closest stand.
		var wall: float = smoothstep(0.35, 0.85, west) \
			* smoothstep(0.40, 0.80, high)
		gain *= 1.0 + WALL_GAIN * wall
		height *= lerpf(1.0, 1.18, wall)
		settle = maxf(settle, 0.62 * wall)
		# The summit shelf opens north and north-east, over the lift line, to
		# the far ridge. Excluding the west half is what keeps the wall and the
		# vista from cancelling at the north-west corner.
		var vista: float = smoothstep(0.45, 0.90, north) \
			* (1.0 - smoothstep(0.45, 0.90, west)) \
			* smoothstep(0.50, 0.90, high)
		gain *= lerpf(1.0, OPENING_GAIN, vista)
		# The east drop thins to scattered pines as the road falls off.
		var thin: float = smoothstep(0.35, 0.85, east) \
			* (1.0 - smoothstep(0.75, 1.00, high))
		gain *= lerpf(1.0, DESCENT_GAIN, thin)
		height *= lerpf(1.0, 0.86, thin)
		# The low south closes in again, doubled on the west where the base
		# hairpin has to shut off the view behind the tightest corner.
		var base: float = clampf(south + 0.50 * west, 0.0, 1.0) \
			* (1.0 - smoothstep(0.10, 0.50, high))
		# The hairpin stand sits on the tightest low corner of the lap, which is
		# where a blind exit needs its view closed the hardest.
		var hairpin: Vector3 = ctx["hairpin"] as Vector3
		var reach: float = Vector2(point.x - hairpin.x,
			point.z - hairpin.z).length()
		var corner: float = (1.0 - smoothstep(HAIRPIN_SPAN * 0.5, HAIRPIN_SPAN,
			reach)) * (1.0 - smoothstep(0.10, 0.50, high))
		gain *= 1.0 + BASE_GAIN * base + HAIRPIN_GAIN * corner
		height *= lerpf(1.0, 1.06, maxf(base, corner))
		settle = maxf(settle, 0.55 * maxf(base, corner))
		tag = "wall" if wall > 0.45 else "other"
		if vista > 0.45:
			tag = "opening"
		elif thin > 0.45:
			tag = "descent"
		elif maxf(base, corner) > 0.45:
			tag = "base"
	else:
		gain *= INFIELD_GAIN
		tag = "infield"
	return {"gain": gain, "height": height, "settle": settle, "tag": tag}


## Acceptance chance for one candidate: the band's base chance, the sector gain,
## the cluster noise, the depth fade and the clearings.
static func _chance(clearings: Array, point: Vector3, base: float, gain: float,
		settle: float, depth: float) -> float:
	var patch: float = lerpf(CLUSTER_FLOOR, CLUSTER_TOP,
		smoothstep(0.30, 0.70, _cluster(point.x, point.z)))
	patch = maxf(patch, settle)
	var clearing: float = _clearing_scale(clearings, point)
	return clampf(base * gain * patch * depth * clearing, 0.0, 1.0)


## How much of the band survives at `point`: 0 in the heart of a clearing, 1 well
## clear of every one.
static func _clearing_scale(clearings: Array, point: Vector3) -> float:
	var scale: float = 1.0
	for entry: Variant in clearings:
		var clearing: Dictionary = entry as Dictionary
		var at: Vector3 = clearing["at"] as Vector3
		var radius: float = float(clearing["radius"])
		var distance: float = Vector2(point.x - at.x, point.z - at.z).length()
		var t: float = clampf((distance - radius * 0.2) / (radius * 0.8), 0.0,
			1.0)
		scale = minf(scale, maxf(t, CLEAR_FLOOR))
	return scale


## Where the summit vista is cut. It sits past the middle of the highest plateau,
## on the lip the road drops off, so the clearing opens down the descent and
## leaves the western crest walled. Taking the first sample at the crest instead
## would put the vista on the climb, which is the side that has to stay closed.
static func _summit_vista(spline: RefCounted, total: float,
		max_deck: float) -> float:
	if max_deck <= 0.5:
		return 0.0
	var samples: int = 128
	var threshold: float = max_deck * 0.92
	var step: float = total / float(samples)
	var best_from: float = 0.0
	var best_length: float = 0.0
	var run_from: float = -1.0
	for index in samples + 1:
		var distance: float = float(index) * step
		var high: bool = _deck_at(spline, distance) >= threshold
		if high and run_from < 0.0:
			run_from = distance
		elif not high and run_from >= 0.0:
			if distance - run_from > best_length:
				best_length = distance - run_from
				best_from = run_from
			run_from = -1.0
	if run_from >= 0.0 and total - run_from > best_length:
		best_length = total - run_from
		best_from = run_from
	if best_length < 0.01:
		return 0.0
	return fposmod(best_from + best_length * VISTA_BIAS, total)


## The two grandstand sites, mirrored from glacier_layout so the forest can cut a
## sightline to the crowd. The layout moves a stand off a high shelf to the base,
## and the forest has to follow it or the clearing would be cut in the trees
## while the stand sits somewhere else.
static func _stand_sites(spline: RefCounted, total: float) -> Array:
	var sites: Array = []
	for spec: Dictionary in STAND_SITES:
		var distance: float = total * float(spec["fraction"])
		if _deck_at(spline, distance) > STAND_DECK_LIMIT:
			distance = total * STAND_FALLBACK
		var frame: Dictionary = spline.sample(distance)
		var road: Vector3 = frame["position"] as Vector3
		var at: Vector3 = road \
			+ (frame["right"] as Vector3) * (STAND_LATERAL * float(spec["side"]))
		at.y = 0.0
		sites.append({"at": at, "road": Vector3(road.x, 0.0, road.z)})
	return sites


# --------------------------------------------------------------------------
# transforms
# --------------------------------------------------------------------------


## Transform for a pine whose height and plan width are scaled separately.
##
## The kit's pines all ship on one tall, narrow module, but an alpine stand is
## anything but regular: the same model has to read as a 6 m sapling in one place
## and a 25 m spire in another. `GlacierProps.fit` scales uniformly, so this
## mirrors its pivot convention - plan centre on `at`, lowest measured point
## lifted onto `at.y` - with a per-axis basis instead.
static func _stretched(model: String, at: Vector3, yaw: float, width: float,
		height: float) -> Transform3D:
	var info: Dictionary = TileCatalog.model_info(model, true)
	if not bool(info.get("ok", false)):
		return Transform3D(Basis(Vector3.UP, yaw), at)
	var aabb: AABB = info["aabb"]
	var centre: Vector2 = info["center"]
	var yaw_basis := Basis(Vector3.UP, yaw)
	var basis: Basis = yaw_basis \
		* Basis.IDENTITY.scaled(Vector3(width, height, width))
	var plan := Vector3(centre.x * width, 0.0, centre.y * width)
	return Transform3D(basis, at - yaw_basis * plan
		+ Vector3.UP * (-aabb.position.y * height))


## Weighted species pick.
static func _pick(rng: RandomNumberGenerator,
		species: Array[Dictionary]) -> Dictionary:
	var total: int = 0
	for entry: Dictionary in species:
		total += int(entry["weight"])
	if total <= 0:
		return species[0] if not species.is_empty() else {}
	var roll: int = rng.randi_range(0, total - 1)
	for entry: Dictionary in species:
		roll -= int(entry["weight"])
		if roll < 0:
			return entry
	return species[species.size() - 1]


# --------------------------------------------------------------------------
# noise and spacing
# --------------------------------------------------------------------------


## Three octaves of value noise in [0, 1]: 40 m stands, 14 m copses and 5 m
## thickets. This is what turns an even lattice into clusters with thin edges.
static func _cluster(x: float, z: float) -> float:
	var value: float = _value_noise(x / 40.0, z / 40.0, SEED) * 0.55
	value += _value_noise(x / 14.0, z / 14.0, SEED + 101) * 0.30
	value += _value_noise(x / 5.0, z / 5.0, SEED + 211) * 0.15
	return clampf(value, 0.0, 1.0)


## Smoothed value noise on an integer lattice.
static func _value_noise(u: float, v: float, salt: int) -> float:
	var x: int = floori(u)
	var z: int = floori(v)
	var fx: float = u - float(x)
	var fz: float = v - float(z)
	var sx: float = fx * fx * (3.0 - 2.0 * fx)
	var sz: float = fz * fz * (3.0 - 2.0 * fz)
	var a: float = _hash(x, z, salt)
	var b: float = _hash(x + 1, z, salt)
	var c: float = _hash(x, z + 1, salt)
	var d: float = _hash(x + 1, z + 1, salt)
	return lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sz)


## Deterministic lattice value in [0, 1].
static func _hash(x: int, z: int, salt: int) -> float:
	var h: int = x * 374761393 + z * 668265263 + salt * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


## True when `point` is at least `spacing` metres from everything already planted
## in `grid`. The grid cell is the spacing, so the 3x3 neighbourhood is the whole
## search.
static func _room(grid: Dictionary, point: Vector3, spacing: float) -> bool:
	var flat := Vector2(point.x, point.z)
	var key := Vector2i(floori(point.x / spacing), floori(point.z / spacing))
	for row in range(-1, 2):
		for col in range(-1, 2):
			var cell := Vector2i(key.x + col, key.y + row)
			if not grid.has(cell):
				continue
			for other: Vector2 in grid[cell] as Array:
				if other.distance_squared_to(flat) < spacing * spacing:
					return false
	return true


## Records a planted prop in the min-spacing grid.
static func _occupy(grid: Dictionary, point: Vector3, spacing: float) -> void:
	var key := Vector2i(floori(point.x / spacing), floori(point.z / spacing))
	if not grid.has(key):
		grid[key] = []
	(grid[key] as Array).append(Vector2(point.x, point.z))


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------


## Batches one band and gives it a visibility range, so a camera far off the pass
## stops paying for the layers it can no longer read. The band lives under its own
## holder because every instance in it shares the range.
static func _flush(holder: Node3D, entries: Array, node_name: String,
		view_end: float, cast_shadow: bool) -> int:
	if holder == null or entries.is_empty():
		return 0
	var band := Node3D.new()
	band.name = node_name + "Band"
	holder.add_child(band)
	var placed: int = GlacierProps.batch(band, entries, node_name, cast_shadow)
	for child: Node in band.get_children():
		var instance := child as MultiMeshInstance3D
		if instance == null:
			continue
		instance.visibility_range_end = view_end
		instance.visibility_range_end_margin = VIEW_MARGIN
		instance.visibility_range_fade_mode = \
			GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	return placed


## Centre of the lap, used to read which side of the pass a point is on.
static func _map_centre(spline: RefCounted) -> Vector3:
	var total: float = maxf(float(spline.total_length), 1.0)
	var sum := Vector3.ZERO
	for index in 48:
		var point: Vector3 = spline.sample(total * float(index) / 48.0)["position"]
		sum += Vector3(point.x, 0.0, point.z)
	return sum / 48.0


## Road deck height at an arc-length position, in metres.
static func _deck_at(spline: RefCounted, distance: float) -> float:
	var frame: Dictionary = spline.sample(distance)
	return (frame["position"] as Vector3).y


## The horizontal direction that points away from the lap centre.
static func _outward(at: Vector3, centre: Vector3, right: Vector3) -> Vector3:
	var flat := Vector3(at.x - centre.x, 0.0, at.z - centre.z)
	if flat.length_squared() < 0.01:
		return right
	return right if right.dot(flat) >= 0.0 else -right


## Publishes the closest approach of a finished family. The gate in the planting
## loop already refuses anything nearer than the limit, so this is a guard for
## future edits, not the place the invariant is held.
static func _report(label: String, count: int, closest: float,
		limit: float) -> void:
	var shown: String = "n/a" if closest == INF else "%.2f" % closest
	print("GLACIER CLEARANCE %s: %d position(s), closest %s m, limit %.2f m" % [
		label, count, shown, limit])
	if closest != INF and closest < limit - 0.02 and OS.is_debug_build():
		push_error("GlacierForest: %s has a prop %.2f m from the centreline, inside %.2f m." % [
			label, closest, limit])


## One batch per model part, per band: the screen mix, the backdrop mix, the
## ridge mix and the underbrush mix never share a MultiMesh.
static func _draw_estimate(bands: Array) -> int:
	var draws: int = 0
	for band: Variant in bands:
		var models: Dictionary = {}
		for entry: Variant in band as Array:
			models[str((entry as Dictionary)["model"])] = true
		draws += models.size()
	return draws


## Empty per-sector tally, so the build log can prove the forest is laid out the
## way this file describes instead of just being dense.
static func _sector_counts() -> Dictionary:
	return {"wall": 0, "base": 0, "descent": 0, "opening": 0, "infield": 0,
		"other": 0}
