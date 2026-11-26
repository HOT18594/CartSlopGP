## KNOCKOUT: a 2–8 player (+ bots) Smash-style Bumper Royale minigame.
##
## Every kart starts each round at 0% damage on an elevated 3D arena above an
## abyss, molten magma sea, or arctic ocean basin. Collisions deal +12%..+28%
## damage (based on closing speed and attacker mass) and apply horizontal +
## upward knockback scaled by `1.0 + damage_pct / 75.0`. Firing POWER SLAM
## (`E` / `F` / Right Mouse / Gamepad `B`, 4.0s cooldown) surges the kart
## forward (+11.0 m/s) inside a golden-orange energy shield for 0.45s, dealing
## +26% damage and 1.85x mega-knockback to any rival within 3.2 m.
##
## Matches run 3 rounds of 55.0s each. At t = 18.0s (Wave 1) and t = 34.0s
## (Wave 2), outer collapsible sectors flash warning strobes for 4.0s before
## dropping into the abyss. Ring-outs credit +2 PTS to `last_attacker_id`
## (6.0s window), and the last survivor earns +3 PTS (+2 PTS each on time-out).
##
## Supports Solo (player + >= 3 smart bots) and full host-authoritative Online
## Multiplayer (`Network.is_session_active()`), plus `CART_KNOCKOUT_SELFTEST=1`.
extends Node3D

const CART_SCENE := preload("res://scenes/player/cart_player.tscn")
const KnockoutMaps := preload("res://scripts/minigames/knockout_maps.gd")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const VisualGrade := preload("res://scripts/systems/visual_grade.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const SCENE_PATH: String = "res://scenes/minigames/knockout.tscn"
const MINIGAMES_MENU: String = "res://scenes/ui/minigames_menu.tscn"
const MAIN_MENU: String = "res://scenes/ui/main_menu.tscn"
const UI_THEME: Theme = preload("res://assets/ui/theme.tres")
const CANDY_BUTTON := preload("res://scripts/ui/candy_button.gd")
const TITLE_FONT: Font = preload("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")
const BODY_FONT: Font = preload("res://assets/ui/fonts/Fredoka-Bold.ttf")

const COUNTDOWN_BEEP: AudioStream = preload("res://assets/audio/sfx/race/countdown_beep.wav")
const COUNTDOWN_GO: AudioStream = preload("res://assets/audio/sfx/race/countdown_go.wav")
const ROUND_CHIME: AudioStream = preload("res://assets/audio/sfx/race/lap_chime.wav")
const FINISH_FANFARE: AudioStream = preload("res://assets/audio/sfx/race/finish_fanfare.wav")
const SLAM_IGNITE_SFX: AudioStream = preload("res://assets/audio/sfx/boost/boost_ignite.wav")
const SLAM_WHOOSH_SFX: AudioStream = preload("res://assets/audio/sfx/boost/boost_whoosh.wav")
const SLAM_HIT_SFX: AudioStream = preload("res://assets/audio/sfx/impacts/impact_heavy.ogg")
const KO_CRASH_SFX: AudioStream = preload("res://assets/audio/sfx/impacts/metal_crash_0.ogg")
const WARNING_SFX: AudioStream = preload("res://assets/audio/sfx/fun/drift_chime.wav")

const SLAM_ACTION: StringName = &"power_slam"

## Match & round pacing constants.
const DEFAULT_ROUNDS: int = 3
const ROUND_SECONDS: float = 55.0
const COUNTDOWN_SECONDS: float = 3.0
const INTERMISSION_SECONDS: float = 3.5

## Collapsing danger zone schedule within each 55.0s round.
const WAVE1_WARN_TIME: float = 18.0
const WAVE_WARN_DURATION: float = 4.0
const WAVE1_DROP_TIME: float = WAVE1_WARN_TIME + WAVE_WARN_DURATION
const WAVE2_WARN_TIME: float = 34.0
const WAVE2_DROP_TIME: float = WAVE2_WARN_TIME + WAVE_WARN_DURATION

## Smash-style knockback & Power-Slam tuning constants.
const DAMAGE_MAX: float = 250.0
const DAMAGE_HIT_MIN: float = 12.0
const DAMAGE_HIT_MAX: float = 28.0
const KNOCKBACK_PCT_DIVISOR: float = 75.0
const KO_CREDIT_WINDOW: float = 6.0
const PAIR_HIT_COOLDOWN: float = 0.28
const MIN_HIT_CLOSING_SPEED: float = 2.0

const SLAM_COOLDOWN: float = 4.0
const SLAM_DURATION: float = 0.45
const SLAM_SURGE_SPEED: float = 11.0
const SLAM_HIT_RADIUS: float = 3.2
const SLAM_DAMAGE_BONUS: float = 26.0
const SLAM_KNOCKBACK_MULT: float = 1.85

## Scoring rules.
const POINTS_PER_KO: int = 2
const POINTS_ROUND_WIN: int = 3
const POINTS_SURVIVOR_TIMEOUT: int = 2

## Contestant limits.
const MAX_CONTESTANTS: int = 8
const SOLO_MIN_BOTS: int = 3
const BOT_PEER_BASE: int = 1000

const BOT_NAMES: PackedStringArray = [
	"BRUISER", "CRUSHER", "VORTEX", "BLITZ",
	"TITAN", "SPARKY", "RAMPAGE",
]
const BOT_COLORS: Array[Color] = [
	Color("f2545b"), Color("4fbf52"), Color("45b6f0"),
	Color("ff9f43"), Color("f26ca7"), Color("38d6f0"), Color("b87ff5"),
]

## Multiplayer sync cadence.
const CART_SYNC_INTERVAL: float = 0.05 ## 20 Hz pose/velocity stream.
const CART_IDLE_SPEED: float = 1.0
const CART_IDLE_INTERVAL: float = 0.20
const DAMAGE_SYNC_INTERVAL: float = 0.10 ## 10 Hz damage/alive table sync.
const CLOCK_SYNC_INTERVAL: float = 0.25 ## 4 Hz round clock keepalive.

## HUD layout constants (designed to fit 960x540 and 1280x720 with zero clipping).
const TOP_BAR_TOP: float = 10.0
const TOP_BAR_WIDTH: float = 392.0
const TOP_BAR_HEIGHT: float = 54.0
const LEADERBOARD_LEFT: float = 16.0
const LEADERBOARD_TOP: float = 10.0
const LEADERBOARD_WIDTH: float = 212.0
const TOAST_WIDTH: float = 392.0
const TOAST_HEIGHT: float = 40.0
const SLAM_BAR_INNER_WIDTH: float = 108.0
const KO_SHADOW_COLOR := Color(0.07, 0.05, 0.15, 0.88)
const KO_TEXT_SHADOW := Color(0.08, 0.06, 0.16, 0.85)

enum Phase { COUNTDOWN, BRAWL, INTERMISSION, FINISHED }


class _KoSlashPlate extends Control:
	var skew_px: float = 12.0
	var fill_color: Color = Color("1e1b3a")
	var border_color: Color = Color("1e1b3a")
	var border_width: float = 3.5
	var shadow_offset := Vector2(4.0, 5.0)
	var accent_color := Color(0.0, 0.0, 0.0, 0.0)
	var accent_width: float = 0.0
	var draw_sheen: bool = true

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var pad_l: float = 2.0
		var pad_t: float = 2.0
		var pad_r: float = maxf(shadow_offset.x + 2.0, 3.0)
		var pad_b: float = maxf(shadow_offset.y + 2.0, 3.0)
		var sk: float = minf(skew_px, maxf(size.x * 0.22, 4.0))
		var w: float = size.x - pad_l - pad_r - sk
		var h: float = size.y - pad_t - pad_b
		if w <= 4.0 or h <= 4.0:
			return
		var pts := PackedVector2Array([
			Vector2(pad_l + sk, pad_t),
			Vector2(pad_l + sk + w, pad_t),
			Vector2(pad_l + w, pad_t + h),
			Vector2(pad_l, pad_t + h),
		])
		var sh := PackedVector2Array([
			pts[0] + shadow_offset,
			pts[1] + shadow_offset,
			pts[2] + shadow_offset,
			pts[3] + shadow_offset,
		])
		draw_colored_polygon(sh, KO_SHADOW_COLOR)
		draw_colored_polygon(pts, fill_color)

		if accent_width > 0.5 and accent_color.a > 0.01:
			var aw: float = minf(accent_width, w * 0.45)
			var wedge := PackedVector2Array([
				Vector2(pad_l + sk, pad_t),
				Vector2(pad_l + sk + aw, pad_t),
				Vector2(pad_l + aw, pad_t + h),
				Vector2(pad_l, pad_t + h),
			])
			draw_colored_polygon(wedge, accent_color)
			draw_line(
				Vector2(pad_l + sk + aw, pad_t),
				Vector2(pad_l + aw, pad_t + h),
				UiPalette.INK, 2.5, true)

		if draw_sheen and h >= 12.0:
			var sh_h: float = maxf(h * 0.26, 2.5)
			var sheen := PackedVector2Array([
				Vector2(pad_l + sk + 1.5, pad_t + 1.5),
				Vector2(pad_l + sk + w - 1.5, pad_t + 1.5),
				Vector2(pad_l + sk * 0.72 + w - 1.5, pad_t + 1.5 + sh_h),
				Vector2(pad_l + sk * 0.72 + 1.5, pad_t + 1.5 + sh_h),
			])
			draw_colored_polygon(sheen, Color(1.0, 1.0, 1.0, 0.20))

		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, border_color, border_width, true)


class _KoSlamSlashBar extends Control:
	var ratio: float = 1.0
	var ready_col: Color = Color("ffd22e")
	var charge_col: Color = Color("38d6f0")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var sk: float = 7.0
		var w: float = size.x - sk - 5.0
		var h: float = size.y - 5.0
		if w <= 6.0 or h <= 3.0:
			return
		var pts := PackedVector2Array([
			Vector2(1.5 + sk, 1.5),
			Vector2(1.5 + sk + w, 1.5),
			Vector2(1.5 + w, 1.5 + h),
			Vector2(1.5, 1.5 + h),
		])
		var sh := PackedVector2Array([
			pts[0] + Vector2(2.5, 3.0),
			pts[1] + Vector2(2.5, 3.0),
			pts[2] + Vector2(2.5, 3.0),
			pts[3] + Vector2(2.5, 3.0),
		])
		draw_colored_polygon(sh, KO_SHADOW_COLOR)
		draw_colored_polygon(pts, Color(0.118, 0.106, 0.227, 0.92))
		var r: float = clampf(ratio, 0.0, 1.0)
		if r > 0.01:
			var fw: float = w * r
			var fill_pts := PackedVector2Array([
				Vector2(1.5 + sk, 1.5),
				Vector2(1.5 + sk + fw, 1.5),
				Vector2(1.5 + fw, 1.5 + h),
				Vector2(1.5, 1.5 + h),
			])
			draw_colored_polygon(fill_pts, ready_col if r >= 0.999 else charge_col)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, UiPalette.INK, 2.5, true)


class _SmashFighterPlate extends Control:
	var accent_color: Color = Color("ffd22e")
	var is_local: bool = false
	var alive: bool = true

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
		var w: float = size.x - pad_l - pad_r - sk
		var h: float = size.y - pad_t - pad_b
		if w <= 12.0 or h <= 12.0:
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
		draw_colored_polygon(sh, KO_SHADOW_COLOR)

		var body_col := Color(0.118, 0.106, 0.227, 0.96)
		if is_local and alive:
			body_col = Color("241f46")
		elif not alive:
			body_col = Color(0.09, 0.08, 0.16, 0.88)
		draw_colored_polygon(pts, body_col)

		# Vibrant Smash-style left colour wedge + bottom colour stripe!
		var wedge_col: Color = accent_color if alive else Color(0.42, 0.40, 0.50, 0.75)
		var ww: float = minf(16.0, w * 0.22)
		var wedge := PackedVector2Array([
			Vector2(pad_l + sk, pad_t),
			Vector2(pad_l + sk + ww, pad_t),
			Vector2(pad_l + ww, pad_t + h),
			Vector2(pad_l, pad_t + h),
		])
		draw_colored_polygon(wedge, wedge_col)

		var stripe_h: float = 5.0
		var b_stripe := PackedVector2Array([
			Vector2(pad_l + sk * (stripe_h / h), pad_t + h - stripe_h),
			Vector2(pad_l + w + sk * (stripe_h / h), pad_t + h - stripe_h),
			Vector2(pad_l + w, pad_t + h),
			Vector2(pad_l, pad_t + h),
		])
		draw_colored_polygon(b_stripe, UiPalette.YELLOW if (is_local and alive) else wedge_col)

		draw_line(
			Vector2(pad_l + sk + ww, pad_t),
			Vector2(pad_l + ww, pad_t + h),
			UiPalette.INK, 3.0, true)

		# Top comic specular sheen.
		if alive:
			var sheen_h: float = maxf(h * 0.22, 3.0)
			var sheen := PackedVector2Array([
				Vector2(pad_l + sk + ww + 2.0, pad_t + 2.0),
				Vector2(pad_l + sk + w - 2.0, pad_t + 2.0),
				Vector2(pad_l + sk * 0.78 + w - 2.0, pad_t + 2.0 + sheen_h),
				Vector2(pad_l + sk * 0.78 + ww + 2.0, pad_t + 2.0 + sheen_h),
			])
			draw_colored_polygon(sheen, Color(1.0, 1.0, 1.0, 0.14))
		else:
			draw_line(
				Vector2(pad_l + sk + ww + 6.0, pad_t + 6.0),
				Vector2(pad_l + w - 6.0, pad_t + h - 6.0),
				Color(0.95, 0.33, 0.36, 0.55), 3.0, true)

		var closed := pts.duplicate()
		closed.append(pts[0])
		if is_local and alive:
			draw_polyline(closed, UiPalette.YELLOW, 5.5, true)
		draw_polyline(closed, UiPalette.INK, 4.0, true)

var _saved_vehicle: String = ""
var _selftest: bool = false
var _multiplayer: bool = false
var _is_host: bool = true

var _arena_id: String = KnockoutMaps.DEFAULT_ID
var _arena_holder: Node3D
var _arena_data: Dictionary = {}
var _ko_y: float = -2.8
var _wave1_nodes: Array[Node3D] = []
var _wave2_nodes: Array[Node3D] = []
var _wave1_warning: bool = false
var _wave1_dropped: bool = false
var _wave2_warning: bool = false
var _wave2_dropped: bool = false
var _falling_sectors: Array[Dictionary] = []

var _cart: CartPlayer
var _hud: Node
var _spectator_cam: Camera3D
var _spectator_active: bool = false
var _spectator_angle: float = 0.0
var _spectator_focus: Vector3 = Vector3.ZERO

## Contestants keyed by int: human peer_id (> 0, 1 in solo) or bot key (-1 - idx).
var _contestants: Dictionary = {}
var _bot_keys: Array[int] = []
var _remote_carts: Dictionary = {} ## peer_id -> CartPlayer
var _peer_vehicles: Dictionary = {} ## peer_id -> vehicle_id
var _pre_step_vel: Dictionary = {} ## key -> Vector3 velocity before move_and_slide
var _pair_cooldowns: Dictionary = {} ## String pair key -> expire _time
var _cart_relay_ms: Dictionary = {}
var _cart_idle_ms: Dictionary = {}
var _cart_idle_pos: Dictionary = {}
var _cart_idle_yaw: Dictionary = {}
var _bot_idle_ms: int = -100000

var _total_rounds: int = DEFAULT_ROUNDS
var _round_duration: float = ROUND_SECONDS
var _round_index: int = 1
var _phase: Phase = Phase.COUNTDOWN
var _countdown: float = COUNTDOWN_SECONDS
var _last_count_int: int = 3
var _round_elapsed: float = 0.0
var _round_remaining: float = ROUND_SECONDS
var _intermission_timer: float = 0.0
var _time: float = 0.0
var _visual_time: float = 0.0
var _local_slam_queued: bool = false

var _cart_sync_timer: float = 0.0
var _bot_sync_timer: float = 0.0
var _damage_sync_timer: float = 0.0
var _clock_sync_timer: float = 0.0
var _ready_retry_timer: float = 0.0
var _net_config_received: bool = false

## Knockout Slop-Slash HUD nodes.
var _canvas: CanvasLayer
var _hud_root: Control
var _top_bar: PanelContainer
var _top_bar_plate: _KoSlashPlate
var _round_label: Label
var _alive_hud_label: Label
var _clock_hud_label: Label
var _clock_hud_plate: _KoSlashPlate
var _arena_label: Label
var _damage_badge: PanelContainer
var _damage_style: StyleBoxFlat
var _damage_caption: Label
var _damage_value_label: Label
var _slam_status_label: Label
var _slam_slash_bar: _KoSlamSlashBar
var _slam_bar_fill: ColorRect
var _slam_bar_bg: PanelContainer
var _leaderboard_panel: PanelContainer
var _leaderboard_rows: VBoxContainer
var _leaderboard_cache: Array[Dictionary] = []
var _fighter_bar: HBoxContainer
var _fighter_cards_cache: Array[Dictionary] = []
var _local_fighter_card: Control
var _toast_panel: PanelContainer
var _toast_plate: _KoSlashPlate
var _toast_style: StyleBoxFlat
var _toast_label: Label
var _toast_timer: float = 0.0
var _spectator_pill: PanelContainer
var _spectator_plate: _KoSlashPlate
var _spectator_label: Label
var _countdown_label: Label
var _intermission_panel: PanelContainer
var _intermission_plate: _KoSlashPlate
var _intermission_title: Label
var _intermission_sub: Label

## Match Result Card nodes.
var _result_root: Control
var _result_panel: PanelContainer
var _result_title: Label
var _result_subtitle: Label
var _result_rows: VBoxContainer
var _result_play_again: Button
var _result_back: Button
var _action_dock: Control


func _enter_tree() -> void:
	_saved_vehicle = GameSettings.selected_vehicle
	GameSettings.selected_vehicle = GameSettings.minigame_vehicle


func _exit_tree() -> void:
	GameSettings.selected_vehicle = _saved_vehicle
	Engine.time_scale = 1.0


func _ready() -> void:
	_selftest = OS.get_environment("CART_KNOCKOUT_SELFTEST") == "1"
	_ensure_slam_action()
	_multiplayer = Network.is_session_active()
	_is_host = Network.is_host if _multiplayer else true
	_apply_env_overrides()
	CursorController.set_menu_mode(false)

	_cart = get_node_or_null("CartPlayer") as CartPlayer
	if _cart == null:
		_cart = get_tree().get_first_node_in_group("player") as CartPlayer
	_setup_spectator_camera()
	_upgrade_graphics()
	_bind_hud()

	_arena_id = KnockoutMaps.resolve(_requested_arena_id())
	_load_arena(_arena_id)
	_setup_local_contestant()
	_setup_bots()
	_build_hud()
	_build_result_card()

	if _multiplayer:
		_setup_multiplayer()

	_start_round(1)
	if _selftest:
		_run_self_test.call_deferred()


# ==========================================================================
# Initialization & Input Setup
# ==========================================================================

