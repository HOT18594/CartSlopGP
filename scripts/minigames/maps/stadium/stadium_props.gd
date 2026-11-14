extends RefCounted
## Batching, collision and clearance factory for the Stadium Circuit dressing.
##
## TileKit owns the measured Kenney footprints, the metre scale, the WORLD
## collider policy and the MultiMesh batching. Its public helpers only cover one
## prop at a time, so this module wraps that plumbing once and adds the pieces a
## stadium needs: continuous runs that follow the true road edge, a batched
## tyre stack made from a primitive torus (the racing kit ships no tyre model),
## and a clearance audit that measures every collider it emitted.
##
## Everything the theme places goes through here, so a single audit can prove
## the owner's invariant: no solid piece inside the racing surface. The kit GLBs
## carry no CollisionShape3D nodes (tile_catalog.gd records that), which is why
## every solid piece gets its collider from this file instead of from the art.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const TileGeometry := preload("res://scripts/minigames/tiles/kenney_tiles.gd")

## Metres per model unit for racing-kit props, matching the road scale.
const PROP_SCALE: float = TileKit.PROP_SCALE
## Metres per model unit for nature-kit props (trees, rocks, bridges).
const NATURE_SCALE: float = TileKit.NATURE_SCALE
## A barrier surface may never come nearer the centreline than this. TileKit
## owns the value; the audit here reuses it so the two can never disagree.
const BARRIER_CLEARANCE: float = TileKit.BARRIER_CLEARANCE
## A stand, garage, light or sign may come this close to the centreline. The
## drivable lane is ROAD_HALF wide, so this leaves a metre past the road edge.
const SOLID_CLEARANCE: float = TileKit.ROAD_HALF + 1.0
## Plan distance of the barrier centre line from the centreline. The barrier's
## visible inner face sits at BARRIER_CLEARANCE, so anything placed beyond
## BARRIER_FACE + a thickness is clear of the wall as well as of the road.
const BARRIER_FACE: float = TileKit.BARRIER_CLEARANCE + 2.2

const TYRE_RADIUS: float = 0.30
const TYRE_TUBE: float = 0.16
const TYRE_LEVELS: int = 4
const TYRE_LEVEL_STEP: float = 0.38
const TYRE_COLLIDER_RADIUS: float = 0.70
const TYRE_HEIGHT: float = (TYRE_TUBE * 2.0
	+ float(TYRE_LEVELS) * TYRE_LEVEL_STEP)
const TYRE_BLACK: Color = Color("141216")
const TYRE_RED: Color = Color("c23a2c")
const TYRE_WHITE: Color = Color("f5efe4")
## Distance fade of a view-limited batch, as a fraction of its cull distance.
const VIEW_FADE: float = 0.14

static var _tyre_mesh: TorusMesh = null
static var _tyre_material: StandardMaterial3D = null


# --------------------------------------------------------------------------
# bodies, footprints and batching


## A static WORLD body owned by TileKit, so every collider in the theme shares
## one layer policy.
static func body(parent: Node3D, node_name: String) -> StaticBody3D:
	return TileKit._static_body(parent, node_name)


## Kenney footprint transform: plan-view centre snapped to `at`, bottom at Y 0.
static func fit(model: String, at: Vector3, yaw: float,
		scale: Vector3, nature: bool = false) -> Transform3D:
	return TileKit._fit_transform(model, at, yaw, scale, nature)


## Measured world size of a model at `scale`.
static func size(model: String, scale: Vector3,
		nature: bool = false) -> Vector3:
	return TileKit._scaled_size(model, scale, nature)


## Mesh parts a batching call emits: one draw call each.
static func part_count(model: String, nature: bool = false) -> int:
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		return 0
	return (info["parts"] as Array).size()


## One MultiMesh per mesh part for every instance of `model`. Returns the draw
## calls it added so the theme can keep the budget honest. `view_end` is an
## optional cull distance in metres: the batches this call creates stop being
## drawn beyond it, which is how the far treeline is kept out of the browser
## build's frame when the camera is on the other side of the bowl.
static func batch(parent: Node3D, model: String, transforms: Array,
		node_name: String, shadow: bool = true, nature: bool = false,
		view_end: float = 0.0) -> int:
	if transforms.is_empty():
		return 0
	var draws: int = part_count(model, nature)
	var first: int = parent.get_child_count()
	TileKit._batch_model(parent, model, transforms, node_name, shadow, nature)
	if view_end > 0.0:
		_cull_far(parent, first, view_end)
	return draws


