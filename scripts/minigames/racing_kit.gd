extends RefCounted
## Reusable circuit furniture shared by the race scene and the sandbox.
##
## Every builder is a static function that drops one self-contained prop (or
## one run of props) under `parent`. Repeated pieces are MultiMeshes and the
## rest is merged into a single vertex-coloured ArrayMesh, so a whole grandstand
## or a kilometre of armco stays at a handful of draw calls.
##
## Solid pieces always carry a StaticBody3D on CollisionLayers.WORLD: barriers,
## tyre walls, grandstands, gantry posts, floodlight poles, distance boards,
## tarmac, pit concrete and kerbs are all real obstacles. A kerb is a low
## drive-over slope rather than a wall, but its raised strip still collides so a
## kart can never pass through the visible geometry.
##
## Materials come from `palette()`, which builds each shared material once.
## The tarmac and pit helpers use the project's Poly Haven asphalt and worn
## concrete scans; nothing here downloads or loads a texture per prop.

const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

const ROAD_HALF: float = 5.5
const ROAD_Y: float = 0.04
const KERB_WIDTH: float = 0.85
const KERB_LIFT: float = 0.10
const KERB_STEP: float = 2.0
const BARRIER_LATERAL: float = ROAD_HALF + 0.35
const BARRIER_STEP: float = 2.4
const TYRE_LATERAL: float = ROAD_HALF + 1.9
const TYRE_SPACING: float = 1.12
const TYRE_RADIUS: float = 0.42
const TYRE_HEIGHT: float = 0.30
const STAND_LATERAL: float = ROAD_HALF + 10.0
const STAND_LENGTH: float = 16.0
const STAND_ROWS: int = 5
const STAND_ROW_RUN: float = 1.08
const STAND_ROW_RISE: float = 0.56

const TITLE_FONT: String = "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"
const PBR_SHADER: String = "res://assets/materials/ground_pbr.gdshader"
const PBR_TEX: String = "res://assets/textures/polyhaven/"

const CREAM := Color("fff6e3")
const STEEL := Color("4a5560")
const DARK := Color("2f2a26")
const CONCRETE := Color("b9b4a8")
const TYRE_BLACK := Color("121114")
const TYRE_RED := Color("c23a2c")
const CROWD_SHIRTS: Array[Color] = [
	Color("e4572e"), Color("2e86ab"), Color("f6c945"), Color("3fa34d"),
	Color("b84a9c"), Color("f3f0e6"), Color("6c5b7b"), Color("e08e45"),
]
const SKIN_TONES: Array[Color] = [
	Color("f2c9a0"), Color("d9a06b"), Color("a86b3f"), Color("7a4a2b"),
	Color("e8b98a"),
]

static var _palette: Dictionary = {}
static var _figures: Dictionary = {}


## Shared materials. Call this instead of making a StandardMaterial3D per prop.
static func palette() -> Dictionary:
	if not _palette.is_empty():
		return _palette
	var vertex: StandardMaterial3D = SceneryKit.vertex_material()
	var instance: StandardMaterial3D = SceneryKit.instance_material(0.95)
	var kerb := StandardMaterial3D.new()
	kerb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	kerb.vertex_color_use_as_albedo = true
	kerb.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color("fff1c4")
	lamp.emission_enabled = true
	lamp.emission = Color("ffd97a")
	lamp.emission_energy_multiplier = 2.2
	lamp.roughness = 0.5
	_palette = {
		"vertex": vertex,
		"instance": instance,
		"kerb": kerb,
		"floodlight": lamp,
		"asphalt": _pbr_material("asphalt_01_diff", "asphalt_01_nor",
			"asphalt_01_rough", 1.0, Color(0.72, 0.74, 0.78), 0.10, 0.03, 0.08),
		"concrete": _pbr_material("concrete_floor_worn_001_diff",
			"concrete_floor_worn_001_nor",
			"concrete_floor_worn_001_rough", 0.75,
			Color(0.82, 0.80, 0.76), 0.12, 0.04, 0.0),
	}
	return _palette


