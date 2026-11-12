extends Node3D
## Circuit TEST FACILITY for the sandbox, built around one central paddock.
##
## The old park was scenery with driving lines threaded through it. This is the
## opposite: five zones, each with one job, all reached from the concrete pad in
## the middle.
##   - PADDOCK: concrete spawn apron, painted grid slots, pit-building facade,
##     parked karts, tyre stacks and four floodlights.
##   - HANDLING LOOP: a closed 158 m tarmac circuit with kerbs, outside armco, a
##     start gantry and a boost pad, so a lap can be timed.
##   - SKIDPAD: a 26 m painted concrete circle with rings, quadrant lines and a
##     timing gantry, for drift work.
##   - JUMP LANE: two solid kickers in a line, a long landing apron and distance
##     boards.
##   - OFF-ROAD: a dirt strip with a cone slalom and a grip area that actually
##     drops the kart's surface grip, so the change is felt and not just seen.
##
## The terrain is flat and is the ONE terrain collider: a single
## ConcavePolygonShape3D. Pavements are merged, flush visual layers lying on that
## solid ground, one shared material per surface (asphalt_02, worn concrete,
## dirt), so they add no collision step and no extra draw calls. Every structure
## - pit building, ramps, sign posts, parked karts, tyre stacks - carries a real
## WORLD-layer collider, and nothing decorative is left in a driving line.
##
## Racing furniture (kerbs, armco, gantry, tyre walls, floodlights) comes from
## RacingKit so the sandbox matches the race maps. Trees live outside the
## perimeter wall only; the skyline is the shared backdrop.

const RacingKit := preload("res://scripts/minigames/racing_kit.gd")
const TrackSpline := preload("res://scripts/minigames/track_spline.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const FoliageBaker := preload("res://scripts/minigames/foliage_baker.gd")
const RealisticTree := preload("res://scripts/minigames/realistic_tree.gd")
const Backdrop := preload("res://scripts/systems/backdrop.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

const BOOST_PAD_SCENE: String = "res://scenes/track/boost_pad.tscn"
const CONE_MODEL: String = "res://assets/models/kenney_car-kit/Models/GLB format/cone.glb"
const CRATE_MODEL: String = "res://assets/models/kenney_car-kit/Models/GLB format/box.glb"
const PBR_SHADER: String = "res://assets/materials/ground_pbr.gdshader"
const PBR_TEX: String = "res://assets/textures/polyhaven/"
const TITLE_FONT: String = "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"

# World
const FIELD: float = 70.0
const WALL_H: float = 6.5
const WALL_T: float = 1.5
const GRID: int = 24

# Zone layout. Every rectangle is x/z metres in park space.
const PADDOCK_RECT := Rect2(-32.0, 0.0, 54.0, 20.0)
const PIT_RECT := Rect2(-32.0, 2.0, 7.0, 12.0)
const SKID_CENTRE := Vector2(50.0, 12.0)
const SKID_RADIUS: float = 13.0
const LOOP_CENTRE := Vector2(0.0, -38.0)
const LOOP_GAP: float = 18.0
const LANE_X: float = -52.0
const LANE_HALF: float = 4.5
const LANE_START_Z: float = 32.0
const LANE_END_Z: float = -44.0
const RAMP_WIDTH: float = 9.0
const RAMP_RISE: float = 2.4
const RAMP_A_BASE_Z: float = 14.0
const RAMP_A_LIP_Z: float = 6.0
const RAMP_B_BASE_Z: float = -6.0
const RAMP_B_LIP_Z: float = -14.0
const DIRT_RECT := Rect2(-26.0, 24.0, 52.0, 38.0)
const DIRT_GRIP: float = 0.72

# Layer heights. The loop road matches RacingKit.ROAD_Y so its kerbs sit flush;
# links sit a hair lower and paint on top, so nothing z-fights where they meet.
const APRON_Y: float = 0.02
const LINK_Y: float = 0.032
const ROAD_Y: float = RacingKit.ROAD_Y
const MARK_Y: float = 0.05

# Colours
const PAINT_CREAM := Color("fff6e3")
const PAINT_YELLOW := Color("ffd22e")
const PAINT_PINK := Color("f26ca7")
const PAINT_BLUE := Color("45b6f0")
const PAINT_ORANGE := Color("ff9f45")
const PAINT_DARK := Color("1e1b3a")
const RAMP_FACE := Color("3b3f46")
const RAMP_SIDE := Color("2a2d33")
const WALL_GREY := Color("7b8087")
const KART_COLOURS: Array[Color] = [
	Color("e4572e"), Color("2e86ab"), Color("f6c945"),
]


## One merged, flat pavement or paint layer.
##
## Every triangle is forced to face up, so a zone builder never has to reason
## about winding: it hands over points and gets a drivable slab back. All the
## pieces for one material share this buffer, which is why the whole park needs
## only three pavement meshes and one paint mesh.
class SurfaceBuf:
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()

	## Adds one up-facing triangle; swaps two points when the winding is down.
	func tri(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
		if (b - a).cross(c - a).y < 0.0:
			var swap: Vector3 = b
			b = c
			c = swap
		var base: int = verts.size()
		for point: Vector3 in [a, b, c]:
			verts.append(point)
			normals.append(Vector3.UP)
			uvs.append(Vector2(point.x, point.z))
			colors.append(color)
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)

	## Adds one up-facing quad as two triangles.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
			color: Color) -> void:
		tri(a, b, c, color)
		tri(a, c, d, color)

	## Adds an axis-aligned rectangle at height `y`.
	func rect(area: Rect2, y: float, color: Color) -> void:
		var x0: float = area.position.x
		var z0: float = area.position.y
		var x1: float = area.end.x
		var z1: float = area.end.y
		quad(Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1),
			Vector3(x1, y, z0), color)

	## Adds a filled circle at height `y`.
	func disc(centre: Vector2, radius: float, segments: int, y: float,
			color: Color) -> void:
		var count: int = maxi(segments, 8)
		for i in count:
			var a0: float = TAU * float(i) / float(count)
			var a1: float = TAU * float(i + 1) / float(count)
			tri(Vector3(centre.x, y, centre.y),
				Vector3(centre.x + cos(a0) * radius, y,
					centre.y + sin(a0) * radius),
				Vector3(centre.x + cos(a1) * radius, y,
					centre.y + sin(a1) * radius), color)

	## Adds a flat annulus at height `y`.
	func ring(centre: Vector2, r_in: float, r_out: float, segments: int,
			y: float, color: Color) -> void:
		var count: int = maxi(segments, 8)
		for i in count:
			var a0: float = TAU * float(i) / float(count)
			var a1: float = TAU * float(i + 1) / float(count)
			var c0: float = cos(a0)
			var s0: float = sin(a0)
			var c1: float = cos(a1)
			var s1: float = sin(a1)
			quad(Vector3(centre.x + c0 * r_in, y, centre.y + s0 * r_in),
				Vector3(centre.x + c0 * r_out, y, centre.y + s0 * r_out),
				Vector3(centre.x + c1 * r_out, y, centre.y + s1 * r_out),
				Vector3(centre.x + c1 * r_in, y, centre.y + s1 * r_in), color)

	## Adds a flat line of `width` metres between two ground points.
	func line(from: Vector2, to: Vector2, width: float, y: float,
			color: Color) -> void:
		var direction: Vector2 = to - from
		if direction.length_squared() < 0.000001:
			return
		direction = direction.normalized()
		var offset: Vector2 = Vector2(-direction.y, direction.x) * (width * 0.5)
		quad(Vector3(from.x - offset.x, y, from.y - offset.y),
			Vector3(from.x + offset.x, y, from.y + offset.y),
			Vector3(to.x + offset.x, y, to.y + offset.y),
			Vector3(to.x - offset.x, y, to.y - offset.y), color)

	## Adds a road ribbon around the whole spline, offset by `centre`.
	func ribbon(spline: RefCounted, centre: Vector2, half_width: float, y: float,
			color: Color, steps: int = 140) -> void:
		var total: float = maxf(spline.total_length, 0.001)
		var count: int = maxi(steps, 8)
		for i in count:
			var f0: Dictionary = spline.sample(total * float(i) / float(count))
			var f1: Dictionary = spline.sample(total * float(i + 1) / float(count))
			var p0: Vector3 = f0["position"]
			var p1: Vector3 = f1["position"]
			var r0: Vector3 = f0["right"]
			var r1: Vector3 = f1["right"]
			quad(
				Vector3(p0.x + centre.x - r0.x * half_width, y,
					p0.z + centre.y - r0.z * half_width),
				Vector3(p0.x + centre.x + r0.x * half_width, y,
					p0.z + centre.y + r0.z * half_width),
				Vector3(p1.x + centre.x + r1.x * half_width, y,
					p1.z + centre.y + r1.z * half_width),
				Vector3(p1.x + centre.x - r1.x * half_width, y,
					p1.z + centre.y - r1.z * half_width), color)


