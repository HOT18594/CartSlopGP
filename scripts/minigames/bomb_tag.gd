extends Node3D
## BLAST TAG (`bomb_tag.tscn`): a high-adrenaline 2–8 player (+ AI bots)
## hot-potato chase minigame across three bespoke multi-level 3D arenas
## (`bt_plaza`, `bt_labyrinth`, `bt_ferries`).
##
## Core loop (120 s continuous match):
##   - Each fuse wave (13.5 s) attaches 1 Mega-Bomb above a kart (2 Mega-Bombs
##     simultaneously when >= 6 total karts are in the arena).
##   - Carrier Panic Overdrive grants the bomb holder 1.18x top speed and rapid
##     boost regeneration (+28/s), forcing runners to drift corners, climb
##     bridges, drop off skywalks and juke around pillars rather than coasting.
##   - Ram-Pass: closing within 2.8 m XZ (< 2.2 m Y) of an unshielded,
##     non-bombed kart instantly transfers the Mega-Bomb (flooring remaining
##     fuse at 1.5 s), awards the passer +1 PT ("CLEAN PASS!"), a +4.0 m/s
##     escape speed burst, and a 1.8 s Cyan Immunity Shield.
##   - Runner Juke Surge (`E` / `F` / Right Mouse / Gamepad `B`, 5.0 s cooldown):
##     triggers a 0.5 s lateral/forward dodge burst and drops a cartoon smoke
##     decoy cloud to break ankles at the last millisecond.
##   - Detonation Shockwave: at 0.0 s fuse, KABOOM! Nearby karts within 12 m
##     catch an outward blast impulse; the holder launches skyward (vy = 9.0),
##     loses -1 PT (floored at 0) and respawns cleanly after 1.2 s, while every
##     surviving non-bombed kart scores +2 PTS ("SURVIVED! +2"). After a 2.0 s
##     breather the next Mega-Bomb targets the highest-scoring leader(s).
##   - Out-of-bounds / water falls (`y < fall_y`) immediately rescue the kart
##     onto the nearest safe spawn at 75% planar speed while KEEPING any bomb.

const CART_SCENE: PackedScene = preload("res://scenes/player/cart_player.tscn")
const SandboxBot := preload("res://scripts/ai/sandbox_bot.gd")
const BombTagMaps := preload("res://scripts/minigames/bomb_tag_maps.gd")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const VisualGrade := preload("res://scripts/systems/visual_grade.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CANDY_BUTTON := preload("res://scripts/ui/candy_button.gd")

const SCENE_PATH: String = "res://scenes/minigames/bomb_tag.tscn"
const MAIN_MENU: String = "res://scenes/ui/main_menu.tscn"
const MINIGAMES_MENU: String = "res://scenes/ui/minigames_menu.tscn"
const UI_THEME: Theme = preload("res://assets/ui/theme.tres")
const TITLE_FONT: Font = preload("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")
const BODY_FONT: Font = preload("res://assets/ui/fonts/Fredoka-Bold.ttf")

const COUNTDOWN_BEEP: AudioStream = preload("res://assets/audio/sfx/race/countdown_beep.wav")
const COUNTDOWN_GO: AudioStream = preload("res://assets/audio/sfx/race/countdown_go.wav")
const TAG_ALERT_SFX: AudioStream = preload("res://assets/audio/sfx/fun/horn.wav")
const PASS_CHIME_SFX: AudioStream = preload("res://assets/audio/sfx/fun/drift_chime.wav")
const SURVIVE_SFX: AudioStream = preload("res://assets/audio/sfx/race/lap_chime.wav")
const JUKE_SFX: AudioStream = preload("res://assets/audio/sfx/boost/boost_whoosh.wav")
const BLAST_BOOM_A: AudioStream = preload("res://assets/audio/sfx/impacts/metal_crash_0.ogg")
const BLAST_BOOM_B: AudioStream = preload("res://assets/audio/sfx/impacts/impact_heavy.ogg")
const FINISH_FANFARE: AudioStream = preload("res://assets/audio/sfx/race/finish_fanfare.wav")

const JUKE_ACTION: String = "juke_dash"

## Core match & bomb rules.
const MATCH_SECONDS: float = 120.0 ## 2:00 continuous hot-potato chase.
const COUNTDOWN_SECONDS: float = 3.0 ## 3-2-1 countdown before release.
const FUSE_SECONDS: float = 13.5 ## Seconds per Mega-Bomb fuse wave.
const PASS_FUSE_FLOOR: float = 1.5 ## Minimum fuse granted to a newly tagged carrier.
const WAVE_BREATHER_SECONDS: float = 2.0 ## Breather between detonation and next bomb wave.
const DUAL_BOMB_MIN_KARTS: int = 6 ## Spawn 2 simultaneous Mega-Bombs when >= 6 karts!
const MAX_BOMBS: int = 2

## Spatial & physics tuning.
const BOMB_FLOAT_HEIGHT: float = 2.1 ## Height (m) of the Mega-Bomb above its carrier.
const HALO_RADIUS: float = 3.2 ## Pulsing red ground warning ring radius (m).
const TAG_RADIUS_XZ: float = 2.8 ## Planar contact distance (m) for Ram-Pass transfer.
const TAG_MAX_DY: float = 2.2 ## Vertical tolerance (m) for Ram-Pass transfer.
const OVERDRIVE_SPEED_MULT: float = 1.18 ## Carrier Panic Overdrive top-speed multiplier.
const OVERDRIVE_ACCEL_MULT: float = 1.14 ## Carrier Panic Overdrive acceleration multiplier.
const OVERDRIVE_BOOST_REFILL: float = 28.0 ## Carrier rapid boost refill rate (units/s).
const SURGE_SPEED_CAP_MULT: float = 1.18 ## Temporary speed headroom during Juke / Pass escape.
const SHIELD_SECONDS: float = 1.8 ## Cyan Immunity Shield duration after a clean pass.
const PASS_ESCAPE_BURST: float = 4.0 ## Forward speed kick (m/s) awarded to the passer.
const PASS_LOCK_SECONDS: float = 0.16 ## Brief guard preventing double-transfer in one tick.
const JUKE_COOLDOWN: float = 5.0 ## Cooldown (s) between Runner Juke Surges.
const JUKE_DURATION: float = 0.5 ## Active burst window (s) of a Runner Juke Surge.
const JUKE_BURST_SPEED: float = 5.8 ## Planar dodge impulse (m/s) on Runner Juke Surge.
const JUKE_HOP_VY: float = 2.1 ## Subtle upward hop (m/s) on grounded Juke Surge.
const BLAST_RADIUS: float = 12.0 ## Detonation shockwave radius (m).
const BLAST_HOLDER_LAUNCH_Y: float = 9.0 ## Upward launch velocity (m/s) on detonated carrier.
const BLAST_RESPAWN_DELAY: float = 1.2 ## Delay (s) before detonated carrier respawns cleanly.
const FALL_SPEED_KEEP: float = 0.75 ## Planar speed fraction preserved on water/fall rescue.

## Scoring rules.
const PASS_POINTS: int = 1 ## +1 PT for each clean Ram-Pass.
const SURVIVE_POINTS: int = 2 ## +2 PTS for surviving a detonation without a bomb.
const BLAST_PENALTY: int = 1 ## -1 PT (floored at 0) when a bomb detonates on you.

## AI & network cadence.
const SOLO_MIN_BOTS: int = 3 ## Guarantees >= 4 total karts in Solo play.
const MAX_CONTESTANTS: int = 8
const AI_JUKE_TRIGGER_DIST: float = 5.5 ## Runner AI fires Juke Surge when carrier <= 5.5 m.
const CART_SYNC_INTERVAL: float = 0.05 ## 20 Hz unreliable_ordered kart pose stream.
const SNAPSHOT_SYNC_INTERVAL: float = 0.10 ## 10 Hz host bomb/score/shield snapshot stream.

## Compact UI geometry (verified zero-clip at both 960x540 and 1280x720).
const CORNER_RADIUS: int = 14
const TOP_BAR_TOP: float = 10.0
const TOP_BAR_WIDTH: float = 456.0
const TOP_BAR_MAX_HEIGHT: float = 60.0
const SCORE_LEFT: float = 18.0
const SCORE_WIDTH: float = 192.0
const CALLOUT_HEIGHT: float = 38.0
const BT_SHADOW_COLOR := Color(0.07, 0.05, 0.15, 0.88)
const BT_TEXT_SHADOW := Color(0.08, 0.06, 0.16, 0.85)

enum Phase { COUNTDOWN, PLAYING, FINISHED }


class _BombSlashPlate extends Control:
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
		draw_colored_polygon(sh, BT_SHADOW_COLOR)
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
			draw_colored_polygon(sheen, Color(1.0, 1.0, 1.0, 0.22))

		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, border_color, border_width, true)


## Crisp vector-drawn cartoon Mega-Bomb icon for HUD pills (avoids missing emoji
## glyphs across Windows/Linux/Web fonts while matching Kenney cartoon UI).
class _BombBadgeIcon extends Control:
	var lit: bool = true
	var pulse: float = 0.0

	func _draw() -> void:
		var c: Vector2 = size * 0.5 + Vector2(-1.0, 1.5)
		var r: float = minf(size.x, size.y) * 0.36
		draw_circle(c, r + 1.5, UiPalette.OUTLINE)
		draw_circle(c, r, Color("23212c") if not lit else Color("2b1d28"))
		draw_arc(c, r * 0.68, -0.4, 1.3, 10,
			Color("ff4d5a") if lit else Color("5eead4"), 2.0)
		var cap_pos: Vector2 = c + Vector2(r * 0.52, -r * 0.62)
		draw_circle(cap_pos, 2.6, Color("ffd22e"))
		var spark_pos: Vector2 = cap_pos + Vector2(2.6, -2.8)
		var spark_r: float = 2.4 + pulse * 1.4
		draw_circle(spark_pos, spark_r,
			Color("ffea5a") if lit else Color("38d6f0"))


var _saved_vehicle: String = ""
var _selftest: bool = false
var _multiplayer: bool = false
var _is_host: bool = true

var _arena_id: String = BombTagMaps.DEFAULT_ID
var _arena_name: String = "TERRACE PLAZA"
var _arena_blurb: String = ""
var _arena_info: Dictionary = {}
var _spawns: Array[Transform3D] = []
var _pillars: Array[Vector3] = []
var _ramps: Array[Dictionary] = []
var _fall_y: float = -2.8
var _bounds_half: float = 60.0

var _cart: CartPlayer
var _hud: Node
var _bots: Array[Dictionary] = [] ## {cart, ai, ghost, orbit_sign, orbit_timer}
var _traffic: Array[CartPlayer] = []
var _remote_carts: Dictionary = {} ## peer_id -> CartPlayer
var _name_labels: Dictionary = {} ## peer_id -> Label3D
var _cart_relay_ms: Dictionary = {}
var _base_stats: Dictionary = {} ## cart instance_id -> {max_speed, acceleration}

## Authoritative contestant table keyed by `key: int` (>0 peer_id, <0 bot_key).
var _contestants: Dictionary = {}
## Active Mega-Bomb slots: Array[{active, carrier, fuse, lock, beep_accum}].
var _bombs: Array[Dictionary] = []
var _bomb_rigs: Array[Dictionary] = []
var _shield_rigs: Dictionary = {} ## key -> {root, sphere_mat, ring}

var _phase: Phase = Phase.COUNTDOWN
var _countdown: float = COUNTDOWN_SECONDS
var _last_count: int = 3
var _match_length: float = MATCH_SECONDS
var _remaining: float = MATCH_SECONDS
var _wave_breather: float = 0.0
var _wave_index: int = 0
var _time: float = 0.0
var _visual_time: float = 0.0
var _rng := RandomNumberGenerator.new()

var _cart_sync_timer: float = 0.0
var _snapshot_sync_timer: float = 0.0
var _ready_retry_timer: float = 0.0

## UI nodes.
var _canvas: CanvasLayer
var _hud_root: Control
var _top_bar: PanelContainer
var _top_bar_plate: _BombSlashPlate
var _clock_label: Label
var _fuse_slash_panel: PanelContainer
var _fuse_slash_plate: _BombSlashPlate
var _fuse_icon: _BombBadgeIcon
var _fuse_label: Label
var _status_pill: PanelContainer
var _status_plate: _BombSlashPlate
var _status_style: StyleBoxFlat
var _status_label: Label
var _arena_label: Label
var _score_panel: PanelContainer
var _score_rows_box: VBoxContainer
var _score_row_pool: Array[Dictionary] = []
var _callout_label: Label
var _callout_timer: float = 0.0
var _countdown_label: Label
var _hud_refresh_timer: float = 0.0

var _result_root: Control
var _result_banner_style: StyleBoxFlat
var _result_title: Label
var _result_subtitle: Label
var _result_rows_box: VBoxContainer
var _result_primary_btn: Button
var _result_secondary_btn: Button


func _enter_tree() -> void:
	_saved_vehicle = GameSettings.selected_vehicle
	GameSettings.selected_vehicle = GameSettings.minigame_vehicle


func _exit_tree() -> void:
	GameSettings.selected_vehicle = _saved_vehicle


func _ready() -> void:
	_selftest = OS.get_environment("CART_BOMB_SELFTEST") == "1"
	_ensure_juke_action()
	_multiplayer = Network.is_session_active()
	_is_host = Network.is_host if _multiplayer else true
	_rng.seed = int(Network.race_seed) if (_multiplayer and Network.race_seed != 0) \
		else (20260808 if _selftest else int(Time.get_ticks_msec()))

	_arena_id = BombTagMaps.resolve_id(_requested_arena())
	_apply_env_overrides()
	CursorController.set_menu_mode(false)
	_upgrade_graphics()

	_cart = get_tree().get_first_node_in_group("player") as CartPlayer
	if _cart != null:
		_capture_cart_base(_cart)
	_bind_hud()
	_build_selected_arena(_arena_id)
	_build_bomb_rigs()
	_place_local_cart()
	_build_bots()
	_init_contestants()
	_build_hud()
	_build_result_card()

	if _multiplayer:
		_setup_multiplayer()
	_begin_countdown()
	if _selftest:
		_run_self_test.call_deferred()


# ==========================================================================
# SETUP & ARENA CONSTRUCTION
# ==========================================================================


func _requested_arena() -> String:
	var forced: String = OS.get_environment("CART_BOMB_MAP").strip_edges()
	if forced != "":
		return forced
	if _multiplayer and Network.session_minigame.strip_edges() != "":
		return Network.session_minigame
	return GameSettings.selected_minigame


func _apply_env_overrides() -> void:
	var sec_raw: String = OS.get_environment("CART_BOMB_SECONDS").strip_edges()
	if sec_raw.is_valid_int():
		_match_length = clampf(float(sec_raw.to_int()), 8.0, 900.0)
	_remaining = _match_length


func _ensure_juke_action() -> void:
	## Registers `juke_dash` on E, F, Right Mouse Button and Gamepad B so
	## runners can Smoke Hop / Juke Surge out of the box on keyboard, mouse or pad.
	if not InputMap.has_action(JUKE_ACTION):
		InputMap.add_action(JUKE_ACTION)
	var keys: Array[Key] = [KEY_E, KEY_F]
	for k: Key in keys:
		var has_k: bool = false
		for ev: InputEvent in InputMap.action_get_events(JUKE_ACTION):
			if ev is InputEventKey and (ev as InputEventKey).physical_keycode == k:
				has_k = true
				break
		if not has_k:
			var kev := InputEventKey.new()
			kev.physical_keycode = k
			InputMap.action_add_event(JUKE_ACTION, kev)

	var has_rmb: bool = false
	for ev: InputEvent in InputMap.action_get_events(JUKE_ACTION):
		if ev is InputEventMouseButton \
				and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			has_rmb = true
			break
	if not has_rmb:
		var mbtn := InputEventMouseButton.new()
		mbtn.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(JUKE_ACTION, mbtn)

	var has_pad: bool = false
	for ev: InputEvent in InputMap.action_get_events(JUKE_ACTION):
		if ev is InputEventJoypadButton \
				and (ev as InputEventJoypadButton).button_index == JOY_BUTTON_B:
			has_pad = true
			break
	if not has_pad:
		var jbtn := InputEventJoypadButton.new()
		jbtn.button_index = JOY_BUTTON_B
		jbtn.device = -1
		InputMap.action_add_event(JUKE_ACTION, jbtn)


func _juke_key_name() -> String:
	for ev: InputEvent in InputMap.action_get_events(JUKE_ACTION):
		if ev is InputEventKey:
			var code: int = (ev as InputEventKey).physical_keycode
			if code != 0:
				return OS.get_keycode_string(code)
	return "E"


func _upgrade_graphics() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.msaa_3d = Viewport.MSAA_2X
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	VisualGrade.apply(get_node_or_null("WorldEnvironment") as WorldEnvironment, "race")
	VisualGrade.apply_sun(get_node_or_null("Sun") as DirectionalLight3D)