static func _pbr_material(diff: String, nor: String, rough: String,
		uv_scale: float, tint: Color, detail: float,
		macro: float, tracks: float) -> Material:
	var diff_path: String = PBR_TEX + diff + ".jpg"
	var nor_path: String = PBR_TEX + nor + ".jpg"
	var rough_path: String = PBR_TEX + rough + ".jpg"
	# A source checkout that has not run the Godot importer yet cannot load the
	# JPGs. Keep the prop usable with an honest flat fallback instead of
	# spraying resource errors; a real build resolves the scans and takes the
	# PBR branch.
	if not (ResourceLoader.exists(diff_path) and ResourceLoader.exists(nor_path)
			and ResourceLoader.exists(rough_path)):
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = tint
		fallback.roughness = 0.92
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
	if tracks > 0.0:
		mat.set_shader_parameter("track_strength", tracks)
	return mat


# --------------------------------------------------------------------------
# kerbs


## A red/white (or `colour`/cream) kerb run along one edge of the road.
## `from_distance`/`to_distance` are arc-length metres; a run that wraps the
## start line is supported. `side` is +1 for the right edge, -1 for the left.
static func kerbs(parent: Node3D, spline: RefCounted, from_distance: float,
		to_distance: float, side: float, colour: Color) -> void:
	if parent == null or spline == null:
		return
	var total: float = maxf(spline.total_length, 0.001)
	var span: float = fposmod(to_distance - from_distance, total)
	if span <= 0.01:
		return
	var steps: int = maxi(int(ceil(span / KERB_STEP)), 1)
	var step: float = span / float(steps)
	var direction: float = 1.0 if side >= 0.0 else -1.0
	var verts := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	for i in steps:
		var s0: float = from_distance + step * float(i)
		var s1: float = s0 + step
		var f0: Dictionary = spline.sample(s0)
		var f1: Dictionary = spline.sample(s1)
		var p0: Vector3 = f0["position"]
		var p1: Vector3 = f1["position"]
		var r0: Vector3 = f0["right"]
		var r1: Vector3 = f1["right"]
		var inner0: Vector3 = p0 + r0 * (ROAD_HALF * direction) \
			+ Vector3.UP * (ROAD_Y + 0.012)
		var inner1: Vector3 = p1 + r1 * (ROAD_HALF * direction) \
			+ Vector3.UP * (ROAD_Y + 0.012)
		var outer0: Vector3 = p0 + r0 * ((ROAD_HALF + KERB_WIDTH) * direction) \
			+ Vector3.UP * (ROAD_Y + KERB_LIFT)
		var outer1: Vector3 = p1 + r1 * ((ROAD_HALF + KERB_WIDTH) * direction) \
			+ Vector3.UP * (ROAD_Y + KERB_LIFT)
		var shade: Color = colour if int(floor(s0 / 3.0)) % 2 == 0 else CREAM
		var low0: Vector3 = outer0 - Vector3.UP * KERB_LIFT
		var low1: Vector3 = outer1 - Vector3.UP * KERB_LIFT
		if direction > 0.0:
			_add_quad(verts, colours, indices, inner0, outer0, outer1, inner1,
				shade)
			_append_quad_faces(faces, inner0, outer0, outer1, inner1)
			_add_quad(verts, colours, indices, low0, outer0, outer1, low1,
				shade.darkened(0.12))
			_append_quad_faces(faces, low0, outer0, outer1, low1)
		else:
			_add_quad(verts, colours, indices, inner1, outer1, outer0, inner0,
				shade)
			_append_quad_faces(faces, inner1, outer1, outer0, inner0)
			_add_quad(verts, colours, indices, low1, outer1, outer0, low0,
				shade.darkened(0.12))
			_append_quad_faces(faces, low1, outer1, outer0, low0)
	var mesh: ArrayMesh = SceneryKit.mesh_from(verts, colours, indices, true)
	if mesh == null:
		return
	var run := MeshInstance3D.new()
	run.name = "Kerbs_%s_%d" % ["R" if direction > 0.0 else "L",
		int(round(from_distance))]
	run.mesh = mesh
	run.material_override = palette()["kerb"] as Material
	run.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(run)
	# The raised strip is a real slope, not a painting: a concave collider lets
	# a kart climb the inside lip and stops it driving through the outer face.
	var body := _static_root(parent, "KerbCollision_%s_%d" % [
		"R" if direction > 0.0 else "L", int(round(from_distance))])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


# --------------------------------------------------------------------------
# barriers


