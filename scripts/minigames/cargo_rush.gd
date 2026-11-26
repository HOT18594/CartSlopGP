extends Node3D
## DELIVER (Cargo Rush): a two-team 2 minute cargo-crate scramble across three
## genuinely distinct 3D cartoon arenas (`harbour` Harbour Overpass, `farmyard`
## Windmill Hills, and `snowfield` Glacier Bowl).
##
## Crates spawn on custom 3D points per map — including atop the +2.2 m steel
## overpass bridge, the +2.0 m windmill hilltop plateau, and the slick 0.45-grip
## glacier ice bowl. A kart drives onto a crate (< 6.5 m/s) and HOLDS the
## interact action for 0.45 seconds to load it, then drives it home to its team
## pad. First team to BASE_TARGET deliveries wins; a tied 2:00 clock enters
## sudden-death overtime.
##
## Solo play is the local kart against the sandbox AI carts. Each rival reuses
## scripts/ai/sandbox_bot.gd as its driver and runs a four-state relay machine
## (seek / hold / carry / deposit) on top, with a claim table so two bots never
## fight over the same present.
##
## Carrying always reads at a glance: the loaded kart tows a team-coloured light
## ribbon on the floor plus a pulsing ground glow, every available present wears
## a pickup ring, and both teams stay on the HUD scoreboard for the whole match.
## A deposit plays a short three-note fanfare and the last ten tied seconds
## flash before overtime.
##
## Online play is host-authoritative for present state and scores, exactly like
## the sandbox: the host simulates holds, carriers and respawns, streams
## present snapshots at 10 Hz, peers freeze their copy and ask the host to
## start or stop a hold. Carts stream peer-to-peer through the host relay and
## scores, clock and phase are replicated as absolute values. The hold action
## is read from the InputMap on every peer, never from a hard-coded key.
##
## The headless self-test (CART_CARGO_SELFTEST=1) prints one line per step:
## select a present, drive to it, hold two seconds, pick it up, drive it to
## the team base and watch the score increment. It exits non-zero on failure.

const CART_SCENE := preload("res://scenes/player/cart_player.tscn")
const SandboxBot := preload("res://scripts/ai/sandbox_bot.gd")
const CargoTheme := preload("res://scripts/minigames/cargo_rush_theme.gd")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const VisualGrade := preload("res://scripts/systems/visual_grade.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const ResultScreen := preload("res://scripts/ui/result_screen.gd")

const SCENE_PATH: String = "res://scenes/minigames/cargo_rush.tscn"
const MAIN_MENU: String = "res://scenes/ui/main_menu.tscn"
const MINIGAMES_MENU: String = "res://scenes/ui/minigames_menu.tscn"
const UI_THEME: Theme = preload("res://assets/ui/theme.tres")
const TITLE_FONT: Font = preload("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")
const BODY_FONT: Font = preload("res://assets/ui/fonts/Fredoka-Bold.ttf")

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

const MATCH_SECONDS: float = 120.0
const OVERTIME_SECONDS: float = 60.0
const COUNTDOWN_SECONDS: float = 3.0
const BASE_TARGET: int = 8
const TEAM_COUNT: int = 2
const CORNER_RADIUS: int = 16 ## One radius for every HUD tile, per the UI kit.

## One spacing scale for the whole HUD, per the UI kit: screen margins 24, gaps
## between blocks 16, small gaps inside a row 8, corner radius 16, no dividers.
const SPACE_MARGIN: float = 24.0
const SPACE_GAP: float = 16.0
const SPACE_GAP_SMALL: float = 8.0
const SCOREBOARD_TOP: float = 12.0
const SCOREBOARD_WIDTH: float = 532.0
const SCOREBOARD_MAX_HEIGHT: float = 64.0
const TOAST_HEIGHT: float = 44.0
const PROMPT_HEIGHT: float = 48.0
const CARGO_SHADOW_COLOR := Color(0.07, 0.05, 0.15, 0.88)
const CARGO_TEXT_SHADOW := Color(0.08, 0.06, 0.16, 0.85)


class _CargoTugHeader extends Control:
	var overtime: bool = false
	var leader: int = -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var sk: float = 12.0
		var pad_l: float = 2.0
		var pad_t: float = 2.0
		var pad_r: float = 6.0
		var pad_b: float = 7.0
		var total_w: float = size.x - pad_l - pad_r - sk
		var h: float = size.y - pad_t - pad_b
		if total_w <= 60.0 or h <= 12.0:
			return
		var mid_x: float = pad_l + total_w * 0.5
		var center_w: float = 106.0
		var wing_w: float = (total_w - center_w + 12.0) * 0.5

		var blue_pts := PackedVector2Array([
			Vector2(pad_l + sk, pad_t),
			Vector2(pad_l + sk + wing_w, pad_t),
			Vector2(pad_l + wing_w, pad_t + h),
			Vector2(pad_l, pad_t + h),
		])
		var red_x0: float = pad_l + total_w - wing_w
		var red_pts := PackedVector2Array([
			Vector2(red_x0 + sk, pad_t),
			Vector2(red_x0 + sk + wing_w, pad_t),
			Vector2(red_x0 + wing_w, pad_t + h),
			Vector2(red_x0, pad_t + h),
		])
		var clk_x0: float = mid_x - center_w * 0.5
		var clk_pts := PackedVector2Array([
			Vector2(clk_x0 + sk, pad_t - 1.0),
			Vector2(clk_x0 + sk + center_w, pad_t - 1.0),
			Vector2(clk_x0 + center_w, pad_t + h + 1.0),
			Vector2(clk_x0, pad_t + h + 1.0),
		])

		# Hard comic shadows
		for poly: PackedVector2Array in [blue_pts, red_pts, clk_pts]:
			var sh := PackedVector2Array([
				poly[0] + Vector2(4.0, 5.0),
				poly[1] + Vector2(4.0, 5.0),
				poly[2] + Vector2(4.0, 5.0),
				poly[3] + Vector2(4.0, 5.0),
			])
			draw_colored_polygon(sh, CARGO_SHADOW_COLOR)

		# Left BLUE slash & Right RED slash
		var blue_col: Color = UiPalette.BLUE.lightened(0.06 if leader == 0 else 0.0)
		var red_col: Color = UiPalette.RED.lightened(0.06 if leader == 1 else 0.0)
		draw_colored_polygon(blue_pts, blue_col)
		draw_colored_polygon(red_pts, red_col)

		# White top comic sheens on both team wings
		var sh_h: float = maxf(h * 0.28, 3.0)
		for x_start: float in [pad_l, red_x0]:
			var sheen := PackedVector2Array([
				Vector2(x_start + sk + 2.0, pad_t + 2.0),
				Vector2(x_start + sk + wing_w - 2.0, pad_t + 2.0),
				Vector2(x_start + sk * 0.72 + wing_w - 2.0, pad_t + 2.0 + sh_h),
				Vector2(x_start + sk * 0.72 + 2.0, pad_t + 2.0 + sh_h),
			])
			draw_colored_polygon(sheen, Color(1.0, 1.0, 1.0, 0.24))

		for poly: PackedVector2Array in [blue_pts, red_pts]:
			var closed := poly.duplicate()
			closed.append(poly[0])
			draw_polyline(closed, UiPalette.INK, 3.5, true)

		# Center Clock Diamond/Slash Plate
		var clk_col: Color = UiPalette.PINK if overtime else UiPalette.YELLOW
		draw_colored_polygon(clk_pts, clk_col)
		var clk_sheen := PackedVector2Array([
			Vector2(clk_x0 + sk + 2.0, pad_t + 1.0),
			Vector2(clk_x0 + sk + center_w - 2.0, pad_t + 1.0),
			Vector2(clk_x0 + sk * 0.72 + center_w - 2.0, pad_t + 1.0 + sh_h),
			Vector2(clk_x0 + sk * 0.72 + 2.0, pad_t + 1.0 + sh_h),
		])
		draw_colored_polygon(clk_sheen, Color(1.0, 1.0, 1.0, 0.30))
		var clk_closed := clk_pts.duplicate()
		clk_closed.append(clk_pts[0])
		draw_polyline(clk_closed, UiPalette.INK, 4.0, true)


class _CargoPromptSlash extends Control:
	var fill_color: Color = Color("1e1b3a")
	var accent_color: Color = Color("ffd22e")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var sk: float = 12.0
		var pad_l: float = 4.0
		var pad_t: float = 3.0
		var pad_r: float = 8.0
		var pad_b: float = 8.0
		var w: float = size.x - pad_l - pad_r - sk
		var h: float = size.y - pad_t - pad_b
		if w <= 16.0 or h <= 8.0:
			return
		var pts := PackedVector2Array([
			Vector2(pad_l + sk, pad_t),
			Vector2(pad_l + sk + w, pad_t),
			Vector2(pad_l + w, pad_t + h),
			Vector2(pad_l, pad_t + h),
		])
		var sh := PackedVector2Array([
			pts[0] + Vector2(4.0, 5.0),
			pts[1] + Vector2(4.0, 5.0),
			pts[2] + Vector2(4.0, 5.0),
			pts[3] + Vector2(4.0, 5.0),
		])
		draw_colored_polygon(sh, CARGO_SHADOW_COLOR)
		draw_colored_polygon(pts, fill_color)
		var wedge := PackedVector2Array([
			Vector2(pad_l + sk, pad_t),
			Vector2(pad_l + sk + 16.0, pad_t),
			Vector2(pad_l + 16.0, pad_t + h),
			Vector2(pad_l, pad_t + h),
		])
		draw_colored_polygon(wedge, accent_color)
		draw_line(
			Vector2(pad_l + sk + 16.0, pad_t),
			Vector2(pad_l + 16.0, pad_t + h),
			UiPalette.INK, 2.5, true)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, accent_color, 3.5, true)

const TEAM_COLORS: Array[Color] = [UiPalette.BLUE, UiPalette.RED]

## Arena footprint. The barrier inner face sits exactly on ARENA_HALF.
## The whole yard is a 16 m lattice: cell centres are multiples of TILE_SIZE
## from the arena centre, so every prop is placed by the same rule.
const TILE_SIZE: float = 16.0
const ARENA_HALF: float = 56.0
const FLOOR_SIZE: float = 170.0
const BASE_Z: Array[float] = [48.0, -48.0]
const PAD_HALF: Vector2 = Vector2(8.0, 5.0)

## Kenney kit pieces used by the shared layout.
const BARRIER_MODEL: String = "barrierWall"
const GRANDSTAND_MODEL: String = "grandStand"
const LIGHT_MODEL: String = "lightPostLarge"
const BANNER_MODEL_RED: String = "bannerTowerRed"
const BANNER_MODEL_GREEN: String = "bannerTowerGreen"
const FLAG_MODEL_RED: String = "flagRed"
const FLAG_MODEL_GREEN: String = "flagGreen"

## Present rules.
const PRESENT_COUNT: int = 7
const PRESENT_RESPAWN: float = 2.2
const PICK_RADIUS: float = 4.2
const HOLD_SECONDS: float = 0.45
const HOLD_MAX_SPEED: float = 6.5
const CARRY_SLOW_SPEED: float = 0.92
const CARRY_SLOW_ACCEL: float = 0.92
const PRESENT_FLOAT: float = 0.78
const CARRY_OFFSET := Transform3D(Basis.IDENTITY, Vector3(0.0, 1.02, -1.48))
const POINT_CLEARANCE: float = 1.0

## Carry read: a light ribbon on the floor behind the loaded kart.
const CARRY_TRAIL_STEP: float = 0.72
const CARRY_TRAIL_POINTS: int = 14
const CARRY_TRAIL_HEIGHT: float = 0.13
## A carrier that fell below this height left the world: drop the present.
const CARRY_VOID_Y: float = -12.0

## Overtime drama: the clock flashes over the last tied seconds, then the
## countdown label slams "OVERTIME" when sudden death starts.
const OT_WARNING_SECONDS: int = 10
const DEPOSIT_FANFARE: Array[float] = [1.0, 1.26, 1.5]
const DEPOSIT_FANFARE_GAP: float = 0.085

## The present lattice. Every point is a cell centre, well clear of the base
## pads and the barrier ring, so a kart can reach it from any direction.
const PRESENT_SPOTS: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.0, 0.0, -32.0),
	Vector3(16.0, 0.0, 16.0),
	Vector3(-16.0, 0.0, 16.0),
	Vector3(16.0, 0.0, -16.0),
	Vector3(-16.0, 0.0, -16.0),
	Vector3(32.0, 0.0, 0.0),
	Vector3(-32.0, 0.0, 0.0),
	Vector3(32.0, 0.0, 32.0),
	Vector3(-32.0, 0.0, 32.0),
	Vector3(32.0, 0.0, -32.0),
	Vector3(-32.0, 0.0, -32.0),
	Vector3(0.0, 0.0, 32.0),
]