func _bind_hud() -> void:
	## Shares `hud.tscn` (Speedometer, Boost Meter, 3-Tier Drift Halo, FPS,
	## Tab Ping) while hiding lap/race-only plaques.
	_hud = get_node_or_null("HUD")
	if _hud == null:
		return
	if _cart != null:
		if _hud.has_method("bind_cart"):
			_hud.call("bind_cart", _cart)
		elif _hud.has_method("set_cart"):
			_hud.call("set_cart", _cart)
	for race_node_name: String in [
		"RacePlaque", "RaceBox", "RacePanel", "RaceBar",
		"LapPlaque", "LapBox", "PositionBox",
		"Standings", "StandingsBox", "StandingsPanel", "StandingsPlaque",
		"WrongWay", "WrongWayLabel", "WrongWayBanner",
		"StatePill", "HintLabel",
	]:
		var item: CanvasItem = _hud.find_child(race_node_name, true, false) as CanvasItem
		if item != null:
			item.visible = false


func _build_selected_arena(target_id: String) -> void:
	for child: Node in get_children():
		if child.name.begins_with("BlastTagArena_"):
			remove_child(child)
			child.queue_free()
	_arena_id = BombTagMaps.resolve_id(target_id)
	_arena_info = BombTagMaps.build_arena(self, _arena_id)
	_arena_name = str(_arena_info.get("name", "TERRACE PLAZA"))
	_arena_blurb = str(_arena_info.get("blurb", ""))
	_fall_y = float(_arena_info.get("fall_y", -2.8))
	_bounds_half = float(_arena_info.get("bounds_half", 60.0))

	_spawns.clear()
	var raw_spawns: Variant = _arena_info.get("spawns", [])
	if raw_spawns is Array:
		for entry: Variant in raw_spawns as Array:
			if entry is Transform3D:
				_spawns.append(entry as Transform3D)

	_pillars.clear()
	var raw_pillars: Variant = _arena_info.get("pillars", [])
	if raw_pillars is Array:
		for p: Variant in raw_pillars as Array:
			if p is Vector3:
				_pillars.append(p as Vector3)

	_ramps.clear()
	var raw_ramps: Variant = _arena_info.get("ramps", [])
	if raw_ramps is Array:
		for r: Variant in raw_ramps as Array:
			if r is Dictionary:
				_ramps.append(r as Dictionary)

	_apply_arena_lighting(_arena_info)


func _apply_arena_lighting(info: Dictionary) -> void:
	var world: WorldEnvironment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		var env: Environment = world.environment
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sky: ProceduralSkyMaterial = env.sky.sky_material as ProceduralSkyMaterial
			sky.sky_top_color = info.get("sky_top", sky.sky_top_color) as Color
			sky.sky_horizon_color = info.get("sky_horizon", sky.sky_horizon_color) as Color
			sky.ground_horizon_color = info.get("sky_horizon", sky.ground_horizon_color) as Color
			sky.ground_bottom_color = info.get("ground_bottom", sky.ground_bottom_color) as Color
		env.fog_light_color = info.get("fog_color", env.fog_light_color) as Color
		if env.fog_enabled:
			env.fog_density = float(info.get("fog_density", env.fog_density))
	var sun: DirectionalLight3D = get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = info.get("sun_color", sun.light_color) as Color
		sun.light_energy = float(info.get("sun_energy", sun.light_energy))


# ==========================================================================
# CONTESTANTS, KARTS & BOTS
# ==========================================================================


func _local_key() -> int:
	return multiplayer.get_unique_id() if _multiplayer else 1


func _bot_key(index: int) -> int:
	return -1 - index


func _bot_index_of(key: int) -> int:
	return -1 - key


func _bot_vehicle() -> String:
	var entry: Dictionary = VehicleCatalog.find(GameSettings.minigame_vehicle)
	if entry.is_empty():
		return VehicleCatalog.DEFAULT_ID
	return GameSettings.minigame_vehicle


func _bot_count() -> int:
	var forced: String = OS.get_environment("CART_BOMB_BOTS").strip_edges()
	if forced.is_valid_int():
		return clampi(forced.to_int(), 1, 7)
	if _selftest:
		return 3
	if _multiplayer:
		var humans: int = maxi(Network.participants().size(), 1)
		var max_bots: int = maxi(0, MAX_CONTESTANTS - humans)
		var wanted: int = Network.session_bot_count if Network.session_bots else 0
		return clampi(wanted, 0, max_bots)
	return clampi(GameSettings.effective_bot_count(), 0, MAX_CONTESTANTS - 1)


func _capture_cart_base(cart: CartPlayer) -> void:
	if cart == null or not is_instance_valid(cart):
		return
	var cid: int = cart.get_instance_id()
	_base_stats[cid] = {
		"max_speed": cart.max_speed,
		"acceleration": cart.acceleration,
	}


func _spawn_for_slot(slot: int) -> Transform3D:
	if _spawns.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0))
	return _spawns[posmod(slot, _spawns.size())]


func _place_local_cart() -> void:
	if _cart == null or not is_instance_valid(_cart):
		return
	var slot: int = 0
	if _multiplayer:
		var peers: Array[int] = Network.participants()
		peers.sort()
		var found: int = peers.find(_local_key())
		if found >= 0:
			slot = found
	var spawn: Transform3D = _spawn_for_slot(slot)
	_cart.global_transform = spawn
	_cart.velocity = Vector3.ZERO
	_cart.set_spawn_transform(spawn)
	_cart.set_physics_process(false)


func _build_bots() -> void:
	if _multiplayer and not _is_host:
		return
	var count: int = _bot_count()
	var human_offset: int = maxi(Network.participants().size(), 1) if _multiplayer else 1
	for i in count:
		_spawn_bot(i, false, human_offset + i)
	_rebuild_traffic()


func _spawn_bot(index: int, ghost: bool, spawn_slot: int) -> void:
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	cart.name = "BlastBot_%d" % (index + 1)
	var spawn_xf: Transform3D = _spawn_for_slot(spawn_slot)
	cart.transform = spawn_xf
	if not ghost:
		cart.ai_mode = true
	add_child(cart)
	var ai: SandboxBot = null
	if ghost:
		cart.setup_remote(9100 + index)
	else:
		cart.setup_ai(_bot_vehicle())
		cart.set_spawn_transform(spawn_xf)
		_capture_cart_base(cart)
		ai = SandboxBot.new()
		var bot_rng := RandomNumberGenerator.new()
		bot_rng.seed = 8801 + index * 173
		ai.setup(cart, index, bot_rng, Network.bot_difficulty())
	var tint: Color = CartPlayer.BOT_TINTS[index % CartPlayer.BOT_TINTS.size()]
	var label := Label3D.new()
	label.name = "BotTag"
	label.text = "BOT %d" % (index + 1)
	label.font = TITLE_FONT
	label.font_size = 48
	label.pixel_size = 0.0085
	label.outline_size = 14
	label.outline_modulate = UiPalette.OUTLINE
	label.modulate = tint.lightened(0.22)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.35, 0.0)
	cart.add_child(label)

	_bots.append({
		"cart": cart,
		"ai": ai,
		"ghost": ghost,
		"orbit_sign": 1.0 if index % 2 == 0 else -1.0,
		"orbit_timer": 1.4 + float(index) * 0.45,
		"color": tint,
	})


func _rebuild_traffic() -> void:
	_traffic.clear()
	if _cart != null and is_instance_valid(_cart):
		_traffic.append(_cart)
	for entry: Dictionary in _bots:
		var bcart: CartPlayer = entry.get("cart") as CartPlayer
		if bcart != null and is_instance_valid(bcart) and not bool(entry.get("ghost", false)):
			_traffic.append(bcart)


func _init_contestants() -> void:
	_contestants.clear()
	var my_key: int = _local_key()
	var my_name: String = Network.name_of(my_key) if _multiplayer else GameSettings.player_name
	var my_col: Color = Network.color_of(my_key) if _multiplayer else GameSettings.tag_color()
	_register_contestant(my_key, my_name, my_col)
	if _multiplayer:
		for peer_id: int in Network.participants():
			if peer_id != my_key:
				_register_contestant(peer_id, Network.name_of(peer_id), Network.color_of(peer_id))
	for i in _bots.size():
		var tint: Color = _bots[i].get("color", Color("ff9f43")) as Color
		_register_contestant(_bot_key(i), "BOT %d" % (i + 1), tint)


func _register_contestant(key: int, display_name: String, tint: Color) -> void:
	if _contestants.has(key):
		var existing: Dictionary = _contestants[key] as Dictionary
		existing["name"] = display_name
		existing["color"] = tint
		return
	_contestants[key] = {
		"key": key,
		"name": display_name,
		"color": tint,
		"points": 0,
		"passes": 0,
		"survivals": 0,
		"blasts": 0,
		"times_bombed": 0,
		"shield_timer": 0.0,
		"juke_cooldown": 0.0,
		"juke_active": 0.0,
		"escape_timer": 0.0,
		"respawn_timer": 0.0,
	}


func _cart_for_key(key: int) -> CartPlayer:
	if key > 0:
		if _multiplayer and key != multiplayer.get_unique_id():
			return _remote_carts.get(key) as CartPlayer
		return _cart
	if key < 0:
		var idx: int = _bot_index_of(key)
		if idx >= 0 and idx < _bots.size():
			return _bots[idx].get("cart") as CartPlayer
	return null


func _active_contestant_keys() -> Array[int]:
	var keys: Array[int] = []
	for raw_k: Variant in _contestants.keys():
		var k: int = int(raw_k)
		var c: CartPlayer = _cart_for_key(k)
		if c != null and is_instance_valid(c):
			keys.append(k)
	keys.sort()
	return keys


func _total_kart_count() -> int:
	return _active_contestant_keys().size()


# ==========================================================================
# 3D VISUAL RIGS: MEGA-BOMB + PULSING GROUND HALO + CYAN IMMUNITY SHIELD
# ==========================================================================


func _build_bomb_rigs() -> void:
	_bombs.clear()
	_bomb_rigs.clear()
	for idx in MAX_BOMBS:
		_bombs.append({
			"active": false,
			"carrier": 0,
			"fuse": FUSE_SECONDS,
			"lock": 0.0,
			"beep_accum": 0.0,
		})
		_bomb_rigs.append(_create_bomb_rig(idx))


