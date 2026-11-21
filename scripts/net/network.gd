extends Node
## Multiplayer session manager.
##
## There are exactly two ways to start a multiplayer world:
##   1. HOST LAN  - this PC is the server; players on the same Wi-Fi find it.
##   2. HOST PI   - this PC registers with the Cart Slop Pi, which returns a
##                  5-letter room code. Clients join with that code only.
## Joining never accepts an IP address or a hand-built address code. A room
## join always goes through the Pi server (or the LAN host that advertises
## itself as a server).

signal host_started(code: String)
signal host_failed(reason: String)
signal join_status_changed(text: String)
signal join_succeeded()
signal join_failed(reason: String)
signal session_ended(reason: String)
signal peers_changed()
signal names_changed()
## Host -> everyone: the ALPHA/BETA split changed, so team columns redraw.
signal teams_changed()
signal latency_changed(ms: int)
signal code_updated(code: String)
signal session_config_changed()
signal server_status_changed(online: bool, detail: String)
signal tag_colors_changed()
signal vehicles_changed()
signal ping_table_changed()
## Smoothed HTTP round trip to the relay. Emitted only when the value changes.
signal relay_metrics_changed(rtt_ms: int, jitter_ms: int)
## Host -> Pi race state stream: whether /api/race/pos is acknowledging batches
## and how many batches it has accepted for the current race.
## Host -> Pi live position batch cadence / acknowledgement.
signal race_state_stream_changed(receiving: bool, updates: int)
## Client-side notification that the host has entered `scene_path` and can
## accept scene-level RPCs without "Node not found" errors.
signal host_scene_ready(scene_path: String)

const DEFAULT_PORT: int = 8910
const PORT_RANGE: int = 40
const MAX_PLAYERS: int = 8
const GAME_SCENE: String = "res://scenes/sandbox/sandbox.tscn"
const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const CARGO_SCENE: String = "res://scenes/minigames/cargo_rush.tscn"
const KNOCKOUT_SCENE: String = "res://scenes/minigames/knockout.tscn"
const BOMB_TAG_SCENE: String = "res://scenes/minigames/bomb_tag.tscn"
## A MINIGAMES room runs one of the four party/racing modes. The event is
## part of the session config so every peer picks the host's scene; it is never
## inferred from a client's own saved menu pick.
const EVENT_RACE: String = "race"
const EVENT_CARGO: String = "cargo"
const EVENT_KNOCKOUT: String = "knockout"
const EVENT_BOMB_TAG: String = "bomb_tag"
const MINIGAME_EVENTS: Array[String] = [
	EVENT_CARGO,
	EVENT_KNOCKOUT,
	EVENT_BOMB_TAG,
]
## Two symmetric sides. 0 = ALPHA (blue), 1 = BETA (red).
const TEAM_COUNT: int = 2
const TEAM_NAMES: PackedStringArray = ["ALPHA", "BETA"]
const VEHICLE_MODE_PICK_OWN: String = "pick_own"
const VEHICLE_MODE_SHARED: String = "shared"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const PING_INTERVAL: float = 2.0
const RELAY_DISCOVERY_PORT: int = 42778
const LAN_ROOM_PORT: int = 42779
const RELAY_HEARTBEAT_INTERVAL: float = 10.0
## A slow Pi can miss a heartbeat or two without the room being gone. A
## definite 404/410 still ends the lobby quickly; timeouts get more attempts.
const HEARTBEAT_MAX_FAILURES: int = 4
const HEARTBEAT_TIMEOUT: float = 8.0
## Relay latency sampling (host ping / client clock probe) and its smoothing.
const RELAY_PROBE_INTERVAL: float = 8.0
const RELAY_RTT_ALPHA: float = 0.25
const RELAY_JITTER_ALPHA: float = 0.2
## Relay tunnel supervisor: rebuild a dead tunnel with exponential backoff.
const TUNNEL_RETRY_BASE: float = 2.0
const TUNNEL_RETRY_MAX: float = 30.0
## HTTPRequest objects are pooled: the race state stream posts ten times a
## second and must not allocate a node per packet.
const HTTP_POOL_MAX: int = 6
const STATE_POST_TIMEOUT: float = 3.0
const COLLISION_SOLVER_PATH: String = "res://scripts/systems/cart_collision.gd"
## First-pass discovery window. A healthy LAN Pi or LAN room host answers in a
## few milliseconds, so a short window keeps the lobby snappy.
const DISCOVERY_TIMEOUT_MS: int = 1200
## macOS 15+ Local Network privacy can DENY the first broadcast while the
## system alert is still on screen (Apple TN3179 explicitly tells apps to add
## retry logic because an operation may be refused before the user answers).
## A single 1.2 s window therefore finds nothing on a freshly installed Mac.
## Only macOS pays for the longer window: Windows/Linux keep the fast path.
const DISCOVERY_TIMEOUT_MACOS_MS: int = 6000
## How often the discovery broadcast is repeated while waiting. UDP is lossy
## and the macOS permission alert needs more than one attempt to get through.
const DISCOVERY_NUDGE_MS: int = 450
## Same macOS permission race for a direct LAN ENet connect: ENet gives up on
## the handshake long before a player has read the system alert.
const JOIN_TIMEOUT_MS: int = 12000
const JOIN_TIMEOUT_MACOS_MS: int = 30000
## A public LAN room re-broadcasts its own advertisement (instead of waiting to
## be asked) so macOS shows the Local Network prompt while the host is still in
## the lobby, and clients find the room without a request round trip.
const LAN_BEACON_INTERVAL: float = 1.5
## How many one-shot warm-up discovery probes a LAN host sends at startup even
## for a PRIVATE room: receiving an incoming broadcast also needs local network
## access on macOS, so the host must trigger its own permission prompt or it
## can never hear a joining client.
const LAN_WARMUP_PROBES: int = 3
const LAN_WARMUP_INTERVAL: float = 1.0
const RELAY_HTTP_TIMEOUT: float = 4.0
## Built-in relay address, used for internet joins when LAN discovery finds
## nothing. It is never shown to the player and never typed into a field;
## CARTSLOP_RELAY can point a build at a different relay for testing.
const DEFAULT_RELAY_SERVER: String = "68.204.45.1:42777"
const ROOM_CODE_ALPHABET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const ALLOWED_SCENES: Array[String] = [
	GAME_SCENE,
	RACE_SCENE,
	CARGO_SCENE,
	KNOCKOUT_SCENE,
	BOMB_TAG_SCENE,
]
const MAX_BOT_COUNT: int = 5
const MAX_LOBBY_ENTRIES: int = 200
const MAX_HTTP_BODY: int = 1024 * 1024
const RelayTunnel := preload("res://scripts/net/relay_tunnel.gd")
const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")

# A reliable scene-start message can land before the client has finished
# changing scenes. Retry for any peer that has not announced ready, but keep
# the retry bounded: a peer stuck in the lobby must not be spammed forever.
const SCENE_RETRY_INTERVAL: float = 1.0
const SCENE_RETRY_MAX: int = 16
const WORLD_BOUND_SQ: float = 5000.0 * 5000.0
## Maximum believable body speed for solver input. The game's boost cap is
## ~26 m/s; a larger finite value is corruption/desync and is clamped rather
## than fed raw into an impulse (which would become a teleport-sized shove).
const MAX_CART_SPEED: float = 64.0
## Remote drift marks. The ghost state packet already carries the owner's
## velocity as an optional trailing field (an older peer that omits it sends
## Vector3.ZERO), so the receiving peer rebuilds the minimum slide state from
## it: lateral slip is the velocity projected on the ghost's right axis - the
## same quantity the local physics calls lat_speed. No extra packet field, no
## second RPC and no bandwidth cost.
## Slip is capped at the receive clamp in player_cart.set_net_state() (60 m/s);
## the drift threshold itself is read from the ghost (drift_detection_threshold)
## instead of being duplicated here.
const GHOST_SLIP_CAP: float = 60.0
## Planar speed floor for a ghost mark. Mirrors skid_trail's min_speed default
## so a ghost that is merely rolling leaves nothing, exactly like a local cart.
const GHOST_SKID_MIN_SPEED: float = 3.0
## Pair keys pack two peer ids into one int: low id in the high word, high id
## in the low word. This avoids formatting a String per contacting pair per tick.
const PAIR_ID_SHIFT: int = 32
const PAIR_ID_MASK: int = 0xFFFFFFFF

var is_host: bool = false
var is_client: bool = false
var in_game: bool = false
var join_code: String = ""
var local_address: String = ""
## Every usable LAN IPv4 address on this machine, best first (see
## _lan_address_candidates()). A Mac can be on Wi-Fi, Ethernet and a VPN at the
## same time; no single "the local IP" answer is reachable by every friend, so
## discovery uses them all and the Pi registration uses the one on the relay's
## subnet. Kept public-friendly for the lobby/debug output.
var local_addresses: PackedStringArray = PackedStringArray()
## "macos_local_network" when discovery found nothing on a Mac. The lobby/room
## browser turns this into a System Settings hint instead of a dead-end.
var discovery_hint: String = ""
var public_address: String = ""
var port: int = DEFAULT_PORT
var latency_ms: int = 0
## Host-only: round trip from this machine to the relay (the actual server).
## A host directly serving on the LAN keeps this at 0.
var host_ping_ms: int = 0
var last_error: String = ""
var connection_mode: String = "pi" ## "lan" (this PC) or "pi" (room service).
var player_names: Dictionary = {} ## peer id -> sanitized display name
var player_colors: Dictionary = {} ## peer id -> name tag Color
var player_vehicles: Dictionary = {} ## peer id -> { sandbox, racing, minigame, racer_color, allocation }
var ping_table: Dictionary = {} ## peer id -> that peer's ping to the server (ms)
var join_pending: bool = false
var room_state: String = "lobby" ## "lobby" | "playing" | "finished"
## Host's room discovery setting. Private rooms are joinable by code only;
## public rooms appear in the browser and can be joined with one click.
var room_public: bool = false
## Set while a multiplayer pause menu is open so the live world cannot keep
## driving/boosting from mouse or keyboard input behind the menu.
var input_locked: bool = false
var server_online: bool = false
## Version string reported by the Pi and the monotonic offset used to put every
## client on the server's clock (see sync_server_clock()).
var server_version: String = ""
var server_clock_offset_ms: int = 0
var server_clock_ready: bool = false
var server_rtt_ms: int = 0
## Smoothed HTTP round trip and jitter to the relay. The host refreshes this
## from its existing ping probe; a client probes /api/time every few seconds.
## A LAN session keeps both at 0 because there is no HTTP relay in the path.
var relay_rtt_ms: int = 0
var relay_jitter_ms: int = 0
var _clock_sync_pending: bool = false
var server_detail: String = "checking"
## Host -> Pi live position stream (server race on a 1.6.1+ relay).
## `race_state_updates` counts acknowledged batches; the race HUD uses it as
## proof that the server is receiving state.
var race_state_updates: int = 0
var race_state_receiving: bool = false
var race_state_stream_enabled: bool = true
var race_state_last_status: int = 0
## Peers that have loaded the current gameplay scene. Gameplay RPCs are only
## sent to these peers; otherwise a peer still in the lobby makes Godot log
## "Node not found: Sandbox" for every 20 Hz state packet.
var scene_ready_peers: Dictionary = {}
## Peers that deliberately returned to the lobby. The host must not keep
## forcing them back into a race they chose to leave.
var _left_scene_peers: Dictionary = {}
var _scene_sync_timer: float = 0.0
var _scene_load_path: String = ""
var host_scene_ready_path: String = ""
var _active_scene_node: Node = null
var _active_scene_path: String = ""
## Pair key -> last solver impulse time. Rate-limits resting contact and
## duplicate remote impacts while a state packet is still in flight.
var _separation_ms: Dictionary = {}
var _impact_ms: Dictionary = {}
## Pair key -> closing speed of the last accepted impact. While a pair stays
## in contact, a state packet that replays the pre-impact velocity must not be
## charged as a brand-new hit (the old code fired again every 100 ms).
var _impact_closing: Dictionary = {}
## Last finite, in-bounds contact pose per peer id. A corrupt or out-of-bounds
## report is replaced from here (never silently dropped) before the car-vs-car
## solver sees a position.
var _last_good_position: Dictionary = {}
## Wall-clock stamp of the last stale-key sweep (see _prune_separation_ms).
var _separation_prune_ms: int = 0
var relay_base: String = ""
var relay_lan_ip: String = ""
var relay_token: String = ""
var relay_port: int = 0
var relay_lan_host: String = ""
var relay_public_host: String = ""
var relay_active: bool = false
var relay_room_code: String = ""
## Optional relay address (hostname, IP, or URL) used for internet joins.
var relay_server_url: String = ""
var relay_server_host: String = ""
var relay_server_http_port: int = 42777
var relay_base_public: bool = false
var relay_tunnel_token: String = ""
var relay_tunnel_port: int = 0
var relay_tunnel_active: bool = false
var _relay_tunnel: Node = null
var _lan_listener: PacketPeerUDP = null
var _relay_forced: bool = false
## HTTP status of the last completed relay call. Callers read it immediately
## after their own await (single-threaded signal resume), which lets the
## heartbeat tell a slow Pi (timeout) from an expired room (404).
var _relay_http_status: int = 0
var _http_idle: Array[HTTPRequest] = []
var _relay_probe_timer: float = 0.0
var _relay_probe_pending: bool = false
var _relay_rtt_ema: float = -1.0
var _relay_jitter_ema: float = 0.0
var _relay_last_rtt: float = -1.0
var _race_state_busy: bool = false
var _race_state_generation: int = 0
var _race_state_failures: int = 0
var _tunnel_retry_timer: float = -1.0
var _tunnel_retry_attempt: int = 0
var _collision_solver: Variant = null
var _collision_solver_checked: bool = false
## LAN host advertisement/permission warm-up state (see _lan_beacon_tick()).
var _lan_beacon_timer: float = -1.0
var _lan_warmup_left: int = 0
var _lan_warmup_timer: float = 0.0
## Bounded macOS LAN-join permission retry: the first ENet attempt can be
## refused while the Local Network alert is on screen, so retry once after it
## is likely answered instead of making the player rescan.
var _lan_join_retry: int = 0
var _lan_join_host: String = ""
var _lan_join_port: int = 0
## Sleep/wake detection: engine ticks can stall across a laptop lid close while
## the wall clock (and the Pi's clock) keeps moving.
var _last_tick_ms: int = 0
var _last_wall_ms: int = 0
var _suspend_count: int = 0
## HTTPRequest.Result of the last relay call. 0 is RESULT_SUCCESS; a TLS
## handshake failure and a timeout both leave the HTTP status at 0, so the
## result is what lets the lobby say "secure connection failed" instead of
## pretending the whole server is offline.
var _relay_http_result: int = 0

## Host-chosen configuration, broadcast with _net_begin_game so every peer
## loads the same world with the same bots. Clients never write these locally.
var game_scene: String = GAME_SCENE
var session_mode: String = GameSettings.GAME_SANDBOX
var session_bots: bool = false
var session_bot_count: int = 0
var session_bot_difficulty: int = 1
## Event selection is separate from both the race map and Cargo arena theme.
var session_event: String = EVENT_RACE ## EVENT_RACE or EVENT_CARGO when mode is MINIGAMES.
## The exact gameplay scene the host will load: GAME_SCENE, RACE_SCENE or
## CARGO_SCENE. Replicated in the session config so a join can never land on a
## race when the host chose DELIVER (or the reverse).
var session_scene: String = GAME_SCENE
var session_minigame: String = ""
## Host-owned assignments survive individual departures and lobby returns.
## Only leave()/a brand-new session clears them; never derive teams from order.
var _peer_teams: Dictionary = {} ## peer id -> 0 (ALPHA / blue) or 1 (BETA / red)
## Auto-balance is on by default. The host locks the current split when the
## room should keep manual teams; joins/leaves then never move anyone.
var teams_locked: bool = false
## Last map/theme the host picker wrote, so configure_session can tell a new
## DELIVER pick from a new RACE pick without a second settings field. Cleared
## by leave(); this is menu bookkeeping, not replicated state.
var _last_pick_map: String = ""
var _last_pick_theme: String = ""
## Set the moment GameSettings writes a picker value (session_changed), before
## the menu calls configure_session. Without it, re-picking the same DELIVER
## theme after a race picked looked like "nothing changed".
var _pending_event: String = ""
## The last picker action this machine made (EVENT_RACE or EVENT_CARGO). It
## survives leave() so re-hosting defaults to the game the host actually chose
## last, instead of guessing from a possibly stale cargo theme.
var _last_pick_event: String = ""
## Registry id (TrackDefs) of the track the host will race on. Sanitised on
## both send and receive; it is always an id, never a scene path.
var session_map_id: String = TrackDefs.DEFAULT_ID
## Host-chosen racing chassis and stat build, relayed with the session config
## exactly like session_map_id. Every peer composes its racing cart from these
## numbers, so a client's local physics and the host's ghost copy agree on
## mass. Both fields are sanitised on send and on receive; an empty value means
## "not supplied" and falls back to the peer's own saved build, which keeps a
## peer that does not carry the field working.
var session_racing_car_id: String = ""
var session_racing_allocation: Dictionary = {}
## Host-controlled room vehicle policy: "pick_own" lets every player choose
## their own Garage vehicle, PRO RACER paint & racing tune; "shared" puts
## everyone into the host's vehicle & tune.
var session_vehicle_mode: String = VEHICLE_MODE_PICK_OWN
var session_shared_vehicle: String = VehicleCatalog.DEFAULT_ID
var session_shared_racer_color: String = "e63946"
var race_standings: Array[Dictionary] = [] ## peer id/name/time/place, filled by the race.

var _peer: ENetMultiplayerPeer
var _host_ticket: int = 0
var _join_ticket: int = 0
var _ping_timer: float = 0.0
var _host_ping_pending: bool = false
var _ping_last_broadcast_ms: int = -100000
var _ping_last_table: Dictionary = {}
var _join_started_ms: int = 0
var _relay_heartbeat: float = 0.0
var _relay_busy: bool = false
var _heartbeat_failures: int = 0
## Shared seed for a race's bot field, generated by the host and sent with
## _net_begin_game so every peer builds the same names, cars and placements.
var race_seed: int = 0

## Bounded, idempotent scene-start retries.
var _scene_retry_counts: Dictionary = {} ## peer id -> retry count



func _rpc_sender() -> int:
	## RPCs can still be queued when a peer is tearing down; never dereference
	## a null multiplayer peer.
	return multiplayer.get_remote_sender_id() if multiplayer.multiplayer_peer != null else 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# There is no user-configurable server address. Tests may call
	# set_relay_server() explicitly, but saved legacy values are ignored.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	# The map/arena picker writes GameSettings before it calls
	# configure_session(). Listening to the write itself catches a second
	# DELIVER pick of the same theme, which a value diff alone would miss.
	GameSettings.session_changed.connect(_on_settings_session_changed)
	# Baseline the picker snapshot from the saved settings, so a bot-count or
	# visibility change can never look like a new map/arena pick.
	_last_pick_map = GameSettings.selected_map
	_last_pick_theme = GameSettings.selected_minigame
	# Baseline the suspend detector here (not in an initialiser) so a long
	# editor pause before the first frame cannot look like a system sleep.
	_last_tick_ms = Time.get_ticks_msec()
	_last_wall_ms = int(Time.get_unix_time_from_system() * 1000.0)


func _process(delta: float) -> void:
	_check_suspend()
	_poll_lan_listener()
	_lan_beacon_tick(delta)
	_relay_heartbeat_tick(delta)
	_relay_tunnel_retry_tick(delta)
	# macOS needs the longer join window because the first LAN connect can sit
	# behind the Local Network permission alert (see DISCOVERY_TIMEOUT_MACOS_MS).
	var join_timeout: int = JOIN_TIMEOUT_MACOS_MS if _is_macos() else JOIN_TIMEOUT_MS
	if join_pending and Time.get_ticks_msec() - _join_started_ms > join_timeout:
		join_pending = false
		var was_lan: bool = connection_mode == "lan"
		leave()
		join_failed.emit(_join_timeout_reason(was_lan))
		return
	if not is_session_active() or not is_connected_to_server():
		return
	_scene_sync_timer += delta
	if is_host and in_game and _scene_sync_timer >= SCENE_RETRY_INTERVAL:
		_scene_sync_timer = 0.0
		_host_retry_scene_start()
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		if not is_host:
			rpc_id(1, "_net_ping", Time.get_ticks_msec())
		elif connection_mode == "pi" and relay_base != "":
			# The room is relayed through the Pi, so the host's real ping is its
			# round trip to that server, not 0.
			_measure_host_ping()
	if is_client and not is_host and relay_base != "":
		# The host already probes every 2 s. Clients need their own sample for
		# the server ping HUD and the adaptive bot poll interval.
		_relay_probe_timer += delta
		if _relay_probe_timer >= RELAY_PROBE_INTERVAL:
			_relay_probe_timer = 0.0
			_probe_relay_latency()


func _host_retry_scene_start() -> void:
	## Re-send the current game start to peers that have not announced scene
	## readiness yet. Each peer gets a fixed retry budget; after that we stop
	## and leave it to a fresh ready RPC or a reconnect. This keeps a peer that
	## is still in the lobby from being pounded by reliable packets forever.
	for peer_id: int in multiplayer.get_peers():
		if scene_ready_peers.has(peer_id):
			_scene_retry_counts.erase(peer_id)
			continue
		if _left_scene_peers.has(peer_id):
			# The player chose to go back to the lobby. Forcing the race back
			# onto them would yank them out of the menu every five seconds.
			continue
		var attempts: int = int(_scene_retry_counts.get(peer_id, 0))
		if attempts >= SCENE_RETRY_MAX:
			continue
		_scene_retry_counts[peer_id] = attempts + 1
		rpc_id(peer_id, "_net_begin_game", game_scene, session_mode,
			session_bots, session_bot_count, race_seed)
		if host_scene_ready_path == game_scene and host_scene_ready_path != "":
			rpc_id(peer_id, "_net_host_scene_ready", host_scene_ready_path)


func is_session_active() -> bool:
	return is_host or is_client


