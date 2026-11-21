## Static 3D arena builder for KNOCKOUT (Bumper Royale).
##
## Builds three genuinely distinct cartoon 3D arenas with zero photoreal PBR
## textures: all geometry uses merged vertex-colour ArrayMeshes via PropBatch /
## SceneryKit plus batched CC0 Kenney Racing & Nature kit models, with explicit
## CollisionLayers.WORLD StaticBody3D colliders on every solid surface.
##
## Arenas:
##   1. "ko_rooftop" — SKYTOP HELIPAD: high-altitude octagonal skyscraper pad
##      above a cartoon skyline & cloud deck, with a +1.8 m central Radar Dome
##      plateau (4-way ramps) and two waves of dropping outer deck sectors.
##   2. "ko_foundry" — MOLTEN FOUNDRY: twin industrial steel islands split by a
##      9 m central magma chasm, linked by a +2.2 m arched central high bridge
##      and two collapsible low outer catwalks over a y = -3.5 m lava sea.
##   3. "ko_iceberg" — FRACTURED ICEBERG: arctic ocean basin (y = -3.0 m) with a
##      0.48-grip slick central ice sheet, 0.90-grip packed snow rim, 4 angled
##      inward corner jump kickers, and two waves of calving ice-shelf lobes.
extends RefCounted

