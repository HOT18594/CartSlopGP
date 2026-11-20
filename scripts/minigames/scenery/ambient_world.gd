extends Node3D
## Presentation-only themed life around tracks and arenas. Static detail is merged
## into one mesh; weather is one MultiMesh and landmarks use a few moving nodes.

const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")

var _theme: String = "meadow"
var _floor_y: float = -0.1
var _arena_style: String = ""
var _weather: MultiMeshInstance3D
var _weather_seeds: Array[Vector3] = []
var _weather_anchor: Vector3 = Vector3.ZERO
var _spinners: Array[Node3D] = []
var _bobbers: Array[Node3D] = []
var _bob_origins: Array[Vector3] = []
var _time: float = 0.0


static func build_track(parent: Node3D, spline: RefCounted, theme_id: String) -> Node3D:
	if parent == null or spline == null:
		return null
	var existing: Node = parent.get_node_or_null("AmbientWorld")
	if existing != null:
		return existing as Node3D
	var world := new()
	world.name = "AmbientWorld"
	parent.add_child(world)
	world._build_track(spline, theme_id)
	return world


## Adds themed life around a party arena. `context` keeps the ring honest about
## the arena it decorates instead of assuming flat ground at y = 0:
##   floor_y      world height the scenery stands on (city abyss, lava sea, ocean)
##   radius_in    inner radius of the ring (defaults clear of the play surface)
##   radius_out   outer radius of the ring
##   style        cluster style override (defaults to the theme)
static func build_arena(parent: Node3D, theme_id: String, half: float,
		context: Dictionary = {}) -> Node3D:
	if parent == null:
		return null
	var existing: Node = parent.get_node_or_null("AmbientWorld")
	if existing != null:
		return existing as Node3D
	var world := new()
	world.name = "AmbientWorld"
	parent.add_child(world)
	world._build_arena(theme_id, half, context)
	return world


func _ready() -> void:
	set_process(DisplayServer.get_name() != "headless")


func _build_track(track: RefCounted, theme_id: String) -> void:
	_theme = _normalise_theme(theme_id)
	_floor_y = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 8100 + _theme.hash()
	var batch := PropBatch.new()
	var total: float = maxf(float(track.get("total_length")), 1.0)
	# The perimeter pass is deliberately sparse: the map themes already carry the
	# dense mid-field scenery, and a 15 m offset used to drop containers and palms
	# into the dockyard's water. Dockyard skips the cluster pass entirely (its own
	# yard/forest builders own that space) and keeps only the landmark cranes.
	var cluster_count: int = 0 if _theme == "dockyard" else 56
	var samples: PackedVector3Array = PackedVector3Array()
	for index in 120:
		var frame: Dictionary = track.call("sample", total * float(index) / 120.0)
		samples.append(frame["position"] as Vector3)
	for index in cluster_count:
		var frame: Dictionary = track.call("sample",
			total * (float(index) + 0.35) / float(cluster_count))
		var point: Vector3 = frame["position"]
		var right: Vector3 = frame["right"]
		right.y = 0.0
		right = right.normalized()
		var forward: Vector3 = frame["forward"]
		var side: float = 1.0 if index % 2 == 0 else -1.0
		var distance: float = rng.randf_range(19.0, 34.0)
		var position: Vector3 = point + right * side * distance
		if not _clear_of_track(position, samples, 18.0):
			continue
		position.y = point.y - 0.18
		var yaw: float = atan2(-forward.x, -forward.z) + rng.randf_range(-0.4, 0.4)
		_add_cluster(batch, position, yaw, rng, index)
	var mesh := MeshInstance3D.new()
	mesh.name = "ThemedPerimeter"
	mesh.mesh = batch.build()
	mesh.material_override = SceneryKit.vertex_material()
	add_child(mesh)
	for index in 4:
		var frame: Dictionary = track.call("sample", total * (0.09 + float(index) * 0.235))
		var point: Vector3 = frame["position"]
		var right: Vector3 = frame["right"]
		right.y = 0.0
		right = right.normalized()
		var side: float = 1.0 if index % 2 == 0 else -1.0
		var offset: Vector3 = right * side * (24.0 + index * 2.0)
		var position: Vector3 = point + offset
		if not _clear_of_track(position, samples, 18.0):
			continue
		position.y = point.y
		# Face the landmark away from the racing line so crane arms and rotors
		# never reach back over the tarmac.
		var outward: Vector3 = offset.normalized()
		_add_landmark(position, index, atan2(outward.x, outward.z))
	_build_weather(Vector3.ZERO)


