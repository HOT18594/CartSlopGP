extends RefCounted
## Shared procedural 3D stylized low-poly landscape & animated landmark builder.
##
## Produces rich faceted mountains, stratified mesas, natural arches, rolling
## woodland hills, watertight under-road supports/embankments, multi-part
## animated landmarks (Ferris wheels, windmills, waterwheels, cargo ships,
## swinging cranes, rotating lighthouses, moving ski-lift gondolas, blimps),
## and biome GPU particles — all with baked vertex colours (zero photoreal
## textures) and minimal draw calls.

const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")


static func add_tri_outward(batch: PropBatch, a: Vector3, b: Vector3, c: Vector3,
		color: Color, outward: Vector3) -> void:
	## Appends a triangle wound so `(b - a).cross(c - a)` aligns with `outward`.
	## Keeps flat-shaded normals consistent for sunlit vs shadowed faces.
	if (b - a).cross(c - a).dot(outward) < 0.0:
		batch.add_triangle(a, c, b, color)
	else:
		batch.add_triangle(a, b, c, color)


static func add_quad_outward(batch: PropBatch, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, color: Color, outward: Vector3) -> void:
	if (b - a).cross(c - a).dot(outward) < 0.0:
		batch.add_quad(a, d, c, b, color)
	else:
		batch.add_quad(a, b, c, d, color)


## --------------------------------------------------------------------------
## Complex Multi-Peak Mountains, Hills, Mesas, Spires & Arches
## --------------------------------------------------------------------------


static func add_alpine_mountain(batch: PropBatch, center: Vector3,
		base_radius: float, peak_height: float, rng: RandomNumberGenerator,
		palette: Dictionary = {}) -> void:
	## Asymmetric faceted mountain with ridgelines, shoulder spurs and snow cap.
	## Base skirt sinks 4 m below center.y so it never floats on slopes.
	var col_base: Color = palette.get("base", Color("3f6d9e")) as Color
	var col_rock: Color = palette.get("rock", Color("4d8fc4")) as Color
	var col_cliff: Color = palette.get("cliff", Color("6fb6de")) as Color
	var col_snow_lo: Color = palette.get("snow_lo", Color("bfe6f7")) as Color
	var col_snow_hi: Color = palette.get("snow_hi", Color("e8f8ff")) as Color

	var sides: int = rng.randi_range(12, 16)
	var rings: int = 7
	var phase_a: float = rng.randf_range(0.0, TAU)
	var phase_b: float = rng.randf_range(0.0, TAU)
	var phase_c: float = rng.randf_range(0.0, TAU)
	var freq_a: float = float(rng.randi_range(3, 5))
	var freq_b: float = float(rng.randi_range(5, 8))
	var lean := Vector2(rng.randf_range(-0.22, 0.22), rng.randf_range(-0.22, 0.22)) * base_radius
	var ridge_radii: Array[float] = []
	for s in sides:
		var ang: float = TAU * float(s) / float(sides)
		var mod: float = 1.0 + 0.24 * sin(ang * freq_a + phase_a) \
			+ 0.14 * cos(ang * freq_b + phase_b) \
			+ 0.09 * sin(ang * 9.0 + phase_c) \
			+ rng.randf_range(-0.08, 0.08)
		ridge_radii.append(maxf(mod, 0.55))

	var ring_pts: Array = []
	for r_idx in rings:
		var t: float = float(r_idx) / float(rings)
		# Concave cliff profile: steep rock walls low, sharp snowy horn high.
		var y: float = center.y - 4.0 if r_idx == 0 else center.y + peak_height * pow(t, 0.8)
		var rad_scale: float = lerpf(1.18, 0.13, t)
		var pts: Array[Vector3] = []
		for s in sides:
			var ang: float = TAU * float(s) / float(sides)
			var twist: float = ang + t * 0.18 * (1.0 if int(phase_a * 10.0) % 2 == 0 else -1.0)
			var r: float = base_radius * ridge_radii[s] * rad_scale
			var px: float = center.x + cos(twist) * r + lean.x * t
			var pz: float = center.z + sin(twist) * r + lean.y * t
			var py: float = y + (0.0 if r_idx == 0 else sin(ang * 3.0 + phase_a) * peak_height * 0.06 * (1.0 - t))
			pts.append(Vector3(px, py, pz))
		ring_pts.append(pts)

	var summit := Vector3(
		center.x + lean.x * 1.08,
		center.y + peak_height + rng.randf_range(0.5, 3.0),
		center.z + lean.y * 1.08
	)

	for r_idx in rings - 1:
		var lo: Array[Vector3] = ring_pts[r_idx]
		var hi: Array[Vector3] = ring_pts[r_idx + 1]
		var frac: float = float(r_idx) / float(rings - 1)
		for s in sides:
			var sn: int = (s + 1) % sides
			var mid: Vector3 = (lo[s] + lo[sn] + hi[s] + hi[sn]) * 0.25
			var outward: Vector3 = Vector3(mid.x - center.x, 0.45 * base_radius, mid.z - center.z).normalized()
			var shade: Color
			if frac < 0.22:
				# Talus apron at the skirt: pale scree catching the light.
				shade = col_base.lerp(col_snow_lo, 0.30) if s % 2 == 0 else col_rock.lerp(col_snow_lo, 0.22)
			elif frac < 0.42:
				shade = col_base if s % 2 == 0 else col_rock
				# Exposed dark rock ribs run down the cliff faces.
				if (s * 5 + r_idx) % 7 == 0:
					shade = shade.darkened(0.22)
			elif frac < 0.66:
				shade = col_rock if (s + r_idx) % 2 == 0 else col_cliff
				if (s * 3 + r_idx * 2) % 9 == 0:
					shade = shade.darkened(0.16)
			elif frac < 0.84:
				shade = col_cliff.lerp(col_snow_lo, 0.65)
			else:
				# Bright wind cornice lip just under the summit cap.
				shade = col_snow_hi.lightened(0.06)
			if (s + r_idx) % 3 == 0 and frac < 0.84:
				shade = shade.darkened(0.06)
			add_quad_outward(batch, lo[s], hi[s], hi[sn], lo[sn], shade, outward)

	var top_ring: Array[Vector3] = ring_pts[rings - 1]
	for s in sides:
		var sn: int = (s + 1) % sides
		var mid: Vector3 = (top_ring[s] + top_ring[sn] + summit) / 3.0
		var outward := Vector3(mid.x - center.x, 0.5 * base_radius, mid.z - center.z).normalized()
		add_tri_outward(batch, top_ring[s], summit, top_ring[sn],
			col_snow_hi if s % 2 == 0 else col_snow_lo, outward)

	# Secondary shoulder peak / buttress to eliminate isolated cone silhouettes.
	if base_radius >= 16.0:
		var sub_ang: float = phase_a + 1.2
		var sub_dist: float = base_radius * rng.randf_range(0.45, 0.65)
		var sub_pos := Vector3(
			center.x + cos(sub_ang) * sub_dist,
			center.y,
			center.z + sin(sub_ang) * sub_dist
		)
		_add_shoulder_spur(batch, sub_pos, base_radius * rng.randf_range(0.42, 0.56),
			peak_height * rng.randf_range(0.45, 0.65), rng, col_base, col_rock, col_snow_lo)
	# Tertiary needle horn on big ranges so skylines stay jagged, never smooth.
	if base_radius >= 38.0:
		var horn_ang: float = phase_b + 2.6
		var horn_dist: float = base_radius * rng.randf_range(0.55, 0.8)
		var horn_pos := Vector3(
			center.x + cos(horn_ang) * horn_dist,
			center.y,
			center.z + sin(horn_ang) * horn_dist
		)
		_add_shoulder_spur(batch, horn_pos, base_radius * rng.randf_range(0.24, 0.34),
			peak_height * rng.randf_range(0.55, 0.8), rng, col_rock, col_cliff, col_snow_hi)


