extends Node3D
## Sandbox scene wiring: menu cursor + optional multiplayer session.
##
## Multiplayer model (host-authoritative props, peer-owned carts):
##   - every peer simulates its own cart and streams position at 20 Hz,
##   - remote carts are interpolated ghosts with no physics or camera,
##   - the host simulates the props and broadcasts snapshots at 10 Hz,
##   - clients freeze their props and ask the host to apply pushes.

const CART_SCENE := preload("res://scenes/player/cart_player.tscn")
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


func _ready() -> void:
	CursorController.set_menu_mode(false)
	_local_cart = get_tree().get_first_node_in_group("player") as CartPlayer
	if Network.is_session_active():
		_setup_multiplayer()


func _setup_multiplayer() -> void:
	_host_mode = Network.is_host
	for node in get_tree().get_nodes_in_group("pushable"):
		if node is RigidBody3D:
			_props.append(node as RigidBody3D)
	_props.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool: return str(a.name) < str(b.name))

	if _local_cart != null:
		_local_cart.global_position = Network.spawn_position(multiplayer.get_unique_id())
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
	# Announce our vehicle so ghosts show the right model (also covers late joiners).
	rpc("_net_hello", GameSettings.selected_vehicle)


func _physics_process(delta: float) -> void:
	if not Network.is_session_active():
		return
	_cart_sync_timer += delta
	if _cart_sync_timer >= CART_SYNC_INTERVAL and _local_cart != null:
		_cart_sync_timer = 0.0
		rpc("_net_cart_state", _local_cart.global_position, _local_cart.rotation.y)

	if _host_mode:
		_prop_sync_timer += delta
		if _prop_sync_timer >= PROP_SYNC_INTERVAL:
			_prop_sync_timer = 0.0
			_broadcast_props()
	else:
		_apply_prop_targets(delta)


# --------------------------------------------------------------------------
# peers


func _on_peer_connected(peer_id: int) -> void:
	_spawn_remote(peer_id)
	rpc("_net_hello", GameSettings.selected_vehicle)


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
func _net_cart_state(position: Vector3, yaw: float) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	var cart: CartPlayer = _remote_carts.get(sender)
	if cart != null and cart.remote_mode:
		cart.net_position = position
		cart.net_yaw = yaw


@rpc("any_peer", "reliable")
func _net_hello(vehicle_id: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	_peer_vehicles[sender] = vehicle_id
	var cart: CartPlayer = _remote_carts.get(sender)
	if cart != null:
		cart.set_vehicle_id(vehicle_id)


@rpc("authority", "unreliable")
func _net_props(positions: PackedVector3Array, yaws: PackedFloat32Array) -> void:
	if _host_mode:
		return
	var count: int = mini(_props.size(), positions.size())
	for index in count:
		_prop_targets[index] = [positions[index], yaws[index]]


@rpc("any_peer", "reliable")
func _net_request_push(index: int, direction: Vector3, kick: float) -> void:
	if not _host_mode or index < 0 or index >= _props.size():
		return
	var prop: RigidBody3D = _props[index]
	prop.sleeping = false
	prop.apply_central_impulse(direction * prop.mass * kick + Vector3.UP * prop.mass * kick * 0.85)


# --------------------------------------------------------------------------
# props


func _broadcast_props() -> void:
	if _props.is_empty():
		return
	var positions := PackedVector3Array()
	var yaws := PackedFloat32Array()
	for prop: RigidBody3D in _props:
		positions.append(prop.global_position)
		yaws.append(prop.rotation.y)
	rpc("_net_props", positions, yaws)


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
		prop.rotation.y = lerp_angle(prop.rotation.y, float(data[1]), blend)


func _on_local_push_requested(prop: Node, direction: Vector3, kick: float) -> void:
	if _host_mode:
		return
	var index: int = _props.find(prop as RigidBody3D)
	if index >= 0:
		rpc_id(1, "_net_request_push", index, direction, kick)
