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
##
## Around that surface sit two layers of scenery:
##   - the park itself: a carved pond with a shoreline, paddock fences, an
##     entrance gate, lamp posts, hay bales, tyre stacks, crates, boulder
##     outcrops, bushes, flowers and wind-blown grass tufts, all placed in the
##     pockets the driving lines never reach;
##   - a layered horizon: three noise-displaced ridgelines, flat-topped buttes,
##     a conifer belt and the shared backdrop mountains. That replaces the old
##     ring of sphere domes, merges into two draw calls and fades into distance
##     fog, so the far view costs nothing per frame.

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

# Pond, in the south-west paddock. The basin is carved into the same height
# field as everything else, so the visible shore and the collision trimesh can
# never disagree. POND_WATER_R is the radius where the basin reaches
# POND_LEVEL: water radius < POND_R so the sheet stops just inside the bank.
const POND_CENTER := Vector2(-54.0, -54.0)
const POND_R: float = 12.0
const POND_DEPTH: float = 1.9
const POND_LEVEL: float = -0.62
const POND_WATER_R: float = 7.3

# Horizon layers are rings around the park: (radius, flank depth, crest height).
const RIDGE_BASE: float = 4.0
const HORIZON_FOG_DENSITY: float = 0.0011

var _grass_mat: ShaderMaterial
var _terrain_mat: ShaderMaterial
var _prop_material: PhysicsMaterial
var _asphalt_mat: StandardMaterial3D
var _concrete_mat: StandardMaterial3D
var _paint_mat: StandardMaterial3D
var _yellow_mat: StandardMaterial3D
var _dirt_mat: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _vertex_mat: StandardMaterial3D
var _horizon_mat: StandardMaterial3D
var _rubber_mat: StandardMaterial3D
var _water_mat: StandardMaterial3D
var _hay_mat: ShaderMaterial

# Merge buffers: fences, the gate, lamps, buttes, ridges and boulders are all
# appended here and flushed as one mesh per material.
var _geo_v := PackedVector3Array()
var _geo_n := PackedVector3Array()
var _geo_c := PackedColorArray()
var _geo_i := PackedInt32Array()
var _unit_box_arrays: Array = []
var _unit_cyl_arrays: Array = []

# Tyre stack visuals are batched; the collision bodies stay one per stack.
var _tyre_xf: Array = []
var _tyre_top_xf: Array = []
var _tyre_stacks: int = 0


func _ready() -> void:
	_rng.seed = 90421
	_make_materials()
	_terrain()
	_painted_marks()
	_jump_lane()
	_mesa()
	_highline()
	_slalom_furniture()
	_park_furniture()
	_perimeter()
	_guardrails()
	_props()
	_scenery()
	_horizon()
	_signs()
	# VisualGrade leaves the sandbox unfogged; the layered horizon needs the
	# haze, so claim the environment after every other _ready has run.
	_apply_horizon_fog.call_deferred()


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
	_vertex_mat = _make_vertex_material(false)
	_horizon_mat = _make_vertex_material(true)
	_rubber_mat = StandardMaterial3D.new()
	_rubber_mat.albedo_color = Color(0.16, 0.17, 0.20)
	_rubber_mat.roughness = 1.0
	_water_mat = StandardMaterial3D.new()
	_water_mat.albedo_color = Color(0.15, 0.33, 0.37, 0.86)
	_water_mat.roughness = 0.14
	_water_mat.metallic = 0.0
	_water_mat.metallic_specular = 0.65
	_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hay_mat = _pbr("dirt_diff", "dirt_nor", "dirt_rough", 2.4,
		Color(1.0, 0.87, 0.54), 0.12, 0.05)


## Shared vertex-coloured material for merged scenery. Culling is disabled for
## the horizon layers because their flanks are seen from the inside of a ring.
func _make_vertex_material(two_sided: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if two_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


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


## Pond basin: a smooth bowl that reaches grade at its rim, so the surrounding
## paddock grass meets the water without a lip. Carved through `_terrain_h`, so
## the shore that is drawn IS the shore that is collided against.
func _pond_h(d: float) -> float:
	if d >= POND_R:
		return 0.0
	var t: float = clampf(d / POND_R, 0.0, 1.0)
	return -POND_DEPTH * 0.5 * (1.0 + cos(PI * t))


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
	return minf(h, _pond_h(Vector2(x - POND_CENTER.x, z - POND_CENTER.y).length()))


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
	# Pond: a wide sand bank that narrows into silt, so the waterline always has
	# visible shore instead of a hard edge against the grass.
	var dp: float = Vector2(x - POND_CENTER.x, z - POND_CENTER.y).length()
	c = _mix(c, Color(0.74, 0.66, 0.47), _fade_out(dp, POND_R * 0.52, POND_R + 0.8))
	c = _mix(c, Color(0.31, 0.33, 0.27), _fade_out(dp, POND_R * 0.12, POND_R * 0.55))
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
	# Visual-only ground outside the wall. The park height field already covers
	# everything inside the wall, so this is a four-quad annulus: no hole to
	# punch over the bowl (which the old fan needed) and nothing that could
	# slice through the new pond basin.
	var outfield := MeshInstance3D.new()
	outfield.name = "Outfield"
	outfield.mesh = _outfield_mesh()
	outfield.material_override = _pbr("grass_diff", "grass_nor", "grass_rough",
		0.12, Color(0.72, 0.93, 0.60), 0.06, 0.06)
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


## Four quads forming a square annulus from just under the wall out to 800 m.
## The inner edge hides beneath the 7 m wall, so the 10 cm step down to the
## outfield plane is never visible from the park.
func _outfield_mesh() -> ArrayMesh:
	var inner: float = FIELD - 0.5
	var outer: float = 800.0
	var y: float = -0.10
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var strips: Array[Rect2] = [
		Rect2(-outer, -outer, outer * 2.0, outer - inner),
		Rect2(-outer, inner, outer * 2.0, outer - inner),
		Rect2(-outer, -inner, outer - inner, inner * 2.0),
		Rect2(inner, -inner, outer - inner, inner * 2.0),
	]
	for strip: Rect2 in strips:
		var base: int = verts.size()
		for corner: Vector2 in [strip.position,
				Vector2(strip.end.x, strip.position.y), strip.end,
				Vector2(strip.position.x, strip.end.y)]:
			verts.append(Vector3(corner.x, y, corner.y))
			norms.append(Vector3.UP)
			uvs.append(corner)
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_arrays(verts, norms, uvs, PackedColorArray(), indices))
	return mesh


