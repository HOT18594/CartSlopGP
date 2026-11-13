extends RefCounted
## Race furniture for the Dockyard Quay theme.
##
## Barriers run the two straights on either side of every straight tile
## (`barrierWall` outside, alternating red/white blocks inside), with stacked
## tyres marking the apex of each hairpin, covered and open grandstands on the
## four outside corners, overhead light gantries spanning the long straights and
## a dense layer of billboards, banner towers, pylons and flags around the quay.
##
## All of it goes through TileKit's public helpers, so the placements use the
## same quarter-tile distance snap and half-metre lateral snap as the rest of
## the grid maps, and every solid piece gets a WORLD collider. Signs, flags and
## floodlights take a cell from the plan before they are placed, which keeps the
## fence ring and the treeline from stacking props on the same tile.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const Parts := preload("res://scripts/minigames/maps/dockyard/dockyard_parts.gd")

## A gantry is 20 m wide; it needs a straight at least this long to sit square.
const GANTRY_MIN_RUN: float = 24.0
## Keep gantries clear of the race's own start/finish gate at distance 0.
const START_CLEARANCE: float = 40.0
## Straight barrier style. The inside gets a shorter block for tighter fences.
const OUTSIDE_BARRIER: String = "barrierWall"
const INSIDE_BARRIERS: Array[String] = ["barrierRed", "barrierWhite"]


## Builds every track-side prop, returning {objects, draws, barriers, ...}.
static func build(parent: Node3D, spline: RefCounted,
		plan: RefCounted) -> Dictionary:
	var stats: Dictionary = {
		"objects": 0, "draws": 0, "barriers": 0, "stands": 0,
		"gantries": 0, "signs": 0, "flags": 0, "lights": 0, "tyres": 0,
	}
	if parent == null or spline == null or plan == null:
		return stats
	_barriers(parent, spline, plan, stats)
	_grandstands(parent, spline, plan, stats)
	_gantries(parent, spline, plan, stats)
	_tyres(parent, spline, plan, stats)
	_flags(parent, spline, plan, stats)
	_signage(parent, spline, plan, stats)
	_lights(parent, spline, plan, stats)
	return stats


## Reserves the fence ring cells under the four hairpin stands. The quay fence
## is built by the yard pass, before the stands, so this pre-pass keeps the two
## passes from clipping a grandstand into a fence panel.
static func reserve_stand_ring(spline: RefCounted, plan: RefCounted) -> void:
	if spline == null or plan == null:
		return
	for corner: Dictionary in plan.major_corners(4):
		var curve: float = float(corner["curve"])
		if absf(curve) < 0.02:
			continue
		var side: float = 1.0 if curve > 0.0 else -1.0
		var distance: float = float(corner["distance"])
		var frame: Dictionary = spline.sample(distance)
		var point: Vector3 = frame["position"] \
			+ frame["right"] * (side * TileKit.STAND_OFFSET)
		plan.reserve_ring_area(Vector2i(
			int(floor(point.x / TileKit.TILE_SIZE)),
			int(floor(point.z / TileKit.TILE_SIZE))), 1)


# --------------------------------------------------------------------------
# barriers and tyres


