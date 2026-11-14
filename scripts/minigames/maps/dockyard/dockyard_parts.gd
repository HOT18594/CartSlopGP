extends RefCounted
## Batching and collision adapter for the Dockyard Quay dressing.
##
## TileKit owns the measured Kenney footprints, the 16 m model scale and the
## MultiMesh batching, but its public helpers only cover barriers, stands,
## lights, signs, flags, tyres, trees and the pit-garage row. A dockyard also
## needs container blocks, quay fencing, pit offices, cranes and the mooring
## clutter, so this adapter calls those same TileKit plumbing functions instead
## of re-measuring a GLB or hand-building a mesh. Every body it creates is a
## TileKit WORLD body and every solid piece gets an explicit box collider: the
## kit GLBs carry zero CollisionShape3D nodes, as tile_catalog.gd records.
##
## The clearance helpers in this file are the map's safety net. A theme prop is
## only emitted after it has been measured against the real road edge, so the
## owner's invariant - nothing solid on the racing surface - is enforced before
## a collider ever reaches the scene.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")

## Metres per model unit, the same ratio the road and every TileKit prop use.
const PROP_SCALE: Vector3 = Vector3.ONE * TileKit.PROP_SCALE
## A solid prop must sit this far from the centreline. The barrier line takes
## BARRIER_CLEARANCE (8.02 m); a further 1.5 m keeps the big container blocks
## and grandstands behind the wall instead of grinding through it.
const SAFE_CLEARANCE: float = TileKit.BARRIER_CLEARANCE + 1.5

## Vertical layering ladder, in metres above the surface a layer stands on. A
## slab, a decal and the foot of a prop each get their own rung, so no two
## surfaces share a plane and the depth buffer has a winner at every distance.
## The rungs are centimetre scale on purpose: a bigger lift reads as a floating
## prop instead of a layered one.
const LAYER_DECK: float = 0.0
const LAYER_FOOT: float = 0.01
const LAYER_APRON: float = 0.02
const LAYER_DECAL: float = 0.03
## Concrete grey of the flat slabs this map builds from a primitive.
const SLAB_COLOUR: Color = Color("8d938d")

static var _slab_material: StandardMaterial3D = null


## The one concrete slab material the yard uses. It is created once and shared
## by every slab batch, and it states the cartoon policy outright: opaque, lit
## per pixel, writing depth. A locally built material must never inherit an
## alpha or unshaded mode it did not ask for - that is the see-through, flat
## look the owner reported.
static func slab_material() -> StandardMaterial3D:
	if _slab_material != null:
		return _slab_material
	var material := StandardMaterial3D.new()
	material.albedo_color = SLAB_COLOUR
	material.roughness = 0.96
	material.metallic = 0.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	_slab_material = material
	return _slab_material


## A static WORLD body owned by TileKit.
static func body(parent: Node3D, node_name: String) -> StaticBody3D:
	return TileKit._static_body(parent, node_name)


## Kenney footprint transform: plan-view centre snapped to `at`, bottom at Y 0.
static func fit(model: String, at: Vector3, yaw: float,
		scale: Vector3) -> Transform3D:
	return TileKit._fit_transform(model, at, yaw, scale)


## Nature-kit footprint transform, with the nature root's measured pivot.
static func fit_nature(model: String, at: Vector3, yaw: float,
		scale: Vector3) -> Transform3D:
	return TileKit._fit_transform(model, at, yaw, scale, true)


## Measured world size of a racing-kit model at `scale`.
static func size(model: String, scale: Vector3) -> Vector3:
	return TileKit._scaled_size(model, scale)


## Measured world size of a nature-kit model at `scale`.
static func size_nature(model: String, scale: Vector3) -> Vector3:
	return TileKit._scaled_size(model, scale, true)


## One MultiMesh per mesh part, shared by every instance. Returns the number of
## draw calls the batch adds, so a theme can report its budget.
static func batch(parent: Node3D, model: String, transforms: Array,
		node_name: String, shadow: bool = true) -> int:
	if transforms.is_empty():
		return 0
	var draw_calls: int = part_count(model)
	TileKit._batch_model(parent, model, transforms, node_name, shadow)
	return draw_calls


## Nature-kit variant of batch(): trees, logs, canoes and rocks live under the
## nature root, so the catalogue must measure them there.
static func batch_nature(parent: Node3D, model: String, transforms: Array,
		node_name: String, shadow: bool = false) -> int:
	if transforms.is_empty():
		return 0
	var draw_calls: int = part_count_nature(model)
	TileKit._batch_model(parent, model, transforms, node_name, shadow, true)
	return draw_calls


## Number of mesh parts a batching call will emit.
static func part_count(model: String) -> int:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return 0
	return (info["parts"] as Array).size()


## Number of mesh parts for a nature-kit model.
static func part_count_nature(model: String) -> int:
	var info: Dictionary = TileCatalog.model_info(model, true)
	if not bool(info.get("ok", false)):
		return 0
	return (info["parts"] as Array).size()


## A real WORLD box collider, rotated to the piece's yaw.
static func box(body_node: StaticBody3D, at: Vector3, yaw: float,
		dimensions: Vector3) -> void:
	TileKit._add_box_shape(body_node,
		Transform3D(Basis(Vector3.UP, yaw), at), dimensions)


## A WORLD cylinder collider, used by bollards and mooring posts.
static func cylinder(body_node: StaticBody3D, at: Vector3, radius: float,
		height: float) -> void:
	TileKit._add_cylinder_shape(body_node, at, radius, height)


## Nearest cell centre for a world point. The caller's height is kept.
static func snap(point: Vector3) -> Vector3:
	return TileKit._snap_point(point)


## Plan distance from a world point to the centreline.
static func track_distance(spline: RefCounted, point: Vector3) -> float:
	return TileKit.spline_distance(spline, point)


## True when a solid footprint `half_extent` wide clears the centreline by
## `clearance`. The plan distance is measured to the footprint centre, so the
## half extent is subtracted before the test.
static func clears(spline: RefCounted, point: Vector3, half_extent: float,
		clearance: float = SAFE_CLEARANCE) -> bool:
	return track_distance(spline, point) - half_extent >= clearance


## Yaw that turns a model's local +Z front towards `target`, in the flat plane.
static func face_yaw(point: Vector3, target: Vector3) -> float:
	var direction := Vector3(target.x - point.x, 0.0, target.z - point.z)
	if direction.length_squared() < 0.01:
		return 0.0
	direction = direction.normalized()
	return atan2(direction.x, direction.z)


## Yaw that runs a 16 m piece along the track at `distance`.
static func along_yaw(spline: RefCounted, distance: float) -> float:
	var forward: Vector3 = spline.sample(distance)["forward"]
	return atan2(-forward.x, -forward.z)


## A point at `lateral` metres right of travel at `distance`, on the road deck.
static func side_point(spline: RefCounted, distance: float,
		lateral: float) -> Vector3:
	var frame: Dictionary = spline.sample(distance)
	return frame["position"] + frame["right"] * lateral
