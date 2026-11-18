extends RefCounted
## Scenery builder for REDWOOD VALLEY (`meadow`).
##
## Pure cartoon Kenney GLB batches + vertex-coloured procedural terrain/water
## (zero photoreal PBR textures). Every solid collider sits on
## CollisionLayers.WORLD and stays >= 7.5 m outside KenneyTiles.clearance_path
## (overhead timber gantry beams keep lowest_y >= 4.4 m).

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const KenneyTiles := preload("res://scripts/minigames/tiles/kenney_tiles.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")

const TILE: float = TileKit.TILE_SIZE
const SOLID_MIN_CLEARANCE: float = 16.5
const TREE_MIN_CLEARANCE: float = 17.5
const FLOWER_MIN_CLEARANCE: float = 12.2
const SEED: int = 20260801

const REDWOOD_SPECIES: Array[Dictionary] = [
	{"model": "tree_tall", "h_min": 18.0, "h_max": 31.0, "w": 5},
	{"model": "tree_tall_dark", "h_min": 19.0, "h_max": 33.0, "w": 4},
	{"model": "tree_pineTallA", "h_min": 14.0, "h_max": 25.0, "w": 4},
	{"model": "tree_pineTallB", "h_min": 15.0, "h_max": 26.0, "w": 4},
	{"model": "tree_oak", "h_min": 10.0, "h_max": 17.0, "w": 3},
	{"model": "tree_oak_fall", "h_min": 10.0, "h_max": 17.0, "w": 3},
	{"model": "tree_tall_fall", "h_min": 15.0, "h_max": 24.0, "w": 2},
	{"model": "tree_default_fall", "h_min": 9.0, "h_max": 15.0, "w": 2},
]

const FLORA_SPECIES: Array[Dictionary] = [
	{"model": "flower_redA", "h_min": 0.45, "h_max": 0.85, "w": 3},
	{"model": "flower_yellowA", "h_min": 0.45, "h_max": 0.85, "w": 3},
	{"model": "flower_purpleA", "h_min": 0.45, "h_max": 0.85, "w": 3},
	{"model": "grass_large", "h_min": 0.50, "h_max": 1.05, "w": 4},
	{"model": "plant_bushLarge", "h_min": 0.95, "h_max": 1.90, "w": 3},
]


static func build(holder: Node3D, spline: RefCounted) -> Dictionary:
	var stats: Dictionary = {
		"objects": 0,
		"draws": 0,
		"barriers": 0,
		"trees": 0,
		"flora": 0,
		"props": 0,
		"cliffs": 0,
	}
	if holder == null or spline == null:
		return stats

	var total: float = maxf(float(spline.total_length), 1.0)
	var seam: float = TileKit._snap_distance(spline, total * 0.5)
	for side: float in [-1.0, 1.0]:
		stats["barriers"] = int(stats["barriers"]) \
			+ TileKit.barrier_line(holder, spline, 0.0, seam, side, "barrierWhite") \
			+ TileKit.barrier_line(holder, spline, seam, 0.0, side, "barrierRed")

	var lake_centre := Vector3(144.0, 0.0, 116.0)
	var south_basin := Vector3(120.0, 0.0, 268.0)
	_build_ground_and_water(holder, spline, lake_centre, south_basin, stats)
	_build_timber_gantry(holder, spline, stats)
	_build_valley_camps_and_logs(holder, spline, lake_centre, stats)
	_build_valley_bluffs(holder, spline, stats)
	_build_redwood_forest(holder, spline, lake_centre, south_basin, stats)

	stats["objects"] = int(stats["barriers"]) + int(stats["trees"]) \
		+ int(stats["flora"]) + int(stats["props"]) + int(stats["cliffs"]) + 3
	stats["draws"] = _count_draws(holder)
	return stats


