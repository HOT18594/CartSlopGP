extends RefCounted
## Designed woodland belt for the KENNEY STADIUM CIRCUIT.
##
## The circuit is a ring of road inside a ring of grandstands, so the treeline
## has one job beyond decoration: enclose the bowl. It is built as a woodland
## belt between FOREST_MIN and FOREST_OUT metres from the centreline - beyond
## the second stand tier - and it is designed, not scattered:
##
##   density   three octaves of value noise set the clumps. Dense stands,
##             ragged edges and open meadows all come out of that one field, so
##             no two stretches of the belt look alike.
##   rows      the belt is about 85 m deep, a dozen plant rows: crowns of the
##             first rows overlap, so the world edge behind them never shows
##             through a gap.
##   framing   the two longest grandstand runs get a clearing behind their
##             stands, so the crowd and the covered main stand read against
##             open sky, and the start gantry gets a deeper notch. A smaller
##             clearing opens the footbridge vista over the valley.
##   closure   every corner gets a denser stand, the two fast corners and the
##             infield hairpin more than the rest, so a corner exit is closed by
##             timber instead of sky.
##   variety   nine nature-kit species plus the racing kit's treeLarge and
##             treeSmall, each with its own scale band and a random yaw.
##   edge      bushes, flat plants and grass clumps run along the barrier line
##             and along the foot of the treeline, so neither starts from bare
##             ground.
##
## Clearance is the owner's invariant: a candidate becomes a tree only when its
## plan distance is at least FOREST_MIN and it lies on the outside of the lap,
## so the woodland cannot grow onto the road or into the infield paddock. Trees
## carry no collider: the barrier ring and the two stand tiers stand between the
## racing surface and the belt, so no trunk is reachable, and 600 static
## cylinders would only cost the browser build's broadphase.
##
## Every model is one MultiMesh per band (the far band splits into four
## quadrants and carries a visibility range), so the whole woodland costs about
## three dozen draw nodes instead of six hundred, and the far half of the ring
## can drop out of the frame while the camera is on the other side of the bowl.

const Props := preload("res://scripts/minigames/maps/stadium/stadium_props.gd")

## Plan distance from the centreline at which the first trunk may stand. The
## outer stand tier sits 36 m out and reaches 44 m; 47 m leaves a row of meadow
## behind the seats instead of growing trunks through them.
const FOREST_MIN: float = 47.0
## Density is feathered in over this distance, so the edge is not a cut circle.
const FOREST_IN: float = 50.0
## The belt starts thinning here and is gone at FOREST_OUT.
const FOREST_FADE: float = 114.0
const FOREST_OUT: float = 134.0
## Plant lattice step, the closest two trunks may stand, and the deterministic
## seed: the woodland must be identical on every build and every peer.
const CELL: float = 7.0
const MIN_SPACING: float = 4.4
const SEED: int = 20261114
## The belt is capped into the 450-650 tree budget the bowl was designed for.
const TREE_MIN: int = 450
const TREE_MAX: int = 640
## Depth at which a tree joins the backdrop layer.
const BACKDROP: float = 82.0
## Cull distance of the backdrop quadrants, in metres. The bowl is 220 m across,
## so this drops the outermost silhouettes of the far diagonal while the near
## band behind the camera's side is always inside the range.
const CULL_END: float = 260.0

## Grandstand clearings. Each of the two longest stand runs gets a shallow
## canopy vista over the middle of the stand, not a clear-cut: the belt steps
## back just far enough for the stand roof and its crowd to read against sky,
## then returns to full depth by CLEAR_DEEP metres out.
const CLEAR_RUNS: int = 2
const CLEAR_HALF: float = 30.0
const CLEAR_FADE: float = 22.0
const CLEAR_SHALLOW: float = 58.0
const CLEAR_DEEP: float = 82.0
## The start gantry notch, measured from the start/finish distance: deeper than
## a stand vista, so the gantry silhouettes against open sky.
const GANTRY_EDGE: float = 22.0
const GANTRY_FADE: float = 18.0
const GANTRY_SHALLOW: float = 74.0
const GANTRY_DEEP: float = 104.0
## The footbridge vista: a narrow clearing behind the valley landmark.
const BRIDGE_CLEAR: float = 10.0
const BRIDGE_FADE: float = 10.0
const BRIDGE_SHALLOW: float = 56.0
const BRIDGE_DEEP: float = 76.0