const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const TileCatalog := preload("res://scripts/minigames/tiles/tile_catalog.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const LandscapeSculptor := preload("res://scripts/minigames/scenery/landscape_sculptor.gd")
const AmbientWorld := preload("res://scripts/minigames/scenery/ambient_world.gd")

const DEFAULT_ID: String = "ko_rooftop"
const ARENA_IDS: PackedStringArray = ["ko_rooftop", "ko_foundry", "ko_iceberg"]

const ARENA_META: Dictionary = {
	"ko_rooftop": {
		"id": "ko_rooftop",
		"name": "SKYTOP HELIPAD",
		"subtitle": "RADAR DOME  ·  DROP DECKS",
		"sky_top": Color("1f7ed4"),
		"sky_horizon": Color("bfe6ff"),
		"ground_bottom": Color("243852"),
		"fog_color": Color("b8e2fc"),
		"fog_density": 0.0009,
		"sun_color": Color("fff5e0"),
		"sun_energy": 1.18,
	},
	"ko_foundry": {
		"id": "ko_foundry",
		"name": "MOLTEN FOUNDRY",
		"subtitle": "TWIN ISLANDS  ·  LAVA CHASM",
		"sky_top": Color("2b161d"),
		"sky_horizon": Color("d65a28"),
		"ground_bottom": Color("38140d"),
		"fog_color": Color("7a2f1b"),
		"fog_density": 0.0016,
		"sun_color": Color("ffcf96"),
		"sun_energy": 1.22,
	},
	"ko_iceberg": {
		"id": "ko_iceberg",
		"name": "FRACTURED ICEBERG",
		"subtitle": "SLICK ICE  ·  CORNER KICKERS",
		"sky_top": Color("2b7ec7"),
		"sky_horizon": Color("dff4ff"),
		"ground_bottom": Color("16527a"),
		"fog_color": Color("d0effc"),
		"fog_density": 0.0011,
		"sun_color": Color("fff2d8"),
		"sun_energy": 1.16,
	},
}


static func ids() -> PackedStringArray:
	return ARENA_IDS


static func resolve(raw_id: String) -> String:
	var key: String = raw_id.strip_edges().to_lower()
	match key:
		"ko_rooftop", "rooftop", "helipad", "skytop", "skytop_helipad":
			return "ko_rooftop"
		"ko_foundry", "foundry", "lava", "molten", "molten_foundry":
			return "ko_foundry"
		"ko_iceberg", "iceberg", "ice", "glacier_ko", "fractured_iceberg":
			return "ko_iceberg"
	return DEFAULT_ID


static func get_arena_meta(arena_id: String) -> Dictionary:
	var clean: String = resolve(arena_id)
	return ARENA_META.get(clean, ARENA_META[DEFAULT_ID]) as Dictionary


static func apply_environment(world: WorldEnvironment, sun: DirectionalLight3D,
		arena_id: String) -> void:
	var meta: Dictionary = get_arena_meta(arena_id)
	if world != null and world.environment != null:
		var env: Environment = world.environment
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sky := env.sky.sky_material as ProceduralSkyMaterial
			sky.sky_top_color = meta.get("sky_top", sky.sky_top_color) as Color
			sky.sky_horizon_color = meta.get("sky_horizon", sky.sky_horizon_color) as Color
			sky.ground_horizon_color = meta.get("sky_horizon", sky.ground_horizon_color) as Color
			sky.ground_bottom_color = meta.get("ground_bottom", sky.ground_bottom_color) as Color
		env.fog_enabled = true
		env.fog_light_color = meta.get("fog_color", env.fog_light_color) as Color
		env.fog_density = float(meta.get("fog_density", 0.0012))
	if sun != null:
		sun.light_color = meta.get("sun_color", Color("fff5e0")) as Color
		sun.light_energy = float(meta.get("sun_energy", 1.15))


static func build_arena(host: Node3D, arena_id: String) -> Dictionary:
	var clean_id: String = resolve(arena_id)
	if host == null:
		var empty_spawns: Array[Transform3D] = []
		var empty_w1: Array[Node3D] = []
		var empty_w2: Array[Node3D] = []
		var empty_zones: Array[Dictionary] = []
		return {
			"id": clean_id,
			"name": str(get_arena_meta(clean_id).get("name", "SKYTOP HELIPAD")),
			"spawns": empty_spawns,
			"ko_y": -2.8,
			"wave1_nodes": empty_w1,
			"wave2_nodes": empty_w2,
			"safe_radius": 21.0,
			"surface_zones": empty_zones,
		}
	var arena: Dictionary
	match clean_id:
		"ko_foundry":
			arena = _build_foundry(host)
		"ko_iceberg":
			arena = _build_iceberg(host)
		_:
			arena = _build_rooftop(host)
	# AmbientWorld needs to know what the arena actually stands on: the rooftop
	# pad floats over a city 64 m down, the foundry pad over a lava sea at -3.5 m
	# and the iceberg over the arctic ocean at -3.0 m. Without this context the
	# ring used to hang mid-air, overlap itself, or plant pines in the water.
	var ambient: Dictionary = {
		"style": "skyline",
		"floor_y": -64.0,
		"radius_in": 58.0,
		"radius_out": 96.0,
	}
	match clean_id:
		"ko_foundry":
			ambient = {"style": "foundry", "floor_y": -3.5,
				"radius_in": 78.0, "radius_out": 112.0}
		"ko_iceberg":
			ambient = {"style": "iceberg", "floor_y": -3.0,
				"radius_in": 50.0, "radius_out": 78.0}
	AmbientWorld.build_arena(host, clean_id, 36.0, ambient)
	_add_dynamic_landmarks(host, clean_id)
	return arena


static func _add_dynamic_landmarks(host: Node3D, clean_id: String) -> void:
	var anim: Dictionary = AmbientWorld.anim_of(host)
	var holder := Node3D.new()
	holder.name = "DynamicLandmarks_" + clean_id
	host.add_child(holder)
	match clean_id:
		"ko_rooftop":
			LandscapeSculptor.build_blimp(holder, Vector3.ZERO, 88.0, 14.0,
				Color("ff595e"), Color("ffd22e"), anim)
			# Spinning radar sweep dish atop the central dome plateau (visual only, well above karts)
			var radar_pivot := Node3D.new()
			radar_pivot.position = Vector3(0.0, 5.2, 0.0)
			holder.add_child(radar_pivot)
			var rb := PropBatch.new()
			rb.add_box(Transform3D(Basis.IDENTITY, Vector3.ZERO),
				Vector3(3.6, 0.42, 0.55), Color("ffd22e"))
			rb.add_box(Transform3D(Basis.IDENTITY, Vector3(1.85, 0.15, 0.0)),
				Vector3(0.45, 0.85, 1.35), Color("38d6f0"))
			rb.flush_to(radar_pivot, "RadarBar", false, SceneryKit.vertex_material())
			if not anim.has("rotators_y"):
				anim["rotators_y"] = []
			(anim["rotators_y"] as Array).append({"node": radar_pivot, "speed": 1.35})
			LandscapeSculptor.add_biome_particles(holder, "stadium", Vector3.ZERO, 55.0)
		"ko_foundry":
			LandscapeSculptor.build_port_crane(holder, Vector3(-64.0, -3.5, -52.0),
				-0.75, 21.0, Color("5c3224"), anim)
			LandscapeSculptor.build_port_crane(holder, Vector3(64.0, -3.5, 52.0),
				2.35, 21.0, Color("4a2a24"), anim)
			LandscapeSculptor.add_biome_particles(holder, "ko_foundry", Vector3.ZERO, 65.0)
		"ko_iceberg":
			LandscapeSculptor.build_lighthouse(holder, Vector3(-76.0, -2.5, -72.0),
				17.0, anim)
			LandscapeSculptor.build_cargo_ship(holder, Vector3(88.0, -3.2, 46.0),
				-0.45, 1.25, anim)
			LandscapeSculptor.build_cargo_ship(holder, Vector3(-96.0, -3.2, 54.0),
				1.9, 1.15, anim)
			LandscapeSculptor.add_biome_particles(holder, "ko_iceberg", Vector3.ZERO, 65.0)


static func is_point_safe(arena_data: Dictionary, point: Vector3,
		wave1_danger: bool, wave2_danger: bool) -> bool:
	var id: String = str(arena_data.get("id", DEFAULT_ID))
	var ax: float = absf(point.x)
	var az: float = absf(point.z)
	match id:
		"ko_foundry":
			# Permanent twin islands + central +2.2 m arched high bridge.
			if ax >= 4.9 and ax <= 16.0 and az <= 16.6:
				return true
			if ax <= 12.6 and az <= 3.8:
				return true
			if not wave2_danger and ax >= 16.0 and ax <= 26.8 and az <= 16.6:
				return true
			if not wave1_danger:
				if ax <= 5.2 and az >= 9.6 and az <= 14.4:
					return true
				if ax >= 4.9 and ax <= 24.5 and az >= 16.6 and az <= 25.2:
					return true
			return false
		"ko_iceberg":
			var r_ice: float = Vector2(point.x, point.z).length()
			if r_ice <= 18.8:
				return true
			if not wave2_danger and r_ice <= 27.4:
				return true
			if not wave1_danger and r_ice <= 35.8:
				return true
			return false
		_:
			var oct_in: float = maxf(maxf(ax, az), (ax + az) * 0.70710678)
			if oct_in <= 19.3:
				return true
			var rad: float = Vector2(point.x, point.z).length()
			var ang: float = fposmod(atan2(point.z, point.x), TAU)
			var sector_idx: int = int(floor((ang + PI / 8.0) / (PI / 4.0))) % 8
			if sector_idx % 2 == 0:
				return (not wave2_danger) and rad <= 31.2
			return (not wave1_danger) and rad <= 34.4


# ==========================================================================
# 1. "ko_rooftop" — SKYTOP HELIPAD
# ==========================================================================

static func _build_rooftop(host: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "Arena_Rooftop"
	host.add_child(root)

	var core_body: StaticBody3D = _solid_body(root, "HelipadCoreBody")
	var core_batch := PropBatch.new()

	var deck_slate := Color("4d5a6e")
	var deck_mid := Color("5b6a80")
	var trim_steel := Color("384453")
	var tower_glass := Color("3a7cb5")
	var tower_frame := Color("6c7f94")
	var yellow_mark := UiPalette.YELLOW
	var white_mark := Color("f7fbff")
	var red_accent := Color("e84848")
	var dome_teal := Color("3699b8")

	# Permanent octagonal inner helipad core (circumradius 22.0 m, inradius 20.32 m).
	var r_core: float = 22.0
	_add_octagon_slab(core_batch, core_body, Vector3.ZERO, r_core, -2.2, 0.0,
		deck_slate, trim_steel)

	# Massive skyscraper support shaft descending below the helipad into the clouds.
	var shaft_r: float = 18.2
	for tier: int in 5:
		var y_top: float = -2.2 - float(tier) * 6.8
		var y_bot: float = y_top - 6.6
		var col_band: Color = tower_glass if tier % 2 == 0 else tower_frame
		_add_ring_sector(core_batch, 0.0, shaft_r, y_bot, y_top,
			0.0, TAU, 8, trim_steel, col_band)
	for pilaster: int in 8:
		var ang: float = TAU * float(pilaster) / 8.0 + PI / 8.0
		var p_pos := Vector3(cos(ang) * 18.0, -18.5, sin(ang) * 18.0)
		core_batch.add_box(Transform3D(Basis(Vector3.UP, -ang), p_pos),
			Vector3(1.8, 33.0, 2.2), trim_steel.lightened(0.12))

	# Helipad aviation markings on the permanent inner deck (y = +0.02 m).
	_add_ring_sector(core_batch, 15.2, 16.1, 0.0, 0.022, 0.0, TAU, 32,
		yellow_mark, yellow_mark)
	_add_ring_sector(core_batch, 18.9, 19.4, 0.0, 0.020, 0.0, TAU, 8,
		white_mark, white_mark)
	# Giant "H" flanking the central radar dome plateau.
	for sx: float in [-1.0, 1.0]:
		core_batch.add_box(Transform3D(Basis.IDENTITY, Vector3(sx * 13.4, 0.015, 0.0)),
			Vector3(1.15, 0.025, 9.6), white_mark)
	for sz: float in [-1.0, 1.0]:
		core_batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.015, sz * 13.4)),
			Vector3(9.6, 0.025, 1.15), yellow_mark)

	# Central Raised +1.8 m Radar Dome Plateau + 4-way smooth ramps.
	var plat_r: float = 6.3
	var plat_h: float = 1.8
	_add_octagon_slab(core_batch, core_body, Vector3.ZERO, plat_r, 0.0, plat_h,
		deck_mid, trim_steel)
	_add_ring_sector(core_batch, 5.4, 5.95, plat_h, plat_h + 0.025, 0.0, TAU, 16,
		yellow_mark, yellow_mark)

	# Four smooth cardinal ramps (N, S, E, W) rising 0.0 -> +1.8 m toward (0,0,0).
	# Local +Z of _add_ramp_wedge climbs UP, so yaw points local +Z toward (0,0,0):
	#   North ramp at (0, 0, -9.15) climbs +Z (yaw = 0.0)
	#   South ramp at (0, 0, +9.15) climbs -Z (yaw = PI)
	#   West ramp  at (-9.15, 0, 0) climbs +X (yaw = PI * 0.5)
	#   East ramp  at (+9.15, 0, 0) climbs -X (yaw = -PI * 0.5)
	var ramp_specs: Array[Dictionary] = [
		{"pos": Vector3(0.0, 0.0, -9.15), "yaw": 0.0},
		{"pos": Vector3(0.0, 0.0, 9.15), "yaw": PI},
		{"pos": Vector3(-9.15, 0.0, 0.0), "yaw": PI * 0.5},
		{"pos": Vector3(9.15, 0.0, 0.0), "yaw": -PI * 0.5},
	]
	for spec: Dictionary in ramp_specs:
		var r_pos: Vector3 = spec["pos"] as Vector3
		var r_yaw: float = float(spec["yaw"])
		_add_ramp_wedge(core_batch, core_body, r_pos, r_yaw, 5.4, 6.7,
			plat_h, 0.0, deck_mid.lightened(0.08), trim_steel, yellow_mark)

	# Central solid Radar Dome hub (radius 1.65 m on top of +1.8 m plateau, leaving
	# 4.65 m of clear elevated circular roadway all around it).
	core_batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, plat_h + 0.35, 0.0)),
		1.72, 0.70, 14, dome_teal)
	core_batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, plat_h + 1.05, 0.0)),
		1.48, 0.85, 14, white_mark)
	_add_cone(core_batch, Transform3D(Basis.IDENTITY, Vector3(0.0, plat_h + 1.48, 0.0)),
		1.48, 0.95, 14, white_mark.darkened(0.04))
	core_batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, plat_h + 2.85, 0.0)),
		0.14, 1.1, 8, red_accent)
	_add_cylinder_collider(core_body, Vector3(0.0, plat_h, 0.0), 1.72, 3.2)

	_emit_batch_mesh(root, core_batch, "HelipadCoreMesh", true)

	# Kenney Racing accents on cantilevered outer light trusses (clear outside drop zone)
	# and radar dish atop the central dome.
	var radar_xforms: Array = [
		_fit_model("radarEquipment", Vector3(0.0, plat_h + 2.35, 0.0), 0.4, Vector3.ONE * 5.2),
	]
	_batch_model(root, "radarEquipment", radar_xforms, "RadarDish", true, false)

	var light_xforms: Array = []
	var truss_batch := PropBatch.new()
	for i: int in 4:
		var ang: float = TAU * float(i) / 4.0 + PI * 0.25
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var radial_yaw: float = atan2(dir.x, dir.z)
		var post_spot: Vector3 = dir * 44.5 + Vector3.UP * (-1.4)
		# Horizontal steel cantilever truss from central core (r = 16 m) to pod (r = 44.5 m)
		truss_batch.add_box(Transform3D(Basis(Vector3.UP, radial_yaw),
			dir * 30.25 + Vector3.UP * (-1.7)),
			Vector3(1.4, 0.85, 29.0), trim_steel)
		# Angled underside brace strut tying cantilever back down into the shaft
		var brace_start: Vector3 = dir * 18.0 + Vector3.UP * (-10.5)
		var brace_end: Vector3 = dir * 42.5 + Vector3.UP * (-1.8)
		var brace_mid: Vector3 = (brace_start + brace_end) * 0.5
		var brace_len: float = brace_start.distance_to(brace_end)
		var brace_pitch: float = atan2(brace_end.y - brace_start.y, 24.5)
		truss_batch.add_box(Transform3D(Basis(Vector3.UP, radial_yaw) * Basis(Vector3.RIGHT, -brace_pitch),
			brace_mid), Vector3(0.75, 0.65, brace_len), trim_steel.darkened(0.1))
		truss_batch.add_cylinder(Transform3D(Basis.IDENTITY, post_spot + Vector3.UP * 0.35),
			2.1, 0.7, 10, deck_mid)
		light_xforms.append(_fit_model("lightPostModern",
			post_spot + Vector3.UP * 0.7, -ang + PI, Vector3.ONE * 13.0))
	_emit_batch_mesh(root, truss_batch, "SpotlightTrusses", false)
	_batch_model(root, "lightPostModern", light_xforms, "PerimeterSpotlights", false, false)

	# Wave 2: 4 outer cardinal edge trapezoidal slabs (E, S, W, N, r = 22.08 .. 34.6 m).
	var wave2_nodes: Array[Node3D] = []
	for idx: int in 4:
		var mid_ang: float = float(idx) * (PI * 0.5)
		var a0: float = mid_ang - PI / 8.0 + 0.014
		var a1: float = mid_ang + PI / 8.0 - 0.014
		var sec: Node3D = _make_ring_wedge_sector(
			root, "Wave2_Cardinal_%d" % idx,
			22.08, 34.6, -1.5, 0.0, a0, a1, 1,
			Color("465366"), trim_steel, yellow_mark, true)
		wave2_nodes.append(sec)

	# Wave 1: 4 outer diagonal corner deck wedges (SE, SW, NW, NE, r = 22.08 .. 38.2 m).
	var wave1_nodes: Array[Node3D] = []
	for idx: int in 4:
		var mid_ang: float = PI * 0.25 + float(idx) * (PI * 0.5)
		var a0: float = mid_ang - PI / 8.0 + 0.014
		var a1: float = mid_ang + PI / 8.0 - 0.014
		var sec: Node3D = _make_ring_wedge_sector(
			root, "Wave1_Corner_%d" % idx,
			22.08, 38.2, -1.4, 0.0, a0, a1, 1,
			Color("516075"), trim_steel, red_accent, true)
		wave1_nodes.append(sec)

	# Distant skyline of cartoon skyscraper towers + fluffy clouds (> 260 m span so
	# preview_render frames tightly on the helipad while keeping a rich backdrop).
	_build_rooftop_skyline(root)

	# 8 symmetric inward-facing spawns on the permanent helipad ring (r = 15.6 m).
	var spawns: Array[Transform3D] = _radial_spawns(8, 15.6, 0.38)
	var surface_zones: Array[Dictionary] = []

	return {
		"id": "ko_rooftop",
		"name": "SKYTOP HELIPAD",
		"subtitle": "RADAR DOME  ·  DROP DECKS",
		"spawns": spawns,
		"ko_y": -2.8,
		"wave1_nodes": wave1_nodes,
		"wave2_nodes": wave2_nodes,
		"safe_radius": 20.2,
		"surface_zones": surface_zones,
		"base_grip": 0.96,
		"chasm_half_x": 0.0,
	}