static func _build_ground_and_water(holder: Node3D, spline: RefCounted,
		lake_centre: Vector3, south_basin: Vector3, stats: Dictionary) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var grass_deep := Color("5d9f41")
	var grass_meadow := Color("72b54f")
	var sand_bank := Color("dfd0a3")
	var water_shallow := Color("38cde0")
	var water_deep := Color("1ba3bf")
	var foam := Color("e6fbff")
	var berm_earth := Color("7f6647")
	var cliff_rock := Color("6f6961")
	var trail_dirt := Color("9a7046")
	var trail_edge := Color("825b36")

	var gy: float = TileKit.Z_GROUND
	_quad(verts, normals, colors,
		Vector3(-640.0, gy, -640.0), Vector3(920.0, gy, -640.0),
		Vector3(920.0, gy, 940.0), Vector3(-640.0, gy, 940.0), grass_deep)
	_quad(verts, normals, colors,
		Vector3(-40.0, gy + 0.005, -40.0), Vector3(340.0, gy + 0.005, -40.0),
		Vector3(340.0, gy + 0.005, 320.0), Vector3(-40.0, gy + 0.005, 320.0),
		grass_meadow)

	# Central infield turquoise lake (>45 m clear of every road strand)
	_disc(verts, normals, colors, lake_centre + Vector3.UP * (gy + 0.010),
		29.0, 31.0, 28, sand_bank)
	_disc(verts, normals, colors, lake_centre + Vector3.UP * (gy + 0.016),
		24.5, 26.5, 28, water_shallow)
	_disc(verts, normals, colors, lake_centre + Vector3.UP * (gy + 0.020),
		18.0, 19.5, 24, water_deep)
	_ring(verts, normals, colors, lake_centre + Vector3.UP * (gy + 0.023),
		21.0, 22.2, 22.8, 24.2, 24, foam)

	# Southern river pool beyond the 4.5 m river bridge viaduct
	_disc(verts, normals, colors, south_basin + Vector3.UP * (gy + 0.010),
		40.0, 28.0, 28, sand_bank)
	_disc(verts, normals, colors, south_basin + Vector3.UP * (gy + 0.016),
		34.5, 23.5, 28, water_shallow)
	_disc(verts, normals, colors, south_basin + Vector3.UP * (gy + 0.020),
		26.0, 17.0, 24, water_deep)

	# River channel flowing from central lake right beneath (7, 13) 'C' (x=120, z=216)
	var river_pts: Array[Vector3] = [
		Vector3(144.0, 0.0, 136.0),
		Vector3(134.0, 0.0, 168.0),
		Vector3(124.0, 0.0, 196.0),
		Vector3(120.0, 0.0, 218.0),
		Vector3(120.0, 0.0, 256.0),
	]
	_ribbon(verts, normals, colors, river_pts, 14.5, gy + 0.011, sand_bank)
	_ribbon(verts, normals, colors, river_pts, 10.8, gy + 0.017, water_shallow)
	_ribbon(verts, normals, colors, river_pts, 7.2, gy + 0.021, water_deep)
	_ribbon(verts, normals, colors, river_pts, 1.3, gy + 0.024, foam)

	# Mountain cliff shelves & bridge abutments under the 9.0 m overlook and 4.5 m bridge,
	# leaving the central river channel open beneath the viaduct!
	var total: float = maxf(float(spline.total_length), 1.0)
	var steps: int = 128
	for i in steps:
		var s0: float = total * float(i) / float(steps)
		var s1: float = total * float(i + 1) / float(steps)
		var f0: Dictionary = spline.sample(s0)
		var f1: Dictionary = spline.sample(s1)
		var p0: Vector3 = f0["position"]
		var p1: Vector3 = f1["position"]
		if maxf(p0.y, p1.y) < 0.15:
			continue
		if p0.x > 96.0 and p0.x < 144.0 and p0.z > 192.0:
			continue
		var r0: Vector3 = f0["right"]
		var r1: Vector3 = f1["right"]
		for side: float in [-1.0, 1.0]:
			var reach: float = 22.0 if maxf(p0.y, p1.y) > 5.0 else 16.5
			var in0: Vector3 = p0 + r0 * (8.5 * side)
			var in1: Vector3 = p1 + r1 * (8.5 * side)
			var out0: Vector3 = p0 + r0 * (reach * side)
			var out1: Vector3 = p1 + r1 * (reach * side)
			in0.y = p0.y - 0.02
			in1.y = p1.y - 0.02
			out0.y = p0.y * 0.42 if side < 0.0 and p0.y > 5.0 else gy
			out1.y = p1.y * 0.42 if side < 0.0 and p1.y > 5.0 else gy
			_quad(verts, normals, colors, in0, in1, out1, out0,
				cliff_rock if maxf(p0.y, p1.y) > 5.0 else berm_earth)
			if out0.y > gy + 0.05 or out1.y > gy + 0.05:
				_quad(verts, normals, colors, out0, out1,
					Vector3(out1.x, gy, out1.z),
					Vector3(out0.x, gy, out0.z), cliff_rock.darkened(0.14))

	# Woodland "dirt" trail sector overlay (frac 0.72..0.93, skipping B/J tiles)
	var dirt_from: float = total * 0.72
	var dirt_to: float = total * 0.93
	var dirt_steps: int = 56
	var surf_y: float = KenneyTiles.ROAD_SURFACE + 0.012
	var half_lane: float = TileKit.ROAD_HALF - 0.45
	for i in dirt_steps:
		var s0: float = lerpf(dirt_from, dirt_to, float(i) / float(dirt_steps))
		var s1: float = lerpf(dirt_from, dirt_to, float(i + 1) / float(dirt_steps))
		if _is_special_tile(spline, s0) or _is_special_tile(spline, s1):
			continue
		var f0: Dictionary = spline.sample(s0)
		var f1: Dictionary = spline.sample(s1)
		var c0: Vector3 = (f0["position"] as Vector3) + Vector3.UP * surf_y
		var c1: Vector3 = (f1["position"] as Vector3) + Vector3.UP * surf_y
		var r0: Vector3 = f0["right"]
		var r1: Vector3 = f1["right"]
		_quad(verts, normals, colors,
			c0 - r0 * half_lane, c0 + r0 * half_lane,
			c1 + r1 * half_lane, c1 - r1 * half_lane,
			trail_dirt if i % 2 == 0 else trail_edge)

	_emit_vertex_mesh(holder, "RedwoodTerrainWater", verts, normals, colors)
	stats["draws"] = int(stats["draws"]) + 1


