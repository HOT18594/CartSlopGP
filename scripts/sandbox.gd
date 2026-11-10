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
const TITLE_FONT: String = "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"
const CART_SYNC_INTERVAL: float = 0.05
const PROP_SYNC_INTERVAL: float = 0.10

var _local_cart: CartPlayer
var _remote_carts: Dictionary = {} ## peer_id -> CartPlayer
var _peer_vehicles: Dictionary = {} ## peer_id -> vehicle id
var _props: Array[RigidBody3D] = []
var _prop_targets: Dictionary = {} ## index -> [Vector3, float]
var _host_mode: bool = false
var _name_labels: Dictionary = {} ## peer id -> Label3D
var _cart_sync_timer: float = 0.0
var _prop_sync_timer: float = 0.0
var _bots: Array[Dictionary] = []
var _bot_time: float = 0.0
var _cart_relay_ms: Dictionary = {} ## peer id -> last host relay (anti-amplification)



func _rpc_sender() -> int:
	## RPCs can still be queued when a peer is tearing down; never dereference
	## a null multiplayer peer.
	return multiplayer.get_remote_sender_id() if multiplayer.multiplayer_peer != null else 0

func _ready() -> void:
	CursorController.set_menu_mode(false)
	VisualGrade.apply($WorldEnvironment, "sandbox")
	VisualGrade.apply_sun($Sun)
	_local_cart = get_tree().get_first_node_in_group("player") as CartPlayer
	if Network.is_session_active():
		_setup_multiplayer()
	elif _local_cart != null:
		# The scene file parks the local cart on the host's multiplayer grid
		# slot. Single player returns to the authored marker so a session that
		# did not start still feels like the solo Sandbox.
		var marker: Node3D = get_tree().get_first_node_in_group("spawn_point") as Node3D
		if marker != null:
			_local_cart.global_position = marker.global_position
			_local_cart.set_spawn_transform(marker.global_transform)
	_setup_bots()


func _setup_multiplayer() -> void:
	_host_mode = Network.is_host
	for node in get_tree().get_nodes_in_group("pushable"):
		if node is RigidBody3D:
			_props.append(node as RigidBody3D)
	_props.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool: return str(a.name) < str(b.name))

	if _local_cart != null:
		_local_cart.global_position = Network.spawn_position(multiplayer.get_unique_id())
		_local_cart.set_spawn_transform(_local_cart.global_transform)
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
	else:
		rpc_id(1, "_net_client_ready", GameSettings.selected_vehicle)


func _physics_process(delta: float) -> void:
	_update_bots(delta)
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
	for i in count:
		var node: CartPlayer = CART_SCENE.instantiate() as CartPlayer
		node.name = "SandboxBot_%d" % (i + 1)
		var angle: float = TAU * float(i) / float(count) + 0.7
		var radius: float = 53.0 + float(i % 3) * 1.8
		# Position BEFORE add_child: a physics body that enters the world at the
		# origin spends its first tick overlapping every other new cart, which
		# launched them across the map. The transform must be set on the
		# detached node so the body is created in the right place.
		var spawn_x: float = cos(angle) * radius
		var spawn_z: float = sin(angle) * radius
		# The outer ring crosses the mesa/highline skirts. Spawn on the actual
		# surface instead of a fixed 0.12 m, or a bot can be born inside a hill.
		var spawn_y: float = _ground_height(Vector3(spawn_x, 0.0, spawn_z)) + 0.12
		node.position = Vector3(spawn_x, spawn_y, spawn_z)
		node.rotation.y = PI - angle
		node.ai_mode = true
		add_child(node)
		node.setup_ai(vehicle_id)
		node.set_spawn_transform(node.global_transform)
		var label := Label3D.new()
		label.text = "BOT %d" % (i + 1)
		label.font = load(TITLE_FONT)
		label.font_size = 48
		label.pixel_size = 0.007
		label.outline_size = 14
		label.outline_modulate = Color(0.118, 0.106, 0.227)
		label.modulate = Color(1.0, 0.83, 0.35)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0.0, 2.4, 0.0)
		node.add_child(label)
		var difficulty: int = clampi(GameSettings.minigame_difficulty, 0, 2)
		var skill_lo: Array[float] = [0.60, 0.72, 0.86]
		var skill_hi: Array[float] = [0.80, 1.00, 1.12]
		_bots.append({
			"node": node,
			"radius": radius,
			# Deterministic lanes: the first three bots always take a
			# different ring/swing line instead of randomly becoming a train.
			"radius_offset": [-4.0, 0.0, 4.0][i % 3],
			"path_style": i % 3,
			"skill": rng.randf_range(skill_lo[difficulty], skill_hi[difficulty]),
			"boost_bias": rng.randf_range(0.45, 1.0),
			"phase": rng.randf() * TAU,
			"stuck": 0.0,
			"stranded": 0.0,
		})


