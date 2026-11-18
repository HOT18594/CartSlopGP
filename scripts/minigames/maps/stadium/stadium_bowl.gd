extends RefCounted
## Outer bowl of the STADIUM CIRCUIT: the part the chase camera sees first.
##
## Everything is placed on the *outside* of the lap, measured from the true road
## edge rather than from hard-coded world points, so a registry grid edit moves
## the whole bowl with the track. The bowl is built as concentric groups:
##
##   tier 1  a ring of stands on a one-grid-cell pitch: the seating wall of the
##           stadium, with the covered main stand over the start/finish and
##           awning stands on the far side. A bay whose 16 m footprint would
##           cut the one beside it on a corner is left out, not drawn through it
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
## front face lands 12.8 m out: behind the barrier face at 8.02 m and behind the
## barrier body (which is 2 m deep), leaving a 2.5 m furniture lane in front of
## the seating. The upper tier stays inside 46 m so the designed woodland, whose
## nearest trunk is 48.2 m, can never grow through the second roof.
const STAND_LATERAL: float = 20.8
## Second tier: a ring of covered stands further out, on both long sides. The
## 0.65 m shadow gap between the back of the lower ring (28.8 m) and the front
## of the upper one (29.45 m) keeps the two tiers reading separately.
const TIER_TWO_LATERAL: float = 37.6
const STAND_MAIN_BAYS: float = 6.0

## Lateral distances of the detail props, all outside the barrier body and
## inside the furniture lane in front of the lower stand ring. Every prop here
## is <= 2.3 m deep, which is what the lane holds.
const FENCE_LATERAL: float = 11.0
const TYRE_LATERAL: float = 11.45
const MARSHAL_LATERAL: float = 11.7
## A crane's measured footprint is 4.2 m deep, so it is yawed to run its long
## axis along the track and only 1.7 m of it faces the road.
const CAMERA_LATERAL: float = 11.5
## Floodlights stand in the same lane, in front of the seating.
const LIGHT_LATERAL: float = 11.45
const SIGN_LATERAL: float = 11.45
const FLAG_LATERAL: float = 11.6
## Cliff walls stand behind the upper tier, so the rock face reads above the
## second roof instead of being buried in the seating.
const CLIFF_LATERAL: float = 49.0
const BRIDGE_DECK: float = 3.7
## Sponsor boards are drawn at four tenths of the catalogue sign scale so a
## 7.6 m deep billboard becomes 1.8 m deep and fits the furniture lane.
const BOARD_SCALE: float = 0.4

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
## A cliff block reaches 3.6 m; the wall stands behind the upper tier.
const CLIFF_REACH: float = 3.6
const CATCH_FENCE_MAX: int = 14
const FLOODLIGHTS: int = 12
const CAMERA_CRANES: int = 6
const FLAG_COUNT: int = 32
const BOARD_COUNT: int = 10
const TREE_BAND: int = 140
const BUSH_BAND: int = 44
## Trees stand beyond the second stand tier and the cliff wall behind it: this
## is the plan distance that guarantees both.
const TREE_RING_MIN: float = 52.0

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
	# Order is priority: the deck-defining terrace and the big, functional
	# furniture take their sites first, then the small dressing fills the lane
	# that is left. Every pass registers its footprint, so a later prop is
	# skipped rather than drawn through an earlier one.
	var placed: Array = []
	_ground_and_terraces(holder, spline, plan, stats)
	_grandstands(holder, spline, plan, stats, placed)
	_catch_fence(holder, spline, plan, stats, placed)
	_floodlights(holder, spline, plan, stats, placed)
	_tyre_walls(holder, spline, plan, stats, placed)
	_camera_cranes(holder, spline, plan, stats, placed)
	_marshal_posts(holder, spline, plan, stats, placed)
	_sponsor_boards(holder, spline, plan, stats, placed)
	_flags(holder, spline, plan, stats, placed)
	_cliff_walls(holder, spline, plan, stats, placed)
	_footbridge(holder, spline, plan, stats)
	_tree_band(holder, spline, plan, stats)