## Armco rail plus posts along one edge. The rail is one merged mesh and one
## continuous StaticBody3D wall on the WORLD layer, so a kart cannot clip it.
static func barriers(parent: Node3D, spline: RefCounted, from_distance: float,
		to_distance: float, side: float) -> void:
	if parent == null or spline == null:
		return
	var total: float = maxf(spline.total_length, 0.001)
	var span: float = fposmod(to_distance - from_distance, total)
	if span <= 0.01:
		return
	var direction: float = 1.0 if side >= 0.0 else -1.0
	var lateral: float = BARRIER_LATERAL * direction
	var steps: int = maxi(int(ceil(span / BARRIER_STEP)), 1)
	var step: float = span / float(steps)
	var body := _static_root(parent, "Barriers_%s_%d" % [
		"R" if direction > 0.0 else "L", int(round(from_distance))])
	var batch := PropBatch.new()
	var faces := PackedVector3Array()
	for i in steps:
		var s0: float = from_distance + step * float(i)
		var s1: float = s0 + step
		var f0: Dictionary = spline.sample(s0)
		var f1: Dictionary = spline.sample(s1)
		var p0: Vector3 = f0["position"] + (f0["right"] as Vector3) * lateral
		var p1: Vector3 = f1["position"] + (f1["right"] as Vector3) * lateral
		var mid: Vector3 = (p0 + p1) * 0.5
		var yaw: float = spline.yaw_at(s0 + step * 0.5)
		var rail_xform: Transform3D = Transform3D(Basis(Vector3.UP, yaw), mid)
		batch.add_box(rail_xform * Transform3D(Basis.IDENTITY,
			Vector3(0.0, 0.68, 0.0)), Vector3(0.10, 0.36, step + 0.12), STEEL)
		# One continuous concave wall for the whole run is cheaper than a box
		# per segment and cannot leave a gap between shapes on a bend.
		var top0: Vector3 = p0 + Vector3.UP * 1.0
		var top1: Vector3 = p1 + Vector3.UP * 1.0
		faces.append(p0)
		faces.append(top0)
		faces.append(p1)
		faces.append(p1)
		faces.append(top0)
		faces.append(top1)
		if i % 2 == 0:
			var post: Transform3D = _track_transform(spline, s0, lateral, 0.0)
			batch.add_box(post * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 0.50, 0.0)), Vector3(0.14, 1.0, 0.14), DARK)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	_add_visual(body, batch, "Armco", palette()["vertex"] as Material)


# --------------------------------------------------------------------------
# tyre wall


## `length` metres of stacked tyres centred on `distance`, three high. Each
## stack is solid on the WORLD layer; one box per stack keeps the shape count
## low while still covering the visible wall.
static func tyre_wall(parent: Node3D, spline: RefCounted, distance: float,
		side: float, length: float) -> void:
	if parent == null or spline == null:
		return
	var direction: float = 1.0 if side >= 0.0 else -1.0
	var lateral: float = TYRE_LATERAL * direction
	var count: int = maxi(int(round(maxf(length, TYRE_SPACING) / TYRE_SPACING)), 1)
	var start: float = distance - float(count - 1) * TYRE_SPACING * 0.5
	var body := _static_root(parent, "TyreWall_%s_%d" % [
		"R" if direction > 0.0 else "L", int(round(distance))])
	var transforms: Array = []
	var colours: Array = []
	for i in count:
		var d: float = start + float(i) * TYRE_SPACING
		var root: Transform3D = _track_transform(spline, d, lateral, 0.0)
		for level in 3:
			transforms.append(root * Transform3D(Basis.IDENTITY,
				Vector3(0.0, TYRE_HEIGHT * 0.5 + float(level) * TYRE_HEIGHT, 0.0)))
			if level == 2:
				colours.append(TYRE_RED if i % 2 == 0 else CREAM)
			else:
				colours.append(TYRE_BLACK)
		_add_box_shape(body, root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, TYRE_HEIGHT * 1.5, 0.0)),
			Vector3(TYRE_RADIUS * 2.0, TYRE_HEIGHT * 3.0, TYRE_SPACING))
	var tyre := CylinderMesh.new()
	tyre.top_radius = TYRE_RADIUS
	tyre.bottom_radius = TYRE_RADIUS
	tyre.height = TYRE_HEIGHT
	tyre.radial_segments = 12
	tyre.rings = 1
	var tyres := SceneryKit.multimesh(tyre, palette()["instance"] as Material,
		transforms, "Tyres", false, colours)
	SceneryKit.set_view(tyres, 0.0, 180.0)
	body.add_child(tyres)


