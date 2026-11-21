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
const LandscapeSculptor := preload("res://scripts/minigames/scenery/landscape_sculptor.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const AmbientWorld := preload("res://scripts/minigames/scenery/ambient_world.gd")

const TILE: float = TileKit.TILE_SIZE
const SOLID_MIN_CLEARANCE: float = TileKit.ROAD_HALF + 4.5
const TREE_MIN_CLEARANCE: float = 19.0
const FLOWER_MIN_CLEARANCE: float = TileKit.ROAD_HALF + 3.2
const SEED: int = 20260801

# Natural rounded & pine forest species (no tall narrow spiky cyan cones).
const REDWOOD_SPECIES: Array[Dictionary] = [
	{"model": "tree_pineTallA", "h_min": 12.0, "h_max": 22.0, "w": 5},
	{"model": "tree_pineTallB", "h_min": 12.0, "h_max": 23.0, "w": 5},
	{"model": "tree_pineRoundA", "h_min": 10.0, "h_max": 18.0, "w": 4},
	{"model": "tree_oak", "h_min": 9.5, "h_max": 16.5, "w": 4},
	{"model": "tree_oak_fall", "h_min": 9.5, "h_max": 16.5, "w": 4},
	{"model": "tree_detailed", "h_min": 9.0, "h_max": 15.5, "w": 3},
	{"model": "tree_default_fall", "h_min": 8.5, "h_max": 14.5, "w": 3},
	{"model": "tree_fat", "h_min": 8.0, "h_max": 14.0, "w": 3},
]

const FLORA_SPECIES: Array[Dictionary] = [
	{"model": "flower_redA", "h_min": 0.48, "h_max": 0.90, "w": 4},
	{"model": "flower_yellowA", "h_min": 0.48, "h_max": 0.90, "w": 4},
	{"model": "flower_purpleA", "h_min": 0.48, "h_max": 0.90, "w": 4},
	{"model": "grass_large", "h_min": 0.55, "h_max": 1.15, "w": 5},
	{"model": "plant_bushLarge", "h_min": 1.00, "h_max": 1.95, "w": 3},
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

	# Open-world meadow: timber/brass safety rails only on the 4.5 m viaduct,
	# 9.0 m mountain overlook, and tight outside bends; free verges elsewhere.
	stats["barriers"] = TileKit.selective_safety_rails(holder, spline, {
		"bridge_y": 2.0,
		"curve_min": 0.032,
		"rail_color": Color("9e6b42"),
		"accent_color": Color("df9b3c"),
		"post_color": Color("5c3a20"),
	})
	TileKit.build_outer_soft_containment(holder, spline, 13.0)

	var anchors: Dictionary = _derive_valley_anchors(spline)
	var lake_centre: Vector3 = anchors["lake"]
	var bridge_pos: Vector3 = anchors["bridge"]
	var south_basin: Vector3 = anchors["south_basin"]

	_build_ground_and_water(holder, spline, anchors, stats)
	_build_timber_gantry(holder, spline, stats)
	_build_valley_camps_and_logs(holder, spline, lake_centre, south_basin, stats)
	_build_valley_hills_and_mill(holder, spline, anchors, stats)
	_build_redwood_forest(holder, spline, lake_centre, south_basin, bridge_pos, stats)

	stats["objects"] = int(stats["barriers"]) + int(stats["trees"]) \
		+ int(stats["flora"]) + int(stats["props"]) + int(stats["cliffs"]) + 4
	stats["draws"] = _count_draws(holder)
	return stats


static func _derive_valley_anchors(spline: RefCounted) -> Dictionary:
	var total: float = maxf(float(spline.total_length), 1.0)
	var bmin := Vector2(INF, INF)
	var bmax := Vector2(-INF, -INF)
	for i in 120:
		var p: Vector3 = spline.sample(total * float(i) / 120.0)["position"]
		bmin.x = minf(bmin.x, p.x)
		bmin.y = minf(bmin.y, p.z)
		bmax.x = maxf(bmax.x, p.x)
		bmax.y = maxf(bmax.y, p.z)
	var centre := Vector3((bmin.x + bmax.x) * 0.5, 0.0, (bmin.y + bmax.y) * 0.5)
	var bridge_pos := Vector3(centre.x, 0.0, bmax.y)
	var tiles_val: Variant = spline.get("tiles")
	if tiles_val is Array:
		for t: Variant in tiles_val as Array:
			if t is Dictionary and str((t as Dictionary).get("tile", "")) == "C":
				var cpos: Vector3 = KenneyTiles._cell_center((t as Dictionary)["cell"])
				bridge_pos = Vector3(cpos.x, 0.0, cpos.z)
				break
	var dir_out := Vector3(bridge_pos.x - centre.x, 0.0, bridge_pos.z - centre.z)
	if absf(dir_out.z) >= absf(dir_out.x):
		dir_out = Vector3(0.0, 0.0, 1.0 if dir_out.z >= 0.0 else -1.0)
	else:
		dir_out = Vector3(1.0 if dir_out.x >= 0.0 else -1.0, 0.0, 0.0)
	var south_basin: Vector3 = bridge_pos + dir_out * 64.0
	return {
		"centre": centre,
		"lake": centre + Vector3(-12.0, 0.0, -8.0),
		"bridge": bridge_pos,
		"dir_out": dir_out,
		"south_basin": south_basin,
		"bounds_min": bmin,
		"bounds_max": bmax,
	}


static func _build_ground_and_water(holder: Node3D, spline: RefCounted,
		anchors: Dictionary, stats: Dictionary) -> void:
	var lake_centre: Vector3 = anchors["lake"]
	var bridge_pos: Vector3 = anchors["bridge"]
	var dir_out: Vector3 = anchors["dir_out"]
	var south_basin: Vector3 = anchors["south_basin"]
	var bmin: Vector2 = anchors["bounds_min"]
	var bmax: Vector2 = anchors["bounds_max"]
	var cx: float = (bmin.x + bmax.x) * 0.5
	var cz: float = (bmin.y + bmax.y) * 0.5

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var grass_deep := Color("599b3d")
	var grass_meadow := Color("71b74e")
	var sand_bank := Color("dfd0a3")
	var water_shallow := Color("38cde0")
	var water_deep := Color("1ba3bf")
	var foam := Color("e6fbff")
	var berm_earth := Color("766248")
	var cliff_rock := Color("6e685f")
	var trail_dirt := Color("9a7046")
	var trail_edge := Color("825b36")

	var gy: float = TileKit.Z_GROUND
	var half_ext: float = 1200.0
	_quad(verts, normals, colors,
		Vector3(cx - half_ext, gy, cz - half_ext),
		Vector3(cx + half_ext, gy, cz - half_ext),
		Vector3(cx + half_ext, gy, cz + half_ext),
		Vector3(cx - half_ext, gy, cz + half_ext), grass_deep)

	# Smooth fluid meadow ground blending rich forest green <-> sunlit meadow <-> warm sandy lakeshore!
	var SceneryKitRes := preload("res://scripts/minigames/scenery/scenery_kit.gd")
	var pad_m: float = 110.0
	var fluid_meadow := MeshInstance3D.new()
	fluid_meadow.name = "MeadowFluidGround"
	fluid_meadow.mesh = SceneryKitRes.build_blended_ground(
		Vector2(bmin.x - pad_m, bmin.y - pad_m),
		Vector2(bmax.x + pad_m, bmax.y + pad_m),
		44, gy + 0.005, func(wx: float, wz: float) -> Color:
			var dx_b: float = maxf(maxf(bmin.x - 24.0 - wx, wx - (bmax.x + 24.0)), 0.0)
			var dz_b: float = maxf(maxf(bmin.y - 24.0 - wz, wz - (bmax.y + 24.0)), 0.0)
			var out_t: float = smoothstep(0.0, 68.0, sqrt(dx_b * dx_b + dz_b * dz_b))
			var wave: float = 0.5 + 0.5 * sin(wx * 0.048) * cos(wz * 0.044)
			var base: Color = grass_meadow.lerp(grass_deep, clampf(out_t + wave * 0.30, 0.0, 1.0))
			var ld: float = Vector2(wx - lake_centre.x, wz - lake_centre.z).length()
			var sd: float = Vector2((wx - south_basin.x) * 0.85, wz - south_basin.z).length()
			var shore_t: float = maxf(1.0 - smoothstep(26.0, 42.0, ld), 1.0 - smoothstep(32.0, 50.0, sd))
			return base.lerp(sand_bank, shore_t * 0.82)
	)
	fluid_meadow.material_override = SceneryKitRes.fluid_ground_material(
		Color(0.95, 1.02, 0.90), Color(1.05, 0.98, 0.86), 0.032, 0.14, 0.90)
	fluid_meadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(fluid_meadow)

	# Central infield turquoise lake
	_disc(verts, normals, colors, lake_centre + Vector3.UP * (gy + 0.010),
		34.0, 32.0, 28, sand_bank)
	_disc(verts, normals, colors, lake_centre + Vector3.UP * (gy + 0.016),
		29.0, 27.0, 28, water_shallow)
	_disc(verts, normals, colors, lake_centre + Vector3.UP * (gy + 0.020),
		21.0, 20.0, 24, water_deep)
	_ring(verts, normals, colors, lake_centre + Vector3.UP * (gy + 0.023),
		24.0, 25.4, 22.5, 24.0, 24, foam)

	# River basin beyond the 4.5 m bridge viaduct
	_disc(verts, normals, colors, south_basin + Vector3.UP * (gy + 0.010),
		44.0, 32.0, 28, sand_bank)
	_disc(verts, normals, colors, south_basin + Vector3.UP * (gy + 0.016),
		38.0, 27.0, 28, water_shallow)
	_disc(verts, normals, colors, south_basin + Vector3.UP * (gy + 0.020),
		28.0, 19.5, 24, water_deep)

	# River channel meandering from central lake right beneath the 'C' viaduct
	var river_pts: Array[Vector3] = [
		lake_centre,
		lake_centre.lerp(bridge_pos, 0.42) + Vector3(-10.0, 0.0, 4.0),
		bridge_pos - dir_out * 18.0,
		bridge_pos + dir_out * 18.0,
		south_basin,
	]
	_ribbon(verts, normals, colors, river_pts, 15.0, gy + 0.011, sand_bank)
	_ribbon(verts, normals, colors, river_pts, 11.2, gy + 0.017, water_shallow)
	_ribbon(verts, normals, colors, river_pts, 7.6, gy + 0.021, water_deep)
	_ribbon(verts, normals, colors, river_pts, 1.4, gy + 0.024, foam)

	# Dirt forest trail sector surface (normalized lap frac 0.72..0.93)
	var total: float = maxf(float(spline.total_length), 1.0)
	var dirt_from: float = total * 0.72
	var dirt_to: float = total * 0.93
	var dirt_steps: int = 72
	var surf_y: float = KenneyTiles.ROAD_SURFACE + 0.012
	var half_lane: float = TileKit.ROAD_HALF - 0.35
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

	# Sculpted earthen embankments & viaduct stonework (gap cleanly over river)
	var em_batch := PropBatch.new()
	LandscapeSculptor.add_road_embankment(em_batch, spline, {
		"road_half": TileKit.ROAD_HALF + 0.6,
		"inner_offset": TileKit.ROAD_HALF + 0.75,
		"outer_offset": TileKit.ROAD_HALF + 14.5,
		"ground_y": gy,
		"hill_rise": 1.9,
		"shoulder": grass_meadow,
		"slope": berm_earth,
		"cliff": cliff_rock,
		"skip_center": bridge_pos,
		"skip_radius": 24.0,
		"steps": 168,
	})
	# Stone bridge abutment piers on both banks of the river beneath the 'C' viaduct
	var perp := Vector3(-dir_out.z, 0.0, dir_out.x).normalized()
	var yaw_br: float = atan2(-perp.x, -perp.z)
	for bank_sign: float in [-1.0, 1.0]:
		var bank_pos: Vector3 = bridge_pos + perp * (bank_sign * 18.5)
		em_batch.add_box(Transform3D(Basis(Vector3.UP, yaw_br),
			bank_pos + Vector3.UP * 2.15), Vector3(6.0, 4.4, TILE * 0.78),
			cliff_rock.darkened(0.08))
		em_batch.add_box(Transform3D(Basis(Vector3.UP, yaw_br),
			bank_pos + Vector3.UP * 4.25), Vector3(7.2, 0.55, TILE * 0.84),
			Color("88827a"))
	em_batch.flush_to(holder, "RedwoodEmbankments", true)
	stats["draws"] = int(stats["draws"]) + 1


static func _is_special_tile(spline: RefCounted, s: float) -> bool:
	if not spline.has_method("tile_at"):
		return false
	var t: Variant = spline.call("tile_at", s)
	if not (t is Dictionary):
		return false
	# Only jump ramps are skipped: the walled kicker mesh rises through the
	# ribbon and a flat decal would slice across its deck. Bump tiles stay
	# painted so no grey asphalt wedge survives inside the dirt sector.
	var k: String = str((t as Dictionary).get("tile", ""))
	return k == "J"


static func _build_timber_gantry(holder: Node3D, spline: RefCounted,
		stats: Dictionary) -> void:
	TileKit.gantry(holder, spline, 0.0)
	var frame: Dictionary = spline.sample(150.0)
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

	var post_lat: float = TileKit.ROAD_HALF + 8.6
	var span_w: float = post_lat * 2.0 + 2.2
	var body := _world_body(holder, "TimberGantry")
	for side: float in [-1.0, 1.0]:
		var post_pos: Vector3 = origin + right * (side * post_lat)
		var xform := Transform3D(Basis(Vector3.UP, yaw),
			post_pos + Vector3.UP * 2.8)
		_box_verts(verts, normals, colors, xform, Vector3(1.2, 5.6, 1.2), cedar)
		_add_box_collider(body, xform, Vector3(1.2, 5.6, 1.2))

	var beam_xf := Transform3D(Basis(Vector3.UP, yaw), origin + Vector3.UP * 5.25)
	_box_verts(verts, normals, colors, beam_xf, Vector3(span_w, 1.0, 1.1), pine_beam)
	_box_verts(verts, normals, colors,
		Transform3D(Basis(Vector3.UP, yaw), origin + Vector3.UP * 5.95),
		Vector3(17.5, 0.80, 0.44), banner_green)
	_box_verts(verts, normals, colors,
		Transform3D(Basis(Vector3.UP, yaw), origin + Vector3.UP * 5.95),
		Vector3(16.4, 0.48, 0.50), banner_gold)
	_add_box_collider(body, beam_xf, Vector3(span_w, 1.0, 1.1))
	_emit_vertex_mesh(holder, "TimberGantryMesh", verts, normals, colors)


static func _build_valley_camps_and_logs(holder: Node3D, spline: RefCounted,
		lake_centre: Vector3, south_basin: Vector3, stats: Dictionary) -> void:
	stats["props"] = int(stats["props"]) \
		+ TileKit.grandstand(holder, spline, 32.0, -1.0, true) \
		+ TileKit.grandstand(holder, spline, 82.0, -1.0, false)

	var body := _world_body(holder, "ValleyCampProps")
	var racing_batches: Dictionary = {}
	var nature_batches: Dictionary = {}
	var total: float = maxf(float(spline.total_length), 1.0)

	# Woodland camps along flat clearings well clear of road
	var camp_fractions: Array[float] = [0.08, 0.14, 0.75, 0.81, 0.91, 0.95]
	var tent_models: Array[String] = ["tent", "tentRoof", "tentClosed"]
	for i in camp_fractions.size():
		var s: float = total * camp_fractions[i]
		var f: Dictionary = spline.sample(s)
		var pos: Vector3 = (f["position"] as Vector3) - (f["right"] as Vector3) * 23.0
		if (f["position"] as Vector3).y > 0.25:
			continue
		pos.y = 0.0
		if TileKit.spline_distance(spline, pos) < 20.0:
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

	# Log stacks & wooden post-and-rail fences along woodland verges (>= SOLID_MIN_CLEARANCE)
	var log_models: Array[String] = ["log_stack", "log_large", "fence_simple"]
	var steps: int = 44
	for i in steps:
		var s: float = total * (float(i) + 0.35) / float(steps)
		var f: Dictionary = spline.sample(s)
		var p_road: Vector3 = f["position"]
		if p_road.y > 0.25:
			continue
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var pos: Vector3 = p_road + (f["right"] as Vector3) * ((TileKit.ROAD_HALF + 8.5) * side)
		pos.y = 0.0
		if TileKit.spline_distance(spline, pos) < SOLID_MIN_CLEARANCE + 2.0:
			continue
		if Vector2(pos.x - lake_centre.x, pos.z - lake_centre.z).length() < 36.0:
			continue
		if Vector2(pos.x - south_basin.x, pos.z - south_basin.z).length() < 42.0:
			continue
		var model: String = log_models[i % log_models.size()]
		if not bool(TileCatalog.model_info(model, true).get("ok", false)):
			continue
		var yaw: float = spline.yaw_at(s) + (PI * 0.5 if model == "fence_simple" else 0.25)
		var sc: float = TileKit.NATURE_SCALE * 0.55
		var sz: Vector3 = TileKit._scaled_size(model, Vector3.ONE * sc, true)
		if not _box_clears_spline(spline, pos + Vector3.UP * (sz.y * 0.5), yaw, sz, SOLID_MIN_CLEARANCE):
			continue
		var xf: Transform3D = TileKit._fit_transform(model, pos, yaw,
			Vector3.ONE * sc, true)
		_push_batch(nature_batches, model, xf)
		_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw),
			pos + Vector3.UP * (sz.y * 0.5)), sz)
		stats["props"] = int(stats["props"]) + 1

	var flag_spots: Array = []
	var used_flag_cells: Dictionary = {}
	for frac: float in [0.03, 0.11, 0.30, 0.54, 0.74, 0.94]:
		var s: float = total * frac
		var f: Dictionary = spline.sample(s)
		var raw_pos: Vector3 = (f["position"] as Vector3) - (f["right"] as Vector3) * 19.0
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