## Applies a visibility range to the batch nodes a single batching call added,
## i.e. the children between `first` and the current child count.
static func _cull_far(parent: Node3D, first: int, view_end: float) -> void:
	for index in range(first, parent.get_child_count()):
		var batch_node := parent.get_child(index) as GeometryInstance3D
		if batch_node == null:
			continue
		batch_node.visibility_range_end = view_end
		batch_node.visibility_range_end_margin = view_end * VIEW_FADE


## A real WORLD box collider, rotated to the piece's yaw and resting on `at`.
static func box(body_node: StaticBody3D, at: Vector3, yaw: float,
		dimensions: Vector3) -> void:
	TileKit._add_box_shape(body_node,
		Transform3D(Basis(Vector3.UP, yaw),
			at + Vector3.UP * (dimensions.y * 0.5)), dimensions)


## A WORLD cylinder collider standing on `at`.
static func cylinder(body_node: StaticBody3D, at: Vector3, radius: float,
		height: float) -> void:
	TileKit._add_cylinder_shape(body_node, at, radius, height)


## Footprint box for a batched model: the measured AABB squashed to the model's
## plan footprint, standing on `at`. `grow` pads the box for models whose art
## overhangs the base (grandstand roofs, banners).
static func model_body(body_node: StaticBody3D, model: String, at: Vector3,
		yaw: float, scale: Vector3, grow: float = 0.0,
		nature: bool = false) -> void:
	var dimensions: Vector3 = size(model, scale, nature)
	dimensions = Vector3(maxf(dimensions.x - grow, 0.6),
		maxf(dimensions.y, 0.6), maxf(dimensions.z - grow, 0.6))
	box(body_node, at, yaw, dimensions)


# --------------------------------------------------------------------------
# road-relative placement


## Frame at a lap distance: position (on the deck), forward and right vectors.
static func frame(spline: RefCounted, distance: float) -> Dictionary:
	if spline == null:
		return {"position": Vector3.ZERO, "forward": Vector3.FORWARD,
			"right": Vector3.RIGHT}
	return spline.sample(distance)


## Point `lateral` metres to one side of the centreline, on the road deck. Use
## this for props whose distance is large enough that the deck offset is safe
## (everything beyond the barrier line).
static func deck_point(spline: RefCounted, distance: float,
		lateral: float) -> Vector3:
	var f: Dictionary = frame(spline, distance)
	return (f["position"] as Vector3) + (f["right"] as Vector3) * lateral


## Point `lateral` metres to one side of the centreline, on flat ground. The
## stands, the tree band and the paddock sit on the meadow, not on the deck.
static func ground_point(spline: RefCounted, distance: float,
		lateral: float) -> Vector3:
	var point: Vector3 = deck_point(spline, distance, lateral)
	point.y = 0.0
	return point


## Yaw that turns a model's local -Z (its front, the way Kenney authors a stand)
## towards the centreline.
static func face_track_yaw(spline: RefCounted, point: Vector3) -> float:
	var target: Vector3 = spline.closest(point).get("point", Vector3.ZERO)
	var delta: Vector3 = target - point
	if delta.length_squared() < 0.01:
		return 0.0
	return atan2(delta.x, delta.z)


## Yaw that follows the lap, for pieces that run with the track (fences, rails,
## tyre walls) instead of facing it.
static func along_yaw(spline: RefCounted, distance: float,
		turn: float = 0.0) -> float:
	var f: Dictionary = frame(spline, distance)
	var forward: Vector3 = f["forward"]
	return atan2(-forward.z, forward.x) + turn


# --------------------------------------------------------------------------
# continuous runs on the true road edge


## Constant-clearance ring around the whole lap, built by the engine from the
## real road edge geometry: straights are lines, the outside of a corner is a
## concentric arc and the inside is a mitre, so a run placed on it can never cut
## across the racing surface. `lateral` is the plan distance from the centreline.
static func ring(spline: RefCounted, side: float,
		lateral: float) -> Dictionary:
	var path: Dictionary = TileGeometry.clearance_path(spline, side, lateral,
		TileKit.CLEARANCE_STEP)
	if bool(path.get("ok", false)):
		return path
	# Fall back to the sampled centreline offset: the audit below still measures
	# the result, so a degraded ring can never silently put a prop on the road.
	return _sampled_ring(spline, side, lateral)