## True when `position` keeps `clearance` metres from every sampled centreline
## point. The track loops near itself, so an offset that is "safe" against its
## own sample can still land on the other side of the circuit.
func _clear_of_track(position: Vector3, samples: PackedVector3Array,
		clearance: float) -> bool:
	var flat := Vector2(position.x, position.z)
	for sample: Vector3 in samples:
		var dx: float = flat.x - sample.x
		var dz: float = flat.y - sample.z
		if dx * dx + dz * dz < clearance * clearance:
			return false
	return true


func _build_arena(theme_id: String, half: float, context: Dictionary) -> void:
	_theme = _normalise_theme(theme_id)
	_arena_style = str(context.get("style", _theme))
	_floor_y = float(context.get("floor_y", -0.1))
	var radius_in: float = float(context.get("radius_in", half + 18.0))
	var radius_out: float = float(context.get("radius_out", half + 40.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + _arena_style.hash()
	var batch := PropBatch.new()
	# Cluster width is 6-8 m, so space the ring by style instead of squeezing 72
	# placements into ~4-8 m of arc (which made the rings overlap themselves).
	var spacing: float = 16.0
	match _arena_style:
		"skyline":
			spacing = 24.0
		"foundry", "iceberg":
			spacing = 13.0
		"dockyard":
			spacing = 18.0
	var mid_radius: float = (radius_in + radius_out) * 0.5
	var count: int = clampi(int(TAU * mid_radius / spacing), 12, 44)
	for index in count:
		var angle: float = TAU * float(index) / float(count)
		var radius: float = rng.randf_range(radius_in, radius_out)
		var position := Vector3(cos(angle) * radius, _floor_y, sin(angle) * radius)
		_add_cluster(batch, position, -angle + rng.randf_range(-0.2, 0.2), rng, index)
	var mesh := MeshInstance3D.new()
	mesh.name = "ThemedPerimeter"
	mesh.mesh = batch.build()
	mesh.material_override = SceneryKit.vertex_material()
	add_child(mesh)
	for index in 4:
		var angle: float = TAU * (float(index) + 0.5) / 4.0
		var radius: float = radius_in + 6.0
		var position := Vector3(cos(angle) * radius, _floor_y, sin(angle) * radius)
		# The landmark's front (+Z) points away from the arena centre.
		_add_landmark(position, index, angle)
	_build_weather(Vector3(0.0, _floor_y, 0.0))


func _normalise_theme(raw: String) -> String:
	match raw:
		"harbour", "dockyard", "bt_ferries":
			return "dockyard"
		"snowfield", "glacier", "ko_iceberg":
			return "glacier"
		"canyon", "farmyard", "bt_labyrinth":
			return "canyon" if raw != "farmyard" else "meadow"
		"foundry", "ko_foundry":
			return "foundry"
		"stadium", "bt_plaza", "ko_rooftop", "sandbox":
			return "stadium"
		_:
			return "meadow"


func _add_cluster(batch: PropBatch, point: Vector3, yaw: float,
		rng: RandomNumberGenerator, index: int) -> void:
	var base := Transform3D(Basis(Vector3.UP, yaw), point)
	var style: String = _arena_style if _arena_style != "" else _theme
	match style:
		"skyline":
			# Rooftop arenas float above a city, so the "ring" is a skyline of
			# towers standing on the abyss plane below the action, never a
			# grandstand ring hanging in mid-air.
			var tower_w: float = rng.randf_range(7.0, 13.0)
			var tower_h: float = rng.randf_range(30.0, 62.0)
			var tower_col: Color = Color("3f4f78") if index % 2 == 0 \
				else Color("4b5d88")
			batch.add_box(base * Transform3D(Basis.IDENTITY,
				Vector3(0.0, tower_h * 0.5, 0.0)),
				Vector3(tower_w, tower_h, tower_w), tower_col)
			var lit: Color = Color("ffdf8a") if index % 3 == 0 else Color("8fd6f2")
			for row in 4:
				var window_y: float = tower_h * (0.18 + 0.18 * float(row))
				batch.add_box(base * Transform3D(Basis.IDENTITY,
					Vector3(0.0, window_y, tower_w * 0.5 + 0.02)),
					Vector3(tower_w * 0.55, 0.9, 0.08), lit)
			if index % 3 == 0:
				batch.add_box(base * Transform3D(Basis.IDENTITY,
					Vector3(0.0, tower_h + 0.6, 0.0)),
					Vector3(0.8, 1.2, 0.8), Color("f05a5a"))
		"iceberg":
			# Floes carry the pines so they stand in the arctic sea instead of
			# hovering over it.
			batch.add_cylinder(base * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 0.18, 0.0)), rng.randf_range(4.2, 6.4), 0.5, 9,
				Color("dff3fa"))
			for offset in [Vector3(-2.2, 0.0, 0.6), Vector3(2.0, 0.0, -1.2)]:
				_tree(batch, base * Transform3D(Basis.IDENTITY, offset),
					rng.randf_range(0.9, 1.3), Color("285e58"),
					Color("574b44"), true)
		"dockyard":
			if _arena_style == "dockyard":
				# Harbours have water: containers ride steel barges instead of
				# standing in the sea.
				batch.add_box(base * Transform3D(Basis.IDENTITY,
					Vector3(0.0, 0.3, 0.0)), Vector3(9.0, 0.6, 12.5),
					Color("3d4a55"))
				for level in 2:
					for column in 2:
						var p := Vector3(float(column) * 3.4 - 1.7,
							1.25 + level * 2.55, 0.0)
						batch.add_box(base * Transform3D(Basis.IDENTITY, p),
							Vector3(3.2, 2.45, 6.2),
							[Color("e45a45"), Color("2d9fbd"), Color("e8ad3e"),
								Color("567287")][(index + level + column) % 4])
			else:
				_dockyard_cluster(batch, base, rng, index)
		"foundry":
			for stack in 2:
				var height: float = 4.5 + float(stack) * 3.0
				batch.add_cylinder(base * Transform3D(Basis.IDENTITY,
					Vector3(float(stack) * 3.0 - 1.5, height * 0.5, 0.0)),
					0.72, height, 10, Color("3f424b"))
				batch.add_cylinder(base * Transform3D(Basis.IDENTITY,
					Vector3(float(stack) * 3.0 - 1.5, height - 0.2, 0.0)),
					0.9, 0.4, 10, Color("ee7441"))
			batch.add_box(base * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 3.0)),
				Vector3(7.0, 0.35, 2.4), Color("f06032"))
		"meadow":
			for offset in [Vector3(-2.2, 0.0, 0.8), Vector3(1.8, 0.0, -1.4)]:
				_tree(batch, base * Transform3D(Basis.IDENTITY, offset), rng.randf_range(0.8, 1.25),
					Color("3d9148"), Color("765036"), false)
			if index % 3 == 0:
				batch.add_cylinder(base * Transform3D(Basis(Vector3.FORWARD, PI * 0.5),
					Vector3(0.0, 0.65, 2.6)), 0.72, 1.5, 10, Color("e5b94f"))
			for flower in 5:
				var p := Vector3(rng.randf_range(-3.0, 3.0), 0.15, rng.randf_range(-3.0, 3.0))
				batch.add_box(base * Transform3D(Basis.IDENTITY, p), Vector3(0.18, 0.3, 0.18),
					Color("ffd55c") if flower % 2 == 0 else Color("f48db5"))
		"canyon":
			for rock in 3:
				var p := Vector3(rng.randf_range(-2.6, 2.6), 0.0, rng.randf_range(-2.0, 2.0))
				var height: float = rng.randf_range(2.0, 6.5)
				batch.add_cone(base * Transform3D(Basis.IDENTITY, p + Vector3.UP * height * 0.5),
					rng.randf_range(1.0, 2.2), height, 6,
					Color("bd5e3d") if rock % 2 == 0 else Color("db8050"))
			if index % 2 == 0:
				_cactus(batch, base * Transform3D(Basis.IDENTITY, Vector3(3.2, 0.0, 0.0)), rng)
		"glacier":
			for offset in [Vector3(-2.5, 0.0, 0.0), Vector3(2.1, 0.0, -1.5)]:
				_tree(batch, base * Transform3D(Basis.IDENTITY, offset), rng.randf_range(0.9, 1.35),
					Color("285e58"), Color("574b44"), true)
			for crystal in 3:
				var height: float = rng.randf_range(1.4, 3.8)
				batch.add_cone(base * Transform3D(Basis.IDENTITY,
					Vector3(2.8 + crystal * 0.6, height * 0.5, 2.0)), 0.55, height, 5, Color("89e5f2"))
		_:
			for row in 3:
				batch.add_box(base * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.45 + row * 0.55, row * 0.9)),
					Vector3(7.5, 0.5, 1.1), Color("43566f"))
				for seat in 8:
					var colors: Array[Color] = [Color("ef5c67"), Color("f4c84c"), Color("49b7d1"), Color("f2eee2")]
					batch.add_box(base * Transform3D(Basis.IDENTITY,
						Vector3(-3.1 + seat * 0.9, 0.95 + row * 0.55, row * 0.9)),
						Vector3(0.48, 0.65, 0.48), colors[(index + row + seat) % colors.size()])


