extends RefCounted
## Scenery builder for SUNSET CANYON (`canyon`).
##
## Cartoon red-rock desert mesa, stratified sandstone arches (lowest_y >= 4.9 m
## over the road, piers >= 10.5 m from KenneyTiles.clearance_path), turquoise
## desert oasis pond, palm grove, cacti & cliff walls. Every low solid collider
## stays >= 8.5 m from clearance_path (>= 16.5 m from spline centreline).
## Zero photoreal PBR textures; <= 50 draw calls total.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const KenneyTiles := preload("res://scripts/minigames/tiles/kenney_tiles.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const LandscapeSculptor := preload("res://scripts/minigames/scenery/landscape_sculptor.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const AmbientWorld := preload("res://scripts/minigames/scenery/ambient_world.gd")

const SOLID_SPLINE_CLEARANCE: float = TileKit.ROAD_HALF + 4.5
const SOLID_PATH_CLEARANCE: float = 4.0
const ARCH_PIER_PATH_CLEARANCE: float = 0.8
const PLANT_MIN_CLEARANCE: float = TileKit.ROAD_HALF + 3.2
const SEED: int = 20260802

const PALM_CANDIDATES: Array[String] = [
	"tree_palm", "tree_palmTall", "tree_palmBend", "tree_palmDetailedTall",
	"tree_palmShort", "tree_plateau", "tree_detailed",
]
const CACTUS_CANDIDATES: Array[String] = [
	"cactus_tall", "cactus_short",
]
const CLIFF_CANDIDATES: Array[String] = [
	"rock_largeA", "rock_largeB", "stone_largeA",
]
const DESERT_BRUSH: Array[String] = [
	"plant_flatShort", "plant_bushSmall", "rock_smallA", "rock_smallFlatA",
	"flower_yellowA",
]


static func build(holder: Node3D, spline: RefCounted) -> Dictionary:
	var stats: Dictionary = {
		"objects": 0,
		"draws": 0,
		"barriers": 0,
		"mesas": 0,
		"arches": 0,
		"cliffs": 0,
		"palms": 0,
		"cacti": 0,
		"brush": 0,
		"props": 0,
	}
	if holder == null or spline == null:
		return stats

	# Open canyon circuit: warm rust/amber rails only along mesa cliffs & sharp bends
	stats["barriers"] = TileKit.selective_safety_rails(holder, spline, {
		"bridge_y": 2.0,
		"curve_min": 0.032,
		"rail_color": Color("e28945"),
		"accent_color": Color("c7422a"),
		"post_color": Color("7d3a22"),
	})
	TileKit.build_outer_soft_containment(holder, spline, 13.5)

	var left_path: Dictionary = KenneyTiles.clearance_path(spline, -1.0,
		TileKit.BARRIER_CLEARANCE, 1.5)
	var right_path: Dictionary = KenneyTiles.clearance_path(spline, 1.0,
		TileKit.BARRIER_CLEARANCE, 1.5)

	var anchors: Dictionary = _derive_canyon_anchors(spline)
	var oasis_centre: Vector3 = anchors["oasis"]

	_build_desert_ground_and_oasis(holder, spline, anchors, stats)
	_build_mesas_and_arches(holder, spline, left_path, right_path, anchors, stats)
	_build_canyon_cliffs_and_stands(holder, spline, left_path, right_path, oasis_centre, stats)
	_build_oasis_palms_and_cacti(holder, spline, left_path, right_path, oasis_centre, stats)

	stats["objects"] = int(stats["barriers"]) + int(stats["mesas"]) \
		+ int(stats["arches"]) + int(stats["cliffs"]) + int(stats["palms"]) \
		+ int(stats["cacti"]) + int(stats["brush"]) + int(stats["props"])
	stats["draws"] = _count_draws(holder)
	return stats


static func _derive_canyon_anchors(spline: RefCounted) -> Dictionary:
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
	var span_x: float = bmax.x - bmin.x
	var span_z: float = bmax.y - bmin.y
	# Find the spacious southern oasis basin inside the horseshoe fold
	var oasis := Vector3(centre.x, 0.0, bmin.y + span_z * 0.62)
	var best_dist: float = TileKit.spline_distance(spline, oasis)
	for gz: float in [0.52, 0.58, 0.65, 0.72]:
		for gx: float in [0.45, 0.50, 0.55]:
			var cand := Vector3(bmin.x + span_x * gx, 0.0, bmin.y + span_z * gz)
			var d: float = TileKit.spline_distance(spline, cand)
			if d > best_dist:
				best_dist = d
				oasis = cand
	return {
		"centre": centre,
		"oasis": oasis,
		"bounds_min": bmin,
		"bounds_max": bmax,
	}