## Corner stands. The additive term is applied after the grandstand clearings,
## so a corner wall still rises at the end of an open stand run and frames it.
const CORNER_REACH: float = 36.0
const CORNER_ADD: float = 0.14
const FAST_REACH: float = 52.0
const FAST_ADD: float = 0.30
const TIGHT_REACH: float = 38.0
const TIGHT_ADD: float = 0.52

## Undergrowth. The fence-line ribbon stands between the barrier's outer face
## (~9.3 m) and the stand fronts (~11.4 m), and the tyre walls own the outside
## of the two tight corners, so the ribbon skips those laps.
const FENCE_LATERAL: float = 10.6
const FENCE_SPACING: float = 3.6
const FENCE_SKIP: float = 0.32
const FENCE_SCALE: float = 0.55
const TYRE_CLEAR: float = 26.0
const EDGE_LATERAL: float = 54.0
const EDGE_SPACING: float = 4.4
const EDGE_JITTER: float = 3.5
const EDGE_KEEP: float = 0.34

## Woodland species. `min`/`max` multiply the kit's own metre scale. The belt
## faces stand tiers 14-22 m tall, so the nature species are pushed to the tall
## end of their range and the racing treeLarge becomes a 15-25 m emergent crown:
## the treeline has to clear the stand roofs to read as woodland behind them.
const NEAR_SPECIES: Array[Dictionary] = [
	{"model": "tree_default", "nature": true, "weight": 13.0,
		"min": 1.00, "max": 1.35},
	{"model": "tree_oak", "nature": true, "weight": 11.0,
		"min": 1.00, "max": 1.35},
	{"model": "tree_detailed", "nature": true, "weight": 10.0,
		"min": 0.95, "max": 1.25},
	{"model": "tree_fat", "nature": true, "weight": 8.0,
		"min": 0.95, "max": 1.30},
	{"model": "tree_cone", "nature": true, "weight": 11.0,
		"min": 1.00, "max": 1.35},
	{"model": "tree_pineTallA", "nature": true, "weight": 12.0,
		"min": 0.95, "max": 1.30},
	{"model": "tree_default_fall", "nature": true, "weight": 8.0,
		"min": 0.95, "max": 1.30},
	{"model": "tree_oak_fall", "nature": true, "weight": 7.0,
		"min": 1.00, "max": 1.35},
	{"model": "tree_default_dark", "nature": true, "weight": 6.0,
		"min": 0.95, "max": 1.30},
	{"model": "treeLarge", "nature": false, "weight": 11.0,
		"min": 0.62, "max": 0.85},
	{"model": "treeSmall", "nature": false, "weight": 9.0,
		"min": 0.68, "max": 0.92},
]
## The far band is read as a silhouette, so it favours the tall crowns and drops
## the small species: fewer models, bigger shapes.
const FAR_SPECIES: Array[Dictionary] = [
	{"model": "tree_pineTallA", "nature": true, "weight": 26.0,
		"min": 1.15, "max": 1.50},
	{"model": "tree_cone", "nature": true, "weight": 24.0,
		"min": 1.15, "max": 1.50},
	{"model": "tree_default_fall", "nature": true, "weight": 20.0,
		"min": 1.10, "max": 1.45},
	{"model": "tree_oak", "nature": true, "weight": 15.0,
		"min": 1.15, "max": 1.45},
	{"model": "treeLarge", "nature": false, "weight": 15.0,
		"min": 0.80, "max": 1.05},
]
## The only species that come from the racing kit, which is scaled in metres
## per model unit rather than the nature kit's smaller unit.
const RACING_TREES: Array[String] = ["treeLarge", "treeSmall"]
const UNDERGROWTH: Array[Dictionary] = [
	{"model": "plant_bush", "weight": 26.0, "min": 0.55, "max": 0.95},
	{"model": "plant_bushLarge", "weight": 20.0, "min": 0.55, "max": 0.95},
	{"model": "plant_flatShort", "weight": 20.0, "min": 0.60, "max": 1.00},
	{"model": "plant_flatTall", "weight": 14.0, "min": 0.60, "max": 1.00},
	{"model": "grass", "weight": 20.0, "min": 0.45, "max": 0.75},
]

