extends Node3D
## Procedural stunt park for the sandbox ("SLOP YARD").
##
## The whole drivable terrain is ONE heightfield surface: the visible mesh and
## the collision trimesh are generated from the same vertex grid, so there are
## no overlapping ground/lathe/pavement trimeshes to fling carts. The bowl is a
## smooth rolled depression, the drift ring is a low dome with broad marked
## entries that return to grade with NO vertical step, and the mesa, highline
## summit, ramps and causeway are all baked into that same surface. Only convex
## props, the solid perimeter wall, guardrails and the safety net use separate
## collision bodies. Everything decorative is visual only.

const FoliageBaker := preload("res://scripts/minigames/foliage_baker.gd")
const RealisticTree := preload("res://scripts/minigames/realistic_tree.gd")
const Backdrop := preload("res://scripts/systems/backdrop.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const BOOST_PAD_SCENE: String = "res://scenes/track/boost_pad.tscn"
const CONE_MODEL: String = "res://assets/models/kenney_car-kit/Models/GLB format/cone.glb"
const CRATE_MODEL: String = "res://assets/models/kenney_car-kit/Models/GLB format/box.glb"
const PBR_SHADER: String = "res://assets/materials/ground_pbr.gdshader"
const PBR_TEX: String = "res://assets/textures/polyhaven/"
const CHECKER_SHADER: String = "res://assets/materials/checker.gdshader"
const TITLE_FONT: String = "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"

const FIELD: float = 70.0
const WALL_H: float = 7.0
const WALL_T: float = 1.5
const RING_IN: float = 52.0
const RING_OUT: float = 58.0
const BOWL_CENTER := Vector2(-36.0, 16.0)
const BOWL_R: float = 12.0
const BOWL_DEPTH: float = 3.2
const DRIFT_CENTER := Vector2(-28.0, -28.0)
const DRIFT_TOP: float = 0.42
const DRIFT_BANK_IN: float = 4.5
const DRIFT_BANK_OUT: float = 9.5
const MESA_CENTER := Vector2(34.0, -16.0)
const MESA_H: float = 5.5
const MESA_TOP_R: float = 10.0
const MESA_FOOT_R: float = 15.0
const HL_CENTER := Vector2(12.0, -40.0)
const HL_TOP_R: float = 9.0
const HL_FOOT_R: float = 14.0
const DROP_CENTER := Vector2(18.0, -16.0)
const RAMP_HALF: float = 3.5
const RAMP_FOOT: float = 7.0
const CAUSE_HALF: float = 2.6
const CAUSE_FOOT: float = 5.0
const GRID: int = 100

var _grass_mat: ShaderMaterial
var _terrain_mat: ShaderMaterial
var _prop_material: PhysicsMaterial
var _asphalt_mat: StandardMaterial3D
var _concrete_mat: StandardMaterial3D
var _paint_mat: StandardMaterial3D
var _yellow_mat: StandardMaterial3D
var _dirt_mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 90421
	_make_materials()
	_terrain()
	_painted_marks()
	_jump_lane()
	_mesa()
	_highline()
	_slalom_furniture()
	_perimeter()
	_guardrails()
	_props()
	_scenery()
	_backdrop()
	_signs()


# --------------------------------------------------------------------------
# materials


func _make_materials() -> void:
	_grass_mat = _pbr("grass_diff", "grass_nor", "grass_rough", 14.0,
		Color(0.74, 0.96, 0.62), 0.08, 0.05)
	_dirt_mat = _pbr("dirt_diff", "dirt_nor", "dirt_rough", 6.0,
		Color(0.94, 0.78, 0.55), 0.10, 0.03)
	_asphalt_mat = StandardMaterial3D.new()
	_asphalt_mat.albedo_color = Color(0.30, 0.32, 0.36)
	_asphalt_mat.roughness = 0.95
	_asphalt_mat.vertex_color_use_as_albedo = true
	_concrete_mat = StandardMaterial3D.new()
	_concrete_mat.albedo_color = Color(0.62, 0.64, 0.67)
	_concrete_mat.roughness = 0.9
	_concrete_mat.vertex_color_use_as_albedo = true
	_paint_mat = StandardMaterial3D.new()
	_paint_mat.albedo_color = Color("fff6e3")
	_paint_mat.roughness = 0.8
	_yellow_mat = StandardMaterial3D.new()
	_yellow_mat.albedo_color = Color("ffd22e")
	_yellow_mat.roughness = 0.8
	# One textured surface for the whole park. Vertex colours carry the zone
	# palette; the grass PBR texture supplies the close-up detail that the old
	# flat-colour mesh was missing.
	_terrain_mat = _pbr("grass_diff", "grass_nor", "grass_rough", 0.26,
		Color(0.92, 0.95, 0.86), 0.10, 0.05)
	_terrain_mat.set_shader_parameter("use_vertex_color", true)


func _pbr(diff: String, nor: String, rough: String, uv_scale: float,
		tint: Color, detail: float, macro: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(PBR_SHADER) as Shader
	mat.set_shader_parameter("albedo_tex", load(PBR_TEX + diff + ".jpg"))
	mat.set_shader_parameter("normal_tex", load(PBR_TEX + nor + ".jpg"))
	mat.set_shader_parameter("rough_tex", load(PBR_TEX + rough + ".jpg"))
	mat.set_shader_parameter("uv_scale", uv_scale)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("detail_strength", detail)
	mat.set_shader_parameter("macro_variation", macro)
	mat.set_shader_parameter("roughness_min", 0.55)
	return mat


# --------------------------------------------------------------------------
# height field: one surface for both the mesh and the collision


func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _fade_out(d: float, a: float, b: float) -> float:
	if a >= b:
		if d <= a:
			return 1.0
		return 0.0
	return 1.0 - _smooth(clampf((d - a) / (b - a), 0.0, 1.0))


func _fade_in(d: float, a: float, b: float) -> float:
	if a >= b:
		if d >= b:
			return 1.0
		return 0.0
	return _smooth(clampf((d - a) / (b - a), 0.0, 1.0))


func _ring_band(d: float, r0: float, r1: float, soft: float) -> float:
	return _fade_in(d, r0 - soft, r0) * _fade_out(d, r1, r1 + soft)


## Rolled bowl: -3.2 m at the centre, zero slope at centre and rim, so the
## surrounding grass meets it with no lip or vertical step.
func _bowl_h(d: float) -> float:
	if d >= BOWL_R:
		return 0.0
	var u: float = pow(clampf(d / BOWL_R, 0.0, 1.0), 1.5)
	return -BOWL_DEPTH * 0.5 * (1.0 + cos(PI * u))


## Broad, gentle entry ramps on two opposite sides (east/west). The outer slope
## reaches grade at 14 m in other directions and 19 m in the marked sectors.
func _drift_outer_end(ang: float) -> float:
	var w: float = pow(absf(cos(ang)), 6.0)
	return lerpf(14.0, 19.0, w)


func _drift_h(d: float, ang: float) -> float:
	if d <= DRIFT_BANK_IN:
		return 0.06
	if d <= DRIFT_BANK_OUT:
		var t: float = (d - DRIFT_BANK_IN) / (DRIFT_BANK_OUT - DRIFT_BANK_IN)
		return lerpf(0.06, DRIFT_TOP, _smooth(t))
	var outer: float = _drift_outer_end(ang)
	if d <= outer:
		var t: float = (d - DRIFT_BANK_OUT) / (outer - DRIFT_BANK_OUT)
		return lerpf(DRIFT_TOP, 0.0, _smooth(t))
	return 0.0


func _mesa_h(d: float) -> float:
	if d <= MESA_TOP_R:
		return MESA_H
	if d >= MESA_FOOT_R:
		return 0.0
	var t: float = (d - MESA_TOP_R) / (MESA_FOOT_R - MESA_TOP_R)
	return MESA_H * 0.5 * (1.0 + cos(PI * t))


func _highline_h(d: float) -> float:
	if d <= HL_TOP_R:
		return MESA_H
	if d >= HL_FOOT_R:
		return 0.0
	var t: float = (d - HL_TOP_R) / (HL_FOOT_R - HL_TOP_R)
	return MESA_H * 0.5 * (1.0 + cos(PI * t))


func _drop_h(d: float) -> float:
	if d >= 5.0:
		return 0.0
	return 0.9 * 0.5 * (1.0 + cos(PI * d / 5.0))


func _ramp_lateral(s: float) -> float:
	if s <= RAMP_HALF:
		return 1.0
	if s >= RAMP_FOOT:
		return 0.0
	var t: float = (s - RAMP_HALF) / (RAMP_FOOT - RAMP_HALF)
	return 0.5 * (1.0 + cos(PI * t))


## Solid earthen drive-up ramps, baked into the same terrain surface so they
## meet grade (y=0) and the summit top (y=5.5) with no step.
func _mesa_ramp_h(x: float, z: float) -> float:
	var s: float = absf(x - 34.0)
	if s >= RAMP_FOOT:
		return 0.0
	# The ramp ends at the mesa's north rim. Without this cutoff the clamped
	# rise stayed at 5.5 m all the way to the perimeter wall.
	if z <= -7.0:
		return 0.0
	var t: float = clampf((20.0 - z) / 27.0, 0.0, 1.0)
	return MESA_H * t * _ramp_lateral(s)


func _highline_ramp_h(x: float, z: float) -> float:
	var s: float = absf(x - 12.0)
	if s >= RAMP_FOOT:
		return 0.0
	# Same cutoff at the highline's north rim, so the ramp does not become a
	# second 5.5 m plateau over the south half of the park.
	if z <= -31.5:
		return 0.0
	var t: float = clampf((-17.0 - z) / 14.5, 0.0, 1.0)
	return MESA_H * t * _ramp_lateral(s)


## Solid elevated causeway joining the mesa and highline summits at 5.5 m.
func _causeway_h(x: float, z: float) -> float:
	var ax: float = 25.0
	var az: float = -16.0
	var bx: float = -4.5
	var bz: float = -24.0
	var px: float = x - ax
	var pz: float = z - az
	var len2: float = bx * bx + bz * bz
	var t: float = clampf((px * bx + pz * bz) / len2, 0.0, 1.0)
	var cx: float = ax + bx * t
	var cz: float = az + bz * t
	var d: float = Vector2(x - cx, z - cz).length()
	if d <= CAUSE_HALF:
		return MESA_H
	if d >= CAUSE_FOOT:
		return 0.0
	var f: float = (d - CAUSE_HALF) / (CAUSE_FOOT - CAUSE_HALF)
	return MESA_H * 0.5 * (1.0 + cos(PI * f))


func _terrain_h(x: float, z: float) -> float:
	var db: float = Vector2(x - BOWL_CENTER.x, z - BOWL_CENTER.y).length()
	var bowl: float = _bowl_h(db)
	if bowl < 0.0:
		return bowl
	var dd: float = Vector2(x - DRIFT_CENTER.x, z - DRIFT_CENTER.y).length()
	var ang: float = atan2(z - DRIFT_CENTER.y, x - DRIFT_CENTER.x)
	var h: float = _drift_h(dd, ang)
	h = maxf(h, _mesa_h(Vector2(x - MESA_CENTER.x, z - MESA_CENTER.y).length()))
	h = maxf(h, _highline_h(Vector2(x - HL_CENTER.x, z - HL_CENTER.y).length()))
	h = maxf(h, _drop_h(Vector2(x - DROP_CENTER.x, z - DROP_CENTER.y).length()))
	h = maxf(h, _mesa_ramp_h(x, z))
	h = maxf(h, _highline_ramp_h(x, z))
	h = maxf(h, _causeway_h(x, z))
	return h


func _mix(a: Color, b: Color, t: float) -> Color:
	return Color(lerpf(a.r, b.r, t), lerpf(a.g, b.g, t),
		lerpf(a.b, b.b, t), lerpf(a.a, b.a, t))


func _hash2(i: int, j: int) -> float:
	var v: float = sin(float(i) * 12.9898 + float(j) * 78.233) * 43758.5453
	return v - floor(v)


func _grass_color(i: int, j: int) -> Color:
	var n: float = (_hash2(i, j) - 0.5) * 0.09
	return Color(0.40 + n, 0.66 + n, 0.28 + n * 0.5)


func _road_weight(x: float, z: float) -> float:
	if absf(x) <= 17.0 and z >= 51.0 and z <= 70.0:
		return 1.0
	if absf(x) <= 5.0 and z >= -12.0 and z <= 51.0:
		return 1.0
	return _ring_band(Vector2(x, z).length(), RING_IN, RING_OUT, 0.6)


func _paved_weight(x: float, z: float) -> float:
	var w: float = 0.0
	if absf(x - 34.0) <= RAMP_HALF and z >= -7.5 and z <= 20.5:
		w = 1.0
	if absf(x - 12.0) <= RAMP_HALF and z >= -32.0 and z <= -16.5:
		w = 1.0
	if _causeway_h(x, z) >= MESA_H * 0.70:
		w = 1.0
	return w


func _terrain_color(x: float, z: float, i: int, j: int) -> Color:
	var c: Color = _grass_color(i, j)
	var db: float = Vector2(x - BOWL_CENTER.x, z - BOWL_CENTER.y).length()
	c = _mix(c, Color(0.56, 0.62, 0.70), _fade_out(db, BOWL_R - 0.6, BOWL_R + 0.4))
	var bang: float = atan2(z - BOWL_CENTER.y, x - BOWL_CENTER.x)
	var bw: float = pow(absf(sin(bang)), 8.0)
	c = _mix(c, Color(1.0, 0.82, 0.18),
		bw * _ring_band(db, 6.0, BOWL_R - 1.0, 1.2) * 0.40)
	c = _mix(c, Color(0.27, 0.29, 0.33),
		maxf(_road_weight(x, z), _paved_weight(x, z)))
	var dd: float = Vector2(x - DRIFT_CENTER.x, z - DRIFT_CENTER.y).length()
	var ang: float = atan2(z - DRIFT_CENTER.y, x - DRIFT_CENTER.x)
	var outer: float = _drift_outer_end(ang)
	c = _mix(c, Color(0.27, 0.29, 0.33), _fade_out(dd, outer - 0.6, outer + 0.4))
	var ew: float = pow(absf(cos(ang)), 6.0)
	c = _mix(c, Color(1.0, 0.82, 0.18),
		ew * _ring_band(dd, DRIFT_BANK_OUT, outer - 0.5, 1.0) * 0.85)
	var dm: float = Vector2(x - DROP_CENTER.x, z - DROP_CENTER.y).length()
	c = _mix(c, Color(0.66, 0.50, 0.34), _fade_out(dm, 3.0, 5.0) * 0.8)
	return c


func _terrain() -> void:
	var cell: float = (FIELD * 2.0) / float(GRID)
	var side: int = GRID + 1
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(side * side)
	norms.resize(side * side)
	colors.resize(side * side)
	uvs.resize(side * side)
	for i in side:
		var x: float = -FIELD + float(i) * cell
		for j in side:
			var z: float = -FIELD + float(j) * cell
			var idx: int = i * side + j
			var h: float = _terrain_h(x, z)
			heights[idx] = h
			verts[idx] = Vector3(x, h, z)
			colors[idx] = _terrain_color(x, z, i, j)
			# World-space UVs keep the tile size constant across the park.
			uvs[idx] = Vector2(x, z)
	for i in side:
		for j in side:
			var idx: int = i * side + j
			var im: int = maxi(i - 1, 0)
			var ip: int = mini(i + 1, GRID)
			var jm: int = maxi(j - 1, 0)
			var jp: int = mini(j + 1, GRID)
			var hx: float = (heights[ip * side + j] - heights[im * side + j]) / (float(ip - im) * cell)
			var hz: float = (heights[i * side + jp] - heights[i * side + jm]) / (float(jp - jm) * cell)
			norms[idx] = Vector3(-hx, 1.0, -hz).normalized()
	var indices := PackedInt32Array()
	for i in GRID:
		for j in GRID:
			var v00: int = i * side + j
			var v10: int = (i + 1) * side + j
			var v01: int = i * side + j + 1
			var v11: int = (i + 1) * side + j + 1
			indices.append_array([v00, v10, v11, v00, v11, v01])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "ParkTerrain"
	instance.mesh = mesh
	instance.material_override = _terrain_mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	var faces := PackedVector3Array()
	for k in range(0, indices.size(), 3):
		faces.append(verts[indices[k]])
		faces.append(verts[indices[k + 1]])
		faces.append(verts[indices[k + 2]])
	_static_faces("TerrainCollision", faces)
	# Visual-only outfield beyond the wall (with a hole over the bowl).
	var outfield := MeshInstance3D.new()
	outfield.name = "Outfield"
	outfield.mesh = _ground_fan(800.0, BOWL_R + 0.05, -0.10)
	outfield.material_override = _pbr("grass_diff", "grass_nor", "grass_rough",
		160.0, Color(0.72, 0.93, 0.60), 0.06, 0.06)
	outfield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outfield)
	# Safety net well below the bowl floor; no overlap with the terrain.
	var body := StaticBody3D.new()
	body.name = "GroundNet"
	body.collision_layer = 1
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(FIELD * 2.0, 2.0, FIELD * 2.0)
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position = Vector3(0.0, -6.0, 0.0)
	body.add_child(collision)
	add_child(body)


## Square sheet minus a circular hole, used only for the visual outfield.
func _ground_fan(half_size: float, hole_r: float, y: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var segments: int = 64
	var center := Vector3(BOWL_CENTER.x, y, BOWL_CENTER.y)
	for j in segments:
		var angle: float = TAU * float(j) / float(segments)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var rim: Vector3 = center + dir * hole_r
		var t: float = half_size / maxf(absf(dir.x), absf(dir.z))
		var edge := Vector3(dir.x * t, y, dir.z * t)
		verts.append(rim)
		verts.append(edge)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		uvs.append(Vector2(rim.x * 0.1, rim.z * 0.1))
		uvs.append(Vector2(edge.x * 0.1, edge.z * 0.1))
	for j in segments:
		var jn: int = (j + 1) % segments
		var a: int = j * 2
		var b: int = jn * 2
		indices.append_array([a, a + 1, b, b, a + 1, b + 1])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_arrays(verts, norms, uvs, PackedColorArray(), indices))
	return mesh


func _arrays(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, colors: PackedColorArray,
		indices: PackedInt32Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	if not indices.is_empty():
		arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Only ONE ConcavePolygonShape3D in the whole park: the terrain. This is what
## guarantees there are no overlapping trimeshes to produce double contacts.
func _static_faces(body_name: String, faces: PackedVector3Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


# --------------------------------------------------------------------------
# painted marks (visual only, no collision)


func _painted_marks() -> void:
	var y: float = 0.03
	_box_decal(Vector3(0, y + 0.01, 51), Vector3(34, 0.02, 1.2), _checker_mat(24, 2))
	_box_decal(Vector3(-5.2, y + 0.01, 19.5), Vector3(0.25, 0.02, 63), _paint_mat)
	_box_decal(Vector3(5.2, y + 0.01, 19.5), Vector3(0.25, 0.02, 63), _paint_mat)
	_annulus(Vector3(BOWL_CENTER.x, 0.04, BOWL_CENTER.y),
		BOWL_R - 0.6, BOWL_R + 0.9, _yellow_mat)
	var disc := CylinderMesh.new()
	disc.top_radius = 4.2
	disc.bottom_radius = 4.2
	disc.height = 0.02
	disc.radial_segments = 48
	var paint := MeshInstance3D.new()
	paint.name = "DriftPaint"
	paint.mesh = disc
	var pink := StandardMaterial3D.new()
	pink.albedo_color = Color("f26ca7")
	paint.material_override = pink
	paint.position = Vector3(DRIFT_CENTER.x, 0.075, DRIFT_CENTER.y)
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(paint)


func _checker_mat(cells_x: int, cells_y: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(CHECKER_SHADER) as Shader
	mat.set_shader_parameter("light_color", Color("fff6e3"))
	mat.set_shader_parameter("dark_color", UiPalette.OUTLINE)
	mat.set_shader_parameter("cells", Vector2(cells_x, cells_y))
	return mat


func _box_decal(at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _annulus(center: Vector3, r_in: float, r_out: float, material: Material) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var seg: int = 64
	for i in seg:
		var a0: float = TAU * float(i) / float(seg)
		var a1: float = TAU * float(i + 1) / float(seg)
		var p0 := Vector3(center.x + cos(a0) * r_in, center.y, center.z + sin(a0) * r_in)
		var p1 := Vector3(center.x + cos(a0) * r_out, center.y, center.z + sin(a0) * r_out)
		var p2 := Vector3(center.x + cos(a1) * r_out, center.y, center.z + sin(a1) * r_out)
		var p3 := Vector3(center.x + cos(a1) * r_in, center.y, center.z + sin(a1) * r_in)
		for v: Vector3 in [p0, p1, p2, p0, p2, p3]:
			verts.append(v)
			norms.append(Vector3.UP)
			uvs.append(Vector2(v.x * 0.1, v.z * 0.1))
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_arrays(verts, norms, uvs, PackedColorArray(), PackedInt32Array()))
	var instance := MeshInstance3D.new()
	instance.name = "BowlCoping"
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


# --------------------------------------------------------------------------
# zones (convex obstacles / decor only)


func _jump_lane() -> void:
	for i in 4:
		var z: float = 36.0 - float(i) * 3.0
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.35
		cylinder.bottom_radius = 0.35
		cylinder.height = 10.0
		cylinder.radial_segments = 16
		var roller := MeshInstance3D.new()
		roller.name = "Roller_%d" % i
		roller.mesh = cylinder
		roller.material_override = _yellow_mat
		roller.rotation.z = PI / 2.0
		roller.position = Vector3(0.0, 0.0, z)
		add_child(roller)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CylinderShape3D.new()
		shape.radius = 0.35
		shape.height = 10.0
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.rotation.z = PI / 2.0
		collision.position = Vector3(0.0, 0.0, z)
		body.add_child(collision)
		add_child(body)
	_wedge("Kicker", Vector3(0, 0.85, 5.5), Vector3(8, 0.3, 7.4), 13.7, _yellow_mat)
	_wedge("Landing", Vector3(0, 0.55, -7.0), Vector3(8, 0.3, 6.4), -10.4, _dirt_mat)
	_boost_pad(Vector3(0, 0.04, 46))
	_boost_pad(Vector3(0, 0.04, 16))


func _wedge(body_name: String, at: Vector3, size: Vector3, angle_deg: float,
		material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.name = body_name + "Mesh"
	instance.mesh = box
	instance.material_override = material
	instance.position = at
	instance.rotation.x = deg_to_rad(angle_deg)
	add_child(instance)
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = at
	collision.rotation.x = deg_to_rad(angle_deg)
	body.add_child(collision)
	add_child(body)


func _boost_pad(at: Vector3) -> void:
	var pad: Node3D = (load(BOOST_PAD_SCENE) as PackedScene).instantiate()
	pad.position = at
	add_child(pad)


func _mesa() -> void:
	_boost_pad(Vector3(34.0, MESA_H + 0.02, -13.0))
	_wedge("MesaLip", Vector3(34, MESA_H + 0.3, -23.0), Vector3(6, 0.25, 3.4), 13.0, _yellow_mat)
	_crate("MesaCrate1", Vector3(31, MESA_H, -18))
	_crate("MesaCrate2", Vector3(37, MESA_H, -18))


func _highline() -> void:
	_boost_pad(Vector3(12.0, MESA_H + 0.03, -38.0))
	_wedge("HighlineLip", Vector3(12.0, MESA_H + 0.25, -47.0),
		Vector3(5.6, 0.25, 3.0), 12.0, _yellow_mat)
	_tire_stack(Vector3(8.5, MESA_H, -42.0))
	_crate("HighlineCrate", Vector3(14.5, MESA_H, -42.0))


func _slalom_furniture() -> void:
	for i in 3:
		var z: float = 29.0 + float(i) * 6.5
		var x: float = 11.0 if i % 2 == 0 else 23.0
		_barrier(Vector3(x, 0.35, z), -12.0 if i % 2 == 0 else 12.0)
		_tire_stack(Vector3(25.0 if i % 2 == 0 else 9.0, 0.0, z + 2.0))
	_barrier(Vector3(18, 0.35, 48), 0.0)


func _tire_stack(at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "TireStack"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = 0.6
	shape.height = 1.05
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = at + Vector3.UP * 0.52
	body.add_child(collision)
	add_child(body)
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.16, 0.17, 0.20)
	rubber.roughness = 1.0
	for i in 3:
		var tire := CylinderMesh.new()
		tire.top_radius = 0.6
		tire.bottom_radius = 0.6
		tire.height = 0.34
		tire.radial_segments = 14
		var instance := MeshInstance3D.new()
		instance.mesh = tire
		instance.material_override = rubber if i < 2 else _yellow_mat
		instance.position = at + Vector3.UP * (0.18 + float(i) * 0.35)
		add_child(instance)


func _barrier(at: Vector3, yaw_deg: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Barrier"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 0.7, 0.5)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = at
	collision.rotation.y = deg_to_rad(yaw_deg)
	body.add_child(collision)
	add_child(body)
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 0.7, 0.5)
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.material_override = _checker_mat(8, 2)
	instance.position = at
	instance.rotation.y = deg_to_rad(yaw_deg)
	add_child(instance)


# --------------------------------------------------------------------------
# perimeter: solid wall with matching visible mesh, scenery pushed outside


func _perimeter() -> void:
	var berm_mat := _pbr("grass_diff", "grass_nor", "grass_rough", 8.0,
		Color(0.62, 0.82, 0.55), 0.08, 0.06)
	for i in 20:
		var angle: float = TAU * float(i) / 20.0
		var sphere := SphereMesh.new()
		sphere.radius = 8.0
		sphere.height = 6.5
		sphere.radial_segments = 12
		sphere.rings = 6
		var berm := MeshInstance3D.new()
		berm.name = "Berm_%02d" % i
		berm.mesh = sphere
		berm.material_override = berm_mat
		var radius: float = _rng.randf_range(112.0, 140.0)
		berm.position = Vector3(cos(angle) * radius,
			-1.5 + _rng.randf_range(-0.3, 0.3), sin(angle) * radius)
		berm.scale = Vector3(_rng.randf_range(2.4, 2.9), 1.0, 1.1)
		berm.rotation.y = angle + PI / 2.0
		berm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(berm)
	var wall_body := StaticBody3D.new()
	wall_body.name = "ParkWall"
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.52, 0.55, 0.58)
	wall_mat.roughness = 0.9
	var bottom: float = -1.0
	var center_y: float = bottom + WALL_H * 0.5
	var long_side: float = FIELD * 2.0 + WALL_T * 2.0
	var short_side: float = FIELD * 2.0
	for side in 4:
		var size: Vector3
		var pos: Vector3
		match side:
			0:
				size = Vector3(long_side, WALL_H, WALL_T)
				pos = Vector3(0, center_y, -FIELD)
			1:
				size = Vector3(long_side, WALL_H, WALL_T)
				pos = Vector3(0, center_y, FIELD)
			2:
				size = Vector3(WALL_T, WALL_H, short_side)
				pos = Vector3(-FIELD, center_y, 0)
			_:
				size = Vector3(WALL_T, WALL_H, short_side)
				pos = Vector3(FIELD, center_y, 0)
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = pos
		wall_body.add_child(collision)
		var box := BoxMesh.new()
		box.size = size
		var instance := MeshInstance3D.new()
		instance.name = "WallPanel_%d" % side
		instance.mesh = box
		instance.material_override = wall_mat
		instance.position = pos
		add_child(instance)
		var curb := MeshInstance3D.new()
		var curb_box := BoxMesh.new()
		if side < 2:
			curb_box.size = Vector3(size.x, 0.35, WALL_T + 0.06)
		else:
			curb_box.size = Vector3(WALL_T + 0.06, 0.35, size.z)
		curb.mesh = curb_box
		curb.material_override = _yellow_mat
		curb.position = pos + Vector3.UP * (WALL_H * 0.5 - 0.18)
		curb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(curb)
	add_child(wall_body)


# --------------------------------------------------------------------------
# guardrails on the elevated spans (real collision, so carts cannot fall off)


func _guardrails() -> void:
	for side: float in [-1.0, 1.0]:
		var x: float = 34.0 + side * RAMP_HALF
		_rail(Vector3(x, 0.0, 20.0), Vector3(x, MESA_H, -7.0))
	for side: float in [-1.0, 1.0]:
		var x: float = 12.0 + side * RAMP_HALF
		_rail(Vector3(x, 0.0, -17.0), Vector3(x, MESA_H, -31.5))
	var a := Vector3(25.0, MESA_H, -16.0)
	var b := Vector3(20.5, MESA_H, -40.0)
	var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var perp := Vector3(-dir.z, 0.0, dir.x).normalized()
	for side: float in [-1.0, 1.0]:
		var off: Vector3 = perp * (CAUSE_HALF * side)
		_rail(a + off, b + off)


func _rail(from: Vector3, to: Vector3) -> void:
	var direction: Vector3 = to - from
	var flat := Vector3(direction.x, 0.0, direction.z)
	var length: float = direction.length()
	var root := Node3D.new()
	root.name = "Guardrail"
	root.position = (from + to) * 0.5
	root.rotation.y = atan2(-flat.x, -flat.z)
	root.rotation.x = atan2(direction.y, maxf(flat.length(), 0.001))
	add_child(root)
	var rail_h: float = 0.95
	var rail_t: float = 0.16
	var box := BoxMesh.new()
	box.size = Vector3(rail_t, rail_h, length)
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = _yellow_mat
	mesh.position = Vector3(0.0, rail_h * 0.5, 0.0)
	root.add_child(mesh)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = box.size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, rail_h * 0.5, 0.0)
	body.add_child(collision)
	root.add_child(body)


# --------------------------------------------------------------------------
# pushable props (deterministic names keep the net index stable)


func _props() -> void:
	for i in 10:
		var angle: float = TAU * float(i) / 10.0
		_cone("DriftCone%d" % (i + 1), Vector3(
			DRIFT_CENTER.x + cos(angle) * 4.2, 0.05,
			DRIFT_CENTER.y + sin(angle) * 4.2))
	for i in 4:
		var angle: float = TAU * (float(i) + 0.5) / 4.0
		_cone("BowlCone%d" % (i + 1), Vector3(
			BOWL_CENTER.x + cos(angle) * (BOWL_R + 1.6), 0.0,
			BOWL_CENTER.y + sin(angle) * (BOWL_R + 1.6)))
	for i in 8:
		var x: float = 14.0 if i % 2 == 0 else 22.0
		_cone("SlalomCone%d" % (i + 1), Vector3(x, 0.0, 28.0 + float(i) * 2.2))
	_crate("Crate1", Vector3(-17.0, 0.0, 40.0))
	_crate("Crate2", Vector3(-16.0, 0.0, 40.0))
	_crate("Crate3", Vector3(-15.0, 0.0, 40.0))
	_crate("Crate4", Vector3(-16.5, 0.71, 40.0))
	_crate("Crate5", Vector3(-15.5, 0.71, 40.0))
	_crate("Crate6", Vector3(-16.0, 1.42, 40.0))
	for i in 4:
		_crate("Crate%d" % (7 + i), Vector3(-18.0 + float(i) * 1.0, 0.0, 44.5))


func _cone(prop_name: String, at: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = prop_name
	body.add_to_group("pushable")
	body.collision_layer = 4
	body.collision_mask = 5
	body.mass = 0.35
	# Cones are light and numerous; full CCD here is wasted physics work.
	body.continuous_cd = false
	body.physics_material_override = _prop_physics()
	# Spawn on the actual terrain, not at a fixed y that can be 0.37 m inside
	# the bowl/dome.
	body.position = Vector3(at.x, _terrain_h(at.x, at.z) + at.y + 0.05, at.z)
	var model: Node3D = (load(CONE_MODEL) as PackedScene).instantiate()
	model.name = "Model"
	body.add_child(model)
	var shape := CylinderShape3D.new()
	shape.height = 0.54
	shape.radius = 0.2
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, 0.27, 0.0)
	body.add_child(collision)
	add_child(body)


func _crate(prop_name: String, at: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = prop_name
	body.add_to_group("pushable")
	body.collision_layer = 4
	body.collision_mask = 5
	body.mass = 0.8
	body.continuous_cd = true
	body.physics_material_override = _prop_physics()
	body.position = Vector3(at.x, _terrain_h(at.x, at.z) + at.y + 0.02, at.z)
	var model: Node3D = (load(CRATE_MODEL) as PackedScene).instantiate()
	model.name = "Model"
	body.add_child(model)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.67, 0.71, 0.67)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, 0.36, 0.0)
	body.add_child(collision)
	add_child(body)


func _prop_physics() -> PhysicsMaterial:
	if _prop_material != null:
		return _prop_material
	var mat := PhysicsMaterial.new()
	mat.friction = 0.9
	mat.bounce = 0.15
	_prop_material = mat
	return mat


# --------------------------------------------------------------------------
# scenery: everything big sits outside the wall; small cover uses _blocked()


func _blocked(point: Vector3, margin: float) -> bool:
	var p := Vector2(point.x, point.z)
	if absf(p.x) > FIELD - 6.0 - margin or absf(p.y) > FIELD - 6.0 - margin:
		return true
	if absf(p.x) < 18.0 + margin and p.y > 50.0 - margin:
		return true
	if absf(p.x) < 6.0 + margin and p.y > -13.0 - margin and p.y < 51.0 + margin:
		return true
	var radius: float = p.length()
	if radius > RING_IN - margin and radius < RING_OUT + margin:
		return true
	if p.distance_to(BOWL_CENTER) < BOWL_R + 3.0 + margin:
		return true
	if p.distance_to(DRIFT_CENTER) < 20.0 + margin:
		return true
	if p.distance_to(MESA_CENTER) < MESA_FOOT_R + 2.0 + margin:
		return true
	if p.distance_to(HL_CENTER) < HL_FOOT_R + 2.0 + margin:
		return true
	if p.distance_to(DROP_CENTER) < 6.0 + margin:
		return true
	if absf(p.x - 34.0) < RAMP_FOOT + margin and p.y > -8.0 - margin and p.y < 21.0 + margin:
		return true
	if absf(p.x - 12.0) < RAMP_FOOT + margin and p.y > -33.0 - margin and p.y < -16.0 + margin:
		return true
	if p.x > 17.0 - margin and p.x < 28.0 + margin and p.y > -42.0 - margin and p.y < -14.0 + margin:
		return true
	if p.x > 9.0 - margin and p.x < 25.0 + margin and p.y > 25.0 - margin and p.y < 48.0 + margin:
		return true
	if p.distance_to(Vector2(-16, 41)) < 7.0 + margin:
		return true
	return false


func _scenery() -> void:
	var foliage := FoliageBaker.make_material()
	_realistic_trees()
	var flower_xf: Array = []
	for i in 240:
		var point := Vector3(_rng.randf_range(-64, 64), 0.0, _rng.randf_range(-64, 64))
		if _blocked(point, 1.0):
			continue
		point.y = _terrain_h(point.x, point.z)
		flower_xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU)
			.scaled(Vector3.ONE * _rng.randf_range(0.6, 1.1)), point))
	_scatter_layer("ParkFlowers", ["flower_purpleA", "flower_redA", "flower_yellowA",
		"grass", "grass_large"], flower_xf, foliage, false, 60.0, [])
	var bush_xf: Array = []
	var bush_colors: Array = []
	for i in 160:
		var angle: float = _rng.randf() * TAU
		var radius: float = _rng.randf_range(80.0, 130.0)
		var point := Vector3(cos(angle) * radius, -0.06, sin(angle) * radius)
		var scale: float = _rng.randf_range(0.9, 1.8)
		bush_xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU)
			.scaled(Vector3.ONE * scale), point))
		bush_colors.append(_tint())
	_scatter_layer("ParkBushes", ["plant_bush", "plant_bushLarge", "plant_bushSmall",
		"rock_smallA", "rock_smallFlatA"], bush_xf, foliage, false, 90.0, bush_colors)


