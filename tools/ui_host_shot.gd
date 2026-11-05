extends Node
## Dev-only: render the live host panel with a map selected.

const OUT := "C:/Users/ethan/Downloads/CartSlopGP/_shots/ui_lobby_host.png"


func _ready() -> void:
	Network.is_host = true
	Network.join_code = "ABCDE"
	Network.relay_active = true
	Network.relay_room_code = "ABCDE"
	Network.relay_tunnel_token = "dev"
	Network.relay_base_public = true
	Network.relay_server_host = "cartslop.local"
	Network.session_mode = GameSettings.GAME_MINIGAMES
	GameSettings.set_multiplayer_mode(GameSettings.GAME_MINIGAMES)
	GameSettings.set_selected_minigame("meadow_loop")
	var packed: PackedScene = load("res://scenes/ui/lobby_menu.tscn") as PackedScene
	var node: Node = packed.instantiate()
	add_child(node)
	for i in 24:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUT)
	print("HOST_SHOT=", OUT)
	get_tree().quit(0)
