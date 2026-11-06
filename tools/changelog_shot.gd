extends Node
const OUT := "C:/Users/ethan/Downloads/CartSlopGP/_shots/changelog.png"
func _ready() -> void:
	var node: Node = (load("res://scenes/ui/changelog_panel.tscn") as PackedScene).instantiate()
	add_child(node)
	await get_tree().process_frame
	node.call("open")
	for i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUT)
	print("CHANGELOG_SHOT=", OUT, " pages=", node.get("_pages").size())
	get_tree().quit(0)