const SALT_JITTER: int = 11
const SALT_CLUMP_A: int = 101
const SALT_CLUMP_B: int = 211
const SALT_CLUMP_C: int = 307
const SALT_FENCE: int = 401
const SALT_EDGE: int = 503


## Plants the designed woodland under `holder`. Returns {trees, underbrush,
## draws, near, far, nearest}, where `nearest` is the plan distance of the
## closest trunk to the centreline, in metres.
static func build(holder: Node3D, spline: RefCounted,
		plan: Dictionary) -> Dictionary:
	var report: Dictionary = {"trees": 0, "underbrush": 0, "draws": 0,
		"near": 0, "far": 0, "nearest": 0.0}
	if holder == null or spline == null or plan.is_empty():
		return report
	if float(plan.get("total", 0.0)) <= 1.0:
		return report
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var sites: Array = _select(spline, plan, rng)
	if sites.is_empty():
		return report
	var root := Node3D.new()
	root.name = "DesignedForest"
	holder.add_child(root)
	var centre: Vector2 = (plan["bounds"] as Rect2).get_center()
	var near_batches: Dictionary = {}
	var far_batches: Dictionary = {}
	var nearest: float = INF
	for site: Dictionary in sites:
		var point: Vector3 = site["position"]
		var clearance: float = float(site["clearance"])
		nearest = minf(nearest, clearance)
		var far: bool = clearance >= BACKDROP
		var species: Dictionary = _pick(FAR_SPECIES if far else NEAR_SPECIES,
			rng.randf())
		var model: String = str(species["model"])
		var nature: bool = bool(species["nature"])
		var factor: float = rng.randf_range(float(species["min"]),
			float(species["max"]))
		var base: float = Props.NATURE_SCALE if nature else Props.PROP_SCALE
		var xform: Transform3D = Props.fit(model, point,
			rng.randf_range(0.0, TAU), Vector3.ONE * (base * factor), nature)
		if far:
			var quadrant: int = _quadrant(point, centre)
			var key: String = "%d:%s" % [quadrant, model]
			var batch: Dictionary = far_batches.get(key,
				{"model": model, "nature": nature, "quadrant": quadrant,
					"transforms": []})
			(batch["transforms"] as Array).append(xform)
			far_batches[key] = batch
			report["far"] = int(report["far"]) + 1
		else:
			if not near_batches.has(model):
				near_batches[model] = []
			(near_batches[model] as Array).append(xform)
			report["near"] = int(report["near"]) + 1
	var draws: int = 0
	for model: String in near_batches:
		draws += Props.batch(root, model, near_batches[model] as Array,
			"Forest_" + model, false, _nature(model))
	for key: String in far_batches:
		var batch: Dictionary = far_batches[key] as Dictionary
		draws += Props.batch(root, str(batch["model"]),
			batch["transforms"] as Array,
			"Backdrop_%d_%s" % [int(batch["quadrant"]), str(batch["model"])],
			false, bool(batch["nature"]), CULL_END)
	var brush: Dictionary = _underbrush(spline, plan, rng)
	var underbrush: int = 0
	for model: String in brush:
		var transforms: Array = brush[model] as Array
		underbrush += transforms.size()
		draws += Props.batch(root, model, transforms, "Forest_Brush_" + model,
			false, true)
	report["trees"] = sites.size()
	report["underbrush"] = underbrush
	report["draws"] = draws
	report["nearest"] = 0.0 if nearest == INF else nearest
	print(("STADIUM FOREST: %d tree(s) (%d near band, %d backdrop), nearest " \
		+ "trunk %.1f m, %d undergrowth clump(s), %d draw node(s)") % [
		int(report["trees"]), int(report["near"]), int(report["far"]),
		float(report["nearest"]), underbrush, draws])
	return report


# --------------------------------------------------------------------------
# site selection

