extends Node3D
## Dev check: two carts, real CharacterBody collision, mass-aware recoil.

const CART := preload("res://scenes/player/cart_player.tscn")
var _a: CartPlayer
var _b: CartPlayer


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(shape)
	add_child(floor_body)

	_a = CART.instantiate() as CartPlayer
	add_child(_a)
	_a.global_position = Vector3(0, 0.6, 0)
	_b = CART.instantiate() as CartPlayer
	add_child(_b)
	_b.setup_remote(2)
	_b.set_vehicle_id("sedan")
	# Ghosts have physics disabled, so B never falls to the floor by itself:
	# rest it ON the floor, or a still-airborne A crashes into a floating body
	# and the measurement catches a free fall instead of the impact.
	_b.global_position = Vector3(0, 0.001, -2.0)
	_b.net_position = _b.global_position

	for i in 24:
		await get_tree().physics_frame
	_a.velocity = Vector3(0, 0, -12.0)
	for i in 24:
		await get_tree().physics_frame
	var speed_after: float = _a.velocity.length()
	print("COLLISION_TEST velocity=", _a.velocity, " speed_after=%.2f impact_timer=" % speed_after,
		_a.get("_impact_timer"))
	var ok: bool = speed_after < 10.0
	print("COLLISION_TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
