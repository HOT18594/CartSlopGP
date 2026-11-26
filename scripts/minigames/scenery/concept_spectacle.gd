extends RefCounted
## Bespoke Concept-Art 3D Spectacle Asset Library (0.8.5):
## Brings the stylized hero concept artworks to life directly inside 3D maps:
##   - Shimmering 3D Northern Lights (Aurora Borealis) sky curtains
##   - Glowing wooden trackside lantern posts (warm amber glass + soft glow)
##   - Giant faceted luminous turquoise glacier ice crystal clusters
##   - Monumental curved Checkered Grand Prix tunnel arches
##   - Swaying colorful festival pennant bunting garlands
##   - Glowing cyan/gold track chevron speed arrows
##   - Neon twilight Knockout octagon chevron barriers & multi-bulb floodlight towers
##
## All geometry is pure procedural low-poly stylized art (zero photo textures)
## with minimal draw calls and safe visual-only clearance outside road lanes.

const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const LandscapeSculptor := preload("res://scripts/minigames/scenery/landscape_sculptor.gd")
const AURORA_SHADER := preload("res://assets/materials/aurora_sky.gdshader")
const LANTERN_POOL_SHADER := preload("res://assets/materials/lantern_pool.gdshader")


static func _emissive_mat(color: Color, energy: float = 2.6,
		transparent: bool = false, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


static func crystal_material() -> StandardMaterial3D:
	## Faceted glacier ice crystal material: unshaded per-facet vertex colors with
	## a subtle deep-cyan inner luminescence so all 6 geometric crystal faces
	## stay distinct and vibrant without blooming to flat white.
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


# --------------------------------------------------------------------------
# 1. Shimmering 3D Northern Lights (Aurora Borealis) Sky Curtains
# --------------------------------------------------------------------------


static func build_northern_lights(parent: Node3D, center: Vector3,
		sky_radius: float = 260.0, base_altitude: float = 82.0) -> Node3D:
	## Builds 3 sweeping curved 3D aurora curtains arching across the sky dome,
	## driven by our custom animated aurora_sky.gdshader!
	if parent == null:
		return null
	var root := Node3D.new()
	root.name = "NorthernLightsAurora"
	root.position = Vector3(center.x, base_altitude, center.z)
	parent.add_child(root)

	var ribbon_specs: Array[Dictionary] = [
		{"r": sky_radius * 0.92, "h": 98.0, "y": 4.0, "a0": -2.6, "a1": 1.3, "phase": 0.0,
			"low": Color("24ff8c"), "mid": Color("22e8ff"), "high": Color("7d3cff"), "energy": 2.05},
		{"r": sky_radius * 0.68, "h": 82.0, "y": 20.0, "a0": 0.1, "a1": 3.7, "phase": 2.1,
			"low": Color("30ffb2"), "mid": Color("38d6ff"), "high": Color("b448ff"), "energy": 1.85},
		{"r": sky_radius * 1.06, "h": 114.0, "y": -8.0, "a0": -1.1, "a1": 2.8, "phase": 4.3,
			"low": Color("1eff9e"), "mid": Color("26d4ff"), "high": Color("6a32e8"), "energy": 1.65},
		{"r": sky_radius * 0.44, "h": 68.0, "y": 34.0, "a0": -3.14, "a1": 3.14, "phase": 1.15,
			"low": Color("2eff98"), "mid": Color("3bf0ff"), "high": Color("8c42ff"), "energy": 1.95},
	]

	for idx in ribbon_specs.size():
		var spec: Dictionary = ribbon_specs[idx]
		var r: float = float(spec["r"])
		var h: float = float(spec["h"])
		var y0: float = float(spec["y"])
		var a0: float = float(spec["a0"])
		var a1: float = float(spec["a1"])
		var segs: int = 44

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var prev_b := Vector3.ZERO
		var prev_t := Vector3.ZERO
		var prev_u: float = 0.0
		for i in segs + 1:
			var u: float = float(i) / float(segs)
			var ang: float = lerpf(a0, a1, u)
			# Organic serpentine S-curve ribbon footprint
			var r_mod: float = r + sin(u * PI * 3.0 + float(idx)) * (sky_radius * 0.14)
			var px: float = cos(ang) * r_mod
			var pz: float = sin(ang) * r_mod
			var y_undulate: float = y0 + sin(u * PI * 2.0 + float(idx) * 1.4) * 14.0
			var pb := Vector3(px, y_undulate, pz)
			var pt := Vector3(px * 0.94, y_undulate + h, pz * 0.94)
			if i > 0:
				st.set_uv(Vector2(prev_u, 0.0))
				st.add_vertex(prev_b)
				st.set_uv(Vector2(prev_u, 1.0))
				st.add_vertex(prev_t)
				st.set_uv(Vector2(u, 1.0))
				st.add_vertex(pt)

				st.set_uv(Vector2(prev_u, 0.0))
				st.add_vertex(prev_b)
				st.set_uv(Vector2(u, 1.0))
				st.add_vertex(pt)
				st.set_uv(Vector2(u, 0.0))
				st.add_vertex(pb)
			prev_b = pb
			prev_t = pt
			prev_u = u

		var mi := MeshInstance3D.new()
		mi.name = "AuroraRibbon_%d" % idx
		mi.mesh = st.commit()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sm := ShaderMaterial.new()
		sm.shader = AURORA_SHADER
		sm.set_shader_parameter("color_low", spec["low"])
		sm.set_shader_parameter("color_mid", spec["mid"])
		sm.set_shader_parameter("color_high", spec["high"])
		sm.set_shader_parameter("phase_offset", float(spec["phase"]))
		sm.set_shader_parameter("intensity", float(spec["energy"]))
		mi.material_override = sm
		root.add_child(mi)
	return root


# --------------------------------------------------------------------------
# 2. Warm Glowing Wooden Trackside Lantern Posts (Glacier / Meadow / Plazas)
# --------------------------------------------------------------------------


static func build_track_lanterns(parent: Node3D, spline: RefCounted,
		spacing_m: float = 34.0, offset_from_center: float = 12.6,
		warm_color: Color = Color("ffb538"), wood_color: Color = Color("5e3e29")) -> Node3D:
	## Lines both sides of a race circuit with stylized wooden hanging lanterns
	## that cast a warm glowing golden core & soft halo (just like bg_hero_glacier!).
	if parent == null or spline == null:
		return null
	var total: float = maxf(float(spline.total_length), 1.0)
	var count: int = clampi(int(total / maxf(spacing_m, 16.0)), 14, 52)
	var samples := PackedVector3Array()
	for si in 140:
		var sf: Dictionary = spline.call("sample", total * float(si) / 140.0)
		samples.append(sf["position"] as Vector3)

	var wood_batch := PropBatch.new()
	var glow_xforms: Array = []
	var halo_xforms: Array = []

	for i in count:
		var s: float = total * (float(i) + 0.25) / float(count)
		var frame: Dictionary = spline.call("sample", s)
		var pos: Vector3 = frame["position"] as Vector3
		var right: Vector3 = frame["right"] as Vector3
		right.y = 0.0
		if right.length_squared() < 0.001:
			continue
		right = right.normalized()
		var fw: Vector3 = frame["forward"] as Vector3
		fw.y = 0.0
		fw = fw.normalized()
		var yaw: float = atan2(-fw.x, -fw.z)

		# Alternate sides (or place both on key landmarks) while keeping strict clearance.
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var post_pos: Vector3 = pos + right * (side * offset_from_center)
		if not _clear_of_samples(post_pos, samples, offset_from_center - 1.4):
			continue
		_stamp_lantern_post(wood_batch, glow_xforms, halo_xforms,
			post_pos, yaw, -side, wood_color)

	return _flush_lanterns(parent, "TrackLanterns", wood_batch, glow_xforms, halo_xforms, warm_color)


static func build_ring_lanterns(parent: Node3D, points: Array[Dictionary],
		warm_color: Color = Color("ffb538"), wood_color: Color = Color("5e3e29")) -> Node3D:
	## Places glowing lantern posts at explicit arena/courtyard positions.
	## Each dict: { "pos": Vector3, "yaw": float, "inward_side": float }
	if parent == null or points.is_empty():
		return null
	var wood_batch := PropBatch.new()
	var glow_xforms: Array = []
	var halo_xforms: Array = []
	for pt: Dictionary in points:
		_stamp_lantern_post(wood_batch, glow_xforms, halo_xforms,
			pt["pos"] as Vector3, float(pt.get("yaw", 0.0)),
			float(pt.get("inward_side", 1.0)), wood_color)
	return _flush_lanterns(parent, "ArenaLanterns", wood_batch, glow_xforms, halo_xforms, warm_color)


static func _stamp_lantern_post(wood_batch: PropBatch, glow_xforms: Array,
		halo_xforms: Array, pos: Vector3, yaw: float, arm_sign: float,
		wood_color: Color) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), pos)
	var iron := Color("1f2233")
	var cap_col := Color("2b2d42")
	# Grounded timber post + snow/stone plinth
	wood_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 2.2, 0.0)),
		Vector3(0.32, 5.4, 0.32), wood_color)
	wood_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.25, 0.0)),
		Vector3(0.58, 0.8, 0.58), wood_color.darkened(0.22))
	# Horizontal overhanging wooden arm pointing inward toward track
	wood_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(arm_sign * 0.82, 4.55, 0.0)),
		Vector3(1.85, 0.22, 0.22), wood_color)
	# Diagonal brace strut
	wood_batch.add_box(xf * Transform3D(Basis(Vector3.BACK, arm_sign * 0.72),
		Vector3(arm_sign * 0.45, 4.10, 0.0)), Vector3(0.16, 1.05, 0.16), wood_color.darkened(0.1))
	# Lantern iron hook + peaked roof cap + base tray
	var lx: float = arm_sign * 1.48
	wood_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(lx, 4.26, 0.0)),
		Vector3(0.08, 0.38, 0.08), iron)
	wood_batch.add_cone(xf * Transform3D(Basis.IDENTITY, Vector3(lx, 4.02, 0.0)),
		0.48, 0.34, 6, cap_col)
	wood_batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(lx, 3.24, 0.0)),
		Vector3(0.46, 0.10, 0.46), cap_col)
	# Glowing lantern glass + soft warm halo
	var lantern_xf: Transform3D = xf * Transform3D(Basis.IDENTITY, Vector3(lx, 3.62, 0.0))
	glow_xforms.append(lantern_xf)
	halo_xforms.append(lantern_xf)


