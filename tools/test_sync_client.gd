extends Node
## Boot stub: moves the real test driver under /root so it SURVIVES the scene
## change that the host's start message triggers on this client.


func _ready() -> void:
	var driver: Node = (load("res://tools/test_sync_client_driver.gd") as GDScript).new()
	driver.name = "SyncClientDriver"
	get_tree().root.add_child.call_deferred(driver)
