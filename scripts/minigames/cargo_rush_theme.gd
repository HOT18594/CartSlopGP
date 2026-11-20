extends RefCounted
## The three DELIVER (Cargo Rush) 3D cartoon maps, chosen by map/theme id:
##   * `harbour`   — HARBOUR OVERPASS: central +2.2 m steel bridge overpass with
##                   broad N/S approach ramps, twin side water-channel splash
##                   trenches, shipping container chicanes and bridge-deck crates.
##   * `farmyard`  — WINDMILL HILLS: central +2.0 m earthen hilltop plateau with
##                   4 wide N/S/E/W dirt ramps, red barn windmill & silo, flanking
##                   mud trenches (0.70 grip) crossed by fast timber plank bridges,
##                   and L-shaped hay-bale chicanes.
##   * `snowfield` — GLACIER BOWL: sunken/berm-ringed central frozen ice rink
##                   (0.45 grip inside radius < 28 m) surrounded by 4 inward
##                   snow-berm jump ramps, crystalline ice-pillar slaloms and a
##                   central ice-rink gift cluster.
##
## Art uses the CC0 Kenney kits + crisp flat vertex-coloured 3D geometry only
## (zero photorealistic PBR textures). Every solid ramp, deck, berm, container,
## hay wall and spire carries an exact CollisionLayers.WORLD physics collider.

const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")

const RACING_ROOT: String = "res://assets/models/kenney_racing_kit/Models/GLTF format/"
const NATURE_ROOT: String = "res://assets/models/kenney_nature_kit/Models/GLTF format/"
const CAR_ROOT: String = "res://assets/models/kenney_car-kit/Models/GLB format/"
const CRATE_MODEL: String = "box"

const DEFAULT_ID: String = "harbour"
const THEME_IDS: PackedStringArray = ["harbour", "farmyard", "snowfield"]

## Surface grip constants per map hazard.
const ICE_BOWL_GRIP: float = 0.45
const ICE_BOWL_SPIN: float = 0.32
const MUD_TRENCH_GRIP: float = 0.70
const WATER_CHANNEL_GRIP: float = 0.76
const WATER_CHANNEL_DRAG: float = 1.55

## Present art. Pickups never block a kart.
const CRATE_SCALE: float = 1.8
const HAZARD_RADIUS: float = 5.4

## Nature scale outside the 56 m arena fence.
const TREE_SCALE: float = 7.2
const BUSH_SCALE: float = 4.8
const ROCK_SCALE: float = 5.2
const TILE_SIZE: float = 16.0
const ARENA_HALF: float = 56.0
const FLOOR_SIZE: float = 170.0
const BASE_Z: Array[float] = [48.0, -48.0]
const PAD_HALF: Vector2 = Vector2(8.0, 5.0)

## Ambient wind for flags and banner towers (presentation only).
const WIND_DEFAULT: float = 1.0

## Outer scenery ring outside the 56 m barrier wall.
const TREE_RING: Array[Vector2] = [
	Vector2(-80.0, -80.0), Vector2(80.0, -80.0),
	Vector2(-80.0, 80.0), Vector2(80.0, 80.0),
	Vector2(-80.0, -48.0), Vector2(80.0, -48.0),
	Vector2(-80.0, 16.0), Vector2(80.0, 16.0),
	Vector2(-80.0, 48.0), Vector2(80.0, 48.0),
	Vector2(-64.0, -80.0), Vector2(-32.0, -80.0), Vector2(0.0, -80.0),
	Vector2(32.0, -80.0), Vector2(64.0, -80.0),
	Vector2(-64.0, 80.0), Vector2(-32.0, 80.0), Vector2(0.0, 80.0),
	Vector2(32.0, 80.0), Vector2(64.0, 80.0),
]
const BUSH_SPOTS: Array[Vector2] = [
	Vector2(-64.0, -32.0), Vector2(64.0, -32.0),
	Vector2(-64.0, 32.0), Vector2(64.0, 32.0),
	Vector2(-32.0, -64.0), Vector2(32.0, -64.0),
	Vector2(-32.0, 64.0), Vector2(32.0, 64.0),
]
const ROCK_SPOTS: Array[Vector2] = [
	Vector2(-64.0, -48.0), Vector2(64.0, -48.0),
	Vector2(-64.0, 48.0), Vector2(64.0, 48.0),
	Vector2(-48.0, -64.0), Vector2(48.0, -64.0),
	Vector2(-48.0, 64.0), Vector2(48.0, 64.0),
]

const HARBOUR_SPEC: Dictionary = {
	"id": "harbour",
	"name": "HARBOUR OVERPASS",
	"blurb": "STEEL BRIDGE & WATER TRENCHES",
	"teams": ["DOCK CREW", "HARBOUR RATS"],
	"sky_top": Color(0.16, 0.47, 0.72),
	"sky_horizon": Color(0.74, 0.87, 0.94),
	"ground_bottom": Color(0.15, 0.24, 0.29),
	"fog_color": Color(0.72, 0.84, 0.91),
	"fog_density": 0.0018,
	"ground": Color("476878"),
	"ground_alt": Color("527788"),
	"paint": Color("f5ecd7"),
	"paint_alt": Color("f0c243"),
	"grip": 0.96,
	"present_kind": "crate",
	"present_label": "CARGO CRATES",
	"present_accent": Color("f4c542"),
	"wind": 1.15,
	"hazard_label": "STEEL OVERPASS  ·  WATER CHANNELS",
	"tree_model": "tree_default",
	"tree_scale": 1.0,
	"present_spots": [
		Vector3(0.0, 2.20, -6.5),
		Vector3(0.0, 2.20, 6.5),
		Vector3(15.0, 0.0, -30.0),
		Vector3(-15.0, 0.0, -30.0),
		Vector3(15.0, 0.0, 30.0),
		Vector3(-15.0, 0.0, 30.0),
		Vector3(32.0, 0.0, 0.0),
		Vector3(-32.0, 0.0, 0.0),
	],
}

const FARMYARD_SPEC: Dictionary = {
	"id": "farmyard",
	"name": "WINDMILL HILLS",
	"blurb": "HILLTOP PLATEAU & MUD BRIDGES",
	"teams": ["PADDOCK POSSE", "BARN RAIDERS"],
	"sky_top": Color(0.22, 0.56, 0.80),
	"sky_horizon": Color(0.86, 0.90, 0.76),
	"ground_bottom": Color(0.32, 0.27, 0.16),
	"fog_color": Color(0.84, 0.87, 0.73),
	"fog_density": 0.0015,
	"ground": Color("6c9c46"),
	"ground_alt": Color("79ac52"),
	"paint": Color("f5ecd7"),
	"paint_alt": Color("f2b134"),
	"grip": 0.94,
	"present_kind": "crate",
	"present_label": "PRODUCE CRATES",
	"present_accent": Color("e4572e"),
	"wind": 0.85,
	"hazard_label": "HILLTOP RAMPS  ·  MUD & TIMBER BRIDGES",
	"tree_model": "tree_oak",
	"tree_scale": 0.95,
	"present_spots": [
		Vector3(0.0, 2.00, 0.0),
		Vector3(-5.8, 2.00, -5.8),
		Vector3(15.0, 0.0, -31.0),
		Vector3(-15.0, 0.0, -31.0),
		Vector3(15.0, 0.0, 31.0),
		Vector3(-15.0, 0.0, 31.0),
		Vector3(39.0, 0.0, 0.0),
		Vector3(-39.0, 0.0, 0.0),
	],
}

