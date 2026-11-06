extends Node

const OUT := "C:/Users/ethan/Downloads/CartSlopGP/_shots/loading.png"


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/ui/scene_loader.tscn") as PackedScene
	var node: Node = packed.instantiate()
	add_child(node)
	node.show()
	var ui: Node = node.get_node("UI")
	ui.call("set_progress", 0.62)
	ui.get_node("Title").text = "LOADING MEADOW LOOP"
	ui.get_node("Message").text = "Building the forest..."
	ui.get_node("Percent").text = "62%"
	for i in 25:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUT)
	print("LOADING_SHOT=", OUT)
	get_tree().quit(0)
