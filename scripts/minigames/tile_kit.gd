extends RefCounted
class_name TileKit
## Cartoon prop API for the Kenney grid maps.
##
## Map agents only type an ASCII grid (see scripts/minigames/tiles/
## kenney_tiles.gd) and then dress it from a theme. A theme is loaded by
## grass_race and must implement exactly:
##
##   # maps/<id>_theme.gd
##   static func build(race: Node3D, spline) -> void
##       # calls tile_kit.* helpers below and returns nothing
##
## The `spline` is the GridSpline returned by KenneyTiles.build, so it exposes
## total_length, sample(), yaw_at() and closest(). Every helper snaps its
## placement to the tile grid: arc distances to a quarter tile, lateral offsets
## to half a metre and points passed as positions to a cell centre.
##
## Clearance is an invariant, not a suggestion. Barriers and banks are placed by
## walking the true road edge geometry (KenneyTiles.clearance_path) at a
## constant lateral distance and are asserted to never come inside
## BARRIER_CLEARANCE of the centreline, so nothing solid can sit on the racing
## surface even on the inside of an 8 m corner.
##
## Repeated props of the same model are batched into one MultiMesh per mesh
## part; one-off pieces (grandstands, gantries, overhead lights) are instantiated
## normally. Every solid piece carries a StaticBody3D collider on
## CollisionLayers.WORLD so it can never be driven through.
##
## `side` is +1 for the right-hand side of the direction of travel and -1 for
## the left, matching the old racing_kit helpers.

const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const TileGeometry := preload("res://scripts/minigames/tiles/kenney_tiles.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

const TILE_SIZE: float = TileCatalog.TILE_SIZE
const ROAD_HALF: float = TileCatalog.ROAD_HALF
const SNAP_STEP: float = TileCatalog.SNAP_STEP
const PROP_SCALE: float = TileCatalog.PROP_SCALE
const NATURE_SCALE: float = TileCatalog.NATURE_SCALE

## Lateral offsets from the centreline, in metres. They are snapped again to
## half a metre so every prop lands on the same lattice.
##
## BARRIER_OFFSET is the clearance beyond the drivable lane edge, so
## BARRIER_CLEARANCE (roughly the road half width plus 2.5 m) is the closest any
## barrier surface may come to the centreline. It lands two centimetres outside
## the visible 16 m tile edge, which is where the Kenney road mesh ends.
const BARRIER_OFFSET: float = 2.5
const BARRIER_CLEARANCE: float = ROAD_HALF + BARRIER_OFFSET
## A grandstand is a full 16 m kit footprint, so its centre sits a little over
## one cell out: its front edge then clears the barrier's outer face instead of
## swallowing the wall.
const STAND_OFFSET: float = TILE_SIZE * 1.15
## A barrier piece is a 4 m chord, so on the outside of a corner its middle sags
## inside the arc and a tilted piece on a hill shifts a couple of centimetres.
## The placement line is pushed out by this much so even after both effects no
## piece comes inside BARRIER_CLEARANCE.
const BARRIER_SAG: float = 0.30
## Meta flag on every barrier body, so an audit can find the wall even when two
## runs share a node name.
const BARRIER_META: String = "tile_barrier"
## Path sample spacing for the barrier/bank walkers, in metres.
const CLEARANCE_STEP: float = 0.75
## Nature-kit bank geometry: the inner face of a bank sits BARRIER_CLEARANCE
## from the centreline, so the models extend BANK_INSET further out.
const BANK_INSET: float = 3.2
const BANK_SPACING: float = 7.0
const BANK_MODELS: Array[String] = [
	"rock_largeA", "rock_largeB", "rock_tallA", "rock_largeF",
]
const TYRE_OFFSET: float = 2.0

const FLAG_SCALE: float = TILE_SIZE * 0.65
const TYRE_RADIUS: float = 0.30
const TYRE_TUBE: float = 0.16
const TYRE_LEVELS: int = 4
const TYRE_LEVEL_STEP: float = 0.38
const TYRE_COLLIDER_RADIUS: float = 0.66

static var _tyre_mesh: TorusMesh = null
static var _tyre_material: StandardMaterial3D = null


# --------------------------------------------------------------------------
# barriers and tyres


## Red/white/wall barrier run along one edge of the track. The run follows the
## real road edge at a constant BARRIER_CLEARANCE from the centreline: straight
## cells give a straight wall, the outside of a corner gives a concentric arc,
## and the inside of a corner is mitred between the two neighbouring walls
## instead of being offset onto the racing surface. Each piece is a real wall
## section with its own box collider on WORLD, laid along the path chord, so the
## wall is continuous and never chords across a corner. Distances snap to a
## quarter tile.
static func barrier_line(parent: Node3D, spline: RefCounted, from_dist: float,
		to_dist: float, side: float, kind: String = "barrierRed") -> int:
	if parent == null or spline == null:
		return 0
	var spec: Dictionary = TileCatalog.barrier_spec(kind)
	var piece_length: float = float(spec.get("length", 0.25)) * TILE_SIZE
	if piece_length <= 0.01:
		return 0
	var total: float = maxf(float(spline.total_length), 0.001)
	var direction: float = 1.0 if side >= 0.0 else -1.0
	var start: float = _snap_distance(spline, from_dist)
	var span: float = fposmod(to_dist - start, total)
	if span <= 0.01:
		span = total
	var model: String = str(spec.get("model", "barrierRed"))
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return 0
	var path: Dictionary = TileGeometry.clearance_path(spline, direction,
		BARRIER_CLEARANCE + BARRIER_SAG, CLEARANCE_STEP)
	if not bool(path.get("ok", false)):
		push_warning("TileKit.barrier_line: no usable %s clearance path for this spline." % (
			"right" if direction > 0.0 else "left"))
		return 0
	var run_length: float = _path_run_length(path, start, span,
		float(spline.total_length))
	if run_length <= piece_length * 0.5:
		return 0
	var size_y: float = float(spec.get("height", 0.1312)) * TILE_SIZE
	var size_z: float = float(spec.get("depth", 0.123)) * TILE_SIZE
	var from_position: float = _path_position(path, start)
	var body := _static_body(parent, "Barrier_%s_%d_%s" % [
		kind, int(round(start)), "R" if direction > 0.0 else "L"])
	body.set_meta(BARRIER_META, true)
	body.set_meta("tile_barrier_clearance", BARRIER_CLEARANCE)
	var transforms: Array = []
	var closest: float = INF
	# Sharp path corners are mitres: a 4 m chord across one would cut the corner
	# and reach inside BARRIER_CLEARANCE, so each smooth stretch is walled on its
	# own and the pieces meet at the corner point.
	var cuts: PackedFloat32Array = _run_cuts(path, from_position, run_length)
	for index in range(0, cuts.size() - 1):
		var segment_from: float = cuts[index]
		var segment_to: float = cuts[index + 1]
		var segment_length: float = segment_to - segment_from
		if segment_length < 0.4:
			continue
		var count: int = maxi(int(round(segment_length / piece_length)), 1)
		var step_length: float = segment_length / float(count)
		for piece in count:
			var s0: float = segment_from + step_length * float(piece)
			var s1: float = s0 + step_length
			var p0: Vector3 = _path_point(path, s0)
			var p1: Vector3 = _path_point(path, s1)
			var chord: Vector3 = p1 - p0
			var horizontal: float = Vector2(chord.x, chord.z).length()
			if horizontal < 0.02:
				continue
			var yaw: float = atan2(-chord.z, chord.x)
			var pitch: float = atan2(chord.y, horizontal)
			var outward := Vector3(-chord.z, 0.0, chord.x).normalized() * direction
			var middle: Vector3 = (p0 + p1) * 0.5
			var centre: Vector3 = middle + outward * (size_z * 0.5)
			centre.y = middle.y
			var length: float = maxf(chord.length(), 0.1)
			var scale := Vector3(PROP_SCALE * length / piece_length, PROP_SCALE,
				PROP_SCALE)
			var xform: Transform3D = _fit_transform(model, centre, yaw, scale)
			var axis: Vector3 = Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, 1.0)
			transforms.append(_tilt(xform, centre, axis, pitch))
			var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(0.0, 0.0, 1.0),
				pitch)
			_add_box_shape(body, Transform3D(basis,
				centre + basis * Vector3.UP * (size_y * 0.5)),
				Vector3(length * 0.98, size_y, size_z))
			closest = minf(closest, _min_clearance(spline, p0, p1, middle))
	if transforms.is_empty():
		# A degenerate run (a seam inside one corner) leaves nothing to show.
		body.free()
		return 0
	_batch_model(body, model, transforms, "BarrierRun", true)
	_assert_run_clearance(closest, start, span, direction)
	return transforms.size()


