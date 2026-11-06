extends SceneTree
## Dev check: the host collision resolver exchanges momentum.

class FakeCart extends Node3D:
	var velocity: Vector3 = Vector3.ZERO
	func get_collision_velocity() -> Vector3: return velocity
	func get_mass() -> float: return 1000.0
	func apply_vehicle_bump(normal: Vector3, push: float) -> void:
		velocity += normal * push
	func apply_vehicle_impulse(impulse: Vector3) -> void:
		velocity += impulse

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var net: Node = root.get_node("Network")
	net.is_host = true
	net.clear_scene_ready()
	var a := FakeCart.new()
	var b := FakeCart.new()
	root.add_child(a)
	root.add_child(b)
	a.global_position = Vector3.ZERO
	b.global_position = Vector3(1.0, 0.0, 0.0)
	a.velocity = Vector3(5.0, 0.0, 0.0)
	b.velocity = Vector3.ZERO
	net.resolve_car_collisions(a, {1: b})
	print("COLLISION_A=", a.velocity, " COLLISION_B=", b.velocity)
	var ok: bool = a.velocity.x < 5.0 and b.velocity.x > 0.0
	print("CAR_COLLISION: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
