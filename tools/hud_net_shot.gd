extends Node
const OUT := "C:/Users/ethan/Downloads/CartSlopGP/_shots/hud_net.png"
func _ready() -> void:
	Network.is_host = true
	var hud: Node = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUT)
	print("HUD_NET_SHOT=", OUT)
	get_tree().quit(0)
