extends Node3D
## CARGO RUSH: a two-team present relay in a compact arena.
##
## Presents spawn at points of interest all over the yard - on the handling
## loop, under the start gantry, by the grandstands, on the skidpad, down the
## jump lane, on the dirt strip and between the chicane barriers. A kart stops
## on a present and HOLDS the interact action for three seconds to load it,
## then drives it home and the present drops the moment the kart touches its
## own base pad. First team to BASE_TARGET deliveries wins; a five minute cap
## with a tied score goes to sudden-death overtime.
##
## The arena is one shared layout for every theme: a kerbed and armco'd
## handling loop, a start gantry, two grandstands, floodlights, distance
## boards, tyre walls, marshal posts, a fenced perimeter with catch fencing
## and banners, and a tree line behind the fence. cargo_rush_theme.gd owns the
## ground scans, the present art, the yard dressing and the grip rule, so a
## skin can never change the layout or the rules.
##
## Solo play is the local kart against the sandbox AI carts. Each rival reuses
## scripts/ai/sandbox_bot.gd as its driver and runs a four-state relay machine
## (seek / hold / carry / deposit) on top, with a claim table so two bots never
## fight over the same present.
##
## Online play is host-authoritative for present state and scores, exactly like
## the sandbox: the host simulates holds, carriers and respawns, streams
## present snapshots at 10 Hz, peers freeze their copy and ask the host to
## start or stop a hold. Carts stream peer-to-peer through the host relay and
## scores, clock and phase are replicated as absolute values. The hold action
## is read from the InputMap, never from a hard-coded key.

const CART_SCENE := preload("res://scenes/player/cart_player.tscn")
const SandboxBot := preload("res://scripts/ai/sandbox_bot.gd")
const CargoTheme := preload("res://scripts/minigames/cargo_rush_theme.gd")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const VisualGrade := preload("res://scripts/systems/visual_grade.gd")
const RacingKit := preload("res://scripts/minigames/racing_kit.gd")
const TrackSpline := preload("res://scripts/minigames/track_spline.gd")
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
const PICKUP_SFX: AudioStream = preload("res://assets/audio/sfx/fun/drift_chime.wav")
const DELIVERY_SFX: AudioStream = preload("res://assets/audio/sfx/race/lap_chime.wav")
const FINISH_FANFARE: AudioStream = preload("res://assets/audio/sfx/race/finish_fanfare.wav")

## Interact action. It is registered here only when the project has no action
## of that name, exactly like input_setup.gd adds the pad bindings; the game
## itself always reads the action, so a rebind keeps working.
const INTERACT_ACTION: String = "interact"
const INTERACT_KEY: Key = KEY_E

const MATCH_SECONDS: float = 300.0
const OVERTIME_SECONDS: float = 60.0
const COUNTDOWN_SECONDS: float = 3.0
const BASE_TARGET: int = 5
const TEAM_COUNT: int = 2
const CORNER_RADIUS: int = 16 ## One radius for every HUD tile, per the UI kit.
const TEAM_COLORS: Array[Color] = [UiPalette.BLUE, UiPalette.RED]

## Arena footprint. The wall sits exactly on ARENA_HALF.
const ARENA_HALF: float = 56.0
const WALL_HEIGHT: float = 3.4
const WALL_THICKNESS: float = 1.0
const FLOOR_SIZE: float = 170.0
const BASE_Z: Array[float] = [44.0, -44.0]
const PAD_HALF: Vector2 = Vector2(8.0, 5.0)

## The handling loop. Same generator the race uses, sized for a compact yard.
const LOOP_PRESET: Dictionary = {
	"control_points": 20,
	"samples_per_segment": 8,
	"base_radius": 21.0,
	"lobe_a": 0.15,
	"lobe_b": 0.030,
	"lobe_c": 0.012,
	"lobe_d": 0.055,
	"stretch_x": 1.32,
	"stretch_z": 0.74,
	"elevation": [],
}
## Barrier runs: four spans of the lap with a gate between them, so a kart can
## always get on and off the loop. Fractions of the lap.
const LOOP_RUN_STARTS: Array[float] = [0.03, 0.28, 0.53, 0.78]
const LOOP_RUN_SPAN: float = 0.19
## Solid pieces around the loop, at lap fractions.
const TYRE_WALL_SPOTS: Array[float] = [0.14, 0.40, 0.65, 0.90]
const STAND_SPOTS: Array[float] = [0.34, 0.60]
const BOARD_SPOTS: Array[float] = [0.23, 0.73]
const GANTRY_SPOT: float = 0.10

## Present rules.
const PRESENT_COUNT: int = 7
const PRESENT_RESPAWN: float = 1.1
const PICK_RADIUS: float = 4.2
const HOLD_SECONDS: float = 3.0
const CARRY_SLOW_SPEED: float = 0.86
const CARRY_SLOW_ACCEL: float = 0.90
const PRESENT_FLOAT: float = 0.78
const CARRY_OFFSET := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.02, -1.48))
const POINT_CLEARANCE: float = 1.0

## POI grip zones that belong to the shared layout rather than the theme.
const DIRT_RECT := Rect2(39.0, -18.0, 10.0, 36.0)
const DIRT_GRIP: float = 0.78
const SKID_CENTRE := Vector2(-22.0, 28.0)
const SKID_RADIUS: float = 8.0
const SKID_GRIP: float = 0.70
## Chicane: two parallel barrier walls with a present in the gap.
const CHICANE_X: float = 20.0
const CHICANE_Z: float = 26.0

const CART_SYNC_INTERVAL: float = 0.05
const PRESENT_SYNC_INTERVAL: float = 0.10
const STATE_SYNC_INTERVAL: float = 0.25
const CLIENT_SNAP_DISTANCE: float = 7.0
const HOLD_REQUEST_INTERVAL: float = 0.10
const HOLD_REQUEST_TIMEOUT_MS: int = 500

const BOT_MIN: int = 2
const BOT_MAX: int = 5
const BOT_SEEK: int = 0
const BOT_HOLD: int = 1
const BOT_CARRY: int = 2
const BOT_DEPOSIT: int = 3
const BOT_NEAR_DRIVE: float = 12.0

const PRESENT_AVAILABLE: int = 0
const PRESENT_CARRIED: int = 1
const PRESENT_RESPAWNING: int = 2

enum Phase { COUNTDOWN, RACING, OVERTIME, FINISHED }

var _theme_id: String = CargoTheme.DEFAULT_ID
var _theme: Dictionary = {}
var _theme_root: Node3D
var _team_names: PackedStringArray = PackedStringArray()
var _hazards: Array[Dictionary] = []
var _stats: Dictionary = {"objects": 0, "draw_calls": 0, "solid_bodies": 0}

var _loop_spline: RefCounted
var _pads: Array[Vector3] = []
var _pad_visuals: Array[MeshInstance3D] = []
var _pad_labels: Array[Label3D] = []
var _pillar_labels: Array[Label3D] = []
var _pillars: Array[Node3D] = []
var _floor: MeshInstance3D
var _apron: MeshInstance3D
var _dirt_plane: MeshInstance3D
var _skid_plane: MeshInstance3D

var _present_points: Array[Dictionary] = []
var _presents: Array[Dictionary] = []
var _present_nodes: Array[Dictionary] = []
var _present_meshes: Array[Mesh] = []
var _present_material: Material
var _ring_material: StandardMaterial3D
var _ring_colour: Color = Color(1.0, 0.86, 0.35, 0.95)
var _point_cursor: int = 0
var _local_hold_index: int = -1
var _local_holding: bool = false
var _local_hold_time: float = 0.0
var _hold_state: Dictionary = {} ## holder key -> {index, time}
var _claims: Dictionary = {} ## present index -> holder key
var _client_holds: Dictionary = {} ## peer id -> {index, holding, ms}
var _hold_send_timer: float = 0.0
var _carry_saved: Dictionary = {} ## cart instance id -> {max_speed, acceleration}

var _cart: CartPlayer
var _bots: Array[Dictionary] = []
var _traffic: Array[CartPlayer] = []
var _saved_vehicle: String = ""

var _score: PackedInt32Array = PackedInt32Array([0, 0])
var _local_team: int = 0
var _phase: Phase = Phase.COUNTDOWN
var _countdown: float = COUNTDOWN_SECONDS
var _last_count: int = 3
var _remaining: float = MATCH_SECONDS
var _overtime_remaining: float = 0.0
var _overtime: bool = false
var _match_length: float = MATCH_SECONDS
var _overtime_length: float = OVERTIME_SECONDS
var _target: int = BASE_TARGET
var _time: float = 0.0
var _visual_time: float = 0.0

var _multiplayer: bool = false
var _is_host: bool = true
var _remote_carts: Dictionary = {}
var _name_labels: Dictionary = {}
var _cart_relay_ms: Dictionary = {}
var _present_sync_timer: float = 0.0
var _state_sync_timer: float = 0.0
var _cart_sync_timer: float = 0.0
var _bot_sync_timer: float = 0.0
var _bot_sync_positions: Dictionary = {}

var _selftest: bool = false
var _debug: bool = false
var _debug_timer: float = 0.0
var _selftest_collected: int = 0
var _selftest_deliveries: int = 0
var _selftest_cycle: bool = false

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
var _prompt_label: Label
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
		Engine.max_fps = 60
	_ensure_interact_action()
	_multiplayer = Network.is_session_active()
	_is_host = Network.is_host if _multiplayer else true
	_local_team = _team_of_local_peer()
	_theme_id = CargoTheme.resolve(_requested_theme())
	_theme = CargoTheme.get_theme(_theme_id)
	_team_names = CargoTheme.team_names(_theme)
	_apply_test_overrides()
	CursorController.set_menu_mode(false)
	_upgrade_graphics()

	_cart = get_tree().get_first_node_in_group("player") as CartPlayer
	_build_arena()
	_build_bases()
	_apply_theme()
	_build_present_pool()
	_place_local_cart()
	_build_bots()
	_build_hud()
	_build_result_card()
	if _multiplayer:
		_setup_multiplayer()
	if _debug:
		_probe_structure()
	_begin_countdown()
	if _selftest:
		_run_self_test.call_deferred()


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
		_match_length = clampf(float(seconds.to_int()), 5.0, 900.0)
	var overtime: String = OS.get_environment("CART_CARGO_OVERTIME").strip_edges()
	if overtime.is_valid_int():
		_overtime_length = clampf(float(overtime.to_int()), 2.0, 300.0)
	var target: String = OS.get_environment("CART_CARGO_TARGET").strip_edges()
	if target.is_valid_int():
		_target = clampi(target.to_int(), 1, 99)
	_remaining = _match_length