static func _build_rooftop_skyline(root: Node3D) -> void:
	var horizon := PropBatch.new()
	var palette: Array[Color] = [
		Color("355c8a"), Color("436d9e"), Color("2f4b6e"),
		Color("5278a3"), Color("3d6487"), Color("5d7187"),
	]
	var window_glow := Color("ffe699")
	var roof_col := Color("2b3645")
	var tower_count: int = 24
	for i: int in tower_count:
		var ang: float = TAU * float(i) / float(tower_count) + 0.13
		var dist: float = 108.0 + float((i * 7) % 5) * 16.0
		var tx: float = cos(ang) * dist
		var tz: float = sin(ang) * dist
		var w: float = 14.0 + float((i * 3) % 4) * 4.5
		var d: float = 14.0 + float((i * 5) % 4) * 4.5
		var top_y: float = -4.0 + float((i * 11) % 7) * 5.2
		var bot_y: float = -68.0
		var h: float = top_y - bot_y
		var col: Color = palette[i % palette.size()]
		var yaw: float = float(i) * 0.35
		var basis := Basis(Vector3.UP, yaw)
		horizon.add_box(Transform3D(basis, Vector3(tx, bot_y + h * 0.5, tz)),
			Vector3(w, h, d), col)
		horizon.add_box(Transform3D(basis, Vector3(tx, top_y + 0.6, tz)),
			Vector3(w * 0.84, 1.2, d * 0.84), roof_col)
		# Lit cartoon horizontal window bands near tower crown.
		for band: int in 3:
			var wy: float = top_y - 3.2 - float(band) * 4.2
			horizon.add_box(Transform3D(basis, Vector3(tx, wy, tz)),
				Vector3(w + 0.25, 0.9, d * 0.72), window_glow)
		if i % 3 == 0:
			horizon.add_cylinder(Transform3D(Basis.IDENTITY,
				Vector3(tx, top_y + 4.5, tz)), 0.35, 7.8, 6, Color("d94848"))

	# Fluffy cartoon cloud clusters drifting below the rooftop (-9 m .. -18 m).
	# They live in their own unshaded batch: the sunset light turned the shared
	# lit batch muddy brown, which read as floating islands instead of clouds.
	var cloud_batch := PropBatch.new()
	var cloud_white := Color("f2f9ff")
	var cloud_shade := Color("d5eafa")
	for c: int in 18:
		var ang: float = TAU * float(c) / 18.0 + 0.22
		var dist: float = 68.0 + float((c * 5) % 6) * 15.0
		var cy: float = -10.5 - float(c % 4) * 2.4
		var center := Vector3(cos(ang) * dist, cy, sin(ang) * dist)
		cloud_batch.add_cylinder(Transform3D(Basis.IDENTITY, center),
			11.5, 2.8, 10, cloud_white)
		cloud_batch.add_cylinder(Transform3D(Basis.IDENTITY,
			center + Vector3(6.5, 0.8, -3.0)), 8.2, 2.6, 9, cloud_white)
		cloud_batch.add_cylinder(Transform3D(Basis.IDENTITY,
			center + Vector3(-6.0, -0.5, 3.5)), 8.8, 2.2, 9, cloud_shade)
	_emit_batch_mesh(root, cloud_batch, "CloudDeck", false, true)

	# Deep city floor haze plate far below (-64 m) + outer tiered skyscrapers.
	var sky_rng := RandomNumberGenerator.new()
	sky_rng.seed = 81921
	for j: int in 24:
		var ang2: float = TAU * float(j) / 24.0 + 0.08
		var dist2: float = 165.0 + float((j * 5) % 4) * 24.0
		var sw: float = 18.0 + float(j % 3) * 6.0
		var sh: float = 64.0 + float((j * 7) % 5) * 14.0
		LandscapeSculptor.add_skyscraper(horizon,
			Vector3(cos(ang2) * dist2, -64.0, sin(ang2) * dist2),
			float(j) * 0.42, sw, sw * 0.9, sh,
			palette[(j + 2) % palette.size()], window_glow, sky_rng)

	var abyss := MeshInstance3D.new()
	abyss.name = "CityAbyssPlane"
	var abyss_plane := PlaneMesh.new()
	abyss_plane.size = Vector2(1150.0, 1150.0)
	abyss.mesh = abyss_plane
	abyss.position = Vector3(0.0, -64.0, 0.0)
	abyss.material_override = _flat_material(Color("223954"), true)
	abyss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(abyss)

	_emit_batch_mesh(root, horizon, "SkylineBackdrop", false)


# ==========================================================================
# 2. "ko_foundry" — MOLTEN FOUNDRY
# ==========================================================================

