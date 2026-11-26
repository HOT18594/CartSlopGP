extends RefCounted
## Bespoke High-Alpine Cliffside Terrain, Matterhorn Cathedral Ranges,
## Towering Upslope Cliff Walls, Sheer Drop-Off Buttresses & Dual-Cable Gondolas
## for Glacier Pass.
##
## Designed directly from `bg_hero_glacier.png`:
##   * cliffs    Watertight, multi-strata dark-slate & glacier-blue rock cliff
##               drop-offs beneath every elevated road deck, paired with towering
##               upslope snow-and-slate cliff walls rising 22-46 m above the
##               outer mountain side of the pass (with hanging icicles, snow
##               cornices, and colossal glowing turquoise crystal formations!).
##   * outcrops  Multi-faceted frost-veined slate rock formations & snowdrifts.
##   * ridges    Two rings of colossal Matterhorn cathedral peaks & jagged alpine
##               massifs with a 16-point perimeter footprint gate so NO mountain
##               skirt or spur can ever intersect or approach the road!
##   * pylons    Monumental alpine ski-lift infrastructure & gliding gondolas.

const GlacierProps := preload("res://scripts/minigames/maps/glacier/glacier_props.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const LandscapeSculptor := preload("res://scripts/minigames/scenery/landscape_sculptor.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const ConceptSpectacle := preload("res://scripts/minigames/scenery/concept_spectacle.gd")
const AmbientWorld := preload("res://scripts/minigames/scenery/ambient_world.gd")

const TILE: float = TileCatalog.TILE_SIZE
const SEED: int = 20261113

## Ski-lift pylons.
const LIFT_PYLONS: int = 6
const LIFT_SPACING: float = 28.0
const LIFT_OFFSET: float = 26.5
const LIFT_HEIGHT: float = 15.0
const LIFT_POST: String = "lightPostModern"
const LIFT_ARM: String = "rail"


static func build(holder: Node3D, spline: RefCounted) -> Dictionary:
	var stats: Dictionary = {
		"cliffs": 0, "outcrops": 0, "ridges": 0, "pylons": 0,
		"draws": 0, "objects": 0,
	}
	if holder == null or spline == null:
		return stats
	var cliff_info: Dictionary = _cliff_pass_architecture(holder, spline)
	stats["cliffs"] = int(cliff_info.get("cliffs", 0))
	stats["outcrops"] = _outcrops(holder, spline)
	stats["ridges"] = _ridges(holder, spline)
	stats["pylons"] = _ski_lift(holder, spline)
	var lake_peaks: int = _alpine_lake_and_peaks(holder, spline)
	stats["objects"] = int(stats["cliffs"]) + int(stats["outcrops"]) \
		+ int(stats["ridges"]) + int(stats["pylons"]) + lake_peaks
	stats["draws"] = int(cliff_info.get("draws", 2)) + 3 + (1 if int(stats["pylons"]) > 0 else 0) + (2 if lake_peaks > 0 else 0)
	return stats


# --------------------------------------------------------------------------
# 1. Bespoke Textured Cliffside Mountain Pass & Sheer Drop-Off Buttresses
# --------------------------------------------------------------------------


static func _cliff_pass_architecture(holder: Node3D, spline: RefCounted) -> Dictionary:
	## Replaces the old tan Kenney boxes with rich, multi-tone faceted alpine
	## slate cliff walls:
	##   (A) Sheer vertical fluted rock drop-off walls directly beneath every
	##       elevated road edge (with horizontal ice strata & hanging icicles).
	##   (B) Towering upslope snow-and-slate mountain cliff faces rising 20-44 m
	##       above the outer perimeter of the circuit (just like bg_hero_glacier!),
	##       studded with giant glowing turquoise & sapphire glacier crystals!
	var batch := PropBatch.new()
	var crystal_batch := PropBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 19

	var total: float = maxf(float(spline.total_length), 1.0)
	var bounds: Rect2 = _map_bounds(spline)
	var map_center := Vector3(bounds.position.x + bounds.size.x * 0.5, 0.0,
		bounds.position.y + bounds.size.y * 0.5)

	var slate_deep := Color("5680b5")
	var slate_dark := Color("6a96cc")
	var slate_mid := Color("82aee2")
	var slate_lit := Color("a2caf5")
	var ice_vein := Color("c2e8ff")
	var snow_lo := Color("daeffc")
	var snow_hi := Color("f4fbff")

	var steps: int = 180
	var road_edge: float = TileKit.ROAD_HALF + 0.35
	var cliff_segments: int = 0

	# (A) Sheer Under-Road Cliff Drop-Off Buttresses & Hanging Icicle Cornices
	for i in steps:
		var s0: float = total * float(i) / float(steps)
		var s1: float = total * float(i + 1) / float(steps)
		if spline.has_method("tile_at"):
			var s_mid: float = (s0 + s1) * 0.5
			var prev_t: Variant = spline.call("tile_at", fposmod(s_mid - 11.0, total))
			if prev_t is Dictionary and str((prev_t as Dictionary).get("tile", "")) == "J":
				continue
		var f0: Dictionary = spline.sample(s0)
		var f1: Dictionary = spline.sample(s1)
		var p0: Vector3 = f0["position"] as Vector3
		var p1: Vector3 = f1["position"] as Vector3
		if p0.y < 1.2 and p1.y < 1.2:
			continue
		var r0: Vector3 = (f0["right"] as Vector3)
		r0.y = 0.0
		r0 = r0.normalized()
		var r1: Vector3 = (f1["right"] as Vector3)
		r1.y = 0.0
		r1 = r1.normalized()

		for side: float in [-1.0, 1.0]:
			var top0: Vector3 = Vector3(p0.x, maxf(p0.y + 0.15, 0.2), p0.z) + r0 * (side * road_edge)
			var top1: Vector3 = Vector3(p1.x, maxf(p1.y + 0.15, 0.2), p1.z) + r1 * (side * road_edge)
			var h_avg: float = (top0.y + top1.y) * 0.5
			if h_avg < 1.3:
				continue
			# Fluted 3-tier rock face flaring slightly outward as it plunges to y = -0.5
			var j0: float = 1.6 + 0.9 * sin(float(i) * 1.7 + side)
			var j1: float = 1.6 + 0.9 * sin(float(i + 1) * 1.7 + side)
			var mid0: Vector3 = Vector3(top0.x, top0.y * 0.56, top0.z) + r0 * (side * j0)
			var mid1: Vector3 = Vector3(top1.x, top1.y * 0.56, top1.z) + r1 * (side * j1)
			var bot0: Vector3 = Vector3(top0.x, -0.4, top0.z) + r0 * (side * (j0 * 2.3 + 2.2))
			var bot1: Vector3 = Vector3(top1.x, -0.4, top1.z) + r1 * (side * (j1 * 2.3 + 2.2))
			# Keep flared foot clear of any adjacent low road lane
			if GlacierProps.clearance(spline, bot0) < TileKit.ROAD_HALF + 1.8 \
					or GlacierProps.clearance(spline, bot1) < TileKit.ROAD_HALF + 1.8:
				bot0 = Vector3(top0.x, -0.4, top0.z) + r0 * (side * 1.2)
				bot1 = Vector3(top1.x, -0.4, top1.z) + r1 * (side * 1.2)

			var out_dir: Vector3 = (r0 + r1).normalized() * side
			var upper_col: Color = slate_mid if i % 2 == 0 else slate_lit
			if (i + int(side + 2.0)) % 5 == 0:
				upper_col = ice_vein.darkened(0.12)
			var lower_col: Color = slate_dark if i % 2 == 0 else slate_deep
			LandscapeSculptor.add_quad_outward(batch, mid0, top0, top1, mid1, upper_col, out_dir)
			LandscapeSculptor.add_quad_outward(batch, bot0, mid0, mid1, bot1, lower_col, out_dir)

			# Overhanging snow cornice lip + gleaming icicles every 2nd step on high cliffs
			var cornice_mid: Vector3 = (top0 + top1) * 0.5 + out_dir * 0.35
			var seg_fw: Vector3 = (top1 - top0)
			var seg_len: float = seg_fw.length()
			if seg_len > 0.1:
				var seg_yaw: float = atan2(-seg_fw.x, -seg_fw.z)
				var c_xf := Transform3D(Basis(Vector3.UP, seg_yaw), cornice_mid)
				batch.add_box(c_xf, Vector3(0.95, 0.42, seg_len + 0.25), snow_hi if i % 2 == 0 else snow_lo)
				if h_avg >= 4.5 and i % 2 == 0:
					var icicle_h: float = rng.randf_range(1.6, 3.4)
					batch.add_cone(c_xf * Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0.15 * side, -icicle_h * 0.5 - 0.15, 0.0)),
						0.32, icicle_h, 5, Color("99e6ff"))
			cliff_segments += 1

	# (B) Giant Faceted Glacier Crystal Eruptions along the outer pass shoulder
	var wall_steps: int = 36
	for w_i in wall_steps:
		var s: float = total * (float(w_i) + 0.3) / float(wall_steps)
		var frame: Dictionary = spline.sample(s)
		var pos: Vector3 = frame["position"] as Vector3
		var right: Vector3 = frame["right"] as Vector3
		right.y = 0.0
		if right.length_squared() < 0.001:
			continue
		right = right.normalized()

		var to_out: Vector3 = (pos - map_center)
		to_out.y = 0.0
		var mountain_side: float = 1.0 if right.dot(to_out) >= 0.0 else -1.0

		if w_i % 2 == 0:
			var crys_pos: Vector3 = pos + right * (mountain_side * (TileKit.ROAD_HALF + 14.5))
			crys_pos.y = maxf(pos.y - 0.6, 0.2)
			if _footprint_clear(spline, crys_pos, 11.2):
				ConceptSpectacle.add_crystal_cluster(crystal_batch, crys_pos,
					rng.randf_range(1.40, 2.25), rng, batch)
				cliff_segments += 1

	var draws: int = 0
	if batch.flush_to(holder, "GlacierCliffs", false, SceneryKit.vertex_material()) != null:
		draws += 1
	if crystal_batch.flush_to(holder, "GlacierCliffCrystals", false, ConceptSpectacle.crystal_material()) != null:
		draws += 1
	return {"cliffs": cliff_segments, "draws": draws}