func _ensure_interact_action() -> void:
	## The hold action is always read from the InputMap. A project that already
	## binds "interact" keeps its own binding; otherwise we add the standard
	## keyboard key and a pad shoulder so the mode is playable out of the box.
	if InputMap.has_action(INTERACT_ACTION):
		return
	InputMap.add_action(INTERACT_ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = INTERACT_KEY
	InputMap.action_add_event(INTERACT_ACTION, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_LEFT_SHOULDER
	pad.device = -1
	InputMap.action_add_event(INTERACT_ACTION, pad)


func _interact_key_name() -> String:
	## The HUD prompt follows the real binding instead of assuming "E".
	for event: InputEvent in InputMap.action_get_events(INTERACT_ACTION):
		if event is InputEventKey:
			var code: int = (event as InputEventKey).physical_keycode
			if code != 0:
				return OS.get_keycode_string(code)
		elif event is InputEventJoypadButton:
			return "PAD"
	return "E"


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


# --------------------------------------------------------------------------
# arena: ground, perimeter and the handling loop


func _build_arena() -> void:
	_build_ground()
	_build_perimeter()
	_build_loop()
	_build_jump_lane()
	_build_dirt_strip()
	_build_skidpad()
	_build_chicane()
	_build_floodlights()


func _build_ground() -> void:
	_floor = MeshInstance3D.new()
	_floor.name = "ArenaFloor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
	_floor.mesh = plane
	add_child(_floor)

	var ground := StaticBody3D.new()
	ground.name = "GroundCollision"
	ground.collision_layer = CollisionLayers.WORLD
	ground.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(FLOOR_SIZE, 2.0, FLOOR_SIZE)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, -1.0, 0.0)
	ground.add_child(collision)
	add_child(ground)

	# Worn concrete over the playfield. Themes without an apron scan simply
	# leave the floor scan showing.
	_apron = MeshInstance3D.new()
	_apron.name = "ArenaApron"
	var slab := PlaneMesh.new()
	slab.size = Vector2(ARENA_HALF * 2.0, ARENA_HALF * 2.0)
	_apron.mesh = slab
	_apron.position = Vector3(0.0, 0.012, 0.0)
	add_child(_apron)
	_apron.visible = false


func _build_perimeter() -> void:
	## One merged wall mesh and one static body. The inner face is exactly at
	## ARENA_HALF, so the playable rectangle matches the visible wall. Catch
	## fencing, banners and a painted band make the fence read as a circuit
	## boundary rather than an invisible box.
	var body := StaticBody3D.new()
	body.name = "ArenaWalls"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	var batch := PropBatch.new()
	var span: float = ARENA_HALF * 2.0 + WALL_THICKNESS * 2.0
	var concrete := Color(0.56, 0.57, 0.58)
	var accent := Color(0.42, 0.44, 0.48)
	var steel := Color(0.29, 0.32, 0.36)
	for side: float in [-1.0, 1.0]:
		var z_centre: float = side * (ARENA_HALF + WALL_THICKNESS * 0.5)
		var x_centre: float = side * (ARENA_HALF + WALL_THICKNESS * 0.5)
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, WALL_HEIGHT * 0.5, z_centre)),
			Vector3(span, WALL_HEIGHT, WALL_THICKNESS), concrete)
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, WALL_HEIGHT - 0.10, z_centre)),
			Vector3(span, 0.20, WALL_THICKNESS + 0.08), accent)
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(x_centre, WALL_HEIGHT * 0.5, 0.0)),
			Vector3(WALL_THICKNESS, WALL_HEIGHT, span), concrete)
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(x_centre, WALL_HEIGHT - 0.10, 0.0)),
			Vector3(WALL_THICKNESS + 0.08, 0.20, span), accent)
		_add_wall_shape(body, Vector3(0.0, WALL_HEIGHT * 0.5, z_centre),
			Vector3(span, WALL_HEIGHT, WALL_THICKNESS))
		_add_wall_shape(body, Vector3(x_centre, WALL_HEIGHT * 0.5, 0.0),
			Vector3(WALL_THICKNESS, WALL_HEIGHT, span))
	# Painted hazard band along the bottom of the wall.
	for side: float in [-1.0, 1.0]:
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, 0.24, side * (ARENA_HALF - 0.02))),
			Vector3(span, 0.24, 0.05), UiPalette.YELLOW)
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(side * (ARENA_HALF - 0.02), 0.24, 0.0)),
			Vector3(0.05, 0.24, span), UiPalette.YELLOW)
	# Fence posts along the top of the wall.
	for side: float in [-1.0, 1.0]:
		for i in 15:
			var along: float = -ARENA_HALF + 4.0 + float(i) * 7.7
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(along, WALL_HEIGHT + 1.5, side * ARENA_HALF)),
				Vector3(0.16, 3.0, 0.16), steel)
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(side * ARENA_HALF, WALL_HEIGHT + 1.5, along)),
				Vector3(0.16, 3.0, 0.16), steel)
	var visual := MeshInstance3D.new()
	visual.name = "ArenaWallsVisual"
	visual.mesh = batch.build()
	visual.material_override = SceneryKit.vertex_material()
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	SceneryKit.bump(_stats, "draw_calls")

	# Catch fencing: one instanced bar mesh for the whole perimeter.
	var bars: Array = []
	var step: float = 0.62
	var count: int = int((ARENA_HALF * 2.0) / step)
	for i in count:
		var along: float = -ARENA_HALF + float(i) * step
		bars.append(Transform3D(Basis.IDENTITY,
			Vector3(along, WALL_HEIGHT + 1.55, -ARENA_HALF)))
		bars.append(Transform3D(Basis.IDENTITY,
			Vector3(along, WALL_HEIGHT + 1.55, ARENA_HALF)))
		bars.append(Transform3D(Basis.IDENTITY,
			Vector3(-ARENA_HALF, WALL_HEIGHT + 1.55, along)))
		bars.append(Transform3D(Basis.IDENTITY,
			Vector3(ARENA_HALF, WALL_HEIGHT + 1.55, along)))
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(0.045, 2.9, 0.045)
	var fence := SceneryKit.multimesh(bar_mesh,
		SceneryKit.instance_material(0.95), bars, "CatchFence", false)
	SceneryKit.set_view(fence, 0.0, 110.0)
	add_child(fence)
	SceneryKit.bump(_stats, "draw_calls")

	# Sponsor hoardings on the inside face of the fence.
	var board_batch := PropBatch.new()
	var texts: PackedStringArray = ["CART SLOP GP", "GRIP TAPE", "TURBO TEA",
		"SLOP ENERGY", "BIG HAT CO", "MEADOW TYRES"]
	var colours: Array[Color] = [Color("2e86ab"), Color("e4572e"),
		Color("f6c945"), Color("3fa34d"), Color("b84a9c"), Color("c9553f")]
	for i in 6:
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var along: float = -34.0 + float(i / 2) * 34.0
		var spot := Vector3(along, 1.55, side * (ARENA_HALF - 0.06))
		var yaw: float = PI if side < 0.0 else 0.0
		board_batch.add_box(Transform3D(Basis(Vector3.UP, yaw),
			spot + Vector3(0.0, 0.0, side * 0.06)),
			Vector3(7.0, 1.15, 0.10), colours[i])
		var label := Label3D.new()
		label.name = "Hoard_%02d" % i
		label.text = texts[i]
		label.font = load(TITLE_FONT)
		label.font_size = 72
		label.pixel_size = 0.0092
		label.outline_size = 10
		label.outline_modulate = UiPalette.OUTLINE
		label.modulate = UiPalette.CREAM
		label.position = spot + Vector3(0.0, 0.0, -side * 0.06)
		label.rotation.y = yaw + PI
		add_child(label)
		SceneryKit.bump(_stats, "objects")
	var boards := MeshInstance3D.new()
	boards.name = "Hoardings"
	boards.mesh = board_batch.build()
	boards.material_override = SceneryKit.vertex_material()
	boards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(boards)
	SceneryKit.bump(_stats, "draw_calls")
	SceneryKit.bump(_stats, "solid_bodies")


func _add_wall_shape(body: StaticBody3D, position: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = position
	body.add_child(collision)


func _build_loop() -> void:
	## The handling loop: kerbs on both edges, armco in four runs with a gate
	## between them, tyre walls, grandstands, the start gantry, distance boards
	## and marshal posts. Every solid piece is on CollisionLayers.WORLD.
	_loop_spline = TrackSpline.new(LOOP_PRESET)
	var total: float = _loop_spline.total_length
	RacingKit.kerbs(self, _loop_spline, 0.0, total, 1.0, Color("c23a2c"))
	RacingKit.kerbs(self, _loop_spline, 0.0, total, -1.0, Color("e8e2d2"))
	SceneryKit.bump(_stats, "draw_calls", 2)
	SceneryKit.bump(_stats, "objects", 2)
	for start: float in LOOP_RUN_STARTS:
		var from_d: float = total * start
		var to_d: float = total * (start + LOOP_RUN_SPAN)
		RacingKit.barriers(self, _loop_spline, from_d, to_d, 1.0)
		RacingKit.barriers(self, _loop_spline, from_d, to_d, -1.0)
		SceneryKit.bump(_stats, "draw_calls", 2)
		SceneryKit.bump(_stats, "objects", 2)
		SceneryKit.bump(_stats, "solid_bodies", 2)
	for index in TYRE_WALL_SPOTS.size():
		var side: float = _outside_side(total * TYRE_WALL_SPOTS[index])
		RacingKit.tyre_wall(self, _loop_spline, total * TYRE_WALL_SPOTS[index],
			side, 12.0)
		SceneryKit.bump(_stats, "draw_calls")
		SceneryKit.bump(_stats, "objects", 33)
		SceneryKit.bump(_stats, "solid_bodies")
	for spot: float in STAND_SPOTS:
		RacingKit.grandstand(self, _loop_spline, total * spot,
			_outside_side(total * spot))
		SceneryKit.bump(_stats, "draw_calls", 3)
		SceneryKit.bump(_stats, "objects", 6)
		SceneryKit.bump(_stats, "solid_bodies")
	RacingKit.start_gantry(self, _loop_spline, total * GANTRY_SPOT)
	SceneryKit.bump(_stats, "draw_calls", 2)
	SceneryKit.bump(_stats, "objects", 3)
	SceneryKit.bump(_stats, "solid_bodies")
	for index in BOARD_SPOTS.size():
		var distance: float = total * BOARD_SPOTS[index]
		RacingKit.distance_board(self, _loop_spline, distance,
			"CARGO RUSH" if index == 0 else "BASE")
		SceneryKit.bump(_stats, "draw_calls", 2)
		SceneryKit.bump(_stats, "objects", 2)
		SceneryKit.bump(_stats, "solid_bodies")
	_build_marshal_posts(total)
	_build_loop_tyre_bundles(total)


func _outside_side(distance: float) -> float:
	## Which side of the loop is the outside at `distance`, using the same
	## signed turn test racing_kit uses.
	if _loop_spline == null:
		return 1.0
	var before: float = _loop_spline.yaw_at(distance - 6.0)
	var after: float = _loop_spline.yaw_at(distance + 6.0)
	return 1.0 if angle_difference(before, after) > 0.0 else -1.0


func _build_marshal_posts(total: float) -> void:
	## Six marshal huts on the outside of the loop. One merged mesh, one static
	## body with a box per hut: a real obstacle, not a painting.
	var body := StaticBody3D.new()
	body.name = "MarshalPosts"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	var batch := PropBatch.new()
	var hut := Color(0.86, 0.84, 0.74)
	var roof := Color(0.74, 0.28, 0.22)
	var yellow := Color(0.95, 0.76, 0.18)
	for i in 6:
		var fraction: float = 0.055 + float(i) * 0.165
		var distance: float = total * fraction
		var side: float = _outside_side(distance)
		var frame: Dictionary = _loop_spline.sample(distance)
		var position: Vector3 = (frame["position"] as Vector3) \
			+ (frame["right"] as Vector3) * (side * 9.4)
		var yaw: float = _loop_spline.yaw_at(distance)
		var root := Transform3D(Basis(Vector3.UP, yaw), position)
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, 1.05, 0.0)), Vector3(2.0, 2.1, 1.7), hut)
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, 2.22, 0.0)), Vector3(2.4, 0.18, 2.1), roof)
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, 1.55, -0.86)), Vector3(1.2, 0.7, 0.06), Color(0.18, 0.22, 0.26))
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(1.25, 2.6, 0.0)), Vector3(0.08, 3.2, 0.08), Color(0.3, 0.32, 0.36))
		batch.add_box(root * Transform3D(Basis.IDENTITY,
			Vector3(1.25, 3.9, 0.0)), Vector3(0.9, 0.55, 0.04), yellow)
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.2, 2.4, 1.9)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = root * Transform3D(Basis.IDENTITY,
			Vector3(0.0, 1.2, 0.0))
		body.add_child(collision)
		SceneryKit.bump(_stats, "objects", 5)
	var visual := MeshInstance3D.new()
	visual.name = "MarshalHuts"
	visual.mesh = batch.build()
	visual.material_override = SceneryKit.vertex_material()
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	SceneryKit.bump(_stats, "draw_calls")
	SceneryKit.bump(_stats, "solid_bodies")