## Candidate trees: jittered lattice points in the belt, filtered by plan
## clearance, side of the lap and the designed density field. The list keeps the
## density of every eligible point so the target count can be filled or thinned
## without ever putting a trunk inside the barrier line.
static func _candidate_list(spline: RefCounted, plan: Dictionary) -> Array:
	var candidates: Array = []
	var area: Rect2 = (plan["bounds"] as Rect2).grow(FOREST_OUT)
	var outside: float = float(plan.get("outside", 1.0))
	var rows: int = int(ceil(area.size.y / CELL))
	var cols: int = int(ceil(area.size.x / CELL))
	for row: int in rows:
		for col: int in cols:
			var x: float = area.position.x + (float(col) + 0.5) * CELL
			var z: float = area.position.y + (float(row) + 0.5) * CELL
			var jitter: Vector2 = Vector2(
				(_hash_unit(col, row, SALT_JITTER) - 0.5) * CELL * 0.62,
				(_hash_unit(row, col, SALT_JITTER) - 0.5) * CELL * 0.62)
			var point := Vector3(x + jitter.x, 0.0, z + jitter.y)
			var hit: Dictionary = spline.plan_closest(point)
			var clearance: float = float(hit.get("distance", INF))
			if clearance < FOREST_MIN or clearance > FOREST_OUT:
				continue
			var lap: float = float(hit.get("s", 0.0))
			if not _outside_lap(spline, point, hit, lap, outside):
				continue
			var density: float = _density(point, clearance, lap, plan)
			if density < 0.03:
				continue
			candidates.append({"position": point, "clearance": clearance,
				"lap": lap, "density": density, "chosen": false})
	return candidates


## Chooses the final tree set: one deterministic draw per candidate against its
## density, a minimum trunk spacing, then a fill or a thin to the tree budget.
static func _select(spline: RefCounted, plan: Dictionary,
		rng: RandomNumberGenerator) -> Array:
	var candidates: Array = _candidate_list(spline, plan)
	_shuffle(candidates, rng)
	var chosen: Array = []
	var spacing: Dictionary = {}
	for candidate: Dictionary in candidates:
		if rng.randf() >= float(candidate["density"]):
			continue
		var point: Vector3 = candidate["position"]
		if not _spacing_ok(spacing, point):
			continue
		candidate["chosen"] = true
		chosen.append(candidate)
		_spacing_add(spacing, point)
	if chosen.size() < TREE_MIN:
		_fill(candidates, chosen, spacing)
	if chosen.size() > TREE_MAX:
		_thin(chosen, rng)
	return chosen


## Fills a thin belt up to TREE_MIN from the densest rejected sites. A clearing
## has density 0, so the fill can never plant into one.
static func _fill(candidates: Array, chosen: Array,
		spacing: Dictionary) -> void:
	var ranked: Array = candidates.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["density"]) > float(b["density"]))
	for candidate: Dictionary in ranked:
		if chosen.size() >= TREE_MIN:
			return
		if bool(candidate.get("chosen", false)):
			continue
		var point: Vector3 = candidate["position"]
		if not _spacing_ok(spacing, point):
			continue
		candidate["chosen"] = true
		chosen.append(candidate)
		_spacing_add(spacing, point)


## Thins an over-dense belt with a seeded shuffle, so the cap falls evenly over
## the whole ring instead of cutting the lap at one distance.
static func _thin(chosen: Array, rng: RandomNumberGenerator) -> void:
	_shuffle(chosen, rng)
	chosen.resize(TREE_MAX)


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap: int = rng.randi_range(0, index)
		var hold: Variant = values[index]
		values[index] = values[swap]
		values[swap] = hold


## True when `point` stands on the outside of the lap, which is the only side
## the woodland may occupy: the infield holds the pit lane and the paddock.
static func _outside_lap(spline: RefCounted, point: Vector3,
		hit: Dictionary, lap: float, outside: float) -> bool:
	var frame: Dictionary = spline.sample(lap)
	var right: Vector3 = frame["right"]
	var nearest: Vector3 = hit.get("point", Vector3.ZERO)
	return (point - nearest).dot(right) * outside > 0.0


