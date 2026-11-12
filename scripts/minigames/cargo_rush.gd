extends Node3D
## CARGO RUSH: a 90 second two-team arena scramble.
##
## Crates spawn in the middle of the yard. Every cart shoves and shepherds them
## into its own delivery pad; the team with the most deliveries wins. A tied
## clock goes to sudden-death overtime: the next delivery takes the match.
##
## Solo play is the local kart against the sandbox AI carts. Each rival reuses
## scripts/ai/sandbox_bot.gd as its driver: the bot is fed a cargo goal every
## tick (approach point behind a crate, then straight through it) and keeps the
## sandbox's obstacle rays, stuck recovery and personalities. The shove itself
## is the same mass-scaled impulse the sandbox uses for props.
##
## Online play is host-authoritative for crate state, exactly like the sandbox
## and the race: the host simulates the crates and streams snapshots at 10 Hz,
## peers freeze their copy and ask the host to apply pushes, and cart states
## stream peer-to-peer through the host relay. Scores, the clock and the
## overtime flag are host-owned and replicated as absolute values.
##
## Three arena themes (dockyard / farmyard / snowfield) live in
## cargo_rush_theme.gd and change the ground, the crate art and the grip rule.
## Every solid prop has a real collision shape on CollisionLayers.WORLD.

const CART_SCENE := preload("res://scenes/player/cart_player.tscn")
const SandboxBot := preload("res://scripts/ai/sandbox_bot.gd")
const CargoTheme := preload("res://scripts/minigames/cargo_rush_theme.gd")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const VisualGrade := preload("res://scripts/systems/visual_grade.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const SCENE_PATH: String = "res://scenes/minigames/cargo_rush.tscn"
const MAIN_MENU: String = "res://scenes/ui/main_menu.tscn"
const MINIGAMES_MENU: String = "res://scenes/ui/minigames_menu.tscn"
const UI_THEME: String = "res://assets/ui/theme.tres"
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const TITLE_FONT: String = "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"

const COUNTDOWN_BEEP: AudioStream = preload("res://assets/audio/sfx/race/countdown_beep.wav")
const COUNTDOWN_GO: AudioStream = preload("res://assets/audio/sfx/race/countdown_go.wav")
const DELIVERY_CHIME: AudioStream = preload("res://assets/audio/sfx/race/lap_chime.wav")
const FINISH_FANFARE: AudioStream = preload("res://assets/audio/sfx/race/finish_fanfare.wav")

const MATCH_SECONDS: float = 90.0
const OVERTIME_SECONDS: float = 30.0
const COUNTDOWN_SECONDS: float = 3.0
const ARENA_HALF: float = 44.0
const WALL_HEIGHT: float = 2.6
const WALL_THICKNESS: float = 1.2
const FLOOR_SIZE: float = 100.0
const PAD_HALF: Vector2 = Vector2(8.0, 5.0)
const PAD_DISTANCE: float = 30.0
const CRATE_COUNT: int = 6
const CRATE_RING: float = 3.8
const CRATE_RESPAWN_DELAY: float = 1.1
const CRATE_GROUP: String = "pushable"
const BOT_MIN: int = 2
const BOT_MAX: int = 5
const TEAM_COUNT: int = 2
const CART_SYNC_INTERVAL: float = 0.05
const PROP_SYNC_INTERVAL: float = 0.10
const STATE_SYNC_INTERVAL: float = 0.25
const CLIENT_SNAP_DISTANCE: float = 7.0
const SHOVE_RANGE: float = 3.1
const SHOVE_COOLDOWN_MS: int = 220
const CORNER_RADIUS: int = 16 ## One radius for every HUD tile, per the UI kit.
const TEAM_COLORS: Array[Color] = [UiPalette.BLUE, UiPalette.RED]

enum Phase { COUNTDOWN, RACING, FINISHED }

var _theme_id: String = CargoTheme.DEFAULT_ID
var _theme: Dictionary = {}
var _theme_root: Node3D
var _team_names: PackedStringArray = PackedStringArray()
var _hazards: Array[Dictionary] = []
var _pads: PackedVector3Array = PackedVector3Array()
var _pad_visuals: Array[MeshInstance3D] = []
var _pad_labels: Array[Label3D] = []
var _floor: MeshInstance3D
var _apron: MeshInstance3D

var _crates: Array[RigidBody3D] = []
var _crate_visuals: Array[MeshInstance3D] = []
var _crate_home: PackedVector3Array = PackedVector3Array()
var _crate_respawn: PackedFloat32Array = PackedFloat32Array()

var _cart: CartPlayer
var _bots: Array[Dictionary] = []
var _traffic: Array[CartPlayer] = []
var _bot_shove_count: int = 0
var _saved_vehicle: String = ""

var _score: PackedInt32Array = PackedInt32Array([0, 0])
var _local_team: int = 0
var _phase: Phase = Phase.COUNTDOWN
var _countdown: float = COUNTDOWN_SECONDS
var _last_count: int = 3
var _remaining: float = MATCH_SECONDS
var _overtime: bool = false
var _overtime_remaining: float = 0.0
var _match_length: float = MATCH_SECONDS
var _overtime_length: float = OVERTIME_SECONDS
var _time: float = 0.0
var _debug_timer: float = 0.0

var _multiplayer: bool = false
var _is_host: bool = true
var _remote_carts: Dictionary = {}
var _name_labels: Dictionary = {}
var _cart_relay_ms: Dictionary = {}
var _prop_targets: Dictionary = {}
var _prop_kick_until: Dictionary = {}
var _push_stamp: Dictionary = {}
var _prop_sync_timer: float = 0.0
var _state_sync_timer: float = 0.0
var _cart_sync_timer: float = 0.0
var _bot_sync_timer: float = 0.0
var _client_bots_wanted: int = 0

var _selftest: bool = false
var _debug: bool = false
var _selftest_elapsed: float = 0.0
var _selftest_done: bool = false
var _selftest_max_move: float = 0.0
var _selftest_start: PackedVector3Array = PackedVector3Array()
var _selftest_bot_start: PackedVector3Array = PackedVector3Array()
var _selftest_bot_move: float = 0.0
var _selftest_scores: PackedInt32Array = PackedInt32Array([0, 0])

var _canvas: CanvasLayer
var _hud_root: Control
var _timer_label: Label
var _overtime_label: Label
var _score_labels: Array[Label] = []
var _team_name_labels: Array[Label] = []
var _theme_name_label: Label
var _theme_detail_label: Label
var _countdown_label: Label
var _toast_label: Label
var _toast_timer: float = 0.0
var _hud_timer: float = 0.0
var _last_timer_text: String = ""
var _last_score_text: PackedStringArray = PackedStringArray()

var _result_root: Control
var _result_title: Label
var _result_subtitle: Label
var _result_score_labels: Array[Label] = []
var _result_team_labels: Array[Label] = []
var _result_note: Label
var _result_primary: Button


func _enter_tree() -> void:
	# CartPlayer reads GameSettings.selected_vehicle in its own _ready, which
	# runs before this script's _ready. Swap in the minigame kart and put the
	# sandbox choice back when the arena is left (memory only, never saved).
	_saved_vehicle = GameSettings.selected_vehicle
	GameSettings.selected_vehicle = GameSettings.minigame_vehicle


func _exit_tree() -> void:
	GameSettings.selected_vehicle = _saved_vehicle


func _ready() -> void:
	_selftest = OS.get_environment("CART_CARGO_SELFTEST") == "1"
	_debug = OS.get_environment("CART_CARGO_DEBUG") == "1"
	if OS.get_environment("CART_CARGO_LOCK_FPS") == "1":
		# Headless balancing runs are uncapped by default; the shove cooldown
		# uses wall-clock time, so cap the loop to real 60 FPS for those runs.
		Engine.max_fps = 60
	_multiplayer = Network.is_session_active()
	_is_host = Network.is_host if _multiplayer else true
	_local_team = _team_of_local_peer()
	_theme_id = CargoTheme.resolve(_requested_theme())
	_theme = CargoTheme.get_theme(_theme_id)
	_team_names = CargoTheme.team_names(_theme)
	_time = 0.0
	_apply_test_overrides()
	CursorController.set_menu_mode(false)
	_upgrade_graphics()

	_cart = get_tree().get_first_node_in_group("player") as CartPlayer
	_build_arena()
	_apply_theme()
	_build_crates()
	_place_local_cart()
	_build_bots()
	_build_hud()
	_build_result_card()
	_connect_local_cart()
	if _multiplayer:
		_setup_multiplayer()
	if _debug:
		_probe_structure()
	_begin_countdown()
	if _selftest:
		_run_self_test.call_deferred()


func _probe_structure() -> void:
	## Headless sanity check for the real collision tree: every static body in
	## the arena is WORLD with at least one shape, and every crate advertises
	## both pushable layers. Gated by CART_CARGO_DEBUG, so it costs nothing in
	## a normal match.
	var solids: int = 0
	var missing: int = 0
	var world_ok: bool = true
	for node in find_children("*", "StaticBody3D", true, false):
		var body: StaticBody3D = node as StaticBody3D
		solids += 1
		var shapes: int = 0
		for child in body.get_children():
			if child is CollisionShape3D:
				shapes += 1
		if shapes == 0:
			missing += 1
		if body.collision_layer != CollisionLayers.WORLD:
			world_ok = false
	var needed: int = CollisionLayers.PROP | CollisionLayers.SOLID_PROP
	var crate_shapes: int = 0
	var crate_layers: int = 0
	for crate: RigidBody3D in _crates:
		for child in crate.get_children():
			if child is CollisionShape3D:
				crate_shapes += 1
		if (crate.collision_layer & needed) == needed:
			crate_layers += 1
	print("CARGO_DEBUG structure solids=%d missing_shapes=%d world_layer_ok=%s "
		% [solids, missing, str(world_ok)]
		+ "crates=%d crate_shapes=%d crate_layers=%d hazards=%d"
		% [_crates.size(), crate_shapes, crate_layers, _hazards.size()])


# --------------------------------------------------------------------------
# setup


func _requested_theme() -> String:
	var forced: String = OS.get_environment("CART_CARGO_THEME").strip_edges()
	if forced != "":
		return forced
	var selected: String = GameSettings.selected_minigame
	if _multiplayer and Network.session_minigame != "":
		selected = Network.session_minigame
	return selected


func _apply_test_overrides() -> void:
	## Headless verification hooks, same idea as the race's CART_TEST_LAPS.
	var seconds: String = OS.get_environment("CART_CARGO_SECONDS").strip_edges()
	if seconds.is_valid_int():
		_match_length = clampf(float(seconds.to_int()), 3.0, 300.0)
	var overtime: String = OS.get_environment("CART_CARGO_OVERTIME").strip_edges()
	if overtime.is_valid_int():
		_overtime_length = clampf(float(overtime.to_int()), 2.0, 120.0)
	_remaining = _match_length


func _team_of_local_peer() -> int:
	if not _multiplayer:
		return 0
	var ids: Array[int] = Network.participants()
	var index: int = ids.find(multiplayer.get_unique_id())
	if index < 0:
		return 0
	return index % TEAM_COUNT


func _upgrade_graphics() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.msaa_3d = Viewport.MSAA_2X
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	VisualGrade.apply(get_node_or_null("WorldEnvironment") as WorldEnvironment, "race")
	VisualGrade.apply_sun(get_node_or_null("Sun") as DirectionalLight3D)


func _build_arena() -> void:
	_floor = MeshInstance3D.new()
	_floor.name = "ArenaFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	_floor.mesh = plane
	_floor.material_override = CargoTheme.floor_material(_theme)
	add_child(_floor)

	var ground := StaticBody3D.new()
	ground.name = "GroundCollision"
	ground.collision_layer = CollisionLayers.WORLD
	ground.collision_mask = 0
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(FLOOR_SIZE, 2.0, FLOOR_SIZE)
	var ground_collision := CollisionShape3D.new()
	ground_collision.shape = ground_shape
	ground_collision.position = Vector3(0.0, -1.0, 0.0)
	ground.add_child(ground_collision)
	add_child(ground)

	_build_walls()
	_build_pads()


func _build_walls() -> void:
	## One merged visual and one static body. The inner face is exactly at
	## ARENA_HALF, so the playable rectangle matches the visible wall.
	var body := StaticBody3D.new()
	body.name = "ArenaWalls"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	var batch := PropBatch.new()
	var span: float = ARENA_HALF * 2.0 + WALL_THICKNESS * 2.0
	var concrete := Color(0.56, 0.57, 0.58)
	var accent := Color(0.42, 0.44, 0.48)
	for side: float in [-1.0, 1.0]:
		var z_centre: float = side * (ARENA_HALF + WALL_THICKNESS * 0.5)
		var x_centre: float = side * (ARENA_HALF + WALL_THICKNESS * 0.5)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, WALL_HEIGHT * 0.5, z_centre)),
			Vector3(span, WALL_HEIGHT, WALL_THICKNESS), concrete)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, WALL_HEIGHT - 0.08, z_centre)),
			Vector3(span, 0.16, WALL_THICKNESS + 0.06), accent)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(x_centre, WALL_HEIGHT * 0.5, 0.0)),
			Vector3(WALL_THICKNESS, WALL_HEIGHT, span), concrete)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(x_centre, WALL_HEIGHT - 0.08, 0.0)),
			Vector3(WALL_THICKNESS + 0.06, 0.16, span), accent)
		_add_wall_shape(body, Vector3(0.0, WALL_HEIGHT * 0.5, z_centre),
			Vector3(span, WALL_HEIGHT, WALL_THICKNESS))
		_add_wall_shape(body, Vector3(x_centre, WALL_HEIGHT * 0.5, 0.0),
			Vector3(WALL_THICKNESS, WALL_HEIGHT, span))
	# Painted hazard band along the bottom of the harbour wall.
	for side: float in [-1.0, 1.0]:
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, 0.22, side * (ARENA_HALF - 0.03))),
			Vector3(span, 0.22, 0.06), UiPalette.YELLOW)
	var visual := MeshInstance3D.new()
	visual.name = "ArenaWallsVisual"
	visual.mesh = batch.build()
	visual.material_override = SceneryKit.vertex_material()
	add_child(visual)


