extends Node3D
## A solo 3-lap race on a closed circuit chosen from TrackDefs. Built at runtime
## from one closed Catmull-Rom spline.
##
## Pipeline:
##   preset -> spline -> road ribbon + curbs + invisible barrier walls + ground
##          -> start/finish line + four sector gates
##          -> map theme hook (res://scripts/minigames/maps/<id>_theme.gd)
##          -> physical AI rivals that drive the same vehicle as the player
##          -> lap/sector tracking, countdown, HUD badges and a candy result card
##
## The kart, chase camera, boost, drift, HUD and pause menu are the same ones
## the sandbox uses. Nothing here touches multiplayer.

const TrackSpline := preload("res://scripts/minigames/track_spline.gd")
const KenneyTiles := preload("res://scripts/minigames/tiles/kenney_tiles.gd")
const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const RaceAI := preload("res://scripts/minigames/race_ai.gd")
const CART_SCENE := preload("res://scenes/player/cart_player.tscn")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const FoliageBaker := preload("res://scripts/minigames/foliage_baker.gd")
const RaceScenery := preload("res://scripts/minigames/race_scenery.gd")
const MeadowLandmarks := preload("res://scripts/minigames/meadow_landmarks.gd")
const RaceEffects := preload("res://scripts/minigames/race_effects.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const ResultScreen := preload("res://scripts/ui/result_screen.gd")
const ART_BACKDROP := preload("res://scripts/ui/art_backdrop.gd")
const VisualGrade := preload("res://scripts/systems/visual_grade.gd")
const Backdrop := preload("res://scripts/systems/backdrop.gd")
const OUTLINE_SHADER := preload("res://assets/materials/toon_outline.gdshader")
const UI_THEME := preload("res://assets/ui/theme.tres")

const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const LOBBY_SCENE: String = "res://scenes/minigames/meadow_lobby.tscn"
const MINIGAMES_MENU: String = "res://scenes/ui/minigames_menu.tscn"
const MAIN_MENU: String = "res://scenes/ui/main_menu.tscn"
const PBR_SHADER: String = "res://assets/materials/ground_pbr.gdshader"
const PBR_TEX: String = "res://assets/textures/polyhaven/"
const BOOST_PAD_SCENE: String = "res://scenes/track/boost_pad.tscn"
const CONE_MODEL: String = "res://assets/models/kenney_car-kit/Models/GLB format/cone.glb"
const CHECKER_SHADER: String = "res://assets/materials/checker.gdshader"
const CHECKER_FLAG: String = "res://scripts/ui/checker_flag.gd"
const THEME: String = "res://assets/ui/theme.tres"
const TITLE_FONT: String = "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"
const KART_ROOT: String = "res://assets/models/kenney_car-kit/Models/GLB format/"
const COUNTDOWN_BEEP: AudioStream = preload("res://assets/audio/sfx/race/countdown_beep.wav")
const COUNTDOWN_GO: AudioStream = preload("res://assets/audio/sfx/race/countdown_go.wav")
const LAP_CHIME: AudioStream = preload("res://assets/audio/sfx/race/lap_chime.wav")
const FINISH_FANFARE: AudioStream = preload("res://assets/audio/sfx/race/finish_fanfare.wav")
const FOREST_AMBIENCE: AudioStream = preload("res://assets/audio/ambience/forest_ambience.mp3")
const NET_SYNC_INTERVAL: float = 0.05
const CART_IDLE_SPEED: float = 1.0
const CART_IDLE_INTERVAL: float = 0.20
## Host-authoritative final standings. The host owns the only canonical
## finishing order; it re-broadcasts a revisioned reliable snapshot at this
## cadence while results are live, and force-finalises after the settle
## deadline so a lost packet or a stalled racer can never freeze the result
## card on "WAITING FOR ...".
const STANDINGS_BROADCAST_INTERVAL: float = 1.0
const STANDINGS_FINALIZE_TIMEOUT: float = 12.0
## Close-finish ordering (WS5-02). The reliable finish report is the single
## authoritative source for a human's crossing; the 20 Hz *unreliable* progress
## stream only latches a provisional fallback, because packet arrival through a
## relay can jitter by more than the gap between two close finishes. The report
## carries the peer's own race clock, which starts one countdown-broadcast
## delay after the host's clock, so the host re-aligns it with half the measured
## RTT. The clamps below bound a modified client's ability to claim any time it
## likes: a report may only slightly beat the host's observed crossing.
const FINISH_PROGRESS_SLACK: float = 0.6 ## s a report may beat/lag the progress latch
const FINISH_REPORT_SLACK: float = 2.0 ## s a reliable report may trail the crossing
const FINISH_ONE_WAY_MAX: float = 1.0 ## s cap on the RTT/2 clock re-alignment
const StandingsReconciler := preload("res://scripts/net/standings_reconciler.gd")
## Host -> Pi live position batch cadence (server race only).
const STATE_STREAM_INTERVAL: float = 0.10
## A spoofed far-future sender stamp must not permanently freeze a peer's
## progress and leave every result card waiting forever. A huge backwards jump
## is treated as a clock reset and re-baselined.
const NET_CLOCK_RESET_MS: int = 60_000
## A server race streams the Pi's bot field at 6-12 Hz. Each poll stores a
## target; the ghost is moved every physics frame, so corners and ramp heights
## glide in instead of the body teleporting on every sample.
const SERVER_BOT_BLEND: float = 12.0
const SERVER_BOT_VERTICAL_BLEND: float = 24.0
## A snapshot is extrapolated with the server's velocity for at most this long,
## so a stalled poll parks the ghost instead of launching it down the track.
const SERVER_BOT_MAX_EXTRAPOLATION: float = 0.35
## A correction larger than this is a respawn or a warp, not network jitter.
const SERVER_BOT_SNAP_DISTANCE: float = 8.0

## A landing only puffs tyre smoke when it is a real hit: enough air time to
## leave the ground and enough downward speed to matter.
const LANDING_SMOKE_MIN_AIR: float = 0.24
const LANDING_SMOKE_MIN_FALL: float = 6.5
## Forward speed lost in one step at the road edge that counts as a barrier hit.
const BARRIER_HIT_SPEED_LOSS: float = 9.0

const TOTAL_LAPS: int = 3
var _total_laps: int = TOTAL_LAPS
const ROAD_HALF: float = 5.5
const ROAD_Y: float = 0.04
const CURB_WIDTH: float = 0.8
const BARRIER_OFFSET: float = 0.5
const BARRIER_HEIGHT: float = 2.4
const START_DISTANCE: float = 8.0
const FIELD_X: float = 200.0
const FIELD_Z: float = 170.0
const GROUND_X: float = 2400.0
const GROUND_Z: float = 2400.0
const GRID_CELL: float = 16.0
const ROAD_STEP: float = 1.5

const TREES: PackedStringArray = [
	"tree_default", "tree_default_dark", "tree_default_fall",
	"tree_oak", "tree_oak_dark", "tree_oak_fall",
	"tree_cone", "tree_cone_dark", "tree_cone_fall",
	"tree_fat", "tree_fat_darkh", "tree_fat_fall",
	"tree_tall", "tree_tall_dark", "tree_tall_fall",
	"tree_thin", "tree_thin_dark", "tree_thin_fall",
	"tree_simple", "tree_simple_dark", "tree_detailed", "tree_detailed_dark",
	"tree_small", "tree_small_dark", "tree_small_fall",
	"tree_pineTallA", "tree_pineTallB", "tree_pineTallC", "tree_pineTallD",
	"tree_pineRoundA", "tree_pineRoundB", "tree_pineRoundC", "tree_pineRoundE",
	"tree_pineSmallA", "tree_pineSmallB", "tree_pineSmallC",
	"tree_plateau", "tree_plateau_dark",
]
const BUSHES: PackedStringArray = [
	"plant_bush", "plant_bushDetailed", "plant_bushLarge", "plant_bushSmall",
	"plant_bushTriangle", "plant_bushLargeTriangle", "plant_flatShort", "plant_flatTall",
]
const GRASSES: PackedStringArray = ["grass", "grass_large", "grass_leafs", "grass_leafsLarge"]
const FLOWERS: PackedStringArray = [
	"flower_purpleA", "flower_purpleB", "flower_redA", "flower_redB",
	"flower_yellowA", "flower_yellowB",
]
const ROCKS: PackedStringArray = [
	"rock_largeA", "rock_largeB", "rock_largeC", "rock_smallA", "rock_smallB",
	"rock_smallC", "rock_smallFlatA", "rock_tallA", "stone_largeA", "stone_smallA",
]
const WOODLAND: PackedStringArray = [
	"stump_round", "stump_old", "stump_roundDetailed", "log", "log_large",
	"mushroom_red", "mushroom_tan", "mushroom_redGroup",
]

const RAMP_FRACTIONS: Array[float] = [0.315, 0.915]
const RAMP_WIDTH: float = 6.4
const RAMP_LENGTH: float = 6.0
const RAMP_HEIGHT: float = 1.90

const BOT_NAMES: PackedStringArray = [
	"SLOPPY", "CLANK", "BEEP", "POPPY", "TURBO", "RUSTY",
	"MUNCH", "WHEEZY", "BUCKET", "NOODLE", "CRUMB", "ZIPPY",
	"SQUEAK", "BONK", "PUDDING", "GIZMO",
]
const BOT_COLORS: Array[Color] = [
	Color("45b6f0"), Color("f26ca7"), Color("ffd22e"), Color("4fbf52"),
	Color("f2545b"), Color("38d6f0"), Color("b18cff"), Color("ff9f45"),
]

enum Phase { COUNTDOWN, RACING, FINISHED }

var _spline: RefCounted
var _use_grid: bool = false
var _road_half: float = ROAD_HALF
var _preset: Dictionary = {}
var _preset_id: String = TrackDefs.DEFAULT_ID
var _cart: CartPlayer
var _hud: Node
var _hud_time_accum: float = 0.0
var _hud_standings_accum: float = 0.0
var _hud_last_place: int = -1
var _hud_last_lap: int = -1
var _rival_tick_accum: float = 0.0
var _baked: Dictionary = {}
var _grid: Dictionary = {}
var _foliage_material: Material
var _rivals: Array[Dictionary] = []
## Reused cart list for rival avoidance; rebuilt only when a rival joins.
var _traffic: Array[CartPlayer] = []
## Solid trackside bodies (hay bales, apex tyre stacks) the race AI dodges.
var _trackside_solids: PackedVector3Array = PackedVector3Array()
## Local copies of the spline's centreline tables, used by the rivals' own
## nearest-point search. Sharing TrackSpline.closest()'s single cached index
## between five carts can return a boundary point a corner away, which used to
## freeze a rival's progress and even teleport the local player forward.
var _track_points: PackedVector3Array = PackedVector3Array()
var _track_cumulative: PackedFloat32Array = PackedFloat32Array()
var _track_total: float = 1.0
var _rival_nearest_distance: float = 0.0
var _rival_nearest_index: int = 0
var _scenery: RefCounted
var _scenery_stats: Dictionary = {}
var _effects: Node3D
## Start marshal: the pivot swings the flag arm, the flag spins on its pole.
var _marshal_pivot: Node3D
var _marshal_flag: Node3D
var _marshal_time: float = 0.0
## Pooled one-shot tyre-smoke puffs for hard landings.
var _smoke: Array[GPUParticles3D] = []
var _smoke_serial: int = 0
var _air_time: float = 0.0
var _fall_speed: float = 0.0
var _bend_materials: Array = []
var _start_lights: Array[MeshInstance3D] = []
var _gate_beams: Array[MeshInstance3D] = []
var _last_sector: int = 0
var _ramp_distances: Array[float] = []

var _phase: Phase = Phase.COUNTDOWN
var _countdown: float = 3.0
var _go_time: float = 0.0
var _last_count: int = 0
var _waiting_for_peers: bool = false
var _wait_elapsed: float = 0.0
var _client_ready_retry_timer: float = 0.0
var _go_shown: bool = false
var _race_time: float = 0.0
var _lap: int = 1
var _lap_start: float = 0.0
## Consecutive implausible crossings rejected by the min-lap guard. Capped so
## a heuristic can never block race progress forever (see _complete_lap).
var _rejected_crossings: int = 0
var _lap_times: Array[float] = []
var _unwrapped: float = START_DISTANCE
var _prev_s: float = START_DISTANCE
var _sector_flags: int = 1
var _skip_progress: bool = true
var _last_cart_pos: Vector3 = Vector3.ZERO
var _off_timer: float = 0.0
var _was_off_track: bool = false
## Unwrapped race time when the local cart crossed the line, -1 while racing.
## Placements compare this instead of the leftover metres of an overshooting
## progress value, so an earlier finisher is never passed by a later one.
var _finish_time: float = -1.0
## Peer id -> host-clock race time at which that peer's progress first reached
## the finish line. This is an arrival-jittered *fallback* only: the reliable
## _net_report_finish replaces it with the authoritative crossing stamp.
var _remote_finish_provisional: Dictionary = {}
## Peer id -> authoritative host-clock crossing time, from the reliable finish
## report (or the provisional fallback until that report lands).
var _remote_finish_time: Dictionary = {}
## Host-authoritative final standings (see STANDINGS_* above). The snapshot is
## the single source of truth for places once it arrives; every client renders
## it instead of its own guess, so all result cards agree.
var _standings_snapshot: Dictionary = {}
var _standings_rev: int = 0
var _standings_epoch: int = 0
var _standings_timer: float = 0.0
var _standings_wait: float = 0.0
var _standings_finalized: bool = false
var _finish_reported: bool = false
## Sentinel: reliable finish report from each peer (total + best lap).
var _peer_result_extra: Dictionary = {}
## The Pi's official result owns the big placement once it lands; the local
## 2 Hz standings refresh must not overwrite it.
var _official_applied: bool = false
## Absolute progress of the local grid slot (solo START_DISTANCE, MP grid row),
## used to re-base the race cleanly on a second countdown.
var _start_s: float = START_DISTANCE
var _barrier_cooldown: float = 0.0
var _last_forward_speed: float = 0.0
var _base_max_speed: float = 19.0
var _saved_vehicle: String = ""
var _toast_timer: float = 0.0
var _multiplayer: bool = false
var _is_host: bool = false
var _remote_carts: Dictionary = {}
var _peer_vehicles: Dictionary = {}
var _race_vehicle: String = "" ## The host's car - everyone drives it in a race.
var _name_labels: Dictionary = {}
var _remote_progress: Dictionary = {}
var _remote_progress_ms: Dictionary = {} ## peer id -> newest accepted stamp
var _net_sync_timer: float = 0.0
var _cart_idle_ms: Dictionary = {}
var _cart_idle_pos: Dictionary = {}
var _cart_idle_yaw: Dictionary = {}
var _bot_idle_ms: int = -100000
var _state_stream_timer: float = 0.0
## Server-authoritative race (Pi 1.6.0+): clock, official times, bot field.
var _server_race_active: bool = false
## Whether the Pi clock was usable when this race started. A client that could
## not sync must still get a drivable race, so it falls back to its own clock.
var _server_clock_ok: bool = false
var _server_race_id: String = ""
var _server_race_secret: String = ""
var _server_start_ms: int = 0
var _server_race_pending: bool = false
var _server_bots_timer: float = 0.0
var _server_bots_pending: bool = false
var _server_official: Dictionary = {}
var _server_finished_reported: bool = false
var _bot_sync_timer: float = 0.0
var _horn_stamp: Dictionary = {}
var _race_relay_ms: Dictionary = {}
## Host-authoritative race props: the host simulates cones and broadcasts
## snapshots; clients freeze their copy and ask the host to apply pushes.
var _props: Array[RigidBody3D] = []
var _prop_targets: Dictionary = {}
var _prop_sync_timer: float = 0.0
var _push_stamp: Dictionary = {}
## Client-side prediction: a pushed frozen prop is unfrozen briefly so the
## player sees it fly immediately instead of driving through it.
var _prop_kick_until: Dictionary = {}
var _prop_serial: int = 0
const PROP_SYNC_INTERVAL: float = 0.10

var _canvas: CanvasLayer
var _countdown_label: Label
var _callout_label: Label
var _callout_timer: float = 0.0
var _wrong_way_label: Label
var _wrong_way_timer: float = 0.0
var _wrong_way_active: bool = false
var _wrong_way_flash: float = 0.0
var _toast_label: Label
var _offtrack_label: Label
var _impact_label: Label
var _impact_timer: float = 0.0
var _result_root: Control
var _result_ui ## Scripts/ui/result_screen.gd builder for the shared card layout.
var _result_card: Dictionary = {}
var _result_title: Label
var _result_subtitle: Label
var _result_total: Label
var _result_best: Label
var _result_place: Label
var _result_laps: Label
var _result_lap_rows: VBoxContainer
var _result_standings_section: VBoxContainer
var _result_wait_banner: PanelContainer
var _result_wait_label: Label
var _result_wait_style: StyleBoxFlat
var _result_done_style: StyleBoxFlat
var _result_standings_rows: VBoxContainer
var _result_standings_cache: Dictionary = {}
var _result_row_style: StyleBoxFlat
var _result_local_row_style: StyleBoxFlat
var _result_refresh_timer: float = 0.0
var _ambient_audio: AudioStreamPlayer


# --------------------------------------------------------------------------
# lifecycle



func _rpc_sender() -> int:
	## RPCs can still be queued when a peer is tearing down; never dereference
	## a null multiplayer peer.
	return multiplayer.get_remote_sender_id() if multiplayer.multiplayer_peer != null else 0

func _enter_tree() -> void:
	# CartPlayer reads GameSettings.selected_vehicle in its own _ready, which
	# runs before this node's _ready. Swap in the effective racing vehicle here
	# (honoring PICK OWN vs SHARED in multiplayer) and put sandbox back on exit.
	_saved_vehicle = GameSettings.selected_vehicle
	if Network.is_session_active() and multiplayer.multiplayer_peer != null:
		GameSettings.selected_vehicle = Network.effective_vehicle_for(multiplayer.get_unique_id(), "racing")
	else:
		GameSettings.selected_vehicle = GameSettings.minigame_vehicle


func _exit_tree() -> void:
	GameSettings.selected_vehicle = _saved_vehicle


## WS5P3-04: the room ended while this scene was streaming. Never start a
## silent offline race; return to the lobby with the disconnect notice instead.
func _abort_stale_session_load() -> void:
	SceneLoader.go_to(Network.LOBBY_SCENE, "SESSION ENDED",
		"The room ended before the match could start.",
		SceneLoader.network_priority())


func _ready() -> void:
	# WS5P3-04 guard: only an authoritative (network-priority) load can be
	# stale-session; a solo start is never cancelled by this check.
	if SceneLoader.active_priority() > 0 \
			and Network.consume_session_ended_during_load():
		call_deferred("_abort_stale_session_load")
		return
	# Decide the session type before building the map: in a session the host's
	# Network session map decides the layout for every peer.
	_multiplayer = Network.is_session_active()
	_is_host = Network.is_host
	# Same epoch on every peer: the replicated race seed. It only has to change
	# between races inside one scene instance, which a reload never reuses.
	_standings_epoch = Network.race_seed
	# In a session both peers build the host's session map, so the host and
	# every client race the same layout. Solo uses the local map pick.
	var map_id: String = GameSettings.selected_map
	if _multiplayer and Network.session_map_id != "":
		map_id = Network.session_map_id
	_preset = TrackDefs.get_preset(map_id)
	_preset_id = str(_preset.get("id", TrackDefs.DEFAULT_ID))
	# Cartoon maps are Kenney tile grids: the engine builds the road, its
	# colliders and returns the centreline the race, AI and server contracts use.
	# Older free-form presets still fall back to the spline builder.
	var grid_rows: PackedStringArray = TrackDefs.grid_of(_preset)
	if grid_rows.size() > 0:
		var theme_dict: Dictionary = {"id": TrackDefs.theme_id_of(_preset)}
		var height_rows: PackedStringArray = TrackDefs.heights_of(_preset)
		if height_rows.size() > 0:
			theme_dict["heights"] = height_rows
		_spline = KenneyTiles.build(self, grid_rows, theme_dict)
		_use_grid = _spline != null
		_road_half = KenneyTiles.ROAD_HALF if _use_grid else ROAD_HALF
	else:
		_spline = TrackSpline.new(_preset)
		_use_grid = false
		_road_half = ROAD_HALF
	_track_points = _spline.points
	_track_cumulative = _spline.cumulative
	_track_total = maxf(_spline.total_length, 1.0)
	var test_laps: String = OS.get_environment("CART_TEST_LAPS")
	if test_laps.is_valid_int():
		_total_laps = clampi(test_laps.to_int(), 1, 9)
	CursorController.set_menu_mode(false)
	_upgrade_graphics()

	_cart = get_tree().get_first_node_in_group("player") as CartPlayer
	_hud = $HUD
	# The result card is built below, so the session type decides its buttons.
	if _cart != null:
		_base_max_speed = _cart.max_speed
		_last_cart_pos = _cart.global_position
		_cart.surface_grip = _surface_grip_for(START_DISTANCE)

	_build_ground()
	if not _use_grid:
		_build_track()
		_build_barriers()
		_build_start_line()
		_build_gates()
	_build_start_lights()
	_build_marshal()
	_build_boost_pads()
	if not _use_grid:
		_build_ramps()
		_build_trackside_props()
	# The meadow forest, horizon, grandstands and signs are map theme content
	# now. The hook does nothing when this map has no theme yet.
	_build_theme()
	_build_rivals()
	_build_overlay()
	_build_tyre_smoke()
	_start_ambience()

	if _cart != null:
		var spawn: Transform3D = _track_transform(START_DISTANCE)
		_cart.set_spawn_transform(spawn)
		_cart.global_transform = spawn
		_cart.velocity = Vector3.ZERO
		_cart.set_physics_process(false)
		_effects = RaceEffects.new()
		_effects.name = "RaceEffects"
		add_child(_effects)
		_effects.call("setup", _cart)
		if not _cart.horn_requested.is_connected(_on_horn_requested):
			_cart.horn_requested.connect(_on_horn_requested)
		if _multiplayer:
			_setup_multiplayer()
			_waiting_for_peers = true
			_wait_elapsed = 0.0
			_countdown_label.text = "WAITING"

	_hud.call("set_lap", 1, _total_laps)
	_hud.call("set_race_position", 1, _field_size())
	_hud.call("set_race_time", 0.0, -1.0)
	if not _waiting_for_peers:
		_countdown_label.text = "3"
		_toast("%s  ·  3 LAPS" % _race_title(), 2.2)


func _upgrade_graphics() -> void:
	# The race keeps 2x MSAA plus FXAA; sky, sun, fog and post come from the
	# shared VisualGrade so every map stays visually consistent.
	var viewport: Viewport = get_viewport()
	if viewport != null:
		# 2x MSAA plus FXAA antialiases the alpha-scissor foliage that MSAA
		# alone cannot touch, at a fraction of 4x MSAA's bandwidth.
		viewport.msaa_3d = Viewport.MSAA_2X
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	VisualGrade.apply($WorldEnvironment, "race")
	VisualGrade.apply_sun($Sun)


func _race_title() -> String:
	return str(_preset.get("name", "RACE"))


func _build_theme() -> void:
	## Map-specific scenery lives in res://scripts/minigames/maps/<id>_theme.gd.
	## The theme owns the meadow forest, the dockyard apron and the snow fields;
	## a map without a theme simply runs the shared track and props.
	var path: String = "res://scripts/minigames/maps/%s_theme.gd" % _preset_id
	if not ResourceLoader.exists(path):
		return
	var theme_script: Script = load(path) as Script
	if theme_script == null:
		return
	if theme_script.has_method("build"):
		theme_script.call("build", self, _spline)


func _surface_grip_for(distance: float) -> float:
	## Grip multiplier at an arc-length position, sampled from the map data.
	var total: float = maxf(_spline.total_length, 0.001)
	return TrackDefs.grip_at(_preset, distance / total)


func _update_surface_grip(player_s: float) -> void:
	## Every physical cart samples its own part of the track, so a rival can be
	## on the wet section while the player is still on dry asphalt. A ghost does
	## not need it, but writing the field is harmless and keeps remote code paths
	## identical if they ever gain physics.
	if _cart != null:
		_cart.surface_grip = _surface_grip_for(player_s)
	for rival: Dictionary in _rivals:
		var node: CartPlayer = rival["node"]
		if is_instance_valid(node):
			node.surface_grip = _surface_grip_for(float(rival.get("prev_s", 0.0)))


func _track_transform(distance: float, lateral: float = 0.0, height: float = 0.2) -> Transform3D:
	var frame: Dictionary = _spline.sample(distance)
	var base_y: float = KenneyTiles.ROAD_SURFACE if _use_grid else 0.0
	var position: Vector3 = frame["position"] + frame["right"] * lateral + Vector3.UP * (base_y + height)
	return Transform3D(Basis(Vector3.UP, _spline.yaw_at(distance)), position)


# --------------------------------------------------------------------------
# world


func _build_ground() -> void:
	if not _use_grid:
		var plane := PlaneMesh.new()
		plane.size = Vector2(GROUND_X, GROUND_Z)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "MeadowGround"
		mesh_instance.mesh = plane
		mesh_instance.material_override = _pbr_material(
			"grass_diff", "grass_nor", "grass_rough", GROUND_X / 10.0,
			Color(0.72, 0.88, 0.65), 0.10, 0.05)
		add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(GROUND_X, 2.0, GROUND_Z)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(collision)
	add_child(body)


func _build_hills() -> void:
	## Layered ridges, cliffs and peaks replace the old row of half-buried
	## spheres, which read as "semicircle hills" from the chase camera.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7713
	RaceScenery.new().build_horizon(self)
	# Far peaks, rural landmarks and woodland push the horizon out in layers.
	Backdrop.add_mountains(self, rng, 14)
	Backdrop.add_clouds(self, rng, 18)
	MeadowLandmarks.build(self, _spline)


func _pbr_material(diff: String, nor: String, rough: String, uv_scale: float,
		tint: Color, detail: float, macro: float, tracks: float = 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(PBR_SHADER) as Shader
	mat.set_shader_parameter("albedo_tex", load(PBR_TEX + diff + ".jpg"))
	mat.set_shader_parameter("normal_tex", load(PBR_TEX + nor + ".jpg"))
	mat.set_shader_parameter("rough_tex", load(PBR_TEX + rough + ".jpg"))
	mat.set_shader_parameter("uv_scale", uv_scale)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("detail_strength", detail)
	mat.set_shader_parameter("macro_variation", macro)
	mat.set_shader_parameter("roughness_min", 0.55)
	if tracks > 0.0:
		mat.set_shader_parameter("track_strength", tracks)
	return mat


func _build_track() -> void:
	var steps: int = int(ceil(_spline.total_length / ROAD_STEP))

	# Dirt road ribbon. V is arc length / 5 m so the texture tiles along it.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var road_faces := PackedVector3Array()
	for i in steps + 1:
		var s: float = float(i) / float(steps) * _spline.total_length
		var frame: Dictionary = _spline.sample(s)
		var centre: Vector3 = frame["position"]
		var right: Vector3 = frame["right"]
		var lift := Vector3.UP * ROAD_Y
		verts.append(centre - right * ROAD_HALF + lift)
		verts.append(centre + right * ROAD_HALF + lift)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		var v: float = s / 5.0
		uvs.append(Vector2(0.0, v))
		uvs.append(Vector2(1.0, v))
	for i in steps:
		var a: int = i * 2
		# Front faces must point up: with cull_disabled a reversed winding makes
		# Godot flip the normal for the back face and the whole road goes dark.
		indices.append(a)
		indices.append(a + 2)
		indices.append(a + 1)
		indices.append(a + 1)
		indices.append(a + 2)
		indices.append(a + 3)
		# The same triangles double as the road's physical surface so the wheels
		# rest on the visible dirt (not 4 cm lower on the ground box) and the
		# skid-mark raycasts land on the road instead of under it.
		road_faces.append_array([
			verts[a], verts[a + 2], verts[a + 1],
			verts[a + 1], verts[a + 2], verts[a + 3],
		])

	var road := ArrayMesh.new()
	road.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_make_arrays(verts, norms, uvs, PackedColorArray(), indices))
	var road_mesh := MeshInstance3D.new()
	road_mesh.name = "DirtTrack"
	road_mesh.mesh = road
	road_mesh.material_override = _pbr_material(
		"dirt_diff", "dirt_nor", "dirt_rough", 1.0,
		Color(0.84, 0.80, 0.68), 0.13, 0.025, 0.16)
	add_child(road_mesh)

	# Physical road surface: the kart drives on the dirt it sees. Without this
	# body the wheels rest on the ground box 4 cm lower and every skid mark is
	# painted underneath the road texture where nobody can see it.
	var road_body := StaticBody3D.new()
	road_body.name = "RoadCollision"
	road_body.collision_layer = 1
	road_body.collision_mask = 0
	var road_shape := ConcavePolygonShape3D.new()
	road_shape.set_faces(road_faces)
	var road_collision := CollisionShape3D.new()
	road_collision.shape = road_shape
	road_body.add_child(road_collision)
	add_child(road_body)

	# Alternating red/white curbs, baked as vertex colours (one draw call).
	var curb_verts := PackedVector3Array()
	var curb_norms := PackedVector3Array()
	var curb_colors := PackedColorArray()
	var red := UiPalette.RED
	var white := Color("fff6e3")
	for i in steps:
		var s0: float = float(i) / float(steps) * _spline.total_length
		var s1: float = float(i + 1) / float(steps) * _spline.total_length
		var f0: Dictionary = _spline.sample(s0)
		var f1: Dictionary = _spline.sample(s1)
		var shade: Color = red if int(s0 / 3.0) % 2 == 0 else white
		for side in [-1.0, 1.0]:
			var inner0: Vector3 = f0["position"] + f0["right"] * (ROAD_HALF * side) + Vector3.UP * (ROAD_Y + 0.008)
			var outer0: Vector3 = f0["position"] + f0["right"] * ((ROAD_HALF + CURB_WIDTH) * side) + Vector3.UP * (ROAD_Y + 0.008)
			var inner1: Vector3 = f1["position"] + f1["right"] * (ROAD_HALF * side) + Vector3.UP * (ROAD_Y + 0.008)
			var outer1: Vector3 = f1["position"] + f1["right"] * ((ROAD_HALF + CURB_WIDTH) * side) + Vector3.UP * (ROAD_Y + 0.008)
			_append_quad(curb_verts, curb_norms, curb_colors,
				inner0, outer0, outer1, inner1, shade)

	var curbs := ArrayMesh.new()
	curbs.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_make_arrays(curb_verts, curb_norms, PackedVector2Array(), curb_colors, PackedInt32Array()))
	var curb_mesh := MeshInstance3D.new()
	curb_mesh.name = "CandyCurbs"
	curb_mesh.mesh = curbs
	var curb_mat := StandardMaterial3D.new()
	curb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	curb_mat.vertex_color_use_as_albedo = true
	curb_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	curb_mesh.material_override = curb_mat
	add_child(curb_mesh)


