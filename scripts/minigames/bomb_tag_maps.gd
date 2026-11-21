extends RefCounted
## Builds the three genuinely distinct 3D arenas for BLAST TAG (`bomb_tag.tscn`):
##   1. `bt_plaza`     — TERRACE PLAZA: sunlit 3-tier festival courtyard (0.0 m
##                       ground + fountain roundabout, +2.2 m N/S mid terraces
##                       with >= 3.9 m flanking archway tunnels, +4.4 m central
##                       skywalk bridge with >= 3.95 m courtyard headroom and
##                       open roof drop-off edges).
##   2. `bt_labyrinth` — CANYON LABYRINTH: warm red-rock amphitheatre with 8
##                       towering stratified sandstone pillars (>= 14 m figure-8
##                       juke lanes) plus a central +3.85 m Mesa Overpass Bridge
##                       (>= 3.47 m headroom over the E/W canyon main street).
##   3. `bt_ferries`   — TWIN FERRIES: deep blue harbour channel (y = -3.0 m)
##                       with two moored 36 x 96 m cargo ferry decks separated
##                       by a 12 m open water channel, linked by 2 arched steel
##                       boarding bridges (+2.2 m crest) and 2 boosted high-speed
##                       gap-jump kickers, plus +2.0 m bow/stern wheelhouse decks.
##
## Every arena is static and host-parameterised (`build_arena(host, arena_id)`)
## so the live minigame, headless selftest and preview renderer share one path.
## Zero photorealistic PBR textures are referenced anywhere: geometry uses
## flat cartoon vertex-coloured `PropBatch` / `SceneryKit` meshes and CC0 Kenney
## racing/nature kit MultiMeshes, with `CollisionLayers.WORLD` colliders on all
## floors, ramps, walls, bridges and solid landmarks.

const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const LandscapeSculptor := preload("res://scripts/minigames/scenery/landscape_sculptor.gd")
const AmbientWorld := preload("res://scripts/minigames/scenery/ambient_world.gd")
const BOOST_PAD_SCENE: PackedScene = preload("res://scenes/track/boost_pad.tscn")

const RACING_ROOT: String = "res://assets/models/kenney_racing_kit/Models/GLTF format/"
const NATURE_ROOT: String = "res://assets/models/kenney_nature_kit/Models/GLTF format/"

const DEFAULT_ID: String = "bt_plaza"
const ARENA_IDS: PackedStringArray = ["bt_plaza", "bt_labyrinth", "bt_ferries"]

const ARENA_META: Dictionary = {
	"bt_plaza": {
		"id": "bt_plaza",
		"name": "TERRACE PLAZA",
		"blurb": "3-TIER FESTIVAL SKYWALK",
		"sky_top": Color("2a8fe0"),
		"sky_horizon": Color("d6f0ff"),
		"ground_bottom": Color("3b6c3a"),
		"fog_color": Color("cfeaf9"),
		"fog_density": 0.0011,
		"sun_color": Color("fff4dc"),
		"sun_energy": 1.18,
	},
	"bt_labyrinth": {
		"id": "bt_labyrinth",
		"name": "CANYON LABYRINTH",
		"blurb": "MESA PILLARS & OVERPASS",
		"sky_top": Color("d96836"),
		"sky_horizon": Color("ffd399"),
		"ground_bottom": Color("6e2f1d"),
		"fog_color": Color("f6c38c"),
		"fog_density": 0.0012,
		"sun_color": Color("ffd79c"),
		"sun_energy": 1.24,
	},
	"bt_ferries": {
		"id": "bt_ferries",
		"name": "TWIN FERRIES",
		"blurb": "12M HARBOUR CHANNEL JUMP",
		"sky_top": Color("2577bd"),
		"sky_horizon": Color("c9e6f5"),
		"ground_bottom": Color("123d5e"),
		"fog_color": Color("c2dfef"),
		"fog_density": 0.0010,
		"sun_color": Color("fff6e8"),
		"sun_energy": 1.18,
	},
}

static var _model_cache: Dictionary = {}
static var _flat_mat_cache: Dictionary = {}


## Ordered list of all Blast Tag arena IDs.
static func ids() -> PackedStringArray:
	return ARENA_IDS


## Resolves any loose menu/session/env identifier to a valid Blast Tag arena ID.
static func resolve_id(raw: String) -> String:
	var clean: String = raw.strip_edges().to_lower()
	match clean:
		"bt_plaza", "plaza", "terrace_plaza", "terrace":
			return "bt_plaza"
		"bt_labyrinth", "labyrinth", "canyon_labyrinth", "canyon":
			return "bt_labyrinth"
		"bt_ferries", "ferries", "twin_ferries", "harbour", "harbor":
			return "bt_ferries"
	return DEFAULT_ID


## Metadata dictionary (sky/fog/name/blurb) for `arena_id`.
static func arena_meta(arena_id: String) -> Dictionary:
	var key: String = resolve_id(arena_id)
	return (ARENA_META.get(key, ARENA_META[DEFAULT_ID]) as Dictionary).duplicate()


## Builds the complete 3D arena + WORLD colliders + BoostPads under `host`.
## Returns `{ "id", "name", "blurb", "spawns": Array[Transform3D],
## "fall_y": float, "bounds_half": float, "boost_spots": Array[Transform3D],
## "pillars": Array[Vector3], "ramps": Array[Dictionary], ... }`.
static func build_arena(host: Node3D, arena_id: String) -> Dictionary:
	var resolved: String = resolve_id(arena_id)
	var meta: Dictionary = arena_meta(resolved)
	var spawns: Array[Transform3D] = []
	var boost_spots: Array[Transform3D] = []
	var pillars: Array[Vector3] = []
	var ramps: Array[Dictionary] = []
	var fall_y: float = -2.8
	var bounds_half: float = 60.0

	if host == null:
		meta["spawns"] = spawns
		meta["fall_y"] = fall_y
		meta["bounds_half"] = bounds_half
		meta["boost_spots"] = boost_spots
		meta["pillars"] = pillars
		meta["ramps"] = ramps
		return meta

	var root := Node3D.new()
	root.name = "BlastTagArena_" + resolved
	host.add_child(root)

	match resolved:
		"bt_labyrinth":
			bounds_half = 62.0
			fall_y = -2.8
			_build_labyrinth(root, spawns, boost_spots, pillars, ramps)
		"bt_ferries":
			bounds_half = 60.0
			fall_y = -2.1
			_build_ferries(root, spawns, boost_spots, pillars, ramps)
		_:
			bounds_half = 60.0
			fall_y = -2.8
			_build_plaza(root, spawns, boost_spots, pillars, ramps)

	# Party arenas ring themselves differently: the ferries sit in a harbour at
	# y = -3.0 m and must get barges in the water, not containers standing in it.
	var ambient: Dictionary = {
		"style": "stadium",
		"radius_in": bounds_half + 16.0,
		"radius_out": bounds_half + 40.0,
	}
	match resolved:
		"bt_labyrinth":
			ambient = {"style": "canyon",
				"radius_in": bounds_half + 16.0, "radius_out": bounds_half + 40.0}
		"bt_ferries":
			ambient = {"style": "dockyard", "floor_y": -3.0,
				"radius_in": 46.0, "radius_out": 74.0}
	AmbientWorld.build_arena(root, resolved, bounds_half, ambient)
	_add_dynamic_landmarks(root, resolved)
	meta["id"] = resolved
	meta["spawns"] = spawns
	meta["fall_y"] = fall_y
	meta["bounds_half"] = bounds_half
	meta["boost_spots"] = boost_spots
	meta["pillars"] = pillars
	meta["ramps"] = ramps
	return meta


# ==========================================================================
# MAP 1: "bt_plaza" — TERRACE PLAZA (120 x 120 m, 3 Vertical Tiers)
# ==========================================================================