func _add_wall_shape(body: StaticBody3D, position: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = position
	body.add_child(collision)


func _build_pads() -> void:
	for team in TEAM_COUNT:
		var side: float = 1.0 if team == 0 else -1.0
		var centre := Vector3(0.0, 0.0, side * PAD_DISTANCE)
		_pads.append(centre)
		var pad := MeshInstance3D.new()
		pad.name = "DeliveryPad_%d" % team
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(PAD_HALF.x * 2.0, PAD_HALF.y * 2.0)
		pad.mesh = mesh
		pad.position = centre + Vector3.UP * 0.022
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = TEAM_COLORS[team].darkened(0.06)
		pad.material_override = mat
		add_child(pad)
		_pad_visuals.append(pad)
		var border := MeshInstance3D.new()
		border.name = "DeliveryPadEdge_%d" % team
		var edge := PlaneMesh.new()
		edge.size = Vector2(PAD_HALF.x * 2.0 + 0.5, PAD_HALF.y * 2.0 + 0.5)
		border.mesh = edge
		border.position = centre + Vector3.UP * 0.015
		var edge_mat := StandardMaterial3D.new()
		edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		edge_mat.albedo_color = UiPalette.CREAM
		border.material_override = edge_mat
		add_child(border)
		var label := Label3D.new()
		label.name = "PadLabel_%d" % team
		label.text = _team_names[team]
		label.font = load(TITLE_FONT)
		label.font_size = 96
		label.pixel_size = 0.012
		label.outline_size = 14
		label.outline_modulate = UiPalette.OUTLINE
		label.modulate = TEAM_COLORS[team].lightened(0.35)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = centre + Vector3.UP * 3.1
		add_child(label)
		_pad_labels.append(label)
	# Spawn ring marking in the middle of the yard.
	var ring := MeshInstance3D.new()
	ring.name = "SpawnRing"
	var disc := CylinderMesh.new()
	disc.top_radius = 5.8
	disc.bottom_radius = 5.8
	disc.height = 0.02
	disc.radial_segments = 32
	disc.rings = 1
	ring.mesh = disc
	ring.position = Vector3(0.0, 0.012, 0.0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.12)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


func _apply_theme() -> void:
	## Build (or rebuild) the theme-owned skin. The arena footprint, pads and
	## crate colliders are shared by every theme, so this never changes a rule.
	if _theme_root != null and is_instance_valid(_theme_root):
		_theme_root.queue_free()
	_theme_root = Node3D.new()
	_theme_root.name = "ThemeRoot"
	add_child(_theme_root)
	_hazards = CargoTheme.build_scenery(_theme_root, _theme)
	if _floor != null:
		_floor.material_override = CargoTheme.floor_material(_theme)
	_apply_apron()
	_apply_sky()
	_refresh_crate_visuals()


func _apply_apron() -> void:
	var material: Material = CargoTheme.apron_material(_theme)
	if material == null:
		if _apron != null:
			_apron.visible = false
		return
	if _apron == null:
		_apron = MeshInstance3D.new()
		_apron.name = "QuaySlab"
		var slab := PlaneMesh.new()
		slab.size = Vector2(64.0, 64.0)
		_apron.mesh = slab
		_apron.position = Vector3(0.0, 0.02, 0.0)
		add_child(_apron)
	_apron.visible = true
	_apron.material_override = material


func _apply_sky() -> void:
	var world: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null:
		return
	var env: Environment = world.environment
	var sky: ProceduralSkyMaterial = null
	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		sky = env.sky.sky_material as ProceduralSkyMaterial
	if sky != null:
		sky.sky_top_color = _theme.get("sky_top", sky.sky_top_color) as Color
		sky.sky_horizon_color = _theme.get("sky_horizon", sky.sky_horizon_color) as Color
		sky.ground_horizon_color = _theme.get("sky_horizon", sky.ground_horizon_color) as Color
		sky.ground_bottom_color = _theme.get("ground_bottom", sky.ground_bottom_color) as Color
	env.fog_light_color = _theme.get("fog_color", env.fog_light_color) as Color
	if env.fog_enabled:
		env.fog_density = float(_theme.get("fog_density", env.fog_density))


func _build_crates() -> void:
	var meshes: Array[Mesh] = CargoTheme.crate_meshes(_theme)
	var material: Material = CargoTheme.crate_material(_theme)
	var extents: Vector3 = CargoTheme.crate_extents()
	var mass: float = CargoTheme.crate_mass(_theme)
	var damp: float = CargoTheme.crate_damp(_theme)
	var count: int = 3 if _selftest else CRATE_COUNT
	for i in count:
		var angle: float = TAU * float(i) / float(count)
		var home := Vector3(cos(angle) * CRATE_RING,
			extents.y * 0.5 + 0.06, sin(angle) * CRATE_RING)
		var crate := RigidBody3D.new()
		crate.name = "Cargo_%02d" % i
		crate.mass = mass
		crate.collision_layer = CollisionLayers.PROP | CollisionLayers.SOLID_PROP
		crate.collision_mask = CollisionLayers.WORLD | CollisionLayers.SOLID_PROP
		crate.linear_damp = damp
		crate.angular_damp = clampf(damp * 1.4, 0.08, 3.0)
		crate.continuous_cd = true
		crate.position = home
		var shape := BoxShape3D.new()
		shape.size = extents
		var collision := CollisionShape3D.new()
		collision.shape = shape
		crate.add_child(collision)
		var visual := MeshInstance3D.new()
		visual.name = "CrateVisual"
		visual.mesh = meshes[i % meshes.size()]
		visual.material_override = material
		crate.add_child(visual)
		crate.add_to_group(CRATE_GROUP)
		add_child(crate)
		_crates.append(crate)
		_crate_visuals.append(visual)
		_crate_home.append(home)
		_crate_respawn.append(0.0)


func _place_local_cart() -> void:
	if _cart == null:
		return
	# Every player starts on their own team's side of the yard, facing the
	# crate ring in the middle.
	var side: float = 1.0 if _local_team == 0 else -1.0
	var spawn := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.22, 18.0 * side))
	_cart.global_transform = spawn
	_cart.velocity = Vector3.ZERO
	_cart.set_spawn_transform(spawn)
	_cart.surface_grip = float(_theme.get("grip", 1.0))
	_cart.set_physics_process(false)


