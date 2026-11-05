extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://scenes/dev/driving_test.tscn")
	var world: Node = scene.instantiate()
	root.add_child(world)
	await process_frame
	var cart := world.get_node("CartPlayer") as CartPlayer

	cart.global_position = Vector3(0, 0.3, 2)
	cart.rotation = Vector3.ZERO
	cart.velocity = Vector3.ZERO
	Input.action_press("accelerate")
	var max_slope_pitch: float = -1.0
	var max_collider_pitch: float = -1.0
	var max_weight_pitch: float = -1.0
	var max_y: float = 0.0
	for i in 130:
		await physics_frame
		max_slope_pitch = maxf(max_slope_pitch, cart._slope_pitch)
		max_collider_pitch = maxf(max_collider_pitch, cart._collision_shapes[0].transform.basis.get_euler().x)
		max_weight_pitch = maxf(max_weight_pitch, cart._base_pitch)
		max_y = maxf(max_y, cart.global_position.y)
	Input.action_release("accelerate")
	print("RAMP_MAX_SLOPE_PITCH=", max_slope_pitch)
	print("RAMP_MAX_COLLIDER_PITCH=", max_collider_pitch)
	print("RAMP_MAX_WEIGHT_PITCH=", max_weight_pitch)
	print("RAMP_MAX_HEIGHT=", max_y)
	_check(max_slope_pitch > 0.15, "Ramp lifts the model nose")
	_check(max_collider_pitch > 0.15, "Compound collider follows the ramp")
	_check(max_weight_pitch > 0.015, "Acceleration transfers weight rearward")
	_check(max_y > 1.3, "Slope-aware drive climbs and launches")

	cart._reset_cart()
	await process_frame
	cart.global_position = Vector3(45, 2.55, -9.55)
	cart.rotation = Vector3.ZERO
	cart.velocity = Vector3.ZERO
	var min_ledge_pitch: float = 1.0
	var min_front_support: int = 4
	for i in 60:
		await physics_frame
		min_ledge_pitch = minf(min_ledge_pitch, cart._slope_pitch)
		min_front_support = mini(min_front_support, cart._support_count)
	print("LEDGE_MIN_SLOPE_PITCH=", min_ledge_pitch)
	print("LEDGE_MIN_SUPPORT_COUNT=", min_front_support)
	_check(min_ledge_pitch < -0.45, "Front wheels losing support tips the nose down")
	_check(min_front_support <= 2, "Ledge is detected by wheel support probes")

	cart._reset_cart()
	await process_frame
	cart.global_position = Vector3(49.6, 2.55, -6)
	cart.rotation = Vector3.ZERO
	cart.velocity = Vector3.ZERO
	var min_side_roll: float = 1.0
	for i in 60:
		await physics_frame
		min_side_roll = minf(min_side_roll, cart._slope_roll)
	print("SIDE_LEDGE_MIN_ROLL=", min_side_roll)
	_check(min_side_roll < -0.2, "Losing right-side support rolls the chassis right")

	cart._reset_cart()
	await process_frame
	cart.global_position = Vector3(0, 0.25, -35.5)
	cart.rotation = Vector3.ZERO
	cart.velocity = Vector3.ZERO
	Input.action_press("accelerate")
	var max_impact_kick: float = 0.0
	for i in 80:
		await physics_frame
		max_impact_kick = maxf(max_impact_kick, absf(cart._base_pitch_vel))
	Input.action_release("accelerate")
	print("WALL_FINAL_POSITION=", cart.global_position)
	print("WALL_MAX_PITCH_KICK=", max_impact_kick)
	_check(cart.global_position.z > -39.5, "Compound bumper cannot pass through the wall")
	_check(max_impact_kick > 0.03, "Wall impact produces directional suspension motion")

	cart._reset_cart()
	await process_frame
	var target: RigidBody3D = null
	var best: float = 1e9
	for node in get_nodes_in_group("pushable"):
		var prop := node as RigidBody3D
		if prop == null:
			continue
		var distance: float = prop.global_position.distance_to(cart.global_position)
		if distance < best:
			best = distance
			target = prop
	var start: Vector3 = target.global_position
	cart.global_position = target.global_position + Vector3(0, 0.3, 3.2)
	var direction: Vector3 = target.global_position - cart.global_position
	direction.y = 0.0
	cart.rotation.y = atan2(-direction.x, -direction.z)
	Input.action_press("accelerate")
	var max_prop_spin: float = 0.0
	for i in 75:
		await physics_frame
		max_prop_spin = maxf(max_prop_spin, target.angular_velocity.length())
	Input.action_release("accelerate")
	print("PUSH_MOVED=", target.global_position.distance_to(start))
	print("PUSH_MAX_SPIN=", max_prop_spin)
	_check(target.global_position.distance_to(start) > 0.5, "Pushable collision still transfers momentum")
	_check(max_prop_spin > 0.01, "Off-center prop hits transfer spin")

	cart._reset_cart()
	await process_frame
	Input.action_press("accelerate")
	Input.action_press("boost")
	var max_boost_speed: float = 0.0
	for i in 150:
		await physics_frame
		max_boost_speed = maxf(max_boost_speed, cart.velocity.length())
	Input.action_release("boost")
	Input.action_release("accelerate")
	print("BOOST_SPEED_SEEN=", max_boost_speed)
	_check(max_boost_speed > cart.max_speed, "Boost remains faster than ordinary driving")

	world.queue_free()
	await process_frame
	print("DYNAMICS_TEST_FAILURES=", _failures)
	quit(_failures)

func _check(condition: bool, description: String) -> void:
	print("PASS: " if condition else "FAIL: ", description)
	if not condition:
		_failures += 1
