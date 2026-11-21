extends Node3D
## Sandbox scene wiring: menu cursor + optional multiplayer session.
##
## Multiplayer model (host-authoritative props, peer-owned carts):
##   - every peer simulates its own cart and streams position at 20 Hz,
##   - remote carts are interpolated ghosts with no physics or camera,
##   - the host simulates the props and broadcasts snapshots at 10 Hz,
##   - clients freeze their props and ask the host to apply pushes.

const CART_SCENE := preload("res://scenes/player/cart_player.tscn")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")
const VisualGrade := preload("res://scripts/systems/visual_grade.gd")
const SandboxBot := preload("res://scripts/ai/sandbox_bot.gd")
const CollisionLayers := preload("res://scripts/systems/collision_layers.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const UI_THEME: Theme = preload("res://assets/ui/theme.tres")
const TITLE_FONT: Font = preload("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")
const CART_SYNC_INTERVAL: float = 0.05
const PROP_SYNC_INTERVAL: float = 0.10
const CART_IDLE_SPEED: float = 1.0
const CART_IDLE_INTERVAL: float = 0.20
## Painted paddock grid slots, row-major, mirrored from sandbox_park.gd. Slot 5
## (index 4) is the authored single-player marker.
const GRID_SLOTS: Array[Vector3] = [
	Vector3(-9.0, 0.0, 5.0), Vector3(0.0, 0.0, 5.0), Vector3(9.0, 0.0, 5.0),
	Vector3(-9.0, 0.0, 13.0), Vector3(0.0, 0.0, 13.0), Vector3(9.0, 0.0, 13.0),
]
const GRID_MARKER_SLOT: int = 4
## Overflow seats past the six painted boxes: two rows on the pit-gate lane in
## front of the grid, then the paved east apron columns. Every centre is on the
## apron and clear of the garages, the yard cone line, the tyre stacks, the
## crates, the banners and the terrace, which the old row at z = 17 was not (it
## sat on the dirt among the slalom cones). Eighteen seats total, more than the
## five-bot plus room capacity.
const GRID_OVERFLOW: Array[Vector3] = [
	Vector3(-9.0, 0.0, -3.0), Vector3(0.0, 0.0, -3.0), Vector3(9.0, 0.0, -3.0),
	Vector3(-9.0, 0.0, -11.0), Vector3(0.0, 0.0, -11.0),
	Vector3(9.0, 0.0, -11.0),
	Vector3(18.0, 0.0, -3.0), Vector3(27.0, 0.0, -3.0),
	Vector3(18.0, 0.0, -11.0), Vector3(27.0, 0.0, -11.0),
	Vector3(18.0, 0.0, 13.0), Vector3(27.0, 0.0, 13.0),
]
## Prop watchdog. Everything pushable sits on the y = 0 slab inside the fence;
## a prop below the slab or past the fence has tunnelled or been thrown out and
## goes back to the pose it was authored with.
const PROP_FLOOR: float = -0.6
const PROP_BOUNDS: float = 122.0
const PROP_RECOVER_INTERVAL: float = 0.5
const PROP_KICK_MS: int = 400
const PROP_KICK_RETRY_MS: int = 150
const PROP_SLEEP_SPEED: float = 0.30
const PROP_SLEEP_SPIN: float = 0.60
## A respawn slot this tall is not ground: the bot is on the pit-garage or
## grandstand roof, where the single downward probe put it.
const RESPAWN_ROOF_HEIGHT: float = 4.0
const RESPAWN_PROBE_RADIUS: float = 0.95
## Zone hint toast: compact top-center banner at y = 22 styled with theme.tres,
## staying clear of BoostBox / Speedometer even at 960 x 540.
const HINT_MARGIN: int = 24
const HINT_TOP: int = 22
const HINT_GAP: int = 12
const HINT_SMALL_GAP: int = 4
const HINT_RADIUS: int = 14
const HINT_WIDTH: float = 380.0
const HINT_SECONDS: float = 5.0
const ZONE_PROBE_INTERVAL: float = 0.25

var _local_cart: CartPlayer
var _remote_carts: Dictionary = {} ## peer_id -> CartPlayer
var _peer_vehicles: Dictionary = {} ## peer_id -> vehicle id
var _props: Array[RigidBody3D] = []
var _prop_homes: Array[Transform3D] = [] ## authored pose per _props index
var _prop_targets: Dictionary = {} ## index -> [Vector3, Vector4 quaternion]
var _host_mode: bool = false
var _name_labels: Dictionary = {} ## peer id -> Label3D
var _cart_sync_timer: float = 0.0
var _prop_sync_timer: float = 0.0
var _prop_recover_timer: float = 0.0
var _bots: Array[SandboxBot] = []
var _traffic: Array[CartPlayer] = [] ## local player first, then every bot cart
var _bot_time: float = 0.0
var _bot_homes: Array[Transform3D] = [] ## fallback seat per bot, index-parallel
## Consecutive-no-progress watchdog: window-start seat and stalled-window count
## per bot, index-parallel to _bots. Net displacement (not speed) reseats a bot
## that oscillates in place, which keeps moving enough to decay bot.stuck.
const BOT_PROGRESS_WINDOW: float = 1.0
const BOT_PROGRESS_MIN: float = 1.5
const BOT_NO_PROGRESS_LIMIT: int = 4
var _bot_progress_pos: Array[Vector3] = []
var _bot_no_progress: Array[int] = []
var _bot_progress_timer: float = 0.0
## Authored spawn anchor from the scene marker; grid slots reuse its height and
## facing so single- and multiplayer start on the same transforms.
var _spawn_anchor: Transform3D = Transform3D(Basis.IDENTITY,
	Vector3(0.0, 0.25, 0.0))
var _cart_relay_ms: Dictionary = {} ## peer id -> last host relay (anti-amplification)
var _cart_idle_ms: Dictionary = {} ## peer id -> last cart send (deadband)
var _cart_idle_pos: Dictionary = {} ## peer id -> last sent position
var _cart_idle_yaw: Dictionary = {} ## peer id -> last sent yaw
## Client-side prediction for a pushed frozen prop.
var _prop_kick_until: Dictionary = {}
## Paddock seat allocation: peer id -> grid index, and every claimed index. A
## late joiner must never reuse a seat a bot already drives out of.
var _peer_slots: Dictionary = {}
var _slot_owner: Dictionary = {}
## Respawn overlap probe, allocated once.
var _respawn_shape: SphereShape3D
var _respawn_query: PhysicsShapeQueryParameters3D
## Zone hint toast state.
var _hint_layer: CanvasLayer
var _hint_panel: PanelContainer
var _hint_title: Label
var _hint_body: Label
var _hint_timer: Timer
var _zone_probe: float = 0.0
var _zones_seen: Dictionary = {}



func _rpc_sender() -> int:
	## RPCs can still be queued when a peer is tearing down; never dereference
	## a null multiplayer peer.
	return multiplayer.get_remote_sender_id() if multiplayer.multiplayer_peer != null else 0

func _ready() -> void:
	CursorController.set_menu_mode(false)
	VisualGrade.apply($WorldEnvironment, "sandbox")
	VisualGrade.apply_sun($Sun)
	_local_cart = get_tree().get_first_node_in_group("player") as CartPlayer
	var marker: Node3D = get_tree().get_first_node_in_group("spawn_point") as Node3D
	if marker != null:
		_spawn_anchor = marker.global_transform
	_collect_props()
	if Network.is_session_active():
		_setup_multiplayer()
	elif _local_cart != null:
		# The scene file parks the local cart on the host's multiplayer grid
		# slot. Single player returns to the authored marker so a session that
		# did not start still feels like the solo Sandbox.
		if marker != null:
			_local_cart.global_position = marker.global_position
			_local_cart.set_spawn_transform(marker.global_transform)
	_build_zone_hint()
	_setup_bots()


func _setup_multiplayer() -> void:
	_host_mode = Network.is_host
	if _local_cart != null:
		var local_slot: Transform3D = _grid_slot_transform(
			_claim_peer_slot(multiplayer.get_unique_id()))
		_local_cart.global_transform = local_slot
		_local_cart.set_spawn_transform(local_slot)
		if not _local_cart.net_push_requested.is_connected(_on_local_push_requested):
			_local_cart.net_push_requested.connect(_on_local_push_requested)
		if not _local_cart.horn_requested.is_connected(_on_horn_requested):
			_local_cart.horn_requested.connect(_on_horn_requested)

	if not _host_mode:
		for prop: RigidBody3D in _props:
			prop.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			prop.freeze = true

	for peer_id: int in multiplayer.get_peers():
		_spawn_remote(peer_id)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.names_changed.connect(_refresh_name_labels)
	Network.tag_colors_changed.connect(_refresh_name_labels)
	# Vehicle models are exchanged through the scene, not the lobby: tell the
	# host we are ready, or broadcast ours to everyone if we are the host.
	_peer_vehicles[multiplayer.get_unique_id()] = GameSettings.selected_vehicle
	Network.notify_scene_ready()
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("SANDBOX_NET ready id=", multiplayer.get_unique_id(),
			" host=", _host_mode, " peers=", multiplayer.get_peers())
	if _host_mode:
		_broadcast_vehicle(multiplayer.get_unique_id(), GameSettings.selected_vehicle)
	elif Network.is_scene_ready(1):
		rpc_id(1, "_net_client_ready", GameSettings.selected_vehicle)


func _physics_process(delta: float) -> void:
	_update_bots(delta)
	_recover_props(delta)
	_probe_zone(delta)
	if not Network.is_session_active():
		return
	if _host_mode and _local_cart != null:
		Network.resolve_car_collisions(_local_cart, _remote_carts)
	_cart_sync_timer += delta
	if _cart_sync_timer >= CART_SYNC_INTERVAL and _local_cart != null:
		_cart_sync_timer = 0.0
		var stamp: int = Time.get_ticks_msec()
		if _host_mode:
			_broadcast_cart_state(multiplayer.get_unique_id(),
				_local_cart.global_position, _local_cart.rotation.y, stamp,
				_local_cart.velocity)
		elif Network.is_scene_ready(1):
			rpc_id(1, "_net_cart_state", multiplayer.get_unique_id(),
				_local_cart.global_position, _local_cart.rotation.y, stamp,
				_local_cart.velocity)

	if _host_mode:
		_prop_sync_timer += delta
		if _prop_sync_timer >= PROP_SYNC_INTERVAL:
			_prop_sync_timer = 0.0
			_broadcast_props()
	else:
		_expire_prop_kicks()
		_apply_prop_targets(delta)


# --------------------------------------------------------------------------
# Optional AI carts. They use the same controls and physics as the local player.


func _setup_bots() -> void:
	var count: int = Network.session_bot_count if Network.is_session_active() \
		else GameSettings.effective_bot_count()
	if count <= 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = Network.race_seed if Network.is_session_active() and Network.race_seed != 0 \
		else Time.get_ticks_msec()
	# In a session every peer must build the same bot bodies. Each machine has
	# its own saved Sandbox car, so use the deterministic catalog default for
	# the shared bot field instead of the local selection.
	var vehicle_id: String = VehicleCatalog.DEFAULT_ID if Network.is_session_active() \
		else GameSettings.selected_vehicle
	if VehicleCatalog.find(vehicle_id).is_empty():
		vehicle_id = VehicleCatalog.DEFAULT_ID
	# Bots take the first free seats after every peer. Solo, the authored marker
	# slot stays reserved for the local cart. Position BEFORE add_child: a
	# physics body that enters the world at the origin spends its first tick
	# overlapping every other new cart, which launched them across the map.
	var first_slot: int = Network.participants().size() \
		if Network.is_session_active() else 0
	for i in count:
		var node: CartPlayer = CART_SCENE.instantiate() as CartPlayer
		node.name = "SandboxBot_%d" % (i + 1)
		var slot_index: int = _claim_slot(first_slot + i)
		var slot: Transform3D = _grid_slot_transform(slot_index)
		node.position = slot.origin
		node.rotation.y = slot.basis.get_euler().y
		node.ai_mode = true
		add_child(node)
		node.setup_ai(vehicle_id)
		node.set_spawn_transform(node.global_transform)
		_bot_homes.append(node.global_transform)
		_bot_progress_pos.append(node.global_transform.origin)
		_bot_no_progress.append(0)
		var label := Label3D.new()
		label.text = "BOT %d" % (i + 1)
		label.font = TITLE_FONT
		label.font_size = 48
		label.pixel_size = 0.007
		label.outline_size = 14
		label.outline_modulate = Color(0.118, 0.106, 0.227)
		label.modulate = Color(1.0, 0.83, 0.35)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0.0, 2.4, 0.0)
		node.add_child(label)
		var difficulty: int = Network.bot_difficulty()
		var bot: SandboxBot = SandboxBot.new()
		bot.setup(node, i, rng, difficulty)
		bot.allow_tag = true
		_bots.append(bot)
	# The traffic list is rebuilt once, not every tick: every driver reads the
	# local player and the other bots from this shared array.
	_traffic.clear()
	if _local_cart != null and is_instance_valid(_local_cart):
		_traffic.append(_local_cart)
	for built: SandboxBot in _bots:
		if is_instance_valid(built.cart):
			_traffic.append(built.cart)


