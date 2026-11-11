extends RefCounted
## Trackside furniture for Meadow Loop: tyre walls, sponsor banners, distance
## boards, catch fences and the spectator car park.
##
## Only the tyre walls are solid: they are the one addition that is meant to
## stop a kart, so they carry a WORLD collision layer. Everything else is pure
## decoration with no body at all. Repeated props are MultiMeshes and the rest
## shares one merged mesh, so the whole layer is a handful of draw calls.

const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const TrackRoute := preload("res://scripts/minigames/scenery/track_route.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

const TITLE_FONT: String = "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"

## Lateral offsets, in metres from the centreline. The barrier bodies sit at
## ROAD_HALF + 0.5 = 6.0, so the tyre wall at 6.6 is outside the racing surface
## while still reading as a track-edge barrier.
const TYRE_LATERAL: float = 6.6
const BANNER_LATERAL: float = 8.0
const BOARD_LATERAL: float = 8.1
const CATCH_FENCE_LATERAL: float = 9.2

const TYRE_BLACK := Color("121114")
const TYRE_RED := Color("c23a2c")
const TYRE_CREAM := Color("eee6d2")
const STEEL := Color("4a5560")
const DARK := Color("2f2a26")
const CREAM := Color("efe6cf")
const BANNER_COLORS: Array[Color] = [
	Color("2e86ab"), Color("e4572e"), Color("f6c945"), Color("3fa34d"),
	Color("b84a9c"), Color("c9553f"),
]
const BANNER_TEXTS: PackedStringArray = [
	"SLOP ENERGY", "GRIP TAPE", "MEADOW TYRES", "TURBO TEA",
	"BIG HAT CO", "CART SLOP GP",
]
const CAR_COLORS: Array[Color] = [
	Color("d94f45"), Color("3f7fbf"), Color("e8c34a"), Color("4f9e57"),
	Color("c9c4b8"), Color("8a5bb5"), Color("d97f3f"), Color("2f4a63"),
]


## Builds every prop under `parent`, including the solid tyre walls.
static func build(parent: Node3D, spline: RefCounted, rng: RandomNumberGenerator,
		stats: Dictionary) -> void:
	if parent == null or spline == null:
		return
	var material: StandardMaterial3D = SceneryKit.vertex_material()
	var batch := PropBatch.new()
	_tyre_walls(parent, spline, stats)
	_banners(parent, batch, spline, stats)
	_distance_boards(parent, batch, spline, stats)
	_catch_fences(parent, batch, spline)
	var mesh: ArrayMesh = batch.build()
	if mesh != null:
		var props := MeshInstance3D.new()
		props.name = "CircuitProps"
		props.mesh = mesh
		props.material_override = material
		props.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(props)
		SceneryKit.bump(stats, "draw_calls")
	_spectator_cars(parent, spline, rng, stats)


# --------------------------------------------------------------------------
# tyre walls - the only solid addition


static func _tyre_walls(parent: Node3D, spline: RefCounted,
		stats: Dictionary) -> void:
	## Stacked tyres around the outside of the four tightest bends, with a
	## red/cream top row. Solid on the WORLD layer, so a kart that gets past the
	## invisible barrier is stopped by something it can see.
	var tyre_radius: float = 0.46
	var tyre_height: float = 0.30
	var spacing: float = 1.15
	var stacks_per_wall: int = 24
	var transforms: Array = []
	var colors: Array = []
	var solid := StaticBody3D.new()
	solid.name = "TyreWalls"
	solid.collision_layer = CollisionLayers.WORLD
	solid.collision_mask = 0
	parent.add_child(solid)
	var corners: Array[Dictionary] = TrackRoute.corners(spline, 4, 0.15, 70.0)
	var walls: int = 0
	for candidate: Dictionary in corners:
		var distance: float = float(candidate["d"])
		var outside: float = float(candidate["outside"])
		var lateral: float = outside * TYRE_LATERAL
		if not TrackRoute.spot_ok(spline, distance, lateral,
				float(stacks_per_wall) * spacing * 0.5, tyre_radius, 0.5):
			continue
		var run_start: float = distance - float(stacks_per_wall - 1) * spacing * 0.5
		for stack in stacks_per_wall:
			var d: float = run_start + float(stack) * spacing
			var root: Transform3D = TrackRoute.transform_at(spline, d, lateral)
			for level in 3:
				transforms.append(root * Transform3D(Basis.IDENTITY,
					Vector3(0.0, tyre_height * 0.5 + float(level) * tyre_height,
						0.0)))
				if level == 2:
					colors.append(TYRE_RED if (stack + level) % 2 == 0 else TYRE_CREAM)
				else:
					colors.append(TYRE_BLACK)
			# One box per three stacks keeps the shape count low while still
			# covering the gap between the tyres.
			if stack % 3 == 0:
				var shape := BoxShape3D.new()
				shape.size = Vector3(tyre_radius * 2.0, tyre_height * 3.0,
					spacing * 3.0)
				var collision := CollisionShape3D.new()
				collision.shape = shape
				collision.transform = root * Transform3D(Basis.IDENTITY,
					Vector3(0.0, tyre_height * 1.5, 0.0))
				solid.add_child(collision)
		walls += 1
		SceneryKit.bump(stats, "tyres", stacks_per_wall * 3)
	if transforms.is_empty():
		solid.queue_free()
		return
	var tyre_mesh := CylinderMesh.new()
	tyre_mesh.top_radius = tyre_radius
	tyre_mesh.bottom_radius = tyre_radius
	tyre_mesh.height = tyre_height
	tyre_mesh.radial_segments = 12
	tyre_mesh.rings = 1
	var material: StandardMaterial3D = SceneryKit.instance_material(0.98)
	var tyres := SceneryKit.multimesh(tyre_mesh, material, transforms,
		"TyreWalls", false, colors)
	SceneryKit.set_view(tyres, 0.0, 260.0)
	parent.add_child(tyres)
	SceneryKit.bump(stats, "tyre_walls", walls)
	SceneryKit.bump(stats, "draw_calls")


# --------------------------------------------------------------------------
# signage


static func _banners(parent: Node3D, batch: RefCounted, spline: RefCounted,
		stats: Dictionary) -> void:
	## Long hoardings parallel to the barrier on the two main straights, facing
	## the track. Text is one Label3D each, so six boards stay six labels.
	var index: int = 0
	for straight: Dictionary in TrackRoute.straights(spline, 2):
		var length: float = float(straight["length"])
		if length < 34.0:
			continue
		for slot in 2:
			var distance: float = float(straight["d"]) - length * 0.24 \
				+ float(slot) * length * 0.48
			var lateral: float = BANNER_LATERAL if index % 2 == 0 else -BANNER_LATERAL
			var text: String = BANNER_TEXTS[index % BANNER_TEXTS.size()]
			var color: Color = BANNER_COLORS[index % BANNER_COLORS.size()]
			index += 1
			if not TrackRoute.spot_ok(spline, distance, lateral, 3.6, 0.3, 0.4):
				continue
			var root: Transform3D = Transform3D(
				Basis(Vector3.UP, TrackRoute.facing_yaw(spline, distance, lateral)),
				TrackRoute.at(spline, distance, lateral))
			batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.45, 0.0)),
				Vector3(7.2, 1.2, 0.14), color)
			batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.82, 0.0)),
				Vector3(7.3, 0.1, 0.2), DARK)
			for post: float in [-3.1, 3.1]:
				batch.add_box(root * Transform3D(Basis.IDENTITY,
					Vector3(post, 0.7, 0.0)), Vector3(0.14, 1.4, 0.14), DARK)
			var label := Label3D.new()
			label.name = "Banner_%02d" % index
			label.text = text
			label.font = load(TITLE_FONT)
			label.font_size = 72
			label.pixel_size = 0.0095
			label.outline_size = 10
			label.outline_modulate = Color(0.12, 0.10, 0.20, 0.8)
			label.modulate = CREAM
			label.transform = root * Transform3D(Basis(Vector3.UP, PI),
				Vector3(0.0, 1.47, -0.10))
			SceneryKit.set_view(label, 0.0, 150.0)
			parent.add_child(label)
			SceneryKit.bump(stats, "banners")


