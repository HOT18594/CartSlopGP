extends Node
## Dev-only: screenshot the lobby after loading the online room list.
const OUT := "C:/Users/ethan/Downloads/CartSlopGP/_shots/lobby_browse.png"

func _ready() -> void:
	Network.set_relay_server("192.168.1.22:42777")
	var node: Node = (load("res://scenes/ui/lobby_menu.tscn") as PackedScene).instantiate()
	add_child(node)
	for i in 30:
		await get_tree().process_frame
	node.call("_browse_pi_rooms")
	for i in 120:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUT)
	print("BROWSE_SHOT=", OUT,
		" children=", node.get("_lan_box").get_child_count(),
		" visible=", node.get("_lan_box").visible,
		" panel_size=", node.get_node("Center/Scroll/Panel").size)
	get_tree().quit(0)