# --------------------------------------------------------------------------
# grandstand


## A stepped stand with a roof, rail and instanced crowd, facing the track from
## `side`. The whole footprint is one WORLD collision box, so it is never a
## drive-through decoration.
static func grandstand(parent: Node3D, spline: RefCounted, distance: float,
		side: float) -> void:
	if parent == null or spline == null:
		return
	var direction: float = 1.0 if side >= 0.0 else -1.0
	var lateral: float = STAND_LATERAL * direction
	var yaw: float = spline.yaw_at(distance) \
		+ (PI * 0.5 if direction > 0.0 else -PI * 0.5)
	var root := _static_root(parent, "Grandstand_%s_%d" % [
		"R" if direction > 0.0 else "L", int(round(distance))],
		Transform3D(Basis(Vector3.UP, yaw),
			_track_position(spline, distance, lateral, 0.0)))
	var depth: float = float(STAND_ROWS) * STAND_ROW_RUN
	var front: float = -depth * 0.5
	var roof_y: float = STAND_ROW_RISE * float(STAND_ROWS) + 3.0
	var batch := PropBatch.new()
	for row in STAND_ROWS:
		var z: float = front + (float(row) + 0.5) * STAND_ROW_RUN
		var top: float = STAND_ROW_RISE * float(row + 1)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, top - 0.09, z)),
			Vector3(STAND_LENGTH, 0.18, STAND_ROW_RUN + 0.04), CONCRETE)
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, top * 0.5, z - STAND_ROW_RUN * 0.5)),
			Vector3(STAND_LENGTH, top, 0.14), CONCRETE.darkened(0.12))
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, top + 0.08, z + 0.18)),
			Vector3(STAND_LENGTH, 0.14, 0.40), Color("8fa3b8"))
	batch.add_box(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-7.0)),
		Vector3(0.0, roof_y, 0.4)), Vector3(STAND_LENGTH + 1.6, 0.22, depth + 3.0),
		Color("c9553f"))
	for i in 5:
		var x: float = -STAND_LENGTH * 0.5 + 0.8 \
			+ (STAND_LENGTH - 1.6) * float(i) / 4.0
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(x, roof_y * 0.5, front - 0.9)), Vector3(0.24, roof_y, 0.24),
			STEEL)
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, front - 1.05)),
		Vector3(STAND_LENGTH, 1.1, 0.18), STEEL)
	batch.add_box(Transform3D(Basis.IDENTITY,
		Vector3(0.0, roof_y * 0.55, depth * 0.5)),
		Vector3(STAND_LENGTH, roof_y * 1.1, 0.28), CONCRETE.darkened(0.20))
	_add_box_shape(root, Transform3D(Basis.IDENTITY,
		Vector3(0.0, roof_y * 0.5, 0.2)),
		Vector3(STAND_LENGTH + 1.0, roof_y, depth + 1.0))
	_add_box_shape(root, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-7.0)),
		Vector3(0.0, roof_y, 0.4)), Vector3(STAND_LENGTH + 1.6, 0.22, depth + 3.0))
	_add_visual(root, batch, "StandDetail", palette()["vertex"] as Material)

	var seats: int = maxi(int((STAND_LENGTH - 0.6) / 0.8), 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(round(distance * 17.0)) ^ int(round(side * 31.0))
	var bodies: Array = []
	var heads: Array = []
	var shirts: Array = []
	var skins: Array = []
	for row in STAND_ROWS:
		for seat in seats:
			if rng.randf() < 0.18:
				continue
			var x: float = -STAND_LENGTH * 0.5 + 0.5 \
				+ (STAND_LENGTH - 1.0) * float(seat) / float(maxi(seats - 1, 1))
			var top: float = STAND_ROW_RISE * float(row + 1)
			var z: float = front + (float(row) + 0.5) * STAND_ROW_RUN
			var scale: float = rng.randf_range(0.90, 1.08)
			var basis: Basis = Basis.IDENTITY.scaled(Vector3.ONE * scale)
			bodies.append(Transform3D(basis, Vector3(x, top + 0.34, z)))
			heads.append(Transform3D(basis, Vector3(x, top + 0.92, z)))
			shirts.append(CROWD_SHIRTS[rng.randi_range(0, CROWD_SHIRTS.size() - 1)])
			skins.append(SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)])
	if not bodies.is_empty():
		var figures: Dictionary = _figure_meshes()
		var crowd_body := SceneryKit.multimesh(figures["body"] as Mesh,
			palette()["instance"] as Material, bodies, "StandCrowd", false, shirts)
		SceneryKit.set_view(crowd_body, 0.0, 150.0)
		root.add_child(crowd_body)
		var crowd_head := SceneryKit.multimesh(figures["head"] as Mesh,
			palette()["instance"] as Material, heads, "StandCrowdHeads", false, skins)
		SceneryKit.set_view(crowd_head, 0.0, 150.0)
		root.add_child(crowd_head)