# --------------------------------------------------------------------------
# merged geometry kit
#
# Fences, gates, lamps, buttes, ridgelines and boulders are all built from flat
# triangles appended to one scratch buffer and flushed as a single mesh, so a
# few hundred pieces of scenery still cost one draw call per material.


func _geo_begin() -> void:
	_geo_v = PackedVector3Array()
	_geo_n = PackedVector3Array()
	_geo_c = PackedColorArray()
	_geo_i = PackedInt32Array()


## Takes the current buffer as an ArrayMesh (used for MultiMesh sources).
func _geo_mesh() -> ArrayMesh:
	if _geo_v.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _geo_v
	arrays[Mesh.ARRAY_NORMAL] = _geo_n
	arrays[Mesh.ARRAY_COLOR] = _geo_c
	arrays[Mesh.ARRAY_INDEX] = _geo_i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Flush the buffer into one MeshInstance3D. Decoration only: never a body.
func _geo_commit(node_name: String, material: Material, shadows: bool) -> void:
	if _geo_v.is_empty():
		return
	var mesh := _geo_mesh()
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Flat-shaded triangle, visible from the `facing` side. Godot's front faces are
## clockwise, so the winding has to be picked as well as the normal: a mirrored
## index order would leave rock and butte faces culled or lit from behind.
func _geo_tri(a: Vector3, b: Vector3, c: Vector3, color: Color,
		facing: Vector3 = Vector3.UP) -> void:
	var normal: Vector3 = (c - a).cross(b - a)
	if normal.length_squared() < 0.000001:
		return
	normal = normal.normalized()
	var upside_down: bool = normal.dot(facing) < 0.0
	if upside_down:
		normal = -normal
	var base: int = _geo_v.size()
	for point: Vector3 in [a, b, c]:
		_geo_v.append(point)
		_geo_n.append(normal)
		_geo_c.append(color)
	if upside_down:
		_geo_i.append_array([base, base + 2, base + 1])
	else:
		_geo_i.append_array([base, base + 1, base + 2])


## Flat-shaded quad with a colour ramp from the `lo` edge (a,b) to `hi` (c,d).
## Same winding rule as `_geo_tri`, applied to both triangles of the quad.
func _geo_ramp_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		lo: Color, hi: Color, facing: Vector3) -> void:
	var normal: Vector3 = (c - a).cross(b - a)
	if normal.length_squared() < 0.000001:
		return
	normal = normal.normalized()
	var upside_down: bool = normal.dot(facing) < 0.0
	if upside_down:
		normal = -normal
	var base: int = _geo_v.size()
	for point: Vector3 in [a, b, c, d]:
		_geo_v.append(point)
		_geo_n.append(normal)
	_geo_c.append(lo)
	_geo_c.append(lo)
	_geo_c.append(hi)
	_geo_c.append(hi)
	if upside_down:
		_geo_i.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		_geo_i.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


func _geo_box(xform: Transform3D, size: Vector3, color: Color) -> void:
	if _unit_box_arrays.is_empty():
		var box := BoxMesh.new()
		_unit_box_arrays = box.surface_get_arrays(0)
	_geo_append(_unit_box_arrays, xform, size, color)


## Eight-sided post: enough for a lamp standard seen across the park.
func _geo_cylinder(xform: Transform3D, radius: float, height: float,
		color: Color) -> void:
	if _unit_cyl_arrays.is_empty():
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.0
		cylinder.bottom_radius = 1.0
		cylinder.height = 1.0
		cylinder.radial_segments = 8
		cylinder.rings = 1
		_unit_cyl_arrays = cylinder.surface_get_arrays(0)
	_geo_append(_unit_cyl_arrays, xform, Vector3(radius, height, radius), color)


## Append a unit primitive through `xform` and a non-uniform `scale`. Normals
## are re-normalised against the scale, which is exact for box/cylinder faces.
func _geo_append(arrays: Array, xform: Transform3D, scale: Vector3,
		color: Color) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var basis: Basis = xform.basis.orthonormalized()
	var base: int = _geo_v.size()
	for i in verts.size():
		_geo_v.append(xform * (verts[i] * scale))
		var local: Vector3 = norms[i]
		var adjusted := Vector3(local.x / maxf(absf(scale.x), 0.0001),
			local.y / maxf(absf(scale.y), 0.0001),
			local.z / maxf(absf(scale.z), 0.0001))
		_geo_n.append((basis * adjusted).normalized())
		_geo_c.append(color)
	for i in indices.size():
		_geo_i.append(base + indices[i])


## Beam between two ground points: rails, lintels and fences that follow slope.
func _geo_beam(from: Vector3, to: Vector3, width: float, height: float,
		color: Color) -> void:
	var delta: Vector3 = to - from
	var length: float = delta.length()
	if length < 0.01:
		return
	var z_axis: Vector3 = delta / length
	var x_axis: Vector3 = z_axis.cross(Vector3.UP)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	# z.cross(x) keeps the basis right-handed: a mirrored basis would invert the
	# triangle winding and leave every rail inside-out under back-face culling.
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	_geo_box(Transform3D(Basis(x_axis, y_axis, z_axis), (from + to) * 0.5),
		Vector3(width, height, length), color)


func _ground_point(flat: Vector3) -> Vector3:
	return Vector3(flat.x, _terrain_h(flat.x, flat.z), flat.z)


## Deterministic 0..1 hash for rock wobble and per-face shade variation.
func _hash01(value: int) -> float:
	var v: float = sin(float(value) * 12.9898) * 43758.5453
	return v - floor(v)


## Collapse a primitive mesh into an ArrayMesh so MultiMesh can batch it.
func _mesh_to_array(mesh: Mesh) -> ArrayMesh:
	var arrays: Array = mesh.surface_get_arrays(0)
	var baked := ArrayMesh.new()
	baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return baked