## Sculpted 360-degree rolling mountain ridges + alpine peak horizon, cascading
## meadow waterfall & turning waterwheel river mill (registered in AmbientWorld).
static func _build_valley_hills_and_mill(holder: Node3D, spline: RefCounted,
		anchors: Dictionary, stats: Dictionary) -> void:
	var batch := PropBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 404
	var centre: Vector3 = anchors["centre"]
	var bridge_pos: Vector3 = anchors["bridge"]
	var lake_centre: Vector3 = anchors["lake"]
	var hill_pal: Dictionary = {
		"base": Color("478936"),
		"mid": Color("5ea645"),
		"top": Color("7cc458"),
	}
	var ridge_pal: Dictionary = {
		"base": Color("3e7a35"),
		"rock": Color("5a8f4c"),
		"cliff": Color("7fae6a"),
		"snow_lo": Color("a8d8a8"),
		"snow_hi": Color("e4f4e4"),
	}

	# Layered ring of sculpted woodland hills & distant faceted alpine peaks
	var max_span: float = maxf(
		(anchors["bounds_max"] as Vector2).x - (anchors["bounds_min"] as Vector2).x,
		(anchors["bounds_max"] as Vector2).y - (anchors["bounds_min"] as Vector2).y)
	for i in 18:
		var ang: float = TAU * float(i) / 18.0 + 0.1
		var mrad: float = rng.randf_range(44.0, 68.0) if i % 3 == 0 \
			else rng.randf_range(38.0, 62.0)
		var rad: float = max_span * 0.58 + rng.randf_range(34.0, 96.0)
		var pos := Vector3(centre.x + cos(ang) * rad, 0.0, centre.z + sin(ang) * rad)
		if pos.distance_to(bridge_pos) < 88.0:
			continue
		# Sculpted feet spread wider than the base radius: keep the whole
		# mass clear of the road or a hillside lands on the track.
		if TileKit.spline_distance(spline, pos) < mrad * 1.4 + 22.0:
			continue
		if i % 3 == 0:
			LandscapeSculptor.add_alpine_mountain(batch, pos,
				mrad, rng.randf_range(48.0, 82.0), rng, ridge_pal)
		else:
			LandscapeSculptor.add_woodland_hill(batch, pos,
				mrad, rng.randf_range(32.0, 54.0),
				rng.randf_range(16.0, 32.0), rng, hill_pal)

	# Scenic waterfall bluff pouring into the infield lake shoreline
	var fall_base: Vector3 = lake_centre + Vector3(32.0, 0.0, -14.0)
	if TileKit.spline_distance(spline, fall_base) >= 42.0:
		LandscapeSculptor.add_alpine_mountain(batch, fall_base + Vector3(12.0, 0.0, 0.0),
			24.0, 26.0, rng, {
				"base": Color("4a7a52"),
				"rock": Color("5f8f66"),
				"cliff": Color("7fae86"),
				"snow_lo": Color("bfe3c8"),
				"snow_hi": Color("ecf8ef"),
			})
		# Cascading water chute & turquoise splash foam
		for tier in 4:
			var t_y: float = 2.0 + float(tier) * 4.2
			var t_x: float = fall_base.x + float(tier) * 2.0 - 2.0
			batch.add_box(Transform3D(Basis.IDENTITY, Vector3(t_x, t_y, fall_base.z)),
				Vector3(4.2, 4.8, 5.4), Color("46d8eb") if tier % 2 == 0 else Color("daf9ff"))
		stats["props"] = int(stats["props"]) + 1

	batch.flush_to(holder, "ValleyMountainsAndHills", false)
	stats["cliffs"] = int(stats["cliffs"]) + 19

	# Riverside mill house + rotating waterwheel beside the southern river channel
	var anim: Dictionary = AmbientWorld.anim_of(holder)
	var mill_pos: Vector3 = bridge_pos + anchors["dir_out"] * 30.0 + Vector3(-16.0, 0.0, 0.0)
	if TileKit.spline_distance(spline, mill_pos) >= 24.0:
		LandscapeSculptor.build_waterwheel(holder, mill_pos, 0.25, 4.4, anim)
		stats["props"] = int(stats["props"]) + 1


