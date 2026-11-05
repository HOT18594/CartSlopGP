extends Node
## Dev-only: instantiate a UI scene, optionally open an overlay, screenshot.

const OUT_DIR := "C:/Users/ethan/Downloads/CartSlopGP/_shots"

@export_file("*.tscn") var scene_path: String = "res://scenes/ui/play_menu.tscn"
@export var shot_name: String = "ui_state"
@export var open_node: String = ""

var _frames: int = 0
var _node: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var packed: PackedScene = load(scene_path) as PackedScene
	_node = packed.instantiate()
	add_child(_node)
	if open_node != "":
		var target: Node = _node if open_node == "." else _node.get_node(open_node)
		target.call("open")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 40:
		_shot()


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	image.save_png(OUT_DIR + "/" + shot_name + ".png")
	print("SHOT=", OUT_DIR + "/" + shot_name + ".png")
	get_tree().quit()