## One draw call for every repeated prop. `transforms` are world transforms.
func _batch(node_name: String, mesh: Mesh, material: Material,
		transforms: Array, shadows: bool, view_end: float = 0.0) -> void:
	if transforms.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.material_override = material
	if not shadows:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if view_end > 0.0:
		instance.visibility_range_end = view_end
		instance.visibility_range_end_margin = 8.0
		instance.visibility_range_fade_mode = \
			GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	add_child(instance)


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


## Collision stays one body per stack (carts must feel it); the 3 tyres are
## only visuals, so they go into the shared batch instead of 3 draw calls.
func _tire_stack(at: Vector3) -> void:
	_tyre_stacks += 1
	var body := StaticBody3D.new()
	body.name = "TireStack_%d" % _tyre_stacks
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
	for i in 3:
		var xform := Transform3D(Basis.IDENTITY, at + Vector3.UP * (0.18 + float(i) * 0.35))
		if i < 2:
			_tyre_xf.append(xform)
		else:
			_tyre_top_xf.append(xform)


## One rubber MultiMesh for every stack, plus one for the yellow top tyres.
func _flush_tire_stacks() -> void:
	var tire := CylinderMesh.new()
	tire.top_radius = 0.6
	tire.bottom_radius = 0.6
	tire.height = 0.34
	tire.radial_segments = 14
	var baked := _mesh_to_array(tire)
	_batch("TireStacks", baked, _rubber_mat, _tyre_xf, true)
	_batch("TireStackTops", baked, _yellow_mat, _tyre_top_xf, false)


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
# park furniture: pond, fences, gate, lamps and hay
#
# Every piece here is decoration and carries NO collision: the merged meshes
# are visual only, so a stray kart can never snag a fence post. Everything is
# placed in the paddocks between the ring road and the wall, or against the
# wall itself, which keeps it all clear of the driving lines.


func _park_furniture() -> void:
	_pond()
	_paddock_fence()
	_entrance_gate()
	_lamp_posts()
	_hay_bales()
	# Extra obstacle furniture for the two open paddocks.
	_tire_stack(Vector3(38.0, 0.0, 60.0))
	_tire_stack(Vector3(51.0, 0.0, 38.0))
	_tire_stack(Vector3(-44.0, 0.0, -44.0))
	_tire_stack(Vector3(-62.0, 0.0, -36.0))
	_flush_tire_stacks()


## Water sheet + shoreline planting. The basin itself is carved by `_pond_h`
## through `_terrain_h`, so the collision mesh already agrees with the shore;
## only the flat water disc and the ground cover are added here.
func _pond() -> void:
	var sheet_mesh := CylinderMesh.new()
	sheet_mesh.top_radius = POND_WATER_R
	sheet_mesh.bottom_radius = POND_WATER_R
	sheet_mesh.height = 0.05
	sheet_mesh.radial_segments = 40
	sheet_mesh.rings = 1
	var sheet := MeshInstance3D.new()
	sheet.name = "PondWater"
	sheet.mesh = sheet_mesh
	sheet.material_override = _water_mat
	sheet.position = Vector3(POND_CENTER.x, POND_LEVEL, POND_CENTER.y)
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sheet)
	# A ring of shore stones straddling the waterline: it hides the 2 cm lip
	# where the flat water sheet meets the curved bank and gives the pond an
	# edge you can read from the track.
	_geo_begin()
	var stone := Color(0.58, 0.56, 0.52)
	for i in 11:
		var angle: float = TAU * float(i) / 11.0 + 0.15
		var point: Vector3 = Vector3(POND_CENTER.x + cos(angle) * (POND_WATER_R - 0.15),
			0.0, POND_CENTER.y + sin(angle) * (POND_WATER_R - 0.15))
		point = _ground_point(point)
		_geo_box(Transform3D(Basis(Vector3.UP, angle + PI * 0.5),
			point + Vector3.UP * 0.05), Vector3(1.4, 0.3, 0.8), stone)
	_geo_commit("PondStones", _vertex_mat, false)


## Post-and-rail paddock fencing: two runs close the pond off from the ring
## road, two more edge the south-east hay field.
func _paddock_fence() -> void:
	_geo_begin()
	var wood := Color(0.62, 0.47, 0.33)
	var dark := Color(0.47, 0.35, 0.25)
	# Both runs stay outside the 52-58 m ring and outside the pond basin, so no
	# post ever stands on a driving line.
	_fence_run(Vector3(-66.0, 0.0, -38.0), Vector3(-58.0, 0.0, -38.0), 2.6, wood)
	_fence_run(Vector3(-53.0, 0.0, -38.0), Vector3(-49.0, 0.0, -38.0), 2.6, wood)
	_fence_run(Vector3(-38.0, 0.0, -66.0), Vector3(-38.0, 0.0, -50.0), 2.6, wood)
	_fence_run(Vector3(44.0, 0.0, 44.0), Vector3(44.0, 0.0, 66.0), 2.8, dark)
	_fence_run(Vector3(44.0, 0.0, 44.0), Vector3(66.0, 0.0, 44.0), 2.8, dark)
	# Field gate hung open at the pond run's gap: two leaves, no collision.
	_gate_leaf(Vector3(-58.0, 0.0, -38.0), -0.7, 2.6, dark)
	_gate_leaf(Vector3(-53.0, 0.0, -38.0), PI + 0.7, 2.6, dark)
	_geo_commit("PaddockFence", _vertex_mat, false)


## One post-and-rail run between two flat points, following the terrain height.
func _fence_run(from: Vector3, to: Vector3, spacing: float, color: Color) -> void:
	var delta: Vector3 = to - from
	var length: float = delta.length()
	if length < 0.5:
		return
	var bays: int = maxi(int(round(length / spacing)), 1)
	var points: Array[Vector3] = []
	for i in bays + 1:
		points.append(_ground_point(from + delta * (float(i) / float(bays))))
	var post_color: Color = color.darkened(0.22)
	for point: Vector3 in points:
		_geo_box(Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.62),
			Vector3(0.14, 1.3, 0.14), post_color)
	for i in bays:
		for height: float in [0.46, 0.94]:
			_geo_beam(points[i] + Vector3.UP * height,
				points[i + 1] + Vector3.UP * height, 0.09, 0.11, color)