func bot_difficulty() -> int:
	return clampi(session_bot_difficulty if is_session_active() \
		else GameSettings.minigame_difficulty, 0, 2)


func clear_scene_ready() -> void:
	input_locked = false
	scene_ready_peers.clear()
	_left_scene_peers.clear()
	_scene_retry_counts.clear()
	_separation_ms.clear()
	_impact_ms.clear()
	_impact_closing.clear()
	_last_good_position.clear()
	_scene_load_path = ""
	host_scene_ready_path = ""
	_active_scene_node = null
	_active_scene_path = ""
	if is_host:
		scene_ready_peers[1] = true


func is_scene_ready(peer_id: int) -> bool:
	return scene_ready_peers.has(peer_id)


func mark_peer_scene_ready(peer_id: int) -> void:
	if is_host and peer_id > 0:
		scene_ready_peers[peer_id] = true
		_left_scene_peers.erase(peer_id)


func _cart_extents(cart: Node) -> Dictionary:
	## Solver geometry must always be finite and positive, whatever a ghost's
	## vehicle table says. Clamp to the catalog's real envelope, not to infinity.
	var raw: Dictionary = {}
	if cart.has_method("get_collision_extents"):
		var value: Variant = cart.call("get_collision_extents")
		if value is Dictionary:
			raw = value as Dictionary
	return {
		"width": clampf(_finite_or(float(raw.get("width", 1.50)), 1.50), 0.5, 4.0),
		"length": clampf(_finite_or(float(raw.get("length", 2.26)), 2.26), 1.0, 5.0),
		"height": clampf(_finite_or(float(raw.get("height", 1.70)), 1.70), 0.5, 4.0),
	}


func _finite_or(value: float, fallback: float) -> float:
	return value if is_finite(value) else fallback


func _shared_collision_solver() -> Variant:
	## Loaded lazily and cached: the shared solver may not exist while another
	## workstream is still landing it, and load() must not run every tick.
	if not _collision_solver_checked:
		_collision_solver_checked = true
		_collision_solver = load(COLLISION_SOLVER_PATH)
	return _collision_solver


func _cart_velocity_value(cart: Node) -> Vector3:
	## Raw velocity property (the shared solver writes this on every body).
	## get_collision_velocity() returns net_velocity for a remote ghost, which
	## the solver deliberately leaves untouched while it resolves the ghost.
	## Sanitise here: a single NaN body velocity must not poison the pair.
	var value: Variant = cart.get("velocity")
	if not (value is Vector3):
		return Vector3.ZERO
	var raw: Vector3 = value as Vector3
	return raw.limit_length(MAX_CART_SPEED) if raw.is_finite() else Vector3.ZERO


func _collision_velocity_of(cart: Node) -> Vector3:
	## Velocity used for the closing-speed test. A ghost advertises its
	## authoritative net_velocity through get_collision_velocity(); a local
	## body exposes its physics velocity directly. Never return a value the
	## solver can turn into an absurd impulse.
	if cart.has_method("get_collision_velocity"):
		var value: Variant = cart.call("get_collision_velocity")
		if value is Vector3:
			var velocity: Vector3 = value as Vector3
			return velocity.limit_length(MAX_CART_SPEED) \
				if velocity.is_finite() else Vector3.ZERO
	return _cart_velocity_value(cart)


static func ghost_slide_state(yaw: float, velocity: Vector3) -> Vector2:
	## (lateral slip speed, planar speed) for a remote ghost, rebuilt from the
	## velocity already in its state payload. Slip is the absolute velocity
	## projected on the ghost's right axis - the same number the local physics
	## calls lat_speed - so a ghost and its owner agree on what a drift is.
	## Finite-checked and bounded on receive: a corrupt, stale or absent
	## velocity resolves to Vector2.ZERO, which leaves no mark and logs nothing.
	if not is_finite(yaw) or not velocity.is_finite():
		return Vector2.ZERO
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	if not planar.is_finite():
		return Vector2.ZERO
	var right: Vector3 = Basis(Vector3.UP, wrapf(yaw, -PI, PI)) * Vector3.RIGHT
	var slip: float = absf(planar.dot(right))
	var speed: float = planar.length()
	if not is_finite(slip) or not is_finite(speed):
		return Vector2.ZERO
	return Vector2(clampf(slip, 0.0, GHOST_SLIP_CAP),
		clampf(speed, 0.0, MAX_CART_SPEED))


static func ghost_skid_active(slide: Vector2, slip_threshold: float) -> bool:
	## True while a ghost slides hard enough to mark. The threshold is the
	## ghost's own drift_detection_threshold (2.0 m/s by default), read at
	## receive time so the remote and local paths cannot drift apart. A slip
	## of zero - the old-peer case - is always a clean "no marks".
	if not slide.is_finite() or not is_finite(slip_threshold):
		return false
	# Strict comparisons, matching player_cart's own tests: lat_speed must
	# exceed drift_detection_threshold and the planar speed must exceed the
	# ribbon's min_speed floor.
	return slide.x > maxf(slip_threshold, 0.5) \
		and slide.y > GHOST_SKID_MIN_SPEED


func _cart_mass(cart: Node) -> float:
	## Must match CartCollision._body_mass so the delta-v computed from the
	## solver's scalar impulse is exactly the one it applied locally.
	if cart.has_method("get_mass"):
		var value: Variant = cart.call("get_mass")
		if value is float or value is int:
			var mass: float = float(value)
			if is_finite(mass) and mass > 0.0:
				return mass
	return 1200.0


func _pair_key(id_a: int, id_b: int) -> int:
	## Stable pair key without a per-tick String allocation.
	return (mini(id_a, id_b) << PAIR_ID_SHIFT) \
		| (maxi(id_a, id_b) & PAIR_ID_MASK)


func _contact_position(peer_id: int, cart: Node, rendered: Vector3) -> Vector3:
	## Solver-safe contact pose, and the reason a bad packet does not drop a
	## pair: an invalid raw value is replaced, never skipped.
	## A remote ghost advertises its newest accepted packet in net_position;
	## that is the freshest pose the host owns, so it wins over the lagging
	## interpolated body. A local cart uses the body it is actually simulating.
	## Fallback chain: newest packet -> rendered body -> last good pose ->
	## deterministic spawn. The value that reaches the solver is always finite
	## and inside the world; the raw value never is.
	if cart.get("remote_mode") == true:
		var net_value: Variant = cart.get("net_position")
		if net_value is Vector3:
			var net_position: Vector3 = net_value as Vector3
			if net_position.is_finite() \
					and net_position.length_squared() <= WORLD_BOUND_SQ:
				_last_good_position[peer_id] = net_position
				return net_position
	if rendered.is_finite() and rendered.length_squared() <= WORLD_BOUND_SQ:
		_last_good_position[peer_id] = rendered
		return rendered
	var cached: Variant = _last_good_position.get(peer_id)
	if cached is Vector3:
		var cached_position: Vector3 = cached as Vector3
		if cached_position.is_finite() \
				and cached_position.length_squared() <= WORLD_BOUND_SQ:
			return cached_position
	var spawn: Vector3 = spawn_position(peer_id)
	if spawn.is_finite():
		_last_good_position[peer_id] = spawn
		return spawn
	return Vector3.ZERO


func _erase_peer_separation(peer_id: int) -> void:
	## Drop pair throttle stamps that mention a departed peer. Peer churn used
	## to leave keys behind for the rest of the session.
	_erase_peer_pair_keys(_separation_ms, peer_id)
	_erase_peer_pair_keys(_impact_ms, peer_id)
	_erase_peer_pair_keys(_impact_closing, peer_id)


func _erase_peer_pair_keys(stamps: Dictionary, peer_id: int) -> void:
	if stamps.is_empty():
		return
	for key: int in stamps.keys():
		var low: int = key >> PAIR_ID_SHIFT
		var high: int = key & PAIR_ID_MASK
		if low == peer_id or high == peer_id:
			stamps.erase(key)


func _prune_separation_ms(now_ms: int) -> void:
	## Contact stamps are keyed by peer pair. Peer churn (reconnects reuse new
	## ids) used to grow the dictionaries for the whole session. Sweep old keys
	## no more than every 15 s; the per-tick path stays allocation-free.
	if now_ms - _separation_prune_ms <= 15_000:
		return
	_separation_prune_ms = now_ms
	for stamps: Dictionary in [_separation_ms, _impact_ms]:
		for key: int in stamps.keys():
			if now_ms - int(stamps[key]) > 60_000:
				stamps.erase(key)
	# The closing-speed memory has no timestamp; it is cleared with the pair
	# on separation and on peer departure, so bound it to the live impact keys.
	for key: int in _impact_closing.keys():
		if not _impact_ms.has(key):
			_impact_closing.erase(key)


static func sanitize_racing_car_id(raw: String) -> String:
	## Every curated racing choice, including road vehicles, the stock cart,
	## and legacy racer color IDs normalized to "race_car", may cross the wire.
	var key: String = VehicleCatalog.normalize_id(raw.strip_edges())
	return key if VehicleCatalog.is_racing_choice(key) else ""


static func sanitize_racing_allocation(raw: Dictionary) -> Dictionary:
	## Receive/send side both pass through the catalog clamp: all four keys,
	## 0..RACING_STAT_MAX each, over-budget builds trimmed deterministically.
	if raw.is_empty():
		return {}
	return VehicleCatalog.sanitize_allocation(raw)


func _obb_contact(offset: Vector3, yaw_a: float, yaw_b: float,
		ext_a: Dictionary, ext_b: Dictionary) -> Dictionary:
	## 2D oriented-box overlap on the ground plane. The old fixed 2.40 m
	## circle fired at empty air beside a sedan and let trucks interpenetrate.
	var half_a := Vector2(float(ext_a.get("width", 1.5)) * 0.5,
		float(ext_a.get("length", 2.26)) * 0.5)
	var half_b := Vector2(float(ext_b.get("width", 1.5)) * 0.5,
		float(ext_b.get("length", 2.26)) * 0.5)
	var a_right: Vector3 = Basis(Vector3.UP, yaw_a) * Vector3.RIGHT
	var a_forward: Vector3 = Basis(Vector3.UP, yaw_a) * Vector3.FORWARD
	var b_right: Vector3 = Basis(Vector3.UP, yaw_b) * Vector3.RIGHT
	var b_forward: Vector3 = Basis(Vector3.UP, yaw_b) * Vector3.FORWARD
	var axes: Array[Vector3] = [a_right, a_forward, b_right, b_forward]
	var min_overlap: float = INF
	var best_axis: Vector3 = Vector3.ZERO
	for axis: Vector3 in axes:
		var radius_a: float = (absf(axis.dot(a_right)) * half_a.x
			+ absf(axis.dot(a_forward)) * half_a.y)
		var radius_b: float = (absf(axis.dot(b_right)) * half_b.x
			+ absf(axis.dot(b_forward)) * half_b.y)
		var distance: float = absf(offset.dot(axis))
		var overlap: float = radius_a + radius_b - distance
		if overlap <= 0.0:
			return {}
		if overlap < min_overlap:
			min_overlap = overlap
			best_axis = axis if offset.dot(axis) >= 0.0 else -axis
	if min_overlap == INF or best_axis.length_squared() < 0.001:
		return {}
	return {"normal": best_axis.normalized(), "penetration": min_overlap}


func _swept_obb_contact(cart_a: Node, cart_b: Node, offset: Vector3,
		ext_a: Dictionary, ext_b: Dictionary) -> Dictionary:
	## Conservative swept fallback for a pair that moved through itself between
	## contact samples (a prediction correction or a long 20 Hz tick). Walk the
	## pair backwards along this tick's relative motion and return the most
	## recent overlapping sample. Normal driving keeps the discrete test
	## sufficient; this only runs when that test found nothing.
	var relative: Vector3 = _collision_velocity_of(cart_a) \
		- _collision_velocity_of(cart_b)
	relative.y = 0.0
	if not relative.is_finite() or not offset.is_finite():
		return {}
	var ticks: float = float(Engine.physics_ticks_per_second)
	if not is_finite(ticks) or ticks <= 0.0:
		return {}
	var travel: float = relative.length() / ticks
	if travel < 0.25:
		return {}
	# Broad phase first: bodies further apart than both lengths plus this
	# tick's travel cannot have touched, so no probes are needed.
	var reach: float = maxf(float(ext_a.get("length", 2.26)),
		float(ext_a.get("width", 1.5))) \
		+ maxf(float(ext_b.get("length", 2.26)),
		float(ext_b.get("width", 1.5))) \
		+ travel
	if offset.length_squared() > reach * reach:
		return {}
	var probes: int = 6
	var step: Vector3 = relative / (ticks * float(probes))
	var probe: Vector3 = offset
	var yaw_a: float = cart_a.global_rotation.y
	var yaw_b: float = cart_b.global_rotation.y
	if not is_finite(yaw_a):
		yaw_a = 0.0
	if not is_finite(yaw_b):
		yaw_b = 0.0
	for i in probes:
		probe -= step
		var contact: Dictionary = _obb_contact(
			probe, yaw_a, yaw_b, ext_a, ext_b)
		if contact.is_empty():
			continue
		# Only trust a probe that still describes the current side of the
		# contact. Once the pair has swapped sides the old normal points the
		# wrong way, and the impulse would pull the two carts together.
		var probe_normal: Vector3 = contact["normal"] as Vector3
		if not probe_normal.is_finite():
			continue
		if offset.dot(probe_normal) <= 0.0:
			return {}
		return contact
	return {}


func resolve_car_collisions(local_cart: Node, remotes: Dictionary) -> void:
	## The host resolves every contact each physics tick. Momentum handles the
	## impact; the physics engine owns positional separation and the shared
	## solver owns the equal/opposite velocity exchange.
	##
	## Prop rule, explicit: solid props (crates) are STATIC obstacles on every
	## peer - a client freezes its prop bodies at the host's pose. Both sides
	## therefore run identical cart-vs-prop physics, so a client can never
	## phase through a crate the host says it hit. This resolver owns only
	## car-vs-car momentum; the host is authoritative for a pushed prop's
	## motion, never for whether a solid crate blocks.
	if not is_host or not is_instance_valid(local_cart):
		return
	var solver: Variant = _shared_collision_solver()
	var host_id: int = multiplayer.get_unique_id()
	var now_ms: int = Time.get_ticks_msec()
	_prune_separation_ms(now_ms)
	var ids: Array = remotes.keys()
	ids.sort()
	# Host vs every remote, then remote vs remote. Iterating in place avoids
	# the array-of-pairs allocation that used to run on every physics tick.
	for peer_id: Variant in ids:
		var remote: Node = remotes[peer_id] as Node
		if not is_instance_valid(remote):
			# A ghost can be queue_free()d on a peer disconnect in the same
			# frame this loop runs. Calling get()/global_position on a freed
			# instance is an engine error, so drop the entry here.
			continue
		_resolve_contact_pair(local_cart, host_id, local_cart, int(peer_id),
			remote, solver, host_id, now_ms)
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var remote_a: Node = remotes[ids[i]] as Node
			var remote_b: Node = remotes[ids[j]] as Node
			if not is_instance_valid(remote_a) or not is_instance_valid(remote_b):
				continue
			_resolve_contact_pair(local_cart, int(ids[i]), remote_a,
				int(ids[j]), remote_b, solver, host_id, now_ms)


func _resolve_contact_pair(local_cart: Node, id_a: int, cart_a: Node,
		id_b: int, cart_b: Node, solver: Variant, host_id: int,
		now_ms: int) -> void:
	# Freed bodies compare true against null in GDScript, so a stale dict entry
	# must be tested with is_instance_valid before any property read.
	if not is_instance_valid(cart_a) or not is_instance_valid(cart_b) \
			or id_a <= 0 or id_b <= 0:
		return
	# A finished or severed cart is not an obstacle by design; its owner set
	# contact_enabled=false. This is an intentional non-contact, not the
	# invalid-position fallback path below.
	if cart_a.get("contact_enabled") == false \
			or cart_b.get("contact_enabled") == false:
		return
	if id_a != host_id and not is_scene_ready(id_a):
		return
	if id_b != host_id and not is_scene_ready(id_b):
		return
	# Freshest safe poses. A NaN/Inf/out-of-bounds report falls back to the
	# newest packet, the last good pose or the deterministic spawn - the pair
	# is never silently dropped because one side sent a bad value.
	var pos_a: Vector3 = _contact_position(id_a, cart_a, cart_a.global_position)
	var pos_b: Vector3 = _contact_position(id_b, cart_b, cart_b.global_position)
	var pair_key: int = _pair_key(id_a, id_b)
	var ext_a: Dictionary = _cart_extents(cart_a)
	var ext_b: Dictionary = _cart_extents(cart_b)
	var contact_height: float = maxf(
		float(ext_a.get("height", 1.70)),
		float(ext_b.get("height", 1.70)))
	if absf(pos_b.y - pos_a.y) > contact_height * 0.95:
		# One cart is on the roof / well above the other: not a planar bump, so
		# the next planar overlap starts a fresh impact.
		_impact_ms.erase(pair_key)
		_impact_closing.erase(pair_key)
		return
	var offset: Vector3 = pos_b - pos_a
	offset.y = 0.0
	if not offset.is_finite():
		return
	var yaw_a: float = cart_a.global_rotation.y
	var yaw_b: float = cart_b.global_rotation.y
	if not is_finite(yaw_a):
		yaw_a = 0.0
	if not is_finite(yaw_b):
		yaw_b = 0.0
	var contact: Dictionary = _obb_contact(offset, yaw_a, yaw_b, ext_a, ext_b)
	if contact.is_empty():
		# Discrete overlap can miss a pair that crossed between samples (a
		# prediction correction or a long 20 Hz tick). Probe the relative
		# motion for the most recent overlapping sample.
		contact = _swept_obb_contact(cart_a, cart_b, offset, ext_a, ext_b)
		if contact.is_empty():
			# Out of contact: the next overlap is a NEW impact, not the tail of
			# the one already answered. Without this reset a pair that bounced
			# and touched again inside the cooldown lost its second hit.
			_impact_ms.erase(pair_key)
			_impact_closing.erase(pair_key)
			return
	var normal: Vector3 = contact["normal"]
	var penetration: float = float(contact["penetration"])
	if not normal.is_finite() or normal.length_squared() < 0.0001 \
			or not is_finite(penetration):
		return
	normal = normal.normalized()
	penetration = clampf(penetration, 0.0, 2.5)
	# A corrupt velocity is zeroed by _collision_velocity_of() and the pair
	# still gets its resting/positional resolution; it is never a reason to
	# drop the contact or to write the bad value into either body.
	var vel_a: Vector3 = _collision_velocity_of(cart_a)
	var vel_b: Vector3 = _collision_velocity_of(cart_b)
	var relative: Vector3 = vel_a - vel_b
	var closing: float = maxf(relative.dot(normal), 0.0)
	if not is_finite(closing):
		closing = 0.0
	if closing < 0.08:
		# Resting overlap is positional, not an impact. The physics engine
		# separates the bodies; rate-limit the solver's small resting
		# impulse so a ghost parked against the host does not vibrate.
		if penetration < 0.03:
			return
		if now_ms - int(_separation_ms.get(pair_key, -1000)) < 120:
			return
		_separation_ms[pair_key] = now_ms
	else:
		# One momentum impulse per continuous contact. A late state packet can
		# rewind the predicted ghost velocity to its pre-impact value, so the
		# old 100 ms window fired the same hit over and over (a ghost pinned
		# inside the host was shoved ten times a second). A pair pays a new
		# impact only after it has been out of contact, or when the new closing
		# speed is clearly harder than the one already answered.
		if now_ms - int(_impact_ms.get(pair_key, -1000)) < 100:
			return
		var answered: float = float(_impact_closing.get(pair_key, -1000.0))
		_impact_ms[pair_key] = now_ms
		if closing <= answered + 1.5:
			return
		_impact_closing[pair_key] = closing
	if solver != null:
		# The shared solver owns all impulse maths (including resting and
		# friction rules) so the sandbox and the race respond identically.
		# The physics engine already separated this pair, so pass
		# separate=false: double separation was the visible jitter.
		var contact_point: Vector3 = (pos_a + pos_b) * 0.5
		var raw_a: Vector3 = _cart_velocity_value(cart_a)
		var raw_b: Vector3 = _cart_velocity_value(cart_b)
		var impulse_mag: float = float(solver.resolve_pair(cart_a, cart_b,
			contact_point, normal, penetration, false))
		# The solver returns the scalar impulse it just applied. Both owners
		# get exactly that delta-v: the host directly, a remote through the
		# existing RPC. The remote applies it to its own local body once; its
		# _process_collisions skips remote carts, so the local physics step
		# cannot add a second exchange for the same contact.
		if impulse_mag > 0.0:
			var impulse_dir: Vector3 = normal.normalized()
			if id_a != host_id:
				var delta_a: Vector3 = (-impulse_dir \
					* (impulse_mag / _cart_mass(cart_a))).limit_length(
					MAX_CART_SPEED)
				if delta_a.is_finite() and delta_a.length_squared() > 0.000001:
					local_cart.rpc_id(id_a, "_net_apply_car_impulse", delta_a)
					# Predict the owner's velocity locally so the next tick's
					# closing test does not fire the same impact again while
					# its post-impact packet is still in flight.
					cart_a.set("net_velocity",
						(vel_a + delta_a).limit_length(MAX_CART_SPEED))
			if id_b != host_id:
				var delta_b: Vector3 = (impulse_dir \
					* (impulse_mag / _cart_mass(cart_b))).limit_length(
					MAX_CART_SPEED)
				if delta_b.is_finite() and delta_b.length_squared() > 0.000001:
					local_cart.rpc_id(id_b, "_net_apply_car_impulse", delta_b)
					cart_b.set("net_velocity",
						(vel_b + delta_b).limit_length(MAX_CART_SPEED))
		# Restore the host-side scratch velocity the solver wrote. A remote
		# owner receives the impulse above and keeps its own physics.
		if id_a != host_id:
			cart_a.set("velocity", raw_a)
		if id_b != host_id:
			cart_b.set("velocity", raw_b)
		return
	var mass_a: float = _cart_mass(cart_a)
	var mass_b: float = _cart_mass(cart_b)
	var inv_a: float = 1.0 / mass_a
	var inv_b: float = 1.0 / mass_b
	var impact_impulse: float = 1.18 * closing / (inv_a + inv_b)
	var separation_speed: float = clampf(penetration * 5.0, 0.0, 1.2)
	var normal_impulse: float = impact_impulse + separation_speed / (inv_a + inv_b)
	var impulse_a: Vector3 = -normal * normal_impulse
	var impulse_b: Vector3 = normal * normal_impulse
	# Coulomb friction only applies to a real impact. Separation must not
	# erase sideways sliding when two carts are grinding along together.
	if closing > 0.02:
		var tangent: Vector3 = relative - normal * relative.dot(normal)
		var tangent_speed: float = tangent.length()
		if tangent_speed > 0.02:
			var tangent_dir: Vector3 = tangent / tangent_speed
			var tangent_impulse: float = minf(tangent_speed / (inv_a + inv_b),
				0.24 * impact_impulse)
			impulse_a -= tangent_dir * tangent_impulse
			impulse_b += tangent_dir * tangent_impulse
	# Pre-1.6.0 fallback while the shared solver is unavailable: compute the
	# raw momentum exchange here. apply_vehicle_impulse() is the receiver's
	# single entry point and bounds the delta; this path only shapes it.
	var delta_a: Vector3 = (impulse_a / mass_a).limit_length(MAX_CART_SPEED)
	var delta_b: Vector3 = (impulse_b / mass_b).limit_length(MAX_CART_SPEED)
	if id_a == host_id:
		cart_a.call("apply_vehicle_impulse", delta_a)
	else:
		local_cart.rpc_id(id_a, "_net_apply_car_impulse", delta_a)
	if id_b == host_id:
		cart_b.call("apply_vehicle_impulse", delta_b)
	else:
		local_cart.rpc_id(id_b, "_net_apply_car_impulse", delta_b)