var _rng := RandomNumberGenerator.new()
var _font: Font

var _asphalt: SurfaceBuf = SurfaceBuf.new()
var _concrete: SurfaceBuf = SurfaceBuf.new()
var _dirt: SurfaceBuf = SurfaceBuf.new()
var _marks: SurfaceBuf = SurfaceBuf.new()

var _structs: PropBatch = PropBatch.new()
var _paddock_solids: Array = []
var _jump_solids: Array = []
var _skidpad_solids: Array = []
var _sign_solids: Array = []
var _tyre_positions: Array[Vector3] = []
var _grip_before: Dictionary = {}

var _grass_mat: ShaderMaterial
var _dirt_mat: ShaderMaterial
var _asphalt_mat: Material
var _concrete_mat: Material
var _vertex_mat: StandardMaterial3D
var _rubber_mat: StandardMaterial3D
var _yellow_mat: StandardMaterial3D
var _prop_material: PhysicsMaterial


func _ready() -> void:
	_rng.seed = 90421
	_font = load(TITLE_FONT) as Font
	_make_materials()
	_terrain()
	_paddock()
	_handling_loop()
	_skidpad()
	_jump_lane()
	_offroad()
	_perimeter()
	_scenery()
	_backdrop()
	_pushable_props()
	_grip_zone()
	_commit_facility()


# --------------------------------------------------------------------------
# materials
#
# One material per surface, shared by every piece of that surface. The tarmac
# and concrete helpers fall back to an honest flat tone when a checkout has not
# run the Godot importer yet, exactly like RacingKit's palette does: the prop is
# then still usable in a headless boot and picks the scan back up in a build.


## Builds the shared surface materials once; no prop owns a duplicate.
func _make_materials() -> void:
	_grass_mat = _pbr("grass_diff", "grass_nor", "grass_rough", 0.22,
		Color(0.74, 0.92, 0.62), 0.08, 0.05)
	_dirt_mat = _pbr("dirt_diff", "dirt_nor", "dirt_rough", 0.35,
		Color(0.98, 0.80, 0.56), 0.10, 0.04)
	_asphalt_mat = _scanned_material("asphalt_02_diff", "asphalt_02_nor",
		"asphalt_02_rough", 0.13, Color(0.80, 0.82, 0.86), 0.10, 0.035,
		Color(0.27, 0.28, 0.31))
	_concrete_mat = RacingKit.palette()["concrete"] as Material
	_vertex_mat = _make_vertex_material(false)
	_rubber_mat = StandardMaterial3D.new()
	_rubber_mat.albedo_color = Color(0.16, 0.17, 0.20)
	_rubber_mat.roughness = 1.0
	_yellow_mat = StandardMaterial3D.new()
	_yellow_mat.albedo_color = PAINT_YELLOW
	_yellow_mat.roughness = 0.8


## Shared vertex-coloured material for merged structures and painted marks.
func _make_vertex_material(two_sided: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if two_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## PBR material for a Poly Haven scan that is already imported.
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


## PBR material for a Poly Haven scan that may not be imported yet. The source
## checkout has the JPGs but not always their .import sidecars, so the fallback
## keeps a cold headless boot free of loader errors.
func _scanned_material(diff: String, nor: String, rough: String,
		uv_scale: float, tint: Color, detail: float, macro: float,
		fallback_color: Color) -> Material:
	var diff_path: String = PBR_TEX + diff + ".jpg"
	var nor_path: String = PBR_TEX + nor + ".jpg"
	var rough_path: String = PBR_TEX + rough + ".jpg"
	if not (ResourceLoader.exists(diff_path) and ResourceLoader.exists(nor_path)
			and ResourceLoader.exists(rough_path)):
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = fallback_color
		fallback.roughness = 0.94
		fallback.metallic = 0.0
		return fallback
	var mat := ShaderMaterial.new()
	mat.shader = load(PBR_SHADER) as Shader
	mat.set_shader_parameter("albedo_tex", load(diff_path))
	mat.set_shader_parameter("normal_tex", load(nor_path))
	mat.set_shader_parameter("rough_tex", load(rough_path))
	mat.set_shader_parameter("uv_scale", uv_scale)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("detail_strength", detail)
	mat.set_shader_parameter("macro_variation", macro)
	mat.set_shader_parameter("roughness_min", 0.55)
	return mat


# --------------------------------------------------------------------------
# ground: one flat heightfield, one terrain collider, one grass material


## Flat heightfield, the single terrain collider, grass outfield and safe net.
func _terrain() -> void:
	var cell: float = (FIELD * 2.0) / float(GRID)
	var side: int = GRID + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize(side * side)
	norms.resize(side * side)
	uvs.resize(side * side)
	for i in side:
		var x: float = -FIELD + float(i) * cell
		for j in side:
			var z: float = -FIELD + float(j) * cell
			var index: int = i * side + j
			verts[index] = Vector3(x, 0.0, z)
			norms[index] = Vector3.UP
			uvs[index] = Vector2(x, z)
	for i in GRID:
		for j in GRID:
			var v00: int = i * side + j
			var v10: int = (i + 1) * side + j
			var v01: int = i * side + j + 1
			var v11: int = (i + 1) * side + j + 1
			indices.append_array([v00, v01, v10, v10, v01, v11])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_arrays(verts, norms, uvs, indices))
	var ground := MeshInstance3D.new()
	ground.name = "FacilityGround"
	ground.mesh = mesh
	ground.material_override = _grass_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	# The one terrain collider. Nothing else in the park is a concave terrain
	# shape; every raised prop is a box, cylinder or convex wedge.
	var faces := PackedVector3Array()
	for k in range(0, indices.size(), 3):
		faces.append(verts[indices[k]])
		faces.append(verts[indices[k + 1]])
		faces.append(verts[indices[k + 2]])
	_static_faces("TerrainCollision", faces)
	# Grass outfield beyond the wall. Four quads, so the far view costs one
	# draw call and never cuts a hole in the facility ground.
	var outfield := SurfaceBuf.new()
	var inner: float = FIELD - 0.5
	var outer: float = 800.0
	var strips: Array[Rect2] = [
		Rect2(-outer, -outer, outer * 2.0, outer - inner),
		Rect2(-outer, inner, outer * 2.0, outer - inner),
		Rect2(-outer, -inner, outer - inner, inner * 2.0),
		Rect2(inner, -inner, outer - inner, inner * 2.0),
	]
	for strip: Rect2 in strips:
		outfield.rect(strip, -0.08, Color.WHITE)
	var outfield_mesh: ArrayMesh = _mesh_from_buffer(outfield)
	if outfield_mesh != null:
		var outfield_instance := MeshInstance3D.new()
		outfield_instance.name = "Outfield"
		outfield_instance.mesh = outfield_mesh
		outfield_instance.material_override = _grass_mat
		outfield_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(outfield_instance)
	# Safety net well below the flat ground; no overlap with the terrain.
	var body := StaticBody3D.new()
	body.name = "GroundNet"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(FIELD * 2.0, 2.0, FIELD * 2.0)
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position = Vector3(0.0, -6.0, 0.0)
	body.add_child(collision)
	add_child(body)