func _create_bomb_rig(index: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "MegaBombRig_%d" % index
	root.visible = false
	add_child(root)

	# Cartoon black/charcoal iron Mega-Bomb sphere + crimson band + golden fuse cap.
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.56
	body_mesh.height = 1.12
	body_mesh.radial_segments = 20
	body_mesh.rings = 12
	var sphere := MeshInstance3D.new()
	sphere.name = "BombSphere"
	sphere.mesh = body_mesh
	var iron_mat := StandardMaterial3D.new()
	iron_mat.albedo_color = Color("1f2029")
	iron_mat.roughness = 0.55
	iron_mat.metallic = 0.0
	sphere.material_override = iron_mat
	root.add_child(sphere)

	var band_mesh := TorusMesh.new()
	band_mesh.inner_radius = 0.44
	band_mesh.outer_radius = 0.60
	band_mesh.rings = 24
	band_mesh.ring_segments = 8
	var band := MeshInstance3D.new()
	band.name = "CrimsonBand"
	band.mesh = band_mesh
	band.scale = Vector3(1.0, 0.28, 1.0)
	var band_mat := StandardMaterial3D.new()
	band_mat.albedo_color = Color("e63946")
	band_mat.emission_enabled = true
	band_mat.emission = Color("ff3b47")
	band_mat.emission_energy_multiplier = 0.45
	band.material_override = band_mat
	root.add_child(band)

	# Golden fuse crown + curved fuse cord via PropBatch.
	var cap_batch := PropBatch.new()
	cap_batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.54, 0.0)),
		0.22, 0.20, 14, Color("ffd22e"))
	cap_batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.65, 0.0)),
		0.26, 0.06, 14, Color("f4a226"))
	cap_batch.add_box(Transform3D(Basis(Vector3.FORWARD, -0.35), Vector3(0.08, 0.78, 0.0)),
		Vector3(0.08, 0.28, 0.08), Color("d9be8c"))
	cap_batch.add_box(Transform3D(Basis(Vector3.FORWARD, -0.82), Vector3(0.22, 0.91, 0.0)),
		Vector3(0.08, 0.22, 0.08), Color("c7a873"))
	var cap_inst := MeshInstance3D.new()
	cap_inst.name = "GoldenFuseCap"
	cap_inst.mesh = cap_batch.build()
	cap_inst.material_override = SceneryKit.vertex_material()
	root.add_child(cap_inst)

	# Live sparking fuse star at the wick tip.
	var spark := Node3D.new()
	spark.name = "FuseSpark"
	spark.position = Vector3(0.31, 0.96, 0.0)
	root.add_child(spark)
	var spark_batch := PropBatch.new()
	spark_batch.add_box(Transform3D.IDENTITY, Vector3(0.34, 0.08, 0.08), Color("fff380"))
	spark_batch.add_box(Transform3D.IDENTITY, Vector3(0.08, 0.34, 0.08), Color("ff9f1c"))
	spark_batch.add_box(Transform3D.IDENTITY, Vector3(0.08, 0.08, 0.34), Color("ff4040"))
	var spark_mesh := MeshInstance3D.new()
	spark_mesh.mesh = spark_batch.build()
	var spark_mat := SceneryKit.vertex_material()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mesh.material_override = spark_mat
	spark_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spark.add_child(spark_mesh)

	# Floating Countdown Label3D ("8.4") right above the Mega-Bomb.
	var timer_3d := Label3D.new()
	timer_3d.name = "FuseLabel3D"
	timer_3d.text = "13.5"
	timer_3d.font = TITLE_FONT
	timer_3d.font_size = 86
	timer_3d.pixel_size = 0.0095
	timer_3d.outline_size = 16
	timer_3d.outline_modulate = UiPalette.OUTLINE
	timer_3d.modulate = UiPalette.YELLOW
	timer_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	timer_3d.no_depth_test = true
	timer_3d.position = Vector3(0.0, 1.42, 0.0)
	root.add_child(timer_3d)

	# World-space Pulsing Red Warning Halo on the ground (3.2 m tag warning ring!).
	var halo_root := Node3D.new()
	halo_root.name = "MegaBombHalo_%d" % index
	halo_root.visible = false
	add_child(halo_root)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = HALO_RADIUS - 0.34
	ring_mesh.outer_radius = HALO_RADIUS
	ring_mesh.rings = 36
	ring_mesh.ring_segments = 6
	var ring_inst := MeshInstance3D.new()
	ring_inst.mesh = ring_mesh
	ring_inst.scale = Vector3(1.0, 0.05, 1.0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring_mat.albedo_color = Color(1.0, 0.22, 0.24, 0.72)
	ring_inst.material_override = ring_mat
	ring_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo_root.add_child(ring_inst)

	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = HALO_RADIUS - 0.36
	disc_mesh.bottom_radius = HALO_RADIUS - 0.36
	disc_mesh.height = 0.03
	disc_mesh.radial_segments = 28
	disc_mesh.rings = 1
	var disc_inst := MeshInstance3D.new()
	disc_inst.mesh = disc_mesh
	var disc_mat := StandardMaterial3D.new()
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc_mat.albedo_color = Color(1.0, 0.16, 0.18, 0.16)
	disc_inst.material_override = disc_mat
	disc_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo_root.add_child(disc_inst)

	return {
		"root": root,
		"sphere": sphere,
		"iron_mat": iron_mat,
		"band_mat": band_mat,
		"spark": spark,
		"label": timer_3d,
		"halo_root": halo_root,
		"ring_mat": ring_mat,
		"disc_mat": disc_mat,
	}


func _ensure_shield_rig(key: int, cart: CartPlayer) -> Dictionary:
	if _shield_rigs.has(key):
		var cached: Dictionary = _shield_rigs[key] as Dictionary
		var c_root: Node3D = cached.get("root") as Node3D
		if c_root != null and is_instance_valid(c_root):
			if c_root.get_parent() != cart:
				if c_root.get_parent() != null:
					c_root.get_parent().remove_child(c_root)
				cart.add_child(c_root)
			return cached
	var s_root := Node3D.new()
	s_root.name = "CyanImmunityShield"
	s_root.position = Vector3(0.0, 0.85, 0.0)
	s_root.visible = false
	cart.add_child(s_root)

	var bubble_mesh := SphereMesh.new()
	bubble_mesh.radius = 1.52
	bubble_mesh.height = 2.75
	bubble_mesh.radial_segments = 20
	bubble_mesh.rings = 10
	var bubble := MeshInstance3D.new()
	bubble.mesh = bubble_mesh
	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bubble_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bubble_mat.albedo_color = Color(0.20, 0.90, 1.0, 0.28)
	bubble.material_override = bubble_mat
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s_root.add_child(bubble)

	var orbit_mesh := TorusMesh.new()
	orbit_mesh.inner_radius = 1.46
	orbit_mesh.outer_radius = 1.64
	orbit_mesh.rings = 28
	orbit_mesh.ring_segments = 6
	var orbit := MeshInstance3D.new()
	orbit.mesh = orbit_mesh
	orbit.scale = Vector3(1.0, 0.08, 1.0)
	var orbit_mat := StandardMaterial3D.new()
	orbit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orbit_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	orbit_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	orbit_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	orbit_mat.albedo_color = Color(0.35, 0.96, 1.0, 0.72)
	orbit.material_override = orbit_mat
	orbit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s_root.add_child(orbit)

	var rig := {
		"root": s_root,
		"bubble_mat": bubble_mat,
		"orbit": orbit,
	}
	_shield_rigs[key] = rig
	return rig


func _update_visual_rigs(delta: float) -> void:
	# Update Mega-Bomb 3D rigs + ground warning halos.
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state \
		if get_world_3d() != null else null
	for i in _bombs.size():
		var bomb: Dictionary = _bombs[i]
		var rig: Dictionary = _bomb_rigs[i]
		var root: Node3D = rig["root"] as Node3D
		var halo: Node3D = rig["halo_root"] as Node3D
		if not bool(bomb["active"]) or _phase != Phase.PLAYING:
			root.visible = false
			halo.visible = false
			continue
		var carrier: CartPlayer = _cart_for_key(int(bomb["carrier"]))
		if carrier == null or not is_instance_valid(carrier):
			root.visible = false
			halo.visible = false
			continue
		var fuse: float = maxf(float(bomb["fuse"]), 0.0)
		var panic: bool = fuse < 4.0
		var pulse_speed: float = 15.0 if fuse < 2.0 else (9.5 if panic else 4.2)
		var beat: float = 0.5 + 0.5 * sin(_visual_time * pulse_speed + float(i) * 1.3)

		root.visible = true
		var bob: float = sin(_visual_time * 4.5 + float(i)) * 0.10
		root.global_position = carrier.global_position + Vector3(0.0, BOMB_FLOAT_HEIGHT + bob, 0.0)
		root.rotate_y(delta * (3.2 if panic else 1.6))
		var swell: float = 1.0 + beat * (0.18 if panic else 0.06)
		(rig["sphere"] as Node3D).scale = Vector3.ONE * swell

		var iron_mat: StandardMaterial3D = rig["iron_mat"] as StandardMaterial3D
		iron_mat.albedo_color = Color("1f2029").lerp(Color("c92a2a"), beat * (0.72 if panic else 0.15))

		var spark: Node3D = rig["spark"] as Node3D
		spark.rotate_x(delta * 14.0)
		spark.rotate_z(delta * 11.0)
		spark.scale = Vector3.ONE * (0.85 + beat * 0.65)

		var lbl: Label3D = rig["label"] as Label3D
		lbl.text = "%.1f" % fuse
		if panic:
			lbl.modulate = Color("ff3b3b") if beat > 0.45 else Color.WHITE
			lbl.scale = Vector3.ONE * (1.08 + beat * 0.22)
		else:
			lbl.modulate = UiPalette.YELLOW
			lbl.scale = Vector3.ONE

		# Ground warning halo projected cleanly onto the floor beneath the carrier.
		var ground_y: float = carrier.global_position.y + 0.06
		if space != null:
			var rq := PhysicsRayQueryParameters3D.create(
				carrier.global_position + Vector3.UP * 1.2,
				carrier.global_position + Vector3.DOWN * 8.0,
				CollisionLayers.WORLD)
			var hit: Dictionary = space.intersect_ray(rq)
			if not hit.is_empty():
				ground_y = (hit["position"] as Vector3).y + 0.06
		halo.visible = true
		halo.global_position = Vector3(carrier.global_position.x, ground_y, carrier.global_position.z)
		var h_scale: float = 0.96 + beat * 0.07
		halo.scale = Vector3(h_scale, 1.0, h_scale)
		var rmat: StandardMaterial3D = rig["ring_mat"] as StandardMaterial3D
		rmat.albedo_color = Color(1.0, 0.18 if panic else 0.28, 0.20, 0.48 + beat * 0.42)

	# Update Cyan Immunity Shield bubbles on recently passed karts.
	for raw_k: Variant in _contestants.keys():
		var k: int = int(raw_k)
		var cdata: Dictionary = _contestants[k] as Dictionary
		var stimer: float = float(cdata.get("shield_timer", 0.0))
		var cart: CartPlayer = _cart_for_key(k)
		if stimer <= 0.0 or cart == null or not is_instance_valid(cart):
			if _shield_rigs.has(k):
				var existing_root: Node3D = (_shield_rigs[k] as Dictionary).get("root") as Node3D
				if existing_root != null and is_instance_valid(existing_root):
					existing_root.visible = false
			continue
		var srig: Dictionary = _ensure_shield_rig(k, cart)
		var sroot: Node3D = srig["root"] as Node3D
		sroot.visible = true
		var fade: float = clampf(stimer / 0.35, 0.25, 1.0)
		var sbeat: float = 0.5 + 0.5 * sin(_visual_time * 9.0)
		var bmat: StandardMaterial3D = srig["bubble_mat"] as StandardMaterial3D
		bmat.albedo_color = Color(0.20, 0.90, 1.0, (0.22 + sbeat * 0.12) * fade)
		var orbit: Node3D = srig["orbit"] as Node3D
		orbit.rotate_y(delta * 5.2)


# ==========================================================================
# MATCH FLOW & 60 HZ GAMEPLAY PHYSICS
# ==========================================================================


func _begin_countdown() -> void:
	_phase = Phase.COUNTDOWN
	_countdown = COUNTDOWN_SECONDS
	_last_count = int(ceil(_countdown))
	_remaining = _match_length
	_wave_breather = 0.0
	_wave_index = 0
	if _countdown_label != null:
		_countdown_label.text = str(_last_count)
		_countdown_label.visible = true
	if _selftest:
		if _countdown_label != null:
			_countdown_label.visible = false
		_start_match()


func _tick_countdown(delta: float) -> void:
	_countdown = maxf(_countdown - delta, 0.0)
	var count: int = int(ceil(_countdown))
	if count == _last_count:
		return
	_last_count = count
	if count > 0:
		if _countdown_label != null:
			_countdown_label.text = str(count)
			_countdown_label.visible = true
			_pop_control(_countdown_label)
		_play_sfx(COUNTDOWN_BEEP, -8.0, 1.0 + float(3 - count) * 0.07)
		return
	if _countdown_label != null:
		_countdown_label.visible = false
	_show_callout("BLAST TAG!  ·  DON'T HOLD THE BOMB!", UiPalette.YELLOW, 1.8)
	_play_sfx(COUNTDOWN_GO, -5.0, 1.04)
	if _is_host or not _multiplayer:
		_start_match()


func _start_match() -> void:
	if _phase != Phase.COUNTDOWN:
		return
	_phase = Phase.PLAYING
	_remaining = _match_length
	if _countdown_label != null:
		_countdown_label.visible = false
	_set_local_cart_active(true)
	if _is_host or not _multiplayer:
		_spawn_bomb_wave(true)
		if _multiplayer:
			_broadcast_snapshot()


func _set_local_cart_active(active: bool) -> void:
	if _cart == null or not is_instance_valid(_cart):
		return
	_cart.set_physics_process(active)
	if not active:
		_cart.velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	_time += delta
	if _multiplayer and _is_host and _cart != null and Network.is_session_active():
		Network.resolve_car_collisions(_cart, _remote_carts)
	_net_tick(delta)

	match _phase:
		Phase.COUNTDOWN:
			_tick_countdown(delta)
		Phase.PLAYING:
			_tick_contestant_timers(delta)
			_tick_overdrive_and_caps(delta)
			_tick_local_juke_input()
			_tick_fall_rescue()
			if _is_host or not _multiplayer:
				_tick_bombs(delta)
				_tick_bots(delta)
				_tick_match_clock(delta)


func _tick_match_clock(delta: float) -> void:
	_remaining = maxf(_remaining - delta, 0.0)
	if _remaining <= 0.0:
		_finish_match()


func _tick_contestant_timers(delta: float) -> void:
	for raw_k: Variant in _contestants.keys():
		var k: int = int(raw_k)
		var cdata: Dictionary = _contestants[k] as Dictionary
		cdata["shield_timer"] = maxf(float(cdata.get("shield_timer", 0.0)) - delta, 0.0)
		cdata["juke_cooldown"] = maxf(float(cdata.get("juke_cooldown", 0.0)) - delta, 0.0)
		cdata["juke_active"] = maxf(float(cdata.get("juke_active", 0.0)) - delta, 0.0)
		cdata["escape_timer"] = maxf(float(cdata.get("escape_timer", 0.0)) - delta, 0.0)
		var resp: float = float(cdata.get("respawn_timer", 0.0))
		if resp > 0.0:
			resp = maxf(resp - delta, 0.0)
			cdata["respawn_timer"] = resp
			if resp <= 0.0:
				_respawn_kart_safely(k, false)


func _is_bombed(key: int) -> bool:
	for bomb: Dictionary in _bombs:
		if bool(bomb["active"]) and int(bomb["carrier"]) == key:
			return true
	return false


func _bomb_fuse_of(key: int) -> float:
	var best: float = -1.0
	for bomb: Dictionary in _bombs:
		if bool(bomb["active"]) and int(bomb["carrier"]) == key:
			var f: float = float(bomb["fuse"])
			if best < 0.0 or f < best:
				best = f
	return best


func _shortest_active_fuse() -> float:
	var best: float = -1.0
	for bomb: Dictionary in _bombs:
		if bool(bomb["active"]):
			var f: float = float(bomb["fuse"])
			if best < 0.0 or f < best:
				best = f
	return best


func _active_bomb_count() -> int:
	var n: int = 0
	for bomb: Dictionary in _bombs:
		if bool(bomb["active"]):
			n += 1
	return n


## Applies Carrier Panic Overdrive (1.18x top speed + rapid boost refill) to
## Mega-Bomb holders, and temporary speed headroom during Juke / Escape surges.
func _tick_overdrive_and_caps(delta: float) -> void:
	for raw_k: Variant in _contestants.keys():
		var k: int = int(raw_k)
		var cart: CartPlayer = _cart_for_key(k)
		if cart == null or not is_instance_valid(cart) or cart.remote_mode:
			continue
		var cid: int = cart.get_instance_id()
		if not _base_stats.has(cid):
			_capture_cart_base(cart)
		var base: Dictionary = _base_stats[cid] as Dictionary
		var base_spd: float = float(base["max_speed"])
		var base_acc: float = float(base["acceleration"])
		var cdata: Dictionary = _contestants[k] as Dictionary

		if _is_bombed(k):
			cart.max_speed = base_spd * OVERDRIVE_SPEED_MULT
			cart.acceleration = base_acc * OVERDRIVE_ACCEL_MULT
			cart.boost_amount = minf(cart.max_boost,
				cart.boost_amount + delta * OVERDRIVE_BOOST_REFILL)
		elif float(cdata.get("juke_active", 0.0)) > 0.0 \
				or float(cdata.get("escape_timer", 0.0)) > 0.0:
			cart.max_speed = base_spd * SURGE_SPEED_CAP_MULT
			cart.acceleration = base_acc * 1.12
		else:
			cart.max_speed = base_spd
			cart.acceleration = base_acc


## Water / Out-of-Bounds rescue (`y < _fall_y`): teleports back onto the nearest
## safe spawn at 75% planar speed while KEEPING the bomb (no suicide clears!).
func _tick_fall_rescue() -> void:
	for raw_k: Variant in _contestants.keys():
		var k: int = int(raw_k)
		var cart: CartPlayer = _cart_for_key(k)
		if cart == null or not is_instance_valid(cart) or cart.remote_mode:
			continue
		if cart.global_position.y >= _fall_y:
			continue
		_rescue_fallen_kart(k, cart)


func _rescue_fallen_kart(key: int, cart: CartPlayer) -> void:
	var planar_speed: float = Vector2(cart.velocity.x, cart.velocity.z).length()
	var safe_xf: Transform3D = _nearest_safe_spawn(cart.global_position, true)
	cart.set_spawn_transform(safe_xf)
	cart.reset_for_respawn()
	cart.global_transform = safe_xf
	cart.reset_physics_interpolation()
	var forward: Vector3 = -safe_xf.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	cart.velocity = forward * (planar_speed * FALL_SPEED_KEEP)
	if key == _local_key():
		if _is_bombed(key):
			_show_callout("SPLASH!  ·  BOMB STAYS ON YOU!", UiPalette.RED, 1.5)
		else:
			_show_callout("RESCUED!  ·  -25% SPEED", UiPalette.CYAN, 1.2)


func _respawn_kart_safely(key: int, preserve_speed: bool) -> void:
	var cart: CartPlayer = _cart_for_key(key)
	if cart == null or not is_instance_valid(cart) or cart.remote_mode:
		return
	var safe_xf: Transform3D = _safest_respawn_pad(key)
	var kept_spd: float = Vector2(cart.velocity.x, cart.velocity.z).length() * 0.5 \
		if preserve_speed else 0.0
	cart.set_spawn_transform(safe_xf)
	cart.reset_for_respawn()
	cart.global_transform = safe_xf
	cart.reset_physics_interpolation()
	var fwd: Vector3 = (-safe_xf.basis.z).normalized()
	cart.velocity = fwd * kept_spd


func _nearest_safe_spawn(from_pos: Vector3, nearest: bool) -> Transform3D:
	if _spawns.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0))
	var best: Transform3D = _spawns[0]
	var best_d: float = INF if nearest else -INF
	for xf: Transform3D in _spawns:
		var d: float = _planar_distance(from_pos, xf.origin)
		if (nearest and d < best_d) or (not nearest and d > best_d):
			best_d = d
			best = xf
	return best


func _safest_respawn_pad(for_key: int) -> Transform3D:
	if _spawns.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.5, 0.0))
	var best: Transform3D = _spawns[0]
	var best_clearance: float = -1.0
	for xf: Transform3D in _spawns:
		var min_other: float = 999.0
		for raw_k: Variant in _contestants.keys():
			var ok: int = int(raw_k)
			if ok == for_key:
				continue
			var ocart: CartPlayer = _cart_for_key(ok)
			if ocart != null and is_instance_valid(ocart):
				min_other = minf(min_other, _planar_distance(xf.origin, ocart.global_position))
		if min_other > best_clearance:
			best_clearance = min_other
			best = xf
	return best


# ==========================================================================
# MECHANIC 2B: RUNNER JUKE SURGE / SMOKE HOP (`E` / `F` / RMB / PAD B)
# ==========================================================================


func _tick_local_juke_input() -> void:
	if _cart == null or not is_instance_valid(_cart):
		return
	if get_tree().paused or Network.input_locked:
		return
	if not Input.is_action_just_pressed(JUKE_ACTION):
		return
	var my_key: int = _local_key()
	if _is_bombed(my_key):
		_show_callout("RAM A KART TO PASS THE BOMB!", UiPalette.YELLOW, 1.0)
		return
	var cdata: Dictionary = _contestants.get(my_key, {}) as Dictionary
	if float(cdata.get("juke_cooldown", 0.0)) > 0.0 or float(cdata.get("respawn_timer", 0.0)) > 0.0:
		return
	var steer_in: float = Input.get_axis("steer_right", "steer_left")
	if absf(steer_in) < 0.12:
		steer_in = _cart.steer_smoothed
	_trigger_juke(my_key, steer_in, false)
	if _multiplayer and not _is_host and Network.is_scene_ready(1):
		rpc_id(1, "_net_request_juke", clampf(steer_in, -1.0, 1.0))


func _trigger_juke(key: int, steer_sign: float, from_net: bool) -> bool:
	if _phase != Phase.PLAYING or not _contestants.has(key) or _is_bombed(key):
		return false
	var cdata: Dictionary = _contestants[key] as Dictionary
	if not from_net and (float(cdata.get("juke_cooldown", 0.0)) > 0.0 \
			or float(cdata.get("respawn_timer", 0.0)) > 0.0):
		return false
	var cart: CartPlayer = _cart_for_key(key)
	if cart == null or not is_instance_valid(cart):
		return false

	cdata["juke_cooldown"] = JUKE_COOLDOWN
	cdata["juke_active"] = JUKE_DURATION

	var forward: Vector3 = -cart.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD
	var right: Vector3 = cart.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT

	# Lateral/forward juke vector: sharp side-cut if steering, brisk forward dash if neutral.
	var lat: float = -clampf(steer_sign, -1.0, 1.0)
	var surge_dir: Vector3 = (forward * 0.78 + right * lat * 0.68).normalized() \
		if absf(lat) > 0.15 else forward

	if not cart.remote_mode:
		var cid: int = cart.get_instance_id()
		if _base_stats.has(cid):
			cart.max_speed = float((_base_stats[cid] as Dictionary)["max_speed"]) * SURGE_SPEED_CAP_MULT
		cart.velocity += surge_dir * JUKE_BURST_SPEED
		if cart.is_on_floor():
			cart.velocity.y = maxf(cart.velocity.y, JUKE_HOP_VY)

	_spawn_smoke_decoy(cart.global_position)
	_play_sfx(JUKE_SFX, -6.0, 1.22)
	if key == _local_key():
		var cam: ChaseCamera = cart.get_node_or_null("CameraArm") as ChaseCamera
		if cam != null:
			cam.punch_fov(4.5)
		_show_callout("JUKE SURGE!", UiPalette.CYAN, 0.85)

	if _multiplayer and _is_host:
		_broadcast_juke_fx(key, cart.global_position, surge_dir)
	return true