static func _add_shoulder_spur(batch: PropBatch, center: Vector3, radius: float,
		height: float, rng: RandomNumberGenerator, col_a: Color, col_b: Color,
		col_cap: Color) -> void:
	var sides: int = 9
	var base_pts: Array[Vector3] = []
	var mid_pts: Array[Vector3] = []
	var phase: float = rng.randf_range(0.0, TAU)
	for s in sides:
		var ang: float = TAU * float(s) / float(sides)
		var r: float = radius * (1.0 + 0.22 * sin(ang * 3.0 + phase) + 0.1 * sin(ang * 6.0 + phase * 1.7))
		base_pts.append(Vector3(center.x + cos(ang) * r, center.y - 4.0, center.z + sin(ang) * r))
		mid_pts.append(Vector3(center.x + cos(ang) * r * 0.52, center.y + height * 0.58,
			center.z + sin(ang) * r * 0.52))
	var tip := Vector3(center.x + cos(phase) * radius * 0.12, center.y + height,
		center.z + sin(phase) * radius * 0.12)
	for s in sides:
		var sn: int = (s + 1) % sides
		var out_v := Vector3(base_pts[s].x - center.x, radius * 0.35, base_pts[s].z - center.z).normalized()
		add_quad_outward(batch, base_pts[s], mid_pts[s], mid_pts[sn], base_pts[sn],
			col_a if s % 2 == 0 else col_b, out_v)
		add_tri_outward(batch, mid_pts[s], tip, mid_pts[sn],
			col_cap if s % 2 == 0 else col_b.lerp(col_cap, 0.65), out_v)


static func add_volcanic_peak(batch: PropBatch, center: Vector3,
		base_radius: float, peak_height: float, rng: RandomNumberGenerator) -> void:
	## Jagged basalt volcanic cone with glowing magma caldera rim.
	var col_basalt_dark := Color("27212a")
	var col_basalt := Color("3b3340")
	var col_scorch := Color("59322b")
	var col_lava := Color("ff6b2b")
	var sides: int = rng.randi_range(9, 12)
	var phase: float = rng.randf_range(0.0, TAU)
	var base_pts: Array[Vector3] = []
	var mid_pts: Array[Vector3] = []
	var rim_pts: Array[Vector3] = []
	for s in sides:
		var ang: float = TAU * float(s) / float(sides)
		var jag: float = 1.0 + 0.25 * sin(ang * 4.0 + phase) + rng.randf_range(-0.1, 0.1)
		var r0: float = base_radius * jag
		var r1: float = base_radius * 0.58 * jag
		var r2: float = base_radius * 0.26 * (0.9 + 0.2 * cos(ang * 3.0))
		base_pts.append(Vector3(center.x + cos(ang) * r0, center.y - 4.0, center.z + sin(ang) * r0))
		mid_pts.append(Vector3(center.x + cos(ang) * r1, center.y + peak_height * 0.55, center.z + sin(ang) * r1))
		rim_pts.append(Vector3(center.x + cos(ang) * r2, center.y + peak_height * (0.95 + 0.08 * sin(ang * 5.0)),
			center.z + sin(ang) * r2))
	var crater := Vector3(center.x, center.y + peak_height * 0.80, center.z)
	for s in sides:
		var sn: int = (s + 1) % sides
		var out_v := Vector3(base_pts[s].x - center.x, base_radius * 0.4, base_pts[s].z - center.z).normalized()
		add_quad_outward(batch, base_pts[s], mid_pts[s], mid_pts[sn], base_pts[sn],
			col_basalt_dark if s % 2 == 0 else col_basalt, out_v)
		add_quad_outward(batch, mid_pts[s], rim_pts[s], rim_pts[sn], mid_pts[sn],
			col_scorch if s % 3 == 0 else col_basalt, out_v)
		add_tri_outward(batch, rim_pts[s], crater, rim_pts[sn],
			col_lava if s % 2 == 0 else Color("ff9e38"), Vector3.UP)


static func add_woodland_hill(batch: PropBatch, center: Vector3,
		radius_x: float, radius_z: float, height: float, rng: RandomNumberGenerator,
		palette: Dictionary = {}) -> void:
	## Sculpted multi-tiered rolling hillside (never spherical bubbles or cones).
	## Four terraced tiers, sunlit meadow patches and a granite summit tor.
	var col_skirt: Color = palette.get("skirt", Color("4d8c39")) as Color
	var col_mid: Color = palette.get("mid", Color("63ad44")) as Color
	var col_top: Color = palette.get("top", Color("7ac254")) as Color
	var col_tor: Color = palette.get("tor", Color("8d8f96")) as Color
	var sides: int = rng.randi_range(10, 14)
	var phase: float = rng.randf_range(0.0, TAU)
	var r0_pts: Array[Vector3] = []
	var r1_pts: Array[Vector3] = []
	var r2_pts: Array[Vector3] = []
	var r3_pts: Array[Vector3] = []
	for s in sides:
		var ang: float = TAU * float(s) / float(sides)
		var wobble: float = 1.0 + 0.22 * sin(ang * 3.0 + phase) + 0.12 * cos(ang * 5.0 - phase) + 0.07 * sin(ang * 8.0 + phase * 2.0)
		var cx: float = cos(ang) * radius_x * wobble
		var cz: float = sin(ang) * radius_z * wobble
		r0_pts.append(Vector3(center.x + cx * 1.05, center.y - 3.5, center.z + cz * 1.05))
		r1_pts.append(Vector3(center.x + cx * 0.72, center.y + height * 0.42, center.z + cz * 0.72))
		r2_pts.append(Vector3(center.x + cx * 0.46, center.y + height * 0.74, center.z + cz * 0.46))
		r3_pts.append(Vector3(center.x + cx * 0.24, center.y + height * 0.94, center.z + cz * 0.24))
	var crown := Vector3(center.x, center.y + height, center.z)
	for s in sides:
		var sn: int = (s + 1) % sides
		var sunny: bool = sin(float(s) * 2.4 + phase) > 0.35
		var out_v := Vector3(r0_pts[s].x - center.x, maxf(radius_x, radius_z) * 0.45, r0_pts[s].z - center.z).normalized()
		add_quad_outward(batch, r0_pts[s], r1_pts[s], r1_pts[sn], r0_pts[sn],
			(col_skirt.lightened(0.07) if sunny else col_skirt) if s % 2 == 0 else col_skirt.lightened(0.05), out_v)
		add_quad_outward(batch, r1_pts[s], r2_pts[s], r2_pts[sn], r1_pts[sn],
			(col_mid.lightened(0.08) if sunny else col_mid) if s % 2 == 0 else col_mid.darkened(0.04), out_v)
		add_quad_outward(batch, r2_pts[s], r3_pts[s], r3_pts[sn], r2_pts[sn],
			col_top.lightened(0.05) if s % 2 == 0 else col_top.darkened(0.03), out_v)
		add_tri_outward(batch, r3_pts[s], crown, r3_pts[sn], col_top.lightened(0.10), Vector3.UP)
	# Granite summit tor: a jagged little rock cluster on the crown.
	if height >= 14.0:
		var tor_pts: Array[Vector3] = []
		for ts in 5:
			var tang: float = TAU * float(ts) / 5.0 + phase
			tor_pts.append(crown + Vector3(cos(tang) * 1.6, 0.0, sin(tang) * 1.6))
		var tor_tip := crown + Vector3(0.0, 2.6, 0.0)
		for ts in 5:
			var tn: int = (ts + 1) % 5
			var tout := Vector3(tor_pts[ts].x - crown.x, 1.2, tor_pts[ts].z - crown.z).normalized()
			add_tri_outward(batch, tor_pts[ts], tor_tip, tor_pts[tn],
				col_tor if ts % 2 == 0 else col_tor.darkened(0.12), tout)


