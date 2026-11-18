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

const SOLID_SPLINE_CLEARANCE: float = 16.5
const SOLID_PATH_CLEARANCE: float = 8.5
const ARCH_PIER_PATH_CLEARANCE: float = 10.6
const PLANT_MIN_CLEARANCE: float = 16.0
const SEED: int = 20260802

const PALM_CANDIDATES: Array[String] = [
	"tree_palm", "tree_palmTall", "tree_palmBend", "tree_palmDetailedTall",
	"tree_palmShort", "tree_plateau", "tree_detailed",
]
const CACTUS_CANDIDATES: Array[String] = [
	"cactus_tall", "cactus_short",
]
const CLIFF_CANDIDATES: Array[String] = [
	"cliff_block_stone", "cliff_large_stone", "cliff_block_rock",
	"rock_tallA", "rock_largeA", "stone_largeA",
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

	var total: float = maxf(float(spline.total_length), 1.0)
	var seam: float = TileKit._snap_distance(spline, total * 0.5)
	for side: float in [-1.0, 1.0]:
		stats["barriers"] = int(stats["barriers"]) \
			+ TileKit.barrier_line(holder, spline, 0.0, seam, side, "barrierRed") \
			+ TileKit.barrier_line(holder, spline, seam, 0.0, side, "barrierWhite")

	var left_path: Dictionary = KenneyTiles.clearance_path(spline, -1.0,
		TileKit.BARRIER_CLEARANCE, 1.5)
	var right_path: Dictionary = KenneyTiles.clearance_path(spline, 1.0,
		TileKit.BARRIER_CLEARANCE, 1.5)
	var oasis_centre := Vector3(152.0, 0.0, 208.0)
	_build_desert_ground_and_oasis(holder, spline, oasis_centre, stats)
	_build_mesas_and_arches(holder, spline, left_path, right_path, oasis_centre, stats)
	_build_canyon_cliffs_and_stands(holder, spline, left_path, right_path, oasis_centre, stats)
	_build_oasis_palms_and_cacti(holder, spline, left_path, right_path, oasis_centre, stats)

	stats["objects"] = int(stats["barriers"]) + int(stats["mesas"]) \
		+ int(stats["arches"]) + int(stats["cliffs"]) + int(stats["palms"]) \
		+ int(stats["cacti"]) + int(stats["brush"]) + int(stats["props"])
	stats["draws"] = _count_draws(holder)
	return stats


static func _build_desert_ground_and_oasis(holder: Node3D, spline: RefCounted,
		oasis_centre: Vector3, stats: Dictionary) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var sand_outer := Color("d77643")
	var sand_basin := Color("e49354")
	var oasis_sand := Color("f2da9e")
	var oasis_grass := Color("6cb857")
	var water_rim := Color("34d2df")
	var water_core := Color("179db8")
	var mesa_shelf := Color("bd502d")
	var mesa_wall := Color("9e3b22")
	var mesa_band := Color("d96b38")
	var dirt_tint := Color("c66535")
	var splash_tint := Color("2fbcd0")

	var gy: float = TileKit.Z_GROUND
	_quad(verts, normals, colors,
		Vector3(-680.0, gy, -680.0), Vector3(980.0, gy, -680.0),
		Vector3(980.0, gy, 980.0), Vector3(-680.0, gy, 980.0), sand_outer)
	_quad(verts, normals, colors,
		Vector3(-40.0, gy + 0.005, -40.0), Vector3(350.0, gy + 0.005, -40.0),
		Vector3(350.0, gy + 0.005, 320.0), Vector3(-40.0, gy + 0.005, 320.0),
		sand_basin)

	# Lush oasis fringe + bright turquoise desert pond in southern horseshoe pocket
	_disc(verts, normals, colors, oasis_centre + Vector3.UP * (gy + 0.009),
		24.0, 18.5, 28, oasis_grass)
	_disc(verts, normals, colors, oasis_centre + Vector3.UP * (gy + 0.012),
		20.5, 15.5, 28, oasis_sand)
	_disc(verts, normals, colors, oasis_centre + Vector3.UP * (gy + 0.017),
		17.0, 12.5, 28, water_rim)
	_disc(verts, normals, colors, oasis_centre + Vector3.UP * (gy + 0.021),
		12.0, 8.5, 24, water_core)

	# Stratified red-rock cliff shelf under the 12.0 m mesa rim skyway & switchbacks
	var total: float = maxf(float(spline.total_length), 1.0)
	var steps: int = 144
	for i in steps:
		var s0: float = total * float(i) / float(steps)
		var s1: float = total * float(i + 1) / float(steps)
		var f0: Dictionary = spline.sample(s0)
		var f1: Dictionary = spline.sample(s1)
		var p0: Vector3 = f0["position"]
		var p1: Vector3 = f1["position"]
		if maxf(p0.y, p1.y) < 0.20:
			continue
		var r0: Vector3 = f0["right"]
		var r1: Vector3 = f1["right"]
		for side: float in [-1.0, 1.0]:
			var reach: float = 31.0 if side < 0.0 else 17.5
			var in0: Vector3 = p0 + r0 * (8.4 * side)
			var in1: Vector3 = p1 + r1 * (8.4 * side)
			var out0: Vector3 = p0 + r0 * (reach * side)
			var out1: Vector3 = p1 + r1 * (reach * side)
			in0.y = p0.y - 0.02
			in1.y = p1.y - 0.02
			out0.y = p0.y - 0.04 if side < 0.0 else maxf(p0.y * 0.52, gy)
			out1.y = p1.y - 0.04 if side < 0.0 else maxf(p1.y * 0.52, gy)
			_quad(verts, normals, colors, in0, in1, out1, out0, mesa_shelf)
			var mid0_y: float = lerpf(gy, out0.y, 0.55)
			var mid1_y: float = lerpf(gy, out1.y, 0.55)
			_quad(verts, normals, colors,
				out0, out1,
				Vector3(out1.x, mid1_y, out1.z),
				Vector3(out0.x, mid0_y, out0.z), mesa_band)
			_quad(verts, normals, colors,
				Vector3(out0.x, mid0_y, out0.z),
				Vector3(out1.x, mid1_y, out1.z),
				Vector3(out1.x, gy, out1.z),
				Vector3(out0.x, gy, out0.z), mesa_wall)

	# Dusty red-earth canyon trail overlays on the two "dirt" sectors
	var road_y: float = KenneyTiles.ROAD_SURFACE + 0.011
	var half_lane: float = TileKit.ROAD_HALF - 0.50
	for span_pair: Vector2 in [Vector2(0.40, 0.61), Vector2(0.72, 0.85)]:
		var d_steps: int = 36
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

	# Oasis splash puddles on the flat 0.0 m southern straight (skipping J at 0.656..0.672!)
	var splash_y: float = KenneyTiles.ROAD_SURFACE + 0.013
	for frac: float in [0.625, 0.644, 0.680, 0.700]:
		if _is_special_tile(spline, total * frac):
			continue
		var f: Dictionary = spline.sample(total * frac)
		var p: Vector3 = f["position"]
		if p.y > 0.05:
			continue
		var side_off: Vector3 = (f["right"] as Vector3) * (1.5 if int(frac * 100.0) % 2 == 0 else -1.5)
		_disc(verts, normals, colors,
			Vector3(p.x + side_off.x, p.y + splash_y, p.z + side_off.z),
			2.7, 2.0, 14, splash_tint)

	_emit_vertex_mesh(holder, "CanyonGroundAndOasis", verts, normals, colors)
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
		oasis_centre: Vector3, stats: Dictionary) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var body := _world_body(holder, "CanyonMesasAndArches")

	var layer_colors: Array[Color] = [
		Color("9f3921"),
		Color("c24e2c"),
		Color("dc723c"),
		Color("ea9c54"),
		Color("f1ba72"),
	]

	# Towering stratified red-rock mesas framing the horizon & central canyon basin
	var mesa_sites: Array[Dictionary] = [
		{"pos": Vector3(114.0, 0.0, 108.0), "w": 30.0, "d": 26.0, "h": 22.0, "yaw": 0.22},
		{"pos": Vector3(152.0, 0.0, -42.0), "w": 54.0, "d": 28.0, "h": 30.0, "yaw": 0.08},
		{"pos": Vector3(322.0, 0.0, 72.0), "w": 38.0, "d": 46.0, "h": 32.0, "yaw": -0.22},
		{"pos": Vector3(324.0, 0.0, 184.0), "w": 36.0, "d": 38.0, "h": 26.0, "yaw": 0.35},
		{"pos": Vector3(-36.0, 0.0, 108.0), "w": 34.0, "d": 56.0, "h": 30.0, "yaw": 0.12},
		{"pos": Vector3(152.0, 0.0, 304.0), "w": 58.0, "d": 30.0, "h": 27.0, "yaw": -0.10},
		{"pos": Vector3(24.0, 0.0, 258.0), "w": 34.0, "d": 30.0, "h": 22.0, "yaw": 0.42},
		{"pos": Vector3(276.0, 0.0, 268.0), "w": 36.0, "d": 32.0, "h": 24.0, "yaw": -0.34},
	]
	for site: Dictionary in mesa_sites:
		var base_pos: Vector3 = site["pos"]
		var w: float = float(site["w"])
		var d: float = float(site["d"])
		var h: float = float(site["h"])
		var yaw: float = float(site["yaw"])
		var col_size := Vector3(w * 0.9, h, d * 0.9)
		if not _box_clears_all(spline, left_path, right_path,
				base_pos + Vector3.UP * (h * 0.5), yaw, col_size,
				SOLID_SPLINE_CLEARANCE, SOLID_PATH_CLEARANCE):
			continue
		var half_diag: float = Vector2(w, d).length() * 0.5
		if Vector2(base_pos.x - oasis_centre.x, base_pos.z - oasis_centre.z).length() < half_diag + 20.0:
			continue
		var tiers: int = 4
		var cur_y: float = 0.0
		for t in tiers:
			var shrink: float = 1.0 - float(t) * 0.14
			var tier_h: float = h / float(tiers)
			var size := Vector3(w * shrink, tier_h, d * shrink)
			var xf := Transform3D(Basis(Vector3.UP, yaw + float(t) * 0.04),
				base_pos + Vector3.UP * (cur_y + tier_h * 0.5))
			_box_verts(verts, normals, colors, xf, size,
				layer_colors[t % layer_colors.size()])
			cur_y += tier_h
		_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw),
			base_pos + Vector3.UP * (h * 0.5)), col_size)
		stats["mesas"] = int(stats["mesas"]) + 1

	# Twin monumental red-rock canyon arches over flat 0.0 m canyon straights:
	#   * lowest_y = 4.90 m (>= 4.5 m overhead clearance!)
	#   * side piers at +-20.8 m (inner face >= 11.4 m from clearance_path!)
	var total: float = maxf(float(spline.total_length), 1.0)
	for arch_s: float in [total * 0.487, total * 0.787]:
		var f: Dictionary = spline.sample(arch_s)
		var origin: Vector3 = f["position"]
		if origin.y > 0.25:
			continue
		var right: Vector3 = f["right"]
		var forward: Vector3 = f["forward"]
		var yaw: float = atan2(-forward.x, -forward.z)
		var pier_size := Vector3(2.6, 6.8, 3.4)
		var left_pier: Vector3 = origin - right * 20.8
		var right_pier: Vector3 = origin + right * 20.8
		left_pier.y = origin.y
		right_pier.y = origin.y
		if not _box_clears_all(spline, left_path, right_path,
				left_pier + Vector3.UP * 3.4, yaw, pier_size,
				19.0, ARCH_PIER_PATH_CLEARANCE):
			continue
		if not _box_clears_all(spline, left_path, right_path,
				right_pier + Vector3.UP * 3.4, yaw, pier_size,
				19.0, ARCH_PIER_PATH_CLEARANCE):
			continue
		for pier_base: Vector3 in [left_pier, right_pier]:
			var pier_xf := Transform3D(Basis(Vector3.UP, yaw),
				pier_base + Vector3.UP * 3.4)
			_box_verts(verts, normals, colors, pier_xf,
				pier_size, layer_colors[1])
			_box_verts(verts, normals, colors,
				Transform3D(Basis(Vector3.UP, yaw), pier_base + Vector3.UP * 1.4),
				Vector3(3.1, 2.8, 3.9), layer_colors[0])
			_add_box_collider(body, pier_xf, pier_size)
		# Overhead sandstone arch lintel + crown (lowest_y = 5.75 - 0.85 = 4.90 m >= 4.5 m!)
		var span_xf := Transform3D(Basis(Vector3.UP, yaw),
			origin + Vector3.UP * 5.75)
		_box_verts(verts, normals, colors, span_xf,
			Vector3(44.2, 1.7, 3.2), layer_colors[2])
		_box_verts(verts, normals, colors,
			Transform3D(Basis(Vector3.UP, yaw), origin + Vector3.UP * 6.95),
			Vector3(34.0, 0.95, 2.6), layer_colors[3])
		_add_box_collider(body, span_xf, Vector3(44.2, 1.7, 3.2))
		stats["arches"] = int(stats["arches"]) + 1

	# Cartoon saguaro cacti accents (visual vertex mesh, >= 8.5 m from clearance_path)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 77
	var cactus_green := Color("3b8c47")
	var cactus_dark := Color("2d6e37")
	for idx in 60:
		var s: float = total * float(idx) / 60.0
		var f: Dictionary = spline.sample(s)
		var side: float = -1.0 if idx % 2 == 0 else 1.0
		var lat: float = rng.randf_range(17.5, 34.0)
		var pos: Vector3 = (f["position"] as Vector3) + (f["right"] as Vector3) * (lat * side)
		pos.y = 0.0
		if (f["position"] as Vector3).y > 1.6 and lat < 22.0:
			continue
		if not _point_clears_all(spline, left_path, right_path, pos,
				PLANT_MIN_CLEARANCE, SOLID_PATH_CLEARANCE):
			continue
		if Vector2(pos.x - oasis_centre.x, pos.z - oasis_centre.z).length() < 19.0:
			continue
		var h: float = rng.randf_range(2.8, 4.8)
		var c_yaw: float = rng.randf() * TAU
		var base_b := Basis(Vector3.UP, c_yaw)
		_box_verts(verts, normals, colors,
			Transform3D(base_b, pos + Vector3.UP * (h * 0.5)),
			Vector3(0.52, h, 0.52), cactus_green)
		_box_verts(verts, normals, colors,
			Transform3D(base_b, pos + base_b * Vector3(0.55, h * 0.56, 0.0)),
			Vector3(0.65, 0.36, 0.38), cactus_dark)
		_box_verts(verts, normals, colors,
			Transform3D(base_b, pos + base_b * Vector3(0.76, h * 0.72, 0.0)),
			Vector3(0.38, h * 0.36, 0.38), cactus_green)
		_box_verts(verts, normals, colors,
			Transform3D(base_b, pos + base_b * Vector3(-0.52, h * 0.46, 0.0)),
			Vector3(0.60, 0.34, 0.36), cactus_dark)
		_box_verts(verts, normals, colors,
			Transform3D(base_b, pos + base_b * Vector3(-0.72, h * 0.60, 0.0)),
			Vector3(0.36, h * 0.30, 0.36), cactus_green)
		stats["cacti"] = int(stats["cacti"]) + 1

	_emit_vertex_mesh(holder, "CanyonMesasArchesCactiMesh", verts, normals, colors)
	stats["draws"] = int(stats["draws"]) + 1