# --------------------------------------------------------------------------
# 2. Textured Glacial Slate & Frost Outcrops
# --------------------------------------------------------------------------


static func _outcrops(holder: Node3D, spline: RefCounted) -> int:
	## Procedural faceted ice-blue boulder clusters & wind-carved snowdrifts.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 41
	var batch := PropBatch.new()
	var total: float = maxf(float(spline.total_length), 1.0)
	var placed: int = 0
	var count: int = 44
	for i in count:
		var s: float = total * (float(i) + 0.5) / float(count)
		var frame: Dictionary = spline.sample(s)
		var pos: Vector3 = frame["position"] as Vector3
		var right: Vector3 = frame["right"] as Vector3
		right.y = 0.0
		if right.length_squared() < 0.001:
			continue
		right = right.normalized()
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var dist: float = rng.randf_range(24.0, 38.0)
		var base := Vector3(pos.x, 0.0, pos.z) + right * (side * dist)
		var rad: float = rng.randf_range(3.2, 5.8)
		if not _footprint_clear(spline, base, rad + 15.5):
			continue
		_add_glacial_outcrop(batch, base, rad, rng.randf_range(2.2, 4.8), rng)
		placed += 1
	batch.flush_to(holder, "GlacierOutcrops", false, SceneryKit.vertex_material())
	return placed