## A hung gate leaf: frame, two braces and three palings, all in one batch.
func _gate_leaf(hinge: Vector3, yaw: float, width: float, color: Color) -> void:
	var base: Vector3 = _ground_point(hinge)
	var basis := Basis(Vector3.UP, yaw)
	var post_color: Color = color.darkened(0.2)
	var far: Vector3 = base + basis * Vector3(width, 0.0, 0.0)
	_geo_box(Transform3D(basis, base + Vector3.UP * 0.62), Vector3(0.13, 1.3, 0.13), post_color)
	_geo_box(Transform3D(basis, far + Vector3.UP * 0.62), Vector3(0.13, 1.3, 0.13), post_color)
	for height: float in [0.34, 0.96]:
		_geo_beam(base + Vector3.UP * height, far + Vector3.UP * height, 0.08, 0.10, color)
	for i in 3:
		var at: Vector3 = base + basis * Vector3(width * (0.25 + float(i) * 0.25), 0.0, 0.0)
		_geo_box(Transform3D(basis, at + Vector3.UP * 0.64), Vector3(0.1, 1.15, 0.07), color)


## Gatehouse on the start straight. The pilasters cap 0.6 m over the wall and
## lean 0.25 m proud of its face, but only into the last 25 cm of the apron:
## a kart's own body is already stopped by the wall before it can touch them.
func _entrance_gate() -> void:
	_geo_begin()
	var stone := Color(0.70, 0.68, 0.62)
	var stone_dark := Color(0.51, 0.50, 0.47)
	var timber := Color(0.50, 0.35, 0.24)
	var deck: float = _terrain_h(0.0, 69.0)
	for side: float in [-1.0, 1.0]:
		var x: float = side * 9.4
		_geo_box(Transform3D(Basis.IDENTITY, Vector3(x, deck + 3.3, 69.45)),
			Vector3(1.4, 6.6, 0.9), stone)
		_geo_box(Transform3D(Basis.IDENTITY, Vector3(x, deck + 0.3, 69.35)),
			Vector3(1.8, 0.6, 1.1), stone_dark)
		_geo_box(Transform3D(Basis.IDENTITY, Vector3(x, deck + 6.75, 69.4)),
			Vector3(1.8, 0.32, 1.15), stone_dark)
	_geo_beam(Vector3(-9.4, deck + 5.15, 69.45), Vector3(9.4, deck + 5.15, 69.45),
		0.75, 0.55, timber)
	# Upper beam clears the yellow wall coping at 5.65-6.0 m.
	_geo_beam(Vector3(-9.4, deck + 6.2, 69.45), Vector3(9.4, deck + 6.2, 69.45),
		0.5, 0.32, timber)
	for i in 7:
		var x: float = -7.2 + float(i) * 2.4
		_geo_beam(Vector3(x, deck + 5.25, 69.45), Vector3(x + 1.2, deck + 6.05, 69.45),
			0.14, 0.18, timber)
	# Hanging board, 4.3 m up and 15 cm proud of the wall face.
	_geo_box(Transform3D(Basis.IDENTITY, Vector3(0.0, deck + 4.3, 69.16)),
		Vector3(5.4, 0.9, 0.12), Color(0.36, 0.42, 0.30))
	_geo_commit("EntranceGate", _vertex_mat, false)


## Lamp standards around the wall verge, well outside the ring road.
func _lamp_posts() -> void:
	_geo_begin()
	var glow_positions: Array[Vector3] = []
	var metal := Color(0.25, 0.27, 0.30)
	var offsets: Array[float] = [-56.0, -28.0, 0.0, 28.0, 56.0]
	var spots: Array[Vector3] = []
	for offset: float in offsets:
		spots.append(Vector3(offset, 0.0, 66.0))
		spots.append(Vector3(offset, 0.0, -66.0))
		if absf(offset) > 1.0:
			spots.append(Vector3(66.0, 0.0, offset))
			spots.append(Vector3(-66.0, 0.0, offset))
	for spot: Vector3 in spots:
		# Skip the pond paddock and the start straight's gate opening.
		if spot.distance_to(Vector3(POND_CENTER.x, 0.0, POND_CENTER.y)) < POND_R + 3.0:
			continue
		if absf(spot.x) < 13.0 and spot.z > 60.0:
			continue
		var base: Vector3 = _ground_point(spot)
		_geo_cylinder(Transform3D(Basis.IDENTITY, base + Vector3.UP * 2.2),
			0.10, 4.4, metal)
		_geo_box(Transform3D(Basis.IDENTITY, base + Vector3.UP * 4.34),
			Vector3(0.54, 0.13, 0.54), metal)
		glow_positions.append(base + Vector3.UP * 4.16)
	_geo_commit("LampPosts", _vertex_mat, false)
	if glow_positions.is_empty():
		return
	_geo_begin()
	for at: Vector3 in glow_positions:
		_geo_box(Transform3D(Basis.IDENTITY, at), Vector3(0.40, 0.24, 0.40),
			Color(1.0, 0.93, 0.72))
	# Unshaded so the lamps read as self-lit without an extra light per post.
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.93, 0.72)
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_geo_commit("LampHeads", glow, false)


## Straw bales in the south-east paddock: one MultiMesh, no collision.
func _hay_bales() -> void:
	var bale := CylinderMesh.new()
	bale.top_radius = 0.62
	bale.bottom_radius = 0.62
	bale.height = 1.28
	bale.radial_segments = 12
	bale.rings = 1
	var spots: Array[Vector2] = [
		Vector2(48.0, 48.0), Vector2(50.5, 47.0), Vector2(49.6, 50.4),
		Vector2(52.8, 49.6), Vector2(53.4, 46.0), Vector2(46.8, 51.6),
		Vector2(56.0, 52.4), Vector2(57.4, 49.0), Vector2(51.2, 53.6),
		Vector2(-63.0, -42.0), Vector2(-65.5, -44.0), Vector2(-60.5, -41.5),
	]
	var transforms: Array = []
	for spot: Vector2 in spots:
		var point := Vector3(spot.x, _terrain_h(spot.x, spot.y) + 0.62, spot.y)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, PI * 0.5)
		transforms.append(Transform3D(basis, point))
	_batch("HayBales", _mesh_to_array(bale), _hay_mat, transforms, false)