## Splits a path run at its sharp corners: [from, corner…, from + length].
## Every stretch between two cuts is smooth enough for a straight barrier piece
## to stay outside its own arc.
static func _run_cuts(path: Dictionary, from_position: float,
		run_length: float) -> PackedFloat32Array:
	var cuts := PackedFloat32Array()
	cuts.append(from_position)
	var total: float = maxf(float(path["total_length"]), 0.001)
	var breaks: PackedFloat32Array = _path_breaks(path)
	if not breaks.is_empty():
		var end: float = from_position + run_length
		var selected: Array[float] = []
		for raw: float in breaks:
			var value: float = raw
			while value <= from_position + 0.001:
				value += total
			if value < end - 0.2:
				selected.append(value)
		selected.sort()
		for value: float in selected:
			cuts.append(value)
	cuts.append(from_position + run_length)
	return cuts


## Path arc lengths of the sharp corners (mitres), where a barrier piece must
## end instead of bridging across.
static func _path_breaks(path: Dictionary) -> PackedFloat32Array:
	var breaks := PackedFloat32Array()
	var points: PackedVector3Array = path["points"]
	var lengths: PackedFloat32Array = path["lengths"]
	if points.size() < 4 or lengths.size() != points.size():
		return breaks
	# Drop the duplicated closing point, then walk the ring.
	var count: int = points.size()
	if count > 1 and points[0].distance_to(points[count - 1]) < 0.001:
		count -= 1
	var limit: float = deg_to_rad(10.0)
	for index in count:
		var previous: Vector3 = points[posmod(index - 1, count)]
		var current: Vector3 = points[index]
		var next: Vector3 = points[posmod(index + 1, count)]
		var incoming: Vector3 = current - previous
		var outgoing: Vector3 = next - current
		incoming.y = 0.0
		outgoing.y = 0.0
		if incoming.length() < 0.001 or outgoing.length() < 0.001:
			continue
		if incoming.angle_to(outgoing) > limit:
			breaks.append(lengths[index])
	return breaks