func _build_bots() -> void:
	if _multiplayer and not _is_host:
		return
	var count: int = _bot_count()
	for index in count:
		_spawn_bot(index, false)
	_rebuild_traffic()


func _bot_count() -> int:
	if _selftest:
		return 2
	if _multiplayer:
		# Online the host's lobby setting is authoritative; a room may run
		# humans only.
		return clampi(Network.session_bot_count, 0, BOT_MAX)
	return clampi(maxi(GameSettings.effective_bot_count(), BOT_MIN), BOT_MIN, BOT_MAX)


func _bot_vehicle() -> String:
	var entry: Dictionary = VehicleCatalog.find(GameSettings.minigame_vehicle)
	if entry.is_empty():
		return VehicleCatalog.DEFAULT_ID
	return GameSettings.minigame_vehicle


func _spawn_bot(index: int, ghost: bool) -> void:
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	cart.name = "CargoBot_%d" % (index + 1)
	var spawn: Vector3 = _bot_spawn(index)
	cart.position = spawn
	cart.rotation.y = atan2(spawn.x, spawn.z)
	if not ghost:
		cart.ai_mode = true
	add_child(cart)
	var ai: SandboxBot = null
	if ghost:
		cart.setup_remote(9000 + index)
	else:
		cart.setup_ai(_bot_vehicle())
		cart.set_spawn_transform(cart.global_transform)
		ai = SandboxBot.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = 7301 + index * 137
		ai.setup(cart, index, rng, clampi(GameSettings.minigame_difficulty, 0, 2))
	var label := Label3D.new()
	label.name = "BotTag"
	label.text = "BOT %d" % (index + 1)
	label.font = load(TITLE_FONT)
	label.font_size = 48
	label.pixel_size = 0.008
	label.outline_size = 14
	label.outline_modulate = UiPalette.OUTLINE
	label.modulate = TEAM_COLORS[_bot_team(index)].lightened(0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.4, 0.0)
	cart.add_child(label)
	_bots.append({
		"cart": cart,
		"ai": ai,
		"team": _bot_team(index),
		"ghost": ghost,
		"crate": -1,
		"pick_ms": 0,
		"shove_ms": 0,
	})


func _bot_team(index: int) -> int:
	# Rivals split across both teams so the player always has a teammate and
	# an opponent in a two-bot solo match.
	return 1 if index % 2 == 0 else 0


func _bot_spawn(index: int) -> Vector3:
	var team: int = _bot_team(index)
	var side: float = 1.0 if team == 0 else -1.0
	var slot: int = index / 2
	var x: float = (-7.0 if index % 4 < 2 else 7.0) - float(slot) * 5.0
	var z: float = side * (21.0 + float(slot) * 2.0)
	return Vector3(x, 0.22, z)


func _rebuild_traffic() -> void:
	_traffic.clear()
	if _cart != null and is_instance_valid(_cart):
		_traffic.append(_cart)
	for entry: Dictionary in _bots:
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart) and not bool(entry.get("ghost", false)):
			_traffic.append(cart)


func _connect_local_cart() -> void:
	if _cart == null:
		return
	if not _cart.net_push_requested.is_connected(_on_local_push_requested):
		_cart.net_push_requested.connect(_on_local_push_requested)


# --------------------------------------------------------------------------
# match flow


func _begin_countdown() -> void:
	_phase = Phase.COUNTDOWN
	_countdown = COUNTDOWN_SECONDS
	_last_count = int(ceil(_countdown))
	_remaining = _match_length
	_overtime = false
	_overtime_remaining = 0.0
	if _countdown_label != null:
		_countdown_label.text = str(_last_count)
		_countdown_label.visible = true
	if _selftest:
		_countdown_label.visible = false
		_start_race()


func _tick_countdown(delta: float) -> void:
	_countdown = maxf(_countdown - delta, 0.0)
	var count: int = int(ceil(_countdown))
	if count == _last_count:
		return
	_last_count = count
	if count > 0:
		_countdown_label.text = str(count)
		_countdown_label.visible = true
		_pop_label(_countdown_label)
		_play_one_shot(COUNTDOWN_BEEP, -8.0, 1.0 + float(3 - count) * 0.06)
		return
	_countdown_label.visible = false
	_show_toast("GO!", 0.9)
	_play_one_shot(COUNTDOWN_GO, -5.0, 1.0)
	if not _multiplayer or _is_host:
		_start_race()


func _start_race() -> void:
	if _phase != Phase.COUNTDOWN:
		return
	_phase = Phase.RACING
	_remaining = _match_length
	_overtime = false
	_countdown_label.visible = false
	_set_cart_active(true)
	_show_toast("SHOVE CRATES INTO YOUR PAD", 2.2)
	if _multiplayer and _is_host:
		_broadcast_state()


func _set_cart_active(active: bool) -> void:
	if _cart != null and is_instance_valid(_cart):
		_cart.set_physics_process(active)
		if not active:
			_cart.velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	_time += delta
	if _multiplayer and _is_host and _cart != null \
			and Network.is_session_active():
		Network.resolve_car_collisions(_cart, _remote_carts)
	_net_tick(delta)
	_apply_theme_grip(delta)
	match _phase:
		Phase.COUNTDOWN:
			_tick_countdown(delta)
		Phase.RACING:
			if _is_host or not _multiplayer:
				_tick_crates(delta)
				_tick_clock(delta)
			_tick_bots(delta)
	if _selftest:
		_selftest_tick(delta)


func _tick_clock(delta: float) -> void:
	if _overtime:
		_overtime_remaining = maxf(_overtime_remaining - delta, 0.0)
		if _overtime_remaining <= 0.0:
			_finish_match()
		return
	_remaining = maxf(_remaining - delta, 0.0)
	if _remaining > 0.0:
		return
	if _score[0] == _score[1]:
		_overtime = true
		_overtime_remaining = _overtime_length
		_show_toast("OVERTIME  ·  NEXT DELIVERY WINS", 2.6)
		if _debug:
			print("CARGO_DEBUG overtime start")
		_broadcast_state()
	else:
		_finish_match()


func _tick_crates(delta: float) -> void:
	for index in _crates.size():
		if _crate_respawn[index] > 0.0:
			_crate_respawn[index] = maxf(_crate_respawn[index] - delta, 0.0)
			if _crate_respawn[index] <= 0.0:
				_reset_crate(index)
			continue
		var crate: RigidBody3D = _crates[index]
		if not is_instance_valid(crate):
			continue
		var position: Vector3 = crate.global_position
		if position.y < -4.0 or absf(position.x) > ARENA_HALF + 6.0 \
				or absf(position.z) > ARENA_HALF + 6.0:
			_reset_crate(index)
			continue
		for team in TEAM_COUNT:
			if _inside_pad(position, team):
				_deliver(index, team)
				if _phase == Phase.FINISHED:
					return
				break