func _requested_arena_id() -> String:
	var env_id: String = OS.get_environment("CART_KNOCKOUT_ARENA").strip_edges()
	if env_id != "":
		return env_id
	if _multiplayer and Network.session_minigame.strip_edges() != "":
		return Network.session_minigame
	var picked: String = GameSettings.selected_minigame.strip_edges()
	if picked != "":
		return picked
	return KnockoutMaps.DEFAULT_ID


func _apply_env_overrides() -> void:
	var r_env: String = OS.get_environment("CART_KNOCKOUT_ROUNDS").strip_edges()
	if r_env.is_valid_int():
		_total_rounds = clampi(r_env.to_int(), 1, 9)
	var s_env: String = OS.get_environment("CART_KNOCKOUT_SECONDS").strip_edges()
	if s_env.is_valid_int():
		_round_duration = clampf(float(s_env.to_int()), 10.0, 300.0)


func _ensure_slam_action() -> void:
	if not InputMap.has_action(SLAM_ACTION):
		InputMap.add_action(SLAM_ACTION)
	_add_key_binding(SLAM_ACTION, KEY_E)
	_add_key_binding(SLAM_ACTION, KEY_F)
	_add_mouse_binding(SLAM_ACTION, MOUSE_BUTTON_RIGHT)
	_add_joy_binding(SLAM_ACTION, JOY_BUTTON_B)
	_add_joy_binding(SLAM_ACTION, JOY_BUTTON_LEFT_SHOULDER)


func _add_key_binding(action: StringName, keycode: Key) -> void:
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == keycode:
			return
	var added := InputEventKey.new()
	added.physical_keycode = keycode
	added.device = -1
	InputMap.action_add_event(action, added)


func _add_mouse_binding(action: StringName, button_index: MouseButton) -> void:
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == button_index:
			return
	var added := InputEventMouseButton.new()
	added.button_index = button_index
	added.device = -1
	InputMap.action_add_event(action, added)


func _add_joy_binding(action: StringName, button_index: JoyButton) -> void:
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button_index:
			return
	var added := InputEventJoypadButton.new()
	added.button_index = button_index
	added.device = -1
	InputMap.action_add_event(action, added)


func _input(event: InputEvent) -> void:
	# Intercept Gamepad B during live combat so it fires Power-Slam instead of
	# bubbling to PauseMenu._unhandled_input via ui_cancel.
	if _phase != Phase.BRAWL or SceneLoader.is_busy() or _is_pause_open():
		return
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed and jb.button_index == JOY_BUTTON_B:
			_local_slam_queued = true
			UiKit.consume_input(self)


func _is_pause_open() -> bool:
	var pause_root: Control = get_node_or_null("PauseMenu/Root") as Control
	return pause_root != null and pause_root.visible


func _upgrade_graphics() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.msaa_3d = Viewport.MSAA_2X
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	VisualGrade.apply(get_node_or_null("WorldEnvironment") as WorldEnvironment, "race")
	VisualGrade.apply_sun(get_node_or_null("Sun") as DirectionalLight3D)


func _setup_spectator_camera() -> void:
	_spectator_cam = Camera3D.new()
	_spectator_cam.name = "SpectatorCamera"
	_spectator_cam.fov = 66.0
	_spectator_cam.current = false
	add_child(_spectator_cam)


func _bind_hud() -> void:
	_hud = get_node_or_null("HUD")
	if _hud == null:
		return
	if _cart != null and _hud.has_method("bind_cart"):
		_hud.call("bind_cart", _cart)
	for hide_name: String in [
		"RacePlaque", "LiveStandings", "WrongWayBanner", "StatePill", "HintLabel",
	]:
		var item: CanvasItem = _hud.find_child(hide_name, true, false) as CanvasItem
		if item != null:
			item.visible = false
			item.modulate.a = 0.0
	var net_block: Control = _hud.find_child("NetBlock", true, false) as Control
	if net_block != null:
		net_block.offset_left = -256.0
		net_block.offset_right = -16.0


# ==========================================================================
# Arena Loading & Collapsing Sector Management
# ==========================================================================

func _load_arena(target_id: String) -> void:
	_arena_id = KnockoutMaps.resolve(target_id)
	_falling_sectors.clear()
	_wave1_nodes.clear()
	_wave2_nodes.clear()
	if _arena_holder != null and is_instance_valid(_arena_holder):
		remove_child(_arena_holder)
		_arena_holder.free()
	_arena_holder = Node3D.new()
	_arena_holder.name = "ArenaStage"
	add_child(_arena_holder)

	_arena_data = KnockoutMaps.build_arena(_arena_holder, _arena_id)
	_ko_y = float(_arena_data.get("ko_y", -2.8))
	var w1_raw: Variant = _arena_data.get("wave1_nodes", [])
	if w1_raw is Array:
		for n: Variant in w1_raw as Array:
			if n is Node3D:
				_wave1_nodes.append(n as Node3D)
	var w2_raw: Variant = _arena_data.get("wave2_nodes", [])
	if w2_raw is Array:
		for n: Variant in w2_raw as Array:
			if n is Node3D:
				_wave2_nodes.append(n as Node3D)

	KnockoutMaps.apply_environment(
		get_node_or_null("WorldEnvironment") as WorldEnvironment,
		get_node_or_null("Sun") as DirectionalLight3D,
		_arena_id)
	_reset_waves()
	if _arena_label != null:
		_arena_label.text = str(_arena_data.get("name", "SKYTOP HELIPAD"))


func _reset_waves() -> void:
	_wave1_warning = false
	_wave1_dropped = false
	_wave2_warning = false
	_wave2_dropped = false
	_falling_sectors.clear()
	for group: Array[Node3D] in [_wave1_nodes, _wave2_nodes]:
		for sector: Node3D in group:
			if sector == null or not is_instance_valid(sector):
				continue
			sector.visible = true
			if sector.has_meta("rest_transform"):
				sector.transform = sector.get_meta("rest_transform") as Transform3D
			var warn_mesh: MeshInstance3D = sector.get_meta("warn_mesh", null) as MeshInstance3D
			if warn_mesh != null:
				warn_mesh.visible = false
			_set_sector_colliders_disabled(sector, false)


func _set_wave_warning(wave_num: int, active: bool) -> void:
	if wave_num == 1:
		if _wave1_dropped:
			return
		_wave1_warning = active
	else:
		if _wave2_dropped:
			return
		_wave2_warning = active
	var nodes: Array[Node3D] = _wave1_nodes if wave_num == 1 else _wave2_nodes
	for sector: Node3D in nodes:
		if sector == null or not is_instance_valid(sector):
			continue
		var warn_mesh: MeshInstance3D = sector.get_meta("warn_mesh", null) as MeshInstance3D
		if warn_mesh != null:
			warn_mesh.visible = active


func _collapse_wave(wave_num: int) -> void:
	var nodes: Array[Node3D] = _wave1_nodes if wave_num == 1 else _wave2_nodes
	if wave_num == 1:
		if _wave1_dropped:
			return
		_wave1_warning = false
		_wave1_dropped = true
	else:
		if _wave2_dropped:
			return
		_wave2_warning = false
		_wave2_dropped = true

	_play_one_shot(KO_CRASH_SFX, -7.0, 0.78)
	for sector: Node3D in nodes:
		if sector == null or not is_instance_valid(sector):
			continue
		var warn_mesh: MeshInstance3D = sector.get_meta("warn_mesh", null) as MeshInstance3D
		if warn_mesh != null:
			warn_mesh.visible = false
		_set_sector_colliders_disabled(sector, true)
		var out_dir: Vector3 = sector.position
		out_dir.y = 0.0
		var tilt_axis: Vector3 = out_dir.normalized().cross(Vector3.UP) \
			if out_dir.length_squared() > 0.01 else Vector3.RIGHT
		_falling_sectors.append({
			"node": sector,
			"vel_y": -2.5,
			"axis": tilt_axis.normalized(),
			"ang_vel": 0.48,
			"age": 0.0,
		})


func _set_sector_colliders_disabled(sector: Node3D, disabled: bool) -> void:
	var raw_shapes: Variant = sector.get_meta("shapes", [])
	if raw_shapes is Array:
		for item: Variant in raw_shapes as Array:
			if item is CollisionShape3D and is_instance_valid(item):
				(item as CollisionShape3D).disabled = disabled
	for child: Node in sector.find_children("*", "CollisionShape3D", true, false):
		(child as CollisionShape3D).disabled = disabled


func _tick_wave_schedule() -> void:
	if not _wave1_warning and not _wave1_dropped and _round_elapsed >= WAVE1_WARN_TIME:
		_set_wave_warning(1, true)
		_show_toast("⚠ OUTER RING DROPPING!", 3.6, Color("ff9e2c"))
		_play_one_shot(WARNING_SFX, -4.0, 0.92)
		if _multiplayer and _is_host:
			_broadcast_wave_event(1, false)
	if not _wave1_dropped and _round_elapsed >= WAVE1_DROP_TIME:
		_collapse_wave(1)
		_show_toast("OUTER RING COLLAPSED!", 1.8, UiPalette.RED)
		if _multiplayer and _is_host:
			_broadcast_wave_event(1, true)
	if not _wave2_warning and not _wave2_dropped and _round_elapsed >= WAVE2_WARN_TIME:
		_set_wave_warning(2, true)
		_show_toast("⚠ FINAL RING SHRINKING!", 3.6, UiPalette.RED)
		_play_one_shot(WARNING_SFX, -3.5, 1.12)
		if _multiplayer and _is_host:
			_broadcast_wave_event(2, false)
	if not _wave2_dropped and _round_elapsed >= WAVE2_DROP_TIME:
		_collapse_wave(2)
		_show_toast("FINAL CORE SHOWDOWN!", 2.2, UiPalette.YELLOW)
		if _multiplayer and _is_host:
			_broadcast_wave_event(2, true)


func _tick_wave_visuals(delta: float) -> void:
	# Pulse active warning strobes between bright amber and crimson red.
	for wave_idx: int in [1, 2]:
		var active: bool = _wave1_warning if wave_idx == 1 else _wave2_warning
		if not active:
			continue
		var rate: float = 9.5 if wave_idx == 1 else 13.0
		var pulse: float = 0.5 + 0.5 * sin(_visual_time * rate)
		var col: Color = Color(1.0, 0.65, 0.12, 0.28).lerp(
			Color(1.0, 0.16, 0.14, 0.68), pulse)
		var nodes: Array[Node3D] = _wave1_nodes if wave_idx == 1 else _wave2_nodes
		for sector: Node3D in nodes:
			if sector == null or not is_instance_valid(sector):
				continue
			var mat: StandardMaterial3D = sector.get_meta("warn_mat", null) as StandardMaterial3D
			if mat != null:
				mat.albedo_color = col

	# Animate dropped sectors plunging downward into the abyss.
	var i: int = _falling_sectors.size() - 1
	while i >= 0:
		var item: Dictionary = _falling_sectors[i]
		var sector: Node3D = item.get("node") as Node3D
		if sector == null or not is_instance_valid(sector):
			_falling_sectors.remove_at(i)
			i -= 1
			continue
		var age: float = float(item.get("age", 0.0)) + delta
		var vel_y: float = float(item.get("vel_y", -2.5)) - 26.0 * delta
		var axis: Vector3 = item.get("axis", Vector3.RIGHT) as Vector3
		var ang_vel: float = float(item.get("ang_vel", 0.45))
		sector.position.y += vel_y * delta
		if axis.length_squared() > 0.01:
			sector.rotate(axis, ang_vel * delta)
		item["age"] = age
		item["vel_y"] = vel_y
		if age >= 1.35:
			sector.visible = false
			_falling_sectors.remove_at(i)
		i -= 1


# ==========================================================================
# Contestants, Karts, Shield Visuals & Floating 3D Damage Badges
# ==========================================================================

func _local_key() -> int:
	if _multiplayer and multiplayer.multiplayer_peer != null:
		return multiplayer.get_unique_id()
	return 1


func _chosen_vehicle_id() -> String:
	var id: String = Network.effective_vehicle_for(_local_key(), "minigame") \
		if Network.is_session_active() else GameSettings.minigame_vehicle
	id = VehicleCatalog.normalize_id(id)
	if VehicleCatalog.find(id).is_empty():
		return VehicleCatalog.DEFAULT_ID
	return id


func _desired_bot_count() -> int:
	if _selftest:
		return SOLO_MIN_BOTS
	if _multiplayer:
		if not Network.session_bots:
			return 0
		var humans: int = maxi(Network.participants().size(), 1)
		return clampi(Network.session_bot_count, 0, maxi(MAX_CONTESTANTS - humans, 0))
	return clampi(GameSettings.effective_bot_count(), 0, MAX_CONTESTANTS - 1)


func _setup_local_contestant() -> void:
	if _cart == null:
		return
	var key: int = _local_key()
	var local_name: String = GameSettings.player_name.strip_edges()
	if local_name == "":
		local_name = "PLAYER"
	var local_col: Color = GameSettings.tag_color()
	_peer_vehicles[key] = _chosen_vehicle_id()
	_cart.reapply_vehicle(_chosen_vehicle_id())
	_register_contestant(key, local_name, local_col, _cart, false, -1, false)


func _setup_bots() -> void:
	if _multiplayer and not _is_host:
		return
	var count: int = _desired_bot_count()
	for idx: int in count:
		_spawn_bot_contestant(idx, false)


func _spawn_bot_contestant(bot_index: int, remote_ghost: bool) -> void:
	var key: int = -1 - bot_index
	if _contestants.has(key):
		return
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	cart.name = "KnockoutBot_%d" % (bot_index + 1)
	cart.position = Vector3(0.0, 0.5, 12.0)
	if not remote_ghost:
		cart.ai_mode = true
	add_child(cart)
	if remote_ghost:
		cart.setup_remote(BOT_PEER_BASE + bot_index)
		cart.set_vehicle_id(_chosen_vehicle_id())
	else:
		cart.setup_ai(_chosen_vehicle_id())
	var bot_name: String = BOT_NAMES[bot_index % BOT_NAMES.size()]
	var bot_col: Color = BOT_COLORS[bot_index % BOT_COLORS.size()]
	_register_contestant(key, bot_name, bot_col, cart, true, bot_index, true)
	_bot_keys.append(key)


func _register_contestant(key: int, display_name: String, tint: Color,
		cart: CartPlayer, is_bot: bool, bot_index: int,
		show_overhead_badge: bool) -> void:
	var shield_parts: Dictionary = _attach_slam_shield(cart)
	var name_3d: Label3D = null
	var dmg_3d: Label3D = null
	if show_overhead_badge and cart != null:
		name_3d = Label3D.new()
		name_3d.name = "RivalName3D"
		name_3d.text = display_name
		name_3d.font = TITLE_FONT
		name_3d.font_size = 38
		name_3d.pixel_size = 0.0058
		name_3d.outline_size = 11
		name_3d.outline_modulate = UiPalette.OUTLINE
		name_3d.modulate = tint.lightened(0.22)
		name_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_3d.no_depth_test = true
		name_3d.position = Vector3(0.0, 2.02, 0.0)
		cart.add_child(name_3d)

		dmg_3d = Label3D.new()
		dmg_3d.name = "RivalDamage3D"
		dmg_3d.text = "0%"
		dmg_3d.font = TITLE_FONT
		dmg_3d.font_size = 48
		dmg_3d.pixel_size = 0.0066
		dmg_3d.outline_size = 13
		dmg_3d.outline_modulate = UiPalette.OUTLINE
		dmg_3d.modulate = Color.WHITE
		dmg_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dmg_3d.no_depth_test = true
		dmg_3d.position = Vector3(0.0, 2.46, 0.0)
		cart.add_child(dmg_3d)

	var base_mult: float = cart.boost_speed_multiplier if cart != null else 1.35
	_contestants[key] = {
		"key": key,
		"name": display_name,
		"color": tint,
		"cart": cart,
		"is_bot": is_bot,
		"bot_index": bot_index,
		"alive": true,
		"damage_pct": 0.0,
		"score": 0,
		"kos": 0,
		"last_attacker_id": 0,
		"last_hit_time": -999.0,
		"slam_cooldown": 0.0,
		"slam_timer": 0.0,
		"slam_dir": Vector3.FORWARD,
		"slam_hits": {},
		"kb_timer": 0.0,
		"base_boost_mult": base_mult,
		"shield_node": shield_parts.get("root"),
		"shield_mat": shield_parts.get("mat"),
		"ring_node": shield_parts.get("ring"),
		"name_3d": name_3d,
		"dmg_3d": dmg_3d,
		"spawn_slot": 0,
		"ai_target": 0,
		"ai_retarget_t": 0.0,
		"ai_strafe": 1.0 if (absi(key) % 2 == 0) else -1.0,
	}


func _attach_slam_shield(cart: CartPlayer) -> Dictionary:
	if cart == null:
		return {}
	var holder := Node3D.new()
	holder.name = "PowerSlamShield"
	holder.position = Vector3(0.0, 0.72, 0.0)
	holder.visible = false
	cart.add_child(holder)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.62, 0.14, 0.46)

	var shell := MeshInstance3D.new()
	shell.name = "EnergyShell"
	var sphere := SphereMesh.new()
	sphere.radius = 1.48
	sphere.height = 2.15
	sphere.radial_segments = 18
	sphere.rings = 10
	shell.mesh = sphere
	shell.scale = Vector3(1.0, 0.82, 1.32)
	shell.material_override = mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(shell)

	var ring := MeshInstance3D.new()
	ring.name = "ShockRing"
	var torus := TorusMesh.new()
	torus.inner_radius = 1.55
	torus.outer_radius = 1.98
	torus.rings = 24
	torus.ring_segments = 8
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.12, 1.0)
	ring.position = Vector3(0.0, -0.32, 0.0)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(ring)

	return {"root": holder, "mat": mat, "ring": ring}


func _damage_color(pct: float) -> Color:
	if pct < 50.0:
		return Color.WHITE.lerp(UiPalette.YELLOW, clampf(pct / 50.0, 0.0, 1.0))
	if pct < 100.0:
		return UiPalette.YELLOW.lerp(Color("ff8c24"), clampf((pct - 50.0) / 50.0, 0.0, 1.0))
	if pct < 150.0:
		return Color("ff8c24").lerp(Color("ff3644"), clampf((pct - 100.0) / 50.0, 0.0, 1.0))
	var pulse: float = 0.5 + 0.5 * sin(_visual_time * 14.0)
	return Color("ff2938").lerp(Color("ff9ca3"), pulse * 0.65)


func _refresh_3d_badge(entry: Dictionary, pop: bool = false) -> void:
	var dmg_lbl: Label3D = entry.get("dmg_3d") as Label3D
	var name_lbl: Label3D = entry.get("name_3d") as Label3D
	var alive: bool = bool(entry.get("alive", true))
	var pct: float = float(entry.get("damage_pct", 0.0))
	if name_lbl != null and is_instance_valid(name_lbl):
		name_lbl.visible = alive
		name_lbl.text = str(entry.get("name", "RIVAL"))
	if dmg_lbl != null and is_instance_valid(dmg_lbl):
		dmg_lbl.visible = alive
		dmg_lbl.text = "%d%%" % int(round(pct))
		dmg_lbl.modulate = _damage_color(pct)
		if pop:
			dmg_lbl.scale = Vector3.ONE * 1.32
			var tw: Tween = create_tween()
			tw.tween_property(dmg_lbl, "scale", Vector3.ONE, 0.20) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ==========================================================================