static func add_stratified_mesa(batch: PropBatch, center: Vector3,
		radius: float, height: float, tiers: int, rng: RandomNumberGenerator,
		palette: Dictionary = {}) -> void:
	## Irregular polygonal desert mesa with sedimentary strata bands & talus skirt.
	## Accepts both the canonical talus/band_a/band_b/cap keys and the
	## base/mid/top/band/cap aliases every map theme historically passed, so
	## no caller palette silently falls back to defaults.
	var col_talus: Color = palette.get("talus",
		palette.get("base", Color("b85432"))) as Color
	var col_band_a: Color = palette.get("band_a",
		palette.get("band", palette.get("base", Color("9c3c24")))) as Color
	var col_band_b: Color = palette.get("band_b",
		palette.get("mid", palette.get("band", Color("d46a3b")))) as Color
	var col_cap: Color = palette.get("cap",
		palette.get("top", Color("e3874c"))) as Color

	var sides: int = rng.randi_range(8, 11)
	var phase: float = rng.randf_range(0.0, TAU)
	var shape_mod: Array[float] = []
	for s in sides:
		var ang: float = TAU * float(s) / float(sides)
		var mod: float = 1.0 + 0.24 * sin(ang * 3.0 + phase) + rng.randf_range(-0.12, 0.12)
		shape_mod.append(maxf(mod, 0.52))

	var step_count: int = maxi(tiers, 2)
	var prev_ring: Array[Vector3] = []
	for s in sides:
		var ang: float = TAU * float(s) / float(sides)
		var r: float = radius * shape_mod[s] * 1.18
		prev_ring.append(Vector3(center.x + cos(ang) * r, center.y - 4.0, center.z + sin(ang) * r))

	for t_idx in step_count:
		var f0: float = float(t_idx) / float(step_count)
		var f1: float = float(t_idx + 1) / float(step_count)
		var r_lo: float = lerpf(1.0, 0.56, f0)
		var r_hi: float = lerpf(0.86, 0.48, f1)
		var y_lo: float = center.y + height * (f0 * 0.85 if t_idx > 0 else 0.0)
		var y_hi: float = center.y + height * f1
		var mid_ring: Array[Vector3] = []
		var top_ring: Array[Vector3] = []
		for s in sides:
			var ang: float = TAU * float(s) / float(sides)
			var m_r: float = radius * shape_mod[s] * r_lo
			var t_r: float = radius * shape_mod[s] * r_hi
			mid_ring.append(Vector3(center.x + cos(ang) * m_r, y_lo + (height / float(step_count)) * 0.25,
				center.z + sin(ang) * m_r))
			top_ring.append(Vector3(center.x + cos(ang) * t_r, y_hi, center.z + sin(ang) * t_r))
		var wall_col: Color = col_band_a if t_idx % 2 == 0 else col_band_b
		for s in sides:
			var sn: int = (s + 1) % sides
			var out_v := Vector3(mid_ring[s].x - center.x, radius * 0.25, mid_ring[s].z - center.z).normalized()
			add_quad_outward(batch, prev_ring[s], mid_ring[s], mid_ring[sn], prev_ring[sn],
				col_talus if t_idx == 0 else wall_col.darkened(0.08), out_v)
			# Desert varnish: dark vertical streaks weather a few wall facets.
			var face_col: Color = wall_col
			if (s * 3 + t_idx * 5) % 11 == 0:
				face_col = wall_col.darkened(0.28)
			elif (s + t_idx) % 4 == 0:
				face_col = wall_col.lightened(0.08)
			add_quad_outward(batch, mid_ring[s], top_ring[s], top_ring[sn], mid_ring[sn],
				face_col, out_v)
		prev_ring = top_ring

	# Caprock lip: a flared overhang ring under the cap so the rim casts a
	# hard shadow line instead of melting into the walls.
	var lip_ring: Array[Vector3] = []
	for s in sides:
		var ang: float = TAU * float(s) / float(sides)
		var r: float = radius * shape_mod[s] * 0.52
		lip_ring.append(Vector3(center.x + cos(ang) * r, center.y + height - 0.6, center.z + sin(ang) * r))
	for s in sides:
		var sn: int = (s + 1) % sides
		var out_v := Vector3(lip_ring[s].x - center.x, radius * 0.2, lip_ring[s].z - center.z).normalized()
		add_quad_outward(batch, lip_ring[s], prev_ring[s], prev_ring[sn], lip_ring[sn],
			col_band_a.darkened(0.30), out_v)

	var cap_center := Vector3(center.x, center.y + height + 0.15, center.z)
	for s in sides:
		var sn: int = (s + 1) % sides
		add_tri_outward(batch, prev_ring[s], cap_center, prev_ring[sn], col_cap, Vector3.UP)
	# Pale caprock speckle: sunlit flecks across the summit.
	if sides >= 8:
		for s in range(0, sides, 3):
			var sn: int = (s + 1) % sides
			var speck_mid: Vector3 = (prev_ring[s] + prev_ring[sn] + cap_center) / 3.0
			add_tri_outward(batch, prev_ring[s], speck_mid, prev_ring[sn],
				col_cap.lightened(0.14), Vector3.UP)

	# Fallen talus boulders ringing the base (same batch, no colliders: the
	# mesa body itself is already clearance-gated far from the road).
	var talus_n: int = 9
	for b in talus_n:
		var bang: float = TAU * float(b) / float(talus_n) + phase * 0.5
		var br: float = radius * (1.02 + 0.18 * sin(float(b) * 2.7 + phase))
		var bpos := Vector3(center.x + cos(bang) * br, center.y + 0.4, center.z + sin(bang) * br)
		var bs: float = radius * rng.randf_range(0.05, 0.10) + 0.7
		var brot := Basis(Vector3.UP, bang + rng.randf_range(-0.4, 0.4))
		batch.add_box(Transform3D(brot, bpos),
			Vector3(bs * 1.4, bs, bs * 1.1),
			col_talus.darkened(0.05) if b % 2 == 0 else col_band_a.darkened(0.10))


static func add_canyon_spire(batch: PropBatch, center: Vector3,
		radius: float, height: float, rng: RandomNumberGenerator) -> void:
	## Sculpted multi-band hoodoo / canyon pinnacle with wide talus base,
	## mushroom caprock and a balanced summit boulder.
	var colors: Array[Color] = [
		Color("a84426"), Color("cc6136"), Color("943821"), Color("df7f47"),
	]
	var sides: int = 9
	var phase: float = rng.randf_range(0.0, TAU)
	var levels: Array[Dictionary] = [
		{"y": -3.5, "r": 1.30},
		{"y": height * 0.25, "r": 0.78},
		{"y": height * 0.52, "r": 0.60},
		{"y": height * 0.72, "r": 0.42},
		{"y": height * 0.88, "r": 0.55},
		{"y": height * 0.99, "r": 0.34},
	]
	var rings: Array = []
	for lvl: Dictionary in levels:
		var pts: Array[Vector3] = []
		var r_mul: float = float(lvl["r"])
		var y: float = center.y + float(lvl["y"])
		for s in sides:
			var ang: float = TAU * float(s) / float(sides)
			var r: float = radius * r_mul * (1.0 + 0.2 * sin(ang * 3.0 + phase) + 0.08 * sin(ang * 7.0 - phase))
			pts.append(Vector3(center.x + cos(ang) * r, y, center.z + sin(ang) * r))
		rings.append(pts)
	for i in rings.size() - 1:
		var lo: Array[Vector3] = rings[i]
		var hi: Array[Vector3] = rings[i + 1]
		var col: Color = colors[i % colors.size()]
		for s in sides:
			var sn: int = (s + 1) % sides
			var out_v := Vector3(lo[s].x - center.x, radius * 0.2, lo[s].z - center.z).normalized()
			var band_col: Color = col.darkened(0.18) if (s + i) % 5 == 0 else col
			add_quad_outward(batch, lo[s], hi[s], hi[sn], lo[sn], band_col, out_v)
	var top_ring: Array[Vector3] = rings[rings.size() - 1]
	var cap := Vector3(center.x, center.y + height, center.z)
	for s in sides:
		var sn: int = (s + 1) % sides
		add_tri_outward(batch, top_ring[s], cap, top_ring[sn], Color("e68f54"), Vector3.UP)
	# Balanced summit boulder perched on the cap.
	var brock := Vector3(center.x + cos(phase) * radius * 0.08, center.y + height + 1.1, center.z + sin(phase) * radius * 0.08)
	var br: float = radius * 0.16 + 0.8
	var brot := Basis(Vector3.UP, phase * 1.3)
	batch.add_box(Transform3D(brot, brock), Vector3(br * 1.5, br * 1.2, br * 1.2), Color("943821"))
	batch.add_box(Transform3D(brot * Basis(Vector3.RIGHT, 0.35), brock + Vector3(0.0, br * 0.75, 0.0)),
		Vector3(br * 1.1, br * 0.8, br * 0.9), Color("cc6136"))