func _inside_pad(position: Vector3, team: int) -> bool:
	var centre: Vector3 = _pads[team]
	return absf(position.x - centre.x) <= PAD_HALF.x \
		and absf(position.z - centre.z) <= PAD_HALF.y \
		and position.y <= 3.5


func _deliver(index: int, team: int) -> void:
	_score[team] = _score[team] + 1
	var crate: RigidBody3D = _crates[index]
	if is_instance_valid(crate):
		crate.freeze = true
		crate.collision_layer = 0
		crate.linear_velocity = Vector3.ZERO
		crate.angular_velocity = Vector3.ZERO
	_crate_respawn[index] = CRATE_RESPAWN_DELAY
	if index < _crate_visuals.size() and is_instance_valid(_crate_visuals[index]):
		_crate_visuals[index].visible = false
	_flash_pad(team)
	_show_toast("%s DELIVERS!" % _team_names[team], 1.5)
	_play_one_shot(DELIVERY_CHIME, -5.0, 1.08)
	_refresh_score_now()
	if _debug:
		print("CARGO_DEBUG delivery team=%d score=%d-%d"
			% [team, _score[0], _score[1]])
	if _multiplayer and _is_host:
		_broadcast_delivery(team)
		_broadcast_state()
	if _overtime:
		_finish_match()


func _reset_crate(index: int) -> void:
	var crate: RigidBody3D = _crates[index]
	if not is_instance_valid(crate):
		return
	crate.freeze = true
	crate.global_transform = Transform3D(Basis.IDENTITY, _crate_home[index])
	crate.reset_physics_interpolation()
	crate.linear_velocity = Vector3.ZERO
	crate.angular_velocity = Vector3.ZERO
	crate.collision_layer = CollisionLayers.PROP | CollisionLayers.SOLID_PROP
	crate.freeze = false
	crate.sleeping = false
	if index < _crate_visuals.size() and is_instance_valid(_crate_visuals[index]):
		_crate_visuals[index].visible = true


func _refresh_crate_visuals() -> void:
	var meshes: Array[Mesh] = CargoTheme.crate_meshes(_theme)
	var material: Material = CargoTheme.crate_material(_theme)
	for index in _crate_visuals.size():
		var visual: MeshInstance3D = _crate_visuals[index]
		if not is_instance_valid(visual):
			continue
		visual.mesh = meshes[index % meshes.size()]
		visual.material_override = material


func _finish_match() -> void:
	if _phase == Phase.FINISHED:
		return
	_phase = Phase.FINISHED
	_countdown_label.visible = false
	_set_cart_active(false)
	for entry: Dictionary in _bots:
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart):
			cart.set_ai_controls(0.0, 0.5, 0.0)
	if _multiplayer and _is_host:
		Network.set_room_state("finished")
		_broadcast_match_end()
	if _debug:
		print("CARGO_DEBUG finish score=%d-%d overtime=%s winner=%d"
			% [_score[0], _score[1], str(_overtime), _winner()])
	_show_result()


func _winner() -> int:
	if _score[0] == _score[1]:
		return -1
	return 0 if _score[0] > _score[1] else 1


func _show_result() -> void:
	var winner: int = _winner()
	var title: String = "DRAW"
	if winner == _local_team:
		title = "VICTORY!"
	elif winner >= 0:
		title = "DEFEAT"
	_result_title.text = title
	_result_subtitle.text = "%s  ·  %s" % [str(_theme.get("name", "CARGO RUSH")),
		str(_theme.get("blurb", "ARENA SCRAMBLE"))]
	for team in TEAM_COUNT:
		_result_team_labels[team].text = _team_names[team]
		_result_score_labels[team].text = str(_score[team])
	_result_note.text = "MOST DELIVERIES WINS"
	_result_root.visible = true
	_result_root.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(_result_root, "modulate:a", 1.0, 0.24) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	CursorController.set_menu_mode(true)
	var pause_root: Control = get_node_or_null("PauseMenu/Root") as Control
	if pause_root == null or not pause_root.visible:
		MenuNav.refresh()
		if _result_primary != null:
			MenuNav.focus(_result_primary)
	_play_one_shot(FINISH_FANFARE, -7.0, 1.0)


# --------------------------------------------------------------------------
# theme grip


func _apply_theme_grip(delta: float) -> void:
	if _traffic.is_empty():
		return
	var base_grip: float = float(_theme.get("grip", 1.0))
	for cart: CartPlayer in _traffic:
		if not is_instance_valid(cart) or cart.remote_mode:
			continue
		var grip: float = base_grip
		var spin: float = 0.0
		for zone: Dictionary in _hazards:
			var centre: Vector3 = zone.get("centre", Vector3.ZERO) as Vector3
			var radius: float = float(zone.get("radius", 0.0))
			var offset: Vector3 = cart.global_position - centre
			offset.y = 0.0
			if offset.length_squared() <= radius * radius:
				grip = minf(grip, float(zone.get("grip", grip)))
				spin = maxf(spin, float(zone.get("spin", 0.0)))
		cart.surface_grip = clampf(grip, 0.2, 1.5)
		if spin <= 0.0 or not cart.is_on_floor():
			continue
		if cart.current_state != CartPlayer.CartState.DRIVING:
			continue
		var wobble: float = sin(_time * 2.7 + float(cart.get_instance_id() % 31)) * spin
		cart.rotate_y(wobble * delta * 0.30)
		cart.velocity += cart.global_transform.basis.x * wobble * delta * 1.25


# --------------------------------------------------------------------------
# bots


func _tick_bots(delta: float) -> void:
	if _bots.is_empty():
		return
	if _multiplayer and not _is_host:
		return
	for entry: Dictionary in _bots:
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		var ai: SandboxBot = entry.get("ai") as SandboxBot
		if cart == null or not is_instance_valid(cart) or ai == null:
			continue
		if _phase != Phase.RACING:
			cart.set_ai_controls(0.0, 0.45, 0.0)
			continue
		var goal: Dictionary = _bot_goal(entry)
		var target: Vector3 = goal.get("target", Vector3.ZERO) as Vector3
		var near: bool = bool(goal.get("near", false))
		var push: bool = bool(goal.get("push", false))
		entry["close"] = push
		if near:
			# Short-range cargo logic is ours: stage behind the crate, then
			# drive through it. The sandbox driver's arrival test treats a
			# sustained shove as being stuck, so it must not own this phase.
			ai.stuck = 0.0
			ai._reverse_timer = 0.0
			ai._reverse_cooldown = 0.0
			_drive_to(cart, target, push)
		else:
			# Far from the crate, let the sandbox driver do the driving: its
			# obstacle rays, stuck recovery and personalities are unchanged.
			ai._dest_target = target
			ai._dest_entry = target
			ai._via_active = false
			ai._dest_phase = 0
			ai._dest_timer = 0.0
			ai._near_timer = 0.0
			ai.tick(delta, _time, _traffic)
			if ai.stuck > 5.0 or ai.stranded > 1.5:
				ai.respawn()
		# Always try: a bot pinned beside the crate may read as "not pushing"
		# for a frame while it is physically touching the box.
		_try_bot_shove(entry)
	if _debug:
		_debug_timer += delta
		if _debug_timer >= 5.0:
			_debug_timer = 0.0
			_debug_bots()


func _drive_to(cart: CartPlayer, target: Vector3, push: bool) -> void:
	## Direct short-range steering for cargo work. Waypoints are approached at
	## a controllable speed so a 20 m/s bot does not overshoot the staging point
	## and swing around again. Push mode never brakes: the point is to stay on
	## the crate and let the shove cooldown do its job.
	var local: Vector3 = cart.to_local(target)
	if not local.is_finite():
		return
	var steer: float = clampf(atan2(-local.x, -local.z) * 2.1, -1.0, 1.0)
	var distance: float = Vector2(local.x, local.z).length()
	var speed: float = Vector2(cart.velocity.x, cart.velocity.z).length()
	if push:
		cart.set_ai_controls(1.0, 0.0, steer, false)
		return
	var desired: float = 9.0 if distance > 10.0 \
		else lerpf(1.8, 9.0, clampf(distance / 10.0, 0.0, 1.0))
	var throttle: float = 1.0 if speed < desired else 0.0
	var brake: float = 0.0
	if speed > desired + 0.6:
		brake = clampf((speed - desired) / 6.0, 0.0, 0.9)
	cart.set_ai_controls(throttle, brake, steer, false)