const SNOWFIELD_SPEC: Dictionary = {
	"id": "snowfield",
	"name": "GLACIER BOWL",
	"blurb": "SLICK ICE RINK & BERM JUMPS",
	"teams": ["YULECREW", "REINDEER"],
	"sky_top": Color(0.36, 0.62, 0.86),
	"sky_horizon": Color(0.90, 0.95, 0.99),
	"ground_bottom": Color(0.72, 0.80, 0.88),
	"fog_color": Color(0.88, 0.93, 0.98),
	"fog_density": 0.0020,
	"ground": Color("e2f0f7"),
	"ground_alt": Color("cee5f0"),
	"paint": Color("f7fbff"),
	"paint_alt": Color("2e86ab"),
	"grip": 0.94,
	"present_kind": "gift",
	"present_label": "WRAPPED GIFTS",
	"present_accent": Color("e23b4e"),
	"wind": 1.45,
	"hazard_label": "GLACIER ICE RINK  ·  4 BERM JUMP RAMPS",
	"tree_model": "tree_pineTallA",
	"tree_scale": 1.0,
	"present_spots": [
		Vector3(0.0, 0.0, 0.0),
		Vector3(8.5, 0.0, 0.0),
		Vector3(-8.5, 0.0, 0.0),
		Vector3(0.0, 0.0, 9.5),
		Vector3(16.0, 0.0, -33.0),
		Vector3(-16.0, 0.0, -33.0),
		Vector3(16.0, 0.0, 33.0),
		Vector3(-16.0, 0.0, 33.0),
	],
}

const THEMES: Dictionary = {
	"harbour": HARBOUR_SPEC,
	"dockyard": HARBOUR_SPEC,
	"farmyard": FARMYARD_SPEC,
	"snowfield": SNOWFIELD_SPEC,
}

static var _model_cache: Dictionary = {}
static var _paint_cache: Dictionary = {}


## Every canonical Deliver map id in registry order.
static func ids() -> PackedStringArray:
	return THEME_IDS


## Map a loose id (menu selection, legacy id, env override) to a Deliver map id.
static func resolve(id: String) -> String:
	var key: String = id.strip_edges().to_lower()
	match key:
		"harbour", "harbor", "dockyard", "dockyard_dash", "cargo_rush", "stadium":
			return "harbour"
		"farmyard", "farm", "windmill", "meadow", "meadow_loop", "circuit", "canyon":
			return "farmyard"
		"snowfield", "snow", "glacier_bowl", "alpine", "alpine_slide", "glacier":
			return "snowfield"
	return DEFAULT_ID


## The data block for `id`, never null.
static func get_theme(id: String) -> Dictionary:
	var key: String = resolve(id)
	var entry: Variant = THEMES.get(key, THEMES[DEFAULT_ID])
	return entry as Dictionary


## Custom 3D present spawn coordinates (including elevated Y!) for `theme`.
static func present_spots(theme: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var raw: Variant = theme.get("present_spots", [])
	if raw is Array:
		for entry: Variant in raw as Array:
			if entry is Vector3:
				out.append(entry as Vector3)
	if out.is_empty():
		for fallback: Vector3 in HARBOUR_SPEC["present_spots"] as Array:
			out.append(fallback)
	return out


## The two team names, always exactly two entries.
static func team_names(theme: Dictionary) -> PackedStringArray:
	var names := PackedStringArray()
	var raw: Variant = theme.get("teams", [])
	if raw is Array:
		for entry: Variant in raw as Array:
			names.append(str(entry))
	while names.size() < 2:
		names.append("CREW %d" % (names.size() + 1))
	return names


## Human label for what a present is in this theme.
static func present_label(theme: Dictionary) -> String:
	return str(theme.get("present_label", "CRATES"))


# --------------------------------------------------------------------------
# materials
# --------------------------------------------------------------------------


static func floor_material(theme: Dictionary) -> Material:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = theme.get("ground", Color("476878")) as Color
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


static func apron_material(theme: Dictionary) -> Material:
	return flat_material(theme.get("ground_alt", Color("527788")) as Color)


static func dirt_material(theme: Dictionary) -> Material:
	return flat_material(theme.get("paint_alt", Color("8a5a32")) as Color)


static func skid_material(theme: Dictionary) -> Material:
	return flat_material(theme.get("ground_alt", Color("cee5f0")) as Color)


static func flat_material(colour: Color, unshaded: bool = true) -> StandardMaterial3D:
	var key: String = "%s/%s" % [colour.to_html(), str(unshaded)]
	if _paint_cache.has(key):
		return _paint_cache[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_paint_cache[key] = mat
	return mat


static func present_meshes(_theme: Dictionary) -> Array[Mesh]:
	var meshes: Array[Mesh] = []
	var info: Dictionary = model_info(CRATE_MODEL)
	if not bool(info.get("ok", false)):
		return meshes
	for part: Dictionary in info.get("parts", []) as Array:
		var mesh: Mesh = part.get("mesh") as Mesh
		if mesh != null:
			meshes.append(mesh)
	return meshes


static func present_material(_theme: Dictionary) -> Material:
	return flat_material(Color.WHITE)


static func accent() -> Color:
	return Color(1.0, 0.82, 0.28)


static func pickup_colour(theme: Dictionary) -> Color:
	var base: Color = theme.get("present_accent", accent()) as Color
	return base.lightened(0.22)


static func carry_colour(theme: Dictionary) -> Color:
	return theme.get("present_accent", accent()) as Color


static func wind(theme: Dictionary) -> float:
	return clampf(float(theme.get("wind", WIND_DEFAULT)), 0.0, 4.0)


# --------------------------------------------------------------------------
# present art
# --------------------------------------------------------------------------


static func build_present(root: Node3D, theme: Dictionary, index: int) -> void:
	if root == null:
		return
	var crate: Node3D = place_model(root, CRATE_MODEL, Vector3.ZERO,
		float(index) * 0.7, Vector3.ONE * CRATE_SCALE, "Crate")
	if crate == null:
		return
	var accent_colour: Color = theme.get("present_accent", accent()) as Color
	var batch := PropBatch.new()
	var height: float = CRATE_SCALE * 0.715
	var span: float = CRATE_SCALE * 0.715 + 0.06
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.5, 0.0)),
		Vector3(0.17, height, span), accent_colour)
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, height * 0.5, 0.0)),
		Vector3(span, height, 0.17), accent_colour)
	batch.add_box(Transform3D(Basis(Vector3.UP, 0.0),
		Vector3(0.0, height + 0.05, 0.0)), Vector3(span * 0.9, 0.12, 0.14),
		accent_colour.darkened(0.12))
	for side: float in [-1.0, 1.0]:
		batch.add_box(Transform3D(Basis(Vector3.BACK, side * 0.42),
			Vector3(side * 0.18, height + 0.15, 0.0)),
			Vector3(0.34, 0.13, 0.20), accent_colour)
	var ribbon := MeshInstance3D.new()
	ribbon.name = "Ribbon"
	ribbon.mesh = batch.build()
	ribbon.material_override = SceneryKit.vertex_material()
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ribbon)


# --------------------------------------------------------------------------
# standalone arena builder (used by preview_render.gd for map screenshots)
# --------------------------------------------------------------------------