func _realistic_trees() -> void:
	var bark := _pbr("bark_diff", "bark_nor", "grass_rough", 1.0,
		Color(0.95, 0.93, 0.88), 0.28, 0.035)
	var leaves := ShaderMaterial.new()
	leaves.shader = load("res://assets/materials/foliage_wind.gdshader") as Shader
	leaves.set_shader_parameter("card_tex", load("res://assets/textures/foliage/leaf_broad.png"))
	leaves.set_shader_parameter("tint", Color(0.86, 0.98, 0.80))
	leaves.set_shader_parameter("sway_height", 10.0)
	leaves.set_shader_parameter("wind_strength", 0.24)
	leaves.set_shader_parameter("wind_speed", 1.0)
	leaves.set_shader_parameter("alpha_cutoff", 0.42)
	leaves.set_shader_parameter("bend_radius", 0.0)
	leaves.set_shader_parameter("bend_strength", 0.0)
	var buckets: Dictionary = {}
	# ALL trees are placed beyond the solid wall: no pass-through trunks inside.
	for i in 300:
		var angle: float = _rng.randf() * TAU
		var radius: float = _rng.randf_range(80.0, 140.0)
		var point := Vector3(cos(angle) * radius, -0.06, sin(angle) * radius)
		var variant: int = _rng.randi_range(0, RealisticTree.variant_count() - 1)
		if not buckets.has(variant):
			buckets[variant] = []
		var scale: float = _rng.randf_range(0.75, 1.35)
		buckets[variant].append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU)
			.scaled(Vector3.ONE * scale), point))
	var holder := Node3D.new()
	holder.name = "ParkForest"
	add_child(holder)
	var builder := RealisticTree.new()
	for variant: int in buckets:
		var tree: Dictionary = builder.build(variant, 6800 + variant * 97)
		var transforms: Array = buckets[variant]
		holder.add_child(FoliageBaker.create_chunked_instances(
			tree["bark"], bark, transforms, true, 125.0, [], 64.0))
		holder.add_child(FoliageBaker.create_chunked_instances(
			tree["leaf"], leaves, transforms, false, 125.0, [], 64.0))