static func _flush_lanterns(parent: Node3D, node_name: String, wood_batch: PropBatch,
		glow_xforms: Array, halo_xforms: Array, warm_color: Color) -> Node3D:
	if glow_xforms.is_empty():
		return null
	var root := Node3D.new()
	root.name = node_name
	parent.add_child(root)
	wood_batch.flush_to(root, "LanternPosts", false, SceneryKit.vertex_material())

	var glass := CylinderMesh.new()
	glass.top_radius = 0.28
	glass.bottom_radius = 0.21
	glass.height = 0.68
	glass.radial_segments = 6
	var glass_mm := SceneryKit.multimesh(glass, _emissive_mat(warm_color, 4.2),
		glow_xforms, "LanternGlass", false)
	root.add_child(glass_mm)

	var halo := SphereMesh.new()
	halo.radius = 0.92
	halo.height = 1.84
	halo.radial_segments = 10
	halo.rings = 6
	var halo_mm := SceneryKit.multimesh(halo, _emissive_mat(warm_color, 1.5, true, 0.18),
		halo_xforms, "LanternHalos", false)
	root.add_child(halo_mm)

	# Real warm golden glow pools projected onto the floor beneath EVERY lantern!
	var pool_xforms: Array = []
	var flat_rot := Basis(Vector3.RIGHT, -PI * 0.5)
	for g_xf: Transform3D in glow_xforms:
		var floor_pos := Vector3(g_xf.origin.x, g_xf.origin.y - 3.52, g_xf.origin.z)
		pool_xforms.append(Transform3D(flat_rot, floor_pos))
	var pool_quad := QuadMesh.new()
	pool_quad.size = Vector2(12.5, 12.5)
	var pool_mat := ShaderMaterial.new()
	pool_mat.shader = LANTERN_POOL_SHADER
	pool_mat.set_shader_parameter("pool_color", warm_color)
	pool_mat.set_shader_parameter("intensity", 1.25)
	var pool_mm := SceneryKit.multimesh(pool_quad, pool_mat, pool_xforms, "LanternFloorPools", false)
	root.add_child(pool_mm)

	# Real OmniLight3D lights illuminating karts, snow, stone, and road surfaces!
	# Budget up to 14 evenly spaced lights per scene for buttery Forward Mobile FPS.
	var max_lights: int = 14
	var step: int = maxi(1, int(ceili(float(glow_xforms.size()) / float(max_lights))))
	var spawned_lights: int = 0
	for i in range(0, glow_xforms.size(), step):
		if spawned_lights >= max_lights:
			break
		var l_xf: Transform3D = glow_xforms[i] as Transform3D
		var light := OmniLight3D.new()
		light.name = "LanternLight_%d" % spawned_lights
		light.position = l_xf.origin - Vector3(0.0, 0.35, 0.0)
		light.light_color = warm_color
		light.light_energy = 2.6
		light.omni_range = 16.5
		light.omni_attenuation = 1.45
		light.shadow_enabled = false
		root.add_child(light)
		spawned_lights += 1
	return root