## Builds a complete standalone 3D Deliver map (`harbour`, `farmyard`, or
## `snowfield`) under `stage` and returns `{spawns, theme}` so preview tools can
## stage karts and frame the exact 3D arena without running gameplay scripts.
static func build_arena(stage: Node3D, id: String) -> Dictionary:
	var theme: Dictionary = get_theme(id)
	var canonical: String = str(theme.get("id", DEFAULT_ID))
	var stats: Dictionary = {"objects": 0, "draw_calls": 0, "solid_bodies": 0}
	if stage == null:
		return {"theme": theme, "spawns": []}

	# Floor + 7x7 checkerboard
	var floor_inst := MeshInstance3D.new()
	floor_inst.name = "ArenaFloor"
	var floor_plane := PlaneMesh.new()
	floor_plane.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	floor_inst.mesh = floor_plane
	floor_inst.material_override = floor_material(theme)
	stage.add_child(floor_inst)

	var tile := PlaneMesh.new()
	tile.size = Vector2(TILE_SIZE, TILE_SIZE)
	var checker_xforms: Array = []
	var checker_cols: Array = []
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			checker_xforms.append(Transform3D(Basis.IDENTITY,
				Vector3(float(ix) * TILE_SIZE, 0.014, float(iz) * TILE_SIZE)))
			var even: bool = (ix + iz) % 2 == 0
			checker_cols.append(theme.get("ground" if even else "ground_alt",
				Color("476878")) as Color)
	var checker: MultiMeshInstance3D = SceneryKit.multimesh(tile,
		SceneryKit.instance_material(1.0), checker_xforms, "ArenaChecker",
		false, checker_cols)
	stage.add_child(checker)

	# Perimeter barrier ring
	var b_size: Vector3 = scaled_size("barrierWall", Vector3.ONE * TILE_SIZE)
	var b_depth: float = maxf(b_size.z, 0.1)
	var b_xforms: Array = []
	for side: float in [-1.0, 1.0]:
		for i in 7:
			var along: float = -ARENA_HALF + TILE_SIZE * (float(i) + 0.5)
			b_xforms.append(fit_transform("barrierWall",
				Vector3(along, 0.0, side * (ARENA_HALF + b_depth * 0.5)),
				0.0, Vector3.ONE * TILE_SIZE))
			b_xforms.append(fit_transform("barrierWall",
				Vector3(side * (ARENA_HALF + b_depth * 0.5), 0.0, along),
				PI * 0.5, Vector3.ONE * TILE_SIZE))
	batch_model(stage, "barrierWall", b_xforms, "BarrierRing", true)

	# Boundary stripes
	var paint_batch := PropBatch.new()
	var paint_col: Color = theme.get("paint", Color("f5ecd7")) as Color
	for side: float in [-1.0, 1.0]:
		paint_batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, 0.022, side * (ARENA_HALF - 2.0))),
			Vector3(ARENA_HALF * 2.0 - 4.0, 0.04, 0.7), paint_col)
		paint_batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(side * (ARENA_HALF - 2.0), 0.022, 0.0)),
			Vector3(0.7, 0.04, ARENA_HALF * 2.0 - 4.0), paint_col)
	var paint_inst := MeshInstance3D.new()
	paint_inst.name = "FloorPaint"
	paint_inst.mesh = paint_batch.build()
	paint_inst.material_override = SceneryKit.vertex_material()
	paint_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(paint_inst)

	# Grandstands, floodlights & banners
	for sx: float in [-1.0, 1.0]:
		place_model(stage, "grandStand", Vector3(sx * 64.0, 0.0, 0.0),
			sx * PI * 0.5, Vector3.ONE * (TILE_SIZE * 0.75),
			"Grandstand_%d" % (0 if sx < 0.0 else 1))
		for sz: float in [-1.0, 1.0]:
			place_model(stage, "lightPostLarge",
				Vector3(sx * 64.0, 0.0, sz * 64.0), 0.0,
				Vector3.ONE * TILE_SIZE,
				"Floodlight_%d_%d" % [int(sx), int(sz)])
	place_model(stage, "bannerTowerGreen", Vector3(0.0, 0.0, 64.0), 0.0,
		Vector3.ONE * TILE_SIZE, "Banner_0")
	place_model(stage, "bannerTowerRed", Vector3(0.0, 0.0, -64.0), PI,
		Vector3.ONE * TILE_SIZE, "Banner_1")

	# Team delivery pads, flags & beacons
	var team_cols: Array[Color] = [Color("2d8cf0"), Color("e8453c")]
	var pads: Array[Vector3] = []
	for team in 2:
		var centre := Vector3(0.0, 0.0, BASE_Z[team])
		pads.append(centre)
		var pad_batch := PropBatch.new()
		pad_batch.add_box(Transform3D(Basis.IDENTITY, centre + Vector3.UP * 0.03),
			Vector3(PAD_HALF.x * 2.0 + 0.8, 0.05, PAD_HALF.y * 2.0 + 0.8),
			Color("f8f3e6"))
		pad_batch.add_box(Transform3D(Basis.IDENTITY, centre + Vector3.UP * 0.06),
			Vector3(PAD_HALF.x * 2.0, 0.06, PAD_HALF.y * 2.0),
			team_cols[team].darkened(0.08))
		var outward: float = signf(BASE_Z[team])
		var pillar_pos := centre + Vector3(0.0, 0.0, outward * (PAD_HALF.y + 1.6))
		pad_batch.add_box(Transform3D(Basis.IDENTITY, pillar_pos + Vector3.UP * 2.5),
			Vector3(1.2, 4.8, 1.2), team_cols[team].darkened(0.12))
		var pad_mesh := MeshInstance3D.new()
		pad_mesh.name = "TeamBase_%d" % team
		pad_mesh.mesh = pad_batch.build()
		pad_mesh.material_override = SceneryKit.vertex_material()
		stage.add_child(pad_mesh)
		var flag_model: String = "flagGreen" if team == 0 else "flagRed"
		for side: float in [-1.0, 1.0]:
			place_model(stage, flag_model,
				Vector3(side * 16.0, 0.0, centre.z),
				-PI * 0.5 * outward, Vector3.ONE * 8.0,
				"BaseFlag_%d_%d" % [team, int(side)])

	# Unique 3D map geometry & hazards
	var theme_root := Node3D.new()
	theme_root.name = "ThemeRoot"
	stage.add_child(theme_root)
	build_scenery(theme_root, theme, {"half": ARENA_HALF, "base_pads": pads}, stats)
	# The cargo arenas sit on a 170 m floor; keep the ambient ring between the
	# 56 m barrier and the floor edge so nothing hangs off the world.
	preload("res://scripts/minigames/scenery/ambient_world.gd").build_arena(
		theme_root, canonical, ARENA_HALF,
		{"radius_in": 62.0, "radius_out": 80.0, "floor_y": -0.05})

	# Visible crates on the map's elevated & lane spawn spots
	var spots: Array[Vector3] = present_spots(theme)
	var ring_tint: Color = pickup_colour(theme)
	for idx in mini(spots.size(), 7):
		var spot: Vector3 = spots[idx]
		var holder := Node3D.new()
		holder.name = "PreviewPresent_%d" % idx
		holder.position = spot + Vector3.UP * 0.78
		stage.add_child(holder)
		build_present(holder, theme, idx)
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.12
		torus.outer_radius = 1.48
		ring.mesh = torus
		ring.scale = Vector3(1.0, 0.05, 1.0)
		ring.position = Vector3(0.0, -0.68, 0.0)
		ring.material_override = flat_material(ring_tint)
		holder.add_child(ring)

	var spawns: Array[Transform3D] = _preview_spawns_for(canonical)
	return {"theme": theme, "spawns": spawns}


static func _preview_spawns_for(canonical: String) -> Array[Transform3D]:
	match canonical:
		"farmyard":
			return [
				Transform3D(Basis(Vector3.UP, 0.0), Vector3(0.0, 2.02, 4.2)),
				Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-28.0, 0.50, -13.0)),
				Transform3D(Basis(Vector3.UP, -0.35), Vector3(16.0, 0.02, -22.0)),
				Transform3D(Basis(Vector3.UP, PI + 0.30), Vector3(-16.0, 0.02, 22.0)),
			]
		"snowfield":
			return [
				Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(-12.0, 0.05, -10.0)),
				Transform3D(Basis(Vector3.UP, -PI * 0.75), Vector3(31.5, 0.95, 31.5)),
				Transform3D(Basis(Vector3.UP, 0.20), Vector3(14.0, 0.05, -24.0)),
				Transform3D(Basis(Vector3.UP, PI - 0.25), Vector3(-15.0, 0.05, 24.0)),
			]
		_:
			return [
				Transform3D(Basis(Vector3.UP, 0.0), Vector3(-2.0, 2.22, 2.5)),
				Transform3D(Basis(Vector3.UP, PI), Vector3(2.2, 1.15, -18.5)),
				Transform3D(Basis(Vector3.UP, -0.25), Vector3(15.0, 0.02, -22.0)),
				Transform3D(Basis(Vector3.UP, PI + 0.25), Vector3(-15.0, 0.02, 20.0)),
			]


# --------------------------------------------------------------------------
# 3D map scenery & surface hazard zones
# --------------------------------------------------------------------------


