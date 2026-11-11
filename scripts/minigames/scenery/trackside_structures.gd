extends RefCounted
## Circuit structures for Meadow Loop: grandstands with instanced crowds, the
## start gantry, the pit wall and the marshal posts.
##
## Everything that repeats is merged into one vertex-coloured mesh per group,
## and each grandstand owns its own crowd MultiMesh so the stand and its people
## are frustum- and distance-culled together. Grandstands swap to a blocky
## stand-in past 175 m and their crowd drops out at 150 m.

const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const TrackRoute := preload("res://scripts/minigames/scenery/track_route.gd")

const TITLE_FONT: String = "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"

const CROWD_SHIRTS: Array[Color] = [
	Color("e4572e"), Color("2e86ab"), Color("f6c945"), Color("3fa34d"),
	Color("b84a9c"), Color("f3f0e6"), Color("6c5b7b"), Color("e08e45"),
]
const SKIN_TONES: Array[Color] = [
	Color("f2c9a0"), Color("d9a06b"), Color("a86b3f"), Color("7a4a2b"),
	Color("e8b98a"),
]
const CONCRETE := Color("b9b4a8")
const STEEL := Color("4a5560")
const SEAT_BLUE := Color("8fa3b8")
const ROOF_RED := Color("c9553f")
const CREAM := Color("efe6cf")
const DARK := Color("2f2a26")
const MARSHAL_YELLOW := Color("f2c230")

## Lateral offsets, in metres from the centreline, that keep the zones apart:
## tyre walls at 6.6, the existing fence at 8.7, catch fence at 9.2, marshal
## posts at 11.6, grandstand fronts at 12.5.
const STAND_LATERAL: float = 19.0
const MARSHAL_LATERAL: float = 11.6
const PIT_WALL_LATERAL: float = 6.9

const ROWS: int = 7
const ROW_RISE: float = 0.62
const ROW_RUN: float = 1.18


## Builds every structure under `parent`, plus the shared staff figures.
static func build(parent: Node3D, spline: RefCounted, rng: RandomNumberGenerator,
		stats: Dictionary) -> void:
	if parent == null or spline == null:
		return
	var material: StandardMaterial3D = SceneryKit.vertex_material()
	var figures: Dictionary = _figure_meshes()
	var batch := PropBatch.new()
	var bodies: Array = []
	var heads: Array = []
	var shirts: Array = []
	var skins: Array = []
	_gantry(parent, batch, spline)
	_pit_wall(batch, spline, bodies, heads, shirts, skins, rng)
	_marshal_posts(batch, spline, bodies, heads, shirts, skins, stats)
	_grandstands(parent, spline, rng, material, figures, stats)
	var mesh: ArrayMesh = batch.build()
	if mesh != null:
		var structures := MeshInstance3D.new()
		structures.name = "CircuitStructures"
		structures.mesh = mesh
		structures.material_override = material
		structures.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(structures)
		SceneryKit.bump(stats, "draw_calls")
	_build_staff(parent, figures, bodies, heads, shirts, skins, stats)


## One low-poly body and head, shared by the crowd and the track staff.
static func _figure_meshes() -> Dictionary:
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
	return {
		"body": body,
		"head": head,
		"material": SceneryKit.instance_material(0.92),
	}


## Adds a crowd MeshInstance parented to `host`, using local-space transforms.
static func _add_figures(host: Node3D, figures: Dictionary, bodies: Array,
		heads: Array, shirts: Array, skins: Array, node_name: String,
		view_end: float) -> void:
	if bodies.is_empty():
		return
	var body_instance := SceneryKit.multimesh(figures["body"], figures["material"],
		bodies, node_name, false, shirts)
	SceneryKit.set_view(body_instance, 0.0, view_end)
	host.add_child(body_instance)
	var head_instance := SceneryKit.multimesh(figures["head"], figures["material"],
		heads, node_name + "Heads", false, skins)
	SceneryKit.set_view(head_instance, 0.0, view_end)
	host.add_child(head_instance)