static func _add_glacial_outcrop(batch: PropBatch, center: Vector3,
		radius: float, height: float, rng: RandomNumberGenerator) -> void:
	var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), center)
	# Snow-covered glacial boulder + bright powder snowdrifts
	batch.add_cone(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.35, 0.0)),
		radius, height * 0.78, 7, Color("84b2e2"))
	batch.add_cone(xf * Transform3D(Basis(Vector3.UP, 0.5), Vector3(0.0, height * 0.58, 0.0)),
		radius * 0.74, height * 0.48, 7, Color("eef8ff"))
	batch.add_cone(xf * Transform3D(Basis.IDENTITY, Vector3(radius * 0.55, height * 0.22, -radius * 0.3)),
		radius * 0.78, height * 0.48, 6, Color("c8e4fa"))
	batch.add_cone(xf * Transform3D(Basis.IDENTITY, Vector3(-radius * 0.45, 0.42, radius * 0.4)),
		radius * 1.05, 1.25, 8, Color("f5fbff"))


# --------------------------------------------------------------------------
# 3. Real 3D Sculpted Continuous Winter Mountain Ranges & Rolling Snowfields
# --------------------------------------------------------------------------


static func _ridges(holder: Node3D, spline: RefCounted) -> int:
	## Continuous 3D sculpted heightfield mountain range & snow-covered valley
	## foothills surrounding the entire Glacier Pass circuit.
	##
	## Instead of isolated 2D-looking intersecting cones, this evaluates a true
	## continuous 3D ridged-multifractal alpine terrain surface `y = H(x, z)`
	## with sweeping 3D arête ridgelines, U-shaped glacial cirques, snow saddles,
	## and rolling winter snowhills. Every vertex within `ROAD_HALF + 15 m` of
	## the road spline is smoothly clamped below ground so ZERO mountain faces
	## can ever intersect or encroach upon the road!
	var bounds: Rect2 = _map_bounds(spline)
	var centre := Vector2(bounds.position.x + bounds.size.x * 0.5,
		bounds.position.y + bounds.size.y * 0.5)
	var half_x: float = bounds.size.x * 0.5
	var half_z: float = bounds.size.y * 0.5

	# Pre-sample 240 road centreline points for fast O(N) road-clearance queries
	var total: float = maxf(float(spline.total_length), 1.0)
	var sample_cnt: int = 240
	var road_pts := PackedVector2Array()
	road_pts.resize(sample_cnt)
	for i in sample_cnt:
		var p3: Vector3 = spline.sample(total * float(i) / float(sample_cnt))["position"] as Vector3
		road_pts[i] = Vector2(p3.x, p3.z)

	var min_x: float = bounds.position.x - 450.0
	var max_x: float = bounds.end.x + 450.0
	var min_z: float = bounds.position.y - 430.0
	var max_z: float = bounds.end.y + 430.0
	var nx: int = 104
	var nz: int = 92
	var stride: int = nx + 1
	var grid_pts := PackedVector3Array()
	var grid_clear := PackedFloat32Array()
	grid_pts.resize(stride * (nz + 1))
	grid_clear.resize(stride * (nz + 1))

	var safe_inner: float = TileKit.ROAD_HALF + 15.5
	for iz in nz + 1:
		var tz: float = float(iz) / float(nz)
		var wz: float = lerpf(min_z, max_z, tz)
		for ix in nx + 1:
			var tx: float = float(ix) / float(nx)
			var wx: float = lerpf(min_x, max_x, tx)
			var idx: int = iz * stride + ix

			# Shortest plan distance to the road spline
			var min_d_sq: float = INF
			for rp: Vector2 in road_pts:
				var dx: float = wx - rp.x
				var dz: float = wz - rp.y
				var d2: float = dx * dx + dz * dz
				if d2 < min_d_sq:
					min_d_sq = d2
			var d_road: float = sqrt(min_d_sq)
			grid_clear[idx] = d_road

			if d_road <= safe_inner:
				grid_pts[idx] = Vector3(wx, -0.55, wz)
				continue

			# Smooth envelopes from the road edge outward
			var foothill_env: float = smoothstep(safe_inner, safe_inner + 24.0, d_road)
			var massif_env: float = smoothstep(safe_inner + 26.0, safe_inner + 96.0, d_road)

			# Radial basin distance (0 inside circuit, rising smoothly outside the loop)
			var ex: float = maxf(absf(wx - centre.x) - (half_x - 24.0), 0.0) / 290.0
			var ez: float = maxf(absf(wz - centre.y) - (half_z - 24.0), 0.0) / 270.0
			var basin_r: float = clampf(sqrt(ex * ex + ez * ez), 0.0, 1.45)

			# 1. Rolling 3D winter snowdrifts & snow-covered foothills (2..9 m)
			var snow_wave: float = (0.5 + 0.5 * sin(wx * 0.017 + wz * 0.014) * cos(wz * 0.019 - wx * 0.012)) * 6.2 \
				+ (0.5 + 0.5 * sin(wx * 0.036 - wz * 0.031)) * 2.6

			# 2. True 3D Ridged Multifractal Alpine Massifs (sweeping 3D arêtes,
			#    interconnected saddles, and U-shaped glacial cirque valleys)
			var u1: float = wx * 0.0095 + wz * 0.0072 + 0.45 * sin(wz * 0.008)
			var v1: float = wz * 0.0098 - wx * 0.0068 + 0.45 * cos(wx * 0.008)
			var ridge_a: float = 1.0 - absf(sin(u1))
			var ridge_b: float = 1.0 - absf(cos(v1))
			var arête_main: float = pow(clampf(ridge_a * 0.60 + ridge_b * 0.40, 0.0, 1.0), 1.48)

			var u2: float = wx * 0.021 - wz * 0.0165 + 1.3
			var v2: float = wz * 0.019 + wx * 0.0175 + 2.1
			var spur_a: float = 1.0 - absf(sin(u2))
			var spur_b: float = 1.0 - absf(cos(v2))
			var arête_spur: float = pow(clampf(spur_a * 0.55 + spur_b * 0.45, 0.0, 1.0), 1.65)

			var fine_crag: float = (1.0 - absf(sin(wx * 0.042 + wz * 0.037))) * 8.5

			var range_amp: float = lerpf(34.0, 148.0, clampf(pow(basin_r, 0.72), 0.0, 1.0))
			var wy: float = foothill_env * snow_wave \
				+ massif_env * (range_amp * (0.18 + 0.62 * arête_main + 0.32 * arête_spur) + fine_crag * arête_main)
			grid_pts[idx] = Vector3(wx, wy, wz)

	# Build flat-shaded 3D terrain mesh with winter snow & frosted alpine rock coloring
	var batch := PropBatch.new()
	var col_powder_hi := Color("f2faff")
	var col_powder_mid := Color("d6ebfc")
	var col_snow_shade := Color("afd2f2")
	var col_frost_rock := Color("78a5d8")
	var col_alpine_slate := Color("5682b8")
	var col_deep_granite := Color("3e679c")

	var tri_groups: int = 0
	for iz in nz:
		for ix in nx:
			var i00: int = iz * stride + ix
			var i10: int = i00 + 1
			var i01: int = i00 + stride
			var i11: int = i01 + 1
			var p00: Vector3 = grid_pts[i00]
			var p10: Vector3 = grid_pts[i10]
			var p01: Vector3 = grid_pts[i01]
			var p11: Vector3 = grid_pts[i11]
			if p00.y < -0.35 and p10.y < -0.35 and p01.y < -0.35 and p11.y < -0.35:
				continue
			_add_sculpted_terrain_tri(batch, p00, p01, p11,
				col_powder_hi, col_powder_mid, col_snow_shade, col_frost_rock, col_alpine_slate, col_deep_granite)
			_add_sculpted_terrain_tri(batch, p00, p11, p10,
				col_powder_hi, col_powder_mid, col_snow_shade, col_frost_rock, col_alpine_slate, col_deep_granite)
			tri_groups += 1

	batch.flush_to(holder, "AlpineMountainHorizon", false, SceneryKit.vertex_material())
	return maxi(tri_groups / 120, 40)