static func _build_desert_ground_and_oasis(holder: Node3D, spline: RefCounted,
		anchors: Dictionary, stats: Dictionary) -> void:
	var oasis_centre: Vector3 = anchors["oasis"]
	var bmin: Vector2 = anchors["bounds_min"]
	var bmax: Vector2 = anchors["bounds_max"]
	var cx: float = (bmin.x + bmax.x) * 0.5
	var cz: float = (bmin.y + bmax.y) * 0.5

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var sand_outer := Color("d6743f")
	var sand_basin := Color("e49354")
	var oasis_sand := Color("f2da9e")
	var oasis_grass := Color("5fad4c")
	var water_rim := Color("34d2df")
	var water_core := Color("179db8")
	var dirt_tint := Color("c66535")
	var splash_tint := Color("2fbcd0")

	var gy: float = TileKit.Z_GROUND
	var half_ext: float = 1200.0
	_quad(verts, normals, colors,
		Vector3(cx - half_ext, gy, cz - half_ext),
		Vector3(cx + half_ext, gy, cz - half_ext),
		Vector3(cx + half_ext, gy, cz + half_ext),
		Vector3(cx - half_ext, gy, cz + half_ext), sand_outer)
	_quad(verts, normals, colors,
		Vector3(bmin.x - 52.0, gy + 0.005, bmin.y - 52.0),
		Vector3(bmax.x + 52.0, gy + 0.005, bmin.y - 52.0),
		Vector3(bmax.x + 52.0, gy + 0.005, bmax.y + 52.0),
		Vector3(bmin.x - 52.0, gy + 0.005, bmax.y + 52.0), sand_basin)

	# Lush turquoise oasis pond in canyon pocket (bounded to never touch tracks)
	var pond_r: float = clampf(TileKit.spline_distance(spline, oasis_centre) - 14.0,
		16.0, 30.0)
	_disc(verts, normals, colors, oasis_centre + Vector3.UP * (gy + 0.009),
		pond_r * 1.16, pond_r * 0.94, 28, oasis_grass)
	_disc(verts, normals, colors, oasis_centre + Vector3.UP * (gy + 0.012),
		pond_r * 0.98, pond_r * 0.78, 28, oasis_sand)
	_disc(verts, normals, colors, oasis_centre + Vector3.UP * (gy + 0.017),
		pond_r * 0.80, pond_r * 0.64, 28, water_rim)
	_disc(verts, normals, colors, oasis_centre + Vector3.UP * (gy + 0.021),
		pond_r * 0.56, pond_r * 0.44, 24, water_core)

	# Dusty red-earth canyon trail overlays on the two "dirt" sectors
	var total: float = maxf(float(spline.total_length), 1.0)
	var road_y: float = KenneyTiles.ROAD_SURFACE + 0.011
	var half_lane: float = TileKit.ROAD_HALF - 0.40
	for span_pair: Vector2 in [Vector2(0.40, 0.61), Vector2(0.72, 0.85)]:
		var d_steps: int = 44
		for idx in d_steps:
			var s0: float = total * lerpf(span_pair.x, span_pair.y, float(idx) / float(d_steps))
			var s1: float = total * lerpf(span_pair.x, span_pair.y, float(idx + 1) / float(d_steps))
			if _is_special_tile(spline, s0) or _is_special_tile(spline, s1):
				continue
			var f0: Dictionary = spline.sample(s0)
			var f1: Dictionary = spline.sample(s1)
			var c0: Vector3 = (f0["position"] as Vector3) + Vector3.UP * road_y
			var c1: Vector3 = (f1["position"] as Vector3) + Vector3.UP * road_y
			var r0: Vector3 = f0["right"]
			var r1: Vector3 = f1["right"]
			_quad(verts, normals, colors,
				c0 - r0 * half_lane, c0 + r0 * half_lane,
				c1 + r1 * half_lane, c1 - r1 * half_lane, dirt_tint)

	# Oasis spring splash puddles along the southern flat oasis road
	var splash_y: float = KenneyTiles.ROAD_SURFACE + 0.013
	for frac: float in [0.625, 0.644, 0.680, 0.700]:
		if _is_special_tile(spline, total * frac):
			continue
		var f: Dictionary = spline.sample(total * frac)
		var p: Vector3 = f["position"]
		if p.y > 0.05:
			continue
		var side_off: Vector3 = (f["right"] as Vector3) * (2.0 if int(frac * 100.0) % 2 == 0 else -2.0)
		_disc(verts, normals, colors,
			Vector3(p.x + side_off.x, p.y + splash_y, p.z + side_off.z),
			3.2, 2.4, 14, splash_tint)

	_emit_vertex_mesh(holder, "CanyonGroundAndOasis", verts, normals, colors)
	stats["draws"] = int(stats["draws"]) + 1

	# Warm terracotta sandstone embankments supporting elevated rim & switchbacks
	var em_batch := PropBatch.new()
	LandscapeSculptor.add_road_embankment(em_batch, spline, {
		"road_half": TileKit.ROAD_HALF + 0.6,
		"inner_offset": TileKit.ROAD_HALF + 0.55,
		"outer_offset": TileKit.ROAD_HALF + 16.0,
		"ground_y": gy,
		"hill_rise": 1.6,
		"shoulder": sand_basin,
		"slope": Color("c24e2c"),
		"cliff": Color("9f3921"),
		"steps": 160,
	})
	em_batch.flush_to(holder, "CanyonSandstoneTerraces", true)
	stats["draws"] = int(stats["draws"]) + 1