## Marshals, pit crew and anyone else outside a stand: one small MultiMesh pair
## for the whole circuit, since there are only a dozen of them.
static func _build_staff(parent: Node3D, figures: Dictionary, bodies: Array,
		heads: Array, shirts: Array, skins: Array, stats: Dictionary) -> void:
	if bodies.is_empty():
		return
	_add_figures(parent, figures, bodies, heads, shirts, skins,
		"CircuitStaff", 150.0)
	SceneryKit.bump(stats, "figures", bodies.size())
	SceneryKit.bump(stats, "draw_calls", 2)


# --------------------------------------------------------------------------
# start gantry


static func _gantry(parent: Node3D, batch: RefCounted, spline: RefCounted) -> void:
	## A proper overhead gantry 30 m before the line. The start gate built by the
	## race controller sits at 0 m and stays untouched.
	var distance: float = fposmod(-30.0, spline.total_length)
	var root: Transform3D = TrackRoute.transform_at(spline, distance, 0.0)
	var tower: float = 7.6
	for side: float in [-1.0, 1.0]:
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(side * tower, 4.2, 0.0)), Vector3(1.0, 8.4, 1.0), STEEL)
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(side * tower, 0.18, 0.0)), Vector3(1.7, 0.36, 1.7), CONCRETE)
	batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 8.3, 0.0)),
		Vector3(tower * 2.0 + 1.0, 0.9, 0.9), STEEL)
	batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 7.15, 0.0)),
		Vector3(tower * 2.0 + 1.0, 1.5, 0.16), CREAM)
	for i in 7:
		var x: float = -tower + 0.8 + (tower * 2.0 - 1.6) * float(i) / 6.0
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(x, 7.8, 0.0)),
			Vector3(0.12, 1.4, 0.16), STEEL)
	var label := Label3D.new()
	label.name = "GantryBanner"
	label.text = "CART SLOP GP"
	label.font = load(TITLE_FONT)
	label.font_size = 96
	label.pixel_size = 0.017
	label.outline_size = 14
	label.outline_modulate = Color(0.12, 0.10, 0.20, 0.9)
	label.modulate = Color(1.0, 0.84, 0.28)
	label.transform = root * Transform3D(Basis.IDENTITY, Vector3(0.0, 7.15, 0.12))
	SceneryKit.set_view(label, 0.0, 240.0)
	parent.add_child(label)


# --------------------------------------------------------------------------
# pit wall


static func _pit_wall(batch: RefCounted, spline: RefCounted, bodies: Array,
		heads: Array, shirts: Array, skins: Array,
		rng: RandomNumberGenerator) -> void:
	## Low pit wall on the inside of the start straight with timing desks and
	## crew behind it. The wall itself is only knee high: decoration, no body.
	## It stops short of the start gantry at -30 m so the towers stay clear.
	var total: float = spline.total_length
	var start: float = fposmod(-78.0, total)
	for step in 9:
		var distance: float = start + float(step) * 5.0
		var root: Transform3D = TrackRoute.transform_at(spline, distance,
			PIT_WALL_LATERAL)
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)),
			Vector3(0.34, 1.0, 5.0), CONCRETE.darkened(0.06))
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.04, 0.0)),
			Vector3(0.42, 0.1, 5.04), CREAM)
		if step % 3 != 1:
			continue
		var desk: Transform3D = TrackRoute.transform_at(spline, distance + 2.5,
			7.7)
		batch.add_box(desk * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.56, 0.0)),
			Vector3(0.9, 1.12, 2.2), STEEL)
		batch.add_box(desk * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 0.0)),
			Vector3(1.0, 0.16, 2.3), DARK)
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(-0.22, 1.42, 0.0)),
			Vector3(0.1, 0.48, 1.4), DARK)
		for i in 2:
			var offset := Vector3(-0.5, 0.0, -0.55 + float(i) * 1.1)
			bodies.append(desk * Transform3D(Basis.IDENTITY,
				offset + Vector3.UP * 0.52))
			heads.append(desk * Transform3D(Basis.IDENTITY,
				offset + Vector3.UP * 1.12))
			shirts.append(CROWD_SHIRTS[rng.randi_range(0, CROWD_SHIRTS.size() - 1)])
			skins.append(SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)])