func _update_bots(delta: float) -> void:
	if _bots.is_empty():
		return
	_bot_time += delta
	for i in _bots.size():
		var bot: Dictionary = _bots[i]
		var node: CartPlayer = bot["node"]
		if not is_instance_valid(node):
			continue
		var position: Vector3 = node.global_position
		var forward: Vector3 = -node.global_transform.basis.z
		var speed: float = maxf(node.velocity.dot(forward), 0.0)
		var skill: float = bot["skill"]
		var style: int = int(bot["path_style"])
		var swing: float = [0.6, 3.2, 2.0][style]
		var radius: float = clampf(float(bot["radius"]) + float(bot["radius_offset"])
			+ sin(_bot_time * 0.35 + float(bot["phase"])) * swing, 44.0, 60.0)
		if style == 2:
			radius = clampf(float(bot["radius"]) + float(bot["radius_offset"])
				+ sin(atan2(position.z, position.x) * 3.0 + float(bot["phase"])) * 2.5,
				44.0, 60.0)
		var angle: float = atan2(position.z, position.x)
		var lookahead: float = clampf(speed * 0.65, 7.0, 14.0) * lerpf(1.16, 0.90, skill)
		var target_angle: float = angle + lookahead / radius
		var target := Vector3(cos(target_angle) * radius, position.y,
			sin(target_angle) * radius)
		var target_speed: float = node.max_speed * lerpf(0.62, 0.93, skill)
		for other: CartPlayer in [_local_cart] + _bots.map(func(item: Dictionary) -> CartPlayer: return item["node"]):
			if other == node or not is_instance_valid(other):
				continue
			var offset: Vector3 = other.global_position - position
			offset.y = 0.0
			var ahead: float = offset.dot(forward)
			var side: float = offset.dot(node.global_transform.basis.x)
			if ahead > 0.0 and ahead < 10.0 and absf(side) < 2.4:
				if ahead < 5.0:
					target_speed = minf(target_speed, maxf(other.get_collision_velocity().dot(forward), 0.0))
				target += node.global_transform.basis.x * (-2.5 if side > 0.0 else 2.5)
		var local_target: Vector3 = node.to_local(target)
		var steer: float = clampf(atan2(-local_target.x, -local_target.z) * 2.0, -1.0, 1.0)
		steer += sin(_bot_time + float(bot["phase"])) * (1.06 - skill) * 0.12
		var throttle: float = 1.0 if speed < target_speed else 0.0
		var brake: float = clampf((speed - target_speed) / 5.0, 0.0, 0.75) \
			if speed > target_speed + 1.0 else 0.0
		var use_boost: bool = speed > node.max_speed * 0.55 and node.boost_amount > 25.0 \
			and float(bot["boost_bias"]) > 0.52 and absf(steer) < 0.45 and brake <= 0.0
		if float(bot["stuck"]) > 1.0 and float(bot["stuck"]) < 4.0:
			# Back out of a wall/prop before the hard respawn.
			throttle = 0.0
			brake = 1.0
			steer = clampf(-steer * 0.8, -1.0, 1.0)
			use_boost = false
		node.set_ai_controls(throttle, brake, steer, use_boost)
		if speed < 0.8:
			bot["stuck"] = float(bot["stuck"]) + delta
		else:
			bot["stuck"] = maxf(float(bot["stuck"]) - delta * 2.0, 0.0)
		if position.y < -3.0 or Vector2(position.x, position.z).length() > 80.0:
			bot["stranded"] = float(bot["stranded"]) + delta
		else:
			bot["stranded"] = 0.0
		if float(bot["stuck"]) > 4.0 or float(bot["stranded"]) > 1.5:
			var reset_angle: float = atan2(position.z, position.x) + 0.12
			var reset_position := Vector3(cos(reset_angle) * radius, 0.0,
				sin(reset_angle) * radius)
			# The bot ring crosses the mesa/highline skirts; a fixed y=0.15
			# respawns a stuck bot inside the terrain and starts a fall loop.
			reset_position.y = _ground_height(reset_position) + 0.12
			node.global_position = reset_position
			node.rotation = Vector3(0.0, PI - reset_angle, 0.0)
			node.set_spawn_transform(node.global_transform)
			node.reset_for_respawn()
			node.velocity = Vector3.ZERO
			bot["stuck"] = 0.0
			bot["stranded"] = 0.0


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