static func _build_canyon_cliffs_and_stands(holder: Node3D, spline: RefCounted,
		left_path: Dictionary, right_path: Dictionary,
		oasis_centre: Vector3, stats: Dictionary) -> void:
	var total: float = maxf(float(spline.total_length), 1.0)
	TileKit.gantry(holder, spline, 0.0)
	stats["props"] = int(stats["props"]) \
		+ TileKit.grandstand(holder, spline, 32.0, -1.0, true) \
		+ TileKit.grandstand(holder, spline, total * 0.640, -1.0, false)

	var body := _world_body(holder, "CanyonCliffProps")
	var cliff_models: Array[String] = _available_models(CLIFF_CANDIDATES, true)
	var batches: Dictionary = {}
	if not cliff_models.is_empty():
		var steps: int = 48
		for i in steps:
			var s: float = total * float(i) / float(steps)
			var f: Dictionary = spline.sample(s)
			var side: float = -1.0 if i % 3 != 0 else 1.0
			var lat: float = 24.0 + float(i % 3) * 5.0
			var pos: Vector3 = (f["position"] as Vector3) + (f["right"] as Vector3) * (lat * side)
			pos.y = 0.0
			if Vector2(pos.x - oasis_centre.x, pos.z - oasis_centre.z).length() < 25.0:
				continue
			var model: String = cliff_models[i % cliff_models.size()]
			var sc: float = TileKit.NATURE_SCALE * (0.70 + 0.25 * float(i % 3))
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

	# Desert racing flags: snap to 16 m cell centre FIRST and verify >= 9.0 m
	# from clearance_path (>= 17.5 m from spline) BEFORE calling TileKit.flags!
	var flags: Array = []
	var used_cells: Dictionary = {}
	for frac: float in [0.04, 0.15, 0.30, 0.48, 0.63, 0.78, 0.90]:
		var s: float = total * frac
		var f: Dictionary = spline.sample(s)
		var raw_pos: Vector3 = (f["position"] as Vector3) - (f["right"] as Vector3) * 19.5
		var snapped: Vector3 = TileKit._snap_point(raw_pos)
		snapped.y = (f["position"] as Vector3).y if (f["position"] as Vector3).y > 0.5 else 0.0
		var cell_key := Vector2i(int(round(snapped.x)), int(round(snapped.z)))
		if used_cells.has(cell_key):
			continue
		var flag_box := Vector3(2.2, 5.0, 2.2)
		if _box_clears_all(spline, left_path, right_path,
				snapped + Vector3.UP * 2.5, 0.0, flag_box,
				SOLID_SPLINE_CLEARANCE + 1.0, SOLID_PATH_CLEARANCE + 0.5):
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
		var palm_count: int = 34
		for i in palm_count:
			var ang: float = TAU * float(i) / float(palm_count) + rng.randf_range(-0.08, 0.08)
			var rx: float = rng.randf_range(18.5, 25.5)
			var rz: float = rng.randf_range(14.0, 19.5)
			var pos := oasis_centre + Vector3(cos(ang) * rx, 0.0, sin(ang) * rz)
			pos.y = 0.0
			if not _point_clears_all(spline, left_path, right_path, pos,
					PLANT_MIN_CLEARANCE, SOLID_PATH_CLEARANCE):
				continue
			var model: String = palm_models[i % palm_models.size()]
			var info: Dictionary = TileCatalog.model_info(model, true)
			var h_base: float = maxf((info["aabb"] as AABB).size.y, 0.01)
			var sc: float = rng.randf_range(8.5, 14.5) / h_base
			var xf: Transform3D = TileKit._fit_transform(model, pos,
				rng.randf() * TAU, Vector3.ONE * sc, true)
			_push_batch(batches, model, xf)
			stats["palms"] = int(stats["palms"]) + 1

	var total: float = maxf(float(spline.total_length), 1.0)
	if not cactus_models.is_empty():
		for i in 76:
			var s: float = total * rng.randf()
			var f: Dictionary = spline.sample(s)
			var side: float = -1.0 if rng.randf() < 0.5 else 1.0
			var pos: Vector3 = (f["position"] as Vector3) \
				+ (f["right"] as Vector3) * (side * rng.randf_range(17.5, 38.0))
			pos.y = 0.0
			if not _point_clears_all(spline, left_path, right_path, pos,
					PLANT_MIN_CLEARANCE, SOLID_PATH_CLEARANCE):
				continue
			if Vector2(pos.x - oasis_centre.x, pos.z - oasis_centre.z).length() < 19.5:
				continue
			var model: String = cactus_models[i % cactus_models.size()]
			var info: Dictionary = TileCatalog.model_info(model, true)
			var h_base: float = maxf((info["aabb"] as AABB).size.y, 0.01)
			var sc: float = rng.randf_range(2.6, 5.2) / h_base
			var xf: Transform3D = TileKit._fit_transform(model, pos,
				rng.randf() * TAU, Vector3.ONE * sc, true)
			_push_batch(batches, model, xf)
			stats["cacti"] = int(stats["cacti"]) + 1

	if not brush_models.is_empty():
		for i in 240:
			var s: float = total * rng.randf()
			var f: Dictionary = spline.sample(s)
			var side: float = -1.0 if rng.randf() < 0.55 else 1.0
			var pos: Vector3 = (f["position"] as Vector3) \
				+ (f["right"] as Vector3) * (side * rng.randf_range(16.2, 46.0))
			pos.y = 0.0
			if not _point_clears_all(spline, left_path, right_path, pos,
					PLANT_MIN_CLEARANCE, SOLID_PATH_CLEARANCE):
				continue
			if Vector2(pos.x - oasis_centre.x, pos.z - oasis_centre.z).length() < 18.0:
				continue
			var model: String = brush_models[i % brush_models.size()]
			var info: Dictionary = TileCatalog.model_info(model, true)
			var h_base: float = maxf((info["aabb"] as AABB).size.y, 0.01)
			var sc: float = rng.randf_range(0.45, 1.25) / h_base
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
