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


func _ready() -> void:
	CursorController.set_menu_mode(false)
	_local_cart = get_tree().get_first_node_in_group("player") as CartPlayer
	if Network.is_session_active():
		_setup_multiplayer()
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

	if not _host_mode:
		for prop: RigidBody3D in _props:
			prop.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			prop.freeze = true

	for peer_id: int in multiplayer.get_peers():
		_spawn_remote(peer_id)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	Network.names_changed.connect(_refresh_name_labels)
	# Vehicle models are exchanged through the scene, not the lobby: tell the
	# host we are ready, or broadcast ours to everyone if we are the host.
	_peer_vehicles[multiplayer.get_unique_id()] = GameSettings.selected_vehicle
	if _host_mode:
		rpc("_net_peer_vehicle", multiplayer.get_unique_id(), GameSettings.selected_vehicle)
	else:
		rpc("_net_client_ready", GameSettings.selected_vehicle)


func _physics_process(delta: float) -> void:
	_update_bots(delta)
	if not Network.is_session_active():
		return
	_cart_sync_timer += delta
	if _cart_sync_timer >= CART_SYNC_INTERVAL and _local_cart != null:
		_cart_sync_timer = 0.0
		rpc("_net_cart_state", multiplayer.get_unique_id(),
			_local_cart.global_position, _local_cart.rotation.y)

	if _host_mode:
		_prop_sync_timer += delta
		if _prop_sync_timer >= PROP_SYNC_INTERVAL:
			_prop_sync_timer = 0.0
			_broadcast_props()
	else:
		_apply_prop_targets(delta)


# --------------------------------------------------------------------------
# optional AI carts (visual ghosts on a relaxed loop)


func _setup_bots() -> void:
	var count: int = Network.session_bot_count if Network.is_session_active() \
		else GameSettings.effective_bot_count()
	if count <= 0:
		return
	var entries: Array[Dictionary] = VehicleCatalog.all()
	for i in count:
		var node := Node3D.new()
		node.name = "SandboxBot_%d" % (i + 1)
		var entry: Dictionary = entries[(i + 1) % entries.size()]
		node.add_child(VehicleVisual.build(entry))
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
		add_child(node)
		_bots.append({
			"node": node,
			"angle": TAU * float(i) / float(count) + 0.7,
			"radius": 20.0 + float(i) * 4.5,
			"speed": 0.22 + float(i) * 0.025,
		})


func _update_bots(delta: float) -> void:
	if _bots.is_empty():
		return
	_bot_time += delta
	for bot: Dictionary in _bots:
		var angle: float = float(bot["angle"]) + _bot_time * float(bot["speed"])
		var radius: float = float(bot["radius"])
		var node: Node3D = bot["node"]
		node.global_position = Vector3(cos(angle) * radius, 0.12,
			sin(angle) * radius)
		node.rotation.y = PI - angle


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
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	add_child(cart)
	cart.setup_remote(peer_id)
	# The ghost scene briefly owns a current Camera3D; make sure the local
	# driving camera stays in charge.
	if _local_cart != null:
		var local_camera := _local_cart.get_node_or_null("CameraArm/Camera3D") as Camera3D
		if local_camera != null:
			local_camera.current = true
	cart.global_position = Network.spawn_position(peer_id)
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


# --------------------------------------------------------------------------
# RPCs


@rpc("any_peer", "unreliable")
func _net_cart_state(peer_id: int, position: Vector3, yaw: float) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	# A client may only speak for itself; the host relays it to everyone else.
	if sender != 1 and peer_id != sender:
		return
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null and cart.remote_mode:
		cart.net_position = position
		cart.net_yaw = yaw
	if _host_mode and sender != 1:
		rpc("_net_cart_state", peer_id, position, yaw)


@rpc("any_peer", "reliable")
func _net_client_ready(vehicle_id: String) -> void:
	## A peer has entered the sandbox. The host stores its vehicle and replies
	## with the whole map, covering late joins and clients that missed an
	## earlier hello while they were still in the lobby.
	var sender: int = multiplayer.get_remote_sender_id()
	if sender <= 1 or sender == multiplayer.get_unique_id():
		return
	_store_peer_vehicle(sender, vehicle_id)
	if not _host_mode:
		return
	rpc("_net_peer_vehicle", sender, vehicle_id)
	for peer_id: Variant in _peer_vehicles.keys():
		rpc_id(sender, "_net_peer_vehicle", int(peer_id), str(_peer_vehicles[peer_id]))


@rpc("authority", "reliable")
func _net_peer_vehicle(peer_id: int, vehicle_id: String) -> void:
	_store_peer_vehicle(peer_id, vehicle_id)


func _store_peer_vehicle(peer_id: int, vehicle_id: String) -> void:
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
	var count: int = mini(_props.size(), positions.size())
	for index in count:
		_prop_targets[index] = [positions[index], rotations[index]]


@rpc("any_peer", "reliable")
func _net_request_push(index: int, direction: Vector3, kick: float) -> void:
	if not _host_mode or index < 0 or index >= _props.size():
		return
	var prop: RigidBody3D = _props[index]
	prop.sleeping = false
	kick = clampf(kick, 0.1, 4.0)
	direction = direction.normalized()
	prop.apply_central_impulse(direction * prop.mass * kick + Vector3.UP * prop.mass * kick * 0.85)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0))
	prop.apply_torque_impulse(spin * prop.mass * 1.6)


# --------------------------------------------------------------------------
# props


func _broadcast_props() -> void:
	if _props.is_empty():
		return
	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	for prop: RigidBody3D in _props:
		positions.append(prop.global_position)
		rotations.append(prop.global_rotation)
	rpc("_net_props", positions, rotations)


func _apply_prop_targets(delta: float) -> void:
	if _prop_targets.is_empty():
		return
	var blend: float = 1.0 - exp(-12.0 * delta)
	for index: int in _prop_targets:
		if index < 0 or index >= _props.size():
			continue
		var prop: RigidBody3D = _props[index]
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