static func _sampled_ring(spline: RefCounted, side: float,
		lateral: float) -> Dictionary:
	var direction: float = 1.0 if side >= 0.0 else -1.0
	var points := PackedVector3Array()
	var distances := PackedFloat32Array()
	var lengths := PackedFloat32Array()
	var step: float = TileKit.CLEARANCE_STEP
	var total: float = maxf(float(spline.total_length), 1.0)
	var count: int = maxi(int(ceil(total / step)), 4)
	for index in count:
		var distance: float = total * float(index) / float(count)
		var f: Dictionary = frame(spline, distance)
		var point: Vector3 = (f["position"] as Vector3) \
			+ (f["right"] as Vector3) * (lateral * direction)
		points.append(point)
		distances.append(distance)
		lengths.append(distance)
	points.append(points[0])
	distances.append(total)
	lengths.append(total)
	return {"ok": points.size() >= 4, "points": points,
		"distances": distances, "lengths": lengths,
		"total_length": total, "lateral": lateral}


## Path arc position that a lap distance maps to on a clearance ring.
static func ring_position(ring_path: Dictionary, lap_distance: float) -> float:
	var distances: PackedFloat32Array = ring_path["distances"]
	if distances.size() < 2:
		return 0.0
	var wanted: float = fposmod(lap_distance,
		maxf(float(distances[distances.size() - 1]), 0.001))
	for index in range(0, distances.size() - 1):
		var from: float = distances[index]
		var to: float = distances[index + 1]
		if to < from:
			continue
		if wanted >= from and wanted <= to:
			var t: float = 0.0 if to - from < 0.0001 \
				else (wanted - from) / (to - from)
			return lerpf((ring_path["lengths"] as PackedFloat32Array)[index],
				(ring_path["lengths"] as PackedFloat32Array)[index + 1], t)
	return float(ring_path["total_length"])


## Point on a ring at a path arc length.
static func ring_point(ring_path: Dictionary, path_distance: float) -> Vector3:
	var points: PackedVector3Array = ring_path["points"]
	var lengths: PackedFloat32Array = ring_path["lengths"]
	if points.size() < 2 or lengths.size() != points.size():
		return points[0] if not points.is_empty() else Vector3.ZERO
	var total: float = maxf(float(ring_path["total_length"]), 0.001)
	var wanted: float = fposmod(path_distance, total)
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


## Evenly spaced points on a ring between two lap distances, at `spacing` metres
## of path. Returns [{position, yaw, lap}] with the lap distance each point
## came from, so callers can skip a site.
static func ring_run(ring_path: Dictionary, from_lap: float, to_lap: float,
		spacing: float) -> Array:
	var entries: Array = []
	var start: float = ring_position(ring_path, from_lap)
	var end: float = ring_position(ring_path, to_lap)
	var path_total: float = maxf(float(ring_path["total_length"]), 0.1)
	var run: float = fposmod(end - start, path_total)
	if run <= 0.01:
		run = path_total
	var count: int = maxi(int(floor(run / spacing)), 1)
	var step: float = run / float(maxi(count, 1))
	for index in count:
		var path_distance: float = start + step * (float(index) + 0.5)
		var here: Vector3 = ring_point(ring_path, path_distance)
		var ahead: Vector3 = ring_point(ring_path, path_distance + 0.8)
		var delta: Vector3 = ahead - here
		entries.append({
			"position": here,
			"yaw": atan2(-delta.z, delta.x) if delta.length_squared() > 0.0001 \
				else 0.0,
			"path": path_distance,
		})
	return entries


## Half of a model's widest plan dimension, in metres: how far its footprint
## reaches from its placement point. A 16 m stand reaches 8 m.
static func half_extent(model: String, scale: Vector3,
		nature: bool = false) -> float:
	var footprint: Vector3 = size(model, scale, nature)
	return maxf(footprint.x, footprint.z) * 0.5


## True when a prop of `radius` metres around `point` clears the racing surface
## by SOLID_CLEARANCE. This is the filter that keeps a wide stand or garage out
## of the inside of a hairpin, where a constant-lateral ring folds back onto the
## road; every placement loops through it before any node is created.
static func site_ok(spline: RefCounted, point: Vector3, radius: float) -> bool:
	if spline == null:
		return true
	return TileKit.spline_distance(spline, point) \
		>= radius + SOLID_CLEARANCE


# --------------------------------------------------------------------------
# tyres


