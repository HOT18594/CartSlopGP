extends RefCounted
## Ground and wet-weather pass for the Dockyard Quay theme.
##
## The whole map stands on one flat cartoon concrete apron with a faint 16 m
## expansion-joint grid, so the old meadow texture can never show through the
## quay. On top of it the pass paints the working details that make the apron
## read as a dock: a yellow quay edge line, hazard hatching at the service
## corners, wheel-stop marks and the cart-lane arrows. All the paint is one
## vertex-coloured mesh, so the whole layer costs a single draw call.
##
## The wet sector the track preset declares (surfaces: kind `wet`) is a field of
## flat painted puddles, not a continuous coloured ribbon: a dark wet centre with
## a pale cartoon rim, scattered across the full width of the lane and stretched
## into a few long streaks along the racing line. One MultiMesh for the lot.
##
## Nothing here is a solid prop: the apron is the floor (the race scene already
## owns the WORLD ground collider, and this pass adds one only when a grid scene
## boots without it) and the paint and puddles are millimetres above it.

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
const PAINT_Y: float = 0.028
const GROUND_COLOUR := Color("76828a")
const SEAM_COLOUR := Color("5f6a73")
const PAINT_YELLOW := Color("e8c34a")
const PAINT_WHITE := Color("e9edf0")
const PAINT_DARK := Color("3f474e")
const PUDDLE_INNER := Color("467482")
const PUDDLE_MID := Color("79a4af")
const PUDDLE_RIM := Color("d5e7ea")
const PUDDLE_LIFT: float = 0.013
## Fallback span if the registry loses its wet entry; matches track_defs.gd.
const WET_FALLBACK := Vector2(0.30, 0.58)
## Puddle field size. Density is deliberate: the painted pools read as a wet
## sector at chase-camera height without tinting the whole lane.
const PUDDLE_COUNT: int = 86
const STREAK_COUNT: int = 18
const PUDDLE_SEGMENTS: int = 12


## Builds the apron, its joint grid, the painted quay markings and the puddles.
static func build(parent: Node3D, spline: RefCounted,
		plan: RefCounted) -> Dictionary:
	var stats: Dictionary = {"objects": 0, "draws": 0, "paint": 0,
		"puddles": 0}
	if parent == null or spline == null or plan == null:
		return stats
	_apron(parent, plan, stats)
	if not plan.is_grid():
		# The current race scene still paints its ribbon with a photoreal dirt
		# material. A flat cartoon slab a few millimetres above it hides that
		# without touching the race's own mesh, so the fallback stays on-palette.
		_legacy_tarmac(parent, spline, stats)
	else:
		_paint(parent, plan, stats)
	_wet_puddles(parent, spline, plan, stats)
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
# painted quay markings


## A single vertex-coloured paint mesh: quay edge line, hazard hatching on the
## four service corners and wheel-stop ticks down the outer band. Zero
## thickness, so it is paint and not a solid prop.
static func _paint(parent: Node3D, plan: RefCounted, stats: Dictionary) -> void:
	var verts := PackedVector3Array()
	var colours := PackedColorArray()
	var marks: int = 0
	var min_x: float = 0.6 * TileKit.TILE_SIZE
	var max_x: float = (float(plan.cols) - 0.6) * TileKit.TILE_SIZE
	var min_z: float = 0.6 * TileKit.TILE_SIZE
	var max_z: float = (float(plan.rows) - 0.6) * TileKit.TILE_SIZE
	# A continuous yellow safety line just inside the apron edge.
	_add_rect(verts, colours, Vector3(min_x, PAINT_Y, min_z),
		Vector3(max_x, PAINT_Y, min_z), 0.30, PAINT_YELLOW, false)
	_add_rect(verts, colours, Vector3(min_x, PAINT_Y, max_z),
		Vector3(max_x, PAINT_Y, max_z), 0.30, PAINT_YELLOW, false)
	_add_rect(verts, colours, Vector3(min_x, PAINT_Y, min_z),
		Vector3(min_x, PAINT_Y, max_z), 0.30, PAINT_YELLOW, true)
	_add_rect(verts, colours, Vector3(max_x, PAINT_Y, min_z),
		Vector3(max_x, PAINT_Y, max_z), 0.30, PAINT_YELLOW, true)
	marks += 4
	# Hazard hatching in the four service corners of the apron.
	for corner: Vector3 in [
			Vector3(min_x + 3.0, PAINT_Y, min_z + 3.0),
			Vector3(max_x - 3.0, PAINT_Y, min_z + 3.0),
			Vector3(min_x + 3.0, PAINT_Y, max_z - 3.0),
			Vector3(max_x - 3.0, PAINT_Y, max_z - 3.0)]:
		for stripe in 4:
			var offset: float = (float(stripe) - 1.5) * 0.85
			var centre: Vector3 = corner + Vector3(offset, 0.0, 0.0)
			_add_rect(verts, colours, centre + Vector3(0.0, 0.0, -1.4),
				centre + Vector3(0.0, 0.0, 1.4), 0.28,
				PAINT_DARK if stripe % 2 == 0 else PAINT_YELLOW, true)
			marks += 1
	# Wheel-stop ticks and bay dividers down the outer band.
	for cell: Vector2i in plan.outer_band_cells():
		if (cell.x + cell.y) % 3 != 0:
			continue
		var point: Vector3 = plan.cell_point(cell)
		var horizontal: bool = cell.y == 0 or cell.y == plan.rows - 1
		var half := Vector3(1.3, 0.0, 0.0) if horizontal \
			else Vector3(0.0, 0.0, 1.3)
		_add_rect(verts, colours, point - half + Vector3.UP * PAINT_Y,
			point + half + Vector3.UP * PAINT_Y, 0.22, PAINT_WHITE,
			not horizontal)
		marks += 1
	if verts.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "QuayPaint"
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	stats["draws"] = int(stats["draws"]) + 1
	stats["objects"] = int(stats["objects"]) + marks
	stats["paint"] = marks