func _debug_bots() -> void:
	## Gated by CART_CARGO_DEBUG: a compact per-bot state line for headless
	## balancing runs. Costs nothing when the variable is unset.
	for entry: Dictionary in _bots:
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		var ai: SandboxBot = entry.get("ai") as SandboxBot
		if cart == null or not is_instance_valid(cart):
			continue
		var pick: int = int(entry.get("crate", -1))
		var crate_gap: float = -1.0
		var crate_pos := Vector3.ZERO
		if pick >= 0 and pick < _crates.size():
			crate_pos = _crates[pick].global_position
			crate_gap = _planar_distance(cart.global_position, crate_pos)
		var stuck: float = ai.stuck if ai != null else -1.0
		print("CARGO_DEBUG bot team=%d pos=(%.1f,%.1f) speed=%.1f stuck=%.1f "
			% [int(entry.get("team", 1)), cart.global_position.x,
			cart.global_position.z, cart.velocity.length(), stuck]
			+ "pick=%d gap=%.1f crate=(%.1f,%.1f) throttle=%.2f close=%s shoves=%d"
			% [pick, crate_gap, crate_pos.x, crate_pos.z, cart.ai_throttle,
			str(bool(entry.get("close", false))), _bot_shove_count])


func _bot_goal(entry: Dictionary) -> Dictionary:
	var cart: CartPlayer = entry.get("cart") as CartPlayer
	var team: int = int(entry.get("team", 1))
	var pad: Vector3 = _pads[team]
	var pick: int = int(entry.get("crate", -1))
	var now: int = Time.get_ticks_msec()
	if pick < 0 or pick >= _crates.size() or _crate_respawn[pick] > 0.0 \
			or now - int(entry.get("pick_ms", 0)) > 5000:
		pick = _pick_bot_crate(cart, team)
		entry["crate"] = pick
		entry["pick_ms"] = now
	if pick < 0:
		return {"target": pad, "near": false, "push": false, "crate_pos": pad}
	var crate_position: Vector3 = _crates[pick].global_position
	var to_pad: Vector3 = pad - crate_position
	to_pad.y = 0.0
	if to_pad.length_squared() < 0.1:
		to_pad = Vector3(0.0, 0.0, -1.0 if team == 0 else 1.0)
	to_pad = to_pad.normalized()
	var offset: Vector3 = crate_position - cart.global_position
	offset.y = 0.0
	var gap: float = offset.length()
	var lateral := Vector3(-to_pad.z, 0.0, to_pad.x)
	var along: float = offset.dot(to_pad)
	var near: bool = gap < 30.0
	var push: bool = near and along > 1.2
	var target: Vector3 = crate_position
	if push:
		# Aim at the crate itself: a point beyond it lets an off-centre bot
		# slide past and end up between the crate and its own pad.
		target = crate_position + to_pad * 0.6
	elif near and gap < 5.5:
		# Stuck on the wrong side: swing wide of the crate before turning in.
		var side: float = signf(offset.dot(lateral))
		target = crate_position + lateral * (6.0 if side >= 0.0 else -6.0)
	elif near:
		target = crate_position - to_pad * 4.5
	return {"target": target, "near": near, "push": push,
		"crate_pos": crate_position}


func _pick_bot_crate(cart: CartPlayer, team: int) -> int:
	var best: int = -1
	var best_score: float = INF
	# A little random taste per cart stops the whole field pushing one box.
	var bias: float = 0.85 + float(cart.get_instance_id() % 7) * 0.04
	for index in _crates.size():
		if _crate_respawn[index] > 0.0:
			continue
		var crate: RigidBody3D = _crates[index]
		if not is_instance_valid(crate):
			continue
		var position: Vector3 = crate.global_position
		var to_bot: float = _planar_distance(position, cart.global_position)
		var to_pad: float = _planar_distance(position, _pads[team])
		var score: float = (to_bot + to_pad * 0.7) * bias
		if score < best_score:
			best_score = score
			best = index
	return best


func _try_bot_shove(entry: Dictionary) -> void:
	var cart: CartPlayer = entry.get("cart") as CartPlayer
	var now: int = Time.get_ticks_msec()
	if now - int(entry.get("shove_ms", 0)) < SHOVE_COOLDOWN_MS:
		return
	var planar := Vector3(cart.velocity.x, 0.0, cart.velocity.z)
	var speed: float = planar.length()
	# A bot pressed against a crate has almost no speed left. That is the
	# moment it should lean on the box, so fall back to the nose direction.
	var direction: Vector3 = planar / speed if speed > 0.6 \
		else -cart.global_transform.basis.z
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		return
	direction = direction.normalized()
	if speed < 0.25 and cart.ai_throttle < 0.35:
		return
	var best: int = -1
	var best_gap: float = INF
	for index in _crates.size():
		if _crate_respawn[index] > 0.0:
			continue
		var crate: RigidBody3D = _crates[index]
		if not is_instance_valid(crate):
			continue
		var offset: Vector3 = crate.global_position - cart.global_position
		offset.y = 0.0
		var gap: float = offset.length()
		if gap > SHOVE_RANGE or gap < 0.05:
			continue
		# A pinned cart cannot turn (steering needs speed), so a crate beside
		# the nose still counts when it is physically touching the cart.
		if gap > 2.4 and offset.normalized().dot(direction) < 0.15:
			continue
		if gap < best_gap:
			best_gap = gap
			best = index
	if best < 0:
		return
	var to_pad: Vector3 = _pads[int(entry.get("team", 1))] - _crates[best].global_position
	to_pad.y = 0.0
	if to_pad.length_squared() < 0.1:
		return
	_shove_crate(_crates[best], to_pad.normalized(),
		clampf(2.2 + speed * 0.25, 2.2, 3.4))
	_bot_shove_count += 1
	entry["shove_ms"] = now


func _shove_crate(crate: RigidBody3D, direction: Vector3, kick: float) -> void:
	## The AI's controlled nudge. It barely lifts the crate, so a rival shepherds
	## a box toward its pad instead of launching it over the wall.
	if not is_instance_valid(crate) or not direction.is_finite():
		return
	if direction.length_squared() < 0.0001:
		return
	crate.freeze = false
	crate.sleeping = false
	var normal: Vector3 = direction.normalized()
	var force: float = clampf(kick, 0.1, 4.0)
	crate.apply_central_impulse(normal * crate.mass * force
		+ Vector3.UP * crate.mass * force * 0.12)


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --------------------------------------------------------------------------
# HUD


