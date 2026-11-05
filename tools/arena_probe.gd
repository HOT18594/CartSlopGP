extends Node

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	for n in get_tree().get_nodes_in_group("pushable"):
		var b: Node3D = n as Node3D
		if b != null and b.name.to_lower().contains("crate"):
			print("CRATE ", b.name, " pos=", b.global_position, " visible=", b.is_visible_in_tree())
	print("pushable count=", get_tree().get_nodes_in_group("pushable").size())
	get_tree().quit()