static func _is_special_tile(spline: RefCounted, s: float) -> bool:
	if not spline.has_method("tile_at"):
		return false
	var t: Variant = spline.call("tile_at", s)
	if not (t is Dictionary):
		return false
	var k: String = str((t as Dictionary).get("tile", ""))
	return k == "B" or k == "J"


static func _build_mesas_and_arches(holder: Node3D, spline: RefCounted,
		left_path: Dictionary, right_path: Dictionary,
		anchors: Dictionary, stats: Dictionary) -> void:
	var oasis_centre: Vector3 = anchors["oasis"]
	var centre: Vector3 = anchors["centre"]
	var bmin: Vector2 = anchors["bounds_min"]
	var bmax: Vector2 = anchors["bounds_max"]
	var span: float = maxf(bmax.x - bmin.x, bmax.y - bmin.y)

	var body := _world_body(holder, "CanyonMesasAndArches")
	var sculptor_batch := PropBatch.new()
	var cacti_batch := PropBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 77

	var layer_colors: Array[Color] = [
		Color("9f3921"),
		Color("c24e2c"),
		Color("dc723c"),
		Color("ea9c54"),
		Color("f1ba72"),
	]
	var mesa_pal: Dictionary = {
		"base": Color("9f3921"),
		"band": Color("d96b38"),
		"cap": Color("e99f5c"),
	}

	# Irregular multi-tiered mesas & wind-carved spires ringing the horizon + infield
	for i in 16:
		var ang: float = TAU * float(i) / 16.0 + 0.12
		var r: float = span * 0.56 + rng.randf_range(38.0, 92.0)
		var pos := Vector3(centre.x + cos(ang) * r, 0.0, centre.z + sin(ang) * r)
		var rad: float = rng.randf_range(22.0, 38.0)
		var h: float = rng.randf_range(26.0, 58.0)
		if TileKit.spline_distance(spline, pos) < rad + 18.0:
			continue
		if i % 3 == 0:
			LandscapeSculptor.add_canyon_spire(sculptor_batch, pos, rad * 0.55, h * 1.05, rng)
		else:
			LandscapeSculptor.add_stratified_mesa(sculptor_batch, pos, rad, h, 4, rng, mesa_pal)
		stats["mesas"] = int(stats["mesas"]) + 1

	# Inner canyon basin butte overlooking the north infield (away from oasis)
	var infield_butte: Vector3 = centre + Vector3(-24.0, 0.0, -34.0)
	if TileKit.spline_distance(spline, infield_butte) >= 34.0 \
			and infield_butte.distance_to(oasis_centre) >= 42.0:
		LandscapeSculptor.add_stratified_mesa(sculptor_batch, infield_butte,
			16.0, 24.0, 3, rng, mesa_pal)
		var butte_sz := Vector3(24.0, 24.0, 24.0)
		if _box_clears_all(spline, left_path, right_path,
				infield_butte + Vector3.UP * 12.0, 0.25, butte_sz,
				SOLID_SPLINE_CLEARANCE + 2.0, SOLID_PATH_CLEARANCE):
			_add_box_collider(body, Transform3D(Basis(Vector3.UP, 0.25),
				infield_butte + Vector3.UP * 12.0), butte_sz)
		stats["mesas"] = int(stats["mesas"]) + 1

	# Sculpted Oasis waterfall ledge feeding turquoise spring water into oasis pond
	var spring_pos: Vector3 = oasis_centre + Vector3(0.0, 0.0, -24.0)
	if TileKit.spline_distance(spline, spring_pos) >= 26.0:
		LandscapeSculptor.add_stratified_mesa(sculptor_batch, spring_pos,
			12.0, 14.0, 3, rng, mesa_pal)
		for fall_i in 3:
			sculptor_batch.add_box(Transform3D(Basis.IDENTITY,
				spring_pos + Vector3(0.0, 2.0 + float(fall_i) * 3.8, 7.5)),
				Vector3(3.6, 4.2, 1.8), Color("46d8eb") if fall_i % 2 == 0 else Color("daf9ff"))

	# Twin sculpted Natural Rock Arches spanning flat desert straightaways:
	# span_width = 25.0 m => piers at +-14.3 m (inner collider +-12.2 m >> 8.09 m!)
	var total: float = maxf(float(spline.total_length), 1.0)
	var arch_s_placed: Array[float] = []
	for step_i in 48:
		if int(stats["arches"]) >= 2:
			break
		var arch_s: float = total * float(step_i) / 48.0
		var too_close: bool = false
		for prev_s: float in arch_s_placed:
			if absf(fposmod(arch_s - prev_s + total * 0.5, total) - total * 0.5) < total * 0.22:
				too_close = true
				break
		if too_close:
			continue
		var f: Dictionary = spline.sample(arch_s)
		var origin: Vector3 = f["position"]
		if origin.y > 1.5 or absf(angle_difference(spline.yaw_at(arch_s + 12.0), spline.yaw_at(arch_s - 12.0))) > 0.14:
			continue
		var right: Vector3 = f["right"]
		var forward: Vector3 = f["forward"]
		var yaw: float = atan2(-forward.x, -forward.z)
		var pier_offset: float = 15.6
		var pier_size := Vector3(4.2, 6.8, 4.6)
		var left_pier: Vector3 = origin - right * pier_offset
		var right_pier: Vector3 = origin + right * pier_offset
		left_pier.y = origin.y
		right_pier.y = origin.y
		if not _box_clears_all(spline, left_path, right_path,
				left_pier + Vector3.UP * 2.0, yaw, pier_size,
				TileKit.ROAD_HALF + 3.5, ARCH_PIER_PATH_CLEARANCE):
			continue
		if not _box_clears_all(spline, left_path, right_path,
				right_pier + Vector3.UP * 2.0, yaw, pier_size,
				TileKit.ROAD_HALF + 3.5, ARCH_PIER_PATH_CLEARANCE):
			continue
		LandscapeSculptor.add_natural_arch(sculptor_batch, body, origin, yaw,
			27.6, 6.6, 3.8, layer_colors[1], layer_colors[2])
		arch_s_placed.append(arch_s)
		stats["arches"] = int(stats["arches"]) + 1

	sculptor_batch.flush_to(holder, "CanyonMesasAndArchesMesh", true)
	stats["draws"] = int(stats["draws"]) + 1

	# Spinning Desert Windmill overlooking the southern oasis basin
	var windmill_pos: Vector3 = oasis_centre + Vector3(26.0, 0.0, -18.0)
	if TileKit.spline_distance(spline, windmill_pos) >= 20.0:
		LandscapeSculptor.build_windmill(holder, windmill_pos, -0.45, 1.15,
			"canyon", AmbientWorld.anim_of(holder))
		stats["props"] = int(stats["props"]) + 1

	# Cartoon saguaro cacti accents (vertex mesh along desert verges)
	var cactus_green := Color("3b8c47")
	var cactus_dark := Color("2d6e37")
	for idx in 76:
		var s: float = total * float(idx) / 76.0
		var f: Dictionary = spline.sample(s)
		var side: float = -1.0 if idx % 2 == 0 else 1.0
		var lat: float = rng.randf_range(TileKit.ROAD_HALF + 8.5, TileKit.ROAD_HALF + 26.0)
		var pos: Vector3 = (f["position"] as Vector3) + (f["right"] as Vector3) * (lat * side)
		pos.y = 0.0
		if (f["position"] as Vector3).y > 1.6 and lat < TileKit.ROAD_HALF + 14.0:
			continue
		if not _point_clears_all(spline, left_path, right_path, pos,
				PLANT_MIN_CLEARANCE, SOLID_PATH_CLEARANCE):
			continue
		if Vector2(pos.x - oasis_centre.x, pos.z - oasis_centre.z).length() < 24.0:
			continue
		var h: float = rng.randf_range(2.8, 4.8)
		var c_yaw: float = rng.randf() * TAU
		var base_b := Basis(Vector3.UP, c_yaw)
		cacti_batch.add_box(Transform3D(base_b, pos + Vector3.UP * (h * 0.5)),
			Vector3(0.52, h, 0.52), cactus_green)
		cacti_batch.add_box(Transform3D(base_b, pos + base_b * Vector3(0.55, h * 0.56, 0.0)),
			Vector3(0.65, 0.36, 0.38), cactus_dark)
		cacti_batch.add_box(Transform3D(base_b, pos + base_b * Vector3(0.76, h * 0.72, 0.0)),
			Vector3(0.38, h * 0.36, 0.38), cactus_green)
		cacti_batch.add_box(Transform3D(base_b, pos + base_b * Vector3(-0.52, h * 0.46, 0.0)),
			Vector3(0.60, 0.34, 0.36), cactus_dark)
		cacti_batch.add_box(Transform3D(base_b, pos + base_b * Vector3(-0.72, h * 0.60, 0.0)),
			Vector3(0.36, h * 0.30, 0.36), cactus_green)
		stats["cacti"] = int(stats["cacti"]) + 1

	cacti_batch.flush_to(holder, "CanyonSaguaroCactiMesh", false)
	stats["draws"] = int(stats["draws"]) + 1