func _spawn_remote(peer_id: int) -> void:
	if _remote_carts.has(peer_id) or peer_id == multiplayer.get_unique_id():
		return
	var spawn: Vector3 = Network.spawn_position(peer_id)
	# Ghosts never run physics, so they would hover at the spawn height (a
	# quarter metre up) until the first sync packet. Sit them on the floor.
	spawn.y = _ground_height(spawn)
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	# Set the transform before add_child so the body never spends a tick at the
	# world origin, overlapping the local cart and other new ghosts.
	cart.position = spawn
	add_child(cart)
	cart.setup_remote(peer_id)
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


func _add_name_label(cart: CartPlayer, peer_id: int) -> void:
	var label := Label3D.new()
	label.text = Network.name_of(peer_id)
	label.font = load("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")
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
func _net_props(positions: PackedVector3Array, rotations: PackedVector3Array) -> void:
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
	prop.apply_central_impulse(direction * prop.mass * kick + Vector3.UP * prop.mass * kick * 0.85)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0))
	prop.apply_torque_impulse(spin * prop.mass * 1.6)


# --------------------------------------------------------------------------
# props


func _broadcast_cart_state(peer_id: int, position: Vector3, yaw: float,
		sent_ms: int = 0, velocity: Vector3 = Vector3.ZERO) -> void:
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
	var valid: Array[RigidBody3D] = []
	for prop: RigidBody3D in _props:
		if is_instance_valid(prop):
			valid.append(prop)
	if valid.size() != _props.size():
		_props = valid
		_prop_targets.clear()
	if _props.is_empty():
		return
	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	for prop: RigidBody3D in _props:
		positions.append(prop.global_position)
		rotations.append(prop.global_rotation)
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
		var data: Array = _prop_targets[index]
		prop.global_position = prop.global_position.lerp(data[0] as Vector3, blend)
		var target_rotation: Vector3 = data[1] as Vector3
		prop.global_rotation = Vector3(
			lerp_angle(prop.global_rotation.x, target_rotation.x, blend),
			lerp_angle(prop.global_rotation.y, target_rotation.y, blend),
			lerp_angle(prop.global_rotation.z, target_rotation.z, blend))


func _on_local_push_requested(prop: Node, direction: Vector3, kick: float) -> void:
	if _host_mode:
		return
	var index: int = _props.find(prop as RigidBody3D)
	if index >= 0:
		rpc_id(1, "_net_request_push", index, direction, kick)


func _ground_height(at: Vector3) -> float:
	## Floor height under a point, for placing ghosts and bots. The ray starts
	## above the tallest park feature (5.5 m) so a spawn on the mesa/highline
	## skirt finds the real surface instead of falling back to y=0.
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * 12.0, at + Vector3.DOWN * 30.0, 1)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	return (hit["position"] as Vector3).y + 0.001