static func _build_foundry(host: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "Arena_Foundry"
	host.add_child(root)

	var core_body: StaticBody3D = _solid_body(root, "FoundryCoreBody")
	var core_batch := PropBatch.new()

	var steel_dark := Color("5b5660")
	var steel_deck := Color("736c78")
	var iron_rib := Color("454049")
	var slag_trim := Color("9a6040")
	var hazard_amber := Color("ff9e2c")
	var magma_bright := Color("ff5e1a")
	var magma_gold := Color("ffbe2e")

	# Glowing cartoon magma sea at y = -3.5 m (1100 m seamless horizon).
	var lava := MeshInstance3D.new()
	lava.name = "MagmaSea"
	var lava_plane := PlaneMesh.new()
	lava_plane.size = Vector2(1100.0, 1100.0)
	lava.mesh = lava_plane
	lava.position = Vector3(0.0, -3.5, 0.0)
	var lava_mat := StandardMaterial3D.new()
	lava_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lava_mat.albedo_color = Color("a8340f")
	lava.material_override = lava_mat
	lava.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lava)

	# Bright molten crust ribbons in the central 9 m lava chasm (y = -3.44 m).
	var crust_batch := PropBatch.new()
	for idx: int in 9:
		var lz: float = -32.0 + float(idx) * 8.0
		var lx: float = sin(float(idx) * 1.7) * 1.6
		crust_batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(lx, -3.45, lz)),
			2.6 + float(idx % 3) * 0.8, 0.08, 10, magma_gold)
	_emit_batch_mesh(root, crust_batch, "MagmaGlowPools", false, true)

	# Twin Permanent Main Steel Islands:
	# West Core: x in [-16.8, -4.5], z in [-17.5, +17.5] (9.0 m central chasm!).
	# East Core: x in [+4.5, +16.8], z in [-17.5, +17.5].
	var island_w: float = 12.3
	var island_len: float = 35.0
	var island_h: float = 3.8
	for side: float in [-1.0, 1.0]:
		var cx: float = side * (4.5 + island_w * 0.5)
		var center := Vector3(cx, -island_h * 0.5, 0.0)
		var size := Vector3(island_w, island_h, island_len)
		core_batch.add_box(Transform3D(Basis.IDENTITY, center), size, steel_deck)
		_add_box_collider(core_body, Transform3D(Basis.IDENTITY, center), size)
		# Glowing chasm-side warning stripe along x = +-4.7 m.
		core_batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(side * 4.75, 0.016, 0.0)),
			Vector3(0.45, 0.025, island_len - 0.6), hazard_amber)
		# Foundry floor grate panels.
		for gz: float in [-11.5, 11.5]:
			core_batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(cx, 0.014, gz)),
				Vector3(6.4, 0.022, 6.4), steel_dark)
		# Heavy iron support columns descending into the magma sea.
		for pz: float in [-13.5, 0.0, 13.5]:
			core_batch.add_cylinder(Transform3D(Basis.IDENTITY,
				Vector3(cx, -2.6, pz)), 1.6, 2.8, 10, iron_rib)

	# Central +2.2 m Arched High Bridge spanning the 9.0 m chasm (x = -4.8 .. +4.8,
	# width = 8.4 m) + West & East ramps.
	var bridge_h: float = 2.2
	var bridge_w: float = 8.4
	var span_x: float = 9.6
	var deck_thick: float = 0.65
	var deck_center := Vector3(0.0, bridge_h - deck_thick * 0.5, 0.0)
	core_batch.add_box(Transform3D(Basis.IDENTITY, deck_center),
		Vector3(span_x, deck_thick, bridge_w), steel_deck.lightened(0.08))
	_add_box_collider(core_body, Transform3D(Basis.IDENTITY, deck_center),
		Vector3(span_x, deck_thick, bridge_w))

	# Dramatic iron arch ribs under the high bridge + low 0.18 m side kerbs (low
	# enough that slammed rivals fly sideways straight off into the central lava!).
	for sz: float in [-1.0, 1.0]:
		var kz: float = sz * (bridge_w * 0.5 - 0.22)
		core_batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, bridge_h + 0.09, kz)),
			Vector3(span_x, 0.18, 0.42), hazard_amber)
		_add_box_collider(core_body, Transform3D(Basis.IDENTITY,
			Vector3(0.0, bridge_h + 0.09, kz)),
			Vector3(span_x, 0.18, 0.42))
		# Arch struts below deck.
		core_batch.add_box(Transform3D(Basis(Vector3.BACK, 0.34),
			Vector3(-3.1, 0.95, kz)), Vector3(4.2, 0.45, 0.55), slag_trim)
		core_batch.add_box(Transform3D(Basis(Vector3.BACK, -0.34),
			Vector3(3.1, 0.95, kz)), Vector3(4.2, 0.45, 0.55), slag_trim)

	# West & East ramps up to the +2.2 m high bridge:
	# West ramp centered at x = -8.55 (spans -12.4 .. -4.7), climbs +X (yaw = PI * 0.5).
	# East ramp centered at x = +8.55 (spans +4.7 .. +12.4), climbs -X (yaw = -PI * 0.5).
	_add_ramp_wedge(core_batch, core_body, Vector3(-8.55, 0.0, 0.0), PI * 0.5,
		bridge_w, 7.7, bridge_h, 0.0, steel_deck.lightened(0.06), iron_rib, hazard_amber)
	_add_ramp_wedge(core_batch, core_body, Vector3(8.55, 0.0, 0.0), -PI * 0.5,
		bridge_w, 7.7, bridge_h, 0.0, steel_deck.lightened(0.06), iron_rib, hazard_amber)

	_emit_batch_mesh(root, core_batch, "FoundryCoreMesh", true)

	# Wave 1: 2 Outer Low Catwalks across the 9 m chasm + 4 North/South End Aprons.
	var wave1_nodes: Array[Node3D] = []
	for cat_idx: int in 2:
		var cz: float = -12.2 if cat_idx == 0 else 12.2
		var catwalk: Node3D = _make_box_sector(
			root, "Wave1_Catwalk_%d" % cat_idx,
			Vector3(0.0, 0.0, cz), 0.0,
			Vector3(9.4, 0.65, 5.4),
			Color("594c47"), iron_rib, magma_bright,
			false, 0.0)
		wave1_nodes.append(catwalk)

	var apron_idx: int = 0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var ax: float = sx * (4.5 + 20.5 * 0.5)
			var az: float = sz * (17.5 + 8.6 * 0.5)
			var apron: Node3D = _make_box_sector(
				root, "Wave1_Apron_%d" % apron_idx,
				Vector3(ax, 0.0, az), 0.0 if sz > 0.0 else PI,
				Vector3(20.5, 2.2, 8.6),
				Color("54484d"), iron_rib, hazard_amber,
				true, 0.20)
			wave1_nodes.append(apron)
			apron_idx += 1

	# Wave 2: 4 Outer West & East Wings (|x| = 16.8 .. 27.6 m, split N/S).
	var wave2_nodes: Array[Node3D] = []
	var wing_idx: int = 0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var wx: float = sx * (16.8 + 10.8 * 0.5)
			var wz: float = sz * (17.5 * 0.5)
			var wing_yaw: float = PI * 0.5 if sx > 0.0 else -PI * 0.5
			var wing: Node3D = _make_box_sector(
				root, "Wave2_Wing_%d" % wing_idx,
				Vector3(wx, 0.0, wz), wing_yaw,
				Vector3(17.5, 2.4, 10.8),
				Color("423c45"), iron_rib, magma_gold,
				true, 0.20)
			wave2_nodes.append(wing)
			wing_idx += 1

	# Industrial smelter perimeter & distant cavern backdrop.
	_build_foundry_scenery(root)

	# 8 symmetric spawns: 4 on West Core Island, 4 on East Core Island, facing inward.
	var spawns: Array[Transform3D] = []
	var z_slots: Array[float] = [-11.5, -5.8, 5.8, 11.5]
	for i: int in 4:
		var zp: float = z_slots[i]
		var w_pos := Vector3(-13.4, 0.38, zp)
		var e_pos := Vector3(13.4, 0.38, -zp)
		spawns.append(_look_inward(w_pos, Vector3(0.0, 0.38, zp * 0.25)))
		spawns.append(_look_inward(e_pos, Vector3(0.0, 0.38, -zp * 0.25)))

	var surface_zones: Array[Dictionary] = []
	return {
		"id": "ko_foundry",
		"name": "MOLTEN FOUNDRY",
		"subtitle": "TWIN ISLANDS  ·  LAVA CHASM",
		"spawns": spawns,
		"ko_y": -3.05,
		"wave1_nodes": wave1_nodes,
		"wave2_nodes": wave2_nodes,
		"safe_radius": 18.0,
		"surface_zones": surface_zones,
		"base_grip": 0.94,
		"chasm_half_x": 4.5,
	}


