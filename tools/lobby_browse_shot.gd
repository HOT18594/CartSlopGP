extends Node
## Dev-only: screenshot the room-browser popup after loading the online list.
const OUT := "C:/Users/ethan/Downloads/CartSlopGP/_shots/lobby_browse.png"

func _ready() -> void:
	Network.set_relay_server("192.168.1.22:42777")
	var node: Node = (load("res://scenes/ui/lobby_menu.tscn") as PackedScene).instantiate()
	add_child(node)
	for i in 30:
		await get_tree().process_frame
	node.call("_on_browse_online")
	for i in 120:
		await get_tree().process_frame
	var browser: Control = node.get("_browser")
	# Dev shot: show a populated list even when the Pi is unreachable.
	if browser.get("_rooms").is_empty():
		browser.set("_busy", false)
		browser.call("set_rooms", [
			{"name": "ETHAN", "players": 3, "room_code": "ABCDE", "state": "lobby"},
			{"name": "MIKE", "players": 2, "room_code": "K7Q2P", "state": "lobby"},
			{"name": "SARAH", "players": 5, "room_code": "Z9WXM", "state": "lobby"},
			{"name": "BOT RACE", "players": 1, "room_code": "MEAD0", "state": "lobby"},
		])
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUT)
	print("BROWSE_SHOT=", OUT,
		" popup_visible=", browser.visible,
		" rows=", browser.get_node("Center/Panel/Body/ListScroll/List").get_child_count(),
		" hint=", browser.get_node("Center/Panel/Body/StatusLabel").text)
	get_tree().quit(0)