# --------------------------------------------------------------------------
# zone 1: PADDOCK


## Zone 1: concrete apron, grid, pit facade, parked karts, stacks and lights.
func _paddock() -> void:
	_concrete.rect(PADDOCK_RECT, APRON_Y, Color.WHITE)
	# Apron edge line, so the concrete reads as a made surface from the seat.
	var inset: float = 0.6
	var border := PADDOCK_RECT.grow(-inset)
	_marks.line(border.position, Vector2(border.end.x, border.position.y), 0.16,
		MARK_Y, PAINT_CREAM)
	_marks.line(Vector2(border.position.x, border.end.y), border.end, 0.16,
		MARK_Y, PAINT_CREAM)
	_marks.line(border.position, Vector2(border.position.x, border.end.y), 0.16,
		MARK_Y, PAINT_CREAM)
	_marks.line(Vector2(border.end.x, border.position.y), border.end, 0.16,
		MARK_Y, PAINT_CREAM)
	# Six painted grid slots, two rows of three. The local cart starts on slot 5.
	var slot: int = 1
	for row in 2:
		for column in 3:
			var centre := Vector2(-9.0 + float(column) * 9.0,
				5.0 + float(row) * 8.0)
			_paint_slot(centre)
			_grid_number(slot, centre)
			slot += 1
	_pit_building()
	# Three karts parked nose-in to the pit bays.
	for bay in 3:
		_parked_kart(Vector3(-22.2, APRON_Y, 4.0 + float(bay) * 4.0),
			PI * 0.5, KART_COLOURS[bay])
		_paint_bay(Vector2(-21.0, 4.0 + float(bay) * 4.0))
	# Tyre stacks line the pad edges and sit clear of the four service routes:
	# the apron stays a paddock, not an obstacle course.
	for spot: Vector2 in [Vector2(18.5, 1.5), Vector2(18.5, 5.5),
			Vector2(8.5, 18.5), Vector2(13.0, 18.5), Vector2(-19.0, 1.5),
			Vector2(-15.0, 1.5)]:
		_tyre_stack(Vector3(spot.x, APRON_Y, spot.y))
	_flush_tyre_stacks()
	# Four floodlight towers just outside the apron: emissive heads, no extra
	# dynamic lights, solid poles on WORLD.
	RacingKit.floodlight(self, Vector3(-38.0, 0.0, -4.0))
	RacingKit.floodlight(self, Vector3(28.0, 0.0, -4.0))
	RacingKit.floodlight(self, Vector3(-30.0, 0.0, 23.5))
	RacingKit.floodlight(self, Vector3(28.0, 0.0, 23.5))
	_solid_batch("PaddockSolids", _paddock_solids)


## Painted border of one start-grid slot.
func _paint_slot(centre: Vector2) -> void:
	var half := Vector2(2.1, 2.7)
	_marks.line(Vector2(centre.x - half.x, centre.y - half.y),
		Vector2(centre.x + half.x, centre.y - half.y), 0.18, MARK_Y, PAINT_CREAM)
	_marks.line(Vector2(centre.x - half.x, centre.y + half.y),
		Vector2(centre.x + half.x, centre.y + half.y), 0.18, MARK_Y, PAINT_CREAM)
	_marks.line(Vector2(centre.x - half.x, centre.y - half.y),
		Vector2(centre.x - half.x, centre.y + half.y), 0.18, MARK_Y, PAINT_CREAM)
	_marks.line(Vector2(centre.x + half.x, centre.y - half.y),
		Vector2(centre.x + half.x, centre.y + half.y), 0.18, MARK_Y, PAINT_CREAM)


## Painted outline of one pit bay.
func _paint_bay(centre: Vector2) -> void:
	_marks.line(Vector2(centre.x - 2.6, centre.y - 1.7),
		Vector2(centre.x + 1.8, centre.y - 1.7), 0.14, MARK_Y, PAINT_YELLOW)
	_marks.line(Vector2(centre.x - 2.6, centre.y + 1.7),
		Vector2(centre.x + 1.8, centre.y + 1.7), 0.14, MARK_Y, PAINT_YELLOW)
	_marks.line(Vector2(centre.x - 2.6, centre.y - 1.7),
		Vector2(centre.x - 2.6, centre.y + 1.7), 0.14, MARK_Y, PAINT_YELLOW)


## Big painted grid number, lying flat and readable from the south.
func _grid_number(number: int, centre: Vector2) -> void:
	var label := Label3D.new()
	label.name = "GridNumber%d" % number
	label.text = str(number)
	label.font = _font
	label.font_size = 128
	label.pixel_size = 0.011
	label.outline_size = 12
	label.outline_modulate = PAINT_DARK
	label.modulate = PAINT_CREAM
	label.position = Vector3(centre.x, MARK_Y + 0.005, centre.y - 1.9)
	label.rotation.x = -PI * 0.5
	add_child(label)


