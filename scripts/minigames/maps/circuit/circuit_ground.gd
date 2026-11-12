extends RefCounted
## Paved ground for the circuit theme: tarmac verge, pit lane and paddock.
##
## The race scene owns the racing surface itself and this theme never touches
## it. Everything here is the apron *around* the road: a Poly Haven asphalt_02
## verge outside the kerb line on both sides of the whole lap, a worn concrete
## pit lane on the inside of the start straight, an asphalt paddock behind it
## and the painted service-lane markings.
##
## The verge starts outside the race controller's invisible barrier
## (6.0 m from the centreline), so nothing added here can affect the racing
## surface. Each strip is one merged mesh with baked UVs and one WORLD
## collision body, so a whole lap of apron costs one draw call per strip.

const RaceKit := preload("res://scripts/minigames/racing_kit.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

const PBR_SHADER: String = "res://assets/materials/ground_pbr.gdshader"
const PBR_TEX: String = "res://assets/textures/polyhaven/"

## Mirrors grass_race.gd / racing_kit.gd: the road top and the painted edge
## strip the race controller already lays down (5.5 + 0.85 = 6.35 m).
const ROAD_Y: float = 0.04
const ROAD_HALF: float = 5.5

## Verge band, measured from the centreline. It begins where the race
## controller's painted edge ends so the two never overlap.
const VERGE_INNER: float = ROAD_HALF + 0.8
const VERGE_OUTER: float = 12.0

## Pit lane: a concrete strip on the inside (+right) of the start straight.
## LANE_FROM/LANE_TO are relative to the start line; the build wraps them.
const LANE_INNER: float = ROAD_HALF + 0.8
const LANE_OUTER: float = 15.4
const LANE_FROM: float = -94.0
const LANE_TO: float = -7.0
const LANE_FRONT: float = 10.7
const PADDOCK_OUTER: float = 26.0

const RIBBON_STEP: float = 2.0
## Metres between texture repeats. UVs are baked in metres so the asphalt
## grain keeps a constant size however long the strip is.
const UV_SCALE: float = 6.0
const PAINT_Y: float = ROAD_Y + 0.016

const WHITE := Color("f4f1e6")
const LANE_YELLOW := Color("e8c34a")

static var _asphalt: Material = null
static var _paint: Material = null


## Builds every paved strip and its markings under `holder`.
static func build(holder: Node3D, spline: RefCounted) -> void:
	if holder == null or spline == null:
		return
	var asphalt: Material = _asphalt_material()
	var concrete: Material = RaceKit.palette()["concrete"] as Material
	var total: float = maxf(spline.total_length, 0.001)
	for side: float in [-1.0, 1.0]:
		_ribbon(holder, spline, 0.0, total, VERGE_INNER * side,
			VERGE_OUTER * side, ROAD_Y + 0.004, asphalt,
			"TarmacVerge%s" % ("R" if side > 0.0 else "L"))
	var span: Array[float] = lane_span(spline)
	var lane_from: float = span[0]
	var lane_length: float = span[1]
	_ribbon(holder, spline, lane_from, lane_from + lane_length, LANE_INNER,
		LANE_OUTER, ROAD_Y + 0.010, concrete, "PitLaneConcrete")
	_ribbon(holder, spline, lane_from, lane_from + lane_length, LANE_OUTER,
		PADDOCK_OUTER, ROAD_Y + 0.006, asphalt, "PitPaddock")
	_paint_markings(holder, spline, lane_from, lane_length)


## The pit lane as {start arc length, length}. The span ends a few metres
## before the start line so the start gate and its lights stand on clean road.
static func lane_span(spline: RefCounted) -> Array[float]:
	var total: float = maxf(spline.total_length, 0.001)
	var from: float = fposmod(LANE_FROM, total)
	var to: float = fposmod(LANE_TO, total)
	var span: Array[float] = [from, fposmod(to - from, total)]
	return span


## True when `distance` is on (or within `margin` metres of) the pit lane.
static func in_lane(spline: RefCounted, distance: float,
		margin: float = 0.0) -> bool:
	var span: Array[float] = lane_span(spline)
	var offset: float = fposmod(distance - span[0], spline.total_length)
	return offset <= span[1] + margin or offset >= spline.total_length - margin


# --------------------------------------------------------------------------
# surfaces


## One paved strip with a solid WORLD face. `lateral_a` and `lateral_b` are
## sorted internally so both sides of the road get the same upward winding.
static func _ribbon(parent: Node3D, spline: RefCounted, from_distance: float,
		to_distance: float, lateral_a: float, lateral_b: float, height: float,
		material: Material, node_name: String) -> void:
	var span: float = to_distance - from_distance
	if span <= 0.01:
		return
	var steps: int = maxi(int(ceil(span / RIBBON_STEP)), 1)
	var step: float = span / float(steps)
	var low: float = minf(lateral_a, lateral_b)
	var high: float = maxf(lateral_a, lateral_b)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	for i in steps + 1:
		var s: float = from_distance + step * float(i)
		var frame: Dictionary = spline.sample(s)
		var base: Vector3 = (frame["position"] as Vector3) \
			+ Vector3.UP * height
		var right: Vector3 = frame["right"]
		verts.append(base + right * low)
		verts.append(base + right * high)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		uvs.append(Vector2(low / UV_SCALE, s / UV_SCALE))
		uvs.append(Vector2(high / UV_SCALE, s / UV_SCALE))
	for i in steps:
		var a: int = i * 2
		indices.append(a)
		indices.append(a + 2)
		indices.append(a + 1)
		indices.append(a + 1)
		indices.append(a + 2)
		indices.append(a + 3)
		faces.append_array([verts[a], verts[a + 2], verts[a + 1],
			verts[a + 1], verts[a + 2], verts[a + 3]])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	var body := StaticBody3D.new()
	body.name = node_name + "Collision"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = false
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)