static func _build_plaza(root: Node3D, spawns: Array[Transform3D],
		boost_spots: Array[Transform3D], pillars: Array[Vector3],
		ramps: Array[Dictionary]) -> void:
	var half: float = 60.0
	var body: StaticBody3D = _solid_body(root, "PlazaWorldCollision")
	var batch := PropBatch.new()

	# Surrounding festival lawn apron + sunlit cobblestone court base.
	_add_plane(root, "OuterLawn", Vector2(1050.0, 1050.0), Vector3(0.0, -0.08, 0.0),
		Color("52a849"))
	_add_box_collider(body, Transform3D(Basis.IDENTITY, Vector3(0.0, -1.0, 0.0)),
		Vector3(144.0, 2.0, 144.0))

	# Ground courtyard floor slab + MultiMesh checkerboard tiles (120 x 120 m).
	_add_plane(root, "PlazaBaseFloor", Vector2(124.0, 124.0),
		Vector3(0.0, 0.0, 0.0), Color("e6cfa8"))
	var tile_mesh := PlaneMesh.new()
	tile_mesh.size = Vector2(12.0, 12.0)
	var tile_xforms: Array = []
	var tile_cols: Array = []
	var col_a := Color("edd8b4")
	var col_b := Color("dfbf91")
	var col_ring := Color("d4845a")
	for ix in range(-5, 5):
		for iz in range(-5, 5):
			var cx: float = (float(ix) + 0.5) * 12.0
			var cz: float = (float(iz) + 0.5) * 12.0
			tile_xforms.append(Transform3D(Basis.IDENTITY, Vector3(cx, 0.012, cz)))
			var radial: float = Vector2(cx, cz).length()
			if radial < 18.0:
				tile_cols.append(col_ring if (ix + iz) % 2 == 0 else col_a)
			else:
				tile_cols.append(col_a if (ix + iz) % 2 == 0 else col_b)
	root.add_child(SceneryKit.multimesh(tile_mesh, SceneryKit.instance_material(1.0),
		tile_xforms, "PlazaTiles", false, tile_cols))

	# Central Fountain Roundabout at (0, 0, 0) — solid stone basin + turquoise water tiers.
	var fountain_r: float = 4.6
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.03, 0.0)),
		11.2, 0.05, 32, Color("f6ebd6"))
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.04, 0.0)),
		9.6, 0.05, 32, Color("c96d49"))
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, 0.0)),
		fountain_r, 1.10, 20, Color("f2e5ce"))
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.98, 0.0)),
		fountain_r - 0.45, 0.30, 20, Color("2cc6dc"))
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.45, 0.0)),
		1.85, 1.35, 16, Color("e6d4b5"))
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.08, 0.0)),
		2.35, 0.24, 16, Color("f7efe0"))
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.22, 0.0)),
		1.95, 0.12, 16, Color("49def2"))
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.65, 0.0)),
		0.55, 0.90, 12, Color("a6f6ff"))
	_add_cylinder_collider(body, Vector3.ZERO, fountain_r, 2.8)
	pillars.append(Vector3.ZERO)

	# 4 Courtyard Juke Columns / Festival Kiosks at (+-22, 0, +-14), leaving >= 14 m lanes.
	var kiosk_palette: Array[Color] = [
		Color("e85349"), Color("2ba8d9"), Color("f2a93b"), Color("48b862")
	]
	var kiosk_idx: int = 0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var kpos := Vector3(sx * 22.0, 0.0, sz * 13.5)
			var accent: Color = kiosk_palette[kiosk_idx % kiosk_palette.size()]
			kiosk_idx += 1
			batch.add_cylinder(Transform3D(Basis.IDENTITY, kpos + Vector3.UP * 0.20),
				2.35, 0.40, 14, Color("d8c39e"))
			batch.add_cylinder(Transform3D(Basis.IDENTITY, kpos + Vector3.UP * 1.85),
				1.75, 2.90, 14, Color("f7efe0"))
			_add_frustum(batch, Transform3D(Basis.IDENTITY, kpos + Vector3.UP * 3.85),
				2.65, 0.35, 1.25, 12, accent)
			_add_cylinder_collider(body, kpos, 2.15, 4.2)
			pillars.append(kpos)

	# ------------------------------------------------------------------
	# TIER 1 (+2.2 m): North & South Mid Terraces + Wide <= 11.3 deg Ramps
	#                  + Flanking Drive-Under Archways (>= 3.90 m clearance!)
	# ------------------------------------------------------------------
	var terrace_y: float = 2.2
	var stone_wall := Color("d6a05e")
	var terrace_top := Color("e0603c")
	var terrace_trim := Color("ffd9a0")
	var arch_col := Color("e86a2e")

	for z_sign: float in [-1.0, 1.0]:
		var tz_center: float = z_sign * 38.0
		# Solid terrace platform: x in [-28, 28] (56 m), z in [28..48] or [-48..-28] (20 m).
		_add_solid_box(batch, body,
			Transform3D(Basis.IDENTITY, Vector3(0.0, terrace_y * 0.5, tz_center)),
			Vector3(56.0, terrace_y, 20.0), stone_wall)
		# Decorative top paving + cream parapet coping.
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, terrace_y + 0.015, tz_center)),
			Vector3(55.2, 0.03, 19.2), terrace_top)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, terrace_y + 0.025, tz_center)),
			Vector3(48.0, 0.03, 12.0), Color("f0d9b5"))

		# Back guardrail on outer edge of terrace (z = +-47.5) so karts stay in bounds,
		# while inner courtyard balconies (x in [-24..-7] and [+7..+24] at z = +-28)
		# stay deliberately OPEN for thrilling roof drop-offs!
		_add_solid_box(batch, body,
			Transform3D(Basis.IDENTITY, Vector3(0.0, terrace_y + 0.55, z_sign * 47.55)),
			Vector3(55.6, 1.10, 0.90), terrace_trim)
		# Corner safety bollards at inner balcony corners (+-26.5, z_sign * 28.5).
		for sx: float in [-1.0, 1.0]:
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(sx * 26.2, terrace_y + 0.50, z_sign * 28.5)),
				Vector3(3.4, 1.0, 0.9), terrace_trim)
			# Drop-off chevron stripe along open balcony edge.
			batch.add_box(Transform3D(Basis.IDENTITY, Vector3(sx * 15.5, terrace_y + 0.03, z_sign * 28.45)),
				Vector3(16.0, 0.04, 0.75), Color("ffd22e"))

		# West & East wide Ground-to-Terrace Ramps:
		# Climb from x = +-39.0 (y = 0.0) to x = +-28.0 (y = 2.2), width = 10.0 m.
		# Slope = atan2(2.2, 11.0) = 11.31 deg (<= 14 deg!).
		for sx: float in [-1.0, 1.0]:
			var r_start := Vector3(sx * 39.0, 0.0, tz_center)
			var r_end := Vector3(sx * 28.0, terrace_y, tz_center)
			_add_ramp(batch, body, r_start, r_end, 10.0, 0.48,
				Color("e08a54"), terrace_trim, true, ramps)
			# Fill wedge underneath ramp so no kart wedges under the low slope.
			# Kept 0.19 m below the ramp surface and inset inside the slab
			# so it never pokes through the deck or out its sides.
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(sx * 33.2, terrace_y * 0.22, tz_center)),
				Vector3(9.4, terrace_y * 0.44, 9.0), stone_wall)

			# Grand Drive-Under Festival Archway Portal over the flanking lane!
			# Spans from x = +-39.5 to x = +-57.5 (18.0 m clear tunnel width!),
			# lintel underside at y = 3.90 m (>= 3.4 m clearance!).
			var outer_pier_x: float = sx * 58.2
			var inner_pier_x: float = sx * 40.0
			var arch_z: float = tz_center + z_sign * 6.8
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(outer_pier_x, 2.35, arch_z)),
				Vector3(2.4, 4.7, 2.8), stone_wall)
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(inner_pier_x, 2.35, arch_z)),
				Vector3(2.4, 4.7, 2.8), stone_wall)
			var arch_mid_x: float = sx * 49.1
			# Overhead arch lintel: center y = 4.35, height = 0.90 -> bottom = 3.90 m!
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(arch_mid_x, 4.35, arch_z)),
				Vector3(20.6, 0.90, 2.8), arch_col)
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(arch_mid_x, 4.98, arch_z)),
				Vector3(18.0, 0.38, 2.2), terrace_trim)

	# ------------------------------------------------------------------
	# TIER 2 (+4.4 m): Upper Skywalk Bridge across the center courtyard!
	# Underside = 4.40 - 0.44 = 3.96 m (>= 3.6 m vertical clearance!)
	# ------------------------------------------------------------------
	var sky_y: float = 4.40
	var sky_thick: float = 0.44
	var sky_col := Color("2f7fc4")
	var sky_deck := Color("ffc46b")

	# Central flat Skywalk span: z in [-19.5, +19.5] (39.0 m long), width = 10.4 m.
	# Underside is at y = 4.40 - 0.44 = 3.96 m over the ground courtyard!
	_add_solid_box(batch, body,
		Transform3D(Basis.IDENTITY, Vector3(0.0, sky_y - sky_thick * 0.5, 0.0)),
		Vector3(10.4, sky_thick, 39.0), sky_col)
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, sky_y + 0.016, 0.0)),
		Vector3(9.6, 0.03, 38.6), sky_deck)
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, sky_y + 0.026, 0.0)),
		Vector3(1.4, 0.03, 37.0), Color("ffd22e"))

	# Outer skywalk safety parapets (|z| in [9.5, 19.5]) + OPEN central drop-off zone
	# (|z| < 9.5) marked with bright yellow/red chevrons so runners can leap off!
	for z_sign: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(sx * 5.35, sky_y + 0.45, z_sign * 14.5)),
				Vector3(0.65, 0.90, 10.0), terrace_trim)
			# Open roof edge drop markers along z in [-9.5, +9.5].
			batch.add_box(Transform3D(Basis.IDENTITY, Vector3(sx * 5.35, sky_y + 0.035, 0.0)),
				Vector3(0.65, 0.05, 18.6), Color("ff595e"))

		# Terrace-to-Skywalk Ramp: climbs from (0, 2.2, z_sign * 30.5) on Mid Terrace
		# to (0, 4.4, z_sign * 19.5) onto Skywalk! Run = 11.0 m, Rise = 2.2 m -> 11.31 deg!
		# Notice z in [z_sign*30.5 .. z_sign*48.0] leaves 17.5 m of wide terrace behind it!
		var sr_start := Vector3(0.0, terrace_y, z_sign * 30.5)
		var sr_end := Vector3(0.0, sky_y, z_sign * 19.5)
		_add_ramp(batch, body, sr_start, sr_end, 9.6, 0.46,
			sky_col.lightened(0.12), terrace_trim, true, ramps)
		# Stepped support blocks under the ramp: each top stays 0.35 m below
		# the ramp surface so the climb is never walled off. The old single
		# full-height abutment stood ~1.7 m across the slope and blocked it.
		for step_i in 4:
			var zc: float = z_sign * (29.0 - float(step_i) * 2.5)
			var surf_y: float = 2.2 + (30.5 - absf(zc)) / 11.0 * 2.2
			var top_y: float = surf_y - 0.35
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(0.0, top_y * 0.5, zc)),
				Vector3(9.2, top_y, 2.6), stone_wall)
		pillars.append(Vector3(0.0, 0.0, z_sign * 23.75))

	# Enclosed Perimeter Barrier Ring (120 x 120 m, inner face at +-60.0 m).
	_build_enclosed_perimeter(root, body, batch, half, "barrierRed", "barrierWhite")

	# Festival Dressing outside the perimeter wall (grandstands, banner towers, oaks).
	_dress_plaza_exterior(root, body, half)

	var props_mesh := MeshInstance3D.new()
	props_mesh.name = "PlazaArchitectureMesh"
	props_mesh.mesh = batch.build()
	props_mesh.material_override = SceneryKit.vertex_material()
	root.add_child(props_mesh)

	# 4 Corner Courtyard Boost Pads + 2 Skywalk/Terrace Boost Pads (6 total).
	_spawn_boost_pad(root, Vector3(-44.0, 0.02, -22.0), 0.0, 9.0, boost_spots)
	_spawn_boost_pad(root, Vector3(44.0, 0.02, 22.0), PI, 9.0, boost_spots)
	_spawn_boost_pad(root, Vector3(-22.0, 0.02, 44.0), PI * 0.5, 9.0, boost_spots)
	_spawn_boost_pad(root, Vector3(22.0, 0.02, -44.0), -PI * 0.5, 9.0, boost_spots)
	_spawn_boost_pad(root, Vector3(0.0, sky_y + 0.03, 0.0), 0.0, 8.5, boost_spots)
	_spawn_boost_pad(root, Vector3(0.0, terrace_y + 0.03, -41.0), PI * 0.5, 8.5, boost_spots)

	# 8 Balanced Safe Spawns across the plaza courtyard & mid terraces.
	var spawn_defs: Array[Array] = [
		[Vector3(-36.0, 0.38, 18.0), 0.0],
		[Vector3(36.0, 0.38, -18.0), PI],
		[Vector3(-36.0, 0.38, -18.0), PI],
		[Vector3(36.0, 0.38, 18.0), 0.0],
		[Vector3(-14.0, 0.38, 0.0), 0.0],
		[Vector3(14.0, 0.38, 0.0), PI],
		[Vector3(-16.0, terrace_y + 0.38, -39.0), PI * 0.5],
		[Vector3(16.0, terrace_y + 0.38, 39.0), -PI * 0.5],
	]
	for item: Array in spawn_defs:
		var pos: Vector3 = item[0] as Vector3
		var yaw: float = float(item[1])
		spawns.append(Transform3D(Basis(Vector3.UP, yaw), pos))