func _scatter_layer(layer_name: String, models: Array, transforms: Array,
		material: Material, shadows: bool, view_end: float, colors: Array) -> void:
	if transforms.is_empty():
		return
	var buckets: Dictionary = {}
	for i in transforms.size():
		var key: int = i % models.size()
		if not buckets.has(key):
			buckets[key] = {"xf": [], "col": []}
		buckets[key]["xf"].append(transforms[i])
		if not colors.is_empty():
			buckets[key]["col"].append(colors[i])
	var holder := Node3D.new()
	holder.name = layer_name
	add_child(holder)
	for key: int in buckets:
		var mesh: ArrayMesh = FoliageBaker.bake(str(models[key]))
		if mesh == null:
			continue
		holder.add_child(FoliageBaker.create_chunked_instances(
			mesh, material, buckets[key]["xf"], shadows, view_end, buckets[key]["col"]))


func _tint() -> Color:
	return Color(_rng.randf_range(0.55, 0.85), _rng.randf_range(0.7, 0.95),
		_rng.randf_range(0.5, 0.75))


func _backdrop() -> void:
	var hill_mat := _pbr("grass_diff", "grass_nor", "grass_rough", 20.0,
		Color(0.62, 0.78, 0.55), 0.10, 0.06)
	for i in 16:
		var angle: float = TAU * float(i) / 16.0 + _rng.randf_range(-0.1, 0.1)
		var radius: float = _rng.randf_range(190.0, 330.0)
		var hill_radius: float = _rng.randf_range(40.0, 70.0)
		var hill_height: float = hill_radius * _rng.randf_range(1.3, 1.7)
		_hill("Hill_%02d" % i, angle, radius, hill_radius, hill_height, hill_mat, 1.2)
	var ridge_mat := StandardMaterial3D.new()
	ridge_mat.albedo_color = Color(0.24, 0.38, 0.28)
	ridge_mat.roughness = 1.0
	for i in 9:
		var angle: float = TAU * float(i) / 9.0 + 0.28
		_hill("Ridge_%02d" % i, angle, _rng.randf_range(420.0, 580.0),
			_rng.randf_range(70.0, 120.0), _rng.randf_range(75.0, 120.0), ridge_mat, 1.6)
	Backdrop.add_mountains(self, _rng, 10)
	Backdrop.add_clouds(self, _rng, 16)