func _build_hud() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 15
	add_child(_canvas)
	_hud_root = Control.new()
	_hud_root.name = "HudRoot"
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.theme = load(UI_THEME)
	_canvas.add_child(_hud_root)

	var timer_panel := PanelContainer.new()
	timer_panel.name = "TimerPlaque"
	timer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_panel.anchor_left = 0.5
	timer_panel.anchor_right = 0.5
	timer_panel.offset_left = -132.0
	timer_panel.offset_right = 132.0
	timer_panel.offset_top = 16.0
	timer_panel.offset_bottom = 112.0
	timer_panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.118, 0.106, 0.227, 0.82)))
	_hud_root.add_child(timer_panel)
	var timer_column := VBoxContainer.new()
	timer_column.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_column.add_theme_constant_override("separation", 0)
	timer_panel.add_child(timer_column)
	var timer_caption := _label("TIME", 13, Color(1, 1, 1, 0.62))
	timer_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_column.add_child(timer_caption)
	_timer_label = _label("1:30", 42, UiPalette.YELLOW, 8)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_column.add_child(_timer_label)
	_overtime_label = _label("OVERTIME", 13, UiPalette.CREAM, 4)
	_overtime_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overtime_label.visible = false
	timer_column.add_child(_overtime_label)

	var score_panel := PanelContainer.new()
	score_panel.name = "ScorePlaque"
	score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_panel.offset_left = 24.0
	score_panel.offset_top = 16.0
	score_panel.offset_right = 338.0
	score_panel.offset_bottom = 150.0
	score_panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.118, 0.106, 0.227, 0.80)))
	_hud_root.add_child(score_panel)
	var score_column := VBoxContainer.new()
	score_column.add_theme_constant_override("separation", 4)
	score_panel.add_child(score_column)
	score_column.add_child(_label("DELIVERED", 12, Color(1, 1, 1, 0.55)))
	for team in TEAM_COUNT:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		score_column.add_child(row)
		var dot := ColorRect.new()
		dot.color = TEAM_COLORS[team]
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot)
		var name_label := _label(_team_names[team], 18, UiPalette.CREAM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.clip_text = true
		row.add_child(name_label)
		var value := _label("0", 26, UiPalette.YELLOW, 5)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		_team_name_labels.append(name_label)
		_score_labels.append(value)

	var theme_panel := PanelContainer.new()
	theme_panel.name = "ThemePlaque"
	theme_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_panel.anchor_left = 1.0
	theme_panel.anchor_right = 1.0
	theme_panel.offset_left = -338.0
	theme_panel.offset_right = -24.0
	theme_panel.offset_top = 16.0
	theme_panel.offset_bottom = 162.0
	theme_panel.add_theme_stylebox_override("panel",
		_panel_style(Color(0.118, 0.106, 0.227, 0.76)))
	_hud_root.add_child(theme_panel)
	var theme_column := VBoxContainer.new()
	theme_column.add_theme_constant_override("separation", 2)
	theme_panel.add_child(theme_column)
	theme_column.add_child(_label("ARENA", 12, Color(1, 1, 1, 0.55)))
	_theme_name_label = _label(str(_theme.get("name", "DOCKYARD")), 24,
		UiPalette.CREAM, 5)
	theme_column.add_child(_theme_name_label)
	_theme_detail_label = _label("", 12, Color(1, 1, 1, 0.62))
	_theme_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	theme_column.add_child(_theme_detail_label)

	_countdown_label = _label("3", 112, UiPalette.YELLOW, 14)
	_countdown_label.theme_type_variation = &"TitleLabel"
	_countdown_label.add_theme_constant_override("outline_size", 14)
	_countdown_label.add_theme_color_override("font_outline_color", UiPalette.OUTLINE)
	_countdown_label.anchor_left = 0.5
	_countdown_label.anchor_right = 0.5
	_countdown_label.anchor_top = 0.5
	_countdown_label.anchor_bottom = 0.5
	_countdown_label.offset_left = -320.0
	_countdown_label.offset_right = 320.0
	_countdown_label.offset_top = -170.0
	_countdown_label.offset_bottom = -20.0
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud_root.add_child(_countdown_label)

	_toast_label = _label("", 26, Color.WHITE, 10)
	_toast_label.anchor_left = 0.5
	_toast_label.anchor_right = 0.5
	_toast_label.offset_left = -470.0
	_toast_label.offset_right = 470.0
	_toast_label.offset_top = 138.0
	_toast_label.offset_bottom = 184.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.visible = false
	_hud_root.add_child(_toast_label)
	_refresh_theme_text()
	_refresh_team_texts()
	_refresh_score_now()


func _panel_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(CORNER_RADIUS)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 12.0
	style.anti_aliasing = true
	return style


func _label(text: String, size: int, colour: Color, outline: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if outline > 0:
		label.add_theme_color_override("font_outline_color", UiPalette.OUTLINE)
		label.add_theme_constant_override("outline_size", outline)
	return label


func _refresh_theme_text() -> void:
	if _theme_name_label == null or _theme_detail_label == null:
		return
	_theme_name_label.text = str(_theme.get("name", "DOCKYARD"))
	_theme_detail_label.text = "%s  ·  %s" % [CargoTheme.crate_label(_theme),
		str(_theme.get("hazard_label", ""))]


func _refresh_team_texts() -> void:
	for team in TEAM_COUNT:
		if team < _team_name_labels.size():
			_team_name_labels[team].text = _team_names[team]
			_team_name_labels[team].add_theme_color_override("font_color",
				UiPalette.YELLOW if team == _local_team else UiPalette.CREAM)
		if team < _pad_labels.size():
			_pad_labels[team].text = _team_names[team]
			_pad_labels[team].modulate = TEAM_COLORS[team].lightened(0.35)
		if team < _pad_visuals.size():
			var mat: StandardMaterial3D = _pad_visuals[team].material_override \
				as StandardMaterial3D
			if mat != null:
				mat.albedo_color = TEAM_COLORS[team].darkened(0.06)


func _refresh_score_now() -> void:
	for team in TEAM_COUNT:
		if team < _score_labels.size():
			_score_labels[team].text = str(_score[team])


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer = maxf(_toast_timer - delta, 0.0)
		if _toast_timer <= 0.0 and _toast_label != null:
			_toast_label.visible = false
	_hud_timer += delta
	if _hud_timer < 0.1:
		return
	_hud_timer = 0.0
	_refresh_hud()


func _refresh_hud() -> void:
	if _timer_label == null:
		return
	var timer_text: String = _clock_text()
	if timer_text != _last_timer_text:
		_last_timer_text = timer_text
		_timer_label.text = timer_text
	_overtime_label.visible = _overtime and _phase != Phase.FINISHED
	var scores := PackedStringArray([str(_score[0]), str(_score[1])])
	if scores != _last_score_text:
		_last_score_text = scores
		_refresh_score_now()


func _clock_text() -> String:
	var seconds: float = _overtime_remaining if _overtime else _remaining
	if _phase == Phase.FINISHED:
		seconds = _overtime_remaining if _overtime else 0.0
	var whole: int = maxi(int(ceil(seconds)), 0)
	var text: String = "%d:%02d" % [whole / 60, whole % 60]
	return "OT " + text if _overtime else text


func _show_toast(text: String, duration: float) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_label.visible = true
	_toast_timer = duration


func _pop_label(label: Label) -> void:
	if label == null:
		return
	label.scale = Vector2.ONE * 1.22
	label.pivot_offset = label.size * 0.5
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _flash_pad(team: int) -> void:
	if team < _pad_visuals.size() and is_instance_valid(_pad_visuals[team]):
		var pad: MeshInstance3D = _pad_visuals[team]
		pad.scale = Vector3(1.0, 1.0, 1.08)
		var tween := create_tween()
		tween.tween_property(pad, "scale", Vector3.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var pop := Label3D.new()
	pop.name = "ScorePop"
	pop.text = "+1"
	pop.font = load(TITLE_FONT)
	pop.font_size = 96
	pop.pixel_size = 0.010
	pop.outline_size = 16
	pop.outline_modulate = UiPalette.OUTLINE
	pop.modulate = TEAM_COLORS[team].lightened(0.35)
	pop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pop.no_depth_test = true
	pop.position = _pads[team] + Vector3.UP * 3.4
	add_child(pop)
	var tween := create_tween()
	tween.tween_property(pop, "position:y", pop.position.y + 2.6, 0.85)
	tween.parallel().tween_property(pop, "modulate:a", 0.0, 0.85)
	tween.tween_callback(pop.queue_free)


func _build_result_card() -> void:
	_result_root = Control.new()
	_result_root.name = "ResultCard"
	_result_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_root.visible = false
	_result_root.add_to_group("nav_scope")
	_hud_root.add_child(_result_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.06, 0.09, 0.19, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = UiPalette.CREAM
	panel_style.border_color = UiPalette.OUTLINE
	panel_style.set_border_width_all(5)
	panel_style.set_corner_radius_all(CORNER_RADIUS)
	panel_style.content_margin_left = 5.0
	panel_style.content_margin_right = 5.0
	panel_style.content_margin_top = 5.0
	panel_style.content_margin_bottom = 5.0
	panel_style.shadow_color = Color(0.12, 0.10, 0.23, 0.45)
	panel_style.shadow_offset = Vector2(0, 10)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_theme_constant_override("margin_top", 22)
	pad.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(pad)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	pad.add_child(body)

	var banner := PanelContainer.new()
	var banner_style := StyleBoxFlat.new()
	banner_style.bg_color = UiPalette.YELLOW
	banner_style.set_corner_radius_all(CORNER_RADIUS)
	banner_style.content_margin_left = 18.0
	banner_style.content_margin_right = 18.0
	banner_style.content_margin_top = 2.0
	banner_style.content_margin_bottom = 4.0
	banner.add_theme_stylebox_override("panel", banner_style)
	body.add_child(banner)
	_result_title = _label("VICTORY!", 34, UiPalette.INK)
	_result_title.theme_type_variation = &"TitleLabel"
	_result_title.add_theme_constant_override("outline_size", 0)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(_result_title)

	_result_subtitle = _label("", 14, UiPalette.MUTED)
	_result_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_result_subtitle)

	var scores := HBoxContainer.new()
	scores.alignment = BoxContainer.ALIGNMENT_CENTER
	scores.add_theme_constant_override("separation", 56)
	body.add_child(scores)
	for team in TEAM_COUNT:
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 0)
		scores.add_child(column)
		var team_label := _label(_team_names[team], 14, UiPalette.MUTED)
		team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(team_label)
		var value := _label("0", 36, UiPalette.INK, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(value)
		_result_team_labels.append(team_label)
		_result_score_labels.append(value)

	_result_note = _label("MOST DELIVERIES WINS", 12, UiPalette.MUTED)
	_result_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_result_note)

	if _multiplayer:
		_result_primary = _make_button("BACK TO LOBBY", UiPalette.YELLOW, 58.0)
		_result_primary.pressed.connect(_on_back_to_lobby)
	else:
		_result_primary = _make_button("PLAY AGAIN", UiPalette.YELLOW, 58.0)
		_result_primary.pressed.connect(_on_play_again)
	body.add_child(_result_primary)
	var menu := _make_button("MAIN MENU", UiPalette.RED, 52.0)
	menu.pressed.connect(_on_main_menu)
	body.add_child(menu)


func _make_button(text: String, colour: Color, height: float) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", colour)
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", 22)
	return button


# --------------------------------------------------------------------------
# audio


func _play_one_shot(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = volume_db
	player.pitch_scale = pitch
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


# --------------------------------------------------------------------------
# multiplayer: host-authoritative crates, peer-owned carts


func _setup_multiplayer() -> void:
	if not _multiplayer:
		return
	_props_setup()
	for peer_id: int in multiplayer.get_peers():
		_spawn_remote_cart(peer_id)
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not Network.names_changed.is_connected(_refresh_name_labels):
		Network.names_changed.connect(_refresh_name_labels)
	if not Network.tag_colors_changed.is_connected(_refresh_name_labels):
		Network.tag_colors_changed.connect(_refresh_name_labels)
	Network.notify_scene_ready()
	if _is_host:
		_broadcast_state()
		_broadcast_bot_states()
	else:
		rpc_id(1, "_net_cargo_ready", _theme_id, _bot_vehicle())


func _props_setup() -> void:
	for crate: RigidBody3D in _crates:
		if not is_instance_valid(crate):
			continue
		if not _is_host:
			crate.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			crate.freeze = true


func _on_peer_connected(peer_id: int) -> void:
	_spawn_remote_cart(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var cart: CartPlayer = _remote_carts.get(peer_id) as CartPlayer
	if cart != null:
		cart.queue_free()
		_remote_carts.erase(peer_id)
	_name_labels.erase(peer_id)


func _spawn_remote_cart(peer_id: int) -> void:
	if _remote_carts.has(peer_id) or peer_id == multiplayer.get_unique_id():
		return
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	cart.name = "Remote_%d" % peer_id
	cart.position = Vector3(0.0, 0.22, 18.0)
	add_child(cart)
	cart.setup_remote(peer_id)
	cart.net_position = cart.global_position
	cart.net_yaw = cart.rotation.y
	var label := Label3D.new()
	label.name = "NameTag"
	label.text = Network.name_of(peer_id)
	label.font = load(TITLE_FONT)
	label.font_size = 56
	label.pixel_size = 0.010
	label.outline_size = 16
	label.outline_modulate = UiPalette.OUTLINE
	label.modulate = Network.color_of(peer_id)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.2, 0.0)
	cart.add_child(label)
	_name_labels[peer_id] = label
	_remote_carts[peer_id] = cart
	if _cart != null:
		var camera := _cart.get_node_or_null("CameraArm/Camera3D") as Camera3D
		if camera != null:
			camera.current = true


func _refresh_name_labels() -> void:
	for peer_id: int in _name_labels:
		var label: Label3D = _name_labels[peer_id] as Label3D
		if is_instance_valid(label):
			label.text = Network.name_of(peer_id)
			label.modulate = Network.color_of(peer_id)


func _net_tick(delta: float) -> void:
	if not _multiplayer or not Network.is_session_active():
		return
	if _cart != null and is_instance_valid(_cart):
		_cart_sync_timer += delta
		if _cart_sync_timer >= CART_SYNC_INTERVAL:
			_cart_sync_timer = 0.0
			var stamp: int = Time.get_ticks_msec()
			if _is_host:
				_broadcast_cart_state(multiplayer.get_unique_id(),
					_cart.global_position, _cart.rotation.y, stamp, _cart.velocity)
			elif Network.is_scene_ready(1):
				rpc_id(1, "_net_cargo_cart_state", multiplayer.get_unique_id(),
					_cart.global_position, _cart.rotation.y, stamp, _cart.velocity)
	if _is_host:
		_prop_sync_timer += delta
		if _prop_sync_timer >= PROP_SYNC_INTERVAL:
			_prop_sync_timer = 0.0
			_broadcast_props()
		_bot_sync_timer += delta
		if _bot_sync_timer >= PROP_SYNC_INTERVAL and not _bots.is_empty():
			_bot_sync_timer = 0.0
			_broadcast_bot_states()
		_state_sync_timer += delta
		if _state_sync_timer >= STATE_SYNC_INTERVAL:
			_state_sync_timer = 0.0
			_broadcast_state()
	else:
		_expire_prop_kicks()
		_apply_prop_targets(delta)


func _rpc_sender() -> int:
	return multiplayer.get_remote_sender_id() if multiplayer.multiplayer_peer != null else 0


func _broadcast_cart_state(peer_id: int, position: Vector3, yaw: float,
		sent_ms: int, velocity: Vector3) -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_cargo_cart_state", peer_id, position, yaw,
				sent_ms, velocity)


@rpc("any_peer", "unreliable")
func _net_cargo_cart_state(peer_id: int, position: Vector3, yaw: float,
		sent_ms: int, velocity: Vector3 = Vector3.ZERO) -> void:
	var sender: int = _rpc_sender()
	if sender != 1 and peer_id != sender:
		return
	if not position.is_finite() or not is_finite(yaw) or not velocity.is_finite():
		return
	if position.length_squared() > 5000.0 * 5000.0 or sent_ms < 0:
		return
	var cart: CartPlayer = _remote_carts.get(peer_id) as CartPlayer
	var accepted: bool = false
	if cart != null and cart.remote_mode:
		accepted = cart.set_net_state(position, yaw, sent_ms, velocity)
	if _is_host and sender != 1 and accepted:
		var now: int = Time.get_ticks_msec()
		if now - int(_cart_relay_ms.get(peer_id, -10000)) >= 25:
			_cart_relay_ms[peer_id] = now
			_broadcast_cart_state(peer_id, position, yaw, sent_ms, velocity)


func _broadcast_props() -> void:
	if _crates.is_empty():
		return
	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	for crate: RigidBody3D in _crates:
		if is_instance_valid(crate):
			positions.append(crate.global_position)
			rotations.append(crate.global_rotation)
		else:
			positions.append(Vector3.ZERO)
			rotations.append(Vector3.ZERO)
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_props", positions, rotations)


@rpc("authority", "unreliable")
func _net_props(positions: PackedVector3Array, rotations: PackedVector3Array) -> void:
	if _is_host or not _multiplayer:
		return
	if positions.size() != _crates.size() or rotations.size() != _crates.size():
		return
	for index in positions.size():
		if not positions[index].is_finite() or not rotations[index].is_finite():
			continue
		_prop_targets[index] = [positions[index], rotations[index]]


func _apply_prop_targets(delta: float) -> void:
	if _prop_targets.is_empty():
		return
	var blend: float = 1.0 - exp(-12.0 * delta)
	for index: int in _prop_targets:
		if index < 0 or index >= _crates.size():
			continue
		var crate: RigidBody3D = _crates[index]
		if not is_instance_valid(crate):
			continue
		if _prop_kick_until.has(crate.get_instance_id()):
			continue
		var data: Array = _prop_targets[index]
		var target: Vector3 = data[0] as Vector3
		var target_rotation: Vector3 = data[1] as Vector3
		if crate.global_position.distance_squared_to(target) \
				> CLIENT_SNAP_DISTANCE * CLIENT_SNAP_DISTANCE:
			crate.global_transform = Transform3D(Basis.from_euler(target_rotation), target)
			crate.reset_physics_interpolation()
			continue
		crate.global_position = crate.global_position.lerp(target, blend)
		crate.global_rotation = Vector3(
			lerp_angle(crate.global_rotation.x, target_rotation.x, blend),
			lerp_angle(crate.global_rotation.y, target_rotation.y, blend),
			lerp_angle(crate.global_rotation.z, target_rotation.z, blend))


func _on_local_push_requested(prop: Node, direction: Vector3, kick: float) -> void:
	if not _multiplayer or _is_host:
		return
	var index: int = _crates.find(prop as RigidBody3D)
	if index < 0:
		return
	# Predict locally so the crate moves on this screen immediately; the host
	# remains authoritative and the next snapshot corrects the pose.
	_kick_prop(prop as RigidBody3D, direction, kick)
	rpc_id(1, "_net_request_push", index, direction, kick)


func _kick_prop(prop: RigidBody3D, direction: Vector3, kick: float) -> void:
	if not is_instance_valid(prop) or not direction.is_finite() or not is_finite(kick):
		return
	if direction.length_squared() < 0.0001:
		return
	prop.freeze = false
	prop.sleeping = false
	direction = direction.normalized()
	kick = clampf(kick, 0.1, 4.0)
	prop.apply_central_impulse(direction * prop.mass * kick
		+ Vector3.UP * prop.mass * kick * 0.85)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5),
		randf_range(-1.0, 1.0))
	prop.apply_torque_impulse(spin * prop.mass * 1.6)
	_prop_kick_until[prop.get_instance_id()] = Time.get_ticks_msec() + 400