static func _dress_plaza_exterior(root: Node3D, body: StaticBody3D, half: float) -> void:
	var stand_xforms: Array = []
	for side: float in [-1.0, 1.0]:
		var pos_ew := Vector3(side * (half + 10.5), 0.0, 0.0)
		var yaw_ew: float = -PI * 0.5 if side < 0.0 else PI * 0.5
		stand_xforms.append(fit_transform("grandStandCovered", pos_ew, yaw_ew,
			Vector3.ONE * 13.0))
		var sz: Vector3 = scaled_size("grandStandCovered", Vector3.ONE * 13.0)
		_add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw_ew),
			pos_ew + Vector3.UP * (sz.y * 0.5)), sz)
	batch_model(root, "grandStandCovered", stand_xforms, "PlazaGrandstands", true)

	var banner_red: Array = []
	var banner_green: Array = []
	var lights: Array = []
	for sx: float in [-1.0, 1.0]:
		for sz_sign: float in [-1.0, 1.0]:
			var lpos := Vector3(sx * (half + 8.0), 0.0, sz_sign * (half + 8.0))
			lights.append(fit_transform("lightPostLarge", lpos, 0.0, Vector3.ONE * 14.0))
			var bpos := Vector3(sx * 28.0, 0.0, sz_sign * (half + 7.5))
			if sx * sz_sign > 0.0:
				banner_red.append(fit_transform("bannerTowerRed", bpos, 0.0, Vector3.ONE * 13.0))
			else:
				banner_green.append(fit_transform("bannerTowerGreen", bpos, 0.0, Vector3.ONE * 13.0))
	batch_model(root, "lightPostLarge", lights, "PlazaFloodlights", true)
	batch_model(root, "bannerTowerRed", banner_red, "PlazaBannersRed", true)
	batch_model(root, "bannerTowerGreen", banner_green, "PlazaBannersGreen", true)

	var trees: Array = []
	for i in 20:
		var angle: float = TAU * float(i) / 20.0
		var r: float = 84.0 + float(i % 3) * 7.0
		var tpos := Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		trees.append(fit_transform("tree_oak", tpos, angle, Vector3.ONE * 7.5, true))
	batch_model(root, "tree_oak", trees, "PlazaTrees", false, true)


# ==========================================================================
# MAP 2: "bt_labyrinth" — CANYON LABYRINTH (124 x 124 m, 8 Mesa Pillars
#        + Central +3.85 m Mesa Overpass Bridge with >= 3.47 m clearance)
# ==========================================================================