static func _is_special_tile(spline: RefCounted, s: float) -> bool:
	if not spline.has_method("tile_at"):
		return false
	var t: Variant = spline.call("tile_at", s)
	if not (t is Dictionary):
		return false
	var k: String = str((t as Dictionary).get("tile", ""))
	return k == "B" or k == "J"


static func _build_timber_gantry(holder: Node3D, spline: RefCounted,
		stats: Dictionary) -> void:
	TileKit.gantry(holder, spline, 0.0)
	var frame: Dictionary = spline.sample(120.0)
	var origin: Vector3 = frame["position"]
	var right: Vector3 = frame["right"]
	var forward: Vector3 = frame["forward"]
	var yaw: float = atan2(-forward.x, -forward.z)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var cedar := Color("7c4d2b")
	var pine_beam := Color("a56c3d")
	var banner_gold := Color("f4c430")
	var banner_green := Color("3f8f45")

	var body := _world_body(holder, "TimberGantry")
	for side: float in [-1.0, 1.0]:
		var post_pos: Vector3 = origin + right * (side * 16.6)
		var xform := Transform3D(Basis(Vector3.UP, yaw),
			post_pos + Vector3.UP * 2.7)
		_box_verts(verts, normals, colors, xform, Vector3(1.1, 5.4, 1.1), cedar)
		_add_box_collider(body, xform, Vector3(1.1, 5.4, 1.1))

	# Overhead timber truss + valley banner (lowest_y = 4.48 m >= 4.4 m > 3.2 m!)
	var beam_xf := Transform3D(Basis(Vector3.UP, yaw), origin + Vector3.UP * 4.98)
	_box_verts(verts, normals, colors, beam_xf, Vector3(34.8, 0.96, 1.08), pine_beam)
	_box_verts(verts, normals, colors,
		Transform3D(Basis(Vector3.UP, yaw), origin + Vector3.UP * 5.68),
		Vector3(15.6, 0.74, 0.44), banner_green)
	_box_verts(verts, normals, colors,
		Transform3D(Basis(Vector3.UP, yaw), origin + Vector3.UP * 5.68),
		Vector3(14.6, 0.46, 0.50), banner_gold)
	_add_box_collider(body, beam_xf, Vector3(34.8, 0.96, 1.08))
	_emit_vertex_mesh(holder, "TimberGantryMesh", verts, normals, colors)