# Round Flow, Spawning, Ring-Out & Scoring
# ==========================================================================

func _sorted_contestant_keys() -> Array[int]:
	var humans: Array[int] = []
	var bots: Array[int] = []
	for raw_key: Variant in _contestants.keys():
		var k: int = int(raw_key)
		if k > 0:
			humans.append(k)
		else:
			bots.append(k)
	humans.sort()
	bots.sort()
	bots.reverse() # -1, -2, -3...
	var ordered: Array[int] = []
	ordered.append_array(humans)
	ordered.append_array(bots)
	return ordered


func _start_round(round_num: int, forced_slots: Dictionary = {}) -> void:
	_round_index = clampi(round_num, 1, _total_rounds)
	_phase = Phase.COUNTDOWN
	_countdown = COUNTDOWN_SECONDS
	_last_count_int = int(ceil(_countdown))
	_round_elapsed = 0.0
	_round_remaining = _round_duration
	_local_slam_queued = false
	_pair_cooldowns.clear()
	_pre_step_vel.clear()

	_reset_waves()
	_set_spectator_mode(false)
	if _intermission_panel != null:
		_intermission_panel.visible = false

	var spawns: Array[Transform3D] = []
	var raw_spawns: Variant = _arena_data.get("spawns", [])
	if raw_spawns is Array:
		for sp: Variant in raw_spawns as Array:
			if sp is Transform3D:
				spawns.append(sp as Transform3D)
	if spawns.is_empty():
		spawns.append(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.4, 14.0)))

	var keys: Array[int] = _sorted_contestant_keys()
	for idx: int in keys.size():
		var key: int = keys[idx]
		var entry: Dictionary = _contestants[key]
		var slot: int = int(forced_slots.get(key, (idx + (_round_index - 1) * 3) % spawns.size()))
		slot = posmod(slot, spawns.size())
		entry["spawn_slot"] = slot
		entry["alive"] = true
		entry["damage_pct"] = 0.0
		entry["last_attacker_id"] = 0
		entry["last_hit_time"] = -999.0
		entry["slam_cooldown"] = 0.0
		entry["slam_timer"] = 0.0
		entry["slam_hits"] = {}
		entry["kb_timer"] = 0.0

		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart):
			var spawn_xform: Transform3D = spawns[slot]
			cart.visible = true
			cart.boost_speed_multiplier = float(entry.get("base_boost_mult", 1.35))
			cart.race_finished = false
			if cart.remote_mode:
				cart.global_transform = spawn_xform
				cart.net_position = spawn_xform.origin
				cart.net_yaw = spawn_xform.basis.get_euler().y
				cart.net_velocity = Vector3.ZERO
				cart.contact_enabled = true
				cart.collision_layer = CollisionLayers.GHOST
				cart.reset_physics_interpolation()
			else:
				cart.reset_at(spawn_xform, false)
				cart.contact_enabled = true
				cart.collision_layer = CollisionLayers.GHOST if cart.ai_mode else CollisionLayers.PLAYER
				cart.collision_mask = (CollisionLayers.WORLD | CollisionLayers.PLAYER
					| CollisionLayers.GHOST | CollisionLayers.SOLID_PROP)
				cart.set_physics_process(false)
			var shield: Node3D = entry.get("shield_node") as Node3D
			if shield != null:
				shield.visible = false
		_refresh_3d_badge(entry, false)

	if _countdown_label != null:
		_countdown_label.text = str(_last_count_int)
		_countdown_label.visible = not _selftest
	_refresh_hud_immediate()

	if _multiplayer and _is_host:
		_broadcast_round_transition("ROUND %d" % _round_index, "")

	if _selftest:
		_begin_brawl()


func _begin_brawl() -> void:
	if _phase != Phase.COUNTDOWN:
		return
	_phase = Phase.BRAWL
	_round_elapsed = 0.0
	_round_remaining = _round_duration
	if _countdown_label != null:
		_countdown_label.visible = false
	for raw_key: Variant in _contestants.keys():
		var entry: Dictionary = _contestants[int(raw_key)]
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart) and not cart.remote_mode:
			cart.set_physics_process(true)
	_show_toast("BRAWL!  ·  KNOCK RIVALS OFF THE EDGE!", 2.2, UiPalette.YELLOW)
	_play_one_shot(COUNTDOWN_GO, -5.0, 1.0)
	if _multiplayer and _is_host:
		_broadcast_round_transition("BRAWL!", "")


func _set_spectator_mode(active: bool) -> void:
	_spectator_active = active
	var chase_cam: Camera3D = _cart.get_node_or_null("CameraArm/Camera3D") as Camera3D \
		if _cart != null and is_instance_valid(_cart) else null
	if active and _spectator_cam != null:
		if chase_cam != null:
			chase_cam.current = false
		_spectator_cam.current = true
	else:
		if _spectator_cam != null:
			_spectator_cam.current = false
		if chase_cam != null:
			chase_cam.current = true
	if _spectator_pill != null:
		_spectator_pill.visible = active


# ==========================================================================
# Fixed 60 Hz Physics Step: Combat, Knockback, Power-Slam, Ring-Outs & AI
# ==========================================================================

func _physics_process(delta: float) -> void:
	_time += delta
	_net_tick(delta)
	_apply_surface_grip()

	match _phase:
		Phase.COUNTDOWN:
			_tick_countdown(delta)
		Phase.BRAWL:
			_tick_local_slam_input()
			_tick_contestant_timers(delta)
			if _is_host or not _multiplayer:
				_tick_wave_schedule()
				_tick_power_slams()
				_tick_smash_collisions()
				_tick_ai_bots(delta)
				_tick_ring_outs()
				_tick_round_clock(delta)
			else:
				_tick_client_slam_surge()
		Phase.INTERMISSION:
			if _is_host or not _multiplayer:
				_intermission_timer = maxf(_intermission_timer - delta, 0.0)
				if _intermission_timer <= 0.0:
					if _round_index < _total_rounds:
						_start_round(_round_index + 1)
					else:
						_finish_match()

	_snapshot_pre_step_velocities()


func _snapshot_pre_step_velocities() -> void:
	for raw_key: Variant in _contestants.keys():
		var key: int = int(raw_key)
		var entry: Dictionary = _contestants[key]
		if not bool(entry.get("alive", false)):
			continue
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart):
			_pre_step_vel[key] = _safe_vel(cart.get_collision_velocity())


func _safe_vel(v: Vector3) -> Vector3:
	return v.limit_length(60.0) if v.is_finite() else Vector3.ZERO


func _tick_countdown(delta: float) -> void:
	_countdown = maxf(_countdown - delta, 0.0)
	var count_now: int = int(ceil(_countdown))
	if count_now == _last_count_int:
		return
	_last_count_int = count_now
	if count_now > 0:
		if _countdown_label != null:
			_countdown_label.text = str(count_now)
			_countdown_label.visible = true
			_pop_control(_countdown_label)
		_play_one_shot(COUNTDOWN_BEEP, -8.0, 1.0 + float(3 - count_now) * 0.08)
		return
	if not _multiplayer or _is_host:
		_begin_brawl()


func _tick_round_clock(delta: float) -> void:
	_round_elapsed += delta
	_round_remaining = maxf(_round_duration - _round_elapsed, 0.0)
	var alive_keys: Array[int] = _alive_contestant_keys()
	if alive_keys.is_empty():
		# Everybody is out (e.g. solo self ring-out): conclude immediately
		# instead of staring at an empty arena until the timer expires.
		_conclude_round(alive_keys, false)
	elif alive_keys.size() <= 1 and _contestants.size() >= 2:
		_conclude_round(alive_keys, false)
	elif _round_remaining <= 0.0:
		_conclude_round(alive_keys, true)


func _alive_contestant_keys() -> Array[int]:
	var out: Array[int] = []
	for raw_key: Variant in _contestants.keys():
		var k: int = int(raw_key)
		if bool(_contestants[k].get("alive", false)):
			out.append(k)
	return out


func _apply_surface_grip() -> void:
	var base_grip: float = float(_arena_data.get("base_grip", 0.95))
	var zones: Array = _arena_data.get("surface_zones", []) as Array
	for raw_key: Variant in _contestants.keys():
		var entry: Dictionary = _contestants[int(raw_key)]
		if not bool(entry.get("alive", false)):
			continue
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart == null or not is_instance_valid(cart) or cart.remote_mode:
			continue
		var grip: float = base_grip
		var best_prio: int = -1
		var p2 := Vector2(cart.global_position.x, cart.global_position.z)
		for raw_z: Variant in zones:
			if not (raw_z is Dictionary):
				continue
			var z: Dictionary = raw_z as Dictionary
			var prio: int = int(z.get("priority", 0))
			if prio < best_prio:
				continue
			var c: Vector2 = z.get("center", Vector2.ZERO) as Vector2
			var d: float = p2.distance_to(c)
			var kind: String = str(z.get("shape", "circle"))
			if kind == "circle" and d <= float(z.get("radius", 0.0)):
				grip = float(z.get("grip", grip))
				best_prio = prio
			elif kind == "ring" and d >= float(z.get("inner_radius", 0.0)) \
					and d <= float(z.get("outer_radius", 0.0)):
				grip = float(z.get("grip", grip))
				best_prio = prio
		cart.surface_grip = clampf(grip, 0.25, 1.35)


# --------------------------------------------------------------------------
# Mechanic 2: Power-Slam Surge
# --------------------------------------------------------------------------

func _tick_local_slam_input() -> void:
	var want_slam: bool = _local_slam_queued
	_local_slam_queued = false
	if not _is_pause_open() and not Network.input_locked \
			and Input.is_action_just_pressed(SLAM_ACTION):
		want_slam = true
	if not want_slam:
		return
	var key: int = _local_key()
	if not _contestants.has(key):
		return
	var entry: Dictionary = _contestants[key]
	if not bool(entry.get("alive", false)):
		return
	if float(entry.get("slam_cooldown", 0.0)) > 0.0:
		return
	if _multiplayer and not _is_host:
		_activate_slam(key)
		if Network.is_scene_ready(1):
			rpc_id(1, "_net_request_slam")
	else:
		_activate_slam(key)
		if _multiplayer and _is_host:
			_broadcast_slam(key)


func _activate_slam(key: int, override_dir: Vector3 = Vector3.ZERO) -> bool:
	if not _contestants.has(key):
		return false
	var entry: Dictionary = _contestants[key]
	if not bool(entry.get("alive", false)):
		return false
	if float(entry.get("slam_cooldown", 0.0)) > 0.05 and override_dir == Vector3.ZERO:
		return false
	var cart: CartPlayer = entry.get("cart") as CartPlayer
	if cart == null or not is_instance_valid(cart):
		return false

	var fwd: Vector3 = override_dir
	if fwd.length_squared() < 0.01:
		fwd = -cart.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3.FORWARD

	entry["slam_cooldown"] = SLAM_COOLDOWN
	entry["slam_timer"] = SLAM_DURATION
	entry["slam_dir"] = fwd
	entry["slam_hits"] = {}

	if not cart.remote_mode:
		var base_mult: float = float(entry.get("base_boost_mult", 1.35))
		var cur_fwd: float = maxf(cart.velocity.dot(fwd), 0.0)
		var target_speed: float = cur_fwd + SLAM_SURGE_SPEED
		var needed_mult: float = (target_speed + 2.0) / maxf(cart.max_speed, 1.0)
		cart.boost_speed_multiplier = clampf(maxf(base_mult, needed_mult), base_mult, 2.35)
		entry["kb_timer"] = maxf(float(entry.get("kb_timer", 0.0)), SLAM_DURATION + 0.15)
		# The surge's only impulse: the per-frame ticks below enforce the hard
		# planar-speed cap instead of pushing again on top of this.
		cart.velocity += fwd * SLAM_SURGE_SPEED
		if key == _local_key():
			var cam_rig: ChaseCamera = cart.get_node_or_null("CameraArm") as ChaseCamera
			if cam_rig != null:
				cam_rig.punch_fov(7.5)
				cam_rig.add_shake(0.22)

	var shield: Node3D = entry.get("shield_node") as Node3D
	if shield != null:
		shield.visible = true
	_play_one_shot(SLAM_IGNITE_SFX, -5.0, 1.08)
	_play_one_shot(SLAM_WHOOSH_SFX, -6.0, 1.0)
	return true


func _tick_contestant_timers(delta: float) -> void:
	for raw_key: Variant in _contestants.keys():
		var entry: Dictionary = _contestants[int(raw_key)]
		var cd: float = maxf(float(entry.get("slam_cooldown", 0.0)) - delta, 0.0)
		var st: float = maxf(float(entry.get("slam_timer", 0.0)) - delta, 0.0)
		var kbt: float = maxf(float(entry.get("kb_timer", 0.0)) - delta, 0.0)
		entry["slam_cooldown"] = cd
		entry["slam_timer"] = st
		entry["kb_timer"] = kbt

		var shield: Node3D = entry.get("shield_node") as Node3D
		if shield != null:
			shield.visible = st > 0.0 and bool(entry.get("alive", false))

		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart) and not cart.remote_mode and kbt <= 0.0:
			var base_mult: float = float(entry.get("base_boost_mult", 1.35))
			cart.boost_speed_multiplier = move_toward(
				cart.boost_speed_multiplier, base_mult, 2.4 * delta)


func _tick_client_slam_surge() -> void:
	var entry: Dictionary = _contestants.get(_local_key(), {}) as Dictionary
	if entry.is_empty() or float(entry.get("slam_timer", 0.0)) <= 0.0:
		return
	var cart: CartPlayer = entry.get("cart") as CartPlayer
	if cart == null or not is_instance_valid(cart):
		return
	# Single impulse was applied in _activate_slam; only enforce the hard
	# planar-speed cap here instead of stacking a per-frame push on top.
	var cap: float = cart.max_speed + SLAM_SURGE_SPEED
	var planar := Vector2(cart.velocity.x, cart.velocity.z)
	if planar.length() > cap:
		var clamped: Vector2 = planar.normalized() * cap
		cart.velocity.x = clamped.x
		cart.velocity.z = clamped.y


func _tick_power_slams() -> void:
	var keys: Array[int] = _alive_contestant_keys()
	for attacker_key: int in keys:
		var attacker: Dictionary = _contestants[attacker_key]
		if float(attacker.get("slam_timer", 0.0)) <= 0.0:
			continue
		var a_cart: CartPlayer = attacker.get("cart") as CartPlayer
		if a_cart == null or not is_instance_valid(a_cart):
			continue
		var s_dir: Vector3 = attacker.get("slam_dir", -a_cart.global_transform.basis.z) as Vector3
		if not a_cart.remote_mode:
			# The surge is the single impulse from _activate_slam; hold the
			# hard planar-speed cap instead of stacking a per-frame push.
			var surge_cap: float = a_cart.max_speed + SLAM_SURGE_SPEED
			var surge_planar := Vector2(a_cart.velocity.x, a_cart.velocity.z)
			if surge_planar.length() > surge_cap:
				var surge_clamped: Vector2 = surge_planar.normalized() * surge_cap
				a_cart.velocity.x = surge_clamped.x
				a_cart.velocity.z = surge_clamped.y

		var hits: Dictionary = attacker.get("slam_hits", {}) as Dictionary
		var a_pos: Vector3 = a_cart.global_position
		var mass_ratio: float = clampf(a_cart.get_mass() / 1200.0, 0.80, 1.40)

		for victim_key: int in keys:
			if victim_key == attacker_key or hits.has(victim_key):
				continue
			var victim: Dictionary = _contestants[victim_key]
			var v_cart: CartPlayer = victim.get("cart") as CartPlayer
			if v_cart == null or not is_instance_valid(v_cart):
				continue
			var offset: Vector3 = v_cart.global_position - a_pos
			if absf(offset.y) > 2.3:
				continue
			var planar := Vector2(offset.x, offset.z)
			if planar.length() > SLAM_HIT_RADIUS:
				continue

			hits[victim_key] = true
			attacker["slam_hits"] = hits
			_pair_cooldowns[_pair_id(attacker_key, victim_key)] = _time + PAIR_HIT_COOLDOWN

			var radial: Vector3 = Vector3(offset.x, 0.0, offset.z).normalized() \
				if planar.length_squared() > 0.001 else s_dir
			var push_dir: Vector3 = (radial * 0.68 + s_dir * 0.32).normalized()
			if push_dir.length_squared() < 0.001:
				push_dir = s_dir

			var new_pct: float = clampf(
				float(victim.get("damage_pct", 0.0)) + SLAM_DAMAGE_BONUS, 0.0, DAMAGE_MAX)
			victim["damage_pct"] = new_pct
			victim["last_attacker_id"] = attacker_key
			victim["last_hit_time"] = _time

			var kb_scale: float = (1.0 + new_pct / KNOCKBACK_PCT_DIVISOR) * SLAM_KNOCKBACK_MULT
			var horiz_mag: float = clampf(7.8 * mass_ratio * kb_scale, 11.5, 41.0)
			var up_pop: float = clampf(2.6 + kb_scale * 0.92, 3.2, 8.2)
			var impulse: Vector3 = push_dir * horiz_mag + Vector3.UP * up_pop

			_deliver_knockback(victim_key, impulse, new_pct, attacker_key, true)
			_spawn_hit_burst((a_pos + v_cart.global_position) * 0.5 + Vector3.UP * 0.8, true)
			_pop_world_text("+%d%% SLAM!" % int(SLAM_DAMAGE_BONUS),
				v_cart.global_position + Vector3.UP * 2.9, Color("ffb830"), 58)
			_play_one_shot(SLAM_HIT_SFX, -3.0, 0.92)


# --------------------------------------------------------------------------
# Mechanic 1: Smash-Style Knockback % Collisions
# --------------------------------------------------------------------------

