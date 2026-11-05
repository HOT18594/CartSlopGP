extends SceneTree

var _frames: int = 0
var _cart: CharacterBody3D
var _world: Node

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/dev/driving_test.tscn")
	_world = scene.instantiate()
	root.add_child(_world)
	await process_frame
	_cart = _world.get_node("CartPlayer")
	_cart.global_position = Vector3(0, 0.35, 0)
	_cart.rotation = Vector3.ZERO
	Input.action_press("accelerate")

func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames == 108:
		_shot("dev_ramp.png")
	elif _frames == 122:
		Input.action_release("accelerate")
		_cart._reset_cart()
		_cart.global_position = Vector3(45, 2.55, -9.55)
		_cart.rotation = Vector3.ZERO
		_cart.velocity = Vector3.ZERO
	elif _frames == 165:
		_shot("dev_ledge.png")
	elif _frames == 180:
		_cart._reset_cart()
		_cart.global_position = Vector3(49.6, 2.55, -6)
		_cart.rotation = Vector3.ZERO
		_cart.velocity = Vector3.ZERO
	elif _frames == 225:
		_shot("dev_side_ledge.png")
	elif _frames == 240:
		_world.queue_free()
		await process_frame
		quit()
	return false

func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	var path: String = ProjectSettings.globalize_path("res://" + file_name)
	image.save_png(path)
	print("SHOT_SAVED=", path)