static func add_natural_arch(batch: PropBatch, body: StaticBody3D,
		center: Vector3, yaw: float, span_width: float, clear_height: float,
		depth: float, col_a: Color, col_b: Color) -> void:
	## Sculpted multi-segment sandstone/ice arch over a road with solid piers.
	var basis := Basis(Vector3.UP, yaw)
	var xform := Transform3D(basis, center)
	var segments: int = 9
	var half_span: float = span_width * 0.5
	var arch_thick: float = maxf(depth * 0.55, 2.2)

	# Flared foundation piers well outside the lane, with angled wing fins
	# bracing each pier against the hillside.
	for side: float in [-1.0, 1.0]:
		var pier_x: float = side * (half_span + 1.8)
		var pier_h: float = clear_height * 0.72
		batch.add_box(xform * Transform3D(Basis.IDENTITY, Vector3(pier_x, pier_h * 0.5 - 2.0, 0.0)),
			Vector3(4.2, pier_h + 4.0, depth * 1.25), col_a)
		batch.add_box(xform * Transform3D(Basis.IDENTITY, Vector3(pier_x * 1.05, 0.4, 0.0)),
			Vector3(5.6, 3.2, depth * 1.5), col_b)
		batch.add_box(xform * Transform3D(Basis(Vector3.BACK, side * 0.5),
			Vector3(pier_x + side * 2.6, 1.1, 0.0)),
			Vector3(1.4, 4.6, depth * 1.1), col_a.darkened(0.12))
		if body != null:
			var shape := BoxShape3D.new()
			shape.size = Vector3(4.2, pier_h + 4.0, depth * 1.25)
			var col := CollisionShape3D.new()
			col.shape = shape
			col.transform = xform * Transform3D(Basis.IDENTITY, Vector3(pier_x, pier_h * 0.5 - 2.0, 0.0))
			body.add_child(col)

	var mid_seg: int = segments / 2
	for i in segments:
		var f0: float = float(i) / float(segments)
		var f1: float = float(i + 1) / float(segments)
		var a0: float = PI * f0
		var a1: float = PI * f1
		var mid_a: float = (a0 + a1) * 0.5
		var p0 := Vector3(-cos(a0) * half_span, clear_height * 0.48 + sin(a0) * clear_height * 0.58, 0.0)
		var p1 := Vector3(-cos(a1) * half_span, clear_height * 0.48 + sin(a1) * clear_height * 0.58, 0.0)
		var seg_mid: Vector3 = (p0 + p1) * 0.5
		var seg_dir: Vector3 = (p1 - p0)
		var seg_len: float = seg_dir.length() + 0.65
		var seg_ang: float = atan2(seg_dir.y, seg_dir.x)
		var seg_xf := xform * Transform3D(Basis(Vector3.BACK, seg_ang), seg_mid)
		var thick: float = arch_thick * (1.28 - 0.35 * sin(mid_a))
		var seg_col: Color = col_a if i % 2 == 0 else col_b
		if i == mid_seg:
			# Oversized keystone locking the crown.
			thick *= 1.45
			seg_len += 0.9
			seg_col = col_b.lightened(0.10)
		elif i % 3 == 2:
			seg_col = seg_col.darkened(0.14)
		batch.add_box(seg_xf, Vector3(seg_len, thick, depth * (1.15 - 0.2 * sin(mid_a))),
			seg_col)


## --------------------------------------------------------------------------
## Continuous Track Terrain Shoulders & Elevated Bridge/Cliff Under-Supports
## --------------------------------------------------------------------------


static func add_road_embankment(batch: PropBatch, spline: RefCounted,
		opts: Dictionary = {}) -> void:
	## Builds seamless, watertight terrain shoulders hugging the road verge and
	## sloping down/up into the surrounding world, plus solid sloped cliff/wall
	## supports under every elevated section so no deck ever floats in mid-air.
	if batch == null or spline == null:
		return
	var road_half: float = float(opts.get("road_half", 7.6))
	var inner_off: float = float(opts.get("inner_offset", road_half + 1.6))
	var outer_off: float = float(opts.get("outer_offset", road_half + 18.0))
	var shoulder_col: Color = opts.get("shoulder", Color("5f9e44")) as Color
	var slope_col: Color = opts.get("slope", Color("4e8839")) as Color
	var cliff_col: Color = opts.get("cliff", Color("665c52")) as Color
	var ground_y: float = float(opts.get("ground_y", -0.04))
	var hill_amp: float = float(opts.get("hill_rise", 1.8))
	var steps: int = int(opts.get("steps", 120))
	var skip_pos: Vector3 = opts.get("skip_center", Vector3(1e9, 0.0, 1e9)) as Vector3
	var skip_r: float = float(opts.get("skip_radius", 0.0))
	var total: float = maxf(float(spline.total_length), 1.0)

	# Sample track centreline points to check self-proximity (avoid extending an
	# embankment into a neighboring strand on tight chicanes/overpasses).
	var samples: Array[Dictionary] = []
	for i in steps:
		var s: float = total * float(i) / float(steps)
		samples.append(spline.sample(s))

	for i in steps:
		var f0: Dictionary = samples[i]
		var f1: Dictionary = samples[(i + 1) % steps]
		var p0: Vector3 = f0["position"]
		var p1: Vector3 = f1["position"]
		if skip_r > 0.0 and Vector2(p0.x - skip_pos.x, p0.z - skip_pos.z).length() < skip_r:
			continue
		var r0: Vector3 = f0["right"]
		r0.y = 0.0
		r0 = r0.normalized()
		var r1: Vector3 = f1["right"]
		r1.y = 0.0
		r1 = r1.normalized()
		var s0: float = total * float(i) / float(steps)

		for side: float in [-1.0, 1.0]:
			var deck_y0: float = p0.y
			var deck_y1: float = p1.y
			var min_deck: float = minf(deck_y0, deck_y1)
			var in0 := Vector3(p0.x + r0.x * side * inner_off, deck_y0 - 0.14, p0.z + r0.z * side * inner_off)
			var in1 := Vector3(p1.x + r1.x * side * inner_off, deck_y1 - 0.14, p1.z + r1.z * side * inner_off)

			# Shrink outer reach if another road strand runs close nearby.
			var reach: float = outer_off
			var mid_probe: Vector3 = (p0 + p1) * 0.5 + (r0 + r1).normalized() * side * (outer_off * 0.65)
			var min_other_dist: float = INF
			for j in steps:
				if absf(float(j - i)) <= 4 or absf(float(j - i)) >= steps - 4:
					continue
				var op: Vector3 = samples[j]["position"]
				var d: float = Vector2(mid_probe.x - op.x, mid_probe.z - op.z).length()
				if d < min_other_dist:
					min_other_dist = d
			if min_other_dist < road_half + 10.0:
				reach = minf(reach, inner_off + 2.8)

			var hill0: float = 0.0
			var hill1: float = 0.0
			if min_deck < 1.2 and reach > inner_off + 4.0:
				hill0 = maxf(0.0, sin(s0 * 0.032 + side * 1.1) * hill_amp)
				hill1 = maxf(0.0, sin((s0 + total / float(steps)) * 0.032 + side * 1.1) * hill_amp)

			var out_y0: float = ground_y - 0.4 + hill0
			var out_y1: float = ground_y - 0.4 + hill1
			var out0 := Vector3(p0.x + r0.x * side * reach, out_y0, p0.z + r0.z * side * reach)
			var out1 := Vector3(p1.x + r1.x * side * reach, out_y1, p1.z + r1.z * side * reach)

			var mid_in0 := Vector3(p0.x + r0.x * side * (inner_off + 2.2), deck_y0 - 0.25,
				p0.z + r0.z * side * (inner_off + 2.2))
			var mid_in1 := Vector3(p1.x + r1.x * side * (inner_off + 2.2), deck_y1 - 0.25,
				p1.z + r1.z * side * (inner_off + 2.2))

			add_quad_outward(batch, in0, in1, mid_in1, mid_in0, shoulder_col, Vector3.UP)
			var outward_n := ((r0 + r1).normalized() * side + Vector3.UP * 0.65).normalized()
			var face_col: Color = cliff_col if min_deck >= 1.6 else slope_col
			if i % 2 == 1:
				face_col = face_col.darkened(0.04)
			add_quad_outward(batch, mid_in0, mid_in1, out1, out0, face_col, outward_n)

		# Solid central bridge pier wall / support column on tall viaducts so
		# undersides look engineered when driving nearby or below.
		if minf(p0.y, p1.y) >= 2.2 and i % 3 == 0:
			var pier_h: float = p0.y - ground_y
			var fw: Vector3 = f0["forward"]
			fw.y = 0.0
			fw = fw.normalized()
			var yaw: float = atan2(-fw.x, -fw.z)
			var pier_xf := Transform3D(Basis(Vector3.UP, yaw),
				Vector3(p0.x, ground_y + pier_h * 0.5 - 0.4, p0.z))
			batch.add_box(pier_xf, Vector3(road_half * 1.45, pier_h + 0.6, 2.8), cliff_col.darkened(0.1))