func _update_bots(delta: float) -> void:
	if _bots.is_empty():
		return
	_bot_time += delta
	_bot_progress_timer += delta
	var close_window: bool = _bot_progress_timer >= BOT_PROGRESS_WINDOW
	if close_window:
		_bot_progress_timer = 0.0
	for i in _bots.size():
		var bot: SandboxBot = _bots[i]
		if not is_instance_valid(bot.cart):
			continue
		bot.tick(delta, _bot_time, _traffic)
		if close_window:
			_track_bot_progress(i, bot)
		var stalled: int = int(_bot_no_progress[i]) if i < _bot_no_progress.size() else 0
		# The hard reset is the last resort: a bot with no net progress across
		# consecutive windows (or that has left the park) gets put back on its
		# lane. Displacement — not the speed-decayed stuck timer — catches a bot
		# oscillating in place.
		if stalled >= BOT_NO_PROGRESS_LIMIT or bot.stranded > 1.5:
			_respawn_bot(bot, i)


func _track_bot_progress(i: int, bot: SandboxBot) -> void:
	## Close one progress window: net planar displacement since the window
	## opened counts as progress, anything less extends the stall streak.
	while _bot_progress_pos.size() <= i:
		_bot_progress_pos.append(bot.cart.global_position)
	while _bot_no_progress.size() <= i:
		_bot_no_progress.append(0)
	var last: Vector3 = _bot_progress_pos[i]
	var here: Vector3 = bot.cart.global_position
	var moved: float = Vector2(here.x - last.x, here.z - last.z).length()
	if moved < BOT_PROGRESS_MIN:
		_bot_no_progress[i] = int(_bot_no_progress[i]) + 1
	else:
		_bot_no_progress[i] = 0
	_bot_progress_pos[i] = here


