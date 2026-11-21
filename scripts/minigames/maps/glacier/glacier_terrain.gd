extends RefCounted
## Alpine terrain dressing for Glacier Pass: the mountain the road is cut into.
##
## Three passes, all built from the Kenney nature kit so the map stays flat
## cartoon art:
##
##   cliffs    rock faces planted just outside the barrier line wherever the
##             road deck is above the snow. They rise from the ground to the
##             deck, which is what makes an elevated cell read as a road cut
##             into a hillside instead of a slab floating over a white plane.
##   outcrops  boulder clusters further out, on both sides, following the same
##             clearance path as the barriers so they can never creep onto the
##             road. A rock is always based at ground level: no floating.
##   ridges    three rings of big cliff blocks 150-330 m out, which give the
##             chase camera a horizon and hide the edge of the ground plate.
##
## Plus the ski-lift line: six pylons on a straight run in the infield, a post
## and a cross arm each, solid on CollisionLayers.WORLD. Every solid position is
## checked in plan against the racing centreline before it is accepted.

const GlacierProps := preload("res://scripts/minigames/maps/glacier/glacier_props.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const LandscapeSculptor := preload("res://scripts/minigames/scenery/landscape_sculptor.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const AmbientWorld := preload("res://scripts/minigames/scenery/ambient_world.gd")

const TILE: float = TileCatalog.TILE_SIZE
const NATURE: float = TileCatalog.NATURE_SCALE

const CLIFF_LATERAL: float = 25.5
const CLIFF_STEP: float = 9.0
const CLIFF_MIN_DECK: float = 1.6
const MAX_CLIFFS: int = 44
const CLIFF_MODELS: Array[String] = [
	"cliff_large_rock", "cliff_half_rock",
]

const OUTCROP_LATERAL: float = 30.5
const OUTCROP_STEP: float = 19.0
const MAX_OUTCROPS: int = 38
const OUTCROP_MODELS: Array[String] = [
	"rock_largeA", "rock_largeB", "rock_largeD",
]

## Distant ridges: rings of oversized blocks. They are outside the playable
## snowfield, but they still carry a collider so a kart can never clip a ridge.
## Pushed well beyond the first fog band so they read as hazy alpine peaks
## instead of two giant cuboids hanging in the sky behind the circuit.
const RIDGE_RINGS: Array[Dictionary] = [
	{"radius": 248.0, "count": 5, "height": 22.0},
	{"radius": 340.0, "count": 6, "height": 32.0},
	{"radius": 440.0, "count": 7, "height": 46.0},
]
const RIDGE_MODELS: Array[String] = [
	"cliff_large_stone", "cliff_blockSlope_stone", "cliff_block_stone",
	"cliff_top_stone", "cliff_large_rock", "cliff_blockSlope_rock",
	"cliff_block_rock", "cliff_top_rock",
]

## Ski-lift pylons.
const LIFT_PYLONS: int = 6
const LIFT_SPACING: float = 34.0
const LIFT_OFFSET: float = 42.0
const LIFT_HEIGHT: float = 15.0
const LIFT_POST: String = "lightPostModern"
const LIFT_ARM: String = "rail"
const SEED: int = 20261113


## Builds every terrain pass under `holder`. Returns the piece counts and the
## draw estimate.
static func build(holder: Node3D, spline: RefCounted) -> Dictionary:
	var stats: Dictionary = {
		"cliffs": 0, "outcrops": 0, "ridges": 0, "pylons": 0,
		"draws": 0, "objects": 0,
	}
	if holder == null or spline == null:
		return stats
	stats["cliffs"] = _cliffs(holder, spline)
	stats["outcrops"] = _outcrops(holder, spline)
	stats["ridges"] = _ridges(holder, spline)
	stats["pylons"] = _ski_lift(holder, spline)
	var lake_peaks: int = _alpine_lake_and_peaks(holder, spline)
	stats["objects"] = int(stats["cliffs"]) + int(stats["outcrops"]) \
		+ int(stats["ridges"]) + int(stats["pylons"]) + lake_peaks
	stats["draws"] = _draw_estimate(stats) + (1 if lake_peaks > 0 else 0)
	return stats


# --------------------------------------------------------------------------
# cliffs along the road
# --------------------------------------------------------------------------


## Rock faces under a raised deck. Every cliff is a nature block scaled to the
## deck height at that point and based on y = 0, so it meets the ground and the
## road shoulder at once with no gap and no float. The foot is lifted one rung
## off the snow plane and the site is measured against the colliders already in
## the scene, so a face can never be planted through a stand or a fence.
static func _cliffs(holder: Node3D, spline: RefCounted) -> int:
	var entries: Array = []
	var points: Array = []
	var body: StaticBody3D = GlacierProps.body(holder, "GlacierCliffs")
	for side: float in [-1.0, 1.0]:
		var path: Dictionary = GlacierProps.constant_path(spline, side,
			CLIFF_LATERAL)
		if not bool(path.get("ok", false)):
			continue
		var length: float = float(path["total_length"])
		var count: int = int(floor(length / CLIFF_STEP))
		for index in count:
			if entries.size() >= MAX_CLIFFS:
				break
			var at: Vector3 = GlacierProps.path_point(path,
				(float(index) + 0.5) * CLIFF_STEP)
			var deck_height: float = maxf(at.y, 0.0)
			if deck_height < CLIFF_MIN_DECK:
				continue
			var forward: Vector3 = GlacierProps.path_forward(path,
				(float(index) + 0.5) * CLIFF_STEP)
			var model: String = CLIFF_MODELS[index % CLIFF_MODELS.size()]
			# Stack the face so its top lands on the deck: one block for a low
			# shoulder, two for the summit cut.
			var block_height: float = deck_height
			var scale: float = GlacierProps.scale_for_height(model,
				block_height, true)
			scale = clampf(scale, 1.2, 13.5)
			var yaw: float = GlacierProps.axis_yaw(model, scale, forward, true)
			var footprint: Vector2 = GlacierProps.footprint(model, scale, true)
			var width: float = minf(footprint.x * 0.72, 4.8)
			var base := Vector3(at.x, 0.0, at.z) \
				+ Vector3.UP * GlacierProps.LAYER_FOOT
			if GlacierProps.clearance(spline, base) < 17.0:
				continue
			if not GlacierProps.site_clear(holder, base, width * 0.5):
				continue
			entries.append({"model": model, "nature": true,
				"transform": GlacierProps.fit(model, base, yaw, scale, true)})
			points.append(base)
			GlacierProps.box(body, base + Vector3.UP * (block_height * 0.5),
				Vector3(width, block_height, width))
	if entries.is_empty():
		body.free()
		return 0
	GlacierProps.batch(holder, entries, "GlacierCliffs", true)
	GlacierProps.assert_clearance("GlacierCliffs", points, spline)
	return entries.size()


# --------------------------------------------------------------------------
# outcrops
# --------------------------------------------------------------------------


## Boulder fields on both sides of the pass. Grounded one rung above the snow
## plane, batched per model, one box collider each. A boulder is skipped when it
## would be planted through a stand, a garage or a fence that is already in the
## scene: the outcrop band crosses the stand band, and a rock through a
## grandstand is the same class of clip as a stand through a stand.
static func _outcrops(holder: Node3D, spline: RefCounted) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var entries: Array = []
	var points: Array = []
	var body: StaticBody3D = GlacierProps.body(holder, "GlacierOutcrops")
	for side: float in [-1.0, 1.0]:
		var path: Dictionary = GlacierProps.constant_path(spline, side,
			OUTCROP_LATERAL)
		if not bool(path.get("ok", false)):
			continue
		var length: float = float(path["total_length"])
		var count: int = int(floor(length / OUTCROP_STEP))
		for index in count:
			if entries.size() >= MAX_OUTCROPS:
				break
			var at: Vector3 = GlacierProps.path_point(path,
				(float(index) + 0.5) * OUTCROP_STEP)
			var jitter := Vector3(rng.randf_range(-4.0, 4.0), 0.0,
				rng.randf_range(-4.0, 4.0))
			var base := Vector3(at.x + jitter.x, 0.0, at.z + jitter.z) \
				+ Vector3.UP * GlacierProps.LAYER_FOOT
			if GlacierProps.clearance(spline, base) < 21.0:
				continue
			var model: String = OUTCROP_MODELS[rng.randi_range(0,
				OUTCROP_MODELS.size() - 1)]
			var scale: float = NATURE * rng.randf_range(0.75, 1.25)
			var plan: Vector2 = GlacierProps.footprint(model, scale, true)
			if not GlacierProps.site_clear(holder, base,
					maxf(plan.x, plan.y) * 0.5):
				continue
			var yaw: float = rng.randf_range(0.0, TAU)
			entries.append({"model": model, "nature": true,
				"transform": GlacierProps.fit(model, base, yaw, scale, true)})
			points.append(base)
			var height: float = GlacierProps.height(model, scale, true)
			GlacierProps.box(body, base + Vector3.UP * (height * 0.5),
				Vector3(minf(plan.x, 6.0), height, minf(plan.y, 6.0)))
	if entries.is_empty():
		body.free()
		return 0
	GlacierProps.batch(holder, entries, "GlacierOutcrops", true)
	GlacierProps.assert_clearance("GlacierOutcrops", points, spline)
	return entries.size()


# --------------------------------------------------------------------------
# distant ridges
# --------------------------------------------------------------------------


## Three rings of oversized cliff blocks, so every camera angle has a mountain
## horizon behind the pine band.
static func _ridges(holder: Node3D, spline: RefCounted) -> int:
	# 360-degree jagged snow-capped alpine mountain ring around the pass,
	# replacing flat background cuboids.
	var bounds: Rect2 = _map_bounds(spline)
	var centre := Vector3(bounds.position.x + bounds.size.x * 0.5, 0.0,
		bounds.position.y + bounds.size.y * 0.5)
	var span: float = maxf(bounds.size.x, bounds.size.y)
	var batch := PropBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 7
	var alpine_pal: Dictionary = {
		"base": Color("3f6d9e"),
		"rock": Color("4d8fc4"),
		"cliff": Color("6fb6de"),
		"snow_lo": Color("bfe6f7"),
		"snow_hi": Color("e8f8ff"),
	}
	var count: int = 0
	for i in 18:
		var ang: float = TAU * float(i) / 18.0 + 0.08
		var mrad: float = rng.randf_range(40.0, 62.0)
		var rad: float = span * 0.56 + rng.randf_range(48.0, 125.0)
		var pos := Vector3(centre.x + cos(ang) * rad, 0.0, centre.z + sin(ang) * rad)
		# Mountain feet spread ~1.5x base radius: keep the whole mass clear
		# of the road or a peak lands on the track and karts phase through it.
		if GlacierProps.clearance(spline, pos) < mrad * 1.5 + 24.0:
			continue
		LandscapeSculptor.add_alpine_mountain(batch, pos,
			mrad, rng.randf_range(52.0, 102.0), rng, alpine_pal)
		count += 1
	batch.flush_to(holder, "AlpineMountainHorizon", false)
	return count


# --------------------------------------------------------------------------
# ski lift
# --------------------------------------------------------------------------


## Six pylons on a line in the infield, parallel to the longest straight, with a
## cross arm near the top. Trees cover the cable run, so the line reads as lift
## infrastructure without adding a primitive the kit does not ship.
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
	# A lift line needs open ground: try both sides at two offsets, because a
	# pinched figure-of-eight leaves only some of the infield clear.
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
		print("GLACIER SKI LIFT: no clear side for the lift line at %.0f m" % (
			float(straight["distance"])))
		return 0
	var post_scale: float = GlacierProps.scale_for_height(LIFT_POST,
		LIFT_HEIGHT)
	var arm_scale: float = 9.0
	var entries: Array = []
	var points: Array = []
	var body: StaticBody3D = GlacierProps.body(holder, "GlacierSkiLift")
	for index in LIFT_PYLONS:
		var offset: float = (float(index) - float(LIFT_PYLONS - 1) * 0.5) \
			* LIFT_SPACING
		var raw_base: Vector3 = centre + forward * offset \
			+ right * (chosen_offset * chosen)
		var base := Vector3(raw_base.x, GlacierProps.LAYER_FOOT, raw_base.z)
		if GlacierProps.clearance(spline, base) < 24.0:
			continue
		if not GlacierProps.site_clear(holder, base, 1.2):
			continue
		points.append(base)
		entries.append({"model": LIFT_POST,
			"transform": GlacierProps.fit(LIFT_POST, base,
				GlacierProps.axis_yaw(LIFT_POST, post_scale, forward),
				post_scale)})
		var arm_at: Vector3 = base + Vector3.UP * (LIFT_HEIGHT * 0.86)
		entries.append({"model": LIFT_ARM,
			"transform": GlacierProps.fit(LIFT_ARM, arm_at,
				GlacierProps.axis_yaw(LIFT_ARM, arm_scale, right),
				arm_scale)})
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
# helpers
# --------------------------------------------------------------------------


static func _map_bounds(spline: RefCounted) -> Rect2:
	var total: float = maxf(float(spline.total_length), 1.0)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 64:
		var p: Vector3 = spline.sample(total * float(i) / 64.0)["position"]
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.z)
	return Rect2(lo, hi - lo)