# --------------------------------------------------------------------------
# perimeter: solid wall with matching visible mesh, scenery pushed outside


func _perimeter() -> void:
	# The old ring of 20 squashed sphere "berms" lived here. The conifer belt
	# and the ridgelines behind it do that job now, with real silhouettes.
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
	# Loose crates in the paddocks: still pushable, still out of every line.
	_crate("Crate11", Vector3(47.0, 0.0, 56.0))
	_crate("Crate12", Vector3(48.1, 0.0, 56.4))
	_crate("Crate13", Vector3(47.6, 0.71, 56.2))
	_crate("Crate14", Vector3(-45.5, 0.0, 45.0))
	_crate("Crate15", Vector3(-46.6, 0.0, 45.6))
	_crate("Crate16", Vector3(58.0, 0.0, -30.0))


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
	# Crates are heavy and solid: the kart cannot drive through one, and the
	# push sensor still launches it. Cones stay on the non-blocking PROP layer.
	body.collision_layer = 4 | 16
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
	if p.distance_to(POND_CENTER) < POND_R + 2.5 + margin:
		return true
	return false


## The start apron is 34 m wide, so the verge rings must stay out of it: a
## boulder or bush on the grid square is exactly where a kart is placed.
func _on_apron(p: Vector2) -> bool:
	return absf(p.x) < 20.0 and p.y > 49.0


func _scenery() -> void:
	var foliage: StandardMaterial3D = FoliageBaker.make_material()
	_realistic_trees()
	_conifer_line()
	_bushes(foliage)
	_flowers(foliage)
	_grass_tufts()
	_rocks()


## Mixed broadleaf/conifer belt beyond the wall. Clusters read as woodland far
## better than an even scatter, and the same instance count goes further.
## Trunks and canopies are separate MultiMeshes (different materials), so the
## whole forest is a handful of chunked draw calls.
func _realistic_trees() -> void:
	var bark := _pbr("bark_diff", "bark_nor", "grass_rough", 1.0,
		Color(0.95, 0.93, 0.88), 0.28, 0.035)
	var broad: ShaderMaterial = _wind_material("leaf_broad",
		Color(0.88, 1.0, 0.82), 10.0, 0.26, 1.0)
	var frond: ShaderMaterial = _wind_material("leaf_frond",
		Color(0.66, 0.86, 0.64), 12.0, 0.30, 0.9)
	# Two geometry variants only: every extra variant is another pair of draw
	# calls, and scale + tint variation carries the variety from the far side
	# of a 7 m wall.
	var builder := RealisticTree.new()
	var variants: Array[int] = [0, 3]
	var partners: Array[ShaderMaterial] = [broad, frond]
	var xf_a: Array = []
	var xf_b: Array = []
	for cluster: Vector3 in _tree_clusters():
		var count: int = _rng.randi_range(14, 22)
		for i in count:
			var offset := Vector2(_rng.randf_range(-1.0, 1.0),
				_rng.randf_range(-1.0, 1.0)).normalized() * pow(_rng.randf(), 0.6) * 17.0
			var point := Vector3(cluster.x + offset.x, -0.06, cluster.z + offset.y)
			var scale: float = _rng.randf_range(0.72, 1.42)
			var xform := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU)
				.scaled(Vector3.ONE * scale), point)
			if _rng.randf() < 0.62:
				xf_a.append(xform)
			else:
				xf_b.append(xform)
	var holder := Node3D.new()
	holder.name = "ParkForest"
	add_child(holder)
	var groups: Array = [[xf_a, 0], [xf_b, 1]]
	for group: Array in groups:
		var transforms: Array = group[0]
		if transforms.is_empty():
			continue
		var index: int = int(group[1])
		var tree: Dictionary = builder.build(variants[index], 6800 + variants[index] * 97)
		holder.add_child(FoliageBaker.create_chunked_instances(
			tree["bark"], bark, transforms, true, 340.0, [], 112.0))
		# Alpha-cutout canopies into a 90 m shadow cascade is not worth the
		# samples; the trunks still ground each tree.
		holder.add_child(FoliageBaker.create_chunked_instances(
			tree["leaf"], partners[index], transforms, false, 340.0, [], 112.0))


## Cluster centres on the outfield, from just behind the wall to the near ridge.
func _tree_clusters() -> Array[Vector3]:
	var clusters: Array[Vector3] = []
	for i in 13:
		var angle: float = TAU * float(i) / 13.0 + _rng.randf_range(-0.14, 0.14)
		var radius: float = _rng.randf_range(78.0, 138.0)
		clusters.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	return clusters


## Kenney pines scale off their own bounds, so the tree line gets a conifer
## silhouette blend without a second procedural tree build.
func _conifer_line() -> void:
	var mesh: ArrayMesh = FoliageBaker.bake("tree_pineTallA")
	if mesh == null:
		return
	var bounds: AABB = mesh.get_aabb()
	var unit: float = 13.5 / maxf(bounds.size.y, 0.01)
	var transforms: Array = []
	for i in 90:
		var angle: float = TAU * _rng.randf()
		var radius: float = _rng.randf_range(92.0, 160.0)
		var scale: float = unit * _rng.randf_range(0.75, 1.5)
		var point := Vector3(cos(angle) * radius,
			-0.06 - bounds.position.y * scale, sin(angle) * radius)
		transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU)
			.scaled(Vector3.ONE * scale), point))
	var holder: Node3D = FoliageBaker.create_chunked_instances(mesh,
		FoliageBaker.make_material(), transforms, false, 340.0, [], 112.0)
	holder.name = "ParkConifers"
	add_child(holder)