# --------------------------------------------------------------------------
# 3. Giant Faceted Glowing Turquoise Ice Crystal Clusters (bg_hero_glacier!)
# --------------------------------------------------------------------------


static func build_glacier_crystals(parent: Node3D, spline: RefCounted,
		count: int = 26) -> Node3D:
	## Dramatic giant translucent/glowing faceted cyan-sapphire ice crystal spires
	## jutting from the snowy cliff verges alongside the track (matching bg_hero_glacier!).
	if parent == null or spline == null:
		return null
	var total: float = maxf(float(spline.total_length), 1.0)
	var samples := PackedVector3Array()
	for si in 180:
		var sf: Dictionary = spline.call("sample", total * float(si) / 180.0)
		samples.append(sf["position"] as Vector3)

	var rng := RandomNumberGenerator.new()
	rng.seed = 77431
	var batch := PropBatch.new()
	var snow_batch := PropBatch.new()
	var placed: int = 0
	for i in count:
		var s: float = total * (float(i) + 0.38) / float(count)
		var frame: Dictionary = spline.call("sample", s)
		var pos: Vector3 = frame["position"] as Vector3
		var right: Vector3 = frame["right"] as Vector3
		right.y = 0.0
		if right.length_squared() < 0.001:
			continue
		right = right.normalized()
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var scale_k: float = rng.randf_range(1.35, 2.55)
		var dist: float = rng.randf_range(21.5, 34.0)
		var c_pos: Vector3 = pos + right * (side * dist)
		# Verify both center and outer crystal ring clear every road segment!
		var clear_r: float = 16.5 + scale_k * 3.0
		if not _clear_of_samples(c_pos, samples, clear_r):
			side = -side
			c_pos = pos + right * (side * dist)
			if not _clear_of_samples(c_pos, samples, clear_r):
				continue
		c_pos.y = maxf(pos.y - 1.2, 0.0)
		add_crystal_cluster(batch, c_pos, scale_k, rng, snow_batch)
		placed += 1
	if placed == 0:
		return null
	var root := Node3D.new()
	root.name = "GlacierIceCrystals"
	parent.add_child(root)
	var mi := MeshInstance3D.new()
	mi.name = "CrystalSpires"
	mi.mesh = batch.build()
	mi.material_override = crystal_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	snow_batch.flush_to(root, "CrystalSnowBases", false, SceneryKit.vertex_material())
	return root