func _respawn_bot(bot: SandboxBot, index: int) -> void:
	## Hard reset, then prove the landing spot is free. The driver's own probe
	## takes the TOPMOST surface under the slot, so a respawn aimed at the pit
	## block landed the bot on the pit-garage roof (11 m up) and a slot inside
	## the grandstand box embedded it in solid geometry.
	bot.respawn()
	var cart: CartPlayer = bot.cart
	if not is_instance_valid(cart):
		return
	if index < _bot_no_progress.size():
		_bot_no_progress[index] = 0
	if index < _bot_progress_pos.size():
		_bot_progress_pos[index] = cart.global_position
	if not _cart_slot_blocked(cart):
		return
	var home: Transform3D = _bot_homes[index] \
		if index < _bot_homes.size() else _grid_slot_transform(0)
	var ground: float = _ground_height(home.origin)
	cart.global_transform = Transform3D(home.basis,
		Vector3(home.origin.x, ground + 0.12, home.origin.z))
	cart.set_spawn_transform(cart.global_transform)
	cart.reset_for_respawn()
	cart.velocity = Vector3.ZERO
	if index < _bot_progress_pos.size():
		_bot_progress_pos[index] = cart.global_position


func _cart_slot_blocked(cart: CartPlayer) -> bool:
	## True when the cart is standing on a roof or overlapping solid geometry or
	## another kart. One sphere overlap plus the height ceiling, no ray chains.
	if not cart.global_position.is_finite():
		return true
	if cart.global_position.y > RESPAWN_ROOF_HEIGHT:
		return true
	if _respawn_shape == null:
		_respawn_shape = SphereShape3D.new()
		_respawn_shape.radius = RESPAWN_PROBE_RADIUS
		_respawn_query = PhysicsShapeQueryParameters3D.new()
		_respawn_query.shape = _respawn_shape
		_respawn_query.collide_with_areas = false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	_respawn_query.transform = Transform3D(Basis.IDENTITY,
		cart.global_position + Vector3.UP * 1.0)
	_respawn_query.collision_mask = CollisionLayers.WORLD \
		| CollisionLayers.SOLID_PROP | CollisionLayers.PLAYER \
		| CollisionLayers.GHOST
	var excluded: Array[RID] = [cart.get_rid()]
	_respawn_query.exclude = excluded
	return not space.intersect_shape(_respawn_query, 1).is_empty()