# --------------------------------------------------------------------------
# service-lane paint


static func _paint_markings(holder: Node3D, spline: RefCounted,
		lane_from: float, lane_length: float) -> void:
	var verts := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	# Continuous edge lines: white against the road, yellow against the bays.
	_paint_strip(spline, lane_from, lane_from + lane_length, LANE_INNER + 0.25,
		0.15, WHITE, verts, colours, indices)
	_paint_strip(spline, lane_from, lane_from + lane_length, LANE_OUTER - 0.35,
		0.16, LANE_YELLOW, verts, colours, indices)
	# Dashed centre guide: the classic pit-lane read at speed.
	var cursor: float = 4.0
	while cursor < lane_length - 3.0:
		_paint_strip(spline, lane_from + cursor,
			lane_from + minf(cursor + 2.6, lane_length - 1.0), LANE_FRONT,
			0.11, WHITE, verts, colours, indices)
		cursor += 7.0
	# Four service boxes along the lane, in front of the garage doors.
	for i in 4:
		var bay: float = 13.0 + float(i) * 18.0
		if bay + 3.0 > lane_length:
			break
		_paint_box(spline, lane_from + bay, 4.4, 12.1, 14.9, WHITE, verts,
			colours, indices)
	var mesh: ArrayMesh = SceneryKit.mesh_from(verts, colours, indices, false)
	if mesh == null:
		return
	var paint := MeshInstance3D.new()
	paint.name = "PitLanePaint"
	paint.mesh = mesh
	paint.material_override = _paint_material()
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(paint)


static func _paint_strip(spline: RefCounted, from_distance: float,
		to_distance: float, lateral: float, width: float, colour: Color,
		verts: PackedVector3Array, colours: PackedColorArray,
		indices: PackedInt32Array) -> void:
	var span: float = to_distance - from_distance
	if span <= 0.01:
		return
	var steps: int = maxi(int(ceil(span / 2.0)), 1)
	var step: float = span / float(steps)
	var low: float = lateral - width * 0.5
	var high: float = lateral + width * 0.5
	for i in steps:
		var f0: Dictionary = spline.sample(from_distance + step * float(i))
		var f1: Dictionary = spline.sample(from_distance + step * float(i + 1))
		var p0: Vector3 = (f0["position"] as Vector3) + Vector3.UP * PAINT_Y
		var p1: Vector3 = (f1["position"] as Vector3) + Vector3.UP * PAINT_Y
		var r0: Vector3 = f0["right"]
		var r1: Vector3 = f1["right"]
		_add_quad(verts, colours, indices, p0 + r0 * low, p0 + r0 * high,
			p1 + r1 * low, p1 + r1 * high, colour)