static func add_crystal_cluster(batch: PropBatch, center: Vector3,
		scale_k: float, rng: RandomNumberGenerator,
		snow_batch: PropBatch = null) -> void:
	## 4-7 angled multi-faceted hexagonal crystalline spires rising from a sculpted
	## snow-and-slate pedestal, with per-face turquoise/cyan/sapphire facet shading
	## matching bg_hero_glacier.png.
	var shards: int = rng.randi_range(4, 7)
	var pal_main: Array[Color] = [
		Color("35cef7"), Color("28b4eb"), Color("4ee0ff"), Color("1e98d6"),
	]
	if snow_batch != null:
		# Sculpted snowbank & dark slate rock collar wrapping the crystal eruption
		snow_batch.add_cone(Transform3D(Basis.IDENTITY, center + Vector3(0.0, 0.65 * scale_k, 0.0)),
			3.8 * scale_k, 2.4 * scale_k, 8, Color("e3f3fc"))
		snow_batch.add_cone(Transform3D(Basis(Vector3.UP, 0.4), center + Vector3(0.8 * scale_k, 0.45 * scale_k, -0.6 * scale_k)),
			2.9 * scale_k, 1.8 * scale_k, 7, Color("bfdcf0"))
		snow_batch.add_box(Transform3D(Basis(Vector3.UP, 0.25), center + Vector3(0.0, -1.8 * scale_k, 0.0)),
			Vector3(4.8 * scale_k, 3.8 * scale_k, 4.8 * scale_k), Color("2b4870"))
	for i in shards:
		var is_main: bool = i == 0
		var is_second: bool = i == 1
		var h: float = (rng.randf_range(12.5, 19.5) if is_main else (rng.randf_range(8.5, 13.5) if is_second else rng.randf_range(4.8, 9.8))) * scale_k
		var r: float = (rng.randf_range(1.75, 2.65) if is_main else (rng.randf_range(1.25, 1.95) if is_second else rng.randf_range(0.82, 1.42))) * scale_k
		var ang: float = TAU * float(i) / float(shards) + rng.randf_range(-0.22, 0.22)
		var off := Vector3(cos(ang), 0.0, sin(ang)) * (0.0 if is_main else r * 1.28)
		var tilt_x: float = rng.randf_range(-0.14, 0.14) if is_main else rng.randf_range(-0.42, 0.42)
		var tilt_z: float = rng.randf_range(-0.14, 0.14) if is_main else rng.randf_range(-0.42, 0.42)
		var rot := Basis(Vector3.UP, ang) * Basis(Vector3.RIGHT, tilt_x) * Basis(Vector3.FORWARD, tilt_z)
		var col: Color = pal_main[i % pal_main.size()]
		var base_xf := Transform3D(rot, center + off)
		_add_faceted_crystal_spire(batch, base_xf, r, h, col)


