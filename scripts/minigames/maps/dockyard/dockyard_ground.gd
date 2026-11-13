extends RefCounted
## Ground and wet-weather pass for the Dockyard Quay theme.
##
## The whole map stands on one flat cartoon concrete apron with a faint 16 m
## expansion-joint grid, so the old meadow texture can never show through the
## quay. The wet sector the track preset declares (surfaces: kind `wet`) gets a
## single contiguous, slightly raised ribbon on the road, plus a handful of
## flat puddle decals so the grip change reads from the chase camera.
##
## Nothing here is a solid prop: the apron is the floor (the race scene already
## owns the WORLD ground collider, and this pass adds one only when a grid scene
## boots without it) and the wet patch is 1 cm of paint above the road.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

const GROUND_SIZE: float = 2200.0
## 2 cm over the race's own meadow plane: far enough apart to avoid z-fighting
## at the chase camera's distance, still under the legacy road at 4 cm.
const GROUND_Y: float = 0.02
## Cartoon asphalt over the legacy ribbon, above the old road (4 cm) and just
## below the old kerbs (4.8 cm), so neither shows through.
const TARMAC_Y: float = 0.047
const GROUND_COLOUR := Color("7d8b93")
const SEAM_COLOUR := Color("65707a")
const WET_COLOUR := Color("35707f")
const WET_EDGE_COLOUR := Color("86bfcc")
const PUDDLE_COLOUR := Color("a3d9e3")
const WET_EDGE: float = 0.8
const WET_LIFT: float = 0.012
const PUDDLE_LIFT: float = 0.018
## Fallback span if the registry loses its wet entry; matches track_defs.gd.
const WET_FALLBACK := Vector2(0.30, 0.58)


## Builds the apron, its joint grid, the wet ribbon and the puddle decals.
static func build(parent: Node3D, spline: RefCounted,
		plan: RefCounted) -> Dictionary:
	var stats: Dictionary = {"objects": 0, "draws": 0}
	if parent == null or spline == null or plan == null:
		return stats
	_apron(parent, plan, stats)
	if not plan.is_grid():
		# The current race scene still paints its ribbon with a photoreal dirt
		# material. A flat cartoon slab a few millimetres above it hides that
		# without touching the race's own mesh, so the fallback stays on-palette.
		_legacy_tarmac(parent, spline, stats)
	_wet_patch(parent, spline, plan, stats)
	return stats


# --------------------------------------------------------------------------
# apron


static func _apron(parent: Node3D, plan: RefCounted, stats: Dictionary) -> void:
	var ground := MeshInstance3D.new()
	ground.name = "DockyardApron"
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	ground.mesh = plane
	ground.position = plan.centre() + Vector3.UP * GROUND_Y
	ground.material_override = _flat_material(GROUND_COLOUR, 0.98)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ground)
	stats["draws"] = int(stats["draws"]) + 1
	if plan.is_grid():
		_seams(parent, plan, stats)
	_ground_collision(parent, plan)


## Faint expansion joints on the tile lattice: one MultiMesh, one draw call.
static func _seams(parent: Node3D, plan: RefCounted, stats: Dictionary) -> void:
	var tile: float = TileKit.TILE_SIZE
	var transforms: Array = []
	var width: float = float(plan.cols) * tile
	var depth: float = float(plan.rows) * tile
	var centre: Vector3 = plan.centre()
	for col in range(1, int(plan.cols)):
		transforms.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(0.16, 0.010, depth)),
			Vector3(float(col) * tile, GROUND_Y + 0.005, centre.z)))
	for row in range(1, int(plan.rows)):
		transforms.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(width, 0.010, 0.16)),
			Vector3(centre.x, GROUND_Y + 0.005, float(row) * tile)))
	if transforms.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = box
	multi.instance_count = transforms.size()
	for index in transforms.size():
		multi.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = "ApronJoints"
	instance.multimesh = multi
	instance.material_override = _flat_material(SEAM_COLOUR, 0.95)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	stats["draws"] = int(stats["draws"]) + 1


## The race scene already drops a 1400 m ground box. A bare grid scene does
## not, so the quay supplies the same floor only when the race is missing it.
static func _ground_collision(parent: Node3D, plan: RefCounted) -> void:
	var race: Node = parent.get_parent()
	if race != null and race.has_node("GroundCollision"):
		return
	var body := StaticBody3D.new()
	body.name = "DockyardGroundCollision"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(GROUND_SIZE, 2.0, GROUND_SIZE)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = plan.centre() + Vector3.DOWN * 1.0
	body.add_child(collision)
	parent.add_child(body)


# --------------------------------------------------------------------------
# legacy road overlay