func _make_arrays(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, colors: PackedColorArray,
		indices: PackedInt32Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	if not indices.is_empty():
		arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _append_quad(verts: PackedVector3Array, norms: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, color: Color) -> void:
	for vertex: Vector3 in [a, b, c, a, c, d]:
		verts.append(vertex)
		norms.append(Vector3.UP)
		colors.append(color)


func _build_barriers() -> void:
	# An invisible trimesh wall just outside each curb keeps the kart on the
	# winding ribbon. One static body for the whole loop.
	var steps: int = int(ceil(_spline.total_length / (ROAD_STEP * 2.0)))
	var faces := PackedVector3Array()
	for i in steps:
		var s0: float = float(i) / float(steps) * _spline.total_length
		var s1: float = float(i + 1) / float(steps) * _spline.total_length
		var f0: Dictionary = _spline.sample(s0)
		var f1: Dictionary = _spline.sample(s1)
		for side in [-1.0, 1.0]:
			var offset: float = (ROAD_HALF + BARRIER_OFFSET) * side
			var a: Vector3 = f0["position"] + f0["right"] * offset
			var b: Vector3 = f1["position"] + f1["right"] * offset
			var a_top: Vector3 = a + Vector3.UP * BARRIER_HEIGHT
			var b_top: Vector3 = b + Vector3.UP * BARRIER_HEIGHT
			faces.append(a)
			faces.append(a_top)
			faces.append(b)
			faces.append(b)
			faces.append(a_top)
			faces.append(b_top)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "TrackBarriers"
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _build_start_line() -> void:
	var f: Dictionary = _spline.sample(0.0)
	var p: Vector3 = f["position"]
	var r: Vector3 = f["right"]
	var fw: Vector3 = f["forward"]
	var lift := Vector3.UP * (ROAD_Y + 0.02)
	var a := p - r * ROAD_HALF - fw * 0.9 + lift
	var b := p + r * ROAD_HALF - fw * 0.9 + lift
	var c := p + r * ROAD_HALF + fw * 0.9 + lift
	var d := p - r * ROAD_HALF + fw * 0.9 + lift
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for v: Vector3 in [a, b, c, a, c, d]:
		verts.append(v)
		norms.append(Vector3.UP)
	for uv: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1),
			Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
		uvs.append(uv)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_make_arrays(verts, norms, uvs, PackedColorArray(), PackedInt32Array()))
	var line := MeshInstance3D.new()
	line.name = "StartFinishLine"
	line.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load(CHECKER_SHADER) as Shader
	mat.set_shader_parameter("cells", Vector2(14.0, 2.0))
	line.material_override = mat
	add_child(line)


func _build_gates() -> void:
	_build_gate(0.0, "START / FINISH", UiPalette.YELLOW, true)
	# The three split gates are the track's zones: each one keeps its colour and
	# carries a readable ZONE label, so a player always knows which quarter of
	# the lap they are on even when the HUD is in a corner.
	var quarter: float = _spline.total_length / 4.0
	_build_gate(quarter, "ZONE 1", UiPalette.CYAN, false)
	_build_gate(quarter * 2.0, "ZONE 2", UiPalette.PINK, false)
	_build_gate(quarter * 3.0, "ZONE 3", UiPalette.BLUE, false)


func _build_gate(distance: float, caption: String, color: Color, finish: bool) -> void:
	var gate := Node3D.new()
	gate.name = "Gate_" + caption.replace(" ", "_").replace("/", "-")
	gate.transform = _track_transform(distance, 0.0, 0.0)
	add_child(gate)

	var post_height: float = 5.2
	var span: float = ROAD_HALF + 1.1
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = UiPalette.OUTLINE
	post_mat.roughness = 1.0
	post_mat.next_pass = _outline_material(0.05)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(0.15, 0.18, 0.22)
	beam_mat.roughness = 0.82
	beam_mat.next_pass = _outline_material(0.035)

	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.55, post_height, 0.55)
		post.mesh = box
		post.position = Vector3(side * span, post_height * 0.5, 0.0)
		post.material_override = post_mat
		gate.add_child(post)

	var beam := MeshInstance3D.new()
	var beam_box := BoxMesh.new()
	beam_box.size = Vector3(span * 2.0 + 0.55, 0.95, 0.6)
	beam.mesh = beam_box
	beam.position = Vector3(0.0, post_height, 0.0)
	beam.material_override = beam_mat
	gate.add_child(beam)
	_gate_beams.append(beam)
	var accent := MeshInstance3D.new()
	var accent_box := BoxMesh.new()
	accent_box.size = Vector3(span * 2.0 + 0.58, 0.16, 0.64)
	accent.mesh = accent_box
	accent.position = Vector3(0.0, post_height + 0.27, 0.0)
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = color
	accent_mat.roughness = 0.8
	accent.material_override = accent_mat
	gate.add_child(accent)

	if finish:
		# Checkered strip across the front of the finish beam.
		var strip := MeshInstance3D.new()
		var strip_box := BoxMesh.new()
		strip_box.size = Vector3(span * 2.0 + 0.55, 0.36, 0.66)
		strip.mesh = strip_box
		strip.position = Vector3(0.0, post_height - 0.6, 0.0)
		var checker := ShaderMaterial.new()
		checker.shader = load(CHECKER_SHADER) as Shader
		checker.set_shader_parameter("cells", Vector2(20.0, 1.0))
		strip.material_override = checker
		gate.add_child(strip)

	# Zone gates are read from their colour and flash, and a small label names
	# the quarter. It sits above the beam so it never crowds the road.
	var label := Label3D.new()
	label.text = caption
	label.font = load(TITLE_FONT)
	label.font_size = 64 if finish else 52
	label.pixel_size = 0.017 if finish else 0.0125
	label.outline_size = 18
	label.outline_modulate = UiPalette.OUTLINE
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, post_height + (1.0 if finish else 0.85), 0.0)
	gate.add_child(label)


func _outline_material(thickness: float) -> ShaderMaterial:
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE_SHADER
	outline.set_shader_parameter("thickness", thickness)
	return outline


func _build_start_lights() -> void:
	# One clean row of five lamps: one lamp per countdown beat, all five green
	# on GO. The old 2x5 F1 grid read as two confusing rows in a cartoon game.
	var distance: float = START_DISTANCE + 12.0
	var rig := Node3D.new()
	rig.name = "StartLights"
	rig.transform = _track_transform(distance, 0.0, 0.0)
	add_child(rig)
	var post_offset: float = (_road_half + 2.65) if _use_grid else (ROAD_HALF + 0.8)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.28, 5.8, 0.28)
		post.mesh = box
		post.position = Vector3(side * post_offset, 2.9, 0.0)
		var dark := StandardMaterial3D.new()
		dark.albedo_color = UiPalette.OUTLINE
		post.material_override = dark
		rig.add_child(post)
	var bar := MeshInstance3D.new()
	var bar_box := BoxMesh.new()
	bar_box.size = Vector3(post_offset * 2.0 + 0.3, 1.05, 0.3)
	bar.mesh = bar_box
	bar.position = Vector3(0.0, 5.48, 0.0)
	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.16, 0.18, 0.29, 1)
	bar.material_override = bar_mat
	rig.add_child(bar)
	for column in 5:
		var lamp := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.30
		sphere.height = 0.60
		lamp.mesh = sphere
		# +Z faces the approaching grid; the lamps sit on the near side of the
		# beam so the whole rig does not read as a blank black bar.
		lamp.position = Vector3((float(column) - 2.0) * 0.72, 5.48, 0.26)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.14, 0.22, 1)
		mat.emission_enabled = true
		mat.emission = Color(0.35, 0.06, 0.08, 1)
		mat.emission_energy_multiplier = 0.35
		lamp.material_override = mat
		rig.add_child(lamp)
		_start_lights.append(lamp)


func _set_start_lights(red_count: int, green: bool) -> void:
	for i in _start_lights.size():
		var mat: StandardMaterial3D = _start_lights[i].material_override as StandardMaterial3D
		if mat == null:
			continue
		var lit: bool = green or i < red_count
		mat.emission = Color(0.15, 0.95, 0.32, 1) if green \
			else (Color(1.0, 0.14, 0.16, 1) if lit else Color(0.35, 0.06, 0.08, 1))
		mat.emission_energy_multiplier = 3.2 if lit else 0.25
		mat.albedo_color = Color(0.1, 0.35, 0.14, 1) if green \
			else (Color(0.5, 0.1, 0.1, 1) if lit else Color(0.16, 0.14, 0.22, 1))


func _build_marshal() -> void:
	## A marshal on the outside of the grid waves the checkered flag through the
	## countdown and drops it on GO. The chase camera sits behind the kart, so
	## the figure reads even when the gantry lights are out of frame.
	var root := Node3D.new()
	root.name = "StartMarshal"
	# 7.4 m out sits between the race's invisible barrier (6 m) and the theme's
	# catch fence (~7.9 m), so the figure never clips a hoarding.
	root.transform = _track_transform(START_DISTANCE + 6.0,
		-(_road_half + 1.9), 0.0)
	add_child(root)

	var vest := StandardMaterial3D.new()
	vest.albedo_color = Color("ff8a3d")
	vest.roughness = 0.9
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("f2c39b")
	skin.roughness = 0.95
	var dark := StandardMaterial3D.new()
	dark.albedo_color = UiPalette.OUTLINE
	dark.roughness = 1.0

	var torso := MeshInstance3D.new()
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.28
	torso_mesh.height = 1.05
	torso.mesh = torso_mesh
	torso.position = Vector3(0.0, 0.85, 0.0)
	torso.material_override = vest
	root.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.19
	head_mesh.height = 0.38
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.53, 0.0)
	head.material_override = skin
	root.add_child(head)

	for side: float in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.16, 0.62, 0.18)
		leg.mesh = leg_mesh
		leg.position = Vector3(side * 0.12, 0.32, 0.0)
		leg.material_override = dark
		root.add_child(leg)

	_marshal_pivot = Node3D.new()
	_marshal_pivot.position = Vector3(0.26, 1.32, 0.0)
	_marshal_pivot.rotation.z = -0.35
	root.add_child(_marshal_pivot)

	var arm := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.12, 0.72, 0.12)
	arm.mesh = arm_mesh
	arm.position = Vector3(0.0, 0.34, 0.0)
	arm.material_override = vest
	_marshal_pivot.add_child(arm)

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.03
	pole_mesh.bottom_radius = 0.03
	pole_mesh.height = 1.25
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, 1.02, 0.0)
	pole.material_override = dark
	_marshal_pivot.add_child(pole)

	_marshal_flag = Node3D.new()
	_marshal_flag.position = Vector3(0.0, 1.62, 0.0)
	_marshal_pivot.add_child(_marshal_flag)
	var flag := MeshInstance3D.new()
	var flag_mesh := QuadMesh.new()
	flag_mesh.size = Vector2(0.95, 0.6)
	flag.mesh = flag_mesh
	flag.position = Vector3(0.48, 0.0, 0.0)
	var flag_mat := ShaderMaterial.new()
	flag_mat.shader = load(CHECKER_SHADER) as Shader
	flag_mat.set_shader_parameter("cells", Vector2(6.0, 4.0))
	flag.material_override = flag_mat
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marshal_flag.add_child(flag)


func _animate_marshal(delta: float) -> void:
	## Waved fast through the countdown, dropped once the race is live. A cheap
	## damped swing instead of a tween, so a paused or reset countdown keeps the
	## arm exactly where the state says it should be.
	if _marshal_pivot == null:
		return
	_marshal_time += delta
	var target: float = -1.25
	if _phase == Phase.COUNTDOWN:
		target = -0.35 + sin(_marshal_time * 8.0) * 0.35
	var blend: float = 1.0 - exp(-6.0 * delta)
	_marshal_pivot.rotation.z = lerpf(_marshal_pivot.rotation.z, target, blend)
	if _marshal_flag != null:
		_marshal_flag.rotation.y = sin(_marshal_time * 4.0) * 0.35


func _build_tyre_smoke() -> void:
	## A small pool of one-shot grey smoke puffs. A hard landing gets tyre smoke
	## instead of the shared warm dust burst, which reads as an impact rather
	## than as the speed dust already flowing off the rear wheels.
	for index in 3:
		var puff := GPUParticles3D.new()
		puff.name = "TyreSmoke%d" % index
		puff.amount = 18
		puff.lifetime = 1.05
		puff.one_shot = true
		puff.emitting = false
		puff.explosiveness = 0.92
		puff.local_coords = false
		puff.visibility_aabb = AABB(Vector3(-12, -3, -12), Vector3(24, 10, 24))
		var process_mat := ParticleProcessMaterial.new()
		process_mat.direction = Vector3(0.0, 1.0, 0.0)
		process_mat.spread = 70.0
		process_mat.gravity = Vector3(0.0, 1.1, 0.0)
		process_mat.initial_velocity_min = 0.8
		process_mat.initial_velocity_max = 2.4
		process_mat.scale_min = 0.7
		process_mat.scale_max = 1.7
		process_mat.lifetime_randomness = 0.35
		process_mat.color = Color(0.93, 0.93, 0.95, 1)
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([
			Color(0.95, 0.95, 0.97, 0.0), Color(0.92, 0.92, 0.95, 0.5),
			Color(0.86, 0.87, 0.90, 0.25), Color(0.86, 0.87, 0.90, 0.0)])
		var ramp_texture := GradientTexture1D.new()
		ramp_texture.gradient = ramp
		process_mat.color_ramp = ramp_texture
		puff.process_material = process_mat
		var quad := QuadMesh.new()
		quad.size = Vector2(0.5, 0.5)
		var quad_material := StandardMaterial3D.new()
		quad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		quad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		quad_material.billboard_keep_scale = true
		quad_material.vertex_color_use_as_albedo = true
		quad_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		quad_material.albedo_texture = load(
			"res://assets/textures/foliage/dust_puff.png")
		quad.material = quad_material
		puff.draw_pass_1 = quad
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(puff)
		_smoke.append(puff)


func _update_landing_smoke(delta: float) -> void:
	if _cart == null:
		return
	if not _cart.is_on_floor():
		_air_time += delta
		_fall_speed = maxf(_fall_speed, -_cart.velocity.y)
		return
	if _air_time >= LANDING_SMOKE_MIN_AIR \
			and _fall_speed >= LANDING_SMOKE_MIN_FALL:
		_puff_tyre_smoke()
	_air_time = 0.0
	_fall_speed = 0.0


func _puff_tyre_smoke() -> void:
	if _smoke.is_empty() or _cart == null:
		return
	var puff: GPUParticles3D = _smoke[_smoke_serial % _smoke.size()]
	_smoke_serial += 1
	var basis: Basis = _cart.global_transform.basis
	puff.global_position = _cart.global_position - basis.z * 0.65 \
		+ Vector3.UP * 0.10
	puff.restart()
	puff.emitting = true


func _build_start_festival() -> void:
	## The start is the identity shot: bunting, a hay-bale grandstand, a parked
	## tractor and a giant checkered flag. Everything sits outside the barriers,
	## so it is pure scenery and costs no lap collision.
	var root := Node3D.new()
	root.name = "StartFestival"
	root.transform = _track_transform(START_DISTANCE, 0.0, 0.0)
	add_child(root)

	var bunting := MeshInstance3D.new()
	bunting.name = "Bunting"
	bunting.mesh = _bunting_mesh(ROAD_HALF * 2.0 + 1.4, 18)
	var bunting_mat := StandardMaterial3D.new()
	bunting_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bunting_mat.vertex_color_use_as_albedo = true
	bunting_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bunting.material_override = bunting_mat
	bunting.position = Vector3(0.0, 5.1, 0.0)
	root.add_child(bunting)

	# Hay-bale grandstand, three stepped rows facing the grid.
	var hay_mat := StandardMaterial3D.new()
	hay_mat.albedo_color = Color(0.72, 0.57, 0.28)
	hay_mat.roughness = 0.95
	var hay_mesh := BoxMesh.new()
	hay_mesh.size = Vector3(1.25, 0.78, 1.7)
	var hay := MultiMesh.new()
	hay.transform_format = MultiMesh.TRANSFORM_3D
	hay.mesh = hay_mesh
	hay.instance_count = 12
	var hay_index: int = 0
	for row in 3:
		for col in 4:
			hay.set_instance_transform(hay_index, Transform3D(Basis.IDENTITY,
				Vector3(8.1 + float(row) * 1.32, 0.40 + float(row) * 0.80,
					-3.2 + float(col) * 1.76)))
			hay_index += 1
	var hay_instances := MultiMeshInstance3D.new()
	hay_instances.name = "HayGrandstand"
	hay_instances.multimesh = hay
	hay_instances.material_override = hay_mat
	root.add_child(hay_instances)

	# A real Kenney tractor grounds the farm theme without a custom model.
	var tractor_scene: PackedScene = load(
		"res://assets/models/kenney_car-kit/Models/GLB format/tractor.glb") as PackedScene
	if tractor_scene != null:
		var tractor: Node3D = tractor_scene.instantiate() as Node3D
		tractor.name = "ParkedTractor"
		tractor.position = Vector3(-9.6, 0.0, 3.4)
		tractor.rotation.y = 0.85
		tractor.scale = Vector3.ONE * 1.05
		root.add_child(tractor)

	# Giant checkered flag on the inside of the first corner.
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.07
	pole_mesh.bottom_radius = 0.09
	pole_mesh.height = 6.4
	pole_mesh.radial_segments = 10
	pole.mesh = pole_mesh
	pole.position = Vector3(-8.6, 3.2, -2.6)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.86, 0.84, 0.78)
	pole.material_override = pole_mat
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	var flag_mesh := QuadMesh.new()
	flag_mesh.size = Vector2(2.7, 1.65)
	flag.mesh = flag_mesh
	flag.position = Vector3(-7.25, 5.45, -2.6)
	flag.rotation.y = 0.18
	var flag_mat := ShaderMaterial.new()
	flag_mat.shader = load(CHECKER_SHADER) as Shader
	flag_mat.set_shader_parameter("cells", Vector2(8.0, 4.0))
	flag.material_override = flag_mat
	root.add_child(flag)


