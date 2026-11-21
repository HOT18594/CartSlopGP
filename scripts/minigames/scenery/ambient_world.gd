extends Node3D
## Presentation-only themed life around tracks and arenas. Static detail is merged
## into one mesh via LandscapeSculptor + PropBatch; weather is one MultiMesh plus
## optional biome GPU particles; landmarks use smooth animated pivots.

const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const LandscapeSculptor := preload("res://scripts/minigames/scenery/landscape_sculptor.gd")

var _theme: String = "meadow"
var _floor_y: float = -0.1
var _arena_style: String = ""
var _weather: MultiMeshInstance3D
var _weather_seeds: Array[Vector3] = []
var _weather_anchor: Vector3 = Vector3.ZERO
var _anim: Dictionary = {}
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


## Allows map themes to register their own moving landmark pivots into the
## shared AmbientWorld animation loop (skipped in headless).
func get_anim_registry() -> Dictionary:
	return _anim


static func anim_of(parent: Node) -> Dictionary:
	if parent == null:
		return {}
	var aw := parent.get_node_or_null("AmbientWorld")
	if aw != null and aw.has_method("get_anim_registry"):
		return aw.call("get_anim_registry") as Dictionary
	return {}


func _ready() -> void:
	set_process(DisplayServer.get_name() != "headless")