# --------------------------------------------------------------------------
# peers


func _on_peer_connected(peer_id: int) -> void:
	_spawn_remote(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null:
		cart.queue_free()
		_remote_carts.erase(peer_id)
	_name_labels.erase(peer_id)
	_peer_vehicles.erase(peer_id)
	_release_peer_slot(peer_id)


func _spawn_remote(peer_id: int) -> void:
	if _remote_carts.has(peer_id) or peer_id == multiplayer.get_unique_id():
		return
	var slot: Transform3D = _grid_slot_transform(_claim_peer_slot(peer_id))
	var spawn: Vector3 = slot.origin
	# Ghosts never run physics, so they would hover at the spawn height (a
	# quarter metre up) until the first sync packet. Sit them on the floor.
	spawn.y = _ground_height(spawn)
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	# Set the transform before add_child so the body never spends a tick at the
	# world origin, overlapping the local cart and other new ghosts.
	cart.position = spawn
	cart.rotation.y = slot.basis.get_euler().y
	add_child(cart)
	cart.setup_remote(peer_id)
	cart.set_spawn_transform(Transform3D(slot.basis, spawn))
	# The ghost scene briefly owns a current Camera3D; make sure the local
	# driving camera stays in charge.
	if _local_cart != null:
		var local_camera := _local_cart.get_node_or_null("CameraArm/Camera3D") as Camera3D
		if local_camera != null:
			local_camera.current = true
	cart.net_position = cart.global_position
	if _peer_vehicles.has(peer_id):
		cart.set_vehicle_id(str(_peer_vehicles[peer_id]))
	_add_name_label(cart, peer_id)
	_remote_carts[peer_id] = cart


func _peer_grid_index(peer_id: int) -> int:
	## Stable grid order: the same sorted participant list on every machine.
	## A peer that has not been listed yet (`find` returns -1) falls back to
	## seat 0, which the claim walk then moves to the first genuinely free seat.
	return maxi(Network.participants().find(peer_id), 0)


func _claim_peer_slot(peer_id: int) -> int:
	## One unique paddock seat per peer. Bots claim through the same table, so a
	## peer that connects after the field was built cannot take a bot's seat.
	if _peer_slots.has(peer_id):
		return int(_peer_slots[peer_id])
	var index: int = _claim_slot(_peer_grid_index(peer_id))
	_peer_slots[peer_id] = index
	return index


func _release_peer_slot(peer_id: int) -> void:
	if not _peer_slots.has(peer_id):
		return
	_slot_owner.erase(int(_peer_slots[peer_id]))
	_peer_slots.erase(peer_id)


func _claim_slot(preferred: int) -> int:
	## First free seat at or after the preferred index. `_slot_owner` is a set.
	var index: int = maxi(preferred, 0)
	while _slot_taken(index):
		index += 1
	_slot_owner[index] = true
	return index


func _slot_taken(index: int) -> bool:
	## Solo keeps the authored marker (slot 5, index 4) free for the player.
	if index == GRID_MARKER_SLOT and not Network.is_session_active():
		return true
	return _slot_owner.has(index)


func _grid_slot_transform(index: int) -> Transform3D:
	## One paddock grid transform. The six painted boxes come first, in order;
	## overflow keeps to the paved apron and the 16 m gate corridor. Height and
	## facing come from the authored single-player marker, so both modes share
	## the same spawn pose.
	var centre: Vector3
	if index < GRID_SLOTS.size():
		centre = GRID_SLOTS[index]
	else:
		var extra: int = clampi(index - GRID_SLOTS.size(), 0,
			GRID_OVERFLOW.size() - 1)
		centre = GRID_OVERFLOW[extra]
	return Transform3D(_spawn_anchor.basis,
		Vector3(centre.x, _spawn_anchor.origin.y, centre.z))


func _add_name_label(cart: CartPlayer, peer_id: int) -> void:
	var label := Label3D.new()
	label.text = Network.name_of(peer_id)
	label.font = TITLE_FONT
	label.font_size = 64
	label.pixel_size = 0.006
	label.outline_size = 18
	label.outline_modulate = Color(0.118, 0.106, 0.227)
	label.modulate = Network.color_of(peer_id)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0, 2.5, 0)
	cart.add_child(label)
	_name_labels[peer_id] = label