func _build_loop_tyre_bundles(total: float) -> void:
	## Bundles of spare tyres stacked at the gate mouths, so every entry to the
	## loop reads as a working service road. Solid on WORLD.
	var body := StaticBody3D.new()
	body.name = "TyreBundles"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	var transforms: Array = []
	var colours: Array = []
	for start: float in LOOP_RUN_STARTS:
		var distance: float = total * (start + LOOP_RUN_SPAN + 0.03)
		var frame: Dictionary = _loop_spline.sample(distance)
		for side: float in [-1.0, 1.0]:
			var position: Vector3 = (frame["position"] as Vector3) \
				+ (frame["right"] as Vector3) * (side * 7.6)
			for level in 2:
				transforms.append(Transform3D(Basis.IDENTITY,
					position + Vector3.UP * (0.16 + float(level) * 0.32)))
				colours.append(Color(0.08, 0.08, 0.10) if level == 0
					else Color(0.76, 0.23, 0.18))
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.4, 0.64, 1.4)
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.position = position + Vector3.UP * 0.32
			body.add_child(collision)
			SceneryKit.bump(_stats, "objects", 2)
	if transforms.is_empty():
		body.queue_free()
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.48
	mesh.bottom_radius = 0.48
	mesh.height = 0.30
	mesh.radial_segments = 12
	mesh.rings = 1
	var tyres := SceneryKit.multimesh(mesh,
		SceneryKit.instance_material(0.98), transforms, "TyreBundles", false,
		colours)
	SceneryKit.set_view(tyres, 0.0, 200.0)
	add_child(tyres)
	SceneryKit.bump(_stats, "draw_calls")
	SceneryKit.bump(_stats, "solid_bodies")


func _build_jump_lane() -> void:
	## A straight kicker lane along the south apron: a paved lane, two ramps and
	## marker cones. The ramps are real drivable wedges with concave colliders.
	var lane := MeshInstance3D.new()
	lane.name = "JumpLane"
	var plane := PlaneMesh.new()
	plane.size = Vector2(84.0, 10.0)
	lane.mesh = plane
	lane.position = Vector3(0.0, 0.02, -30.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.40, 0.43)
	mat.roughness = 0.88
	lane.material_override = mat
	add_child(lane)
	SceneryKit.bump(_stats, "draw_calls")
	_add_ramp(Vector3(-12.0, 0.0, -30.0), -PI * 0.5, 6.0, 9.0, 0.72)
	_add_ramp(Vector3(8.0, 0.0, -30.0), -PI * 0.5, 6.0, 9.0, 0.72)
	# Cones line the lane. They sit on the non-blocking PROP layer, so a kart
	# can clip one without being stopped.
	var cone_transforms: Array = []
	var cone_colours: Array = []
	for i in 12:
		var x: float = -36.0 + float(i) * 6.5
		for side: float in [-1.0, 1.0]:
			cone_transforms.append(Transform3D(Basis.IDENTITY,
				Vector3(x, 0.0, -30.0 + side * 4.6)))
			cone_colours.append(Color(0.94, 0.44, 0.12))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 0.24
	cone.height = 0.62
	cone.radial_segments = 8
	cone.rings = 1
	var cones := SceneryKit.multimesh(cone,
		SceneryKit.instance_material(0.85), cone_transforms, "LaneCones", false,
		cone_colours)
	SceneryKit.set_view(cones, 0.0, 120.0)
	add_child(cones)
	SceneryKit.bump(_stats, "draw_calls")
	SceneryKit.bump(_stats, "objects", cone_transforms.size())


func _add_ramp(centre: Vector3, yaw: float, width: float, length: float,
		height: float) -> void:
	## A wedge that rises from +Z to a lip at -Z in local space, with a vertical
	## back face. The mesh and the concave collider share the same corners, so
	## the kart drives up exactly what it can see.
	var root := Transform3D(Basis(Vector3.UP, yaw), centre)
	var half_w: float = width * 0.5
	var half_l: float = length * 0.5
	var entry_l := Vector3(-half_w, 0.0, half_l)
	var entry_r := Vector3(half_w, 0.0, half_l)
	var lip_l := Vector3(-half_w, height, -half_l)
	var lip_r := Vector3(half_w, height, -half_l)
	var foot_l := Vector3(-half_w, 0.0, -half_l)
	var foot_r := Vector3(half_w, 0.0, -half_l)
	var batch := PropBatch.new()
	var deck := Color(0.52, 0.54, 0.56)
	var stripe := Color(0.95, 0.76, 0.18)
	batch.add_quad(root * entry_l, root * entry_r, root * lip_r, root * lip_l, deck)
	batch.add_quad(root * lip_l, root * lip_r, root * foot_r, root * foot_l,
		deck.darkened(0.18))
	batch.add_triangle(root * entry_l, root * lip_l, root * foot_l, deck.darkened(0.08))
	batch.add_triangle(root * entry_r, root * foot_r, root * lip_r, deck.darkened(0.08))
	batch.add_quad(root * (lip_l + Vector3(0.0, 0.02, -0.55)),
		root * (lip_r + Vector3(0.0, 0.02, -0.55)),
		root * (lip_r + Vector3(0.0, -0.22, -0.55)),
		root * (lip_l + Vector3(0.0, -0.22, -0.55)), stripe)
	var visual := MeshInstance3D.new()
	visual.name = "Ramp"
	visual.mesh = batch.build()
	visual.material_override = SceneryKit.vertex_material()
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	var body := StaticBody3D.new()
	body.name = "RampCollision"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	var faces := PackedVector3Array([
		root * entry_l, root * entry_r, root * lip_r,
		root * entry_l, root * lip_r, root * lip_l,
		root * lip_l, root * lip_r, root * foot_r,
		root * lip_l, root * foot_r, root * foot_l,
		root * entry_l, root * lip_l, root * foot_l,
		root * entry_r, root * foot_r, root * lip_r,
	])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	SceneryKit.bump(_stats, "draw_calls")
	SceneryKit.bump(_stats, "objects", 2)
	SceneryKit.bump(_stats, "solid_bodies")


func _build_dirt_strip() -> void:
	_dirt_plane = MeshInstance3D.new()
	_dirt_plane.name = "DirtStrip"
	var plane := PlaneMesh.new()
	plane.size = Vector2(DIRT_RECT.size.x, DIRT_RECT.size.y)
	_dirt_plane.mesh = plane
	_dirt_plane.position = Vector3(DIRT_RECT.position.x + DIRT_RECT.size.x * 0.5,
		0.03, DIRT_RECT.position.y + DIRT_RECT.size.y * 0.5)
	add_child(_dirt_plane)
	# Marker posts on the strip edges.
	var batch := PropBatch.new()
	for side: float in [-1.0, 1.0]:
		for i in 6:
			var z: float = -16.0 + float(i) * 6.5
			batch.add_box(Transform3D(Basis.IDENTITY,
				Vector3(DIRT_RECT.position.x + (0.0 if side < 0.0
					else DIRT_RECT.size.x), 0.45, z)),
				Vector3(0.16, 0.9, 0.16), Color(0.92, 0.80, 0.42))
	var posts := MeshInstance3D.new()
	posts.name = "DirtMarkers"
	posts.mesh = batch.build()
	posts.material_override = SceneryKit.vertex_material()
	posts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(posts)
	SceneryKit.bump(_stats, "draw_calls")
	SceneryKit.bump(_stats, "objects", 12)


func _build_skidpad() -> void:
	_skid_plane = MeshInstance3D.new()
	_skid_plane.name = "Skidpad"
	var disc := CylinderMesh.new()
	disc.top_radius = SKID_RADIUS
	disc.bottom_radius = SKID_RADIUS
	disc.height = 0.05
	disc.radial_segments = 36
	disc.rings = 1
	_skid_plane.mesh = disc
	_skid_plane.position = Vector3(SKID_CENTRE.x, 0.035, SKID_CENTRE.y)
	add_child(_skid_plane)
	# A white rim and four cones mark the pad.
	var rim := MeshInstance3D.new()
	rim.name = "SkidpadRim"
	var ring := CylinderMesh.new()
	ring.top_radius = SKID_RADIUS + 0.5
	ring.bottom_radius = SKID_RADIUS + 0.5
	ring.height = 0.03
	ring.radial_segments = 36
	ring.rings = 1
	rim.mesh = ring
	rim.position = Vector3(SKID_CENTRE.x, 0.02, SKID_CENTRE.y)
	var rim_mat := StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.albedo_color = UiPalette.CREAM
	rim.material_override = rim_mat
	rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rim)
	SceneryKit.bump(_stats, "draw_calls", 2)


func _build_chicane() -> void:
	## Two short parallel barrier walls on the north-east apron with a present
	## slot between them: the "between the barriers" point of interest.
	var body := StaticBody3D.new()
	body.name = "Chicane"
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	var batch := PropBatch.new()
	var steel := Color(0.29, 0.32, 0.36)
	var cream := Color(0.90, 0.86, 0.76)
	for side: float in [-1.0, 1.0]:
		var x: float = CHICANE_X + side * 3.2
		for i in 7:
			var z: float = CHICANE_Z - 6.0 + float(i) * 2.0
			batch.add_box(Transform3D(Basis.IDENTITY, Vector3(x, 0.62, z)),
				Vector3(0.18, 1.24, 2.0),
				steel if i % 2 == 0 else cream)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.30, 1.24, 14.0)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(x, 0.62, CHICANE_Z)
		body.add_child(collision)
	var visual := MeshInstance3D.new()
	visual.name = "ChicaneWalls"
	visual.mesh = batch.build()
	visual.material_override = SceneryKit.vertex_material()
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	SceneryKit.bump(_stats, "draw_calls")
	SceneryKit.bump(_stats, "objects", 14)
	SceneryKit.bump(_stats, "solid_bodies")