func _tick_smash_collisions() -> void:
	var keys: Array[int] = _alive_contestant_keys()
	var count: int = keys.size()
	for i: int in count:
		var key_a: int = keys[i]
		var entry_a: Dictionary = _contestants[key_a]
		var cart_a: CartPlayer = entry_a.get("cart") as CartPlayer
		if cart_a == null or not is_instance_valid(cart_a):
			continue
		for j: int in range(i + 1, count):
			var key_b: int = keys[j]
			var pair_token: String = _pair_id(key_a, key_b)
			if float(_pair_cooldowns.get(pair_token, -1.0)) > _time:
				continue
			var entry_b: Dictionary = _contestants[key_b]
			var cart_b: CartPlayer = entry_b.get("cart") as CartPlayer
			if cart_b == null or not is_instance_valid(cart_b):
				continue

			var pos_a: Vector3 = cart_a.global_position
			var pos_b: Vector3 = cart_b.global_position
			if absf(pos_b.y - pos_a.y) > 1.85:
				continue
			var diff_xz := Vector3(pos_b.x - pos_a.x, 0.0, pos_b.z - pos_a.z)
			var dist: float = diff_xz.length()
			var reach: float = _contact_reach(cart_a, cart_b)
			if dist > reach and not _did_slide_collide(cart_a, cart_b):
				continue

			var normal: Vector3 = diff_xz / dist if dist > 0.001 else Vector3.RIGHT
			var vel_a: Vector3 = _best_pre_vel(key_a, cart_a, normal)
			var vel_b: Vector3 = _best_pre_vel(key_b, cart_b, -normal)
			var closing: float = (vel_a - vel_b).dot(normal)
			if closing < MIN_HIT_CLOSING_SPEED:
				continue

			_pair_cooldowns[pair_token] = _time + PAIR_HIT_COOLDOWN
			var into_b: float = maxf(vel_a.dot(normal), 0.0)
			var into_a: float = maxf(-vel_b.dot(normal), 0.0)
			var speed_t: float = clampf((closing - MIN_HIT_CLOSING_SPEED) / 17.5, 0.0, 1.0)
			var base_dmg: float = lerpf(DAMAGE_HIT_MIN, DAMAGE_HIT_MAX, speed_t)
			var mass_a: float = clampf(cart_a.get_mass() / 1200.0, 0.78, 1.42)
			var mass_b: float = clampf(cart_b.get_mass() / 1200.0, 0.78, 1.42)

			if into_b >= into_a * 0.42 or into_a < 1.0:
				_apply_smash_hit(key_a, key_b, normal, speed_t, base_dmg * mass_a, mass_a)
			if into_a >= into_b * 0.42 and into_a >= 1.5:
				_apply_smash_hit(key_b, key_a, -normal, speed_t, base_dmg * mass_b, mass_b)

			_spawn_hit_burst((pos_a + pos_b) * 0.5 + Vector3.UP * 0.7, false)
			_play_one_shot(SLAM_HIT_SFX, -6.5, lerpf(1.18, 0.90, speed_t))


func _pair_id(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


func _contact_reach(a: CartPlayer, b: CartPlayer) -> float:
	var ext_a: Dictionary = a.get_collision_extents()
	var ext_b: Dictionary = b.get_collision_extents()
	var ra: float = (float(ext_a.get("width", 1.5)) + float(ext_a.get("length", 2.26))) * 0.26
	var rb: float = (float(ext_b.get("width", 1.5)) + float(ext_b.get("length", 2.26))) * 0.26
	return ra + rb + 0.36


func _did_slide_collide(a: CartPlayer, b: CartPlayer) -> bool:
	if not a.remote_mode:
		for idx: int in a.get_slide_collision_count():
			var col: KinematicCollision3D = a.get_slide_collision(idx)
			if col != null and col.get_collider() == b:
				return true
	if not b.remote_mode:
		for idx: int in b.get_slide_collision_count():
			var col: KinematicCollision3D = b.get_slide_collision(idx)
			if col != null and col.get_collider() == a:
				return true
	return false


func _best_pre_vel(key: int, cart: CartPlayer, dir: Vector3) -> Vector3:
	var cur: Vector3 = _safe_vel(cart.get_collision_velocity())
	var pre: Vector3 = _pre_step_vel.get(key, cur) as Vector3
	return pre if pre.dot(dir) >= cur.dot(dir) else cur


func _apply_smash_hit(attacker_key: int, victim_key: int, push_dir: Vector3,
		speed_t: float, raw_damage: float, attacker_mass_ratio: float) -> void:
	var victim: Dictionary = _contestants[victim_key]
	var added_dmg: float = clampf(raw_damage, DAMAGE_HIT_MIN, DAMAGE_HIT_MAX)
	var new_pct: float = clampf(float(victim.get("damage_pct", 0.0)) + added_dmg, 0.0, DAMAGE_MAX)
	victim["damage_pct"] = new_pct
	victim["last_attacker_id"] = attacker_key
	victim["last_hit_time"] = _time

	var kb_scale: float = 1.0 + new_pct / KNOCKBACK_PCT_DIVISOR
	var base_push: float = lerpf(3.0, 6.8, speed_t) * attacker_mass_ratio
	var horiz_mag: float = clampf(base_push * kb_scale, 3.0, 36.0)
	var up_pop: float = 0.0 if new_pct < 42.0 \
		else clampf((kb_scale - 1.45) * 2.15, 1.2, 6.8)
	var impulse: Vector3 = push_dir.normalized() * horiz_mag + Vector3.UP * up_pop
	_deliver_knockback(victim_key, impulse, new_pct, attacker_key, false)


func _deliver_knockback(victim_key: int, impulse: Vector3, new_pct: float,
		attacker_key: int, is_slam: bool) -> void:
	if not _contestants.has(victim_key):
		return
	var victim: Dictionary = _contestants[victim_key]
	_refresh_3d_badge(victim, true)
	if victim_key == _local_key():
		_pulse_hud_damage()

	var cart: CartPlayer = victim.get("cart") as CartPlayer
	if cart == null or not is_instance_valid(cart):
		return

	if _multiplayer and _is_host and victim_key > 1 and cart.remote_mode:
		if Network.is_scene_ready(victim_key):
			rpc_id(victim_key, "_net_apply_knockback", impulse, new_pct, attacker_key, is_slam)
		return

	_apply_local_knockback_body(victim, cart, impulse, is_slam, victim_key == _local_key())


func _apply_local_knockback_body(entry: Dictionary, cart: CartPlayer,
		impulse: Vector3, is_slam: bool, is_local_player: bool) -> void:
	if cart == null or not is_instance_valid(cart) or cart.remote_mode:
		return
	var horiz := Vector2(impulse.x, impulse.z)
	var horiz_mag: float = horiz.length()
	var base_mult: float = float(entry.get("base_boost_mult", 1.35))
	var needed_mult: float = (horiz_mag + 3.0) / maxf(cart.max_speed, 1.0)
	cart.boost_speed_multiplier = clampf(
		maxf(cart.boost_speed_multiplier, needed_mult), base_mult, 2.45)
	entry["kb_timer"] = maxf(float(entry.get("kb_timer", 0.0)),
		clampf(0.22 + horiz_mag * 0.012, 0.22, 0.62))

	# Blend knockback cleanly: light hits at 0% nudge velocity; high-% hits launch!
	var push_dir: Vector3 = Vector3(impulse.x, 0.0, impulse.z).normalized() \
		if horiz_mag > 0.001 else Vector3.FORWARD
	var along: float = cart.velocity.dot(push_dir)
	var target_along: float = maxf(along + horiz_mag * 0.65, horiz_mag)
	cart.velocity += push_dir * (target_along - along)
	if impulse.y > 0.1:
		cart.velocity.y = maxf(cart.velocity.y, impulse.y)

	if is_local_player:
		var cam_rig: ChaseCamera = cart.get_node_or_null("CameraArm") as ChaseCamera
		if cam_rig != null:
			cam_rig.add_shake(0.55 if is_slam else clampf(horiz_mag / 32.0, 0.14, 0.48))
			if is_slam or horiz_mag > 18.0:
				cam_rig.punch_fov(8.5 if is_slam else 5.0)


# --------------------------------------------------------------------------
# Ring-Outs, Elimination, Round Conclusion & Match End
# --------------------------------------------------------------------------

func _tick_ring_outs() -> void:
	var now_ms: int = Time.get_ticks_msec()
	for raw_key: Variant in _contestants.keys():
		var key: int = int(raw_key)
		var entry: Dictionary = _contestants[key]
		if not bool(entry.get("alive", false)):
			continue
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart == null or not is_instance_valid(cart):
			continue
		if cart.remote_mode:
			# A ghost that stopped streaming poses (crashed client, stalled
			# loader) would otherwise sit parked above the arena alive forever
			# and stall the round. Expire it like a ring-out.
			var last_ms: int = cart._net_last_receive_ms
			if now_ms - last_ms > CartPlayer.GHOST_STREAM_TIMEOUT_MS:
				_eliminate_contestant(key, cart.net_position)
				continue
		var check_pos: Vector3 = cart.net_position if cart.remote_mode else cart.global_position
		if check_pos.y <= _ko_y:
			_eliminate_contestant(key, check_pos)


func _eliminate_contestant(victim_key: int, ko_pos: Vector3) -> void:
	if not _contestants.has(victim_key):
		return
	var victim: Dictionary = _contestants[victim_key]
	if not bool(victim.get("alive", false)):
		return
	victim["alive"] = false
	victim["slam_timer"] = 0.0

	var attacker_key: int = int(victim.get("last_attacker_id", 0))
	var hit_age: float = _time - float(victim.get("last_hit_time", -999.0))
	var valid_ko: bool = attacker_key != 0 and attacker_key != victim_key \
		and hit_age <= KO_CREDIT_WINDOW and _contestants.has(attacker_key)

	if valid_ko:
		var attacker: Dictionary = _contestants[attacker_key]
		attacker["score"] = int(attacker.get("score", 0)) + POINTS_PER_KO
		attacker["kos"] = int(attacker.get("kos", 0)) + 1
		var a_cart: CartPlayer = attacker.get("cart") as CartPlayer
		if a_cart != null and is_instance_valid(a_cart):
			_pop_world_text("+%d KO!" % POINTS_PER_KO,
				a_cart.global_position + Vector3.UP * 3.1, UiPalette.YELLOW, 68)
		_show_toast("%s KO'd %s! (+%d)" % [
			str(attacker.get("name", "PLAYER")),
			str(victim.get("name", "RIVAL")),
			POINTS_PER_KO,
		], 2.6, UiPalette.YELLOW)
	else:
		attacker_key = 0
		_show_toast("%s RINGED OUT!" % str(victim.get("name", "RIVAL")), 2.2, UiPalette.RED)

	_park_eliminated_cart(victim)
	_spawn_ko_burst(Vector3(ko_pos.x, _ko_y + 0.35, ko_pos.z))
	_play_one_shot(KO_CRASH_SFX, -3.5, 1.0)

	if victim_key == _local_key() and _alive_contestant_keys().size() > 1:
		_set_spectator_mode(true)

	_refresh_hud_immediate()
	if _multiplayer and _is_host:
		_broadcast_ko_event(victim_key, attacker_key, ko_pos)


func _park_eliminated_cart(entry: Dictionary) -> void:
	var cart: CartPlayer = entry.get("cart") as CartPlayer
	if cart != null and is_instance_valid(cart):
		cart.visible = false
		cart.contact_enabled = false
		cart.race_finished = true
		cart.collision_layer = 0
		cart.collision_mask = 0
		cart.velocity = Vector3.ZERO
		if not cart.remote_mode:
			cart.set_physics_process(false)
	var shield: Node3D = entry.get("shield_node") as Node3D
	if shield != null:
		shield.visible = false
	_refresh_3d_badge(entry, false)


func _conclude_round(survivor_keys: Array[int], timed_out: bool) -> void:
	if _phase != Phase.BRAWL:
		return
	var banner_title: String = ""
	var banner_sub: String = ""

	if not timed_out and survivor_keys.size() == 1:
		var win_key: int = survivor_keys[0]
		var winner: Dictionary = _contestants[win_key]
		winner["score"] = int(winner.get("score", 0)) + POINTS_ROUND_WIN
		banner_title = "ROUND %d WINNER: %s!" % [_round_index, str(winner.get("name", "PLAYER"))]
		banner_sub = "+%d PTS SURVIVAL BONUS" % POINTS_ROUND_WIN
	elif timed_out and not survivor_keys.is_empty():
		var names := PackedStringArray()
		for sk: int in survivor_keys:
			var surv: Dictionary = _contestants[sk]
			surv["score"] = int(surv.get("score", 0)) + POINTS_SURVIVOR_TIMEOUT
			names.append(str(surv.get("name", "SURVIVOR")))
		banner_title = "TIME UP! %d SURVIVED" % survivor_keys.size()
		banner_sub = "+%d PTS EACH: %s" % [POINTS_SURVIVOR_TIMEOUT, ", ".join(names)]
	else:
		banner_title = "ROUND %d DOUBLE KO!" % _round_index
		banner_sub = "NO SURVIVOR BONUS"

	# Freeze driving karts cleanly during intermission.
	for raw_key: Variant in _contestants.keys():
		var cart: CartPlayer = _contestants[int(raw_key)].get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart) and not cart.remote_mode:
			cart.set_ai_controls(0.0, 1.0, 0.0)
			cart.set_physics_process(false)

	_play_one_shot(ROUND_CHIME, -5.0, 1.05)
	_refresh_hud_immediate()

	if _round_index >= _total_rounds:
		_finish_match()
		return

	_phase = Phase.INTERMISSION
	_intermission_timer = INTERMISSION_SECONDS
	_show_intermission_banner(banner_title, banner_sub)
	if _multiplayer and _is_host:
		_broadcast_round_transition(banner_title, banner_sub)


func _show_intermission_banner(title_text: String, sub_text: String) -> void:
	if _intermission_panel == null:
		return
	_intermission_title.text = title_text
	_intermission_sub.text = "%s\n%s" % [sub_text, _standings_summary_line()]
	_intermission_panel.visible = true
	_pop_control(_intermission_panel)


func _standings_summary_line() -> String:
	var ranked: Array[Dictionary] = _ranked_contestants()
	var parts := PackedStringArray()
	for i: int in mini(ranked.size(), 4):
		var c: Dictionary = ranked[i]
		parts.append("%d. %s (%d PT)" % [i + 1, str(c.get("name", "?")), int(c.get("score", 0))])
	return "  ·  ".join(parts)


func _finish_match() -> void:
	if _phase == Phase.FINISHED:
		return
	_phase = Phase.FINISHED
	_set_spectator_mode(false)
	if _intermission_panel != null:
		_intermission_panel.visible = false
	if _countdown_label != null:
		_countdown_label.visible = false
	for raw_key: Variant in _contestants.keys():
		var cart: CartPlayer = _contestants[int(raw_key)].get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart) and not cart.remote_mode:
			cart.set_physics_process(false)
			cart.velocity = Vector3.ZERO
	if _multiplayer and _is_host:
		Network.set_room_state("finished")
		_broadcast_round_transition("MATCH OVER", "")
	_show_result_card()


# ==========================================================================
# Smart Knockout AI (Arena-Aware, Edge Recovery, Chasm Routing & Power-Slam)
# ==========================================================================

func _tick_ai_bots(delta: float) -> void:
	var w1_danger: bool = _wave1_warning or _wave1_dropped
	var w2_danger: bool = _wave2_warning or _wave2_dropped
	var diff: int = Network.bot_difficulty()
	var chasm_half: float = float(_arena_data.get("chasm_half_x", 0.0))

	for bot_key: int in _bot_keys:
		if not _contestants.has(bot_key):
			continue
		var bot: Dictionary = _contestants[bot_key]
		if not bool(bot.get("alive", false)) or bool(bot.get("selftest_manual", false)):
			continue
		var cart: CartPlayer = bot.get("cart") as CartPlayer
		if cart == null or not is_instance_valid(cart) or cart.remote_mode:
			continue

		var pos: Vector3 = cart.global_position
		var fwd: Vector3 = -cart.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD

		# 1. Edge & Collapsing Danger-Zone Recovery Priority:
		var ahead_probe: Vector3 = pos + fwd * 5.8
		var on_safe_now: bool = KnockoutMaps.is_point_safe(_arena_data, pos, w1_danger, w2_danger)
		var ahead_safe: bool = KnockoutMaps.is_point_safe(_arena_data, ahead_probe, w1_danger, w2_danger)

		if not on_safe_now or not ahead_safe:
			var anchor: Vector3 = _safe_recovery_anchor(pos, chasm_half)
			_steer_bot_toward(cart, anchor, 1.0, true, false)
			continue

		# 2. Target Selection (prefers high damage_pct rivals and rivals near edges):
		var retarget_t: float = float(bot.get("ai_retarget_t", 0.0)) - delta
		var target_key: int = int(bot.get("ai_target", 0))
		if retarget_t <= 0.0 or not _is_valid_rival(bot_key, target_key):
			target_key = _pick_ai_target(bot_key, pos, diff)
			bot["ai_target"] = target_key
			bot["ai_retarget_t"] = lerpf(0.55, 0.28, float(diff) * 0.5) \
				+ float(absi(bot_key) % 3) * 0.08
		else:
			bot["ai_retarget_t"] = retarget_t

		if target_key == 0 or not _contestants.has(target_key):
			var idle_anchor: Vector3 = _safe_recovery_anchor(pos, chasm_half)
			_steer_bot_toward(cart, idle_anchor, 0.65, false, false)
			continue

		var target_entry: Dictionary = _contestants[target_key]
		var t_cart: CartPlayer = target_entry.get("cart") as CartPlayer
		if t_cart == null or not is_instance_valid(t_cart):
			continue

		var t_pos: Vector3 = t_cart.global_position
		var t_vel: Vector3 = _safe_vel(t_cart.get_collision_velocity())
		var goal: Vector3 = t_pos + Vector3(t_vel.x, 0.0, t_vel.z) * 0.20

		# Foundry Twin-Island Bridge Routing across the 9 m central lava chasm:
		if chasm_half > 0.1 and pos.x * t_pos.x < 0.0 and absf(pos.x) > chasm_half:
			var bridge_z: float = _best_foundry_bridge_z(pos.z, w1_danger)
			if absf(pos.z - bridge_z) > 2.8:
				goal = Vector3(signf(pos.x) * 10.5, pos.y, bridge_z)
			else:
				goal = Vector3(-signf(pos.x) * 9.5, pos.y, bridge_z)

		var to_goal: Vector3 = goal - pos
		to_goal.y = 0.0
		var dist_to_target: float = Vector2(t_pos.x - pos.x, t_pos.z - pos.z).length()
		var local_goal: Vector3 = cart.to_local(Vector3(goal.x, pos.y, goal.z))
		var angle_err: float = atan2(-local_goal.x, -local_goal.z)

		var want_drift: bool = absf(angle_err) > [1.00, 0.85, 0.70][diff] \
			and Vector2(cart.velocity.x, cart.velocity.z).length() > [7.0, 8.5, 10.0][diff]
		var slam_probe: Vector3 = pos + fwd * 8.2
		var slam_path_safe: bool = KnockoutMaps.is_point_safe(
			_arena_data, slam_probe, w1_danger, w2_danger)
		var want_boost: bool = absf(angle_err) < 0.35 and dist_to_target > 4.0 and slam_path_safe

		_steer_bot_toward(cart, goal, 1.0, want_boost, want_drift)

		# 3. Fire Power-Slam when lined up and the trajectory stays safe!
		# Skill scales the trigger: Hard slams from further out and wider off.
		var angle_to_rival: float = absf(atan2(
			-cart.to_local(t_pos).x, -cart.to_local(t_pos).z))
		if float(bot.get("slam_cooldown", 0.0)) <= 0.0 \
				and dist_to_target <= [7.0, 8.5, 9.5][diff] and dist_to_target >= 1.8 \
				and angle_to_rival <= [0.30, 0.36, 0.42][diff] and slam_path_safe:
			if _activate_slam(bot_key) and _multiplayer and _is_host:
				_broadcast_slam(bot_key)


func _safe_recovery_anchor(pos: Vector3, chasm_half: float) -> Vector3:
	if chasm_half > 0.1:
		if absf(pos.x) <= chasm_half + 0.6:
			return Vector3(0.0, 2.2, 0.0)
		var side: float = -1.0 if pos.x < 0.0 else 1.0
		return Vector3(side * 10.6, 0.0, clampf(pos.z * 0.35, -8.0, 8.0))
	return Vector3.ZERO