static func _build_foundry_scenery(root: Node3D) -> void:
	# Close industrial crucibles & gantries just outside the islands (~42..48 m)
	# so preview_render frames the twin islands + pouring crucibles dramatically.
	var near_batch := PropBatch.new()
	var dark_iron := Color("252026")
	var rust_steel := Color("5e3829")
	var molten_orange := Color("ff6a1a")
	var molten_core := Color("ffd438")

	for side_z: float in [-1.0, 1.0]:
		# Overhead crane gantries sit well outside the play arena so they frame
		# the islands instead of cutting across the camera view.
		var gz: float = side_z * 78.0
		for sx: float in [-1.0, 1.0]:
			# Pillars stand flush in the magma sea (y = -3.5): 13.5 m tall
			# centered at 2.75 so the base is buried, not floating.
			near_batch.add_box(Transform3D(Basis.IDENTITY, Vector3(sx * 30.0, 2.75, gz)),
				Vector3(2.4, 13.5, 2.4), dark_iron)
		near_batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 10.2, gz)),
			Vector3(42.0, 1.8, 2.8), rust_steel)
		# Suspended pouring crucible over the central lava chasm!
		near_batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 9.2, gz)),
			2.8, 4.0, 12, dark_iron)
		near_batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 11.0, gz)),
			2.4, 0.7, 12, molten_core)
		# Glowing molten stream pouring straight down into the magma sea!
		near_batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.9, gz * 0.96)),
			0.7, 11.5, 10, molten_orange)
		near_batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, -3.35, gz * 0.96)),
			3.2, 0.25, 12, molten_core)
	_emit_batch_mesh(root, near_batch, "FoundryCrucibles", false)

	var light_xforms: Array = []
	var pylon_xforms: Array = []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			light_xforms.append(_fit_model("lightPostLarge",
				Vector3(sx * 36.0, -3.4, sz * 34.0),
				atan2(-sx, -sz), Vector3.ONE * 16.0))
			pylon_xforms.append(_fit_model("pylon",
				Vector3(sx * 42.0, -3.4, sz * 12.0),
				0.0, Vector3.ONE * 15.0))
	_batch_model(root, "lightPostLarge", light_xforms, "FoundryLights", false, false)
	_batch_model(root, "pylon", pylon_xforms, "FoundryPylons", false, false)

	# Ring of sculpted volcanic caldera peaks + industrial smelter chimneys.
	var far_batch := PropBatch.new()
	var cavern_rock := Color("3a221e")
	var pipe_grey := Color("554a50")
	var volc_rng := RandomNumberGenerator.new()
	volc_rng.seed = 66109
	for v: int in 14:
		var vang: float = TAU * float(v) / 14.0 + 0.17
		var vdist: float = 128.0 + float(v % 3) * 32.0
		LandscapeSculptor.add_volcanic_peak(far_batch,
			Vector3(cos(vang) * vdist, -3.5, sin(vang) * vdist),
			28.0 + float(v % 4) * 7.5, 34.0 + float(v % 3) * 14.0, volc_rng)
	for i: int in 14:
		var ang: float = TAU * float(i) / 14.0
		var dist: float = 195.0 + float((i * 3) % 4) * 24.0
		var px: float = cos(ang) * dist
		var pz: float = sin(ang) * dist
		var h: float = 28.0 + float((i * 7) % 5) * 5.0
		far_batch.add_cylinder(Transform3D(Basis.IDENTITY,
			Vector3(px, h * 0.5 - 4.0, pz)),
			7.5, h, 8, pipe_grey if i % 2 == 0 else cavern_rock)
		if i % 2 == 0:
			far_batch.add_cylinder(Transform3D(Basis.IDENTITY,
				Vector3(px, h - 3.6, pz)), 8.2, 1.2, 8, molten_orange)
	_emit_batch_mesh(root, far_batch, "FoundryCavernHorizon", false)


# ==========================================================================
# 3. "ko_iceberg" — FRACTURED ICEBERG
# ==========================================================================

static func _build_iceberg(host: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "Arena_Iceberg"
	host.add_child(root)

	var core_body: StaticBody3D = _solid_body(root, "GlacierCoreBody")
	var core_batch := PropBatch.new()

	var snow_white := Color("f2f9ff")
	var snow_ridge := Color("dfeffa")
	var ice_slick := Color("7fd4f2")
	var ice_highlight := Color("aee8fc")
	var ice_wall := Color("4ca6cf")
	var ice_deep := Color("2b7aa3")
	var kicker_accent := Color("2994c4")

	# Bright Arctic Ocean Basin at y = -3.0 m (1100 m seamless sea horizon).
	var ocean := MeshInstance3D.new()
	ocean.name = "ArcticOcean"
	var ocean_plane := PlaneMesh.new()
	ocean_plane.size = Vector2(1100.0, 1100.0)
	ocean.mesh = ocean_plane
	ocean.position = Vector3(0.0, -3.0, 0.0)
	ocean.material_override = _flat_material(Color("1c84b8"), false)
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ocean)

	# Sea-foam ring around the glacier shelf base (y = -2.95 m).
	var foam_batch := PropBatch.new()
	_add_ring_sector(foam_batch, 19.0, 41.5, -2.97, -2.93, 0.0, TAU, 24,
		Color("9ce3fa"), Color("6bc8eb"))
	_emit_batch_mesh(root, foam_batch, "ArcticFoamRing", false)

	# Permanent Central Glacier Core (circumradius 21.0 m, submerged keel to -3.2 m).
	var r_core: float = 21.0
	_add_octagon_slab(core_batch, core_body, Vector3.ZERO, r_core, -3.2, 0.0,
		snow_white, ice_wall)

	# Central 0.48-grip Slick Blue-Crystal Ice Sheet (radius 15.2 m, y = +0.018 m).
	_add_ring_sector(core_batch, 0.0, 15.2, 0.0, 0.018, 0.0, TAU, 24,
		ice_slick, ice_wall)
	_add_ring_sector(core_batch, 6.2, 6.65, 0.0, 0.024, 0.0, TAU, 16,
		ice_highlight, ice_highlight)
	_add_ring_sector(core_batch, 14.7, 15.35, 0.0, 0.026, 0.0, TAU, 24,
		snow_white, snow_white)
	# Geometric frost fracture lines across the slick ice core.
	for crack: int in 4:
		var c_ang: float = float(crack) * PI * 0.25 + 0.2
		core_batch.add_box(Transform3D(Basis(Vector3.UP, c_ang),
			Vector3(0.0, 0.022, 0.0)),
			Vector3(0.28, 0.012, 26.0), ice_highlight)

	# 0.90-grip Packed Snow Ridge visual bolsters around the permanent rim (r = 15.4 .. 20.0 m).
	# Offset by half a segment so the 8 bolsters sit BETWEEN the 4 diagonal
	# kickers instead of slicing through their decks.
	for seg: int in 8:
		var s_ang: float = TAU * float(seg) / 8.0 + PI / 8.0
		var r_pos := Vector3(cos(s_ang) * 18.6, 0.02, sin(s_ang) * 18.6)
		core_batch.add_box(Transform3D(Basis(Vector3.UP, -s_ang), r_pos),
			Vector3(2.6, 0.04, 6.0), snow_ridge)

	# 4 Angled Inward Jump Ramps (Corner Kickers) at the 4 diagonal corners
	# (r = 16.5 m, angled INWARD so karts launch toward (0,0,0) across the ice!).
	for idx: int in 4:
		var ang: float = PI * 0.25 + float(idx) * PI * 0.5
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var kicker_pos: Vector3 = dir * 16.4
		# Local +Z of _add_ramp_wedge climbs UP; point local +Z toward -dir (inward):
		var inward_yaw: float = atan2(-dir.x, -dir.z)
		_add_ramp_wedge(core_batch, core_body, kicker_pos, inward_yaw,
			4.8, 4.2, 0.92, 0.0, snow_white, ice_wall, kicker_accent)

	_emit_batch_mesh(root, core_batch, "GlacierCoreMesh", true)

	# Wave 2: 4 Secondary Ice Rim Quadrant Sectors (r = 21.08 .. 29.2 m, aligned to octagon faces).
	var wave2_nodes: Array[Node3D] = []
	for idx: int in 4:
		var a0: float = float(idx) * PI * 0.5 - PI / 8.0 + 0.016
		var a1: float = a0 + PI * 0.5 - 0.032
		var sec: Node3D = _make_ring_wedge_sector(
			root, "Wave2_IceRim_%d" % idx,
			21.08, 29.2, -2.6, 0.0, a0, a1, 2,
			Color("d6effc"), ice_wall, Color("3ea4d4"))
		wave2_nodes.append(sec)

	# Wave 1: 4 Outer Floating Ice-Shelf Lobes (r = 29.28 .. 38.0 m) that calve into the sea.
	var wave1_nodes: Array[Node3D] = []
	for idx: int in 4:
		var a0: float = float(idx) * PI * 0.5 + 0.035
		var a1: float = a0 + PI * 0.5 - 0.070
		var sec: Node3D = _make_ring_wedge_sector(
			root, "Wave1_IceLobe_%d" % idx,
			29.28, 38.0, -2.2, 0.0, a0, a1, 4,
			Color("c2e7fa"), ice_deep, snow_white)
		wave1_nodes.append(sec)

	# Distant icebergs, snow peaks & pine islands around the arctic basin.
	_build_iceberg_scenery(root)

	# 8 symmetric spawns at r = 12.2 m (clear of the 4 r = 16.4 m corner kickers).
	var spawns: Array[Transform3D] = _radial_spawns(8, 12.2, 0.38)

	# Surface physics zones:
	#   Priority 2: central slick ice sheet (r <= 15.2 m) -> grip 0.48
	#   Priority 1: packed snow ridge ring (15.2 < r <= 21.0 m) -> grip 0.90
	#   Base grip on outer calving ice shelves: 0.64
	var surface_zones: Array[Dictionary] = [
		{
			"shape": "circle",
			"center": Vector2.ZERO,
			"radius": 15.2,
			"grip": 0.48,
			"priority": 2,
		},
		{
			"shape": "ring",
			"center": Vector2.ZERO,
			"inner_radius": 15.2,
			"outer_radius": 21.2,
			"grip": 0.90,
			"priority": 1,
		},
	]

	return {
		"id": "ko_iceberg",
		"name": "FRACTURED ICEBERG",
		"subtitle": "SLICK ICE  ·  CORNER KICKERS",
		"spawns": spawns,
		"ko_y": -2.65,
		"wave1_nodes": wave1_nodes,
		"wave2_nodes": wave2_nodes,
		"safe_radius": 20.5,
		"surface_zones": surface_zones,
		"base_grip": 0.64,
		"chasm_half_x": 0.0,
	}


