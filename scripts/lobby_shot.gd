extends Node
## Dev-only: host a LAN session and screenshot the live host panel.

const OUT := "C:/Users/ethan/Downloads/CartSlopGP/_shots/lobby_host.png"


func _ready() -> void:
	Network.host_started.connect(_on_hosted)
	Network.host_game("lan")


func _on_hosted(_code: String) -> void:
	var packed: PackedScene = load("res://scenes/ui/lobby_menu.tscn") as PackedScene
	add_child(packed.instantiate())
	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUT)
	print("SHOT=", OUT)
	get_tree().quit()