static func _distance_boards(parent: Node3D, batch: RefCounted,
		spline: RefCounted, stats: Dictionary) -> void:
	## 100 m and 50 m boards on the outside of the four tightest bends. They face
	## the oncoming cars, so a plain track yaw is correct here.
	var markers: Array[Dictionary] = [
		{"offset": -34.0, "text": "100"},
		{"offset": -18.0, "text": "50"},
	]
	for candidate: Dictionary in TrackRoute.corners(spline, 4, 0.15, 70.0):
		var lateral: float = float(candidate["outside"]) * BOARD_LATERAL
		for marker: Dictionary in markers:
			var distance: float = float(candidate["d"]) + float(marker["offset"])
			var root: Transform3D = TrackRoute.transform_at(spline, distance,
				lateral)
			batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.45, 0.0)),
				Vector3(1.7, 1.0, 0.12), CREAM)
			batch.add_box(root * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.9, 0.01)),
				Vector3(1.72, 0.16, 0.14), TYRE_RED)
			for post: float in [-0.62, 0.62]:
				batch.add_box(root * Transform3D(Basis.IDENTITY,
					Vector3(post, 0.65, 0.0)), Vector3(0.1, 1.3, 0.1), STEEL)
			var label := Label3D.new()
			label.text = str(marker["text"])
			label.font = load(TITLE_FONT)
			label.font_size = 96
			label.pixel_size = 0.0075
			label.outline_size = 10
			label.outline_modulate = Color(0.12, 0.10, 0.20, 0.85)
			label.modulate = DARK
			label.transform = root * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 1.42, 0.09))
			SceneryKit.set_view(label, 0.0, 150.0)
			parent.add_child(label)
			SceneryKit.bump(stats, "distance_boards")