static func _build_labyrinth(root: Node3D, spawns: Array[Transform3D],
		boost_spots: Array[Transform3D], pillars: Array[Vector3],
		ramps: Array[Dictionary]) -> void:
	var half: float = 62.0
	var body: StaticBody3D = _solid_body(root, "LabyrinthWorldCollision")
	var batch := PropBatch.new()

	# Warm red-rock desert floor & wide desert horizon.
	_add_plane(root, "DesertHorizon", Vector2(1050.0, 1050.0),
		Vector3(0.0, -0.08, 0.0), Color("c96235"))
	_add_box_collider(body, Transform3D(Basis.IDENTITY, Vector3(0.0, -1.0, 0.0)),
		Vector3(150.0, 2.0, 150.0))

	_add_plane(root, "CanyonBasinFloor", Vector2(128.0, 128.0),
		Vector3(0.0, 0.0, 0.0), Color("df864a"))

	# Bold figure-8 desert track tiles (MultiMesh, 1 draw call).
	var tile_mesh := PlaneMesh.new()
	tile_mesh.size = Vector2(12.4, 12.4)
	var tile_xforms: Array = []
	var tile_cols: Array = []
	var sand_a := Color("e69558")
	var sand_b := Color("d67b42")
	var road_tint := Color("c45e33")
	for ix in range(-5, 5):
		for iz in range(-5, 5):
			var cx: float = (float(ix) + 0.5) * 12.4
			var cz: float = (float(iz) + 0.5) * 12.4
			tile_xforms.append(Transform3D(Basis.IDENTITY, Vector3(cx, 0.012, cz)))
			var on_main_street: bool = absf(cz) < 11.0 or (absf(absf(cx) - 34.0) < 9.0)
			if on_main_street:
				tile_cols.append(road_tint)
			else:
				tile_cols.append(sand_a if (ix + iz) % 2 == 0 else sand_b)
	root.add_child(SceneryKit.multimesh(tile_mesh, SceneryKit.instance_material(1.0),
		tile_xforms, "CanyonFloorTiles", false, tile_cols))

	# ------------------------------------------------------------------
	# 8 Towering Sandstone Rock Pillars / Mesa Blocks inside the arena!
	# Coordinates guarantee >= 14.0 m clear drift lanes everywhere!
	# ------------------------------------------------------------------
	var strata: Array[Color] = [
		Color("9e3921"), Color("bf4d2b"), Color("db723c"),
		Color("eb9d56"), Color("f2bf78"),
	]
	var pillar_specs: Array[Dictionary] = [
		{"pos": Vector3(-24.0, 0.0, -19.0), "w": 8.8, "d": 8.8, "h": 9.6, "yaw": 0.08},
		{"pos": Vector3(-24.0, 0.0, 19.0), "w": 8.8, "d": 8.8, "h": 10.4, "yaw": -0.06},
		{"pos": Vector3(24.0, 0.0, -19.0), "w": 8.8, "d": 8.8, "h": 10.2, "yaw": -0.07},
		{"pos": Vector3(24.0, 0.0, 19.0), "w": 8.8, "d": 8.8, "h": 9.4, "yaw": 0.09},
		{"pos": Vector3(-43.5, 0.0, -39.5), "w": 9.0, "d": 9.0, "h": 12.2, "yaw": 0.12},
		{"pos": Vector3(-43.5, 0.0, 39.5), "w": 9.0, "d": 9.0, "h": 11.6, "yaw": -0.11},
		{"pos": Vector3(43.5, 0.0, -39.5), "w": 9.0, "d": 9.0, "h": 11.8, "yaw": -0.10},
		{"pos": Vector3(43.5, 0.0, 39.5), "w": 9.0, "d": 9.0, "h": 12.4, "yaw": 0.11},
	]
	for spec: Dictionary in pillar_specs:
		var ppos: Vector3 = spec["pos"] as Vector3
		var pw: float = float(spec["w"])
		var pd: float = float(spec["d"])
		var ph: float = float(spec["h"])
		var pyaw: float = float(spec["yaw"])
		# Low bevelled sandstone kerb base + 4 stepped stratified rock tiers.
		var tiers: int = 4
		var cur_y: float = 0.0
		for t in tiers:
			var shrink: float = 1.0 - float(t) * 0.13
			var th: float = ph / float(tiers)
			var t_xf := Transform3D(Basis(Vector3.UP, pyaw + float(t) * 0.05),
				ppos + Vector3.UP * (cur_y + th * 0.5))
			batch.add_box(t_xf, Vector3(pw * shrink, th, pd * shrink),
				strata[t % strata.size()])
			cur_y += th
		batch.add_box(Transform3D(Basis(Vector3.UP, pyaw), ppos + Vector3.UP * (ph + 0.18)),
			Vector3(pw * 0.52, 0.36, pd * 0.52), strata[4])
		_add_box_collider(body, Transform3D(Basis(Vector3.UP, pyaw),
			ppos + Vector3.UP * (ph * 0.5)), Vector3(pw * 0.92, ph, pd * 0.92))
		pillars.append(ppos)

	# ------------------------------------------------------------------
	# Central Mesa Overpass Bridge (+3.85 m deck, 0.38 m slab -> 3.47 m
	# clear headroom >= 3.4 m over the 18 m-wide E/W Canyon Main Street!)
	# ------------------------------------------------------------------
	var bridge_y: float = 3.85
	var slab_t: float = 0.38
	# Central bridge deck: x in [-5.5, 5.5] (11.0 m wide), z in [-9.5, 9.5] (19.0 m span).
	_add_solid_box(batch, body,
		Transform3D(Basis.IDENTITY, Vector3(0.0, bridge_y - slab_t * 0.5, 0.0)),
		Vector3(11.0, slab_t, 19.0), strata[1])
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, bridge_y + 0.016, 0.0)),
		Vector3(10.2, 0.03, 18.8), strata[3])
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, bridge_y + 0.026, 0.0)),
		Vector3(1.2, 0.03, 18.4), Color("fff1d0"))
	# Low sandstone bridge side kerbs (with open central stunt gap? Keep low 0.75 m parapets
	# on outer 5 m and open middle 8 m so karts can also drop onto E/W street!).
	for z_sign: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(sx * 5.15, bridge_y + 0.42, z_sign * 6.8)),
				Vector3(0.70, 0.84, 5.4), strata[4])

		# N & S Ramps: climb from z = +-26.0 (y = 0.0) to z = +-9.5 (y = 3.85).
		# Run = 16.5 m, Rise = 3.85 m -> Slope = atan2(3.85, 16.5) = 13.13 deg <= 14 deg!
		var mr_start := Vector3(0.0, 0.0, z_sign * 26.0)
		var mr_end := Vector3(0.0, bridge_y, z_sign * 9.5)
		_add_ramp(batch, body, mr_start, mr_end, 10.4, 0.46,
			strata[2], strata[4], true, ramps)
		# Solid stepped mesa supports under each ramp: every top stays 0.30 m
		# below the ramp surface so the climb is never walled off. The old
		# full-height abutments poked ~0.6 m through the slope.
		for step_i in 4:
			var zc: float = z_sign * (21.0 - float(step_i) * 3.0)
			var surf_y: float = (26.0 - absf(zc)) / 16.5 * bridge_y
			var stop_y: float = surf_y - 0.30
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(0.0, stop_y * 0.5, zc)),
				Vector3(9.8, stop_y, 3.2), strata[0])

	# Canyon Perimeter Wall (124 x 124 m) + Red-Rock Rim Cliffs, Cacti & Palms outside!
	_build_enclosed_perimeter(root, body, batch, half, "barrierWall", "barrierRed")
	_dress_labyrinth_exterior(root, body, batch, half, strata)

	var canyon_mesh := MeshInstance3D.new()
	canyon_mesh.name = "LabyrinthMesaMesh"
	canyon_mesh.mesh = batch.build()
	canyon_mesh.material_override = SceneryKit.vertex_material()
	root.add_child(canyon_mesh)

	# 6 Canyon Boost Strips: E/W underpass main street, N/S outer canyon loops, bridge crest.
	_spawn_boost_pad(root, Vector3(-38.0, 0.02, 0.0), -PI * 0.5, 9.5, boost_spots)
	_spawn_boost_pad(root, Vector3(38.0, 0.02, 0.0), PI * 0.5, 9.5, boost_spots)
	_spawn_boost_pad(root, Vector3(-24.0, 0.02, -46.0), -PI * 0.5, 9.0, boost_spots)
	_spawn_boost_pad(root, Vector3(24.0, 0.02, 46.0), PI * 0.5, 9.0, boost_spots)
	_spawn_boost_pad(root, Vector3(0.0, bridge_y + 0.03, 0.0), 0.0, 9.0, boost_spots)
	_spawn_boost_pad(root, Vector3(0.0, 0.02, 46.0), 0.0, 9.0, boost_spots)

	# 8 Wide-Lane Canyon Spawns.
	var spawn_defs: Array[Array] = [
		[Vector3(-36.0, 0.38, -28.0), -PI * 0.25],
		[Vector3(36.0, 0.38, 28.0), PI * 0.75],
		[Vector3(-36.0, 0.38, 28.0), -PI * 0.75],
		[Vector3(36.0, 0.38, -28.0), PI * 0.25],
		[Vector3(-15.0, 0.38, 0.0), -PI * 0.5],
		[Vector3(15.0, 0.38, 0.0), PI * 0.5],
		[Vector3(0.0, 0.38, -44.0), PI],
		[Vector3(0.0, 0.38, 44.0), 0.0],
	]
	for item: Array in spawn_defs:
		spawns.append(Transform3D(Basis(Vector3.UP, float(item[1])), item[0] as Vector3))


static func _dress_labyrinth_exterior(root: Node3D, body: StaticBody3D,
		batch: PropBatch, half: float, strata: Array[Color]) -> void:
	# Towering canyon rim mesas outside the +-62 m barrier ring.
	var rim_spots: Array[Array] = [
		[Vector3(0.0, 0.0, -84.0), 56.0, 22.0, 20.0],
		[Vector3(0.0, 0.0, 84.0), 56.0, 22.0, 21.0],
		[Vector3(-84.0, 0.0, 0.0), 22.0, 56.0, 22.0],
		[Vector3(84.0, 0.0, 0.0), 22.0, 56.0, 19.0],
		[Vector3(-80.0, 0.0, -78.0), 28.0, 28.0, 24.0],
		[Vector3(80.0, 0.0, -78.0), 28.0, 28.0, 23.0],
		[Vector3(-80.0, 0.0, 78.0), 28.0, 28.0, 25.0],
		[Vector3(80.0, 0.0, 78.0), 28.0, 28.0, 22.0],
	]
	for rspec: Array in rim_spots:
		var rpos: Vector3 = rspec[0] as Vector3
		var rw: float = float(rspec[1])
		var rd: float = float(rspec[2])
		var rh: float = float(rspec[3])
		for t in 3:
			var s: float = 1.0 - float(t) * 0.16
			var th: float = rh / 3.0
			batch.add_box(Transform3D(Basis.IDENTITY,
				rpos + Vector3.UP * (float(t) * th + th * 0.5)),
				Vector3(rw * s, th, rd * s), strata[t % strata.size()])

	var cacti: Array = []
	var palms: Array = []
	var rocks: Array = []
	for i in 24:
		var ang: float = TAU * float(i) / 24.0
		var rad: float = half + 8.5 + float(i % 3) * 4.5
		var pos := Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
		if i % 3 == 0:
			palms.append(fit_transform("tree_palmTall", pos, ang, Vector3.ONE * 7.8, true))
		else:
			cacti.append(fit_transform("cactus_tall", pos, ang * 1.7, Vector3.ONE * 6.5, true))
		if i % 2 == 0:
			var rpos := Vector3(cos(ang + 0.12) * (rad + 5.0), 0.0, sin(ang + 0.12) * (rad + 5.0))
			rocks.append(fit_transform("rock_largeA", rpos, ang, Vector3.ONE * 5.6, true))
	batch_model(root, "cactus_tall", cacti, "LabyrinthCacti", false, true)
	batch_model(root, "tree_palmTall", palms, "LabyrinthPalms", false, true)
	batch_model(root, "rock_largeA", rocks, "LabyrinthRocks", false, true)

	var stands: Array = []
	for side: float in [-1.0, 1.0]:
		# Pushed well outside the +-62 m barrier ring at a smaller scale so
		# the stands no longer straddle the wall and cover edge tiles.
		var spos := Vector3(side * (half + 18.0), 0.0, 28.0 * side)
		var syaw: float = -PI * 0.5 if side < 0.0 else PI * 0.5
		stands.append(fit_transform("grandStand", spos, syaw, Vector3.ONE * 8.0))
		var sz: Vector3 = scaled_size("grandStand", Vector3.ONE * 8.0)
		_add_box_collider(body, Transform3D(Basis(Vector3.UP, syaw),
			spos + Vector3.UP * (sz.y * 0.5)), sz)
	batch_model(root, "grandStand", stands, "LabyrinthStands", true)


# ==========================================================================
# MAP 3: "bt_ferries" — TWIN FERRIES (West & East 36 x 96 m Cargo Ships,
#        12 m Open Water Channel at y = -3.0 m, 2 Arched Boarding Bridges
#        + 2 Opposing Boosted Gap-Jump Kickers!)
# ==========================================================================


