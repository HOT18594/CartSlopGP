extends RefCounted
## Shared, texture-free prop plumbing for the Glacier Pass theme.
##
## Every Glacier module places scenery through this file so the three map rules
## are enforced once instead of in every pass:
##
##   * batching: repeated props are grouped by model and written into one
##     MultiMesh per mesh part, which is what keeps an 800-object alpine map
##     under ~120 draw calls;
##   * colliders: Kenney GLBs ship with zero CollisionShape3D nodes, so a solid
##     prop is registered on a StaticBody3D whose layer is
##     CollisionLayers.WORLD and whose box is sized from the model's measured
##     AABB;
##   * clearance: a solid position is measured in plan against the racing
##     centreline before it is accepted, and one inside SOLID_CLEARANCE is
##     refused and reported, so nothing solid can ever be planted on the racing
##     surface - the owner's main complaint, held as an invariant.
##
## Height: `fit()` puts a model's lowest measured point on `at.y`, exactly like
## tile_kit, so a prop on the flat snow (y = 0) never floats and a prop on the
## road deck follows the hill. Modules pass ground height or deck height
## explicitly; this file never guesses.

const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileGeometry := preload("res://scripts/minigames/tiles/kenney_tiles.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

const TILE: float = TileCatalog.TILE_SIZE
const ROAD_HALF: float = TileCatalog.ROAD_HALF
const NATURE_SCALE: float = TileCatalog.NATURE_SCALE

## Closest a solid prop centre may sit to the centreline. The barrier's inner
## face is BARRIER_CLEARANCE (8.02 m) from the centreline and a barrier is
## 16 m * 0.123 / 2 ~= 1 m deep, so 9.4 m clears the wall with a metre to
## spare and stays far outside the 6.02 m floor a kart audit uses.
const SOLID_CLEARANCE: float = TileKit.BARRIER_CLEARANCE + 1.4
## Path sampling for banks, rails and cliff bands, in metres.
const PATH_STEP: float = 0.75


# --------------------------------------------------------------------------
# batching
# --------------------------------------------------------------------------


## One StaticBody3D per prop family. Everything a module adds to it collides on
## WORLD and on nothing else.
static func body(parent: Node3D, node_name: String) -> StaticBody3D:
	var node := StaticBody3D.new()
	node.name = node_name
	node.collision_layer = CollisionLayers.WORLD
	node.collision_mask = 0
	parent.add_child(node)
	return node


## Box collider whose centre is `at` rotated by `yaw`.
static func box(collider: StaticBody3D, at: Vector3, size: Vector3,
		yaw: float = 0.0) -> void:
	if collider == null or size.x <= 0.01 or size.y <= 0.01 or size.z <= 0.01:
		return
	var shape := BoxShape3D.new()
	shape.size = size
	var node := CollisionShape3D.new()
	node.shape = shape
	node.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	collider.add_child(node)


## Upright cylinder collider standing on `at`.
static func cylinder(collider: StaticBody3D, at: Vector3, radius: float,
		height: float) -> void:
	if collider == null or radius <= 0.01 or height <= 0.01:
		return
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = at + Vector3.UP * (height * 0.5)
	collider.add_child(node)
	return


# --------------------------------------------------------------------------
# models
# --------------------------------------------------------------------------


## `scale` is metres per model unit, the same convention tile_kit uses. The
## model's plan centre is put on `at` and its lowest measured point is lifted
## to `at.y`, so a rock or tree stands on the surface it was given.
static func fit(model: String, at: Vector3, yaw: float, scale: float,
		nature: bool = false) -> Transform3D:
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		return Transform3D(Basis(Vector3.UP, yaw), at)
	var centre: Vector2 = info["center"]
	var aabb: AABB = info["aabb"]
	var yaw_basis := Basis(Vector3.UP, yaw)
	var basis: Basis = yaw_basis * Basis.IDENTITY.scaled(Vector3.ONE * scale)
	var centre_m := Vector3(centre.x * scale, 0.0, centre.y * scale)
	var lift: float = -aabb.position.y * scale
	return Transform3D(basis, at - yaw_basis * centre_m + Vector3.UP * lift)


## Plan footprint of a model at `scale`, in metres.
static func footprint(model: String, scale: float,
		nature: bool = false) -> Vector2:
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		return Vector2(0.5, 0.5)
	var aabb: AABB = info["aabb"]
	return Vector2(aabb.size.x, aabb.size.z) * scale


## Height of a model at `scale`, in metres.
static func height(model: String, scale: float, nature: bool = false) -> float:
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		return 0.5
	return (info["aabb"] as AABB).size.y * scale


## Scale that makes `model` exactly `metres` tall, clamped so a missing or
## degenerate GLB can never divide by zero.
static func scale_for_height(model: String, metres: float,
		nature: bool = false) -> float:
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		return NATURE_SCALE
	var base: float = maxf((info["aabb"] as AABB).size.y, 0.0001)
	return metres / base


## Longest plan axis of a model at `scale`, in metres. Rail and fence pieces are
## authored along one axis; `axis_yaw` returns the yaw that points it along a
## direction, so a run can be laid piece by piece without knowing the export.
static func longest_axis(model: String, scale: float,
		nature: bool = false) -> float:
	var plan: Vector2 = footprint(model, scale, nature)
	return maxf(plan.x, plan.y)


## Yaw that points a piece's longest plan axis along the horizontal direction
## `direction`, so consecutive pieces meet end to end.
static func axis_yaw(model: String, scale: float, direction: Vector3,
		nature: bool = false) -> float:
	var info: Dictionary = TileCatalog.model_info(model, nature)
	var along_x: bool = true
	if bool(info.get("ok", false)):
		var aabb: AABB = info["aabb"]
		along_x = aabb.size.x >= aabb.size.z
	if along_x:
		return atan2(-direction.z, direction.x)
	return atan2(direction.x, direction.z) + PI


## Batches `entries` ([{model, transform, nature?}]) into one MultiMesh per
## model part and returns the instances actually written. A model with several
## mesh parts costs one draw call per part; most kit pieces are a single part.
static func batch(parent: Node3D, entries: Array, node_name: String,
		cast_shadow: bool = true) -> int:
	if parent == null or entries.is_empty():
		return 0
	var groups: Dictionary = {}
	for entry: Variant in entries:
		if not (entry is Dictionary):
			continue
		var data: Dictionary = entry as Dictionary
		var model: String = str(data.get("model", ""))
		if model == "":
			continue
		var key: String = ("nature:" if bool(data.get("nature", false)) \
			else "racing:") + model
		if not groups.has(key):
			groups[key] = {"model": model,
				"nature": bool(data.get("nature", false)), "items": []}
		((groups[key] as Dictionary)["items"] as Array).append(
			data.get("transform", Transform3D.IDENTITY))
	var placed: int = 0
	for key: String in groups:
		var group: Dictionary = groups[key] as Dictionary
		var model: String = str(group["model"])
		var nature: bool = bool(group["nature"])
		var info: Dictionary = TileCatalog.model_info(model, nature)
		if not bool(info.get("ok", false)):
			continue
		var parts: Array = info["parts"] as Array
		var items: Array = group["items"] as Array
		if items.is_empty():
			continue
		for part_index in parts.size():
			var part: Dictionary = parts[part_index]
			var mesh: Mesh = part["mesh"] as Mesh
			var local: Transform3D = part["transform"]
			if mesh == null:
				continue
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = mesh
			multi.instance_count = items.size()
			for item_index in items.size():
				var world: Transform3D = items[item_index] as Transform3D
				multi.set_instance_transform(item_index, world * local)
			var instance := MultiMeshInstance3D.new()
			instance.name = node_name if parts.size() == 1 \
				else "%s_p%d" % [node_name, part_index]
			instance.multimesh = multi
			instance.cast_shadow = \
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(instance)
		placed += items.size()
	return placed


## A single model instance, for one-off pieces. Returns null when the GLB is
## missing so a caller never has to null-check the catalog itself.
static func single(parent: Node3D, model: String, xform: Transform3D,
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


## Longest run of consecutive straight tiles, in lap order: {distance, span}.
## Tiles are in lap order, so a run is a stretch where every tile keeps the
## heading; its centre and length are what the pit-lane split and the ski-lift
## line are laid along. Empty when no run is longer than one cell.
static func longest_straight(spline: RefCounted) -> Dictionary:
	if spline == null:
		return {}
	var tiles: Variant = spline.get("tiles")
	if not (tiles is Array) or (tiles as Array).is_empty():
		return {}
	var best: Dictionary = {}
	var run_from: float = 0.0
	var run_to: float = 0.0
	var in_run: bool = false
	for entry: Variant in tiles as Array:
		if not (entry is Dictionary):
			continue
		var tile: Dictionary = entry as Dictionary
		var kind: String = str(tile.get("tile", ""))
		var straight: bool = kind == "S" or kind == "P" or kind == "E" \
			or kind == "B" or kind == "J"
		var from: float = float(tile.get("from", 0.0))
		var to: float = float(tile.get("to", from))
		if straight:
			if not in_run:
				run_from = from
				in_run = true
			run_to = to
			continue
		if in_run and run_to - run_from > float(best.get("span", 0.0)):
			best = {"distance": (run_from + run_to) * 0.5,
				"span": run_to - run_from}
		in_run = false
	if in_run and run_to - run_from > float(best.get("span", 0.0)):
		best = {"distance": (run_from + run_to) * 0.5,
			"span": run_to - run_from}
	if float(best.get("span", 0.0)) < TILE:
		return {}
	return best


# --------------------------------------------------------------------------
# the racing surface
# --------------------------------------------------------------------------


## Plan distance from a world point to the racing centreline. Clearance is
## always measured in plan so a prop beside a raised deck is judged against the
## road it stands next to, not against its own height.
static func clearance(spline: RefCounted, point: Vector3) -> float:
	return TileKit.spline_distance(spline, point)


## Road deck height at an arc-length position, in metres.
static func deck(spline: RefCounted, distance: float) -> float:
	if spline == null:
		return 0.0
	var frame: Dictionary = spline.sample(distance)
	return (frame["position"] as Vector3).y


## Highest road deck on the lap, in metres.
static func max_deck(spline: RefCounted) -> float:
	if spline == null:
		return 0.0
	var total: float = maxf(float(spline.total_length), 1.0)
	var highest: float = 0.0
	for index in 64:
		highest = maxf(highest, deck(spline, total * float(index) / 64.0))
	return highest


## Refuses a solid prop that would stand on the racing surface. Returns true
## when the position is safe, so a caller can skip it instead of pushing a prop
## through the tarmac.
static func safe(spline: RefCounted, point: Vector3,
		label: String = "prop") -> bool:
	if spline == null:
		return true
	var distance: float = clearance(spline, point)
	if distance >= SOLID_CLEARANCE:
		return true
	push_error("GlacierProps: %s at %.1f, %.1f is %.2f m from the centreline, inside SOLID_CLEARANCE %.2f m." % [
		label, point.x, point.z, distance, SOLID_CLEARANCE])
	return false


## Publishes the closest approach of a finished prop family and fails a debug
## build when one of its positions is too close to the racing surface.
static func assert_clearance(label: String, points: Array,
		spline: RefCounted) -> float:
	var closest: float = INF
	for entry: Variant in points:
		if not (entry is Vector3):
			continue
		closest = minf(closest, clearance(spline, entry as Vector3))
	if closest == INF:
		return INF
	print("GLACIER CLEARANCE %s: %d position(s), closest %.2f m, limit %.2f m" % [
		label, points.size(), closest, SOLID_CLEARANCE])
	if closest < SOLID_CLEARANCE - 0.02 and OS.is_debug_build():
		push_error("GlacierProps: %s has a solid %.2f m from the centreline, inside %.2f m." % [
			label, closest, SOLID_CLEARANCE])
	return closest


# --------------------------------------------------------------------------
# elevation paths
# --------------------------------------------------------------------------


## A constant-clearance path around one side of the lap that follows the true
## road edge and the road deck height, so fences, banks and cliff bands climb
## with the hill. Returns KenneyTiles.clearance_path's dictionary.
static func constant_path(spline: RefCounted, side: float,
		lateral: float) -> Dictionary:
	if spline == null:
		return {"ok": false, "points": PackedVector3Array(),
			"lengths": PackedFloat32Array(), "total_length": 0.0}
	return TileGeometry.clearance_path(spline, side, lateral, PATH_STEP)


## Point on a clearance path at a path arc length.
static func path_point(path: Dictionary, distance: float) -> Vector3:
	var points: PackedVector3Array = path["points"]
	var lengths: PackedFloat32Array = path["lengths"]
	if points.size() < 2 or lengths.size() != points.size():
		return points[0] if not points.is_empty() else Vector3.ZERO
	var total: float = maxf(float(path["total_length"]), 0.001)
	var wanted: float = fposmod(distance, total)
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


## Direction of a clearance path at a path arc length, flattened to plan.
static func path_forward(path: Dictionary, distance: float) -> Vector3:
	var ahead: Vector3 = path_point(path, distance + 1.0)
	var behind: Vector3 = path_point(path, distance - 1.0)
	var direction: Vector3 = ahead - behind
	direction.y = 0.0
	if direction.length() < 0.001:
		return Vector3.FORWARD
	return direction.normalized()