func _spawn_smoke_decoy(origin: Vector3) -> void:
	if _selftest or DisplayServer.get_name() == "headless":
		return
	var cloud := Node3D.new()
	cloud.name = "SmokeDecoy"
	cloud.position = origin + Vector3.UP * 0.45
	add_child(cloud)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.93, 0.95, 0.99, 0.78)

	var offsets: Array[Vector3] = [
		Vector3(0.0, 0.25, 0.0),
		Vector3(-0.75, 0.15, 0.45),
		Vector3(0.75, 0.18, 0.40),
		Vector3(-0.52, 0.42, -0.58),
		Vector3(0.56, 0.38, -0.52),
		Vector3(0.0, 0.68, 0.15),
	]
	for idx in offsets.size():
		var puff := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r: float = 0.62 + float(idx % 3) * 0.18
		sm.radius = r
		sm.height = r * 1.85
		sm.radial_segments = 12
		sm.rings = 6
		puff.mesh = sm
		puff.position = offsets[idx] * 0.55
		puff.material_override = mat
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.add_child(puff)

	cloud.scale = Vector3.ONE * 0.55
	var tw := create_tween()
	tw.tween_property(cloud, "scale", Vector3(2.25, 1.75, 2.25), 0.95) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cloud, "position:y", origin.y + 1.45, 0.95)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.95)
	tw.tween_callback(cloud.queue_free)


# ==========================================================================
# MECHANICS 1, 2A & 3: MEGA-BOMB WAVES, RAM-PASS & DETONATION SHOCKWAVE
# ==========================================================================


func _desired_bomb_count() -> int:
	var total: int = _total_kart_count()
	if total < 2:
		return 0
	return 2 if total >= DUAL_BOMB_MIN_KARTS else 1


func _spawn_bomb_wave(initial: bool) -> void:
	var wanted: int = _desired_bomb_count()
	if wanted <= 0:
		return
	var candidates: Array[int] = _active_contestant_keys()
	if candidates.is_empty():
		return

	var chosen: Array[int] = []
	if initial:
		# First fuse cycle: shuffle contestants randomly for a fair opening scramble.
		var pool: Array[int] = candidates.duplicate()
		for i in range(pool.size() - 1, 0, -1):
			var j: int = _rng.randi_range(0, i)
			var tmp: int = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		for k: int in pool:
			if chosen.size() >= wanted:
				break
			chosen.append(k)
	else:
		# Catch-up mechanic: attach next Mega-Bomb(s) to the highest-scoring kart(s)!
		var ranked: Array[int] = candidates.duplicate()
		ranked.sort_custom(func(a: int, b: int) -> bool:
			var ca: Dictionary = _contestants.get(a, {}) as Dictionary
			var cb: Dictionary = _contestants.get(b, {}) as Dictionary
			var pa: int = int(ca.get("points", 0))
			var pb: int = int(cb.get("points", 0))
			if pa != pb:
				return pa > pb
			var ba: int = int(ca.get("times_bombed", 0))
			var bb: int = int(cb.get("times_bombed", 0))
			if ba != bb:
				return ba < bb
			return a < b
		)
		for k: int in ranked:
			if chosen.size() >= wanted:
				break
			chosen.append(k)

	for i in _bombs.size():
		var bomb: Dictionary = _bombs[i]
		if i < chosen.size():
			var holder: int = chosen[i]
			bomb["active"] = true
			bomb["carrier"] = holder
			bomb["fuse"] = FUSE_SECONDS
			bomb["lock"] = 0.25
			bomb["beep_accum"] = 0.0
			if _contestants.has(holder):
				var hc: Dictionary = _contestants[holder] as Dictionary
				hc["times_bombed"] = int(hc.get("times_bombed", 0)) + 1
				hc["shield_timer"] = 0.0
			if holder == _local_key():
				_play_alert_chime()
				_show_callout("YOU HAVE THE BOMB!  ·  RAM TO PASS!", UiPalette.RED, 2.2)
		else:
			bomb["active"] = false
			bomb["carrier"] = 0
			bomb["fuse"] = 0.0

	_wave_index += 1
	if chosen.size() >= 2 and not _is_bombed(_local_key()):
		_show_callout("DOUBLE MEGA-BOMB WAVE!  ·  WATCH OUT!", UiPalette.YELLOW, 1.8)
	elif not initial and not chosen.is_empty() and not _is_bombed(_local_key()):
		var leader_name: String = _name_of_key(chosen[0])
		_show_callout("MEGA-BOMB ON %s!" % leader_name, UiPalette.YELLOW, 1.6)

	if _multiplayer and _is_host:
		_broadcast_snapshot()


func _tick_bombs(delta: float) -> void:
	if _active_bomb_count() == 0:
		if _remaining <= 1.5:
			return
		_wave_breather = maxf(_wave_breather - delta, 0.0)
		if _wave_breather <= 0.0:
			_spawn_bomb_wave(false)
		return

	# Step fuses, fuse beeps, Ram-Pass contact checks, and 0.0s detonations.
	for i in _bombs.size():
		var bomb: Dictionary = _bombs[i]
		if not bool(bomb["active"]):
			continue
		var holder: int = int(bomb["carrier"])
		var holder_cart: CartPlayer = _cart_for_key(holder)
		if holder_cart == null or not is_instance_valid(holder_cart):
			# Disconnected holder: re-home the live bomb onto the nearest active kart.
			var fallback: Array[int] = _active_contestant_keys()
			if fallback.is_empty():
				bomb["active"] = false
				continue
			bomb["carrier"] = fallback[0]
			holder = fallback[0]
			holder_cart = _cart_for_key(holder)

		bomb["lock"] = maxf(float(bomb["lock"]) - delta, 0.0)
		bomb["fuse"] = maxf(float(bomb["fuse"]) - delta, 0.0)
		_tick_fuse_beep(bomb, delta)

		# Check Ram-Pass transfer before detonation if fuse > 0.0.
		if float(bomb["fuse"]) > 0.0 and float(bomb["lock"]) <= 0.0:
			var pass_target: int = _find_ram_pass_target(holder, holder_cart)
			if pass_target != 0:
				_execute_ram_pass(i, holder, pass_target)
				continue

		if float(bomb["fuse"]) <= 0.0:
			_execute_detonation(i)


func _tick_fuse_beep(bomb: Dictionary, delta: float) -> void:
	if _selftest:
		return
	var fuse: float = float(bomb["fuse"])
	var interval: float = 0.85
	if fuse < 2.0:
		interval = 0.14
	elif fuse < 4.0:
		interval = 0.25
	elif fuse < 7.5:
		interval = 0.48
	var accum: float = float(bomb["beep_accum"]) + delta
	if accum >= interval:
		accum = 0.0
		var pitch: float = lerpf(1.88, 1.05, clampf(fuse / FUSE_SECONDS, 0.0, 1.0))
		var vol: float = -9.0 if int(bomb["carrier"]) == _local_key() else -15.0
		_play_sfx(COUNTDOWN_BEEP, vol, pitch)
	bomb["beep_accum"] = accum


func _find_ram_pass_target(holder_key: int, holder_cart: CartPlayer) -> int:
	if holder_cart == null or not is_instance_valid(holder_cart):
		return 0
	var hpos: Vector3 = _authoritative_pos(holder_cart)
	var best_key: int = 0
	var best_dist: float = TAG_RADIUS_XZ
	for raw_k: Variant in _contestants.keys():
		var k: int = int(raw_k)
		if k == holder_key or _is_bombed(k):
			continue
		var cdata: Dictionary = _contestants[k] as Dictionary
		if float(cdata.get("shield_timer", 0.0)) > 0.0 \
				or float(cdata.get("respawn_timer", 0.0)) > 0.0:
			continue
		var tcart: CartPlayer = _cart_for_key(k)
		if tcart == null or not is_instance_valid(tcart):
			continue
		var tpos: Vector3 = _authoritative_pos(tcart)
		if absf(hpos.y - tpos.y) >= TAG_MAX_DY:
			continue
		var d_xz: float = _planar_distance(hpos, tpos)
		if d_xz <= best_dist:
			best_dist = d_xz
			best_key = k
	return best_key


func _authoritative_pos(cart: CartPlayer) -> Vector3:
	if cart.remote_mode and cart.net_position.is_finite() \
			and cart.net_position.length_squared() > 0.0001:
		return cart.net_position
	return cart.global_position


func _execute_ram_pass(bomb_idx: int, from_key: int, to_key: int) -> void:
	if bomb_idx < 0 or bomb_idx >= _bombs.size():
		return
	var bomb: Dictionary = _bombs[bomb_idx]
	var new_fuse: float = maxf(float(bomb["fuse"]), PASS_FUSE_FLOOR)
	bomb["carrier"] = to_key
	bomb["fuse"] = new_fuse
	bomb["lock"] = PASS_LOCK_SECONDS
	bomb["beep_accum"] = 0.0

	var from_pts: int = 0
	if _contestants.has(from_key):
		var fc: Dictionary = _contestants[from_key] as Dictionary
		fc["points"] = int(fc.get("points", 0)) + PASS_POINTS
		fc["passes"] = int(fc.get("passes", 0)) + 1
		fc["shield_timer"] = SHIELD_SECONDS
		fc["escape_timer"] = 0.65
		from_pts = int(fc["points"])
	if _contestants.has(to_key):
		var tc: Dictionary = _contestants[to_key] as Dictionary
		tc["times_bombed"] = int(tc.get("times_bombed", 0)) + 1
		tc["shield_timer"] = 0.0
		tc["juke_active"] = 0.0

	_apply_pass_burst_and_fx(from_key, to_key)
	if _multiplayer and _is_host:
		_broadcast_pass(bomb_idx, from_key, to_key, new_fuse, from_pts)


func _apply_pass_burst_and_fx(from_key: int, to_key: int) -> void:
	var passer_cart: CartPlayer = _cart_for_key(from_key)
	var receiver_cart: CartPlayer = _cart_for_key(to_key)

	if passer_cart != null and is_instance_valid(passer_cart):
		if not passer_cart.remote_mode:
			var cid: int = passer_cart.get_instance_id()
			if _base_stats.has(cid):
				passer_cart.max_speed = float((_base_stats[cid] as Dictionary)["max_speed"]) \
					* SURGE_SPEED_CAP_MULT
			var fwd: Vector3 = -passer_cart.global_transform.basis.z
			fwd.y = 0.0
			if receiver_cart != null and is_instance_valid(receiver_cart):
				var away: Vector3 = passer_cart.global_position - receiver_cart.global_position
				away.y = 0.0
				if away.length_squared() > 0.01:
					fwd = (fwd.normalized() * 0.65 + away.normalized() * 0.35)
			fwd = fwd.normalized() if fwd.length_squared() > 0.0001 else Vector3.FORWARD
			passer_cart.velocity += fwd * PASS_ESCAPE_BURST
		_pop_3d_text("CLEAN PASS! +1", passer_cart.global_position + Vector3.UP * 2.5,
			UiPalette.CYAN, 68)

	if receiver_cart != null and is_instance_valid(receiver_cart):
		_pop_3d_text("TAGGED!", receiver_cart.global_position + Vector3.UP * 2.5,
			UiPalette.RED, 68)

	var my_key: int = _local_key()
	if from_key == my_key:
		_play_sfx(PASS_CHIME_SFX, -4.0, 1.24)
		_show_callout("CLEAN PASS! +%d PT  ·  SHIELDED!" % PASS_POINTS, UiPalette.CYAN, 1.6)
	elif to_key == my_key:
		_play_alert_chime()
		_show_callout("YOU HAVE THE BOMB! PASS IT!", UiPalette.RED, 2.0)
	else:
		_play_sfx(PASS_CHIME_SFX, -10.0, 1.12)
		_show_callout("%s PASSED TO %s!" % [_name_of_key(from_key), _name_of_key(to_key)],
			UiPalette.YELLOW, 1.2)


func _execute_detonation(bomb_idx: int) -> void:
	if bomb_idx < 0 or bomb_idx >= _bombs.size():
		return
	var bomb: Dictionary = _bombs[bomb_idx]
	if not bool(bomb["active"]):
		return
	var victim_key: int = int(bomb["carrier"])
	bomb["active"] = false
	bomb["carrier"] = 0
	bomb["fuse"] = 0.0

	var victim_cart: CartPlayer = _cart_for_key(victim_key)
	var blast_pos: Vector3 = victim_cart.global_position \
		if (victim_cart != null and is_instance_valid(victim_cart)) else Vector3.ZERO

	# Victim penalty (-1 PT floored at 0) + 1.2s skyward toss before safe respawn.
	if _contestants.has(victim_key):
		var vc: Dictionary = _contestants[victim_key] as Dictionary
		vc["points"] = maxi(0, int(vc.get("points", 0)) - BLAST_PENALTY)
		vc["blasts"] = int(vc.get("blasts", 0)) + 1
		vc["respawn_timer"] = BLAST_RESPAWN_DELAY
		vc["shield_timer"] = 0.0

	# Every surviving non-bombed kart scores +2 PTS ("SURVIVED! +2")!
	for raw_k: Variant in _contestants.keys():
		var k: int = int(raw_k)
		if k == victim_key or _is_bombed(k):
			continue
		var sc: Dictionary = _contestants[k] as Dictionary
		sc["points"] = int(sc.get("points", 0)) + SURVIVE_POINTS
		sc["survivals"] = int(sc.get("survivals", 0)) + 1

	_apply_detonation_shockwave_and_fx(victim_key, blast_pos)

	if _active_bomb_count() == 0:
		_wave_breather = WAVE_BREATHER_SECONDS

	if _multiplayer and _is_host:
		_broadcast_detonation(bomb_idx, victim_key, blast_pos)


func _apply_detonation_shockwave_and_fx(victim_key: int, blast_pos: Vector3) -> void:
	_spawn_explosion_fx(blast_pos)
	_play_sfx(BLAST_BOOM_A, -3.5, 0.82)
	_play_sfx(BLAST_BOOM_B, -4.5, 0.92)

	# Apply shockwave impulse to all local/AI karts within 12 m + launch victim!
	for raw_k: Variant in _contestants.keys():
		var k: int = int(raw_k)
		var cart: CartPlayer = _cart_for_key(k)
		if cart == null or not is_instance_valid(cart):
			continue
		if k == victim_key:
			if not cart.remote_mode:
				cart.velocity.x *= 0.45
				cart.velocity.z *= 0.45
				cart.velocity.y = BLAST_HOLDER_LAUNCH_Y
			_pop_3d_text("KABOOM! -1", blast_pos + Vector3.UP * 2.8, UiPalette.RED, 80)
			continue

		if not cart.remote_mode:
			var offset: Vector3 = cart.global_position - blast_pos
			var d_xz: float = Vector2(offset.x, offset.z).length()
			if d_xz < BLAST_RADIUS:
				var out_dir: Vector3 = Vector3(offset.x, 0.0, offset.z)
				out_dir = out_dir.normalized() if out_dir.length_squared() > 0.01 \
					else Vector3.FORWARD
				var strength: float = 1.0 - clampf(d_xz / BLAST_RADIUS, 0.0, 1.0)
				cart.velocity += out_dir * lerpf(4.5, 13.5, strength)
				cart.velocity.y = maxf(cart.velocity.y, lerpf(1.8, 5.4, strength))

		if not _is_bombed(k):
			_pop_3d_text("SURVIVED! +2", cart.global_position + Vector3.UP * 2.4,
				UiPalette.GRASS, 66)

	# Camera shake & local player callout.
	var my_key: int = _local_key()
	if _cart != null and is_instance_valid(_cart):
		var cam: ChaseCamera = _cart.get_node_or_null("CameraArm") as ChaseCamera
		if cam != null:
			var cam_d: float = _cart.global_position.distance_to(blast_pos)
			var trauma: float = 0.95 if my_key == victim_key \
				else clampf(1.0 - cam_d / 38.0, 0.25, 0.80)
			cam.add_shake(trauma)
			if my_key == victim_key or cam_d < BLAST_RADIUS:
				cam.punch_fov(6.5)

	if my_key == victim_key:
		_show_callout("KABOOM!  ·  -1 PT!", UiPalette.RED, 1.9)
	elif not _is_bombed(my_key):
		_play_sfx(SURVIVE_SFX, -5.5, 1.18)
		_show_callout("SURVIVED!  ·  +%d PTS!" % SURVIVE_POINTS, UiPalette.GRASS, 1.8)


func _spawn_explosion_fx(center: Vector3) -> void:
	if _selftest or DisplayServer.get_name() == "headless":
		return
	var root := Node3D.new()
	root.name = "BlastShockwaveFX"
	root.position = center + Vector3.UP * 0.9
	add_child(root)

	# Inner white-gold core + orange cartoon fireball sphere.
	var fire_mesh := SphereMesh.new()
	fire_mesh.radius = 1.0
	fire_mesh.height = 2.0
	fire_mesh.radial_segments = 20
	fire_mesh.rings = 10
	var fire := MeshInstance3D.new()
	fire.mesh = fire_mesh
	var fire_mat := StandardMaterial3D.new()
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire_mat.albedo_color = Color(1.0, 0.48, 0.12, 0.92)
	fire.material_override = fire_mat
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fire)

	# Expanding electric magenta shockwave ring (scales out to 12 m!).
	var wave_mesh := TorusMesh.new()
	wave_mesh.inner_radius = 0.82
	wave_mesh.outer_radius = 1.0
	wave_mesh.rings = 32
	wave_mesh.ring_segments = 6
	var wave := MeshInstance3D.new()
	wave.mesh = wave_mesh
	wave.position = Vector3(0.0, -0.65, 0.0)
	var wave_mat := StandardMaterial3D.new()
	wave_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wave_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wave_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wave_mat.albedo_color = Color(1.0, 0.22, 0.68, 0.90)
	wave.material_override = wave_mat
	wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wave)

	# Cartoon spark shower cubes shooting outward.
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color("ffe047")
	var box := BoxMesh.new()
	box.size = Vector3(0.32, 0.32, 0.32)
	var tw := create_tween()
	tw.tween_property(fire, "scale", Vector3.ONE * 7.6, 0.48) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(fire_mat, "albedo_color:a", 0.0, 0.52)
	tw.parallel().tween_property(wave, "scale", Vector3(BLAST_RADIUS, 0.35, BLAST_RADIUS), 0.52) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(wave_mat, "albedo_color:a", 0.0, 0.52)

	for s_idx in 12:
		var ang: float = TAU * float(s_idx) / 12.0
		var sp := MeshInstance3D.new()
		sp.mesh = box
		sp.material_override = spark_mat
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(sp)
		var out := Vector3(cos(ang) * 8.5, 3.2 + float(s_idx % 3) * 1.4, sin(ang) * 8.5)
		tw.parallel().tween_property(sp, "position", out, 0.52) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(sp, "scale", Vector3.ONE * 0.05, 0.52)

	tw.tween_callback(root.queue_free)