func _active_gameplay_scene() -> Node:
	if is_instance_valid(_active_scene_node) and _active_scene_node.is_inside_tree():
		return _active_scene_node
	var tree: SceneTree = get_tree()
	return tree.current_scene if tree != null else null


func _active_gameplay_scene_path(current: Node = null) -> String:
	if _active_scene_path != "" and is_instance_valid(_active_scene_node) \
			and _active_scene_node.is_inside_tree():
		return _active_scene_path
	var scene_node: Node = current if current != null else _active_gameplay_scene()
	var path: String = scene_node.scene_file_path if scene_node != null else ""
	if path == "" and in_game:
		path = game_scene
	return path


func notify_scene_ready(scene_node: Node = null, explicit_path: String = "") -> void:
	## Called by every gameplay scene after its networking setup.
	## SceneTree._change_scene sets get_tree().current_scene AFTER add_child()
	## and _ready() finish, so callers may pass `self` or we resolve from the
	## active gameplay scene tracking fields.
	var current: Node = scene_node if (scene_node != null and is_instance_valid(scene_node)) \
		else (get_tree().current_scene if get_tree() != null else null)
	var scene_path: String = explicit_path
	if scene_path == "" and current != null:
		scene_path = current.scene_file_path
	if scene_path == "" and in_game:
		scene_path = game_scene
	if current != null:
		_active_scene_node = current
	if scene_path != "":
		_active_scene_path = scene_path
	if not is_session_active() or multiplayer.multiplayer_peer == null:
		return
	if is_host:
		scene_ready_peers[1] = true
		host_scene_ready_path = scene_path
		if scene_path != "" and is_connected_to_server():
			for peer_id: int in multiplayer.get_peers():
				rpc_id(peer_id, "_net_host_scene_ready", scene_path)
	else:
		# Do not assume the host finished loading the gameplay scene first:
		# only mark peer 1 ready once the host announces it entered this scene.
		if scene_path != "" and host_scene_ready_path == scene_path:
			scene_ready_peers[1] = true
		else:
			scene_ready_peers.erase(1)
	_scene_load_path = ""


@rpc("authority", "call_remote", "reliable")
func _net_host_scene_ready(scene_path: String) -> void:
	if is_host or scene_path == "" or scene_path not in ALLOWED_SCENES:
		return
	host_scene_ready_path = scene_path
	var current: Node = _active_gameplay_scene()
	var active_path: String = _active_gameplay_scene_path(current)
	if active_path == scene_path and current != null:
		scene_ready_peers[1] = true
		host_scene_ready.emit(scene_path)
		_send_client_scene_ready(current, scene_path)


func _send_client_scene_ready(current: Node, scene_path: String) -> void:
	if is_host or current == null or not is_connected_to_server():
		return
	if not is_scene_ready(1):
		return
	if scene_path == GAME_SCENE and current.has_method("_net_client_ready"):
		current.rpc_id(1, "_net_client_ready", GameSettings.selected_vehicle)
	elif scene_path == RACE_SCENE and current.has_method("_net_race_ready"):
		current.rpc_id(1, "_net_race_ready", GameSettings.minigame_vehicle)
	elif scene_path == CARGO_SCENE and current.has_method("_net_cargo_ready"):
		current.rpc_id(1, "_net_cargo_ready", session_minigame,
			GameSettings.minigame_vehicle)
	elif scene_path == KNOCKOUT_SCENE and current.has_method("_net_knockout_ready"):
		current.rpc_id(1, "_net_knockout_ready", session_minigame,
			GameSettings.minigame_vehicle)
	elif scene_path == BOMB_TAG_SCENE and current.has_method("_net_bomb_ready"):
		current.rpc_id(1, "_net_bomb_ready", session_minigame,
			GameSettings.minigame_vehicle)




func is_connected_to_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() \
		== MultiplayerPeer.CONNECTION_CONNECTED


func peer_count() -> int:
	if not is_session_active():
		return 0
	return multiplayer.get_peers().size() + 1


# --------------------------------------------------------------------------
# game event + teams


static func event_for_scene(scene_path: String) -> String:
	## "" for the sandbox, otherwise which minigame this scene belongs to.
	match scene_path:
		CARGO_SCENE:
			return EVENT_CARGO
		KNOCKOUT_SCENE:
			return EVENT_KNOCKOUT
		BOMB_TAG_SCENE:
			return EVENT_BOMB_TAG
		RACE_SCENE:
			return EVENT_RACE
	return ""


static func event_for_theme_id(theme_id: String) -> String:
	## Map a minigame arena/theme id back to its owning event.
	for preset: Dictionary in TrackDefs.PRESETS:
		if TrackDefs.is_minigame(preset) and TrackDefs.theme_ids(preset).has(theme_id):
			var scene_path: String = str(preset.get("scene", ""))
			var ev: String = event_for_scene(scene_path)
			if ev != "":
				return ev
	if theme_id.begins_with("ko_"):
		return EVENT_KNOCKOUT
	if theme_id.begins_with("bt_"):
		return EVENT_BOMB_TAG
	return EVENT_CARGO if TrackDefs.has_theme_id(theme_id) else ""


func scene_for_event(event: String) -> String:
	## The host's scene for an event. A blank event means the sandbox.
	match event:
		EVENT_CARGO:
			return CARGO_SCENE
		EVENT_KNOCKOUT:
			return KNOCKOUT_SCENE
		EVENT_BOMB_TAG:
			return BOMB_TAG_SCENE
		EVENT_RACE:
			return RACE_SCENE
	return GAME_SCENE


static func _sanitize_minigame_theme(event: String, raw_theme: String) -> String:
	## Guarantee that `session_minigame` always belongs to `event` (so a
	## Knockout room never carries a stale Cargo Rush theme or vice versa).
	var preset_id: String = ""
	match event:
		EVENT_CARGO:
			preset_id = "cargo_rush"
		EVENT_KNOCKOUT:
			preset_id = "knockout"
		EVENT_BOMB_TAG:
			preset_id = "bomb_tag"
		_:
			return ""
	var preset: Dictionary = TrackDefs.get_minigame(preset_id)
	if preset.is_empty():
		return ""
	var clean: String = raw_theme.strip_edges().to_lower()
	if TrackDefs.theme_ids(preset).has(clean):
		return clean
	return TrackDefs.default_theme(preset)


func set_host_event(event: String, map_or_arena_id: String = "") -> void:
	## Host helper used by the mode/map selector and lobby to set both the event
	## and its map/arena in one atomic session update.
	var clean_ev: String = event.strip_edges().to_lower()
	if clean_ev == "cargo_rush" or clean_ev == "deliver":
		clean_ev = EVENT_CARGO
	elif clean_ev == "blast_tag":
		clean_ev = EVENT_BOMB_TAG
	if clean_ev == "" or clean_ev == "sandbox":
		GameSettings.set_multiplayer_mode(GameSettings.GAME_SANDBOX)
		if is_host:
			configure_session(GameSettings.GAME_SANDBOX, GameSettings.bots_enabled,
				GameSettings.effective_bot_count(), "", GAME_SCENE)
			_push_room_state()
		return
	GameSettings.set_multiplayer_mode(GameSettings.GAME_MINIGAMES)
	if clean_ev == EVENT_RACE or clean_ev == "racing":
		if map_or_arena_id != "":
			GameSettings.set_selected_map(map_or_arena_id)
		if is_host:
			configure_session(GameSettings.GAME_MINIGAMES, GameSettings.bots_enabled,
				GameSettings.effective_bot_count(), GameSettings.selected_map, RACE_SCENE)
			_push_room_state()
		return
	if clean_ev in MINIGAME_EVENTS:
		var target_theme: String = _sanitize_minigame_theme(
			clean_ev,
			map_or_arena_id if map_or_arena_id != "" else GameSettings.selected_minigame)
		if target_theme != "":
			GameSettings.set_selected_minigame(target_theme)
		if is_host:
			configure_session(GameSettings.GAME_MINIGAMES, GameSettings.bots_enabled,
				GameSettings.effective_bot_count(), GameSettings.selected_map,
				scene_for_event(clean_ev))
			_push_room_state()


func is_deliver_session() -> bool:
	## True for a CARGO RUSH room. Uses the replicated scene/event, never the
	## local player's menu pick, so a client cannot believe it is delivering
	## while the host is racing.
	if session_mode != GameSettings.GAME_MINIGAMES:
		return false
	if session_scene != "":
		return session_scene == CARGO_SCENE
	return session_event == EVENT_CARGO


func team_for_peer(peer_id: int) -> int:
	## 0 = ALPHA, 1 = BETA, always in range. An unassigned peer (a just-joined
	## client before the config packet lands) falls back to a deterministic
	## parity split, so every peer agrees on who is on which side.
	if peer_id <= 0:
		return 0
	if _peer_teams.has(peer_id):
		return 1 if int(_peer_teams[peer_id]) == 1 else 0
	return peer_id % TEAM_COUNT


func set_peer_team(peer_id: int, team: int) -> void:
	## Host only. A manual move is authoritative and is not undone by the
	## joiner/leaver balance pass.
	if not is_host or not is_session_active():
		return
	if team < 0 or team >= TEAM_COUNT:
		return
	if not participants().has(peer_id):
		return
	_peer_teams[peer_id] = team
	_push_session_config()
	teams_changed.emit()


func set_teams_locked(locked: bool) -> void:
	## Host only. Locking freezes the current split; unlocking balances once.
	if not is_host or not is_session_active():
		return
	teams_locked = locked
	if not teams_locked:
		_balance_teams()
	_push_session_config()
	teams_changed.emit()


func refresh_session_config() -> void:
	## Re-broadcast the host's current setup (mode, scene, teams) without
	## re-deriving it from local settings. Used when a peer joins the room.
	if not is_host or not is_session_active():
		return
	_push_session_config()


func _smaller_team() -> int:
	var counts: Array[int] = _team_counts()
	return 0 if counts[0] <= counts[1] else 1


func _team_counts() -> Array[int]:
	var counts: Array[int] = [0, 0]
	for peer_id: int in participants():
		if _peer_teams.has(peer_id):
			var team: int = team_for_peer(peer_id)
			counts[team] = counts[team] + 1
	return counts


func _balance_teams() -> void:
	## Host only, auto mode only. Every live peer gets a side, departed peers
	## lose theirs, and the counts never differ by more than one. The host is
	## moved last, so a late joiner is the one who switches sides.
	if not is_host or teams_locked:
		return
	var ids: Array[int] = participants()
	for peer_id: int in ids:
		if not _peer_teams.has(peer_id):
			_peer_teams[peer_id] = _smaller_team()
	for _guard in ids.size() + TEAM_COUNT:
		var counts: Array[int] = _team_counts()
		if absi(counts[0] - counts[1]) <= 1:
			break
		var crowded: int = 0 if counts[0] > counts[1] else 1
		var mover: int = -1
		for peer_id: int in ids:
			if peer_id != 1 and team_for_peer(peer_id) == crowded:
				mover = peer_id
		if mover < 0:
			for peer_id: int in ids:
				if team_for_peer(peer_id) == crowded:
					mover = peer_id
		if mover < 0:
			break
		_peer_teams[mover] = 1 - crowded


# --------------------------------------------------------------------------
# hosting


func host_game(mode: String = "pi") -> void:
	leave()
	_host_ticket += 1
	var ticket: int = _host_ticket
	connection_mode = "lan" if mode == "lan" else "pi"
	GameSettings.set_connection_preference(connection_mode)
	SceneLoader.begin_task("OPENING A ROOM", "Starting the server...")
	await get_tree().process_frame
	if ticket != _host_ticket:
		SceneLoader.end_task()
		return
	local_address = _local_ip()
	var bound_port: int = _open_server()
	if bound_port <= 0:
		SceneLoader.end_task()
		host_failed.emit("Could not open a game port. Close any other copy and try again.")
		return
	port = bound_port
	is_host = true
	in_game = false
	room_state = "lobby"
	join_code = ""
	public_address = ""
	session_mode = GameSettings.multiplayer_mode
	session_bots = GameSettings.bots_enabled
	session_bot_count = GameSettings.effective_bot_count()
	session_bot_difficulty = clampi(GameSettings.minigame_difficulty, 0, 2)
	# The room carries its event/scene from the very first host frame. A
	# DELIVER room hosts CARGO RUSH; everything else keeps its race/sandbox
	# scene, so no path downstream has to guess from the mode alone.
	session_event = _infer_session_event(session_mode)
	session_scene = scene_for_event(session_event)
	session_minigame = _sanitize_minigame_theme(session_event, GameSettings.selected_minigame) \
		if session_event in MINIGAME_EVENTS else ""
	session_map_id = GameSettings.sanitize_map_id(GameSettings.selected_map)
	# A fresh room starts with a clean, balanced team split.
	_peer_teams.clear()
	teams_locked = false
	_peer_teams[1] = 0
	_balance_teams()
	session_racing_car_id = sanitize_racing_car_id(
		GameSettings.racing_vehicle_id())
	session_racing_allocation = sanitize_racing_allocation(
		GameSettings.racing_allocation())
	session_vehicle_mode = VEHICLE_MODE_SHARED \
		if GameSettings.multiplayer_vehicle_mode == VEHICLE_MODE_SHARED \
		else VEHICLE_MODE_PICK_OWN
	session_shared_vehicle = GameSettings.vehicle_for_channel(active_vehicle_channel())
	session_shared_racer_color = GameSettings.racer_color
	room_public = GameSettings.room_public
	player_names[1] = GameSettings.player_name
	player_colors[1] = GameSettings.tag_color()
	player_vehicles[1] = _local_loadout_dict()
	ping_table[1] = 0

	if connection_mode == "lan":
		# The host PC is the server. No internet, no Pi, no code to type.
		_start_lan_listener()
		if _lan_listener == null:
			_abort_host("Could not start LAN discovery. Close another copy and try again.")
			return
		SceneLoader.end_task()
		host_started.emit("")
		peers_changed.emit()
		return

	# Pi mode: the server allocates the short room code. There is no direct
	# public-IP / UPnP fallback any more.
	SceneLoader.task_message("Connecting to the Cart Slop server...")
	var found: bool = await _discover_relay()
	if ticket != _host_ticket:
		SceneLoader.end_task()
		return
	if not found:
		_abort_host("Cart Slop server is offline. Check the internet, or host a LAN room.")
		return
	SceneLoader.task_message("Creating your room...")
	var registered: bool = false
	for attempt in 2:
		if await _register_relay(port):
			registered = true
			break
		if ticket != _host_ticket:
			# Cancelled mid-registration. Release the overlay here: leaving it
			# up blocks every later go_to() until SceneLoader's task timeout.
			SceneLoader.end_task()
			return
		await get_tree().create_timer(0.6).timeout
		if ticket != _host_ticket:
			SceneLoader.end_task()
			return
	if ticket != _host_ticket:
		SceneLoader.end_task()
		return
	if not registered:
		_abort_host("The server could not create a room. Try again in a moment.")
		return
	relay_active = true
	join_code = relay_room_code
	if join_code == "":
		_abort_host("The server did not return a room code.")
		return
	SceneLoader.end_task()
	host_started.emit(join_code)
	peers_changed.emit()


func _abort_host(reason: String) -> void:
	leave()
	SceneLoader.end_task()
	host_failed.emit(reason)


func _discover_relay() -> bool:
	## A manually configured public server wins; otherwise UDP broadcast to
	## the Pi's discovery port (no DNS/.local dependency).
	if relay_base != "":
		return true
	if relay_server_url != "":
		relay_base = relay_server_url
		relay_base_public = true
		return true
	var probes: Array[Dictionary] = _open_probe_sockets()
	if probes.is_empty():
		# No usable LAN interface (or every bind was refused). Do not give up
		# before the public fallback: a player behind a purely virtual adapter
		# can still join a room by code.
		if _use_default_public_relay():
			var public_probe: Dictionary = await _relay_get("/api/status", 3.0)
			if not public_probe.is_empty():
				discovery_hint = ""
				return true
			_clear_default_public_relay()
		return false
	var request: PackedByteArray = "CARTSLOP_DISCOVER".to_utf8_buffer()
	_broadcast_probes(probes, request, RELAY_DISCOVERY_PORT)
	# macOS 15+ may deny the first broadcast while the Local Network permission
	# alert is still on screen (Apple TN3179 tells apps to add retry logic), so
	# the macOS window is longer. Every other platform keeps the short window,
	# and a reply exits immediately on all platforms.
	var timeout_ms: int = DISCOVERY_TIMEOUT_MACOS_MS if _is_macos() else DISCOVERY_TIMEOUT_MS
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	var next_nudge: int = Time.get_ticks_msec() + DISCOVERY_NUDGE_MS
	while Time.get_ticks_msec() < deadline:
		for probe: Dictionary in probes:
			var socket: PacketPeerUDP = probe["socket"] as PacketPeerUDP
			if socket == null:
				continue
			while socket.get_available_packet_count() > 0:
				var text: String = socket.get_packet().get_string_from_utf8()
				# Cheap gate: the discovery port also receives unrelated UDP on
				# a busy LAN; only our service reply reaches JSON parsing.
				if not text.contains("cartslop"):
					continue
				var parsed: Variant = JSON.parse_string(text)
				if not (parsed is Dictionary):
					continue
				var reply: Dictionary = parsed as Dictionary
				if str(reply.get("service", "")) != "cartslop":
					continue
				var reply_ip: String = _strip_host_brackets(
					str(reply.get("lan_ip", "")))
				# A reply is only useful for a LAN Pi. If the Pi did not name
				# its lan_ip (or named an address we cannot trust), fall back to
				# the packet source, which is by definition routed back to the Pi.
				if not _is_lan_peer_address(reply_ip):
					reply_ip = _strip_host_brackets(socket.get_packet_ip())
				if not _is_private_ipv4(reply_ip):
					continue
				var http_port: int = int(reply.get("http_port", 42777))
				if http_port <= 0 or http_port > 65535:
					continue
				relay_lan_ip = reply_ip
				relay_base = "http://%s:%d" % [reply_ip, http_port]
				relay_base_public = false
				discovery_hint = ""
				_close_probes(probes)
				return true
		var now: int = Time.get_ticks_msec()
		if now >= next_nudge:
			# UDP is lossy, and on macOS the first attempts can be refused while
			# the permission alert is unanswered. Keep nudging until the window
			# closes; one lost broadcast must not push the player to the public
			# fallback.
			next_nudge = now + DISCOVERY_NUDGE_MS
			_broadcast_probes(probes, request, RELAY_DISCOVERY_PORT)
		await get_tree().process_frame
	_close_probes(probes)
	# No LAN answer. Tell the lobby why on macOS, then try the built-in relay
	# once; this is what lets a player on a restrictive network use a short
	# room code through the online relay.
	discovery_hint = "macos_local_network" if _is_macos() else ""
	if _use_default_public_relay():
		var probe: Dictionary = await _relay_get("/api/status", 3.0)
		if not probe.is_empty():
			discovery_hint = ""
			return true
		_clear_default_public_relay()
	return false


func _use_default_public_relay() -> bool:
	var text: String = OS.get_environment("CARTSLOP_RELAY").strip_edges()
	if text == "" and OS.has_feature("web"):
		# The hosted page and the game API share an origin, so the browser build
		# must talk to the server that served it rather than a baked-in address.
		# location.origin keeps the scheme, which matters behind a TLS tunnel:
		# an https page must use 443, not the game's usual 42777.
		var origin: String = str(JavaScriptBridge.eval("location.origin", true)).strip_edges()
		if origin != "":
			text = origin
	if text == "":
		text = DEFAULT_RELAY_SERVER.strip_edges()
	if text == "":
		return false
	var lower_text: String = text.to_lower()
	var secure: bool = lower_text.begins_with("https://")
	var rest: String = text
	if secure:
		rest = rest.substr(8)
	elif lower_text.begins_with("http://"):
		rest = rest.substr(7)
	rest = rest.trim_suffix("/")
	var authority: String = rest.get_slice("/", 0)
	var host: String = authority
	var port: int = 443 if secure else 42777
	if authority.begins_with("["):
		var close_idx: int = authority.find("]")
		if close_idx <= 1:
			return false
		# Sockets need the bare IPv6 literal; brackets are URL syntax only.
		host = _strip_host_brackets(authority.substr(0, close_idx + 1))
		if close_idx + 1 < authority.length() and authority[close_idx + 1] == ":":
			port = int(authority.substr(close_idx + 2))
	elif authority.contains(":"):
		var parts: PackedStringArray = authority.split(":")
		host = _strip_host_brackets(parts[0])
		port = int(parts[1]) if parts.size() > 1 else (443 if secure else 42777)
	if host == "" or port <= 0 or port > 65535:
		return false
	relay_server_host = _strip_host_brackets(host)
	relay_server_http_port = port
	relay_server_url = ("https://" if secure else "http://") \
		+ _url_host(relay_server_host) + ":" + str(port)
	relay_base = relay_server_url
	relay_base_public = true
	return true