## Publishes the closest approach of one run and fails a debug build when a
## piece would be on the racing surface.
static func _assert_run_clearance(closest: float, start: float, span: float,
		direction: float) -> void:
	if closest == INF:
		return
	if closest >= BARRIER_CLEARANCE - 0.02:
		return
	push_error("TileKit.barrier_line: %s run from %.1f m over %.1f m has a barrier %.2f m from the centreline, inside BARRIER_CLEARANCE %.2f m." % [
		"right" if direction > 0.0 else "left", start, span, closest,
		BARRIER_CLEARANCE])


## Closest plan distance from a barrier run's three sampled points to the
## centreline. Uses the grid spline's exact plan helper when available.
static func _min_clearance(spline: RefCounted, p0: Vector3, p1: Vector3,
		p2: Vector3) -> float:
	return minf(spline_distance(spline, p0),
		minf(spline_distance(spline, p1), spline_distance(spline, p2)))


## Debug assert for a whole built circuit: measures every barrier collider and
## reports the closest approach, so a map can prove its wall clears the road.
## Returns true when every piece is at least BARRIER_CLEARANCE from the
## centreline.
static func assert_barrier_clearance(parent: Node3D, spline: RefCounted,
		label: String = "") -> bool:
	var report: Dictionary = barrier_clearance(parent, spline)
	var clears: bool = bool(report["clears"])
	print("BARRIER CLEARANCE %s: %d piece(s), closest %.2f m, limit %.2f m -> %s" % [
		label if label != "" else "circuit", int(report["pieces"]),
		float(report["closest"]), float(report["limit"]),
		"CLEARS" if clears else "ON THE ROAD"])
	if not clears and OS.is_debug_build():
		push_error("TileKit.assert_barrier_clearance: %s has %d barrier piece(s) inside %.2f m of the centreline (closest %.2f m)." % [
			label if label != "" else "circuit", int(report["offenders"]),
			float(report["limit"]), float(report["closest"])])
	return clears


## Closest plan approach of every barrier collider under `parent` to the
## centreline: {pieces, closest, limit, offenders, clears}.
static func barrier_clearance(parent: Node3D, spline: RefCounted) -> Dictionary:
	var report: Dictionary = {"pieces": 0, "closest": INF,
		"limit": BARRIER_CLEARANCE, "offenders": 0, "clears": false}
	if parent == null or spline == null:
		report["closest"] = 0.0
		return report
	_walk_barrier_shapes(parent, spline, report)
	var closest: float = float(report["closest"])
	if closest == INF:
		closest = 0.0
	report["closest"] = closest
	report["clears"] = closest >= BARRIER_CLEARANCE - 0.02
	return report


static func _walk_barrier_shapes(node: Node, spline: RefCounted,
		report: Dictionary) -> void:
	for child: Node in node.get_children():
		if child is StaticBody3D and bool(child.get_meta(BARRIER_META, false)):
			for shape_node: Node in child.get_children():
				var collision := shape_node as CollisionShape3D
				if collision == null:
					continue
				var box := collision.shape as BoxShape3D
				if box == null:
					continue
				_measure_barrier_box(collision, box, spline, report)
		_walk_barrier_shapes(child, spline, report)


static func _measure_barrier_box(collision: CollisionShape3D, box: BoxShape3D,
		spline: RefCounted, report: Dictionary) -> void:
	var xform: Transform3D = _world_transform(collision)
	var half: Vector3 = box.size * 0.5
	var closest: float = INF
	for point: Vector3 in _box_samples(half):
		closest = minf(closest, spline_distance(spline, xform * point))
	if closest == INF:
		return
	report["pieces"] = int(report["pieces"]) + 1
	report["closest"] = minf(float(report["closest"]), closest)
	if closest < BARRIER_CLEARANCE - 0.02:
		report["offenders"] = int(report["offenders"]) + 1


