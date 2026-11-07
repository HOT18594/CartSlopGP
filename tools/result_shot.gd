extends Node
## Dev-only: renders the Meadow Loop result card so the finish artwork behind it
## can be eyeballed without driving three laps.

const OUT := "C:/Users/ethan/Downloads/CartSlopGP/_shots"
const RACE := "res://scenes/minigames/grass_race.tscn"

var _race: Node


func _ready() -> void:
	GameSettings.minigame_vehicle = "shopping_cart"
	GameSettings.selected_vehicle = "shopping_cart"
	var packed: PackedScene = load(RACE) as PackedScene
	_race = packed.instantiate()
	add_child(_race)
	for i in 90:
		await get_tree().process_frame
	_race.call("_finish")
	for i in 45:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var name: String = "race_result.png"
	image.save_png(OUT + "/" + name)
	print("RESULT_SHOT=", OUT + "/" + name)
	get_tree().quit(0)