static func _add_faceted_crystal_spire(batch: PropBatch, base_xf: Transform3D,
		radius: float, height: float, base_col: Color) -> void:
	## 6-sided hexagonal quartz-ice crystal prism with distinct per-facet colors:
	## deep sapphire collar -> multi-tone turquoise shaft -> tapered upper shoulder -> chiseled 6-facet apex.
	var sides: int = 6
	var facet_tones: Array[Color] = [
		base_col.lightened(0.42), # Sun-catching specular diamond-cyan facet
		base_col.lightened(0.20), # Bright turquoise facet
		base_col,                 # Core glacial cyan facet
		base_col.darkened(0.18),  # Mid sapphire facet
		base_col.darkened(0.32),  # Deep shadow sapphire facet
		base_col.lightened(0.08), # Rim-lit cyan facet
	]
	var y0: float = -0.4
	var y1: float = height * 0.24
	var y2: float = height * 0.68
	var y3: float = height * 1.0
	var r0: float = radius * 1.06
	var r1: float = radius * 0.96
	var r2: float = radius * 0.74
	var apex: Vector3 = base_xf * Vector3(0.0, y3, 0.0)
	for s in sides:
		var a0: float = TAU * float(s) / float(sides)
		var a1: float = TAU * float(s + 1) / float(sides)
		var c0 := Vector2(cos(a0), sin(a0))
		var c1 := Vector2(cos(a1), sin(a1))
		var f_col: Color = facet_tones[s % facet_tones.size()]
		var collar_col: Color = f_col.darkened(0.26)
		var tip_col: Color = f_col.lightened(0.22)

		var p00: Vector3 = base_xf * Vector3(c0.x * r0, y0, c0.y * r0)
		var p01: Vector3 = base_xf * Vector3(c1.x * r0, y0, c1.y * r0)
		var p10: Vector3 = base_xf * Vector3(c0.x * r1, y1, c0.y * r1)
		var p11: Vector3 = base_xf * Vector3(c1.x * r1, y1, c1.y * r1)
		var p20: Vector3 = base_xf * Vector3(c0.x * r2, y2, c0.y * r2)
		var p21: Vector3 = base_xf * Vector3(c1.x * r2, y2, c1.y * r2)

		# Lower sapphire collar quad
		batch.add_quad(p00, p10, p11, p01, collar_col)
		# Main faceted crystal shaft quad
		batch.add_quad(p10, p20, p21, p11, f_col)
		# Chiseled pyramidal crystal tip triangle
		batch.add_triangle(p20, apex, p21, tip_col)


# --------------------------------------------------------------------------
# 4. Monumental Checkered Grand Prix Tunnel Arches (bg_hero_paddock!)
# --------------------------------------------------------------------------


