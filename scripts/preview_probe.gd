extends Node3D
## Dev-only probe: renders the asset preview, saves a screenshot, quits.

const SHOT_PATH := "C:/Users/ethan/AppData/Roaming/AutoClaw-oversea-official/accounts/778bf5d7de6c01371b1d2316f24f7a9b87e644c0c9f0ae7664e0dca12c137262/projects/Default/probe_preview.png"

var _frames: int = 0


func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames == 20:
		_take_screenshot()
	elif _frames == 30:
		print("PROBE_PREVIEW_DONE")
		get_tree().quit()


func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_PATH)
	print("PROBE_SAVED=", SHOT_PATH)