func _refresh_name_labels() -> void:
	for peer_id: int in _name_labels:
		var label: Label3D = _name_labels[peer_id]
		if is_instance_valid(label):
			label.text = Network.name_of(peer_id)
			label.modulate = Network.color_of(peer_id)


# --------------------------------------------------------------------------
# RPCs


@rpc("any_peer", "unreliable")
func _net_cart_state(peer_id: int, position: Vector3, yaw: float, sent_ms: int,
		velocity: Vector3 = Vector3.ZERO) -> void:
	var sender: int = _rpc_sender()
	# A client may only speak for itself; the host relays it to everyone else.
	if sender != 1 and peer_id != sender:
		return
	# NaN/Inf from a peer would otherwise propagate into every ghost and into
	# the host's collision resolver (all NaN comparisons are false).
	if not position.is_finite() or not is_finite(yaw) or not velocity.is_finite():
		return
	if position.length_squared() > 5000.0 * 5000.0:
		return
	if sent_ms < 0:
		return
	var cart: CartPlayer = _remote_carts.get(peer_id)
	var accepted: bool = false
	if cart != null and cart.remote_mode:
		accepted = cart.set_net_state(position, yaw, sent_ms, velocity)
	if _host_mode and sender != 1 and accepted:
		# A modified client can otherwise turn one 20 Hz stream into a
		# broadcast storm for every other peer.
		var now: int = Time.get_ticks_msec()
		if now - int(_cart_relay_ms.get(peer_id, -10000)) >= 25:
			_cart_relay_ms[peer_id] = now
			_broadcast_cart_state(peer_id, position, yaw, sent_ms, velocity)


@rpc("any_peer", "reliable")
func _net_client_ready(vehicle_id: String) -> void:
	## A peer has entered the sandbox. The host stores its vehicle and replies
	## with the whole map, covering late joins and clients that missed an
	## earlier hello while they were still in the lobby.
	var sender: int = _rpc_sender()
	if sender <= 1 or sender == multiplayer.get_unique_id():
		return
	if vehicle_id.length() > 64:
		return
	Network.mark_peer_scene_ready(sender)
	_store_peer_vehicle(sender, vehicle_id)
	if not _host_mode:
		return
	var stored: String = str(_peer_vehicles.get(sender, ""))
	if stored == "":
		return
	# Relay the validated/stored id, never the raw attacker string.
	_broadcast_vehicle(sender, stored)
	for peer_id: Variant in _peer_vehicles.keys():
		rpc_id(sender, "_net_peer_vehicle", int(peer_id),
			str(_peer_vehicles[peer_id]))


@rpc("authority", "reliable")
func _net_peer_vehicle(peer_id: int, vehicle_id: String) -> void:
	_store_peer_vehicle(peer_id, vehicle_id)