func _clear_default_public_relay() -> void:
	_invalidate_relay_route()


func _invalidate_relay_route() -> void:
	## The cached route points at a server that just failed. Drop it so the
	## next attempt rediscovers instead of retrying a dead address for every
	## browse/join click. A user-forced server is kept and re-resolved.
	relay_base = ""
	if not _relay_forced:
		relay_server_url = ""
		relay_server_host = ""
	relay_base_public = false


# --------------------------------------------------------------------------
# LAN room discovery (host advertises itself; no typed IP, no Pi required)


func _start_lan_listener() -> void:
	_stop_lan_listener()
	var udp := PacketPeerUDP.new()
	if udp.bind(LAN_ROOM_PORT) != OK:
		last_error = "lan_discovery_unavailable"
		return
	udp.set_broadcast_enabled(true)
	_lan_listener = udp
	# Trigger our own macOS Local Network permission prompt NOW, while the host
	# is still in the lobby, instead of leaving it until a client is waiting.
	_lan_warmup_left = LAN_WARMUP_PROBES
	_lan_warmup_timer = 0.0
	_lan_beacon_timer = LAN_BEACON_INTERVAL if room_public else -1.0


func _lan_beacon_tick(delta: float) -> void:
	## LAN host advertisement. A PUBLIC room beacons every LAN_BEACON_INTERVAL
	## (clients find it without a request round trip, and the first beacon makes
	## macOS show the Local Network alert while the host is in the lobby). Every
	## room also sends a few one-shot warm-up probes: receiving an incoming
	## broadcast is itself a local-network operation on macOS, so a host that
	## never sends anything can never prompt itself and can never hear clients.
	if _lan_listener == null or not is_host or connection_mode != "lan":
		return
	if _lan_warmup_left > 0:
		_lan_warmup_timer -= delta
		if _lan_warmup_timer <= 0.0:
			_lan_warmup_left -= 1
			_lan_warmup_timer = LAN_WARMUP_INTERVAL
			_send_discovery_probe(JSON.stringify({
				"service": "cartslop-lan",
				"want": "rooms",
			}).to_utf8_buffer(), LAN_ROOM_PORT)
	if _lan_beacon_timer < 0.0:
		return
	_lan_beacon_timer -= delta
	if _lan_beacon_timer > 0.0:
		return
	_lan_beacon_timer = LAN_BEACON_INTERVAL
	var beacon: Dictionary = _lan_room_record()
	beacon["beacon"] = true
	_send_discovery_probe(JSON.stringify(beacon).to_utf8_buffer(), LAN_ROOM_PORT)


func _lan_room_record() -> Dictionary:
	## One shared room description for discovery replies and beacons.
	return {
		"service": "cartslop-lan",
		"name": GameSettings.player_name,
		"host": local_address if _valid_ip(local_address) else _local_ip(),
		"port": port,
		"players": peer_count(),
		"mode": session_mode,
		"event": session_event,
		"state": room_state,
		"map": _advertised_room_map(),
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
	}


func _lan_reply_host(sender: String) -> String:
	## The client must connect back to THIS host on the interface the request
	## actually arrived from. A multi-homed Mac that answers with its VPN/utun
	## address (the old local_address behaviour) is unreachable.
	var best: String = _lan_address_for(sender)
	if best != "" and best != "127.0.0.1":
		return best
	return local_address if _valid_ip(local_address) else _local_ip()


func _stop_lan_listener() -> void:
	if _lan_listener != null:
		_lan_listener.close()
		_lan_listener = null
	_lan_beacon_timer = -1.0
	_lan_warmup_left = 0


func _advertised_room_map() -> String:
	if session_mode == GameSettings.GAME_MINIGAMES and session_event in MINIGAME_EVENTS:
		var clean_theme: String = _sanitize_minigame_theme(session_event, session_minigame)
		return clean_theme if clean_theme != "" else session_map_id
	return session_map_id


func _poll_lan_listener() -> void:
	if _lan_listener == null:
		return
	while _lan_listener.get_available_packet_count() > 0:
		var packet: PackedByteArray = _lan_listener.get_packet()
		var sender: String = _lan_listener.get_packet_ip()
		var sender_port: int = _lan_listener.get_packet_port()
		var packet_text: String = packet.get_string_from_utf8()
		if not packet_text.contains("cartslop-lan"):
			continue
		var parsed: Variant = JSON.parse_string(packet_text)
		if not (parsed is Dictionary):
			continue
		var request: Dictionary = parsed as Dictionary
		if str(request.get("service", "")) != "cartslop-lan" \
				or str(request.get("want", "")) != "rooms":
			continue
		if sender == "" or sender_port <= 0:
			continue
		# Only answer a real LAN peer. Replying to a spoofed public source
		# would turn the discovery socket into a small UDP reflector.
		if not _is_lan_peer_address(sender):
			continue
		# Private LAN rooms do not answer discovery at all. The host flips the
		# ROOM setting to PUBLIC when friends are ready to join.
		if not room_public:
			continue
		var reply: Dictionary = _lan_room_record()
		reply["host"] = _lan_reply_host(sender)
		_lan_listener.set_dest_address(sender, sender_port)
		_lan_listener.put_packet(JSON.stringify(reply).to_utf8_buffer())


func scan_lan_rooms(timeout: float = 1.4) -> Array:
	## Broadcast a request and collect host replies/beacons. Returns rooms
	## discovered on the local network. Nothing here is typed by the player.
	## Replies are collected per interface socket: a reply that came back on an
	## interface-bound socket is preferred over one that came back over the
	## default route (which may be a VPN on a Mac), so the room row carries an
	## address the friend's Wi-Fi can actually reach.
	var probes: Array[Dictionary] = _open_probe_sockets()
	if probes.is_empty():
		return []
	var request: PackedByteArray = JSON.stringify({
		"service": "cartslop-lan",
		"want": "rooms",
	}).to_utf8_buffer()
	_broadcast_probes(probes, request, LAN_ROOM_PORT)
	var found: Dictionary = {}
	var started: int = Time.get_ticks_msec()
	var window_ms: int = int(maxf(timeout, 0.4) * 1000.0)
	var short_deadline: int = started + window_ms
	var deadline: int = short_deadline
	if _is_macos():
		# A Mac's first scan can sit behind the Local Network permission alert;
		# keep retrying past the normal window instead of telling the player
		# "no rooms" before they have answered it. Still exits as soon as a room
		# answers, so a healthy LAN is just as fast as before.
		deadline = started + maxi(window_ms, DISCOVERY_TIMEOUT_MACOS_MS)
	var next_nudge: int = started + DISCOVERY_NUDGE_MS
	while Time.get_ticks_msec() < deadline:
		for probe: Dictionary in probes:
			var socket: PacketPeerUDP = probe["socket"] as PacketPeerUDP
			if socket == null:
				continue
			var arrival_rank: int = int(probe["rank"])
			while socket.get_available_packet_count() > 0:
				var packet: PackedByteArray = socket.get_packet()
				var sender_ip: String = socket.get_packet_ip()
				var room: Dictionary = _parse_lan_room_reply(
					packet.get_string_from_utf8(), sender_ip)
				if room.is_empty():
					continue
				if not _lan_version_matches(str(room.get("version", ""))):
					continue
				room["_rank"] = arrival_rank
				var key: String = "%s:%d" % [str(room["host"]), int(room["port"])]
				if not found.has(key) or int((found[key] as Dictionary)["_rank"]) < arrival_rank:
					found[key] = room
		if not found.is_empty() and Time.get_ticks_msec() >= short_deadline:
			# A room answered inside the normal window: do not make the lobby
			# wait out the macOS grace period just to collect stragglers.
			break
		var now: int = Time.get_ticks_msec()
		if now >= next_nudge:
			next_nudge = now + DISCOVERY_NUDGE_MS
			_broadcast_probes(probes, request, LAN_ROOM_PORT)
		await get_tree().process_frame
	_close_probes(probes)
	if found.is_empty():
		discovery_hint = "macos_local_network" if _is_macos() else ""
		return []
	# Best interface first. The internal rank key is stripped before the list
	# reaches the room browser, which knows nothing about discovery plumbing.
	var ranked: Array[Dictionary] = []
	for entry: Variant in found.values():
		ranked.append(entry as Dictionary)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("_rank", 0)) > int(b.get("_rank", 0)))
	var rooms: Array = []
	for room: Dictionary in ranked:
		var clean: Dictionary = room.duplicate()
		clean.erase("_rank")
		rooms.append(clean)
	return rooms


func join_lan_room(room: Dictionary) -> void:
	if join_pending or is_session_active():
		# _connect_to() starts by calling leave(). A second click on a LAN row
		# (or a click while this machine is hosting) must not tear that live
		# session down; every other join path already refuses the same way.
		return
	var host: String = _strip_host_brackets(str(room.get("host", "")).strip_edges())
	var open_port: int = int(room.get("port", 0))
	if not _is_lan_peer_address(host) or open_port <= 0:
		join_failed.emit("That LAN room is no longer available. Scan again.")
		return
	if int(room.get("players", 1)) >= MAX_PLAYERS:
		join_failed.emit("That LAN room is full. Pick another room or wait for a slot. Hint: try a different room.")
		return
	if str(room.get("state", "lobby")) != "lobby":
		join_failed.emit("That LAN match already started. Ask the host to return to the lobby. Hint: wait for the lobby.")
		return
	# A fresh user action re-arms the one-shot macOS permission retry.
	_lan_join_retry = 0
	join_status_changed.emit("Joining the LAN room...")
	_connect_to(host, open_port, "lan")


func _join_transport_reason(code: String = "") -> String:
	var detail: String = _relay_result_detail()
	match detail:
		"tls_error":
			return "Secure connection failed (TLS). Check system date/time and firewall, then try again. Hint: fix clock/VPN and retry."
		"dns_error":
			return "Could not resolve the server (DNS). Check DNS/VPN settings, then try again. Hint: check network and retry."
		"timeout":
			return "Connection timed out waiting for the server. Try again in a moment. Hint: retry."
		"unreachable":
			return "Could not reach the server. Check the internet connection, then try again. Hint: check connection and retry."
	if _relay_http_status == 410:
		return "That room expired on the server. Ask the host for a fresh code. Hint: host a new room." if code == "" else "Room %s expired on the server. Ask the host for a fresh code. Hint: host a new room." % code
	return ""


func _acquire_http(timeout: float) -> HTTPRequest:
	## Reuse an idle request when possible. The 10 Hz race state stream used to
	## create and free an HTTPRequest node ten times a second.
	while not _http_idle.is_empty():
		var pooled: HTTPRequest = _http_idle.pop_back()
		if is_instance_valid(pooled) and pooled.is_inside_tree():
			pooled.timeout = timeout
			pooled.body_size_limit = MAX_HTTP_BODY
			return pooled
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.body_size_limit = MAX_HTTP_BODY
	add_child(http)
	return http


func _release_http(http: HTTPRequest) -> void:
	if not is_instance_valid(http) or not http.is_inside_tree():
		return
	if _http_idle.size() >= HTTP_POOL_MAX:
		http.queue_free()
		return
	_http_idle.append(http)


func _relay_post(path: String, payload: Dictionary,
		timeout: float = 6.0) -> Dictionary:
	## One JSON POST, parsed into a Dictionary. The request object comes from
	## the shared pool so fire-and-forget callers do not allocate per packet.
	## POSTs are not retried here: register/heartbeat own their retry policy and
	## a duplicated state-changing request could create two rooms. The transport
	## result is recorded so a TLS/DNS failure is distinguishable from an HTTP
	## error by the lobby/updater.
	if relay_base == "":
		_relay_http_status = 0
		_relay_http_result = HTTPRequest.RESULT_SUCCESS
		return {}
	var base: String = relay_base
	var http: HTTPRequest = _acquire_http(timeout)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var error: Error = http.request(base + path, headers,
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_relay_http_status = -1
		_relay_http_result = HTTPRequest.RESULT_REQUEST_FAILED
		_release_http(http)
		return {}
	var response: Array = await http.request_completed
	_release_http(http)
	_relay_http_result = int(response[0])
	_relay_http_status = int(response[1])
	if relay_base == "" or relay_base != base:
		# A leave() during the request cleared/changed the route; the answer
		# belongs to a session that no longer exists.
		return {}
	return _relay_parse_response(response)


func _relay_get(path: String, timeout: float = RELAY_HTTP_TIMEOUT) -> Dictionary:
	## GET with ONE transport retry. A macOS sleep/wake, a VPN switch or a stale
	## pooled keep-alive connection can fail the first request while the network
	## is actually fine; retrying a GET is safe (idempotent). A TLS handshake
	## failure is deliberately not retried: the certificate store will not heal
	## in 150 ms, and the caller reports it instead of calling the server offline.
	if relay_base == "":
		_relay_http_status = 0
		_relay_http_result = HTTPRequest.RESULT_SUCCESS
		return {}
	var base: String = relay_base
	for attempt in 2:
		var http: HTTPRequest = _acquire_http(timeout)
		var error: Error = http.request(base + path, [], HTTPClient.METHOD_GET)
		if error != OK:
			_relay_http_status = -1
			_relay_http_result = HTTPRequest.RESULT_REQUEST_FAILED
			_release_http(http)
			return {}
		var response: Array = await http.request_completed
		_release_http(http)
		_relay_http_result = int(response[0])
		_relay_http_status = int(response[1])
		if relay_base == "" or relay_base != base:
			return {}
		if int(response[0]) == HTTPRequest.RESULT_SUCCESS:
			return _relay_parse_response(response)
		if attempt == 0 and _relay_result_retryable(int(response[0])):
			await get_tree().create_timer(0.15).timeout
			continue
		break
	return {}


func _relay_parse_response(response: Array) -> Dictionary:
	var status: int = int(response[1])
	if status != 200:
		return {}
	var parsed: Variant = JSON.parse_string(
		(response[3] as PackedByteArray).get_string_from_utf8())
	return parsed as Dictionary if parsed is Dictionary else {}


func _relay_result_retryable(result: int) -> bool:
	## Transport-only failures worth one retry: a stale keep-alive connection,
	## a wake race, or a transient DNS/VPN switch. TLS is excluded on purpose.
	match result:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR, \
		HTTPRequest.RESULT_TIMEOUT, HTTPRequest.RESULT_NO_RESPONSE:
			return true
	return false


func _remember_server_version(status: Dictionary) -> void:
	var version: String = str(status.get("version", "")).strip_edges()
	if version != "":
		server_version = version


func server_race_supported() -> bool:
	## 1.6.0 is the first server build with race sessions. An empty version is
	## treated as "try it": a 1.5.1 Pi answers 404 and the caller falls back.
	if server_version == "":
		return true
	var parts: PackedStringArray = server_version.split(".")
	if parts.size() < 2:
		return false
	var major: int = int(parts[0])
	var minor: int = int(parts[1])
	return major > 1 or (major == 1 and minor >= 6)


func server_pos_supported() -> bool:
	## /api/race/pos arrived in 1.6.1. An empty version is tried; the first 404
	## then disables the stream for that race. A known 1.6.0 relay skips it.
	if server_version == "":
		return true
	var parts: PackedStringArray = server_version.split(".")
	if parts.size() < 2:
		return false
	var major: int = int(parts[0])
	var minor: int = int(parts[1])
	if major != 1:
		return major > 1
	if minor != 6:
		return minor > 6
	var patch: int = int(parts[2]) if parts.size() > 2 else 0
	return patch >= 1


func server_now_ms() -> int:
	## Monotonic local clock plus the offset measured against /api/time, so a
	## wall-clock jump on the PC cannot move the race timer.
	return Time.get_ticks_msec() + server_clock_offset_ms


func sync_server_clock(samples: int = 7) -> bool:
	## NTP-style median of at least 7 samples, step-applied (no slew). Every
	## peer then derives the same race time.
	if relay_base == "":
		return false
	if _clock_sync_pending:
		# Another caller (scene setup, or the server-race RPC) is already
		# measuring. Wait for that result instead of returning a stale offset.
		for i in 180:
			await get_tree().process_frame
			if not _clock_sync_pending:
				break
		return server_clock_ready
	_clock_sync_pending = true
	var sync_base: String = relay_base
	var sync_ticket: int = _host_ticket + _join_ticket
	var offsets: Array[int] = []
	var rtts: Array[int] = []
	for i in maxi(samples, 7):
		if relay_base == "" or relay_base != sync_base \
				or sync_ticket != _host_ticket + _join_ticket:
			break
		var t0: int = Time.get_ticks_msec()
		var data: Dictionary = await _relay_get("/api/ping?t=%d" % t0, 2.0)
		if data.is_empty() and relay_base == sync_base \
				and sync_ticket == _host_ticket + _join_ticket:
			data = await _relay_get("/api/time", 2.0)
		var t1: int = Time.get_ticks_msec()
		if relay_base == "" or relay_base != sync_base \
				or sync_ticket != _host_ticket + _join_ticket:
			break
		if data.is_empty():
			continue
		var server_ms: int = int(data.get("s", data.get("time_ms", 0)))
		if server_ms <= 0:
			continue
		var rtt: int = maxi(t1 - t0, 0)
		var offset: int = server_ms - ((t0 + t1) >> 1)
		_note_relay_rtt(rtt)
		offsets.append(offset)
		rtts.append(rtt)
		await get_tree().process_frame
	_clock_sync_pending = false
	if offsets.is_empty() or relay_base == "" or relay_base != sync_base \
			or sync_ticket != _host_ticket + _join_ticket:
		return false
	offsets.sort()
	rtts.sort()
	server_clock_offset_ms = offsets[offsets.size() / 2]
	server_rtt_ms = rtts[rtts.size() / 2]
	server_clock_ready = true
	return true


func _note_relay_rtt(sample_ms: int) -> void:
	## Exponential moving average plus mean absolute deviation. The host feeds
	## this from its existing 2 s ping probe; clients feed it from the clock
	## probe, so the HUD shows the real path to the server, not only the ENet
	## hop to the host.
	var sample: float = float(clampi(sample_ms, 0, 5000))
	if _relay_rtt_ema < 0.0:
		_relay_rtt_ema = sample
	else:
		_relay_rtt_ema = lerpf(_relay_rtt_ema, sample, RELAY_RTT_ALPHA)
	if _relay_last_rtt >= 0.0:
		var delta: float = absf(sample - _relay_last_rtt)
		_relay_jitter_ema = lerpf(_relay_jitter_ema, delta, RELAY_JITTER_ALPHA)
	_relay_last_rtt = sample
	var rtt: int = int(round(_relay_rtt_ema))
	var jitter: int = int(round(_relay_jitter_ema))
	if rtt == relay_rtt_ms and jitter == relay_jitter_ms:
		return
	relay_rtt_ms = rtt
	relay_jitter_ms = jitter
	relay_metrics_changed.emit(relay_rtt_ms, relay_jitter_ms)


func _probe_relay_latency() -> void:
	## Clients have no host ping probe. A small /api/ping GET keeps the relay
	## RTT and jitter fresh for the HUD and the adaptive bot poll interval.
	if _relay_probe_pending or relay_base == "":
		return
	_relay_probe_pending = true
	var started: int = Time.get_ticks_msec()
	var data: Dictionary = await _relay_get("/api/ping?t=%d" % started, 2.0)
	if data.is_empty():
		data = await _relay_get("/api/time", 2.0)
	var rtt: int = maxi(Time.get_ticks_msec() - started, 0)
	_relay_probe_pending = false
	if data.is_empty() or not is_session_active():
		return
	_note_relay_rtt(rtt)


func server_bot_poll_interval() -> float:
	## Server bots are polled at 6-12 Hz. A slow or jittery relay gets fewer
	## polls so the HTTP queue (and the Pi's rate limiter) never saturates; the
	## default is 8 Hz, matching the current server's bot simulation cadence.
	if relay_rtt_ms <= 0:
		return 1.0 / 8.0
	var path_ms: int = relay_rtt_ms + relay_jitter_ms
	var hz: float = 8.0
	if path_ms >= 300:
		hz = 6.0
	elif path_ms >= 180:
		hz = 7.0
	elif path_ms <= 50:
		hz = 12.0
	elif path_ms <= 100:
		hz = 10.0
	return 1.0 / hz


func reset_race_state_stream() -> void:
	## A new server race starts a fresh stream. Re-enabling here also lets a
	## relay upgraded mid-session pick up /api/race/pos on the next race.
	_race_state_generation += 1
	race_state_updates = 0
	race_state_receiving = false
	race_state_stream_enabled = server_pos_supported()
	race_state_last_status = 0
	_race_state_busy = false
	_race_state_failures = 0
	race_state_stream_changed.emit(false, 0)


func stream_race_state(race_id: String, secret: String, rows: Array) -> void:
	## Host-only fire-and-forget batch of live cart states for the Pi. One
	## request is allowed in flight: if it is still running, this tick's data is
	## dropped rather than queued, so a slow relay can never build a backlog.
	if not is_host or not race_state_stream_enabled or _race_state_busy:
		return
	if relay_base == "" or race_id == "" or secret == "" or rows.is_empty():
		return
	if not server_clock_ready:
		return
	_race_state_busy = true
	var generation: int = _race_state_generation
	var payload: Dictionary = {
		"race": race_id,
		"secret": secret,
		"t": server_now_ms(),
		"p": rows,
	}
	var response: Dictionary = await _relay_post("/api/race/pos", payload,
		STATE_POST_TIMEOUT)
	if generation != _race_state_generation:
		# A new race or a disconnect owns the stream now. A late reply must not
		# clear the newer request's busy flag or count toward its HUD.
		return
	_race_state_busy = false
	race_state_last_status = _relay_http_status
	if response.is_empty() or response.get("ok") == false:
		_race_state_failures += 1
		if race_state_last_status == 404 or race_state_last_status == 405:
			# 1.6.0 and older relays have the race API but no /pos. Stop
			# posting silently instead of hammering a missing endpoint.
			race_state_stream_enabled = false
			race_state_receiving = false
			race_state_stream_changed.emit(false, race_state_updates)
		elif race_state_receiving:
			race_state_receiving = false
			race_state_stream_changed.emit(false, race_state_updates)
		return
	race_state_updates += 1
	_race_state_failures = 0
	var notify: bool = not race_state_receiving or race_state_updates <= 1 \
		or race_state_updates % 10 == 0
	race_state_receiving = true
	if notify:
		race_state_stream_changed.emit(true, race_state_updates)


func _extract_scene_track_points() -> Array:
	## Sample up to 160 3D centreline points from the active race scene's spline
	## so the Pi server simulates bots and lap validation on the exact grid map.
	var scene_node: Node = _active_gameplay_scene()
	if scene_node == null:
		return []
	var spline: Variant = scene_node.get("_spline")
	if spline == null or not (spline is Object):
		return []
	var raw_pts: Variant = (spline as Object).get("points")
	var pts: PackedVector3Array = PackedVector3Array()
	if raw_pts is PackedVector3Array:
		pts = raw_pts as PackedVector3Array
	elif raw_pts is Array:
		for item: Variant in raw_pts as Array:
			if item is Vector3:
				pts.append(item as Vector3)
	var total: int = pts.size()
	if total < 8:
		return []
	var max_samples: int = mini(total, 160)
	var out: Array = []
	for i in max_samples:
		var idx: int = mini(int(floor(float(i) * float(total) / float(max_samples))), total - 1)
		var v: Vector3 = pts[idx]
		if not v.is_finite():
			return []
		out.append([snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)])
	return out