func _best_foundry_bridge_z(cur_z: float, wave1_danger: bool) -> float:
	if wave1_danger:
		return 0.0
	var options: Array[float] = [-12.2, 0.0, 12.2]
	var best_z: float = 0.0
	var best_d: float = INF
	for bz: float in options:
		var d: float = absf(cur_z - bz)
		if d < best_d:
			best_d = d
			best_z = bz
	return best_z


func _is_valid_rival(self_key: int, rival_key: int) -> bool:
	if rival_key == 0 or rival_key == self_key or not _contestants.has(rival_key):
		return false
	return bool(_contestants[rival_key].get("alive", false))


func _pick_ai_target(self_key: int, self_pos: Vector3, diff: int = 1) -> int:
	var best_key: int = 0
	var best_score: float = -INF
	var safe_r: float = maxf(float(_arena_data.get("safe_radius", 20.0)), 1.0)
	# Skill-weighted hunting: Easy chases whoever is nearest, Hard hunts the
	# weakest high-percentage rival hanging near an edge. Same speed either way.
	var pct_w: float = [0.05, 0.16, 0.24][clampi(diff, 0, 2)]
	var edge_w: float = [4.0, 9.0, 12.0][clampi(diff, 0, 2)]
	var dist_w: float = [1.20, 0.58, 0.35][clampi(diff, 0, 2)]
	for raw_key: Variant in _contestants.keys():
		var k: int = int(raw_key)
		if k == self_key:
			continue
		var rival: Dictionary = _contestants[k]
		if not bool(rival.get("alive", false)):
			continue
		var r_cart: CartPlayer = rival.get("cart") as CartPlayer
		if r_cart == null or not is_instance_valid(r_cart):
			continue
		var r_pos: Vector3 = r_cart.global_position
		var dist: float = Vector2(r_pos.x - self_pos.x, r_pos.z - self_pos.z).length()
		var pct: float = float(rival.get("damage_pct", 0.0))
		var edge_ratio: float = Vector2(r_pos.x, r_pos.z).length() / safe_r
		var bias: float = float((absi(self_key * 7 + k * 13)) % 5) * 1.1
		var score: float = pct * pct_w + edge_ratio * edge_w - dist * dist_w + bias
		if score > best_score:
			best_score = score
			best_key = k
	return best_key


func _steer_bot_toward(cart: CartPlayer, target: Vector3, throttle_scale: float,
		use_boost: bool, use_drift: bool) -> void:
	var local: Vector3 = cart.to_local(Vector3(target.x, cart.global_position.y, target.z))
	if not local.is_finite():
		cart.set_ai_controls(0.0, 0.0, 0.0)
		return
	var angle: float = atan2(-local.x, -local.z)
	var steer: float = clampf(angle * 2.35, -1.0, 1.0)
	var brake: float = 0.35 if absf(angle) > 2.1 and cart.velocity.length() > 10.0 else 0.0
	var throttle: float = throttle_scale if brake <= 0.01 else 0.25
	cart.set_ai_controls(throttle, brake, steer, use_boost, use_drift)


# ==========================================================================
# Visual Effects & Audio
# ==========================================================================

func _process(delta: float) -> void:
	_visual_time += delta
	_tick_wave_visuals(delta)
	_tick_shield_visuals(delta)
	_tick_spectator_camera(delta)

	if _toast_timer > 0.0:
		_toast_timer = maxf(_toast_timer - delta, 0.0)
		if _toast_timer <= 0.0 and _toast_panel != null:
			_toast_panel.visible = false

	_refresh_hud_frame()


func _tick_shield_visuals(delta: float) -> void:
	for raw_key: Variant in _contestants.keys():
		var entry: Dictionary = _contestants[int(raw_key)]
		var st: float = float(entry.get("slam_timer", 0.0))
		if st <= 0.0:
			continue
		var shield: Node3D = entry.get("shield_node") as Node3D
		var ring: MeshInstance3D = entry.get("ring_node") as MeshInstance3D
		var mat: StandardMaterial3D = entry.get("shield_mat") as StandardMaterial3D
		if shield != null and is_instance_valid(shield):
			var pulse: float = 1.0 + 0.12 * sin(_visual_time * 28.0)
			shield.scale = Vector3.ONE * pulse
		if ring != null and is_instance_valid(ring):
			ring.rotate_y(delta * 9.5)
		if mat != null:
			var ratio: float = clampf(st / SLAM_DURATION, 0.0, 1.0)
			mat.albedo_color = Color(1.0, 0.66, 0.16, 0.20 + 0.42 * ratio)


func _tick_spectator_camera(delta: float) -> void:
	if not _spectator_active or _spectator_cam == null:
		return
	var alive_keys: Array[int] = _alive_contestant_keys()
	var center := Vector3.ZERO
	var count: int = 0
	for k: int in alive_keys:
		var c: CartPlayer = _contestants[k].get("cart") as CartPlayer
		if c != null and is_instance_valid(c):
			center += c.global_position
			count += 1
	if count > 0:
		center /= float(count)
	_spectator_focus = _spectator_focus.lerp(center, 1.0 - exp(-4.5 * delta))
	_spectator_angle += delta * 0.34
	var eye := _spectator_focus + Vector3(
		cos(_spectator_angle) * 25.0, 15.5, sin(_spectator_angle) * 25.0)
	_spectator_cam.look_at_from_position(eye, _spectator_focus + Vector3.UP * 0.8, Vector3.UP)
	if _spectator_label != null:
		_spectator_label.text = "ELIMINATED  ·  SPECTATING (%d ALIVE)" % maxi(count, 1)


func _spawn_hit_burst(pos: Vector3, is_slam: bool) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "HitBurst"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.85 if is_slam else 0.68
	torus.rings = 20
	torus.ring_segments = 6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.72, 0.18, 0.90) if is_slam else Color(1.0, 0.92, 0.55, 0.75)
	ring.material_override = mat
	ring.position = pos
	ring.scale = Vector3(0.6, 0.08, 0.6)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

	var end_s: float = 4.2 if is_slam else 2.4
	var tw: Tween = create_tween()
	tw.tween_property(ring, "scale", Vector3(end_s, 0.08, end_s), 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.28)
	tw.tween_callback(ring.queue_free)


func _spawn_ko_burst(pos: Vector3) -> void:
	var primary := Color("ff6b1a") if _arena_id == "ko_foundry" \
		else (Color("5ce1ff") if _arena_id == "ko_iceberg" else UiPalette.YELLOW)
	var secondary := Color("ffd438") if _arena_id == "ko_foundry" \
		else (Color("f0fbff") if _arena_id == "ko_iceberg" else UiPalette.RED)

	var holder := Node3D.new()
	holder.name = "KoSplashBurst"
	holder.position = pos
	add_child(holder)

	var plume_mat := StandardMaterial3D.new()
	plume_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plume_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plume_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	plume_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	plume_mat.albedo_color = Color(primary.r, primary.g, primary.b, 0.88)

	var column := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6
	cyl.bottom_radius = 2.4
	cyl.height = 9.5
	cyl.radial_segments = 14
	column.mesh = cyl
	column.position = Vector3(0.0, 3.8, 0.0)
	column.material_override = plume_mat
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(column)

	var wave := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.1
	torus.outer_radius = 1.9
	torus.rings = 24
	torus.ring_segments = 6
	wave.mesh = torus
	wave.scale = Vector3(0.8, 0.1, 0.8)
	wave.material_override = plume_mat
	wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(wave)

	var shard_mesh := BoxMesh.new()
	shard_mesh.size = Vector3(0.55, 0.55, 0.55)
	var shard_mat := StandardMaterial3D.new()
	shard_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shard_mat.albedo_color = secondary

	var tw: Tween = create_tween()
	tw.tween_property(column, "scale", Vector3(1.65, 1.45, 1.65), 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(wave, "scale", Vector3(4.8, 0.1, 4.8), 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(plume_mat, "albedo_color:a", 0.0, 0.62)

	for i: int in 8:
		var ang: float = TAU * float(i) / 8.0
		var shard := MeshInstance3D.new()
		shard.mesh = shard_mesh
		shard.material_override = shard_mat
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(shard)
		var peak := Vector3(cos(ang) * 4.5, 5.2 + float(i % 3) * 1.4, sin(ang) * 4.5)
		tw.parallel().tween_property(shard, "position", peak, 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(shard, "scale", Vector3.ONE * 0.05, 0.60)

	tw.tween_callback(holder.queue_free)


func _pop_world_text(text: String, world_pos: Vector3, colour: Color,
		font_px: int) -> void:
	var pop := Label3D.new()
	pop.name = "KoPop3D"
	pop.text = text
	pop.font = TITLE_FONT
	pop.font_size = font_px
	pop.pixel_size = 0.0095
	pop.outline_size = 15
	pop.outline_modulate = UiPalette.OUTLINE
	pop.modulate = colour
	pop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pop.no_depth_test = true
	pop.position = world_pos
	add_child(pop)
	var tw: Tween = create_tween()
	tw.tween_property(pop, "position:y", world_pos.y + 2.4, 0.78)
	tw.parallel().tween_property(pop, "modulate:a", 0.0, 0.78)
	tw.tween_callback(pop.queue_free)


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


# ==========================================================================
# Slop-Slash Comic-Arcade HUD, Smash Fighter Damage Plates & Result Card
# ==========================================================================

func _empty_box(pad_l: float = 0.0, pad_t: float = 0.0,
		pad_r: float = 0.0, pad_b: float = 0.0) -> StyleBoxEmpty:
	var st := StyleBoxEmpty.new()
	st.content_margin_left = pad_l
	st.content_margin_top = pad_t
	st.content_margin_right = pad_r
	st.content_margin_bottom = pad_b
	return st


func _attach_ko_slash(host: Control, skew: float, fill: Color,
		border: Color = UiPalette.INK, border_w: float = 3.5,
		shadow := Vector2(4.0, 5.0)) -> _KoSlashPlate:
	var plate := _KoSlashPlate.new()
	plate.name = "SlashPlate"
	plate.skew_px = skew
	plate.fill_color = fill
	plate.border_color = border
	plate.border_width = minf(border_w, 1.5)
	plate.shadow_offset = shadow * 0.35
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(plate)
	host.move_child(plate, 0)
	return plate


func _build_hud() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 15
	add_child(_canvas)

	_hud_root = Control.new()
	_hud_root.name = "KnockoutHudRoot"
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.theme = UI_THEME
	_canvas.add_child(_hud_root)

	# 1. Top-Center Skewed Comic Arcade Header Slash (ROUND + 00:55 + ALIVE + SLAM!)
	_top_bar = PanelContainer.new()
	_top_bar.name = "KnockoutTopBar"
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.anchor_left = 0.5
	_top_bar.anchor_right = 0.5
	_top_bar.offset_left = -TOP_BAR_WIDTH * 0.5
	_top_bar.offset_right = TOP_BAR_WIDTH * 0.5
	_top_bar.offset_top = TOP_BAR_TOP
	_top_bar.offset_bottom = TOP_BAR_TOP + TOP_BAR_HEIGHT
	_top_bar.add_theme_stylebox_override("panel", _empty_box(18.0, 4.0, 20.0, 8.0))
	_top_bar_plate = _attach_ko_slash(
		_top_bar, 14.0, UiPalette.INK, UiPalette.CREAM, 3.5, Vector2(4.0, 5.0))
	_top_bar_plate.accent_width = 0.0
	_hud_root.add_child(_top_bar)

	var top_row := HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_theme_constant_override("separation", 8)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(top_row)

	# Left cluster: ROUND 1/3 + ALIVE count (all LuckiestGuy + thick ink outline)
	var round_col := VBoxContainer.new()
	round_col.alignment = BoxContainer.ALIGNMENT_CENTER
	round_col.add_theme_constant_override("separation", 0)
	round_col.custom_minimum_size = Vector2(106.0, 0.0)
	round_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(round_col)

	_round_label = _ui_label("ROUND 1/3", 15, UiPalette.YELLOW, 6)
	_round_label.clip_text = true
	round_col.add_child(_round_label)

	_alive_hud_label = _ui_label("4 ALIVE", 12, UiPalette.CYAN, 5)
	_alive_hud_label.clip_text = true
	round_col.add_child(_alive_hud_label)

	# Hidden arena label preserved for _load_arena() contract safety.
	_arena_label = _ui_label(str(_arena_data.get("name", "SKYTOP HELIPAD")), 10, UiPalette.CREAM, 4)
	_arena_label.visible = false
	round_col.add_child(_arena_label)

	# Center skewed #ffd22e yellow clock tag ("00:55" in #1e1b3a LuckiestGuy)
	var clock_panel := PanelContainer.new()
	clock_panel.custom_minimum_size = Vector2(96.0, 38.0)
	clock_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_panel.add_theme_stylebox_override("panel", _empty_box(12.0, 2.0, 14.0, 5.0))
	_clock_hud_plate = _attach_ko_slash(
		clock_panel, 10.0, UiPalette.YELLOW, UiPalette.INK, 3.5, Vector2(3.0, 4.0))
	top_row.add_child(clock_panel)

	_clock_hud_label = _ui_label("00:55", 22, UiPalette.INK, 0, false)
	_clock_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_hud_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clock_panel.add_child(_clock_hud_label)

	# Hidden fallback damage refs (live % counters now shine on Smash Fighter Plates!)
	_damage_badge = PanelContainer.new()
	_damage_badge.visible = false
	_damage_value_label = _ui_label("0%", 20, Color.WHITE, 6)
	_damage_badge.add_child(_damage_value_label)
	top_row.add_child(_damage_badge)

	# Right cluster kept hidden in top bar (now shines in the bottom-center Action Dock!)
	var slam_col := VBoxContainer.new()
	slam_col.visible = false
	slam_col.alignment = BoxContainer.ALIGNMENT_CENTER
	slam_col.add_theme_constant_override("separation", 2)
	slam_col.custom_minimum_size = Vector2(114.0, 0.0)
	slam_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(slam_col)

	_slam_status_label = _ui_label("SLAM [E]", 12, UiPalette.YELLOW, 5)
	_slam_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slam_status_label.clip_text = true
	slam_col.add_child(_slam_status_label)

	_slam_slash_bar = _KoSlamSlashBar.new()
	_slam_slash_bar.custom_minimum_size = Vector2(SLAM_BAR_INNER_WIDTH, 14.0)
	slam_col.add_child(_slam_slash_bar)

	# 2. Top-Left Skewed Comic Score Slashes (zero outer box, preserves fits_960!)
	_leaderboard_panel = PanelContainer.new()
	_leaderboard_panel.name = "LeaderboardPanel"
	_leaderboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_leaderboard_panel.offset_left = LEADERBOARD_LEFT
	_leaderboard_panel.offset_top = LEADERBOARD_TOP
	_leaderboard_panel.offset_right = LEADERBOARD_LEFT + LEADERBOARD_WIDTH
	_leaderboard_panel.offset_bottom = LEADERBOARD_TOP + 48.0
	_leaderboard_panel.add_theme_stylebox_override("panel", _empty_box())
	_hud_root.add_child(_leaderboard_panel)

	_leaderboard_rows = VBoxContainer.new()
	_leaderboard_rows.add_theme_constant_override("separation", 3)
	_leaderboard_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_leaderboard_panel.add_child(_leaderboard_rows)

	# 3. Legacy multi-fighter bottom strip hidden in favor of clean YOUR DAMAGE + [E] SLAM Dock!
	_fighter_bar = HBoxContainer.new()
	_fighter_bar.name = "SmashFighterBar"
	_fighter_bar.visible = false
	_fighter_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_fighter_bar)

	# Dedicated Bottom-Center Player Combat & [E] Slam Recharge Dock
	var AbilityDockRes := preload("res://scripts/ui/ability_dock.gd")
	_action_dock = AbilityDockRes.new()
	_action_dock.name = "KnockoutActionDock"
	_action_dock.set("show_damage", true)
	_action_dock.set("show_ability", true)
	_action_dock.set("key_text", "E")
	_action_dock.set("ability_title", "SLAM READY!")
	_action_dock.set("controls_hint", "WASD DRIVE  ·  SPACE DRIFT  ·  SHIFT BOOST  ·  E SLAM")
	_hud_root.add_child(_action_dock)

	# 4. Upper-Center Skewed KO & Hazard Warning Slash
	_toast_panel = PanelContainer.new()
	_toast_panel.name = "KoToastPanel"
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.offset_left = -TOAST_WIDTH * 0.5
	_toast_panel.offset_right = TOAST_WIDTH * 0.5
	_toast_panel.offset_top = TOP_BAR_TOP + TOP_BAR_HEIGHT + 8.0
	_toast_panel.offset_bottom = TOP_BAR_TOP + TOP_BAR_HEIGHT + 8.0 + TOAST_HEIGHT
	_toast_panel.add_theme_stylebox_override("panel", _empty_box(18.0, 4.0, 20.0, 8.0))
	_toast_plate = _attach_ko_slash(
		_toast_panel, 12.0, UiPalette.INK, UiPalette.YELLOW, 3.5, Vector2(4.0, 5.0))
	_toast_plate.accent_width = 0.0
	_toast_panel.visible = false
	_hud_root.add_child(_toast_panel)

	_toast_label = _ui_label("", 17, UiPalette.YELLOW, 6)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast_label.clip_text = true
	_toast_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toast_panel.add_child(_toast_label)

	# 5. Spectator Status Slash (sits cleanly above the Action Dock)
	_spectator_pill = PanelContainer.new()
	_spectator_pill.name = "SpectatorPill"
	_spectator_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spectator_pill.anchor_left = 0.5
	_spectator_pill.anchor_right = 0.5
	_spectator_pill.anchor_top = 1.0
	_spectator_pill.anchor_bottom = 1.0
	_spectator_pill.offset_left = -168.0
	_spectator_pill.offset_right = 168.0
	_spectator_pill.offset_top = -148.0
	_spectator_pill.offset_bottom = -110.0
	_spectator_pill.add_theme_stylebox_override("panel", _empty_box(18.0, 4.0, 20.0, 7.0))
	_spectator_plate = _attach_ko_slash(
		_spectator_pill, 12.0, UiPalette.INK, UiPalette.CYAN, 3.5, Vector2(4.0, 5.0))
	_spectator_plate.accent_width = 0.0
	_spectator_pill.visible = false
	_hud_root.add_child(_spectator_pill)

	_spectator_label = _ui_label("ELIMINATED · SPECTATING", 14, UiPalette.CYAN, 6)
	_spectator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectator_label.clip_text = true
	_spectator_pill.add_child(_spectator_label)

	# 6. Center Countdown Label & Skewed Round Intermission Banner
	_countdown_label = _ui_label("3", 104, UiPalette.YELLOW, 12)
	_countdown_label.anchor_left = 0.5
	_countdown_label.anchor_right = 0.5
	_countdown_label.anchor_top = 0.5
	_countdown_label.anchor_bottom = 0.5
	_countdown_label.offset_left = -220.0
	_countdown_label.offset_right = 220.0
	_countdown_label.offset_top = -64.0
	_countdown_label.offset_bottom = 64.0
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud_root.add_child(_countdown_label)

	_intermission_panel = PanelContainer.new()
	_intermission_panel.name = "IntermissionBanner"
	_intermission_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intermission_panel.anchor_left = 0.5
	_intermission_panel.anchor_right = 0.5
	_intermission_panel.anchor_top = 0.5
	_intermission_panel.anchor_bottom = 0.5
	_intermission_panel.offset_left = -236.0
	_intermission_panel.offset_right = 236.0
	_intermission_panel.offset_top = -74.0
	_intermission_panel.offset_bottom = 74.0
	_intermission_panel.add_theme_stylebox_override("panel", _empty_box(24.0, 14.0, 26.0, 18.0))
	_intermission_plate = _attach_ko_slash(
		_intermission_panel, 14.0, UiPalette.INK, UiPalette.YELLOW, 4.0, Vector2(5.0, 6.0))
	_intermission_plate.accent_color = UiPalette.YELLOW
	_intermission_plate.accent_width = 16.0
	_intermission_panel.visible = false
	_hud_root.add_child(_intermission_panel)

	var inter_col := VBoxContainer.new()
	inter_col.alignment = BoxContainer.ALIGNMENT_CENTER
	inter_col.add_theme_constant_override("separation", 6)
	inter_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intermission_panel.add_child(inter_col)

	_intermission_title = _ui_label("ROUND 1 COMPLETE", 24, UiPalette.YELLOW, 7)
	_intermission_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intermission_title.clip_text = true
	inter_col.add_child(_intermission_title)

	_intermission_sub = _ui_label("", 13, UiPalette.CREAM, 5)
	_intermission_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intermission_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inter_col.add_child(_intermission_sub)


func _build_result_card() -> void:
	_result_root = Control.new()
	_result_root.name = "ResultCard"
	_result_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_root.visible = false
	_result_root.add_to_group("nav_scope")
	_hud_root.add_child(_result_root)

	var pause_menu: Control = get_node_or_null("PauseMenu/Root") as Control
	if pause_menu != null and not pause_menu.visibility_changed.is_connected(_on_pause_visibility_changed):
		pause_menu.visibility_changed.connect(_on_pause_visibility_changed)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.08, 0.18, 0.60)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_root.add_child(center)

	_result_panel = PanelContainer.new()
	_result_panel.name = "ResultPanel"
	_result_panel.custom_minimum_size = Vector2(520.0, 0.0)
	_result_panel.add_theme_stylebox_override("panel",
		UiKit.slanted_panel(Color(0.056, 0.068, 0.156, 0.95),
			Color(0.24, 0.84, 0.96, 0.56), 0.055, 4, 6, 34.0, 26.0))
	center.add_child(_result_panel)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	_result_panel.add_child(body)

	var banner := PanelContainer.new()
	var banner_style := _card_style(UiPalette.YELLOW, UiPalette.OUTLINE, 3, 5)
	banner_style.skew = Vector2(0.14, 0.0)
	banner_style.content_margin_left = 22.0
	banner_style.content_margin_right = 22.0
	banner_style.content_margin_top = 12.0
	banner_style.content_margin_bottom = 12.0
	banner.add_theme_stylebox_override("panel", banner_style)
	body.add_child(banner)

	_result_title = _ui_label("KNOCKOUT CHAMPION!", 28, UiPalette.INK, 0)
	_result_title.theme_type_variation = &"TitleLabel"
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(_result_title)

	_result_subtitle = _ui_label("", 14, UiPalette.CYAN, 0)
	_result_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_result_subtitle)

	_result_rows = VBoxContainer.new()
	_result_rows.add_theme_constant_override("separation", 8)
	body.add_child(_result_rows)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", UiKit.SPACING)
	body.add_child(actions)

	if not _multiplayer or _is_host:
		_result_play_again = _candy_button("PLAY AGAIN", UiPalette.YELLOW, 48.0, 18)
		_result_play_again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_result_play_again.pressed.connect(_on_play_again)
		actions.add_child(_result_play_again)

	var back_text: String = "BACK TO LOBBY" if _multiplayer else "BACK TO MODES"
	_result_back = _candy_button(back_text,
		UiPalette.CYAN if (not _multiplayer or _is_host) else UiPalette.YELLOW, 48.0, 18)
	_result_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_back.pressed.connect(_on_back_pressed)
	actions.add_child(_result_back)