func _build_floodlights() -> void:
	var spots: Array[Vector3] = [
		Vector3(-40.0, 0.0, 40.0), Vector3(40.0, 0.0, 40.0),
		Vector3(-40.0, 0.0, -40.0), Vector3(40.0, 0.0, -40.0),
		Vector3(-13.0, 0.0, 52.0), Vector3(13.0, 0.0, -52.0),
	]
	for spot: Vector3 in spots:
		RacingKit.floodlight(self, spot)
		SceneryKit.bump(_stats, "draw_calls", 2)
		SceneryKit.bump(_stats, "objects", 7)
		SceneryKit.bump(_stats, "solid_bodies")


# --------------------------------------------------------------------------
# bases


func _build_bases() -> void:
	for team in TEAM_COUNT:
		var centre := Vector3(0.0, 0.0, BASE_Z[team])
		_pads.append(centre)
		var border := MeshInstance3D.new()
		border.name = "BaseBorder_%d" % team
		var edge := PlaneMesh.new()
		edge.size = Vector2(PAD_HALF.x * 2.0 + 0.7, PAD_HALF.y * 2.0 + 0.7)
		border.mesh = edge
		border.position = centre + Vector3.UP * 0.045
		var edge_mat := StandardMaterial3D.new()
		edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		edge_mat.albedo_color = UiPalette.CREAM
		border.material_override = edge_mat
		border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(border)
		SceneryKit.bump(_stats, "draw_calls")

		var pad := MeshInstance3D.new()
		pad.name = "BasePad_%d" % team
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(PAD_HALF.x * 2.0, PAD_HALF.y * 2.0)
		pad.mesh = mesh
		pad.position = centre + Vector3.UP * 0.06
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = TEAM_COLORS[team].darkened(0.10)
		pad.material_override = mat
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pad)
		_pad_visuals.append(pad)
		SceneryKit.bump(_stats, "draw_calls")

		var label := Label3D.new()
		label.name = "BaseLabel_%d" % team
		label.text = _team_names[team]
		label.font = load(TITLE_FONT)
		label.font_size = 96
		label.pixel_size = 0.011
		label.outline_size = 14
		label.outline_modulate = UiPalette.OUTLINE
		label.modulate = TEAM_COLORS[team].lightened(0.32)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = centre + Vector3.UP * 3.0
		add_child(label)
		_pad_labels.append(label)
		SceneryKit.bump(_stats, "objects")

		_build_base_structures(team, centre)


func _build_base_structures(team: int, centre: Vector3) -> void:
	## Flag poles and the scoreboard pillar. Both are solid on WORLD, so a kart
	## cannot drive through its own base furniture.
	var outward: float = signf(BASE_Z[team])
	var body := StaticBody3D.new()
	body.name = "BaseSolids_%d" % team
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	var batch := PropBatch.new()
	var colour: Color = TEAM_COLORS[team]
	var pole := Color(0.32, 0.34, 0.38)
	for side: float in [-1.0, 1.0]:
		var pole_pos := Vector3(side * (PAD_HALF.x - 0.6), 0.0,
			centre.z + outward * (PAD_HALF.y - 0.4))
		batch.add_cylinder(Transform3D(Basis.IDENTITY,
			pole_pos + Vector3.UP * 2.4), 0.09, 4.8, 8, pole)
		batch.add_box(Transform3D(Basis(Vector3.UP, PI * 0.5),
			pole_pos + Vector3.UP * 3.9 + Vector3(0.0, 0.0, 0.75)),
			Vector3(1.5, 1.0, 0.05), colour)
		batch.add_box(Transform3D(Basis.IDENTITY,
			pole_pos + Vector3.UP * 4.7), Vector3(0.3, 0.3, 0.3),
			UiPalette.YELLOW)
		var pole_shape := CylinderShape3D.new()
		pole_shape.radius = 0.16
		pole_shape.height = 4.8
		var pole_collision := CollisionShape3D.new()
		pole_collision.shape = pole_shape
		pole_collision.position = pole_pos + Vector3.UP * 2.4
		body.add_child(pole_collision)
		SceneryKit.bump(_stats, "objects", 3)

	var pillar_pos := Vector3(0.0, 0.0, centre.z + outward * (PAD_HALF.y + 1.6))
	var pillar := Node3D.new()
	pillar.name = "ScorePillar_%d" % team
	pillar.position = pillar_pos
	add_child(pillar)
	var pillar_batch := PropBatch.new()
	pillar_batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.15, 0.0)),
		Vector3(2.2, 0.30, 2.2), Color(0.50, 0.52, 0.55))
	pillar_batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.5, 0.0)),
		Vector3(1.15, 4.7, 1.15), colour.darkened(0.12))
	pillar_batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 4.95, 0.0)),
		Vector3(1.7, 0.42, 1.7), UiPalette.CREAM)
	for side: float in [-1.0, 1.0]:
		pillar_batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, 2.6, side * 0.60)), Vector3(0.86, 1.9, 0.05),
			Color(0.10, 0.11, 0.14))
	var pillar_mesh := MeshInstance3D.new()
	pillar_mesh.name = "PillarBody"
	pillar_mesh.mesh = pillar_batch.build()
	pillar_mesh.material_override = SceneryKit.vertex_material()
	pillar.add_child(pillar_mesh)
	var pillar_shape := BoxShape3D.new()
	pillar_shape.size = Vector3(1.3, 5.2, 1.3)
	var pillar_collision := CollisionShape3D.new()
	pillar_collision.shape = pillar_shape
	pillar_collision.position = Vector3(0.0, 2.6, 0.0)
	pillar.add_child(pillar_collision)
	_pillars.append(pillar)

	for side: float in [-1.0, 1.0]:
		var face := Label3D.new()
		face.name = "PillarScore_%s" % ("A" if side < 0.0 else "B")
		face.text = "0 / %d" % _target
		face.font = load(TITLE_FONT)
		face.font_size = 128
		face.pixel_size = 0.0075
		face.outline_size = 16
		face.outline_modulate = UiPalette.OUTLINE
		face.modulate = UiPalette.YELLOW
		face.position = Vector3(0.0, 3.4, side * 0.62)
		face.rotation.y = PI if side < 0.0 else 0.0
		pillar.add_child(face)
		_pillar_labels.append(face)

	# A soft team-coloured beam makes the base findable from across the yard.
	var beam := MeshInstance3D.new()
	beam.name = "BaseBeam"
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 1.1
	beam_mesh.bottom_radius = 1.6
	beam_mesh.height = 13.0
	beam_mesh.radial_segments = 16
	beam_mesh.rings = 1
	beam.mesh = beam_mesh
	beam.position = pillar_pos + Vector3.UP * 6.6
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_mat.albedo_color = Color(colour.r, colour.g, colour.b, 0.16)
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	SceneryKit.bump(_stats, "draw_calls", 4)
	SceneryKit.bump(_stats, "objects", 8)
	SceneryKit.bump(_stats, "solid_bodies")


func _inside_pad(position: Vector3, team: int) -> bool:
	if team < 0 or team >= _pads.size():
		return false
	var centre: Vector3 = _pads[team]
	return absf(position.x - centre.x) <= PAD_HALF.x \
		and absf(position.z - centre.z) <= PAD_HALF.y \
		and position.y <= 3.5


# --------------------------------------------------------------------------
# theme


func _apply_theme() -> void:
	if _theme_root != null and is_instance_valid(_theme_root):
		_theme_root.queue_free()
	_theme_root = Node3D.new()
	_theme_root.name = "ThemeRoot"
	add_child(_theme_root)
	var arena := {
		"half": ARENA_HALF,
		"loop_centre": Vector3.ZERO,
		"loop_extent": Vector2(34.0, 15.0),
		"base_pads": _pads,
	}
	_hazards = CargoTheme.build_scenery(_theme_root, _theme, arena, _stats)
	if _floor != null:
		_floor.material_override = CargoTheme.floor_material(_theme)
	var apron: Material = CargoTheme.apron_material(_theme)
	if _apron != null:
		_apron.visible = apron != null
		if apron != null:
			_apron.material_override = apron
	if _dirt_plane != null:
		_dirt_plane.material_override = CargoTheme.dirt_material(_theme)
	if _skid_plane != null:
		_skid_plane.material_override = CargoTheme.skid_material(_theme)
	_present_meshes = CargoTheme.present_meshes(_theme)
	_present_material = CargoTheme.present_material(_theme)
	_apply_sky()
	_refresh_present_visuals()


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


# --------------------------------------------------------------------------
# presents: points of interest, pool, visuals


func _build_present_pool() -> void:
	## Collect every point of interest, then build one reusable present node per
	## slot. Nothing is placed in the world until the race starts, so a client
	## never shows a present the host has not spawned.
	_present_points.clear()
	var total: float = _loop_spline.total_length if _loop_spline != null else 1.0
	for fraction: float in [0.12, 0.44, 0.74]:
		var frame: Dictionary = _loop_spline.sample(total * fraction)
		_add_present_point(frame["position"] as Vector3, "handling loop")
	var gantry: Dictionary = _loop_spline.sample(total * GANTRY_SPOT)
	_add_present_point(gantry["position"] as Vector3, "under the gantry")
	for spot: float in STAND_SPOTS:
		var distance: float = total * spot
		var side: float = _outside_side(distance)
		var frame: Dictionary = _loop_spline.sample(distance)
		var position: Vector3 = (frame["position"] as Vector3) \
			+ (frame["right"] as Vector3) * (side * 3.8)
		_add_present_point(position, "near the stands")
	_add_present_point(Vector3(SKID_CENTRE.x, 0.0, SKID_CENTRE.y), "skidpad")
	_add_present_point(Vector3(SKID_CENTRE.x + 4.0, 0.0, SKID_CENTRE.y + 2.0),
		"skidpad")
	_add_present_point(Vector3(-30.0, 0.0, -30.0), "jump lane")
	_add_present_point(Vector3(24.0, 0.0, -30.0), "jump lane")
	_add_present_point(Vector3(44.0, 0.0, 6.0), "dirt strip")
	_add_present_point(Vector3(43.0, 0.0, -10.0), "dirt strip")
	_add_present_point(Vector3(CHICANE_X, 0.0, CHICANE_Z - 2.0),
		"between barriers")
	if _selftest:
		# Three presents, all within reach of the south base, so the scripted
		# fifteen seconds can actually prove a full bot cycle.
		_present_points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _planar_distance(a["position"] as Vector3, _pads[1]) \
				< _planar_distance(b["position"] as Vector3, _pads[1]))
		while _present_points.size() > 3:
			_present_points.pop_back()
	var count: int = _present_points.size() if _selftest else PRESENT_COUNT
	for i in count:
		_presents.append({
			"point": -1,
			"position": Vector3.ZERO,
			"state": PRESENT_RESPAWNING,
			"carrier": 0,
			"respawn": 0.0,
			"hold": 0.0,
			"mesh": i % maxi(_present_meshes.size(), 1),
		})
		_present_nodes.append(_build_present_node(i))


func _add_present_point(position: Vector3, poi: String) -> void:
	_present_points.append({
		"position": Vector3(position.x, 0.0, position.z),
		"poi": poi,
	})