func _store_peer_vehicle(peer_id: int, vehicle_id: String) -> void:
	if vehicle_id.length() > 64:
		return
	if VehicleCatalog.find(vehicle_id).is_empty():
		return
	_peer_vehicles[peer_id] = vehicle_id
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null:
		cart.set_vehicle_id(vehicle_id)


@rpc("authority", "unreliable")
func _net_props(positions: PackedVector3Array,
		rotations: PackedVector4Array) -> void:
	if _host_mode:
		return
	if positions.size() > _props.size() or rotations.size() < positions.size():
		return
	for index in positions.size():
		if not positions[index].is_finite() or not rotations[index].is_finite():
			continue
		_prop_targets[index] = [positions[index], rotations[index]]


var _push_stamp: Dictionary = {}
var _horn_stamp: Dictionary = {}


func _on_horn_requested() -> void:
	## The local cart already played its own horn; this only tells the room.
	var my_id: int = multiplayer.get_unique_id()
	if _host_mode:
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
	# A reliable RPC can be queued more than once; cap the playback rate.
	var now: int = Time.get_ticks_msec()
	if now - int(_horn_stamp.get(peer_id, -10000)) < 140:
		return
	_horn_stamp[peer_id] = now
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null:
		cart.honk()
	if _host_mode and sender != 1:
		_broadcast_horn(peer_id, sender)


@rpc("any_peer", "reliable")
func _net_request_push(index: int, direction: Vector3, kick: float) -> void:
	if not _host_mode or index < 0 or index >= _props.size():
		return
	# The pause menu freezes the world while the MultiplayerAPI keeps polling,
	# so a queued push would land on a frozen body and fire on resume.
	if get_tree().paused:
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
	var prop: RigidBody3D = _props[index]
	prop.sleeping = false
	kick = clampf(kick, 0.1, 4.0)
	direction = direction.normalized()
	# Above the body origin, so the hit topples the cone instead of sliding it
	# along the ground and leaving it standing.
	prop.apply_impulse(direction * prop.mass * kick
		+ Vector3.UP * prop.mass * kick * 0.85, Vector3(0.0, 0.3, 0.0))
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0))
	prop.apply_torque_impulse(spin * prop.mass * 1.6)


# --------------------------------------------------------------------------
# props


func _collect_props() -> void:
	## The pushables this scene syncs, ordered by name so host and clients agree
	## on the index protocol. The authored pose per index is the recovery pad.
	_props.clear()
	_prop_homes.clear()
	for node: Node in get_tree().get_nodes_in_group("pushable"):
		if node is RigidBody3D:
			_props.append(node as RigidBody3D)
	_props.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool:
		return str(a.name) < str(b.name))
	for prop: RigidBody3D in _props:
		_prop_homes.append(prop.global_transform)


func _recover_props(delta: float) -> void:
	## Watchdog for pushables that tunnelled through the y = 0 slab or were
	## thrown past the fence. It ran only in a session before, because _props
	## was filled by the multiplayer setup, so solo lost props for good.
	if _props.is_empty():
		_prop_recover_timer = 0.0
		return
	_prop_recover_timer += delta
	if _prop_recover_timer < PROP_RECOVER_INTERVAL:
		return
	_prop_recover_timer = 0.0
	# The host owns prop motion; a client's props are frozen at the host pose.
	if Network.is_session_active() and not _host_mode:
		return
	for index in _props.size():
		var prop: RigidBody3D = _props[index]
		if not is_instance_valid(prop):
			continue
		var at: Vector3 = prop.global_position
		if at.is_finite() and at.y > PROP_FLOOR \
				and absf(at.x) <= PROP_BOUNDS and absf(at.z) <= PROP_BOUNDS:
			continue
		_reset_prop(index)


func _reset_prop(index: int) -> void:
	## Puts one prop back on its authored pad with no residual motion.
	if index < 0 or index >= _props.size() or index >= _prop_homes.size():
		return
	var prop: RigidBody3D = _props[index]
	if not is_instance_valid(prop):
		return
	prop.freeze = false
	prop.sleeping = false
	prop.global_transform = _prop_homes[index]
	prop.linear_velocity = Vector3.ZERO
	prop.angular_velocity = Vector3.ZERO
	prop.reset_physics_interpolation()


func _prune_props() -> void:
	## Drop bodies freed by a scene rebuild, keeping pose homes index-aligned so
	## the recovery table cannot point a neighbour at the wrong pad.
	var kept: Array[RigidBody3D] = []
	var homes: Array[Transform3D] = []
	for index in _props.size():
		var prop: RigidBody3D = _props[index]
		if not is_instance_valid(prop):
			continue
		kept.append(prop)
		homes.append(_prop_homes[index] if index < _prop_homes.size()
			else prop.global_transform)
	_props = kept
	_prop_homes = homes
	_prop_targets.clear()
	_prop_kick_until.clear()


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
		sent_ms: int = 0, velocity: Vector3 = Vector3.ZERO) -> void:
	if _cart_idle_skip(peer_id, position, yaw, velocity):
		return
	if sent_ms <= 0:
		sent_ms = Time.get_ticks_msec()
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_cart_state", peer_id, position, yaw, sent_ms, velocity)