static func _build_valley_camps_and_logs(holder: Node3D, spline: RefCounted,
		lake_centre: Vector3, stats: Dictionary) -> void:
	stats["props"] = int(stats["props"]) \
		+ TileKit.grandstand(holder, spline, 24.0, -1.0, true) \
		+ TileKit.grandstand(holder, spline, 64.0, -1.0, false)

	var body := _world_body(holder, "ValleyCampProps")
	var racing_batches: Dictionary = {}
	var nature_batches: Dictionary = {}
	var total: float = maxf(float(spline.total_length), 1.0)

	# Camp tents at scenic clearings well outside the barrier ring (>= 18.5 m)
	var camp_fractions: Array[float] = [0.09, 0.14, 0.74, 0.78, 0.92, 0.96]
	var tent_models: Array[String] = ["tent", "tentRoof", "tentClosed"]
	for i in camp_fractions.size():
		var s: float = total * camp_fractions[i]
		var f: Dictionary = spline.sample(s)
		var pos: Vector3 = (f["position"] as Vector3) - (f["right"] as Vector3) * 20.5
		if (f["position"] as Vector3).y > 0.25:
			continue
		pos.y = 0.0
		if TileKit.spline_distance(spline, pos) < 18.5:
			continue
		var model: String = tent_models[i % tent_models.size()]
		if not bool(TileCatalog.model_info(model, false).get("ok", false)):
			continue
		var yaw: float = atan2((f["right"] as Vector3).x, (f["right"] as Vector3).z)
		var xf: Transform3D = TileKit._fit_transform(model, pos, yaw,
			Vector3.ONE * TileKit.PROP_SCALE, false)
		_push_batch(racing_batches, model, xf)
		var sz: Vector3 = TileKit._scaled_size(model, Vector3.ONE * TileKit.PROP_SCALE, false)
		if _box_clears_spline(spline, pos + Vector3.UP * (sz.y * 0.5), yaw, sz, SOLID_MIN_CLEARANCE):
			_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw),
				pos + Vector3.UP * (sz.y * 0.5)), sz)
		stats["props"] = int(stats["props"]) + 1

	# Log stacks & wooden post-and-rail fences along woodland verges (>= 16.5 m)
	var log_models: Array[String] = ["log_stack", "log_large", "fence_simple"]
	var steps: int = 36
	for i in steps:
		var s: float = total * (float(i) + 0.35) / float(steps)
		var f: Dictionary = spline.sample(s)
		var p_road: Vector3 = f["position"]
		if p_road.y > 0.25:
			continue
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var pos: Vector3 = p_road + (f["right"] as Vector3) * (18.2 * side)
		pos.y = 0.0
		if TileKit.spline_distance(spline, pos) < SOLID_MIN_CLEARANCE + 1.5:
			continue
		if Vector2(pos.x - lake_centre.x, pos.z - lake_centre.z).length() < 34.0:
			continue
		var model: String = log_models[i % log_models.size()]
		if not bool(TileCatalog.model_info(model, true).get("ok", false)):
			continue
		var yaw: float = spline.yaw_at(s) + (PI * 0.5 if model == "fence_simple" else 0.25)
		var sc: float = TileKit.NATURE_SCALE * 0.52
		var sz: Vector3 = TileKit._scaled_size(model, Vector3.ONE * sc, true)
		if not _box_clears_spline(spline, pos + Vector3.UP * (sz.y * 0.5), yaw, sz, SOLID_MIN_CLEARANCE):
			continue
		var xf: Transform3D = TileKit._fit_transform(model, pos, yaw,
			Vector3.ONE * sc, true)
		_push_batch(nature_batches, model, xf)
		_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw),
			pos + Vector3.UP * (sz.y * 0.5)), sz)
		stats["props"] = int(stats["props"]) + 1

	# Checkered & green woodland flags: snap to 16 m cell centre FIRST so
	# TileKit.flags never snaps a corner offset back onto the road!
	var flag_spots: Array = []
	var used_flag_cells: Dictionary = {}
	for frac: float in [0.03, 0.11, 0.32, 0.56, 0.76, 0.94]:
		var s: float = total * frac
		var f: Dictionary = spline.sample(s)
		var raw_pos: Vector3 = (f["position"] as Vector3) - (f["right"] as Vector3) * 18.0
		var snapped: Vector3 = TileKit._snap_point(raw_pos)
		snapped.y = (f["position"] as Vector3).y if (f["position"] as Vector3).y > 0.5 else 0.0
		var cell_key := Vector2i(int(round(snapped.x)), int(round(snapped.z)))
		if used_flag_cells.has(cell_key):
			continue
		if TileKit.spline_distance(spline, snapped) >= SOLID_MIN_CLEARANCE + 1.0:
			used_flag_cells[cell_key] = true
			flag_spots.append({
				"position": snapped,
				"kind": "flagGreen" if int(frac * 100.0) % 2 == 0 else "flagCheckers",
				"yaw": spline.yaw_at(s),
			})
	stats["props"] = int(stats["props"]) + TileKit.flags(holder, flag_spots)

	for model: String in racing_batches:
		TileKit._batch_model(holder, model, racing_batches[model] as Array,
			"Camp_" + model, true, false)
	for model: String in nature_batches:
		TileKit._batch_model(holder, model, nature_batches[model] as Array,
			"Wood_" + model, false, true)
	if body.get_child_count() == 0:
		body.free()