# --------------------------------------------------------------------------
# catch fences


static func _catch_fences(parent: Node3D, batch: RefCounted,
		spline: RefCounted) -> void:
	## Tall wire catch fencing along the straights, made from one instanced bar
	## mesh plus merged posts and rails. Hidden past 90 m, where a 4 cm bar is
	## sub-pixel and would only shimmer.
	var bars: Array = []
	for straight: Dictionary in TrackRoute.straights(spline, 2):
		var length: float = minf(float(straight["length"]) * 0.72, 44.0)
		if length < 16.0:
			continue
		var run_start: float = float(straight["d"]) - length * 0.5
		for side: float in [-1.0, 1.0]:
			var lateral: float = side * CATCH_FENCE_LATERAL
			var count: int = int(length / 0.5)
			for i in count + 1:
				var distance: float = run_start + float(i) * 0.5
				bars.append(Transform3D(
					Basis(Vector3.UP, TrackRoute.facing_yaw(spline, distance, lateral)),
					TrackRoute.at(spline, distance, lateral, 1.32)))
			var posts: int = int(length / 4.0)
			for i in posts + 1:
				var distance: float = run_start + float(i) * 4.0
				var root: Transform3D = Transform3D(
					Basis(Vector3.UP, TrackRoute.facing_yaw(spline, distance, lateral)),
					TrackRoute.at(spline, distance, lateral))
				batch.add_box(root * Transform3D(Basis.IDENTITY,
					Vector3(0.0, 1.5, 0.0)), Vector3(0.14, 3.0, 0.14), STEEL)
			for i in posts:
				var distance: float = run_start + float(i) * 4.0 + 2.0
				var root: Transform3D = Transform3D(
					Basis(Vector3.UP, TrackRoute.facing_yaw(spline, distance, lateral)),
					TrackRoute.at(spline, distance, lateral))
				batch.add_box(root * Transform3D(Basis.IDENTITY,
					Vector3(0.0, 2.86, 0.0)), Vector3(4.2, 0.1, 0.1), STEEL)
	if bars.is_empty():
		return
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(0.045, 2.64, 0.045)
	var material: StandardMaterial3D = SceneryKit.instance_material(0.95)
	var fence := SceneryKit.multimesh(bar_mesh, material, bars, "CatchFence",
		false)
	SceneryKit.set_view(fence, 0.0, 90.0)
	parent.add_child(fence)


# --------------------------------------------------------------------------
# spectator car park


static func _spectator_cars(parent: Node3D, spline: RefCounted,
		rng: RandomNumberGenerator, stats: Dictionary) -> void:
	## Parked cars in a paddock beyond the fence, tinted per instance. The mesh
	## is built once and drawn as a single MultiMesh: no glTF loads, no bodies.
	var batch := PropBatch.new()
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.62, 0.0)),
		Vector3(1.85, 0.62, 4.1), Color.WHITE)
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.06, -0.2)),
		Vector3(1.55, 0.52, 1.9), Color(0.86, 0.88, 0.92))
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.42, 2.06)),
		Vector3(1.7, 0.22, 0.12), Color(0.35, 0.36, 0.38))
	for x: float in [-0.84, 0.84]:
		for z: float in [-1.32, 1.32]:
			batch.add_cylinder(Transform3D(Basis(Vector3.BACK, PI * 0.5),
				Vector3(x, 0.34, z)), 0.34, 0.24, 8, Color(0.16, 0.15, 0.17))
	var mesh: ArrayMesh = batch.build()
	if mesh == null:
		return
	var transforms: Array = []
	var colors: Array = []
	var total: float = spline.total_length
	var attempts: int = 0
	while transforms.size() < 20 and attempts < 90:
		attempts += 1
		var distance: float = fposmod(-70.0 + rng.randf() * 68.0, total)
		var lateral: float = -rng.randf_range(26.0, 42.0)
		var point: Vector3 = TrackRoute.at(spline, distance, lateral)
		if not TrackRoute.free_ground(spline, point, 2.8):
			continue
		var basis := Basis(Vector3.UP,
			spline.yaw_at(distance) + rng.randf_range(-0.45, 0.45))
		transforms.append(Transform3D(basis, point))
		colors.append(CAR_COLORS[rng.randi_range(0, CAR_COLORS.size() - 1)])
	if transforms.is_empty():
		return
	var material: StandardMaterial3D = SceneryKit.instance_material(0.55)
	var cars := SceneryKit.multimesh(mesh, material, transforms, "SpectatorCars",
		false, colors)
	SceneryKit.set_view(cars, 0.0, 320.0)
	parent.add_child(cars)
	SceneryKit.bump(stats, "spectator_cars", transforms.size())
	SceneryKit.bump(stats, "draw_calls")