func _show_result_card() -> void:
	if _result_root == null:
		return
	var ranked: Array[Dictionary] = _ranked_contestants()
	var champ_name: String = str(ranked[0].get("name", "PLAYER")) if not ranked.is_empty() else "PLAYER"
	var champ_key: int = int(ranked[0].get("key", 0)) if not ranked.is_empty() else 0
	if champ_key == _local_key():
		_result_title.text = "VICTORY!  ·  %s" % champ_name
	else:
		_result_title.text = "WINNER: %s" % champ_name
	_result_subtitle.text = "%s  ·  %d ROUNDS COMPLETE" % [
		str(_arena_data.get("name", "SKYTOP HELIPAD")), _total_rounds]

	for child: Node in _result_rows.get_children():
		_result_rows.remove_child(child)
		child.queue_free()

	var max_rows: int = mini(ranked.size(), MAX_CONTESTANTS)
	for i: int in max_rows:
		var c: Dictionary = ranked[i]
		var is_me: bool = int(c.get("key", 0)) == _local_key()
		var row_panel := PanelContainer.new()
		var bg: Color = Color(0.14, 0.26, 0.42, 0.94) if is_me else Color(0.095, 0.112, 0.228, 0.88)
		var bcol: Color = UiPalette.YELLOW if i == 0 else (UiPalette.CYAN if is_me else Color(1.0, 1.0, 1.0, 0.10))
		var r_style := _card_style(bg, bcol, 2 if (i == 0 or is_me) else 1, 5)
		r_style.skew = Vector2(0.14, 0.0)
		r_style.content_margin_left = 18.0
		r_style.content_margin_right = 18.0
		r_style.content_margin_top = 8.0
		r_style.content_margin_bottom = 8.0
		row_panel.add_theme_stylebox_override("panel", r_style)
		_result_rows.add_child(row_panel)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row_panel.add_child(row)

		var rank_lbl := _ui_label("#%d" % (i + 1), 15, UiPalette.YELLOW if i == 0 else UiPalette.CYAN, 0)
		rank_lbl.theme_type_variation = &"TitleLabel"
		rank_lbl.custom_minimum_size = Vector2(34.0, 0.0)
		row.add_child(rank_lbl)

		var name_lbl := _ui_label(str(c.get("name", "PLAYER")), 15,
			UiPalette.YELLOW if is_me else UiPalette.CREAM, 0)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_lbl)

		var ko_lbl := _ui_label("%d KO" % int(c.get("kos", 0)), 14, UiPalette.CYAN, 0)
		ko_lbl.custom_minimum_size = Vector2(58.0, 0.0)
		ko_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(ko_lbl)

		var pts_lbl := _ui_label("%d PTS" % int(c.get("score", 0)), 16, UiPalette.YELLOW, 0)
		pts_lbl.theme_type_variation = &"TitleLabel"
		pts_lbl.custom_minimum_size = Vector2(72.0, 0.0)
		pts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pts_lbl)

	_result_root.visible = true
	_result_root.modulate.a = 0.0
	var fade: Tween = create_tween()
	fade.tween_property(_result_root, "modulate:a", 1.0, 0.24) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	CursorController.set_menu_mode(true)
	if _is_pause_open():
		_result_root.remove_from_group("nav_scope")
	else:
		if not _result_root.is_in_group("nav_scope"):
			_result_root.add_to_group("nav_scope")
		MenuNav.refresh()
		var focus_btn: Button = _result_play_again if _result_play_again != null else _result_back
		if focus_btn != null:
			MenuNav.focus(focus_btn)
	_play_one_shot(FINISH_FANFARE, -6.5, 1.0)


func _on_pause_visibility_changed() -> void:
	if _result_root == null or not _result_root.visible:
		return
	var pause_open: bool = _is_pause_open()
	if pause_open:
		_result_root.remove_from_group("nav_scope")
	elif not _result_root.is_in_group("nav_scope"):
		_result_root.add_to_group("nav_scope")
	MenuNav.refresh()
	if not pause_open:
		var focus_btn: Button = _result_play_again if _result_play_again != null else _result_back
		if focus_btn != null:
			MenuNav.focus(focus_btn)


func _on_play_again() -> void:
	if _multiplayer:
		if _is_host:
			Network.start_game(SCENE_PATH, GameSettings.GAME_MINIGAMES)
		return
	SceneLoader.go_to(SCENE_PATH, "KNOCKOUT", "BUMPER ROYALE")


func _on_back_pressed() -> void:
	if _multiplayer:
		Network.return_to_lobby_keep_session()
	else:
		SceneLoader.go_to(MINIGAMES_MENU, "GAME MODES", "PICK AN EVENT")


func _refresh_hud_frame() -> void:
	if _round_label == null:
		return
	var whole_s: int = maxi(int(ceil(_round_remaining)), 0)
	_round_label.text = "ROUND %d/%d" % [_round_index, _total_rounds]
	if _clock_hud_label != null:
		_clock_hud_label.text = "%02d:%02d" % [whole_s / 60, whole_s % 60]
		var urgent: bool = whole_s <= 10 and (whole_s % 2 == 1)
		if _clock_hud_plate != null:
			_clock_hud_plate.fill_color = UiPalette.PINK if urgent else UiPalette.YELLOW
			_clock_hud_plate.queue_redraw()
		_clock_hud_label.add_theme_constant_override("outline_size", 5 if urgent else 0)
		_clock_hud_label.add_theme_color_override("font_color",
			UiPalette.CREAM if urgent else UiPalette.INK)
	if _alive_hud_label != null:
		_alive_hud_label.text = "%d ALIVE" % _alive_contestant_keys().size()

	var local: Dictionary = _contestants.get(_local_key(), {}) as Dictionary
	var pct: float = float(local.get("damage_pct", 0.0))
	var alive: bool = bool(local.get("alive", true))
	var col: Color = _damage_color(pct)
	if _damage_value_label != null:
		_damage_value_label.text = "%d%%" % int(round(pct)) if alive else "OUT"
		_damage_value_label.add_theme_color_override("font_color", col if alive else UiPalette.RED)

	var slam_cd: float = float(local.get("slam_cooldown", 0.0))
	var ready_ratio: float = clampf(1.0 - slam_cd / SLAM_COOLDOWN, 0.0, 1.0)
	if _slam_slash_bar != null:
		_slam_slash_bar.ratio = ready_ratio
		_slam_slash_bar.queue_redraw()
	if _slam_status_label != null:
		if not alive:
			_slam_status_label.text = "SPECTATING"
			_slam_status_label.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
		elif ready_ratio >= 0.999:
			_slam_status_label.text = "SLAM! [E]"
			_slam_status_label.add_theme_color_override("font_color", UiPalette.YELLOW)
		else:
			_slam_status_label.text = "SLAM %.1fS" % slam_cd
			_slam_status_label.add_theme_color_override("font_color", UiPalette.CYAN)

	if _action_dock != null:
		_action_dock.set("damage_text", "%d%%" % int(round(pct)) if alive else "OUT")
		_action_dock.set("damage_color", col if alive else UiPalette.RED)
		_action_dock.set("ability_ratio", ready_ratio if alive else 0.0)
		if not alive:
			_action_dock.set("ability_title", "SPECTATING")
			_action_dock.set("ability_color", UiPalette.CYAN)
		elif ready_ratio >= 0.999:
			_action_dock.set("ability_title", "SLAM READY!")
			_action_dock.set("ability_color", UiPalette.YELLOW)
		else:
			_action_dock.set("ability_title", "RECHARGING %.1fS" % slam_cd)
			_action_dock.set("ability_color", UiPalette.CYAN)
		_action_dock.queue_redraw()

	_refresh_leaderboard_pills()
	_refresh_smash_fighter_plates()
	_layout_hud()


func _refresh_hud_immediate() -> void:
	_refresh_hud_frame()


func _refresh_leaderboard_pills() -> void:
	if _leaderboard_rows == null:
		return
	var ranked: Array[Dictionary] = _ranked_contestants()
	var count: int = mini(ranked.size(), MAX_CONTESTANTS)
	while _leaderboard_cache.size() < count:
		var pill := PanelContainer.new()
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.custom_minimum_size = Vector2(0.0, 26.0)
		pill.add_theme_stylebox_override("panel", _empty_box(20.0, 2.0, 18.0, 4.0))
		var plate := _attach_ko_slash(
			pill, 9.0, Color(0.118, 0.106, 0.227, 0.88), UiPalette.INK, 2.5, Vector2(2.5, 3.0))
		plate.draw_sheen = false

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 5)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(hbox)

		var nm := _ui_label("PLAYER", 11, UiPalette.CREAM, 4, false)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hbox.add_child(nm)

		var pt := _ui_label("0P", 11, UiPalette.YELLOW, 4, false)
		pt.custom_minimum_size = Vector2(30.0, 0.0)
		pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(pt)

		_leaderboard_rows.add_child(pill)
		_leaderboard_cache.append({
			"pill": pill, "plate": plate, "name": nm, "pts": pt,
		})

	for idx: int in _leaderboard_cache.size():
		var slot: Dictionary = _leaderboard_cache[idx]
		var pill: PanelContainer = slot["pill"] as PanelContainer
		if idx >= count:
			pill.visible = false
			continue
		pill.visible = true
		var c: Dictionary = ranked[idx]
		var alive: bool = bool(c.get("alive", true))
		var is_me: bool = int(c.get("key", 0)) == _local_key()
		var fighter_col: Color = (c.get("color", UiPalette.YELLOW) as Color)
		var plate: _KoSlashPlate = slot["plate"] as _KoSlashPlate
		plate.fill_color = UiPalette.YELLOW if is_me else Color(0.118, 0.106, 0.227, 0.88)
		plate.accent_color = UiPalette.PINK if is_me else (fighter_col if alive else UiPalette.MUTED)
		plate.accent_width = 10.0
		plate.queue_redraw()

		var nm: Label = slot["name"] as Label
		nm.text = "%d. %s" % [idx + 1, str(c.get("name", "PLAYER"))]
		nm.add_theme_constant_override("outline_size", 0 if is_me else 4)
		nm.add_theme_color_override("font_color",
			UiPalette.INK if is_me else (UiPalette.CREAM if alive else UiPalette.TEXT_DIM))

		var pt: Label = slot["pts"] as Label
		pt.text = "%dP" % int(c.get("score", 0))
		pt.add_theme_constant_override("outline_size", 0 if is_me else 4)
		pt.add_theme_color_override("font_color",
			UiPalette.INK if is_me else UiPalette.YELLOW)


func _fighter_display_list(max_cards: int) -> Array[Dictionary]:
	## Local fighter always anchors card 0, followed by alive/top-ranked rivals.
	var out: Array[Dictionary] = []
	var my_k: int = _local_key()
	if _contestants.has(my_k):
		out.append(_contestants[my_k] as Dictionary)
	for entry: Dictionary in _ranked_contestants():
		if out.size() >= max_cards:
			break
		if int(entry.get("key", 0)) == my_k:
			continue
		out.append(entry)
	return out


func _refresh_smash_fighter_plates() -> void:
	if _fighter_bar == null:
		return
	var vp: Viewport = get_viewport()
	var view: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1280.0, 720.0)
	if view.x <= 1.0:
		view = Vector2(1280.0, 720.0)
	var lane_w: float = maxf((view.x - 246.0) - 324.0, 320.0)
	var max_cards: int = 3 if lane_w < 480.0 else (4 if lane_w < 680.0 else 5)
	var shown: Array[Dictionary] = _fighter_display_list(max_cards)
	var count: int = shown.size()
	var gap: float = 8.0
	var card_w: float = clampf(
		floor((lane_w - gap * float(maxi(count - 1, 0))) / float(maxi(count, 1))),
		92.0, 160.0)
	var pct_font: int = 34 if card_w < 138.0 else 37

	while _fighter_cards_cache.size() < count:
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.custom_minimum_size = Vector2(card_w, 72.0)
		card.add_theme_stylebox_override("panel", _empty_box(18.0, 3.0, 12.0, 6.0))

		var plate := _SmashFighterPlate.new()
		plate.name = "SmashPlate"
		plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.add_child(plate)
		card.move_child(plate, 0)

		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(col)

		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 4)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(head)

		var nm := _ui_label("FIGHTER", 13, UiPalette.CREAM, 5, false)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		head.add_child(nm)

		var tag := _ui_label("YOU", 11, UiPalette.YELLOW, 4, false)
		head.add_child(tag)

		var pct_lbl := _ui_label("0%", pct_font, UiPalette.CREAM, 8, true)
		pct_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pct_lbl.clip_text = true
		col.add_child(pct_lbl)

		_fighter_bar.add_child(card)
		_fighter_cards_cache.append({
			"card": card, "plate": plate, "name": nm, "tag": tag, "pct": pct_lbl,
		})

	_local_fighter_card = null
	var my_key: int = _local_key()
	for i in _fighter_cards_cache.size():
		var slot: Dictionary = _fighter_cards_cache[i]
		var card: PanelContainer = slot["card"] as PanelContainer
		if i >= count:
			card.visible = false
			continue
		card.visible = true
		card.custom_minimum_size = Vector2(card_w, 72.0)

		var entry: Dictionary = shown[i]
		var is_me: bool = int(entry.get("key", 0)) == my_key
		if is_me:
			_local_fighter_card = card
		var alive: bool = bool(entry.get("alive", true))
		var pct: float = float(entry.get("damage_pct", 0.0))
		var tint: Color = entry.get("color", UiPalette.CYAN) as Color

		var plate: _SmashFighterPlate = slot["plate"] as _SmashFighterPlate
		plate.accent_color = UiPalette.YELLOW if is_me else tint
		plate.is_local = is_me
		plate.alive = alive
		plate.queue_redraw()

		var nm: Label = slot["name"] as Label
		nm.text = str(entry.get("name", "FIGHTER"))
		nm.add_theme_color_override("font_color",
			UiPalette.YELLOW if is_me else (UiPalette.CREAM if alive else UiPalette.TEXT_DIM))

		var tag: Label = slot["tag"] as Label
		var kos: int = int(entry.get("kos", 0))
		if is_me:
			tag.text = "YOU" if kos <= 0 else "YOU·%dKO" % kos
			tag.add_theme_color_override("font_color", UiPalette.YELLOW)
		else:
			tag.text = "%dKO" % kos if kos > 0 else "%dP" % int(entry.get("score", 0))
			tag.add_theme_color_override("font_color", UiPalette.CYAN)

		var pct_lbl: Label = slot["pct"] as Label
		pct_lbl.add_theme_font_size_override("font_size", pct_font)
		pct_lbl.text = "%d%%" % int(round(pct)) if alive else "KO!"
		pct_lbl.add_theme_color_override("font_color",
			_damage_color(pct) if alive else UiPalette.RED)


func _ranked_contestants() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for raw_key: Variant in _contestants.keys():
		list.append(_contestants[int(raw_key)] as Dictionary)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa: int = int(a.get("score", 0))
		var sb: int = int(b.get("score", 0))
		if sa != sb:
			return sa > sb
		var ka: int = int(a.get("kos", 0))
		var kb: int = int(b.get("kos", 0))
		if ka != kb:
			return ka > kb
		var aa: bool = bool(a.get("alive", false))
		var ab: bool = bool(b.get("alive", false))
		if aa != ab:
			return aa and not ab
		return float(a.get("damage_pct", 0.0)) < float(b.get("damage_pct", 0.0))
	)
	return list