## Pit building facade on the west edge of the pad: masonry box, livery band,
## three dark garage bays and a roll-up slat pattern. One box collider covers
## the whole footprint, so no kart can enter a painted bay.
func _pit_building() -> void:
	var centre := Vector3(PIT_RECT.get_center().x, 2.6, PIT_RECT.get_center().y)
	_structs.add_box(Transform3D(Basis.IDENTITY, centre),
		Vector3(PIT_RECT.size.x, 5.2, PIT_RECT.size.y), Color("c9c4b6"))
	_structs.add_box(Transform3D(Basis.IDENTITY, centre + Vector3.UP * 2.72),
		Vector3(PIT_RECT.size.x + 0.6, 0.34, PIT_RECT.size.y + 0.6),
		Color("83817a"))
	var face_x: float = PIT_RECT.end.x
	# Every facade detail sits a few centimetres PROUD of the wall (east of it),
	# otherwise the building's own face hides it.
	_structs.add_box(Transform3D(Basis.IDENTITY, Vector3(face_x + 0.09, 4.45,
		PIT_RECT.get_center().y)), Vector3(0.18, 0.9, 10.0),
		Color("2f7d4f"))
	for bay in 3:
		var z: float = 4.0 + float(bay) * 4.0
		_structs.add_box(Transform3D(Basis.IDENTITY,
			Vector3(face_x + 0.06, 1.5, z)), Vector3(0.12, 3.0, 3.2),
			Color("17181c"))
		_structs.add_box(Transform3D(Basis.IDENTITY,
			Vector3(face_x + 0.10, 3.12, z)), Vector3(0.16, 0.4, 3.5),
			RacingKit.CREAM)
		for slat in 3:
			_structs.add_box(Transform3D(Basis.IDENTITY,
				Vector3(face_x + 0.11, 0.45 + float(slat) * 0.85, z)),
				Vector3(0.08, 0.10, 3.1), Color("d8cdb4"))
	var label := Label3D.new()
	label.name = "PitPaddockSign"
	label.text = "PADDOCK"
	label.font = _font
	label.font_size = 128
	label.pixel_size = 0.008
	label.outline_size = 14
	label.outline_modulate = PAINT_DARK
	label.modulate = PAINT_CREAM
	label.position = Vector3(face_x + 0.22, 4.45, PIT_RECT.get_center().y)
	label.rotation.y = PI * 0.5
	add_child(label)
	var shape := BoxShape3D.new()
	shape.size = Vector3(PIT_RECT.size.x + 0.2, 5.4, PIT_RECT.size.y + 0.2)
	_paddock_solids.append([shape, Transform3D(Basis.IDENTITY,
		centre)])


## A chunky parked kart built from shared primitives: chassis, nose, seat,
## wheels and one box collider, all in the merged structure mesh.
func _parked_kart(at: Vector3, yaw: float, tint: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_structs.add_box(Transform3D(basis, at + Vector3.UP * 0.52),
		Vector3(1.30, 0.46, 2.30), tint)
	_structs.add_box(Transform3D(basis, at + basis * Vector3(0.0, 0.46, -1.30)),
		Vector3(0.95, 0.30, 0.70), tint.darkened(0.2))
	_structs.add_box(Transform3D(basis, at + basis * Vector3(0.0, 0.88, 0.10)),
		Vector3(0.85, 0.50, 0.70), Color("20232a"))
	_structs.add_box(Transform3D(basis, at + basis * Vector3(0.0, 1.02, -0.50)),
		Vector3(0.50, 0.16, 0.42), RacingKit.CREAM)
	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			var wheel := Transform3D(basis * Basis(Vector3.BACK, PI * 0.5),
				at + basis * Vector3(side * 0.72, 0.32, end * 0.82))
			_structs.add_cylinder(wheel, 0.33, 0.30, 10, Color("141519"))
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.70, 1.20, 2.60)
	_paddock_solids.append([shape, Transform3D(basis, at + Vector3.UP * 0.62)])


## Tyre stack: three batched cylinders, one solid cylinder per stack.
func _tyre_stack(at: Vector3) -> void:
	_tyre_positions.append(at)


## Batches every tyre stack's rubber and yellow top tyres by material.
func _flush_tyre_stacks() -> void:
	if _tyre_positions.is_empty():
		return
	var tyre := CylinderMesh.new()
	tyre.top_radius = 0.6
	tyre.bottom_radius = 0.6
	tyre.height = 0.34
	tyre.radial_segments = 12
	tyre.rings = 1
	var baked: ArrayMesh = _mesh_to_array(tyre)
	var lower: Array = []
	var tops: Array = []
	for at: Vector3 in _tyre_positions:
		for level in 3:
			var xform := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU),
				at + Vector3.UP * (0.17 + float(level) * 0.34))
			if level == 2:
				tops.append(xform)
			else:
				lower.append(xform)
		var shape := CylinderShape3D.new()
		shape.radius = 0.6
		shape.height = 1.05
		_paddock_solids.append([shape, Transform3D(Basis.IDENTITY,
			at + Vector3.UP * 0.52)])
	_batch("TyreStacks", baked, _rubber_mat, lower, false)
	_batch("TyreStackTops", baked, _yellow_mat, tops, false)


# --------------------------------------------------------------------------
# zone 2: HANDLING LOOP


## Zone 2: spline oval with kit kerbs, outside armco and a timing gantry.
func _handling_loop() -> void:
	# A flat oval: 158 m round, wide enough to slide, tight enough to time a lap
	# in a few seconds. Generated by the same TrackSpline the race maps use.
	var preset: Dictionary = {
		"control_points": 20,
		"samples_per_segment": 10,
		"base_radius": 26.0,
		"lobe_a": 0.08,
		"lobe_b": 0.02,
		"lobe_c": 0.012,
		"lobe_d": 0.04,
		"stretch_x": 1.15,
		"stretch_z": 0.70,
		"elevation": [],
	}
	var spline = TrackSpline.new(preset)
	var holder := Node3D.new()
	holder.name = "HandlingLoop"
	holder.position = Vector3(LOOP_CENTRE.x, 0.0, LOOP_CENTRE.y)
	add_child(holder)
	var total: float = spline.total_length
	var entry: float = _loop_entry_distance(spline)
	_asphalt.ribbon(spline, LOOP_CENTRE, RacingKit.ROAD_HALF, ROAD_Y, Color.WHITE)
	# Kerbs both sides, armco outside only: the infield stays drivable so the
	# loop is never a cage for anything that starts inside it.
	var gap_half: float = LOOP_GAP * 0.5
	RacingKit.kerbs(holder, spline, entry + gap_half, entry + total - gap_half,
		1.0, RacingKit.TYRE_RED)
	RacingKit.kerbs(holder, spline, entry + gap_half, entry + total - gap_half,
		-1.0, RacingKit.TYRE_RED)
	RacingKit.barriers(holder, spline, entry + gap_half, entry + total - gap_half,
		-1.0)
	RacingKit.tyre_wall(holder, spline, entry + 62.0, -1.0, 8.0)
	RacingKit.tyre_wall(holder, spline, entry + 128.0, -1.0, 8.0)
	# Timing gantry and its painted start/finish band.
	var start_distance: float = entry + 26.0
	RacingKit.start_gantry(holder, spline, start_distance)
	_paint_loop_start(spline, start_distance)
	# Boost pad on the straight, aimed along the racing direction.
	var pad_frame: Dictionary = spline.sample(entry + 12.0)
	var pad_position: Vector3 = pad_frame["position"] + Vector3(LOOP_CENTRE.x,
		0.0, LOOP_CENTRE.y)
	_boost_pad(Vector3(pad_position.x, ROAD_Y, pad_position.z),
		pad_frame["forward"] as Vector3)
	# Paved link from the paddock pad into the loop's entry gap.
	_asphalt.rect(Rect2(-6.0, -23.0, 14.0, 23.0), LINK_Y, Color.WHITE)
	_marks.line(Vector2(-6.4, -14.0), Vector2(-6.4, -0.3), 0.20, MARK_Y,
		PAINT_CREAM)
	_marks.line(Vector2(8.4, -14.0), Vector2(8.4, -0.3), 0.20, MARK_Y,
		PAINT_CREAM)
	_zone_sign("HANDLING LOOP", Vector2(12.0, -10.0), 0.0, PAINT_BLUE)


