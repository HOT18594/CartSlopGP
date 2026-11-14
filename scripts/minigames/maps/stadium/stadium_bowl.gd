extends RefCounted
## Outer bowl of the STADIUM CIRCUIT: the part the chase camera sees first.
##
## Everything is placed on the *outside* of the lap, measured from the true road
## edge rather than from hard-coded world points, so a registry grid edit moves
## the whole bowl with the track. The bowl is built as concentric groups:
##
##   tier 1  an unbroken ring of stands one grid cell apart: the seating wall of
##           the stadium, with the covered main stand over the start/finish and
##           awning stands on the far side
##   tier 2  covered stands a further 17 m out along both long sides, offset by
##           half a bay so the two tiers read as a terrace and not as a grid
##   fence   catch fencing on the longest straight and on the outside of the
##           two fastest corners
##   detail  tyre walls at the two tightest corners, a marshal post at every
##           corner, camera cranes, floodlights, sponsor boards and flags
##   green   cliff walls flanking the raised sweep and the valley, a footbridge
##           over the valley, then the tree band beyond the barrier ring
##
## Repeated props are batched into MultiMeshes by stadium_props.gd and every
## solid piece carries a WORLD collider. Nothing here is placed inside the
## barrier line: the theme's clearance audit measures what this module emitted.

const Props := preload("res://scripts/minigames/maps/stadium/stadium_props.gd")
const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")

const GRANDSTAND_OPEN: String = "grandStand"
const GRANDSTAND_COVERED: String = "grandStandCovered"
const GRANDSTAND_AWNING: String = "grandStandAwning"
const GRANDSTAND_ROUND: String = "grandStandRound"
const FENCE_MODEL: String = "fenceStraight"
const CAMERA_MODEL: String = "camera_exclusive"
const LIGHT_MODEL: String = "lightPostLarge"
const MARSHAL_BASE: String = "pylon"
const MARSHAL_FLAG: String = "flagCheckersSmall"
const CLIFF_MODEL: String = "cliff_block_rock"
const BRIDGE_SIDE: String = "bridge_side_stone"
const BRIDGE_CENTER: String = "bridge_center_stone"

## Metres between two stands of the lower ring: one grid cell, so the ring reads
## as a continuous terrace.
const STAND_BAY: float = 16.0
## Lateral distance of the lower stand ring. A stand is a 16 m footprint, so its
## front face lands 11.4 m out: behind the barrier face at 8 m and behind the
## wall body that sits on it.
const STAND_LATERAL: float = 19.4
## Second tier: a ring of covered stands further out, on both long sides.
const TIER_TWO_LATERAL: float = 36.0
const STAND_MAIN_BAYS: float = 6.0

## Lateral distances of the detail props, all outside the barrier face.
const FENCE_LATERAL: float = 11.6
const TYRE_LATERAL: float = 10.2
const MARSHAL_LATERAL: float = 13.4
const CAMERA_LATERAL: float = 23.0
const LIGHT_LATERAL: float = 29.0
const SIGN_LATERAL: float = 14.4
const FLAG_LATERAL: float = 12.4
const CLIFF_LATERAL: float = 14.6
const BRIDGE_DECK: float = 3.7

const TYRE_STACKS_PER_CORNER: int = 6
const TYRE_STACK_SPACING: float = 4.4
## Plan reach of each prop family, in metres: half its widest dimension, used to
## reject a site that would fold back onto the road on the inside of a hairpin.
const STAND_REACH: float = 11.4
const FENCE_REACH: float = 1.0
const TYRE_REACH: float = 1.4
const MARSHAL_REACH: float = 1.9
const CAMERA_REACH: float = 2.2
const LIGHT_REACH: float = 3.2
const FLAG_REACH: float = 1.2
## A 26 m round stand reaches 13 m.
const ROUND_REACH: float = 18.6
## A cliff block reaches 3.6 m; the valley wall stands further out than that.
const CLIFF_REACH: float = 3.6
const CATCH_FENCE_MAX: int = 14
const FLOODLIGHTS: int = 12
const CAMERA_CRANES: int = 6
const FLAG_COUNT: int = 32
const BOARD_COUNT: int = 10
const TREE_BAND: int = 140
const BUSH_BAND: int = 44
## Trees stand beyond the second stand tier, which is the barrier ring's outer
## edge: this is the plan distance that guarantees it.
const TREE_RING_MIN: float = 44.0