func _bunting_mesh(width: float, count: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var palette: Array[Color] = [UiPalette.YELLOW, UiPalette.CYAN,
		UiPalette.PINK, UiPalette.GRASS, UiPalette.CREAM]
	var span: float = width / float(count)
	for i in count:
		var x0: float = -width * 0.5 + span * float(i)
		var x1: float = x0 + span * 0.82
		var mid: float = (x0 + x1) * 0.5
		var sag: float = 0.42 * sin(PI * (float(i) + 0.5) / float(count))
		var base: int = verts.size()
		verts.append(Vector3(x0, 0.0, 0.0))
		verts.append(Vector3(x1, 0.0, 0.0))
		verts.append(Vector3(mid, -0.58 - sag, 0.0))
		for n in 3:
			normals.append(Vector3(0.0, 0.0, 1.0))
		var color: Color = palette[i % palette.size()]
		colors.append(color)
		colors.append(color)
		colors.append(color)
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _track_surface_transform(distance: float, lateral: float = 0.0,
		height: float = 0.02) -> Transform3D:
	var frame: Dictionary = _spline.sample(distance)
	var base_y: float = KenneyTiles.ROAD_SURFACE if _use_grid else 0.0
	var forward: Vector3 = (frame["forward"] as Vector3).normalized()
	var right: Vector3 = (frame["right"] as Vector3)
	right.y = 0.0
	right = right.normalized()
	var up: Vector3 = right.cross(forward).normalized()
	if up.y < 0.0:
		up = -up
	right = forward.cross(up).normalized()
	var basis := Basis(right, up, -forward)
	var pos: Vector3 = (frame["position"] as Vector3) + right * lateral + up * (base_y + height)
	return Transform3D(basis, pos)


func _build_boost_pads() -> void:
	var packed: PackedScene = load(BOOST_PAD_SCENE) as PackedScene
	if packed == null:
		return
	var holder := Node3D.new()
	holder.name = "BoostPads"
	add_child(holder)
	var laterals: Array[float] = [-2.0, 2.0, 0.0, -1.8, 1.8, 0.0]
	if _use_grid:
		var distances: PackedFloat32Array = _grid_boost_distances(6)
		for i in distances.size():
			var pad: Node3D = packed.instantiate() as Node3D
			pad.transform = _track_surface_transform(distances[i],
				laterals[i % laterals.size()], 0.025)
			if pad.has_method("set_pad_dimensions"):
				pad.call("set_pad_dimensions", 8.8, 5.8)
			holder.add_child(pad)
		return
	for i in 6:
		var distance: float = _spline.total_length * (0.12 + float(i) * 0.16)
		var lateral: float = laterals[i % laterals.size()]
		var pad: Node3D = packed.instantiate() as Node3D
		# The road surface is at y = 0.04; sit just above the surface.
		pad.transform = _track_surface_transform(distance, lateral, 0.075)
		if pad.has_method("set_pad_dimensions"):
			pad.call("set_pad_dimensions", 7.8, 5.2)
		holder.add_child(pad)


func _grid_boost_distances(target_count: int) -> PackedFloat32Array:
	## Pick evenly spaced straight cells (flat or smooth grade) on a Kenney
	## grid so boost pads align flush with the road deck and never land on a
	## jump ramp or bump.
	var picked := PackedFloat32Array()
	var candidates: PackedFloat32Array = PackedFloat32Array()
	var total: float = maxf(_spline.total_length, 1.0)
	var raw_tiles: Variant = _spline.get("tiles")
	if raw_tiles is Array:
		for entry: Variant in raw_tiles as Array:
			if not (entry is Dictionary):
				continue
			var tile: Dictionary = entry as Dictionary
			var kind: String = str(tile.get("tile", ""))
			if kind != "S" and kind != "P" and kind != "E" and kind != "G":
				continue
			if bool(tile.get("start", false)):
				continue
			var h_in: float = float(tile.get("height_in", 0.0))
			var h_out: float = float(tile.get("height_out", 0.0))
			# Allow flat straights and gentle constant-grade ramps (<= 1.6 m / tile),
			# avoiding sharp crests or jump edges.
			if absf(h_out - h_in) > 1.65:
				continue
			var mid: float = (float(tile.get("from", 0.0)) + float(tile.get("to", 0.0))) * 0.5
			var rel: float = fposmod(mid - START_DISTANCE, total)
			if rel < 28.0 or rel > total - 24.0:
				continue
			candidates.append(mid)
	if candidates.is_empty():
		var steps: int = 32
		for idx in steps:
			var s: float = total * (0.12 + 0.80 * float(idx) / float(steps))
			if absf(_spline.curvature_at(s, 4.0)) > 0.012:
				continue
			var y_a: float = (_spline.sample(s - 3.0)["position"] as Vector3).y
			var y_b: float = (_spline.sample(s + 3.0)["position"] as Vector3).y
			if absf(y_b - y_a) > 0.02:
				continue
			candidates.append(s)
	if candidates.is_empty():
		return picked
	var count: int = mini(target_count, candidates.size())
	var min_gap: float = maxf(total / float(count + 1) * 0.55, 24.0)
	for slot in count:
		var ideal: float = total * (0.16 + 0.72 * float(slot) / float(maxi(count - 1, 1)))
		var best_s: float = -1.0
		var best_err: float = INF
		for cand: float in candidates:
			var too_close: bool = false
			for chosen_s: float in picked:
				var diff: float = absf(fposmod(cand - chosen_s + total * 0.5, total) - total * 0.5)
				if diff < min_gap:
					too_close = true
					break
			if too_close:
				continue
			var err: float = absf(fposmod(cand - ideal + total * 0.5, total) - total * 0.5)
			if err < best_err:
				best_err = err
				best_s = cand
		if best_s >= 0.0:
			picked.append(best_s)
	return picked


func _build_ramps() -> void:
	# Two dirt kickers on the racing line. The collision is a convex wedge, so
	# the normal physics loop handles the launch; rivals get a matching lift in
	# _place_rival.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.38, 0.20)
	mat.roughness = 0.92
	mat.metallic = 0.0
	# The hand-built wedge winding faces down on some drivers; keep both faces
	# visible so the ramp never looks like an invisible floor.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lip_mat := StandardMaterial3D.new()
	lip_mat.albedo_color = Color(0.96, 0.88, 0.67)
	lip_mat.roughness = 0.85
	lip_mat.emission_enabled = true
	lip_mat.emission = Color(0.55, 0.42, 0.18)
	lip_mat.emission_energy_multiplier = 0.25
	for fraction: float in RAMP_FRACTIONS:
		var distance: float = _spline.total_length * fraction
		_ramp_distances.append(distance)
		var body := StaticBody3D.new()
		body.name = "Ramp_%d" % int(fraction * 100.0)
		body.transform = _track_transform(distance, 0.0, 0.045)
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)

		var half_w: float = RAMP_WIDTH * 0.5
		var half_l: float = RAMP_LENGTH * 0.5
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		_add_tri(verts, norms, uvs,
			Vector3(-half_w, 0.0, half_l), Vector3(half_w, 0.0, half_l),
			Vector3(half_w, RAMP_HEIGHT, -half_l), Vector3.UP)
		_add_tri(verts, norms, uvs,
			Vector3(-half_w, 0.0, half_l), Vector3(half_w, RAMP_HEIGHT, -half_l),
			Vector3(-half_w, RAMP_HEIGHT, -half_l), Vector3.UP)
		_add_tri(verts, norms, uvs,
			Vector3(-half_w, 0.0, half_l), Vector3(-half_w, RAMP_HEIGHT, -half_l),
			Vector3(-half_w, 0.0, -half_l), Vector3.LEFT)
		_add_tri(verts, norms, uvs,
			Vector3(half_w, 0.0, half_l), Vector3(half_w, 0.0, -half_l),
			Vector3(half_w, RAMP_HEIGHT, -half_l), Vector3.RIGHT)
		_add_tri(verts, norms, uvs,
			Vector3(-half_w, RAMP_HEIGHT, -half_l), Vector3(half_w, RAMP_HEIGHT, -half_l),
			Vector3(half_w, 0.0, -half_l), Vector3.BACK)
		_add_tri(verts, norms, uvs,
			Vector3(-half_w, RAMP_HEIGHT, -half_l), Vector3(half_w, 0.0, -half_l),
			Vector3(-half_w, 0.0, -half_l), Vector3.BACK)

		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			_make_arrays(verts, norms, uvs, PackedColorArray(), PackedInt32Array()))
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = mat
		body.add_child(visual)

		# A pale lip at the crest makes the kicker readable from a distance.
		var lip := MeshInstance3D.new()
		var lip_mesh := BoxMesh.new()
		lip_mesh.size = Vector3(RAMP_WIDTH + 0.1, 0.16, 0.55)
		lip.mesh = lip_mesh
		lip.material_override = lip_mat
		lip.position = Vector3(0.0, RAMP_HEIGHT + 0.02, -half_l + 0.32)
		body.add_child(lip)

		# Bright side rails make the kicker read as a ramp at speed.
		var rail_mat := StandardMaterial3D.new()
		rail_mat.albedo_color = Color(0.96, 0.82, 0.50)
		rail_mat.roughness = 0.8
		rail_mat.emission_enabled = true
		rail_mat.emission = Color(0.45, 0.30, 0.10)
		rail_mat.emission_energy_multiplier = 0.2
		var slope_length: float = sqrt(RAMP_LENGTH * RAMP_LENGTH
			+ RAMP_HEIGHT * RAMP_HEIGHT)
		var slope_angle: float = atan2(RAMP_HEIGHT, RAMP_LENGTH)

		# A thin solid top slab guarantees a visible driving surface.
		var top := MeshInstance3D.new()
		var top_mesh := BoxMesh.new()
		top_mesh.size = Vector3(RAMP_WIDTH, 0.07, slope_length)
		top.mesh = top_mesh
		top.material_override = mat
		top.position = Vector3(0.0, RAMP_HEIGHT * 0.5 + 0.035, 0.0)
		top.rotation.x = slope_angle
		body.add_child(top)
		for side: float in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var rail_mesh := BoxMesh.new()
			rail_mesh.size = Vector3(0.18, 0.12, slope_length)
			rail.mesh = rail_mesh
			rail.material_override = rail_mat
			rail.position = Vector3(side * (half_w + 0.06), RAMP_HEIGHT * 0.5 + 0.07, 0.0)
			rail.rotation.x = slope_angle
			body.add_child(rail)

		var shape := ConvexPolygonShape3D.new()
		shape.points = PackedVector3Array([
			Vector3(-half_w, 0.0, half_l), Vector3(half_w, 0.0, half_l),
			Vector3(-half_w, RAMP_HEIGHT, -half_l), Vector3(half_w, RAMP_HEIGHT, -half_l),
			Vector3(-half_w, 0.0, -half_l), Vector3(half_w, 0.0, -half_l),
		])
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)


func _add_tri(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3,
		_normal_dir: Vector3) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	for vertex: Vector3 in [a, b, c]:
		verts.append(vertex)
		norms.append(normal)
	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(1, 0))
	uvs.append(Vector2(0.5, 1))


func _ramp_lift_at(progress: float) -> float:
	var wrapped: float = fposmod(progress, _spline.total_length)
	for distance: float in _ramp_distances:
		var start: float = distance - RAMP_LENGTH * 0.5
		var end: float = distance + RAMP_LENGTH * 0.5
		if wrapped >= start and wrapped <= end:
			return RAMP_HEIGHT * ((wrapped - start) / maxf(RAMP_LENGTH, 0.001))
	return 0.0


func _build_trackside_props() -> void:
	# Designed obstacles instead of random clutter: two cone chicanes and a
	# narrow gate sit on the straights, with a light scatter of cones near the
	# edges for chaos. Cones are pushable so they fly when clipped rather than
	# stopping the kart dead.
	var cone: PackedScene = load(CONE_MODEL) as PackedScene
	if cone == null:
		return
	var holder := Node3D.new()
	holder.name = "TrackCones"
	add_child(holder)
	var length: float = _spline.total_length
	# Slalom chicanes: alternating cones force a weave down the straight.
	_chicane(holder, cone, length * 0.515, 4, 6.0, 1.9)
	_chicane(holder, cone, length * 0.135, 3, 6.5, 1.8)
	# A tight gate: thread it or smash through.
	var gate_d: float = length * 0.635
	for row in 3:
		for side: float in [-1.0, 1.0]:
			_spawn_cone(holder, cone, gate_d + float(row) * 3.0, side * 2.0, 0.8)
	# A few loose cones near the verges, never on the ideal line.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5511
	for i in 8:
		var distance: float = length * rng.randf()
		if absf(fposmod(distance - START_DISTANCE, length)) < 26.0:
			continue
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		_spawn_cone(holder, cone, distance, side * rng.randf_range(3.6, 4.6), 0.72)


func _chicane(holder: Node3D, cone: PackedScene, center: float, count: int,
		spacing: float, lateral: float) -> void:
	var start: float = center - float(count - 1) * spacing * 0.5
	for i in count:
		var side: float = 1.0 if i % 2 == 0 else -1.0
		_spawn_cone(holder, cone, start + float(i) * spacing, side * lateral, 0.8)


func _spawn_cone(holder: Node3D, cone: PackedScene, distance: float,
		lateral: float, scale: float) -> void:
	var body := RigidBody3D.new()
	# Explicit names keep the prop index identical on every peer, so a push
	# request and a snapshot always address the same cone.
	body.name = "TrackProp%03d" % _prop_serial
	_prop_serial += 1
	body.add_to_group("pushable")
	body.collision_layer = 4
	body.collision_mask = 5
	body.mass = 0.4
	body.transform = _track_transform(distance, lateral, 0.06)
	var model: Node3D = cone.instantiate() as Node3D
	model.scale = Vector3.ONE * scale
	body.add_child(model)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.45, 0.62, 0.45)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0, 0.31, 0)
	body.add_child(collision)
	holder.add_child(body)


func _build_verge_details() -> void:
	## Low-cost colour and clutter between the track and the forest: flowers,
	## mushrooms, rocks and fallen logs. One MultiMesh per model, no shadows.
	var rng := RandomNumberGenerator.new()
	rng.seed = 8123
	var holder := Node3D.new()
	holder.name = "VergeDetails"
	add_child(holder)
	var material: Material = FoliageBaker.make_material()
	var specs: Array[Dictionary] = [
		{"model": "flower_redA", "count": 180, "scale": 0.55},
		{"model": "flower_purpleA", "count": 180, "scale": 0.55},
		{"model": "flower_yellowA", "count": 180, "scale": 0.55},
		{"model": "flower_redB", "count": 120, "scale": 0.50},
		{"model": "mushroom_redGroup", "count": 70, "scale": 0.75},
		{"model": "mushroom_tan", "count": 50, "scale": 0.65},
		{"model": "rock_largeA", "count": 26, "scale": 1.15},
		{"model": "rock_largeB", "count": 26, "scale": 1.15},
		{"model": "log", "count": 20, "scale": 1.0},
	]
	for spec: Dictionary in specs:
		var mesh: ArrayMesh = FoliageBaker.bake(str(spec["model"]))
		if mesh == null:
			continue
		var transforms: Array = []
		for i in int(spec["count"]):
			var distance: float = rng.randf() * _spline.total_length
			var side: float = 1.0 if rng.randf() < 0.5 else -1.0
			var lateral: float = side * rng.randf_range(7.5, 34.0)
			var position: Vector3 = _track_transform(distance, lateral, 0.02).origin
			if _near_track(position, 7.0):
				continue
			var scale: float = float(spec["scale"]) * rng.randf_range(0.8, 1.25)
			var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale)
			transforms.append(Transform3D(basis, position))
		if transforms.is_empty():
			continue
		holder.add_child(FoliageBaker.create_chunked_instances(
			mesh, material, transforms, false, 80.0, [], 96.0))


func _tight_corners(max_count: int) -> Array[Dictionary]:
	## The tightest bends, spaced apart, each tagged with which side is outside.
	var candidates: Array[Dictionary] = []
	var step: float = 8.0
	var d: float = 20.0
	while d < _spline.total_length - 20.0:
		var before: float = _spline.yaw_at(d - 7.0)
		var after: float = _spline.yaw_at(d + 7.0)
		var curve: float = angle_difference(before, after)
		if absf(curve) > 0.14:
			candidates.append({"d": d, "curve": curve})
		d += step
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a["curve"])) > absf(float(b["curve"])))
	var chosen: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var ok: bool = true
		for other: Dictionary in chosen:
			if absf(fposmod(float(candidate["d"]) - float(other["d"]),
					_spline.total_length)) < 55.0:
				ok = false
				break
		if ok:
			candidate["outside"] = 1.0 if float(candidate["curve"]) > 0.0 else -1.0
			chosen.append(candidate)
		if chosen.size() >= max_count:
			break
	return chosen


func _build_corner_furniture() -> void:
	## Chevron boards and tire stacks at the six tightest corners. These are
	## the visual language of a race track and cost only a handful of meshes.
	var chosen: Array[Dictionary] = _tight_corners(6)
	if chosen.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "CornerFurniture"
	add_child(holder)
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = UiPalette.YELLOW
	board_mat.roughness = 0.9
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = UiPalette.OUTLINE
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.09, 0.08, 0.10)
	tire_mat.roughness = 1.0
	var tire_xf: Array = []
	var tire_cylinder := CylinderMesh.new()
	tire_cylinder.top_radius = 0.44
	tire_cylinder.bottom_radius = 0.44
	tire_cylinder.height = 0.26
	var stripe_xf: Array = []
	var post_xf: Array = []
	var pole_xf: Array = []
	var stripe_box := BoxMesh.new()
	stripe_box.size = Vector3(0.34, 0.85, 0.02)
	var post_box := BoxMesh.new()
	post_box.size = Vector3(0.12, 1.1, 0.12)
	var pole_cylinder := CylinderMesh.new()
	pole_cylinder.top_radius = 0.05
	pole_cylinder.bottom_radius = 0.05
	pole_cylinder.height = 3.6
	for candidate: Dictionary in chosen:
		var distance: float = float(candidate["d"])
		var outside: float = 1.0 if float(candidate["curve"]) > 0.0 else -1.0
		var root := Node3D.new()
		root.transform = _track_transform(distance, outside * (ROAD_HALF + 2.2), 0.0)
		root.rotation.y += PI
		holder.add_child(root)
		var board := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3.1, 0.85, 0.14)
		board.mesh = box
		board.position = Vector3(0.0, 1.15, 0.0)
		board.material_override = board_mat
		root.add_child(board)
		for stripe in 3:
			stripe_xf.append(root.transform * Transform3D(
				Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(28.0))),
				Vector3(-0.85 + float(stripe) * 0.85, 1.15, 0.08)))
		for post_side in [-1.0, 1.0]:
			post_xf.append(root.transform * Transform3D(Basis.IDENTITY,
				Vector3(post_side * 1.25, 0.55, 0.0)))
		# A tall pennant makes the corner readable from a distance.
		pole_xf.append(root.transform * Transform3D(Basis.IDENTITY,
			Vector3(0.0, 1.8, -0.2)))
		var flag := MeshInstance3D.new()
		var flag_mesh := BoxMesh.new()
		flag_mesh.size = Vector3(0.9, 0.55, 0.03)
		flag.mesh = flag_mesh
		flag.position = Vector3(0.45, 3.35, -0.2)
		var flag_mat := StandardMaterial3D.new()
		flag_mat.albedo_color = BOT_COLORS[chosen.find(candidate) % BOT_COLORS.size()]
		flag.material_override = flag_mat
		root.add_child(flag)
		for stack in 3:
			var stack_transform: Transform3D = _track_transform(
				distance - 2.0 + float(stack) * 2.0,
				outside * (ROAD_HALF + 4.0), 0.0)
			for tire in 3:
				tire_xf.append(stack_transform * Transform3D(Basis.IDENTITY,
					Vector3(0.0, 0.13 + float(tire) * 0.26, 0.0)))
	holder.add_child(_multimesh_instances(tire_cylinder, tire_mat, tire_xf,
		"CornerTireStacks"))
	holder.add_child(_multimesh_instances(stripe_box, stripe_mat, stripe_xf,
		"CornerChevrons"))
	holder.add_child(_multimesh_instances(post_box, stripe_mat, post_xf,
		"CornerPosts"))
	holder.add_child(_multimesh_instances(pole_cylinder, stripe_mat, pole_xf,
		"CornerPennants"))


func _build_corner_hazards() -> void:
	## Real penalties at the three tightest corners: a hay-bale wall on the
	## outside exit catches anyone running wide, and a solid tire stack marks
	## the apex on the inside. Both sit at the road edge so the centreline the
	## bots follow stays clear.
	var chosen: Array[Dictionary] = _tight_corners(3)
	if chosen.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "CornerHazards"
	add_child(holder)
	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.85, 0.68, 0.34)
	straw.roughness = 1.0
	var strap := StandardMaterial3D.new()
	strap.albedo_color = Color(0.45, 0.34, 0.18)
	strap.roughness = 1.0
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.10, 0.09, 0.11)
	tire_mat.roughness = 1.0
	var bale_xf: Array = []
	var band_xf: Array = []
	var apex_xf: Array = []
	var bale_size := Vector3(0.7, 0.9, 1.8)
	var bale_box := BoxMesh.new()
	bale_box.size = bale_size
	var band_box := BoxMesh.new()
	band_box.size = Vector3(0.74, 0.92, 0.12)
	var tire_cylinder := CylinderMesh.new()
	tire_cylinder.top_radius = 0.5
	tire_cylinder.bottom_radius = 0.5
	tire_cylinder.height = 0.28
	for candidate: Dictionary in chosen:
		var distance: float = float(candidate["d"])
		var outside: float = float(candidate["outside"])
		# Hay wall along the outside exit.
		for bale in 7:
			var d: float = distance + 1.0 + float(bale) * 2.0
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.transform = _track_transform(d, outside * (ROAD_HALF - 0.3), 0.0)
			holder.add_child(body)
			bale_xf.append(body.transform * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 0.45, 0.0)))
			for strap_z in [-0.5, 0.5]:
				band_xf.append(body.transform * Transform3D(Basis.IDENTITY,
					Vector3(0.0, 0.45, strap_z)))
			var shape := BoxShape3D.new()
			shape.size = bale_size
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.position = Vector3(0.0, 0.45, 0.0)
			body.add_child(collision)
		# Solid apex tire stack on the inside.
		var apex := StaticBody3D.new()
		apex.collision_layer = 1
		apex.collision_mask = 0
		apex.transform = _track_transform(distance, -outside * (ROAD_HALF - 1.2), 0.0)
		holder.add_child(apex)
		for tire in 3:
			apex_xf.append(apex.transform * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 0.14 + float(tire) * 0.28, 0.0)))
		var apex_shape := CylinderShape3D.new()
		apex_shape.radius = 0.5
		apex_shape.height = 0.84
		var apex_collision := CollisionShape3D.new()
		apex_collision.shape = apex_shape
		apex_collision.position = Vector3(0.0, 0.42, 0.0)
		apex.add_child(apex_collision)
	holder.add_child(_multimesh_instances(bale_box, straw, bale_xf, "HayBales"))
	holder.add_child(_multimesh_instances(band_box, strap, band_xf, "HayStraps"))
	holder.add_child(_multimesh_instances(tire_cylinder, tire_mat, apex_xf, "ApexTires"))