# --------------------------------------------------------------------------
# the seating bowl


## Two concentric stand rings, batched into one MultiMesh per model, so the
## whole bowl costs four draw calls however many bays it holds. Every bay is
## tested in plan against the bays already placed: a fixed 16 m spacing turns a
## 16 m square into an interpenetrating pile on a corner, so a bay that would
## clip the terrace is left out instead of being drawn through its neighbour.
static func _grandstands(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary, placed: Array) -> void:
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
		var lap: float = fposmod(start + STAND_BAY * (float(index) + 0.5), total)
		if not Props.site_ok(spline, point, STAND_REACH):
			continue
		if not Props.side_ok(spline, point, outside):
			continue
		var model: String = GRANDSTAND_OPEN
		if _lap_gap(lap, start, total) < STAND_BAY * STAND_MAIN_BAYS:
			model = GRANDSTAND_COVERED
		elif index % 4 == 2:
			model = GRANDSTAND_AWNING
		var yaw: float = ring_stand_yaw(site, outside)
		var footprint: Vector3 = Props.size(model,
			Vector3.ONE * Props.PROP_SCALE)
		if not Props.site_free(placed, point, yaw, footprint):
			stats["stands_shed"] = int(stats.get("stands_shed", 0)) + 1
			continue
		Props.remember(placed, point, yaw, footprint)
		_add(lower, model, Props.fit(model, point, yaw,
			Vector3.ONE * Props.PROP_SCALE))
		colliders.append({"model": model, "point": point, "yaw": yaw})
	var upper_sites: Array = Props.ring_run(upper_ring, 0.0, total,
		STAND_BAY * 2.0)
	for index in upper_sites.size():
		var site: Dictionary = upper_sites[index]
		var point: Vector3 = (site["position"] as Vector3)
		var lap: float = fposmod(start + STAND_BAY * 2.0 \
			* (float(index) + 0.5), total)
		if not Props.site_ok(spline, point, STAND_REACH):
			continue
		if not Props.side_ok(spline, point, outside):
			continue
		var model: String = GRANDSTAND_COVERED if index % 2 == 0 \
			else GRANDSTAND_OPEN
		var yaw: float = ring_stand_yaw(site, outside)
		var footprint: Vector3 = Props.size(model,
			Vector3.ONE * Props.PROP_SCALE)
		if not Props.site_free(placed, point, yaw, footprint):
			stats["stands_shed"] = int(stats.get("stands_shed", 0)) + 1
			continue
		Props.remember(placed, point, yaw, footprint)
		_add(upper, model, Props.fit(model, point, yaw,
			Vector3.ONE * Props.PROP_SCALE))
		colliders.append({"model": model, "point": point, "yaw": yaw})
	var stand_body := Props.body(holder, "Grandstands")
	for entry: Dictionary in colliders:
		var point: Vector3 = entry["point"]
		Props.model_body(stand_body, str(entry["model"]), point,
			float(entry["yaw"]), Vector3.ONE * Props.PROP_SCALE)
	var placed_count: int = 0
	for model: String in lower:
		var transforms: Array = lower[model] as Array
		placed_count += transforms.size()
		stats["draws"] = int(stats.get("draws", 0)) + Props.batch(holder,
			model, transforms, "Stand_" + model, true)
	for model: String in upper:
		var transforms: Array = upper[model] as Array
		placed_count += transforms.size()
		stats["draws"] = int(stats.get("draws", 0)) + Props.batch(holder,
			model, transforms, "UpperStand_" + model, true)
	stats["stands"] = int(stats.get("stands", 0)) + placed_count


