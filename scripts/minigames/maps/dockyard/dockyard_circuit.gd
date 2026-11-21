extends RefCounted
## Race furniture for the Dockyard Quay theme.
##
## The barrier ring is the owner's invariant made visible: one continuous wall
## follows the true road edge on both sides of the whole lap at
## TileKit.BARRIER_CLEARANCE, using the clearance-path geometry so even the
## inside of an 8 m quay hairpin cannot pinch onto the racing surface. The
## outside is a concrete wall; the inside alternates red/white sections.
##
## On top of that ring: covered and open grandstands on the major corners, tyre
## stacks at the apexes, overhead light gantries on the straights, billboards,
## low boards, banner towers and pylons around the apron, flags on the infield
## and floodlights down the quay edge. Every placement is measured against the
## spline before it is emitted; the cells a prop takes are claimed in the plan so
## the yard and the treeline cannot stack on top of them.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const Parts := preload("res://scripts/minigames/maps/dockyard/dockyard_parts.gd")

## A gantry is 20 m wide; it needs a straight at least this long to sit square.
const GANTRY_MIN_RUN: float = 24.0
## Keep gantries clear of the race's own start/finish gate at distance 0.
const START_CLEARANCE: float = 40.0
## Barrier style: the short red/white race blocks, alternated in lap sections.
const INSIDE_BARRIERS: Array[String] = ["barrierRed", "barrierWhite"]
## Barrier ring alternation: one colour change every sixth of a lap.
const INSIDE_SECTIONS: int = 6
const LIGHT_LIMIT: int = 14

const FLAG_KINDS: Array[String] = ["flagRed", "flagCheckers", "flagGreen"]
const SIGN_KINDS: Array[String] = [
	"billboard", "billboardLow", "pylon", "bannerTowerRed",
	"bannerTowerGreen",
]


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
	# Lights claim their quay-edge cells before the optional signage and flags,
	# so a full container yard can never squeeze the floodlights out.
	_lights(parent, spline, plan, stats)
	_signage(parent, spline, plan, stats)
	_flags(parent, spline, plan, stats)
	return stats


## Reserves the fence ring cells under the four hairpin stands. The quay fence
## is built by the yard pass, before the stands, so this pre-pass keeps the two
## passes from clipping a grandstand into a fence panel.
static func reserve_stand_ring(spline: RefCounted, plan: RefCounted) -> void:
	if spline == null or plan == null or not plan.is_grid():
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