## Bushes along the wall verge, the paddocks and the pond bank. Soft cover, so
## driving through one is harmless; placement still avoids every driving line.
func _bushes(material: Material) -> void:
	var transforms: Array = []
	var colors: Array = []
	for i in 320:
		var point := Vector3(_rng.randf_range(-64.0, 64.0), 0.0,
			_rng.randf_range(-64.0, 64.0))
		if _blocked(point, 1.2):
			continue
		point.y = _terrain_h(point.x, point.z)
		transforms.append(_bush_transform(point))
		colors.append(_tint())
	# Verge ring: a continuous green band under the wall hides its footing.
	for i in 90:
		var angle: float = TAU * _rng.randf()
		var radius: float = _rng.randf_range(62.5, 67.0)
		var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if _on_apron(Vector2(point.x, point.z)):
			continue
		if point.distance_to(Vector3(POND_CENTER.x, 0.0, POND_CENTER.y)) < POND_R + 1.0:
			continue
		point.y = _terrain_h(point.x, point.z)
		transforms.append(_bush_transform(point))
		colors.append(_tint())
	# Pond bank.
	for i in 22:
		var angle: float = TAU * float(i) / 22.0 + _rng.randf_range(-0.12, 0.12)
		var radius: float = _rng.randf_range(POND_R * 0.72, POND_R * 0.95)
		var point := Vector3(POND_CENTER.x + cos(angle) * radius, 0.0,
			POND_CENTER.y + sin(angle) * radius)
		point.y = _terrain_h(point.x, point.z)
		transforms.append(_bush_transform(point))
		colors.append(_tint())
	_scatter_layer("ParkBushes", ["plant_bush", "plant_bushLarge"], transforms,
		material, false, 95.0, colors, 96.0)


func _bush_transform(point: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _rng.randf() * TAU)
		.scaled(Vector3.ONE * _rng.randf_range(0.7, 1.7)), point)


## Two flower models only: they are tiny, so the draw calls matter more than
## the variety.
func _flowers(material: Material) -> void:
	var transforms: Array = []
	for i in 320:
		var point := Vector3(_rng.randf_range(-64.0, 64.0), 0.0,
			_rng.randf_range(-64.0, 64.0))
		if _blocked(point, 1.0):
			continue
		point.y = _terrain_h(point.x, point.z)
		transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU)
			.scaled(Vector3.ONE * _rng.randf_range(0.6, 1.1)), point))
	# ~70 m visibility and one chunk: two draw calls for the whole flower coat.
	_scatter_layer("ParkFlowers", ["flower_purpleA", "flower_yellowA"],
		transforms, material, false, 72.0, [], 999.0)


## Wind-blown grass cards hugging every driving line, plus reeds in the pond.
## One MultiMesh layer with a short visibility range, so the cost stays at a
## couple of draw calls no matter where the camera looks.
func _grass_tufts() -> void:
	var material: ShaderMaterial = _wind_material("grass_card",
		Color(0.84, 1.0, 0.74), 0.95, 0.13, 1.9)
	var mesh: ArrayMesh = _grass_clump(0.95, 3)
	var transforms: Array = []
	# Outer lip of the ring road: the view most laps are looking at.
	for i in 280:
		var angle: float = TAU * _rng.randf()
		var radius: float = _rng.randf_range(59.0, 63.5)
		var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if _blocked(point, 0.5):
			continue
		point.y = _terrain_h(point.x, point.z) + 0.02
		transforms.append(_grass_transform(point))
	# Both sides of the main straight.
	for i in 150:
		var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
		var point := Vector3(_rng.randf_range(6.4, 9.6) * side, 0.0,
			_rng.randf_range(-12.0, 50.0))
		point.y = _terrain_h(point.x, point.z) + 0.02
		transforms.append(_grass_transform(point))
	# Start apron edges.
	for i in 80:
		var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
		var point := Vector3(_rng.randf_range(17.6, 21.5) * side, 0.0,
			_rng.randf_range(51.0, 69.0))
		point.y = _terrain_h(point.x, point.z) + 0.02
		transforms.append(_grass_transform(point))
	# Reeds standing in the shallows, then a taller fringe on the bank.
	for i in 34:
		var angle: float = TAU * float(i) / 34.0 + _rng.randf_range(-0.1, 0.1)
		var radius: float = _rng.randf_range(7.6, 9.6)
		var point := Vector3(POND_CENTER.x + cos(angle) * radius, 0.0,
			POND_CENTER.y + sin(angle) * radius)
		point.y = _terrain_h(point.x, point.z) + 0.02
		transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU)
			.scaled(Vector3.ONE * _rng.randf_range(1.5, 2.4)), point))
	var holder: Node3D = FoliageBaker.create_chunked_instances(mesh, material,
		transforms, false, 58.0, [], 64.0)
	holder.name = "ParkGrass"
	add_child(holder)


func _grass_transform(point: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _rng.randf() * TAU)
		.scaled(Vector3.ONE * _rng.randf_range(0.6, 1.35)), point)