## Ring site at a path arc length: the point and the path's own along-yaw.
static func ring_site(ring_path: Dictionary, path: float) -> Dictionary:
	var point: Vector3 = Props.ring_point(ring_path, path)
	var ahead: Vector3 = Props.ring_point(ring_path, path + 0.8)
	var delta: Vector3 = ahead - point
	return {"position": point,
		"yaw": atan2(-delta.z, delta.x) if delta.length_squared() > 0.0001 \
			else 0.0}


## Facing yaw for a prop placed from a clearance ring: its position is the ring
## point, so its facing has to come from the ring tangent as well. A yaw taken
## from the lap distance is sampled metres away on a corner, which turns a
## 6 m floodlight across the service lane and a billboard through a stand.
static func ring_face_yaw(ring_path: Dictionary, path: float,
		side: float) -> float:
	return ring_stand_yaw(ring_site(ring_path, path), side)


## Yaw that turns a stand's front face towards the track, using the clearance
## ring's own tangent instead of the centreline forward: on a corner the ring
## position no longer matches the lap distance the forward was sampled at, and
## a stand yawed from the wrong lap cuts through its neighbour.
static func ring_stand_yaw(site: Dictionary, side: float) -> float:
	return float(site["yaw"]) - PI * 0.5 \
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
		stats: Dictionary, placed: Array) -> void:
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
	var footprint: Vector3 = Props.size(FENCE_MODEL,
		Vector3.ONE * Props.PROP_SCALE)
	for run: Dictionary in runs:
		var sites: Array = Props.ring_run(ring, float(run["from"]),
			float(run["to"]), STAND_BAY)
		for site: Dictionary in sites:
			if transforms.size() >= CATCH_FENCE_MAX:
				break
			var point: Vector3 = (site["position"] as Vector3)
			if not Props.site_ok(spline, point, FENCE_REACH):
				continue
			if not Props.side_ok(spline, point, outside):
				continue
			var yaw: float = float(site["yaw"])
			# Fence panels tile end to end, so they may touch: only a real
			# interpenetration is refused.
			if not Props.site_free(placed, point, yaw, footprint, 0.0):
				continue
			Props.remember(placed, point, yaw, footprint)
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
		stats: Dictionary, placed: Array) -> void:
	var outside: float = float(plan["outside"])
	var ring: Dictionary = Props.ring(spline, outside, TYRE_LATERAL)
	var stacks: Array = []
	var tyre_diameter: float = (Props.TYRE_RADIUS + Props.TYRE_TUBE) * 2.0
	var footprint := Vector3(tyre_diameter, Props.TYRE_HEIGHT, tyre_diameter)
	for corner: Dictionary in plan["tight_corners"] as Array:
		var apex: float = float(corner["distance"])
		var sites: Array = Props.ring_run(ring, apex - 14.0, apex + 18.0,
			TYRE_STACK_SPACING)
		for index in mini(sites.size(), TYRE_STACKS_PER_CORNER):
			var point: Vector3 = (sites[index] as Dictionary)["position"]
			if not Props.site_ok(spline, point, TYRE_REACH):
				continue
			if not Props.side_ok(spline, point, outside):
				continue
			if not Props.site_free(placed, point, 0.0, footprint):
				continue
			Props.remember(placed, point, 0.0, footprint)
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
		plan: Dictionary, stats: Dictionary, placed: Array) -> void:
	var outside: float = float(plan["outside"])
	var ring: Dictionary = Props.ring(spline, outside, MARSHAL_LATERAL)
	var bases: Array = []
	var flags: Array = []
	var spots: Array[Dictionary] = []
	var footprint := Vector3(1.9, 6.4, 1.9)
	for corner: Dictionary in plan["corners"] as Array:
		var apex: float = float(corner["distance"])
		var sites: Array = Props.ring_run(ring, apex - 3.0, apex + 5.0, 8.0)
		if sites.is_empty():
			continue
		var point: Vector3 = (sites[0] as Dictionary)["position"]
		if not Props.site_ok(spline, point, MARSHAL_REACH):
			continue
		if not Props.side_ok(spline, point, outside):
			continue
		var yaw: float = float((sites[0] as Dictionary)["yaw"])
		if not Props.site_free(placed, point, yaw, footprint):
			continue
		Props.remember(placed, point, yaw, footprint)
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
		plan: Dictionary, stats: Dictionary, placed: Array) -> void:
	var outside: float = float(plan["outside"])
	var ring: Dictionary = Props.ring(spline, outside, CAMERA_LATERAL)
	var total: float = float(plan["total"])
	var transforms: Array = []
	var spots: Array[Dictionary] = []
	var footprint := Vector3(2.4, 6.5, 2.4)
	for index in CAMERA_CRANES:
		var lap: float = total * (float(index) + 0.5) / float(CAMERA_CRANES)
		var path: float = Props.ring_position(ring, lap)
		var point: Vector3 = Props.ring_point(ring, path)
		if not Props.site_ok(spline, point, CAMERA_REACH):
			continue
		if not Props.side_ok(spline, point, outside):
			continue
		var yaw: float = ring_face_yaw(ring, path, outside)
		# The crane is 4.2 m deep, so it is turned a quarter to run its arm
		# along the lane instead of through the seating behind it.
		var place_yaw: float = yaw + PI * 0.5
		if not Props.site_free(placed, point, place_yaw, footprint):
			continue
		Props.remember(placed, point, place_yaw, footprint)
		transforms.append(Props.fit(CAMERA_MODEL, point, place_yaw,
			Vector3.ONE * Props.PROP_SCALE))
		spots.append({"point": point, "yaw": place_yaw})
	var body := Props.body(holder, "CameraCranes")
	for spot: Dictionary in spots:
		Props.box(body, spot["point"], float(spot["yaw"]),
			Vector3(2.4, 6.5, 2.4))
	stats["cameras"] = int(stats.get("cameras", 0)) + transforms.size()
	stats["draws"] = int(stats.get("draws", 0)) \
		+ Props.batch(holder, CAMERA_MODEL, transforms, "CameraCranes", true)