## Builds the full 3D arena terrain, ramps, obstacles and outer ring under `root`
## and returns the surface hazard zones:
##   [{centre: Vector3, radius?: float, half_extents?: Vector2, max_y?: float,
##     grip: float, spin: float, drag?: float}].
static func build_scenery(root: Node3D, theme: Dictionary, arena: Dictionary,
		stats: Dictionary) -> Array[Dictionary]:
	var hazards: Array[Dictionary] = []
	if root == null:
		return hazards
	var half: float = float(arena.get("half", ARENA_HALF))
	_scatter_nature(root, theme, half, stats)
	var canonical: String = resolve(str(theme.get("id", DEFAULT_ID)))
	match canonical:
		"farmyard":
			hazards = _build_farmyard_hills(root, theme, half, stats)
		"snowfield":
			hazards = _build_glacier_bowl(root, theme, half, stats)
		_:
			hazards = _build_harbour_overpass(root, theme, half, stats)
	return hazards


# --------------------------------------------------------------------------
# Map 1: HARBOUR OVERPASS (`harbour`)
# --------------------------------------------------------------------------


static func _build_harbour_overpass(root: Node3D, theme: Dictionary,
		half: float, stats: Dictionary) -> Array[Dictionary]:
	var hazards: Array[Dictionary] = []
	var batch := PropBatch.new()
	var ramp_verts := PackedVector3Array()
	var ramp_normals := PackedVector3Array()
	var ramp_colors := PackedColorArray()
	var body: StaticBody3D = solid_root(root, "HarbourOverpassCollision")

	var deck_steel := Color("4f5d6b")
	var deck_road := Color("3b4652")
	var girder_yellow := Color("f0b832")
	var girder_dark := Color("2e3742")
	var kerb_cream := Color("f6efe0")
	var seawall_col := Color("6c7a86")

	# 1. Central +2.20 m Elevated Steel Overpass Bridge (N-S: z = -13.5 .. +13.5)
	var deck_y: float = 2.20
	var deck_thick: float = 0.44
	var deck_w: float = 11.6
	var deck_len: float = 27.0
	batch.add_box(Transform3D(Basis.IDENTITY,
		Vector3(0.0, deck_y - deck_thick * 0.5, 0.0)),
		Vector3(deck_w, deck_thick, deck_len), deck_steel)
	batch.add_box(Transform3D(Basis.IDENTITY,
		Vector3(0.0, deck_y + 0.012, 0.0)),
		Vector3(deck_w - 1.2, 0.025, deck_len - 0.2), deck_road)
	add_box_collider(body, Transform3D(Basis.IDENTITY,
		Vector3(0.0, deck_y - deck_thick * 0.5, 0.0)),
		Vector3(deck_w, deck_thick, deck_len))

	# Centre dashed stripe & edge yellow safety girders along the bridge deck
	for seg in 5:
		var z_dash: float = -10.0 + float(seg) * 5.0
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, deck_y + 0.03, z_dash)),
			Vector3(0.38, 0.02, 2.6), girder_yellow)
	for sx: float in [-1.0, 1.0]:
		var rail_x: float = sx * (deck_w * 0.5 - 0.28)
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(rail_x, deck_y + 0.28, 0.0)),
			Vector3(0.56, 0.56, deck_len), girder_yellow)
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(rail_x, deck_y + 0.58, 0.0)),
			Vector3(0.62, 0.10, deck_len), kerb_cream)
		add_box_collider(body, Transform3D(Basis.IDENTITY,
			Vector3(rail_x, deck_y + 0.28, 0.0)),
			Vector3(0.56, 0.56, deck_len))
		# Steel H-columns supporting the bridge deck
		for z_col: float in [-11.5, 0.0, 11.5]:
			var col_pos := Vector3(sx * 4.8, 0.0, z_col)
			batch.add_box(Transform3D(Basis.IDENTITY,
				col_pos + Vector3.UP * ((deck_y - deck_thick) * 0.5)),
				Vector3(0.95, deck_y - deck_thick, 0.95), girder_dark)
			add_box_collider(body, Transform3D(Basis.IDENTITY,
				col_pos + Vector3.UP * ((deck_y - deck_thick) * 0.5)),
				Vector3(0.95, deck_y - deck_thick, 0.95))

	# Overhead steel bridge portal frames (lowest_y = 5.50 m, purely overhead)
	for z_arch: float in [-9.0, 9.0]:
		for sx: float in [-1.0, 1.0]:
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(sx * (deck_w * 0.5 - 0.28), deck_y + 1.95, z_arch)),
				Vector3(0.42, 3.30, 0.42), girder_dark)
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, deck_y + 3.65, z_arch)),
			Vector3(deck_w + 0.2, 0.48, 0.52), girder_yellow)

	# 2. Broad South & North Approach Ramps (run = 10.5 m, rise = 2.20 m -> 11.8 deg!)
	_add_wedge_ramp(ramp_verts, ramp_normals, ramp_colors, body,
		Vector3(0.0, 0.0, -24.0), Vector3(0.0, 0.0, -13.5),
		11.2, deck_y, deck_road, deck_steel, girder_yellow)
	_add_wedge_ramp(ramp_verts, ramp_normals, ramp_colors, body,
		Vector3(0.0, 0.0, 24.0), Vector3(0.0, 0.0, 13.5),
		11.2, deck_y, deck_road, deck_steel, girder_yellow)

	# 3. Twin Side Water-Channel Hazards (x = +-21.0, z = [-20.5, +20.5])
	var water_root := Node3D.new()
	water_root.name = "WaterChannels"
	root.add_child(water_root)
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.10, 0.55, 0.74, 0.80)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.roughness = 0.14
	water_mat.emission_enabled = true
	water_mat.emission = Color(0.06, 0.34, 0.48)
	water_mat.emission_energy_multiplier = 0.28

	for sx: float in [-1.0, 1.0]:
		var wx: float = sx * 21.0
		var half_ext := Vector2(4.8, 20.0)
		# Low bevelled coaming sills along outer E/W edges (0.08 m visual trim)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(wx, 0.018, 0.0)),
			Vector3(half_ext.x * 2.0 + 0.9, 0.036, half_ext.y * 2.0 + 0.9),
			seawall_col)
		var sheet := MeshInstance3D.new()
		sheet.name = "WaterChannel_%s" % ("W" if sx < 0.0 else "E")
		var wplane := BoxMesh.new()
		wplane.size = Vector3(half_ext.x * 2.0, 0.04, half_ext.y * 2.0)
		sheet.mesh = wplane
		sheet.position = Vector3(wx, 0.045, 0.0)
		sheet.material_override = water_mat
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		water_root.add_child(sheet)
		# Bright cartoon foam stripes on the water surface
		for f_idx in 4:
			var fz: float = -13.5 + float(f_idx) * 9.0
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(wx, 0.068, fz)),
				Vector3(half_ext.x * 1.45, 0.015, 0.65),
				Color("a6eefc"))
		hazards.append({
			"centre": Vector3(wx, 0.0, 0.0),
			"half_extents": half_ext,
			"max_y": 0.75,
			"grip": WATER_CHANNEL_GRIP,
			"drag": WATER_CHANNEL_DRAG,
			"spin": 0.20,
		})

	# 4. Shipping Container Chicanes & Corner Stacks (clear of all crate spots!)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var chicane := Vector3(sx * 36.5, 0.0, sz * 18.5)
			var c_yaw: float = sx * sz * 0.28
			_add_container_pocket(batch, body, chicane, c_yaw, sx * sz > 0.0)
			var corner := Vector3(sx * minf(half - 8.5, 47.5), 0.0,
				sz * minf(half - 9.5, 46.5))
			_add_container_pocket(batch, body, corner, atan2(-sx, -sz),
				sx > 0.0)
		_add_bollard_plinth(batch, body,
			Vector3(sx * minf(half - 7.5, 48.5), 0.0, 0.0),
			-sx * PI * 0.5, girder_yellow)

	_emit_batches(root, batch, ramp_verts, ramp_normals, ramp_colors,
		"HarbourProps", "HarbourRamps")
	SceneryKit.bump(stats, "objects", 28)
	SceneryKit.bump(stats, "draw_calls", 3)
	SceneryKit.bump(stats, "solid_bodies")
	return hazards


# --------------------------------------------------------------------------
# Map 2: WINDMILL HILLS (`farmyard`)
# --------------------------------------------------------------------------