## N stacks of cartoon tyres, batched into one MultiMesh (the kit has no tyre
## model). Each stack gets a real cylinder collider on WORLD. The stack colour
## alternates so a long wall reads as red/white blocks instead of a black smear.
static func tyres(parent: Node3D, stacks: Array, node_name: String = "Tyres") -> int:
	if parent == null or stacks.is_empty():
		return 0
	var body := body(parent, node_name)
	var transforms: Array = []
	var colours: Array = []
	for stack_index in stacks.size():
		var entry: Dictionary = stacks[stack_index]
		var at: Vector3 = entry["position"]
		var tint: Color = TYRE_RED if stack_index % 3 == 1 else TYRE_WHITE \
			if stack_index % 3 == 2 else TYRE_BLACK
		for level in TYRE_LEVELS:
			transforms.append(Transform3D(Basis.IDENTITY,
				at + Vector3.UP * (TYRE_TUBE
					+ float(level) * TYRE_LEVEL_STEP)))
			colours.append(TYRE_BLACK if level < TYRE_LEVELS - 1 else tint)
		cylinder(body, at, TYRE_COLLIDER_RADIUS, TYRE_HEIGHT + 0.1)
	var instance: MultiMeshInstance3D = _coloured_multimesh(_tyre_geometry(),
		_tyre_paint(), transforms, colours, node_name)
	body.add_child(instance)
	return stacks.size()


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


static func _coloured_multimesh(mesh: Mesh, material: Material,
		transforms: Array, colours: Array,
		node_name: String) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.use_colors = true
	multi.instance_count = transforms.size()
	for index in transforms.size():
		multi.set_instance_transform(index, transforms[index])
		multi.set_instance_color(index, colours[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.material_override = material
	instance.cast_shadow = \
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return instance


# --------------------------------------------------------------------------
# clearance audit


## Measures every WORLD collider under `root` in plan view against the
## centreline and returns {pieces, closest, worst, offenders, at_least}, where
## `at_least` is the limit that was asked for. Overhead colliders (a gantry beam
## or a footbridge deck a kart drives under) are measured too, but reported
## separately as `overhead`, because they are not on the racing surface.
static func audit(root: Node, spline: RefCounted, limit: float,
		overhead_top: float = 3.2) -> Dictionary:
	var report: Dictionary = {"pieces": 0, "closest": INF, "worst": "none",
		"offenders": 0, "overhead": 0, "limit": limit, "at_least": false}
	_walk(root, spline, report, overhead_top)
	var closest: float = float(report["closest"])
	if closest == INF:
		closest = 0.0
	report["closest"] = closest
	report["at_least"] = closest >= limit - 0.02
	return report


static func _walk(node: Node, spline: RefCounted, report: Dictionary,
		overhead_top: float) -> void:
	for child: Node in node.get_children():
		var body_node := child as StaticBody3D
		if body_node != null:
			for shape_node: Node in body_node.get_children():
				var collision := shape_node as CollisionShape3D
				if collision != null:
					_measure(body_node, collision, spline, report,
						overhead_top)
		_walk(child, spline, report, overhead_top)


static func _measure(body_node: StaticBody3D, collision: CollisionShape3D,
		spline: RefCounted, report: Dictionary, overhead_top: float) -> void:
	var xform: Transform3D = world_transform(collision)
	var samples: Array[Vector3] = []
	var overhead: bool = false
	var box := collision.shape as BoxShape3D
	var cylinder_shape := collision.shape as CylinderShape3D
	if box != null:
		for point: Vector3 in TileKit.box_samples(box.size * 0.5):
			samples.append(point)
		overhead = xform.origin.y - box.size.y * 0.5 > overhead_top
	elif cylinder_shape != null:
		for step in 8:
			var angle: float = TAU * float(step) / 8.0
			samples.append(Vector3(cos(angle) * cylinder_shape.radius, 0.0,
				sin(angle) * cylinder_shape.radius))
		overhead = xform.origin.y - cylinder_shape.height * 0.5 > overhead_top
	else:
		return
	report["pieces"] = int(report["pieces"]) + 1
	if overhead:
		# A beam or bridge deck overhead is not on the racing surface: it is
		# counted but never measured for the clearance number.
		report["overhead"] = int(report["overhead"]) + 1
		return
	var closest: float = INF
	for point: Vector3 in samples:
		closest = minf(closest, TileKit.spline_distance(spline,
			xform * point))
	if closest == INF:
		return
	if closest < float(report["closest"]):
		report["closest"] = closest
		report["worst"] = str(body_node.name)
	if closest < float(report["limit"]) - 0.02:
		report["offenders"] = int(report["offenders"]) + 1


## Composes the parent chain, so a collider under the themed holder measures in
## world space even when a tool builds the map off-tree.
static func world_transform(node: Node3D) -> Transform3D:
	var xform: Transform3D = node.transform
	var current: Node = node.get_parent()
	while current is Node3D:
		xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


## Draw-call count: every GeometryInstance3D the theme added is one draw unit
## (a MultiMesh batch holds one node per mesh part).
static func count_geometry(node: Node) -> int:
	var count: int = 1 if node is GeometryInstance3D else 0
	for child: Node in node.get_children():
		count += count_geometry(child)
	return count