static func build_checkered_arches(parent: Node3D, spline: RefCounted,
		fractions: Array[float], span_width: float = 23.0,
		clear_height: float = 13.5, accent: Color = Color("38d6f0")) -> Node3D:
	## Sweeping parabolic checkered racing arches straddling the circuit, with
	## piers wide outside the lane and glowing neon racing trim!
	if parent == null or spline == null:
		return null
	var total: float = maxf(float(spline.total_length), 1.0)
	var batch := PropBatch.new()
	var trim_batch := PropBatch.new()
	var built_any: bool = false

	for frac: float in fractions:
		var frame: Dictionary = spline.call("sample", total * frac)
		var pos: Vector3 = frame["position"] as Vector3
		var fw: Vector3 = frame["forward"] as Vector3
		fw.y = 0.0
		if fw.length_squared() < 0.001:
			continue
		fw = fw.normalized()
		var yaw: float = atan2(-fw.x, -fw.z)
		add_checkered_arch_at(batch, trim_batch, pos, yaw, span_width, clear_height, accent)
		built_any = true

	if not built_any:
		return null
	var root := Node3D.new()
	root.name = "CheckeredGPArches"
	parent.add_child(root)
	batch.flush_to(root, "ArchShell", false, SceneryKit.vertex_material())
	trim_batch.flush_to(root, "ArchNeonTrim", false, _emissive_mat(accent, 2.2))
	return root


static func add_checkered_arch_at(batch: PropBatch, trim_batch: PropBatch,
		center: Vector3, yaw: float, span_width: float = 23.0,
		clear_height: float = 13.5, accent: Color = Color("38d6f0")) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), center)
	var half_span: float = span_width * 0.5
	var segs: int = 16
	var depth: float = 3.4
	var col_w := Color("f7f9fc")
	var col_b := Color("1c1f33")
	var col_pier := Color("dce4f0")

	# Grounded plinth feet well outside the lane
	for side: float in [-1.0, 1.0]:
		batch.add_box(xf * Transform3D(Basis.IDENTITY, Vector3(side * (half_span + 0.6), 0.4, 0.0)),
			Vector3(3.2, 3.2, depth + 1.2), col_pier)

	for i in segs:
		var a0: float = PI * float(i) / float(segs)
		var a1: float = PI * float(i + 1) / float(segs)
		var p0 := Vector3(-cos(a0) * half_span, sin(a0) * clear_height, 0.0)
		var p1 := Vector3(-cos(a1) * half_span, sin(a1) * clear_height, 0.0)
		var mid: Vector3 = (p0 + p1) * 0.5
		var dir: Vector3 = p1 - p0
		var seg_len: float = dir.length() + 0.16
		var ang: float = atan2(dir.y, dir.x)
		var seg_xf := xf * Transform3D(Basis(Vector3.BACK, ang), mid)
		# Two rows of alternating checkered blocks along arch thickness
		batch.add_box(seg_xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -depth * 0.25)),
			Vector3(seg_len, 1.35, depth * 0.48), col_w if i % 2 == 0 else col_b)
		batch.add_box(seg_xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0,  depth * 0.25)),
			Vector3(seg_len, 1.35, depth * 0.48), col_b if i % 2 == 0 else col_w)
		# Glowing neon inner underside rim strip!
		trim_batch.add_box(seg_xf * Transform3D(Basis.IDENTITY, Vector3(0.0, -0.74, 0.0)),
			Vector3(seg_len, 0.18, depth * 0.82), accent)


# --------------------------------------------------------------------------
# 5. Swaying Colorful Festival Pennant Bunting Garlands (bg_hero_canyon/paddock!)
# --------------------------------------------------------------------------