static func _build_farmyard_hills(root: Node3D, theme: Dictionary,
		half: float, stats: Dictionary) -> Array[Dictionary]:
	var hazards: Array[Dictionary] = []
	var batch := PropBatch.new()
	var ramp_verts := PackedVector3Array()
	var ramp_normals := PackedVector3Array()
	var ramp_colors := PackedColorArray()
	var body: StaticBody3D = solid_root(root, "WindmillHillsCollision")

	var hill_top := Color("7ab54e")
	var hill_earth := Color("94663b")
	var dirt_ramp := Color("b88450")
	var timber_light := Color("c98d4c")
	var timber_dark := Color("7d4f28")
	var barn_red := Color("c93b2b")
	var cream := Color("f7f0de")
	var mud_col := Color("593f24")
	var mud_sheen := Color("735231")

	# 1. Central +2.00 m Raised Earthen Barn Plateau (22 x 22 m top: [-11..11])
	var plat_y: float = 2.00
	var plat_w: float = 22.0
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, plat_y * 0.5, 0.0)),
		Vector3(plat_w, plat_y, plat_w), hill_earth)
	batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, plat_y + 0.012, 0.0)),
		Vector3(plat_w - 0.5, 0.025, plat_w - 0.5), hill_top)
	add_box_collider(body, Transform3D(Basis.IDENTITY,
		Vector3(0.0, plat_y * 0.5, 0.0)),
		Vector3(plat_w, plat_y, plat_w))

	# Corner timber post-and-rail fences on the 4 corners of the plateau
	# (leaving the 10.4 m N/S/E/W ramp mouths wide open!)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(sx * 8.2, plat_y + 0.34, sz * 10.75)),
				Vector3(5.2, 0.16, 0.24), timber_dark)
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(sx * 10.75, plat_y + 0.34, sz * 8.2)),
				Vector3(0.24, 0.16, 5.2), timber_dark)
			for post_off: float in [5.8, 10.7]:
				batch.add_box(Transform3D(Basis.IDENTITY,
					Vector3(sx * post_off, plat_y + 0.32, sz * 10.75)),
					Vector3(0.28, 0.64, 0.28), timber_dark)
				batch.add_box(Transform3D(Basis.IDENTITY,
					Vector3(sx * 10.75, plat_y + 0.32, sz * post_off)),
					Vector3(0.28, 0.64, 0.28), timber_dark)

	# Iconic Cartoon Windmill & Silo Landmark on the NE hilltop corner (7.6, 2.0, 7.6)
	var mill_pos := Vector3(7.6, plat_y, 7.6)
	batch.add_cylinder(Transform3D(Basis.IDENTITY, mill_pos + Vector3.UP * 2.4),
		1.85, 4.8, 12, barn_red)
	batch.add_cone(Transform3D(Basis.IDENTITY, mill_pos + Vector3.UP * 5.65),
		2.15, 1.8, 12, cream)
	var hub_pos := mill_pos + Vector3(-1.85, 4.35, 0.0)
	batch.add_cylinder(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), hub_pos),
		0.38, 0.55, 10, timber_dark)
	for blade in 4:
		var ang: float = PI * 0.25 + float(blade) * PI * 0.5
		var b_basis := Basis(Vector3.RIGHT, ang)
		var sail_off: Vector3 = b_basis * Vector3(0.0, 1.85, 0.0)
		batch.add_box(Transform3D(b_basis, hub_pos + Vector3(-0.22, 0.0, 0.0) + sail_off),
			Vector3(0.10, 3.2, 0.62), cream)
	add_cylinder_collider(body, mill_pos, 1.95, 6.2)

	# 2. Four Wide Dirt Approach Ramps from N, S, E, W (10.4 m wide, 10.0 m run -> 11.3 deg!)
	_add_wedge_ramp(ramp_verts, ramp_normals, ramp_colors, body,
		Vector3(0.0, 0.0, -21.0), Vector3(0.0, 0.0, -11.0),
		10.4, plat_y, dirt_ramp, hill_earth, timber_light)
	_add_wedge_ramp(ramp_verts, ramp_normals, ramp_colors, body,
		Vector3(0.0, 0.0, 21.0), Vector3(0.0, 0.0, 11.0),
		10.4, plat_y, dirt_ramp, hill_earth, timber_light)
	_add_wedge_ramp(ramp_verts, ramp_normals, ramp_colors, body,
		Vector3(21.0, 0.0, 0.0), Vector3(11.0, 0.0, 0.0),
		10.4, plat_y, dirt_ramp, hill_earth, timber_light)
	_add_wedge_ramp(ramp_verts, ramp_normals, ramp_colors, body,
		Vector3(-21.0, 0.0, 0.0), Vector3(-11.0, 0.0, 0.0),
		10.4, plat_y, dirt_ramp, hill_earth, timber_light)

	# 3. Flanking Mud Trenches (x = +-28.0, 0.70 grip) + Fast Timber Plank Bridges
	for sx: float in [-1.0, 1.0]:
		var mx: float = sx * 28.0
		var mud_half := Vector2(4.4, 25.0)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(mx, 0.022, 0.0)),
			Vector3(mud_half.x * 2.0, 0.03, mud_half.y * 2.0), mud_col)
		for p_idx in 5:
			var pz: float = -18.0 + float(p_idx) * 9.0
			batch.add_cylinder(Transform3D(Basis.IDENTITY,
				Vector3(mx + sx * (float(p_idx % 2) - 0.5) * 2.0, 0.04, pz)),
				2.6, 0.02, 14, mud_sheen)
		hazards.append({
			"centre": Vector3(mx, 0.0, 0.0),
			"half_extents": mud_half,
			"max_y": 0.34,
			"grip": MUD_TRENCH_GRIP,
			"drag": 1.18,
			"spin": 0.0,
		})
		# Two raised wooden plank shortcut bridges across each mud trench (z = -13, +13)
		for bz: float in [-13.0, 13.0]:
			var bridge_y: float = 0.48
			var span_x: float = 9.4
			var bridge_w: float = 6.2
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(mx, bridge_y * 0.5, bz)),
				Vector3(span_x, bridge_y, bridge_w), timber_dark)
			for plank in 7:
				var px: float = mx - 3.9 + float(plank) * 1.3
				batch.add_box(Transform3D(Basis.IDENTITY,
					Vector3(px, bridge_y + 0.015, bz)),
					Vector3(1.08, 0.03, bridge_w - 0.3), timber_light)
			add_box_collider(body, Transform3D(Basis.IDENTITY,
				Vector3(mx, bridge_y * 0.5, bz)),
				Vector3(span_x, bridge_y, bridge_w))
			_add_wedge_ramp(ramp_verts, ramp_normals, ramp_colors, body,
				Vector3(mx - span_x * 0.5 - 3.0, 0.0, bz),
				Vector3(mx - span_x * 0.5, 0.0, bz),
				bridge_w, bridge_y, timber_light, timber_dark, cream)
			_add_wedge_ramp(ramp_verts, ramp_normals, ramp_colors, body,
				Vector3(mx + span_x * 0.5 + 3.0, 0.0, bz),
				Vector3(mx + span_x * 0.5, 0.0, bz),
				bridge_w, bridge_y, timber_light, timber_dark, cream)

	# 4. L-Shaped Hay-Bale Chicane Walls in Outer Quadrants + Corner Farm Props
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_hay_l_wall(batch, body, Vector3(sx * 40.5, 0.0, sz * 25.0),
				sx, sz)
			var corner := Vector3(sx * minf(half - 8.5, 47.5), 0.0,
				sz * minf(half - 9.5, 46.5))
			_add_trough_prop(batch, body, corner, atan2(-sx, -sz))

	_emit_batches(root, batch, ramp_verts, ramp_normals, ramp_colors,
		"FarmyardProps", "FarmyardRamps")
	SceneryKit.bump(stats, "objects", 34)
	SceneryKit.bump(stats, "draw_calls", 2)
	SceneryKit.bump(stats, "solid_bodies")
	return hazards


