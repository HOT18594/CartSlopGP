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
## `dress_track` is the shared detail pass KenneyTiles.build calls once per race:
## a painted kerb line, evenly spaced advertising hoardings and a marker on every
## corner, merged into one vertex-coloured mesh. It carries no collider, so it is
## pure trackside detail and cannot narrow or catch the racing surface.
##
## Repeated props of the same model are batched into one MultiMesh per mesh
## part; one-off pieces (grandstands, gantries, overhead lights) are instantiated
## normally. Every solid piece carries a StaticBody3D collider on
## CollisionLayers.WORLD so it can never be driven through.
##
## `side` is +1 for the right-hand side of the direction of travel and -1 for
## the left, matching the old racing_kit helpers.
##
## Z-FIGHTING LADDER (the only stacking policy in the Kenney maps):
##   ground slab   Z_GROUND  -0.020 m   terrain, aprons, floors
##   road piece    Z_ROAD     0.000 m   every drivable Kenney slab
##   decal/paint   Z_DECAL   +0.012 m   painted lines, bands, overlaps
##   prop base     Z_PROP    +0.024 m   stands, garages, barriers, foliage
## A layer never nudges itself against a neighbour; it moves to its rung. Props
## are fitted with Z_PROP in `_fit_transform`, road cross arms use Z_DECAL in
## kenney_tiles.gd, and the deferred audit raises every unshaded transparent
## decal to DECAL_RENDER_PRIORITY so it draws after the road.
##
## MATERIAL POLICY: imported kit surfaces are forced back to OPAQUE, SHADED,
## DEPTH_DRAW_OPAQUE_ONLY by `sanitize_props`, unless the albedo texture really
## contains alpha (the two chain-link fence models do). Every prop helper calls
## the sanitiser as it instantiates, and a deferred audit covers props whose
## theme code instantiates GLBs directly. Counts print as `PROP AUDIT ...`.
##
## COLLIDER POLICY: `_add_model_colliders` tries a cheap convex hull (<= 64
## points), uses a trimesh for large/concave structures (stands, garages), and
## keeps an oriented AABB box for long thin repeated pieces (barriers, flags,
## screens). The old AABB box is now only the no-surface fallback.

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
const BANK_INSET: float = 5.0
const BANK_SPACING: float = 7.0
const BANK_MODELS: Array[String] = [
	"rock_largeA", "rock_largeB", "rock_tallA", "rock_largeF",
]
const TYRE_OFFSET: float = 2.0

## Trackside detail (detail only: no colliders, so it can never narrow the road).
## A painted kerb line sits on the kit's raised kerb at the lane edge; low
## advertising hoardings stand on the verge between the invisible kart barrier
## and the themed catch wall; a marker stands on the outside of every corner.
const DETAIL_META: String = "tile_kit_track_detail"
const DETAIL_HOLDER: String = "TrackDetail"
const KERB_LATERAL: float = ROAD_HALF + 0.32
const KERB_HALF_WIDTH: float = 0.20
const KERB_LIFT: float = TileCatalog.ROAD_SURFACE + 0.172
const HOARDING_LATERAL: float = ROAD_HALF + 2.05
const HOARDING_SPACING: float = 3.4
const HOARDING_WIDTH: float = 3.2
const HOARDING_HEIGHT: float = 1.25
const HOARDING_DEPTH: float = 0.16
const HOARDING_SINK: float = 0.12
const MARKER_LATERAL: float = ROAD_HALF + 2.45
const MARKER_HEIGHT: float = 2.30
const MARKER_SINK: float = 0.20
const DETAIL_RED: Color = Color("c23a2c")
const DETAIL_CREAM: Color = Color("fff6e3")
const DETAIL_PALETTE: Array[Color] = [
	Color("c23a2c"), Color("e8c34a"), Color("2e86ab"), Color("4fbf52"),
	Color("f26ca7"), Color("ff9f45"),
]

const FLAG_SCALE: float = TILE_SIZE * 0.65
const TYRE_RADIUS: float = 0.30
const TYRE_TUBE: float = 0.16
const TYRE_LEVELS: int = 4
const TYRE_LEVEL_STEP: float = 0.38
const TYRE_COLLIDER_RADIUS: float = 0.66

## Vertical epsilon ladder, in metres. See the stacking policy at the top.
const Z_GROUND: float = -0.020
const Z_ROAD: float = 0.000
const Z_DECAL: float = 0.012
const Z_PROP: float = 0.024
const LAYER_GROUND: int = 0
const LAYER_ROAD: int = 1
const LAYER_DECAL: int = 2
const LAYER_PROP: int = 3
## Render priority an unshaded transparent decal must carry.
const DECAL_RENDER_PRIORITY: int = 1

## A convex hull this small is cheaper than a triangle mesh. Above it the
## factory treats the surface as concave and builds a trimesh.
const COLLIDER_CONVEX_BUDGET: int = 64
const COLLIDER_STATS_META: String = "tile_kit_collider_stats"
const MATERIAL_STATS_META: String = "tile_kit_material_stats"
const SANITIZE_META: String = "tile_kit_sanitized"
const SANITIZE_SCHEDULED_META: String = "tile_kit_sanitize_scheduled"

## Model families whose hitbox must follow the art instead of wrapping it.
const TRIMESH_MODELS: Array[String] = [
	"grandStand", "pitsGarage", "pitsOffice", "crane", "container",
	"lightPost", "overheadLights", "camera",
]
## Long, thin or flat repeated pieces keep a deliberately cheap oriented box.
const SCREEN_MODELS: Array[String] = [
	"barrier", "billboard", "bannerTower", "flag", "fence", "rail", "sign",
]

