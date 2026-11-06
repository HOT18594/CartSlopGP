extends Node

const OUT := "C:/Users/ethan/Downloads/CartSlopGP/_shots"
const RACE := "res://scenes/minigames/grass_race.tscn"

var _race: Node
var _cart: Node3D


func _ready() -> void:
	# Keep preview captures on the default cart, independent of a tester's
	# saved vehicle choice.
	GameSettings.minigame_vehicle = "shopping_cart"
	GameSettings.selected_vehicle = "shopping_cart"
	var packed: PackedScene = load(RACE) as PackedScene
	_race = packed.instantiate()
	add_child(_race)
	for i in 90:
		await get_tree().process_frame
	_cart = _race.get("_cart") as Node3D
	var spline: RefCounted = _race.get("_spline")
	var length: float = float(spline.get("total_length"))
	for spot in [0.02, 0.23, 0.27, 0.48, 0.60, 0.67, 0.72]:
		var distance: float = length * float(spot)
		var transform: Transform3D = _race.call("_track_transform", distance)
		_cart.global_transform = transform
		_cart.set("velocity", Vector3.ZERO)
		var rig: Node = _cart.get_node_or_null("CameraArm")
		if rig != null:
			rig.call("reset_camera")
		for i in 30:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var name: String = "race_%02d.png" % int(float(spot) * 100.0)
		image.save_png(OUT + "/" + name)
		print("RACE_SHOT=", OUT + "/" + name)
	get_tree().quit(0)