## Minimum-spacing hash: 4.4 m between trunks, checked across the 3x3 cells
## around a point because a hash cell is one minimum spacing wide.
static func _spacing_ok(spacing: Dictionary, point: Vector3) -> bool:
	var key := Vector2i(floori(point.x / MIN_SPACING),
		floori(point.z / MIN_SPACING))
	var here := Vector2(point.x, point.z)
	for offset_x: int in [-1, 0, 1]:
		for offset_z: int in [-1, 0, 1]:
			var bucket: Variant = spacing.get(
				key + Vector2i(offset_x, offset_z), null)
			if not (bucket is Array):
				continue
			for other: Vector2 in bucket as Array:
				if here.distance_squared_to(other) \
						< MIN_SPACING * MIN_SPACING:
					return false
	return true


static func _spacing_add(spacing: Dictionary, point: Vector3) -> void:
	var key := Vector2i(floori(point.x / MIN_SPACING),
		floori(point.z / MIN_SPACING))
	if not spacing.has(key):
		spacing[key] = []
	(spacing[key] as Array).append(Vector2(point.x, point.z))


# --------------------------------------------------------------------------
# the density field

## Probability that a lattice point in the belt grows a tree: the radial band,
## the noise clumps and the designed clearings multiply, then the corner stand
## is added so it still rises at the end of an open stand run.
static func _density(point: Vector3, clearance: float, lap: float,
		plan: Dictionary) -> float:
	var density: float = _band_base(clearance) \
		* (0.28 + 0.92 * _clump(point))
	density *= _clearing(lap, clearance, plan)
	density += _corner_wall(lap, plan)
	density *= _envelope(clearance)
	return clampf(density, 0.0, 0.95)


## Full strength through the pack, feathering in at the stands and out at the
## far edge so the woodland has no hard boundary.
static func _envelope(clearance: float) -> float:
	if clearance < FOREST_MIN or clearance > FOREST_OUT:
		return 0.0
	if clearance < FOREST_IN:
		return smoothstep(FOREST_MIN, FOREST_IN, clearance)
	if clearance <= FOREST_FADE:
		return 1.0
	return 1.0 - smoothstep(FOREST_FADE, FOREST_OUT, clearance)


## Radial density of the belt: near the stands it is nearly solid (the crowns
## will overlap), then it thins with depth so the far silhouettes read as a
## treeline and not as a wall.
static func _band_base(clearance: float) -> float:
	if clearance < 62.0:
		return 0.98
	if clearance < 82.0:
		return lerpf(0.98, 0.72, smoothstep(62.0, 82.0, clearance))
	if clearance < 100.0:
		return lerpf(0.72, 0.22, smoothstep(82.0, 100.0, clearance))
	return lerpf(0.22, 0.06, smoothstep(100.0, FOREST_OUT, clearance))


## Three octaves of value noise: 60 m stands, 24 m clumps and 10 m ragged edges,
## shaped into dense cores with thinning fringes.
static func _clump(point: Vector3) -> float:
	var noise: float = 0.58 \
		* _value_noise(point.x * 0.016, point.z * 0.016, SALT_CLUMP_A) \
		+ 0.29 * _value_noise(point.x * 0.041, point.z * 0.041,
			SALT_CLUMP_B) \
		+ 0.13 * _value_noise(point.x * 0.098, point.z * 0.098,
			SALT_CLUMP_C)
	return smoothstep(0.32, 0.68, noise)


