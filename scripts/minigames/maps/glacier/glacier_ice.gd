extends RefCounted
## Visible ice over the spans the glacier preset declares as `ice`.
##
## This is a surface decal, not a prop: the grid engine owns the road mesh and
## its collider, so the sheen is a flat, unshaded ribbon a few millimetres above
## the visible road top. It has no collision and casts no shadow.
##
## Height: the Kenney road pieces are placed with their lowest point on the deck
## the grid engine gives the cell, so the sheen is painted on the spline sample
## raised by the road slab's measured thickness. On a flat map that is the old
## fixed y; on the alpine descent it follows the hill, which is where the ice now
## lives. Raised cells (bump and jump) are skipped so the flat sheet never cuts
## through a crest.
##
## The ribbon follows the same spline the road uses and the spans come from
## GlacierSurface, so the visual can never disagree with the grip model.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const KenneyTiles := preload("res://scripts/minigames/tiles/kenney_tiles.gd")
const GlacierSurface := preload("res://scripts/minigames/maps/glacier/glacier_surface.gd")

const NODE_NAME: String = "GlacierIceSheen"
## Cold stylized glacial ice: rich translucent cyan-sapphire sheen with
## bright crystalline frost track highlights.
const SHEEN_COLOR := Color(0.52, 0.85, 1.0, 0.62)
const STEP: float = 3.0
const EDGE_INSET: float = 0.30
## The legacy grass_race dirt ribbon is painted at y = 0.04.
const FALLBACK_ROAD_TOP: float = 0.04
const FALLBACK_GRID_TOP: float = 0.32
const LIFT: float = 0.012


## Adds the ice sheen under `holder`. Returns {draws, spans, length, top}; a
## second call (or a preset with no ice) returns zeroed statistics.
static func build(holder: Node3D, race: Node3D, spline: RefCounted,
		preset: Dictionary) -> Dictionary:
	var stats: Dictionary = {"draws": 0, "spans": 0, "length": 0.0, "top": 0.0}
	if holder == null or spline == null:
		return stats
	if holder.has_node(NODE_NAME):
		return stats
	var spans: Array[Dictionary] = GlacierSurface.ice_spans(preset)
	if spans.is_empty():
		return stats
	var total: float = maxf(float(spline.total_length), 1.0)
	var top: float = _road_top(race)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var covered: float = 0.0
	for span: Dictionary in spans:
		var from_distance: float = float(span["from"]) * total
		var to_distance: float = float(span["to"]) * total
		if to_distance <= from_distance:
			to_distance += total
		covered += to_distance - from_distance
		_add_span(spline, from_distance, to_distance, top, verts, normals,
			indices)
	if indices.is_empty():
		return stats
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.name = NODE_NAME
	node.mesh = mesh
	node.material_override = _material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(node)
	stats["draws"] = 1
	stats["spans"] = spans.size()
	stats["length"] = covered
	stats["top"] = top + LIFT
	return stats


## Quad strip along one ice span, inset from the barrier so the snow edge still
## reads on both sides of the lane. Each quad is lifted off its own spline
## sample, so a span on the descent is painted on the slope and not in the air.
static func _add_span(spline: RefCounted, from_distance: float,
		to_distance: float, top: float, verts: PackedVector3Array,
		normals: PackedVector3Array, indices: PackedInt32Array) -> void:
	var span: float = to_distance - from_distance
	if span <= 0.01:
		return
	var steps: int = maxi(int(ceil(span / STEP)), 1)
	var half: float = TileKit.ROAD_HALF - EDGE_INSET
	for index in steps:
		var s0: float = from_distance + span * float(index) / float(steps)
		var s1: float = from_distance + span * float(index + 1) \
			/ float(steps)
		if _is_raised(spline, s0) or _is_raised(spline, s1):
			continue
		var f0: Dictionary = spline.sample(s0)
		var f1: Dictionary = spline.sample(s1)
		var c0: Vector3 = f0["position"] + Vector3.UP * (top + LIFT)
		var c1: Vector3 = f1["position"] + Vector3.UP * (top + LIFT)
		var r0: Vector3 = f0["right"]
		var r1: Vector3 = f1["right"]
		var base: int = verts.size()
		for point: Vector3 in [
				c0 - r0 * half, c0 + r0 * half,
				c1 - r1 * half, c1 + r1 * half]:
			verts.append(point)
			normals.append(Vector3.UP)
		indices.append(base)
		indices.append(base + 2)
		indices.append(base + 1)
		indices.append(base + 1)
		indices.append(base + 2)
		indices.append(base + 3)


## True on a bump, jump cell, or the carved broken-chasm cell immediately
## following a jump cell, so the ice sheet never stretches across open air!
static func _is_raised(spline: RefCounted, distance: float) -> bool:
	if not spline.has_method("tile_at"):
		return false
	var tile: Variant = spline.call("tile_at", distance)
	if not (tile is Dictionary):
		return false
	var tile_char: String = str((tile as Dictionary).get("tile", ""))
	if tile_char == "B" or tile_char == "J":
		return true
	var prev_tile: Variant = spline.call("tile_at", distance - 14.0)
	if prev_tile is Dictionary and str((prev_tile as Dictionary).get("tile", "")) == "J":
		return true
	return false


## Height of the visible road top. On any Kenney grid map (flat MultiMesh
## `Road_*` OR elevated merged `Road` MeshInstance3D), the lane surface sits at
## `KenneyTiles.ROAD_SURFACE`, and `LIFT = 0.012` places the sheen at
## `ROAD_SURFACE + 0.012 m`.
static func _road_top(race: Node3D) -> float:
	if race != null and _has_grid_road(race):
		return KenneyTiles.ROAD_SURFACE
	return FALLBACK_ROAD_TOP


## True when the race has the grid engine's road under it (either merged
## elevated `Road` MeshInstance3D or flat `Road_*` MultiMeshInstance3D).
static func _has_grid_road(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is MeshInstance3D and str(child.name) == "Road":
			return true
		var instance := child as MultiMeshInstance3D
		if instance != null and str(instance.name).begins_with("Road_"):
			return true
		if _has_grid_road(child):
			return true
	return false


static func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = SHEEN_COLOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	return material