static func _build_redwood_forest(holder: Node3D, spline: RefCounted,
		lake_centre: Vector3, south_basin: Vector3, bridge_pos: Vector3,
		stats: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var tree_batches: Dictionary = {}
	var flora_batches: Dictionary = {}
	var total: float = maxf(float(spline.total_length), 1.0)

	var laterals: Array[float] = [20.5, 28.0, 36.5, 46.0, 58.0, 72.0]
	var steps: int = 110
	for lat: float in laterals:
		for step in steps:
			for side: float in [-1.0, 1.0]:
				if rng.randf() > (0.56 if side < 0.0 else 0.36):
					continue
				var s: float = fposmod(float(step) / float(steps) * total
					+ rng.randf_range(-3.0, 3.0), total)
				var f: Dictionary = spline.sample(s)
				var pos: Vector3 = (f["position"] as Vector3) \
					+ (f["right"] as Vector3) * (lat * side) \
					+ Vector3(rng.randf_range(-2.6, 2.6), 0.0,
						rng.randf_range(-2.6, 2.6))
				pos.y = 0.0
				if TileKit.spline_distance(spline, pos) < TREE_MIN_CLEARANCE:
					continue
				if Vector2(pos.x - lake_centre.x, pos.z - lake_centre.z).length() < 38.0:
					continue
				if Vector2(pos.x - south_basin.x, pos.z - south_basin.z).length() < 46.0:
					continue
				if Vector2(pos.x - bridge_pos.x, pos.z - bridge_pos.z).length() < 24.0:
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
					rng.randf() * TAU, Vector3(sc * 0.96, sc, sc * 0.96), true)
				_push_batch(tree_batches, model, xf)
				stats["trees"] = int(stats["trees"]) + 1

	# Rich roadside wildflowers & meadow shrubs outside the drivable curb
	var flora_steps: int = 160
	for step in flora_steps:
		for side: float in [-1.0, 1.0]:
			if rng.randf() > 0.72:
				continue
			var s: float = total * float(step) / float(flora_steps)
			var f: Dictionary = spline.sample(s)
			var road_p: Vector3 = f["position"]
			if road_p.y > 0.25:
				continue
			var lat: float = rng.randf_range(TileKit.ROAD_HALF + 3.4, TileKit.ROAD_HALF + 10.2)
			var pos: Vector3 = road_p + (f["right"] as Vector3) * (lat * side)
			pos.y = 0.0
			if TileKit.spline_distance(spline, pos) < FLOWER_MIN_CLEARANCE:
				continue
			if Vector2(pos.x - lake_centre.x, pos.z - lake_centre.z).length() < 33.0:
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