## --------------------------------------------------------------------------
## Detailed Animated Landmarks
## --------------------------------------------------------------------------


static func build_ferris_wheel(parent: Node3D, pos: Vector3, yaw: float,
		radius: float, anim: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "FerrisWheel"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var static_batch := PropBatch.new()
	var steel := Color("e2455a")
	var hub_col := Color("1e1b3a")
	var hub_y: float = radius + 4.5
	# Twin A-frame support legs.
	for side_z: float in [-2.6, 2.6]:
		for leg_dir: float in [-1.0, 1.0]:
			var foot := Vector3(leg_dir * radius * 0.55, -2.0, side_z)
			var top := Vector3(0.0, hub_y, side_z)
			var mid: Vector3 = (foot + top) * 0.5
			var vec: Vector3 = top - foot
			var ang: float = atan2(vec.x, vec.y)
			static_batch.add_box(Transform3D(Basis(Vector3.BACK, ang), mid),
				Vector3(1.1, vec.length(), 1.1), steel)
	static_batch.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5),
		Vector3(0.0, hub_y, 0.0)), 1.6, 6.8, 12, hub_col)

	var base_mesh := MeshInstance3D.new()
	base_mesh.mesh = static_batch.build()
	base_mesh.material_override = SceneryKit.vertex_material()
	root.add_child(base_mesh)

	var wheel_pivot := Node3D.new()
	wheel_pivot.name = "WheelRotor"
	wheel_pivot.position = Vector3(0.0, hub_y, 0.0)
	root.add_child(wheel_pivot)

	var wheel_batch := PropBatch.new()
	var spoke_count: int = 12
	var gondola_colors: Array[Color] = [
		Color("ff595e"), Color("ffd22e"), Color("38d6f0"),
		Color("71c847"), Color("f26ca7"), Color("ff9f45"),
	]
	for i in spoke_count:
		var a0: float = TAU * float(i) / float(spoke_count)
		var a1: float = TAU * float(i + 1) / float(spoke_count)
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
		for rz: float in [-1.4, 1.4]:
			wheel_batch.add_box(Transform3D(Basis(Vector3.BACK, a0 - PI * 0.5),
				Vector3(p0.x * 0.5, p0.y * 0.5, rz)),
				Vector3(0.32, radius, 0.32), steel)
			var rim_mid: Vector3 = (p0 + p1) * 0.5 + Vector3(0.0, 0.0, rz)
			var rim_dir: Vector3 = p1 - p0
			wheel_batch.add_box(Transform3D(Basis(Vector3.BACK, atan2(rim_dir.y, rim_dir.x)),
				rim_mid), Vector3(rim_dir.length() + 0.3, 0.55, 0.55), Color("ffd22e"))
		var g_col: Color = gondola_colors[i % gondola_colors.size()]
		wheel_batch.add_box(Transform3D(Basis.IDENTITY, p0), Vector3(2.1, 2.3, 2.8), g_col)
		wheel_batch.add_box(Transform3D(Basis.IDENTITY, p0 + Vector3(0.0, 1.25, 0.0)),
			Vector3(2.3, 0.35, 3.0), Color("fff6e3"))

	var wheel_mesh := MeshInstance3D.new()
	wheel_mesh.mesh = wheel_batch.build()
	wheel_mesh.material_override = SceneryKit.vertex_material()
	wheel_pivot.add_child(wheel_mesh)

	if not anim.has("spinners_z"):
		anim["spinners_z"] = []
	(anim["spinners_z"] as Array).append({"node": wheel_pivot, "speed": 0.22})
	return root


static func build_windmill(parent: Node3D, pos: Vector3, yaw: float,
		scale_val: float, style: String, anim: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Windmill"
	root.position = pos
	root.rotation.y = yaw
	root.scale = Vector3.ONE * scale_val
	parent.add_child(root)

	var body_batch := PropBatch.new()
	var wall_col: Color = Color("f2e6cf") if style == "meadow" else Color("d99159")
	var roof_col: Color = Color("d94a44") if style == "meadow" else Color("8a3e25")
	body_batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 4.0, 0.0)),
		2.2, 10.0, 8, wall_col)
	body_batch.add_cone(Transform3D(Basis.IDENTITY, Vector3(0.0, 10.5, 0.0)),
		2.65, 3.2, 8, roof_col)
	body_batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.6, 2.0)),
		Vector3(1.2, 2.6, 0.4), Color("6b442a"))
	body_batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 5.4, 2.05)),
		Vector3(0.9, 1.1, 0.25), Color("ffdf7a"))
	var tower := MeshInstance3D.new()
	tower.mesh = body_batch.build()
	tower.material_override = SceneryKit.vertex_material()
	root.add_child(tower)

	var rotor := Node3D.new()
	rotor.position = Vector3(0.0, 8.2, 2.45)
	root.add_child(rotor)
	var blade_batch := PropBatch.new()
	blade_batch.add_cylinder(Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO),
		0.52, 0.9, 8, Color("3c3747"))
	for i in 4:
		var ang: float = float(i) * PI * 0.5
		var bxform := Transform3D(Basis(Vector3.BACK, ang),
			Vector3(-sin(ang), cos(ang), 0.0) * 3.1)
		blade_batch.add_box(bxform, Vector3(0.24, 5.8, 0.16), Color("6b442a"))
		blade_batch.add_box(bxform * Transform3D(Basis.IDENTITY, Vector3(0.55, 0.4, 0.06)),
			Vector3(1.05, 4.6, 0.08), Color("fff6e3") if i % 2 == 0 else Color("f7d463"))
	var blade_mesh := MeshInstance3D.new()
	blade_mesh.mesh = blade_batch.build()
	blade_mesh.material_override = SceneryKit.vertex_material()
	rotor.add_child(blade_mesh)

	if not anim.has("spinners_z"):
		anim["spinners_z"] = []
	(anim["spinners_z"] as Array).append({"node": rotor, "speed": 0.72})
	return root