static func _build_canyon_cliffs_and_stands(holder: Node3D, spline: RefCounted,
		left_path: Dictionary, right_path: Dictionary,
		oasis_centre: Vector3, stats: Dictionary) -> void:
	var total: float = maxf(float(spline.total_length), 1.0)
	TileKit.gantry(holder, spline, 0.0)
	stats["props"] = int(stats["props"]) \
		+ TileKit.grandstand(holder, spline, 36.0, -1.0, true) \
		+ TileKit.grandstand(holder, spline, total * 0.640, -1.0, false)

	var body := _world_body(holder, "CanyonCliffProps")
	var cliff_models: Array[String] = _available_models(CLIFF_CANDIDATES, true)
	var batches: Dictionary = {}
	if not cliff_models.is_empty():
		var steps: int = 56
		for i in steps:
			var s: float = total * float(i) / float(steps)
			var f: Dictionary = spline.sample(s)
			var side: float = -1.0 if i % 3 != 0 else 1.0
			var lat: float = TileKit.ROAD_HALF + 16.5 + float(i % 3) * 6.0
			var pos: Vector3 = (f["position"] as Vector3) + (f["right"] as Vector3) * (lat * side)
			pos.y = 0.0
			if Vector2(pos.x - oasis_centre.x, pos.z - oasis_centre.z).length() < 28.0:
				continue
			var model: String = cliff_models[i % cliff_models.size()]
			var sc: float = TileKit.NATURE_SCALE * (0.68 + 0.25 * float(i % 3))
			var yaw: float = spline.yaw_at(s) + float(i) * 0.7
			var sz: Vector3 = TileKit._scaled_size(model, Vector3.ONE * sc, true)
			var col_sz: Vector3 = sz * 0.85
			if not _box_clears_all(spline, left_path, right_path,
					pos + Vector3.UP * (sz.y * 0.5), yaw, col_sz,
					SOLID_SPLINE_CLEARANCE, SOLID_PATH_CLEARANCE):
				continue
			var xf: Transform3D = TileKit._fit_transform(model, pos, yaw,
				Vector3.ONE * sc, true)
			_push_batch(batches, model, xf)
			_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw),
				pos + Vector3.UP * (sz.y * 0.5)), col_sz)
			stats["cliffs"] = int(stats["cliffs"]) + 1

	for model: String in batches:
		TileKit._batch_model(holder, model, batches[model] as Array,
			"CanyonCliff_" + model, false, true)

	var flags: Array = []
	var used_cells: Dictionary = {}
	for frac: float in [0.04, 0.14, 0.29, 0.46, 0.62, 0.77, 0.90]:
		var s: float = total * frac
		var f: Dictionary = spline.sample(s)
		var raw_pos: Vector3 = (f["position"] as Vector3) - (f["right"] as Vector3) * (TileKit.ROAD_HALF + 11.5)
		var snapped: Vector3 = TileKit._snap_point(raw_pos)
		snapped.y = (f["position"] as Vector3).y if (f["position"] as Vector3).y > 0.5 else 0.0
		var cell_key := Vector2i(int(round(snapped.x)), int(round(snapped.z)))
		if used_cells.has(cell_key):
			continue
		var flag_box := Vector3(2.2, 5.0, 2.2)
		if _box_clears_all(spline, left_path, right_path,
				snapped + Vector3.UP * 2.5, 0.0, flag_box,
				SOLID_SPLINE_CLEARANCE + 1.0, SOLID_PATH_CLEARANCE):
			used_cells[cell_key] = true
			flags.append({
				"position": snapped,
				"kind": "flagRed" if int(frac * 100.0) % 2 == 0 else "flagCheckers",
				"yaw": spline.yaw_at(s),
			})
	stats["props"] = int(stats["props"]) + TileKit.flags(holder, flags)
	if body.get_child_count() == 0:
		body.free()