static func _build_valley_bluffs(holder: Node3D, spline: RefCounted,
		stats: Dictionary) -> void:
	var body := _world_body(holder, "ValleyBluffs")
	var batches: Dictionary = {}
	var models: Array[String] = ["cliff_block_rock", "rock_largeA", "rock_tallA"]
	var ring_centre := Vector3(144.0, 0.0, 120.0)
	var count: int = 40
	for i in count:
		var ang: float = TAU * float(i) / float(count)
		var rad_x: float = 156.0 + 14.0 * sin(float(i) * 1.9)
		var rad_z: float = 132.0 + 12.0 * cos(float(i) * 2.3)
		var pos := Vector3(ring_centre.x + cos(ang) * rad_x, 0.0,
			ring_centre.z + sin(ang) * rad_z)
		if pos.x > 85.0 and pos.x < 155.0 and pos.z > 210.0:
			continue
		if TileKit.spline_distance(spline, pos) < 24.0:
			continue
		var model: String = models[i % models.size()]
		if not bool(TileCatalog.model_info(model, true).get("ok", false)):
			continue
		var sc: float = TileKit.NATURE_SCALE * (0.85 + 0.30 * float(i % 4))
		var yaw: float = ang + PI * 0.5
		var sz: Vector3 = TileKit._scaled_size(model, Vector3.ONE * sc, true)
		if not _box_clears_spline(spline, pos + Vector3.UP * (sz.y * 0.5), yaw, sz * 0.85, SOLID_MIN_CLEARANCE):
			continue
		var xf: Transform3D = TileKit._fit_transform(model, pos, yaw,
			Vector3.ONE * sc, true)
		_push_batch(batches, model, xf)
		_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw),
			pos + Vector3.UP * (sz.y * 0.5)), sz * 0.85)
		stats["cliffs"] = int(stats["cliffs"]) + 1

	for model: String in batches:
		TileKit._batch_model(holder, model, batches[model] as Array,
			"Bluff_" + model, false, true)
	if body.get_child_count() == 0:
		body.free()


