extends Node

const CartScene := preload("res://scenes/player/cart_player.tscn")

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)


func _static_box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	body.position = position
	add_child(body)
	return body


func _spawn_cart(vehicle_id: String, position: Vector3) -> CartPlayer:
	var cart := CartScene.instantiate() as CartPlayer
	cart.ai_mode = true
	cart.position = position
	add_child(cart)
	cart.reapply_vehicle(vehicle_id)
	return cart


func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame


func _run() -> void:
	_static_box(Vector3(40.0, 1.0, 160.0), Vector3(0.0, -0.5, -20.0))
	for vehicle_id in ["shopping_cart", "truck"]:
		var cart := _spawn_cart(vehicle_id, Vector3(0.0, 0.08, 30.0))
		cart.set_ai_controls(1.0, 0.0, 0.0)
		await _frames(180)
		var speed: float = Vector2(cart.velocity.x, cart.velocity.z).length()
		_check(speed > 9.0, "%s failed to accelerate: %.2f m/s" % [vehicle_id, speed])
		var yaw_before: float = cart.rotation.y
		cart.set_ai_controls(1.0, 0.0, 1.0)
		await _frames(45)
		var yaw_delta: float = absf(wrapf(cart.rotation.y - yaw_before, -PI, PI))
		var direction_dot: float = Vector3(cart.velocity.x, 0.0, cart.velocity.z).normalized().dot(-cart.global_basis.z)
		_check(yaw_delta > 0.65, "%s has insufficient high-speed steering: %.3f rad" % [vehicle_id, yaw_delta])
		_check(direction_dot > 0.65, "%s slides instead of following a turn: %.3f" % [vehicle_id, direction_dot])
		cart.queue_free()
		await _frames(2)

	var ramp := StaticBody3D.new()
	ramp.collision_layer = 1
	ramp.collision_mask = 0
	var ramp_shape := ConvexPolygonShape3D.new()
	ramp_shape.points = PackedVector3Array([
		Vector3(-4.0, 0.0, 4.0), Vector3(4.0, 0.0, 4.0),
		Vector3(-4.0, 0.0, -4.0), Vector3(4.0, 0.0, -4.0),
		Vector3(-4.0, 2.4, -4.0), Vector3(4.0, 2.4, -4.0),
	])
	var ramp_collision := CollisionShape3D.new()
	ramp_collision.shape = ramp_shape
	ramp.add_child(ramp_collision)
	add_child(ramp)
	for vehicle_id in ["shopping_cart", "truck"]:
		var cart := _spawn_cart(vehicle_id, Vector3(0.0, 0.08, 22.0))
		cart.set_ai_controls(1.0, 0.0, 0.0)
		var launched: bool = false
		var peak_up_speed: float = 0.0
		var air_frames: int = 0
		for index in 300:
			await get_tree().physics_frame
			peak_up_speed = maxf(peak_up_speed, cart.velocity.y)
			if not cart.is_on_floor() and cart.position.z < -3.0:
				launched = true
				air_frames += 1
			if launched and cart.is_on_floor() and air_frames > 8:
				break
		_check(launched, "%s never left the ramp" % vehicle_id)
		_check(peak_up_speed > 3.0, "%s lost its ramp launch: %.2f m/s upward" % [vehicle_id, peak_up_speed])
		_check(air_frames >= 12, "%s jump was not satisfying: %d airborne frames" % [vehicle_id, air_frames])
		_check(cart.position.is_finite() and cart.velocity.is_finite(), "%s physics became invalid" % vehicle_id)
		cart.queue_free()
		await _frames(2)
	print("DRIVING_SMOKE: %s" % ("PASS" if _failures == 0 else "%d failures" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)