static func _paint_cross(spline: RefCounted, distance: float, lateral_a: float,
		lateral_b: float, width: float, colour: Color,
		verts: PackedVector3Array, colours: PackedColorArray,
		indices: PackedInt32Array) -> void:
	var frame: Dictionary = spline.sample(distance)
	var point: Vector3 = (frame["position"] as Vector3) + Vector3.UP * PAINT_Y
	var right: Vector3 = frame["right"]
	var forward: Vector3 = frame["forward"]
	var low: float = minf(lateral_a, lateral_b)
	var high: float = maxf(lateral_a, lateral_b)
	var half: float = width * 0.5
	_add_quad(verts, colours, indices,
		point + right * low - forward * half,
		point + right * high - forward * half,
		point + right * low + forward * half,
		point + right * high + forward * half, colour)


static func _paint_box(spline: RefCounted, distance: float, length: float,
		lateral_a: float, lateral_b: float, colour: Color,
		verts: PackedVector3Array, colours: PackedColorArray,
		indices: PackedInt32Array) -> void:
	var half: float = length * 0.5
	var line: float = 0.09
	_paint_strip(spline, distance - half, distance + half, lateral_a, line,
		colour, verts, colours, indices)
	_paint_strip(spline, distance - half, distance + half, lateral_b, line,
		colour, verts, colours, indices)
	_paint_cross(spline, distance - half, lateral_a - line * 0.5,
		lateral_b + line * 0.5, line, colour, verts, colours, indices)
	_paint_cross(spline, distance + half, lateral_a - line * 0.5,
		lateral_b + line * 0.5, line, colour, verts, colours, indices)


static func _add_quad(verts: PackedVector3Array, colours: PackedColorArray,
		indices: PackedInt32Array, low0: Vector3, high0: Vector3,
		low1: Vector3, high1: Vector3, colour: Color) -> void:
	# Same winding as the road ribbon: low edge first, then the high edge, then
	# the next sample. The material is unshaded and cull-disabled, so the paint
	# never disappears when the camera drops behind the line.
	var base: int = verts.size()
	for vertex: Vector3 in [low0, high0, low1, high1]:
		verts.append(vertex)
		colours.append(colour)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 1)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base + 3)


# --------------------------------------------------------------------------
# materials


static func _asphalt_material() -> Material:
	if _asphalt != null:
		return _asphalt
	# asphalt_02 is the project's darker, cleaner race asphalt. asphalt_01 is
	# the worn meadow tarmac RacingKit uses; keeping the two apart is what makes
	# the fresh verge read as a track surface instead of more meadow.
	_asphalt = _pbr_material("asphalt_02", Color(0.80, 0.82, 0.86), 0.10, 0.035)
	return _asphalt


static func _pbr_material(prefix: String, tint: Color, detail: float,
		macro: float) -> Material:
	var diff: String = PBR_TEX + prefix + "_diff.jpg"
	var nor: String = PBR_TEX + prefix + "_nor.jpg"
	var rough: String = PBR_TEX + prefix + "_rough.jpg"
	# A source checkout that has not run the importer yet cannot load the JPGs.
	# Fall back to an honest flat colour instead of spraying resource errors.
	if not (ResourceLoader.exists(diff) and ResourceLoader.exists(nor)
			and ResourceLoader.exists(rough)):
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = tint
		fallback.roughness = 0.94
		fallback.metallic = 0.0
		return fallback
	var mat := ShaderMaterial.new()
	mat.shader = load(PBR_SHADER) as Shader
	mat.set_shader_parameter("albedo_tex", load(diff))
	mat.set_shader_parameter("normal_tex", load(nor))
	mat.set_shader_parameter("rough_tex", load(rough))
	mat.set_shader_parameter("uv_scale", 1.0)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("detail_strength", detail)
	mat.set_shader_parameter("macro_variation", macro)
	mat.set_shader_parameter("roughness_min", 0.60)
	return mat


static func _paint_material() -> Material:
	if _paint != null:
		return _paint
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_paint = mat
	return _paint