static var _tyre_mesh: TorusMesh = null
static var _tyre_material: StandardMaterial3D = null
static var _material_cache: Dictionary = {}
static var _mesh_cache: Dictionary = {}
static var _shape_cache: Dictionary = {}
static var _decal_cache: Dictionary = {}
static var _detail_material_cache: StandardMaterial3D = null


# --------------------------------------------------------------------------
# material sanitiser
#
# Imported Kenney surfaces are supposed to be opaque and lit. A source texture
# is the only thing allowed to keep transparency: we inspect its actual alpha
# channel instead of guessing from the material name. The function is
# idempotent, caches the copied materials so a palette is never recoloured, and
# records its counters on the scene root for the deferred audit line.


## Vertical rung of the stacking ladder, in metres.
static func layer_y(layer: int) -> float:
	match layer:
		LAYER_GROUND:
			return Z_GROUND
		LAYER_ROAD:
			return Z_ROAD
		LAYER_DECAL:
			return Z_DECAL
		_:
			return Z_PROP


## Render priority an unshaded transparent decal must carry.
static func decal_render_priority() -> int:
	return DECAL_RENDER_PRIORITY


## Schedules one deferred audit on the scene root. Called by every prop helper
## and by KenneyTiles.build, so props a theme instantiates directly are still
## covered once the whole map exists.
static func schedule_prop_audit(parent: Node) -> void:
	var root: Node = _scene_root(parent)
	if root == null or root.has_meta(SANITIZE_SCHEDULED_META):
		return
	root.set_meta(SANITIZE_SCHEDULED_META, true)
	var audit := PropAudit.new()
	audit.name = "TileKitPropAudit"
	audit.target = root
	# Props are built inside a node's _ready, when that node may still be busy
	# adding children. Defer the audit node so it lands on the next idle frame.
	root.add_child.call_deferred(audit)


## Sanitises every Kenney-kit surface under `root`. `stats_root` is the scene
## root whose metadata accumulates the counters; it defaults to `root`.
## Returns {surfaces, changed, kept_alpha}.
static func sanitize_props(root: Node, stats_root: Node = null) -> Dictionary:
	var empty: Dictionary = {"surfaces": 0, "changed": 0, "kept_alpha": 0}
	if root == null:
		return empty
	var owner: Node = stats_root if stats_root != null else root
	var stats: Dictionary = _material_stats(owner)
	_sanitize_walk(root, stats)
	owner.set_meta(MATERIAL_STATS_META, stats)
	return stats.duplicate()


## Prints the measured prop audit for one scene root.
static func report_prop_audit(root: Node, decal_priority: int = 0) -> void:
	if root == null:
		return
	var materials: Dictionary = _material_stats(root)
	var colliders: Dictionary = _collider_stats(root)
	print("PROP AUDIT %s: materials changed %d/%d surface(s), texture alpha kept %d; decal priority raised %d; colliders hull=%d trimesh=%d oriented_box=%d fallback=%d" % [
		_audit_label(root), int(materials.get("changed", 0)),
		int(materials.get("surfaces", 0)), int(materials.get("kept_alpha", 0)),
		decal_priority, int(colliders.get("hull", 0)),
		int(colliders.get("trimesh", 0)),
		int(colliders.get("oriented_box", 0)),
		int(colliders.get("fallback", 0))])


## Gives unshaded transparent decals the decal rung's render priority. Ground,
## paint and prop surfaces are left alone: opaque materials ignore priority, and
## props are already opaque.
static func apply_decal_priority(root: Node) -> int:
	if root == null:
		return 0
	var stats: Dictionary = {"changed": 0}
	_decal_walk(root, stats)
	return int(stats.get("changed", 0))


static func _decal_walk(node: Node, stats: Dictionary) -> void:
	if not _under_prop_body(node) \
			and (node is MeshInstance3D or node is MultiMeshInstance3D):
		_decal_instance(node, stats)
	for child: Node in node.get_children():
		_decal_walk(child, stats)


static func _decal_instance(node: Node, stats: Dictionary) -> void:
	var mesh: Mesh = null
	var multi: MultiMesh = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	elif node is MultiMeshInstance3D:
		multi = (node as MultiMeshInstance3D).multimesh
		if multi != null:
			mesh = multi.mesh
	if mesh == null:
		return
	var geometry := node as GeometryInstance3D
	if geometry != null and geometry.material_override is BaseMaterial3D:
		var source := geometry.material_override as BaseMaterial3D
		var clean: BaseMaterial3D = _decal_material(source, stats)
		if clean != source:
			geometry.material_override = clean
		return
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for surface in mesh.get_surface_count():
			var material: Material = instance.get_surface_override_material(surface)
			if material == null:
				material = mesh.surface_get_material(surface)
			if not (material is BaseMaterial3D):
				continue
			var source := material as BaseMaterial3D
			var clean: BaseMaterial3D = _decal_material(source, stats)
			if clean != source:
				instance.set_surface_override_material(surface, clean)
	elif multi != null:
		var clean_mesh: Mesh = _priority_mesh(mesh, stats)
		if clean_mesh != mesh:
			multi.mesh = clean_mesh


static func _decal_material(source: BaseMaterial3D,
		stats: Dictionary) -> BaseMaterial3D:
	if source.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED \
			or source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
			or source.render_priority == DECAL_RENDER_PRIORITY:
		return source
	var key: int = source.get_instance_id()
	if _decal_cache.has(key):
		stats["changed"] = int(stats.get("changed", 0)) + 1
		return _decal_cache[key] as BaseMaterial3D
	var clean: BaseMaterial3D = source.duplicate() as BaseMaterial3D
	clean.render_priority = DECAL_RENDER_PRIORITY
	_decal_cache[key] = clean
	stats["changed"] = int(stats.get("changed", 0)) + 1
	return clean