func _finish_match() -> void:
	if _phase == Phase.FINISHED:
		return
	_phase = Phase.FINISHED
	for bomb: Dictionary in _bombs:
		bomb["active"] = false
	_set_local_cart_active(false)
	for entry: Dictionary in _bots:
		var bcart: CartPlayer = entry.get("cart") as CartPlayer
		if bcart != null and is_instance_valid(bcart):
			bcart.set_ai_controls(0.0, 0.6, 0.0, false, false)
	if _multiplayer and _is_host:
		Network.set_room_state("finished")
		_broadcast_match_end()
	_show_result_card()


# ==========================================================================
# SMART BLAST TAG AI (HUNTER INTERCEPT + MULTI-LEVEL / FERRY ROUTING + JUKE)
# ==========================================================================


func _tick_bots(delta: float) -> void:
	if _bots.is_empty() or (_multiplayer and not _is_host):
		return
	for idx in _bots.size():
		var entry: Dictionary = _bots[idx]
		if bool(entry.get("ghost", false)):
			continue
		var cart: CartPlayer = entry.get("cart") as CartPlayer
		var ai: SandboxBot = entry.get("ai") as SandboxBot
		if cart == null or not is_instance_valid(cart):
			continue
		var key: int = _bot_key(idx)
		var cdata: Dictionary = _contestants.get(key, {}) as Dictionary
		if _phase != Phase.PLAYING or float(cdata.get("respawn_timer", 0.0)) > 0.0:
			cart.set_ai_controls(0.0, 0.5, 0.0, false, false)
			continue

		# Dedicated stuck & reverse recovery so bots never wedge against pillars/rails.
		var rev_t: float = float(entry.get("rev_timer", 0.0))
		if rev_t > 0.0:
			entry["rev_timer"] = maxf(rev_t - delta, 0.0)
			var rev_steer: float = float(entry.get("orbit_sign", 1.0)) * 0.9
			cart.set_ai_controls(0.0, 1.0, rev_steer, false, false)
			continue
		var planar_spd: float = Vector2(cart.velocity.x, cart.velocity.z).length()
		var stuck_t: float = float(entry.get("stuck_timer", 0.0))
		if planar_spd < 1.6 and cart.is_on_floor():
			stuck_t += delta
			if stuck_t > 3.2:
				entry["stuck_timer"] = 0.0
				_respawn_kart_safely(key, false)
				continue
			elif stuck_t > 0.95:
				entry["stuck_timer"] = 1.4
				entry["rev_timer"] = 0.65
				entry["orbit_sign"] = -float(entry.get("orbit_sign", 1.0))
				continue
		else:
			stuck_t = maxf(stuck_t - delta * 2.0, 0.0)
		entry["stuck_timer"] = stuck_t

		if _is_bombed(key):
			_tick_bot_hunter(idx, entry, cart, ai, key, delta)
		else:
			_tick_bot_runner(idx, entry, cart, ai, key, delta)


func _tick_bot_hunter(_idx: int, _entry: Dictionary, cart: CartPlayer,
		ai: SandboxBot, bot_key: int, _delta: float) -> void:
	# Lock onto nearest unshielded, non-bombed contestant.
	var best_key: int = 0
	var best_score: float = INF
	for raw_k: Variant in _contestants.keys():
		var k: int = int(raw_k)
		if k == bot_key or _is_bombed(k):
			continue
		var tc: Dictionary = _contestants[k] as Dictionary
		if float(tc.get("shield_timer", 0.0)) > 0.0 or float(tc.get("respawn_timer", 0.0)) > 0.0:
			continue
		var tcart: CartPlayer = _cart_for_key(k)
		if tcart == null or not is_instance_valid(tcart):
			continue
		var tpos: Vector3 = _authoritative_pos(tcart)
		var score: float = _planar_distance(cart.global_position, tpos) \
			+ absf(tpos.y - cart.global_position.y) * 3.2
		if score < best_score:
			best_score = score
			best_key = k

	if best_key == 0:
		_ai_steer_towards(cart, Vector3.ZERO, true)
		return

	var target_cart: CartPlayer = _cart_for_key(best_key)
	var target_pos: Vector3 = _authoritative_pos(target_cart)
	var target_vel: Vector3 = target_cart.get_collision_velocity()
	var d_xz: float = _planar_distance(cart.global_position, target_pos)
	var lead_time: float = clampf(d_xz / 24.0, 0.0, 0.48)
	var intercept: Vector3 = target_pos + Vector3(target_vel.x, 0.0, target_vel.z) * lead_time

	var nav_goal: Vector3 = _route_arena_waypoint(cart.global_position, intercept)
	if ai != null and ai.stuck > 3.8:
		ai.respawn()
		return
	_ai_steer_towards(cart, nav_goal, true)
	if ai != null:
		ai._dest_target = nav_goal


func _tick_bot_runner(_idx: int, entry: Dictionary, cart: CartPlayer,
		ai: SandboxBot, bot_key: int, delta: float) -> void:
	# Find closest active Mega-Bomb carrier.
	var threat_pos := Vector3.ZERO
	var threat_dist: float = INF
	var has_threat: bool = false
	for bomb: Dictionary in _bombs:
		if not bool(bomb["active"]):
			continue
		var ccart: CartPlayer = _cart_for_key(int(bomb["carrier"]))
		if ccart == null or not is_instance_valid(ccart):
			continue
		var cpos: Vector3 = _authoritative_pos(ccart)
		var d: float = _planar_distance(cart.global_position, cpos)
		if d < threat_dist:
			threat_dist = d
			threat_pos = cpos
			has_threat = true

	var orbit_timer: float = float(entry.get("orbit_timer", 1.5)) - delta
	if orbit_timer <= 0.0:
		orbit_timer = _rng.randf_range(1.6, 3.2)
		entry["orbit_sign"] = -float(entry.get("orbit_sign", 1.0))
	entry["orbit_timer"] = orbit_timer
	var orbit_sign: float = float(entry.get("orbit_sign", 1.0))

	if not has_threat:
		_ai_steer_towards(cart, Vector3(orbit_sign * 22.0, 0.0, 0.0), false)
		return

	# Trigger Runner Juke Surge if Bomb Carrier closes within 5.5 m!
	if threat_dist <= AI_JUKE_TRIGGER_DIST:
		var local_threat: Vector3 = cart.to_local(threat_pos)
		var dodge_sign: float = 1.0 if local_threat.x > 0.0 else -1.0
		_trigger_juke(bot_key, dodge_sign, false)

	var my_pos: Vector3 = cart.global_position
	var away: Vector3 = my_pos - threat_pos
	away.y = 0.0
	away = away.normalized() if away.length_squared() > 0.01 else Vector3.FORWARD
	var perp := Vector3(-away.z * orbit_sign, 0.0, away.x * orbit_sign)

	# Blend away + perpendicular weave, pulling back inside safe arena bounds.
	var evade_goal: Vector3 = my_pos + (away * 0.62 + perp * 0.78).normalized() * 22.0
	var safe_lim: float = _bounds_half - 9.0
	if _arena_id == "bt_ferries":
		# Keep runners safely on their current ferry deck unless crossing a bridge!
		var side: float = -1.0 if my_pos.x < 0.0 else 1.0
		if threat_dist < 15.0:
			# Cross nearest boarding bridge to escape onto the opposite ferry!
			var bz: float = -18.0 if my_pos.z < 0.0 else 18.0
			evade_goal = _route_arena_waypoint(my_pos, Vector3(-side * 24.0, 0.0, bz))
		else:
			evade_goal.x = clampf(evade_goal.x,
				-38.0 if side < 0.0 else 10.0,
				-10.0 if side < 0.0 else 38.0)
			evade_goal.z = clampf(evade_goal.z, -42.0, 42.0)
	else:
		evade_goal.x = clampf(evade_goal.x, -safe_lim, safe_lim)
		evade_goal.z = clampf(evade_goal.z, -safe_lim, safe_lim)
		# Weave toward nearest pillar or ramp to break sightlines!
		if threat_dist < 20.0 and not _ramps.is_empty() and my_pos.y < 1.0:
			var best_r: Dictionary = _ramps[0]
			var best_rd: float = INF
			for r: Dictionary in _ramps:
				var bpt: Vector3 = r["bottom"] as Vector3
				if absf(bpt.y - my_pos.y) < 0.8:
					var rd: float = _planar_distance(my_pos, bpt)
					if rd < best_rd:
						best_rd = rd
						best_r = r
			if best_rd < 24.0:
				evade_goal = best_r["top"] as Vector3

	if ai != null and ai.stuck > 3.8:
		ai.respawn()
		return
	var want_boost: bool = threat_dist < 16.5 and cart.boost_amount > 32.0
	_ai_steer_towards(cart, evade_goal, want_boost)


func _route_arena_waypoint(from_pos: Vector3, goal_pos: Vector3) -> Vector3:
	# 1. Twin Ferries cross-channel routing: use boarding bridges or jump kickers!
	if _arena_id == "bt_ferries" and (from_pos.x * goal_pos.x) < -24.0 \
			and absf(from_pos.x) > 5.5:
		var best_bz: float = -18.0 if absf(from_pos.z + 18.0) <= absf(from_pos.z - 18.0) else 18.0
		var entry_x: float = -18.0 if from_pos.x < 0.0 else 18.0
		if absf(from_pos.z - best_bz) > 4.2:
			return Vector3(entry_x, 0.0, best_bz)
		return Vector3(-entry_x, 2.2, best_bz)

	# 2. Multi-level ramp routing when target sits on a higher tier/bridge!
	if goal_pos.y - from_pos.y > 1.35 and not _ramps.is_empty():
		var best_ramp: Dictionary = {}
		var best_d: float = INF
		for r: Dictionary in _ramps:
			var bot_pt: Vector3 = r["bottom"] as Vector3
			if absf(bot_pt.y - from_pos.y) > 1.2:
				continue
			var d: float = _planar_distance(from_pos, bot_pt)
			if d < best_d:
				best_d = d
				best_ramp = r
		if not best_ramp.is_empty():
			var b_pt: Vector3 = best_ramp["bottom"] as Vector3
			var t_pt: Vector3 = best_ramp["top"] as Vector3
			if _planar_distance(from_pos, b_pt) > 5.5:
				return b_pt
			return t_pt

	return goal_pos


func _ai_steer_towards(cart: CartPlayer, target: Vector3, boost_wanted: bool) -> void:
	var local: Vector3 = cart.to_local(Vector3(target.x, cart.global_position.y, target.z))
	if not local.is_finite():
		return
	var angle: float = atan2(-local.x, -local.z)
	var steer: float = clampf(angle * 2.15, -1.0, 1.0)

	# Dual forward-whisker raycasts: deflect away from vertical walls/pillars
	# (`normal.y < 0.55`) while ignoring drivable <= 14 deg ramps (`normal.y >= 0.96`).
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state \
		if get_world_3d() != null else null
	if space != null:
		var origin: Vector3 = cart.global_position + Vector3.UP * 0.65
		var fwd: Vector3 = -cart.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
		var left_dir: Vector3 = fwd.rotated(Vector3.UP, 0.40) * 6.0
		var right_dir: Vector3 = fwd.rotated(Vector3.UP, -0.40) * 6.0
		var ql := PhysicsRayQueryParameters3D.create(origin, origin + left_dir, CollisionLayers.WORLD)
		var qr := PhysicsRayQueryParameters3D.create(origin, origin + right_dir, CollisionLayers.WORLD)
		var hit_l: Dictionary = space.intersect_ray(ql)
		var hit_r: Dictionary = space.intersect_ray(qr)
		var block_l: bool = not hit_l.is_empty() and (hit_l["normal"] as Vector3).y < 0.55
		var block_r: bool = not hit_r.is_empty() and (hit_r["normal"] as Vector3).y < 0.55
		if block_l and not block_r:
			steer = clampf(steer - 0.72, -1.0, 1.0)
		elif block_r and not block_l:
			steer = clampf(steer + 0.72, -1.0, 1.0)

	var handbrake: bool = absf(angle) > 0.78 and cart.velocity.length() > 8.5
	var brake: float = 0.25 if absf(angle) > 1.65 else 0.0
	var boost_now: bool = boost_wanted and absf(steer) < 0.62
	cart.set_ai_controls(1.0, brake, steer, boost_now, handbrake)


# ==========================================================================
# MULTIPLAYER SYNC (`Network.is_session_active()`)
# ==========================================================================


func _setup_multiplayer() -> void:
	for peer_id: int in multiplayer.get_peers():
		_spawn_remote_cart(peer_id)
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not Network.names_changed.is_connected(_refresh_peer_identities):
		Network.names_changed.connect(_refresh_peer_identities)
	if not Network.tag_colors_changed.is_connected(_refresh_peer_identities):
		Network.tag_colors_changed.connect(_refresh_peer_identities)
	Network.notify_scene_ready()
	if _is_host:
		_broadcast_snapshot()
	else:
		rpc_id(1, "_net_bomb_ready", _arena_id, _bot_vehicle())


func _on_peer_connected(peer_id: int) -> void:
	_spawn_remote_cart(peer_id)
	_register_contestant(peer_id, Network.name_of(peer_id), Network.color_of(peer_id))


func _on_peer_disconnected(peer_id: int) -> void:
	var rcart: CartPlayer = _remote_carts.get(peer_id) as CartPlayer
	if rcart != null and is_instance_valid(rcart):
		rcart.queue_free()
	_remote_carts.erase(peer_id)
	_name_labels.erase(peer_id)
	_cart_relay_ms.erase(peer_id)
	_shield_rigs.erase(peer_id)
	_contestants.erase(peer_id)


func _spawn_remote_cart(peer_id: int) -> void:
	if _remote_carts.has(peer_id) or peer_id == multiplayer.get_unique_id():
		return
	var rcart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	rcart.name = "Remote_%d" % peer_id
	var spawn_xf: Transform3D = _spawn_for_slot(peer_id)
	rcart.transform = spawn_xf
	add_child(rcart)
	rcart.setup_remote(peer_id)
	var label := Label3D.new()
	label.name = "NameTag"
	label.text = Network.name_of(peer_id)
	label.font = TITLE_FONT
	label.font_size = 54
	label.pixel_size = 0.0095
	label.outline_size = 15
	label.outline_modulate = UiPalette.OUTLINE
	label.modulate = Network.color_of(peer_id)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.3, 0.0)
	rcart.add_child(label)
	_name_labels[peer_id] = label
	_remote_carts[peer_id] = rcart
	_register_contestant(peer_id, Network.name_of(peer_id), Network.color_of(peer_id))
	if _cart != null:
		var cam := _cart.get_node_or_null("CameraArm/Camera3D") as Camera3D
		if cam != null:
			cam.current = true


func _refresh_peer_identities() -> void:
	for peer_id: int in _name_labels.keys():
		var lbl: Label3D = _name_labels[peer_id] as Label3D
		if is_instance_valid(lbl):
			lbl.text = Network.name_of(peer_id)
			lbl.modulate = Network.color_of(peer_id)
		_register_contestant(peer_id, Network.name_of(peer_id), Network.color_of(peer_id))
	var my_key: int = _local_key()
	if _multiplayer:
		_register_contestant(my_key, Network.name_of(my_key), Network.color_of(my_key))


func _rpc_sender() -> int:
	return multiplayer.get_remote_sender_id() if multiplayer.multiplayer_peer != null else 0


func _net_tick(delta: float) -> void:
	if not _multiplayer or not Network.is_session_active():
		return
	if not _is_host and _phase == Phase.COUNTDOWN:
		_ready_retry_timer += delta
		if _ready_retry_timer >= 1.2:
			_ready_retry_timer = 0.0
			rpc_id(1, "_net_bomb_ready", _arena_id, _bot_vehicle())

	if _cart != null and is_instance_valid(_cart):
		_cart_sync_timer += delta
		if _cart_sync_timer >= CART_SYNC_INTERVAL:
			_cart_sync_timer = 0.0
			var stamp: int = Time.get_ticks_msec()
			if _is_host:
				_broadcast_cart_state(multiplayer.get_unique_id(),
					_cart.global_position, _cart.rotation.y, stamp, _cart.velocity)
				if not _bots.is_empty():
					_broadcast_bot_states(stamp)
			elif Network.is_scene_ready(1):
				rpc_id(1, "_net_bomb_cart_state", multiplayer.get_unique_id(),
					_cart.global_position, _cart.rotation.y, stamp, _cart.velocity)

	if not _is_host:
		return
	_snapshot_sync_timer += delta
	if _snapshot_sync_timer >= SNAPSHOT_SYNC_INTERVAL:
		_snapshot_sync_timer = 0.0
		_broadcast_snapshot()