## Boulders: two faceted rock meshes instanced everywhere the park needs rock.
## Shore stones, corner outcrops, the wall verge and the outfield scree at the
## foot of the ridgelines all share the same two draw calls.
func _rocks() -> void:
	var xf_a: Array = []
	var xf_b: Array = []
	# Pond shore, some half in the water.
	for i in 14:
		var angle: float = TAU * float(i) / 14.0 + _rng.randf_range(-0.15, 0.15)
		var radius: float = _rng.randf_range(6.4, 10.2)
		var point := Vector3(POND_CENTER.x + cos(angle) * radius, 0.0,
			POND_CENTER.y + sin(angle) * radius)
		point.y = _terrain_h(point.x, point.z)
		_add_rock(xf_a, xf_b, point, _rng.randf_range(0.5, 1.25))
	# Corner outcrops, tucked into the paddocks. The centres are far enough out
	# that the 6 m jitter can never reach the ring road.
	var outcrops: Array[Vector2] = [
		Vector2(48.0, -52.0), Vector2(-48.0, 50.0),
		Vector2(60.0, 32.0), Vector2(-62.0, 26.0),
	]
	for centre: Vector2 in outcrops:
		for i in 6:
			var offset := Vector2(_rng.randf_range(-6.0, 6.0), _rng.randf_range(-6.0, 6.0))
			var point := Vector3(centre.x + offset.x, 0.0, centre.y + offset.y)
			point.y = _terrain_h(point.x, point.z)
			_add_rock(xf_a, xf_b, point, _rng.randf_range(0.9, 2.2))
	# Wall verge.
	for i in 26:
		var angle: float = TAU * float(i) / 26.0 + _rng.randf_range(-0.08, 0.08)
		var radius: float = _rng.randf_range(63.5, 67.5)
		var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if _on_apron(Vector2(point.x, point.z)):
			continue
		if point.distance_to(Vector3(POND_CENTER.x, 0.0, POND_CENTER.y)) < POND_R + 1.0:
			continue
		point.y = _terrain_h(point.x, point.z)
		_add_rock(xf_a, xf_b, point, _rng.randf_range(0.5, 1.4))
	# Scree at the foot of the near ridgeline (outfield, visual only).
	for i in 30:
		var angle: float = TAU * _rng.randf()
		var radius: float = _rng.randf_range(110.0, 145.0)
		var point := Vector3(cos(angle) * radius, -0.1, sin(angle) * radius)
		_add_rock(xf_a, xf_b, point, _rng.randf_range(1.2, 2.8))
	_batch("ParkBoulders", _rock_mesh(1337, 9, 5), _vertex_mat, xf_a, false)
	_batch("ParkStones", _rock_mesh(2711, 8, 4), _vertex_mat, xf_b, false)


func _add_rock(xf_a: Array, xf_b: Array, point: Vector3, scale: float) -> void:
	var basis := Basis(Vector3.UP, _rng.randf() * TAU)
	basis = basis.scaled(Vector3(scale, scale * _rng.randf_range(0.6, 0.95), scale))
	var xform := Transform3D(basis, point + Vector3.UP * scale * 0.35)
	if _rng.randf() < 0.5:
		xf_a.append(xform)
	else:
		xf_b.append(xform)


## Faceted boulder: a UV sphere pushed around by a hash, then flat-shaded.
## ~90 triangles, so a hundred of them is cheaper than one tree.
func _rock_mesh(seed_value: int, radial: int, rings: int) -> ArrayMesh:
	_geo_begin()
	var points: Array[Vector3] = []
	for ring in rings + 1:
		var phi: float = PI * float(ring) / float(rings)
		for j in radial:
			var theta: float = TAU * float(j) / float(radial)
			var dir := Vector3(sin(phi) * cos(theta), cos(phi),
				sin(phi) * sin(theta))
			var wobble: float = 0.74 + 0.34 * _hash01(seed_value + ring * 31 + j * 7)
			points.append(dir * wobble)
	var base := Color(0.53, 0.52, 0.47)
	for ring in rings:
		for j in radial:
			var jn: int = (j + 1) % radial
			var a: int = ring * radial + j
			var b: int = ring * radial + jn
			var c: int = (ring + 1) * radial + j
			var d: int = (ring + 1) * radial + jn
			var shade: float = 0.84 + 0.30 * _hash01(seed_value + ring * 17 + j * 53)
			var color := Color(base.r * shade, base.g * shade, base.b * shade)
			# The mesh is centred on the origin, so the centroid is the way out.
			_geo_tri(points[a], points[b], points[c], color,
				(points[a] + points[b] + points[c]) / 3.0)
			_geo_tri(points[b], points[d], points[c], color,
				(points[b] + points[d] + points[c]) / 3.0)
	return _geo_mesh()


## One material per foliage card sheet, shared by every instance of that layer.
func _wind_material(card: String, tint: Color, sway_height: float,
		strength: float, speed: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/materials/foliage_wind.gdshader") as Shader
	mat.set_shader_parameter("card_tex",
		load("res://assets/textures/foliage/" + card + ".png"))
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("sway_height", sway_height)
	mat.set_shader_parameter("wind_strength", strength)
	mat.set_shader_parameter("wind_speed", speed)
	mat.set_shader_parameter("alpha_cutoff", 0.42)
	# No kart-bend: that uniform would have to be pushed every frame, and the
	# park's grass sits outside the lines the carts actually drive.
	mat.set_shader_parameter("bend_radius", 0.0)
	mat.set_shader_parameter("bend_strength", 0.0)
	return mat


## Crossed alpha cards: a tuft that reads from every angle for 6 triangles.
func _grass_clump(size: float, count: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var half: float = size * 0.5
	for c in count:
		var basis := Basis(Vector3.UP, PI * float(c) / float(count))
		var base: int = verts.size()
		for corner: Vector2 in [Vector2(-half, 0.0), Vector2(half, 0.0),
				Vector2(half, size), Vector2(-half, size)]:
			verts.append(basis * Vector3(corner.x, corner.y, 0.0))
			norms.append(Vector3.UP)
		uvs.append(Vector2(0.0, 1.0))
		uvs.append(Vector2(1.0, 1.0))
		uvs.append(Vector2(1.0, 0.0))
		uvs.append(Vector2(0.0, 0.0))
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _scatter_layer(layer_name: String, models: Array, transforms: Array,
		material: Material, shadows: bool, view_end: float, colors: Array,
		chunk: float = 48.0) -> void:
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
			mesh, material, buckets[key]["xf"], shadows, view_end,
			buckets[key]["col"], chunk))


func _tint() -> Color:
	return Color(_rng.randf_range(0.55, 0.85), _rng.randf_range(0.7, 0.95),
		_rng.randf_range(0.5, 0.75))


# --------------------------------------------------------------------------
# horizon: layered ridgelines, flat-topped buttes, backdrop mountains
#
# All of it merges into two vertex-coloured meshes, so the entire far view is
# two draw calls. The silhouettes do the work and the fog does the fading:
# nothing here is tessellated enough to need LOD.


