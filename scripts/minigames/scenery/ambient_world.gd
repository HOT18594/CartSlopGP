extends Node3D
## Presentation-only themed life around tracks and arenas. Static detail is merged
## into one mesh via LandscapeSculptor + PropBatch; weather is one MultiMesh plus
## optional biome GPU particles; landmarks use smooth animated pivots.

const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const LandscapeSculptor := preload("res://scripts/minigames/scenery/landscape_sculptor.gd")
const ConceptSpectacle := preload("res://scripts/minigames/scenery/concept_spectacle.gd")

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
	# Note: Glacier Pass builds its own bespoke cliffside massifs & Matterhorn
	# cathedral ranges in GlacierTerrain with strict multi-point road clearance.
	var ring_count: int = 0 if _theme == "glacier" else (14 if _theme == "dockyard" else 22)
	for i in ring_count:
		var ang: float = TAU * float(i) / float(ring_count) + rng.randf_range(-0.08, 0.08)
		var dist: float = radius_est + rng.randf_range(65.0 if _theme == "dockyard" else 55.0, 155.0)
		var pos := Vector3(center.x + cos(ang) * dist, -1.0, center.z + sin(ang) * dist)
		var foot: float = 92.0
		match _theme:
			"glacier":
				foot = 56.0 * 1.55 + 16.0
			"canyon":
				foot = 48.0 + 18.0
			"dockyard":
				foot = 46.0 + 18.0
			"stadium":
				foot = 56.0 * 1.2 + 16.0
		if not _clear_of_track(pos, samples, foot):
			continue
		match _theme:
			"glacier":
				if i % 3 == 0:
					LandscapeSculptor.add_twin_cathedral_peaks(batch, pos,
						rng.randf_range(34.0, 52.0), rng.randf_range(54.0, 96.0), rng)
				else:
					LandscapeSculptor.add_alpine_mountain(batch, pos,
						rng.randf_range(28.0, 54.0), rng.randf_range(38.0, 86.0), rng)
			"canyon":
				if i % 4 == 0:
					LandscapeSculptor.add_canyon_arch_butte(batch, pos,
						rng.randf_range(26.0, 38.0), rng.randf_range(30.0, 54.0), rng)
				elif i % 3 == 0:
					LandscapeSculptor.add_canyon_spire(batch, pos,
						rng.randf_range(8.0, 15.0), rng.randf_range(24.0, 44.0), rng)
				else:
					LandscapeSculptor.add_stratified_mesa(batch, pos,
						rng.randf_range(22.0, 42.0), rng.randf_range(24.0, 52.0), 4, rng)
			"dockyard":
				LandscapeSculptor.add_coastal_sea_stacks(batch, pos,
					rng.randf_range(22.0, 38.0), rng.randf_range(18.0, 42.0), rng)
			"stadium":
				if i % 4 == 0:
					LandscapeSculptor.add_twin_cathedral_peaks(batch, pos,
						rng.randf_range(32.0, 46.0), rng.randf_range(34.0, 58.0), rng, {
							"base": Color("478440"),
							"rock": Color("5b9c49"),
							"cliff": Color("74b857"),
							"snow_lo": Color("9ad470"),
							"snow_hi": Color("c2e89c"),
						})
				else:
					LandscapeSculptor.add_woodland_hill(batch, pos,
						rng.randf_range(30.0, 56.0), rng.randf_range(26.0, 50.0),
						rng.randf_range(16.0, 34.0), rng, {
							"skirt": Color("559c3e"),
							"mid": Color("67b54a"),
							"top": Color("7bc759"),
						})
			_:
				if i % 4 == 0:
					LandscapeSculptor.add_twin_cathedral_peaks(batch, pos,
						rng.randf_range(34.0, 48.0), rng.randf_range(38.0, 64.0), rng, {
							"base": Color("3d7344"),
							"rock": Color("4f8a52"),
							"cliff": Color("68a363"),
							"snow_lo": Color("b8ccd4"),
							"snow_hi": Color("eaf4f7"),
						})
				else:
					LandscapeSculptor.add_woodland_hill(batch, pos,
						rng.randf_range(32.0, 62.0), rng.randf_range(28.0, 54.0),
						rng.randf_range(22.0, 48.0), rng)

	# Mid-field clusters well clear of the widened lane.
	var cluster_count: int = 0 if (_theme == "dockyard" or _theme == "glacier") else 42
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

	# Tier-3 Low-Effort Far-Field Horizon Silhouette Ring for racing maps too!
	# Centered on the track's true center and checked against all road samples.
	if _theme != "glacier":
		_build_far_horizon_ring(radius_est + 120.0, rng, Vector3(center.x, _floor_y, center.z), samples)

	for index in (0 if _theme == "glacier" else 6):
		var frame: Dictionary = track.call("sample", total * (0.08 + float(index) * 0.165))
		var point: Vector3 = frame["position"]
		var right: Vector3 = frame["right"]
		right.y = 0.0
		right = right.normalized()
		var side: float = 1.0 if index % 2 == 0 else -1.0
		var offset: Vector3 = right * side * (32.0 + float(index % 3) * 4.5)
		var position: Vector3 = point + offset
		if not _clear_of_track(position, samples, 25.0):
			continue
		position.y = maxf(point.y, 0.0)
		var outward: Vector3 = offset.normalized()
		_add_landmark(position, index, atan2(outward.x, outward.z))

	# Signature orbiting SlopMart Grand Prix Blimp cruising overhead.
	LandscapeSculptor.build_slop_blimp(self, Vector3(center.x, 0.0, center.z),
		clampf(radius_est * 0.72, 68.0, 130.0), 46.0, _anim, 0.35)

	# Concept-Art 3D Spectacle Pass per Racing Theme!
	match _theme:
		"glacier":
			ConceptSpectacle.build_northern_lights(self, Vector3(center.x, 0.0, center.z),
				maxf(radius_est * 1.45, 220.0), 68.0)
			ConceptSpectacle.build_track_lanterns(self, track, 32.0, 12.6,
				Color("ffb538"), Color("5e3e29"))
			ConceptSpectacle.build_glacier_crystals(self, track, 22)
			ConceptSpectacle.build_track_chevrons(self, track, 16, Color("ffe266"))
		"canyon":
			# 3 monumental sandstone sky-arches spanning right over the canyon highway!
			var arch_batch := PropBatch.new()
			for frac: float in [0.16, 0.52, 0.80]:
				var af: Dictionary = track.call("sample", total * frac)
				var ap: Vector3 = af["position"] as Vector3
				var afw: Vector3 = af["forward"] as Vector3
				afw.y = 0.0
				if afw.length_squared() > 0.001:
					afw = afw.normalized()
					LandscapeSculptor.add_natural_arch(arch_batch, null, ap,
						atan2(-afw.x, -afw.z), 25.0, 15.0, 5.2,
						Color("b34625"), Color("e38042"))
			arch_batch.flush_to(self, "CanyonSkyArches", false, SceneryKit.vertex_material())
			ConceptSpectacle.build_pennant_garlands(self, track, [0.08, 0.34, 0.66, 0.90], 24.5, 11.2)
			ConceptSpectacle.build_track_lanterns(self, track, 44.0, 13.0,
				Color("ff9e38"), Color("6e3b24"))
			ConceptSpectacle.build_track_chevrons(self, track, 14, Color("fff0a8"))
		"stadium":
			ConceptSpectacle.build_checkered_arches(self, track, [0.12, 0.44, 0.76], 23.5, 13.5, Color("38d6f0"))
			ConceptSpectacle.build_pennant_garlands(self, track, [0.26, 0.58, 0.88], 24.0, 11.5)
		"dockyard":
			ConceptSpectacle.build_checkered_arches(self, track, [0.18, 0.62], 23.5, 13.5, Color("ffd22e"))
			ConceptSpectacle.build_track_lanterns(self, track, 42.0, 13.0,
				Color("ffd052"), Color("334154"))
		_:
			ConceptSpectacle.build_checkered_arches(self, track, [0.15, 0.55], 23.5, 13.5, Color("ffd22e"))
			ConceptSpectacle.build_pennant_garlands(self, track, [0.30, 0.72, 0.90], 24.0, 11.5)
			ConceptSpectacle.build_track_lanterns(self, track, 40.0, 12.8,
				Color("ffbf47"), Color("5a3b26"))

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
	var backdrop_count: int = 20
	for index in backdrop_count:
		var angle: float = TAU * (float(index) + 0.5) / float(backdrop_count)
		var dist: float = radius_out + rng.randf_range(38.0, 102.0)
		var pos := Vector3(cos(angle) * dist, _floor_y, sin(angle) * dist)
		match _arena_style:
			"skyline":
				LandscapeSculptor.add_skyscraper(batch, pos, -angle,
					rng.randf_range(12.0, 22.0), rng.randf_range(12.0, 22.0),
					rng.randf_range(44.0, 94.0), Color("364568"), Color("ffdf8a"), rng)
			"foundry":
				LandscapeSculptor.add_volcanic_peak(batch, pos,
					rng.randf_range(24.0, 46.0), rng.randf_range(34.0, 68.0), rng)
			"iceberg", "glacier":
				if index % 3 == 0:
					LandscapeSculptor.add_twin_cathedral_peaks(batch, pos,
						rng.randf_range(28.0, 44.0), rng.randf_range(44.0, 82.0), rng)
				else:
					LandscapeSculptor.add_alpine_mountain(batch, pos,
						rng.randf_range(24.0, 48.0), rng.randf_range(32.0, 74.0), rng)
			"canyon":
				if index % 4 == 0:
					LandscapeSculptor.add_canyon_arch_butte(batch, pos,
						rng.randf_range(24.0, 36.0), rng.randf_range(26.0, 48.0), rng)
				else:
					LandscapeSculptor.add_stratified_mesa(batch, pos,
						rng.randf_range(22.0, 42.0), rng.randf_range(22.0, 48.0), 4, rng)
			"dockyard":
				LandscapeSculptor.add_coastal_sea_stacks(batch, pos,
					rng.randf_range(20.0, 34.0), rng.randf_range(18.0, 38.0), rng)
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

	# Tier-3 Low-Effort Far-Field Horizon Silhouette Ring (220..340 m out):
	# Gives every non-racing arena a massive living world vista at almost zero GPU cost.
	_build_far_horizon_ring(radius_out, rng)

	for index in 4:
		var angle: float = TAU * (float(index) + 0.5) / 4.0
		var radius: float = radius_in + 10.0 if half > 62.0 else radius_in + 24.0
		var position := Vector3(cos(angle) * radius, _floor_y, sin(angle) * radius)
		var landmark_index: int = index if half > 62.0 else index + 1
		_add_landmark(position, landmark_index, angle)
	# Sweeping arena festival spotlights & overhead SlopMart blimp for lively atmosphere.
	if _arena_style in ["skyline", "stadium", "foundry"]:
		for si in 4:
			var sa: float = TAU * float(si) / 4.0 + 0.25
			var s_pos := Vector3(cos(sa) * (radius_in + 14.0), _floor_y, sin(sa) * (radius_in + 14.0))
			var beam_col: Color = Color("ff8038") if _arena_style == "foundry" else (Color("38d6f0") if si % 2 == 0 else Color("ffd22e"))
			LandscapeSculptor.build_sky_spotlight(self, s_pos, beam_col, float(si) * 1.3, _anim)
	LandscapeSculptor.build_slop_blimp(self, Vector3(0.0, 0.0, 0.0),
		maxf(radius_out * 1.18, 108.0), _floor_y + 56.0, _anim, 2.2)
	_build_weather(Vector3(0.0, _floor_y, 0.0))
	LandscapeSculptor.add_biome_particles(self, _arena_style,
		Vector3(0.0, maxf(_floor_y, 0.0), 0.0), half * 1.45)