static func _figure_meshes() -> Dictionary:
	if not _figures.is_empty():
		return _figures
	var body := CapsuleMesh.new()
	body.radius = 0.22
	body.height = 0.92
	body.radial_segments = 6
	body.rings = 2
	var head := SphereMesh.new()
	head.radius = 0.17
	head.height = 0.34
	head.radial_segments = 5
	head.rings = 2
	_figures = {"body": body, "head": head}
	return _figures


# --------------------------------------------------------------------------
# start gantry


## Overhead gantry across the road at `distance`. The two posts (and the beam,
## for anything airborne) are solid on the WORLD layer.
static func start_gantry(parent: Node3D, spline: RefCounted,
		distance: float) -> void:
	if parent == null or spline == null:
		return
	var root := _static_root(parent, "StartGantry_%d" % int(round(distance)),
		_track_transform(spline, distance, 0.0, 0.0))
	var span: float = ROAD_HALF + 1.5
	var batch := PropBatch.new()
	for side: float in [-1.0, 1.0]:
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(side * span, 3.2, 0.0)), Vector3(0.80, 6.4, 0.80), STEEL)
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(side * span, 0.20, 0.0)), Vector3(1.45, 0.40, 1.45),
			CONCRETE)
		_add_box_shape(root, Transform3D(Basis.IDENTITY,
			Vector3(side * span, 3.2, 0.0)), Vector3(0.80, 6.4, 0.80))
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 6.20, 0.0)),
		Vector3(span * 2.0 + 0.8, 0.80, 0.70), STEEL)
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 5.30, 0.0)),
		Vector3(span * 2.0 + 0.4, 1.00, 0.16), CREAM)
	_add_box_shape(root, Transform3D(Basis.IDENTITY, Vector3(0.0, 6.20, 0.0)),
		Vector3(span * 2.0 + 0.8, 0.80, 0.70))
	_add_box_shape(root, Transform3D(Basis.IDENTITY, Vector3(0.0, 5.30, 0.0)),
		Vector3(span * 2.0 + 0.4, 1.00, 0.16))
	_add_visual(root, batch, "GantryFrame", palette()["vertex"] as Material)
	var label := Label3D.new()
	label.name = "GantryBanner"
	label.text = "CART SLOP GP"
	label.font = load(TITLE_FONT)
	label.font_size = 96
	label.pixel_size = 0.015
	label.outline_size = 14
	label.outline_modulate = Color(0.12, 0.10, 0.20, 0.9)
	label.modulate = Color(1.0, 0.84, 0.28)
	label.position = Vector3(0.0, 5.30, 0.12)
	SceneryKit.set_view(label, 0.0, 240.0)
	root.add_child(label)


# --------------------------------------------------------------------------
# floodlight