func _expire_prop_kicks() -> void:
	if _prop_kick_until.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	for id: int in _prop_kick_until.keys():
		if now < int(_prop_kick_until[id]):
			continue
		_prop_kick_until.erase(id)
		var prop: RigidBody3D = instance_from_id(id) as RigidBody3D
		if is_instance_valid(prop):
			prop.freeze = true


@rpc("any_peer", "reliable")
func _net_request_push(index: int, direction: Vector3, kick: float) -> void:
	if not _is_host or index < 0 or index >= _crates.size():
		return
	if not direction.is_finite() or not is_finite(kick):
		return
	if direction.length_squared() < 0.0001:
		return
	var sender: int = _rpc_sender()
	var now: int = Time.get_ticks_msec()
	if now - int(_push_stamp.get(sender, -10000)) < 100:
		return
	_push_stamp[sender] = now
	_kick_prop(_crates[index], direction, kick)


@rpc("any_peer", "reliable")
func _net_cargo_ready(theme_id: String, vehicle_id: String) -> void:
	var sender: int = _rpc_sender()
	if sender <= 1 or sender == multiplayer.get_unique_id() or not _is_host:
		return
	if vehicle_id.length() > 64:
		return
	Network.mark_peer_scene_ready(sender)
	_spawn_remote_cart(sender)
	rpc_id(sender, "_net_cargo_config", _theme_id, _bots.size())
	if _phase == Phase.FINISHED:
		# A peer that loaded after the whistle still gets the result card.
		rpc_id(sender, "_net_match_end", _score[0], _score[1], _winner())
	rpc_id(sender, "_net_cargo_state", _clock_seconds(), _score[0], _score[1],
		_overtime, int(_phase))