func _build_present_node(index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Present_%02d" % index
	root.visible = false
	add_child(root)
	var mesh := MeshInstance3D.new()
	mesh.name = "Gift"
	if not _present_meshes.is_empty():
		mesh.mesh = _present_meshes[index % _present_meshes.size()]
	mesh.material_override = _present_material
	root.add_child(mesh)
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	var disc := CylinderMesh.new()
	disc.top_radius = 1.05
	disc.bottom_radius = 1.05
	disc.height = 0.03
	disc.radial_segments = 24
	disc.rings = 1
	halo.mesh = disc
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.albedo_color = Color(1.0, 0.84, 0.32, 0.30)
	halo.material_override = halo_mat
	halo.position = Vector3(0.0, -0.70, 0.0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	var ring_mesh := ImmediateMesh.new()
	var ring := MeshInstance3D.new()
	ring.name = "ProgressRing"
	ring.mesh = ring_mesh
	ring.visible = false
	ring.position = Vector3(0.0, 0.95, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	return {
		"root": root,
		"mesh": mesh,
		"halo": halo,
		"ring": ring,
		"ring_mesh": ring_mesh,
		"phase": float(index) * 0.9,
	}


func _refresh_present_visuals() -> void:
	for i in _present_nodes.size():
		var node: Dictionary = _present_nodes[i]
		var mesh: MeshInstance3D = node["mesh"] as MeshInstance3D
		if mesh == null or _present_meshes.is_empty():
			continue
		mesh.mesh = _present_meshes[i % _present_meshes.size()]
		mesh.material_override = _present_material


func _start_presents() -> void:
	if _presents.is_empty():
		return
	if _multiplayer and not _is_host:
		return
	for index in _presents.size():
		_spawn_present(index)


func _spawn_present(index: int) -> void:
	if index < 0 or index >= _presents.size():
		return
	var point: int = _free_point()
	if point < 0:
		return
	var present: Dictionary = _presents[index]
	present["point"] = point
	present["position"] = (_present_points[point]["position"] as Vector3)
	present["state"] = PRESENT_AVAILABLE
	present["carrier"] = 0
	present["hold"] = 0.0
	present["respawn"] = 0.0
	var node: Dictionary = _present_nodes[index]
	var root: Node3D = node["root"] as Node3D
	root.visible = true
	root.position = (present["position"] as Vector3) + Vector3.UP * PRESENT_FLOAT
	root.rotation = Vector3(0.0, float(index) * 0.7, 0.0)


func _free_point() -> int:
	## The next point that is clear of geometry and not already holding another
	## live present. Rotating the cursor keeps respawns spread around the map.
	if _present_points.is_empty():
		return -1
	var total: int = _present_points.size()
	for step in total:
		var index: int = (_point_cursor + step) % total
		var position: Vector3 = _present_points[index]["position"] as Vector3
		if _point_occupied(index):
			continue
		if not _point_clear(position):
			continue
		_point_cursor = (index + 1) % total
		return index
	for step in total:
		var index: int = (_point_cursor + step) % total
		var position: Vector3 = _present_points[index]["position"] as Vector3
		if not _point_occupied(index):
			_point_cursor = (index + 1) % total
			return index
	return -1


func _point_occupied(index: int) -> bool:
	for present: Dictionary in _presents:
		if int(present["point"]) == index \
				and int(present["state"]) == PRESENT_AVAILABLE:
			return true
	return false


func _point_clear(position: Vector3) -> bool:
	## Never spawn a present inside geometry. A shape query at the present's
	## floating height is cheap and exact; authored points are clear already,
	## this is the guard against a theme prop landing on one.
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return true
	var sphere := SphereShape3D.new()
	sphere.radius = POINT_CLEARANCE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY,
		position + Vector3.UP * (PRESENT_FLOAT + 0.45))
	query.collision_mask = CollisionLayers.WORLD
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return space.intersect_shape(query, 1).is_empty()


func _tick_presents(delta: float) -> void:
	## Host-only simulation: respawn timers, hold progress, carriers and
	## deposits. Clients only apply the snapshots this produces.
	for index in _presents.size():
		var present: Dictionary = _presents[index]
		if int(present["state"]) != PRESENT_RESPAWNING:
			continue
		present["respawn"] = maxf(float(present["respawn"]) - delta, 0.0)
		if float(present["respawn"]) <= 0.0:
			_spawn_present(index)
	_tick_holds(delta)
	_tick_carriers()


func _tick_holds(delta: float) -> void:
	var wants: Dictionary = _collect_hold_wants()
	for key: int in wants.keys():
		var index: int = int(wants[key])
		if index < 0 or index >= _presents.size():
			_hold_state.erase(key)
			continue
		var present: Dictionary = _presents[index]
		if int(present["state"]) != PRESENT_AVAILABLE:
			_hold_state.erase(key)
			continue
		var cart: CartPlayer = _cart_for_key(key)
		if cart == null or not _present_in_range(cart, index):
			_hold_state.erase(key)
			continue
		var data: Dictionary = _hold_state.get(key, {"index": index, "time": 0.0})
		if int(data.get("index", -1)) != index:
			data = {"index": index, "time": 0.0}
		data["time"] = float(data.get("time", 0.0)) + delta
		_hold_state[key] = data
		if float(data["time"]) >= HOLD_SECONDS:
			_take_present(index, key)
	for key: int in _hold_state.keys():
		if wants.has(key):
			continue
		_hold_state.erase(key)
	for index in _presents.size():
		_presents[index]["hold"] = 0.0
	for key: int in _hold_state.keys():
		var data: Dictionary = _hold_state[key]
		var index: int = int(data.get("index", -1))
		if index < 0 or index >= _presents.size():
			continue
		_presents[index]["hold"] = maxf(float(_presents[index]["hold"]),
			float(data.get("time", 0.0)))


func _collect_hold_wants() -> Dictionary:
	var wants: Dictionary = {}
	if _local_hold_index >= 0 and _local_holding:
		wants[_local_key()] = _local_hold_index
	if _multiplayer:
		var now: int = Time.get_ticks_msec()
		for peer: int in _client_holds.keys():
			var entry: Dictionary = _client_holds[peer]
			if now - int(entry.get("ms", 0)) > HOLD_REQUEST_TIMEOUT_MS:
				continue
			if not bool(entry.get("holding", false)):
				continue
			wants[peer] = int(entry.get("index", -1))
	for index in _bots.size():
		var entry: Dictionary = _bots[index]
		if int(entry.get("state", BOT_SEEK)) != BOT_HOLD:
			continue
		var present_index: int = int(entry.get("present", -1))
		if present_index >= 0:
			wants[_bot_key(index)] = present_index
	return wants


func _take_present(index: int, key: int) -> void:
	if index < 0 or index >= _presents.size():
		return
	var present: Dictionary = _presents[index]
	if int(present["state"]) != PRESENT_AVAILABLE:
		return
	present["state"] = PRESENT_CARRIED
	present["carrier"] = key
	present["hold"] = 0.0
	for other: int in _hold_state.keys():
		var data: Dictionary = _hold_state[other]
		if int(data.get("index", -1)) == index:
			_hold_state.erase(other)
	_claims.erase(index)
	var cart: CartPlayer = _cart_for_key(key)
	if cart != null:
		_apply_carry_slow(cart)
		_pop_text("+1 %s" % _present_word(), cart.global_position
			+ Vector3.UP * 2.2, Color(1.0, 0.88, 0.36), 64)
	_stats["collected"] = int(_stats.get("collected", 0)) + 1
	if _selftest:
		_selftest_collected += 1
	_play_one_shot(PICKUP_SFX, -4.0, 1.10)
	if key == _local_key():
		_show_toast("LOADED  ·  DRIVE IT HOME", 1.4)
	elif key > 0:
		_show_toast("%s LOADED A PRESENT" % Network.name_of(key), 1.2)
	if _multiplayer and _is_host:
		_broadcast_presents()
	if _debug:
		print("CARGO_DEBUG take present=%d holder=%d" % [index, key])


func _tick_carriers() -> void:
	for index in _presents.size():
		var present: Dictionary = _presents[index]
		if int(present["state"]) != PRESENT_CARRIED:
			continue
		var key: int = int(present["carrier"])
		var cart: CartPlayer = _cart_for_key(key)
		if cart == null:
			_release_present(index)
			continue
		present["position"] = cart.global_position
		if _inside_pad(cart.global_position, _team_for_key(key)):
			_deliver_present(index, key)


func _deliver_present(index: int, key: int) -> void:
	var present: Dictionary = _presents[index]
	var team: int = _team_for_key(key)
	_score[team] = _score[team] + 1
	present["state"] = PRESENT_RESPAWNING
	present["carrier"] = 0
	present["respawn"] = PRESENT_RESPAWN
	present["hold"] = 0.0
	var cart: CartPlayer = _cart_for_key(key)
	if cart != null:
		_restore_carry_slow(cart)
		_pop_text("DELIVERED", cart.global_position + Vector3.UP * 2.4,
			TEAM_COLORS[team].lightened(0.30), 72)
	_stats["deliveries"] = int(_stats.get("deliveries", 0)) + 1
	if _selftest:
		_selftest_deliveries += 1
		if key < 0:
			_selftest_cycle = true
	_flash_pad(team)
	_refresh_score_now()
	_play_one_shot(DELIVERY_SFX, -4.0, 1.06)
	_show_toast("%s SCORES!" % _team_names[team], 1.5)
	if _debug:
		print("CARGO_DEBUG delivery team=%d score=%d-%d key=%d"
			% [team, _score[0], _score[1], key])
	if _multiplayer and _is_host:
		_broadcast_delivery(team, key)
		_broadcast_state()
	if _overtime or _score[team] >= _target:
		_finish_match()


func _release_present(index: int) -> void:
	## A carrier that vanished (disconnect, respawn out of the world) hands the
	## present back to the pool instead of freezing it forever.
	if index < 0 or index >= _presents.size():
		return
	var present: Dictionary = _presents[index]
	var key: int = int(present["carrier"])
	var cart: CartPlayer = _cart_for_key(key)
	if cart != null:
		_restore_carry_slow(cart)
	present["state"] = PRESENT_RESPAWNING
	present["carrier"] = 0
	present["respawn"] = PRESENT_RESPAWN
	present["hold"] = 0.0
	if _multiplayer and _is_host:
		_broadcast_presents()


func _apply_carry_slow(cart: CartPlayer) -> void:
	## A loaded kart is a little slower and a little lazier on the throttle, so
	## a carrier can be chased down. The base values are restored on delivery.
	if not is_instance_valid(cart):
		return
	var id: int = cart.get_instance_id()
	if _carry_saved.has(id):
		return
	_carry_saved[id] = {
		"max_speed": cart.max_speed,
		"acceleration": cart.acceleration,
	}
	cart.max_speed = cart.max_speed * CARRY_SLOW_SPEED
	cart.acceleration = cart.acceleration * CARRY_SLOW_ACCEL


func _restore_carry_slow(cart: CartPlayer) -> void:
	if not is_instance_valid(cart):
		return
	var id: int = cart.get_instance_id()
	if not _carry_saved.has(id):
		return
	var saved: Dictionary = _carry_saved[id]
	cart.max_speed = float(saved.get("max_speed", cart.max_speed))
	cart.acceleration = float(saved.get("acceleration", cart.acceleration))
	_carry_saved.erase(id)


func _debug_bots() -> void:
	## Gated by CART_CARGO_DEBUG: one compact line per bot plus the present
	## table. Costs nothing when the variable is unset.
	var present_states := PackedStringArray()
	for index in _presents.size():
		var present: Dictionary = _presents[index]
		present_states.append("%d:%d/%d" % [index, int(present["state"]),
			int(present["carrier"])])
	print("CARGO_DEBUG presents=%s score=%d-%d phase=%d"
		% [",".join(present_states), _score[0], _score[1], int(_phase)])
	for index in _bots.size():
		var entry: Dictionary = _bots[index]
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart == null or not is_instance_valid(cart):
			continue
		var hold_data: Dictionary = _hold_state.get(_bot_key(index), {}) as Dictionary
		print("CARGO_DEBUG bot=%d team=%d state=%d present=%d pos=(%.1f,%.1f) "
			% [index, int(entry.get("team", 1)), int(entry.get("state", 0)),
			int(entry.get("present", -1)), cart.global_position.x,
			cart.global_position.z]
			+ "speed=%.1f throttle=%.2f brake=%.2f steer=%.2f hold=%.1f"
			% [Vector2(cart.velocity.x, cart.velocity.z).length(),
			cart.ai_throttle, cart.ai_brake, cart.ai_steer,
			float(hold_data.get("time", 0.0))])


func _present_in_range(cart: CartPlayer, index: int) -> bool:
	if cart == null or index < 0 or index >= _presents.size():
		return false
	var target: Vector3 = _presents[index]["position"] as Vector3
	if _planar_distance(cart.global_position, target) > PICK_RADIUS:
		return false
	return absf(cart.global_position.y - target.y) < 3.0


func _present_word() -> String:
	return str(_theme.get("present_kind", "present")).to_upper()


func _nearest_present(cart: CartPlayer) -> int:
	var best: int = -1
	var best_gap: float = PICK_RADIUS
	for index in _presents.size():
		if int(_presents[index]["state"]) != PRESENT_AVAILABLE:
			continue
		var target: Vector3 = _presents[index]["position"] as Vector3
		var gap: float = _planar_distance(cart.global_position, target)
		if gap < best_gap:
			best_gap = gap
			best = index
	return best


func _update_present_visuals(delta: float) -> void:
	for index in _presents.size():
		var present: Dictionary = _presents[index]
		var node: Dictionary = _present_nodes[index]
		var root: Node3D = node["root"] as Node3D
		if root == null:
			continue
		match int(present["state"]):
			PRESENT_AVAILABLE:
				root.visible = true
				var base: Vector3 = present["position"] as Vector3
				root.position = base + Vector3.UP * (PRESENT_FLOAT
					+ sin(_visual_time * 2.1 + float(node.get("phase", 0.0))) * 0.09)
				root.rotate_y(delta * 1.35)
			PRESENT_CARRIED:
				root.visible = true
				var carrier: CartPlayer = _cart_for_key(int(present["carrier"]))
				if carrier != null:
					root.global_transform = carrier.global_transform * CARRY_OFFSET
				else:
					root.position = present["position"] as Vector3
			_:
				root.visible = false
		_update_present_ring(index, float(present["hold"]))


func _update_present_ring(index: int, progress: float) -> void:
	var node: Dictionary = _present_nodes[index]
	var ring: MeshInstance3D = node["ring"] as MeshInstance3D
	var mesh: ImmediateMesh = node["ring_mesh"] as ImmediateMesh
	if ring == null or mesh == null:
		return
	var clamped: float = clampf(progress / HOLD_SECONDS, 0.0, 1.0)
	if clamped <= 0.02 or int(_presents[index]["state"]) != PRESENT_AVAILABLE:
		ring.visible = false
		return
	ring.visible = true
	mesh.clear_surfaces()
	var steps: int = maxi(int(ceil(48.0 * clamped)), 3)
	var sweep: float = clamped * TAU
	var start: float = -PI * 0.5
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _ring_material)
	for i in steps + 1:
		var angle: float = start + sweep * float(i) / float(steps)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		mesh.surface_set_color(_ring_colour)
		mesh.surface_add_vertex(direction * 0.54)
		mesh.surface_set_color(_ring_colour)
		mesh.surface_add_vertex(direction * 0.76)
	mesh.surface_end()


# --------------------------------------------------------------------------
# karts and bots


func _place_local_cart() -> void:
	if _cart == null:
		return
	var side: float = 1.0 if _local_team == 0 else -1.0
	var spawn := Transform3D(Basis(Vector3.UP, 0.0 if _local_team == 0 else PI),
		Vector3(0.0, 0.35, side * (absf(BASE_Z[_local_team]) - 3.5)))
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
		return clampi(Network.session_bot_count, 0, BOT_MAX)
	return clampi(maxi(GameSettings.effective_bot_count(), BOT_MIN), BOT_MIN, BOT_MAX)


func _bot_vehicle() -> String:
	var entry: Dictionary = VehicleCatalog.find(GameSettings.minigame_vehicle)
	if entry.is_empty():
		return VehicleCatalog.DEFAULT_ID
	return GameSettings.minigame_vehicle


func _bot_team(index: int) -> int:
	# Rivals split across both teams so the player always has a teammate and an
	# opponent in a two-bot solo match.
	return 1 if index % 2 == 0 else 0


func _bot_key(index: int) -> int:
	return -1 - index


func _bot_index_of(key: int) -> int:
	return -1 - key


func _spawn_bot(index: int, ghost: bool) -> void:
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	cart.name = "CargoBot_%d" % (index + 1)
	var team: int = _bot_team(index)
	var spawn: Vector3 = _bot_spawn(index)
	if _selftest and index == 0 and not _present_points.is_empty():
		# Put the first bot within sight of the nearest present so the fifteen
		# second self-test can prove the full pickup-carry-deliver cycle. The
		# present pool is spawned later, so the authored point is the anchor.
		var target: Vector3 = _present_points[0]["position"] as Vector3
		var to_base: Vector3 = _pads[team] - target
		to_base.y = 0.0
		if to_base.length_squared() < 0.1:
			to_base = Vector3.FORWARD
		spawn = target + to_base.normalized() * 7.0
	cart.position = spawn
	cart.rotation.y = atan2(-(spawn.x - _pads[team].x), -(spawn.z - _pads[team].z))
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
	label.modulate = TEAM_COLORS[team].lightened(0.3)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.4, 0.0)
	cart.add_child(label)
	_bots.append({
		"cart": cart,
		"ai": ai,
		"team": team,
		"ghost": ghost,
		"state": BOT_SEEK,
		"present": -1,
		"seek_time": 0.0,
		"hold_time": 0.0,
		"carry_time": 0.0,
	})