## A 9 m light tower. The head is emissive rather than a real Light3D: a racing
## map can hold a dozen of these without paying for a dozen dynamic lights.
## The pole and base are solid on WORLD.
static func floodlight(parent: Node3D, position: Vector3) -> void:
	if parent == null:
		return
	var yaw: float = atan2(position.x, position.z)
	var root := _static_root(parent, "Floodlight_%d_%d" % [
		int(round(position.x)), int(round(position.z))],
		Transform3D(Basis(Vector3.UP, yaw), position))
	var batch := PropBatch.new()
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.15, 0.0)),
		Vector3(1.40, 0.30, 1.40), CONCRETE)
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 4.75, 0.0)),
		0.16, 9.0, 8, STEEL)
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 9.15, 0.0)),
		Vector3(2.20, 0.18, 0.18), STEEL)
	for i in 4:
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3((float(i) - 1.5) * 0.50, 9.02, -0.10)),
			Vector3(0.44, 0.10, 0.36), DARK)
	_add_box_shape(root, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.15, 0.0)),
		Vector3(1.40, 0.30, 1.40))
	_add_box_shape(root, Transform3D(Basis.IDENTITY, Vector3(0.0, 9.15, 0.0)),
		Vector3(2.20, 0.18, 0.18))
	var pole_shape := CylinderShape3D.new()
	pole_shape.radius = 0.22
	pole_shape.height = 9.0
	var pole := CollisionShape3D.new()
	pole.shape = pole_shape
	pole.position = Vector3(0.0, 4.50, 0.0)
	root.add_child(pole)
	_add_visual(root, batch, "FloodlightFrame", palette()["vertex"] as Material)
	var lamps := PropBatch.new()
	for i in 4:
		lamps.add_box(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-24.0)),
			Vector3((float(i) - 1.5) * 0.50, 9.12, 0.10)),
			Vector3(0.38, 0.24, 0.06), Color.WHITE)
	_add_visual(root, lamps, "FloodlightLamps",
		palette()["floodlight"] as Material)


# --------------------------------------------------------------------------
# distance board


## Trackside marker board. It is placed on the outside of the bend at
## `distance` and faces approaching traffic. Board and posts are solid.
static func distance_board(parent: Node3D, spline: RefCounted, distance: float,
		text: String) -> void:
	if parent == null or spline == null:
		return
	var side: float = _outside_side(spline, distance)
	var lateral: float = side * (ROAD_HALF + 3.2)
	var root := _static_root(parent, "DistanceBoard_%d" % int(round(distance)),
		_track_transform(spline, distance, lateral, 0.0))
	var batch := PropBatch.new()
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.55, 0.0)),
		Vector3(3.00, 1.10, 0.16), CREAM)
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.08, 0.01)),
		Vector3(3.06, 0.18, 0.18), TYRE_RED)
	for post: float in [-1.20, 1.20]:
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(post, 0.60, 0.0)),
			Vector3(0.12, 1.20, 0.12), STEEL)
	_add_box_shape(root, Transform3D(Basis.IDENTITY, Vector3(0.0, 1.05, 0.0)),
		Vector3(3.10, 2.20, 0.28))
	_add_visual(root, batch, "Board", palette()["vertex"] as Material)
	var label := Label3D.new()
	label.name = "BoardText"
	label.text = text
	label.font = load(TITLE_FONT)
	label.font_size = 96
	label.pixel_size = 0.0075
	label.outline_size = 10
	label.outline_modulate = Color(0.12, 0.10, 0.20, 0.85)
	label.modulate = DARK
	label.position = Vector3(0.0, 1.52, 0.11)
	SceneryKit.set_view(label, 0.0, 150.0)
	root.add_child(label)


# --------------------------------------------------------------------------
# paved surfaces (the extra helpers that use the Poly Haven scans)


## Asphalt ribbon over a span of the spline, with its own solid driving surface.
## Use it to replace the dirt road on a paved map. `width` is full width.
static func tarmac(parent: Node3D, spline: RefCounted, from_distance: float,
		to_distance: float, width: float = ROAD_HALF * 2.0) -> void:
	if parent == null or spline == null or width <= 0.0:
		return
	var total: float = maxf(spline.total_length, 0.001)
	var span: float = fposmod(to_distance - from_distance, total)
	if span <= 0.01:
		return
	var steps: int = maxi(int(ceil(span / 2.0)), 1)
	var half: float = width * 0.5
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	for i in steps + 1:
		var s: float = from_distance + span * float(i) / float(steps)
		var frame: Dictionary = spline.sample(s)
		var centre: Vector3 = frame["position"] + Vector3.UP * (ROAD_Y + 0.02)
		var right: Vector3 = frame["right"]
		verts.append(centre - right * half)
		verts.append(centre + right * half)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		var v: float = s / 6.0
		uvs.append(Vector2(0.0, v))
		uvs.append(Vector2(1.0, v))
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
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_make_arrays(verts, norms, uvs, indices))
	var visual := MeshInstance3D.new()
	visual.name = "Tarmac_%d" % int(round(from_distance))
	visual.mesh = mesh
	visual.material_override = palette()["asphalt"] as Material
	parent.add_child(visual)
	var body := _static_root(parent, "TarmacCollision_%d" % int(round(from_distance)))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = false
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


