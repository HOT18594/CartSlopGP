extends Node
## Dev-only: render each menu to a PNG so the layout can be inspected.

const OUT_DIR := "C:/Users/ethan/Downloads/CartSlopGP/_shots"
const SCENES: Array[Dictionary] = [
	{"path": "res://scenes/ui/main_menu.tscn", "name": "main"},
	{"path": "res://scenes/ui/play_menu.tscn", "name": "play"},
	{"path": "res://scenes/ui/lobby_menu.tscn", "name": "lobby"},
	{"path": "res://scenes/ui/minigames_menu.tscn", "name": "minigames"},
	{"path": "res://scenes/ui/vehicle_select.tscn", "name": "vehicle"},
	{"path": "res://scenes/ui/settings_menu.tscn", "name": "settings", "open": true},
]

var _index: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_next")


func _next() -> void:
	if _index >= SCENES.size():
		get_tree().quit(0)
		return
	var data: Dictionary = SCENES[_index]
	var packed: PackedScene = load(str(data["path"])) as PackedScene
	if packed == null:
		_index += 1
		call_deferred("_next")
		return
	var node: Node = packed.instantiate()
	add_child(node)
	var cursor: Node = get_node_or_null("/root/CursorController")
	if cursor != null:
		cursor.set("enable_custom_cursor", false)
		cursor.call("set_menu_mode", true)
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	if bool(data.get("open", false)):
		node.call("open")
	for i in 18:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	image.save_png(OUT_DIR + "/ui_" + str(data["name"]) + ".png")
	print("UI_SHOT=", str(data["name"]))
	node.queue_free()
	_index += 1
	for i in 4:
		await get_tree().process_frame
	call_deferred("_next")