func _layout_hud() -> void:
	var vp: Viewport = get_viewport()
	var view: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1280.0, 720.0)
	if view.x <= 1.0 or view.y <= 1.0:
		view = Vector2(1280.0, 720.0)
	if _top_bar != null:
		var min_top: Vector2 = _top_bar.get_combined_minimum_size()
		var w: float = maxf(TOP_BAR_WIDTH, min_top.x + 6.0)
		var h: float = maxf(TOP_BAR_HEIGHT, min_top.y)
		_top_bar.offset_left = -w * 0.5
		_top_bar.offset_right = w * 0.5
		_top_bar.offset_top = TOP_BAR_TOP
		_top_bar.offset_bottom = TOP_BAR_TOP + h
		if _toast_panel != null:
			var t_top: float = TOP_BAR_TOP + h + 8.0
			_toast_panel.offset_top = t_top
			_toast_panel.offset_bottom = t_top + maxf(
				TOAST_HEIGHT, _toast_panel.get_combined_minimum_size().y)
	if _leaderboard_panel != null:
		var lb_min: Vector2 = _leaderboard_panel.get_combined_minimum_size()
		_leaderboard_panel.offset_right = LEADERBOARD_LEFT + maxf(LEADERBOARD_WIDTH, lb_min.x)
		_leaderboard_panel.offset_bottom = LEADERBOARD_TOP + lb_min.y
	if _fighter_bar != null:
		var lane_l: float = 324.0
		var lane_r: float = maxf(view.x - 246.0, lane_l + 320.0)
		var f_min: Vector2 = _fighter_bar.get_combined_minimum_size()
		var f_h: float = maxf(74.0, f_min.y)
		_fighter_bar.offset_left = lane_l
		_fighter_bar.offset_right = maxf(lane_r, lane_l + f_min.x)
		_fighter_bar.offset_bottom = -10.0
		_fighter_bar.offset_top = -10.0 - f_h


func _hud_clips() -> bool:
	var vp: Viewport = get_viewport()
	var view: Vector2 = vp.get_visible_rect().size if vp != null else Vector2(1280.0, 720.0)
	if _hud_clips_for_rect(view):
		return true
	if _top_bar != null and _leaderboard_panel != null:
		if _top_bar.get_global_rect().intersects(_leaderboard_panel.get_global_rect()):
			return true
	return false


func _hud_clips_for_rect(view: Vector2) -> bool:
	var checks: Array[Control] = [_top_bar, _leaderboard_panel]
	if _fighter_bar != null and _fighter_bar.visible:
		checks.append(_fighter_bar)
	if _toast_panel != null and _toast_panel.visible:
		checks.append(_toast_panel)
	if _countdown_label != null and _countdown_label.visible:
		checks.append(_countdown_label)
	if _intermission_panel != null and _intermission_panel.visible:
		checks.append(_intermission_panel)
	if _result_panel != null and _result_root != null and _result_root.visible:
		checks.append(_result_panel)
	for ctrl: Control in checks:
		if ctrl == null or not is_instance_valid(ctrl):
			continue
		var rect: Rect2 = ctrl.get_global_rect()
		if rect.position.x < -0.5 or rect.position.y < -0.5 \
				or rect.end.x > view.x + 0.5 or rect.end.y > view.y + 0.5:
			return true
		var min_sz: Vector2 = ctrl.get_combined_minimum_size()
		if min_sz.x > rect.size.x + 0.5 or min_sz.y > rect.size.y + 0.5:
			return true
	return false


func _pulse_hud_damage() -> void:
	if _local_fighter_card != null:
		_pop_control(_local_fighter_card)


func _show_toast(text: String, duration: float, accent: Color = UiPalette.YELLOW) -> void:
	if _toast_panel == null or _toast_label == null:
		return
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", accent)
	if _toast_plate != null:
		_toast_plate.accent_color = accent
		_toast_plate.border_color = accent
		_toast_plate.queue_redraw()
	_toast_panel.visible = true
	_toast_timer = duration
	_layout_hud()


func _pop_control(ctrl: Control) -> void:
	if ctrl == null:
		return
	ctrl.pivot_offset = ctrl.size * 0.5
	ctrl.scale = Vector2.ONE * 1.16
	var tw: Tween = create_tween()
	tw.tween_property(ctrl, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _card_style(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(border_w)
	st.set_corner_radius_all(radius)
	st.anti_aliasing = true
	return st


func _ui_label(text: String, font_size: int, colour: Color,
		outline: int = 0, hard_shadow: Variant = null) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.theme_type_variation = &"TitleLabel"
	lbl.add_theme_font_override("font", BODY_FONT)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", colour)
	if outline > 0:
		lbl.add_theme_color_override("font_outline_color", UiPalette.INK)
		lbl.add_theme_constant_override("outline_size", mini(outline, 3))
	else:
		lbl.add_theme_constant_override("outline_size", 0)
	var use_shadow: bool = (outline >= 5) if hard_shadow == null else bool(hard_shadow)
	if use_shadow:
		lbl.add_theme_color_override("font_shadow_color", KO_TEXT_SHADOW)
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 2)
	else:
		lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
		lbl.add_theme_constant_override("shadow_offset_x", 0)
		lbl.add_theme_constant_override("shadow_offset_y", 0)
	return lbl


func _candy_button(text: String, fill: Color, height: float,
		font_size: int) -> Button:
	var btn := Button.new()
	btn.set_script(CANDY_BUTTON)
	btn.set("fill_color", fill)
	btn.text = text
	btn.custom_minimum_size = Vector2(0.0, height)
	btn.add_theme_font_size_override("font_size", font_size)
	return btn


# ==========================================================================
# Online Multiplayer Sync (`Network.is_session_active()`)
# ==========================================================================

func _setup_multiplayer() -> void:
	for peer_id: int in multiplayer.get_peers():
		_spawn_remote_peer(peer_id)
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not Network.names_changed.is_connected(_on_net_identity_changed):
		Network.names_changed.connect(_on_net_identity_changed)
	if not Network.tag_colors_changed.is_connected(_on_net_identity_changed):
		Network.tag_colors_changed.connect(_on_net_identity_changed)

	Network.notify_scene_ready(self, Network.KNOCKOUT_SCENE)
	if not _is_host and Network.is_scene_ready(1):
		rpc_id(1, "_net_knockout_ready", _arena_id, _chosen_vehicle_id())


func _on_peer_connected(peer_id: int) -> void:
	_spawn_remote_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if _contestants.has(peer_id):
		# A disconnected peer must count as eliminated, not vanish: erasing the
		# entry shrinks the field below two contestants and the round can never
		# conclude, leaving a ghost stalling it forever.
		var entry: Dictionary = _contestants[peer_id]
		if bool(entry.get("alive", false)):
			var gone_cart: CartPlayer = entry.get("cart") as CartPlayer
			var gone_pos: Vector3 = gone_cart.net_position \
				if (gone_cart != null and is_instance_valid(gone_cart) \
					and gone_cart.remote_mode) else Vector3(0.0, _ko_y, 0.0)
			_eliminate_contestant(peer_id, gone_pos)
			entry["cart"] = null
		var dead_cart: CartPlayer = entry.get("cart") as CartPlayer
		if dead_cart != null and is_instance_valid(dead_cart):
			dead_cart.queue_free()
			entry["cart"] = null
	_remote_carts.erase(peer_id)
	_peer_vehicles.erase(peer_id)
	_cart_relay_ms.erase(peer_id)
	_refresh_hud_immediate()
	if peer_id == 1 and not _is_host and _multiplayer \
			and (_phase == Phase.COUNTDOWN or _phase == Phase.BRAWL \
			or _phase == Phase.INTERMISSION):
		# Host (only round clock/collision/transition authority) is gone:
		# conclude locally from the current standings instead of idling in
		# COUNTDOWN/BRAWL/INTERMISSION forever with no results.
		_finish_match()


func _on_net_identity_changed() -> void:
	for raw_key: Variant in _contestants.keys():
		var key: int = int(raw_key)
		if key <= 0 or key == _local_key():
			continue
		var entry: Dictionary = _contestants[key]
		entry["name"] = Network.name_of(key)
		entry["color"] = Network.color_of(key)
		_refresh_3d_badge(entry, false)
	_refresh_hud_immediate()


func _spawn_remote_peer(peer_id: int) -> void:
	if peer_id <= 0 or peer_id == _local_key() or _remote_carts.has(peer_id):
		return
	var spawns: Array = _arena_data.get("spawns", []) as Array
	var slot: int = _contestants.size() % maxi(spawns.size(), 1)
	var spawn_xform := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 14.0))
	if not spawns.is_empty() and spawns[slot] is Transform3D:
		spawn_xform = spawns[slot] as Transform3D
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	cart.name = "Remote_%d" % peer_id
	cart.transform = spawn_xform
	add_child(cart)
	cart.setup_remote(peer_id)
	cart.net_position = spawn_xform.origin
	cart.net_yaw = spawn_xform.basis.get_euler().y
	cart.contact_enabled = true
	cart.collision_layer = CollisionLayers.GHOST
	var veh: String = str(_peer_vehicles.get(peer_id,
		Network.effective_vehicle_for(peer_id, "minigame")))
	cart.set_vehicle_id(veh, Network.effective_racer_color_for(peer_id))
	_remote_carts[peer_id] = cart
	_register_contestant(peer_id, Network.name_of(peer_id),
		Network.color_of(peer_id), cart, false, -1, true)
	_contestants[peer_id]["spawn_slot"] = slot
	if not _spectator_active and _cart != null:
		var chase_cam: Camera3D = _cart.get_node_or_null("CameraArm/Camera3D") as Camera3D
		if chase_cam != null:
			chase_cam.current = true


func _rpc_sender() -> int:
	return multiplayer.get_remote_sender_id() if multiplayer.multiplayer_peer != null else 0


func _net_tick(delta: float) -> void:
	if not _multiplayer or not Network.is_session_active():
		return
	if not _is_host and not _net_config_received and Network.is_scene_ready(1):
		_ready_retry_timer += delta
		if _ready_retry_timer >= 0.8:
			_ready_retry_timer = 0.0
			rpc_id(1, "_net_knockout_ready", _arena_id, _chosen_vehicle_id())
	var my_id: int = _local_key()
	var my_entry: Dictionary = _contestants.get(my_id, {}) as Dictionary
	if _cart != null and is_instance_valid(_cart) and bool(my_entry.get("alive", false)):
		_cart_sync_timer += delta
		if _cart_sync_timer >= CART_SYNC_INTERVAL:
			_cart_sync_timer = 0.0
			var stamp: int = Time.get_ticks_msec()
			if _is_host:
				_broadcast_cart_pose(my_id, _cart.global_position,
					_cart.rotation.y, stamp, _cart.velocity)
			elif Network.is_scene_ready(1):
				rpc_id(1, "_net_ko_cart_state", my_id, _cart.global_position,
					_cart.rotation.y, stamp, _cart.velocity)

	if not _is_host:
		return

	_bot_sync_timer += delta
	if _bot_sync_timer >= CART_SYNC_INTERVAL and not _bot_keys.is_empty():
		_bot_sync_timer = 0.0
		_broadcast_bot_poses()

	_damage_sync_timer += delta
	if _damage_sync_timer >= DAMAGE_SYNC_INTERVAL:
		_damage_sync_timer = 0.0
		_broadcast_damage_table()

	_clock_sync_timer += delta
	if _clock_sync_timer >= CLOCK_SYNC_INTERVAL:
		_clock_sync_timer = 0.0
		_broadcast_clock()


@rpc("any_peer", "reliable")
func _net_knockout_ready(arena_id: String, vehicle_id: String) -> void:
	var sender: int = _rpc_sender()
	if sender <= 1 or sender == _local_key() or not _is_host:
		return
	if arena_id.length() > 64 or vehicle_id.length() > 64:
		return
	Network.mark_peer_scene_ready(sender)
	_spawn_remote_peer(sender)
	var clean_veh: String = Network.effective_vehicle_for(sender, "minigame") \
		if Network.is_shared_vehicle_mode() else GameSettings.sanitize_vehicle_id(vehicle_id)
	_peer_vehicles[sender] = clean_veh
	var r_cart: CartPlayer = _remote_carts.get(sender) as CartPlayer
	if r_cart != null and is_instance_valid(r_cart):
		r_cart.set_vehicle_id(clean_veh, Network.effective_racer_color_for(sender))

	# Sync arena, bot count, round count & peer vehicles to the newly ready peer
	# and refresh peer vehicles on all ready peers.
	for peer_id: int in multiplayer.get_peers():
		if Network.is_scene_ready(peer_id):
			rpc_id(peer_id, "_net_knockout_config", _arena_id, _bot_keys.size(),
				_total_rounds, _peer_vehicles)

	_send_full_round_snapshot(sender)


@rpc("authority", "reliable")
func _net_knockout_config(arena_id: String, bot_count: int, total_rounds: int,
		peer_vehicles: Dictionary) -> void:
	if _is_host or not _multiplayer:
		return
	_net_config_received = true
	_total_rounds = clampi(total_rounds, 1, 9)
	var resolved: String = KnockoutMaps.resolve(arena_id)
	if resolved != _arena_id:
		_load_arena(resolved)

	var clamped_bots: int = clampi(bot_count, 0, MAX_CONTESTANTS - 1)
	if _bot_keys.size() != clamped_bots:
		for bk: int in _bot_keys:
			if _contestants.has(bk):
				var bc: CartPlayer = _contestants[bk].get("cart") as CartPlayer
				if bc != null and is_instance_valid(bc):
					bc.queue_free()
				_contestants.erase(bk)
		_bot_keys.clear()
		for idx: int in clamped_bots:
			_spawn_bot_contestant(idx, true)

	for raw_pid: Variant in peer_vehicles.keys():
		var pid: int = int(raw_pid)
		var vid: String = GameSettings.sanitize_vehicle_id(str(peer_vehicles[raw_pid]))
		_peer_vehicles[pid] = vid
		if pid != _local_key():
			_spawn_remote_peer(pid)
			var rc: CartPlayer = _remote_carts.get(pid) as CartPlayer
			if rc != null and is_instance_valid(rc):
				rc.set_vehicle_id(vid)


func _cart_idle_skip(peer_id: int, pos: Vector3, yaw: float, vel: Vector3) -> bool:
	if Vector2(vel.x, vel.z).length() >= CART_IDLE_SPEED:
		_cart_idle_ms[peer_id] = Time.get_ticks_msec()
		_cart_idle_pos[peer_id] = pos
		_cart_idle_yaw[peer_id] = yaw
		return false
	var now: int = Time.get_ticks_msec()
	var last_ms: int = int(_cart_idle_ms.get(peer_id, -100000))
	var last_pos: Vector3 = _cart_idle_pos.get(peer_id, pos)
	var last_yaw: float = float(_cart_idle_yaw.get(peer_id, yaw))
	if pos.distance_squared_to(last_pos) > 0.0004 or absf(angle_difference(last_yaw, yaw)) > 0.01:
		_cart_idle_ms[peer_id] = now
		_cart_idle_pos[peer_id] = pos
		_cart_idle_yaw[peer_id] = yaw
		return false
	if now - last_ms < int(CART_IDLE_INTERVAL * 1000.0):
		return true
	_cart_idle_ms[peer_id] = now
	_cart_idle_pos[peer_id] = pos
	_cart_idle_yaw[peer_id] = yaw
	return false


func _broadcast_cart_pose(peer_id: int, pos: Vector3, yaw: float,
		sent_ms: int, vel: Vector3) -> void:
	if _cart_idle_skip(peer_id, pos, yaw, vel):
		return
	for target: int in multiplayer.get_peers():
		if target != peer_id and Network.is_scene_ready(target):
			rpc_id(target, "_net_ko_cart_state", peer_id, pos, yaw, sent_ms, vel)


@rpc("any_peer", "unreliable_ordered")
func _net_ko_cart_state(peer_id: int, pos: Vector3, yaw: float,
		sent_ms: int, vel: Vector3 = Vector3.ZERO) -> void:
	var sender: int = _rpc_sender()
	if sender != 1 and peer_id != sender:
		return
	if not pos.is_finite() or not is_finite(yaw) or not vel.is_finite():
		return
	if pos.length_squared() > 5000.0 * 5000.0 or sent_ms < 0:
		return
	var cart: CartPlayer = _remote_carts.get(peer_id) as CartPlayer
	var entry: Dictionary = _contestants.get(peer_id, {}) as Dictionary
	if cart != null and is_instance_valid(cart) and cart.remote_mode \
			and bool(entry.get("alive", true)):
		var accepted: bool = cart.set_net_state(pos, yaw, sent_ms, vel)
		if _is_host and sender != 1 and accepted:
			var now_ms: int = Time.get_ticks_msec()
			if now_ms - int(_cart_relay_ms.get(peer_id, -1000)) >= 25:
				_cart_relay_ms[peer_id] = now_ms
				_broadcast_cart_pose(peer_id, pos, yaw, sent_ms, vel)


func _broadcast_bot_poses() -> void:
	var now: int = Time.get_ticks_msec()
	var all_idle: bool = true
	for bk: int in _bot_keys:
		var entry: Dictionary = _contestants.get(bk, {}) as Dictionary
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
	for bk: int in _bot_keys:
		var entry: Dictionary = _contestants.get(bk, {}) as Dictionary
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart == null or not is_instance_valid(cart):
			positions.append(Vector3.ZERO)
			yaws.append(0.0)
			velocities.append(Vector3.ZERO)
			continue
		positions.append(cart.global_position)
		yaws.append(cart.rotation.y)
		velocities.append(_safe_vel(cart.velocity))
	var stamp: int = Time.get_ticks_msec()
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_ko_bot_states", positions, yaws, velocities, stamp)


@rpc("authority", "unreliable_ordered")
func _net_ko_bot_states(positions: PackedVector3Array, yaws: PackedFloat32Array,
		velocities: PackedVector3Array, sent_ms: int) -> void:
	if _is_host or not _multiplayer:
		return
	var count: int = mini(positions.size(), _bot_keys.size())
	if yaws.size() < count or velocities.size() < count:
		return
	for i: int in count:
		var bk: int = _bot_keys[i]
		var entry: Dictionary = _contestants.get(bk, {}) as Dictionary
		if not bool(entry.get("alive", false)):
			continue
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		if cart != null and is_instance_valid(cart) and cart.remote_mode:
			cart.set_net_state(positions[i], yaws[i], sent_ms, velocities[i])


@rpc("any_peer", "reliable")
func _net_request_slam() -> void:
	if not _is_host or _phase != Phase.BRAWL:
		return
	var sender: int = _rpc_sender()
	if sender <= 1 or not _contestants.has(sender):
		return
	if _activate_slam(sender):
		_broadcast_slam(sender)


func _broadcast_slam(actor_key: int) -> void:
	var entry: Dictionary = _contestants.get(actor_key, {}) as Dictionary
	var dir: Vector3 = entry.get("slam_dir", Vector3.FORWARD) as Vector3
	for target: int in multiplayer.get_peers():
		if target != actor_key and Network.is_scene_ready(target):
			rpc_id(target, "_net_slam_activated", actor_key, dir)