static func build_waterwheel(parent: Node3D, pos: Vector3, yaw: float,
		radius: float, anim: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Waterwheel"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var frame := PropBatch.new()
	frame.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, radius * 0.5, -1.8)),
		Vector3(radius * 1.4, radius * 1.2 + 2.0, 2.6), Color("7a5338"))
	frame.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, radius * 1.15, -1.8)),
		Vector3(radius * 1.55, 0.6, 3.0), Color("b84437"))
	var frame_mi := MeshInstance3D.new()
	frame_mi.mesh = frame.build()
	frame_mi.material_override = SceneryKit.vertex_material()
	root.add_child(frame_mi)

	var wheel := Node3D.new()
	wheel.position = Vector3(0.0, radius * 0.65, 0.6)
	root.add_child(wheel)
	var wb := PropBatch.new()
	for i in 10:
		var ang: float = TAU * float(i) / 10.0
		var pos_v := Vector3(cos(ang) * radius, sin(ang) * radius, 0.0)
		wb.add_box(Transform3D(Basis(Vector3.BACK, ang - PI * 0.5), pos_v * 0.5),
			Vector3(0.28, radius, 0.24), Color("5c3c27"))
		wb.add_box(Transform3D(Basis(Vector3.BACK, ang), pos_v),
			Vector3(0.95, 0.28, 1.5), Color("8c5e3c"))
	var wmi := MeshInstance3D.new()
	wmi.mesh = wb.build()
	wmi.material_override = SceneryKit.vertex_material()
	wheel.add_child(wmi)

	if not anim.has("spinners_z"):
		anim["spinners_z"] = []
	(anim["spinners_z"] as Array).append({"node": wheel, "speed": -0.85})
	return root


static func build_port_crane(parent: Node3D, pos: Vector3, yaw: float,
		height: float, color: Color, anim: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "PortCrane"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var base := PropBatch.new()
	for lx: float in [-2.6, 2.6]:
		for lz: float in [-2.2, 2.2]:
			# Legs run 0..height so the base sits flush on the ground (or lava
			# plane) instead of buried 3 m beneath it.
			base.add_box(Transform3D(Basis.IDENTITY, Vector3(lx, height * 0.5, lz)),
				Vector3(0.9, height, 0.9), color)
	base.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.42, 0.0)),
		Vector3(6.0, 0.85, 5.2), color.darkened(0.12))
	base.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.92, 0.0)),
		Vector3(6.4, 1.4, 5.4), color)
	# Boom arm extending forward (+Z).
	base.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.96, 6.5)),
		Vector3(3.2, 1.1, 22.0), color)
	base.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.84, 3.6)),
		Vector3(2.8, 2.2, 3.4), Color("ffd22e"))
	var base_mi := MeshInstance3D.new()
	base_mi.mesh = base.build()
	base_mi.material_override = SceneryKit.vertex_material()
	root.add_child(base_mi)

	var trolley := Node3D.new()
	trolley.position = Vector3(0.0, height * 0.90, 9.5)
	root.add_child(trolley)
	var tb := PropBatch.new()
	tb.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -3.5, 0.0)),
		Vector3(0.18, 7.0, 0.18), Color("2b323d"))
	tb.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -7.2, 0.0)),
		Vector3(2.8, 2.4, 5.8), Color("e45a45"))
	var tmi := MeshInstance3D.new()
	tmi.mesh = tb.build()
	tmi.material_override = SceneryKit.vertex_material()
	trolley.add_child(tmi)

	if not anim.has("pendulums"):
		anim["pendulums"] = []
	(anim["pendulums"] as Array).append({
		"node": trolley,
		"origin": trolley.position,
		"amp": Vector3(0.0, 1.1, 3.2),
		"speed": 0.48,
	})
	return root


static func build_cargo_ship(parent: Node3D, pos: Vector3, yaw: float,
		scale_val: float, anim: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "CargoShip"
	root.position = pos
	root.rotation.y = yaw
	root.scale = Vector3.ONE * scale_val
	parent.add_child(root)

	var batch := PropBatch.new()
	# Hull + red keel + bow.
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, 0.0)),
		Vector3(9.5, 3.6, 28.0), Color("2c3847"))
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.1, 0.0)),
		Vector3(9.7, 1.2, 28.2), Color("c43b33"))
	batch.add_box(Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0.0, 1.4, 14.0)),
		Vector3(6.7, 3.6, 6.7), Color("2c3847"))
	# Bridge tower at stern (-Z).
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 5.2, -9.8)),
		Vector3(8.2, 4.4, 5.6), Color("f4efe2"))
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 8.2, -9.4)),
		Vector3(9.4, 1.6, 3.6), Color("f4efe2"))
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 8.2, -7.5)),
		Vector3(8.4, 0.75, 0.2), Color("2e86ab"))
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 9.8, -11.4)),
		0.9, 3.2, 8, Color("e45a45"))
	# Container stacks on deck.
	var palette: Array[Color] = [
		Color("e45a45"), Color("2d9fbd"), Color("e8ad3e"), Color("498761"),
	]
	var idx: int = 0
	for cz: float in [-3.2, 2.6, 8.4]:
		for cx: float in [-2.1, 2.1]:
			for cy in 2:
				batch.add_box(Transform3D(Basis.IDENTITY, Vector3(cx, 4.1 + float(cy) * 2.15, cz)),
					Vector3(2.8, 2.0, 5.2), palette[idx % palette.size()])
				idx += 1

	var mi := MeshInstance3D.new()
	mi.mesh = batch.build()
	mi.material_override = SceneryKit.vertex_material()
	root.add_child(mi)

	if not anim.has("bobbers"):
		anim["bobbers"] = []
	(anim["bobbers"] as Array).append({
		"node": root,
		"origin": pos,
		"amp_y": 0.35,
		"roll": 0.028,
		"speed": 0.78,
	})
	return root


static func build_lighthouse(parent: Node3D, pos: Vector3, height: float,
		anim: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Lighthouse"
	root.position = pos
	parent.add_child(root)

	var batch := PropBatch.new()
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0)),
		4.8, 4.0, 9, Color("666e75"))
	var bands: int = 4
	var band_h: float = height / float(bands)
	for b in bands:
		var r_bot: float = lerpf(2.6, 1.5, float(b) / float(bands))
		batch.add_cylinder(Transform3D(Basis.IDENTITY,
			Vector3(0.0, 2.5 + (float(b) + 0.5) * band_h, 0.0)),
			r_bot, band_h, 10, Color("f7f3e8") if b % 2 == 0 else Color("db4439"))
	var lantern_y: float = 2.5 + height + 1.2
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, lantern_y, 0.0)),
		1.45, 2.2, 10, Color("ffe57f"))
	batch.add_cone(Transform3D(Basis.IDENTITY, Vector3(0.0, lantern_y + 1.9, 0.0)),
		2.0, 2.2, 10, Color("2b3242"))
	var mi := MeshInstance3D.new()
	mi.mesh = batch.build()
	mi.material_override = SceneryKit.vertex_material()
	root.add_child(mi)

	var beam := Node3D.new()
	beam.position = Vector3(0.0, lantern_y, 0.0)
	root.add_child(beam)
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.35
	cone_mesh.bottom_radius = 4.2
	cone_mesh.height = 28.0
	cone_mesh.radial_segments = 10
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.94, 0.62, 0.24)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for dir_sign: float in [-1.0, 1.0]:
		var cone_mi := MeshInstance3D.new()
		cone_mi.mesh = cone_mesh
		cone_mi.material_override = mat
		cone_mi.rotation.z = dir_sign * PI * 0.5
		cone_mi.position = Vector3(dir_sign * 14.0, 0.0, 0.0)
		cone_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.add_child(cone_mi)

	if not anim.has("rotators_y"):
		anim["rotators_y"] = []
	(anim["rotators_y"] as Array).append({"node": beam, "speed": 0.95})
	return root


static func add_ski_chalet(batch: PropBatch, pos: Vector3, yaw: float,
		scale_val: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.IDENTITY.scaled(Vector3.ONE * scale_val), pos)
	# Stone plinth & timber walls.
	batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.6, 0.0)),
		Vector3(6.6, 2.2, 5.4), Color("70767d"))
	batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 3.0, 0.0)),
		Vector3(6.2, 3.0, 5.0), Color("8c5938"))
	# Warm glowing windows on front/sides.
	for wx: float in [-1.7, 0.0, 1.7]:
		batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(wx, 3.0, 2.55)),
			Vector3(0.95, 1.1, 0.12), Color("ffd86b"))
	# Pitched snow roof.
	for side: float in [-1.0, 1.0]:
		var rxf := xf * Transform3D(Basis(Vector3.BACK, side * 0.55),
			Vector3(side * 1.9, 5.3, 0.0))
		batch.add_box(rxf, Vector3(4.5, 0.55, 6.0), Color("ecf7fc"))
	# Chimney.
	batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(1.8, 5.8, -1.2)),
		Vector3(0.95, 2.8, 0.95), Color("5b6169"))