## Designed clearings, all expressed as a 0..1 multiplier on the clump density.
## 1 keeps the woodland; 0 is a true clearing.
static func _clearing(lap: float, clearance: float,
		plan: Dictionary) -> float:
	var total: float = float(plan.get("total", 0.0))
	if total <= 1.0:
		return 1.0
	var factor: float = 1.0
	for centre: float in _grandstand_centres(plan):
		var gap: float = _lap_gap(lap, centre, total)
		if gap >= CLEAR_HALF + CLEAR_FADE:
			continue
		var along: float = 1.0 - smoothstep(CLEAR_HALF,
			CLEAR_HALF + CLEAR_FADE, gap)
		var across: float = smoothstep(CLEAR_SHALLOW, CLEAR_DEEP, clearance)
		factor = minf(factor, lerpf(1.0, across, along))
	var gantry_gap: float = _lap_gap(lap,
		float(plan.get("start_distance", 0.0)), total)
	if gantry_gap < GANTRY_EDGE + GANTRY_FADE:
		var along_g: float = 1.0 - smoothstep(GANTRY_EDGE,
			GANTRY_EDGE + GANTRY_FADE, gantry_gap)
		var across_g: float = smoothstep(GANTRY_SHALLOW, GANTRY_DEEP, clearance)
		factor = minf(factor, lerpf(1.0, across_g, along_g))
	var valley: Dictionary = plan.get("valley", {}) as Dictionary
	if bool(valley.get("ok", false)):
		var middle: float = (float(valley["from"]) + float(valley["to"])) * 0.5
		var bridge_gap: float = _lap_gap(lap, middle, total)
		if bridge_gap < BRIDGE_CLEAR + BRIDGE_FADE:
			var along_b: float = 1.0 - smoothstep(BRIDGE_CLEAR,
				BRIDGE_CLEAR + BRIDGE_FADE, bridge_gap)
			var across_b: float = smoothstep(BRIDGE_SHALLOW, BRIDGE_DEEP,
				clearance)
			factor = minf(factor, lerpf(1.0, across_b, along_b))
	return factor


## Lap distance at the middle of each of the two longest stand runs: the two
## stand vistas the woodland is framed around.
static func _grandstand_centres(plan: Dictionary) -> Array[float]:
	var centres: Array[float] = []
	var straights: Array = plan.get("straights", []) as Array
	var total: float = float(plan.get("total", 1.0))
	for index: int in straights.size():
		if centres.size() >= CLEAR_RUNS:
			break
		var run: Dictionary = straights[index] as Dictionary
		if float(run.get("length", 0.0)) < 40.0:
			continue
		centres.append(fposmod((float(run["from"]) + float(run["to"])) * 0.5,
			total))
	return centres


## Additive tree wall around corners, independent of the clump field: this is
## what closes the view out of a fast exit and behind the infield hairpin.
static func _corner_wall(lap: float, plan: Dictionary) -> float:
	var total: float = float(plan.get("total", 0.0))
	if total <= 1.0:
		return 0.0
	var add: float = _ring_add(lap, plan.get("corners", []) as Array,
		CORNER_REACH, CORNER_ADD, total)
	add = maxf(add, _ring_add(lap, plan.get("fast_corners", []) as Array,
		FAST_REACH, FAST_ADD, total))
	add = maxf(add, _ring_add(lap, plan.get("tight_corners", []) as Array,
		TIGHT_REACH, TIGHT_ADD, total))
	return add


## Strongest corner contribution at `lap`: `amount` at an apex, feathered to
## zero at `reach` metres of lap either side.
static func _ring_add(lap: float, entries: Array, reach: float, amount: float,
		total: float) -> float:
	var add: float = 0.0
	for entry: Dictionary in entries:
		var gap: float = _lap_gap(lap, float(entry["distance"]), total)
		if gap >= reach:
			continue
		add = maxf(add, amount * (1.0 - smoothstep(0.0, reach, gap)))
	return add


## Shortest wrapped distance between two lap positions.
static func _lap_gap(a: float, b: float, total: float) -> float:
	if total <= 0.01:
		return absf(a - b)
	return absf(fposmod(a - b + total * 0.5, total) - total * 0.5)


# --------------------------------------------------------------------------
# undergrowth