func _bot_spawn(index: int) -> Vector3:
	var team: int = _bot_team(index)
	var slot: int = index / 2
	var x: float = -4.5 + float(index % 2) * 9.0
	var z: float = BASE_Z[team] - signf(BASE_Z[team]) * (3.5 + float(slot) * 2.4)
	return Vector3(x, 0.35, z)


func _rebuild_traffic() -> void:
	_traffic.clear()
	if _cart != null and is_instance_valid(_cart):
		_traffic.append(_cart)
	for entry: Dictionary in _bots:
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart) \
				and not bool(entry.get("ghost", false)):
			_traffic.append(cart)


func _local_key() -> int:
	if _multiplayer:
		return multiplayer.get_unique_id()
	return 1


func _cart_for_key(key: int) -> CartPlayer:
	if key > 0:
		if _multiplayer and key != multiplayer.get_unique_id():
			return _remote_carts.get(key) as CartPlayer
		return _cart
	if key < 0:
		var index: int = _bot_index_of(key)
		if index >= 0 and index < _bots.size():
			var cart: CartPlayer = _bots[index].get("cart") as CartPlayer
			if cart != null and is_instance_valid(cart):
				return cart
	return null


func _team_for_key(key: int) -> int:
	if key < 0:
		var index: int = _bot_index_of(key)
		if index >= 0 and index < _bots.size():
			return int(_bots[index].get("team", 1))
		return 1
	if _multiplayer:
		var ids: Array[int] = Network.participants()
		var slot: int = ids.find(key)
		if slot >= 0:
			return slot % TEAM_COUNT
	return _local_team


func _tick_bots(delta: float) -> void:
	if _bots.is_empty():
		return
	if _multiplayer and not _is_host:
		return
	for index in _bots.size():
		var entry: Dictionary = _bots[index]
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		var ai: SandboxBot = entry.get("ai") as SandboxBot
		if cart == null or not is_instance_valid(cart) or ai == null:
			continue
		if _phase != Phase.RACING and _phase != Phase.OVERTIME:
			cart.set_ai_controls(0.0, 0.5, 0.0)
			continue
		_tick_bot(index, entry, cart, ai, delta)


func _tick_bot(index: int, entry: Dictionary, cart: CartPlayer,
		ai: SandboxBot, delta: float) -> void:
	var key: int = _bot_key(index)
	var state: int = int(entry.get("state", BOT_SEEK))
	match state:
		BOT_HOLD:
			var hold_index: int = int(entry.get("present", -1))
			if hold_index < 0 or hold_index >= _presents.size():
				_bot_release(entry, key)
				entry["state"] = BOT_SEEK
				return
			var present: Dictionary = _presents[hold_index]
			if int(present["state"]) == PRESENT_CARRIED \
					and int(present["carrier"]) == key:
				entry["state"] = BOT_CARRY
				entry["carry_time"] = 0.0
				return
			if int(present["state"]) != PRESENT_AVAILABLE:
				_bot_release(entry, key)
				entry["state"] = BOT_SEEK
				return
			if not _present_in_range(cart, hold_index):
				entry["hold_time"] = float(entry.get("hold_time", 0.0)) + delta
				if float(entry["hold_time"]) > 1.6:
					_bot_release(entry, key)
					entry["state"] = BOT_SEEK
					entry["hold_time"] = 0.0
					return
			else:
				entry["hold_time"] = 0.0
			_bot_stop(cart)
		BOT_CARRY, BOT_DEPOSIT:
			var carry_index: int = int(entry.get("present", -1))
			if carry_index < 0 or carry_index >= _presents.size() \
					or int(_presents[carry_index]["state"]) != PRESENT_CARRIED \
					or int(_presents[carry_index]["carrier"]) != key:
				_bot_release(entry, key)
				entry["state"] = BOT_SEEK
				return
			var team: int = int(entry.get("team", 1))
			var base: Vector3 = _pads[team]
			if _inside_pad(cart.global_position, team):
				entry["state"] = BOT_DEPOSIT
				_bot_stop(cart)
				return
			entry["state"] = BOT_CARRY
			entry["carry_time"] = float(entry.get("carry_time", 0.0)) + delta
			if float(entry["carry_time"]) > 40.0:
				_bot_release(entry, key)
				entry["state"] = BOT_SEEK
				entry["carry_time"] = 0.0
				return
			_bot_drive(cart, ai, base, delta, 0.92)
		_:
			_tick_bot_seek(index, entry, cart, ai, delta, key)


func _tick_bot_seek(index: int, entry: Dictionary, cart: CartPlayer,
		ai: SandboxBot, delta: float, key: int) -> void:
	var present_index: int = int(entry.get("present", -1))
	if present_index < 0 or present_index >= _presents.size() \
			or int(_presents[present_index]["state"]) != PRESENT_AVAILABLE:
		_bot_release(entry, key)
		_bot_choose(index, entry, cart)
		present_index = int(entry.get("present", -1))
		if present_index < 0:
			_bot_stop(cart)
			return
	if _present_in_range(cart, present_index):
		entry["state"] = BOT_HOLD
		entry["hold_time"] = 0.0
		_bot_stop(cart)
		return
	var target: Vector3 = _presents[present_index]["position"] as Vector3
	entry["seek_time"] = float(entry.get("seek_time", 0.0)) + delta
	if float(entry["seek_time"]) > 26.0:
		_bot_release(entry, key)
		entry["seek_time"] = 0.0
		_bot_choose(index, entry, cart)
		return
	_bot_drive(cart, ai, target, delta, 1.0)
	if ai.stuck > 5.0 or ai.stranded > 1.5:
		ai.respawn()


