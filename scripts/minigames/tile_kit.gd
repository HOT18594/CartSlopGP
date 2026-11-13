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
## Repeated props of the same model are batched into one MultiMesh per mesh
## part; one-off pieces (grandstands, gantries, overhead lights) are instantiated
## normally. Every solid piece carries a StaticBody3D collider on
## CollisionLayers.WORLD so it can never be driven through.
##
## `side` is +1 for the right-hand side of the direction of travel and -1 for
## the left, matching the old racing_kit helpers.

const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

const TILE_SIZE: float = TileCatalog.TILE_SIZE
const ROAD_HALF: float = TileCatalog.ROAD_HALF
const SNAP_STEP: float = TileCatalog.SNAP_STEP
const PROP_SCALE: float = TileCatalog.PROP_SCALE
const NATURE_SCALE: float = TileCatalog.NATURE_SCALE

## Lateral offsets from the centreline, in metres. They are snapped again to
## half a metre so every prop lands on the same lattice.
const BARRIER_OFFSET: float = 0.9
const TYRE_OFFSET: float = 2.0
const STAND_OFFSET: float = TILE_SIZE * 0.95

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


## Red/white/wall barrier run along one edge of the track. The run is a real
## continuous wall on WORLD: each piece gets a box collider the size of the
## visible barrier. Distances snap to a quarter tile.
static func barrier_line(parent: Node3D, spline: RefCounted, from_dist: float,
		to_dist: float, side: float, kind: String = "barrierRed") -> int:
	if parent == null or spline == null:
		return 0
	var spec: Dictionary = TileCatalog.barrier_spec(kind)
	var length_m: float = float(spec.get("length", 0.25)) * TILE_SIZE
	if length_m <= 0.01:
		return 0
	var total: float = maxf(float(spline.total_length), 0.001)
	var direction: float = 1.0 if side >= 0.0 else -1.0
	var lateral: float = _snap_lateral(ROAD_HALF + BARRIER_OFFSET) * direction
	var start: float = _snap_distance(spline, from_dist)
	var span: float = fposmod(_snap_distance(spline, to_dist) - start, total)
	if span < length_m * 0.5:
		return 0
	var count: int = maxi(int(round(span / length_m)), 1)
	var model: String = str(spec.get("model", "barrierRed"))
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return 0
	var body := _static_body(parent, "Barrier_%s_%d" % [kind,
		int(round(start))])
	var size := Vector3(length_m * 0.98,
		float(spec.get("height", 0.1312)) * TILE_SIZE,
		float(spec.get("depth", 0.123)) * TILE_SIZE)
	var transforms: Array = []
	for index in count:
		var distance: float = start + float(index) * length_m
		var point: Vector3 = _point_at(spline, distance, lateral)
		var yaw: float = _across_track_yaw(spline, distance)
		transforms.append(_fit_transform(model, point, yaw,
			Vector3.ONE * PROP_SCALE))
		_add_box_shape(body,
			Transform3D(Basis(Vector3.UP, yaw),
				point + Vector3.UP * (size.y * 0.5)),
			size)
	_batch_model(body, model, transforms, "BarrierRun", true)
	return count


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
## solid on WORLD; the beam is above kart height.
static func gantry(parent: Node3D, spline: RefCounted, dist: float) -> int:
	if parent == null or spline == null:
		return 0
	var distance: float = _snap_distance(spline, dist)
	var frame: Dictionary = spline.sample(distance)
	var point: Vector3 = frame["position"]
	point.y = 0.0
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


## Distance from a world point to the centreline, or INF without a spline.
static func spline_distance(spline: RefCounted, point: Vector3) -> float:
	if spline == null:
		return INF
	var hit: Dictionary = spline.closest(point)
	return float(hit.get("distance", INF))


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


static func _point_at(spline: RefCounted, distance: float,
		lateral: float) -> Vector3:
	var frame: Dictionary = spline.sample(distance)
	var position: Vector3 = frame["position"]
	var right: Vector3 = frame["right"]
	var point: Vector3 = position + right * lateral
	point.y = 0.0
	return point


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
## ((column + 0.5) * TILE, 0, (row + 0.5) * TILE).
static func _snap_point(point: Vector3) -> Vector3:
	var column: int = int(floor(point.x / TILE_SIZE))
	var row: int = int(floor(point.z / TILE_SIZE))
	return Vector3((float(column) + 0.5) * TILE_SIZE, 0.0,
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