## Grandstand / floodlight / banner positions, all on the same lattice.
const GRANDSTAND_SPOTS: Array[Vector3] = [
	Vector3(64.0, 0.0, 0.0), Vector3(-64.0, 0.0, 0.0),
]
const GRANDSTAND_SCALE: float = TILE_SIZE * 0.75
const LIGHT_SPOTS: Array[Vector3] = [
	Vector3(64.0, 0.0, 64.0), Vector3(-64.0, 0.0, 64.0),
	Vector3(64.0, 0.0, -64.0), Vector3(-64.0, 0.0, -64.0)
]
const BANNER_SPOTS: Array[Vector3] = [
	Vector3(0.0, 0.0, 64.0), Vector3(0.0, 0.0, -64.0)
]
## Base flags flank each pad on the 16 m lattice, two per team.
const BASE_FLAG_OFFSET := Vector2(16.0, 0.0)

## Headless delivery proof.
const SELFTEST_SPAWN := Vector3(0.0, 0.35, -40.0)
const SELFTEST_APPROACH: float = 3.0
const SELFTEST_HOLD_TIMEOUT: float = 7.0
const SELFTEST_DRIVE_TIMEOUT: float = 14.0

const CART_SYNC_INTERVAL: float = 0.05
const CART_IDLE_SPEED: float = 1.0
const CART_IDLE_INTERVAL: float = 0.20
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

var _pads: Array[Vector3] = []
var _pad_visuals: Array[MeshInstance3D] = []
var _pad_labels: Array[Label3D] = []
var _pillar_labels: Array[Label3D] = []
var _pillars: Array[Node3D] = []
var _base_beams: Array[MeshInstance3D] = []
var _beam_materials: Array[StandardMaterial3D] = []
var _ambient: Array[Dictionary] = [] ## {node, base, amp, speed, phase}
var _floor: MeshInstance3D
var _checker: MultiMeshInstance3D
var _paint_lines: MeshInstance3D
var _centre_ring: MeshInstance3D

var _present_points: Array[Dictionary] = []
var _presents: Array[Dictionary] = []
var _present_nodes: Array[Dictionary] = []
var _ring_material: StandardMaterial3D
var _trail_material: StandardMaterial3D
var _trail_points: Array[PackedVector3Array] = []
var _ring_colour: Color = Color(1.0, 0.86, 0.35, 0.95)
var _point_cursor: int = 0
var _local_hold_index: int = -1
var _local_holding: bool = false
var _local_hold_time: float = 0.0
var _hold_state: Dictionary = {} ## holder key -> {index, time}
var _hold_owner: Dictionary = {} ## present index -> the one holder allowed to load it
var _claims: Dictionary = {} ## present index -> holder key
var _client_holds: Dictionary = {} ## peer id -> {index, holding, ms}
var _hold_send_timer: float = 0.0
var _hold_sent_index: int = -1
var _hold_sent_holding: bool = false
var _carry_saved: Dictionary = {} ## cart instance id -> {max_speed, acceleration}

var _cart: CartPlayer
var _hud: Node
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
var _ot_warn_second: int = 0

var _multiplayer: bool = false
var _is_host: bool = true
var _remote_carts: Dictionary = {}
var _name_labels: Dictionary = {}
var _cart_relay_ms: Dictionary = {}
var _cart_idle_ms: Dictionary = {}
var _cart_idle_pos: Dictionary = {}
var _cart_idle_yaw: Dictionary = {}
var _bot_idle_ms: int = -100000
var _bot_idle_pos: Array = []
var _present_sync_timer: float = 0.0
var _state_sync_timer: float = 0.0
var _cart_sync_timer: float = 0.0
var _bot_sync_timer: float = 0.0
var _ready_retry_timer: float = 0.0
var _net_config_received: bool = false
var _bot_sync_positions: Dictionary = {}

var _selftest: bool = false
var _debug: bool = false
var _debug_timer: float = 0.0
var _selftest_collected: int = 0
var _selftest_deliveries: int = 0
var _selftest_cycle: bool = false
var _selftest_bot: Dictionary = {}
var _selftest_cart: CartPlayer
var _selftest_present: int = -1

var _canvas: CanvasLayer
var _hud_root: Control
var _scoreboard_panel: PanelContainer
var _tug_header: _CargoTugHeader
var _timer_panel: PanelContainer
var _timer_label: Label
var _arena_tag_label: Label
var _score_labels: Array[Label] = []
var _team_name_labels: Array[Label] = []
var _countdown_label: Label
var _toast_label: Label
var _prompt_slash: _CargoPromptSlash
var _prompt_label: Label
var _toast_timer: float = 0.0
var _hud_timer: float = 0.0
var _hud_dump_frames: int = -1 ## CART_CARGO_HUD=1 prints the measured HUD rects
var _last_timer_text: String = ""
var _last_score_text: PackedStringArray = PackedStringArray()

var _result_root: Control
var _result_ui ## scripts/ui/result_screen.gd builder for the shared card layout.
var _result_card: Dictionary = {}
var _result_title: Label
var _result_subtitle: Label
var _result_score_labels: Array[Label] = []
var _result_team_labels: Array[Label] = []
var _result_note: Label
var _result_primary: Button


func _enter_tree() -> void:
	# CartPlayer reads GameSettings.selected_vehicle in its own _ready, which
	# runs before this script's _ready. Swap in the effective minigame kart and
	# put the sandbox choice back when the arena is left (memory only, not saved).
	_saved_vehicle = GameSettings.selected_vehicle
	if Network.is_session_active() and multiplayer.multiplayer_peer != null:
		GameSettings.selected_vehicle = Network.effective_vehicle_for(multiplayer.get_unique_id(), "minigame")
	else:
		GameSettings.selected_vehicle = GameSettings.minigame_vehicle


func _exit_tree() -> void:
	GameSettings.selected_vehicle = _saved_vehicle


## WS5P3-04: the room ended while this scene was streaming. Never start a
## silent offline match; return to the lobby with the disconnect notice instead.
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
	_selftest = OS.get_environment("CART_CARGO_SELFTEST") == "1"
	_debug = OS.get_environment("CART_CARGO_DEBUG") == "1"
	if OS.get_environment("CART_CARGO_HUD") == "1":
		_hud_dump_frames = 12
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
	_bind_hud()
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
	return Network.team_for_peer(multiplayer.get_unique_id())


func _on_teams_changed() -> void:
	## TEAM ASSIGNMENT HOOK: the host moved this player in the lobby. Score
	## ownership already follows Network.team_for_peer; mirror the change
	## locally so the team HUD and the "drive it home" prompt use the new pad.
	if not _multiplayer:
		return
	var team: int = _team_of_local_peer()
	if team == _local_team:
		return
	_local_team = team
	if not _team_valid(team):
		# Dropped to a spectator slot: park the kart rather than letting a
		# teamless kart drive, and keep the prompt off the pad lookup.
		_set_cart_active(false)
		_local_hold_index = -1
		_local_holding = false
		_refresh_team_texts()
		_refresh_prompt()
		return
	_refresh_team_texts()
	_refresh_prompt()


func _upgrade_graphics() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.msaa_3d = Viewport.MSAA_2X
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	VisualGrade.apply(get_node_or_null("WorldEnvironment") as WorldEnvironment, "race")
	VisualGrade.apply_sun(get_node_or_null("Sun") as DirectionalLight3D)


func _bind_hud() -> void:
	## Bind the shared driving HUD (Speedometer, Boost Meter, Drift-Charge Halo,
	## FPS, Tab Ping list) while hiding race-only lap/position/standings plaques.
	_hud = get_node_or_null("HUD")
	if _hud == null:
		return
	if _cart != null:
		if _hud.has_method("set_cart"):
			_hud.call("set_cart", _cart)
		elif _hud.has_method("bind_cart"):
			_hud.call("bind_cart", _cart)
		else:
			for prop: Dictionary in _hud.get_property_list():
				var prop_name: String = str(prop.get("name", ""))
				if prop_name == "cart" or prop_name == "target_cart":
					_hud.set(prop_name, _cart)
	if _hud.has_method("set_race_mode"):
		_hud.call("set_race_mode", false)
	elif _hud.has_method("set_race_hud_visible"):
		_hud.call("set_race_hud_visible", false)
	elif _hud.has_method("hide_race_hud"):
		_hud.call("hide_race_hud")
	for race_node_name: String in [
		"RacePlaque", "RaceBox", "RacePanel", "RaceBar",
		"LapPlaque", "LapBox", "PositionBox",
		"Standings", "StandingsBox", "StandingsPanel", "StandingsPlaque",
		"WrongWay", "WrongWayLabel", "WrongWayBanner",
	]:
		var node: CanvasItem = _hud.find_child(race_node_name, true, false) as CanvasItem
		if node != null:
			node.visible = false


# --------------------------------------------------------------------------
# arena: ground, barrier ring and dressing


func _build_arena() -> void:
	_build_ground()
	_build_perimeter()
	_build_markings()
	_build_grandstands()
	_build_floodlights()
	_build_banners()


func _build_ground() -> void:
	## One flat floor, one collider and a bold 16 m checkerboard. The checker is
	## a single MultiMesh with per-instance flat colours: no texture, one draw.
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

	var tile := PlaneMesh.new()
	tile.size = Vector2(TILE_SIZE, TILE_SIZE)
	var transforms: Array = []
	var colours: Array = []
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			transforms.append(Transform3D(Basis.IDENTITY,
				Vector3(float(ix) * TILE_SIZE, 0.014, float(iz) * TILE_SIZE)))
			colours.append(_checker_colour(ix, iz))
	_checker = SceneryKit.multimesh(tile,
		SceneryKit.instance_material(1.0), transforms, "ArenaChecker", false,
		colours)
	add_child(_checker)
	SceneryKit.bump(_stats, "draw_calls")
	SceneryKit.bump(_stats, "objects", transforms.size())


func _checker_colour(ix: int, iz: int) -> Color:
	var even: bool = (ix + iz) % 2 == 0
	return _theme.get("ground" if even else "ground_alt",
		Color("3d6b7c")) as Color


func _refresh_checker() -> void:
	if _checker == null or _checker.multimesh == null:
		return
	var multi: MultiMesh = _checker.multimesh
	for index in multi.instance_count:
		var ix: int = (index / 7) - 3
		var iz: int = (index % 7) - 3
		multi.set_instance_color(index, _checker_colour(ix, iz))


func _build_perimeter() -> void:
	## A closed ring of Kenney barrierWall pieces, 7 per side on the 16 m
	## lattice. The visual inner face is exactly ARENA_HALF and four continuous
	## WORLD boxes match it, so the playable rectangle is the visible one.
	var size: Vector3 = CargoTheme.scaled_size(BARRIER_MODEL,
		Vector3.ONE * TILE_SIZE)
	var depth: float = maxf(size.z, 0.1)
	var height: float = maxf(size.y, 0.1)
	var transforms: Array = []
	for side: float in [-1.0, 1.0]:
		for i in 7:
			var along: float = -ARENA_HALF + TILE_SIZE * (float(i) + 0.5)
			transforms.append(CargoTheme.fit_transform(BARRIER_MODEL,
				Vector3(along, 0.0, side * (ARENA_HALF + depth * 0.5)),
				0.0, Vector3.ONE * TILE_SIZE))
			transforms.append(CargoTheme.fit_transform(BARRIER_MODEL,
				Vector3(side * (ARENA_HALF + depth * 0.5), 0.0, along),
				PI * 0.5, Vector3.ONE * TILE_SIZE))
	var body: StaticBody3D = CargoTheme.solid_root(self, "ArenaBarrierCollision")
	var span: float = ARENA_HALF * 2.0 + depth * 2.0
	for side: float in [-1.0, 1.0]:
		CargoTheme.add_box_collider(body, Transform3D(Basis.IDENTITY,
			Vector3(0.0, height * 0.5,
				side * (ARENA_HALF + depth * 0.5))),
			Vector3(span, height, depth))
		CargoTheme.add_box_collider(body, Transform3D(Basis.IDENTITY,
			Vector3(side * (ARENA_HALF + depth * 0.5), height * 0.5, 0.0)),
			Vector3(depth, height, span))
	CargoTheme.batch_model(self, BARRIER_MODEL, transforms, "BarrierRing", true)
	SceneryKit.bump(_stats, "draw_calls")
	SceneryKit.bump(_stats, "objects", transforms.size())
	SceneryKit.bump(_stats, "solid_bodies")


func _build_markings() -> void:
	## Flat paint only: boundary stripes, a centre cross and a ring. None of it
	## collides, because a line on the floor is not a prop.
	_paint_lines = MeshInstance3D.new()
	_paint_lines.name = "FloorPaint"
	_paint_lines.material_override = SceneryKit.vertex_material()
	_paint_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_paint_lines)

	_centre_ring = MeshInstance3D.new()
	_centre_ring.name = "CentreRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 7.4
	torus.outer_radius = 8.4
	torus.rings = 48
	torus.ring_segments = 6
	_centre_ring.mesh = torus
	_centre_ring.scale = Vector3(1.0, 0.03, 1.0)
	_centre_ring.position = Vector3(0.0, 0.056, 0.0)
	_centre_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_centre_ring)
	_refresh_markings()
	SceneryKit.bump(_stats, "draw_calls", 2)
	SceneryKit.bump(_stats, "objects", 6)