static func _build_iceberg_scenery(root: Node3D) -> void:
	# Floating sea-ice floes close around the basin (~44..50 m) for rich framing.
	var near_batch := PropBatch.new()
	var snow_col := Color("f0f8ff")
	var ice_side := Color("4ca6cf")
	for i: int in 8:
		var ang: float = TAU * float(i) / 8.0 + 0.32
		var dist: float = 46.0 + float(i % 2) * 4.5
		var pos := Vector3(cos(ang) * dist, -2.85, sin(ang) * dist)
		near_batch.add_cylinder(Transform3D(Basis(Vector3.UP, ang), pos),
			4.2 + float(i % 3) * 1.1, 0.9, 6, snow_col)
		if i % 2 == 0:
			_add_cone(near_batch, Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 0.45, 0.0)),
				2.4, 4.8, 6, ice_side.lightened(0.22))
	_emit_batch_mesh(root, near_batch, "FloatingIceFloes", false)

	# Distant arctic horizon (> 260 m span): towering icebergs, snow peaks & pine islands.
	var far_batch := PropBatch.new()
	var pine_xforms: Array = []
	var rock_xforms: Array = []
	for i: int in 18:
		var ang: float = TAU * float(i) / 18.0 + 0.11
		var dist: float = 122.0 + float((i * 5) % 4) * 16.0
		var ix: float = cos(ang) * dist
		var iz: float = sin(ang) * dist
		var island_r: float = 14.0 + float(i % 3) * 5.0
		far_batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(ix, -1.8, iz)),
			island_r, 3.2, 7, snow_col)
		if i % 3 == 0:
			# Pine snow island with Kenney pines & rocks.
			for p: int in 3:
				var off_a: float = ang + float(p - 1) * 0.45
				var tree_spot := Vector3(ix + cos(off_a) * 5.2, -0.2, iz + sin(off_a) * 5.2)
				pine_xforms.append(_fit_model("tree_pineTallA", tree_spot,
					float(i + p) * 1.1, Vector3.ONE * 9.5, true))
			rock_xforms.append(_fit_model("rock_tallA", Vector3(ix, -0.2, iz),
				float(i) * 0.8, Vector3.ONE * 8.0, true))
		else:
			# Asymmetric faceted alpine glacier peak (explicit cartoon-blue
			# palette so the horizon reads ice-blue, not flat grey).
			var ice_rng := RandomNumberGenerator.new()
			ice_rng.seed = 44200 + i
			LandscapeSculptor.add_alpine_mountain(far_batch,
				Vector3(ix, -2.0, iz),
				island_r * 1.45, 28.0 + float((i * 7) % 5) * 9.0, ice_rng,
				{
					"base": Color("2f6d9e"),
					"rock": Color("3f9fd0"),
					"cliff": Color("6fc6e8"),
					"snow_lo": Color("c4eafb"),
					"snow_hi": Color("f0fbff"),
				})
	_emit_batch_mesh(root, far_batch, "ArcticHorizonPeaks", false)
	_batch_model(root, "tree_pineTallA", pine_xforms, "ArcticPines", false, true)
	_batch_model(root, "rock_tallA", rock_xforms, "ArcticRocks", false, true)


# ==========================================================================
# Collapsible Sector Builders (Visual + Warning Strobe + WORLD StaticBody3D)
# ==========================================================================

static func _make_box_sector(parent: Node3D, node_name: String,
		center_top: Vector3, yaw: float, size: Vector3,
		top_col: Color, side_col: Color, trim_col: Color,
		outer_kerb: bool, kerb_h: float) -> Node3D:
	var sector := Node3D.new()
	sector.name = node_name
	sector.position = center_top
	sector.rotation.y = yaw
	parent.add_child(sector)

	var batch := PropBatch.new()
	var body: StaticBody3D = _solid_body(sector, node_name + "_Body")
	var shapes: Array[CollisionShape3D] = []

	var box_center := Vector3(0.0, -size.y * 0.5, 0.0)
	batch.add_box(Transform3D.IDENTITY.translated(box_center), size, side_col)
	batch.add_box(Transform3D.IDENTITY.translated(Vector3(0.0, -0.04, 0.0)),
		Vector3(size.x - 0.16, 0.09, size.z - 0.16), top_col)
	# Hazard stripe near the outer lip (+Z in local sector space).
	var stripe_z: float = size.z * 0.5 - 0.55
	batch.add_box(Transform3D.IDENTITY.translated(Vector3(0.0, 0.015, stripe_z)),
		Vector3(size.x - 0.6, 0.025, 0.65), trim_col)

	shapes.append(_add_box_collider(body,
		Transform3D.IDENTITY.translated(box_center), size))

	if outer_kerb and kerb_h > 0.02:
		# Two short corner bumper tabs with a wide central knockout gap!
		var tab_w: float = minf(size.x * 0.24, 3.4)
		for sx: float in [-1.0, 1.0]:
			var kx: float = sx * (size.x * 0.5 - tab_w * 0.5 - 0.35)
			var k_pos := Vector3(kx, kerb_h * 0.5, size.z * 0.5 - 0.32)
			var k_size := Vector3(tab_w, kerb_h, 0.55)
			batch.add_box(Transform3D.IDENTITY.translated(k_pos), k_size, trim_col)
			shapes.append(_add_box_collider(body,
				Transform3D.IDENTITY.translated(k_pos), k_size))

	_emit_batch_mesh(sector, batch, "SectorMesh", true)

	# Warning strobe overlay (+0.032 m above sector deck).
	var warn_batch := PropBatch.new()
	warn_batch.add_box(Transform3D.IDENTITY.translated(Vector3(0.0, 0.032, 0.0)),
		Vector3(size.x - 0.3, 0.02, size.z - 0.3), Color.WHITE)
	var warn_mat: StandardMaterial3D = _warning_material()
	var warn_inst := MeshInstance3D.new()
	warn_inst.name = "WarningStrobe"
	warn_inst.mesh = warn_batch.build()
	warn_inst.material_override = warn_mat
	warn_inst.visible = false
	warn_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sector.add_child(warn_inst)

	sector.set_meta("rest_transform", sector.transform)
	sector.set_meta("shapes", shapes)
	sector.set_meta("warn_mesh", warn_inst)
	sector.set_meta("warn_mat", warn_mat)
	return sector


