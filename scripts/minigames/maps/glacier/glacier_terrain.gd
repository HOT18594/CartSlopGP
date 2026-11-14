extends RefCounted
## Alpine terrain dressing for Glacier Pass: the mountain the road is cut into.
##
## Three passes, all built from the Kenney nature kit so the map stays flat
## cartoon art:
##
##   cliffs    rock faces planted just outside the barrier line wherever the
##             road deck is above the snow. They rise from the ground to the
##             deck, which is what makes an elevated cell read as a road cut
##             into a hillside instead of a slab floating over a white plane.
##   outcrops  boulder clusters further out, on both sides, following the same
##             clearance path as the barriers so they can never creep onto the
##             road. A rock is always based at ground level: no floating.
##   ridges    three rings of big cliff blocks 150-330 m out, which give the
##             chase camera a horizon and hide the edge of the ground plate.
##
## Plus the ski-lift line: six pylons on a straight run in the infield, a post
## and a cross arm each, solid on CollisionLayers.WORLD. Every solid position is
## checked in plan against the racing centreline before it is accepted.

const GlacierProps := preload("res://scripts/minigames/maps/glacier/glacier_props.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")

const TILE: float = TileCatalog.TILE_SIZE
const NATURE: float = TileCatalog.NATURE_SCALE

## Cliff faces hugging the road: just outside the barrier't outer face, so the
## 5 m wide collider still starts well beyond BARRIER_CLEARANCE.
const CLIFF_LATERAL: float = 13.2
const CLIFF_STEP: float = 8.0
## A deck lower than this is not worth a rock face.
const CLIFF_MIN_DECK: float = 1.2
const MAX_CLIFFS: int = 44
const CLIFF_MODELS: Array[String] = [
	"cliff_large_rock", "cliff_block_rock", "cliff_half_rock",
]

## Boulder clusters further out.
const OUTCROP_LATERAL: float = 18.5
const OUTCROP_STEP: float = 19.0
const MAX_OUTCROPS: int = 38
const OUTCROP_MODELS: Array[String] = [
	"rock_tallA", "rock_tallC", "rock_largeA", "rock_largeB", "rock_largeD",
	"cliff_block_rock",
]

## Distant ridges: rings of oversized blocks. They are outside the playable
## snowfield, but they still carry a collider so a kart can never clip a ridge.
const RIDGE_RINGS: Array[Dictionary] = [
	{"radius": 168.0, "count": 5, "height": 26.0},
	{"radius": 238.0, "count": 6, "height": 38.0},
	{"radius": 318.0, "count": 7, "height": 54.0},
]
const RIDGE_MODELS: Array[String] = [
	"cliff_large_rock", "cliff_blockSlope_rock", "cliff_block_rock",
	"cliff_top_rock",
]

## Ski-lift pylons.
const LIFT_PYLONS: int = 6
const LIFT_SPACING: float = 34.0
const LIFT_OFFSET: float = 42.0
const LIFT_HEIGHT: float = 15.0
const LIFT_POST: String = "lightPostModern"
const LIFT_ARM: String = "rail"
const SEED: int = 20261113


## Builds every terrain pass under `holder`. Returns the piece counts and the
## draw estimate.
static func build(holder: Node3D, spline: RefCounted) -> Dictionary:
	var stats: Dictionary = {
		"cliffs": 0, "outcrops": 0, "ridges": 0, "pylons": 0,
		"draws": 0, "objects": 0,
	}
	if holder == null or spline == null:
		return stats
	stats["cliffs"] = _cliffs(holder, spline)
	stats["outcrops"] = _outcrops(holder, spline)
	stats["ridges"] = _ridges(holder, spline)
	stats["pylons"] = _ski_lift(holder, spline)
	stats["objects"] = int(stats["cliffs"]) + int(stats["outcrops"]) \
		+ int(stats["ridges"]) + int(stats["pylons"])
	stats["draws"] = _draw_estimate(stats)
	return stats


# --------------------------------------------------------------------------
# cliffs along the road
# --------------------------------------------------------------------------