func _broadcast_vehicle(peer_id: int, vehicle_id: String) -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_peer_vehicle", peer_id, vehicle_id)


func _broadcast_props() -> void:
	if _props.is_empty():
		return
	# A prop can be freed by a scene rebuild or a cleanup while the sandbox is
	# still streaming. Drop dead references before indexing so the host and
	# clients keep the same prop order.
	for prop: RigidBody3D in _props:
		if not is_instance_valid(prop):
			_prune_props()
			break
	if _props.is_empty():
		return
	var positions := PackedVector3Array()
	var rotations := PackedVector4Array()
	for prop: RigidBody3D in _props:
		positions.append(prop.global_position)
		# Quaternions, not Euler angles: a cone that tips past 90 degrees sends
		# its Euler X through a branch cut, and the client used to lerp the
		# short way back towards upright while the host showed it lying down.
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
		var target_position: Vector3 = data[0] as Vector3
		prop.global_position = prop.global_position.lerp(target_position, blend)
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


func _on_local_push_requested(prop: Node, direction: Vector3, kick: float) -> void:
	if _host_mode:
		return
	var index: int = _props.find(prop as RigidBody3D)
	if index < 0:
		return
	# Predict locally so the box moves on this screen immediately; the host
	# remains authoritative and the next snapshot corrects the pose.
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
	prop.apply_impulse(direction * prop.mass * kick
		+ Vector3.UP * prop.mass * kick * 0.85, Vector3(0.0, 0.3, 0.0))
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0))
	prop.apply_torque_impulse(spin * prop.mass * 1.6)
	_prop_kick_until[prop.get_instance_id()] = Time.get_ticks_msec() + PROP_KICK_MS


func _expire_prop_kicks() -> void:
	if _prop_kick_until.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	for id: int in _prop_kick_until.keys():
		if now < int(_prop_kick_until[id]):
			continue
		var prop: RigidBody3D = instance_from_id(id) as RigidBody3D
		if not is_instance_valid(prop):
			_prop_kick_until.erase(id)
			continue
		# A prop that is still tumbling stays live. Freezing it on the fixed
		# deadline is what snapped a knocked cone back upright mid-tip.
		if prop.linear_velocity.length() > PROP_SLEEP_SPEED \
				or prop.angular_velocity.length() > PROP_SLEEP_SPIN:
			_prop_kick_until[id] = now + PROP_KICK_RETRY_MS
			continue
		prop.freeze = true
		_prop_kick_until.erase(id)


func _ground_height(at: Vector3) -> float:
	## Floor height under a point, for placing ghosts. The ray starts above the
	## tallest facility solid so a slot near the pit building or kickers finds the
	## real surface instead of falling back to y=0.
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * 12.0, at + Vector3.DOWN * 30.0, 1)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	return (hit["position"] as Vector3).y + 0.001


# --------------------------------------------------------------------------
# zone hints (Slop-Slash floating comic banner — zero shaded rounded boxes!)


class _ZoneSlashTag extends Control:
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
		if w <= 12.0 or h <= 8.0:
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
		draw_colored_polygon(sh, Color(0.07, 0.05, 0.15, 0.88))
		draw_colored_polygon(pts, UiPalette.YELLOW)
		var wedge := PackedVector2Array([
			Vector2(pad_l + sk, pad_t),
			Vector2(pad_l + sk + 12.0, pad_t),
			Vector2(pad_l + 12.0, pad_t + h),
			Vector2(pad_l, pad_t + h),
		])
		draw_colored_polygon(wedge, UiPalette.CYAN)
		draw_line(
			Vector2(pad_l + sk + 12.0, pad_t),
			Vector2(pad_l + 12.0, pad_t + h),
			UiPalette.INK, 2.5, true)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, UiPalette.INK, 3.5, true)