@rpc("any_peer", "reliable")
func _net_bomb_ready(arena_id: String, vehicle_id: String) -> void:
	var sender: int = _rpc_sender()
	if sender <= 1 or sender == multiplayer.get_unique_id() or not _is_host:
		return
	if arena_id.length() > 64 or vehicle_id.length() > 64:
		return
	Network.mark_peer_scene_ready(sender)
	_spawn_remote_cart(sender)
	var rcart: CartPlayer = _remote_carts.get(sender) as CartPlayer
	if rcart != null and is_instance_valid(rcart):
		rcart.set_vehicle_id(GameSettings.sanitize_vehicle_id(vehicle_id))
	rpc_id(sender, "_net_bomb_config", _arena_id, _bots.size())
	_send_snapshot_to(sender)
	if _phase == Phase.FINISHED:
		_send_match_end_to(sender)


@rpc("authority", "reliable")
func _net_bomb_config(arena_id: String, bot_count: int) -> void:
	if _is_host:
		return
	var resolved: String = BombTagMaps.resolve_id(arena_id)
	if resolved != _arena_id:
		_build_selected_arena(resolved)
		_place_local_cart()
	_spawn_client_bots(clampi(bot_count, 0, MAX_CONTESTANTS - 1))


func _spawn_client_bots(count: int) -> void:
	if _bots.size() == count:
		return
	for i in _bots.size():
		var bcart: CartPlayer = _bots[i].get("cart") as CartPlayer
		if bcart != null and is_instance_valid(bcart):
			bcart.queue_free()
		_contestants.erase(_bot_key(i))
	_bots.clear()
	var human_offset: int = maxi(Network.participants().size(), 1)
	for i in count:
		_spawn_bot(i, true, human_offset + i)
		var tint: Color = _bots[i].get("color", Color("ff9f43")) as Color
		_register_contestant(_bot_key(i), "BOT %d" % (i + 1), tint)
	_rebuild_traffic()


func _broadcast_cart_state(peer_id: int, pos: Vector3, yaw: float,
		sent_ms: int, vel: Vector3) -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_bomb_cart_state", peer_id, pos, yaw, sent_ms, vel)


@rpc("any_peer", "unreliable_ordered")
func _net_bomb_cart_state(peer_id: int, pos: Vector3, yaw: float,
		sent_ms: int, vel: Vector3 = Vector3.ZERO) -> void:
	var sender: int = _rpc_sender()
	if sender != 1 and peer_id != sender:
		return
	if not pos.is_finite() or not is_finite(yaw) or not vel.is_finite() or sent_ms < 0:
		return
	var rcart: CartPlayer = _remote_carts.get(peer_id) as CartPlayer
	var accepted: bool = false
	if rcart != null and rcart.remote_mode:
		accepted = rcart.set_net_state(pos, yaw, sent_ms, vel)
	if _is_host and sender != 1 and accepted:
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - int(_cart_relay_ms.get(peer_id, -1000)) >= 25:
			_cart_relay_ms[peer_id] = now_ms
			_broadcast_cart_state(peer_id, pos, yaw, sent_ms, vel)


func _broadcast_bot_states(sent_ms: int) -> void:
	var positions := PackedVector3Array()
	var yaws := PackedFloat32Array()
	var velocities := PackedVector3Array()
	for entry: Dictionary in _bots:
		var bcart: CartPlayer = entry.get("cart") as CartPlayer
		if bcart == null or not is_instance_valid(bcart):
			positions.append(Vector3.ZERO)
			yaws.append(0.0)
			velocities.append(Vector3.ZERO)
		else:
			positions.append(bcart.global_position)
			yaws.append(bcart.rotation.y)
			velocities.append(bcart.velocity.limit_length(60.0))
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_bomb_bot_states", positions, yaws, velocities, sent_ms)


@rpc("authority", "unreliable_ordered")
func _net_bomb_bot_states(positions: PackedVector3Array, yaws: PackedFloat32Array,
		velocities: PackedVector3Array, sent_ms: int) -> void:
	if _is_host or not _multiplayer:
		return
	var count: int = mini(positions.size(), _bots.size())
	if yaws.size() < count or velocities.size() < count:
		return
	for i in count:
		var bcart: CartPlayer = _bots[i].get("cart") as CartPlayer
		if bcart != null and is_instance_valid(bcart) and bcart.remote_mode:
			bcart.set_net_state(positions[i], yaws[i], sent_ms, velocities[i])


@rpc("any_peer", "reliable")
func _net_request_juke(steer_sign: float) -> void:
	if not _is_host:
		return
	var sender: int = _rpc_sender()
	if sender <= 1 or not is_finite(steer_sign):
		return
	_trigger_juke(sender, clampf(steer_sign, -1.0, 1.0), false)


func _broadcast_juke_fx(key: int, origin: Vector3, surge_dir: Vector3) -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_juke_fx", key, origin, surge_dir)


@rpc("authority", "reliable")
func _net_juke_fx(key: int, origin: Vector3, _surge_dir: Vector3) -> void:
	if _is_host or not _multiplayer or not origin.is_finite():
		return
	if key == _local_key():
		return
	if _contestants.has(key):
		var cd: Dictionary = _contestants[key] as Dictionary
		cd["juke_cooldown"] = JUKE_COOLDOWN
		cd["juke_active"] = JUKE_DURATION
	_spawn_smoke_decoy(origin)
	_play_sfx(JUKE_SFX, -11.0, 1.2)


func _pack_snapshot() -> Dictionary:
	var b_carriers := PackedInt32Array()
	var b_fuses := PackedFloat32Array()
	for bomb: Dictionary in _bombs:
		b_carriers.append(int(bomb["carrier"]) if bool(bomb["active"]) else 0)
		b_fuses.append(float(bomb["fuse"]) if bool(bomb["active"]) else 0.0)

	var keys := PackedInt32Array()
	var pts := PackedInt32Array()
	var passes := PackedInt32Array()
	var survs := PackedInt32Array()
	var shields := PackedFloat32Array()
	for raw_k: Variant in _contestants.keys():
		var k: int = int(raw_k)
		var cd: Dictionary = _contestants[k] as Dictionary
		keys.append(k)
		pts.append(int(cd.get("points", 0)))
		passes.append(int(cd.get("passes", 0)))
		survs.append(int(cd.get("survivals", 0)))
		shields.append(float(cd.get("shield_timer", 0.0)))
	return {
		"carriers": b_carriers,
		"fuses": b_fuses,
		"keys": keys,
		"pts": pts,
		"passes": passes,
		"survs": survs,
		"shields": shields,
	}


func _broadcast_snapshot() -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			_send_snapshot_to(target)


func _send_snapshot_to(target: int) -> void:
	var snap: Dictionary = _pack_snapshot()
	rpc_id(target, "_net_bomb_snapshot", _remaining, int(_phase), _wave_breather,
		snap["carriers"], snap["fuses"], snap["keys"], snap["pts"],
		snap["passes"], snap["survs"], snap["shields"])


@rpc("authority", "unreliable_ordered")
func _net_bomb_snapshot(rem: float, phase_in: int, breather: float,
		b_carriers: PackedInt32Array, b_fuses: PackedFloat32Array,
		keys: PackedInt32Array, pts: PackedInt32Array,
		passes: PackedInt32Array, survs: PackedInt32Array,
		shields: PackedFloat32Array) -> void:
	if _is_host or not _multiplayer or _phase == Phase.FINISHED:
		return
	if not is_finite(rem) or not is_finite(breather):
		return
	_remaining = clampf(rem, 0.0, 999.0)
	_wave_breather = clampf(breather, 0.0, 10.0)
	var p_clamped: int = clampi(phase_in, 0, 2)
	if p_clamped == int(Phase.PLAYING) and _phase == Phase.COUNTDOWN:
		_start_match()

	for i in mini(b_carriers.size(), _bombs.size()):
		var cid: int = b_carriers[i]
		_bombs[i]["active"] = cid != 0
		_bombs[i]["carrier"] = cid
		_bombs[i]["fuse"] = b_fuses[i] if i < b_fuses.size() else 0.0

	var n: int = keys.size()
	if pts.size() == n and passes.size() == n and survs.size() == n and shields.size() == n:
		for i in n:
			var k: int = keys[i]
			if not _contestants.has(k):
				var nm: String = Network.name_of(k) if k > 0 else ("BOT %d" % (_bot_index_of(k) + 1))
				var col: Color = Network.color_of(k) if k > 0 else Color("ff9f43")
				_register_contestant(k, nm, col)
			var cd: Dictionary = _contestants[k] as Dictionary
			cd["points"] = pts[i]
			cd["passes"] = passes[i]
			cd["survivals"] = survs[i]
			cd["shield_timer"] = shields[i]


func _broadcast_pass(bomb_idx: int, from_key: int, to_key: int,
		new_fuse: float, from_pts: int) -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_bomb_pass", bomb_idx, from_key, to_key, new_fuse, from_pts)


@rpc("authority", "reliable")
func _net_bomb_pass(bomb_idx: int, from_key: int, to_key: int,
		new_fuse: float, from_pts: int) -> void:
	if _is_host or not _multiplayer or _phase == Phase.FINISHED:
		return
	if bomb_idx >= 0 and bomb_idx < _bombs.size():
		_bombs[bomb_idx]["active"] = true
		_bombs[bomb_idx]["carrier"] = to_key
		_bombs[bomb_idx]["fuse"] = clampf(new_fuse, 0.0, FUSE_SECONDS + 2.0)
	if _contestants.has(from_key):
		var fc: Dictionary = _contestants[from_key] as Dictionary
		fc["points"] = maxi(from_pts, 0)
		fc["passes"] = int(fc.get("passes", 0)) + 1
		fc["shield_timer"] = SHIELD_SECONDS
		fc["escape_timer"] = 0.65
	if _contestants.has(to_key):
		(_contestants[to_key] as Dictionary)["shield_timer"] = 0.0
	_apply_pass_burst_and_fx(from_key, to_key)


func _broadcast_detonation(bomb_idx: int, victim_key: int, blast_pos: Vector3) -> void:
	var snap: Dictionary = _pack_snapshot()
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_bomb_detonate", bomb_idx, victim_key, blast_pos,
				snap["keys"], snap["pts"], snap["survs"])


@rpc("authority", "reliable")
func _net_bomb_detonate(bomb_idx: int, victim_key: int, blast_pos: Vector3,
		keys: PackedInt32Array, pts: PackedInt32Array,
		survs: PackedInt32Array) -> void:
	if _is_host or not _multiplayer or not blast_pos.is_finite():
		return
	if bomb_idx >= 0 and bomb_idx < _bombs.size():
		_bombs[bomb_idx]["active"] = false
		_bombs[bomb_idx]["carrier"] = 0
		_bombs[bomb_idx]["fuse"] = 0.0
	if _contestants.has(victim_key):
		(_contestants[victim_key] as Dictionary)["respawn_timer"] = BLAST_RESPAWN_DELAY
	if keys.size() == pts.size() and keys.size() == survs.size():
		for i in keys.size():
			if _contestants.has(keys[i]):
				var cd: Dictionary = _contestants[keys[i]] as Dictionary
				cd["points"] = pts[i]
				cd["survivals"] = survs[i]
	_apply_detonation_shockwave_and_fx(victim_key, blast_pos)


func _broadcast_match_end() -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			_send_match_end_to(target)


func _send_match_end_to(target: int) -> void:
	var snap: Dictionary = _pack_snapshot()
	rpc_id(target, "_net_bomb_match_end", snap["keys"], snap["pts"],
		snap["passes"], snap["survs"])


@rpc("authority", "reliable")
func _net_bomb_match_end(keys: PackedInt32Array, pts: PackedInt32Array,
		passes: PackedInt32Array, survs: PackedInt32Array) -> void:
	if _is_host or not _multiplayer or _phase == Phase.FINISHED:
		return
	var n: int = keys.size()
	if pts.size() == n and passes.size() == n and survs.size() == n:
		for i in n:
			if _contestants.has(keys[i]):
				var cd: Dictionary = _contestants[keys[i]] as Dictionary
				cd["points"] = pts[i]
				cd["passes"] = passes[i]
				cd["survivals"] = survs[i]
	_phase = Phase.FINISHED
	for bomb: Dictionary in _bombs:
		bomb["active"] = false
	_set_local_cart_active(false)
	_show_result_card()


# ==========================================================================
# SLOP-SLASH COMIC-ARCADE HUD + MATCH RESULT CARD (ZERO CLIP @ 960x540 & 1280x720)
# ==========================================================================


func _empty_bt_box(pad_l: float = 0.0, pad_t: float = 0.0,
		pad_r: float = 0.0, pad_b: float = 0.0) -> StyleBoxEmpty:
	var st := StyleBoxEmpty.new()
	st.content_margin_left = pad_l
	st.content_margin_top = pad_t
	st.content_margin_right = pad_r
	st.content_margin_bottom = pad_b
	return st


func _attach_bt_slash(host: Control, skew: float, fill: Color,
		border: Color = UiPalette.INK, border_w: float = 3.5,
		shadow := Vector2(4.0, 5.0)) -> _BombSlashPlate:
	var plate := _BombSlashPlate.new()
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
	_hud_root.name = "BlastTagHudRoot"
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.theme = UI_THEME
	_canvas.add_child(_hud_root)

	# 1. Top-Center Skewed Comic Fuse Header Slash (width 456 px, height <= 54 px).
	_top_bar = PanelContainer.new()
	_top_bar.name = "BlastTagTopBar"
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.anchor_left = 0.5
	_top_bar.anchor_right = 0.5
	_top_bar.offset_left = -TOP_BAR_WIDTH * 0.5
	_top_bar.offset_right = TOP_BAR_WIDTH * 0.5
	_top_bar.offset_top = TOP_BAR_TOP
	_top_bar.offset_bottom = TOP_BAR_TOP + 52.0
	_top_bar.add_theme_stylebox_override("panel", _empty_bt_box(16.0, 4.0, 18.0, 7.0))
	_top_bar_plate = _attach_bt_slash(
		_top_bar, 14.0, UiPalette.INK, UiPalette.CREAM, 3.5, Vector2(4.0, 5.0))
	_top_bar_plate.accent_color = UiPalette.YELLOW
	_top_bar_plate.accent_width = 10.0
	_hud_root.add_child(_top_bar)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(col)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)

	_clock_label = _make_label("2:00", 22, UiPalette.YELLOW, 6)
	_clock_label.custom_minimum_size = Vector2(62.0, 0.0)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_clock_label)

	# Active Mega-Bomb Fuse Angled Slash (bold yellow -> hot-pink/crimson urgency!)
	_fuse_slash_panel = PanelContainer.new()
	_fuse_slash_panel.custom_minimum_size = Vector2(126.0, 36.0)
	_fuse_slash_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fuse_slash_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuse_slash_panel.add_theme_stylebox_override("panel", _empty_bt_box(14.0, 2.0, 16.0, 5.0))
	_fuse_slash_plate = _attach_bt_slash(
		_fuse_slash_panel, 11.0, UiPalette.YELLOW, UiPalette.INK, 3.5, Vector2(3.0, 4.0))
	row.add_child(_fuse_slash_panel)

	var fuse_row := HBoxContainer.new()
	fuse_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fuse_row.add_theme_constant_override("separation", 6)
	fuse_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fuse_slash_panel.add_child(fuse_row)

	_fuse_icon = _BombBadgeIcon.new()
	_fuse_icon.custom_minimum_size = Vector2(20.0, 20.0)
	_fuse_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fuse_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fuse_row.add_child(_fuse_icon)

	_fuse_label = _make_label("13.5S", 20, UiPalette.INK, 0, false)
	_fuse_label.custom_minimum_size = Vector2(64.0, 0.0)
	_fuse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	fuse_row.add_child(_fuse_label)

	# Skewed Status / Juke Callout Slash
	_status_pill = PanelContainer.new()
	_status_pill.custom_minimum_size = Vector2(178.0, 34.0)
	_status_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_pill.add_theme_stylebox_override("panel", _empty_bt_box(14.0, 2.0, 16.0, 5.0))
	_status_plate = _attach_bt_slash(
		_status_pill, 10.0, UiPalette.CYAN, UiPalette.INK, 3.2, Vector2(3.0, 4.0))
	row.add_child(_status_pill)

	_status_label = _make_label("JUKE [E]", 13, UiPalette.INK, 0, false)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.clip_text = true
	_status_pill.add_child(_status_label)

	# Preserved hidden arena label reference so text updates never overflow top_bar.
	_arena_label = _make_label("BLAST TAG · " + _arena_name, 10, UiPalette.CREAM, 4)
	_arena_label.visible = false
	col.add_child(_arena_label)

	# 2. Top-Left Skewed Parallelogram Score Slashes (StyleBoxEmpty outer container!).
	_score_panel = PanelContainer.new()
	_score_panel.name = "LiveScorePanel"
	_score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var score_top: float = 48.0 if _multiplayer else 12.0
	_score_panel.offset_left = SCORE_LEFT
	_score_panel.offset_right = SCORE_LEFT + SCORE_WIDTH
	_score_panel.offset_top = score_top
	_score_panel.offset_bottom = score_top + 40.0
	_score_panel.add_theme_stylebox_override("panel", _empty_bt_box())
	_hud_root.add_child(_score_panel)

	_score_rows_box = VBoxContainer.new()
	_score_rows_box.add_theme_constant_override("separation", 3)
	_score_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_panel.add_child(_score_rows_box)

	for r_idx in MAX_CONTESTANTS:
		var r_panel := PanelContainer.new()
		r_panel.custom_minimum_size = Vector2(0.0, 23.0)
		r_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r_panel.visible = false
		r_panel.add_theme_stylebox_override("panel", _empty_bt_box(14.0, 1.0, 12.0, 3.0))
		var r_plate := _attach_bt_slash(
			r_panel, 10.0, Color(0.118, 0.106, 0.227, 0.88), UiPalette.INK, 2.5, Vector2(2.5, 3.0))
		r_plate.draw_sheen = false

		var r_hbox := HBoxContainer.new()
		r_hbox.add_theme_constant_override("separation", 5)
		r_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r_panel.add_child(r_hbox)

		var nm := _make_label("PLAYER", 11, UiPalette.CREAM, 4, false)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		r_hbox.add_child(nm)

		var badge := _make_label("", 10, UiPalette.YELLOW, 4, false)
		r_hbox.add_child(badge)

		var pts_lbl := _make_label("0", 12, UiPalette.YELLOW, 4, false)
		pts_lbl.custom_minimum_size = Vector2(26.0, 0.0)
		pts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r_hbox.add_child(pts_lbl)

		_score_rows_box.add_child(r_panel)
		_score_row_pool.append({
			"row": r_panel,
			"plate": r_plate,
			"name": nm,
			"badge": badge,
			"pts": pts_lbl,
		})

	# 3. Upper-Center Floating LuckiestGuy Callout & Center Countdown Label.
	_callout_label = _make_label("", 24, UiPalette.YELLOW, 8)
	_callout_label.anchor_left = 0.5
	_callout_label.anchor_right = 0.5
	_callout_label.offset_left = -260.0
	_callout_label.offset_right = 260.0
	_callout_label.offset_top = TOP_BAR_TOP + 60.0
	_callout_label.offset_bottom = TOP_BAR_TOP + 60.0 + CALLOUT_HEIGHT
	_callout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout_label.visible = false
	_hud_root.add_child(_callout_label)

	_countdown_label = _make_label("3", 104, UiPalette.YELLOW, 14)
	_countdown_label.anchor_left = 0.5
	_countdown_label.anchor_right = 0.5
	_countdown_label.anchor_top = 0.5
	_countdown_label.anchor_bottom = 0.5
	_countdown_label.offset_left = -240.0
	_countdown_label.offset_right = 240.0
	_countdown_label.offset_top = -64.0
	_countdown_label.offset_bottom = 64.0
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud_root.add_child(_countdown_label)

	_refresh_hud()
	_layout_hud()