func start_server_race(laps: int, bots: int, difficulty: int,
		max_speed: float, seed: int, track_points: Array = []) -> Dictionary:
	if relay_base == "" or relay_token == "" or not is_host:
		return {}
	if not server_clock_ready:
		await sync_server_clock()
	if not server_clock_ready:
		# Without the server clock the countdown and the race timer would be
		# nonsense. Fall back to the host-run race instead of starting one.
		return {}
	var sampled: Array = track_points if not track_points.is_empty() \
		else _extract_scene_track_points()
	var payload: Dictionary = {
		"token": relay_token,
		"laps": clampi(laps, 1, 9),
		"bots": clampi(bots, 0, 5),
		"difficulty": clampi(difficulty, 0, 2),
		"max_speed": clampf(max_speed, 8.0, 52.0),
		"seed": seed,
		# 1.7.0+ builds the server bot field from this map so its ghosts drive
		# the same layout every peer builds locally. 1.8.0+ also accepts exact
		# 3D polyline points so any grid circuit works without static baking.
		"map": GameSettings.sanitize_map_id(session_map_id),
	}
	if sampled.size() >= 8:
		payload["points"] = sampled
	var response: Dictionary = await _relay_post("/api/race/start", payload)
	var race: Variant = response.get("race", {})
	if race is Dictionary and str((race as Dictionary).get("id", "")) != "":
		return race as Dictionary
	return {}


func fetch_server_race(race_id: String) -> Dictionary:
	if relay_base == "" or race_id == "":
		return {}
	var response: Dictionary = await _relay_get("/api/race/" + race_id, 2.0)
	var race: Variant = response.get("race", {})
	return race as Dictionary if race is Dictionary else {}


func fetch_server_bots(race_id: String) -> Dictionary:
	if relay_base == "" or race_id == "":
		return {}
	var response: Dictionary = await _relay_get("/api/race/" + race_id + "/bots", 2.0)
	var bots: Variant = response.get("bots", {})
	return bots as Dictionary if bots is Dictionary else {}


func report_server_lap(race_id: String, secret: String, peer: int,
		name: String, lap: int, race_ms: int, lap_ms: int,
		finished: bool) -> Dictionary:
	if relay_base == "" or race_id == "" or secret == "":
		return {}
	var payload: Dictionary = {
		"race": race_id,
		"secret": secret,
		"peer": peer,
		"name": name.substr(0, 16),
		"lap": lap,
		"race_ms": maxi(race_ms, 0),
		"lap_ms": maxi(lap_ms, 0),
		"finished": finished,
	}
	var response: Dictionary = await _relay_post("/api/race/lap", payload)
	var official: Variant = response.get("official", {})
	return official as Dictionary if official is Dictionary else {}


func fetch_lobbies() -> Array:
	if not await _discover_relay():
		server_online = false
		server_status_changed.emit(false, "offline")
		return []
	var response: Dictionary = await _relay_get("/api/lobbies", 4.0)
	server_online = not response.is_empty()
	if not server_online:
		_invalidate_relay_route()
	server_status_changed.emit(server_online, "online" if server_online else "offline")
	var lobbies: Variant = response.get("lobbies", [])
	if not (lobbies is Array):
		return []
	var open: Array = []
	for entry: Variant in lobbies as Array:
		if open.size() >= MAX_LOBBY_ENTRIES:
			break
		if entry is Dictionary and str((entry as Dictionary).get("state", "lobby")) == "lobby":
			open.append(entry)
	return open


func _register_relay(local_port: int) -> bool:
	## The POST can still be in flight when this machine cancels hosting and
	## starts a new room. A late reply for the dead request must not overwrite
	## the live room's token and code (heartbeats would then keep the wrong
	## room alive and let the real one expire), so the host ticket is captured
	## before the await and re-checked after it.
	var ticket: int = _host_ticket
	# Advertise the address on the relay's own subnet. A Mac that is wired to
	# Ethernet while Wi-Fi is the Pi's network used to register the Ethernet
	# address, so every remote client got a lan_host it could not reach.
	var advertised_ip: String = local_address
	if _is_lan_peer_address(relay_lan_ip):
		advertised_ip = _lan_address_for(relay_lan_ip)
	elif advertised_ip == "" or not _valid_ip(advertised_ip):
		advertised_ip = _local_ip()
	var response: Dictionary = await _relay_post("/api/register", {
		"name": GameSettings.player_name,
		"local_port": local_port,
		"local_ip": advertised_ip,
		"tunnel": true,
		"public": room_public,
		"mode": session_mode,
		"event": session_event,
		"map": _advertised_room_map(),
	})
	if ticket != _host_ticket:
		return false
	if response.is_empty():
		return false
	relay_token = str(response.get("token", ""))
	relay_room_code = str(response.get("room_code", ""))
	relay_port = int(response.get("relay_port", 0))
	relay_lan_host = str(response.get("lan_host", relay_lan_ip))
	relay_public_host = str(response.get("public_host", ""))
	relay_tunnel_token = str(response.get("tunnel_token", ""))
	relay_tunnel_port = int(response.get("tunnel_port", 0))
	if relay_base_public and relay_server_host != "":
		# A hostname/tunnel is the address clients actually used.
		relay_public_host = relay_server_host
	_relay_heartbeat = 0.0
	if relay_token != "" and relay_port > 0 and relay_tunnel_token != "" \
			and relay_tunnel_port > 0:
		_start_relay_tunnel()
	return relay_token != "" and relay_port > 0


func _start_relay_tunnel() -> void:
	if _relay_tunnel != null:
		return
	# Sockets need bare IPv6 literals; a "[fd00::1]" host from a URL would make
	# StreamPeerTCP/DNS fail. _is_local_subnet() replaces the old _same_subnet_24
	# against the single _local_ip(), which a multi-homed Mac got wrong.
	var host: String = _strip_host_brackets(relay_lan_host)
	if host == "" and relay_base_public:
		host = _strip_host_brackets(relay_server_host)
	if relay_base_public and host != "" and not _is_local_subnet(host):
		host = _strip_host_brackets(relay_server_host)
	if host == "":
		host = _strip_host_brackets(relay_lan_ip)
	if host == "":
		return
	_relay_tunnel = RelayTunnel.new()
	add_child(_relay_tunnel)
	_relay_tunnel.configure(host, relay_tunnel_port, relay_tunnel_token, port)
	_relay_tunnel.tunnel_ready.connect(_on_relay_tunnel_ready)
	_relay_tunnel.tunnel_lost.connect(_on_relay_tunnel_lost)
	_relay_tunnel.start()


func _on_relay_tunnel_ready() -> void:
	## A live tunnel cancels any pending backoff and resets the schedule.
	relay_tunnel_active = true
	_tunnel_retry_attempt = 0
	_tunnel_retry_timer = -1.0


func _on_relay_tunnel_lost(reason: String = "") -> void:
	relay_tunnel_active = false
	if reason != "" and last_error == "":
		last_error = reason
	if not is_host or not relay_active or _relay_tunnel == null:
		return
	if _tunnel_retry_timer >= 0.0:
		return
	_tunnel_retry_attempt = mini(_tunnel_retry_attempt + 1, 8)
	var delay: float = minf(
		TUNNEL_RETRY_BASE * pow(2.0, float(_tunnel_retry_attempt - 1)),
		TUNNEL_RETRY_MAX) * randf_range(0.8, 1.2)
	_tunnel_retry_timer = delay


func _relay_tunnel_retry_tick(delta: float) -> void:
	## The tunnel retries on its own; after the backoff expires, rebuild it so a
	## half-open socket or a rotated token cannot wedge the room forever.
	if _tunnel_retry_timer < 0.0:
		return
	if not is_host or not relay_active or _relay_tunnel == null or relay_tunnel_active:
		_tunnel_retry_timer = -1.0
		return
	_tunnel_retry_timer -= delta
	if _tunnel_retry_timer > 0.0:
		return
	_tunnel_retry_timer = -1.0
	if _relay_tunnel.tunnel_ready.is_connected(_on_relay_tunnel_ready):
		_relay_tunnel.tunnel_ready.disconnect(_on_relay_tunnel_ready)
	if _relay_tunnel.tunnel_lost.is_connected(_on_relay_tunnel_lost):
		_relay_tunnel.tunnel_lost.disconnect(_on_relay_tunnel_lost)
	_relay_tunnel.stop()
	_relay_tunnel.queue_free()
	_relay_tunnel = null
	_start_relay_tunnel()


func _relay_heartbeat_tick(delta: float) -> void:
	if not relay_active or not is_host or _relay_busy or relay_token == "":
		return
	_relay_heartbeat += delta
	if _relay_heartbeat < RELAY_HEARTBEAT_INTERVAL:
		return
	_relay_heartbeat = 0.0
	_relay_busy = true
	# Capture the session identity: leave()/host_game() during the await must
	# not let a late reply clear the NEW session's busy flag or end its room.
	var ticket: int = _host_ticket
	var token: String = relay_token
	var response: Dictionary = await _relay_post("/api/heartbeat", {
		"token": token,
		"state": room_state,
		"players": peer_count(),
		"public": room_public,
		"mode": session_mode,
		"event": session_event,
		"map": _advertised_room_map(),
	}, HEARTBEAT_TIMEOUT)
	var status: int = _relay_http_status
	if ticket != _host_ticket or token != relay_token:
		return
	_relay_busy = false
	if not is_host or not relay_active:
		return
	if response.is_empty() or response.get("ok") != true:
		# A slow Pi can miss a heartbeat without the room being gone. A
		# definite 404/410 expires the room immediately; timeouts get retries.
		_heartbeat_failures += 1
		var detail: String = _relay_result_detail()
		if status == 404:
			detail = "room_not_found"
		elif status == 410:
			detail = "room_expired"
		elif not response.is_empty() and response.get("ok") == false:
			detail = "room_expired"
		if detail != "" and last_error == "":
			# Surface a TLS/DNS problem instead of reporting a healthy Pi as
			# "offline" when the real cause is the trust store or resolution.
			last_error = detail
			server_detail = detail
			server_status_changed.emit(server_online, server_detail)
		var definite: bool = not response.is_empty() \
			or status == 404 or status == 410
		if status == 404 or status == 410 \
				or (definite and _heartbeat_failures >= 2) \
				or _heartbeat_failures >= HEARTBEAT_MAX_FAILURES:
			_on_relay_room_lost()
		return
	_heartbeat_failures = 0


func _on_relay_room_lost() -> void:
	if not is_host or not relay_active:
		return
	var was_in_game: bool = in_game
	leave()
	session_ended.emit("The room expired on the game server. Host a new room.")
	if was_in_game:
		SceneLoader.go_to(LOBBY_SCENE, "ROOM LOST",
			"The game server lost this room. Host a new one.")


func set_room_state(state: String) -> void:
	var next: String = state if state in ["lobby", "playing", "finished"] else "lobby"
	if next == room_state:
		return
	room_state = next
	_push_room_state()


func set_room_public(value: bool) -> void:
	## Host only. Updates the live room immediately: online rooms are pushed to
	## the Pi, LAN rooms stop (or start) answering discovery broadcasts.
	if not is_host or room_public == value:
		return
	room_public = value
	if relay_active:
		_relay_heartbeat = RELAY_HEARTBEAT_INTERVAL
		_push_room_state()
	if _lan_listener != null and is_host and connection_mode == "lan":
		# A room switched to PUBLIC starts advertising immediately instead of
		# waiting for the next host restart; switching to PRIVATE stops the
		# beacons at once (the request/reply path checks room_public anyway).
		_lan_beacon_timer = LAN_BEACON_INTERVAL if value else -1.0
	# Clients show the room's PUBLIC/PRIVATE state; without this the lobby was
	# reading each client's own saved setting and could label the room wrong.
	_push_session_config()