static func build_pennant_garlands(parent: Node3D, spline: RefCounted,
		fractions: Array[float], span_width: float = 24.0,
		height: float = 11.5) -> Node3D:
	## Overhead festival flag lines slung across tracks/canyons on twin poles.
	if parent == null or spline == null:
		return null
	var total: float = maxf(float(spline.total_length), 1.0)
	var batch := PropBatch.new()
	var built: bool = false
	for frac: float in fractions:
		var frame: Dictionary = spline.call("sample", total * frac)
		var pos: Vector3 = frame["position"] as Vector3
		var fw: Vector3 = frame["forward"] as Vector3
		fw.y = 0.0
		if fw.length_squared() < 0.001:
			continue
		fw = fw.normalized()
		add_pennant_line(batch, pos, atan2(-fw.x, -fw.z), span_width, height)
		built = true
	if not built:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "FestivalPennantGarlands"
	mi.mesh = batch.build()
	mi.material_override = SceneryKit.vertex_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func add_pennant_line(batch: PropBatch, center: Vector3, yaw: float,
		span_width: float = 24.0, height: float = 11.5) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), center)
	var half: float = span_width * 0.5
	var pole_col := Color("594132")
	var wire_col := Color("1f2233")
	var flag_cols: Array[Color] = [
		Color("ff4757"), Color("ffd22e"), Color("38d6f0"),
		Color("4cd964"), Color("f26ca7"), Color("ff9f43"),
	]
	for side: float in [-1.0, 1.0]:
		batch.add_cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(side * half, height * 0.5 - 0.8, 0.0)),
			0.26, height + 1.8, 8, pole_col)
		batch.add_cylinder(xf * Transform3D(Basis.IDENTITY, Vector3(side * half, height + 0.25, 0.0)),
			0.38, 0.45, 8, Color("ffd22e"))
	var flags: int = 15
	for i in flags:
		var u0: float = float(i) / float(flags)
		var u1: float = float(i + 1) / float(flags)
		var um: float = (u0 + u1) * 0.5
		var sag0: float = sin(u0 * PI) * 2.1
		var sag1: float = sin(u1 * PI) * 2.1
		var sagm: float = sin(um * PI) * 2.1
		var p0 := Vector3(lerpf(-half, half, u0), height - sag0, 0.0)
		var p1 := Vector3(lerpf(-half, half, u1), height - sag1, 0.0)
		var mid: Vector3 = (p0 + p1) * 0.5
		var dir: Vector3 = p1 - p0
		batch.add_box(xf * Transform3D(Basis(Vector3.BACK, atan2(dir.y, dir.x)), mid),
			Vector3(dir.length() + 0.08, 0.10, 0.10), wire_col)
		# Triangular pennant banner hanging down
		var fx: float = lerpf(-half, half, um)
		var fy: float = height - sagm - 0.72
		batch.add_cone(xf * Transform3D(Basis(Vector3.RIGHT, PI), Vector3(fx, fy, 0.0)),
			0.62, 1.35, 3, flag_cols[i % flag_cols.size()])


# --------------------------------------------------------------------------
# 6. Glowing Track Chevron Speed Arrows (bg_hero_glacier & bg_hero_canyon!)
# --------------------------------------------------------------------------


static func build_track_chevrons(parent: Node3D, spline: RefCounted,
		count: int = 18, color: Color = Color("ffe052")) -> Node3D:
	## Warm golden racing guide chevron arrows painted flush above the road,
	## pointing strictly FORWARD (-Z along travel tangent).
	if parent == null or spline == null:
		return null
	var total: float = maxf(float(spline.total_length), 1.0)
	var batch := PropBatch.new()
	for i in count:
		var s: float = total * (float(i) + 0.4) / float(count)
		var frame: Dictionary = spline.call("sample", s)
		var pos: Vector3 = frame["position"] as Vector3
		var fw: Vector3 = frame["forward"] as Vector3
		fw.y = 0.0
		if fw.length_squared() < 0.001:
			continue
		fw = fw.normalized()
		var yaw: float = atan2(-fw.x, -fw.z)
		var xf := Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0.0, 0.09, 0.0))
		for k in 3:
			var z_off: float = float(k - 1) * 2.1
			for side: float in [-1.0, 1.0]:
				# -side * 0.58 angles outer tips back (+Z) so the center apex points FORWARD (-Z)!
				var wing_xf := xf * Transform3D(Basis(Vector3.UP, -side * 0.58),
					Vector3(side * 1.10, 0.0, z_off))
				batch.add_box(wing_xf, Vector3(2.45, 0.04, 0.48), color)
	var mi := MeshInstance3D.new()
	mi.name = "GlowingTrackChevrons"
	mi.mesh = batch.build()
	mi.material_override = _emissive_mat(color, 2.2)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# --------------------------------------------------------------------------
# 7. Neon Twilight Knockout Octagon Perimeter Lights & Floodlight Towers (bg_hero_arena!)
# --------------------------------------------------------------------------


