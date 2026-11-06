extends Node
## Boot stub: moves the real test driver under /root so it SURVIVES the scene
## change that Network.start_game() triggers (the current scene is freed).


func _ready() -> void:
	var driver: Node = (load("res://tools/test_sync_host_driver.gd") as GDScript).new()
	driver.name = "SyncHostDriver"
	get_tree().root.add_child.call_deferred(driver)