func _push_room_state() -> void:
	## Host -> Pi only. Pause never calls this: the room keeps its current
	## server state while a client or host is looking at a menu.
	if not is_host or not relay_active or relay_token == "" or relay_base == "":
		return
	var base: String = relay_base
	var body: Dictionary = {
		"token": relay_token,
		"state": room_state,
		"players": peer_count(),
		"public": room_public,
		"mode": session_mode,
		"event": session_event,
		"map": _advertised_room_map(),
	}
	var http: HTTPRequest = _acquire_http(3.0)
	http.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray,
			_b: PackedByteArray) -> void: _release_http(http), CONNECT_ONE_SHOT)
	var error: Error = http.request(base + "/api/heartbeat", ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		_release_http(http)


func _relay_unregister_async(token: String, base: String) -> void:
	if token == "" or base == "":
		return
	var http: HTTPRequest = _acquire_http(3.0)
	http.request_completed.connect(func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		_release_http(http), CONNECT_ONE_SHOT)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var error: Error = http.request(base + "/api/unregister", headers, HTTPClient.METHOD_POST,
		JSON.stringify({"token": token}))
	if error != OK:
		_release_http(http)


func _open_server() -> int:
	for offset in PORT_RANGE:
		var candidate: int = DEFAULT_PORT + offset
		var peer := ENetMultiplayerPeer.new()
		# ENet's max_clients excludes the host, so allow 7 clients for 8 total.
		if peer.create_server(candidate, MAX_PLAYERS - 1) == OK:
			_peer = peer
			multiplayer.multiplayer_peer = _peer
			return candidate
	return 0


static func _is_macos() -> bool:
	## Code-signing / Local Network privacy behaviour only exists on macOS; the
	## platform branch is centralised here so tests can reason about it.
	return OS.has_feature("macos") or OS.get_name() == "macOS"


func local_network_hint() -> String:
	## UI helper: an actionable explanation when LAN discovery finds nothing on
	## macOS 15+. Empty elsewhere so Windows/Linux never show a Mac-only note.
	if not _is_macos():
		return ""
	return "MACOS: ENABLE LOCAL NETWORK FOR CART SLOP GP IN SYSTEM SETTINGS."


static func _interface_score(iface: Dictionary) -> int:
	## Physical-LAN score for one interface. Windows exposes friendly names
	## ("Wi-Fi", "Ethernet 2"); macOS exposes only BSD names (en0, en1, utun0,
	## bridge0, awdl0, llw0, anpi0) with an empty `friendly`, so scoring only
	## Windows words silently treats every Mac adapter as equal and lets a
	## VPN/Thunderbolt-bridge address win. Positive = likely physical LAN.
	var label: String = (str(iface.get("name", "")) + " "
		+ str(iface.get("friendly", ""))).strip_edges().to_lower()
	if label == "":
		return 0
	for bad: String in ["virtual", "vmware", "vbox", "hyper-v", "vethernet",
			"wsl", "docker", "tailscale", "zerotier", "vpn", "warp",
			"cloudflare", "loopback", "bluetooth",
			# macOS/BSD tunnel + virtual link names (friendly name is empty).
			"utun", "tun", "tap", "bridge", "awdl", "llw", "anpi", "gif",
			"stf", "ppp", "ipsec", "lo0", "lo1", "ham"]:
		if label.contains(bad):
			return -200
	for good: String in ["wi-fi", "wifi", "wireless", "wlan", "ethernet",
			"eth", "en0", "en1", "en2", "en3", "en4", "en5", "en6", "en7",
			"en8", "en9"]:
		if label.contains(good):
			return 30
	return 0


func _lan_address_candidates() -> PackedStringArray:
	## Every usable IPv4 LAN address on this machine, best first. A multi-homed
	## Mac needs more than one answer: the Wi-Fi address is right for a Wi-Fi
	## friend, Ethernet for a wired one, and a VPN/utun address for neither.
	var scored: Array[Dictionary] = []
	for iface_value: Variant in IP.get_local_interfaces():
		if not (iface_value is Dictionary):
			continue
		var iface: Dictionary = iface_value as Dictionary
		var rank: int = _interface_score(iface)
		if rank <= -200:
			continue
		for address_value: Variant in (iface.get("addresses", []) as Array):
			var address: String = str(address_value)
			if not _valid_ip(address):
				continue
			# Loopback, "this network" and IPv4 link-local are never reachable
			# room addresses; multicast/broadcast/reserved ranges are not either.
			if address.begins_with("0.") or address.begins_with("127.") \
					or address.begins_with("169.254."):
				continue
			if int(address.split(".")[0]) >= 224:
				continue
			var score: int = rank
			if _is_private_ipv4(address):
				score += 40
			elif _is_cgnat_ipv4(address):
				# Tailscale-style 100.64/10 overlay: usable but never the LAN
				# address to advertise to a friend or the Pi.
				score -= 25
			else:
				# Public IPv4 on a physical adapter can still be a real LAN
				# (campus/corporate Wi-Fi), just a weaker preference.
				score += 5
			scored.append({"address": address, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["score"]) > int(b["score"]))
	var out: PackedStringArray = PackedStringArray()
	for entry: Dictionary in scored:
		var address: String = str(entry["address"])
		if not out.has(address):
			out.append(address)
	if out.is_empty():
		# A driver or a tiny platform may hide the interface list; fall back to
		# the flat list rather than reporting only loopback.
		for value: Variant in IP.get_local_addresses():
			var address: String = str(value)
			if _valid_ip(address) and _is_private_ipv4(address) \
					and not address.begins_with("127."):
				if not out.has(address):
					out.append(address)
	return out


func _local_ip() -> String:
	## Best single "this machine's LAN address" answer, used for the LAN
	## discovery advertisement and as the Pi registration fallback. Every
	## candidate is kept in local_addresses[] because no single address is
	## reachable from every peer.
	var candidates: PackedStringArray = _lan_address_candidates()
	local_addresses = candidates
	if not candidates.is_empty():
		return candidates[0]
	return "127.0.0.1"


static func _broadcast_targets_for(address: String) -> PackedStringArray:
	## Directed-broadcast candidates for one LAN IPv4 address. Godot 4.7.2's
	## IP.get_local_interfaces() has no netmask, so cover the common private
	## prefix lengths. An extra packet sent to a non-broadcast private address
	## is harmless (the router drops it) and this beats the old single
	## hard-coded /24, which missed /8 and /16 LANs entirely.
	var out: PackedStringArray = PackedStringArray()
	var parts: PackedStringArray = address.split(".")
	if parts.size() != 4:
		return out
	var first: int = int(parts[0])
	var second: int = int(parts[1])
	out.append("%d.%d.%d.255" % [first, second, int(parts[2])])
	if first == 10:
		out.append("10.255.255.255")
	elif first == 172 and second >= 16 and second <= 31:
		out.append("172.31.255.255")
	elif first == 192 and second == 168:
		out.append("192.168.255.255")
	return out


func _discovery_targets() -> PackedStringArray:
	## Limited broadcast plus every candidate subnet's directed broadcast.
	## macOS routes the limited broadcast only out the default interface, so a
	## Mac with Ethernet as the default route never probes its Wi-Fi subnet
	## without the directed targets below.
	var out: PackedStringArray = PackedStringArray(["255.255.255.255"])
	for address: String in _lan_address_candidates():
		for target: String in _broadcast_targets_for(address):
			if not out.has(target):
				out.append(target)
	return out


func _send_discovery_probe(request: PackedByteArray, dest_port: int,
		socket: PacketPeerUDP = null) -> void:
	## Send the probe from the shared receive socket AND from one socket bound
	## to each interface address. On BSD/macOS a limited broadcast follows the
	## default route, so a Mac whose default route is a VPN/utun would never
	## probe the real Wi-Fi/Ethernet subnet otherwise.
	var targets: PackedStringArray = _discovery_targets()
	if socket != null:
		for target: String in targets:
			socket.set_dest_address(target, dest_port)
			socket.put_packet(request)
	for address: String in _lan_address_candidates():
		var sender := PacketPeerUDP.new()
		if sender.bind(0, address) != OK:
			# Windows refuses some adapter-bound sends; the wildcard socket
			# above already covered the common case.
			continue
		sender.set_broadcast_enabled(true)
		for target: String in targets:
			sender.set_dest_address(target, dest_port)
			sender.put_packet(request)
		sender.close()


func _open_probe_sockets() -> Array[Dictionary]:
	## Discovery I/O must be per interface. A Mac with a VPN default route sends
	## the limited broadcast out the VPN, so a single wildcard socket makes the
	## peer answer a VPN source address; the player then tries to join an address
	## that only exists on the VPN. One socket bound to each physical LAN address
	## keeps both directions of the exchange on that interface; the wildcard
	## socket stays as a fallback for platforms that refuse adapter-bound sends.
	## Returned entries: {"socket": PacketPeerUDP, "rank": int, "bound": String}.
	var probes: Array[Dictionary] = []
	for address: String in _lan_address_candidates():
		var udp := PacketPeerUDP.new()
		if udp.bind(0, address) != OK:
			continue
		udp.set_broadcast_enabled(true)
		probes.append({"socket": udp, "rank": 2, "bound": address})
	var wildcard := PacketPeerUDP.new()
	if wildcard.bind(0) == OK:
		wildcard.set_broadcast_enabled(true)
		probes.append({"socket": wildcard, "rank": 1, "bound": ""})
	return probes


func _broadcast_probes(probes: Array[Dictionary], request: PackedByteArray,
		dest_port: int) -> void:
	var targets: PackedStringArray = _discovery_targets()
	for probe: Dictionary in probes:
		var udp: PacketPeerUDP = probe["socket"] as PacketPeerUDP
		if udp == null:
			continue
		for target: String in targets:
			udp.set_dest_address(target, dest_port)
			udp.put_packet(request)


func _close_probes(probes: Array[Dictionary]) -> void:
	for probe: Dictionary in probes:
		var udp: PacketPeerUDP = probe["socket"] as PacketPeerUDP
		if udp != null:
			udp.close()


func _lan_address_for(remote_ip: String) -> String:
	## Our address that the given remote can reach: the one on the remote's
	## subnet first, then the best physical address. Discovery replies and the
	## local_ip advertised to the Pi both use this, so a Mac on Ethernet with a
	## Wi-Fi friend does not advertise the unreachable wired address.
	var target: String = _strip_host_brackets(remote_ip)
	var candidates: PackedStringArray = _lan_address_candidates()
	if _valid_ip(target):
		for address: String in candidates:
			if _same_subnet_24(address, target):
				return address
	if not candidates.is_empty():
		return candidates[0]
	return local_address if _valid_ip(local_address) else "127.0.0.1"


func _is_local_subnet(address: String) -> bool:
	## True when the address belongs to a subnet this machine is attached to.
	## Used to decide whether the relay's LAN hint is actually local, and to
	## accept LAN peers on public/campus IPv4 networks (a public IPv4 LAN is
	## still a LAN; rejecting it used to make campus Macs invisible).
	if not _valid_ip(_strip_host_brackets(address)):
		return false
	for local: String in _lan_address_candidates():
		if _same_subnet_24(local, _strip_host_brackets(address)):
			return true
	return false


func _is_lan_peer_address(address: String) -> bool:
	## A plausible directly-attached peer: private IPv4 or on one of our own
	## subnets. Loopback/link-local/"this network" are never valid room peers.
	var text: String = _strip_host_brackets(address)
	if not _valid_ip(text):
		return false
	if text.begins_with("0.") or text.begins_with("127.") \
			or text.begins_with("169.254."):
		return false
	return _is_private_ipv4(text) or _is_local_subnet(text)


static func _strip_host_brackets(host: String) -> String:
	## URL/IPv6 details: "http://[fd00::1]:42777" keeps its square brackets in
	## the authority, but StreamPeerTCP/ENet need the bare literal. Strip them
	## for socket use; _url_host() re-adds them when composing an HTTP URL.
	var text: String = host.strip_edges()
	if text.begins_with("[") and text.ends_with("]"):
		return text.substr(1, text.length() - 2)
	return text


static func _url_host(host: String) -> String:
	## Bracket an IPv6 literal again so relay_base stays a valid URL.
	var text: String = _strip_host_brackets(host)
	return "[" + text + "]" if text.contains(":") else text


static func _is_ipv6_literal(text: String) -> bool:
	## Loose "is this already an address" test. ENet/StreamPeerTCP accept the
	## bare IPv6 form Godot prints (e.g. "fd00:0:0:0:0:0:0:1"), so a literal
	## must never be handed to the DNS resolver (macOS would fail it).
	var clean: String = _strip_host_brackets(text)
	if clean.contains("%"):
		clean = clean.get_slice("%", 0)
	if not clean.contains(":"):
		return false
	for character: String in clean:
		if not "0123456789abcdefABCDEF:.".contains(character):
			return false
	return clean.count(":") >= 2


func _is_ip_literal(text: String) -> bool:
	var clean: String = _strip_host_brackets(text)
	return _valid_ip(clean) or _is_ipv6_literal(clean)


func _resolve_host_async(host: String, timeout_ms: int) -> String:
	## Bounded, non-blocking hostname resolution. IP.resolve_hostname() blocks
	## the main loop, and on macOS a ".local"/Bonjour name or a dead VPN
	## resolver can stall for seconds (the whole game freezes). The resolver
	## queue is polled from the main loop instead; TYPE_IPV4 avoids the macOS
	## "localhost resolves to ::1 first, server only listens on IPv4" trap.
	var clean: String = _strip_host_brackets(host)
	if _is_ip_literal(clean):
		return clean
	var queue_id: int = IP.resolve_hostname_queue_item(clean, IP.TYPE_IPV4)
	if queue_id == -1:
		# Queue unavailable (very old/small platforms): accept the blocking
		# call as a last resort so behaviour does not regress.
		return _strip_host_brackets(IP.resolve_hostname(clean, IP.TYPE_IPV4))
	var deadline: int = Time.get_ticks_msec() + maxi(timeout_ms, 250)
	while true:
		var status: int = IP.get_resolve_item_status(queue_id)
		if status == IP.RESOLVER_STATUS_DONE:
			var address: String = _strip_host_brackets(IP.get_resolve_item_address(queue_id))
			IP.erase_resolve_item(queue_id)
			return address
		if status == IP.RESOLVER_STATUS_ERROR:
			IP.erase_resolve_item(queue_id)
			return ""
		if Time.get_ticks_msec() >= deadline:
			IP.erase_resolve_item(queue_id)
			return ""
		await get_tree().process_frame
	return ""


func _check_suspend() -> void:
	## macOS laptops sleep on lid close. Engine ticks can stop advancing while
	## wall time (and the Pi's clock) keeps moving, so the measured relay clock
	## offset, pooled HTTP keep-alive sockets and the relay tunnel all go stale.
	## A wall-vs-tick gap is the portable signal for "we were suspended".
	var ticks: int = Time.get_ticks_msec()
	var wall: int = int(Time.get_unix_time_from_system() * 1000.0)
	if _last_tick_ms == 0:
		_last_tick_ms = ticks
		_last_wall_ms = wall
		return
	var tick_delta: int = ticks - _last_tick_ms
	var wall_delta: int = wall - _last_wall_ms
	_last_tick_ms = ticks
	_last_wall_ms = wall
	if wall_delta <= 0:
		# Wall clock stepped backwards (NTP correction); rebaseline only.
		return
	if wall_delta - tick_delta < 3000:
		return
	_on_system_resumed()


func _on_system_resumed() -> void:
	## Repair session state after a sleep/wake or a long main-thread stall.
	_suspend_count += 1
	_drop_http_pool()
	# The relay clock offset belongs to the pre-sleep path; re-measure before
	# the next server race so countdowns/lap times cannot shift by the sleep.
	server_clock_ready = false
	server_clock_offset_ms = 0
	_relay_probe_pending = false
	_host_ping_pending = false
	_race_state_busy = false
	if _relay_tunnel != null and _relay_tunnel.has_method("reconnect"):
		# A half-open TCP tunnel can look CONNECTED forever after wake; force a
		# fresh handshake instead of waiting for the next write to fail.
		_relay_tunnel.call("reconnect")
		relay_tunnel_active = false
	if is_host and relay_active:
		_relay_heartbeat = RELAY_HEARTBEAT_INTERVAL
		_heartbeat_failures = 0


func _drop_http_pool() -> void:
	## Free keep-alive HTTPRequest objects: after sleep/wake (or a VPN switch)
	## their pooled TCP/TLS connections point at a network path that is gone,
	## and the first request on each would fail with RESULT_CONNECTION_ERROR.
	for http: HTTPRequest in _http_idle:
		if is_instance_valid(http):
			http.cancel_request()
			http.queue_free()
	_http_idle.clear()


func _relay_result_detail() -> String:
	## Machine-readable transport failure for the lobby/updater. HTTP status 0
	## means "no HTTP answer at all", which used to be reported as "server
	## offline" even when the real cause was a TLS handshake failure.
	match _relay_http_result:
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "tls_error"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "dns_error"
		HTTPRequest.RESULT_TIMEOUT, HTTPRequest.RESULT_NO_RESPONSE:
			return "timeout"
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "unreachable"
	return ""


func _join_timeout_reason(was_lan: bool) -> String:
	var transport: String = _join_transport_reason()
	if transport != "":
		return transport
	var reason: String = "Connection timed out. The room may have closed, or the server is unreachable. Hint: retry in a moment."
	if was_lan and _is_macos():
		reason += " On macOS, allow Cart Slop GP under System Settings > Privacy & Security > Local Network."
	return reason


func _lan_version_matches(room_version: String) -> bool:
	var local: String = str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	if local == "":
		return true
	if room_version.strip_edges() == "":
		return false
	return room_version.strip_edges() == local


func _parse_lan_room_reply(packet_text: String, sender_ip: String) -> Dictionary:
	## Parse a LAN discovery answer/beacon. The packet SOURCE address wins over
	## the advertised "host" field: the reply is guaranteed routable back to the
	## sender, while the advertised address comes from whichever adapter the
	## host picked for itself (a multi-homed Mac can pick a VPN/utun address).
	## This also makes an old host with a wrong local_address joinable.
	## Cheap prefix gate first: port 42779 also receives unrelated UDP noise on
	## a busy LAN, and handing every packet to JSON.parse_string() prints engine
	## parse errors for each one.
	if not packet_text.contains("cartslop-lan"):
		return {}
	var parsed: Variant = JSON.parse_string(packet_text)
	if not (parsed is Dictionary):
		return {}
	var room: Dictionary = parsed as Dictionary
	if str(room.get("service", "")) != "cartslop-lan":
		return {}
	var open_port: int = int(room.get("port", 0))
	if open_port <= 0 or open_port > 65535:
		return {}
	var advertised: String = _strip_host_brackets(str(room.get("host", "")))
	var source: String = _strip_host_brackets(sender_ip)
	var host: String = ""
	if _is_lan_peer_address(source):
		host = source
	elif _is_lan_peer_address(advertised):
		host = advertised
	if host == "":
		return {}
	var raw_mode: String = str(room.get("mode", GameSettings.GAME_SANDBOX)).strip_edges().to_lower()
	var clean_mode: String = GameSettings.GAME_MINIGAMES \
		if raw_mode == GameSettings.GAME_MINIGAMES else GameSettings.GAME_SANDBOX
	var raw_event: String = str(room.get("event", EVENT_RACE)).strip_edges().to_lower()
	var clean_event: String = raw_event \
		if (raw_event == EVENT_RACE or raw_event in MINIGAME_EVENTS) \
		else (EVENT_RACE if clean_mode == GameSettings.GAME_MINIGAMES else "")
	var raw_state: String = str(room.get("state", "lobby")).strip_edges().to_lower()
	var clean_state: String = raw_state if raw_state in ["lobby", "playing", "finished"] else "lobby"
	var raw_map: String = str(room.get("map", "")).strip_edges().to_lower()
	return {
		"name": GameSettings.sanitize_name(str(room.get("name", "HOST"))),
		"host": host,
		"port": open_port,
		"players": clampi(int(room.get("players", 1)), 1, MAX_PLAYERS),
		"mode": clean_mode,
		"event": clean_event,
		"state": clean_state,
		"map": raw_map if TrackDefs.has_theme_id(raw_map) \
			else GameSettings.sanitize_map_id(raw_map),
		"version": str(room.get("version", "")).strip_edges(),
	}


func _is_public_ipv4(text: String) -> bool:
	if not _valid_ip(text):
		return false
	if text.begins_with("10.") or text.begins_with("127.") or text.begins_with("169.254."):
		return false
	if text.begins_with("192.168."):
		return false
	if text.begins_with("172."):
		var second: int = int(text.split(".")[1])
		if second >= 16 and second <= 31:
			return false
	if _is_cgnat_ipv4(text):
		return false
	return true


func _is_cgnat_ipv4(text: String) -> bool:
	## RFC 6598 shared address space (carrier-grade NAT).
	if not _valid_ip(text) or not text.begins_with("100."):
		return false
	var second: int = int(text.split(".")[1])
	return second >= 64 and second <= 127


# --------------------------------------------------------------------------
# joining


func set_relay_server(raw: String) -> void:
	## Accepts "1.2.3.4", "1.2.3.4:42777", "cartslop.example.com",
	## or a full http(s) URL. Empty means "use LAN discovery".
	var text: String = raw.strip_edges()
	_relay_forced = text != ""
	GameSettings.set_relay_server(text)
	relay_server_url = ""
	relay_server_host = ""
	relay_server_http_port = 42777
	var was_public: bool = relay_base_public
	relay_base_public = false
	if text == "":
		if was_public:
			relay_base = ""
		return
	var lower_text: String = text.to_lower()
	var secure: bool = lower_text.begins_with("https://")
	var rest: String = text
	if secure:
		rest = rest.substr(8)
	elif lower_text.begins_with("http://"):
		rest = rest.substr(7)
	rest = rest.trim_suffix("/")
	var authority: String = rest.get_slice("/", 0)
	var host: String = authority
	var default_port: int = 443 if secure else 42777
	var http_port: int = default_port
	if authority.begins_with("["):
		var close_idx: int = authority.find("]")
		if close_idx <= 1:
			return
		# Store the bare IPv6 literal: sockets (ENet/StreamPeerTCP) reject the
		# URL bracket syntax. _url_host() re-adds brackets for the HTTP base.
		host = _strip_host_brackets(authority.substr(0, close_idx + 1))
		if close_idx + 1 < authority.length() and authority[close_idx + 1] == ":":
			http_port = int(authority.substr(close_idx + 2))
	elif authority.contains(":"):
		var parts: PackedStringArray = authority.split(":")
		host = _strip_host_brackets(parts[0])
		http_port = int(parts[1]) if parts.size() > 1 else default_port
	if host == "" or http_port <= 0 or http_port > 65535:
		return
	relay_server_host = _strip_host_brackets(host)
	relay_server_http_port = http_port
	relay_server_url = ("https://" if secure else "http://") \
		+ _url_host(relay_server_host) + ":" + str(relay_server_http_port)
	relay_base = relay_server_url
	relay_base_public = true


func set_local_name(raw_name: String) -> void:
	GameSettings.set_player_name(raw_name)
	if is_session_active():
		rpc("_net_set_name", multiplayer.get_unique_id(), GameSettings.player_name)


func name_of(peer_id: int) -> String:
	return str(player_names.get(peer_id, "PLAYER %d" % peer_id))


func color_of(peer_id: int) -> Color:
	## A peer's chosen name tag colour; white when unknown (e.g. solo rivals).
	return player_colors.get(peer_id, Color.WHITE)


func set_local_tag_color(hex: String) -> void:
	## Persist locally, then announce to the session so every label updates.
	GameSettings.set_player_tag_color(hex)
	if is_session_active():
		rpc("_net_set_tag_color", multiplayer.get_unique_id(), GameSettings.player_tag_color)
	tag_colors_changed.emit()


func active_vehicle_channel() -> String:
	## Which Garage slot applies to the room's current mode ("racing", "minigame", "sandbox").
	var sc: String = session_scene
	if sc == RACE_SCENE or session_event == EVENT_RACE:
		return "racing"
	if sc in [CARGO_SCENE, KNOCKOUT_SCENE, BOMB_TAG_SCENE] or session_event in MINIGAME_EVENTS:
		return "minigame"
	if session_mode == GameSettings.GAME_MINIGAMES:
		return "racing"
	return "sandbox"


func _local_loadout_dict() -> Dictionary:
	return {
		"sandbox": GameSettings.vehicle_for_channel("sandbox"),
		"racing": GameSettings.vehicle_for_channel("racing"),
		"minigame": GameSettings.vehicle_for_channel("minigame"),
		"racer_color": GameSettings.racer_color,
		"allocation": GameSettings.racing_allocation(),
	}


static func _sanitize_racer_hex(raw: String) -> String:
	var clean: String = raw.strip_edges().trim_prefix("#").to_lower()
	if clean.length() != 6:
		return "e63946"
	for ch: String in clean:
		if not "0123456789abcdef".contains(ch):
			return "e63946"
	return clean


static func _sanitize_vehicle_loadout(raw: Dictionary) -> Dictionary:
	var alloc_raw: Variant = raw.get("allocation", {})
	var alloc_dict: Dictionary = alloc_raw as Dictionary if alloc_raw is Dictionary else {}
	return {
		"sandbox": GameSettings.sanitize_vehicle_id(str(raw.get("sandbox", VehicleCatalog.DEFAULT_ID))),
		"racing": GameSettings.sanitize_racing_vehicle_id(str(raw.get("racing", VehicleCatalog.DEFAULT_RACING_ID))),
		"minigame": GameSettings.sanitize_vehicle_id(str(raw.get("minigame", VehicleCatalog.DEFAULT_ID))),
		"racer_color": _sanitize_racer_hex(str(raw.get("racer_color", "e63946"))),
		"allocation": VehicleCatalog.sanitize_allocation(alloc_dict) if not alloc_dict.is_empty() else VehicleCatalog.default_allocation(),
	}


func set_session_vehicle_mode(mode: String) -> void:
	## Host only. Switches between "pick_own" (every player uses their own car
	## and racing tune) and "shared" (everyone drives the host's car).
	var clean: String = VEHICLE_MODE_SHARED if mode == VEHICLE_MODE_SHARED else VEHICLE_MODE_PICK_OWN
	GameSettings.set_multiplayer_vehicle_mode(clean)
	if not is_host:
		return
	session_vehicle_mode = clean
	session_shared_vehicle = GameSettings.vehicle_for_channel(active_vehicle_channel())
	session_shared_racer_color = GameSettings.racer_color
	session_racing_car_id = sanitize_racing_car_id(GameSettings.racing_vehicle_id())
	session_racing_allocation = sanitize_racing_allocation(GameSettings.racing_allocation())
	player_vehicles[1] = _local_loadout_dict()
	_push_session_config()
	vehicles_changed.emit()


func set_local_vehicle_loadout() -> void:
	## Broadcasts the local player's Garage choices (vehicles, PRO RACER paint,
	## and racing stat allocation) to the multiplayer room.
	var loadout: Dictionary = _local_loadout_dict()
	if not is_session_active():
		vehicles_changed.emit()
		return
	var my_id: int = multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 1
	player_vehicles[my_id] = loadout
	if is_connected_to_server():
		rpc("_net_set_vehicle_loadout", my_id, loadout)
	if is_host:
		session_shared_vehicle = GameSettings.vehicle_for_channel(active_vehicle_channel())
		session_shared_racer_color = GameSettings.racer_color
		session_racing_car_id = sanitize_racing_car_id(GameSettings.racing_vehicle_id())
		session_racing_allocation = sanitize_racing_allocation(GameSettings.racing_allocation())
		_push_session_config()
	vehicles_changed.emit()


func is_shared_vehicle_mode() -> bool:
	return is_session_active() and session_vehicle_mode == VEHICLE_MODE_SHARED


func effective_vehicle_for(peer_id: int, channel: String = "") -> String:
	## Single authoritative vehicle resolver used by every gameplay scene and
	## CartPlayer so host and clients always agree on every car in the match.
	var ch: String = channel if channel != "" else active_vehicle_channel()
	if not is_session_active():
		return GameSettings.vehicle_for_channel(ch)
	if session_vehicle_mode == VEHICLE_MODE_SHARED:
		if player_vehicles.has(1):
			var host_lo: Dictionary = player_vehicles[1] as Dictionary
			var from_host: String = str(host_lo.get(ch, ""))
			if from_host != "":
				return GameSettings.sanitize_racing_vehicle_id(from_host) if ch == "racing" \
					else GameSettings.sanitize_vehicle_id(from_host)
		if ch == "racing" and session_racing_car_id != "":
			return sanitize_racing_car_id(session_racing_car_id)
		return GameSettings.sanitize_vehicle_id(session_shared_vehicle)
	# PICK OWN mode: every player uses their own Garage car!
	var my_id: int = multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 0
	if peer_id == my_id:
		return GameSettings.vehicle_for_channel(ch)
	if player_vehicles.has(peer_id):
		var peer_lo: Dictionary = player_vehicles[peer_id] as Dictionary
		var pick: String = str(peer_lo.get(ch, ""))
		if pick != "":
			return GameSettings.sanitize_racing_vehicle_id(pick) if ch == "racing" \
				else GameSettings.sanitize_vehicle_id(pick)
	return VehicleCatalog.DEFAULT_ID


func effective_racer_color_for(peer_id: int) -> String:
	if not is_session_active():
		return GameSettings.racer_color
	if session_vehicle_mode == VEHICLE_MODE_SHARED:
		if player_vehicles.has(1):
			return _sanitize_racer_hex(str((player_vehicles[1] as Dictionary).get("racer_color", session_shared_racer_color)))
		return _sanitize_racer_hex(session_shared_racer_color)
	var my_id: int = multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 0
	if peer_id == my_id:
		return GameSettings.racer_color
	if player_vehicles.has(peer_id):
		return _sanitize_racer_hex(str((player_vehicles[peer_id] as Dictionary).get("racer_color", "e63946")))
	return "e63946"


func effective_racing_allocation_for(peer_id: int) -> Dictionary:
	if not is_session_active():
		return GameSettings.racing_allocation()
	if session_vehicle_mode == VEHICLE_MODE_SHARED:
		if not session_racing_allocation.is_empty():
			return session_racing_allocation
		if player_vehicles.has(1):
			var host_alloc: Variant = (player_vehicles[1] as Dictionary).get("allocation", {})
			if host_alloc is Dictionary and not (host_alloc as Dictionary).is_empty():
				return sanitize_racing_allocation(host_alloc as Dictionary)
		return VehicleCatalog.default_allocation()
	var my_id: int = multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else 0
	if peer_id == my_id:
		return GameSettings.racing_allocation()
	if player_vehicles.has(peer_id):
		var peer_alloc: Variant = (player_vehicles[peer_id] as Dictionary).get("allocation", {})
		if peer_alloc is Dictionary and not (peer_alloc as Dictionary).is_empty():
			return sanitize_racing_allocation(peer_alloc as Dictionary)
	return VehicleCatalog.default_allocation()


func join_public_room(room: Dictionary) -> void:
	## Join a room picked from the public browser. No code is shown or typed:
	## the fresh /api/lobbies row already carries the relay address.
	if join_pending or is_session_active():
		return
	_join_ticket += 1
	var ticket: int = _join_ticket
	join_pending = true
	_join_started_ms = Time.get_ticks_msec()
	# A fresh public/online join owns no LAN permission retry.
	_lan_join_retry = 0
	_lan_join_host = ""
	_lan_join_port = 0
	if str(room.get("state", "lobby")).strip_edges().to_lower() != "lobby":
		join_pending = false
		join_failed.emit("That match already started. Ask the host to return to the lobby. Hint: wait for the lobby.")
		return
	if int(room.get("players", 1)) >= MAX_PLAYERS:
		join_pending = false
		join_failed.emit("That room is full. Pick another room or wait for a slot. Hint: try a different room.")
		return
	if room.has("public") and not bool(room.get("public")):
		join_pending = false
		join_failed.emit("That room is private. Ask the host for the code.")
		return
	# A row can be minutes old: the host may have switched to PRIVATE or
	# started the race since the browser fetched it. Re-check the live list.
	var listing: Array = await fetch_lobbies()
	if ticket != _join_ticket or not join_pending:
		return
	var live_row: Dictionary = {}
	for entry: Variant in listing:
		if not (entry is Dictionary):
			continue
		var row: Dictionary = entry as Dictionary
		if int(row.get("relay_port", 0)) == int(room.get("relay_port", 0)) \
				and str(row.get("name", "")) == str(room.get("name", "")):
			live_row = row
			break
	if live_row.is_empty():
		join_pending = false
		var transport: String = _join_transport_reason()
		if transport != "":
			join_failed.emit(transport)
		else:
			join_failed.emit("That room is no longer public. Ask the host for the code.")
		return
	room = live_row
	if str(room.get("state", "lobby")).strip_edges().to_lower() != "lobby":
		join_pending = false
		join_failed.emit("That match already started. Ask the host to return to the lobby. Hint: wait for the lobby.")
		return
	if int(room.get("players", 1)) >= MAX_PLAYERS:
		join_pending = false
		join_failed.emit("That room is full. Pick another room or wait for a slot. Hint: try a different room.")
		return
	var host: String = ""
	if relay_base_public:
		host = relay_server_host
		if host == "":
			host = str(room.get("public_host", ""))
	if host == "":
		host = str(room.get("lan_host", ""))
	var relay_port: int = int(room.get("relay_port", 0))
	if host == "" or relay_port <= 0:
		join_pending = false
		join_failed.emit("That room is not accepting players yet. Try again.")
		return
	set_meta("last_join_code", "")
	join_status_changed.emit("Joining the room...")
	_connect_to(host, relay_port, "pi")


func join_game(raw_code: String) -> void:
	## Only a 5-letter room code from the Pi is accepted. Never an IP address,
	## hostname, port, or hand-built 14-character address code.
	if join_pending or is_session_active():
		return
	_join_ticket += 1
	var ticket: int = _join_ticket
	join_pending = true
	_join_started_ms = Time.get_ticks_msec()
	# A fresh code join owns no LAN permission retry.
	_lan_join_retry = 0
	_lan_join_host = ""
	_lan_join_port = 0
	var text: String = raw_code.strip_edges().to_upper().replace(" ", "").replace("-", "")
	if not _valid_room_code(text):
		join_pending = false
		join_failed.emit("Enter the 5-letter room code from the host. IP addresses are not used.")
		return
	join_status_changed.emit("Connecting to the Cart Slop server...")
	if not await _discover_relay():
		if ticket != _join_ticket:
			return
		join_pending = false
		# A code join that cannot reach the service must flip the lobby into
		# its offline state, not just print a line inside the JOIN card.
		server_online = false
		server_detail = "offline"
		var discover_reason: String = _join_transport_reason()
		if discover_reason != "":
			server_detail = _relay_result_detail()
			last_error = server_detail
		server_status_changed.emit(false, server_detail)
		if discover_reason != "":
			join_failed.emit(discover_reason)
		else:
			join_failed.emit("The Cart Slop server is offline. Check the internet, or join a LAN room.")
		return
	if ticket != _join_ticket or not join_pending:
		return
	join_status_changed.emit("Finding room %s..." % text)
	var room: Dictionary = await _relay_get("/api/room/" + text, 4.0)
	if ticket != _join_ticket or not join_pending:
		return
	if room.is_empty():
		join_pending = false
		# A 404 can be a typo, but an empty result after a network failure
		# would otherwise keep retrying the same dead route.
		_invalidate_relay_route()
		var transport: String = _join_transport_reason(text)
		if transport != "":
			join_failed.emit(transport)
		elif _relay_http_status == 404:
			join_failed.emit("Room %s was not found. Ask the host for a fresh code. Hint: check the code and retry." % text)
		else:
			join_failed.emit("Room %s was not found. Ask the host for a fresh code." % text)
		return
	if int(room.get("players", 1)) >= MAX_PLAYERS:
		join_pending = false
		join_failed.emit("That room is full. Pick another room or wait for a slot. Hint: try a different room.")
		return
	var state: String = str(room.get("state", "lobby")).to_lower()
	if state != "lobby":
		join_pending = false
		join_failed.emit("That match already started. Ask the host to return to the lobby. Hint: wait for the lobby.")
		return
	var host: String = str(room.get("lan_host", ""))
	if relay_base_public:
		# The client reached the Pi at its public address; the relay lives there.
		host = relay_server_host if relay_server_host != "" else str(room.get("public_host", ""))
		if host == "":
			host = str(room.get("lan_host", ""))
	var relay_port: int = int(room.get("relay_port", 0))
	if host == "" or relay_port <= 0:
		join_pending = false
		join_failed.emit("That room is not accepting players yet. Try again.")
		return
	if ticket != _join_ticket or not join_pending:
		return
	_connect_to(host, relay_port, "pi")


func _connect_to(connect_ip: String, connect_port: int, mode: String) -> void:
	# A Pi client keeps the relay's HTTP route after the ENet handshake: the
	# shared race clock, the server bot poll and the latency probe all use it.
	# leave() clears the route so a failed/replaced session cannot leak it.
	var keep_relay: String = relay_base if mode != "lan" else ""
	var keep_public: bool = relay_base_public if mode != "lan" else false
	var intended_lan: bool = mode == "lan"
	leave()
	var ticket: int = _join_ticket
	if keep_relay != "":
		relay_base = keep_relay
		relay_base_public = keep_public
	# _connect_to owns the join lifecycle from here: keep join_pending set
	# across the async DNS step so a second click cannot start a competing join.
	join_pending = true
	_join_started_ms = Time.get_ticks_msec()
	var host: String = _strip_host_brackets(connect_ip)
	if not _is_ip_literal(host):
		# Never block the main loop on DNS: a macOS ".local"/VPN resolver can
		# stall for seconds and freeze the game. The resolver queue is polled
		# with a deadline instead, and an IPv6 literal is never resolved.
		join_status_changed.emit("Looking up the room address...")
		host = await _resolve_host_async(host, 3000)
		if ticket != _join_ticket or not join_pending:
			return
		if host == "":
			join_pending = false
			join_failed.emit("Could not resolve the room address (DNS). Check DNS/VPN settings, then try again. Hint: check network and retry.")
			return
	if connect_port <= 0 or connect_port > 65535:
		join_pending = false
		join_failed.emit("That room is not accepting players yet.")
		return
	# Remember the LAN destination: macOS may refuse the first connect while
	# the Local Network alert is up, and _on_connection_failed() retries once.
	if intended_lan:
		_lan_join_host = host
		_lan_join_port = connect_port
	join_status_changed.emit("Connecting to the room...")
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(host, connect_port)
	if error != OK:
		join_pending = false
		join_failed.emit("Could not start the connection. Try again.")
		return
	_peer = peer
	multiplayer.multiplayer_peer = peer
	connection_mode = "lan" if intended_lan else "pi"
	is_client = true
	in_game = false
	room_state = "lobby"
	player_names.clear()


func leave() -> void:
	_host_ticket += 1 ## Cancels an in-flight host_game() await chain.
	_join_ticket += 1 ## Cancels an in-flight join_game() await chain.
	_stop_lan_listener()
	clear_scene_ready()
	room_state = "lobby"
	if relay_active and relay_token != "":
		_relay_unregister_async(relay_token, relay_base)
	if _peer != null:
		_peer.close()
	if multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer != _peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	is_host = false
	is_client = false
	in_game = false
	join_pending = false
	join_code = ""
	relay_active = false
	relay_token = ""
	relay_port = 0
	relay_lan_host = ""
	relay_public_host = ""
	relay_room_code = ""
	relay_base = ""
	_heartbeat_failures = 0
	if not _relay_forced:
		relay_server_url = ""
		relay_server_host = ""
	relay_base_public = false
	relay_tunnel_active = false
	relay_tunnel_token = ""
	relay_tunnel_port = 0
	if _relay_tunnel != null:
		if _relay_tunnel.tunnel_ready.is_connected(_on_relay_tunnel_ready):
			_relay_tunnel.tunnel_ready.disconnect(_on_relay_tunnel_ready)
		if _relay_tunnel.tunnel_lost.is_connected(_on_relay_tunnel_lost):
			_relay_tunnel.tunnel_lost.disconnect(_on_relay_tunnel_lost)
		_relay_tunnel.stop()
		_relay_tunnel.queue_free()
		_relay_tunnel = null
	public_address = ""
	latency_ms = 0
	host_ping_ms = 0
	_host_ping_pending = false
	relay_rtt_ms = 0
	relay_jitter_ms = 0
	_relay_rtt_ema = -1.0
	_relay_jitter_ema = 0.0
	_relay_last_rtt = -1.0
	_relay_probe_timer = 0.0
	_relay_probe_pending = false
	_relay_http_status = 0
	_relay_http_result = 0
	# The next session starts with a clean discovery state; a stale macOS hint
	# from the previous scan must not leak onto a fresh lobby.
	discovery_hint = ""
	# The clock offset belongs to the relay this session measured. Reusing it
	# after a relay restart would put the countdown and the race timer on the
	# old server's clock, so force the next race to measure again.
	server_clock_ready = false
	server_clock_offset_ms = 0
	_relay_busy = false
	_tunnel_retry_timer = -1.0
	_tunnel_retry_attempt = 0
	reset_race_state_stream()
	last_error = ""
	input_locked = false
	player_names.clear()
	player_colors.clear()
	player_vehicles.clear()
	ping_table.clear()
	_name_stamp.clear()
	_ping_stamp.clear()
	_color_stamp.clear()
	_vehicle_stamp.clear()
	_ping_request_stamp.clear()
	race_standings.clear()
	# A stale host build must not leak into the next session before its first
	# config packet; player_cart.gd treats empty as "use the local save".
	session_racing_car_id = ""
	session_racing_allocation = {}
	session_vehicle_mode = VEHICLE_MODE_PICK_OWN
	session_shared_vehicle = VehicleCatalog.DEFAULT_ID
	session_shared_racer_color = "e63946"
	# No room means no mode/scene/teams. A new session starts from its own
	# host snapshot instead of inheriting the last room's DELIVER split.
	session_scene = GAME_SCENE
	session_event = ""
	session_minigame = ""
	_peer_teams.clear()
	teams_locked = false
	# Keep _last_pick_map/_last_pick_theme/_last_pick_event: they are the
	# local picker's memory, not session state, and re-hosting should default
	# to the game the host confirmed last.
	_pending_event = ""


# --------------------------------------------------------------------------
# session config (host -> everyone, while still in the lobby)


func configure_session(mode: String, bots: bool, count: int,
		map_id: String = "", scene: String = "") -> void:
	## Host only. `scene` names the exact gameplay scene when the caller knows
	## it (the lobby's RACING/DELIVER choice). When omitted, a changed pocket
	## picker selection decides race vs DELIVER; otherwise the current event
	## is kept, so adjusting bots never flips the gamemode.
	if not is_host:
		return
	session_mode = mode
	session_bots = bots
	session_bot_count = clampi(count, 0, MAX_BOT_COUNT)
	session_bot_difficulty = clampi(GameSettings.minigame_difficulty, 0, 2)
	# The map is sanitised before it leaves this machine. An empty override
	# means "use the host's current pick", which is what older call sites do.
	session_map_id = GameSettings.sanitize_map_id(
		map_id if map_id != "" else GameSettings.selected_map)
	if mode != GameSettings.GAME_MINIGAMES:
		session_event = ""
		_pending_event = ""
		_last_pick_event = ""
	elif scene != "" and scene in ALLOWED_SCENES and scene != GAME_SCENE:
		session_event = event_for_scene(scene)
		_pending_event = ""
		_last_pick_event = session_event
		_note_pick_snapshot()
	else:
		session_event = _infer_session_event(mode)
	session_scene = scene_for_event(session_event)
	session_minigame = _sanitize_minigame_theme(session_event, GameSettings.selected_minigame) \
		if session_event in MINIGAME_EVENTS else ""
	# The racing build travels in the same reliable packet as the map id. It is
	# sanitised before it leaves (the receiver sanitises again), and a peer
	# that never receives the trailing fields keeps its own saved build.
	session_racing_car_id = sanitize_racing_car_id(
		GameSettings.racing_vehicle_id())
	session_racing_allocation = sanitize_racing_allocation(
		GameSettings.racing_allocation())
	session_shared_vehicle = GameSettings.vehicle_for_channel(active_vehicle_channel())
	session_shared_racer_color = GameSettings.racer_color
	player_vehicles[1] = _local_loadout_dict()
	_push_session_config()


func _note_pick_snapshot() -> void:
	## Remember which map/theme the menu just wrote. Called after a scene was
	## supplied explicitly and after an inferred pick, so the next inference
	## compares against the pick that is actually active.
	_last_pick_map = GameSettings.selected_map
	_last_pick_theme = GameSettings.selected_minigame


func _on_settings_session_changed() -> void:
	## A write from the map / arena picker (or a settings load) happened. Note
	## which field actually moved; the next configure_session() consumes it.
	var theme_id: String = GameSettings.selected_minigame
	var map_id: String = GameSettings.selected_map
	if theme_id != _last_pick_theme and TrackDefs.has_theme_id(theme_id):
		var ev: String = event_for_theme_id(theme_id)
		if ev != "":
			_pending_event = ev
			_last_pick_event = ev
	elif map_id != _last_pick_map:
		_pending_event = EVENT_RACE
		_last_pick_event = EVENT_RACE


func _infer_session_event(mode: String) -> String:
	## Menu path (minigames_menu calls configure_session without a scene).
	## A pending picker write identifies the card the host just confirmed;
	## changed values are the fallback; then the last confirmed pick, so a
	## re-host after a match keeps the game that was actually played.
	if mode != GameSettings.GAME_MINIGAMES:
		_note_pick_snapshot()
		_pending_event = ""
		return ""
	var theme_id: String = GameSettings.selected_minigame
	var map_id: String = GameSettings.selected_map
	var theme_changed: bool = theme_id != _last_pick_theme
	var map_changed: bool = map_id != _last_pick_map
	var event: String = session_event
	if _pending_event != "":
		event = _pending_event
	elif theme_changed and TrackDefs.has_theme_id(theme_id):
		var ev_from_theme: String = event_for_theme_id(theme_id)
		if ev_from_theme != "":
			event = ev_from_theme
	elif map_changed:
		event = EVENT_RACE
	_pending_event = ""
	if event != EVENT_RACE and not (event in MINIGAME_EVENTS):
		event = _last_pick_event
	if event != EVENT_RACE and not (event in MINIGAME_EVENTS):
		var fallback_ev: String = event_for_theme_id(theme_id)
		event = fallback_ev if fallback_ev != "" else EVENT_RACE
	_note_pick_snapshot()
	_last_pick_event = event
	return event


func _push_session_config() -> void:
	## One reliable host -> peer config packet. The trailing racing fields are
	## optional on the receiver so a peer without them still gets mode, bots and
	## map, then falls back to its local racing build.
	if not is_session_active() or multiplayer.multiplayer_peer == null \
			or not is_connected_to_server():
		return
	rpc("_net_session_config", session_mode, session_bots, session_bot_count,
		session_map_id, session_racing_car_id, session_racing_allocation,
		session_event, session_scene, session_minigame, room_public,
		_peer_teams.duplicate(), teams_locked, session_bot_difficulty,
		session_vehicle_mode, session_shared_vehicle, session_shared_racer_color)


@rpc("authority", "call_local", "reliable")
func _net_session_config(mode: String, bots: bool, count: int,
		map_id: String = "", racing_car_id: String = "",
		racing_allocation: Dictionary = {}, event: String = "",
		scene: String = "", theme_id: String = "", public_room: bool = false,
		teams: Dictionary = {}, locked: bool = false, difficulty: int = 1,
		vehicle_mode: String = "", shared_vehicle: String = "",
		shared_racer_color: String = "") -> void:
	if mode != GameSettings.GAME_SANDBOX and mode != GameSettings.GAME_MINIGAMES:
		return
	count = clampi(count, 0, MAX_BOT_COUNT)
	session_mode = mode
	session_bots = bots
	session_bot_count = count
	session_bot_difficulty = clampi(difficulty, 0, 2)
	# Only a real gameplay scene may become the room's scene. A peer cannot
	# smuggle a path through the config RPC, and a mismatch between the
	# event and the scene resolves to a safe sandbox/race scene.
	var clean_scene: String = scene if scene in ALLOWED_SCENES else ""
	if clean_scene == "":
		clean_scene = GAME_SCENE if mode == GameSettings.GAME_SANDBOX \
			else scene_for_event(event if (event == EVENT_RACE or event in MINIGAME_EVENTS) else EVENT_RACE)
	session_scene = clean_scene
	session_event = event_for_scene(clean_scene) \
		if mode == GameSettings.GAME_MINIGAMES else ""
	# Receive-side sanitising: only a registry race-map id can become the
	# session map, so a peer cannot smuggle a scene path through the config RPC.
	if map_id != "":
		session_map_id = GameSettings.sanitize_map_id(map_id)
	# The minigame arena theme is sanitised against the active event so a room
	# can never hold another mode's arena id.
	session_minigame = _sanitize_minigame_theme(session_event, theme_id) \
		if session_event in MINIGAME_EVENTS else ""
	room_public = public_room
	# An absent racing field is the old-client default: keep the peer's local
	# build rather than overwriting it with an empty one.
	if racing_car_id != "":
		session_racing_car_id = sanitize_racing_car_id(racing_car_id)
	if not racing_allocation.is_empty():
		session_racing_allocation = sanitize_racing_allocation(
			racing_allocation)
	if vehicle_mode != "":
		session_vehicle_mode = VEHICLE_MODE_SHARED \
			if vehicle_mode == VEHICLE_MODE_SHARED else VEHICLE_MODE_PICK_OWN
	if shared_vehicle != "":
		session_shared_vehicle = GameSettings.sanitize_vehicle_id(shared_vehicle)
	if shared_racer_color != "":
		session_shared_racer_color = _sanitize_racer_hex(shared_racer_color)
	var clean_teams: Dictionary = _sanitize_teams(teams)
	var lock_changed: bool = locked != teams_locked
	var assignment_changed: bool = clean_teams != _peer_teams
	_peer_teams = clean_teams
	teams_locked = locked
	if assignment_changed or lock_changed:
		teams_changed.emit()
	if is_host:
		GameSettings.set_session_config(GameSettings.MODE_MULTIPLAYER, mode,
			bots, count, session_map_id)
	session_config_changed.emit()


func _sanitize_teams(raw: Dictionary) -> Dictionary:
	## peer id -> 0/1 only, bounded, so a hostile packet cannot grow the table.
	## Godot ENet peer IDs are random 31-bit positive integers (1..0x7FFFFFFF).
	var clean: Dictionary = {}
	for key: Variant in raw.keys():
		if clean.size() >= MAX_PLAYERS + 1:
			break
		var peer_id: int = int(key)
		if peer_id <= 0 or peer_id > 0x7FFFFFFF:
			continue
		var value: Variant = raw[key]
		if not (value is int or value is float):
			continue
		var team: int = int(value)
		if team != 0 and team != 1:
			continue
		clean[peer_id] = team
	return clean


func is_lan() -> bool:
	return connection_mode == "lan"


# --------------------------------------------------------------------------
# session flow


func start_game(scene_path: String = "", mode: String = "") -> void:
	## Host-only. Picks the scene from the host's session mode when omitted,
	## then pushes the exact configuration to every peer before loading.
	if not is_host:
		return
	var target: String = scene_path
	var chosen_mode: String = mode
	if chosen_mode == "":
		chosen_mode = GameSettings.multiplayer_mode
	if chosen_mode != GameSettings.GAME_MINIGAMES:
		# A sandbox room can never inherit a stale cargo/race scene.
		chosen_mode = GameSettings.GAME_SANDBOX
		target = GAME_SCENE
		session_event = ""
	elif target == "":
		# The replicated event decides which minigame scene the host loads.
		target = scene_for_event(session_event)
	if target not in ALLOWED_SCENES:
		target = GAME_SCENE if chosen_mode == GameSettings.GAME_SANDBOX \
			else scene_for_event(session_event if (session_event == EVENT_RACE or session_event in MINIGAME_EVENTS) else EVENT_RACE)
	if chosen_mode == GameSettings.GAME_MINIGAMES:
		session_event = event_for_scene(target)
		if session_event == "":
			session_event = EVENT_RACE
			target = RACE_SCENE
	else:
		session_event = ""
	session_scene = target
	in_game = true
	game_scene = target
	session_mode = chosen_mode
	session_bots = GameSettings.bots_enabled
	session_bot_count = GameSettings.effective_bot_count()
	session_bot_difficulty = clampi(GameSettings.minigame_difficulty, 0, 2)
	session_map_id = GameSettings.sanitize_map_id(GameSettings.selected_map)
	session_minigame = _sanitize_minigame_theme(session_event, GameSettings.selected_minigame) \
		if session_event in MINIGAME_EVENTS else ""
	session_racing_car_id = sanitize_racing_car_id(
		GameSettings.racing_vehicle_id())
	session_racing_allocation = sanitize_racing_allocation(
		GameSettings.racing_allocation())
	session_shared_vehicle = GameSettings.vehicle_for_channel(active_vehicle_channel())
	session_shared_racer_color = GameSettings.racer_color
	player_vehicles[1] = _local_loadout_dict()
	_balance_teams()
	race_seed = Time.get_ticks_msec()
	clear_scene_ready()
	set_room_state("playing")
	# Refresh the config so a build changed in the garage after the last peer
	# change still reaches every peer before the scene starts (reliable and
	# ordered ahead of the begin-game packet).
	_push_session_config()
	rpc("_net_begin_game", target, chosen_mode, session_bots, session_bot_count, race_seed)


@rpc("authority", "call_local", "reliable")
func _net_begin_game(scene_path: String, mode: String, bots: bool, count: int,
		seed_value: int = 0) -> void:
	# A malicious host must not be able to load an arbitrary scene or spawn
	# billions of bots on a joining client.
	if scene_path not in ALLOWED_SCENES:
		return
	if mode != GameSettings.GAME_SANDBOX and mode != GameSettings.GAME_MINIGAMES:
		return
	count = clampi(count, 0, MAX_BOT_COUNT)
	var current: Node = _active_gameplay_scene()
	var active_path: String = _active_gameplay_scene_path(current)
	if current != null and active_path == scene_path and in_game:
		# The first ready RPC can reach the host before its scene exists. On a
		# retry, announce through the loaded scene again once the host is ready.
		notify_scene_ready(current, scene_path)
		if not is_host:
			_send_client_scene_ready(current, scene_path)
		return
	if _scene_load_path == scene_path:
		# A previous retry already asked SceneLoader for this scene. It may
		# still be streaming; queueing it again would load the scene twice.
		return
	_scene_load_path = scene_path
	if not is_host:
		scene_ready_peers.erase(1)
		if host_scene_ready_path != scene_path:
			host_scene_ready_path = ""
	input_locked = false
	in_game = true
	game_scene = scene_path
	session_mode = mode
	session_scene = scene_path
	session_event = event_for_scene(scene_path) if mode == GameSettings.GAME_MINIGAMES else ""
	session_bots = bots
	session_bot_count = count
	if seed_value != 0:
		race_seed = seed_value
	# The host's session config stays in Network.* on clients. Only the host
	# writes its own persisted settings; otherwise a client's later volume/
	# name save would silently persist the host's mode and bot count.
	if is_host:
		GameSettings.set_session_config(GameSettings.MODE_MULTIPLAYER, mode, bots, count)
	var title: String = "STARTING SANDBOX"
	if mode == GameSettings.GAME_MINIGAMES:
		match scene_path:
			CARGO_SCENE:
				title = "STARTING DELIVER"
			KNOCKOUT_SCENE:
				title = "STARTING KNOCKOUT"
			BOMB_TAG_SCENE:
				title = "STARTING BLAST TAG"
			_:
				title = "STARTING RACE"
	SceneLoader.go_to(scene_path, title, "Syncing players...")


func return_to_lobby(reason: String = "") -> void:
	if is_session_active():
		leave()
	session_ended.emit(reason)
	SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER")


func return_to_lobby_keep_session() -> void:
	## Used after a race result. The host brings everyone back to the lobby;
	## a client waits in its own lobby while the connection stays open.
	clear_scene_ready()
	if not is_session_active():
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER")
		return
	if is_host:
		in_game = false
		set_room_state("lobby")
		rpc("_net_return_lobby")
	else:
		# Tell the host we left the race scene so it stops sending cart-state
		# RPCs to a node that no longer exists.
		rpc_id(1, "_net_client_left_scene")
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER")


@rpc("any_peer", "call_remote", "reliable")
func _net_client_left_scene() -> void:
	var sender: int = _rpc_sender()
	if sender <= 1:
		return
	scene_ready_peers.erase(sender)
	_left_scene_peers[sender] = true
	_scene_retry_counts.erase(sender)


@rpc("authority", "call_local", "reliable")
func _net_return_lobby() -> void:
	clear_scene_ready()
	input_locked = false
	in_game = false
	SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER")


# --------------------------------------------------------------------------
# signals


func _on_peer_connected(id: int) -> void:
	# A reconnect can reuse a peer id after a long session; never inherit the
	# previous occupant's retry budget or throttle stamps.
	_scene_retry_counts.erase(id)
	_left_scene_peers.erase(id)
	_name_stamp.erase(id)
	_ping_stamp.erase(id)
	_color_stamp.erase(id)
	_vehicle_stamp.erase(id)
	_ping_request_stamp.erase(id)
	if is_host and in_game and game_scene == RACE_SCENE:
		# Meadow Loop does not support joining mid-race: a peer that arrives
		# after the start would sit on a frozen WAITING screen. Drop it
		# instead of force-loading a race it can never join.
		if _peer != null:
			_peer.disconnect_peer(id)
		return
	peers_changed.emit()
	_push_room_state()
	if is_host and is_session_active():
		# Deliver rooms are team games: a joiner gets a side immediately, the
		# split is balanced again unless the host locked it, and the whole
		# table travels in the same config packet as the mode and scene. Push
		# this BEFORE any begin-game packet so the new peer can read its team
		# as soon as the arena loads.
		if not _peer_teams.has(id):
			_peer_teams[id] = _smaller_team()
		_balance_teams()
		_push_session_config()
		teams_changed.emit()
	if is_host:
		# Send the existing name/colour table to the newcomer. Without this a
		# client only learns colours from peers who change them later.
		for peer_id: int in player_names:
			rpc_id(id, "_net_set_name", peer_id, str(player_names[peer_id]))
		for peer_id: int in player_colors:
			var color: Color = player_colors[peer_id]
			rpc_id(id, "_net_set_tag_color", peer_id, color.to_html(false))
		for peer_id: int in player_vehicles:
			rpc_id(id, "_net_set_vehicle_loadout", peer_id, player_vehicles[peer_id])
		if in_game:
			rpc_id(id, "_net_begin_game", game_scene, session_mode,
				session_bots, session_bot_count, race_seed)
			if host_scene_ready_path == game_scene and host_scene_ready_path != "":
				rpc_id(id, "_net_host_scene_ready", host_scene_ready_path)
	if is_session_active():
		# Re-announce our name & vehicle loadout so the newcomer (and everyone) has it.
		rpc("_net_set_name", multiplayer.get_unique_id(), GameSettings.player_name)
		rpc("_net_set_vehicle_loadout", multiplayer.get_unique_id(), _local_loadout_dict())


var _name_stamp: Dictionary = {}
var _ping_stamp: Dictionary = {}
var _color_stamp: Dictionary = {}
var _vehicle_stamp: Dictionary = {}
var _ping_request_stamp: Dictionary = {}


@rpc("any_peer", "call_local", "reliable")
func _net_set_name(peer_id: int, raw_name: String) -> void:
	var sender: int = _rpc_sender()
	# Host relays client names so every client sees the whole player list.
	if sender != 0 and sender != 1 and peer_id != sender:
		return
	# One reliable name change per peer every 2 s. Without this a client can
	# flood a large string and make the host rebroadcast it to every peer.
	if sender > 1:
		var now: int = Time.get_ticks_msec()
		if now - int(_name_stamp.get(sender, -10000)) < 2000:
			return
		_name_stamp[sender] = now
	var clean: String = GameSettings.sanitize_name(raw_name)
	player_names[peer_id] = clean
	names_changed.emit()
	# Rebroadcast the sanitized value, never the raw attacker string.
	if is_host and sender != 0 and sender != 1:
		rpc("_net_set_name", peer_id, clean)


@rpc("any_peer", "call_local", "reliable")
func _net_set_tag_color(peer_id: int, raw_hex: String) -> void:
	## Same relay pattern as names: a peer speaks for itself, host relays.
	var sender: int = _rpc_sender()
	if sender != 0 and sender != 1 and peer_id != sender:
		return
	var clean: String = str(raw_hex).strip_edges().trim_prefix("#").to_lower()
	if clean.length() != 6:
		return
	for character: String in clean:
		if not ("0123456789abcdef".contains(character)):
			return
	# Colours are reliable RPCs that the host rebroadcasts to every peer.
	# Throttle them exactly like names so one client cannot amplify a flood.
	if sender > 1:
		var now: int = Time.get_ticks_msec()
		if now - int(_color_stamp.get(sender, -10000)) < 2000:
			return
		_color_stamp[sender] = now
	player_colors[peer_id] = Color(clean)
	tag_colors_changed.emit()
	if is_host and sender != 0 and sender != 1:
		rpc("_net_set_tag_color", peer_id, clean)


@rpc("any_peer", "call_local", "reliable")
func _net_set_vehicle_loadout(peer_id: int, raw_loadout: Dictionary) -> void:
	## Relay each player's Garage choices (vehicles per mode, PRO RACER paint
	## color, and racing stat allocation). Host sanitizes & broadcasts to all.
	var sender: int = _rpc_sender()
	if sender != 0 and sender != 1 and peer_id != sender:
		return
	if sender > 1:
		var now: int = Time.get_ticks_msec()
		if now - int(_vehicle_stamp.get(sender, -10000)) < 400:
			return
		_vehicle_stamp[sender] = now
	var clean: Dictionary = _sanitize_vehicle_loadout(raw_loadout)
	player_vehicles[peer_id] = clean
	vehicles_changed.emit()
	if is_host and sender != 0 and sender != 1:
		rpc("_net_set_vehicle_loadout", peer_id, clean)


func _on_peer_disconnected(id: int) -> void:
	scene_ready_peers.erase(id)
	_erase_peer_separation(id)
	_last_good_position.erase(id)
	_scene_retry_counts.erase(id)
	_left_scene_peers.erase(id)
	player_names.erase(id)
	player_colors.erase(id)
	player_vehicles.erase(id)
	ping_table.erase(id)
	_peer_teams.erase(id)
	_name_stamp.erase(id)
	_ping_stamp.erase(id)
	_color_stamp.erase(id)
	_vehicle_stamp.erase(id)
	_ping_request_stamp.erase(id)
	peers_changed.emit()
	names_changed.emit()
	tag_colors_changed.emit()
	vehicles_changed.emit()
	ping_table_changed.emit()
	_push_room_state()
	if is_host and is_session_active():
		_broadcast_ping_table()
		# A departure can unbalance a deliver room. Rebalance unless locked
		# and let every remaining peer redraw its team columns.
		_balance_teams()
		_push_session_config()
		teams_changed.emit()


func _on_connected_to_server() -> void:
	is_client = true
	join_pending = false
	# The connection answered, so the macOS permission retry budget resets.
	_lan_join_retry = 0
	_lan_join_host = ""
	_lan_join_port = 0
	clear_scene_ready()
	rpc("_net_set_name", multiplayer.get_unique_id(), GameSettings.player_name)
	rpc("_net_set_tag_color", multiplayer.get_unique_id(), GameSettings.player_tag_color)
	set_local_vehicle_loadout()
	join_status_changed.emit("Connected. Waiting for the host to start...")
	join_succeeded.emit()
	peers_changed.emit()


func _on_connection_failed() -> void:
	## macOS 15+ can refuse the first direct LAN connect while the Local
	## Network permission alert is on screen. Retry once, after the player has
	## had a moment to answer, instead of dumping them back to the menu with a
	## misleading "could not reach that host" error.
	var was_lan: bool = connection_mode == "lan"
	var retry_host: String = _lan_join_host
	var retry_port: int = _lan_join_port
	var retry: bool = was_lan and _is_macos() and _lan_join_retry < 1 \
		and retry_host != "" and retry_port > 0
	leave()
	if retry:
		_lan_join_retry += 1
		join_status_changed.emit("Waiting for macOS Local Network permission...")
		_retry_lan_join_deferred(retry_host, retry_port)
		return
	join_failed.emit(_join_failure_reason(was_lan))


func _retry_lan_join_deferred(host: String, open_port: int) -> void:
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree() or join_pending or is_session_active():
		return
	_connect_to(host, open_port, "lan")


func _join_failure_reason(was_lan: bool) -> String:
	var transport: String = _join_transport_reason()
	if transport != "":
		return transport
	var reason: String = "Could not reach that host. Check the code and that the host is online. Hint: verify the code and retry."
	if was_lan and _is_macos():
		reason += " On macOS, allow Cart Slop GP under System Settings > Privacy & Security > Local Network."
	return reason


func _on_server_disconnected() -> void:
	in_game = false
	var was_client: bool = is_client
	leave()
	if was_client:
		session_ended.emit("The host ended the session.")
		var current: Node = get_tree().current_scene
		# Reloading the lobby wipes the reason from the fresh instance's
		# status label. If we are already there, let _on_session_ended show it.
		if current == null or current.scene_file_path != LOBBY_SCENE:
			SceneLoader.go_to(LOBBY_SCENE, "SESSION ENDED", "The host disconnected.")


# --------------------------------------------------------------------------
# ping


@rpc("any_peer", "unreliable")
func _net_ping(stamp: int) -> void:
	var sender: int = _rpc_sender()
	if sender <= 0 or not multiplayer.is_server():
		return
	# Unreliable pings are cheap, but a client can still use them to make the
	# host reply at line rate. One per 0.5 s is plenty for a 2 s ping cycle.
	var now: int = Time.get_ticks_msec()
	if now - int(_ping_request_stamp.get(sender, -10000)) < 500:
		return
	_ping_request_stamp[sender] = now
	rpc_id(sender, "_net_pong", stamp)


@rpc("authority", "unreliable")
func _net_pong(stamp: int) -> void:
	# Clamp: a stale or corrupt echoed stamp must not put a negative (or
	# multi-minute) ping into the HUD or the table the host rebroadcasts.
	latency_ms = clampi(Time.get_ticks_msec() - stamp, 0, 5000)
	latency_changed.emit(latency_ms)
	# Publish our own RTT so the host can build the Minecraft-style ping table
	# every player sees when holding Tab.
	ping_table[multiplayer.get_unique_id()] = latency_ms
	ping_table_changed.emit()
	rpc_id(1, "_net_report_ping", latency_ms)


@rpc("any_peer", "unreliable")
func _net_report_ping(ms: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = _rpc_sender()
	if sender <= 1:
		return
	# One report per 2 s per peer: each one makes the host send a reliable
	# table to every client, so an unthrottled peer can amplify a packet into
	# a lobby-wide broadcast storm.
	var now: int = Time.get_ticks_msec()
	if now - int(_ping_stamp.get(sender, -10000)) < 2000:
		return
	_ping_stamp[sender] = now
	ping_table[sender] = clampi(ms, 0, 5000)
	_broadcast_ping_table()


func _broadcast_ping_table() -> void:
	## Host-only: relay everyone's reported ping so clients can show it too.
	## Throttled: broadcast only on >50 ms change or every 10 s.
	if not is_host or not is_session_active():
		return
	ping_table[1] = host_ping_ms
	var now: int = Time.get_ticks_msec()
	var changed: bool = false
	if _ping_last_table.size() != ping_table.size():
		changed = true
	else:
		for key: Variant in ping_table.keys():
			var prev: int = int(_ping_last_table.get(key, -100000))
			if absi(int(ping_table[key]) - prev) > 50:
				changed = true
				break
	if not changed and now - _ping_last_broadcast_ms < 10000:
		return
	_ping_last_broadcast_ms = now
	_ping_last_table = ping_table.duplicate()
	rpc("_net_ping_table", ping_table)


func _measure_host_ping() -> void:
	## Host only: time a real HTTP round trip to the relay. The host has no ENet
	## server above it, so 0 ms was a lie whenever the Pi relays the room.
	if _host_ping_pending or not is_host or not is_session_active():
		return
	if connection_mode != "pi" or relay_base == "":
		host_ping_ms = 0
		return
	_host_ping_pending = true
	var started: int = Time.get_ticks_msec()
	var status: Dictionary = await _relay_get("/api/status", 2.0)
	_host_ping_pending = false
	if not is_host or not is_session_active():
		return
	if status.is_empty():
		# Keep the last good value rather than showing 0 for a dropped probe.
		return
	host_ping_ms = clampi(Time.get_ticks_msec() - started, 1, 5000)
	_note_relay_rtt(host_ping_ms)
	ping_table[1] = host_ping_ms
	ping_table_changed.emit()
	latency_changed.emit(host_ping_ms)
	_broadcast_ping_table()


@rpc("authority", "reliable")
func _net_ping_table(table: Dictionary) -> void:
	var clean: Dictionary = {}
	for key: Variant in table.keys():
		var id: int = int(key)
		if id <= 0 or id > 4096:
			continue
		var value: Variant = table[key]
		if not (value is int or value is float):
			continue
		clean[id] = clampi(int(value), 0, 5000)
		if clean.size() >= 64:
			break
	ping_table = clean
	ping_table_changed.emit()


# --------------------------------------------------------------------------
# helpers


static func encode_address(ip: String, udp_port: int) -> String:
	## 12 hex chars for ip:port plus a 2-char checksum -> 14 chars total.
	var parts: PackedStringArray = ip.split(".")
	if parts.size() != 4:
		return ""
	var bytes: Array[int] = []
	for part: String in parts:
		bytes.append(clampi(int(part), 0, 255))
	bytes.append((udp_port >> 8) & 0xFF)
	bytes.append(udp_port & 0xFF)
	var checksum: int = 0
	for value: int in bytes:
		checksum = (checksum + value) & 0xFF
	var out: String = ""
	for value: int in bytes:
		out += "%02X" % value
	return out + "%02X" % checksum


static func decode_address(raw: String) -> Dictionary:
	var text: String = raw.strip_edges().to_upper().replace(" ", "")
	if text == "":
		return {}
	if text.contains(":"):
		var bits: PackedStringArray = text.split(":")
		if bits.size() != 2:
			return {}
		var typed_port: int = int(bits[1])
		if typed_port <= 0 or typed_port > 65535:
			return {}
		return {"ip": bits[0], "port": typed_port}
	if text.length() != 14:
		return {}
	for character in text:
		if not ("0123456789ABCDEF".contains(character)):
			return {}
	var checksum: int = 0
	for index in 6:
		checksum = (checksum + text.substr(index * 2, 2).hex_to_int()) & 0xFF
	if checksum != text.substr(12, 2).hex_to_int():
		return {}
	var ip: String = "%d.%d.%d.%d" % [
		text.substr(0, 2).hex_to_int(),
		text.substr(2, 2).hex_to_int(),
		text.substr(4, 2).hex_to_int(),
		text.substr(6, 2).hex_to_int(),
	]
	var udp_port: int = text.substr(8, 4).hex_to_int()
	if udp_port <= 0:
		return {}
	return {"ip": ip, "port": udp_port}


func _same_subnet_24(left: String, right: String) -> bool:
	if not _valid_ip(left) or not _valid_ip(right):
		return false
	return left.substr(0, left.rfind(".")) == right.substr(0, right.rfind("."))


func _valid_ip(text: String) -> bool:
	var parts: PackedStringArray = text.strip_edges().split(".")
	if parts.size() != 4:
		return false
	for part: String in parts:
		if part == "" or not part.is_valid_int():
			return false
		var value: int = int(part)
		if value < 0 or value > 255:
			return false
	return true


func _valid_room_code(text: String) -> bool:
	if text.length() != 5:
		return false
	for character: String in text:
		if not ROOM_CODE_ALPHABET.contains(character):
			return false
	return true


func _is_private_ipv4(text: String) -> bool:
	if not _valid_ip(text):
		return false
	if text.begins_with("10.") or text.begins_with("192.168.") or text.begins_with("127."):
		return true
	if text.begins_with("172."):
		var second: int = int(text.split(".")[1])
		return second >= 16 and second <= 31
	return false


func probe_server() -> bool:
	## Used by the lobby to show PI SERVER ONLINE/OFFLINE and to disable room
	## hosting/joining when there is nothing to connect to.
	if is_host or is_client or join_pending:
		# A live session owns the relay route. Re-probing here used to clear
		# it on a slow /api/status and silently stop heartbeats.
		server_online = true
		server_detail = "online"
		return true
	var ticket: int = _host_ticket + _join_ticket
	var found: bool = await _discover_relay()
	if ticket != _host_ticket + _join_ticket or is_host or is_client or join_pending:
		# Host or join started while the probe was in flight. Never clear the
		# relay route underneath it.
		return true
	if not found:
		server_online = false
		server_detail = "offline"
		server_status_changed.emit(false, "offline")
		return false
	var status: Dictionary = await _relay_get("/api/status", 3.0)
	if ticket != _host_ticket + _join_ticket or is_host or is_client or join_pending:
		return true
	server_online = not status.is_empty()
	if server_online:
		_remember_server_version(status)
	server_detail = "online" if server_online else "offline"
	if not server_online:
		# A TLS/DNS transport failure is not the same as an HTTP failure. Keep
		# the detail so the lobby can explain a trust-store/VPN problem instead
		# of pretending the game server is offline.
		var detail: String = _relay_result_detail()
		if detail != "":
			server_detail = detail
			last_error = detail
		# Force the next attempt to rediscover instead of reusing a dead route.
		# A user-forced server is kept; only the resolved route is cleared.
		_invalidate_relay_route()
	server_status_changed.emit(server_online, server_detail)
	return server_online


func participants() -> Array[int]:
	## Everyone in the session, including us, in a stable order.
	var ids: Array[int] = [multiplayer.get_unique_id()]
	for peer_id: int in multiplayer.get_peers():
		ids.append(peer_id)
	ids.sort()
	return ids


func spawn_position(peer_id: int) -> Vector3:
	## Deterministic starting grid: five columns, then a row further back.
	var index: int = maxi(participants().find(peer_id), 0)
	var column: int = index % 5
	var row: int = index / 5
	return Vector3(-6.0 + column * 3.0, 0.25, 64.0 - row * 4.0)