func _layout_hud() -> void:
	if _top_bar != null:
		var tmin: Vector2 = _top_bar.get_combined_minimum_size()
		var tw: float = clampf(maxf(TOP_BAR_WIDTH, tmin.x + 8.0), TOP_BAR_WIDTH, 500.0)
		var th: float = clampf(maxf(tmin.y, 48.0), 48.0, TOP_BAR_MAX_HEIGHT)
		_top_bar.offset_left = -tw * 0.5
		_top_bar.offset_right = tw * 0.5
		_top_bar.offset_top = TOP_BAR_TOP
		_top_bar.offset_bottom = TOP_BAR_TOP + th
		if _callout_label != null:
			_callout_label.offset_top = TOP_BAR_TOP + th + 8.0
			_callout_label.offset_bottom = TOP_BAR_TOP + th + 8.0 + CALLOUT_HEIGHT
	if _score_panel != null:
		var smin: Vector2 = _score_panel.get_combined_minimum_size()
		var score_top: float = 48.0 if _multiplayer else 12.0
		_score_panel.offset_top = score_top
		_score_panel.offset_bottom = score_top + maxf(smin.y, 28.0)


func _hud_clips_for_size(view: Vector2) -> bool:
	if _top_bar == null or _score_panel == null:
		return true
	var top_w: float = _top_bar.offset_right - _top_bar.offset_left
	var top_h: float = _top_bar.offset_bottom - _top_bar.offset_top
	if top_h > TOP_BAR_MAX_HEIGHT + 1.0:
		return true
	var top_rect := Rect2(Vector2(view.x * 0.5 - top_w * 0.5, _top_bar.offset_top),
		Vector2(top_w, top_h))
	var score_rect := Rect2(Vector2(_score_panel.offset_left, _score_panel.offset_top),
		Vector2(SCORE_WIDTH, _score_panel.offset_bottom - _score_panel.offset_top))
	if top_rect.position.x < 0.0 or top_rect.end.x > view.x or top_rect.end.y > view.y:
		return true
	if score_rect.position.x < 0.0 or score_rect.end.x > view.x or score_rect.end.y > view.y:
		return true
	if score_rect.intersects(top_rect):
		return true
	var tmin: Vector2 = _top_bar.get_combined_minimum_size()
	if tmin.x > top_rect.size.x + 1.0 or tmin.y > top_rect.size.y + 1.0:
		return true
	return false


func _process(delta: float) -> void:
	_visual_time += delta
	_update_visual_rigs(delta)
	if _callout_timer > 0.0:
		_callout_timer = maxf(_callout_timer - delta, 0.0)
		if _callout_timer <= 0.0 and _callout_label != null:
			_callout_label.visible = false

	# Smooth live pulse on fuse icon & urgent fuse text.
	if _fuse_icon != null:
		var sf: float = _shortest_active_fuse()
		_fuse_icon.lit = sf >= 0.0
		_fuse_icon.pulse = 0.5 + 0.5 * sin(_visual_time * (14.0 if sf > 0.0 and sf < 4.0 else 5.0))
		_fuse_icon.queue_redraw()

	_hud_refresh_timer += delta
	if _hud_refresh_timer >= 0.08:
		_hud_refresh_timer = 0.0
		_refresh_hud()
		_layout_hud()


func _refresh_hud() -> void:
	if _clock_label == null:
		return
	var whole: int = maxi(int(ceil(_remaining)), 0)
	_clock_label.text = "%d:%02d" % [whole / 60, whole % 60]
	_clock_label.add_theme_color_override("font_color",
		UiPalette.PINK if (whole <= 15 and whole % 2 == 1) else UiPalette.YELLOW)

	_arena_label.text = ("BLAST TAG  ·  %s  ·  %s" % [_arena_name, _arena_blurb]) \
		if _arena_blurb != "" else ("BLAST TAG  ·  %s" % _arena_name)

	var my_key: int = _local_key()
	var my_fuse: float = _bomb_fuse_of(my_key)
	var min_fuse: float = _shortest_active_fuse()
	var flash: bool = sin(_visual_time * 14.0) > 0.0

	if min_fuse >= 0.0:
		_fuse_label.text = "%.1fS" % min_fuse
		var urgent_fuse: bool = min_fuse < 4.5 or my_fuse >= 0.0
		if _fuse_slash_plate != null:
			if urgent_fuse:
				_fuse_slash_plate.fill_color = Color("ff3b3f") if flash else UiPalette.PINK
			else:
				_fuse_slash_plate.fill_color = UiPalette.YELLOW
			_fuse_slash_plate.queue_redraw()
		_fuse_label.add_theme_constant_override("outline_size", 6 if urgent_fuse else 0)
		_fuse_label.add_theme_color_override("font_color",
			UiPalette.CREAM if urgent_fuse else UiPalette.INK)
	else:
		_fuse_label.text = "+%.1fS" % maxf(_wave_breather, 0.0)
		if _fuse_slash_plate != null:
			_fuse_slash_plate.fill_color = UiPalette.CYAN
			_fuse_slash_plate.queue_redraw()
		_fuse_label.add_theme_constant_override("outline_size", 0)
		_fuse_label.add_theme_color_override("font_color", UiPalette.INK)

	var my_data: Dictionary = _contestants.get(my_key, {}) as Dictionary
	var shield_t: float = float(my_data.get("shield_timer", 0.0))
	var juke_cd: float = float(my_data.get("juke_cooldown", 0.0))

	if my_fuse >= 0.0:
		_status_label.text = "PASS THE BOMB!"
		_status_label.add_theme_constant_override("outline_size", 5)
		_status_label.add_theme_color_override("font_color", UiPalette.CREAM)
		if _status_plate != null:
			_status_plate.fill_color = Color("ff3b3f") if flash else UiPalette.PINK
			_status_plate.queue_redraw()
	elif shield_t > 0.0:
		_status_label.text = "SHIELD %.1fS" % shield_t
		_status_label.add_theme_constant_override("outline_size", 0)
		_status_label.add_theme_color_override("font_color", UiPalette.INK)
		if _status_plate != null:
			_status_plate.fill_color = UiPalette.CYAN
			_status_plate.queue_redraw()
	elif juke_cd > 0.05:
		_status_label.text = "JUKE %.1fS" % juke_cd
		_status_label.add_theme_constant_override("outline_size", 5)
		_status_label.add_theme_color_override("font_color", UiPalette.CYAN)
		if _status_plate != null:
			_status_plate.fill_color = Color(0.16, 0.14, 0.30, 0.96)
			_status_plate.queue_redraw()
	else:
		_status_label.text = "SAFE · JUKE [%s]" % _juke_key_name()
		_status_label.add_theme_constant_override("outline_size", 0)
		_status_label.add_theme_color_override("font_color", UiPalette.INK)
		if _status_plate != null:
			_status_plate.fill_color = UiPalette.GRASS
			_status_plate.queue_redraw()

	# Refresh sorted Skewed Comic Live Score Slashes.
	var sorted: Array[Dictionary] = _sorted_standings()
	for i in _score_row_pool.size():
		var slot: Dictionary = _score_row_pool[i]
		var r_panel: Control = slot["row"] as Control
		if i >= sorted.size():
			r_panel.visible = false
			continue
		r_panel.visible = true
		var entry: Dictionary = sorted[i]
		var k: int = int(entry["key"])
		var is_me: bool = k == my_key
		var bombed: bool = _is_bombed(k)
		var shielded: bool = float(entry.get("shield_timer", 0.0)) > 0.0
		var tint: Color = entry["color"] as Color

		var r_plate: _BombSlashPlate = slot["plate"] as _BombSlashPlate
		if bombed:
			r_plate.fill_color = Color("ff3b3f") if flash else UiPalette.PINK
			r_plate.accent_color = UiPalette.YELLOW
			r_plate.accent_width = 10.0
		elif is_me:
			r_plate.fill_color = UiPalette.YELLOW
			r_plate.accent_color = UiPalette.CYAN if shielded else UiPalette.PINK
			r_plate.accent_width = 10.0
		else:
			r_plate.fill_color = Color(0.118, 0.106, 0.227, 0.88)
			r_plate.accent_color = UiPalette.CYAN if shielded else tint
			r_plate.accent_width = 10.0
		r_plate.queue_redraw()

		var dark_text: bool = is_me and not bombed
		var nm_lbl: Label = slot["name"] as Label
		nm_lbl.text = "%d. %s" % [i + 1, str(entry["name"])]
		nm_lbl.add_theme_constant_override("outline_size", 0 if dark_text else 4)
		nm_lbl.add_theme_color_override("font_color",
			UiPalette.INK if dark_text else UiPalette.CREAM)

		var b_lbl: Label = slot["badge"] as Label
		b_lbl.add_theme_constant_override("outline_size", 0 if dark_text else 4)
		if bombed:
			b_lbl.text = "BOMB!"
			b_lbl.add_theme_color_override("font_color", UiPalette.YELLOW)
		elif shielded:
			b_lbl.text = "SHLD"
			b_lbl.add_theme_color_override("font_color",
				UiPalette.INK if dark_text else UiPalette.CYAN)
		else:
			b_lbl.text = ""

		var pts_lbl: Label = slot["pts"] as Label
		pts_lbl.text = str(int(entry["points"]))
		pts_lbl.add_theme_constant_override("outline_size", 0 if dark_text else 4)
		pts_lbl.add_theme_color_override("font_color",
			UiPalette.INK if dark_text else UiPalette.YELLOW)


func _sorted_standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for raw_k: Variant in _contestants.keys():
		rows.append(_contestants[int(raw_k)] as Dictionary)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: int = int(a.get("points", 0))
		var pb: int = int(b.get("points", 0))
		if pa != pb:
			return pa > pb
		var psa: int = int(a.get("passes", 0))
		var psb: int = int(b.get("passes", 0))
		if psa != psb:
			return psa > psb
		var sa: int = int(a.get("survivals", 0))
		var sb: int = int(b.get("survivals", 0))
		if sa != sb:
			return sa > sb
		return int(a.get("key", 0)) < int(b.get("key", 0))
	)
	return rows


# --------------------------------------------------------------------------
# Polished Match Result Card (in "nav_scope", yields to PauseMenu!)
# --------------------------------------------------------------------------


func _build_result_card() -> void:
	_result_root = Control.new()
	_result_root.name = "BlastResultCard"
	_result_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_root.visible = false
	_hud_root.add_child(_result_root)

	var pause_root: Control = get_node_or_null("PauseMenu/Root") as Control
	if pause_root != null and not pause_root.visibility_changed.is_connected(_on_pause_visibility_changed):
		pause_root.visibility_changed.connect(_on_pause_visibility_changed)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.08, 0.18, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_root.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560.0, 0.0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = UiPalette.CREAM
	card_style.border_color = UiPalette.OUTLINE
	card_style.set_border_width_all(5)
	card_style.set_corner_radius_all(16)
	card_style.content_margin_left = 18.0
	card_style.content_margin_right = 18.0
	card_style.content_margin_top = 14.0
	card_style.content_margin_bottom = 14.0
	card_style.shadow_color = Color(0.10, 0.09, 0.22, 0.48)
	card_style.shadow_offset = Vector2(0.0, 8.0)
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	card.add_child(body)

	var banner := PanelContainer.new()
	_result_banner_style = StyleBoxFlat.new()
	_result_banner_style.bg_color = UiPalette.YELLOW
	_result_banner_style.set_corner_radius_all(12)
	_result_banner_style.content_margin_left = 16.0
	_result_banner_style.content_margin_right = 16.0
	_result_banner_style.content_margin_top = 6.0
	_result_banner_style.content_margin_bottom = 6.0
	banner.add_theme_stylebox_override("panel", _result_banner_style)
	body.add_child(banner)

	_result_title = _make_label("WINNER!", 30, UiPalette.INK)
	_result_title.theme_type_variation = &"TitleLabel"
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(_result_title)

	_result_subtitle = _make_label("", 13, UiPalette.MUTED)
	_result_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_result_subtitle)

	# Column header + per-contestant standings rows (Points, Passes, Survivals).
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	var h_name := _make_label("CONTESTANT", 12, UiPalette.MUTED)
	h_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(h_name)
	for col_txt: String in ["PTS", "PASSES", "SURVIVALS"]:
		var hl := _make_label(col_txt, 12, UiPalette.MUTED)
		hl.custom_minimum_size = Vector2(72.0, 0.0)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		header.add_child(hl)
	body.add_child(header)

	_result_rows_box = VBoxContainer.new()
	_result_rows_box.add_theme_constant_override("separation", 4)
	body.add_child(_result_rows_box)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	body.add_child(btn_row)

	if _multiplayer and not _is_host:
		_result_primary_btn = _make_candy_button("BACK TO LOBBY", UiPalette.YELLOW, 48.0)
		_result_primary_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_result_primary_btn.pressed.connect(_on_back_pressed)
		btn_row.add_child(_result_primary_btn)
		_result_secondary_btn = _make_candy_button("MAIN MENU", UiPalette.BLUE, 48.0)
		_result_secondary_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_result_secondary_btn.pressed.connect(_on_main_menu_pressed)
		btn_row.add_child(_result_secondary_btn)
	else:
		_result_primary_btn = _make_candy_button("PLAY AGAIN", UiPalette.YELLOW, 48.0)
		_result_primary_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_result_primary_btn.pressed.connect(_on_play_again_pressed)
		btn_row.add_child(_result_primary_btn)
		var back_text: String = "BACK TO LOBBY" if _multiplayer else "BACK TO MODES"
		_result_secondary_btn = _make_candy_button(back_text, UiPalette.BLUE, 48.0)
		_result_secondary_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_result_secondary_btn.pressed.connect(_on_back_pressed)
		btn_row.add_child(_result_secondary_btn)