func _build_track_fence() -> void:
	## Low cream fence along both verges. Two MultiMeshes for the whole loop
	## (posts + rails) add structure without a draw-call per segment.
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 1.0, 0.12)
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.10, 0.12, 4.0)
	var post_xf: Array = []
	var rail_xf: Array = []
	var step: float = 4.0
	var d: float = 0.0
	while d < _spline.total_length:
		for side in [-1.0, 1.0]:
			var lateral: float = side * (ROAD_HALF + 3.2)
			var base: Transform3D = _track_transform(d, lateral, 0.0)
			post_xf.append(Transform3D(Basis(Vector3.UP, _spline.yaw_at(d)),
				base.origin + Vector3.UP * 0.5))
			if d + step < _spline.total_length:
				var rail: Transform3D = _track_transform(d + step * 0.5, lateral, 0.0)
				for height: float in [0.38, 0.82]:
					rail_xf.append(Transform3D(Basis(Vector3.UP, _spline.yaw_at(d + step * 0.5)),
						rail.origin + Vector3.UP * height))
		d += step
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("fff6e3")
	material.roughness = 1.0
	var posts := FoliageBaker.create_instances(_box_to_array(post_mesh), material, post_xf, false)
	posts.name = "FencePosts"
	add_child(posts)
	var rails := FoliageBaker.create_instances(_box_to_array(rail_mesh), material, rail_xf, false)
	rails.name = "FenceRails"
	add_child(rails)


func _box_to_array(box: BoxMesh) -> ArrayMesh:
	var arrays: Array = box.surface_get_arrays(0)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _multimesh_instances(mesh: Mesh, material: Material,
		transforms: Array, node_name: String) -> MultiMeshInstance3D:
	## One draw call for every repeated bale, band, tire or marker. Collision
	## bodies stay separate; only the visuals are batched.
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _build_sponsor_boards() -> void:
	## Muted painted farm signs with two posts and lettering on both faces.
	var holder := Node3D.new()
	holder.name = "SponsorBoards"
	add_child(holder)
	var texts: PackedStringArray = ["SLOP", "CART SLOP GP", "MEADOW LOOP", "GO FAST"]
	var colors: Array[Color] = [
		Color("a94f42"), Color("527789"), Color("c5a44f"), Color("637e58"),
		Color("a94f42"), Color("527789"), Color("c5a44f"), Color("637e58"),
	]
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("342f2b")
	dark.roughness = 1.0
	var post_xf: Array = []
	var post_box := BoxMesh.new()
	post_box.size = Vector3(0.16, 1.65, 0.16)
	for i in 8:
		var distance: float = _spline.total_length * (0.07 + float(i) * 0.115)
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var root := Node3D.new()
		root.transform = _track_transform(distance, side * (ROAD_HALF + 5.2), 0.0)
		root.rotation.y += PI
		holder.add_child(root)
		var board := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4.4, 1.35, 0.16)
		board.mesh = box
		board.position = Vector3(0.0, 1.55, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i % colors.size()]
		mat.roughness = 0.95
		board.material_override = mat
		root.add_child(board)
		for post_x: float in [-1.65, 1.65]:
			post_xf.append(root.transform * Transform3D(Basis.IDENTITY,
				Vector3(post_x, 0.82, 0.0)))
		# Only the track-facing side needs lettering; a back-face label was
		# invisible and doubled the label draw calls.
		var label := Label3D.new()
		label.text = texts[i % texts.size()]
		label.font = load(TITLE_FONT)
		label.font_size = 64
		label.pixel_size = 0.008
		label.outline_size = 8
		label.outline_modulate = Color(UiPalette.OUTLINE, 0.65)
		label.modulate = UiPalette.CREAM
		label.position = Vector3(0.0, 1.62, 0.10)
		root.add_child(label)
	holder.add_child(_multimesh_instances(post_box, dark, post_xf, "SponsorPosts"))


func _flash_gate(sector: int) -> void:
	# Sector 0 is the start gantry; sectors 1..3 are the three split gates.
	# Check for an empty list before the modulo: the old order divided by zero
	# on a map that never built its gates.
	if _gate_beams.is_empty():
		return
	var index: int = sector % _gate_beams.size()
	var beam: MeshInstance3D = _gate_beams[index]
	var mat: StandardMaterial3D = beam.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.emission_enabled = true
	mat.emission = Color(1, 0.95, 0.6, 1)
	mat.emission_energy_multiplier = 2.4
	var tween := create_tween()
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.85)


# --------------------------------------------------------------------------
# dense scenery


func _build_grid() -> void:
	for i in _spline.points.size():
		var p: Vector3 = _spline.points[i]
		var key := Vector2i(int(floor(p.x / GRID_CELL)), int(floor(p.z / GRID_CELL)))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)


func _near_track(position: Vector3, radius: float) -> bool:
	if MeadowLandmarks.is_clearing(_spline, position):
		return true
	var key := Vector2i(int(floor(position.x / GRID_CELL)),
		int(floor(position.z / GRID_CELL)))
	var radius_sq: float = radius * radius
	# Large exclusions (the far-field forest starts 34 m out) need a wider
	# neighbourhood than the usual 3x3 used for the 7-10 m track clearance.
	var reach: int = clampi(ceili(radius / GRID_CELL), 1, 4)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var bucket: Array = _grid.get(key + Vector2i(dx, dz), [])
			for index: int in bucket:
				if position.distance_squared_to(_spline.points[index]) < radius_sq:
					return true
	return false


func _bake_cached(model_name: String) -> ArrayMesh:
	if _baked.has(model_name):
		return _baked[model_name]
	var mesh: ArrayMesh = FoliageBaker.bake(model_name)
	_baked[model_name] = mesh
	return mesh


func _candidate(rng: RandomNumberGenerator) -> Vector3:
	# Two thirds of everything is packed into the verges the camera actually
	# sees; the rest fills the wider field so the horizon is never empty.
	if rng.randf() < 0.64:
		var frame: Dictionary = _spline.sample(rng.randf() * _spline.total_length)
		var angle: float = rng.randf() * TAU
		var distance: float = rng.randf_range(9.0, 55.0)
		return frame["position"] + Vector3(cos(angle), 0.0, sin(angle)) * distance
	return Vector3(rng.randf_range(-FIELD_X, FIELD_X), 0.0,
		rng.randf_range(-FIELD_Z, FIELD_Z))


func _scatter(rng: RandomNumberGenerator, models: PackedStringArray,
		attempts: int, exclusion: float, scale_min: float, scale_max: float,
		cast_shadow: bool, group_name: String, tint_variation: bool = false) -> void:
	var buckets: Dictionary = {}
	for i in attempts:
		var position: Vector3 = _candidate(rng)
		if absf(position.x) > FIELD_X or absf(position.z) > FIELD_Z:
			continue
		if _near_track(position, exclusion):
			continue
		var model: String = models[rng.randi_range(0, models.size() - 1)]
		var scale: float = rng.randf_range(scale_min, scale_max)
		var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale)
		if not buckets.has(model):
			buckets[model] = {"xf": [], "col": []}
		buckets[model]["xf"].append(Transform3D(basis, position + Vector3.UP * 0.02))
		if tint_variation:
			buckets[model]["col"].append(_foliage_tint(rng))

	var holder := Node3D.new()
	holder.name = group_name
	add_child(holder)
	for model: String in buckets:
		var baked: ArrayMesh = _bake_cached(model)
		if baked == null:
			continue
		var data: Dictionary = buckets[model]
		holder.add_child(FoliageBaker.create_instances(
			baked, _foliage_material, data["xf"], cast_shadow, data["col"]))


func _foliage_tint(rng: RandomNumberGenerator) -> Color:
	# Per-instance colour keeps 2,700 trees from reading as one flat wall of
	# green: a few warm autumn crowns, some shaded ones, some sunlit.
	var roll: float = rng.randf()
	if roll < 0.09:
		return Color(1.0, 0.76, 0.44)
	if roll < 0.28:
		return Color(0.72, 0.88, 0.76)
	if roll < 0.52:
		return Color(1.0, 0.98, 0.86)
	return Color.WHITE


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261105
	# No flat-shaded Kenney trees in the background: the PBR forest and the
	# grassy hill ring own the horizon now. Small ground cover stays cheap.
	_scatter(rng, BUSHES, 280, 22.0, 1.1, 2.4, false, "FarUnderbrush", true)
	_scatter(rng, GRASSES, 850, 7.4, 0.9, 2.1, false, "GrassClumps")
	_scatter(rng, FLOWERS, 300, 7.4, 0.8, 1.6, false, "Wildflowers")
	_scatter(rng, ROCKS, 200, 9.0, 0.8, 2.2, false, "Rocks")
	_scatter(rng, WOODLAND, 130, 10.0, 1.0, 2.0, false, "WoodlandProps")
	_build_trackside_fences(rng)

	_scenery = RaceScenery.new()
	var data: Dictionary = _scenery.build(self, _spline, self, 9137)
	_bend_materials = data["bend_materials"]
	_scenery_stats = data["stats"]
	print("MEADOW LOOP scenery: %d PBR trees, %d grass cards, %d scanned plants" % [
		int(_scenery_stats["trees"]), int(_scenery_stats["grass_cards"]),
		int(_scenery_stats["scanned"])])


func _build_trackside_fences(rng: RandomNumberGenerator) -> void:
	# Short wooden markers on the outside of the corners make the track read
	# from the chase camera even when the forest is thick.
	var transforms: Array = []
	var spacing: float = 9.0
	var count: int = int(floor(_spline.total_length / spacing))
	for i in count:
		var s: float = float(i) * spacing
		var frame: Dictionary = _spline.sample(s)
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var offset: float = (ROAD_HALF + CURB_WIDTH + 1.3) * side
		if _near_track(frame["position"] + frame["right"] * offset, 5.0):
			# Skip the marker when another part of the loop passes right there.
			continue
		var position: Vector3 = frame["position"] + frame["right"] * offset
		var basis: Basis = Basis(Vector3.UP, _spline.yaw_at(s) + rng.randf_range(-0.15, 0.15))
		transforms.append(Transform3D(basis, position + Vector3.UP * 0.02))
	var baked: ArrayMesh = _bake_cached("fence_simple")
	if baked == null or transforms.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "TracksideMarkers"
	holder.add_child(FoliageBaker.create_instances(
		baked, _foliage_material, transforms, false))
	add_child(holder)


# --------------------------------------------------------------------------
# rivals


func _bot_count() -> int:
	## Solo: the BOTS pill in PLAY. Multiplayer: whatever the host chose.
	if _multiplayer:
		return clampi(Network.session_bot_count, 0, 5) if Network.session_bots else 0
	return GameSettings.effective_bot_count()


func _build_rivals() -> void:
	var count: int = _bot_count()
	if count <= 0:
		return
	_collect_trackside_solids()
	# Only the host runs the rival simulation. Clients spawn the same bodies as
	# interpolated ghosts and follow the host's snapshot, so every player sees
	# the same bots on the same line.
	var authority: bool = not _multiplayer or _is_host
	var rng := RandomNumberGenerator.new()
	if _multiplayer and Network.race_seed != 0:
		rng.seed = Network.race_seed
	elif _multiplayer and Network.join_code != "":
		rng.seed = Network.join_code.hash()
	else:
		rng.seed = Time.get_ticks_msec()
	var names: Array = Array(BOT_NAMES)
	for j in range(names.size() - 1, 0, -1):
		var k: int = rng.randi_range(0, j)
		var swap: Variant = names[j]
		names[j] = names[k]
		names[k] = swap
	var vehicle_id: String = GameSettings.minigame_vehicle
	if VehicleCatalog.find(vehicle_id).is_empty():
		vehicle_id = VehicleCatalog.DEFAULT_ID
	var difficulty: int = Network.bot_difficulty()
	var skill_lo: Array[float] = [0.62, 0.72, 0.86]
	var skill_hi: Array[float] = [0.82, 1.00, 1.12]
	var boost_lo: Array[float] = [0.15, 0.40, 0.65]
	var boost_hi: Array[float] = [0.55, 0.85, 1.00]
	var aggr_lo: Array[float] = [0.15, 0.35, 0.60]
	var aggr_hi: Array[float] = [0.40, 0.70, 1.00]
	# One seeded offset rotates the field through the four lines, so even the
	# first five rivals never share a single centreline.
	var line_offset: int = rng.randi_range(0, RaceAI.LINE_COUNT - 1)
	for i in count:
		var lane: float = [-0.36, 0.36, 0.0, -0.18, 0.18][i % 5] * _road_half
		var progress: float = START_DISTANCE + 5.0 + float(i) * 4.5
		var spawn: Transform3D = _track_transform(progress, lane, 0.12)
		var rival: CartPlayer = CART_SCENE.instantiate() as CartPlayer
		# Transform before add_child: a body created at the origin spends its
		# first tick overlapping the player and other rivals.
		rival.transform = spawn
		if authority:
			rival.name = "Rival_" + str(names[i % names.size()])
			# Mark AI before add_child so CartFeedback skips audio, skid ribbons
			# and per-frame particle work during _ready.
			rival.ai_mode = true
			add_child(rival)
			rival.setup_ai(vehicle_id)
		else:
			# Client copy: a solid ghost driven only by the host's snapshot.
			add_child(rival)
			rival.call("setup_remote", 1000 + i)
			rival.name = "Rival_" + str(names[i % names.size()])
			rival.set_vehicle_id(vehicle_id)
		var label := Label3D.new()
		label.text = str(names[i % names.size()])
		label.font = load(TITLE_FONT)
		label.font_size = 42
		label.pixel_size = 0.0062
		label.outline_size = 13
		label.outline_modulate = UiPalette.OUTLINE
		label.modulate = BOT_COLORS[i % BOT_COLORS.size()]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0.0, 2.05, 0.0)
		rival.add_child(label)
		rival.set_spawn_transform(spawn)
		rival.surface_grip = _surface_grip_for(progress)
		# Personality is drawn in the same order as before the AI rewrite, so a
		# seeded field stays familiar. Skill sets the margins; the drawn line
		# style, phase, aggression and lookahead trim make every driver follow a
		# different line and apply throttle and brakes differently.
		var skill: float = rng.randf_range(skill_lo[difficulty], skill_hi[difficulty])
		var lookahead: float = rng.randf_range(0.82, 1.18)
		var boost_bias: float = rng.randf_range(boost_lo[difficulty], boost_hi[difficulty])
		var aggression: float = rng.randf_range(aggr_lo[difficulty], aggr_hi[difficulty])
		var phase: float = rng.randf() * TAU
		# Rotate through the four lines instead of drawing independently: a
		# five-bot field always shows at least four different racing lines, and
		# the seeded offset still changes who gets which line.
		var line_style: int = (i + line_offset) % RaceAI.LINE_COUNT
		var driver: RaceAI = null
		if authority:
			driver = RaceAI.new(_spline, _road_half, _preset)
			driver.configure(skill, lane * 0.25, boost_bias, rival.max_speed,
				line_style, phase, aggression, lookahead)
			driver.set_obstacles(_trackside_solids)
		_rivals.append({
			"node": rival,
			"label": label,
			"progress": progress,
			"prev_s": _spline.wrap_distance(progress),
			"index": _track_index_at_distance(progress),
			"lateral": lane,
			"lane": lane,
			"skill": skill,
			"lookahead": lookahead,
			"boost_bias": boost_bias,
			"aggression": aggression,
			"phase": phase,
			"vehicle": vehicle_id,
			"stuck": 0.0,
			"off_time": 0.0,
			"finished": false,
			## Race time of the line crossing, -1 while still racing.
			"finish_time": -1.0,
			"driver": driver,
			"server_pos": Vector3.ZERO,
			"server_yaw": 0.0,
			"server_velocity": Vector3.ZERO,
			"server_stamp_ms": 0,
			"has_server_sample": false,
		})


func _collect_trackside_solids() -> void:
	## Hay-bale walls and apex tyre stacks are solid bodies right at the road
	## edge. The race AI avoids them without a per-frame physics query.
	_trackside_solids.clear()
	var hazards: Node3D = get_node_or_null("CornerHazards") as Node3D
	if hazards == null:
		return
	for child: Node in hazards.get_children():
		if child is StaticBody3D:
			_trackside_solids.append((child as StaticBody3D).global_position)


func _reset_rival(index: int) -> void:
	var rival: Dictionary = _rivals[index]
	var node: CartPlayer = rival["node"]
	var spawn: Transform3D = _track_transform(float(rival["progress"]),
		float(rival["lane"]), 0.15)
	node.set_spawn_transform(spawn)
	node.global_transform = spawn
	node.reset_for_respawn()
	node.velocity = Vector3.ZERO
	node.surface_grip = _surface_grip_for(float(rival["progress"]))
	rival["prev_s"] = _spline.wrap_distance(float(rival["progress"]))
	rival["index"] = _track_index_at_distance(float(rival["progress"]))
	rival["stuck"] = 0.0
	rival["off_time"] = 0.0
	var driver: RaceAI = rival["driver"]
	if driver != null:
		driver.reset()


func _track_index_at_distance(distance: float) -> int:
	## Binary search over the local copy of the spline's cumulative arc length.
	var count: int = _track_cumulative.size()
	if count <= 0:
		return 0
	var target: float = fposmod(distance, _track_total)
	var low: int = 0
	var high: int = count - 1
	while low < high:
		var mid: int = (low + high + 1) / 2
		if _track_cumulative[mid] <= target:
			low = mid
		else:
			high = mid - 1
	return low


func _rival_nearest(world_position: Vector3, hint_index: int) -> float:
	## Nearest centreline arc length around this rival's own last segment.
	## One shared spline cache cannot tell five carts apart: its window can
	## return a boundary point a corner away and freeze a rival's progress,
	## so each rival keeps its own hint. Results land in _rival_nearest_index
	## and _rival_nearest_distance; the scan allocates nothing.
	var count: int = _track_points.size()
	if count < 2:
		_rival_nearest_index = 0
		_rival_nearest_distance = 0.0
		return 0.0
	var best_sq: float = INF
	var best_s: float = 0.0
	var best_index: int = posmod(hint_index, count)
	var offset: int = -8
	while offset <= 16:
		var index: int = posmod(hint_index + offset, count)
		var a: Vector3 = _track_points[index]
		var b: Vector3 = _track_points[(index + 1) % count]
		var ab: Vector3 = b - a
		var length_sq: float = ab.length_squared()
		var t: float = 0.0
		if length_sq > 0.000001:
			t = clampf((world_position - a).dot(ab) / length_sq, 0.0, 1.0)
		var candidate: Vector3 = a + ab * t
		var d_sq: float = world_position.distance_squared_to(candidate)
		if d_sq < best_sq:
			best_sq = d_sq
			best_s = _track_cumulative[index] + sqrt(length_sq) * t
			best_index = index
		offset += 1
	_rival_nearest_index = best_index
	_rival_nearest_distance = sqrt(best_sq)
	return fposmod(best_s, _track_total)


func _tick_rivals(delta: float) -> void:
	## Host/solo AI. One shared traffic list is rebuilt per tick (not per rival)
	## and every rival is driven by its own RaceAI; lap and progress bookkeeping
	## stays exactly where it was.
	var limit: float = _race_finish_distance()
	_traffic.clear()
	for other_rival: Dictionary in _rivals:
		var other_node: CartPlayer = other_rival["node"]
		if is_instance_valid(other_node):
			_traffic.append(other_node)
	if _cart != null:
		_traffic.append(_cart)
	for remote: CartPlayer in _remote_carts.values():
		if is_instance_valid(remote):
			_traffic.append(remote)
	for i in _rivals.size():
		var rival: Dictionary = _rivals[i]
		var node: CartPlayer = rival["node"]
		if not is_instance_valid(node):
			continue
		if bool(rival["finished"]):
			node.set_ai_controls(0.0, 0.35, 0.0)
			continue
		var s: float = _rival_nearest(node.global_position, int(rival["index"]))
		rival["index"] = _rival_nearest_index
		var track_distance: float = _rival_nearest_distance
		var step: float = s - float(rival["prev_s"])
		if step < -_spline.total_length * 0.5:
			step += _spline.total_length
		elif step > _spline.total_length * 0.5:
			step -= _spline.total_length
		var progress: float = float(rival["progress"])
		progress += clampf(step, -node.max_speed * delta * 2.0 - 1.0,
			node.max_speed * delta * 2.0 + 1.0)
		rival["progress"] = progress
		rival["prev_s"] = s
		var frame: Dictionary = _spline.sample(s)
		rival["lateral"] = (node.global_position - frame["position"]).dot(frame["right"])
		if progress >= limit:
			rival["finished"] = true
			# Bank WHEN the line was crossed: placements rank finishers by this
			# time, never by the leftover metres past the line.
			if float(rival["finish_time"]) < 0.0:
				rival["finish_time"] = _race_time
			node.collision_layer = 0
			node.contact_enabled = false
			node.set_ai_controls(0.0, 0.5, 0.0)
			continue

		var driver: RaceAI = rival["driver"]
		if driver == null:
			# A rival carried over from a scene built before the driver table
			# existed still rolls forward instead of parking on the grid.
			node.set_ai_controls(0.6, 0.0, 0.0)
			continue
		driver.update(delta, node, progress, _traffic)
		node.set_ai_controls(driver.throttle, driver.brake, driver.steer,
			driver.boost, driver.drift)

		var speed: float = maxf(node.velocity.dot(
			-node.global_transform.basis.z), 0.0)
		if speed < 0.8:
			rival["stuck"] = float(rival["stuck"]) + delta
		else:
			rival["stuck"] = maxf(float(rival["stuck"]) - delta * 2.0, 0.0)
		if float(track_distance) > _road_half + 7.5 or node.global_position.y < -8.0:
			rival["off_time"] = float(rival["off_time"]) + delta
		else:
			rival["off_time"] = 0.0
		if float(rival["stuck"]) > 4.0 or float(rival["off_time"]) > 2.0:
			_reset_rival(i)


func _remote_finished(peer_id: int) -> bool:
	## A peer is finished once its streamed progress reached the line. The
	## crossing is latched, so a late or reordered packet cannot un-finish it.
	if _remote_finish_time.has(peer_id):
		return true
	return float(_remote_progress.get(peer_id, 0.0)) \
		>= _race_finish_distance() - 2.0


func _cart_is_ahead(finished: bool, finish_time: float, progress: float) -> bool:
	## True when another cart's result beats the local cart. Finished carts
	## always beat racing ones; between two finishers the earlier crossing wins,
	## not the leftover metres of progress. Server bots stop exactly on the line
	## while the local cart overshoots it by up to one physics frame, which used
	## to let the later finisher steal the place.
	var local_finished: bool = _finish_time >= 0.0
	if finished != local_finished:
		return finished
	if finished and finish_time >= 0.0 and _finish_time >= 0.0 \
			and not is_equal_approx(finish_time, _finish_time):
		return finish_time < _finish_time
	if is_equal_approx(progress, _unwrapped):
		return false
	return progress > _unwrapped


func _place() -> int:
	# The host's canonical standings own the place once they land; every peer
	# then shows the same number for the same cart.
	if _multiplayer and not _standings_snapshot.is_empty():
		var canonical: Dictionary = StandingsReconciler.places(_standings_snapshot)
		var local_id: int = multiplayer.get_unique_id()
		if canonical.has(local_id):
			return int(canonical[local_id])
	var position: int = 1
	for rival: Dictionary in _rivals:
		if _cart_is_ahead(bool(rival["finished"]), float(rival["finish_time"]),
				float(rival["progress"])):
			position += 1
	for peer_id: int in _remote_progress:
		if _cart_is_ahead(_remote_finished(peer_id),
				float(_remote_finish_time.get(peer_id, -1.0)),
				float(_remote_progress[peer_id])):
			position += 1
	return position


func _field_size() -> int:
	var count: int = 1 + _rivals.size() + _remote_progress.size()
	# A peer whose progress packet has not arrived yet is still part of the
	# host's canonical field, so the "/ N" suffix must not shrink mid-race.
	if _multiplayer and not _standings_snapshot.is_empty():
		count = maxi(count, (_standings_snapshot.get("rows", []) as Array).size())
	return count


# --------------------------------------------------------------------------
# overlay (candy UI, matching the menus)