## Floodlights on the outer ring, evenly spaced so every seat sees a lit sky.
static func _floodlights(holder: Node3D, spline: RefCounted, plan: Dictionary,
		stats: Dictionary, placed: Array) -> void:
	var outside: float = float(plan["outside"])
	var ring: Dictionary = Props.ring(spline, outside, LIGHT_LATERAL)
	var transforms: Array = []
	var spots: Array[Dictionary] = []
	var footprint: Vector3 = Props.size(LIGHT_MODEL,
		Vector3.ONE * Props.PROP_SCALE)
	for index in FLOODLIGHTS:
		var lap: float = float(plan["total"]) * (float(index) + 0.5) \
			/ float(FLOODLIGHTS)
		var path: float = Props.ring_position(ring, lap)
		var point: Vector3 = Props.ring_point(ring, path)
		if not Props.site_ok(spline, point, LIGHT_REACH):
			continue
		if not Props.side_ok(spline, point, outside):
			continue
		var yaw: float = ring_face_yaw(ring, path, outside)
		if not Props.site_free(placed, point, yaw, footprint):
			continue
		Props.remember(placed, point, yaw, footprint)
		transforms.append(Props.fit(LIGHT_MODEL, point, yaw,
			Vector3.ONE * Props.PROP_SCALE))
		spots.append({"point": point, "yaw": yaw})
	if transforms.is_empty():
		return
	var body := Props.body(holder, "Floodlights")
	for spot: Dictionary in spots:
		# The collider follows the model's yaw: an axis-aligned box on a turned
		# pylon is 3 m too deep across the service lane.
		Props.model_body(body, LIGHT_MODEL, spot["point"],
			float(spot["yaw"]), Vector3.ONE * Props.PROP_SCALE)
	stats["lights"] = int(stats.get("lights", 0)) + transforms.size()
	stats["draws"] = int(stats.get("draws", 0)) \
		+ Props.batch(holder, LIGHT_MODEL, transforms, "Floodlights", true)