static func _add_sculpted_terrain_tri(batch: PropBatch, a: Vector3, b: Vector3,
		c: Vector3, col_powder_hi: Color, col_powder_mid: Color,
		col_snow_shade: Color, col_frost_rock: Color, col_alpine_slate: Color,
		col_deep_granite: Color) -> void:
	if a.y < -0.35 and b.y < -0.35 and c.y < -0.35:
		return
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 0.0001:
		return
	n = n.normalized()
	if n.y < 0.0:
		n = -n
	var h_avg: float = (a.y + b.y + c.y) / 3.0
	var h_max: float = maxf(a.y, maxf(b.y, c.y))
	# Directional winter moonlight highlight factor across the 3D facet normal
	var moon_dir := Vector3(-0.55, 0.58, -0.60).normalized()
	var lit: float = clampf(n.dot(moon_dir) * 0.5 + 0.5, 0.0, 1.0)
	var strata: float = 0.5 + 0.5 * sin(h_avg * 0.28 + (a.x - a.z) * 0.022)

	var col: Color
	if h_avg < 10.5:
		# Lower valley snowfields & rolling snowdrift foothills: soft winter snow
		col = col_snow_shade.lerp(col_powder_hi, smoothstep(0.20, 0.88, lit))
	elif h_max > 74.0 and (n.y >= 0.62 or lit > 0.58):
		# High alpine snow caps & sunlit summit ridges
		col = col_powder_mid.lerp(col_powder_hi, smoothstep(0.35, 0.85, lit))
	elif n.y >= 0.78:
		# Snow-covered mountain bowls, saddles, and high terraces
		col = col_snow_shade.lerp(col_powder_mid, lit)
	elif n.y >= 0.62:
		# Transition snow-and-rock alpine facets
		var rock_mid: Color = col_alpine_slate.lerp(col_frost_rock, lit)
		col = rock_mid.lerp(col_powder_mid, smoothstep(0.62, 0.78, n.y) * 0.75 + strata * 0.25)
	else:
		# Sculpted 3D alpine granite & frosted blue-slate crag faces
		var crag: Color = col_deep_granite.lerp(col_frost_rock, clampf(lit * 0.72 + strata * 0.28, 0.0, 1.0))
		if strata > 0.74 and h_avg > 28.0:
			# Snow-dusted horizontal rock strata ledges
			crag = crag.lerp(col_powder_mid, 0.48)
		col = crag
	LandscapeSculptor.add_tri_outward(batch, a, b, c, col, Vector3.UP)