static func build_ski_lift_system(parent: Node3D, p_start: Vector3,
		p_end: Vector3, tower_count: int, gondola_count: int,
		anim: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "SkiLiftLine"
	parent.add_child(root)
	var batch := PropBatch.new()
	var dir: Vector3 = (p_end - p_start)
	var flat_dir := Vector3(dir.x, 0.0, dir.z).normalized()
	var yaw: float = atan2(flat_dir.x, flat_dir.z)
	var cross_right: Vector3 = flat_dir.cross(Vector3.UP).normalized()
	var cable_offset: float = 2.4

	for i in maxi(tower_count, 2):
		var t: float = float(i) / float(maxi(tower_count - 1, 1))
		var pt: Vector3 = p_start.lerp(p_end, t)
		# Pylons stand on the ground (y = 0), not floating: height matches
		# the cable point so the base is always buried and the top meets it.
		var pylon_h: float = maxf(pt.y, 4.0)
		var pylon_xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(pt.x, pylon_h * 0.5, pt.z))
		batch.add_cylinder(pylon_xf, 0.45, pylon_h, 8, Color("485968"))
		batch.add_box(Transform3D(Basis(Vector3.UP, yaw), pt + Vector3.UP * 0.1),
			Vector3(cable_offset * 2.3, 0.45, 0.65), Color("36434f"))

	# Parallel cables.
	var span_len: float = p_start.distance_to(p_end)
	var mid: Vector3 = (p_start + p_end) * 0.5
	var pitch: float = atan2(dir.y, maxf(Vector2(dir.x, dir.z).length(), 0.1))
	var cable_basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
	for side: float in [-1.0, 1.0]:
		batch.add_box(Transform3D(cable_basis, mid + cross_right * side * cable_offset),
			Vector3(0.14, 0.14, span_len), Color("283038"))

	var mi := MeshInstance3D.new()
	mi.mesh = batch.build()
	mi.material_override = SceneryKit.vertex_material()
	root.add_child(mi)

	# Animated gondolas gliding back and forth along both cables.
	var colors: Array[Color] = [Color("e85352"), Color("ffd22e"), Color("38d6f0")]
	if not anim.has("gondolas"):
		anim["gondolas"] = []
	for g in gondola_count:
		var side: float = 1.0 if g % 2 == 0 else -1.0
		var car := Node3D.new()
		car.name = "Gondola_%d" % g
		car.rotation.y = yaw
		root.add_child(car)
		var cb := PropBatch.new()
		cb.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -1.2, 0.0)),
			Vector3(0.14, 2.2, 0.14), Color("2d3742"))
		cb.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -2.8, 0.0)),
			Vector3(2.2, 2.1, 2.6), colors[g % colors.size()])
		cb.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -2.5, 0.0)),
			Vector3(2.26, 0.85, 1.8), Color("bceeff"))
		var cmi := MeshInstance3D.new()
		cmi.mesh = cb.build()
		cmi.material_override = SceneryKit.vertex_material()
		car.add_child(cmi)
		(anim["gondolas"] as Array).append({
			"node": car,
			"start": p_start + cross_right * side * cable_offset,
			"end": p_end + cross_right * side * cable_offset,
			"phase": float(g) / float(maxi(gondola_count, 1)),
			"speed": 0.055 if side > 0.0 else -0.055,
		})
	return root


static func build_blimp(parent: Node3D, center: Vector3, orbit_radius: float,
		altitude: float, body_col: Color, fin_col: Color, anim: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "FestivalBlimp"
	root.position = Vector3(center.x + orbit_radius, altitude, center.z)
	parent.add_child(root)

	var hull := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 4.6
	sm.height = 9.2
	sm.radial_segments = 14
	sm.rings = 8
	hull.mesh = sm
	hull.scale = Vector3(1.0, 0.92, 2.65)
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = body_col
	hull_mat.roughness = 0.85
	hull.material_override = hull_mat
	root.add_child(hull)

	var fins := PropBatch.new()
	fins.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -4.4, 0.5)),
		Vector3(2.6, 1.8, 5.4), Color("262b3d"))
	fins.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -10.5)),
		Vector3(0.45, 7.6, 3.6), fin_col)
	fins.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -10.5)),
		Vector3(7.6, 0.45, 3.6), fin_col)
	var fmi := MeshInstance3D.new()
	fmi.mesh = fins.build()
	fmi.material_override = SceneryKit.vertex_material()
	root.add_child(fmi)

	if not anim.has("orbiters"):
		anim["orbiters"] = []
	(anim["orbiters"] as Array).append({
		"node": root,
		"center": Vector3(center.x, altitude, center.z),
		"radius": orbit_radius,
		"speed": 0.14,
		"phase": 0.4,
	})
	return root


static func build_hot_air_balloon(parent: Node3D, pos: Vector3,
		col_a: Color, col_b: Color, phase: float, anim: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Balloon"
	root.position = pos
	parent.add_child(root)

	var env := PropBatch.new()
	var rings: Array[Dictionary] = [
		{"y": 0.0, "r": 1.4},
		{"y": 1.8, "r": 3.4},
		{"y": 4.2, "r": 4.2},
		{"y": 6.4, "r": 3.0},
		{"y": 7.6, "r": 0.4},
	]
	var segs: int = 10
	for i in rings.size() - 1:
		var lo: Dictionary = rings[i]
		var hi: Dictionary = rings[i + 1]
		for s in segs:
			var a0: float = TAU * float(s) / float(segs)
			var a1: float = TAU * float(s + 1) / float(segs)
			var p00 := Vector3(cos(a0) * float(lo["r"]), float(lo["y"]), sin(a0) * float(lo["r"]))
			var p01 := Vector3(cos(a1) * float(lo["r"]), float(lo["y"]), sin(a1) * float(lo["r"]))
			var p10 := Vector3(cos(a0) * float(hi["r"]), float(hi["y"]), sin(a0) * float(hi["r"]))
			var p11 := Vector3(cos(a1) * float(hi["r"]), float(hi["y"]), sin(a1) * float(hi["r"]))
			var col: Color = col_a if s % 2 == 0 else col_b
			if i == 2:
				col = col_b.lightened(0.18) if s % 2 == 0 else col_a.lightened(0.18)
			var out_v := Vector3(cos((a0 + a1) * 0.5), 0.15, sin((a0 + a1) * 0.5)).normalized()
			add_quad_outward(env, p00, p10, p11, p01, col, out_v)
	env.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, -2.4, 0.0)),
		Vector3(1.8, 1.4, 1.8), Color("8a5b3d"))
	for c: Vector2 in [Vector2(-0.7, -0.7), Vector2(0.7, -0.7), Vector2(-0.7, 0.7), Vector2(0.7, 0.7)]:
		env.add_box(Transform3D(Basis.IDENTITY, Vector3(c.x, -1.0, c.y)),
			Vector3(0.10, 2.0, 0.10), Color("4a3728"))
	var mi := MeshInstance3D.new()
	mi.mesh = env.build()
	mi.material_override = SceneryKit.vertex_material()
	root.add_child(mi)

	if not anim.has("bobbers"):
		anim["bobbers"] = []
	(anim["bobbers"] as Array).append({
		"node": root,
		"origin": pos,
		"amp_y": 1.6,
		"roll": 0.035,
		"speed": 0.52,
		"phase": phase,
	})
	return root


