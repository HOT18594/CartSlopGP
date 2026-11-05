extends CharacterBody3D
## Arcade cart controller for the driving test scene.
##
## Inputs come from the project input map:
## accelerate, brake, steer_left, steer_right, handbrake, reset_cart.

# Driving feel - all values are tunable in the Inspector.
@export var max_speed: float = 16.0 ## Fastest forward speed (m/s).
@export var reverse_speed: float = 6.0 ## Fastest reverse speed (m/s).
@export var acceleration: float = 18.0 ## Speed gained per second while accelerating (m/s^2).
@export var brake_power: float = 24.0 ## Speed removed per second while braking (m/s^2).
@export var friction: float = 8.0 ## Speed lost per second when no input is held (m/s^2).
@export var turn_speed: float = 2.4 ## Steering rate (radians/second).
@export var gravity: float = 20.0 ## Downward acceleration (m/s^2).
@export var mesh_tilt_amount: float = 0.07 ## Visual lean into turns (radians).

var _forward_speed: float = 0.0 ## Signed speed along the cart's nose (+ = forward).
var _spawn_transform: Transform3D = Transform3D.IDENTITY

@onready var _mesh_root: Node3D = $MeshRoot


func _ready() -> void:
	add_to_group("player")
	var spawn_point: Node3D = get_tree().get_first_node_in_group("spawn_point") as Node3D
	if spawn_point != null:
		_spawn_transform = spawn_point.global_transform
	else:
		_spawn_transform = global_transform


func _physics_process(delta: float) -> void:
	var steer_input: float = Input.get_axis("steer_right", "steer_left")
	_update_speed(delta)
	_apply_handbrake(delta)
	_apply_steering(steer_input, delta)
	_set_velocity(delta)
	move_and_slide()
	_apply_mesh_tilt(steer_input, delta)
	if Input.is_action_just_pressed("reset_cart"):
		_reset_cart()


func _update_speed(delta: float) -> void:
	if Input.is_action_pressed("accelerate"):
		_forward_speed = move_toward(_forward_speed, max_speed, acceleration * delta)
	elif Input.is_action_pressed("brake"):
		if _forward_speed > 0.0:
			# Brake first, then reverse once stopped.
			_forward_speed = move_toward(_forward_speed, 0.0, brake_power * delta)
		else:
			_forward_speed = move_toward(_forward_speed, -reverse_speed, acceleration * delta)
	else:
		# No input: roll to a stop.
		_forward_speed = move_toward(_forward_speed, 0.0, friction * delta)


func _apply_handbrake(delta: float) -> void:
	# Extra braking for now; can become a drift later.
	if Input.is_action_pressed("handbrake"):
		_forward_speed = move_toward(_forward_speed, 0.0, brake_power * delta)


func _apply_steering(steer_input: float, delta: float) -> void:
	# A stopped cart cannot turn; steering power builds up with speed and
	# inverts while reversing, like a real car.
	var speed_fraction: float = clampf(absf(_forward_speed) / max_speed, 0.0, 1.0)
	var turn_rate: float = steer_input * turn_speed * minf(speed_fraction * 2.0, 1.0) * signf(_forward_speed)
	rotate_y(turn_rate * delta)


func _set_velocity(delta: float) -> void:
	# Gravity is applied every frame so the cart sticks to ramps and slopes;
	# move_and_slide() cancels it while standing on the floor.
	velocity.y -= gravity * delta
	var forward_direction: Vector3 = -global_transform.basis.z
	velocity.x = forward_direction.x * _forward_speed
	velocity.z = forward_direction.z * _forward_speed


func _apply_mesh_tilt(steer_input: float, delta: float) -> void:
	var speed_fraction: float = clampf(_forward_speed / max_speed, -1.0, 1.0)
	var target_tilt: float = steer_input * mesh_tilt_amount * speed_fraction
	_mesh_root.rotation.z = lerpf(_mesh_root.rotation.z, target_tilt, 5.0 * delta)


func _reset_cart() -> void:
	## Returns the cart to the arena spawn point and zeroes all motion.
	_forward_speed = 0.0
	velocity = Vector3.ZERO
	global_transform = _spawn_transform
	_mesh_root.rotation = Vector3.ZERO
