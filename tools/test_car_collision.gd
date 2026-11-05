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
	_b.global_position = Vector3(0, 0.6, -2.0)
	_b.net_position = _b.global_position

	for i in 4:
		await get_tree().physics_frame
	_a.velocity = Vector3(0, 0, -12.0)
	for i in 24:
		await get_tree().physics_frame
	print("COLLISION_TEST velocity=", _a.velocity, " impact_timer=", _a.get("_impact_timer"))
	get_tree().quit(0)