static func _barriers(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	if plan.is_grid():
		var runs: Array = plan.straight_runs()
		for index in runs.size():
			var run: Dictionary = runs[index]
			var from_distance: float = float(run["from"])
			var to_distance: float = float(run["to"])
			_barrier_run(parent, spline, from_distance, to_distance, 1.0,
				OUTSIDE_BARRIER, stats)
			var inside: String = INSIDE_BARRIERS[index % INSIDE_BARRIERS.size()]
			_barrier_run(parent, spline, from_distance, to_distance, -1.0,
				inside, stats)
		return
	# The legacy oval has no straight tile edges to stop at; a continuous run of
	# short blocks follows its corners without chording the road.
	var end: float = plan.total - TileKit.SNAP_STEP
	_barrier_run(parent, spline, 0.0, end, 1.0, "barrierRed", stats)
	_barrier_run(parent, spline, 0.0, end, -1.0, "barrierWhite", stats)


static func _barrier_run(parent: Node3D, spline: RefCounted,
		from_distance: float, to_distance: float, side: float, kind: String,
		stats: Dictionary) -> void:
	var count: int = TileKit.barrier_line(parent, spline, from_distance,
		to_distance, side, kind)
	if count <= 0:
		return
	stats["objects"] = int(stats["objects"]) + count
	stats["barriers"] = int(stats["barriers"]) + count
	stats["draws"] = int(stats["draws"]) + 1


## Two stacks per corner on the apex side, just outside the road edge.
static func _tyres(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	for corner: Dictionary in plan.major_corners(4):
		var distance: float = float(corner["distance"])
		var side: float = -1.0 if float(corner["curve"]) > 0.0 else 1.0
		for offset: float in [-TileKit.SNAP_STEP, TileKit.SNAP_STEP]:
			var count: int = TileKit.tyre_stack(parent, spline,
				distance + offset, side)
			if count > 0:
				stats["objects"] = int(stats["objects"]) + count
				stats["tyres"] = int(stats["tyres"]) + count
				stats["draws"] = int(stats["draws"]) + 1


# --------------------------------------------------------------------------
# grandstands


## Covered and open stands on the four hairpins. reserve_stand_ring() has
## already cleared the fence cells under each footprint.
static func _grandstands(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var corners: Array = plan.major_corners(4)
	for index in corners.size():
		var corner: Dictionary = corners[index]
		var distance: float = float(corner["distance"])
		var curve: float = float(corner["curve"])
		if absf(curve) < 0.02:
			continue
		var side: float = 1.0 if curve > 0.0 else -1.0
		var covered: bool = index < 2
		var count: int = TileKit.grandstand(parent, spline, distance, side,
			covered)
		if count <= 0:
			continue
		stats["objects"] = int(stats["objects"]) + count
		stats["stands"] = int(stats["stands"]) + count
		stats["draws"] = int(stats["draws"]) + 1


# --------------------------------------------------------------------------
# gantries and floodlights


static func _gantries(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var candidates: Array[float] = []
	for run: Dictionary in plan.straight_runs():
		if float(run["length"]) < GANTRY_MIN_RUN:
			continue
		var middle: float = float(run["from"]) + float(run["length"]) * 0.5
		if _near_start(middle, plan.total):
			continue
		candidates.append(middle)
	if candidates.is_empty():
		for fraction: float in [0.14, 0.46, 0.78]:
			candidates.append(plan.total * fraction)
	var chosen: Array[float] = []
	for candidate: float in candidates:
		var clear: bool = true
		for other: float in chosen:
			var gap: float = absf(fposmod(candidate - other + plan.total * 0.5,
				plan.total) - plan.total * 0.5)
			if gap < 50.0:
				clear = false
				break
		if not clear:
			continue
		chosen.append(candidate)
		if chosen.size() >= 4:
			break
	# A free oval can be too wobbly for four straight runs; keep the gantries
	# spread around the lap instead of dropping to one.
	for fraction: float in [0.18, 0.48, 0.78]:
		if chosen.size() >= 3:
			break
		var distance: float = plan.total * fraction
		if _near_start(distance, plan.total):
			continue
		var clear: bool = true
		for other: float in chosen:
			var gap: float = absf(fposmod(distance - other + plan.total * 0.5,
				plan.total) - plan.total * 0.5)
			if gap < 50.0:
				clear = false
				break
		if clear:
			chosen.append(distance)
	for distance: float in chosen:
		var count: int = TileKit.gantry(parent, spline, distance)
		if count > 0:
			stats["objects"] = int(stats["objects"]) + count
			stats["gantries"] = int(stats["gantries"]) + 1
			stats["draws"] = int(stats["draws"]) + 1


static func _lights(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var points: Array[Vector3] = []
	if plan.is_grid():
		var candidates: Array = [
			Vector2i(1, 0), Vector2i(5, 0), Vector2i(9, 0), Vector2i(13, 0),
			Vector2i(2, 0), Vector2i(12, 0),
			Vector2i(1, 9), Vector2i(5, 9), Vector2i(9, 9), Vector2i(13, 9),
			Vector2i(2, 9), Vector2i(12, 9),
			Vector2i(0, 2), Vector2i(0, 7), Vector2i(14, 2), Vector2i(14, 7),
			Vector2i(0, 1), Vector2i(14, 1), Vector2i(0, 8), Vector2i(14, 8),
		]
		points = plan.take_cells(candidates, 10)
	else:
		var slots: Array = plan.arc_slots(32.0, 26.0, true, 20.0)
		for slot: Variant in slots:
			if points.size() >= 10:
				break
			if slot is Vector3:
				points.append(slot)
	if points.is_empty():
		return
	var entries: Array = []
	for point: Vector3 in points:
		entries.append({"position": point, "kind": TileCatalog.LIGHT_POST,
			"yaw": 0.0})
	var placed: int = TileKit.lights(parent, entries)
	if placed <= 0:
		return
	stats["objects"] = int(stats["objects"]) + placed
	stats["lights"] = int(stats["lights"]) + placed
	stats["draws"] = int(stats["draws"]) + 1


static func _near_start(distance: float, total: float) -> bool:
	var wrapped: float = fposmod(distance, total)
	return minf(wrapped, total - wrapped) < START_CLEARANCE


# --------------------------------------------------------------------------
# signage


static func _signage(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var centre: Vector3 = plan.centre()
	var entries: Array = []
	if plan.is_grid():
		for point: Vector3 in plan.take_cells([
				Vector2i(3, 0), Vector2i(11, 0),
				Vector2i(3, 9), Vector2i(11, 9),
				Vector2i(6, 0), Vector2i(6, 9)], 6):
			entries.append(_sign_entry(point, "billboard", centre))
		for point: Vector3 in plan.take_cells([
				Vector2i(4, 0), Vector2i(8, 0),
				Vector2i(4, 9), Vector2i(8, 9)], 4):
			entries.append(_sign_entry(point, "billboardLow", centre))
		var banner_index: int = 0
		for point: Vector3 in plan.take_cells([
				Vector2i(2, 0), Vector2i(12, 0),
				Vector2i(2, 9), Vector2i(12, 9)], 4):
			var kind: String = "bannerTowerRed" if banner_index % 2 == 0 \
				else "bannerTowerGreen"
			entries.append(_sign_entry(point, kind, centre))
			banner_index += 1
		var pylons: Array[Vector3] = plan.take_cells([
			Vector2i(0, 0), Vector2i(1, 0), Vector2i(5, 0), Vector2i(7, 0),
			Vector2i(9, 0), Vector2i(13, 0), Vector2i(14, 0),
			Vector2i(0, 9), Vector2i(1, 9), Vector2i(5, 9), Vector2i(7, 9),
			Vector2i(9, 9), Vector2i(13, 9), Vector2i(14, 9),
			Vector2i(0, 2), Vector2i(0, 7), Vector2i(14, 2), Vector2i(14, 7),
			Vector2i(1, 3), Vector2i(1, 6), Vector2i(13, 3), Vector2i(13, 6),
		], 14)
		for point: Vector3 in pylons:
			entries.append(_sign_entry(point, "pylon", centre))
	else:
		var slots: Array = plan.arc_slots(20.0, 24.0, true, 18.0)
		var index: int = 0
		for slot: Variant in slots:
			if entries.size() >= 28:
				break
			if not (slot is Vector3):
				continue
			var point: Vector3 = slot
			var kind: String = "pylon"
			if index < 4:
				kind = "bannerTowerRed" if index % 2 == 0 \
					else "bannerTowerGreen"
			elif index < 14:
				kind = "billboardLow" if index % 4 == 0 else "billboard"
			entries.append(_sign_entry(point, kind, centre))
			index += 1
	if entries.is_empty():
		return
	var placed: int = TileKit.signage(parent, entries)
	if placed <= 0:
		return
	stats["objects"] = int(stats["objects"]) + placed
	stats["signs"] = int(stats["signs"]) + placed
	stats["draws"] = int(stats["draws"]) + _sign_draws(entries)


static func _sign_entry(point: Vector3, kind: String,
		centre: Vector3) -> Dictionary:
	return {"position": point, "kind": kind, "yaw": _face_yaw(point, centre)}


## Yaw that turns a billboard's local +Z front towards the circuit centre. The
## Kenney billboard panel sits on +Z of its legs (the OBJ's back plate is at
## -Z), so a board outside the loop looks at the track instead of at the sea.
static func _face_yaw(point: Vector3, centre: Vector3) -> float:
	var direction := Vector3(centre.x - point.x, 0.0, centre.z - point.z)
	if direction.length_squared() < 0.01:
		return 0.0
	direction = direction.normalized()
	return atan2(direction.x, direction.z)


static func _sign_draws(entries: Array) -> int:
	var models: Dictionary = {}
	for entry: Variant in entries:
		if not (entry is Dictionary):
			continue
		var data: Dictionary = entry as Dictionary
		models[_sign_model(str(data.get("kind", "billboard")))] = true
	return models.size()


static func _sign_model(kind: String) -> String:
	match kind:
		"billboardLow":
			return TileCatalog.BILLBOARD_LOW
		"pylon":
			return TileCatalog.PYLON
		"bannerTower", "bannerTowerRed":
			return TileCatalog.BANNER_TOWER
		"bannerTowerGreen":
			return TileCatalog.BANNER_TOWER_GREEN
		_:
			return TileCatalog.BILLBOARD


# --------------------------------------------------------------------------
# flags


static func _flags(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var centre: Vector3 = plan.centre()
	var points: Array[Vector3] = []
	if plan.is_grid():
		# The infield cells between the chicane, the garages and the pit apron:
		# flag poles there never fight the outer-band billboards for a cell.
		points = plan.take_cells([
			Vector2i(6, 2), Vector2i(7, 2),
			Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4),
			Vector2i(3, 5), Vector2i(11, 5),
		], 8)
	else:
		var slots: Array = plan.arc_slots(16.0, 14.0, true, 14.0)
		for slot: Variant in slots:
			if points.size() >= 12:
				break
			if slot is Vector3:
				points.append(slot)
	if points.is_empty():
		return
	var entries: Array = []
	for index in points.size():
		var kind: String = "flagRed" if index % 2 == 0 else "flagCheckers"
		entries.append({
			"position": points[index],
			"kind": kind,
			"yaw": _face_yaw(points[index], centre),
		})
	var placed: int = TileKit.flags(parent, entries)
	if placed <= 0:
		return
	stats["objects"] = int(stats["objects"]) + placed
	stats["flags"] = int(stats["flags"]) + placed
	stats["draws"] = int(stats["draws"]) + 2 * _model_draws(entries)


static func _model_draws(entries: Array) -> int:
	var models: Dictionary = {}
	for entry: Variant in entries:
		if entry is Dictionary:
			models[str((entry as Dictionary).get("kind", "flagRed"))] = true
	return models.size()
