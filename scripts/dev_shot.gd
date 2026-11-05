extends Node
## Dev-only screenshot helper for the UI smoke test. Not shipped logic.

const OUT_DIR := "C:/Users/ethan/Downloads/CartSlopGP/_shots"

@export var mode: String = "menu"

var _frames: int = 0
var _cart: CartPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	if mode == "drive":
		_cart = get_tree().get_first_node_in_group("player") as CartPlayer


func _physics_process(_delta: float) -> void:
	_frames += 1
	if mode == "settings":
		if _frames == 20:
			get_parent().get_node("Shot/SettingsMenu").open()
		elif _frames == 30:
			_shot("settings")
			get_tree().quit()
		return
	if mode == "changelog":
		if _frames == 20:
			get_parent().get_node("Shot/ChangelogPanel").open()
		elif _frames == 32:
			_shot("changelog")
			get_tree().quit()
		return
	if mode == "pause":
		if _frames == 10:
			_send_action("pause")
		elif _frames == 35:
			_shot("pause_esc")
			print("PAUSED=", get_tree().paused)
		elif _frames == 45:
			_send_action("pause")
		elif _frames == 70:
			print("PAUSED=", get_tree().paused)
			_shot("pause_closed")
			get_tree().quit()
		return
	if mode == "font":
		if _frames == 20:
			_shot("font_test")
			get_tree().quit()
		return
	if mode == "vehicle":
		var ui: Node = get_parent().get_node("Shot")
		if _frames == 14:
			_shot("vehicle_cart")
		elif _frames == 20:
			ui.call("_step", 1)
		elif _frames == 34:
			_shot("vehicle_sedan")
		elif _frames == 40:
			ui.call("_step", 4)
		elif _frames == 54:
			_shot("vehicle_truck")
			get_tree().quit()
		return
	if mode == "arena":
		if _frames == 2:
			var cam := Camera3D.new()
			cam.fov = 55.0
			get_parent().add_child(cam)
			cam.look_at_from_position(Vector3(0, 150, 118), Vector3(0, 0, -6), Vector3.UP)
			cam.current = true
		elif _frames == 40:
			_shot("arena")
			get_tree().quit()
		return
	if mode == "pad":
		if _frames == 20:
			_shot("pad")
			get_tree().quit()
		return
	if mode == "play":
		if _frames == 30:
			_shot("play")
			get_tree().quit()
		return
	if mode == "menu":
		if _frames == 30:
			_shot("menu")
			get_tree().quit()
		return
	if _frames == 4:
		Input.action_press("accelerate")
	elif _frames == 26:
		_shot("drive_start")
	elif _frames == 72:
		_shot("cones")
	elif _frames == 100:
		print("POS100 z=", _cart.global_position.z, " y=", _cart.global_position.y, " speed=", _cart.velocity.length())
	elif _frames == 140:
		print("POS140 z=", _cart.global_position.z, " y=", _cart.global_position.y, " speed=", _cart.velocity.length())
	elif _frames == 110:
		Input.action_press("handbrake")
		Input.action_press("steer_right")
	elif _frames == 130:
		print("STATE=", _cart.current_state_name, " drift=", _cart.is_drifting, " speed=", _cart.velocity.length())
		_shot("drift_a")
	elif _frames == 150:
		print("STATE=", _cart.current_state_name, " drift=", _cart.is_drifting, " speed=", _cart.velocity.length())
		_shot("drift_b")
	elif _frames == 100:
		var airborne: int = 0
		var moved: int = 0
		for node in get_tree().get_nodes_in_group("pushable"):
			var body: RigidBody3D = node as RigidBody3D
			if body == null:
				continue
			if absf(body.linear_velocity.y) > 0.4 or body.global_position.y > 0.35:
				airborne += 1
			if body.linear_velocity.length() > 0.4:
				moved += 1
		print("PROPS airborne=", airborne, " moving=", moved, " cart_speed=", _cart.velocity.length())
	elif _frames == 170:
		Input.action_release("handbrake")
		Input.action_release("steer_right")
		_shot("drift_c")
	elif _frames == 230:
		print("FAST speed=", _cart.velocity.length())
		_shot("drive_fast")
		get_tree().quit()


func _send_action(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _ready_probe() -> void:
	pass


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUT_DIR + "/" + name + ".png")
	print("SHOT=", OUT_DIR + "/" + name + ".png")