static func _add_hay_l_wall(batch: PropBatch, body: StaticBody3D,
		corner: Vector3, sx: float, sz: float) -> void:
	var straw := Color("e8b948")
	var straw_top := Color("f2ca63")
	var twine := Color("8c5a2b")
	# Arm A (runs inward along X) + Arm B (runs inward along Z)
	var arm_a := corner + Vector3(-sx * 2.2, 0.85, 0.0)
	var arm_b := corner + Vector3(0.0, 0.85, -sz * 2.4)
	batch.add_box(Transform3D(Basis.IDENTITY, arm_a),
		Vector3(4.8, 1.7, 2.1), straw)
	batch.add_box(Transform3D(Basis.IDENTITY, arm_a + Vector3.UP * 0.88),
		Vector3(4.4, 0.12, 1.9), straw_top)
	batch.add_box(Transform3D(Basis.IDENTITY, arm_a),
		Vector3(0.24, 1.74, 2.16), twine)
	add_box_collider(body, Transform3D(Basis.IDENTITY, arm_a),
		Vector3(4.8, 1.7, 2.1))

	batch.add_box(Transform3D(Basis.IDENTITY, arm_b),
		Vector3(2.1, 1.7, 5.0), straw)
	batch.add_box(Transform3D(Basis.IDENTITY, arm_b + Vector3.UP * 0.88),
		Vector3(1.9, 0.12, 4.6), straw_top)
	batch.add_box(Transform3D(Basis.IDENTITY, arm_b),
		Vector3(2.16, 1.74, 0.24), twine)
	add_box_collider(body, Transform3D(Basis.IDENTITY, arm_b),
		Vector3(2.1, 1.7, 5.0))


# --------------------------------------------------------------------------
# Map 3: GLACIER BOWL (`snowfield`)
# --------------------------------------------------------------------------


static func _build_glacier_bowl(root: Node3D, theme: Dictionary,
		half: float, stats: Dictionary) -> Array[Dictionary]:
	var hazards: Array[Dictionary] = []
	var batch := PropBatch.new()
	var ramp_verts := PackedVector3Array()
	var ramp_normals := PackedVector3Array()
	var ramp_colors := PackedColorArray()
	var body: StaticBody3D = solid_root(root, "GlacierBowlCollision")

	var snow_pure := Color("f4f9fd")
	var snow_shade := Color("d6e6f2")
	var ice_outer := Color("7ad7ec")
	var ice_mid := Color("4bc2e0")
	var ice_core := Color("2ca6cc")
	var frost_white := Color("eefbff")
	var accent_blue := theme.get("paint_alt", Color("2e86ab")) as Color

	# 1. Central Frozen Ice Rink (radius = 28.0 m, 0.45 surface_grip!)
	var rink_r: float = 28.0
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.015, 0.0)),
		rink_r + 1.4, 0.025, 40, snow_pure)
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.024, 0.0)),
		rink_r, 0.025, 40, ice_outer)
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.032, 0.0)),
		rink_r * 0.74, 0.025, 36, ice_mid)
	batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.040, 0.0)),
		rink_r * 0.42, 0.025, 32, ice_core)
	# Crisp cartoon frost-crack lines radiating across the ice sheet
	for crack in 6:
		var c_ang: float = float(crack) * PI / 6.0 + 0.22
		batch.add_box(Transform3D(Basis(Vector3.UP, c_ang),
			Vector3(0.0, 0.054, 0.0)),
			Vector3(0.32, 0.01, rink_r * 1.68), frost_white)

	hazards.append({
		"centre": Vector3.ZERO,
		"radius": rink_r,
		"grip": ICE_BOWL_GRIP,
		"spin": ICE_BOWL_SPIN,
	})

	# 2. Four Inward Diagonal Snow-Berm Jump Ramps (NE, NW, SW, SE -> 10.3 deg!)
	# Each ramp rises from r = 36.8 m (y = 0) inward to r = 28.6 m (y = 1.48 m),
	# launching karts airborne over the berm straight into the slick ice bowl!
	var diag_angles: Array[float] = [
		PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75,
	]
	for ang: float in diag_angles:
		var radial := Vector3(cos(ang), 0.0, sin(ang))
		var toe: Vector3 = radial * 36.8
		var crest: Vector3 = radial * 28.6
		_add_wedge_ramp(ramp_verts, ramp_normals, ramp_colors, body,
			toe, crest, 8.6, 1.48, snow_pure, snow_shade, ice_outer)

	# 3. Sculpted Snow-Berm Ring Segments framing the Ice Bowl (leaving N/S/E/W
	#    entry gates AND the 4 diagonal jump ramps wide open!)
	var berm_angles_deg: Array[float] = [
		23.0, 67.0, 113.0, 157.0, 203.0, 247.0, 293.0, 337.0,
	]
	for deg: float in berm_angles_deg:
		var rad: float = deg_to_rad(deg)
		var b_pos := Vector3(cos(rad) * 30.8, 0.0, sin(rad) * 30.8)
		var b_yaw: float = -rad
		var b_basis := Basis(Vector3.UP, b_yaw)
		batch.add_box(Transform3D(b_basis, b_pos + Vector3.UP * 0.62),
			Vector3(3.4, 1.24, 7.6), snow_shade)
		batch.add_box(Transform3D(b_basis, b_pos + Vector3.UP * 1.28),
			Vector3(2.6, 0.22, 7.0), snow_pure)
		add_box_collider(body, Transform3D(b_basis, b_pos + Vector3.UP * 0.68),
			Vector3(3.4, 1.36, 7.6))

	# 4. Crystalline Ice-Pillar Slalom Spires inside the Bowl + Outer Cairns
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var spire := Vector3(sx * 14.5, 0.0, sz * 13.5)
			batch.add_cylinder(Transform3D(Basis.IDENTITY,
				spire + Vector3.UP * 0.28), 1.95, 0.56, 10, snow_pure)
			batch.add_cone(Transform3D(Basis(Vector3.UP, sx * 0.4),
				spire + Vector3.UP * 2.15), 1.35, 3.7, 7, ice_outer)
			batch.add_cone(Transform3D(Basis(Vector3.FORWARD, -sx * 0.14),
				spire + Vector3(sx * 0.85, 1.35, 0.0)), 0.85, 2.3, 6, frost_white)
			add_cylinder_collider(body, spire, 1.75, 3.8)

			var corner := Vector3(sx * minf(half - 8.5, 47.5), 0.0,
				sz * minf(half - 9.5, 46.5))
			_add_ice_outcrop(batch, body, corner, atan2(-sx, -sz))
		_add_snow_cairn(batch, body,
			Vector3(sx * minf(half - 7.5, 48.5), 0.0, 0.0),
			0.0, accent_blue)

	_emit_batches(root, batch, ramp_verts, ramp_normals, ramp_colors,
		"GlacierBowlProps", "GlacierBowlRamps")
	SceneryKit.bump(stats, "objects", 30)
	SceneryKit.bump(stats, "draw_calls", 2)
	SceneryKit.bump(stats, "solid_bodies")
	return hazards


# --------------------------------------------------------------------------
# shared 3D wedge ramp + prop builders
# --------------------------------------------------------------------------