func _bot_choose(index: int, entry: Dictionary, cart: CartPlayer) -> void:
	## Weighted pick over every free present: distance to the kart plus a share
	## of the distance home, so a bot does not run across the map for a present
	## it would then have to carry back again. A claim table keeps two bots off
	## the same present.
	var key: int = _bot_key(index)
	var team: int = int(entry.get("team", 1))
	var best: int = -1
	var best_score: float = INF
	var bias: float = 0.90 + float(cart.get_instance_id() % 13) * 0.02
	for present_index in _presents.size():
		if int(_presents[present_index]["state"]) != PRESENT_AVAILABLE:
			continue
		if _claims.has(present_index) and int(_claims[present_index]) != key:
			continue
		var position: Vector3 = _presents[present_index]["position"] as Vector3
		var to_present: float = _planar_distance(cart.global_position, position)
		var to_base: float = _planar_distance(position, _pads[team])
		var score: float = (to_present + to_base * 0.55) * bias
		if score < best_score:
			best_score = score
			best = present_index
	entry["present"] = best
	if best >= 0:
		_claims[best] = key
	entry["state"] = BOT_SEEK
	entry["seek_time"] = 0.0


func _bot_release(entry: Dictionary, key: int) -> void:
	var present_index: int = int(entry.get("present", -1))
	if present_index >= 0 and int(_claims.get(present_index, key)) == key:
		_claims.erase(present_index)
	entry["present"] = -1


func _bot_stop(cart: CartPlayer) -> void:
	cart.set_ai_controls(0.0, 1.0, 0.0)


func _bot_drive(cart: CartPlayer, ai: SandboxBot, target: Vector3,
		delta: float, speed_scale: float) -> void:
	var gap: float = _planar_distance(cart.global_position, target)
	if gap > BOT_NEAR_DRIVE:
		_sandbox_drive(ai, cart, target, delta)
		return
	_drive_to(cart, target, speed_scale)


func _sandbox_drive(ai: SandboxBot, cart: CartPlayer, target: Vector3,
		delta: float) -> void:
	## Far from the goal, let the sandbox driver do the driving: its obstacle
	## rays, stuck recovery and personalities are unchanged. The destination is
	## re-fed every tick, and the circuit state is cleared so the sandbox can
	## never take the wheel for its own loop.
	ai._dest_target = target
	ai._dest_entry = target
	ai._via_active = false
	ai._loop_active = false
	ai._dest_phase = 0
	ai._dest_timer = 0.0
	ai._near_timer = 0.0
	ai.tick(delta, _time, _traffic)


func _drive_to(cart: CartPlayer, target: Vector3, speed_scale: float) -> void:
	## Direct short-range steering for relay work. Waypoints are approached at a
	## controllable speed so a fast kart does not overshoot the present.
	var local: Vector3 = cart.to_local(target)
	if not local.is_finite():
		return
	var steer: float = clampf(atan2(-local.x, -local.z) * 2.1, -1.0, 1.0)
	var distance: float = Vector2(local.x, local.z).length()
	var speed: float = Vector2(cart.velocity.x, cart.velocity.z).length()
	var desired: float = (9.0 if distance > 10.0
		else lerpf(1.6, 9.0, clampf(distance / 10.0, 0.0, 1.0))) * speed_scale
	var throttle: float = 1.0 if speed < desired else 0.0
	var brake: float = 0.0
	if speed > desired + 0.6:
		brake = clampf((speed - desired) / 6.0, 0.0, 0.9)
	cart.set_ai_controls(throttle, brake, steer, false)


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
		if _countdown_label != null:
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
	_show_toast("GO!  ·  GRAB A PRESENT", 1.2)
	_play_one_shot(COUNTDOWN_GO, -5.0, 1.0)
	if not _multiplayer or _is_host:
		_start_race()


func _start_race() -> void:
	if _phase != Phase.COUNTDOWN:
		return
	_phase = Phase.RACING
	_remaining = _match_length
	_overtime = false
	if _countdown_label != null:
		_countdown_label.visible = false
	_set_cart_active(true)
	_start_presents()
	_show_toast("HOLD %s ON A PRESENT  ·  FIRST TO %d"
		% [_interact_key_name(), _target], 2.8)
	if _multiplayer and _is_host:
		_broadcast_state()
		_broadcast_presents()


func _set_cart_active(active: bool) -> void:
	if _cart != null and is_instance_valid(_cart):
		_cart.set_physics_process(active)
		if not active:
			_cart.velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	_time += delta
	if _multiplayer and _is_host and _cart != null and Network.is_session_active():
		Network.resolve_car_collisions(_cart, _remote_carts)
	_net_tick(delta)
	_apply_theme_grip(delta)
	match _phase:
		Phase.COUNTDOWN:
			_tick_countdown(delta)
		Phase.RACING, Phase.OVERTIME:
			if _is_host or not _multiplayer:
				_tick_presents(delta)
				_tick_clock(delta)
			_tick_local_input(delta)
			_tick_bots(delta)
			if _debug:
				_debug_timer += delta
				if _debug_timer >= 2.0:
					_debug_timer = 0.0
					_debug_bots()


func _tick_clock(delta: float) -> void:
	if _phase == Phase.OVERTIME:
		_overtime_remaining = maxf(_overtime_remaining - delta, 0.0)
		if _overtime_remaining <= 0.0:
			_finish_match()
		return
	_remaining = maxf(_remaining - delta, 0.0)
	if _remaining > 0.0:
		return
	if _score[0] == _score[1]:
		_phase = Phase.OVERTIME
		_overtime = true
		_overtime_remaining = _overtime_length
		_show_toast("OVERTIME  ·  NEXT DELIVERY WINS", 2.6)
		if _debug:
			print("CARGO_DEBUG overtime start")
		if _multiplayer and _is_host:
			_broadcast_state()
	else:
		_finish_match()


func _finish_match() -> void:
	if _phase == Phase.FINISHED:
		return
	_phase = Phase.FINISHED
	if _countdown_label != null:
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


# --------------------------------------------------------------------------
# local input: the hold action


func _tick_local_input(delta: float) -> void:
	if _cart == null or not is_instance_valid(_cart):
		return
	var carrying: int = _carried_by(_local_key())
	if carrying >= 0:
		_local_hold_index = -1
		_local_holding = false
		_local_hold_time = 0.0
		_send_hold_request(-1, false, delta)
		return
	var nearest: int = _nearest_present(_cart)
	_local_hold_index = nearest
	_local_holding = nearest >= 0 and Input.is_action_pressed(INTERACT_ACTION)
	if not _local_holding:
		_local_hold_time = 0.0
		_send_hold_request(-1, false, delta)
		return
	if _is_host or not _multiplayer:
		# The host already owns the authoritative progress; the ring reads it.
		_local_hold_time = _local_hold_progress(nearest)
	else:
		_local_hold_time = minf(_local_hold_time + delta, HOLD_SECONDS)
	_send_hold_request(nearest, true, delta)


func _local_hold_progress(index: int) -> float:
	if index < 0 or index >= _presents.size():
		return 0.0
	return float(_presents[index]["hold"])


func _send_hold_request(index: int, holding: bool, delta: float) -> void:
	if not _multiplayer or _is_host:
		return
	_hold_send_timer -= delta
	if _hold_send_timer > 0.0 and holding:
		return
	_hold_send_timer = HOLD_REQUEST_INTERVAL
	if not Network.is_scene_ready(1):
		return
	rpc_id(1, "_net_hold_request", index, holding)