static func _build_ferries(root: Node3D, spawns: Array[Transform3D],
		boost_spots: Array[Transform3D], pillars: Array[Vector3],
		ramps: Array[Dictionary]) -> void:
	var body: StaticBody3D = _solid_body(root, "FerriesWorldCollision")
	var batch := PropBatch.new()

	# Deep blue cartoon harbour ocean at y = -3.0 m (no collider on water —
	# falling karts splash below fall_y = -2.1 m and teleport to nearest safe spawn!).
	var water_y: float = -3.0
	_add_plane(root, "HarbourOcean", Vector2(1050.0, 1050.0),
		Vector3(0.0, water_y, 0.0), Color("166bb3"))
	# Channel lighter turquoise water strip + white wake foam lines along x = +-6.0 m.
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, water_y + 0.02, 0.0)),
		Vector3(13.6, 0.04, 118.0), Color("2396d9"))
	for side: float in [-1.0, 1.0]:
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(side * 5.85, water_y + 0.04, 0.0)),
			Vector3(0.55, 0.04, 102.0), Color("dff6ff"))

	# ------------------------------------------------------------------
	# West Ferry (x in [-42.0, -6.0]) & East Ferry (x in [+6.0, +42.0])
	# Each deck is 36.0 x 96.0 m at y = 0.0 m; open channel = 12.0 m!
	# ------------------------------------------------------------------
	var deck_w: float = 36.0
	var deck_l: float = 96.0
	var raised_y: float = 2.0

	for f_idx in 2:
		var side: float = -1.0 if f_idx == 0 else 1.0 ## -1 = West Ferry, +1 = East Ferry
		var cx: float = side * 24.0 ## Deck spans [cx - 18, cx + 18] = [-42..-6] or [+6..+42]
		var hull_main: Color = Color("c83e3b") if f_idx == 0 else Color("27598f")
		var hull_stripe := Color("f5f0e6")
		var deck_grey := Color("697684")
		var deck_lane := Color("798796")
		var accent_col: Color = Color("f4b63d") if f_idx == 0 else Color("3dc2e8")

		# Main Ship Hull & Deck Collider (36 x 96 m, top flush at y = 0.0 m, extends to y = -3.2 m).
		_add_solid_box(batch, body,
			Transform3D(Basis.IDENTITY, Vector3(cx, -1.60, 0.0)),
			Vector3(deck_w, 3.20, deck_l), hull_main)
		# Crisp white waterline stripe & dark lower keel band.
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(cx, -2.55, 0.0)),
			Vector3(deck_w + 0.24, 0.52, deck_l + 0.24), Color("222933"))
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(cx, -0.42, 0.0)),
			Vector3(deck_w + 0.18, 0.36, deck_l + 0.18), hull_stripe)
		# Tapered cartoon Bow (North, z = -48..-58) & Stern (South, z = +48..+55) hull prows.
		_add_frustum(batch, Transform3D(Basis(Vector3.UP, PI * 0.25),
			Vector3(cx, -1.5, -51.5)), 16.0, 9.0, 3.0, 4, hull_main)
		_add_frustum(batch, Transform3D(Basis(Vector3.UP, PI * 0.25),
			Vector3(cx, -1.5, 50.5)), 16.0, 12.0, 3.0, 4, hull_main.darkened(0.08))

		# Painted Steel Cargo Deck Markings (zero z-fighting, cm-stepped).
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(cx, 0.014, 0.0)),
			Vector3(deck_w - 1.2, 0.025, deck_l - 1.2), deck_grey)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(cx - side * 7.5, 0.026, 0.0)),
			Vector3(10.0, 0.025, 68.0), deck_lane)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(cx + side * 7.5, 0.026, 0.0)),
			Vector3(10.0, 0.025, 68.0), deck_lane)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(cx, 0.032, 0.0)),
			Vector3(0.65, 0.025, 52.0), accent_col)

		# --------------------------------------------------------------
		# Bow (+2.0 m) & Stern (+2.0 m) Raised Wheelhouse / Forecastle Decks
		# --------------------------------------------------------------
		for end_sign: float in [-1.0, 1.0]:
			var rz_center: float = end_sign * 42.0 ## Spans |z| in [36.0, 48.0] (12 m deep, 26 m wide)
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(cx, raised_y * 0.5, rz_center)),
				Vector3(26.0, raised_y, 12.0), Color("8895a3"))
			batch.add_box(Transform3D(Basis.IDENTITY, Vector3(cx, raised_y + 0.018, rz_center)),
				Vector3(25.0, 0.03, 11.2), accent_col.darkened(0.18))
			# Wide 12.5 deg ramp climbing from |z| = 27.0 (y = 0.0) to |z| = 36.0 (y = 2.0)!
			var wr_start := Vector3(cx, 0.0, end_sign * 27.0)
			var wr_end := Vector3(cx, raised_y, end_sign * 36.0)
			_add_ramp(batch, body, wr_start, wr_end, 10.4, 0.44,
				Color("9aa7b5"), hull_stripe, true, ramps)
			# Stepped fill under the ramp: every top stays 0.15 m below the
			# ramp surface. The old flat fill stood ~0.8 m across the climb.
			for wstep in 3:
				var wzc: float = end_sign * (29.0 + float(wstep) * 2.5)
				var wsurf: float = (absf(wzc) - 27.0) / 9.0 * raised_y
				var wtop: float = wsurf - 0.15
				_add_solid_box(batch, body,
					Transform3D(Basis.IDENTITY, Vector3(cx, wtop * 0.5, wzc)),
					Vector3(9.8, wtop, 2.7), Color("5b6673"))

			if end_sign < 0.0:
				# Bow Captain's Wheelhouse Cabin Tower (juke island on the +2.0 m bow deck!).
				var cab_pos := Vector3(cx, raised_y, -44.2)
				_add_solid_box(batch, body,
					Transform3D(Basis.IDENTITY, cab_pos + Vector3.UP * 1.45),
					Vector3(8.4, 2.9, 4.2), hull_stripe)
				batch.add_box(Transform3D(Basis.IDENTITY, cab_pos + Vector3.UP * 2.15),
					Vector3(8.6, 0.72, 4.4), Color("29435c"))
				batch.add_box(Transform3D(Basis.IDENTITY, cab_pos + Vector3.UP * 3.08),
					Vector3(9.2, 0.36, 4.9), hull_main)
				batch.add_cylinder(Transform3D(Basis.IDENTITY, cab_pos + Vector3.UP * 4.1),
					0.28, 1.8, 8, accent_col)
			else:
				# Stern Twin Cartoon Smokestacks!
				for sx_off: float in [-3.4, 3.4]:
					var fpos := Vector3(cx + sx_off, raised_y, 44.6)
					batch.add_cylinder(Transform3D(Basis.IDENTITY, fpos + Vector3.UP * 2.1),
						1.25, 4.2, 14, hull_main)
					batch.add_cylinder(Transform3D(Basis.IDENTITY, fpos + Vector3.UP * 3.85),
						1.30, 0.65, 14, Color("1f242d"))
					_add_cylinder_collider(body, fpos, 1.30, 4.2)

		# --------------------------------------------------------------
		# Colorful Container Juke Islands on Outer Cargo Lane (x = side * 31.0)
		# Leaves the entire inner lane (|x| in [6..25]) wide open for bridges & jumps!
		# --------------------------------------------------------------
		var container_colors: Array[Color] = [
			Color("e65b3c"), Color("2f9cd6"), Color("f0b429"), Color("42b868")
		]
		var c_z_spots: Array[float] = [-16.0, 0.0, 16.0]
		for c_i in c_z_spots.size():
			var cpos := Vector3(side * 30.5, 0.0, c_z_spots[c_i])
			var ccol: Color = container_colors[(c_i + f_idx * 2) % container_colors.size()]
			var ccol_top: Color = container_colors[(c_i + f_idx * 2 + 1) % container_colors.size()]
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, cpos + Vector3.UP * 1.35),
				Vector3(5.2, 2.7, 6.8), ccol)
			batch.add_box(Transform3D(Basis.IDENTITY, cpos + Vector3.UP * 2.75),
				Vector3(5.36, 0.12, 6.96), hull_stripe)
			if c_i != 1:
				_add_solid_box(batch, body,
					Transform3D(Basis(Vector3.UP, 0.06 * side), cpos + Vector3.UP * 3.95),
					Vector3(4.8, 2.3, 6.2), ccol_top)
			pillars.append(cpos)

		# --------------------------------------------------------------
		# Ship Perimeter Bulwark Railings:
		# Protect outer sea edges & bow/stern corners, while leaving deliberate
		# OPEN SLOTS at the 2 Boarding Bridges (z = +-18), 2 Jump Kickers
		# (z = +-5.5), and 2 stunt channel slots (z = +-30.5)!
		# --------------------------------------------------------------
		var outer_x: float = side * 41.55
		_add_solid_box(batch, body,
			Transform3D(Basis.IDENTITY, Vector3(outer_x, 0.65, 0.0)),
			Vector3(0.90, 1.30, deck_l), hull_stripe)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(outer_x, 1.35, 0.0)),
			Vector3(0.96, 0.18, deck_l), accent_col)
		for end_sign: float in [-1.0, 1.0]:
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(cx, raised_y + 0.60, end_sign * 47.55)),
				Vector3(26.0, 1.20, 0.90), hull_stripe)
			# Corner outer deck wings beside the raised bow/stern.
			for wing_s: float in [-1.0, 1.0]:
				var wx: float = cx + wing_s * 15.5
				_add_solid_box(batch, body,
					Transform3D(Basis.IDENTITY, Vector3(wx, 0.60, end_sign * 47.55)),
					Vector3(5.0, 1.20, 0.90), hull_stripe)

		# Inner channel edge (x = side * 6.45) segmented railings with deliberate open slots!
		# Bridges occupy z in [-22.6..-13.4] and [+13.4..+22.6].
		# Kickers/landings occupy z in [-10.2..-0.8] and [+0.8..+10.2].
		# Stunt gap slots occupy z in [-33.5..-27.5] and [+27.5..+33.5].
		var inner_x: float = side * 6.45
		var rail_spans: Array[Vector2] = [
			Vector2(-47.5, -33.5),
			Vector2(-27.5, -22.8),
			Vector2(-13.2, -10.4),
			Vector2(10.4, 13.2),
			Vector2(22.8, 27.5),
			Vector2(33.5, 47.5),
		]
		for span: Vector2 in rail_spans:
			var rlen: float = span.y - span.x
			var rmid: float = (span.x + span.y) * 0.5
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(inner_x, 0.58, rmid)),
				Vector3(0.85, 1.16, rlen), hull_stripe)
			batch.add_box(Transform3D(Basis.IDENTITY, Vector3(inner_x, 1.20, rmid)),
				Vector3(0.92, 0.16, rlen), Color("ff595e"))

	# ------------------------------------------------------------------
	# 2 Wide Arched Steel Boarding Bridges (+2.2 m crest) at z = -18 & z = +18
	# Span cleanly across the 12 m water channel (x = -16 -> -5 -> +5 -> +16)
	# ------------------------------------------------------------------
	var bridge_crest_y: float = 2.20
	var steel_col := Color("f2a93b")
	var steel_dark := Color("394859")
	for bz: float in [-18.0, 18.0]:
		# Central crest deck spanning x in [-5.2, +5.2] at y = +2.20 m (width = 9.0 m).
		_add_solid_box(batch, body,
			Transform3D(Basis.IDENTITY, Vector3(0.0, bridge_crest_y - 0.22, bz)),
			Vector3(10.4, 0.44, 9.0), steel_dark)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, bridge_crest_y + 0.018, bz)),
			Vector3(10.2, 0.03, 8.4), Color("aab6c4"))
		# West & East Boarding Ramps: |x| = 16.2 (y = 0.0) -> |x| = 5.2 (y = 2.20).
		# Run = 11.0 m, Rise = 2.20 m -> 11.31 deg (<= 14 deg!).
		_add_ramp(batch, body, Vector3(-16.2, 0.0, bz), Vector3(-5.2, bridge_crest_y, bz),
			9.0, 0.44, steel_dark, steel_col, true, ramps)
		_add_ramp(batch, body, Vector3(16.2, 0.0, bz), Vector3(5.2, bridge_crest_y, bz),
			9.0, 0.44, steel_dark, steel_col, true, ramps)

		# Arched overhead cartoon steel truss portals + sturdy bridge side guardrails!
		for z_off: float in [-4.25, 4.25]:
			_add_solid_box(batch, body,
				Transform3D(Basis.IDENTITY, Vector3(0.0, bridge_crest_y + 0.55, bz + z_off)),
				Vector3(10.6, 1.10, 0.55), steel_col)
			# Overhead steel arch ribs (>= 4.2 m clear above crest deck!).
			for post_x: float in [-4.8, 4.8]:
				batch.add_box(Transform3D(Basis.IDENTITY,
					Vector3(post_x, bridge_crest_y + 2.3, bz + z_off)),
					Vector3(0.55, 4.6, 0.55), steel_col)
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(0.0, bridge_crest_y + 4.45, bz + z_off)),
				Vector3(10.2, 0.55, 0.55), steel_col)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, bridge_crest_y + 4.55, bz)),
			Vector3(0.65, 0.45, 9.0), Color("ff595e"))

	# ------------------------------------------------------------------
	# 2 Opposing High-Speed Gap-Jump Kickers across the 12 m Water Channel!
	#   North-Center Kicker (z = -5.5): jumps West -> East (-15.5 -> -6.0, +2.35 m)
	#   South-Center Kicker (z = +5.5): jumps East -> West (+15.5 -> +6.0, +2.35 m)
	#   Slope = atan2(2.35, 9.5) = 13.89 deg <= 14 deg!
	#   Paired with high-burst BoostPads so karts soar cleanly over all 12 m!
	# ------------------------------------------------------------------
	var kicker_h: float = 2.35
	# West -> East Kicker at z = -5.5:
	_add_ramp(batch, body, Vector3(-15.5, 0.0, -5.5), Vector3(-6.0, kicker_h, -5.5),
		8.2, 0.46, Color("ff6b35"), Color("ffd22e"), true, ramps)
	# Stepped supports under the kicker: every top stays 0.12 m below the
	# ramp surface so the deck never pokes through. The old flat fill stood
	# ~0.8 m across the low half of the climb.
	for kstep in 5:
		var kxc: float = [-14.5, -12.5, -10.5, -8.5, -7.0][kstep]
		var ksurf: float = (kxc + 15.5) / 9.5 * kicker_h
		var kstop: float = maxf(ksurf - 0.12, 0.05)
		_add_solid_box(batch, body,
			Transform3D(Basis.IDENTITY, Vector3(kxc, kstop * 0.5, -5.5)),
			Vector3(2.0, kstop, 7.6), Color("394859"))
	# Landing target chevron pad on East Ferry at (+10.5, 0.03, -5.5) + gentle catch bevel:
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(11.0, 0.03, -5.5)),
		Vector3(9.6, 0.04, 9.2), Color("38d6f0"))
	_spawn_boost_pad(root, Vector3(-18.2, 0.03, -5.5), -PI * 0.5, 12.5, boost_spots)
	_spawn_boost_pad(root, Vector3(-10.8, kicker_h * 0.50 + 0.08, -5.5),
		-PI * 0.5, 13.0, boost_spots, atan2(kicker_h, 9.5))

	# East -> West Kicker at z = +5.5:
	_add_ramp(batch, body, Vector3(15.5, 0.0, 5.5), Vector3(6.0, kicker_h, 5.5),
		8.2, 0.46, Color("ff6b35"), Color("ffd22e"), true, ramps)
	for kstep in 5:
		var kxc2: float = [14.5, 12.5, 10.5, 8.5, 7.0][kstep]
		var ksurf2: float = (15.5 - kxc2) / 9.5 * kicker_h
		var kstop2: float = maxf(ksurf2 - 0.12, 0.05)
		_add_solid_box(batch, body,
			Transform3D(Basis.IDENTITY, Vector3(kxc2, kstop2 * 0.5, 5.5)),
			Vector3(2.0, kstop2, 7.6), Color("394859"))
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(-11.0, 0.03, 5.5)),
		Vector3(9.6, 0.04, 9.2), Color("38d6f0"))
	_spawn_boost_pad(root, Vector3(18.2, 0.03, 5.5), PI * 0.5, 12.5, boost_spots)
	_spawn_boost_pad(root, Vector3(10.8, kicker_h * 0.50 + 0.08, 5.5),
		PI * 0.5, 13.0, boost_spots, atan2(kicker_h, 9.5))

	# Deck outer straightaway BoostPads (1 on West Ferry, 1 on East Ferry).
	_spawn_boost_pad(root, Vector3(-21.0, 0.03, 24.0), 0.0, 9.0, boost_spots)
	_spawn_boost_pad(root, Vector3(21.0, 0.03, -24.0), PI, 9.0, boost_spots)

	# Harbour Buoys, Cranes & Distant Breakwater Scenery in the surrounding water.
	_dress_ferries_harbour(root, batch, water_y)

	var ferries_mesh := MeshInstance3D.new()
	ferries_mesh.name = "TwinFerriesMesh"
	ferries_mesh.mesh = batch.build()
	ferries_mesh.material_override = SceneryKit.vertex_material()
	root.add_child(ferries_mesh)

	# 8 Safe Ferry Deck Spawns (4 on West Ferry, 4 on East Ferry, well clear of water).
	var spawn_defs: Array[Array] = [
		[Vector3(-21.0, 0.38, -26.0), PI],
		[Vector3(21.0, 0.38, 26.0), 0.0],
		[Vector3(-21.0, 0.38, 26.0), 0.0],
		[Vector3(21.0, 0.38, -26.0), PI],
		[Vector3(-36.0, 0.38, -8.0), PI],
		[Vector3(36.0, 0.38, 8.0), 0.0],
		[Vector3(-36.0, 0.38, 12.0), 0.0],
		[Vector3(36.0, 0.38, -12.0), PI],
	]
	for item: Array in spawn_defs:
		spawns.append(Transform3D(Basis(Vector3.UP, float(item[1])), item[0] as Vector3))


