extends Node3D
## Dev-only probe: drive, drift, reset, then a fast straight - screenshots + prints.

const SHOT_DRIFT := "C:/Users/ethan/AppData/Roaming/AutoClaw-oversea-official/accounts/778bf5d7de6c01371b1d2316f24f7a9b87e644c0c9f0ae7664e0dca12c137262/projects/Default/probe_driving.png"
const SHOT_RESET := "C:/Users/ethan/AppData/Roaming/AutoClaw-oversea-official/accounts/778bf5d7de6c01371b1d2316f24f7a9b87e644c0c9f0ae7664e0dca12c137262/projects/Default/probe_reset.png"
const SHOT_FAST := "C:/Users/ethan/AppData/Roaming/AutoClaw-oversea-official/accounts/778bf5d7de6c01371b1d2316f24f7a9b87e644c0c9f0ae7664e0dca12c137262/projects/Default/probe_fast.png"

var _frames: int = 0
var _start_pos: Vector3

@onready var _cart: CharacterBody3D = get_tree().get_first_node_in_group("player") as CharacterBody3D


func _ready() -> void:
	if _cart == null:
		push_error("Probe found no cart in group 'player'.")
		get_tree().quit(1)


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames == 5:
		_start_pos = _cart.global_position
		Input.action_press("accelerate")
	elif _frames == 45:
		Input.action_press("handbrake")
		Input.action_press("steer_left")
	elif _frames == 70:
		_take_screenshot(SHOT_DRIFT)
	elif _frames == 76:
		var player := _cart as CartPlayer
		var feedback := get_tree().get_first_node_in_group("cart_feedback") as CartFeedback
		print("PROBE_START=", _start_pos)
		print("PROBE_NOW=", _cart.global_position)
		print("PROBE_SPEED=", _cart.velocity.length())
		if player != null:
			print("PROBE_DRIFTING=", player.is_drifting)
		if feedback != null:
			print("PROBE_DUST=", feedback.dust_active)
			print("PROBE_AUDIO_ENGINE_PLAYING=", feedback.get_node("EngineAudio").playing)
		Input.action_release("handbrake")
		Input.action_release("steer_left")
		Input.action_release("accelerate")
		Input.action_press("reset_cart")
	elif _frames == 79:
		Input.action_release("reset_cart")
	elif _frames == 84:
		print("PROBE_RESET_POS=", _cart.global_position)
		_take_screenshot(SHOT_RESET)
		Input.action_press("accelerate")
	elif _frames == 190:
		var feedback := get_tree().get_first_node_in_group("cart_feedback") as CartFeedback
		print("PROBE_FAST_SPEED=", _cart.velocity.length())
		print("PROBE_FAST_POS=", _cart.global_position)
		if feedback != null:
			print("PROBE_FAST_DUST=", feedback.dust_active)
			print("PROBE_FAST_SPEEDFX=", feedback.speed_feedback_active)
		_take_screenshot(SHOT_FAST)
	elif _frames == 196:
		Input.action_release("accelerate")
	elif _frames == 202:
		print("PROBE_DONE")
		get_tree().quit()


func _take_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(path)
	print("PROBE_SAVED=", path)