## Rock faces under a raised deck. Every cliff is a nature block scaled to the
## deck height at that point and based on y = 0, so it meets the ground and the
## road shoulder at once with no gap and no float.
static func _cliffs(holder: Node3D, spline: RefCounted) -> int:
	var entries: Array = []
	var points: Array = []
	var body: StaticBody3D = GlacierProps.body(holder, "GlacierCliffs")
	for side: float in [-1.0, 1.0]:
		var path: Dictionary = GlacierProps.constant_path(spline, side,
			CLIFF_LATERAL)
		if not bool(path.get("ok", false)):
			continue
		var length: float = float(path["total_length"])
		var count: int = int(floor(length / CLIFF_STEP))
		for index in count:
			if entries.size() >= MAX_CLIFFS:
				break
			var at: Vector3 = GlacierProps.path_point(path,
				(float(index) + 0.5) * CLIFF_STEP)
			var deck_height: float = maxf(at.y, 0.0)
			if deck_height < CLIFF_MIN_DECK:
				continue
			var forward: Vector3 = GlacierProps.path_forward(path,
				(float(index) + 0.5) * CLIFF_STEP)
			var model: String = CLIFF_MODELS[index % CLIFF_MODELS.size()]
			# Stack the face so its top lands on the deck: one block for a low
			# shoulder, two for the summit cut.
			var block_height: float = deck_height
			var scale: float = GlacierProps.scale_for_height(model,
				block_height, true)
			scale = clampf(scale, 1.2, 9.0)
			var yaw: float = GlacierProps.axis_yaw(model, scale, forward, true)
			var base := Vector3(at.x, 0.0, at.z)
			entries.append({"model": model, "nature": true,
				"transform": GlacierProps.fit(model, base, yaw, scale, true)})
			points.append(base)
			var width: float = minf(GlacierProps.footprint(model, scale,
				true).x * 0.72, 5.5)
			GlacierProps.box(body, base + Vector3.UP * (block_height * 0.5),
				Vector3(width, block_height, width))
	if entries.is_empty():
		body.free()
		return 0
	GlacierProps.batch(holder, entries, "GlacierCliffs", true)
	GlacierProps.assert_clearance("GlacierCliffs", points, spline)
	return entries.size()


# --------------------------------------------------------------------------
# outcrops
# --------------------------------------------------------------------------


## Boulder fields on both sides of the pass. Grounded on the snow, batched per
## model, one box collider each.
static func _outcrops(holder: Node3D, spline: RefCounted) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var entries: Array = []
	var points: Array = []
	var body: StaticBody3D = GlacierProps.body(holder, "GlacierOutcrops")
	for side: float in [-1.0, 1.0]:
		var path: Dictionary = GlacierProps.constant_path(spline, side,
			OUTCROP_LATERAL)
		if not bool(path.get("ok", false)):
			continue
		var length: float = float(path["total_length"])
		var count: int = int(floor(length / OUTCROP_STEP))
		for index in count:
			if entries.size() >= MAX_OUTCROPS:
				break
			var at: Vector3 = GlacierProps.path_point(path,
				(float(index) + 0.5) * OUTCROP_STEP)
			var jitter := Vector3(rng.randf_range(-4.0, 4.0), 0.0,
				rng.randf_range(-4.0, 4.0))
			var base := Vector3(at.x + jitter.x, 0.0, at.z + jitter.z)
			if GlacierProps.clearance(spline, base) < GlacierProps.SOLID_CLEARANCE:
				continue
			var model: String = OUTCROP_MODELS[rng.randi_range(0,
				OUTCROP_MODELS.size() - 1)]
			var scale: float = NATURE * rng.randf_range(0.75, 1.25)
			var yaw: float = rng.randf_range(0.0, TAU)
			entries.append({"model": model, "nature": true,
				"transform": GlacierProps.fit(model, base, yaw, scale, true)})
			points.append(base)
			var plan: Vector2 = GlacierProps.footprint(model, scale, true)
			var height: float = GlacierProps.height(model, scale, true)
			GlacierProps.box(body, base + Vector3.UP * (height * 0.5),
				Vector3(minf(plan.x, 6.5), height, minf(plan.y, 6.5)))
	if entries.is_empty():
		body.free()
		return 0
	GlacierProps.batch(holder, entries, "GlacierOutcrops", true)
	GlacierProps.assert_clearance("GlacierOutcrops", points, spline)
	return entries.size()


# --------------------------------------------------------------------------
# distant ridges
# --------------------------------------------------------------------------


## Three rings of oversized cliff blocks, so every camera angle has a mountain
## horizon behind the pine band.
static func _ridges(holder: Node3D, spline: RefCounted) -> int:
	var centre: Vector3 = _map_centre(spline)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 7
	var entries: Array = []
	var points: Array = []
	var body: StaticBody3D = GlacierProps.body(holder, "GlacierRidges")
	for ring: Dictionary in RIDGE_RINGS:
		var radius: float = float(ring["radius"])
		var count: int = int(ring["count"])
		var height: float = float(ring["height"])
		for index in count:
			var angle: float = TAU * (float(index) + 0.5) / float(count) \
				+ rng.randf_range(-0.10, 0.10)
			var base := Vector3(centre.x + cos(angle) * radius, 0.0,
				centre.z + sin(angle) * radius)
			if GlacierProps.clearance(spline, base) < 40.0:
				continue
			var model: String = RIDGE_MODELS[rng.randi_range(0,
				RIDGE_MODELS.size() - 1)]
			var scale: float = GlacierProps.scale_for_height(model,
				height * rng.randf_range(0.8, 1.15), true)
			var yaw: float = -angle + rng.randf_range(-0.35, 0.35)
			entries.append({"model": model, "nature": true,
				"transform": GlacierProps.fit(model, base, yaw, scale, true)})
			points.append(base)
			var plan: Vector2 = GlacierProps.footprint(model, scale, true)
			var ridge_height: float = GlacierProps.height(model, scale, true)
			GlacierProps.box(body, base + Vector3.UP * (ridge_height * 0.5),
				Vector3(plan.x * 0.8, ridge_height, plan.y * 0.8))
	if entries.is_empty():
		body.free()
		return 0
	GlacierProps.batch(holder, entries, "GlacierRidges", true)
	return entries.size()