static func _dress_ferries_harbour(root: Node3D, batch: PropBatch, water_y: float) -> void:
	# Floating red/green harbour channel buoys & distant cartoon lighthouse island.
	var buoy_spots: Array[Vector3] = [
		Vector3(0.0, water_y, -56.0), Vector3(0.0, water_y, 56.0),
		Vector3(-56.0, water_y, -32.0), Vector3(56.0, water_y, -32.0),
		Vector3(-56.0, water_y, 32.0), Vector3(56.0, water_y, 32.0),
	]
	for i in buoy_spots.size():
		var bpos: Vector3 = buoy_spots[i]
		var bcol: Color = Color("e84848") if i % 2 == 0 else Color("3ebf62")
		batch.add_cylinder(Transform3D(Basis.IDENTITY, bpos + Vector3.UP * 0.45),
			1.55, 0.90, 12, bcol)
		_add_frustum(batch, Transform3D(Basis.IDENTITY, bpos + Vector3.UP * 1.65),
			1.05, 0.25, 1.55, 10, Color("f7f3e8"))
		batch.add_cylinder(Transform3D(Basis.IDENTITY, bpos + Vector3.UP * 2.65),
			0.35, 0.45, 10, Color("ffd22e"))

	# Distant cartoon rocky lighthouse islet at (0, water_y, -92) for horizon framing.
	var isle := Vector3(0.0, water_y, -92.0)
	_add_frustum(batch, Transform3D(Basis.IDENTITY, isle + Vector3.UP * 1.6),
		15.0, 9.5, 3.2, 12, Color("7e878f"))
	_add_frustum(batch, Transform3D(Basis.IDENTITY, isle + Vector3.UP * 6.2),
		2.8, 1.9, 6.0, 12, Color("f7f3e8"))
	_add_frustum(batch, Transform3D(Basis.IDENTITY, isle + Vector3.UP * 11.2),
		2.1, 1.6, 4.0, 12, Color("d9413b"))
	batch.add_cylinder(Transform3D(Basis.IDENTITY, isle + Vector3.UP * 14.0),
		1.8, 1.6, 12, Color("ffe373"))

	var lights: Array = []
	var flags_r: Array = []
	var flags_g: Array = []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			lights.append(fit_transform("lightPostModern",
				Vector3(sx * 40.5, 0.0, sz * 32.0), -sx * PI * 0.5, Vector3.ONE * 10.0))
			if sx < 0.0:
				flags_r.append(fit_transform("flagRed",
					Vector3(sx * 35.0, 2.0, sz * 46.5), 0.0, Vector3.ONE * 7.5))
			else:
				flags_g.append(fit_transform("flagGreen",
					Vector3(sx * 35.0, 2.0, sz * 46.5), 0.0, Vector3.ONE * 7.5))
	batch_model(root, "lightPostModern", lights, "FerryDeckLights", false)
	batch_model(root, "flagRed", flags_r, "WestFerryFlags", false)
	batch_model(root, "flagGreen", flags_g, "EastFerryFlags", false)