func _build_track(track: RefCounted, theme_id: String) -> void:
	_theme = _normalise_theme(theme_id)
	_floor_y = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 8100 + _theme.hash()
	var batch := PropBatch.new()
	var total: float = maxf(float(track.get("total_length")), 1.0)
	var samples := PackedVector3Array()
	var bounds_min := Vector3(INF, INF, INF)
	var bounds_max := Vector3(-INF, -INF, -INF)
	for index in 160:
		var frame: Dictionary = track.call("sample", total * float(index) / 160.0)
		var pt: Vector3 = frame["position"] as Vector3
		samples.append(pt)
		bounds_min = bounds_min.min(pt)
		bounds_max = bounds_max.max(pt)
	var center: Vector3 = (bounds_min + bounds_max) * 0.5
	var radius_est: float = maxf(Vector2(bounds_max.x - bounds_min.x, bounds_max.z - bounds_min.z).length() * 0.5, 120.0)

	# Outer sculpted mountain / mesa / headland horizon ring surrounding the circuit
	# so the track feels enveloped in a living 360-degree landscape.
	# Clearance is measured against each landform's real footprint (base radius
	# x spread + margin): a flat 36 m gate let 80 m-wide peaks land on the road.
	if _theme != "dockyard":
		var ring_count: int = 20
		for i in ring_count:
			var ang: float = TAU * float(i) / float(ring_count) + rng.randf_range(-0.08, 0.08)
			var dist: float = radius_est + rng.randf_range(55.0, 145.0)
			var pos := Vector3(center.x + cos(ang) * dist, -1.0, center.z + sin(ang) * dist)
			var foot: float = 90.0
			match _theme:
				"glacier":
					foot = 54.0 * 1.5 + 16.0
				"canyon":
					foot = 42.0 + 16.0
				"stadium":
					foot = 56.0 * 1.2 + 16.0
			if not _clear_of_track(pos, samples, foot):
				continue
			match _theme:
				"glacier":
					LandscapeSculptor.add_alpine_mountain(batch, pos,
						rng.randf_range(28.0, 54.0), rng.randf_range(38.0, 86.0), rng)
				"canyon":
					if i % 3 == 0:
						LandscapeSculptor.add_canyon_spire(batch, pos,
							rng.randf_range(8.0, 15.0), rng.randf_range(24.0, 44.0), rng)
					else:
						LandscapeSculptor.add_stratified_mesa(batch, pos,
							rng.randf_range(22.0, 42.0), rng.randf_range(24.0, 52.0), 4, rng)
				"stadium":
					LandscapeSculptor.add_woodland_hill(batch, pos,
						rng.randf_range(30.0, 56.0), rng.randf_range(26.0, 50.0),
						rng.randf_range(16.0, 34.0), rng, {
							"skirt": Color("559c3e"),
							"mid": Color("67b54a"),
							"top": Color("7bc759"),
						})
				_:
					LandscapeSculptor.add_woodland_hill(batch, pos,
						rng.randf_range(32.0, 62.0), rng.randf_range(28.0, 54.0),
						rng.randf_range(22.0, 48.0), rng)

	# Mid-field clusters well clear of the widened lane.
	var cluster_count: int = 0 if _theme == "dockyard" else 42
	for index in cluster_count:
		var frame: Dictionary = track.call("sample",
			total * (float(index) + 0.35) / float(cluster_count))
		var point: Vector3 = frame["position"]
		var right: Vector3 = frame["right"]
		right.y = 0.0
		right = right.normalized()
		var forward: Vector3 = frame["forward"]
		var side: float = 1.0 if index % 2 == 0 else -1.0
		var distance: float = rng.randf_range(26.0, 48.0)
		var position: Vector3 = point + right * side * distance
		if not _clear_of_track(position, samples, 24.0):
			continue
		position.y = minf(point.y, 2.0) - 0.25
		var yaw: float = atan2(-forward.x, -forward.z) + rng.randf_range(-0.4, 0.4)
		_add_cluster(batch, position, yaw, rng, index)

	var built := batch.build()
	if built != null:
		var mesh := MeshInstance3D.new()
		mesh.name = "ThemedPerimeter"
		mesh.mesh = built
		mesh.material_override = SceneryKit.vertex_material()
		add_child(mesh)

	for index in 4:
		var frame: Dictionary = track.call("sample", total * (0.11 + float(index) * 0.23))
		var point: Vector3 = frame["position"]
		var right: Vector3 = frame["right"]
		right.y = 0.0
		right = right.normalized()
		var side: float = 1.0 if index % 2 == 0 else -1.0
		var offset: Vector3 = right * side * (32.0 + index * 3.0)
		var position: Vector3 = point + offset
		if not _clear_of_track(position, samples, 25.0):
			continue
		position.y = maxf(point.y, 0.0)
		var outward: Vector3 = offset.normalized()
		_add_landmark(position, index, atan2(outward.x, outward.z))

	_build_weather(Vector3(center.x, 0.0, center.z))
	LandscapeSculptor.add_biome_particles(self, _theme,
		Vector3(center.x, 0.0, center.z), radius_est * 0.85)


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
	var radius_in: float = float(context.get("radius_in", half + 20.0))
	var radius_out: float = float(context.get("radius_out", half + 54.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + _arena_style.hash()
	var batch := PropBatch.new()

	var spacing: float = 18.0
	match _arena_style:
		"skyline":
			spacing = 24.0
		"foundry", "iceberg":
			spacing = 16.0
		"dockyard":
			spacing = 22.0
	var mid_radius: float = (radius_in + radius_out) * 0.5
	var count: int = clampi(int(TAU * mid_radius / spacing), 14, 40)
	for index in count:
		var angle: float = TAU * float(index) / float(count)
		var radius: float = rng.randf_range(radius_in, radius_out)
		var position := Vector3(cos(angle) * radius, _floor_y, sin(angle) * radius)
		_add_cluster(batch, position, -angle + rng.randf_range(-0.25, 0.25), rng, index)

	# Second distant sculpted backdrop ring so no arena sits in an empty void.
	var backdrop_count: int = 18
	for index in backdrop_count:
		var angle: float = TAU * (float(index) + 0.5) / float(backdrop_count)
		var dist: float = radius_out + rng.randf_range(35.0, 95.0)
		var pos := Vector3(cos(angle) * dist, _floor_y, sin(angle) * dist)
		match _arena_style:
			"skyline":
				LandscapeSculptor.add_skyscraper(batch, pos, -angle,
					rng.randf_range(12.0, 22.0), rng.randf_range(12.0, 22.0),
					rng.randf_range(42.0, 88.0), Color("364568"), Color("ffdf8a"), rng)
			"foundry":
				LandscapeSculptor.add_volcanic_peak(batch, pos,
					rng.randf_range(24.0, 44.0), rng.randf_range(32.0, 62.0), rng)
			"iceberg", "glacier":
				LandscapeSculptor.add_alpine_mountain(batch, pos,
					rng.randf_range(24.0, 48.0), rng.randf_range(32.0, 74.0), rng)
			"canyon":
				LandscapeSculptor.add_stratified_mesa(batch, pos,
					rng.randf_range(22.0, 42.0), rng.randf_range(22.0, 48.0), 4, rng)
			_:
				LandscapeSculptor.add_woodland_hill(batch, pos,
					rng.randf_range(28.0, 52.0), rng.randf_range(26.0, 48.0),
					rng.randf_range(18.0, 38.0), rng)

	var built := batch.build()
	if built != null:
		var mesh := MeshInstance3D.new()
		mesh.name = "ThemedPerimeter"
		mesh.mesh = built
		mesh.material_override = SceneryKit.vertex_material()
		add_child(mesh)

	for index in 4:
		var angle: float = TAU * (float(index) + 0.5) / 4.0
		# Small enclosed arenas (plaza, rooftop...): the old radius_in + 10
		# planted the 11 m ferris wheel across the corner barriers. Push the
		# ring out and fly balloons instead of the wide wheel there.
		var radius: float = radius_in + 10.0 if half > 62.0 else radius_in + 24.0
		var position := Vector3(cos(angle) * radius, _floor_y, sin(angle) * radius)
		var landmark_index: int = index if half > 62.0 else index + 1
		_add_landmark(position, landmark_index, angle)
	_build_weather(Vector3(0.0, _floor_y, 0.0))
	LandscapeSculptor.add_biome_particles(self, _arena_style,
		Vector3(0.0, maxf(_floor_y, 0.0), 0.0), half * 1.45)


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
			var tower_w: float = rng.randf_range(8.5, 15.0)
			var tower_d: float = rng.randf_range(8.5, 15.0)
			var tower_h: float = rng.randf_range(34.0, 68.0)
			var tower_col: Color = Color("3f4f78") if index % 2 == 0 else Color("4b5d88")
			var lit: Color = Color("ffdf8a") if index % 3 == 0 else Color("8fd6f2")
			LandscapeSculptor.add_skyscraper(batch, point, yaw, tower_w, tower_d,
				tower_h, tower_col, lit, rng)
		"iceberg":
			batch.add_cylinder(base * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 0.25, 0.0)), rng.randf_range(5.5, 8.5), 0.9, 9,
				Color("dff3fa"))
			if index % 2 == 0:
				LandscapeSculptor.add_alpine_mountain(batch, point + Vector3(0.0, 0.3, 0.0),
					rng.randf_range(4.5, 7.2), rng.randf_range(6.0, 12.0), rng)
			for offset: Vector3 in [Vector3(-2.6, 0.2, 0.8), Vector3(2.4, 0.2, -1.4)]:
				_tree(batch, base * Transform3D(Basis.IDENTITY, offset),
					rng.randf_range(0.95, 1.45), Color("285e58"), Color("574b44"), true)
		"dockyard":
			if _arena_style == "dockyard":
				batch.add_box(base * Transform3D(Basis.IDENTITY,
					Vector3(0.0, 0.35, 0.0)), Vector3(10.5, 0.8, 14.0),
					Color("3d4a55"))
				for level in 2:
					for column in 2:
						var p := Vector3(float(column) * 3.6 - 1.8,
							1.4 + level * 2.55, 0.0)
						batch.add_box(base * Transform3D(Basis.IDENTITY, p),
							Vector3(3.3, 2.45, 6.2),
							[Color("e45a45"), Color("2d9fbd"), Color("e8ad3e"),
								Color("567287")][(index + level + column) % 4])
			else:
				_dockyard_cluster(batch, base, index)
		"foundry":
			if index % 3 == 0:
				LandscapeSculptor.add_volcanic_peak(batch, point,
					rng.randf_range(7.0, 12.0), rng.randf_range(12.0, 24.0), rng)
			else:
				for stack in 2:
					var height: float = 5.5 + float(stack) * 3.5
					batch.add_cylinder(base * Transform3D(Basis.IDENTITY,
						Vector3(float(stack) * 3.2 - 1.6, height * 0.5, 0.0)),
						0.82, height, 10, Color("3f424b"))
					batch.add_cylinder(base * Transform3D(Basis.IDENTITY,
						Vector3(float(stack) * 3.2 - 1.6, height - 0.2, 0.0)),
						1.02, 0.45, 10, Color("ee7441"))
				batch.add_box(base * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.2, 3.0)),
					Vector3(7.6, 0.4, 2.6), Color("f06032"))
		"meadow":
			for offset: Vector3 in [Vector3(-2.6, 0.0, 1.0), Vector3(2.2, 0.0, -1.6)]:
				_tree(batch, base * Transform3D(Basis.IDENTITY, offset),
					rng.randf_range(0.95, 1.45), Color("3d9148"), Color("765036"), false)
			if index % 4 == 0:
				LandscapeSculptor.add_woodland_hill(batch, point + Vector3(0.0, -0.2, 0.0),
					rng.randf_range(7.0, 12.0), rng.randf_range(7.0, 12.0),
					rng.randf_range(3.5, 6.5), rng)
			for flower in 5:
				var p := Vector3(rng.randf_range(-3.2, 3.2), 0.16, rng.randf_range(-3.2, 3.2))
				batch.add_box(base * Transform3D(Basis.IDENTITY, p), Vector3(0.22, 0.34, 0.22),
					Color("ffd55c") if flower % 2 == 0 else Color("f48db5"))
		"canyon":
			if index % 2 == 0:
				LandscapeSculptor.add_canyon_spire(batch, point,
					rng.randf_range(3.2, 5.8), rng.randf_range(7.5, 14.5), rng)
			else:
				LandscapeSculptor.add_stratified_mesa(batch, point,
					rng.randf_range(5.5, 9.0), rng.randf_range(6.0, 11.0), 3, rng)
			if index % 2 == 0:
				_cactus(batch, base * Transform3D(Basis.IDENTITY, Vector3(4.5, 0.0, 0.0)), rng)
			# Tumbled rock pile at the outcrop foot.
			for rubble in 3:
				var rr: float = rng.randf_range(0.7, 1.4)
				batch.add_box(base * Transform3D(Basis(Vector3.UP, rng.randf() * TAU),
					Vector3(-3.4 + float(rubble) * 1.1, rr * 0.35, 2.6 + rng.randf_range(-0.6, 0.6))),
					Vector3(rr * 1.5, rr * 0.9, rr * 1.2),
					Color("8a3c22") if rubble % 2 == 0 else Color("b85a35"))
		"glacier":
			for offset: Vector3 in [Vector3(-2.6, 0.0, 0.2), Vector3(2.4, 0.0, -1.6)]:
				_tree(batch, base * Transform3D(Basis.IDENTITY, offset),
					rng.randf_range(1.0, 1.5), Color("2f7d6e"), Color("5a4638"), true)
			# Wind-sculpted snowdrift wedge + ice shards at the cluster foot.
			batch.add_box(base * Transform3D(Basis(Vector3.UP, 0.35),
				Vector3(0.2, 0.28, 3.4)), Vector3(5.2, 0.55, 1.8), Color("cfeaf8"))
			batch.add_box(base * Transform3D(Basis(Vector3.FORWARD, 0.28),
				Vector3(-2.2, 0.75, 3.1)), Vector3(0.5, 1.5, 0.5), Color("8fd4ec"))
			if index % 3 == 0:
				LandscapeSculptor.add_alpine_mountain(batch, point + Vector3(3.0, 0.0, 2.0),
					rng.randf_range(5.0, 8.0), rng.randf_range(6.0, 11.0), rng)
		_:
			# Grounded woodland cluster + festival pavilion (zero floating crowd strips).
			LandscapeSculptor.add_woodland_hill(batch, point,
				rng.randf_range(6.5, 11.0), rng.randf_range(6.5, 11.0),
				rng.randf_range(2.2, 4.5), rng)
			for offset: Vector3 in [Vector3(-2.6, 0.5, 0.8), Vector3(2.4, 0.5, -1.0)]:
				_tree(batch, base * Transform3D(Basis.IDENTITY, offset),
					rng.randf_range(0.9, 1.3), Color("4da34e"), Color("765036"), false)
			# Berry bushes dotting the verge.
			for bush in 3:
				var bpos := Vector3(rng.randf_range(-4.0, 4.0), 0.35, rng.randf_range(2.0, 4.5))
				batch.add_box(base * Transform3D(Basis(Vector3.UP, rng.randf() * TAU), bpos),
					Vector3(0.9, 0.7, 0.9),
					Color("3f9e46") if bush % 2 == 0 else Color("57b84a"))