@rpc("authority", "reliable")
func _net_cargo_config(theme_id: String, bot_count: int) -> void:
	if _is_host:
		return
	if not CargoTheme.ids().has(theme_id):
		return
	if theme_id != _theme_id:
		_theme_id = theme_id
		_theme = CargoTheme.get_theme(theme_id)
		_team_names = CargoTheme.team_names(_theme)
		_apply_theme()
		_refresh_theme_text()
		_refresh_team_texts()
		_refresh_score_now()
	_spawn_client_bots(clampi(bot_count, 0, BOT_MAX))


func _spawn_client_bots(count: int) -> void:
	if count == _client_bots_wanted and _bots.size() == count:
		return
	for entry: Dictionary in _bots:
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart):
			cart.queue_free()
	_bots.clear()
	_client_bots_wanted = count
	for index in count:
		_spawn_bot(index, true)
	_rebuild_traffic()


func _broadcast_state() -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_cargo_state", _clock_seconds(), _score[0],
				_score[1], _overtime, int(_phase))


func _clock_seconds() -> float:
	return _overtime_remaining if _overtime else _remaining


@rpc("authority", "unreliable")
func _net_cargo_state(remaining: float, score_a: int, score_b: int,
		overtime: bool, phase: int) -> void:
	if _is_host or not _multiplayer:
		return
	if _phase == Phase.FINISHED:
		return
	if not is_finite(remaining) or remaining < 0.0 or remaining > 1000.0:
		return
	_score[0] = clampi(score_a, 0, 99)
	_score[1] = clampi(score_b, 0, 99)
	_remaining = remaining
	_overtime = overtime
	if _overtime:
		_overtime_remaining = remaining
	var incoming: int = clampi(phase, 0, 2)
	if incoming == int(Phase.RACING) and _phase == Phase.COUNTDOWN:
		_phase = Phase.RACING
		_countdown_label.visible = false
		_set_cart_active(true)
		_show_toast("SHOVE CRATES INTO YOUR PAD", 2.2)


func _broadcast_delivery(team: int) -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_cargo_delivery", team, _score[0], _score[1])


@rpc("authority", "reliable")
func _net_cargo_delivery(team: int, score_a: int, score_b: int) -> void:
	if _is_host or not _multiplayer or _phase == Phase.FINISHED:
		return
	if team < 0 or team >= TEAM_COUNT:
		return
	_score[0] = clampi(score_a, 0, 99)
	_score[1] = clampi(score_b, 0, 99)
	_show_toast("%s DELIVERS!" % _team_names[team], 1.5)
	_play_one_shot(DELIVERY_CHIME, -5.0, 1.08)
	_flash_pad(team)
	_refresh_score_now()


func _broadcast_match_end() -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_match_end", _score[0], _score[1], _winner())


@rpc("authority", "reliable")
func _net_match_end(score_a: int, score_b: int, winner: int) -> void:
	if _is_host or not _multiplayer:
		return
	if _phase == Phase.FINISHED:
		return
	_score[0] = clampi(score_a, 0, 99)
	_score[1] = clampi(score_b, 0, 99)
	_phase = Phase.FINISHED
	_set_cart_active(false)
	for entry: Dictionary in _bots:
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart):
			cart.set_ai_controls(0.0, 0.5, 0.0)
	_show_result()


func _broadcast_bot_states() -> void:
	if _bots.is_empty() or not _is_host:
		return
	var positions := PackedVector3Array()
	var yaws := PackedFloat32Array()
	var velocities := PackedVector3Array()
	for entry: Dictionary in _bots:
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart == null or not is_instance_valid(cart):
			positions.append(Vector3.ZERO)
			yaws.append(0.0)
			velocities.append(Vector3.ZERO)
			continue
		positions.append(cart.global_position)
		yaws.append(cart.rotation.y)
		velocities.append(cart.velocity.limit_length(60.0))
	var stamp: int = Time.get_ticks_msec()
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_bot_states", positions, yaws, velocities, stamp)


@rpc("authority", "unreliable")
func _net_bot_states(positions: PackedVector3Array, yaws: PackedFloat32Array,
		velocities: PackedVector3Array, sent_ms: int) -> void:
	if _is_host or not _multiplayer:
		return
	var count: int = mini(positions.size(), _bots.size())
	if yaws.size() < count or velocities.size() < count:
		return
	for index in count:
		var position: Vector3 = positions[index]
		if not position.is_finite() or not is_finite(yaws[index]) \
				or not velocities[index].is_finite():
			continue
		var cart: CartPlayer = _bots[index].get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart) and cart.remote_mode:
			cart.set_net_state(position, yaws[index], sent_ms, velocities[index])


# --------------------------------------------------------------------------
# navigation


func _on_play_again() -> void:
	if _multiplayer:
		return
	SceneLoader.go_to(SCENE_PATH, "CARGO RUSH", "90 SECOND SCRAMBLE")


func _on_back_to_lobby() -> void:
	if _multiplayer:
		Network.return_to_lobby_keep_session()
	else:
		SceneLoader.go_to(MINIGAMES_MENU, "MINIGAMES", "PICK AN EVENT")


func _on_main_menu() -> void:
	if Network.is_session_active():
		Network.leave()
	SceneLoader.go_to(MAIN_MENU, "MAIN MENU")


# --------------------------------------------------------------------------
# headless self-test


func _run_self_test() -> void:
	## Boots the real arena with 3 crates and 2 bots, pushes the crates toward
	## the player's pad and reports whether they moved and the score changed.
	## Run with CART_CARGO_SELFTEST=1; the scene quits itself when finished.
	_selftest_scores[0] = _score[0]
	_selftest_scores[1] = _score[1]
	_selftest_start = PackedVector3Array()
	for crate: RigidBody3D in _crates:
		_selftest_start.append(crate.global_position)
	_selftest_bot_start = PackedVector3Array()
	for entry: Dictionary in _bots:
		var bot: CartPlayer = entry.get("cart") as CartPlayer
		if bot != null and is_instance_valid(bot):
			_selftest_bot_start.append(bot.global_position)
	for _frame in 480:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
	var moved: bool = _selftest_max_move > 1.0
	var bots_moved: bool = _selftest_bot_move > 2.0
	var changed: bool = _score[0] + _score[1] > _selftest_scores[0] + _selftest_scores[1]
	var base_grip: float = _cart.surface_grip if _cart != null else -1.0
	var hazard_grip: float = -1.0
	if _cart != null and not _hazards.is_empty():
		var spot: Vector3 = _hazards[0].get("centre", Vector3.ZERO) as Vector3
		_cart.global_position = spot + Vector3.UP * 0.4
		_cart.velocity = Vector3.ZERO
		await get_tree().physics_frame
		await get_tree().physics_frame
		hazard_grip = _cart.surface_grip
	var report: String = "CARGO_SELFTEST crates=%d bots=%d moved=%s max_move=%.2f "
	report += "bots_moved=%s bot_move=%.2f bot_shoves=%d "
	report += "score_changed=%s score=%d-%d phase=%d"
	print(report % [_crates.size(), _bots.size(), str(moved),
		_selftest_max_move, str(bots_moved), _selftest_bot_move,
		_bot_shove_count, str(changed), _score[0], _score[1], int(_phase)])
	print("CARGO_SELFTEST theme=%s base_grip=%.2f hazard_grip=%.2f"
		% [_theme_id, base_grip, hazard_grip])
	get_tree().quit()


func _selftest_tick(delta: float) -> void:
	_selftest_elapsed += delta
	for index in _bots.size():
		var bot: CartPlayer = _bots[index].get("cart") as CartPlayer
		if bot == null or not is_instance_valid(bot) \
				or index >= _selftest_bot_start.size():
			continue
		_selftest_bot_move = maxf(_selftest_bot_move,
			_planar_distance(bot.global_position, _selftest_bot_start[index]))
	if _selftest_elapsed > 5.5:
		return
	for index in _crates.size():
		if _crate_respawn[index] > 0.0:
			continue
		var crate: RigidBody3D = _crates[index]
		if not is_instance_valid(crate):
			continue
		var start: Vector3 = _selftest_start[index] \
			if index < _selftest_start.size() else _crate_home[index]
		_selftest_max_move = maxf(_selftest_max_move,
			_planar_distance(crate.global_position, start))
		var direction: Vector3 = _pads[0] - crate.global_position
		direction.y = 0.0
		if direction.length_squared() < 0.01:
			continue
		direction = direction.normalized()
		if crate.linear_velocity.dot(direction) < 7.0:
			crate.apply_central_impulse(direction * crate.mass * 0.45)