func _build_overlay() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 15
	add_child(_canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI_THEME
	_canvas.add_child(root)

	_countdown_label = _make_label(root, 112, UiPalette.YELLOW,
		Vector2(-260.0, -110.0), Vector2(260.0, 110.0), 0.5, 0.0)
	_countdown_label.text = "3"

	# Upper-center arcade banner zone (y = 92..190) so callouts and warnings
	# sit cleanly below the top HUD bar without ever covering the player's kart.
	_callout_label = _make_label(root, 30, UiPalette.YELLOW,
		Vector2(-380.0, 92.0), Vector2(380.0, 124.0), 0.0, 0.0)
	_callout_label.visible = false

	_wrong_way_label = _make_label(root, 28, UiPalette.RED,
		Vector2(-360.0, 92.0), Vector2(360.0, 124.0), 0.0, 0.0)
	_wrong_way_label.text = "WRONG WAY!  ·  TURN AROUND"
	_wrong_way_label.visible = false

	_toast_label = _make_label(root, 24, Color("ffffff"),
		Vector2(-380.0, 124.0), Vector2(380.0, 152.0), 0.0, 0.0)
	_toast_label.visible = false

	_offtrack_label = _make_label(root, 20, UiPalette.RED,
		Vector2(-300.0, 152.0), Vector2(300.0, 171.0), 0.0, 0.0)
	_offtrack_label.text = "OFF TRACK  ·  EASE BACK IN"
	_offtrack_label.visible = false

	_impact_label = _make_label(root, 20, UiPalette.YELLOW,
		Vector2(-300.0, 171.0), Vector2(300.0, 190.0), 0.0, 0.0)
	_impact_label.text = "BARRIER!  ·  EASE OFF"
	_impact_label.visible = false

	_result_ui = ResultScreen.new()
	_result_card = _result_ui.build(root, {
		"name": "ResultCard",
		"title": "RACE COMPLETE",
		"subtitle": _result_summary_text(),
		"multiplayer": _multiplayer,
		"is_host": _is_host,
		"primary_text": "RACE AGAIN" if (not _multiplayer or _is_host) else "",
		"primary_color": UiPalette.YELLOW,
		"on_primary": _on_race_again,
		"secondary_text": "BACK TO LOBBY" if _multiplayer else "BACK TO MODES",
		"secondary_color": UiPalette.CYAN if (not _multiplayer or _is_host) else UiPalette.YELLOW,
		"on_secondary": _on_back_to_lobby,
		"tertiary_text": "MAIN MENU",
		"tertiary_color": UiPalette.RED,
		"on_tertiary": _on_main_menu,
		# 0.8.7 host/non-host contract (resolved in result_screen.gd): the host's
		# MAIN MENU is confirm-gated while a live room is active; a client gets
		# the animated "Waiting for host..." status + LEAVE LOBBY instead of any
		# host-only navigation, so `on_leave` is the same leave-session callback.
		"confirm_main_menu": _multiplayer,
		"on_leave": _on_main_menu,
		# The canonical standings table is built by _build_result_standings()
		# from _result_entries(); the helper only supplies the column slot.
		"standings_columns": [],
		"standings_slot": _multiplayer,
	})
	_result_root = _result_card["root"] as Control
	_result_title = _result_card["title"] as Label
	_result_subtitle = _result_card["subtitle"] as Label
	# The pause menu is a nav scope too. Keep the card out of the way while it
	# is open, or MenuNav would pick the deeper result card and arrow keys
	# would move focus behind the pause panel.
	var pause_menu: Control = get_node_or_null("PauseMenu/Root") as Control
	if pause_menu != null:
		pause_menu.visibility_changed.connect(_on_pause_visibility_changed)

	# Finish-line artwork behind the card, matching the menu art set. The shared
	# result scrim sits above it so the card stays readable.
	var art: Control = ART_BACKDROP.new()
	art.set("texture_names", PackedStringArray(["preview_" + _preset_id + ".png", "bg_parking.png"]))
	art.set("dim", 0.14)
	_result_root.add_child(art)
	_result_root.move_child(art, 0)

	var telemetry: VBoxContainer = _result_card["telemetry"] as VBoxContainer

	var flag := Control.new()
	flag.custom_minimum_size = Vector2(190, 30)
	flag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	flag.set_script(load(CHECKER_FLAG))
	flag.set("show_pole", false)
	flag.set("wave_amount", 0.0)
	flag.set("columns", 8)
	flag.set("rows", 3)
	var header: VBoxContainer = _result_card["header"] as VBoxContainer
	header.add_child(flag)
	header.move_child(flag, 0)

	# One caption row over one value row, from the shared UiKit telemetry grid.
	var stats: Dictionary = _result_ui.make_stat_tiles(
		["RACE TIME", "BEST LAP", "POSITION", "LAPS"])
	telemetry.add_child(stats["grid"])
	var stat_values: Array = stats["values"]
	_result_total = stat_values[0] as Label
	_result_best = stat_values[1] as Label
	_result_place = stat_values[2] as Label
	_result_laps = stat_values[3] as Label

	# Lap table: lap name, time, delta to the previous lap. The best lap is
	# tinted instead of separated by a rule.
	var lap_table: Dictionary = _result_ui.make_table([
		{"label": "LAP", "expand": true, "align": HORIZONTAL_ALIGNMENT_LEFT},
		{"label": "TIME", "width": 96.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"label": "DELTA", "width": 76.0, "align": HORIZONTAL_ALIGNMENT_RIGHT},
	])
	telemetry.add_child(lap_table["box"])
	_result_lap_rows = lap_table["rows"] as VBoxContainer

	if _multiplayer:
		var standings_column: VBoxContainer = _result_card["standings_slot"] as VBoxContainer
		_build_result_standings(standings_column)
	else:
		# The shared refresh path still expects the node to exist, just hidden.
		# Keep it in the tree (hidden) so it is freed with the scene.
		_result_standings_section = VBoxContainer.new()
		_result_standings_section.visible = false
		telemetry.add_child(_result_standings_section)


func _build_result_standings(parent: VBoxContainer) -> void:
	## Multiplayer-only standings column. Remote peers do not replicate lap
	## times, so their total/best stay "—" and the gap is the real track
	## distance behind the leader; the card never invents a time for another
	## player. The wait banner sits above the table so it never covers a row.
	_result_standings_section = VBoxContainer.new()
	_result_standings_section.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
	_result_standings_section.visible = false
	parent.add_child(_result_standings_section)

	var standings_title := Label.new()
	standings_title.text = "STANDINGS"
	standings_title.theme_type_variation = &"TitleLabel"
	standings_title.add_theme_font_size_override("font_size", 18)
	standings_title.add_theme_color_override("font_color", UiPalette.YELLOW)
	standings_title.add_theme_constant_override("outline_size", 0)
	standings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_standings_section.add_child(standings_title)

	_result_wait_style = _make_result_banner_style(UiPalette.YELLOW)
	_result_done_style = _make_result_banner_style(UiPalette.GRASS)
	_result_wait_banner = PanelContainer.new()
	_result_wait_banner.visible = false
	_result_wait_banner.add_theme_stylebox_override("panel", _result_wait_style)
	_result_standings_section.add_child(_result_wait_banner)
	_result_wait_label = Label.new()
	_result_wait_label.text = "WAITING FOR OTHER PLAYERS"
	_result_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_wait_label.add_theme_font_size_override("font_size", 14)
	_result_wait_label.add_theme_color_override("font_color", UiPalette.INK)
	_result_wait_banner.add_child(_result_wait_label)

	var standings_header_pad := MarginContainer.new()
	standings_header_pad.add_theme_constant_override("margin_left", UiKit.SPACING_TIGHT)
	standings_header_pad.add_theme_constant_override("margin_right", UiKit.SPACING_TIGHT)
	_result_standings_section.add_child(standings_header_pad)
	var standings_header := HBoxContainer.new()
	standings_header.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
	standings_header_pad.add_child(standings_header)
	standings_header.add_child(_make_standings_header("POS", 30.0,
		HORIZONTAL_ALIGNMENT_CENTER))
	standings_header.add_child(_make_standings_header("", 10.0,
		HORIZONTAL_ALIGNMENT_LEFT))
	standings_header.add_child(_make_standings_header("DRIVER", 0.0,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	standings_header.add_child(_make_standings_header("TOTAL", 62.0,
		HORIZONTAL_ALIGNMENT_RIGHT))
	standings_header.add_child(_make_standings_header("BEST", 62.0,
		HORIZONTAL_ALIGNMENT_RIGHT))
	standings_header.add_child(_make_standings_header("GAP", 54.0,
		HORIZONTAL_ALIGNMENT_RIGHT))

	var standings_scroll := ScrollContainer.new()
	standings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	standings_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# Fit whatever vertical budget the result helper left above the action
	# footer; a full field therefore scrolls instead of pushing the buttons
	# past the 720p safe height.
	standings_scroll.custom_minimum_size = Vector2(0.0,
		minf(344.0, float(_result_ui.table_cap(_result_card))))
	_result_standings_section.add_child(standings_scroll)
	_result_standings_rows = VBoxContainer.new()
	_result_standings_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_standings_rows.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
	standings_scroll.add_child(_result_standings_rows)

	_result_row_style = UiKit.row_style(false)
	_result_local_row_style = UiKit.row_style(true)


func _result_summary_text() -> String:
	## Track, distance and the official-time tag when the Pi has stamped the
	## result. Used while building the card and again when the stamp lands.
	var text: String = "%s  ·  %d LAPS" % [_race_title(), _total_laps]
	if _official_applied:
		text += "  ·  OFFICIAL"
	return text


func _make_label(parent: Control, font_size: int, color: Color,
		top_left: Vector2, bottom_right: Vector2, anchor_y: float,
		y_offset: float) -> Label:
	var label := Label.new()
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = anchor_y
	label.anchor_bottom = anchor_y
	label.offset_left = top_left.x
	label.offset_right = bottom_right.x
	label.offset_top = top_left.y + y_offset
	label.offset_bottom = bottom_right.y + y_offset
	label.pivot_offset = Vector2((bottom_right.x - top_left.x) * 0.5,
		(bottom_right.y - top_left.y) * 0.5)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.theme_type_variation = &"TitleLabel"
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", UiPalette.OUTLINE)
	label.add_theme_constant_override("outline_size", 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _make_result_banner_style(color: Color) -> StyleBoxFlat:
	## Slanted accent banner behind the standings wait/done slot.
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = UiPalette.OUTLINE
	style.set_border_width_all(3)
	style.set_corner_radius_all(5)
	style.skew = Vector2(0.14, 0.0)
	style.content_margin_left = float(UiKit.SPACING)
	style.content_margin_right = float(UiKit.SPACING)
	style.content_margin_top = float(UiKit.SPACING_TIGHT)
	style.content_margin_bottom = float(UiKit.SPACING_TIGHT)
	style.anti_aliasing = true
	return style


func _make_standings_header(text: String, width: float, align: int,
		expand: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = align
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UiPalette.CYAN)
	return label


func _make_standings_row() -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 36)
	panel.add_theme_stylebox_override("panel", _result_row_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
	panel.add_child(row)
	var place := Label.new()
	place.custom_minimum_size = Vector2(30, 0)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place.add_theme_font_size_override("font_size", 14)
	place.add_theme_color_override("font_color", UiPalette.YELLOW)
	row.add_child(place)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", UiPalette.CREAM)
	row.add_child(name_label)
	var total := Label.new()
	total.custom_minimum_size = Vector2(62, 0)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total.add_theme_font_size_override("font_size", 14)
	total.add_theme_color_override("font_color", UiPalette.CREAM)
	row.add_child(total)
	var best := Label.new()
	best.custom_minimum_size = Vector2(62, 0)
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	best.add_theme_font_size_override("font_size", 14)
	best.add_theme_color_override("font_color", UiPalette.CYAN)
	row.add_child(best)
	var gap := Label.new()
	gap.custom_minimum_size = Vector2(54, 0)
	gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gap.add_theme_font_size_override("font_size", 14)
	gap.add_theme_color_override("font_color", UiPalette.YELLOW)
	row.add_child(gap)
	_result_standings_rows.add_child(panel)
	return {
		"panel": panel,
		"place": place,
		"dot": dot,
		"name": name_label,
		"total": total,
		"best": best,
		"gap": gap,
	}


func _update_standings_row(row_data: Dictionary, entry: Dictionary, place: int,
		leader_progress: float) -> void:
	var panel: PanelContainer = row_data["panel"]
	panel.add_theme_stylebox_override("panel",
		_result_local_row_style if bool(entry["local"]) else _result_row_style)
	(row_data["place"] as Label).text = str(place)
	(row_data["dot"] as ColorRect).color = entry["color"]
	(row_data["name"] as Label).text = str(entry["name"])
	var total_seconds: float = float(entry["total"])
	if total_seconds >= 0.0:
		(row_data["total"] as Label).text = _format_time(total_seconds)
	else:
		(row_data["total"] as Label).text = "—"
	var best_seconds: float = float(entry["best"])
	if best_seconds >= 0.0:
		(row_data["best"] as Label).text = _format_time(best_seconds)
	else:
		(row_data["best"] as Label).text = "—"
	var gap_text: String = "—"
	if place == 1:
		gap_text = "WINNER" if bool(entry["finished"]) else "LEADER"
	elif bool(entry["finished"]):
		gap_text = "FINISHED"
	else:
		var behind: float = maxf(leader_progress - float(entry["progress"]), 0.0)
		gap_text = "+%d m" % int(round(behind))
	(row_data["gap"] as Label).text = gap_text


func _result_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var local_id: int = multiplayer.get_unique_id() if _multiplayer else 0
	var local_finished: bool = _finish_time >= 0.0
	entries.append({
		"key": "local",
		"id": local_id,
		"name": (Network.name_of(local_id) + "  (YOU)") if _multiplayer else "YOU",
		"color": Network.color_of(local_id) if _multiplayer else UiPalette.YELLOW,
		"progress": _unwrapped,
		"finished": local_finished,
		"finish_time": _finish_time,
		"local": true,
		# Never invent a total time for a cart that is still racing: the live
		# HUD standings reuse this list before the result card opens.
		"total": _race_time if local_finished else -1.0,
		"best": _best_lap_time(),
	})
	for index in _rivals.size():
		var rival: Dictionary = _rivals[index]
		var rival_label: Label3D = rival["label"]
		entries.append({
			"key": "rival_%d" % index,
			"id": -1 - index,
			"name": rival_label.text,
			"color": rival_label.modulate,
			"progress": float(rival["progress"]),
			"finished": bool(rival["finished"]),
			"finish_time": float(rival["finish_time"]),
			"local": false,
			"total": -1.0,
			"best": -1.0,
		})
	for peer_id: int in _remote_progress:
		entries.append({
			"key": "peer_%d" % peer_id,
			"id": peer_id,
			"name": Network.name_of(peer_id),
			"color": Network.color_of(peer_id),
			"progress": float(_remote_progress[peer_id]),
			"finished": _remote_finished(peer_id),
			"finish_time": float(_remote_finish_time.get(peer_id, -1.0)),
			"local": false,
			"total": -1.0,
			"best": -1.0,
		})
	# The host's canonical standings own order and finish times once a snapshot
	# has arrived. Before that (and in solo) the local deterministic sort runs.
	if _multiplayer and not _standings_snapshot.is_empty():
		return _entries_from_standings(entries)
	entries.sort_custom(Callable(self, "_standings_before"))
	for index in entries.size():
		entries[index]["place"] = index + 1
	return entries


func _standings_before(a: Dictionary, b: Dictionary) -> bool:
	## Finished carts first (earlier crossing wins), then racing carts by
	## distance, then the local cart on an exact tie. The old progress-only sort
	## let a later finisher pass an earlier one because the local cart overshoots
	## the line by up to one physics frame while bots stop exactly on it.
	var a_finished: bool = bool(a["finished"])
	var b_finished: bool = bool(b["finished"])
	if a_finished != b_finished:
		return a_finished
	var pa: float = float(a["progress"])
	var pb: float = float(b["progress"])
	if a_finished:
		var a_time: float = float(a["finish_time"])
		var b_time: float = float(b["finish_time"])
		if a_time >= 0.0 and b_time >= 0.0 and not is_equal_approx(a_time, b_time):
			return a_time < b_time
	if not is_equal_approx(pa, pb):
		return pa > pb
	if bool(a["local"]):
		return true
	if bool(b["local"]):
		return false
	return int(a["id"]) < int(b["id"])


func _refresh_result_standings() -> void:
	if not _multiplayer or _result_standings_rows == null:
		return
	_result_standings_section.visible = true
	var entries: Array[Dictionary] = _result_entries()
	var leader_progress: float = 0.0
	if not entries.is_empty():
		leader_progress = float(entries[0]["progress"])
	var live_keys: Dictionary = {}
	for entry: Dictionary in entries:
		live_keys[str(entry["key"])] = true
	var stale: Array[String] = []
	for key: String in _result_standings_cache:
		if not live_keys.has(key):
			stale.append(key)
	for key: String in stale:
		var old: Dictionary = _result_standings_cache[key]
		var old_panel: Control = old["panel"]
		if is_instance_valid(old_panel):
			_result_standings_rows.remove_child(old_panel)
			old_panel.queue_free()
		_result_standings_cache.erase(key)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var key: String = str(entry["key"])
		var row_data: Dictionary = _result_standings_cache.get(key, {})
		if row_data.is_empty():
			row_data = _make_standings_row()
			_result_standings_cache[key] = row_data
		_update_standings_row(row_data, entry, index + 1, leader_progress)
		_result_standings_rows.move_child(row_data["panel"] as Control, index)
	if _result_place != null and not _official_applied:
		# Remote progress can arrive after our finish; keep the big position in
		# sync with the live standings. The Pi's official placement wins once
		# it lands; a local guess must never overwrite it.
		var live_place: int = _place()
		_result_place.text = "%s / %d" % [_ordinal(live_place), _field_size()]
	var waiting: int = _waiting_peer_count()
	_result_wait_banner.visible = true
	if waiting > 0:
		_result_wait_label.text = "WAITING FOR %d PLAYER%s..." % [
			waiting, "" if waiting == 1 else "S"]
		_result_wait_banner.add_theme_stylebox_override("panel", _result_wait_style)
	else:
		_result_wait_label.text = "ALL PLAYERS FINISHED"
		_result_wait_banner.add_theme_stylebox_override("panel", _result_done_style)


func _on_pause_visibility_changed() -> void:
	if _result_root == null or not _result_root.visible:
		return
	var pause_menu: Control = get_node_or_null("PauseMenu/Root") as Control
	var pause_open: bool = pause_menu != null and pause_menu.visible
	if pause_open:
		_result_root.remove_from_group("nav_scope")
	elif not _result_root.is_in_group("nav_scope"):
		_result_root.add_to_group("nav_scope")
	var menu_nav: Node = get_node_or_null("/root/MenuNav")
	if menu_nav != null:
		menu_nav.call("refresh")


func _waiting_peer_count() -> int:
	if not _multiplayer:
		return 0
	# Canonical standings are the waiting source once they exist: the host has
	# already force-finalised them after the settle deadline, so a lost final
	# state packet can no longer pin the result card on "WAITING FOR ...".
	if not _standings_snapshot.is_empty():
		if bool(_standings_snapshot.get("final", false)):
			return 0
		var local_id: int = multiplayer.get_unique_id()
		var canonical_waiting: int = 0
		for row_value: Variant in (_standings_snapshot.get("rows", []) as Array):
			if not (row_value is Dictionary):
				continue
			var row: Dictionary = row_value as Dictionary
			if int(row.get("id", 0)) == local_id:
				continue
			if not bool(row.get("finished", false)):
				canonical_waiting += 1
		return canonical_waiting
	var local_id: int = multiplayer.get_unique_id()
	var waiting: int = 0
	for peer_id: int in Network.participants():
		if peer_id == local_id:
			continue
		# A peer that returned to the lobby is still connected but no longer
		# in this race scene. Do not wait on it forever. Clients only track the
		# host in scene_ready_peers, so use the progress table there instead.
		if Network.is_host:
			if not Network.is_scene_ready(peer_id):
				continue
		elif not _remote_progress.has(peer_id):
			continue
		if not _remote_finished(peer_id):
			waiting += 1
	return waiting


func _race_finish_distance() -> float:
	if _spline == null:
		return 0.0
	# Progress is absolute track distance and starts at START_DISTANCE (the
	# grid sits before the line), so the finish is START_DISTANCE + 3 laps.
	# The old value (3 laps only) made the player and every result threshold
	# finish 8 m early relative to the rivals.
	return START_DISTANCE + float(_total_laps) * _spline.total_length


func _best_lap_time() -> float:
	if _lap_times.is_empty():
		return -1.0
	var best: float = _lap_times[0]
	for time: float in _lap_times:
		best = minf(best, time)
	return best


func _last_lap_time() -> float:
	## The lap just completed, 0 when no lap has run. The Pi's final report
	## wants this lap time, not the accumulated race clock.
	if _lap_times.is_empty():
		return 0.0
	return _lap_times[_lap_times.size() - 1]


func _fill_result_laps() -> void:
	for child: Node in _result_lap_rows.get_children():
		_result_lap_rows.remove_child(child)
		child.queue_free()
	var best_index: int = -1
	var best_time: float = -1.0
	for index in mini(_lap_times.size(), _total_laps):
		if best_time < 0.0 or _lap_times[index] < best_time:
			best_time = _lap_times[index]
			best_index = index
	for index in _total_laps:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiKit.SPACING_TIGHT)
		var caption := Label.new()
		caption.text = "LAP %d" % (index + 1)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.add_theme_font_size_override("font_size", 16)
		caption.add_theme_color_override("font_color",
			UiPalette.YELLOW if index == best_index else UiPalette.TEXT_DIM)
		row.add_child(caption)
		var value := Label.new()
		value.custom_minimum_size = Vector2(96, 0)
		value.text = _format_time(_lap_times[index]) if index < _lap_times.size() else "—"
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 16)
		value.add_theme_color_override("font_color",
			UiPalette.YELLOW if index == best_index else UiPalette.CREAM)
		row.add_child(value)
		var delta := Label.new()
		delta.custom_minimum_size = Vector2(76, 0)
		delta.text = "—"
		delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		delta.add_theme_font_size_override("font_size", 14)
		delta.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		if index > 0 and index < _lap_times.size():
			var change: float = _lap_times[index] - _lap_times[index - 1]
			delta.text = _format_lap_delta(change)
			if change < -0.005:
				delta.add_theme_color_override("font_color", UiPalette.GRASS)
			elif change > 0.005:
				delta.add_theme_color_override("font_color", UiPalette.RED)
		row.add_child(delta)
		_result_lap_rows.add_child(row)


func _format_lap_delta(seconds: float) -> String:
	## Clean readout shared by the lap toast and the result table: two
	## decimals, a real sign, and a single 0.00 for an exact repeat.
	if absf(seconds) < 0.005:
		return "0.00"
	return ("+%.2f" if seconds > 0.0 else "−%.2f") % absf(seconds)


func _toast(text: String, duration: float) -> void:
	_toast_label.text = text
	_toast_label.visible = true
	_toast_timer = duration


func _callout(text: String, color: Color = UiPalette.YELLOW,
		duration: float = 2.2) -> void:
	if _callout_label == null:
		return
	_callout_label.text = text
	_callout_label.add_theme_color_override("font_color", color)
	_callout_label.visible = true
	_callout_timer = duration
	_pop_label(_callout_label)


func _set_wrong_way(active: bool) -> void:
	if _wrong_way_active == active:
		return
	_wrong_way_active = active
	if not active:
		_wrong_way_timer = 0.0
		_wrong_way_flash = 0.0
	if _hud != null and _hud.has_method("set_wrong_way"):
		_hud.call("set_wrong_way", active)
		if _wrong_way_label != null:
			_wrong_way_label.visible = false
	elif _wrong_way_label != null:
		_wrong_way_label.visible = active
		if active:
			_pop_label(_wrong_way_label)


func _pop_label(label: Label) -> void:
	label.scale = Vector2.ONE * 1.25
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --------------------------------------------------------------------------
# multiplayer ghosts (host-authoritative start, peers own their carts)


func _setup_multiplayer() -> void:
	_multiplayer = true
	_is_host = Network.is_host
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_NET setup peers=", multiplayer.get_peers(), " host=", _is_host)
	var my_id: int = multiplayer.get_unique_id()
	var my_vehicle: String = Network.effective_vehicle_for(my_id, "racing")
	if _is_host:
		_race_vehicle = my_vehicle
	_peer_vehicles[my_id] = my_vehicle
	if _cart != null:
		_cart.reapply_vehicle(my_vehicle, Network.effective_racer_color_for(my_id),
			Network.effective_racing_allocation_for(my_id))
		_base_max_speed = _cart.max_speed
	_place_local_on_grid()
	_setup_props_net()
	for peer_id: int in multiplayer.get_peers():
		_spawn_remote(peer_id)
	multiplayer.peer_connected.connect(_on_net_peer_connected)
	multiplayer.peer_disconnected.connect(_on_net_peer_disconnected)
	Network.names_changed.connect(_refresh_net_names)
	Network.tag_colors_changed.connect(_refresh_net_names)
	Network.notify_scene_ready(self, Network.RACE_SCENE)
	if Network.server_race_supported() and Network.relay_base != "":
		Network.sync_server_clock()
	if _is_host:
		if Network.is_shared_vehicle_mode():
			for target: int in multiplayer.get_peers():
				if Network.is_scene_ready(target):
					rpc_id(target, "_net_force_race_vehicle", _race_vehicle)
		_broadcast_race_vehicle(my_id, _race_vehicle)
	elif Network.is_scene_ready(1):
		rpc_id(1, "_net_race_ready", my_vehicle)


func _place_local_on_grid() -> void:
	if _cart == null:
		return
	var ids: Array[int] = Network.participants()
	var found: int = ids.find(multiplayer.get_unique_id())
	# A missing id used to collapse every peer onto slot 0, stacking spawns.
	var index: int = found if found >= 0 else absi(multiplayer.get_unique_id()) % 8
	var row: int = index / 2
	var column: int = index % 2
	var start_s: float = START_DISTANCE - float(row) * 4.5
	var col_lat: float = (-0.36 + float(column) * 0.72) * _road_half
	var spawn: Transform3D = _track_transform(start_s, col_lat)
	_cart.set_spawn_transform(spawn)
	_cart.global_transform = spawn
	_cart.velocity = Vector3.ZERO
	_last_cart_pos = _cart.global_position
	_start_s = start_s
	_prev_s = start_s
	_unwrapped = start_s


func _on_net_peer_connected(peer_id: int) -> void:
	_spawn_remote(peer_id)


func _on_net_peer_disconnected(peer_id: int) -> void:
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_NET disconnected peer=", peer_id, " peers=", multiplayer.get_peers())
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null:
		cart.queue_free()
		_remote_carts.erase(peer_id)
	_peer_vehicles.erase(peer_id)
	_name_labels.erase(peer_id)
	_remote_progress.erase(peer_id)
	_remote_progress_ms.erase(peer_id)
	_remote_finish_time.erase(peer_id)
	_remote_finish_provisional.erase(peer_id)
	_peer_result_extra.erase(peer_id)
	_race_relay_ms.erase(peer_id)


func _spawn_remote(peer_id: int) -> void:
	if _remote_carts.has(peer_id) or peer_id == multiplayer.get_unique_id():
		return
	var ids: Array[int] = Network.participants()
	var index: int = maxi(ids.find(peer_id), 0)
	var row: int = index / 2
	var column: int = index % 2
	# 0.05 sits the ghost ON the dirt road (top at 0.04): ghosts run no physics,
	# so anything higher leaves them hovering in the air until the first sync.
	var spawn: Transform3D = _track_transform(START_DISTANCE - float(row) * 4.5,
		-2.6 + float(column) * 5.2, 0.02 if _use_grid else 0.05)
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	# Transform before add_child: otherwise the body starts at the world origin
	# for one physics tick and shoves every cart already near it.
	cart.transform = spawn
	add_child(cart)
	cart.setup_remote(peer_id)
	cart.net_position = cart.global_position
	cart.net_yaw = cart.rotation.y
	var init_vid: String = str(_peer_vehicles.get(peer_id,
		Network.effective_vehicle_for(peer_id, "racing")))
	if init_vid == "" and peer_id == 1 and _race_vehicle != "":
		init_vid = _race_vehicle
	if init_vid != "":
		cart.set_vehicle_id(init_vid, Network.effective_racer_color_for(peer_id),
			Network.effective_racing_allocation_for(peer_id))
	var label := Label3D.new()
	label.text = Network.name_of(peer_id)
	label.font = load(TITLE_FONT)
	label.font_size = 42
	label.pixel_size = 0.0062
	label.outline_size = 13
	label.outline_modulate = UiPalette.OUTLINE
	label.modulate = Network.color_of(peer_id)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.05, 0.0)
	cart.add_child(label)
	_name_labels[peer_id] = label
	_remote_carts[peer_id] = cart
	_remote_progress[peer_id] = START_DISTANCE - float(row) * 4.5
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_NET remote=", peer_id, " vehicle=", _peer_vehicles.get(peer_id, "?"))
	if _cart != null:
		var camera := _cart.get_node_or_null("CameraArm/Camera3D") as Camera3D
		if camera != null:
			camera.current = true


func _refresh_net_names() -> void:
	for peer_id: int in _name_labels:
		var label: Label3D = _name_labels[peer_id]
		if is_instance_valid(label):
			label.text = Network.name_of(peer_id)
			label.modulate = Network.color_of(peer_id)


func _cart_idle_skip(peer_id: int, position: Vector3, yaw: float, velocity: Vector3) -> bool:
	if Vector2(velocity.x, velocity.z).length() >= CART_IDLE_SPEED:
		_cart_idle_ms[peer_id] = Time.get_ticks_msec()
		_cart_idle_pos[peer_id] = position
		_cart_idle_yaw[peer_id] = yaw
		return false
	var now: int = Time.get_ticks_msec()
	var last_ms: int = int(_cart_idle_ms.get(peer_id, -100000))
	var last_pos: Vector3 = _cart_idle_pos.get(peer_id, position)
	var last_yaw: float = float(_cart_idle_yaw.get(peer_id, yaw))
	if position.distance_squared_to(last_pos) > 0.0004 or absf(angle_difference(last_yaw, yaw)) > 0.01:
		_cart_idle_ms[peer_id] = now
		_cart_idle_pos[peer_id] = position
		_cart_idle_yaw[peer_id] = yaw
		return false
	if now - last_ms < int(CART_IDLE_INTERVAL * 1000.0):
		return true
	_cart_idle_ms[peer_id] = now
	_cart_idle_pos[peer_id] = position
	_cart_idle_yaw[peer_id] = yaw
	return false


func _broadcast_race_state(peer_id: int, position: Vector3, yaw: float,
		progress: float, sent_ms: int = 0,
		velocity: Vector3 = Vector3.ZERO) -> void:
	if _cart_idle_skip(peer_id, position, yaw, velocity):
		return
	if sent_ms <= 0:
		sent_ms = Time.get_ticks_msec()
	for target: int in multiplayer.get_peers():
		if target == peer_id:
			continue
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_race_cart_state", peer_id, position, yaw, progress, sent_ms, velocity)


func _broadcast_race_vehicle(peer_id: int, vehicle_id: String) -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_race_vehicle", peer_id, vehicle_id)


@rpc("any_peer", "reliable")
func _net_race_ready(vehicle_id: String) -> void:
	var sender: int = _rpc_sender()
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_NET ready from=", sender, " vehicle=", vehicle_id)
	if sender <= 1 or sender == multiplayer.get_unique_id():
		return
	Network.mark_peer_scene_ready(sender)
	# WS5-10: the standings keepalive stops once a snapshot is final, so a peer
	# that finished loading late would never receive the canonical result. Send
	# the current snapshot directly now that the peer can receive scene RPCs.
	if _is_host and not _standings_snapshot.is_empty():
		rpc_id(sender, "_net_standings", int(_standings_snapshot.get("epoch", 0)),
			int(_standings_snapshot.get("rev", 0)),
			_standings_snapshot.get("rows", []) as Array,
			bool(_standings_snapshot.get("final", false)))
	var clean_vid: String = _race_vehicle if (_is_host and Network.is_shared_vehicle_mode()) \
		else GameSettings.sanitize_racing_vehicle_id(vehicle_id)
	_store_net_vehicle(sender, clean_vid)
	if _is_host and not _waiting_for_peers:
		if _server_race_active:
			rpc_id(sender, "_net_server_race_start", _server_race_id,
				_server_race_secret, _server_start_ms, _rivals.size())
		elif _phase == Phase.COUNTDOWN:
			rpc_id(sender, "_net_race_countdown", maxf(_countdown, 0.1))
		elif _phase == Phase.RACING or _phase == Phase.FINISHED:
			# The host already started (or finished) while this peer was still
			# loading. Release its WAITING screen; a finished host still lets a
			# late loader drive instead of freezing on an empty track.
			rpc_id(sender, "_net_race_join_now")
	if not _is_host:
		return
	if Network.is_shared_vehicle_mode():
		rpc_id(sender, "_net_force_race_vehicle", _race_vehicle)
	else:
		_broadcast_race_vehicle(sender, clean_vid)
	for peer_id: Variant in _peer_vehicles.keys():
		rpc_id(sender, "_net_race_vehicle", int(peer_id), str(_peer_vehicles[peer_id]))
	# If this was the last peer we were waiting for, begin the countdown now.
	if _waiting_for_peers and not _server_race_pending:
		var all_ready: bool = true
		for peer_id: int in multiplayer.get_peers():
			if not Network.is_scene_ready(peer_id):
				all_ready = false
				break
		if all_ready:
			_begin_race_countdown()


@rpc("authority", "reliable")
func _net_race_vehicle(peer_id: int, vehicle_id: String) -> void:
	_store_net_vehicle(peer_id, vehicle_id)


func _store_net_vehicle(peer_id: int, vehicle_id: String) -> void:
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_NET store peer=", peer_id, " vehicle=", vehicle_id)
	if vehicle_id.length() > 64:
		return
	var norm_id: String = VehicleCatalog.normalize_id(vehicle_id)
	if VehicleCatalog.find(norm_id).is_empty():
		return
	if peer_id == 1 and not _is_host:
		_peer_vehicles[1] = norm_id
		var host_cart: CartPlayer = _remote_carts.get(1)
		if host_cart != null:
			host_cart.set_vehicle_id(norm_id, Network.effective_racer_color_for(1),
				Network.effective_racing_allocation_for(1))
		if Network.is_shared_vehicle_mode():
			_apply_forced_vehicle(norm_id)
		return
	_peer_vehicles[peer_id] = norm_id
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null:
		cart.set_vehicle_id(norm_id, Network.effective_racer_color_for(peer_id),
			Network.effective_racing_allocation_for(peer_id))


func _apply_forced_vehicle(vehicle_id: String) -> void:
	## Client side (SHARED mode only): switch the LOCAL race cart to the host's car.
	var norm_id: String = VehicleCatalog.normalize_id(vehicle_id)
	if _race_vehicle == norm_id \
			and str(_peer_vehicles.get(multiplayer.get_unique_id(), "")) == norm_id:
		return
	_race_vehicle = norm_id
	_peer_vehicles[multiplayer.get_unique_id()] = norm_id
	if _cart != null:
		_cart.reapply_vehicle(norm_id, Network.effective_racer_color_for(1),
			Network.effective_racing_allocation_for(1))
		_base_max_speed = _cart.max_speed
	for rival: Dictionary in _rivals:
		var node: CartPlayer = rival["node"]
		node.reapply_vehicle(norm_id)
		rival["vehicle"] = norm_id


@rpc("authority", "call_local", "reliable")
func _net_force_race_vehicle(vehicle_id: String) -> void:
	if _is_host or not Network.is_shared_vehicle_mode():
		return
	_apply_forced_vehicle(vehicle_id)


func _on_horn_requested() -> void:
	## Local cart already honked; share it with the room.
	var my_id: int = multiplayer.get_unique_id()
	if _is_host:
		_broadcast_horn(my_id, 0)
	elif Network.is_scene_ready(1):
		rpc_id(1, "_net_horn", my_id)


func _broadcast_horn(peer_id: int, except_id: int) -> void:
	for target: int in multiplayer.get_peers():
		if target != except_id and Network.is_scene_ready(target):
			rpc_id(target, "_net_horn", peer_id)


@rpc("any_peer", "reliable")
func _net_horn(peer_id: int) -> void:
	var sender: int = _rpc_sender()
	if sender != 1 and peer_id != sender:
		return
	if peer_id == multiplayer.get_unique_id():
		return
	var now: int = Time.get_ticks_msec()
	if now - int(_horn_stamp.get(peer_id, -10000)) < 140:
		return
	_horn_stamp[peer_id] = now
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null:
		cart.honk()
	if _is_host and sender != 1:
		_broadcast_horn(peer_id, sender)


@rpc("any_peer", "unreliable")
func _net_race_cart_state(peer_id: int, position: Vector3, yaw: float,
		progress: float, sent_ms: int = 0,
		velocity: Vector3 = Vector3.ZERO) -> void:
	var sender: int = _rpc_sender()
	if sender != 1 and peer_id != sender:
		return
	# The host relays a client's packet to every ready peer, including its
	# sender. Storing your own echo creates a phantom self entry in the
	# standings (and a duplicate result row), so ignore it.
	if peer_id == multiplayer.get_unique_id():
		return
	if not position.is_finite() or not is_finite(yaw) or not is_finite(progress) \
			or not velocity.is_finite():
		return
	if position.length_squared() > 5000.0 * 5000.0:
		return
	if sent_ms < 0:
		return
	# Drop a reordered datagram before it can move the ghost or the standings
	# backwards. The sender's own clock makes the stamp comparable per peer.
	var newest: int = int(_remote_progress_ms.get(peer_id, -1))
	if sent_ms > 0 and sent_ms <= newest:
		if newest - sent_ms <= NET_CLOCK_RESET_MS:
			return
		# Sender restarted its process or sent one absurd stamp. Accept the
		# new baseline instead of rejecting every later packet forever.
		newest = -1
	if sent_ms > 0:
		_remote_progress_ms[peer_id] = sent_ms
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null and cart.remote_mode:
		_accept_remote_race_state(peer_id, cart, position, yaw, progress,
			sent_ms, velocity, newest)
	if _is_host and sender != 1:
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - int(_race_relay_ms.get(peer_id, -10000)) >= 20:
			_race_relay_ms[peer_id] = now_ms
			_broadcast_race_state(peer_id, position, yaw,
				float(_remote_progress.get(peer_id, progress)), sent_ms, velocity)


func _accept_remote_race_state(peer_id: int, cart: CartPlayer, position: Vector3,
		yaw: float, progress: float, sent_ms: int, velocity: Vector3,
		previous_stamp: int) -> void:
	## The timestamped, bounded progress pipeline shared by the RPC above and
	## the focused headless regression test.
	cart.set_net_state(position, yaw, sent_ms, velocity)
	var limit: float = float(_total_laps + 1) * _spline.total_length
	var previous: float = float(_remote_progress.get(peer_id, progress))
	# A peer reports its own lap distance. Bound the jump by the elapsed
	# sender time and the cart's real top speed, so a dropped packet still
	# catches up but a modified client cannot gain 8 m every 50 ms.
	var elapsed_s: float = 0.05
	if sent_ms > 0 and previous_stamp >= 0:
		elapsed_s = clampf(float(sent_ms - previous_stamp) / 1000.0, 0.05, 2.0)
	var max_step: float = 12.0
	if _cart != null:
		max_step = _cart.max_speed * elapsed_s * 1.5 + 1.0
	var clamped_progress: float = clampf(progress, maxf(previous - max_step, 0.0),
		minf(previous + max_step, limit))
	_remote_progress[peer_id] = clamped_progress
	# Remote progress is lap-relative once the cart crosses the start line
	# (the first crossing subtracts the grid offset). Use the same finish
	# distance as the local placement code, or a finished ghost stays solid.
	var finish_line: float = _race_finish_distance()
	if clamped_progress >= finish_line - 2.0:
		# A crossed cart is not an obstacle, and it must stay that way even
		# though it keeps streaming state until the race ends. This stream is
		# unreliable and sampled at 20 Hz, so the stamp it leaves is a
		# provisional fallback only: the reliable _net_report_finish owns the
		# ordering time and overwrites it (WS5-02).
		if not _remote_finish_provisional.has(peer_id):
			_remote_finish_provisional[peer_id] = _race_time
		if not _remote_finish_time.has(peer_id):
			_remote_finish_time[peer_id] = _race_time
			if _is_host:
				# Publish the live order now; the reliable report re-broadcasts
				# a corrected revision for every peer.
				_broadcast_standings(_all_humans_finished())
		cart.mark_race_finished()


# --------------------------------------------------------------------------
# host-authoritative props and bots


func _setup_props_net() -> void:
	for node in get_tree().get_nodes_in_group("pushable"):
		if node is RigidBody3D:
			_props.append(node as RigidBody3D)
	_props.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool: return str(a.name) < str(b.name))
	if _cart != null and not _cart.net_push_requested.is_connected(_on_local_push_requested):
		_cart.net_push_requested.connect(_on_local_push_requested)
	if not _is_host:
		for prop: RigidBody3D in _props:
			prop.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			prop.freeze = true