## Visual-only distant hill; well outside the wall (radius >= 190 m).
func _hill(hill_name: String, angle: float, radius: float, hill_radius: float,
		hill_height: float, material: Material, stretch: float) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = hill_radius
	sphere.height = hill_height
	sphere.radial_segments = 20
	sphere.rings = 10
	var hill := MeshInstance3D.new()
	hill.name = hill_name
	hill.mesh = sphere
	hill.material_override = material
	hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hill.position = Vector3(cos(angle) * radius, -hill_height * 0.18, sin(angle) * radius)
	hill.scale = Vector3(_rng.randf_range(1.1, stretch), 1.0, _rng.randf_range(1.1, stretch))
	add_child(hill)


func _signs() -> void:
	_sign("SLOP YARD", Vector3(0, 0, 49.5), Color("ffd22e"), 1.0, true)
	_sign("THE BOWL", Vector3(-36, 0, 30.5), Color("45b6f0"), 1.0)
	_sign("DRIFT RING", Vector3(-28, 0, -16.5), Color("f26ca7"), 1.0)
	_sign("MESA", Vector3(30.5, 0, 22.5), Color("4fbf52"), 1.0)
	_sign("HIGHLINE", Vector3(16.5, 0, -15.0), Color("45b6f0"), 0.9)
	_sign("SLALOM", Vector3(14, 0, 24.0), Color("ff9f45"), 0.9)


