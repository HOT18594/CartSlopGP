extends Node
## Visual check: real driving with handbrake so the skid-mark ribbon paints on
## the dirt road. Saves screenshots to _shots/skid_*.png. Run WINDOWED.

const OUT := "C:/Users/ethan/Downloads/CartSlopGP/_shots"
const RACE := "res://scenes/minigames/grass_race.tscn"

var _race: Node
var _cart: CartPlayer


func _ready() -> void:
	GameSettings.minigame_vehicle = "sedan"
	GameSettings.selected_vehicle = "sedan"
	var packed: PackedScene = load(RACE) as PackedScene
	_race = packed.instantiate()
	add_child(_race)
	for i in 90:
		await get_tree().process_frame
	_cart = _race.get("_cart") as CartPlayer
	# Force the race into RACING so physics runs, then drive with real input.
	_race.set("_phase", 1)
	_race.set("_waiting_for_peers", false)
	_cart.set_physics_process(true)
	var spline: RefCounted = _race.get("_spline")
	var transform: Transform3D = _race.call("_track_transform", 40.0)
	_cart.global_transform = transform
	_cart.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_press("accelerate")
	for i in 60:
		await get_tree().physics_frame
	# Handbrake + steering: a genuine drift the trail must record.
	Input.action_press("handbrake")
	Input.action_press("steer_left")
	for i in 150:
		await get_tree().physics_frame
	Input.action_release("steer_left")
	Input.action_release("handbrake")
	for i in 10:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var chase: Image = get_viewport().get_texture().get_image()
	chase.save_png(OUT + "/skid_chase.png")
	print("SKID_SHOT=", OUT + "/skid_chase.png")
	# Low rear three-quarter view straight at the fresh marks.
	var cam := Camera3D.new()
	var spline_obj: RefCounted = _race.get("_spline")
	var frame: Dictionary = spline_obj.call("sample", 46.0)
	cam.global_transform = Transform3D(Basis(Vector3.UP, float(spline_obj.call("yaw_at", 46.0))),
		(frame["position"] as Vector3) + Vector3(4.0, 1.6, 0.0))
	cam.look_at((frame["position"] as Vector3) + Vector3(0.0, 0.4, 0.0), Vector3.UP)
	add_child(cam)
	cam.current = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var low: Image = get_viewport().get_texture().get_image()
	low.save_png(OUT + "/skid_low.png")
	print("SKID_SHOT=", OUT + "/skid_low.png")
	Input.action_release("accelerate")
	get_tree().quit(0)