## Sponsor boards and pylons on the outside of the straights, batched per model
## and facing the track so the sponsor art reads from the chase camera.
static func _sponsor_boards(holder: Node3D, spline: RefCounted,
		plan: Dictionary, stats: Dictionary, placed: Array) -> void:
	var outside: float = float(plan["outside"])
	var ring: Dictionary = Props.ring(spline, outside, SIGN_LATERAL)
	var batches: Dictionary = {}
	var body := Props.body(holder, "SponsorBoards")
	var total: float = float(plan["total"])
	for index in BOARD_COUNT:
		var lap: float = total * (float(index) + 0.25) / float(BOARD_COUNT)
		_board(batches, body, spline, ring, lap, outside, "billboardLow", placed)
	for corner: Dictionary in plan["tight_corners"] as Array:
		var apex: float = float(corner["distance"])
		for offset: float in [-24.0, 26.0]:
			_board(batches, body, spline, ring, apex + offset, outside, "pylon",
				placed)
	stats["signage"] = int(stats.get("signage", 0)) + _batch_count(batches)
	for kind: String in batches:
		var model: String = _sign_model(kind)
		stats["draws"] = int(stats.get("draws", 0)) \
			+ Props.batch(holder, model, batches[kind] as Array,
				"Sign_" + model, true)


## One sponsor board or pylon at a lap position on the outside sign ring.
static func _board(batches: Dictionary, body_node: StaticBody3D,
		spline: RefCounted, ring_path: Dictionary, lap: float, outside: float,
		kind: String, placed: Array) -> void:
	var path: float = Props.ring_position(ring_path, lap)
	var point: Vector3 = Props.ring_point(ring_path, path)
	var model: String = _sign_model(kind)
	var scale: float = TileCatalog.sign_scale(kind) \
		* (BOARD_SCALE if model == TileCatalog.BILLBOARD_LOW else 1.0)
	var footprint: Vector3 = Props.size(model, Vector3.ONE * scale)
	if not Props.site_ok(spline, point, Props.half_extent(model,
			Vector3.ONE * scale)):
		return
	if not Props.side_ok(spline, point, outside):
		return
	var yaw: float = ring_face_yaw(ring_path, path, outside)
	if not Props.site_free(placed, point, yaw, footprint):
		return
	Props.remember(placed, point, yaw, footprint)
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
		stats: Dictionary, placed: Array) -> void:
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
		if not Props.site_ok(spline, point, FLAG_REACH):
			continue
		if not Props.side_ok(spline, point, outside):
			continue
		var kind: String = kinds[index % kinds.size()]
		var yaw: float = ring_face_yaw(ring, path, outside)
		var footprint: Vector3 = Props.size(kind, Vector3.ONE * scale)
		if not Props.site_free(placed, point, yaw, footprint):
			continue
		Props.remember(placed, point, yaw, footprint)
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
		stats: Dictionary, placed: Array) -> void:
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
			if not Props.site_ok(spline, point, CLIFF_REACH):
				continue
			if not Props.side_ok(spline, point, outside):
				continue
			var yaw: float = float(site["yaw"])
			var footprint: Vector3 = Props.size(CLIFF_MODEL, scale, true)
			if not Props.site_free(placed, point, yaw, footprint):
				continue
			Props.remember(placed, point, yaw, footprint)
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
## centre module spans the road. Piers stand outside the barrier body and the
## deck is high enough for a kart to drive under, which is what makes the dip
## read as a tunnel mouth. The modules are spaced from their measured widths
## plus a seam gap, so no two stone pieces share a face plane.
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
	var centre_size: Vector3 = Props.size(BRIDGE_CENTER,
		Vector3.ONE * Props.NATURE_SCALE, true)
	var side_size: Vector3 = Props.size(BRIDGE_SIDE,
		Vector3.ONE * Props.NATURE_SCALE, true)
	var seam: float = 0.05
	var module_offset: float = (centre_size.x + side_size.x) * 0.5 + seam
	var deck_top: float = centre.y + BRIDGE_DECK + Props.LAYER_APRON
	var modules: Array[Dictionary] = [
		{"model": BRIDGE_SIDE, "offset": -module_offset},
		{"model": BRIDGE_CENTER, "offset": 0.0},
		{"model": BRIDGE_SIDE, "offset": module_offset},
	]
	var body := Props.body(holder, "Footbridge")
	var batches: Dictionary = {}
	for module: Dictionary in modules:
		var point: Vector3 = centre + right * float(module["offset"])
		point.y = deck_top
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
	var deck_width: float = side_size.x + module_offset * 2.0
	Props.box(body, centre + Vector3.UP * BRIDGE_DECK, yaw,
		Vector3(deck_width, 0.5, centre_size.z))
	var pier_offset: float = maxf(deck_width * 0.5 + 0.45, 9.2)
	for side: float in [-1.0, 1.0]:
		var pier: Vector3 = centre + right * (side * pier_offset)
		pier.y = centre.y
		Props.box(body, pier, yaw,
			Vector3(1.4, BRIDGE_DECK - Props.LAYER_APRON,
				centre_size.z * 0.7))
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