static func _build_redwood_forest(holder: Node3D, spline: RefCounted,
		lake_centre: Vector3, south_basin: Vector3, stats: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var tree_batches: Dictionary = {}
	var flora_batches: Dictionary = {}
	var total: float = maxf(float(spline.total_length), 1.0)

	var laterals: Array[float] = [19.0, 25.0, 32.0, 40.0, 49.0, 60.0]
	var steps: int = 92
	for lat: float in laterals:
		for step in steps:
			for side: float in [-1.0, 1.0]:
				if rng.randf() > (0.58 if side < 0.0 else 0.34):
					continue
				var s: float = fposmod(float(step) / float(steps) * total
					+ rng.randf_range(-2.5, 2.5), total)
				var f: Dictionary = spline.sample(s)
				var pos: Vector3 = (f["position"] as Vector3) \
					+ (f["right"] as Vector3) * (lat * side) \
					+ Vector3(rng.randf_range(-2.4, 2.4), 0.0,
						rng.randf_range(-2.4, 2.4))
				pos.y = 0.0
				if TileKit.spline_distance(spline, pos) < TREE_MIN_CLEARANCE:
					continue
				if Vector2(pos.x - lake_centre.x, pos.z - lake_centre.z).length() < 33.0:
					continue
				if Vector2(pos.x - south_basin.x, pos.z - south_basin.z).length() < 42.0:
					continue
				if pos.x > 98.0 and pos.x < 156.0 and pos.z > 130.0 and pos.z < 268.0:
					continue
				if pos.x > 36.0 and pos.x < 120.0 and pos.z > -8.0 and pos.z < 14.0:
					continue
				var spec: Dictionary = _pick_weighted(rng, REDWOOD_SPECIES)
				var model: String = str(spec["model"])
				var info: Dictionary = TileCatalog.model_info(model, true)
				if not bool(info.get("ok", false)):
					model = "tree_pineTallA"
					info = TileCatalog.model_info(model, true)
					if not bool(info.get("ok", false)):
						continue
				var h_base: float = maxf((info["aabb"] as AABB).size.y, 0.01)
				var target_h: float = rng.randf_range(float(spec["h_min"]),
					float(spec["h_max"]))
				var sc: float = target_h / h_base
				var xf: Transform3D = TileKit._fit_transform(model, pos,
					rng.randf() * TAU, Vector3(sc * 0.95, sc, sc * 0.95), true)
				_push_batch(tree_batches, model, xf)
				stats["trees"] = int(stats["trees"]) + 1

	var flora_steps: int = 120
	for step in flora_steps:
		for side: float in [-1.0, 1.0]:
			if rng.randf() > 0.65:
				continue
			var s: float = total * float(step) / float(flora_steps)
			var f: Dictionary = spline.sample(s)
			var road_p: Vector3 = f["position"]
			if road_p.y > 0.25:
				continue
			var lat: float = rng.randf_range(12.6, 17.5)
			var pos: Vector3 = road_p + (f["right"] as Vector3) * (lat * side)
			pos.y = 0.0
			if TileKit.spline_distance(spline, pos) < FLOWER_MIN_CLEARANCE:
				continue
			if Vector2(pos.x - lake_centre.x, pos.z - lake_centre.z).length() < 28.0:
				continue
			var spec: Dictionary = _pick_weighted(rng, FLORA_SPECIES)
			var model: String = str(spec["model"])
			var info: Dictionary = TileCatalog.model_info(model, true)
			if not bool(info.get("ok", false)):
				continue
			var h_base: float = maxf((info["aabb"] as AABB).size.y, 0.01)
			var sc: float = rng.randf_range(float(spec["h_min"]),
				float(spec["h_max"])) / h_base
			var xf: Transform3D = TileKit._fit_transform(model, pos,
				rng.randf() * TAU, Vector3.ONE * sc, true)
			_push_batch(flora_batches, model, xf)
			stats["flora"] = int(stats["flora"]) + 1

	var forest_node := Node3D.new()
	forest_node.name = "RedwoodCanopy"
	holder.add_child(forest_node)
	for model: String in tree_batches:
		TileKit._batch_model(forest_node, model, tree_batches[model] as Array,
			"Tree_" + model, false, true)
	for model: String in flora_batches:
		TileKit._batch_model(forest_node, model, flora_batches[model] as Array,
			"Flora_" + model, false, true)


static func _box_clears_spline(spline: RefCounted, centre: Vector3, yaw: float,
		size: Vector3, min_dist: float) -> bool:
	var basis := Basis(Vector3.UP, yaw)
	for pt: Vector3 in TileKit.box_samples(size * 0.5):
		if TileKit.spline_distance(spline, centre + basis * pt) < min_dist:
			return false
	return true


static func _pick_weighted(rng: RandomNumberGenerator,
		items: Array[Dictionary]) -> Dictionary:
	var sum: int = 0
	for item: Dictionary in items:
		sum += int(item["w"])
	var roll: int = rng.randi_range(0, maxi(sum - 1, 0))
	for item: Dictionary in items:
		roll -= int(item["w"])
		if roll < 0:
			return item
	return items[0]


static func _push_batch(batches: Dictionary, model: String,
		xf: Transform3D) -> void:
	if not batches.has(model):
		batches[model] = []
	(batches[model] as Array).append(xf)


static func _world_body(parent: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	return body


static func _add_box_collider(body: StaticBody3D, xform: Transform3D,
		size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = xform
	body.add_child(col)


static func _emit_vertex_mesh(parent: Node3D, node_name: String,
		verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	return inst


static func _quad(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, col: Color) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	n = n.normalized() if n.length_squared() > 0.000001 else Vector3.UP
	if n.y < 0.0 and absf(a.y - c.y) < 0.02:
		n = -n
	for pt: Vector3 in [a, b, c, a, c, d]:
		verts.append(pt)
		normals.append(n)
		colors.append(col)


static func _disc(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, centre: Vector3, rx: float, rz: float,
		segs: int, col: Color) -> void:
	for i in segs:
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		var p0 := centre + Vector3(cos(a0) * rx, 0.0, sin(a0) * rz)
		var p1 := centre + Vector3(cos(a1) * rx, 0.0, sin(a1) * rz)
		for pt: Vector3 in [centre, p1, p0]:
			verts.append(pt)
			normals.append(Vector3.UP)
			colors.append(col)


static func _ring(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, centre: Vector3, rx0: float, rx1: float,
		rz0: float, rz1: float, segs: int, col: Color) -> void:
	for i in segs:
		var a0: float = TAU * float(i) / float(segs)
		var a1: float = TAU * float(i + 1) / float(segs)
		var i0 := centre + Vector3(cos(a0) * rx0, 0.0, sin(a0) * rz0)
		var i1 := centre + Vector3(cos(a1) * rx0, 0.0, sin(a1) * rz0)
		var o0 := centre + Vector3(cos(a0) * rx1, 0.0, sin(a0) * rz1)
		var o1 := centre + Vector3(cos(a1) * rx1, 0.0, sin(a1) * rz1)
		_quad(verts, normals, colors, i0, i1, o1, o0, col)


static func _ribbon(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, pts: Array[Vector3], half_w: float,
		y_val: float, col: Color) -> void:
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var across: Vector3 = dir.cross(Vector3.UP).normalized() * half_w
		var a0 := Vector3(a.x, y_val, a.z) - across
		var a1 := Vector3(a.x, y_val, a.z) + across
		var b0 := Vector3(b.x, y_val, b.z) - across
		var b1 := Vector3(b.x, y_val, b.z) + across
		_quad(verts, normals, colors, a0, a1, b1, b0, col)


static func _box_verts(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, xform: Transform3D, size: Vector3,
		col: Color) -> void:
	var h: Vector3 = size * 0.5
	var p: Array[Vector3] = []
	for ix: float in [-1.0, 1.0]:
		for iy: float in [-1.0, 1.0]:
			for iz: float in [-1.0, 1.0]:
				p.append(xform * Vector3(h.x * ix, h.y * iy, h.z * iz))
	_quad(verts, normals, colors, p[0], p[1], p[3], p[2], col.darkened(0.12))
	_quad(verts, normals, colors, p[4], p[6], p[7], p[5], col.darkened(0.06))
	_quad(verts, normals, colors, p[0], p[4], p[5], p[1], col.darkened(0.18))
	_quad(verts, normals, colors, p[2], p[3], p[7], p[6], col)
	_quad(verts, normals, colors, p[0], p[2], p[6], p[4], col.darkened(0.15))
	_quad(verts, normals, colors, p[1], p[5], p[7], p[3], col.darkened(0.08))


static func _count_draws(node: Node) -> int:
	var total: int = 0
	if node is MeshInstance3D or node is MultiMeshInstance3D or node is Label3D:
		total += 1
	for child: Node in node.get_children():
		total += _count_draws(child)
	return total