## Eight corners plus the four face centres of a box, so the audit does not only
## look at the ends of a long barrier piece.
static func _box_samples(half: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for ix: int in [-1, 1]:
		for iy: int in [-1, 1]:
			for iz: int in [-1, 1]:
				points.append(Vector3(half.x * float(ix), half.y * float(iy),
					half.z * float(iz)))
	points.append(Vector3.ZERO)
	points.append(Vector3(0.0, 0.0, half.z))
	points.append(Vector3(0.0, 0.0, -half.z))
	points.append(Vector3(half.x, 0.0, 0.0))
	points.append(Vector3(-half.x, 0.0, 0.0))
	return points


## Composes the parent chain, so a collider under a themed holder measures in
## world space even when a tool builds the map off-tree.
static func _world_transform(node: Node3D) -> Transform3D:
	var xform: Transform3D = node.transform
	var current: Node = node.get_parent()
	while current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


## One stack of cartoon tyres. The racing kit ships no tyre model, so the stack
## is a primitive torus batch in the same flat palette; the collider is a real
## cylinder on WORLD.
static func tyre_stack(parent: Node3D, spline: RefCounted, dist: float,
		side: float) -> int:
	if parent == null or spline == null:
		return 0
	var direction: float = 1.0 if side >= 0.0 else -1.0
	var lateral: float = _snap_lateral(ROAD_HALF + TYRE_OFFSET) * direction
	var distance: float = _snap_distance(spline, dist)
	var point: Vector3 = _point_at(spline, distance, lateral)
	var body := _static_body(parent, "Tyres_%d" % int(round(distance)))
	var transforms: Array = []
	var colours: Array = []
	for level in TYRE_LEVELS:
		transforms.append(Transform3D(Basis.IDENTITY,
			point + Vector3.UP * (TYRE_TUBE + float(level) * TYRE_LEVEL_STEP)))
		colours.append(Color("121114") if level < TYRE_LEVELS - 1 \
			else Color("c23a2c"))
	var instance := _multimesh(_tyre_geometry(), _tyre_paint(), transforms,
		"TyreStack", false, colours)
	body.add_child(instance)
	var height: float = TYRE_TUBE * 2.0 + float(TYRE_LEVELS) * TYRE_LEVEL_STEP
	_add_cylinder_shape(body, point, TYRE_COLLIDER_RADIUS, height)
	return 1


# --------------------------------------------------------------------------
# terrain


## A berm/bank run along the outside of the circuit, built from nature-kit rock
## blocks. It follows the same clearance path as the barriers, so a map can dress
## elevation cheaply and still guarantee the banks never reach the road: the
## inner face of every bank sits BARRIER_CLEARANCE from the centreline. Banks
## follow the spline height, so they climb with an elevated circuit, and each one
## carries a WORLD box collider.
static func terrain_banks(parent: Node3D, spline: RefCounted, from_dist: float,
		to_dist: float, side: float, height: float = 1.6) -> int:
	if parent == null or spline == null:
		return 0
	var total: float = maxf(float(spline.total_length), 0.001)
	var direction: float = 1.0 if side >= 0.0 else -1.0
	var start: float = _snap_distance(spline, from_dist)
	var span: float = fposmod(to_dist - start, total)
	if span <= 0.01:
		span = total
	if span < BANK_SPACING * 0.5:
		return 0
	var path: Dictionary = TileGeometry.clearance_path(spline, direction,
		BARRIER_CLEARANCE + BANK_INSET, CLEARANCE_STEP)
	if not bool(path.get("ok", false)):
		return 0
	var run_length: float = _path_run_length(path, start, span, total)
	var count: int = maxi(int(floor(run_length / BANK_SPACING)), 1)
	var step: float = run_length / float(count)
	var from_position: float = _path_position(path, start)
	var body := _static_body(parent, "TerrainBanks_%d_%s" % [
		int(round(start)), "R" if direction > 0.0 else "L"])
	var scale_factor: float = NATURE_SCALE * clampf(height / 2.0, 0.55, 1.6)
	var batches: Dictionary = {}
	var placed: int = 0
	for index in count:
		var s: float = from_position + step * (float(index) + 0.5)
		var point: Vector3 = _path_point(path, s)
		if spline_distance(spline, point) < BARRIER_CLEARANCE - 0.02:
			continue
		var model: String = TileCatalog.pick(BANK_MODELS, index, "rock_largeA")
		var jitter: float = 0.85 + 0.3 * fposmod(float(index) * 0.61803398875,
			1.0)
		var bank_scale: float = scale_factor * jitter
		if not batches.has(model):
			batches[model] = []
		(batches[model] as Array).append(_fit_transform(model, point,
			float(index) * 1.7, Vector3.ONE * bank_scale, true))
		_add_box_shape(body, Transform3D(Basis.IDENTITY,
			point + Vector3.UP * (height * 0.5)),
			Vector3(BANK_INSET * 1.6, height, BANK_INSET * 1.6))
		placed += 1
	for model: String in batches:
		_batch_model(body, model, batches[model] as Array, "Bank_" + model,
			false, true)
	return placed


# --------------------------------------------------------------------------
# structures


## A stepped grandstand with (covered) or without a roof, facing the track from
## `side`. The whole footprint is one WORLD collision box.
static func grandstand(parent: Node3D, spline: RefCounted, dist: float,
		side: float, covered: bool = false) -> int:
	if parent == null or spline == null:
		return 0
	var model: String = TileCatalog.GRANDSTAND_COVERED if covered \
		else TileCatalog.GRANDSTAND_OPEN
	var direction: float = 1.0 if side >= 0.0 else -1.0
	var distance: float = _snap_distance(spline, dist)
	var point: Vector3 = _point_at(spline, distance,
		_snap_lateral(STAND_OFFSET) * direction)
	var yaw: float = _along_track_yaw(spline, distance) \
		+ (PI * 0.5 if direction > 0.0 else -PI * 0.5)
	var node := _emit_unique(parent, model,
		_fit_transform(model, point, yaw, Vector3.ONE * PROP_SCALE),
		"Grandstand_%d" % int(round(distance)))
	if node == null:
		return 0
	var body := _static_body(parent, "GrandstandCollision_%d" % int(round(distance)))
	var size: Vector3 = _scaled_size(model, Vector3.ONE * PROP_SCALE)
	_add_box_shape(body, Transform3D(Basis(Vector3.UP, yaw),
		point + Vector3.UP * (size.y * 0.5)), size)
	return 1


## A row of pit garages on the grid cell centres in `grid_positions`. Entries
## may be Vector2i(column, row), [column, row] or a world Vector3 that snaps to
## its cell. Garages are batched; each gets a box collider.
static func pit_building(parent: Node3D, grid_positions: Array) -> int:
	if parent == null or grid_positions.is_empty():
		return 0
	var body := _static_body(parent, "PitBuildings")
	var transforms: Array = []
	var points: Array[Vector3] = []
	for entry: Variant in grid_positions:
		var point: Vector3 = _grid_point(entry)
		points.append(point)
		transforms.append(_fit_transform(TileCatalog.PIT_GARAGE, point, 0.0,
			Vector3.ONE * PROP_SCALE))
	_batch_model(body, TileCatalog.PIT_GARAGE, transforms, "PitGarages", true)
	var size: Vector3 = _scaled_size(TileCatalog.PIT_GARAGE,
		Vector3.ONE * PROP_SCALE)
	for point: Vector3 in points:
		_add_box_shape(body, Transform3D(Basis.IDENTITY,
			point + Vector3.UP * (size.y * 0.5)),
			Vector3(minf(size.x, TILE_SIZE), size.y, minf(size.z, TILE_SIZE)))
	return points.size()


## Floodlight posts on the grid. `positions` entries are Vector3 cell points or
## {position, kind, yaw} dictionaries; kind `overhead` places a lit gantry.
static func lights(parent: Node3D, positions: Array) -> int:
	if parent == null or positions.is_empty():
		return 0
	var body := _static_body(parent, "Lights")
	var post_transforms: Array = []
	var post_spots: Array[Vector3] = []
	var placed: int = 0
	for index in positions.size():
		var entry: Variant = positions[index]
		var point := Vector3.ZERO
		var kind: String = TileCatalog.LIGHT_POST
		var yaw: float = 0.0
		if entry is Dictionary:
			var data: Dictionary = entry as Dictionary
			point = _grid_point(data.get("position", Vector3.ZERO))
			kind = str(data.get("kind", TileCatalog.LIGHT_POST))
			yaw = float(data.get("yaw", 0.0))
		else:
			point = _grid_point(entry)
		if kind == "overhead" or kind == TileCatalog.LIGHT_GANTRY:
			var xform: Transform3D = _fit_transform(TileCatalog.LIGHT_GANTRY,
				point, yaw, Vector3.ONE * PROP_SCALE)
			if _emit_unique(body, TileCatalog.LIGHT_GANTRY, xform,
					"GantryLight_%d" % index) != null:
				_add_gantry_colliders(body, TileCatalog.LIGHT_GANTRY, xform,
					PROP_SCALE)
				placed += 1
			continue
		post_transforms.append(_fit_transform(TileCatalog.LIGHT_POST, point,
			yaw, Vector3.ONE * PROP_SCALE))
		post_spots.append(point)
		placed += 1
	if not post_transforms.is_empty():
		_batch_model(body, TileCatalog.LIGHT_POST, post_transforms,
			"LightPosts", true)
	var height: float = _scaled_size(TileCatalog.LIGHT_POST,
		Vector3.ONE * PROP_SCALE).y
	for point: Vector3 in post_spots:
		_add_cylinder_shape(body, point, 0.45, height)
	return placed


## Billboards, pylons and banner towers. Entries are Vector3 cell points or
## {position, kind, yaw}; kind is `billboard`, `billboardLow`, `pylon`,
## `bannerTower` (red) or `bannerTowerGreen`.
static func signage(parent: Node3D, positions: Array) -> int:
	if parent == null or positions.is_empty():
		return 0
	var body := _static_body(parent, "Signage")
	var batches: Dictionary = {}
	var colliders: Array = []
	for entry: Variant in positions:
		var point := Vector3.ZERO
		var kind: String = "billboard"
		var yaw: float = 0.0
		if entry is Dictionary:
			var data: Dictionary = entry as Dictionary
			point = _grid_point(data.get("position", Vector3.ZERO))
			kind = str(data.get("kind", "billboard"))
			yaw = float(data.get("yaw", 0.0))
		else:
			point = _grid_point(entry)
		var model: String = _sign_model(kind)
		var scale: float = TileCatalog.sign_scale(kind)
		if not batches.has(model):
			batches[model] = []
		(batches[model] as Array).append(_fit_transform(model, point, yaw,
			Vector3.ONE * scale))
		colliders.append({"model": model, "point": point, "yaw": yaw,
			"scale": scale})
	for model: String in batches:
		_batch_model(body, model, batches[model] as Array, "Sign_" + model, true)
	for data: Dictionary in colliders:
		var size: Vector3 = _scaled_size(str(data["model"]),
			Vector3.ONE * float(data["scale"]))
		var point: Vector3 = data["point"]
		var yaw: float = float(data["yaw"])
		_add_box_shape(body, Transform3D(Basis(Vector3.UP, yaw),
			point + Vector3.UP * (size.y * 0.5)), size)
	return positions.size()


## Flag poles. Entries are Vector3 cell points or {position, kind, yaw};
## kind is flagRed, flagGreen, flagCheckers or flagCheckersSmall.
static func flags(parent: Node3D, positions: Array) -> int:
	if parent == null or positions.is_empty():
		return 0
	var body := _static_body(parent, "Flags")
	var batches: Dictionary = {}
	var poles: Array[Vector3] = []
	for index in positions.size():
		var entry: Variant = positions[index]
		var point := Vector3.ZERO
		var yaw: float = 0.0
		var model: String = TileCatalog.pick(TileCatalog.FLAG_MODELS, index,
			"flagRed")
		if entry is Dictionary:
			var data: Dictionary = entry as Dictionary
			point = _grid_point(data.get("position", Vector3.ZERO))
			model = str(data.get("kind", model))
			yaw = float(data.get("yaw", 0.0))
		else:
			point = _grid_point(entry)
		if not batches.has(model):
			batches[model] = []
		(batches[model] as Array).append(_fit_transform(model, point, yaw,
			Vector3.ONE * FLAG_SCALE))
		poles.append(point)
	for model: String in batches:
		_batch_model(body, model, batches[model] as Array, "Flag_" + model, true)
	var height: float = _scaled_size("flagRed", Vector3.ONE * FLAG_SCALE).y
	for point: Vector3 in poles:
		_add_box_shape(body, Transform3D(Basis.IDENTITY,
			point + Vector3.UP * (height * 0.5)),
			Vector3(0.35, height, 0.35))
	return poles.size()


## Trees, bushes and rocks from the Kenney nature kit. A position is rejected
## when it is not outside the barrier line, so foliage can never grow through
## the track. Entries are Vector3 cell points or {position, kind, scale}.
## `spline` is optional: when omitted the track is found through the
## `kenney_spline` metadata KenneyTiles.build stores on the race root.
static func trees(parent: Node3D, positions: Array,
		spline: RefCounted = null) -> int:
	if parent == null or positions.is_empty():
		return 0
	var track: RefCounted = spline if spline != null else _find_spline(parent)
	if track == null:
		push_warning("TileKit.trees: no spline found; barrier clearance was not checked.")
	var body := _static_body(parent, "Foliage")
	var batches: Dictionary = {}
	var placed: int = 0
	var rejected: int = 0
	for index in positions.size():
		var entry: Variant = positions[index]
		var point := Vector3.ZERO
		var model: String = TileCatalog.pick(TileCatalog.TREE_MODELS, index,
			"tree_default")
		var jitter: float = 0.85 + 0.30 * fposmod(float(index) * 0.61803398875,
			1.0)
		if entry is Dictionary:
			var data: Dictionary = entry as Dictionary
			point = _grid_point(data.get("position", Vector3.ZERO))
			model = str(data.get("kind", data.get("model", model)))
			jitter = float(data.get("scale", jitter))
		else:
			point = _grid_point(entry)
		if track != null \
				and spline_distance(track, point) < ROAD_HALF + TILE_SIZE * 0.45:
			rejected += 1
			continue
		var scale: float = NATURE_SCALE * jitter
		if not batches.has(model):
			batches[model] = []
		(batches[model] as Array).append(_fit_transform(model, point,
			float(index) * 1.7, Vector3.ONE * scale, true))
		_add_foliage_collider(body, model, point, scale)
		placed += 1
	for model: String in batches:
		_batch_model(body, model, batches[model] as Array, "Nature_" + model,
			false, true)
	if rejected > 0:
		push_warning("TileKit.trees: skipped %d position(s) inside the barrier line." % rejected)
	return placed


## Overhead start/finish gantry across the road at `dist`. The two legs are
## solid on WORLD; the beam is above kart height. The gantry follows the road
## deck height like every other track-side prop.
static func gantry(parent: Node3D, spline: RefCounted, dist: float) -> int:
	if parent == null or spline == null:
		return 0
	var distance: float = _snap_distance(spline, dist)
	var frame: Dictionary = spline.sample(distance)
	var point: Vector3 = frame["position"]
	var right: Vector3 = frame["right"]
	var yaw: float = atan2(-right.z, right.x)
	var xform: Transform3D = _fit_transform(TileCatalog.LIGHT_GANTRY, point,
		yaw, Vector3.ONE * PROP_SCALE)
	var node := _emit_unique(parent, TileCatalog.LIGHT_GANTRY, xform,
		"Gantry_%d" % int(round(distance)))
	if node == null:
		return 0
	var body := _static_body(parent, "GantryCollision_%d" % int(round(distance)))
	_add_gantry_colliders(body, TileCatalog.LIGHT_GANTRY, xform, PROP_SCALE)
	return 1


## Plan distance from a world point to the centreline, or INF without a spline.
## Clearance is measured in plan view so a prop beside a raised road section is
## still judged against the racing surface it sits next to.
static func spline_distance(spline: RefCounted, point: Vector3) -> float:
	if spline == null:
		return INF
	if spline.has_method("plan_distance"):
		return float(spline.call("plan_distance", point))
	var hit: Dictionary = spline.closest(point)
	return float(hit.get("distance", INF))


## Road deck height at a world point, from the grid spline. 0 on a flat map.
static func ground_height(spline: RefCounted, point: Vector3) -> float:
	if spline == null:
		return 0.0
	var hit: Dictionary = spline.closest(point)
	return float((hit.get("point", Vector3.ZERO) as Vector3).y)


## Walk up from `node` looking for the spline KenneyTiles.build stored on the
## race root, so trees() can enforce barrier clearance without an extra arg.
static func _find_spline(node: Node) -> RefCounted:
	var current: Node = node
	while current != null:
		var stored: Variant = current.get_meta("kenney_spline", null)
		if stored is RefCounted:
			return stored as RefCounted
		current = current.get_parent()
	return null


# --------------------------------------------------------------------------
# sign helpers


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
# placement


## Point at `lateral` from the centreline. The height is the road deck's, so a
## prop on an elevated map sits on the terrain instead of at world zero.
static func _point_at(spline: RefCounted, distance: float,
		lateral: float) -> Vector3:
	var frame: Dictionary = spline.sample(distance)
	var position: Vector3 = frame["position"]
	var right: Vector3 = frame["right"]
	return position + right * lateral


## Rotates a placement about `axis` through `pivot`, so props can follow a
## sloped road instead of floating level over it.
static func _tilt(xform: Transform3D, pivot: Vector3, axis: Vector3,
		angle: float) -> Transform3D:
	if absf(angle) < 0.0001:
		return xform
	var turn := Basis(axis.normalized(), angle)
	return Transform3D(turn * xform.basis, pivot + turn * (xform.origin - pivot))


## Path arc position that a lap arc length maps to on a clearance path.
static func _path_position(path: Dictionary, lap_distance: float) -> float:
	var distances: PackedFloat32Array = path["distances"]
	var lengths: PackedFloat32Array = path["lengths"]
	if distances.size() < 2 or lengths.size() != distances.size():
		return 0.0
	var total: float = float(path["total_length"])
	var wanted: float = fposmod(lap_distance, maxf(
		float(distances[distances.size() - 1]), 0.001))
	for index in range(0, distances.size() - 1):
		var from: float = distances[index]
		var to: float = distances[index + 1]
		if to < from:
			continue
		if wanted >= from and wanted <= to:
			var t: float = 0.0 if to - from < 0.0001 \
				else (wanted - from) / (to - from)
			return lerpf(lengths[index], lengths[index + 1], t)
	return total


## Path length of a lap run, following the offset path rather than the lap.
static func _path_run_length(path: Dictionary, start: float, span: float,
		lap_total: float) -> float:
	var path_total: float = float(path["total_length"])
	if path_total <= 0.01:
		return 0.0
	var from: float = _path_position(path, start)
	var to: float = _path_position(path, fposmod(start + span, maxf(lap_total,
		0.001)))
	var run: float = fposmod(to - from, path_total)
	if run <= 0.01:
		run = path_total
	return run


## Point on a clearance path at a path arc length.
static func _path_point(path: Dictionary, distance: float) -> Vector3:
	var points: PackedVector3Array = path["points"]
	var lengths: PackedFloat32Array = path["lengths"]
	if points.is_empty():
		return Vector3.ZERO
	if points.size() < 2 or lengths.size() != points.size():
		return points[0]
	var total: float = float(path["total_length"])
	var wanted: float = fposmod(distance, maxf(total, 0.001))
	var low: int = 0
	var high: int = lengths.size() - 2
	while low < high:
		var mid: int = (low + high + 1) / 2
		if lengths[mid] <= wanted:
			low = mid
		else:
			high = mid - 1
	var span: float = lengths[low + 1] - lengths[low]
	var t: float = 0.0 if span < 0.0001 else (wanted - lengths[low]) / span
	return points[low].lerp(points[low + 1], clampf(t, 0.0, 1.0))


## Yaw that maps a road piece's local -Z (travel) onto the track forward.
static func _along_track_yaw(spline: RefCounted, distance: float) -> float:
	var frame: Dictionary = spline.sample(distance)
	var forward: Vector3 = frame["forward"]
	return atan2(-forward.x, -forward.z)


## Yaw that maps a model's local +X (long axis) onto the track forward.
static func _across_track_yaw(spline: RefCounted, distance: float) -> float:
	var frame: Dictionary = spline.sample(distance)
	var forward: Vector3 = frame["forward"]
	return atan2(-forward.z, forward.x)


static func _snap_distance(spline: RefCounted, distance: float) -> float:
	var total: float = maxf(float(spline.total_length), 0.001)
	return fposmod(round(distance / SNAP_STEP) * SNAP_STEP, total)


static func _snap_lateral(lateral: float) -> float:
	return round(lateral / TileCatalog.LATERAL_STEP) \
		* TileCatalog.LATERAL_STEP


## Nearest cell centre for a world point. Cell (column, row) has its centre at
## ((column + 0.5) * TILE, 0, (row + 0.5) * TILE). The caller's height is kept,
## so a theme can put a prop on an elevated cell by passing a Vector3.
static func _snap_point(point: Vector3) -> Vector3:
	var column: int = int(floor(point.x / TILE_SIZE))
	var row: int = int(floor(point.z / TILE_SIZE))
	return Vector3((float(column) + 0.5) * TILE_SIZE, point.y,
		(float(row) + 0.5) * TILE_SIZE)


static func _grid_point(entry: Variant) -> Vector3:
	if entry is Vector2i:
		var cell: Vector2i = entry
		return Vector3((float(cell.x) + 0.5) * TILE_SIZE, 0.0,
			(float(cell.y) + 0.5) * TILE_SIZE)
	if entry is Vector3:
		var world: Vector3 = entry
		return _snap_point(world)
	if entry is Array:
		var coords: Array = entry
		if coords.size() >= 2:
			return Vector3((float(coords[0]) + 0.5) * TILE_SIZE, 0.0,
				(float(coords[1]) + 0.5) * TILE_SIZE)
	return Vector3.ZERO


# --------------------------------------------------------------------------
# model plumbing


static func _fit_transform(model: String, at: Vector3, yaw: float,
		scale: Vector3, nature: bool = false) -> Transform3D:
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), at)
	var center: Vector2 = info["center"]
	var aabb: AABB = info["aabb"]
	var yaw_basis := Basis(Vector3.UP, yaw)
	var basis: Basis = yaw_basis * Basis.IDENTITY.scaled(scale)
	var center_m := Vector3(center.x * scale.x, 0.0, center.y * scale.z)
	var lift: float = -aabb.position.y * scale.y
	return Transform3D(basis, at - yaw_basis * center_m + Vector3.UP * lift)