## Distance along the spline whose world point is nearest the paddock gate.
func _loop_entry_distance(spline: RefCounted) -> float:
	var best: float = 0.0
	var best_distance: float = INF
	var total: float = maxf(spline.total_length, 0.001)
	for i in 360:
		var s: float = total * float(i) / 360.0
		var point: Vector3 = spline.sample(s)["position"]
		var offset := Vector2(point.x + LOOP_CENTRE.x, point.z + LOOP_CENTRE.y)
		var distance: float = offset.length()
		if distance < best_distance:
			best_distance = distance
			best = s
	return best


## Checker start/finish band across the loop at the gantry.
func _paint_loop_start(spline: RefCounted, distance: float) -> void:
	var before: Dictionary = spline.sample(distance - 0.9)
	var after: Dictionary = spline.sample(distance + 0.9)
	var pb: Vector3 = before["position"] + Vector3(LOOP_CENTRE.x, MARK_Y,
		LOOP_CENTRE.y)
	var pa: Vector3 = after["position"] + Vector3(LOOP_CENTRE.x, MARK_Y,
		LOOP_CENTRE.y)
	var rb: Vector3 = before["right"]
	var ra: Vector3 = after["right"]
	var half: float = RacingKit.ROAD_HALF
	for i in 12:
		var t0: float = -half + 2.0 * half * float(i) / 12.0
		var t1: float = -half + 2.0 * half * float(i + 1) / 12.0
		var shade: Color = PAINT_CREAM if i % 2 == 0 else PAINT_DARK
		_marks.quad(pb + rb * t0, pb + rb * t1, pa + ra * t1, pa + ra * t0, shade)


# --------------------------------------------------------------------------
# zone 3: SKIDPAD


## Zone 3: painted concrete circle with a timing gantry.
func _skidpad() -> void:
	_concrete.disc(SKID_CENTRE, SKID_RADIUS, 64, APRON_Y, Color.WHITE)
	# Concrete link from the pad's east edge: it runs under the circle rim by a
	# metre so the join never shows a sliver of grass.
	_concrete.rect(Rect2(PADDOCK_RECT.end.x - 0.5, SKID_CENTRE.y - 4.0,
		SKID_RADIUS + 7.0, 8.0), LINK_Y, Color.WHITE)
	_marks.ring(SKID_CENTRE, SKID_RADIUS - 0.75, SKID_RADIUS - 0.25, 72,
		MARK_Y, PAINT_CREAM)
	_marks.ring(SKID_CENTRE, 6.30, 6.75, 56, MARK_Y, PAINT_YELLOW)
	_marks.disc(SKID_CENTRE, 1.5, 24, MARK_Y, PAINT_PINK)
	for i in 4:
		var angle: float = TAU * float(i) / 4.0 + PI * 0.25
		var direction := Vector2(cos(angle), sin(angle))
		_marks.line(SKID_CENTRE + direction * 6.75,
			SKID_CENTRE + direction * (SKID_RADIUS - 0.75), 0.22, MARK_Y,
			PAINT_CREAM)
	# Timing line down the middle of the circle.
	for i in 10:
		var x0: float = SKID_CENTRE.x - SKID_RADIUS + float(i) \
			* (SKID_RADIUS * 2.0 / 10.0)
		_marks.rect(Rect2(x0, SKID_CENTRE.y - 0.55,
			SKID_RADIUS * 2.0 / 10.0, 1.1), MARK_Y,
			PAINT_CREAM if i % 2 == 0 else PAINT_DARK)
	_timing_gantry()
	_zone_sign("SKIDPAD", Vector2(36.5, 19.5), -PI * 0.5, PAINT_PINK)
	_solid_batch("SkidpadSolids", _skidpad_solids)


## Timing gantry on the north edge of the pad, facing the paddock. Two solid
## poles, a beam and an emissive-looking board, all in the merged structure mesh.
func _timing_gantry() -> void:
	var beam_z: float = SKID_CENTRE.y + SKID_RADIUS + 1.8
	for side: float in [-1.0, 1.0]:
		var x: float = SKID_CENTRE.x + side * 7.5
		_structs.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 2.4, beam_z)),
			Vector3(0.28, 4.8, 0.28), RacingKit.STEEL)
		_structs.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.14, beam_z)),
			Vector3(0.80, 0.28, 0.80), RacingKit.CONCRETE)
		var pole := BoxShape3D.new()
		pole.size = Vector3(0.42, 4.8, 0.42)
		_skidpad_solids.append([pole, Transform3D(Basis.IDENTITY,
			Vector3(x, 2.4, beam_z))])
	_structs.add_box(Transform3D(Basis.IDENTITY,
		Vector3(SKID_CENTRE.x, 4.85, beam_z)), Vector3(15.6, 0.30, 0.30),
		RacingKit.STEEL)
	_structs.add_box(Transform3D(Basis.IDENTITY,
		Vector3(SKID_CENTRE.x, 4.02, beam_z)), Vector3(7.0, 1.5, 0.18),
		Color("1c3b57"))
	var beam := BoxShape3D.new()
	beam.size = Vector3(15.6, 1.6, 0.3)
	_skidpad_solids.append([beam, Transform3D(Basis.IDENTITY,
		Vector3(SKID_CENTRE.x, 4.45, beam_z))])
	var label := Label3D.new()
	label.name = "SkidpadTimingSign"
	label.text = "SKIDPAD"
	label.font = _font
	label.font_size = 96
	label.pixel_size = 0.0075
	label.outline_size = 12
	label.outline_modulate = PAINT_DARK
	label.modulate = PAINT_CREAM
	label.position = Vector3(SKID_CENTRE.x, 4.02, beam_z + 0.12)
	add_child(label)


# --------------------------------------------------------------------------
# zone 4: JUMP LANE


