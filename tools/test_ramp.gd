extends Node

const RACE := "res://scenes/minigames/grass_race.tscn"

var _race: Node


func _ready() -> void:
	var packed: PackedScene = load(RACE) as PackedScene
	_race = packed.instantiate()
	add_child(_race)
	for i in 90:
		await get_tree().process_frame
	var cart: CharacterBody3D = _race.get("_cart") as CharacterBody3D
	var spline: RefCounted = _race.get("_spline")
	var ramps: Array = _race.get("_ramp_distances")
	if ramps.is_empty():
		print("RAMP TEST FAIL: no ramps")
		get_tree().quit(1)
		return
	var start: float = float(ramps[0]) - 14.0
	cart.global_transform = _race.call("_track_transform", start)
	cart.set("velocity", Vector3.ZERO)
	cart.set_physics_process(true)
	_race.set("_phase", 1)
	_race.set("_go_shown", true)
	Input.action_press("accelerate")
	var max_y: float = cart.global_position.y
	var max_speed: float = 0.0
	for i in 220:
		await get_tree().physics_frame
		max_y = maxf(max_y, cart.global_position.y)
		max_speed = maxf(max_speed, cart.velocity.length())
	Input.action_release("accelerate")
	var info: Dictionary = spline.call("closest", cart.global_position)
	print("RAMP_TEST max_y=%.2f max_speed=%.2f end_s=%.1f ramp=%.1f" % [
		max_y, max_speed, float(info["s"]), float(ramps[0])])
	var ok: bool = max_y > 0.65
	print("RAMP TEST: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