## Appends a flush 6-vertex solid ramp rising from `toe_pos` (at `toe_pos.y`)
## to `crest_pos` (at `toe_pos.y + rise`) with painted directional chevrons and
## registers an exact ConvexPolygonShape3D collider on `body`.
static func _add_wedge_ramp(verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray,
		body: StaticBody3D, toe_pos: Vector3, crest_pos: Vector3,
		width: float, rise: float, top_col: Color, side_col: Color,
		stripe_col: Color) -> void:
	var planar := Vector3(crest_pos.x - toe_pos.x, 0.0, crest_pos.z - toe_pos.z)
	var run: float = planar.length()
	if run < 0.05 or width < 0.05 or rise < 0.02:
		return
	var fwd: Vector3 = planar / run
	var right: Vector3 = fwd.cross(Vector3.UP).normalized()
	var hw: float = width * 0.5
	var y0: float = toe_pos.y
	var y1: float = toe_pos.y + rise

	var tl := Vector3(toe_pos.x, y0, toe_pos.z) - right * hw
	var tr := Vector3(toe_pos.x, y0, toe_pos.z) + right * hw
	var bl := Vector3(crest_pos.x, y0, crest_pos.z) - right * hw
	var br := Vector3(crest_pos.x, y0, crest_pos.z) + right * hw
	var cl := Vector3(crest_pos.x, y1, crest_pos.z) - right * hw
	var cr := Vector3(crest_pos.x, y1, crest_pos.z) + right * hw

	# Sloped driving surface
	_push_quad(verts, normals, colors, tl, tr, cr, cl, top_col)
	# Back vertical face at crest
	_push_quad(verts, normals, colors, br, bl, cl, cr, side_col)
	# Left & right triangular side walls
	_push_tri(verts, normals, colors, tl, cl, bl, side_col)
	_push_tri(verts, normals, colors, tr, br, cr, side_col)

	# 2 painted chevron boost/climb stripes flush on top of the slope
	var slope_up: Vector3 = (cr - tr).cross(tl - tr).normalized()
	if slope_up.y < 0.0:
		slope_up = -slope_up
	var lift: Vector3 = slope_up * 0.018
	for idx in 2:
		var t0: float = 0.24 + float(idx) * 0.36
		var t1: float = t0 + 0.11
		var c0: Vector3 = tl.lerp(cl, t0).lerp(tr.lerp(cr, t0), 0.5)
		var c1: Vector3 = tl.lerp(cl, t1 + 0.06).lerp(tr.lerp(cr, t1 + 0.06), 0.5)
		var sl0: Vector3 = tl.lerp(cl, t0) + right * (width * 0.16) + lift
		var sr0: Vector3 = tr.lerp(cr, t0) - right * (width * 0.16) + lift
		var sl1: Vector3 = tl.lerp(cl, t1) + right * (width * 0.16) + lift
		var sr1: Vector3 = tr.lerp(cr, t1) - right * (width * 0.16) + lift
		_push_quad(verts, normals, colors, sl0, c0 + lift, c1 + lift, sl1, stripe_col)
		_push_quad(verts, normals, colors, c0 + lift, sr0, sr1, c1 + lift, stripe_col)

	if body != null:
		var hull := ConvexPolygonShape3D.new()
		hull.points = PackedVector3Array([tl, tr, bl, br, cl, cr])
		var shape_node := CollisionShape3D.new()
		shape_node.shape = hull
		body.add_child(shape_node)


static func _push_quad(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, col: Color) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	n = n.normalized() if n.length_squared() > 0.000001 else Vector3.UP
	for pt: Vector3 in [a, b, c, a, c, d]:
		verts.append(pt)
		normals.append(n)
		colors.append(col)


static func _push_tri(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		col: Color) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	n = n.normalized() if n.length_squared() > 0.000001 else Vector3.UP
	for pt: Vector3 in [a, b, c]:
		verts.append(pt)
		normals.append(n)
		colors.append(col)


static func _emit_batches(root: Node3D, batch: PropBatch,
		ramp_verts: PackedVector3Array, ramp_normals: PackedVector3Array,
		ramp_colors: PackedColorArray, prop_name: String,
		ramp_name: String) -> void:
	var prop_mesh: ArrayMesh = batch.build()
	if prop_mesh != null and prop_mesh.get_surface_count() > 0:
		var prop_inst := MeshInstance3D.new()
		prop_inst.name = prop_name
		prop_inst.mesh = prop_mesh
		prop_inst.material_override = SceneryKit.vertex_material()
		root.add_child(prop_inst)
	if not ramp_verts.is_empty():
		var r_mesh := ArrayMesh.new()
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = ramp_verts
		arrays[Mesh.ARRAY_NORMAL] = ramp_normals
		arrays[Mesh.ARRAY_COLOR] = ramp_colors
		r_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat: StandardMaterial3D = SceneryKit.vertex_material().duplicate() \
			as StandardMaterial3D
		if mat != null:
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var ramp_inst := MeshInstance3D.new()
		ramp_inst.name = ramp_name
		ramp_inst.mesh = r_mesh
		ramp_inst.material_override = mat if mat != null \
			else SceneryKit.vertex_material()
		root.add_child(ramp_inst)


static func _add_container_pocket(batch: PropBatch, body: StaticBody3D,
		at: Vector3, yaw: float, warm: bool) -> void:
	var primary: Color = Color("d95d39") if warm else Color("2c6e91")
	var secondary: Color = Color("f0b429") if warm else Color("4ea8de")
	var basis := Basis(Vector3.UP, yaw)
	var lower := Transform3D(basis, at + Vector3.UP * 1.35)
	batch.add_box(lower, Vector3(5.6, 2.7, 2.5), primary)
	batch.add_box(Transform3D(basis, at + Vector3.UP * 2.74),
		Vector3(5.72, 0.12, 2.62), primary.lightened(0.18))
	var upper_offset: Vector3 = basis * Vector3(0.35, 3.85, -0.15)
	var upper := Transform3D(basis * Basis(Vector3.UP, 0.08), at + upper_offset)
	batch.add_box(upper, Vector3(4.6, 2.2, 2.3), secondary)
	add_box_collider(body, Transform3D(basis, at + Vector3.UP * 2.45),
		Vector3(5.7, 4.9, 2.6))


static func _add_bollard_plinth(batch: PropBatch, body: StaticBody3D,
		at: Vector3, yaw: float, accent_col: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
	batch.add_box(Transform3D(basis, at + Vector3.UP * 0.20),
		Vector3(2.2, 0.40, 4.4), Color("7a858c"))
	for dz: float in [-1.25, 1.25]:
		var post: Vector3 = at + basis * Vector3(0.0, 0.0, dz)
		batch.add_cylinder(Transform3D(Basis.IDENTITY, post + Vector3.UP * 0.85),
			0.42, 0.95, 12, Color("2b303a"))
		batch.add_cylinder(Transform3D(Basis.IDENTITY, post + Vector3.UP * 1.36),
			0.52, 0.18, 12, accent_col)
	add_box_collider(body, Transform3D(basis, at + Vector3.UP * 0.75),
		Vector3(2.2, 1.5, 4.4))


static func _add_trough_prop(batch: PropBatch, body: StaticBody3D,
		at: Vector3, yaw: float) -> void:
	var wood := Color("8d5b34")
	var water := Color("56b4d3")
	var basis := Basis(Vector3.UP, yaw)
	batch.add_box(Transform3D(basis, at + Vector3.UP * 0.48),
		Vector3(1.9, 0.96, 4.2), wood)
	batch.add_box(Transform3D(basis, at + Vector3.UP * 0.98),
		Vector3(1.5, 0.08, 3.8), water)
	add_box_collider(body, Transform3D(basis, at + Vector3.UP * 0.50),
		Vector3(1.9, 1.0, 4.2))


static func _add_ice_outcrop(batch: PropBatch, body: StaticBody3D,
		at: Vector3, yaw: float) -> void:
	var ice_base := Color("89c9e8")
	var ice_bright := Color("c8ecfa")
	var snow := Color("f4f9fd")
	var basis := Basis(Vector3.UP, yaw)
	batch.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.35),
		2.8, 0.70, 10, snow)
	batch.add_cone(Transform3D(basis, at + Vector3.UP * 2.1),
		1.55, 3.6, 7, ice_base)
	var side_pos: Vector3 = at + basis * Vector3(1.35, 1.45, 0.45)
	batch.add_cone(Transform3D(basis * Basis(Vector3.FORWARD, -0.16), side_pos),
		1.15, 2.5, 6, ice_bright)
	add_cylinder_collider(body, at, 2.6, 3.8)


static func _add_snow_cairn(batch: PropBatch, body: StaticBody3D,
		at: Vector3, _yaw: float, accent_col: Color) -> void:
	batch.add_cylinder(Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.32),
		1.85, 0.64, 12, Color("eef6fb"))
	for tier in 3:
		var col: Color = accent_col if tier % 2 == 0 else Color("f7fbff")
		batch.add_cylinder(Transform3D(Basis.IDENTITY,
			at + Vector3.UP * (0.88 + float(tier) * 0.56)),
			0.55 - float(tier) * 0.07, 0.54, 10, col)
	add_cylinder_collider(body, at, 1.75, 2.3)