# --------------------------------------------------------------------------
# ski lift
# --------------------------------------------------------------------------


## Six pylons on a line in the infield, parallel to the longest straight, with a
## cross arm near the top. Trees cover the cable run, so the line reads as lift
## infrastructure without adding a primitive the kit does not ship.
static func _ski_lift(holder: Node3D, spline: RefCounted) -> int:
	var straight: Dictionary = _longest_straight(spline)
	if straight.is_empty():
		return 0
	var distance: float = float(straight["distance"])
	var forward: Vector3 = (spline.sample(distance)["forward"] as Vector3)
	forward.y = 0.0
	if forward.length() < 0.01:
		return 0
	forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var centre: Vector3 = spline.sample(distance)["position"] as Vector3
	# A lift line needs open ground: try both sides at two offsets, because a
	# pinched figure-of-eight leaves only some of the infield clear.
	var chosen: float = 0.0
	var chosen_offset: float = LIFT_OFFSET
	for offset: float in [LIFT_OFFSET, LIFT_OFFSET * 1.7]:
		for side: float in [-1.0, 1.0]:
			var candidate: Vector3 = centre + right * (offset * side)
			if GlacierProps.clearance(spline, candidate) >= offset - 2.0:
				chosen = side
				chosen_offset = offset
				break
		if chosen != 0.0:
			break
	if chosen == 0.0:
		print("GLACIER SKI LIFT: no clear side for the lift line at %.0f m" % (
			float(straight["distance"])))
		return 0
	var post_scale: float = GlacierProps.scale_for_height(LIFT_POST,
		LIFT_HEIGHT)
	var arm_scale: float = 9.0
	var entries: Array = []
	var points: Array = []
	var body: StaticBody3D = GlacierProps.body(holder, "GlacierSkiLift")
	for index in LIFT_PYLONS:
		var offset: float = (float(index) - float(LIFT_PYLONS - 1) * 0.5) \
			* LIFT_SPACING
		var base: Vector3 = centre + forward * offset \
			+ right * (chosen_offset * chosen)
		base.y = 0.0
		if GlacierProps.clearance(spline, base) < 24.0:
			continue
		points.append(base)
		entries.append({"model": LIFT_POST,
			"transform": GlacierProps.fit(LIFT_POST, base,
				GlacierProps.axis_yaw(LIFT_POST, post_scale, forward),
				post_scale)})
		var arm_at: Vector3 = base + Vector3.UP * (LIFT_HEIGHT * 0.86)
		entries.append({"model": LIFT_ARM,
			"transform": GlacierProps.fit(LIFT_ARM, arm_at,
				GlacierProps.axis_yaw(LIFT_ARM, arm_scale, right),
				arm_scale)})
		GlacierProps.cylinder(body, base, 0.9, LIFT_HEIGHT)
		GlacierProps.box(body, arm_at, Vector3(9.0, 0.6, 0.6),
			GlacierProps.axis_yaw(LIFT_ARM, arm_scale, right))
	if entries.is_empty():
		body.free()
		return 0
	GlacierProps.batch(holder, entries, "GlacierSkiLift", true)
	GlacierProps.assert_clearance("GlacierSkiLift", points, spline)
	return points.size()


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------


## Centre of the lap's plan bounds, used to ring the ridges around the map.
static func _map_centre(spline: RefCounted) -> Vector3:
	var total: float = maxf(float(spline.total_length), 1.0)
	var sum := Vector3.ZERO
	for index in 48:
		var point: Vector3 = spline.sample(total * float(index) / 48.0)["position"]
		sum += Vector3(point.x, 0.0, point.z)
	return sum / 48.0


## Longest straight run of the lap, which is where a lift line fits without
## crossing the road.
static func _longest_straight(spline: RefCounted) -> Dictionary:
	return GlacierProps.longest_straight(spline)


static func _draw_estimate(stats: Dictionary) -> int:
	var draws: int = 0
	if int(stats["cliffs"]) > 0:
		draws += CLIFF_MODELS.size()
	if int(stats["outcrops"]) > 0:
		draws += OUTCROP_MODELS.size()
	if int(stats["ridges"]) > 0:
		draws += RIDGE_MODELS.size()
	if int(stats["pylons"]) > 0:
		draws += 2
	return draws