func _build_zone_hint() -> void:
	## Top-center floating Slop-Slash zone callout at y = 22 (zero dark boxes!),
	## staying clear of BoostBox and SpeedGauge even at 960x540.
	if _hint_panel != null:
		return
	_hint_layer = CanvasLayer.new()
	_hint_layer.name = "ZoneHints"
	_hint_layer.layer = 2
	add_child(_hint_layer)
	var anchor := Control.new()
	anchor.name = "Anchor"
	anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.theme = UI_THEME
	_hint_layer.add_child(anchor)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", HINT_MARGIN)
	margin.add_theme_constant_override("margin_top", HINT_TOP)
	margin.add_theme_constant_override("margin_right", HINT_MARGIN)
	margin.add_theme_constant_override("margin_bottom", HINT_MARGIN)
	anchor.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", HINT_GAP)
	margin.add_child(column)
	_hint_panel = PanelContainer.new()
	_hint_panel.name = "ZoneToast"
	_hint_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_theme_stylebox_override("panel", _hint_style())
	_hint_panel.visible = false
	column.add_child(_hint_panel)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 6)
	_hint_panel.add_child(body)

	var title_tag := PanelContainer.new()
	title_tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag_empty := StyleBoxEmpty.new()
	tag_empty.content_margin_left = 24.0
	tag_empty.content_margin_right = 22.0
	tag_empty.content_margin_top = 5.0
	tag_empty.content_margin_bottom = 9.0
	title_tag.add_theme_stylebox_override("panel", tag_empty)
	var slash := _ZoneSlashTag.new()
	slash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_tag.add_child(slash)
	body.add_child(title_tag)

	_hint_title = Label.new()
	_hint_title.name = "ZoneName"
	_hint_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_title.theme_type_variation = &"TitleLabel"
	_hint_title.add_theme_font_override("font", TITLE_FONT)
	_hint_title.add_theme_font_size_override("font_size", 20)
	_hint_title.add_theme_color_override("font_color", UiPalette.INK)
	_hint_title.add_theme_constant_override("outline_size", 0)
	_hint_title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.0))
	_hint_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_tag.add_child(_hint_title)

	_hint_body = Label.new()
	_hint_body.name = "ZoneHint"
	_hint_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_body.theme_type_variation = &"TitleLabel"
	_hint_body.add_theme_font_override("font", TITLE_FONT)
	_hint_body.add_theme_font_size_override("font_size", 16)
	_hint_body.add_theme_color_override("font_color", UiPalette.CREAM)
	_hint_body.add_theme_color_override("font_outline_color", UiPalette.INK)
	_hint_body.add_theme_constant_override("outline_size", 7)
	_hint_body.add_theme_color_override("font_shadow_color", Color(0.08, 0.06, 0.16, 0.85))
	_hint_body.add_theme_constant_override("shadow_offset_x", 3)
	_hint_body.add_theme_constant_override("shadow_offset_y", 4)
	_hint_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_body.custom_minimum_size.x = HINT_WIDTH
	body.add_child(_hint_body)
	_hint_timer = Timer.new()
	_hint_timer.name = "ZoneToastTimer"
	_hint_timer.one_shot = true
	_hint_timer.wait_time = HINT_SECONDS
	# Real time, so the toast fades out even with the pause menu open.
	_hint_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_hint_timer.timeout.connect(_hide_zone_hint)
	add_child(_hint_timer)
	if OS.get_environment("CART_DEBUG_PARK") == "1":
		_measure_zone_hint.call_deferred()


## Debug-only layout proof: prints the toast rect against the design viewport,
## so the top-center placement and 960x540 / 1280x720 fit are measured.
func _measure_zone_hint() -> void:
	await get_tree().process_frame
	if _hint_panel == null or not _hint_panel.visible:
		return
	var view: Vector2 = _hint_panel.get_viewport_rect().size
	var rect: Rect2 = _hint_panel.get_global_rect()
	var left: float = rect.position.x
	var right: float = view.x - rect.end.x
	var bottom: float = view.y - rect.end.y
	var top: float = rect.position.y
	print("ZONE TOAST viewport=%s rect=(%.0f, %.0f, %.0f x %.0f) edges L=%.0f R=%.0f T=%.0f B=%.0f -> %s" % [
		view, rect.position.x, rect.position.y, rect.size.x, rect.size.y,
		left, right, top, bottom,
		"INSIDE" if left >= HINT_MARGIN - 0.5 and right >= HINT_MARGIN - 0.5
			and bottom >= HINT_MARGIN - 0.5 and top >= float(HINT_TOP) - 0.5 else "CLIPPED"])


func _hint_style() -> StyleBoxEmpty:
	var style := StyleBoxEmpty.new()
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 2.0
	return style


func _probe_zone(delta: float) -> void:
	## Names the zone the local cart is in once, the first time it gets there.
	if _hint_panel == null or _local_cart == null \
			or not is_instance_valid(_local_cart):
		return
	_zone_probe -= delta
	if _zone_probe > 0.0:
		return
	_zone_probe = ZONE_PROBE_INTERVAL
	var park: Node = get_node_or_null("Park")
	if park == null or not park.has_method("zone_at"):
		return
	var zone: String = str(park.call("zone_at", _local_cart.global_position))
	if zone == "" or _zones_seen.has(zone):
		return
	_zones_seen[zone] = true
	_show_zone_hint(zone, str(park.call("zone_hint", zone)))


func _show_zone_hint(zone: String, hint: String) -> void:
	if _hint_panel == null:
		return
	_hint_title.text = zone
	_hint_body.text = hint
	_hint_panel.visible = hint != ""
	if _hint_timer != null:
		_hint_timer.start(HINT_SECONDS)
	if OS.get_environment("CART_DEBUG_PARK") == "1":
		print("ZONE HINT %s | %s" % [zone, hint])


func _hide_zone_hint() -> void:
	if _hint_panel != null:
		_hint_panel.visible = false