func _refresh_markings() -> void:
	## The paint is theme-coloured, so a late client theme change rebuilds the
	## merged floor mesh instead of leaving the previous skin's stripes behind.
	if _paint_lines == null or _centre_ring == null:
		return
	var paint: Color = _theme.get("paint", UiPalette.CREAM) as Color
	var accent: Color = _theme.get("paint_alt", UiPalette.YELLOW) as Color
	var canonical: String = CargoTheme.resolve(str(_theme.get("id", "")))
	var batch := PropBatch.new()
	for side: float in [-1.0, 1.0]:
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(0.0, 0.022, side * (ARENA_HALF - 2.0))),
			Vector3(ARENA_HALF * 2.0 - 4.0, 0.04, 0.7), paint)
		batch.add_box(Transform3D(Basis.IDENTITY,
			Vector3(side * (ARENA_HALF - 2.0), 0.022, 0.0)),
			Vector3(0.7, 0.04, ARENA_HALF * 2.0 - 4.0), paint)
	if canonical == "snowfield":
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.052, 0.0)),
			Vector3(2.0, 0.02, 16.0), accent)
		batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.054, 0.0)),
			Vector3(16.0, 0.02, 2.0), accent)
	_paint_lines.mesh = batch.build()
	_centre_ring.visible = canonical == "snowfield"
	_centre_ring.material_override = CargoTheme.flat_material(accent)


func _build_grandstands() -> void:
	## Two Kenney grandstands outside the barrier, facing the arena. The whole
	## footprint is one WORLD box: a real obstacle, never drive-through dressing.
	var body: StaticBody3D = CargoTheme.solid_root(self, "GrandstandCollision")
	for index in GRANDSTAND_SPOTS.size():
		var spot: Vector3 = GRANDSTAND_SPOTS[index]
		# Kenney grandStand seats face +Z: +PI/2 on west (-X) faces east (+X) inward!
		var yaw: float = PI * 0.5 if spot.x < 0.0 else -PI * 0.5
		if CargoTheme.place_model(self, GRANDSTAND_MODEL, spot, yaw,
				Vector3.ONE * GRANDSTAND_SCALE,
				"Grandstand_%d" % index) == null:
			continue
		var size: Vector3 = CargoTheme.scaled_size(GRANDSTAND_MODEL,
			Vector3.ONE * GRANDSTAND_SCALE)
		CargoTheme.add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw),
			spot + Vector3.UP * (size.y * 0.5)), size)
		SceneryKit.bump(_stats, "objects")
		SceneryKit.bump(_stats, "draw_calls")
	SceneryKit.bump(_stats, "solid_bodies")


func _build_floodlights() -> void:
	## Four Kenney light posts on the corner cells outside the barrier. Each
	## pole is solid on WORLD with a cylinder collider.
	var body: StaticBody3D = CargoTheme.solid_root(self, "LightCollision")
	for index in LIGHT_SPOTS.size():
		var spot: Vector3 = LIGHT_SPOTS[index]
		if CargoTheme.place_model(self, LIGHT_MODEL, spot, 0.0,
				Vector3.ONE * TILE_SIZE, "Floodlight_%d" % index) == null:
			continue
		var size: Vector3 = CargoTheme.scaled_size(LIGHT_MODEL,
			Vector3.ONE * TILE_SIZE)
		CargoTheme.add_cylinder_collider(body, spot, 1.0, size.y)
		SceneryKit.bump(_stats, "objects")
		SceneryKit.bump(_stats, "draw_calls")
	SceneryKit.bump(_stats, "solid_bodies")


func _build_banners() -> void:
	## Team-coloured Kenney banner towers behind each base, outside the wall.
	var body: StaticBody3D = CargoTheme.solid_root(self, "BannerCollision")
	for index in BANNER_SPOTS.size():
		var spot: Vector3 = BANNER_SPOTS[index]
		var model: String = BANNER_MODEL_GREEN if index == 0 else BANNER_MODEL_RED
		var yaw: float = 0.0 if spot.z > 0.0 else PI
		var banner: Node3D = CargoTheme.place_model(self, model, spot, yaw,
			Vector3.ONE * TILE_SIZE, "Banner_%d" % index)
		if banner == null:
			continue
		# A slow lean on the tall banner towers, well under the collider's slack.
		_add_ambient(banner, 0.014, 0.65, float(index) * 1.9)
		var size: Vector3 = CargoTheme.scaled_size(model,
			Vector3.ONE * TILE_SIZE)
		CargoTheme.add_box_collider(body, Transform3D(Basis(Vector3.UP, yaw),
			spot + Vector3.UP * (size.y * 0.5)), size)
		SceneryKit.bump(_stats, "objects")
		SceneryKit.bump(_stats, "draw_calls")
	SceneryKit.bump(_stats, "solid_bodies")


# --------------------------------------------------------------------------
# ambient life: a little permanent motion so the yard never looks like a still


func _add_ambient(node: Node3D, amp: float, speed: float, phase: float) -> void:
	## Register a dressing node for a tiny yaw sway around its own base. The
	## colliders live on the static bodies, so moving the visual never changes
	## the playfield: this is presentation only, at a couple of degrees.
	if node == null:
		return
	var wind: float = CargoTheme.wind(_theme)
	if wind <= 0.0:
		return
	_ambient.append({
		"node": node,
		"base": node.transform,
		"amp": amp * wind,
		"speed": speed,
		"phase": phase,
	})


func _tick_ambient() -> void:
	## Cheap permanent motion: dressing sway, base-beam breathing and a slow
	## centre-ring pulse. It runs on every peer; none of it is gameplay.
	if _ambient.is_empty() and _base_beams.is_empty() and _centre_ring == null:
		return
	var t: float = _visual_time
	for entry: Dictionary in _ambient:
		var node: Node3D = entry.get("node") as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var base: Transform3D = entry.get("base", Transform3D.IDENTITY) as Transform3D
		var amp: float = float(entry.get("amp", 0.0))
		var speed: float = float(entry.get("speed", 1.0))
		var phase: float = float(entry.get("phase", 0.0))
		var sway: float = sin(t * speed + phase) * amp
		node.transform = base * Transform3D(Basis(Vector3.UP, sway), Vector3.ZERO)
	for index in _base_beams.size():
		var beam: MeshInstance3D = _base_beams[index]
		if beam == null or not is_instance_valid(beam):
			continue
		var beat: float = 0.5 + 0.5 * sin(t * 0.9 + float(index) * 1.6)
		beam.scale = Vector3(1.0 + beat * 0.06, 1.0 + beat * 0.05,
			1.0 + beat * 0.06)
		if index < _beam_materials.size():
			var mat: StandardMaterial3D = _beam_materials[index]
			if mat != null:
				var colour: Color = mat.albedo_color
				mat.albedo_color = Color(colour.r, colour.g, colour.b,
					0.10 + beat * 0.09)
	if _centre_ring != null and is_instance_valid(_centre_ring):
		var pulse: float = 0.5 + 0.5 * sin(t * 0.7)
		_centre_ring.scale = Vector3(1.0 + pulse * 0.018, 0.03,
			1.0 + pulse * 0.018)


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
		label.font = TITLE_FONT
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
	## Kenney flags on the pad corners and the scoreboard pillar. Every pole and
	## the pillar are solid on WORLD, so a kart cannot drive through base
	## furniture.
	var outward: float = signf(BASE_Z[team])
	var body := StaticBody3D.new()
	body.name = "BaseSolids_%d" % team
	body.collision_layer = CollisionLayers.WORLD
	body.collision_mask = 0
	add_child(body)
	var colour: Color = TEAM_COLORS[team]
	var flag_model: String = FLAG_MODEL_GREEN if team == 0 else FLAG_MODEL_RED
	var flag_scale: Vector3 = Vector3.ONE * 8.0
	for side: float in [-1.0, 1.0]:
		var flag_pos := Vector3(side * BASE_FLAG_OFFSET.x, 0.0,
			centre.z + outward * BASE_FLAG_OFFSET.y)
		var flag_yaw: float = -PI * 0.5 * outward
		var flag_node: Node3D = CargoTheme.place_model(self, flag_model, flag_pos,
			flag_yaw, flag_scale, "BaseFlag_%d_%d" % [team, int(side)])
		if flag_node != null:
			# Wind flutter: a few degrees of yaw, so the yard never looks frozen.
			_add_ambient(flag_node, 0.05, 1.35 + float(team) * 0.12,
				float(team) * 1.7 + side * 0.9)
			var flag_size: Vector3 = CargoTheme.scaled_size(flag_model,
				flag_scale)
			CargoTheme.add_cylinder_collider(body, flag_pos, 0.35,
				flag_size.y)
			SceneryKit.bump(_stats, "objects")
			SceneryKit.bump(_stats, "draw_calls")

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
	# The pillar is solid: the shape belongs to the team's WORLD static body,
	# not to the Node3D visual, or it would never enter the physics world.
	var pillar_shape := BoxShape3D.new()
	pillar_shape.size = Vector3(1.3, 5.2, 1.3)
	var pillar_collision := CollisionShape3D.new()
	pillar_collision.shape = pillar_shape
	pillar_collision.position = pillar_pos + Vector3.UP * 2.6
	body.add_child(pillar_collision)
	_pillars.append(pillar)

	for side: float in [-1.0, 1.0]:
		var face := Label3D.new()
		face.name = "PillarScore_%s" % ("A" if side < 0.0 else "B")
		face.text = "0 / %d" % _target
		face.font = TITLE_FONT
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
	_base_beams.append(beam)
	_beam_materials.append(beam_mat)
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
		"base_pads": _pads,
	}
	_hazards = CargoTheme.build_scenery(_theme_root, _theme, arena, _stats)
	if _floor != null:
		_floor.material_override = CargoTheme.floor_material(_theme)
	_refresh_checker()
	_refresh_markings()
	_apply_sky()
	_rebuild_present_points()
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


func _rebuild_present_points() -> void:
	_present_points.clear()
	var spots: Array[Vector3] = CargoTheme.present_spots(_theme)
	if spots.is_empty():
		spots = PRESENT_SPOTS
	for spot: Vector3 in spots:
		_add_present_point(spot, "elevated" if spot.y > 0.5 else "lane")


func _build_present_pool() -> void:
	## Build one reusable present node per slot on the map's 3D spawn points.
	## Nothing is placed in the world until the race starts, so a client never
	## shows a present the host has not spawned.
	_rebuild_present_points()
	_ring_material = StandardMaterial3D.new()
	_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_material.vertex_color_use_as_albedo = true
	_ring_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_material = StandardMaterial3D.new()
	_trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_material.vertex_color_use_as_albedo = true
	_trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in PRESENT_COUNT:
		_trail_points.append(PackedVector3Array())
		_presents.append({
			"point": -1,
			"position": Vector3.ZERO,
			"state": PRESENT_RESPAWNING,
			"carrier": 0,
			"respawn": 0.0,
			"hold": 0.0,
		})
		_present_nodes.append(_build_present_node(i))


func _add_present_point(position: Vector3, poi: String) -> void:
	_present_points.append({
		"position": Vector3(position.x, position.y, position.z),
		"poi": poi,
	})


func _build_present_node(index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Present_%02d" % index
	root.visible = false
	add_child(root)
	CargoTheme.build_present(root, _theme, index)
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
	var accent: Color = _theme.get("present_accent", CargoTheme.accent()) as Color
	halo_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.30)
	halo.material_override = halo_mat
	halo.position = Vector3(0.0, -0.70, 0.0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(halo)
	var pickup := MeshInstance3D.new()
	pickup.name = "PickupRing"
	var pickup_mesh := TorusMesh.new()
	pickup_mesh.inner_radius = 1.12
	pickup_mesh.outer_radius = 1.46
	pickup_mesh.rings = 32
	pickup_mesh.ring_segments = 6
	pickup.mesh = pickup_mesh
	pickup.scale = Vector3(1.0, 0.05, 1.0)
	pickup.position = Vector3(0.0, -0.78, 0.0)
	var pickup_mat := StandardMaterial3D.new()
	pickup_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pickup_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pickup_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pickup_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pickup_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.52)
	pickup.material_override = pickup_mat
	pickup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(pickup)
	var glow := MeshInstance3D.new()
	glow.name = "CarryGlow"
	var glow_mesh := TorusMesh.new()
	glow_mesh.inner_radius = 1.05
	glow_mesh.outer_radius = 1.62
	glow_mesh.rings = 32
	glow_mesh.ring_segments = 6
	glow.mesh = glow_mesh
	glow.scale = Vector3(1.0, 0.05, 1.0)
	glow.position = Vector3(0.0, -1.0, 0.0)
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow_mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.55)
	glow.material_override = glow_mat
	glow.visible = false
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)
	var ring_mesh := ImmediateMesh.new()
	var ring := MeshInstance3D.new()
	ring.name = "ProgressRing"
	ring.mesh = ring_mesh
	ring.visible = false
	ring.position = Vector3(0.0, 0.95, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	# The trail is world-space, so it is a sibling of the present root, not a
	# child: a child would inherit the carrier's transform every frame.
	var trail_mesh := ImmediateMesh.new()
	var trail := MeshInstance3D.new()
	trail.name = "CarryTrail_%02d" % index
	trail.mesh = trail_mesh
	trail.visible = false
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)
	return {
		"root": root,
		"halo": halo,
		"pickup": pickup,
		"pickup_mat": pickup_mat,
		"glow": glow,
		"glow_mat": glow_mat,
		"trail": trail,
		"trail_mesh": trail_mesh,
		"ring": ring,
		"ring_mesh": ring_mesh,
		"phase": float(index) * 0.9,
	}