func _on_local_push_requested(prop: Node, direction: Vector3, kick: float) -> void:
	if _is_host or not _multiplayer:
		return
	var index: int = _props.find(prop as RigidBody3D)
	if index < 0:
		return
	# Predict locally so the cone flies on this screen too; the host stays
	# authoritative and the next snapshot corrects the pose.
	_kick_prop(prop as RigidBody3D, direction, kick)
	if Network.is_scene_ready(1):
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
	prop.apply_central_impulse(direction * prop.mass * kick + Vector3.UP * prop.mass * kick * 0.85)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0))
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


func _broadcast_props() -> void:
	if _props.is_empty():
		return
	var positions := PackedVector3Array()
	var rotations := PackedVector4Array()
	for prop: RigidBody3D in _props:
		if not is_instance_valid(prop):
			positions.append(Vector3.ZERO)
			rotations.append(Vector4(0.0, 0.0, 0.0, 1.0))
			continue
		positions.append(prop.global_position)
		var basis: Basis = prop.global_transform.basis.orthonormalized()
		var turn: Quaternion = basis.get_rotation_quaternion().normalized()
		rotations.append(Vector4(turn.x, turn.y, turn.z, turn.w))
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_props", positions, rotations)


func _apply_prop_targets(delta: float) -> void:
	if _prop_targets.is_empty():
		return
	var blend: float = 1.0 - exp(-12.0 * delta)
	for index: int in _prop_targets:
		if index < 0 or index >= _props.size():
			continue
		var prop: RigidBody3D = _props[index]
		if not is_instance_valid(prop):
			continue
		if _prop_kick_until.has(prop.get_instance_id()):
			continue
		var data: Array = _prop_targets[index]
		prop.global_position = prop.global_position.lerp(data[0] as Vector3, blend)
		var packed: Vector4 = data[1] as Vector4
		var target_turn := Quaternion(packed.x, packed.y, packed.z, packed.w)
		if target_turn.length_squared() < 0.5:
			continue
		var current: Quaternion = prop.global_transform.basis \
			.get_rotation_quaternion()
		var turn: Quaternion = current.slerp(target_turn.normalized(), blend)
		var xform: Transform3D = prop.global_transform
		xform.basis = Basis(turn)
		prop.global_transform = xform


@rpc("authority", "unreliable")
func _net_props(positions: PackedVector3Array,
		rotations: PackedVector4Array) -> void:
	if _is_host or not _multiplayer:
		return
	if positions.size() > _props.size() or rotations.size() < positions.size():
		return
	for index in positions.size():
		if not positions[index].is_finite() or not rotations[index].is_finite():
			continue
		_prop_targets[index] = [positions[index], rotations[index]]


@rpc("any_peer", "reliable")
func _net_request_push(index: int, direction: Vector3, kick: float) -> void:
	if not _is_host or index < 0 or index >= _props.size():
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
	_kick_prop(_props[index], direction, kick)


func _broadcast_bot_states() -> void:
	if _rivals.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var all_idle: bool = true
	for rival: Dictionary in _rivals:
		var node: CartPlayer = rival["node"]
		var vel: Vector3 = node.velocity if is_instance_valid(node) else Vector3.ZERO
		if Vector2(vel.x, vel.z).length() >= CART_IDLE_SPEED:
			all_idle = false
			break
	if all_idle and now - _bot_idle_ms < int(CART_IDLE_INTERVAL * 1000.0):
		return
	_bot_idle_ms = now
	var positions := PackedVector3Array()
	var yaws := PackedFloat32Array()
	var velocities := PackedVector3Array()
	var progresses := PackedFloat32Array()
	for rival: Dictionary in _rivals:
		var node: CartPlayer = rival["node"]
		if not is_instance_valid(node):
			positions.append(Vector3.ZERO)
			yaws.append(0.0)
			velocities.append(Vector3.ZERO)
			progresses.append(float(rival["progress"]))
			continue
		positions.append(node.global_position)
		yaws.append(node.rotation.y)
		velocities.append(node.velocity.limit_length(60.0))
		progresses.append(float(rival["progress"]))
	var stamp: int = Time.get_ticks_msec()
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_bot_states", positions, yaws, velocities, progresses, stamp)


@rpc("authority", "unreliable")
func _net_bot_states(positions: PackedVector3Array, yaws: PackedFloat32Array,
		velocities: PackedVector3Array, progresses: PackedFloat32Array,
		sent_ms: int) -> void:
	if _is_host or not _multiplayer or _server_race_active:
		return
	var count: int = mini(positions.size(), _rivals.size())
	if yaws.size() < count or velocities.size() < count or progresses.size() < count:
		return
	var finish: float = _race_finish_distance()
	for i in count:
		var position: Vector3 = positions[i]
		if not position.is_finite() or not is_finite(yaws[i]) \
				or not velocities[i].is_finite() or not is_finite(progresses[i]):
			continue
		var rival: Dictionary = _rivals[i]
		var node: CartPlayer = rival["node"]
		if not is_instance_valid(node) or not node.remote_mode:
			continue
		node.set_net_state(position, yaws[i], sent_ms, velocities[i])
		rival["progress"] = progresses[i]
		if not bool(rival["finished"]) and progresses[i] >= finish - 2.0:
			rival["finished"] = true
			if float(rival["finish_time"]) < 0.0:
				rival["finish_time"] = _race_time
			node.mark_race_finished()


# --------------------------------------------------------------------------
# host-authoritative final standings
#
# Root cause this fixes: every peer used to rank the field from its own
# unreliable progress feed and from `_race_time` sampled when a finish packet
# happened to arrive, so close finishes (and any dropped final packet) produced
# different final standings on different screens. Now the host latches the
# crossing order, builds one canonical snapshot and every client renders it.


func _canonical_standings_rows() -> Array:
	## Host only: one row per competitor from the host's authoritative view.
	var rows: Array = []
	if _cart == null:
		return rows
	var local_id: int = multiplayer.get_unique_id() if _multiplayer else 0
	rows.append(_canonical_human_row(local_id))
	for peer_id: int in _remote_progress:
		if peer_id == local_id:
			continue
		rows.append(_canonical_human_row(peer_id))
	for index in _rivals.size():
		var rival: Dictionary = _rivals[index]
		var label: Label3D = rival["label"] as Label3D
		rows.append({
			"id": -1 - index,
			"name": label.text if label != null else "RIVAL %d" % (index + 1),
			"finished": bool(rival["finished"]),
			"finish_time": float(rival["finish_time"]),
			"progress": float(rival["progress"]),
			"total": -1.0,
			"best": -1.0,
		})
	return rows


func _canonical_human_row(peer_id: int) -> Dictionary:
	var local_id: int = multiplayer.get_unique_id() if _multiplayer else 0
	var finished: bool
	var finish_time: float
	var progress: float
	var total: float = -1.0
	var best: float = -1.0
	if peer_id == local_id:
		finished = _finish_time >= 0.0
		finish_time = _finish_time if finished else -1.0
		progress = _unwrapped
		total = _race_time if finished else -1.0
		best = _best_lap_time()
	else:
		finished = _remote_finished(peer_id)
		finish_time = float(_remote_finish_time.get(peer_id, -1.0)) if finished else -1.0
		progress = float(_remote_progress.get(peer_id, 0.0))
		var extra: Dictionary = {}
		if _peer_result_extra.has(peer_id):
			extra = _peer_result_extra[peer_id] as Dictionary
		if finished:
			total = float(extra.get("total", -1.0))
			best = float(extra.get("best", -1.0))
	return {
		"id": peer_id,
		"name": Network.name_of(peer_id),
		"finished": finished,
		"finish_time": finish_time,
		"progress": progress,
		"total": total,
		"best": best,
	}