func _dockyard_cluster(batch: PropBatch, base: Transform3D, index: int) -> void:
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
	var height: float = rng.randf_range(2.6, 4.6)
	var green := Color("39855c")
	batch.add_cylinder(base * Transform3D(Basis.IDENTITY, Vector3.UP * height * 0.5),
		0.32, height, 8, green)
	for side: float in [-1.0, 1.0]:
		batch.add_cylinder(base * Transform3D(Basis(Vector3.FORWARD, PI * 0.5),
			Vector3(side * 0.65, height * 0.52, 0.0)), 0.22, 1.25, 8, green)
		batch.add_cylinder(base * Transform3D(Basis.IDENTITY,
			Vector3(side * 1.2, height * 0.72, 0.0)), 0.22, 1.35, 8, green)


func _add_landmark(point: Vector3, index: int, yaw: float = 0.0) -> void:
	match _theme:
		"meadow":
			LandscapeSculptor.build_windmill(self, point, yaw, 1.15, "meadow", _anim)
		"canyon":
			LandscapeSculptor.build_windmill(self, point, yaw, 1.05, "canyon", _anim)
		"dockyard":
			if index % 2 == 0:
				LandscapeSculptor.build_port_crane(self, point, yaw, 14.0, Color("f0b73e"), _anim)
			else:
				LandscapeSculptor.build_cargo_ship(self, point + Vector3(0.0, -0.5, 0.0), yaw, 0.78, _anim)
		"foundry":
			LandscapeSculptor.build_port_crane(self, point, yaw, 13.0, Color("e36642"), _anim)
		"glacier":
			var end_pt: Vector3 = point + Vector3(cos(yaw), 0.25, sin(yaw)) * 28.0
			LandscapeSculptor.build_ski_lift_system(self, point + Vector3.UP * 8.0,
				end_pt + Vector3.UP * 14.0, 2, 2, _anim)
		_:
			if index == 0:
				LandscapeSculptor.build_ferris_wheel(self, point, yaw, 11.0, _anim)
			else:
				var col_a: Color = Color("ed5d68") if index % 2 == 0 else Color("38d6f0")
				var col_b: Color = Color("ffd22e") if index % 2 == 0 else Color("f26ca7")
				LandscapeSculptor.build_hot_air_balloon(self, point + Vector3.UP * 13.0,
					col_a, col_b, float(index) * 1.4, _anim)