static func _priority_mesh(mesh: Mesh, stats: Dictionary) -> Mesh:
	var copy: Mesh = null
	for surface in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(surface)
		if not (material is BaseMaterial3D):
			continue
		var source := material as BaseMaterial3D
		var clean: BaseMaterial3D = _decal_material(source, stats)
		if clean == source:
			continue
		if copy == null:
			copy = mesh.duplicate() as Mesh
		copy.surface_set_material(surface, clean)
	return copy if copy != null else mesh


static func _sanitize_walk(node: Node, stats: Dictionary) -> void:
	if node is MeshInstance3D or node is MultiMeshInstance3D:
		_sanitize_instance(node, stats)
	for child: Node in node.get_children():
		_sanitize_walk(child, stats)


static func _sanitize_instance(node: Node, stats: Dictionary) -> void:
	if node.has_meta(SANITIZE_META):
		return
	var mesh: Mesh = null
	var multi: MultiMesh = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	elif node is MultiMeshInstance3D:
		multi = (node as MultiMeshInstance3D).multimesh
		if multi != null:
			mesh = multi.mesh
	if mesh == null:
		return
	if not _is_kit_mesh(mesh) and not _under_prop_body(node):
		return
	var geometry := node as GeometryInstance3D
	if geometry != null and geometry.material_override != null:
		var override := geometry.material_override
		if override is BaseMaterial3D:
			var source := override as BaseMaterial3D
			_note_material(stats, source)
			var clean: BaseMaterial3D = _sanitize_material(source)
			if clean != source:
				geometry.material_override = clean
		node.set_meta(SANITIZE_META, true)
		return
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		for surface in mesh.get_surface_count():
			var material: Material = instance.get_surface_override_material(surface)
			if material == null:
				material = mesh.surface_get_material(surface)
			if not (material is BaseMaterial3D):
				continue
			var source := material as BaseMaterial3D
			_note_material(stats, source)
			var clean: BaseMaterial3D = _sanitize_material(source)
			if clean != source:
				instance.set_surface_override_material(surface, clean)
	elif multi != null:
		var clean_mesh: Mesh = _sanitized_mesh(mesh, stats)
		if clean_mesh != mesh:
			multi.mesh = clean_mesh
	node.set_meta(SANITIZE_META, true)


## Returns a sanitised copy of `mesh` only when at least one surface changes.
static func _sanitized_mesh(mesh: Mesh, stats: Dictionary) -> Mesh:
	var key: int = mesh.get_instance_id()
	var cached: Variant = _mesh_cache.get(key, null)
	if cached is Mesh:
		var existing: Mesh = cached as Mesh
		for surface in mesh.get_surface_count():
			var source: Material = mesh.surface_get_material(surface)
			if source is BaseMaterial3D:
				_note_material(stats, source as BaseMaterial3D)
		return existing
	var copy: Mesh = null
	for surface in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(surface)
		if not (material is BaseMaterial3D):
			continue
		var source := material as BaseMaterial3D
		_note_material(stats, source)
		var clean: BaseMaterial3D = _sanitize_material(source)
		if clean == source:
			continue
		if copy == null:
			copy = mesh.duplicate() as Mesh
		copy.surface_set_material(surface, clean)
	if copy == null:
		return mesh
	_mesh_cache[key] = copy
	return copy


## Opaque, per-pixel, ambient-lit copy of a source material. The palette is
## copied verbatim; only the render state is corrected.
static func _sanitize_material(source: BaseMaterial3D) -> BaseMaterial3D:
	var key: int = source.get_instance_id()
	if _material_cache.has(key):
		return _material_cache[key] as BaseMaterial3D
	if not _material_changed(source):
		_material_cache[key] = source
		return source
	var clean: BaseMaterial3D = source.duplicate() as BaseMaterial3D
	clean.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	clean.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	clean.disable_ambient_light = false
	# Only a texture with real alpha may stay transparent; everything else is
	# forced opaque so a prop can never be a see-through ghost.
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
			and not _texture_needs_alpha(source.albedo_texture):
		clean.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		clean.albedo_color.a = 1.0
	_material_cache[key] = clean
	return clean


static func _material_changed(source: BaseMaterial3D) -> bool:
	if source.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
		return true
	if source.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY:
		return true
	if source.disable_ambient_light:
		return true
	return source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
		and not _texture_needs_alpha(source.albedo_texture)


static func _note_material(stats: Dictionary, source: BaseMaterial3D) -> void:
	stats["surfaces"] = int(stats.get("surfaces", 0)) + 1
	if _material_changed(source):
		stats["changed"] = int(stats.get("changed", 0)) + 1
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
			and _texture_needs_alpha(source.albedo_texture):
		stats["kept_alpha"] = int(stats.get("kept_alpha", 0)) + 1


## True only when the texture carries non-opaque pixels. A missing or unreadable
## image is treated as alpha-bearing so the sanitiser can never erase a real cut
## out by guessing.
static func _texture_needs_alpha(texture: Texture2D) -> bool:
	if texture == null:
		return false
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return true
	if image.is_compressed() and image.decompress() != OK:
		return true
	return image.detect_alpha() != Image.ALPHA_NONE


static func _is_kit_mesh(mesh: Mesh) -> bool:
	return mesh.resource_path.contains(
		"res://assets/models/kenney_racing_kit/") \
		or mesh.resource_path.contains(
			"res://assets/models/kenney_nature_kit/")


## A visual parented under a StaticBody3D is a solid prop, even when its mesh is
## a primitive or a theme-built ArrayMesh. Ground planes and painted decals live
## under the map holder, not a body, so they keep their authored flat shading.
static func _under_prop_body(node: Node) -> bool:
	var current: Node = node.get_parent()
	while current != null:
		if current is StaticBody3D:
			return true
		if current.get_parent() is Window:
			return false
		current = current.get_parent()
	return false