static func _make_ring_wedge_sector(parent: Node3D, node_name: String,
		r_inner: float, r_outer: float, y_bot: float, y_top: float,
		a0: float, a1: float, segments: int,
		top_col: Color, side_col: Color, trim_col: Color,
		corner_kerbs: bool = false) -> Node3D:
	var mid_a: float = (a0 + a1) * 0.5
	var mid_r: float = (r_inner + r_outer) * 0.5
	var pivot := Vector3(cos(mid_a) * mid_r, y_top, sin(mid_a) * mid_r)

	var sector := Node3D.new()
	sector.name = node_name
	sector.position = pivot
	parent.add_child(sector)

	var batch := PropBatch.new()
	var warn_batch := PropBatch.new()
	var body: StaticBody3D = _solid_body(sector, node_name + "_Body")
	var shapes: Array[CollisionShape3D] = []

	var count: int = maxi(segments, 1)
	var thick: float = y_top - y_bot
	for s: int in count:
		var t0: float = lerpf(a0, a1, float(s) / float(count))
		var t1: float = lerpf(a0, a1, float(s + 1) / float(count))
		_add_ring_sector_offset(batch, -pivot, r_inner, r_outer, y_bot, y_top,
			t0, t1, 1, top_col, side_col, s == 0, s == count - 1)
		_add_ring_sector_offset(batch, -pivot, r_outer - 0.85, r_outer - 0.18,
			y_top, y_top + 0.022, t0, t1, 1, trim_col, trim_col, false, false)
		_add_ring_sector_offset(warn_batch, -pivot, r_inner + 0.25, r_outer - 0.25,
			y_top + 0.025, y_top + 0.045, t0, t1, 1, Color.WHITE, Color.WHITE, false, false)

		# Chord BoxShape3D matching this arc segment flush at y_top.
		var tm: float = (t0 + t1) * 0.5
		var d_ang: float = t1 - t0
		var r_in_chord: float = r_inner * cos(d_ang * 0.5)
		var r_out_chord: float = r_outer * cos(d_ang * 0.5)
		var c_mid_r: float = (r_in_chord + r_out_chord) * 0.5
		var chord_w: float = 2.0 * r_outer * sin(d_ang * 0.5) * 0.92
		var radial_d: float = maxf(r_out_chord - r_in_chord, 1.0) + 0.35
		var world_c := Vector3(cos(tm) * c_mid_r, y_top - thick * 0.5, sin(tm) * c_mid_r)
		var local_c: Vector3 = world_c - pivot
		var c_yaw: float = atan2(cos(tm), sin(tm))
		shapes.append(_add_box_collider(body,
			Transform3D(Basis(Vector3.UP, c_yaw), local_c),
			Vector3(chord_w, thick, radial_d)))

	if corner_kerbs:
		for end_a: float in [a0 + 0.06, a1 - 0.06]:
			var kr: float = r_outer * cos((a1 - a0) * 0.5) - 0.45
			var kw_pos: Vector3 = Vector3(cos(end_a) * kr, y_top + 0.11, sin(end_a) * kr) - pivot
			var k_yaw: float = atan2(cos(mid_a), sin(mid_a))
			var k_size := Vector3(2.8, 0.22, 0.55)
			batch.add_box(Transform3D(Basis(Vector3.UP, k_yaw), kw_pos), k_size, trim_col)
			shapes.append(_add_box_collider(body,
				Transform3D(Basis(Vector3.UP, k_yaw), kw_pos), k_size))

	_emit_batch_mesh(sector, batch, "SectorMesh", true)

	var warn_mat: StandardMaterial3D = _warning_material()
	var warn_inst := MeshInstance3D.new()
	warn_inst.name = "WarningStrobe"
	warn_inst.mesh = warn_batch.build()
	warn_inst.material_override = warn_mat
	warn_inst.visible = false
	warn_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sector.add_child(warn_inst)

	sector.set_meta("rest_transform", sector.transform)
	sector.set_meta("shapes", shapes)
	sector.set_meta("warn_mesh", warn_inst)
	sector.set_meta("warn_mat", warn_mat)
	return sector


# ==========================================================================
# Geometry & Physics Primitives
# ==========================================================================

static func _solid_body(parent: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	return body


static func _add_box_collider(body: StaticBody3D, xform: Transform3D,
		size: Vector3) -> CollisionShape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(size.x, 0.05), maxf(size.y, 0.05), maxf(size.z, 0.05))
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = xform
	body.add_child(col)
	return col


static func _add_cylinder_collider(body: StaticBody3D, base_point: Vector3,
		radius: float, height: float) -> CollisionShape3D:
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, 0.05)
	shape.height = maxf(height, 0.1)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = base_point + Vector3.UP * (shape.height * 0.5)
	body.add_child(col)
	return col


static func _add_octagon_slab(batch: PropBatch, body: StaticBody3D,
		center: Vector3, circum_r: float, y_bot: float, y_top: float,
		top_col: Color, side_col: Color) -> void:
	# Visual regular octagon (vertices at k * 45 + 22.5 deg) matching the exact
	# union of 4 rotated BoxShape3D rectangles at 0, 45, 90, 135 deg!
	var count: int = 8
	var top_c := center + Vector3.UP * y_top
	var bot_c := center + Vector3.UP * y_bot
	for i: int in count:
		var a0: float = TAU * float(i) / float(count) + PI / 8.0
		var a1: float = TAU * float(i + 1) / float(count) + PI / 8.0
		var t0 := center + Vector3(cos(a0) * circum_r, y_top, sin(a0) * circum_r)
		var t1 := center + Vector3(cos(a1) * circum_r, y_top, sin(a1) * circum_r)
		var b0 := center + Vector3(cos(a0) * circum_r, y_bot, sin(a0) * circum_r)
		var b1 := center + Vector3(cos(a1) * circum_r, y_bot, sin(a1) * circum_r)
		batch.add_triangle(top_c, t1, t0, top_col)
		batch.add_triangle(bot_c, b0, b1, side_col.darkened(0.22))
		batch.add_quad(b0, t0, t1, b1, side_col)

	if body != null:
		var h: float = y_top - y_bot
		var box_w: float = 2.0 * circum_r * sin(PI / 8.0)
		var box_d: float = 2.0 * circum_r * cos(PI / 8.0)
		var mid_y: float = (y_top + y_bot) * 0.5
		for k: int in 4:
			var yaw: float = float(k) * (PI * 0.25)
			_add_box_collider(body,
				Transform3D(Basis(Vector3.UP, yaw), center + Vector3.UP * mid_y),
				Vector3(box_w, h, box_d))


static func _add_ring_sector(batch: PropBatch, r_inner: float, r_outer: float,
		y_bot: float, y_top: float, a0: float, a1: float, segments: int,
		top_col: Color, side_col: Color) -> void:
	var full_loop: bool = absf((a1 - a0) - TAU) < 0.001
	_add_ring_sector_offset(batch, Vector3.ZERO, r_inner, r_outer, y_bot, y_top,
		a0, a1, segments, top_col, side_col, not full_loop, not full_loop)