func _broadcast_standings(final: bool = false) -> void:
	## Host only. One reliable revisioned snapshot to every scene-ready peer.
	if not _is_host or not _multiplayer or not Network.is_session_active():
		return
	_standings_rev += 1
	var snapshot: Dictionary = StandingsReconciler.build(_standings_epoch,
		_standings_rev, _canonical_standings_rows(), final)
	_standings_snapshot = snapshot
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_standings", int(snapshot["epoch"]),
				int(snapshot["rev"]), snapshot["rows"] as Array,
				bool(snapshot["final"]))
	_apply_standings_snapshot(snapshot)


@rpc("authority", "reliable")
func _net_standings(epoch: int, rev: int, rows: Array, final: bool) -> void:
	## Client side. StandingsReconciler.accept() rejects stale/duplicate/older
	## revisions, so a reordered late packet can never move a finished place.
	if _is_host or not _multiplayer:
		return
	var incoming: Dictionary = {"epoch": epoch, "rev": rev, "rows": rows,
		"final": final}
	var merged: Dictionary = StandingsReconciler.accept(_standings_snapshot,
		incoming)
	if merged == _standings_snapshot:
		return
	_standings_snapshot = merged
	_apply_standings_snapshot(merged)
	if bool(merged.get("final", false)):
		_standings_finalized = true
		_refresh_result_standings()


func _apply_standings_snapshot(snapshot: Dictionary) -> void:
	## Mirror the canonical places onto the live HUD/result placement. The Pi's
	## official server-race result still owns the big placement when it exists
	## (_official_applied), but the standings rows always follow the snapshot.
	if snapshot.is_empty():
		return
	var places_map: Dictionary = StandingsReconciler.places(snapshot)
	var local_id: int = multiplayer.get_unique_id() if _multiplayer else 0
	if places_map.has(local_id):
		_hud_last_place = -1
		if _result_place != null and not _official_applied:
			var place: int = int(places_map[local_id])
			_result_place.text = "%s / %d" % [_ordinal(place), _field_size()]
			if _phase == Phase.FINISHED:
				_set_result_title(place)


static func compensated_finish_time(reported_s: float, one_way_ms: float,
		host_now_s: float, provisional_s: float) -> float:
	## WS5-02: turn a peer's reliable finish report into one canonical host-clock
	## crossing stamp (seconds). All ordering for human finishers goes through
	## this single value, so two finishes can no longer be ordered by the arrival
	## time of an unreliable 20 Hz packet.
	##
	## `reported_s` is the peer's own race time (its clock starts one
	## countdown-broadcast delay after the host's, hence the re-alignment),
	## `host_now_s` is the host clock when the report was processed and
	## `provisional_s` is the host clock when the progress stream first showed
	## the crossing (-1.0 when it never did). Pure so the ordering can be
	## asserted headlessly.
	var one_way_s: float = clampf(one_way_ms / 1000.0, 0.0, FINISH_ONE_WAY_MAX)
	var reported: float = clampf(reported_s, 0.0, 86400.0)
	var host_now: float = clampf(host_now_s, 0.0, 86400.0)
	var estimate: float = reported + one_way_s
	if provisional_s >= 0.0:
		# The progress latch sampled the host clock after the real crossing
		# (packet delay), so the compensated report may only slightly beat it.
		estimate = clampf(estimate, maxf(provisional_s - FINISH_PROGRESS_SLACK, 0.0),
			provisional_s + FINISH_PROGRESS_SLACK)
	else:
		# No progress sample to compare against: bound how far behind the report
		# may claim the crossing was, so a modified client cannot win by
		# reporting an implausibly short race.
		estimate = clampf(estimate,
			maxf(host_now - FINISH_REPORT_SLACK - one_way_s, 0.0), host_now)
	return estimate


@rpc("any_peer", "reliable")
func _net_report_finish(reported_total_s: float, reported_best_s: float) -> void:
	## Host side. A client's crossing is reported reliably: the unreliable final
	## state packet can be dropped, and its arrival time jitters by more than the
	## gap of a close finish. This report is the *authoritative* ordering source
	## for humans (WS5-02): it replaces any provisional stamp the progress stream
	## left, delay-compensated onto the host clock. Only the first report per peer
	## per race is accepted, so a duplicate re-report cannot reorder the field.
	if not _is_host or not _multiplayer:
		return
	var sender: int = _rpc_sender()
	if sender <= 1 or not _remote_carts.has(sender):
		return
	if not is_finite(reported_total_s) or not is_finite(reported_best_s):
		return
	if _peer_result_extra.has(sender):
		# Already latched for this race: monotonic, first report wins.
		return
	var provisional: float = float(_remote_finish_provisional.get(sender, -1.0))
	_remote_finish_time[sender] = compensated_finish_time(reported_total_s,
		float(Network.peer_rtt_ms(sender)) * 0.5, _race_time, provisional)
	_remote_finish_provisional.erase(sender)
	var extra: Dictionary = {}
	extra["total"] = clampf(reported_total_s, 0.0, 86400.0)
	extra["best"] = clampf(reported_best_s, 0.0, 86400.0)
	_peer_result_extra[sender] = extra
	var cart: CartPlayer = _remote_carts.get(sender) as CartPlayer
	if cart != null and is_instance_valid(cart):
		cart.mark_race_finished()
	_broadcast_standings(_all_humans_finished())


func _all_humans_finished() -> bool:
	if not _multiplayer:
		return true
	if _finish_time < 0.0:
		return false
	var local_id: int = multiplayer.get_unique_id()
	for peer_id: int in Network.participants():
		if peer_id == local_id:
			continue
		if Network.is_host and not Network.is_scene_ready(peer_id):
			continue
		# Only the reliable report finalises a human place; the provisional
		# progress latch is not enough, or the terminal final snapshot could
		# freeze an arrival-jittered order (WS5-02). A lost report is covered by
		# STANDINGS_FINALIZE_TIMEOUT in _tick_standings.
		if not _peer_result_extra.has(peer_id):
			return false
	return true


func _tick_standings(delta: float) -> void:
	## Host re-broadcast/keepalive loop. Runs from _process once any finish has
	## been latched, so a client that crossed the line while the host was still
	## racing also sees the updated order on its waiting result card.
	if not _is_host or not _multiplayer or _standings_finalized:
		return
	if _finish_time < 0.0 and _remote_finish_time.is_empty():
		return
	_standings_timer += delta
	if _phase == Phase.FINISHED:
		_standings_wait += delta
	var final: bool = _phase == Phase.FINISHED \
		and (_all_humans_finished() or _standings_wait >= STANDINGS_FINALIZE_TIMEOUT)
	if final or _standings_timer >= STANDINGS_BROADCAST_INTERVAL:
		_standings_timer = 0.0
		_broadcast_standings(final)
		if final:
			_standings_finalized = true


func _entries_from_standings(local_entries: Array[Dictionary]) -> Array[Dictionary]:
	## Merge the canonical snapshot over the locally built rows: the snapshot
	## owns order, finish state and times; local rows fill in colour/(YOU)/best
	## for competitors the snapshot does not mention.
	var by_id: Dictionary = {}
	for entry: Dictionary in local_entries:
		by_id[int(entry["id"])] = entry
	var ordered: Array[Dictionary] = []
	var used: Dictionary = {}
	var rows: Array = _standings_snapshot.get("rows", []) as Array
	for row_value: Variant in rows:
		if not (row_value is Dictionary):
			continue
		var row: Dictionary = row_value as Dictionary
		var id: int = int(row.get("id", 0))
		if not by_id.has(id) or used.has(id):
			continue
		used[id] = true
		var entry: Dictionary = by_id[id]
		entry["finished"] = bool(row.get("finished", false))
		entry["finish_time"] = float(row.get("finish_time", -1.0))
		entry["progress"] = float(row.get("progress", 0.0))
		if float(row.get("total", -1.0)) >= 0.0:
			entry["total"] = float(row["total"])
		if float(row.get("best", -1.0)) >= 0.0:
			entry["best"] = float(row["best"])
		ordered.append(entry)
	# Anything the snapshot did not cover keeps the local deterministic order.
	var leftovers: Array[Dictionary] = []
	for entry: Dictionary in local_entries:
		if not used.has(int(entry["id"])):
			leftovers.append(entry)
	leftovers.sort_custom(Callable(self, "_standings_before"))
	ordered.append_array(leftovers)
	for index in ordered.size():
		ordered[index]["place"] = index + 1
	return ordered




# --------------------------------------------------------------------------
# race loop


func _physics_process(delta: float) -> void:
	# Contact impulses, AI inputs, lap progress and the race clock are all
	# fixed-step work. Running them from _process made bumps, AI and lap timing
	# depend on the render rate.
	if _multiplayer and _is_host and _cart != null:
		Network.resolve_car_collisions(_cart, _remote_carts)
	if _multiplayer and Network.is_session_active():
		if _is_host:
			_prop_sync_timer += delta
			if _prop_sync_timer >= PROP_SYNC_INTERVAL:
				_prop_sync_timer = 0.0
				_broadcast_props()
		else:
			_expire_prop_kicks()
			_apply_prop_targets(delta)
	if _waiting_for_peers:
		# Keep the authored default countdown out of the physics tick until the
		# host has actually started the race (local or server-owned).
		return
	match _phase:
		Phase.COUNTDOWN:
			_tick_countdown(delta)
		Phase.RACING:
			_tick_race(delta)


func _process(delta: float) -> void:
	# The start marshal and the transient barrier badge keep ticking in every
	# phase, including the wait for peers, so the grid never looks frozen.
	_animate_marshal(delta)
	if _impact_timer > 0.0:
		_impact_timer -= delta
		if _impact_timer <= 0.0 and _impact_label != null:
			_impact_label.visible = false
	if _callout_timer > 0.0:
		_callout_timer -= delta
		if _callout_timer <= 0.0 and _callout_label != null:
			_callout_label.visible = false
	if _wrong_way_active and _wrong_way_label != null and _wrong_way_label.visible:
		_wrong_way_flash += delta
		var flash_on: bool = fmod(_wrong_way_flash, 0.42) < 0.28
		_wrong_way_label.add_theme_color_override("font_color",
			UiPalette.RED if flash_on else UiPalette.YELLOW)
	if _waiting_for_peers:
		_wait_elapsed += delta
		if _is_host:
			var all_ready: bool = true
			for peer_id: int in multiplayer.get_peers():
				if not Network.is_scene_ready(peer_id):
					all_ready = false
					break
			if all_ready or _wait_elapsed >= 8.0:
				_begin_race_countdown()
		elif _multiplayer and Network.is_session_active() and Network.is_connected_to_server():
			_client_ready_retry_timer += delta
			if _client_ready_retry_timer >= 0.8:
				_client_ready_retry_timer = 0.0
				if Network.is_scene_ready(1):
					rpc_id(1, "_net_race_ready", Network.effective_vehicle_for(multiplayer.get_unique_id(), "racing"))
		return
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_label.visible = false
	if _multiplayer and _cart != null and _phase != Phase.FINISHED \
			and Network.is_session_active() and Network.is_connected_to_server():
		_net_sync_timer += delta
		if _net_sync_timer >= NET_SYNC_INTERVAL:
			_net_sync_timer = 0.0
			if _is_host:
				_broadcast_race_state(multiplayer.get_unique_id(),
					_cart.global_position, _cart.rotation.y, _unwrapped,
					Time.get_ticks_msec(), _cart.velocity)
			elif Network.is_scene_ready(1):
				rpc_id(1, "_net_race_cart_state", multiplayer.get_unique_id(),
					_cart.global_position, _cart.rotation.y, _unwrapped,
					Time.get_ticks_msec(), _cart.velocity)
	if _multiplayer and _is_host and Network.is_session_active() \
			and not _rivals.is_empty() and not _server_race_active:
		# Stream the bots even while the host sits on its result card: clients
		# are still racing and must see them keep driving.
		_bot_sync_timer += delta
		if _bot_sync_timer >= 0.05:
			_bot_sync_timer = 0.0
			_broadcast_bot_states()
	if _multiplayer and _is_host and _server_race_active \
			and _phase == Phase.RACING and Network.is_session_active() \
			and Network.is_connected_to_server():
		# The Pi-owned race gets one batched position snapshot every 100 ms.
		# Network.stream_race_state() drops a tick if the relay is still busy.
		_state_stream_timer += delta
		if _state_stream_timer >= STATE_STREAM_INTERVAL:
			_state_stream_timer = 0.0
			_push_server_state()
	# Host-owned final standings: re-broadcast while any finish is live, and
	# force-finalise after the settle deadline so no result card waits forever.
	_tick_standings(delta)
	match _phase:
		Phase.FINISHED:
			# Peers keep streaming their progress after we cross the line, so
			# the standings and the waiting banner stay live.
			if _multiplayer and _result_root != null and _result_root.visible:
				_result_refresh_timer += delta
				if _result_refresh_timer >= 0.5:
					_result_refresh_timer = 0.0
					_refresh_result_standings()


func _begin_race_countdown() -> void:
	if not _is_host:
		return
	if Network.server_race_supported() and Network.relay_token != "":
		# The Pi owns the clock and the bot field in multiplayer. Stay in the
		# WAITING state until the race exists; the physics tick must not run its
		# default 3 s countdown while the HTTP request is in flight.
		_begin_server_race()
		return
	_start_local_countdown(3.0)


func _reset_race_progress(force: bool = false) -> void:
	## One reset for every countdown path. A race that restarts inside the same
	## scene (server fallback, late join, re-issued start) must never inherit the
	## previous clock, laps, sector flags or finish bookkeeping. A normal
	## countdown never rewinds a cart that is already racing; an authoritative
	## server start does.
	if not force and (_phase == Phase.RACING or not _lap_times.is_empty()):
		return
	_race_time = 0.0
	_lap = 1
	_lap_start = 0.0
	_rejected_crossings = 0
	_lap_times.clear()
	_sector_flags = 0
	_last_sector = -1
	_skip_progress = true
	_prev_s = _spline.wrap_distance(_start_s) if _spline != null else _start_s
	_unwrapped = _start_s
	_off_timer = 0.0
	_was_off_track = false
	_barrier_cooldown = 0.0
	_last_forward_speed = 0.0
	_air_time = 0.0
	_fall_speed = 0.0
	_go_time = 0.0
	_finish_time = -1.0
	_remote_finish_time.clear()
	_remote_finish_provisional.clear()
	_official_applied = false
	_standings_snapshot = {}
	_standings_rev = 0
	_standings_timer = 0.0
	_standings_wait = 0.0
	_standings_finalized = false
	_finish_reported = false
	_peer_result_extra.clear()
	_impact_timer = 0.0
	if _impact_label != null:
		_impact_label.visible = false
	if _offtrack_label != null:
		_offtrack_label.visible = false
	_toast_timer = 0.0
	if _toast_label != null:
		_toast_label.visible = false
	_callout_timer = 0.0
	if _callout_label != null:
		_callout_label.visible = false
	_wrong_way_timer = 0.0
	_set_wrong_way(false)
	_set_start_lights(0, false)
	if _result_root != null:
		_result_root.visible = false
	for rival: Dictionary in _rivals:
		rival["finished"] = false
		rival["finish_time"] = -1.0
	if _hud != null:
		_hud_last_lap = -1
		_hud_last_place = -1
		_hud.call("set_lap", 1, _total_laps)
		_hud.call("set_race_time", 0.0, -1.0)


func _start_local_countdown(seconds: float) -> void:
	_reset_race_progress()
	_waiting_for_peers = false
	_countdown = maxf(seconds, 0.1)
	_last_count = 0
	_go_shown = false
	_phase = Phase.COUNTDOWN
	_countdown_label.visible = true
	_countdown_label.add_theme_color_override("font_color", UiPalette.YELLOW)
	_countdown_label.text = str(int(ceil(_countdown)))
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_COUNTDOWN_START host peers=", multiplayer.get_peers())
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_race_countdown", _countdown)


func _begin_server_race() -> void:
	if _server_race_pending or _server_race_active:
		return
	_server_race_pending = true
	var race: Dictionary = await Network.start_server_race(
		_total_laps, _bot_count(), GameSettings.minigame_difficulty,
		_base_max_speed, Network.race_seed)
	_server_race_pending = false
	if not is_inside_tree():
		return
	if race.is_empty():
		_start_local_countdown(3.0)
		return
	var race_id: String = str(race.get("id", ""))
	var secret: String = str(race.get("secret", ""))
	var start_ms: int = int(race.get("start_ms", 0))
	var bots: int = int(race.get("bots", 0))
	if race_id == "" or start_ms <= 0:
		_start_local_countdown(3.0)
		return
	_apply_server_race(race_id, secret, start_ms, bots)
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_server_race_start", race_id, secret, start_ms, bots)


@rpc("authority", "reliable")
func _net_server_race_start(race_id: String, secret: String,
		start_ms: int, bots: int) -> void:
	if _is_host:
		return
	if not Network.server_clock_ready:
		await Network.sync_server_clock(3)
	# The peer can leave the race while the clock sync is in flight.
	if not is_inside_tree():
		return
	_apply_server_race(race_id, secret, start_ms, bots)


func _apply_server_race(race_id: String, secret: String, start_ms: int,
		bots: int) -> void:
	_server_race_active = true
	_server_race_id = race_id
	_server_race_secret = secret
	_server_start_ms = start_ms
	_server_finished_reported = false
	_server_bots_pending = false
	_server_bots_timer = 0.0
	_waiting_for_peers = false
	# A client that could not sync the relay clock must not run the whole race
	# against a nonsense epoch: latch the fallback, derive a plain 3 s
	# countdown, and let the local clock drive the timer and the laps.
	_server_clock_ok = Network.server_clock_ready
	_reset_race_progress(true)
	_convert_rivals_to_server()
	var remaining: float = 3.0
	if _server_clock_ok:
		var raw_remaining: float = float(start_ms - Network.server_now_ms()) / 1000.0
		# Guard against wall-clock skew between a client and the Pi: if the
		# offset puts the countdown outside a plausible [-1.0, 8.0] window,
		# fall back to the local 3 s timer so the client never freezes on a
		# huge number or skips the countdown.
		if raw_remaining >= -1.0 and raw_remaining <= 8.0:
			remaining = clampf(raw_remaining, 0.1, 5.0)
		else:
			_server_clock_ok = false
			remaining = 3.0
	_countdown = remaining
	_last_count = 0
	_go_shown = false
	_phase = Phase.COUNTDOWN
	_countdown_label.visible = true
	_countdown_label.add_theme_color_override("font_color", UiPalette.YELLOW)
	_countdown_label.text = str(int(ceil(_countdown)))
	_state_stream_timer = 0.0
	# The shared HUD reads Network.relay_rtt_ms / race_state_receiving directly;
	# reset the counters so a new race starts at WAIT instead of the old RX.
	Network.reset_race_state_stream()
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_SERVER start id=", race_id, " start_ms=", start_ms,
			" remaining=", _countdown, " bots=", bots,
			" clock_ok=", _server_clock_ok)


func _convert_rivals_to_server() -> void:
	## From here on the rival bodies are ghosts driven only by the Pi snapshots.
	## A host that had been running local AI physics hands them over as well.
	var vehicle: String = _race_vehicle
	if vehicle == "":
		vehicle = GameSettings.minigame_vehicle
	for i in _rivals.size():
		var node: CartPlayer = _rivals[i]["node"]
		if not is_instance_valid(node):
			continue
		if not node.remote_mode:
			node.call("setup_remote", 1000 + i)
			node.set_vehicle_id(vehicle)
		_rivals[i]["progress"] = START_DISTANCE + 5.0 + float(i) * 4.5
		_rivals[i]["finished"] = false
		_rivals[i]["finish_time"] = -1.0
		# A sample from a previous race must never be extrapolated into this one.
		_rivals[i]["has_server_sample"] = false
		_rivals[i]["server_stamp_ms"] = 0
		var driver: RaceAI = _rivals[i]["driver"]
		if driver != null:
			driver.reset()


func _push_server_state() -> void:
	## Host only: one batch with every human cart. The Pi validates bounds and
	## progress before exposing a row; it never trusts an input blindly.
	if _cart == null or _server_race_id == "" or _server_race_secret == "":
		return
	if not Network.race_state_stream_enabled:
		# A 1.6.0 relay has no /api/race/pos. The race still runs from the
		# server clock and bot snapshots; only this position stream stays off.
		return
	var rows: Array = []
	var host_row: Array = _race_state_row(multiplayer.get_unique_id(), _cart,
		_unwrapped)
	if not host_row.is_empty():
		rows.append(host_row)
	for peer_id: int in _remote_carts:
		if not Network.is_scene_ready(peer_id):
			# A peer that returned to the lobby has no live cart state to send.
			continue
		var cart: CartPlayer = _remote_carts[peer_id]
		if not is_instance_valid(cart):
			continue
		var row: Array = _race_state_row(peer_id, cart,
			float(_remote_progress.get(peer_id, 0.0)))
		if not row.is_empty():
			rows.append(row)
	Network.stream_race_state(_server_race_id, _server_race_secret, rows)


func _race_state_row(peer_id: int, cart: CartPlayer, progress: float) -> Array:
	## [peer, x, y, z, vx, vy, vz, yaw, lap], the batch format /api/race/pos
	## validates. Lap is derived from absolute track progress so every peer
	## agrees with the host's unwrapped distance.
	var position: Vector3 = cart.global_position
	var velocity: Vector3 = cart.get_collision_velocity()
	var yaw: float = cart.global_rotation.y
	if not position.is_finite() or not velocity.is_finite() or not is_finite(yaw):
		return []
	var total: float = maxf(_spline.total_length, 1.0)
	# Match the Pi's own lap formula: the grid sits START_DISTANCE past the
	# line, so lap 1 is progress in [START, START + total). The old version
	# omitted the grid offset and reported the next lap 8 m early, which the
	# /api/race/pos validator could flag as progress.
	var lap: int = clampi(int(floor((progress - START_DISTANCE) / total)) + 1,
		1, _total_laps + 1)
	return [peer_id, position.x, position.y, position.z,
		velocity.x, velocity.y, velocity.z, yaw, lap]


@rpc("authority", "call_local", "reliable")
func _net_race_countdown(seconds: float) -> void:
	_reset_race_progress()
	_waiting_for_peers = false
	_countdown = maxf(seconds, 0.1)
	_last_count = 0
	_go_shown = false
	_phase = Phase.COUNTDOWN
	_countdown_label.visible = true
	_countdown_label.add_theme_color_override("font_color", UiPalette.YELLOW)
	_countdown_label.text = str(int(ceil(_countdown)))
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_COUNTDOWN_RECV seconds=", _countdown, " host=", _is_host)


@rpc("authority", "reliable")
func _net_race_join_now() -> void:
	## A lobby peer that finished loading after the host's GO still gets a
	## drivable race instead of sitting on WAITING forever.
	if _is_host:
		return
	_waiting_for_peers = false
	_go_shown = true
	_countdown = 0.0
	_countdown_label.visible = false
	_phase = Phase.RACING
	if _cart != null:
		_cart.set_physics_process(true)


func _tick_countdown(delta: float) -> void:
	if _server_race_active and _server_clock_ok:
		# Derived from the Pi clock every frame: a slow frame or a late RPC
		# cannot shift this client's GO. Clamp to 5.0 s so a sudden clock step
		# cannot inflate the countdown.
		_countdown = clampf(float(_server_start_ms - Network.server_now_ms()) / 1000.0, 0.0, 5.0)
	else:
		_countdown -= delta
	if _countdown > 0.0:
		var count: int = int(ceil(maxf(_countdown, 0.0)))
		if count != _last_count:
			_last_count = count
			_countdown_label.text = str(count) if count > 0 else "GO!"
			_pop_label(_countdown_label)
			_set_start_lights([1, 3, 5][clampi(3 - count, 0, 2)], false)
			if count > 0:
				_play_one_shot(COUNTDOWN_BEEP, -9.0, 1.0)
		return
	if not _go_shown:
		_go_shown = true
		_countdown_label.text = "GO!"
		_countdown_label.add_theme_color_override("font_color", UiPalette.GRASS)
		_pop_label(_countdown_label)
		_set_start_lights(_start_lights.size(), true)
		_flash_gate(0)
		_play_one_shot(COUNTDOWN_GO, -7.0, 1.0)
		# Control and the race clock start on the GO frame. The label stays up
		# for a short visual beat without freezing the karts.
		_phase = Phase.RACING
		_go_time = 0.0
		if _cart != null:
			_cart.set_physics_process(true)
		return