# --------------------------------------------------------------------------
# marshal posts


static func _marshal_posts(batch: RefCounted, spline: RefCounted, bodies: Array,
		heads: Array, shirts: Array, skins: Array, stats: Dictionary) -> void:
	## Small huts on the outside of the loop, each with a marshal and a flag.
	var fractions: Array[float] = [0.12, 0.37, 0.62, 0.87]
	var index: int = 0
	for fraction: float in fractions:
		var distance: float = spline.total_length * fraction
		var lateral: float = MARSHAL_LATERAL if index % 2 == 0 else -MARSHAL_LATERAL
		index += 1
		if not TrackRoute.spot_ok(spline, distance, lateral, 1.6, 1.6):
			continue
		var root: Transform3D = TrackRoute.transform_at(spline, distance, lateral)
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.15, 0.0)),
			Vector3(2.4, 2.3, 2.0), CREAM)
		batch.add_box(root * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12.0)),
			Vector3(0.0, 2.52, -0.18)), Vector3(2.9, 0.16, 2.7), ROOF_RED)
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(-1.22, 1.6, 0.0)),
			Vector3(0.08, 0.62, 1.5), DARK)
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(1.7, 1.9, 0.5)),
			Vector3(0.09, 3.8, 0.09), STEEL)
		batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(1.7, 3.55, 0.82)),
			Vector3(0.04, 0.5, 0.62), MARSHAL_YELLOW)
		bodies.append(root * Transform3D(Basis.IDENTITY, Vector3(-1.05, 0.52, -0.5)))
		heads.append(root * Transform3D(Basis.IDENTITY, Vector3(-1.05, 1.12, -0.5)))
		shirts.append(MARSHAL_YELLOW)
		skins.append(SKIN_TONES[index % SKIN_TONES.size()])
		SceneryKit.bump(stats, "marshal_posts")


# --------------------------------------------------------------------------
# grandstands


static func _grandstands(parent: Node3D, spline: RefCounted,
		rng: RandomNumberGenerator, material: StandardMaterial3D,
		figures: Dictionary, stats: Dictionary) -> void:
	var total: float = spline.total_length
	var spots: Array[Dictionary] = []
	# The main stand looks down the start straight from behind the pit wall; the
	# second one sits on the outside of the tightest bend.
	spots.append({"d": fposmod(-26.0, total), "lateral": STAND_LATERAL,
		"length": 30.0})
	for candidate: Dictionary in TrackRoute.corners(spline, 4, 0.16, 70.0):
		var lateral: float = float(candidate["outside"]) * STAND_LATERAL
		if TrackRoute.spot_ok(spline, float(candidate["d"]), lateral, 13.0, 6.5):
			spots.append({"d": float(candidate["d"]), "lateral": lateral,
				"length": 26.0})
			break
	var index: int = 0
	for spot: Dictionary in spots:
		var distance: float = float(spot["d"])
		var lateral: float = float(spot["lateral"])
		var length: float = float(spot["length"])
		if not TrackRoute.spot_ok(spline, distance, lateral, length * 0.5, 6.5):
			continue
		_build_stand(parent, spline, rng, material, figures, distance, lateral,
			length, index, stats)
		index += 1