## Worn-concrete pit apron beside the road at `distance`. The slab starts at
## the road edge and runs `length` metres along the track from `side`.
static func pit_surface(parent: Node3D, spline: RefCounted, distance: float,
		side: float, length: float, width: float = 7.0) -> void:
	if parent == null or spline == null or length <= 0.0 or width <= 0.0:
		return
	var direction: float = 1.0 if side >= 0.0 else -1.0
	var lateral: float = direction * (ROAD_HALF + width * 0.5)
	var root := _static_root(parent, "PitSurface_%d" % int(round(distance)),
		_track_transform(spline, distance, lateral, ROAD_Y + 0.015))
	var mesh: ArrayMesh = _flat_quad_mesh(width, length, 5.0)
	if mesh != null:
		var visual := MeshInstance3D.new()
		visual.name = "Concrete"
		visual.mesh = mesh
		visual.material_override = palette()["concrete"] as Material
		root.add_child(visual)
	_add_box_shape(root, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.05, 0.0)),
		Vector3(width, 0.10, length))


# --------------------------------------------------------------------------
# helpers


static func _static_root(parent: Node3D, node_name: String,
		xform: Transform3D = Transform3D.IDENTITY) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	body.transform = xform
	parent.add_child(body)
	return body


static func _add_box_shape(body: StaticBody3D, xform: Transform3D,
		size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	body.add_child(collision)


static func _add_visual(root: Node3D, batch: PropBatch, node_name: String,
		material: Material) -> void:
	var mesh: ArrayMesh = batch.build()
	if mesh == null:
		return
	var visual := MeshInstance3D.new()
	visual.name = node_name
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(visual)


static func _track_position(spline: RefCounted, distance: float,
		lateral: float, height: float = 0.0) -> Vector3:
	var frame: Dictionary = spline.sample(distance)
	return (frame["position"] as Vector3) + (frame["right"] as Vector3) * lateral \
		+ Vector3.UP * height


static func _track_transform(spline: RefCounted, distance: float, lateral: float,
		height: float = 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, spline.yaw_at(distance)),
		_track_position(spline, distance, lateral, height))


static func _outside_side(spline: RefCounted, distance: float) -> float:
	var before: float = spline.yaw_at(distance - 6.0)
	var after: float = spline.yaw_at(distance + 6.0)
	return 1.0 if angle_difference(before, after) > 0.0 else -1.0


static func _add_quad(verts: PackedVector3Array, colours: PackedColorArray,
		indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, colour: Color) -> void:
	var base: int = verts.size()
	for vertex: Vector3 in [a, b, c, d]:
		verts.append(vertex)
		colours.append(colour)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 3)


static func _append_quad_faces(faces: PackedVector3Array, a: Vector3,
		b: Vector3, c: Vector3, d: Vector3) -> void:
	faces.append(a)
	faces.append(b)
	faces.append(c)
	faces.append(a)
	faces.append(c)
	faces.append(d)


static func _make_arrays(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


static func _flat_quad_mesh(width: float, length: float,
		uv_scale: float) -> ArrayMesh:
	var hw: float = width * 0.5
	var hl: float = length * 0.5
	var verts := PackedVector3Array([
		Vector3(-hw, 0.0, -hl), Vector3(hw, 0.0, -hl),
		Vector3(hw, 0.0, hl), Vector3(-hw, 0.0, hl),
	])
	var norms := PackedVector3Array([
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(width / uv_scale, 0.0),
		Vector2(width / uv_scale, length / uv_scale),
		Vector2(0.0, length / uv_scale),
	])
	var indices := PackedInt32Array([0, 3, 2, 0, 2, 1])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_make_arrays(verts, norms, uvs, indices))
	return mesh