func _tick_race(delta: float) -> void:
	if _server_race_active and _server_clock_ok:
		# Official race clock: all peers read the same Pi timestamp.
		_race_time = maxf(0.0, float(Network.server_now_ms() - _server_start_ms) / 1000.0)
	else:
		_race_time += delta
	if _go_shown and _countdown_label.visible:
		_go_time += delta
		if _go_time >= 0.7:
			_countdown_label.visible = false
	if _cart == null:
		return

	var info: Dictionary = _spline.closest(_cart.global_position)
	var s: float = info["s"]
	var closest_point: Vector3 = info["point"] as Vector3

	# A reset (R) or a respawn is a teleport: resync, never bank the jump.
	if _cart.global_position.distance_squared_to(_last_cart_pos) > 100.0:
		var total: float = maxf(_spline.total_length, 0.001)
		var lap_index: float = floorf(_unwrapped / total)
		# Any teleport (R reset, respawn, backwards or wrapped-forward) must
		# not let sectors from the old position count toward the new lap.
		_sector_flags = 0
		_last_sector = clampi(int(s / (total / 4.0)), 0, 3)
		# Re-base the unwrapped distance to the new physical position in the
		# current lap; otherwise the lap completes mid-track after a reset.
		_unwrapped = lap_index * total + s
		_skip_progress = true
		# A teleport is neither a landing nor a barrier hit.
		_last_forward_speed = 0.0
		_air_time = 0.0
		_fall_speed = 0.0
		_wrong_way_timer = 0.0
		_set_wrong_way(false)
	_last_cart_pos = _cart.global_position

	if _skip_progress:
		_prev_s = s
		_skip_progress = false
	else:
		var step: float = s - _prev_s
		if step < -_spline.total_length * 0.5:
			step += _spline.total_length
		elif step > _spline.total_length * 0.5:
			step -= _spline.total_length
		var max_step: float = _cart.velocity.length() * delta * 2.5 + 1.0
		_unwrapped += clampf(step, -max_step, max_step)
	_prev_s = s
	_update_surface_grip(s)
	_update_landing_smoke(delta)

	var sector: int = clampi(int(s / (_spline.total_length / 4.0)), 0, 3)
	_sector_flags |= 1 << sector
	if sector != _last_sector:
		_last_sector = sector
		_flash_gate(sector)
	if _unwrapped >= START_DISTANCE + float(_lap) * _spline.total_length \
			and _sector_flags == 0b1111:
		_complete_lap()
		if _phase == Phase.FINISHED:
			# The result card is built; do not run off-track, barrier or rival
			# logic for the rest of this physics frame.
			return

	# Lateral offset from the centreline, not raw nearest-point distance: a
	# barrier scrape or a tight hairpin can spike the 3D/nearest distance while
	# the kart is still fully on the road.
	var frame: Dictionary = _spline.sample(s)
	var right: Vector3 = frame["right"] as Vector3
	var spline_fwd: Vector3 = frame["forward"] as Vector3
	var tangent := Vector3(spline_fwd.x, 0.0, spline_fwd.z)
	if tangent.length_squared() > 0.0001:
		tangent = tangent.normalized()
	var cart_fwd := Vector3(-_cart.global_transform.basis.z.x, 0.0,
		-_cart.global_transform.basis.z.z)
	if cart_fwd.length_squared() > 0.0001:
		cart_fwd = cart_fwd.normalized()
	var planar_speed: float = Vector2(_cart.velocity.x, _cart.velocity.z).length()
	var heading_dot: float = cart_fwd.dot(tangent)
	if heading_dot < -0.45 and planar_speed > 3.0:
		_wrong_way_timer += delta
		if _wrong_way_timer > 1.0:
			_set_wrong_way(true)
	elif heading_dot >= -0.15:
		_wrong_way_timer = 0.0
		_set_wrong_way(false)
	elif not _wrong_way_active:
		_wrong_way_timer = maxf(_wrong_way_timer - delta * 2.0, 0.0)

	var lateral: float = absf((_cart.global_position - closest_point).dot(right))
	# Hysteresis: leave the road at the curb (or past the grid run-off apron),
	# come back only once clearly inside it, so a scrape cannot flip the warning
	# and the slowdown on and off every frame.
	var off_limit: float = (_road_half + 2.1) if _use_grid else (ROAD_HALF + 1.1)
	var back_on: float = (_road_half + 1.4) if _use_grid else (ROAD_HALF + 0.5)
	var was_off: bool = _was_off_track
	var off: bool = lateral > (back_on if _was_off_track else off_limit)
	_was_off_track = off
	if off:
		_off_timer += delta
		if not was_off:
			_offtrack_label.text = "OFF TRACK  ·  EASE BACK IN"
			_offtrack_label.add_theme_color_override("font_color", UiPalette.RED)
			_offtrack_label.visible = true
			_pop_label(_offtrack_label)
		_cart.max_speed = _base_max_speed * 0.55
		# Only pull a kart back once it is really out (past the barrier or the
		# grass) or has been stuck out there for a while. The respawn point is
		# forward of the current arc length, never behind it.
		if _off_timer > 4.5 or lateral > _road_half + 12.5 or _cart.global_position.y < -8.0:
			_respawn(s)
	else:
		_off_timer = 0.0
		_offtrack_label.visible = false
		_cart.max_speed = _base_max_speed

	# Barrier feedback: a hard scrape kills forward speed without pushing the
	# kart off the road, so it needs its own cue. The cooldown keeps one hit
	# from flashing the label on every physics frame.
	_barrier_cooldown = maxf(_barrier_cooldown - delta, 0.0)
	var forward: Vector3 = -_cart.global_transform.basis.z
	var forward_speed: float = _cart.velocity.dot(forward)
	var lost: float = _last_forward_speed - forward_speed
	_last_forward_speed = forward_speed
	var barrier_edge: float = (_road_half + 0.6) if _use_grid else (ROAD_HALF - 1.4)
	if lost > BARRIER_HIT_SPEED_LOSS and lateral > barrier_edge \
			and _barrier_cooldown <= 0.0:
		_barrier_cooldown = 1.2
		_impact_label.text = "BARRIER!  ·  EASE OFF"
		_impact_label.add_theme_color_override("font_color", UiPalette.YELLOW)
		_impact_label.visible = true
		_impact_timer = 1.0
		_pop_label(_impact_label)
	if _effects != null:
		_effects.set("off_track", off)
	# Grass physically bends away from the kart: feed world position to the
	# shared wind shaders once per frame (one uniform, all 5,000 cards).
	for material: ShaderMaterial in _bend_materials:
		material.set_shader_parameter("kart_position", _cart.global_position)

	if _server_race_active:
		# Polls only store a target; the ghosts are interpolated every frame.
		_tick_server_rivals(delta)
		_server_bots_timer += delta
		if _server_bots_timer >= Network.server_bot_poll_interval():
			_server_bots_timer = 0.0
			_fetch_server_bots()
	elif not _multiplayer or _is_host:
		_rival_tick_accum += delta
		if _rival_tick_accum >= 1.0 / 30.0:
			_tick_rivals(_rival_tick_accum)
			_rival_tick_accum = 0.0
	_hud_time_accum += delta
	if _hud_time_accum >= 0.05:
		_hud_time_accum = 0.0
		var lap_now: int = mini(_lap, _total_laps)
		if lap_now != _hud_last_lap:
			_hud_last_lap = lap_now
			_hud.call("set_lap", lap_now, _total_laps)
		var place_now: int = _place()
		if place_now != _hud_last_place:
			_hud_last_place = place_now
			_hud.call("set_race_position", place_now, _field_size())
		_hud.call("set_race_time", _race_time, _best_lap_time())
		_hud_standings_accum += 0.05
		if _hud_standings_accum >= 0.25:
			_hud_standings_accum = 0.0
			_hud.call("set_standings", _result_entries())


func _fetch_server_bots() -> void:
	## The Pi is the only bot simulation in a server race. A poll only stores a
	## target sample here; _tick_server_rivals() moves the ghosts every physics
	## frame, so the 6-12 Hz stream never teleports a body across the track.
	if _server_bots_pending or _server_race_id == "":
		return
	_server_bots_pending = true
	var snapshot: Dictionary = await Network.fetch_server_bots(_server_race_id)
	if snapshot.is_empty() and is_inside_tree():
		# One transient HTTP miss should not freeze the field for a whole poll.
		snapshot = await Network.fetch_server_bots(_server_race_id)
	_server_bots_pending = false
	if not is_inside_tree():
		return
	if snapshot.is_empty() or not _server_race_active:
		return
	var rows: Variant = snapshot.get("bots", [])
	if not (rows is Array):
		return
	var stamp: int = Time.get_ticks_msec()
	var count: int = mini((rows as Array).size(), _rivals.size())
	for i in count:
		var row: Variant = (rows as Array)[i]
		if not (row is Array) or (row as Array).size() < 6:
			continue
		var values: Array = row as Array
		var position := Vector3(float(values[0]), float(values[1]), float(values[2]))
		if not position.is_finite():
			continue
		var node: CartPlayer = _rivals[i]["node"]
		if not is_instance_valid(node):
			continue
		if not node.remote_mode:
			node.call("setup_remote", 1000 + i)
		var yaw: float = float(values[3])
		var velocity := Vector3.ZERO
		if values.size() > 7:
			var speed: float = float(values[7])
			if is_finite(speed):
				velocity = Vector3(-sin(yaw), 0.0, -cos(yaw)) * clampf(speed, 0.0, 60.0)
		# The sample carries the server's ramp height in y. Keep it intact:
		# the ghost rides the server surface instead of a flat road guess.
		var rival: Dictionary = _rivals[i]
		rival["server_pos"] = position
		rival["server_yaw"] = yaw
		rival["server_velocity"] = velocity
		rival["server_stamp_ms"] = stamp
		rival["has_server_sample"] = true
		# The ghost has no local physics; publish the server momentum so the
		# local player's contact response still pushes the rival correctly.
		node.net_position = position
		node.net_yaw = yaw
		node.net_velocity = velocity
		rival["progress"] = float(values[4])
		rival["lap"] = int(values[5])
		if values.size() > 6 and int(values[6]) == 1:
			if not bool(rival["finished"]) and float(rival["finish_time"]) < 0.0:
				rival["finish_time"] = _race_time
			rival["finished"] = true
			node.call("mark_race_finished")


func _tick_server_rivals(delta: float) -> void:
	## Interpolate every server-driven rival toward its newest snapshot. The
	## horizontal error is corrected softly and the snapshot is extrapolated
	## with the server velocity for at most SERVER_BOT_MAX_EXTRAPOLATION; only a
	## correction bigger than SERVER_BOT_SNAP_DISTANCE snaps the body (respawn,
	## warp, first sample). Y is taken straight from the server sample, which
	## carries the ramp height, so the ghosts no longer sink through kickers.
	if _rivals.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var blend: float = 1.0 - exp(-SERVER_BOT_BLEND * delta)
	var vertical_blend: float = 1.0 - exp(-SERVER_BOT_VERTICAL_BLEND * delta)
	for rival: Dictionary in _rivals:
		var node: CartPlayer = rival["node"]
		if not is_instance_valid(node) or not bool(rival["has_server_sample"]):
			continue
		var age: float = clampf(float(now - int(rival["server_stamp_ms"])) / 1000.0,
			0.0, SERVER_BOT_MAX_EXTRAPOLATION)
		var sample_position: Vector3 = rival["server_pos"]
		var sample_velocity: Vector3 = rival["server_velocity"]
		var target_yaw: float = float(rival["server_yaw"])
		var target: Vector3 = sample_position + sample_velocity * age
		if node.global_position.distance_to(target) > SERVER_BOT_SNAP_DISTANCE:
			node.global_position = target
			node.rotation.y = target_yaw
			node.reset_physics_interpolation()
			continue
		var position: Vector3 = node.global_position.lerp(target, blend)
		position.y = lerpf(node.global_position.y, target.y, vertical_blend)
		node.global_position = position
		node.rotation.y = lerp_angle(node.rotation.y, target_yaw, blend)


func _report_server_lap_async(lap: int, lap_ms: float, finished: bool) -> void:
	if not _server_race_active or _server_race_id == "" or _server_race_secret == "":
		return
	var peer: int = multiplayer.get_unique_id()
	var race_ms: int = int(round(_race_time * 1000.0))
	var official: Dictionary = await Network.report_server_lap(
		_server_race_id, _server_race_secret, peer,
		GameSettings.player_name, lap, race_ms, int(round(lap_ms * 1000.0)),
		finished)
	# The scene can be left while the HTTP request is in flight; resuming on a
	# freed node used to raise an error and drop the official result.
	if not is_inside_tree():
		return
	if official.is_empty():
		return
	_server_official = official
	if finished:
		_apply_official_finish(official)


func _apply_official_finish(official: Dictionary) -> void:
	## Replace the local finish time with the server's authoritative one and
	## use the server standings for the big placement label.
	_official_applied = true
	if _result_subtitle != null:
		_result_subtitle.text = _result_summary_text()
	var finish_ms: int = int(official.get("finish_ms", 0))
	if finish_ms <= 0:
		finish_ms = int(official.get("official_race_ms", 0))
	if finish_ms > 0 and _result_total != null:
		_result_total.text = _format_time(float(finish_ms) / 1000.0)
	var best_ms: int = int(official.get("best_lap_ms", 0))
	if best_ms > 0 and _result_best != null:
		_result_best.text = _format_time(float(best_ms) / 1000.0)
	var standings: Variant = official.get("standings", [])
	if not (standings is Array) or _result_place == null:
		return
	var peer: int = multiplayer.get_unique_id()
	for index in (standings as Array).size():
		var entry: Variant = (standings as Array)[index]
		if entry is Dictionary and int((entry as Dictionary).get("peer", -2)) == peer:
			var official_place: int = index + 1
			_result_place.text = "%s / %d" % [_ordinal(official_place),
				(standings as Array).size()]
			# The official place can differ from the local estimate when a
			# remote finish packet was late; the winning wording must match it.
			_set_result_title(official_place)
			return


func _set_result_title(place: int) -> void:
	## One wording ladder for both the local estimate and the official result.
	if _result_title == null:
		return
	_result_title.text = "YOU WIN!" if place == 1 \
		else ("PODIUM FINISH!" if place <= 3 else "RACE COMPLETE")


func _safe_respawn_transform(s: float) -> Transform3D:
	## Respawn on the centreline only if the spot is clear; otherwise search
	## along the track and across the road. A blind centreline respawn can drop
	## a kart inside another kart or a barrier.
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 1.15
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1 | 2 | 8
	query.exclude = [_cart.get_rid()] if _cart != null else []
	for distance_offset: float in [0.0, 4.0, 8.0, 12.0]:
		for lateral: float in [0.0, 2.5, -2.5, 5.0, -5.0]:
			var candidate: Transform3D = _track_transform(s + distance_offset, lateral, 0.25)
			query.transform = candidate.translated(Vector3.UP * 1.1)
			if space_state.intersect_shape(query, 1).is_empty():
				return candidate
	return _track_transform(s)


func _respawn(s: float) -> void:
	if _cart == null or not is_instance_valid(_cart):
		return
	_cart.global_transform = _safe_respawn_transform(s)
	_cart.call("reset_for_respawn")
	_cart.velocity = Vector3.ZERO
	_cart.max_speed = _base_max_speed
	var rig: Node = _cart.get_node_or_null("CameraArm")
	if rig != null:
		rig.call("reset_camera")
	_skip_progress = true
	_off_timer = 0.0
	# A teleport is not a hard landing or a barrier hit.
	_air_time = 0.0
	_fall_speed = 0.0
	_last_forward_speed = 0.0
	_wrong_way_timer = 0.0
	_set_wrong_way(false)
	_toast("BACK ON TRACK", 1.3)


func _complete_lap() -> void:
	var min_speed: float = maxf(_base_max_speed, 1.0)
	var total_len: float = maxf(_spline.total_length, 1.0)
	# Boost pads, manual boost (1.35x), mini-turbos and downhill runs can hold
	# a lap well above flat-out top speed, so the physical floor allows heavy
	# overspeed. It only rejects teleport/physics-glitch crossings (~seconds).
	var min_lap: float = maxf(5.0, total_len / (min_speed * 1.6))
	var lap_time: float = _race_time - _lap_start
	if lap_time < min_lap:
		_rejected_crossings += 1
		if _rejected_crossings < 3:
			# Implausibly quick crossing (reset/teleport/physics glitch):
			# ignore it without banking the time or advancing the lap, and
			# require full sectors again before the next crossing can count.
			_lap_start = _race_time
			_sector_flags = 0
			return
		# Fail-safe: three straight rejections means the player keeps driving
		# full valid laps (e.g. an exceptional boost line), so accept this one
		# rather than block race progress forever. Best-lap integrity is
		# secondary to the race actually finishing.
		_rejected_crossings = 0
	var completed_lap: int = _lap
	var previous_lap: float = _lap_times[_lap_times.size() - 1] \
		if not _lap_times.is_empty() else -1.0
	var previous_best: float = _best_lap_time()
	_lap_times.append(lap_time)
	_rejected_crossings = 0
	_lap_start = _race_time
	_sector_flags = 0
	if _server_race_active:
		_report_server_lap_async(completed_lap, lap_time, false)
	_lap += 1
	if _lap > _total_laps:
		_finish()
		return
	_hud.call("set_lap", _lap, _total_laps)
	# The lap toast doubles as the live lap-delta readout: the completed lap's
	# time, its change against the previous lap, and a BEST tag when it beat
	# every earlier lap. One line, same spacing as the result table.
	var parts: PackedStringArray = [
		"LAP %d / %d" % [completed_lap, _total_laps], _format_time(lap_time)]
	if previous_lap > 0.0:
		parts.append(_format_lap_delta(lap_time - previous_lap))
	if previous_best < 0.0 or lap_time < previous_best:
		parts.append("BEST")
	_toast("   ·   ".join(parts), 2.4)
	var is_new_best: bool = previous_best > 0.0 and lap_time < previous_best
	var is_final_lap: bool = _lap == _total_laps
	if is_final_lap and is_new_best:
		_callout("FINAL LAP!  ·  NEW BEST LAP!", UiPalette.YELLOW, 2.5)
	elif is_final_lap:
		_callout("FINAL LAP!", UiPalette.YELLOW, 2.3)
	elif is_new_best:
		_callout("NEW BEST LAP!", UiPalette.CYAN, 2.2)
	_flash_gate(0)
	if _effects != null:
		_effects.call("lap_burst")
	_play_one_shot(LAP_CHIME, -8.0, 1.0)


func _finish() -> void:
	_phase = Phase.FINISHED
	# Bank the crossing time before anything reads a placement: finished carts
	# are ranked by when they crossed, not by their leftover progress.
	if _finish_time < 0.0:
		_finish_time = _race_time
	if _multiplayer and Network.is_host:
		Network.set_room_state("finished")
	if _cart != null:
		_cart.set_physics_process(false)
		_cart.velocity = Vector3.ZERO
		_cart.max_speed = _base_max_speed
		# A finished cart must not be a solid obstacle for players still
		# crossing the line, and the host solver must skip it too.
		_cart.collision_layer = 0
		_cart.contact_enabled = false
	# Stop steering the rivals too; otherwise they keep their last AI inputs
	# and drive into the barriers behind the result card.
	for rival: Dictionary in _rivals:
		var rival_node: CartPlayer = rival["node"]
		if is_instance_valid(rival_node):
			rival_node.set_ai_controls(0.0, 0.35, 0.0)
	# Publish the final progress exactly once so every peer's placement is
	# correct even after this cart stops streaming state. This used to sit
	# inside the rival loop: with bots OFF the packet was never sent, and with
	# bots ON it was sent once per rival.
	if _cart != null and _multiplayer and Network.is_session_active() \
			and Network.is_connected_to_server():
		if _is_host:
			_broadcast_race_state(multiplayer.get_unique_id(),
				_cart.global_position, _cart.rotation.y, _unwrapped,
				Time.get_ticks_msec(), _cart.velocity)
		elif Network.is_scene_ready(1):
			rpc_id(1, "_net_race_cart_state", multiplayer.get_unique_id(),
				_cart.global_position, _cart.rotation.y, _unwrapped,
				Time.get_ticks_msec(), _cart.velocity)
	# Authoritative result publication. The host stamps its own crossing and
	# broadcasts the canonical order; a client reports its crossing reliably so
	# the host can never miss a finish (the unreliable final state above may be
	# dropped). This is the packet that keeps every result card in agreement.
	if _multiplayer and Network.is_session_active() and Network.is_connected_to_server():
		if _is_host:
			_broadcast_standings(_all_humans_finished())
		elif not _finish_reported:
			_finish_reported = true
			rpc_id(1, "_net_report_finish", _race_time, _best_lap_time())
	CursorController.set_menu_mode(true)
	_offtrack_label.visible = false
	_impact_label.visible = false
	_impact_timer = 0.0
	if _callout_label != null:
		_callout_label.visible = false
	_callout_timer = 0.0
	_wrong_way_timer = 0.0
	_set_wrong_way(false)

	var place: int = _place()
	var suffix: String = _ordinal(place)
	var best: float = _best_lap_time()
	_set_result_title(place)
	_result_subtitle.text = _result_summary_text()
	_result_total.text = _format_time(_race_time) if not _lap_times.is_empty() else "—"
	if _server_race_active and not _server_finished_reported:
		_server_finished_reported = true
		# The final report carries the LAST lap's time, not the whole race:
		# passing the total here corrupted the server's last-lap readout.
		_report_server_lap_async(_total_laps + 1, _last_lap_time(), true)
	_result_best.text = _format_time(best) if best >= 0.0 else "—"
	_result_place.text = "%s / %d" % [suffix, _field_size()]
	_result_laps.text = "%d / %d" % [mini(_lap_times.size(), _total_laps), _total_laps]
	_fill_result_laps()
	_result_standings_section.visible = _multiplayer
	if _multiplayer:
		_refresh_result_standings()
	_result_ui.present(_result_card)
	_hud.call("set_race_time", _race_time, best)
	_hud.call("set_lap", _total_laps, _total_laps)
	var pause_menu: Control = get_node_or_null("PauseMenu/Root") as Control
	if pause_menu != null and pause_menu.visible:
		_result_root.remove_from_group("nav_scope")
	var menu_nav: Node = get_node_or_null("/root/MenuNav")
	if menu_nav != null:
		menu_nav.call("refresh")
	if _effects != null:
		_effects.call("lap_burst")
	_play_one_shot(FINISH_FANFARE, -6.0, 1.0)


func _start_ambience() -> void:
	_ambient_audio = AudioStreamPlayer.new()
	var ambience: AudioStream = FOREST_AMBIENCE
	if ambience is AudioStreamMP3:
		(ambience as AudioStreamMP3).loop = true
	_ambient_audio.stream = ambience
	_ambient_audio.bus = "SFX"
	_ambient_audio.volume_db = -34.0
	add_child(_ambient_audio)
	_ambient_audio.play()
	var tween := create_tween()
	tween.tween_property(_ambient_audio, "volume_db", -23.0, 1.4)


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


func _format_time(seconds: float) -> String:
	## Integer-millisecond formatting. The old float remainder could print
	## "1:60.000" when a lap ended at 59.9995 s because the rounded string
	## carried a 60 while the minutes had not rolled over.
	var total_ms: int = maxi(roundi(maxf(seconds, 0.0) * 1000.0), 0)
	return "%d:%02d.%03d" % [total_ms / 60000, (total_ms / 1000) % 60,
		total_ms % 1000]


func _ordinal(place: int) -> String:
	var suffix: String = "th"
	if place % 100 < 11 or place % 100 > 13:
		match place % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [place, suffix]


# --------------------------------------------------------------------------
# navigation


func _on_race_again() -> void:
	if _multiplayer:
		if _is_host:
			# restart = true: the current scene IS the race scene, so the
			# normal start would be swallowed by the begin-game retry guard.
			Network.start_game(RACE_SCENE, GameSettings.GAME_MINIGAMES, true)
		return
	SceneLoader.go_to(RACE_SCENE, _race_title(), "GET READY")


func _on_back_to_lobby() -> void:
	if _multiplayer:
		Network.return_to_lobby_keep_session()
	else:
		SceneLoader.go_to(MINIGAMES_MENU, "MINIGAMES", "PICK AN EVENT")


func _on_main_menu() -> void:
	if Network.is_session_active():
		Network.leave()
	SceneLoader.go_to(MAIN_MENU, "MAIN MENU")
