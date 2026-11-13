extends RefCounted
## Batching and collision adapter for the Dockyard Quay dressing.
##
## TileKit owns the measured Kenney footprints, the 16 m model scale and the
## MultiMesh batching, but its public helpers only cover barriers, stands,
## lights, signs, flags, tyres, trees and the pit-garage row. A dockyard also
## needs container blocks, quay fencing, offices and a flat pit apron, so this
## adapter calls those same TileKit plumbing functions instead of re-measuring
## a GLB or hand-building a mesh. Every body it creates is a TileKit WORLD body
## and every solid piece gets an explicit box collider: the kit GLBs carry zero
## CollisionShape3D nodes, as tile_catalog.gd records.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")

## Metres per model unit, the same ratio the road and every TileKit prop use.
const PROP_SCALE: Vector3 = Vector3.ONE * TileKit.PROP_SCALE


## A static WORLD body owned by TileKit.
static func body(parent: Node3D, node_name: String) -> StaticBody3D:
	return TileKit._static_body(parent, node_name)


## Kenney footprint transform: plan-view centre snapped to `at`, bottom at Y 0.
static func fit(model: String, at: Vector3, yaw: float,
		scale: Vector3) -> Transform3D:
	return TileKit._fit_transform(model, at, yaw, scale)


## Measured world size of a model at `scale`.
static func size(model: String, scale: Vector3) -> Vector3:
	return TileKit._scaled_size(model, scale)


## One MultiMesh per mesh part, shared by every instance. Returns the number of
## draw calls the batch adds, so a theme can report its budget.
static func batch(parent: Node3D, model: String, transforms: Array,
		node_name: String, shadow: bool = true) -> int:
	if transforms.is_empty():
		return 0
	var draw_calls: int = part_count(model)
	TileKit._batch_model(parent, model, transforms, node_name, shadow)
	return draw_calls


## Number of mesh parts a batching call will emit.
static func part_count(model: String) -> int:
	var info: Dictionary = TileCatalog.model_info(model)
	if not bool(info.get("ok", false)):
		return 0
	return (info["parts"] as Array).size()


## A real WORLD box collider, rotated to the piece's yaw.
static func box(body_node: StaticBody3D, at: Vector3, yaw: float,
		dimensions: Vector3) -> void:
	TileKit._add_box_shape(body_node,
		Transform3D(Basis(Vector3.UP, yaw), at), dimensions)