static func _scaled_size(model: String, scale: Vector3,
		nature: bool = false) -> Vector3:
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		return Vector3(0.1, 0.1, 0.1)
	var aabb: AABB = info["aabb"]
	return aabb.size * scale


static func _emit_unique(parent: Node3D, model: String, xform: Transform3D,
		node_name: String) -> Node3D:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return null
	var packed: PackedScene = load(str(info["path"])) as PackedScene
	if packed == null:
		return null
	var node: Node3D = packed.instantiate() as Node3D
	if node == null:
		return null
	node.name = node_name
	node.transform = xform
	parent.add_child(node)
	return node


static func _batch_model(parent: Node3D, model: String, transforms: Array,
		node_name: String, cast_shadow: bool, nature: bool = false) -> void:
	if transforms.is_empty():
		return
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		return
	var parts: Array = info["parts"]
	for part_index in parts.size():
		var part: Dictionary = parts[part_index]
		var mesh: Mesh = part["mesh"] as Mesh
		var local: Transform3D = part["transform"]
		if mesh == null:
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = transforms.size()
		for index in transforms.size():
			var world: Transform3D = transforms[index]
			multi.set_instance_transform(index, world * local)
		var instance := MultiMeshInstance3D.new()
		instance.name = node_name if parts.size() == 1 \
			else "%s_%d" % [node_name, part_index]
		instance.multimesh = multi
		instance.cast_shadow = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)