static func _add_dynamic_landmarks(root: Node3D, resolved: String) -> void:
	var anim: Dictionary = AmbientWorld.anim_of(root)
	var holder := Node3D.new()
	holder.name = "DynamicLandmarks_" + resolved
	root.add_child(holder)
	var batch := PropBatch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = resolved.hash() ^ 0x4A12
	match resolved:
		"bt_plaza":
			var hill_pal := {
				"skirt": Color("478735"),
				"mid": Color("60a844"),
				"top": Color("77c254"),
			}
			for i in 12:
				var ang: float = TAU * float(i) / 12.0 + 0.16
				var dist: float = 128.0 + float(i % 3) * 28.0
				LandscapeSculptor.add_woodland_hill(batch,
					Vector3(cos(ang) * dist, -0.1, sin(ang) * dist),
					38.0 + float(i % 3) * 10.0, 32.0 + float((i + 1) % 3) * 8.0,
					16.0 + float(i % 4) * 5.5, rng, hill_pal)
			batch.flush_to(holder, "PlazaHorizonHills", false, SceneryKit.vertex_material())
			LandscapeSculptor.build_windmill(holder, Vector3(-96.0, 0.0, -88.0), 0.7, 1.3,
				"meadow", anim)
			LandscapeSculptor.build_windmill(holder, Vector3(98.0, 0.0, 86.0), -2.4, 1.25,
				"meadow", anim)
			LandscapeSculptor.build_hot_air_balloon(holder, Vector3(84.0, 32.0, -76.0),
				Color("ff595e"), Color("ffd22e"), 0.4, anim)
			LandscapeSculptor.build_hot_air_balloon(holder, Vector3(-88.0, 36.0, 74.0),
				Color("38d6f0"), Color("ffd22e"), 2.1, anim)
			LandscapeSculptor.build_hot_air_balloon(holder, Vector3(12.0, 38.0, -118.0),
				Color("9d6bff"), Color("ffd22e"), 4.0, anim)
			LandscapeSculptor.add_biome_particles(holder, "bt_plaza", Vector3.ZERO, 90.0)
		"bt_labyrinth":
			var mesa_pal := {
				"base": Color("914228"),
				"mid": Color("b85a35"),
				"top": Color("d97a45"),
				"cap": Color("e89e5a"),
			}
			for i in 12:
				var ang: float = TAU * float(i) / 12.0 + 0.21
				var dist: float = 122.0 + float(i % 3) * 28.0
				var pos := Vector3(cos(ang) * dist, -0.2, sin(ang) * dist)
				if i % 3 == 0:
					LandscapeSculptor.add_canyon_spire(batch, pos, 18.0 + float(i % 2) * 5.0,
						32.0 + float(i % 4) * 7.0, rng)
				else:
					LandscapeSculptor.add_stratified_mesa(batch, pos,
						28.0 + float(i % 3) * 8.0, 26.0 + float(i % 4) * 8.0,
						3, rng, mesa_pal)
			LandscapeSculptor.add_natural_arch(batch, null,
				Vector3(0.0, 0.0, -124.0), 0.15, 28.0, 14.0, 6.0,
				Color("b85a35"), Color("e89e5a"))
			batch.flush_to(holder, "LabyrinthHorizonMesas", false, SceneryKit.vertex_material())
			LandscapeSculptor.build_windmill(holder, Vector3(-98.0, 0.0, 74.0), 0.85, 1.25,
				"canyon", anim)
			LandscapeSculptor.add_biome_particles(holder, "bt_labyrinth", Vector3.ZERO, 90.0)
		"bt_ferries":
			var coast_pal := {
				"skirt": Color("47853b"),
				"mid": Color("5da346"),
				"top": Color("76bd52"),
			}
			for i in 10:
				var ang: float = TAU * float(i) / 10.0 + 0.28
				var dist: float = 148.0 + float(i % 3) * 32.0
				LandscapeSculptor.add_woodland_hill(batch,
					Vector3(cos(ang) * dist, -3.2, sin(ang) * dist),
					38.0 + float(i % 3) * 11.0, 32.0 + float((i + 1) % 3) * 9.0,
					18.0 + float(i % 4) * 7.0, rng, coast_pal)
			batch.flush_to(holder, "FerriesCoastline", false, SceneryKit.vertex_material())
			LandscapeSculptor.build_lighthouse(holder, Vector3(-108.0, -2.5, -98.0), 19.0, anim)
			LandscapeSculptor.build_cargo_ship(holder, Vector3(-96.0, -3.1, -24.0), 0.15, 1.35, anim)
			LandscapeSculptor.build_cargo_ship(holder, Vector3(98.0, -3.1, 28.0), 3.05, 1.30, anim)
			LandscapeSculptor.build_port_crane(holder, Vector3(-84.0, -3.0, 78.0), -1.1, 20.0,
				Color("ff9f2e"), anim)
			LandscapeSculptor.build_port_crane(holder, Vector3(84.0, -3.0, -78.0), 2.1, 20.0,
				Color("e65142"), anim)
			LandscapeSculptor.add_biome_particles(holder, "bt_ferries", Vector3.ZERO, 90.0)


# ==========================================================================
# SHARED GEOMETRY, RAMP, COLLIDER & KENNEY MODEL HELPERS
# ==========================================================================


static func _solid_body(parent: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	return body


static func _add_box_collider(body: StaticBody3D, xform: Transform3D,
		size: Vector3) -> void:
	if body == null:
		return
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(size.x, 0.05), maxf(size.y, 0.05), maxf(size.z, 0.05))
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = xform
	body.add_child(col)


static func _add_cylinder_collider(body: StaticBody3D, base_center: Vector3,
		radius: float, height: float) -> void:
	if body == null:
		return
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, 0.05)
	shape.height = maxf(height, 0.10)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = base_center + Vector3.UP * (shape.height * 0.5)
	body.add_child(col)


static func _add_solid_box(batch: PropBatch, body: StaticBody3D,
		xform: Transform3D, size: Vector3, color: Color) -> void:
	batch.add_box(xform, size, color)
	_add_box_collider(body, xform, size)


static func _add_plane(parent: Node3D, node_name: String, size: Vector2,
		pos: Vector3, color: Color) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = node_name
	var plane := PlaneMesh.new()
	plane.size = size
	inst.mesh = plane
	inst.position = pos
	inst.material_override = flat_material(color, false)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	return inst