## The map root: the topmost scene node below the SceneTree's Window. Staying
## below the window means the audit, its metadata and its one-per-frame guard
## are scoped to this race or sandbox instead of leaking between loaded maps.
static func _scene_root(node: Node) -> Node:
	var current: Node = node
	while current != null and current.get_parent() != null:
		if current.get_parent() is Window:
			break
		current = current.get_parent()
	return current


static func _audit_label(root: Node) -> String:
	var label: String = ""
	if root.has_meta("kenney_grid_stats"):
		var stats: Variant = root.get_meta("kenney_grid_stats")
		if stats is Dictionary:
			label = str((stats as Dictionary).get("theme", ""))
	return label if label != "" else str(root.name)


static func _material_stats(owner: Node) -> Dictionary:
	if owner.has_meta(MATERIAL_STATS_META):
		var raw: Variant = owner.get_meta(MATERIAL_STATS_META)
		if raw is Dictionary:
			var stats: Dictionary = raw
			stats["surfaces"] = int(stats.get("surfaces", 0))
			stats["changed"] = int(stats.get("changed", 0))
			stats["kept_alpha"] = int(stats.get("kept_alpha", 0))
			return stats
	return {"surfaces": 0, "changed": 0, "kept_alpha": 0}


static func _collider_stats(root: Node) -> Dictionary:
	if root.has_meta(COLLIDER_STATS_META):
		var raw: Variant = root.get_meta(COLLIDER_STATS_META)
		if raw is Dictionary:
			return raw as Dictionary
	return {"hull": 0, "trimesh": 0, "oriented_box": 0, "fallback": 0}


## The deferred pass: waits until the theme has finished building, then audits
## the whole race/sandbox root once and prints the measured counters.
class PropAudit extends Node:
	var target: Node = null

	func _ready() -> void:
		if not is_inside_tree():
			return
		await get_tree().process_frame
		if target == null or not is_instance_valid(target):
			queue_free()
			return
		TileKit.sanitize_props(target, target)
		var decals: int = TileKit.apply_decal_priority(target)
		TileKit.report_prop_audit(target, decals)
		queue_free()


# --------------------------------------------------------------------------
# barriers and tyres


## Red/white/wall barrier run along one edge of the track. The run follows the
## real road edge at a constant BARRIER_CLEARANCE from the centreline: straight
## cells give a straight wall, the outside of a corner gives a concentric arc,
## and the inside of a corner is mitred between the two neighbouring walls
## instead of being offset onto the racing surface. Each piece is a real wall
## section with its own oriented AABB collider on WORLD, laid along the path
## chord, so the wall is continuous and never chords across a corner. Distances
## snap to a quarter tile.
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
			var placed: Transform3D = _tilt(xform, centre, axis, pitch)
			transforms.append(placed)
			# (c) a long thin repeated piece: keep the cheap oriented box, but
			# size it from the model AABB instead of the barrier spec.
			_add_oriented_box(body, model, placed, false, Vector3(0.98, 1.0, 1.0))
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
	for point: Vector3 in box_samples(half):
		closest = minf(closest, spline_distance(spline, xform * point))
	if closest == INF:
		return
	report["pieces"] = int(report["pieces"]) + 1
	report["closest"] = minf(float(report["closest"]), closest)
	if closest < BARRIER_CLEARANCE - 0.02:
		report["offenders"] = int(report["offenders"]) + 1


## Eight corners plus the four face centres of a box, so the audit does not only
## look at the ends of a long barrier piece.
static func box_samples(half: Vector3) -> Array[Vector3]:
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
			point + Vector3.UP * (Z_PROP + TYRE_TUBE
				+ float(level) * TYRE_LEVEL_STEP)))
		colours.append(Color("121114") if level < TYRE_LEVELS - 1 \
			else Color("c23a2c"))
	var instance := _multimesh(_tyre_geometry(), _tyre_paint(), transforms,
		"TyreStack", false, colours)
	body.add_child(instance)
	var height: float = TYRE_TUBE * 2.0 + float(TYRE_LEVELS) * TYRE_LEVEL_STEP
	_add_cylinder_shape(body, point, TYRE_COLLIDER_RADIUS, height)
	return 1


# --------------------------------------------------------------------------
# trackside detail


## The shared trackside detail pass: a painted kerb line on both lane edges, low
## advertising hoardings on the verge and a marker on the outside of every
## corner. Everything is merged into one vertex-coloured mesh (one draw call)
## and carries no collider, so it can never narrow the racing surface. Called
## once by KenneyTiles.build; a theme can skip it with
## `race.set_meta("kenney_skip_track_detail", true)`.
##
## Returns {kerbs, hoardings, markers}.
static func dress_track(parent: Node3D, spline: RefCounted,
		theme_id: String = "") -> Dictionary:
	if parent == null or spline == null:
		return {}
	var root: Node = _scene_root(parent)
	if root == null:
		return {}
	if root.has_meta(DETAIL_META):
		var cached: Variant = root.get_meta(DETAIL_META)
		return cached as Dictionary if cached is Dictionary else {}
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var kerbs: int = _build_kerb_detail(spline, verts, normals, colors)
	var hoardings: int = _build_hoarding_detail(spline, verts, normals, colors)
	var markers: int = _build_corner_marker_detail(spline, verts, normals,
		colors)
	var stats: Dictionary = {
		"kerbs": kerbs, "hoardings": hoardings, "markers": markers,
	}
	if not verts.is_empty():
		var holder := Node3D.new()
		holder.name = DETAIL_HOLDER
		parent.add_child(holder)
		var mesh := ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _detail_material())
		var instance := MeshInstance3D.new()
		instance.name = "TrackDetail"
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(instance)
	root.set_meta(DETAIL_META, stats)
	print("TRACK DETAIL %s: %d kerb quads, %d hoardings, %d corner markers, %s" % [
		theme_id if theme_id != "" else "grid", kerbs, hoardings, markers,
		"1 batched draw" if not verts.is_empty() else "no geometry"])
	return stats