static func _build_stand(parent: Node3D, spline: RefCounted,
		rng: RandomNumberGenerator, material: StandardMaterial3D,
		figures: Dictionary, distance: float, lateral: float, length: float,
		index: int, stats: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "Grandstand_%02d" % index
	root.transform = Transform3D(
		Basis(Vector3.UP, TrackRoute.facing_yaw(spline, distance, lateral)),
		TrackRoute.at(spline, distance, lateral))
	parent.add_child(root)
	var depth: float = float(ROWS) * ROW_RUN
	var front: float = -depth * 0.5
	var roof_y: float = ROW_RISE * float(ROWS) + 2.9
	var batch := PropBatch.new()
	for row in ROWS:
		var z: float = front + (float(row) + 0.5) * ROW_RUN
		var top: float = ROW_RISE * float(row + 1)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, top - 0.09, z)),
			Vector3(length, 0.18, ROW_RUN + 0.04), CONCRETE)
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, top * 0.5, z - ROW_RUN * 0.5)),
			Vector3(length, top, 0.14), CONCRETE.darkened(0.12))
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, top + 0.08, z + 0.18)),
			Vector3(length, 0.14, 0.40), SEAT_BLUE)
	batch.add_box(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-7.0)),
		Vector3(0.0, roof_y, 0.4)), Vector3(length + 1.6, 0.22, depth + 3.0),
		ROOF_RED)
	for i in 5:
		var x: float = -length * 0.5 + 0.8 + (length - 1.6) * float(i) / 4.0
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(x, roof_y * 0.5, front - 0.9)), Vector3(0.24, roof_y, 0.24),
			STEEL)
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, front - 1.05)),
		Vector3(length, 1.1, 0.18), STEEL)
	batch.add_box(Transform3D(Basis.IDENTITY,
		Vector3(0.0, roof_y * 0.55, depth * 0.5)),
		Vector3(length, roof_y * 1.1, 0.28), CONCRETE.darkened(0.2))

	# Crowd: one instanced figure per seat, in the stand's local space so the
	# MultiMesh AABB stays tight enough to cull with the structure.
	var seats: int = maxi(int((length - 0.6) / 0.78), 1)
	var crowd_bodies: Array = []
	var crowd_heads: Array = []
	var crowd_shirts: Array = []
	var crowd_skins: Array = []
	for row in ROWS:
		for seat in seats:
			if rng.randf() < 0.18:
				continue
			var x: float = -length * 0.5 + 0.5 \
				+ (length - 1.0) * float(seat) / float(maxi(seats - 1, 1))
			var top: float = ROW_RISE * float(row + 1)
			var scale: float = rng.randf_range(0.9, 1.08)
			var basis := Basis.IDENTITY.scaled(Vector3.ONE * scale)
			var z: float = front + (float(row) + 0.5) * ROW_RUN
			crowd_bodies.append(Transform3D(basis, Vector3(x, top + 0.34, z)))
			crowd_heads.append(Transform3D(basis, Vector3(x, top + 0.92, z)))
			crowd_shirts.append(
				CROWD_SHIRTS[rng.randi_range(0, CROWD_SHIRTS.size() - 1)])
			crowd_skins.append(
				SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)])

	var mesh: ArrayMesh = batch.build()
	if mesh != null:
		var detail := MeshInstance3D.new()
		detail.name = "StandDetail"
		detail.mesh = mesh
		detail.material_override = material
		detail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		SceneryKit.set_view(detail, 0.0, 175.0)
		root.add_child(detail)
		SceneryKit.bump(stats, "draw_calls")
	var far_batch := PropBatch.new()
	far_batch.add_box(Transform3D(Basis.IDENTITY,
		Vector3(0.0, ROW_RISE * float(ROWS) * 0.5, 0.0)),
		Vector3(length, ROW_RISE * float(ROWS), depth), CONCRETE.darkened(0.1))
	far_batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, roof_y, 0.4)),
		Vector3(length + 1.6, 0.6, depth + 3.0), ROOF_RED)
	var far_mesh: ArrayMesh = far_batch.build()
	if far_mesh != null:
		var block := MeshInstance3D.new()
		block.name = "StandBlock"
		block.mesh = far_mesh
		block.material_override = material
		block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		SceneryKit.set_view(block, 165.0, 720.0)
		root.add_child(block)
		SceneryKit.bump(stats, "draw_calls")
	_add_figures(root, figures, crowd_bodies, crowd_heads, crowd_shirts,
		crowd_skins, "StandCrowd", 150.0)
	SceneryKit.bump(stats, "grandstands")
	SceneryKit.bump(stats, "crowd", crowd_bodies.size())
	SceneryKit.bump(stats, "figures", crowd_bodies.size())
	SceneryKit.bump(stats, "draw_calls", 2)