static func _build_oasis_palms_and_cacti(holder: Node3D, spline: RefCounted,
		left_path: Dictionary, right_path: Dictionary,
		oasis_centre: Vector3, stats: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 303
	var batches: Dictionary = {}
	var palm_models: Array[String] = _available_models(PALM_CANDIDATES, true)
	var cactus_models: Array[String] = _available_models(CACTUS_CANDIDATES, true)
	var brush_models: Array[String] = _available_models(DESERT_BRUSH, true)

	if not palm_models.is_empty():
		var palm_count: int = 38
		for i in palm_count:
			var ang: float = TAU * float(i) / float(palm_count) + rng.randf_range(-0.08, 0.08)
			var rx: float = rng.randf_range(19.5, 29.0)
			var rz: float = rng.randf_range(15.5, 23.0)
			var pos := oasis_centre + Vector3(cos(ang) * rx, 0.0, sin(ang) * rz)
			pos.y = 0.0
			if not _point_clears_all(spline, left_path, right_path, pos,
					PLANT_MIN_CLEARANCE, SOLID_PATH_CLEARANCE):
				continue
			var model: String = palm_models[i % palm_models.size()]
			var info: Dictionary = TileCatalog.model_info(model, true)
			var h_base: float = maxf((info["aabb"] as AABB).size.y, 0.01)
			var sc: float = rng.randf_range(9.0, 15.0) / h_base
			var xf: Transform3D = TileKit._fit_transform(model, pos,
				rng.randf() * TAU, Vector3.ONE * sc, true)
			_push_batch(batches, model, xf)
			stats["palms"] = int(stats["palms"]) + 1

	var total: float = maxf(float(spline.total_length), 1.0)
	if not cactus_models.is_empty():
		for i in 96:
			var s: float = total * rng.randf()
			var f: Dictionary = spline.sample(s)
			var side: float = -1.0 if rng.randf() < 0.5 else 1.0
			var pos: Vector3 = (f["position"] as Vector3) \
				+ (f["right"] as Vector3) * (side * rng.randf_range(TileKit.ROAD_HALF + 8.5, TileKit.ROAD_HALF + 32.0))
			pos.y = 0.0
			if not _point_clears_all(spline, left_path, right_path, pos,
					PLANT_MIN_CLEARANCE, SOLID_PATH_CLEARANCE):
				continue
			if Vector2(pos.x - oasis_centre.x, pos.z - oasis_centre.z).length() < 22.0:
				continue
			var model: String = cactus_models[i % cactus_models.size()]
			var info: Dictionary = TileCatalog.model_info(model, true)
			var h_base: float = maxf((info["aabb"] as AABB).size.y, 0.01)
			var sc: float = rng.randf_range(2.8, 5.4) / h_base
			var xf: Transform3D = TileKit._fit_transform(model, pos,
				rng.randf() * TAU, Vector3.ONE * sc, true)
			_push_batch(batches, model, xf)
			stats["cacti"] = int(stats["cacti"]) + 1

	if not brush_models.is_empty():
		for i in 280:
			var s: float = total * rng.randf()
			var f: Dictionary = spline.sample(s)
			var side: float = -1.0 if rng.randf() < 0.55 else 1.0
			var pos: Vector3 = (f["position"] as Vector3) \
				+ (f["right"] as Vector3) * (side * rng.randf_range(TileKit.ROAD_HALF + 3.5, TileKit.ROAD_HALF + 36.0))
			pos.y = 0.0
			if not _point_clears_all(spline, left_path, right_path, pos,
					PLANT_MIN_CLEARANCE, SOLID_PATH_CLEARANCE):
				continue
			if Vector2(pos.x - oasis_centre.x, pos.z - oasis_centre.z).length() < 20.0:
				continue
			var model: String = brush_models[i % brush_models.size()]
			var info: Dictionary = TileCatalog.model_info(model, true)
			var h_base: float = maxf((info["aabb"] as AABB).size.y, 0.01)
			var sc: float = rng.randf_range(0.50, 1.35) / h_base
			var xf: Transform3D = TileKit._fit_transform(model, pos,
				rng.randf() * TAU, Vector3.ONE * sc, true)
			_push_batch(batches, model, xf)
			stats["brush"] = int(stats["brush"]) + 1

	var flora_holder := Node3D.new()
	flora_holder.name = "CanyonFlora"
	holder.add_child(flora_holder)
	for model: String in batches:
		TileKit._batch_model(flora_holder, model, batches[model] as Array,
			"Desert_" + model, false, true)


static func _point_clears_all(spline: RefCounted, left_path: Dictionary,
		right_path: Dictionary, world_pt: Vector3, min_spline: float,
		min_path: float) -> bool:
	if TileKit.spline_distance(spline, world_pt) < min_spline:
		return false
	if _path_plan_distance(left_path, world_pt) < min_path:
		return false
	if _path_plan_distance(right_path, world_pt) < min_path:
		return false
	return true


static func _box_clears_all(spline: RefCounted, left_path: Dictionary,
		right_path: Dictionary, centre: Vector3, yaw: float, size: Vector3,
		min_spline: float, min_path: float) -> bool:
	var basis := Basis(Vector3.UP, yaw)
	for sample: Vector3 in TileKit.box_samples(size * 0.5):
		var world_pt: Vector3 = centre + basis * sample
		if not _point_clears_all(spline, left_path, right_path, world_pt,
				min_spline, min_path):
			return false
	return true


static func _path_plan_distance(path: Dictionary, pt: Vector3) -> float:
	if not bool(path.get("ok", false)):
		return INF
	var pts: PackedVector3Array = path.get("points", PackedVector3Array())
	if pts.is_empty():
		return INF
	var p2 := Vector2(pt.x, pt.z)
	var best_sq: float = INF
	for i in range(pts.size() - 1):
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var ab: Vector2 = b - a
		var len_sq: float = ab.length_squared()
		var t: float = 0.0 if len_sq < 0.00001 else clampf((p2 - a).dot(ab) / len_sq, 0.0, 1.0)
		var d_sq: float = p2.distance_squared_to(a + ab * t)
		if d_sq < best_sq:
			best_sq = d_sq
	return sqrt(best_sq)


static func _available_models(candidates: Array[String],
		nature: bool) -> Array[String]:
	var out: Array[String] = []
	for m: String in candidates:
		if bool(TileCatalog.model_info(m, nature).get("ok", false)):
			out.append(m)
	return out


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
	mat.roughness = 0.96
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