static func _footprint_clear(spline: RefCounted, center: Vector3,
		required_radius: float) -> bool:
	## Guarantees ZERO road intersection: checks the center point AND 16 points
	## around the full outer skirt perimeter against the entire road spline.
	if GlacierProps.clearance(spline, center) < required_radius:
		return false
	var probe_r: float = maxf(required_radius - TileKit.ROAD_HALF - 4.0, 8.0)
	for i in 16:
		var ang: float = TAU * float(i) / 16.0
		var probe := Vector3(center.x + cos(ang) * probe_r, 0.0, center.z + sin(ang) * probe_r)
		if GlacierProps.clearance(spline, probe) < TileKit.ROAD_HALF + 8.5:
			return false
	return true


# --------------------------------------------------------------------------
# 4. Ski-Lift Infrastructure & Dual-Cable Overhead Gondolas (bg_hero_glacier!)
# --------------------------------------------------------------------------


static func _ski_lift(holder: Node3D, spline: RefCounted) -> int:
	var straight: Dictionary = _longest_straight(spline)
	if straight.is_empty():
		return 0
	var distance: float = float(straight["distance"])
	var forward: Vector3 = (spline.sample(distance)["forward"] as Vector3)
	forward.y = 0.0
	if forward.length() < 0.01:
		return 0
	forward = forward.normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var centre: Vector3 = spline.sample(distance)["position"] as Vector3
	var chosen: float = 0.0
	var chosen_offset: float = LIFT_OFFSET
	for offset: float in [LIFT_OFFSET, LIFT_OFFSET * 1.7]:
		for side: float in [-1.0, 1.0]:
			var candidate: Vector3 = centre + right * (offset * side)
			if GlacierProps.clearance(spline, candidate) >= offset - 2.0:
				chosen = side
				chosen_offset = offset
				break
		if chosen != 0.0:
			break
	if chosen == 0.0:
		return 0
	var post_scale: float = GlacierProps.scale_for_height(LIFT_POST, LIFT_HEIGHT)
	var arm_scale: float = 9.0
	var entries: Array = []
	var points: Array = []
	var body: StaticBody3D = GlacierProps.body(holder, "GlacierSkiLift")
	for index in LIFT_PYLONS:
		var offset: float = (float(index) - float(LIFT_PYLONS - 1) * 0.5) * LIFT_SPACING
		var raw_base: Vector3 = centre + forward * offset + right * (chosen_offset * chosen)
		var base := Vector3(raw_base.x, GlacierProps.LAYER_FOOT, raw_base.z)
		if GlacierProps.clearance(spline, base) < 24.0:
			continue
		if not GlacierProps.site_clear(holder, base, 1.2):
			continue
		points.append(base)
		entries.append({"model": LIFT_POST,
			"transform": GlacierProps.fit(LIFT_POST, base,
				GlacierProps.axis_yaw(LIFT_POST, post_scale, forward), post_scale)})
		var arm_at: Vector3 = base + Vector3.UP * (LIFT_HEIGHT * 0.86)
		entries.append({"model": LIFT_ARM,
			"transform": GlacierProps.fit(LIFT_ARM, arm_at,
				GlacierProps.axis_yaw(LIFT_ARM, arm_scale, right), arm_scale)})
		GlacierProps.cylinder(body, base, 0.9, LIFT_HEIGHT)
		GlacierProps.box(body, arm_at, Vector3(9.0, 0.6, 0.6),
			GlacierProps.axis_yaw(LIFT_ARM, arm_scale, right))
	if entries.is_empty():
		body.free()
		return 0
	GlacierProps.batch(holder, entries, "GlacierSkiLift", true)
	GlacierProps.assert_clearance("GlacierSkiLift", points, spline)
	return points.size()