static func add_skyscraper(batch: PropBatch, pos: Vector3, yaw: float,
		width: float, depth: float, height: float, body_col: Color,
		win_col: Color, rng: RandomNumberGenerator) -> void:
	## Tiered cartoon skyscraper with setbacks, glowing window bands & spire.
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	var lower_h: float = height * 0.62
	var upper_h: float = height * 0.38
	batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, lower_h * 0.5, 0.0)),
		Vector3(width, lower_h, depth), body_col)
	batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, lower_h + upper_h * 0.5, 0.0)),
		Vector3(width * 0.76, upper_h, depth * 0.76), body_col.lightened(0.07))
	# Window strips around all 4 sides.
	var rows: int = clampi(int(height / 8.0), 3, 8)
	for r in rows:
		var wy: float = height * (0.14 + 0.76 * float(r) / float(rows))
		var is_upper: bool = wy > lower_h
		var w_span: float = (width if not is_upper else width * 0.76) * 0.72
		var d_half: float = (depth if not is_upper else depth * 0.76) * 0.5 + 0.06
		batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, wy, d_half)),
			Vector3(w_span, 1.05, 0.14), win_col)
		batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, wy, -d_half)),
			Vector3(w_span, 1.05, 0.14), win_col)
	# Rooftop crown + spire.
	if rng.randf() < 0.65:
		batch.add_cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, height + 3.5, 0.0)),
			0.25, 7.0, 6, Color("ef5c67"))
	else:
		batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(width * 0.12, height + 1.4, 0.0)),
			Vector3(width * 0.28, 2.8, depth * 0.28), Color("677996"))


static func step_animations(anim: Dictionary, time: float, delta: float) -> void:
	## Advances all registered moving parts cleanly on non-headless frames.
	if anim.is_empty():
		return
	for item: Dictionary in anim.get("spinners_z", []):
		var node := item.get("node") as Node3D
		if is_instance_valid(node):
			node.rotation.z += delta * float(item.get("speed", 0.5))
	for item: Dictionary in anim.get("rotators_y", []):
		var node := item.get("node") as Node3D
		if is_instance_valid(node):
			node.rotation.y += delta * float(item.get("speed", 0.5))
	for item: Dictionary in anim.get("bobbers", []):
		var node := item.get("node") as Node3D
		if is_instance_valid(node):
			var origin: Vector3 = item.get("origin", Vector3.ZERO) as Vector3
			var sp: float = float(item.get("speed", 0.6))
			var ph: float = float(item.get("phase", 0.0))
			var amp_y: float = float(item.get("amp_y", 0.5))
			var roll: float = float(item.get("roll", 0.0))
			node.position = origin + Vector3.UP * sin(time * sp + ph) * amp_y
			node.rotation.z = sin(time * sp * 0.8 + ph) * roll
	for item: Dictionary in anim.get("pendulums", []):
		var node := item.get("node") as Node3D
		if is_instance_valid(node):
			var origin: Vector3 = item.get("origin", Vector3.ZERO) as Vector3
			var amp: Vector3 = item.get("amp", Vector3.ZERO) as Vector3
			var sp: float = float(item.get("speed", 0.5))
			node.position = origin + amp * sin(time * sp)
	for item: Dictionary in anim.get("orbiters", []):
		var node := item.get("node") as Node3D
		if is_instance_valid(node):
			var center: Vector3 = item.get("center", Vector3.ZERO) as Vector3
			var rad: float = float(item.get("radius", 80.0))
			var ang: float = time * float(item.get("speed", 0.15)) + float(item.get("phase", 0.0))
			node.position = Vector3(center.x + cos(ang) * rad,
				center.y + sin(time * 0.5) * 2.2, center.z + sin(ang) * rad)
			node.rotation.y = -ang
	for item: Dictionary in anim.get("gondolas", []):
		var node := item.get("node") as Node3D
		if is_instance_valid(node):
			var p0: Vector3 = item.get("start", Vector3.ZERO) as Vector3
			var p1: Vector3 = item.get("end", Vector3.ZERO) as Vector3
			var sp: float = float(item.get("speed", 0.05))
			var ph: float = float(item.get("phase", 0.0))
			var ping: float = 0.5 - 0.5 * cos((time * absf(sp) + ph) * TAU)
			if sp < 0.0:
				ping = 1.0 - ping
			node.position = p0.lerp(p1, ping)


static func add_biome_particles(parent: Node3D, biome: String, center: Vector3,
		extent_xz: float = 160.0) -> GPUParticles3D:
	## Lightweight ambient biome particle emitter (skipped in headless).
	if parent == null or DisplayServer.get_name() == "headless":
		return null
	var gp := GPUParticles3D.new()
	gp.name = "BiomeParticles_" + biome
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.visibility_aabb = AABB(Vector3(-extent_xz, -20.0, -extent_xz),
		Vector3(extent_xz * 2.0, 80.0, extent_xz * 2.0))
	gp.position = center + Vector3(0.0, 14.0, 0.0)

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(extent_xz * 0.75, 10.0, extent_xz * 0.75)

	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES

	match biome:
		"glacier", "snowfield", "ko_iceberg":
			gp.amount = 220
			gp.lifetime = 4.5
			proc.direction = Vector3(0.45, -1.0, 0.25)
			proc.spread = 22.0
			proc.initial_velocity_min = 3.5
			proc.initial_velocity_max = 6.5
			proc.gravity = Vector3(1.2, -1.8, 0.5)
			quad.size = Vector2(0.28, 0.28)
			mat.albedo_color = Color(0.95, 0.99, 1.0, 0.85)
		"canyon", "bt_labyrinth":
			gp.amount = 140
			gp.lifetime = 5.0
			proc.direction = Vector3(1.0, 0.12, 0.35)
			proc.spread = 28.0
			proc.initial_velocity_min = 4.0
			proc.initial_velocity_max = 8.0
			proc.gravity = Vector3(0.6, -0.2, 0.2)
			quad.size = Vector2(0.32, 0.18)
			mat.albedo_color = Color(1.0, 0.80, 0.48, 0.60)
		"dockyard", "harbour", "bt_ferries":
			gp.amount = 120
			gp.lifetime = 4.0
			proc.direction = Vector3(0.7, 0.2, 0.3)
			proc.spread = 35.0
			proc.initial_velocity_min = 2.0
			proc.initial_velocity_max = 4.5
			proc.gravity = Vector3(0.4, 0.1, 0.1)
			quad.size = Vector2(0.45, 0.45)
			mat.albedo_color = Color(0.84, 0.96, 1.0, 0.42)
		"foundry", "ko_foundry":
			gp.amount = 180
			gp.lifetime = 3.6
			proc.direction = Vector3(0.1, 1.0, 0.1)
			proc.spread = 26.0
			proc.initial_velocity_min = 3.0
			proc.initial_velocity_max = 6.8
			proc.gravity = Vector3(0.2, 2.2, 0.0)
			quad.size = Vector2(0.26, 0.26)
			mat.albedo_color = Color(1.0, 0.55, 0.18, 0.90)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.45, 0.12)
			mat.emission_energy_multiplier = 1.8
		"stadium", "bt_plaza":
			gp.amount = 130
			gp.lifetime = 4.8
			proc.direction = Vector3(0.2, -0.6, 0.15)
			proc.spread = 45.0
			proc.initial_velocity_min = 1.5
			proc.initial_velocity_max = 3.2
			proc.gravity = Vector3(0.2, -0.9, 0.1)
			quad.size = Vector2(0.28, 0.16)
			mat.albedo_color = Color(1.0, 0.88, 0.35, 0.78)
		_:
			gp.amount = 130
			gp.lifetime = 5.2
			proc.direction = Vector3(0.5, 0.15, 0.2)
			proc.spread = 45.0
			proc.initial_velocity_min = 1.2
			proc.initial_velocity_max = 2.8
			proc.gravity = Vector3(0.3, -0.25, 0.15)
			quad.size = Vector2(0.22, 0.22)
			mat.albedo_color = Color(0.98, 0.95, 0.62, 0.74)

	quad.material = mat
	gp.process_material = proc
	gp.draw_pass_1 = quad
	gp.emitting = true
	parent.add_child(gp)
	return gp