## Adds one flat quad lying on the apron. `along_z` makes the bar run north-
## south instead of east-west.
static func _add_rect(verts: PackedVector3Array, colours: PackedColorArray,
		start: Vector3, end: Vector3, half_width: float, colour: Color,
		along_z: bool) -> void:
	var normal := Vector3(0.0, 0.0, half_width) if not along_z \
		else Vector3(half_width, 0.0, 0.0)
	var a: Vector3 = start - normal
	var b: Vector3 = start + normal
	var c: Vector3 = end + normal
	var d: Vector3 = end - normal
	for point: Vector3 in [a, b, c, a, c, d]:
		verts.append(point)
		colours.append(colour)


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


## Flat painted puddles and wet streaks across the declared wet span. One
## MultiMesh, one draw call, no continuous coloured ribbon.
static func _wet_puddles(parent: Node3D, spline: RefCounted, plan: RefCounted,
		stats: Dictionary) -> void:
	var span: Vector2 = _wet_span()
	var total: float = maxf(float(spline.total_length), 0.001)
	var from_distance: float = total * clampf(span.x, 0.0, 0.999)
	var to_distance: float = total * clampf(span.y, 0.001, 1.0)
	if to_distance - from_distance < 4.0:
		return
	var road_top: float = plan.road_surface_y()
	var rng := RandomNumberGenerator.new()
	rng.seed = 8842
	var transforms: Array = []
	var wet_length: float = to_distance - from_distance
	for index in PUDDLE_COUNT:
		var t: float = (float(index) + 0.5) / float(PUDDLE_COUNT)
		var distance: float = from_distance + wet_length * (t
			+ rng.randf_range(-0.45, 0.45) / float(PUDDLE_COUNT))
		var frame: Dictionary = spline.sample(fposmod(distance, total))
		var lateral: float = rng.randf_range(-4.9, 4.9)
		var deck: Vector3 = frame["position"]
		var point: Vector3 = deck + frame["right"] * lateral + Vector3.UP \
			* (road_top + PUDDLE_LIFT)
		var scale: Vector2 = Vector2(rng.randf_range(1.1, 3.4),
			rng.randf_range(0.65, 1.7))
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(scale.x, 1.0, scale.y))
		transforms.append(Transform3D(basis, point))
	# Long, thin streaks follow the racing line and sell the low-grip read.
	for index in STREAK_COUNT:
		var t: float = (float(index) + 0.5) / float(STREAK_COUNT)
		var distance: float = from_distance + wet_length * t
		var frame: Dictionary = spline.sample(fposmod(distance, total))
		var lateral: float = rng.randf_range(-3.6, 3.6)
		var deck: Vector3 = frame["position"]
		var point: Vector3 = deck + frame["right"] * lateral + Vector3.UP \
			* (road_top + PUDDLE_LIFT + 0.001)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(rng.randf_range(4.5, 8.5), 1.0, rng.randf_range(0.30,
				0.55)))
		transforms.append(Transform3D(basis, point))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = _puddle_mesh()
	multi.instance_count = transforms.size()
	for index in transforms.size():
		multi.set_instance_transform(index, transforms[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = "PaintedPuddles"
	instance.multimesh = multi
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	stats["draws"] = int(stats["draws"]) + 1
	stats["objects"] = int(stats["objects"]) + transforms.size()
	stats["puddles"] = transforms.size()


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


## One flat puddle: a dark wet centre, a mid ring and a pale cartoon rim.
static func _puddle_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	verts.append(Vector3.ZERO)
	colours.append(PUDDLE_INNER)
	for index in PUDDLE_SEGMENTS:
		var angle: float = TAU * float(index) / float(PUDDLE_SEGMENTS)
		var wobble: float = 1.0 + 0.08 * sin(float(index) * 2.7)
		verts.append(Vector3(cos(angle) * 0.62 * wobble, 0.0,
			sin(angle) * 0.62 * wobble))
		colours.append(PUDDLE_MID)
	for index in PUDDLE_SEGMENTS:
		var angle: float = TAU * float(index) / float(PUDDLE_SEGMENTS)
		var wobble: float = 1.0 + 0.13 * sin(float(index) * 1.9 + 0.6)
		verts.append(Vector3(cos(angle) * wobble, 0.0, sin(angle) * wobble))
		colours.append(PUDDLE_RIM)
	for index in PUDDLE_SEGMENTS:
		var next: int = (index + 1) % PUDDLE_SEGMENTS
		indices.append(0)
		indices.append(1 + index)
		indices.append(1 + next)
	for index in PUDDLE_SEGMENTS:
		var next: int = (index + 1) % PUDDLE_SEGMENTS
		var inner_a: int = 1 + index
		var inner_b: int = 1 + next
		var rim_a: int = 1 + PUDDLE_SEGMENTS + index
		var rim_b: int = 1 + PUDDLE_SEGMENTS + next
		indices.append(inner_a)
		indices.append(rim_a)
		indices.append(inner_b)
		indices.append(inner_b)
		indices.append(rim_a)
		indices.append(rim_b)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _flat_material(colour: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material