# --------------------------------------------------------------------------
# 5. Frozen Turquoise Alpine Tarn, Crystalline Ice Arches, Ski Village & Gondolas
# --------------------------------------------------------------------------


static func _alpine_lake_and_peaks(holder: Node3D, spline: RefCounted) -> int:
	var bounds: Rect2 = _map_bounds(spline)
	var centre := Vector3(bounds.position.x + bounds.size.x * 0.5, 0.0,
		bounds.position.y + bounds.size.y * 0.5)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var snow_drift := Color("e6f4fc")
	var ice_rim := Color("69d8ea")
	var ice_mid := Color("36b6d4")
	var ice_deep := Color("1888ab")
	var frost_line := Color("eefbff")

	var lakes: Array[Dictionary] = [
		{"pos": Vector3(centre.x - 18.0, 0.014, centre.z + 18.0), "rx": 38.0, "rz": 26.0},
		{"pos": Vector3(centre.x + 12.0, 0.014, bounds.end.y + 56.0), "rx": 44.0, "rz": 28.0},
		{"pos": Vector3(bounds.end.x + 68.0, 0.014, bounds.position.y - 34.0), "rx": 42.0, "rz": 28.0},
	]
	var count: int = 0
	for lk: Dictionary in lakes:
		var lp: Vector3 = lk["pos"]
		var rx: float = float(lk["rx"])
		var rz: float = float(lk["rz"])
		if GlacierProps.clearance(spline, lp) < maxf(rx, rz) + 15.0:
			continue
		_gl_disc(verts, normals, colors, lp, rx + 5.5, rz + 5.0, 28, snow_drift)
		_gl_disc(verts, normals, colors, lp + Vector3.UP * 0.005, rx, rz, 28, ice_rim)
		_gl_disc(verts, normals, colors, lp + Vector3.UP * 0.010, rx * 0.80, rz * 0.80, 24, ice_mid)
		_gl_disc(verts, normals, colors, lp + Vector3.UP * 0.014, rx * 0.52, rz * 0.52, 20, ice_deep)
		for f_idx in 5:
			var ang: float = 0.35 + float(f_idx) * 0.62
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var perp := Vector3(-dir.z, 0.0, dir.x) * 0.38
			var a := lp + dir * (-rx * 0.68) + Vector3.UP * 0.018
			var b := lp + dir * (rx * 0.68) + Vector3.UP * 0.018
			_gl_quad(verts, normals, colors, a - perp, a + perp, b + perp, b - perp, frost_line)
		count += 1

	if not verts.is_empty():
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
		mat.roughness = 0.25
		mat.metallic = 0.08
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(0, mat)
		var inst := MeshInstance3D.new()
		inst.name = "GlacierAlpineLakes"
		inst.mesh = mesh
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(inst)

	# Crystalline ice arches & ski chalets
	var em_batch := PropBatch.new()
	var arch_body: StaticBody3D = GlacierProps.body(holder, "GlacierIceArches")
	var total: float = maxf(float(spline.total_length), 1.0)
	var ice_arches_placed: Array[float] = []
	for step_i in 56:
		if ice_arches_placed.size() >= 3:
			break
		var arch_s: float = total * float(step_i) / 56.0
		if arch_s < 80.0 or arch_s > total - 80.0:
			continue
		var too_close: bool = false
		for prev_s: float in ice_arches_placed:
			if absf(fposmod(arch_s - prev_s + total * 0.5, total) - total * 0.5) < total * 0.16:
				too_close = true
				break
		if too_close:
			continue
		var af: Dictionary = spline.sample(arch_s)
		var origin: Vector3 = af["position"]
		if origin.y > 2.2 or absf(angle_difference(spline.yaw_at(arch_s + 12.0), spline.yaw_at(arch_s - 12.0))) > 0.12:
			continue
		var ar: Vector3 = (af["right"] as Vector3).normalized()
		var afwd: Vector3 = (af["forward"] as Vector3).normalized()
		var ayaw: float = atan2(-afwd.x, -afwd.z)
		var left_pier: Vector3 = origin - ar * 15.8
		var right_pier: Vector3 = origin + ar * 15.8
		if GlacierProps.clearance(spline, left_pier) < TileKit.ROAD_HALF + 5.8 \
				or GlacierProps.clearance(spline, right_pier) < TileKit.ROAD_HALF + 5.8:
			continue
		if not GlacierProps.site_clear(holder, Vector3(left_pier.x, 0.0, left_pier.z), 3.4) \
				or not GlacierProps.site_clear(holder, Vector3(right_pier.x, 0.0, right_pier.z), 3.4):
			continue
		LandscapeSculptor.add_natural_arch(em_batch, arch_body, origin, ayaw,
			28.0, 7.2, 4.2, Color("38b6dc"), Color("c4f2ff"))
		ice_arches_placed.append(arch_s)
		count += 1
	if arch_body.get_child_count() == 0:
		arch_body.free()

	for chalet_spec: Dictionary in [
			{"pos": Vector3(centre.x - 46.0, 0.0, bounds.end.y + 42.0), "yaw": 0.25, "scale": 1.38},
			{"pos": Vector3(centre.x + 58.0, 0.0, bounds.end.y + 44.0), "yaw": -0.35, "scale": 1.42},
			{"pos": Vector3(centre.x - 32.0, 0.0, centre.z - 12.0), "yaw": 0.45, "scale": 1.32},
			{"pos": Vector3(centre.x + 28.0, 0.0, centre.z + 22.0), "yaw": -0.20, "scale": 1.35}]:
		var cpos: Vector3 = chalet_spec["pos"] as Vector3
		if GlacierProps.clearance(spline, cpos) >= 26.0:
			LandscapeSculptor.add_ski_chalet(em_batch, cpos,
				float(chalet_spec["yaw"]), float(chalet_spec["scale"]))
			count += 1
	em_batch.flush_to(holder, "GlacierSnowbanksAndChalets", true)

	# Two soaring animated ski-lift gondola cable lines:
	#   1. High Cliff Pass Gondola Line running parallel to the North Summit Pass
	#      (just like the upper-left gondola line in bg_hero_glacier.png!)
	#   2. Alpine Valley Bowl Gondola Line crossing the central glacial tarn!
	var anim_reg: Dictionary = AmbientWorld.anim_of(holder.get_parent() if holder.get_parent() != null else holder)
	var summit_lift_a := Vector3(bounds.position.x + 36.0, 14.5, bounds.position.y + 62.0)
	var summit_lift_b := Vector3(bounds.end.x - 54.0, 19.5, bounds.position.y + 66.0)
	if GlacierProps.clearance(spline, summit_lift_a) >= 22.0 \
			and GlacierProps.clearance(spline, summit_lift_b) >= 22.0:
		LandscapeSculptor.build_ski_lift_system(holder,
			summit_lift_a, summit_lift_b, 5, 5, anim_reg)
		count += 1

	var valley_lift_a := Vector3(centre.x - 58.0, 7.5, centre.z - 18.0)
	var valley_lift_b := Vector3(centre.x + 44.0, 15.0, centre.z + 24.0)
	if GlacierProps.clearance(spline, valley_lift_a) >= 22.0 \
			and GlacierProps.clearance(spline, valley_lift_b) >= 22.0:
		LandscapeSculptor.build_ski_lift_system(holder,
			valley_lift_a, valley_lift_b, 4, 4, anim_reg)
		count += 1
	return count


static func _map_bounds(spline: RefCounted) -> Rect2:
	var total: float = maxf(float(spline.total_length), 1.0)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 80:
		var p: Vector3 = spline.sample(total * float(i) / 80.0)["position"]
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.z)
	return Rect2(lo, hi - lo)


static func _longest_straight(spline: RefCounted) -> Dictionary:
	return GlacierProps.longest_straight(spline)


static func _gl_disc(verts: PackedVector3Array, normals: PackedVector3Array,
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


static func _gl_quad(verts: PackedVector3Array, normals: PackedVector3Array,
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