## Zone 4: two kickers, a landing apron and distance boards.
func _jump_lane() -> void:
	_asphalt.rect(Rect2(LANE_X - LANE_HALF, LANE_END_Z, LANE_HALF * 2.0,
		LANE_START_Z - LANE_END_Z), LINK_Y, Color.WHITE)
	# Service road from the paddock's west edge to the lane.
	_asphalt.rect(Rect2(LANE_X + LANE_HALF, 14.0, 15.5, 8.0), LINK_Y,
		Color.WHITE)
	_marks.line(Vector2(LANE_X - LANE_HALF + 0.35, LANE_START_Z - 1.0),
		Vector2(LANE_X - LANE_HALF + 0.35, LANE_END_Z + 1.0), 0.22, MARK_Y,
		PAINT_CREAM)
	_marks.line(Vector2(LANE_X + LANE_HALF - 0.35, LANE_START_Z - 1.0),
		Vector2(LANE_X + LANE_HALF - 0.35, LANE_END_Z + 1.0), 0.22, MARK_Y,
		PAINT_CREAM)
	# Approach chevrons, pointing at the first kicker.
	for i in 3:
		var z: float = 29.0 - float(i) * 3.2
		_marks.line(Vector2(LANE_X - 2.4, z + 1.6), Vector2(LANE_X, z), 0.40,
			MARK_Y, PAINT_YELLOW)
		_marks.line(Vector2(LANE_X, z), Vector2(LANE_X + 2.4, z + 1.6), 0.40,
			MARK_Y, PAINT_YELLOW)
	# Landing distance stripes every 5 m, measured from the second lip.
	for i in 5:
		var z: float = -19.0 - float(i) * 5.0
		_marks.line(Vector2(LANE_X - 4.0, z), Vector2(LANE_X + 4.0, z), 0.30,
			MARK_Y, PAINT_CREAM)
	_ramp(RAMP_A_BASE_Z, RAMP_A_LIP_Z)
	_ramp(RAMP_B_BASE_Z, RAMP_B_LIP_Z)
	_distance_sign("5 m", Vector2(-59.5, -19.0))
	_distance_sign("10 m", Vector2(-59.5, -24.0))
	_distance_sign("20 m", Vector2(-59.5, -34.0))
	_distance_sign("25 m", Vector2(-59.5, -39.0))
	_zone_sign("JUMP LANE", Vector2(-43.5, 10.0), 0.0, PAINT_ORANGE)
	_boost_pad(Vector3(LANE_X, LINK_Y, 26.0), Vector3.FORWARD)
	_solid_batch("JumpLaneSolids", _jump_solids)


## One solid kicker wedge. `base_z` is the low approach edge and `lip_z` the
## take-off edge, so base_z > lip_z for a ramp rising to the north.
func _ramp(base_z: float, lip_z: float) -> void:
	var x0: float = LANE_X - RAMP_WIDTH * 0.5
	var x1: float = LANE_X + RAMP_WIDTH * 0.5
	var y0: float = LINK_Y
	var y1: float = LINK_Y + RAMP_RISE
	# Incline (up/south), back face (north) and closed sides: a real wedge.
	_structs.add_quad(Vector3(x0, y1, lip_z), Vector3(x0, y0, base_z),
		Vector3(x1, y0, base_z), Vector3(x1, y1, lip_z), RAMP_FACE)
	_structs.add_quad(Vector3(x0, y1, lip_z), Vector3(x1, y1, lip_z),
		Vector3(x1, y0, lip_z), Vector3(x0, y0, lip_z), RAMP_SIDE)
	_structs.add_triangle(Vector3(x0, y1, lip_z), Vector3(x0, y0, lip_z),
		Vector3(x0, y0, base_z), RAMP_SIDE)
	_structs.add_triangle(Vector3(x1, y1, lip_z), Vector3(x1, y0, base_z),
		Vector3(x1, y0, lip_z), RAMP_SIDE)
	# Bright lip cap and side stripes make the take-off readable at speed.
	var run: float = base_z - lip_z
	var slope: float = atan2(RAMP_RISE, run)
	var slope_length: float = sqrt(run * run + RAMP_RISE * RAMP_RISE)
	_structs.add_box(Transform3D(Basis.IDENTITY,
		Vector3(LANE_X, y1 + 0.02, lip_z + 0.18)), Vector3(RAMP_WIDTH, 0.06,
		0.36), PAINT_YELLOW)
	for side: float in [-1.0, 1.0]:
		var stripe := Transform3D(Basis(Vector3.RIGHT, slope),
			Vector3(LANE_X + side * (RAMP_WIDTH * 0.5 - 0.12),
				y0 + RAMP_RISE * 0.5 + 0.03, (base_z + lip_z) * 0.5))
		_structs.add_box(stripe, Vector3(0.20, 0.06, slope_length),
			PAINT_YELLOW)
	# The whole ramp is one convex wedge: solid, smooth to drive, cheap.
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		Vector3(x0, y0, base_z), Vector3(x1, y0, base_z),
		Vector3(x1, y0, lip_z), Vector3(x0, y0, lip_z),
		Vector3(x0, y1, lip_z), Vector3(x1, y1, lip_z),
	])
	_jump_solids.append([shape, Transform3D.IDENTITY])


# --------------------------------------------------------------------------
# zone 5: OFF-ROAD STRIP


## Zone 5: dirt strip, slalom cones and a lower-grip area.
func _offroad() -> void:
	_dirt.rect(DIRT_RECT, APRON_Y, Color.WHITE)
	_asphalt.rect(Rect2(-4.0, PADDOCK_RECT.end.y - 0.5, 8.0,
		DIRT_RECT.position.y - PADDOCK_RECT.end.y + 1.0), LINK_Y, Color.WHITE)
	_marks.rect(Rect2(DIRT_RECT.position.x + 3.0, DIRT_RECT.position.y + 0.9,
		DIRT_RECT.size.x - 6.0, 0.7), MARK_Y, PAINT_CREAM)
	# Edge dashes, so the strip reads as a marked section and not a mud patch.
	for i in 6:
		var z: float = DIRT_RECT.position.y + 5.0 + float(i) * 6.0
		_marks.rect(Rect2(DIRT_RECT.position.x + 0.9, z, 1.4, 0.28), MARK_Y,
			PAINT_CREAM)
		_marks.rect(Rect2(DIRT_RECT.end.x - 2.3, z, 1.4, 0.28), MARK_Y,
			PAINT_CREAM)
	_zone_sign("OFF-ROAD", Vector2(10.0, 27.0), PI, Color("4fbf52"))


## Grip area over the dirt. Karts that enter keep a lower `surface_grip`
## until they leave, which is what makes the surface change readable through
## the steering rather than only through the colour.
func _grip_zone() -> void:
	var area := Area3D.new()
	area.name = "DirtGripZone"
	area.collision_layer = 0
	area.collision_mask = CollisionLayers.PLAYER | CollisionLayers.GHOST
	var box := BoxShape3D.new()
	box.size = Vector3(DIRT_RECT.size.x, 4.0, DIRT_RECT.size.y)
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.position = Vector3(DIRT_RECT.get_center().x, 2.0,
		DIRT_RECT.get_center().y)
	area.add_child(collision)
	area.body_entered.connect(_on_dirt_entered)
	area.body_exited.connect(_on_dirt_exited)
	add_child(area)


## Applies the dirt grip while a kart is on the strip.
func _on_dirt_entered(body: Node3D) -> void:
	if not (body.is_in_group("player") or body.is_in_group("ai_player")):
		return
	var grip: float = _surface_grip_of(body)
	if grip < 0.0:
		return
	_grip_before[body.get_instance_id()] = grip
	body.set("surface_grip", DIRT_GRIP)


## Restores the grip a kart had before it entered the dirt.
func _on_dirt_exited(body: Node3D) -> void:
	# A body freed while it was on the strip cannot be restored; its saved grip
	# entry is simply left behind rather than dereferenced.
	if not is_instance_valid(body):
		return
	var id: int = body.get_instance_id()
	if not _grip_before.has(id):
		return
	body.set("surface_grip", float(_grip_before[id]))
	_grip_before.erase(id)