## The dockyard's land-side container stack (used by racing tracks).
func _dockyard_cluster(batch: PropBatch, base: Transform3D,
		rng: RandomNumberGenerator, index: int) -> void:
	var colors: Array[Color] = [Color("e45a45"), Color("2d9fbd"), Color("e8ad3e"), Color("567287")]
	for level in 2:
		for column in 2:
			var p := Vector3(float(column) * 3.4 - 1.7, 1.3 + level * 2.55, 0.0)
			batch.add_box(base * Transform3D(Basis.IDENTITY, p), Vector3(3.2, 2.45, 6.2),
				colors[(index + level + column) % colors.size()])
			for rib in 5:
				batch.add_box(base * Transform3D(Basis.IDENTITY, p + Vector3(-1.61, 0.0, -2.4 + rib * 1.2)),
					Vector3(0.06, 2.1, 0.08), Color("d5e0db"))
	batch.add_cylinder(base * Transform3D(Basis.IDENTITY, Vector3(4.6, 1.0, 2.8)),
		0.8, 2.0, 12, Color("e5b74f"))


func _tree(batch: PropBatch, base: Transform3D, scale_value: float,
		leaf: Color, trunk: Color, snow: bool) -> void:
	batch.add_cylinder(base * Transform3D(Basis.IDENTITY, Vector3.UP * 1.5 * scale_value),
		0.28 * scale_value, 3.0 * scale_value, 7, trunk)
	for tier in 3:
		var height: float = (2.4 + tier * 1.25) * scale_value
		batch.add_cone(base * Transform3D(Basis.IDENTITY, Vector3.UP * height),
			(2.1 - tier * 0.42) * scale_value, 3.1 * scale_value, 8, leaf.lightened(tier * 0.05))
		if snow:
			batch.add_cone(base * Transform3D(Basis.IDENTITY, Vector3.UP * (height + 0.32 * scale_value)),
				(1.82 - tier * 0.38) * scale_value, 2.35 * scale_value, 8, Color("e9f7f5"))