func _refresh_present_visuals() -> void:
	## Rebuild the Kenney crate and ribbon when a client receives a new theme.
	var accent: Color = _theme.get("present_accent", CargoTheme.accent()) as Color
	_ring_colour = Color(accent.r, accent.g, accent.b, 0.95)
	for i in _present_nodes.size():
		var node: Dictionary = _present_nodes[i]
		var root: Node3D = node.get("root") as Node3D
		if root == null:
			continue
		for child: Node in root.get_children():
			if child.name == "Crate" or child.name == "Ribbon":
				child.queue_free()
		CargoTheme.build_present(root, _theme, i)
		var halo: MeshInstance3D = node.get("halo") as MeshInstance3D
		if halo != null:
			var mat: StandardMaterial3D = halo.material_override \
				as StandardMaterial3D
			if mat != null:
				mat.albedo_color = Color(accent.r, accent.g, accent.b, 0.30)
		var pickup_mat: StandardMaterial3D = node.get("pickup_mat") \
			as StandardMaterial3D
		if pickup_mat != null:
			var ring_tint: Color = CargoTheme.pickup_colour(_theme)
			pickup_mat.albedo_color = Color(ring_tint.r, ring_tint.g,
				ring_tint.b, 0.52)
		var glow_mat: StandardMaterial3D = node.get("glow_mat") \
			as StandardMaterial3D
		if glow_mat != null:
			var glow_tint: Color = CargoTheme.carry_colour(_theme)
			glow_mat.albedo_color = Color(glow_tint.r, glow_tint.g,
				glow_tint.b, 0.55)


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
	var present: Dictionary = _presents[index]
	var point: int = _free_point()
	if point < 0:
		# No clear lattice cell right now. Restart the timer instead of leaving
		# the slot stuck in RESPAWNING with a zero countdown forever.
		present["respawn"] = PRESENT_RESPAWN
		return
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
	## Every kart in range keeps its own hold progress and the first to fill
	## the ring loads the crate; a kart that drives out of range cancels
	## instantly instead of finishing its hold from a distance.
	var wants: Dictionary = _collect_hold_wants()
	var active: Dictionary = {}
	for key: int in wants.keys():
		var index: int = int(wants[key])
		if index < 0 or index >= _presents.size():
			continue
		if int(_presents[index]["state"]) != PRESENT_AVAILABLE:
			continue
		var cart: CartPlayer = _cart_for_key(key)
		if cart == null or not is_instance_valid(cart):
			continue
		if not _present_in_range(cart, index):
			continue
		var planar_speed: float = Vector2(cart.velocity.x, cart.velocity.z).length()
		if planar_speed >= HOLD_MAX_SPEED:
			continue
		active[key] = index
	for index: int in _hold_owner.keys():
		var owner: int = int(_hold_owner[index])
		if int(active.get(owner, -1)) == index:
			continue
		_hold_owner.erase(index)
	for key: int in active.keys():
		var index: int = int(active[key])
		if not _hold_owner.has(index):
			# First kart in range claims the marker; later arrivals keep their
			# own progress and the first to HOLD_SECONDS wins the crate.
			_hold_owner[index] = key
		var data: Dictionary = _hold_state.get(key, {"index": index, "time": 0.0})
		if int(data.get("index", -1)) != index:
			data = {"index": index, "time": 0.0}
		data["time"] = float(data.get("time", 0.0)) + delta
		_hold_state[key] = data
		if float(data["time"]) >= HOLD_SECONDS:
			_take_present(index, key)
	for key: int in _hold_state.keys():
		if active.has(key):
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
		if int(entry.get("state", BOT_SEEK)) != BOT_HOLD \
				or float(entry.get("hold_wait", 0.0)) > 0.0:
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
	_hold_owner.erase(index)
	_claims.erase(index)
	_reset_carry_fx(index)
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
	if _phase == Phase.FINISHED:
		return
	for index in _presents.size():
		var present: Dictionary = _presents[index]
		if int(present["state"]) != PRESENT_CARRIED:
			continue
		var key: int = int(present["carrier"])
		var cart: CartPlayer = _cart_for_key(key)
		if not _carrier_alive(cart):
			# Disconnect, freed kart or a fall out of the world: the crate is
			# dropped back into the pool instead of riding a corpse forever.
			_release_present(index)
			continue
		var team: int = _team_for_key(key)
		if team < 0 or team >= TEAM_COUNT:
			_release_present(index)
			continue
		present["position"] = cart.global_position
		if _inside_pad(cart.global_position, team):
			_deliver_present(index, key)


func _carrier_alive(cart: CartPlayer) -> bool:
	## A carrier must still be a live kart in the tree, above the void. The
	## physics body keeps running while a node is being freed, so check both.
	if cart == null or not is_instance_valid(cart) or not cart.is_inside_tree():
		return false
	return cart.global_position.y > CARRY_VOID_Y


func _deliver_present(index: int, key: int) -> void:
	## One deposit, one point. The guard makes a second delivery in the same
	## frame (two carriers touching down, or a clock tick racing the pad) a
	## no-op, and a finished match can never be scored into again.
	if index < 0 or index >= _presents.size():
		return
	if _phase == Phase.FINISHED:
		return
	if int(_presents[index]["state"]) != PRESENT_CARRIED:
		return
	var team: int = _team_for_key(key)
	if team < 0 or team >= TEAM_COUNT:
		_release_present(index)
		return
	var present: Dictionary = _presents[index]
	_score[team] = _score[team] + 1
	present["state"] = PRESENT_RESPAWNING
	present["carrier"] = 0
	present["respawn"] = PRESENT_RESPAWN
	present["hold"] = 0.0
	_reset_carry_fx(index)
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
	_play_deposit_fanfare()
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
	if is_instance_valid(cart):
		_restore_carry_slow(cart)
	_reset_carry_fx(index)
	present["state"] = PRESENT_RESPAWNING
	present["carrier"] = 0
	present["respawn"] = PRESENT_RESPAWN
	present["hold"] = 0.0
	_hold_owner.erase(index)
	_hold_state.erase(key)
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
	return absf(cart.global_position.y - (target.y + 0.35)) < 1.45


func _present_word() -> String:
	return str(_theme.get("present_kind", "present")).to_upper()


func _nearest_present(cart: CartPlayer) -> int:
	var best: int = -1
	var best_gap: float = PICK_RADIUS
	for index in _presents.size():
		if int(_presents[index]["state"]) != PRESENT_AVAILABLE:
			continue
		var target: Vector3 = _presents[index]["position"] as Vector3
		if absf(cart.global_position.y - (target.y + 0.35)) >= 1.45:
			continue
		var gap: float = _planar_distance(cart.global_position, target)
		if gap < best_gap:
			best_gap = gap
			best = index
	return best


func _update_present_visuals(delta: float) -> void:
	## Presentation only: the host owns every rule, this just draws the state.
	for index in _presents.size():
		var present: Dictionary = _presents[index]
		var node: Dictionary = _present_nodes[index]
		var root: Node3D = node["root"] as Node3D
		if root == null:
			continue
		var pickup: MeshInstance3D = node.get("pickup") as MeshInstance3D
		var glow: MeshInstance3D = node.get("glow") as MeshInstance3D
		var phase: float = float(node.get("phase", 0.0))
		match int(present["state"]):
			PRESENT_AVAILABLE:
				root.visible = true
				var base: Vector3 = present["position"] as Vector3
				root.position = base + Vector3.UP * (PRESENT_FLOAT
					+ sin(_visual_time * 2.1 + phase) * 0.09)
				root.rotate_y(delta * 1.35)
				if glow != null:
					glow.visible = false
				_update_pickup_ring(index, node, pickup, root, phase)
			PRESENT_CARRIED:
				root.visible = true
				if pickup != null:
					pickup.visible = false
				var carrier: CartPlayer = _cart_for_key(int(present["carrier"]))
				if carrier != null and is_instance_valid(carrier):
					root.global_transform = carrier.global_transform * CARRY_OFFSET
				else:
					root.position = present["position"] as Vector3
				_update_carry_fx(index, node, glow, carrier, phase)
			_:
				root.visible = false
				if pickup != null:
					pickup.visible = false
				_reset_carry_fx(index)
		_update_present_ring(index, float(present["hold"]))


func _update_pickup_ring(index: int, node: Dictionary,
		pickup: MeshInstance3D, root: Node3D, phase: float) -> void:
	## A floor decal that always says "load here", brighter the moment the local
	## kart is close enough to act on it. Its height cancels the crate's float,
	## so the ring stays glued to the floor instead of bobbing through it.
	if pickup == null or root == null:
		return
	pickup.visible = true
	var beat: float = 0.5 + 0.5 * sin(_visual_time * 2.4 + phase)
	var close: bool = _cart != null and is_instance_valid(_cart) \
		and _present_in_range(_cart, index)
	var base: Vector3 = _presents[index]["position"] as Vector3
	pickup.position.y = (base.y + 0.10) - root.position.y
	pickup.scale = Vector3(1.0 + beat * 0.06, 0.05, 1.0 + beat * 0.06)
	var mat: StandardMaterial3D = node.get("pickup_mat") as StandardMaterial3D
	if mat == null:
		return
	var tint: Color = _ring_colour
	if close:
		var team: int = _local_team if _local_team >= 0 and _local_team < TEAM_COUNT \
			else -1
		tint = TEAM_COLORS[team].lightened(0.25) if team >= 0 else _ring_colour
	mat.albedo_color = Color(tint.r, tint.g, tint.b,
		0.86 if close else 0.32 + beat * 0.26)


func _update_carry_fx(index: int, node: Dictionary, glow: MeshInstance3D,
		carrier: CartPlayer, phase: float) -> void:
	## Carrier read: a ground glow under the loaded kart and a light ribbon on
	## the floor behind it. Both are additive and cast no shadow.
	var key: int = int(_presents[index]["carrier"])
	var colour: Color = _carry_colour(key)
	var beat: float = 0.5 + 0.5 * sin(_visual_time * 5.2 + phase)
	if glow != null:
		glow.visible = _phase != Phase.FINISHED
		glow.scale = Vector3(1.0 + beat * 0.14, 0.06, 1.0 + beat * 0.14)
		var mat: StandardMaterial3D = node.get("glow_mat") as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(colour.r, colour.g, colour.b,
				0.26 + beat * 0.30)
	_update_carry_trail(index, node, carrier, colour)


func _update_carry_trail(index: int, node: Dictionary, carrier: CartPlayer,
		colour: Color) -> void:
	## A fading additive ribbon along the carrier's recent path, rebuilt as a
	## two-vertex-wide strip so one draw call covers the whole trail.
	var trail: MeshInstance3D = node.get("trail") as MeshInstance3D
	var mesh: ImmediateMesh = node.get("trail_mesh") as ImmediateMesh
	if trail == null or mesh == null or index >= _trail_points.size():
		return
	var points: PackedVector3Array = _trail_points[index]
	if carrier == null or not is_instance_valid(carrier) \
			or _phase == Phase.FINISHED:
		trail.visible = false
		points.clear()
		_trail_points[index] = points
		return
	var trail_y: float = maxf(carrier.global_position.y - 0.22,
		CARRY_TRAIL_HEIGHT)
	var here := Vector3(carrier.global_position.x, trail_y,
		carrier.global_position.z)
	if points.is_empty() \
			or points[points.size() - 1].distance_to(here) >= CARRY_TRAIL_STEP:
		points.append(here)
		while points.size() > CARRY_TRAIL_POINTS:
			points.remove_at(0)
		_trail_points[index] = points
	if points.size() < 2:
		trail.visible = false
		return
	trail.visible = true
	trail.transform = Transform3D.IDENTITY
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_material)
	var count: int = points.size()
	for i in count:
		var point: Vector3 = to_local(points[i])
		var forward: Vector3
		if i == 0:
			forward = points[1] - points[0]
		elif i == count - 1:
			forward = points[i] - points[i - 1]
		else:
			forward = points[i + 1] - points[i - 1]
		forward.y = 0.0
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD
		var side: Vector3 = forward.normalized().cross(Vector3.UP)
		var age: float = float(i) / float(count - 1)
		var half_width: float = 0.22 + 0.34 * age
		mesh.surface_set_color(Color(colour.r, colour.g, colour.b,
			age * age * 0.10))
		mesh.surface_add_vertex(point - side * half_width)
		mesh.surface_set_color(Color(colour.r, colour.g, colour.b,
			0.10 + age * age * 0.52))
		mesh.surface_add_vertex(point + side * half_width)
	mesh.surface_end()