## Reads the kart's grip property through the property list, so this script
## never has to reference the CartPlayer class (which is not cached on a cold
## headless boot).
func _surface_grip_of(body: Node3D) -> float:
	for property in body.get_property_list():
		if str(property.get("name", "")) == "surface_grip":
			return float(body.get("surface_grip"))
	return -1.0


# --------------------------------------------------------------------------
# perimeter and backdrop


## Solid perimeter wall with its yellow coping, one body and one merged mesh.
func _perimeter() -> void:
	var body := StaticBody3D.new()
	body.name = "FacilityWall"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	var bottom: float = -1.0
	var centre_y: float = bottom + WALL_H * 0.5
	var long_side: float = FIELD * 2.0 + WALL_T * 2.0
	var short_side: float = FIELD * 2.0
	for side in 4:
		var size: Vector3
		var position: Vector3
		match side:
			0:
				size = Vector3(long_side, WALL_H, WALL_T)
				position = Vector3(0.0, centre_y, -FIELD)
			1:
				size = Vector3(long_side, WALL_H, WALL_T)
				position = Vector3(0.0, centre_y, FIELD)
			2:
				size = Vector3(WALL_T, WALL_H, short_side)
				position = Vector3(-FIELD, centre_y, 0.0)
			_:
				size = Vector3(WALL_T, WALL_H, short_side)
				position = Vector3(FIELD, centre_y, 0.0)
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = position
		body.add_child(collision)
		_structs.add_box(Transform3D(Basis.IDENTITY, position), size, WALL_GREY)
		# Yellow coping: one box per side, in the same merged mesh.
		if side < 2:
			_structs.add_box(Transform3D(Basis.IDENTITY,
				position + Vector3.UP * (WALL_H * 0.5 - 0.18)),
				Vector3(size.x, 0.35, WALL_T + 0.06), PAINT_YELLOW)
		else:
			_structs.add_box(Transform3D(Basis.IDENTITY,
				position + Vector3.UP * (WALL_H * 0.5 - 0.18)),
				Vector3(WALL_T + 0.06, 0.35, size.z), PAINT_YELLOW)
	add_child(body)


## Trees only outside the wall; nothing green stands in a driving area.
func _scenery() -> void:
	var bark := _pbr("bark_diff", "bark_nor", "grass_rough", 1.0,
		Color(0.95, 0.93, 0.88), 0.28, 0.035)
	var broad := _wind_material("leaf_broad", Color(0.88, 1.0, 0.82), 10.0,
		0.26, 1.0)
	var frond := _wind_material("leaf_frond", Color(0.66, 0.86, 0.64), 12.0,
		0.30, 0.9)
	var builder := RealisticTree.new()
	var variants: Array[int] = [0, 3]
	var leaves: Array[ShaderMaterial] = [broad, frond]
	var transforms: Array = []
	for cluster: Vector3 in _tree_clusters():
		var count: int = _rng.randi_range(10, 14)
		for i in count:
			var offset := Vector2(_rng.randf_range(-1.0, 1.0),
				_rng.randf_range(-1.0, 1.0))
			offset = offset.normalized() * pow(_rng.randf(), 0.6) * 15.0
			var point := Vector3(cluster.x + offset.x, -0.06,
				cluster.z + offset.y)
			if maxf(absf(point.x), absf(point.z)) < FIELD + 8.0:
				continue
			transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU)
				.scaled(Vector3.ONE * _rng.randf_range(0.8, 1.35)), point))
	var holder := Node3D.new()
	holder.name = "FacilityForest"
	add_child(holder)
	for index in 2:
		var subset: Array = []
		for i in transforms.size():
			if i % 2 == index:
				subset.append(transforms[i])
		if subset.is_empty():
			continue
		var tree: Dictionary = builder.build(variants[index], 6800 + index * 97)
		holder.add_child(FoliageBaker.create_chunked_instances(
			tree["bark"] as ArrayMesh, bark, subset, true, 340.0, [], 128.0))
		# Canopy shadows are not worth a 90 m cascade; the trunks ground them.
		holder.add_child(FoliageBaker.create_chunked_instances(
			tree["leaf"] as ArrayMesh, leaves[index], subset, false, 340.0, [],
			128.0))
	_conifer_line()


## Cluster centres on the outfield, always outside the wall.
func _tree_clusters() -> Array[Vector3]:
	var clusters: Array[Vector3] = []
	for i in 8:
		var angle: float = TAU * float(i) / 8.0 + 0.19
		var radius: float = 96.0 + float(i % 3) * 15.0
		clusters.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
	return clusters


## A conifer belt beyond the broadleaf clusters.
func _conifer_line() -> void:
	var mesh: ArrayMesh = FoliageBaker.bake("tree_pineTallA")
	if mesh == null:
		return
	var bounds: AABB = mesh.get_aabb()
	var unit: float = 13.5 / maxf(bounds.size.y, 0.01)
	var transforms: Array = []
	for i in 60:
		var angle: float = TAU * _rng.randf()
		var radius: float = _rng.randf_range(102.0, 168.0)
		var scale: float = unit * _rng.randf_range(0.75, 1.45)
		var point := Vector3(cos(angle) * radius,
			-0.06 - bounds.position.y * scale, sin(angle) * radius)
		if maxf(absf(point.x), absf(point.z)) < FIELD + 9.0:
			continue
		transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU)
			.scaled(Vector3.ONE * scale), point))
	var holder: Node3D = FoliageBaker.create_chunked_instances(mesh,
		FoliageBaker.make_material(), transforms, false, 340.0, [], 128.0)
	holder.name = "FacilityConifers"
	add_child(holder)


## Alpha-cutout foliage material shared by one leaf layer.
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
	# No kart-bend: this foliage is outside the wall, where no kart will go.
	mat.set_shader_parameter("bend_radius", 0.0)
	mat.set_shader_parameter("bend_strength", 0.0)
	return mat


## Shared far mountains and clouds; no collision and no per-frame cost.
func _backdrop() -> void:
	Backdrop.add_mountains(self, _rng, 10)
	Backdrop.add_clouds(self, _rng, 14)


# --------------------------------------------------------------------------
# merged structure mesh, pavement meshes and labels


## Flushes the merged pavements, paint, structures and sign collision.
func _commit_facility() -> void:
	_commit_layer("Tarmac", _asphalt, _asphalt_mat)
	_commit_layer("PaddockConcrete", _concrete, _concrete_mat)
	_commit_layer("DirtStrip", _dirt, _dirt_mat)
	_commit_layer("PaintedMarks", _marks, _vertex_mat)
	_solid_batch("SignSolids", _sign_solids)
	var mesh: ArrayMesh = _structs.build()
	if mesh != null:
		var instance := MeshInstance3D.new()
		instance.name = "FacilityStructures"
		instance.mesh = mesh
		instance.material_override = _vertex_mat
		add_child(instance)