func _carried_by(key: int) -> int:
	for index in _presents.size():
		if int(_presents[index]["state"]) == PRESENT_CARRIED \
				and int(_presents[index]["carrier"]) == key:
			return index
	return -1


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
		# The dirt strip and the skidpad are part of the shared layout.
		var flat := Vector2(cart.global_position.x, cart.global_position.z)
		if DIRT_RECT.has_point(flat):
			grip = minf(grip, DIRT_GRIP)
		var skid := flat.distance_to(SKID_CENTRE)
		if skid <= SKID_RADIUS:
			grip = minf(grip, SKID_GRIP)
		cart.surface_grip = clampf(grip, 0.2, 1.5)
		if spin <= 0.0 or not cart.is_on_floor():
			continue
		if cart.current_state != CartPlayer.CartState.DRIVING:
			continue
		var wobble: float = sin(_time * 2.7 + float(cart.get_instance_id() % 31)) * spin
		cart.rotate_y(wobble * delta * 0.30)
		cart.velocity += cart.global_transform.basis.x * wobble * delta * 1.25


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
	_timer_label = _label("5:00", 42, UiPalette.YELLOW, 8)
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
	score_column.add_child(_label("DELIVERED  ·  FIRST TO %d" % _target, 12,
		Color(1, 1, 1, 0.55)))
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
	_toast_label.offset_top = 132.0
	_toast_label.offset_bottom = 178.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.visible = false
	_hud_root.add_child(_toast_label)

	_prompt_label = _label("", 24, UiPalette.CREAM, 10)
	_prompt_label.anchor_left = 0.5
	_prompt_label.anchor_right = 0.5
	_prompt_label.anchor_top = 1.0
	_prompt_label.anchor_bottom = 1.0
	_prompt_label.offset_left = -430.0
	_prompt_label.offset_right = 430.0
	_prompt_label.offset_top = -118.0
	_prompt_label.offset_bottom = -66.0
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.visible = false
	_hud_root.add_child(_prompt_label)
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
	_theme_detail_label.text = "%s  ·  %s" % [CargoTheme.present_label(_theme),
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
				mat.albedo_color = TEAM_COLORS[team].darkened(0.10)


func _refresh_score_now() -> void:
	for team in TEAM_COUNT:
		var value: int = _score[team]
		if team < _score_labels.size():
			_score_labels[team].text = str(value)
		var text: String = "%d / %d" % [value, _target]
		for offset in 2:
			var index: int = team * 2 + offset
			if index >= _pillar_labels.size():
				continue
			var face: Label3D = _pillar_labels[index]
			if face != null and is_instance_valid(face):
				face.text = text


func _process(delta: float) -> void:
	_visual_time += delta
	_update_present_visuals(delta)
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
	_refresh_prompt()


func _refresh_prompt() -> void:
	if _prompt_label == null:
		return
	var text: String = ""
	if _phase == Phase.RACING or _phase == Phase.OVERTIME:
		var carrying: int = _carried_by(_local_key())
		if carrying >= 0 and _cart != null and is_instance_valid(_cart):
			var team: int = _local_team
			var gap: float = _planar_distance(_cart.global_position, _pads[team])
			text = "DRIVE IT HOME  ·  %s  %d m" % [_team_names[team], int(gap)]
		elif _local_hold_index >= 0:
			if _local_holding:
				# A client shows its own prediction; the host reads the
				# authoritative progress it accumulates itself.
				var progress: float = _local_hold_time
				if _is_host or not _multiplayer:
					progress = _local_hold_progress(_local_hold_index)
				text = "LOADING  ·  %.1f s" % maxf(HOLD_SECONDS - progress, 0.0)
			else:
				text = "HOLD  [%s]  TO LOAD" % _interact_key_name()
	_prompt_label.text = text
	_prompt_label.visible = text != ""


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
		pad.scale = Vector3(1.0, 1.0, 1.06)
		var tween := create_tween()
		tween.tween_property(pad, "scale", Vector3.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if team < _pillars.size() and is_instance_valid(_pillars[team]):
		var pillar: Node3D = _pillars[team]
		pillar.scale = Vector3.ONE * 1.04
		var tween := create_tween()
		tween.tween_property(pillar, "scale", Vector3.ONE, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_text("+1", _pads[team] + Vector3.UP * 4.2,
		TEAM_COLORS[team].lightened(0.35), 96)


func _pop_text(text: String, position: Vector3, colour: Color, size: int) -> void:
	var pop := Label3D.new()
	pop.name = "ScorePop"
	pop.text = text
	pop.font = load(TITLE_FONT)
	pop.font_size = size
	pop.pixel_size = 0.010
	pop.outline_size = 16
	pop.outline_modulate = UiPalette.OUTLINE
	pop.modulate = colour
	pop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pop.no_depth_test = true
	pop.position = position
	add_child(pop)
	var tween := create_tween()
	tween.tween_property(pop, "position:y", position.y + 2.6, 0.85)
	tween.parallel().tween_property(pop, "modulate:a", 0.0, 0.85)
	tween.tween_callback(pop.queue_free)


# --------------------------------------------------------------------------
# result card


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

	_result_note = _label("FIRST TO %d DELIVERIES WINS" % _target, 12,
		UiPalette.MUTED)
	_result_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_result_note)

	if _multiplayer:
		_result_primary = _make_button("BACK TO LOBBY", UiPalette.YELLOW, 58.0)
		_result_primary.pressed.connect(_on_back_to_lobby)
	else:
		_result_primary = _make_button("PLAY AGAIN", UiPalette.YELLOW, 58.0)
		_result_primary.pressed.connect(_on_play_again)
	body.add_child(_result_primary)
	var menu := _make_button("MAIN MENU", UiPalette.BLUE, 52.0)
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


func _show_result() -> void:
	var winner: int = _winner()
	var title: String = "DRAW"
	if winner == _local_team:
		title = "VICTORY!"
	elif winner >= 0:
		title = "DEFEAT"
	_result_title.text = title
	_result_subtitle.text = "%s  ·  %s" % [str(_theme.get("name", "CARGO RUSH")),
		CargoTheme.present_label(_theme)]
	for team in TEAM_COUNT:
		_result_team_labels[team].text = _team_names[team]
		_result_score_labels[team].text = str(_score[team])
	_result_note.text = "FIRST TO %d DELIVERIES WINS" % _target
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
# multiplayer: host-authoritative presents, peer-owned carts


func _setup_multiplayer() -> void:
	if not _multiplayer:
		return
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


func _on_peer_connected(peer_id: int) -> void:
	_spawn_remote_cart(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var cart: CartPlayer = _remote_carts.get(peer_id) as CartPlayer
	if cart != null:
		cart.queue_free()
		_remote_carts.erase(peer_id)
	_name_labels.erase(peer_id)
	_client_holds.erase(peer_id)
	_hold_state.erase(peer_id)
	for index in _presents.size():
		if int(_presents[index]["carrier"]) == peer_id:
			_release_present(index)


func _spawn_remote_cart(peer_id: int) -> void:
	if _remote_carts.has(peer_id) or peer_id == multiplayer.get_unique_id():
		return
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	cart.name = "Remote_%d" % peer_id
	cart.position = Vector3(0.0, 0.35, BASE_Z[0] - 3.5)
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
	if not _is_host:
		return
	_present_sync_timer += delta
	if _present_sync_timer >= PRESENT_SYNC_INTERVAL:
		_present_sync_timer = 0.0
		_broadcast_presents()
	_bot_sync_timer += delta
	if _bot_sync_timer >= PRESENT_SYNC_INTERVAL and not _bots.is_empty():
		_bot_sync_timer = 0.0
		_broadcast_bot_states()
	_state_sync_timer += delta
	if _state_sync_timer >= STATE_SYNC_INTERVAL:
		_state_sync_timer = 0.0
		_broadcast_state()


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


func _broadcast_presents() -> void:
	if _presents.is_empty():
		return
	var count: int = _presents.size()
	var states := PackedInt32Array()
	var carriers := PackedInt32Array()
	var points := PackedInt32Array()
	var holds := PackedFloat32Array()
	var positions := PackedVector3Array()
	for present: Dictionary in _presents:
		states.append(int(present["state"]))
		carriers.append(int(present["carrier"]))
		points.append(int(present["point"]))
		holds.append(float(present["hold"]))
		positions.append(present["position"] as Vector3)
	if states.size() != count:
		return
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_presents", states, carriers, points, holds,
				positions)


@rpc("authority", "unreliable")
func _net_presents(states: PackedInt32Array, carriers: PackedInt32Array,
		points: PackedInt32Array, holds: PackedFloat32Array,
		positions: PackedVector3Array) -> void:
	if _is_host or not _multiplayer:
		return
	if states.size() != _presents.size():
		return
	for index in _presents.size():
		var present: Dictionary = _presents[index]
		present["state"] = clampi(states[index], 0, 2)
		present["carrier"] = carriers[index]
		present["point"] = points[index]
		present["hold"] = holds[index] if index < holds.size() else 0.0
		if index < positions.size() and positions[index].is_finite():
			present["position"] = positions[index]
		var node: Dictionary = _present_nodes[index]
		var root: Node3D = node["root"] as Node3D
		if root == null:
			continue
		if int(present["state"]) == PRESENT_AVAILABLE:
			root.position = (present["position"] as Vector3) \
				+ Vector3.UP * PRESENT_FLOAT
		elif int(present["state"]) == PRESENT_RESPAWNING:
			root.visible = false


@rpc("any_peer", "unreliable")
func _net_hold_request(present_index: int, holding: bool) -> void:
	if not _is_host:
		return
	var sender: int = _rpc_sender()
	if sender <= 1 or sender == multiplayer.get_unique_id():
		return
	_client_holds[sender] = {
		"index": present_index,
		"holding": holding,
		"ms": Time.get_ticks_msec(),
	}


@rpc("any_peer", "reliable")
func _net_cargo_ready(theme_id: String, vehicle_id: String) -> void:
	var sender: int = _rpc_sender()
	if sender <= 1 or sender == multiplayer.get_unique_id() or not _is_host:
		return
	if vehicle_id.length() > 64:
		return
	Network.mark_peer_scene_ready(sender)
	_spawn_remote_cart(sender)
	rpc_id(sender, "_net_cargo_config", _theme_id, _bots.size(), _target)
	if _phase == Phase.FINISHED:
		rpc_id(sender, "_net_match_end", _score[0], _score[1], _winner())
	rpc_id(sender, "_net_cargo_state", _clock_seconds(), _score[0], _score[1],
		_overtime, int(_phase))
	_broadcast_presents()


@rpc("authority", "reliable")
func _net_cargo_config(theme_id: String, bot_count: int, target: int) -> void:
	if _is_host:
		return
	if CargoTheme.ids().has(theme_id) and theme_id != _theme_id:
		_theme_id = theme_id
		_theme = CargoTheme.get_theme(theme_id)
		_team_names = CargoTheme.team_names(_theme)
		_apply_theme()
		_refresh_theme_text()
		_refresh_team_texts()
		_refresh_score_now()
	_target = clampi(target, 1, 99)
	_spawn_client_bots(clampi(bot_count, 0, BOT_MAX))


func _spawn_client_bots(count: int) -> void:
	if _bots.size() == count:
		return
	for entry: Dictionary in _bots:
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart):
			cart.queue_free()
	_bots.clear()
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
	var incoming: int = clampi(phase, 0, 3)
	if incoming != int(Phase.COUNTDOWN) and _phase == Phase.COUNTDOWN:
		_start_race()
	match incoming:
		0:
			_phase = Phase.COUNTDOWN
		1:
			_phase = Phase.RACING
		2:
			_phase = Phase.OVERTIME
		_:
			_phase = Phase.FINISHED


func _broadcast_delivery(team: int, key: int) -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_cargo_delivery", team, _score[0], _score[1], key)


@rpc("authority", "reliable")
func _net_cargo_delivery(team: int, score_a: int, score_b: int,
		key: int) -> void:
	if _is_host or not _multiplayer or _phase == Phase.FINISHED:
		return
	if team < 0 or team >= TEAM_COUNT:
		return
	_score[0] = clampi(score_a, 0, 99)
	_score[1] = clampi(score_b, 0, 99)
	_show_toast("%s SCORES!" % _team_names[team], 1.5)
	_play_one_shot(DELIVERY_SFX, -5.0, 1.06)
	_flash_pad(team)
	_refresh_score_now()
	if key == _local_key():
		_show_toast("DELIVERED!", 1.4)


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
# diagnostics


func _probe_structure() -> void:
	## Headless sanity check for the real collision tree: every static body in
	## the arena is WORLD with at least one shape, and every present point is
	## clear of geometry. Gated by CART_CARGO_DEBUG, so it costs nothing in a
	## normal match.
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
	var blocked: int = 0
	for point: Dictionary in _present_points:
		var spot: Vector3 = point["position"] as Vector3
		if _point_clear(spot):
			continue
		blocked += 1
		print("CARGO_DEBUG blocked_point poi=%s at=(%.1f,%.1f)"
			% [str(point.get("poi", "?")), spot.x, spot.z])
	print("CARGO_DEBUG structure solids=%d missing_shapes=%d world_layer_ok=%s "
		% [solids, missing, str(world_ok)]
		+ "points=%d blocked_points=%d objects=%d draw_calls=%d hazards=%d"
		% [_present_points.size(), blocked, int(_stats.get("objects", 0)),
		int(_stats.get("draw_calls", 0)), _hazards.size()])


# --------------------------------------------------------------------------
# navigation


func _on_play_again() -> void:
	if _multiplayer:
		return
	SceneLoader.go_to(SCENE_PATH, "CARGO RUSH", "PRESENT RELAY")


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
	## Boots the real arena with three presents and two bots, then ticks fifteen
	## seconds of simulated play and reports what actually happened: presents
	## collected, deliveries scored and whether a bot completed a full
	## pickup-carry-deliver cycle. Run with CART_CARGO_SELFTEST=1; the scene
	## quits itself when finished.
	var started: int = Time.get_ticks_msec()
	for _frame in 900:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	print("CARGO_SELFTEST presents=%d bots=%d collected=%d deliveries=%d "
		% [_presents.size(), _bots.size(), _selftest_collected,
		_selftest_deliveries]
		+ "score=%d-%d bot_cycle=%s phase=%d sim=%.1fs"
		% [_score[0], _score[1], str(_selftest_cycle), int(_phase), seconds])
	print("CARGO_SELFTEST theme=%s objects=%d draw_calls=%d holds=%d"
		% [_theme_id, int(_stats.get("objects", 0)),
		int(_stats.get("draw_calls", 0)), _hold_state.size()])
	get_tree().quit()


# --------------------------------------------------------------------------
# helpers


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