func _reset_carry_fx(index: int) -> void:
	## Drop the carrier glow and clear the trail for one present slot.
	if index < 0 or index >= _present_nodes.size():
		return
	var node: Dictionary = _present_nodes[index]
	var glow: MeshInstance3D = node.get("glow") as MeshInstance3D
	if glow != null:
		glow.visible = false
	var trail: MeshInstance3D = node.get("trail") as MeshInstance3D
	if trail != null:
		trail.visible = false
	if index < _trail_points.size():
		_trail_points[index] = PackedVector3Array()


func _carry_colour(key: int) -> Color:
	## Team colour for a carrier's glow and trail; themed accent when the holder
	## has no resolvable team.
	var team: int = _team_for_key(key)
	if team < 0 or team >= TEAM_COUNT:
		return CargoTheme.carry_colour(_theme)
	return TEAM_COLORS[team].lightened(0.18)


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
	if _local_team < 0 or _local_team >= TEAM_COUNT:
		_cart.set_physics_process(false)
		return
	var side: float = 1.0 if _local_team == 0 else -1.0
	var position := Vector3(0.0, 0.35, side * (absf(BASE_Z[_local_team]) - 3.5))
	if _multiplayer:
		var teammates: Array[int] = []
		for peer_id: int in Network.participants():
			if Network.team_for_peer(peer_id) == _local_team:
				teammates.append(peer_id)
		teammates.sort()
		var slot: int = teammates.find(_local_key())
		if slot >= 0:
			# Keep humans on the rear, flat part of the pad, clear of bot starts.
			var columns: int = mini(teammates.size(), 3)
			var rows: int = ceili(float(teammates.size()) / float(columns))
			var row: int = slot / columns
			position.x = (float(slot % columns) - float(columns - 1) * 0.5) * 5.5
			position.z = side * (absf(BASE_Z[_local_team]) + 3.0
				- 4.0 * float(row) / float(maxi(rows - 1, 1)))
	var spawn := Transform3D(Basis(Vector3.UP, 0.0 if _local_team == 0 else PI),
		position)
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
		return 1
	if _multiplayer:
		return clampi(Network.session_bot_count, 0, BOT_MAX) if Network.session_bots else 0
	return clampi(GameSettings.effective_bot_count(), 0, BOT_MAX)


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
	if _selftest and index == 0:
		# The proof bot starts on a lattice cell in the open south half, with a
		# clear straight line to every nearby present and to its own base.
		spawn = SELFTEST_SPAWN
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
		ai.setup(cart, index, rng, Network.bot_difficulty())
	var label := Label3D.new()
	label.name = "BotTag"
	label.text = "BOT %d" % (index + 1)
	label.font = TITLE_FONT
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
		"hold_wait": 0.0,
		"blocked_time": 0.0,
		"carry_time": 0.0,
		"selftest": _selftest and index == 0,
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
	if key == 0:
		return -1
	if _multiplayer:
		return Network.team_for_peer(key)
	return _local_team if key == _local_key() else -1


func _tick_bots(delta: float) -> void:
	if _bots.is_empty():
		return
	if _multiplayer and not _is_host:
		return
	for index in _bots.size():
		var entry: Dictionary = _bots[index]
		if bool(entry.get("selftest", false)):
			# The headless proof drives this cart step by step in
			# _run_self_test; normal relay AI must not fight it.
			continue
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
			entry["hold_wait"] = maxf(float(entry.get("hold_wait", 0.0)) - delta, 0.0)
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
			if _hold_owner.has(hold_index) \
					and int(_hold_owner[hold_index]) != key:
				# Another kart owns this crate. Waiting forever would park the
				# bot on a present it can never load, so give up and re-pick.
				entry["blocked_time"] = float(entry.get("blocked_time", 0.0)) \
					+ delta
				if float(entry["blocked_time"]) > 2.5:
					_bot_release(entry, key)
					entry["state"] = BOT_SEEK
					entry["blocked_time"] = 0.0
				_bot_stop(cart)
				return
			entry["blocked_time"] = 0.0
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
			# A carrier that is wedged or flung out of the world drops the crate
			# and respawns, so one bad tumble cannot hold a present all match.
			if float(entry["carry_time"]) > 40.0 or ai.stuck > 6.0 \
					or ai.stranded > 2.0 or not _carrier_alive(cart):
				_release_present(carry_index)
				_bot_release(entry, key)
				entry["state"] = BOT_SEEK
				entry["carry_time"] = 0.0
				ai.respawn()
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
		var reaction: Array[float] = [1.15, 0.70, 0.35]
		entry["hold_wait"] = reaction[Network.bot_difficulty()] + float(index % 3) * 0.08
		_bot_stop(cart)
		return
	var target: Vector3 = _presents[present_index]["position"] as Vector3
	entry["seek_time"] = float(entry.get("seek_time", 0.0)) + delta
	# Easy bots lose interest sooner, Hard bots grind a bad pick longer.
	if float(entry["seek_time"]) > [20.0, 26.0, 32.0][Network.bot_difficulty()]:
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
		if _hold_owner.has(present_index) \
				and int(_hold_owner[present_index]) != key:
			# Somebody is already loading it: pick another cell rather than
			# circling a crate that cannot be claimed.
			continue
		var position: Vector3 = _presents[present_index]["position"] as Vector3
		var to_present: float = _planar_distance(cart.global_position, position)
		var to_base: float = _planar_distance(position, _pads[team])
		var score: float = (to_present + to_base * 0.55) * bias
		# Easy bots misjudge distances and grab suboptimal crates; Hard bots
		# take the optimum every time. Same speed and loading rules either way.
		if Network.bot_difficulty() == 0:
			score *= 1.0 + float((key + present_index * 3) % 5) * 0.12
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
	## Hold the brake only while there is forward speed. A held brake below the
	## reverse threshold starts backing the kart up after 0.12 s, which used to
	## make a bot drift off a present while it was loading it.
	if cart == null or not is_instance_valid(cart):
		return
	var speed: float = Vector2(cart.velocity.x, cart.velocity.z).length()
	if speed > 0.8:
		cart.set_ai_controls(0.0, 1.0, 0.0)
	else:
		cart.set_ai_controls(0.0, 0.0, 0.0)


func _bot_drive(cart: CartPlayer, ai: SandboxBot, target: Vector3,
		delta: float, speed_scale: float) -> void:
	var difficulty_speed: Array[float] = [0.72, 0.88, 1.0]
	speed_scale *= difficulty_speed[Network.bot_difficulty()]
	var waypoint: Vector3 = _elevated_waypoint(cart, target)
	var gap: float = _planar_distance(cart.global_position, waypoint)
	if gap > BOT_NEAR_DRIVE:
		_sandbox_drive(ai, cart, waypoint, delta)
		return
	_drive_to(cart, waypoint, speed_scale)


func _elevated_waypoint(cart: CartPlayer, target: Vector3) -> Vector3:
	## Routes ground-level AI karts cleanly onto the N/S bridge approach ramps
	## (`harbour`) or the 4 hilltop dirt ramps (`farmyard`) when seeking a crate
	## perched on an elevated 3D deck.
	if cart == null or target.y < 1.0 or cart.global_position.y >= target.y - 0.8:
		return target
	var pos: Vector3 = cart.global_position
	var canonical: String = CargoTheme.resolve(_theme_id)
	if canonical == "harbour":
		if absf(pos.x) <= 4.6 and absf(pos.z) >= 13.0:
			return target
		var ramp_z: float = -25.5 if pos.z < 0.0 else 25.5
		return Vector3(0.0, 0.0, ramp_z)
	if canonical == "farmyard":
		if absf(pos.x) <= 4.5 or absf(pos.z) <= 4.5:
			return target
		var mouths: Array[Vector3] = [
			Vector3(0.0, 0.0, -22.5),
			Vector3(0.0, 0.0, 22.5),
			Vector3(22.5, 0.0, 0.0),
			Vector3(-22.5, 0.0, 0.0),
		]
		var best_mouth: Vector3 = mouths[0]
		var best_dist: float = INF
		for mouth: Vector3 in mouths:
			var dist: float = _planar_distance(pos, mouth)
			if dist < best_dist:
				best_dist = dist
				best_mouth = mouth
		return best_mouth
	return target


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
	var desired: float = (12.0 if distance > 10.0
		else lerpf(3.2, 11.0, clampf(distance / 10.0, 0.0, 1.0))) * speed_scale
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
	_overtime_remaining = 0.0
	_ot_warn_second = 0
	_hold_sent_index = -1
	_hold_sent_holding = false
	_hold_send_timer = 0.0
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
	## An unseated local player (spectator slot, team -1) never gets a drivable
	## kart, even when the race starts: start_race used to switch physics back
	## on for a kart that was parked because it had no team.
	if _cart == null or not is_instance_valid(_cart):
		return
	var drivable: bool = active and _team_valid(_local_team)
	_cart.set_physics_process(drivable)
	if not drivable:
		_cart.velocity = Vector3.ZERO


func _team_valid(team: int) -> bool:
	## Every HUD/pad/score lookup goes through this: team -1 is a real state
	## (unassigned peer or spectator) and must never index a two-team table.
	return team >= 0 and team < TEAM_COUNT


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
	if _score[0] == _score[1] and _score[0] < _target:
		_begin_overtime()
	else:
		_finish_match()


func _tick_overtime_warning() -> void:
	## The last ten tied seconds flash the clock and pop once per second, so
	## sudden death never arrives as a surprise.
	if _phase != Phase.RACING or _timer_label == null:
		return
	if _score[0] != _score[1]:
		_ot_warn_second = 0
		return
	var seconds: int = int(ceil(_remaining))
	if seconds <= 0 or seconds > OT_WARNING_SECONDS:
		return
	if seconds == _ot_warn_second:
		return
	_ot_warn_second = seconds
	_flash_timer()
	_pop_label(_timer_label)
	if seconds == OT_WARNING_SECONDS:
		_show_toast("TIED  ·  OVERTIME IN %d" % seconds, 1.5)
	elif seconds <= 3:
		_play_one_shot(COUNTDOWN_BEEP, -10.0, 1.0 + float(3 - seconds) * 0.10)


func _begin_overtime() -> void:
	## Sudden death. The countdown label is reused for the slam, because the
	## regular countdown has long finished by the time this can fire.
	_phase = Phase.OVERTIME
	_overtime = true
	_overtime_remaining = _overtime_length
	_ot_warn_second = 0
	_show_toast("OVERTIME  ·  NEXT DELIVERY WINS", 2.6)
	if _countdown_label != null:
		_countdown_label.text = "OVERTIME"
		_countdown_label.visible = true
		_pop_label(_countdown_label)
		var tween := create_tween()
		tween.tween_interval(1.1)
		tween.tween_callback(_hide_countdown_label)
	_play_one_shot(COUNTDOWN_GO, -6.0, 0.86)
	if _debug:
		print("CARGO_DEBUG overtime start")
	if _multiplayer and _is_host:
		_broadcast_state()


func _hide_countdown_label() -> void:
	## Clear the overtime slam label without touching a live countdown.
	if _countdown_label != null and _phase != Phase.COUNTDOWN:
		_countdown_label.visible = false
		_countdown_label.text = "3"