## Commits one buffer as a single mesh with the shared material for its surface.
func _commit_layer(node_name: String, buffer: SurfaceBuf,
		material: Material) -> void:
	var mesh: ArrayMesh = _mesh_from_buffer(buffer)
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Converts one SurfaceBuf into a single-surface ArrayMesh.
func _mesh_from_buffer(buffer: SurfaceBuf) -> ArrayMesh:
	if buffer.indices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = buffer.verts
	arrays[Mesh.ARRAY_NORMAL] = buffer.normals
	arrays[Mesh.ARRAY_TEX_UV] = buffer.uvs
	arrays[Mesh.ARRAY_COLOR] = buffer.colors
	arrays[Mesh.ARRAY_INDEX] = buffer.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Zone board: board, cap strip and two posts in the merged structure mesh,
## exact collision on the posts and the board, and one Label3D for the name.
func _zone_sign(text: String, place: Vector2, yaw: float, tint: Color) -> void:
	_board_sign(text, place, yaw, tint, 4.6, 1.15, 2.5, 96, _sign_solids)


## Small trackside distance board, used along the jump landing apron.
func _distance_sign(text: String, place: Vector2) -> void:
	_board_sign(text, place, PI * 0.5, RacingKit.CREAM, 2.0, 0.9, 1.55, 80,
		_jump_solids)


## Shared board/post/label builder for zone and distance signs.
func _board_sign(text: String, place: Vector2, yaw: float, tint: Color,
		width: float, height: float, centre_y: float, font_size: int,
		solids: Array) -> void:
	var at := Vector3(place.x, 0.0, place.y)
	var basis := Basis(Vector3.UP, yaw)
	_structs.add_box(Transform3D(basis, at + Vector3.UP * centre_y),
		Vector3(width, height, 0.14), tint)
	_structs.add_box(Transform3D(basis,
		at + Vector3.UP * (centre_y + height * 0.5 + 0.06)),
		Vector3(width + 0.10, 0.14, 0.18), RacingKit.CREAM)
	for side: float in [-1.0, 1.0]:
		_structs.add_box(Transform3D(basis, at + basis * Vector3(
			side * width * 0.36, centre_y * 0.5, 0.0)),
			Vector3(0.14, centre_y, 0.14), RacingKit.STEEL)
		var post := BoxShape3D.new()
		post.size = Vector3(0.20, centre_y, 0.20)
		solids.append([post, Transform3D(basis, at + basis * Vector3(
			side * width * 0.36, centre_y * 0.5, 0.0))])
	var board := BoxShape3D.new()
	board.size = Vector3(width, height, 0.20)
	solids.append([board, Transform3D(basis, at + Vector3.UP * centre_y)])
	var label := Label3D.new()
	label.name = "Sign_" + text.replace(" ", "")
	label.text = text
	label.font = _font
	# Long zone names shrink to stay inside their board instead of spilling
	# lettering past the panel.
	var fitted: int = font_size if text.length() <= 10 \
		else maxi(int(float(font_size) * 10.0 / float(text.length())), 56)
	label.font_size = fitted
	label.pixel_size = 0.0075
	label.outline_size = 12
	label.outline_modulate = Color(0.12, 0.10, 0.20, 0.9)
	label.modulate = PAINT_CREAM
	label.position = at + basis * Vector3(0.0, centre_y, 0.12)
	label.rotation.y = yaw
	add_child(label)


# --------------------------------------------------------------------------
# pushable props (existing sandbox contract: group "pushable", no WORLD body)


## Existing sandbox pushables: cone slalom and pit crates.
func _pushable_props() -> void:
	# Cone slalom down the dirt: the weave is where the grip loss shows up.
	for i in 8:
		var x: float = -8.0 if i % 2 == 0 else 8.0
		_cone("DirtCone%d" % (i + 1), Vector3(x, APRON_Y, 30.0 + float(i) * 3.6))
	for side: float in [-1.0, 1.0]:
		_cone("DirtGate%d" % int(side + 2.0), Vector3(side * 7.0, APRON_Y, 25.5))
	# Crates by the pit building: pushable, but SOLID_PROP stops the kart.
	for i in 4:
		_crate("PaddockCrate%d" % (i + 1), Vector3(-23.0 + float(i % 2) * 0.9,
			APRON_Y, 16.5 + float(i / 2) * 0.9))


## One pushable cone (PROP layer, as the sandbox contract expects).
func _cone(prop_name: String, at: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = prop_name
	body.add_to_group("pushable")
	body.collision_layer = CollisionLayers.PROP
	body.collision_mask = CollisionLayers.WORLD | CollisionLayers.PROP
	body.mass = 0.35
	# Cones are light and numerous; full CCD here is wasted physics work.
	body.continuous_cd = false
	body.physics_material_override = _prop_physics()
	body.position = at + Vector3.UP * 0.05
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


## One pushable crate (SOLID_PROP, so it also blocks the kart).
func _crate(prop_name: String, at: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = prop_name
	body.add_to_group("pushable")
	# Crates are heavy and solid: the kart cannot drive through one, and the
	# push sensor still launches it.
	body.collision_layer = CollisionLayers.PROP | CollisionLayers.SOLID_PROP
	body.collision_mask = CollisionLayers.WORLD | CollisionLayers.PROP
	body.mass = 0.8
	body.continuous_cd = true
	body.physics_material_override = _prop_physics()
	body.position = at + Vector3.UP * 0.02
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


## Shared physics material for every pushable prop.
func _prop_physics() -> PhysicsMaterial:
	if _prop_material != null:
		return _prop_material
	var mat := PhysicsMaterial.new()
	mat.friction = 0.9
	mat.bounce = 0.15
	_prop_material = mat
	return mat


# --------------------------------------------------------------------------
# shared helpers


## Solid boost pad from the shared scene, oriented along `forward`. The shared
## FloatStrip hovers a metre up and reads as floating geometry in an open
## facility, so the ground chevrons carry the pad instead.
func _boost_pad(at: Vector3, forward: Vector3) -> void:
	var pad: Node3D = (load(BOOST_PAD_SCENE) as PackedScene).instantiate() as Node3D
	var float_strip: Node = pad.get_node_or_null("FloatStrip")
	if float_strip != null:
		float_strip.free()
	pad.position = at
	if forward.length_squared() > 0.0001:
		pad.rotation.y = atan2(-forward.x, -forward.z)
	add_child(pad)


## One draw call for every repeated prop. `transforms` are world transforms.
func _batch(node_name: String, mesh: Mesh, material: Material,
		transforms: Array, shadows: bool) -> void:
	if transforms.is_empty() or mesh == null:
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
	add_child(instance)


## Collapse a primitive mesh into an ArrayMesh so MultiMesh can batch it.
func _mesh_to_array(mesh: Mesh) -> ArrayMesh:
	var arrays: Array = mesh.surface_get_arrays(0)
	var baked := ArrayMesh.new()
	baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return baked


## The one terrain collider: a single ConcavePolygonShape3D for the whole park.
func _static_faces(body_name: String, faces: PackedVector3Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


## One WORLD-layer body for a set of simple colliders, so a whole zone's solid
## furniture costs one node instead of one body per post.
func _solid_batch(body_name: String, shapes: Array) -> void:
	if shapes.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	for entry: Array in shapes:
		var collision := CollisionShape3D.new()
		collision.shape = entry[0] as Shape3D
		collision.transform = entry[1] as Transform3D
		body.add_child(collision)
	add_child(body)


## Packs vertex arrays for one surface.
func _arrays(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array,
		indices: PackedInt32Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not indices.is_empty():
		arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