func _sign(text: String, at: Vector3, color: Color, scale: float,
		gantry: bool = false) -> void:
	var root := Node3D.new()
	root.name = "Sign_" + text
	root.position = at
	root.position.y = _terrain_h(at.x, at.z)
	root.scale = Vector3.ONE * scale
	add_child(root)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color("fff6e3")
	var post_x: float = 5.6 if gantry else 1.6
	var post_h: float = 4.6 if gantry else 2.2
	var board_y: float = 4.9 if gantry else 2.2
	var board_w: float = 12.0 if gantry else 4.2
	var board_h: float = 1.5 if gantry else 1.1
	var solid := StaticBody3D.new()
	solid.name = "SignCollision"
	solid.collision_layer = 1
	solid.collision_mask = 0
	root.add_child(solid)
	for x in [-post_x, post_x]:
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, post_h, 0.18)
		post.mesh = box
		post.material_override = post_mat
		post.position = Vector3(x, post_h * 0.5, 0.0)
		root.add_child(post)
		var post_shape := CollisionShape3D.new()
		var post_box := BoxShape3D.new()
		post_box.size = box.size
		post_shape.shape = post_box
		post_shape.position = post.position
		solid.add_child(post_shape)
	var board := MeshInstance3D.new()
	var board_box := BoxMesh.new()
	board_box.size = Vector3(board_w, board_h, 0.12)
	board.mesh = board_box
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = color
	board.material_override = board_mat
	board.position = Vector3(0.0, board_y, 0.0)
	root.add_child(board)
	var board_shape := CollisionShape3D.new()
	var board_box_shape := BoxShape3D.new()
	board_box_shape.size = board_box.size
	board_shape.shape = board_box_shape
	board_shape.position = board.position
	solid.add_child(board_shape)
	var label := Label3D.new()
	label.text = text
	label.font = load(TITLE_FONT)
	label.font_size = 96 if gantry else 64
	label.pixel_size = 0.012
	label.outline_size = 16 if gantry else 14
	label.outline_modulate = UiPalette.OUTLINE
	label.modulate = UiPalette.CREAM
	label.position = Vector3(0.0, board_y, 0.09)
	root.add_child(label)