func _build_weather(anchor: Vector3) -> void:
	_weather_anchor = anchor
	var mesh := BoxMesh.new()
	var color := Color.WHITE
	match _theme:
		"glacier":
			mesh.size = Vector3(0.14, 0.14, 0.14)
		"dockyard":
			mesh.size = Vector3(0.04, 1.1, 0.04)
			color = Color("a6d8e8")
		"canyon":
			mesh.size = Vector3(0.16, 0.08, 0.16)
			color = Color("edb276")
		"foundry":
			mesh.size = Vector3(0.11, 0.20, 0.11)
			color = Color("ff9b42")
		"stadium":
			mesh.size = Vector3(0.13, 0.05, 0.24)
			color = Color("ffd45e")
		_:
			mesh.size = Vector3(0.11, 0.06, 0.19)
			color = Color("d8ef87")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12000 + _theme.hash()
	var transforms: Array = []
	for index in 120:
		var seed_value := Vector3(rng.randf_range(-34.0, 34.0), rng.randf_range(0.0, 22.0),
			rng.randf_range(-34.0, 34.0))
		_weather_seeds.append(seed_value)
		transforms.append(Transform3D(Basis.IDENTITY, anchor + seed_value))
	_weather = SceneryKit.multimesh(mesh, _material(color), transforms, "AmbientWeather", false)
	var material := _weather.material_override as StandardMaterial3D
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add_child(_weather)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _process(delta: float) -> void:
	_time += delta
	LandscapeSculptor.step_animations(_anim, _time, delta)
	if _weather == null:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var center: Vector3 = camera.global_position if camera != null else _weather_anchor
	for index in _weather_seeds.size():
		var seed_value: Vector3 = _weather_seeds[index]
		var p := seed_value
		match _theme:
			"glacier":
				p.y = fposmod(seed_value.y - _time * 2.2, 22.0)
				p.x += sin(_time * 0.8 + index) * 1.6
			"dockyard":
				p.y = fposmod(seed_value.y - _time * 14.0, 22.0)
				p.x += _time * 0.8
			"foundry":
				p.y = fposmod(seed_value.y + _time * 2.8, 22.0)
				p.x += sin(_time + index) * 0.8
			"canyon":
				p.x = fposmod(seed_value.x + _time * 3.2 + 34.0, 68.0) - 34.0
				p.y = 1.0 + seed_value.y * 0.4 + sin(_time + index) * 0.6
			_:
				p.y = fposmod(seed_value.y - _time * 0.7, 22.0)
				p.x += sin(_time * 0.45 + index) * 2.2
		var basis := Basis(Vector3.UP, _time * 0.4 + index)
		_weather.multimesh.set_instance_transform(index, Transform3D(basis, center + p))