func _flash_timer() -> void:
	## Red-to-white flash on the clock for the overtime warning beats.
	if _timer_label == null:
		return
	_timer_label.modulate = Color(1.0, 0.52, 0.38)
	var tween := create_tween()
	tween.tween_property(_timer_label, "modulate", Color.WHITE, 0.42) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _finish_match() -> void:
	if _phase == Phase.FINISHED:
		return
	_phase = Phase.FINISHED
	_hold_state.clear()
	_hold_owner.clear()
	# Loaded crates must not freeze on karts after the whistle: drop every
	# carried present back into the pool instead of scoring it after time.
	for index in _presents.size():
		if int(_presents[index]["state"]) == PRESENT_CARRIED:
			_release_present(index)
	_hold_sent_index = -1
	_hold_sent_holding = false
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
	## This runs on every peer, host or client, and always reads the local
	## InputMap. A client therefore presses E on its own machine and sends the
	## hold request to the host; the key is never host-only.
	if _cart == null or not is_instance_valid(_cart):
		return
	if not _team_valid(_local_team):
		# A peer with no team has no pad to deliver to: it cannot load a crate.
		_local_hold_index = -1
		_local_holding = false
		_local_hold_time = 0.0
		_send_hold_request(-1, false, delta)
		return
	var carrying: int = _carried_by(_local_key())
	if carrying >= 0:
		# The host slows its authoritative ghost; a client must apply the same
		# carry penalty to its own physical kart or it would drive at full speed.
		if _multiplayer and not _is_host:
			_apply_carry_slow(_cart)
		_local_hold_index = -1
		_local_holding = false
		_local_hold_time = 0.0
		_send_hold_request(-1, false, delta)
		return
	if _multiplayer and not _is_host:
		_restore_carry_slow(_cart)
	var nearest: int = _nearest_present(_cart)
	_local_hold_index = nearest
	var planar_speed: float = Vector2(_cart.velocity.x, _cart.velocity.z).length()
	_local_holding = nearest >= 0 and planar_speed < HOLD_MAX_SPEED \
		and Input.is_action_pressed(INTERACT_ACTION)
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
	## Client-only side of the hold. The request is unreliable and repeated at
	## 10 Hz while E is down; the cancel is reliable, because a dropped release
	## used to keep the host accumulating a hold for another 500 ms after the
	## kart had already driven away.
	if not _multiplayer or _is_host:
		return
	if not holding:
		if not _hold_sent_holding:
			return
		_hold_sent_holding = false
		_hold_sent_index = -1
		_hold_send_timer = 0.0
		if Network.is_scene_ready(1):
			rpc_id(1, "_net_hold_cancel")
		return
	if index != _hold_sent_index:
		_hold_sent_index = index
		_hold_send_timer = 0.0
	_hold_send_timer -= delta
	if _hold_send_timer > 0.0:
		return
	_hold_send_timer = HOLD_REQUEST_INTERVAL
	_hold_sent_holding = true
	if not Network.is_scene_ready(1):
		return
	rpc_id(1, "_net_hold_request", index, true)


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
		var drag: float = 0.0
		var pos: Vector3 = cart.global_position
		for zone: Dictionary in _hazards:
			var max_y: float = float(zone.get("max_y", INF))
			if pos.y > max_y:
				continue
			var centre: Vector3 = zone.get("centre", Vector3.ZERO) as Vector3
			var inside: bool = false
			if zone.has("half_extents"):
				var half_ext: Vector2 = zone["half_extents"] as Vector2
				inside = absf(pos.x - centre.x) <= half_ext.x \
					and absf(pos.z - centre.z) <= half_ext.y
			else:
				var radius: float = float(zone.get("radius", 0.0))
				var dx: float = pos.x - centre.x
				var dz: float = pos.z - centre.z
				inside = dx * dx + dz * dz <= radius * radius
			if inside:
				grip = minf(grip, float(zone.get("grip", grip)))
				spin = maxf(spin, float(zone.get("spin", 0.0)))
				drag = maxf(drag, float(zone.get("drag", 0.0)))
		cart.surface_grip = clampf(grip, 0.2, 1.5)
		if not cart.is_on_floor():
			continue
		if drag > 1.0:
			var damp: float = clampf(1.0 - (drag - 1.0) * delta * 1.8, 0.82, 1.0)
			cart.velocity.x *= damp
			cart.velocity.z *= damp
		if spin <= 0.0 or cart.current_state != CartPlayer.CartState.DRIVING:
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
	_hud_root.theme = UI_THEME
	_canvas.add_child(_hud_root)

	# Blue-vs-Red Skewed Parallelogram Tug-of-War Header (StyleBoxEmpty outer box!)
	_scoreboard_panel = PanelContainer.new()
	_scoreboard_panel.name = "ScoreboardBar"
	_scoreboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scoreboard_panel.anchor_left = 0.5
	_scoreboard_panel.anchor_right = 0.5
	_scoreboard_panel.offset_left = -SCOREBOARD_WIDTH * 0.5
	_scoreboard_panel.offset_right = SCOREBOARD_WIDTH * 0.5
	_scoreboard_panel.offset_top = SCOREBOARD_TOP
	_scoreboard_panel.offset_bottom = SCOREBOARD_TOP + 54.0
	_scoreboard_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_tug_header = _CargoTugHeader.new()
	_tug_header.name = "TugOfWarSlash"
	_tug_header.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scoreboard_panel.add_child(_tug_header)
	_hud_root.add_child(_scoreboard_panel)
	_timer_panel = _scoreboard_panel

	var bar_margin := MarginContainer.new()
	bar_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_margin.add_theme_constant_override("margin_left", 26)
	bar_margin.add_theme_constant_override("margin_top", 8)
	bar_margin.add_theme_constant_override("margin_right", 28)
	bar_margin.add_theme_constant_override("margin_bottom", 12)
	_scoreboard_panel.add_child(bar_margin)

	var bar_column := VBoxContainer.new()
	bar_column.alignment = BoxContainer.ALIGNMENT_CENTER
	bar_column.add_theme_constant_override("separation", 0)
	bar_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_margin.add_child(bar_column)

	var main_row := HBoxContainer.new()
	main_row.alignment = BoxContainer.ALIGNMENT_CENTER
	main_row.add_theme_constant_override("separation", 8)
	main_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_column.add_child(main_row)

	var name_a := _label(_team_names[0], 15, UiPalette.CREAM, 6)
	name_a.custom_minimum_size = Vector2(142.0, 0.0)
	name_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_a.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_a.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_a.clip_text = true
	main_row.add_child(name_a)
	_team_name_labels.append(name_a)

	var score_a := _label("0", 26, UiPalette.YELLOW, 7)
	score_a.custom_minimum_size = Vector2(34.0, 38.0)
	score_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_a.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main_row.add_child(score_a)
	_score_labels.append(score_a)

	_timer_label = _label("2:00", 23, UiPalette.INK, 0, false)
	_timer_label.custom_minimum_size = Vector2(106.0, 38.0)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main_row.add_child(_timer_label)

	var score_b := _label("0", 26, UiPalette.CREAM, 7)
	score_b.custom_minimum_size = Vector2(34.0, 38.0)
	score_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main_row.add_child(score_b)
	_score_labels.append(score_b)

	var name_b := _label(_team_names[1], 15, UiPalette.CREAM, 6)
	name_b.custom_minimum_size = Vector2(142.0, 0.0)
	name_b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_b.clip_text = true
	main_row.add_child(name_b)
	_team_name_labels.append(name_b)

	# Preserved hidden reference so _refresh_theme_text() stays valid without height bloat.
	_arena_tag_label = _label("", 11, UiPalette.CREAM, 5)
	_arena_tag_label.visible = false
	bar_column.add_child(_arena_tag_label)

	_countdown_label = _label("3", 108, UiPalette.YELLOW, 14)
	_countdown_label.anchor_left = 0.5
	_countdown_label.anchor_right = 0.5
	_countdown_label.anchor_top = 0.5
	_countdown_label.anchor_bottom = 0.5
	_countdown_label.offset_left = -320.0
	_countdown_label.offset_right = 320.0
	_countdown_label.offset_top = -78.0
	_countdown_label.offset_bottom = 78.0
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud_root.add_child(_countdown_label)

	_toast_label = _label("", 24, UiPalette.YELLOW, 9)
	_toast_label.anchor_left = 0.5
	_toast_label.anchor_right = 0.5
	_toast_label.offset_left = -360.0
	_toast_label.offset_right = 360.0
	_toast_label.offset_top = SCOREBOARD_TOP + 66.0
	_toast_label.offset_bottom = SCOREBOARD_TOP + 66.0 + TOAST_HEIGHT
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.clip_text = true
	_toast_label.visible = false
	_hud_root.add_child(_toast_label)

	_prompt_slash = _CargoPromptSlash.new()
	_prompt_slash.name = "PromptSlash"
	_prompt_slash.anchor_left = 0.5
	_prompt_slash.anchor_right = 0.5
	_prompt_slash.anchor_top = 1.0
	_prompt_slash.anchor_bottom = 1.0
	_prompt_slash.offset_left = -256.0
	_prompt_slash.offset_right = 256.0
	_prompt_slash.offset_top = -SPACE_MARGIN - PROMPT_HEIGHT - 22.0
	_prompt_slash.offset_bottom = -SPACE_MARGIN - 18.0
	_prompt_slash.visible = false
	_hud_root.add_child(_prompt_slash)

	var controls_hint := _label("WASD DRIVE  ·  SPACE DRIFT  ·  SHIFT BOOST", 13, Color(0.92, 0.94, 0.98, 0.85), 3)
	controls_hint.name = "CargoControlsHint"
	controls_hint.anchor_left = 0.5
	controls_hint.anchor_right = 0.5
	controls_hint.anchor_top = 1.0
	controls_hint.anchor_bottom = 1.0
	controls_hint.offset_left = -240.0
	controls_hint.offset_right = 240.0
	controls_hint.offset_top = -28.0
	controls_hint.offset_bottom = -6.0
	controls_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_root.add_child(controls_hint)

	_prompt_label = _label("", 19, UiPalette.YELLOW, 7)
	_prompt_label.anchor_left = 0.5
	_prompt_label.anchor_right = 0.5
	_prompt_label.anchor_top = 1.0
	_prompt_label.anchor_bottom = 1.0
	_prompt_label.offset_left = -244.0
	_prompt_label.offset_right = 244.0
	_prompt_label.offset_top = -SPACE_MARGIN - PROMPT_HEIGHT
	_prompt_label.offset_bottom = -SPACE_MARGIN
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.clip_text = true
	_prompt_label.visible = false
	_hud_root.add_child(_prompt_label)
	_layout_hud()
	_refresh_theme_text()
	_refresh_team_texts()
	_refresh_score_now()


func _layout_hud() -> void:
	## Measure the compact top-center scoreboard bar after layout (<= 64 px tall)
	## and hang the toast cleanly below it so nothing overlaps at 960x540 or
	## 1280x720.
	if _toast_label == null or _scoreboard_panel == null:
		return
	var minimum: Vector2 = _scoreboard_panel.get_combined_minimum_size()
	var wanted_w: float = maxf(SCOREBOARD_WIDTH, minimum.x + 8.0)
	var wanted_h: float = clampf(maxf(minimum.y, 50.0), 50.0, SCOREBOARD_MAX_HEIGHT)
	if absf(_scoreboard_panel.offset_left + wanted_w * 0.5) > 0.5 \
			or absf(_scoreboard_panel.offset_right - wanted_w * 0.5) > 0.5:
		_scoreboard_panel.offset_left = -wanted_w * 0.5
		_scoreboard_panel.offset_right = wanted_w * 0.5
	if absf(_scoreboard_panel.offset_bottom - (SCOREBOARD_TOP + wanted_h)) > 0.5:
		_scoreboard_panel.offset_top = SCOREBOARD_TOP
		_scoreboard_panel.offset_bottom = SCOREBOARD_TOP + wanted_h
	var top: float = SCOREBOARD_TOP + wanted_h + 12.0
	if absf(_toast_label.offset_top - top) > 0.5:
		_toast_label.offset_top = top
		_toast_label.offset_bottom = top + TOAST_HEIGHT


func _print_hud_rects() -> void:
	## Measurement, not eyeballing: CART_CARGO_HUD=1 dumps every HUD rect and
	## the content minimum it has to hold at both 960x540 and 1280x720.
	var vp: Viewport = get_viewport()
	var view: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1280.0, 720.0)
	print("CARGO_HUD viewport=%dx%d margin=%.0f gap=%.0f small=%.0f radius=%d"
		% [int(view.x), int(view.y), SPACE_MARGIN, SPACE_GAP, SPACE_GAP_SMALL,
		CORNER_RADIUS])
	var rows: Array = [
		["scoreboard", _scoreboard_panel], ["toast", _toast_label],
		["prompt", _prompt_label], ["countdown", _countdown_label],
	]
	for row: Array in rows:
		var control: Control = row[1] as Control
		if control == null or not is_instance_valid(control):
			continue
		var rect: Rect2 = control.get_global_rect()
		var minimum: Vector2 = control.get_combined_minimum_size()
		print("CARGO_HUD %s rect=(%.0f,%.0f %.0fx%.0f) min=(%.0fx%.0f)"
			% [str(row[0]), rect.position.x, rect.position.y, rect.size.x,
			rect.size.y, minimum.x, minimum.y])
	print("CARGO_HUD clips=%s" % str(_hud_clips()))


func _hud_clips() -> bool:
	## True if any HUD control leaves the viewport, exceeds the 64 px scoreboard
	## height budget, or is smaller than its own content minimum.
	var vp: Viewport = get_viewport()
	var view: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1280.0, 720.0)
	if _scoreboard_panel != null and is_instance_valid(_scoreboard_panel):
		if _scoreboard_panel.get_global_rect().size.y > SCOREBOARD_MAX_HEIGHT + 0.5:
			return true
	for control: Control in [_scoreboard_panel, _toast_label, _prompt_label,
			_countdown_label]:
		if control == null or not is_instance_valid(control):
			continue
		var rect: Rect2 = control.get_global_rect()
		if rect.position.x < -0.5 or rect.position.y < -0.5 \
				or rect.end.x > view.x + 0.5 or rect.end.y > view.y + 0.5:
			return true
		var minimum: Vector2 = control.get_combined_minimum_size()
		if minimum.x > rect.size.x + 0.5 or minimum.y > rect.size.y + 0.5:
			return true
	return false


func _scoreboard_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.118, 0.106, 0.227, 0.88)
	style.border_color = UiPalette.OUTLINE
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	style.anti_aliasing = true
	return style


func _label(text: String, size: int, colour: Color, outline: int = 0,
		hard_shadow: Variant = null) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"TitleLabel"
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if outline > 0:
		label.add_theme_color_override("font_outline_color", UiPalette.INK)
		label.add_theme_constant_override("outline_size", mini(outline, 3))
	else:
		label.add_theme_constant_override("outline_size", 0)
	var use_shadow: bool = (outline >= 5) if hard_shadow == null else bool(hard_shadow)
	if use_shadow:
		label.add_theme_color_override("font_shadow_color", CARGO_TEXT_SHADOW)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 2)
	else:
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 0)
	return label