## Flat asphalt slab over the legacy ribbon, one draw call.
static func _legacy_tarmac(parent: Node3D, spline: RefCounted,
		stats: Dictionary) -> void:
	var total: float = maxf(float(spline.total_length), 0.001)
	var steps: int = maxi(int(ceil(total / 2.0)), 8)
	var half: float = TileKit.ROAD_HALF + 0.02
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var indices := PackedInt32Array()
	for step in steps + 1:
		var distance: float = total * float(step) / float(steps)
		var frame: Dictionary = spline.sample(distance)
		var point: Vector3 = frame["position"]
		var right: Vector3 = frame["right"]
		verts.append(point - right * half + Vector3.UP * TARMAC_Y)
		verts.append(point + right * half + Vector3.UP * TARMAC_Y)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
	for step in steps:
		var a: int = step * 2
		indices.append(a)
		indices.append(a + 2)
		indices.append(a + 1)
		indices.append(a + 1)
		indices.append(a + 2)
		indices.append(a + 3)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "DockyardTarmac"
	instance.mesh = mesh
	var material := _flat_material(Color("4b5158"), 0.9)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	stats["draws"] = int(stats["draws"]) + 1


# --------------------------------------------------------------------------
# wet sector


## The contiguous wet ribbon and its puddles, raised just above the road.
static func _wet_patch(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var span: Vector2 = _wet_span()
	var total: float = maxf(float(spline.total_length), 0.001)
	var from_distance: float = total * clampf(span.x, 0.0, 0.999)
	var to_distance: float = total * clampf(span.y, 0.001, 1.0)
	if to_distance - from_distance < 4.0:
		return
	var surface: float = plan.road_surface_y() + WET_LIFT
	_ribbon(parent, spline, from_distance, to_distance, surface)
	stats["draws"] = int(stats["draws"]) + 1
	stats["objects"] = int(stats["objects"]) + 1
	_puddles(parent, spline, from_distance, to_distance, surface + PUDDLE_LIFT)
	stats["draws"] = int(stats["draws"]) + 1


## Wet lap-fraction span declared by the dockyard preset.
static func _wet_span() -> Vector2:
	var preset: Dictionary = TrackDefs.get_preset("dockyard")
	var raw: Variant = preset.get("surfaces", [])
	if raw is Array:
		for entry: Variant in raw as Array:
			if not (entry is Dictionary):
				continue
			var band: Dictionary = entry as Dictionary
			if str(band.get("kind", "")) != "wet":
				continue
			return Vector2(float(band.get("from", WET_FALLBACK.x)),
				float(band.get("to", WET_FALLBACK.y)))
	return WET_FALLBACK


## Three side-by-side strips in one vertex-coloured mesh: dark water with a
## pale edge on each side. One draw call, no transparency sorting.
static func _ribbon(parent: Node3D, spline: RefCounted, from_distance: float,
		to_distance: float, surface: float) -> void:
	var span: float = to_distance - from_distance
	var steps: int = maxi(int(ceil(span / 2.0)), 2)
	var width: float = 2.0 * (TileKit.ROAD_HALF + 0.75)
	var lanes: Array[Dictionary] = [
		{"low": -width * 0.5, "high": -width * 0.5 + WET_EDGE,
			"colour": WET_EDGE_COLOUR},
		{"low": -width * 0.5 + WET_EDGE, "high": width * 0.5 - WET_EDGE,
			"colour": WET_COLOUR},
		{"low": width * 0.5 - WET_EDGE, "high": width * 0.5,
			"colour": WET_EDGE_COLOUR},
	]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for lane: Dictionary in lanes:
		var base: int = verts.size()
		var low: float = float(lane["low"])
		var high: float = float(lane["high"])
		var colour: Color = lane["colour"]
		for step in steps + 1:
			var distance: float = from_distance \
				+ span * float(step) / float(steps)
			var frame: Dictionary = spline.sample(distance)
			var point: Vector3 = frame["position"]
			var right: Vector3 = frame["right"]
			verts.append(point + right * low + Vector3.UP * surface)
			verts.append(point + right * high + Vector3.UP * surface)
			norms.append(Vector3.UP)
			norms.append(Vector3.UP)
			colours.append(colour)
			colours.append(colour)
		for step in steps:
			var a: int = base + step * 2
			indices.append(a)
			indices.append(a + 2)
			indices.append(a + 1)
			indices.append(a + 1)
			indices.append(a + 2)
			indices.append(a + 3)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "WetSector"
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


## Flat pale discs scattered across the wet ribbon: one MultiMesh, one draw.
static func _puddles(parent: Node3D, spline: RefCounted, from_distance: float,
		to_distance: float, surface: float) -> void:
	var span: float = to_distance - from_distance
	var count: int = maxi(int(span / 9.0), 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	var transforms: Array = []
	for index in count:
		var distance: float = from_distance \
			+ span * (float(index) + 0.5) / float(count)
		var frame: Dictionary = spline.sample(distance)
		var lateral: float = rng.randf_range(-3.4, 3.4)
		var point: Vector3 = frame["position"] + frame["right"] * lateral \
			+ Vector3.UP * surface
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(rng.randf_range(1.4, 3.4), 1.0, rng.randf_range(0.9, 1.8)))
		transforms.append(Transform3D(basis, point))
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = plane
	multi.instance_count = transforms.size()
	for index in transforms.size():
		multi.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = "WetPuddles"
	instance.multimesh = multi
	instance.material_override = _flat_material(PUDDLE_COLOUR, 0.35)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


static func _flat_material(colour: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material