const TREE_KINDS: Array[String] = [
	"tree_default", "tree_oak", "tree_pineTallA", "tree_cone", "tree_fat",
	"tree_detailed", "tree_pineRoundA",
]
const BUSH_KINDS: Array[String] = [
	"plant_bush", "plant_bushLarge", "plant_flatShort", "grass",
]
const ROCK_KINDS: Array[String] = [
	"rock_largeA", "rock_largeB", "rock_tallA",
]


## Builds the whole bowl under `holder` and adds its counts to `stats`.
static func build(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	if holder == null or spline == null:
		return
	_grandstands(holder, spline, plan, stats)
	_catch_fence(holder, spline, plan, stats)
	_tyre_walls(holder, spline, plan, stats)
	_marshal_posts(holder, spline, plan, stats)
	_camera_cranes(holder, spline, plan, stats)
	_floodlights(holder, spline, plan, stats)
	_sponsor_boards(holder, spline, plan, stats)
	_flags(holder, spline, plan, stats)
	_cliff_walls(holder, spline, plan, stats)
	_footbridge(holder, spline, plan, stats)
	_tree_band(holder, spline, plan, stats)


# --------------------------------------------------------------------------
# the seating bowl


## Two concentric stand rings, batched into one MultiMesh per model, so the
## whole bowl costs four draw calls however many bays it holds.
static func _grandstands(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	var outside: float = float(plan["outside"])
	var total: float = float(plan["total"])
	var start: float = float(plan["start_distance"])
	var lower_ring: Dictionary = Props.ring(spline, outside, STAND_LATERAL)
	var upper_ring: Dictionary = Props.ring(spline, outside, TIER_TWO_LATERAL)
	var lower: Dictionary = {}
	var upper: Dictionary = {}
	var colliders: Array = []
	var sites: Array = Props.ring_run(lower_ring, 0.0, total, STAND_BAY)
	for index in sites.size():
		var site: Dictionary = sites[index]
		var point: Vector3 = (site["position"] as Vector3)
		point.y = 0.0
		var lap: float = fposmod(start + STAND_BAY * (float(index) + 0.5), total)
		if not Props.site_ok(spline, point, STAND_REACH):
			continue
		var model: String = GRANDSTAND_OPEN
		if _lap_gap(lap, start, total) < STAND_BAY * STAND_MAIN_BAYS:
			model = GRANDSTAND_COVERED
		elif index % 4 == 2:
			model = GRANDSTAND_AWNING
		var yaw: float = stand_yaw(spline, lap, outside)
		_add(lower, model, Props.fit(model, point, yaw,
			Vector3.ONE * Props.PROP_SCALE))
		colliders.append({"model": model, "point": point, "yaw": yaw})
	# One round stand closes each end of the bowl, where the corner makes a
	# square terrace read like a box.
	_round_stands(lower, colliders, spline, plan, outside, start, total)
	var upper_sites: Array = Props.ring_run(upper_ring, 0.0, total,
		STAND_BAY * 2.0)
	for index in upper_sites.size():
		var site: Dictionary = upper_sites[index]
		var point: Vector3 = (site["position"] as Vector3)
		point.y = 0.0
		var lap: float = fposmod(start + STAND_BAY * 2.0 \
			* (float(index) + 0.5), total)
		if not Props.site_ok(spline, point, STAND_REACH):
			continue
		var model: String = GRANDSTAND_COVERED if index % 2 == 0 \
			else GRANDSTAND_OPEN
		var yaw: float = stand_yaw(spline, lap, outside)
		_add(upper, model, Props.fit(model, point, yaw,
			Vector3.ONE * Props.PROP_SCALE))
		colliders.append({"model": model, "point": point, "yaw": yaw})
	var stand_body := Props.body(holder, "Grandstands")
	for entry: Dictionary in colliders:
		var point: Vector3 = entry["point"]
		Props.model_body(stand_body, str(entry["model"]), point,
			float(entry["yaw"]), Vector3.ONE * Props.PROP_SCALE)
	var placed: int = 0
	for model: String in lower:
		var transforms: Array = lower[model] as Array
		placed += transforms.size()
		stats["draws"] = int(stats.get("draws", 0)) + Props.batch(holder,
			model, transforms, "Stand_" + model, true)
	for model: String in upper:
		var transforms: Array = upper[model] as Array
		placed += transforms.size()
		stats["draws"] = int(stats.get("draws", 0)) + Props.batch(holder,
			model, transforms, "UpperStand_" + model, true)
	stats["stands"] = int(stats.get("stands", 0)) + placed


## Round stands at the two ends of the main straight, sized to a 26 m kit
## footprint and set one bay further out so they do not cut the lower ring.
static func _round_stands(lower: Dictionary, colliders: Array,
		spline: RefCounted, plan: Dictionary, outside: float, start: float,
		total: float) -> void:
	var longest: Dictionary = plan["longest"]
	for offset: float in [float(longest["from"]), float(longest["to"])]:
		var lap: float = fposmod(offset, total)
		var point: Vector3 = Props.deck_point(spline, lap,
			(STAND_LATERAL + 4.0) * outside)
		point.y = 0.0
		if not Props.site_ok(spline, point, ROUND_REACH):
			continue
		var yaw: float = stand_yaw(spline, lap, outside)
		_add(lower, GRANDSTAND_ROUND, Props.fit(GRANDSTAND_ROUND, point, yaw,
			Vector3.ONE * Props.PROP_SCALE))
		colliders.append({"model": GRANDSTAND_ROUND, "point": point,
			"yaw": yaw})


## Yaw that turns a stand's front face towards the track, mirroring the
## convention tile_kit.grandstand was tuned with.
static func stand_yaw(spline: RefCounted, lap: float, side: float) -> float:
	var f: Dictionary = Props.frame(spline, lap)
	var forward: Vector3 = f["forward"]
	return atan2(-forward.x, -forward.z) \
		+ (PI * 0.5 if side > 0.0 else -PI * 0.5)


## Appends a transform to the batch for `model`, creating the batch on demand.
static func _add(batches: Dictionary, model: String, xform: Transform3D) -> void:
	if not batches.has(model):
		batches[model] = []
	(batches[model] as Array).append(xform)


## True when `value` is within `reach` of `anchor` on the circular lap.
static func _near(value: float, anchor: float, reach: float,
		total: float) -> bool:
	return _lap_gap(value, anchor, total) < reach


## Shortest distance between two lap positions, for a lap of `total` metres.
static func _lap_gap(a: float, b: float, total: float) -> float:
	if total <= 0.01:
		return absf(a - b)
	return absf(fposmod(a - b + total * 0.5, total) - total * 0.5)


# --------------------------------------------------------------------------
# catch fencing and tyres


## Catch fencing on the outside of the longest straight: the one place a kart
## carries enough speed to leave the road. Two short runs guard the outside of
## the fastest corners as well. The fence follows the lap behind the barrier.
static func _catch_fence(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	var outside: float = float(plan["outside"])
	var longest: Dictionary = plan["longest"]
	var runs: Array[Dictionary] = [
		{"from": float(longest["from"]), "to": float(longest["to"])},
	]
	for corner: Dictionary in plan["fast_corners"] as Array:
		var apex: float = float(corner["distance"])
		runs.append({"from": apex - 20.0, "to": apex + 28.0})
	var ring: Dictionary = Props.ring(spline, outside, FENCE_LATERAL)
	var transforms: Array = []
	var spots: Array[Dictionary] = []
	for run: Dictionary in runs:
		var sites: Array = Props.ring_run(ring, float(run["from"]),
			float(run["to"]), STAND_BAY)
		for site: Dictionary in sites:
			if transforms.size() >= CATCH_FENCE_MAX:
				break
			var point: Vector3 = (site["position"] as Vector3)
			if not Props.site_ok(spline, point, FENCE_REACH):
				continue
			var yaw: float = float(site["yaw"])
			transforms.append(Props.fit(FENCE_MODEL, point, yaw,
				Vector3.ONE * Props.PROP_SCALE))
			spots.append({"point": point, "yaw": yaw})
	if transforms.is_empty():
		return
	var body := Props.body(holder, "CatchFence")
	for spot: Dictionary in spots:
		Props.model_body(body, FENCE_MODEL, spot["point"], float(spot["yaw"]),
			Vector3.ONE * Props.PROP_SCALE)
	stats["draws"] = int(stats.get("draws", 0)) \
		+ Props.batch(holder, FENCE_MODEL, transforms, "CatchFenceBatch", false)
	stats["fences"] = int(stats.get("fences", 0)) + transforms.size()


## Tyre stacks at the two tightest corners, i.e. the infield hairpin whose two
## apexes are closest together. A stack is a primitive torus batch plus a WORLD
## cylinder, so a whole wall of tyres is one draw call.
static func _tyre_walls(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	var outside: float = float(plan["outside"])
	var ring: Dictionary = Props.ring(spline, outside, TYRE_LATERAL)
	var stacks: Array = []
	for corner: Dictionary in plan["tight_corners"] as Array:
		var apex: float = float(corner["distance"])
		var sites: Array = Props.ring_run(ring, apex - 14.0, apex + 18.0,
			TYRE_STACK_SPACING)
		for index in mini(sites.size(), TYRE_STACKS_PER_CORNER):
			var point: Vector3 = (sites[index] as Dictionary)["position"]
			point.y = 0.0
			if not Props.site_ok(spline, point, TYRE_REACH):
				continue
			stacks.append({"position": point})
	if stacks.is_empty():
		return
	stats["tyres"] = int(stats.get("tyres", 0)) \
		+ Props.tyres(holder, stacks, "TyreWalls")
	stats["draws"] = int(stats.get("draws", 0)) + 1


# --------------------------------------------------------------------------
# corner furniture


## A marshal post on the outside of every corner: a pylon base with a checkered
## flag on top, so the driver reads "people here" before the apex.
static func _marshal_posts(holder: Node3D, spline: RefCounted,
		plan: Dictionary, stats: Dictionary) -> void:
	var outside: float = float(plan["outside"])
	var ring: Dictionary = Props.ring(spline, outside, MARSHAL_LATERAL)
	var bases: Array = []
	var flags: Array = []
	var spots: Array[Dictionary] = []
	for corner: Dictionary in plan["corners"] as Array:
		var apex: float = float(corner["distance"])
		var sites: Array = Props.ring_run(ring, apex - 3.0, apex + 5.0, 8.0)
		if sites.is_empty():
			continue
		var point: Vector3 = (sites[0] as Dictionary)["position"]
		point.y = 0.0
		if not Props.site_ok(spline, point, MARSHAL_REACH):
			continue
		var yaw: float = float((sites[0] as Dictionary)["yaw"])
		bases.append(Props.fit(MARSHAL_BASE, point, yaw + PI * 0.5,
			Vector3.ONE * Props.PROP_SCALE))
		flags.append(Props.fit(MARSHAL_FLAG, point + Vector3.UP * 2.2, yaw,
			Vector3.ONE * Props.PROP_SCALE))
		spots.append({"point": point, "yaw": yaw})
	if bases.is_empty():
		return
	var body := Props.body(holder, "MarshalPosts")
	for spot: Dictionary in spots:
		Props.box(body, spot["point"], float(spot["yaw"]),
			Vector3(1.9, 6.4, 1.9))
	stats["draws"] = int(stats.get("draws", 0)) + Props.batch(holder,
		MARSHAL_BASE, bases, "MarshalBases", true)
	stats["draws"] = int(stats.get("draws", 0)) + Props.batch(holder,
		MARSHAL_FLAG, flags, "MarshalFlags", true)
	stats["marshals"] = int(stats.get("marshals", 0)) + bases.size()


## Camera positions: a crane on the outside of the lap every sixth of the way
## round, so the director can cover both straights and both hairpins.
static func _camera_cranes(holder: Node3D, spline: RefCounted,
		plan: Dictionary, stats: Dictionary) -> void:
	var outside: float = float(plan["outside"])
	var ring: Dictionary = Props.ring(spline, outside, CAMERA_LATERAL)
	var total: float = float(plan["total"])
	var transforms: Array = []
	var spots: Array[Dictionary] = []
	for index in CAMERA_CRANES:
		var lap: float = total * (float(index) + 0.5) / float(CAMERA_CRANES)
		var path: float = Props.ring_position(ring, lap)
		var point: Vector3 = Props.ring_point(ring, path)
		point.y = 0.0
		if not Props.site_ok(spline, point, CAMERA_REACH):
			continue
		var yaw: float = stand_yaw(spline, lap, outside)
		transforms.append(Props.fit(CAMERA_MODEL, point, yaw,
			Vector3.ONE * Props.PROP_SCALE))
		spots.append({"point": point, "yaw": yaw})
	var body := Props.body(holder, "CameraCranes")
	for spot: Dictionary in spots:
		Props.box(body, spot["point"], float(spot["yaw"]),
			Vector3(2.4, 6.5, 2.4))
	stats["cameras"] = int(stats.get("cameras", 0)) + transforms.size()
	stats["draws"] = int(stats.get("draws", 0)) \
		+ Props.batch(holder, CAMERA_MODEL, transforms, "CameraCranes", true)


## Floodlights on the outer ring, evenly spaced so every seat sees a lit sky.
static func _floodlights(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	var outside: float = float(plan["outside"])
	var ring: Dictionary = Props.ring(spline, outside, LIGHT_LATERAL)
	var transforms: Array = []
	var spots: Array[Vector3] = []
	for index in FLOODLIGHTS:
		var lap: float = float(plan["total"]) * (float(index) + 0.5) \
			/ float(FLOODLIGHTS)
		var path: float = Props.ring_position(ring, lap)
		var point: Vector3 = Props.ring_point(ring, path)
		point.y = 0.0
		if not Props.site_ok(spline, point, LIGHT_REACH):
			continue
		transforms.append(Props.fit(LIGHT_MODEL, point,
			stand_yaw(spline, lap, outside), Vector3.ONE * Props.PROP_SCALE))
		spots.append(point)
	if transforms.is_empty():
		return
	var body := Props.body(holder, "Floodlights")
	for point: Vector3 in spots:
		Props.model_body(body, LIGHT_MODEL, point, 0.0,
			Vector3.ONE * Props.PROP_SCALE)
	stats["lights"] = int(stats.get("lights", 0)) + transforms.size()
	stats["draws"] = int(stats.get("draws", 0)) \
		+ Props.batch(holder, LIGHT_MODEL, transforms, "Floodlights", true)


## Sponsor boards and pylons on the outside of the straights, batched per model
## and facing the track so the sponsor art reads from the chase camera.
static func _sponsor_boards(holder: Node3D, spline: RefCounted,
		plan: Dictionary, stats: Dictionary) -> void:
	var outside: float = float(plan["outside"])
	var ring: Dictionary = Props.ring(spline, outside, SIGN_LATERAL)
	var batches: Dictionary = {}
	var body := Props.body(holder, "SponsorBoards")
	var total: float = float(plan["total"])
	for index in BOARD_COUNT:
		var lap: float = total * (float(index) + 0.25) / float(BOARD_COUNT)
		_board(batches, body, spline, ring, lap, outside, "billboardLow")
	for corner: Dictionary in plan["tight_corners"] as Array:
		var apex: float = float(corner["distance"])
		for offset: float in [-24.0, 26.0]:
			_board(batches, body, spline, ring, apex + offset, outside, "pylon")
	stats["signage"] = int(stats.get("signage", 0)) + _batch_count(batches)
	for kind: String in batches:
		var model: String = _sign_model(kind)
		stats["draws"] = int(stats.get("draws", 0)) \
			+ Props.batch(holder, model, batches[kind] as Array,
				"Sign_" + model, true)


## One sponsor board or pylon at a lap position on the outside sign ring.
static func _board(batches: Dictionary, body_node: StaticBody3D,
		spline: RefCounted, ring_path: Dictionary, lap: float, outside: float,
		kind: String) -> void:
	var path: float = Props.ring_position(ring_path, lap)
	var point: Vector3 = Props.ring_point(ring_path, path)
	point.y = 0.0
	var model: String = _sign_model(kind)
	var scale: float = TileCatalog.sign_scale(kind)
	if not Props.site_ok(spline, point,
			Props.half_extent(model, Vector3.ONE * scale)):
		return
	var yaw: float = stand_yaw(spline, lap, outside)
	if not batches.has(kind):
		batches[kind] = []
	(batches[kind] as Array).append(Props.fit(model, point, yaw,
		Vector3.ONE * scale))
	Props.model_body(body_node, model, point, yaw, Vector3.ONE * scale)


static func _sign_model(kind: String) -> String:
	match kind:
		"pylon":
			return TileCatalog.PYLON
		"bannerTower":
			return TileCatalog.BANNER_TOWER
		_:
			return TileCatalog.BILLBOARD_LOW


static func _batch_count(batches: Dictionary) -> int:
	var count: int = 0
	for kind: String in batches:
		count += (batches[kind] as Array).size()
	return count


## A flag line around the bowl, one pole every few metres, so the ring reads as
## a festival from the chase camera.
static func _flags(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	var outside: float = float(plan["outside"])
	var ring: Dictionary = Props.ring(spline, outside, FLAG_LATERAL)
	var kinds: Array[String] = ["flagRed", "flagGreen", "flagCheckers"]
	var batches: Dictionary = {}
	var body := Props.body(holder, "Flags")
	var total: float = float(plan["total"])
	var scale: float = TileKit.FLAG_SCALE
	for index in FLAG_COUNT:
		var lap: float = total * float(index) / float(FLAG_COUNT)
		var path: float = Props.ring_position(ring, lap)
		var point: Vector3 = Props.ring_point(ring, path)
		point.y = 0.0
		if not Props.site_ok(spline, point, FLAG_REACH):
			continue
		var kind: String = kinds[index % kinds.size()]
		var yaw: float = stand_yaw(spline, lap, outside)
		if not batches.has(kind):
			batches[kind] = []
		(batches[kind] as Array).append(Props.fit(kind, point, yaw,
			Vector3.ONE * scale))
		Props.model_body(body, kind, point, yaw, Vector3.ONE * scale)
	stats["flags"] = int(stats.get("flags", 0)) + _batch_count(batches)
	for kind: String in batches:
		stats["draws"] = int(stats.get("draws", 0)) \
			+ Props.batch(holder, kind, batches[kind] as Array,
				"Flag_" + kind, true)


# --------------------------------------------------------------------------
# terrain: cliff walls at the raised sweep and the valley, a bridge over it


## A wall of cartoon cliffs on the outside of the raised sweep and of the low
## valley. The cliff blocks stand on the meadow, so they hide the side of the
## raised deck and turn the valley into a cutting instead of a flat field.
static func _cliff_walls(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	var outside: float = float(plan["outside"])
	var ring: Dictionary = Props.ring(spline, outside, CLIFF_LATERAL)
	var spans: Array[Dictionary] = []
	for key: String in ["raised", "valley"]:
		var span: Dictionary = plan[key]
		if bool(span.get("ok", false)):
			spans.append(span)
	if spans.is_empty():
		return
	var transforms: Array = []
	var spots: Array[Dictionary] = []
	var scale: Vector3 = Vector3.ONE * Props.NATURE_SCALE * 0.7
	var body := Props.body(holder, "CliffWalls")
	for span: Dictionary in spans:
		var sites: Array = Props.ring_run(ring, float(span["from"]),
			float(span["to"]), 15.0)
		for site: Dictionary in sites:
			var point: Vector3 = (site["position"] as Vector3)
			point.y = 0.0
			if not Props.site_ok(spline, point, CLIFF_REACH):
				continue
			var yaw: float = float(site["yaw"])
			transforms.append(Props.fit(CLIFF_MODEL, point, yaw, scale, true))
			spots.append({"point": point, "yaw": yaw})
	if transforms.is_empty():
		return
	for spot: Dictionary in spots:
		Props.model_body(body, CLIFF_MODEL, spot["point"], float(spot["yaw"]),
			scale, 0.4, true)
	stats["cliffs"] = int(stats.get("cliffs", 0)) + transforms.size()
	stats["draws"] = int(stats.get("draws", 0)) \
		+ Props.batch(holder, CLIFF_MODEL, transforms, "ValleyCliffs", true, true)


## A stone footbridge over the valley: two side modules carry the deck and a
## centre module spans the road. Piers stand outside the barrier and the deck is
## high enough for a kart to drive under, which is what makes the dip read as a
## tunnel mouth.
static func _footbridge(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	var valley: Dictionary = plan["valley"]
	if not bool(valley.get("ok", false)):
		return
	var middle: float = (float(valley["from"]) + float(valley["to"])) * 0.5
	var f: Dictionary = Props.frame(spline, middle)
	var centre: Vector3 = f["position"]
	var right: Vector3 = f["right"]
	var yaw: float = atan2(-right.z, right.x)
	var span: float = Props.size(BRIDGE_CENTER,
		Vector3.ONE * Props.NATURE_SCALE, true).x
	var modules: Array[Dictionary] = [
		{"model": BRIDGE_SIDE, "offset": -1.0},
		{"model": BRIDGE_CENTER, "offset": 0.0},
		{"model": BRIDGE_SIDE, "offset": 1.0},
	]
	var body := Props.body(holder, "Footbridge")
	var batches: Dictionary = {}
	for module: Dictionary in modules:
		var point: Vector3 = centre + right * (float(module["offset"]) * span)
		point.y = BRIDGE_DECK
		var model: String = str(module["model"])
		if not batches.has(model):
			batches[model] = []
		(batches[model] as Array).append(Props.fit(model, point, yaw,
			Vector3.ONE * Props.NATURE_SCALE, true))
	for model: String in batches:
		stats["draws"] = int(stats.get("draws", 0)) \
			+ Props.batch(holder, model, batches[model] as Array,
				"Bridge_" + model, true, true)
	# The two piers are solid on WORLD; the deck only has to clear a kart.
	var deck_size: Vector3 = Props.size(BRIDGE_CENTER,
		Vector3.ONE * Props.NATURE_SCALE, true)
	Props.box(body, centre + Vector3.UP * BRIDGE_DECK, yaw,
		Vector3(deck_size.x * 3.0, 0.5, deck_size.z))
	for side: float in [-1.0, 1.0]:
		var pier: Vector3 = centre + right * (side * span * 1.55)
		pier.y = 0.0
		Props.box(body, pier, yaw,
			Vector3(deck_size.x * 0.7, BRIDGE_DECK, deck_size.z * 0.7))
	stats["bridge"] = int(stats.get("bridge", 0)) + modules.size()


# --------------------------------------------------------------------------
# the tree band, outside everything


## Trees, bushes and rocks on the meadow beyond the stand ring. Entries are
## filtered against the centreline before they are handed to tile_kit.trees,
## which rejects anything inside the road and batches the rest into one
## MultiMesh per nature model.
static func _tree_band(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary) -> void:
	var bounds: Rect2 = plan["bounds"] as Rect2
	var entries: Array = []
	var step: float = 13.0
	var row: int = 0
	var y: float = bounds.position.y - step * 2.0
	while y < bounds.end.y + step * 2.0 and entries.size() < TREE_BAND + BUSH_BAND:
		var column: int = 0
		var x: float = bounds.position.x - step * 2.0
		while x < bounds.end.x + step * 2.0 \
				and entries.size() < TREE_BAND + BUSH_BAND:
			var hash: int = _hash(row, column)
			var jitter := Vector2(float(hash % 9) - 4.0,
				float((hash >> 3) % 9) - 4.0)
			var point := Vector3(x + jitter.x, 0.0, y + jitter.y)
			var in_plan: bool = bounds.has_point(Vector2(x, y))
			var clear: bool = TileKit.spline_distance(spline, point) \
				>= TREE_RING_MIN
			if clear and not in_plan:
				var bush: bool = entries.size() >= TREE_BAND
				entries.append({"position": point,
					"kind": nature_model(bush, hash),
					"scale": 0.8 + 0.4 * float((hash >> 5) % 100) / 100.0})
			column += 1
			x += step
		row += 1
		y += step
	if entries.is_empty():
		return
	stats["trees"] = int(stats.get("trees", 0)) \
		+ TileKit.trees(holder, entries, spline)
	stats["draws"] = int(stats.get("draws", 0)) \
		+ _band_draws(entries)


## Nature model for a band entry: trees first, then bushes and rocks for the
## undergrowth so the edge of the map does not end in a hard line.
static func nature_model(bush: bool, hash: int) -> String:
	if bush:
		if hash % 5 == 0:
			return ROCK_KINDS[absi(hash) % ROCK_KINDS.size()]
		return BUSH_KINDS[absi(hash) % BUSH_KINDS.size()]
	return TREE_KINDS[absi(hash) % TREE_KINDS.size()]


## Draw calls the foliage batch will add: one per distinct nature model used.
static func _band_draws(entries: Array) -> int:
	var models: Dictionary = {}
	for entry: Dictionary in entries:
		models[str(entry["kind"])] = true
	var draws: int = 0
	for model: String in models:
		draws += Props.part_count(model, true)
	return draws


## Stable per-cell seed: the band must look identical on every build, so the
## variation cannot come from a random generator.
static func _hash(a: int, b: int) -> int:
	return absi((a * 73856093) ^ (b * 19349663))