# --------------------------------------------------------------------------
# colliders


static func _static_body(parent: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	return body


static func _add_box_shape(body: StaticBody3D, xform: Transform3D,
		size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	body.add_child(collision)


static func _add_cylinder_shape(body: StaticBody3D, point: Vector3,
		radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = point + Vector3.UP * (height * 0.5)
	body.add_child(collision)


static func _add_foliage_collider(body: StaticBody3D, model: String,
		point: Vector3, scale: float) -> void:
	if model.begins_with("rock_"):
		_add_box_shape(body, Transform3D(Basis.IDENTITY,
			point + Vector3.UP * (0.5 * scale)), Vector3(1.4, 1.0, 1.4) * scale)
		return
	if model.begins_with("plant_") or model == "grass":
		_add_cylinder_shape(body, point, 0.9 * scale, 1.2 * scale)
		return
	_add_cylinder_shape(body, point, 0.55 * scale, 4.0 * scale)


static func _add_gantry_colliders(body: StaticBody3D, model: String,
		xform: Transform3D, scale_factor: float) -> void:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return
	var aabb: AABB = info["aabb"]
	var center: Vector2 = info["center"]
	var height: float = aabb.size.y * scale_factor
	var thickness: float = 1.2
	var legs: Array[Vector3] = [
		xform * Vector3(aabb.position.x, 0.0, center.y),
		xform * Vector3(aabb.end.x, 0.0, center.y),
	]
	for leg: Vector3 in legs:
		_add_box_shape(body, Transform3D(Basis.IDENTITY,
			leg + Vector3.UP * (height * 0.5)),
			Vector3(thickness, height, thickness))
	_add_box_shape(body, Transform3D(Basis.IDENTITY,
		xform * Vector3(center.x, aabb.size.y * 0.9, center.y)),
		Vector3(aabb.size.x * scale_factor, 1.4, 1.4))


# --------------------------------------------------------------------------
# primitive tyres


static func _tyre_geometry() -> TorusMesh:
	if _tyre_mesh != null:
		return _tyre_mesh
	var mesh := TorusMesh.new()
	mesh.inner_radius = TYRE_RADIUS
	mesh.outer_radius = TYRE_RADIUS + TYRE_TUBE * 2.0
	mesh.rings = 12
	mesh.ring_segments = 8
	_tyre_mesh = mesh
	return _tyre_mesh


static func _tyre_paint() -> StandardMaterial3D:
	if _tyre_material != null:
		return _tyre_material
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_tyre_material = material
	return _tyre_material


static func _multimesh(mesh: Mesh, material: Material, transforms: Array,
		node_name: String, cast_shadow: bool, colours: Array = []) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	if not colours.is_empty() and colours.size() == transforms.size():
		multi.use_colors = true
	multi.instance_count = transforms.size()
	for index in transforms.size():
		var world: Transform3D = transforms[index]
		multi.set_instance_transform(index, world)
	if multi.use_colors:
		for index in colours.size():
			multi.set_instance_color(index, colours[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.material_override = material
	instance.cast_shadow = \
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