@rpc("authority", "reliable")
func _net_slam_activated(actor_key: int, dir: Vector3) -> void:
	if _is_host or not _multiplayer or actor_key == _local_key():
		return
	if not dir.is_finite():
		dir = Vector3.FORWARD
	_activate_slam(actor_key, dir)


@rpc("authority", "reliable")
func _net_apply_knockback(impulse: Vector3, new_damage_pct: float,
		attacker_key: int, is_slam: bool) -> void:
	if _is_host or not _multiplayer or not impulse.is_finite():
		return
	var key: int = _local_key()
	if not _contestants.has(key):
		return
	var entry: Dictionary = _contestants[key]
	entry["damage_pct"] = clampf(new_damage_pct, 0.0, DAMAGE_MAX)
	entry["last_attacker_id"] = attacker_key
	entry["last_hit_time"] = _time
	_pulse_hud_damage()
	var cart: CartPlayer = entry.get("cart") as CartPlayer
	_apply_local_knockback_body(entry, cart, impulse.limit_length(48.0), is_slam, true)
	if cart != null and is_instance_valid(cart):
		_spawn_hit_burst(cart.global_position + Vector3.UP * 0.8, is_slam)
	_play_one_shot(SLAM_HIT_SFX, -3.5 if is_slam else -6.0, 0.95)


func _broadcast_damage_table() -> void:
	var keys := PackedInt32Array()
	var damages := PackedFloat32Array()
	var alive_flags := PackedByteArray()
	for raw_key: Variant in _contestants.keys():
		var k: int = int(raw_key)
		var entry: Dictionary = _contestants[k]
		keys.append(k)
		damages.append(float(entry.get("damage_pct", 0.0)))
		alive_flags.append(1 if bool(entry.get("alive", false)) else 0)
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_damage_table", keys, damages, alive_flags)


@rpc("authority", "unreliable_ordered")
func _net_damage_table(keys: PackedInt32Array, damages: PackedFloat32Array,
		alive_flags: PackedByteArray) -> void:
	if _is_host or not _multiplayer:
		return
	var n: int = mini(keys.size(), mini(damages.size(), alive_flags.size()))
	for i: int in n:
		var k: int = keys[i]
		if not _contestants.has(k):
			continue
		var entry: Dictionary = _contestants[k]
		var pct: float = clampf(damages[i], 0.0, DAMAGE_MAX)
		var prev_pct: float = float(entry.get("damage_pct", 0.0))
		entry["damage_pct"] = pct
		var is_alive: bool = alive_flags[i] != 0
		if not is_alive and bool(entry.get("alive", true)):
			entry["alive"] = false
			_park_eliminated_cart(entry)
		_refresh_3d_badge(entry, pct > prev_pct + 4.0)


func _broadcast_wave_event(wave_num: int, dropping: bool) -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_wave_event", wave_num, dropping)


@rpc("authority", "reliable")
func _net_wave_event(wave_num: int, dropping: bool) -> void:
	if _is_host or not _multiplayer:
		return
	var w: int = 1 if wave_num == 1 else 2
	if dropping:
		_collapse_wave(w)
		_show_toast("OUTER RING COLLAPSED!" if w == 1 else "FINAL CORE SHOWDOWN!",
			2.0, UiPalette.RED if w == 1 else UiPalette.YELLOW)
	else:
		_set_wave_warning(w, true)
		_show_toast("⚠ OUTER RING DROPPING!" if w == 1 else "⚠ FINAL RING SHRINKING!",
			3.6, Color("ff9e2c") if w == 1 else UiPalette.RED)
		_play_one_shot(WARNING_SFX, -4.0, 0.95 if w == 1 else 1.12)


func _pack_scores() -> Dictionary:
	var keys := PackedInt32Array()
	var scores := PackedInt32Array()
	var kos := PackedInt32Array()
	var slots := PackedInt32Array()
	for raw_key: Variant in _contestants.keys():
		var k: int = int(raw_key)
		var entry: Dictionary = _contestants[k]
		keys.append(k)
		scores.append(int(entry.get("score", 0)))
		kos.append(int(entry.get("kos", 0)))
		slots.append(int(entry.get("spawn_slot", 0)))
	return {"keys": keys, "scores": scores, "kos": kos, "slots": slots}


func _apply_packed_scores(keys: PackedInt32Array, scores: PackedInt32Array,
		kos: PackedInt32Array) -> void:
	var n: int = mini(keys.size(), mini(scores.size(), kos.size()))
	for i: int in n:
		var k: int = keys[i]
		if _contestants.has(k):
			_contestants[k]["score"] = clampi(scores[i], 0, 999)
			_contestants[k]["kos"] = clampi(kos[i], 0, 999)


func _broadcast_ko_event(victim_key: int, attacker_key: int, ko_pos: Vector3) -> void:
	var packed: Dictionary = _pack_scores()
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_ko_event", victim_key, attacker_key, ko_pos,
				packed["keys"], packed["scores"], packed["kos"])


@rpc("authority", "reliable")
func _net_ko_event(victim_key: int, attacker_key: int, ko_pos: Vector3,
		keys: PackedInt32Array, scores: PackedInt32Array,
		kos: PackedInt32Array) -> void:
	if _is_host or not _multiplayer:
		return
	_apply_packed_scores(keys, scores, kos)
	if _contestants.has(victim_key):
		var victim: Dictionary = _contestants[victim_key]
		victim["alive"] = false
		_park_eliminated_cart(victim)
		if attacker_key != 0 and _contestants.has(attacker_key):
			_show_toast("%s KO'd %s! (+%d)" % [
				str(_contestants[attacker_key].get("name", "PLAYER")),
				str(victim.get("name", "RIVAL")),
				POINTS_PER_KO,
			], 2.6, UiPalette.YELLOW)
		else:
			_show_toast("%s RINGED OUT!" % str(victim.get("name", "RIVAL")),
				2.2, UiPalette.RED)
	if ko_pos.is_finite():
		_spawn_ko_burst(Vector3(ko_pos.x, _ko_y + 0.35, ko_pos.z))
	_play_one_shot(KO_CRASH_SFX, -3.5, 1.0)
	if victim_key == _local_key() and _alive_contestant_keys().size() > 1:
		_set_spectator_mode(true)
	_refresh_hud_immediate()


func _broadcast_round_transition(banner_title: String, banner_sub: String) -> void:
	var packed: Dictionary = _pack_scores()
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_round_transition", int(_phase), _round_index,
				_round_remaining, banner_title, banner_sub,
				packed["keys"], packed["scores"], packed["kos"], packed["slots"])


func _send_full_round_snapshot(target_peer: int) -> void:
	var packed: Dictionary = _pack_scores()
	rpc_id(target_peer, "_net_round_transition", int(_phase), _round_index,
		_round_remaining, "", "",
		packed["keys"], packed["scores"], packed["kos"], packed["slots"])
	if _wave1_dropped:
		rpc_id(target_peer, "_net_wave_event", 1, true)
	elif _wave1_warning:
		rpc_id(target_peer, "_net_wave_event", 1, false)
	if _wave2_dropped:
		rpc_id(target_peer, "_net_wave_event", 2, true)
	elif _wave2_warning:
		rpc_id(target_peer, "_net_wave_event", 2, false)


@rpc("authority", "reliable")
func _net_round_transition(phase_id: int, round_idx: int, remaining: float,
		banner_title: String, banner_sub: String,
		keys: PackedInt32Array, scores: PackedInt32Array,
		kos: PackedInt32Array, slots: PackedInt32Array) -> void:
	if _is_host or not _multiplayer:
		return
	_apply_packed_scores(keys, scores, kos)
	var slot_map: Dictionary = {}
	for i: int in mini(keys.size(), slots.size()):
		slot_map[keys[i]] = slots[i]

	var incoming: Phase = clampi(phase_id, 0, 3) as Phase
	match incoming:
		Phase.COUNTDOWN:
			_start_round(round_idx, slot_map)
			_apply_packed_scores(keys, scores, kos)
		Phase.BRAWL:
			if _phase == Phase.COUNTDOWN or _round_index != round_idx:
				_start_round(round_idx, slot_map)
				_apply_packed_scores(keys, scores, kos)
			_phase = Phase.COUNTDOWN
			_begin_brawl()
			if is_finite(remaining):
				_round_remaining = clampf(remaining, 0.0, _round_duration)
				_round_elapsed = maxf(_round_duration - _round_remaining, 0.0)
		Phase.INTERMISSION:
			_phase = Phase.INTERMISSION
			_intermission_timer = INTERMISSION_SECONDS
			if banner_title != "":
				_show_intermission_banner(banner_title, banner_sub)
			for raw_k: Variant in _contestants.keys():
				var c: CartPlayer = _contestants[int(raw_k)].get("cart") as CartPlayer
				if c != null and is_instance_valid(c) and not c.remote_mode:
					c.set_physics_process(false)
		Phase.FINISHED:
			_finish_match()


func _broadcast_clock() -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_round_clock", int(_phase), _round_index,
				_round_remaining, _round_elapsed)


@rpc("authority", "unreliable_ordered")
func _net_round_clock(phase_id: int, round_idx: int, remaining: float,
		elapsed: float) -> void:
	if _is_host or not _multiplayer or _phase == Phase.FINISHED:
		return
	# A client that missed a phase transition (late join, packet gap) used to
	# drop this clock forever and drift; snap to the authoritative timer so it
	# re-syncs. Phase itself is still owned by _net_round_transition.
	if round_idx != _round_index or phase_id != int(_phase):
		if is_finite(remaining) and is_finite(elapsed):
			_round_remaining = clampf(remaining, 0.0, _round_duration)
			_round_elapsed = clampf(elapsed, 0.0, _round_duration)
		return
	if is_finite(remaining) and is_finite(elapsed):
		_round_remaining = clampf(remaining, 0.0, _round_duration)
		_round_elapsed = clampf(elapsed, 0.0, _round_duration)


# ==========================================================================
# Headless Verification Hook (`CART_KNOCKOUT_SELFTEST=1`)
# ==========================================================================

func _audit_arena_colliders() -> Dictionary:
	var solids: int = 0
	var missing_shapes: int = 0
	var bad_layers: int = 0
	for node: Node in _arena_holder.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		solids += 1
		if body.collision_layer != CollisionLayers.WORLD:
			bad_layers += 1
		var shape_count: int = 0
		for child: Node in body.get_children():
			if child is CollisionShape3D:
				shape_count += 1
		if shape_count == 0:
			missing_shapes += 1

	var orphan_shapes: int = 0
	for node: Node in find_children("*", "CollisionShape3D", true, false):
		if not (node.get_parent() is CollisionObject3D):
			orphan_shapes += 1

	return {
		"solids": solids,
		"missing_shapes": missing_shapes,
		"bad_layers": bad_layers,
		"orphan_shapes": orphan_shapes,
	}


func _run_self_test() -> void:
	print("KNOCKOUT_SELFTEST step=boot contestants=%d" % _contestants.size())
	if _contestants.size() < 4:
		_fail_selftest("expected >= 4 contestants in solo, got %d" % _contestants.size())
		return

	# 1. Boot & verify all 3 arenas (WORLD StaticBody3D colliders, 0 orphan shapes,
	#    spawns, ko_y above CartPlayer.FALL_RESET_HEIGHT, wave collapse & reset).
	for arena_id: String in KnockoutMaps.ids():
		_load_arena(arena_id)
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		var audit: Dictionary = _audit_arena_colliders()
		var spawns: Array = _arena_data.get("spawns", []) as Array
		print("KNOCKOUT_SELFTEST step=map id=%s solids=%d missing=%d bad_layer=%d orphans=%d spawns=%d w1=%d w2=%d ko_y=%.2f" % [
			arena_id,
			int(audit["solids"]),
			int(audit["missing_shapes"]),
			int(audit["bad_layers"]),
			int(audit["orphan_shapes"]),
			spawns.size(),
			_wave1_nodes.size(),
			_wave2_nodes.size(),
			_ko_y,
		])
		if int(audit["solids"]) <= 0 or int(audit["missing_shapes"]) > 0 \
				or int(audit["bad_layers"]) > 0 or int(audit["orphan_shapes"]) > 0:
			_fail_selftest("collider audit failed on " + arena_id)
			return
		if spawns.size() < 8 or _wave1_nodes.is_empty() or _wave2_nodes.is_empty():
			_fail_selftest("incomplete arena metadata on " + arena_id)
			return
		if _ko_y <= CartPlayer.FALL_RESET_HEIGHT + 0.5:
			_fail_selftest("ko_y too close to FALL_RESET_HEIGHT on " + arena_id)
			return
		_collapse_wave(1)
		var w1_shapes: Array[Node] = _wave1_nodes[0].find_children("*", "CollisionShape3D", true, false)
		var w1_shape: CollisionShape3D = w1_shapes[0] as CollisionShape3D if not w1_shapes.is_empty() else null
		if w1_shape == null or not w1_shape.disabled:
			_fail_selftest("wave 1 collapse did not disable sector collider on " + arena_id)
			return
		_collapse_wave(2)
		_reset_waves()
		if w1_shape.disabled:
			_fail_selftest("wave reset did not re-enable sector collider on " + arena_id)
			return

	# 2. Live AI tick smoke test on ko_rooftop (all 4 karts active).
	_load_arena("ko_rooftop")
	_start_round(1)
	for _ai_step: int in 12:
		await get_tree().physics_frame
		if not is_inside_tree():
			return

	if _bot_keys.size() < 2:
		_fail_selftest("need at least 2 bots for combat simulation")
		return
	var atk_key: int = _bot_keys[0]
	var vic_key: int = _bot_keys[1]
	var atk_entry: Dictionary = _contestants[atk_key]
	var vic_entry: Dictionary = _contestants[vic_key]
	var atk_cart: CartPlayer = atk_entry.get("cart") as CartPlayer
	var vic_cart: CartPlayer = vic_entry.get("cart") as CartPlayer
	atk_entry["selftest_manual"] = true
	vic_entry["selftest_manual"] = true

	# Park non-participating karts safely away from the test lane.
	for raw_k: Variant in _contestants.keys():
		var k: int = int(raw_k)
		if k == atk_key or k == vic_key:
			continue
		var c: CartPlayer = _contestants[k].get("cart") as CartPlayer
		if c != null and is_instance_valid(c):
			c.global_transform = Transform3D(Basis.IDENTITY, Vector3(-14.0, 0.4, float(k) * 2.2))
			c.velocity = Vector3.ZERO
			c.set_physics_process(false)

	# 3. Mechanic 1 check: normal Smash collision (+12%..+28% damage & knockback).
	_pair_cooldowns.clear()
	vic_entry["damage_pct"] = 0.0
	var east_yaw: float = -PI * 0.5
	vic_cart.global_transform = Transform3D(Basis(Vector3.UP, east_yaw), Vector3(1.2, 0.38, 15.5))
	vic_cart.velocity = Vector3.ZERO
	vic_cart.set_ai_controls(0.0, 0.0, 0.0)
	vic_cart.set_physics_process(true)

	atk_cart.global_transform = Transform3D(Basis(Vector3.UP, east_yaw), Vector3(-1.0, 0.38, 15.5))
	atk_cart.velocity = Vector3(16.0, 0.0, 0.0)
	atk_cart.set_ai_controls(1.0, 0.0, 0.0)
	atk_cart.set_physics_process(true)

	var smash_hit_ok: bool = false
	for _sframe: int in 24:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		if float(vic_entry.get("damage_pct", 0.0)) >= DAMAGE_HIT_MIN - 0.1:
			smash_hit_ok = true
			break
	if not smash_hit_ok:
		_fail_selftest("normal Smash collision did not apply +12%..+28% damage")
		return

	# 4. Mechanic 2 + Ring-Out KO check: Power-Slam near East ledge (+X).
	_pair_cooldowns.clear()
	vic_entry["damage_pct"] = 145.0
	vic_cart.global_transform = Transform3D(Basis(Vector3.UP, east_yaw), Vector3(32.2, 0.38, 0.0))
	vic_cart.velocity = Vector3.ZERO
	vic_cart.set_ai_controls(0.0, 0.0, 0.0)
	vic_cart.set_physics_process(true)

	atk_cart.global_transform = Transform3D(Basis(Vector3.UP, east_yaw), Vector3(29.6, 0.38, 0.0))
	atk_cart.velocity = Vector3(10.0, 0.0, 0.0)
	atk_cart.set_ai_controls(0.0, 0.0, 0.0)
	atk_cart.set_physics_process(true)
	atk_entry["slam_cooldown"] = 0.0
	_activate_slam(atk_key, Vector3.RIGHT)

	var hit_registered: bool = false
	var ko_registered: bool = false
	for _frame: int in 180:
		if bool(vic_entry.get("alive", false)):
			vic_cart.set_ai_controls(0.0, 0.0, 0.0)
		if hit_registered and bool(atk_entry.get("alive", false)):
			atk_cart.velocity = Vector3.ZERO
			atk_cart.set_ai_controls(0.0, 1.0, 0.0)
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		if float(vic_entry.get("damage_pct", 0.0)) > 145.5 \
				and int(vic_entry.get("last_attacker_id", 0)) == atk_key:
			hit_registered = true
		if not bool(vic_entry.get("alive", true)):
			ko_registered = true
			break

	print("KNOCKOUT_SELFTEST step=combat smash=%s hit=%s ko=%s vic_dmg=%.1f atk_alive=%s atk_score=%d atk_kos=%d" % [
		str(smash_hit_ok),
		str(hit_registered),
		str(ko_registered),
		float(vic_entry.get("damage_pct", 0.0)),
		str(bool(atk_entry.get("alive", false))),
		int(atk_entry.get("score", 0)),
		int(atk_entry.get("kos", 0)),
	])
	if not hit_registered:
		_fail_selftest("Power-Slam hit did not increase victim damage_pct or record attacker")
		return
	if not bool(atk_entry.get("alive", false)):
		_fail_selftest("attacker unexpectedly self-eliminated during selftest")
		return
	if not ko_registered or int(atk_entry.get("score", 0)) < POINTS_PER_KO \
			or int(atk_entry.get("kos", 0)) < 1:
		_fail_selftest("ring-out KO did not eliminate victim and award +2 PTS")
		return

	# 5. Verify HUD bounds & 960x540 / 1280x720 non-overlap.
	await get_tree().process_frame
	await get_tree().process_frame
	_layout_hud()
	var clipped: bool = _hud_clips()
	var fits_960: bool = (_leaderboard_panel.offset_right + 12.0) < (480.0 + _top_bar.offset_left)
	print("KNOCKOUT_SELFTEST step=hud clips=%s fits_960=%s" % [str(clipped), str(fits_960)])
	if clipped or not fits_960:
		_fail_selftest("HUD clipped viewport or overlapped at 960x540")
		return

	print("KNOCKOUT_SELFTEST step=pass")
	get_tree().quit(0)


func _fail_selftest(reason: String) -> void:
	push_error("KNOCKOUT_SELFTEST FAIL: " + reason)
	print("KNOCKOUT_SELFTEST step=fail reason=%s" % reason)
	get_tree().quit(1)