## Bushes, flat plants and grass clumps. A ribbon follows the barrier line
## between the wall and the stand fronts, and a second, wider ring sits at the
## foot of the treeline. Both are pooled into one batch per model.
static func _underbrush(spline: RefCounted, plan: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var batches: Dictionary = {}
	var total: float = float(plan.get("total", 0.0))
	var outside: float = float(plan.get("outside", 1.0))
	var fence_ring: Dictionary = Props.ring(spline, outside, FENCE_LATERAL)
	var index: int = 0
	var lap: float = 0.0
	while lap < total:
		if not _near_tyres(lap, plan) \
				and _hash_unit(index, 1, SALT_FENCE) > FENCE_SKIP:
			var point: Vector3 = Props.ring_point(fence_ring,
				Props.ring_position(fence_ring, lap))
			point.y = 0.0
			_brush(batches, point, FENCE_SCALE, rng)
		index += 1
		lap += FENCE_SPACING
	var edge_ring: Dictionary = Props.ring(spline, outside, EDGE_LATERAL)
	var sites: Array = Props.ring_run(edge_ring, 0.0, total, EDGE_SPACING)
	for site: Dictionary in sites:
		var point: Vector3 = (site["position"] as Vector3)
		point.y = 0.0
		var roll: float = _hash_unit(int(round(point.x)), int(round(point.z)),
			SALT_EDGE)
		if roll >= EDGE_KEEP:
			continue
		point += Vector3((_hash_unit(int(round(point.z)), index, SALT_EDGE)
			- 0.5) * EDGE_JITTER * 2.0, 0.0,
			(_hash_unit(index, int(round(point.x)), SALT_EDGE) - 0.5)
			* EDGE_JITTER * 2.0)
		_brush(batches, point, 1.0, rng)
		index += 1
	return batches


## Appends one undergrowth clump to the batch for its species.
static func _brush(batches: Dictionary, point: Vector3, factor: float,
		rng: RandomNumberGenerator) -> void:
	var species: Dictionary = _pick(UNDERGROWTH, rng.randf())
	var model: String = str(species["model"])
	var scale: float = Props.NATURE_SCALE * factor \
		* rng.randf_range(float(species["min"]), float(species["max"]))
	if not batches.has(model):
		batches[model] = []
	(batches[model] as Array).append(Props.fit(model, point,
		rng.randf_range(0.0, TAU), Vector3.ONE * scale, true))


## True when a lap position is inside a tyre wall: those stacks stand at 10.2 m
## and must not be grown through by the 10.6 m undergrowth ribbon.
static func _near_tyres(lap: float, plan: Dictionary) -> bool:
	var total: float = float(plan.get("total", 0.0))
	for corner: Dictionary in plan.get("tight_corners", []) as Array:
		if _lap_gap(lap, float(corner["distance"]), total) <= TYRE_CLEAR:
			return true
	return false


# --------------------------------------------------------------------------
# helpers

## True for the species the nature kit owns; the two racing trees carry their
## own metre scale and so must not be passed to the nature batcher.
static func _nature(model: String) -> bool:
	return not RACING_TREES.has(model)


## Quadrant of the plan rectangle a backdrop tree belongs to, so the far band
## can cull as four coarse chunks.
static func _quadrant(point: Vector3, centre: Vector2) -> int:
	return (1 if point.x >= centre.x else 0) \
		+ (2 if point.z >= centre.y else 0)


## Weighted pick from a species table with a 0..1 roll.
static func _pick(species: Array, roll: float) -> Dictionary:
	var total: float = 0.0
	for entry: Dictionary in species:
		total += float(entry["weight"])
	var wanted: float = roll * total
	for entry: Dictionary in species:
		wanted -= float(entry["weight"])
		if wanted <= 0.0:
			return entry
	return species[species.size() - 1] as Dictionary


## Hash in [0, 1) for a lattice coordinate. Deterministic across builds and
## peers, unlike a random generator seeded from time.
static func _hash_unit(x: int, y: int, salt: int) -> float:
	return float(_hash(x, y, salt) % 104729) / 104729.0


static func _hash(x: int, y: int, salt: int) -> int:
	var value: int = (x * 374761393 + y * 668265263 + salt * 2654435761) \
		& 0x7FFFFFFF
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7FFFFFFF
	return (value ^ (value >> 16)) & 0x7FFFFFFF


## One octave of smooth value noise on the integer lattice.
static func _value_noise(x: float, z: float, salt: int) -> float:
	var cell_x: int = floori(x)
	var cell_z: int = floori(z)
	var fx: float = x - float(cell_x)
	var fz: float = z - float(cell_z)
	var u: float = fx * fx * (3.0 - 2.0 * fx)
	var v: float = fz * fz * (3.0 - 2.0 * fz)
	var low: float = lerpf(_hash_unit(cell_x, cell_z, salt),
		_hash_unit(cell_x + 1, cell_z, salt), u)
	var high: float = lerpf(_hash_unit(cell_x, cell_z + 1, salt),
		_hash_unit(cell_x + 1, cell_z + 1, salt), u)
	return lerpf(low, high, v)