static func _add_ring_sector_offset(batch: PropBatch, offset: Vector3,
		r_inner: float, r_outer: float, y_bot: float, y_top: float,
		a0: float, a1: float, segments: int,
		top_col: Color, side_col: Color, cap_start: bool, cap_end: bool) -> void:
	var count: int = maxi(segments, 1)
	var bot_col: Color = side_col.darkened(0.20)
	for i: int in count:
		var t0: float = lerpf(a0, a1, float(i) / float(count))
		var t1: float = lerpf(a0, a1, float(i + 1) / float(count))
		var out0_t := offset + Vector3(cos(t0) * r_outer, y_top, sin(t0) * r_outer)
		var out1_t := offset + Vector3(cos(t1) * r_outer, y_top, sin(t1) * r_outer)
		var out0_b := offset + Vector3(cos(t0) * r_outer, y_bot, sin(t0) * r_outer)
		var out1_b := offset + Vector3(cos(t1) * r_outer, y_bot, sin(t1) * r_outer)
		if r_inner <= 0.01:
			var c_top := offset + Vector3(0.0, y_top, 0.0)
			var c_bot := offset + Vector3(0.0, y_bot, 0.0)
			batch.add_triangle(c_top, out1_t, out0_t, top_col)
			batch.add_triangle(c_bot, out0_b, out1_b, bot_col)
			batch.add_quad(out0_b, out0_t, out1_t, out1_b, side_col)
		else:
			var in0_t := offset + Vector3(cos(t0) * r_inner, y_top, sin(t0) * r_inner)
			var in1_t := offset + Vector3(cos(t1) * r_inner, y_top, sin(t1) * r_inner)
			var in0_b := offset + Vector3(cos(t0) * r_inner, y_bot, sin(t0) * r_inner)
			var in1_b := offset + Vector3(cos(t1) * r_inner, y_bot, sin(t1) * r_inner)
			batch.add_quad(in0_t, in1_t, out1_t, out0_t, top_col)
			batch.add_quad(in0_b, out0_b, out1_b, in1_b, bot_col)
			batch.add_quad(out0_b, out0_t, out1_t, out1_b, side_col)
			batch.add_quad(in1_b, in1_t, in0_t, in0_b, side_col)
	if cap_start and r_outer > 0.01:
		var in_s: float = maxf(r_inner, 0.0)
		var s_in_b := offset + Vector3(cos(a0) * in_s, y_bot, sin(a0) * in_s)
		var s_in_t := offset + Vector3(cos(a0) * in_s, y_top, sin(a0) * in_s)
		var s_out_t := offset + Vector3(cos(a0) * r_outer, y_top, sin(a0) * r_outer)
		var s_out_b := offset + Vector3(cos(a0) * r_outer, y_bot, sin(a0) * r_outer)
		batch.add_quad(s_in_b, s_in_t, s_out_t, s_out_b, side_col.darkened(0.08))
	if cap_end and r_outer > 0.01:
		var in_e: float = maxf(r_inner, 0.0)
		var e_in_b := offset + Vector3(cos(a1) * in_e, y_bot, sin(a1) * in_e)
		var e_in_t := offset + Vector3(cos(a1) * in_e, y_top, sin(a1) * in_e)
		var e_out_t := offset + Vector3(cos(a1) * r_outer, y_top, sin(a1) * r_outer)
		var e_out_b := offset + Vector3(cos(a1) * r_outer, y_bot, sin(a1) * r_outer)
		batch.add_quad(e_out_b, e_out_t, e_in_t, e_in_b, side_col.darkened(0.08))


static func _add_ramp_wedge(batch: PropBatch, body: StaticBody3D,
		origin: Vector3, yaw: float, width: float, length: float, rise: float,
		base_y: float, deck_col: Color, side_col: Color,
		stripe_col: Color) -> void:
	## Smooth drive-up wedge whose local -Z sits at `base_y` and local +Z rises
	## to `base_y + rise`, paired with a lip-free tilted BoxShape3D collider.
	var xform := Transform3D(Basis(Vector3.UP, yaw), origin + Vector3.UP * base_y)
	var hw: float = width * 0.5
	var hl: float = length * 0.5
	var lo_l: Vector3 = xform * Vector3(-hw, 0.0, -hl)
	var lo_r: Vector3 = xform * Vector3(hw, 0.0, -hl)
	var hi_l_bot: Vector3 = xform * Vector3(-hw, 0.0, hl)
	var hi_r_bot: Vector3 = xform * Vector3(hw, 0.0, hl)
	var hi_l_top: Vector3 = xform * Vector3(-hw, rise, hl)
	var hi_r_top: Vector3 = xform * Vector3(hw, rise, hl)

	# Sloped top deck (+Y/-Z outward normal).
	batch.add_quad(lo_l, hi_l_top, hi_r_top, lo_r, deck_col)
	# Back vertical face (+Z normal) + bottom face (-Y normal).
	batch.add_quad(hi_l_bot, hi_r_bot, hi_r_top, hi_l_top, side_col)
	batch.add_quad(lo_l, lo_r, hi_r_bot, hi_l_bot, side_col.darkened(0.2))
	# Left (-X) and Right (+X) triangular cheek walls.
	batch.add_triangle(lo_l, hi_l_bot, hi_l_top, side_col)
	batch.add_triangle(lo_r, hi_r_top, hi_r_bot, side_col)

	# Painted edge stripes up the ramp.
	var sw: float = 0.28
	for side: float in [-1.0, 1.0]:
		var sx0: float = side * (hw - sw * 0.65) - sw * 0.5
		var sx1: float = sx0 + sw
		var s_lo_l: Vector3 = xform * Vector3(sx0, 0.018, -hl + 0.1)
		var s_lo_r: Vector3 = xform * Vector3(sx1, 0.018, -hl + 0.1)
		var s_hi_l: Vector3 = xform * Vector3(sx0, rise + 0.018, hl - 0.1)
		var s_hi_r: Vector3 = xform * Vector3(sx1, rise + 0.018, hl - 0.1)
		batch.add_quad(s_lo_l, s_hi_l, s_hi_r, s_lo_r, stripe_col)

	if body != null:
		var slope: float = atan2(rise, length)
		var hypot: float = sqrt(length * length + rise * rise)
		var thick: float = 0.60
		var n_local := Vector3(0.0, cos(slope), -sin(slope))
		var mid_local: Vector3 = Vector3(0.0, rise * 0.5, 0.0) - n_local * (thick * 0.5)
		var col_basis: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -slope)
		_add_box_collider(body,
			Transform3D(col_basis, origin + Vector3.UP * base_y + Basis(Vector3.UP, yaw) * mid_local),
			Vector3(width, thick, hypot))


static func _add_cone(batch: PropBatch, xform: Transform3D, radius: float,
		height: float, segments: int, color: Color) -> void:
	var count: int = maxi(segments, 3)
	var apex: Vector3 = xform * Vector3(0.0, height, 0.0)
	var base_c: Vector3 = xform * Vector3.ZERO
	for i: int in count:
		var a0: float = TAU * float(i) / float(count)
		var a1: float = TAU * float(i + 1) / float(count)
		var p0: Vector3 = xform * Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
		var p1: Vector3 = xform * Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
		batch.add_triangle(p0, apex, p1, color)
		batch.add_triangle(base_c, p0, p1, color.darkened(0.22))


static func _emit_batch_mesh(parent: Node3D, batch: PropBatch, node_name: String,
		cast_shadow: bool = true, unshaded: bool = false) -> MeshInstance3D:
	var mesh: ArrayMesh = batch.build()
	if mesh == null:
		return null
	var inst := MeshInstance3D.new()
	inst.name = node_name
	inst.mesh = mesh
	var mat: StandardMaterial3D = SceneryKit.vertex_material()
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inst.material_override = mat
	if not cast_shadow:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	return inst


static func _flat_material(colour: Color, unshaded: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


static func _warning_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.25, 0.12, 0.55)
	return mat


static func _radial_spawns(count: int, radius: float, y: float) -> Array[Transform3D]:
	var spawns: Array[Transform3D] = []
	for i: int in count:
		var ang: float = TAU * float(i) / float(count)
		var pos := Vector3(cos(ang) * radius, y, sin(ang) * radius)
		spawns.append(_look_inward(pos, Vector3(0.0, y, 0.0)))
	return spawns


static func _look_inward(from_pos: Vector3, target: Vector3) -> Transform3D:
	var to_target: Vector3 = target - from_pos
	to_target.y = 0.0
	var yaw: float = atan2(-to_target.x, -to_target.z) if to_target.length_squared() > 0.001 else 0.0
	return Transform3D(Basis(Vector3.UP, yaw), from_pos)


static func _fit_model(model: String, at: Vector3, yaw: float,
		scale: Vector3, nature: bool = false) -> Transform3D:
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), at)
	var center: Vector2 = info["center"] as Vector2
	var aabb: AABB = info["aabb"] as AABB
	var yaw_basis := Basis(Vector3.UP, yaw)
	var basis: Basis = yaw_basis * Basis.IDENTITY.scaled(scale)
	var center_m := Vector3(center.x * scale.x, 0.0, center.y * scale.z)
	var lift: float = -aabb.position.y * scale.y
	return Transform3D(basis, at - yaw_basis * center_m + Vector3.UP * lift)


static func _batch_model(parent: Node3D, model: String, transforms: Array,
		node_name: String, cast_shadow: bool = true,
		nature: bool = false) -> void:
	if parent == null or transforms.is_empty():
		return
	var info: Dictionary = TileCatalog.model_info(model, nature)
	if not bool(info.get("ok", false)):
		return
	var parts: Array = info.get("parts", []) as Array
	for part_index: int in parts.size():
		var part: Dictionary = parts[part_index]
		var mesh: Mesh = part.get("mesh") as Mesh
		var local: Transform3D = part.get("transform", Transform3D.IDENTITY) as Transform3D
		if mesh == null:
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = transforms.size()
		for index: int in transforms.size():
			multi.set_instance_transform(index, (transforms[index] as Transform3D) * local)
		var inst := MultiMeshInstance3D.new()
		inst.name = node_name if parts.size() == 1 else "%s_%d" % [node_name, part_index]
		inst.multimesh = multi
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(inst)