## Builds a smooth drivable ramp whose top surface runs flush from `start_pos`
## to `end_pos`, with orthonormal vector Basis (exact in all 360 deg yaws),
## matching WORLD BoxShape3D collider, chevron centre stripe, and optional low
## side kerbs, and appends `{bottom, top, tier_y}` to `ramps` for AI navigation.
static func _add_ramp(batch: PropBatch, body: StaticBody3D, start_pos: Vector3,
		end_pos: Vector3, width: float, thickness: float, deck_color: Color,
		trim_color: Color, with_kerbs: bool, ramps: Array[Dictionary]) -> void:
	var span: Vector3 = end_pos - start_pos
	var length: float = span.length()
	if length < 0.2:
		return
	var z_axis: Vector3 = span / length
	var x_axis: Vector3 = Vector3.UP.cross(z_axis)
	if x_axis.length_squared() < 0.0001:
		x_axis = Vector3.RIGHT
	else:
		x_axis = x_axis.normalized()
	var y_axis: Vector3 = z_axis.cross(x_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	var top_mid: Vector3 = (start_pos + end_pos) * 0.5
	var slab_center: Vector3 = top_mid - y_axis * (thickness * 0.5)
	var slab_size := Vector3(width, thickness, length + 0.18)
	var slab_xf := Transform3D(basis, slab_center)
	batch.add_box(slab_xf, slab_size, deck_color)
	_add_box_collider(body, slab_xf, slab_size)

	# Painted centre guide stripe along the ramp slope.
	batch.add_box(Transform3D(basis, top_mid + y_axis * 0.018),
		Vector3(0.85, 0.03, length * 0.86), Color("ffd22e"))

	if with_kerbs:
		var kerb_w: float = 0.45
		var kerb_h: float = 0.34
		for side: float in [-1.0, 1.0]:
			var k_center: Vector3 = top_mid + x_axis * (side * (width * 0.5 - kerb_w * 0.5)) \
				+ y_axis * (kerb_h * 0.5)
			var k_xf := Transform3D(basis, k_center)
			var k_size := Vector3(kerb_w, kerb_h, length * 0.92)
			batch.add_box(k_xf, k_size, trim_color)
			_add_box_collider(body, k_xf, k_size)

	ramps.append({
		"bottom": start_pos,
		"top": end_pos,
		"tier_y": end_pos.y,
		"width": width,
	})


## Builds a tapered cartoon frustum / cone / pyramid using PropBatch quads + caps.
static func _add_frustum(batch: PropBatch, xform: Transform3D, bottom_r: float,
		top_r: float, height: float, segments: int, color: Color) -> void:
	var count: int = maxi(segments, 3)
	var half: float = height * 0.5
	var c_top: Vector3 = xform * Vector3(0.0, half, 0.0)
	var c_bot: Vector3 = xform * Vector3(0.0, -half, 0.0)
	for i in count:
		var a0: float = TAU * float(i) / float(count)
		var a1: float = TAU * float(i + 1) / float(count)
		var b0 := Vector3(cos(a0) * bottom_r, -half, sin(a0) * bottom_r)
		var b1 := Vector3(cos(a1) * bottom_r, -half, sin(a1) * bottom_r)
		var t0 := Vector3(cos(a0) * top_r, half, sin(a0) * top_r)
		var t1 := Vector3(cos(a1) * top_r, half, sin(a1) * top_r)
		batch.add_quad(xform * b0, xform * t0, xform * t1, xform * b1, color)
		if top_r > 0.01:
			batch.add_triangle(c_top, xform * t1, xform * t0, color.lightened(0.08))
		batch.add_triangle(c_bot, xform * b0, xform * b1, color.darkened(0.08))


## Enclosed Kenney barrier ring around a `half`-metre square arena, backed by 4
## continuous WORLD wall colliders so no high-speed kart can ever snag a seam.
static func _build_enclosed_perimeter(root: Node3D, body: StaticBody3D,
		batch: PropBatch, half: float, model_a: String, model_b: String) -> void:
	var tile: float = 16.0
	var count: int = maxi(int(round((half * 2.0) / tile)), 4)
	var step: float = (half * 2.0) / float(count)
	var b_size: Vector3 = scaled_size(model_a, Vector3.ONE * step)
	var depth: float = maxf(b_size.z, 1.4)
	var wall_h: float = maxf(b_size.y, 2.8)
	var xforms_a: Array = []
	var xforms_b: Array = []
	for side: float in [-1.0, 1.0]:
		for i in count:
			var along: float = -half + step * (float(i) + 0.5)
			var xf_ns: Transform3D = fit_transform(model_a if i % 2 == 0 else model_b,
				Vector3(along, 0.0, side * (half + depth * 0.5)), 0.0, Vector3.ONE * step)
			var xf_ew: Transform3D = fit_transform(model_b if i % 2 == 0 else model_a,
				Vector3(side * (half + depth * 0.5), 0.0, along), PI * 0.5, Vector3.ONE * step)
			if i % 2 == 0:
				xforms_a.append(xf_ns)
				xforms_b.append(xf_ew)
			else:
				xforms_b.append(xf_ns)
				xforms_a.append(xf_ew)
		var span: float = half * 2.0 + depth * 2.0
		_add_box_collider(body, Transform3D(Basis.IDENTITY,
			Vector3(0.0, wall_h * 0.5 + 0.6, side * (half + depth * 0.5))),
			Vector3(span, wall_h + 1.2, depth))
		_add_box_collider(body, Transform3D(Basis.IDENTITY,
			Vector3(side * (half + depth * 0.5), wall_h * 0.5 + 0.6, 0.0)),
			Vector3(depth, wall_h + 1.2, span))
		# Crisp boundary paint stripe inside the arena wall.
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.024, side * (half - 1.4))),
			Vector3(half * 2.0 - 2.8, 0.03, 0.55), Color("fff6e3"))
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(side * (half - 1.4), 0.024, 0.0)),
			Vector3(0.55, 0.03, half * 2.0 - 2.8), Color("fff6e3"))
	batch_model(root, model_a, xforms_a, "PerimeterA", true)
	if model_b != model_a:
		batch_model(root, model_b, xforms_b, "PerimeterB", true)
	else:
		batch_model(root, model_a, xforms_b, "PerimeterA2", true)


static func _spawn_boost_pad(root: Node3D, at: Vector3, yaw: float,
		burst: float, boost_spots: Array[Transform3D], pitch: float = 0.0) -> void:
	var basis: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var xf := Transform3D(basis, at)
	boost_spots.append(xf)
	if BOOST_PAD_SCENE == null:
		return
	var pad: Area3D = BOOST_PAD_SCENE.instantiate() as Area3D
	if pad == null:
		return
	pad.name = "ArenaBoostPad_%d" % boost_spots.size()
	pad.transform = xf
	pad.set("burst_speed", burst)
	root.add_child(pad)


static func flat_material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var key: String = "%s/%s" % [color.to_html(), str(unshaded)]
	if _flat_mat_cache.has(key):
		return _flat_mat_cache[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.96
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flat_mat_cache[key] = mat
	return mat


static func model_info(model: String, nature: bool = false) -> Dictionary:
	var path: String = (NATURE_ROOT if nature else RACING_ROOT) + model + ".glb"
	if _model_cache.has(path):
		return _model_cache[path] as Dictionary
	var info: Dictionary = {"ok": false, "path": path}
	if not ResourceLoader.exists(path):
		_model_cache[path] = info
		return info
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		_model_cache[path] = info
		return info
	var inst: Node = packed.instantiate()
	var aabb: AABB = _measure_aabb(inst, Transform3D.IDENTITY)
	var parts: Array = []
	_collect_parts(inst, Transform3D.IDENTITY, parts)
	inst.free()
	info["ok"] = true
	info["aabb"] = aabb
	info["center"] = Vector2((aabb.position.x + aabb.end.x) * 0.5,
		(aabb.position.z + aabb.end.z) * 0.5)
	info["size"] = aabb.size
	info["parts"] = parts
	_model_cache[path] = info
	return info


static func fit_transform(model: String, at: Vector3, yaw: float,
		scale: Vector3, nature: bool = false) -> Transform3D:
	var info: Dictionary = model_info(model, nature)
	if not bool(info.get("ok", false)):
		return Transform3D(Basis(Vector3.UP, yaw).scaled(scale), at)
	var center: Vector2 = info["center"] as Vector2
	var aabb: AABB = info["aabb"] as AABB
	var yaw_basis := Basis(Vector3.UP, yaw)
	var basis: Basis = yaw_basis * Basis.IDENTITY.scaled(scale)
	var center_m := Vector3(center.x * scale.x, 0.0, center.y * scale.z)
	var lift: float = -aabb.position.y * scale.y
	return Transform3D(basis, at - yaw_basis * center_m + Vector3.UP * lift)


static func scaled_size(model: String, scale: Vector3,
		nature: bool = false) -> Vector3:
	var info: Dictionary = model_info(model, nature)
	if not bool(info.get("ok", false)):
		return Vector3(1.0, 1.0, 1.0)
	return (info["aabb"] as AABB).size * scale


static func batch_model(parent: Node3D, model: String, transforms: Array,
		node_name: String, cast_shadow: bool = true,
		nature: bool = false) -> void:
	if parent == null or transforms.is_empty():
		return
	var info: Dictionary = model_info(model, nature)
	if not bool(info.get("ok", false)):
		return
	var parts: Array = info.get("parts", []) as Array
	for p_idx in parts.size():
		var part: Dictionary = parts[p_idx] as Dictionary
		var mesh: Mesh = part.get("mesh") as Mesh
		var local: Transform3D = part.get("transform", Transform3D.IDENTITY) as Transform3D
		if mesh == null:
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = transforms.size()
		for idx in transforms.size():
			multi.set_instance_transform(idx, (transforms[idx] as Transform3D) * local)
		var inst := MultiMeshInstance3D.new()
		inst.name = node_name if parts.size() == 1 else "%s_%d" % [node_name, p_idx]
		inst.multimesh = multi
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(inst)


static func _measure_aabb(node: Node, xform: Transform3D) -> AABB:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	var result := AABB()
	var found: bool = false
	if node is MeshInstance3D:
		var m_inst := node as MeshInstance3D
		if m_inst.mesh != null:
			result = local * m_inst.mesh.get_aabb()
			found = true
	for child: Node in node.get_children():
		var child_box: AABB = _measure_aabb(child, local)
		if child is MeshInstance3D or child_box.size.length_squared() > 0.00001:
			result = result.merge(child_box) if found else child_box
			found = true
	return result


static func _collect_parts(node: Node, xform: Transform3D, parts: Array) -> void:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var m_inst := node as MeshInstance3D
		if m_inst.mesh != null:
			parts.append({"mesh": m_inst.mesh, "transform": local})
	for child: Node in node.get_children():
		_collect_parts(child, local, parts)