## A painted red/cream band on the kit's raised kerb along both lane edges. The
## band follows the true clearance path, so it never cuts inside a corner.
static func _build_kerb_detail(spline: RefCounted,
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> int:
	var quads: int = 0
	for side: float in [-1.0, 1.0]:
		var path: Dictionary = TileGeometry.clearance_path(spline, side,
			KERB_LATERAL, CLEARANCE_STEP)
		if not bool(path.get("ok", false)):
			continue
		var points: PackedVector3Array = path["points"] as PackedVector3Array
		if points.size() < 2:
			continue
		var travelled: float = 0.0
		for index in range(0, points.size() - 1):
			var a: Vector3 = points[index]
			var b: Vector3 = points[index + 1]
			var delta: Vector3 = b - a
			var length: float = delta.length()
			if length < 0.05:
				continue
			var tangent := Vector3(delta.x, 0.0, delta.z)
			if tangent.length_squared() < 0.000001:
				continue
			tangent = tangent.normalized()
			var across: Vector3 = tangent.cross(Vector3.UP).normalized()
			var a0: Vector3 = a + across * KERB_HALF_WIDTH \
				+ Vector3.UP * KERB_LIFT
			var a1: Vector3 = a - across * KERB_HALF_WIDTH \
				+ Vector3.UP * KERB_LIFT
			var b0: Vector3 = b + across * KERB_HALF_WIDTH \
				+ Vector3.UP * KERB_LIFT
			var b1: Vector3 = b - across * KERB_HALF_WIDTH \
				+ Vector3.UP * KERB_LIFT
			var color: Color = DETAIL_CREAM \
				if int(travelled / 2.4) % 2 == 0 else DETAIL_RED
			_append_detail_quad(verts, normals, colors, a0, b0, b1, a1,
				color)
			travelled += length
			quads += 1
	return quads


## Low hoarding boards on the verge, evenly repeated around the lap. Each board
## is a cream frame with a coloured inset, so the line reads as advertising even
## without a text texture.
static func _build_hoarding_detail(spline: RefCounted,
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> int:
	var placed: int = 0
	for side: float in [-1.0, 1.0]:
		var path: Dictionary = TileGeometry.clearance_path(spline, side,
			HOARDING_LATERAL, CLEARANCE_STEP)
		if not bool(path.get("ok", false)):
			continue
		var total: float = float(path["total_length"])
		if total < HOARDING_SPACING:
			continue
		var count: int = maxi(int(floor(total / HOARDING_SPACING)), 1)
		var step: float = total / float(count)
		for index in count:
			var at: float = float(index) * step + step * 0.5
			var point: Vector3 = _path_point(path, at)
			var ahead: Vector3 = _path_point(path, at + 0.6)
			var behind: Vector3 = _path_point(path, at - 0.6)
			var tangent := Vector3(ahead.x - behind.x, 0.0,
				ahead.z - behind.z)
			if tangent.length_squared() < 0.000001:
				continue
			tangent = tangent.normalized()
			var right: Vector3 = tangent.cross(Vector3.UP).normalized()
			var outward: Vector3 = right * side
			var base: float = point.y - HOARDING_SINK
			var centre := Vector3(point.x, base + HOARDING_HEIGHT * 0.5,
				point.z)
			var basis := Basis(tangent, Vector3.UP, right)
			_append_detail_box(verts, normals, colors,
				Transform3D(basis, centre),
				Vector3(HOARDING_WIDTH, HOARDING_HEIGHT, HOARDING_DEPTH),
				DETAIL_CREAM)
			var inset_centre: Vector3 = centre - outward \
				* (HOARDING_DEPTH * 0.5)
			_append_detail_box(verts, normals, colors,
				Transform3D(basis, inset_centre),
				Vector3(HOARDING_WIDTH - 0.22, HOARDING_HEIGHT - 0.22,
					HOARDING_DEPTH + 0.06),
				_detail_color(DETAIL_PALETTE, placed, DETAIL_RED))
			placed += 1
	return placed


## One striped marker on the outside of every corner, on the verge, well clear
## of the barrier clearance so it is pure trackside detail.
static func _build_corner_marker_detail(spline: RefCounted,
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> int:
	var tiles_value: Variant = spline.get("tiles")
	if not (tiles_value is Array):
		return 0
	var placed: int = 0
	for tile: Dictionary in tiles_value as Array:
		var tile_char: String = str(tile.get("tile", ""))
		if tile_char != "L" and tile_char != "R" and tile_char != "W":
			continue
		var centre: Vector3 = TileGeometry._cell_center(tile["cell"])
		var entry: int = int(tile.get("entry", 0))
		var exit: int = int(tile.get("exit", 2))
		var din: Vector3 = -TileGeometry._edge_3d(entry)
		var right: Vector3 = din.cross(Vector3.UP).normalized()
		var corner: Vector3 = centre \
			+ TileGeometry._edge_3d(entry) * (TILE_SIZE * 0.5) \
			+ TileGeometry._edge_3d(exit) * (TILE_SIZE * 0.5)
		var side_out: float = -1.0 if (corner - centre).dot(right) > 0.0 \
			else 1.0
		var mid: float = (float(tile.get("from", 0.0)) \
			+ float(tile.get("to", 0.0))) * 0.5
		var frame: Dictionary = spline.sample(mid)
		var origin: Vector3 = frame["position"]
		var point: Vector3 = origin \
			+ (frame["right"] as Vector3) * (MARKER_LATERAL * side_out)
		if spline_distance(spline, point) < ROAD_HALF + 1.0:
			continue
		var base: float = origin.y - MARKER_SINK
		var segment: float = MARKER_HEIGHT / 3.0
		for band in 3:
			_append_detail_box(verts, normals, colors,
				Transform3D(Basis.IDENTITY, Vector3(point.x,
					base + segment * (float(band) + 0.5), point.z)),
				Vector3(0.22, segment, 0.22),
				DETAIL_RED if band % 2 == 0 else DETAIL_CREAM)
		_append_detail_box(verts, normals, colors,
			Transform3D(Basis.IDENTITY, Vector3(point.x,
				base + MARKER_HEIGHT + 0.28, point.z)),
			Vector3(0.62, 0.56, 0.62), DETAIL_CREAM)
		_append_detail_box(verts, normals, colors,
			Transform3D(Basis.IDENTITY, Vector3(point.x,
				base + MARKER_HEIGHT + 0.62, point.z)),
			Vector3(0.64, 0.12, 0.64), DETAIL_RED)
		placed += 1
	return placed


static func _detail_material() -> StandardMaterial3D:
	if _detail_material_cache != null:
		return _detail_material_cache
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_detail_material_cache = material
	return material


static func _detail_color(palette: Array[Color], index: int,
		fallback: Color) -> Color:
	if palette.is_empty():
		return fallback
	return palette[posmod(index, palette.size())]


static func _append_detail_quad(verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var normal: Vector3 = (b - a).cross(c - a)
	if normal.length_squared() > 0.0000001:
		normal = normal.normalized()
	else:
		normal = Vector3.UP
	_append_detail_tri(verts, normals, colors, a, b, c, normal, color)
	_append_detail_tri(verts, normals, colors, a, c, d, normal, color)


static func _append_detail_tri(verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, normal: Vector3,
		color: Color) -> void:
	for point: Vector3 in [a, b, c]:
		verts.append(point)
		normals.append(normal)
		colors.append(color)


static func _append_detail_box(verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray,
		xform: Transform3D, size: Vector3, color: Color) -> void:
	var half: Vector3 = size * 0.5
	var p: Array[Vector3] = []
	for ix: float in [-1.0, 1.0]:
		for iy: float in [-1.0, 1.0]:
			for iz: float in [-1.0, 1.0]:
				p.append(xform * Vector3(half.x * ix, half.y * iy,
					half.z * iz))
	_append_detail_quad(verts, normals, colors, p[0], p[1], p[3], p[2],
		color.darkened(0.10))
	_append_detail_quad(verts, normals, colors, p[4], p[6], p[7], p[5],
		color.darkened(0.06))
	_append_detail_quad(verts, normals, colors, p[0], p[4], p[5], p[1],
		color.darkened(0.16))
	_append_detail_quad(verts, normals, colors, p[2], p[3], p[7], p[6],
		color.darkened(0.16))
	_append_detail_quad(verts, normals, colors, p[0], p[2], p[6], p[4],
		color.darkened(0.20))
	_append_detail_quad(verts, normals, colors, p[1], p[5], p[7], p[3],
		color)


# --------------------------------------------------------------------------
# terrain


## A berm/bank run along the outside of the circuit, built from nature-kit rock
## blocks. It follows the same clearance path as the barriers, so a map can dress
## elevation cheaply and still guarantee the banks never reach the road: the
## inner face of every bank sits BARRIER_CLEARANCE from the centreline. Banks
## follow the spline height, so they climb with an elevated circuit, and each one
## carries a WORLD convex-hull collider.
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
		var bank_xform: Transform3D = _fit_transform(model, point,
			float(index) * 1.7, Vector3.ONE * bank_scale, true)
		if not batches.has(model):
			batches[model] = []
		(batches[model] as Array).append(bank_xform)
		# Rock blocks are convex enough for a real hull, so a bank rolls over
		# the rock instead of hitting a 4 m cube around it.
		_add_model_colliders(body, model, bank_xform, true, "auto")
		placed += 1
	for model: String in batches:
		_batch_model(body, model, batches[model] as Array, "Bank_" + model,
			false, true)
	return placed


# --------------------------------------------------------------------------
# structures


## A stepped grandstand with (covered) or without a roof, facing the track from
## `side`. The art itself is the WORLD trimesh collider.
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
	# (b) a stand is large and concave: its trimesh follows the steps and lets
	# a kart drive under the open frame instead of hitting one fat box.
	_add_model_colliders(body, model, node.transform, false, "trimesh")
	return 1


## A row of pit garages on the grid cell centres in `grid_positions`. Entries
## may be Vector2i(column, row), [column, row] or a world Vector3 that snaps to
## its cell. Garages are batched; each shell gets a trimesh collider so the open
## service bay stays drivable.
static func pit_building(parent: Node3D, grid_positions: Array) -> int:
	if parent == null or grid_positions.is_empty():
		return 0
	var body := _static_body(parent, "PitBuildings")
	var transforms: Array = []
	var placed: Array[Transform3D] = []
	for entry: Variant in grid_positions:
		var point: Vector3 = _grid_point(entry)
		var garage_xform: Transform3D = _fit_transform(TileCatalog.PIT_GARAGE,
			point, 0.0, Vector3.ONE * PROP_SCALE)
		transforms.append(garage_xform)
		placed.append(garage_xform)
	_batch_model(body, TileCatalog.PIT_GARAGE, transforms, "PitGarages", true)
	# (b) the garage is a concave shell: a trimesh keeps the open service bay
	# drivable, which an AABB around the footprint never could.
	for garage_xform: Transform3D in placed:
		_add_model_colliders(body, TileCatalog.PIT_GARAGE, garage_xform,
			false, "trimesh")
	return placed.size()


## Floodlight posts on the grid. `positions` entries are Vector3 cell points or
## {position, kind, yaw} dictionaries; kind `overhead` places a lit gantry.
static func lights(parent: Node3D, positions: Array) -> int:
	if parent == null or positions.is_empty():
		return 0
	var body := _static_body(parent, "Lights")
	var post_transforms: Array = []
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
		placed += 1
	if not post_transforms.is_empty():
		_batch_model(body, TileCatalog.LIGHT_POST, post_transforms,
			"LightPosts", true)
	# (b) a floodlight mast is large and concave; its trimesh catches the pole
	# and the lamp head instead of one full-height cylinder.
	for post_xform: Transform3D in post_transforms:
		_add_model_colliders(body, TileCatalog.LIGHT_POST, post_xform,
			false, "trimesh")
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
		var xform: Transform3D = _fit_transform(model, point, yaw,
			Vector3.ONE * scale)
		if not batches.has(model):
			batches[model] = []
		(batches[model] as Array).append(xform)
		colliders.append({"model": model, "xform": xform})
	for model: String in batches:
		_batch_model(body, model, batches[model] as Array, "Sign_" + model, true)
	for data: Dictionary in colliders:
		# Billboards and banner towers are screens: cheap oriented boxes. A
		# pylon falls through to the hull path.
		_add_model_colliders(body, str(data["model"]),
			data["xform"] as Transform3D, false, "auto")
	return positions.size()


## Flag poles. Entries are Vector3 cell points or {position, kind, yaw};
## kind is flagRed, flagGreen, flagCheckers or flagCheckersSmall.
static func flags(parent: Node3D, positions: Array) -> int:
	if parent == null or positions.is_empty():
		return 0
	var body := _static_body(parent, "Flags")
	var batches: Dictionary = {}
	var poles: Array[Dictionary] = []
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
		var pole_xform: Transform3D = _fit_transform(model, point, yaw,
			Vector3.ONE * FLAG_SCALE)
		if not batches.has(model):
			batches[model] = []
		(batches[model] as Array).append(pole_xform)
		poles.append({"model": model, "xform": pole_xform})
	for model: String in batches:
		_batch_model(body, model, batches[model] as Array, "Flag_" + model, true)
	# (c) a flag is a thin repeated screen: one oriented AABB box per pole,
	# rotated with the flag instead of an axis-aligned cube.
	for pole: Dictionary in poles:
		_add_oriented_box(body, str(pole["model"]),
			pole["xform"] as Transform3D)
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
		var xform: Transform3D = _fit_transform(model, point,
			float(index) * 1.7, Vector3.ONE * scale, true)
		if not batches.has(model):
			batches[model] = []
		(batches[model] as Array).append(xform)
		_add_foliage_collider(body, model, point, scale, xform)
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
	# Props live on their own rung of the Z ladder, never on the road/decal
	# plane they sit above.
	var lift: float = -aabb.position.y * scale.y + Z_PROP
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
	sanitize_props(node, _scene_root(parent))
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
		sanitize_props(instance, _scene_root(parent))
		parent.add_child(instance)


# --------------------------------------------------------------------------
# colliders


static func _static_body(parent: Node3D, node_name: String) -> StaticBody3D:
	schedule_prop_audit(parent)
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	return body


## Adds the best collision shape for one visual instance of a Kenney model.
##
## `policy` is "auto" (hull if cheap, else trimesh), "hull", "trimesh" or "box".
## Auto resolves by model family first: structures become trimeshes, screens and
## other long thin pieces stay oriented boxes, and the rest try a cheap hull.
## The shapes are baked from the mesh in model space and shared through a cache,
## so every instance of a garage reuses one trimesh instead of rebuilding it.
static func _add_model_colliders(body: StaticBody3D, model: String,
		xform: Transform3D, nature: bool = false,
		policy: String = "auto") -> void:
	var resolved: String = _resolve_policy(model, policy)
	if resolved == "box":
		_add_oriented_box(body, model, xform, nature)
		return
	var scale: Vector3 = xform.basis.get_scale()
	var built: Dictionary = _model_shapes(model, nature, scale, resolved)
	var shapes: Array = built.get("shapes", []) as Array
	if shapes.is_empty():
		# (d) no usable surfaces: the measured AABB is the last resort.
		_add_oriented_box(body, model, xform, nature, Vector3.ONE, "fallback")
		return
	var kind: String = str(built.get("kind", "fallback"))
	var basis: Basis = xform.basis.orthonormalized()
	for item: Variant in shapes:
		if not (item is Shape3D):
			continue
		var collision := CollisionShape3D.new()
		collision.shape = item as Shape3D
		collision.transform = Transform3D(basis, xform.origin)
		body.add_child(collision)
		_record_collider(body, kind)


## Oriented AABB box: sized from the mesh's measured footprint and rotated with
## the prop. This is the cheap route for barriers, flags and screens.
static func _add_oriented_box(body: StaticBody3D, model: String,
		xform: Transform3D, nature: bool = false,
		shrink: Vector3 = Vector3.ONE, kind: String = "oriented_box") -> void:
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		_add_box_shape(body, Transform3D(xform.basis.orthonormalized(),
			xform.origin + Vector3.UP * 0.5), Vector3.ONE)
		_record_collider(body, "fallback")
		return
	var aabb: AABB = info["aabb"]
	var scale: Vector3 = xform.basis.get_scale().abs()
	var size: Vector3 = aabb.size * scale * shrink
	if size.x <= 0.001 or size.y <= 0.001 or size.z <= 0.001:
		_add_box_shape(body, Transform3D(xform.basis.orthonormalized(),
			xform.origin + Vector3.UP * 0.5), Vector3.ONE)
		_record_collider(body, "fallback")
		return
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = Transform3D(xform.basis.orthonormalized(),
		xform * (aabb.position + aabb.size * 0.5))
	body.add_child(collision)
	_record_collider(body, kind)


## Chooses the factory route for a model. Family policy wins over the measured
## hull so a grandstand is never wrapped in one fat convex blob.
static func _resolve_policy(model: String, policy: String) -> String:
	if policy != "auto":
		return policy
	if _model_matches(model, TRIMESH_MODELS):
		return "trimesh"
	if _model_matches(model, SCREEN_MODELS):
		return "box"
	return "auto"


static func _model_matches(model: String, prefixes: Array[String]) -> bool:
	for prefix: String in prefixes:
		if model.begins_with(prefix):
			return true
	return false


## Cached shapes for (model, nature, scale, policy). Returns {kind, shapes}.
## Convex hulls must stay under COLLIDER_CONVEX_BUDGET points; the moment one
## part exceeds it the whole prop switches to a trimesh, because a hull of a
## concave prop fills the doorway a kart is meant to drive through.
static func _model_shapes(model: String, nature: bool, scale: Vector3,
		policy: String) -> Dictionary:
	var key: String = "%s|%s|%s|%s" % [model, str(nature),
		_scale_key(scale), policy]
	if _shape_cache.has(key):
		return _shape_cache[key] as Dictionary
	var info: Dictionary = TileCatalog.model_info(model, nature)
	var result: Dictionary = {"kind": "fallback", "shapes": []}
	if not bool(info.get("ok", false)):
		_shape_cache[key] = result
		return result
	var parts: Array = info["parts"] as Array
	if parts.is_empty():
		_shape_cache[key] = result
		return result
	if policy == "trimesh":
		var meshes: Array[Shape3D] = []
		for part: Dictionary in parts:
			var shape: Shape3D = _trimesh_shape(part, scale)
			if shape != null:
				meshes.append(shape)
		if not meshes.is_empty():
			result = {"kind": "trimesh", "shapes": meshes}
		_shape_cache[key] = result
		return result
	var hulls: Array[Shape3D] = []
	var cheap: bool = true
	for part: Dictionary in parts:
		var hull: Shape3D = _convex_shape(part, scale,
			COLLIDER_CONVEX_BUDGET)
		if hull == null:
			cheap = false
			break
		hulls.append(hull)
	if cheap and not hulls.is_empty():
		result = {"kind": "hull", "shapes": hulls}
		_shape_cache[key] = result
		return result
	var fallback_meshes: Array[Shape3D] = []
	for part: Dictionary in parts:
		var shape: Shape3D = _trimesh_shape(part, scale)
		if shape != null:
			fallback_meshes.append(shape)
	if not fallback_meshes.is_empty():
		result = {"kind": "trimesh", "shapes": fallback_meshes}
	_shape_cache[key] = result
	return result


## Convex hull of one mesh part, baked with the model scale, or null when the
## hull would exceed `budget` points.
static func _convex_shape(part: Dictionary, scale: Vector3,
		budget: int) -> Shape3D:
	var mesh: Mesh = part["mesh"] as Mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var hull := mesh.create_convex_shape(true, true)
	if hull == null or hull.points.size() < 4 or hull.points.size() > budget:
		return null
	var bake: Transform3D = _bake(part, scale)
	var points := PackedVector3Array()
	points.resize(hull.points.size())
	for index in hull.points.size():
		points[index] = bake * hull.points[index]
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


## Trimesh of one mesh part, baked with the model scale.
static func _trimesh_shape(part: Dictionary, scale: Vector3) -> Shape3D:
	var mesh: Mesh = part["mesh"] as Mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var concave := mesh.create_trimesh_shape()
	if concave == null:
		return null
	var faces: PackedVector3Array = concave.get_faces()
	if faces.size() < 3:
		return null
	var bake: Transform3D = _bake(part, scale)
	for index in faces.size():
		faces[index] = bake * faces[index]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	return shape


## Model scale applied to a part's own local mesh transform.
static func _bake(part: Dictionary, scale: Vector3) -> Transform3D:
	var local: Transform3D = part["transform"]
	return Transform3D(Basis.IDENTITY.scaled(scale), Vector3.ZERO) * local


static func _scale_key(scale: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [scale.x, scale.y, scale.z]


static func _record_collider(body: Node, kind: String) -> void:
	var root: Node = _scene_root(body)
	if root == null:
		return
	var stats: Dictionary = _collider_stats(root)
	stats[kind] = int(stats.get(kind, 0)) + 1
	root.set_meta(COLLIDER_STATS_META, stats)


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
	collision.position = point + Vector3.UP * (Z_PROP + height * 0.5)
	body.add_child(collision)


static func _add_foliage_collider(body: StaticBody3D, model: String,
		point: Vector3, scale: float, xform: Transform3D) -> void:
	if model.begins_with("rock_"):
		# A rock is convex; the hull follows its silhouette instead of the old
		# axis-aligned 4 m cube.
		_add_model_colliders(body, model, xform, true, "auto")
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
	var basis: Basis = xform.basis.orthonormalized()
	var legs: Array[Vector3] = [
		xform * Vector3(aabb.position.x, 0.0, center.y),
		xform * Vector3(aabb.end.x, 0.0, center.y),
	]
	# (c) a gantry is a thin repeated frame: keep oriented boxes, but rotate
	# them with the prop so the legs are not axis-aligned cubes.
	for leg: Vector3 in legs:
		_add_box_shape(body, Transform3D(basis,
			leg + basis * Vector3.UP * (height * 0.5)),
			Vector3(thickness, height, thickness))
		_record_collider(body, "oriented_box")
	_add_box_shape(body, Transform3D(basis,
		xform * Vector3(center.x, aabb.size.y * 0.9, center.y)),
		Vector3(aabb.size.x * scale_factor, 1.4, 1.4))
	_record_collider(body, "oriented_box")


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