func _cactus(batch: PropBatch, base: Transform3D, rng: RandomNumberGenerator) -> void:
	var height: float = rng.randf_range(2.5, 4.5)
	var green := Color("39855c")
	batch.add_cylinder(base * Transform3D(Basis.IDENTITY, Vector3.UP * height * 0.5),
		0.32, height, 8, green)
	for side in [-1.0, 1.0]:
		batch.add_cylinder(base * Transform3D(Basis(Vector3.FORWARD, PI * 0.5),
			Vector3(side * 0.65, height * 0.52, 0.0)), 0.22, 1.25, 8, green)
		batch.add_cylinder(base * Transform3D(Basis.IDENTITY,
			Vector3(side * 1.2, height * 0.72, 0.0)), 0.22, 1.35, 8, green)


func _add_landmark(point: Vector3, index: int, yaw: float = 0.0) -> void:
	match _theme:
		"meadow":
			_windmill(point, index, yaw)
		"dockyard", "foundry":
			_crane(point, index, yaw)
		"glacier":
			_gondola(point, index, yaw)
		_:
			_balloon(point, index)


func _windmill(point: Vector3, index: int, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "Windmill_%d" % index
	root.position = point
	root.rotation.y = yaw
	add_child(root)
	_box(root, Vector3(0.0, 4.0, 0.0), Vector3(1.2, 8.0, 1.2), Color("eee0bd"))
	var rotor := Node3D.new()
	rotor.position = Vector3(0.0, 7.4, -0.8)
	root.add_child(rotor)
	for blade in 4:
		var piece := _box(rotor, Vector3(0.0, 1.65, 0.0), Vector3(0.48, 3.5, 0.18),
			Color("ef6355") if blade % 2 == 0 else Color("f7d156"))
		piece.rotation.z = blade * PI * 0.5
		piece.position = Vector3(-sin(piece.rotation.z), cos(piece.rotation.z), 0.0) * 1.65
	_spinners.append(rotor)


func _crane(point: Vector3, index: int, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "AnimatedCrane_%d" % index
	root.position = point
	root.rotation.y = yaw
	add_child(root)
	var color := Color("f0b73e") if _theme == "dockyard" else Color("e36642")
	_box(root, Vector3(0.0, 6.0, 0.0), Vector3(0.8, 12.0, 0.8), color)
	_box(root, Vector3(3.5, 11.7, 0.0), Vector3(8.0, 0.65, 0.65), color)
	var hook := Node3D.new()
	hook.position = Vector3(6.8, 7.0, 0.0)
	root.add_child(hook)
	_box(hook, Vector3(0.0, 2.0, 0.0), Vector3(0.10, 4.0, 0.10), Color("303d48"))
	_box(hook, Vector3.ZERO, Vector3(0.75, 0.75, 0.75), Color("e7e1ce"))
	_bobbers.append(hook)
	_bob_origins.append(hook.position)


func _gondola(point: Vector3, index: int, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "SkiLift_%d" % index
	root.position = point
	root.rotation.y = yaw
	add_child(root)
	_box(root, Vector3(-6.0, 4.0, 0.0), Vector3(0.5, 8.0, 0.5), Color("586b7a"))
	_box(root, Vector3(6.0, 4.0, 0.0), Vector3(0.5, 8.0, 0.5), Color("586b7a"))
	_box(root, Vector3(0.0, 7.8, 0.0), Vector3(12.0, 0.10, 0.10), Color("2f3d48"))
	var car := Node3D.new()
	car.position = Vector3(-4.0, 6.4, 0.0)
	root.add_child(car)
	_box(car, Vector3.ZERO, Vector3(2.0, 1.7, 1.7), Color("e85352"))
	_box(car, Vector3(0.0, 1.2, 0.0), Vector3(0.12, 1.0, 0.12), Color("374955"))
	_bobbers.append(car)
	_bob_origins.append(car.position)


func _balloon(point: Vector3, index: int) -> void:
	var root := Node3D.new()
	root.name = "FestivalBalloon_%d" % index
	root.position = point + Vector3.UP * 9.0
	add_child(root)
	var color := Color("ed5d68") if index % 2 == 0 else Color("f1bd42")
	var sphere := SphereMesh.new()
	sphere.radius = 2.4
	sphere.height = 4.8
	sphere.radial_segments = 12
	sphere.rings = 6
	var mesh := MeshInstance3D.new()
	mesh.mesh = sphere
	mesh.material_override = _material(color)
	root.add_child(mesh)
	_box(root, Vector3(0.0, -3.0, 0.0), Vector3(1.2, 0.8, 1.2), Color("8a5b3d"))
	_bobbers.append(root)
	_bob_origins.append(root.position)


func _box(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = point
	instance.material_override = _material(color)
	parent.add_child(instance)
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _build_weather(anchor: Vector3) -> void:
	_weather_anchor = anchor
	var mesh := BoxMesh.new()
	var color := Color.WHITE
	match _theme:
		"glacier":
			mesh.size = Vector3(0.12, 0.12, 0.12)
		"dockyard":
			mesh.size = Vector3(0.035, 1.1, 0.035)
			color = Color("a6d8e8")
		"canyon":
			mesh.size = Vector3(0.16, 0.08, 0.16)
			color = Color("edb276")
		"foundry":
			mesh.size = Vector3(0.10, 0.18, 0.10)
			color = Color("ff9b42")
		"stadium":
			mesh.size = Vector3(0.12, 0.05, 0.22)
			color = Color("ffd45e")
		_:
			mesh.size = Vector3(0.10, 0.06, 0.18)
			color = Color("d8ef87")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12000 + _theme.hash()
	var transforms: Array = []
	for index in 120:
		var seed_value := Vector3(rng.randf_range(-28.0, 28.0), rng.randf_range(0.0, 18.0),
			rng.randf_range(-28.0, 28.0))
		_weather_seeds.append(seed_value)
		transforms.append(Transform3D(Basis.IDENTITY, anchor + seed_value))
	_weather = SceneryKit.multimesh(mesh, _material(color), transforms, "AmbientWeather", false)
	var material := _weather.material_override as StandardMaterial3D
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_child(_weather)


func _process(delta: float) -> void:
	_time += delta
	for index in _spinners.size():
		_spinners[index].rotation.z += delta * (0.45 + index * 0.08)
	for index in _bobbers.size():
		var node: Node3D = _bobbers[index]
		if _theme == "glacier":
			node.position = _bob_origins[index] + Vector3(sin(_time * 0.32 + index) * 4.2, 0.0, 0.0)
		elif _theme == "dockyard" or _theme == "foundry":
			node.position = _bob_origins[index] + Vector3.UP * sin(_time * 0.7 + index) * 1.2
		else:
			node.position = _bob_origins[index] + Vector3(sin(_time * 0.2 + index) * 2.0,
				sin(_time * 0.65 + index) * 0.6, 0.0)
			node.rotation.y += delta * 0.08
	if _weather == null:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var center: Vector3 = camera.global_position if camera != null else _weather_anchor
	for index in _weather_seeds.size():
		var seed_value: Vector3 = _weather_seeds[index]
		var p := seed_value
		match _theme:
			"glacier":
				p.y = fposmod(seed_value.y - _time * 2.1, 18.0)
				p.x += sin(_time * 0.8 + index) * 1.4
			"dockyard":
				p.y = fposmod(seed_value.y - _time * 15.0, 18.0)
				p.x += _time * 0.8
			"foundry":
				p.y = fposmod(seed_value.y + _time * 2.8, 18.0)
				p.x += sin(_time + index) * 0.7
			"canyon":
				p.x = fposmod(seed_value.x + _time * 3.0 + 28.0, 56.0) - 28.0
				p.y = 1.0 + seed_value.y * 0.35 + sin(_time + index) * 0.6
			_:
				p.y = fposmod(seed_value.y - _time * 0.65, 18.0)
				p.x += sin(_time * 0.45 + index) * 2.0
		var basis := Basis(Vector3.UP, _time * 0.4 + index)
		_weather.multimesh.set_instance_transform(index, Transform3D(basis, center + p))