static func build_neon_arena_ring(parent: Node3D, radius: float,
		y_level: float, sides: int = 8,
		col_a: Color = Color("ff3ec9"), col_b: Color = Color("ffd22e")) -> Node3D:
	## Glowing magenta & gold neon under-rim strips + towering angled multi-bulb
	## stadium floodlight towers casting golden spotlight beams down onto the arena!
	if parent == null:
		return null
	var root := Node3D.new()
	root.name = "NeonArenaSpectacle"
	parent.add_child(root)

	var frame_batch := PropBatch.new()
	var neon_a := PropBatch.new()
	var neon_b := PropBatch.new()
	var bulb_batch := PropBatch.new()
	var beam_mat := _emissive_mat(Color("fff0b8"), 0.85, true, 0.052)

	# Glowing magenta/gold rim strips around all 8 sides of the arena deck
	for i in sides:
		var a0: float = TAU * float(i) / float(sides) + PI / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides) + PI / float(sides)
		var p0 := Vector3(cos(a0) * radius, y_level - 0.10, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, y_level - 0.10, sin(a1) * radius)
		var mid: Vector3 = (p0 + p1) * 0.5
		var edge: Vector3 = p1 - p0
		var edge_len: float = edge.length()
		var yaw: float = atan2(-edge.z, edge.x)
		var exf := Transform3D(Basis(Vector3.UP, yaw), mid)
		var target_b: PropBatch = neon_a if i % 2 == 0 else neon_b
		target_b.add_box(exf, Vector3(edge_len * 0.94, 0.24, 0.34), col_a if i % 2 == 0 else col_b)
		# Glowing neon corner pylon accents
		target_b.add_box(Transform3D(Basis(Vector3.UP, a0), Vector3(p0.x, y_level + 0.55, p0.z)),
			Vector3(0.32, 1.35, 0.32), col_a if i % 2 == 0 else col_b)

	# 4 Towering Angled Multi-Bulb Stadium Floodlight Towers outside the drop zone
	var tower_r: float = radius + 14.5
	for t in 4:
		var ang: float = TAU * float(t) / 4.0 + PI * 0.25
		var base_pos := Vector3(cos(ang) * tower_r, y_level - 18.0, sin(ang) * tower_r)
		var inward_yaw: float = atan2(-cos(ang), -sin(ang))
		var txf := Transform3D(Basis(Vector3.UP, inward_yaw), base_pos)
		frame_batch.add_box(txf * Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0.0, 17.5, -1.5)),
			Vector3(1.1, 36.0, 1.1), Color("23273d"))
		var head_xf := txf * Transform3D(Basis(Vector3.RIGHT, 0.55), Vector3(0.0, 35.5, -3.6))
		frame_batch.add_box(head_xf, Vector3(9.4, 5.2, 1.0), Color("1b1f33"))
		for row in 2:
			for col in 5:
				var bx: float = lerpf(-3.4, 3.4, float(col) / 4.0)
				var by: float = -1.1 if row == 0 else 1.1
				bulb_batch.add_box(head_xf * Transform3D(Basis.IDENTITY, Vector3(bx, by, 0.58)),
					Vector3(1.2, 1.2, 0.24), Color("fff7cf"))
		# Subtle upper atmospheric floodlight halo cone (never obscures camera!)
		var cone := CylinderMesh.new()
		cone.top_radius = 3.0
		cone.bottom_radius = 9.2
		cone.height = 19.0
		cone.radial_segments = 12
		var beam := MeshInstance3D.new()
		beam.mesh = cone
		beam.material_override = beam_mat
		beam.transform = txf * Transform3D(Basis(Vector3.RIGHT, -0.58), Vector3(0.0, 29.0, 4.5))
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(beam)

	frame_batch.flush_to(root, "FloodlightTowers", false, SceneryKit.vertex_material())
	neon_a.flush_to(root, "NeonStripMagenta", false, _emissive_mat(col_a, 3.4))
	neon_b.flush_to(root, "NeonStripGold", false, _emissive_mat(col_b, 3.2))
	bulb_batch.flush_to(root, "FloodlightBulbs", false, _emissive_mat(Color("fff8d4"), 4.0))
	return root


static func _clear_of_samples(position: Vector3, samples: PackedVector3Array,
		clearance: float) -> bool:
	var flat := Vector2(position.x, position.z)
	var c2: float = clearance * clearance
	for sample: Vector3 in samples:
		var dx: float = flat.x - sample.x
		var dz: float = flat.y - sample.z
		if dx * dx + dz * dz < c2:
			return false
	return true