## The full barrier ring. Both sides run the whole lap; the run is split at a
## half-tile seam so the wall crosses the start/finish without a snapped
## zero-length span, and the inside is split again into colour sections.
static func _barriers(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	# Open harbour circuit: yellow/red safety rails along the elevated crane
	# overpass, tight outer corners, and the seaside seawall edge only.
	var total: float = maxf(float(plan.total), 1.0)
	var placed: int = TileKit.selective_safety_rails(parent, spline, {
		"bridge_y": 2.2,
		"curve_min": 0.032,
		"spans": [{"from": total * 0.46, "to": total * 0.72, "side": -1.0}],
		"rail_color": Color("e2c044"),
		"accent_color": Color("c7422a"),
		"post_color": Color("38434e"),
	})
	TileKit.build_outer_soft_containment(parent, spline, 12.5)
	stats["objects"] = int(stats["objects"]) + placed
	stats["barriers"] = int(stats["barriers"]) + placed
	if placed > 0:
		stats["draws"] = int(stats["draws"]) + 1


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


## Two stacks per corner on the apex side, just outside the road edge. The stack
## is a primitive torus batch in the kit palette; its collider is on WORLD.
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


## Covered and open stands on the four major corners. reserve_stand_ring() has
## already cleared the fence cells under each footprint; the stand itself is one
## kit model with one WORLD box.
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
# gantries


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
			if gap < 55.0:
				clear = false
				break
		if not clear:
			continue
		chosen.append(candidate)
		if chosen.size() >= 3:
			break
	for distance: float in chosen:
		var count: int = TileKit.gantry(parent, spline, distance)
		if count > 0:
			stats["objects"] = int(stats["objects"]) + count
			stats["gantries"] = int(stats["gantries"]) + 1
			stats["draws"] = int(stats["draws"]) + 1


static func _near_start(distance: float, total: float) -> bool:
	var wrapped: float = fposmod(distance, total)
	return minf(wrapped, total - wrapped) < START_CLEARANCE


# --------------------------------------------------------------------------
# lights


## Fourteen floodlight posts, evenly spread around the outer band and the ring
## beyond it: the quay should read as a lit working dock at speed.
static func _lights(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var points: Array[Vector3] = []
	if plan.is_grid():
		points = _outer_sites(plan, spline, LIGHT_LIMIT, 2)
	else:
		for slot: Variant in plan.arc_slots(32.0, 26.0, true, 20.0):
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


## Up to `limit` spaced sites on the outer bands, free cells first and the
## beyond ring second. Every lattice site is claimed before it is returned.
static func _outer_sites(plan: RefCounted, spline: RefCounted, limit: int,
		stride: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var candidates: Array[Vector2i] = plan.outer_band_cells()
	candidates.append_array(plan.beyond_band_cells())
	candidates.append_array(plan.far_band_cells())
	var seen: int = 0
	for cell: Vector2i in candidates:
		if points.size() >= limit:
			break
		seen += 1
		if (seen - 1) % stride != 0:
			continue
		var point: Vector3 = plan.cell_point(cell)
		if Parts.track_distance(spline, point) < Parts.SAFE_CLEARANCE + 2.0:
			continue
		if plan.is_used(cell):
			continue
		if plan.in_grid(cell):
			if not plan.take(cell):
				continue
		else:
			plan.mark(cell)
		points.append(point)
	return points


# --------------------------------------------------------------------------
# signage


static func _signage(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var centre: Vector3 = plan.centre()
	var entries: Array = []
	if plan.is_grid():
		for index in 20:
			var point: Vector3 = Vector3.ZERO
			var found: bool = false
			var cells: Array[Vector2i] = plan.outer_band_cells()
			cells.append_array(plan.beyond_band_cells())
			cells.append_array(plan.far_band_cells())
			for cell: Vector2i in cells:
				var probe: Vector3 = plan.cell_point(cell)
				if Parts.track_distance(spline, probe) < 20.0:
					continue
				if plan.is_used(cell):
					continue
				if plan.in_grid(cell):
					if not plan.take(cell):
						continue
				else:
					plan.mark(cell)
				point = probe
				found = true
				break
			if not found:
				continue
			var kind: String = SIGN_KINDS[index % SIGN_KINDS.size()]
			entries.append({
				"position": point, "kind": kind,
				"yaw": _face_yaw(point, centre),
			})
	else:
		var slots: Array = plan.arc_slots(20.0, 24.0, true, 18.0)
		var index: int = 0
		for slot: Variant in slots:
			if entries.size() >= 24:
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
			entries.append({
				"position": point, "kind": kind,
				"yaw": _face_yaw(point, centre),
			})
			index += 1
	if entries.is_empty():
		return
	var placed: int = TileKit.signage(parent, entries)
	if placed <= 0:
		return
	stats["objects"] = int(stats["objects"]) + placed
	stats["signs"] = int(stats["signs"]) + placed
	stats["draws"] = int(stats["draws"]) + _sign_draws(entries)


## Yaw that turns a billboard's local +Z front towards the circuit centre. The
## Kenney billboard panel sits on +Z of its legs, so a board outside the loop
## looks at the track instead of at the sea.
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
	var total: int = 0
	for model: String in models:
		total += Parts.part_count(model)
	return total


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


## Flags on the free infield cells and the outer band. A flag pole is a thin
## solid, so the cell has to be off the road by at least the barrier line.
static func _flags(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var centre: Vector3 = plan.centre()
	var points: Array[Vector3] = []
	if plan.is_grid():
		for cell: Vector2i in plan.free_cells():
			if points.size() >= 12:
				break
			var point: Vector3 = plan.cell_point(cell)
			var distance: float = Parts.track_distance(spline, point)
			if distance < 13.0 or distance > 40.0:
				continue
			if plan.is_ring_cell(cell):
				continue
			if not plan.take(cell):
				continue
			points.append(point)
		if points.size() < 12:
			var outer: Array[Vector2i] = plan.outer_band_cells()
			outer.append_array(plan.beyond_band_cells())
			outer.append_array(plan.far_band_cells())
			for cell: Vector2i in outer:
				if points.size() >= 12:
					break
				if plan.is_used(cell):
					continue
				var point: Vector3 = plan.cell_point(cell)
				if Parts.track_distance(spline, point) < 13.0:
					continue
				if plan.in_grid(cell):
					if not plan.take(cell):
						continue
				else:
					plan.mark(cell)
				points.append(point)
	else:
		for slot: Variant in plan.arc_slots(16.0, 14.0, true, 14.0):
			if points.size() >= 12:
				break
			if slot is Vector3:
				points.append(slot)
	if points.is_empty():
		return
	var entries: Array = []
	for index in points.size():
		entries.append({
			"position": points[index],
			"kind": FLAG_KINDS[index % FLAG_KINDS.size()],
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