# --------------------------------------------------------------------------
# cartoon turf ground + terraced stadium berms


## One merged vertex-coloured cartoon mesh covering the whole stadium ground and
## raising clean earthen/concrete stadium terraces beneath every elevated track
## sector so grandstands, floodlights, cranes and flags never float in mid-air.
static func _ground_and_terraces(holder: Node3D, spline: RefCounted,
		plan: Dictionary, stats: Dictionary) -> void:
	var bounds: Rect2 = plan["bounds"] as Rect2
	var cx: float = bounds.position.x + bounds.size.x * 0.5
	var cz: float = bounds.position.y + bounds.size.y * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var turf_outer := Color("6fae4a")
	var turf_inner := Color("79ba53")
	var berm_top := Color("66a244")
	var berm_wall := Color("8b8e92")

	# Wide outer cartoon turf sheet covering 1500 x 1500 m at Z_GROUND (-0.02 m)
	var half_ext: float = 750.0
	var ground_y: float = TileKit.Z_GROUND
	_push_quad(verts, normals, colors,
		Vector3(cx - half_ext, ground_y, cz - half_ext),
		Vector3(cx + half_ext, ground_y, cz - half_ext),
		Vector3(cx + half_ext, ground_y, cz + half_ext),
		Vector3(cx - half_ext, ground_y, cz + half_ext),
		turf_outer)

	# Mowed infield stadium turf pad slightly above outer grass (-0.014 m)
	var pad_min := Vector2(bounds.position.x - 24.0, bounds.position.y - 24.0)
	var pad_max := Vector2(bounds.end.x + 24.0, bounds.end.y + 24.0)
	_push_quad(verts, normals, colors,
		Vector3(pad_min.x, ground_y + 0.006, pad_min.y),
		Vector3(pad_max.x, ground_y + 0.006, pad_min.y),
		Vector3(pad_max.x, ground_y + 0.006, pad_max.y),
		Vector3(pad_min.x, ground_y + 0.006, pad_max.y),
		turf_inner)

	# Continuous stadium terrace embankment under elevated bowl props & stands,
	# plus viaduct piers under the 9.0 m stadium sky-bridge.
	var outside: float = float(plan["outside"])
	var inner_ring: Dictionary = Props.ring(spline, outside, 8.6)
	var outer_ring: Dictionary = Props.ring(spline, outside, 46.5)
	if bool(inner_ring.get("ok", false)) and bool(outer_ring.get("ok", false)):
		var total: float = maxf(float(plan["total"]), 1.0)
		var steps: int = 144
		for i in steps:
			var lap0: float = total * float(i) / float(steps)
			var lap1: float = total * float(i + 1) / float(steps)
			var h0: float = float(spline.height_at(lap0))
			var h1: float = float(spline.height_at(lap1))
			if maxf(h0, h1) < 0.08:
				continue
			var a_in: Vector3 = Props.ring_point(inner_ring,
				Props.ring_position(inner_ring, lap0))
			var b_in: Vector3 = Props.ring_point(inner_ring,
				Props.ring_position(inner_ring, lap1))
			var a_out: Vector3 = Props.ring_point(outer_ring,
				Props.ring_position(outer_ring, lap0))
			var b_out: Vector3 = Props.ring_point(outer_ring,
				Props.ring_position(outer_ring, lap1))
			a_in.y = h0 - 0.015
			b_in.y = h1 - 0.015
			a_out.y = h0 - 0.015
			b_out.y = h1 - 0.015
			_push_quad(verts, normals, colors, a_in, b_in, b_out, a_out, berm_top)
			_push_quad(verts, normals, colors,
				Vector3(a_in.x, ground_y, a_in.z),
				Vector3(b_in.x, ground_y, b_in.z),
				b_in, a_in, berm_wall)
			_push_quad(verts, normals, colors,
				a_out, b_out,
				Vector3(b_out.x, ground_y, b_out.z),
				Vector3(a_out.x, ground_y, a_out.z), berm_wall.darkened(0.08))
			# Infield sky-bridge concrete fascia & support columns on high spans
			if i % 3 == 0 and minf(h0, h1) >= 2.8:
				var f_mid: Dictionary = Props.frame(spline, (lap0 + lap1) * 0.5)
				var p_mid: Vector3 = f_mid["position"]
				var r_mid: Vector3 = f_mid["right"]
				var fwd_mid: Vector3 = f_mid["forward"]
				for p_side: float in [-3.8, 3.8]:
					var col_base: Vector3 = p_mid + r_mid * p_side
					var hw: Vector3 = r_mid * 0.65
					var hd: Vector3 = fwd_mid * 0.65
					var y_top: float = p_mid.y - 0.08
					var c0 := Vector3(col_base.x, ground_y, col_base.z) - hw - hd
					var c1 := Vector3(col_base.x, ground_y, col_base.z) + hw - hd
					var c2 := Vector3(col_base.x, ground_y, col_base.z) + hw + hd
					var c3 := Vector3(col_base.x, ground_y, col_base.z) - hw + hd
					var t0 := Vector3(c0.x, y_top, c0.z)
					var t1 := Vector3(c1.x, y_top, c1.z)
					var t2 := Vector3(c2.x, y_top, c2.z)
					var t3 := Vector3(c3.x, y_top, c3.z)
					_push_quad(verts, normals, colors, c0, c1, t1, t0, berm_wall)
					_push_quad(verts, normals, colors, c1, c2, t2, t1, berm_wall.darkened(0.08))
					_push_quad(verts, normals, colors, c2, c3, t3, t2, berm_wall)
					_push_quad(verts, normals, colors, c3, c0, t0, t3, berm_wall.darkened(0.08))

	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var inst := MeshInstance3D.new()
	inst.name = "StadiumTurfAndTerraces"
	inst.mesh = mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(inst)
	stats["draws"] = int(stats.get("draws", 0)) + 1


static func _push_quad(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, color: Color) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() > 0.000001:
		n = n.normalized()
		if n.y < 0.0 and absf(a.y - c.y) < 0.01:
			n = -n
	else:
		n = Vector3.UP
	for pt: Vector3 in [a, b, c, a, c, d]:
		verts.append(pt)
		normals.append(n)
		colors.append(color)