func _refresh_theme_text() -> void:
	if _arena_tag_label == null:
		return
	var ot_now: bool = _overtime and _phase != Phase.FINISHED
	if _tug_header != null and _tug_header.overtime != ot_now:
		_tug_header.overtime = ot_now
		_tug_header.queue_redraw()
		if _timer_label != null:
			_timer_label.add_theme_constant_override("outline_size", 5 if ot_now else 0)
			_timer_label.add_theme_color_override("font_color",
				UiPalette.CREAM if ot_now else UiPalette.INK)
	var arena_name: String = str(_theme.get("name", "DOCKYARD"))
	var blurb: String = str(_theme.get("blurb", "")).strip_edges()
	if _overtime and _phase != Phase.FINISHED:
		_arena_tag_label.text = "OVERTIME  ·  NEXT DELIVERY WINS  ·  %s" % arena_name
		_arena_tag_label.add_theme_color_override("font_color", UiPalette.YELLOW)
	else:
		_arena_tag_label.text = ("FIRST TO %d  ·  %s  ·  %s" % [_target, arena_name, blurb]) \
			if blurb != "" else ("FIRST TO %d  ·  %s" % [_target, arena_name])
		_arena_tag_label.add_theme_color_override("font_color",
			Color(1.0, 1.0, 1.0, 0.68))


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
	## Both teams are always on the board, each with its progress to the target
	## so a glance answers "who is winning and how close is it".
	_refresh_theme_text()
	var leader: int = _leader()
	if _tug_header != null:
		_tug_header.overtime = _overtime and _phase != Phase.FINISHED
		_tug_header.leader = leader
		_tug_header.queue_redraw()
	if _timer_label != null:
		var ot_active: bool = _overtime and _phase != Phase.FINISHED
		_timer_label.add_theme_constant_override("outline_size", 5 if ot_active else 0)
		_timer_label.add_theme_color_override("font_color",
			UiPalette.CREAM if ot_active else UiPalette.INK)
	for team in TEAM_COUNT:
		var value: int = _score[team]
		if team < _score_labels.size():
			_score_labels[team].text = str(value)
			_score_labels[team].add_theme_color_override("font_color",
				UiPalette.YELLOW if team == leader else UiPalette.CREAM)
		var text: String = "%d / %d" % [value, _target]
		for offset in 2:
			var index: int = team * 2 + offset
			if index >= _pillar_labels.size():
				continue
			var face: Label3D = _pillar_labels[index]
			if face != null and is_instance_valid(face):
				face.text = text


func _leader() -> int:
	## The team currently ahead, or -1 when the relay is level.
	if _score[0] == _score[1]:
		return -1
	return 0 if _score[0] > _score[1] else 1


func _process(delta: float) -> void:
	if _hud_dump_frames > 0:
		_hud_dump_frames -= 1
		if _hud_dump_frames == 0:
			_print_hud_rects()
	_visual_time += delta
	_update_present_visuals(delta)
	_tick_ambient()
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
	_refresh_theme_text()
	var scores := PackedStringArray([str(_score[0]), str(_score[1])])
	if scores != _last_score_text:
		_last_score_text = scores
		_refresh_score_now()
	_refresh_prompt()
	_layout_hud()
	_tick_overtime_warning()