static func _scatter_nature(root: Node3D, theme: Dictionary, half: float,
		stats: Dictionary) -> void:
	var tree_model: String = str(theme.get("tree_model", "tree_default"))
	var tree_scale: float = float(theme.get("tree_scale", 1.0)) * TREE_SCALE
	var tree_transforms: Array = []
	for index in TREE_RING.size():
		var spot: Vector2 = TREE_RING[index]
		if absf(spot.x) < half + 4.0 and absf(spot.y) < half + 4.0:
			continue
		var scale: float = tree_scale * (0.86
			+ 0.28 * fposmod(float(index) * 0.61803398875, 1.0))
		tree_transforms.append(fit_transform(tree_model,
			Vector3(spot.x, 0.0, spot.y), float(index) * 1.7,
			Vector3.ONE * scale, true))
		var tree_size: Vector3 = scaled_size(tree_model, Vector3.ONE * scale,
			true)
		add_cylinder_collider(_nature_body(root), Vector3(spot.x, 0.0, spot.y),
			0.12 * scale, maxf(tree_size.y, 1.0))
	SceneryKit.bump(stats, "objects", tree_transforms.size())
	SceneryKit.bump(stats, "draw_calls")
	batch_model(root, tree_model, tree_transforms, "TreeRing", true, true)
	if not _model_exists(tree_model, true):
		push_warning("CargoTheme: missing tree model " + tree_model)

	var bush_transforms: Array = []
	for index in BUSH_SPOTS.size():
		var spot: Vector2 = BUSH_SPOTS[index]
		var scale: float = BUSH_SCALE * (0.9
			+ 0.2 * fposmod(float(index) * 0.41421356237, 1.0))
		bush_transforms.append(fit_transform("plant_bushLarge",
			Vector3(spot.x, 0.0, spot.y), float(index) * 2.3,
			Vector3.ONE * scale, true))
	SceneryKit.bump(stats, "objects", bush_transforms.size())
	SceneryKit.bump(stats, "draw_calls")
	batch_model(root, "plant_bushLarge", bush_transforms, "Bushes", true, true)

	var rock_transforms: Array = []
	for index in ROCK_SPOTS.size():
		var spot: Vector2 = ROCK_SPOTS[index]
		var scale: float = ROCK_SCALE * (0.9
			+ 0.2 * fposmod(float(index) * 0.73205080756, 1.0))
		rock_transforms.append(fit_transform("rock_largeA",
			Vector3(spot.x, 0.0, spot.y), float(index) * 1.1,
			Vector3.ONE * scale, true))
		var rock_size: Vector3 = scaled_size("rock_largeA",
			Vector3.ONE * scale, true)
		add_box_collider(_nature_body(root),
			Transform3D(Basis(Vector3.UP, float(index) * 1.1),
				Vector3(spot.x, 0.0, spot.y)
					+ Vector3.UP * (rock_size.y * 0.5)),
			Vector3(maxf(rock_size.x, 0.4), maxf(rock_size.y, 0.4),
				maxf(rock_size.z, 0.4)))
	SceneryKit.bump(stats, "objects", rock_transforms.size())
	SceneryKit.bump(stats, "draw_calls")
	batch_model(root, "rock_largeA", rock_transforms, "Rocks", true, true)
	SceneryKit.bump(stats, "solid_bodies")


static func _nature_body(root: Node3D) -> StaticBody3D:
	var existing: Node = root.get_node_or_null("NatureCollision")
	if existing is StaticBody3D:
		return existing as StaticBody3D
	return solid_root(root, "NatureCollision")


static func _model_exists(model: String, nature: bool = false) -> bool:
	return ResourceLoader.exists(_model_path(model, nature))


# --------------------------------------------------------------------------
# Kenney model plumbing
# --------------------------------------------------------------------------


static func model_info(model: String, nature: bool = false) -> Dictionary:
	var path: String = _model_path(model, nature)
	if _model_cache.has(path):
		return _model_cache[path] as Dictionary
	var info: Dictionary = {"ok": false, "path": path}
	if not ResourceLoader.exists(path):
		push_warning("CargoTheme: missing model " + path)
		_model_cache[path] = info
		return info
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_warning("CargoTheme: cannot load " + path)
		_model_cache[path] = info
		return info
	var root: Node = packed.instantiate()
	var aabb: AABB = _aabb(root, Transform3D.IDENTITY)
	var parts: Array = []
	_collect_parts(root, Transform3D.IDENTITY, parts)
	root.free()
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
	var center: Vector2 = info["center"]
	var aabb: AABB = info["aabb"]
	var yaw_basis := Basis(Vector3.UP, yaw)
	var basis: Basis = yaw_basis * Basis.IDENTITY.scaled(scale)
	var center_m := Vector3(center.x * scale.x, 0.0, center.y * scale.z)
	var lift: float = -aabb.position.y * scale.y
	return Transform3D(basis, at - yaw_basis * center_m + Vector3.UP * lift)


static func scaled_size(model: String, scale: Vector3,
		nature: bool = false) -> Vector3:
	var info: Dictionary = model_info(model, nature)
	if not bool(info.get("ok", false)):
		return Vector3(0.1, 0.1, 0.1)
	return (info["aabb"] as AABB).size * scale


static func place_model(parent: Node3D, model: String, at: Vector3, yaw: float,
		scale: Vector3, node_name: String, nature: bool = false) -> Node3D:
	if parent == null:
		return null
	var info: Dictionary = model_info(model, nature)
	if not bool(info.get("ok", false)):
		return null
	var packed: PackedScene = load(str(info["path"])) as PackedScene
	if packed == null:
		return null
	var node: Node3D = packed.instantiate() as Node3D
	if node == null:
		return null
	node.name = node_name
	node.transform = fit_transform(model, at, yaw, scale, nature)
	parent.add_child(node)
	return node


static func batch_model(parent: Node3D, model: String, transforms: Array,
		node_name: String, cast_shadow: bool = true,
		nature: bool = false) -> void:
	if parent == null or transforms.is_empty():
		return
	var info: Dictionary = model_info(model, nature)
	if not bool(info.get("ok", false)):
		return
	var parts: Array = info.get("parts", []) as Array
	for part_index in parts.size():
		var part: Dictionary = parts[part_index]
		var mesh: Mesh = part.get("mesh") as Mesh
		var local: Transform3D = part.get("transform", Transform3D.IDENTITY) \
			as Transform3D
		if mesh == null:
			continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = transforms.size()
		for index in transforms.size():
			multi.set_instance_transform(index,
				(transforms[index] as Transform3D) * local)
		var instance := MultiMeshInstance3D.new()
		instance.name = node_name if parts.size() == 1 \
			else "%s_%d" % [node_name, part_index]
		instance.multimesh = multi
		instance.cast_shadow = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(instance)


# --------------------------------------------------------------------------
# colliders
# --------------------------------------------------------------------------


static func solid_root(parent: Node3D, node_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	parent.add_child(body)
	return body


static func add_box_collider(body: StaticBody3D, xform: Transform3D,
		size: Vector3) -> void:
	if body == null:
		return
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	body.add_child(collision)


static func add_cylinder_collider(body: StaticBody3D, point: Vector3,
		radius: float, height: float) -> void:
	if body == null:
		return
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, 0.05)
	shape.height = maxf(height, 0.1)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = point + Vector3.UP * (shape.height * 0.5)
	body.add_child(collision)


# --------------------------------------------------------------------------
# measurement
# --------------------------------------------------------------------------


static func _model_path(model: String, nature: bool = false) -> String:
	if nature:
		return NATURE_ROOT + model + ".glb"
	if model == CRATE_MODEL:
		return CAR_ROOT + model + ".glb"
	return RACING_ROOT + model + ".glb"


static func _aabb(node: Node, xform: Transform3D) -> AABB:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	var result := AABB()
	var found: bool = false
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh != null:
			result = local * instance.mesh.get_aabb()
			found = true
	for child: Node in node.get_children():
		var child_box: AABB = _aabb(child, local)
		if child_box.size.length_squared() > 0.000001:
			result = result.merge(child_box) if found else child_box
			found = true
	return result


static func _collect_parts(node: Node, xform: Transform3D, parts: Array) -> void:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh != null:
			parts.append({"mesh": instance.mesh, "transform": local})
	for child: Node in node.get_children():
		_collect_parts(child, local, parts)
