extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	get_window().size = Vector2i(1280, 720)
	var scene_path: String = OS.get_environment("CART_CAPTURE_SCENE")
	if scene_path.is_empty():
		scene_path = "res://scenes/ui/hud.tscn"
	var scene: Node = load(scene_path).instantiate()
	add_child(scene)
	if scene is CanvasItem:
		(scene as CanvasItem).visible = true
	if scene_path.ends_with("boost_pad.tscn"):
		var camera := Camera3D.new()
		add_child(camera)
		camera.position = Vector3(5.0, 7.0, 8.0)
		camera.look_at(Vector3.ZERO)
		camera.current = true
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
		add_child(light)
	if scene_path.ends_with("hud.tscn"):
		scene.set_race_position(2, 6)
		scene.set_lap(2, 3)
		scene.set_race_time(83.42)
		scene.set_best_lap(41.8)
		var entries: Array[Dictionary] = []
		var names: Array[String] = ["MIXTAPE", "YOU", "BASKETCASE", "VAN GO", "DUMPSTAR", "CARTOON"]
		for index in 6:
			entries.append({"name": names[index], "progress": 600.0 - index * 18.0,
				"local": index == 1, "color": Color("45b6f0")})
		scene.set_standings(entries)
	for index in 12:
		await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	var output: String = OS.get_environment("CART_CAPTURE_OUTPUT")
	if output.is_empty():
		output = "res://.godot/ui_capture.png"
	var error: Error = image.save_png(output)
	print("UI_CAPTURE: %s (%dx%d), error=%d" % [output, image.get_width(), image.get_height(), error])
	get_tree().quit(0 if error == OK else 1)