func _horizon() -> void:
	_geo_begin()
	# Three ridgelines, each paler than the one in front. The baked colour
	# gradient means the depth still reads on a device where fog is cheap. The
	# near flank starts at 140 m, beyond the tree line, so it never swallows the
	# forest it is supposed to sit behind.
	_ridge_ring(190.0, 50.0, 26.0, 96,
		Color(0.19, 0.28, 0.21), Color(0.33, 0.44, 0.32))
	_ridge_ring(320.0, 92.0, 62.0, 72,
		Color(0.24, 0.33, 0.36), Color(0.42, 0.52, 0.55))
	_ridge_ring(640.0, 180.0, 132.0, 48,
		Color(0.42, 0.52, 0.62), Color(0.62, 0.71, 0.79))
	_geo_commit("HorizonRidges", _horizon_mat, false)
	_geo_begin()
	# Flat-topped buttes standing on the ridgelines.
	_butte(Vector2(118.0, 62.0), 22.0, 20.0, 11)
	_butte(Vector2(-150.0, -20.0), 26.0, 26.0, 23)
	_butte(Vector2(-40.0, 175.0), 30.0, 32.0, 37)
	_butte(Vector2(60.0, -190.0), 24.0, 24.0, 41)
	_butte(Vector2(200.0, 40.0), 28.0, 34.0, 53)
	_butte(Vector2(-190.0, 120.0), 32.0, 38.0, 67)
	_butte(Vector2(10.0, 260.0), 20.0, 18.0, 71)
	_geo_commit("HorizonButtes", _horizon_mat, false)
	Backdrop.add_mountains(self, _rng, 10)
	Backdrop.add_clouds(self, _rng, 16)


## One closed ridgeline ring. `foot` is how far the flank runs in from the
## crest; the base sits RIDGE_BASE under the outfield so no seam can show.
func _ridge_ring(radius: float, foot: float, height: float, segments: int,
		base_color: Color, crest_color: Color) -> void:
	var phase_a: float = _rng.randf() * TAU
	var phase_b: float = _rng.randf() * TAU
	var phase_c: float = _rng.randf() * TAU
	var front: Array[Vector3] = []
	var shoulder: Array[Vector3] = []
	var crest: Array[Vector3] = []
	var back: Array[Vector3] = []
	for i in segments:
		var angle: float = TAU * float(i) / float(segments)
		var noise: float = clampf(0.5 + 0.5 * (
			0.52 * sin(angle * 2.0 + phase_a)
			+ 0.30 * sin(angle * 5.0 + phase_b)
			+ 0.18 * sin(angle * 11.0 + phase_c)), 0.0, 1.0)
		var top: float = height * (0.30 + 0.70 * noise)
		var wobble: float = 1.0 + 0.045 * sin(angle * 4.0 + phase_b)
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		front.append(dir * (radius - foot) + Vector3.DOWN * RIDGE_BASE)
		shoulder.append(dir * (radius - foot * 0.42) + Vector3.UP * (top * 0.46))
		crest.append(dir * radius * wobble + Vector3.UP * top)
		back.append(dir * (radius + foot * 0.85) + Vector3.DOWN * RIDGE_BASE)
	var mid_color: Color = base_color.lerp(crest_color, 0.45)
	for i in segments:
		var j: int = (i + 1) % segments
		var facing: Vector3 = -(crest[i] + crest[j]) * 0.5
		facing.y = 0.0
		facing = facing.normalized()
		_geo_ramp_quad(front[i], front[j], shoulder[j], shoulder[i],
			base_color, mid_color, facing)
		_geo_ramp_quad(shoulder[i], shoulder[j], crest[j], crest[i],
			mid_color, crest_color, facing)
		_geo_ramp_quad(crest[i], crest[j], back[j], back[i],
			crest_color, base_color, -facing)


## Flat-topped butte: wobbled rim, talus skirt and a flat cap.
func _butte(centre: Vector2, radius: float, height: float, seed_value: int) -> void:
	var segments: int = 24
	var phase: float = _hash01(seed_value) * TAU
	var rim: Array[Vector3] = []
	var mid: Array[Vector3] = []
	var foot: Array[Vector3] = []
	for i in segments:
		var angle: float = TAU * float(i) / float(segments)
		var wobble: float = 1.0 + 0.09 * sin(angle * 3.0 + phase) \
			+ 0.05 * sin(angle * 7.0 + phase * 1.7)
		var top: float = height * (1.0 + 0.018 * sin(angle * 5.0 + phase))
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		rim.append(Vector3(centre.x, top, centre.y) + dir * radius * wobble)
		mid.append(Vector3(centre.x, height * 0.5, centre.y)
			+ dir * radius * wobble * 1.18)
		foot.append(Vector3(centre.x, -RIDGE_BASE, centre.y)
			+ dir * radius * wobble * 1.55)
	var rock_lo := Color(0.34, 0.33, 0.30)
	var rock_hi := Color(0.63, 0.55, 0.44)
	var cap := Color(0.52, 0.53, 0.36)
	var rock_mid: Color = rock_lo.lerp(rock_hi, 0.4)
	for i in segments:
		var j: int = (i + 1) % segments
		var facing := Vector3(rim[i].x - centre.x, 0.0, rim[i].z - centre.y).normalized()
		_geo_ramp_quad(foot[i], foot[j], mid[j], mid[i], rock_lo, rock_mid, facing)
		_geo_ramp_quad(mid[i], mid[j], rim[j], rim[i], rock_mid, rock_hi, facing)
		_geo_tri(Vector3(centre.x, height, centre.y), rim[i], rim[j], cap)


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


# --------------------------------------------------------------------------
# atmosphere


## Distance haze for the layered horizon. VisualGrade deliberately leaves the
## sandbox unfogged, so this only fills the gap when nobody else has: a later
## shared look pass keeps control if it decides the park should have fog.
func _apply_horizon_fog() -> void:
	var world: World3D = get_world_3d()
	if world == null:
		return
	var env: Environment = world.environment
	if env == null or env.fog_enabled:
		return
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color("bfe9ff")
	env.fog_light_energy = 0.9
	# Light enough that the bowl and the ring markings stay crisp at 60 m, deep
	# enough that the 640 m ridgeline melts into the sky.
	env.fog_density = HORIZON_FOG_DENSITY
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.15