func _build_far_horizon_ring(inner_r: float, rng: RandomNumberGenerator,
		ring_center: Vector3 = Vector3.ZERO,
		track_samples: PackedVector3Array = PackedVector3Array()) -> void:
	## Ultra-low-poly distant atmospheric mountain / skyline / island silhouette
	## ring (one cheap single-mesh batch) so every map feels embedded in a huge
	## cohesive world without costing frame rate or cluttering the arena.
	var style: String = _arena_style if _arena_style != "" else _theme
	var far := PropBatch.new()
	var count: int = 24
	var base_r: float = maxf(inner_r + 125.0, 210.0)
	for i in count:
		var ang: float = TAU * float(i) / float(count) + rng.randf_range(-0.04, 0.04)
		var dist: float = base_r + rng.randf_range(0.0, 75.0)
		var pos := Vector3(ring_center.x + cos(ang) * dist, _floor_y - 2.0, ring_center.z + sin(ang) * dist)
		if not track_samples.is_empty() and not _clear_of_track(pos, track_samples, 96.0):
			continue
		match style:
			"skyline":
				var h: float = rng.randf_range(44.0, 108.0)
				var w: float = rng.randf_range(16.0, 30.0)
				far.add_box(Transform3D(Basis(Vector3.UP, -ang),
					pos + Vector3(0.0, h * 0.5, 0.0)), Vector3(w, h, w),
					Color("24264a").lightened(float(i % 3) * 0.04))
			"foundry":
				var h: float = rng.randf_range(38.0, 82.0)
				var r: float = rng.randf_range(26.0, 48.0)
				far.add_cone(Transform3D(Basis(Vector3.UP, ang),
					pos + Vector3(0.0, h * 0.5, 0.0)), r, h, 5,
					Color("3b2220").lightened(float(i % 3) * 0.04))
			"glacier", "iceberg", "snowfield":
				var h: float = rng.randf_range(48.0, 96.0)
				var r: float = rng.randf_range(30.0, 56.0)
				far.add_cone(Transform3D(Basis(Vector3.UP, ang),
					pos + Vector3(0.0, h * 0.5, 0.0)), r, h, 5,
					Color("315285").lightened(float(i % 3) * 0.06))
			"canyon", "bt_labyrinth":
				var h: float = rng.randf_range(36.0, 74.0)
				var w: float = rng.randf_range(28.0, 52.0)
				far.add_box(Transform3D(Basis(Vector3.UP, ang),
					pos + Vector3(0.0, h * 0.5, 0.0)), Vector3(w, h, w * 0.72),
					Color("7c3b36").lightened(float(i % 3) * 0.05))
			"dockyard", "harbour", "bt_ferries":
				var h: float = rng.randf_range(24.0, 54.0)
				var r: float = rng.randf_range(28.0, 54.0)
				far.add_cone(Transform3D(Basis(Vector3.UP, ang),
					pos + Vector3(0.0, h * 0.5, 0.0)), r, h, 6,
					Color("3d6870").lightened(float(i % 3) * 0.05))
			_:
				var h: float = rng.randf_range(28.0, 64.0)
				var r: float = rng.randf_range(34.0, 62.0)
				far.add_cone(Transform3D(Basis(Vector3.UP, ang),
					pos + Vector3(0.0, h * 0.5, 0.0)), r, h, 6,
					Color("4a7c66").lightened(float(i % 3) * 0.05))
	var mesh := far.build()
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.name = "FarHorizonSilhouette"
		mi.mesh = mesh
		mi.material_override = SceneryKit.vertex_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


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
			if index % 2 == 0:
				LandscapeSculptor.build_windmill(self, point, yaw, 1.15, "meadow", _anim)
			else:
				LandscapeSculptor.build_giant_wind_turbine(self, point, yaw, 22.0, _anim)
		"canyon":
			if index % 2 == 0:
				LandscapeSculptor.build_windmill(self, point, yaw, 1.05, "canyon", _anim)
			else:
				LandscapeSculptor.build_giant_wind_turbine(self, point, yaw, 24.0, _anim)
		"dockyard":
			if index % 3 == 0:
				LandscapeSculptor.build_port_crane(self, point, yaw, 14.0, Color("f0b73e"), _anim)
			elif index % 3 == 1:
				LandscapeSculptor.build_cargo_ship(self, point + Vector3(0.0, -0.5, 0.0), yaw, 0.78, _anim)
			else:
				LandscapeSculptor.build_lighthouse(self, point, 18.0, _anim)
		"foundry":
			if index % 2 == 0:
				LandscapeSculptor.build_port_crane(self, point, yaw, 13.0, Color("e36642"), _anim)
			else:
				LandscapeSculptor.build_sky_spotlight(self, point, Color("ff7832"), float(index) * 1.7, _anim)
		"glacier":
			var end_pt: Vector3 = point + Vector3(cos(yaw), 0.25, sin(yaw)) * 28.0
			LandscapeSculptor.build_ski_lift_system(self, point + Vector3.UP * 8.0,
				end_pt + Vector3.UP * 14.0, 2, 2, _anim)
		_:
			if index == 0:
				LandscapeSculptor.build_ferris_wheel(self, point, yaw, 11.0, _anim)
			elif index % 3 == 2:
				LandscapeSculptor.build_sky_spotlight(self, point, Color("38d6f0"), float(index) * 1.2, _anim)
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