func _refresh_prompt() -> void:
	if _prompt_label == null:
		return
	var text: String = ""
	if _phase == Phase.RACING or _phase == Phase.OVERTIME:
		var carrying: int = _carried_by(_local_key())
		if not _team_valid(_local_team):
			# No team means no pad to drive to: never index _pads[-1].
			text = ""
		elif carrying >= 0 and _cart != null and is_instance_valid(_cart):
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
				text = "LOADING  ·  %.2f s" % maxf(HOLD_SECONDS - progress, 0.0)
			elif _cart != null and is_instance_valid(_cart) \
					and Vector2(_cart.velocity.x, _cart.velocity.z).length() >= HOLD_MAX_SPEED \
					and Input.is_action_pressed(INTERACT_ACTION):
				text = "SLOW DOWN TO LOAD  ·  [%s]" % _interact_key_name()
			else:
				text = "HOLD  [%s]  TO LOAD" % _interact_key_name()
	_prompt_label.text = text
	_prompt_label.visible = text != ""
	if _prompt_slash != null:
		_prompt_slash.visible = text != ""
		var carrying_now: bool = _carried_by(_local_key()) >= 0
		_prompt_slash.accent_color = TEAM_COLORS[_local_team] \
			if (carrying_now and _team_valid(_local_team)) else UiPalette.YELLOW
		_prompt_slash.queue_redraw()


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
	if not _team_valid(team):
		return
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
	pop.font = TITLE_FONT
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
	_result_ui = ResultScreen.new()
	_result_card = _result_ui.build(_hud_root, {
		"name": "ResultCard",
		"title": "VICTORY!",
		"subtitle": "",
		"multiplayer": _multiplayer,
		"is_host": _is_host,
		"panel_width": 760.0,
		"primary_text": "PLAY AGAIN" if (not _multiplayer or _is_host) else "",
		"primary_color": UiPalette.YELLOW,
		"on_primary": _on_play_again,
		"secondary_text": "BACK TO LOBBY" if _multiplayer else "BACK TO MODES",
		"secondary_color": UiPalette.CYAN if (not _multiplayer or _is_host) else UiPalette.YELLOW,
		"on_secondary": _on_back_to_lobby,
		"tertiary_text": "MAIN MENU",
		"tertiary_color": UiPalette.RED,
		"on_tertiary": _on_main_menu,
		# 0.8.7 host/non-host contract (resolved in result_screen.gd): host MAIN
		# MENU is confirm-gated in a live room; a client gets the waiting status +
		# LEAVE LOBBY instead of host-only navigation.
		"confirm_main_menu": _multiplayer,
		"on_leave": _on_main_menu,
	})
	_result_root = _result_card["root"] as Control
	_result_title = _result_card["title"] as Label
	_result_subtitle = _result_card["subtitle"] as Label
	_result_primary = _result_card.get("primary") as Button
	var pause_menu: Control = get_node_or_null("PauseMenu/Root") as Control
	if pause_menu != null and not pause_menu.visibility_changed.is_connected(_on_pause_visibility_changed):
		pause_menu.visibility_changed.connect(_on_pause_visibility_changed)

	# Team score plates: the headline telemetry of the Cargo Rush card.
	var telemetry: VBoxContainer = _result_card["telemetry"] as VBoxContainer
	var scores := HBoxContainer.new()
	scores.alignment = BoxContainer.ALIGNMENT_CENTER
	scores.add_theme_constant_override("separation", UiKit.SPACING)
	telemetry.add_child(scores)
	var team_accents: Array[Color] = [UiPalette.BLUE, UiPalette.RED]
	for team in TEAM_COUNT:
		var score_card := PanelContainer.new()
		score_card.custom_minimum_size = Vector2(180.0, 0.0)
		score_card.add_theme_stylebox_override("panel",
			UiKit.slanted_card(UiPalette.SURFACE_CARD, team_accents[team],
				0.14, 2, 5, 18.0, 12.0))
		scores.add_child(score_card)
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 2)
		score_card.add_child(column)
		var team_label := _label(_team_names[team], 14, team_accents[team])
		team_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(team_label)
		var value := _label("0", 38, UiPalette.CREAM, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(value)
		_result_team_labels.append(team_label)
		_result_score_labels.append(value)

	_result_note = _label("FIRST TO %d DELIVERIES WINS" % _target,
		int(UiKit.CAPTION_SIZE), UiPalette.TEXT_DIM)
	_result_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	telemetry.add_child(_result_note)


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
	_result_ui.present(_result_card)
	CursorController.set_menu_mode(true)
	var pause_root: Control = get_node_or_null("PauseMenu/Root") as Control
	if pause_root != null and pause_root.visible:
		_result_root.remove_from_group("nav_scope")
	else:
		if not _result_root.is_in_group("nav_scope"):
			_result_root.add_to_group("nav_scope")
		MenuNav.refresh()
		var focus_btn: Control = _result_ui.focus_default(_result_card)
		if focus_btn != null:
			MenuNav.focus(focus_btn)
	_play_one_shot(FINISH_FANFARE, -7.0, 1.0)


func _on_pause_visibility_changed() -> void:
	if _result_root == null or not _result_root.visible:
		return
	var pause_menu: Control = get_node_or_null("PauseMenu/Root") as Control
	var pause_open: bool = pause_menu != null and pause_menu.visible
	if pause_open:
		_result_root.remove_from_group("nav_scope")
	elif not _result_root.is_in_group("nav_scope"):
		_result_root.add_to_group("nav_scope")
	MenuNav.refresh()
	if not pause_open:
		var focus_btn: Control = _result_ui.focus_default(_result_card)
		if focus_btn != null:
			MenuNav.focus(focus_btn)


# --------------------------------------------------------------------------
# audio


func _play_one_shot(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = _spawn_audio(stream, volume_db, pitch)
	if player == null:
		return
	player.play()
	player.finished.connect(player.queue_free)


func _spawn_audio(stream: AudioStream, volume_db: float,
		pitch: float) -> AudioStreamPlayer:
	## One throwaway player for a one-shot; the caller owns its lifetime.
	if stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = volume_db
	player.pitch_scale = pitch
	add_child(player)
	return player


func _play_deposit_fanfare() -> void:
	## A short rising three-note flourish on a deposit. Notes after the first
	## are scheduled on a tween, so the whole fanfare is three one-shots and no
	## extra node has to stay alive per deposit.
	var notes: Array[AudioStreamPlayer] = []
	for index in DEPOSIT_FANFARE.size():
		var note: AudioStreamPlayer = _spawn_audio(DELIVERY_SFX, -6.0,
			float(DEPOSIT_FANFARE[index]))
		if note == null:
			continue
		notes.append(note)
	if notes.is_empty():
		return
	notes[0].play()
	notes[0].finished.connect(notes[0].queue_free)
	for index in range(1, notes.size()):
		var note: AudioStreamPlayer = notes[index]
		var delay: float = DEPOSIT_FANFARE_GAP * float(index)
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_callback(note.play)
		tween.tween_interval(1.4)
		tween.tween_callback(note.queue_free)


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
	if not Network.teams_changed.is_connected(_on_teams_changed):
		Network.teams_changed.connect(_on_teams_changed)
	Network.notify_scene_ready(self, Network.CARGO_SCENE)
	if _is_host:
		_broadcast_state()
		_broadcast_bot_states()
	elif Network.is_scene_ready(1):
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
	_release_hold_owner(peer_id)
	_cart_relay_ms.erase(peer_id)
	for index in _presents.size():
		if int(_presents[index]["carrier"]) == peer_id:
			_release_present(index)
	if peer_id == 1 and not _is_host and _multiplayer \
			and (_phase == Phase.RACING or _phase == Phase.OVERTIME):
		# Host (only match-clock authority) is gone: conclude locally from the
		# current score instead of racing a frozen clock forever.
		_finish_match()


func _spawn_remote_cart(peer_id: int) -> void:
	if _remote_carts.has(peer_id) or peer_id == multiplayer.get_unique_id():
		return
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	cart.name = "Remote_%d" % peer_id
	cart.position = Vector3(0.0, 0.35, BASE_Z[0] - 3.5)
	add_child(cart)
	cart.setup_remote(peer_id)
	cart.set_vehicle_id(Network.effective_vehicle_for(peer_id, "minigame"),
		Network.effective_racer_color_for(peer_id))
	cart.net_position = cart.global_position
	cart.net_yaw = cart.rotation.y
	var label := Label3D.new()
	label.name = "NameTag"
	label.text = Network.name_of(peer_id)
	label.font = TITLE_FONT
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
	if not _is_host and not _net_config_received and Network.is_scene_ready(1):
		_ready_retry_timer += delta
		if _ready_retry_timer >= 0.8:
			_ready_retry_timer = 0.0
			rpc_id(1, "_net_cargo_ready", _theme_id, _bot_vehicle())
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


func _broadcast_cart_state(peer_id: int, position: Vector3, yaw: float,
		sent_ms: int, velocity: Vector3) -> void:
	if _cart_idle_skip(peer_id, position, yaw, velocity):
		return
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
	if not holding:
		_client_holds.erase(sender)
		_hold_state.erase(sender)
		_release_hold_owner(sender)
		return
	_client_holds[sender] = {
		"index": present_index,
		"holding": holding,
		"ms": Time.get_ticks_msec(),
	}
	if _debug:
		print("CARGO_DEBUG client_hold peer=%d present=%d holding=%s"
			% [sender, present_index, str(holding)])


@rpc("any_peer", "reliable")
func _net_hold_cancel() -> void:
	## Reliable counterpart to the 10 Hz unreliable hold request: cancelling
	## must never be lost, or a client that drove away would keep charging.
	if not _is_host:
		return
	var sender: int = _rpc_sender()
	if sender <= 1 or sender == multiplayer.get_unique_id():
		return
	_client_holds.erase(sender)
	_hold_state.erase(sender)
	_release_hold_owner(sender)


func _release_hold_owner(key: int) -> void:
	## Drop every claimed present held by one kart (cancel, disconnect, respawn).
	for index: int in _hold_owner.keys():
		if int(_hold_owner[index]) == key:
			_hold_owner.erase(index)


@rpc("any_peer", "reliable")
func _net_cargo_ready(theme_id: String, vehicle_id: String) -> void:
	var sender: int = _rpc_sender()
	if sender <= 1 or sender == multiplayer.get_unique_id() or not _is_host:
		return
	if vehicle_id.length() > 64:
		return
	Network.mark_peer_scene_ready(sender)
	_spawn_remote_cart(sender)
	var rcart: CartPlayer = _remote_carts.get(sender) as CartPlayer
	if rcart != null and is_instance_valid(rcart):
		var clean_vid: String = Network.effective_vehicle_for(sender, "minigame") \
			if Network.is_shared_vehicle_mode() else GameSettings.sanitize_vehicle_id(vehicle_id)
		rcart.set_vehicle_id(clean_vid, Network.effective_racer_color_for(sender))
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
	_net_config_received = true
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
	var incoming: int = clampi(phase, 0, 3)
	# A late unreliable packet must never drag this peer backwards: regressing
	# OVERTIME to RACING would flash the wrong clock and lose sudden death.
	if incoming < int(_phase) and incoming != int(Phase.COUNTDOWN):
		return
	_score[0] = clampi(score_a, 0, 99)
	_score[1] = clampi(score_b, 0, 99)
	_remaining = remaining
	_overtime = overtime
	if _overtime:
		_overtime_remaining = remaining
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
			# FINISHED arrives via the reliable _net_match_end (scores + result
			# card). This unreliable snapshot must never set it first: the
			# state packet routinely wins the race, and the real match end is
			# then dropped as a duplicate, freezing the client at 0:00 with no
			# results and a still-drivable kart.
			pass


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
	_play_deposit_fanfare()
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
	# Mirror the host's whistle cleanup so carried-crate glows and hold rings
	# don't stick on top of the result card on clients.
	_hold_state.clear()
	_hold_owner.clear()
	for index in _presents.size():
		if int(_presents[index]["state"]) == PRESENT_CARRIED:
			_release_present(index)
	_set_cart_active(false)
	for entry: Dictionary in _bots:
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart):
			cart.set_ai_controls(0.0, 0.5, 0.0)
	_show_result()


func _broadcast_bot_states() -> void:
	if _bots.is_empty() or not _is_host:
		return
	var now: int = Time.get_ticks_msec()
	var all_idle: bool = true
	for entry: Dictionary in _bots:
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		var vel: Vector3 = cart.velocity if cart != null and is_instance_valid(cart) else Vector3.ZERO
		if Vector2(vel.x, vel.z).length() >= CART_IDLE_SPEED:
			all_idle = false
			break
	if all_idle and now - _bot_idle_ms < int(CART_IDLE_INTERVAL * 1000.0):
		return
	_bot_idle_ms = now
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
	var orphan_shapes: int = 0
	for node in find_children("*", "CollisionShape3D", true, false):
		var parent: Node = node.get_parent()
		if not (parent is CollisionObject3D):
			orphan_shapes += 1
	var crates: int = find_children("Crate", "Node3D", true, false).size()
	var stands: int = find_children("Grandstand_*", "Node3D", true, false).size()
	var lights: int = find_children("Floodlight_*", "Node3D", true, false).size()
	var banners: int = find_children("Banner_*", "Node3D", true, false).size()
	var blocked: int = 0
	for point: Dictionary in _present_points:
		var spot: Vector3 = point["position"] as Vector3
		if _point_clear(spot):
			continue
		blocked += 1
		print("CARGO_DEBUG blocked_point poi=%s at=(%.1f,%.1f)"
			% [str(point.get("poi", "?")), spot.x, spot.z])
	print("CARGO_DEBUG structure solids=%d missing_shapes=%d orphan_shapes=%d "
		% [solids, missing, orphan_shapes]
		+ "world_layer_ok=%s points=%d blocked_points=%d objects=%d "
		% [str(world_ok), _present_points.size(), blocked,
		int(_stats.get("objects", 0))]
		+ "draw_calls=%d hazards=%d crates=%d stands=%d lights=%d banners=%d"
		% [int(_stats.get("draw_calls", 0)), _hazards.size(), crates, stands,
		lights, banners])


# --------------------------------------------------------------------------
# navigation


func _on_play_again() -> void:
	if _multiplayer:
		if _is_host:
			# restart = true: a same-scene rematch must reload the scene; the
			# plain start would be swallowed by the begin-game retry guard.
			Network.start_game(SCENE_PATH, GameSettings.GAME_MINIGAMES, true)
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
	## Runs the real mode with one scripted bot and prints every relay step.
	## The bot uses the live hold/carry/delivery systems, not a shortcut: it
	## selects through _bot_choose, stops on the present, waits out the real
	## two second hold, carries the present and watches the score increment.
	## Run with CART_CARGO_SELFTEST=1. Exit code 0 means the loop passed.
	var started: int = Time.get_ticks_msec()
	print("CARGO_SELFTEST step=boot theme=%s presents=%d bots=%d action=%s key=%s"
		% [_theme_id, _presents.size(), _bots.size(), INTERACT_ACTION,
		_interact_key_name()])
	var wait: int = 300
	while (_phase != Phase.RACING or _presents.is_empty() or _bots.is_empty()) \
			and wait > 0:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		wait -= 1
	if _bots.is_empty() or _presents.is_empty():
		_fail_selftest("arena did not start")
		return
	_selftest_bot = _bots[0]
	_selftest_cart = _selftest_bot.get("cart") as CartPlayer
	if _selftest_cart == null or not is_instance_valid(_selftest_cart):
		_fail_selftest("selftest bot has no cart")
		return
	_bot_choose(0, _selftest_bot, _selftest_cart)
	_selftest_present = int(_selftest_bot.get("present", -1))
	if _selftest_present < 0 or _selftest_present >= _presents.size():
		_fail_selftest("bot could not select a present")
		return
	var present: Dictionary = _presents[_selftest_present]
	if int(present["state"]) != PRESENT_AVAILABLE:
		_fail_selftest("selected present is not available")
		return
	var target: Vector3 = present["position"] as Vector3
	print("CARGO_SELFTEST step=select present=%d poi=%s target=(%.1f,%.1f)"
		% [_selftest_present, str(_present_points[int(present["point"])]["poi"]),
		target.x, target.z])
	_face_target(_selftest_cart, target)
	print("CARGO_SELFTEST step=drive target=(%.1f,%.1f) gap=%.1f"
		% [target.x, target.z,
		_planar_distance(_selftest_cart.global_position, target)])
	var reached: bool = await _selftest_drive_to(target, SELFTEST_APPROACH,
		SELFTEST_DRIVE_TIMEOUT)
	if not reached:
		_fail_selftest("bot did not reach the present")
		return
	print("CARGO_SELFTEST step=arrive gap=%.1f speed=%.1f"
		% [_planar_distance(_selftest_cart.global_position, target),
		Vector2(_selftest_cart.velocity.x, _selftest_cart.velocity.z).length()])
	_bot_stop(_selftest_cart)
	_selftest_bot["state"] = BOT_HOLD
	_selftest_bot["present"] = _selftest_present
	_selftest_bot["hold_time"] = 0.0
	print("CARGO_SELFTEST step=hold present=%d seconds=%.2f"
		% [_selftest_present, HOLD_SECONDS])
	var held: bool = await _selftest_wait_for_pickup()
	if not held:
		_fail_selftest("hold did not load the present")
		return
	print("CARGO_SELFTEST step=pickup collected=%d present_state=%d"
		% [_selftest_collected, int(_presents[_selftest_present]["state"])])
	_selftest_bot["state"] = BOT_CARRY
	_selftest_bot["carry_time"] = 0.0
	var team: int = int(_selftest_bot.get("team", 1))
	var score_before: int = _score[team]
	var base: Vector3 = _pads[team]
	print("CARGO_SELFTEST step=carry team=%d base=(%.1f,%.1f) score=%d-%d"
		% [team, base.x, base.z, _score[0], _score[1]])
	var delivered: bool = await _selftest_drive_until_score(base, score_before)
	if not delivered:
		_fail_selftest("carried present never reached the base pad")
		return
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	print("CARGO_SELFTEST step=deliver score=%d-%d deliveries=%d cycle=%s"
		% [_score[0], _score[1], _selftest_deliveries,
		str(_selftest_cycle)])
	print("CARGO_SELFTEST step=stats theme=%s objects=%d draw_calls=%d hazards=%d"
		% [_theme_id, int(_stats.get("objects", 0)),
		int(_stats.get("draw_calls", 0)), _hazards.size()])
	var hud_clipped: bool = _hud_clips()
	print("CARGO_SELFTEST step=hud clips=%s" % str(hud_clipped))
	if hud_clipped:
		_fail_selftest("hud clipped viewport or minimum size")
		return
	print("CARGO_SELFTEST step=pass collected=%d deliveries=%d sim=%.1fs"
		% [_selftest_collected, _selftest_deliveries, seconds])
	get_tree().quit()


func _fail_selftest(reason: String) -> void:
	print("CARGO_SELFTEST step=fail reason=%s" % reason)
	print("CARGO_SELFTEST step=result FAIL collected=%d deliveries=%d score=%d-%d"
		% [_selftest_collected, _selftest_deliveries, _score[0], _score[1]])
	get_tree().quit(1)


func _face_target(cart: CartPlayer, target: Vector3) -> void:
	if cart == null or not is_instance_valid(cart):
		return
	var offset: Vector3 = target - cart.global_position
	offset.y = 0.0
	if offset.length_squared() <= 0.01:
		return
	cart.rotation.y = atan2(-offset.x, -offset.z)


func _selftest_steer(target: Vector3) -> void:
	## Direct short-range steering for the proof bot. The arena is open, so a
	## simple heading controller is enough; it slows before the target so the
	## two second hold starts inside the pickup radius.
	var cart: CartPlayer = _selftest_cart
	if cart == null or not is_instance_valid(cart):
		return
	var local: Vector3 = cart.to_local(Vector3(target.x, cart.global_position.y,
		target.z))
	var distance: float = Vector2(local.x, local.z).length()
	var steer: float = clampf(atan2(-local.x, -local.z) * 2.2, -1.0, 1.0)
	var speed: float = Vector2(cart.velocity.x, cart.velocity.z).length()
	var desired: float = clampf(distance * 1.1, 2.5, 13.0)
	var throttle: float = 1.0 if speed < desired else 0.0
	var brake: float = 0.0
	if speed > desired + 0.5:
		brake = clampf((speed - desired) / 4.0, 0.0, 1.0)
	if distance < 4.0:
		# Creep the last metres instead of braking to a stop outside the pickup
		# radius. Below 2.4 m, coasting friction parks the kart.
		throttle = 0.35 if distance > 2.4 else 0.0
		brake = 0.4 if speed > 2.5 else 0.0
	cart.set_ai_controls(throttle, brake, steer, false)


func _selftest_drive_to(target: Vector3, arrive: float,
		timeout: float) -> bool:
	var frames: int = maxi(int(timeout * 60.0), 1)
	for _frame in frames:
		await get_tree().physics_frame
		if not is_inside_tree() or not is_instance_valid(_selftest_cart):
			return false
		if _planar_distance(_selftest_cart.global_position, target) <= arrive:
			_bot_stop(_selftest_cart)
			return true
		_selftest_steer(target)
	return false


func _selftest_wait_for_pickup() -> bool:
	var frames: int = maxi(int(SELFTEST_HOLD_TIMEOUT * 60.0), 1)
	var last_half: int = -1
	for _frame in frames:
		await get_tree().physics_frame
		if not is_inside_tree() or not is_instance_valid(_selftest_cart):
			return false
		var present: Dictionary = _presents[_selftest_present]
		var state: int = int(present["state"])
		if state == PRESENT_CARRIED \
				and int(present["carrier"]) == _bot_key(0):
			return true
		if state != PRESENT_AVAILABLE:
			return false
		var hold: float = float(present["hold"])
		var step_bucket: int = int(hold * 10.0)
		if step_bucket > last_half:
			last_half = step_bucket
			print("CARGO_SELFTEST step=hold progress=%.2f/%.2f"
				% [hold, HOLD_SECONDS])
		var spot: Vector3 = present["position"] as Vector3
		if _planar_distance(_selftest_cart.global_position, spot) \
				> PICK_RADIUS - 0.4:
			_selftest_steer(spot)
		else:
			_bot_stop(_selftest_cart)
	return false


func _selftest_drive_until_score(base: Vector3, score_before: int) -> bool:
	var team: int = int(_selftest_bot.get("team", 1))
	var frames: int = maxi(int(SELFTEST_DRIVE_TIMEOUT * 60.0), 1)
	for _frame in frames:
		await get_tree().physics_frame
		if not is_inside_tree() or not is_instance_valid(_selftest_cart):
			return false
		if _score[team] > score_before:
			_bot_stop(_selftest_cart)
			return true
		var present: Dictionary = _presents[_selftest_present]
		if int(present["state"]) != PRESENT_CARRIED:
			return _score[team] > score_before
		_selftest_steer(base)
	return false


# --------------------------------------------------------------------------
# helpers


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
