extends Node
const OUT := "C:/Users/ethan/Downloads/CartSlopGP/_shots/lobby_typing.png"
func _ready() -> void:
	var node: Node = (load("res://scenes/ui/lobby_menu.tscn") as PackedScene).instantiate()
	add_child(node)
	for i in 12:
		await get_tree().process_frame
	var input: LineEdit = node.get("_name_input")
	input.grab_focus()
	input.text = "ETHAN"
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUT)
	print("TYPING_SHOT=", OUT)
	get_tree().quit(0)
