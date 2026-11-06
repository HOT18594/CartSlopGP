extends Node
## Dev-only: pause menu layout capture without leaving the tree paused.

const OUT := "C:/Users/ethan/Downloads/CartSlopGP/_shots/ui_pause.png"


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/ui/pause_menu.tscn") as PackedScene
	var node: Node = packed.instantiate()
	add_child(node)
	node.get_node("Root").call("open")
	get_tree().paused = false
	for i in 26:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUT)
	print("PAUSE_SHOT=", OUT)
	get_tree().quit(0)