## Centre of the lap's plan bounds, used to ring the ridges around the map.
static func _map_centre(spline: RefCounted) -> Vector3:
	var total: float = maxf(float(spline.total_length), 1.0)
	var sum := Vector3.ZERO
	for index in 48:
		var point: Vector3 = spline.sample(total * float(index) / 48.0)["position"]
		sum += Vector3(point.x, 0.0, point.z)
	return sum / 48.0


## Longest straight run of the lap, which is where a lift line fits without
## crossing the road.
static func _longest_straight(spline: RefCounted) -> Dictionary:
	return GlacierProps.longest_straight(spline)


static func _draw_estimate(stats: Dictionary) -> int:
	var draws: int = 0
	if int(stats["cliffs"]) > 0:
		draws += CLIFF_MODELS.size()
	if int(stats["outcrops"]) > 0:
		draws += OUTCROP_MODELS.size()
	if int(stats["ridges"]) > 0:
		draws += RIDGE_MODELS.size()
	if int(stats["pylons"]) > 0:
		draws += 2
	return draws


# --------------------------------------------------------------------------
# frozen turquoise alpine lake vista, snowbanks & snow-capped peaks
# --------------------------------------------------------------------------


static func _alpine_lake_and_peaks(holder: Node3D,
		spline: RefCounted) -> int:
	var bounds: Rect2 = _map_bounds(spline)
	var centre := Vector3(bounds.position.x + bounds.size.x * 0.5, 0.0,
		bounds.position.y + bounds.size.y * 0.5)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var snow_drift := Color("f2f7fc")
	var ice_rim := Color("69d8ea")
	var ice_mid := Color("39b8d4")
	var ice_deep := Color("1f95b5")
	var frost_line := Color("eefbff")

	# Two dynamically placed frozen turquoise alpine lakes
	var lakes: Array[Dictionary] = [
		{"pos": Vector3(centre.x + 12.0, 0.014, bounds.end.y + 52.0), "rx": 34.0, "rz": 22.0},
		{"pos": Vector3(bounds.end.x + 64.0, 0.014, bounds.position.y - 30.0), "rx": 38.0, "rz": 26.0},
	]
	var count: int = 0
	for lk: Dictionary in lakes:
		var lp: Vector3 = lk["pos"]
		var rx: float = float(lk["rx"])
		var rz: float = float(lk["rz"])
		if GlacierProps.clearance(spline, lp) < maxf(rx, rz) + 14.0:
			continue
		_gl_disc(verts, normals, colors, lp, rx + 5.0, rz + 4.5, 26, snow_drift)
		_gl_disc(verts, normals, colors, lp + Vector3.UP * 0.005, rx, rz, 26, ice_rim)
		_gl_disc(verts, normals, colors, lp + Vector3.UP * 0.010, rx * 0.80, rz * 0.80, 24, ice_mid)
		_gl_disc(verts, normals, colors, lp + Vector3.UP * 0.014, rx * 0.52, rz * 0.52, 20, ice_deep)
		for f_idx in 4:
			var ang: float = 0.4 + float(f_idx) * 0.72
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var perp := Vector3(-dir.z, 0.0, dir.x) * 0.35
			var a := lp + dir * (-rx * 0.65) + Vector3.UP * 0.018
			var b := lp + dir * (rx * 0.65) + Vector3.UP * 0.018
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
		mat.roughness = 0.92
		mat.metallic = 0.0
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(0, mat)
		var inst := MeshInstance3D.new()
		inst.name = "GlacierAlpineLakes"
		inst.mesh = mesh
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(inst)

	# Watertight sculpted snow embankments, ice arches over valley straight, & ski chalets
	var em_batch := PropBatch.new()
	LandscapeSculptor.add_road_embankment(em_batch, spline, {
		"road_half": TileKit.ROAD_HALF + 0.6,
		"inner_offset": TileKit.ROAD_HALF + 0.55,
		"outer_offset": TileKit.ROAD_HALF + 16.0,
		"ground_y": 0.0,
		"hill_rise": 1.6,
		"shoulder": Color("d8ecf7"),
		"slope": Color("8fc3e4"),
		"cliff": Color("4a6a8c"),
		"steps": 160,
	})
	var arch_body: StaticBody3D = GlacierProps.body(holder, "GlacierIceArches")
	var total: float = maxf(float(spline.total_length), 1.0)
	var ice_arches_placed: Array[float] = []
	for step_i in 48:
		if ice_arches_placed.size() >= 2:
			break
		var arch_s: float = total * float(step_i) / 48.0
		if arch_s < 80.0 or arch_s > total - 80.0:
			continue
		var too_close: bool = false
		for prev_s: float in ice_arches_placed:
			if absf(fposmod(arch_s - prev_s + total * 0.5, total) - total * 0.5) < total * 0.18:
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
		var left_pier: Vector3 = origin - ar * 15.6
		var right_pier: Vector3 = origin + ar * 15.6
		if GlacierProps.clearance(spline, left_pier) < TileKit.ROAD_HALF + 5.5 \
				or GlacierProps.clearance(spline, right_pier) < TileKit.ROAD_HALF + 5.5:
			continue
		# Piers are 4.2 m wide on 5.6 m foundations: refuse sites where the
		# avalanche fence band (16.4 m) or any solid already stands.
		if not GlacierProps.site_clear(holder, Vector3(left_pier.x, 0.0, left_pier.z), 3.2) \
				or not GlacierProps.site_clear(holder, Vector3(right_pier.x, 0.0, right_pier.z), 3.2):
			continue
		LandscapeSculptor.add_natural_arch(em_batch, arch_body, origin, ayaw,
			27.6, 6.6, 3.8, Color("3fb9d8"), Color("b8ecfa"))
		ice_arches_placed.append(arch_s)
		count += 1
	if arch_body.get_child_count() == 0:
		arch_body.free()

	for chalet_pos: Vector3 in [
			Vector3(centre.x - 42.0, 0.0, bounds.end.y + 38.0),
			Vector3(centre.x + 56.0, 0.0, bounds.end.y + 42.0),
			Vector3(centre.x + 18.0, 0.0, centre.z + 18.0)]:
		if GlacierProps.clearance(spline, chalet_pos) >= 24.0:
			LandscapeSculptor.add_ski_chalet(em_batch, chalet_pos, 0.3, 1.25)
			count += 1
	em_batch.flush_to(holder, "GlacierSnowbanksAndChalets", true)

	# Gliding animated ski-lift gondola cable line spanning the alpine bowl
	var lift_a := Vector3(centre.x - 48.0, 0.0, centre.z - 22.0)
	var lift_b := Vector3(centre.x + 48.0, 0.0, centre.z + 28.0)
	if GlacierProps.clearance(spline, lift_a) >= 22.0 \
			and GlacierProps.clearance(spline, lift_b) >= 22.0:
		LandscapeSculptor.build_ski_lift_system(holder,
			lift_a + Vector3.UP * 8.0, lift_b + Vector3.UP * 14.0,
			4, 4, AmbientWorld.anim_of(holder))
		count += 1
	return count


static func _gl_peak(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, base: Vector3, radius: float, height: float,
		rock_a: Color, rock_b: Color, cap_col: Color) -> void:
	var sides: int = 6
	var apex := base + Vector3(0.0, height, 0.0)
	var snow_split: float = 0.56
	for i in sides:
		var a0: float = TAU * float(i) / float(sides) + 0.2
		var a1: float = TAU * float(i + 1) / float(sides) + 0.2
		var r0: float = radius * (0.88 + 0.16 * float(i % 2))
		var r1: float = radius * (0.88 + 0.16 * float((i + 1) % 2))
		var b0 := base + Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var b1 := base + Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
		var m0 := b0.lerp(apex, snow_split)
		var m1 := b1.lerp(apex, snow_split)
		_gl_quad(verts, normals, colors, b0, b1, m1, m0,
			rock_a if i % 2 == 0 else rock_b)
		var n: Vector3 = (m1 - m0).cross(apex - m0).normalized()
		for pt: Vector3 in [m0, m1, apex]:
			verts.append(pt)
			normals.append(n)
			colors.append(cap_col)


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