func _show_result_card() -> void:
	if _result_root == null:
		return
	for child: Node in _result_rows_box.get_children():
		child.queue_free()

	var standings: Array[Dictionary] = _sorted_standings()
	var my_key: int = _local_key()
	if not standings.is_empty():
		var top_entry: Dictionary = standings[0]
		var top_key: int = int(top_entry["key"])
		var tied_top: bool = standings.size() > 1 \
			and int(standings[1]["points"]) == int(top_entry["points"]) \
			and int(standings[1]["passes"]) == int(top_entry["passes"])
		if tied_top:
			_result_title.text = "TIED BLAST CHAMPIONS!"
			_result_banner_style.bg_color = UiPalette.CYAN
		elif top_key == my_key:
			_result_title.text = "VICTORY!  ·  #1 %s" % str(top_entry["name"])
			_result_banner_style.bg_color = UiPalette.YELLOW
		else:
			_result_title.text = "WINNER: %s!" % str(top_entry["name"])
			_result_banner_style.bg_color = UiPalette.BLUE.lightened(0.18)

	_result_subtitle.text = "BLAST TAG  ·  %s  ·  FINAL STANDINGS" % _arena_name

	for i in standings.size():
		var row_data: Dictionary = standings[i]
		var rk: int = int(row_data["key"])
		var pill := PanelContainer.new()
		var pstyle := StyleBoxFlat.new()
		pstyle.bg_color = Color(1.0, 0.85, 0.25, 0.35) if rk == my_key \
			else Color(0.12, 0.11, 0.23, 0.07)
		pstyle.set_corner_radius_all(8)
		pstyle.content_margin_left = 10.0
		pstyle.content_margin_right = 10.0
		pstyle.content_margin_top = 3.0
		pstyle.content_margin_bottom = 3.0
		pill.add_theme_stylebox_override("panel", pstyle)

		var rbox := HBoxContainer.new()
		rbox.add_theme_constant_override("separation", 8)
		pill.add_child(rbox)

		var nm := _make_label("%d. %s" % [i + 1, str(row_data["name"])], 14, UiPalette.INK)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rbox.add_child(nm)

		for val_txt: String in [
			str(int(row_data.get("points", 0))),
			str(int(row_data.get("passes", 0))),
			str(int(row_data.get("survivals", 0))),
		]:
			var vl := _make_label(val_txt, 14, UiPalette.INK)
			vl.custom_minimum_size = Vector2(72.0, 0.0)
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			rbox.add_child(vl)

		_result_rows_box.add_child(pill)

	_result_root.visible = true
	CursorController.set_menu_mode(true)
	var pause_root: Control = get_node_or_null("PauseMenu/Root") as Control
	if pause_root != null and pause_root.visible:
		_result_root.remove_from_group("nav_scope")
	else:
		if not _result_root.is_in_group("nav_scope"):
			_result_root.add_to_group("nav_scope")
		MenuNav.refresh()
		if _result_primary_btn != null:
			MenuNav.focus(_result_primary_btn)
	_play_sfx(FINISH_FANFARE, -6.5, 1.0)


func _on_pause_visibility_changed() -> void:
	if _result_root == null or not _result_root.visible:
		return
	var pause_root: Control = get_node_or_null("PauseMenu/Root") as Control
	var pause_open: bool = pause_root != null and pause_root.visible
	if pause_open:
		_result_root.remove_from_group("nav_scope")
	elif not _result_root.is_in_group("nav_scope"):
		_result_root.add_to_group("nav_scope")
	MenuNav.refresh()
	if not pause_open and _result_primary_btn != null:
		MenuNav.focus(_result_primary_btn)


func _on_play_again_pressed() -> void:
	if _multiplayer:
		if _is_host:
			Network.start_game(SCENE_PATH, GameSettings.GAME_MINIGAMES)
		return
	SceneLoader.go_to(SCENE_PATH, "BLAST TAG", _arena_name)


func _on_back_pressed() -> void:
	if _multiplayer:
		Network.return_to_lobby_keep_session()
	else:
		SceneLoader.go_to(MINIGAMES_MENU, "GAME MODES", "PICK AN EVENT")


func _on_main_menu_pressed() -> void:
	if Network.is_session_active():
		Network.leave()
	SceneLoader.go_to(MAIN_MENU, "MAIN MENU")


# ==========================================================================
# UI, AUDIO & POPUP HELPERS
# ==========================================================================


func _bar_style(bg: Color, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = UiPalette.OUTLINE
	s.set_border_width_all(3)
	s.set_corner_radius_all(CORNER_RADIUS)
	s.content_margin_left = float(pad_x)
	s.content_margin_right = float(pad_x)
	s.content_margin_top = float(pad_y)
	s.content_margin_bottom = float(pad_y)
	s.anti_aliasing = true
	return s


func _make_label(text: String, font_size: int, color: Color,
		outline: int = 0, hard_shadow: Variant = null) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.theme_type_variation = &"TitleLabel"
	lbl.add_theme_font_override("font", BODY_FONT)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	if outline > 0:
		lbl.add_theme_color_override("font_outline_color", UiPalette.INK)
		lbl.add_theme_constant_override("outline_size", mini(outline, 3))
	else:
		lbl.add_theme_constant_override("outline_size", 0)
	var use_shadow: bool = (outline >= 5) if hard_shadow == null else bool(hard_shadow)
	if use_shadow:
		lbl.add_theme_color_override("font_shadow_color", BT_TEXT_SHADOW)
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 2)
	else:
		lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
		lbl.add_theme_constant_override("shadow_offset_x", 0)
		lbl.add_theme_constant_override("shadow_offset_y", 0)
	return lbl


func _make_candy_button(text: String, fill: Color, height: float) -> Button:
	var btn := Button.new()
	btn.set_script(CANDY_BUTTON)
	btn.set("fill_color", fill)
	btn.text = text
	btn.custom_minimum_size = Vector2(0.0, height)
	btn.add_theme_font_size_override("font_size", 20)
	return btn


func _show_callout(text: String, color: Color, duration: float) -> void:
	if _callout_label == null:
		return
	_callout_label.text = text
	_callout_label.add_theme_color_override("font_color", color)
	_callout_label.visible = true
	_callout_timer = duration
	_pop_control(_callout_label)


func _pop_control(control: Control) -> void:
	if control == null:
		return
	control.scale = Vector2.ONE * 1.16
	control.pivot_offset = control.size * 0.5
	var tw := create_tween()
	tw.tween_property(control, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _pop_3d_text(text: String, pos: Vector3, color: Color, size: int) -> void:
	if _selftest or DisplayServer.get_name() == "headless":
		return
	var pop := Label3D.new()
	pop.text = text
	pop.font = TITLE_FONT
	pop.font_size = size
	pop.pixel_size = 0.010
	pop.outline_size = 15
	pop.outline_modulate = UiPalette.OUTLINE
	pop.modulate = color
	pop.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pop.no_depth_test = true
	pop.position = pos
	add_child(pop)
	var tw := create_tween()
	tw.tween_property(pop, "position:y", pos.y + 2.4, 0.80)
	tw.parallel().tween_property(pop, "modulate:a", 0.0, 0.80)
	tw.tween_callback(pop.queue_free)


func _play_sfx(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if _selftest or stream == null or DisplayServer.get_name() == "headless":
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _play_alert_chime() -> void:
	## Snappy 0.35 s urgent double-chime when tagged with a Mega-Bomb!
	if _selftest or DisplayServer.get_name() == "headless":
		return
	_play_sfx(TAG_ALERT_SFX, -6.0, 1.32)
	var tw := create_tween()
	tw.tween_interval(0.17)
	tw.tween_callback(_play_sfx.bind(COUNTDOWN_BEEP, -4.5, 1.65))


func _name_of_key(key: int) -> String:
	if _contestants.has(key):
		return str((_contestants[key] as Dictionary).get("name", "KART"))
	return "KART"


func _planar_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ==========================================================================
# HEADLESS SELF-TEST (`CART_BOMB_SELFTEST=1`)
# ==========================================================================


func _run_self_test() -> void:
	## Verifies all 3 Blast Tag 3D maps (`bt_plaza`, `bt_labyrinth`, `bt_ferries`),
	## WORLD StaticBody3D colliders (0 missing shapes, 0 orphan shapes), BoostPad
	## placement, Carrier Panic Overdrive, Ram-Pass transfer (+1 PT + 1.8 s Cyan
	## Immunity Shield), Runner Juke Surge, Detonation Shockwave (+2 PTS survivor
	## scoring + leader catch-up wave), and HUD bounds at 1280x720 and 960x540.
	print("BOMB_SELFTEST step=boot arena=%s bots=%d contestants=%d"
		% [_arena_id, _bots.size(), _contestants.size()])
	await get_tree().physics_frame

	# 1. Build & verify all 3 maps cleanly!
	for map_id: String in BombTagMaps.ids():
		var stage := Node3D.new()
		stage.name = "SelftestStage_" + map_id
		stage.position = Vector3(0.0, 250.0, 0.0)
		add_child(stage)
		var info: Dictionary = BombTagMaps.build_arena(stage, map_id)
		await get_tree().physics_frame

		var spawns_arr: Variant = info.get("spawns", [])
		var boosts_arr: Variant = info.get("boost_spots", [])
		var pillars_arr: Variant = info.get("pillars", [])
		var spawn_n: int = (spawns_arr as Array).size() if spawns_arr is Array else 0
		var boost_n: int = (boosts_arr as Array).size() if boosts_arr is Array else 0
		var pillar_n: int = (pillars_arr as Array).size() if pillars_arr is Array else 0

		var solids: int = 0
		var total_shapes: int = 0
		var missing_shapes: int = 0
		var world_ok: bool = true
		for node: Node in stage.find_children("*", "StaticBody3D", true, false):
			var sb := node as StaticBody3D
			solids += 1
			if sb.collision_layer != CollisionLayers.WORLD:
				world_ok = false
			var sc: int = 0
			for ch: Node in sb.get_children():
				if ch is CollisionShape3D and (ch as CollisionShape3D).shape != null:
					sc += 1
			total_shapes += sc
			if sc == 0:
				missing_shapes += 1

		var orphans: int = 0
		for node: Node in stage.find_children("*", "CollisionShape3D", true, false):
			if not (node.get_parent() is CollisionObject3D):
				orphans += 1

		var live_pads: int = stage.find_children("ArenaBoostPad_*", "Area3D", true, false).size()
		print("BOMB_SELFTEST step=map id=%s solids=%d shapes=%d spawns=%d boosts=%d/%d pillars=%d world_ok=%s orphans=%d"
			% [map_id, solids, total_shapes, spawn_n, live_pads, boost_n,
			pillar_n, str(world_ok), orphans])

		stage.queue_free()
		await get_tree().physics_frame

		if solids == 0 or total_shapes == 0 or missing_shapes > 0 or not world_ok or orphans > 0:
			_fail_selftest("map %s failed collider audit" % map_id)
			return
		if spawn_n < 8 or boost_n < 4 or live_pads != boost_n:
			_fail_selftest("map %s missing spawns or boost pads" % map_id)
			return

	# 2. Verify live gameplay mechanics: Overdrive, Ram-Pass, Juke Surge & Detonation!
	if _bots.size() < 2 or _cart == null:
		_fail_selftest("insufficient karts for gameplay proof")
		return

	var key_a: int = _local_key()
	var key_b: int = _bot_key(0)
	var key_c: int = _bot_key(1)
	var cart_a: CartPlayer = _cart_for_key(key_a)
	var cart_b: CartPlayer = _cart_for_key(key_b)
	var cart_c: CartPlayer = _cart_for_key(key_c)

	# Pause rival AI steering briefly during exact contact placement by parking far bots
	# and placing A & B on flat plaza ground.
	_bombs[0]["active"] = true
	_bombs[0]["carrier"] = key_a
	_bombs[0]["fuse"] = 1.10 ## Below 1.5s floor so Ram-Pass must clamp fuse >= 1.5s!
	_bombs[0]["lock"] = 0.0
	_bombs[1]["active"] = false
	for k: int in [key_a, key_b, key_c]:
		var cd: Dictionary = _contestants[k] as Dictionary
		cd["points"] = 0
		cd["passes"] = 0
		cd["survivals"] = 0
		cd["shield_timer"] = 0.0
		cd["juke_cooldown"] = 0.0

	var base_spd_a: float = float((_base_stats[cart_a.get_instance_id()] as Dictionary)["max_speed"])
	await get_tree().physics_frame
	if cart_a.max_speed < base_spd_a * 1.15:
		_fail_selftest("carrier panic overdrive did not boost max_speed")
		return

	# Place B within 1.6 m XZ of A on isolated spawn[0], parking all other bots far away!
	for extra_i in range(2, _bots.size()):
		var extra_c: CartPlayer = _bots[extra_i].get("cart") as CartPlayer
		if extra_c != null and is_instance_valid(extra_c):
			extra_c.global_position = _spawns[5 + (extra_i % 2)].origin
			extra_c.velocity = Vector3.ZERO

	var anchor: Vector3 = _spawns[0].origin
	cart_a.global_position = anchor
	cart_a.velocity = Vector3.ZERO
	cart_b.global_position = anchor + Vector3(1.6, 0.0, 0.0)
	cart_b.velocity = Vector3.ZERO
	cart_c.global_position = _spawns[2].origin
	cart_c.velocity = Vector3.ZERO

	await get_tree().physics_frame
	await get_tree().physics_frame

	var cd_a: Dictionary = _contestants[key_a] as Dictionary
	if int(_bombs[0]["carrier"]) != key_b:
		_fail_selftest("ram-pass did not transfer bomb from A to B")
		return
	if int(cd_a["points"]) != PASS_POINTS or int(cd_a["passes"]) != 1:
		_fail_selftest("passer did not receive +1 PT")
		return
	if float(cd_a["shield_timer"]) <= 1.0:
		_fail_selftest("passer did not receive cyan immunity shield")
		return
	if float(_bombs[0]["fuse"]) < 1.35:
		_fail_selftest("ram-pass did not apply 1.5s fair fuse floor")
		return
	print("BOMB_SELFTEST step=ram_pass holder=%d passer_pts=%d shield=%.2f fuse=%.2f"
		% [int(_bombs[0]["carrier"]), int(cd_a["points"]),
		float(cd_a["shield_timer"]), float(_bombs[0]["fuse"])])

	# Test Runner Juke Surge on unbombed kart C.
	var juked: bool = _trigger_juke(key_c, 1.0, false)
	var cd_c: Dictionary = _contestants[key_c] as Dictionary
	if not juked or float(cd_c["juke_cooldown"]) < 4.5:
		_fail_selftest("runner juke surge failed")
		return
	print("BOMB_SELFTEST step=juke_surge cooldown=%.2f" % float(cd_c["juke_cooldown"]))

	# Isolate B at spawn[4] and set fuse to 0.01s so detonation fires on the next tick!
	cart_b.global_position = _spawns[4].origin
	cart_b.velocity = Vector3.ZERO
	_bombs[0]["fuse"] = 0.01
	_bombs[0]["lock"] = 0.25
	for _f in 6:
		await get_tree().physics_frame
		if not bool(_bombs[0]["active"]):
			break

	if bool(_bombs[0]["active"]):
		_fail_selftest("mega-bomb did not detonate at 0.0s")
		return
	if cart_b.velocity.y < 3.0:
		_fail_selftest("detonated holder was not launched upward")
		return
	# Passer A had 1 PT + 2 survivor PTS = 3 PTS; Runner C had 0 + 2 = 2 PTS; Victim B = 0 PTS!
	if int(cd_a["points"]) != PASS_POINTS + SURVIVE_POINTS or int(cd_c["points"]) < SURVIVE_POINTS:
		_fail_selftest("detonation survivor scoring mismatch (A=%d C=%d)"
			% [int(cd_a["points"]), int(cd_c["points"])])
		return
	print("BOMB_SELFTEST step=detonate pts_a=%d pts_b=%d pts_c=%d breather=%.2f"
		% [int(cd_a["points"]), int((_contestants[key_b] as Dictionary)["points"]),
		int(cd_c["points"]), _wave_breather])

	# Verify Catch-Up Wave spawns next Mega-Bomb onto highest-scoring leader (key_a = 3 PTS)!
	_wave_breather = 0.02
	for _f in 4:
		await get_tree().physics_frame
		if bool(_bombs[0]["active"]):
			break
	if int(_bombs[0]["carrier"]) != key_a:
		_fail_selftest("next wave did not target highest-scoring kart (got %d expected %d)"
			% [int(_bombs[0]["carrier"]), key_a])
		return
	print("BOMB_SELFTEST step=catchup_spawn leader=%d" % int(_bombs[0]["carrier"]))

	# 3. Verify HUD layout & zero clipping at 1280x720 AND 960x540!
	_refresh_hud()
	_layout_hud()
	await get_tree().process_frame
	var clip_720: bool = _hud_clips_for_size(Vector2(1280.0, 720.0))
	var clip_540: bool = _hud_clips_for_size(Vector2(960.0, 540.0))
	print("BOMB_SELFTEST step=hud clip_1280x720=%s clip_960x540=%s"
		% [str(clip_720), str(clip_540)])
	if clip_720 or clip_540:
		_fail_selftest("hud clipped at 1280x720 or 960x540")
		return

	print("BOMB_SELFTEST step=pass maps=3 pass_pts=%d surv_pts=%d"
		% [PASS_POINTS, SURVIVE_POINTS])
	get_tree().quit(0)


func _fail_selftest(reason: String) -> void:
	push_error("BOMB_SELFTEST FAIL: " + reason)
	print("BOMB_SELFTEST step=fail reason=" + reason)
	get_tree().quit(1)
